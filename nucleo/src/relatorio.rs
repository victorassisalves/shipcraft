//! Item 38: `shipcraft report [--json]`, the flow measured from the run log
//! alone: no git history, no network, no agent. It finds `.git` by walking up
//! from the current directory, so it runs no git command, and it never refuses.

use crate::refusal::Result;
use serde_json::{json, Map, Value};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

type Row = Map<String, Value>;

pub fn run(as_json: bool) -> Result<()> {
    let bytes = log_path().and_then(|p| fs::read(p).ok()).unwrap_or_default();
    let (rows, gaps) = read(&bytes);
    let report = Report::of(&rows);
    let gaps: Vec<Value> =
        gaps.into_iter().map(|(line, reason)| json!({"kind": "gap", "line": line, "reason": reason})).collect();
    let lines: Vec<Value> =
        [report.meta.clone()].into_iter().chain(report.locks.clone()).chain(report.days.clone()).chain(gaps).collect();
    if as_json {
        for line in &lines {
            println!("{line}");
        }
    } else {
        print!("{}", text(&lines));
    }
    Ok(())
}

/// `<common git dir>/shipcraft/runs.jsonl`, the one `medicao` writes, found
/// without git: a `.git` directory, or a `.git` file (`gitdir: <dir>`) whose
/// `commondir` points at the main repository's.
fn log_path() -> Option<PathBuf> {
    let cwd = std::env::current_dir().ok()?;
    let dot = cwd.ancestors().map(|d| d.join(".git")).find(|p| p.exists())?;
    let git_dir = if dot.is_dir() {
        dot
    } else {
        let content = fs::read_to_string(&dot).ok()?;
        let dir = Path::new(content.trim().strip_prefix("gitdir:")?.trim());
        dot.parent()?.join(dir)
    };
    let common = match fs::read_to_string(git_dir.join("commondir")) {
        Ok(rel) => git_dir.join(rel.trim()),
        Err(_) => git_dir,
    };
    Some(common.join("shipcraft").join("runs.jsonl"))
}

/// The rows, without blank lines and escapes, and the lines that do not read
/// (physical line number, reason). A BOM at the start and a trailing CR go.
fn read(bytes: &[u8]) -> (Vec<Row>, Vec<(usize, String)>) {
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

struct Report {
    meta: Value,
    locks: Vec<Value>,
    days: Vec<Value>,
}

/// What a lock's row needs for the day summary.
struct Merged {
    day: String,
    red_to_merge: Option<f64>,
    waiting: Option<f64>,
    first_approved: Option<bool>,
}

impl Report {
    fn of(rows: &[Row]) -> Report {
        let ats: Vec<f64> = rows.iter().filter_map(at).collect();
        let bound = |pick: fn(f64, f64) -> f64| ats.iter().copied().reduce(pick).map(num);
        let all = |layer: &str| rows.iter().filter(|r| str_of(r, "layer") == layer).collect::<Vec<_>>();
        let meta = json!({
            "kind": "meta", "first_at": bound(f64::min), "last_at": bound(f64::max),
            "hook": stats(&all("hook")), "ci": stats(&all("ci")),
        });
        let mut ids: Vec<String> = Vec::new();
        for id in rows.iter().flat_map(locks_of) {
            if !ids.contains(&id) {
                ids.push(id);
            }
        }
        let mut merged = Vec::new();
        let locks = ids
            .iter()
            .map(|id| {
                let mine: Vec<&Row> = rows.iter().filter(|r| locks_of(r).contains(id)).collect();
                let (row, m) = lock_row(id, &mine);
                merged.extend(m);
                row
            })
            .collect();
        let mut by_day: BTreeMap<String, Vec<Merged>> = BTreeMap::new();
        for m in merged {
            by_day.entry(m.day.clone()).or_default().push(m);
        }
        let days = by_day
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
            .collect();
        Report { meta, locks, days }
    }
}

fn lock_row(id: &str, rows: &[&Row]) -> (Value, Option<Merged>) {
    let passed = |layer: &str| first(rows.iter().copied().filter(|r| str_of(r, "layer") == layer && is(r, "passed")));
    let red = passed("red");
    let close = passed("close");
    // A merge counts only into the default branch.
    let merge = first(rows.iter().copied().filter(|r| {
        str_of(r, "layer") == "merge"
            && is(r, "passed")
            && r.get("base")
                .and_then(Value::as_str)
                .is_some_and(|b| r.get("default_branch").and_then(Value::as_str) == Some(b))
    }));
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
        "first_review_approved": first_approved, "refusals": refusals, "errors": errors,
        "hook": of("hook"), "ci": of("ci"),
    });
    let merged = merge.map(|m| Merged { day: day(m), red_to_merge: span(red, merge), waiting, first_approved });
    (row, merged)
}

