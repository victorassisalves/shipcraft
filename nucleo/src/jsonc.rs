//! JSONC, as `tsc` reads a `tsconfig.json`: comments, a trailing comma, a
//! UTF-8 BOM and any line ending or space it takes, Unicode ones too (item 16b).

use serde_json::Value;

pub fn parse(text: &str) -> Option<Value> {
    serde_json::from_str(&plain_json(text.strip_prefix('\u{feff}').unwrap_or(text))?).ok()
}

/// The text without comments (each one becomes a space), with every space
/// outside strings as an ASCII space, and without a comma right before a `}`
/// or a `]`; strings pass as they are. None when a block comment does not
/// close: `tsc` does not read that (an open string or text after the value
/// fail in the JSON parser, as in `tsc`).
fn plain_json(text: &str) -> Option<String> {
    let mut out = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '"' => {
                out.push(c);
                while let Some(s) = chars.next() {
                    out.push(s);
                    match s {
                        '\\' => out.extend(chars.next()),
                        '"' => break,
                        _ => {}
                    }
                }
            }
            '/' if chars.peek() == Some(&'/') => {
                while chars.next_if(|&n| !matches!(n, '\n' | '\r' | '\u{2028}' | '\u{2029}')).is_some() {}
                out.push(' ');
            }
            '/' if chars.peek() == Some(&'*') => {
                chars.next();
                let mut last = ' ';
                chars.by_ref().find(|&n| std::mem::replace(&mut last, n) == '*' && n == '/')?;
                out.push(' ');
            }
            '}' | ']' => {
                let kept = out.trim_end().len();
                // Only a trailing comma goes: one right after `[`, `{` or
                // another comma stays, and the JSON parser refuses it, as `tsc` does.
                if out[..kept].ends_with(',') && !out[..kept - 1].trim_end().ends_with(['[', '{', ',']) {
                    out.truncate(kept - 1);
                }
                out.push(c);
            }
            // The scanner of `tsc` also skips the zero-width space and the BOM.
            c if c.is_whitespace() || c == '\u{200b}' || c == '\u{feff}' => out.push(' '),
            _ => out.push(c),
        }
    }
    Some(out)
}
