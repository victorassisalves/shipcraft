//! Item 132: the files vitest reads beside the tests. `red` locks the runner
//! configs of every vitest suite, the modules they import by relative path
//! and the setup files they name; it refuses a config it cannot read
//! (`setup-unreadable`), and the hook and CI refuse a runner config added
//! while a lock is open (`runner-config-added`).

mod scan;

use crate::config::{Config, Suite, CONFIG_FILE};
use crate::git::{Repo, Snapshot};
use crate::lock::Lock;
use crate::red::one_line;
use crate::refusal::{failed, refuse, short_list, Result};
use scan::Event;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;

/// The extensions of a runner config name.
const CONFIG_EXTS: [&str; 6] = ["ts", "mts", "cts", "js", "mjs", "cjs"];
/// The extensions a reached module is scanned with, and a setup literal's candidates.
const JS_EXTS: [&str; 8] = ["ts", "tsx", "mts", "cts", "js", "jsx", "mjs", "cjs"];

#[derive(Clone, Copy, PartialEq)]
enum Name {
    VitestConfig,
    Workspace,
    Vite,
}

/// A path's runner config name, when its last component is one.
fn runner_name(path: &str) -> Option<Name> {
    let (stem, ext) = path.rsplit('/').next()?.rsplit_once('.')?;
    if !CONFIG_EXTS.contains(&ext) {
        return None;
    }
    match stem {
        "vitest.config" => Some(Name::VitestConfig),
        "vitest.workspace" => Some(Name::Workspace),
        "vite.config" => Some(Name::Vite),
        _ => None,
    }
}

fn folder(path: &str) -> &str {
    path.rsplit_once('/').map_or("", |(dir, _)| dir)
}

/// The suites whose command contains `vitest`.
fn vitest_suites(config: &Config) -> Vec<Suite> {
    config.suites().into_iter().filter(|suite| suite.comando.contains("vitest")).collect()
}

/// Point 1: the locked runner configs of `suites` among `paths`: every
/// `vitest.config.*` and `vitest.workspace.*` under a suite's root, and a
/// `vite.config.*` directly in the root folder with no `vitest.config.*` there.
fn runner_configs(suites: &[Suite], paths: &[String]) -> BTreeSet<String> {
    let candidates: Vec<(&String, Name)> = paths
        .iter()
        .filter(|path| !path.split('/').any(|part| part == "node_modules"))
        .filter_map(|path| runner_name(path).map(|name| (path, name)))
        .collect();
    let mut found = BTreeSet::new();
    for suite in suites {
        let prefix = suite.prefix();
        let in_root = |path: &str| folder(path) == suite.raiz;
        let vitest_in_root = candidates.iter().any(|(path, name)| *name == Name::VitestConfig && in_root(path));
        for (path, name) in &candidates {
            let locked = match name {
                Name::VitestConfig | Name::Workspace => path.starts_with(&prefix),
                Name::Vite => in_root(path) && !vitest_in_root,
            };
            if locked {
                found.insert(path.to_string());
            }
        }
    }
    found
}

/// A literal's content joined to `folder`: `.` and empty segments dropped,
/// each `..` removing the segment before it; None above the root.
fn join(folder: &str, content: &str) -> Option<String> {
    let mut parts: Vec<&str> = Vec::new();
    for part in folder.split('/').chain(content.split('/')) {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop()?;
            }
            _ => parts.push(part),
        }
    }
    Some(parts.join("/"))
}

fn relative(content: &str) -> bool {
    content.starts_with("./") || content.starts_with("../")
}

/// What the discovery found: every path to lock, and the first unreadable
/// config module in bytewise path order with why.
#[derive(Default)]
pub struct Found {
    pub paths: BTreeSet<String>,
    pub unreadable: Option<(String, String)>,
}

