//! shipcraft, the Shipcraft v2 core (docs/spec.md).
//!
//! It guarantees that the GREEN cannot make the suite pass by changing, deleting
//! or skipping the tests the RED locked, nor the config that says how they run;
//! and that every PR goes through the CI and an executed review before the merge.

mod check;
mod ci;
mod config;
mod contract;
mod docs;
mod fecha;
mod fila;
mod forma;
mod gh;
mod git;
mod glob;
mod init;
mod init_briefs;
mod init_msg;
mod init_probe;
mod init_tool;
mod install;
mod jsonc;
mod junit;
mod lang;
mod lock;
mod marca;
mod medicao;
mod merge;
mod narrow;
mod pr;
mod processo;
mod red;
mod refusal;
mod relatorio;
mod revisao;
mod suite;
mod tsbuild;

use git::Repo;
use refusal::{Result, Stop};
use std::process::ExitCode;
use std::time::Instant;

const USAGE: &str =
    "usage: shipcraft --version | shipcraft init [--lang python|node|go] [--github]
     | shipcraft init --lang other --command <cmd> --glob <glob>... [--github]
     | shipcraft red [--redo] [--base <ref>] [--all] [--fix [--reported-at <time>] [--fixes-release <tag>]]
     | shipcraft check [--commit-msg <file>] | shipcraft close
     | shipcraft ci --base <ref> [--pr]
     | shipcraft pr [--title <t>] [--body <file>] | shipcraft review [--pr <n>]
     | shipcraft merge <pr> [--no-review \"<reason>\"] | shipcraft status | shipcraft report [--json]";

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
            // Item 67: syntax first (exit 2): `--lang` and `--command` once each, every
            // flag with a value, and a value that starts with `--` is a missing one.
            let mut options = init::Options::default();
            let mut rest = rest.iter();
            while let Some(arg) = rest.next() {
                let mut value = || match rest.next() {
                    Some(v) if !v.starts_with("--") => Ok(*v),
                    _ => Err(invalid(args)),
                };
                match *arg {
                    "--lang" if options.lang.is_none() => options.lang = Some(value()?),
                    "--command" if options.command.is_none() => options.command = Some(value()?),
                    "--glob" => options.globs.push(value()?),
                    "--github" => options.github = true,
                    _ => return Err(invalid(args)),
                }
            }
            init::run(&init::open()?, &options)
        }
        ["red", rest @ ..] => {
            // Item 55: each option once, in any order; item 60: `--redo` takes the others too.
            // Item 75: `--fix`, and `--reported-at` and `--fixes-release` only with it,
            // never with `--redo`; each value in its grammar.
            let (mut redo, mut all, mut base) = (false, false, None);
            let (mut fix, mut reported_at, mut fixes_release) = (false, None, None);
            let mut rest = rest.iter();
            while let Some(arg) = rest.next() {
                match *arg {
                    "--redo" if !redo => redo = true,
                    "--all" if !all => all = true,
                    "--base" if base.is_none() => base = Some(*rest.next().ok_or_else(|| invalid(args))?),
                    "--fix" if !fix => fix = true,
                    "--reported-at" if reported_at.is_none() => {
                        reported_at = Some(rest.next().filter(|v| lock::valid_time(v)).ok_or_else(|| invalid(args))?)
                    }
                    "--fixes-release" if fixes_release.is_none() => {
                        fixes_release = Some(rest.next().filter(|v| lock::valid_tag(v)).ok_or_else(|| invalid(args))?)
                    }
                    _ => return Err(invalid(args)),
                }
            }
            if (redo && (fix || reported_at.is_some() || fixes_release.is_some()))
                || (!fix && (reported_at.is_some() || fixes_release.is_some()))
            {
                return Err(invalid(args));
            }
            let fix = lock::Fix {
                kind: if fix { lock::Kind::Fix } else { lock::Kind::Feature },
                reported_at: reported_at.map(|v| v.to_string()),
                fixes_release: fixes_release.map(|v| v.to_string()),
            };
            // Item 38: a lock written, or a refusal, is a row.
            let started = Instant::now();
            let repo = Repo::open()?;
            let mut chosen = None;
            if redo {
                // Item 46: every redo is a `red` row with `redo: true` and HEAD's lock id.
                let (mut path, mut dropped, mut left) = (None, None, None);
                let result = red::redo(&repo, base, all, &mut path, &mut dropped, &mut chosen, &mut left);
                let mut row = medicao::row(&repo, "red", started, &result);
                row["redo"] = true.into();
                if let Some(path) = &path {
                    row["lock"] = medicao::lock_id(path).into();
                }
                if let Some(dropped) = dropped {
                    row["rerun_dropped"] = dropped.into();
                }
                // Item 81: only when the lock was written.
                if let Some(left) = &left {
                    left.record(&mut row);
                }
                if let Some(chosen) = &chosen {
                    chosen.record(&mut row);
                }
                medicao::record(&repo, row);
                return result;
            }
            let fields = [
                ("kind", serde_json::Value::from(fix.kind.as_str())),
                ("reported_at", fix.reported_at.clone().into()),
                ("fixes_release", fix.fixes_release.clone().into()),
            ];
            let result = red::run(&repo, base, all, fix, &mut chosen);
            let mut row = medicao::row(&repo, "red", started, &result);
            // Item 75: every non-redo row carries the fix fields.
            for (key, value) in fields {
                row[key] = value;
            }
            if let Ok((path, dropped, left)) = &result {
                row["lock"] = medicao::lock_id(path).into();
                // Item 53: how many cases the second run did not lock.
                row["rerun_dropped"] = (*dropped).into();
                // Item 81: the cases left out, or null when the base tree was unread.
                left.record(&mut row);
            }
            // Item 55: how the first run was chosen, once it was decided.
            if let Some(chosen) = &chosen {
                chosen.record(&mut row);
            }
            medicao::record(&repo, row);
            result.map(drop)
        }
        ["check"] => measured("hook", |repo, _| check::run(repo, false)),
        // The git hook passes the message file, which is ignored.
        ["check", "--commit-msg", ..] => measured("hook", |repo, _| check::run(repo, true)),
        ["close"] => {
            fecha::run();
            Ok(())
        }
        // Item 40: only `--pr` allows the docs-only path.
        ["ci", "--base", base] => measured("ci", |repo, row| ci::run(repo, base, false, row)),
        ["ci", "--base", base, "--pr"] => measured("ci", |repo, row| ci::run(repo, base, true, row)),
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
        // Item 38: reads only the run log; never refuses.
        ["report"] => relatorio::run(false),
        ["report", "--json"] => relatorio::run(true),
        // Item 23: records no row, as `init`.
        // Item 21.1: any folder, no repository nor .shipcraft.toml needed.
        ["--version"] => {
            println!("{}", version_line());
            setup_hint();
            Ok(())
        }
        [] | ["help" | "-h" | "--help"] => {
            println!("{USAGE}");
            setup_hint();
            Ok(())
        }
        _ => Err(invalid(args)),
    }
}

