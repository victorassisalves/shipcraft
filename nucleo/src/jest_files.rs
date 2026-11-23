//! Item 140: the files Jest reads beside the tests. `red` locks the Jest
//! configs of every Jest suite, the modules they import by relative path and
//! the setup files they name, reading `package.json`'s `jest` key too; it
//! refuses what it cannot read (`setup-unreadable`). The hook and CI refuse an
//! added Jest config (`runner-config-added`, in `vitest_files::check_added`)
//! and a changed `jest` key (`jest-config-changed`). Item 155: `red` also
//! locks the files the module keys name and reads a relative `preset`.

use crate::config::{Config, Suite};
use crate::git::{Repo, Snapshot};
use crate::jsonc;
use crate::pytest_config::{all_paths, holds, Judge, Settings};
use crate::red::one_line;
use crate::refusal::{failed, refuse, Result};
use crate::vitest_files::scan::{self, Event, Item, Modules, Read};
use crate::vitest_files::{folder, join, kind, relative, Found, Kind, JS_EXTS};
use serde_json::{Map, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;

/// The extensions of a Jest config name.
const CONFIG_EXTS: [&str; 7] = ["ts", "mts", "cts", "js", "mjs", "cjs", "json"];

/// Item 155: the keys whose values name modules Jest loads, in order; in
/// JSON, `hasteImplModulePath` is read inside `haste`.
const MODULE_KEYS: [&str; 17] = [
    "snapshotSerializers",
    "testEnvironment",
    "transform",
    "moduleNameMapper",
    "resolver",
    "snapshotResolver",
    "testSequencer",
    "testRunner",
    "runner",
    "runtime",
    "testResultsProcessor",
    "reporters",
    "watchPlugins",
    "dependencyExtractor",
    "filter",
    "prettierPath",
    "hasteImplModulePath",
];

/// Item 155: what a Jest config module's scan reads besides item 140's keys;
/// inside a preset, `preset` is not read.
const DATA_KEYS: &[&str] = &["globals", "testEnvironmentOptions"];
const IN_CONFIG: Modules = Modules { keys: &MODULE_KEYS, single: Some("preset"), data: DATA_KEYS };
const IN_PRESET: Modules = Modules { keys: &MODULE_KEYS, single: None, data: DATA_KEYS };

/// The suites whose command contains `jest`.
pub fn suites(config: &Config) -> Vec<Suite> {
    config.suites().into_iter().filter(|suite| suite.comando.contains("jest")).collect()
}

/// A path of `repo.files()` named `name(last component)`, with no component
/// `node_modules`, under a suite's root or directly in a folder that holds it.
fn watched(suites: &[Suite], paths: &[String], name: impl Fn(&str) -> bool) -> BTreeSet<String> {
    paths
        .iter()
        .filter(|path| !path.split('/').any(|part| part == "node_modules"))
        .filter(|path| name(path.rsplit('/').next().unwrap_or(path)))
        .filter(|path| suites.iter().any(|suite| holds(suite, path)))
        .cloned()
        .collect()
}

fn config_name(name: &str) -> bool {
    name.rsplit_once('.').is_some_and(|(stem, ext)| stem == "jest.config" && CONFIG_EXTS.contains(&ext))
}

/// Point 1: the locked Jest configs of `suites` among `paths`.
pub fn configs(suites: &[Suite], paths: &[String]) -> BTreeSet<String> {
    watched(suites, paths, config_name)
}

/// Point 1: the watched manifests of `suites` among `paths`.
fn manifests(suites: &[Suite], paths: &[String]) -> BTreeSet<String> {
    watched(suites, paths, |name| name == "package.json")
}

/// How an options object may set its root folder.
#[derive(Clone, Copy, PartialEq)]
enum RootRule {
    /// A Jest config or a manifest's `jest` object: a relative string.
    Own,
    /// A `.json` module reached by an import: none.
    Forbidden,
    /// An inline `projects` object: `<rootDir>` is the parent's root folder.
    Project,
}

/// A module to read: its path, None for a locked config or the root folder of
/// the config that reached it, and whether it was reached from a preset.
type Module = (String, Option<String>, bool);

struct Discovery<'a> {
    repo: &'a Repo,
    present: BTreeSet<String>,
    paths: BTreeSet<String>,
    /// The first reason of each read, by path, then by root folder (a read as
    /// a preset after the other read with the same root folder).
    why: BTreeMap<String, BTreeMap<(String, bool), String>>,
    queue: Vec<Module>,
    seen: BTreeSet<Module>,
}

