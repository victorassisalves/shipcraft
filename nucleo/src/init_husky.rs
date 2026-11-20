//! Items 25 and 133: the husky route. husky 9 (`core.hooksPath .husky/_` with
//! `.husky/_/h`) and husky 7 or 8 (`core.hooksPath .husky` with husky's
//! `.husky/_/husky.sh`) are integrated; every other husky layout refuses with a
//! Next that can be followed.

use crate::git::Repo;
use crate::init::{is_executable, LOCAL};
use crate::init_tool::{alien, alien_plain, old_husky, read, Tool, HUSKY, TWICE};
use crate::refusal::Result;
use std::fs;
use std::io::ErrorKind;

/// husky 7's and husky 8's helper lines, compared as text (133.1).
pub(crate) const HELPERS: [&str; 2] = [". \"$(dirname \"$0\")/_/husky.sh\"", ". \"$(dirname -- \"$0\")/_/husky.sh\""];
/// 133.2: runners that run the project's installed binary, longest first.
const RUNNERS: [&[&str]; 4] = [&["npx", "--no", "--"], &["npx", "--no"], &["pnpm", "exec", "--"], &["pnpm", "exec"]];
const HELPER: &str = ".husky/_/husky.sh";

pub(crate) fn plan(repo: &Repo, dir: Option<&str>, local: bool) -> Result<Tool> {
    let old = old_husky(repo);
    let h = fs::read(repo.path(".husky/_/h"));
    if !old && dir == Some(".husky/_") {
        if let Ok(bytes) = &h {
            if bytes.is_empty() {
                return alien(".husky/_/h is empty: husky installation was interrupted".into(), "run `npx husky`");
            }
            return husky(repo, local, false);
        }
    }
    if old {
        return alien_plain(
            "this project configures husky in package.json (husky.hooks), the form of husky 4 and earlier",
            "update husky to 9 and run `npx husky init`, replace the `npm test` line it writes in .husky/pre-commit with your husky.hooks pre-commit command (or remove the file if there is none), move the other husky.hooks commands into .husky/<hook> files, remove husky.hooks from package.json and run `shipcraft init` again",
        );
    }
    let no_h = matches!(repo.path(".husky/_/h").symlink_metadata(), Err(e) if e.kind() == ErrorKind::NotFound);
    if dir == Some(".husky") && no_h && helper_is_husky(repo) {
        return husky(repo, local, true);
    }
    alien_plain(
        "this project's husky setup is neither husky 9 (core.hooksPath .husky/_ with .husky/_/h) nor husky 7 or 8 (core.hooksPath .husky with .husky/_/husky.sh)",
        "run `npx husky` (husky 9) or `npx husky install` (husky 7 or 8) and run `shipcraft init` again",
    )
}

/// 133.1: `.husky/_/husky.sh` is a regular file holding husky 7's and 8's re-run lines.
fn helper_is_husky(repo: &Repo) -> bool {
    let path = repo.path(HELPER);
    if !path.symlink_metadata().is_ok_and(|m| m.file_type().is_file()) {
        return false;
    }
    let Ok(bytes) = fs::read(&path) else { return false };
    let text = String::from_utf8_lossy(&bytes);
    let lines: Vec<&str> = text.split('\n').map(|l| l.trim_matches([' ', '\t'])).collect();
    lines.contains(&"sh -e \"$0\" \"$@\"") && lines.contains(&"exit $exitCode")
}

