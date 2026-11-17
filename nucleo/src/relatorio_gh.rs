//! Item 79: `report --github`, the selected locks' waiting and merge times
//! asked of GitHub through `gh`. Separate from gh.rs's readers: every call has
//! a 60 s limit in its own process group, its outcome is reused by argument
//! list, and a failure is a `missing` reason, never a refusal nor printed text.

use crate::config::{Config, CONFIG_FILE};
use crate::gh::percent_encode;
use crate::processo::kill_group;
use crate::relatorio::{days_from_civil, num, Git, REPOSITORY_VARS};
use serde_json::{Map, Value};
use std::collections::HashMap;
use std::io::Read;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::mpsc::{channel, TryRecvError};
use std::time::{Duration, Instant};

const LIMIT: Duration = Duration::from_secs(60);
const FAILED: &str = "gh failed";
const UNREADABLE: &str = "unreadable answer from gh";
const TIMED_OUT: &str = "gh timed out";

/// The PR a lock went through, from the run log.
pub enum Pr {
    None,
    Several,
    One(u64),
}

/// A call's outcome: its answer, or the reason it gives.
type Outcome = Result<Value, &'static str>;

pub struct Asker<'a> {
    root: PathBuf,
    /// Item 76's git, the default branch and its commit, when git evidence read.
    git: Option<(&'a Git, &'a str, &'a str)>,
    /// Keyed by the full argument list; a timed-out call is never kept.
    calls: HashMap<Vec<String>, Outcome>,
    timed_out: bool,
    /// `[execution] ci` and `suite_checks`, read once; None when unreadable.
    config: Option<Option<(String, Vec<String>)>>,
}

