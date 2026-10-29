//! `.shipcraft.toml`: how the suites run, which files are tests, and where each
//! layer runs (`[execution]`, `[roles]`, `[review]`, `[machine]`).

use crate::git::{Repo, Snapshot};
use crate::glob;
use crate::lang::Lang;
use crate::refusal::{refuse, Result};
use serde::Deserialize;
use std::collections::BTreeSet;
use std::fs;

pub const CONFIG_FILE: &str = ".shipcraft.toml";
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Refuse the old filename only in the content the command judges.
pub fn reject_legacy_file(repo: &Repo, snapshot: &Snapshot) -> Result<()> {
    let exists = |path: &str| -> Result<bool> {
        match snapshot {
            Snapshot::Tree => Ok(repo.path(path).symlink_metadata().is_ok()),
            _ => repo.read(snapshot, path).map(|bytes| bytes.is_some()),
        }
    };
    if !exists(CONFIG_FILE)? && exists(".sc2.toml")? {
        return refuse(
            "config-invalid",
            "the project has .sc2.toml but no .shipcraft.toml",
            "Shipcraft reads its configuration from .shipcraft.toml",
            "rename .sc2.toml to .shipcraft.toml and run again",
        );
    }
    Ok(())
}

/// The English config contract requires this binary's major/minor version.
pub fn minimum_version() -> String {
    VERSION.split('.').take(2).collect::<Vec<_>>().join(".")
}

#[derive(Deserialize)]
pub struct Config {
    pub lang: Option<Lang>,
    pub runner: Option<String>,
    pub test_command: Option<String>,
    /// The check of the whole project, before the tests: in the CI and the
    /// RED, never in the hook (item 13).
    #[serde(rename = "check")]
    pub verifica: Option<String>,
    #[serde(default)]
    pub test_globs: Vec<String>,
    #[serde(default)]
    #[serde(rename = "filter")]
    pub filtra: Filtra,
    #[serde(default)]
    pub suite: Vec<Suite>,
    /// Runs once at the root before the first suite, in the CI and the RED,
    /// never on a copy (item 16a).
    pub build: Option<Build>,
    #[serde(default)]
    #[serde(rename = "execution")]
    pub execucao: Execucao,
    #[serde(default)]
    #[serde(rename = "roles")]
    pub papeis: Papeis,
    #[serde(default)]
    #[serde(rename = "review")]
    pub revisao: Revisao,
    #[serde(default)]
    #[serde(rename = "machine")]
    pub maquina: Maquina,
    #[serde(default)]
    pub pr: Pr,
}

/// One suite (item 9): `comando` runs in `raiz`, and `globs` are relative to it.
#[derive(Clone, Deserialize)]
pub struct Suite {
    #[serde(default)]
    #[serde(rename = "name")]
    pub nome: String,
    #[serde(default = "dot")]
    #[serde(rename = "root")]
    pub raiz: String,
    #[serde(rename = "command")]
    pub comando: String,
    #[serde(default)]
    #[serde(rename = "check")]
    pub verifica: Option<String>,
    #[serde(default)]
    pub globs: Vec<String>,
    /// Item 22.4: who filters the hook's run, shipcraft or the command.
    #[serde(default)]
    #[serde(rename = "filter")]
    pub filtra: Filtra,
}

#[derive(Clone, Copy, Default, PartialEq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Filtra {
    #[default]
    Shipcraft,
    #[serde(rename = "command")]
    Comando,
}

impl Suite {
    /// The root as a path prefix from the project's root, "" or "dir/".
    pub fn prefix(&self) -> String {
        if self.raiz.is_empty() {
            String::new()
        } else {
            format!("{}/", self.raiz)
        }
    }

    /// Whether a path from the project's root is one of this suite's files.
    pub fn matches(&self, path: &str) -> bool {
        let relative = path.strip_prefix(&self.prefix());
        relative.is_some_and(|rel| self.globs.iter().any(|g| glob::matches(g, rel)))
    }

    /// The suite in a refusal: its `nome`, or its folder from the root.
    pub fn name(&self) -> &str {
        if self.nome.is_empty() {
            self.shown_root()
        } else {
            &self.nome
        }
    }

    /// The root as messages show it: the project's root is `.` (item 30).
    pub fn shown_root(&self) -> &str {
        if self.raiz.is_empty() {
            "."
        } else {
            &self.raiz
        }
    }
}

