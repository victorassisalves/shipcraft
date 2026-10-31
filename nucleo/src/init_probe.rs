//! Item 71: a Node workspace whose root vitest config defines the projects runs
//! each vitest suite from the root with `--project=<name>`, so the root config
//! (pool options, `globalSetup`) applies. `init` asks vitest which project holds
//! which files (`vitest list --filesOnly --json`), once, and converts a suite
//! only when the answer names one project that is safe to write and lies inside
//! the suite's folder.

use crate::lang::Profile;
use crate::red::one_line;
use crate::suite::shell_quote;
use std::fs;
use std::io::Read;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc::{self, TryRecvError};
use std::thread;
use std::time::{Duration, Instant};

const STEMS: [&str; 4] = ["vitest.workspace", "vitest.projects", "vitest.config", "vite.config"];
const EXTS: [&str; 7] = ["ts", "mts", "cts", "js", "mjs", "cjs", "json"];
const LIMIT: Duration = Duration::from_secs(60);
const PROBE: [&str; 6] = ["--no", "--", "vitest", "list", "--filesOnly", "--json"];

const NONE: &str = "vitest listed none of its files";
const MANY: &str = "vitest listed its files in more than one project";
const UNSAFE: &str = "its vitest project name is not one shipcraft writes in a command";
const OUTSIDE: &str = "its vitest project also lists files outside it";
const BAD_FOLDER: &str = "its folder name cannot be written in a glob";

/// One entry of the answer: the file (canonical when possible) and its project name.
struct Entry {
    file: PathBuf,
    name: String,
}

/// Converts the vitest suites of a workspace when the probe allows it. Returns
/// the lines to print after the workspace line, and whether a suite converted
/// (then the config is written in the `[[suite]]` form).
pub fn convert(root: &Path, suites: &mut [(String, String, Profile)]) -> (Vec<String>, bool) {
    let candidates: Vec<usize> = (0..suites.len()).filter(|&i| suites[i].2.runner == "vitest").collect();
    if candidates.is_empty() || !triggered(root) {
        return (Vec::new(), false);
    }
    let entries = match probe(root) {
        Ok(entries) => entries,
        Err(how) => {
            return (
                vec![format!(
                    "shipcraft: suites run inside their packages: `vitest list` {how}; the root vitest config does not apply to them"
                )],
                false,
            )
        }
    };
    let base = fs::canonicalize(root).unwrap_or_else(|_| root.to_path_buf());
    let mut lines = Vec::new();
    let mut any = false;
    for i in candidates {
        let (name, dir, profile) = &mut suites[i];
        let shown = one_line(name);
        match judge(&base, dir, &entries) {
            Ok(project) => {
                lines.push(format!(
                    "shipcraft: suite {shown} runs from the repository root with --project={}, so the root vitest config applies",
                    one_line(&project)
                ));
                root_form(dir, &project, profile);
                *dir = ".".to_string();
                any = true;
            }
            Err(why) => lines.push(format!("shipcraft: suite {shown} runs inside its package: {why}")),
        }
    }
    (lines, any)
}

/// Point 1: a regular file (never followed) at the root with a vitest config name.
fn triggered(root: &Path) -> bool {
    STEMS.iter().any(|stem| {
        EXTS.iter().any(|ext| root.join(format!("{stem}.{ext}")).symlink_metadata().is_ok_and(|m| m.is_file()))
    })
}

/// Point 3: the project the suite converts to, or the reason it does not.
fn judge(base: &Path, dir: &str, entries: &[Entry]) -> Result<String, &'static str> {
    let folder = base.join(dir);
    let inside = |e: &&Entry| e.file.starts_with(&folder);
    let mine: Vec<&Entry> = entries.iter().filter(inside).collect();
    let Some(first) = mine.first() else { return Err(NONE) };
    let project = first.name.clone();
    if mine.iter().any(|e| e.name != project) {
        return Err(MANY);
    }
    let allowed = |c: char| c.is_ascii_alphanumeric() || matches!(c, '@' | '/' | '.' | '_' | '-');
    if project.is_empty() || project.starts_with('-') || !project.chars().all(allowed) {
        return Err(UNSAFE);
    }
    if entries.iter().any(|e| e.name.eq_ignore_ascii_case(&project) && !e.file.starts_with(&folder)) {
        return Err(OUTSIDE);
    }
    let literal = |c: char| !matches!(c, '*' | '?' | '[' | ']' | '{' | '}' | '!' | '(' | ')') && !c.is_control();
    if !dir.chars().all(literal) {
        return Err(BAD_FOLDER);
    }
    Ok(project)
}

/// Point 4: the command with `--project=<project>` right after `run`, globs
/// prefixed with the folder, and the check entering the package.
fn root_form(dir: &str, project: &str, profile: &mut Profile) {
    profile.command = profile.command.replacen("vitest run ", &format!("vitest run --project={project} "), 1);
    profile.globs = profile.globs.iter().map(|g| format!("{dir}/{g}")).collect();
    if profile.check.is_some() {
        let target = format!("./{dir}");
        let plain = target.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '/' | '.' | '_' | '-'));
        let target = if plain { target } else { shell_quote(&target) };
        profile.check = Some(format!("cd {target} && npx --no -- tsc --noEmit"));
    }
}

