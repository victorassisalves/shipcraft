//! Item 135: `shipcraft export --base <ref> <branch>` writes `<branch>` with the
//! commits of `<ref>..HEAD` without Shipcraft's files, for a project that does
//! not use Shipcraft. It reads no config, writes no row and changes nothing but
//! the new branch (and the objects it needs).

use crate::export_block::{outcome, Outcome, BLOCK_NAMES};
use crate::git::{self, short, TempDir};
use crate::refusal::{failed, refuse, Result};
use std::collections::BTreeSet;
use std::ffi::{OsStr, OsString};
use std::io::Write;
use std::os::unix::ffi::OsStrExt;
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};

/// Shipcraft's paths at the repository root (point 1), each covering every path under it.
const NAMES: [&str; 16] = [
    ".shipcraft.toml",
    ".sc2.toml",
    ".shipcraft",
    "AGENTS.md",
    "CLAUDE.md",
    ".pre-commit-config.yaml",
    ".husky/commit-msg",
    ".husky/post-commit",
    "lefthook.yml",
    ".lefthook.yml",
    "lefthook.yaml",
    ".lefthook.yaml",
    "lefthook-local.yml",
    ".lefthook-local.yml",
    "lefthook-local.yaml",
    ".lefthook-local.yaml",
];

/// The name a Shipcraft path shows by on the `kept as in` line, or None when
/// `path` is not at or under one of them.
fn shipcraft_name(path: &[u8]) -> Option<&'static str> {
    NAMES.iter().find_map(|name| {
        let rest = path.strip_prefix(name.as_bytes())?;
        (rest.is_empty() || rest.starts_with(b"/")).then_some(if *name == ".shipcraft" { ".shipcraft/" } else { name })
    })
}

/// Bytes for a message line: UTF-8 with invalid bytes replaced, each control character a space.
fn clean(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).chars().map(|c| if c.is_control() { ' ' } else { c }).collect()
}

/// A commit's subject: its message up to the first `\n`.
fn subject(message: &[u8]) -> String {
    let line = message.split(|b| *b == b'\n').next().unwrap_or_default();
    if line.is_empty() {
        "(no subject)".to_string()
    } else {
        clean(line)
    }
}

/// Closed: UTF-8 without a byte order mark, one JSON object whose `state` is `closed`.
fn closed(bytes: &[u8]) -> bool {
    let Ok(text) = std::str::from_utf8(bytes) else { return false };
    if text.starts_with('\u{feff}') {
        return false;
    }
    match serde_json::from_str::<serde_json::Value>(text) {
        Ok(serde_json::Value::Object(map)) => map.get("state").and_then(|v| v.as_str()) == Some("closed"),
        _ => false,
    }
}

/// A commit object read raw (`git cat-file commit`).
#[derive(Debug, PartialEq)]
struct Raw {
    tree: Vec<u8>,
    parent: Option<Vec<u8>>,
    author: Vec<u8>,
    committer: Vec<u8>,
    message: Vec<u8>,
}

/// The headers end at the first empty line; continuation lines start with a
/// space. None without a `tree`, `author` or `committer` line.
fn parse_commit(bytes: &[u8]) -> Option<Raw> {
    let (headers, message) = match bytes.windows(2).position(|w| w == b"\n\n") {
        Some(i) => (&bytes[..i], &bytes[i + 2..]),
        None => (bytes.strip_suffix(b"\n").unwrap_or(bytes), &b""[..]),
    };
    let (mut tree, mut parent, mut author, mut committer) = (None, None, None, None);
    for line in headers.split(|b| *b == b'\n') {
        let field = |name: &[u8]| line.strip_prefix(name).map(<[u8]>::to_vec);
        if tree.is_none() {
            tree = field(b"tree ");
        }
        if parent.is_none() {
            parent = field(b"parent ");
        }
        if author.is_none() {
            author = field(b"author ");
        }
        if committer.is_none() {
            committer = field(b"committer ");
        }
    }
    Some(Raw { tree: tree?, parent, author: author?, committer: committer?, message: message.to_vec() })
}

