//! Item 20: with a lefthook file, the init integrates through the `commit-msg`,
//! the one hook route: it adds `shipcraft check --commit-msg` to the `commit-msg`
//! block and `shipcraft close` to the `post-commit` one (item 17), and raises
//! `shipcraft_min`.

use crate::config::{minimum_version, version_parts, CONFIG_FILE};
use crate::git::{Repo, Snapshot};
use crate::init::{block_layout, insert_text, is_executable, LOCAL};
use crate::lock::{lock_files, Lock};
use crate::refusal::{failed, refuse, Result};
use serde_norway::{Mapping, Value};
use std::fs;

/// The two blocks this route writes, and the `run` of each `shipcraft` command.
const BLOCKS: [(&str, &str); 2] = [("commit-msg", "shipcraft check --commit-msg"), ("post-commit", "shipcraft close")];

const BY_HAND: &str =
    "or manually put `shipcraft check --commit-msg` in commit-msg and `shipcraft close` in post-commit";

/// The lefthook file, its text, the new text (None: both commands are there)
/// and the hooks of the two blocks that git does not run yet.
pub struct Plan {
    pub file: String,
    pub old: String,
    pub new: Option<String>,
    pub missing: Vec<&'static str>,
}

/// Whether the lefthook file reads as YAML (a repeated key, too, does not).
pub fn readable(text: &str) -> std::result::Result<(), String> {
    parse(text).map(|_| ()).map_err(|_| "cannot be read as YAML".into())
}

/// The parser reads a leading BOM and a second key as two documents: the
/// BOM goes before parsing (the bytes written keep it).
fn parse(text: &str) -> std::result::Result<Value, serde_norway::Error> {
    serde_norway::from_str(text.strip_prefix('\u{feff}').unwrap_or(text))
}

fn command<'a>(doc: &'a Value, block: &str) -> Option<&'a Value> {
    doc.get(block)?.get("commands")?.get("shipcraft")
}

/// Item 58: a `shipcraft` command that is just `run: <run>`, with `shipcraft` or the
/// project's `./node_modules/.bin/shipcraft`.
fn generated(shipcraft: &Value, run: &str) -> bool {
    shipcraft.as_mapping().is_some_and(|m| m.len() == 1)
        && [run.to_string(), run.replacen("shipcraft", LOCAL, 1)]
            .iter()
            .any(|r| shipcraft.get("run") == Some(&r.as_str().into()))
}

/// 20.2 and 20.3: the checks of this route and the text with the commands
/// that are missing; any doubt refuses, nothing written (rule 17).
pub fn plan(repo: &Repo, file: &str, text: String, local: bool) -> Result<Plan> {
    let stop = |problem: String| alien(format!("{file} {problem}"), &problem);
    let doc: Value = parse(&text).map_err(|_| failed(format!("{file} disappeared while it was read")))?;
    let mut top = match doc {
        Value::Mapping(top) => top,
        Value::Null => Mapping::new(),
        _ => return stop("is not a YAML map".into()),
    };
    if let Some(key) = ["extends", "jobs", "remotes", "rc"].into_iter().find(|k| top.contains_key(k)) {
        return stop(format!("uses `{key}`"));
    }
    if let Err(problem) = block_layout(&text) {
        return stop(problem);
    }
    if top.get("pre-commit").and_then(|b| b.get("commands")).and_then(|c| c.get("shipcraft")).is_some() {
        return twice(repo, file);
    }
    let mut new = text.clone();
    for (block, run) in BLOCKS {
        let mut map = match top.get(block) {
            None | Some(Value::Null) => Mapping::new(),
            Some(Value::Mapping(map)) => map.clone(),
            Some(_) => return stop(format!("has a {block} block that is not a map")),
        };
        if let Some(key) = map.keys().find(|k| k.as_str() != Some("commands")) {
            return stop(format!("has `{}` in the {block} block besides commands", key.as_str().unwrap_or("?")));
        }
        let mut commands = match map.get("commands") {
            None | Some(Value::Null) => Mapping::new(),
            Some(Value::Mapping(commands)) => commands.clone(),
            Some(_) => return stop(format!("has commands in {block} that is not a map")),
        };
        match commands.get("shipcraft") {
            Some(shipcraft) if generated(shipcraft, run) => continue,
            Some(_) => {
                return stop(format!("already has an `shipcraft` command in {block} that is not just `run: {run}`"))
            }
            None => {}
        }
        let run = if local { run.replacen("shipcraft", LOCAL, 1) } else { run.to_string() };
        let mut shipcraft = Mapping::new();
        shipcraft.insert("run".into(), run.as_str().into());
        commands.insert("shipcraft".into(), Value::Mapping(shipcraft));
        map.insert("commands".into(), Value::Mapping(commands));
        top.insert(block.into(), Value::Mapping(map));
        new = insert_text(&new, block, &[format!("run: {run}")]);
    }
    // 15b.4: what is written reads back as the expected YAML, or it refuses.
    if !matches!(parse(&new), Ok(back) if back == Value::Mapping(top)) {
        return stop("cannot prove where to put shipcraft commands without changing the rest".into());
    }
    // The notice also names a `pre-commit` the lefthook still has to install.
    let pre = repo.hook_path("pre-commit")?;
    let mut missing = if is_executable(&pre) { vec![] } else { vec!["pre-commit"] };
    for (block, _) in BLOCKS {
        let hook = repo.hook_path(block)?;
        let shown = hook.strip_prefix(repo.root()).unwrap_or(&hook).display().to_string();
        if hook.symlink_metadata().is_err() {
            missing.push(block);
        } else if !fs::read_to_string(&hook).is_ok_and(|t| is_lefthook(&t, block)) {
            let what = format!("installed hook {block} ({shown}) is not from lefthook");
            return alien(what.clone(), &what);
        } else if !is_executable(&hook) {
            missing.push(block);
        }
    }
    let new = (new != text).then_some(new);
    Ok(Plan { file: file.to_string(), old: text, new, missing })
}

