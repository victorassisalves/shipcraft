//! The rules a commit keeps while a lock is open (rules 2 to 4), shared by the
//! hook (`shipcraft check`) and the CI (`shipcraft ci`).

use crate::config::{self, CONFIG_FILE};
use crate::git::{text, Repo, Snapshot};
use crate::init::LEFTHOOK_FILES;
use crate::init_tool::{HUSKY, PRE_COMMIT_CONFIG};
use crate::junit::{Outcome, Report};
use crate::lock::{Lock, LockFiles, LOCK_DIR};
use crate::refusal::{failed, refuse, short_list, Result};
use crate::suite::{FailedCheck, Missing};
use std::collections::BTreeSet;

const RESTORE_LOCK: &str =
    "restore the lock as shipcraft left it; it closes automatically in the commit where locked cases pass";

/// Item 33: in the hook, the "Como seguir" of a lock refusal ends with the
/// command that restores the lock from HEAD, when HEAD holds it and its name
/// is one `shipcraft red` writes; otherwise restoring could delete its only copy.
fn restore(how: &str, path: &str, in_head: bool) -> String {
    let name = path.strip_prefix(LOCK_DIR).and_then(|rest| rest.strip_prefix('/')).unwrap_or_default();
    let safe = !name.is_empty() && name.chars().all(|c| c.is_ascii_alphanumeric() || "._-".contains(c));
    if !(in_head && safe) {
        return how.to_string();
    }
    format!("{how}; to restore it: `git restore --staged --worktree --source=HEAD -- ':/{path}'`")
}

/// What a commit did to one lock file, judged against its parent(s).
pub enum Change {
    /// The same bytes as in a parent.
    Kept(Lock),
    /// A new open lock: this is the RED commit.
    Opened(Lock),
    /// An open lock that shipcraft closed: this commit claims the GREEN.
    Closed(Lock),
    /// Gone. Allowed only for a lock that was already closed.
    Removed,
    /// Item 159: an open lock rewritten as its abandoned form (a replace
    /// commit); it binds nothing.
    Abandoned,
}

impl Change {
    /// The lock whose contract binds the commit, if any.
    pub fn binding(&self) -> Option<&Lock> {
        match self {
            Change::Kept(lock) if lock.is_open() => Some(lock),
            Change::Opened(lock) | Change::Closed(lock) => Some(lock),
            _ => None,
        }
    }
}

/// The locks whose contract binds the commit, with their paths and changes.
pub fn bindings(changes: &[(String, Change)]) -> impl Iterator<Item = (&str, &Change, &Lock)> {
    changes.iter().filter_map(|(path, change)| change.binding().map(|lock| (path.as_str(), change, lock)))
}

/// Item 46: the paths a commit with one parent changes, asked for only when a
/// lock goes from open to open (a redo commit); None for a merge.
pub type Changed<'a> = Option<&'a dyn Fn() -> Result<Vec<String>>>;

/// Judges every lock file of `now` against the same file in `parents`.
/// Refuses a deleted open lock and any lock not written by shipcraft. In the hook
/// (`hook`), `parents` is HEAD alone.
pub fn judge_locks(
    parents: &[LockFiles],
    now: &LockFiles,
    place: &str,
    hook: bool,
    changed: Changed,
) -> Result<Vec<(String, Change)>> {
    judge_locks_admitting(parents, now, place, hook, false, changed)
}

/// As `judge_locks`; with `admit_closed`, a new lock that arrives already
/// closed is kept instead of refused (item 42: a squash the gate proved).
pub fn judge_locks_admitting(
    parents: &[LockFiles],
    now: &LockFiles,
    place: &str,
    hook: bool,
    admit_closed: bool,
    changed: Changed,
) -> Result<Vec<(String, Change)>> {
    // A merge never counts as a redo: a lock it carries equals a parent's.
    let changed = changed.filter(|_| parents.len() == 1);
    let paths: BTreeSet<&String> = parents.iter().flat_map(|locks| locks.keys()).chain(now.keys()).collect();
    let changes = paths
        .into_iter()
        .map(|path| Ok((path.clone(), judge(path, parents, now.get(path), place, hook, admit_closed, changed)?)))
        .collect::<Result<Vec<_>>>()?;
    replace_alone(&changes, parents, place)?;
    Ok(changes)
}

