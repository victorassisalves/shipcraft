//! The unit tests of `report`.

use super::evidence::fix_of_row;
use super::flow::read;
use super::github::{blocking, checks, reviewed_commits};
use super::quality::{reds, review, size};
use super::rows::{median, p90};
use super::selection::{matches, Selection};
use super::text::{day, duration, percent, text, utc};
use super::*;
use crate::config::CONFIG_FILE;
use crate::relatorio_gh::Asker;
use serde_json::{json, Value};
use std::fs;

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
fn readable_text_forms() {
    assert_eq!(utc(100.9), "1970-01-01T00:01:40Z");
    assert_eq!(utc(-1.0), "1969-12-31T23:59:59Z");
    for (x, want) in [
        (0.0, "0 s"),
        (59.0, "59 s"),
        (60.0, "1 min 0 s"),
        (3599.0, "59 min 59 s"),
        (3600.0, "1 h 0 min 0 s"),
        (4226.0, "1 h 10 min 26 s"),
        (97_384.0, "27 h 3 min 4 s"),
        (-65.0, "-1 min 5 s"),
        (-0.4, "0 s"),
    ] {
        assert_eq!(duration(x), want);
    }
    assert_eq!(percent(2.0 / 3.0), "67%");
    assert_eq!(percent(0.0), "0%");
}

#[test]
fn release_tag_patterns_match_whole_names() {
    let m = |p: &str, n: &str| matches(p.as_bytes(), n.as_bytes());
    assert!(m("deploy-*", "deploy-20261107-1730"));
    assert!(m("deploy-*", "deploy-"));
    assert!(!m("deploy-*", "deployed/prod"));
    assert!(m("draken-platform-v*", "draken-platform-v0.1.0"));
    assert!(!m("draken-platform-v*", "v1.0.0"));
    assert!(m("v*", "v2.48.0") && m("v*", "v2"));
    assert!(!m("v*", "xv2"));
    assert!(m("rel/*", "rel/a/b"));
    assert!(m("*-prod", "a/b-prod") && !m("*-prod", "a-prod-x"));
    assert!(m("a*b*c", "aXbYbZc") && !m("a*b*c", "aXbYbZ"));
    assert!(m("a**", "a") && m("exact", "exact") && !m("exact", "exact2"));
}

