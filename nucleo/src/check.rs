//! `shipcraft check`, called by the pre-commit hook. Judges what goes in the commit
//! (the index, plus the files git ignores) against the open locks, and closes
//! a lock inside the first commit in which all its locked cases pass.
//!
//! Item 17: with `--commit-msg` (the lefthook runs the `pre-commit` in
//! parallel) it judges the final index and does not write the lock: it marks
//! the judged commit, and `shipcraft close` closes the lock after it (`marca`).
//!
//! Item 6: files outside the commit (untracked, unstaged edits, editor
//! backups) neither block nor change the result. Item 13: only the test files
//! that hold a case that failed at the RED run, and the lock closes when all
//! those cases pass; the whole suite is the CI's.
//!
//! Item 28: before judging, it warns of files in `.shipcraft/locks/` that are left
//! out of the commit; the warning never changes the verdict.

use crate::config::{self, Config, Filtra, CONFIG_FILE};
use crate::contract::{
    bindings, changed_paths, check_files, check_lefthook, judge_locks, judge_suite, no_report, Change, Scope, Verdict,
};
use crate::git::{text, Repo, Snapshot};
use crate::lock::{lock_files, Lock, LockFiles};
use crate::marca;
use crate::refusal::{failed, Result, Stop};
use crate::suite;
use std::fs;

pub fn run(repo: &Repo, commit_msg: bool) -> Result<()> {
    config::reject_legacy_file(repo, &Snapshot::Index)?;
    warn_outside(repo);
    if commit_msg {
        marca::remove(repo)?;
    }
    let staged_config = repo.read(&Snapshot::Index, CONFIG_FILE)?.map(|b| String::from_utf8_lossy(&b).into_owned());
    if let Some(text) = &staged_config {
        config::check_min(text)?;
    }
    // A merge is judged against both parents, as CI judges it: `git merge` runs
    // the commit-msg hook, and a lock closed on the other branch is not an edit.
    let merging = if repo.head()?.is_some() { repo.resolve("MERGE_HEAD")? } else { None };
    let parents: Vec<Snapshot> = repo.head()?.into_iter().chain(merging).map(Snapshot::Commit).collect();
    // Item 31: a commit that changes the config has it validated here, even
    // with no lock open; deleting it is uninstalling and is not validated.
    if let Some(text) = &staged_config {
        let head_config = match parents.first() {
            Some(head) => repo.read(head, CONFIG_FILE)?,
            None => None,
        };
        if head_config.as_deref() != Some(text.as_bytes()) {
            Config::parse(text)?;
        }
    }
    let mut parent_locks = parents.iter().map(|p| lock_files(repo, p)).collect::<Result<Vec<_>>>()?;
    if parent_locks.is_empty() {
        parent_locks.push(LockFiles::new());
    }
    let staged_locks = lock_files(repo, &Snapshot::Index)?;
    // Item 46: a redo commit is judged by the paths it changes against HEAD.
    let changed = || match parents.first() {
        Some(Snapshot::Commit(head)) => changed_paths(repo, head, &Snapshot::Index),
        _ => Ok(Vec::new()),
    };
    let changes = judge_locks(&parent_locks, &staged_locks, "in the pending commit", true, Some(&changed))?;

    let binding: Vec<_> = bindings(&changes).collect();
    if binding.is_empty() {
        println!("shipcraft: no open lock; commit allowed.");
        return Ok(());
    }
    for (path, change, lock) in &binding {
        check_files(repo, &Snapshot::Index, path, lock)?;
        if !matches!(change, Change::Opened(_)) {
            check_lefthook(repo, &parents, &Snapshot::Index, path)?;
        }
    }
    let config = match &staged_config {
        Some(text) => Config::parse(text)?,
        None => Config::load(repo)?,
    };

    // With nothing outside the index the tree is the commit; otherwise the
    // suite runs on a git checkout of the index (item 14).
    let copy = if repo.unstaged()?.is_empty() { None } else { Some(repo.export(&Snapshot::Index)?) };
    let dir = copy.as_ref().map_or(repo.root(), |c| c.path());
    let locked = suite::Locked {
        files: binding.iter().flat_map(|(_, _, lock)| lock.files.keys().cloned()).collect(),
        cases: binding.iter().flat_map(|(_, _, lock)| lock.failing_at_red.iter().cloned()).collect(),
        present: repo.list(&Snapshot::Index, ".")?,
        tmp: repo.root().join(repo.text(&["rev-parse", "--git-path", "shipcraft/tmp"])?),
    };
    // Item 22.6: the reminder in `caso-sumiu` names the suites the command filters.
    let comando: Vec<String> = config
        .suites()
        .iter()
        .filter(|suite| suite.filtra == Filtra::Comando)
        .map(|suite| if suite.nome.is_empty() { String::new() } else { format!("{}:", suite.nome) })
        .collect();
    let (report, blocking) = suite::run_red(dir, copy.is_some(), &config, &locked)?.or_else(no_report)?;
    let mut closing = Vec::new();
    for (path, change, lock) in binding {
        match (
            change,
            judge_suite(
                &report,
                path,
                change,
                lock,
                Scope::Hook { red: &locked.cases, blocking: &blocking, comando: &comando },
            )?,
        ) {
            (Change::Kept(_), Verdict::Green) if commit_msg => closing.push(path.to_string()),
            (Change::Kept(_), Verdict::Green) => close(repo, path, lock)?,
            (Change::Kept(_), Verdict::Red) => {
                println!("shipcraft: locked cases still fail; lock {path} stays open.")
            }
            (Change::Opened(_), _) => println!("shipcraft: RED commit checked: lock {path} is committed open."),
            _ => println!("shipcraft: lock {path} closes in this commit."),
        }
    }
    if closing.is_empty() {
        return Ok(());
    }
    println!("shipcraft: all locked cases pass; {} close(s) right after this commit.", closing.join(", "));
    marca::write(repo, closing)
}