/// Item 59: the suite names of a `.shipcraft.toml` other than the tree's,
/// read as TOML alone, without the config's validation: each `[[suite]]`
/// whose `name` is a non-empty string. None when it is not TOML.
pub fn suite_names(bytes: &[u8]) -> Option<BTreeSet<String>> {
    let value: toml::Table = toml::from_str(std::str::from_utf8(bytes).ok()?).ok()?;
    let suites = value.get("suite").and_then(toml::Value::as_array).map_or(&[][..], Vec::as_slice);
    let names = suites.iter().filter_map(|suite| suite.get("name")?.as_str()).filter(|name| !name.is_empty());
    Some(names.map(str::to_string).collect())
}

/// Item 59: the suite a case belongs to among `names`, the longest `n` for
/// which the id starts with `n:`.
pub fn owner<'a>(case: &str, names: impl IntoIterator<Item = &'a String>) -> Option<&'a String> {
    let own = |name: &&String| case.strip_prefix(name.as_str()).is_some_and(|rest| rest.starts_with(':'));
    names.into_iter().filter(own).max_by_key(|name| name.len())
}

#[derive(Deserialize)]
pub struct Build {
    #[serde(rename = "command")]
    pub comando: String,
}

#[derive(Deserialize)]
#[serde(default)]
pub struct Execucao {
    /// Items 42 and 47: `ci`, `review` and `merge` take any TOML value here, so
    /// that `check_execution` names a wrong one instead of a `config-invalid`.
    #[serde(deserialize_with = "any_value")]
    pub ci: String,
    #[serde(rename = "review", deserialize_with = "any_value")]
    pub revisao: String,
    #[serde(rename = "ci_timeout")]
    pub tempo_max_ci: u64,
    /// Item 42: how `shipcraft merge` merges, `merge` or `squash`.
    #[serde(deserialize_with = "any_value")]
    pub merge: String,
    /// Item 62: the project's own GitHub checks that run the suite; read as
    /// any TOML value so that `check_execution` names a wrong one, then kept
    /// in `suite_checks`.
    #[serde(rename = "suite_checks")]
    suite_checks_raw: Option<toml::Value>,
    #[serde(skip)]
    pub suite_checks: Vec<String>,
}

#[derive(Deserialize)]
#[serde(default)]
pub struct Papeis {
    #[serde(rename = "review")]
    pub revisao: String,
}

#[derive(Deserialize)]
#[serde(default)]
pub struct Revisao {
    pub spec: Option<String>,
    #[serde(rename = "timeout")]
    pub tempo_max: u64,
}

/// Item 11, rule 3: above `aviso_linhas` product lines the summary suggests a
/// split. Item 24:
/// `forma_linhas` fixes the N of the shape warning (an integer above 0).
#[derive(Deserialize)]
#[serde(default)]
pub struct Pr {
    #[serde(rename = "warn_lines")]
    pub aviso_linhas: u64,
    #[serde(rename = "shape_lines")]
    pub forma_linhas: Option<std::num::NonZeroU64>,
}

impl Default for Pr {
    fn default() -> Self {
        Pr { aviso_linhas: 500, forma_linhas: None }
    }
}

#[derive(Default, Deserialize)]
pub struct Maquina {
    pub slots: Option<u64>,
}

impl Default for Execucao {
    fn default() -> Self {
        Execucao {
            ci: "local".into(),
            revisao: "local".into(),
            tempo_max_ci: 1800,
            merge: "merge".into(),
            suite_checks_raw: None,
            suite_checks: Vec::new(),
        }
    }
}

impl Default for Papeis {
    fn default() -> Self {
        Papeis { revisao: "codex".into() }
    }
}

impl Default for Revisao {
    fn default() -> Self {
        Revisao { spec: None, tempo_max: 1200 }
    }
}

fn dot() -> String {
    ".".to_string()
}

/// Where a layer runs (item 1).
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Camada {
    Local,
    Github,
    Desligado,
}

impl Config {
    /// The tree's `.shipcraft.toml`.
    pub fn load(repo: &Repo) -> Result<Config> {
        reject_legacy_file(repo, &Snapshot::Tree)?;
        let Ok(text) = fs::read_to_string(repo.path(CONFIG_FILE)) else { return no_config() };
        Config::parse(&text)
    }

