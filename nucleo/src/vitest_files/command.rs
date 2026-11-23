//! Item 154: the config a vitest suite's command makes vitest read: `red`
//! locks it (point 2) or refuses `setup-unreadable` (point 3), and the hook
//! and CI take it, lexically, from a snapshot (point 4).

use super::scan::{self, Event};
use super::{folder, join, kind, relative, Kind, CONFIG_EXTS, JS_EXTS};
use crate::config::{Config, Suite};
use crate::git::Repo;
use crate::red::one_line;
use crate::refusal::{failed, refuse, Result, Stop};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};
use std::{fs, io};

const QUOTES: &str = "its quotes do not close";
const RESERVED: [&str; 9] = ["if", "then", "else", "elif", "do", "while", "until", "!", "{"];
const WRAPPERS: [&str; 11] = ["npx", "bunx", "pnpm", "yarn", "bun", "npm", "env", "exec", "time", "nice", "command"];

/// A word or an operator of a command.
#[derive(Debug, PartialEq)]
enum Tok {
    Word(String),
    Control,
    Open,
    Close,
}

#[derive(Default)]
struct Lexer {
    out: Vec<Tok>,
    word: Option<String>,
    /// The word holds a quoted or escaped character.
    quoted: bool,
    /// The next word is a redirection's operand.
    operand: bool,
}

impl Lexer {
    fn push(&mut self, c: char) {
        self.word.get_or_insert_with(String::new).push(c);
    }

    fn end(&mut self) {
        match self.word.take() {
            Some(word) if !std::mem::take(&mut self.operand) => self.out.push(Tok::Word(word)),
            _ => {}
        }
        self.quoted = false;
    }

    fn op(&mut self, tok: Tok) {
        self.end();
        self.operand = false;
        self.out.push(tok);
    }
}

/// Point 1's tokens, or why the whole command is unreadable.
fn tokens(command: &str) -> std::result::Result<Vec<Tok>, &'static str> {
    let chars: Vec<char> = command.chars().collect();
    let mut lx = Lexer::default();
    let mut i = 0;
    while i < chars.len() {
        match chars[i] {
            ' ' | '\t' => lx.end(),
            '\n' | ';' | '&' | '|' => lx.op(Tok::Control),
            '(' => lx.op(Tok::Open),
            ')' => lx.op(Tok::Close),
            c @ ('<' | '>') => {
                let digits = lx.word.as_ref().is_some_and(|w| w.bytes().all(|b| b.is_ascii_digit()));
                if digits && !lx.operand && !lx.quoted {
                    lx.word = None; // its file descriptor
                }
                lx.end();
                if c == '<' && chars.get(i + 1) == Some(&'<') {
                    return Err("it holds a here-document");
                }
                i += chars[i + 1..].iter().take_while(|c| matches!(c, '<' | '>' | '&' | '|')).count();
                lx.operand = true;
            }
            '#' if lx.word.is_none() => {
                i = chars[i..].iter().position(|&c| c == '\n').map_or(chars.len(), |n| i + n) - 1
            }
            '\\' if chars.get(i + 1) == Some(&'\n') => i += 1,
            '\\' => {
                lx.push(*chars.get(i + 1).ok_or(QUOTES)?);
                lx.quoted = true;
                i += 1;
            }
            '\'' => {
                let close = chars[i + 1..].iter().position(|&c| c == '\'').ok_or(QUOTES)?;
                lx.word.get_or_insert_with(String::new).extend(&chars[i + 1..i + 1 + close]);
                lx.quoted = true;
                i += close + 1;
            }
            '"' => {
                lx.word.get_or_insert_with(String::new);
                lx.quoted = true;
                i += 1;
                // A backslash before another character is kept, and so is that character.
                while chars.get(i) != Some(&'"') {
                    match (chars.get(i).ok_or(QUOTES)?, chars.get(i + 1)) {
                        ('\\', None) => return Err(QUOTES),
                        ('\\', Some('\n')) => i += 1,
                        ('\\', Some(&next @ ('"' | '\\' | '$' | '`'))) => {
                            lx.push(next);
                            i += 1;
                        }
                        (&c, _) => lx.push(c),
                    }
                    i += 1;
                }
            }
            c => lx.push(c),
        }
        i += 1;
    }
    lx.end();
    Ok(lx.out)
}

