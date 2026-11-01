//! Item 68: the phase briefs `init` installs in `.shipcraft/briefs/`, after
//! everything else it writes has succeeded. Nothing here fails the init or
//! undoes what it wrote: a brief that cannot be written, or a file already
//! there, is kept with a notice.

use crate::git::Repo;
use std::fs;
use std::io::{ErrorKind, Write};
use std::path::Path;

const DIR: &str = ".shipcraft/briefs";

/// The RED session's brief, in the machine form (`shipcraft`).
const RED_BRIEF: &str = "# shipcraft: the RED phase

You are the RED session: you write the failing tests for a change, not the change.

- Write the failing tests from the intent, never from an implementation.
- Write two cases per rule: the ordinary one, and a boundary a rushed GREEN would get wrong.
- First read the existing tests that cover the behavior the change touches, and never contradict them unless the intent says that behavior changes.
- Each test written for the new behavior must fail for the right reason before you run `shipcraft red`. Passing control tests are fine: they are locked as controls.
- Fake external tools with their real output.
- Commit the tests, their stubs and the lock in one commit, and stop.
- List ambiguities instead of picking a reading silently.
";

/// The GREEN session's brief, in the machine form (`shipcraft`).
const GREEN_BRIEF: &str = "# shipcraft: the GREEN phase

You are the GREEN session: you make the locked tests pass.

- Start from the RED commit.
- Never edit a locked file or a lock (`.shipcraft/locks/*`).
- Change product code, dependencies or config until the locked tests pass.
- Run the locked tests and the other tests the change affects, not the full suite unless the change affects all of it: CI runs it once (where CI is off, once before the PR). Report a failure outside the locked tests; it is not a gate: the hook's verdict decides the commit.
- If a test looks wrong, stop and report the test with the reason, instead of working around it.
- Commit.
";

/// A brief's full text: from a project-local install every command is
/// `npx -- shipcraft`, as in the block (item 61); the last line names the version.
fn text(brief: &str, local: bool) -> String {
    let body = if local { brief.replace("`shipcraft ", "`npx -- shipcraft ") } else { brief.to_string() };
    format!("{body}\n<!-- written by shipcraft {} -->\n", env!("CARGO_PKG_VERSION"))
}

/// Writes the briefs that are missing; returns the closing line's part for the
/// ones written (`, .shipcraft/briefs/red.md`), red before green.
pub fn write(repo: &Repo, local: bool) -> String {
    if let Err(reason) = folder(repo) {
        println!("shipcraft: {DIR} not written: {reason}");
        return String::new();
    }
    let mut listed = String::new();
    for (name, brief) in [("red.md", RED_BRIEF), ("green.md", GREEN_BRIEF)] {
        let relative = format!("{DIR}/{name}");
        let path = repo.path(&relative);
        let variants = [text(brief, local), text(brief, !local)];
        match path.symlink_metadata() {
            Err(e) if e.kind() == ErrorKind::NotFound => match create(&path, &variants[0]) {
                Ok(()) => listed.push_str(&format!(", {relative}")),
                Err(e) => println!("shipcraft: {relative} not written: {e}"),
            },
            Ok(meta) if meta.is_file() => match fs::read(&path).map(String::from_utf8) {
                Ok(Ok(old)) if variants.contains(&old) => {}
                Ok(Ok(_)) => {
                    println!("shipcraft: {relative} differs from this version's, kept: compare it with docs/spec.md")
                }
                _ => println!("shipcraft: {relative} could not be read, kept"),
            },
            _ => println!("shipcraft: {relative} could not be read, kept"),
        }
    }
    listed
}

/// `.shipcraft` and `.shipcraft/briefs`, each checked without following a
/// link, and created when absent.
fn folder(repo: &Repo) -> Result<(), String> {
    for relative in [".shipcraft", DIR] {
        let path = repo.path(relative);
        match path.symlink_metadata() {
            Ok(meta) if meta.file_type().is_symlink() => return Err(format!("{relative} is a symlink")),
            Ok(meta) if !meta.is_dir() => return Err(format!("{relative} is not a folder")),
            Ok(_) => {}
            Err(e) if e.kind() == ErrorKind::NotFound => {
                fs::create_dir(&path).map_err(|e| format!("could not create {relative} ({e})"))?
            }
            Err(e) => return Err(format!("could not check {relative} ({e})")),
        }
    }
    Ok(())
}

/// Writes a new brief through a temporary file in its folder, renamed into
/// place; a failure removes the temporary file.
fn create(path: &Path, content: &str) -> std::io::Result<()> {
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_nanos());
    let mut attempt = 0u32;
    let (temp, mut file) = loop {
        let temp = path.with_file_name(format!(".{name}.shipcraft-{}-{nanos}-{attempt}.tmp", std::process::id()));
        match fs::OpenOptions::new().write(true).create_new(true).open(&temp) {
            Ok(file) => break (temp, file),
            Err(e) if e.kind() == ErrorKind::AlreadyExists && attempt < 100 => attempt += 1,
            Err(e) => return Err(e),
        }
    };
    let result = file.write_all(content.as_bytes()).and_then(|()| file.sync_all()).and_then(|()| {
        // Never replaces an entry that appeared meanwhile.
        match path.symlink_metadata() {
            Err(e) if e.kind() == ErrorKind::NotFound => fs::rename(&temp, path),
            Err(e) => Err(e),
            Ok(_) => Err(std::io::Error::new(ErrorKind::AlreadyExists, "an entry appeared meanwhile")),
        }
    });
    drop(file);
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn briefs_end_with_the_version_and_use_lf() {
        for brief in [RED_BRIEF, GREEN_BRIEF] {
            for local in [false, true] {
                let t = text(brief, local);
                assert!(!t.contains('\r') && t.ends_with('\n'));
                let last = t.lines().last().unwrap();
                assert_eq!(last, format!("<!-- written by shipcraft {} -->", env!("CARGO_PKG_VERSION")));
                assert_eq!(t.contains("npx -- shipcraft"), local && brief == RED_BRIEF);
            }
        }
    }
}
