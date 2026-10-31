//! `shipcraft red`: runs the suite, demands that it fail by assertion, and writes an
//! open lock with the hash of every test file and of `.shipcraft.toml` (rule 1).

use crate::config::{self, Config, CONFIG_FILE};
use crate::git::{Repo, Snapshot};
use crate::glob;
use crate::junit::{Outcome, Report};
use crate::lock::{lock_files, new_digest, new_lock_path, Fix, Lock, LOCK_DIR};
use crate::narrow::{self, Chosen, Fallback, Plan};
use crate::refusal::{failed, refuse, short_list, Result};
use crate::suite::{self, Narrowed};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::{self, Write};
use std::path::Path;

/// Item 81: the failing cases a written lock left out because they live in a
/// test file the RED did not change, or the base tree that could not be read.
#[derive(Default)]
pub struct LeftOut {
    pub cases: Vec<String>,
    /// Why the base tree could not be read: nothing was left out.
    pub unread: Option<String>,
}

impl LeftOut {
    /// `unchanged_dropped` on the `red` row: null when the base tree could not
    /// be read, the count when above 0, and absent otherwise.
    pub fn record(&self, row: &mut serde_json::Value) {
        if self.unread.is_some() {
            row["unchanged_dropped"] = serde_json::Value::Null;
        } else if !self.cases.is_empty() {
            row["unchanged_dropped"] = self.cases.len().into();
        }
    }

    /// The line after item 53's and before `RED locked at`/`RED redone at`.
    fn print(&self) {
        if let Some(error) = &self.unread {
            println!("shipcraft: every failing case is locked: could not read the base tree ({error})");
        } else if !self.cases.is_empty() {
            let shown: Vec<String> = self.cases.iter().map(|id| one_line(id)).collect();
            println!(
                "shipcraft: not locked, failing in test files this RED did not change: {}; CI runs them",
                short_list(&shown)
            );
        }
    }
}

/// The path of the lock written, how many cases the second run dropped, and
/// (item 81) the cases left out.
/// Item 55: `base` and `all` choose the first run; `chosen`, how it ran, once
/// the selection is decided. Item 75: `fix`, the lock's fix fields.
pub fn run(
    repo: &Repo,
    base: Option<&str>,
    all: bool,
    fix: Fix,
    chosen: &mut Option<Chosen>,
) -> Result<(String, usize, LeftOut)> {
    let config = Config::load(repo)?;
    refuse_if_a_lock_is_open(repo)?;
    // Item 80: before the base and anything else.
    crate::install::refuse_if_not_committed(repo, false)?;
    let base = narrow::base(repo, base);
    let changed = narrow::changed(repo, &base);
    warn_outside_globs(repo, &config, &changed);
    let plan = narrow::plan(repo, &config, &changed, all, None);
    let report = red_report(repo, &config, "shipcraft red", &base, plan, chosen)?;
    let failing = failing_at_red(&report, "shipcraft red")?;
    let left = leave_out(repo, &config, &changed, all, None, &failing)?;
    let (cases, failing) = without(&left.cases, report.cases_run(), failing);

    let files = locked_files(repo, &config)?;
    refuse_a_suite_without_tests(repo, &config, &files, &failing)?;
    let (failing, dropped) = confirm(repo, &config, &files, failing, "shipcraft red")?;
    // Item 53: hashed as the second run leaves the files.
    let files = locked_files(repo, &config)?;

    let lock = Lock::open(files, cases, failing, fix);
    let path = new_lock_path();
    let full_path = repo.path(&path);
    fs::create_dir_all(full_path.parent().expect("a lock path has a directory"))
        .and_then(|()| fs::write(&full_path, lock.to_json()))
        .map_err(|e| failed(format!("write {path}: {e}")))?;

    print_dropped(&dropped);
    left.print();
    println!(
        "shipcraft: RED locked at {path}: {} file(s), {} case(s), {} failing: {}",
        lock.files.len(),
        lock.cases.len(),
        lock.failing_at_red.len(),
        short_list(&lock.failing_at_red)
    );
    println!("shipcraft: commit the lock with the tests; the hook checks the RED commit.");
    warn_absent_suites(repo, &config, &base, &lock);
    next_green(&config);
    Ok((path, dropped.len(), left))
}

