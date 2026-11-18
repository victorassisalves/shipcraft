//! The read-only git runner (item 76).

use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;
use std::process::{Command, Stdio};

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

/// Read-only git at the discovered root, with no lazy fetch and no prompt.
pub(crate) struct Git {
    pub(super) root: PathBuf,
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
    pub(super) fn ok(&self, args: &[&str]) -> std::result::Result<Vec<u8>, String> {
        match self.call(args)? {
            (Some(0), out) => Ok(out),
            (code, _) => Err(failure(args, code)),
        }
    }

    /// Exit 0's stdout, or None for exit 1 with no output (absent, not a failure).
    pub(super) fn maybe(&self, args: &[&str]) -> std::result::Result<Option<Vec<u8>>, String> {
        match self.call(args)? {
            (Some(0), out) => Ok(Some(out)),
            (Some(1), out) if out.is_empty() => Ok(None),
            (code, _) => Err(failure(args, code)),
        }
    }

    /// The commit a ref or tag names, or None when absent or not a commit.
    pub(super) fn commit(&self, name: &str) -> std::result::Result<Option<String>, String> {
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
    pub(super) fn locks(&self, commit: &str) -> std::result::Result<BTreeMap<String, String>, String> {
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

/// Item 127: the args of the one `git log` call that reads RED commits: every
/// commit of every ref and HEAD, as stored, with each lock file change against
/// its parent, NUL-framed (`%H`, `%P`, `%ct`, `%B`, then raw pairs).
const RED_LOG: [&str; 18] = [
    "--no-replace-objects",
    "-c",
    "log.showSignature=false",
    "-c",
    "i18n.logOutputEncoding=UTF-8",
    "-c",
    "log.follow=false",
    "log",
    "--no-show-signature",
    "--no-color",
    "--all",
    "--full-history",
    "--no-renames",
    "--raw",
    "-z",
    "--no-abbrev",
    "--format=%H%x00%P%x00%ct%x00%B",
    "--",
];

impl Git {
    /// Item 127: for each wanted (lock, parent), the message of its RED commit:
    /// one parent equal to `parent`, adding `.shipcraft/locks/<lock>.json` as a
    /// regular file; the earliest by committer time, then by id.
    pub(super) fn red_commits(
        &self,
        wanted: &BTreeSet<(String, String)>,
    ) -> std::result::Result<BTreeMap<(String, String), String>, String> {
        let args = [&RED_LOG[..], &[".shipcraft/locks/"]].concat();
        let out = self.ok(&args)?;
        let mut found: BTreeMap<(String, String), (i64, String, String)> = BTreeMap::new();
        for c in lock_commits(&out).ok_or_else(|| unreadable(&args))? {
            let [parent] = &c.parents[..] else { continue };
            for (lock, p) in wanted.iter().filter(|(_, p)| p == parent) {
                let path = format!(".shipcraft/locks/{lock}.json").into_bytes();
                let mut inside = path.clone();
                inside.push(b'/');
                let added = c.changes.iter().any(|(mode, status, file)| {
                    *file == path && *status == b"A" && (*mode == b"100644" || *mode == b"100755")
                });
                if !added || c.changes.iter().any(|(_, _, file)| file.starts_with(&inside)) {
                    continue;
                }
                let candidate = (c.time, c.id.clone(), String::from_utf8_lossy(c.message).into_owned());
                let best = found.entry((lock.clone(), p.clone())).or_insert_with(|| candidate.clone());
                if (candidate.0, &candidate.1) < (best.0, &best.1) {
                    *best = candidate;
                }
            }
        }
        Ok(found.into_iter().map(|(key, (_, _, message))| (key, message)).collect())
    }
}

/// A commit of item 127's log: its changes as (new mode, status, path) bytes.
struct LogCommit<'a> {
    id: String,
    parents: Vec<String>,
    time: i64,
    message: &'a [u8],
    changes: Vec<(&'a [u8], &'a [u8], &'a [u8])>,
}

/// Item 127: whole records only; None for anything else.
fn lock_commits(out: &[u8]) -> Option<Vec<LogCommit<'_>>> {
    let full = |t: &str| {
        (t.len() == 40 || t.len() == 64) && t.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    };
    let text = |t: &[u8]| std::str::from_utf8(t).ok().map(str::to_string);
    let mut tokens: Vec<&[u8]> = out.split(|b| *b == 0).collect();
    // Every record ends with a NUL: the last piece is empty.
    if tokens.pop()? != b"" {
        return None;
    }
    let mut tokens = tokens.into_iter().peekable();
    let mut commits = Vec::new();
    while let Some(id) = tokens.next() {
        let id = text(id).filter(|t| full(t))?;
        let parents = text(tokens.next()?)?;
        let parents: Vec<String> = parents.split(' ').filter(|p| !p.is_empty()).map(str::to_string).collect();
        if !parents.iter().all(|p| full(p)) {
            return None;
        }
        let time = text(tokens.next()?)?;
        let digits = time.strip_prefix('-').unwrap_or(&time);
        if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        let (time, message) = (time.parse().ok()?, tokens.next()?);
        let mut changes = Vec::new();
        while let Some(meta) = tokens.peek().and_then(|t| t.strip_prefix(b"\n").unwrap_or(t).strip_prefix(b":")) {
            tokens.next();
            let fields: Vec<&[u8]> = meta.split(|b| *b == b' ').collect();
            let [_, mode, _, _, status] = fields[..] else { return None };
            changes.push((mode, status, tokens.next()?));
        }
        commits.push(LogCommit { id, parents, time, message, changes });
    }
    Some(commits)
}

pub(super) fn failure(args: &[&str], code: Option<i32>) -> String {
    match code {
        Some(code) => format!("git failed: `git {}` exited {code}", args.join(" ")),
        None => format!("git failed: `git {}` was stopped by a signal", args.join(" ")),
    }
}

pub(super) fn unreadable(args: &[&str]) -> String {
    format!("git failed: `git {}` printed unreadable output", args.join(" "))
}

pub(super) fn utf8(args: &[&str], out: Vec<u8>) -> std::result::Result<String, String> {
    String::from_utf8(out).map_err(|_| unreadable(args))
}

#[cfg(test)]
mod red_log {
    use super::lock_commits;

    #[test]
    fn red_log_records_parse_whole_or_not_at_all() {
        let (a, b, z) = ("a".repeat(40), "b".repeat(64), "0".repeat(40));
        let mut out = format!(
            "{a}\0{b}\0100\0red\n:000000 100644 {z}\0\n:000000 100644 {z} {a} A\0.shipcraft/locks/x.json\0:100644 100755 {a} {a} M\0p"
        )
        .into_bytes();
        out.push(0xff);
        out.extend_from_slice(format!("\0{b}\0{a} {a}\0-5\0\0").as_bytes());
        let got = lock_commits(&out).expect("whole records");
        assert_eq!(got.len(), 2);
        assert_eq!((got[0].parents.clone(), got[0].time), (vec![b.clone()], 100));
        assert_eq!(got[0].message, format!("red\n:000000 100644 {z}").as_bytes());
        assert_eq!(got[0].changes[0], (&b"100644"[..], &b"A"[..], &b".shipcraft/locks/x.json"[..]));
        assert_eq!(got[0].changes[1].2, &[b'p', 0xff][..]);
        assert_eq!((got[1].parents.len(), got[1].time, got[1].message), (2, -5, &b""[..]));
        assert!(lock_commits(b"").expect("no commit").is_empty());
        assert!(lock_commits(&out[..out.len() - 1]).is_none());
        assert!(lock_commits(format!("{a}\0\0x\0m\0").as_bytes()).is_none());
        assert!(lock_commits(format!("{}\0\01\0m\0", a.to_uppercase()).as_bytes()).is_none());
        assert!(lock_commits(format!("{a}\0\01\0m\0:1 2 A\0p\0").as_bytes()).is_none());
    }
}
