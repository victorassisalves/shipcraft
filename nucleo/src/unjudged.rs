//! Item 141: commits the hook did not judge. Git makes some commits without
//! running `commit-msg` (`revert`, `cherry-pick`, rebase picks, `am`), so
//! nothing judged them locally. A commit is *judged* when the run log has a
//! passed `hook` row for its tree and first parent (or a `close` row for it);
//! `close` checks HEAD when it is not, and `status` and `pr` name such commits.

use crate::config::CONFIG_FILE;
use crate::git::{short, Repo, Snapshot, TempDir};
use crate::lock::{lock_files, Lock};
use crate::medicao;
use crate::refusal::Stop;
use std::collections::{BTreeSet, HashMap};
use std::fs;
use std::process::Command;

/// What the run log says: the passed hook rows (tree, commit), the commits
/// of the `close` rows, and the cutoff (the first row that carries `tree`).
struct Log {
    hooks: Vec<(String, String)>,
    closes: Vec<String>,
    cutoff: Option<u64>,
}

fn read_log(rows: Vec<serde_json::Value>) -> Log {
    let mut log = Log { hooks: Vec::new(), closes: Vec::new(), cutoff: None };
    for row in rows {
        let (Some(layer), Some(result), Some(commit)) =
            (row["layer"].as_str(), row["result"].as_str(), row["commit"].as_str())
        else {
            continue;
        };
        let tree = row["tree"].as_str();
        if let (Some(_), Some(at)) = (tree, row["at"].as_u64()) {
            log.cutoff = Some(log.cutoff.map_or(at, |c| c.min(at)));
        }
        match (layer, tree) {
            // A `refused` or `error` row never makes a commit judged.
            _ if result != "passed" => {}
            ("hook", Some(tree)) => log.hooks.push((tree.into(), commit.into())),
            ("close", _) => log.closes.push(commit.into()),
            _ => {}
        }
    }
    log
}

/// A commit's tree, committer time and parents, as git gives them.
struct Info {
    tree: String,
    time: u64,
    parents: Vec<String>,
}

struct Reader<'a> {
    repo: &'a Repo,
    log: Log,
    shallow: Vec<String>,
    /// First parents of the commits hook rows name ("" for a root commit).
    firsts: HashMap<String, Option<String>>,
}