/// Item 46: `red --redo` rewrites the open lock HEAD holds, in place, as the
/// lock `red` would write for this tree; it keeps every case of the old one.
/// `path` is HEAD's lock as soon as it is known, for the run log row;
/// `rerun_dropped`, the cases the second run dropped, once the lock is written;
/// `chosen`, how the first run went, once HEAD's lock is known. Item 60: it
/// runs `red`'s selection (`base`, `all`) plus the files of the lock's cases.
pub fn redo(
    repo: &Repo,
    base: Option<&str>,
    all: bool,
    path: &mut Option<String>,
    rerun_dropped: &mut Option<usize>,
    chosen: &mut Option<Chosen>,
    unchanged: &mut Option<LeftOut>,
) -> Result<()> {
    let config = Config::load(repo)?;
    let (lock_path, old) = head_lock(repo, path)?;
    // Item 80: after HEAD's lock, before the base and anything else.
    crate::install::refuse_if_not_committed(repo, true)?;
    // Item 66: the redo resolves its base as `red` does.
    let base = narrow::base(repo, base);
    let changed = narrow::changed(repo, &base);
    warn_outside_globs(repo, &config, &changed);
    let plan = narrow::plan(repo, &config, &changed, all, Some(&old));
    let report = red_report(repo, &config, "shipcraft red --redo", &base, plan, chosen)?;
    let run = report.cases_run();
    let dropped: Vec<&String> = old.cases.iter().filter(|case| !run.contains(case)).collect();
    if !dropped.is_empty() {
        return refuse(
            "redo-drops-case",
            format!("the suite no longer has case(s) of lock {lock_path}: {}", short_list(&dropped)),
            "a redo repairs the RED's tests and keeps its contract: every case it locked stays locked",
            "keep every locked case in the suite and run `shipcraft red --redo` again; a repair that drops or renames a case means rewriting the branch's history",
        );
    }
    let failing = failing_at_red(&report, "shipcraft red --redo")?;
    let left = leave_out(repo, &config, &changed, all, Some(&old), &failing)?;
    let (run, failing) = without(&left.cases, run, failing);
    let files = locked_files(repo, &config)?;
    refuse_a_suite_without_tests(repo, &config, &files, &failing)?;
    let (failing, dropped) = confirm(repo, &config, &files, failing, "shipcraft red --redo")?;
    let files = locked_files(repo, &config)?;
    // Item 75: format 4 keeps its fix fields; a format 2 or 3 lock becomes format 3.
    let lock = old.redone(files, run, failing);

    let full_path = repo.path(&lock_path);
    let in_tree = fs::read(&full_path).ok().and_then(|bytes| Lock::parse(&bytes));
    if lock == old && in_tree.as_ref() == Some(&old) {
        println!("shipcraft: RED unchanged: lock {lock_path} already reads the same; nothing written.");
        return Ok(());
    }
    replace(&full_path, &lock_path, &lock.to_json())?;
    *rerun_dropped = Some(dropped.len());
    print_dropped(&dropped);
    left.print();
    *unchanged = Some(left);

    let minus = |a: &[String], b: &[String]| a.iter().filter(|case| !b.contains(case)).cloned().collect::<Vec<_>>();
    let list = |cases: Vec<String>| if cases.is_empty() { "none".to_string() } else { cases.join(", ") };
    println!(
        "shipcraft: RED redone at {lock_path}: {} file(s), {} case(s), {} failing: {}",
        lock.files.len(),
        lock.cases.len(),
        lock.failing_at_red.len(),
        short_list(&lock.failing_at_red)
    );
    println!("shipcraft: cases added: {}", list(minus(&lock.cases, &old.cases)));
    println!("shipcraft: cases no longer failing at RED: {}", list(minus(&old.failing_at_red, &lock.failing_at_red)));
    println!("shipcraft: cases newly failing at RED: {}", list(minus(&lock.failing_at_red, &old.failing_at_red)));
    println!("shipcraft: commit the lock with the repaired tests, and nothing else; the hook checks the redo commit.");
    warn_absent_suites(repo, &config, &base, &lock);
    next_green(&config);
    Ok(())
}

/// Item 64: after a lock is written, the last stdout line names the GREEN.
fn next_green(config: &Config) {
    match &config.papeis.green {
        Some(green) => println!("shipcraft: next: the GREEN, in a new session ({}, [roles] green)", green.shown()),
        None => println!("shipcraft: next: the GREEN, in a new session ([roles] green not set)"),
    }
}

