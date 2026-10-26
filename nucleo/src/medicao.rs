//! Item 10: every hook, CI and review run appends one line to
//! `.git/shipcraft/runs.jsonl` (not versioned), and `shipcraft pr` posts the
//! branch's summary from it.
//!
//! Item 38: every row carries `lock` (the lock id, or empty); the rows run for
//! a PR also carry `locks`, the locks the PR's diff changes.

use crate::config::Config;
use crate::git::{Repo, Snapshot};
use crate::lock::{lock_files, Lock, LOCK_DIR};
use crate::refusal::{Result, Stop};
use serde_json::{json, Value};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

const FILE: &str = "runs.jsonl";
/// Item 11, rule 4: `shipcraft pr` sets the PR's product lines here, so the `ci`
/// (a child process) and `review` rows it causes carry `product_lines`.
pub const LINHAS_ENV: &str = "SHIPCRAFT_PRODUCT_LINES";
pub const LOCKFILES: [&str; 7] =
    ["Cargo.lock", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "go.sum", "poetry.lock", "uv.lock"];
/// Item 38: the locks of the PR being run, as a JSON list, so the `ci` (a child
/// process) and `review` rows it causes carry them.
pub const LOCKS_ENV: &str = "SHIPCRAFT_PR_LOCKS";
const AVISO: &str = "Smaller PRs usually get faster reviews; consider splitting.";

/// Appends a row; measuring never breaks the command it measures.
pub fn record(repo: &Repo, mut row: Value) {
    let Ok(dir) = repo.shipcraft_dir() else { return };
    if let Some(obj) = row.as_object_mut() {
        let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        obj.entry("at").or_insert(json!(now));
        obj.entry("lock").or_insert(json!(""));
        let of_run = matches!(obj["layer"].as_str(), Some("ci" | "review" | "pr"));
        if let (Some(locks), true) = (pr_locks(), of_run) {
            obj.entry("locks").or_insert(json!(locks));
        }
        let lines = std::env::var(LINHAS_ENV).ok().and_then(|v| v.parse::<u64>().ok());
        let of_pr = obj["layer"] == "ci" || obj["layer"] == "review";
        if let (Some(n), true) = (lines, of_pr) {
            obj.insert("product_lines".into(), json!(n));
        }
        // Item 24.2: the files the shape warning named, `null` without N.
        if let (Ok(avisos), true) = (std::env::var(crate::forma::AVISOS_ENV), of_pr) {
            obj.insert("shape_warnings".into(), avisos.parse::<u64>().map_or(Value::Null, |n| json!(n)));
        }
    }
    let _ = fs::create_dir_all(&dir);
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(dir.join(FILE)) {
        let _ = writeln!(file, "{row}");
    }
}

pub fn rows(repo: &Repo) -> Vec<Value> {
    let Ok(dir) = repo.shipcraft_dir() else { return Vec::new() };
    fs::read_to_string(dir.join(FILE))
        .unwrap_or_default()
        .lines()
        .filter_map(|line| serde_json::from_str(line).ok())
        .collect()
}

/// The row of a hook or CI run, from how the command ended; `docs_only` only on
/// CI rows, `lock` on hook rows (the lock open before the hook ran).
pub fn layer(repo: &Repo, camada: &str, started: Instant, result: &Result<()>, docs_only: Option<bool>, lock: Option<String>) {
    let mut row = row(repo, camada, started, result);
    if let Some(lock) = lock {
        row["lock"] = json!(lock);
    }
    if let Some(docs_only) = docs_only {
        row["docs_only"] = json!(docs_only);
    }
    record(repo, row);
}

/// The row of a step, from how the command ended.
pub fn row<T>(repo: &Repo, camada: &str, started: Instant, result: &Result<T>) -> Value {
    let (resultado, codigo) = match result {
        Ok(_) => ("passed", String::new()),
        Err(Stop::Refused(r)) => ("refused", r.code.to_string()),
        Err(Stop::Failed(_)) => ("error", "error".to_string()),
    };
    let mut row = json!({
        "layer": camada,
        "secs": seconds(started),
        "result": resultado,
        "code": codigo,
        "branch": repo.branch(),
        "commit": repo.head().ok().flatten().unwrap_or_default(),
    });
    // The `shipcraft pr` that ran this CI repeats why it refused (item 19.2).
    if let Err(Stop::Refused(r)) = result {
        row["reason"] = json!(r.what());
    }
    row
}

/// Item 38: the id of a lock, its file name without `.json`.
pub fn lock_id(path: &str) -> String {
    std::path::Path::new(path).file_stem().map(|s| s.to_string_lossy().into_owned()).unwrap_or_default()
}

