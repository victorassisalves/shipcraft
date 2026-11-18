//! Item 55: `red` runs the RED's changed test files. The base, the paths
//! changed since it, each suite's selected files, and why `red` runs every
//! suite instead when it cannot narrow safely. Item 60: `red --redo` adds
//! the files that hold HEAD's lock cases.

use crate::config::{self, Config, CONFIG_FILE, LEGACY_FILE};
use crate::git::{git_in, short, Repo};
use crate::lock::Lock;
use crate::refusal::short_list;
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
    /// Item 65: the selected files (repository paths) that hold no case in
    /// their suite's own report, when the narrowed run stood. Not logged.
    pub support: BTreeSet<String>,
    /// Item 129: the merge base's short id, which the `config changed` line names.
    merge_base: Option<String>,
}

impl Chosen {
    pub fn new(plan: &Plan, locked: usize, merge_base: Option<&str>) -> Chosen {
        let (selected, fallback) = match plan {
            Plan::All(why) => (0, Some(*why)),
            Plan::Changed { files, .. } => (*files, None),
        };
        let merge_base = merge_base.map(|id| short(id).to_string());
        Chosen { selected, locked, fallback, support: BTreeSet::new(), merge_base }
    }

    /// The line `red` prints before its usual lines.
    pub fn notice(&self) -> String {
        match (self.fallback, &self.merge_base) {
            // Item 129: the line names the file and the merge base it differs from.
            (Some(Fallback::ConfigChanged), Some(id)) => format!(
                "shipcraft: red ran every suite: config changed ({CONFIG_FILE} differs from the merge base {id})"
            ),
            (Some(why), _) => format!("shipcraft: red ran every suite: {}", why.text()),
            (None, _) => format!("shipcraft: red ran the changed test files: {} of {}", self.selected, self.locked),
        }
    }

    /// Item 65: the line right after the notice when the narrowed run stood
    /// and a selected file holds no case.
    pub fn support_notice(&self) -> Option<String> {
        if self.fallback.is_some() || self.support.is_empty() {
            return None;
        }
        let paths: Vec<&String> = self.support.iter().collect();
        Some(format!(
            "shipcraft: red did not run the tests that may use the changed support file(s): {}; CI runs them",
            short_list(&paths)
        ))
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

/// The commit `red` compares with (item 66): `--base`, or the first of the
/// candidates that resolves to a commit, and how messages name it.
#[derive(Clone, Debug)]
pub struct Compared {
    pub commit: String,
    pub shown: String,
    /// The base came from a candidate after `origin/HEAD` (item 66, point 4).
    missing_origin_head: bool,
}

impl Compared {
    /// Item 66: the line right before the selection line, when the base came
    /// from a candidate after `origin/HEAD`.
    pub fn notice(&self) -> Option<String> {
        self.missing_origin_head
            .then(|| format!("shipcraft: red compared with {} (origin/HEAD is missing)", self.shown))
    }
}

/// The base or why there is none: the commit and the fallback merge-base
/// failures give still name it (item 66, points 2 and 4).
pub type Base = std::result::Result<Compared, Fallback>;

/// Item 66: the candidates without `--base`, in order, with their short
/// names; `HEAD` is the last.
const CANDIDATES: [(&str, &str); 5] = [
    (DEFAULT_BASE, "origin/HEAD"),
    ("refs/remotes/origin/main", "origin/main"),
    ("refs/remotes/origin/master", "origin/master"),
    ("refs/heads/main", "main"),
    ("refs/heads/master", "master"),
];

/// The base `red` compares with. With `--base`, that ref as item 55 reads it.
/// Without, item 66: `HEAD` first (unborn is `no base`), then the first
/// candidate that resolves to a commit, each resolved once.
pub fn base(repo: &Repo, base: Option<&str>) -> Base {
    if let Some(rev) = base {
        let commit = repo.resolve(rev).map_err(|_| Fallback::GitFailed)?.ok_or(Fallback::NoBase)?;
        return Ok(Compared { commit, shown: rev.to_string(), missing_origin_head: false });
    }
    let head = commit_of(repo, "HEAD")?.ok_or(Fallback::NoBase)?;
    for (i, (rev, shown)) in CANDIDATES.iter().enumerate() {
        if let Some(commit) = commit_of(repo, rev)? {
            return Ok(Compared { commit, shown: shown.to_string(), missing_origin_head: i > 0 });
        }
    }
    // The last candidate is `HEAD`, already resolved above.
    Ok(Compared { commit: head, shown: "HEAD".to_string(), missing_origin_head: true })
}

/// `git rev-parse --verify -q <rev>^{commit}`: exit 1 is None; any other exit,
/// a signal, a failure to start git, or output that is not one commit id is
/// `git failed`.
fn commit_of(repo: &Repo, rev: &str) -> std::result::Result<Option<String>, Fallback> {
    let spec = format!("{rev}^{{commit}}");
    let out = git_in(repo.root(), &["rev-parse", "--verify", "-q", &spec]).map_err(|_| Fallback::GitFailed)?;
    match out.status.code() {
        Some(0) => {
            let text = String::from_utf8(out.stdout).map_err(|_| Fallback::GitFailed)?;
            let id = text.strip_suffix('\n').unwrap_or(&text);
            let hex = id.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b));
            if hex && matches!(id.len(), 40 | 64) {
                Ok(Some(id.to_string()))
            } else {
                Err(Fallback::GitFailed)
            }
        }
        Some(1) => Ok(None),
        _ => Err(Fallback::GitFailed),
    }
}

