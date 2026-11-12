//! Item 103: the size block at the end of the PR body, and the rest of a body
//! without it. Pure text functions: the body is split at `\n` only, a line's
//! one trailing `\r` is ignored when it is compared with a marker, and every
//! other character (U+2028, U+2029, a lone `\r`) is ordinary.

pub const START: &str = "<!-- shipcraft:size -->";
pub const END: &str = "<!-- /shipcraft:size -->";

/// The block's `Size:` line, without its `\n`.
pub fn size_line(n: u64, limit: u64, (added, removed): (u64, u64)) -> String {
    format!("Size: {n} product lines against a limit of {limit} (+{added} / -{removed}, counted as in the PR summary).")
}

/// The block's second line, only when `n` is above `limit`.
pub const ABOVE: &str = "Above the limit: if this change can ship in working slices, the first slice can be its own PR; if it cannot, a line here saying why helps the reviewer.";

/// The lines of the block between the markers: `Size:` and, above the limit, `Above the limit:`.
pub fn lines((added, removed): (u64, u64), limit: u64) -> Vec<String> {
    let n = added + removed;
    let mut lines = vec![size_line(n, limit, (added, removed))];
    if n > limit {
        lines.push(ABOVE.to_string());
    }
    lines
}

/// The whole block, each line ending in `\n`.
pub fn block(size: (u64, u64), limit: u64) -> String {
    let mut text = format!("{START}\n");
    for line in lines(size, limit) {
        text.push_str(&line);
        text.push('\n');
    }
    text.push_str(END);
    text.push('\n');
    text
}

fn is_marker(line: &str, marker: &str) -> bool {
    line.strip_suffix('\r').unwrap_or(line) == marker
}

/// The byte offset where the trailing block starts, if the body has one: the
/// body ends with a line that is exactly the end marker (then only spaces,
/// tabs, `\r` and `\n`), and the last earlier line that is exactly the start
/// marker opens it.
fn trailing_start(body: &str) -> Option<usize> {
    let trimmed = body.trim_end_matches([' ', '\t', '\r', '\n']);
    let end_line_at = trimmed.rfind('\n').map_or(0, |i| i + 1);
    if &trimmed[end_line_at..] != END {
        return None;
    }
    let mut start = None;
    let mut at = 0;
    for line in trimmed[..end_line_at].split_inclusive('\n') {
        if is_marker(line.strip_suffix('\n').unwrap_or(line), START) {
            start = Some(at);
        }
        at += line.len();
    }
    start
}

/// The rest of a body: the body itself without a trailing block; with one,
/// the text before its start line, less one `\n` when that text ends in
/// `\n\n` or is exactly `\n`.
pub fn rest(body: &str) -> &str {
    let Some(start) = trailing_start(body) else { return body };
    let before = &body[..start];
    if before.ends_with("\n\n") || before == "\n" {
        &before[..before.len() - 1]
    } else {
        before
    }
}

/// The new body from the base text: the block alone when the base's rest is
/// empty; else the rest, `\n` when it does not end in one, a blank line, the block.
pub fn new_body(base: &str, size: (u64, u64), limit: u64) -> String {
    let rest = rest(base);
    let block = block(size, limit);
    if rest.is_empty() {
        return block;
    }
    let mut body = rest.to_string();
    if !body.ends_with('\n') {
        body.push('\n');
    }
    body.push('\n');
    body.push_str(&block);
    body
}

#[cfg(test)]
mod tests {
    use super::*;

    const SMALL: (u64, u64) = (3, 2);

    fn blk() -> String {
        block(SMALL, 500)
    }

    #[test]
    fn block_below_and_above_the_limit() {
        assert_eq!(
            block((3, 2), 500),
            "<!-- shipcraft:size -->\nSize: 5 product lines against a limit of 500 (+3 / -2, counted as in the PR summary).\n<!-- /shipcraft:size -->\n"
        );
        let at = block((250, 250), 500);
        assert!(!at.contains("Above the limit"), "500 is not above 500");
        let above = block((300, 201), 500);
        assert_eq!(above.lines().nth(2).unwrap(), ABOVE);
        assert_eq!(above.lines().count(), 4);
    }

    #[test]
    fn no_block_is_the_whole_body() {
        assert_eq!(rest("Intent.\n"), "Intent.\n");
        assert_eq!(rest("Intent."), "Intent.");
        assert_eq!(rest(""), "");
    }

    #[test]
    fn trailing_block_is_removed_with_the_blank_line() {
        let body = format!("Intent.\n\n{}", blk());
        assert_eq!(rest(&body), "Intent.\n");
        assert_eq!(rest(&blk()), "");
        // Only one `\n` goes, and only from `\n\n` or a lone `\n`.
        assert_eq!(rest(&format!("Intent.\n{}", blk())), "Intent.\n");
        assert_eq!(rest(&format!("Intent.\n\n\n{}", blk())), "Intent.\n\n");
        assert_eq!(rest(&format!("\n{}", blk())), "");
        assert_eq!(rest(&format!("\n\n{}", blk())), "\n");
    }

