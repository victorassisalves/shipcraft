//! Item 25: the init integrates with the husky 9 and with the pre-commit
//! framework through the `commit-msg` (item 17): `shipcraft check --commit-msg` in
//! the `commit-msg` and `shipcraft close` in the `post-commit`. Their `pre-commit`
//! is not touched: its formatters run before, and the `commit-msg` sees the
//! final index.

use crate::config::CONFIG_FILE;
use crate::git::Repo;
use crate::init::{is_executable, layout, single_source, LOCAL};
use crate::refusal::{failed, refuse, Result, Stop};
use serde_norway::Value;
use std::fs;

pub const PRE_COMMIT_CONFIG: &str = ".pre-commit-config.yaml";
/// The husky files the init writes, and the line of each (point 1).
pub const HUSKY: [(&str, &str); 2] =
    [(".husky/commit-msg", "shipcraft check --commit-msg \"$1\""), (".husky/post-commit", "shipcraft close")];
/// The two local hooks of the pre-commit framework (point 2): id, entry, stage.
const HOOKS: [(&str, &str, &str); 2] = [
    ("shipcraft-check", "shipcraft check --commit-msg", "commit-msg"),
    ("shipcraft-fecha", "shipcraft close", "post-commit"),
];
const TWICE: &str = "with it, the suite would run twice per commit: remove it";

/// What the integration writes: (file, old text or None when new, new text),
/// and what git does not run yet, with the command that installs it.
pub struct Tool {
    pub name: &'static str,
    pub writes: Vec<(String, Option<String>, String)>,
    pub missing: Vec<String>,
    pub install: &'static str,
}

/// Whether the project uses one of these tools: `.husky/`, a husky before
/// the 9 (`husky.hooks` in the `package.json`, point 1) or the config.
pub fn present(repo: &Repo) -> bool {
    old_husky(repo) || [".husky", PRE_COMMIT_CONFIG].iter().any(|f| repo.path(f).symlink_metadata().is_ok())
}

/// A `core.hooksPath` in `.husky` is a husky's, of the 9 or of before (point 1).
pub fn husky_path(dir: Option<&str>) -> bool {
    dir.is_some_and(|d| d.starts_with(".husky"))
}

fn old_husky(repo: &Repo) -> bool {
    let package = fs::read_to_string(repo.path("package.json")).ok();
    let json = package.and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok());
    json.is_some_and(|p| p.get("husky").and_then(|h| h.get("hooks")).is_some())
}

/// 25.3: a line that runs `shipcraft check` (its first two words, after an `exec`), in a `pre-commit`.
fn checks(text: &str) -> bool {
    text.lines().any(|l| l.split_whitespace().skip_while(|w| *w == "exec").take(2).eq(["shipcraft", "check"]))
}

/// Points 1 to 4: the plan, decided before anything is written; any doubt
/// refuses, nothing written (rule 17). `dir` is the raw `core.hooksPath`.
/// Item 58: `local` writes `./node_modules/.bin/shipcraft` for `shipcraft`; both forms are recognized.
pub fn decide(repo: &Repo, dir: Option<&str>, local: bool) -> Result<Tool> {
    let husky = husky_path(dir) || old_husky(repo) || repo.path(".husky").symlink_metadata().is_ok();
    let other = if husky && repo.path(PRE_COMMIT_CONFIG).symlink_metadata().is_ok() {
        Some("husky (.husky/) and the pre-commit framework (.pre-commit-config.yaml)".to_string())
    } else {
        let tool = if husky { "husky" } else { "the pre-commit framework" };
        // 15a.2: any lefthook source, in any name and format the core reads.
        single_source(repo, "").err().map(|source| format!("{tool} and lefthook ({source})"))
    };
    if let Some(both) = other {
        return alien(format!("the project uses two hook tools: {both}"), "keep only one");
    }
    if husky {
        husky_plan(repo, dir, local)
    } else {
        pre_commit_plan(repo, dir, local)
    }
}