/// Item 159: a commit that abandons a lock abandons exactly one and opens
/// exactly one new lock (a path no parent has).
fn replace_alone(changes: &[(String, Change)], parents: &[LockFiles], place: &str) -> Result<()> {
    let abandoned: Vec<&String> =
        changes.iter().filter(|(_, change)| matches!(change, Change::Abandoned)).map(|(path, _)| path).collect();
    if abandoned.is_empty() {
        return Ok(());
    }
    let new = |path: &String| parents.iter().all(|locks| !locks.contains_key(path));
    let opened = changes.iter().filter(|(path, change)| matches!(change, Change::Opened(_)) && new(path)).count();
    if abandoned.len() == 1 && opened == 1 {
        return Ok(());
    }
    refuse(
        "replace-alone",
        format!(
            "lock(s) abandoned {place}: {}, with {opened} new lock(s) opened; a replace commit abandons one lock and opens one",
            short_list(&abandoned)
        ),
        "a replace commit closes one RED's lock as abandoned and opens the RED that replaces it, in the same commit",
        "run `shipcraft red --replace --reason <text>` and commit both locks it names, with the tests and stubs, in one commit",
    )
}

/// Item 159: the lock a replace commit abandons, with its parent's open form.
pub fn abandoned_lock<'a>(changes: &'a [(String, Change)], parent: &'a LockFiles) -> Option<(&'a str, Lock)> {
    changes.iter().find_map(|(path, change)| match change {
        Change::Abandoned => parent.get(path).and_then(|bytes| Lock::parse(bytes)).map(|old| (path.as_str(), old)),
        _ => None,
    })
}

/// Item 159: a replace commit passes the no-GREEN rule read from its one
/// parent (`parent`); none for a commit that abandons nothing.
pub fn check_replace(repo: &Repo, parent: &str, changes: &[(String, Change)], parent_locks: &LockFiles) -> Result<()> {
    match abandoned_lock(changes, parent_locks) {
        Some((path, old)) => no_green(repo, parent, path, &old),
        None => Ok(()),
    }
}

/// Item 159, point 1's no-GREEN rule: R is the newest commit of `from`'s
/// first-parent line whose diff against its first parent (or the empty tree)
/// adds `path`; every commit after R up to `from`, oldest first, has one
/// parent and is a redo of the lock at `path` or a Markdown commit. A merge,
/// any other commit, or no R refuses `replace-after-green`; a shallow
/// boundary reached before R, or a failed git read, is an error.
pub fn no_green(repo: &Repo, from: &str, path: &str, open: &Lock) -> Result<()> {
    let shallow_file = repo.root().join(repo.text(&["rev-parse", "--git-path", "shallow"])?);
    let shallow = match std::fs::read_to_string(&shallow_file) {
        Ok(text) => text.lines().map(str::to_string).collect(),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => BTreeSet::new(),
        Err(e) => return Err(failed(format!("read {}: {e}", shallow_file.display()))),
    };
    // Each commit after R, newest first, with its parents and raw diff.
    let mut after = Vec::new();
    let mut commit = from.to_string();
    let found = loop {
        let parents = repo.parents(&commit)?;
        if parents.is_empty() && shallow.contains(&commit) {
            return Err(failed(format!(
                "commit {commit} is a shallow boundary: the RED of lock {path} is beyond the history this clone has (git fetch --unshallow)"
            )));
        }
        let raw = match parents.first() {
            Some(first) => repo.run(&["diff-tree", "-r", "-z", "--raw", "--no-renames", first, &commit])?,
            None => {
                repo.run(&["diff-tree", "-r", "-z", "--raw", "--no-renames", "--no-commit-id", "--root", &commit])?
            }
        };
        let entries = raw_entries(&raw)?;
        if entries.iter().any(|e| e.status == "A" && e.path == path) {
            break true;
        }
        let next = parents.first().cloned();
        after.push((commit, parents, entries));
        match next {
            Some(next) => commit = next,
            None => break false,
        }
    };
    let neither = |what: String| {
        refuse(
            "replace-after-green",
            format!("{what}: it is neither a redo of lock {path} nor a commit that changes only Markdown files"),
            "once a GREEN committed code against this lock, a new contract written after it may fit that code",
            "repair the tests with `shipcraft red --redo`, which keeps every case, or open the new RED on a new branch from the base",
        )
    };
    if !found {
        return neither(format!("no commit on HEAD's first-parent line adds lock {path}"));
    }
    for (commit, parents, entries) in after.iter().rev() {
        let [parent] = parents.as_slice() else {
            return neither(format!("commit {commit} after the RED is a merge"));
        };
        if !(markdown(entries, open) || is_redo(repo, parent, commit, path)?) {
            return neither(format!("commit {commit} after the RED"));
        }
    }
    Ok(())
}

