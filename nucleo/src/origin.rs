//! Item 130: `pr` and `merge` refuse with no remote named origin, and `pr` checks
//! that GitHub says the `gh` account can write to each of origin's push URLs
//! before it fetches, pushes or sends anything.

use crate::gh;
use crate::git::{git_in, text, Repo};
use crate::refusal::{failed, refuse, Result};
use serde_json::Value;

const NO_ORIGIN_NEXT: &str = "the work stays local, and `shipcraft ci --base {base}` is your finish line; to open PRs, add a GitHub repository you can push to: git remote add origin <url>";

/// `pr`'s check (points 1 and 2): no output when origin passes.
pub fn check_pr(repo: &Repo) -> Result<()> {
    let Some(urls) = push_urls(repo)? else {
        return refuse(
            "no-origin",
            "this repository has no remote named origin, so shipcraft pr has nowhere to open a PR",
            "pr pushes the branch to origin and opens the PR on GitHub; nothing was fetched, pushed or sent",
            NO_ORIGIN_NEXT.replace("{base}", &local_base(repo)),
        );
    };
    let urls = split_urls(&urls);
    if urls.is_empty() {
        return unverified(repo, "origin has no push URL");
    }
    for url in &urls {
        let url = without_userinfo(url);
        match decide(gh::run(repo, &["repo", "view", &url, "--json", "nameWithOwner,viewerPermission"])) {
            Answer::Pass => {}
            Answer::NotWritable { name, permission } => {
                return refuse(
                    "origin-not-writable",
                    format!(
                        "origin is {}, where your GitHub permission is {}, so shipcraft pr cannot push to it",
                        one_line(&name),
                        one_line(&permission)
                    ),
                    "pr pushes the branch to origin before anything else, and a branch pushed to a repository that is not yours fails or lands in someone else's project; nothing was fetched, pushed or sent",
                    format!(
                        "point origin's push URL at a GitHub repository you can push to, such as your fork (git remote set-url origin <url>; when git remote -v shows other push URLs, git remote set-url --push origin <url>), or keep the work local: `shipcraft ci --base {base}` is your finish line; for a project that does not use Shipcraft, `shipcraft export --base {base} <new branch>` first makes a branch without Shipcraft's files",
                        base = pr_base(repo)
                    ),
                );
            }
            Answer::Unverified(reason) => return unverified(repo, &reason),
        }
    }
    Ok(())
}

/// `merge`'s check (point 1 only).
pub fn check_merge(repo: &Repo) -> Result<()> {
    if push_urls(repo)?.is_some() {
        return Ok(());
    }
    refuse(
        "no-origin",
        "this repository has no remote named origin, so shipcraft merge has no PR to merge",
        "merge reads the PR and its statuses on GitHub through origin; nothing was fetched or sent",
        NO_ORIGIN_NEXT.replace("{base}", &local_base(repo)),
    )
}

fn unverified(repo: &Repo, reason: &str) -> Result<()> {
    refuse(
        "origin-unverified",
        format!("shipcraft pr could not confirm that you can push to origin: {}", one_line(reason)),
        "pr pushes only to a repository GitHub says you can write to, and every later step needs gh too; nothing was fetched, pushed or sent",
        format!(
            "check that origin is a GitHub repository (git remote get-url origin) and that gh is logged in (gh auth status), then run shipcraft pr again; or keep the work local: `shipcraft ci --base {}` is your finish line",
            pr_base(repo)
        ),
    )
}

/// `git remote get-url --push --all origin`: its stdout, or None when git exits 2
/// (no such remote). Any other nonzero exit, or a signal, is a failure.
fn push_urls(repo: &Repo) -> Result<Option<Vec<u8>>> {
    let args = ["remote", "get-url", "--push", "--all", "origin"];
    let out = git_in(repo.root(), &args)?;
    match out.status.code() {
        Some(0) => Ok(Some(out.stdout)),
        Some(2) => Ok(None),
        _ => Err(failed(format!("`git {}` failed: {}", args.join(" "), text(&out.stderr).trim()))),
    }
}

/// Point 1's base: `main`, else `master`, else `<base branch>`.
fn local_base(repo: &Repo) -> String {
    let exists =
        |b: &str| repo.try_text(&["rev-parse", "-q", "--verify", &format!("refs/heads/{b}^{{commit}}")]).is_some();
    ["main", "master"].into_iter().find(|b| exists(b)).unwrap_or("<base branch>").to_string()
}

