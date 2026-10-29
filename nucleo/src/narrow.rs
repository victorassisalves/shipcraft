//! Item 55: `red` runs the RED's changed test files. The base, the paths
//! changed since it, each suite's selected files, and why `red` runs every
//! suite instead when it cannot narrow safely. Item 60: `red --redo` adds
//! the files that hold HEAD's lock cases.

use crate::config::{self, Config, CONFIG_FILE};
use crate::git::{git_in, Repo};
use crate::lock::Lock;
use crate::suite;
use serde_json::{json, Value};
use std::collections::BTreeSet;
use std::fs;

/// The base `red` narrows against when `--base` does not name one.
const DEFAULT_BASE: &str = "refs/remotes/origin/HEAD";

/// Why `red` ran every suite, in the order the first that applies is reported.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Fallback {
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

/// A changed path as git reports it: whether it was at the base, and its bytes.
pub type ChangedPath = (bool, Vec<u8>);

/// The ref `red` narrows against: `base`, or origin's HEAD when not given.
pub fn base_ref(base: Option<&str>) -> &str {
    base.unwrap_or(DEFAULT_BASE)
}

/// The base ref as messages name it (item 59).
pub fn shown_ref(base: Option<&str>) -> &str {
    base.unwrap_or("origin/HEAD")
}

/// The paths changed since the merge base of HEAD and the base ref, or why
/// they cannot be read; item 59 reads them even when the plan is not narrowed.
pub fn changed(repo: &Repo, base: Option<&str>) -> std::result::Result<Vec<ChangedPath>, Fallback> {
    let base = base_commit(repo, base_ref(base))?;
    changed_paths(repo, &base).ok_or(Fallback::GitFailed)
}

/// The plan for `red`: `--all`, or the changed test files among `changed`;
/// with `redo` (item 60, HEAD's lock), plus each suite's lock files. The
/// emptiness test comes after the union.
pub fn plan(
    repo: &Repo,
    config: &Config,
    changed: &std::result::Result<Vec<ChangedPath>, Fallback>,
    all: bool,
    redo: Option<&Lock>,
) -> Plan {
    if all {
        return Plan::All(Fallback::All);
    }
    let chosen = changed.as_ref().map_err(|why| *why).and_then(|changed| select(repo, config, changed));
    let (mut selected, mut files) = match chosen {
        Ok(chosen) => chosen,
        Err(why) => return Plan::All(why),
    };
    if let Some(lock) = redo {
        if let Err(why) = add_lock_files(repo, config, lock, &mut selected, &mut files) {
            return Plan::All(why);
        }
    }
    if files.is_empty() {
        return Plan::All(Fallback::NothingSelected);
    }
    Plan::Changed { selected, files: files.len() }
}

/// Item 60: adds to each suite's selection its lock files, the files (from
/// its root) that hold the lock's cases it owns (item 59's suite identity),
/// mapped by item 55's mapper over the lock's `files`, on the working tree.
/// A case of no suite, or of no single readable file, is `case without file`.
fn add_lock_files(
    repo: &Repo,
    config: &Config,
    lock: &Lock,
    selected: &mut [BTreeSet<String>],
    files: &mut BTreeSet<String>,
) -> std::result::Result<(), Fallback> {
    let suites = config.suites();
    let named: Vec<String> = suites.iter().map(|suite| suite.nome.clone()).filter(|n| !n.is_empty()).collect();
    let unnamed: Vec<usize> = (0..suites.len()).filter(|&i| suites[i].nome.is_empty()).collect();
    let mut cases: Vec<Vec<&str>> = vec![Vec::new(); suites.len()];
    for case in &lock.cases {
        let (i, id) = match config::owner(case, &named) {
            Some(name) => {
                let i = suites.iter().position(|suite| &suite.nome == name).expect("an owner is a suite's name");
                (i, &case[name.len() + 1..])
            }
            None => match unnamed[..] {
                [one] => (one, case.as_str()),
                _ => return Err(Fallback::CaseWithoutFile),
            },
        };
        cases[i].push(id);
    }
    let present = repo.files().map_err(|_| Fallback::GitFailed)?;
    let locked: Vec<String> = lock.files.keys().cloned().collect();
    for ((suite, cases), selected) in suites.iter().zip(&cases).zip(selected) {
        if cases.is_empty() {
            continue;
        }
        let prefix = suite.prefix();
        for rel in suite::holding(repo.root(), suite, &locked, &present, cases)? {
            let path = format!("{prefix}{rel}");
            // As item 55 checks a selected file: `lstat`, then opened for reading.
            let regular = fs::symlink_metadata(repo.path(&path)).is_ok_and(|m| m.is_file());
            if !regular || fs::File::open(repo.path(&path)).is_err() {
                return Err(Fallback::CaseWithoutFile);
            }
            selected.insert(rel);
            files.insert(path);
        }
    }
    Ok(())
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

/// The changed paths: at the base means the diff's entries that are not
/// added. None when git fails.
fn changed_paths(repo: &Repo, base: &str) -> Option<Vec<ChangedPath>> {
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

/// Each suite's selected files (from its root), and the distinct files by
/// repository path.
type Selection = (Vec<BTreeSet<String>>, BTreeSet<String>);

/// The selection among the changed paths, or the first reason to run every
/// suite instead; the emptiness test is the caller's.
fn select(repo: &Repo, config: &Config, changed: &[ChangedPath]) -> std::result::Result<Selection, Fallback> {
    let suites = config.suites();
    let mut selected = vec![BTreeSet::new(); suites.len()];
    let mut files = BTreeSet::new();
    let mut why: Option<Fallback> = None;
    let mut fall = |reason: Fallback| why = Some(why.map_or(reason, |first| first.min(reason)));
    for (at_base, path) in changed {
        let Ok(path) = String::from_utf8(path.clone()) else {
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
        if *at_base && !regular {
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
    match why {
        Some(why) => Err(why),
        None => Ok((selected, files)),
    }
}