impl<'a> Asker<'a> {
    pub fn new(root: &Path, git: Option<(&'a Git, &'a str, &'a str)>) -> Asker<'a> {
        Asker { root: root.to_path_buf(), git, calls: HashMap::new(), timed_out: false, config: None }
    }

    /// Point 2's steps for one lock row: fills `merge_at`, `close_to_merge` and
    /// `red_to_merge` of a `merge_not_observed` row (naming each in `filled`),
    /// and gives the waiting, or the one `missing` reason.
    pub fn lock(&mut self, row: &mut Value, pr: Pr, filled: &mut Vec<&str>) -> Result<f64, String> {
        // After a timeout, no lock is finished, even one whose answers are in hand.
        if self.timed_out {
            return Err(TIMED_OUT.to_string());
        }
        let pr = match pr {
            Pr::None => return Err("no pr in the run log".to_string()),
            Pr::Several => return Err("several prs in the run log".to_string()),
            Pr::One(pr) => pr,
        };
        let n = pr.to_string();
        let answer = self.call(&["pr", "view", &n, "--json", "number,state,mergedAt,headRefOid,mergeCommit"])?;
        let view = PrView::read(&answer, pr).ok_or(UNREADABLE)?;
        if view.state != "MERGED" {
            return Err("pr not merged".to_string());
        }
        let merged_at = view.merged_at.and_then(time).ok_or(UNREADABLE)?;
        if !oid(view.head) {
            return Err(UNREADABLE.to_string());
        }
        if row["state"] == "merge_not_observed" {
            let merge = view.merge.filter(|o| oid(o)).ok_or(UNREADABLE)?;
            // Unavailable git evidence leaves no `merge_not_observed` lock.
            let Some((git, branch, tip)) = self.git else { return Err(FAILED.to_string()) };
            if !matches!(git.call(&["merge-base", "--is-ancestor", merge, tip]), Ok((Some(0), _))) {
                return Err(format!("pr not merged into {branch}"));
            }
            let at = merged_at as f64;
            row["merge_at"] = num(at);
            filled.push("merge_at");
            for (field, from) in [("close_to_merge", "close_at"), ("red_to_merge", "red_at")] {
                if let Some(start) = row[from].as_f64() {
                    row[field] = num(at - start);
                    filled.push(field);
                }
            }
        }
        let (ci, checks) = self.config().ok_or("config unreadable")?;
        // Its `shipcraft/ci` status is an administrative success, not a CI run.
        if ci == "off" {
            return Err("ci off".to_string());
        }
        let head = view.head.to_string();
        let mut done = None;
        for name in ["shipcraft/ci".to_string()].iter().chain(&checks) {
            let completion = self.component(&head, name, name != "shipcraft/ci")?;
            done = done.max(Some(completion));
        }
        let merge_at = row["merge_at"].as_f64().ok_or(UNREADABLE)?;
        let waiting = merge_at - done.expect("shipcraft/ci is always a component") as f64;
        if waiting < 0.0 {
            return Err("ci finished after merge".to_string());
        }
        Ok(waiting)
    }

    /// One required component at the head: its completion, or the reason.
    fn component(&mut self, head: &str, name: &str, suite: bool) -> Result<i64, String> {
        let status = self.call(&[
            "api",
            "--paginate",
            "--slurp",
            &format!("repos/{{owner}}/{{repo}}/commits/{head}/status?per_page=100"),
        ])?;
        let statuses = pages(&status, "statuses", |e| {
            e.get("context").is_some_and(Value::is_string) && e.get("state").is_some_and(Value::is_string)
        })
        .ok_or(UNREADABLE)?;
        // (green, completion time) for each match.
        let mut matches: Vec<(bool, &Value)> = statuses
            .iter()
            .filter(|e| e["context"] == name)
            .map(|e| (e["state"] == "success", e.get("created_at").unwrap_or(&Value::Null)))
            .collect();
        let runs;
        if suite {
            let path = format!(
                "repos/{{owner}}/{{repo}}/commits/{head}/check-runs?check_name={}&filter=latest&per_page=100",
                percent_encode(name)
            );
            runs = self.call(&["api", "--paginate", "--slurp", &path])?;
            let runs = pages(&runs, "check_runs", check_run).ok_or(UNREADABLE)?;
            matches.extend(runs.iter().filter(|e| e["name"] == name).map(|e| {
                (
                    e["status"] == "completed" && e["conclusion"] == "success",
                    e.get("completed_at").unwrap_or(&Value::Null),
                )
            }));
        }
        if matches.is_empty() {
            return Err(format!("{name} missing at head"));
        }
        if matches.iter().any(|(green, _)| !green) {
            return Err(format!("{name} not green at head now"));
        }
        let mut latest = None;
        for (_, at) in matches {
            latest = latest.max(Some(at.as_str().and_then(time).ok_or(UNREADABLE)?));
        }
        Ok(latest.expect("a match"))
    }

    /// Tests: an asker whose calls are answered in hand, or timed out.
    #[cfg(test)]
    pub fn answered(answers: Vec<(Vec<&str>, Outcome)>, timed_out: bool) -> Asker<'a> {
        let calls = answers.into_iter().map(|(k, v)| (k.into_iter().map(str::to_string).collect(), v)).collect();
        Asker { root: PathBuf::new(), git: None, calls, timed_out, config: None }
    }

    /// Tests: an asker whose config is already read, as these `suite_checks`
    /// (None: unreadable).
    #[cfg(test)]
    pub fn configured(mut self, checks: Option<&[&str]>) -> Asker<'a> {
        let checks = checks.map(|c| ("github".to_string(), c.iter().map(|n| n.to_string()).collect()));
        self.config = Some(checks);
        self
    }

    /// Item 113: the Blocking count of the latest `shipcraft/review` status
    /// with a count at a reviewed commit (40 lowercase hex), or the reason.
    pub fn blocking(&mut self, commit: &str) -> Result<u64, String> {
        let path = format!("repos/{{owner}}/{{repo}}/commits/{commit}/statuses?per_page=100");
        let answer = self.call(&["api", "--paginate", "--slurp", &path])?;
        latest_count(&answer).map_err(str::to_string)
    }

    /// Item 114: the config's `suite_checks`, through the once-per-run reader;
    /// None when the config is unreadable or names no check.
    pub fn suite_checks(&mut self) -> Option<Vec<String>> {
        self.config().map(|(_, checks)| checks).filter(|checks| !checks.is_empty())
    }

    /// Item 114: one reviewed PR's runs of each name (in `names` order), read
    /// in full from its commits' check runs, or the one reason it is not read.
    pub fn pr_checks(&mut self, pr: u64, names: &[String]) -> Result<Vec<Tally>, String> {
        // After a timeout, no PR is finished, even one whose answers are in hand.
        if self.timed_out {
            return Err(TIMED_OUT.to_string());
        }
        let path = format!("repos/{{owner}}/{{repo}}/pulls/{pr}/commits?per_page=100");
        let answer = self.call(&["api", "--paginate", "--slurp", &path])?;
        let commits = pr_commits(&answer).ok_or(UNREADABLE)?;
        let mut runs = Vec::new();
        for sha in &commits {
            let path = format!("repos/{{owner}}/{{repo}}/commits/{sha}/check-runs?filter=all&per_page=100");
            let answer = self.call(&["api", "--paginate", "--slurp", &path])?;
            runs.push(suite_runs(&answer, names).ok_or(UNREADABLE)?);
        }
        Ok(tally(&runs, names.len()))
    }