/// Item 46: the one open lock HEAD holds, read as today (a broken seal is
/// `lock-edited`, an unknown format `lock-format`).
fn head_lock(repo: &Repo, path: &mut Option<String>) -> Result<(String, Lock)> {
    let head = match repo.head()? {
        Some(head) => Snapshot::Commit(head),
        None => return without_lock(),
    };
    let mut open = Vec::new();
    for file in repo.list(&head, LOCK_DIR)?.into_iter().filter(|p| p.ends_with(".json")) {
        let bytes = repo.read(&head, &file)?.unwrap_or_default();
        if Lock::parse(&bytes).is_none_or(|lock| lock.is_open()) {
            open.push(file);
        }
    }
    // With several, the row names one `red` wrote (its file name), else the first.
    open.sort_by_key(|file| !written_by_red(file));
    let Some(first) = open.first() else { return without_lock() };
    *path = Some(first.clone());
    if open.len() > 1 {
        return refuse(
            "lock-open",
            format!("HEAD holds {} open locks: {}", open.len(), short_list(&open)),
            "a redo rewrites the one open lock of the branch's cycle; with more than one, it cannot tell which",
            "finish or remove the extra cycle so HEAD holds one open lock, then run `shipcraft red --redo` again",
        );
    }
    let bytes = lock_files(repo, &head)?.remove(first.as_str()).unwrap_or_default();
    match Lock::parse(&bytes) {
        Some(lock) => Ok((first.clone(), lock)),
        None => refuse(
            "lock-edited",
            format!("lock {first} was edited outside shipcraft {}", head.describe()),
            "only shipcraft changes the lock: `shipcraft red` opens it and the green commit closes it; editing it manually silently changes the contract",
            "restore the lock as shipcraft left it; it closes automatically in the commit where locked cases pass",
        ),
    }
}

fn without_lock<T>() -> Result<T> {
    refuse(
        "redo-without-lock",
        "HEAD holds no open lock: there is no committed RED to redo",
        "a redo rewrites the RED commit's lock in a commit of its own; a RED not yet committed needs no redo",
        "for an uncommitted RED, delete its lock file and run `shipcraft red` again; otherwise commit the RED first",
    )
}

