//! Which hook route a commit takes, the install's form, and shipcraft's own hooks (items 15a, 15b, 20, 25, 58).

use super::files::{is_executable, make_executable, on_path, write};
use super::lefthook::single_source;
use crate::git::{git_in, text, Repo};
use crate::init_hooks;
use crate::init_msg::{self, Plan};
use crate::init_tool::{self, Tool};
use crate::refusal::{failed, firm, refuse, Refusal, Result, Stop};
use crate::suite::shell_quote;
use std::fs;
use std::path::{Path, PathBuf};

pub(crate) const HOOK_MARK: &str = "# shipcraft hook";
/// Item 58: how the hooks of a project-local install call it.
pub const LOCAL: &str = "./node_modules/.bin/shipcraft";
const PLAIN_LOCAL: &str = "\"$(git rev-parse --show-toplevel)/node_modules/.bin/shipcraft\"";

pub const LEFTHOOK_FILES: [&str; 4] = ["lefthook.yml", ".lefthook.yml", "lefthook.yaml", ".lefthook.yaml"];

/// Where `shipcraft check` goes. There is one route: `shipcraft check --commit-msg`
/// in `commit-msg` and `shipcraft close` in `post-commit`, through shipcraft's own
/// hooks, the lefthook file (item 20), or the husky 9 and pre-commit (item 25).
pub(super) enum Hook {
    Own(Vec<PathBuf>),
    Msg(Plan),
    Tool(Tool),
    /// Item 153: hooks wired by hand, both paths as shown (`<commit-msg>, <post-commit>`).
    Hand(String),
}

