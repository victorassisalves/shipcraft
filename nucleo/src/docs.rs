//! Item 40: a PR that changes only docs (a `*.md` at the root, anything under
//! the top-level `docs/`) skips the build, the `check` and the suites in
//! `shipcraft ci --pr`; the history is still checked. The rule is fixed: there
//! is no config.

use crate::config::{Config, CONFIG_FILE};
use crate::git::{Repo, Snapshot};
use crate::init::lefthook_source;
use crate::init_tool::{HUSKY, PRE_COMMIT_CONFIG};
use crate::lock::{lock_files, Lock};

/// Whether every path from the merge-base of `base` and `head` to `head` is
/// a plain docs file that nothing protects. Any doubt (no merge-base, a diff
/// that does not read, no path) is not docs only, and neither is a head with
/// an open lock.
pub fn docs_only(repo: &Repo, config: &Config, base: &str, head: &str) -> bool {
    let Some(merge_base) = repo.try_text(&["merge-base", base, head]) else { return false };
    let Ok(raw) = repo.run(&["diff", "-z", "--raw", "--no-renames", &merge_base, head]) else { return false };
    let raw = String::from_utf8_lossy(&raw);
    let mut fields = raw.split('\0').filter(|f| !f.is_empty());
    let mut any = false;
    while let Some(meta) = fields.next() {
        let Some(path) = fields.next() else { return false };
        if !plain(meta) || !doc(path) || protected(config, path) {
            return false;
        }
        any = true;
    }
    any && !open_lock(repo, head)
}

/// A raw diff entry (`:<old mode> <new mode> <sha> <sha> <status>`) of a
/// regular file that kept its mode: no link, submodule, mode or type change.
fn plain(meta: &str) -> bool {
    let parts: Vec<&str> = meta.trim_start_matches(':').split(' ').collect();
    let regular = |mode: &str| ["000000", "100644", "100755"].contains(&mode);
    match parts.as_slice() {
        [old, new, _, _, status] => {
            regular(old)
                && regular(new)
                && (old == new || *old == "000000" || *new == "000000")
                && ["A", "D", "M"].contains(status)
        }
        _ => false,
    }
}

/// A `*.md` at the root (no slash in the path), or anything under the top-level `docs/`.
fn doc(path: &str) -> bool {
    (!path.contains('/') && path.ends_with(".md")) || path.starts_with("docs/")
}

/// The test and support files of any suite, `.shipcraft.toml`, `.shipcraft/` and the
/// lefthook's sources, at the root or in `.config/` (item 15a.2).
fn protected(config: &Config, path: &str) -> bool {
    let name = path.strip_prefix(".config/").unwrap_or(path).to_ascii_lowercase();
    config.is_test_file(path)
        || path == CONFIG_FILE
        || path.starts_with(".shipcraft/")
        || (!name.contains('/') && lefthook_source(&name))
        || path == PRE_COMMIT_CONFIG
        || HUSKY.iter().any(|(f, _)| path == *f)
}

fn open_lock(repo: &Repo, head: &str) -> bool {
    match lock_files(repo, &Snapshot::Commit(head.to_string())) {
        Ok(locks) => locks.values().any(|bytes| Lock::parse(bytes).is_none_or(|lock| lock.is_open())),
        Err(_) => true,
    }
}

#[cfg(test)]
mod tests {
    use super::{doc, plain};

    #[test]
    fn docs_are_root_md_or_top_level_docs() {
        assert!(doc("README.md"));
        assert!(doc("docs/table.csv"));
        assert!(doc("docs/a/b.md"));
        assert!(!doc("src/brief.md"));
        assert!(!doc("pkg/docs/notes.md"));
        assert!(!doc("README.txt"));
        assert!(!doc("docs"));
    }

    #[test]
    fn plain_refuses_links_and_mode_changes() {
        let z = "0000000000000000000000000000000000000000";
        assert!(plain(&format!(":100644 100644 {z} {z} M")));
        assert!(plain(&format!(":000000 100644 {z} {z} A")));
        assert!(!plain(&format!(":000000 120000 {z} {z} A")));
        assert!(!plain(&format!(":100644 100755 {z} {z} M")));
        assert!(!plain(&format!(":100644 100644 {z} {z} T")));
    }
}
