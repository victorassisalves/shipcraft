//! Item 38: `shipcraft report [--json]`, the flow measured from the run log.
//! It finds `.git` by walking up from the current directory and never refuses.
//! Item 76: `[--since <tag>]`, and a local DORA readout from the run log, the
//! release tags and the lock files, read through `git -C <root>` read-only, with
//! no network read; a key without data says so with a count.

use crate::lock::{self, Lock};
use crate::refusal::Result;
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

type Row = Map<String, Value>;

pub fn run(as_json: bool, since: Option<&str>) -> Result<()> {
    let found = discover();
    let bytes = found.as_ref().and_then(|(_, log)| fs::read(log).ok()).unwrap_or_default();
    let (rows, gaps) = read(&bytes);
    let mut ids: Vec<String> = Vec::new();
    for id in rows.iter().flat_map(locks_of) {
        if !ids.contains(&id) {
            ids.push(id);
        }
    }
    let evidence = match &found {
        Some((root, _)) => Evidence::read(&Git { root: root.clone() }, &ids),
        None => Err("no git repository found".to_string()),
    };
    if let (Some(tag), Ok(ev)) = (since, &evidence) {
        if !ev.releases.iter().any(|r| r.name == tag) {
            eprintln!("report: --since {tag} is not a release tag on {}", ev.branch);
            std::process::exit(2);
        }
    }
    let facts = evidence.as_ref().ok().map(|ev| Facts::of(ev, &rows, &ids));
    let report = Report::of(&rows, &ids, facts.as_ref());
    let dora = dora(&rows, evidence.as_ref().map(|ev| (ev, facts.as_ref().expect("facts with evidence"))), since);
    let gaps: Vec<Value> =
        gaps.into_iter().map(|(line, reason)| json!({"kind": "gap", "line": line, "reason": reason})).collect();
    let lines: Vec<Value> = [report.meta.clone()]
        .into_iter()
        .chain(report.locks.clone())
        .chain(report.days.clone())
        .chain([dora])
        .chain(gaps)
        .collect();
    if as_json {
        for line in &lines {
            println!("{line}");
        }
    } else {
        print!("{}", text(&lines));
    }
    Ok(())
}

/// The folder holding the `.git` (directory or file) found by walking up from
/// the current directory, and `<common git dir>/shipcraft/runs.jsonl`, the run
/// log `medicao` writes, found without git: a `.git` file (`gitdir: <dir>`)
/// leads to its `commondir`.
fn discover() -> Option<(PathBuf, PathBuf)> {
    let cwd = std::env::current_dir().ok()?;
    let dot = cwd.ancestors().map(|d| d.join(".git")).find(|p| p.exists())?;
    let root = dot.parent()?.to_path_buf();
    let git_dir = if dot.is_dir() {
        dot
    } else {
        let content = fs::read_to_string(&dot).ok()?;
        let dir = Path::new(content.trim().strip_prefix("gitdir:")?.trim());
        root.join(dir)
    };
    let common = match fs::read_to_string(git_dir.join("commondir")) {
        Ok(rel) => git_dir.join(rel.trim()),
        Err(_) => git_dir,
    };
    Some((root, common.join("shipcraft").join("runs.jsonl")))
}

/// Every variable `git rev-parse --local-env-vars` names, plus the ceiling:
/// an inherited environment never selects another repository.
const REPOSITORY_VARS: [&str; 16] = [
    "GIT_ALTERNATE_OBJECT_DIRECTORIES",
    "GIT_CONFIG",
    "GIT_CONFIG_PARAMETERS",
    "GIT_CONFIG_COUNT",
    "GIT_OBJECT_DIRECTORY",
    "GIT_DIR",
    "GIT_WORK_TREE",
    "GIT_IMPLICIT_WORK_TREE",
    "GIT_GRAFT_FILE",
    "GIT_INDEX_FILE",
    "GIT_NO_REPLACE_OBJECTS",
    "GIT_REPLACE_REF_BASE",
    "GIT_PREFIX",
    "GIT_SHALLOW_FILE",
    "GIT_COMMON_DIR",
    "GIT_CEILING_DIRECTORIES",
];

/// Read-only git at the discovered root, with no lazy fetch and no prompt.
struct Git {
    root: PathBuf,
}

impl Git {
    /// The exit code and stdout; Err when git cannot run.
    fn call(&self, args: &[&str]) -> std::result::Result<(Option<i32>, Vec<u8>), String> {
        let mut command = Command::new("git");
        command.arg("-C").arg(&self.root).args(args);
        command.env("GIT_NO_LAZY_FETCH", "1").env("GIT_TERMINAL_PROMPT", "0");
        for var in REPOSITORY_VARS {
            command.env_remove(var);
        }
        let out = command
            .stdin(Stdio::null())
            .stderr(Stdio::null())
            .output()
            .map_err(|e| format!("git failed: cannot run git: {e}"))?;
        Ok((out.status.code(), out.stdout))
    }

    /// Exit 0's stdout; anything else is a failure.
    fn ok(&self, args: &[&str]) -> std::result::Result<Vec<u8>, String> {
        match self.call(args)? {
            (Some(0), out) => Ok(out),
            (code, _) => Err(failure(args, code)),
        }
    }

