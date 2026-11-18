//! The project files `init` writes or finds.

use crate::config::CONFIG_FILE;
use crate::git::Repo;
use crate::refusal::{failed, Result};
use std::fs;
use std::path::{Path, PathBuf};

pub fn on_path(name: &str) -> bool {
    std::env::var_os("PATH")
        .map(|paths| std::env::split_paths(&paths).any(|dir| is_executable(&dir.join(name))))
        .unwrap_or(false)
}

pub fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    fs::metadata(path).map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0).unwrap_or(false)
}

/// Writes a project file unless it already exists (a link, even a broken one,
/// counts as existing: the init never writes through it).
pub(super) fn write_once(repo: &Repo, created: &mut Vec<PathBuf>, relative: &str, content: &str) -> Result<()> {
    let path = repo.path(relative);
    if path.symlink_metadata().is_ok() {
        println!("shipcraft: {relative} already exists, kept");
        return Ok(());
    }
    write(&path, content, created)?;
    println!("shipcraft: created {relative}");
    Ok(())
}

/// Item 90: with no language there is nothing to generate, so this path never
/// writes a config: one gone since planning stops the run instead.
pub(super) fn keep_config(repo: &Repo) -> Result<()> {
    let path = repo.path(CONFIG_FILE);
    path.symlink_metadata().map_err(|e| failed(format!("{CONFIG_FILE} is gone since init started: {e}")))?;
    println!("shipcraft: {CONFIG_FILE} already exists, kept");
    Ok(())
}

/// Writes a file, noting each directory and file it creates in `created`.
pub(super) fn write(path: &Path, content: &str, created: &mut Vec<PathBuf>) -> Result<()> {
    let missing: Vec<&Path> = path.ancestors().skip(1).take_while(|d| d.symlink_metadata().is_err()).collect();
    for dir in missing.into_iter().rev() {
        fs::create_dir(dir).map_err(|e| failed(format!("create {}: {e}", dir.display())))?;
        created.push(dir.to_path_buf());
    }
    if path.symlink_metadata().is_err() {
        created.push(path.to_path_buf());
    }
    fs::write(path, content).map_err(|e| failed(format!("write {}: {e}", path.display())))
}

pub(super) fn make_executable(path: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o755))
        .map_err(|e| failed(format!("make {} executable: {e}", path.display())))
}
