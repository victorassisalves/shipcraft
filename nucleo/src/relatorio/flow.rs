//! The run log and the lock and day lines (items 38, 46).

use super::evidence::{fix_of_row, red_row, Facts};
use super::rows::{at, first, first_row, is, locks_of, median, num, stats, str_of};
use super::text::day;
use super::Row;
use serde_json::{json, Value};
use std::collections::BTreeMap;

/// The rows, without blank lines and escapes, and the lines that do not read
/// (physical line number, reason). A BOM at the start and a trailing CR go.
pub(super) fn read(bytes: &[u8]) -> (Vec<Row>, Vec<(usize, String)>) {
    let text = String::from_utf8_lossy(bytes);
    let text = text.strip_prefix('\u{feff}').unwrap_or(&text);
    let (mut rows, mut gaps) = (Vec::new(), Vec::new());
    for (i, line) in text.split('\n').enumerate() {
        let line = line.strip_suffix('\r').unwrap_or(line);
        if line.trim().is_empty() {
            continue;
        }
        match serde_json::from_str::<Value>(line) {
            Ok(Value::Object(row)) if row.get("escape") == Some(&Value::Bool(true)) => {}
            Ok(Value::Object(row)) => rows.push(row),
            Ok(_) => gaps.push((i + 1, "not a JSON object".to_string())),
            Err(e) => gaps.push((i + 1, format!("not JSON: {e}"))),
        }
    }
    (rows, gaps)
}

pub(super) struct Report {
    pub(super) meta: Value,
    pub(super) locks: Vec<Value>,
    /// Per lock row, what the day rows need when it merged.
    pub(super) merged: Vec<Option<Merged>>,
}

/// What a lock's row needs for the day summary.
pub(super) struct Merged {
    day: String,
    red_to_merge: Option<f64>,
    pub(super) waiting: Option<f64>,
    first_approved: Option<bool>,
}

impl Report {
    pub(super) fn of(rows: &[Row], ids: &[String], facts: Option<&Facts>) -> Report {
        let ats: Vec<f64> = rows.iter().filter_map(at).collect();
        let bound = |pick: fn(f64, f64) -> f64| ats.iter().copied().reduce(pick).map(num);
        let all = |layer: &str| rows.iter().filter(|r| str_of(r, "layer") == layer).collect::<Vec<_>>();
        let meta = json!({
            "kind": "meta", "first_at": bound(f64::min), "last_at": bound(f64::max),
            "hook": stats(&all("hook")), "ci": stats(&all("ci")),
        });
        // Item 76: then the lock files at the default branch's tip the log does not name.
        let mut all: Vec<String> = ids.to_vec();
        if let Some(facts) = facts {
            all.extend(facts.tip.iter().filter(|id| !ids.contains(id)).cloned());
        }
        let mut merged = Vec::new();
        let locks: Vec<Value> = all
            .iter()
            .map(|id| {
                let mine: Vec<&Row> = rows.iter().filter(|r| locks_of(r).contains(id)).collect();
                let (mut row, m) = lock_row(id, &mine);
                // Item 76, point 2: the fix data's last source is the earliest passed
                // non-redo `red` row, which needs no git; only git-derived values
                // go null when git evidence is unavailable.
                let fix = match facts {
                    Some(f) => f.fix.get(id).cloned().unwrap_or_default(),
                    None => red_row(rows, id).map(fix_of_row).unwrap_or_default(),
                };
                if m.is_none() && facts.is_some_and(|f| f.tip.contains(id)) {
                    row["state"] = "merge_not_observed".into();
                }
                row["change_kind"] = fix.kind.into();
                row["reported_at"] = fix.reported_at.into();
                row["fixes_release"] = fix.fixes_release.into();
                merged.push(m);
                row
            })
            .collect();
        Report { meta, locks, merged }
    }

