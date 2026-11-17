//! Item 38: `shipcraft report [--json]`, the flow measured from the run log.
//! It finds `.git` by walking up from the current directory and never refuses.
//! Item 76: `[--since <tag>]`, and a local DORA readout from the run log, the
//! release tags and the lock files, read through `git -C <root>` read-only, with
//! no network read; a key without data says so with a count.
//! Item 79: `[--github]` fills the selected locks' waiting and merge times
//! from GitHub through `gh` (relatorio_gh); without it, nothing changes.
//! Item 99: `[report] release_tags` in `<root>/.shipcraft.toml` names the
//! project's release tags; without it, item 76's `vX.Y.Z` tags.

use crate::config::{self, CONFIG_FILE};
use crate::lock::{self, Lock};
use crate::refusal::Result;
use crate::relatorio_gh::{oid, Asker, Pr};
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

type Row = Map<String, Value>;

/// Item 99: which tags are releases, from the `[report]` table alone.
enum Selection {
    /// Item 76's `vX.Y.Z` tags: no key, or a file this reader does not read.
    Default,
    /// A valid `release_tags`.
    Pattern(String),
    /// An invalid `[report]`: the problem, and no git evidence.
    Invalid(String),
}

impl Selection {
    /// `<root>/.shipcraft.toml` from the working tree; never refuses.
    fn read(root: &Path) -> Selection {
        let path = root.join(CONFIG_FILE);
        if !fs::metadata(&path).is_ok_and(|m| m.is_file()) {
            return Selection::Default;
        }
        let Some(text) = fs::read(&path).ok().and_then(|b| String::from_utf8(b).ok()) else {
            return Selection::Default;
        };
        let Ok(table) = text.parse::<toml::Table>() else { return Selection::Default };
        match config::report_release_tags(&table) {
            Ok(None) => Selection::Default,
            Ok(Some(pattern)) => Selection::Pattern(pattern),
            Err(problem) => Selection::Invalid(problem),
        }
    }

    /// Whether a tag name is of the releases' grammar.
    fn names(&self, tag: &str) -> bool {
        match self {
            Selection::Pattern(pattern) => matches(pattern.as_bytes(), tag.as_bytes()),
            _ => lock::valid_tag(tag),
        }
    }

    /// Item 105: None when `tag` is a release name of this selection, else
    /// the selection as `red`'s refusal names it.
    fn release_name_problem(&self, tag: &str) -> Option<String> {
        match self {
            Selection::Invalid(problem) => Some(format!("invalid: {}", config::report_invalid(problem))),
            Selection::Pattern(pattern) => (!self.names(tag)).then(|| pattern.clone()),
            Selection::Default => (!self.names(tag)).then(|| "vX.Y.Z".to_string()),
        }
    }

    fn pattern(&self) -> Option<&str> {
        match self {
            Selection::Pattern(pattern) => Some(pattern),
            _ => None,
        }
    }
}

/// Item 99: `*` matches any run of bytes, `/` and the empty run included;
/// every other byte matches itself; the whole name must match.
fn matches(pattern: &[u8], name: &[u8]) -> bool {
    let (mut p, mut n) = (0, 0);
    let mut star: Option<(usize, usize)> = None;
    while n < name.len() {
        if p < pattern.len() && pattern[p] == b'*' {
            star = Some((p, n));
            p += 1;
        } else if p < pattern.len() && pattern[p] == name[n] {
            p += 1;
            n += 1;
        } else if let Some((sp, sn)) = star {
            p = sp + 1;
            n = sn + 1;
            star = Some((sp, sn + 1));
        } else {
            return false;
        }
    }
    pattern[p..].iter().all(|b| *b == b'*')
}

/// Item 105: `red --fixes-release <tag>`'s selection check, with item 99's
/// reader of the working tree's `[report]` (the root found as `report` finds
/// it; none found is the default reading) and its matcher. None when the tag
/// names a release of the selection; else the `<pattern>` the refusal shows:
/// the pattern, `vX.Y.Z` under the default reading, or `invalid: <reason>`
/// (item 99's full reason, as `report` prints it) under an invalid
/// `[report]`, where no tag is accepted.
pub fn not_a_release_name(tag: &str) -> Option<String> {
    let selection = discover().map_or(Selection::Default, |(root, _)| Selection::read(&root));
    selection.release_name_problem(tag)
}

/// What `report` reads before any git call: the repository and run log, and
/// the release selection (item 99), so `main` checks `--since`'s grammar first.
pub struct Prepared {
    found: Option<(PathBuf, PathBuf)>,
    selection: Selection,
}

impl Prepared {
    pub fn read() -> Prepared {
        let found = discover();
        let selection = found.as_ref().map_or(Selection::Default, |(root, _)| Selection::read(root));
        Prepared { found, selection }
    }

    /// `--since`'s grammar: the pattern when `release_tags` is valid, item
    /// 76's `vX.Y.Z` with the default reading, none with an invalid `[report]`.
    pub fn since_grammar(&self, tag: &str) -> bool {
        match &self.selection {
            Selection::Invalid(_) => true,
            selection => selection.names(tag),
        }
    }
}