/// The plan of husky 9 (`seven` false: item 25.4) or of husky 7 and 8 (133.1).
fn husky(repo: &Repo, local: bool, seven: bool) -> Result<Tool> {
    if read(repo, ".husky/pre-commit")?.is_some_and(|t| runs_check(&t)) {
        return alien(".husky/pre-commit has an `shipcraft check`".into(), TWICE);
    }
    let (mut writes, mut missing, mut paths) = (Vec::new(), Vec::new(), Vec::new());
    for (file, plain) in HUSKY {
        let project = plain.replacen("shipcraft", LOCAL, 1);
        let line = if local { project.as_str() } else { plain };
        let Some(text) = read(repo, file)? else {
            let new = if seven { format!("#!/bin/sh\n{}\n\n{line}\n", HELPERS[0]) } else { format!("{line}\n") };
            writes.push((file.to_string(), None, new));
            continue;
        };
        if seven && !is_executable(&repo.path(file)) {
            missing.push(format!("{file} (not executable)"));
            paths.push(file);
        }
        let helper = if seven { Some(seven_checks(file, &text)?) } else { None };
        let commands = [words(plain), words(&project)];
        let calls: Vec<(usize, &str)> =
            text.lines().enumerate().filter(|(_, l)| shipcraft_words(&words(l)).is_some()).collect();
        if let Some((_, other)) = calls.iter().find(|(_, l)| !commands.contains(&strip_runner(&words(l)))) {
            return alien(
                format!("{file} already calls shipcraft another way ({})", other.trim()),
                &format!("keep only `{line}`"),
            );
        }
        let new = match helper {
            Some(helper) => {
                let lines: Vec<&str> = text.split('\n').collect();
                let first = (helper + 1..lines.len()).find(|&i| !skipped(lines[i]));
                if !calls.is_empty() {
                    if calls.len() > 1 || Some(calls[0].0) != first {
                        return alien_plain(
                            &format!("{file} does not call shipcraft right after sourcing {HELPER}"),
                            "put the shipcraft line right after the husky.sh line and run shipcraft init again",
                        );
                    }
                    continue;
                }
                let pieces: Vec<&str> = text.split_inclusive('\n').collect();
                let mut new = pieces[..=helper].concat();
                if !new.ends_with('\n') {
                    new.push('\n');
                }
                format!("{new}{line}\n{}", pieces[helper + 1..].concat())
            }
            None if !calls.is_empty() => continue,
            // 25.4: first, after the `#!`: at the end, an `exec` or an `exit 0` would skip it.
            None => match text.split_once('\n') {
                Some((first, rest)) if first.starts_with("#!") => format!("{first}\n{line}\n{rest}"),
                None if text.starts_with("#!") => format!("{text}\n{line}\n"),
                _ => format!("{line}\n{text}"),
            },
        };
        writes.push((file.to_string(), Some(text.clone()), new));
    }
    if seven {
        let install = if paths.is_empty() { String::new() } else { format!("chmod +x {}", paths.join(" ")) };
        return Ok(Tool { name: "husky", writes, missing, install, stageless: Vec::new(), exec_new: true });
    }
    let missing = ["commit-msg", "post-commit"]
        .iter()
        .map(|h| format!(".husky/_/{h}"))
        .filter(|l| !is_executable(&repo.path(l)))
        .collect();
    Ok(Tool { name: "husky", writes, missing, install: "npx husky".into(), stageless: Vec::new(), exec_new: false })
}

/// 133.1, in order: CR line endings, then the helper line; its index in `text.split('\n')`.
fn seven_checks(file: &str, text: &str) -> Result<usize> {
    if text.contains('\r') {
        return alien_plain(
            &format!("{file} has CR line endings, which sh reads as part of each line"),
            &format!("convert {file} to LF line endings and run shipcraft init again"),
        );
    }
    match helper_line(text) {
        Some(i) => Ok(i),
        None => alien_plain(
            &format!("{file} does not source {HELPER}, so a failing shipcraft command would not stop the hook"),
            "add . \"$(dirname \"$0\")/_/husky.sh\" as its first command and run shipcraft init again",
        ),
    }
}

/// A blank line or a comment line (its first non-blank character is `#`).
fn skipped(line: &str) -> bool {
    let t = line.trim_start_matches([' ', '\t']);
    t.is_empty() || t.starts_with('#')
}

/// 133.1: the index (in `text.split('\n')`) of the helper line: the first line
/// after the `#!` line that is not blank or a comment, when it is husky's.
pub(crate) fn helper_line(text: &str) -> Option<usize> {
    let lines: Vec<&str> = text.split('\n').collect();
    if !lines[0].starts_with("#!") {
        return None;
    }
    let i = (1..lines.len()).find(|&i| !skipped(lines[i]))?;
    let t = lines[i].trim_matches([' ', '\t']);
    let b = t.as_bytes();
    let cut = (1..b.len()).find(|&k| b[k] == b'#' && matches!(b[k - 1], b' ' | b'\t')).map_or(t, |k| &t[..k - 1]);
    HELPERS.contains(&cut.trim_end_matches([' ', '\t'])).then_some(i)
}

/// A line's words, split on spaces and tabs (133.2).
pub(crate) fn words(line: &str) -> Vec<&str> {
    line.split([' ', '\t']).filter(|w| !w.is_empty()).collect()
}

/// The words after the longest runner prefix, or all of them.
fn strip_runner<'a>(words: &[&'a str]) -> Vec<&'a str> {
    let prefix = RUNNERS.iter().find(|r| words.starts_with(r)).map_or(0, |r| r.len());
    words[prefix..].to_vec()
}

/// 133.2: a shipcraft line's words from `shipcraft` on, after one optional runner prefix.
pub(crate) fn shipcraft_words<'a>(words: &[&'a str]) -> Option<Vec<&'a str>> {
    let rest = strip_runner(words);
    matches!(rest.first(), Some(&("shipcraft" | LOCAL))).then_some(rest)
}