/// Point 2's base: the base `pr` uses when origin/HEAD resolves, else point 1's.
fn pr_base(repo: &Repo) -> String {
    match repo.try_text(&["symbolic-ref", "-q", "--short", "refs/remotes/origin/HEAD"]) {
        Some(_) => repo.default_branch(),
        None => local_base(repo),
    }
}

/// The push URLs: lines split on `\n`, a trailing `\r` removed, empty lines dropped.
fn split_urls(out: &[u8]) -> Vec<String> {
    String::from_utf8_lossy(out)
        .split('\n')
        .map(|l| l.strip_suffix('\r').unwrap_or(l))
        .filter(|l| !l.is_empty())
        .map(str::to_string)
        .collect()
}

/// `<scheme>://<userinfo>@<rest>` loses its `<userinfo>@` (up to the last `@`
/// before the first `/` after `://`); any other URL is returned as it is.
fn without_userinfo(url: &str) -> String {
    let Some(at) = url.find("://") else { return url.to_string() };
    let (head, rest) = url.split_at(at + 3);
    let authority = &rest[..rest.find('/').unwrap_or(rest.len())];
    match authority.rfind('@') {
        Some(i) => format!("{head}{}", &rest[i + 1..]),
        None => url.to_string(),
    }
}

#[derive(Debug, PartialEq)]
enum Answer {
    Pass,
    NotWritable { name: String, permission: String },
    Unverified(String),
}

/// What one `gh repo view` answer decides.
fn decide(answer: std::result::Result<String, String>) -> Answer {
    let out = match answer {
        Ok(out) => out,
        Err(e) => return Answer::Unverified(first_line(&e)),
    };
    let missing = || Answer::Unverified("gh did not return your permission on origin".to_string());
    let Ok(Value::Object(map)) = serde_json::from_str::<Value>(&out) else { return missing() };
    let permission = match map.get("viewerPermission") {
        Some(Value::String(p)) if matches!(p.as_str(), "ADMIN" | "MAINTAIN" | "WRITE") => return Answer::Pass,
        Some(Value::String(p)) if !p.is_empty() => p.clone(),
        Some(Value::String(_)) | Some(Value::Null) => "none".to_string(),
        _ => return missing(),
    };
    let name = match map.get("nameWithOwner") {
        Some(Value::String(n)) if !n.is_empty() => n.clone(),
        _ => "a GitHub repository".to_string(),
    };
    Answer::NotWritable { name, permission }
}

/// The first nonempty line of `gh::run`'s error, trimmed.
fn first_line(error: &str) -> String {
    error
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .map_or_else(|| "gh failed with no message".to_string(), str::to_string)
}

