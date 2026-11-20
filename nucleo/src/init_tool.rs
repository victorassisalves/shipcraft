//! Item 25: the init integrates with the husky 9 and with the pre-commit
//! framework through the `commit-msg` (item 17): `shipcraft check --commit-msg` in
//! the `commit-msg` and `shipcraft close` in the `post-commit`. Their `pre-commit`
//! is not touched: its formatters run before, and the `commit-msg` sees the
//! final index. Item 133: husky 7 and 8 (`init_husky`), prek's launchers and the
//! hooks with no stages.

use crate::config::CONFIG_FILE;
use crate::git::Repo;
use crate::init::{is_executable, layout, on_path, single_source, LOCAL};
use crate::refusal::{failed, refuse, short_list, Result, Stop};
use serde_norway::Value;
use std::fs;
use std::path::Path;

pub const PRE_COMMIT_CONFIG: &str = ".pre-commit-config.yaml";
/// The husky files the init writes, and the line of each (point 1).
pub const HUSKY: [(&str, &str); 2] =
    [(".husky/commit-msg", "shipcraft check --commit-msg \"$1\""), (".husky/post-commit", "shipcraft close")];
/// The two local hooks of the pre-commit framework (point 2): id, entry, stage.
pub(crate) const HOOKS: [(&str, &str, &str); 2] = [
    ("shipcraft-check", "shipcraft check --commit-msg", "commit-msg"),
    ("shipcraft-close", "shipcraft close", "post-commit"),
];
/// 133.5: the post-commit hook's id before 2.76, still read as it.
pub(crate) const LEGACY: &str = "shipcraft-fecha";
pub(crate) const TWICE: &str = "with it, the suite would run twice per commit: remove it";

/// What the integration writes: (file, old text or None when new, new text),
/// and what git does not run yet, with the command that installs it.
pub struct Tool {
    pub name: &'static str,
    pub writes: Vec<(String, Option<String>, String)>,
    pub missing: Vec<String>,
    pub install: String,
    /// 133.4: the ids of the project's pre-commit hooks that also run at commit-msg and post-commit.
    pub stageless: Vec<String>,
    /// 133.1: the files this plan creates are set to 0755 (husky 7 and 8).
    pub exec_new: bool,
}

/// Whether the project uses one of these tools: `.husky/`, a husky before
/// the 9 (`husky.hooks` in the `package.json`, point 1) or the config.
pub fn present(repo: &Repo) -> bool {
    old_husky(repo) || [".husky", PRE_COMMIT_CONFIG].iter().any(|f| repo.path(f).symlink_metadata().is_ok())
}

/// A `core.hooksPath` in `.husky` is a husky's, of the 9 or of before (point 1).
pub fn husky_path(dir: Option<&str>) -> bool {
    dir.is_some_and(|d| d.starts_with(".husky"))
}

pub(crate) fn old_husky(repo: &Repo) -> bool {
    let package = fs::read_to_string(repo.path("package.json")).ok();
    let json = package.and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok());
    json.is_some_and(|p| p.get("husky").and_then(|h| h.get("hooks")).is_some())
}

/// 25.3: a line that runs `shipcraft check` (its first two words, after an `exec`), in the installed `pre-commit`.
fn checks(text: &str) -> bool {
    text.lines().any(|l| l.split_whitespace().skip_while(|w| *w == "exec").take(2).eq(["shipcraft", "check"]))
}

/// Points 1 to 4: the plan, decided before anything is written; any doubt
/// refuses, nothing written (rule 17). `dir` is the raw `core.hooksPath`.
/// Item 58: `local` writes `./node_modules/.bin/shipcraft` for `shipcraft`; both forms are recognized.
pub fn decide(repo: &Repo, dir: Option<&str>, local: bool) -> Result<Tool> {
    let husky = husky_path(dir) || old_husky(repo) || repo.path(".husky").symlink_metadata().is_ok();
    let other = if husky && repo.path(PRE_COMMIT_CONFIG).symlink_metadata().is_ok() {
        Some("husky (.husky/) and the pre-commit framework (.pre-commit-config.yaml)".to_string())
    } else {
        let tool = if husky { "husky" } else { "the pre-commit framework" };
        // 15a.2: any lefthook source, in any name and format the core reads.
        single_source(repo, "").err().map(|source| format!("{tool} and lefthook ({source})"))
    };
    if let Some(both) = other {
        return alien(format!("the project uses two hook tools: {both}"), "keep only one");
    }
    if husky {
        crate::init_husky::plan(repo, dir, local)
    } else {
        pre_commit_plan(repo, dir, local)
    }
}

