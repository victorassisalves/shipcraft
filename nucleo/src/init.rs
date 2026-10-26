//! `shipcraft init`: writes `.shipcraft.toml`, `.shipcraft/locks/` and the `AGENTS.md` block,
//! and installs the pre-commit hook. Nothing else is written, in the project or in `.git`: the
//! GitHub workflow is in `docs/github-ci.md`, for who turns it on (item 27). Review starts off (item 2) and, with `--github`, it marks
//! shipcraft/ci as required where GitHub protects branches (item 5.3).
//! It decides everything before asking or writing, and undoes its own writes
//! when one fails (item 15a). Where the lefthook runs the hook, it adds a `shipcraft`
//! command to the lefthook file instead of installing its own (item 15b), or
//! the two commands of the `commit-msg` route (item 20), as it does with the
//! husky 9 and the pre-commit framework (item 25).

use crate::config::{minimum_version, CONFIG_FILE};
use crate::gh;
use crate::git::{git_in, text, Repo, Snapshot};
use crate::glob;
use crate::init_msg::{self, Plan};
use crate::init_tool::{self, Tool};
use crate::lang::{self, Lang, Profile};
use crate::lock::LOCK_DIR;
use crate::refusal::{failed, refuse, Result};
use crate::suite::shell_quote;
use crate::tsbuild;
use std::fs;
use std::path::{Path, PathBuf};

const HOOK_MARK: &str = "# shipcraft hook";
pub const LEFTHOOK_FILES: [&str; 4] = ["lefthook.yml", ".lefthook.yml", "lefthook.yaml", ".lefthook.yaml"];
const IN_LEFTHOOK: &str = "in the run of an `shipcraft` command in the lefthook file pre-commit block";
const CONFIG_FAILS: &str = "in the project pre-commit hook, after fixing git config";
pub const AGENTS: [&str; 3] = ["codex", "claude", "gemini"];

const HEADER: &str = "\
# shipcraft: how the suite runs and where each layer runs. Changing this file with an
# open lock is refused. In test_command (and command), {junit} becomes the
# path where the runner writes its JUnit report. Optional check checks the
# whole project before tests: it runs in shipcraft ci and RED, never in the hook.
";

/// 15a.2: a `.git` above the current directory that git does not open (a
/// `git config` that fails) leaves the hook in doubt, not absent (rule 17).
pub fn open() -> Result<Repo> {
    Repo::open().or_else(|no_git| {
        let cwd = std::env::current_dir().map_err(|e| failed(format!("current directory: {e}")))?;
        if !cwd.ancestors().any(|d| d.join(".git").symlink_metadata().is_ok()) {
            return Err(no_git);
        }
        let out = git_in(&cwd, &["rev-parse", "--show-toplevel"])?;
        let why = text(&out.stderr).lines().next().unwrap_or_default().to_string();
        alien(format!("git cannot open this repository ({why})"), CONFIG_FAILS)
    })
}

pub fn run(repo: &Repo, lang_flag: Option<&str>, github: bool) -> Result<()> {
    crate::config::reject_legacy_file(repo, &Snapshot::Tree)?;
    let (lang, suites) = plan(repo, lang_flag)?;
    let hook = decide_hook(repo)?;
    let raise = if let Hook::Msg(_) | Hook::Tool(_) = &hook { init_msg::raise_min(repo)? } else { None };
    // Item 16b: proved on the tree before anything is written.
    let build = if repo.path(CONFIG_FILE).symlink_metadata().is_ok() { None } else { tsbuild::infer(repo)? };
    match suites.as_slice() {
        [(_, raiz, profile)] if raiz == "." => {
            println!("shipcraft: language {} (runner {})", lang.name(), profile.runner)
        }
        _ => println!("shipcraft: workspace {} with {} suite(s)", lang.name(), suites.len()),
    }
    let reviewer = reviewer();
    // Item 15a: a write that fails in the middle undoes what this run created.
    let mut created = Vec::new();
    let written = write_once(repo, &mut created, CONFIG_FILE, &config_text(lang, &suites, &reviewer, build.as_deref()))
        .and_then(|()| write_once(repo, &mut created, &format!("{LOCK_DIR}/.gitkeep"), ""))
        .and_then(|()| match &hook {
            Hook::Own(path) => install_hook(path, &mut created),
            Hook::Lefthook(file, old, new, _) => integrate(repo, file, old, new.as_deref()),
            Hook::Msg(plan) => init_msg::write(repo, plan, raise.as_ref()),
            Hook::Tool(tool) => init_tool::write(repo, tool, raise.as_ref()),
        });
    if let Err(stop) = written {
        for path in created.iter().rev() {
            let _ = fs::remove_file(path).or_else(|_| fs::remove_dir(path));
        }
        println!("shipcraft: undid what this run created");
        return Err(stop);
    }
    let agents = agents_block(repo);
    if let Some(command) = &build {
        println!("shipcraft: [build] in {CONFIG_FILE} runs `{command}` before suites");
    }
    if let Hook::Lefthook(.., false) = &hook {
        println!(
            "shipcraft: lefthook pre-commit hook is not installed: run `lefthook install` so commits go through `shipcraft check`"
        );
    }
    if let Hook::Msg(Plan { missing, .. }) = &hook {
        if !missing.is_empty() {
            println!("shipcraft: still need to install {}: run `lefthook install` so commits go through `shipcraft check --commit-msg` and `shipcraft close`", init_msg::hooks(missing));
        }
    }
    if let Hook::Tool(tool) = &hook {
        init_tool::notice(tool);
    }
    if github {
        protect(repo);
    }
    println!(
        "shipcraft: review is off. To have {reviewer} review each PR in a separate session, set review = \"local\" in {CONFIG_FILE} [execution] section; the diff goes to its provider."
    );
    let lefthook = match &hook {
        Hook::Lefthook(file, ..) | Hook::Msg(Plan { file, .. }) => format!(", {file}"),
        Hook::Tool(tool) => tool.writes.iter().map(|(file, ..)| format!(", {file}")).collect(),
        Hook::Own(_) => String::new(),
    };
    println!("shipcraft: ready. Commit {CONFIG_FILE}{lefthook}{agents} and {LOCK_DIR}/;");
    println!("shipcraft: then write the failing test and stub, and run `shipcraft red`.");
    // 27.1, read raw: a `shipcraft_min` above this binary keeps the file's real `ci`.
    let table = fs::read_to_string(repo.path(CONFIG_FILE)).ok().and_then(|t| t.parse::<toml::Table>().ok());
    let ci = table.as_ref().and_then(|t| t.get("execution")?.get("ci")?.as_str()).unwrap_or("local");
    if let Some(line) = ci_line(ci) {
        println!("{line}");
    }
    Ok(())
}