/// The paths changed since the merge base of HEAD and the base, and that
/// merge base (item 81 reads its tree).
pub struct Changed {
    pub merge_base: String,
    pub paths: Vec<ChangedPath>,
}

/// The changed paths, or why they cannot be read; item 59 reads them even
/// when the plan is not narrowed.
pub fn changed(repo: &Repo, base: &Base) -> std::result::Result<Changed, Fallback> {
    let compared = base.as_ref().map_err(|why| *why)?;
    let merge_base = merge_base(repo, &compared.commit)?;
    let paths = changed_paths(repo, &merge_base).ok_or(Fallback::GitFailed)?;
    Ok(Changed { merge_base, paths })
}

/// Item 81: which of `paths` (repository paths, deduplicated by the caller)
/// are in `merge_base`'s tree, byte for byte, read in one
/// `git ls-tree -r -z --name-only <merge base> -- <paths>`; or, when the read
/// fails, git's first stderr line, the exit status or the signal.
pub fn in_base_tree(repo: &Repo, merge_base: &str, paths: &[&str]) -> std::result::Result<BTreeSet<String>, String> {
    use std::os::unix::process::ExitStatusExt;
    let out = std::process::Command::new("git")
        .current_dir(repo.root())
        .env("GIT_LITERAL_PATHSPECS", "1")
        .args(["ls-tree", "-r", "-z", "--name-only", merge_base, "--"])
        .args(paths)
        .output()
        .map_err(|e| format!("run git: {e}"))?;
    if !out.status.success() {
        let stderr = String::from_utf8_lossy(&out.stderr);
        if let Some(line) = stderr.lines().map(str::trim_end).find(|line| !line.is_empty()) {
            return Err(line.to_string());
        }
        return Err(match (out.status.code(), out.status.signal()) {
            (Some(code), _) => format!("exited with {code}"),
            (None, Some(signal)) => format!("killed by signal {signal}"),
            _ => "ended without an exit code".to_string(),
        });
    }
    let entries: BTreeSet<&[u8]> = out.stdout.split(|b| *b == 0).filter(|entry| !entry.is_empty()).collect();
    Ok(paths.iter().filter(|path| entries.contains(path.as_bytes())).map(|path| path.to_string()).collect())
}

