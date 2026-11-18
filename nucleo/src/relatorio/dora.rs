//! The DORA line (item 76); item 124's merge mode.

use super::evidence::{red_row, unix_time, Evidence, Facts, FixData, Release};
use super::rows::{at, median, num, p90};
use super::Row;
use crate::config::Deploy;
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
    deploy: Option<Deploy>,
) -> Value {
    const KEYS: [&str; 5] = ["deploys", "lead_time", "rework_rate", "time_to_recover", "change_failure_rate"];
    let (ev, facts) = match evidence {
        Ok(found) => found,
        Err(reason) => {
            let mut out = json!({
                "kind": "dora",
                "git": {
                    "default_branch": null, "deploy": deploy.map(Deploy::as_str),
                    "deploy_source": deploy.map(|_| "config"), "merges": null,
                    "releases": null, "release_tags": release_tags, "reason": reason,
                },
                "since": since,
            });
            for key in KEYS {
                out[key] = json!({"value": null, "n": 0, "missing": 0, "reason": reason});
            }
            return out;
        }
    };
    // Item 124: merges in place of releases in merge mode, and its words.
    let merge = ev.merges.is_some();
    let deployed = ev.deploys();
    let (one, many, done) = if merge { ("merge", "merges", "merged") } else { ("release", "releases", "released") };
    let start = since.and_then(|tag| ev.releases.iter().find(|r| r.name == tag)).map(|r| r.time);
    // Item 125: else a merge id starts the window at its merge, by line order.
    let from = match (start, ev.merges.as_deref(), since) {
        (None, Some(merges), Some(value)) => merge_named(merges, value).unwrap_or(0),
        _ => 0,
    };
    let read: Vec<usize> = (from..deployed.len()).filter(|i| start.is_none_or(|t| deployed[*i].time >= t)).collect();
    let names: BTreeSet<&str> = deployed.iter().map(|r| r.name.as_str()).collect();
    let read_names: BTreeSet<&str> = read.iter().map(|i| deployed[*i].name.as_str()).collect();
    // The shipped locks: those whose release is read.
    let shipped: Vec<(&String, &Release, &FixData)> = facts
        .release
        .iter()
        .filter(|(_, i)| read.contains(i))
        .map(|(id, i)| (id, &deployed[*i], &facts.fix[id]))
        .collect();
    let times: Vec<i64> = read.iter().map(|i| deployed[*i].time).collect();
    let deploys = {
        let (first, last) = (times.iter().min().copied(), times.iter().max().copied());
        let value = first.zip(last).map(|(first, last)| {
            let span = (last - first) as f64 / 86_400.0;
            let per_day = (times.len() >= 2 && span > 0.0).then(|| num(times.len() as f64 / span));
            json!({"count": times.len(), "first": first, "last": last, "per_day": per_day})
        });
        metric(value, times.len(), 0, || format!("no {one} read"))
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
                format!("{missing} shipped lock(s) without a passed red row in this run log, or {done} before it")
            } else {
                format!("no shipped lock in the {many} read")
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
                format!("no {one} read ships a lock")
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
                format!("{missing} shipped fix lock(s) without reported_at, or {done} before it")
            } else {
                "no shipped fix lock with reported_at".to_string()
            }
        })
    };
    let change_failure_rate = {
        // The deploy each shipped fix names: item 76's `fixes_release`, or in
        // merge mode the merge live at its `reported_at` (item 124).
        let named: Vec<Option<&str>> = fixes
            .iter()
            .map(|(id, _, f)| match merge {
                true => live_merge(deployed, facts.release[*id], f).map(|i| deployed[i].name.as_str()),
                false => f.fixes_release.as_deref().filter(|t| names.contains(t)),
            })
            .collect();
        let missing = unknown + named.iter().filter(|n| n.is_none()).count();
        let failed: BTreeSet<&str> = named.into_iter().flatten().filter(|t| read_names.contains(t)).collect();
        let n = read.len();
        let value = (missing == 0 && n > 0).then(|| num(failed.len() as f64 / n as f64));
        metric(value, n, missing, || {
            if missing > 0 {
                match merge {
                    true => format!("{missing} shipped lock(s) with an unknown change_kind, or fix lock(s) with no merge before their reported_at"),
                    false => format!("{missing} shipped lock(s) with an unknown change_kind, or fix lock(s) naming no release"),
                }
            } else {
                format!("no {one} read")
            }
        })
    };
    json!({
        "kind": "dora",
        "git": {
            "default_branch": ev.branch, "deploy": ev.deploy.0.as_str(), "deploy_source": ev.deploy.1,
            "merges": ev.merges.as_ref().map(Vec::len),
            "releases": ev.releases.len(), "release_tags": release_tags, "reason": null,
        },
        "since": since,
        "deploys": deploys, "lead_time": lead_time, "rework_rate": rework_rate,
        "time_to_recover": time_to_recover, "change_failure_rate": change_failure_rate,
    })
}