fn pre_commit_plan(repo: &Repo, dir: Option<&str>, local: bool) -> Result<Tool> {
    if let Some(dir) = dir.filter(|d| *d != ".git/hooks") {
        return alien(
            format!("core.hooksPath is {dir:?}, and shipcraft only accepts .git/hooks, exactly"),
            "remove core.hooksPath",
        );
    }
    let text = read(repo, PRE_COMMIT_CONFIG)?.unwrap_or_default();
    fn stop<T>(problem: &str) -> Result<T> {
        alien(format!("{PRE_COMMIT_CONFIG} {problem}"), "keep the `repos` list in block style")
    }
    let doc = parse(&text).map_err(|_| ()).or_else(|()| stop("cannot be read as YAML"))?;
    if let Err(problem) = layout(&text, true) {
        return stop(&problem);
    }
    let Some(repos) = doc.get("repos").and_then(Value::as_sequence) else { return stop("has no `repos` list") };
    let hooks = || repos.iter().filter_map(|r| r.get("hooks")?.as_sequence()).flatten();
    let ids: Vec<&str> = hooks().filter_map(|h| h.get("id")?.as_str()).collect();
    // 133.5: `shipcraft close` would run twice, whatever the order and contents.
    if ids.contains(&HOOKS[1].0) && ids.contains(&LEGACY) {
        return stop(&format!("has both {} and {LEGACY} (post-commit)", HOOKS[1].0));
    }
    // 25.3: a hook's stages are its `stages`, if not empty; else the top's
    // `default_stages`, if there (`[]` is none); else all. Not a list of text: does not read.
    let default = match stage_list(doc.get("default_stages")) {
        Ok(list) => list,
        Err(()) => return stop("has an unreadable `default_stages` (not a list of strings)"),
    };
    let (mut wanted, mut stageless): (Vec<usize>, Vec<String>) = (vec![0, 1], Vec::new());
    for hook in hooks() {
        let id = hook.get("id").and_then(Value::as_str);
        let own = HOOKS.iter().position(|(h, ..)| Some(*h) == id).or((id == Some(LEGACY)).then_some(1));
        if let (Some(i), Some(id)) = (own, id) {
            if *hook != canonical(i, false, id) && *hook != canonical(i, true, id) {
                return stop(&format!("has hook `{id}` ({}) different from what shipcraft writes", HOOKS[i].2));
            }
            wanted.retain(|w| *w != i);
            continue;
        }
        let Ok(own) = stage_list(hook.get("stages")) else {
            return stop("has an unreadable `stages` (not a list of strings)");
        };
        // 133.4: deduplicated on the raw id, in file order.
        match id {
            Some(id) if own.as_ref().is_none_or(Vec::is_empty) && !stageless.iter().any(|s| s == id) => {
                stageless.push(id.to_string())
            }
            _ => {}
        }
        let stages = own.filter(|s| !s.is_empty()).or(default.clone());
        let pre = stages.is_none_or(|s| s.iter().any(|v| matches!(v.as_str(), "pre-commit" | "commit")));
        // The first word as the shell splits it, named `shipcraft` with or without a path, then `check`.
        let Some(words) = shell_words(hook.get("entry").and_then(Value::as_str).unwrap_or_default()) else {
            return stop("has an `entry` that cannot be read as shell words");
        };
        let shipcraft = words.first().is_some_and(|w| w.rsplit('/').next() == Some("shipcraft"));
        if pre && shipcraft && words.get(1).is_some_and(|w| w == "check") {
            return alien(format!("{PRE_COMMIT_CONFIG} has an `shipcraft check` in pre-commit"), TWICE);
        }
    }
    let mut writes = Vec::new();
    if !wanted.is_empty() {
        let new =
            append(&text, &wanted, local).ok_or(()).or_else(|()| stop("cannot prove where to put shipcraft hooks"))?;
        let mut expected = doc.clone();
        let item = parse(&item(&wanted, 0, 1, "\n", local)).ok().and_then(|v| v.as_sequence()?.first().cloned());
        if let Some((r, i)) = expected.get_mut("repos").and_then(Value::as_sequence_mut).zip(item) {
            r.push(i);
        }
        if !parse(&new).is_ok_and(|back| back == expected) {
            return stop("cannot prove where to put shipcraft hooks without changing the rest");
        }
        writes.push((PRE_COMMIT_CONFIG.to_string(), Some(text), new));
    }
    let pre = fs::read_to_string(repo.hook_path("pre-commit")?).ok();
    if pre.as_deref().is_some_and(|t| t.contains("# shipcraft hook") || checks(t)) {
        return alien("the installed pre-commit hook runs `shipcraft check`".into(), TWICE);
    }
    // 133.3: a file that cannot be read is no launcher of either kind.
    let (mut prek, mut classic) = (pre.as_deref().is_some_and(|t| is_prek(t, "pre-commit")), false);
    let mut missing = Vec::new();
    for hook in ["commit-msg", "post-commit"] {
        let path = repo.hook_path(hook)?;
        let shown = path.strip_prefix(repo.root()).unwrap_or(&path).display().to_string();
        let text = fs::read_to_string(&path).ok();
        let (ours, theirs) =
            (text.as_deref().is_some_and(|t| is_launcher(t, hook)), text.is_some_and(|t| is_prek(&t, hook)));
        (classic, prek) = (classic || ours, prek || theirs);
        if path.symlink_metadata().is_err() {
            missing.push(format!("hook {hook}"));
        } else if !ours && !theirs {
            return alien(format!("installed hook {hook} ({shown}) is not from pre-commit or prek"), "remove it");
        } else if !is_executable(&path) {
            missing.push(format!("hook {hook}"));
        }
    }
    let prek = prek || (!classic && !on_path("pre-commit") && on_path("prek"));
    let name = if prek { "prek" } else { "pre-commit" };
    let install = format!("{name} install -t commit-msg -t post-commit");
    let stageless = if default.as_ref().is_none_or(Vec::is_empty) { stageless } else { Vec::new() };
    Ok(Tool { name, writes, missing, install, stageless, exec_new: false })
}

