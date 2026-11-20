//! Item 142: `export` reads Shipcraft's block out of the root `AGENTS.md` and
//! `CLAUDE.md` instead of resetting them, keeping the contribution's own edits.

use crate::export::Entry;
use crate::init::{marker_lines, written_blocks};
use crate::refusal::Result;

/// The two names point 1 reads the block out of, in the order of their lines.
pub(crate) const BLOCK_NAMES: [&str; 2] = ["AGENTS.md", "CLAUDE.md"];

/// What the exported tree holds at one of `BLOCK_NAMES` for a commit.
#[derive(Debug, PartialEq)]
pub(crate) enum Outcome {
    /// Item 135's rule: the fork point's entries at and under the name.
    Rule135,
    /// Item 135's rule because the markers are not one block Shipcraft writes (c).
    Unpaired,
    /// The commit's entries, unchanged.
    AsIs,
    /// No entry at or under the name.
    Absent,
    /// A blob of this content with the commit's mode.
    Blob { mode: String, content: Vec<u8> },
}

fn regular(entry: &Entry, name: &str) -> bool {
    entry.path == name.as_bytes() && entry.kind == "blob" && (entry.mode == "100644" || entry.mode == "100755")
}

/// Point 1 for `name`, with `commit` and `fork` the entries at and under it in
/// the commit and the fork point, and `read` a blob's bytes by object id.
pub(crate) fn outcome(
    name: &str,
    commit: &[&Entry],
    fork: &[&Entry],
    read: impl Fn(&str) -> Result<Vec<u8>>,
) -> Result<Outcome> {
    let same = commit.len() == fork.len()
        && commit.iter().zip(fork).all(|(c, f)| c.path == f.path && c.oid == f.oid && c.mode == f.mode);
    if same {
        return Ok(Outcome::AsIs);
    }
    let [entry] = commit else {
        return Ok(if commit.is_empty() { Outcome::Absent } else { Outcome::Rule135 });
    };
    let fork_blob = match fork {
        [] => None,
        [f] if regular(f, name) => Some(f),
        _ => return Ok(Outcome::Rule135),
    };
    if !regular(entry, name) {
        return Ok(Outcome::Rule135);
    }
    let fork_bytes = fork_blob.map(|f| read(&f.oid)).transpose()?;
    Ok(match strip(name, &read(&entry.oid)?, fork_bytes.as_deref()) {
        Strip::NoMarker => Outcome::AsIs,
        Strip::Other => Outcome::Unpaired,
        Strip::Removed(content) if content.is_empty() && fork_bytes.is_none() => Outcome::Absent,
        Strip::Removed(content) => Outcome::Blob { mode: entry.mode.clone(), content },
    })
}

#[derive(Debug, PartialEq)]
enum Strip {
    NoMarker,
    Removed(Vec<u8>),
    Other,
}