/// Point 1's discovery on the working tree, run to the end.
pub fn discover(repo: &Repo, config: &Config) -> Result<Found> {
    let suites = suites(config);
    if suites.is_empty() {
        return Ok(Found::default());
    }
    let listed = repo.files()?;
    let mut d = Discovery {
        repo,
        present: listed.iter().cloned().collect(),
        paths: BTreeSet::new(),
        why: BTreeMap::new(),
        queue: Vec::new(),
        seen: BTreeSet::new(),
    };
    for path in configs(&suites, &listed) {
        match kind(repo, &path)? {
            Kind::File => d.push(path, None, false),
            Kind::Link => d.note(&path, folder(&path), false, format!("{} is a symbolic link", one_line(&path))),
            Kind::Folder => {}
        }
    }
    for path in manifests(&suites, &listed) {
        if !matches!(kind(repo, &path)?, Kind::Folder) {
            d.manifest(&path)?;
        }
    }
    while let Some((module, root, preset)) = d.queue.pop() {
        d.read(&module, root, preset)?;
    }
    let unreadable = d.why.into_iter().next().and_then(|(path, reads)| Some((path, reads.into_values().next()?)));
    Ok(Found { paths: d.paths, unreadable })
}

/// A literal with a leading `<rootDir>/` replaced by `./`, `<rootDir>` alone by `.`.
fn replaced(literal: &str) -> String {
    match literal.strip_prefix("<rootDir>") {
        Some("") => ".".to_string(),
        Some(rest) if rest.starts_with('/') => format!(".{rest}"),
        _ => literal.to_string(),
    }
}

/// Item 155: the path a module item names before its candidates, with its
/// literal: a literal joined to `root` (`<rootDir>` replaced; one without
/// `./`, `../` or `<rootDir>` only when `packages`), a relative
/// `require.resolve` joined to `own`, None when it joins above the repository
/// root; None names nothing, an absolute literal is a reason.
fn target<'i>(
    item: &'i Item,
    root: &str,
    own: &str,
    packages: bool,
    first: &mut Option<String>,
) -> Option<(&'i str, Option<String>)> {
    let (literal, folder, content) = match item {
        Item::Literal(literal) if literal.starts_with('/') => {
            first.get_or_insert_with(|| format!("{} is an absolute path", one_line(literal)));
            return None;
        }
        Item::Literal(literal) if packages || relative(literal) || literal.starts_with("<rootDir>") => {
            (literal, root, replaced(literal))
        }
        Item::Resolve(literal) if relative(literal) => (literal, own, literal.clone()),
        Item::Literal(_) | Item::Resolve(_) => return None,
    };
    Some((literal, join(folder, &content)))
}

/// Item 155: a `moduleNameMapper` literal holds `$` and a digit (`$1`).
fn captures(literal: &str) -> bool {
    literal.as_bytes().windows(2).any(|pair| pair[0] == b'$' && pair[1].is_ascii_digit())
}

/// Item 155: the module literals of a JSON module key's value: a string, an
/// array's strings and its tuples' strings, an object's values read as array
/// items (in `serde_json`'s map order).
fn json_items(value: &Value) -> Vec<&str> {
    fn strings(value: &Value) -> Vec<&str> {
        match value {
            Value::String(one) => vec![one.as_str()],
            Value::Array(items) => items.iter().filter_map(Value::as_str).collect(),
            _ => Vec::new(),
        }
    }
    match value {
        Value::String(one) => vec![one.as_str()],
        Value::Array(items) => items.iter().flat_map(strings).collect(),
        Value::Object(map) => map.values().flat_map(strings).collect(),
        _ => Vec::new(),
    }
}

/// The root folder a root key's value names from `folder`: `None` is the
/// config's folder; a literal not starting with `/` is joined to it.
fn root_of(folder: &str, value: &Option<String>) -> Option<String> {
    match value {
        None => Some(folder.to_string()),
        Some(literal) if literal.starts_with('/') => None,
        Some(literal) => join(folder, literal),
    }
}