/// One `git ls-tree -z` entry.
pub(crate) struct Entry {
    pub(crate) mode: String,
    pub(crate) kind: String,
    pub(crate) oid: String,
    pub(crate) path: Vec<u8>,
}

fn entries(bytes: &[u8]) -> Result<Vec<Entry>> {
    let mut out = Vec::new();
    for record in bytes.split(|b| *b == 0).filter(|r| !r.is_empty()) {
        let tab = record.iter().position(|b| *b == b'\t').ok_or_else(|| failed("unreadable `git ls-tree` output"))?;
        let meta = git::text(&record[..tab]);
        let mut parts = meta.split(' ');
        let (Some(mode), Some(kind), Some(oid)) = (parts.next(), parts.next(), parts.next()) else {
            return Err(failed("unreadable `git ls-tree` output"));
        };
        out.push(Entry { mode: mode.into(), kind: kind.into(), oid: oid.into(), path: record[tab + 1..].to_vec() });
    }
    Ok(out)
}

/// Settings for every git call of export, over the repository's config: no
/// fsmonitor hook or daemon (the temporary index runs it), and no index
/// extension that writes into the repository (`sharedindex.*` of a split
/// index) or reads the working tree (untracked cache, sparse index).
const SETTINGS: [&str; 6] = [
    "core.fsmonitor=false",
    "core.splitIndex=false",
    "core.untrackedCache=false",
    "core.sparseCheckout=false",
    "index.sparse=false",
    "gc.auto=0",
];

/// Git as export runs it: no hook (an empty hooks folder, `SETTINGS`), no lazy
/// fetch, no replace refs or grafts, and a temporary index outside the repository's.
struct Git {
    root: PathBuf,
    hooks: TempDir,
    index: TempDir,
}

impl Git {
    fn open() -> Result<Git> {
        let cwd = std::env::current_dir().map_err(|e| failed(format!("current directory: {e}")))?;
        let hooks = TempDir::new("shipcraft-export-hooks")?;
        let index = TempDir::new("shipcraft-export-index")?;
        let mut git = Git { root: cwd, hooks, index };
        let out = git.output(&["rev-parse", "--show-toplevel"], false, None)?;
        if !out.status.success() {
            // Outside a repository: `ci`'s stop (no-git).
            crate::git::Repo::open()?;
            return Err(failed(format!("`git rev-parse --show-toplevel` failed: {}", git::text(&out.stderr).trim())));
        }
        let root = out.stdout.strip_suffix(b"\n").unwrap_or(&out.stdout);
        git.root = PathBuf::from(OsStr::from_bytes(root));
        Ok(git)
    }

    fn output(&self, args: &[&str], index: bool, stdin: Option<&[u8]>) -> Result<Output> {
        let mut hooks = OsString::from("core.hooksPath=");
        hooks.push(self.hooks.path());
        let mut cmd = Command::new("git");
        cmd.arg("-C").arg(&self.root).arg("--literal-pathspecs").arg("-c").arg(hooks);
        for setting in SETTINGS {
            cmd.arg("-c").arg(setting);
        }
        cmd.args(args);
        cmd.env("GIT_NO_LAZY_FETCH", "1").env("GIT_NO_REPLACE_OBJECTS", "1").env("GIT_GRAFT_FILE", "/dev/null");
        if index {
            cmd.env("GIT_INDEX_FILE", self.index_file());
        }
        let run_failed = |e: std::io::Error| failed(format!("run git: {e}"));
        let Some(input) = stdin else { return cmd.output().map_err(run_failed) };
        let mut child =
            cmd.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn().map_err(run_failed)?;
        let written = child.stdin.take().map(|mut s| s.write_all(input));
        let out = child.wait_with_output().map_err(run_failed)?;
        if let Some(Err(e)) = written {
            if out.status.success() {
                return Err(failed(format!("write to `git {}`: {e}", args.join(" "))));
            }
        }
        Ok(out)
    }

    fn index_file(&self) -> PathBuf {
        self.index.path().join("index")
    }

    fn checked(&self, args: &[&str], index: bool, stdin: Option<&[u8]>) -> Result<Vec<u8>> {
        let out = self.output(args, index, stdin)?;
        if !out.status.success() {
            return Err(failed(format!("`git {}` failed: {}", args.join(" "), git::text(&out.stderr).trim())));
        }
        Ok(out.stdout)
    }

