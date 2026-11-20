//! Item 138: pytest's own settings. The hook and CI refuse a change to the
//! settings pytest reads (`pytest.ini`, `.pytest.ini`, `pytest.toml`,
//! `.pytest.toml`, `pyproject.toml`'s `tool.pytest`, `setup.cfg`'s
//! `[tool:pytest]`, `tox.ini`'s `[pytest]`) while a lock is open
//! (`pytest-config-changed`). Nothing is locked: each judged path is compared
//! with every parent's.

use crate::config::{Config, Suite};
use crate::git::{Repo, Snapshot};
use crate::red::one_line;
use crate::refusal::{refuse, Result};
use crate::vitest_files::snapshot_paths;
use std::collections::BTreeSet;

/// Point 1's pytest config names.
const NAMES: [&str; 7] =
    ["pytest.ini", ".pytest.ini", "pytest.toml", ".pytest.toml", "pyproject.toml", "setup.cfg", "tox.ini"];
/// The names pytest uses whole, even with no section in them.
const WHOLE: [&str; 4] = ["pytest.ini", ".pytest.ini", "pytest.toml", ".pytest.toml"];

/// The pytest settings of a path in a snapshot.
#[derive(Debug)]
enum Settings {
    None,
    Bytes(Vec<u8>),
    Value(toml::Value),
    /// A symbolic link: equals nothing.
    Linked,
}

impl Settings {
    fn same(&self, other: &Settings) -> bool {
        match (self, other) {
            (Settings::None, Settings::None) => true,
            (Settings::Bytes(a), Settings::Bytes(b)) => a == b,
            (Settings::Value(a), Settings::Value(b)) => a == b,
            _ => false,
        }
    }
}

fn file_name(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

fn folder(path: &str) -> &str {
    path.rsplit_once('/').map_or("", |(dir, _)| dir)
}

/// The suites whose command contains `pytest`.
fn pytest_suites(config: &Config) -> Vec<Suite> {
    config.suites().into_iter().filter(|suite| suite.comando.contains("pytest")).collect()
}

/// Whether `suite` watches `path`: under its root at any depth, or directly in
/// a folder from the repository root down to the root's parent.
fn watches(suite: &Suite, path: &str) -> bool {
    if !NAMES.contains(&file_name(path)) {
        return false;
    }
    if path.starts_with(&suite.prefix()) {
        return true;
    }
    let dir = folder(path);
    dir.is_empty() || suite.raiz.starts_with(&format!("{dir}/"))
}

/// The paths judged: the watched paths of every suite among `paths`, once, in bytewise order.
fn watched<'a>(suites: &[Suite], paths: impl IntoIterator<Item = &'a String>) -> BTreeSet<String> {
    paths.into_iter().filter(|path| suites.iter().any(|suite| watches(suite, path))).cloned().collect()
}

/// Python's `str.splitlines(keepends=True)`: each line with its own separator.
fn split_lines(text: &str) -> Vec<(&str, &str)> {
    const BREAKS: [char; 10] =
        ['\n', '\r', '\u{0b}', '\u{0c}', '\u{1c}', '\u{1d}', '\u{1e}', '\u{85}', '\u{2028}', '\u{2029}'];
    let mut lines = Vec::new();
    let mut rest = text;
    while !rest.is_empty() {
        let Some(at) = rest.find(BREAKS) else {
            lines.push((rest, ""));
            break;
        };
        let width =
            if rest[at..].starts_with("\r\n") { 2 } else { rest[at..].chars().next().map_or(1, char::len_utf8) };
        lines.push((&rest[..at], &rest[at..at + width]));
        rest = &rest[at + width..];
    }
    lines
}

/// A header's name: a line that starts with `[` and, cut before its first `#`
/// or `;` and trimmed at the end, ends with `]`.
fn header(line: &str) -> Option<&str> {
    if !line.starts_with('[') {
        return None;
    }
    let cut = line.find(['#', ';']).map_or(line, |at| &line[..at]).trim_end();
    (cut.len() >= 2 && cut.ends_with(']')).then(|| &cut[1..cut.len() - 1])
}

