//! `shipcraft ci --base <ref>`: repeats the hook's checks on every commit of
//! `<base>..HEAD` and runs the whole suite on HEAD only, as the base's
//! `.shipcraft.toml` says. A commit made with
//! `--no-verify`, or under an edited hook, is caught here. Run on the default
//! branch, it also warns of the merges that skipped the gate (item 5.5).
//! With `--pr`, a docs-only PR skips the build, the `check` and the suites
//! (item 40).

use crate::config::{Camada, Config};
use crate::contract::{
    arrive_closed, bindings, check_files, check_lefthook, judge_locks, judge_locks_admitting, judge_suite, no_report,
    Change, Scope, Verdict,
};
use crate::docs;
use crate::gh;
use crate::git::{short, Repo, Snapshot};
use crate::lock::lock_files;
use crate::medicao;
use crate::refusal::{failed, refuse, Result};
use crate::suite;
use serde_json::json;

pub fn run(repo: &Repo, base: &str, pr: bool, docs_only: &mut bool) -> Result<()> {
    let base =
        repo.resolve(base)?.ok_or_else(|| failed(format!("--base {base} is not a commit in this repository")))?;
    let head_sha = repo.head()?.ok_or_else(|| failed("the repository has no commits"))?;
    // Item 38: a CI run for a PR carries its locks, set before anything here
    // can refuse, so the row of an early refusal still names them; `shipcraft
    // pr` already set them.
    if pr && medicao::pr_locks().is_none() {
        medicao::set_pr_locks(&medicao::locks_changed(repo, &base, &head_sha));
    }
    let head = Snapshot::Commit(head_sha.clone());
    // Item 31: HEAD's config is validated; a HEAD without one uninstalls.
    let head_config = Config::at(repo, &head)?;
    // Item 1, rule 3: the range is judged by the config of its base (the PR's
    // base branch); a change to `.shipcraft.toml` counts only once it is in the base.
    let Some(config) = Config::at(repo, &Snapshot::Commit(base.clone()))?.or(head_config) else {
        return crate::config::no_config();
    };
    let commits = repo.commits_since(&base)?;
    *docs_only = pr && docs::docs_only(repo, &config, &base, &head_sha);

    // How each commit changed the locks; with an empty range, HEAD's locks as they are.
    let head_locks = lock_files(repo, &head)?;
    let mut head_changes = judge_locks(std::slice::from_ref(&head_locks), &head_locks, &head.describe(), false)?;
    let on_default = repo.branch() == repo.default_branch();
    for commit in &commits {
        let snapshot = Snapshot::Commit(commit.clone());
        let parents: Vec<Snapshot> = repo.parents(commit)?.into_iter().map(Snapshot::Commit).collect();
        let locks = parents.iter().map(|parent| lock_files(repo, parent)).collect::<Result<Vec<_>>>()?;
        let now = lock_files(repo, &snapshot)?;
        // Item 42: on the default branch, a lock that arrives closed is
        // admitted only when GitHub shows the commit is a squash of a PR whose
        // head had every required status in success.
        let admit = on_default && arrive_closed(&locks, &now) && squash_proved(repo, commit, &required(&config));
        let changes = judge_locks_admitting(&locks, &now, &snapshot.describe(), false, admit)?;
        for (path, change, lock) in bindings(&changes) {
            check_files(repo, &snapshot, path, lock)?;
            // 15c.4: a lefthook change in a commit (made with --no-verify) is the CI's.
            if !matches!(change, Change::Opened(_)) {
                check_lefthook(repo, &parents, &snapshot, path)?;
            }
        }
        head_changes = changes;
    }
    println!("shipcraft: {} commit(s) checked in {}..HEAD", commits.len(), short(&base));
    if *docs_only {
        println!("docs only: the suites do not run");
        return passed(repo, &base, &config);
    }

    // The suite judges HEAD: on the tree when it is HEAD, else on a copy of
    // HEAD. The build runs only on the tree (item 16a).
    let dirty = repo.dirty()?;
    if dirty && config.build.is_some() {
        return refuse(
            "build-dirty-tree",
            ".shipcraft.toml has [build] and the tree is dirty: there are changes outside HEAD",
            "the build writes to the tree itself and builds only the judged content (HEAD); it does not run in a copy yet",
            "commit or stash the changes (git stash) and run `shipcraft ci` again",
        );
    }
    let copy = if dirty { Some(repo.export(&head)?) } else { None };
    let dir = copy.as_ref().map_or(repo.root(), |c| c.path());
    suite::build(dir, &config, "")?;
    let report = suite::run(dir, copy.is_some(), &config)?.or_else(no_report)?;
    let mut cycle_open = false;
    for (path, change, lock) in bindings(&head_changes) {
        match (change, judge_suite(&report, path, change, lock, Scope::Ci)?) {
            (Change::Kept(_), Verdict::Green) => {
                return refuse(
                    "lock-not-closed",
                    format!("the locked cases pass at HEAD, but lock {path} is still open"),
                    "the lock closes automatically in the commit where cases pass; if it did not, the commit skipped the hook (--no-verify)",
                    "redo the last commit with the hook enabled (git commit --amend --no-edit, without --no-verify) to close the lock",
                );
            }
            (Change::Kept(_) | Change::Opened(_), _) => cycle_open = true,
            _ => {}
        }
    }
    if !cycle_open && !report.is_green() {
        return refuse(
            "suite-red",
            "the suite fails at HEAD and there is no open cycle",
            "outside an open cycle the suite stays green; a new failing test starts with RED",
            "fix the code, or open the new test cycle with `shipcraft red`",
        );
    }
    passed(repo, &base, &config)
}