/// What an invocation says about the config: no `--config` (vitest's walk),
/// `--no-config`, or `--config`'s value as written.
#[derive(Debug, PartialEq)]
pub(crate) enum Named {
    Walk,
    Nothing,
    Path(String),
}

/// A vitest invocation read without a reason.
#[derive(Debug, PartialEq)]
pub(crate) struct Invocation {
    pub word: String,
    pub config: Named,
    pub root: Option<String>,
}

/// One simple command that holds an invocation, or its reason.
type Item = std::result::Result<Invocation, String>;

fn base(word: &str) -> &str {
    word.rsplit('/').next().unwrap_or(word)
}

/// `NAME=value`, `NAME` an ASCII letter or `_` then letters, digits and `_`.
fn assignment(word: &str) -> bool {
    let Some((name, _)) = word.split_once('=') else { return false };
    let mut bytes = name.bytes();
    bytes.next().is_some_and(|b| b.is_ascii_alphabetic() || b == b'_')
        && bytes.all(|b| b.is_ascii_alphanumeric() || b == b'_')
}

/// Point 1: the invocations of a command in command order, or why the whole
/// command is unreadable.
pub(crate) fn read(command: &str) -> std::result::Result<Vec<Item>, String> {
    let toks = tokens(command).map_err(str::to_string)?;
    let mut items = Vec::new();
    let mut words: Vec<String> = Vec::new();
    let (mut depth, mut in_force) = (0usize, None::<(usize, String)>);
    for tok in toks.into_iter().chain([Tok::Control]) {
        if let Tok::Word(word) = tok {
            words.push(word);
            continue;
        }
        simple(&std::mem::take(&mut words), depth, &mut in_force, &mut items);
        match tok {
            Tok::Open => depth += 1,
            Tok::Close => {
                depth = depth.saturating_sub(1);
                in_force = in_force.filter(|(at, _)| depth >= *at);
            }
            _ => {}
        }
    }
    Ok(items)
}

/// One simple command at `depth`.
fn simple(words: &[String], depth: usize, in_force: &mut Option<(usize, String)>, items: &mut Vec<Item>) {
    let Some(c) = words.iter().position(|w| !assignment(w) && !RESERVED.contains(&w.as_str())) else { return };
    let first = words[c].as_str();
    if first == "cd" || first == "pushd" {
        if in_force.as_ref().is_none_or(|(at, _)| depth < *at) {
            *in_force = Some((depth, first.to_string()));
        }
        return;
    }
    match invocation_word(words, c) {
        Some(k) => items.push(match in_force {
            Some((_, cd)) => Err(format!("{cd} runs before vitest")),
            None => options(&words[k], &words[k + 1..]),
        }),
        None if WRAPPERS.contains(&first) && words[c + 1..].iter().any(|w| base(w) == "vitest") => {
            items.push(Err(format!("{first} runs vitest in a form Shipcraft does not read")))
        }
        None => {}
    }
}

/// The index of the invocation word, from the command word at `k`.
fn invocation_word(words: &[String], mut k: usize) -> Option<usize> {
    loop {
        if base(&words[k]) == "vitest" {
            return Some(k);
        }
        if !WRAPPERS.contains(&words[k].as_str()) {
            return None;
        }
        let skipped = |w: &String| w.starts_with('-') || assignment(w) || matches!(w.as_str(), "exec" | "x" | "dlx");
        k = (k + 1..words.len()).find(|&j| !skipped(&words[j]))?;
    }
}

