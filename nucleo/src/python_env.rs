//! Item 134: which Python runs a project's pytest suite. `init` picks the
//! project's virtual environment (or uv) over a bare `python3`; a suite whose
//! interpreter is missing says so; a linked worktree borrows the main
//! worktree's venv; `status` names a bare `python3` beside a venv.

use crate::config::{Config, Suite, CONFIG_FILE};
use crate::git::{text, Repo};
use crate::init::{is_executable, on_path};
use crate::suite::shell_quote;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// What follows the interpreter in the command `init` writes for pytest.
pub const PYTEST_ARGS: &str = "-m pytest -p no:cacheprovider --junitxml={junit}";

const EDIT: &str = "to use another, edit test_command in .shipcraft.toml";

/// The interpreter `init` writes, first match (point 1).
#[derive(Debug, PartialEq, Eq)]
pub enum Choice {
    /// `.venv` or `venv`: its `bin/python` is an executable file.
    Venv(&'static str),
    /// `uv.lock` at the root and `uv` on `PATH`.
    Uv,
    /// `poetry.lock` at the root and `poetry` on `PATH` (item 152).
    Poetry,
    Path,
}

impl Choice {
    pub fn pick(root: &Path) -> Choice {
        if let Some(dir) = [".venv", "venv"].into_iter().find(|d| is_executable(&root.join(d).join("bin/python"))) {
            return Choice::Venv(dir);
        }
        // fs::metadata follows a link: a link to a file counts, a dangling one does not.
        let locked = |file: &str, tool: &str| is_file(&root.join(file)) && on_path(tool);
        if locked("uv.lock", "uv") {
            return Choice::Uv;
        }
        if locked("poetry.lock", "poetry") {
            return Choice::Poetry;
        }
        Choice::Path
    }

    pub fn command(&self) -> String {
        let python = match self {
            Choice::Venv(dir) => format!("{dir}/bin/python"),
            Choice::Uv => "uv run --frozen python".to_string(),
            Choice::Poetry => "poetry run python".to_string(),
            Choice::Path => "python3".to_string(),
        };
        format!("{python} {PYTEST_ARGS}")
    }

    /// The line printed right after the language line (point 2).
    pub fn line(&self) -> String {
        match self {
            Choice::Venv(dir) => {
                format!("shipcraft: Python interpreter {dir}/bin/python (the project's virtual environment); {EDIT}")
            }
            Choice::Uv => format!("shipcraft: Python through uv run --frozen (uv.lock and uv on PATH, no runnable .venv/bin/python or venv/bin/python); {EDIT}"),
            Choice::Poetry => format!("shipcraft: Python through poetry run (poetry.lock and poetry on PATH, no runnable .venv/bin/python or venv/bin/python, and no uv.lock with uv on PATH); {EDIT}"),
            Choice::Path => format!("shipcraft: Python interpreter python3 from PATH (no runnable .venv/bin/python or venv/bin/python, no uv.lock with uv on PATH, and no poetry.lock with poetry on PATH), so the hook runs whichever python3 is first on PATH at commit time; {EDIT}"),
        }
    }

    pub fn venv(&self) -> Option<&'static str> {
        match self {
            Choice::Venv(dir) => Some(dir),
            _ => None,
        }
    }
}

/// `fs::metadata` follows a link: a link to a file counts, a dangling one,
/// a folder or any error does not.
fn is_file(path: &Path) -> bool {
    std::fs::metadata(path).is_ok_and(|m| m.is_file())
}

/// Point 2's warning, when git does not ignore the venv's interpreter
/// (`git check-ignore` exits 1); any other outcome prints nothing.
pub fn unignored_warning(root: &Path, dir: &str) -> Option<String> {
    let python = format!("{dir}/bin/python");
    let mut git = Command::new("git");
    git.current_dir(root).args(["check-ignore", "-q", "--", &python]);
    git.stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null());
    let ignored = git.status().ok()?.code()?;
    (ignored == 1).then(|| warning(dir))
}

