//! `[roles]` (item 64).

use super::version::version_parts;
use super::CONFIG_FILE;
use crate::refusal::{refuse, Result};
use serde::Deserialize;

/// Item 64: `[roles]` as written; each role is any TOML value until
/// `check_roles` names what is wrong with it.
#[derive(Default, Deserialize)]
#[serde(default)]
pub(super) struct PapeisRaw {
    red: Option<toml::Value>,
    green: Option<toml::Value>,
    review: Option<toml::Value>,
}

/// Item 64: one role, the agent alone or with a model and an effort.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Papel {
    pub agent: String,
    pub model: Option<String>,
    pub effort: Option<String>,
}

impl Papel {
    pub fn agent(agent: &str) -> Papel {
        Papel { agent: agent.to_string(), model: None, effort: None }
    }

    /// `agent`, then ` (<model>, effort <effort>)`, ` (<model>)` or
    /// ` (effort <effort>)` when they are given.
    pub fn shown(&self) -> String {
        match (&self.model, &self.effort) {
            (Some(m), Some(e)) => format!("{} ({m}, effort {e})", self.agent),
            (Some(m), None) => format!("{} ({m})", self.agent),
            (None, Some(e)) => format!("{} (effort {e})", self.agent),
            (None, None) => self.agent.clone(),
        }
    }
}

/// Item 64: the review role (`codex` when absent) and the RED and GREEN
/// roles (`None` when absent: the session that starts the RED and GREEN chooses).
pub struct Papeis {
    pub revisao: Papel,
    pub red: Option<Papel>,
    pub green: Option<Papel>,
}

impl Default for Papeis {
    fn default() -> Self {
        Papeis { revisao: Papel::agent("codex"), red: None, green: None }
    }
}

/// Item 64: the agents a role names.
const ROLE_AGENTS: [&str; 3] = ["codex", "claude", "gemini"];
/// Item 64: the minimum a table role, or any `red` or `green`, needs.
const ROLES_MIN: &str = "2.20";

/// Item 64: after item 47's checks, the `shipcraft_min` rule, then `red`,
/// `green` and `review`; each refusal names the exact key path.
pub(super) fn check_roles(text: &str, raw: PapeisRaw) -> Result<Papeis> {
    let needs = [("red", &raw.red), ("green", &raw.green), ("review", &raw.review)]
        .into_iter()
        .find(|(name, value)| match value {
            Some(toml::Value::Table(_)) => true,
            Some(_) => *name != "review",
            None => false,
        })
        .map(|(name, _)| name);
    if let Some(name) = needs {
        let min = text
            .parse::<toml::Table>()
            .ok()
            .and_then(|t| t.get("shipcraft_min").and_then(|v| v.as_str()).map(str::to_string));
        let low = match &min {
            None => Some(format!("shipcraft_min is not set in {CONFIG_FILE}")),
            Some(m) if version_parts(m) < version_parts(ROLES_MIN) => {
                Some(format!("shipcraft_min = {} in {CONFIG_FILE} is below {ROLES_MIN}", quoted(m)))
            }
            Some(_) => None,
        };
        if let Some(low) = low {
            return refuse(
                "config-invalid",
                format!("{low}, and [roles] {name} needs {ROLES_MIN} or above"),
                "older binaries do not know a role table or the RED and GREEN roles, and would judge the project differently",
                format!("set shipcraft_min = \"{ROLES_MIN}\" (or above) in {CONFIG_FILE} and run again"),
            );
        }
    }
    let red = raw.red.map(|v| role("red", v)).transpose()?;
    let green = raw.green.map(|v| role("green", v)).transpose()?;
    let revisao = raw.review.map(|v| role("review", v)).transpose()?.unwrap_or_else(|| Papel::agent("codex"));
    Ok(Papeis { revisao, red, green })
}