/// The open lock the index carries, or empty: a hook row with none counts
/// only in the hook totals.
pub fn open_lock(repo: &Repo) -> String {
    let Ok(locks) = lock_files(repo, &Snapshot::Index) else { return String::new() };
    locks.iter().find(|(_, bytes)| Lock::parse(bytes).is_none_or(|l| l.is_open())).map_or(String::new(), |(p, _)| lock_id(p))
}

/// The locks whose files changed from the merge-base of `base` and `head` to
/// `head`: the PR's own diff. Best effort: empty when git cannot tell.
pub fn locks_changed(repo: &Repo, base: &str, head: &str) -> Vec<String> {
    let range = format!("{base}...{head}");
    let Ok(out) = repo.run(&["diff", "--name-only", "-z", "--no-renames", &range, "--", LOCK_DIR]) else {
        return Vec::new();
    };
    let mut locks: Vec<String> = String::from_utf8_lossy(&out)
        .split('\0')
        .filter(|p| p.ends_with(".json"))
        .map(lock_id)
        .collect();
    locks.dedup();
    locks
}

/// Sets the PR's locks for the rows this process and its children record.
pub fn set_pr_locks(locks: &[String]) {
    std::env::set_var(LOCKS_ENV, json!(locks).to_string());
}

pub fn pr_locks() -> Option<Vec<String>> {
    serde_json::from_str(&std::env::var(LOCKS_ENV).ok()?).ok()
}

pub fn seconds(started: Instant) -> f64 {
    (started.elapsed().as_secs_f64() * 1000.0).round() / 1000.0
}

/// Item 10, rule 2: refusals and time per layer, and the review's tokens.
pub fn summary(repo: &Repo, branch: &str) -> String {
    let rows: Vec<Value> = rows(repo).into_iter().filter(|r| r["branch"] == branch).collect();
    let mut text = format!(
        "**shipcraft: measurements for branch `{branch}`**\n\n| layer | runs | refusals | errors | time (s) |\n|---|---|---|---|---|\n"
    );
    for camada in ["hook", "ci", "review"] {
        // Item 38: a reused verdict is not a new round.
        let mine: Vec<&Value> = rows.iter().filter(|r| r["layer"] == camada && r["reused"] != true).collect();
        let count = |res: &str| mine.iter().filter(|r| r["result"] == res).count();
        let time: f64 = mine.iter().filter_map(|r| r["secs"].as_f64()).sum();
        let label = if camada == "review" { "review" } else { camada };
        text += &format!("| {label} | {} | {} | {} | {time:.1} |\n", mine.len(), count("refused"), count("error"));
    }
    let tokens: u64 = rows.iter().filter(|r| r["layer"] == "review").filter_map(|r| r["tokens"].as_u64()).sum();
    text += &format!("\nReview tokens: {tokens}\n");
    text
}

/// Item 11, rule 2: product lines `(added, removed)` from `base` to `head`.
/// Out: test and support files, pure renames (0/0 in numstat), the closed
/// list of lockfiles by name, and binaries (`-` in numstat).
pub fn product_lines(repo: &Repo, config: &Config, base: &str, head: &str) -> Result<(u64, u64)> {
    let out = repo.run(&["diff", "--numstat", "-z", "-M", base, head])?;
    let (mut added, mut removed) = (0, 0);
    for (path, counts) in numstat(&out) {
        let name = path.rsplit('/').next().unwrap_or(&path);
        let Some((a, r)) = counts else { continue };
        if !LOCKFILES.contains(&name) && !config.is_test_file(&path) {
            added += a;
            removed += r;
        }
    }
    Ok((added, removed))
}

/// The entries of `git diff --numstat -z`: the path (the new one of a
/// rename) and its counts, None for a file git takes for binary (`-`).
pub fn numstat(out: &[u8]) -> Vec<(String, Option<(u64, u64)>)> {
    let out = String::from_utf8_lossy(out);
    let mut fields = out.split('\0');
    let mut entries = Vec::new();
    while let Some(entry) = fields.next().filter(|e| !e.is_empty()) {
        let mut parts = entry.splitn(3, '\t');
        let (a, r, mut path) = (parts.next().unwrap_or(""), parts.next().unwrap_or(""), parts.next().unwrap_or(""));
        if path.is_empty() {
            // A rename: the old path, then the new one, as their own fields.
            fields.next();
            path = fields.next().unwrap_or("");
        }
        let counts = a.parse::<u64>().ok().zip(r.parse::<u64>().ok());
        entries.push((path.to_string(), counts));
    }
    entries
}

/// Item 11, rules 1 and 3: the size line, and the warning above `[pr] aviso_linhas`.
pub fn size_text(config: &Config, (added, removed): (u64, u64)) -> String {
    let mut text = format!("Size: +{added} / -{removed} product lines\n");
    if added + removed > config.pr.aviso_linhas {
        text += &format!("\n{AVISO}\n");
    }
    text
}
