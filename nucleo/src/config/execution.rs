//! `[execution]` and `[machine]`, and the layers (items 1, 42, 47, 62).

use super::version::min_reaches;
use crate::refusal::{refuse, Result};
use serde::Deserialize;

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
    pub(super) suite_checks_raw: Option<toml::Value>,
    #[serde(skip)]
    pub suite_checks: Vec<String>,
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

/// Where a layer runs (item 1).
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Camada {
    Local,
    Github,
    Desligado,
}

pub(super) fn camada(key: &str, value: &str) -> Result<Camada> {
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
pub(super) fn check_execution(text: &str) -> Result<()> {
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
    if !min_reaches(table, "2.18") {
        return wrong("is not empty, and needs shipcraft_min = \"2.18\" or above".into());
    }
    Ok(())
}