    /// The `.shipcraft.toml` of a snapshot, if it has one.
    pub fn at(repo: &Repo, snapshot: &Snapshot) -> Result<Option<Config>> {
        reject_legacy_file(repo, snapshot)?;
        match repo.read(snapshot, CONFIG_FILE)? {
            Some(bytes) => Config::parse(&String::from_utf8_lossy(&bytes)).map(Some),
            None => Ok(None),
        }
    }

    /// The config a PR is judged by (item 1, rule 3): the base branch's, as
    /// origin has it; the tree's when the base has none yet.
    pub fn of_base(repo: &Repo, base: &str) -> Result<Config> {
        let rev = format!("origin/{base}");
        if repo.resolve(&rev)?.is_some() {
            if let Some(config) = Config::at(repo, &Snapshot::Commit(rev))? {
                return Ok(config);
            }
        }
        Config::load(repo)
    }

    pub fn parse(text: &str) -> Result<Config> {
        check_legacy_keys(text)?;
        check_min(text)?;
        let mut config: Config = match toml::from_str(text) {
            Ok(config) => config,
            Err(e) => return not_toml(text, &e),
        };
        check_execution(text)?;
        config.execucao.suite_checks = config
            .execucao
            .suite_checks_raw
            .take()
            .and_then(|v| v.as_array().map(|a| a.iter().filter_map(|e| e.as_str().map(str::to_string)).collect()))
            .unwrap_or_default();
        config.normalize()?;
        Ok(config)
    }

    /// Item 30.1: the `raiz` and the globs without their `.` and empty parts,
    /// once, so every use sees one form; the project's root is "".
    fn normalize(&mut self) -> Result<()> {
        self.test_globs = normal_globs("test_globs", &self.test_globs)?;
        for suite in &mut self.suite {
            suite.raiz = normal_path("root", &suite.raiz)?;
            suite.globs = normal_globs("globs", &suite.globs)?;
        }
        Ok(())
    }

    /// The suites: the `[[suite]]` tables, or the v0 single suite at the root.
    pub fn suites(&self) -> Vec<Suite> {
        if !self.suite.is_empty() {
            return self.suite.clone();
        }
        let comando = self.test_command.clone().unwrap_or_default();
        vec![Suite {
            nome: String::new(),
            raiz: String::new(),
            comando,
            verifica: self.verifica.clone(),
            globs: self.test_globs.clone(),
            filtra: self.filtra,
        }]
    }

    /// A case's id within `suite`, without the suite's prefix, when the case
    /// is the suite's: for a named suite, its owner by item 59's identity (so
    /// `api` does not take `api:jobs:` cases); an unnamed suite takes every id.
    pub fn own<'a>(&self, suite: &Suite, case: &'a str) -> Option<&'a str> {
        if suite.nome.is_empty() {
            return Some(case);
        }
        let named: Vec<String> = self.suites().into_iter().map(|s| s.nome).filter(|n| !n.is_empty()).collect();
        let id = case.strip_prefix(suite.nome.as_str())?.strip_prefix(':')?;
        (owner(case, &named) == Some(&suite.nome)).then_some(id)
    }

    /// The project's test files (and support files), as paths from the root.
    pub fn test_files(&self, repo: &Repo) -> Result<Vec<String>> {
        let files = repo.files()?;
        Ok(files.into_iter().filter(|path| self.is_test_file(path)).filter(|path| repo.path(path).is_file()).collect())
    }

    pub fn is_test_file(&self, path: &str) -> bool {
        self.suites().iter().any(|suite| suite.matches(path))
    }

    /// The two layers, `(ci, revisao)`; refuses a value the v1 does not know.
    pub fn camadas(&self) -> Result<(Camada, Camada)> {
        let ci = camada("ci", &self.execucao.ci)?;
        let revisao = camada("review", &self.execucao.revisao)?;
        if revisao == Camada::Github {
            return refuse(
                "review-github",
                "[execution] review = \"github\" is not available in v1 yet",
                "the executed review runs on this machine; the GitHub layer is reserved for a future version",
                "set review = \"local\" or review = \"off\" in .shipcraft.toml on main",
            );
        }
        Ok((ci, revisao))
    }
}

