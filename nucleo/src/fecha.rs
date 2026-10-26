//! `shipcraft close`, called by the post-commit hook (item 17, point 2): closes, in
//! a commit of its own, the locks the `commit-msg` judgment marked, when the
//! commit just made is the one it judged. It always exits 0 (the user's commit
//! already exists). Item 38: it writes a `close` row per lock once the commit
//! that closes it exists, or an `error` row when it could not close.

use crate::git::{short, Repo, Snapshot, TempDir};
use crate::lock::Lock;
use crate::marca::{self, Marca};
use crate::medicao;
use serde_json::json;
use std::fs;
use std::path::Path;
use std::process::Command;
use std::time::Instant;

const AGAIN: &str = "the lock stays open, and the next green commit closes it";
/// The operations `git status` reports as in progress, by their git path.
const IN_PROGRESS: [(&str, &str); 5] = [
    ("MERGE_HEAD", "merge"),
    ("CHERRY_PICK_HEAD", "cherry-pick"),
    ("REVERT_HEAD", "revert"),
    ("rebase-merge", "rebase"),
    ("rebase-apply", "rebase"),
];

pub fn run() {
    let started = Instant::now();
    let Ok(repo) = Repo::open() else { return };
    let Some(marca) = marca::read(&repo) else { return };
    if let Some(op) = in_progress(&repo) {
        discard(&repo);
        return println!("shipcraft: a {op} is in progress; {AGAIN}.");
    }
    let Some(head) = repo.head().ok().flatten().filter(|head| judged(&repo, &marca, head)) else {
        discard(&repo);
        return println!("shipcraft: this is not the commit that commit-msg judged; {AGAIN}.");
    };
    let closed = match closing_commit(&repo, &marca, &head) {
        Ok(closed) => closed,
        Err(e) => {
            record(&repo, &marca, started, "error", "");
            return println!(
                "shipcraft: the lock did not close ({}); nothing changed: run `shipcraft close` manually.",
                one_line(&e)
            )
        }
    };
    record(&repo, &marca, started, "passed", &closed.commit);
    after_ref(&repo, &marca, &closed);
}

/// Item 38: one `close` row per lock of the mark.
fn record(repo: &Repo, marca: &Marca, started: Instant, result: &str, commit: &str) {
    for path in &marca.travas {
        medicao::record(
            repo,
            json!({"layer": "close", "secs": medicao::seconds(started), "result": result,
                   "code": if result == "passed" { "" } else { "error" }, "branch": repo.branch(),
                   "commit": commit, "lock": medicao::lock_id(path)}),
        );
    }
}

fn in_progress(repo: &Repo) -> Option<&'static str> {
    IN_PROGRESS.iter().find(|(file, _)| git_path(repo, file).is_some_and(|p| p.exists())).map(|(_, op)| *op)
}

fn git_path(repo: &Repo, name: &str) -> Option<std::path::PathBuf> {
    repo.try_text(&["rev-parse", "--git-path", name]).map(|p| repo.path(&p))
}

/// HEAD's tree is the judged tree, and the HEAD before the commit is the
/// HEAD seen at the judgment.
fn judged(repo: &Repo, marca: &Marca, head: &str) -> bool {
    let tree = repo.try_text(&["rev-parse", "HEAD^{tree}"]);
    tree.as_deref() == Some(&marca.arvore) && head_before(repo, head).as_deref() == Some(&marca.head)
}

/// `HEAD@{1}`, from HEAD's own reflog (git would fall back to the branch's):
/// the old value of the last entry, if it moved HEAD to `head`. No reflog
/// counts as another HEAD (rule 17).
fn head_before(repo: &Repo, head: &str) -> Option<String> {
    let log = fs::read_to_string(git_path(repo, "logs/HEAD")?).ok()?;
    let mut fields = log.lines().last()?.split(' ');
    let (old, new) = (fields.next()?, fields.next()?);
    (new == head).then(|| old.to_string())
}

fn discard(repo: &Repo) {
    let _ = marca::remove(repo);
}

/// The commit that carries the closed locks on top of HEAD, and each lock:
/// its path, its bytes in HEAD, its closed blob and bytes.
struct Closed {
    commit: String,
    locks: Vec<(String, Vec<u8>, String, String)>,
}