const LOCKS: &str = ".shipcraft/locks/";
const EMPTY_BLOBS: [&str; 2] =
    ["e69de29bb2d1d6434b8b29ae775ad8c2e48c5391", "473a0f4c3be8a93681a267e3b1e9a7dcda1185436fe141f7749120a303721813"];

/// Item 28: one line per lock file git leaves out of this commit, up to 5.
fn warn_outside(repo: &Repo) {
    let mut outside = match outside_locks(repo) {
        Ok(outside) => outside,
        Err(e) => {
            let reason = match e {
                Stop::Failed(message) => message,
                Stop::Refused(refusal) => refusal.what().to_string(),
            };
            return println!("shipcraft: warning: could not read {LOCKS} ({reason}).");
        }
    };
    outside.sort_by(|(a, _), (b, _)| (!a.ends_with(".json"), a.as_bytes()).cmp(&(!b.ends_with(".json"), b.as_bytes())));
    outside.dedup();
    for (path, ignored) in outside.iter().take(5) {
        let (add, note) = if *ignored { ("git add -f", " (ignored by git)") } else { ("git add", "") };
        let quoted = path.replace('\'', "'\\''");
        println!(
            "shipcraft: warning: {path} is outside this commit. If this is the RED commit, add the lock: {add} '{quoted}'{note}"
        );
    }
    if outside.len() > 5 {
        println!("shipcraft: warning: and {} more files in {LOCKS} outside this commit.", outside.len() - 5);
    }
}

/// Untracked, ignored (flag true), and index entries holding the empty blob
/// (`git add -N`), read by git with the index git handed the hook.
fn outside_locks(repo: &Repo) -> Result<Vec<(String, bool)>> {
    let names = |bytes: Vec<u8>| bytes.split(|b| *b == 0).filter(|s| !s.is_empty()).map(text).collect::<Vec<_>>();
    let mut outside: Vec<_> = names(repo.run(&["ls-files", "-z", "--others", "--exclude-standard", "--", LOCKS])?)
        .into_iter()
        .map(|p| (p, false))
        .collect();
    let ignored = repo.run(&["ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--", LOCKS])?;
    outside.extend(names(ignored).into_iter().map(|p| (p, true)));
    for entry in names(repo.run(&["ls-files", "-z", "--stage", "--", LOCKS])?) {
        if let Some((meta, path)) = entry.split_once('\t') {
            if meta.split(' ').nth(1).is_some_and(|sha| EMPTY_BLOBS.contains(&sha)) {
                outside.push((path.to_string(), false));
            }
        }
    }
    Ok(outside)
}

/// The lock turns closed inside the commit itself.
fn close(repo: &Repo, path: &str, lock: &Lock) -> Result<()> {
    fs::write(repo.path(path), lock.closed().to_json()).map_err(|e| failed(format!("write {path}: {e}")))?;
    repo.add(path)?;
    println!("shipcraft: all locked cases pass; lock {path} closes in this commit.");
    Ok(())
}