pub fn run(prepared: Prepared, as_json: bool, since: Option<&str>, github: bool) -> Result<()> {
    let Prepared { found, selection } = prepared;
    let bytes = found.as_ref().and_then(|(_, log)| fs::read(log).ok()).unwrap_or_default();
    let (rows, gaps) = read(&bytes);
    let mut ids: Vec<String> = Vec::new();
    for id in rows.iter().flat_map(locks_of) {
        if !ids.contains(&id) {
            ids.push(id);
        }
    }
    let root = found.as_ref().map(|(root, _)| root.clone()).unwrap_or_default();
    let git = Git { root: root.clone() };
    let evidence = match (&found, &selection) {
        (None, _) => Err("no git repository found".to_string()),
        // Item 99: an invalid `[report]` reads no git, as a git failure.
        (Some(_), Selection::Invalid(problem)) => Err(config::report_invalid(problem)),
        (Some(_), selection) => Evidence::read(&git, &ids, selection),
    };
    if let (Some(tag), Ok(ev)) = (since, &evidence) {
        if !ev.releases.iter().any(|r| r.name == tag) {
            eprintln!("report: --since {tag} is not a release tag on {}", ev.branch);
            std::process::exit(2);
        }
    }
    let facts = evidence.as_ref().ok().map(|ev| Facts::of(ev, &rows, &ids));
    let mut report = Report::of(&rows, &ids, facts.as_ref());
    let evidence_facts = evidence.as_ref().map(|ev| (ev, facts.as_ref().expect("facts with evidence")));
    let dora = dora(&rows, evidence_facts, since, selection.pattern());
    // Item 79: after item 76's reads, and before the day rows take the waiting.
    let git_tip = evidence.as_ref().ok().map(|ev| (&git, ev.branch.as_str(), ev.tip_commit.as_str()));
    let mut asker = github.then(|| Asker::new(&root, git_tip));
    let summary = asker.as_mut().map(|asker| ask_github(asker, &rows, &mut report));
    let mut review_line = review(&rows);
    // Item 113: after item 79's calls, through the same asker.
    if let (Some(asker), Some(line)) = (asker.as_mut(), review_line.as_mut()) {
        blocking(asker, &rows, line);
    }
    // Item 114: after item 113's calls, through the same asker.
    let checks_line = match (asker.as_mut(), &review_line) {
        (Some(asker), Some(_)) => checks(asker, &rows),
        _ => None,
    };
    let gaps: Vec<Value> =
        gaps.into_iter().map(|(line, reason)| json!({"kind": "gap", "line": line, "reason": reason})).collect();
    let lines: Vec<Value> = [report.meta.clone()]
        .into_iter()
        .chain(report.locks.clone())
        .chain(report.days())
        .chain(size(&rows))
        .chain(reds(&rows))
        .chain(review_line)
        .chain(checks_line)
        .chain([dora])
        .chain(summary)
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
pub(crate) const REPOSITORY_VARS: [&str; 16] = [
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

/// Item 79: asks GitHub about each selected lock row (`merged` or
/// `merge_not_observed`, `waiting` null), in print order, and fills what it
/// answers; every lock row gets its `github` list. The `github` summary line.
fn ask_github(asker: &mut Asker, rows: &[Row], report: &mut Report) -> Value {
    let (mut selected, mut merge_filled, mut waiting_filled) = (0, 0, 0);
    let mut missing: BTreeMap<String, u64> = BTreeMap::new();
    for (row, merged) in report.locks.iter_mut().zip(report.merged.iter_mut()) {
        let mut filled: Vec<&str> = Vec::new();
        let state = row["state"].as_str().unwrap_or_default();
        if (state == "merged" || state == "merge_not_observed") && row["waiting"].is_null() {
            selected += 1;
            let pr = pr_of(rows, row["lock"].as_str().unwrap_or_default(), state == "merged");
            match asker.lock(row, pr, &mut filled) {
                Ok(waiting) => {
                    row["waiting"] = num(waiting);
                    filled.push("waiting");
                    if let Some(m) = merged {
                        m.waiting = Some(waiting);
                    }
                    waiting_filled += 1;
                }
                Err(reason) => *missing.entry(reason).or_default() += 1,
            }
            if filled.contains(&"merge_at") {
                merge_filled += 1;
            }
        }
        row["github"] = json!(filled);
    }
    json!({
        "kind": "github", "selected": selected, "merge_filled": merge_filled,
        "waiting_filled": waiting_filled, "missing": missing,
    })
}

/// Item 79: the PR a lock went through. A `merged` lock's is the `pr` of the
/// `merge` row that gave its `merge_at`; another's, the `pr` of every `pr`
/// row naming it, any result. Only positive JSON integers count.
fn pr_of(rows: &[Row], id: &str, merged: bool) -> Pr {
    let mine: Vec<&Row> = rows.iter().filter(|r| locks_of(r).iter().any(|l| l == id)).collect();
    let positive = |r: &Row| r.get("pr").and_then(Value::as_u64).filter(|n| *n > 0);
    let prs: BTreeSet<u64> = if merged {
        merge_row(&mine).and_then(positive).into_iter().collect()
    } else {
        mine.iter().filter(|r| str_of(r, "layer") == "pr").filter_map(|r| positive(r)).collect()
    };
    match prs.len() {
        0 => Pr::None,
        1 => Pr::One(prs.into_iter().next().expect("one PR")),
        _ => Pr::Several,
    }
}

/// Read-only git at the discovered root, with no lazy fetch and no prompt.
pub(crate) struct Git {
    root: PathBuf,
}

impl Git {
    /// The exit code and stdout; Err when git cannot run.
    pub(crate) fn call(&self, args: &[&str]) -> std::result::Result<(Option<i32>, Vec<u8>), String> {
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

/// A release: a tag of the selection's grammar (item 76's `vX.Y.Z`, or item
/// 99's pattern) whose commit is on the default branch.
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
    /// Item 79: the default branch's commit, for the ancestry check.
    tip_commit: String,
    tip: BTreeMap<String, String>,
    /// Ordered by time, then by version (by tag name under a pattern).
    releases: Vec<Release>,
    /// Fix data from the first valid lock file among the tip, the latest
    /// release that holds it and HEAD; absent when none has one.
    files: BTreeMap<String, FixData>,
}

impl Evidence {
    fn read(git: &Git, log_ids: &[String], selection: &Selection) -> std::result::Result<Evidence, String> {
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
        for name in names.lines().filter(|n| selection.names(n)) {
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
        // Item 99: the version tie-break only for item 76's tags; under a
        // pattern, the tag name in byte order.
        releases.sort_by(|a, b| {
            a.time.cmp(&b.time).then_with(|| match selection {
                Selection::Pattern(_) => a.name.as_bytes().cmp(b.name.as_bytes()),
                _ => version_cmp(&a.name, &b.name),
            })
        });
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
        Ok(Evidence { branch, tip_commit, tip, releases, files })
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

/// The fix data a `red` row carries, each field in its grammar; item 105:
/// `fixes_release` is a tag name (item 75's syntax included).
fn fix_of_row(row: &Row) -> FixData {
    let kind = row.get("kind").and_then(Value::as_str).filter(|k| *k == "feature" || *k == "fix");
    let field = |key: &str, valid: fn(&str) -> bool| row.get(key).and_then(Value::as_str).filter(|v| valid(v));
    FixData {
        kind: kind.map(str::to_string),
        reported_at: field("reported_at", lock::valid_time).map(str::to_string),
        fixes_release: field("fixes_release", lock::tag_name).map(str::to_string),
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
    Some(days_from_civil(y, mo, d) * 86_400 + h * 3600 + mi * 60 + sec - offset)
}

/// Howard Hinnant's days_from_civil: days since 1970-01-01.
pub(crate) fn days_from_civil(y: i64, mo: i64, d: i64) -> i64 {
    let y = if mo <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (mo + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// One DORA metric.
fn metric(value: Option<Value>, n: usize, missing: usize, why: impl FnOnce() -> String) -> Value {
    let value = value.filter(|_| n > 0);
    let reason = (value.is_none() || missing > 0).then(why);
    json!({"value": value, "n": n, "missing": missing, "reason": reason})
}

fn dora(
    rows: &[Row],
    evidence: std::result::Result<(&Evidence, &Facts), &String>,
    since: Option<&str>,
    release_tags: Option<&str>,
) -> Value {
    const KEYS: [&str; 5] = ["deploys", "lead_time", "rework_rate", "time_to_recover", "change_failure_rate"];
    let (ev, facts) = match evidence {
        Ok(found) => found,
        Err(reason) => {
            let mut out = json!({
                "kind": "dora",
                "git": {"default_branch": null, "releases": null, "release_tags": release_tags, "reason": reason},
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
        "git": {"default_branch": ev.branch, "releases": ev.releases.len(), "release_tags": release_tags, "reason": null},
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
    /// Per lock row, what the day rows need when it merged.
    merged: Vec<Option<Merged>>,
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
        let locks: Vec<Value> = all
            .iter()
            .map(|id| {
                let mine: Vec<&Row> = rows.iter().filter(|r| locks_of(r).contains(id)).collect();
                let (mut row, m) = lock_row(id, &mine);
                // Item 76, point 2: the fix data's last source is the earliest passed
                // non-redo `red` row, which needs no git; only git-derived values
                // go null when git evidence is unavailable.
                let fix = match facts {
                    Some(f) => f.fix.get(id).cloned().unwrap_or_default(),
                    None => red_row(rows, id).map(fix_of_row).unwrap_or_default(),
                };
                if m.is_none() && facts.is_some_and(|f| f.tip.contains(id)) {
                    row["state"] = "merge_not_observed".into();
                }
                row["change_kind"] = fix.kind.into();
                row["reported_at"] = fix.reported_at.into();
                row["fixes_release"] = fix.fixes_release.into();
                merged.push(m);
                row
            })
            .collect();
        Report { meta, locks, merged }
    }

    fn days(&self) -> Vec<Value> {
        let mut by_day: BTreeMap<String, Vec<&Merged>> = BTreeMap::new();
        for m in self.merged.iter().flatten() {
            by_day.entry(m.day.clone()).or_default().push(m);
        }
        by_day
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
            .collect()
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
    let merge = merge_row(rows).and_then(at);
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

/// The earliest passed `merge` row; a merge counts only into the default branch.
fn merge_row<'a>(rows: &[&'a Row]) -> Option<&'a Row> {
    first_row(rows.iter().copied().filter(|r| merge_counts(r)))
}

/// A `merge` row that counts: passed, into the default branch.
fn merge_counts(row: &Row) -> bool {
    str_of(row, "layer") == "merge"
        && is(row, "passed")
        && row
            .get("base")
            .and_then(Value::as_str)
            .is_some_and(|b| row.get("default_branch").and_then(Value::as_str) == Some(b))
}

/// Item 107: the `size` line, the PRs counted against their size limit, from
/// the `pr` and `merge` rows in the file's order; None when no PR is measured.
/// A PR's size and limit are those of its last measured `pr` row (a JSON
/// integer `pr` above 0, `product_lines` and `warn_lines` JSON integers) before
/// the first counting `merge` row of the same number.
fn size(rows: &[Row]) -> Option<Value> {
    let int = |r: &Row, key: &str| r.get(key).and_then(Value::as_u64);
    let mut measured: BTreeMap<u64, bool> = BTreeMap::new();
    let mut merged: BTreeSet<u64> = BTreeSet::new();
    for row in rows {
        let Some(pr) = int(row, "pr").filter(|n| *n > 0) else { continue };
        if merge_counts(row) {
            merged.insert(pr);
        } else if str_of(row, "layer") == "pr" && !merged.contains(&pr) {
            if let Some((lines, limit)) = int(row, "product_lines").zip(int(row, "warn_lines")) {
                measured.insert(pr, lines > limit);
            }
        }
    }
    if measured.is_empty() {
        return None;
    }
    let count = |all: &[bool]| (all.len(), all.iter().filter(|above| **above).count());
    let (prs, above) = count(&measured.values().copied().collect::<Vec<_>>());
    let (merged_prs, merged_above) =
        count(&measured.iter().filter(|(pr, _)| merged.contains(pr)).map(|(_, above)| *above).collect::<Vec<_>>());
    let share = |part: usize, whole: usize| (whole > 0).then(|| num(part as f64 / whole as f64));
    Some(json!({
        "kind": "size", "prs": prs, "above": above, "above_share": share(above, prs),
        "merged_prs": merged_prs, "merged_above": merged_above,
        "merged_above_share": share(merged_above, merged_prs),
    }))
}

/// Item 109: the `reds` line, the `suite-red` rows of `ci` and those a later
/// green `ci` row on the same commit followed, in the file's order; None when
/// no red row exists. `at`, `branch`, `lock`, `locks` and `failed_count` are not read.
fn reds(rows: &[Row]) -> Option<Value> {
    fn commit(r: &Row) -> Option<&str> {
        r.get("commit").and_then(Value::as_str).filter(|c| !c.is_empty())
    }
    let ci = |r: &Row| str_of(r, "layer") == "ci";
    let red = |r: &Row| ci(r) && is(r, "refused") && str_of(r, "code") == "suite-red" && commit(r).is_some();
    // Items 40 and 62: a row that skipped the suite or left it to GitHub did not run it.
    let skipped = |r: &Row, key: &str| r.get(key) == Some(&Value::Bool(true));
    let green = |r: &Row| {
        ci(r) && is(r, "passed") && commit(r).is_some() && !skipped(r, "docs_only") && !skipped(r, "suite_in_checks")
    };
    // The last green row of each commit, by position in the file.
    let mut last_green: BTreeMap<&str, usize> = BTreeMap::new();
    for (i, row) in rows.iter().enumerate() {
        if green(row) {
            last_green.insert(commit(row).expect("green rows have a commit"), i);
        }
    }
    let (mut suite_red, mut green_again, mut named) = (0usize, 0usize, 0usize);
    let mut secs = 0.0f64;
    let mut cases: BTreeMap<&str, usize> = BTreeMap::new();
    for (i, row) in rows.iter().enumerate().filter(|(_, r)| red(r)) {
        suite_red += 1;
        if !last_green.get(commit(row).expect("red rows have a commit")).is_some_and(|g| *g > i) {
            continue;
        }
        green_again += 1;
        secs += row.get("secs").and_then(Value::as_f64).filter(|s| *s >= 0.0).unwrap_or(0.0);
        if let Some(failed) = row.get("failed").and_then(Value::as_array) {
            named += 1;
            let ids: BTreeSet<&str> = failed.iter().filter_map(Value::as_str).collect();
            for id in ids {
                *cases.entry(id).or_insert(0) += 1;
            }
        }
    }
    if suite_red == 0 {
        return None;
    }
    let mut top: Vec<(&str, usize)> = cases.into_iter().collect();
    // Most rows first; the map gave byte order, and the sort is stable.
    top.sort_by_key(|a| std::cmp::Reverse(a.1));
    let cases: Vec<Value> = top.into_iter().take(5).map(|(id, n)| json!({"id": id, "rows": n})).collect();
    Some(json!({
        "kind": "reds", "suite_red": suite_red, "green_again": green_again,
        "green_again_share": num(green_again as f64 / suite_red as f64),
        "green_again_secs": num(secs), "named": named, "cases": cases,
    }))
}

/// Item 112: the `review` line, the review rounds each PR needed; None when
/// no PR is reviewed. A round row is a `review` row with a JSON integer `pr`
/// above 0, a `passed` or `refused` result, and a `reused` that is not `true`.
fn review(rows: &[Row]) -> Option<Value> {
    let mut rounds: BTreeMap<u64, usize> = BTreeMap::new();
    let mut changes_requested = 0usize;
    for row in rows {
        let Some(pr) = round_pr(row) else { continue };
        let refused = is(row, "refused");
        *rounds.entry(pr).or_insert(0) += 1;
        changes_requested += usize::from(refused);
    }
    if rounds.is_empty() {
        return None;
    }
    let mut most: Vec<(u64, usize)> = rounds.iter().filter(|(_, n)| **n >= 2).map(|(pr, n)| (*pr, *n)).collect();
    let second_round = most.len();
    // Most rounds first; the map gave PR order, and the sort is stable.
    most.sort_by_key(|a| std::cmp::Reverse(a.1));
    let most: Vec<Value> = most.into_iter().take(5).map(|(pr, n)| json!({"pr": pr, "rounds": n})).collect();
    Some(json!({
        "kind": "review", "prs": rounds.len(), "rounds": rounds.values().sum::<usize>(),
        "changes_requested": changes_requested, "second_round": second_round,
        "second_round_share": num(second_round as f64 / rounds.len() as f64), "most": most,
    }))
}

/// Item 112: a round row's PR: a `review` row, not reused, with a `passed`
/// or `refused` result and a JSON integer `pr` above 0.
fn round_pr(row: &Row) -> Option<u64> {
    if str_of(row, "layer") != "review" || row.get("reused") == Some(&Value::Bool(true)) {
        return None;
    }
    if !is(row, "passed") && !is(row, "refused") {
        return None;
    }
    row.get("pr").and_then(Value::as_u64).filter(|n| *n > 0)
}

/// Item 113: the reviewed commits, item 112's round rows grouped by `pr` and
/// `commit` (JSON equality; a missing `commit` is its own value), in the order
/// of each one's first round row.
fn reviewed_commits(rows: &[Row]) -> Vec<(u64, Option<&Value>)> {
    let mut commits: Vec<(u64, Option<&Value>)> = Vec::new();
    for row in rows {
        let Some(pr) = round_pr(row) else { continue };
        let commit = (pr, row.get("commit"));
        if !commits.contains(&commit) {
            commits.push(commit);
        }
    }
    commits
}

/// Item 113: with `--github`, the Blocking count of each reviewed commit read
/// through item 79's asker, added to the `review` object as five keys.
fn blocking(asker: &mut Asker, rows: &[Row], line: &mut Value) {
    let commits = reviewed_commits(rows);
    let mut per_pr: BTreeMap<u64, u64> = BTreeMap::new();
    let mut missing: BTreeMap<String, u64> = BTreeMap::new();
    let (mut total, mut read) = (0u64, 0u64);
    for (pr, commit) in &commits {
        let outcome = match commit.and_then(Value::as_str).filter(|c| oid(c)) {
            None => Err("no commit in the run log".to_string()),
            Some(commit) => asker.blocking(commit),
        };
        match outcome {
            Ok(count) => {
                total += count;
                read += 1;
                *per_pr.entry(*pr).or_default() += count;
            }
            Err(reason) => *missing.entry(reason).or_default() += 1,
        }
    }
    let mut most: Vec<(u64, u64)> = per_pr.into_iter().filter(|(_, n)| *n > 0).collect();
    // Most first; the map gave PR order, and the sort is stable.
    most.sort_by_key(|a| std::cmp::Reverse(a.1));
    let most: Vec<Value> = most.into_iter().take(5).map(|(pr, n)| json!({"pr": pr, "blocking": n})).collect();
    let object = line.as_object_mut().expect("the review line is an object");
    object.insert("blocking".into(), json!(total));
    object.insert("blocking_read".into(), json!(read));
    object.insert("blocking_commits".into(), json!(commits.len()));
    object.insert("blocking_missing".into(), json!(missing));
    object.insert("blocking_most".into(), json!(most));
}

/// Item 114: item 112's reviewed PRs, in the order of their first round row.
fn reviewed_prs(rows: &[Row]) -> Vec<u64> {
    let mut prs: Vec<u64> = Vec::new();
    for (pr, _) in reviewed_commits(rows) {
        if !prs.contains(&pr) {
            prs.push(pr);
        }
    }
    prs
}

/// Item 114: with `--github`, the red runs of each `suite_checks` name at the
/// commits of the reviewed PRs read in full; None with no reviewed PR or no
/// name in a readable config.
fn checks(asker: &mut Asker, rows: &[Row]) -> Option<Value> {
    let prs = reviewed_prs(rows);
    if prs.is_empty() {
        return None;
    }
    let names = asker.suite_checks()?;
    let mut totals = vec![[0u64; 5]; names.len()];
    let mut missing: BTreeMap<String, u64> = BTreeMap::new();
    let mut read = 0u64;
    for pr in &prs {
        match asker.pr_checks(*pr, &names) {
            Ok(counts) => {
                read += 1;
                for (total, count) in totals.iter_mut().zip(counts) {
                    for (t, c) in total.iter_mut().zip(count) {
                        *t += c;
                    }
                }
            }
            Err(reason) => *missing.entry(reason).or_default() += 1,
        }
    }
    let names: Vec<Value> = names
        .iter()
        .zip(totals)
        .map(|(name, [runs, red, green_again, new_commit, still_red])| {
            json!({"name": name, "runs": runs, "red": red, "green_again": green_again,
                "new_commit": new_commit, "still_red": still_red})
        })
        .collect();
    Some(json!({"kind": "checks", "prs": prs.len(), "prs_read": read, "missing": missing, "names": names}))
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
pub(crate) fn num(x: f64) -> Value {
    if x.fract() == 0.0 && x.abs() < 9e15 {
        json!(x as i64)
    } else {
        json!(x)
    }
}

/// The UTC day (YYYY-MM-DD) of a Unix time.
fn day(t: f64) -> String {
    civil((t / 86_400.0).floor() as i64)
}

/// Item 83: a Unix time as UTC `YYYY-MM-DDTHH:MM:SSZ`, its whole second rounded down.
fn utc(t: f64) -> String {
    let secs = t.floor() as i64;
    let rest = secs.rem_euclid(86_400);
    format!("{}T{:02}:{:02}:{:02}Z", civil(secs.div_euclid(86_400)), rest / 3600, rest % 3600 / 60, rest % 60)
}

/// Item 83: a duration in seconds as `<h> h <m> min <s> s`, rounded to the nearest second.
fn duration(x: f64) -> String {
    let total = x.round() as i64;
    let sign = if total < 0 { "-" } else { "" };
    let a = total.unsigned_abs();
    let (h, m, s) = (a / 3600, a % 3600 / 60, a % 60);
    if h > 0 {
        format!("{sign}{h} h {m} min {s} s")
    } else if m > 0 {
        format!("{sign}{m} min {s} s")
    } else {
        format!("{sign}{s} s")
    }
}

/// Item 83: a share as a whole percent.
fn percent(x: f64) -> String {
    format!("{}%", (x * 100.0).round() as i64)
}

/// Item 83's text forms of a value; `-` when it is empty (or not a number).
fn show_with(v: &Value, f: impl Fn(f64) -> String) -> String {
    v.as_f64().map_or_else(|| "-".to_string(), f)
}

/// Howard Hinnant's civil_from_days, as YYYY-MM-DD.
fn civil(days: i64) -> String {
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
    let time = |v: &Value| show_with(v, utc);
    let span = |v: &Value| show_with(v, duration);
    let latency = |v: &Value| show_with(v, |x| format!("{x:.1} s"));
    let stat = |s: &Value| {
        format!("{} (p50 {}, p90 {}, refusals {})", s["count"], latency(&s["p50"]), latency(&s["p90"]), s["refusals"])
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
                    "shipcraft report: runs recorded on this machine only (local run log), first row at {}, last row at {} (UTC); reviews or CI that ran elsewhere are not counted.\n",
                    time(&line["first_at"]), time(&line["last_at"])
                );
                out += &format!("totals: hook {}; ci {}\n", stat(&line["hook"]), stat(&line["ci"]));
            }
            "lock" => {
                let unobserved = line["unobserved"]
                    .as_array()
                    .map(|u| u.iter().filter_map(Value::as_str).collect::<Vec<_>>().join(", "));
                out += &format!(
                    "lock {}: {}; red at {}, close at {}, merge at {}; red to close {}, close to merge {}, red to merge {}; waiting {}; reviews passed {}, refused {}, error {}, first approved {}; redos {}; refusals {}, errors {}; hook {}; ci {}{}{}\n",
                    line["lock"].as_str().unwrap_or_default(),
                    line["state"].as_str().unwrap_or_default(),
                    time(&line["red_at"]), time(&line["close_at"]), time(&line["merge_at"]),
                    span(&line["red_to_close"]), span(&line["close_to_merge"]), span(&line["red_to_merge"]),
                    span(&line["waiting"]),
                    line["reviews"]["passed"], line["reviews"]["refused"], line["reviews"]["error"],
                    show(&line["first_review_approved"]), line["redos"], line["refusals"], line["errors"],
                    stat(&line["hook"]), stat(&line["ci"]),
                    match unobserved.as_deref() {
                        Some("") | None => String::new(),
                        Some(steps) => format!("; not observed here: {steps}"),
                    },
                    // Item 79: only with `--github`, and only when a field was filled.
                    match line["github"].as_array().map(|g| g.iter().filter_map(Value::as_str).collect::<Vec<_>>()) {
                        Some(names) if !names.is_empty() => format!("; from github: {}", names.join(", ")),
                        _ => String::new(),
                    }
                );
            }
            "day" => {
                out += &format!(
                    "day {}: {} merged lock(s); median red to merge {}, median waiting {}, approved on first review {}\n",
                    line["day"].as_str().unwrap_or_default(),
                    line["merged_locks"],
                    span(&line["red_to_merge_median"]),
                    span(&line["waiting_median"]),
                    show_with(&line["first_review_approved_share"], percent)
                );
            }
            // Item 107: the PRs counted against their size limit.
            "size" => {
                out += &format!(
                    "size: {} PR(s) measured, {} above their limit ({}); merged {}, {} above ({})\n",
                    line["prs"],
                    line["above"],
                    show_with(&line["above_share"], percent),
                    line["merged_prs"],
                    line["merged_above"],
                    show_with(&line["merged_above_share"], percent)
                );
            }
            // Item 109: the suite-red runs that went green on the same commit.
            "reds" => {
                let cases = line["cases"].as_array().filter(|c| !c.is_empty()).map_or("none".to_string(), |c| {
                    c.iter()
                        .map(|case| {
                            let id = case["id"].as_str().unwrap_or_default();
                            format!("{} ({})", Value::String(id.to_string()), case["rows"])
                        })
                        .collect::<Vec<_>>()
                        .join(", ")
                });
                out += &format!(
                    "reds: {} suite-red, {} green again on the same commit ({}), {} of CI; cases named in {}: {cases}\n",
                    line["suite_red"],
                    line["green_again"],
                    show_with(&line["green_again_share"], percent),
                    show_with(&line["green_again_secs"], duration),
                    line["named"]
                );
            }
            // Item 112: the review rounds each PR needed.
            "review" => {
                let most = line["most"].as_array().filter(|m| !m.is_empty()).map_or("none".to_string(), |m| {
                    m.iter().map(|e| format!("#{} ({})", e["pr"], e["rounds"])).collect::<Vec<_>>().join(", ")
                });
                out += &format!(
                    "review: {} PR(s) reviewed in {} round(s), {} requested changes; {} needed a second round ({}): {most}",
                    line["prs"],
                    line["rounds"],
                    line["changes_requested"],
                    line["second_round"],
                    show_with(&line["second_round_share"], percent)
                );
                // Item 113: only with `--github`.
                if line.get("blocking").is_some() {
                    let entries = |key: &str, field: &str| {
                        line[key].as_array().filter(|m| !m.is_empty()).map(|m| {
                            m.iter().map(|e| format!("#{} ({})", e["pr"], e[field])).collect::<Vec<_>>().join(", ")
                        })
                    };
                    out += &format!(
                        "; Blocking {} in {} of {} reviewed commit(s): {}",
                        line["blocking"],
                        line["blocking_read"],
                        line["blocking_commits"],
                        entries("blocking_most", "blocking").unwrap_or_else(|| "none".to_string())
                    );
                    if let Some(m) = line["blocking_missing"].as_object().filter(|m| !m.is_empty()) {
                        let reasons = m.iter().map(|(reason, n)| format!("{reason} {n}")).collect::<Vec<_>>();
                        out += &format!("; not read: {}", reasons.join(", "));
                    }
                }
                out += "\n";
            }
            // Item 114: only with `--github`.
            "checks" => {
                out += &format!("checks: {} of {} reviewed PR(s) read", line["prs_read"], line["prs"]);
                for name in line["names"].as_array().into_iter().flatten() {
                    out += &format!(
                        "; {}: {} red in {} run(s), {} green again on the same commit, {} fixed by a new commit, {} still red",
                        Value::String(name["name"].as_str().unwrap_or_default().to_string()),
                        name["red"],
                        name["runs"],
                        name["green_again"],
                        name["new_commit"],
                        name["still_red"]
                    );
                }
                if let Some(m) = line["missing"].as_object().filter(|m| !m.is_empty()) {
                    let reasons = m.iter().map(|(reason, n)| format!("{reason} {n}")).collect::<Vec<_>>();
                    out += &format!("; not read: {}", reasons.join(", "));
                }
                out += "\n";
            }
            "dora" => out += &dora_text(meta, line),
            "github" => {
                let missing = line["missing"].as_object().filter(|m| !m.is_empty()).map_or("none".to_string(), |m| {
                    m.iter().map(|(reason, n)| format!("{reason} {n}")).collect::<Vec<_>>().join(", ")
                });
                out += &format!(
                    "github: selected {}, merge filled {}, waiting filled {}; missing {missing}\n",
                    line["selected"], line["merge_filled"], line["waiting_filled"]
                );
            }
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
    let time = |v: &Value| show_with(v, utc);
    let span = |v: &Value| show_with(v, duration);
    let share = |v: &Value| show_with(v, percent);
    let mut out = "DORA\n".to_string();
    out += &if meta["first_at"].is_null() {
        "run log: no rows yet; it holds this machine's runs only (local run log).\n".to_string()
    } else {
        format!(
            "run log: first row at {}, last row at {} (UTC); it holds this machine's runs only (local run log).\n",
            time(&meta["first_at"]),
            time(&meta["last_at"])
        )
    };
    let git = &dora["git"];
    let since = dora["since"].as_str().map(|s| format!(", since {s}")).unwrap_or_default();
    // Item 99: the line ends with the release tags read, `vX.Y.Z` without the key.
    let tags = git["release_tags"].as_str().unwrap_or("vX.Y.Z");
    out += &match git["default_branch"].as_str() {
        Some(branch) => format!(
            "git: default branch {branch}; {} release(s){since}; lock rows without log times come from the branch tip; release tags: {tags}\n",
            // The releases read: all of them, or those at or after `--since` (deploys' `n`).
            dora["deploys"]["n"]
        ),
        None => format!(
            "git: no evidence ({}){since}; lock rows without log times come from the branch tip when git reads; release tags: {tags}\n",
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
            format!("median {}, p90 {}", span(&v["median"]), span(&v["p90"]))
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
            time(&v["first"]),
            time(&v["last"]),
            show_with(&v["per_day"], |x| format!("{x:.2}")),
            tail(d)
        )
    };
    out += &format!("lead time: {}{}", spread(&dora["lead_time"]), tail(&dora["lead_time"]));
    out += &format!("rework rate: {}{}", share(&dora["rework_rate"]["value"]), tail(&dora["rework_rate"]));
    out += &format!("time to recover: {}{}", spread(&dora["time_to_recover"]), tail(&dora["time_to_recover"]));
    out += &format!(
        "change failure rate: {}{}",
        share(&dora["change_failure_rate"]["value"]),
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
    fn readable_text_forms() {
        assert_eq!(utc(100.9), "1970-01-01T00:01:40Z");
        assert_eq!(utc(-1.0), "1969-12-31T23:59:59Z");
        for (x, want) in [
            (0.0, "0 s"),
            (59.0, "59 s"),
            (60.0, "1 min 0 s"),
            (3599.0, "59 min 59 s"),
            (3600.0, "1 h 0 min 0 s"),
            (4226.0, "1 h 10 min 26 s"),
            (97_384.0, "27 h 3 min 4 s"),
            (-65.0, "-1 min 5 s"),
            (-0.4, "0 s"),
        ] {
            assert_eq!(duration(x), want);
        }
        assert_eq!(percent(2.0 / 3.0), "67%");
        assert_eq!(percent(0.0), "0%");
    }

    #[test]
    fn release_tag_patterns_match_whole_names() {
        let m = |p: &str, n: &str| matches(p.as_bytes(), n.as_bytes());
        assert!(m("deploy-*", "deploy-20261107-1730"));
        assert!(m("deploy-*", "deploy-"));
        assert!(!m("deploy-*", "deployed/prod"));
        assert!(m("draken-platform-v*", "draken-platform-v0.1.0"));
        assert!(!m("draken-platform-v*", "v1.0.0"));
        assert!(m("v*", "v2.48.0") && m("v*", "v2"));
        assert!(!m("v*", "xv2"));
        assert!(m("rel/*", "rel/a/b"));
        assert!(m("*-prod", "a/b-prod") && !m("*-prod", "a-prod-x"));
        assert!(m("a*b*c", "aXbYbZc") && !m("a*b*c", "aXbYbZ"));
        assert!(m("a**", "a") && m("exact", "exact") && !m("exact", "exact2"));
    }

    #[test]
    fn selection_reads_only_the_report_table_and_never_refuses() {
        let dir = std::env::temp_dir().join(format!("item99-sel-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let read = |content: Option<&[u8]>| {
            let path = dir.join(CONFIG_FILE);
            let _ = fs::remove_file(&path);
            let _ = fs::remove_dir_all(&path);
            if let Some(bytes) = content {
                fs::write(&path, bytes).unwrap();
            }
            match Selection::read(&dir) {
                Selection::Default => "default".to_string(),
                Selection::Pattern(p) => format!("pattern {p}"),
                Selection::Invalid(p) => format!("invalid {p}"),
            }
        };
        assert_eq!(read(None), "default");
        assert_eq!(read(Some(b"this is not toml")), "default");
        assert_eq!(read(Some(b"x = \"\xff\"")), "default");
        assert_eq!(read(Some(b"[[suite]]\nroot = \"a\"\n")), "default");
        assert_eq!(read(Some(b"[report]\n")), "default");
        assert_eq!(read(Some(b"shipcraft_min = \"99\"\n[report]\nrelease_tags = \"deploy-*\"")), "pattern deploy-*");
        assert_eq!(read(Some(b"[report]\nrelease_tag = \"deploy-*\"")), "invalid unknown key release_tag");
        assert_eq!(read(Some(b"report = \"v*\"")), "invalid [report] is not a table");
        fs::remove_file(dir.join(CONFIG_FILE)).unwrap();
        fs::create_dir_all(dir.join(CONFIG_FILE)).unwrap();
        assert!(matches!(Selection::read(&dir), Selection::Default));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn fixes_release_must_be_a_release_name_of_the_selection() {
        let default = Selection::Default;
        assert_eq!(default.release_name_problem("v2.25.0"), None);
        assert_eq!(default.release_name_problem("2.25.0").as_deref(), Some("vX.Y.Z"));
        assert_eq!(default.release_name_problem("deploy-1").as_deref(), Some("vX.Y.Z"));
        let deploy = Selection::Pattern("deploy-*".into());
        assert_eq!(deploy.release_name_problem("deploy-20261112-200036"), None);
        assert_eq!(deploy.release_name_problem("v1.0.0").as_deref(), Some("deploy-*"));
        assert_eq!(deploy.release_name_problem("deployed/prod").as_deref(), Some("deploy-*"));
        let v = Selection::Pattern("v*".into());
        assert_eq!(v.release_name_problem("v1.0.0"), None);
        assert_eq!(v.release_name_problem("v2"), None);
        let invalid = Selection::Invalid("unknown key release_tag".into());
        for tag in ["v1.0.0", "deploy-1"] {
            assert_eq!(
                invalid.release_name_problem(tag).as_deref(),
                Some("invalid: [report] in .shipcraft.toml is invalid: unknown key release_tag")
            );
        }
    }

    #[test]
    fn a_red_row_fixes_release_is_read_when_a_tag_name() {
        let row = |release: Value| -> Row {
            json!({"kind": "fix", "reported_at": null, "fixes_release": release}).as_object().unwrap().clone()
        };
        for (value, read) in [
            (json!(null), None),
            (json!("v1.0.0"), Some("v1.0.0")),
            (json!("deploy-20261112-200036"), Some("deploy-20261112-200036")),
            (json!("packages/api/v1.0.0"), Some("packages/api/v1.0.0")),
            (json!("a..b"), None),
            (json!("a b"), None),
            (json!(""), None),
            (json!(1), None),
        ] {
            assert_eq!(fix_of_row(&row(value.clone())).fixes_release.as_deref(), read, "{value}");
        }
    }

    #[test]
    fn size_counts_each_pr_by_its_last_measured_row_before_its_merge() {
        let rows = |log: &str| read(log.as_bytes()).0;
        let pr = |n: u64, lines: u64, limit: u64| {
            format!("{{\"layer\":\"pr\",\"result\":\"refused\",\"pr\":{n},\"product_lines\":{lines},\"warn_lines\":{limit}}}\n")
        };
        let merge = |n: u64, base: &str| {
            format!("{{\"layer\":\"merge\",\"result\":\"passed\",\"pr\":{n},\"base\":\"{base}\",\"default_branch\":\"main\"}}\n")
        };
        // No measured row: no line. Each of these is skipped, never a gap.
        for row in [
            r#"{"layer":"pr","pr":1,"product_lines":400.0,"warn_lines":500}"#,
            r#"{"layer":"pr","pr":1,"product_lines":4e2,"warn_lines":500}"#,
            r#"{"layer":"pr","pr":1,"product_lines":"400","warn_lines":500}"#,
            r#"{"layer":"pr","pr":1,"product_lines":400,"warn_lines":-1}"#,
            r#"{"layer":"pr","pr":1,"product_lines":400}"#,
            r#"{"layer":"pr","pr":0,"product_lines":400,"warn_lines":500}"#,
            r#"{"layer":"pr","pr":1.0,"product_lines":400,"warn_lines":500}"#,
            r#"{"layer":"ci","pr":1,"product_lines":400,"warn_lines":500}"#,
            r#"{"layer":"pr","pr":1,"product_lines":400,"warn_lines":500,"escape":true}"#,
        ] {
            assert_eq!(size(&rows(row)), None, "{row}");
        }
        assert_eq!(size(&rows(&(merge(1, "main") + &pr(1, 900, 500)))), None);
        // The last measured row gives the size and the limit; equal is not above.
        let log = pr(1, 900, 500) + &pr(1, 500, 500) + &pr(2, 1, 0) + &pr(3, 0, 0);
        assert_eq!(
            size(&rows(&log)).unwrap().to_string(),
            r#"{"above":1,"above_share":0.3333333333333333,"kind":"size","merged_above":0,"merged_above_share":null,"merged_prs":0,"prs":3}"#
        );
        // Rows after the first counting merge are not measured; a merge into
        // another base, a refused one and an escape do not count.
        let log = pr(1, 600, 500)
            + &merge(1, "main")
            + &pr(1, 10, 500)
            + &pr(2, 10, 500)
            + &merge(2, "release")
            + &pr(2, 700, 500)
            + &pr(3, 800, 500)
            + r#"{"layer":"merge","result":"refused","pr":3,"base":"main","default_branch":"main"}"#
            + "\n"
            + r#"{"layer":"merge","result":"passed","pr":3,"base":"main","default_branch":"main","escape":true}"#
            + "\n"
            + &pr(4, 10, 500)
            + &merge(4, "main");
        let line = size(&rows(&log)).unwrap();
        assert_eq!(
            line,
            json!({"kind": "size", "prs": 4, "above": 3, "above_share": 0.75,
                "merged_prs": 2, "merged_above": 1, "merged_above_share": 0.5})
        );
        assert_eq!(text(&[line]), "size: 4 PR(s) measured, 3 above their limit (75%); merged 2, 1 above (50%)\n");
        let line = size(&rows(&pr(7, 1, 500))).unwrap();
        assert_eq!(line["above_share"].to_string(), "0");
        assert_eq!(text(&[line]), "size: 1 PR(s) measured, 0 above their limit (0%); merged 0, 0 above (-)\n");
    }

    #[test]
    fn reds_count_each_red_row_green_again_by_a_later_green_row_on_its_commit() {
        let rows = |log: &str| read(log.as_bytes()).0;
        let red = |commit: &str, secs: &str, failed: &str| {
            format!("{{\"layer\":\"ci\",\"result\":\"refused\",\"code\":\"suite-red\",\"commit\":{commit},\"secs\":{secs}{failed}}}\n")
        };
        let green =
            |commit: &str| format!("{{\"layer\":\"ci\",\"result\":\"passed\",\"commit\":{commit},\"secs\":3}}\n");
        // No red row: no line. None of these is a red row, nor a gap.
        for row in [
            String::new(),
            green("\"a\""),
            r#"{"layer":"ci","result":"refused","code":"no-report","commit":"a","secs":5}"#.to_string(),
            r#"{"layer":"ci","result":"refused","code":"case-broke","commit":"a"}"#.to_string(),
            r#"{"layer":"ci","result":"error","code":"suite-red","commit":"a"}"#.to_string(),
            r#"{"layer":"ci","result":"error","code":"timed-out","commit":"a"}"#.to_string(),
            r#"{"layer":"hook","result":"refused","code":"suite-red","commit":"a"}"#.to_string(),
            red("\"\"", "1", ""),
            red("7", "1", ""),
            red("null", "1", ""),
            r#"{"layer":"ci","result":"refused","code":"suite-red"}"#.to_string(),
            r#"{"layer":"ci","result":"refused","code":"suite-red","commit":"a","escape":true}"#.to_string(),
        ] {
            assert_eq!(reds(&rows(&row)), None, "{row}");
        }
        // A red row alone: counted, never green again.
        let line = reds(&rows(&red("\"a\"", "12", ",\"failed\":[\"t1\"]"))).unwrap();
        assert_eq!(
            line.to_string(),
            r#"{"cases":[],"green_again":0,"green_again_secs":0,"green_again_share":0,"kind":"reds","named":0,"suite_red":1}"#
        );
        assert_eq!(
            text(&[line]),
            "reds: 1 suite-red, 0 green again on the same commit (0%), 0 s of CI; cases named in 0: none\n"
        );
        // File order: a green row before the red row, or on another commit, does not count.
        let log = green("\"a\"") + &red("\"a\"", "5", "") + &green("\"b\"");
        assert_eq!(reds(&rows(&log)).unwrap()["green_again"], 0);
        // Two reds, one green: both green again; time summed, fractions kept.
        let log = red("\"a\"", "100.5", ",\"failed\":[]") + &red("\"a\"", "25", "") + &green("\"a\"");
        let line = reds(&rows(&log)).unwrap();
        assert_eq!(
            line,
            json!({"kind": "reds", "suite_red": 2, "green_again": 2, "green_again_share": 1,
                "green_again_secs": 125.5, "named": 1, "cases": []})
        );
        assert_eq!(line["green_again_share"].to_string(), "1");
        assert_eq!(
            text(&[line]),
            "reds: 2 suite-red, 2 green again on the same commit (100%), 2 min 6 s of CI; cases named in 1: none\n"
        );
        // Commits compare byte for byte; branch and lock play no part.
        let log =
            red("\"a\"", "1", "") + r#"{"layer":"ci","result":"passed","commit":"A","branch":"x","lock":"y"}"# + "\n";
        assert_eq!(reds(&rows(&log)).unwrap()["green_again"], 0);
        // Green rows that did not run the suite do not count; any value but true does.
        for (field, counts) in [
            ("\"docs_only\":true", false),
            ("\"suite_in_checks\":true", false),
            ("\"docs_only\":false", true),
            ("\"docs_only\":\"true\"", true),
            ("\"suite_in_checks\":1", true),
            ("\"suite_in_checks\":null", true),
        ] {
            let log = red("\"a\"", "1", "")
                + &format!("{{\"layer\":\"ci\",\"result\":\"passed\",\"commit\":\"a\",{field}}}\n");
            assert_eq!(reds(&rows(&log)).unwrap()["green_again"], u64::from(counts), "{field}");
        }
        // Other green-row shapes: not ci, not passed, empty or non-string commit.
        for row in [
            r#"{"layer":"hook","result":"passed","commit":"a"}"#,
            r#"{"layer":"ci","result":"error","commit":"a"}"#,
            r#"{"layer":"ci","result":"passed","commit":""}"#,
            r#"{"layer":"ci","result":"passed","commit":["a"]}"#,
            r#"{"layer":"ci","result":"passed","commit":"a","escape":true}"#,
        ] {
            let log = red("\"a\"", "1", "") + row + "\n";
            assert_eq!(reds(&rows(&log)).unwrap()["green_again"], 0, "{row}");
        }
        // Secs that are not a number of 0 or more add 0.
        for secs in ["-3", "\"40\"", "null", "true"] {
            let log = red("\"a\"", secs, "") + &green("\"a\"");
            assert_eq!(reds(&rows(&log)).unwrap()["green_again_secs"].to_string(), "0", "{secs}");
        }
        let log = red("\"a\"", "3725", "") + &green("\"a\"");
        assert!(text(&[reds(&rows(&log)).unwrap()]).contains(", 1 h 2 min 5 s of CI;"));
        // Failed: only an array names; non-strings skipped; a duplicate taken once per row.
        for failed in [",\"failed\":\"t1\"", ",\"failed\":{\"t1\":1}", ",\"failed\":null", ""] {
            let log = red("\"a\"", "1", failed) + &green("\"a\"");
            let line = reds(&rows(&log)).unwrap();
            assert_eq!((line["named"].clone(), line["cases"].clone()), (json!(0), json!([])), "{failed}");
        }
        let log = red("\"a\"", "1", ",\"failed\":[\"t1\",\"t1\",2,null,\"t2\"],\"failed_count\":99") + &green("\"a\"");
        assert_eq!(reds(&rows(&log)).unwrap()["cases"], json!([{"id": "t1", "rows": 1}, {"id": "t2", "rows": 1}]));
        // Top 5 by rows, ties by byte order; only green-again rows give cases.
        let log = red("\"a\"", "1", ",\"failed\":[\"z\",\"b\",\"B\",\"a\"]")
            + &red("\"a\"", "1", ",\"failed\":[\"z\",\"b\",\"c\",\"d\"]")
            + &red("\"a\"", "1", ",\"failed\":[\"z\",\"e\"]")
            + &green("\"a\"")
            + &red("\"a\"", "1", ",\"failed\":[\"z\",\"never\"]")
            + &red("\"c\"", "1", ",\"failed\":[\"never\"]");
        let line = reds(&rows(&log)).unwrap();
        assert_eq!(
            line,
            json!({"kind": "reds", "suite_red": 5, "green_again": 3, "green_again_share": 0.6,
                "green_again_secs": 3, "named": 3, "cases": [
                    {"id": "z", "rows": 3}, {"id": "b", "rows": 2}, {"id": "B", "rows": 1},
                    {"id": "a", "rows": 1}, {"id": "c", "rows": 1}]})
        );
        assert_eq!(
            text(&[line]),
            "reds: 5 suite-red, 3 green again on the same commit (60%), 3 s of CI; cases named in 3: \"z\" (3), \"b\" (2), \"B\" (1), \"a\" (1), \"c\" (1)\n"
        );
        // Ids in the text are JSON string literals; the JSON holds the id itself.
        let log = red("\"a\"", "1", r#","failed":["t, (1)\n\"x\"\\\u0001\u007f"]"#) + &green("\"a\"");
        let line = reds(&rows(&log)).unwrap();
        assert_eq!(line["cases"][0]["id"], "t, (1)\n\"x\"\\\u{1}\u{7f}");
        assert_eq!(
            text(&[line]),
            "reds: 1 suite-red, 1 green again on the same commit (100%), 1 s of CI; cases named in 1: \"t, (1)\\n\\\"x\\\"\\\\\\u0001\u{7f}\" (1)\n"
        );
        // A third share prints its fraction in JSON and a whole percent in text.
        let log = red("\"a\"", "0.4", "") + &red("\"b\"", "1", "") + &red("\"c\"", "1", "") + &green("\"a\"");
        let line = reds(&rows(&log)).unwrap();
        assert_eq!(line["green_again_share"].to_string(), "0.3333333333333333");
        assert_eq!(line["green_again_secs"].to_string(), "0.4");
        assert_eq!(
            text(&[line]),
            "reds: 3 suite-red, 1 green again on the same commit (33%), 0 s of CI; cases named in 0: none\n"
        );
    }

    #[test]
    fn review_counts_the_round_rows_of_each_pr() {
        let rows = |log: &str| read(log.as_bytes()).0;
        let round = |pr: &str, result: &str| format!("{{\"layer\":\"review\",\"pr\":{pr},\"result\":\"{result}\"}}\n");
        // No round row: no line. None of these is a round row, nor a gap.
        for row in [
            String::new(),
            round("7", "error"),
            round("7", "skipped"),
            r#"{"layer":"review","pr":7,"result":"passed","reused":true}"#.to_string(),
            r#"{"layer":"review","pr":7,"result":"passed","escape":true}"#.to_string(),
            r#"{"layer":"review","result":"passed"}"#.to_string(),
            r#"{"layer":"pr","pr":7,"result":"passed"}"#.to_string(),
            r#"{"layer":"merge","pr":7,"result":"passed"}"#.to_string(),
            r#"{"pr":7,"result":"passed"}"#.to_string(),
            round("0", "passed"),
            round("-1", "passed"),
            round("7.0", "passed"),
            round("7e0", "passed"),
            round("\"7\"", "passed"),
            round("true", "passed"),
            round("null", "passed"),
            round("[7]", "passed"),
            round("18446744073709551616", "passed"),
        ] {
            assert_eq!(review(&rows(&row)), None, "{row}");
            assert!(read(row.as_bytes()).1.is_empty(), "{row}");
        }
        // Any `reused` but true is a fresh round; one round is no second round.
        for reused in ["", ",\"reused\":false", ",\"reused\":\"true\"", ",\"reused\":1", ",\"reused\":null"] {
            let log = format!("{{\"layer\":\"review\",\"pr\":7,\"result\":\"refused\"{reused}}}\n");
            let line = review(&rows(&log)).unwrap();
            assert_eq!(
                line.to_string(),
                r#"{"changes_requested":1,"kind":"review","most":[],"prs":1,"rounds":1,"second_round":0,"second_round_share":0}"#,
                "{reused}"
            );
            assert_eq!(
                text(&[line]),
                "review: 1 PR(s) reviewed in 1 round(s), 1 requested changes; 0 needed a second round (0%): none\n"
            );
        }
        // Rows anywhere in the file; errors and reused verdicts between them add nothing.
        let log = round("12", "refused")
            + &round("9", "refused")
            + &round("12", "error")
            + r#"{"layer":"review","pr":12,"result":"passed","reused":true}"#
            + "\n"
            + &round("12", "refused")
            + &round("3", "passed")
            + &round("9", "passed")
            + &round("12", "passed")
            + &round("4", "passed");
        let line = review(&rows(&log)).unwrap();
        assert_eq!(
            line,
            json!({"kind": "review", "prs": 4, "rounds": 7, "changes_requested": 3, "second_round": 2,
                "second_round_share": 0.5, "most": [{"pr": 12, "rounds": 3}, {"pr": 9, "rounds": 2}]})
        );
        assert_eq!(
            text(&[line]),
            "review: 4 PR(s) reviewed in 7 round(s), 3 requested changes; 2 needed a second round (50%): #12 (3), #9 (2)\n"
        );
        // Ties by PR number as numbers; at most 5 listed; the share a whole 1.
        let mut log = String::new();
        for pr in ["100", "20", "3", "20", "100", "3", "7", "7", "50", "50", "8", "8", "8"] {
            log += &round(pr, "passed");
        }
        let line = review(&rows(&log)).unwrap();
        assert_eq!(
            line,
            json!({"kind": "review", "prs": 6, "rounds": 13, "changes_requested": 0, "second_round": 6,
                "second_round_share": 1, "most": [{"pr": 8, "rounds": 3}, {"pr": 3, "rounds": 2},
                {"pr": 7, "rounds": 2}, {"pr": 20, "rounds": 2}, {"pr": 50, "rounds": 2}]})
        );
        assert_eq!(line["second_round_share"].to_string(), "1");
        assert_eq!(
            text(&[line]),
            "review: 6 PR(s) reviewed in 13 round(s), 0 requested changes; 6 needed a second round (100%): #8 (3), #3 (2), #7 (2), #20 (2), #50 (2)\n"
        );
        // A third share prints its fraction in JSON and a whole percent in text.
        let log = round("1", "passed") + &round("1", "passed") + &round("2", "passed") + &round("3", "passed");
        let line = review(&rows(&log)).unwrap();
        assert_eq!(line["second_round_share"].to_string(), "0.3333333333333333");
        assert!(text(&[line]).ends_with("1 needed a second round (33%): #1 (2)\n"));
    }

    #[test]
    fn blocking_groups_reviewed_commits_and_ranks_prs() {
        let rows = |log: &str| read(log.as_bytes()).0;
        let sha = |c: char| c.to_string().repeat(40);
        let path = |c: &str| format!("repos/{{owner}}/{{repo}}/commits/{c}/statuses?per_page=100");
        let round =
            |pr: u64, commit: &str| format!("{{\"layer\":\"review\",\"pr\":{pr},\"result\":\"passed\"{commit}}}\n");
        let at = |c: char| format!(",\"commit\":\"{}\"", sha(c));
        let count = |n: u64| {
            json!([[{"context": "shipcraft/review", "created_at": "2026-01-01T00:00:00Z",
                "description": format!("on this machine: APPROVE, Blocking {n} (a)")}]])
        };
        let (a, b, c, d, e, f, g) = (sha('a'), sha('b'), sha('c'), sha('d'), sha('e'), sha('f'), sha('1'));
        let (pa, pb, pc, pd, pe, pf, pg) = (path(&a), path(&b), path(&c), path(&d), path(&e), path(&f), path(&g));
        fn ask<'p>(
            p: &'p str,
            outcome: std::result::Result<Value, &'static str>,
        ) -> (Vec<&'p str>, std::result::Result<Value, &'static str>) {
            (vec!["api", "--paginate", "--slurp", p], outcome)
        }
        // Two rounds on one commit are one reviewed commit; one commit under two PRs is two.
        let log = round(12, &at('a'))
            + &round(12, &at('a'))
            + &round(12, &at('b'))
            + &round(9, &at('a'))
            + &round(9, "")
            + &round(9, ",\"commit\":null")
            + &round(9, ",\"commit\":1")
            + &round(9, ",\"commit\":1.0")
            + &round(9, &at('a').to_uppercase().replace("COMMIT", "commit"))
            + &round(9, ",\"commit\":\"abc\"")
            + &round(3, &at('c'))
            + &round(4, &at('d'))
            + &round(5, &at('e'))
            + &round(6, &at('f'))
            + &round(7, &at('1'));
        let rows = rows(&log);
        assert_eq!(reviewed_commits(&rows).len(), 14);
        let mut asker = Asker::answered(
            vec![
                ask(&pa, Ok(count(2))),
                ask(&pb, Ok(count(1))),
                ask(&pc, Ok(count(3))),
                ask(&pd, Ok(count(3))),
                ask(&pe, Ok(json!([[]]))),
                ask(&pf, Err("gh failed")),
                ask(&pg, Ok(count(1))),
            ],
            false,
        );
        let mut line = review(&rows).unwrap();
        let plain = text(&[line.clone()]);
        blocking(&mut asker, &rows, &mut line);
        assert_eq!(line["blocking"], 12);
        assert_eq!(line["blocking_read"], 6);
        assert_eq!(line["blocking_commits"], 14);
        assert_eq!(
            line["blocking_missing"],
            json!({"gh failed": 1, "no blocking count at commit": 1, "no commit in the run log": 6})
        );
        assert_eq!(
            line["blocking_most"],
            json!([{"pr": 3, "blocking": 3}, {"pr": 4, "blocking": 3}, {"pr": 12, "blocking": 3},
                {"pr": 9, "blocking": 2}, {"pr": 7, "blocking": 1}])
        );
        assert_eq!(
            text(&[line]),
            plain.trim_end().to_string()
                + "; Blocking 12 in 6 of 14 reviewed commit(s): #3 (3), #4 (3), #12 (3), #9 (2), #7 (1); \
                   not read: gh failed 1, no blocking count at commit 1, no commit in the run log 6\n"
        );
        // Everything read: no `not read`; nothing above 0: `none`.
        let rows = read(round(7, &at('a')).as_bytes()).0;
        let mut asker = Asker::answered(vec![ask(&pa, Ok(count(0)))], false);
        let mut line = review(&rows).unwrap();
        blocking(&mut asker, &rows, &mut line);
        assert_eq!(line["blocking_missing"], json!({}));
        assert!(text(&[line]).ends_with("(0%): none; Blocking 0 in 1 of 1 reviewed commit(s): none\n"));
        // After a timeout, every commit counts as timed out, but one with no commit.
        let rows = read((round(7, &at('a')) + &round(8, "")).as_bytes()).0;
        let mut asker = Asker::answered(vec![ask(&pa, Ok(count(4)))], true);
        let mut line = review(&rows).unwrap();
        blocking(&mut asker, &rows, &mut line);
        assert_eq!(line["blocking_missing"], json!({"gh timed out": 1, "no commit in the run log": 1}));
        assert_eq!(line["blocking"], 0);
        assert_eq!(line["blocking_most"], json!([]));
    }

    #[test]
    fn checks_read_each_reviewed_pr_in_full_and_sum_per_name() {
        let names: &[&str] = &["acceptance", "a;b: c"];
        let sha = |c: char| c.to_string().repeat(40);
        let commits = |pr: u64| format!("repos/{{owner}}/{{repo}}/pulls/{pr}/commits?per_page=100");
        let runs = |c: char| format!("repos/{{owner}}/{{repo}}/commits/{}/check-runs?filter=all&per_page=100", sha(c));
        let round = |pr: u64| format!("{{\"layer\":\"review\",\"pr\":{pr},\"result\":\"refused\"}}\n");
        let run = |name: &str, conclusion: &str, s: u32| {
            json!({"name": name, "status": "completed", "conclusion": conclusion,
                "completed_at": format!("2026-01-01T00:00:{s:02}Z")})
        };
        let at = |runs: Vec<Value>| json!([{"total_count": runs.len(), "check_runs": runs}]);
        let list = |cs: &[char]| json!([cs.iter().map(|c| json!({"sha": sha(*c)})).collect::<Vec<_>>()]);
        fn ask<'p>(
            p: &'p str,
            outcome: std::result::Result<Value, &'static str>,
        ) -> (Vec<&'p str>, std::result::Result<Value, &'static str>) {
            (vec!["api", "--paginate", "--slurp", p], outcome)
        }
        let (c3, c9, c4, c8) = (commits(3), commits(9), commits(4), commits(8));
        let (ra, rb, rc) = (runs('a'), runs('b'), runs('c'));
        // PR 9 shares commit b with PR 3; PR 4 fails; PR 8 is unreadable; PR 3 again is one PR.
        let rows = read((round(9) + &round(3) + &round(9) + &round(4) + &round(8)).as_bytes()).0;
        let answers = || {
            vec![
                ask(&c9, Ok(list(&['a', 'b']))),
                ask(&c3, Ok(list(&['b', 'c']))),
                ask(&c4, Err("gh failed")),
                ask(&c8, Ok(json!([]))),
                ask(&ra, Ok(at(vec![run("acceptance", "failure", 1), run("acceptance", "success", 2)]))),
                ask(&rb, Ok(at(vec![run("a;b: c", "failure", 3), run("acceptance", "success", 3)]))),
                ask(&rc, Ok(at(vec![run("a;b: c", "success", 4)]))),
            ]
        };
        let mut asker = Asker::answered(answers(), false).configured(Some(names));
        let line = checks(&mut asker, &rows).unwrap();
        assert_eq!(
            line,
            json!({"kind": "checks", "prs": 4, "prs_read": 2,
                "missing": {"gh failed": 1, "unreadable answer from gh": 1},
                "names": [
                    {"name": "acceptance", "runs": 4, "red": 1, "green_again": 1, "new_commit": 0, "still_red": 0},
                    {"name": "a;b: c", "runs": 3, "red": 2, "green_again": 0, "new_commit": 1, "still_red": 1}]})
        );
        assert_eq!(
            text(&[line]),
            "checks: 2 of 4 reviewed PR(s) read; \"acceptance\": 1 red in 4 run(s), 1 green again on the same commit, \
             0 fixed by a new commit, 0 still red; \"a;b: c\": 2 red in 3 run(s), 0 green again on the same commit, \
             1 fixed by a new commit, 1 still red; not read: gh failed 1, unreadable answer from gh 1\n"
        );
        // A timeout: every PR counts as timed out, also one whose answers are in hand.
        let mut asker = Asker::answered(answers(), true).configured(Some(names));
        let line = checks(&mut asker, &rows).unwrap();
        assert_eq!(line["missing"], json!({"gh timed out": 4}));
        assert_eq!(
            line["names"][1],
            json!({"name": "a;b: c", "runs": 0, "red": 0, "green_again": 0, "new_commit": 0, "still_red": 0})
        );
        // Every PR read: no `not read`.
        let rows9 = read(round(9).as_bytes()).0;
        let mut asker = Asker::answered(answers(), false).configured(Some(&["acceptance"]));
        assert_eq!(
            text(&[checks(&mut asker, &rows9).unwrap()]),
            "checks: 1 of 1 reviewed PR(s) read; \"acceptance\": 1 red in 3 run(s), 1 green again on the same commit, \
             0 fixed by a new commit, 0 still red\n"
        );
        // No reviewed PR, no readable config, or no name: no object and no call.
        for (rows, config) in [
            (read(b"{\"layer\":\"review\",\"result\":\"passed\"}").0, Some(names)),
            (rows9.clone(), None),
            (rows9, Some(&[][..])),
        ] {
            let mut asker = Asker::answered(vec![], false).configured(config);
            assert_eq!(checks(&mut asker, &rows), None);
        }
    }

    #[test]
    fn reader_strips_bom_and_cr_and_counts_physical_lines() {
        let (rows, gaps) = read("\u{feff}{\"at\":1}\r\n\r\n[]\r\n{\"at\":2,\"escape\":true}\n{bad".as_bytes());
        assert_eq!(rows.len(), 1);
        assert_eq!(gaps.iter().map(|g| g.0).collect::<Vec<_>>(), vec![3, 5]);
    }
}
