//! Item 120: each merged PR, by ISO week and by size, and a suggested size limit.
//! Item 127: the markers of each merged PR's RED commit, and the review
//! numbers per marker.

use super::evidence::{days_from_civil, red_row};
use super::flow::merge_counts;
use super::quality::{measured, round_pr};
use super::rows::{at, is, locks_of, median, num};
use super::text::day;
use super::Row;
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};

/// Item 127: a PR's marker lines, word -> value.
pub(super) type Markers = BTreeMap<String, String>;

/// Victor's rule of 2026-11-18: the edges, the minimum and the default.
const EDGES: [u64; 9] = [100, 200, 300, 400, 500, 600, 800, 1000, 1500];
const MINIMUM: usize = 30;
const DEFAULT_LIMIT: u64 = 600;
/// The size table's buckets: `from < lines <= to`, 0 in the first, no `to` in the last.
const BUCKETS: [(u64, Option<u64>); 8] = [
    (0, Some(100)),
    (100, Some(200)),
    (200, Some(300)),
    (300, Some(400)),
    (400, Some(600)),
    (600, Some(800)),
    (800, Some(1200)),
    (1200, None),
];

/// What the week, size, limit and marker lines read of a merged PR.
struct MergedPr {
    merge_at: Option<f64>,
    markers: Option<Markers>,
    week: Option<String>,
    lines: Option<u64>,
    rounds: usize,
    changes: usize,
    first_approved: Option<bool>,
    red_to_merge: Option<f64>,
}

/// Each merged PR's merge row: the first counting one with a valid `pr`.
fn merges(rows: &[Row]) -> BTreeMap<u64, &Row> {
    let mut merges: BTreeMap<u64, &Row> = BTreeMap::new();
    for row in rows.iter().filter(|r| merge_counts(r)) {
        if let Some(pr) = row.get("pr").and_then(Value::as_u64).filter(|n| *n > 0) {
            merges.entry(pr).or_insert(row);
        }
    }
    merges
}

/// Item 127: each merged PR's first lock (its RED row the earliest, ties in
/// the merge row's order) and its parent, that RED row's full commit id.
pub(super) fn red_parents(rows: &[Row]) -> BTreeMap<u64, (String, String)> {
    let full = |c: &&str| (c.len() == 40 || c.len() == 64) && c.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'));
    let mut parents = BTreeMap::new();
    for (pr, merge) in merges(rows) {
        let mut first: Option<(f64, String, &Row)> = None;
        for id in locks_of(merge) {
            if let Some((row, t)) = red_row(rows, &id).and_then(|r| at(r).map(|t| (r, t))) {
                if first.as_ref().is_none_or(|(best, _, _)| t < *best) {
                    first = Some((t, id, row));
                }
            }
        }
        let Some((_, lock, row)) = first else { continue };
        if let Some(commit) = row.get("commit").and_then(Value::as_str).filter(full) {
            parents.insert(pr, (lock, commit.to_string()));
        }
    }
    parents
}

/// Item 127: the marker lines of a message, `<word> cases: <value>`, the
/// first of each word.
pub(super) fn markers_of(message: &str) -> Markers {
    let mut markers = Markers::new();
    for line in message.split('\n') {
        let line = line.strip_suffix('\r').unwrap_or(line);
        let Some((word, value)) = line.split_once(" cases: ") else { continue };
        let word_ok = (1..=32).contains(&word.len()) && word.bytes().all(|b| b.is_ascii_lowercase());
        if word_ok && (1..=32).contains(&value.len()) && value.bytes().all(|b| b.is_ascii_alphanumeric()) {
            markers.entry(word.to_string()).or_insert_with(|| value.to_string());
        }
    }
    markers
}

/// Item 127: a marker value's group.
fn group_of(value: Option<&str>) -> &'static str {
    match value {
        Some("yes") => "set",
        Some("no") => "unset",
        Some(v) if !v.is_empty() && v.bytes().all(|b| b.is_ascii_digit()) => {
            if v.bytes().all(|b| b == b'0') {
                "unset"
            } else {
                "set"
            }
        }
        _ => "none",
    }
}