/// The plan for `red`: `--all`, or the changed test files among `changed`;
/// with `redo` (item 60, HEAD's lock), plus each suite's lock files. The
/// emptiness test comes after the union.
pub fn plan(
    repo: &Repo,
    config: &Config,
    changed: &std::result::Result<Changed, Fallback>,
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

/// The one merge base of HEAD and the base commit; zero or several is
/// `no merge base`, and no other candidate is tried (item 66).
fn merge_base(repo: &Repo, base: &str) -> std::result::Result<String, Fallback> {
    if repo.head().map_err(|_| Fallback::GitFailed)?.is_none() {
        return Err(Fallback::NoMergeBase);
    }
    let out = git_in(repo.root(), &["merge-base", "--all", "HEAD", base]).map_err(|_| Fallback::GitFailed)?;
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
fn select(repo: &Repo, config: &Config, changed: &Changed) -> std::result::Result<Selection, Fallback> {
    let suites = config.suites();
    let mut selected = vec![BTreeSet::new(); suites.len()];
    let mut files = BTreeSet::new();
    let mut why: Option<Fallback> = None;
    let mut fall = |reason: Fallback| why = Some(why.map_or(reason, |first| first.min(reason)));
    for (at_base, path) in &changed.paths {
        let Ok(path) = String::from_utf8(path.clone()) else {
            fall(Fallback::UnreadablePath);
            continue;
        };
        if path == CONFIG_FILE {
            if *at_base || legacy_at_base(repo, &changed.merge_base) {
                fall(Fallback::ConfigChanged);
            }
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

/// Item 129: an added `.shipcraft.toml` installs Shipcraft unless the merge
/// base holds the legacy `.sc2.toml`; a failed read counts as holding it.
fn legacy_at_base(repo: &Repo, merge_base: &str) -> bool {
    in_base_tree(repo, merge_base, &[LEGACY_FILE]).map_or(true, |held| !held.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::git::TempDir;
    use std::process::Command;

    fn git(root: &std::path::Path, args: &[&str]) -> String {
        let out = Command::new("git")
            .current_dir(root)
            .args(["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"])
            .args(args)
            .output()
            .unwrap();
        assert!(out.status.success(), "git {args:?}: {}", String::from_utf8_lossy(&out.stderr));
        String::from_utf8(out.stdout).unwrap().trim_end().to_string()
    }

    /// A repository whose one commit holds `files`; its id.
    fn repo_with(dir: &TempDir, files: &[&str]) -> (Repo, String) {
        let root = dir.path();
        git(root, &["init", "-q"]);
        for file in files {
            fs::write(root.join(file), "x\n").unwrap();
        }
        git(root, &["add", "-A"]);
        git(root, &["commit", "-q", "--allow-empty", "-m", "base"]);
        (Repo::at_root(root), git(root, &["rev-parse", "HEAD"]))
    }

    fn config() -> Config {
        Config::parse("[[suite]]\ncommand = \"true\"\nglobs = [\"tests/*.t\"]\n").unwrap()
    }

    fn added_config(merge_base: &str) -> Changed {
        Changed {
            merge_base: merge_base.to_string(),
            paths: vec![(false, CONFIG_FILE.as_bytes().to_vec()), (false, b"tests/new.t".to_vec())],
        }
    }

    #[test]
    fn an_added_config_narrows_unless_the_merge_base_holds_the_legacy_file() {
        let dir = TempDir::new("shipcraft-narrow").unwrap();
        let (repo, base) = repo_with(&dir, &["a.t"]);
        fs::create_dir_all(dir.path().join("tests")).unwrap();
        fs::write(dir.path().join("tests/new.t"), "x\n").unwrap();
        let (_, files) = select(&repo, &config(), &added_config(&base)).expect("an install narrows");
        assert_eq!(files.into_iter().collect::<Vec<_>>(), ["tests/new.t"], "the config is never selected");

        // At the merge base (modified), it is `config changed` with no read.
        let modified = Changed { merge_base: "not-a-commit".to_string(), paths: vec![(true, CONFIG_FILE.into())] };
        assert_eq!(select(&repo, &config(), &modified).err(), Some(Fallback::ConfigChanged));
        // A failed read of the legacy file keeps the full run.
        assert_eq!(select(&repo, &config(), &added_config("not-a-commit")).err(), Some(Fallback::ConfigChanged));

        let legacy = TempDir::new("shipcraft-narrow").unwrap();
        let (repo, base) = repo_with(&legacy, &[LEGACY_FILE]);
        fs::create_dir_all(legacy.path().join("tests")).unwrap();
        fs::write(legacy.path().join("tests/new.t"), "x\n").unwrap();
        assert_eq!(select(&repo, &config(), &added_config(&base)).err(), Some(Fallback::ConfigChanged));
    }

    #[test]
    fn the_config_changed_line_names_the_file_and_the_merge_base() {
        let id = "0123456789abcdef0123456789abcdef01234567";
        let chosen = Chosen::new(&Plan::All(Fallback::ConfigChanged), 4, Some(id));
        assert_eq!(
            chosen.notice(),
            "shipcraft: red ran every suite: config changed (.shipcraft.toml differs from the merge base 0123456)"
        );
        let mut row = json!({});
        chosen.record(&mut row);
        assert_eq!(row["fallback"], "config changed");
        let other = Chosen::new(&Plan::All(Fallback::NothingSelected), 4, Some(id));
        assert_eq!(other.notice(), "shipcraft: red ran every suite: nothing selected");
        let narrowed = Chosen::new(&Plan::Changed { selected: Vec::new(), files: 1 }, 4, Some(id));
        assert_eq!(narrowed.notice(), "shipcraft: red ran the changed test files: 1 of 4");
    }
}
