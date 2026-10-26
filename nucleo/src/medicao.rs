//! Item 10: every hook, CI and review run appends one line to
//! `.git/shipcraft/runs.jsonl` (not versioned), and `shipcraft pr` posts the
//! branch's summary from it.

use crate::config::Config;
use crate::git::Repo;
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
const AVISO: &str = "Smaller PRs usually get faster reviews; consider splitting.";

/// Appends a row; measuring never breaks the command it measures.
pub fn record(repo: &Repo, mut row: Value) {
    let Ok(dir) = repo.shipcraft_dir() else { return };
    if let Some(obj) = row.as_object_mut() {
        let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
        obj.entry("at").or_insert(json!(now));
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

/// The row of a hook or CI run, from how the command ended.
pub fn layer(repo: &Repo, camada: &str, started: Instant, result: &Result<()>) {
    let (resultado, codigo) = match result {
        Ok(()) => ("passed", String::new()),
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
    record(repo, row);
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
        let mine: Vec<&Value> = rows.iter().filter(|r| r["layer"] == camada).collect();
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