fn version_line() -> String {
    format!("shipcraft {} ({})", config::VERSION, env!("SHIPCRAFT_COMMIT"))
}

/// Items 61 and 69: inside a git work tree whose root has no `.shipcraft.toml`
/// (lstat not-found only), one stderr line says `init` is the required next step;
/// it reads no config.
fn setup_hint() {
    let Ok(cwd) = std::env::current_dir() else { return };
    let Ok(out) = git::git_in(&cwd, &["rev-parse", "--show-toplevel"]) else { return };
    // The root's own bytes, less the one newline git ends it with.
    let root = out.stdout.strip_suffix(b"\n").unwrap_or(&out.stdout);
    if !out.status.success() || root.is_empty() {
        return;
    }
    let root = <std::ffi::OsStr as std::os::unix::ffi::OsStrExt>::from_bytes(root);
    if std::path::Path::new(root)
        .join(config::CONFIG_FILE)
        .symlink_metadata()
        .is_err_and(|e| e.kind() == std::io::ErrorKind::NotFound)
    {
        let root = std::path::Path::new(root);
        eprintln!(
            "shipcraft: next step (required): run `{}` at the repository root to set up Shipcraft; until init runs, Shipcraft checks none of your commits; if init refuses, follow its Next line",
            init_command(root)
        );
    }
}

/// Item 69: the one `init` command the hint names. The project's install (item
/// 58's rule) gets `pnpm exec` when a regular `pnpm-lock.yaml` sits at the root
/// and `pnpm` is on `PATH`, `npx --` otherwise; anything else is `shipcraft init`.
fn init_command(root: &std::path::Path) -> &'static str {
    if !matches!(init::install_at(root), init::Install::Project) {
        return "shipcraft init";
    }
    let lock = root.join("pnpm-lock.yaml").symlink_metadata().is_ok_and(|m| m.file_type().is_file());
    if lock && init::on_path("pnpm") {
        "pnpm exec shipcraft init"
    } else {
        "npx -- shipcraft init"
    }
}

fn invalid(args: &[&str]) -> Stop {
    refusal::failed(format!("invalid arguments: {}; {USAGE}", args.join(" ")))
}

/// Runs a hook or CI command and records it in the measurement (item 10);
/// a CI row says whether the PR was docs only (item 40) and whether the suite
/// was left to the GitHub checks (item 62).
fn measured(camada: &str, command: impl FnOnce(&Repo, &mut medicao::CiRow) -> Result<()>) -> Result<()> {
    let started = Instant::now();
    let repo = Repo::open()?;
    let lock = (camada == "hook").then(|| medicao::open_lock(&repo));
    let mut ci = medicao::CiRow::default();
    let result = command(&repo, &mut ci);
    medicao::layer(&repo, camada, started, &result, (camada == "ci").then_some(ci), lock);
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