/// A lock file name `new_lock_path` writes: 12 lowercase hex characters.
fn written_by_red(path: &str) -> bool {
    let name = path.rsplit('/').next().unwrap_or_default().strip_suffix(".json").unwrap_or_default();
    name.len() == 12 && name.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// Writes a temporary file next to the lock and renames it over the lock, so
/// a failed write leaves the old bytes.
fn replace(full_path: &Path, lock_path: &str, json: &str) -> Result<()> {
    let temp = full_path.with_extension(format!("redo-{}.tmp", std::process::id()));
    let written = fs::write(&temp, json).and_then(|()| fs::rename(&temp, full_path));
    if let Err(e) = written {
        let _ = fs::remove_file(&temp);
        return refuse(
            "redo-write-failed",
            format!("could not replace lock {lock_path}: {e}"),
            "the lock is replaced whole or not at all, so the old lock stays as it was",
            format!("make {LOCK_DIR} writable and run `shipcraft red --redo` again"),
        );
    }
    Ok(())
}

/// The suite's report at RED: the build, every suite's check, every suite
/// (item 55: or the changed test files, as `plan` says); refuses no report and
/// errors before assertions. `again` is the command to rerun. The notice of
/// how it ran comes first, refusals included; item 66's line on the base the
/// candidates gave comes right before it.
fn red_report(
    repo: &Repo,
    config: &Config,
    again: &str,
    base: &narrow::Base,
    plan: Plan,
    chosen: &mut Option<Chosen>,
) -> Result<Report> {
    let locked: BTreeSet<String> = config.test_files(repo)?.into_iter().chain([CONFIG_FILE.to_string()]).collect();
    let first = chosen.insert(Chosen::new(&plan, locked.len()));
    let ran = first_run(repo, config, plan, first);
    if let Some(compared) = base.as_ref().ok().and_then(narrow::Compared::notice) {
        println!("{compared}");
    }
    println!("{}", first.notice());
    if let Some(support) = first.support_notice() {
        println!("{support}");
    }
    let report = match ran? {
        Ok(report) => report,
        // Item 45: a failing check names itself, and says to fix what it reports.
        Err(suite::Missing { reason, check: Some(check) }) => {
            return refuse(
                "no-report",
                reason,
                suite::FailedCheck::WHY,
                format!("{}; then run `{again}` again", check.next()),
            )
        }
        Err(missing) => {
            return refuse(
                "no-report",
                missing.reason,
                "RED fails on an assertion describing behavior; a compilation or import error proves nothing",
                format!("{}; then run `{again}` again", stub_hint(config)),
            )
        }
    };
    let errors = report.cases_with(Outcome::Error);
    if !errors.is_empty() {
        return refuse(
            "error-before-assertions",
            format!("the suite errored before assertions in: {}", short_list(&errors)),
            "RED fails on an assertion describing behavior; a collection or import error proves nothing",
            format!("{}; then run `{again}` again", stub_hint(config)),
        );
    }
    // Item 52: a block whose beforeAll failed is reported as a case no passing run reports.
    let groups = report.group_failures();
    if !groups.is_empty() {
        let shown: Vec<String> = groups.iter().map(|id| one_line(id)).collect();
        return refuse(
            "group-failed",
            format!("a describe block's hook failed before its tests ran, in: {}", short_list(&shown)),
            "the block's hook failed before its tests ran, so the block is reported as a case under a name a passing run never reports, and a lock on it could never close",
            format!("fix the block's hook (or move any assertion it makes into a test of the block); if it failed under load or by chance, run `{again}` again"),
        );
    }
    Ok(report)
}

/// Item 55: the first run's report. The build runs as today; then, with
/// selected files, the narrowed run, whose reports stand only when every case
/// maps to one locked file and (item 65) each suite that ran has a selected
/// file that holds a case; the others are support files. Otherwise
/// `chosen` says why, and every suite's command runs in full (its check ran).
fn first_run(repo: &Repo, config: &Config, plan: Plan, chosen: &mut Chosen) -> Result<suite::Ran<Report>> {
    // The RED judges its own tree: the build runs there (item 16a).
    suite::build(repo.root(), config, &format!("; if it fails because the stub is missing, {}", stub_hint(config)))?;
    let selected = match plan {
        Plan::All(_) => return suite::run(repo.root(), false, config),
        Plan::Changed { selected, .. } => selected,
    };
    let present = repo.files()?;
    let ran = match with_lists(repo, |tmp| suite::run_changed(repo.root(), config, &selected, &present, tmp))? {
        Ok(ran) => ran,
        Err(check) => return Ok(Err(check)),
    };
    let locked = config.test_files(repo)?;
    let mut report = Report::empty();
    let mut fallback: Option<Fallback> = None;
    let mut support = BTreeSet::new();
    for ((suite, files), ran) in config.suites().iter().zip(&selected).zip(ran) {
        let why = match ran {
            Narrowed::Skipped => continue,
            Narrowed::NoReport => Fallback::NoReport,
            Narrowed::Ran(ran) => match suite::covered(repo.root(), suite, &locked, &present, files, ran) {
                Ok((kept, uncovered)) => {
                    report.absorb(&suite.nome, kept);
                    // Item 65: each suite's own uncovered files, by repository path.
                    let prefix = suite.prefix();
                    support.extend(uncovered.into_iter().map(|rel| format!("{prefix}{rel}")));
                    continue;
                }
                Err(why) => why,
            },
        };
        fallback = Some(fallback.map_or(why, |first| first.min(why)));
    }
    let Some(why) = fallback else {
        chosen.support = support;
        return Ok(Ok(report));
    };
    chosen.fallback = Some(why);
    suite::run_commands(repo.root(), config)
}

/// Runs `run` with the directory of item 22's lists, left as it was found
/// (empty and created here: removed).
fn with_lists<T>(repo: &Repo, run: impl FnOnce(&Path) -> Result<T>) -> Result<T> {
    let tmp = repo.root().join(repo.text(&["rev-parse", "--git-path", "shipcraft/tmp"])?);
    let had_tmp = tmp.exists();
    let ran = run(&tmp);
    if !had_tmp {
        let _ = fs::remove_dir(&tmp);
    }
    ran
}

/// The cases failing at RED; none is `red-already-passes`.
fn failing_at_red(report: &Report, again: &str) -> Result<Vec<String>> {
    let failing = report.cases_with(Outcome::Failed);
    if failing.is_empty() {
        return refuse(
            "red-already-passes",
            format!("the suite passed ({} case(s)): there is no RED", report.cases_run().len()),
            "a test that already passes without the implementation specifies nothing new",
            format!("write a test that fails on the missing behavior and run `{again}` again"),
        );
    }
    Ok(failing)
}

/// Item 81: `cases` and `failing` without the cases left out.
fn without(left: &[String], cases: Vec<String>, failing: Vec<String>) -> (Vec<String>, Vec<String>) {
    let keep = |list: Vec<String>| list.into_iter().filter(|case| !left.contains(case)).collect();
    (keep(cases), keep(failing))
}

/// Item 81: the failing cases outside the RED, byte-sorted: each maps, by the
/// hook's mapper over the suite's locked files on the working tree, to one
/// file that is not a changed path and is in the merge base's tree; none
/// with `--all`, without changed paths, for a redo's case of HEAD's lock, or
/// when every failing case is outside (the guard). A case shares no file with
/// a case that stays. A failed base-tree read leaves nothing out.
fn leave_out(
    repo: &Repo,
    config: &Config,
    changed: &std::result::Result<narrow::Changed, Fallback>,
    all: bool,
    redo: Option<&Lock>,
    failing: &[String],
) -> Result<LeftOut> {
    let Ok(changed) = changed else { return Ok(LeftOut::default()) };
    if all {
        return Ok(LeftOut::default());
    }
    let locked = config.test_files(repo)?;
    let present = repo.files()?;
    // Each failing case's one file (a repository path), when every suite that
    // owns it maps it to the same file.
    let mut file_of: BTreeMap<&str, Option<String>> = BTreeMap::new();
    for suite in config.suites() {
        let own: Vec<(&String, &str)> =
            failing.iter().filter_map(|case| config.own(&suite, case).map(|id| (case, id))).collect();
        if own.is_empty() {
            continue;
        }
        let ids: Vec<&str> = own.iter().map(|(_, id)| *id).collect();
        let held = suite::holders(repo.root(), &suite, &locked, &present, &ids);
        let prefix = suite.prefix();
        for (i, (case, _)) in own.iter().enumerate() {
            let file = held.as_ref().map(|files| format!("{prefix}{}", files[i]));
            let entry = file_of.entry(case.as_str()).or_insert_with(|| file.clone());
            if *entry != file {
                *entry = None;
            }
        }
    }
    let changed_paths: BTreeSet<&[u8]> = changed.paths.iter().map(|(_, path)| path.as_slice()).collect();
    let candidates: BTreeMap<&str, &String> = file_of
        .iter()
        .filter(|(case, _)| redo.is_none_or(|lock| !lock.cases.iter().any(|c| c == *case)))
        .filter_map(|(case, file)| file.as_ref().map(|file| (*case, file)))
        .filter(|(_, file)| !changed_paths.contains(file.as_bytes()))
        .collect();
    if candidates.is_empty() {
        return Ok(LeftOut::default());
    }
    let paths: BTreeSet<&str> = candidates.values().map(|file| file.as_str()).collect();
    let paths: Vec<&str> = paths.into_iter().collect();
    let in_base = match narrow::in_base_tree(repo, &changed.merge_base, &paths) {
        Ok(in_base) => in_base,
        Err(error) => return Ok(LeftOut { cases: Vec::new(), unread: Some(error) }),
    };
    let outside: BTreeSet<&str> =
        candidates.iter().filter(|(_, file)| in_base.contains(file.as_str())).map(|(case, _)| *case).collect();
    // The guard: at least one failing case is not outside the RED.
    if failing.iter().all(|case| outside.contains(case.as_str())) {
        return Ok(LeftOut::default());
    }
    // Same file as a case that stays: kept.
    let staying: BTreeSet<&String> = failing
        .iter()
        .filter(|case| !outside.contains(case.as_str()))
        .filter_map(|case| file_of.get(case.as_str()).and_then(Option::as_ref))
        .collect();
    let mut cases: Vec<String> = outside
        .into_iter()
        .filter(|case| !staying.contains(candidates[case]))
        .map(str::to_string)
        .collect();
    cases.sort();
    Ok(LeftOut { cases, unread: None })
}

/// Item 53: reruns once, as the hook runs them, the suites that have a case
/// of `failing`, on the working tree, with `files` as the lock's files; a case
/// stays failing unless its suite's second report shows it passed. The cases
/// kept and those dropped; every case dropped is `red-not-reproduced`.
fn confirm(
    repo: &Repo,
    config: &Config,
    files: &BTreeMap<String, String>,
    failing: Vec<String>,
    again: &str,
) -> Result<(Vec<String>, Vec<String>)> {
    let present = repo.files()?;
    let rerun = |tmp: &Path| -> Result<Vec<String>> {
        let mut dropped = Vec::new();
        for suite in config.suites() {
            let cases: Vec<String> =
                failing.iter().filter(|case| config.own(&suite, case).is_some()).cloned().collect();
            if cases.is_empty() {
                continue;
            }
            // One suite at a time: the hook's run skips every suite without a case,
            // and a suite with no readable report keeps its cases.
            let locked = suite::Locked {
                files: files.keys().cloned().collect(),
                cases,
                present: present.clone(),
                tmp: tmp.to_path_buf(),
            };
            if let Ok((report, _)) = suite::run_red(repo.root(), false, config, &locked)? {
                dropped.extend(locked.cases.into_iter().filter(|case| report.outcome(case) == Some(Outcome::Passed)));
            }
        }
        Ok(dropped)
    };
    let mut dropped = with_lists(repo, rerun)?;
    let kept: Vec<String> = failing.iter().filter(|case| !dropped.contains(case)).cloned().collect();
    if kept.is_empty() {
        let shown: Vec<String> = failing.iter().map(|id| one_line(id)).collect();
        return refuse(
            "red-not-reproduced",
            format!("every case that failed passed on a second run: {}", short_list(&shown)),
            "a RED's failure must happen every time the test runs without the implementation; these failed once and then passed",
            format!("run `{again}` again; if the tests keep passing on their own, fix them (or the setup they depend on)"),
        );
    }
    dropped.sort();
    Ok((kept, dropped))
}

/// Item 53: the cases the second run dropped, before the usual lines.
fn print_dropped(dropped: &[String]) {
    if !dropped.is_empty() {
        let shown: Vec<String> = dropped.iter().map(|id| one_line(id)).collect();
        println!("shipcraft: not locked, passed on a second run: {}", short_list(&shown));
    }
}

/// Item 52: a case id on one line of a refusal (a line break in a name is escaped).
pub(crate) fn one_line(id: &str) -> String {
    id.chars()
        .map(|c| {
            if c.is_control() || matches!(c, '\u{2028}' | '\u{2029}') {
                c.escape_default().to_string()
            } else {
                c.to_string()
            }
        })
        .collect()
}

fn stub_hint(config: &Config) -> &'static str {
    config
        .lang
        .map_or("create the stub: the function exists with the right signature and does nothing yet", |l| l.stub_hint())
}

