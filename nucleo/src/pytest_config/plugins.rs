//! Item 156, point 1: the project files pytest loads as plugins in each
//! source snapshot (the judged one and its parents): the watched conftests,
//! the modules named by `-p` (in the command and the configs' `addopts`) or
//! by `pytest_plugins`, found in the suites' roots and `pythonpath` folders,
//! and any linked folder on a candidate's path.

use super::{file_name, folder, header, holds, ini_section, split_lines, watched};
use crate::config::Suite;
use crate::git::{Repo, Snapshot};
use crate::refusal::Result;
use std::collections::{BTreeSet, HashMap, HashSet};

/// The plugin files of every source snapshot, each once, in bytewise order.
pub(super) fn files(
    repo: &Repo,
    suites: &[Suite],
    sources: &[&Snapshot],
    lists: &[Vec<String>],
) -> Result<BTreeSet<String>> {
    let known: HashSet<&str> = lists.iter().flatten().map(String::as_str).collect();
    let mut found = BTreeSet::new();
    for (snapshot, list) in sources.iter().zip(lists) {
        let mut source = Source {
            repo,
            snapshot,
            present: list.iter().map(String::as_str).collect(),
            known: &known,
            modes: HashMap::new(),
            found: &mut found,
        };
        source.discover(suites, list)?;
    }
    Ok(found)
}

struct Source<'a, 'b> {
    repo: &'a Repo,
    snapshot: &'a Snapshot,
    present: HashSet<&'a str>,
    known: &'a HashSet<&'a str>,
    modes: HashMap<String, Option<String>>,
    found: &'b mut BTreeSet<String>,
}

impl Source<'_, '_> {
    fn linked(&mut self, path: &str) -> Result<bool> {
        if !self.modes.contains_key(path) {
            let mode = self.repo.mode(self.snapshot, path)?;
            self.modes.insert(path.to_string(), mode);
        }
        Ok(self.modes[path].as_deref() == Some("120000"))
    }

    /// The bytes of a present file that is not a symbolic link.
    fn bytes(&mut self, path: &str) -> Result<Option<Vec<u8>>> {
        if !self.present.contains(path) || self.linked(path)? {
            return Ok(None);
        }
        self.repo.read(self.snapshot, path)
    }

    fn discover(&mut self, suites: &[Suite], list: &[String]) -> Result<()> {
        let roots: Vec<String> = suites.iter().map(|suite| suite.raiz.clone()).collect();
        let mut bases = roots.clone();
        let (mut names, mut overrides) = (Vec::new(), Vec::new());
        let configs = watched(suites, list);
        for config in &configs {
            let Some(Ok(text)) = self.bytes(config)?.map(String::from_utf8) else { continue };
            let (addopts, pythonpath) = config_values(file_name(config), &text);
            bases.extend(pythonpath.iter().filter_map(|entry| join(folder(config), entry)));
            for args in &addopts {
                read_args(args, &mut names, &mut overrides, &roots);
            }
        }
        for suite in suites {
            read_args(&split(&suite.comando), &mut names, &mut overrides, std::slice::from_ref(&suite.raiz));
        }
        let folders: Vec<&str> = configs.iter().map(|config| folder(config)).collect();
        for (entry, roots) in &overrides {
            let all = roots.iter().map(String::as_str).chain(folders.iter().copied());
            bases.extend(all.filter_map(|base| join(base, entry)));
        }
        let conftests: Vec<&String> = list
            .iter()
            .filter(|path| file_name(path) == "conftest.py" && suites.iter().any(|s| holds(s, path)))
            .collect();
        let mut py_bases = bases.clone();
        for conftest in &conftests {
            self.found.insert(conftest.to_string());
            py_bases.push(self.package_root(folder(conftest)));
        }
        let mut queue: Vec<String> = Vec::new();
        for name in &names {
            self.resolve(name, &bases, &mut queue)?;
        }
        queue.extend(conftests.into_iter().cloned());
        let mut read = HashSet::new();
        while let Some(file) = queue.pop() {
            if !read.insert(file.clone()) {
                continue;
            }
            let Some(bytes) = self.bytes(&file)? else { continue };
            let text = String::from_utf8_lossy(&bytes);
            let mut here = py_bases.clone();
            here.push(folder(&file).to_string());
            for name in pytest_plugins(&text) {
                self.resolve(&name, &here, &mut queue)?;
            }
        }
        Ok(())
    }