/// Item 27.1: where the CI runs, by the `ci` of the `.shipcraft.toml` left on the
/// tree (a kept one included).
fn ci_line(ci: &str) -> Option<&'static str> {
    match ci {
        "local" => {
            Some("CI runs on this machine through shipcraft pr. To run it on GitHub, see shipcraft docs/github-ci.md.")
        }
        "off" => Some("CI is off ([execution] ci = \"off\")."),
        "github" => Some(
            "CI runs on GitHub: the workflow is in shipcraft docs/github-ci.md if the project does not have one yet.",
        ),
        _ => None,
    }
}

/// The language and the suites: one per package with tests in a workspace,
/// or one at the root.
/// Suites to write: (nome, raiz, profile).
type Suites = Vec<(String, String, Profile)>;

fn plan(repo: &Repo, flag: Option<&str>) -> Result<(Lang, Suites)> {
    if flag.is_none() {
        if let Some((lang, patterns)) = lang::workspace(repo.root()) {
            let suites = workspace_suites(repo, lang, &patterns)?;
            if !suites.is_empty() {
                return Ok((lang, suites));
            }
        }
    }
    let lang = choose_lang(repo, flag)?;
    let profile = lang.profile(repo.root(), "node_modules/.bin/");
    Ok((lang, vec![(String::new(), ".".to_string(), profile)]))
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

fn choose_lang(repo: &Repo, flag: Option<&str>) -> Result<Lang> {
    if let Some(name) = flag {
        return match Lang::from_name(name) {
            Some(lang) => Ok(lang),
            None => refuse(
                "lang-unknown",
                format!("linguagem desconhecida: {name}"),
                "shipcraft knows the runner and stub for each language it supports",
                "use --lang python, --lang node or --lang go",
            ),
        };
    }
    match Lang::detect(repo.root()).as_slice() {
        [lang] => Ok(*lang),
        [] => refuse(
            "lang-unrecognized",
            "could not recognize the project language",
            "shipcraft recognizes a language by its project file, and found none it knows",
            "specify the language: shipcraft init --lang python|node|go",
        ),
        found => refuse(
            "lang-multiple",
            format!(
                "the project appears to use more than one language: {}",
                found.iter().map(|l| l.name()).collect::<Vec<_>>().join(", ")
            ),
            "each project has a runner and a suite; shipcraft does not choose for you",
            "specify the language: shipcraft init --lang python|node|go",
        ),
    }
}

/// Review is optional and off by default: init asks nothing and names the
/// first agent installed, so turning it on is one line.
fn reviewer() -> String {
    AGENTS.into_iter().find(|a| on_path(a)).unwrap_or("codex").to_string()
}

pub fn on_path(name: &str) -> bool {
    std::env::var_os("PATH")
        .map(|paths| std::env::split_paths(&paths).any(|dir| is_executable(&dir.join(name))))
        .unwrap_or(false)
}

pub fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    fs::metadata(path).map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0).unwrap_or(false)
}

fn quoted(s: &str) -> String {
    toml::Value::String(s.to_string()).to_string()
}