fn husky_plan(repo: &Repo, dir: Option<&str>, local: bool) -> Result<Tool> {
    let old = old_husky(repo);
    let h = fs::read(repo.path(".husky/_/h"));
    if old || dir != Some(".husky/_") || h.is_err() {
        let what = "this project does not use husky 9 (core.hooksPath `.husky/_`, `.husky/_/h`, no `husky.hooks` in package.json)";
        return alien(what.into(), "shipcraft integrates with husky 9: update husky to 9, run `npx husky`");
    }
    if h.is_ok_and(|bytes| bytes.is_empty()) {
        return alien(".husky/_/h is empty: husky installation was interrupted".into(), "run `npx husky`");
    }
    let shipcraft = |l: &&str| matches!(l.split_whitespace().next(), Some("shipcraft" | LOCAL));
    if read(repo, ".husky/pre-commit")?.is_some_and(|t| checks(&t)) {
        return alien(".husky/pre-commit has an `shipcraft check`".into(), TWICE);
    }
    let mut writes = Vec::new();
    for (file, plain) in HUSKY {
        let project = plain.replacen("shipcraft", LOCAL, 1);
        let line = if local { project.as_str() } else { plain };
        let Some(text) = read(repo, file)? else {
            writes.push((file.to_string(), None, format!("{line}\n")));
            continue;
        };
        match text.lines().filter(shipcraft).find(|l| l.trim() != plain && l.trim() != project) {
            Some(other) => {
                return alien(
                    format!("{file} already calls shipcraft another way ({})", other.trim()),
                    &format!("keep only `{line}`"),
                )
            }
            None if text.lines().any(|l| shipcraft(&l)) => {}
            // 25.4: first, after the `#!`: at the end, an `exec` or an `exit 0` would skip it.
            None => {
                let (bang, rest) = match text.split_once('\n') {
                    Some((first, rest)) if first.starts_with("#!") => (format!("{first}\n"), rest),
                    None if text.starts_with("#!") => (format!("{text}\n"), ""),
                    _ => (String::new(), text.as_str()),
                };
                writes.push((file.to_string(), Some(text.clone()), format!("{bang}{line}\n{rest}")));
            }
        }
    }
    let missing = ["commit-msg", "post-commit"]
        .iter()
        .map(|h| format!(".husky/_/{h}"))
        .filter(|l| !is_executable(&repo.path(l)))
        .collect();
    Ok(Tool { name: "husky", writes, missing, install: "npx husky" })
}

