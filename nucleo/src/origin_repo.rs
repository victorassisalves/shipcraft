//! Item 144: `pr` and `merge` name origin's repository to every `gh` call they
//! make after item 130's check, as `GH_REPO=HOST/OWNER/REPO` and `GH_HOST=HOST`.

use crate::git::{text, Repo};
use crate::refusal::Result;
use std::process::{Command, Stdio};

/// Reads origin's fetch URL and pins its repository (or none) for `gh::run`.
pub fn pin(repo: &Repo) -> Result<()> {
    let out = text(&repo.run(&["remote", "get-url", "origin"])?);
    let first = out.split('\n').next().unwrap_or_default();
    let url = first.strip_suffix('\r').unwrap_or(first);
    crate::gh::pin(parse(url, ssh_hostname));
    Ok(())
}

/// `<url>` as (`HOST/OWNER/REPO`, `HOST`); `translate` maps an SSH host to its
/// `hostname` as `ssh -G` reports it.
fn parse(url: &str, translate: impl Fn(&str) -> Option<String>) -> Option<(String, String)> {
    let (authority, path, ssh) = match url.split_once("://") {
        Some((scheme, rest)) => {
            let scheme = scheme.to_ascii_lowercase();
            if !["https", "http", "ssh", "git", "git+ssh"].contains(&scheme.as_str()) {
                return None;
            }
            let (authority, path) = rest.split_once('/')?;
            let authority = authority.rsplit_once('@').map_or(authority, |(_, h)| h);
            let authority = match authority.rsplit_once(':') {
                Some((host, port)) if !port.is_empty() && port.bytes().all(|b| b.is_ascii_digit()) => host,
                _ => authority,
            };
            (authority, path, scheme.ends_with("ssh"))
        }
        None => {
            let colon = url.find(':')?;
            if url.find('/').is_some_and(|slash| slash < colon) {
                return None;
            }
            let authority = &url[..colon];
            (authority.rsplit_once('@').map_or(authority, |(_, h)| h), &url[colon + 1..], true)
        }
    };
    if authority.is_empty() || authority.starts_with('[') {
        return None;
    }
    let path = path.trim_matches('/');
    let path = path.strip_suffix(".git").unwrap_or(path);
    let (owner, name) = path.split_once('/')?;
    if owner.is_empty() || name.is_empty() || name.contains('/') {
        return None;
    }
    let mut host =
        if ssh { translate(authority).unwrap_or_else(|| authority.to_string()) } else { authority.to_string() };
    if host.eq_ignore_ascii_case("ssh.github.com") {
        host = "github.com".to_string();
    }
    let host = host.to_lowercase();
    Some((format!("{host}/{owner}/{name}"), host))
}

/// `ssh -G <host>`'s first nonempty `hostname`, or None.
fn ssh_hostname(host: &str) -> Option<String> {
    let out = Command::new("ssh").args(["-G", host]).stdin(Stdio::null()).stderr(Stdio::null()).output().ok()?;
    if !out.status.success() {
        return None;
    }
    text(&out.stdout)
        .lines()
        .filter_map(|line| line.strip_prefix("hostname "))
        .map(str::trim)
        .find(|name| !name.is_empty())
        .map(str::to_string)
}

#[cfg(test)]
mod tests {
    use super::parse;

    fn read(url: &str) -> Option<(String, String)> {
        parse(url, |host| match host {
            "work-gh" => Some("github.com".to_string()),
            "via-ssh" => Some("ssh.github.com".to_string()),
            _ => None,
        })
    }

    fn named(url: &str, repo: &str, host: &str) {
        assert_eq!(read(url), Some((repo.to_string(), host.to_string())), "{url}");
    }

    #[test]
    fn scheme_forms_drop_userinfo_and_port() {
        named("https://user:p@ss@github.com:8443/acme/proj.git", "github.com/acme/proj", "github.com");
        named("http://ghe.example/acme/proj", "ghe.example/acme/proj", "ghe.example");
        named("git://github.com/acme/proj.git", "github.com/acme/proj", "github.com");
        named("ssh://git@github.example144:2222/acme/proj.git/", "github.example144/acme/proj", "github.example144");
        named("GIT+SSH://git@work-gh/acme/proj.git", "github.com/acme/proj", "github.com");
        named("HTTPS://GitHub.COM/Acme/Proj.git", "github.com/Acme/Proj", "github.com");
    }

    #[test]
    fn scp_forms_translate_the_host() {
        named("git@github.example144:acme/proj.git", "github.example144/acme/proj", "github.example144");
        named("github.com:acme/proj", "github.com/acme/proj", "github.com");
        named("git@work-gh:acme/proj.git", "github.com/acme/proj", "github.com");
        named("git@SSH.GitHub.com:acme/proj.git", "github.com/acme/proj", "github.com");
        named("git@via-ssh:acme/proj.git", "github.com/acme/proj", "github.com");
        named("ssh://git@ssh.github.com:443/acme/proj.git", "github.com/acme/proj", "github.com");
    }

    #[test]
    fn other_urls_name_no_repository() {
        for url in [
            "https://github.com/acme/proj/extra.git",
            "https://github.com/acme",
            "https://github.com/",
            "https://github.com",
            "/srv/git/proj.git",
            "./a:b/c",
            "file:///srv/acme/proj.git",
            "ftp://github.com/acme/proj.git",
            "ssh://git@[::1]:22/acme/proj.git",
            "git@[::1]:acme/proj.git",
            "https:///acme/proj.git",
            "https://user@/acme/proj.git",
            ":acme/proj.git",
            "git@:acme/proj.git",
            "",
        ] {
            assert_eq!(read(url), None, "{url}");
        }
    }

    #[test]
    fn the_scheme_form_does_not_translate_https_hosts() {
        named("https://work-gh/acme/proj.git", "work-gh/acme/proj", "work-gh");
    }
}