    /// `<root>/.shipcraft.toml` read once, directly, by `Config::parse`.
    fn config(&mut self) -> Option<(String, Vec<String>)> {
        if self.config.is_none() {
            let text = std::fs::read(self.root.join(CONFIG_FILE)).ok().and_then(|b| String::from_utf8(b).ok());
            let config = text.and_then(|t| Config::parse(&t).ok());
            self.config = Some(config.map(|c| (c.execucao.ci, c.execucao.suite_checks)));
        }
        self.config.clone().flatten()
    }

    /// `gh <args>`, or the outcome a call with the same arguments had.
    fn call(&mut self, args: &[&str]) -> Result<Value, String> {
        if self.timed_out {
            return Err(TIMED_OUT.to_string());
        }
        let key: Vec<String> = args.iter().map(|a| a.to_string()).collect();
        if let Some(outcome) = self.calls.get(&key) {
            return outcome.clone().map_err(str::to_string);
        }
        let outcome = match run(&self.root, args) {
            Ran::TimedOut => {
                self.timed_out = true;
                return Err(TIMED_OUT.to_string());
            }
            Ran::Failed => Err(FAILED),
            Ran::Out(bytes) => String::from_utf8(bytes)
                .ok()
                .and_then(|text| serde_json::from_str::<Value>(&text).ok())
                .ok_or(UNREADABLE),
        };
        self.calls.insert(key, outcome.clone());
        outcome.map_err(str::to_string)
    }
}

/// `pr view`'s answer, in its shape: `number` the PR asked, `state` a string,
/// `mergedAt` a string or null, `headRefOid` a string, `mergeCommit` null or
/// an object with a string `oid`.
struct PrView<'v> {
    state: &'v str,
    merged_at: Option<&'v str>,
    head: &'v str,
    merge: Option<&'v str>,
}

impl<'v> PrView<'v> {
    fn read(answer: &'v Value, pr: u64) -> Option<PrView<'v>> {
        let o = answer.as_object()?;
        if o.get("number")?.as_u64() != Some(pr) {
            return None;
        }
        let merged_at = match o.get("mergedAt")? {
            Value::Null => None,
            v => Some(v.as_str()?),
        };
        let merge = match o.get("mergeCommit")? {
            Value::Null => None,
            v => Some(v.as_object()?.get("oid")?.as_str()?),
        };
        Some(PrView { state: o.get("state")?.as_str()?, merged_at, head: o.get("headRefOid")?.as_str()?, merge })
    }
}

/// A slurped paginated answer: a non-empty array of pages, each an object with
/// the same non-negative integer `total_count` and an array `list`, the entries
/// of all pages numbering that count, every entry an object that `entry` accepts.
fn pages<'v>(
    answer: &'v Value,
    list: &str,
    entry: fn(&Map<String, Value>) -> bool,
) -> Option<Vec<&'v Map<String, Value>>> {
    let pages = answer.as_array().filter(|p| !p.is_empty())?;
    let mut total = None;
    let mut entries = Vec::new();
    for page in pages {
        let page = page.as_object()?;
        let count = page.get("total_count")?.as_u64()?;
        if total.is_some_and(|t| t != count) {
            return None;
        }
        total = Some(count);
        for e in page.get(list)?.as_array()? {
            entries.push(e.as_object().filter(|e| entry(e))?);
        }
    }
    (entries.len() as u64 == total?).then_some(entries)
}

/// Item 79's check-run entry: a string `name`, a string `status` and a
/// `conclusion` that is a string or null.
fn check_run(e: &Map<String, Value>) -> bool {
    e.get("name").is_some_and(Value::is_string)
        && e.get("status").is_some_and(Value::is_string)
        && e.get("conclusion").is_some_and(|c| c.is_string() || c.is_null())
}

/// Item 114: a name's counts in one PR: runs, red, green again, fixed by a
/// new commit, still red.
pub type Tally = [u64; 5];