fn pre_commit_plan(repo: &Repo, dir: Option<&str>, local: bool) -> Result<Tool> {
    if let Some(dir) = dir.filter(|d| *d != ".git/hooks") {
        return alien(
            format!("core.hooksPath is {dir:?}, and shipcraft only accepts .git/hooks, exactly"),
            "remove core.hooksPath",
        );
    }
    let text = read(repo, PRE_COMMIT_CONFIG)?.unwrap_or_default();
    fn stop<T>(problem: &str) -> Result<T> {
        alien(format!("{PRE_COMMIT_CONFIG} {problem}"), "keep the `repos` list in block style")
    }
    let doc = parse(&text).map_err(|_| ()).or_else(|()| stop("cannot be read as YAML"))?;
    if let Err(problem) = layout(&text, true) {
        return stop(&problem);
    }
    let Some(repos) = doc.get("repos").and_then(Value::as_sequence) else { return stop("has no `repos` list") };
    // 25.3: a hook's stages are its `stages`, if not empty; else the top's
    // `default_stages`, if there (`[]` is none); else all. Not a list of text: does not read.
    let default = match stage_list(doc.get("default_stages")) {
        Ok(list) => list,
        Err(()) => return stop("has an unreadable `default_stages` (not a list of strings)"),
    };
    let mut wanted: Vec<usize> = vec![0, 1];
    for hook in repos.iter().filter_map(|r| r.get("hooks")?.as_sequence()).flatten() {
        let id = hook.get("id").and_then(Value::as_str);
        if let Some(i) = HOOKS.iter().position(|(h, ..)| Some(*h) == id) {
            if *hook != canonical(i, false) && *hook != canonical(i, true) {
                return stop(&format!(
                    "has hook `{}` ({}) different from what shipcraft writes",
                    HOOKS[i].0, HOOKS[i].2
                ));
            }
            wanted.retain(|w| *w != i);
            continue;
        }
        let Ok(own) = stage_list(hook.get("stages")) else {
            return stop("has an unreadable `stages` (not a list of strings)");
        };
        let stages = own.filter(|s| !s.is_empty()).or(default.clone());
        let pre = stages.is_none_or(|s| s.iter().any(|v| matches!(v.as_str(), "pre-commit" | "commit")));
        // The first word as the shell splits it, named `shipcraft` with or without a path, then `check`.
        let Some(words) = shell_words(hook.get("entry").and_then(Value::as_str).unwrap_or_default()) else {
            return stop("has an `entry` that cannot be read as shell words");
        };
        let shipcraft = words.first().is_some_and(|w| w.rsplit('/').next() == Some("shipcraft"));
        if pre && shipcraft && words.get(1).is_some_and(|w| w == "check") {
            return alien(format!("{PRE_COMMIT_CONFIG} has an `shipcraft check` in pre-commit"), TWICE);
        }
    }
    let mut writes = Vec::new();
    if !wanted.is_empty() {
        let new =
            append(&text, &wanted, local).ok_or(()).or_else(|()| stop("cannot prove where to put shipcraft hooks"))?;
        let mut expected = doc.clone();
        let item = parse(&item(&wanted, 0, 1, "\n", local)).ok().and_then(|v| v.as_sequence()?.first().cloned());
        expected.get_mut("repos").and_then(Value::as_sequence_mut).zip(item).map(|(r, i)| r.push(i));
        if !parse(&new).is_ok_and(|back| back == expected) {
            return stop("cannot prove where to put shipcraft hooks without changing the rest");
        }
        writes.push((PRE_COMMIT_CONFIG.to_string(), Some(text), new));
    }
    if fs::read_to_string(repo.hook_path("pre-commit")?).is_ok_and(|t| t.contains("# shipcraft hook") || checks(&t)) {
        return alien("the installed pre-commit hook runs `shipcraft check`".into(), TWICE);
    }
    let mut missing = Vec::new();
    for hook in ["commit-msg", "post-commit"] {
        let path = repo.hook_path(hook)?;
        let shown = path.strip_prefix(repo.root()).unwrap_or(&path).display().to_string();
        if path.symlink_metadata().is_err() {
            missing.push(format!("hook {hook}"));
        } else if !fs::read_to_string(&path).is_ok_and(|t| is_launcher(&t, hook)) {
            return alien(format!("installed hook {hook} ({shown}) is not from pre-commit"), "remove it");
        } else if !is_executable(&path) {
            missing.push(format!("hook {hook}"));
        }
    }
    Ok(Tool { name: "pre-commit", writes, missing, install: "pre-commit install -t commit-msg -t post-commit" })
}

/// A `stages` list: None when absent; a value that is not a list of text is `Err`.
fn stage_list(value: Option<&Value>) -> std::result::Result<Option<Vec<String>>, ()> {
    let Some(value) = value else { return Ok(None) };
    let list = value.as_sequence().ok_or(())?;
    list.iter().map(|v| v.as_str().map(String::from).ok_or(())).collect::<std::result::Result<_, _>>().map(Some)
}

/// The words of `text` as the POSIX shell splits them (quotes and `\`); None
/// when a quote is not closed.
fn shell_words(text: &str) -> Option<Vec<String>> {
    let (mut words, mut word, mut open) = (Vec::new(), None::<String>, None::<char>);
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        match (open, c) {
            (Some(q), c) if c == q => open = None,
            (Some('"'), '\\') => {
                let next = chars.next()?;
                let w = word.get_or_insert_with(String::new);
                if !matches!(next, '"' | '\\' | '$' | '`') {
                    w.push('\\');
                }
                w.push(next);
            }
            (Some(_), c) => word.get_or_insert_with(String::new).push(c),
            (None, '\'' | '"') => {
                open = Some(c);
                word.get_or_insert_with(String::new);
            }
            (None, '\\') => word.get_or_insert_with(String::new).push(chars.next()?),
            (None, c) if c.is_whitespace() => words.extend(word.take()),
            (None, c) => word.get_or_insert_with(String::new).push(c),
        }
    }
    words.extend(word);
    open.is_none().then_some(words)
}

/// 25.4: the script `pre-commit install` writes, for this hook and with the
/// config at the root; one with `-c` for another file is another script.
pub fn is_launcher(script: &str, hook: &str) -> bool {
    script.contains("# File generated by pre-commit")
        && script.contains(&format!("--config={PRE_COMMIT_CONFIG} --hook-type={hook})"))
}

