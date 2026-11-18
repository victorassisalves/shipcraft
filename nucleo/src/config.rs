//! `.shipcraft.toml`: how the suites run, which files are tests, and where each
//! layer runs (`[execution]`, `[roles]`, `[review]`, `[machine]`).

mod execution;
mod paths;
mod pr;
mod reading;
mod report;
mod review;
mod roles;
mod suites;
#[cfg(test)]
mod tests;
mod version;

use crate::git::{Repo, Snapshot};
use crate::lang::Lang;
use crate::refusal::{refuse, Result};
pub use execution::Camada;
use execution::{camada, check_execution, Execucao, Maquina};
pub use paths::normal_glob;
use paths::{normal_globs, normal_path};
pub use pr::NewDependencies;
use pr::Pr;
use reading::{check_legacy_keys, not_toml};
use report::check_report;
pub use report::{report_invalid, report_release_tags};
use review::{check_retry_wait, Revisao};
pub use review::{check_review_after, check_review_guide};
pub use roles::Papel;
use roles::{check_roles, Papeis, PapeisRaw};
use serde::Deserialize;
use std::fs;
use suites::Build;
pub use suites::{owner, suite_names, Filtra, Suite};
pub use version::{check_min, min_reaches, minimum_version, version_parts};

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
    /// Item 64: read as raw TOML values, then validated into `papeis`.
    #[serde(default)]
    #[serde(rename = "roles")]
    papeis_raw: PapeisRaw,
    #[serde(skip)]
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
        let mut config = Config::parse_before_guide(text)?;
        // Item 102: after every check that refused before it.
        config.revisao.guide = crate::review_guide::check(text)?;
        Ok(config)
    }

    /// Every check but item 102's, in their order.
    fn parse_before_guide(text: &str) -> Result<Config> {
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
        // Item 64: after every check that refused before it.
        config.papeis = check_roles(text, std::mem::take(&mut config.papeis_raw))?;
        check_retry_wait(text)?;
        config.revisao.after_raw = None;
        config.revisao.after_push = check_review_after(text)?;
        // Item 99: after every check that refused before it.
        check_report(text)?;
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

pub fn no_config<T>() -> Result<T> {
    refuse(
        "no-config",
        format!("there is no {CONFIG_FILE} at the project root"),
        "shipcraft only checks a suite it knows how to run, and .shipcraft.toml says how",
        "run `shipcraft init` and commit the files it creates",
    )
}
