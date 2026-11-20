//! The text output.

use serde_json::Value;

/// The UTC day (YYYY-MM-DD) of a Unix time.
pub(super) fn day(t: f64) -> String {
    civil((t / 86_400.0).floor() as i64)
}

/// Item 83: a Unix time as UTC `YYYY-MM-DDTHH:MM:SSZ`, its whole second rounded down.
pub(crate) fn utc(t: f64) -> String {
    let secs = t.floor() as i64;
    let rest = secs.rem_euclid(86_400);
    format!("{}T{:02}:{:02}:{:02}Z", civil(secs.div_euclid(86_400)), rest / 3600, rest % 3600 / 60, rest % 60)
}

/// Item 83: a duration in seconds as `<h> h <m> min <s> s`, rounded to the nearest second.
pub(super) fn duration(x: f64) -> String {
    let total = x.round() as i64;
    let sign = if total < 0 { "-" } else { "" };
    let a = total.unsigned_abs();
    let (h, m, s) = (a / 3600, a % 3600 / 60, a % 60);
    if h > 0 {
        format!("{sign}{h} h {m} min {s} s")
    } else if m > 0 {
        format!("{sign}{m} min {s} s")
    } else {
        format!("{sign}{s} s")
    }
}

/// Item 83: a share as a whole percent.
pub(super) fn percent(x: f64) -> String {
    format!("{}%", (x * 100.0).round() as i64)
}

/// Item 83's text forms of a value; `-` when it is empty (or not a number).
/// Item 136: DORA's per-day rate; null only because the deploys read span
/// more than zero and less than a day says so.
pub(super) fn per_day(v: &Value) -> String {
    let span = v["last"].as_i64().zip(v["first"].as_i64()).map(|(last, first)| last - first);
    match (v["per_day"].as_f64(), span) {
        (Some(x), _) => format!("{x:.2}"),
        (None, Some(span)) if span > 0 && span < 86_400 => "- (first to last under a day)".to_string(),
        _ => "-".to_string(),
    }
}

fn show_with(v: &Value, f: impl Fn(f64) -> String) -> String {
    v.as_f64().map_or_else(|| "-".to_string(), f)
}