    fn run(&self, args: &[&str]) -> Result<Vec<u8>> {
        self.checked(args, false, None)
    }

    fn line(&self, args: &[&str]) -> Result<String> {
        Ok(git::text(&self.run(args)?).trim().to_string())
    }

    /// Exit 0 is true, exit 1 false, anything else a failure.
    fn test(&self, args: &[&str]) -> Result<(bool, Vec<u8>)> {
        let out = self.output(args, false, None)?;
        match out.status.code() {
            Some(0) => Ok((true, out.stdout)),
            Some(1) => Ok((false, out.stdout)),
            _ => Err(failed(format!("`git {}` failed: {}", args.join(" "), git::text(&out.stderr).trim()))),
        }
    }

    fn verify(&self, spec: &str) -> Result<Option<String>> {
        let (found, out) = self.test(&["rev-parse", "-q", "--verify", spec])?;
        Ok(found.then(|| git::text(&out).trim().to_string()))
    }

    fn ls_tree(&self, args: &[&str]) -> Result<Vec<Entry>> {
        entries(&self.run(&[&["ls-tree", "-z"], args].concat())?)
    }

    /// The entries at or under Shipcraft's paths in a commit, recursively.
    fn shipcraft_entries(&self, commit: &str) -> Result<Vec<Entry>> {
        let args: Vec<&str> = ["-r", "--full-tree", commit, "--"].into_iter().chain(NAMES).collect();
        Ok(self.ls_tree(&args)?.into_iter().filter(|e| shipcraft_name(&e.path).is_some()).collect())
    }

    fn raw(&self, commit: &str) -> Result<Raw> {
        let bytes = self.run(&["cat-file", "commit", commit])?;
        parse_commit(&bytes).ok_or_else(|| failed(format!("commit {commit} has no author or committer line")))
    }
}

/// The first lock in HEAD's `.shipcraft/locks/` that is not closed.
fn open_lock(git: &Git, head: &str) -> Result<Option<Vec<u8>>> {
    let mut tree = head.to_string();
    for folder in [".shipcraft", "locks"] {
        let found = git.ls_tree(&[&tree])?.into_iter().find(|e| e.path == folder.as_bytes() && e.kind == "tree");
        let Some(found) = found else { return Ok(None) };
        tree = found.oid;
    }
    let mut locks: Vec<Entry> =
        git.ls_tree(&[&tree])?.into_iter().filter(|e| e.kind == "blob" && e.path.ends_with(b".json")).collect();
    locks.sort_by(|a, b| a.path.cmp(&b.path));
    for lock in locks {
        if !closed(&git.run(&["cat-file", "blob", &lock.oid])?) {
            return Ok(Some([b".shipcraft/locks/".as_slice(), &lock.path].concat()));
        }
    }
    Ok(None)
}

/// A commit of the range that the export leaves out.
struct LeftOut {
    commit: String,
    subject: String,
}

