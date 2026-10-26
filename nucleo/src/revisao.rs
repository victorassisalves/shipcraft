//! Item 4: the executed review. A new agent session (codex, claude or gemini,
//! from `[papeis] revisao`) reviews a commit in an isolated checkout, from a
//! brief built into the binary. It fails closed: anything but a well-formed
//! verdict on its first line is an error, never an approval, and there is no
//! retry (rule 12).

use crate::config::Config;
use crate::fila;
use crate::git::{short, Repo, Snapshot, TempDir};
use crate::init::AGENTS;
use crate::medicao;
use crate::processo::{self, End};
use crate::refusal::{failed, Result};
use serde_json::json;
use std::fs::{self, File};
use std::process::{Command, Stdio};
use std::time::Instant;

const BRIEF: &str = include_str!("brief.md");
const MAX_DIFF: usize = 400_000;
const MAX_BATTERY: usize = 200_000;

pub struct Request<'a> {
    pub repo: &'a Repo,
    /// The base branch's config (item 1, rule 3).
    pub config: &'a Config,
    pub sha: String,
    pub base_sha: String,
    pub title: String,
    pub body: String,
    pub pr: Option<u64>,
    pub branch: String,
    /// Item 35: empty when there is no key; then it is not recorded.
    pub diff_sha256: String,
}

pub enum Verdict {
    Approve,
    Changes,
    Error(String),
}

pub struct Review {
    pub verdict: Verdict,
    pub blocking: u64,
    pub text: String,
    pub agent: String,
}

impl Review {
    pub fn state(&self) -> &'static str {
        match self.verdict {
            Verdict::Approve => "success",
            Verdict::Changes => "failure",
            Verdict::Error(_) => "error",
        }
    }

    pub fn description(&self) -> String {
        match &self.verdict {
            Verdict::Approve => format!("on this machine: APPROVE, Blocking 0 ({})", self.agent),
            Verdict::Changes => {
                format!("on this machine: CHANGES REQUESTED, Blocking {} ({})", self.blocking, self.agent)
            }
            Verdict::Error(why) => format!("on this machine: review error ({}): {why}", self.agent),
        }
    }
}

pub fn run(req: &Request) -> Result<Review> {
    let agent = req.config.papeis.revisao.clone();
    let started = Instant::now();
    let review = if AGENTS.contains(&agent.as_str()) {
        let _slot = fila::enter(fila::slots(req.config), &format!("{} ({}, review)", req.repo.name(), req.branch))?;
        execute(req, &agent)?
    } else {
        Review {
            verdict: Verdict::Error(format!("[roles] review = \"{agent}\" is not codex, claude or gemini")),
            blocking: 0,
            text: String::new(),
            agent: agent.clone(),
        }
    };
    let (resultado, codigo) = match &review.verdict {
        Verdict::Approve => ("passed", ""),
        Verdict::Changes => ("refused", "changes-requested"),
        Verdict::Error(_) => ("error", "reviewer-no-verdict"),
    };
    let mut row = json!({
        "layer": "review", "secs": medicao::seconds(started), "result": resultado, "code": codigo,
        "branch": req.branch, "commit": req.sha, "tokens": tokens(&review.text), "agent": agent, "pr": req.pr,
    });
    if !req.diff_sha256.is_empty() {
        row["diff_sha256"] = json!(req.diff_sha256);
    }
    medicao::record(req.repo, row);
    Ok(review)
}