    /// From the conftest's folder, up while the folder holds an `__init__.py`.
    fn package_root(&self, start: &str) -> String {
        let mut dir = start;
        while !dir.is_empty() && self.present.contains(within(dir, "__init__.py").as_str()) {
            dir = folder(dir);
        }
        dir.to_string()
    }

    /// Each candidate of `name` in each base: a plugin file when a snapshot
    /// holds it (read in turn when this one does), and its linked folders.
    fn resolve(&mut self, name: &str, bases: &[String], queue: &mut Vec<String>) -> Result<()> {
        for base in bases {
            for candidate in candidates(name, base) {
                let mut at = 0;
                while let Some(slash) = candidate[at..].find('/') {
                    let dir = &candidate[..at + slash];
                    if self.present.contains(dir) && self.linked(dir)? {
                        self.found.insert(dir.to_string());
                    }
                    at += slash + 1;
                }
                if self.known.contains(candidate.as_str()) {
                    self.found.insert(candidate.clone());
                }
                if self.present.contains(candidate.as_str()) {
                    queue.push(candidate);
                }
            }
        }
        Ok(())
    }
}

fn within(base: &str, rest: &str) -> String {
    if base.is_empty() {
        rest.to_string()
    } else {
        format!("{base}/{rest}")
    }
}

/// `entry` joined to `base`: `.` and empty segments dropped, `..` removing
/// the one before; None from `/` or above the repository root.
fn join(base: &str, entry: &str) -> Option<String> {
    if entry.starts_with('/') {
        return None;
    }
    let mut parts: Vec<&str> = Vec::new();
    for part in base.split('/').chain(entry.split('/')) {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop()?;
            }
            _ => parts.push(part),
        }
    }
    Some(parts.join("/"))
}

/// Each package's `__init__.py`, the module and the package of a valid name.
fn candidates(name: &str, base: &str) -> Vec<String> {
    let parts: Vec<&str> = name.split('.').collect();
    let valid = |part: &&str| {
        part.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_')
            && part.bytes().next().is_some_and(|b| !b.is_ascii_digit())
    };
    if !parts.iter().all(valid) {
        return Vec::new();
    }
    let mut found: Vec<String> = (1..parts.len()).map(|n| format!("{}/__init__.py", parts[..n].join("/"))).collect();
    let whole = parts.join("/");
    found.push(format!("{whole}.py"));
    found.push(format!("{whole}/__init__.py"));
    found.into_iter().map(|path| within(base, &path)).collect()
}

/// A config's `addopts` lists and `pythonpath` entries.
fn config_values(name: &str, text: &str) -> (Vec<Vec<String>>, Vec<String>) {
    let section = match name {
        "setup.cfg" => "tool:pytest",
        "pytest.ini" | ".pytest.ini" | "tox.ini" => "pytest",
        _ => return toml_values(name, text),
    };
    let section = ini_section(text, section).unwrap_or_default();
    let addopts = ini_values(&section, "addopts").iter().map(|value| split(value)).collect();
    (addopts, ini_values(&section, "pythonpath").iter().flat_map(|value| split(value)).collect())
}

fn toml_values(name: &str, text: &str) -> (Vec<Vec<String>>, Vec<String>) {
    let Ok(table) = text.parse::<toml::Table>() else { return Default::default() };
    let tables: Vec<&toml::Value> = if name == "pyproject.toml" {
        let pytest = table.get("tool").and_then(|tool| tool.get("pytest"));
        pytest.into_iter().flat_map(|pytest| [pytest.get("ini_options"), Some(pytest)]).flatten().collect()
    } else {
        table.get("pytest").into_iter().collect()
    };
    let list = |value: &toml::Value| match value {
        toml::Value::String(text) => split(text),
        toml::Value::Array(items) => items.iter().filter_map(|item| item.as_str().map(str::to_string)).collect(),
        _ => Vec::new(),
    };
    let addopts = tables.iter().filter_map(|t| t.get("addopts")).map(list).collect();
    (addopts, tables.iter().filter_map(|t| t.get("pythonpath")).flat_map(list).collect())
}