/// A file of the integration as text: None when absent; a link, a file that
/// does not read (no read permission) or that is not text refuses.
fn read(repo: &Repo, file: &str) -> Result<Option<String>> {
    let path = repo.path(file);
    match path.symlink_metadata() {
        Err(_) => return Ok(None),
        Ok(m) if m.file_type().is_symlink() => {
            return alien(format!("{file} is a symbolic link"), "replace it with the file")
        }
        Ok(_) => {}
    }
    match fs::read(&path).map(String::from_utf8) {
        Ok(Ok(text)) if !text.contains('\0') => Ok(Some(text)),
        Ok(_) => alien(format!("{file} is not text"), "replace it with text"),
        Err(e) => alien(format!("cannot read {file} ({e})"), "grant read permission"),
    }
}

fn parse(text: &str) -> std::result::Result<Value, serde_norway::Error> {
    serde_norway::from_str(text.strip_prefix('\u{feff}').unwrap_or(text))
}

/// The hook `i` as the init writes it: exactly its 7 keys.
fn canonical(i: usize, local: bool) -> Value {
    let doc = parse(&item(&[i], 0, 1, "\n", local)).unwrap_or(Value::Null);
    doc.get(0).and_then(|r| r.get("hooks")).and_then(|h| h.get(0)).cloned().unwrap_or(Value::Null)
}

/// A `repo: local` item with the hooks `wanted`, its dash at column `d` and
/// `s` spaces after each dash, in block layout (25.4: `stages` too); `local`, the
/// entry calls `./node_modules/.bin/shipcraft` (item 58).
fn item(wanted: &[usize], d: usize, s: usize, eol: &str, local: bool) -> String {
    let pad = |n: usize| " ".repeat(n);
    let dash = |n: usize| format!("{}-{}", pad(n), pad(s));
    let (k, h) = (d + 1 + s, 2 * d + 2 + 2 * s);
    let mut out = format!("{}repo: local{eol}{}hooks:{eol}", dash(d), pad(k));
    for &i in wanted {
        let (id, entry, stage) = HOOKS[i];
        let name = entry.trim_end_matches(" --commit-msg");
        let entry = if local { entry.replacen("shipcraft", LOCAL, 1) } else { entry.to_string() };
        out += &format!("{}id: {id}{eol}", dash(k + d));
        for line in [format!("name: {name}"), format!("entry: {entry}"), "language: system".into(), "stages:".into()] {
            out += &format!("{}{line}{eol}", pad(h));
        }
        out += &format!("{}{stage}{eol}", dash(h + d));
        out += &format!("{}always_run: true{eol}{}pass_filenames: false{eol}", pad(h), pad(h));
    }
    out
}

/// The text with the item appended at the end of the `repos` list, in the
/// indentation and the line ending the list already uses; None if unproved.
fn append(text: &str, wanted: &[usize], local: bool) -> Option<String> {
    // Every line break the parser reads (YAML 1.1); the first one is the eol.
    let breaks = ['\n', '\r', '\u{85}', '\u{2028}', '\u{2029}'];
    let (mut lines, mut from) = (Vec::new(), 0);
    for (i, c) in text.char_indices().filter(|&(i, c)| breaks.contains(&c) && !text[i..].starts_with("\r\n")) {
        lines.push(&text[from..i + c.len_utf8()]);
        from = i + c.len_utf8();
    }
    lines.extend((from < text.len()).then(|| &text[from..]));
    let eol = lines.first().map_or("", |l| &l[l.trim_end_matches(breaks).len()..]);
    let eol = if eol.is_empty() { "\n" } else { eol };
    let indent = |l: &str| l.len() - l.trim_start_matches(' ').len();
    let content = |l: &str| !l.trim().is_empty() && !l.trim_start().starts_with('#');
    let start = lines.iter().position(|l| l.strip_prefix("repos:").is_some_and(|r| !content(r)))?;
    let first = (start + 1..lines.len()).find(|&i| content(lines[i]))?;
    let (d, rest) = (indent(lines[first]), lines[first].trim_start().strip_prefix('-')?);
    let s = rest.len() - rest.trim_start_matches(' ').len();
    let inside = |l: &str| indent(l) > d || (indent(l) == d && l.trim_start().starts_with('-'));
    let last = (first..lines.len())
        .take_while(|&i| !content(lines[i]) || inside(lines[i]))
        .filter(|&i| content(lines[i]))
        .last()?;
    let mut new = lines[..=last].concat();
    if !new.ends_with(breaks) {
        new += eol;
    }
    Some(new + &item(wanted, d, s.max(1), eol, local) + &lines[last + 1..].concat())
}

