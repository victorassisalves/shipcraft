//! The unit tests of `report --github`'s readers.

use super::answers::time;
use super::blocking::{blocking_count, latest_count};
use super::checks::{pr_commits, suite_runs, tally};
use super::Asker;
use serde_json::{json, Value};

fn sha(c: char) -> String {
    c.to_string().repeat(40)
}

#[test]
fn pr_commits_are_distinct_shas_in_answer_order() {
    let entry = |c: char| json!({"sha": sha(c), "commit": {}});
    let answer = json!([[entry('b'), entry('a')], [], [entry('b'), entry('c')]]);
    assert_eq!(pr_commits(&answer), Some(vec![sha('b'), sha('a'), sha('c')]));
    assert_eq!(pr_commits(&json!([[]])), Some(vec![]));
    for bad in [
        json!([]),
        json!({}),
        json!([{}]),
        json!([[1]]),
        json!([[{}]]),
        json!([[{"sha": 1}]]),
        json!([[{"sha": "abc"}]]),
        json!([[{"sha": sha('A')}]]),
        json!([[{"sha": sha('g')}]]),
        json!([[entry('a')], [{"sha": null}]]),
    ] {
        assert_eq!(pr_commits(&bad), None, "{bad}");
    }
}

fn run(name: &str, status: &str, conclusion: Value, at: &str) -> Value {
    json!({"name": name, "status": status, "conclusion": conclusion, "completed_at": at})
}

fn page(total: usize, runs: Vec<Value>) -> Value {
    json!({"total_count": total, "check_runs": runs})
}

#[test]
fn suite_runs_read_completed_runs_of_the_names() {
    let names = vec!["a b".to_string(), "c/β".to_string()];
    let t = "2026-01-01T00:00:00Z";
    let answer = json!([
        page(
            5,
            vec![
                run("a b", "completed", json!("failure"), t),
                run("other", "completed", json!("success"), "not a time"),
                run("c/β", "in_progress", Value::Null, "x"),
            ]
        ),
        page(5, vec![run("c/β", "completed", json!("cancelled"), t), run("A B", "completed", json!("success"), t)]),
    ]);
    let runs = suite_runs(&answer, &names).unwrap();
    assert_eq!(runs.iter().map(|r| r.name).collect::<Vec<_>>(), [0, 1]);
    for bad in [
        json!([]),
        json!([page(2, vec![run("a b", "completed", json!("success"), t)])]),
        json!([page(1, vec![run("a b", "completed", json!("success"), "2026-01-01 00:00:00")])]),
        json!([page(1, vec![json!({"name": "a b", "status": "completed", "conclusion": "success"})])]),
        json!([page(1, vec![json!({"name": "other", "status": "completed"})])]),
        json!([page(1, vec![json!({"name": "other", "status": 1, "conclusion": null})])]),
        json!([page(1, vec![run("a b", "completed", Value::Null, t)]), page(0, vec![])]),
    ] {
        assert!(suite_runs(&bad, &names).is_none(), "{bad}");
    }
}

#[test]
fn each_red_run_is_green_again_fixed_by_a_new_commit_or_still_red() {
    let names = vec!["n".to_string(), "m".to_string()];
    let at = |s: u32| format!("2026-01-01T00:00:{s:02}Z");
    let at_commit = |runs: Vec<Value>| suite_runs(&json!([page(runs.len(), runs)]), &names).unwrap();
    let r = |name: &str, c: &str, s: u32| run(name, "completed", json!(c), &at(s));
    let commits = vec![
        // Two reds before one green: both green again; an equal-time green is not later.
        at_commit(vec![r("n", "failure", 1), r("n", "timed_out", 2), r("n", "success", 3), r("m", "failure", 5)]),
        at_commit(vec![r("m", "success", 5), r("n", "failure", 6), r("m", "skipped", 1)]),
        // Fixed by a later commit, whatever its later runs say; an earlier commit fixes nothing.
        at_commit(vec![r("n", "success", 7), r("n", "failure", 8), r("m", "failure", 9)]),
        at_commit(vec![r("m", "neutral", 10)]),
    ];
    assert_eq!(tally(&commits, 2), vec![[6, 4, 2, 1, 1], [5, 2, 0, 0, 2]]);
    assert_eq!(tally(&[], 2), vec![[0; 5]; 2]);
}