/// Item 124: the merge a fix shipped by merge `own` names, the latest in line
/// order before `own` whose time is at or before its `reported_at`.
fn live_merge(merges: &[Release], own: usize, fix: &FixData) -> Option<usize> {
    let reported = fix.reported_at.as_deref().and_then(unix_time)?;
    (0..own).rev().find(|i| merges[*i].time <= reported)
}

/// Item 125: 7 to 64 lowercase hex digits.
pub(super) fn merge_id(value: &str) -> bool {
    (7..=64).contains(&value.len()) && value.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

/// Item 125: the one merge whose full id a merge id prefixes, else None.
pub(super) fn merge_named(merges: &[Release], value: &str) -> Option<usize> {
    if !merge_id(value) {
        return None;
    }
    let mut hits = merges.iter().enumerate().filter(|(_, m)| m.commit.starts_with(value)).map(|(i, _)| i);
    match (hits.next(), hits.next()) {
        (Some(i), None) => Some(i),
        _ => None,
    }
}

/// Item 125: in merge mode with `change_failure_rate`'s `missing` above 0,
/// the merge after the latest missing merge on the whole line: one shipping
/// a lock with an unknown `change_kind`, or a fix naming no merge.
pub(super) fn fill_line(ev: &Evidence, facts: &Facts, dora: &Value) -> Option<String> {
    let merges = ev.merges.as_deref()?;
    if dora["change_failure_rate"]["missing"].as_u64().unwrap_or(0) == 0 {
        return None;
    }
    let missing = |(id, i): (&String, &usize)| {
        let f = &facts.fix[id];
        let unnamed = f.kind.as_deref() == Some("fix") && live_merge(merges, *i, f).is_none();
        (f.kind.is_none() || unnamed).then_some(*i)
    };
    let last = facts.release.iter().filter_map(missing).max()?;
    let tail = "the last merge that ships a lock counted missing";
    Some(match merges.get(last + 1) {
        Some(next) => format!(
            "to fill rework rate and change failure rate: report --since {} (the first merge after {}, {tail})",
            next.commit, merges[last].commit
        ),
        None => format!("to fill rework rate and change failure rate: no merge after {}, {tail}", merges[last].commit),
    })
}

#[cfg(test)]
mod merge_mode {
    use super::{live_merge, FixData, Release};
    use std::collections::BTreeMap;

    #[test]
    fn a_fix_names_the_merge_live_at_its_report() {
        let merge = |time| Release { name: String::new(), time, commit: String::new(), locks: BTreeMap::new() };
        let merges = [merge(100), merge(200), merge(150), merge(300)];
        let fix = |at: &str| FixData { kind: Some("fix".into()), reported_at: Some(at.into()), fixes_release: None };
        // 1970-01-01T00:02:40Z is 160: the latest merge before the fix's own at or before it.
        assert_eq!(live_merge(&merges, 3, &fix("1970-01-01T00:02:40Z")), Some(2));
        assert_eq!(live_merge(&merges, 3, &fix("1970-01-01T00:03:20Z")), Some(2));
        assert_eq!(live_merge(&merges, 2, &fix("1970-01-01T00:03:20Z")), Some(1));
        assert_eq!(live_merge(&merges, 3, &fix("1970-01-01T00:01:40Z")), Some(0));
        assert_eq!(live_merge(&merges, 3, &fix("1970-01-01T00:01:00Z")), None);
        assert_eq!(live_merge(&merges, 0, &fix("1970-01-01T00:05:00Z")), None);
        assert_eq!(live_merge(&merges, 3, &FixData::default()), None);
    }

    #[test]
    fn a_merge_id_names_one_merge_by_its_prefix() {
        use super::{merge_id, merge_named};
        assert!(merge_id("abcdef0") && merge_id(&"f".repeat(64)));
        assert!(!merge_id("abcdef") && !merge_id(&"f".repeat(65)) && !merge_id("ABCDEF0") && !merge_id("abcdefg"));
        let merge =
            |commit: &str| Release { name: commit.into(), time: 0, commit: commit.into(), locks: BTreeMap::new() };
        let merges = [merge(&format!("aaaaaaa1{}", "0".repeat(32))), merge(&format!("aaaaaaa2{}", "0".repeat(32)))];
        assert_eq!(merge_named(&merges, "aaaaaaa2"), Some(1));
        assert_eq!(merge_named(&merges, "aaaaaaa"), None);
        assert_eq!(merge_named(&merges, "bbbbbbb"), None);
        assert_eq!(merge_named(&merges, &merges[0].commit), Some(0));
    }
}