#[derive(Clone, Copy, PartialEq)]
enum Verdict {
    Red,
    Green,
    Other,
}

/// A completed run of a `suite_checks` name: the name's index, its verdict
/// and its completion time.
struct Run {
    name: usize,
    verdict: Verdict,
    at: i64,
}

/// Item 114: a slurped PR commits list (a non-empty array of array pages,
/// every entry an object with a 40-lowercase-hex `sha`): the distinct shas,
/// each at its first position.
fn pr_commits(answer: &Value) -> Option<Vec<String>> {
    let mut commits: Vec<String> = Vec::new();
    for page in answer.as_array().filter(|p| !p.is_empty())? {
        for entry in page.as_array()? {
            let sha = entry.as_object()?.get("sha")?.as_str().filter(|s| oid(s))?;
            if !commits.iter().any(|c| c == sha) {
                commits.push(sha.to_string());
            }
        }
    }
    Some(commits)
}

/// Item 114: a commit's `filter=all` check runs (item 79's reader): the
/// completed runs of the `names`, each with a time `completed_at`.
fn suite_runs(answer: &Value, names: &[String]) -> Option<Vec<Run>> {
    let mut runs = Vec::new();
    for e in pages(answer, "check_runs", check_run)? {
        let Some(name) = names.iter().position(|n| e["name"] == n.as_str()) else { continue };
        if e["status"] != "completed" {
            continue;
        }
        let at = e.get("completed_at").and_then(Value::as_str).and_then(time)?;
        let verdict = match e["conclusion"].as_str() {
            Some("failure" | "timed_out") => Verdict::Red,
            Some("success") => Verdict::Green,
            _ => Verdict::Other,
        };
        runs.push(Run { name, verdict, at });
    }
    Some(runs)
}

/// Item 114: each red run judged on its own: green again (a later green run
/// of its name at its commit), else fixed by a new commit (a later green run
/// of its name at a later commit of the PR), else still red.
fn tally(commits: &[Vec<Run>], names: usize) -> Vec<Tally> {
    let mut counts = vec![[0u64; 5]; names];
    for (i, runs) in commits.iter().enumerate() {
        for red in runs {
            let count = &mut counts[red.name];
            count[0] += 1;
            if red.verdict != Verdict::Red {
                continue;
            }
            count[1] += 1;
            let green_after = |runs: &Vec<Run>| {
                runs.iter().any(|g| g.name == red.name && g.verdict == Verdict::Green && g.at > red.at)
            };
            if green_after(runs) {
                count[2] += 1;
            } else if commits[i + 1..].iter().any(green_after) {
                count[3] += 1;
            } else {
                count[4] += 1;
            }
        }
    }
    counts
}

/// Item 113: a slurped statuses list (a non-empty array of array pages, every
/// entry an object with a string `context`; a `shipcraft/review` entry also a
/// string or null `description` and a time `created_at`). The count of the
/// review status with a count whose `created_at` is latest, the first in
/// answer order on equal times.
fn latest_count(answer: &Value) -> Result<u64, &'static str> {
    let pages = answer.as_array().filter(|p| !p.is_empty()).ok_or(UNREADABLE)?;
    let mut latest: Option<(i64, u64)> = None;
    for page in pages {
        for entry in page.as_array().ok_or(UNREADABLE)? {
            let entry = entry.as_object().ok_or(UNREADABLE)?;
            if entry.get("context").and_then(Value::as_str).ok_or(UNREADABLE)? != "shipcraft/review" {
                continue;
            }
            let description = match entry.get("description") {
                Some(Value::Null) => None,
                Some(Value::String(d)) => Some(d.as_str()),
                _ => return Err(UNREADABLE),
            };
            let at = entry.get("created_at").and_then(Value::as_str).and_then(time).ok_or(UNREADABLE)?;
            if let Some(count) = description.and_then(blocking_count) {
                if latest.is_none_or(|(t, _)| at > t) {
                    latest = Some((at, count));
                }
            }
        }
    }
    latest.map(|(_, count)| count).ok_or("no blocking count at commit")
}

