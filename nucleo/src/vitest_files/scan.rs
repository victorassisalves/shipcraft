//! Item 132, the scan: a config module read as JavaScript text, for its setup
//! keys, its root key and its imports, in text order.

/// One token outside comments and whitespace.
#[derive(Debug, PartialEq)]
enum Tok<'a> {
    /// A run of `A`-`Z`, `a`-`z`, `0`-`9`, `_`, `$`.
    Word(&'a str),
    /// A string's content, and whether it is a literal.
    Str(&'a str, bool),
    Punct(u8),
}

/// What the scan found, in text order.
#[derive(Debug, PartialEq)]
pub enum Event {
    /// A literal of a read setup key.
    Setup(String),
    /// Item 140: a read root key of a Jest module, its literal or None for
    /// `import.meta.dirname` and `__dirname`.
    Root(Option<String>),
    /// The literal of `from`, `import`, `import(` or `require(`.
    Import(String),
    /// Why the module is unreadable.
    Bad(String),
}

/// A runner's keys: its setup keys, its root key, and whether a root key's
/// literal is read (Jest's `rootDir`) or refused unless it names the folder.
pub struct Keys {
    pub setup: &'static [&'static str],
    pub root: &'static str,
    pub jest: bool,
}

pub const VITEST: Keys = Keys { setup: &["setupFiles", "globalSetup"], root: "root", jest: false };
pub const JEST: Keys =
    Keys { setup: &["setupFiles", "setupFilesAfterEnv", "globalSetup", "globalTeardown"], root: "rootDir", jest: true };

fn ident(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_' || b == b'$'
}

/// JavaScript's WhiteSpace (tab, VT, FF, space, U+00A0, U+FEFF, Unicode Zs).
fn js_space(c: char) -> bool {
    matches!(c, '\t' | '\u{0B}' | '\u{0C}' | ' ' | '\u{A0}' | '\u{FEFF}' | '\u{1680}' | '\u{2000}'..='\u{200A}')
        || matches!(c, '\u{202F}' | '\u{205F}' | '\u{3000}')
}

/// JavaScript's LineTerminators (LF, CR, U+2028, U+2029).
fn js_line_end(c: char) -> bool {
    matches!(c, '\n' | '\r' | '\u{2028}' | '\u{2029}')
}

/// The char at byte `i`, a char boundary.
fn char_at(text: &str, i: usize) -> char {
    text[i..].chars().next().expect("i is inside the text")
}

fn tokens(text: &str) -> Vec<Tok<'_>> {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        let b = bytes[i];
        let c = char_at(text, i);
        if js_space(c) || js_line_end(c) {
            i += c.len_utf8();
        } else if bytes[i..].starts_with(b"//") {
            i = text[i..].find(js_line_end).map_or(bytes.len(), |n| i + n);
        } else if bytes[i..].starts_with(b"/*") {
            i = bytes[i + 2..].windows(2).position(|w| w == b"*/").map_or(bytes.len(), |n| i + 2 + n + 2);
        } else if matches!(b, b'\'' | b'"' | b'`') {
            let start = i + 1;
            let mut j = start;
            while j < bytes.len() && bytes[j] != b {
                j += if bytes[j] == b'\\' { 2 } else { 1 };
            }
            let end = j.min(bytes.len());
            // A string cut by the end of the text holds its bytes up to there;
            // a backslash at the very end leaves `end` on a char boundary.
            let content = &text[start..end];
            let literal =
                !content.bytes().any(|c| matches!(c, b'\\' | b'\r' | b'\n')) && !(b == b'`' && content.contains("${"));
            out.push(Tok::Str(content, literal));
            i = end + 1;
        } else if ident(b) {
            let start = i;
            while i < bytes.len() && ident(bytes[i]) {
                i += 1;
            }
            out.push(Tok::Word(&text[start..i]));
        } else {
            out.push(Tok::Punct(b));
            i += c.len_utf8();
        }
    }
    out
}

/// A key: a word, or a string whose whole content is the word.
fn key<'a>(tok: &Tok<'a>) -> Option<&'a str> {
    match tok {
        Tok::Word(w) | Tok::Str(w, _) => Some(w),
        Tok::Punct(_) => None,
    }
}

fn literal<'a>(tok: Option<&Tok<'a>>) -> Option<&'a str> {
    match tok {
        Some(Tok::Str(content, true)) => Some(content),
        _ => None,
    }
}

fn ends_value(tok: Option<&Tok>) -> bool {
    matches!(tok, Some(Tok::Punct(b',' | b'}')))
}

/// A read setup key's value from `toks[i]` (right after the `:`): its
/// literals and the index after the value, when `,` or `}` follows it.
fn setup_value(toks: &[Tok], mut i: usize) -> Option<(Vec<String>, usize)> {
    if let Some(one) = literal(toks.get(i)) {
        return ends_value(toks.get(i + 1)).then(|| (vec![one.to_string()], i + 1));
    }
    if toks.get(i) != Some(&Tok::Punct(b'[')) {
        return None;
    }
    i += 1;
    let mut found = Vec::new();
    loop {
        if toks.get(i) == Some(&Tok::Punct(b']')) {
            break;
        }
        found.push(literal(toks.get(i))?.to_string());
        i += 1;
        match toks.get(i) {
            Some(Tok::Punct(b',')) => i += 1,
            Some(Tok::Punct(b']')) => {}
            _ => return None,
        }
    }
    ends_value(toks.get(i + 1)).then_some((found, i + 1))
}