fn config_text(
    lang: Lang,
    suites: &[(String, String, Profile)],
    reviewer: &str,
    build: Option<&str>,
) -> String {
    let globs = |p: &Profile| {
        toml::Value::Array(p.globs.iter().map(|g| toml::Value::String(g.to_string())).collect()).to_string()
    };
    let check = |p: &Profile| p.check.as_ref().map_or(String::new(), |c| format!("check = {}\n", quoted(c)));
    let min = minimum_version();
    let mut text = format!("{HEADER}shipcraft_min = {}\nlang = {}\n", quoted(&min), quoted(lang.name()));
    if let [(_, raiz, profile)] = suites {
        if raiz == "." {
            text += &format!(
                "runner = {}\n{}test_command = {}\ntest_globs = {}\n",
                quoted(profile.runner),
                check(profile),
                quoted(&profile.command),
                globs(profile)
            );
        }
    }
    text += "\n[execution]\n# where each layer runs: local (on this machine), github or off\n# review is optional: \"local\" has [roles] review check each PR in a new session\nci = \"local\"\nreview = \"off\"\nci_timeout = 1800\n";
    text += &format!("\n[roles]\n# the review agent: codex, claude or gemini\nreview = {}\n", quoted(reviewer));
    text +=
        "\n[review]\n# seconds; optional project spec included in the brief: spec = \"docs/spec.md\"\ntimeout = 1200\n";
    if let Some(command) = build {
        text += &format!(
            "\n[build]\n# runs once at the root, before suites, in shipcraft ci and shipcraft red\ncommand = {}\n",
            quoted(command)
        );
    }
    if !(suites.len() == 1 && suites[0].1 == ".") {
        for (nome, raiz, profile) in suites {
            text += &format!(
                "\n[[suite]]\nname = {}\nroot = {}\n{}command = {}\nglobs = {}\n",
                quoted(nome),
                quoted(raiz),
                check(profile),
                quoted(&profile.command),
                globs(profile)
            );
        }
    }
    text
}

/// Item 5.3: marks shipcraft/ci as required where GitHub protects
/// branches. On a plan without protection it says so and goes on.
fn protect(repo: &Repo) {
    let branch = repo.default_branch();
    let body = r#"{"required_status_checks":{"strict":false,"contexts":["shipcraft/ci"]},"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null}"#;
    let path = format!("repos/{{owner}}/{{repo}}/branches/{branch}/protection");
    match gh::with_input(repo, &["api", "-X", "PUT", &path], body) {
        Ok(_) => println!("shipcraft: GitHub now requires shipcraft/ci to merge into {branch}."),
        Err(e) if e.contains("403") || e.contains("Upgrade to GitHub Pro") => {
            println!("shipcraft: this repository has no branch protection on its GitHub plan: `shipcraft merge` is the gate.")
        }
        Err(e) => println!("shipcraft: could not mark statuses as required ({e}); `shipcraft merge` is the gate."),
    }
}

const AGENTS_FILE: &str = "AGENTS.md";
const AGENTS_MARK: &str = "<!-- shipcraft -->";
const AGENTS_BLOCK: &str = "<!-- shipcraft -->
## Tests first, locked (shipcraft)

This repository uses shipcraft: the test that proves a change is written before the code, and the git hook refuses code that passes by changing the test.

1. **RED:** write the failing test and, if needed, a stub (the signature without the logic). Run `shipcraft red`: it locks the tests. Commit the tests, the stub and the new file in `.shipcraft/locks/` together.
2. **GREEN:** write the code until the tests pass. Do not change the locked tests: the hook refuses. If a test looks wrong, stop and tell whoever wrote the RED.
3. The lock closes by itself in the commit where the RED's cases pass.
4. A change that does not change behavior (docs, a refactor with the tests passing) needs no RED: the commit goes through.
5. Never use `git commit --no-verify`: `shipcraft ci` repeats every check and refuses the PR.
";

/// Tells agents the workflow where they already look: creates `AGENTS.md`, or
/// appends the block once to an existing one. A symlink is left alone, and a
/// failure here never undoes the init. Returns `, AGENTS.md` when it wrote.
fn agents_block(repo: &Repo) -> String {
    let path = repo.path(AGENTS_FILE);
    let written = match path.symlink_metadata() {
        Ok(meta) if !meta.is_file() => {
            println!("shipcraft: {AGENTS_FILE} is not a regular file, kept; add the shipcraft block from docs/spec.md by hand");
            return String::new();
        }
        Ok(_) => match fs::read_to_string(&path) {
            Ok(text) if text.contains(AGENTS_MARK) => {
                println!("shipcraft: {AGENTS_FILE} already has the shipcraft block, kept");
                return String::new();
            }
            Ok(text) => {
                let sep = if text.is_empty() || text.ends_with("\n\n") { "" } else if text.ends_with('\n') { "\n" } else { "\n\n" };
                fs::write(&path, format!("{text}{sep}{AGENTS_BLOCK}")).map(|()| "added the shipcraft block to")
            }
            Err(e) => Err(e),
        },
        Err(_) => fs::write(&path, AGENTS_BLOCK).map(|()| "created"),
    };
    match written {
        Ok(verb) => {
            println!("shipcraft: {verb} {AGENTS_FILE}");
            format!(", {AGENTS_FILE}")
        }
        Err(e) => {
            println!("shipcraft: could not write {AGENTS_FILE} ({e}); add the shipcraft block from docs/spec.md by hand");
            String::new()
        }
    }
}