    pub(super) fn days(&self) -> Vec<Value> {
        let mut by_day: BTreeMap<String, Vec<&Merged>> = BTreeMap::new();
        for m in self.merged.iter().flatten() {
            by_day.entry(m.day.clone()).or_default().push(m);
        }
        by_day
            .into_iter()
            .map(|(day, ms)| {
                let reviewed: Vec<bool> = ms.iter().filter_map(|m| m.first_approved).collect();
                let share = (!reviewed.is_empty())
                    .then(|| reviewed.iter().filter(|a| **a).count() as f64 / reviewed.len() as f64);
                json!({
                    "kind": "day", "day": day, "merged_locks": ms.len(),
                    "red_to_merge_median": median(ms.iter().filter_map(|m| m.red_to_merge).collect()),
                    "waiting_median": median(ms.iter().filter_map(|m| m.waiting).collect()),
                    "first_review_approved_share": share.map(num),
                })
            })
            .collect()
    }
}

fn lock_row(id: &str, rows: &[&Row]) -> (Value, Option<Merged>) {
    // Item 46: a redo is not the RED that opened the cycle; `redos` counts them.
    let redo = |r: &Row| r.get("redo") == Some(&Value::Bool(true));
    let passed = |layer: &str| {
        first(rows.iter().copied().filter(|r| str_of(r, "layer") == layer && is(r, "passed") && !redo(r)))
    };
    let redos = rows.iter().filter(|r| str_of(r, "layer") == "red" && is(r, "passed") && redo(r)).count();
    let red = passed("red");
    let close = passed("close");
    let merge = merge_row(rows).and_then(at);
    let span = |a: Option<f64>, b: Option<f64>| a.zip(b).map(|(a, b)| b - a);
    let waiting = merge.and_then(|m| {
        let ci = rows.iter().filter(|r| str_of(r, "layer") == "ci" && is(r, "passed")).filter_map(|r| at(r));
        ci.filter(|t| *t <= m).reduce(f64::max).map(|t| m - t)
    });
    let reviews: Vec<&Row> = rows
        .iter()
        .copied()
        .filter(|r| str_of(r, "layer") == "review" && r.get("reused") != Some(&Value::Bool(true)))
        .collect();
    let count = |result: &str| reviews.iter().filter(|r| is(r, result)).count();
    let first_approved =
        first_row(reviews.iter().copied().filter(|r| is(r, "passed") || is(r, "refused"))).map(|r| is(r, "passed"));
    let mut refusals = BTreeMap::new();
    for r in rows.iter().filter(|r| is(r, "refused")) {
        *refusals.entry(str_of(r, "code").to_string()).or_insert(0u64) += 1;
    }
    let errors = rows.iter().filter(|r| is(r, "error")).count();
    let unobserved: Vec<&str> =
        [("red", red), ("close", close)].iter().filter(|(_, t)| t.is_none()).map(|(s, _)| *s).collect();
    let of = |layer: &str| stats(&rows.iter().copied().filter(|r| str_of(r, "layer") == layer).collect::<Vec<_>>());
    let row = json!({
        "kind": "lock", "lock": id, "state": if merge.is_some() { "merged" } else { "open" },
        "red_at": red.map(num), "close_at": close.map(num), "merge_at": merge.map(num),
        "red_to_close": span(red, close).map(num), "close_to_merge": span(close, merge).map(num),
        "red_to_merge": span(red, merge).map(num), "waiting": waiting.map(num), "unobserved": unobserved,
        "reviews": {"passed": count("passed"), "refused": count("refused"), "error": count("error")},
        "first_review_approved": first_approved, "redos": redos, "refusals": refusals, "errors": errors,
        "hook": of("hook"), "ci": of("ci"),
    });
    let merged = merge.map(|m| Merged { day: day(m), red_to_merge: span(red, merge), waiting, first_approved });
    (row, merged)
}

/// The earliest passed `merge` row; a merge counts only into the default branch.
pub(super) fn merge_row<'a>(rows: &[&'a Row]) -> Option<&'a Row> {
    first_row(rows.iter().copied().filter(|r| merge_counts(r)))
}

/// A `merge` row that counts: passed, into the default branch.
pub(super) fn merge_counts(row: &Row) -> bool {
    str_of(row, "layer") == "merge"
        && is(row, "passed")
        && row
            .get("base")
            .and_then(Value::as_str)
            .is_some_and(|b| row.get("default_branch").and_then(Value::as_str) == Some(b))
}