/// A root key's value from `toks[i]`: the index after it when it names the
/// config's own folder and `,` or `}` follows.
fn root_value(toks: &[Tok], i: usize) -> Option<usize> {
    let meta = [Tok::Word("import"), Tok::Punct(b'.'), Tok::Word("meta"), Tok::Punct(b'.'), Tok::Word("dirname")];
    let after = if toks[i..].starts_with(&meta) {
        i + meta.len()
    } else if toks.get(i) == Some(&Tok::Word("__dirname")) || matches!(literal(toks.get(i)), Some("." | "./")) {
        i + 1
    } else {
        return None;
    };
    ends_value(toks.get(after)).then_some(after)
}

/// Item 140: a Jest root key's value from `toks[i]`: a literal, or a name of
/// the config's folder, followed by `,` or `}`.
fn jest_root(toks: &[Tok], i: usize) -> Option<(Option<String>, usize)> {
    match literal(toks.get(i)) {
        Some(lit) if ends_value(toks.get(i + 1)) => Some((Some(lit.to_string()), i + 1)),
        _ => root_value(toks, i).map(|after| (None, after)),
    }
}

/// The events of one config module, in text order (lossy UTF-8 text).
pub fn scan(text: &str, keys: &Keys) -> Vec<Event> {
    let toks = tokens(text);
    let mut events = Vec::new();
    let mut i = 0;
    while i < toks.len() {
        let colon = toks.get(i + 1) == Some(&Tok::Punct(b':'));
        match (key(&toks[i]), &toks[i]) {
            (Some(name), _) if keys.setup.contains(&name) => match colon.then(|| setup_value(&toks, i + 2)).flatten() {
                Some((found, after)) => {
                    events.extend(found.into_iter().map(Event::Setup));
                    i = after;
                    continue;
                }
                None => events.push(Event::Bad(format!("{name} is not a string or an array of strings"))),
            },
            (Some(name), _) if colon && name == keys.root && keys.jest => match jest_root(&toks, i + 2) {
                Some((value, after)) => {
                    events.push(Event::Root(value));
                    i = after;
                    continue;
                }
                None => events.push(Event::Bad("it sets rootDir".to_string())),
            },
            (Some(name), _) if colon && name == keys.root => match root_value(&toks, i + 2) {
                Some(after) => {
                    i = after;
                    continue;
                }
                None => events.push(Event::Bad("it sets root".to_string())),
            },
            (_, Tok::Word(word @ ("from" | "import" | "require"))) => {
                let next = toks.get(i + 1);
                if *word != "require" {
                    if let Some(lit) = literal(next) {
                        events.push(Event::Import(lit.to_string()));
                        i += 2;
                        continue;
                    }
                }
                if *word != "from" && next == Some(&Tok::Punct(b'(')) {
                    match (literal(toks.get(i + 2)), toks.get(i + 3)) {
                        (Some(lit), Some(Tok::Punct(b')'))) => {
                            events.push(Event::Import(lit.to_string()));
                            i += 4;
                            continue;
                        }
                        _ => events.push(Event::Bad("an import is not a string literal".to_string())),
                    }
                }
            }
            _ => {}
        }
        i += 1;
    }
    events
}

#[cfg(test)]
mod tests {
    use super::Event::{Bad, Import, Root, Setup};
    use super::*;

    fn setup(s: &str) -> Event {
        Setup(s.to_string())
    }

    fn bad(s: &str) -> Event {
        Bad(s.to_string())
    }

    /// The vitest scan; a local item shadows the glob import.
    fn scan(text: &str) -> Vec<Event> {
        super::scan(text, &VITEST)
    }

    #[test]
    fn jest_keys_and_root_dir() {
        let jest = |text: &str| super::scan(text, &JEST);
        let text = "{ rootDir: 'src', setupFilesAfterEnv: ['<rootDir>/a.js'], globalTeardown: './t', root: 'x' }";
        assert_eq!(jest(text), [Root(Some("src".into())), setup("<rootDir>/a.js"), setup("./t")]);
        assert_eq!(jest("{ 'rootDir': __dirname, setupFiles: './s' }"), [Root(None), setup("./s")]);
        assert_eq!(jest("{ rootDir: import.meta.dirname }"), [Root(None)]);
        assert_eq!(jest("{ rootDir: path.join(__dirname, 'src') }"), [bad("it sets rootDir")]);
        assert_eq!(jest("const rootDir = 'x'; a.rootDir"), []);
        assert_eq!(jest("{ globalSetup: g }"), [bad("globalSetup is not a string or an array of strings")]);
        // Jest's keys are nothing to vitest, and vitest's root nothing to Jest.
        assert_eq!(scan("{ setupFilesAfterEnv: x, rootDir: y, globalTeardown: z }"), []);
    }