/// One entry of `git diff-tree -r -z --raw --no-renames`.
struct RawEntry {
    old_mode: String,
    new_mode: String,
    status: String,
    path: String,
}

fn raw_entries(raw: &[u8]) -> Result<Vec<RawEntry>> {
    let bad = || failed("could not read `git diff-tree --raw` output");
    let mut tokens = raw.split(|b| *b == 0);
    let mut entries = Vec::new();
    while let Some(meta) = tokens.next() {
        if meta.is_empty() {
            continue;
        }
        let meta = text(meta);
        let fields: Vec<&str> = meta.strip_prefix(':').ok_or_else(bad)?.split(' ').collect();
        let [old_mode, new_mode, _, _, status] = fields[..] else { return Err(bad()) };
        let path = text(tokens.next().ok_or_else(bad)?);
        entries.push(RawEntry { old_mode: old_mode.into(), new_mode: new_mode.into(), status: status.into(), path });
    }
    Ok(entries)
}

/// Item 159: a Markdown commit: every path ends in `.md`, is not a file the
/// open lock protects, and each side present is a regular file.
fn markdown(entries: &[RawEntry], open: &Lock) -> bool {
    let regular = |mode: &str| mode == "000000" || mode == "100644" || mode == "100755";
    entries.iter().all(|e| {
        e.path.ends_with(".md") && !open.files.contains_key(&e.path) && regular(&e.old_mode) && regular(&e.new_mode)
    })
}

/// Item 159: `commit` rewrites the lock at `path` from open to open and
/// passes item 46's redo-commit rule against `parent`.
fn is_redo(repo: &Repo, parent: &str, commit: &str, path: &str) -> Result<bool> {
    let read = |rev: &str| -> Result<Option<Lock>> {
        Ok(repo.read(&Snapshot::Commit(rev.to_string()), path)?.and_then(|bytes| Lock::parse(&bytes)))
    };
    let (Some(old), Some(new)) = (read(parent)?, read(commit)?) else { return Ok(false) };
    if !(old.is_open() && new.is_open()) || old == new {
        return Ok(false);
    }
    let changed = changed_paths(repo, parent, &Snapshot::Commit(commit.to_string()))?;
    Ok(redo_fault(path, &old, &new, &changed).is_none())
}

/// Item 46: the paths `snapshot` changes against `parent`, both sides of a
/// rename, mode and type changes included.
pub fn changed_paths(repo: &Repo, parent: &str, snapshot: &Snapshot) -> Result<Vec<String>> {
    let out = match snapshot {
        Snapshot::Commit(commit) => {
            repo.run(&["diff-tree", "-r", "--name-only", "--no-renames", "-z", parent, commit])?
        }
        _ => repo.run(&["diff-index", "--cached", "--name-only", "--no-renames", "-z", parent])?,
    };
    Ok(out.split(|b| *b == 0).filter(|p| !p.is_empty()).map(text).collect())
}