pub fn run(reference: &str, branch: &str) -> Result<()> {
    let git = Git::open()?;
    let (shown_ref, shown_branch) = (clean(reference.as_bytes()), clean(branch.as_bytes()));
    let base = git
        .verify(&format!("{reference}^{{commit}}"))?
        .ok_or_else(|| failed(format!("--base {shown_ref} is not a commit in this repository")))?;
    let head = git.verify("HEAD^{commit}")?.ok_or_else(|| failed("HEAD has no commit"))?;
    let span = format!("{base}..HEAD");
    let range: Vec<String> =
        git::text(&git.run(&["rev-list", "--reverse", "--topo-order", &span])?).lines().map(str::to_string).collect();

    let root = git.ls_tree(&["--full-tree", &base])?;
    let has = |name: &str| root.iter().any(|e| e.path == name.as_bytes());
    if let Some(file) = [".shipcraft.toml", ".sc2.toml"].into_iter().find(|f| has(f)) {
        return refuse(
            "export-uses-shipcraft",
            format!("{shown_ref} has {file}, so this project uses Shipcraft and its files belong in the PR"),
            "export leaves out Shipcraft's files for a project that does not use Shipcraft; nothing was written",
            "open the PR from this branch with shipcraft pr",
        );
    }
    if let Some(path) = open_lock(&git, &head)? {
        return refuse(
            "export-lock-open",
            format!("HEAD has an open lock, {}, so its locked tests do not pass yet", clean(&path)),
            "the branch you send upstream should hold finished work, and the lock closes only when its cases pass; nothing was written",
            "finish the GREEN (the hook closes the lock when its cases pass), then run shipcraft export again",
        );
    }
    let fork = match range.first() {
        None => head.clone(),
        Some(oldest) => match git.raw(oldest)?.parent {
            Some(parent) => git::text(&parent),
            None => return Err(failed(format!("{shown_ref} and HEAD share no commit"))),
        },
    };
    let merges = git.run(&["rev-list", "--reverse", "--topo-order", "--min-parents=2", &span])?;
    if let Some(merge) = git::text(&merges).lines().next() {
        return refuse(
            "export-merge",
            format!("{} in {shown_ref}..HEAD is a merge commit, so export cannot replay the branch as one line of commits", short(merge)),
            "export writes each commit again on top of the one before it, and a merge has more than one parent; nothing was written",
            format!("rebase the branch onto {shown_ref} (git rebase {shown_ref}), then run shipcraft export again"),
        );
    }
    let refname = format!("refs/heads/{branch}");
    if branch.starts_with('-') || !git.test(&["check-ref-format", &refname])?.0 {
        return Err(failed(format!("{shown_branch} is not a valid branch name")));
    }
    if git.test(&["rev-parse", "-q", "--verify", &refname])?.0 || git.test(&["symbolic-ref", "-q", &refname])?.0 {
        return refuse(
            "export-branch-exists",
            format!("branch {shown_branch} already exists"),
            "export never moves or overwrites a branch; nothing was written",
            format!("pick another name, or remove {shown_branch} yourself if you no longer need it, then run shipcraft export again"),
        );
    }

    let (tip, left_out, mut kept, notes) = replay(&git, &range, &fork)?;
    let exported = range.len() - left_out.len();
    let Some(tip) = tip.filter(|_| exported > 0) else {
        return refuse(
            "export-empty",
            format!("no commit in {shown_ref}..HEAD changes a file outside Shipcraft's files"),
            "the branch would hold nothing to send upstream; nothing was written",
            "commit your change on this branch, then run shipcraft export again",
        );
    };
    git.run(&["update-ref", "--no-deref", &refname, &tip, ""])?;

    let fork = short(&fork);
    println!(
        "shipcraft: exported {exported} of {} commit(s) in {shown_ref}..HEAD to {shown_branch} ({}), on {fork}, without Shipcraft's files",
        range.len(),
        short(&tip)
    );
    for left in &left_out {
        println!("shipcraft: left out {} {}: no change outside Shipcraft's files", short(&left.commit), left.subject);
    }
    // Item 142: a name every commit read the block out of is not reset.
    kept.retain(|name| !BLOCK_NAMES.contains(name) || notes.rule135.contains(name));
    for (name, commit) in &notes.unpaired {
        println!("shipcraft: {name} in {} has a shipcraft block that is not one Shipcraft writes, or markers that do not pair, so it is kept as in {fork}", short(commit));
    }
    if !kept.is_empty() {
        let kept: Vec<&str> = kept.into_iter().collect();
        println!("shipcraft: kept as in {fork}: {}; add any change of yours to them by hand", kept.join(", "));
    }
    println!(
        "shipcraft: next: push {shown_branch} to your fork and open the PR from it; this branch keeps the locks and the hook's history"
    );
    Ok(())
}