/// Point 1's options of one invocation, or the first reason in argument order.
fn options(word: &str, args: &[String]) -> Item {
    let (mut config, mut root) = (None::<Named>, None::<String>);
    let mut i = 0;
    while i < args.len() {
        let arg = args[i].as_str();
        i += 1;
        if arg == "--" {
            break;
        }
        if arg == "--no-config" {
            if config.is_some() {
                return Err("--config is given more than once".to_string());
            }
            config = Some(Named::Nothing);
            continue;
        }
        let names = ["--config", "-c", "--root", "-r"];
        let carried = names.iter().find_map(|n| Some((*n, Some(arg.strip_prefix(n)?.strip_prefix('=')?))));
        let (name, value) = match carried {
            Some(found) => found,
            None if names.contains(&arg) => {
                let value = args.get(i).filter(|v| !v.starts_with('-')).map(String::as_str);
                i += usize::from(value.is_some());
                (arg, value)
            }
            None => continue,
        };
        let is_config = matches!(name, "--config" | "-c");
        let long = if is_config { "--config" } else { "--root" };
        if (is_config && config.is_some()) || (!is_config && root.is_some()) {
            return Err(format!("{long} is given more than once"));
        }
        let value = match value {
            Some(v) if !v.is_empty() => v,
            _ => return Err(format!("{name} has no value")),
        };
        let shown = one_line(value);
        if value.contains(['$', '`', '*', '?', '[']) || value.starts_with('~') {
            return Err(format!("{name} {shown} is not a plain path"));
        }
        if value.starts_with('/') {
            return Err(format!("{name} {shown} is an absolute path"));
        }
        if is_config {
            config = Some(Named::Path(value.to_string()));
        } else {
            root = Some(value.to_string());
        }
    }
    Ok(Invocation { word: word.to_string(), config: config.unwrap_or(Named::Walk), root })
}

/// `folder`, then each folder above it up to the repository root ("").
fn folders(dir: &str) -> Vec<String> {
    let mut out = vec![dir.to_string()];
    let mut at = dir;
    while !at.is_empty() {
        at = folder(at);
        out.push(at.to_string());
    }
    out
}

/// The walk's names in one folder, in vitest's order.
fn names(dir: &str) -> impl Iterator<Item = String> + '_ {
    ["vitest.config", "vite.config"]
        .into_iter()
        .flat_map(|stem| CONFIG_EXTS.iter().map(move |ext| format!("{stem}.{ext}")))
        .map(move |name| format!("{dir}/{name}").trim_start_matches('/').to_string())
}

fn javascript(path: &str) -> bool {
    path.rsplit('/').next().and_then(|name| name.rsplit_once('.')).is_some_and(|(_, ext)| CONFIG_EXTS.contains(&ext))
}

/// A `version` string whose leading number is 5 or more.
fn major_five(version: &str) -> bool {
    let digits: String = version.chars().take_while(char::is_ascii_digit).collect();
    let digits = digits.trim_start_matches('0');
    digits.len() >= 2 || matches!(digits, "5" | "6" | "7" | "8" | "9")
}

/// Point 2: whether the invocation's vitest is version 5 or later, read from
/// the one `package.json` its word points to.
fn version_five(repo: &Repo, suite: &Suite, word: &str) -> bool {
    const MANIFEST: &str = "node_modules/vitest/package.json";
    let bytes = if word.contains('/') {
        let joined = if word.starts_with('/') { None } else { join(&suite.raiz, word) };
        let dir = joined.as_deref().and_then(|j| j.strip_suffix("node_modules/.bin/vitest"));
        dir.filter(|d| d.is_empty() || d.ends_with('/'))
            .and_then(|d| fs::read(repo.path(&format!("{d}{MANIFEST}"))).ok())
    } else {
        folders(&suite.raiz)
            .iter()
            .find_map(|f| fs::read(repo.path(format!("{f}/{MANIFEST}").trim_start_matches('/'))).ok())
    };
    let parsed = bytes.and_then(|b| serde_json::from_slice::<Value>(&b).ok());
    parsed.as_ref().and_then(|v| v.get("version")?.as_str()).is_some_and(major_five)
}

/// A config `red` takes from an invocation: its path, its vitest root, and
/// whether `--root` was given.
pub(crate) struct Taken {
    pub path: String,
    pub root: String,
    pub rooted: bool,
}

