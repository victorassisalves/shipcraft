//! shipcraft, the Shipcraft v2 core (docs/spec.md).
//!
//! It guarantees that the GREEN cannot make the suite pass by changing, deleting
//! or skipping the tests the RED locked, nor the config that says how they run;
//! and that every PR goes through the CI and an executed review before the merge.

mod check;
mod ci;
mod config;
mod contract;
mod fecha;
mod fila;
mod forma;
mod gh;
mod git;
mod glob;
mod init;
mod init_msg;
mod init_tool;
mod jsonc;
mod junit;
mod lang;
mod lock;
mod marca;
mod medicao;
mod merge;
mod pr;
mod processo;
mod red;
mod refusal;
mod revisao;
mod suite;
mod tsbuild;

use git::Repo;
use refusal::{Result, Stop};
use std::process::ExitCode;
use std::time::Instant;

const USAGE: &str =
    "usage: shipcraft --version | shipcraft init [--lang python|node|go] [--github] | shipcraft red | shipcraft check [--commit-msg <file>] | shipcraft close
     | shipcraft ci --base <ref> [--pr]
     | shipcraft pr [--title <t>] [--body <file>] | shipcraft review [--pr <n>]
     | shipcraft merge <pr> [--no-review \"<reason>\"] | shipcraft status";

fn main() -> ExitCode {
    // Item 22.2: the lists reach only the hook's suite, never a value inherited.
    for var in suite::LIST_VARS {
        std::env::remove_var(var);
    }
    let args: Vec<String> = std::env::args().skip(1).collect();
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(Stop::Refused(refusal)) => {
            eprintln!("{refusal}");
            ExitCode::from(1)
        }
        Err(Stop::Failed(message)) => {
            eprintln!("shipcraft: error: {message}");
            ExitCode::from(2)
        }
    }
}

fn run(args: &[&str]) -> Result<()> {
    match args {
        ["init", rest @ ..] => {
            let mut lang = None;
            let mut github = false;
            let mut rest = rest.iter();
            while let Some(arg) = rest.next() {
                match *arg {
                    "--lang" => lang = Some(*rest.next().ok_or_else(|| invalid(args))?),
                    "--github" => github = true,
                    _ => return Err(invalid(args)),
                }
            }
            init::run(&init::open()?, lang, github)
        }
        ["red"] => red::run(&Repo::open()?),
        ["check"] => measured("hook", |repo| check::run(repo, false)),
        // The git hook passes the message file, which is ignored.
        ["check", "--commit-msg", ..] => measured("hook", |repo| check::run(repo, true)),
        ["close"] => {
            fecha::run();
            Ok(())
        }
        // `--pr` is still accepted (older callers pass it); it no longer changes anything.
        ["ci", "--base", base] | ["ci", "--base", base, "--pr"] => measured("ci", |repo| ci::run(repo, base)),
        ["pr", rest @ ..] => {
            let (mut title, mut body) = (None, None);
            let mut rest = rest.iter();
            while let Some(arg) = rest.next() {
                match *arg {
                    "--title" => title = Some(*rest.next().ok_or_else(|| invalid(args))?),
                    "--body" => body = Some(*rest.next().ok_or_else(|| invalid(args))?),
                    _ => return Err(invalid(args)),
                }
            }
            pr::pr(&Repo::open()?, title, body)
        }
        ["review"] => pr::local(&Repo::open()?),
        ["review", "--pr", n] => pr::of_pr(&Repo::open()?, n),
        ["merge", n] => merge::merge(&Repo::open()?, n, None),
        ["merge", n, "--no-review", motivo] => merge::merge(&Repo::open()?, n, Some(motivo)),
        ["status"] => merge::status(&Repo::open()?),
        // Item 23: records no row, as `init`, `red` and `fecha`.
        // Item 21.1: any folder, no repository nor .shipcraft.toml needed.
        ["--version"] => {
            println!("{}", version_line());
            Ok(())
        }
        [] | ["help" | "-h" | "--help"] => {
            println!("{USAGE}");
            Ok(())
        }
        _ => Err(invalid(args)),
    }
}

fn version_line() -> String {
    format!("shipcraft {} ({})", config::VERSION, env!("SHIPCRAFT_COMMIT"))
}

fn invalid(args: &[&str]) -> Stop {
    refusal::failed(format!("invalid arguments: {}; {USAGE}", args.join(" ")))
}

/// Runs a hook or CI command and records it in the measurement (item 10).
fn measured(camada: &str, command: impl FnOnce(&Repo) -> Result<()>) -> Result<()> {
    let started = Instant::now();
    let repo = Repo::open()?;
    let result = command(&repo);
    medicao::layer(&repo, camada, started, &result);
    result
}

#[cfg(test)]
mod tests {
    #[test]
    fn version_line_is_numeric_version_and_commit() {
        let line = super::version_line();
        let (version, commit) = line["shipcraft ".len()..].split_once(" (").unwrap();
        let parts: Vec<&str> = version.split('.').collect();
        assert_eq!(parts.len(), 3, "{line}");
        assert!(parts.iter().all(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit())), "{line}");
        let commit = commit.strip_suffix(')').unwrap();
        assert!(commit == "no-git" || (commit.len() == 12 && commit.bytes().all(|b| b.is_ascii_hexdigit())), "{line}");
    }
}
