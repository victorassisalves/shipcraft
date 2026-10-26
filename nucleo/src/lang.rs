//! Language profiles: how a project in each language is detected, how its
//! suite runs, which files are tests (and test support), and the stub hint of
//! its messages.

use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Lang {
    Python,
    Node,
    Go,
}

/// What `shipcraft init` writes for one suite.
pub struct Profile {
    pub runner: &'static str,
    pub command: String,
    /// The check of the whole project (`verifica`): the CI's, never the hook's.
    pub check: Option<String>,
    pub globs: &'static [&'static str],
}

impl Lang {
    const ALL: [Lang; 3] = [Lang::Python, Lang::Node, Lang::Go];

    pub fn name(self) -> &'static str {
        match self {
            Lang::Python => "python",
            Lang::Node => "node",
            Lang::Go => "go",
        }
    }

    pub fn from_name(name: &str) -> Option<Lang> {
        Lang::ALL.into_iter().find(|lang| lang.name() == name)
    }

    /// The languages whose markers are in `root`.
    pub fn detect(root: &Path) -> Vec<Lang> {
        let mut found = Vec::new();
        if root.join("pyproject.toml").exists() || has_requirements_file(root) {
            found.push(Lang::Python);
        }
        if node_runner(root).is_some() {
            found.push(Lang::Node);
        }
        if root.join("go.mod").exists() {
            found.push(Lang::Go);
        }
        found
    }

    /// The suite of a package in `dir`. `{junit}` in the command is where shipcraft
    /// asks the runner to write its JUnit report; `bin` is how node tools are
    /// found (`node_modules/.bin/`, or `npx --no -- ` inside a workspace: the `--` keeps the
    /// tool's flags from npx, item 12).
    pub fn profile(self, dir: &Path, bin: &str) -> Profile {
        match self {
            Lang::Python => Profile {
                runner: "pytest",
                command: "python3 -m pytest -p no:cacheprovider --junitxml={junit}".to_string(),
                check: None,
                globs: &[
                    "**/test_*.py",
                    "**/*_test.py",
                    "**/conftest.py",
                    "**/tests/**/fixtures/**",
                    "**/tests/**/helpers/**",
                    "**/test/**/fixtures/**",
                    "**/test/**/helpers/**",
                ],
            },
            Lang::Node => {
                let runner = node_runner(dir).unwrap_or("vitest");
                let check = dir.join("tsconfig.json").exists().then(|| format!("{bin}tsc --noEmit"));
                // jest-junit names each case by its file, as vitest does: the
                // hook runs the RED's cases by the files that hold them (item 13).
                let run = match runner {
                    "jest" => format!(
                        "JEST_JUNIT_OUTPUT_FILE={{junit}} JEST_JUNIT_CLASSNAME='{{filepath}}' {bin}jest --ci --reporters=default --reporters=jest-junit"
                    ),
                    _ => format!("{bin}vitest run --reporter=default --reporter=junit --outputFile.junit={{junit}}"),
                };
                Profile {
                    runner,
                    command: run,
                    check,
                    globs: &["**/*.test.*", "**/*.spec.*", "**/__tests__/**", "**/vitest.config.*", "**/jest.config.*"],
                }
            }
            Lang::Go => Profile {
                runner: "gotestsum",
                command: "gotestsum --junitfile {junit} -- ./...".to_string(),
                check: Some("go vet ./...".to_string()),
                globs: &["**/*_test.go", "**/testdata/**"],
            },
        }
    }

    /// How to write a stub that fails by assertion instead of not compiling.
    pub fn stub_hint(self) -> &'static str {
        match self {
            Lang::Python => "create the stub: the function exists and raises `NotImplementedError`",
            Lang::Node => {
                "create the stub: export the function with the right signature and body `throw new Error(\"not implemented\")`"
            }
            Lang::Go => "create the stub: the function exists with the right signature and returns the zero value",
        }
    }
}

fn has_requirements_file(root: &Path) -> bool {
    let Ok(entries) = fs::read_dir(root) else { return false };
    entries.flatten().any(|entry| {
        let name = entry.file_name().to_string_lossy().into_owned();
        name.starts_with("requirements") && name.ends_with(".txt")
    })
}

fn package_json(dir: &Path) -> Option<serde_json::Value> {
    serde_json::from_str(&fs::read_to_string(dir.join("package.json")).ok()?).ok()
}

/// "vitest" or "jest" when package.json depends on one of them.
fn node_runner(dir: &Path) -> Option<&'static str> {
    let package = package_json(dir)?;
    let depends_on =
        |name: &str| ["dependencies", "devDependencies"].iter().any(|section| package[section].get(name).is_some());
    ["vitest", "jest"].into_iter().find(|runner| depends_on(runner))
}

/// A workspace (item 9): its language and the package patterns, from
/// `pnpm-workspace.yaml`, `workspaces` in `package.json`, or `go.work`.
pub fn workspace(root: &Path) -> Option<(Lang, Vec<String>)> {
    if let Ok(text) = fs::read_to_string(root.join("pnpm-workspace.yaml")) {
        let patterns: Vec<String> = text
            .lines()
            .filter_map(|line| line.trim().strip_prefix("- "))
            .map(|p| p.trim().trim_matches(|c| c == '"' || c == '\'').to_string())
            .collect();
        return Some((Lang::Node, patterns));
    }
    if let Some(package) = package_json(root) {
        let list = package["workspaces"].as_array().or_else(|| package["workspaces"]["packages"].as_array());
        if let Some(list) = list {
            return Some((Lang::Node, list.iter().filter_map(|v| v.as_str().map(str::to_string)).collect()));
        }
    }
    let text = fs::read_to_string(root.join("go.work")).ok()?;
    let mut dirs = Vec::new();
    let mut in_block = false;
    for line in text.lines().map(str::trim) {
        if in_block {
            if line.starts_with(')') {
                in_block = false;
            } else if !line.is_empty() && !line.starts_with("//") {
                dirs.push(line.to_string());
            }
        } else if let Some(rest) = line.strip_prefix("use") {
            match rest.trim() {
                "(" => in_block = true,
                one if !one.is_empty() => dirs.push(one.to_string()),
                _ => {}
            }
        }
    }
    Some((Lang::Go, dirs))
}