/// Rule 1: one open cycle per branch.
fn refuse_if_a_lock_is_open(repo: &Repo) -> Result<()> {
    for (path, bytes) in lock_files(repo, &Snapshot::Tree)? {
        if Lock::parse(&bytes).is_none_or(|lock| lock.is_open()) {
            return refuse(
                "lock-open",
                format!("there is already an open lock on this branch: {path}"),
                "one cycle at a time on the same branch: the current RED has not turned green yet",
                "finish the current cycle (the commit where locked cases pass closes the lock), or open the new RED on another branch",
            );
        }
    }
    Ok(())
}

/// Item 30.2: a suite that has cases failing at the RED and locks no regular
/// file (a link does not count, 30.3) would leave its tests open to the GREEN.
fn refuse_a_suite_without_tests(
    repo: &Repo,
    config: &Config,
    files: &BTreeMap<String, String>,
    failing: &[String],
) -> Result<()> {
    let regular = |path: &String| fs::symlink_metadata(repo.path(path)).is_ok_and(|m| m.is_file());
    for suite in config.suites() {
        let own = if suite.nome.is_empty() { String::new() } else { format!("{}:", suite.nome) };
        let fails = failing.iter().any(|case| case.starts_with(&own));
        if fails && !files.keys().any(|path| suite.matches(path) && regular(path)) {
            return refuse(
                "suite-without-tests",
                format!(
                    "suite {} (root `{}`, globs {:?}) has failing cases and no test files: the lock would cover none of it",
                    suite.name(),
                    suite.shown_root(),
                    suite.globs
                ),
                "the lock protects RED tests by hash; without a locked file, GREEN can change them",
                "fix this suite's `root` and `globs` in .shipcraft.toml to match the test files, and run `shipcraft red` again",
            );
        }
    }
    Ok(())
}

