//! Which tags are releases (items 99, 105).

use crate::config::{self, CONFIG_FILE};
use crate::lock;
use std::fs;
use std::path::Path;

/// Item 99: which tags are releases, from the `[report]` table alone.
pub(super) enum Selection {
    /// Item 76's `vX.Y.Z` tags: no key, or a file this reader does not read.
    Default,
    /// A valid `release_tags`.
    Pattern(String),
    /// An invalid `[report]`: the problem, and no git evidence.
    Invalid(String),
}

impl Selection {
    /// `<root>/.shipcraft.toml` from the working tree; never refuses.
    pub(super) fn read(root: &Path) -> Selection {
        let path = root.join(CONFIG_FILE);
        if !fs::metadata(&path).is_ok_and(|m| m.is_file()) {
            return Selection::Default;
        }
        let Some(text) = fs::read(&path).ok().and_then(|b| String::from_utf8(b).ok()) else {
            return Selection::Default;
        };
        let Ok(table) = text.parse::<toml::Table>() else { return Selection::Default };
        match config::report_release_tags(&table) {
            Ok(None) => Selection::Default,
            Ok(Some(pattern)) => Selection::Pattern(pattern),
            Err(problem) => Selection::Invalid(problem),
        }
    }

    /// Whether a tag name is of the releases' grammar.
    pub(super) fn names(&self, tag: &str) -> bool {
        match self {
            Selection::Pattern(pattern) => matches(pattern.as_bytes(), tag.as_bytes()),
            _ => lock::valid_tag(tag),
        }
    }

    /// Item 105: None when `tag` is a release name of this selection, else
    /// the selection as `red`'s refusal names it.
    pub(super) fn release_name_problem(&self, tag: &str) -> Option<String> {
        match self {
            Selection::Invalid(problem) => Some(format!("invalid: {}", config::report_invalid(problem))),
            Selection::Pattern(pattern) => (!self.names(tag)).then(|| pattern.clone()),
            Selection::Default => (!self.names(tag)).then(|| "vX.Y.Z".to_string()),
        }
    }

    pub(super) fn pattern(&self) -> Option<&str> {
        match self {
            Selection::Pattern(pattern) => Some(pattern),
            _ => None,
        }
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
