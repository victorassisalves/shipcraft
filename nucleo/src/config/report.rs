//! `[report]` (items 99, 105).

use super::CONFIG_FILE;
use crate::refusal::{refuse, Result};

/// Item 124: `[report] deploy`, what `report` counts as a deploy.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Deploy {
    Merge,
    Release,
}

impl Deploy {
    pub fn as_str(self) -> &'static str {
        match self {
            Deploy::Merge => "merge",
            Deploy::Release => "release",
        }
    }
}

/// Item 99: `[report] release_tags`, the pattern `report` reads releases by.
/// `Ok(None)` when there is no `[report]` table or it has no pattern; `Err`
/// names the first problem, in the spec's order, item 124's `deploy` last.
pub fn report_release_tags(table: &toml::Table) -> std::result::Result<Option<String>, String> {
    let pattern = release_tags(table)?;
    report_deploy(table)?;
    Ok(pattern)
}

/// Item 124: the `deploy` key, `Ok(None)` when absent. Its problem is
/// checked after item 99's (`report_release_tags` names the first).
pub fn report_deploy(table: &toml::Table) -> std::result::Result<Option<Deploy>, String> {
    let Some(value) = table.get("report").and_then(toml::Value::as_table).and_then(|r| r.get("deploy")) else {
        return Ok(None);
    };
    match value.as_str() {
        Some("merge") => Ok(Some(Deploy::Merge)),
        Some("release") => Ok(Some(Deploy::Release)),
        _ => Err("deploy is not \"merge\" or \"release\"".to_string()),
    }
}

fn release_tags(table: &toml::Table) -> std::result::Result<Option<String>, String> {
    let Some(report) = table.get("report") else { return Ok(None) };
    let Some(report) = report.as_table() else { return Err("[report] is not a table".to_string()) };
    let mut keys: Vec<&String> = report.keys().collect();
    keys.sort();
    if let Some(key) = keys.into_iter().find(|k| !matches!(k.as_str(), "release_tags" | "deploy")) {
        return Err(format!("unknown key {key}"));
    }
    let Some(value) = report.get("release_tags") else { return Ok(None) };
    let Some(pattern) = value.as_str() else { return Err("release_tags is not a string".to_string()) };
    if pattern.is_empty() {
        return Err("release_tags is empty".to_string());
    }
    if pattern.bytes().any(|b| !(0x21..=0x7e).contains(&b)) {
        return Err("release_tags has a byte outside 0x21-0x7E".to_string());
    }
    if pattern.bytes().any(|b| matches!(b, b'?' | b'[' | b']' | b'\\')) {
        return Err("release_tags has ?, [, ] or \\".to_string());
    }
    if pattern.bytes().all(|b| b == b'*') {
        return Err("release_tags is only *".to_string());
    }
    Ok(Some(pattern.to_string()))
}

/// Item 99: the reason an invalid `[report]` gives, the one text the
/// `config-invalid` refusal, `report`'s git reason and `red`'s
/// `--fixes-release` refusal (item 105) all print.
pub fn report_invalid(problem: &str) -> String {
    format!("[report] in {CONFIG_FILE} is invalid: {problem}")
}

/// Item 99: an invalid `[report]` refuses wherever the config is validated,
/// naming the key and what is wrong. An older binary ignores the table, so no
/// `shipcraft_min` is needed.
pub(super) fn check_report(text: &str) -> Result<()> {
    let Ok(table) = text.parse::<toml::Table>() else { return Ok(()) };
    match report_release_tags(&table) {
        Ok(_) => Ok(()),
        Err(problem) => refuse(
            "config-invalid",
            report_invalid(&problem),
            "report reads its releases by this pattern, and shipcraft does not guess one it cannot read",
            format!("set release_tags = \"<pattern>\" (printable ASCII, `*` the only wildcard, not only `*`) as the only key of [report] in {CONFIG_FILE}, or remove [report], and run again"),
        ),
    }
}

/// Item 122: an invalid `[findings]` refuses wherever the config is
/// validated, last in `Config::parse`. An older binary ignores the table.
pub(super) fn check_findings(text: &str) -> Result<()> {
    let Ok(table) = text.parse::<toml::Table>() else { return Ok(()) };
    match crate::findings::classes(&table) {
        Ok(_) => Ok(()),
        Err(problem) => refuse(
            "config-invalid",
            crate::findings::invalid(&problem),
            "report --findings groups the review findings by these classes, and shipcraft does not guess a class it cannot read",
            format!("give each [[findings.class]] a name and a non-empty list of valid keyword patterns, or remove [findings], in {CONFIG_FILE} and run again"),
        ),
    }
}