/// Point 1's discovery on the working tree, run to the end.
pub fn discover(repo: &Repo, config: &Config) -> Result<Found> {
    let suites = vitest_suites(config);
    if suites.is_empty() {
        return Ok(Found::default());
    }
    let listed = repo.files()?;
    let present: BTreeSet<&str> = listed.iter().map(String::as_str).collect();
    let mut why: BTreeMap<String, String> = BTreeMap::new();
    let mut paths = BTreeSet::new();
    let mut queue = Vec::new();
    for path in runner_configs(&suites, &listed) {
        match kind(repo, &path)? {
            Kind::File => queue.push(path),
            Kind::Link => {
                why.entry(path.clone()).or_insert_with(|| format!("{} is a symbolic link", one_line(&path)));
            }
            Kind::Folder => {}
        }
    }
    let mut seen: BTreeSet<String> = queue.iter().cloned().collect();
    while let Some(module) = queue.pop() {
        paths.insert(module.clone());
        let scanned = module.rsplit_once('.').is_some_and(|(_, ext)| JS_EXTS.contains(&ext));
        if !scanned {
            continue;
        }
        let bytes = fs::read(repo.path(&module)).map_err(|e| failed(format!("read {module}: {e}")))?;
        let mut first: Option<String> = None;
        for event in scan::scan(&String::from_utf8_lossy(&bytes)) {
            let (content, import) = match event {
                Event::Bad(reason) => {
                    first.get_or_insert(reason);
                    continue;
                }
                Event::Setup(content) if content.starts_with('/') => {
                    first.get_or_insert_with(|| format!("{} is an absolute path", one_line(&content)));
                    continue;
                }
                Event::Setup(content) => (content, false),
                Event::Import(content) if relative(&content) => (content, true),
                Event::Import(_) => continue,
            };
            let Some(base) = join(folder(&module), &content) else { continue };
            let mut named = false;
            let candidates = [base.clone()].into_iter().chain(JS_EXTS.iter().map(|ext| format!("{base}.{ext}")));
            for candidate in candidates.filter(|c| present.contains(c.as_str())) {
                match kind(repo, &candidate)? {
                    Kind::File => named = true,
                    Kind::Link => {
                        first.get_or_insert_with(|| format!("{} is a symbolic link", one_line(&candidate)));
                        named = true;
                        continue;
                    }
                    Kind::Folder => continue,
                }
                if !import {
                    paths.insert(candidate);
                } else if seen.insert(candidate.clone()) {
                    queue.push(candidate);
                }
            }
            if !named && relative(&content) {
                first.get_or_insert_with(|| format!("{} names no file in the repository", one_line(&content)));
            }
        }
        if let Some(reason) = first {
            why.entry(module).or_insert(reason);
        }
    }
    Ok(Found { paths, unreadable: why.into_iter().next() })
}

enum Kind {
    File,
    Link,
    Folder,
}

/// A repository path as `fs::symlink_metadata` sees it. Every path asked is one
/// `repo.files()` lists, so one the tree no longer has (a tracked file deleted)
/// is a read failure, as `locked_files` fails on it: exit 2, no lock written.
fn kind(repo: &Repo, path: &str) -> Result<Kind> {
    match fs::symlink_metadata(repo.path(path)) {
        Ok(meta) if meta.file_type().is_symlink() => Ok(Kind::Link),
        Ok(meta) if meta.is_dir() => Ok(Kind::Folder),
        Ok(_) => Ok(Kind::File),
        Err(e) => Err(failed(format!("read {path}: {e}"))),
    }
}

/// Point 2: the refusal for the first unreadable config module.
pub fn refuse_unreadable<T>(config: &str, why: &str) -> Result<T> {
    let config = one_line(config);
    refuse(
        "setup-unreadable",
        format!("could not read the vitest setup files of {config}: {why}"),
        "red locks the setup files it can name; one it cannot name could change what every locked case sees",
        format!("in {config}, write setupFiles and globalSetup as string literals or arrays of them, with paths relative to the file and no root key, then run red again"),
    )
}

/// Point 3: the lock's paths that match no suite's globs and are not the config.
fn beside(config: &Config, lock: &Lock) -> Vec<String> {
    let outside = |path: &&String| path.as_str() != CONFIG_FILE && !config.is_test_file(path);
    lock.files.keys().filter(outside).map(|path| one_line(path)).collect()
}

/// Point 3's line, right before `RED locked at`/`RED redone at`.
pub fn print_beside(config: &Config, lock: &Lock) {
    let shown = beside(config, lock);
    if !shown.is_empty() {
        println!("shipcraft: red also locked what vitest reads beside the tests: {}", short_list(&shown));
    }
}

