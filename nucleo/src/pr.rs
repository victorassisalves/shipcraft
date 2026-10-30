//! Item 3: `shipcraft pr`, the single door of a PR, and `shipcraft review`, the same
//! review without (or for another) PR.

use crate::config::{Camada, Config};
use crate::docs;
use crate::fila;
use crate::forma;
use crate::gh;
use crate::git::{short, Repo};
use crate::lock::sha256_hex;
use crate::medicao;
use crate::processo::{self, End};
use crate::refusal::{failed, refuse, Result};
use crate::revisao::{self, Request, Review, Verdict};
use serde_json::json;
use std::fs;
use std::process::Command;
use std::thread::sleep;
use std::time::{Duration, Instant};

const OFF: &str = "off in .shipcraft.toml";

/// How a layer ended for this PR.
enum Gate {
    Passed,
    /// Did not pass; the reason, for the refusal at the end.
    Stopped(&'static str, String),
}

pub fn pr(repo: &Repo, title: Option<&str>, body_file: Option<&str>) -> Result<()> {
    let started = Instant::now();
    let base = repo.default_branch();
    repo.run(&["fetch", "-q", "origin"])?;
    let config = Config::of_base(repo, &base)?;
    let (ci, revisao) = config.camadas()?;
    let branch = repo.branch();
    if branch.is_empty() || branch == base {
        return refuse(
            "pr-not-on-branch",
            format!(
                "shipcraft pr needs a working branch, and HEAD is at {}",
                if branch.is_empty() { "nenhum branch" } else { &branch }
            ),
            format!("a PR brings a branch into {base}; {base} cannot open a PR into itself"),
            "create a branch (git switch -c <name>) and run shipcraft pr on it",
        );
    }
    let body_given = match body_file {
        Some(path) => Some(fs::read_to_string(path).map_err(|e| failed(format!("read {path}: {e}")))?),
        None => None,
    };
    let head = repo.head()?.ok_or_else(|| failed("the branch has no commits"))?;

    repo.run(&["push", "-q", "--force-with-lease", "origin", &format!("{branch}:refs/heads/{branch}")])?;
    println!("shipcraft: {branch} published to origin ({})", short(&head));
    let (number, body) = match gh::open_pr(repo, &branch)? {
        Some((n, existing)) => {
            if title.is_some() || body_given.is_some() {
                gh::edit_pr(repo, n, title, body_given.as_deref())?;
            }
            (n, body_given.or(existing))
        }
        None => {
            let title = match title {
                Some(t) => t.to_string(),
                None => repo.text(&["log", "-1", "--format=%s"])?,
            };
            let body = body_given.unwrap_or_default();
            (gh::create_pr(repo, &branch, &base, &title, &body)?, Some(body))
        }
    };
    println!("shipcraft: PR #{number}");
    let base_sha = repo.text(&["merge-base", &format!("origin/{base}"), "HEAD"])?;
    // Item 38: the ci, review and pr rows of this PR carry its locks.
    let locks = medicao::locks_changed(repo, &base_sha, &head);
    medicao::set_pr_locks(&locks);
    // Item 41: the local CI's wait for a slot; `None` without local CI.
    let mut queue_secs = None;
    // Item 38: from here the PR and its locks are known, so the `pr` row
    // records how the command ended (passed, refused, or error), whichever
    // later step stops it.
    let result = (|| -> Result<()> {
        let size = medicao::product_lines(repo, &config, &base_sha, &head)?;
        std::env::set_var(medicao::LINHAS_ENV, (size.0 + size.1).to_string());
        let forma = forma::forma(repo, &config, &base_sha, &head);
        std::env::set_var(forma::AVISOS_ENV, forma.avisos.map_or("null".to_string(), |n| n.to_string()));

        let ci_gate = match ci {
            Camada::Local => local_ci(repo, &config, &branch, &head, &base, &mut queue_secs)?,
            Camada::Github if revisao == Camada::Local => wait_github_ci(repo, &config, &head)?,
            Camada::Github => Gate::Passed,
            Camada::Desligado => {
                gh::status(repo, &head, "shipcraft/ci", "success", OFF)?;
                println!("shipcraft: CI {OFF}");
                Gate::Passed
            }
        };
        let gate = match (ci_gate, revisao) {
            (Gate::Passed, Camada::Local) => {
                let title = gh::json(repo, &["pr", "view", &number.to_string(), "--json", "title"])?["title"]
                    .as_str()
                    .map(str::to_string);
                let req = Request {
                    repo,
                    config: &config,
                    diff_sha256: diff_sha256(repo, &base_sha, &head),
                    text_sha256: text_sha256(title.as_deref(), body.as_deref()),
                    sha: head.clone(),
                    base_sha,
                    title: title.unwrap_or_default(),
                    body: body.clone().unwrap_or_default(),
                    pr: Some(number),
                    branch: branch.clone(),
                    // Item 63: the CI gate passed at this head with local or GitHub CI.
                    after_green_ci: matches!(ci, Camada::Local | Camada::Github),
                };
                review_and_publish(&req)?
            }
            (Gate::Passed, _) => {
                gh::status(repo, &head, "shipcraft/review", "success", OFF)?;
                println!("shipcraft: review {OFF}");
                Gate::Passed
            }
            (stopped, _) => stopped,
        };
        let summary = medicao::summary(repo, &branch) + "\n" + &medicao::size_text(&config, size) + &forma.text;
        gh::comment(repo, number, &summary)?;
        match gate {
            Gate::Passed => {
                println!(
                    "shipcraft: PR #{number} ready: enabled layers passed; merge with `shipcraft merge {number}`."
                );
                Ok(())
            }
            Gate::Stopped(code, why) => refuse(
                code,
                format!("PR #{number} is not ready: {why}"),
                "merging requires green CI and review on the latest PR commit",
                "fix what the layer reported, commit and run shipcraft pr again",
            ),
        }
    })();
    let mut row = medicao::row(repo, "pr", started, &result);
    row["pr"] = json!(number);
    row["base"] = json!(base);
    row["queue_secs"] = json!(queue_secs);
    medicao::record(repo, row);
    result
}

/// Item 3, rule 2: `shipcraft ci --pr` on this machine, through the queue and with
/// `[execution] ci_timeout`, published as `shipcraft/ci` on HEAD. Item 41: a
/// docs-only PR (item 40's rule) skips the queue; `queue_secs` gets the wait.
fn local_ci(
    repo: &Repo,
    config: &Config,
    branch: &str,
    head: &str,
    base: &str,
    queue_secs: &mut Option<u64>,
) -> Result<Gate> {
    // `--base` is the tip of the base branch as origin has it now: the range
    // is the same as from the merge-base, and the child judges the suite by
    // the base's current config (item 1, rule 3).
    let base_tip = repo.text(&["rev-parse", &format!("origin/{base}")])?;
    let limit = config.execucao.tempo_max_ci;
    *queue_secs = Some(0);
    let docs_only = docs::docs_only(repo, config, &base_tip, head);
    let slot = if docs_only {
        None
    } else {
        let asked = Instant::now();
        let slot = fila::enter(fila::slots(config), &format!("{} ({branch}, ci)", repo.name()));
        *queue_secs = Some(asked.elapsed().as_secs());
        Some(slot?)
    };
    println!(
        "shipcraft: CI on this machine: shipcraft ci --base origin/{base} ({}, up to {limit} s)",
        short(&base_tip)
    );
    let started = Instant::now();
    let exe = std::env::current_exe().map_err(|e| failed(format!("find the current binary: {e}")))?;
    let end =
        processo::run(Command::new(exe).args(["ci", "--base", &base_tip, "--pr"]).current_dir(repo.root()), limit)?;
    drop(slot);
    let (state, description, gate) = match end {
        End::Exited(0) => ("success", "on this machine: CI passed".to_string(), Gate::Passed),
        End::Exited(1) => (
            "failure",
            "on this machine: CI refused (shipcraft pr output says why)".to_string(),
            Gate::Stopped("ci-refused", refused_why(repo, head)),
        ),
        End::Exited(code) => (
            "error",
            format!("on this machine: shipcraft ci failed (exit code {code})"),
            Gate::Stopped("ci-error", "CI failed".to_string()),
        ),
        End::TimedOut => {
            medicao::record(
                repo,
                json!({"layer": "ci", "secs": medicao::seconds(started), "result": "error",
                       "code": "timed-out", "branch": branch, "commit": head,
                       "docs_only": docs_only, "suite_in_checks": false}),
            );
            let why = format!("timed out ({limit} s, [execution] ci_timeout)");
            ("error", format!("on this machine: {why}"), Gate::Stopped("ci-timed-out", format!("CI stopped: {why}")))
        }
    };
    gh::status(repo, head, "shipcraft/ci", state, &description)?;
    println!("shipcraft: shipcraft/ci {state}: {description}");
    Ok(gate)
}

/// "o CI recusou", with the refusal the CI recorded for `head`, so the last
/// three lines of `shipcraft pr` say it too (item 19.2: the command and the code).
fn refused_why(repo: &Repo, head: &str) -> String {
    let rows = medicao::rows(repo);
    let row = rows.iter().rev().find(|r| r["layer"] == "ci" && r["commit"] == head);
    match row.and_then(|r| r["reason"].as_str()) {
        Some(motivo) => format!("CI refused: {motivo}"),
        None => "CI refused".to_string(),
    }
}

/// Item 3, rule 4: with `ci = "github"`, the workflow publishes `shipcraft/ci`;
/// the local review waits for it (up to `tempo_max_ci`) and runs only on success.
/// Item 62: CI is green at HEAD when `shipcraft/ci` is and so is every suite
/// check; any failed one stops the wait, and an unreadable one is read again.
fn wait_github_ci(repo: &Repo, config: &Config, head: &str) -> Result<Gate> {
    let limit = Duration::from_secs(config.execucao.tempo_max_ci);
    let names = &config.execucao.suite_checks;
    let waited = if names.is_empty() {
        "GitHub shipcraft/ci".to_string()
    } else {
        format!("GitHub shipcraft/ci and {}", names.join(", "))
    };
    println!("shipcraft: waiting for {waited} at {} (up to {} s)", short(head), limit.as_secs());
    let started = Instant::now();
    loop {
        let ci = gh::statuses(repo, head)?.get("shipcraft/ci").map(|(s, _)| s.clone());
        if let Some(state @ ("failure" | "error")) = ci.as_deref() {
            return Ok(Gate::Stopped("ci-github", format!("GitHub shipcraft/ci returned {state}; review did not run")));
        }
        let checks: Vec<(&String, gh::Check)> = names.iter().map(|name| (name, gh::check(repo, head, name))).collect();
        if let Some((name, _)) = checks.iter().find(|(_, check)| *check == gh::Check::Failed) {
            return Ok(Gate::Stopped("ci-github", format!("GitHub check {name} failed; review did not run")));
        }
        let ci_green = ci.as_deref() == Some("success");
        if ci_green && checks.iter().all(|(_, check)| *check == gh::Check::Green) {
            return Ok(Gate::Passed);
        }
        let elapsed = started.elapsed();
        if elapsed >= limit {
            if names.is_empty() {
                return Ok(Gate::Stopped(
                    "ci-github-no-status",
                    format!("GitHub shipcraft/ci did not arrive within {} s; review did not run", limit.as_secs()),
                ));
            }
            let mut not_green: Vec<String> = Vec::new();
            if !ci_green {
                not_green.push(format!("shipcraft/ci {}", ci.as_deref().unwrap_or("no status")));
            }
            not_green.extend(
                checks.iter().filter(|(_, check)| *check != gh::Check::Green).map(|(n, c)| format!("{n} {}", c.word())),
            );
            return Ok(Gate::Stopped(
                "ci-github-no-status",
                format!(
                    "CI was not green within {} s ({}); review did not run",
                    limit.as_secs(),
                    not_green.join(", ")
                ),
            ));
        }
        sleep((limit - elapsed).min(Duration::from_secs(2)));
    }
}

/// Item 35: SHA-256 of the changed paths with the full blob ids on both sides,
/// so two ranges match only with the same versions of every changed file.
/// Empty (no reuse, nothing recorded) when git fails or nothing changed.
fn diff_sha256(repo: &Repo, base_sha: &str, head: &str) -> String {
    let args = ["diff", "--raw", "-z", "--no-abbrev", "--no-renames", "--ignore-submodules=none", base_sha, head];
    match repo.run(&args) {
        Ok(raw) if !raw.is_empty() => sha256_hex(&raw),
        _ => String::new(),
    }
}

/// Item 54: SHA-256 of the title's bytes, one NUL, the body's bytes, exactly as
/// the brief receives them; empty (no key) when either could not be read.
fn text_sha256(title: Option<&str>, body: Option<&str>) -> String {
    match (title, body) {
        (Some(title), Some(body)) => sha256_hex(&[title.as_bytes(), b"\0", body.as_bytes()].concat()),
        _ => String::new(),
    }
}

/// Item 54: a recorded text key is a source only when it is 64 lowercase hex.
fn valid_key(key: &str) -> bool {
    key.len() == 64 && key.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

/// Item 4, rule 4: the verdict of an earlier review of the same file versions.
/// Item 54: and of the same PR title and body.
fn earlier_verdict(repo: &Repo, diff_sha256: &str, text_sha256: &str) -> Option<(String, String)> {
    if diff_sha256.is_empty() || !valid_key(text_sha256) {
        return None;
    }
    medicao::rows(repo)
        .into_iter()
        .rev()
        .find(|r| {
            r["layer"] == "review"
                && r["reused"] != true
                && r["diff_sha256"] == diff_sha256
                && r["text_sha256"].as_str() == Some(text_sha256)
                && (r["result"] == "passed" || r["result"] == "refused")
        })
        .map(|r| {
            (r["result"].as_str().unwrap_or_default().to_string(), r["commit"].as_str().unwrap_or_default().to_string())
        })
}

/// Runs (or reuses) the review and publishes `shipcraft/review` and the comment.
fn review_and_publish(req: &Request) -> Result<Gate> {
    let (repo, sha) = (req.repo, req.sha.as_str());
    if let Some((resultado, from)) = earlier_verdict(repo, &req.diff_sha256, &req.text_sha256) {
        let (state, gate) = if resultado == "passed" {
            ("success", Gate::Passed)
        } else {
            ("failure", Gate::Stopped("review-changes-requested", "review requested changes".to_string()))
        };
        // Item 38: a reused verdict is recorded, and is not a new round.
        let mut row = json!({"layer": "review", "secs": 0, "result": resultado,
               "code": if resultado == "passed" { "" } else { "changes-requested" },
               "branch": req.branch, "commit": sha, "tokens": 0, "agent": req.config.papeis.revisao,
               "pr": req.pr, "reused": true});
        // Item 54: a reused row records both keys (reuse needs both).
        row["diff_sha256"] = json!(req.diff_sha256);
        row["text_sha256"] = json!(req.text_sha256);
        medicao::record(repo, row);
        let description = format!("on this machine: verdict from {} reused (same file versions)", short(&from));
        gh::status(repo, sha, "shipcraft/review", state, &description)?;
        println!("shipcraft: shipcraft/review {state}: {description}");
        return Ok(gate);
    }
    let agent = &req.config.papeis.revisao;
    gh::status(repo, sha, "shipcraft/review", "pending", &format!("on this machine: review in progress ({agent})"))?;
    let review = revisao::run(req)?;
    if let Some(pr) = req.pr {
        gh::comment(repo, pr, &comment(&review))?;
    }
    gh::status(repo, sha, "shipcraft/review", review.state(), &review.description())?;
    println!("shipcraft: shipcraft/review {}: {}", review.state(), review.description());
    Ok(match review.verdict {
        Verdict::Approve => Gate::Passed,
        Verdict::Changes => Gate::Stopped("review-changes-requested", "review requested changes".to_string()),
        Verdict::Error(why) => Gate::Stopped("review-error", format!("review gave no verdict ({why})")),
    })
}

fn comment(review: &Review) -> String {
    match &review.verdict {
        Verdict::Error(why) => {
            format!("**shipcraft: review ({}) gave no verdict:** {why}\n\n{}", review.agent, review.text)
        }
        _ => format!("**shipcraft: review executed by {}, on this machine**\n\n{}", review.agent, review.text),
    }
}

/// `shipcraft review`: the review of the local HEAD, shown and not published.
pub fn local(repo: &Repo) -> Result<()> {
    let base = repo.default_branch();
    let config = Config::of_base(repo, &base)?;
    refuse_if_off(&config)?;
    let head = repo.head()?.ok_or_else(|| failed("the branch has no commits"))?;
    let base_ref = format!("origin/{base}");
    let base_ref = if repo.resolve(&base_ref)?.is_some() { base_ref } else { base };
    let base_sha = repo.text(&["merge-base", &base_ref, "HEAD"])?;
    let log = repo.text(&["log", "--format=- %s%n%b", &format!("{base_sha}..HEAD")])?;
    let title = repo.text(&["log", "-1", "--format=%s"])?;
    let body = format!("(No PR yet: a local review of the branch before its PR. Its commits:)\n\n{log}");
    let req = Request {
        repo,
        config: &config,
        diff_sha256: diff_sha256(repo, &base_sha, &head),
        // Item 54: local rows get the key; local review still runs every time.
        text_sha256: text_sha256(Some(&title), Some(&body)),
        title,
        body,
        sha: head,
        base_sha,
        pr: None,
        branch: repo.branch(),
        after_green_ci: false,
    };
    let review = revisao::run(&req)?;
    println!("{}", review.text);
    outcome(&review, "local review")
}

/// `shipcraft review --pr <n>`: a PR that did not come from `shipcraft pr`, reviewed in
/// an isolated copy, with the status and comment published on its head.
pub fn of_pr(repo: &Repo, number: &str) -> Result<()> {
    let pr = gh::json(
        repo,
        &["pr", "view", number, "--json", "number,title,body,headRefOid,headRefName,baseRefName,isCrossRepository"],
    )?;
    if pr["isCrossRepository"] == true {
        return refuse(
            "pr-from-fork",
            format!("PR #{number} comes from a fork, and v1 does not review fork PRs"),
            "fork code comes from outside, and shipcraft good-faith model does not apply to it",
            "review this PR manually, or bring the branch into the repository and open the PR through shipcraft pr",
        );
    }
    let field = |k: &str| pr[k].as_str().unwrap_or_default().to_string();
    let (sha, base) = (field("headRefOid"), field("baseRefName"));
    repo.run(&[
        "fetch",
        "-q",
        "origin",
        &format!("+refs/heads/{base}:refs/remotes/origin/{base}"),
        &format!("refs/pull/{number}/head"),
    ])?;
    if repo.resolve(&sha)?.is_none() {
        return Err(failed(format!("HEAD of PR #{number} ({sha}) did not come from origin")));
    }
    let config = Config::of_base(repo, &base)?;
    refuse_if_off(&config)?;
    let base_sha = repo.text(&["merge-base", &format!("origin/{base}"), &sha])?;
    medicao::set_pr_locks(&medicao::locks_changed(repo, &base_sha, &sha));
    let req = Request {
        repo,
        config: &config,
        diff_sha256: diff_sha256(repo, &base_sha, &sha),
        // Item 54: no text key when gh's title or body is missing, null or not a string.
        text_sha256: text_sha256(pr["title"].as_str(), pr["body"].as_str()),
        sha,
        base_sha,
        title: field("title"),
        body: field("body"),
        pr: pr["number"].as_u64(),
        branch: field("headRefName"),
        after_green_ci: false,
    };
    match review_and_publish(&req)? {
        Gate::Passed => Ok(()),
        Gate::Stopped(code, why) => refuse(
            code,
            format!("PR #{number} did not pass: {why}"),
            "merging requires an approved review on the latest PR commit",
            "fix what the review reported (the PR comment) and run review again",
        ),
    }
}

fn refuse_if_off(config: &Config) -> Result<()> {
    if config.camadas()?.1 == Camada::Desligado {
        return refuse(
            "review-off",
            "review is off in .shipcraft.toml on main",
            "the project disabled review, and code is not sent to any provider until it enables it",
            "enable it with [execution] review = \"local\" on main, or continue without review",
        );
    }
    Ok(())
}

fn outcome(review: &Review, what: &str) -> Result<()> {
    match &review.verdict {
        Verdict::Approve => {
            println!("shipcraft: {what} approved ({}).", review.agent);
            Ok(())
        }
        Verdict::Changes => refuse(
            "review-changes-requested",
            format!("{what} requested changes (Blocking {})", review.blocking),
            "the PR can only land with an approved review; blockers are above, with reproductions",
            "fix the blockers, commit and run review again",
        ),
        Verdict::Error(why) => refuse(
            "review-error",
            format!("{what} gave no verdict: {why}"),
            "review fails closed: without a well-formed verdict there is no approval, and shipcraft does not retry automatically",
            "see reviewer output above; change the reviewer or timeout once, then escalate",
        ),
    }
}
