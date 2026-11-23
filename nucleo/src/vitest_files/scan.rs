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
    positioned(text, keys).into_iter().map(|(_, event)| event).collect()
}

/// Item 155: events with the index of the token where each was found.
#[derive(Default)]
struct Events {
    list: Vec<(usize, Event)>,
    at: usize,
}

impl Events {
    fn push(&mut self, event: Event) {
        self.list.push((self.at, event));
    }

    fn extend(&mut self, events: impl IntoIterator<Item = Event>) {
        for event in events {
            self.push(event);
        }
    }
}

/// `scan`'s events, each with its token index.
fn positioned(text: &str, keys: &Keys) -> Vec<(usize, Event)> {
    let toks = tokens(text);
    let mut events = Events::default();
    let mut i = 0;
    while i < toks.len() {
        events.at = i;
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
    events.list
}

/// Item 155: a module item, a string literal or `require.resolve(<literal>)`.
#[derive(Debug, PartialEq)]
pub enum Item {
    Literal(String),
    Resolve(String),
}

/// Item 155: what `scan_with` found, in text order.
#[derive(Debug, PartialEq)]
pub enum Read {
    /// One of `scan`'s events.
    Event(Event),
    /// A module item of a read module key's value.
    Module(&'static str, Item),
}

/// Item 155: the module keys a scan reads, the one whose value is a single
/// module item (`preset`), and the data keys whose values name nothing.
pub struct Modules {
    pub keys: &'static [&'static str],
    pub single: Option<&'static str>,
    pub data: &'static [&'static str],
}

/// `scan`'s events with the module items of `modules`' keys, in text order.
pub fn scan_with(text: &str, keys: &Keys, modules: &Modules) -> Vec<Read> {
    let toks = tokens(text);
    let mut found: Vec<(usize, Read)> =
        positioned(text, keys).into_iter().map(|(at, event)| (at, Read::Event(event))).collect();
    let mut i = 0;
    while i < toks.len() {
        let name = key(&toks[i]).filter(|_| toks.get(i + 1) == Some(&Tok::Punct(b':')));
        let module = name.and_then(|name| modules.keys.iter().chain(&modules.single).find(|k| **k == name).copied());
        if module.is_none() && !name.is_some_and(|name| modules.data.contains(&name)) {
            i += 1;
            continue;
        }
        // The value runs to its `,` or closing bracket; keys inside it name nothing.
        let end = value_end(&toks, i + 2);
        if let Some(module) = module.filter(|_| ends_value(toks.get(end))) {
            let value = &toks[i + 2..end];
            let items = if modules.single == Some(module) { item(value).into_iter().collect() } else { items(value) };
            found.extend(items.into_iter().map(|item| (i, Read::Module(module, item))));
        }
        i = end.max(i + 1);
    }
    found.sort_by_key(|(at, _)| *at);
    found.into_iter().map(|(_, read)| read).collect()
}

/// The index of the first `,` or unmatched closing bracket from `toks[i]`.
fn value_end(toks: &[Tok], mut i: usize) -> usize {
    let mut depth = 0usize;
    while let Some(tok) = toks.get(i) {
        match tok {
            Tok::Punct(b'(' | b'[' | b'{') => depth += 1,
            Tok::Punct(b')' | b']' | b'}') if depth == 0 => break,
            Tok::Punct(b')' | b']' | b'}') => depth -= 1,
            Tok::Punct(b',') if depth == 0 => break,
            _ => {}
        }
        i += 1;
    }
    i
}

/// A module item that is the whole of `toks`.
fn item(toks: &[Tok]) -> Option<Item> {
    match toks {
        [Tok::Str(content, true)] => Some(Item::Literal(content.to_string())),
        [Tok::Word("require"), Tok::Punct(b'.'), Tok::Word("resolve"), Tok::Punct(b'('), Tok::Str(content, true), Tok::Punct(b')')] => {
            Some(Item::Resolve(content.to_string()))
        }
        _ => None,
    }
}

/// The parts of `toks` when it is one `open`...matching-close group, split at
/// the group's own commas (an empty part, after a trailing comma, dropped).
fn parts<'t, 'a>(toks: &'t [Tok<'a>], open: u8) -> Option<Vec<&'t [Tok<'a>]>> {
    let inner = toks.get(1..toks.len().checked_sub(1)?)?;
    if toks.first() != Some(&Tok::Punct(open)) || !matches!(toks.last(), Some(Tok::Punct(b')' | b']' | b'}'))) {
        return None;
    }
    let mut out = Vec::new();
    let mut start = 0;
    while start < inner.len() {
        let end = value_end(inner, start);
        // An unmatched closing bracket inside: the group closed before the end.
        if end < inner.len() && inner[end] != Tok::Punct(b',') {
            return None;
        }
        out.push(&inner[start..end]);
        start = end + 1;
    }
    Some(out.into_iter().filter(|part| !part.is_empty()).collect())
}