#[test]
fn a_pr_is_read_in_full_or_gives_its_one_reason() {
    let names = vec!["n".to_string()];
    let commits = "repos/{owner}/{repo}/pulls/5/commits?per_page=100";
    let runs = |c: char| format!("repos/{{owner}}/{{repo}}/commits/{}/check-runs?filter=all&per_page=100", sha(c));
    let (ra, rb) = (runs('a'), runs('b'));
    let list = json!([[{"sha": sha('a')}, {"sha": sha('b')}, {"sha": sha('a')}]]);
    let red = json!([page(1, vec![run("n", "completed", json!("failure"), "2026-01-01T00:00:00Z")])]);
    let green = json!([page(1, vec![run("n", "completed", json!("success"), "2026-01-01T00:00:01Z")])]);
    fn ask<'p>(p: &'p str, o: Result<Value, &'static str>) -> (Vec<&'p str>, Result<Value, &'static str>) {
        (vec!["api", "--paginate", "--slurp", p], o)
    }
    let answered = |b: Result<Value, &'static str>, timed_out| {
        Asker::answered(vec![ask(commits, Ok(list.clone())), ask(&ra, Ok(red.clone())), ask(&rb, b)], timed_out)
    };
    assert_eq!(answered(Ok(green.clone()), false).pr_checks(5, &names), Ok(vec![[2, 1, 0, 1, 0]]));
    assert_eq!(answered(Err("gh failed"), false).pr_checks(5, &names), Err("gh failed".to_string()));
    assert_eq!(answered(Ok(json!([[]])), false).pr_checks(5, &names), Err("unreadable answer from gh".to_string()));
    assert_eq!(answered(Ok(green), true).pr_checks(5, &names), Err("gh timed out".to_string()));
}

#[test]
fn blocking_counts_follow_the_grammar() {
    for (description, count) in [
        ("on this machine: APPROVE, Blocking 0 (claude)", Some(0)),
        ("on this machine: CHANGES REQUESTED, Blocking 3 (claude)", Some(3)),
        ("on this machine: CHANGES REQUESTED, Blocking 007", Some(7)),
        ("on this machine: APPROVE, Blocking 999999999 x", Some(999_999_999)),
        ("on this machine: APPROVE, Blocking 1234567890", None),
        ("on this machine: APPROVE, Blocking ", None),
        ("on this machine: APPROVE, Blocking -1", None),
        ("on this machine: APPROVE, Blocking 1x", None),
        ("on this machine: APPROVE, Blocking 1(claude)", None),
        ("on this machine: APPROVE, Blocking 1\t", None),
        ("on this machine: APPROVE, Blocking ٣", None),
        ("on this machine: APPROVE, blocking 1", None),
        ("on this machine: approve, Blocking 1", None),
        (" on this machine: APPROVE, Blocking 1", None),
        ("on this machine: review in progress (claude)", None),
        ("verdict from abc reused (same file versions)", None),
        ("off in .shipcraft.toml", None),
    ] {
        assert_eq!(blocking_count(description), count, "{description}");
    }
}

#[test]
fn the_latest_count_wins_ties_to_the_first() {
    let status = |d: Value, at: &str| json!({"context": "shipcraft/review", "description": d, "created_at": at});
    let approve = |n: u32| json!(format!("on this machine: APPROVE, Blocking {n} (a)"));
    // Newest by time, whatever the order; a later status without a count is skipped.
    let answer = json!([
        [status(approve(1), "2026-01-01T00:00:00Z"), status(approve(4), "2026-01-03T00:00:00Z")],
        [],
        [status(json!("review error"), "2026-01-09T00:00:00Z"), status(Value::Null, "2026-01-09T00:00:00Z")],
        [{"context": "other", "description": 5}, status(approve(2), "2026-01-02T00:00:00Z")]
    ]);
    assert_eq!(latest_count(&answer), Ok(4));
    // Equal times: the first in answer order.
    let answer = json!([[status(approve(6), "2026-01-01T00:00:00Z")], [status(approve(9), "2026-01-01T00:00:00Z")]]);
    assert_eq!(latest_count(&answer), Ok(6));
    for none in [json!([[]]), json!([[{"context": "x"}], [status(json!("review error"), "2026-01-01T00:00:00Z")]])] {
        assert_eq!(latest_count(&none), Err("no blocking count at commit"), "{none}");
    }
    for bad in [
        json!([]),
        json!({}),
        json!([{}]),
        json!([[1]]),
        json!([[{"context": 1}]]),
        json!([[{"state": "success"}]]),
        json!([[status(approve(1), "2026-01-01T00:00:00Z")], [{"context": null}]]),
        json!([[{"context": "shipcraft/review", "created_at": "2026-01-01T00:00:00Z"}]]),
        json!([[status(json!(1), "2026-01-01T00:00:00Z")]]),
        json!([[status(approve(1), "2026-01-01 00:00:00")]]),
        json!([[{"context": "shipcraft/review", "description": null}]]),
    ] {
        assert_eq!(latest_count(&bad), Err("unreadable answer from gh"), "{bad}");
    }
}

#[test]
fn times_are_github_utc_real_dates() {
    assert_eq!(time("1970-01-01T00:00:00Z"), Some(0));
    assert_eq!(time("2023-11-14T22:13:20Z"), Some(1_700_000_000));
    assert!(time("2000-02-29T23:59:59Z").is_some());
    assert!(time("0001-01-01T00:00:00Z").is_some());
    assert!(time("9999-12-31T23:59:59Z").is_some());
    for bad in [
        "1900-02-29T00:00:00Z",
        "0000-01-01T00:00:00Z",
        "2023-04-31T00:00:00Z",
        "2023-01-01T24:00:00Z",
        "2023-01-01T00:00:00.0Z",
        "2023-01-01t00:00:00z",
        "+023-01-01T00:00:00Z",
        "２０２３-01-01T00:00:00Z",
    ] {
        assert_eq!(time(bad), None, "{bad}");
    }
}