/// Item 142: the names of `BLOCK_NAMES` some commit exported by item 135's
/// rule, and those that took (c) with the oldest such commit, in that order.
#[derive(Default)]
struct BlockNotes {
    rule135: BTreeSet<&'static str>,
    unpaired: Vec<(&'static str, String)>,
}

type Replayed = (Option<String>, Vec<LeftOut>, BTreeSet<&'static str>, BlockNotes);

/// Writes the exported commits on `fork`, oldest first: the tip (None when
/// every commit is left out), the commits left out, the Shipcraft names
/// any commit of the range changes in the original history, and item 142's notes.
fn replay(git: &Git, range: &[String], fork: &str) -> Result<Replayed> {
    let (mut previous, mut previous_tree) = (fork.to_string(), git.line(&["rev-parse", &format!("{fork}^{{tree}}")])?);
    let fork_entries = git.shipcraft_entries(fork)?;
    let (mut tip, mut left_out, mut kept, mut notes) = (None, Vec::new(), BTreeSet::new(), BlockNotes::default());
    for commit in range {
        let raw = git.raw(commit)?;
        let parent = raw.parent.as_deref().map(git::text).unwrap_or_else(|| fork.to_string());
        let diff_args: Vec<&str> = [
            "diff-tree",
            "-r",
            "-z",
            "--no-renames",
            "--no-ext-diff",
            "--no-textconv",
            "--name-only",
            &parent,
            commit,
            "--",
        ]
        .into_iter()
        .chain(NAMES)
        .collect();
        for path in git.run(&diff_args)?.split(|b| *b == 0).filter(|p| !p.is_empty()) {
            kept.extend(shipcraft_name(path));
        }
        let tree = exported_tree(git, commit, &raw, &fork_entries, &mut notes)?;
        if tree == previous_tree {
            left_out.push(LeftOut { commit: commit.clone(), subject: subject(&raw.message) });
            continue;
        }
        let object = [
            format!("tree {tree}\nparent {previous}\nauthor ").as_bytes(),
            &raw.author,
            b"\ncommitter ",
            &raw.committer,
            b"\n\n",
            &raw.message,
        ]
        .concat();
        let written =
            git.checked(&["hash-object", "-t", "commit", "-w", "--no-filters", "--stdin"], false, Some(&object))?;
        previous = git::text(&written).trim().to_string();
        previous_tree = tree;
        tip = Some(previous.clone());
    }
    notes.unpaired.sort_by_key(|(name, _)| BLOCK_NAMES.iter().position(|n| n == name));
    Ok((tip, left_out, kept, notes))
}

/// The entries of `list` at or under the Shipcraft path `name`.
fn under<'a>(list: &'a [Entry], name: &str) -> Vec<&'a Entry> {
    list.iter().filter(|e| shipcraft_name(&e.path) == Some(name)).collect()
}