/// Item 42: the locks of `now` that no parent has and that arrive closed.
pub fn arrive_closed(parents: &[LockFiles], now: &LockFiles) -> bool {
    now.iter().any(|(path, bytes)| {
        parents.iter().all(|locks| !locks.contains_key(path)) && Lock::parse(bytes).is_some_and(|l| !l.is_open())
    })
}

fn judge(
    path: &str,
    parents: &[LockFiles],
    now: Option<&Vec<u8>>,
    place: &str,
    hook: bool,
    admit_closed: bool,
    changed: Changed,
) -> Result<Change> {
    let before: Vec<&Vec<u8>> = parents.iter().filter_map(|locks| locks.get(path)).collect();
    let how = restore(RESTORE_LOCK, path, hook && !before.is_empty());
    let Some(bytes) = now else {
        let was_open = before.iter().any(|bytes| Lock::parse(bytes).is_none_or(|lock| lock.is_open()));
        if was_open {
            return refuse(
                "lock-deleted",
                format!("open lock {path} was deleted {place}"),
                "the lock is the RED contract; deleting it discards the contract without fulfilling it",
                how,
            );
        }
        return Ok(Change::Removed);
    };
    let edited = || {
        refuse(
            "lock-edited",
            format!("lock {path} was edited outside shipcraft {place}"),
            "only shipcraft changes the lock: `shipcraft red` opens it and the green commit closes it; editing it manually silently changes the contract",
            how.as_str(),
        )
    };
    let Some(lock) = Lock::parse(bytes) else { return edited() };
    // Item 43: the seal does not depend on whitespace or key order, so a lock
    // that reads the same as a parent's is kept, whatever its presentation.
    if before.contains(&bytes) || before.iter().filter_map(|old| Lock::parse(old)).any(|old| old == lock) {
        return Ok(Change::Kept(lock));
    }
    if before.is_empty() && lock.is_open() {
        return Ok(Change::Opened(lock));
    }
    if before.is_empty() && admit_closed {
        return Ok(Change::Kept(lock));
    }
    // Item 46: an open lock rewritten as another open lock in a commit with
    // one parent is a redo commit; once its paths pass, it is judged as a RED.
    let open_parent = before.iter().filter_map(|bytes| Lock::parse(bytes)).find(Lock::is_open);
    // Item 159: in a commit with one parent, its abandoned form.
    if let (Some(_), Some(old)) = (changed, &open_parent) {
        if lock.abandons(old) {
            return Ok(Change::Abandoned);
        }
    }
    if let (Some(changed), Some(old), true) = (changed, &open_parent, lock.is_open()) {
        return redo(path, old, lock, changed()?, place);
    }
    let closes_a_parent =
        before.iter().filter_map(|bytes| Lock::parse(bytes)).any(|old| old.is_open() && old.closed() == lock);
    if closes_a_parent {
        Ok(Change::Closed(lock))
    } else {
        edited()
    }
}

/// Item 46: a redo commit keeps every case of the parent's lock and changes
/// only the lock and files one of the two locks protects, never the config nor
/// a hook integration file.
fn redo(path: &str, old: &Lock, lock: Lock, changed: Vec<String>, place: &str) -> Result<Change> {
    match redo_fault(path, old, &lock, &changed) {
        None => Ok(Change::Opened(lock)),
        Some(RedoFault::Dropped(dropped)) => refuse(
            "redo-drops-case",
            format!("the redo of lock {path} {place} drops case(s) of the open lock: {}", short_list(&dropped)),
            "a redo repairs the RED's tests and keeps its contract: every case it locked stays locked",
            "keep every case of the open lock and rewrite the lock with `shipcraft red --redo`; a repair that drops or renames a case means rewriting the branch's history",
        ),
        Some(RedoFault::Mixed(mixed)) => refuse(
            "redo-mixed",
            format!("the redo of lock {path} {place} also changes: {}", short_list(&mixed)),
            "a redo commit repairs only the RED's tests: product code, the config or a hook integration file in it would change the contract unjudged",
            "commit only the repaired tests and the lock `shipcraft red --redo` wrote; make the other changes in a commit of their own",
        ),
    }
}