/// The module items of an array's items that are module items.
fn array_items(toks: &[Tok]) -> Option<Vec<Item>> {
    Some(parts(toks, b'[')?.into_iter().filter_map(item).collect())
}

/// A module key's value: a module item, an array (its module items, and the
/// module items of each tuple in it) or an object (each property's value read
/// as an array item is); any other shape names nothing.
fn items(toks: &[Tok]) -> Vec<Item> {
    if let Some(one) = item(toks) {
        return vec![one];
    }
    let as_array_item = |part: &[Tok]| item(part).map(|one| vec![one]).or_else(|| array_items(part));
    if let Some(list) = parts(toks, b'[') {
        return list.into_iter().filter_map(as_array_item).flatten().collect();
    }
    let Some(props) = parts(toks, b'{') else { return Vec::new() };
    props
        .into_iter()
        .filter_map(|prop| match prop {
            [Tok::Word(_) | Tok::Str(..), Tok::Punct(b':'), value @ ..] => as_array_item(value),
            _ => None,
        })
        .flatten()
        .collect()
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

    /// Item 155: the Jest scan with the module keys, as `jest_files` calls it.
    fn modules(text: &str) -> Vec<Read> {
        let keys = &["transform", "testEnvironment", "reporters", "moduleNameMapper", "watchPlugins"];
        super::scan_with(text, &JEST, &Modules { keys, single: Some("preset"), data: &["globals"] })
    }

    fn lit(key: &'static str, s: &str) -> Read {
        Read::Module(key, Item::Literal(s.to_string()))
    }

    #[test]
    fn module_items_of_each_value_shape() {
        assert_eq!(modules("{ testEnvironment: '<rootDir>/env.js' }"), [lit("testEnvironment", "<rootDir>/env.js")]);
        let res = Read::Module("testEnvironment", Item::Resolve("./e".into()));
        assert_eq!(modules("{ testEnvironment: require.resolve('./e'), }"), [res]);
        let text = "{ reporters: ['default', ['./rep.js', { outputDirectory: './out' }], {x: './no'}, ...more] }";
        assert_eq!(modules(text), [lit("reporters", "default"), lit("reporters", "./rep.js")]);
        let text = "{ transform: { '\\\\.ts$': ['./ts.js', { tsconfig: './t.json' }], \"x\": './css.js', ...base, y, m() {} } }";
        assert_eq!(modules(text), [lit("transform", "./ts.js"), lit("transform", "./css.js")]);
        assert_eq!(
            modules("{ watchPlugins: [['./w.js', {key: 'k'}]], transform: {a: [['./no.js']]} }"),
            [lit("watchPlugins", "./w.js")]
        );
        assert_eq!(modules("{ preset: './p', }"), [lit("preset", "./p")]);
        assert_eq!(modules("{ preset: ['./p'] }"), []);
    }

    #[test]
    fn other_value_shapes_name_nothing_and_are_never_bad() {
        for text in [
            "{ testEnvironment: './env.js' + '.bak' }",
            "{ reporters: ['./r.js'].concat([]) }",
            "{ testEnvironment: (x) }",
            "{ transform: { a: './t.js' } as const }",
            "{ testEnvironment: env }",
            "{ testEnvironment: path.join(__dirname, 'env.js') }",
            "{ testEnvironment: `./${e}` }",
            "{ testEnvironment: './a\\\\b' }",
            "{ preset: name }",
            "transform(src); testEnvironment",
            "{ testEnvironment: './e.js' ]",
        ] {
            assert_eq!(modules(text), [], "{text}");
        }
    }

    #[test]
    fn keys_inside_module_and_data_values_name_nothing() {
        let text = "{ reporters: [['./rep.js', {transform: './t.txt'}]], globals: {testEnvironment: './g.js'}, testEnvironment: './e.js' }";
        assert_eq!(modules(text), [lit("reporters", "./rep.js"), lit("testEnvironment", "./e.js")]);
        // Item 132's events go on inside a value, at their place in text order.
        let text = "{ setupFiles: './s', testEnvironment: require('./env'), transform: {x: './t.js'}, globalSetup: g }";
        assert_eq!(
            modules(text),
            [
                Read::Event(setup("./s")),
                Read::Event(Import("./env".into())),
                lit("transform", "./t.js"),
                Read::Event(bad("globalSetup is not a string or an array of strings")),
            ]
        );
    }

    #[test]
    fn scan_is_unchanged_by_the_module_keys() {
        let text = "{ transform: {x: './t.js'}, preset: './p', setupFiles: ['./s'], rootDir: 'src' }";
        assert_eq!(super::scan(text, &JEST), [setup("./s"), Root(Some("src".into()))]);
        assert_eq!(scan(text), [setup("./s")]);
    }
}
