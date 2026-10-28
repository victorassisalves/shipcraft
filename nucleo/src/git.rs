//! The git calls shipcraft needs, and the three places it reads files from.
//!
//! A file that is not there is `None`; any other git or I/O error is a
//! failure, never taken for a missing file.

use crate::refusal::{failed, refuse, Result};
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

/// Where a file is read from: the working tree, the index (what the next
/// commit carries), or a commit.
pub enum Snapshot {
    Tree,
    Index,
    Commit(String),
}

impl Snapshot {
    /// For messages: "in the tree", "in the index", "in commit 1a2b3c4".
    pub fn describe(&self) -> String {
        match self {
            Snapshot::Tree => "in the tree".to_string(),
            Snapshot::Index => "in the index".to_string(),
            Snapshot::Commit(rev) => format!("in commit {}", short(rev)),
        }
    }
}

pub fn short(rev: &str) -> &str {
    &rev[..rev.len().min(7)]
}

pub struct Repo {
    root: PathBuf,
}

impl Repo {
    /// The repository that holds the current directory.
    pub fn open() -> Result<Repo> {
        let cwd = std::env::current_dir().map_err(|e| failed(format!("current directory: {e}")))?;
        let out = git_in(&cwd, &["rev-parse", "--show-toplevel"])?;
        if !out.status.success() {
            return refuse(
                "no-git",
                "this directory is not in a git repository",
                "shipcraft stores the RED contract in git so CI checks the same thing as the local machine",
                "run `git init` (or enter the repository) and try again",
            );
        }
        Ok(Repo { root: PathBuf::from(text(&out.stdout).trim()) })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn path(&self, relative: &str) -> PathBuf {
        self.root.join(relative)
    }

    /// Runs git in the repository root; a non-zero exit is a failure.
    pub fn run(&self, args: &[&str]) -> Result<Vec<u8>> {
        let out = git_in(&self.root, args)?;
        if !out.status.success() {
            return Err(failed(format!("`git {}` failed: {}", args.join(" "), text(&out.stderr).trim())));
        }
        Ok(out.stdout)
    }

    /// `git rev-parse -q --verify`: None when the revision does not exist.
    fn verify(&self, spec: &str) -> Result<Option<String>> {
        let out = git_in(&self.root, &["rev-parse", "-q", "--verify", spec])?;
        match out.status.code() {
            Some(0) => Ok(Some(text(&out.stdout).trim().to_string())),
            Some(1) => Ok(None),
            _ => Err(failed(format!("`git rev-parse {spec}` failed: {}", text(&out.stderr).trim()))),
        }
    }

    /// None on a branch with no commits yet.
    pub fn head(&self) -> Result<Option<String>> {
        self.verify("HEAD")
    }

    /// The full hash of a commit, or None if `rev` names no commit.
    pub fn resolve(&self, rev: &str) -> Result<Option<String>> {
        self.verify(&format!("{rev}^{{commit}}"))
    }

    /// The commits in `base..HEAD`, oldest first.
    pub fn commits_since(&self, base: &str) -> Result<Vec<String>> {
        let range = format!("{base}..HEAD");
        let out = self.run(&["rev-list", "--reverse", "--topo-order", &range])?;
        Ok(text(&out).lines().map(str::to_string).collect())
    }

    pub fn parents(&self, commit: &str) -> Result<Vec<String>> {
        let out = self.run(&["rev-list", "--parents", "-n", "1", commit])?;
        Ok(text(&out).split_whitespace().skip(1).map(str::to_string).collect())
    }

    /// A file's content in a snapshot, or None if it is not there.
    pub fn read(&self, snapshot: &Snapshot, path: &str) -> Result<Option<Vec<u8>>> {
        let object = match snapshot {
            Snapshot::Tree => {
                return match fs::read(self.path(path)) {
                    Ok(bytes) => Ok(Some(bytes)),
                    Err(e) if e.kind() == ErrorKind::NotFound => Ok(None),
                    Err(e) => Err(failed(format!("read {path}: {e}"))),
                };
            }
            Snapshot::Index if self.run(&["ls-files", "-z", "--", path])?.is_empty() => return Ok(None),
            Snapshot::Commit(rev) if self.run(&["ls-tree", "-z", rev, "--", path])?.is_empty() => return Ok(None),
            Snapshot::Index => format!(":{path}"),
            Snapshot::Commit(rev) => format!("{rev}:{path}"),
        };
        self.run(&["cat-file", "blob", &object]).map(Some)
    }

    /// The files directly under `dir` in a snapshot, as paths from the root.
    pub fn list(&self, snapshot: &Snapshot, dir: &str) -> Result<Vec<String>> {
        let mut paths = match snapshot {
            Snapshot::Tree => self.list_tree_dir(dir)?,
            Snapshot::Index => split_nul(&self.run(&["ls-files", "-z", "--", dir])?),
            Snapshot::Commit(rev) => split_nul(&self.run(&["ls-tree", "-r", "-z", "--name-only", rev, "--", dir])?),
        };
        paths.sort();
        Ok(paths)
    }

    fn list_tree_dir(&self, dir: &str) -> Result<Vec<String>> {
        let listing_failed = |e: std::io::Error| failed(format!("list {dir}: {e}"));
        let entries = match fs::read_dir(self.path(dir)) {
            Ok(entries) => entries,
            Err(e) if e.kind() == ErrorKind::NotFound => return Ok(Vec::new()),
            Err(e) => return Err(listing_failed(e)),
        };
        let mut paths = Vec::new();
        for entry in entries {
            let entry = entry.map_err(listing_failed)?;
            if entry.file_type().map_err(listing_failed)?.is_file() {
                paths.push(format!("{dir}/{}", entry.file_name().to_string_lossy()));
            }
        }
        Ok(paths)
    }

    /// Every file of the project that git does not ignore, tracked or not.
    pub fn files(&self) -> Result<Vec<String>> {
        let mut paths = split_nul(&self.run(&["ls-files", "-z", "--cached", "--others", "--exclude-standard"])?);
        paths.sort();
        paths.dedup();
        Ok(paths)
    }

    /// The files git tracks (in the index).
    pub fn tracked(&self) -> Result<Vec<String>> {
        Ok(split_nul(&self.run(&["ls-files", "-z", "--cached"])?))
    }

    /// The files whose working-tree content is not what the index holds:
    /// unstaged edits and deletions, and untracked files git does not ignore.
    pub fn unstaged(&self) -> Result<Vec<String>> {
        let mut paths = split_nul(&self.run(&["diff", "--name-only", "-z"])?);
        paths.extend(split_nul(&self.run(&["ls-files", "-z", "--others", "--exclude-standard"])?));
        paths.sort();
        Ok(paths)
    }

    /// Item 57: whether `GIT_INDEX_FILE` names an index other than the
    /// repository's own (`git commit --only`, `git commit <paths>`).
    pub fn other_index(&self) -> Result<bool> {
        let Some(named) = std::env::var_os("GIT_INDEX_FILE") else { return Ok(false) };
        let own = self.root.join(self.text(&["rev-parse", "--git-dir"])?).join("index");
        let real = |path: PathBuf| path.canonicalize().unwrap_or(path);
        Ok(real(self.root.join(named)) != real(own))
    }

    pub fn add(&self, path: &str) -> Result<()> {
        self.run(&["add", "--", path]).map(drop)
    }

    /// `git <args>` as trimmed text; a non-zero exit is a failure.
    pub fn text(&self, args: &[&str]) -> Result<String> {
        Ok(text(&self.run(args)?).trim().to_string())
    }

    /// `git <args>` as trimmed text, or None when git exits non-zero.
    pub fn try_text(&self, args: &[&str]) -> Option<String> {
        let out = git_in(&self.root, args).ok()?;
        out.status.success().then(|| text(&out.stdout).trim().to_string())
    }

    /// The current branch, or "" on a detached HEAD.
    pub fn branch(&self) -> String {
        self.try_text(&["symbolic-ref", "-q", "--short", "HEAD"]).unwrap_or_default()
    }

    /// The branch origin's HEAD points at (`main` when origin does not say).
    pub fn default_branch(&self) -> String {
        self.try_text(&["symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD"])
            .and_then(|r| r.strip_prefix("origin/").map(str::to_string))
            .unwrap_or_else(|| "main".to_string())
    }

    /// `.git/shipcraft/`, in the main repository even from a worktree.
    pub fn shipcraft_dir(&self) -> Result<PathBuf> {
        Ok(self.root.join(self.text(&["rev-parse", "--git-common-dir"])?).join("shipcraft"))
    }

    /// The project name: the root directory's name.
    pub fn name(&self) -> String {
        self.root.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
    }

    /// Anything tracked, staged or untracked (not ignored) that differs from HEAD.
    pub fn dirty(&self) -> Result<bool> {
        Ok(!self.run(&["status", "--porcelain", "-z"])?.is_empty())
    }

    /// A git checkout of a snapshot in a temporary directory (items 6.2 and
    /// 14): a worktree detached at HEAD (or at the commit) whose index and
    /// files are the snapshot's, so `HEAD`, the history and `git ls-files`
    /// work in it as in a clean clone (before the first commit, a new
    /// repository with the index as its content); plus the files git ignores
    /// in the working tree (dependencies, `.env`, generated files), linked in
    /// place unless the judged content has that path. Untracked files that git
    /// does not ignore stay out.
    pub fn export(&self, snapshot: &Snapshot) -> Result<Checkout> {
        let (at, tree) = match snapshot {
            Snapshot::Index => (self.head()?, self.text(&["write-tree"])?),
            Snapshot::Commit(rev) => (Some(rev.clone()), rev.clone()),
            Snapshot::Tree => return Err(failed("the tree needs no copy")),
        };
        let copy = Checkout { dir: TempDir::new("shipcraft-arvore")?, root: self.root.clone(), worktree: at.is_some() };
        let dir = copy.path().to_string_lossy().into_owned();
        match &at {
            // --no-checkout: no post-checkout hook; the files come from read-tree.
            Some(at) => {
                outside_index(&self.root, &["worktree", "add", "-q", "--detach", "--no-checkout", &dir, at])?;
            }
            // No commit yet (the first RED): a new repository that borrows
            // this one's objects, with the index as its index and files.
            None => {
                outside_index(copy.path(), &["init", "-q", "--template="])?;
                let objects = self.root.join(self.text(&["rev-parse", "--git-path", "objects"])?);
                fs::write(copy.path().join(".git/objects/info/alternates"), format!("{}\n", objects.display()))
                    .map_err(|e| failed(format!("link objects into the copy: {e}")))?;
            }
        }
        outside_index(copy.path(), &["read-tree", "-u", "--reset", &tree])?;
        let ignored = self.run(&["ls-files", "-z", "--others", "--ignored", "--exclude-standard", "--directory"])?;
        for entry in split_nul(&ignored) {
            let entry = entry.trim_end_matches('/');
            if entry.rsplit('/').next() == Some("__pycache__") {
                continue; // a bytecode cache, not a dependency
            }
            let link = copy.path().join(entry);
            if link.symlink_metadata().is_ok() {
                continue; // tracked in the judged content, which wins
            }
            if let Some(parent) = link.parent() {
                let _ = fs::create_dir_all(parent);
            }
            std::os::unix::fs::symlink(self.path(entry), &link)
                .map_err(|e| failed(format!("link {entry} into the copy: {e}")))?;
        }
        Ok(copy)
    }

    /// Where git looks for a hook (honours core.hooksPath and worktrees).
    pub fn hook_path(&self, name: &str) -> Result<PathBuf> {
        let out = self.run(&["rev-parse", "--git-path", &format!("hooks/{name}")])?;
        Ok(self.root.join(text(&out).trim()))
    }
}

/// A directory under the temporary directory, removed when dropped.
pub struct TempDir(PathBuf);

impl TempDir {
    pub fn new(prefix: &str) -> Result<TempDir> {
        let nanos =
            std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
        let path = std::env::temp_dir().join(format!("{prefix}-{}-{nanos}", std::process::id()));
        fs::create_dir_all(&path).map_err(|e| failed(format!("create {}: {e}", path.display())))?;
        Ok(TempDir(path.canonicalize().unwrap_or(path)))
    }

    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// The variables a git hook passes on that point at the hook's repository
/// (`GIT_INDEX_FILE` is `.git/index`, relative): a process working in a
/// checkout copy must find the copy's own repository instead.
pub const HOOK_GIT_ENV: [&str; 3] = ["GIT_INDEX_FILE", "GIT_DIR", "GIT_WORK_TREE"];

/// Runs git in `dir` without the hook's variables: the worktree of a checkout
/// copy must never touch the index of the commit being made.
fn outside_index(dir: &Path, args: &[&str]) -> Result<()> {
    let mut cmd = Command::new("git");
    cmd.arg("-C").arg(dir).args(args);
    for var in HOOK_GIT_ENV {
        cmd.env_remove(var);
    }
    let out = cmd.output().map_err(|e| failed(format!("run git: {e}")))?;
    if !out.status.success() {
        return Err(failed(format!("`git {}` failed: {}", args.join(" "), text(&out.stderr).trim())));
    }
    Ok(())
}

/// A checkout copy (`Repo::export`), removed with its worktree when dropped.
pub struct Checkout {
    dir: TempDir,
    root: PathBuf,
    worktree: bool,
}

impl Checkout {
    pub fn path(&self) -> &Path {
        self.dir.path()
    }
}

impl Drop for Checkout {
    fn drop(&mut self) {
        if self.worktree {
            let dir = self.path().to_string_lossy().into_owned();
            let _ = outside_index(&self.root, &["worktree", "remove", "--force", &dir]);
            let _ = outside_index(&self.root, &["worktree", "prune"]);
        }
    }
}

/// Runs git in `dir`, with paths taken literally (no pathspec magic).
pub fn git_in(dir: &Path, args: &[&str]) -> Result<Output> {
    Command::new("git")
        .arg("-C")
        .arg(dir)
        .arg("--literal-pathspecs")
        .args(args)
        .output()
        .map_err(|e| failed(format!("run git: {e}")))
}

pub fn text(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

fn split_nul(bytes: &[u8]) -> Vec<String> {
    bytes.split(|b| *b == 0).filter(|s| !s.is_empty()).map(text).collect()
}