/// A `stages` list: None when absent; a value that is not a list of text is `Err`.
fn stage_list(value: Option<&Value>) -> std::result::Result<Option<Vec<String>>, ()> {
    let Some(value) = value else { return Ok(None) };
    let list = value.as_sequence().ok_or(())?;
    list.iter().map(|v| v.as_str().map(String::from).ok_or(())).collect::<std::result::Result<_, _>>().map(Some)
}

/// The words of `text` as the POSIX shell splits them (quotes and `\`); None
/// when a quote is not closed.
fn shell_words(text: &str) -> Option<Vec<String>> {
    let (mut words, mut word, mut open) = (Vec::new(), None::<String>, None::<char>);
    let mut chars = text.chars();
    while let Some(c) = chars.next() {
        match (open, c) {
            (Some(q), c) if c == q => open = None,
            (Some('"'), '\\') => {
                let next = chars.next()?;
                let w = word.get_or_insert_with(String::new);
                if !matches!(next, '"' | '\\' | '$' | '`') {
                    w.push('\\');
                }
                w.push(next);
            }
            (Some(_), c) => word.get_or_insert_with(String::new).push(c),
            (None, '\'' | '"') => {
                open = Some(c);
                word.get_or_insert_with(String::new);
            }
            (None, '\\') => word.get_or_insert_with(String::new).push(chars.next()?),
            (None, c) if c.is_whitespace() => words.extend(word.take()),
            (None, c) => word.get_or_insert_with(String::new).push(c),
        }
    }
    words.extend(word);
    open.is_none().then_some(words)
}

/// 25.4: the script `pre-commit install` writes, for this hook and with the
/// config at the root; one with `-c` for another file is another script.
pub fn is_launcher(script: &str, hook: &str) -> bool {
    script.contains("# File generated by pre-commit")
        && script.contains(&format!("--config={PRE_COMMIT_CONFIG} --hook-type={hook})"))
}