fn role(name: &str, value: toml::Value) -> Result<Papel> {
    let path = format!("roles.{name}");
    let table = match value {
        toml::Value::String(agent) if ROLE_AGENTS.contains(&agent.as_str()) => return Ok(Papel::agent(&agent)),
        toml::Value::String(agent) => {
            return role_invalid(&path, format!("= {} is not codex, claude or gemini", quoted(&agent)))
        }
        toml::Value::Table(table) => table,
        other => return role_invalid(&path, format!("is {}, not an agent name or a table", a_type(&other))),
    };
    let agent_path = format!("{path}.agent");
    let agent = match table.get("agent") {
        None => return role_invalid(&agent_path, "is missing".to_string()),
        Some(toml::Value::String(a)) if ROLE_AGENTS.contains(&a.as_str()) => a.clone(),
        Some(toml::Value::String(a)) => {
            return role_invalid(&agent_path, format!("= {} is not codex, claude or gemini", quoted(a)))
        }
        Some(other) => return role_invalid(&agent_path, format!("is {}, not codex, claude or gemini", a_type(other))),
    };
    let mut keys: Vec<&String> = table.keys().collect();
    keys.sort();
    if let Some(key) = keys.into_iter().find(|k| !matches!(k.as_str(), "agent" | "model" | "effort")) {
        return role_invalid(
            &format!("{path}.{}", escaped(key)),
            "is not a role key (a role table has agent, model and effort)".to_string(),
        );
    }
    let model = table.get("model").map(|v| shape(&format!("{path}.model"), v)).transpose()?;
    let effort_path = format!("{path}.effort");
    let effort = table.get("effort").map(|v| shape(&effort_path, v)).transpose()?;
    if let Some(e) = &effort {
        let list: &[&str] = match agent.as_str() {
            "codex" => &["minimal", "low", "medium", "high", "xhigh"],
            "claude" => &["low", "medium", "high", "xhigh", "max"],
            _ => &[],
        };
        if list.is_empty() {
            return role_invalid(&effort_path, format!("= {}, and {agent} takes no effort", quoted(e)));
        }
        if !list.contains(&e.as_str()) {
            return role_invalid(
                &effort_path,
                format!("= {} is not an effort {agent} takes ({})", quoted(e), list.join(", ")),
            );
        }
    }
    Ok(Papel { agent, model, effort })
}

/// Item 64: a `model` or `effort` is a non-empty string, not starting with
/// `-`, without a whitespace or control character (Unicode's definitions).
fn shape(path: &str, value: &toml::Value) -> Result<String> {
    let Some(s) = value.as_str() else {
        return role_invalid(path, format!("is {}, not a string", a_type(value)));
    };
    if s.is_empty() {
        return role_invalid(path, "is empty".to_string());
    }
    if s.starts_with('-') {
        return role_invalid(path, format!("= {} starts with -", quoted(s)));
    }
    if s.chars().any(|c| c.is_whitespace() || c.is_control()) {
        return role_invalid(path, format!("= {} has a whitespace or control character", quoted(s)));
    }
    Ok(s.to_string())
}

fn role_invalid<T>(path: &str, problem: String) -> Result<T> {
    refuse(
        "config-invalid",
        format!("`{path}` {problem} in {CONFIG_FILE}"),
        "shipcraft starts the reviewer and shows the RED and GREEN roles exactly as written, and does not guess a role it cannot read",
        format!("fix `{path}` in {CONFIG_FILE} (a role is \"codex\", \"claude\" or \"gemini\", or a table with agent and an optional model and effort) and run again"),
    )
}

fn a_type(value: &toml::Value) -> String {
    let t = value.type_str();
    if t.starts_with(['a', 'e', 'i', 'o', 'u']) {
        format!("an {t}")
    } else {
        format!("a {t}")
    }
}

/// A string on one line: whitespace other than a space, control characters,
/// quotes and backslashes as `\u{..}` escapes.
fn escaped(s: &str) -> String {
    s.chars()
        .map(|c| {
            if (c.is_whitespace() && c != ' ') || c.is_control() || c == '"' || c == '\\' {
                format!("\\u{{{:04X}}}", c as u32)
            } else {
                c.to_string()
            }
        })
        .collect()
}

fn quoted(s: &str) -> String {
    format!("\"{}\"", escaped(s))
}