/// Why an invocation is unreadable, or a read failure.
enum Fail {
    Why(String),
    Stop(Stop),
}
type Read<T> = std::result::Result<T, Fail>;

/// Point 2 for one invocation: the config it names. On the working tree
/// (`tree`), with point 2's reasons; in a snapshot (point 4), lexically: no
/// file read, no link checked, the walk always up to the repository root.
fn take(tree: Option<&Repo>, suite: &Suite, present: &BTreeSet<&str>, inv: &Invocation) -> Read<Option<Taken>> {
    let why = |text: String| Fail::Why(text);
    let root = match &inv.root {
        None => suite.raiz.clone(),
        Some(v) => join(&suite.raiz, v)
            .ok_or_else(|| why(format!("--root {} names a folder above the repository root", one_line(v))))?,
    };
    if let (Some(v), Some(repo)) = (&inv.root, tree) {
        let parts: Vec<&str> = root.split('/').filter(|p| !p.is_empty()).collect();
        for prefix in (1..=parts.len()).map(|k| parts[..k].join("/")) {
            let above = suite.raiz == prefix || suite.raiz.starts_with(&format!("{prefix}/"));
            if !above && fs::symlink_metadata(repo.path(&prefix)).is_ok_and(|m| m.file_type().is_symlink()) {
                return Err(why(format!("--root {} goes through a symbolic link", one_line(v))));
            }
        }
    }
    let path = match &inv.config {
        Named::Nothing => return Ok(None),
        Named::Path(v) => {
            let shown = one_line(v);
            let path = join(&root, v)
                .ok_or_else(|| why(format!("--config {shown} names a file above the repository root")))?;
            if !present.contains(path.as_str()) {
                return Err(why(format!("--config {shown} names no file in the repository")));
            }
            if !javascript(&path) {
                return Err(why(format!("--config {shown} is not a .ts, .mts, .cts, .js, .mjs or .cjs file")));
            }
            path
        }
        Named::Walk => {
            let mut walked = folders(&root);
            if tree.is_some_and(|repo| version_five(repo, suite, &inv.word)) {
                walked.truncate(1);
            }
            // On the working tree, a name git does not list is checked.
            let mut found = None;
            for path in walked.iter().flat_map(|f| names(f)) {
                if present.contains(path.as_str()) {
                    found = Some(path);
                    break;
                }
                let Some(repo) = tree else { continue };
                match fs::symlink_metadata(repo.path(&path)) {
                    Ok(meta) if meta.is_dir() => {}
                    Ok(_) => return Err(why(format!("{} is a vitest config git does not list", one_line(&path)))),
                    Err(e) if e.kind() == io::ErrorKind::NotFound => {}
                    Err(e) => return Err(Fail::Stop(failed(format!("read {path}: {e}")))),
                }
            }
            let Some(path) = found else { return Ok(None) };
            path
        }
    };
    Ok(Some(Taken { path, root, rooted: inv.root.is_some() }))
}

/// Points 2 and 3: the configs every invocation of the vitest `suites` names,
/// in config order, or `setup-unreadable` for the first one it cannot read.
pub(crate) fn taken(repo: &Repo, config: &Config, suites: &[Suite], present: &BTreeSet<&str>) -> Result<Vec<Taken>> {
    let mut out = Vec::new();
    for suite in suites {
        let read = read(&suite.comando).map_err(Fail::Why).and_then(|items| {
            items.into_iter().try_for_each(|item| {
                out.extend(take(Some(repo), suite, present, &item.map_err(Fail::Why)?)?);
                Ok(())
            })
        });
        let why = match read {
            Ok(()) => continue,
            Err(Fail::Stop(stop)) => return Err(stop),
            Err(Fail::Why(why)) => why,
        };
        let key = match config.suite.is_empty() {
            true => "test_command".to_string(),
            false => format!("command of [[suite]] {}", one_line(suite.name())),
        };
        return refuse(
            "setup-unreadable",
            format!("could not read the vitest config of {key}: {why}"),
            "red locks the config vitest reads and the setup files it names; a config it cannot name could change what every locked case sees",
            "in .shipcraft.toml, give vitest's --config and --root at most once each, as plain relative paths, with no cd before vitest, then run red again",
        );
    }
    Ok(out)
}

