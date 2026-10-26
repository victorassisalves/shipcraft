//! Item 5: `shipcraft merge <pr> [--no-review "<reason>"]`, the merge gate, and
//! `shipcraft status`, which says how protected the default branch really is.

use crate::config::{Camada, Config};
use crate::gh;
use crate::git::{short, Repo, Snapshot};
use crate::lock::lock_files;
use crate::medicao;
use crate::refusal::{refuse, Result};
use serde_json::json;
use std::time::Instant;

/// The text that marks a PR merged with `--no-review` (read back by `shipcraft ci`, item 5.5).
pub const SEM_REVISAO_MARK: &str = "shipcraft merge --no-review";

pub fn merge(repo: &Repo, number: &str, sem_revisao: Option<&str>) -> Result<()> {
    let started = Instant::now();
    if sem_revisao.is_some_and(|m| m.trim().is_empty()) {
        return refuse(
            "no-review-without-reason",
            "--no-review has no reason",
            "merging without review is a recorded exception: the reason goes in the PR and measurements",
            format!("give the reason: shipcraft merge {number} --no-review \"<reason>\""),
        );
    }
    let pr = gh::json(repo, &["pr", "view", number, "--json", "number,state,headRefOid,headRefName,baseRefName"])?;
    let field = |k: &str| pr[k].as_str().unwrap_or_default().to_string();
    let (head, base) = (field("headRefOid"), field("baseRefName"));
    if field("state") != "OPEN" {
        return refuse(
            "pr-not-open",
            format!("PR #{number} is not open ({})", field("state")),
            "shipcraft merge only brings an open PR into the base",
            "check the PR number (gh pr list) and try again",
        );
    }
    repo.run(&["fetch", "-q", "origin", &format!("+refs/heads/{base}:refs/remotes/origin/{base}")])?;
    let config = Config::of_base(repo, &base)?;
    let (ci, revisao) = config.camadas()?;
    let statuses = gh::statuses(repo, &head)?;
    let state = |context: &str| statuses.get(context).map_or("no status", |(s, _)| s.as_str());
    if ci != Camada::Desligado && state("shipcraft/ci") != "success" {
        return refuse(
            "merge-without-ci",
            format!(
                "PR #{number} has no successful shipcraft/ci at its HEAD ({}): {}",
                short(&head),
                state("shipcraft/ci")
            ),
            "merging requires green CI on the latest PR commit; --no-review waives review, never CI",
            "run shipcraft pr on the PR branch to run CI and publish the status, then try again",
        );
    }
    if revisao != Camada::Desligado && sem_revisao.is_none() && state("shipcraft/review") != "success" {
        return refuse(
            "merge-without-review",
            format!(
                "PR #{number} has no successful shipcraft/review at its HEAD ({}): {}",
                short(&head),
                state("shipcraft/review")
            ),
            "merging requires an approved review on the latest PR commit",
            format!(
                "run shipcraft pr (or shipcraft review --pr {number}) and fix what the review requests; if it cannot run, use --no-review \"<reason>\""
            ),
        );
    }
    let pr_number = pr["number"].as_u64().unwrap_or(0);
    if let Some(motivo) = sem_revisao {
        gh::comment(
            repo,
            pr_number,
            &format!("**{SEM_REVISAO_MARK}:** {motivo}\n\nThis merge landed without an executed review; the reason stays here and in measurements."),
        )?;
    }
    // Item 38: the locks the PR delivers, from its own diff, read before the
    // merge moves the base; best effort, as all measuring.
    if repo.resolve(&format!("{head}^{{commit}}")).ok().flatten().is_none() {
        let _ = repo.run(&["fetch", "-q", "origin", &format!("refs/pull/{pr_number}/head")]);
    }
    let locks = medicao::locks_changed(repo, &format!("origin/{base}"), &head);
    gh::must(repo, &["pr", "merge", number, "--merge"])?;
    medicao::record(
        repo,
        json!({"layer": "merge", "secs": medicao::seconds(started), "result": "passed",
               "code": if sem_revisao.is_some() { "no-review" } else { "" }, "reason": sem_revisao,
               "pr": pr_number, "branch": field("headRefName"), "commit": head,
               "base": base, "default_branch": repo.default_branch(), "locks": locks}),
    );
    println!(
        "shipcraft: PR #{number} merged into {base}{}.",
        if sem_revisao.is_some() { " without review (reason in the PR)" } else { "" }
    );
    Ok(())
}

pub fn status(repo: &Repo) -> Result<()> {
    let base = repo.default_branch();
    let config = Config::load(repo)?;
    println!("shipcraft: branch {}", repo.branch());
    let layer = |value: &str| match value {
        "local" => "local (on this machine)".to_string(),
        other => other.to_string(),
    };
    println!(
        "shipcraft: layers: ci {}; review {} (agent {})",
        layer(&config.execucao.ci),
        layer(&config.execucao.revisao),
        config.papeis.revisao
    );
    println!("{}", crate::init::hook_status(repo));
    let open: Vec<String> = lock_files(repo, &Snapshot::Tree)?
        .into_iter()
        .filter(|(_, bytes)| crate::lock::Lock::parse(bytes).is_none_or(|l| l.is_open()))
        .map(|(path, _)| path)
        .collect();
    println!("shipcraft: open locks: {}", if open.is_empty() { "none".to_string() } else { open.join(", ") });
    let path = format!("repos/{{owner}}/{{repo}}/branches/{base}/protection");
    let line = match gh::run(repo, &["api", &path]) {
        Ok(out) => {
            let value: serde_json::Value = serde_json::from_str(&out).unwrap_or_default();
            let contexts = &value["required_status_checks"]["contexts"];
            let has = |c: &str| contexts.as_array().is_some_and(|l| l.iter().any(|x| x == c));
            if has("shipcraft/ci") && has("shipcraft/review") {
                format!("shipcraft: branch protection on {base}: GitHub requires shipcraft/ci and shipcraft/review")
            } else {
                format!("shipcraft: branch protection on {base}, but GitHub does not require shipcraft/ci and shipcraft/review: `shipcraft merge` is the gate")
            }
        }
        Err(e) if e.contains("403") || e.contains("Upgrade to GitHub Pro") => {
            "shipcraft: this repository has no branch protection (GitHub free plan): `shipcraft merge` is the gate"
                .to_string()
        }
        Err(e) if e.contains("404") || e.contains("not protected") => {
            format!("shipcraft: {base} has no branch protection: `shipcraft merge` is the gate")
        }
        Err(e) => format!(
            "shipcraft: could not read branch protection ({}): use `shipcraft merge` as the gate",
            e.lines().next().unwrap_or("")
        ),
    };
    println!("{line}");
    Ok(())
}
