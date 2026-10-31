//! Item 80: `red` refuses while a file of the Shipcraft install is in the
//! working tree but neither in HEAD nor staged: the hook would read it as a
//! locked file deleted, or a hook file created while the lock is open.

use crate::config::CONFIG_FILE;
use crate::git::{text, Repo};
use crate::init::LEFTHOOK_FILES;
use crate::init_tool::{HUSKY, PRE_COMMIT_CONFIG};
use crate::lock::LOCK_DIR;
use crate::refusal::{failed, refuse, Result};
use std::collections::BTreeSet;
use std::io::ErrorKind;
use std::process::Command;

/// Point 1: the paths `init` writes and git tracks, from the repository root.
fn install_paths() -> Vec<String> {
    let mut paths = vec![
        CONFIG_FILE.to_string(),
        format!("{LOCK_DIR}/.gitkeep"),
        ".shipcraft/briefs/red.md".to_string(),
        ".shipcraft/briefs/green.md".to_string(),
    ];
    paths.extend(HUSKY.iter().map(|(file, _)| file.to_string()));
    paths.push(PRE_COMMIT_CONFIG.to_string());
    paths.extend(LEFTHOOK_FILES.iter().map(|f| f.to_string()));
    paths
}

/// Points 2 to 5: refuses `install-not-committed` when an install path exists
/// in the working tree (or cannot be read) and neither HEAD nor the index has it.
pub fn refuse_if_not_committed(repo: &Repo, redo: bool) -> Result<()> {
    let mut existing = Vec::new();
    // Each uncommitted path, with the lstat error that made it so, if any.
    let mut uncommitted: Vec<(String, Option<String>)> = Vec::new();
    for path in install_paths() {
        match std::fs::symlink_metadata(repo.path(&path)) {
            Ok(_) => existing.push(path),
            Err(e) if matches!(e.kind(), ErrorKind::NotFound | ErrorKind::NotADirectory) => {}
            Err(e) => uncommitted.push((path, Some(e.to_string()))),
        }
    }
    if !existing.is_empty() {
        let mut installed = BTreeSet::new();
        if head_exists(repo)? {
            let mut args = vec!["ls-tree", "-z", "--name-only", "HEAD", "--"];
            args.extend(existing.iter().map(String::as_str));
            installed.extend(listed(repo, &args)?);
        }
        let lacking: Vec<&String> = existing.iter().filter(|p| !installed.contains(*p)).collect();
        if !lacking.is_empty() {
            let mut args = vec!["ls-files", "-z", "--cached", "--"];
            args.extend(lacking.iter().map(|p| p.as_str()));
            installed.extend(listed(repo, &args)?);
        }
        uncommitted.extend(existing.into_iter().filter(|p| !installed.contains(p)).map(|p| (p, None)));
    }
    if uncommitted.is_empty() {
        return Ok(());
    }
    uncommitted.sort_by(|a, b| a.0.as_bytes().cmp(b.0.as_bytes()));
    let shown: Vec<String> = uncommitted
        .iter()
        .map(|(path, error)| match error {
            Some(error) => format!("{path} (could not be read: {error})"),
            None => path.clone(),
        })
        .collect();
    let paths: Vec<&str> = uncommitted.iter().map(|(path, _)| path.as_str()).collect();
    let again = if redo { "shipcraft red --redo" } else { "shipcraft red" };
    refuse(
        "install-not-committed",
        format!("the Shipcraft install is not committed or staged: {}", shown.join(", ")),
        "the lock protects .shipcraft.toml and the hook judges the commit's index against HEAD, so an install file the commit lacks reads as a locked file deleted, or a hook file created while the lock is open, and the RED commit is refused",
        format!(
            "stage the install (`git add -- {}`), with the other files init's `shipcraft: ready. Commit ...` line named when they changed (AGENTS.md, CLAUDE.md, and package.json with its lockfile for a project install), or commit them; then run `{again}` again",
            paths.join(" ")
        ),
    )
}

/// Runs git in the repository root with the exact argv the spec names (no
/// `-C`), pathspecs taken literally through the environment.
fn git(repo: &Repo, args: &[&str]) -> Result<(Option<i32>, Vec<u8>, String)> {
    let out = Command::new("git")
        .current_dir(repo.root())
        .env("GIT_LITERAL_PATHSPECS", "1")
        .args(args)
        .output()
        .map_err(|e| failed(format!("run git: {e}")))?;
    Ok((out.status.code(), out.stdout, text(&out.stderr).trim().to_string()))
}

/// Point 3: `git rev-parse -q --verify HEAD`; exit 1 means unborn.
fn head_exists(repo: &Repo) -> Result<bool> {
    match git(repo, &["rev-parse", "-q", "--verify", "HEAD"])? {
        (Some(0), _, _) => Ok(true),
        (Some(1), _, _) => Ok(false),
        (_, _, stderr) => Err(failed(format!("`git rev-parse HEAD` failed: {stderr}"))),
    }
}

/// The NUL-terminated paths a listing prints; anything else is a failure.
fn listed(repo: &Repo, args: &[&str]) -> Result<Vec<String>> {
    let (code, stdout, stderr) = git(repo, args)?;
    let shown = || args[..args.len().min(4)].join(" ");
    if code != Some(0) {
        return Err(failed(format!("`git {}` failed: {stderr}", shown())));
    }
    if !stdout.is_empty() && stdout.last() != Some(&0) {
        return Err(failed(format!("`git {}` printed output that is not NUL-terminated paths", shown())));
    }
    Ok(stdout.split(|b| *b == 0).filter(|s| !s.is_empty()).map(text).collect())
}
