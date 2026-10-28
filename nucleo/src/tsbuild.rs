//! Item 16b: the `[build]` the init writes when the project uses TypeScript
//! project references. It reads tracked content only (the index) and proves the
//! command once on the tree; on any doubt it leaves `[build]` out and says
//! why, so a failed inference costs time, never the verdict (rule 17).

use crate::config::CONFIG_FILE;
use crate::git::{Repo, Snapshot};
use crate::glob;
use crate::jsonc;
use crate::refusal::{warn, Result};
use crate::suite;
use serde_json::Value;
use std::collections::BTreeSet;

/// Wildcards the test globs do not have: the init does not guess them.
const UNKNOWN: [&str; 5] = ["{", "[", "+(", "@(", "!("];

/// The `[build] comando` to write: `tsc -b` on every folder (the root as `.`)
/// whose own `tsconfig.json` has the signal, with those folders. None without
/// the signal, or after saying why it was left out.
pub fn infer(repo: &Repo) -> Result<Option<(String, Vec<String>)>> {
    let tracked: BTreeSet<String> = repo.tracked()?.into_iter().collect();
    let Some(packages) = packages(repo, &tracked)? else { return Ok(None) };
    let mut dirs = Vec::new();
    for dir in std::iter::once(".".to_string()).chain(packages) {
        let file = if dir == "." { "tsconfig.json".to_string() } else { format!("{dir}/tsconfig.json") };
        let Some(text) = indexed(repo, &file)? else { continue };
        let Some(config) = jsonc::parse(&text) else {
            println!("shipcraft: did not write [build]: cannot read {file} as JSONC");
            return Ok(None);
        };
        if config.get("references").is_some() || config["compilerOptions"]["composite"] == Value::Bool(true) {
            dirs.push(dir);
        }
    }
    if dirs.is_empty() {
        return Ok(None);
    }
    dirs.sort();
    let targets: Vec<String> = dirs.iter().map(|dir| shell_word(dir)).collect();
    let command = format!("npx --no -- tsc -b {}", targets.join(" "));
    let Err(how) = suite::run_build(&command, repo.root())? else { return Ok(Some((command, dirs))) };
    warn(
        format!("did not write [build]: `{command}` {how}"),
        "init proves the build in the tree before writing it; a failing [build] would refuse every shipcraft ci and shipcraft red",
        format!("fix the build and run shipcraft init again, or {}", by_hand(&command)),
    );
    Ok(None)
}

/// The workspace packages: folders with a tracked `package.json` that a glob
/// of either manifest takes and no `!` glob of it removes (the union of both
/// manifests). None after saying why, when a manifest does not read.
fn packages(repo: &Repo, tracked: &BTreeSet<String>) -> Result<Option<BTreeSet<String>>> {
    let folders: Vec<&str> = tracked
        .iter()
        .filter_map(|f| f.strip_suffix("/package.json"))
        .filter(|dir| !dir.split('/').any(|name| name == "node_modules"))
        .collect();
    let mut found = BTreeSet::new();
    let Some(manifests) = manifests(repo)? else { return Ok(None) };
    for (file, globs) in manifests {
        if let Some(glob) = globs.iter().find(|g| UNKNOWN.iter().any(|w| g.contains(w))) {
            return Ok(left_out(
                format!("did not write [build]: cannot understand glob `{glob}` in {file}"),
                "shipcraft only matches `*`, `?`, `**` and exclusion `!`; another wildcard would mean guessing which packages are included",
            ));
        }
        let takes = |glob: &str, dir: &str| glob::matches(glob.trim_start_matches("./").trim_end_matches('/'), dir);
        let (out, into): (Vec<&String>, Vec<&String>) = globs.iter().partition(|g| g.starts_with('!'));
        found.extend(
            folders
                .iter()
                .filter(|dir| into.iter().any(|g| takes(g, dir)) && !out.iter().any(|g| takes(&g[1..], dir)))
                .map(|dir| dir.to_string()),
        );
    }
    Ok(Some(found))
}

/// The package globs of `pnpm-workspace.yaml` and of `workspaces` in
/// `package.json`, each with its file.
fn manifests(repo: &Repo) -> Result<Option<Vec<(&'static str, Vec<String>)>>> {
    let mut all = Vec::new();
    if let Some(text) = indexed(repo, "pnpm-workspace.yaml")? {
        let doc = serde_norway::from_str::<serde_norway::Value>(&text).ok().and_then(|d| serde_json::to_value(d).ok());
        all.push(("pnpm-workspace.yaml", doc.and_then(|d| globs(&d, "packages", false))));
    }
    if let Some(text) = indexed(repo, "package.json")? {
        let doc = serde_json::from_str::<Value>(&text).ok();
        all.push(("package.json", doc.and_then(|d| globs(&d, "workspaces", true))));
    }
    let mut read = Vec::new();
    for (file, globs) in all {
        let Some(globs) = globs else {
            return Ok(left_out(
                format!("did not write [build]: cannot read {file}, or its package list is not a list of strings"),
                "[build] comes from workspace packages, and shipcraft does not guess which ones",
            ));
        };
        read.push((file, globs));
    }
    Ok(Some(read))
}

/// A tracked file's content in the index, or None when git does not track it.
fn indexed(repo: &Repo, path: &str) -> Result<Option<String>> {
    Ok(repo.read(&Snapshot::Index, path)?.map(|bytes| String::from_utf8_lossy(&bytes).into_owned()))
}

/// The list of texts under `key` of a manifest (with `yarn`, also the object
/// that has it in `packages`); no key is an empty list, and anything else
/// (null, a map, a non-text item) is None.
fn globs(doc: &Value, key: &str, yarn: bool) -> Option<Vec<String>> {
    let list = match doc.get(key) {
        None if doc.is_object() || doc.is_null() => return Some(Vec::new()),
        None => return None,
        Some(Value::Object(object)) if yarn => object.get("packages")?,
        Some(list) => list,
    };
    list.as_array()?.iter().map(|g| g.as_str().map(str::to_string)).collect()
}

/// A folder as one shell word: as it is when that is safe, quoted otherwise.
fn shell_word(dir: &str) -> String {
    let safe = |c: char| c.is_ascii_alphanumeric() || "._/-@+".contains(c);
    if dir.chars().all(safe) {
        dir.to_string()
    } else {
        suite::shell_quote(dir)
    }
}

fn left_out<T>(what: String, why: &str) -> Option<T> {
    warn(what, why, by_hand("npx --no -- tsc -b <directories with project references>"));
    None
}

fn by_hand(command: &str) -> String {
    format!("manually add a [build] section to {CONFIG_FILE} with command = \"{command}\"")
}
