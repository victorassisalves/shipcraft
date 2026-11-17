//! Item 38: `shipcraft report [--json]`, the flow measured from the run log.
//! It finds `.git` by walking up from the current directory and never refuses.
//! Item 76: `[--since <tag>]`, and a local DORA readout from the run log, the
//! release tags and the lock files, read through `git -C <root>` read-only, with
//! no network read; a key without data says so with a count.
//! Item 79: `[--github]` fills the selected locks' waiting and merge times
//! from GitHub through `gh` (relatorio_gh); without it, nothing changes.
//! Item 99: `[report] release_tags` in `<root>/.shipcraft.toml` names the
//! project's release tags; without it, item 76's `vX.Y.Z` tags.

mod dora;
mod evidence;
mod flow;
mod git;
mod github;
mod quality;
mod rows;
mod selection;
#[cfg(test)]
mod tests;
mod text;

use crate::config;
use crate::refusal::Result;
use crate::relatorio_gh::Asker;
use dora::dora;
pub(crate) use evidence::days_from_civil;
use evidence::{Evidence, Facts};
use flow::{read, Report};
pub(crate) use git::{Git, REPOSITORY_VARS};
use github::{ask_github, blocking, checks};
use quality::{reds, review, size};
use rows::locks_of;
pub(crate) use rows::num;
use selection::Selection;
use serde_json::{json, Map, Value};
use std::fs;
use std::path::{Path, PathBuf};
use text::text;

type Row = Map<String, Value>;

/// Item 105: `red --fixes-release <tag>`'s selection check, with item 99's
/// reader of the working tree's `[report]` (the root found as `report` finds
/// it; none found is the default reading) and its matcher. None when the tag
/// names a release of the selection; else the `<pattern>` the refusal shows:
/// the pattern, `vX.Y.Z` under the default reading, or `invalid: <reason>`
/// (item 99's full reason, as `report` prints it) under an invalid
/// `[report]`, where no tag is accepted.
pub fn not_a_release_name(tag: &str) -> Option<String> {
    let selection = discover().map_or(Selection::Default, |(root, _)| Selection::read(&root));
    selection.release_name_problem(tag)
}

/// What `report` reads before any git call: the repository and run log, and
/// the release selection (item 99), so `main` checks `--since`'s grammar first.
pub struct Prepared {
    found: Option<(PathBuf, PathBuf)>,
    selection: Selection,
}

impl Prepared {
    pub fn read() -> Prepared {
        let found = discover();
        let selection = found.as_ref().map_or(Selection::Default, |(root, _)| Selection::read(root));
        Prepared { found, selection }
    }

    /// `--since`'s grammar: the pattern when `release_tags` is valid, item
    /// 76's `vX.Y.Z` with the default reading, none with an invalid `[report]`.
    pub fn since_grammar(&self, tag: &str) -> bool {
        match &self.selection {
            Selection::Invalid(_) => true,
            selection => selection.names(tag),
        }
    }
}

pub fn run(prepared: Prepared, as_json: bool, since: Option<&str>, github: bool) -> Result<()> {
    let Prepared { found, selection } = prepared;
    let bytes = found.as_ref().and_then(|(_, log)| fs::read(log).ok()).unwrap_or_default();
    let (rows, gaps) = read(&bytes);
    let mut ids: Vec<String> = Vec::new();
    for id in rows.iter().flat_map(locks_of) {
        if !ids.contains(&id) {
            ids.push(id);
        }
    }
    let root = found.as_ref().map(|(root, _)| root.clone()).unwrap_or_default();
    let git = Git { root: root.clone() };
    let evidence = match (&found, &selection) {
        (None, _) => Err("no git repository found".to_string()),
        // Item 99: an invalid `[report]` reads no git, as a git failure.
        (Some(_), Selection::Invalid(problem)) => Err(config::report_invalid(problem)),
        (Some(_), selection) => Evidence::read(&git, &ids, selection),
    };
    if let (Some(tag), Ok(ev)) = (since, &evidence) {
        if !ev.releases.iter().any(|r| r.name == tag) {
            eprintln!("report: --since {tag} is not a release tag on {}", ev.branch);
            std::process::exit(2);
        }
    }
    let facts = evidence.as_ref().ok().map(|ev| Facts::of(ev, &rows, &ids));
    let mut report = Report::of(&rows, &ids, facts.as_ref());
    let evidence_facts = evidence.as_ref().map(|ev| (ev, facts.as_ref().expect("facts with evidence")));
    let dora = dora(&rows, evidence_facts, since, selection.pattern());
    // Item 79: after item 76's reads, and before the day rows take the waiting.
    let git_tip = evidence.as_ref().ok().map(|ev| (&git, ev.branch.as_str(), ev.tip_commit.as_str()));
    let mut asker = github.then(|| Asker::new(&root, git_tip));
    let summary = asker.as_mut().map(|asker| ask_github(asker, &rows, &mut report));
    let mut review_line = review(&rows);
    // Item 113: after item 79's calls, through the same asker.
    if let (Some(asker), Some(line)) = (asker.as_mut(), review_line.as_mut()) {
        blocking(asker, &rows, line);
    }
    // Item 114: after item 113's calls, through the same asker.
    let checks_line = match (asker.as_mut(), &review_line) {
        (Some(asker), Some(_)) => checks(asker, &rows),
        _ => None,
    };
    let gaps: Vec<Value> =
        gaps.into_iter().map(|(line, reason)| json!({"kind": "gap", "line": line, "reason": reason})).collect();
    let lines: Vec<Value> = [report.meta.clone()]
        .into_iter()
        .chain(report.locks.clone())
        .chain(report.days())
        .chain(size(&rows))
        .chain(reds(&rows))
        .chain(review_line)
        .chain(checks_line)
        .chain([dora])
        .chain(summary)
        .chain(gaps)
        .collect();
    if as_json {
        for line in &lines {
            println!("{line}");
        }
    } else {
        print!("{}", text(&lines));
    }
    Ok(())
}

/// The folder holding the `.git` (directory or file) found by walking up from
/// the current directory, and `<common git dir>/shipcraft/runs.jsonl`, the run
/// log `medicao` writes, found without git: a `.git` file (`gitdir: <dir>`)
/// leads to its `commondir`.
fn discover() -> Option<(PathBuf, PathBuf)> {
    let cwd = std::env::current_dir().ok()?;
    let dot = cwd.ancestors().map(|d| d.join(".git")).find(|p| p.exists())?;
    let root = dot.parent()?.to_path_buf();
    let git_dir = if dot.is_dir() {
        dot
    } else {
        let content = fs::read_to_string(&dot).ok()?;
        let dir = Path::new(content.trim().strip_prefix("gitdir:")?.trim());
        root.join(dir)
    };
    let common = match fs::read_to_string(git_dir.join("commondir")) {
        Ok(rel) => git_dir.join(rel.trim()),
        Err(_) => git_dir,
    };
    Some((root, common.join("shipcraft").join("runs.jsonl")))
}