/// The `merged_pr`, `week`, `size_bucket` and `limit` lines, from the run log;
/// item 127: each PR's `markers` (`null` when it has no RED commit read), then
/// the `marker` lines over the window (`since` and its start time). None when
/// no PR is merged.
pub(super) fn merged_prs(rows: &[Row], red: &BTreeMap<u64, Markers>, since: Option<(&str, Option<i64>)>) -> Vec<Value> {
    let (sizes, _) = measured(rows);
    let (mut lines, mut prs) = (Vec::new(), Vec::new());
    for (pr, merge) in merges(rows) {
        let locks = locks_of(merge);
        let merge_at = at(merge);
        let rounds: Vec<bool> = rows.iter().filter(|r| round_pr(r) == Some(pr)).map(|r| is(r, "passed")).collect();
        let red_at = locks.iter().filter_map(|id| red_row(rows, id).and_then(at)).reduce(f64::min);
        let p = MergedPr {
            merge_at,
            markers: red.get(&pr).cloned(),
            week: merge_at.and_then(iso_week),
            lines: sizes.get(&pr).map(|(lines, _)| *lines),
            rounds: rounds.len(),
            changes: rounds.iter().filter(|passed| !**passed).count(),
            first_approved: rounds.first().copied(),
            red_to_merge: merge_at.zip(red_at).map(|(m, r)| m - r).filter(|d| d.is_finite()),
        };
        lines.push(json!({
            "kind": "merged_pr", "pr": pr, "locks": locks, "merge_at": merge_at.map(num), "week": p.week,
            "product_lines": p.lines, "rounds": p.rounds, "changes_requested": p.changes,
            "first_round_approved": p.first_approved, "red_to_merge": p.red_to_merge.map(num),
            "markers": p.markers,
        }));
        prs.push(p);
    }
    let mut weeks: BTreeMap<&str, Vec<&MergedPr>> = BTreeMap::new();
    for p in &prs {
        if let Some(week) = &p.week {
            weeks.entry(week.as_str()).or_default().push(p);
        }
    }
    for (week, of_week) in weeks {
        let mut line = group(&of_week);
        line["kind"] = "week".into();
        line["week"] = week.into();
        line["red_to_merge_median"] = median(of_week.iter().filter_map(|p| p.red_to_merge).collect()).into();
        lines.push(line);
    }
    let sized: Vec<(u64, &MergedPr)> = prs.iter().filter_map(|p| p.lines.map(|n| (n, p))).collect();
    if !sized.is_empty() {
        sizes_and_limit(&sized, &mut lines);
    }
    // Item 127: the window by `merge_at` at or after `--since`'s start time.
    let window: Vec<&MergedPr> = match since {
        None => prs.iter().collect(),
        Some((_, start)) => prs.iter().filter(|p| p.merge_at.zip(start).is_some_and(|(m, t)| m >= t as f64)).collect(),
    };
    let words: BTreeSet<&String> = window.iter().flat_map(|p| p.markers.iter().flat_map(|m| m.keys())).collect();
    for word in words {
        for name in ["set", "unset", "none"] {
            let in_group =
                |p: &&MergedPr| group_of(p.markers.as_ref().and_then(|m| m.get(word)).map(String::as_str)) == name;
            let of_group: Vec<&MergedPr> = window.iter().copied().filter(in_group).collect();
            let mut line = group(&of_group);
            line["kind"] = "marker".into();
            line["marker"] = word.as_str().into();
            line["group"] = name.into();
            line["since"] = since.map(|(value, _)| value).into();
            lines.push(line);
        }
    }
    lines
}

/// Item 120's week numbers over a group: merged and reviewed PRs, the rates,
/// and those reviewed with 3 or more rounds.
fn group(prs: &[&MergedPr]) -> Value {
    let mut line = rates(prs);
    let reviewed = prs.iter().filter(|p| p.rounds > 0).count();
    let three = prs.iter().filter(|p| p.rounds >= 3).count();
    line["merged_prs"] = prs.len().into();
    line["three_rounds"] = three.into();
    line["three_rounds_share"] = share(three, reviewed).into();
    line
}

/// The eight size buckets and the limit, over the measured merged PRs.
fn sizes_and_limit(sized: &[(u64, &MergedPr)], lines: &mut Vec<Value>) {
    for (from, to) in BUCKETS {
        let held = |n: u64| (n > from || (from == 0 && n == 0)) && to.is_none_or(|to| n <= to);
        let of_bucket: Vec<&MergedPr> = sized.iter().filter(|(n, _)| held(*n)).map(|(_, p)| *p).collect();
        let mut line = rates(&of_bucket);
        line["kind"] = "size_bucket".into();
        line["from"] = from.into();
        line["to"] = to.into();
        line["merged_prs"] = of_bucket.len().into();
        lines.push(line);
    }
    lines.push(limit(sized));
}

/// The reviewed PRs of a group, the share approved on round 1 and the change
/// requests per reviewed PR.
fn rates(prs: &[&MergedPr]) -> Value {
    let reviewed: Vec<&&MergedPr> = prs.iter().filter(|p| p.rounds > 0).collect();
    let approved = reviewed.iter().filter(|p| p.first_approved == Some(true)).count();
    let changes: usize = reviewed.iter().map(|p| p.changes).sum();
    json!({
        "reviewed_prs": reviewed.len(), "round1_approved_share": share(approved, reviewed.len()),
        "changes_requested_per_pr": share(changes, reviewed.len()),
    })
}