fn passed(repo: &Repo, base: &str, config: &Config) -> Result<()> {
    if repo.branch() == repo.default_branch() {
        warn_merges(repo, base, config);
    }
    println!("shipcraft: CI ok.");
    // Item 44: `ci` publishes no status; the last line says who publishes
    // `shipcraft/ci`, by the `ci` value of the config the range is judged by.
    if let Some(line) = who_publishes(&config.execucao.ci) {
        println!("{line}");
    }
    Ok(())
}

/// Item 44: the last line of a `ci` that exits 0, per `[execution] ci`. A
/// value shipcraft does not know gets no line (its refusal is elsewhere).
fn who_publishes(ci: &str) -> Option<&'static str> {
    match ci {
        "local" => Some("shipcraft: ci publishes no status; shipcraft pr runs CI and publishes shipcraft/ci on HEAD."),
        "github" => Some("shipcraft: ci publishes no status; the GitHub workflow publishes shipcraft/ci on HEAD."),
        "off" => {
            Some("shipcraft: ci publishes no status; with ci = \"off\", shipcraft pr publishes shipcraft/ci as off.")
        }
        _ => None,
    }
}

/// Item 5.5: a merge into the default branch went through the gate when its
/// PR head had every layer that is on in `success`, or was merged with
/// `shipcraft merge --no-review`. Any other merge is warned of and measured as an
/// escape. A warning, never a refusal.
fn warn_merges(repo: &Repo, base: &str, config: &Config) {
    // Item 42: every first-parent commit, so a squash is judged too.
    let Some(merges) = repo.try_text(&["rev-list", "--first-parent", &format!("{base}..HEAD")]) else {
        return;
    };
    if merges.is_empty() {
        return;
    }
    let required = required(config);
    let known: Vec<String> = medicao::rows(repo)
        .into_iter()
        .filter(|r| r["escape"] == true)
        .filter_map(|r| r["commit"].as_str().map(str::to_string))
        .collect();
    for merge in merges.lines() {
        match gated(repo, merge, &required) {
            Ok(Some(pr)) => {
                println!(
                    "shipcraft: warning: merge {} (PR #{pr}) landed without {} in success and without `shipcraft merge --no-review`",
                    short(merge),
                    required.join(" and ")
                );
                if !known.iter().any(|c| c == merge) {
                    medicao::record(
                        repo,
                        json!({"layer": "merge", "escape": true, "pr": pr, "secs": 0, "result": "passed",
                               "code": "escape", "branch": repo.branch(), "commit": merge}),
                    );
                }
            }
            Ok(None) => {}
            Err(e) => {
                println!("shipcraft: warning: could not check merges on {} through gh: {e}", repo.branch());
                return;
            }
        }
    }
}

