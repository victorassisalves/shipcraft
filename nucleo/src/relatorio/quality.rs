//! The size, reds and review lines from the run log (items 107, 109, 112).

use super::flow::merge_counts;
use super::rows::{is, num, str_of};
use super::Row;
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};

/// Item 107: the `size` line, the PRs counted against their size limit, from
/// the `pr` and `merge` rows in the file's order; None when no PR is measured.
/// A PR's size and limit are those of its last measured `pr` row (a JSON
/// integer `pr` above 0, `product_lines` and `warn_lines` JSON integers) before
/// the first counting `merge` row of the same number.
pub(super) fn size(rows: &[Row]) -> Option<Value> {
    let int = |r: &Row, key: &str| r.get(key).and_then(Value::as_u64);
    let mut measured: BTreeMap<u64, bool> = BTreeMap::new();
    let mut merged: BTreeSet<u64> = BTreeSet::new();
    for row in rows {
        let Some(pr) = int(row, "pr").filter(|n| *n > 0) else { continue };
        if merge_counts(row) {
            merged.insert(pr);
        } else if str_of(row, "layer") == "pr" && !merged.contains(&pr) {
            if let Some((lines, limit)) = int(row, "product_lines").zip(int(row, "warn_lines")) {
                measured.insert(pr, lines > limit);
            }
        }
    }
    if measured.is_empty() {
        return None;
    }
    let count = |all: &[bool]| (all.len(), all.iter().filter(|above| **above).count());
    let (prs, above) = count(&measured.values().copied().collect::<Vec<_>>());
    let (merged_prs, merged_above) =
        count(&measured.iter().filter(|(pr, _)| merged.contains(pr)).map(|(_, above)| *above).collect::<Vec<_>>());
    let share = |part: usize, whole: usize| (whole > 0).then(|| num(part as f64 / whole as f64));
    Some(json!({
        "kind": "size", "prs": prs, "above": above, "above_share": share(above, prs),
        "merged_prs": merged_prs, "merged_above": merged_above,
        "merged_above_share": share(merged_above, merged_prs),
    }))
}

/// Item 109: the `reds` line, the `suite-red` rows of `ci` and those a later
/// green `ci` row on the same commit followed, in the file's order; None when
/// no red row exists. `at`, `branch`, `lock`, `locks` and `failed_count` are not read.
pub(super) fn reds(rows: &[Row]) -> Option<Value> {
    fn commit(r: &Row) -> Option<&str> {
        r.get("commit").and_then(Value::as_str).filter(|c| !c.is_empty())
    }
    let ci = |r: &Row| str_of(r, "layer") == "ci";
    let red = |r: &Row| ci(r) && is(r, "refused") && str_of(r, "code") == "suite-red" && commit(r).is_some();
    // Items 40 and 62: a row that skipped the suite or left it to GitHub did not run it.
    let skipped = |r: &Row, key: &str| r.get(key) == Some(&Value::Bool(true));
    let green = |r: &Row| {
        ci(r) && is(r, "passed") && commit(r).is_some() && !skipped(r, "docs_only") && !skipped(r, "suite_in_checks")
    };
    // The last green row of each commit, by position in the file.
    let mut last_green: BTreeMap<&str, usize> = BTreeMap::new();
    for (i, row) in rows.iter().enumerate() {
        if green(row) {
            last_green.insert(commit(row).expect("green rows have a commit"), i);
        }
    }
    let (mut suite_red, mut green_again, mut named) = (0usize, 0usize, 0usize);
    let mut secs = 0.0f64;
    let mut cases: BTreeMap<&str, usize> = BTreeMap::new();
    for (i, row) in rows.iter().enumerate().filter(|(_, r)| red(r)) {
        suite_red += 1;
        if !last_green.get(commit(row).expect("red rows have a commit")).is_some_and(|g| *g > i) {
            continue;
        }
        green_again += 1;
        secs += row.get("secs").and_then(Value::as_f64).filter(|s| *s >= 0.0).unwrap_or(0.0);
        if let Some(failed) = row.get("failed").and_then(Value::as_array) {
            named += 1;
            let ids: BTreeSet<&str> = failed.iter().filter_map(Value::as_str).collect();
            for id in ids {
                *cases.entry(id).or_insert(0) += 1;
            }
        }
    }
    if suite_red == 0 {
        return None;
    }
    let mut top: Vec<(&str, usize)> = cases.into_iter().collect();
    // Most rows first; the map gave byte order, and the sort is stable.
    top.sort_by_key(|a| std::cmp::Reverse(a.1));
    let cases: Vec<Value> = top.into_iter().take(5).map(|(id, n)| json!({"id": id, "rows": n})).collect();
    Some(json!({
        "kind": "reds", "suite_red": suite_red, "green_again": green_again,
        "green_again_share": num(green_again as f64 / suite_red as f64),
        "green_again_secs": num(secs), "named": named, "cases": cases,
    }))
}

/// Item 112: the `review` line, the review rounds each PR needed; None when
/// no PR is reviewed. A round row is a `review` row with a JSON integer `pr`
/// above 0, a `passed` or `refused` result, and a `reused` that is not `true`.
pub(super) fn review(rows: &[Row]) -> Option<Value> {
    let mut rounds: BTreeMap<u64, usize> = BTreeMap::new();
    let mut changes_requested = 0usize;
    for row in rows {
        let Some(pr) = round_pr(row) else { continue };
        let refused = is(row, "refused");
        *rounds.entry(pr).or_insert(0) += 1;
        changes_requested += usize::from(refused);
    }
    if rounds.is_empty() {
        return None;
    }
    let mut most: Vec<(u64, usize)> = rounds.iter().filter(|(_, n)| **n >= 2).map(|(pr, n)| (*pr, *n)).collect();
    let second_round = most.len();
    // Most rounds first; the map gave PR order, and the sort is stable.
    most.sort_by_key(|a| std::cmp::Reverse(a.1));
    let most: Vec<Value> = most.into_iter().take(5).map(|(pr, n)| json!({"pr": pr, "rounds": n})).collect();
    Some(json!({
        "kind": "review", "prs": rounds.len(), "rounds": rounds.values().sum::<usize>(),
        "changes_requested": changes_requested, "second_round": second_round,
        "second_round_share": num(second_round as f64 / rounds.len() as f64), "most": most,
    }))
}

/// Item 112: a round row's PR: a `review` row, not reused, with a `passed`
/// or `refused` result and a JSON integer `pr` above 0.
pub(super) fn round_pr(row: &Row) -> Option<u64> {
    if str_of(row, "layer") != "review" || row.get("reused") == Some(&Value::Bool(true)) {
        return None;
    }
    if !is(row, "passed") && !is(row, "refused") {
        return None;
    }
    row.get("pr").and_then(Value::as_u64).filter(|n| *n > 0)
}