/// Plumbing on a temporary index: HEAD's tree with only each lock's blob
/// swapped for `closed`, `commit-tree`, then `update-ref HEAD <new> <old>`.
/// Nothing changes on failure; no hook runs.
fn closing_commit(repo: &Repo, marca: &Marca, head: &str) -> Result<Closed, String> {
    let lock_file = git_path(repo, "index").map(|p| std::path::PathBuf::from(format!("{}.lock", p.display())));
    if lock_file.is_none_or(|p| p.exists()) {
        return Err("the index is locked: index.lock exists".into());
    }
    let temp = TempDir::new("shipcraft-fecha").map_err(|_| "could not create the temporary index".to_string())?;
    let index = temp.path().join("index").to_string_lossy().into_owned();
    let on_temp = [("GIT_INDEX_FILE", index.as_str())];
    git(repo, &on_temp, &["read-tree", head])?;
    let mut locks = Vec::new();
    for path in &marca.travas {
        let bytes = repo.read(&Snapshot::Commit(head.into()), path).ok().flatten();
        let lock = bytes.as_deref().and_then(Lock::parse).filter(Lock::is_open);
        let lock = lock.ok_or_else(|| format!("lock {path} is not open at HEAD"))?;
        let file = temp.path().join("trava");
        let json = lock.closed().to_json();
        fs::write(&file, &json).map_err(|e| format!("write the closed lock: {e}"))?;
        let blob = git(repo, &[], &["hash-object", "-w", "--no-filters", &file.to_string_lossy()])?;
        git(repo, &on_temp, &["update-index", "--add", "--cacheinfo", &format!("100644,{blob},{path}")])?;
        locks.push((path.clone(), bytes.unwrap_or_default(), blob, json));
    }
    let tree = git(repo, &on_temp, &["write-tree"])?;
    let names: Vec<&str> =
        marca.travas.iter().map(|p| Path::new(p).file_stem().and_then(|s| s.to_str()).unwrap_or(p)).collect();
    let message = format!("shipcraft: close lock {}", names.join(", "));
    // `commit-tree` alone ignores commit.gpgsign; the effective config says whether to sign.
    let sign = git(repo, &[], &["config", "--type=bool", "commit.gpgsign"]).is_ok_and(|v| v == "true");
    let mut args = vec!["commit-tree", &tree, "-p", head, "-m", &message];
    args.extend(sign.then_some("-S"));
    let commit = git(repo, &[], &args)?;
    git(repo, &[], &["update-ref", "-m", &format!("commit: {message}"), "HEAD", &commit, head])?;
    Ok(Closed { commit, locks })
}

/// After the ref: the index swaps only each lock's entry; the tree file is
/// rewritten only when it still has the bytes HEAD had; then the mark goes.
fn after_ref(repo: &Repo, marca: &Marca, closed: &Closed) {
    let commit = short(&closed.commit);
    let paths = marca.travas.join(" ");
    for (path, _, blob, _) in &closed.locks {
        if git(repo, &[], &["update-index", "--cacheinfo", &format!("100644,{blob},{path}")]).is_err() {
            println!(
                "shipcraft: the lock closed in commit {commit}, but the index did not change; run `git reset -q -- {paths}`."
            );
            break;
        }
    }
    let mut kept = Vec::new();
    for (path, before, _, json) in &closed.locks {
        let file = repo.path(path);
        if fs::read(&file).ok().as_ref() != Some(before) {
            kept.push(path.as_str());
        } else if fs::write(&file, json).is_err() {
            println!("shipcraft: the lock closed in commit {commit}, but {path} did not change in the tree; run `git checkout HEAD -- {path}`.");
        }
    }
    discard(repo);
    match kept.is_empty() {
        true => println!("shipcraft: lock {paths} closed in commit {commit}."),
        false => println!(
            "shipcraft: lock {paths} closed in commit {commit}; {} was edited in the tree and left as is.",
            kept.join(", ")
        ),
    }
}

/// `git <args>` in the repository root, with `args[0]` as git's first
/// argument and hooks off; the trimmed output, or the error on one line.
fn git(repo: &Repo, env: &[(&str, &str)], args: &[&str]) -> Result<String, String> {
    let mut cmd = Command::new("git");
    cmd.current_dir(repo.root()).args(args).envs(env.iter().copied());
    hooks_off(&mut cmd);
    let out = cmd.output().map_err(|e| format!("run git: {e}"))?;
    match out.status.success() {
        true => Ok(String::from_utf8_lossy(&out.stdout).trim().to_string()),
        false => Err(format!("git {}: {}", args[0], one_line(&String::from_utf8_lossy(&out.stderr)))),
    }
}

/// `core.hooksPath=/dev/null` as one more `GIT_CONFIG_*` entry, after the
/// ones inherited from the environment, which keep applying (signing,
/// identity). An unreadable count is left as is: git refuses it, before the ref.
fn hooks_off(cmd: &mut Command) {
    let count = std::env::var("GIT_CONFIG_COUNT").map_or(Some(0), |n| n.parse::<usize>().ok());
    if let Some(n) = count {
        cmd.env("GIT_CONFIG_COUNT", (n + 1).to_string());
        cmd.env(format!("GIT_CONFIG_KEY_{n}"), "core.hooksPath");
        cmd.env(format!("GIT_CONFIG_VALUE_{n}"), "/dev/null");
    }
}

fn one_line(text: &str) -> String {
    text.split('\n').map(str::trim).filter(|l| !l.is_empty()).collect::<Vec<_>>().join("; ")
}