fn share(part: usize, whole: usize) -> Option<Value> {
    (whole > 0).then(|| num(part as f64 / whole as f64))
}

/// The suggested limit over the reviewed measured merged PRs: the largest
/// supported edge that qualifies, the default when none is supported.
fn limit(sized: &[(u64, &MergedPr)]) -> Value {
    let sample: Vec<(u64, &MergedPr)> = sized.iter().filter(|(_, p)| p.rounds > 0).copied().collect();
    let (mut supported, mut best, mut before) = (false, None, 0);
    for edge in EDGES {
        let up_to: Vec<&MergedPr> = sample.iter().filter(|(n, _)| *n <= edge).map(|(_, p)| *p).collect();
        let own = sample.iter().any(|(n, _)| *n <= edge && (*n > before || edge == EDGES[0]));
        before = edge;
        if up_to.len() < MINIMUM || !own {
            continue;
        }
        supported = true;
        let changes: usize = up_to.iter().map(|p| p.changes).sum();
        let approved = up_to.iter().filter(|p| p.first_approved == Some(true)).count();
        if changes < up_to.len() && 2 * approved >= up_to.len() {
            best = Some(edge);
        }
    }
    let (limit, basis) = match (supported, best) {
        (false, _) => (Some(DEFAULT_LIMIT), "default"),
        (true, Some(edge)) => (Some(edge), "data"),
        (true, None) => (None, "none"),
    };
    json!({
        "kind": "limit", "sample": sample.len(), "minimum": MINIMUM, "default": DEFAULT_LIMIT,
        "limit": limit, "basis": basis,
    })
}