/// The status contexts a PR head needs: those of the layers that are on
/// (both when the config's layers cannot be read).
fn required(config: &Config) -> Vec<&'static str> {
    match config.camadas() {
        Ok((ci, revisao)) => [(ci, "shipcraft/ci"), (revisao, "shipcraft/review")]
            .into_iter()
            .filter(|(camada, _)| *camada != Camada::Desligado)
            .map(|(_, context)| context)
            .collect(),
        Err(_) => vec!["shipcraft/ci", "shipcraft/review"],
    }
}

/// How a PR merged into the default branch stood at the gate (items 5.5 and 42).
struct PrGate {
    number: u64,
    /// Every required status in success at the PR head.
    statuses: bool,
    /// Every required status but the review in success at the PR head.
    ci: bool,
    /// The PR carries the `shipcraft merge --no-review` comment.
    waived: bool,
}

impl PrGate {
    /// The escape check's verdict: the merge went through the gate.
    fn escaped(&self) -> bool {
        !self.statuses && !self.waived
    }

    /// Item 42: a squash proves its closed locks when its statuses are in
    /// success, or the review was waived while the CI was in success.
    fn proves_closed_locks(&self) -> bool {
        self.statuses || (self.waived && self.ci)
    }
}

/// The gate standing of the PR GitHub reports `commit` as the merge commit of;
/// None when no PR merged it.
fn pr_gate(repo: &Repo, commit: &str, required: &[&str]) -> std::result::Result<Option<PrGate>, String> {
    let get = |path: String| -> std::result::Result<serde_json::Value, String> {
        serde_json::from_str(&gh::run(repo, &["api", &path])?).map_err(|e| e.to_string())
    };
    let pulls = get(format!("repos/{{owner}}/{{repo}}/commits/{commit}/pulls"))?;
    let Some(pr) = pulls.as_array().into_iter().flatten().find(|p| p["merge_commit_sha"] == commit) else {
        return Ok(None);
    };
    let number = pr["number"].as_u64().unwrap_or(0);
    let head = pr["head"]["sha"].as_str().unwrap_or_default();
    let statuses = get(format!("repos/{{owner}}/{{repo}}/commits/{head}/statuses"))?;
    let latest = |context: &str| {
        statuses.as_array().into_iter().flatten().find(|s| s["context"] == context).and_then(|s| s["state"].as_str())
    };
    let ok = |context: &&str| latest(context) == Some("success");
    let all = required.iter().all(ok);
    let ci = required.iter().filter(|c| **c != "shipcraft/review").all(ok);
    let waived = !all && {
        let comments = get(format!("repos/{{owner}}/{{repo}}/issues/{number}/comments"))?;
        comments
            .as_array()
            .into_iter()
            .flatten()
            .any(|c| c["body"].as_str().is_some_and(|b| b.contains(crate::merge::SEM_REVISAO_MARK)))
    };
    Ok(Some(PrGate { number, statuses: all, ci, waived }))
}

/// Item 42: `commit` is a PR's merge commit and that PR went through the gate
/// with its CI in success; false when GitHub cannot be read.
fn squash_proved(repo: &Repo, commit: &str, required: &[&str]) -> bool {
    matches!(pr_gate(repo, commit, required), Ok(Some(gate)) if gate.proves_closed_locks())
}

/// The PR number when the merge skipped the gate; None when it went through
/// it, or is not a PR merge.
fn gated(repo: &Repo, merge: &str, required: &[&str]) -> std::result::Result<Option<u64>, String> {
    Ok(pr_gate(repo, merge, required)?.filter(PrGate::escaped).map(|gate| gate.number))
}