/// The hash of every test file and of `.shipcraft.toml`, by path.
fn locked_files(repo: &Repo, config: &Config) -> Result<BTreeMap<String, String>> {
    let mut files = BTreeMap::new();
    for path in config.test_files(repo)?.iter().map(String::as_str).chain([CONFIG_FILE]) {
        let bytes = fs::read(repo.path(path)).map_err(|e| failed(format!("read {path}: {e}")))?;
        files.insert(path.to_string(), new_digest(&bytes));
    }
    Ok(files)
}

/// Item 59: a warning, one line on stderr; a failed write is ignored.
fn warning(text: String) {
    let _ = writeln!(io::stderr(), "shipcraft: warning: {text}");
}

/// Item 59: a path's last component is named as a test: `test_*.py`,
/// `*_test.py`, `*_test.go`, or `*.test.<ext>` and `*.spec.<ext>` for JS/TS.
fn test_named(path: &str) -> bool {
    let name = path.rsplit('/').next().unwrap_or_default();
    let js = ["js", "jsx", "mjs", "cjs", "ts", "tsx", "mts", "cts"];
    ["test_*.py", "*_test.py", "*_test.go"].iter().any(|pattern| glob::matches(pattern, name))
        || js.iter().any(|ext| [".test.", ".spec."].iter().any(|kind| glob::matches(&format!("*{kind}{ext}"), name)))
}

