//! Item 17: the mark `shipcraft check --commit-msg` leaves for `shipcraft close`, in
//! `git rev-parse --git-path shipcraft/close` (one per worktree): the tree it
//! judged, the HEAD it saw and the locks that close.

use crate::git::Repo;
use crate::refusal::{refuse, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::io::ErrorKind;
use std::path::PathBuf;

#[derive(Serialize, Deserialize)]
pub struct Marca {
    /// `git write-tree` of the judged index.
    pub arvore: String,
    /// HEAD at the judgment (with no commit there is no mark: every lock is new).
    pub head: String,
    pub travas: Vec<String>,
}

pub fn path(repo: &Repo) -> Result<PathBuf> {
    Ok(repo.path(&repo.text(&["rev-parse", "--git-path", "shipcraft/close"])?))
}

/// None when there is no mark, or it does not read as one.
pub fn read(repo: &Repo) -> Option<Marca> {
    serde_json::from_slice(&fs::read(path(repo).ok()?).ok()?).ok()
}

/// Removes the mark; failing to remove it refuses (rule 17).
pub fn remove(repo: &Repo) -> Result<()> {
    let path = path(repo)?;
    match fs::remove_file(&path) {
        Err(e) if e.kind() != ErrorKind::NotFound => not_written(&path, e),
        _ => Ok(()),
    }
}

/// Marks the index as judged: the locks close in the commit made from it.
pub fn write(repo: &Repo, travas: Vec<String>) -> Result<()> {
    let marca = Marca { arvore: repo.text(&["write-tree"])?, head: repo.head()?.unwrap_or_default(), travas };
    let path = path(repo)?;
    let json = serde_json::to_string(&marca).expect("a mark always serializes");
    let written = path.parent().map_or(Ok(()), fs::create_dir_all).and_then(|()| fs::write(&path, json));
    written.or_else(|e| not_written(&path, e))
}

fn not_written(path: &std::path::Path, e: std::io::Error) -> Result<()> {
    refuse(
        "mark-failed",
        format!("could not write the close mark at {}: {e}", path.display()),
        "without the mark, post-commit does not know which commit was judged, and the lock would silently stay open",
        format!("free {} (delete what is there) and commit again", path.display()),
    )
}
