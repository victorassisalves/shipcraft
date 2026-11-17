//! The read-only git runner (item 76).

use std::collections::BTreeMap;
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
