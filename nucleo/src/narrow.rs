//! Item 55: `red` runs the RED's changed test files. The base, the paths
//! changed since it, each suite's selected files, and why `red` runs every
//! suite instead when it cannot narrow safely.

use crate::config::{Config, CONFIG_FILE};
use crate::git::{git_in, Repo};
use serde_json::{json, Value};
use std::collections::BTreeSet;
use std::fs;

/// The base `red` narrows against when `--base` does not name one.
const DEFAULT_BASE: &str = "refs/remotes/origin/HEAD";

/// Why `red` ran every suite, in the order the first that applies is reported.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Fallback {
    Redo,
    All,
    NoBase,
    NoMergeBase,
    GitFailed,
    ConfigChanged,
    ProtectedRemoved,
    UnreadablePath,
    NothingSelected,
    NoReport,
    CaseWithoutFile,
    FileWithoutCases,
}

impl Fallback {
    pub fn text(self) -> &'static str {
        match self {
            Fallback::Redo => "--redo",
            Fallback::All => "--all",
            Fallback::NoBase => "no base",
            Fallback::NoMergeBase => "no merge base",
            Fallback::GitFailed => "git failed",
            Fallback::ConfigChanged => "config changed",
            Fallback::ProtectedRemoved => "protected file removed",
            Fallback::UnreadablePath => "unreadable path",
            Fallback::NothingSelected => "nothing selected",
            Fallback::NoReport => "no report",
            Fallback::CaseWithoutFile => "case without file",
            Fallback::FileWithoutCases => "file without cases",
        }
    }
}

/// What `red` runs first: every suite, and why; or each suite's selected
/// files (from its root, one set per suite in configuration order) and how
/// many distinct files that is, by repository path.
pub enum Plan {
    All(Fallback),
    Changed { selected: Vec<BTreeSet<String>>, files: usize },
}

/// How the first run went, once the selection is decided: the notice and the
/// run log row's three fields. `fallback` is set when a narrowed run falls back.
pub struct Chosen {
    pub selected: usize,
    pub locked: usize,
    pub fallback: Option<Fallback>,
}

impl Chosen {
    pub fn new(plan: &Plan, locked: usize) -> Chosen {
        match plan {
            Plan::All(why) => Chosen { selected: 0, locked, fallback: Some(*why) },
            Plan::Changed { files, .. } => Chosen { selected: *files, locked, fallback: None },
        }
    }

    /// The line `red` prints before its usual lines.
    pub fn notice(&self) -> String {
        match self.fallback {
            Some(why) => format!("shipcraft: red ran every suite: {}", why.text()),
            None => format!("shipcraft: red ran the changed test files: {} of {}", self.selected, self.locked),
        }
    }

    /// `selection`, `selected_files` and `fallback` on the `red` row.
    pub fn record(&self, row: &mut Value) {
        row["selection"] = json!(if self.fallback.is_some() { "all" } else { "changed" });
        row["selected_files"] = json!(self.selected);
        row["fallback"] = self.fallback.map_or(Value::Null, |why| json!(why.text()));
    }
}

/// The plan for `red` (not `--redo`): `--all`, or the changed test files
/// since the merge base of HEAD and `base` (origin's HEAD when not given).
pub fn plan(repo: &Repo, config: &Config, base: Option<&str>, all: bool) -> Plan {
    if all {
        return Plan::All(Fallback::All);
    }
    let base = match base_commit(repo, base.unwrap_or(DEFAULT_BASE)) {
        Ok(base) => base,
        Err(why) => return Plan::All(why),
    };
    let changed = match changed_paths(repo, &base) {
        Some(changed) => changed,
        None => return Plan::All(Fallback::GitFailed),
    };
    select(repo, config, changed)
}

/// The one merge base of HEAD and `rev`.
fn base_commit(repo: &Repo, rev: &str) -> std::result::Result<String, Fallback> {
    let Some(base) = repo.resolve(rev).map_err(|_| Fallback::GitFailed)? else { return Err(Fallback::NoBase) };
    if repo.head().map_err(|_| Fallback::GitFailed)?.is_none() {
        return Err(Fallback::NoMergeBase);
    }
    let out = git_in(repo.root(), &["merge-base", "--all", "HEAD", &base]).map_err(|_| Fallback::GitFailed)?;
    let bases: Vec<&[u8]> = out.stdout.split(|b| *b == b'\n').filter(|line| !line.is_empty()).collect();
    match (out.status.code(), &bases[..]) {
        (Some(0), [one]) => Ok(String::from_utf8_lossy(one).into_owned()),
        // Exit 1 with nothing printed: no merge base.
        (Some(0), _) | (Some(1), []) => Err(Fallback::NoMergeBase),
        _ => Err(Fallback::GitFailed),
    }
}

/// A changed path as git reports it: whether it was at the base (the diff's
/// entries that are not added), and its bytes. None when git fails.
fn changed_paths(repo: &Repo, base: &str) -> Option<Vec<(bool, Vec<u8>)>> {
    let diff = repo.run(&["diff", "-z", "--name-status", "--no-renames", base, "--"]).ok()?;
    let mut fields = diff.split(|b| *b == 0).filter(|field| !field.is_empty());
    let mut changed = Vec::new();
    while let (Some(status), Some(path)) = (fields.next(), fields.next()) {
        changed.push((status != b"A", path.to_vec()));
    }
    let untracked = repo.run(&["ls-files", "-z", "--others", "--exclude-standard"]).ok()?;
    changed.extend(untracked.split(|b| *b == 0).filter(|path| !path.is_empty()).map(|path| (false, path.to_vec())));
    Some(changed)
}

/// Each suite's selected files among the changed paths, or the first reason
/// to run every suite instead.
fn select(repo: &Repo, config: &Config, changed: Vec<(bool, Vec<u8>)>) -> Plan {
    let suites = config.suites();
    let mut selected = vec![BTreeSet::new(); suites.len()];
    let mut files = BTreeSet::new();
    let mut why: Option<Fallback> = None;
    let mut fall = |reason: Fallback| why = Some(why.map_or(reason, |first| first.min(reason)));
    for (at_base, path) in changed {
        let Ok(path) = String::from_utf8(path) else {
            fall(Fallback::UnreadablePath);
            continue;
        };
        if path == CONFIG_FILE {
            fall(Fallback::ConfigChanged);
            continue;
        }
        let holders: Vec<usize> = (0..suites.len()).filter(|&i| suites[i].matches(&path)).collect();
        if holders.is_empty() {
            continue;
        }
        // A link is not a regular file, as `lstat` sees it.
        let regular = fs::symlink_metadata(repo.path(&path)).is_ok_and(|m| m.is_file());
        if at_base && !regular {
            fall(Fallback::ProtectedRemoved);
        }
        if !regular || fs::File::open(repo.path(&path)).is_err() {
            fall(Fallback::UnreadablePath);
            continue;
        }
        for i in holders {
            let prefix = suites[i].prefix();
            selected[i].insert(path.strip_prefix(&prefix).unwrap_or(&path).to_string());
        }
        files.insert(path);
    }
    if files.is_empty() {
        fall(Fallback::NothingSelected);
    }
    match why {
        Some(why) => Plan::All(why),
        None => Plan::Changed { selected, files: files.len() },
    }
}
