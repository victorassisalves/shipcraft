//! `init`'s language and suites (items 56, 72, 90).

use super::OTHER_FORM;
use crate::config::CONFIG_FILE;
use crate::git::Repo;
use crate::glob;
use crate::jsonc;
use crate::lang::{self, Lang, Profile};
use crate::refusal::{refuse, Result};
use std::fs;
use std::path::Path;

/// The language and the suites: one per package with tests in a workspace,
/// or one at the root. No language (item 90) means a kept config and no suites.
/// Suites to write: (nome, raiz, profile).
type Suites = Vec<(String, String, Profile)>;

pub(super) fn plan(repo: &Repo, flag: Option<&str>) -> Result<(Option<Lang>, Suites)> {
    if flag.is_none() {
        if let Some((lang, patterns)) = lang::workspace(repo.root()) {
            let suites = workspace_suites(repo, lang, &patterns)?;
            if !suites.is_empty() {
                return Ok((Some(lang), suites));
            }
        }
    }
    let Some(lang) = choose_lang(repo, flag)? else {
        return Ok((None, Vec::new()));
    };
    let profile = lang.profile(repo.root(), "node_modules/.bin/");
    Ok((Some(lang), vec![(String::new(), ".".to_string(), profile)]))
}

fn workspace_suites(repo: &Repo, lang: Lang, patterns: &[String]) -> Result<Suites> {
    let files = repo.files()?;
    let mut dirs: Vec<String> = Vec::new();
    for pattern in patterns {
        let pattern = pattern.trim_start_matches("./").trim_end_matches('/');
        match pattern.strip_suffix("/**").or_else(|| pattern.strip_suffix("/*")) {
            Some(parent) => {
                let Ok(entries) = fs::read_dir(repo.path(parent)) else { continue };
                for entry in entries.flatten().filter(|e| e.path().is_dir()) {
                    dirs.push(format!("{parent}/{}", entry.file_name().to_string_lossy()));
                }
            }
            None => dirs.push(pattern.to_string()),
        }
    }
    dirs.sort();
    dirs.dedup();
    let marker = if lang == Lang::Go { "go.mod" } else { "package.json" };
    let mut suites = Vec::new();
    for dir in dirs {
        let path = repo.path(&dir);
        if !path.join(marker).exists() {
            continue;
        }
        let profile = lang.profile(&path, "npx --no -- ");
        let prefix = format!("{dir}/");
        let has_tests = files
            .iter()
            .filter_map(|f| f.strip_prefix(&prefix))
            .any(|rel| !rel.contains("node_modules/") && profile.globs.iter().take(3).any(|g| glob::matches(g, rel)));
        if has_tests {
            let name = dir.rsplit('/').next().unwrap_or(&dir).to_string();
            suites.push((name, dir, profile));
        }
    }
    Ok(suites)
}

/// Item 56: a suite whose `tsconfig.json` checks no file (a solution config)
/// loses its `tsc --noEmit` when `[build]` type-checks its folder, and keeps it
/// otherwise; either way a line says so. Item 72: any other suite whose folder
/// `[build]` names loses its check too, with its own line. Returns those lines,
/// in suite order.
pub(super) fn drop_empty_checks(repo: &Repo, suites: &mut Suites, built: &[String]) -> Vec<String> {
    let mut lines = Vec::new();
    for (name, root, profile) in suites.iter_mut() {
        let path = if root == "." { "tsconfig.json".to_string() } else { format!("{root}/tsconfig.json") };
        if profile.check.is_none() {
            continue;
        }
        let shown = if name.is_empty() { "default".to_string() } else { crate::red::one_line(name) };
        let empty = checks_no_file(&repo.path(&path));
        // Item 72: [build] type-checks the suite's package folder, whatever its
        // tsconfig holds. Runs before item 71's probe, so `root` is still the
        // package folder a converted suite's check would enter.
        if !empty {
            if built.contains(root) {
                profile.check = None;
                lines.push(format!(
                    "shipcraft: no check written for suite {shown}: [build] type-checks {}",
                    crate::red::one_line(&path)
                ));
            }
            continue;
        }
        let what = if built.contains(root) {
            profile.check = None;
            format!("no check written for suite {shown}: [build] type-checks its references")
        } else {
            format!(
                "the check of suite {shown} passes without checking: set check to the project's own type-check command"
            )
        };
        lines.push(format!("shipcraft: {} checks no file; {what}", crate::red::one_line(&path)));
    }
    lines
}

/// A regular file that reads as a JSON object with `files: []`, `include`
/// absent or `[]`, no `extends` and a non-empty `references` array. Anything
/// else is not judged (item 56).
fn checks_no_file(path: &Path) -> bool {
    if !path.symlink_metadata().is_ok_and(|m| m.is_file()) {
        return false;
    }
    let Some(config) = fs::read_to_string(path).ok().and_then(|text| jsonc::parse(&text)) else { return false };
    let Some(config) = config.as_object() else { return false };
    let empty = |v: &serde_json::Value| v.as_array().is_some_and(Vec::is_empty);
    config.get("files").is_some_and(empty)
        && config.get("include").is_none_or(empty)
        && !config.contains_key("extends")
        && config.get("references").and_then(|v| v.as_array()).is_some_and(|r| !r.is_empty())
}

fn choose_lang(repo: &Repo, flag: Option<&str>) -> Result<Option<Lang>> {
    if let Some(name) = flag {
        return match Lang::from_name(name) {
            Some(lang) => Ok(Some(lang)),
            None => refuse(
                "lang-unknown",
                format!("linguagem desconhecida: {name}"),
                "shipcraft knows the runner and stub for each language it supports",
                "use --lang python, --lang node or --lang go",
            ),
        };
    }
    match Lang::detect(repo.root()).as_slice() {
        [lang] => Ok(Some(*lang)),
        // Item 90: a config already says how to run the tests, in whatever form
        // (a link, a broken link and a folder count); later steps judge it.
        _ if repo.path(CONFIG_FILE).symlink_metadata().is_ok() => Ok(None),
        [] => refuse(
            "lang-unrecognized",
            "could not recognize the project language",
            "shipcraft recognizes a language by its project file, and found none it knows; it can also run any test command that writes JUnit",
            format!("specify the language: shipcraft init --lang python|node|go; for any other: {OTHER_FORM}"),
        ),
        found => refuse(
            "lang-multiple",
            format!(
                "the project appears to use more than one language: {}",
                found.iter().map(|l| l.name()).collect::<Vec<_>>().join(", ")
            ),
            "each project has a runner and a suite; shipcraft does not choose for you",
            format!("specify the language: shipcraft init --lang python|node|go; for any other: {OTHER_FORM}"),
        ),
    }
}