/// Writes a project file unless it already exists (a link, even a broken one,
/// counts as existing: the init never writes through it).
fn write_once(repo: &Repo, created: &mut Vec<PathBuf>, relative: &str, content: &str) -> Result<()> {
    let path = repo.path(relative);
    if path.symlink_metadata().is_ok() {
        println!("shipcraft: {relative} already exists, kept");
        return Ok(());
    }
    write(&path, content, created)?;
    println!("shipcraft: created {relative}");
    Ok(())
}

/// Where `shipcraft check` goes: shipcraft's own hook, or a command in the lefthook file
/// (the file, its text, the new text, None when it already has the command,
/// and whether git runs the lefthook's hook: installed and executable, 15c.5),
/// or the two commands of the `commit-msg` route (item 20), or the husky's
/// or the pre-commit's (item 25).
enum Hook {
    Own(PathBuf),
    Lefthook(String, String, Option<String>, bool),
    Msg(Plan),
    Tool(Tool),
}

/// Item 15c.1, `shipcraft status`: the lefthook runs the hook only when its hook is
/// installed and its file has the `shipcraft` command; any doubt reads as no hook.
pub fn hook_status(repo: &Repo) -> String {
    match decide_hook(repo) {
        decided if init_tool::present(repo) => {
            init_tool::status(decided.and_then(|h| if let Hook::Tool(t) = h { Ok(t) } else { Err(failed(String::new())) }))
        }
        Ok(Hook::Lefthook(file, _, None, true)) => format!("shipcraft: hook through lefthook ({file}, shipcraft command)"),
        Ok(Hook::Lefthook(..)) => {
            "shipcraft: missing hook: the lefthook hook is not installed or its file has no shipcraft command; run `shipcraft init` and `lefthook install`".into()
        }
        // 20.3: by this route, each event says what it misses, even when the init refuses.
        decided if LEFTHOOK_FILES.iter().any(|f| fs::read_to_string(repo.path(f)).is_ok_and(|t| init_msg::route(&t) == Ok(true))) => {
            init_msg::status(repo, matches!(decided, Ok(Hook::Msg(_))))
        }
        Ok(Hook::Own(path)) if is_executable(&path) => "shipcraft: shipcraft hook installed".into(),
        _ => "shipcraft: missing hook: the commit does not go through `shipcraft check`; run `shipcraft init`".into(),
    }
}

/// Item 15a: the hook is decided before any question or write. shipcraft installs
/// its own hook only where no other tool manages pre-commit, and integrates
/// with the lefthook only where it surely runs the hook (item 15b); any doubt
/// is a refusal that leaves the tree as it was (rule 17).
fn decide_hook(repo: &Repo) -> Result<Hook> {
    let msg = LEFTHOOK_FILES
        .iter()
        .any(|f| fs::read_to_string(repo.path(f)).is_ok_and(|text| init_msg::route(&text) != Ok(false)));
    // The raw value, letter by letter (15a.3): '.git/hooks/', './.git/hooks',
    // the absolute path or a space refuse, even when they name the same directory.
    // Exit 1 is an unset key; any other failure is not absence (15a.2).
    let out = git_in(repo.root(), &["config", "core.hooksPath"])?;
    let dir = match out.status.code() {
        Some(1) => None,
        Some(0) => Some(text(out.stdout.strip_suffix(b"\n").unwrap_or(&out.stdout))),
        _ => {
            let why = text(&out.stderr).lines().next().unwrap_or_default().to_string();
            return hook_alien(msg, format!("git config fails ({why})"), CONFIG_FAILS);
        }
    };
    // Item 25 (changes 15a.2 and 15a.3): `.husky/` or the pre-commit config.
    if init_tool::present(repo) || init_tool::husky_path(dir.as_deref()) {
        return init_tool::decide(repo, dir.as_deref()).map(Hook::Tool);
    }
    if let Some(dir) = dir.filter(|d| d != ".git/hooks") {
        let what = format!("core.hooksPath is {dir:?}, and shipcraft only accepts .git/hooks, exactly");
        return hook_alien(msg, what, &format!("at the end of {dir}/pre-commit"));
    }
    let hook = repo.hook_path("pre-commit")?;
    let shown = hook.strip_prefix(repo.root()).unwrap_or(&hook).display().to_string();
    let installed = hook.symlink_metadata().is_ok().then(|| fs::read_to_string(&hook).unwrap_or_default());
    let runs = is_executable(&hook);
    let lefthook: Vec<&str> = LEFTHOOK_FILES.into_iter().filter(|f| repo.path(f).symlink_metadata().is_ok()).collect();
    match (lefthook.as_slice(), installed) {
        ([], Some(text)) if !text.contains(HOOK_MARK) => hook_alien(
            msg,
            format!("a pre-commit hook not owned by shipcraft already exists ({shown})"),
            &format!("at the end of {shown}"),
        ),
        // 15a.2: the first `lefthook install` would remove the shipcraft hook.
        ([], _) => match single_source(repo, "") {
            Ok(()) => Ok(Hook::Own(hook)),
            Err(problem) => hook_alien(
                msg,
                format!("lefthook configuration may be outside the 4 root names: {problem}"),
                IN_LEFTHOOK,
            ),
        },
        ([file], installed) => lefthook_hook(repo, file, installed, &shown, runs),
        (files, _) => hook_alien(
            msg,
            format!("there is more than one lefthook file at the root ({})", files.join(", ")),
            IN_LEFTHOOK,
        ),
    }
}