/// The locks a row is about: its `lock` and its `locks`.
fn locks_of(row: &Row) -> Vec<String> {
    let mut ids: Vec<String> = Vec::new();
    let single = row.get("lock").and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string);
    let many = row.get("locks").and_then(Value::as_array).into_iter().flatten().filter_map(Value::as_str);
    for id in single.into_iter().chain(many.filter(|s| !s.is_empty()).map(str::to_string)) {
        if !ids.contains(&id) {
            ids.push(id);
        }
    }
    ids
}

fn at(row: &Row) -> Option<f64> {
    row.get("at").and_then(Value::as_f64)
}

fn str_of<'a>(row: &'a Row, key: &str) -> &'a str {
    row.get(key).and_then(Value::as_str).unwrap_or_default()
}

fn is(row: &Row, result: &str) -> bool {
    str_of(row, "result") == result
}

/// The row with the earliest `at`; equal times keep file order.
fn first_row<'a>(rows: impl Iterator<Item = &'a Row>) -> Option<&'a Row> {
    rows.filter(|r| at(r).is_some()).fold(None, |best: Option<&Row>, r| match best {
        Some(b) if at(b) <= at(r) => Some(b),
        _ => Some(r),
    })
}

fn first<'a>(rows: impl Iterator<Item = &'a Row>) -> Option<f64> {
    first_row(rows).and_then(at)
}

/// Count, p50, p90 of `secs`, and refusals by code.
fn stats(rows: &[&Row]) -> Value {
    let secs: Vec<f64> = rows.iter().filter_map(|r| r.get("secs").and_then(Value::as_f64)).collect();
    let mut refusals = BTreeMap::new();
    for r in rows.iter().filter(|r| is(r, "refused")) {
        *refusals.entry(str_of(r, "code").to_string()).or_insert(0u64) += 1;
    }
    json!({"count": rows.len(), "p50": median(secs.clone()), "p90": p90(secs), "refusals": refusals})
}

/// The median: the mean of the two middle values for an even count.
fn median(mut values: Vec<f64>) -> Option<Value> {
    if values.is_empty() {
        return None;
    }
    values.sort_by(f64::total_cmp);
    let n = values.len();
    Some(num(if n % 2 == 1 { values[n / 2] } else { (values[n / 2 - 1] + values[n / 2]) / 2.0 }))
}

/// Nearest rank: the ceil(0.9 n)-th smallest.
fn p90(mut values: Vec<f64>) -> Option<Value> {
    if values.is_empty() {
        return None;
    }
    values.sort_by(f64::total_cmp);
    let rank = (9 * values.len()).div_ceil(10);
    Some(num(values[rank - 1]))
}

/// A whole number prints as an integer.
fn num(x: f64) -> Value {
    if x.fract() == 0.0 && x.abs() < 9e15 {
        json!(x as i64)
    } else {
        json!(x)
    }
}

/// The UTC day (YYYY-MM-DD) of a Unix time.
fn day(t: f64) -> String {
    let days = (t / 86_400.0).floor() as i64;
    // Howard Hinnant's civil_from_days.
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!("{y:04}-{m:02}-{d:02}")
}