fn execute(req: &Request, agent: &str) -> Result<Review> {
    let repo = req.repo;
    let work = TempDir::new("shipcraft-revisao")?;
    let tree = work.path().join("arvore");
    let tree_s = tree.to_string_lossy().into_owned();
    repo.run(&["worktree", "add", "-q", "--detach", &tree_s, &req.sha])?;
    let brief_path = work.path().join("brief.md");
    fs::write(&brief_path, brief(req, &tree_s, &work.path().to_string_lossy())?)
        .map_err(|e| failed(format!("write the brief: {e}")))?;
    let last = work.path().join("ultima-mensagem.md");
    let (out, err) = (work.path().join("saida.txt"), work.path().join("erros.txt"));
    let file = |p: &std::path::Path| File::create(p).map_err(|e| failed(format!("create {}: {e}", p.display())));
    let prompt = format!(
        "Read the review brief in the file {} and follow it. Your final message is the review, and its first line is the verdict.",
        brief_path.display()
    );
    let mut cmd = Command::new(agent);
    match agent {
        "codex" => cmd.args(["exec", "--skip-git-repo-check", "-C", &tree_s, "-s", "workspace-write"]).args([
            "-c",
            "sandbox_workspace_write.network_access=true",
            "-o",
            &last.to_string_lossy(),
            &prompt,
        ]),
        "claude" => cmd.args(["-p", "--permission-mode", "bypassPermissions", &prompt]),
        _ => cmd.args(["--yolo", "-p", &prompt]),
    };
    cmd.current_dir(&tree).stdin(Stdio::null()).stdout(file(&out)?).stderr(file(&err)?);
    let limit = req.config.revisao.tempo_max;
    eprintln!(
        "shipcraft: review by {agent} on this machine, in an isolated copy of {} (up to {limit} s)",
        short(&req.sha)
    );
    let end = processo::run(&mut cmd, limit);
    let _ = repo.run(&["worktree", "remove", "--force", &tree_s]);
    let _ = repo.run(&["worktree", "prune"]);
    let stdout = fs::read_to_string(&out).unwrap_or_default();
    let stderr = fs::read_to_string(&err).unwrap_or_default();
    let final_message = fs::read_to_string(&last).unwrap_or_default();
    let text = if final_message.trim().is_empty() { stdout.clone() } else { final_message };
    let all = format!("{stdout}\n{stderr}");
    let (verdict, blocking) = match end {
        Err(e) => (Verdict::Error(format!("could not start the reviewer: {}", stop_text(e))), 0),
        Ok(End::TimedOut) => (Verdict::Error(format!("timed out ({limit} s, [review] timeout)")), 0),
        Ok(End::Exited(0)) => parse(&text, &req.sha),
        Ok(End::Exited(code)) => {
            let last_line = stderr.lines().rev().find(|l| !l.trim().is_empty()).unwrap_or("").trim();
            (Verdict::Error(format!("the reviewer exited with code {code}: {last_line}")), 0)
        }
    };
    Ok(Review {
        verdict,
        blocking,
        text: format!("{}\n{}", text.trim_end(), token_line(&all)).trim_end().to_string(),
        agent: agent.to_string(),
    })
}

fn stop_text(stop: crate::refusal::Stop) -> String {
    match stop {
        crate::refusal::Stop::Failed(m) => m,
        crate::refusal::Stop::Refused(r) => r.to_string(),
    }
}

/// Item 4, rule 2: exactly `APPROVE at <sha>` or `CHANGES REQUESTED at <sha>`
/// on the very first line (the sha in full, or abbreviated to 7 or more
/// characters), and `Blocking: N` on the second. Anything else is an error.
fn parse(text: &str, sha: &str) -> (Verdict, u64) {
    let mut lines = text.lines().map(str::trim_end);
    let first = lines.next().unwrap_or("");
    let second = lines.next().unwrap_or("");
    let malformed = |line: &str| {
        let shown: String = line.chars().take(60).collect();
        (Verdict::Error(format!("malformed verdict: the first line is \"{shown}\"")), 0)
    };
    let (approve, at) = if let Some(at) = first.strip_prefix("APPROVE at ") {
        (true, at)
    } else if let Some(at) = first.strip_prefix("CHANGES REQUESTED at ") {
        (false, at)
    } else {
        return malformed(first);
    };
    if at.len() < 7 || !at.chars().all(|c| c.is_ascii_hexdigit()) {
        return malformed(first);
    }
    if !sha.starts_with(at) {
        return (Verdict::Error(format!("the verdict is for another commit ({at})")), 0);
    }
    let Some(blocking) = second.strip_prefix("Blocking: ").and_then(|n| n.parse::<u64>().ok()) else {
        return (Verdict::Error("malformed verdict: the second line is not \"Blocking: N\"".to_string()), 0);
    };
    match (approve, blocking) {
        (true, 0) => (Verdict::Approve, 0),
        (_, n) => (Verdict::Changes, n.max(1)),
    }
}

