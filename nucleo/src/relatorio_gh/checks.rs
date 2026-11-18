//! Item 114's reading of a PR's commits and check runs.

use super::answers::{check_run, oid, pages, time};
use serde_json::Value;

/// Item 114: a name's counts in one PR: runs, red, green again, fixed by a
/// new commit, still red.
pub type Tally = [u64; 5];

#[derive(Clone, Copy, PartialEq)]
enum Verdict {
    Red,
    Green,
    Other,
}

/// A completed run of a `suite_checks` name: the name's index, its verdict
/// and its completion time.
pub(super) struct Run {
    pub(super) name: usize,
    verdict: Verdict,
    at: i64,
}

/// Item 114: a slurped PR commits list (a non-empty array of array pages,
/// every entry an object with a 40-lowercase-hex `sha`): the distinct shas,
/// each at its first position.
pub(super) fn pr_commits(answer: &Value) -> Option<Vec<String>> {
    let mut commits: Vec<String> = Vec::new();
    for page in answer.as_array().filter(|p| !p.is_empty())? {
        for entry in page.as_array()? {
            let sha = entry.as_object()?.get("sha")?.as_str().filter(|s| oid(s))?;
            if !commits.iter().any(|c| c == sha) {
                commits.push(sha.to_string());
            }
        }
    }
    Some(commits)
}

/// Item 114: a commit's `filter=all` check runs (item 79's reader): the
/// completed runs of the `names`, each with a time `completed_at`.
pub(super) fn suite_runs(answer: &Value, names: &[String]) -> Option<Vec<Run>> {
    let mut runs = Vec::new();
    for e in pages(answer, "check_runs", check_run)? {
        let Some(name) = names.iter().position(|n| e["name"] == n.as_str()) else { continue };
        if e["status"] != "completed" {
            continue;
        }
        let at = e.get("completed_at").and_then(Value::as_str).and_then(time)?;
        let verdict = match e["conclusion"].as_str() {
            Some("failure" | "timed_out") => Verdict::Red,
            Some("success") => Verdict::Green,
            _ => Verdict::Other,
        };
        runs.push(Run { name, verdict, at });
    }
    Some(runs)
}

/// Item 114: each red run judged on its own: green again (a later green run
/// of its name at its commit), else fixed by a new commit (a later green run
/// of its name at a later commit of the PR), else still red.
pub(super) fn tally(commits: &[Vec<Run>], names: usize) -> Vec<Tally> {
    let mut counts = vec![[0u64; 5]; names];
    for (i, runs) in commits.iter().enumerate() {
        for red in runs {
            let count = &mut counts[red.name];
            count[0] += 1;
            if red.verdict != Verdict::Red {
                continue;
            }
            count[1] += 1;
            let green_after = |runs: &Vec<Run>| {
                runs.iter().any(|g| g.name == red.name && g.verdict == Verdict::Green && g.at > red.at)
            };
            if green_after(runs) {
                count[2] += 1;
            } else if commits[i + 1..].iter().any(green_after) {
                count[3] += 1;
            } else {
                count[4] += 1;
            }
        }
    }
    counts
}