/// A path of the config without its `.` and empty parts; an absolute one, or
/// one with `..`, is an invalid config (item 30.1).
fn normal_path(key: &str, value: &str) -> Result<String> {
    let parts: Vec<&str> = value.split('/').filter(|p| !p.is_empty() && *p != ".").collect();
    if value.starts_with('/') || parts.contains(&"..") {
        return invalid(key, value, "is outside the project");
    }
    Ok(parts.join("/"))
}

fn normal_globs(key: &str, globs: &[String]) -> Result<Vec<String>> {
    globs
        .iter()
        .map(|g| match normal_path(key, g)? {
            empty if empty.is_empty() => invalid(key, g, "matches no files"),
            glob => Ok(glob),
        })
        .collect()
}

fn invalid<T>(key: &str, value: &str, problem: &str) -> Result<T> {
    refuse(
        "config-invalid",
        format!("{key} = \"{value}\" in {CONFIG_FILE} {problem}"),
        "the lock covers test files by their path within the project, and shipcraft does not guess another",
        format!("use a path relative to the project root in {key}, without `..`, and run again"),
    )
}

/// E1: old wire names must never disappear as ignored serde fields.
fn check_legacy_keys(text: &str) -> Result<()> {
    let Ok(table) = text.parse::<toml::Table>() else { return Ok(()) };
    legacy_keys(&toml::Value::Table(table), "")
}

fn legacy_keys(value: &toml::Value, path: &str) -> Result<()> {
    match value {
        toml::Value::Table(table) => {
            for (key, value) in table {
                let prefix = if path.is_empty() { String::new() } else { format!("{path}.") };
                let replacement = match key.as_str() {
                    "verifica" => Some("check"),
                    "filtra" => Some("filter"),
                    "execucao" => Some("execution"),
                    "papeis" => Some("roles"),
                    "revisao" => Some("review"),
                    "maquina" => Some("machine"),
                    "tempo_max_ci" => Some("ci_timeout"),
                    "tempo_max" => Some("timeout"),
                    "aviso_linhas" => Some("warn_lines"),
                    "forma_linhas" => Some("shape_lines"),
                    "nome" => Some("name"),
                    "raiz" => Some("root"),
                    "comando" => Some("command"),
                    _ => None,
                };
                if let Some(new) = replacement {
                    return refuse(
                        "config-invalid",
                        format!("legacy config key `{prefix}{key}` in {CONFIG_FILE}; use `{prefix}{new}`"),
                        "ignoring the old key could skip a project check or change how the commit is judged",
                        format!("rename `{prefix}{key}` to `{prefix}{new}` in {CONFIG_FILE} and run again"),
                    );
                }
                legacy_keys(value, &format!("{prefix}{key}"))?;
            }
        }
        toml::Value::Array(values) => {
            for (index, value) in values.iter().enumerate() {
                legacy_keys(value, &format!("{path}[{index}]"))?;
            }
        }
        _ => {}
    }
    Ok(())
}

/// Item 31: a `.shipcraft.toml` that is not TOML, or lacks a required key, is
/// refused in three lines wherever it is read.
fn not_toml<T>(text: &str, e: &toml::de::Error) -> Result<T> {
    // The line the error points at names the key (`filtra = true`).
    let at = e.span().map(|span| {
        let n = text[..span.start.min(text.len())].matches('\n').count();
        format!(" (line {}: `{}`)", n + 1, text.lines().nth(n).unwrap_or("").trim())
    });
    refuse(
        "config-invalid",
        format!(
            "{CONFIG_FILE} is not a valid configuration: {}{}",
            e.message().trim().replace('\n', " "),
            at.unwrap_or_default()
        ),
        "after it, every PR would be judged by a config shipcraft cannot read",
        format!("fix {CONFIG_FILE} (TOML, with `command` in each [[suite]]) and run again"),
    )
}

fn camada(key: &str, value: &str) -> Result<Camada> {
    match value {
        "local" => Ok(Camada::Local),
        "github" => Ok(Camada::Github),
        "off" => Ok(Camada::Desligado),
        other => refuse(
            "execution-invalid",
            format!("[execution] {key} = \"{other}\" is not a value shipcraft knows"),
            "each layer runs on this machine, on GitHub or is off, and shipcraft does not guess which",
            format!("use {key} = \"local\", \"github\" or \"off\" in .shipcraft.toml on main"),
        ),
    }
}