/// `commit`'s tree with Shipcraft's paths as in the fork point, built in the
/// temporary index; `AGENTS.md` and `CLAUDE.md` by item 142's point 1.
fn exported_tree(git: &Git, commit: &str, raw: &Raw, fork_entries: &[Entry], notes: &mut BlockNotes) -> Result<String> {
    let tree = git::text(&raw.tree);
    git.checked(&["read-tree", &tree], true, None)?;
    // A non-folder `.husky` in the commit keeps its place: the fork point's hooks under it stay out.
    let husky_blocks =
        git.ls_tree(&["--full-tree", commit, "--", ".husky"])?.iter().any(|e| e.path == b".husky" && e.kind != "tree");
    let commit_entries = git.shipcraft_entries(commit)?;
    let mut own = Vec::new();
    for name in BLOCK_NAMES {
        let read = |oid: &str| git.run(&["cat-file", "blob", oid]);
        match outcome(name, &under(&commit_entries, name), &under(fork_entries, name), read)? {
            Outcome::Unpaired => {
                notes.rule135.insert(name);
                if !notes.unpaired.iter().any(|(n, _)| *n == name) {
                    notes.unpaired.push((name, commit.to_string()));
                }
            }
            Outcome::Rule135 => drop(notes.rule135.insert(name)),
            other => own.push((name, other)),
        }
    }
    let own_of = |path: &[u8]| own.iter().find(|(name, _)| shipcraft_name(path) == Some(*name)).map(|(_, o)| o);
    let mut info = Vec::new();
    for entry in commit_entries.iter().filter(|e| own_of(&e.path) != Some(&Outcome::AsIs)) {
        info.extend_from_slice(format!("0 {}\t", "0".repeat(entry.oid.len())).as_bytes());
        info.extend_from_slice(&entry.path);
        info.push(0);
    }
    for entry in fork_entries {
        if (husky_blocks && entry.path.starts_with(b".husky/")) || own_of(&entry.path).is_some() {
            continue;
        }
        info.extend_from_slice(format!("{} {} {}\t", entry.mode, entry.kind, entry.oid).as_bytes());
        info.extend_from_slice(&entry.path);
        info.push(0);
    }
    for (name, out) in &own {
        if let Outcome::Blob { mode, content } = out {
            let oid = git.checked(&["hash-object", "-w", "--no-filters", "--stdin"], false, Some(content))?;
            info.extend_from_slice(format!("{mode} blob {}\t{name}\0", git::text(&oid).trim()).as_bytes());
        }
    }
    if !info.is_empty() {
        git.checked(&["update-index", "-z", "--index-info"], true, Some(&info))?;
    }
    Ok(git::text(&git.checked(&["write-tree"], true, None)?).trim().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shipcraft_paths_are_root_names_and_what_is_under_them() {
        assert_eq!(shipcraft_name(b".shipcraft"), Some(".shipcraft/"));
        assert_eq!(shipcraft_name(b".shipcraft/locks/x.json"), Some(".shipcraft/"));
        assert_eq!(shipcraft_name(b"AGENTS.md/guide.md"), Some("AGENTS.md"));
        assert_eq!(shipcraft_name(b".husky/commit-msg"), Some(".husky/commit-msg"));
        assert_eq!(shipcraft_name(b".lefthook-local.yaml"), Some(".lefthook-local.yaml"));
        for other in
            [&b"docs/AGENTS.md"[..], b"AGENTS.md.bak", b".shipcraft.tomlx", b".husky/pre-commit", b".shipcraftx"]
        {
            assert_eq!(shipcraft_name(other), None, "{}", clean(other));
        }
    }

    #[test]
    fn a_raw_commit_keeps_author_committer_and_message_bytes() {
        let raw = b"tree t1\nparent p1\nparent p2\nauthor A <a> 1 +0000\ncommitter K <k> 2 +0000\ngpgsig -----BEGIN\n \n -----END\n\nsubj\n\nbody\n";
        let parsed = parse_commit(raw).unwrap();
        assert_eq!(parsed.tree, b"t1");
        assert_eq!(parsed.parent.as_deref(), Some(&b"p1"[..]));
        assert_eq!(parsed.author, b"A <a> 1 +0000");
        assert_eq!(parsed.committer, b"K <k> 2 +0000");
        assert_eq!(parsed.message, b"subj\n\nbody\n");
        assert_eq!(parse_commit(b"tree t\nauthor A\n\nm").map(|r| r.parent), None);
        assert_eq!(parse_commit(b"tree t\nauthor A\ncommitter K\n").unwrap().message, b"");
    }

    #[test]
    fn subjects_and_paths_print_on_one_line() {
        assert_eq!(subject(b"feat: sub\n\nbody"), "feat: sub");
        assert_eq!(subject(b"\nbody"), "(no subject)");
        assert_eq!(subject(b"a\tb\x1b\xff"), "a b \u{fffd}");
    }

    #[test]
    fn a_lock_is_closed_only_as_an_object_with_state_closed() {
        assert!(closed(br#"{"state":"closed","x":1}"#));
        assert!(closed(br#"{"state":"open","state":"closed"}"#));
        assert!(!closed(br#"{"state":"closed","state":"open"}"#));
        assert!(!closed("\u{feff}{\"state\":\"closed\"}".as_bytes()));
        assert!(!closed(br#"["closed"]"#));
        assert!(!closed(b"{\"state\":\"closed\"} {}"));
        assert!(!closed(b"\xff"));
        assert!(!closed(b"x.json"));
    }

    #[test]
    fn ls_tree_entries_keep_raw_paths() {
        let listed = entries(b"100644 blob abc\ta\tb\x00040000 tree def\t.shipcraft\0").unwrap();
        assert_eq!((listed[0].mode.as_str(), listed[0].path.as_slice()), ("100644", &b"a\tb"[..]));
        assert_eq!((listed[1].kind.as_str(), listed[1].oid.as_str()), ("tree", "def"));
    }
}