    #[test]
    fn a_setup_key_is_read_as_a_literal_or_an_array_of_literals() {
        assert_eq!(scan("test: { setupFiles: ['./a.ts'] }"), [setup("./a.ts")]);
        assert_eq!(scan("{ setupFiles: \"./a\", globalSetup: `./g`, }"), [setup("./a"), setup("./g")]);
        assert_eq!(scan("{ 'setupFiles' /* c */ : [ './a', // x\n \"./b\", ] }"), [setup("./a"), setup("./b")]);
        assert_eq!(scan("{ setupFiles: [] }"), []);
    }

    #[test]
    fn whitespace_and_line_ends_are_javascript_s() {
        let lit = [setup("./src/test-setup.ts")];
        assert_eq!(scan("export default {test:{setupFiles\u{2028}:\u{2029}\"./src/test-setup.ts\"}};"), lit);
        assert_eq!(scan("\u{FEFF}{ setupFiles:\u{0B}[\u{A0}'./src/test-setup.ts'\u{3000},\u{2003}]\u{FEFF}}"), lit);
        assert_eq!(scan("{\u{202F}root\u{205F}:\u{1680}import.meta.dirname\u{2029}}"), []);
        assert_eq!(scan("require\u{2028}(\u{A0}'./a'\u{2009})"), [Import("./a".into())]);
        // A `//` comment ends at U+2028 and U+2029 as at LF and CR.
        assert_eq!(scan("// c\u{2028}{ setupFiles: x }"), [bad("setupFiles is not a string or an array of strings")]);
        assert_eq!(scan("// c\u{2029}import './b'"), [Import("./b".into())]);
        // Another non-ASCII character is not whitespace.
        assert_eq!(scan("{ setupFiles: é'./a' }"), [bad("setupFiles is not a string or an array of strings")]);
    }

    #[test]
    fn a_key_in_a_comment_or_inside_a_word_is_not_a_key() {
        assert_eq!(scan("// setupFiles: x\n/* globalSetup: y */ { mysetupFiles: z, setupFiles_: w }"), []);
        assert_eq!(scan("{ a: 'a setupFiles b' }"), []);
    }

    #[test]
    fn a_setup_key_that_is_not_read_is_bad() {
        let not = bad("setupFiles is not a string or an array of strings");
        for text in [
            "{ setupFiles: files }",
            "{ setupFiles: ['./a' + 'b.ts'] }",
            "{ setupFiles: [...a] }",
            "setupFiles.push('./a')",
            "const setupFiles = ['./a']",
            "{ setupFiles }",
            "{ setupFiles: ['./a'].concat(x) }",
            "{ setupFiles: [`./${a}`] }",
            "{ setupFiles: ['./a\\'b'] }",
            "{ include: ['setupFiles'] }",
        ] {
            assert_eq!(scan(text), std::slice::from_ref(&not), "{text}");
        }
        assert_eq!(scan("{ globalSetup: g }"), [bad("globalSetup is not a string or an array of strings")]);
    }

    #[test]
    fn a_root_key_is_bad_unless_it_names_the_folder() {
        for ok in [
            "{ root: import.meta.dirname, setupFiles: './s' }",
            "{ root: __dirname }",
            "{ 'root': '.' }",
            "{ root: \"./\" }",
        ] {
            assert!(!scan(ok).iter().any(|e| matches!(e, Bad(_))), "{ok}");
        }
        assert_eq!(scan("{ root: './src' }"), [bad("it sets root")]);
        assert_eq!(scan("{ root: path.resolve(__dirname) }"), [bad("it sets root")]);
        assert_eq!(scan("const root = 'x'; path.resolve('root'); a.root"), []);
    }

    #[test]
    fn imports_are_found_and_a_built_one_is_bad() {
        let text = "import { defineConfig } from 'vitest/config'\nimport './side'\nconst b = await import('./b')\nconst c = require(\"../c\")";
        assert_eq!(
            scan(text),
            [Import("vitest/config".into()), Import("./side".into()), Import("./b".into()), Import("../c".into())]
        );
        assert_eq!(scan("require(name)"), [bad("an import is not a string literal")]);
        assert_eq!(scan("import('./a' + b)"), [bad("an import is not a string literal")]);
        assert_eq!(scan("import.meta.url; Array.from(x); 'require(x)'; // import(x)"), []);
    }

    #[test]
    fn events_keep_text_order_and_strings_hide_their_text() {
        let text = "const s = \"// not a comment\"; { setupFiles: ['./a'], root: 'x', globalSetup: g }";
        assert_eq!(
            scan(text),
            [setup("./a"), bad("it sets root"), bad("globalSetup is not a string or an array of strings")]
        );
        // An unterminated string or comment runs to the end.
        assert_eq!(scan("'setupFiles: x"), []);
        assert_eq!(scan("x 'setupFiles'"), [bad("setupFiles is not a string or an array of strings")]);
        assert_eq!(scan("/* setupFiles: x"), []);
        assert_eq!(scan("'abc\\"), []);
    }
}
