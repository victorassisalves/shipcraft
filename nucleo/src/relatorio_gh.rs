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
            let runs = pages(&runs, "check_runs", |e| {
                e.get("name").is_some_and(Value::is_string)
                    && e.get("status").is_some_and(Value::is_string)
                    && e.get("conclusion").is_some_and(|c| c.is_string() || c.is_null())
            })
            .ok_or(UNREADABLE)?;
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

/// 40 lowercase hex characters.
fn oid(text: &str) -> bool {
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
    use super::time;

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