type Dirs = BTreeMap<String, BTreeSet<String>>;

/// Point 2: the folders each module's setup literals resolve from: its own
/// when a runner config reaches it, each reaching named config's root folders.
pub(crate) fn dirs(repo: &Repo, present: &BTreeSet<&str>, runners: &BTreeSet<String>, taken: &[Taken]) -> Result<Dirs> {
    let (mut rooted, mut dirs) = (BTreeMap::new(), Dirs::new());
    for (start, named) in runners.iter().map(|p| (p, None)).chain(taken.iter().map(|t| (&t.path, Some(t)))) {
        let (mut seen, mut queue) = (BTreeSet::from([start.clone()]), vec![start.clone()]);
        while let Some(module) = queue.pop() {
            let scanned = module.rsplit_once('.').is_some_and(|(_, ext)| JS_EXTS.contains(&ext));
            if !scanned || !matches!(kind(repo, &module)?, Kind::File) {
                continue;
            }
            let bytes = fs::read(repo.path(&module)).map_err(|e| failed(format!("read {module}: {e}")))?;
            let events = scan::scan(&String::from_utf8_lossy(&bytes), &scan::VITEST);
            rooted.insert(module.clone(), events.contains(&Event::Root(None)));
            for event in events {
                let Event::Import(content) = event else { continue };
                let Some(base) = join(folder(&module), &content).filter(|_| relative(&content)) else { continue };
                for candidate in [base.clone()].into_iter().chain(JS_EXTS.iter().map(|ext| format!("{base}.{ext}"))) {
                    let file = present.contains(candidate.as_str()) && matches!(kind(repo, &candidate)?, Kind::File);
                    if file && seen.insert(candidate.clone()) {
                        queue.push(candidate);
                    }
                }
            }
        }
        let mut roots: BTreeSet<String> = named.map(|t| t.root.clone()).into_iter().collect();
        if named.is_some_and(|t| !t.rooted) {
            roots.extend(seen.iter().filter(|m| rooted.get(*m) == Some(&true)).map(|m| folder(m).to_string()));
        }
        for module in seen {
            let own = roots.is_empty().then(|| folder(&module).to_string());
            dirs.entry(module).or_default().extend(roots.iter().cloned().chain(own));
        }
    }
    Ok(dirs)
}