    /// Exit 0's stdout, or None for exit 1 with no output (absent, not a failure).
    fn maybe(&self, args: &[&str]) -> std::result::Result<Option<Vec<u8>>, String> {
        match self.call(args)? {
            (Some(0), out) => Ok(Some(out)),
            (Some(1), out) if out.is_empty() => Ok(None),
            (code, _) => Err(failure(args, code)),
        }
    }

    /// The commit a ref or tag names, or None when absent or not a commit.
    fn commit(&self, name: &str) -> std::result::Result<Option<String>, String> {
        let spec = format!("{name}^{{commit}}");
        let args = ["rev-parse", "--verify", "-q", spec.as_str()];
        match self.maybe(&args)? {
            None => Ok(None),
            Some(out) => {
                let sha = utf8(&args, out)?.trim().to_string();
                if sha.is_empty() || !sha.bytes().all(|b| b.is_ascii_hexdigit()) {
                    return Err(unreadable(&args));
                }
                Ok(Some(sha))
            }
        }
    }

    /// The lock files at a commit: id -> blob id.
    fn locks(&self, commit: &str) -> std::result::Result<BTreeMap<String, String>, String> {
        let args = ["ls-tree", "-z", commit, "--", ".shipcraft/locks/"];
        let out = self.ok(&args)?;
        let mut locks = BTreeMap::new();
        for entry in out.split(|b| *b == 0).filter(|e| !e.is_empty()) {
            let entry = std::str::from_utf8(entry).map_err(|_| unreadable(&args))?;
            let (meta, path) = entry.split_once('\t').ok_or_else(|| unreadable(&args))?;
            let fields: Vec<&str> = meta.split(' ').collect();
            let [_, kind, oid] = fields[..] else { return Err(unreadable(&args)) };
            let Some(id) = path.strip_prefix(".shipcraft/locks/").and_then(|p| p.strip_suffix(".json")) else {
                continue;
            };
            if kind == "blob" && !id.is_empty() && !id.contains('/') {
                locks.insert(id.to_string(), oid.to_string());
            }
        }
        Ok(locks)
    }
}

fn failure(args: &[&str], code: Option<i32>) -> String {
    match code {
        Some(code) => format!("git failed: `git {}` exited {code}", args.join(" ")),
        None => format!("git failed: `git {}` was stopped by a signal", args.join(" ")),
    }
}

fn unreadable(args: &[&str]) -> String {
    format!("git failed: `git {}` printed unreadable output", args.join(" "))
}

fn utf8(args: &[&str], out: Vec<u8>) -> std::result::Result<String, String> {
    String::from_utf8(out).map_err(|_| unreadable(args))
}

/// A release: a `vX.Y.Z` tag whose commit is on the default branch.
struct Release {
    name: String,
    time: i64,
    locks: BTreeMap<String, String>,
}

/// A lock's fix data: `change_kind`, `reported_at`, `fixes_release`.
#[derive(Clone, Default)]
struct FixData {
    kind: Option<String>,
    reported_at: Option<String>,
    fixes_release: Option<String>,
}

/// What git says, all read before anything is reported: one failure makes
/// every git-derived value null.
struct Evidence {
    branch: String,
    tip: BTreeMap<String, String>,
    /// Ordered by time, then by version.
    releases: Vec<Release>,
    /// Fix data from the first valid lock file among the tip, the latest
    /// release that holds it and HEAD; absent when none has one.
    files: BTreeMap<String, FixData>,
}

