//! Reading the TOML text: the legacy keys and the text that is not TOML (E1, item 31).

use super::CONFIG_FILE;
use crate::refusal::{refuse, Result};

/// E1: old wire names must never disappear as ignored serde fields.
pub(super) fn check_legacy_keys(text: &str) -> Result<()> {
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
pub(super) fn not_toml<T>(text: &str, e: &toml::de::Error) -> Result<T> {
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