/// One lefthook file at the root: the route (item 20.1), then the conditions
/// of both routes (15a.2, 15b.1, 15b.3), then the route's own plan. In the
/// `commit-msg` route, the refusal never says to use the `pre-commit`.
fn lefthook_hook(repo: &Repo, file: &str, installed: Option<String>, shown: &str, runs: bool) -> Result<Hook> {
    let path = repo.path(file);
    let read = fs::read_to_string(&path);
    let route = read.as_deref().map_or(Ok(false), init_msg::route);
    let problem = if installed.is_some_and(|text| !init_msg::is_lefthook(&text, "pre-commit")) {
        Some(format!("{file} exists, but the installed pre-commit hook ({shown}) is not from lefthook"))
    } else if path.symlink_metadata().is_ok_and(|m| m.file_type().is_symlink()) {
        // 15b.3: a link is never written through.
        Some(format!("{file} is a symbolic link"))
    } else if let Err(problem) = single_source(repo, file) {
        Some(format!("{file} is not the only lefthook configuration: {problem}"))
    } else {
        read.as_ref().err().map(|e| format!("cannot read {file} ({e})"))
    };
    let msg = route != Ok(false);
    match (problem, read, route) {
        (Some(what), ..) => hook_alien(msg, what, IN_LEFTHOOK),
        (None, _, Err(problem)) => init_msg::alien(format!("{file} {problem}"), &problem),
        (None, Ok(text), Ok(true)) => init_msg::plan(repo, file, text).map(Hook::Msg),
        (None, Ok(text), Ok(false)) => match lefthook_plan(&text) {
            Ok(new) => Ok(Hook::Lefthook(file.to_string(), text, new, runs)),
            Err(problem) => alien(format!("{file} {problem}"), IN_LEFTHOOK),
        },
        (None, Err(e), _) => Err(failed(format!("read {file}: {e}"))),
    }
}

/// A name the lefthook reads its configuration from: `lefthook` or
/// `lefthook-local`, with or without the dot, in any format it reads.
pub fn lefthook_source(name: &str) -> bool {
    let name = name.strip_prefix('.').unwrap_or(name);
    let rest = name.strip_prefix("lefthook").map(|r| r.strip_prefix("-local").unwrap_or(r));
    rest.and_then(|r| r.strip_prefix('.')).is_some_and(|ext| ["yml", "yaml", "json", "jsonc", "toml"].contains(&ext))
}

/// 15b.1 and 15a.2: the lefthook reads its configuration from `file` alone
/// (from nothing, when `file` is empty), or the first source it may read
/// instead: `LEFTHOOK_CONFIG`, or `lefthook` or `lefthook-local`, with or
/// without the dot, in any format it reads, at the root or in `.config/`. A
/// directory it cannot list is a source in doubt, not an absent one (rule 17).
pub fn single_source(repo: &Repo, file: &str) -> std::result::Result<(), String> {
    if std::env::var_os("LEFTHOOK_CONFIG").is_some() {
        return Err("LEFTHOOK_CONFIG is set".into());
    }
    for dir in ["", ".config/"] {
        let path = repo.path(if dir.is_empty() { "." } else { dir });
        // Nothing there, or a plain file (named without the slash, which a
        // file refuses): surely no source inside.
        let plain = repo.path(dir.trim_end_matches('/')).symlink_metadata().is_ok_and(|m| m.is_file());
        if plain || path.symlink_metadata().map_or_else(|e| e.kind() == std::io::ErrorKind::NotFound, |m| m.is_file()) {
            continue;
        }
        let unread = |e: std::io::Error| format!("cannot read {} ({e})", if dir.is_empty() { "the root" } else { dir });
        for entry in fs::read_dir(&path).map_err(unread)? {
            let name = format!("{dir}{}", entry.map_err(unread)?.file_name().to_string_lossy());
            // Case-insensitive: so is the file system on macOS.
            let lower = name.to_ascii_lowercase();
            if lower != file && lefthook_source(&lower[dir.len()..]) {
                return Err(format!("found {name}"));
            }
        }
    }
    Ok(())
}