impl<'a> Reader<'a> {
    fn new(repo: &'a Repo) -> Reader<'a> {
        let shallow = repo
            .try_text(&["rev-parse", "--git-path", "shallow"])
            .and_then(|p| fs::read_to_string(repo.path(&p)).ok())
            .unwrap_or_default();
        Reader {
            repo,
            log: read_log(medicao::rows(repo)),
            shallow: shallow.lines().map(str::to_string).collect(),
            firsts: HashMap::new(),
        }
    }

    fn info(&self, commit: &str) -> Result<Info, String> {
        if self.shallow.iter().any(|c| c == commit) {
            return Err(format!("commit {} is a shallow boundary, so its parents are not known", short(commit)));
        }
        // Plumbing: the raw commit object, which no display setting
        // (`log.showSignature`, `format.pretty`, colors) changes.
        let raw = self.repo.run(&["cat-file", "commit", commit]).map_err(message)?;
        parse_commit(&String::from_utf8_lossy(&raw))
            .ok_or_else(|| format!("git could not give the tree and time of commit {}", short(commit)))
    }

    fn first_parent(&mut self, commit: &str) -> Option<String> {
        if !self.firsts.contains_key(commit) {
            let first = self.info(commit).ok().map(|i| i.parents.into_iter().next().unwrap_or_default());
            self.firsts.insert(commit.to_string(), first);
        }
        self.firsts[commit].clone()
    }

    /// A passed hook row judged `commit`'s tree on its first parent, or on
    /// a commit with that first parent (an amend or a reword).
    fn judged(&mut self, commit: &str, info: &Info) -> bool {
        if self.log.closes.iter().any(|c| c == commit) {
            return true;
        }
        let parent = info.parents.first().map_or("", String::as_str);
        let named: Vec<String> =
            self.log.hooks.iter().filter(|(tree, _)| *tree == info.tree).map(|(_, c)| c.clone()).collect();
        named.iter().any(|c| c == parent || (!c.is_empty() && self.first_parent(c).as_deref() == Some(parent)))
    }

    /// The open lock ids of `commit` and its parents (open or unparsable),
    /// in byte order, then `unknown` when a read failed; empty when none.
    fn open_ids(&self, commit: &str, info: &Result<Info, String>) -> Vec<String> {
        let mut snapshots = vec![commit.to_string()];
        snapshots.extend(info.as_ref().map(|i| i.parents.clone()).unwrap_or_default());
        let mut failed = info.is_err();
        let mut ids = BTreeSet::new();
        for snapshot in snapshots {
            match lock_files(self.repo, &Snapshot::Commit(snapshot)) {
                Ok(locks) => ids.extend(
                    locks
                        .iter()
                        .filter(|(_, bytes)| Lock::parse(bytes).is_none_or(|l| l.is_open()))
                        .map(|(path, _)| medicao::lock_id(path)),
                ),
                Err(_) => failed = true,
            }
        }
        ids.into_iter().chain(failed.then(|| "unknown".to_string())).collect()
    }

    /// Not judged, with a lock open, and (with a cutoff) not before it.
    fn unjudged(&mut self, commit: &str, cutoff: u64) -> bool {
        let info = self.info(commit);
        match &info {
            Ok(i) if i.time < cutoff => return false,
            Ok(i) if self.judged(commit, i) => return false,
            _ => {}
        }
        !self.open_ids(commit, &info).is_empty()
    }
}

/// A raw commit object's header: `tree`, every `parent` in order, and the
/// committer time (the second-to-last field of the `committer` line).
fn parse_commit(raw: &str) -> Option<Info> {
    let (mut tree, mut time, mut parents) = (None, None, Vec::new());
    for line in raw.lines().take_while(|l| !l.is_empty()) {
        match line.split_once(' ') {
            Some(("tree", id)) => tree = Some(id.to_string()),
            Some(("parent", id)) => parents.push(id.to_string()),
            Some(("committer", who)) => time = who.rsplit(' ').nth(1).and_then(|t| t.parse().ok()),
            _ => {}
        }
    }
    Some(Info { tree: tree.filter(|t| !t.is_empty())?, time: time?, parents })
}

fn message(stop: Stop) -> String {
    match stop {
        Stop::Failed(m) => m,
        Stop::Refused(r) => r.what().to_string(),
    }
}

/// Each byte below 0x20, and 0x7f, as a space: one line of text.
fn flat(text: &str) -> String {
    text.chars().map(|c| if c < ' ' || c == '\x7f' { ' ' } else { c }).collect()
}

/// Points 4 and 5: the commits of `<base>..HEAD` with a lock open that the
/// hook did not judge, at or after the cutoff, in `rev-list --topo-order`
/// order; None when there is no cutoff or the range cannot be listed.
pub fn commits(repo: &Repo, base: &str) -> Option<Vec<String>> {
    let mut reader = Reader::new(repo);
    let cutoff = reader.log.cutoff?;
    let list = repo.text(&["rev-list", "--topo-order", &format!("{base}..HEAD")]).ok()?;
    Some(list.lines().filter(|c| reader.unjudged(c, cutoff)).map(str::to_string).collect())
}

/// `<n> (<shorts>)`: the first 5 short ids, then ` and <k> more`.
pub fn named(commits: &[String]) -> String {
    let shorts: Vec<&str> = commits.iter().take(5).map(|c| short(c)).collect();
    let more = commits.len().saturating_sub(5);
    let more = if more > 0 { format!(" and {more} more") } else { String::new() };
    format!("{} ({}{more})", commits.len(), shorts.join(", "))
}

/// Point 4's line for `status`: the base is `origin/<default>`, else `<default>`.
pub fn status_line(repo: &Repo) -> Option<String> {
    let default = repo.default_branch();
    let base = [format!("origin/{default}"), default].into_iter().find(|b| repo.resolve(b).ok().flatten().is_some())?;
    let found = commits(repo, &base).filter(|c| !c.is_empty())?;
    Some(format!(
        "shipcraft: commits with a lock open that the hook did not judge: {}; shipcraft ci --base {base} judges them",
        named(&found)
    ))
}

/// Point 1: `git write-tree` of the effective index (`GIT_INDEX_FILE`, else
/// the repository's), run on a temporary copy so the caller's index is never
/// rewritten (item 28); "" on any other failure. A missing index file is
/// an empty index, as git reads it.
pub fn index_tree(repo: &Repo) -> String {
    let index = match std::env::var_os("GIT_INDEX_FILE") {
        // Relative to the root, where the hook's git calls run (`git -C <root>`).
        Some(path) => Some(repo.root().join(path)),
        None => repo.try_text(&["rev-parse", "--git-path", "index"]).map(|p| repo.path(&p)),
    };
    let Some(index) = index else { return String::new() };
    let Ok(temp) = TempDir::new("shipcraft-tree") else { return String::new() };
    let copy = temp.path().join("index");
    // No index file is an empty index to git: write-tree then reads the
    // copy's path, which does not exist, and gives the empty tree.
    match fs::copy(&index, &copy) {
        Err(e) if e.kind() != std::io::ErrorKind::NotFound => return String::new(),
        _ => {}
    }
    let out = Command::new("git").arg("-C").arg(repo.root()).arg("write-tree").env("GIT_INDEX_FILE", &copy).output();
    match out {
        Ok(out) if out.status.success() => String::from_utf8_lossy(&out.stdout).trim().to_string(),
        _ => String::new(),
    }
}

/// Point 3: `close` without a mark checks HEAD when it has a lock open and
/// the hook did not judge it; prints its two lines, writes no row.
pub fn post_commit(repo: &Repo) {
    let Some(head) = repo.head().ok().flatten() else { return };
    let mut reader = Reader::new(repo);
    let info = reader.info(&head);
    let first = info.as_ref().ok().map(|i| i.parents.first().cloned());
    let present = |commit: &str| !matches!(repo.read(&Snapshot::Commit(commit.into()), CONFIG_FILE), Ok(None));
    // A failed read of HEAD's parents counts as a config present.
    if !present(&head) && first.as_ref().is_some_and(|p| p.as_deref().is_none_or(|p| !present(p))) {
        return;
    }
    if info.as_ref().is_ok_and(|i| reader.judged(&head, i)) {
        return;
    }
    let ids = reader.open_ids(&head, &info);
    if ids.is_empty() {
        return;
    }
    let short = short(&head);
    println!(
        "shipcraft: commit {short} ({}) was not judged by the hook, with lock {} open; checking it now against the locks, without the suite (CI judges it in full).",
        flat(&action(repo, &head)),
        flat(&ids.join(", "))
    );
    let checked = info.map(|i| crate::ci::check_commit(repo, &head, &i.parents, |_, _| false));
    match checked {
        Ok(Ok(_)) => println!("shipcraft: commit {short} keeps the locks' files (the suite did not run); if the locked cases pass now, a commit through the hook closes the lock: git commit --allow-empty -m \"close lock\""),
        Ok(Err(Stop::Refused(r))) => println!(
            "shipcraft: commit {short} would be refused by CI ({}): {}; next: {}",
            flat(r.code),
            flat(r.what()),
            crate::inv::route(&flat(r.how()))
        ),
        Ok(Err(Stop::Failed(e))) | Err(e) => println!("shipcraft: commit {short} could not be checked ({}); CI checks it", flat(&e)),
    }
}

/// HEAD's own reflog: the message of its last line up to the first `: `,
/// when that line moved HEAD to `head`; `unknown` otherwise.
fn action(repo: &Repo, head: &str) -> String {
    let line = repo
        .try_text(&["rev-parse", "--git-path", "logs/HEAD"])
        .and_then(|p| fs::read(repo.path(&p)).ok())
        .and_then(|log| log.split(|b| *b == b'\n').rfind(|l| !l.is_empty()).map(<[u8]>::to_vec));
    let line = String::from_utf8_lossy(&line.unwrap_or_default()).into_owned();
    let Some((ids, text)) = line.split_once('\t') else { return "unknown".into() };
    match ids.split(' ').nth(1) == Some(head) {
        true => text.split_once(": ").map_or(text, |(action, _)| action).to_string(),
        false => "unknown".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn the_log_keeps_typed_rows_and_the_cutoff_needs_a_tree() {
        let log = read_log(vec![
            json!({"layer": "hook", "result": "passed", "commit": "a", "tree": "t1", "at": 9}),
            json!({"layer": "hook", "result": "refused", "commit": "b", "tree": "t2", "at": 5}),
            json!({"layer": "hook", "result": "passed", "commit": "c", "at": 1}),
            json!({"layer": "hook", "result": "passed", "commit": "d", "tree": "t3", "at": -2}),
            json!({"layer": "close", "result": "passed", "commit": "e"}),
            json!({"layer": "close", "result": "passed", "commit": 7}),
            json!({"layer": "close", "result": "refused", "commit": "f"}),
            json!({"layer": "close", "result": 1, "commit": "g"}),
            json!([1, 2]),
        ]);
        assert_eq!(log.hooks, vec![("t1".to_string(), "a".to_string()), ("t3".to_string(), "d".to_string())]);
        assert_eq!(log.closes, vec!["e".to_string()]);
        assert_eq!(log.cutoff, Some(5));
        assert_eq!(read_log(vec![json!({"layer": "ci", "result": "passed", "commit": "a", "at": 1})]).cutoff, None);
    }

    #[test]
    fn a_raw_commit_gives_tree_parents_and_committer_time() {
        let raw = "tree t1\nparent p1\nparent p2\nauthor A <a@x> 5 +0000\ncommitter C D <c@x> 1795189812 -0300\ngpgsig -----BEGIN SSH SIGNATURE-----\n abc\n\nmsg\ntree no\n";
        let info = parse_commit(raw).unwrap();
        assert_eq!((info.tree.as_str(), info.time), ("t1", 1795189812));
        assert_eq!(info.parents, vec!["p1".to_string(), "p2".to_string()]);
        assert!(parse_commit("tree t1\n").is_none());
        assert!(parse_commit("Good \"git\" signature\ntree t1\n").is_none());
    }

    #[test]
    fn a_missing_index_is_the_empty_tree_and_stays_missing() {
        if std::env::var_os("GIT_INDEX_FILE").is_some() {
            return; // run inside a hook: the effective index is not this repository's
        }
        let dir = TempDir::new("shipcraft-test-item141").unwrap();
        assert!(crate::git::git_in(dir.path(), &["init", "-q"]).unwrap().status.success());
        let repo = Repo::at_root(dir.path());
        let empty = repo.text(&["hash-object", "-t", "tree", "/dev/null"]).unwrap();
        assert_eq!(index_tree(&repo), empty);
        assert!(!dir.path().join(".git/index").exists());
    }

    #[test]
    fn named_shows_five_then_how_many_more() {
        let c: Vec<String> = (0..7).map(|i| format!("{i}{i}{i}{i}{i}{i}{i}{i}")).collect();
        assert_eq!(named(&c[..2]), "2 (0000000, 1111111)");
        assert_eq!(named(&c), "7 (0000000, 1111111, 2222222, 3333333, 4444444 and 2 more)");
        assert_eq!(flat("a\nb\tc\x7fd"), "a b c d");
    }
}