fn text(lines: &[Value]) -> String {
    let show = |v: &Value| if v.is_null() { "-".to_string() } else { v.to_string() };
    let secs = |v: &Value| if v.is_null() { "-".to_string() } else { format!("{v} s") };
    let stat = |s: &Value| {
        format!("{} (p50 {}, p90 {}, refusals {})", s["count"], secs(&s["p50"]), secs(&s["p90"]), s["refusals"])
    };
    let mut out = String::new();
    for line in lines {
        match line["kind"].as_str().unwrap_or_default() {
            "meta" if line["first_at"].is_null() => {
                out += "shipcraft report: runs recorded on this machine only (local run log): no rows yet.\n";
            }
            "meta" => {
                out += &format!(
                    "shipcraft report: runs recorded on this machine only (local run log), first row at {}, last row at {} (Unix seconds); reviews or CI that ran elsewhere are not counted.\n",
                    line["first_at"], line["last_at"]
                );
                out += &format!("totals: hook {}; ci {}\n", stat(&line["hook"]), stat(&line["ci"]));
            }
            "lock" => {
                let unobserved = line["unobserved"]
                    .as_array()
                    .map(|u| u.iter().filter_map(Value::as_str).collect::<Vec<_>>().join(", "));
                out += &format!(
                    "lock {}: {}; red at {}, close at {}, merge at {}; red to close {}, close to merge {}, red to merge {}; waiting {}; reviews passed {}, refused {}, error {}, first approved {}; refusals {}, errors {}; hook {}; ci {}{}\n",
                    line["lock"].as_str().unwrap_or_default(),
                    line["state"].as_str().unwrap_or_default(),
                    show(&line["red_at"]), show(&line["close_at"]), show(&line["merge_at"]),
                    secs(&line["red_to_close"]), secs(&line["close_to_merge"]), secs(&line["red_to_merge"]),
                    secs(&line["waiting"]),
                    line["reviews"]["passed"], line["reviews"]["refused"], line["reviews"]["error"],
                    show(&line["first_review_approved"]), line["refusals"], line["errors"],
                    stat(&line["hook"]), stat(&line["ci"]),
                    match unobserved.as_deref() {
                        Some("") | None => String::new(),
                        Some(steps) => format!("; not observed here: {steps}"),
                    }
                );
            }
            "day" => {
                out += &format!(
                    "day {}: {} merged lock(s); median red to merge {}, median waiting {}, approved on first review {}\n",
                    line["day"].as_str().unwrap_or_default(),
                    line["merged_locks"],
                    secs(&line["red_to_merge_median"]),
                    secs(&line["waiting_median"]),
                    show(&line["first_review_approved_share"])
                );
            }
            _ => {
                out += &format!(
                    "gap: line {} does not read ({})\n",
                    line["line"],
                    line["reason"].as_str().unwrap_or_default()
                )
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn percentiles_follow_the_fixed_readings() {
        let ten: Vec<f64> = (1..=10).map(f64::from).collect();
        assert_eq!(median(ten.clone()), Some(json!(5.5)));
        assert_eq!(p90(ten), Some(json!(9)));
        assert_eq!(median(vec![]), None);
    }

    #[test]
    fn utc_day_boundaries() {
        assert_eq!(day(86_399.0), "1970-01-01");
        assert_eq!(day(86_400.0), "1970-01-02");
        assert_eq!(day(1_792_972_800.0), "2026-10-26");
    }

    #[test]
    fn reader_strips_bom_and_cr_and_counts_physical_lines() {
        let (rows, gaps) = read("\u{feff}{\"at\":1}\r\n\r\n[]\r\n{\"at\":2,\"escape\":true}\n{bad".as_bytes());
        assert_eq!(rows.len(), 1);
        assert_eq!(gaps.iter().map(|g| g.0).collect::<Vec<_>>(), vec![3, 5]);
    }
}