/// A string as it is, any other TOML value as TOML; `check_execution` refuses it.
fn any_value<'de, D: serde::Deserializer<'de>>(d: D) -> std::result::Result<String, D::Error> {
    Ok(match toml::Value::deserialize(d)? {
        toml::Value::String(s) => s,
        other => other.to_string(),
    })
}

/// Items 42 and 47: `[execution] ci` and `review` are `"local"`, `"github"` or
/// `"off"`, and `merge` is `"merge"` (the default) or `"squash"`; any other
/// value, a non-string included, refuses wherever the config is read, checked
/// in the order `ci`, `review`, `merge`. `review = "github"` passes here and is
/// refused by `camadas()`.
fn check_execution(text: &str) -> Result<()> {
    let Ok(table) = text.parse::<toml::Table>() else { return Ok(()) };
    let Some(execution) = table.get("execution") else { return Ok(()) };
    for key in ["ci", "review"] {
        let Some(value) = execution.get(key) else { continue };
        if !matches!(value.as_str(), Some("local" | "github" | "off")) {
            return refuse(
                "execution-invalid",
                format!("[execution] {key} = {value} is not a value shipcraft knows"),
                "each layer runs on this machine, on GitHub or is off, and shipcraft does not guess which",
                format!("use {key} = \"local\", \"github\" or \"off\" in .shipcraft.toml on main"),
            );
        }
    }
    if let Some(value) = execution.get("merge") {
        if !matches!(value.as_str(), Some("merge" | "squash")) {
            return refuse(
                "execution-invalid",
                format!("[execution] merge = {value} is not a value shipcraft knows"),
                "shipcraft merge makes a merge commit or squashes the PR, and shipcraft does not guess which",
                "use merge = \"merge\" or \"squash\" in .shipcraft.toml on main",
            );
        }
    }
    check_suite_checks(&table, execution)
}

/// Item 62: `[execution] suite_checks` is an array of distinct, trimmed,
/// non-empty names without control characters, never Shipcraft's own
/// contexts; a non-empty one needs `ci = "github"` and `shipcraft_min` at
/// 2.18 or above, so no older binary judges the project without it.
fn check_suite_checks(table: &toml::Table, execution: &toml::Value) -> Result<()> {
    let Some(value) = execution.get("suite_checks") else { return Ok(()) };
    let wrong = |problem: String| {
        refuse(
            "execution-invalid",
            format!("[execution] suite_checks = {value} {problem}"),
            "shipcraft merges only when every named GitHub check that runs the suite is green, and does not guess which",
            "use suite_checks = [\"<check name>\", ...] with ci = \"github\" and shipcraft_min = \"2.18\" in .shipcraft.toml on main",
        )
    };
    let Some(names) = value.as_array() else { return wrong("is not an array of strings".into()) };
    let mut seen: Vec<&str> = Vec::new();
    for element in names {
        let Some(name) = element.as_str() else { return wrong(format!("has {element}, which is not a string")) };
        if name.is_empty() {
            return wrong("has an empty name".into());
        }
        if name.chars().any(|c| c <= '\u{1f}' || c == '\u{7f}') {
            return wrong(format!("has {element}, which holds a control character"));
        }
        if name.starts_with(char::is_whitespace) || name.ends_with(char::is_whitespace) {
            return wrong(format!("has {element}, which starts or ends with whitespace"));
        }
        if seen.contains(&name) {
            return wrong(format!("names {element} twice"));
        }
        if name == "shipcraft/ci" || name == "shipcraft/review" {
            return wrong(format!("names {element}, which is shipcraft's own status"));
        }
        seen.push(name);
    }
    if names.is_empty() {
        return Ok(());
    }
    if execution.get("ci").and_then(|v| v.as_str()) != Some("github") {
        return wrong("is not empty, and needs ci = \"github\"".into());
    }
    let min = table.get("shipcraft_min").and_then(|v| v.as_str());
    let well_formed = min.is_some_and(|m| {
        let runs: Vec<&str> = m.split('.').collect();
        (2..=3).contains(&runs.len()) && runs.iter().all(|r| !r.is_empty() && r.bytes().all(|b| b.is_ascii_digit()))
    });
    if !well_formed || min.is_some_and(|m| version_parts(m) < version_parts("2.18")) {
        return wrong("is not empty, and needs shipcraft_min = \"2.18\" or above".into());
    }
    Ok(())
}

