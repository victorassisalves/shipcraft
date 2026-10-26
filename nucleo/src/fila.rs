//! Item 7: the machine's queue. Local CI and local review run at most
//! `[maquina] slots` at a time, across all projects of the machine.
//!
//! A slot is an flock on `slot-<i>`; a waiter is an flock on a file in
//! `espera/`, named by arrival. The OS drops a lock when its process dies, so
//! a crash never holds the queue.

use crate::config::Config;
use crate::refusal::{failed, Result};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, Write};
use std::path::{Path, PathBuf};
use std::thread::sleep;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// A slot held until dropped.
pub struct Slot(File);

impl Drop for Slot {
    fn drop(&mut self) {
        let _ = self.0.set_len(0);
        let _ = self.0.unlock();
    }
}

fn dir() -> PathBuf {
    let state = std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state"));
    state.join("shipcraft/queue")
}

/// `[maquina] slots`: the machine's config first, then the project's; 1 by default.
pub fn slots(config: &Config) -> u64 {
    let home = PathBuf::from(std::env::var_os("HOME").unwrap_or_default());
    let xdg = std::env::var_os("XDG_CONFIG_HOME").map(PathBuf::from).unwrap_or_else(|| home.join(".config"));
    let machine = fs::read_to_string(xdg.join("shipcraft/config.toml"))
        .ok()
        .and_then(|t| t.parse::<toml::Table>().ok())
        .and_then(|t| t.get("machine")?.get("slots")?.as_integer());
    machine.map(|n| n as u64).or(config.maquina.slots).unwrap_or(1).max(1)
}

fn open(path: &Path) -> Result<File> {
    OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path)
        .map_err(|e| failed(format!("open {}: {e}", path.display())))
}

/// Waits for a slot. `who` says what runs ("proj (branch, ci)"), for whoever waits.
pub fn enter(slots: u64, who: &str) -> Result<Slot> {
    let dir = dir();
    let waiting = dir.join("espera");
    fs::create_dir_all(&waiting).map_err(|e| failed(format!("create {}: {e}", waiting.display())))?;
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    let name = format!("{nanos:024}-{}", std::process::id());
    // Locked before it shows up in espera/, so nobody takes it for a dead waiter.
    let tmp = dir.join(format!(".{name}"));
    let ticket = open(&tmp)?;
    ticket.lock().map_err(|e| failed(format!("lock {}: {e}", tmp.display())))?;
    let mine = waiting.join(&name);
    fs::rename(&tmp, &mine).map_err(|e| failed(format!("enter the queue: {e}")))?;

    let mut shown = String::new();
    loop {
        let ahead = waiters_ahead(&waiting, &name);
        if ahead == 0 {
            for i in 0..slots {
                let mut slot = open(&dir.join(format!("slot-{i}")))?;
                if slot.try_lock().is_ok() {
                    let _ = slot.set_len(0);
                    let _ = slot.rewind();
                    let _ = slot.write_all(who.as_bytes());
                    let _ = fs::remove_file(&mine);
                    drop(ticket);
                    return Ok(Slot(slot));
                }
            }
        }
        let line = format!(
            "shipcraft: in the machine queue ({slots} slot(s)): position {}; running now: {}",
            ahead + 1,
            running(&dir, slots)
        );
        if line != shown {
            eprintln!("{line}");
            shown = line;
        }
        sleep(Duration::from_millis(250));
    }
}

/// Live waiters that arrived before `name`; dead ones are cleared.
fn waiters_ahead(waiting: &Path, name: &str) -> usize {
    let Ok(entries) = fs::read_dir(waiting) else { return 0 };
    let mut names: Vec<String> = entries.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect();
    names.sort();
    names
        .into_iter()
        .take_while(|n| n.as_str() < name)
        .filter(|n| {
            let path = waiting.join(n);
            match File::open(&path) {
                Ok(f) if f.try_lock().is_ok() => {
                    let _ = fs::remove_file(&path);
                    false
                }
                Ok(_) => true,
                Err(_) => false,
            }
        })
        .count()
}

/// What holds the slots now.
fn running(dir: &Path, slots: u64) -> String {
    let mut who = Vec::new();
    for i in 0..slots {
        let Ok(mut f) = File::open(dir.join(format!("slot-{i}"))) else { continue };
        if f.try_lock().is_ok() {
            continue; // free: what it says is stale
        }
        let mut text = String::new();
        if f.read_to_string(&mut text).is_ok() && !text.trim().is_empty() {
            who.push(text.trim().to_string());
        }
    }
    if who.is_empty() {
        "—".to_string()
    } else {
        who.join("; ")
    }
}
