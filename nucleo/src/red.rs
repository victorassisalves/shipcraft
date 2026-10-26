//! `shipcraft red`: runs the suite, demands that it fail by assertion, and writes an
//! open lock with the hash of every test file and of `.shipcraft.toml` (rule 1).

use crate::config::{Config, CONFIG_FILE};
use crate::git::{Repo, Snapshot};
use crate::junit::Outcome;
use crate::lock::{lock_files, new_lock_path, sha256_hex, Lock};
use crate::refusal::{failed, refuse, short_list, Result};
use crate::suite;
use std::collections::BTreeMap;
use std::fs;

pub fn run(repo: &Repo) -> Result<()> {
    let config = Config::load(repo)?;
    refuse_if_a_lock_is_open(repo)?;

    // The RED judges its own tree: the build runs there (item 16a).
    suite::build(repo.root(), &config, &format!("; if it fails because the stub is missing, {}", stub_hint(&config)))?;
    let report = match suite::run(repo.root(), false, &config)? {
        Ok(report) => report,
        Err(missing) => {
            return refuse(
                "no-report",
                missing.0,
                "RED fails on an assertion describing behavior; a compilation or import error proves nothing",
                format!("{}; then run `shipcraft red` again", stub_hint(&config)),
            )
        }
    };
    let errors = report.cases_with(Outcome::Error);
    if !errors.is_empty() {
        return refuse(
            "error-before-assertions",
            format!("the suite errored before assertions in: {}", short_list(&errors)),
            "RED fails on an assertion describing behavior; a collection or import error proves nothing",
            format!("{}; then run `shipcraft red` again", stub_hint(&config)),
        );
    }
    let failing = report.cases_with(Outcome::Failed);
    if failing.is_empty() {
        return refuse(
            "red-already-passes",
            format!("the suite passed ({} case(s)): there is no RED", report.cases_run().len()),
            "a test that already passes without the implementation specifies nothing new",
            "write a test that fails on the missing behavior and run `shipcraft red` again",
        );
    }

    let files = locked_files(repo, &config)?;
    refuse_a_suite_without_tests(repo, &config, &files, &failing)?;

    let lock = Lock::open(files, report.cases_run(), failing);
    let path = new_lock_path();
    let full_path = repo.path(&path);
    fs::create_dir_all(full_path.parent().expect("a lock path has a directory"))
        .and_then(|()| fs::write(&full_path, lock.to_json()))
        .map_err(|e| failed(format!("write {path}: {e}")))?;

    println!(
        "shipcraft: RED locked at {path}: {} file(s), {} case(s), {} failing: {}",
        lock.files.len(),
        lock.cases.len(),
        lock.failing_at_red.len(),
        short_list(&lock.failing_at_red)
    );
    println!("shipcraft: commit the lock with the tests; the hook checks the RED commit.");
    Ok(())
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
        files.insert(path.to_string(), sha256_hex(&bytes));
    }
    Ok(files)
}