/// Item 15b: checks the lefthook file against points 1, 2 and 4 and returns its
/// text with a `shipcraft` command that runs last (None: the command is already
/// there), or the first condition it fails.
fn lefthook_plan(text: &str) -> std::result::Result<Option<String>, String> {
    use serde_norway::{Mapping, Value};
    let written = block_layout(text)?;
    let Ok(doc) = serde_norway::from_str::<Value>(text) else { return Err("cannot be read as YAML".into()) };
    let mut top = match doc {
        Value::Mapping(top) => top,
        Value::Null => Mapping::new(),
        _ => return Err("is not a YAML map".into()),
    };
    if let Some(key) = ["extends", "jobs", "remotes", "rc"].into_iter().find(|k| top.contains_key(k)) {
        return Err(format!("uses `{key}`"));
    }
    let mut block = match top.get("pre-commit") {
        None | Some(Value::Null) => Mapping::new(),
        Some(Value::Mapping(block)) => block.clone(),
        Some(_) => return Err("has a pre-commit block that is not a map".into()),
    };
    // 20.1: `parallel: false` counts as absent.
    let absent = |k: &Value| k.as_str() == Some("parallel") && block.get(k) == Some(&Value::Bool(false));
    if let Some(key) = block.keys().find(|k| k.as_str() != Some("commands") && !absent(k)) {
        return Err(format!("has `{}` in the pre-commit block besides commands", key.as_str().unwrap_or("?")));
    }
    let mut commands = match block.get("commands") {
        None | Some(Value::Null) => Mapping::new(),
        Some(Value::Mapping(commands)) => commands.clone(),
        Some(_) => return Err("has commands in pre-commit that is not a map".into()),
    };
    // 15b.2: the lefthook runs last a command without priority, or with 0; so
    // every other command needs a positive decimal one, written in it.
    let priority = |name: &str| {
        let (raw, plain) = written.iter().find(|(n, ..)| n == name).map(|(_, raw, plain)| (raw.as_str(), *plain))?;
        let decimal = plain && !raw.starts_with('0') && !raw.is_empty() && raw.bytes().all(|b| b.is_ascii_digit());
        decimal.then(|| raw.parse::<i32>().ok()).flatten()
    };
    let mut last = 0;
    for (name, command) in commands.iter().filter(|(name, _)| name.as_str() != Some("shipcraft")) {
        let name = name.as_str().unwrap_or("?");
        match priority(name) {
            Some(p) if command.is_mapping() => last = last.max(p),
            _ => return Err(format!("has command `{name}` without an explicit positive integer priority (without it, lefthook runs it last)")),
        }
    }
    if let Some(shipcraft) = commands.get("shipcraft") {
        let same = shipcraft.as_mapping().is_some_and(|m| m.len() == 2)
            && shipcraft.get("run").and_then(Value::as_str) == Some("shipcraft check")
            && priority("shipcraft").is_some_and(|p| p > last);
        return if same {
            Ok(None)
        } else {
            Err("already has an `shipcraft` command that is not just `run: shipcraft check` and the highest priority"
                .into())
        };
    }
    let next = last.checked_add(1).ok_or("has priority 2147483647, and shipcraft cannot run after it")?;
    let mut shipcraft = Mapping::new();
    shipcraft.insert("run".into(), "shipcraft check".into());
    shipcraft.insert("priority".into(), next.into());
    commands.insert("shipcraft".into(), Value::Mapping(shipcraft));
    block.insert("commands".into(), Value::Mapping(commands));
    top.insert("pre-commit".into(), Value::Mapping(block));
    // 15b.4: the text stays as it was, with the command added; if it does not
    // read back as the expected YAML, the init cannot prove where it goes.
    let new = insert_text(text, "pre-commit", &["run: shipcraft check".into(), format!("priority: {next}")]);
    match serde_norway::from_str::<Value>(&new) {
        Ok(back) if back == Value::Mapping(top) => Ok(Some(new)),
        _ => Err("cannot prove where to put the shipcraft command without changing the rest".into()),
    }
}

/// 15b.4, from the parser's events (not the text): the first thing that is not
/// the block layout (flow, an anchor or alias, a merge `<<`, a quoted key, a
/// `...`), or each pre-commit command's written priority: (name, raw, plain).
pub fn block_layout(text: &str) -> std::result::Result<Vec<(String, String, bool)>, String> {
    layout(text, false)
}

