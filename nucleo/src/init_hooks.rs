//! Item 101: `status` reads the hooks a project keeps under its own
//! `core.hooksPath`, where `init` does not write (item 15a). The check is
//! textual: nothing is expanded or run.

use crate::git::Repo;
use crate::init::{is_executable, LEFTHOOK_FILES};
use crate::init_tool;
use std::fs;
use std::path::{Path, PathBuf};

/// The two hooks, the arguments their call line carries, and how a hook
/// that lacks it is named.
const HOOKS: [(&str, &[&str], &str); 2] = [
    ("commit-msg", &["check", "--commit-msg"], "shipcraft check --commit-msg"),
    ("post-commit", &["close"], "shipcraft close"),
];

/// Point 1: the line for a `core.hooksPath` (`dir`, the raw value) outside
/// `.git/hooks` that no husky, pre-commit or lefthook owns; None keeps today's route.
pub fn status(repo: &Repo, dir: &str) -> Option<String> {
    if dir == ".git/hooks"
        || init_tool::husky_path(Some(dir))
        || init_tool::present(repo)
        || LEFTHOOK_FILES.iter().any(|f| repo.path(f).symlink_metadata().is_ok())
    {
        return None;
    }
    let mut paths = Vec::new();
    for (name, _, _) in HOOKS {
        let Ok(path) = repo.hook_path(name) else {
            return Some(format!("shipcraft: missing hook: could not read the hooks under core.hooksPath {dir}"));
        };
        paths.push(path);
    }
    let problems = problems(dir, &paths);
    Some(if problems.is_empty() {
        format!("shipcraft: hooks in core.hooksPath {dir} call shipcraft (commit-msg and post-commit)")
    } else {
        format!(
            "shipcraft: missing hook: {}; add the shipcraft calls there (shipcraft init does not write under core.hooksPath)",
            problems.join(", ")
        )
    })
}

/// Point 2's problems, commit-msg's first, at most one per hook;
/// `<dir>/<hook>` drops one trailing `/` from `<dir>`.
fn problems(dir: &str, paths: &[PathBuf]) -> Vec<String> {
    let dir = dir.strip_suffix('/').unwrap_or(dir);
    HOOKS
        .iter()
        .zip(paths)
        .filter_map(|((name, args, call), path)| problem(path, args).map(|p| p.text(dir, name, call)))
        .collect()
}

/// The first problem of one hook, if any.
#[derive(Debug, PartialEq)]
enum Problem {
    Missing,
    NoCall,
}

impl Problem {
    fn text(&self, dir: &str, name: &str, call: &str) -> String {
        match self {
            Problem::Missing => format!("{dir}/{name} is missing or not executable"),
            Problem::NoCall => format!("{dir}/{name} does not call {call}"),
        }
    }
}

/// A readable, executable regular file (symlinks followed) holding a call line.
fn problem(path: &Path, args: &[&str]) -> Option<Problem> {
    if !is_executable(path) {
        return Some(Problem::Missing);
    }
    match fs::read(path) {
        Err(_) => Some(Problem::Missing),
        Ok(bytes) if calls(&bytes, args) => None,
        Ok(_) => Some(Problem::NoCall),
    }
}

fn blank(b: u8) -> bool {
    b == b' ' || b == b'\t'
}

fn skip_blanks(s: &[u8]) -> &[u8] {
    let n = s.iter().take_while(|b| blank(**b)).count();
    &s[n..]
}

/// Whether any line of `text` is a call line with these arguments, compared
/// as bytes: split on `\n`, a trailing `\r` stripped, `#` lines skipped.
fn calls(text: &[u8], args: &[&str]) -> bool {
    text.split(|b| *b == b'\n').any(|line| call_line(line.strip_suffix(b"\r").unwrap_or(line), args))
}

