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

mod agents;
mod config_file;
mod custom;
mod files;
mod hook;
mod lefthook;
mod suites;

use crate::config::CONFIG_FILE;
use crate::gh;
use crate::git::{git_in, text, Repo, Snapshot};
use crate::init_msg::{self, Plan};
use crate::init_tool;
use crate::lang::{self, Lang};
use crate::lock::LOCK_DIR;
use crate::python_env;
use crate::refusal::{failed, Result};
use crate::tsbuild;
use std::fs;

use agents::agents_block;
use config_file::{config_text, reviewer};
use custom::custom;
use files::{keep_config, write_once};
use hook::{
    decide_hook, install, install_hooks, install_prefix, install_vitest, modules_not_ignored, uncommitted_manifests,
    Hook,
};
use suites::{drop_empty_checks, plan};

pub use agents::agents_block_status;
pub(crate) use agents::{marker_lines, rewrite, written_blocks, FORMS};
pub use config_file::AGENTS;
pub use files::{is_executable, on_path};
pub use hook::{hook_status, LEFTHOOK_FILES, LOCAL};
pub(crate) use hook::{hooks_path_by, install_at, invocation, written_hook, HooksPath, Install, HOOK_MARK};
pub use lefthook::{block_layout, insert_text, layout, lefthook_source, single_source};

const LOCAL_NOTICE: &str =
    "shipcraft: hooks call this project's install (node_modules/.bin/shipcraft); upgrade it with your package manager";

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

/// Item 67: the full form of `init --lang other`, in the `Next:` of its refusals,
/// after the project's invocation (item 131).
const OTHER_FORM: &str = "init --lang other --command '<test command writing JUnit to {junit}>' --glob '<test files>'";
const SEED_NOTICE: &str = "shipcraft: .shipcraft.toml exists and was kept; --command and --glob only seed a new config";