impl Evidence {
    fn read(git: &Git, log_ids: &[String]) -> std::result::Result<Evidence, String> {
        let probe = ["config", "--get-regexp", r"^(extensions\.partialclone|remote\..*\.promisor)$"];
        if let Some(out) = git.maybe(&probe)? {
            if partial(&utf8(&probe, out)?) {
                return Err("partial clone: report reads no network".to_string());
            }
        }
        let shallow = ["rev-parse", "--is-shallow-repository"];
        match utf8(&shallow, git.ok(&shallow)?)?.trim_end_matches('\n') {
            "true" => return Err("shallow clone: history incomplete".to_string()),
            "false" => {}
            _ => return Err(unreadable(&shallow)),
        }
        let mut default = None;
        for name in ["refs/remotes/origin/HEAD", "refs/remotes/origin/main", "refs/heads/main", "refs/heads/master"] {
            if let Some(commit) = git.commit(name)? {
                default = Some((name.to_string(), commit));
                break;
            }
        }
        let Some((branch, tip_commit)) = default else { return Err("no default branch".to_string()) };
        let list = ["for-each-ref", "refs/tags", "--format=%(refname:strip=2)"];
        let names = utf8(&list, git.ok(&list)?)?;
        let mut releases = Vec::new();
        let mut commits = BTreeMap::new();
        for name in names.lines().filter(|n| lock::valid_tag(n)) {
            let Some(commit) = git.commit(&format!("refs/tags/{name}"))? else { continue };
            let ancestry = ["merge-base", "--is-ancestor", commit.as_str(), tip_commit.as_str()];
            match git.call(&ancestry)? {
                (Some(0), _) => {}
                (Some(1), _) => continue,
                (code, _) => return Err(failure(&ancestry, code)),
            }
            let time = release_time(git, name, &commit)?;
            let locks = git.locks(&commit)?;
            commits.insert(name.to_string(), commit);
            releases.push(Release { name: name.to_string(), time, locks });
        }
        releases.sort_by(|a, b| a.time.cmp(&b.time).then_with(|| version_cmp(&a.name, &b.name)));
        let tip = git.locks(&tip_commit)?;
        let head = match git.commit("HEAD")? {
            Some(commit) => Some((git.locks(&commit)?, commit)),
            None => None,
        };
        let mut population: BTreeSet<String> = log_ids.iter().cloned().collect();
        population.extend(tip.keys().cloned());
        for release in &releases {
            population.extend(release.locks.keys().cloned());
        }
        let mut parsed: BTreeMap<String, Option<Lock>> = BTreeMap::new();
        let mut files = BTreeMap::new();
        for id in population {
            let mut sources: Vec<(&str, &String)> = Vec::new();
            if let Some(oid) = tip.get(&id) {
                sources.push((tip_commit.as_str(), oid));
            }
            for release in releases.iter().rev() {
                if let Some(oid) = release.locks.get(&id) {
                    sources.push((commits[&release.name].as_str(), oid));
                }
            }
            if let Some((locks, commit)) = &head {
                if let Some(oid) = locks.get(&id) {
                    sources.push((commit.as_str(), oid));
                }
            }
            for (commit, oid) in sources {
                if !parsed.contains_key(oid) {
                    let spec = format!("{commit}:.shipcraft/locks/{id}.json");
                    let bytes = git.ok(&["cat-file", "blob", spec.as_str()])?;
                    // Item 76, point 1: only a lock valid by this binary's rules
                    // (a supported format, seal included) ends the search.
                    let lock = lock::check_format(&spec, &bytes).ok().and_then(|()| Lock::parse(&bytes));
                    parsed.insert(oid.clone(), lock);
                }
                if let Some(lock) = &parsed[oid] {
                    let data = match &lock.fix {
                        Some(fix) => FixData {
                            kind: Some(fix.kind.as_str().to_string()),
                            reported_at: fix.reported_at.clone(),
                            fixes_release: fix.fixes_release.clone(),
                        },
                        None => FixData::default(),
                    };
                    files.insert(id.clone(), data);
                    break;
                }
            }
        }
        Ok(Evidence { branch, tip, releases, files })
    }
}

/// A partial clone: `extensions.partialclone` with a value, or a
/// `remote.<name>.promisor` that is true in git's boolean spellings.
fn partial(config: &str) -> bool {
    config.lines().any(|line| {
        let (key, value) = match line.split_once(' ') {
            Some((key, value)) => (key, Some(value)),
            None => (line, None),
        };
        let key = key.to_ascii_lowercase();
        if key == "extensions.partialclone" {
            return value.is_some_and(|v| !v.is_empty());
        }
        key.starts_with("remote.")
            && key.ends_with(".promisor")
            && value.is_none_or(|v| ["true", "yes", "on", "1"].contains(&v.to_ascii_lowercase().as_str()))
    })
}

/// The tagger date of an annotated tag that has one, else the commit's
/// committer date, read with no signature verifier.
fn release_time(git: &Git, name: &str, commit: &str) -> std::result::Result<i64, String> {
    let pattern = format!("refs/tags/{name}");
    let args = ["for-each-ref", pattern.as_str(), "--format=%(objecttype) %(taggerdate:unix)"];
    let out = utf8(&args, git.ok(&args)?)?;
    let line = out.lines().next().ok_or_else(|| unreadable(&args))?;
    let (kind, date) = line.split_once(' ').ok_or_else(|| unreadable(&args))?;
    if kind == "tag" && !date.is_empty() {
        return seconds(date).ok_or_else(|| unreadable(&args));
    }
    let args = ["-c", "log.showSignature=false", "log", "--no-show-signature", "-1", "--format=%ct", commit];
    let out = utf8(&args, git.ok(&args)?)?;
    seconds(out.trim_end_matches('\n')).ok_or_else(|| unreadable(&args))
}

fn seconds(text: &str) -> Option<i64> {
    let digits = text.strip_prefix('-').unwrap_or(text);
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    text.parse().ok()
}

/// `vX.Y.Z` by major, minor, patch as decimal numbers of any length.
fn version_cmp(a: &str, b: &str) -> std::cmp::Ordering {
    let parts = |t: &str| t.trim_start_matches('v').split('.').map(str::to_string).collect::<Vec<_>>();
    let (a, b) = (parts(a), parts(b));
    a.iter()
        .zip(&b)
        .map(|(x, y)| x.len().cmp(&y.len()).then_with(|| x.cmp(y)))
        .find(|o| o.is_ne())
        .unwrap_or(std::cmp::Ordering::Equal)
}

