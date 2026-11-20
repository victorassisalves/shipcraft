//! Which tags are releases (items 99, 105, 137), and what a deploy is (item 124).

use super::git::Git;
use crate::config::{self, Deploy, CONFIG_FILE};
use crate::lock;
use std::fs;
use std::path::{Path, PathBuf};

/// Why `red --fixes-release <tag>` refuses a name (items 105, 137).
pub enum NotRelease {
    /// Item 105: not a release name of the selection, shown as this.
    Selection(String),
    /// Item 137: a bare name the clone holds no tag of (default reading).
    NotInClone,
}

/// Item 99: which tags are releases, from the `[report]` table alone, with
/// item 124's valid `deploy` key when set.
pub(super) enum Selection {
    /// Item 76's `vX.Y.Z` tags and item 137's bare `X.Y.Z` tags: no key, or a
    /// file this reader does not read.
    Default(Option<Deploy>),
    /// A valid `release_tags`.
    Pattern(String, Option<Deploy>),
    /// An invalid `[report]`: the problem, and no git evidence.
    Invalid(String),
}

impl Selection {
    /// `<root>/.shipcraft.toml` from the working tree; never refuses.
    pub(super) fn read(root: &Path) -> Selection {
        let path = root.join(CONFIG_FILE);
        if !fs::metadata(&path).is_ok_and(|m| m.is_file()) {
            return Selection::Default(None);
        }
        let Some(text) = fs::read(&path).ok().and_then(|b| String::from_utf8(b).ok()) else {
            return Selection::Default(None);
        };
        let Ok(table) = text.parse::<toml::Table>() else { return Selection::Default(None) };
        // A valid `release_tags` holds a valid `deploy` (checked last).
        let deploy = config::report_deploy(&table).ok().flatten();
        match config::report_release_tags(&table) {
            Ok(None) => Selection::Default(deploy),
            Ok(Some(pattern)) => Selection::Pattern(pattern, deploy),
            Err(problem) => Selection::Invalid(problem),
        }
    }

    /// Whether a tag name is of the releases' grammar.
    pub(super) fn names(&self, tag: &str) -> bool {
        match self {
            Selection::Pattern(pattern, _) => matches(pattern.as_bytes(), tag.as_bytes()),
            _ => lock::valid_tag(tag) || bare(tag),
        }
    }

    /// Item 105: None when `tag` is a release name of this selection, else
    /// the selection as `red`'s refusal names it. Under the default reading,
    /// only `vX.Y.Z` here: a bare name is item 137's tag read (`in_clone`).
    pub(super) fn release_name_problem(&self, tag: &str) -> Option<String> {
        match self {
            Selection::Invalid(problem) => Some(format!("invalid: {}", config::report_invalid(problem))),
            Selection::Pattern(pattern, _) => (!self.names(tag)).then(|| pattern.clone()),
            Selection::Default(_) => (!lock::valid_tag(tag)).then(|| "vX.Y.Z".to_string()),
        }
    }

    pub(super) fn pattern(&self) -> Option<&str> {
        match self {
            Selection::Pattern(pattern, _) => Some(pattern),
            _ => None,
        }
    }

    /// Item 124: the valid `[report] deploy`, None when absent or invalid.
    pub(super) fn deploy(&self) -> Option<Deploy> {
        match self {
            Selection::Default(deploy) | Selection::Pattern(_, deploy) => *deploy,
            Selection::Invalid(_) => None,
        }
    }
}

/// Item 137: item 75's tag syntax without the leading `v`: three
/// dot-separated decimal numbers, no leading zeros, any number of digits.
pub(super) fn bare(tag: &str) -> bool {
    !tag.starts_with('v') && lock::valid_tag(&format!("v{tag}"))
}

/// Item 137: whether the clone at `root` holds a tag named `tag`, from one
/// `for-each-ref refs/tags` through `report`'s scrubbed `Git`. The output is
/// read only on exit 0 when empty or ending with LF; its LF-split lines are
/// compared as bytes. No root, or any failure, holds no tag.
pub(super) fn in_clone(root: Option<PathBuf>, tag: &str) -> bool {
    let Some(root) = root else { return false };
    let list = ["for-each-ref", "refs/tags", "--format=%(refname:strip=2)"];
    match (Git { root }).call(&list) {
        Ok((Some(0), out)) if out.is_empty() || out.ends_with(b"\n") => {
            out.split(|b| *b == b'\n').any(|line| line == tag.as_bytes())
        }
        _ => false,
    }
}

/// Item 99: `*` matches any run of bytes, `/` and the empty run included;
/// every other byte matches itself; the whole name must match.
pub(super) fn matches(pattern: &[u8], name: &[u8]) -> bool {
    let (mut p, mut n) = (0, 0);
    let mut star: Option<(usize, usize)> = None;
    while n < name.len() {
        if p < pattern.len() && pattern[p] == b'*' {
            star = Some((p, n));
            p += 1;
        } else if p < pattern.len() && pattern[p] == name[n] {
            p += 1;
            n += 1;
        } else if let Some((sp, sn)) = star {
            p = sp + 1;
            n = sn + 1;
            star = Some((sp, sn + 1));
        } else {
            return false;
        }
    }
    pattern[p..].iter().all(|b| *b == b'*')
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::process::Command;

    #[test]
    fn the_bare_syntax_is_item_75s_without_the_v() {
        for tag in ["0.164.0", "10.0.12", "0.0.0", "123456789012345678901.0.1"] {
            assert!(bare(tag), "{tag}");
        }
        for tag in ["1.2", "01.2.3", "1.2.3rc1", "1.2.3-rc.1", "v1.2.3", "vv1.2.3", "1.2.3.4", "", "1..3", " 1.2.3"] {
            assert!(!bare(tag), "{tag}");
        }
    }

    #[test]
    fn the_default_reading_names_both_forms_and_red_checks_only_v() {
        let default = Selection::Default(None);
        assert!(default.names("v1.2.3") && default.names("1.2.3"));
        assert!(!default.names("1.2") && !default.names("rel/1.2.3"));
        assert_eq!(default.release_name_problem("1.2.3").as_deref(), Some("vX.Y.Z"));
        let pattern = Selection::Pattern("v*".into(), None);
        assert!(!pattern.names("1.2.3"));
    }

    #[test]
    fn the_tag_read_compares_whole_lines_as_bytes() {
        let dir = std::env::temp_dir().join(format!("item137-tags-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let git = |args: &[&str]| {
            let mut command = Command::new("git");
            command.arg("-C").arg(&dir).args(["-c", "core.hooksPath=/dev/null"]).args(args);
            for var in super::super::REPOSITORY_VARS {
                command.env_remove(var);
            }
            let ok = command.output().unwrap().status.success();
            assert!(ok, "{args:?}");
        };
        git(&["init", "-q"]);
        assert!(!in_clone(Some(dir.clone()), "1.2.3"));
        git(&["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "c"]);
        for tag in ["1.2.30", "rel/1.2.3", "v1.2.3"] {
            git(&["tag", tag]);
        }
        assert!(!in_clone(Some(dir.clone()), "1.2.3"));
        git(&["tag", "1.2.3"]);
        assert!(in_clone(Some(dir.clone()), "1.2.3"));
        assert!(!in_clone(Some(dir.clone()), "1.2.4"));
        assert!(!in_clone(None, "1.2.3"));
        let _ = fs::remove_dir_all(&dir);
    }
}