/// The tokens the reviewer reported ("tokens used: N", or N on the next line).
fn tokens(text: &str) -> Option<u64> {
    let at = text.rfind("tokens used")?;
    let digits: String = text[at + "tokens used".len()..]
        .chars()
        .skip_while(|c| *c == ':' || c.is_whitespace())
        .take_while(|c| c.is_ascii_digit() || *c == ',')
        .filter(char::is_ascii_digit)
        .collect();
    digits.parse().ok()
}

fn token_line(all: &str) -> String {
    tokens(all).map(|t| format!("\ntokens used: {t}")).unwrap_or_default()
}

fn brief(req: &Request, tree: &str, work: &str) -> Result<String> {
    let repo = req.repo;
    let diff = repo.text(&["diff", "--no-ext-diff", "--no-textconv", "--no-color", &req.base_sha, &req.sha])?;
    let spec = match &req.config.revisao.spec {
        Some(path) => match repo.read(&Snapshot::Commit(req.sha.clone()), path)? {
            Some(bytes) => format!("From `{path}`:\n\n{}", String::from_utf8_lossy(&bytes)),
            None => format!("`[review] spec` points at `{path}`, which is not in the head commit."),
        },
        None => {
            "The project names no spec (`[review] spec` in .shipcraft.toml): judge against the intent and the battery."
                .to_string()
        }
    };
    let commands: Vec<String> = req
        .config
        .suites()
        .iter()
        .map(|s| {
            let raiz = crate::suite::shell_quote(s.shown_root());
            match &s.verifica {
                Some(check) => format!("(cd {raiz} && {check} && {})", s.comando),
                None => format!("(cd {raiz} && {})", s.comando),
            }
        })
        .collect();
    let what = match req.pr {
        Some(n) => format!("pull request #{n}"),
        None => format!("the branch {} (before its pull request)", req.branch),
    };
    let body = if req.body.trim().is_empty() { "(the PR has no body)".to_string() } else { req.body.clone() };
    Ok(BRIEF
        .replace("{{WHAT}}", &what)
        .replace("{{PROJECT}}", &repo.name())
        .replace("{{TITLE}}", &req.title)
        .replace("{{SHA}}", &req.sha)
        .replace("{{BASE_SHA}}", &req.base_sha)
        .replace("{{TREE}}", tree)
        .replace("{{WORK}}", work)
        .replace("{{COMMANDS}}", &commands.join("\n"))
        .replace("{{MINUTES}}", &(req.config.revisao.tempo_max / 60).max(1).to_string())
        .replace("{{BODY}}", &body)
        .replace("{{SPEC}}", &spec)
        .replace("{{BATTERY}}", &battery(req)?)
        .replace("{{DIFF}}", &cap(&diff, MAX_DIFF)))
}

/// The test files of the head commit, whole up to a cap; past it, by name.
fn battery(req: &Request) -> Result<String> {
    let files = req.repo.text(&["ls-tree", "-r", "--name-only", &req.sha])?;
    let mut text = String::new();
    let mut left = Vec::new();
    for path in files.lines().filter(|p| req.config.is_test_file(p)) {
        let bytes = req.repo.read(&Snapshot::Commit(req.sha.clone()), path)?.unwrap_or_default();
        if text.len() + bytes.len() > MAX_BATTERY {
            left.push(path);
            continue;
        }
        text += &format!("### `{path}`\n\n```\n{}\n```\n\n", String::from_utf8_lossy(&bytes).trim_end());
    }
    if !left.is_empty() {
        text += &format!("Also in the battery (read them in the checkout): {}\n", left.join(", "));
    }
    Ok(if text.is_empty() { "(no test files)".to_string() } else { text })
}

fn cap(text: &str, max: usize) -> String {
    if text.len() <= max {
        return text.to_string();
    }
    let mut end = max;
    while !text.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}\n... (cut at {max} bytes: read the rest with git diff in the checkout)", &text[..end])
}