/// Point 4: the configs a suite's invocations read without a reason name
/// among a snapshot's paths.
pub(crate) fn in_snapshot(suite: &Suite, paths: &BTreeSet<&str>) -> Vec<String> {
    let invocations = read(&suite.comando).unwrap_or_default().into_iter().filter_map(Item::ok);
    invocations.filter_map(|inv| take(None, suite, paths, &inv).ok().flatten().map(|t| t.path)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn words(command: &str) -> Vec<String> {
        let shown = |tok| if let Tok::Word(w) = tok { w } else { format!("{tok:?}") };
        tokens(command).unwrap().into_iter().map(shown).collect()
    }

    fn inv(word: &str, config: Named, root: Option<&str>) -> Item {
        Ok(Invocation { word: word.into(), config, root: root.map(str::to_string) })
    }

    fn bad(why: &str) -> Item {
        Err(why.into())
    }

    fn suite(raiz: &str, comando: &str) -> Suite {
        let text = format!("[[suite]]\nroot = \"{raiz}\"\ncommand = \'\'\'{comando}\'\'\'\nglobs = [\"*.ts\"]\n");
        Config::parse(&text).unwrap().suites().remove(0)
    }

    #[test]
    fn the_tokenizer_splits_as_sh() {
        assert_eq!(words("a  b\tc"), ["a", "b", "c"]);
        assert_eq!(
            words("a;b&&c|d\ne"),
            ["a", "Control", "b", "Control", "Control", "c", "Control", "d", "Control", "e"]
        );
        assert_eq!(words("(cd x)y"), ["Open", "cd", "x", "Close", "y"]);
        assert_eq!(words("--root='my web' \"a\\\"b\\x\" c\\ d"), ["--root=my web", "a\"b\\x", "c d"]);
        assert_eq!(words("a \\\n b \"x\\\ny\""), ["a", "b", "xy"]);
        assert_eq!(words("'' a"), ["", "a"]);
        assert_eq!(words("# vitest -c x\nb #c d"), ["Control", "b"]);
        assert_eq!(words("a#b $X `y` *"), ["a#b", "$X", "`y`", "*"]);
        assert_eq!(words("a 2>&1 b >out c>>log d <in e >|f"), ["a", "b", "c", "d", "e"]);
        assert_eq!(words("\\2026>x '2026'>x \"2026\">x 2>x b"), ["2026", "2026", "2026", "b"]);
        assert_eq!([tokens("a 'b"), tokens("a \"b"), tokens("a \\")], [Err(QUOTES), Err(QUOTES), Err(QUOTES)]);
        assert_eq!(tokens("cat <<EOF\nx\nEOF"), Err("it holds a here-document"));
    }

    #[test]
    fn invocations_and_wrappers() {
        let walk = |w: &str| inv(w, Named::Walk, None);
        assert_eq!(read("node_modules/.bin/vitest run"), Ok(vec![walk("node_modules/.bin/vitest")]));
        assert_eq!(read("npx --no -- vitest run"), Ok(vec![walk("vitest")]));
        assert_eq!(read("env CI=1 npx vitest; pnpm exec vitest"), Ok(vec![walk("vitest"), walk("vitest")]));
        assert_eq!(read("if true; then A=1 vitest; fi"), Ok(vec![walk("vitest")]));
        assert_eq!(read("printf vitest --config x.ts; npm test; npm run test:vitest"), Ok(vec![]));
        let env = bad("env runs vitest in a form Shipcraft does not read");
        assert_eq!(read("env -u NODE_OPTIONS vitest"), Ok(vec![env]));
        assert_eq!(read("cd web && vitest run"), Ok(vec![bad("cd runs before vitest")]));
        assert_eq!(read("cd x && make; cd ..; vitest"), Ok(vec![bad("cd runs before vitest")]));
        let group = inv("vitest", Named::Path("u.ts".into()), None);
        assert_eq!(read("(cd tools && true); vitest -c u.ts"), Ok(vec![group]));
        assert_eq!(read("((pushd a); vitest)"), Ok(vec![walk("vitest")]));
        assert_eq!(read("(pushd a; (true)); vitest"), Ok(vec![walk("vitest")]));
        assert_eq!(read("pushd a; (vitest)"), Ok(vec![bad("pushd runs before vitest")]));
        assert_eq!(read("a 'b"), Err(QUOTES.to_string()));
    }

    #[test]
    fn the_options_of_an_invocation() {
        let path = |p: &str| Named::Path(p.into());
        assert_eq!(read("vitest -c a.ts -r web"), Ok(vec![inv("vitest", path("a.ts"), Some("web"))]));
        assert_eq!(read("vitest --config=a=b.ts --root=."), Ok(vec![inv("vitest", path("a=b.ts"), Some("."))]));
        assert_eq!(read("vitest -c=x --no-config"), Ok(vec![bad("--config is given more than once")]));
        assert_eq!(read("vitest --no-config"), Ok(vec![inv("vitest", Named::Nothing, None)]));
        assert_eq!(read("vitest run -- --config x"), Ok(vec![inv("vitest", Named::Walk, None)]));
        assert_eq!(read("vitest -t --config x"), Ok(vec![inv("vitest", path("x"), None)]));
        assert_eq!(read("vitest -uc x"), Ok(vec![inv("vitest", Named::Walk, None)]));
        assert_eq!(read("vitest -c a.ts -c b.ts"), Ok(vec![bad("--config is given more than once")]));
        assert_eq!(read("vitest -r"), Ok(vec![bad("-r has no value")]));
        assert_eq!(read("vitest -r --reporter=x"), Ok(vec![bad("-r has no value")]));
        assert_eq!(read("vitest --config= x"), Ok(vec![bad("--config has no value")]));
        assert_eq!(read("vitest -c ''"), Ok(vec![bad("-c has no value")]));
        assert_eq!(read("vitest --config $CFG"), Ok(vec![bad("--config $CFG is not a plain path")]));
        assert_eq!(read("vitest -r ~/x"), Ok(vec![bad("-r ~/x is not a plain path")]));
        assert_eq!(read("vitest --root /abs"), Ok(vec![bad("--root /abs is an absolute path")]));
        assert_eq!(read("vitest -c 'a\nb'"), Ok(vec![inv("vitest", path("a\nb"), None)]));
        assert_eq!(read("vitest -c '/a\nb'"), Ok(vec![bad("-c /a\\nb is an absolute path")]));
    }

    #[test]
    fn the_walk_and_the_snapshot() {
        assert_eq!([folders("a/b"), folders("")], [vec!["a/b", "a", ""], vec![""]]);
        let order: Vec<String> = names("web").collect();
        assert_eq!(
            [&order[0], &order[5], &order[6]],
            ["web/vitest.config.ts", "web/vitest.config.cjs", "web/vite.config.ts"]
        );
        let paths: BTreeSet<&str> =
            ["vite.config.ts", "vitest.config.ts", "web/vite.config.mjs", "cfg/u.ts", "cfg/u.json"].into();
        assert_eq!(in_snapshot(&suite("web", "vitest"), &paths), ["web/vite.config.mjs"]);
        assert_eq!(in_snapshot(&suite("docs", "vitest"), &paths), ["vitest.config.ts"]);
        let both =
            "vitest -c ../cfg/u.ts && vitest -c ../cfg/u.json; vitest --no-config; vitest -r ../.. ; vitest -r ..";
        assert_eq!(in_snapshot(&suite("web", both), &paths), ["cfg/u.ts", "vitest.config.ts"]);
        assert!(in_snapshot(&suite("", "cd x; vitest"), &paths).is_empty());
        assert!(in_snapshot(&suite("", "vitest 'x"), &paths).is_empty());
    }

    #[test]
    fn the_version_rule() {
        for yes in ["5.0.4", "5", "10.1.0", "05.1", "9-beta", "0005x"] {
            assert!(major_five(yes), "{yes}");
        }
        for no in ["4.0.5", "0", "00", "v5", "", "1.2"] {
            assert!(!major_five(no), "{no}");
        }
        let dir = crate::git::TempDir::new("shipcraft-vitest-command-").unwrap();
        let write = |path: &str, text: &str| {
            let full = dir.path().join(path);
            fs::create_dir_all(full.parent().unwrap()).unwrap();
            fs::write(full, text).unwrap();
        };
        write("node_modules/vitest/package.json", r#"{"version":"4.0.5"}"#);
        write("web/node_modules/vitest/package.json", r#"{"version":"5.0.4"}"#);
        write("bad/node_modules/vitest/package.json", "not json");
        let repo = Repo::at_root(dir.path());
        let suite = |raiz: &str| suite(raiz, "");
        assert!(version_five(&repo, &suite("web"), "vitest"));
        assert!(version_five(&repo, &suite("web"), "node_modules/.bin/vitest"));
        assert!(!version_five(&repo, &suite("web"), "../node_modules/.bin/vitest"));
        assert!(!version_five(&repo, &suite("web/x"), "./bin/vitest"));
        assert!(!version_five(&repo, &suite("web"), "/web/node_modules/.bin/vitest"));
        assert!(!version_five(&repo, &suite("web"), "../../node_modules/.bin/vitest"));
        assert!(!version_five(&repo, &suite("other"), "vitest"));
        assert!(!version_five(&repo, &suite("bad"), "vitest"), "the first file read decides, not JSON: no evidence");
        assert!(version_five(&repo, &suite("web/deep"), "vitest"));
    }
}