/// 133.3: the script `prek install` writes for this hook, with the config at the
/// root: the marker line and one `exec "$PREK" hook-impl <options> -- ...` line.
pub(crate) fn is_prek(script: &str, hook: &str) -> bool {
    let lines: Vec<&str> = script.split('\n').map(|l| l.strip_suffix('\r').unwrap_or(l)).collect();
    let config = format!("--config={PRE_COMMIT_CONFIG}");
    let launch = |line: &&str| {
        let Some(words) = shell_words(line) else { return false };
        let Some(options) = words.strip_prefix(&["exec".to_string(), "$PREK".into(), "hook-impl".into()]) else {
            return false;
        };
        let options: Vec<&String> = options.iter().take_while(|w| *w != "--").collect();
        let configs: Vec<&&String> =
            options.iter().filter(|w| w.starts_with("--config") || w.as_str() == "-c").collect();
        options.iter().any(|w| **w == format!("--hook-type={hook}"))
            && (configs.is_empty() || (configs.len() == 1 && **configs[0] == config))
    };
    lines.iter().any(|l| l.starts_with("# File generated by prek")) && lines.iter().any(launch)
}

/// A file of the integration as text: None when absent; a link, a file that
/// does not read (no read permission) or that is not text refuses.
pub(crate) fn read(repo: &Repo, file: &str) -> Result<Option<String>> {
    let path = repo.path(file);
    match path.symlink_metadata() {
        Err(_) => return Ok(None),
        Ok(m) if m.file_type().is_symlink() => {
            return alien(format!("{file} is a symbolic link"), "replace it with the file")
        }
        Ok(_) => {}
    }
    match fs::read(&path).map(String::from_utf8) {
        Ok(Ok(text)) if !text.contains('\0') => Ok(Some(text)),
        Ok(_) => alien(format!("{file} is not text"), "replace it with text"),
        Err(e) => alien(format!("cannot read {file} ({e})"), "grant read permission"),
    }
}

fn parse(text: &str) -> std::result::Result<Value, serde_norway::Error> {
    serde_norway::from_str(text.strip_prefix('\u{feff}').unwrap_or(text))
}

/// The hook `i` as the init writes it, under `id` (133.5): exactly its 7 keys.
fn canonical(i: usize, local: bool, id: &str) -> Value {
    let doc = parse(&item(&[i], 0, 1, "\n", local)).unwrap_or(Value::Null);
    let mut hook = doc.get(0).and_then(|r| r.get("hooks")).and_then(|h| h.get(0)).cloned().unwrap_or(Value::Null);
    if let Some(map) = hook.as_mapping_mut() {
        map.insert("id".into(), id.into());
    }
    hook
}

/// A `repo: local` item with the hooks `wanted`, its dash at column `d` and
/// `s` spaces after each dash, in block layout (25.4: `stages` too); `local`, the
/// entry calls `./node_modules/.bin/shipcraft` (item 58).
pub(crate) fn item(wanted: &[usize], d: usize, s: usize, eol: &str, local: bool) -> String {
    let pad = |n: usize| " ".repeat(n);
    let dash = |n: usize| format!("{}-{}", pad(n), pad(s));
    let (k, h) = (d + 1 + s, 2 * d + 2 + 2 * s);
    let mut out = format!("{}repo: local{eol}{}hooks:{eol}", dash(d), pad(k));
    for &i in wanted {
        let (id, entry, stage) = HOOKS[i];
        let name = entry.trim_end_matches(" --commit-msg");
        let entry = if local { entry.replacen("shipcraft", LOCAL, 1) } else { entry.to_string() };
        out += &format!("{}id: {id}{eol}", dash(k + d));
        for line in [format!("name: {name}"), format!("entry: {entry}"), "language: system".into(), "stages:".into()] {
            out += &format!("{}{line}{eol}", pad(h));
        }
        out += &format!("{}{stage}{eol}", dash(h + d));
        out += &format!("{}always_run: true{eol}{}pass_filenames: false{eol}", pad(h), pad(h));
    }
    out
}

