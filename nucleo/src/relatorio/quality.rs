//! The size, reds and review lines from the run log (items 107, 109, 112, 123).

use super::flow::merge_counts;
use super::prs::iso_week;
use super::rows::{at, is, num, str_of};
use super::Row;
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};

/// Item 107: the `size` line, the PRs counted against their size limit, from
/// the `pr` and `merge` rows in the file's order; None when no PR is measured.
/// A PR's size and limit are those of its last measured `pr` row (a JSON
/// integer `pr` above 0, `product_lines` and `warn_lines` JSON integers) before
/// the first counting `merge` row of the same number.
pub(super) fn size(rows: &[Row]) -> Option<Value> {
    let (sizes, merged) = measured(rows);
    let measured: BTreeMap<u64, bool> = sizes.into_iter().map(|(pr, (lines, limit))| (pr, lines > limit)).collect();
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

/// Item 107's reading: per PR, the `product_lines` and `warn_lines` of its
/// last measured `pr` row before its first counting `merge` row, and the PRs
/// with a counting `merge` row.
pub(super) fn measured(rows: &[Row]) -> (BTreeMap<u64, (u64, u64)>, BTreeSet<u64>) {
    let int = |r: &Row, key: &str| r.get(key).and_then(Value::as_u64);
    let mut measured = BTreeMap::new();
    let mut merged: BTreeSet<u64> = BTreeSet::new();
    for row in rows {
        let Some(pr) = int(row, "pr").filter(|n| *n > 0) else { continue };
        if merge_counts(row) {
            merged.insert(pr);
        } else if str_of(row, "layer") == "pr" && !merged.contains(&pr) {
            if let Some(size) = int(row, "product_lines").zip(int(row, "warn_lines")) {
                measured.insert(pr, size);
            }
        }
    }
    (measured, merged)
}

/// Item 109: the `reds` line, the `suite-red` rows of `ci` and those a later
/// green `ci` row on the same commit followed, in the file's order; None when
/// no red row exists. `at`, `branch`, `lock`, `locks` and `failed_count` are not read.
pub(super) fn reds(rows: &[Row]) -> Option<Value> {
    tally("reds", &red_rows(rows))
}

/// Item 123: the `reds_week` lines, item 109's reading over the red rows of
/// each ISO week of their `at` (item 120's rule), earliest week first; a red
/// row without a week is in none.
pub(super) fn reds_weeks(rows: &[Row]) -> Vec<Value> {
    let mut weeks: BTreeMap<String, Vec<(&Row, bool)>> = BTreeMap::new();
    for red in red_rows(rows) {
        if let Some(week) = at(red.0).and_then(iso_week) {
            weeks.entry(week).or_default().push(red);
        }
    }
    let mut lines = Vec::new();
    for (week, reds) in weeks {
        let mut line = tally("reds_week", &reds).expect("a week has a red row");
        line["week"] = json!(week);
        lines.push(line);
    }
    lines
}

/// Item 109's red rows, in the file's order, each with whether it is green again.
fn red_rows(rows: &[Row]) -> Vec<(&Row, bool)> {
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
    let again =
        |i: usize, row: &Row| last_green.get(commit(row).expect("red rows have a commit")).is_some_and(|g| *g > i);
    rows.iter().enumerate().filter(|(_, r)| red(r)).map(|(i, row)| (row, again(i, row))).collect()
}

/// Item 109's counts over some red rows; None when there are none.
fn tally(kind: &str, reds: &[(&Row, bool)]) -> Option<Value> {
    if reds.is_empty() {
        return None;
    }
    let (mut green_again, mut named) = (0usize, 0usize);
    let mut secs = 0.0f64;
    let mut cases: BTreeMap<&str, usize> = BTreeMap::new();
    for (row, _) in reds.iter().filter(|(_, again)| *again) {
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
    let mut top: Vec<(&str, usize)> = cases.into_iter().collect();
    // Most rows first; the map gave byte order, and the sort is stable.
    top.sort_by_key(|a| std::cmp::Reverse(a.1));
    let cases: Vec<Value> = top.into_iter().take(5).map(|(id, n)| json!({"id": id, "rows": n})).collect();
    Some(json!({
        "kind": kind, "suite_red": reds.len(), "green_again": green_again,
        "green_again_share": num(green_again as f64 / reds.len() as f64),
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

#[cfg(test)]
mod tests {
    use super::*;

    fn log(lines: &[Value]) -> Vec<Row> {
        lines.iter().map(|v| v.as_object().cloned().expect("an object")).collect()
    }

    fn red(at: Value, commit: &str, secs: f64, failed: &[&str]) -> Value {
        json!({"layer": "ci", "result": "refused", "code": "suite-red", "commit": commit, "at": at,
               "secs": secs, "failed": failed})
    }

    fn green(commit: &str) -> Value {
        json!({"layer": "ci", "result": "passed", "commit": commit, "at": 0})
    }

    #[test]
    fn reds_weeks_split_item_109s_reading_by_the_red_rows_iso_week() {
        // 2026-11-16 (Monday, W47) and 2026-11-15 (Sunday, W46); 1970-01-01 is W01.
        let (w46, w47) = (1_794_787_199.0, 1_794_787_200.0);
        let rows = log(&[
            red(json!(w47), "a", 10.0, &["t1", "t2"]),
            red(json!(w46), "b", 2.5, &[]),
            red(json!(100), "c", 4.0, &["t1"]),
            red(json!("x"), "a", 7.0, &["t9"]),
            red(json!(-1), "a", 1.0, &[]),
            red(json!(253_402_300_800u64), "a", 1.0, &[]),
            json!({"layer": "ci", "result": "refused", "code": "suite-red", "commit": "a", "secs": 1}),
            green("a"),
            green("b"),
        ]);
        let weeks = reds_weeks(&rows);
        let names: Vec<&str> = weeks.iter().map(|w| w["week"].as_str().unwrap()).collect();
        assert_eq!(names, ["1970-W01", "2026-W46", "2026-W47"]);
        assert_eq!(
            weeks[0],
            json!({"kind": "reds_week", "week": "1970-W01", "suite_red": 1, "green_again": 0,
                   "green_again_share": 0, "green_again_secs": 0, "named": 0, "cases": []})
        );
        assert_eq!(weeks[1]["green_again_secs"], json!(2.5));
        assert_eq!(weeks[1]["named"], 1);
        assert_eq!(weeks[2]["cases"], json!([{"id": "t1", "rows": 1}, {"id": "t2", "rows": 1}]));
        // Rows without a week count in `reds` only.
        let total = reds(&rows).unwrap();
        assert_eq!(total["suite_red"], 7);
        let sum = |key: &str| weeks.iter().map(|w| w[key].as_u64().unwrap()).sum::<u64>();
        assert_eq!((sum("suite_red"), sum("green_again")), (3, 2));
        assert_eq!(total["green_again"], 6);
        // No red row, or none with a week: no week line.
        assert!(reds_weeks(&log(&[green("a")])).is_empty());
        assert!(reds_weeks(&log(&[red(json!(null), "a", 1.0, &[])])).is_empty());
    }

    #[test]
    fn reds_week_text_is_the_reds_line_with_its_week() {
        let rows = log(&[red(json!(100), "a", 3723.0, &["a\"b"]), green("a")]);
        let lines: Vec<Value> = reds(&rows).into_iter().chain(reds_weeks(&rows)).collect();
        assert_eq!(
            super::super::text::text(&lines),
            "reds: 1 suite-red, 1 green again on the same commit (100%), 1 h 2 min 3 s of CI; cases named in 1: \"a\\\"b\" (1)\n\
             reds 1970-W01: 1 suite-red, 1 green again on the same commit (100%), 1 h 2 min 3 s of CI; cases named in 1: \"a\\\"b\" (1)\n"
        );
    }
}