pub fn run(repo: &Repo, options: &Options) -> Result<()> {
    crate::config::reject_legacy_file(repo, &Snapshot::Tree)?;
    let install = install(repo);
    // Item 131: the lines that name a command name it as this install runs.
    let inv = invocation(repo.root(), &install);
    let custom = custom(options, inv)?;
    let (lang, mut suites) = match &custom {
        Some(_) => (None, Vec::new()),
        None => plan(repo, options.lang, inv)?,
    };
    let local = matches!(install, Install::Project);
    let hook = decide_hook(repo, local)?;
    let raise = init_msg::raise_min(repo)?;
    // Item 16b: proved on the tree before anything is written.
    let kept = repo.path(CONFIG_FILE).symlink_metadata().is_ok();
    // Item 67: `--lang other` skips TypeScript build inference entirely.
    let (build, built) = match if kept || lang.is_none() { None } else { tsbuild::infer(repo)? } {
        Some((command, dirs)) => (Some(command), dirs),
        None => (None, Vec::new()),
    };
    let unchecked =
        if kept || lang != Some(Lang::Node) { Vec::new() } else { drop_empty_checks(repo, &mut suites, &built) };
    let workspace = !matches!(suites.as_slice(), [(_, raiz, _)] if raiz == ".");
    // Item 134: the project's Python, only in a config this run writes.
    let python = (!kept && custom.is_none() && lang == Some(Lang::Python) && !workspace)
        .then(|| python_env::Choice::pick(repo.root()));
    if let Some(choice) = &python {
        suites[0].2.command = choice.command();
    }
    // Item 71: after [build] and item 56's judgement, before anything is written.
    let (probed, named) = if !kept && lang == Some(Lang::Node) && workspace {
        crate::init_probe::convert(repo.root(), &mut suites)
    } else {
        (Vec::new(), false)
    };
    match lang {
        None if custom.is_some() => println!("shipcraft: test command run as written (filter = \"command\")"),
        // Item 90: a kept config with no language chosen: neither line applies.
        None => {}
        Some(lang) if !workspace => {
            println!("shipcraft: language {} (runner {})", lang.name(), suites[0].2.runner);
            python.iter().for_each(|choice| println!("{}", choice.line()));
        }
        Some(lang) => println!("shipcraft: workspace {} with {} suite(s)", lang.name(), suites.len()),
    }
    for line in &probed {
        println!("{line}");
    }
    let reviewer = reviewer();
    // Item 15a: a write that fails in the middle undoes what this run created.
    let mut created = Vec::new();
    let config = if lang.is_none() && custom.is_none() {
        keep_config(repo)
    } else {
        write_once(
            repo,
            &mut created,
            CONFIG_FILE,
            &config_text(lang, custom.as_ref(), &suites, named, &reviewer, build.as_deref()),
        )
    };
    let written =
        config.and_then(|()| write_once(repo, &mut created, &format!("{LOCK_DIR}/.gitkeep"), "")).and_then(|()| {
            match &hook {
                Hook::Own(hooks) => install_hooks(hooks, local, &mut created),
                Hook::Msg(plan) => init_msg::write(repo, plan, raise.as_ref()).map(|()| plan.new.is_some()),
                Hook::Tool(tool) => init_tool::write(repo, tool, raise.as_ref()).map(|()| !tool.writes.is_empty()),
            }
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
    // Item 150: the block and the briefs in the form of item 131's invocation.
    let agents = agents_block(repo, inv);
    // Item 68: only after everything else this run writes has succeeded.
    let briefs = crate::init_briefs::write(repo, inv);
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
        init_tool::stages_notice(tool);
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
    // Item 147: a React app's first DOM test, in a config this run writes.
    if !kept && lang == Some(Lang::Node) && !workspace && lang::react_without_dom(repo.root()) {
        println!(
            "shipcraft: package.json depends on react: to test a component in a DOM with Testing Library, install them with `{} jsdom @testing-library/react` and start each such test file with the line // @vitest-environment jsdom",
            install_prefix(repo.root())
        );
    }
    // Item 131: the project's install, whose packages a `git add -A` would stage.
    if local && modules_not_ignored(repo.root()) {
        println!("shipcraft: node_modules is not ignored by git: add it to .gitignore before committing, or `git add -A` stages the installed packages");
    }
    if let Some(warning) =
        python.as_ref().and_then(|c| c.venv()).and_then(|d| python_env::unignored_warning(repo.root(), d))
    {
        println!("{warning}");
    }
    // Item 91: a new config whose root suite got vitest only by default.
    if !kept && lang == Some(Lang::Node) && !workspace && lang::node_runner(repo.root()).is_none() {
        println!(
            "shipcraft: warning: found neither vitest nor jest in package.json, so the test command assumes vitest. Install it with `{}`, or for another runner, from the repository root, remove {CONFIG_FILE} and run: {inv} {OTHER_FORM}",
            install_vitest(repo.root())
        );
    }
    let manifests = if local { uncommitted_manifests(repo.root()) } else { String::new() };
    println!("shipcraft: ready. Commit {CONFIG_FILE}{lefthook}{agents}{briefs}{manifests} and {LOCK_DIR}/;");
    println!("shipcraft: then write the failing test and stub, and run `{inv} red`.");
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
    println!("{}", protect_line(gh::with_input(repo, &["api", "-X", "PUT", &path], &body), required, &branch));
}

/// The one line `protect` prints; only GitHub's own words, never a local
/// failure's text (item 151), say the plan has no protection.
fn protect_line(result: std::result::Result<String, gh::Failure>, required: &str, branch: &str) -> String {
    match result {
        Ok(_) => format!("shipcraft: GitHub now requires {required} to merge into {branch}."),
        Err(gh::Failure::Answer(e)) if e.contains("Upgrade to GitHub Pro") => crate::inv::route(
            "shipcraft: this repository has no branch protection on its GitHub plan: `shipcraft merge` is the gate.",
        ),
        Err(e) => crate::inv::route(&format!(
            "shipcraft: could not mark statuses as required ({e}); `shipcraft merge` is the gate."
        )),
    }
}