#[test]
fn selection_reads_only_the_report_table_and_never_refuses() {
    let dir = std::env::temp_dir().join(format!("item99-sel-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    let read = |content: Option<&[u8]>| {
        let path = dir.join(CONFIG_FILE);
        let _ = fs::remove_file(&path);
        let _ = fs::remove_dir_all(&path);
        if let Some(bytes) = content {
            fs::write(&path, bytes).unwrap();
        }
        match Selection::read(&dir) {
            Selection::Default(_) => "default".to_string(),
            Selection::Pattern(p, _) => format!("pattern {p}"),
            Selection::Invalid(p) => format!("invalid {p}"),
        }
    };
    assert_eq!(read(None), "default");
    assert_eq!(read(Some(b"this is not toml")), "default");
    assert_eq!(read(Some(b"x = \"\xff\"")), "default");
    assert_eq!(read(Some(b"[[suite]]\nroot = \"a\"\n")), "default");
    assert_eq!(read(Some(b"[report]\n")), "default");
    assert_eq!(read(Some(b"shipcraft_min = \"99\"\n[report]\nrelease_tags = \"deploy-*\"")), "pattern deploy-*");
    assert_eq!(read(Some(b"[report]\nrelease_tag = \"deploy-*\"")), "invalid unknown key release_tag");
    assert_eq!(read(Some(b"report = \"v*\"")), "invalid [report] is not a table");
    fs::remove_file(dir.join(CONFIG_FILE)).unwrap();
    fs::create_dir_all(dir.join(CONFIG_FILE)).unwrap();
    assert!(matches!(Selection::read(&dir), Selection::Default(_)));
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn fixes_release_must_be_a_release_name_of_the_selection() {
    let default = Selection::Default(None);
    assert_eq!(default.release_name_problem("v2.25.0"), None);
    assert_eq!(default.release_name_problem("2.25.0").as_deref(), Some("vX.Y.Z"));
    assert_eq!(default.release_name_problem("deploy-1").as_deref(), Some("vX.Y.Z"));
    let deploy = Selection::Pattern("deploy-*".into(), None);
    assert_eq!(deploy.release_name_problem("deploy-20261112-200036"), None);
    assert_eq!(deploy.release_name_problem("v1.0.0").as_deref(), Some("deploy-*"));
    assert_eq!(deploy.release_name_problem("deployed/prod").as_deref(), Some("deploy-*"));
    let v = Selection::Pattern("v*".into(), None);
    assert_eq!(v.release_name_problem("v1.0.0"), None);
    assert_eq!(v.release_name_problem("v2"), None);
    let invalid = Selection::Invalid("unknown key release_tag".into());
    for tag in ["v1.0.0", "deploy-1"] {
        assert_eq!(
            invalid.release_name_problem(tag).as_deref(),
            Some("invalid: [report] in .shipcraft.toml is invalid: unknown key release_tag")
        );
    }
}

#[test]
fn a_red_row_fixes_release_is_read_when_a_tag_name() {
    let row = |release: Value| -> Row {
        json!({"kind": "fix", "reported_at": null, "fixes_release": release}).as_object().unwrap().clone()
    };
    for (value, read) in [
        (json!(null), None),
        (json!("v1.0.0"), Some("v1.0.0")),
        (json!("deploy-20261112-200036"), Some("deploy-20261112-200036")),
        (json!("packages/api/v1.0.0"), Some("packages/api/v1.0.0")),
        (json!("a..b"), None),
        (json!("a b"), None),
        (json!(""), None),
        (json!(1), None),
    ] {
        assert_eq!(fix_of_row(&row(value.clone())).fixes_release.as_deref(), read, "{value}");
    }
}

#[test]
fn size_counts_each_pr_by_its_last_measured_row_before_its_merge() {
    let rows = |log: &str| read(log.as_bytes()).0;
    let pr = |n: u64, lines: u64, limit: u64| {
        format!(
            "{{\"layer\":\"pr\",\"result\":\"refused\",\"pr\":{n},\"product_lines\":{lines},\"warn_lines\":{limit}}}\n"
        )
    };
    let merge = |n: u64, base: &str| {
        format!("{{\"layer\":\"merge\",\"result\":\"passed\",\"pr\":{n},\"base\":\"{base}\",\"default_branch\":\"main\"}}\n")
    };
    // No measured row: no line. Each of these is skipped, never a gap.
    for row in [
        r#"{"layer":"pr","pr":1,"product_lines":400.0,"warn_lines":500}"#,
        r#"{"layer":"pr","pr":1,"product_lines":4e2,"warn_lines":500}"#,
        r#"{"layer":"pr","pr":1,"product_lines":"400","warn_lines":500}"#,
        r#"{"layer":"pr","pr":1,"product_lines":400,"warn_lines":-1}"#,
        r#"{"layer":"pr","pr":1,"product_lines":400}"#,
        r#"{"layer":"pr","pr":0,"product_lines":400,"warn_lines":500}"#,
        r#"{"layer":"pr","pr":1.0,"product_lines":400,"warn_lines":500}"#,
        r#"{"layer":"ci","pr":1,"product_lines":400,"warn_lines":500}"#,
        r#"{"layer":"pr","pr":1,"product_lines":400,"warn_lines":500,"escape":true}"#,
    ] {
        assert_eq!(size(&rows(row)), None, "{row}");
    }
    assert_eq!(size(&rows(&(merge(1, "main") + &pr(1, 900, 500)))), None);
    // The last measured row gives the size and the limit; equal is not above.
    let log = pr(1, 900, 500) + &pr(1, 500, 500) + &pr(2, 1, 0) + &pr(3, 0, 0);
    assert_eq!(
        size(&rows(&log)).unwrap().to_string(),
        r#"{"above":1,"above_share":0.3333333333333333,"kind":"size","merged_above":0,"merged_above_share":null,"merged_prs":0,"prs":3}"#
    );
    // Rows after the first counting merge are not measured; a merge into
    // another base, a refused one and an escape do not count.
    let log = pr(1, 600, 500)
        + &merge(1, "main")
        + &pr(1, 10, 500)
        + &pr(2, 10, 500)
        + &merge(2, "release")
        + &pr(2, 700, 500)
        + &pr(3, 800, 500)
        + r#"{"layer":"merge","result":"refused","pr":3,"base":"main","default_branch":"main"}"#
        + "\n"
        + r#"{"layer":"merge","result":"passed","pr":3,"base":"main","default_branch":"main","escape":true}"#
        + "\n"
        + &pr(4, 10, 500)
        + &merge(4, "main");
    let line = size(&rows(&log)).unwrap();
    assert_eq!(
        line,
        json!({"kind": "size", "prs": 4, "above": 3, "above_share": 0.75,
            "merged_prs": 2, "merged_above": 1, "merged_above_share": 0.5})
    );
    assert_eq!(text(&[line]), "size: 4 PR(s) measured, 3 above their limit (75%); merged 2, 1 above (50%)\n");
    let line = size(&rows(&pr(7, 1, 500))).unwrap();
    assert_eq!(line["above_share"].to_string(), "0");
    assert_eq!(text(&[line]), "size: 1 PR(s) measured, 0 above their limit (0%); merged 0, 0 above (-)\n");
}

#[test]
fn reds_count_each_red_row_green_again_by_a_later_green_row_on_its_commit() {
    let rows = |log: &str| read(log.as_bytes()).0;
    let red = |commit: &str, secs: &str, failed: &str| {
        format!("{{\"layer\":\"ci\",\"result\":\"refused\",\"code\":\"suite-red\",\"commit\":{commit},\"secs\":{secs}{failed}}}\n")
    };
    let green = |commit: &str| format!("{{\"layer\":\"ci\",\"result\":\"passed\",\"commit\":{commit},\"secs\":3}}\n");
    // No red row: no line. None of these is a red row, nor a gap.
    for row in [
        String::new(),
        green("\"a\""),
        r#"{"layer":"ci","result":"refused","code":"no-report","commit":"a","secs":5}"#.to_string(),
        r#"{"layer":"ci","result":"refused","code":"case-broke","commit":"a"}"#.to_string(),
        r#"{"layer":"ci","result":"error","code":"suite-red","commit":"a"}"#.to_string(),
        r#"{"layer":"ci","result":"error","code":"timed-out","commit":"a"}"#.to_string(),
        r#"{"layer":"hook","result":"refused","code":"suite-red","commit":"a"}"#.to_string(),
        red("\"\"", "1", ""),
        red("7", "1", ""),
        red("null", "1", ""),
        r#"{"layer":"ci","result":"refused","code":"suite-red"}"#.to_string(),
        r#"{"layer":"ci","result":"refused","code":"suite-red","commit":"a","escape":true}"#.to_string(),
    ] {
        assert_eq!(reds(&rows(&row)), None, "{row}");
    }
    // A red row alone: counted, never green again.
    let line = reds(&rows(&red("\"a\"", "12", ",\"failed\":[\"t1\"]"))).unwrap();
    assert_eq!(
        line.to_string(),
        r#"{"cases":[],"green_again":0,"green_again_secs":0,"green_again_share":0,"kind":"reds","named":0,"suite_red":1}"#
    );
    assert_eq!(
        text(&[line]),
        "reds: 1 suite-red, 0 green again on the same commit (0%), 0 s of CI; cases named in 0: none\n"
    );
    // File order: a green row before the red row, or on another commit, does not count.
    let log = green("\"a\"") + &red("\"a\"", "5", "") + &green("\"b\"");
    assert_eq!(reds(&rows(&log)).unwrap()["green_again"], 0);
    // Two reds, one green: both green again; time summed, fractions kept.
    let log = red("\"a\"", "100.5", ",\"failed\":[]") + &red("\"a\"", "25", "") + &green("\"a\"");
    let line = reds(&rows(&log)).unwrap();
    assert_eq!(
        line,
        json!({"kind": "reds", "suite_red": 2, "green_again": 2, "green_again_share": 1,
            "green_again_secs": 125.5, "named": 1, "cases": []})
    );
    assert_eq!(line["green_again_share"].to_string(), "1");
    assert_eq!(
        text(&[line]),
        "reds: 2 suite-red, 2 green again on the same commit (100%), 2 min 6 s of CI; cases named in 1: none\n"
    );
    // Commits compare byte for byte; branch and lock play no part.
    let log = red("\"a\"", "1", "") + r#"{"layer":"ci","result":"passed","commit":"A","branch":"x","lock":"y"}"# + "\n";
    assert_eq!(reds(&rows(&log)).unwrap()["green_again"], 0);
    // Green rows that did not run the suite do not count; any value but true does.
    for (field, counts) in [
        ("\"docs_only\":true", false),
        ("\"suite_in_checks\":true", false),
        ("\"docs_only\":false", true),
        ("\"docs_only\":\"true\"", true),
        ("\"suite_in_checks\":1", true),
        ("\"suite_in_checks\":null", true),
    ] {
        let log =
            red("\"a\"", "1", "") + &format!("{{\"layer\":\"ci\",\"result\":\"passed\",\"commit\":\"a\",{field}}}\n");
        assert_eq!(reds(&rows(&log)).unwrap()["green_again"], u64::from(counts), "{field}");
    }
    // Other green-row shapes: not ci, not passed, empty or non-string commit.
    for row in [
        r#"{"layer":"hook","result":"passed","commit":"a"}"#,
        r#"{"layer":"ci","result":"error","commit":"a"}"#,
        r#"{"layer":"ci","result":"passed","commit":""}"#,
        r#"{"layer":"ci","result":"passed","commit":["a"]}"#,
        r#"{"layer":"ci","result":"passed","commit":"a","escape":true}"#,
    ] {
        let log = red("\"a\"", "1", "") + row + "\n";
        assert_eq!(reds(&rows(&log)).unwrap()["green_again"], 0, "{row}");
    }
    // Secs that are not a number of 0 or more add 0.
    for secs in ["-3", "\"40\"", "null", "true"] {
        let log = red("\"a\"", secs, "") + &green("\"a\"");
        assert_eq!(reds(&rows(&log)).unwrap()["green_again_secs"].to_string(), "0", "{secs}");
    }
    let log = red("\"a\"", "3725", "") + &green("\"a\"");
    assert!(text(&[reds(&rows(&log)).unwrap()]).contains(", 1 h 2 min 5 s of CI;"));
    // Failed: only an array names; non-strings skipped; a duplicate taken once per row.
    for failed in [",\"failed\":\"t1\"", ",\"failed\":{\"t1\":1}", ",\"failed\":null", ""] {
        let log = red("\"a\"", "1", failed) + &green("\"a\"");
        let line = reds(&rows(&log)).unwrap();
        assert_eq!((line["named"].clone(), line["cases"].clone()), (json!(0), json!([])), "{failed}");
    }
    let log = red("\"a\"", "1", ",\"failed\":[\"t1\",\"t1\",2,null,\"t2\"],\"failed_count\":99") + &green("\"a\"");
    assert_eq!(reds(&rows(&log)).unwrap()["cases"], json!([{"id": "t1", "rows": 1}, {"id": "t2", "rows": 1}]));
    // Top 5 by rows, ties by byte order; only green-again rows give cases.
    let log = red("\"a\"", "1", ",\"failed\":[\"z\",\"b\",\"B\",\"a\"]")
        + &red("\"a\"", "1", ",\"failed\":[\"z\",\"b\",\"c\",\"d\"]")
        + &red("\"a\"", "1", ",\"failed\":[\"z\",\"e\"]")
        + &green("\"a\"")
        + &red("\"a\"", "1", ",\"failed\":[\"z\",\"never\"]")
        + &red("\"c\"", "1", ",\"failed\":[\"never\"]");
    let line = reds(&rows(&log)).unwrap();
    assert_eq!(
        line,
        json!({"kind": "reds", "suite_red": 5, "green_again": 3, "green_again_share": 0.6,
            "green_again_secs": 3, "named": 3, "cases": [
                {"id": "z", "rows": 3}, {"id": "b", "rows": 2}, {"id": "B", "rows": 1},
                {"id": "a", "rows": 1}, {"id": "c", "rows": 1}]})
    );
    assert_eq!(
        text(&[line]),
        "reds: 5 suite-red, 3 green again on the same commit (60%), 3 s of CI; cases named in 3: \"z\" (3), \"b\" (2), \"B\" (1), \"a\" (1), \"c\" (1)\n"
    );
    // Ids in the text are JSON string literals; the JSON holds the id itself.
    let log = red("\"a\"", "1", r#","failed":["t, (1)\n\"x\"\\\u0001\u007f"]"#) + &green("\"a\"");
    let line = reds(&rows(&log)).unwrap();
    assert_eq!(line["cases"][0]["id"], "t, (1)\n\"x\"\\\u{1}\u{7f}");
    assert_eq!(
        text(&[line]),
        "reds: 1 suite-red, 1 green again on the same commit (100%), 1 s of CI; cases named in 1: \"t, (1)\\n\\\"x\\\"\\\\\\u0001\u{7f}\" (1)\n"
    );
    // A third share prints its fraction in JSON and a whole percent in text.
    let log = red("\"a\"", "0.4", "") + &red("\"b\"", "1", "") + &red("\"c\"", "1", "") + &green("\"a\"");
    let line = reds(&rows(&log)).unwrap();
    assert_eq!(line["green_again_share"].to_string(), "0.3333333333333333");
    assert_eq!(line["green_again_secs"].to_string(), "0.4");
    assert_eq!(
        text(&[line]),
        "reds: 3 suite-red, 1 green again on the same commit (33%), 0 s of CI; cases named in 0: none\n"
    );
}

#[test]
fn review_counts_the_round_rows_of_each_pr() {
    let rows = |log: &str| read(log.as_bytes()).0;
    let round = |pr: &str, result: &str| format!("{{\"layer\":\"review\",\"pr\":{pr},\"result\":\"{result}\"}}\n");
    // No round row: no line. None of these is a round row, nor a gap.
    for row in [
        String::new(),
        round("7", "error"),
        round("7", "skipped"),
        r#"{"layer":"review","pr":7,"result":"passed","reused":true}"#.to_string(),
        r#"{"layer":"review","pr":7,"result":"passed","escape":true}"#.to_string(),
        r#"{"layer":"review","result":"passed"}"#.to_string(),
        r#"{"layer":"pr","pr":7,"result":"passed"}"#.to_string(),
        r#"{"layer":"merge","pr":7,"result":"passed"}"#.to_string(),
        r#"{"pr":7,"result":"passed"}"#.to_string(),
        round("0", "passed"),
        round("-1", "passed"),
        round("7.0", "passed"),
        round("7e0", "passed"),
        round("\"7\"", "passed"),
        round("true", "passed"),
        round("null", "passed"),
        round("[7]", "passed"),
        round("18446744073709551616", "passed"),
    ] {
        assert_eq!(review(&rows(&row)), None, "{row}");
        assert!(read(row.as_bytes()).1.is_empty(), "{row}");
    }
    // Any `reused` but true is a fresh round; one round is no second round.
    for reused in ["", ",\"reused\":false", ",\"reused\":\"true\"", ",\"reused\":1", ",\"reused\":null"] {
        let log = format!("{{\"layer\":\"review\",\"pr\":7,\"result\":\"refused\"{reused}}}\n");
        let line = review(&rows(&log)).unwrap();
        assert_eq!(
            line.to_string(),
            r#"{"changes_requested":1,"kind":"review","most":[],"prs":1,"rounds":1,"second_round":0,"second_round_share":0}"#,
            "{reused}"
        );
        assert_eq!(
            text(&[line]),
            "review: 1 PR(s) reviewed in 1 round(s), 1 requested changes; 0 needed a second round (0%): none\n"
        );
    }
    // Rows anywhere in the file; errors and reused verdicts between them add nothing.
    let log = round("12", "refused")
        + &round("9", "refused")
        + &round("12", "error")
        + r#"{"layer":"review","pr":12,"result":"passed","reused":true}"#
        + "\n"
        + &round("12", "refused")
        + &round("3", "passed")
        + &round("9", "passed")
        + &round("12", "passed")
        + &round("4", "passed");
    let line = review(&rows(&log)).unwrap();
    assert_eq!(
        line,
        json!({"kind": "review", "prs": 4, "rounds": 7, "changes_requested": 3, "second_round": 2,
            "second_round_share": 0.5, "most": [{"pr": 12, "rounds": 3}, {"pr": 9, "rounds": 2}]})
    );
    assert_eq!(
        text(&[line]),
        "review: 4 PR(s) reviewed in 7 round(s), 3 requested changes; 2 needed a second round (50%): #12 (3), #9 (2)\n"
    );
    // Ties by PR number as numbers; at most 5 listed; the share a whole 1.
    let mut log = String::new();
    for pr in ["100", "20", "3", "20", "100", "3", "7", "7", "50", "50", "8", "8", "8"] {
        log += &round(pr, "passed");
    }
    let line = review(&rows(&log)).unwrap();
    assert_eq!(
        line,
        json!({"kind": "review", "prs": 6, "rounds": 13, "changes_requested": 0, "second_round": 6,
            "second_round_share": 1, "most": [{"pr": 8, "rounds": 3}, {"pr": 3, "rounds": 2},
            {"pr": 7, "rounds": 2}, {"pr": 20, "rounds": 2}, {"pr": 50, "rounds": 2}]})
    );
    assert_eq!(line["second_round_share"].to_string(), "1");
    assert_eq!(
        text(&[line]),
        "review: 6 PR(s) reviewed in 13 round(s), 0 requested changes; 6 needed a second round (100%): #8 (3), #3 (2), #7 (2), #20 (2), #50 (2)\n"
    );
    // A third share prints its fraction in JSON and a whole percent in text.
    let log = round("1", "passed") + &round("1", "passed") + &round("2", "passed") + &round("3", "passed");
    let line = review(&rows(&log)).unwrap();
    assert_eq!(line["second_round_share"].to_string(), "0.3333333333333333");
    assert!(text(&[line]).ends_with("1 needed a second round (33%): #1 (2)\n"));
}

#[test]
fn blocking_groups_reviewed_commits_and_ranks_prs() {
    let rows = |log: &str| read(log.as_bytes()).0;
    let sha = |c: char| c.to_string().repeat(40);
    let path = |c: &str| format!("repos/{{owner}}/{{repo}}/commits/{c}/statuses?per_page=100");
    let round = |pr: u64, commit: &str| format!("{{\"layer\":\"review\",\"pr\":{pr},\"result\":\"passed\"{commit}}}\n");
    let at = |c: char| format!(",\"commit\":\"{}\"", sha(c));
    let count = |n: u64| {
        json!([[{"context": "shipcraft/review", "created_at": "2026-01-01T00:00:00Z",
            "description": format!("on this machine: APPROVE, Blocking {n} (a)")}]])
    };
    let (a, b, c, d, e, f, g) = (sha('a'), sha('b'), sha('c'), sha('d'), sha('e'), sha('f'), sha('1'));
    let (pa, pb, pc, pd, pe, pf, pg) = (path(&a), path(&b), path(&c), path(&d), path(&e), path(&f), path(&g));
    fn ask<'p>(
        p: &'p str,
        outcome: std::result::Result<Value, &'static str>,
    ) -> (Vec<&'p str>, std::result::Result<Value, &'static str>) {
        (vec!["api", "--paginate", "--slurp", p], outcome)
    }
    // Two rounds on one commit are one reviewed commit; one commit under two PRs is two.
    let log = round(12, &at('a'))
        + &round(12, &at('a'))
        + &round(12, &at('b'))
        + &round(9, &at('a'))
        + &round(9, "")
        + &round(9, ",\"commit\":null")
        + &round(9, ",\"commit\":1")
        + &round(9, ",\"commit\":1.0")
        + &round(9, &at('a').to_uppercase().replace("COMMIT", "commit"))
        + &round(9, ",\"commit\":\"abc\"")
        + &round(3, &at('c'))
        + &round(4, &at('d'))
        + &round(5, &at('e'))
        + &round(6, &at('f'))
        + &round(7, &at('1'));
    let rows = rows(&log);
    assert_eq!(reviewed_commits(&rows).len(), 14);
    let mut asker = Asker::answered(
        vec![
            ask(&pa, Ok(count(2))),
            ask(&pb, Ok(count(1))),
            ask(&pc, Ok(count(3))),
            ask(&pd, Ok(count(3))),
            ask(&pe, Ok(json!([[]]))),
            ask(&pf, Err("gh failed")),
            ask(&pg, Ok(count(1))),
        ],
        false,
    );
    let mut line = review(&rows).unwrap();
    let plain = text(&[line.clone()]);
    blocking(&mut asker, &rows, &mut line);
    assert_eq!(line["blocking"], 12);
    assert_eq!(line["blocking_read"], 6);
    assert_eq!(line["blocking_commits"], 14);
    assert_eq!(
        line["blocking_missing"],
        json!({"gh failed": 1, "no blocking count at commit": 1, "no commit in the run log": 6})
    );
    assert_eq!(
        line["blocking_most"],
        json!([{"pr": 3, "blocking": 3}, {"pr": 4, "blocking": 3}, {"pr": 12, "blocking": 3},
            {"pr": 9, "blocking": 2}, {"pr": 7, "blocking": 1}])
    );
    assert_eq!(
        text(&[line]),
        plain.trim_end().to_string()
            + "; Blocking 12 in 6 of 14 reviewed commit(s): #3 (3), #4 (3), #12 (3), #9 (2), #7 (1); \
               not read: gh failed 1, no blocking count at commit 1, no commit in the run log 6\n"
    );
    // Everything read: no `not read`; nothing above 0: `none`.
    let rows = read(round(7, &at('a')).as_bytes()).0;
    let mut asker = Asker::answered(vec![ask(&pa, Ok(count(0)))], false);
    let mut line = review(&rows).unwrap();
    blocking(&mut asker, &rows, &mut line);
    assert_eq!(line["blocking_missing"], json!({}));
    assert!(text(&[line]).ends_with("(0%): none; Blocking 0 in 1 of 1 reviewed commit(s): none\n"));
    // After a timeout, every commit counts as timed out, but one with no commit.
    let rows = read((round(7, &at('a')) + &round(8, "")).as_bytes()).0;
    let mut asker = Asker::answered(vec![ask(&pa, Ok(count(4)))], true);
    let mut line = review(&rows).unwrap();
    blocking(&mut asker, &rows, &mut line);
    assert_eq!(line["blocking_missing"], json!({"gh timed out": 1, "no commit in the run log": 1}));
    assert_eq!(line["blocking"], 0);
    assert_eq!(line["blocking_most"], json!([]));
}

#[test]
fn checks_read_each_reviewed_pr_in_full_and_sum_per_name() {
    let names: &[&str] = &["acceptance", "a;b: c"];
    let sha = |c: char| c.to_string().repeat(40);
    let commits = |pr: u64| format!("repos/{{owner}}/{{repo}}/pulls/{pr}/commits?per_page=100");
    let runs = |c: char| format!("repos/{{owner}}/{{repo}}/commits/{}/check-runs?filter=all&per_page=100", sha(c));
    let round = |pr: u64| format!("{{\"layer\":\"review\",\"pr\":{pr},\"result\":\"refused\"}}\n");
    let run = |name: &str, conclusion: &str, s: u32| {
        json!({"name": name, "status": "completed", "conclusion": conclusion,
            "completed_at": format!("2026-01-01T00:00:{s:02}Z")})
    };
    let at = |runs: Vec<Value>| json!([{"total_count": runs.len(), "check_runs": runs}]);
    let list = |cs: &[char]| json!([cs.iter().map(|c| json!({"sha": sha(*c)})).collect::<Vec<_>>()]);
    fn ask<'p>(
        p: &'p str,
        outcome: std::result::Result<Value, &'static str>,
    ) -> (Vec<&'p str>, std::result::Result<Value, &'static str>) {
        (vec!["api", "--paginate", "--slurp", p], outcome)
    }
    let (c3, c9, c4, c8) = (commits(3), commits(9), commits(4), commits(8));
    let (ra, rb, rc) = (runs('a'), runs('b'), runs('c'));
    // PR 9 shares commit b with PR 3; PR 4 fails; PR 8 is unreadable; PR 3 again is one PR.
    let rows = read((round(9) + &round(3) + &round(9) + &round(4) + &round(8)).as_bytes()).0;
    let answers = || {
        vec![
            ask(&c9, Ok(list(&['a', 'b']))),
            ask(&c3, Ok(list(&['b', 'c']))),
            ask(&c4, Err("gh failed")),
            ask(&c8, Ok(json!([]))),
            ask(&ra, Ok(at(vec![run("acceptance", "failure", 1), run("acceptance", "success", 2)]))),
            ask(&rb, Ok(at(vec![run("a;b: c", "failure", 3), run("acceptance", "success", 3)]))),
            ask(&rc, Ok(at(vec![run("a;b: c", "success", 4)]))),
        ]
    };
    let mut asker = Asker::answered(answers(), false).configured(Some(names));
    let line = checks(&mut asker, &rows).unwrap();
    assert_eq!(
        line,
        json!({"kind": "checks", "prs": 4, "prs_read": 2,
            "missing": {"gh failed": 1, "unreadable answer from gh": 1},
            "names": [
                {"name": "acceptance", "runs": 4, "red": 1, "green_again": 1, "new_commit": 0, "still_red": 0},
                {"name": "a;b: c", "runs": 3, "red": 2, "green_again": 0, "new_commit": 1, "still_red": 1}]})
    );
    assert_eq!(
        text(&[line]),
        "checks: 2 of 4 reviewed PR(s) read; \"acceptance\": 1 red in 4 run(s), 1 green again on the same commit, \
         0 fixed by a new commit, 0 still red; \"a;b: c\": 2 red in 3 run(s), 0 green again on the same commit, \
         1 fixed by a new commit, 1 still red; not read: gh failed 1, unreadable answer from gh 1\n"
    );
    // A timeout: every PR counts as timed out, also one whose answers are in hand.
    let mut asker = Asker::answered(answers(), true).configured(Some(names));
    let line = checks(&mut asker, &rows).unwrap();
    assert_eq!(line["missing"], json!({"gh timed out": 4}));
    assert_eq!(
        line["names"][1],
        json!({"name": "a;b: c", "runs": 0, "red": 0, "green_again": 0, "new_commit": 0, "still_red": 0})
    );
    // Every PR read: no `not read`.
    let rows9 = read(round(9).as_bytes()).0;
    let mut asker = Asker::answered(answers(), false).configured(Some(&["acceptance"]));
    assert_eq!(
        text(&[checks(&mut asker, &rows9).unwrap()]),
        "checks: 1 of 1 reviewed PR(s) read; \"acceptance\": 1 red in 3 run(s), 1 green again on the same commit, \
         0 fixed by a new commit, 0 still red\n"
    );
    // No reviewed PR, no readable config, or no name: no object and no call.
    for (rows, config) in [
        (read(b"{\"layer\":\"review\",\"result\":\"passed\"}").0, Some(names)),
        (rows9.clone(), None),
        (rows9, Some(&[][..])),
    ] {
        let mut asker = Asker::answered(vec![], false).configured(config);
        assert_eq!(checks(&mut asker, &rows), None);
    }
}

#[test]
fn reader_strips_bom_and_cr_and_counts_physical_lines() {
    let (rows, gaps) = read("\u{feff}{\"at\":1}\r\n\r\n[]\r\n{\"at\":2,\"escape\":true}\n{bad".as_bytes());
    assert_eq!(rows.len(), 1);
    assert_eq!(gaps.iter().map(|g| g.0).collect::<Vec<_>>(), vec![3, 5]);
}
