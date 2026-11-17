//! What `report --github` asks through `relatorio_gh`'s `Asker` (items 79, 113, 114).

use super::flow::{merge_row, Report};
use super::quality::round_pr;
use super::rows::{locks_of, num, str_of};
use super::Row;
use crate::relatorio_gh::{oid, Asker, Pr};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};

/// Item 79: asks GitHub about each selected lock row (`merged` or
/// `merge_not_observed`, `waiting` null), in print order, and fills what it
/// answers; every lock row gets its `github` list. The `github` summary line.
pub(super) fn ask_github(asker: &mut Asker, rows: &[Row], report: &mut Report) -> Value {
    let (mut selected, mut merge_filled, mut waiting_filled) = (0, 0, 0);
    let mut missing: BTreeMap<String, u64> = BTreeMap::new();
    for (row, merged) in report.locks.iter_mut().zip(report.merged.iter_mut()) {
        let mut filled: Vec<&str> = Vec::new();
        let state = row["state"].as_str().unwrap_or_default();
        if (state == "merged" || state == "merge_not_observed") && row["waiting"].is_null() {
            selected += 1;
            let pr = pr_of(rows, row["lock"].as_str().unwrap_or_default(), state == "merged");
            match asker.lock(row, pr, &mut filled) {
                Ok(waiting) => {
                    row["waiting"] = num(waiting);
                    filled.push("waiting");
                    if let Some(m) = merged {
                        m.waiting = Some(waiting);
                    }
                    waiting_filled += 1;
                }
                Err(reason) => *missing.entry(reason).or_default() += 1,
            }
            if filled.contains(&"merge_at") {
                merge_filled += 1;
            }
        }
        row["github"] = json!(filled);
    }
    json!({
        "kind": "github", "selected": selected, "merge_filled": merge_filled,
        "waiting_filled": waiting_filled, "missing": missing,
    })
}

/// Item 79: the PR a lock went through. A `merged` lock's is the `pr` of the
/// `merge` row that gave its `merge_at`; another's, the `pr` of every `pr`
/// row naming it, any result. Only positive JSON integers count.
fn pr_of(rows: &[Row], id: &str, merged: bool) -> Pr {
    let mine: Vec<&Row> = rows.iter().filter(|r| locks_of(r).iter().any(|l| l == id)).collect();
    let positive = |r: &Row| r.get("pr").and_then(Value::as_u64).filter(|n| *n > 0);
    let prs: BTreeSet<u64> = if merged {
        merge_row(&mine).and_then(positive).into_iter().collect()
    } else {
        mine.iter().filter(|r| str_of(r, "layer") == "pr").filter_map(|r| positive(r)).collect()
    };
    match prs.len() {
        0 => Pr::None,
        1 => Pr::One(prs.into_iter().next().expect("one PR")),
        _ => Pr::Several,
    }
}

/// Item 113: the reviewed commits, item 112's round rows grouped by `pr` and
/// `commit` (JSON equality; a missing `commit` is its own value), in the order
/// of each one's first round row.
pub(super) fn reviewed_commits(rows: &[Row]) -> Vec<(u64, Option<&Value>)> {
    let mut commits: Vec<(u64, Option<&Value>)> = Vec::new();
    for row in rows {
        let Some(pr) = round_pr(row) else { continue };
        let commit = (pr, row.get("commit"));
        if !commits.contains(&commit) {
            commits.push(commit);
        }
    }
    commits
}

/// Item 113: with `--github`, the Blocking count of each reviewed commit read
/// through item 79's asker, added to the `review` object as five keys.
pub(super) fn blocking(asker: &mut Asker, rows: &[Row], line: &mut Value) {
    let commits = reviewed_commits(rows);
    let mut per_pr: BTreeMap<u64, u64> = BTreeMap::new();
    let mut missing: BTreeMap<String, u64> = BTreeMap::new();
    let (mut total, mut read) = (0u64, 0u64);
    for (pr, commit) in &commits {
        let outcome = match commit.and_then(Value::as_str).filter(|c| oid(c)) {
            None => Err("no commit in the run log".to_string()),
            Some(commit) => asker.blocking(commit),
        };
        match outcome {
            Ok(count) => {
                total += count;
                read += 1;
                *per_pr.entry(*pr).or_default() += count;
            }
            Err(reason) => *missing.entry(reason).or_default() += 1,
        }
    }
    let mut most: Vec<(u64, u64)> = per_pr.into_iter().filter(|(_, n)| *n > 0).collect();
    // Most first; the map gave PR order, and the sort is stable.
    most.sort_by_key(|a| std::cmp::Reverse(a.1));
    let most: Vec<Value> = most.into_iter().take(5).map(|(pr, n)| json!({"pr": pr, "blocking": n})).collect();
    let object = line.as_object_mut().expect("the review line is an object");
    object.insert("blocking".into(), json!(total));
    object.insert("blocking_read".into(), json!(read));
    object.insert("blocking_commits".into(), json!(commits.len()));
    object.insert("blocking_missing".into(), json!(missing));
    object.insert("blocking_most".into(), json!(most));
}

/// Item 114: item 112's reviewed PRs, in the order of their first round row.
fn reviewed_prs(rows: &[Row]) -> Vec<u64> {
    let mut prs: Vec<u64> = Vec::new();
    for (pr, _) in reviewed_commits(rows) {
        if !prs.contains(&pr) {
            prs.push(pr);
        }
    }
    prs
}

/// Item 114: with `--github`, the red runs of each `suite_checks` name at the
/// commits of the reviewed PRs read in full; None with no reviewed PR or no
/// name in a readable config.
pub(super) fn checks(asker: &mut Asker, rows: &[Row]) -> Option<Value> {
    let prs = reviewed_prs(rows);
    if prs.is_empty() {
        return None;
    }
    let names = asker.suite_checks()?;
    let mut totals = vec![[0u64; 5]; names.len()];
    let mut missing: BTreeMap<String, u64> = BTreeMap::new();
    let mut read = 0u64;
    for pr in &prs {
        match asker.pr_checks(*pr, &names) {
            Ok(counts) => {
                read += 1;
                for (total, count) in totals.iter_mut().zip(counts) {
                    for (t, c) in total.iter_mut().zip(count) {
                        *t += c;
                    }
                }
            }
            Err(reason) => *missing.entry(reason).or_default() += 1,
        }
    }
    let names: Vec<Value> = names
        .iter()
        .zip(totals)
        .map(|(name, [runs, red, green_again, new_commit, still_red])| {
            json!({"name": name, "runs": runs, "red": red, "green_again": green_again,
                "new_commit": new_commit, "still_red": still_red})
        })
        .collect();
    Some(json!({"kind": "checks", "prs": prs.len(), "prs_read": read, "missing": missing, "names": names}))
}
