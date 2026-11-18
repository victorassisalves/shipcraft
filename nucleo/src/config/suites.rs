//! The suites and the build (items 9, 16a, 22.4, 59).

use crate::glob;
use serde::Deserialize;
use std::collections::BTreeSet;

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

fn dot() -> String {
    ".".to_string()
}