/// Item 113: a review description's count: one of the two verdict prefixes,
/// then 1 to 9 ASCII digits, then the end or a space.
fn blocking_count(description: &str) -> Option<u64> {
    let rest = ["on this machine: APPROVE, Blocking ", "on this machine: CHANGES REQUESTED, Blocking "]
        .iter()
        .find_map(|prefix| description.strip_prefix(prefix))?;
    let digits = rest.bytes().take_while(u8::is_ascii_digit).count();
    if !(1..=9).contains(&digits) || !matches!(rest.as_bytes().get(digits), None | Some(b' ')) {
        return None;
    }
    rest[..digits].parse().ok()
}

/// 40 lowercase hex characters.
pub fn oid(text: &str) -> bool {
    text.len() == 40 && text.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

/// GitHub's UTC form `YYYY-MM-DDTHH:MM:SSZ`, a real date in years 0001 to
/// 9999, as Unix seconds; any other text is not a time.
fn time(text: &str) -> Option<i64> {
    let b = text.as_bytes();
    if b.len() != 20 || [b[4], b[7], b[10], b[13], b[16], b[19]] != *b"--T::Z" {
        return None;
    }
    let n = |r: std::ops::Range<usize>| -> Option<i64> {
        b[r.clone()].iter().all(u8::is_ascii_digit).then(|| text[r].parse().ok())?
    };
    let (y, mo, d, h, mi, s) = (n(0..4)?, n(5..7)?, n(8..10)?, n(11..13)?, n(14..16)?, n(17..19)?);
    let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);
    let days = match mo {
        2 if leap => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        1..=12 => 31,
        _ => return None,
    };
    if y < 1 || d < 1 || d > days || h > 23 || mi > 59 || s > 59 {
        return None;
    }
    Some(days_from_civil(y, mo, d) * 86_400 + h * 3600 + mi * 60 + s)
}

enum Ran {
    Out(Vec<u8>),
    Failed,
    TimedOut,
}

/// `gh <args>` at the root, in its own process group, stdin from /dev/null,
/// stderr discarded, without the repository-selecting git variables and with
/// no prompt. The limit covers its start, its output and its exit; at the
/// limit the group is killed and its output no longer waited for.
fn run(root: &Path, args: &[&str]) -> Ran {
    let started = Instant::now();
    let mut command = Command::new("gh");
    command.args(args).current_dir(root).env("GH_PROMPT_DISABLED", "1");
    for var in REPOSITORY_VARS {
        command.env_remove(var);
    }
    let spawned = command.stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null()).process_group(0).spawn();
    let Ok(mut child) = spawned else { return Ran::Failed };
    let mut stdout = child.stdout.take().expect("piped stdout");
    // A descendant may hold the pipe past the limit: the reader is never joined.
    let (send, output) = channel();
    std::thread::spawn(move || {
        let mut bytes = Vec::new();
        let _ = send.send(stdout.read_to_end(&mut bytes).map(|_| bytes));
    });
    let stop = |child: &mut std::process::Child| {
        let _ = kill_group(child.id());
        let _ = child.kill();
        let _ = child.wait();
    };
    let (mut status, mut out) = (None, None);
    loop {
        if status.is_none() {
            match child.try_wait() {
                Ok(s) => status = s,
                Err(_) => {
                    stop(&mut child);
                    return Ran::Failed;
                }
            }
        }
        // A non-zero exit or a signal: the group goes, any partial answer too.
        if status.is_some_and(|s| !s.success()) {
            let _ = kill_group(child.id());
            return Ran::Failed;
        }
        if out.is_none() {
            match output.try_recv() {
                Ok(read) => out = Some(read),
                Err(TryRecvError::Empty) => {}
                Err(TryRecvError::Disconnected) => out = Some(Err(std::io::ErrorKind::BrokenPipe.into())),
            }
        }
        match (&status, out.take()) {
            (Some(_), Some(Ok(bytes))) => return Ran::Out(bytes),
            (_, Some(Err(_))) => {
                stop(&mut child);
                return Ran::Failed;
            }
            (_, read) => out = read,
        }
        if started.elapsed() >= LIMIT {
            stop(&mut child);
            return Ran::TimedOut;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[cfg(test)]
mod tests {
    use super::{blocking_count, latest_count, pr_commits, suite_runs, tally, time, Asker};
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
        let answer =
            json!([[status(approve(6), "2026-01-01T00:00:00Z")], [status(approve(9), "2026-01-01T00:00:00Z")]]);
        assert_eq!(latest_count(&answer), Ok(6));
        for none in [json!([[]]), json!([[{"context": "x"}], [status(json!("review error"), "2026-01-01T00:00:00Z")]])]
        {
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
}