/// With `repos_only` (item 25), flow and quoted keys count only in the
/// `repos` key and its list; anchors, aliases, merges and `...` everywhere.
pub fn layout(text: &str, repos_only: bool) -> std::result::Result<Vec<(String, String, bool)>, String> {
    use std::mem::MaybeUninit;
    use unsafe_libyaml_norway as y;
    // One frame per open collection: (is a map, the key whose value comes next).
    let mut stack: Vec<(bool, Option<String>)> = Vec::new();
    let mut written = Vec::new();
    let mut parser = Box::new(MaybeUninit::<y::yaml_parser_t>::uninit());
    let parser = parser.as_mut_ptr();
    // SAFETY: the parser is initialized before use and deleted once; each
    // event is read while alive and deleted right after.
    unsafe {
        if y::yaml_parser_initialize(parser).fail {
            return Err("cannot be read as YAML".into());
        }
        y::yaml_parser_set_input_string(parser, text.as_ptr(), text.len() as u64);
        let result = loop {
            let mut event = MaybeUninit::<y::yaml_event_t>::uninit();
            if y::yaml_parser_parse(parser, event.as_mut_ptr()).fail {
                break Err("cannot be read as YAML".into());
            }
            let e = &*event.as_ptr();
            let step = layout_step(e, &mut stack, &mut written, repos_only);
            let end = e.type_ == y::YAML_STREAM_END_EVENT;
            y::yaml_event_delete(event.as_mut_ptr());
            match step {
                Err(problem) => break Err(problem),
                Ok(()) if end => break Ok(()),
                Ok(()) => {}
            }
        };
        y::yaml_parser_delete(parser);
        result.map(|()| written)
    }
}

/// One parser event of `block_layout`.
unsafe fn layout_step(
    e: &unsafe_libyaml_norway::yaml_event_t,
    stack: &mut Vec<(bool, Option<String>)>,
    written: &mut Vec<(String, String, bool)>,
    repos_only: bool,
) -> std::result::Result<(), String> {
    use unsafe_libyaml_norway::*;
    let styled = !repos_only || matches!(&stack[..], [(true, Some(k))] if k == "repos");
    let anchor = match e.type_ {
        YAML_SCALAR_EVENT => e.data.scalar.anchor,
        YAML_MAPPING_START_EVENT => e.data.mapping_start.anchor,
        YAML_SEQUENCE_START_EVENT => e.data.sequence_start.anchor,
        _ => std::ptr::null_mut(),
    };
    if e.type_ == YAML_ALIAS_EVENT || !anchor.is_null() {
        return Err("uses an anchor or alias".into());
    }
    if e.type_ == YAML_DOCUMENT_END_EVENT && !e.data.document_end.implicit {
        return Err("ends the document with `...`".into());
    }
    if styled
        && ((e.type_ == YAML_MAPPING_START_EVENT && e.data.mapping_start.style == YAML_FLOW_MAPPING_STYLE)
            || (e.type_ == YAML_SEQUENCE_START_EVENT && e.data.sequence_start.style == YAML_FLOW_SEQUENCE_STYLE))
    {
        return Err("uses flow style ({...} or [...])".into());
    }
    let is_key = matches!(stack.last(), Some((true, None)));
    match e.type_ {
        YAML_SCALAR_EVENT => {
            let s = &e.data.scalar;
            let value = String::from_utf8_lossy(std::slice::from_raw_parts(s.value, s.length as usize)).into_owned();
            let plain = s.style == YAML_PLAIN_SCALAR_STYLE && s.tag.is_null();
            if is_key && !plain && (!repos_only || (stack.len() == 1 && value == "repos")) {
                return Err("has a quoted key".into());
            }
            if is_key && value == "<<" {
                return Err("uses merge `<<`".into());
            }
            if is_key {
                stack.last_mut().unwrap().1 = Some(value);
                return Ok(());
            }
            let path: Vec<&str> = stack.iter().map(|(_, key)| key.as_deref().unwrap_or("-")).collect();
            if let ["pre-commit", "commands", name, "priority"] = path[..] {
                written.push((name.to_string(), value, plain));
            }
        }
        YAML_MAPPING_START_EVENT | YAML_SEQUENCE_START_EVENT if is_key => return Err("has a non-text key".into()),
        YAML_MAPPING_START_EVENT | YAML_SEQUENCE_START_EVENT => {
            stack.push((e.type_ == YAML_MAPPING_START_EVENT, None));
            return Ok(());
        }
        YAML_MAPPING_END_EVENT | YAML_SEQUENCE_END_EVENT => {
            stack.pop();
        }
        _ => return Ok(()),
    }
    // A value ended: its map waits for the next key.
    if let Some((true, key)) = stack.last_mut() {
        *key = None;
    }
    Ok(())
}