/// 15b.1 and 20.2: the script `lefthook install` writes ends in this call,
/// with or without the `"$@"`; a mere mention of the name is not the lefthook.
pub fn is_lefthook(script: &str, hook: &str) -> bool {
    let call = format!("call_lefthook run \"{hook}\"");
    script.lines().rev().find(|l| !l.trim().is_empty()).is_some_and(|l| l.trim_start().starts_with(&call))
}

/// 20.3: a `shipcraft` in the `pre-commit` too would run the suite twice.
fn twice<T>(repo: &Repo, file: &str) -> Result<T> {
    let first =
        if open_lock(repo) { "close the open lock (with it, changing the lefthook file is refused), " } else { "" };
    refuse(
        "foreign-hook",
        format!("{file} has an `shipcraft` command in pre-commit, and integration uses commit-msg"),
        "with both, the suite would run twice per commit",
        format!("{first}remove the shipcraft command from {file} pre-commit and run `shipcraft init` again, {BY_HAND}"),
    )
}

/// Whether HEAD has an open lock; a lock that does not read counts as open.
fn open_lock(repo: &Repo) -> bool {
    let Ok(Some(_)) = repo.head() else { return false };
    lock_files(repo, &Snapshot::Commit("HEAD".into()))
        .map_or(true, |locks| locks.values().any(|bytes| Lock::parse(bytes).is_none_or(|l| l.is_open())))
}

/// The `hook-alheio` refusal of this route: the 3rd line says what keeps the
/// integration from happening, never to put `shipcraft check` in the `pre-commit`.
pub fn alien<T>(what: String, problem: &str) -> Result<T> {
    refuse(
        "foreign-hook",
        what,
        "shipcraft does not replace or edit another tool's hook: when in doubt, this step stays manual",
        format!("what prevents commit-msg integration: {problem}; fix it and run `shipcraft init` again, {BY_HAND}"),
    )
}

/// 20.2: the `shipcraft_min` of an existing `.shipcraft.toml`, raised to this binary's
/// version: (old text, new text), or None when it needs no change. Only the
/// `shipcraft_min` line changes, or one is added before the first key; if the text
/// does not read back as the same table with the new `shipcraft_min`, it refuses.
pub fn raise_min(repo: &Repo) -> Result<Option<(String, String)>> {
    let minimum = minimum_version();
    let path = repo.path(CONFIG_FILE);
    let Ok(meta) = path.symlink_metadata() else { return Ok(None) };
    let unproved = |why: &str| {
        refuse(
            "shipcraft-min",
            format!("cannot raise shipcraft_min in {CONFIG_FILE} to {minimum}: {why}"),
            "a project integrated through commit-msg needs an shipcraft that knows `shipcraft close`",
            format!("put `shipcraft_min = \"{minimum}\"` in {CONFIG_FILE} and run `shipcraft init` again"),
        )
    };
    if meta.file_type().is_symlink() {
        return unproved("is a symbolic link");
    }
    let old = fs::read_to_string(&path).map_err(|e| failed(format!("read {CONFIG_FILE}: {e}")))?;
    let Ok(mut table) = old.parse::<toml::Table>() else { return unproved("cannot be read as TOML") };
    if table.get("shipcraft_min").and_then(|v| v.as_str()).is_some_and(|m| version_parts(m) >= version_parts(&minimum))
    {
        return Ok(None);
    }
    let line = format!("shipcraft_min = \"{minimum}\"");
    let lines: Vec<&str> = old.split_inclusive('\n').collect();
    let first_key = |l: &&str| !l.trim().is_empty() && !l.trim_start().starts_with('#');
    let new = match lines.iter().position(|l| l.trim_start().starts_with("shipcraft_min")) {
        Some(at) => {
            let eol = &lines[at][lines[at].trim_end_matches(['\r', '\n']).len()..];
            [&lines[..at].concat(), line.as_str(), eol, &lines[at + 1..].concat()].concat()
        }
        None => {
            let at = lines.iter().position(first_key).unwrap_or(lines.len());
            let eol = if old.contains("\r\n") { "\r\n" } else { "\n" };
            [&lines[..at].concat(), line.as_str(), eol, &lines[at..].concat()].concat()
        }
    };
    table.insert("shipcraft_min".into(), toml::Value::String(minimum.clone()));
    match new.parse::<toml::Table>() {
        Ok(back) if back == table => Ok(Some((old, new))),
        _ => unproved("cannot prove where the shipcraft_min line is without changing the rest"),
    }
}