/// One shell word: unquoted segments (no blank or quote) and quoted ones (no
/// escapes), up to the first unquoted blank. Its value is the segments joined
/// without their quotes, and the rest of the line; None for an unclosed quote.
fn shell_word(line: &[u8]) -> Option<(Vec<u8>, &[u8])> {
    let mut word = Vec::new();
    let mut rest = line;
    loop {
        match rest.first() {
            None => return Some((word, rest)),
            Some(b) if blank(*b) => return Some((word, rest)),
            Some(&q @ (b'"' | b'\'')) => {
                let end = rest[1..].iter().position(|b| *b == q)?;
                word.extend_from_slice(&rest[1..1 + end]);
                rest = &rest[2 + end..];
            }
            Some(_) => {
                let end = rest.iter().position(|b| blank(*b) || *b == b'"' || *b == b'\'').unwrap_or(rest.len());
                word.extend_from_slice(&rest[..end]);
                rest = &rest[end..];
            }
        }
    }
}

/// Leading blanks, an optional `exec` and blanks, a command word whose last
/// `/` component is `shipcraft`, then blanks and each argument, each followed
/// by blanks or the end of the line.
fn call_line(line: &[u8], args: &[&str]) -> bool {
    let mut rest = skip_blanks(line);
    if rest.first() == Some(&b'#') {
        return false;
    }
    if let Some(after) = rest.strip_prefix(b"exec") {
        if after.first().is_some_and(|b| blank(*b)) {
            rest = skip_blanks(after);
        }
    }
    let Some((word, mut rest)) = shell_word(rest) else { return false };
    if word.rsplit(|b| *b == b'/').next() != Some(b"shipcraft".as_slice()) {
        return false;
    }
    for arg in args {
        if !rest.first().is_some_and(|b| blank(*b)) {
            return false;
        }
        let Some(after) = skip_blanks(rest).strip_prefix(arg.as_bytes()) else { return false };
        rest = after;
    }
    rest.first().is_none_or(|b| blank(*b))
}

#[cfg(test)]
mod tests {
    use super::*;

    const MSG: &[&str] = &["check", "--commit-msg"];
    const CLOSE: &[&str] = &["close"];