/// Item 59: the changed test-named regular files that match no suite's
/// globs, before the build; nothing when the changed paths cannot be read.
fn warn_outside_globs(repo: &Repo, config: &Config, changed: &std::result::Result<narrow::Changed, Fallback>) {
    let Ok(changed) = changed else { return };
    let outside: BTreeSet<&str> = changed
        .paths
        .iter()
        .filter_map(|(_, path)| std::str::from_utf8(path).ok())
        .filter(|path| test_named(path) && !config.is_test_file(path))
        // A regular file as `lstat` sees it, and readable (as item 55's selection asks).
        .filter(|path| fs::symlink_metadata(repo.path(path)).is_ok_and(|m| m.is_file()))
        .filter(|path| fs::File::open(repo.path(path)).is_ok())
        .collect();
    if outside.is_empty() {
        return;
    }
    let outside: Vec<&str> = outside.into_iter().collect();
    warning(format!(
        "{} changed test file(s) match no suite's globs and are not locked: {}; widen a suite's globs, or add a [[suite]] for them (when the base has a .shipcraft.toml, CI judges a PR by the base's, so a new suite goes in a PR of its own first)",
        outside.len(),
        short_list(&outside)
    ));
}

/// Item 59: the named suites with a case in the lock that the base's
/// `.shipcraft.toml` does not have; nothing when it cannot be read. Item 66:
/// the base is the commit `red` compared with, named as point 4 names it.
fn warn_absent_suites(repo: &Repo, config: &Config, base: &narrow::Base, lock: &Lock) {
    let Ok(compared) = base else { return };
    let at_base = repo.read(&Snapshot::Commit(compared.commit.clone()), CONFIG_FILE).ok().flatten();
    let Some(present) = at_base.as_deref().and_then(config::suite_names) else { return };
    let named: Vec<String> = config.suites().into_iter().map(|suite| suite.nome).filter(|n| !n.is_empty()).collect();
    let absent: BTreeSet<&String> = lock
        .cases
        .iter()
        .filter_map(|case| config::owner(case, &named))
        .filter(|name| !present.contains(*name))
        .collect();
    if absent.is_empty() {
        return;
    }
    let absent: Vec<&String> = absent.into_iter().collect();
    let shown = &compared.shown;
    warning(format!(
        "the lock has cases in suite(s) absent from {shown}'s .shipcraft.toml: {}; CI judges a PR by its base's config and will refuse them as case-missing; bring the suite to {shown} in a PR of its own, then rebase this branch",
        short_list(&absent)
    ));
}
