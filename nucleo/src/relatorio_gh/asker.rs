//! The asker: a lock's waiting and merge time, a commit's Blocking count, a PR's check runs, the config, the cache.

use super::answers::{check_run, oid, pages, time, PrView};
use super::blocking::latest_count;
use super::checks::{pr_commits, suite_runs, tally, Tally};
use super::process::{run, Ran};
use super::{Outcome, Pr, FAILED, TIMED_OUT, UNREADABLE};
use crate::config::{Config, CONFIG_FILE};
use crate::gh::percent_encode;
use crate::relatorio::{num, Git};
use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

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