    #[test]
    fn spec_examples_call() {
        assert!(calls(br#"exec "$HOME/.local/shipcraft-2/bin/shipcraft" check --commit-msg "$1""#, MSG));
        assert!(calls(b"shipcraft close", CLOSE));
        assert!(calls(b"\t/usr/local/bin/shipcraft close", CLOSE));
        assert!(calls(br#"exec "$HOME/.local/shipcraft-2/bin/shipcraft" close"#, CLOSE));
    }

    #[test]
    fn spec_non_examples_do_not_call() {
        for line in ["# shipcraft close", "echo shipcraft close", "shipcraft-old close", "shipcraft closed"] {
            assert!(!calls(line.as_bytes(), CLOSE), "{line}");
        }
    }

    #[test]
    fn quotes_exec_and_blanks() {
        assert!(calls(b"'/opt/bin/shipcraft' close", CLOSE));
        assert!(calls(b"exec\t'shipcraft' close", CLOSE));
        assert!(calls(b"  exec   shipcraft\tcheck \t--commit-msg\t\"$1\"", MSG));
        assert!(calls(b"shipcraft close # after", CLOSE));
        assert!(calls(b"shipcraft close\r\n", CLOSE));
        assert!(calls(b"#!/bin/sh\nset -e\nshipcraft close\n", CLOSE));
        // The other hook's arguments, a quote left open, words glued to the quote.
        assert!(!calls(b"shipcraft close", MSG));
        assert!(!calls(b"shipcraft check --commit-msg", CLOSE));
        assert!(!calls(b"shipcraft check", MSG));
        assert!(!calls(b"shipcraft check --commit-msgs", MSG));
        assert!(!calls(b"\"shipcraft close", CLOSE));
        assert!(!calls(b"\"shipcraft\"close", CLOSE)); // one word: `shipcraftclose`
        assert!(!calls(b"'shipcraft close", CLOSE));
        assert!(!calls(b"/bin/\"shipcraft close", CLOSE));
        assert!(!calls(b"shipcraft close;", CLOSE));
        assert!(!calls(b"shipcraft/ close", CLOSE));
        assert!(!calls(b"execshipcraft close", CLOSE));
        assert!(!calls(b"  # exec shipcraft close", CLOSE));
        assert!(!calls(b"shipcraft", CLOSE));
    }

    #[test]
    fn mixed_quoting_is_one_shell_word() {
        assert!(calls(br#""$HOME"/bin/shipcraft close"#, CLOSE));
        assert!(calls(br#"'a'"b"/shipcraft close"#, CLOSE));
        assert!(calls(br#"exec /opt/"ship"'craft' check --commit-msg "$1""#, MSG));
        assert!(calls(br#""$HOME"/bin/"shipcraft" close"#, CLOSE));
        assert_eq!(shell_word(br#"'a'"b"/shipcraft close"#), Some((b"ab/shipcraft".to_vec(), b" close".as_slice())));
        assert_eq!(shell_word(br#""$HOME"/bin/shipcraft"#), Some((b"$HOME/bin/shipcraft".to_vec(), b"".as_slice())));
        assert!(!calls(br#""$HOME"/bin/shipcraft-old close"#, CLOSE));
        assert!(!calls(br#""$HOME/bin/shipcraft"x close"#, CLOSE));
    }

    #[test]
    fn bytes_not_utf8_do_not_hide_a_call() {
        assert!(calls(b"# coment\xe1rio em Latin-1\nshipcraft close\n", CLOSE));
        assert!(calls(b"shipcraft close # \xff\xfe", CLOSE));
    }

    #[test]
    fn problems_in_order_one_per_hook() {
        let dir = std::env::temp_dir().join(format!("shipcraft-i101-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let write = |name: &str, body: &str, mode: u32| {
            use std::os::unix::fs::PermissionsExt;
            let p = dir.join(name);
            fs::write(&p, body).unwrap();
            fs::set_permissions(&p, fs::Permissions::from_mode(mode)).unwrap();
            p
        };
        let msg = write("commit-msg", "#!/bin/sh\necho hi\n", 0o755);
        let close = write("post-commit", "#!/bin/sh\nshipcraft close\n", 0o644);
        let missing = dir.join("absent");
        assert_eq!(problem(&msg, MSG), Some(Problem::NoCall));
        // Not executable wins over its call line: only one problem per hook.
        assert_eq!(problem(&close, CLOSE), Some(Problem::Missing));
        assert_eq!(problem(&missing, CLOSE), Some(Problem::Missing));
        assert_eq!(problem(&dir, CLOSE), Some(Problem::Missing));
        let link = dir.join("link");
        let target = write("target", "exec shipcraft close\n", 0o755);
        std::os::unix::fs::symlink(&target, &link).unwrap();
        assert_eq!(problem(&link, CLOSE), None);
        let good = write("good-msg", "exec shipcraft check --commit-msg \"$1\"\n", 0o755);
        assert!(problems("scripts/hooks", &[good, link.clone()]).is_empty());
        assert_eq!(
            problems("scripts/hooks", &[missing.clone(), dir.clone()]),
            [
                "scripts/hooks/commit-msg is missing or not executable",
                "scripts/hooks/post-commit is missing or not executable",
            ]
        );
        // One trailing `/` is dropped before joining; an empty value stays empty.
        assert_eq!(
            problems("scripts/hooks/", &[missing.clone(), msg.clone()]),
            [
                "scripts/hooks/commit-msg is missing or not executable",
                "scripts/hooks/post-commit does not call shipcraft close",
            ]
        );
        assert_eq!(
            problems("hooks//", &[missing.clone(), link.clone()]),
            ["hooks//commit-msg is missing or not executable"]
        );
        assert_eq!(problems("", &[missing.clone(), link.clone()]), ["/commit-msg is missing or not executable"]);
        assert_eq!(
            problems("scripts/hooks", &[msg, close]),
            [
                "scripts/hooks/commit-msg does not call shipcraft check --commit-msg",
                "scripts/hooks/post-commit is missing or not executable",
            ]
        );
        let _ = fs::remove_dir_all(&dir);
    }
}