/// The lefthook text with a `shipcraft` command (its `body` lines) at the end of
/// `block:` → `commands:` (each created when missing), in the indentation
/// and the line ending the file already uses.
pub fn insert_text(text: &str, block: &str, body: &[String]) -> String {
    let text = &bare_nulls(text, block);
    let eol = if text.contains("\r\n") { "\r\n" } else { "\n" };
    let lines: Vec<&str> = text.split_inclusive('\n').collect();
    let indent = |l: &str| l.len() - l.trim_start_matches(' ').len();
    let content = |l: &str| !l.trim().is_empty() && !l.trim_start().starts_with('#');
    let key = |l: &str, k: &str| {
        l.trim_start().strip_prefix(k).is_some_and(|rest| rest.trim().is_empty() || rest.trim_start().starts_with('#'))
    };
    let end_of = |from: usize, depth: usize| {
        (from..lines.len()).find(|&i| content(lines[i]) && indent(lines[i]) <= depth).unwrap_or(lines.len())
    };
    let entry = |pad: usize, step: usize| {
        let (pad, inner) = (" ".repeat(pad), " ".repeat(pad + step));
        format!("{pad}shipcraft:{eol}") + &body.iter().map(|l| format!("{inner}{l}{eol}")).collect::<String>()
    };
    let (at, added) = match lines.iter().position(|l| indent(l) == 0 && key(l, &format!("{block}:"))) {
        None => (lines.len(), format!("{block}:{eol}  commands:{eol}{}", entry(4, 2))),
        Some(block) => {
            let end = end_of(block + 1, 0);
            match (block + 1..end).find(|&i| key(lines[i], "commands:")) {
                None => (block + 1, format!("  commands:{eol}{}", entry(4, 2))),
                Some(commands) => {
                    let depth = indent(lines[commands]);
                    let end = end_of(commands + 1, depth);
                    let pad = (commands + 1..end).find(|&i| content(lines[i])).map_or(depth + 2, |i| indent(lines[i]));
                    (end, entry(pad, pad - depth))
                }
            }
        }
    };
    let mut new = lines[..at].concat();
    if !new.is_empty() && !new.ends_with('\n') {
        new.push_str(eol);
    }
    new + &added + &lines[at..].concat()
}

/// 20.2: `block: null` (or `~`) and its `commands: null` become `block:` and
/// `commands:`, the comment kept, so the commands go in block layout.
fn bare_nulls(text: &str, block: &str) -> String {
    let mut inside = false;
    let mut out = String::new();
    for line in text.split_inclusive('\n') {
        let body = line.trim_end_matches(['\r', '\n']);
        let (eol, pad) = (&line[body.len()..], &body[..body.len() - body.trim_start().len()]);
        if pad.is_empty() && !body.is_empty() && !body.starts_with('#') {
            inside = body.starts_with(&format!("{block}:"));
        }
        let key = if pad.is_empty() { format!("{block}:") } else { "commands:".to_string() };
        let rest = body.trim_start().strip_prefix(&key).filter(|_| inside);
        let (value, comment) =
            rest.map_or(("", ""), |r| r.split_once('#').map_or((r, ""), |(v, _)| (v, &r[v.len()..])));
        if ["null", "Null", "NULL", "~"].contains(&value.trim()) {
            out +=
                &format!("{pad}{key}{}{eol}", if comment.is_empty() { String::new() } else { format!(" {comment}") });
        } else {
            out += line;
        }
    }
    out
}

/// Writes the lefthook file decided by `lefthook_plan`, or keeps it.
fn integrate(repo: &Repo, file: &str, old: &str, new: Option<&str>) -> Result<()> {
    let Some(new) = new else {
        println!("shipcraft: {file} already has the shipcraft command in pre-commit, kept");
        return Ok(());
    };
    let path = repo.path(file);
    fs::write(&path, new).map_err(|e| {
        let _ = fs::write(&path, old);
        failed(format!("write {file}: {e}"))
    })?;
    println!("shipcraft: added the shipcraft command (shipcraft check, last) to {file} pre-commit");
    Ok(())
}

/// In the `commit-msg` route (item 20.3), the refusal says what keeps the
/// integration from happening, not to use the `pre-commit`.
fn hook_alien<T>(msg: bool, what: String, place: &str) -> Result<T> {
    if msg {
        init_msg::alien(what.clone(), &what)
    } else {
        alien(what, place)
    }
}

/// The `hook-alheio` refusal: nothing written, and where `shipcraft check` goes.
fn alien<T>(what: String, place: &str) -> Result<T> {
    refuse(
        "foreign-hook",
        what,
        "shipcraft does not replace or edit another tool's hook: when in doubt, this step stays manual",
        format!("put `shipcraft check` {place}"),
    )
}

fn install_hook(hook: &Path, created: &mut Vec<PathBuf>) -> Result<()> {
    let exe = std::env::current_exe().map_err(|e| failed(format!("find the current binary: {e}")))?;
    let script = format!(
        "#!/bin/sh\n{HOOK_MARK}: checks the commit against open locks\nexec {} check\n",
        shell_quote(&exe.to_string_lossy())
    );
    write(hook, &script, created)?;
    make_executable(hook)?;
    println!("shipcraft: pre-commit hook installed");
    Ok(())
}

/// Writes a file, noting each directory and file it creates in `created`.
fn write(path: &Path, content: &str, created: &mut Vec<PathBuf>) -> Result<()> {
    let missing: Vec<&Path> = path.ancestors().skip(1).take_while(|d| d.symlink_metadata().is_err()).collect();
    for dir in missing.into_iter().rev() {
        fs::create_dir(dir).map_err(|e| failed(format!("create {}: {e}", dir.display())))?;
        created.push(dir.to_path_buf());
    }
    if path.symlink_metadata().is_err() {
        created.push(path.to_path_buf());
    }
    fs::write(path, content).map_err(|e| failed(format!("write {}: {e}", path.display())))
}

fn make_executable(path: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o755))
        .map_err(|e| failed(format!("make {} executable: {e}", path.display())))
}