/// Writes the `.shipcraft.toml` raise and the lefthook file in one transaction:
/// if a write fails, both go back byte by byte (15a.1).
pub fn write(repo: &Repo, plan: &Plan, min: Option<&(String, String)>) -> Result<()> {
    let minimum = minimum_version();
    let config = repo.path(CONFIG_FILE);
    let lefthook = repo.path(&plan.file);
    if let Some((old, new)) = min {
        fs::write(&config, new).map_err(|e| {
            let _ = fs::write(&config, old);
            failed(format!("write {CONFIG_FILE}: {e}"))
        })?;
        println!("shipcraft: raised shipcraft_min in {CONFIG_FILE} to {minimum}");
    }
    let Some(new) = &plan.new else {
        println!("shipcraft: {} already has shipcraft commands in commit-msg and post-commit, kept", plan.file);
        return Ok(());
    };
    fs::write(&lefthook, new).map_err(|e| {
        let _ = fs::write(&lefthook, &plan.old);
        if let Some((old, _)) = min {
            let _ = fs::write(&config, old);
        }
        failed(format!("write {}: {e}", plan.file))
    })?;
    println!(
        "shipcraft: added shipcraft commands to {} (shipcraft check --commit-msg in commit-msg, shipcraft close in post-commit)",
        plan.file
    );
    Ok(())
}

/// The hooks git does not run yet, for a one-line message.
pub fn hooks(missing: &[&str]) -> String {
    match missing {
        [one] => format!("the lefthook {one} hook"),
        _ => format!("the lefthook hooks {}", missing.join(" and ")),
    }
}

/// 20.3, `shipcraft status`: by this route, the hook runs only when both commands
/// are the shipcraft ones and both hooks are the lefthook's, executable, and the
/// init would integrate as it is; otherwise what is missing, event by event.
pub fn status(repo: &Repo, integrates: bool) -> String {
    let Some((file, doc)) = crate::init::LEFTHOOK_FILES
        .iter()
        .find_map(|f| Some((f, parse(&fs::read_to_string(repo.path(f)).ok()?).ok()?)))
    else {
        return "shipcraft: missing hook: the commit does not go through `shipcraft check`; run `shipcraft init`"
            .into();
    };
    let mut wants = Vec::new();
    for (block, run) in BLOCKS {
        let shipcraft = command(&doc, block);
        if !shipcraft.is_some_and(|c| generated(c, run)) {
            wants.push(format!("the `shipcraft` command with `run: {run}` in {block}"));
        }
    }
    for (block, _) in BLOCKS {
        let hook = repo.hook_path(block).ok();
        let ok = hook
            .as_ref()
            .is_some_and(|h| is_executable(h) && fs::read_to_string(h).is_ok_and(|t| is_lefthook(&t, block)));
        if !ok {
            wants.push(format!("the installed and executable lefthook {block} hook"));
        }
    }
    match (wants.is_empty(), integrates) {
        (true, true) => format!("shipcraft: hook through lefthook (commit-msg): {file}, shipcraft commands"),
        (true, false) => format!("shipcraft: missing hook: `shipcraft init` refuses {file}; run it to see why"),
        _ => format!(
            "shipcraft: missing hook: missing {}; run `shipcraft init` and `lefthook install`",
            wants.join(", ")
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_repeated_key_does_not_read() {
        assert!(parse("a: 1\na: 2\n").is_err());
        assert!(parse("\u{feff}a: 1\nb: 2\n").is_ok());
        assert!(readable("a: 1\na: 2\n").is_err());
    }

    #[test]
    fn writes_both_blocks_in_block_layout() {
        let text = "pre-commit:\n  parallel: true\ncommit-msg:\npost-commit:\n  commands:\n";
        let mut new = text.to_string();
        for (block, run) in BLOCKS {
            new = insert_text(&new, block, &[format!("run: {run}")]);
        }
        assert_eq!(
            new,
            "pre-commit:\n  parallel: true\ncommit-msg:\n  commands:\n    shipcraft:\n      run: shipcraft check --commit-msg\npost-commit:\n  commands:\n    shipcraft:\n      run: shipcraft close\n"
        );
    }
}