/// The ISO 8601 week (`YYYY-Www`) of the UTC day of a Unix time; none
/// outside `[0, 10000-01-01T00:00:00Z)`.
pub(super) fn iso_week(t: f64) -> Option<String> {
    if !(0.0..253_402_300_800.0).contains(&t) {
        return None;
    }
    let days = (t / 86_400.0).floor() as i64;
    // The week's Thursday (1970-01-01 was one) names its year.
    let thursday = days - (days + 3).rem_euclid(7) + 3;
    let year: i64 = day(thursday as f64 * 86_400.0).get(..4)?.parse().ok()?;
    let week = (thursday - days_from_civil(year, 1, 1)) / 7 + 1;
    Some(format!("{year:04}-W{week:02}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(v: Value) -> Row {
        v.as_object().cloned().expect("an object")
    }

    #[test]
    fn iso_weeks_take_the_thursday_year() {
        let at = |y, m, d| (days_from_civil(y, m, d) * 86_400) as f64;
        assert_eq!(iso_week(at(2026, 11, 18)).as_deref(), Some("2026-W47"));
        assert_eq!(iso_week(at(2027, 1, 1)).as_deref(), Some("2026-W53"));
        assert_eq!(iso_week(at(2024, 12, 30)).as_deref(), Some("2025-W01"));
        assert_eq!(iso_week(0.0).as_deref(), Some("1970-W01"));
        assert_eq!(iso_week(253_402_300_799.5).as_deref(), Some("9999-W52"));
        assert_eq!(iso_week(-0.5), None);
        assert_eq!(iso_week(253_402_300_800.0), None);
    }

    #[test]
    fn merged_prs_count_rounds_per_pr_and_suggest_a_limit() {
        let mut rows = vec![
            row(json!({"layer": "red", "result": "passed", "lock": "b", "at": 50})),
            row(json!({"layer": "red", "result": "passed", "lock": "a", "at": 100})),
            row(json!({"layer": "red", "result": "passed", "lock": "a", "redo": true, "at": 10})),
            row(json!({"layer": "pr", "pr": 7, "product_lines": 100, "warn_lines": 600})),
            row(json!({"layer": "review", "pr": 7, "result": "refused"})),
            row(json!({"layer": "review", "pr": 7, "result": "passed"})),
            row(json!({"layer": "merge", "result": "passed", "pr": 7, "base": "main", "default_branch": "main",
                "locks": ["a", "b"], "at": 1_000})),
            row(json!({"layer": "merge", "result": "passed", "pr": 9, "base": "main", "default_branch": "main"})),
        ];
        let lines = merged_prs(&rows, &BTreeMap::new(), None);
        assert_eq!(lines[0]["pr"], 7);
        assert_eq!(lines[0]["red_to_merge"], 950);
        assert_eq!((&lines[0]["rounds"], &lines[0]["changes_requested"]), (&json!(2), &json!(1)));
        assert_eq!(lines[0]["first_round_approved"], false);
        assert_eq!((&lines[1]["week"], &lines[1]["product_lines"]), (&Value::Null, &Value::Null));
        assert_eq!(lines[2]["kind"], "week");
        assert_eq!(lines.iter().filter(|l| l["kind"] == "size_bucket").count(), 8);
        assert_eq!((&lines[11]["limit"], &lines[11]["basis"]), (&json!(600), &json!("default")));
        for pr in 10..40 {
            rows.push(row(json!({"layer": "pr", "pr": pr, "product_lines": 150, "warn_lines": 600})));
            rows.push(row(json!({"layer": "review", "pr": pr, "result": "passed"})));
            rows.push(row(json!({"layer": "merge", "result": "passed", "pr": pr, "base": "m", "default_branch": "m"})));
        }
        let limit = merged_prs(&rows, &BTreeMap::new(), None).pop().expect("a limit line");
        assert_eq!((&limit["sample"], &limit["limit"], &limit["basis"]), (&json!(31), &json!(200), &json!("data")));
        assert!(merged_prs(&rows[..6], &BTreeMap::new(), None).is_empty());
    }

    #[test]
    fn red_commit_markers_split_the_review_numbers_by_group() {
        let full = "c".repeat(40);
        let merge = |pr: u64, locks: Value, at: u64| {
            row(json!({"layer": "merge", "result": "passed", "pr": pr, "base": "m", "default_branch": "m",
                "locks": locks, "at": at}))
        };
        let rows = vec![
            row(json!({"layer": "red", "result": "passed", "lock": "late", "at": 20, "commit": "dddd"})),
            row(json!({"layer": "red", "result": "passed", "lock": "early", "at": 10, "commit": full})),
            row(json!({"layer": "red", "result": "passed", "lock": "early", "at": 5, "redo": true, "commit": "e"})),
            row(json!({"layer": "red", "result": "passed", "lock": "short", "at": 5, "commit": "abc1234"})),
            row(json!({"layer": "review", "pr": 1, "result": "refused"})),
            row(json!({"layer": "review", "pr": 1, "result": "refused"})),
            row(json!({"layer": "review", "pr": 1, "result": "passed"})),
            row(json!({"layer": "review", "pr": 2, "result": "passed"})),
            merge(1, json!(["late", "early"]), 100),
            merge(2, json!(["short"]), 200),
            merge(3, json!([]), 300),
        ];
        let parents = red_parents(&rows);
        assert_eq!(parents.into_iter().collect::<Vec<_>>(), vec![(1, ("early".to_string(), full))]);
        let red: BTreeMap<u64, Markers> = [
            (1, markers_of("red\n\nledger cases: 010\r\nledger cases: 0\n order cases: yes\nx cases: y \n")),
            (2, markers_of("order cases: no\nlong cases: 123456789012345678901234567890123")),
        ]
        .into();
        assert_eq!(red[&1], [("ledger".to_string(), "010".to_string())].into());
        let lines = merged_prs(&rows, &red, None);
        assert_eq!(lines[0]["markers"], json!({"ledger": "010"}));
        assert_eq!(lines[2]["markers"], Value::Null);
        let markers: Vec<&Value> = lines.iter().filter(|l| l["kind"] == "marker").collect();
        let groups: Vec<(&Value, &Value, &Value)> =
            markers.iter().map(|l| (&l["marker"], &l["group"], &l["merged_prs"])).collect();
        assert_eq!(groups.len(), 6);
        assert_eq!(groups[0], (&json!("ledger"), &json!("set"), &json!(1)));
        assert_eq!(groups[2], (&json!("ledger"), &json!("none"), &json!(2)));
        assert_eq!(groups[4], (&json!("order"), &json!("unset"), &json!(1)));
        assert_eq!((&markers[0]["three_rounds"], &markers[0]["changes_requested_per_pr"]), (&json!(1), &json!(2)));
        assert_eq!((&markers[1]["round1_approved_share"], &markers[1]["since"]), (&Value::Null, &Value::Null));
        let since = merged_prs(&rows, &red, Some(("v1", Some(150))));
        let windowed: Vec<&Value> = since.iter().filter(|l| l["kind"] == "marker").collect();
        assert_eq!(windowed.iter().map(|l| l["marker"].as_str()).collect::<Vec<_>>(), vec![Some("order"); 3]);
        assert_eq!((&windowed[1]["merged_prs"], &windowed[1]["since"]), (&json!(1), &json!("v1")));
        assert!(merged_prs(&rows, &BTreeMap::new(), None).iter().all(|l| l["kind"] != "marker"));
        let groups_of = ["yes", "1", "010", "no", "0", "00", "Yes", "maybe", "n2"].map(|v| group_of(Some(v)));
        assert_eq!(groups_of, ["set", "set", "set", "unset", "unset", "unset", "none", "none", "none"]);
    }
}