    #[test]
    fn block_followed_by_trailing_whitespace() {
        let body = format!("Intent.\n\n{} \t\r\n\n  ", blk());
        assert_eq!(rest(&body), "Intent.\n");
        let no_newline = format!("Intent.\n\n{}", blk().trim_end());
        assert_eq!(rest(&no_newline), "Intent.\n");
        // Text after the end marker means there is no trailing block.
        let after = format!("Intent.\n\n{}more\n", blk());
        assert_eq!(rest(&after), after);
    }

    #[test]
    fn markers_in_the_middle_are_kept() {
        let body = format!("Before.\n{}After.\n", blk());
        assert_eq!(rest(&body), body);
        let fenced = format!("```\n{}```\n", blk());
        assert_eq!(rest(&fenced), fenced);
        // An author's block, then Shipcraft's: only the trailing one goes.
        let both = format!("A\n{}B\n\n{}", blk(), blk());
        assert_eq!(rest(&both), format!("A\n{}B\n", blk()));
    }

    #[test]
    fn unmatched_markers_are_kept() {
        let start_only = "Intent.\n<!-- shipcraft:size -->\nSize: 1\n";
        assert_eq!(rest(start_only), start_only);
        let end_only = "Intent.\n<!-- /shipcraft:size -->\n";
        assert_eq!(rest(end_only), end_only);
        // A marker with other text on its line is not a marker.
        let indented = "Intent.\n <!-- shipcraft:size -->\nx\n<!-- /shipcraft:size -->\n";
        assert_eq!(rest(indented), indented);
        let inline = "x <!-- shipcraft:size -->\n<!-- /shipcraft:size -->";
        assert_eq!(rest(inline), inline);
    }

    #[test]
    fn crlf_bodies() {
        let body = "Intent.\r\n\r\n<!-- shipcraft:size -->\r\nSize: 5\r\n<!-- /shipcraft:size -->\r\n";
        assert_eq!(rest(body), "Intent.\r\n\r\n");
        let body = "Intent.\n\n<!-- shipcraft:size -->\r\nSize: 5\r\n<!-- /shipcraft:size -->\r\n";
        assert_eq!(rest(body), "Intent.\n");
        // Two `\r` before `\n` on the start line is not a marker.
        let two = "Intent.\n<!-- shipcraft:size -->\r\r\n<!-- /shipcraft:size -->\n";
        assert_eq!(rest(two), two);
    }

    #[test]
    fn u2028_and_lone_cr_are_ordinary() {
        let sep = "Intent.\u{2028}<!-- shipcraft:size -->\nSize\n<!-- /shipcraft:size -->\n";
        assert_eq!(rest(sep), sep);
        let cr = "Intent.\r<!-- shipcraft:size -->\nSize\n<!-- /shipcraft:size -->\n";
        assert_eq!(rest(cr), cr);
        let body = format!("Intent.\u{2028}\u{2029}\n\n{}", blk());
        assert_eq!(rest(&body), "Intent.\u{2028}\u{2029}\n");
        assert_eq!(rest(&new_body("a\u{2028}b", SMALL, 500)), "a\u{2028}b\n");
    }

    #[test]
    fn empty_body_gets_the_block_alone() {
        assert_eq!(new_body("", SMALL, 500), blk());
        assert_eq!(new_body(&blk(), (9, 9), 500), block((9, 9), 500));
    }

    #[test]
    fn the_separator_is_reversible() {
        for base in ["X\n", "X\n\n", "\n", "\n\n", "a\nb\n", "X\r\n"] {
            let new = new_body(base, SMALL, 500);
            assert_eq!(rest(&new), base, "base {base:?}");
        }
        // A rest that does not end in `\n` gains one.
        assert_eq!(new_body("X", SMALL, 500), format!("X\n\n{}", blk()));
        assert_eq!(rest(&new_body("X", SMALL, 500)), "X\n");
        assert_eq!(new_body("X\n", SMALL, 500), format!("X\n\n{}", blk()));
    }

    #[test]
    fn applying_twice_gives_the_same_body() {
        for base in ["", "X", "X\n", "X\n\n", "\n", "X\r\n", "A\n<!-- shipcraft:size -->\n", "a\u{2028}"] {
            let once = new_body(base, SMALL, 500);
            assert_eq!(new_body(&once, SMALL, 500), once, "base {base:?}");
        }
        // A new count replaces the old block in place.
        let once = new_body("X\n", SMALL, 500);
        assert_eq!(new_body(&once, (400, 200), 500), new_body("X\n", (400, 200), 500));
    }

    #[test]
    fn the_key_of_x_equals_the_key_of_its_new_body() {
        let key = |title: &str, body: &str| [title.as_bytes(), b"\0", rest(body).as_bytes()].concat();
        let new = new_body("X\n", SMALL, 500);
        assert_eq!(key("T", "X\n"), key("T", &new));
        assert_eq!(key("T", ""), key("T", &new_body("", SMALL, 500)));
        assert_ne!(key("T", "X"), key("T", &new_body("X", SMALL, 500)));
    }
}