/// The section named `name`, read as `iniconfig` reads it: every matching
/// header through the line before the next header, concatenated in file
/// order with separators kept; None when no header matches.
fn ini_section(text: &str, name: &str) -> Option<String> {
    let mut found: Option<String> = None;
    let mut inside = false;
    for (line, separator) in split_lines(text) {
        if let Some(named) = header(line) {
            inside = named == name;
            if inside {
                found.get_or_insert_with(String::new);
            }
        }
        if inside {
            let section = found.as_mut().expect("a matching header started it");
            section.push_str(line);
            section.push_str(separator);
        }
    }
    found
}

/// `pyproject.toml`'s `tool.pytest` value; its bytes when it does not parse.
fn pyproject(bytes: Vec<u8>) -> Settings {
    let parsed = std::str::from_utf8(&bytes).ok().and_then(|text| text.parse::<toml::Table>().ok());
    let Some(table) = parsed else { return Settings::Bytes(bytes) };
    match table.get("tool").and_then(toml::Value::as_table).and_then(|tool| tool.get("pytest")) {
        Some(value) => Settings::Value(value.clone()),
        None => Settings::None,
    }
}

/// The settings of a file named `name` holding `bytes`.
fn of_bytes(name: &str, bytes: Vec<u8>) -> Settings {
    let section = match name {
        "pyproject.toml" => return pyproject(bytes),
        "setup.cfg" => "tool:pytest",
        "tox.ini" => "pytest",
        _ => return Settings::Bytes(bytes),
    };
    let Ok(text) = std::str::from_utf8(&bytes) else { return Settings::Bytes(bytes) };
    ini_section(text, section).map_or(Settings::None, |found| Settings::Bytes(found.into_bytes()))
}

/// Point 1: the pytest settings of `path` in `snapshot`.
fn settings(repo: &Repo, snapshot: &Snapshot, path: &str) -> Result<Settings> {
    match repo.mode(snapshot, path)?.as_deref() {
        None => return Ok(Settings::None),
        Some("120000") => return Ok(Settings::Linked),
        Some(_) => {}
    }
    Ok(match repo.read(snapshot, path)? {
        None => Settings::None,
        Some(bytes) if WHOLE.contains(&file_name(path)) => Settings::Bytes(bytes),
        Some(bytes) => of_bytes(file_name(path), bytes),
    })
}