/// The paths of a snapshot.
fn snapshot_paths(repo: &Repo, snapshot: &Snapshot) -> Result<Vec<String>> {
    let out = match snapshot {
        Snapshot::Tree => return repo.files(),
        Snapshot::Index => repo.run(&["ls-files", "-z", "--cached"])?,
        Snapshot::Commit(rev) => repo.run(&["ls-tree", "-r", "-z", "--name-only", rev])?,
    };
    let mut paths: Vec<String> = out.split(|b| *b == 0).filter(|p| !p.is_empty()).map(crate::git::text).collect();
    paths.sort();
    paths.dedup();
    Ok(paths)
}

/// Point 4, right after `check_lefthook`: a locked runner config of the
/// snapshot's vitest suites that no parent has and the lock does not hold.
pub fn check_added(repo: &Repo, parents: &[Snapshot], snapshot: &Snapshot, lock_path: &str, lock: &Lock) -> Result<()> {
    let Some(config) = Config::at(repo, snapshot)? else { return Ok(()) };
    let suites = vitest_suites(&config);
    if suites.is_empty() {
        return Ok(());
    }
    for path in runner_configs(&suites, &snapshot_paths(repo, snapshot)?) {
        if lock.files.contains_key(&path) {
            continue;
        }
        let mut in_parent = false;
        for parent in parents {
            in_parent |= repo.read(parent, &path)?.is_some();
        }
        if in_parent {
            continue;
        }
        let shown = one_line(&path);
        return refuse(
            "runner-config-added",
            format!("runner config {shown} was added {} with lock {} open", snapshot.describe(), one_line(lock_path)),
            "vitest reads its settings from this file, so adding one during GREEN can change the judge mid-game",
            format!("remove {shown}; if the suite needs it, add it in a RED (shipcraft red --redo) or after the cycle closes"),
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn suite(raiz: &str, comando: &str) -> Suite {
        let text = format!("[[suite]]\nroot = \"{raiz}\"\ncommand = \"{comando}\"\nglobs = [\"**/*.test.ts\"]\n");
        Config::parse(&text).unwrap().suites().remove(0)
    }

    fn paths(list: &[&str]) -> Vec<String> {
        list.iter().map(|p| p.to_string()).collect()
    }

    fn found(set: BTreeSet<String>) -> Vec<String> {
        set.into_iter().collect()
    }

    /// A git repository with `files` committed, then `deleted` removed from the tree.
    fn repo_with(files: &[(&str, &str)], deleted: &[&str]) -> (crate::git::TempDir, Repo) {
        let dir = crate::git::TempDir::new("shipcraft-vitest-files-").unwrap();
        let git = |args: &[&str]| assert!(crate::git::git_in(dir.path(), args).unwrap().status.success());
        git(&["init", "-q"]);
        for (path, text) in files {
            let full = dir.path().join(path);
            fs::create_dir_all(full.parent().unwrap()).unwrap();
            fs::write(full, text).unwrap();
        }
        git(&["add", "-A"]);
        for path in deleted {
            fs::remove_file(dir.path().join(path)).unwrap();
        }
        let repo = Repo::at_root(dir.path());
        (dir, repo)
    }

    #[test]
    fn a_tracked_path_deleted_from_the_tree_fails_the_discovery() {
        let config = Config::parse("[[suite]]\ncommand = \"vitest run\"\nglobs = [\"src/**/*.test.ts\"]\n").unwrap();
        let files = [
            ("vitest.config.ts", "import './base'\nexport default { test: { setupFiles: ['./src/setup'] } }"),
            ("base.ts", "export {}"),
            ("src/setup.ts", "// setup"),
        ];
        let (_dir, repo) = repo_with(&files, &[]);
        let whole = discover(&repo, &config).unwrap();
        assert!(whole.unreadable.is_none());
        assert_eq!(found(whole.paths), paths(&["base.ts", "src/setup.ts", "vitest.config.ts"]));
        // A runner config, a module reached by an import and a setup file candidate.
        for gone in ["vitest.config.ts", "base.ts", "src/setup.ts"] {
            let (_dir, repo) = repo_with(&files, &[gone]);
            match discover(&repo, &config) {
                Err(crate::refusal::Stop::Failed(message)) => {
                    assert!(message.starts_with(&format!("read {gone}: ")), "{message}")
                }
                _ => panic!("{gone} deleted from the tree must fail the discovery"),
            }
        }
        // A setup literal with no candidate git lists is still unreadable.
        let missing = [("vitest.config.ts", "export default { test: { setupFiles: './nope.ts' } }")];
        let (_dir, repo) = repo_with(&missing, &[]);
        let why = discover(&repo, &config).unwrap().unreadable;
        assert_eq!(why, Some(("vitest.config.ts".into(), "./nope.ts names no file in the repository".into())));
    }

    #[test]
    fn runner_config_names() {
        assert!(runner_name("a/vitest.config.mts") == Some(Name::VitestConfig));
        assert!(runner_name("vitest.workspace.cjs") == Some(Name::Workspace));
        assert!(runner_name("vite.config.js") == Some(Name::Vite));
        assert!(runner_name("vitest.config.json").is_none());
        assert!(runner_name("vite.config.tsx").is_none());
        assert!(runner_name("my.vitest.config.ts").is_none());
    }

    #[test]
    fn the_runner_configs_of_a_root_suite() {
        let all = paths(&[
            "examples/demo/vite.config.ts",
            "node_modules/x/vitest.config.ts",
            "pkg/vitest.config.ts",
            "vite.config.ts",
            "vitest.workspace.ts",
        ]);
        let root = [suite(".", "npx vitest run")];
        assert_eq!(
            found(runner_configs(&root, &all)),
            paths(&["pkg/vitest.config.ts", "vite.config.ts", "vitest.workspace.ts"])
        );
        let mut with = all.clone();
        with.push("vitest.config.ts".into());
        assert_eq!(
            found(runner_configs(&root, &with)),
            paths(&["pkg/vitest.config.ts", "vitest.config.ts", "vitest.workspace.ts"]),
            "a vite.config beside a vitest.config is not locked"
        );
    }

    #[test]
    fn the_runner_configs_of_a_suite_in_a_folder() {
        let all = paths(&["vite.config.ts", "web/sub/vitest.config.ts", "web/vite.config.ts", "web/x/vite.config.ts"]);
        let web = [suite("web", "vitest run")];
        assert_eq!(found(runner_configs(&web, &all)), paths(&["web/sub/vitest.config.ts", "web/vite.config.ts"]));
        let jest = Config::parse("[[suite]]\ncommand = \"jest\"\nglobs = [\"*.test.ts\"]\n").unwrap();
        assert!(vitest_suites(&jest).is_empty(), "a suite whose command does not contain vitest");
    }

    #[test]
    fn a_literal_joins_the_module_folder() {
        assert_eq!(join("src", "./test-setup.ts").as_deref(), Some("src/test-setup.ts"));
        assert_eq!(join("a/b", "../c//./d").as_deref(), Some("a/c/d"));
        assert_eq!(join("", "./x").as_deref(), Some("x"));
        assert_eq!(join("a", "../../x"), None);
        assert_eq!(join("", "@testing-library/jest-dom/vitest").as_deref(), Some("@testing-library/jest-dom/vitest"));
    }

    #[test]
    fn the_unreadable_refusal_text() {
        let Err(crate::refusal::Stop::Refused(refusal)) = refuse_unreadable::<()>("a\nb.ts", "it sets root") else {
            panic!("a refusal")
        };
        assert_eq!(refusal.code, "setup-unreadable");
        assert_eq!(
            refusal.to_string(),
            "shipcraft refused: could not read the vitest setup files of a\\nb.ts: it sets root\n\
             Why: red locks the setup files it can name; one it cannot name could change what every locked case sees\n\
             Next: in a\\nb.ts, write setupFiles and globalSetup as string literals or arrays of them, with paths relative to the file and no root key, then run red again"
        );
    }

    #[test]
    fn the_paths_beside_the_tests() {
        let config = Config::parse("[[suite]]\ncommand = \"vitest run\"\nglobs = [\"src/**/*.test.ts\"]\n").unwrap();
        let fix = crate::lock::Fix { kind: crate::lock::Kind::Feature, reported_at: None, fixes_release: None };
        let files: BTreeMap<String, String> = [CONFIG_FILE, "src/a.test.ts", "vitest.config.ts", "src/setup.ts"]
            .iter()
            .map(|p| (p.to_string(), String::new()))
            .collect();
        let lock = Lock::open(files, Vec::new(), Vec::new(), Vec::new(), fix);
        assert_eq!(beside(&config, &lock), paths(&["src/setup.ts", "vitest.config.ts"]));
    }
}