/// The text with the item appended at the end of the `repos` list, in the
/// indentation and the line ending the list already uses; None if unproved.
pub(crate) fn append(text: &str, wanted: &[usize], local: bool) -> Option<String> {
    // Every line break the parser reads (YAML 1.1); the first one is the eol.
    let breaks = ['\n', '\r', '\u{85}', '\u{2028}', '\u{2029}'];
    let (mut lines, mut from) = (Vec::new(), 0);
    for (i, c) in text.char_indices().filter(|&(i, c)| breaks.contains(&c) && !text[i..].starts_with("\r\n")) {
        lines.push(&text[from..i + c.len_utf8()]);
        from = i + c.len_utf8();
    }
    lines.extend((from < text.len()).then(|| &text[from..]));
    let eol = lines.first().map_or("", |l| &l[l.trim_end_matches(breaks).len()..]);
    let eol = if eol.is_empty() { "\n" } else { eol };
    let indent = |l: &str| l.len() - l.trim_start_matches(' ').len();
    let content = |l: &str| !l.trim().is_empty() && !l.trim_start().starts_with('#');
    let start = lines.iter().position(|l| l.strip_prefix("repos:").is_some_and(|r| !content(r)))?;
    let first = (start + 1..lines.len()).find(|&i| content(lines[i]))?;
    let (d, rest) = (indent(lines[first]), lines[first].trim_start().strip_prefix('-')?);
    let s = rest.len() - rest.trim_start_matches(' ').len();
    let inside = |l: &str| indent(l) > d || (indent(l) == d && l.trim_start().starts_with('-'));
    let last = (first..lines.len())
        .take_while(|&i| !content(lines[i]) || inside(lines[i]))
        .filter(|&i| content(lines[i]))
        .last()?;
    let mut new = lines[..=last].concat();
    if !new.ends_with(breaks) {
        new += eol;
    }
    Some(new + &item(wanted, d, s.max(1), eol, local) + &lines[last + 1..].concat())
}

/// The writes of `tool` and the `.shipcraft.toml` raise in one transaction: if a
/// write fails, every file written goes back byte by byte (15a.1).
pub fn write(repo: &Repo, tool: &Tool, min: Option<&(String, String)>) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    write_with(repo, tool, min, |path| fs::set_permissions(path, fs::Permissions::from_mode(0o755)))
}

/// `write` with the mode setter given (133.1: a failed mode undoes the run as a failed write does).
fn write_with(
    repo: &Repo,
    tool: &Tool,
    min: Option<&(String, String)>,
    mode: impl Fn(&Path) -> std::io::Result<()>,
) -> Result<()> {
    let config = min.map(|(old, new)| (CONFIG_FILE.to_string(), Some(old.clone()), new.clone()));
    let mut done = Vec::new();
    for (file, old, new) in config.iter().chain(&tool.writes) {
        let path = repo.path(file);
        let wrote = match fs::write(&path, new) {
            Err(e) => Err(format!("write {file}: {e}")),
            Ok(()) if tool.exec_new && old.is_none() => mode(&path).map_err(|e| format!("set the mode of {file}: {e}")),
            Ok(()) => Ok(()),
        };
        done.push((path, old));
        if let Err(message) = wrote {
            for (path, old) in done.iter().rev() {
                let _ = old.as_ref().map_or_else(|| fs::remove_file(path), |old| fs::write(path, old));
            }
            return Err(failed(message));
        }
        println!(
            "shipcraft: {} {file}",
            if file == CONFIG_FILE { "raised shipcraft_min (1.2) in" } else { "added shipcraft to" }
        );
    }
    Ok(())
}

/// 25.3, `shipcraft status`: by the tool only when both commands are as the init
/// writes them and both hooks are the tool's; otherwise what is missing.
pub fn status(decided: Result<Tool>) -> String {
    let tool = match decided {
        Ok(tool) => tool,
        Err(Stop::Refused(r)) => return format!("shipcraft: missing hook: `shipcraft init` refuses: {}", r.what()),
        Err(_) => {
            return "shipcraft: missing hook: `shipcraft init` cannot decide the integration; run it to see why".into()
        }
    };
    let mut wants: Vec<String> = tool.writes.iter().map(|(f, ..)| format!("the shipcraft command in {f}")).collect();
    wants.extend(tool.missing.iter().cloned());
    match wants.is_empty() {
        true => format!("shipcraft: hook through {} (commit-msg)", tool.name),
        false => format!(
            "shipcraft: missing hook: missing {}; run `shipcraft init` and `{}`",
            wants.join(", "),
            tool.install
        ),
    }
}

/// Item 25 in `shipcraft init`: what git still has to install, in one line.
pub fn notice(tool: &Tool) {
    if !tool.missing.is_empty() {
        println!(
            "shipcraft: still need to install {}: run `{}` so commits go through `shipcraft check --commit-msg` and `shipcraft close`",
            tool.missing.join(" and "),
            tool.install
        );
    }
}

