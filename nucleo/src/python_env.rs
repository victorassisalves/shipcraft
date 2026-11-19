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
    Path,
}

impl Choice {
    pub fn pick(root: &Path) -> Choice {
        if let Some(dir) = [".venv", "venv"].into_iter().find(|d| is_executable(&root.join(d).join("bin/python"))) {
            return Choice::Venv(dir);
        }
        // fs::metadata follows a link: a link to a file counts, a dangling one does not.
        if std::fs::metadata(root.join("uv.lock")).is_ok_and(|m| m.is_file()) && on_path("uv") {
            return Choice::Uv;
        }
        Choice::Path
    }

    pub fn command(&self) -> String {
        let python = match self {
            Choice::Venv(dir) => format!("{dir}/bin/python"),
            Choice::Uv => "uv run --frozen python".to_string(),
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
            Choice::Path => format!("shipcraft: Python interpreter python3 from PATH (no runnable .venv/bin/python or venv/bin/python, and no uv.lock with uv on PATH), so the hook runs whichever python3 is first on PATH at commit time; {EDIT}"),
        }
    }

    pub fn venv(&self) -> Option<&'static str> {
        match self {
            Choice::Venv(dir) => Some(dir),
            _ => None,
        }
    }
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
/// interpreter the folder where it ran (`root`) does not have, or `uv` off
/// `PATH`: the tail of the first line, and the advice. None keeps today's refusal.
pub fn missing_interpreter(command: &str, root: &Path, shown_root: &str, key: &str) -> Option<(String, Advice)> {
    let word = first_word(command)?;
    if word == "uv" {
        if on_path("uv") {
            return None;
        }
        let why = "the suite's command runs through uv".to_string();
        return Some((
            "; uv is not on PATH".to_string(),
            Advice { why, next: format!("install uv or edit {key} in {CONFIG_FILE}; then try again") },
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
/// it was replaced.
pub fn borrow(command: String, suite: &Suite, root: &Path) -> (String, bool) {
    let Some(word) = first_word(&suite.comando) else { return (command, false) };
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
    let out = Command::new("git")
        .args(["rev-parse", "--path-format=absolute", "--git-common-dir", "--git-dir"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let said = text(&out.stdout);
    let mut lines = said.lines();
    main_of(lines.next()?, lines.next()?)
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

    #[test]
    fn status_line_names_the_root_and_key() {
        assert_eq!(
            status_line("pkg", "python", "pkg", "venv", "command of [[suite]] pkg"),
            "shipcraft: suite pkg runs python from PATH, but pkg/venv/bin/python is the project's virtual environment; to use it, start command of [[suite]] pkg with venv/bin/python in .shipcraft.toml"
        );
    }
}