/// Per lock id: its fix data and its release (index into the releases).
struct Facts {
    tip: BTreeSet<String>,
    fix: BTreeMap<String, FixData>,
    release: BTreeMap<String, usize>,
}

impl Facts {
    fn of(ev: &Evidence, rows: &[Row], log_ids: &[String]) -> Facts {
        let mut fix = BTreeMap::new();
        let mut release = BTreeMap::new();
        let mut population: BTreeSet<&String> = log_ids.iter().collect();
        population.extend(ev.tip.keys());
        for (i, r) in ev.releases.iter().enumerate() {
            for id in r.locks.keys() {
                population.insert(id);
                release.entry(id.clone()).or_insert(i);
            }
        }
        for id in population {
            let data = match ev.files.get(id) {
                Some(data) => data.clone(),
                None => red_row(rows, id).map(fix_of_row).unwrap_or_default(),
            };
            fix.insert(id.clone(), data);
        }
        Facts { tip: ev.tip.keys().cloned().collect(), fix, release }
    }
}

/// The fix data a `red` row carries, each field in its grammar.
fn fix_of_row(row: &Row) -> FixData {
    let kind = row.get("kind").and_then(Value::as_str).filter(|k| *k == "feature" || *k == "fix");
    let field = |key: &str, valid: fn(&str) -> bool| row.get(key).and_then(Value::as_str).filter(|v| valid(v));
    FixData {
        kind: kind.map(str::to_string),
        reported_at: field("reported_at", lock::valid_time).map(str::to_string),
        fixes_release: field("fixes_release", lock::valid_tag).map(str::to_string),
    }
}

/// The earliest passed non-redo `red` row of a lock (ties in file order).
fn red_row<'a>(rows: &'a [Row], id: &str) -> Option<&'a Row> {
    first_row(rows.iter().filter(|r| {
        str_of(r, "layer") == "red"
            && is(r, "passed")
            && r.get("redo") != Some(&Value::Bool(true))
            && locks_of(r).iter().any(|l| l == id)
    }))
}