/// 133.4, in `shipcraft init` right after `notice`: the hooks that will also run at commit-msg and post-commit.
pub fn stages_notice(tool: &Tool) {
    if !tool.stageless.is_empty() {
        let ids: Vec<String> = tool.stageless.iter().map(|id| crate::red::one_line(id)).collect();
        println!(
            "shipcraft: these pre-commit hooks have no stages in {PRE_COMMIT_CONFIG}, so they also run at commit-msg and post-commit: {}; to keep them at pre-commit only, add stages: [pre-commit] to them or default_stages: [pre-commit] at the top",
            short_list(&ids)
        );
    }
}

/// 133.1: a `foreign-hook` refusal whose Next is whole, with no manual branch.
pub(crate) fn alien_plain<T>(what: &str, how: &str) -> Result<T> {
    refuse("foreign-hook", what, WHY, how)
}

const WHY: &str = "shipcraft does not replace or edit another tool's hook: when in doubt, this step stays manual";

/// The `hook-alheio` refusal of this route: what keeps the integration, and
/// the commands by hand, never the `pre-commit`.
pub(crate) fn alien<T>(what: String, how: &str) -> Result<T> {
    refuse(
        "foreign-hook",
        what,
        WHY,
        format!("{how} and run `shipcraft init` again, or manually put `shipcraft check --commit-msg` in commit-msg and `shipcraft close` in post-commit"),
    )
}
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn appends_in_the_list_indentation() {
        let text = "repos:\n-   repo: x\n    hooks:\n    -   id: y\n        stages: [pre-commit]\ndefault_stages: [pre-commit]\n";
        let new = append(text, &[0, 1], false).unwrap();
        assert!(new.starts_with(text.trim_end_matches("default_stages: [pre-commit]\n")));
        assert!(
            new.contains("-   repo: local\n    hooks:\n    -   id: shipcraft-check\n        name: shipcraft check\n")
        );
        assert!(new.ends_with("default_stages: [pre-commit]\n"));
        let doc = parse(&new).unwrap();
        assert_eq!(doc["repos"][1]["hooks"][1], canonical(1, false, "shipcraft-close"));
        assert_eq!(doc["repos"][1]["hooks"][0]["stages"][0], Value::from("commit-msg"));
    }

    const PREK: &str = "#!/bin/sh\n# File generated by prek: https://github.com/j178/prek\n# ID: 182c10f181da4464a3eec51b83331688\nHERE=\"$(cd \"$(dirname \"$0\")\" && pwd)\"\nPREK=\"/usr/bin/prek\"\nexec \"$PREK\" hook-impl --hook-dir \"$HERE\" --script-version 4 --hook-type=commit-msg -- \"$@\"\n";

    #[test]
    fn reads_the_prek_launch_line() {
        assert!(is_prek(PREK, "commit-msg"));
        assert!(is_prek(&PREK.replace('\n', "\r\n"), "commit-msg"));
        assert!(!is_prek(PREK, "post-commit"));
        assert!(!is_prek(&PREK.replace("# File generated by prek", "# File"), "commit-msg"));
        let with = |extra: &str| PREK.replace(" -- ", &format!(" {extra} -- "));
        assert!(is_prek(&with("--config=\".pre-commit-config.yaml\""), "commit-msg"));
        assert!(!is_prek(&with("--config=\"other.yaml\""), "commit-msg"));
        assert!(!is_prek(&with("--config other.yaml"), "commit-msg"));
        assert!(!is_prek(&with("-c other.yaml"), "commit-msg"));
        assert!(!is_prek(&with("--config=.pre-commit-config.yaml --config=.pre-commit-config.yaml"), "commit-msg"));
        assert!(is_prek(&PREK.replace("\"$@\"", "-c x \"$@\""), "commit-msg"));
        assert!(!is_prek(&PREK.replace("exec \"$PREK\"", "echo exec \"$PREK\""), "commit-msg"));
        assert!(!is_prek(&PREK.replace("exec \"$PREK\"", "# exec \"$PREK\""), "commit-msg"));
        assert!(!is_prek(&PREK.replace("hook-impl", "hook-impl '"), "commit-msg"));
    }

    fn repo_with(config: &str) -> (crate::git::TempDir, Repo) {
        let dir = crate::git::TempDir::new("shipcraft-test-item133").unwrap();
        let out = std::process::Command::new("git").arg("init").arg("-q").arg(dir.path()).output().unwrap();
        assert!(out.status.success());
        fs::write(dir.path().join(PRE_COMMIT_CONFIG), config).unwrap();
        let repo = Repo::at_root(dir.path());
        (dir, repo)
    }

    fn hook(id: &str, stages: &str) -> String {
        format!("  - id: {id}\n    name: x\n    entry: x\n    language: system\n{stages}")
    }

    #[test]
    fn lists_the_hooks_with_no_stages() {
        let hooks = [
            hook("lint", ""),
            hook("typed", "    stages: [pre-push]\n"),
            hook("empty", "    stages: []\n"),
            hook("lint", ""),
            "  - id: 7\n    name: x\n    entry: x\n    language: system\n".to_string(),
        ];
        let config = format!("repos:\n- repo: local\n  hooks:\n{}", hooks.concat());
        let (_d, repo) = repo_with(&config);
        let tool = pre_commit_plan(&repo, None, false).unwrap_or_else(|e| panic!("{e:?}"));
        assert_eq!(tool.stageless, ["lint", "empty"]);
        assert_eq!(tool.writes.len(), 1);
        let (_d, repo) = repo_with(&format!("default_stages: [pre-commit]\n{config}"));
        assert!(pre_commit_plan(&repo, None, false).unwrap_or_else(|e| panic!("{e:?}")).stageless.is_empty());
        let (_d, repo) = repo_with(&format!("default_stages: []\n{config}"));
        assert_eq!(pre_commit_plan(&repo, None, false).unwrap_or_else(|e| panic!("{e:?}")).stageless.len(), 2);
    }

    #[test]
    fn reads_the_old_close_id() {
        let old = item(&[0, 1], 0, 1, "\n", false).replace("shipcraft-close", LEGACY);
        let (_d, repo) = repo_with(&format!("repos:\n{old}"));
        let tool = pre_commit_plan(&repo, None, false).unwrap_or_else(|e| panic!("{e:?}"));
        assert!(tool.writes.is_empty() && tool.stageless.is_empty());
        let both = format!(
            "{old}{}",
            item(&[1], 0, 1, "\n", false).replace("entry: shipcraft close\n", "entry: shipcraft close --x\n")
        );
        let (_d, repo) = repo_with(&format!("repos:\n{both}"));
        match pre_commit_plan(&repo, None, false) {
            Err(Stop::Refused(r)) => {
                assert_eq!(
                    r.what(),
                    ".pre-commit-config.yaml has both shipcraft-close and shipcraft-fecha (post-commit)"
                )
            }
            other => panic!("both ids must refuse: {:?}", other.map(|t| t.writes)),
        }
        let fecha = item(&[1], 0, 1, "\n", false).replace("shipcraft-close", LEGACY);
        let differs = fecha.replace("pass_filenames: false\n", "pass_filenames: true\n");
        let (_d, repo) = repo_with(&format!("repos:\n{differs}"));
        match pre_commit_plan(&repo, None, false) {
            Err(Stop::Refused(r)) => assert!(r.what().contains("`shipcraft-fecha`"), "{}", r.what()),
            _ => panic!("a differing old id must refuse"),
        }
    }

    #[test]
    fn a_failed_mode_undoes_the_run() {
        let dir = crate::git::TempDir::new("shipcraft-test-item133").unwrap();
        let repo = Repo::at_root(dir.path());
        fs::write(dir.path().join("kept"), "old").unwrap();
        fs::write(dir.path().join(CONFIG_FILE), "min").unwrap();
        let writes =
            vec![("kept".to_string(), Some("old".to_string()), "new".to_string()), ("made".into(), None, "x".into())];
        let tool =
            Tool { name: "husky", writes, missing: vec![], install: String::new(), stageless: vec![], exec_new: true };
        let min = ("min".to_string(), "raised".to_string());
        let refused = || std::io::Error::other("refused");
        match write_with(&repo, &tool, Some(&min), |_| Err(refused())) {
            Err(Stop::Failed(message)) => assert_eq!(message, "set the mode of made: refused"),
            _ => panic!("a failed mode must fail"),
        }
        assert_eq!(fs::read_to_string(dir.path().join("kept")).unwrap(), "old");
        assert_eq!(fs::read_to_string(dir.path().join(CONFIG_FILE)).unwrap(), "min");
        assert!(dir.path().join("made").symlink_metadata().is_err());
        assert!(write(&repo, &tool, None).is_ok());
        assert!(is_executable(&dir.path().join("made")) && !is_executable(&dir.path().join("kept")));
    }
}
