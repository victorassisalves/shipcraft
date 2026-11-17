//! The DORA line (item 76).

use super::evidence::{red_row, unix_time, Evidence, Facts, FixData, Release};
use super::rows::{at, median, num, p90};
use super::Row;
use serde_json::{json, Value};
use std::collections::BTreeSet;

/// One DORA metric.
fn metric(value: Option<Value>, n: usize, missing: usize, why: impl FnOnce() -> String) -> Value {
    let value = value.filter(|_| n > 0);
    let reason = (value.is_none() || missing > 0).then(why);
    json!({"value": value, "n": n, "missing": missing, "reason": reason})
}

pub(super) fn dora(
    rows: &[Row],
    evidence: std::result::Result<(&Evidence, &Facts), &String>,
    since: Option<&str>,
    release_tags: Option<&str>,
) -> Value {
    const KEYS: [&str; 5] = ["deploys", "lead_time", "rework_rate", "time_to_recover", "change_failure_rate"];
    let (ev, facts) = match evidence {
        Ok(found) => found,
        Err(reason) => {
            let mut out = json!({
                "kind": "dora",
                "git": {"default_branch": null, "releases": null, "release_tags": release_tags, "reason": reason},
                "since": since,
            });
            for key in KEYS {
                out[key] = json!({"value": null, "n": 0, "missing": 0, "reason": reason});
            }
            return out;
        }
    };
    let start = since.and_then(|tag| ev.releases.iter().find(|r| r.name == tag)).map(|r| r.time);
    let read: Vec<usize> = (0..ev.releases.len()).filter(|i| start.is_none_or(|t| ev.releases[*i].time >= t)).collect();
    let names: BTreeSet<&str> = ev.releases.iter().map(|r| r.name.as_str()).collect();
    let read_names: BTreeSet<&str> = read.iter().map(|i| ev.releases[*i].name.as_str()).collect();
    // The shipped locks: those whose release is read.
    let shipped: Vec<(&String, &Release, &FixData)> = facts
        .release
        .iter()
        .filter(|(_, i)| read.contains(i))
        .map(|(id, i)| (id, &ev.releases[*i], &facts.fix[id]))
        .collect();
    let times: Vec<i64> = read.iter().map(|i| ev.releases[*i].time).collect();
    let deploys = {
        let (first, last) = (times.iter().min().copied(), times.iter().max().copied());
        let value = first.zip(last).map(|(first, last)| {
            let span = (last - first) as f64 / 86_400.0;
            let per_day = (times.len() >= 2 && span > 0.0).then(|| num(times.len() as f64 / span));
            json!({"count": times.len(), "first": first, "last": last, "per_day": per_day})
        });
        metric(value, times.len(), 0, || "no release read".to_string())
    };
    let lead_time = {
        let (mut samples, mut missing) = (Vec::new(), 0);
        for (id, release, _) in &shipped {
            match red_row(rows, id).and_then(at) {
                Some(red) if release.time as f64 > red => samples.push(release.time as f64 - red),
                _ => missing += 1,
            }
        }
        let n = samples.len();
        let value = (n > 0).then(|| json!({"median": median(samples.clone()), "p90": p90(samples)}));
        metric(value, n, missing, || {
            if missing > 0 {
                format!("{missing} shipped lock(s) without a passed red row in this run log, or released before it")
            } else {
                "no shipped lock in the releases read".to_string()
            }
        })
    };
    let unknown = shipped.iter().filter(|(_, _, f)| f.kind.is_none()).count();
    let rework_rate = {
        let shipping: BTreeSet<&str> = shipped.iter().map(|(_, r, _)| r.name.as_str()).collect();
        let fixing: BTreeSet<&str> = shipped
            .iter()
            .filter(|(_, _, f)| f.kind.as_deref() == Some("fix"))
            .map(|(_, r, _)| r.name.as_str())
            .collect();
        let n = shipping.len();
        let value = (unknown == 0 && n > 0).then(|| num(fixing.len() as f64 / n as f64));
        metric(value, n, unknown, || {
            if unknown > 0 {
                format!("{unknown} shipped lock(s) with an unknown change_kind")
            } else {
                "no release read ships a lock".to_string()
            }
        })
    };
    let fixes: Vec<&(&String, &Release, &FixData)> =
        shipped.iter().filter(|(_, _, f)| f.kind.as_deref() == Some("fix")).collect();
    let time_to_recover = {
        let (mut samples, mut missing) = (Vec::new(), 0);
        for (_, release, f) in &fixes {
            match f.reported_at.as_deref().and_then(unix_time) {
                Some(reported) if release.time > reported => samples.push((release.time - reported) as f64),
                _ => missing += 1,
            }
        }
        let n = samples.len();
        let value = (n > 0).then(|| json!({"median": median(samples.clone()), "p90": p90(samples)}));
        metric(value, n, missing, || {
            if missing > 0 {
                format!("{missing} shipped fix lock(s) without reported_at, or released before it")
            } else {
                "no shipped fix lock with reported_at".to_string()
            }
        })
    };
    let change_failure_rate = {
        let unlinked =
            fixes.iter().filter(|(_, _, f)| f.fixes_release.as_deref().is_none_or(|t| !names.contains(t))).count();
        let missing = unknown + unlinked;
        let failed: BTreeSet<&str> = fixes
            .iter()
            .filter_map(|(_, _, f)| f.fixes_release.as_deref())
            .filter(|t| read_names.contains(t))
            .collect();
        let n = read.len();
        let value = (missing == 0 && n > 0).then(|| num(failed.len() as f64 / n as f64));
        metric(value, n, missing, || {
            if missing > 0 {
                format!("{missing} shipped lock(s) with an unknown change_kind, or fix lock(s) naming no release")
            } else {
                "no release read".to_string()
            }
        })
    };
    json!({
        "kind": "dora",
        "git": {"default_branch": ev.branch, "releases": ev.releases.len(), "release_tags": release_tags, "reason": null},
        "since": since,
        "deploys": deploys, "lead_time": lead_time, "rework_rate": rework_rate,
        "time_to_recover": time_to_recover, "change_failure_rate": change_failure_rate,
    })
}