pub fn no_config<T>() -> Result<T> {
    refuse(
        "no-config",
        format!("there is no {CONFIG_FILE} at the project root"),
        "shipcraft only checks a suite it knows how to run, and .shipcraft.toml says how",
        "run `shipcraft init` and commit the files it creates",
    )
}

/// Item 9, rule 2: an shipcraft older than `shipcraft_min` refuses instead of judging.
pub fn check_min(text: &str) -> Result<()> {
    let Ok(table) = text.parse::<toml::Table>() else { return Ok(()) };
    let Some(min) = table.get("shipcraft_min").and_then(|v| v.as_str()) else { return Ok(()) };
    if version_parts(min) <= version_parts(VERSION) {
        return Ok(());
    }
    refuse(
        "shipcraft-min",
        format!(".shipcraft.toml requires shipcraft {min} or newer, and this is {VERSION}"),
        "two machines cannot judge the same commit differently without warning",
        format!("update shipcraft to version {min} or newer and run again"),
    )
}

/// Splits a version into numbers, trailing zeros dropped, so 2.0 and 2.0.0 compare equal.
pub fn version_parts(v: &str) -> Vec<u64> {
    let mut parts: Vec<u64> = v.split('.').map(|p| p.trim().parse().unwrap_or(0)).collect();
    while parts.last() == Some(&0) {
        parts.pop();
    }
    parts
}

#[cfg(test)]
mod tests {
    use super::Config;

    fn suite(raiz: &str, glob: &str) -> String {
        format!("[[suite]]\nroot = \"{raiz}\"\ncommand = \"x\"\nglobs = [\"{glob}\"]\n")
    }

    #[test]
    fn legacy_document_keys_refuse_before_deserialization() {
        for (text, old, new) in [
            ("verifica = 'exit 37'", "verifica", "check"),
            ("\"verifica\" = 'exit 37'", "verifica", "check"),
            ("[execucao]\nci = 'local'", "execucao", "execution"),
            ("execution.tempo_max_ci = 17", "execution.tempo_max_ci", "execution.ci_timeout"),
            ("suite = [{ nome = 'api' }]", "suite[0].nome", "suite[0].name"),
            ("check = 'true'\nverifica = 'false'", "verifica", "check"),
        ] {
            match Config::parse(text) {
                Err(crate::refusal::Stop::Refused(r)) => {
                    assert_eq!(r.code, "config-invalid", "{text}");
                    assert!(r.what().contains(&format!("`{old}`")), "{}", r.what());
                    assert!(r.what().contains(&format!("`{new}`")), "{}", r.what());
                }
                _ => panic!("legacy key accepted: {text}"),
            }
        }
        assert!(Config::parse("check = 'echo verifica filtra comando' # [execucao]\n").is_ok());
    }

    #[test]
    fn english_config_keys_reach_their_consumers() {
        let config = Config::parse(
            r#"
check = "project-check"
filter = "command"
[execution]
ci = "github"
review = "off"
ci_timeout = 17
[roles]
review = "claude"
[review]
spec = "contract.md"
timeout = 19
[machine]
slots = 3
[pr]
warn_lines = 23
shape_lines = 29
[build]
command = "compile"
[[suite]]
name = "api"
root = "packages/api"
command = "test"
check = "suite-check"
filter = "command"
globs = ["tests/**"]
"#,
        )
        .unwrap();
        assert_eq!(config.verifica.as_deref(), Some("project-check"));
        assert!(config.filtra == super::Filtra::Comando);
        assert!(config.camadas().unwrap() == (super::Camada::Github, super::Camada::Desligado));
        assert_eq!(config.execucao.tempo_max_ci, 17);
        assert_eq!(config.papeis.revisao, "claude");
        assert_eq!(config.revisao.spec.as_deref(), Some("contract.md"));
        assert_eq!(config.revisao.tempo_max, 19);
        assert_eq!(config.maquina.slots, Some(3));
        assert_eq!(config.pr.aviso_linhas, 23);
        assert_eq!(config.pr.forma_linhas.unwrap().get(), 29);
        assert_eq!(config.build.unwrap().comando, "compile");
        let suite = &config.suite[0];
        assert_eq!(suite.nome, "api");
        assert_eq!(suite.raiz, "packages/api");
        assert_eq!(suite.comando, "test");
        assert_eq!(suite.verifica.as_deref(), Some("suite-check"));
        assert!(suite.filtra == super::Filtra::Comando);
        assert!(Config::parse("filter = \"comando\"").is_err());
        assert!(Config::parse("[execution]\nreview = \"github\"").unwrap().camadas().is_err());
        assert_eq!(Config::parse("").unwrap().execucao.merge, "merge");
        assert_eq!(Config::parse("[execution]\nmerge = \"squash\"").unwrap().execucao.merge, "squash");
        for bad in [
            "merge = \"rebase\"",
            "merge = 7",
            "merge = true",
            "ci = \"desligado\"",
            "ci = \"LOCAL\"",
            "ci = 7",
            "review = \"off \"",
            "review = [\"local\"]",
        ] {
            let refused = Config::parse(&format!("[execution]\n{bad}"));
            assert!(matches!(refused, Err(crate::refusal::Stop::Refused(r)) if r.code == "execution-invalid"), "{bad}");
        }
        let refused = Config::parse("[execution]\nci = \"foo\"\nci_timeout = \"bad\"");
        assert!(matches!(refused, Err(crate::refusal::Stop::Refused(r)) if r.code == "config-invalid"));
    }

