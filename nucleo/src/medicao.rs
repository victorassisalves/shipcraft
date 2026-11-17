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
use std::process::{Command, Stdio};
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
/// Item 50: Shipcraft's own files, `.shipcraft.toml` at the root and every
/// path under `.shipcraft/`, are not product; matched literally on the
/// repository-relative path git prints (the HEAD path of a rename).
pub fn shipcraft_own(path: &[u8]) -> bool {
    path == b".shipcraft.toml" || path.starts_with(b".shipcraft/")
}
/// The same paths as git pathspecs (whole tree minus Shipcraft's own), so a
/// diff never reads an excluded blob.
pub const NOT_OWN: [&str; 3] = [":(top)", ":(top,literal,exclude).shipcraft.toml", ":(top,literal,exclude).shipcraft/"];
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

/// What a CI run says of itself in its row: whether the PR was docs only
/// (item 40), whether the suite was left to `suite_checks` (item 62), and
/// the failing cases at HEAD when it refused `suite-red` (item 97).
#[derive(Default, Clone)]
pub struct CiRow {
    pub docs_only: bool,
    pub suite_in_checks: bool,
    pub failed: Option<Vec<String>>,
}

/// Item 97: a `suite-red` row lists at most this many failing cases.
const FAILED_MAX: usize = 50;

/// Item 97: the first `FAILED_MAX` failing ids, in the order given (byte
/// order), and how many failed in all.
fn put_failed(row: &mut Value, failed: &[String]) {
    row["failed"] = json!(failed.iter().take(FAILED_MAX).collect::<Vec<_>>());
    row["failed_count"] = json!(failed.len());
}