/// The writes of `tool` and the `.shipcraft.toml` raise in one transaction: if a
/// write fails, every file written goes back byte by byte (15a.1).
pub fn write(repo: &Repo, tool: &Tool, min: Option<&(String, String)>) -> Result<()> {
    let config = min.map(|(old, new)| (CONFIG_FILE.to_string(), Some(old.clone()), new.clone()));
    let mut done = Vec::new();
    for (file, old, new) in config.iter().chain(&tool.writes) {
        let path = repo.path(file);
        let wrote = fs::write(&path, new);
        done.push((path, old));
        if let Err(e) = wrote {
            for (path, old) in done.iter().rev() {
                let _ = old.as_ref().map_or_else(|| fs::remove_file(path), |old| fs::write(path, old));
            }
            return Err(failed(format!("write {file}: {e}")));
        }
        println!(
            "shipcraft: {} {file}",
            if file == CONFIG_FILE { "raised shipcraft_min (1.2) in" } else { "added shipcraft to" }
        );
    }
    Ok(())
}

/// 25.3, `shipcraft status`: by the tool only when both commands are as the init
/// writes them and both hooks are the tool's; otherwise what is missing.
pub fn status(decided: Result<Tool>) -> String {
    let tool = match decided {
        Ok(tool) => tool,
        Err(Stop::Refused(r)) => return format!("shipcraft: missing hook: `shipcraft init` refuses: {}", r.what()),
        Err(_) => {
            return "shipcraft: missing hook: `shipcraft init` cannot decide the integration; run it to see why".into()
        }
    };
    let mut wants: Vec<String> = tool.writes.iter().map(|(f, ..)| format!("the shipcraft command in {f}")).collect();
    wants.extend(tool.missing.iter().cloned());
    match wants.is_empty() {
        true => format!("shipcraft: hook through {} (commit-msg)", tool.name),
        false => format!(
            "shipcraft: missing hook: missing {}; run `shipcraft init` and `{}`",
            wants.join(", "),
            tool.install
        ),
    }
}

/// Item 25 in `shipcraft init`: what git still has to install, in one line.
pub fn notice(tool: &Tool) {
    if !tool.missing.is_empty() {
        println!(
            "shipcraft: still need to install {}: run `{}` so commits go through `shipcraft check --commit-msg` and `shipcraft close`",
            tool.missing.join(" and "),
            tool.install
        );
    }
}

/// The `hook-alheio` refusal of this route: what keeps the integration, and
/// the commands by hand, never the `pre-commit`.
fn alien<T>(what: String, how: &str) -> Result<T> {
    refuse(
        "foreign-hook",
        what,
        "shipcraft does not replace or edit another tool's hook: when in doubt, this step stays manual",
        format!("{how} and run `shipcraft init` again, or manually put `shipcraft check --commit-msg` in commit-msg and `shipcraft close` in post-commit"),
    )
}
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn appends_in_the_list_indentation() {
        let text = "repos:\n-   repo: x\n    hooks:\n    -   id: y\n        stages: [pre-commit]\ndefault_stages: [pre-commit]\n";
        let new = append(text, &[0, 1], false).unwrap();
        assert!(new.starts_with(text.trim_end_matches("default_stages: [pre-commit]\n")));
        assert!(
            new.contains("-   repo: local\n    hooks:\n    -   id: shipcraft-check\n        name: shipcraft check\n")
        );
        assert!(new.ends_with("default_stages: [pre-commit]\n"));
        let doc = parse(&new).unwrap();
        assert_eq!(doc["repos"][1]["hooks"][1], canonical(1, false));
        assert_eq!(doc["repos"][1]["hooks"][0]["stages"][0], Value::from("commit-msg"));
    }
}
