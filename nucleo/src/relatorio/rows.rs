//! Run-log row readers and the statistics.

use super::Row;
use serde_json::{json, Value};
use std::collections::BTreeMap;

/// The locks a row is about: its `lock` and its `locks`.
pub(super) fn locks_of(row: &Row) -> Vec<String> {
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

pub(super) fn at(row: &Row) -> Option<f64> {
    row.get("at").and_then(Value::as_f64)
}

pub(super) fn str_of<'a>(row: &'a Row, key: &str) -> &'a str {
    row.get(key).and_then(Value::as_str).unwrap_or_default()
}

pub(super) fn is(row: &Row, result: &str) -> bool {
    str_of(row, "result") == result
}

/// The row with the earliest `at`; equal times keep file order.
pub(super) fn first_row<'a>(rows: impl Iterator<Item = &'a Row>) -> Option<&'a Row> {
    rows.filter(|r| at(r).is_some()).fold(None, |best: Option<&Row>, r| match best {
        Some(b) if at(b) <= at(r) => Some(b),
        _ => Some(r),
    })
}

pub(super) fn first<'a>(rows: impl Iterator<Item = &'a Row>) -> Option<f64> {
    first_row(rows).and_then(at)
}

/// Count, p50, p90 of `secs`, and refusals by code.
pub(super) fn stats(rows: &[&Row]) -> Value {
    let secs: Vec<f64> = rows.iter().filter_map(|r| r.get("secs").and_then(Value::as_f64)).collect();
    let mut refusals = BTreeMap::new();
    for r in rows.iter().filter(|r| is(r, "refused")) {
        *refusals.entry(str_of(r, "code").to_string()).or_insert(0u64) += 1;
    }
    json!({"count": rows.len(), "p50": median(secs.clone()), "p90": p90(secs), "refusals": refusals})
}

/// The median: the mean of the two middle values for an even count.
pub(super) fn median(mut values: Vec<f64>) -> Option<Value> {
    if values.is_empty() {
        return None;
    }
    values.sort_by(f64::total_cmp);
    let n = values.len();
    Some(num(if n % 2 == 1 { values[n / 2] } else { (values[n / 2 - 1] + values[n / 2]) / 2.0 }))
}

/// Nearest rank: the ceil(0.9 n)-th smallest.
pub(super) fn p90(mut values: Vec<f64>) -> Option<Value> {
    if values.is_empty() {
        return None;
    }
    values.sort_by(f64::total_cmp);
    let rank = (9 * values.len()).div_ceil(10);
    Some(num(values[rank - 1]))
}

/// A whole number prints as an integer.
pub(crate) fn num(x: f64) -> Value {
    if x.fract() == 0.0 && x.abs() < 9e15 {
        json!(x as i64)
    } else {
        json!(x)
    }
}