/// The row of a hook or CI run, from how the command ended; `ci` only on
/// CI rows, `lock` on hook rows (the lock open before the hook ran).
pub fn layer(repo: &Repo, camada: &str, started: Instant, result: &Result<()>, ci: Option<CiRow>, lock: Option<String>) {
    let mut row = row(repo, camada, started, result);
    if let Some(lock) = lock {
        row["lock"] = json!(lock);
    }
    if let Some(ci) = ci {
        row["docs_only"] = json!(ci.docs_only);
        row["suite_in_checks"] = json!(ci.suite_in_checks);
        if let Some(failed) = &ci.failed {
            put_failed(&mut row, failed);
        }
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
    locks
        .iter()
        .find(|(_, bytes)| Lock::parse(bytes).is_none_or(|l| l.is_open()))
        .map_or(String::new(), |(p, _)| lock_id(p))
}

/// The locks whose files changed from the merge-base of `base` and `head` to
/// `head`: the PR's own diff. Best effort: empty when git cannot tell.
pub fn locks_changed(repo: &Repo, base: &str, head: &str) -> Vec<String> {
    let range = format!("{base}...{head}");
    let Ok(out) = repo.run(&["diff", "--name-only", "-z", "--no-renames", &range, "--", LOCK_DIR]) else {
        return Vec::new();
    };
    let mut locks: Vec<String> =
        String::from_utf8_lossy(&out).split('\0').filter(|p| p.ends_with(".json")).map(lock_id).collect();
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

/// Item 108: the attribute that marks a generated file.
const GENERATED_ATTR: &[u8] = b"linguist-generated";
const ATTR_UNREADABLE: &str = "git check-attr gave an unreadable answer";
const ATTR_FAILED: &str = "git check-attr failed";

/// Item 11, rule 2: product lines `(added, removed)` from `base` to `head`.
/// Out: test and support files, pure renames (0/0 in numstat), the closed
/// list of lockfiles by name, binaries (`-` in numstat), Shipcraft's own
/// files (item 50) and, since item 108, the files the head commit marks
/// `linguist-generated`. The second value is the reason when git could not
/// say which files are generated: then none is left out, for the whole PR.
pub fn product_lines(repo: &Repo, config: &Config, base: &str, head: &str) -> Result<((u64, u64), Option<String>)> {
    let out = repo.run(&["diff", "--numstat", "-z", "-M", base, head])?;
    let entries = numstat_raw(&out);
    let (generated, reason) = match generated(repo, head, &entries) {
        Ok(marks) => (marks, None),
        Err(reason) => (vec![false; entries.len()], Some(reason)),
    };
    let (mut added, mut removed) = (0, 0);
    for ((path, counts), generated) in entries.iter().zip(generated) {
        // The rest of the classification reads the path as item 11 does.
        let path = String::from_utf8_lossy(path);
        let name = path.rsplit('/').next().unwrap_or(&path);
        let Some((a, r)) = counts else { continue };
        if !generated && !LOCKFILES.contains(&name) && !config.is_test_file(&path) && !shipcraft_own(path.as_bytes()) {
            added += a;
            removed += r;
        }
    }
    Ok(((added, removed), reason))
}

/// Item 108: which of the numstat's paths the head commit's `.gitattributes`
/// mark generated, by one `git check-attr` over all of them; no call when
/// the diff names no path. `Err` is the reason of the warning line.
fn generated(repo: &Repo, head: &str, entries: &[(Vec<u8>, Option<(u64, u64)>)]) -> std::result::Result<Vec<bool>, String> {
    if entries.is_empty() {
        return Ok(Vec::new());
    }
    let paths: Vec<&[u8]> = entries.iter().map(|(path, _)| path.as_slice()).collect();
    let mut input = Vec::new();
    for path in &paths {
        input.extend_from_slice(path);
        input.push(0);
    }
    let spawned = Command::new("git")
        .arg("-C")
        .arg(repo.root())
        .arg("--literal-pathspecs")
        .args(["check-attr", &format!("--source={head}"), "-z", "--stdin", "linguist-generated"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn();
    let Ok(mut child) = spawned else { return Err(ATTR_FAILED.to_string()) };
    // The paths are written beside the read, so a long list never blocks on
    // a full pipe; dropping the handle closes git's stdin.
    let stdin = child.stdin.take();
    let writer = std::thread::spawn(move || match stdin {
        Some(mut stdin) => stdin.write_all(&input).and_then(|()| stdin.flush()).is_ok(),
        None => false,
    });
    let out = child.wait_with_output();
    let written = writer.join().unwrap_or(false);
    let Ok(out) = out else { return Err(ATTR_FAILED.to_string()) };
    if !written || !out.status.success() {
        return Err(attr_failure(&out.stderr));
    }
    attr_answer(&paths, &out.stdout).ok_or_else(|| ATTR_UNREADABLE.to_string())
}

/// The reason of a failed `git check-attr`: the first non-empty line of its
/// stderr, without its trailing CR.
fn attr_failure(stderr: &[u8]) -> String {
    let text = String::from_utf8_lossy(stderr);
    text.split('\n')
        .map(|line| line.strip_suffix('\r').unwrap_or(line))
        .find(|line| !line.is_empty())
        .map_or_else(|| ATTR_FAILED.to_string(), str::to_string)
}

/// Item 108: reads the answer of `git check-attr -z` for `paths`, as raw
/// bytes. It fits when, split at every NUL, it is three fields per path
/// (the path asked at that position, the attribute's name, the value) and
/// one empty remainder. Generated is the value `set` or `true`, nothing else.
fn attr_answer(paths: &[&[u8]], answer: &[u8]) -> Option<Vec<bool>> {
    let fields: Vec<&[u8]> = answer.split(|b| *b == 0).collect();
    if fields.len() != paths.len() * 3 + 1 || !fields[fields.len() - 1].is_empty() {
        return None;
    }
    let mut marks = Vec::with_capacity(paths.len());
    for (path, record) in paths.iter().zip(fields.chunks_exact(3)) {
        if record[0] != *path || record[1] != GENERATED_ATTR {
            return None;
        }
        marks.push(record[2] == b"set" || record[2] == b"true");
    }
    Some(marks)
}

/// The entries of `git diff --numstat -z` with the path as the bytes git
/// printed (item 108): the same entries as `numstat`, whose path is the
/// lossy text of these bytes.
fn numstat_raw(out: &[u8]) -> Vec<(Vec<u8>, Option<(u64, u64)>)> {
    let mut fields = out.split(|b| *b == 0);
    let mut entries = Vec::new();
    while let Some(entry) = fields.next().filter(|e| !e.is_empty()) {
        let mut parts = entry.splitn(3, |b| *b == b'\t');
        let empty: &[u8] = b"";
        let (a, r, mut path) = (parts.next().unwrap_or(empty), parts.next().unwrap_or(empty), parts.next().unwrap_or(empty));
        if path.is_empty() {
            // A rename: the old path, then the new one, as their own fields.
            fields.next();
            path = fields.next().unwrap_or(empty);
        }
        let count = |field: &[u8]| std::str::from_utf8(field).ok().and_then(|n| n.parse::<u64>().ok());
        entries.push((path.to_vec(), count(a).zip(count(r))));
    }
    entries
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

#[cfg(test)]
mod tests {
    use super::{attr_answer, attr_failure, numstat, numstat_raw, put_failed, FAILED_MAX};
    use serde_json::json;

    #[test]
    fn failed_keeps_the_first_fifty_and_counts_all() {
        let ids: Vec<String> = (0..51).map(|i| format!("t::case_{i:02}")).collect();
        let mut row = json!({"layer": "ci"});
        put_failed(&mut row, &ids);
        assert_eq!(row["failed"], json!(ids[..FAILED_MAX]));
        assert_eq!(row["failed"].as_array().unwrap().len(), 50);
        assert_eq!(row["failed"][49], "t::case_49");
        assert_eq!(row["failed_count"], 51);
    }

    #[test]
    fn failed_under_the_cut_is_whole() {
        let mut row = json!({"layer": "ci"});
        put_failed(&mut row, &["api:t::x".to_string()]);
        assert_eq!(row["failed"], json!(["api:t::x"]));
        assert_eq!(row["failed_count"], 1);
    }
    fn answer(records: &[(&[u8], &str, &str)]) -> Vec<u8> {
        let mut out = Vec::new();
        for (path, attr, value) in records {
            out.extend_from_slice(path);
            out.push(0);
            out.extend_from_slice(attr.as_bytes());
            out.push(0);
            out.extend_from_slice(value.as_bytes());
            out.push(0);
        }
        out
    }

    const ATTR: &str = "linguist-generated";

    #[test]
    fn attr_answer_reads_each_value() {
        let values = ["set", "true", "unset", "false", "unspecified", "TRUE", "yes", "1", "", "True", "set "];
        let names: Vec<Vec<u8>> = (0..values.len()).map(|i| format!("gen/f{i}.ts").into_bytes()).collect();
        let paths: Vec<&[u8]> = names.iter().map(Vec::as_slice).collect();
        let records: Vec<(&[u8], &str, &str)> = paths.iter().zip(values).map(|(p, v)| (*p, ATTR, v)).collect();
        let marks = attr_answer(&paths, &answer(&records)).unwrap();
        assert_eq!(marks, [true, true, false, false, false, false, false, false, false, false, false]);
    }

    #[test]
    fn attr_answer_matches_raw_path_bytes() {
        let odd: &[u8] = b"gen/\xff\xfe\n\t \"x\".ts";
        let paths: [&[u8]; 2] = [odd, b"src/a.rs"];
        let fit = answer(&[(odd, ATTR, "set"), (b"src/a.rs", ATTR, "unspecified")]);
        assert_eq!(attr_answer(&paths, &fit), Some(vec![true, false]));
        // The lossy text of the path is not the path.
        let lossy = String::from_utf8_lossy(odd).into_owned();
        let other = answer(&[(lossy.as_bytes(), ATTR, "set"), (b"src/a.rs", ATTR, "unspecified")]);
        assert_eq!(attr_answer(&paths, &other), None);
    }

    #[test]
    fn attr_answer_that_does_not_fit_is_none() {
        let paths: [&[u8]; 2] = [b"a.ts", b"b.ts"];
        let fit = answer(&[(b"a.ts", ATTR, "set"), (b"b.ts", ATTR, "unset")]);
        assert_eq!(attr_answer(&paths, &fit), Some(vec![true, false]));
        // A wrong path at a position, the two swapped included.
        assert_eq!(attr_answer(&paths, &answer(&[(b"a.ts", ATTR, "set"), (b"c.ts", ATTR, "unset")])), None);
        assert_eq!(attr_answer(&paths, &answer(&[(b"b.ts", ATTR, "unset"), (b"a.ts", ATTR, "set")])), None);
        assert_eq!(attr_answer(&paths, &answer(&[(b"./a.ts", ATTR, "set"), (b"b.ts", ATTR, "unset")])), None);
        // A wrong attribute name.
        assert_eq!(attr_answer(&paths, &answer(&[(b"a.ts", ATTR, "set"), (b"b.ts", "linguist-vendored", "set")])), None);
        assert_eq!(attr_answer(&paths, &answer(&[(b"a.ts", "Linguist-Generated", "set"), (b"b.ts", ATTR, "set")])), None);
        // No final NUL.
        assert_eq!(attr_answer(&paths, &fit[..fit.len() - 1]), None);
        // Bytes left over after the last record.
        assert_eq!(attr_answer(&paths, &[fit.as_slice(), b"x"].concat()), None);
        assert_eq!(attr_answer(&paths, &[fit.as_slice(), b"\n"].concat()), None);
        assert_eq!(attr_answer(&paths, &[fit.as_slice(), b"\0"].concat()), None);
        // Fewer records, and more.
        assert_eq!(attr_answer(&paths, &answer(&[(b"a.ts", ATTR, "set")])), None);
        assert_eq!(attr_answer(&paths, b""), None);
        let more = answer(&[(b"a.ts", ATTR, "set"), (b"b.ts", ATTR, "unset"), (b"b.ts", ATTR, "unset")]);
        assert_eq!(attr_answer(&paths, &more), None);
        // A record cut short, and the newline framing of a call without -z.
        assert_eq!(attr_answer(&paths, b"a.ts\0linguist-generated\0set\0b.ts\0linguist-generated\0"), None);
        assert_eq!(attr_answer(&paths, b"a.ts: linguist-generated: set\nb.ts: linguist-generated: unset\n"), None);
    }

    #[test]
    fn attr_failure_is_the_first_non_empty_stderr_line() {
        assert_eq!(attr_failure(b"error: unknown option `source=abc'\nusage: git check-attr\n"), "error: unknown option `source=abc'");
        assert_eq!(attr_failure(b"\n\r\nfatal: bad\r\nmore\n"), "fatal: bad");
        assert_eq!(attr_failure(b"fatal: no newline"), "fatal: no newline");
        assert_eq!(attr_failure(b""), "git check-attr failed");
        assert_eq!(attr_failure(b"\n\r\n"), "git check-attr failed");
    }

    #[test]
    fn numstat_raw_gives_the_entries_of_numstat() {
        let out: &[u8] = b"3\t1\tsrc/a.rs\0-\t-\timg.png\x000\t0\t\0old.rs\0new.rs\x002\t0\tgen/\xff.ts\x005\t5\tdir/Cargo.lock\0";
        let raw = numstat_raw(out);
        let lossy: Vec<(String, Option<(u64, u64)>)> =
            raw.iter().map(|(p, c)| (String::from_utf8_lossy(p).into_owned(), *c)).collect();
        assert_eq!(lossy, numstat(out));
        assert_eq!(raw.len(), 5);
        assert_eq!(raw[1], (b"img.png".to_vec(), None));
        assert_eq!(raw[2], (b"new.rs".to_vec(), Some((0, 0))));
        assert_eq!(raw[3], (b"gen/\xff.ts".to_vec(), Some((2, 0))));
        assert!(numstat_raw(b"").is_empty());
    }
}
