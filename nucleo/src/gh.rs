//! The GitHub calls, all through `gh` (the surface in acceptance/README.md).
//! Errors come back as the text `gh` printed, so callers can tell a 403 from a 404.

use crate::git::{Repo, TempDir};
use crate::refusal::{failed, Result};
use serde_json::Value;
use std::collections::BTreeMap;
use std::fs;
use std::process::Command;

/// `gh <args>` in the repository root: stdout, or the error text.
pub fn run(repo: &Repo, args: &[&str]) -> std::result::Result<String, String> {
    let out = Command::new("gh").args(args).current_dir(repo.root()).output().map_err(|e| format!("run gh: {e}"))?;
    let stdout = String::from_utf8_lossy(&out.stdout).into_owned();
    if out.status.success() {
        Ok(stdout)
    } else {
        Err(format!("{} {}", String::from_utf8_lossy(&out.stderr).trim(), stdout.trim()).trim().to_string())
    }
}

/// `gh <args>`, a failure of shipcraft when gh fails.
pub fn must(repo: &Repo, args: &[&str]) -> Result<String> {
    run(repo, args).map_err(|e| failed(format!("`gh {}` failed: {e}", args.join(" "))))
}

pub fn json(repo: &Repo, args: &[&str]) -> Result<Value> {
    let out = must(repo, args)?;
    serde_json::from_str(&out).map_err(|e| failed(format!("`gh {}` did not return JSON: {e}", args.join(" "))))
}

/// `gh <args> --input <file>` with `body` in the file.
pub fn with_input(repo: &Repo, args: &[&str], body: &str) -> std::result::Result<String, String> {
    let dir = TempDir::new("shipcraft-gh").map_err(|_| "temporary directory".to_string())?;
    let file = dir.path().join("corpo.json");
    fs::write(&file, body).map_err(|e| e.to_string())?;
    let file = file.to_string_lossy().into_owned();
    let mut all: Vec<&str> = args.to_vec();
    all.extend(["--input", &file]);
    run(repo, &all)
}

/// A file holding `text`, for `--body-file` (kept while the TempDir lives).
fn body_file(text: &str) -> Result<(TempDir, String)> {
    let dir = TempDir::new("shipcraft-gh")?;
    let file = dir.path().join("corpo.md");
    fs::write(&file, text).map_err(|e| failed(format!("write {}: {e}", file.display())))?;
    let file = file.to_string_lossy().into_owned();
    Ok((dir, file))
}

/// Publishes a commit status (GitHub keeps at most 140 characters of description).
pub fn status(repo: &Repo, sha: &str, context: &str, state: &str, description: &str) -> Result<()> {
    let description: String = description.chars().take(140).collect();
    must(
        repo,
        &[
            "api",
            "-X",
            "POST",
            &format!("repos/{{owner}}/{{repo}}/statuses/{sha}"),
            "-f",
            &format!("state={state}"),
            "-f",
            &format!("context={context}"),
            "-f",
            &format!("description={description}"),
        ],
    )
    .map(drop)
}

/// The latest status of each context on a commit: context -> (state, description).
pub fn statuses(repo: &Repo, sha: &str) -> Result<BTreeMap<String, (String, String)>> {
    let list = json(repo, &["api", &format!("repos/{{owner}}/{{repo}}/commits/{sha}/statuses")])?;
    let mut latest = BTreeMap::new();
    // GitHub lists the newest first.
    for s in list.as_array().into_iter().flatten() {
        let context = s["context"].as_str().unwrap_or_default().to_string();
        let state = s["state"].as_str().unwrap_or_default().to_string();
        let description = s["description"].as_str().unwrap_or_default().to_string();
        latest.entry(context).or_insert((state, description));
    }
    Ok(latest)
}

pub fn comment(repo: &Repo, pr: u64, text: &str) -> Result<()> {
    let (_dir, file) = body_file(text)?;
    must(repo, &["pr", "comment", &pr.to_string(), "--body-file", &file]).map(drop)
}

/// The open PR of a branch: (number, body).
/// Item 54: the body is `None` when gh's field is missing, null or not a string.
pub fn open_pr(repo: &Repo, branch: &str) -> Result<Option<(u64, Option<String>)>> {
    let list = json(repo, &["pr", "list", "--head", branch, "--state", "open", "--json", "number,body"])?;
    Ok(list
        .as_array()
        .and_then(|l| l.first())
        .map(|pr| (pr["number"].as_u64().unwrap_or(0), pr["body"].as_str().map(str::to_string))))
}

pub fn create_pr(repo: &Repo, branch: &str, base: &str, title: &str, body: &str) -> Result<u64> {
    let (_dir, file) = body_file(body)?;
    let out = must(repo, &["pr", "create", "--title", title, "--body-file", &file, "--base", base, "--head", branch])?;
    out.trim()
        .rsplit('/')
        .next()
        .and_then(|n| n.parse().ok())
        .ok_or_else(|| failed(format!("`gh pr create` did not return the PR number: {out}")))
}

pub fn edit_pr(repo: &Repo, pr: u64, title: Option<&str>, body: Option<&str>) -> Result<()> {
    let n = pr.to_string();
    let mut args = vec!["pr", "edit", &n];
    if let Some(title) = title {
        args.extend(["--title", title]);
    }
    let file;
    let _dir;
    if let Some(body) = body {
        (_dir, file) = body_file(body)?;
        args.extend(["--body-file", &file]);
    }
    must(repo, &args).map(drop)
}