/// Point 2: runs the probe from the root, reading its stdout while it runs,
/// with one limit for the whole of it. The error is the `<how>` of point 5.
fn probe(root: &Path) -> Result<Vec<Entry>, String> {
    let mut command = Command::new("npx");
    command
        .args(PROBE)
        .current_dir(root)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .process_group(0);
    let mut child = command.spawn().map_err(|_| "could not start".to_string())?;
    let started = Instant::now();
    let Some(mut stdout) = child.stdout.take() else {
        stop(&mut child);
        return Err("could not be read".to_string());
    };
    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || {
        let mut bytes = Vec::new();
        let read = stdout.read_to_end(&mut bytes).map(|_| bytes);
        let _ = sender.send(read);
    });
    let mut status = None;
    let mut output = None;
    loop {
        if status.is_none() {
            match child.try_wait() {
                Ok(found) => status = found,
                Err(_) => {
                    stop(&mut child);
                    return Err("could not be read".to_string());
                }
            }
        }
        if output.is_none() {
            match receiver.try_recv() {
                Ok(Ok(bytes)) => output = Some(bytes),
                Ok(Err(_)) | Err(TryRecvError::Disconnected) => {
                    stop(&mut child);
                    return Err("could not be read".to_string());
                }
                Err(TryRecvError::Empty) => {}
            }
        }
        if let (Some(status), Some(bytes)) = (status, output.as_ref()) {
            if let Some(signal) = status.signal() {
                return Err(format!("was stopped by signal {signal}"));
            }
            match status.code() {
                Some(0) => return parse(bytes).ok_or_else(|| "printed no file list".to_string()),
                Some(code) => return Err(format!("exited {code}")),
                None => return Err("could not be read".to_string()),
            }
        }
        if started.elapsed() >= LIMIT {
            stop(&mut child);
            return Err("timed out after 60 s".to_string());
        }
        thread::sleep(Duration::from_millis(20));
    }
}

/// Kills the probe's whole group, and reaps its leader.
fn stop(child: &mut std::process::Child) {
    if let Err(e) = crate::processo::kill_group(child.id()) {
        eprintln!("shipcraft: could not stop the process group {}: {e}", child.id());
    }
    let _ = child.kill();
    let _ = child.wait();
}

/// A JSON array of objects, each with an absolute string `file`; anything
/// else rejects the whole answer.
fn parse(bytes: &[u8]) -> Option<Vec<Entry>> {
    let text = std::str::from_utf8(bytes).ok()?;
    let value: serde_json::Value = serde_json::from_str(text).ok()?;
    let mut entries = Vec::new();
    for item in value.as_array()? {
        let object = item.as_object()?;
        let file = object.get("file")?.as_str()?;
        let path = Path::new(file);
        if !path.is_absolute() {
            return None;
        }
        let name = object.get("projectName").and_then(|v| v.as_str()).unwrap_or_default().to_string();
        let file = fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
        entries.push(Entry { file, name });
    }
    Some(entries)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(file: &str, name: &str) -> Entry {
        Entry { file: PathBuf::from(file), name: name.to_string() }
    }

    #[test]
    fn judges_in_the_order_of_point_3() {
        let base = Path::new("/r");
        let ok = [entry("/r/p/a/x.test.ts", "api")];
        assert_eq!(judge(base, "p/a", &ok), Ok("api".to_string()));
        assert_eq!(judge(base, "p/ab", &ok), Err(NONE));
        let mixed = [entry("/r/p/a/x.test.ts", "api"), entry("/r/p/a/y.test.ts", "")];
        assert_eq!(judge(base, "p/a", &mixed), Err(MANY));
        assert_eq!(judge(base, "p/a", &[entry("/r/p/a/x.test.ts", "")]), Err(UNSAFE));
        assert_eq!(judge(base, "p/a", &[entry("/r/p/a/x.test.ts", "-x")]), Err(UNSAFE));
        let collide = [entry("/r/p/a/x.test.ts", "api"), entry("/r/p/b/x.test.ts", "API")];
        assert_eq!(judge(base, "p/a", &collide), Err(OUTSIDE));
        assert_eq!(judge(base, "p/a!", &[entry("/r/p/a!/x.test.ts", "api")]), Err(BAD_FOLDER));
    }

    #[test]
    fn rejects_answers_that_are_not_a_file_list() {
        assert!(parse(b"[]").is_some_and(|e| e.is_empty()));
        assert!(parse(b"[{\"file\":\"rel.ts\"}]").is_none());
        assert!(parse(b"[{\"file\":\"/a.ts\"},1]").is_none());
        assert!(parse(b"{}").is_none());
        assert!(parse(b"\xff").is_none());
        assert_eq!(parse(b"[{\"file\":\"\\/a.ts\",\"projectName\":7}]").unwrap()[0].name, "");
    }
}