/// Item 75's time grammar, as Unix seconds.
fn unix_time(text: &str) -> Option<i64> {
    if !lock::valid_time(text) {
        return None;
    }
    let n = |r: std::ops::Range<usize>| text.get(r).and_then(|s| s.parse::<i64>().ok());
    let (y, mo, d, h, mi) = (n(0..4)?, n(5..7)?, n(8..10)?, n(11..13)?, n(14..16)?);
    let (sec, rest) = if text.as_bytes().get(16) == Some(&b':') { (n(17..19)?, 19) } else { (0, 16) };
    let offset = match text.as_bytes()[rest] {
        b'Z' => 0,
        sign => {
            let o = n(rest + 1..rest + 3)? * 3600 + n(rest + 4..rest + 6)? * 60;
            if sign == b'-' {
                -o
            } else {
                o
            }
        }
    };
    // Howard Hinnant's days_from_civil.
    let y = if mo <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (mo + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    Some(days * 86_400 + h * 3600 + mi * 60 + sec - offset)
}

/// One DORA metric.
fn metric(value: Option<Value>, n: usize, missing: usize, why: impl FnOnce() -> String) -> Value {
    let value = value.filter(|_| n > 0);
    let reason = (value.is_none() || missing > 0).then(why);
    json!({"value": value, "n": n, "missing": missing, "reason": reason})
}

fn dora(rows: &[Row], evidence: std::result::Result<(&Evidence, &Facts), &String>, since: Option<&str>) -> Value {
    const KEYS: [&str; 5] = ["deploys", "lead_time", "rework_rate", "time_to_recover", "change_failure_rate"];
    let (ev, facts) = match evidence {
        Ok(found) => found,
        Err(reason) => {
            let mut out = json!({
                "kind": "dora",
                "git": {"default_branch": null, "releases": null, "reason": reason},
                "since": since,
            });
            for key in KEYS {
                out[key] = json!({"value": null, "n": 0, "missing": 0, "reason": reason});
            }
            return out;
        }
    };
    let start = since.and_then(|tag| ev.releases.iter().find(|r| r.name == tag)).map(|r| r.time);
    let read: Vec<usize> = (0..ev.releases.len()).filter(|i| start.is_none_or(|t| ev.releases[*i].time >= t)).collect();
    let names: BTreeSet<&str> = ev.releases.iter().map(|r| r.name.as_str()).collect();
    let read_names: BTreeSet<&str> = read.iter().map(|i| ev.releases[*i].name.as_str()).collect();
    // The shipped locks: those whose release is read.
    let shipped: Vec<(&String, &Release, &FixData)> = facts
        .release
        .iter()
        .filter(|(_, i)| read.contains(i))
        .map(|(id, i)| (id, &ev.releases[*i], &facts.fix[id]))
        .collect();
    let times: Vec<i64> = read.iter().map(|i| ev.releases[*i].time).collect();
    let deploys = {
        let (first, last) = (times.iter().min().copied(), times.iter().max().copied());
        let value = first.zip(last).map(|(first, last)| {
            let span = (last - first) as f64 / 86_400.0;
            let per_day = (times.len() >= 2 && span > 0.0).then(|| num(times.len() as f64 / span));
            json!({"count": times.len(), "first": first, "last": last, "per_day": per_day})
        });
        metric(value, times.len(), 0, || "no release read".to_string())
    };
    let lead_time = {
        let (mut samples, mut missing) = (Vec::new(), 0);
        for (id, release, _) in &shipped {
            match red_row(rows, id).and_then(at) {
                Some(red) if release.time as f64 > red => samples.push(release.time as f64 - red),
                _ => missing += 1,
            }
        }
        let n = samples.len();
        let value = (n > 0).then(|| json!({"median": median(samples.clone()), "p90": p90(samples)}));
        metric(value, n, missing, || {
            if missing > 0 {
                format!("{missing} shipped lock(s) without a passed red row in this run log, or released before it")
            } else {
                "no shipped lock in the releases read".to_string()
            }
        })
    };
    let unknown = shipped.iter().filter(|(_, _, f)| f.kind.is_none()).count();
    let rework_rate = {
        let shipping: BTreeSet<&str> = shipped.iter().map(|(_, r, _)| r.name.as_str()).collect();
        let fixing: BTreeSet<&str> = shipped
            .iter()
            .filter(|(_, _, f)| f.kind.as_deref() == Some("fix"))
            .map(|(_, r, _)| r.name.as_str())
            .collect();
        let n = shipping.len();
        let value = (unknown == 0 && n > 0).then(|| num(fixing.len() as f64 / n as f64));
        metric(value, n, unknown, || {
            if unknown > 0 {
                format!("{unknown} shipped lock(s) with an unknown change_kind")
            } else {
                "no release read ships a lock".to_string()
            }
        })
    };
    let fixes: Vec<&(&String, &Release, &FixData)> =
        shipped.iter().filter(|(_, _, f)| f.kind.as_deref() == Some("fix")).collect();
    let time_to_recover = {
        let (mut samples, mut missing) = (Vec::new(), 0);
        for (_, release, f) in &fixes {
            match f.reported_at.as_deref().and_then(unix_time) {
                Some(reported) if release.time > reported => samples.push((release.time - reported) as f64),
                _ => missing += 1,
            }
        }
        let n = samples.len();
        let value = (n > 0).then(|| json!({"median": median(samples.clone()), "p90": p90(samples)}));
        metric(value, n, missing, || {
            if missing > 0 {
                format!("{missing} shipped fix lock(s) without reported_at, or released before it")
            } else {
                "no shipped fix lock with reported_at".to_string()
            }
        })
    };
    let change_failure_rate = {
        let unlinked =
            fixes.iter().filter(|(_, _, f)| f.fixes_release.as_deref().is_none_or(|t| !names.contains(t))).count();
        let missing = unknown + unlinked;
        let failed: BTreeSet<&str> = fixes
            .iter()
            .filter_map(|(_, _, f)| f.fixes_release.as_deref())
            .filter(|t| read_names.contains(t))
            .collect();
        let n = read.len();
        let value = (missing == 0 && n > 0).then(|| num(failed.len() as f64 / n as f64));
        metric(value, n, missing, || {
            if missing > 0 {
                format!("{missing} shipped lock(s) with an unknown change_kind, or fix lock(s) naming no release")
            } else {
                "no release read".to_string()
            }
        })
    };
    json!({
        "kind": "dora",
        "git": {"default_branch": ev.branch, "releases": ev.releases.len(), "reason": null},
        "since": since,
        "deploys": deploys, "lead_time": lead_time, "rework_rate": rework_rate,
        "time_to_recover": time_to_recover, "change_failure_rate": change_failure_rate,
    })
}

/// The rows, without blank lines and escapes, and the lines that do not read
/// (physical line number, reason). A BOM at the start and a trailing CR go.
fn read(bytes: &[u8]) -> (Vec<Row>, Vec<(usize, String)>) {
    let text = String::from_utf8_lossy(bytes);
    let text = text.strip_prefix('\u{feff}').unwrap_or(&text);
    let (mut rows, mut gaps) = (Vec::new(), Vec::new());
    for (i, line) in text.split('\n').enumerate() {
        let line = line.strip_suffix('\r').unwrap_or(line);
        if line.trim().is_empty() {
            continue;
        }
        match serde_json::from_str::<Value>(line) {
            Ok(Value::Object(row)) if row.get("escape") == Some(&Value::Bool(true)) => {}
            Ok(Value::Object(row)) => rows.push(row),
            Ok(_) => gaps.push((i + 1, "not a JSON object".to_string())),
            Err(e) => gaps.push((i + 1, format!("not JSON: {e}"))),
        }
    }
    (rows, gaps)
}

struct Report {
    meta: Value,
    locks: Vec<Value>,
    days: Vec<Value>,
}

/// What a lock's row needs for the day summary.
struct Merged {
    day: String,
    red_to_merge: Option<f64>,
    waiting: Option<f64>,
    first_approved: Option<bool>,
}

impl Report {
    fn of(rows: &[Row], ids: &[String], facts: Option<&Facts>) -> Report {
        let ats: Vec<f64> = rows.iter().filter_map(at).collect();
        let bound = |pick: fn(f64, f64) -> f64| ats.iter().copied().reduce(pick).map(num);
        let all = |layer: &str| rows.iter().filter(|r| str_of(r, "layer") == layer).collect::<Vec<_>>();
        let meta = json!({
            "kind": "meta", "first_at": bound(f64::min), "last_at": bound(f64::max),
            "hook": stats(&all("hook")), "ci": stats(&all("ci")),
        });
        // Item 76: then the lock files at the default branch's tip the log does not name.
        let mut all: Vec<String> = ids.to_vec();
        if let Some(facts) = facts {
            all.extend(facts.tip.iter().filter(|id| !ids.contains(id)).cloned());
        }
        let mut merged = Vec::new();
        let locks = all
            .iter()
            .map(|id| {
                let mine: Vec<&Row> = rows.iter().filter(|r| locks_of(r).contains(id)).collect();
                let (mut row, m) = lock_row(id, &mine);
                let fix = facts.and_then(|f| f.fix.get(id)).cloned().unwrap_or_default();
                if m.is_none() && facts.is_some_and(|f| f.tip.contains(id)) {
                    row["state"] = "merge_not_observed".into();
                }
                row["change_kind"] = fix.kind.into();
                row["reported_at"] = fix.reported_at.into();
                row["fixes_release"] = fix.fixes_release.into();
                merged.extend(m);
                row
            })
            .collect();
        let mut by_day: BTreeMap<String, Vec<Merged>> = BTreeMap::new();
        for m in merged {
            by_day.entry(m.day.clone()).or_default().push(m);
        }
        let days = by_day
            .into_iter()
            .map(|(day, ms)| {
                let reviewed: Vec<bool> = ms.iter().filter_map(|m| m.first_approved).collect();
                let share = (!reviewed.is_empty())
                    .then(|| reviewed.iter().filter(|a| **a).count() as f64 / reviewed.len() as f64);
                json!({
                    "kind": "day", "day": day, "merged_locks": ms.len(),
                    "red_to_merge_median": median(ms.iter().filter_map(|m| m.red_to_merge).collect()),
                    "waiting_median": median(ms.iter().filter_map(|m| m.waiting).collect()),
                    "first_review_approved_share": share.map(num),
                })
            })
            .collect();
        Report { meta, locks, days }
    }
}

fn lock_row(id: &str, rows: &[&Row]) -> (Value, Option<Merged>) {
    // Item 46: a redo is not the RED that opened the cycle; `redos` counts them.
    let redo = |r: &Row| r.get("redo") == Some(&Value::Bool(true));
    let passed = |layer: &str| {
        first(rows.iter().copied().filter(|r| str_of(r, "layer") == layer && is(r, "passed") && !redo(r)))
    };
    let redos = rows.iter().filter(|r| str_of(r, "layer") == "red" && is(r, "passed") && redo(r)).count();
    let red = passed("red");
    let close = passed("close");
    // A merge counts only into the default branch.
    let merge = first(rows.iter().copied().filter(|r| {
        str_of(r, "layer") == "merge"
            && is(r, "passed")
            && r.get("base")
                .and_then(Value::as_str)
                .is_some_and(|b| r.get("default_branch").and_then(Value::as_str) == Some(b))
    }));
    let span = |a: Option<f64>, b: Option<f64>| a.zip(b).map(|(a, b)| b - a);
    let waiting = merge.and_then(|m| {
        let ci = rows.iter().filter(|r| str_of(r, "layer") == "ci" && is(r, "passed")).filter_map(|r| at(r));
        ci.filter(|t| *t <= m).reduce(f64::max).map(|t| m - t)
    });
    let reviews: Vec<&Row> = rows
        .iter()
        .copied()
        .filter(|r| str_of(r, "layer") == "review" && r.get("reused") != Some(&Value::Bool(true)))
        .collect();
    let count = |result: &str| reviews.iter().filter(|r| is(r, result)).count();
    let first_approved =
        first_row(reviews.iter().copied().filter(|r| is(r, "passed") || is(r, "refused"))).map(|r| is(r, "passed"));
    let mut refusals = BTreeMap::new();
    for r in rows.iter().filter(|r| is(r, "refused")) {
        *refusals.entry(str_of(r, "code").to_string()).or_insert(0u64) += 1;
    }
    let errors = rows.iter().filter(|r| is(r, "error")).count();
    let unobserved: Vec<&str> =
        [("red", red), ("close", close)].iter().filter(|(_, t)| t.is_none()).map(|(s, _)| *s).collect();
    let of = |layer: &str| stats(&rows.iter().copied().filter(|r| str_of(r, "layer") == layer).collect::<Vec<_>>());
    let row = json!({
        "kind": "lock", "lock": id, "state": if merge.is_some() { "merged" } else { "open" },
        "red_at": red.map(num), "close_at": close.map(num), "merge_at": merge.map(num),
        "red_to_close": span(red, close).map(num), "close_to_merge": span(close, merge).map(num),
        "red_to_merge": span(red, merge).map(num), "waiting": waiting.map(num), "unobserved": unobserved,
        "reviews": {"passed": count("passed"), "refused": count("refused"), "error": count("error")},
        "first_review_approved": first_approved, "redos": redos, "refusals": refusals, "errors": errors,
        "hook": of("hook"), "ci": of("ci"),
    });
    let merged = merge.map(|m| Merged { day: day(m), red_to_merge: span(red, merge), waiting, first_approved });
    (row, merged)
}

/// The locks a row is about: its `lock` and its `locks`.
fn locks_of(row: &Row) -> Vec<String> {
    let mut ids: Vec<String> = Vec::new();
    let single = row.get("lock").and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string);
    let many = row.get("locks").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str);
    for id in single.into_iter().chain(many.filter(|s| !s.is_empty()).map(str::to_string)) {
        if !ids.contains(&id) {
            ids.push(id);
        }
    }
    ids
}