/// Each control character becomes one space, so a refusal stays three lines.
fn one_line(value: &str) -> String {
    value.chars().map(|c| if c.is_control() { ' ' } else { c }).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::git::TempDir;
    use std::path::Path;
    use std::process::Command;

    fn git(dir: &Path, args: &[&str]) {
        let out = Command::new("git")
            .arg("-C")
            .arg(dir)
            .args(args)
            .env("GIT_CONFIG_GLOBAL", "/dev/null")
            .env("GIT_CONFIG_NOSYSTEM", "1")
            .env("GIT_AUTHOR_NAME", "t")
            .env("GIT_AUTHOR_EMAIL", "t@example.invalid")
            .env("GIT_COMMITTER_NAME", "t")
            .env("GIT_COMMITTER_EMAIL", "t@example.invalid")
            .output()
            .unwrap();
        assert!(out.status.success(), "git {args:?}: {}", text(&out.stderr));
    }

    fn ok(json: &str) -> Answer {
        decide(Ok(json.to_string()))
    }

    fn not_writable(name: &str, permission: &str) -> Answer {
        Answer::NotWritable { name: name.to_string(), permission: permission.to_string() }
    }

    #[test]
    fn userinfo_is_removed_only_after_a_scheme() {
        assert_eq!(without_userinfo("https://user:secret@github.com/o/r.git"), "https://github.com/o/r.git");
        assert_eq!(without_userinfo("ssh://git@github.com/o/r.git"), "ssh://github.com/o/r.git");
        assert_eq!(without_userinfo("https://a@b@github.com/o/r"), "https://github.com/o/r");
        assert_eq!(without_userinfo("https://github.com/o/r@v1"), "https://github.com/o/r@v1");
        assert_eq!(without_userinfo("https://github.com"), "https://github.com");
        assert_eq!(without_userinfo("https://tok@github.com"), "https://github.com");
        assert_eq!(without_userinfo("git@github.com:o/r.git"), "git@github.com:o/r.git");
        assert_eq!(without_userinfo("/srv/bare.git"), "/srv/bare.git");
    }

    #[test]
    fn urls_split_on_newlines_and_keep_everything_else() {
        assert_eq!(split_urls(b"a\nb\r\n\n c \n"), vec!["a", "b", " c "]);
        assert_eq!(split_urls(b""), Vec::<String>::new());
        assert_eq!(split_urls(b"\r\n"), Vec::<String>::new());
        assert_eq!(split_urls(b"x\xffy\n"), vec!["x\u{fffd}y"]);
    }

    #[test]
    fn write_maintain_and_admin_pass() {
        for p in ["ADMIN", "MAINTAIN", "WRITE"] {
            assert_eq!(ok(&format!(r#"{{"nameWithOwner":"o/r","viewerPermission":"{p}"}}"#)), Answer::Pass);
        }
        // A duplicate key: the last value counts.
        assert_eq!(ok(r#"{"viewerPermission":"READ","viewerPermission":"WRITE"}"#), Answer::Pass);
    }

    #[test]
    fn other_permissions_are_not_writable() {
        assert_eq!(ok(r#"{"nameWithOwner":"o/r","viewerPermission":"READ"}"#), not_writable("o/r", "READ"));
        assert_eq!(ok(r#"{"nameWithOwner":"o/r","viewerPermission":"TRIAGE"}"#), not_writable("o/r", "TRIAGE"));
        assert_eq!(ok(r#"{"nameWithOwner":"o/r","viewerPermission":"write"}"#), not_writable("o/r", "write"));
        assert_eq!(ok(r#"{"nameWithOwner":"o/r","viewerPermission":""}"#), not_writable("o/r", "none"));
        assert_eq!(ok(r#"{"nameWithOwner":"o/r","viewerPermission":null}"#), not_writable("o/r", "none"));
        let generic = "a GitHub repository";
        assert_eq!(ok(r#"{"viewerPermission":"READ"}"#), not_writable(generic, "READ"));
        assert_eq!(ok(r#"{"nameWithOwner":"","viewerPermission":"READ"}"#), not_writable(generic, "READ"));
        assert_eq!(ok(r#"{"nameWithOwner":7,"viewerPermission":"READ"}"#), not_writable(generic, "READ"));
    }

    #[test]
    fn anything_else_is_unverified() {
        let missing = Answer::Unverified("gh did not return your permission on origin".to_string());
        for out in ["", "not json", "[]", "\"WRITE\"", "{}", r#"{"viewerPermission":1}"#, r#"{"viewerPermission":{}}"#]
        {
            assert_eq!(ok(out), missing, "{out:?}");
        }
        let err = |e: &str| decide(Err(e.to_string()));
        assert_eq!(err("HTTP 404: Not Found\nmore"), Answer::Unverified("HTTP 404: Not Found".to_string()));
        assert_eq!(err("\n  \n  boom  \nx"), Answer::Unverified("boom".to_string()));
        assert_eq!(err(""), Answer::Unverified("gh failed with no message".to_string()));
        assert_eq!(err(" \n "), Answer::Unverified("gh failed with no message".to_string()));
    }

    #[test]
    fn control_characters_become_spaces() {
        assert_eq!(one_line("a\tb\u{1b}c\u{7f}d\u{85}e"), "a b c d e");
        assert_eq!(one_line("o/r"), "o/r");
    }

    #[test]
    fn no_origin_is_exit_2_and_the_local_base_needs_a_branch() {
        let dir = TempDir::new("shipcraft-test-item130").unwrap();
        git(dir.path(), &["init", "-q", "-b", "trunk"]);
        let repo = Repo::at_root(dir.path());
        git(dir.path(), &["commit", "-q", "--allow-empty", "-m", "first"]);
        assert_eq!(push_urls(&repo).unwrap(), None);
        // A tag named main is not a branch.
        git(dir.path(), &["tag", "main"]);
        assert_eq!(local_base(&repo), "<base branch>");
        git(dir.path(), &["branch", "master"]);
        assert_eq!(local_base(&repo), "master");
        git(dir.path(), &["branch", "main"]);
        assert_eq!(local_base(&repo), "main");
        assert_eq!(pr_base(&repo), "main");
        git(dir.path(), &["remote", "add", "origin", "https://example.invalid/r.git"]);
        git(dir.path(), &["config", "--add", "remote.origin.pushurl", "/a"]);
        git(dir.path(), &["config", "--add", "remote.origin.pushurl", "/b"]);
        assert_eq!(split_urls(&push_urls(&repo).unwrap().unwrap()), vec!["/a", "/b"]);
    }
}