impl Discovery<'_> {
    fn push(&mut self, module: String, root: Option<String>, preset: bool) {
        if self.seen.insert((module.clone(), root.clone(), preset)) {
            self.queue.push((module, root, preset));
        }
    }

    fn note(&mut self, path: &str, root: &str, preset: bool, reason: String) {
        self.why.entry(path.to_string()).or_default().entry((root.to_string(), preset)).or_insert(reason);
    }

    /// The candidates of `base` that are repository files (a link is a reason).
    fn candidates(&self, base: &str, json: bool, first: &mut Option<String>) -> Result<(bool, Vec<String>)> {
        let exts = JS_EXTS.iter().copied().chain(json.then_some("json"));
        self.qualify(std::iter::once(base.to_string()).chain(exts.map(|ext| format!("{base}.{ext}"))), first)
    }

    /// Which of `all` are repository files, and whether any is in the
    /// repository (a folder is skipped, a link is a reason).
    fn qualify(&self, all: impl Iterator<Item = String>, first: &mut Option<String>) -> Result<(bool, Vec<String>)> {
        let (mut named, mut files) = (false, Vec::new());
        for candidate in all.filter(|c| self.present.contains(c)) {
            match kind(self.repo, &candidate)? {
                Kind::File => files.push(candidate),
                Kind::Link => {
                    first.get_or_insert_with(|| format!("{} is a symbolic link", one_line(&candidate)));
                }
                Kind::Folder => continue,
            }
            named = true;
        }
        Ok((named, files))
    }

    /// A setup literal, resolved against `root` with `<rootDir>` replaced.
    fn setup(&mut self, literal: &str, root: &str, first: &mut Option<String>) -> Result<()> {
        if literal.starts_with('/') {
            first.get_or_insert_with(|| format!("{} is an absolute path", one_line(literal)));
            return Ok(());
        }
        let Some(base) = join(root, &replaced(literal)) else { return Ok(()) };
        let (named, files) = self.candidates(&base, false, first)?;
        self.paths.extend(files);
        if !named && (relative(literal) || literal.starts_with("<rootDir>")) {
            first.get_or_insert_with(|| format!("{} names no file in the repository", one_line(literal)));
        }
        Ok(())
    }

    /// Item 155: a module item of `key`, a literal resolved like a setup
    /// literal or a `require.resolve` resolved from the module's folder `own`;
    /// the candidates also follow the path with `/index`.
    fn module(&mut self, key: &str, item: Item, root: &str, own: &str, first: &mut Option<String>) -> Result<()> {
        let mapper = key == "moduleNameMapper";
        if let (true, Item::Literal(literal)) = (mapper, &item) {
            if !literal.starts_with("<rootDir>") || captures(literal) {
                return Ok(());
            }
        }
        // Above the repository root a module literal names nothing (item 140).
        let Some((literal, Some(base))) = target(&item, root, own, true, first) else { return Ok(()) };
        let index = join(&base, "index").expect("a join below base");
        let (named, files) = self.candidates(&base, false, first)?;
        let (indexed, more) = self.candidates(&index, false, first)?;
        self.paths.extend(files.into_iter().chain(more));
        if !named && !indexed && !mapper && (relative(literal) || literal.starts_with("<rootDir>")) {
            first.get_or_insert_with(|| format!("{} names no file in the repository", one_line(literal)));
        }
        Ok(())
    }

    /// Item 155: a relative preset; every candidate in the repository is locked
    /// and read as a module the config imports, from the config's root folder.
    fn preset(&mut self, item: Item, root: &str, own: &str, first: &mut Option<String>) -> Result<()> {
        let Some((literal, base)) = target(&item, root, own, false, first) else { return Ok(()) };
        let Some(base) = base else {
            // A relative preset above the repository root has no candidate in it.
            first.get_or_insert_with(|| format!("{} names no file in the repository", one_line(literal)));
            return Ok(());
        };
        let exts = ["json", "js", "cjs", "mjs"];
        let all = std::iter::once(base.clone())
            .chain(exts.iter().map(|ext| format!("{base}.{ext}")))
            .chain(exts.iter().filter_map(|ext| join(&base, &format!("jest-preset.{ext}"))));
        let (named, files) = self.qualify(all, first)?;
        for file in files {
            self.push(file, Some(root.to_string()), true);
        }
        if !named {
            first.get_or_insert_with(|| format!("{} names no file in the repository", one_line(literal)));
        }
        Ok(())
    }

    /// One read of a module: a locked config (`inherited` None) or a module
    /// reached by an import from a config whose root folder is `inherited`.
    fn read(&mut self, module: &str, inherited: Option<String>, preset: bool) -> Result<()> {
        self.paths.insert(module.to_string());
        let ext = module.rsplit_once('.').map_or("", |(_, ext)| ext);
        if ext != "json" && !JS_EXTS.contains(&ext) {
            return Ok(());
        }
        let bytes = fs::read(self.repo.path(module)).map_err(|e| failed(format!("read {module}: {e}")))?;
        let own = folder(module);
        let mut first = None;
        let root = if ext == "json" {
            let text = std::str::from_utf8(&bytes).ok();
            let parsed = match &inherited {
                None => text.and_then(jsonc::parse),
                Some(_) => text.and_then(|text| serde_json::from_str(text).ok()),
            };
            let base = inherited.clone().unwrap_or_else(|| own.to_string());
            match parsed {
                Some(Value::Object(map)) => {
                    let rule = if inherited.is_some() { RootRule::Forbidden } else { RootRule::Own };
                    self.options(&map, &base, rule, preset, &mut first)?
                }
                _ => {
                    first = Some("it is not a JSON object".to_string());
                    base
                }
            }
        } else {
            self.script(module, &bytes, &inherited, preset, &mut first)?
        };
        if let Some(reason) = first {
            self.note(module, &root, preset, reason);
        }
        Ok(())
    }

    /// A JavaScript module, scanned with Jest's keys; returns its root folder.
    fn script(
        &mut self,
        module: &str,
        bytes: &[u8],
        inherited: &Option<String>,
        preset: bool,
        first: &mut Option<String>,
    ) -> Result<String> {
        let own = folder(module);
        let modules = if preset { &IN_PRESET } else { &IN_CONFIG };
        let events = scan::scan_with(&String::from_utf8_lossy(bytes), &scan::JEST, modules);
        let first_root =
            events.iter().find_map(|e| if let Read::Event(Event::Root(value)) = e { Some(value) } else { None });
        let root = match inherited {
            Some(root) => root.clone(),
            None => first_root.and_then(|value| root_of(own, value)).unwrap_or_else(|| own.to_string()),
        };
        let mut roots = 0;
        for event in events {
            let event = match event {
                Read::Event(event) => event,
                Read::Module("preset", item) => {
                    self.preset(item, &root, own, first)?;
                    continue;
                }
                Read::Module(key, item) => {
                    self.module(key, item, &root, own, first)?;
                    continue;
                }
            };
            match event {
                Event::Bad(reason) => {
                    first.get_or_insert(reason);
                }
                Event::Root(value) => {
                    roots += 1;
                    if inherited.is_some() || roots > 1 || root_of(own, &value).is_none() {
                        first.get_or_insert_with(|| "it sets rootDir".to_string());
                    }
                }
                Event::Setup(literal) => self.setup(&literal, &root, first)?,
                Event::Import(content) if relative(&content) => {
                    let Some(base) = join(own, &content) else { continue };
                    let (named, files) = self.candidates(&base, true, first)?;
                    for file in files {
                        self.push(file, Some(root.clone()), preset);
                    }
                    if !named {
                        first.get_or_insert_with(|| format!("{} names no file in the repository", one_line(&content)));
                    }
                }
                Event::Import(_) => {}
            }
        }
        Ok(root)
    }

    /// The JSON reader: an options object's `rootDir`, its setup keys, its
    /// `preset` (not inside a preset), its module keys and its `projects`
    /// objects, depth first; returns its root folder.
    fn options(
        &mut self,
        map: &Map<String, Value>,
        base: &str,
        rule: RootRule,
        preset: bool,
        first: &mut Option<String>,
    ) -> Result<String> {
        let root = match (map.get("rootDir"), rule) {
            (None, _) => Some(base.to_string()),
            (Some(Value::String(dir)), RootRule::Own) if !dir.starts_with('/') => join(base, dir),
            (Some(Value::String(dir)), RootRule::Project) if !dir.starts_with('/') => {
                join(base, dir.strip_prefix("<rootDir>").unwrap_or(dir))
            }
            _ => None,
        };
        let root = root.unwrap_or_else(|| {
            first.get_or_insert_with(|| "it sets rootDir".to_string());
            base.to_string()
        });
        for key in scan::JEST.setup {
            let literals = match map.get(*key) {
                None => continue,
                Some(Value::String(one)) => vec![one.as_str()],
                Some(Value::Array(items)) if items.iter().all(Value::is_string) => {
                    items.iter().filter_map(Value::as_str).collect()
                }
                Some(_) => {
                    first.get_or_insert_with(|| format!("{key} is not a string or an array of strings"));
                    continue;
                }
            };
            for literal in literals {
                self.setup(literal, &root, first)?;
            }
        }
        if let Some(Value::String(named)) = map.get("preset").filter(|_| !preset) {
            self.preset(Item::Literal(named.clone()), &root, "", first)?;
        }
        let haste = map.get("haste").and_then(Value::as_object);
        for key in MODULE_KEYS {
            let value = if key == "hasteImplModulePath" { haste.and_then(|h| h.get(key)) } else { map.get(key) };
            for literal in value.map(json_items).unwrap_or_default() {
                self.module(key, Item::Literal(literal.to_string()), &root, "", first)?;
            }
        }
        if let Some(Value::Array(projects)) = map.get("projects") {
            for project in projects.iter().filter_map(Value::as_object) {
                self.options(project, &root, RootRule::Project, preset, first)?;
            }
        }
        Ok(root)
    }

    /// A watched manifest: its `jest` object, read when it parses.
    fn manifest(&mut self, path: &str) -> Result<()> {
        let bytes = fs::read(self.repo.path(path)).map_err(|e| failed(format!("read {path}: {e}")))?;
        let parsed = std::str::from_utf8(&bytes).ok().and_then(|text| serde_json::from_str(text).ok());
        let Some(Value::Object(map)) = parsed else { return Ok(()) };
        let Some(jest) = map.get("jest") else { return Ok(()) };
        let mut first = None;
        let own = folder(path);
        match jest {
            Value::Object(options) => {
                self.options(options, own, RootRule::Own, false, &mut first)?;
            }
            _ => first = Some("its jest key is not an object".to_string()),
        }
        if let Some(reason) = first {
            self.note(path, own, false, reason);
        }
        Ok(())
    }
}