    #[test]
    fn raiz_and_globs_are_normalized_once() {
        for (raiz, normal) in
            [("./packages/api/", "packages/api"), ("packages//api", "packages/api"), ("./", ""), (".", ""), ("", "")]
        {
            let config = Config::parse(&suite(raiz, "./tests/**")).unwrap_or_else(|_| panic!("{raiz}"));
            assert_eq!(config.suite[0].raiz, normal);
            assert_eq!(config.suite[0].globs, ["tests/**"]);
        }
        assert!(Config::parse(&suite("./packages/api", "tests/*.py")).unwrap().is_test_file("packages/api/tests/a.py"));
    }

    #[test]
    fn absolute_or_parent_paths_and_empty_globs_are_invalid() {
        for (raiz, glob) in [
            ("/", "*"),
            ("/.", "*"),
            ("/x", "*"),
            ("a/../b", "*"),
            ("..", "*"),
            ("a", ""),
            ("a", "./"),
            ("a", "/t/*"),
            ("a", "../*"),
        ] {
            assert!(Config::parse(&suite(raiz, glob)).is_err(), "{raiz} {glob}");
        }
    }

    #[test]
    fn not_toml_or_a_suite_without_comando_is_a_refusal() {
        for text in ["this is not toml", "[[suite]]\nroot = \"a\"\n"] {
            match Config::parse(text) {
                Err(crate::refusal::Stop::Refused(r)) => assert_eq!(r.code, "config-invalid", "{text}"),
                _ => panic!("{text}"),
            }
        }
    }

    #[test]
    fn suite_checks_need_github_ci_and_a_2_18_minimum() {
        let ok = "shipcraft_min = \"2.18\"\n[execution]\nci = \"github\"\nsuite_checks = [\"a b\", \"c/\u{3b2}\"]";
        assert_eq!(Config::parse(ok).unwrap().execucao.suite_checks, ["a b", "c/\u{3b2}"]);
        assert!(Config::parse("[execution]\nsuite_checks = []").unwrap().execucao.suite_checks.is_empty());
        for bad in [
            "shipcraft_min = \"2.18\"\n[execution]\nci = \"github\"\nsuite_checks = \"a\"",
            "shipcraft_min = \"2.18\"\n[execution]\nci = \"github\"\nsuite_checks = [\"a\", \"a\"]",
            "shipcraft_min = \"2.18\"\n[execution]\nci = \"github\"\nsuite_checks = [\"\\u00a0a\"]",
            "shipcraft_min = \"2.18\"\n[execution]\nci = \"github\"\nsuite_checks = [\"shipcraft/ci\"]",
            "shipcraft_min = \"2.18\"\n[execution]\nci = \"local\"\nsuite_checks = [\"a\"]",
            "shipcraft_min = \"2.17\"\n[execution]\nci = \"github\"\nsuite_checks = [\"a\"]",
            "shipcraft_min = \"2.18a\"\n[execution]\nci = \"github\"\nsuite_checks = [\"a\"]",
            "[execution]\nci = \"github\"\nsuite_checks = [\"a\"]",
        ] {
            let refused = Config::parse(bad);
            assert!(matches!(refused, Err(crate::refusal::Stop::Refused(r)) if r.code == "execution-invalid"), "{bad}");
        }
    }
}