fn warning(dir: &str) -> String {
    format!("shipcraft: warning: {dir}/bin/python is not ignored by git, and the hook and ci run the suite in a copy that links only ignored files when the tree differs from what they judge: add {dir}/ to .gitignore before committing")
}

/// The command's first word, split on ASCII whitespace (point 3's reader).
pub fn first_word(command: &str) -> Option<&str> {
    command.split_ascii_whitespace().next()
}

/// `<dir>` of a `<dir>/bin/python` or `<dir>/bin/python3` word, nonempty.
pub fn venv_dir(word: &str) -> Option<&str> {
    let dir = word.strip_suffix("/bin/python").or_else(|| word.strip_suffix("/bin/python3"))?;
    (!dir.is_empty()).then_some(dir)
}

/// How messages name the suite's command in the config.
pub fn key(config: &Config, suite: &Suite) -> String {
    if config.suite.is_empty() {
        "test_command".to_string()
    } else {
        format!("command of [[suite]] {}", suite.name())
    }
}

/// Why and what to do, for a suite whose interpreter is missing (point 3).
pub struct Advice {
    pub why: String,
    pub next: String,
}

/// Point 3: when the suite wrote no report and its command's first word is an
/// interpreter the folder where it ran (`root`) does not have, or `uv` (or,
/// item 152, `poetry`) off `PATH`: the tail of the first line, and the advice. None keeps today's refusal.
pub fn missing_interpreter(command: &str, root: &Path, shown_root: &str, key: &str) -> Option<(String, Advice)> {
    let word = first_word(command)?;
    if word == "uv" || word == "poetry" {
        if on_path(word) {
            return None;
        }
        let why = format!("the suite's command runs through {word}");
        return Some((
            format!("; {word} is not on PATH"),
            Advice { why, next: format!("install {word} or edit {key} in {CONFIG_FILE}; then try again") },
        ));
    }
    let dir = venv_dir(word)?;
    if is_executable(&root.join(word)) {
        return None;
    }
    let tail = format!("; its interpreter {word} is missing or not executable at the suite's root {shown_root}");
    let why = "the suite's command names a Python interpreter that the folder where the suite ran does not have, as observed after it ran".to_string();
    let next = if Path::new(word).is_absolute() {
        format!("install that interpreter or edit {key} in {CONFIG_FILE}; then try again")
    } else {
        format!("create it at the suite's root (python3 -m venv {dir} and install the test dependencies into it, or uv sync); if it exists in the working tree, add {dir}/ to .gitignore, since the hook's copy links only ignored files; or edit {key} in {CONFIG_FILE}; then try again")
    };
    Some((tail, Advice { why, next }))
}

/// Point 3's worktree rule, right before a suite's command runs in `root`:
/// a relative venv interpreter missing here, in a linked worktree whose main
/// worktree has it, runs from there. Returns the command to run and whether
/// it was replaced. Item 152: a `poetry run python` command run outside the
/// project's folder names that folder to Poetry, never `borrowed`.
pub fn borrow(command: String, suite: &Suite, root: &Path) -> (String, bool) {
    let Some(word) = first_word(&suite.comando) else { return (command, false) };
    if word == "poetry" {
        return (poetry_project(&command, suite, root).unwrap_or(command), false);
    }
    let Some(dir) = venv_dir(word) else { return (command, false) };
    if Path::new(word).is_absolute() || is_executable(&root.join(word)) {
        return (command, false);
    }
    let Some(main) = main_worktree() else { return (command, false) };
    let theirs = main.join(&suite.raiz).join(word);
    if !is_executable(&theirs) {
        return (command, false);
    }
    let Some(replaced) = replace_first(&command, word, &shell_quote(&theirs.to_string_lossy())) else {
        return (command, false);
    };
    eprintln!(
        "shipcraft: suite {} runs {} (this worktree has no {dir}; the main worktree's)",
        suite.name(),
        theirs.display()
    );
    (replaced, true)
}

