//! The lock: the RED's contract, one file per cycle in `.shipcraft/locks/<id>.json`.

use crate::git::{Repo, Snapshot};
use crate::refusal::{failed, refuse, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::time::{SystemTime, UNIX_EPOCH};

pub const LOCK_DIR: &str = ".shipcraft/locks";
/// The lock format this shipcraft writes and reads (item 9, rule 2).
pub const FORMAT: u64 = 2;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    Open,
    Closed,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Lock {
    /// The format version: an shipcraft that does not know it refuses to judge.
    #[serde(rename = "format")]
    pub formato: u64,
    pub state: State,
    /// sha256 of each locked test file and of `.shipcraft.toml`, by path.
    pub files: BTreeMap<String, String>,
    /// The cases the report showed at the RED (skipped ones excluded).
    pub cases: Vec<String>,
    /// The cases that failed at the RED.
    pub failing_at_red: Vec<String>,
    /// sha256 of the lock with an empty seal. A hand edit breaks it; it is a
    /// check against mistakes and shortcuts, not a signature.
    pub seal: String,
}

impl Lock {
    pub fn open(files: BTreeMap<String, String>, cases: Vec<String>, failing_at_red: Vec<String>) -> Lock {
        Lock { formato: FORMAT, state: State::Open, files, cases, failing_at_red, seal: String::new() }.sealed()
    }

    /// The same lock, closed by shipcraft.
    pub fn closed(&self) -> Lock {
        Lock { state: State::Closed, ..self.clone() }.sealed()
    }

    pub fn is_open(&self) -> bool {
        self.state == State::Open
    }

    /// None when the bytes are not a lock, or when it was edited by hand.
    pub fn parse(bytes: &[u8]) -> Option<Lock> {
        let lock: Lock = serde_json::from_slice(bytes).ok()?;
        (lock.seal == lock.compute_seal()).then_some(lock)
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).expect("a lock always serializes") + "\n"
    }

    fn sealed(mut self) -> Lock {
        self.seal = self.compute_seal();
        self
    }

    fn compute_seal(&self) -> String {
        let unsealed = Lock { seal: String::new(), ..self.clone() };
        sha256_hex(serde_json::to_string(&unsealed).expect("a lock always serializes").as_bytes())
    }
}

/// The lock files of a snapshot, by path.
pub type LockFiles = BTreeMap<String, Vec<u8>>;

pub fn lock_files(repo: &Repo, snapshot: &Snapshot) -> Result<LockFiles> {
    let mut locks = LockFiles::new();
    for path in repo.list(snapshot, LOCK_DIR)? {
        if !path.ends_with(".json") {
            continue;
        }
        let bytes =
            repo.read(snapshot, &path)?.ok_or_else(|| failed(format!("lock {path} disappeared while reading")))?;
        check_format(&path, &bytes)?;
        locks.insert(path, bytes);
    }
    Ok(locks)
}

/// Refuses a lock written in a format this shipcraft does not know. A lock that is
/// not JSON, or has no format, is left to the seal check (edited by hand).
fn check_format(path: &str, bytes: &[u8]) -> Result<()> {
    let Ok(value) = serde_json::from_slice::<serde_json::Value>(bytes) else { return Ok(()) };
    match value.get("format").or_else(|| value.get("formato")) {
        Some(f) if value.get("formato").is_some() || f.as_u64() != Some(FORMAT) => refuse(
            "lock-format",
            format!("lock {path} has format {f}, and this shipcraft only knows format {FORMAT}"),
            "two machines cannot judge the same commit differently without warning",
            "run `shipcraft red` again with this shipcraft to generate a lock in the current format",
        ),
        _ => Ok(()),
    }
}

/// A new lock path, unique per cycle so two branches never write the same file.
pub fn new_lock_path() -> String {
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    let id = &sha256_hex(format!("{nanos}-{}", std::process::id()).as_bytes())[..12];
    format!("{LOCK_DIR}/{id}.json")
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}
