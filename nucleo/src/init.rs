//! `shipcraft init`: writes `.shipcraft.toml`, `.shipcraft/locks/`, the `AGENTS.md` block and its `CLAUDE.md` import (item 61),
//! the phase briefs in `.shipcraft/briefs/` (item 68),
//! and installs the pre-commit hook. Nothing else is written, in the project or in `.git`: the
//! GitHub workflow is in `docs/github-ci.md`, for who turns it on (item 27). Review is on when an agent is installed (item 2) and, with `--github`, it marks
//! the statuses as required where GitHub protects branches (item 5.3).
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
use crate::jsonc;
use crate::lang::{self, Lang, Profile};
use crate::lock::LOCK_DIR;
use crate::refusal::{failed, refuse, Result};
use crate::suite::shell_quote;
use crate::tsbuild;
use std::fs;
use std::path::{Path, PathBuf};

const HOOK_MARK: &str = "# shipcraft hook";
/// Item 58: how the hooks of a project-local install call it.
pub const LOCAL: &str = "./node_modules/.bin/shipcraft";
const PLAIN_LOCAL: &str = "\"$(git rev-parse --show-toplevel)/node_modules/.bin/shipcraft\"";
const LOCAL_NOTICE: &str =
    "shipcraft: hooks call this project's install (node_modules/.bin/shipcraft); upgrade it with your package manager";
pub const LEFTHOOK_FILES: [&str; 4] = ["lefthook.yml", ".lefthook.yml", "lefthook.yaml", ".lefthook.yaml"];
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
        let what = format!("git cannot open this repository ({why})");
        init_msg::alien(what.clone(), &what)
    })
}

/// The arguments of `init`, already past the syntax check (item 67).
#[derive(Default)]
pub struct Options<'a> {
    pub lang: Option<&'a str>,
    pub command: Option<&'a str>,
    pub globs: Vec<&'a str>,
    pub github: bool,
}

/// Item 67: the full form of `init --lang other`, in the `Next:` of its refusals.
const OTHER_FORM: &str =
    "shipcraft init --lang other --command '<test command writing JUnit to {junit}>' --glob '<test files>'";
const SEED_NOTICE: &str = "shipcraft: .shipcraft.toml exists and was kept; --command and --glob only seed a new config";

/// Item 67: a suite Shipcraft runs as written; its command and normalized globs.
struct Custom {
    command: String,
    globs: Vec<String>,
}