/// Item 152's point 2: the command with `poetry -P <project folder>`, when the
/// config's command is `poetry run python ...`, the run's Poetry project has no
/// in-project `.venv`, and the main folder's project is another folder.
fn poetry_project(command: &str, suite: &Suite, root: &Path) -> Option<String> {
    let words: Vec<&str> = suite.comando.split_ascii_whitespace().take(3).collect();
    if words != ["poetry", "run", "python"] {
        return None;
    }
    let here = std::fs::canonicalize(root).ok()?;
    let top =
        root.ancestors().nth(Path::new(&suite.raiz).components().count()).and_then(|t| std::fs::canonicalize(t).ok());
    if has_own_venv(&here, top.as_deref()) {
        return None;
    }
    let project = std::fs::canonicalize(main_folder()?.join(&suite.raiz)).ok()?;
    if !project.is_dir() || project == here {
        return None;
    }
    let path = project.to_str()?;
    let replaced = replace_first(command, "poetry", &format!("poetry -P {}", shell_quote(path)))?;
    eprintln!(
        "shipcraft: suite {} runs poetry -P {path} (Poetry keys its environment to the project folder, and this run is in another folder)",
        suite.name()
    );
    Some(replaced)
}

/// Whether the first folder holding a `pyproject.toml`, from the canonical
/// run folder `here` up to the canonical top of the tree it runs in (`root`
/// less the suite's `raiz`, a normalized relative path; included), holds a
/// `.venv` folder. A `here` outside `top` (a suite root linked elsewhere), or
/// no `top`, walks up to the filesystem root. No such folder: false.
fn has_own_venv(here: &Path, top: Option<&Path>) -> bool {
    let top = top.filter(|t| here.starts_with(t));
    let mut reached = false;
    here.ancestors()
        .take_while(|folder| !std::mem::replace(&mut reached, Some(*folder) == top))
        .find(|folder| is_file(&folder.join("pyproject.toml")))
        .is_some_and(|folder| std::fs::metadata(folder.join(".venv")).is_ok_and(|m| m.is_dir()))
}

/// `command` with its first word, when it is `word`, replaced by `with`.
fn replace_first(command: &str, word: &str, with: &str) -> Option<String> {
    let rest = command.trim_start_matches(|c: char| c.is_ascii_whitespace());
    let lead = &command[..command.len() - rest.len()];
    let after = rest.strip_prefix(word)?;
    if !after.is_empty() && !after.starts_with(|c: char| c.is_ascii_whitespace()) {
        return None;
    }
    Some(format!("{lead}{with}{after}"))
}

/// The main worktree, when this process's repository is a linked worktree:
/// the common dir differs from the git dir and is a folder named `.git`. Git
/// reads the caller's environment, so in a hook (`GIT_DIR` set) it is the
/// hook's repository, also when the suite runs in a checkout copy.
fn main_worktree() -> Option<PathBuf> {
    let (common, git_dir) = git_dirs()?;
    main_of(&common, git_dir.as_deref()?)
}

/// Item 152: the main folder, the parent of a common dir named `.git`, from
/// the main worktree or a linked one (a bare repository reads nothing).
fn main_folder() -> Option<PathBuf> {
    let (common, _) = git_dirs()?;
    let common = Path::new(&common);
    (common.file_name()? == ".git").then(|| common.parent().map(Path::to_path_buf))?
}

/// `git rev-parse --path-format=absolute --git-common-dir --git-dir` in this
/// process's working directory: the common dir (the answer trimmed, its first
/// line) and the git dir. A failed spawn, a nonzero exit or an empty answer
/// reads nothing; so does a bare repository (review round 1), whose linked
/// worktrees have no main worktree to borrow from or name to Poetry.
fn git_dirs() -> Option<(String, Option<String>)> {
    git_dirs_in(Path::new("."))
}