/// Point 2, right after `vitest_files::check_added`: the first judged path
/// whose settings in `snapshot` equal those of no parent.
pub fn check_changed(repo: &Repo, parents: &[Snapshot], snapshot: &Snapshot, lock_path: &str) -> Result<()> {
    let Some(config) = Config::at(repo, snapshot)? else { return Ok(()) };
    let suites = pytest_suites(&config);
    if suites.is_empty() {
        return Ok(());
    }
    let mut paths = snapshot_paths(repo, snapshot)?;
    for parent in parents {
        paths.extend(snapshot_paths(repo, parent)?);
    }
    for path in watched(&suites, &paths) {
        let now = settings(repo, snapshot, &path)?;
        let before = parents.iter().map(|parent| settings(repo, parent, &path)).collect::<Result<Vec<_>>>()?;
        if before.iter().any(|old| now.same(old)) {
            continue;
        }
        let done = match &now {
            Settings::Linked => "are behind a symbolic link",
            _ if before.iter().all(|old| matches!(old, Settings::None)) => "were added",
            Settings::None => "were removed",
            _ => "changed",
        };
        let shown = one_line(&path);
        return refuse(
            "pytest-config-changed",
            format!("pytest's settings in {shown} {done} {} with lock {} open", snapshot.describe(), one_line(lock_path)),
            "pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",
            format!("undo the change to pytest's settings in {shown}; if the suite needs it, make it after the cycle closes"),
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn suite(raiz: &str, comando: &str) -> Suite {
        let text = format!("[[suite]]\nroot = \"{raiz}\"\ncommand = \"{comando}\"\nglobs = [\"tests/**/*.py\"]\n");
        Config::parse(&text).unwrap().suites().remove(0)
    }

    fn same(name: &str, a: &str, b: &str) -> bool {
        of_bytes(name, a.as_bytes().to_vec()).same(&of_bytes(name, b.as_bytes().to_vec()))
    }

    fn section(text: &str, name: &str) -> Option<String> {
        ini_section(text, name)
    }

    #[test]
    fn the_watched_paths() {
        let all: Vec<String> = [
            "pytest.ini",
            "svc/api/deep/tox.ini",
            "svc/setup.cfg",
            "svc/api/pyproject.toml",
            "svc/other/pytest.ini",
            "svc/api/conftest.py",
            "svc/apix/pytest.ini",
            "svc/api/Pytest.ini",
        ]
        .iter()
        .map(|p| p.to_string())
        .collect();
        let got: Vec<String> = watched(&[suite("svc/api", "python -m pytest")], &all).into_iter().collect();
        assert_eq!(got, ["pytest.ini", "svc/api/deep/tox.ini", "svc/api/pyproject.toml", "svc/setup.cfg"]);
        let root: Vec<String> = watched(&[suite(".", "pytest -q")], &all).into_iter().collect();
        assert_eq!(root.len(), 6, "every config name under a root suite: {root:?}");
        let other = Config::parse("[[suite]]\ncommand = \"tox -e py\"\nglobs = [\"t/*.py\"]\n").unwrap();
        assert!(pytest_suites(&other).is_empty(), "a command without pytest");
    }

    #[test]
    fn pyproject_compares_the_tool_pytest_value() {
        let a = "[project]\nname = \"a\"\n[tool.pytest.ini_options]\naddopts = \"-q\"\ntestpaths = ['tests']\n";
        let spaced =
            "[project]\nname = \"b\"\n\n[tool.pytest.ini_options]\ntestpaths = [ \"tests\" ]  # c\naddopts='-q'\n";
        assert!(same("pyproject.toml", a, spaced), "spacing, quotes, key order and [project] do not count");
        let more = format!("{a}pythonpath = [\"shadow\"]\n");
        assert!(!same("pyproject.toml", a, &more));
        assert!(same("pyproject.toml", "[project]\nname = \"a\"\n", "[tool.black]\nx = 1\n"), "both none");
        assert!(matches!(of_bytes("pyproject.toml", b"tool = 1\n".to_vec()), Settings::None));
        assert!(!same("pyproject.toml", "[tool]\npytest = 1\n", "[tool]\npytest = 2\n"), "a scalar is a value");
        assert!(!same("pyproject.toml", "[tool.pytest]\nx = nan\n", "[tool.pytest]\nx = nan\n"), "nan != nan");
        // One that stops parsing has changed; one that does not parse falls back to bytes.
        assert!(!same("pyproject.toml", a, "[tool.pytest.ini_options\n"));
        assert!(same("pyproject.toml", "[broken\n", "[broken\n"));
        assert!(matches!(of_bytes("pyproject.toml", vec![b'[', 0xff, b']']), Settings::Bytes(_)));
        assert!(!Settings::Linked.same(&Settings::Linked));
        assert!(!Settings::Bytes(Vec::new()).same(&Settings::None));
    }

    #[test]
    fn lines_split_as_python_splits_them() {
        let text = "a\r\nb\rc\u{0c}d\u{2028}e\u{1c}f\u{85}g\n\nh";
        let got: Vec<(&str, &str)> = split_lines(text);
        let want = [
            ("a", "\r\n"),
            ("b", "\r"),
            ("c", "\u{0c}"),
            ("d", "\u{2028}"),
            ("e", "\u{1c}"),
            ("f", "\u{85}"),
            ("g", "\n"),
            ("", "\n"),
            ("h", ""),
        ];
        assert_eq!(got, want);
        assert!(split_lines("").is_empty());
    }

    #[test]
    fn headers() {
        assert_eq!(header("[tool:pytest]  # comment"), Some("tool:pytest"));
        assert_eq!(header("[pytest] ; c ]"), Some("pytest"));
        assert_eq!(header("[pytest]\t "), Some("pytest"));
        assert_eq!(header("[unused"), None);
        assert_eq!(header("  [pytest]"), None);
        assert_eq!(header("["), None);
        assert_eq!(header("[]"), Some(""));
        assert_eq!(header("[a#]"), None);
    }

    #[test]
    fn the_ini_section() {
        let cfg = "[metadata]\nname = x\n[tool:pytest]  # here\naddopts = -q\n[unused\n  [flake8]\n[flake8]\nx = 1\n";
        assert_eq!(section(cfg, "tool:pytest").unwrap(), "[tool:pytest]  # here\naddopts = -q\n[unused\n  [flake8]\n");
        assert_eq!(section(cfg, "pytest"), None);
        assert_eq!(section("[pytest]", "pytest").unwrap(), "[pytest]", "an empty section is not none");
        let split = "[pytest]\na = 1\n[tox]\nx\n[pytest]\nb = 2\n";
        assert_eq!(section(split, "pytest").unwrap(), "[pytest]\na = 1\n[pytest]\nb = 2\n");
        let crlf = "[metadata]\r\nn = 1\r\n[tool:pytest] ; c\r\naddopts = -q\r\n";
        assert_eq!(section(crlf, "tool:pytest").unwrap(), "[tool:pytest] ; c\r\naddopts = -q\r\n");
        let cr = "[metadata]\rn = 1\r[tool:pytest]\raddopts = -q\r";
        assert_eq!(section(cr, "tool:pytest").unwrap(), "[tool:pytest]\raddopts = -q\r");
        let sep = "[tox]\u{2028}[pytest]\u{0c}a = 1\u{2028}[x]\u{1c}";
        assert_eq!(section(sep, "pytest").unwrap(), "[pytest]\u{0c}a = 1\u{2028}");
    }

    #[test]
    fn ini_settings() {
        let a = "[metadata]\nversion = 1\n[tool:pytest]\naddopts = -q\n";
        let b = "[metadata]\nversion = 2\n[tool:pytest]\naddopts = -q\n";
        assert!(same("setup.cfg", a, b), "another section's change does not count");
        assert!(!same("setup.cfg", a, "[metadata]\nversion = 1\n[tool:pytest]\naddopts = -q # x\n"));
        assert!(same("setup.cfg", "[metadata]\n", "[pytest]\naddopts = -p x\n"), "[pytest] is not setup.cfg's");
        assert!(!same("tox.ini", "[tox]\n", "[tox]\n[pytest]\n"), "an added empty section");
        let split = |second: &str| format!("[pytest]\na = 1\n[tox]\n[pytest]\n{second}\n");
        assert!(!same("tox.ini", &split("b = 1"), &split("b = 2")), "the second of two sections");
        assert!(!same("setup.cfg", "[tool:pytest]\n[unused\n", "[tool:pytest]\n[unused2\n"), "a continuation line");
        assert!(!same("setup.cfg", "[tool:pytest]\n  [x]\n", "[tool:pytest]\n  [y]\n"), "a leading-space line");
        // Not UTF-8: the whole bytes.
        let bad = |extra: u8| of_bytes("setup.cfg", vec![b'[', b'a', b']', b'\n', 0xff, extra]);
        assert!(matches!(bad(1), Settings::Bytes(ref b) if b.len() == 6));
        assert!(!bad(1).same(&bad(2)), "a change outside any section counts when it is not UTF-8");
        assert!(same("pytest.ini", "[pytest]\n", "[pytest]\n"));
        assert!(!same("pytest.ini", "", "\n"), "a whole file compares its bytes");
    }
}
