//! The rules a commit keeps while a lock is open (rules 2 to 4), shared by the
//! hook (`shipcraft check`) and the CI (`shipcraft ci`).

use crate::config::CONFIG_FILE;
use crate::git::{Repo, Snapshot};
use crate::init::LEFTHOOK_FILES;
use crate::init_tool::{HUSKY, PRE_COMMIT_CONFIG};
use crate::junit::{Outcome, Report};
use crate::lock::{Lock, LockFiles, LOCK_DIR};
use crate::refusal::{refuse, short_list, Result};
use crate::suite::Missing;
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

/// Judges every lock file of `now` against the same file in `parents`.
/// Refuses a deleted open lock and any lock not written by shipcraft. In the hook
/// (`hook`), `parents` is HEAD alone.
pub fn judge_locks(parents: &[LockFiles], now: &LockFiles, place: &str, hook: bool) -> Result<Vec<(String, Change)>> {
    judge_locks_admitting(parents, now, place, hook, false)
}

/// As `judge_locks`; with `admit_closed`, a new lock that arrives already
/// closed is kept instead of refused (item 42: a squash the gate proved).
pub fn judge_locks_admitting(
    parents: &[LockFiles],
    now: &LockFiles,
    place: &str,
    hook: bool,
    admit_closed: bool,
) -> Result<Vec<(String, Change)>> {
    let paths: BTreeSet<&String> = parents.iter().flat_map(|locks| locks.keys()).chain(now.keys()).collect();
    paths
        .into_iter()
        .map(|path| Ok((path.clone(), judge(path, parents, now.get(path), place, hook, admit_closed)?)))
        .collect()
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
    let closes_a_parent =
        before.iter().filter_map(|bytes| Lock::parse(bytes)).any(|old| old.is_open() && old.closed() == lock);
    if closes_a_parent {
        Ok(Change::Closed(lock))
    } else {
        edited()
    }
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
    let names = LEFTHOOK_FILES.iter().flat_map(|f| [f.to_string(), f.replacen("lefthook", "lefthook-local", 1)]);
    let names = names.chain(HUSKY.map(|(f, _)| f.to_string())).chain([PRE_COMMIT_CONFIG.to_string()]);
    for file in names {
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
/// case of a suite in `comando` (`filtra = "comando"`) recalls `SHIPCRAFT_CASES`.
fn check_cases_ran(report: &Report, lock_path: &str, required: &[String], comando: &[String]) -> Result<()> {
    let with = |wanted: Option<Outcome>| -> Vec<&String> {
        required.iter().filter(|case| report.outcome(case) == wanted).collect()
    };
    let missing = with(None);
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
    /// The CI: the whole suite.
    Ci,
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
            check_cases_ran(report, lock_path, &lock.failing_at_red, comando)?;
            blocking.iter().filter(|case| !red.contains(case)).cloned().collect()
        }
        Scope::Ci => {
            check_cases_ran(report, lock_path, &lock.cases, &[])?;
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

/// The suite wrote no report.
pub fn no_report<T>(missing: Missing) -> Result<T> {
    refuse(
        "no-report",
        missing.0,
        "shipcraft judges the suite by its report; without it, locked cases cannot be checked",
        "run the suite manually (check and test_command in .shipcraft.toml), fix the error and try again",
    )
}

#[cfg(test)]
mod tests {
    use super::restore;

    #[test]
    fn restore_names_the_command_only_for_a_safe_lock_in_head() {
        let cmd = "`git restore --staged --worktree --source=HEAD -- ':/.shipcraft/locks/v1-33_a.json'`";
        assert!(restore("x", ".shipcraft/locks/v1-33_a.json", true).ends_with(cmd));
        assert_eq!(restore("x", ".shipcraft/locks/v1-33_a.json", false), "x");
        assert_eq!(restore("x", ".shipcraft/locks/com espaço.json", true), "x");
        assert_eq!(restore("x", ".shipcraft/locks/sub/a.json", true), "x");
    }
}
