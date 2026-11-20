//! Item 16b: the `[build]` the init writes when the project uses TypeScript
//! project references. It reads tracked content only (the index) and proves the
//! command once on the tree; on any doubt it leaves `[build]` out and says
//! why, so a failed inference costs time, never the verdict (rule 17).

use crate::config::CONFIG_FILE;
use crate::git::{Repo, Snapshot};
use crate::glob;
use crate::jsonc;
use crate::refusal::{short_list, Result};
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
            return Ok(left_out(
                format!("cannot read {} as JSONC", fold(&file)),
                "init infers [build] only from tsconfig files it can read, and does not guess which folders the build needs",
            ));
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
    // Item 131: the probe is quiet; a failure is a skipped step, and what it
    // left untracked is named.
    let before = untracked(repo);
    let probed = suite::probe_build(&command, repo.root())?;
    if let Err((how, line)) = &probed {
        let line = line.as_ref().map(|l| format!(": {}", fold(l))).unwrap_or_default();
        skipped(
            &format!("`{command}` {how}{line}"),
            "init writes [build] only after it passes in the tree; a failing [build] would refuse every shipcraft ci and shipcraft red",
            &format!(
                "when `{command}` passes (run it to see the errors), add a [build] section to {CONFIG_FILE} with command = {}",
                basic_string(&command)
            ),
        );
    }
    if let (Some(before), Some(after)) = (before, untracked(repo)) {
        let left: Vec<String> = after.difference(&before).map(|path| fold(&String::from_utf8_lossy(path))).collect();
        if !left.is_empty() {
            println!(
                "shipcraft: the build left files git does not ignore: {}; add them to .gitignore before committing",
                short_list(&left)
            );
        }
    }
    Ok(probed.is_ok().then_some((command, dirs)))
}

/// Item 131: one line for the probe's lines: each run of whitespace and control
/// characters becomes one space, with no other escaping.
fn fold(text: &str) -> String {
    let parts = text.split(|c: char| c.is_whitespace() || c.is_control()).filter(|part| !part.is_empty());
    parts.collect::<Vec<_>>().join(" ")
}

/// Item 131: a TOML basic string on one line, `"` and `\` escaped (the `toml`
/// crate would write a `"` in a multi-line string instead).
fn basic_string(text: &str) -> String {
    let mut out = String::from("\"");
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\u{8}' => out.push_str("\\b"),
            '\t' => out.push_str("\\t"),
            '\n' => out.push_str("\\n"),
            '\u{c}' => out.push_str("\\f"),
            '\r' => out.push_str("\\r"),
            c if c.is_control() => out.push_str(&format!("\\u{:04X}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// The untracked files git does not ignore, as git gives them; None when git
/// fails or does not start.
fn untracked(repo: &Repo) -> Option<BTreeSet<Vec<u8>>> {
    let out = crate::git::git_in(repo.root(), &["ls-files", "-z", "--others", "--exclude-standard"]).ok()?;
    let paths = out.stdout.split(|b| *b == 0).filter(|p| !p.is_empty()).map(<[u8]>::to_vec);
    out.status.success().then(|| paths.collect())
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
                format!("cannot understand glob `{}` in {file}", fold(glob)),
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

/// A manifest file and the package globs it lists.
type Manifest = (&'static str, Vec<String>);

/// The package globs of `pnpm-workspace.yaml` and of `workspaces` in
/// `package.json`, each with its file.
fn manifests(repo: &Repo) -> Result<Option<Vec<Manifest>>> {
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
                format!("cannot read {file}, or its package list is not a list of strings"),
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

/// Item 147: the JSONC, glob and manifest notices, in item 131's skip form.
fn left_out<T>(what: String, why: &str) -> Option<T> {
    skipped(&what, why, BY_HAND);
    None
}

const BY_HAND: &str = "when the tests need a build first, add a [build] section to .shipcraft.toml with command = \"npx --no -- tsc -b <directories with project references>\", and remove the check of each suite in those directories, since tsc --noEmit refuses a composite project (TS6310)";

/// Items 131 and 147: every `[build]` notice after which init goes on.
fn skipped(what: &str, why: &str, next: &str) {
    println!("shipcraft: skipped the optional [build] step: {what}");
    println!("Why: {why}, so init goes on without it");
    println!("Next: {next}");
}

#[cfg(test)]
mod tests {
    use super::{basic_string, fold};

    #[test]
    fn fold_turns_whitespace_and_control_runs_into_one_space() {
        assert_eq!(fold("b\nname\t \u{1}x\u{2028}y"), "b name x y");
    }

    #[test]
    fn basic_string_reads_back_as_the_same_command() {
        for command in ["npx --no -- tsc -b .", "npx --no -- tsc -b 'p\"q' 'a\\b'", "x\ty\u{1}"] {
            let line = format!("command = {}", basic_string(command));
            assert!(!line.contains("\"\"\""), "{line}");
            let table: toml::Table = line.parse().unwrap();
            assert_eq!(table["command"].as_str(), Some(command), "{line}");
        }
    }
}