/// (a), (b) or (c) for a blob of `name`, with `fork` the fork point's blob at it.
fn strip(name: &str, bytes: &[u8], fork: Option<&[u8]>) -> Strip {
    let (from, to) = match marker_lines(bytes).as_slice() {
        [] => return Strip::NoMarker,
        [(true, from, _), (false, _, to)] => (*from, *to),
        _ => return Strip::Other,
    };
    if !written_blocks(name).iter().any(|b| b.as_bytes() == &bytes[from..to]) {
        return Strip::Other;
    }
    let (mut before, after) = (&bytes[..from], &bytes[to..]);
    if after.is_empty() {
        let k = match fork {
            Some(f) if !f.is_empty() => f.iter().rev().take_while(|b| **b == b'\n').count(),
            _ => 1,
        };
        while before.ends_with(b"\n") && before.iter().rev().take_while(|b| **b == b'\n').count() > k {
            before = &before[..before.len() - 1];
        }
    }
    Strip::Removed([before, after].concat())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn block() -> String {
        written_blocks("AGENTS.md")[0].clone()
    }

    fn removed(bytes: &[u8], fork: Option<&[u8]>) -> Vec<u8> {
        match strip("AGENTS.md", bytes, fork) {
            Strip::Removed(content) => content,
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn an_appended_block_comes_back_as_the_fork_point_has_it() {
        let b = block();
        for fork in [&b"# Up"[..], b"# Up\n", b"# Up\n\n"] {
            let sep = if fork.ends_with(b"\n\n") {
                ""
            } else if fork.ends_with(b"\n") {
                "\n"
            } else {
                "\n\n"
            };
            let file = [fork, sep.as_bytes(), b.as_bytes()].concat();
            assert_eq!(removed(&file, Some(fork)), fork);
        }
        assert_eq!(removed(b.as_bytes(), None), b"");
        assert_eq!(removed(format!("mine\n\n{b}").as_bytes(), None), b"mine\n");
        assert_eq!(
            removed(format!("# Up\n- new\n\n{b}after\n").as_bytes(), Some(b"# Up\n")),
            b"# Up\n- new\n\nafter\n"
        );
    }

    #[test]
    fn markers_that_are_not_a_written_block_are_never_guessed_at() {
        let b = block();
        assert_eq!(strip("AGENTS.md", b"# Up\n", None), Strip::NoMarker);
        assert_eq!(strip("AGENTS.md", b"<!-- shipcraft -->\n", None), Strip::Other);
        assert_eq!(strip("AGENTS.md", format!("{b}{b}").as_bytes(), None), Strip::Other);
        assert_eq!(strip("AGENTS.md", b"<!-- /shipcraft -->\n<!-- shipcraft -->\n", None), Strip::Other);
        assert_eq!(strip("AGENTS.md", b.replace('\n', "\r\n").as_bytes(), None), Strip::Other);
        assert_eq!(strip("AGENTS.md", b.replace("RED", "Red").as_bytes(), None), Strip::Other);
        assert_eq!(strip("CLAUDE.md", b.as_bytes(), None), Strip::Other);
        let claude = "<!-- shipcraft -->\nShipcraft workflow (required): @AGENTS.md\n<!-- /shipcraft -->\n";
        assert_eq!(strip("CLAUDE.md", format!("mine\n{claude}").as_bytes(), None), Strip::Removed(b"mine\n".to_vec()));
    }

    #[test]
    fn every_known_block_in_both_forms_is_read_out() {
        let blocks = written_blocks("AGENTS.md");
        assert!(blocks.iter().any(|b| b.contains("`npx -- shipcraft export --base")));
        assert!(blocks.iter().any(|b| b.contains("After a merge") && !b.contains("shipcraft export")));
        for b in &blocks {
            assert_eq!(removed(format!("x\n\n{b}").as_bytes(), Some(b"x\n")), b"x\n");
        }
    }

    fn entry(mode: &str, oid: &str, path: &str) -> Entry {
        let kind = if mode == "040000" { "tree" } else { "blob" };
        Entry { mode: mode.into(), kind: kind.into(), oid: oid.into(), path: path.as_bytes().to_vec() }
    }

    #[test]
    fn point_one_applies_only_to_regular_files() {
        let read =
            |oid: &str| Ok(if oid == "new" { format!("x\n\n{}", block()).into_bytes() } else { b"x\n".to_vec() });
        let (up, new) = (entry("100644", "up", "AGENTS.md"), entry("100755", "new", "AGENTS.md"));
        let link = entry("120000", "new", "AGENTS.md");
        let under = entry("100644", "up", "AGENTS.md/a.md");
        assert_eq!(outcome("AGENTS.md", &[&up], &[&up], read).unwrap(), Outcome::AsIs);
        assert_eq!(outcome("AGENTS.md", &[], &[&link], read).unwrap(), Outcome::Absent);
        assert_eq!(outcome("AGENTS.md", &[&link], &[&up], read).unwrap(), Outcome::Rule135);
        assert_eq!(outcome("AGENTS.md", &[&new], &[&under], read).unwrap(), Outcome::Rule135);
        assert_eq!(outcome("AGENTS.md", &[&under], &[], read).unwrap(), Outcome::Rule135);
        let blob = Outcome::Blob { mode: "100755".into(), content: b"x\n".to_vec() };
        assert_eq!(outcome("AGENTS.md", &[&new], &[&up], read).unwrap(), blob);
        assert_eq!(outcome("AGENTS.md", &[&up], &[], read).unwrap(), Outcome::AsIs);
    }
}