fn at(row: &Row) -> Option<f64> {
    row.get("at").and_then(Value::as_f64)
}

fn str_of<'a>(row: &'a Row, key: &str) -> &'a str {
    row.get(key).and_then(Value::as_str).unwrap_or_default()
}

fn is(row: &Row, result: &str) -> bool {
    str_of(row, "result") == result
}

/// The row with the earliest `at`; equal times keep file order.
fn first_row<'a>(rows: impl Iterator<Item = &'a Row>) -> Option<&'a Row> {
    rows.filter(|r| at(r).is_some()).fold(None, |best: Option<&Row>, r| match best {
        Some(b) if at(b) <= at(r) => Some(b),
        _ => Some(r),
    })
}

fn first<'a>(rows: impl Iterator<Item = &'a Row>) -> Option<f64> {
    first_row(rows).and_then(at)
}

/// Count, p50, p90 of `secs`, and refusals by code.
fn stats(rows: &[&Row]) -> Value {
    let secs: Vec<f64> = rows.iter().filter_map(|r| r.get("secs").and_then(Value::as_f64)).collect();
    let mut refusals = BTreeMap::new();
    for r in rows.iter().filter(|r| is(r, "refused")) {
        *refusals.entry(str_of(r, "code").to_string()).or_insert(0u64) += 1;
    }
    json!({"count": rows.len(), "p50": median(secs.clone()), "p90": p90(secs), "refusals": refusals})
}