/// Howard Hinnant's civil_from_days, as YYYY-MM-DD.
fn civil(days: i64) -> String {
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

pub(super) fn text(lines: &[Value]) -> String {
    let show = |v: &Value| if v.is_null() { "-".to_string() } else { v.to_string() };
    let time = |v: &Value| show_with(v, utc);
    let span = |v: &Value| show_with(v, duration);
    let latency = |v: &Value| show_with(v, |x| format!("{x:.1} s"));
    let stat = |s: &Value| {
        format!("{} (p50 {}, p90 {}, refusals {})", s["count"], latency(&s["p50"]), latency(&s["p90"]), s["refusals"])
    };
    // Item 120: a group's reviewed PRs, as the week and size lines print them.
    let rated = |line: &Value| {
        format!(
            "{} reviewed, approved on round 1 {}, {} change requests per PR",
            line["reviewed_prs"],
            show_with(&line["round1_approved_share"], percent),
            show_with(&line["changes_requested_per_pr"], |x| format!("{x:.2}"))
        )
    };
    let mut out = String::new();
    let mut meta = &Value::Null;
    for line in lines {
        if line["kind"] == "meta" {
            meta = line;
        }
        match line["kind"].as_str().unwrap_or_default() {
            "meta" if line["first_at"].is_null() => {
                out += "shipcraft report: runs recorded on this machine only (local run log): no rows yet.\n";
            }
            "meta" => {
                out += &format!(
                    "shipcraft report: runs recorded on this machine only (local run log), first row at {}, last row at {} (UTC); reviews or CI that ran elsewhere are not counted.\n",
                    time(&line["first_at"]), time(&line["last_at"])
                );
                out += &format!("totals: hook {}; ci {}\n", stat(&line["hook"]), stat(&line["ci"]));
            }
            "lock" => {
                let unobserved = line["unobserved"]
                    .as_array()
                    .map(|u| u.iter().filter_map(Value::as_str).collect::<Vec<_>>().join(", "));
                out += &format!(
                    "lock {}: {}; red at {}, close at {}, merge at {}; red to close {}, close to merge {}, red to merge {}; waiting {}; reviews passed {}, refused {}, error {}, first approved {}; redos {}; refusals {}, errors {}; hook {}; ci {}{}{}\n",
                    line["lock"].as_str().unwrap_or_default(),
                    line["state"].as_str().unwrap_or_default(),
                    time(&line["red_at"]), time(&line["close_at"]), time(&line["merge_at"]),
                    span(&line["red_to_close"]), span(&line["close_to_merge"]), span(&line["red_to_merge"]),
                    span(&line["waiting"]),
                    line["reviews"]["passed"], line["reviews"]["refused"], line["reviews"]["error"],
                    show(&line["first_review_approved"]), line["redos"], line["refusals"], line["errors"],
                    stat(&line["hook"]), stat(&line["ci"]),
                    match unobserved.as_deref() {
                        Some("") | None => String::new(),
                        Some(steps) => format!("; not observed here: {steps}"),
                    },
                    // Item 79: only with `--github`, and only when a field was filled.
                    match line["github"].as_array().map(|g| g.iter().filter_map(Value::as_str).collect::<Vec<_>>()) {
                        Some(names) if !names.is_empty() => format!("; from github: {}", names.join(", ")),
                        _ => String::new(),
                    }
                );
            }
            "day" => {
                out += &format!(
                    "day {}: {} merged lock(s); median red to merge {}, median waiting {}, approved on first review {}\n",
                    line["day"].as_str().unwrap_or_default(),
                    line["merged_locks"],
                    span(&line["red_to_merge_median"]),
                    span(&line["waiting_median"]),
                    show_with(&line["first_review_approved_share"], percent)
                );
            }
            // Item 107: the PRs counted against their size limit.
            "size" => {
                out += &format!(
                    "size: {} PR(s) measured, {} above their limit ({}); merged {}, {} above ({})\n",
                    line["prs"],
                    line["above"],
                    show_with(&line["above_share"], percent),
                    line["merged_prs"],
                    line["merged_above"],
                    show_with(&line["merged_above_share"], percent)
                );
            }
            // Item 109: the suite-red runs that went green on the same commit;
            // item 123: the same per ISO week, `reds <week>:`.
            "reds" | "reds_week" => {
                let label = line["week"].as_str().map_or("reds".to_string(), |week| format!("reds {week}"));
                let cases = line["cases"].as_array().filter(|c| !c.is_empty()).map_or("none".to_string(), |c| {
                    c.iter()
                        .map(|case| {
                            let id = case["id"].as_str().unwrap_or_default();
                            format!("{} ({})", Value::String(id.to_string()), case["rows"])
                        })
                        .collect::<Vec<_>>()
                        .join(", ")
                });
                out += &format!(
                    "{label}: {} suite-red, {} green again on the same commit ({}), {} of CI; cases named in {}: {cases}\n",
                    line["suite_red"],
                    line["green_again"],
                    show_with(&line["green_again_share"], percent),
                    show_with(&line["green_again_secs"], duration),
                    line["named"]
                );
            }
            // Item 112: the review rounds each PR needed.
            "review" => {
                let most = line["most"].as_array().filter(|m| !m.is_empty()).map_or("none".to_string(), |m| {
                    m.iter().map(|e| format!("#{} ({})", e["pr"], e["rounds"])).collect::<Vec<_>>().join(", ")
                });
                out += &format!(
                    "review: {} PR(s) reviewed in {} round(s), {} requested changes; {} needed a second round ({}): {most}",
                    line["prs"],
                    line["rounds"],
                    line["changes_requested"],
                    line["second_round"],
                    show_with(&line["second_round_share"], percent)
                );
                // Item 113: only with `--github`.
                if line.get("blocking").is_some() {
                    let entries = |key: &str, field: &str| {
                        line[key].as_array().filter(|m| !m.is_empty()).map(|m| {
                            m.iter().map(|e| format!("#{} ({})", e["pr"], e[field])).collect::<Vec<_>>().join(", ")
                        })
                    };
                    out += &format!(
                        "; Blocking {} in {} of {} reviewed commit(s): {}",
                        line["blocking"],
                        line["blocking_read"],
                        line["blocking_commits"],
                        entries("blocking_most", "blocking").unwrap_or_else(|| "none".to_string())
                    );
                    if let Some(m) = line["blocking_missing"].as_object().filter(|m| !m.is_empty()) {
                        let reasons = m.iter().map(|(reason, n)| format!("{reason} {n}")).collect::<Vec<_>>();
                        out += &format!("; not read: {}", reasons.join(", "));
                    }
                }
                out += "\n";
            }
            // Item 114: only with `--github`.
            "checks" => {
                out += &format!("checks: {} of {} reviewed PR(s) read", line["prs_read"], line["prs"]);
                for name in line["names"].as_array().into_iter().flatten() {
                    out += &format!(
                        "; {}: {} red in {} run(s), {} green again on the same commit, {} fixed by a new commit, {} still red",
                        Value::String(name["name"].as_str().unwrap_or_default().to_string()),
                        name["red"],
                        name["runs"],
                        name["green_again"],
                        name["new_commit"],
                        name["still_red"]
                    );
                }
                if let Some(m) = line["missing"].as_object().filter(|m| !m.is_empty()) {
                    let reasons = m.iter().map(|(reason, n)| format!("{reason} {n}")).collect::<Vec<_>>();
                    out += &format!("; not read: {}", reasons.join(", "));
                }
                out += "\n";
            }
            // Item 120: each merged PR, by week and by size, and the suggested limit.
            "merged_pr" => {
                let locks = line["locks"]
                    .as_array()
                    .filter(|l| !l.is_empty())
                    .map_or("none".to_string(), |l| l.iter().filter_map(Value::as_str).collect::<Vec<_>>().join(", "));
                let approved = match line["first_round_approved"].as_bool() {
                    Some(true) => "yes",
                    Some(false) => "no",
                    None => "-",
                };
                out += &format!(
                    "pr #{}: merged at {} ({}); locks {locks}; {} product lines; {} review round(s), {} requested changes, approved on round 1 {approved}; red to merge {}\n",
                    line["pr"],
                    time(&line["merge_at"]),
                    line["week"].as_str().unwrap_or("-"),
                    show(&line["product_lines"]),
                    line["rounds"],
                    line["changes_requested"],
                    span(&line["red_to_merge"])
                );
            }
            "week" => {
                out += &format!(
                    "week {}: {} merged PR(s), median red to merge {}; {}, 3 or more rounds {} ({})\n",
                    line["week"].as_str().unwrap_or_default(),
                    line["merged_prs"],
                    span(&line["red_to_merge_median"]),
                    rated(line),
                    line["three_rounds"],
                    show_with(&line["three_rounds_share"], percent)
                );
            }
            "size_bucket" => {
                let to = line["to"].as_u64().map_or("+".to_string(), |to| format!("-{to}"));
                out += &format!("size {}{to}: {} merged PR(s), {}\n", line["from"], line["merged_prs"], rated(line));
            }
            "limit" => {
                let n = &line["sample"];
                out += &match line["basis"].as_str().unwrap_or_default() {
                    "data" => format!(
                        "suggested limit: {} product lines, from {n} reviewed merged PR(s): the largest supported edge (30 or more PRs up to it, one in its interval) whose PRs up to it average under 1 change request each with at least 50% approved on round 1\n",
                        line["limit"]
                    ),
                    "default" => format!(
                        "suggested limit: 600 product lines (the default): {n} reviewed merged PR(s), no supported edge (30 or more PRs up to it, one in its interval)\n"
                    ),
                    _ => format!(
                        "suggested limit: none: at no supported edge (30 or more PRs up to it, one in its interval) do the PRs up to it average under 1 change request each with at least 50% approved on round 1 ({n} reviewed merged PR(s))\n"
                    ),
                };
            }
            // Item 127: item 120's week numbers per marker group.
            "marker" => {
                let since = line["since"].as_str().map_or(String::new(), |s| format!("; since {s}"));
                out += &format!(
                    "marker {} cases {}: {} merged PR(s), {}, 3 or more rounds {} ({}){since}\n",
                    line["marker"].as_str().unwrap_or_default(),
                    line["group"].as_str().unwrap_or_default(),
                    line["merged_prs"],
                    rated(line),
                    line["three_rounds"],
                    show_with(&line["three_rounds_share"], percent)
                );
            }
            "dora" => out += &dora_text(meta, line),
            "github" => {
                let missing = line["missing"].as_object().filter(|m| !m.is_empty()).map_or("none".to_string(), |m| {
                    m.iter().map(|(reason, n)| format!("{reason} {n}")).collect::<Vec<_>>().join(", ")
                });
                out += &format!(
                    "github: selected {}, merge filled {}, waiting filled {}; missing {missing}\n",
                    line["selected"], line["merge_filled"], line["waiting_filled"]
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

/// Item 76: the DORA block, with the same content as the `dora` line.
fn dora_text(meta: &Value, dora: &Value) -> String {
    let time = |v: &Value| show_with(v, utc);
    let span = |v: &Value| show_with(v, duration);
    let share = |v: &Value| show_with(v, percent);
    let mut out = "DORA\n".to_string();
    out += &if meta["first_at"].is_null() {
        "run log: no rows yet; it holds this machine's runs only (local run log).\n".to_string()
    } else {
        format!(
            "run log: first row at {}, last row at {} (UTC); it holds this machine's runs only (local run log).\n",
            time(&meta["first_at"]),
            time(&meta["last_at"])
        )
    };
    let git = &dora["git"];
    let since = dora["since"].as_str().map(|s| format!(", since {s}")).unwrap_or_default();
    // Item 99: the line ends with the release tags read, `vX.Y.Z` without the key.
    let tags = git["release_tags"].as_str().unwrap_or("vX.Y.Z");
    // Item 124: merge mode's coverage line.
    let why = match git["deploy_source"].as_str() {
        Some("config") => "[report] deploy = \"merge\"",
        _ => "no release tag read",
    };
    let merge = git["deploy"] == "merge" && git["default_branch"].is_string();
    out += &match git["default_branch"].as_str() {
        Some(branch) if merge => format!(
            "git: default branch {branch}; {} merge(s){since}; lock rows without log times come from the branch tip; release tags: {tags}; deploys are merges to the default branch ({why})\n",
            dora["deploys"]["n"]
        ),
        Some(branch) => format!(
            "git: default branch {branch}; {} release(s){since}; lock rows without log times come from the branch tip; release tags: {tags}\n",
            // The releases read: all of them, or those at or after `--since` (deploys' `n`).
            dora["deploys"]["n"]
        ),
        None => format!(
            "git: no evidence ({}){since}; lock rows without log times come from the branch tip when git reads; release tags: {tags}\n",
            git["reason"].as_str().unwrap_or_default()
        ),
    };
    let tail = |m: &Value| {
        let reason = m["reason"].as_str().map(|r| format!("; {r}")).unwrap_or_default();
        format!(" (n {}, missing {}{reason})\n", m["n"], m["missing"])
    };
    let spread = |m: &Value| {
        let v = &m["value"];
        if v.is_null() {
            "-".to_string()
        } else {
            format!("median {}, p90 {}", span(&v["median"]), span(&v["p90"]))
        }
    };
    let d = &dora["deploys"];
    let v = &d["value"];
    out += &if v.is_null() {
        format!("deploys: -{}", tail(d))
    } else {
        format!(
            "deploys: {} {}(s), first at {}, last at {}, per day {}{}",
            v["count"],
            if merge { "merge" } else { "release" },
            time(&v["first"]),
            time(&v["last"]),
            per_day(v),
            tail(d)
        )
    };
    out += &format!("lead time: {}{}", spread(&dora["lead_time"]), tail(&dora["lead_time"]));
    out += &format!("rework rate: {}{}", share(&dora["rework_rate"]["value"]), tail(&dora["rework_rate"]));
    out += &format!("time to recover: {}{}", spread(&dora["time_to_recover"]), tail(&dora["time_to_recover"]));
    out += &format!(
        "change failure rate: {}{}",
        share(&dora["change_failure_rate"]["value"]),
        tail(&dora["change_failure_rate"])
    );
    // Item 125: the merge that would fill the two metrics (text only).
    if let Some(fill) = dora["fill"].as_str() {
        out += &format!("{fill}\n");
    }
    out
}