fn git_dirs_in(cwd: &Path) -> Option<(String, Option<String>)> {
    let out = Command::new("git")
        .current_dir(cwd)
        .args(["rev-parse", "--path-format=absolute", "--git-common-dir", "--git-dir"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let said = text(&out.stdout);
    let mut lines = said.trim().lines();
    let common = lines.next().filter(|l| !l.is_empty())?.to_string();
    let git_dir = lines.next().map(str::to_string);
    (!is_bare(cwd, &common)).then_some((common, git_dir))
}

/// `git --git-dir=<common dir> config --bool --get core.bare` prints `true`;
/// a failure, a nonzero exit or any other answer is git's default, not bare.
/// Read through the common dir (review round 2): with
/// `extensions.worktreeConfig`, git keeps `core.bare` in the main
/// worktree's `config.worktree`, which a linked worktree's own config does
/// not show.
fn is_bare(cwd: &Path, common: &str) -> bool {
    let out = Command::new("git")
        .current_dir(cwd)
        .arg(format!("--git-dir={common}"))
        .args(["config", "--bool", "--get", "core.bare"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output();
    out.is_ok_and(|o| o.status.success() && text(&o.stdout).trim() == "true")
}

fn main_of(common: &str, git_dir: &str) -> Option<PathBuf> {
    let common = Path::new(common);
    if common == Path::new(git_dir) || common.file_name()? != ".git" {
        return None;
    }
    common.parent().map(Path::to_path_buf)
}

/// Point 4: `status`'s lines for suites that run a bare `python3` or
/// `python` beside the project's venv, in config order.
pub fn status_lines(repo: &Repo, config: &Config) -> Vec<String> {
    let mut lines = Vec::new();
    for suite in config.suites() {
        let Some(word) = first_word(&suite.comando).filter(|w| *w == "python3" || *w == "python") else { continue };
        let root = repo.path(&suite.raiz);
        let Some(dir) = [".venv", "venv"].into_iter().find(|d| is_executable(&root.join(d).join("bin/python"))) else {
            continue;
        };
        lines.push(status_line(suite.name(), word, suite.shown_root(), dir, &key(config, &suite)));
    }
    lines
}

fn status_line(name: &str, word: &str, root: &str, dir: &str, key: &str) -> String {
    format!("shipcraft: suite {name} runs {word} from PATH, but {root}/{dir}/bin/python is the project's virtual environment; to use it, start {key} with {dir}/bin/python in {CONFIG_FILE}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("shipcraft-pyenv-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn python(root: &Path, dir: &str, mode: u32) {
        fs::create_dir_all(root.join(dir).join("bin")).unwrap();
        let path = root.join(dir).join("bin/python");
        fs::write(&path, "#!/bin/sh\n").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(mode)).unwrap();
    }

    #[test]
    fn first_word_splits_on_ascii_whitespace() {
        assert_eq!(first_word("  .venv/bin/python -m pytest"), Some(".venv/bin/python"));
        assert_eq!(first_word("\tuv\trun"), Some("uv"));
        assert_eq!(first_word(""), None);
        assert_eq!(first_word("   "), None);
    }

    #[test]
    fn venv_dir_needs_a_nonempty_prefix() {
        assert_eq!(venv_dir(".venv/bin/python"), Some(".venv"));
        assert_eq!(venv_dir("venv/bin/python3"), Some("venv"));
        assert_eq!(venv_dir("/opt/py/bin/python3"), Some("/opt/py"));
        assert_eq!(venv_dir("bin/python"), None);
        assert_eq!(venv_dir("/bin/python3"), None);
        assert_eq!(venv_dir("python3"), None);
        assert_eq!(venv_dir(".venv/bin/pytest"), None);
    }

    #[test]
    fn choice_takes_venv_then_venv_folder_then_path() {
        let root = scratch("choice");
        assert_eq!(Choice::pick(&root), Choice::Path);
        python(&root, ".venv", 0o644);
        assert_eq!(Choice::pick(&root), Choice::Path, "a non-executable .venv python is passed over");
        python(&root, "venv", 0o755);
        assert_eq!(Choice::pick(&root), Choice::Venv("venv"));
        python(&root, ".venv", 0o755);
        assert_eq!(Choice::pick(&root), Choice::Venv(".venv"));
        fs::write(root.join("uv.lock"), "").unwrap();
        assert_eq!(Choice::pick(&root), Choice::Venv(".venv"), "a venv beside uv.lock wins");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn commands_keep_python_dash_m_pytest() {
        assert_eq!(
            Choice::Venv(".venv").command(),
            ".venv/bin/python -m pytest -p no:cacheprovider --junitxml={junit}"
        );
        assert_eq!(Choice::Uv.command(), "uv run --frozen python -m pytest -p no:cacheprovider --junitxml={junit}");
        assert_eq!(Choice::Path.command(), "python3 -m pytest -p no:cacheprovider --junitxml={junit}");
    }

    #[test]
    fn lines_name_the_choice() {
        assert_eq!(Choice::Venv("venv").line(), "shipcraft: Python interpreter venv/bin/python (the project's virtual environment); to use another, edit test_command in .shipcraft.toml");
        assert!(Choice::Uv.line().starts_with("shipcraft: Python through uv run --frozen (uv.lock and uv on PATH"));
        assert!(Choice::Path.line().contains("so the hook runs whichever python3 is first on PATH at commit time"));
        assert_eq!(warning(".venv"), "shipcraft: warning: .venv/bin/python is not ignored by git, and the hook and ci run the suite in a copy that links only ignored files when the tree differs from what they judge: add .venv/ to .gitignore before committing");
    }

    #[test]
    fn missing_interpreter_reads_relative_and_absolute_words() {
        let root = scratch("missing");
        let (tail, advice) = missing_interpreter(".venv/bin/python -m pytest", &root, ".", "test_command").unwrap();
        assert_eq!(tail, "; its interpreter .venv/bin/python is missing or not executable at the suite's root .");
        assert!(advice.next.starts_with("create it at the suite's root (python3 -m venv .venv and"));
        assert!(advice.next.ends_with("or edit test_command in .shipcraft.toml; then try again"));
        let (_, advice) = missing_interpreter("/nowhere/x/bin/python3 -m pytest", &root, ".", "k").unwrap();
        assert_eq!(advice.next, "install that interpreter or edit k in .shipcraft.toml; then try again");
        assert!(missing_interpreter("python3 -m pytest", &root, ".", "k").is_none());
        assert!(missing_interpreter("bin/python -m pytest", &root, ".", "k").is_none());
        assert!(missing_interpreter("", &root, ".", "k").is_none());
        python(&root, ".venv", 0o755);
        assert!(missing_interpreter(".venv/bin/python -m pytest", &root, ".", "k").is_none());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn replace_first_swaps_only_the_whole_first_word() {
        assert_eq!(
            replace_first(" .venv/bin/python -m x", ".venv/bin/python", "'/m/.venv/bin/python'").unwrap(),
            " '/m/.venv/bin/python' -m x"
        );
        assert_eq!(replace_first(".venv/bin/python", ".venv/bin/python", "'/a'").unwrap(), "'/a'");
        assert!(replace_first(".venv/bin/python3 -m x", ".venv/bin/python", "'/a'").is_none());
        assert!(replace_first("python3 -m x", ".venv/bin/python", "'/a'").is_none());
    }

    #[test]
    fn main_worktree_is_the_parent_of_a_dot_git_common_dir() {
        assert_eq!(main_of("/r/.git", "/r/.git/worktrees/w"), Some(PathBuf::from("/r")));
        assert_eq!(main_of("/r/.git", "/r/.git"), None);
        assert_eq!(main_of("/r/repo.git", "/r/repo.git/worktrees/w"), None);
    }

    fn suite(raiz: &str, comando: &str) -> Suite {
        Suite {
            nome: String::new(),
            raiz: raiz.to_string(),
            comando: comando.to_string(),
            verifica: None,
            globs: Vec::new(),
            filtra: crate::config::Filtra::Shipcraft,
        }
    }

    #[test]
    fn poetry_command_and_lines() {
        assert_eq!(Choice::Poetry.command(), "poetry run python -m pytest -p no:cacheprovider --junitxml={junit}");
        assert_eq!(Choice::Poetry.line(), "shipcraft: Python through poetry run (poetry.lock and poetry on PATH, no runnable .venv/bin/python or venv/bin/python, and no uv.lock with uv on PATH); to use another, edit test_command in .shipcraft.toml");
        assert_eq!(Choice::Path.line(), "shipcraft: Python interpreter python3 from PATH (no runnable .venv/bin/python or venv/bin/python, no uv.lock with uv on PATH, and no poetry.lock with poetry on PATH), so the hook runs whichever python3 is first on PATH at commit time; to use another, edit test_command in .shipcraft.toml");
        assert_eq!(Choice::Poetry.venv(), None);
    }

    #[test]
    fn poetry_lock_alone_is_not_poetry_without_the_tool() {
        let root = scratch("poetry-pick");
        fs::write(root.join("poetry.lock"), "").unwrap();
        if !on_path("poetry") {
            assert_eq!(Choice::pick(&root), Choice::Path);
        }
        python(&root, ".venv", 0o755);
        assert_eq!(Choice::pick(&root), Choice::Venv(".venv"), "a venv beside poetry.lock wins");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn missing_poetry_says_so() {
        let root = scratch("missing-poetry");
        if !on_path("poetry") {
            let (tail, advice) =
                missing_interpreter("poetry run python -m pytest", &root, ".", "test_command").unwrap();
            assert_eq!(tail, "; poetry is not on PATH");
            assert_eq!(advice.why, "the suite's command runs through poetry");
            assert_eq!(advice.next, "install poetry or edit test_command in .shipcraft.toml; then try again");
        }
        assert!(missing_interpreter("poetryx run python", &root, ".", "k").is_none());
        let _ = fs::remove_dir_all(&root);
    }

    fn walk(root: &Path, raiz: &str) -> bool {
        let here = fs::canonicalize(root).unwrap();
        let top = root.ancestors().nth(Path::new(raiz).components().count()).and_then(|t| fs::canonicalize(t).ok());
        has_own_venv(&here, top.as_deref())
    }

    #[test]
    fn own_venv_is_the_first_pyproject_folders_up_to_the_top() {
        let top = scratch("own-venv");
        let root = top.join("services/api");
        fs::create_dir_all(&root).unwrap();
        assert!(!walk(&root, "services/api"), "no pyproject.toml anywhere");
        fs::write(top.join("pyproject.toml"), "").unwrap();
        assert!(!walk(&root, "services/api"), "the root project has no .venv");
        fs::write(top.join(".venv"), "").unwrap();
        assert!(!walk(&root, "services/api"), "a .venv file is not an environment");
        fs::remove_file(top.join(".venv")).unwrap();
        fs::create_dir(top.join(".venv")).unwrap();
        assert!(walk(&root, "services/api"));
        assert!(!walk(&root, "api"), "the walk stops at the top of the tree");
        fs::write(root.join("pyproject.toml"), "").unwrap();
        assert!(!walk(&root, "services/api"), "the nearest project is the run's");
        assert!(walk(&top.join(""), ""));
        let _ = fs::remove_dir_all(&top);
    }

    #[test]
    fn own_venv_follows_a_linked_suite_root() {
        let top = scratch("own-venv-link");
        let demo = top.join("packages/demo");
        fs::create_dir_all(demo.join("specs")).unwrap();
        fs::create_dir_all(demo.join(".venv")).unwrap();
        fs::write(demo.join("pyproject.toml"), "").unwrap();
        std::os::unix::fs::symlink("packages/demo/specs", top.join("suite")).unwrap();
        assert!(walk(&top.join("suite"), "suite"), "the physical folder's project has its .venv");
        let outside = scratch("own-venv-outside");
        fs::create_dir_all(outside.join("p/.venv")).unwrap();
        fs::write(outside.join("p/pyproject.toml"), "").unwrap();
        std::os::unix::fs::symlink(outside.join("p"), top.join("away")).unwrap();
        assert!(walk(&top.join("away"), "away"), "outside the top, the walk goes up past it");
        let _ = fs::remove_dir_all(&top);
        let _ = fs::remove_dir_all(&outside);
    }

    fn git(cwd: &Path, args: &[&str]) {
        let ok = Command::new("git").current_dir(cwd).args(args).stdout(Stdio::null()).stderr(Stdio::null()).status();
        assert!(ok.unwrap().success(), "git {args:?}");
    }

    #[test]
    fn a_bare_repository_reads_nothing() {
        if std::env::var_os("GIT_DIR").is_some() {
            return; // inside a git hook, git reads the hook's repository
        }
        let top = scratch("bare");
        git(&top, &["init", "-q", "-b", "main"]);
        git(
            &top,
            &[
                "-c",
                "user.name=t",
                "-c",
                "user.email=t@t",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "-q",
                "--allow-empty",
                "-m",
                "x",
            ],
        );
        git(&top, &["worktree", "add", "-q", "linked-plain", "-b", "plain"]);
        let (common, git_dir) = git_dirs_in(&top.join("linked-plain")).unwrap();
        assert_eq!(main_of(&common, &git_dir.unwrap()), Some(fs::canonicalize(&top).unwrap()));
        git(&top, &["clone", "-q", "--bare", ".", "storage/.git"]);
        git(&top, &["--git-dir=storage/.git", "worktree", "add", "-q", "linked", "main"]);
        assert!(git_dirs_in(&top.join("linked")).is_none(), "a linked worktree of a bare .git clone");
        assert!(git_dirs_in(&top.join("storage/.git")).is_none());
        assert!(git_dirs_in(&top).is_some());
        // Review round 2: core.bare moved to the bare clone's config.worktree
        // (extensions.worktreeConfig), as git's docs tell users to do.
        git(&top, &["clone", "-q", "--bare", ".", "wtconfig/.git"]);
        git(&top, &["--git-dir=wtconfig/.git", "config", "extensions.worktreeConfig", "true"]);
        git(&top, &["--git-dir=wtconfig/.git", "config", "--worktree", "core.bare", "true"]);
        git(&top, &["--git-dir=wtconfig/.git", "config", "--unset", "core.bare"]);
        git(&top, &["--git-dir=wtconfig/.git", "worktree", "add", "-q", "linked-wt", "main"]);
        assert!(git_dirs_in(&top.join("linked-wt")).is_none(), "core.bare in the bare clone's config.worktree");
        let _ = fs::remove_dir_all(&top);
    }

    #[test]
    fn poetry_rewrite_needs_poetry_run_python() {
        let root = scratch("poetry-forms");
        for form in ["poetry run pytest", "poetry -P . run python", "poetry --project . run python", "poetry run"] {
            let command = format!("{form} -x");
            assert_eq!(borrow(command.clone(), &suite("", &command), &root), (command, false));
        }
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn poetry_word_becomes_poetry_dash_p() {
        assert_eq!(
            replace_first("poetry run python -m pytest", "poetry", "poetry -P '/a b'").unwrap(),
            "poetry -P '/a b' run python -m pytest"
        );
        assert_eq!(shell_quote("/x/it's"), "'/x/it'\"'\"'s'");
    }

    #[test]
    fn status_line_names_the_root_and_key() {
        assert_eq!(
            status_line("pkg", "python", "pkg", "venv", "command of [[suite]] pkg"),
            "shipcraft: suite pkg runs python from PATH, but pkg/venv/bin/python is the project's virtual environment; to use it, start command of [[suite]] pkg with venv/bin/python in .shipcraft.toml"
        );
    }
}