/// Why a rewrite of an open lock as another open lock is not a redo commit.
enum RedoFault<'a> {
    /// Cases of the parent's lock the new lock drops.
    Dropped(Vec<&'a String>),
    /// Paths that are neither the lock nor files a lock protects, or are the
    /// config or a hook integration file.
    Mixed(Vec<&'a String>),
}

/// Item 46's redo-commit rule (shared by item 159's no-GREEN rule): every
/// case kept, only the lock and files either lock protects changed, never
/// the config nor a hook integration file.
fn redo_fault<'a>(path: &str, old: &'a Lock, lock: &Lock, changed: &'a [String]) -> Option<RedoFault<'a>> {
    let dropped: Vec<&String> = old.cases.iter().filter(|case| !lock.cases.contains(case)).collect();
    if !dropped.is_empty() {
        return Some(RedoFault::Dropped(dropped));
    }
    let hooks: Vec<String> = hook_files().collect();
    let mixed: Vec<&String> = changed
        .iter()
        .filter(|file| {
            let protected = file.as_str() == path || old.files.contains_key(*file) || lock.files.contains_key(*file);
            !protected || file.as_str() == CONFIG_FILE || hooks.contains(file)
        })
        .collect();
    (!mixed.is_empty()).then_some(RedoFault::Mixed(mixed))
}

/// The hook integration files (items 15c.2, 15c.6 and 25.4): the lefthook
/// file and its local variants, the husky's and the pre-commit's.
fn hook_files() -> impl Iterator<Item = String> {
    let names = LEFTHOOK_FILES.iter().flat_map(|f| [f.to_string(), f.replacen("lefthook", "lefthook-local", 1)]);
    names.chain(HUSKY.map(|(f, _)| f.to_string())).chain([PRE_COMMIT_CONFIG.to_string()])
}

/// Rule 4, files: every file the lock holds is in the snapshot, unchanged.
pub fn check_files(repo: &Repo, snapshot: &Snapshot, lock_path: &str, lock: &Lock) -> Result<()> {
    let place = snapshot.describe();
    for (file, hash) in &lock.files {
        let Some(bytes) = repo.read(snapshot, file)? else {
            return refuse(
                "locked-file-deleted",
                format!("locked file {file} was deleted {place}"),
                "RED is the GREEN contract; deleting the test or config deletes the contract",
                format!("restore {file} as it was at RED and make the code pass it"),
            );
        };
        if lock.digest(&bytes) == *hash {
            continue;
        }
        if file == CONFIG_FILE {
            return refuse(
                "config-changed",
                format!("{CONFIG_FILE} changed {place} with lock {lock_path} open"),
                "the config decides how the suite runs; changing it during GREEN changes the judge mid-game",
                format!("undo the change in {CONFIG_FILE}; if needed, make it after the cycle closes"),
            );
        }
        return refuse(
            "test-changed",
            format!("locked test {file} changed after RED ({place})"),
            "RED is the contract: GREEN changes the code, not the test that judges it",
            format!("undo the change in {file}; if the test looks wrong, stop and tell the RED author"),
        );
    }
    Ok(())
}

/// Items 15c.2 and 15c.6: with the lock open in a parent, the lefthook file and
/// its local variants keep the bytes of a parent; creating, changing or
/// removing one is refused, as for `.shipcraft.toml`: it decides what the hook runs.
/// So are the husky's and the pre-commit's files of the integration (25.4).
pub fn check_lefthook(repo: &Repo, parents: &[Snapshot], snapshot: &Snapshot, lock_path: &str) -> Result<()> {
    for file in hook_files() {
        let now = repo.read(snapshot, &file)?;
        let before = parents.iter().map(|p| repo.read(p, &file)).collect::<Result<Vec<_>>>()?;
        if before.contains(&now) {
            continue;
        }
        let done = match (&now, before.iter().all(Option::is_none)) {
            (None, _) => "was deleted",
            (_, true) => "was created",
            _ => "changed",
        };
        return refuse(
            "hook-config-changed",
            format!("hook integration file {file} {done} {} with lock {lock_path} open", snapshot.describe()),
            "it decides what the hook runs, including `shipcraft check`; changing it during GREEN changes the judge mid-game",
            format!("undo the change in {file}; if needed, make it after the cycle closes"),
        );
    }
    Ok(())
}

/// Rule 4, report: every required case ran, and none was skipped. A missing
/// case of a suite in `comando` (`filtra = "comando"`) recalls `SHIPCRAFT_CASES`;
/// one of a suite the judging config does not have names that cause (item 59).
fn check_cases_ran(
    report: &Report,
    lock_path: &str,
    required: &[String],
    comando: &[String],
    suites: Option<&Suites>,
) -> Result<()> {
    let with = |wanted: Option<Outcome>| -> Vec<&String> {
        required.iter().filter(|case| report.outcome(case) == wanted).collect()
    };
    let missing = with(None);
    if let Some(suites) = suites {
        absent_suites(lock_path, &missing, suites)?;
    }
    if !missing.is_empty() {
        return refuse(
            "case-missing",
            format!("case(s) from lock {lock_path} are missing from the report: {}", short_list(&missing)),
            "every locked case runs until the cycle closes; a case missing from the run proves nothing",
            if missing.iter().any(|case| comando.iter().any(|own| case.starts_with(own.as_str()))) {
                "the command filters by case: check that it selects every case in SHIPCRAFT_CASES; restore filters and runner configuration to the RED state without excluding any locked case"
            } else {
                "restore filters and runner configuration to the RED state without excluding any locked case"
            },
        );
    }
    let skipped = with(Some(Outcome::Skipped));
    if !skipped.is_empty() {
        return refuse(
            "case-skipped",
            format!("case(s) from lock {lock_path} were skipped: {}", short_list(&skipped)),
            "a skipped test proves nothing; skipping RED fakes GREEN",
            "remove the skip from the test or runner configuration, and make the code pass",
        );
    }
    Ok(())
}

/// Item 59: the suite names of the commit being checked (`lock`) and of the
/// config the CI judges with (`judged`).
pub struct Suites {
    pub lock: BTreeSet<String>,
    pub judged: BTreeSet<String>,
}

/// Item 59: missing cases of a suite of the commit's config that the judging
/// config does not have refuse with that cause, before today's text.
fn absent_suites(lock_path: &str, missing: &[&String], suites: &Suites) -> Result<()> {
    let of_absent: Vec<(&String, &String)> = missing
        .iter()
        .filter_map(|case| config::owner(case, &suites.lock).map(|name| (*case, name)))
        .filter(|(_, name)| !suites.judged.contains(*name))
        .collect();
    if of_absent.is_empty() {
        return Ok(());
    }
    let names: Vec<&String> = of_absent.iter().map(|(_, name)| *name).collect::<BTreeSet<_>>().into_iter().collect();
    let cases = of_absent.iter().map(|(case, _)| *case).collect::<BTreeSet<_>>().len();
    refuse(
        "case-missing",
        format!(
            "case(s) from lock {lock_path} belong to suite(s) that the .shipcraft.toml CI judges with does not have: {} ({cases} case(s))",
            short_list(&names)
        ),
        "CI runs the suites of the config it judges with, the base's for a PR, so a suite that is only in this branch's config does not run",
        "if the suite is new in this branch, bring the `[[suite]]` entry to the base in a PR of its own, with the package and at least one passing test (or a runner set to pass with no tests), so the base can run it; merge it, then rebase this branch and run `shipcraft ci` again",
    )
}

/// What the suite says about a lock that binds the commit.
pub enum Verdict {
    /// Some locked case still fails: a RED or an intermediate commit.
    Red,
    /// Every locked case passes: the lock closes in this commit.
    Green,
}

/// What ran (item 13).
pub enum Scope<'a> {
    /// The hook: the files holding the RED's failing cases. `red` holds the
    /// failing cases of every lock the commit is judged against; `blocking`,
    /// the failures in a file that holds a RED case (`suite::run_red`).
    /// `comando`, the prefixes (`nome:`) of the suites with `filtra = "comando"`.
    Hook { red: &'a [String], blocking: &'a BTreeSet<String>, comando: &'a [String] },
    /// The CI: the whole suite, with the suite names that name the cause of
    /// a missing case (item 59), when the commit's config gives any.
    Ci { suites: Option<&'a Suites> },
}

/// Rules 2 to 4 on the report: the cases that must run ran (the RED's failing
/// cases in the hook, every locked case in the CI), no case that did not fail
/// at the RED fails now, a RED commit fails, and a commit that closes the lock
/// passes every case that failed at the RED (item 13). In the hook every
/// failure in a file that holds a RED case counts, even of a case skipped at
/// the RED; in the CI, the locked cases (a new test that fails is the CI's own
/// refusal).
pub fn judge_suite(report: &Report, lock_path: &str, change: &Change, lock: &Lock, scope: Scope) -> Result<Verdict> {
    let failed = |case: &String| matches!(report.outcome(case), Some(Outcome::Failed | Outcome::Error));
    // A lock that closes in the hook was open in HEAD, its only parent.
    let hook = matches!(scope, Scope::Hook { .. });
    let broken: Vec<String> = match scope {
        Scope::Hook { red, blocking, comando } => {
            check_cases_ran(report, lock_path, &lock.failing_at_red, comando, None)?;
            blocking.iter().filter(|case| !red.contains(case)).cloned().collect()
        }
        Scope::Ci { suites } => {
            check_cases_ran(report, lock_path, &lock.cases, &[], suites)?;
            lock.cases.iter().filter(|case| !lock.failing_at_red.contains(case) && failed(case)).cloned().collect()
        }
    };
    if !broken.is_empty() {
        return refuse(
            "case-broke",
            format!("case(s) that did not fail at RED for lock {lock_path} now fail: {}", short_list(&broken)),
            "a known failure is never ignored: GREEN makes RED cases pass without breaking those that already passed",
            "fix the code until these cases pass again; if the test looks wrong, stop and tell the RED author",
        );
    }
    let failing: Vec<&String> =
        lock.failing_at_red.iter().filter(|case| report.outcome(case) != Some(Outcome::Passed)).collect();
    match change {
        Change::Opened(_) if failing.is_empty() => refuse(
            "red-already-passes",
            format!("the suite already passes in the RED commit (lock {lock_path})"),
            "RED is the commit where the test fails; a test that already passes specifies nothing new",
            "commit RED with only tests and the stub, and the implementation in a later commit",
        ),
        Change::Closed(_) if !failing.is_empty() => refuse(
            "lock-closed-red",
            format!("lock {lock_path} arrives closed, but locked cases do not pass: {}", short_list(&failing)),
            "the lock only closes in the commit where all locked cases pass",
            restore("restore the open lock and keep implementing until the locked cases pass", lock_path, hook),
        ),
        _ if failing.is_empty() => Ok(Verdict::Green),
        _ => Ok(Verdict::Red),
    }
}

/// The suite wrote no report, or its check failed (item 45).
pub fn no_report<T>(missing: Missing) -> Result<T> {
    if let Some(check) = &missing.check {
        return refuse("no-report", missing.reason, FailedCheck::WHY, format!("{}, and try again", check.next()));
    }
    if let Some(advice) = missing.advice {
        return refuse("no-report", missing.reason, advice.why, advice.next);
    }
    refuse(
        "no-report",
        missing.reason,
        "shipcraft judges the suite by its report; without it, locked cases cannot be checked",
        "run the suite manually (check and test_command in .shipcraft.toml), fix the error and try again",
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lock::{Fix, Kind};
    use std::collections::BTreeMap;

    fn open_lock() -> Lock {
        let files: BTreeMap<String, String> = [("tests/t.md".to_string(), crate::lock::new_digest(b"t"))].into();
        let fix = Fix { kind: Kind::Feature, reported_at: None, fixes_release: None };
        Lock::open(files, vec!["t::a".into()], vec!["t::a".into()], Vec::new(), fix)
    }

    #[test]
    fn a_markdown_commit_changes_only_regular_md_files_the_lock_does_not_protect() {
        let raw = |text: &str| raw_entries(text.replace('|', "\0").as_bytes()).unwrap();
        let z = "0".repeat(40);
        let a = "a".repeat(40);
        let lock = open_lock();
        let added = raw(&format!(":000000 100644 {z} {a} A|README.md|:100644 100755 {a} {a} M|docs/x.md|"));
        assert_eq!(added.len(), 2);
        assert!(markdown(&added, &lock));
        assert!(markdown(&[], &lock), "an empty commit counts");
        assert!(!markdown(&raw(&format!(":100644 000000 {a} {z} D|x.py|")), &lock));
        assert!(!markdown(&raw(&format!(":000000 120000 {z} {a} A|link.md|")), &lock), "a symlink");
        assert!(!markdown(&raw(&format!(":100644 100644 {a} {a} M|tests/t.md|")), &lock), "a locked file");
        assert!(raw_entries(b"not raw\0").is_err());
    }

    #[test]
    fn an_abandon_needs_exactly_one_new_open_lock() {
        let old = open_lock();
        let parent: LockFiles = [("l/old.json".to_string(), old.to_json().into_bytes())].into();
        let abandoned = old.abandoned("why").unwrap().to_json().into_bytes();
        let new = open_lock().to_json().into_bytes();
        let judged = |now: &[(&str, &Vec<u8>)], parents: usize| {
            let now: LockFiles = now.iter().map(|(p, b)| (p.to_string(), (*b).clone())).collect();
            let none = || Ok(Vec::new());
            let changed: Changed = Some(&none);
            let parents = vec![parent.clone(); parents];
            judge_locks(&parents, &now, "in the pending commit", false, changed)
        };
        let code = |r: Result<Vec<(String, Change)>>| match r {
            Err(Stop::Refused(refusal)) => refusal.code,
            Err(Stop::Failed(_)) => "error",
            Ok(_) => "ok",
        };
        assert_eq!(code(judged(&[("l/old.json", &abandoned), ("l/new.json", &new)], 1)), "ok");
        assert_eq!(code(judged(&[("l/old.json", &abandoned)], 1)), "replace-alone");
        let second = open_lock().to_json().into_bytes();
        assert_eq!(
            code(judged(&[("l/old.json", &abandoned), ("l/new.json", &new), ("l/two.json", &second)], 1)),
            "replace-alone"
        );
        // A merge never abandons.
        assert_eq!(code(judged(&[("l/old.json", &abandoned), ("l/new.json", &new)], 2)), "lock-edited");
        // An abandoned form with other values.
        let other = Lock { cases: vec!["t::a".into(), "t::b".into()], ..old.clone() }.abandoned("why").unwrap();
        let other = other.to_json().into_bytes();
        assert_eq!(code(judged(&[("l/old.json", &other), ("l/new.json", &new)], 1)), "lock-edited");
    }

    use crate::refusal::Stop;

    #[test]
    fn restore_names_the_command_only_for_a_safe_lock_in_head() {
        let cmd = "`git restore --staged --worktree --source=HEAD -- ':/.shipcraft/locks/v1-33_a.json'`";
        assert!(restore("x", ".shipcraft/locks/v1-33_a.json", true).ends_with(cmd));
        assert_eq!(restore("x", ".shipcraft/locks/v1-33_a.json", false), "x");
        assert_eq!(restore("x", ".shipcraft/locks/com espaço.json", true), "x");
        assert_eq!(restore("x", ".shipcraft/locks/sub/a.json", true), "x");
    }
}