/// Point 2: the first unreadable module of both runners in bytewise path
/// order (vitest's wording when the path is both runners').
pub fn refuse_first(vitest: &Found, jest: &Found) -> Result<()> {
    match (&vitest.unreadable, &jest.unreadable) {
        (Some((v, _)), Some((j, why))) if j < v => refuse_unreadable(j, why),
        (Some((v, why)), _) => crate::vitest_files::refuse_unreadable(v, why),
        (None, Some((j, why))) => refuse_unreadable(j, why),
        (None, None) => Ok(()),
    }
}

fn refuse_unreadable<T>(config: &str, why: &str) -> Result<T> {
    let config = one_line(config);
    refuse(
        "setup-unreadable",
        format!("could not read the jest setup files of {config}: {why}"),
        "red locks the setup files it can name; one it cannot name could change what every locked case sees",
        format!("in {config}, write setupFiles, setupFilesAfterEnv, globalSetup and globalTeardown as string literals or arrays of them, and rootDir, if any, as one relative string literal in the config file itself, then run red again"),
    )
}

/// Point 4: a manifest's Jest settings, its `jest` value, or its bytes when it
/// is not a JSON object.
fn jest_settings(_path: &str, bytes: Vec<u8>) -> Settings {
    match std::str::from_utf8(&bytes).ok().and_then(|text| serde_json::from_str::<Value>(text).ok()) {
        Some(Value::Object(mut map)) => map.remove("jest").map_or(Settings::None, Settings::Json),
        _ => Settings::Bytes(bytes),
    }
}

/// Point 4, right after `pytest_config::check_changed`: the first watched
/// manifest whose `jest` key in `snapshot` equals no parent's.
pub fn check_changed(repo: &Repo, parents: &[Snapshot], snapshot: &Snapshot, lock_path: &str) -> Result<()> {
    let Some(config) = Config::at(repo, snapshot)? else { return Ok(()) };
    let suites = suites(&config);
    if suites.is_empty() {
        return Ok(());
    }
    let paths = manifests(&suites, &all_paths(repo, parents, snapshot)?);
    let judge = Judge {
        code: "jest-config-changed",
        subject: "jest's settings",
        why: "Jest reads how the suite runs from the jest key (setup files, module mappings, transforms), so changing it during GREEN changes the judge mid-game",
        undo: "the jest key",
        of: &jest_settings,
    };
    judge.run(repo, parents, snapshot, lock_path, paths)
}

#[cfg(test)]
mod tests;