pub fn run(repo: &Repo, options: &Options) -> Result<()> {
    crate::config::reject_legacy_file(repo, &Snapshot::Tree)?;
    let custom = custom(options)?;
    let (lang, mut suites) = match &custom {
        Some(_) => (None, Vec::new()),
        None => plan(repo, options.lang).map(|(lang, suites)| (Some(lang), suites))?,
    };
    let install = install(repo);
    let local = matches!(install, Install::Project);
    let hook = decide_hook(repo, local)?;
    let raise = init_msg::raise_min(repo)?;
    // Item 16b: proved on the tree before anything is written.
    let kept = repo.path(CONFIG_FILE).symlink_metadata().is_ok();
    // Item 67: `--lang other` skips TypeScript build inference entirely.
    let (build, built) = match if kept || custom.is_some() { None } else { tsbuild::infer(repo)? } {
        Some((command, dirs)) => (Some(command), dirs),
        None => (None, Vec::new()),
    };
    let unchecked =
        if kept || lang != Some(Lang::Node) { Vec::new() } else { drop_empty_checks(repo, &mut suites, &built) };
    let workspace = !matches!(suites.as_slice(), [(_, raiz, _)] if raiz == ".");
    // Item 71: after [build] and item 56's judgement, before anything is written.
    let (probed, named) = if !kept && lang == Some(Lang::Node) && workspace {
        crate::init_probe::convert(repo.root(), &mut suites)
    } else {
        (Vec::new(), false)
    };
    match lang {
        None => println!("shipcraft: test command run as written (filter = \"command\")"),
        Some(lang) if !workspace => println!("shipcraft: language {} (runner {})", lang.name(), suites[0].2.runner),
        Some(lang) => println!("shipcraft: workspace {} with {} suite(s)", lang.name(), suites.len()),
    }
    for line in &probed {
        println!("{line}");
    }
    let reviewer = reviewer();
    // Item 15a: a write that fails in the middle undoes what this run created.
    let mut created = Vec::new();
    let written = write_once(repo, &mut created, CONFIG_FILE, &config_text(lang, custom.as_ref(), &suites, named, &reviewer, build.as_deref()))
        .and_then(|()| write_once(repo, &mut created, &format!("{LOCK_DIR}/.gitkeep"), ""))
        .and_then(|()| match &hook {
            Hook::Own(hooks) => install_hooks(hooks, local, &mut created),
            Hook::Msg(plan) => init_msg::write(repo, plan, raise.as_ref()).map(|()| plan.new.is_some()),
            Hook::Tool(tool) => init_tool::write(repo, tool, raise.as_ref()).map(|()| !tool.writes.is_empty()),
        });
    let wrote = written.as_ref().is_ok_and(|w| *w);
    if let Err(stop) = written {
        for path in created.iter().rev() {
            let _ = fs::remove_file(path).or_else(|_| fs::remove_dir(path));
        }
        println!("shipcraft: undid what this run created");
        return Err(stop);
    }
    if kept && custom.is_some() {
        println!("{SEED_NOTICE}");
    }
    let agents = agents_block(repo, local);
    // Item 68: only after everything else this run writes has succeeded.
    let briefs = crate::init_briefs::write(repo, local);
    if let Some(command) = &build {
        println!("shipcraft: [build] in {CONFIG_FILE} runs `{command}` before suites");
    }
    for line in &unchecked {
        println!("{line}");
    }
    // Item 58: only when this run wrote hooks.
    match &install {
        Install::Project if wrote => println!("{LOCAL_NOTICE}"),
        Install::Nested(dir) if wrote && matches!(hook, Hook::Own(_)) => println!(
            "shipcraft: installed under {}; hooks call this binary by its path (only the root node_modules is wired as the project's)",
            dir.display()
        ),
        _ => {}
    }
    if let Hook::Msg(Plan { missing, .. }) = &hook {
        if !missing.is_empty() {
            println!("shipcraft: still need to install {}: run `lefthook install` so commits go through `shipcraft check --commit-msg` and `shipcraft close`", init_msg::hooks(missing));
        }
    }
    if let Hook::Tool(tool) = &hook {
        init_tool::notice(tool);
    }
    if options.github {
        protect(repo, reviewer.is_some());
    }
    match &reviewer {
        Some(agent) => println!(
            "shipcraft: review by {agent}, in a separate session on this machine; the diff goes to its provider. To turn it off, set review = \"off\" in {CONFIG_FILE} [execution] section."
        ),
        None => println!(
            "shipcraft: no review agent installed (codex, claude or gemini): review stays off. To enable it, install one and set review = \"local\" in {CONFIG_FILE} [execution] section."
        ),
    }
    let lefthook = match &hook {
        Hook::Msg(Plan { file, .. }) => format!(", {file}"),
        Hook::Tool(tool) => tool.writes.iter().map(|(file, ..)| format!(", {file}")).collect(),
        Hook::Own(_) => String::new(),
    };
    println!("shipcraft: ready. Commit {CONFIG_FILE}{lefthook}{agents}{briefs} and {LOCK_DIR}/;");
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

/// Item 56: a suite whose `tsconfig.json` checks no file (a solution config)
/// loses its `tsc --noEmit` when `[build]` type-checks its folder, and keeps it
/// otherwise; either way a line says so. Item 72: any other suite whose folder
/// `[build]` names loses its check too, with its own line. Returns those lines,
/// in suite order.
fn drop_empty_checks(repo: &Repo, suites: &mut Suites, built: &[String]) -> Vec<String> {
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

/// Item 67: `--command` and `--glob` belong to `--lang other`, which needs both;
/// the command (step 3) is judged before the globs (step 4, the first invalid
/// one in argument order). Kept configs do not skip this.
fn custom(options: &Options) -> Result<Option<Custom>> {
    let other_refusal = |what: String| {
        refuse(
            "lang-unknown",
            what,
            "shipcraft runs a test command it does not know as written: it needs the command, {junit} where it writes its JUnit report, and the test files",
            OTHER_FORM,
        )
    };
    if options.lang != Some("other") {
        let given = match (options.command.is_some(), !options.globs.is_empty()) {
            (true, true) => "--command and --glob",
            (true, false) => "--command",
            (false, true) => "--glob",
            (false, false) => return Ok(None),
        };
        return other_refusal(format!("{given} given without --lang other"));
    }
    let Some(command) = options.command else {
        return other_refusal("--lang other needs --command".to_string());
    };
    if options.globs.is_empty() {
        return other_refusal("--lang other needs at least one --glob".to_string());
    }
    if let Some(problem) = command_problem(command) {
        return other_refusal(format!("the --command value {problem}"));
    }
    let mut globs: Vec<String> = Vec::new();
    for glob in &options.globs {
        match crate::config::normal_glob(glob) {
            Ok(normal) if globs.contains(&normal) => {}
            Ok(normal) => globs.push(normal),
            Err(problem) => {
                return refuse(
                    "config-invalid",
                    format!("--glob {} {problem}", shell_quote(&crate::red::one_line(glob))),
                    "the lock covers test files by their path within the project, and shipcraft does not guess another",
                    OTHER_FORM,
                )
            }
        }
    }
    Ok(Some(Custom { command: command.to_string(), globs }))
}

/// What breaks item 67's rules for `--command`, if anything.
fn command_problem(command: &str) -> Option<&'static str> {
    if command.matches("{junit}").count() != 1 {
        return Some("must contain {junit} exactly once");
    }
    if command.replacen("{junit}", "", 1).chars().all(char::is_whitespace) {
        return Some("has nothing but whitespace besides {junit}");
    }
    if command.chars().any(char::is_control) {
        return Some("has a control character");
    }
    None
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

/// Review is on by default with the first agent installed, and off when none
/// is; init asks nothing, and either way the change is one line.
fn reviewer() -> Option<String> {
    AGENTS.into_iter().find(|a| on_path(a)).map(str::to_string)
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
    lang: Option<Lang>,
    custom: Option<&Custom>,
    suites: &[(String, String, Profile)],
    named: bool,
    reviewer: &Option<String>,
    build: Option<&str>,
) -> String {
    let globs = |p: &Profile| {
        toml::Value::Array(p.globs.iter().map(|g| toml::Value::String(g.to_string())).collect()).to_string()
    };
    let check = |p: &Profile| p.check.as_ref().map_or(String::new(), |c| format!("check = {}\n", quoted(c)));
    let min = minimum_version();
    let mut text = format!("{HEADER}shipcraft_min = {}\n", quoted(&min));
    if let Some(lang) = lang {
        text += &format!("lang = {}\n", quoted(lang.name()));
    }
    // Item 67: no lang, runner, check or [build]; the command filters itself.
    if let Some(custom) = custom {
        let globs = toml::Value::Array(custom.globs.iter().map(|g| toml::Value::String(g.clone())).collect());
        text += &format!(
            "test_command = {}\ntest_globs = {globs}\nfilter = \"command\"\n",
            quoted(&custom.command)
        );
    }
    if let [(_, raiz, profile)] = suites {
        if raiz == "." && !named {
            text += &format!(
                "runner = {}\n{}test_command = {}\ntest_globs = {}\n",
                quoted(profile.runner),
                check(profile),
                quoted(&profile.command),
                globs(profile)
            );
        }
    }
    let review = if reviewer.is_some() { "local" } else { "off" };
    // Item 62: what each value means, and that suite_checks moves the suite
    // out of shipcraft/ci; above the table, and no suite_checks written.
    text += "\n# where each layer runs: \"local\" = on this machine, started by shipcraft pr; \"github\" = in this
# project's GitHub Actions (docs/github-ci.md); \"off\" = it does not run and shipcraft merge does not
# require it. shipcraft/ci re-checks every commit of the PR and runs the suite at its HEAD,
# unless suite_checks names GitHub checks that run the suite (docs/github-ci.md).
";
    text += &format!("[execution]\nci = \"local\"\nreview = \"{review}\"\nci_timeout = 1800\n");
    text += &format!(
        "\n[roles]\n# the review agent: codex, claude or gemini\nreview = {}\n",
        quoted(reviewer.as_deref().unwrap_or("codex"))
    );
    text +=
        "\n[review]\n# seconds; optional project spec included in the brief: spec = \"docs/spec.md\"\ntimeout = 1200\n";
    if let Some(command) = build {
        text += &format!(
            "\n[build]\n# runs once at the root, before suites, in shipcraft ci and shipcraft red\ncommand = {}\n",
            quoted(command)
        );
    }
    // Item 71: a converted suite keeps the [[suite]] form, even alone at root ".".
    if named || suites.len() > 1 || suites.first().is_some_and(|s| s.1 != ".") {
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

/// Item 5.3: marks shipcraft/ci, and shipcraft/review when review is on, as
/// required where GitHub protects branches. On a plan without protection it
/// says so and goes on.
fn protect(repo: &Repo, review: bool) {
    let branch = repo.default_branch();
    let contexts = if review { r#"["shipcraft/ci","shipcraft/review"]"# } else { r#"["shipcraft/ci"]"# };
    let body = format!(
        r#"{{"required_status_checks":{{"strict":false,"contexts":{contexts}}},"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null}}"#
    );
    let required = if review { "shipcraft/ci and shipcraft/review" } else { "shipcraft/ci" };
    let path = format!("repos/{{owner}}/{{repo}}/branches/{branch}/protection");
    match gh::with_input(repo, &["api", "-X", "PUT", &path], &body) {
        Ok(_) => println!("shipcraft: GitHub now requires {required} to merge into {branch}."),
        Err(e) if e.contains("403") || e.contains("Upgrade to GitHub Pro") => {
            println!("shipcraft: this repository has no branch protection on its GitHub plan: `shipcraft merge` is the gate.")
        }
        Err(e) => println!("shipcraft: could not mark statuses as required ({e}); `shipcraft merge` is the gate."),
    }
}

const AGENTS_FILE: &str = "AGENTS.md";
const CLAUDE_FILE: &str = "CLAUDE.md";
const START_LINE: &str = "<!-- shipcraft -->";
const END_LINE: &str = "<!-- /shipcraft -->";
/// Item 75: the line the current block gains right after the behavior-change line.
const FIX_LINE: &str = "- When the change fixes behavior a release already shipped, the RED runs `shipcraft red --fix`, with `--reported-at <time>` when the time the defect was first reported is known (for example `2026-10-31T00:36-03:00`) and `--fixes-release <tag>` when the release that shipped it is known (for example `v2.25.0`), so the lock records them.\n";
/// Item 74's block (commit f4220f1, v2.30.0), a known block in both variants;
/// the current block is it with `FIX_LINE` (`current_block`). Item 61's block
/// with item 68's rules: the machine install's block; a project-local install
/// gets it with `npx -- shipcraft` and the repository-root line (`variant`).
const AGENTS_BLOCK_2_30: &str = r#"<!-- shipcraft -->
## shipcraft: TDD with a lock (required in this repository)
- Cycle: RED (a failing test) → `shipcraft red` → GREEN (code) → `git commit`. The git hook checks every commit.
- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.
- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.
- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.
- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).
- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.
- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.
- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.
- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.
- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.
- If you run in a sandbox (for example Codex's `workspace-write`), run `shipcraft red`, `shipcraft red --redo` and `git commit` (its hook runs the locked tests) outside it when you can: inside, they can take many times longer, or fail when git cannot write its index. If you cannot, finish your files and stop (your files: those you added, changed or deleted, both sides of a rename), and give the user the steps to run in a POSIX shell where this project's tests run, each argument you fill in written in single quotes as above: first `cd` to this checkout's absolute path; for a RED, then `shipcraft red` (for a repair, `shipcraft red --redo`), which prints the lock's path; then `git --literal-pathspecs add -f --` with each of your files as its own argument and, for a RED, that lock path; then `git commit -m` with the message. A GREEN gets only the `cd`, `git add` and `git commit` steps. Tell the user to start from the first step that has not succeeded yet, and to stop and tell you if a step fails. If one of your files already had other changes before your phase, or `git diff --cached --name-only -z` lists a staged path that is not one of yours (or fails), say so and name those paths instead of handing the steps over. Change nothing after handing them over. Your phase ends there: you start no other phase, and a commit alone does not mean the lock closed (`shipcraft status` says).
- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.
- When in doubt, run `shipcraft status`.
<!-- /shipcraft -->
"#;
/// Item 74: item 70's block (commit e642432, v2.26.0 to v2.29.0), a known block in both variants.
const AGENTS_BLOCK_2_26: &str = r#"<!-- shipcraft -->
## shipcraft: TDD with a lock (required in this repository)
- Cycle: RED (a failing test) → `shipcraft red` → GREEN (code) → `git commit`. The git hook checks every commit.
- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.
- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.
- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.
- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).
- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.
- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.
- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.
- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.
- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.
- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.
- When in doubt, run `shipcraft status`.
<!-- /shipcraft -->
"#;
/// Item 70: the block at v2.25.0 (`git show v2.25.0:nucleo/src/init.rs`), a known block in both variants.
const AGENTS_BLOCK_2_25: &str = "<!-- shipcraft -->
## shipcraft: TDD with a lock (required in this repository)
- Cycle: RED (a failing test) → `shipcraft red` → GREEN (code) → `git commit`. The git hook checks every commit.
- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.
- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.
- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.
- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).
- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.
- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.
- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.
- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.
- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.
- When in doubt, run `shipcraft status`.
<!-- /shipcraft -->
";
/// Item 68: the block at v2.22.0 (`git show v2.22.0:nucleo/src/init.rs`), a known block in both variants.
const AGENTS_BLOCK_2_22: &str = "<!-- shipcraft -->
## shipcraft: TDD with a lock (required in this repository)
- Cycle: RED (a failing test) → `shipcraft red` → GREEN (code) → `git commit`. The git hook checks every commit.
- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.
- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.
- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).
- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.
- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back, and a RED session fixes it with `shipcraft red --redo`.
- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.
- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.
- When in doubt, run `shipcraft status`.
<!-- /shipcraft -->
";
const ROOT_LINE: &str =
    "- Run Shipcraft commands from the repository root, where `npx -- shipcraft` runs this project's install.\n";
/// The 2.14.0 block (`git show v2.14.0:nucleo/src/init.rs`): a start line, no end line.
const AGENTS_BLOCK_2_14: &str = "<!-- shipcraft -->
## shipcraft: TDD with a lock (required in this repository)
- Cycle: RED (a failing test) → `shipcraft red` → GREEN (code) → `git commit`. The git hook checks every commit.
- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.
- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.
- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*`, never touch the hook or `core.hooksPath`.
- When in doubt, run `shipcraft status`.
";
const CLAUDE_BLOCK: &str = "<!-- shipcraft -->\nShipcraft workflow (required): @AGENTS.md\n<!-- /shipcraft -->\n";
const DIFFERS: &str = "; it differs from this version's: edit it by hand to match docs/spec.md";

/// Item 61: the block's current variant; from a project-local install (item 58)
/// every command is `npx -- shipcraft` (fixed point 39), run from the root.
fn agents_text(local: bool) -> String {
    variant(&current_block(), local)
}

/// Item 75: item 74's block with `FIX_LINE` right after the line that starts
/// `- A behavior change: write the failing test first`.
fn current_block() -> String {
    let at = AGENTS_BLOCK_2_30.find("\n- A behavior change: write the failing test first").expect("the block has the line");
    let end = at + 1 + AGENTS_BLOCK_2_30[at + 1..].find('\n').expect("the line ends") + 1;
    format!("{}{FIX_LINE}{}", &AGENTS_BLOCK_2_30[..end], &AGENTS_BLOCK_2_30[end..])
}

/// A block (this version's, v2.30.0's, v2.26.0's, v2.25.0's or v2.22.0's) in its machine or project-local form.
fn variant(block: &str, local: bool) -> String {
    if !local {
        return block.to_string();
    }
    let text = block.replace("`shipcraft ", "`npx -- shipcraft ");
    let (head, rest) = text.split_at(text.find("\n- ").unwrap() + 1);
    format!("{head}{ROOT_LINE}{rest}")
}

/// Tells agents the workflow where they already look: `AGENTS.md` gets the
/// block, and `CLAUDE.md` imports it where Claude Code reads it (item 61). A
/// failure here never undoes the init. Returns the files it wrote, `, AGENTS.md`.
fn agents_block(repo: &Repo, local: bool) -> String {
    let new = agents_text(local);
    let other = agents_text(!local);
    let (bare_2_22, local_2_22) = (variant(AGENTS_BLOCK_2_22, false), variant(AGENTS_BLOCK_2_22, true));
    let (bare_2_25, local_2_25) = (variant(AGENTS_BLOCK_2_25, false), variant(AGENTS_BLOCK_2_25, true));
    let (bare_2_26, local_2_26) = (variant(AGENTS_BLOCK_2_26, false), variant(AGENTS_BLOCK_2_26, true));
    let (bare_2_30, local_2_30) = (variant(AGENTS_BLOCK_2_30, false), variant(AGENTS_BLOCK_2_30, true));
    let known = [
        other.as_str(),
        bare_2_22.as_str(),
        local_2_22.as_str(),
        bare_2_25.as_str(),
        local_2_25.as_str(),
        bare_2_26.as_str(),
        local_2_26.as_str(),
        bare_2_30.as_str(),
        local_2_30.as_str(),
    ];
    let (wrote, current) = onboard(repo, AGENTS_FILE, &new, &known, Some(AGENTS_BLOCK_2_14));
    let mut listed = if wrote { format!(", {AGENTS_FILE}") } else { String::new() };
    let claude = match repo.path(CLAUDE_FILE).symlink_metadata() {
        Ok(_) => true,
        Err(e) => e.kind() != std::io::ErrorKind::NotFound,
    };
    if claude || on_path("claude") {
        if !current {
            println!(
                "shipcraft: {CLAUDE_FILE} not written: {AGENTS_FILE} does not hold this version's shipcraft block"
            );
        } else if onboard(repo, CLAUDE_FILE, CLAUDE_BLOCK, &[], None).0 {
            listed.push_str(&format!(", {CLAUDE_FILE}"));
        }
    }
    listed
}

/// Writes `new` into `file`: created, appended once, or replacing a known block
/// (`known`, or `legacy` and what follows it); anything else is kept. A symlink
/// is left alone. Returns whether it wrote, and whether the file is a regular
/// one that now holds `new`.
fn onboard(repo: &Repo, file: &str, new: &str, known: &[&str], legacy: Option<&str>) -> (bool, bool) {
    let path = repo.path(file);
    let written = match path.symlink_metadata() {
        Ok(meta) if !meta.is_file() => {
            println!(
                "shipcraft: {file} is not a regular file, kept; add the shipcraft block from docs/spec.md by hand"
            );
            return (false, false);
        }
        Ok(_) => match fs::read_to_string(&path) {
            Ok(text) => match find_block(&text, new, known, legacy) {
                Found::None => {
                    let sep = if text.is_empty() || text.ends_with("\n\n") {
                        ""
                    } else if text.ends_with('\n') {
                        "\n"
                    } else {
                        "\n\n"
                    };
                    rewrite(&path, &format!("{text}{sep}{new}")).map(|()| "added the shipcraft block to")
                }
                Found::Equal => {
                    println!("shipcraft: {file} already has the shipcraft block, kept");
                    return (false, true);
                }
                Found::Known(range) => {
                    let text = format!("{}{new}{}", &text[..range.start], &text[range.end..]);
                    rewrite(&path, &text).map(|()| "replaced the shipcraft block in")
                }
                Found::Differs => {
                    println!("shipcraft: {file} already has the shipcraft block, kept{DIFFERS}");
                    return (false, false);
                }
            },
            Err(e) => Err(e),
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => fs::write(&path, new).map(|()| "created"),
        Err(e) => Err(e),
    };
    match written {
        Ok(verb) => {
            println!("shipcraft: {verb} {file}");
            (true, true)
        }
        Err(e) => {
            println!("shipcraft: could not write {file} ({e}); add the shipcraft block from docs/spec.md by hand");
            (false, false)
        }
    }
}

enum Found {
    None,
    Equal,
    Known(std::ops::Range<usize>),
    Differs,
}

/// Item 61: a marker is a whole line (`\n`-ended, a trailing `\r` ignored)
/// equal to the start or end line; a block runs from a start line through the
/// next end line. Only one start and one end, or the legacy start alone, are read.
fn find_block(text: &str, new: &str, known: &[&str], legacy: Option<&str>) -> Found {
    let mut markers = Vec::new();
    let mut at = 0;
    for line in text.split_inclusive('\n') {
        let bare = line.strip_suffix('\n').unwrap_or(line);
        let bare = bare.strip_suffix('\r').unwrap_or(bare);
        if bare == START_LINE || bare == END_LINE {
            markers.push((bare == START_LINE, at, at + line.len()));
        }
        at += line.len();
    }
    match markers.as_slice() {
        m if !m.iter().any(|(start, ..)| *start) => Found::None,
        [(true, from, _), (false, _, to)] => match &text[*from..*to] {
            block if block == new => Found::Equal,
            block if known.contains(&block) => Found::Known(*from..*to),
            _ => Found::Differs,
        },
        [(true, from, _)] => match legacy {
            Some(old) if text[*from..].starts_with(old) => Found::Known(*from..from + old.len()),
            _ => Found::Differs,
        },
        _ => Found::Differs,
    }
}

/// Rewrites an existing file through a temporary one in its folder, with the
/// old permission bits, renamed over it; a failure leaves the old bytes. A file
/// the owner may not write is not rewritten.
fn rewrite(path: &Path, text: &str) -> std::io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
    let mode = fs::metadata(path)?.permissions().mode() & 0o7777;
    if mode & 0o200 == 0 {
        return Err(std::io::ErrorKind::PermissionDenied.into());
    }
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    // A name of its own, created exclusively: an existing entry is never touched.
    let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_nanos());
    let mut attempt = 0u32;
    let (temp, mut file) = loop {
        let temp = path.with_file_name(format!(".{name}.shipcraft-{}-{nanos}-{attempt}.tmp", std::process::id()));
        match fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temp) {
            Ok(file) => break (temp, file),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists && attempt < 100 => attempt += 1,
            Err(e) => return Err(e),
        }
    };
    let result = file
        .write_all(text.as_bytes())
        .and_then(|()| file.sync_all())
        .and_then(|()| fs::set_permissions(&temp, fs::Permissions::from_mode(mode)))
        .and_then(|()| fs::rename(&temp, path));
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
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

/// Where `shipcraft check` goes. There is one route: `shipcraft check --commit-msg`
/// in `commit-msg` and `shipcraft close` in `post-commit`, through shipcraft's own
/// hooks, the lefthook file (item 20), or the husky 9 and pre-commit (item 25).
enum Hook {
    Own(Vec<PathBuf>),
    Msg(Plan),
    Tool(Tool),
}

/// `shipcraft status`: whether commits go through shipcraft; any doubt reads as no hook.
pub fn hook_status(repo: &Repo) -> String {
    match decide_hook(repo, false) {
        decided if init_tool::present(repo) => {
            init_tool::status(
                decided.and_then(|h| if let Hook::Tool(t) = h { Ok(t) } else { Err(failed(String::new())) }),
            )
        }
        // 20.3: each event says what it misses, even when the init refuses.
        decided if LEFTHOOK_FILES.iter().any(|f| repo.path(f).symlink_metadata().is_ok()) => {
            init_msg::status(repo, matches!(decided, Ok(Hook::Msg(_))))
        }
        Ok(Hook::Own(hooks)) if hooks.iter().all(|h| own_hook(h) && is_executable(h)) => {
            "shipcraft: shipcraft hooks installed (commit-msg and post-commit)".into()
        }
        _ => "shipcraft: missing hook: the commit does not go through `shipcraft check`; run `shipcraft init`".into(),
    }
}

/// Item 58: where the running binary is installed, both paths canonical.
pub(crate) enum Install {
    Machine,
    Project,
    /// A package's `node_modules` under the root.
    Nested(PathBuf),
}

/// Item 58: the project's install is a binary under `<root>/node_modules/`, with
/// `<root>/node_modules/.bin/shipcraft` an executable regular file; any doubt is the machine's.
fn install(repo: &Repo) -> Install {
    install_at(repo.root())
}

/// Item 58's rule for any working-tree root; item 69's hint applies it too.
pub(crate) fn install_at(root: &Path) -> Install {
    let exe = std::env::current_exe().and_then(fs::canonicalize);
    let (Ok(exe), Ok(root)) = (exe, fs::canonicalize(root)) else { return Install::Machine };
    let modules = root.join("node_modules");
    if exe.starts_with(&modules) {
        return if is_executable(&modules.join(".bin/shipcraft")) { Install::Project } else { Install::Machine };
    }
    let Ok(inside) = exe.strip_prefix(&root) else { return Install::Machine };
    let parent = inside.parent().unwrap_or(Path::new(""));
    let mut dir = root.clone();
    for part in parent.components() {
        dir.push(part);
        if part.as_os_str() == "node_modules" {
            return Install::Nested(dir);
        }
    }
    Install::Machine
}

fn own_hook(path: &Path) -> bool {
    fs::read_to_string(path).is_ok_and(|t| t.contains(HOOK_MARK))
}

/// Item 15a: the hook is decided before any question or write. shipcraft installs
/// its own hook only where no other tool manages pre-commit, and integrates
/// with the lefthook only where it surely runs the hook (item 15b); any doubt
/// is a refusal that leaves the tree as it was (rule 17).
fn decide_hook(repo: &Repo, local: bool) -> Result<Hook> {
    let stop = |what: String| init_msg::alien(what.clone(), &what);
    // The raw value, letter by letter (15a.3): '.git/hooks/', './.git/hooks',
    // the absolute path or a space refuse, even when they name the same directory.
    // Exit 1 is an unset key; any other failure is not absence (15a.2).
    let out = git_in(repo.root(), &["config", "core.hooksPath"])?;
    let dir = match out.status.code() {
        Some(1) => None,
        Some(0) => Some(text(out.stdout.strip_suffix(b"\n").unwrap_or(&out.stdout))),
        _ => {
            let why = text(&out.stderr).lines().next().unwrap_or_default().to_string();
            return stop(format!("git config fails ({why})"));
        }
    };
    // Item 25 (changes 15a.2 and 15a.3): `.husky/` or the pre-commit config.
    if init_tool::present(repo) || init_tool::husky_path(dir.as_deref()) {
        return init_tool::decide(repo, dir.as_deref(), local).map(Hook::Tool);
    }
    if let Some(dir) = dir.filter(|d| d != ".git/hooks") {
        return stop(format!("core.hooksPath is {dir:?}, and shipcraft only accepts .git/hooks, exactly"));
    }
    let lefthook: Vec<&str> = LEFTHOOK_FILES.into_iter().filter(|f| repo.path(f).symlink_metadata().is_ok()).collect();
    match lefthook.as_slice() {
        // 15a.2: the first `lefthook install` would remove the shipcraft hooks.
        [] => {
            if let Err(problem) = single_source(repo, "") {
                return stop(format!("lefthook configuration may be outside the 4 root names: {problem}"));
            }
            let mut hooks = Vec::new();
            for event in ["commit-msg", "post-commit"] {
                let hook = repo.hook_path(event)?;
                if hook.symlink_metadata().is_ok() && !own_hook(&hook) {
                    let shown = hook.strip_prefix(repo.root()).unwrap_or(&hook).display().to_string();
                    return stop(format!("a {event} hook not owned by shipcraft already exists ({shown})"));
                }
                hooks.push(hook);
            }
            Ok(Hook::Own(hooks))
        }
        [file] => lefthook_hook(repo, file, local),
        files => stop(format!("there is more than one lefthook file at the root ({})", files.join(", "))),
    }
}

/// One lefthook file at the root: the conditions (15b.1, 15b.3), then the
/// plan of item 20.
fn lefthook_hook(repo: &Repo, file: &str, local: bool) -> Result<Hook> {
    let path = repo.path(file);
    let problem = if path.symlink_metadata().is_ok_and(|m| m.file_type().is_symlink()) {
        // 15b.3: a link is never written through.
        Some(format!("{file} is a symbolic link"))
    } else if let Err(problem) = single_source(repo, file) {
        Some(format!("{file} is not the only lefthook configuration: {problem}"))
    } else {
        None
    };
    if let Some(what) = problem {
        return init_msg::alien(what.clone(), &what);
    }
    let text = fs::read_to_string(&path).map_err(|e| failed(format!("read {file}: {e}")))?;
    if let Err(problem) = init_msg::readable(&text) {
        return init_msg::alien(format!("{file} {problem}"), &problem);
    }
    init_msg::plan(repo, file, text, local).map(Hook::Msg)
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

/// Writes shipcraft's own hooks; whether it wrote any. Item 58: from the
/// project's install, they call the checkout's `node_modules/.bin/shipcraft`, and an
/// existing hook is kept; a hook in that form is kept by any binary.
fn install_hooks(hooks: &[PathBuf], local: bool, created: &mut Vec<PathBuf>) -> Result<bool> {
    let exe = std::env::current_exe().map_err(|e| failed(format!("find the current binary: {e}")))?;
    let exe = format!("exec {}", shell_quote(&exe.to_string_lossy()));
    let missing = "shipcraft: not installed in this checkout (node_modules/.bin/shipcraft)";
    let mut wrote = false;
    for hook in hooks {
        let msg = hook.ends_with("commit-msg");
        if own_hook(hook) && (local || fs::read_to_string(hook).is_ok_and(|t| t.contains(PLAIN_LOCAL))) {
            continue;
        }
        let (what, args) = if msg {
            ("checks the commit against open locks", "check --commit-msg \"$1\"")
        } else {
            ("closes the lock the commit-msg check marked", "close")
        };
        let script = if !local {
            format!("#!/bin/sh\n{HOOK_MARK}: {what}\n{exe} {args}\n")
        } else if msg {
            format!(
                "#!/bin/sh\n{HOOK_MARK}: {what}\nif [ ! -f {PLAIN_LOCAL} ] || [ ! -x {PLAIN_LOCAL} ]; then\n  echo \"{missing}: install the project's dependencies\" >&2\n  exit 1\nfi\nexec {PLAIN_LOCAL} {args}\n"
            )
        } else {
            format!(
                "#!/bin/sh\n{HOOK_MARK}: {what}\nif [ ! -f {PLAIN_LOCAL} ] || [ ! -x {PLAIN_LOCAL} ]; then\n  echo \"{missing}: the lock stays open; install the project's dependencies and run node_modules/.bin/shipcraft close\" >&2\n  exit 0\nfi\nexec {PLAIN_LOCAL} {args}\n"
            )
        };
        write(hook, &script, created)?;
        make_executable(hook)?;
        wrote = true;
    }
    if wrote {
        println!("shipcraft: commit-msg and post-commit hooks installed");
    } else {
        println!("shipcraft: commit-msg and post-commit hooks already installed, kept");
    }
    Ok(wrote)
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