/// 133.2: a `.husky/pre-commit` line that runs `shipcraft check`, after an optional `exec` and runner.
fn runs_check(text: &str) -> bool {
    text.lines().any(|l| {
        let w = words(l);
        let w = w.strip_prefix(&["exec"]).unwrap_or(&w);
        shipcraft_words(w).is_some_and(|rest| rest.get(1) == Some(&"check"))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_helper_line() {
        assert_eq!(helper_line("#!/bin/sh\n. \"$(dirname \"$0\")/_/husky.sh\"\n"), Some(1));
        assert_eq!(helper_line("#!/bin/sh\n# c\n\n  . \"$(dirname -- \"$0\")/_/husky.sh\"\t# x\nnpm t\n"), Some(3));
        assert_eq!(helper_line("#!/bin/sh\n. \"$(dirname \"$0\")/_/husky.sh\""), Some(1));
        assert_eq!(helper_line(". \"$(dirname \"$0\")/_/husky.sh\"\n"), None);
        assert_eq!(helper_line("#!/bin/sh\nnpm t\n. \"$(dirname \"$0\")/_/husky.sh\"\n"), None);
        assert_eq!(helper_line("#!/bin/sh\n. \"$(dirname $0)/_/husky.sh\"\n"), None);
        assert_eq!(helper_line("#!/bin/sh\n. \"$(dirname \"$0\")/_/husky.sh\"#x\n"), None);
        assert_eq!(helper_line("#!/bin/sh\n"), None);
    }

    #[test]
    fn reads_runner_prefixes() {
        let sc = |l: &str| shipcraft_words(&words(l)).map(|w| w.join(" "));
        assert_eq!(sc("npx --no -- shipcraft close").as_deref(), Some("shipcraft close"));
        assert_eq!(sc("npx --no\tshipcraft  close").as_deref(), Some("shipcraft close"));
        assert_eq!(
            sc("pnpm exec -- ./node_modules/.bin/shipcraft close").as_deref(),
            Some("./node_modules/.bin/shipcraft close")
        );
        assert_eq!(sc("pnpm exec shipcraft close").as_deref(), Some("shipcraft close"));
        assert_eq!(sc("npx --no"), None);
        assert_eq!(sc("npx shipcraft close"), None);
        assert_eq!(sc("npx -- shipcraft close"), None);
        assert_eq!(sc("bunx shipcraft close"), None);
        assert_eq!(sc("yarn shipcraft close"), None);
        assert!(runs_check("exec npx --no -- shipcraft check\n"));
        assert!(runs_check("./node_modules/.bin/shipcraft check\n"));
        assert!(!runs_check("npx shipcraft check\n"));
    }

    fn repo_with(files: &[(&str, &str)]) -> (crate::git::TempDir, Repo) {
        let dir = crate::git::TempDir::new("shipcraft-test-item133").unwrap();
        for (file, text) in files {
            let path = dir.path().join(file);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(path, text).unwrap();
        }
        let repo = Repo::at_root(dir.path());
        (dir, repo)
    }

    const SH: &str = "#!/bin/sh\nif [ -z \"$husky_skip_init\" ]; then\n  sh -e \"$0\" \"$@\"\n  exitCode=\"$?\"\n  exit $exitCode\nfi\n";

    #[test]
    fn reads_the_helper_content() {
        let (_d, repo) = repo_with(&[(HELPER, SH)]);
        assert!(helper_is_husky(&repo));
        let (_d, repo) = repo_with(&[(HELPER, ":\n")]);
        assert!(!helper_is_husky(&repo));
        let (_d, repo) = repo_with(&[]);
        assert!(!helper_is_husky(&repo));
    }

    #[test]
    fn plans_husky_seven() {
        let hook = "#!/bin/sh\n. \"$(dirname \"$0\")/_/husky.sh\" # h\nnpm test\n";
        let (_d, repo) = repo_with(&[(HELPER, SH), (".husky/commit-msg", hook)]);
        let tool = husky(&repo, false, true).unwrap();
        assert_eq!(
            tool.writes[0].2,
            "#!/bin/sh\n. \"$(dirname \"$0\")/_/husky.sh\" # h\nshipcraft check --commit-msg \"$1\"\nnpm test\n"
        );
        assert_eq!(tool.writes[1].2, "#!/bin/sh\n. \"$(dirname \"$0\")/_/husky.sh\"\n\nshipcraft close\n");
        assert_eq!(tool.missing, [".husky/commit-msg (not executable)"]);
        assert_eq!(tool.install, "chmod +x .husky/commit-msg");
        let last = "#!/bin/sh\n. \"$(dirname \"$0\")/_/husky.sh\"";
        let (_d, repo) = repo_with(&[(".husky/post-commit", last)]);
        assert_eq!(husky(&repo, false, true).unwrap().writes[1].2, format!("{last}\nshipcraft close\n"));
        let kept = "#!/bin/sh\n. \"$(dirname \"$0\")/_/husky.sh\"\n\nnpx --no -- shipcraft close\nnpm t\n";
        let (_d, repo) = repo_with(&[(".husky/post-commit", kept)]);
        assert_eq!(husky(&repo, false, true).unwrap().writes.len(), 1);
        for bad in [
            "#!/bin/sh\r\n. \"$(dirname \"$0\")/_/husky.sh\"\r\n",
            "#!/bin/sh\nshipcraft close\n",
            "#!/bin/sh\n. \"$(dirname \"$0\")/_/husky.sh\"\nexit 0\nshipcraft close\n",
            "#!/bin/sh\nshipcraft close\n. \"$(dirname \"$0\")/_/husky.sh\"\nshipcraft close\n",
        ] {
            let (_d, repo) = repo_with(&[(".husky/post-commit", bad)]);
            assert!(husky(&repo, false, true).is_err(), "{bad:?}");
        }
    }
}