/// The median: the mean of the two middle values for an even count.
fn median(mut values: Vec<f64>) -> Option<Value> {
    if values.is_empty() {
        return None;
    }
    values.sort_by(f64::total_cmp);
    let n = values.len();
    Some(num(if n % 2 == 1 { values[n / 2] } else { (values[n / 2 - 1] + values[n / 2]) / 2.0 }))
}

/// Nearest rank: the ceil(0.9 n)-th smallest.
fn p90(mut values: Vec<f64>) -> Option<Value> {
    if values.is_empty() {
        return None;
    }
    values.sort_by(f64::total_cmp);
    let rank = (9 * values.len()).div_ceil(10);
    Some(num(values[rank - 1]))
}

/// A whole number prints as an integer.
fn num(x: f64) -> Value {
    if x.fract() == 0.0 && x.abs() < 9e15 {
        json!(x as i64)
    } else {
        json!(x)
    }
}

/// The UTC day (YYYY-MM-DD) of a Unix time.
fn day(t: f64) -> String {
    let days = (t / 86_400.0).floor() as i64;
    // Howard Hinnant's civil_from_days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

fn text(lines: &[Value]) -> String {
    let show = |v: &Value| if v.is_null() { "-".to_string() } else { v.to_string() };
    let secs = |v: &Value| if v.is_null() { "-".to_string() } else { format!("{v} s") };
    let stat = |s: &Value| {
        format!("{} (p50 {}, p90 {}, refusals {})", s["count"], secs(&s["p50"]), secs(&s["p90"]), s["refusals"])
    };
    let mut out = String::new();
    let mut meta = &Value::Null;
    for line in lines {
        if line["kind"] == "meta" {
            meta = line;
        }
        match line["kind"].as_str().unwrap_or_default() {
            "meta" if line["first_at"].is_null() => {
                out += "shipcraft report: runs recorded on this machine only (local run log): no rows yet.\n";
            }
            "meta" => {
                out += &format!(
                    "shipcraft report: runs recorded on this machine only (local run log), first row at {}, last row at {} (Unix seconds); reviews or CI that ran elsewhere are not counted.\n",
                    line["first_at"], line["last_at"]
                );
                out += &format!("totals: hook {}; ci {}\n", stat(&line["hook"]), stat(&line["ci"]));
            }
            "lock" => {
                let unobserved = line["unobserved"]
                    .as_array()
                    .map(|u| u.iter().filter_map(Value::as_str).collect::<Vec<_>>().join(", "));
                out += &format!(
                    "lock {}: {}; red at {}, close at {}, merge at {}; red to close {}, close to merge {}, red to merge {}; waiting {}; reviews passed {}, refused {}, error {}, first approved {}; redos {}; refusals {}, errors {}; hook {}; ci {}{}\n",
                    line["lock"].as_str().unwrap_or_default(),
                    line["state"].as_str().unwrap_or_default(),
                    show(&line["red_at"]), show(&line["close_at"]), show(&line["merge_at"]),
                    secs(&line["red_to_close"]), secs(&line["close_to_merge"]), secs(&line["red_to_merge"]),
                    secs(&line["waiting"]),
                    line["reviews"]["passed"], line["reviews"]["refused"], line["reviews"]["error"],
                    show(&line["first_review_approved"]), line["redos"], line["refusals"], line["errors"],
                    stat(&line["hook"]), stat(&line["ci"]),
                    match unobserved.as_deref() {
                        Some("") | None => String::new(),
                        Some(steps) => format!("; not observed here: {steps}"),
                    }
                );
            }
            "day" => {
                out += &format!(
                    "day {}: {} merged lock(s); median red to merge {}, median waiting {}, approved on first review {}\n",
                    line["day"].as_str().unwrap_or_default(),
                    line["merged_locks"],
                    secs(&line["red_to_merge_median"]),
                    secs(&line["waiting_median"]),
                    show(&line["first_review_approved_share"])
                );
            }
            "dora" => out += &dora_text(meta, line),
            _ => {
                out += &format!(
                    "gap: line {} does not read ({})\n",
                    line["line"],
                    line["reason"].as_str().unwrap_or_default()
                )
            }
        }
    }
    out
}

/// Item 76: the DORA block, with the same content as the `dora` line.
fn dora_text(meta: &Value, dora: &Value) -> String {
    let show = |v: &Value| if v.is_null() { "-".to_string() } else { v.to_string() };
    let secs = |v: &Value| if v.is_null() { "-".to_string() } else { format!("{v} s") };
    let mut out = "DORA\n".to_string();
    out += &if meta["first_at"].is_null() {
        "run log: no rows yet; it holds this machine's runs only (local run log).\n".to_string()
    } else {
        format!(
            "run log: first row at {}, last row at {} (Unix seconds); it holds this machine's runs only (local run log).\n",
            meta["first_at"], meta["last_at"]
        )
    };
    let git = &dora["git"];
    let since = dora["since"].as_str().map(|s| format!(", since {s}")).unwrap_or_default();
    out += &match git["default_branch"].as_str() {
        Some(branch) => format!(
            "git: default branch {branch}; {} release(s){since}; lock rows without log times come from the branch tip.\n",
            // The releases read: all of them, or those at or after `--since` (deploys' `n`).
            dora["deploys"]["n"]
        ),
        None => format!(
            "git: no evidence ({}){since}; lock rows without log times come from the branch tip when git reads.\n",
            git["reason"].as_str().unwrap_or_default()
        ),
    };
    let tail = |m: &Value| {
        let reason = m["reason"].as_str().map(|r| format!("; {r}")).unwrap_or_default();
        format!(" (n {}, missing {}{reason})\n", m["n"], m["missing"])
    };
    let spread = |m: &Value| {
        let v = &m["value"];
        if v.is_null() {
            "-".to_string()
        } else {
            format!("median {}, p90 {}", secs(&v["median"]), secs(&v["p90"]))
        }
    };
    let d = &dora["deploys"];
    let v = &d["value"];
    out += &if v.is_null() {
        format!("deploys: -{}", tail(d))
    } else {
        format!(
            "deploys: {} release(s), first at {}, last at {}, per day {}{}",
            v["count"],
            v["first"],
            v["last"],
            show(&v["per_day"]),
            tail(d)
        )
    };
    out += &format!("lead time: {}{}", spread(&dora["lead_time"]), tail(&dora["lead_time"]));
    out += &format!("rework rate: {}{}", show(&dora["rework_rate"]["value"]), tail(&dora["rework_rate"]));
    out += &format!("time to recover: {}{}", spread(&dora["time_to_recover"]), tail(&dora["time_to_recover"]));
    out += &format!(
        "change failure rate: {}{}",
        show(&dora["change_failure_rate"]["value"]),
        tail(&dora["change_failure_rate"])
    );
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn percentiles_follow_the_fixed_readings() {
        let ten: Vec<f64> = (1..=10).map(f64::from).collect();
        assert_eq!(median(ten.clone()), Some(json!(5.5)));
        assert_eq!(p90(ten), Some(json!(9)));
        assert_eq!(median(vec![]), None);
    }

    #[test]
    fn utc_day_boundaries() {
        assert_eq!(day(86_399.0), "1970-01-01");
        assert_eq!(day(86_400.0), "1970-01-02");
        assert_eq!(day(1_792_972_800.0), "2026-10-26");
    }

    #[test]
    fn reader_strips_bom_and_cr_and_counts_physical_lines() {
        let (rows, gaps) = read("\u{feff}{\"at\":1}\r\n\r\n[]\r\n{\"at\":2,\"escape\":true}\n{bad".as_bytes());
        assert_eq!(rows.len(), 1);
        assert_eq!(gaps.iter().map(|g| g.0).collect::<Vec<_>>(), vec![3, 5]);
    }
}