/// Every value of `key` in a section's text, as `iniconfig` 2.x classifies lines.
fn ini_values(section: &str, key: &str) -> Vec<String> {
    let (mut values, mut current): (Vec<String>, Option<String>) = (Vec::new(), None);
    for (line, _) in split_lines(section) {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with(['#', ';']) {
            continue;
        }
        let is_header = header(line).is_some();
        if line.starts_with(char::is_whitespace) || (line.starts_with('[') && !is_header) {
            if let Some(value) = current.as_mut() {
                value.push('\n');
                value.push_str(trimmed);
            }
            continue;
        }
        values.extend(current.take());
        if let Some(at) = line.find(['=', ':']).filter(|_| !is_header) {
            if line[..at].trim() == key {
                current = Some(line[at + 1..].trim().to_string());
            }
        }
    }
    values.extend(current);
    values
}

/// Python's `shlex.split`; whitespace splitting when it would fail.
fn split(text: &str) -> Vec<String> {
    const SPACE: [char; 4] = [' ', '\t', '\r', '\n'];
    let fallback = || text.split(SPACE).filter(|part| !part.is_empty()).map(str::to_string).collect();
    let (mut args, mut word, mut started) = (Vec::new(), String::new(), false);
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        match c {
            _ if SPACE.contains(&c) => {
                if started {
                    args.push(std::mem::take(&mut word));
                    started = false;
                }
                continue;
            }
            '\\' => word.push(match chars.next() {
                Some(next) => next,
                None => return fallback(),
            }),
            '\'' => loop {
                match chars.next() {
                    Some('\'') => break,
                    Some(inner) => word.push(inner),
                    None => return fallback(),
                }
            },
            '"' => loop {
                match chars.next() {
                    Some('"') => break,
                    Some('\\') => match chars.next() {
                        Some(next @ ('"' | '\\')) => word.push(next),
                        Some(next) => word.extend(['\\', next]),
                        None => return fallback(),
                    },
                    Some(inner) => word.push(inner),
                    None => return fallback(),
                }
            },
            _ => word.push(c),
        }
        started = true;
    }
    if started {
        args.push(word);
    }
    args
}

/// Reads `-p` names and `-o` overrides from one list of arguments: an
/// `addopts` override's value is read for `-p`, a `pythonpath` one's entries
/// are kept with the roots they join.
fn read_args(args: &[String], names: &mut Vec<String>, overrides: &mut Vec<(String, Vec<String>)>, roots: &[String]) {
    p_names(args, names);
    let mut rest = args.iter();
    while let Some(arg) = rest.next() {
        let given = match arg.as_str() {
            "-o" | "--override-ini" => rest.next().map(String::as_str),
            _ if arg.starts_with("--override-ini=") => Some(&arg["--override-ini=".len()..]),
            _ if arg.starts_with("-o") && arg.len() > 2 => Some(&arg[2..]),
            _ => None,
        };
        let Some((key, value)) = given.and_then(|text| text.split_once('=')) else { continue };
        match key.trim() {
            "addopts" => p_names(&split(value), names),
            "pythonpath" => overrides.extend(split(value).into_iter().map(|entry| (entry, roots.to_vec()))),
            _ => {}
        }
    }
}

/// pytest's `consider_preparse`: `-p <name>` and `-p<name>`, trimmed; `no:` names nothing.
fn p_names(args: &[String], names: &mut Vec<String>) {
    let mut rest = args.iter();
    while let Some(arg) = rest.next() {
        let name = match arg.as_str() {
            "-p" => rest.next().map(String::as_str),
            _ if arg.starts_with("-p") => Some(&arg[2..]),
            _ => None,
        };
        if let Some(name) = name.map(str::trim).filter(|name| !name.starts_with("no:")) {
            names.push(name.to_string());
        }
    }
}

/// The names of every readable `pytest_plugins` assignment in Python text.
fn pytest_plugins(text: &str) -> Vec<String> {
    let text = text.replace("\r\n", "\n").replace('\r', "\n");
    let b = text.as_bytes();
    let mut names = Vec::new();
    let mut i = 0;
    while i < b.len() {
        if (i == 0 || b[i - 1] == b'\n') && b[i..].starts_with(b"pytest_plugins") {
            if let Some(value) = assignment(b, i + "pytest_plugins".len()) {
                names.extend(read_value(&text, value));
            }
        }
        i = match b[i] {
            b'#' => line_end(b, i),
            b'\'' | b'"' => literal(b, i).0,
            _ => i + 1,
        };
    }
    names
}