/// `shipcraft status`: whether commits go through shipcraft; any doubt reads as no hook.
pub fn hook_status(repo: &Repo) -> String {
    // core.hooksPath is read once, for item 101's route and for today's.
    let path = hooks_path(repo);
    // Item 101: hooks a project keeps in its own core.hooksPath.
    if let Ok(HooksPath::Set(dir)) = &path {
        if let Some(line) = init_hooks::status(repo, dir) {
            return line;
        }
    }
    match path.and_then(|path| decide_hook_with(repo, false, path)) {
        // Item 153, point 5: through a yielding refusal, hooks wired by hand.
        Ok(Hook::Hand(_)) => "shipcraft: hooks call shipcraft, wired by hand (commit-msg and post-commit)".into(),
        Err(Stop::Refused(r)) if r.what() == RUNS_CHECK => {
            format!("shipcraft: missing hook: `shipcraft init` refuses: {}", r.what())
        }
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
pub(super) fn install(repo: &Repo) -> Install {
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

/// Items 69 and 131: how this project runs shipcraft, by the install's form:
/// the project's install gets `pnpm exec` when a regular `pnpm-lock.yaml` sits
/// at the root and `pnpm` is on `PATH`, `npx --` otherwise; any other is `shipcraft`.
pub(crate) fn invocation(root: &Path, install: &Install) -> &'static str {
    if !matches!(install, Install::Project) {
        return "shipcraft";
    }
    if regular(&root.join("pnpm-lock.yaml")) && on_path("pnpm") {
        "pnpm exec shipcraft"
    } else {
        "npx -- shipcraft"
    }
}

fn regular(path: &Path) -> bool {
    path.symlink_metadata().is_ok_and(|m| m.file_type().is_file())
}

/// Item 131: the command that installs vitest, by the first regular lockfile at the root.
pub(super) fn install_vitest(root: &Path) -> String {
    format!("{} vitest", install_prefix(root))
}

/// Item 131's lockfile rule without the packages (item 147 adds its own).
pub(super) fn install_prefix(root: &Path) -> &'static str {
    if regular(&root.join("pnpm-lock.yaml")) {
        return if root.join("pnpm-workspace.yaml").symlink_metadata().is_ok() {
            "pnpm add -D -w"
        } else {
            "pnpm add -D"
        };
    }
    if regular(&root.join("yarn.lock")) {
        return "yarn add -D";
    }
    if regular(&root.join("bun.lock")) || regular(&root.join("bun.lockb")) {
        return "bun add -d";
    }
    "npm install -D"
}

/// Item 131: the root manifest and lockfiles, regular files that git reports as
/// not committed, each as `, <file>` for the `ready` line.
pub(super) fn uncommitted_manifests(root: &Path) -> String {
    let files = ["package.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock", "bun.lockb", "package-lock.json"];
    let changed = |file: &str| {
        regular(&root.join(file))
            && git_in(root, &["status", "--porcelain=v1", "-z", "--", file])
                .is_ok_and(|out| out.status.success() && !out.stdout.is_empty())
    };
    files.into_iter().filter(|file| changed(file)).map(|file| format!(", {file}")).collect()
}

/// Item 131: whether git says `node_modules` is not ignored (exit 1 only).
pub(super) fn modules_not_ignored(root: &Path) -> bool {
    // Without `--literal-pathspecs`, which `check-ignore` refuses.
    let mut git = std::process::Command::new("git");
    git.arg("-C").arg(root).args(["check-ignore", "-q", "--", "node_modules"]);
    git.output().is_ok_and(|out| out.status.code() == Some(1))
}

fn own_hook(path: &Path) -> bool {
    fs::read_to_string(path).is_ok_and(|t| t.contains(HOOK_MARK))
}

/// `git config core.hooksPath`, read once for `init` and `status`.
pub(crate) enum HooksPath {
    Unset,
    /// The raw value.
    Set(String),
    /// Any exit other than 0 or 1: the first line of git's error.
    Fails(String),
}

/// The raw value, letter by letter (15a.3): '.git/hooks/', './.git/hooks',
/// the absolute path or a space refuse, even when they name the same directory.
/// Exit 1 is an unset key; any other failure is not absence (15a.2).
pub(crate) fn hooks_path(repo: &Repo) -> Result<HooksPath> {
    hooks_path_by(repo, &["config", "core.hooksPath"])
}

/// `hooks_path` through these `git config` arguments (item 143 reads it with `--get`).
pub(crate) fn hooks_path_by(repo: &Repo, args: &[&str]) -> Result<HooksPath> {
    let out = git_in(repo.root(), args)?;
    Ok(match out.status.code() {
        Some(1) => HooksPath::Unset,
        Some(0) => HooksPath::Set(text(out.stdout.strip_suffix(b"\n").unwrap_or(&out.stdout))),
        _ => HooksPath::Fails(text(&out.stderr).lines().next().unwrap_or_default().to_string()),
    })
}

/// Item 15a: the hook is decided before any question or write. shipcraft installs
/// its own hook only where no other tool manages pre-commit, and integrates
/// with the lefthook only where it surely runs the hook (item 15b); any doubt
/// is a refusal that leaves the tree as it was (rule 17).
pub(super) fn decide_hook(repo: &Repo, local: bool) -> Result<Hook> {
    decide_hook_with(repo, local, hooks_path(repo)?)
}

/// `decide_hook` with `core.hooksPath` already read; item 153: a yielding refusal
/// goes to the hand-wired route.
fn decide_hook_with(repo: &Repo, local: bool, path: HooksPath) -> Result<Hook> {
    match route(repo, local, path) {
        Err(Stop::Refused(refusal)) if refusal.yields() => hand(repo, refusal, local),
        decided => decided,
    }
}

/// The routes of items 15a, 15b, 20 and 25, in their order.
fn route(repo: &Repo, local: bool, path: HooksPath) -> Result<Hook> {
    let stop = |what: String| init_msg::alien(what.clone(), &what);
    let dir = match path {
        HooksPath::Unset => None,
        HooksPath::Set(dir) => Some(dir),
        HooksPath::Fails(why) => return stop(format!("git config fails ({why})")).map_err(firm),
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

/// Item 153, point 4's pre-commit check, also read by `status` (point 5).
const RUNS_CHECK: &str = "the installed pre-commit hook runs `shipcraft check`";

/// Item 153, points 3 and 4: hooks wired by hand (point 1) in place of a yielding
/// `refusal`, or `refusal` with the manual branch naming the two files `init` reads.
fn hand(repo: &Repo, refusal: Refusal, local: bool) -> Result<Hook> {
    let mut paths = Vec::new();
    for hook in ["commit-msg", "post-commit"] {
        match repo.hook_path(hook) {
            Ok(path) => paths.push(path),
            Err(_) => return Err(Stop::Refused(refusal.branch(""))),
        }
    }
    let shown: Vec<String> =
        paths.iter().map(|p| p.strip_prefix(repo.root()).unwrap_or(p).display().to_string()).collect();
    if !init_hooks::wired(&paths) {
        let bin = if local { LOCAL } else { "shipcraft" };
        let branch = format!(
            ", or make `{bin} check --commit-msg \"$1\"` the last command of {} and `{bin} close` the last command of {}, each file starting with `#!/bin/sh` and with no `exit` or `exec` line before that call, both executable, and run `shipcraft init` again",
            shown[0], shown[1]
        );
        return Err(Stop::Refused(refusal.branch(&branch)));
    }
    let pre = repo.hook_path("pre-commit")?;
    let runs = is_executable(&pre)
        && fs::read(&pre).is_ok_and(|b| {
            b.windows(HOOK_MARK.len()).any(|w| w == HOOK_MARK.as_bytes()) || init_hooks::calls(&b, &["check"])
        });
    if runs {
        return refuse(
            "foreign-hook",
            RUNS_CHECK,
            "shipcraft does not replace or edit another tool's hook: when in doubt, this step stays manual",
            "with it, the suite would run twice per commit: remove it and run `shipcraft init` again",
        );
    }
    Ok(Hook::Hand(shown.join(", ")))
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

/// Writes shipcraft's own hooks; whether it wrote any. Item 58: from the
/// project's install, they call the checkout's `node_modules/.bin/shipcraft`, and an
/// existing hook is kept; a hook in that form is kept by any binary.
pub(super) fn install_hooks(hooks: &[PathBuf], local: bool, created: &mut Vec<PathBuf>) -> Result<bool> {
    let exe = std::env::current_exe().map_err(|e| failed(format!("find the current binary: {e}")))?;
    let exe = format!("exec {}", shell_quote(&exe.to_string_lossy()));
    let mut wrote = false;
    for hook in hooks {
        let msg = hook.ends_with("commit-msg");
        if own_hook(hook) && (local || fs::read_to_string(hook).is_ok_and(|t| t.contains(PLAIN_LOCAL))) {
            continue;
        }
        write(hook, &hook_script(msg, local, &exe), created)?;
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

/// Item 143: the bytes of `init`'s own hook (`msg`: commit-msg); the machine form runs `exe` (`exec <word>`).
fn hook_script(msg: bool, local: bool, exe: &str) -> String {
    let missing = "shipcraft: not installed in this checkout (node_modules/.bin/shipcraft)";
    let (what, args) = if msg {
        ("checks the commit against open locks", "check --commit-msg \"$1\"")
    } else {
        ("closes the lock the commit-msg check marked", "close")
    };
    if !local {
        format!("#!/bin/sh\n{HOOK_MARK}: {what}\n{exe} {args}\n")
    } else if msg {
        format!(
            "#!/bin/sh\n{HOOK_MARK}: {what}\nif [ ! -f {PLAIN_LOCAL} ] || [ ! -x {PLAIN_LOCAL} ]; then\n  echo \"{missing}: install the project's dependencies\" >&2\n  exit 1\nfi\nexec {PLAIN_LOCAL} {args}\n"
        )
    } else {
        format!(
            "#!/bin/sh\n{HOOK_MARK}: {what}\nif [ ! -f {PLAIN_LOCAL} ] || [ ! -x {PLAIN_LOCAL} ]; then\n  echo \"{missing}: the lock stays open; install the project's dependencies and run node_modules/.bin/shipcraft close\" >&2\n  exit 0\nfi\nexec {PLAIN_LOCAL} {args}\n"
        )
    }
}

/// Item 143: `bytes` are a hook `init` writes: the project-local form, or the machine form with any `shell_quote`d path.
pub(crate) fn written_hook(msg: bool, bytes: &[u8]) -> bool {
    let template = hook_script(msg, false, "exec \0");
    let (head, tail) = template.split_once('\0').unwrap_or_default();
    let word = std::str::from_utf8(bytes).ok().and_then(|t| t.strip_prefix(head)?.strip_suffix(tail));
    let quoted =
        word.and_then(|w| w.strip_prefix('\'')?.strip_suffix('\'')).map(|i| shell_quote(&i.replace("'\"'\"'", "'")));
    bytes == hook_script(msg, true, "").as_bytes() || (quoted.is_some() && quoted.as_deref() == word)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_hooks_init_writes() {
        for msg in [true, false] {
            for path in ["/usr/local/bin/shipcraft", "/a b/it's/shipcraft", ""] {
                let script = hook_script(msg, false, &format!("exec {}", shell_quote(path)));
                assert!(written_hook(msg, script.as_bytes()), "{path}");
            }
            assert!(written_hook(msg, hook_script(msg, true, "").as_bytes()));
            assert!(!written_hook(!msg, hook_script(msg, true, "").as_bytes()));
            let plain = hook_script(msg, false, "exec '/x/shipcraft'");
            assert!(!written_hook(!msg, plain.as_bytes()));
            for edited in [
                plain.replace("'/x/shipcraft'", "/x/shipcraft"),
                plain.replace("'/x/shipcraft'", "'/x/s'hipcraft'"),
                plain.replace("'/x/shipcraft'", "'"),
                plain.replace('\n', "\r\n"),
                format!("{plain}\n"),
                plain.replace("exec ", "exec  "),
            ] {
                assert!(!written_hook(msg, edited.as_bytes()), "{edited:?}");
            }
        }
    }

    #[test]
    fn install_prefix_follows_the_lockfile_rule() {
        let dir = std::env::temp_dir().join(format!("sc-prefix-{}", std::process::id()));
        fs::create_dir_all(&dir).unwrap();
        assert_eq!(install_prefix(&dir), "npm install -D");
        assert_eq!(install_vitest(&dir), "npm install -D vitest");
        for (lock, prefix) in
            [("bun.lockb", "bun add -d"), ("yarn.lock", "yarn add -D"), ("pnpm-lock.yaml", "pnpm add -D")]
        {
            fs::write(dir.join(lock), "").unwrap();
            assert_eq!(install_prefix(&dir), prefix);
        }
        fs::write(dir.join("pnpm-workspace.yaml"), "").unwrap();
        assert_eq!(install_vitest(&dir), "pnpm add -D -w vitest");
        fs::remove_dir_all(&dir).unwrap();
    }
}