fn line_end(b: &[u8], i: usize) -> usize {
    b[i..].iter().position(|&c| c == b'\n').map_or(b.len(), |at| i + at)
}

fn blank(b: &[u8], mut i: usize) -> usize {
    while i < b.len() && matches!(b[i], b' ' | b'\t') {
        i += 1;
    }
    i
}

/// A string literal at the quote `b[i]`: its end, and whether it is closed,
/// triple-quoted and free of backslashes.
fn literal(b: &[u8], i: usize) -> (usize, bool, bool, bool) {
    let quote = b[i];
    let triple = b[i..].starts_with(&[quote; 3]);
    let (mut at, mut clean) = (if triple { i + 3 } else { i + 1 }, true);
    while at < b.len() {
        match b[at] {
            b'\\' => {
                clean = false;
                at += 2;
                continue;
            }
            b'\n' if !triple => return (at, false, false, clean),
            c if c == quote && (!triple || b[at..].starts_with(&[quote; 3])) => {
                return (at + if triple { 3 } else { 1 }, true, triple, clean);
            }
            _ => {}
        }
        at += 1;
    }
    (b.len(), false, triple, clean)
}

/// After the word at a line's start: where the assigned value starts.
fn assignment(b: &[u8], at: usize) -> Option<usize> {
    if b.get(at).is_none_or(|c| c.is_ascii_alphanumeric() || *c == b'_') {
        return None;
    }
    let mut i = blank(b, at);
    match b.get(i)? {
        b'=' if b.get(i + 1) != Some(&b'=') => return Some(i + 1),
        b':' => {}
        _ => return None,
    }
    let mut depth = 0usize;
    i += 1;
    while i < b.len() {
        match b[i] {
            b'\n' | b'#' => return None,
            b'\'' | b'"' => {
                i = literal(b, i).0;
                continue;
            }
            b'(' | b'[' | b'{' => depth += 1,
            b')' | b']' | b'}' => depth = depth.saturating_sub(1),
            b'=' if b.get(i + 1) == Some(&b'=') => i += 1,
            b'=' if depth == 0 => return Some(i + 1),
            _ => {}
        }
        i += 1;
    }
    None
}

/// A plain literal at `i`: its content and its end.
fn plain(text: &str, i: usize) -> Option<(&str, usize)> {
    let b = text.as_bytes();
    if !matches!(b.get(i), Some(b'\'' | b'"')) {
        return None;
    }
    let (end, closed, triple, clean) = literal(b, i);
    (closed && !triple && clean).then(|| (&text[i + 1..end - 1], end))
}

/// Spaces, tabs, an optional comment, then the end of the line or file.
fn ends_line(b: &[u8], i: usize) -> bool {
    let i = blank(b, i);
    i == b.len() || matches!(b[i], b'\n' | b'#')
}

/// Spaces, tabs, line ends and comments.
fn space(b: &[u8], mut i: usize) -> usize {
    loop {
        i = blank(b, i);
        match b.get(i) {
            Some(b'\n') => i += 1,
            Some(b'#') => i = line_end(b, i),
            _ => return i,
        }
    }
}

fn read_value(text: &str, at: usize) -> Vec<String> {
    let b = text.as_bytes();
    let i = blank(b, at);
    let parts = |content: &str| content.split(',').map(str::to_string).collect();
    if let Some((content, end)) = plain(text, i) {
        return if ends_line(b, end) { parts(content) } else { Vec::new() };
    }
    let close = match b.get(i) {
        Some(b'[') => b']',
        Some(b'(') => b')',
        _ => return Vec::new(),
    };
    let (mut items, mut commas, mut j) = (Vec::new(), 0, space(b, i + 1));
    loop {
        if b.get(j) == Some(&close) {
            break;
        }
        let Some((content, end)) = plain(text, j) else { return Vec::new() };
        items.push(content.to_string());
        j = space(b, end);
        match b.get(j) {
            Some(b',') => {
                commas += 1;
                j = space(b, j + 1);
            }
            Some(&c) if c == close => break,
            _ => return Vec::new(),
        }
    }
    if !ends_line(b, j + 1) {
        return Vec::new();
    }
    match (close, items.as_slice(), commas) {
        (b')', [one], 0) => parts(one),
        _ => items,
    }
}

#[cfg(test)]
mod tests;
