//! Item 19: a PR that changes only text (`[pr] texto`) skips the build, the
//! `verifica` and the suites in `shipcraft ci --pr`; the history is still checked,
//! and `[pr] verifica_texto`, the project's cheap check of text, runs instead.

use crate::config::{Config, CONFIG_FILE};
use crate::git::{Repo, Snapshot, TempDir};
use crate::glob;
use crate::init::lefthook_source;
use crate::init_tool::{HUSKY, PRE_COMMIT_CONFIG};
use crate::lock::{lock_files, Lock};
use crate::processo::{self, End};
use crate::refusal::{failed, refuse, Result};
use std::fs::{self, File};
use std::io::{self, Write};
use std::process::Command;
use std::time::{Duration, Instant};

/// Whether every path from the merge-base of `base` and `head` to `head` is
/// a plain file that a `[pr] texto` glob matches and nothing protects. Any
/// doubt (no merge-base, a diff that does not read, no path) is not text
/// (rule 17), and neither is a head with an open lock.
pub fn so_texto(repo: &Repo, config: &Config, base: &str, head: &str) -> bool {
    if config.pr.texto.is_empty() {
        return false;
    }
    let Some(merge_base) = repo.try_text(&["merge-base", base, head]) else { return false };
    let Ok(raw) = repo.run(&["diff", "-z", "--raw", "--no-renames", &merge_base, head]) else { return false };
    let raw = String::from_utf8_lossy(&raw);
    let mut fields = raw.split('\0').filter(|f| !f.is_empty());
    let mut any = false;
    while let Some(meta) = fields.next() {
        let Some(path) = fields.next() else { return false };
        if !plain(meta) || !text(config, path) {
            return false;
        }
        any = true;
    }
    any && !open_lock(repo, head) && roots_exist(repo, config, head)
}

/// Item 19.1: each suite's `raiz`, without its `.` and empty parts, is a
/// chain of folders of HEAD's tree, each name equal byte for byte; no link,
/// file, submodule, missing path, `..` or absolute root. shipcraft resolves no path.
fn roots_exist(repo: &Repo, config: &Config, head: &str) -> bool {
    config.suites().iter().all(|suite| {
        if suite.raiz.starts_with('/') {
            return false;
        }
        let mut tree = format!("{head}^{{tree}}");
        for part in suite.raiz.split('/').filter(|p| !p.is_empty() && *p != ".") {
            let Ok(listing) = repo.run(&["ls-tree", "-z", &tree]) else { return false };
            let listing = String::from_utf8_lossy(&listing);
            let found = listing.split('\0').find_map(|entry| {
                let (meta, name) = entry.split_once('\t')?;
                let mut meta = meta.split(' ');
                (name == part && meta.nth(1) == Some("tree")).then(|| meta.next().map(str::to_string))?
            });
            match found {
                Some(sha) => tree = sha,
                None => return false,
            }
        }
        true
    })
}

/// A raw diff entry (`:<old mode> <new mode> <sha> <sha> <status>`) of a
/// regular file that kept its mode: no link, submodule, mode or type change.
fn plain(meta: &str) -> bool {
    let parts: Vec<&str> = meta.trim_start_matches(':').split(' ').collect();
    let regular = |mode: &str| ["000000", "100644", "100755"].contains(&mode);
    match parts.as_slice() {
        [old, new, _, _, status] => {
            regular(old)
                && regular(new)
                && (old == new || *old == "000000" || *new == "000000")
                && ["A", "D", "M"].contains(status)
        }
        _ => false,
    }
}

fn text(config: &Config, path: &str) -> bool {
    config.pr.texto.iter().any(|g| glob::matches(g, path)) && !protected(config, path)
}

/// The test and support files of any suite, `.shipcraft.toml`, `.shipcraft/` and the
/// lefthook's sources, at the root or in `.config/` (item 15a.2).
fn protected(config: &Config, path: &str) -> bool {
    let name = path.strip_prefix(".config/").unwrap_or(path).to_ascii_lowercase();
    config.is_test_file(path)
        || path == CONFIG_FILE
        || path.starts_with(".shipcraft/")
        || (!name.contains('/') && lefthook_source(&name))
        || path == PRE_COMMIT_CONFIG
        || HUSKY.iter().any(|(f, _)| path == *f)
}

fn open_lock(repo: &Repo, head: &str) -> bool {
    match lock_files(repo, &Snapshot::Commit(head.to_string())) {
        Ok(locks) => locks.values().any(|bytes| Lock::parse(bytes).is_none_or(|lock| lock.is_open())),
        Err(_) => true,
    }
}

/// `[pr] verifica_texto`, as the `verifica` runs: at the root of the judged
/// content (HEAD, on a copy when the tree is dirty), within what is left of
/// the CI's `tempo_max_ci` since `started`, so it ends before the `shipcraft pr`
/// that runs this CI stops it. Its output passes to stderr after it ends,
/// with its last line closed, so shipcraft's own lines stay whole.
pub fn verifica(repo: &Repo, config: &Config, head: &str, started: Instant) -> Result<()> {
    let Some(command) = &config.pr.verifica_texto else { return Ok(()) };
    let copy = if repo.dirty()? { Some(repo.export(&Snapshot::Commit(head.to_string()))?) } else { None };
    let dir = copy.as_ref().map_or(repo.root(), |c| c.path());
    let shown = command.split_whitespace().collect::<Vec<_>>().join(" ");
    let limit = config.execucao.tempo_max_ci;
    eprintln!("shipcraft: checking text ({shown})");
    let work = TempDir::new("shipcraft-texto")?;
    let log = work.path().join("saida.txt");
    let file = File::create(&log).map_err(|e| failed(format!("create {}: {e}", log.display())))?;
    let mut sh = Command::new("sh");
    sh.arg("-c")
        .arg(command)
        .current_dir(dir)
        .stdout(file.try_clone().map_err(|e| failed(e.to_string()))?)
        .stderr(file);
    let end = processo::run_for(&mut sh, Duration::from_secs(limit).saturating_sub(started.elapsed()));
    let mut said = fs::read(&log).unwrap_or_default();
    if said.last().is_some_and(|b| *b != b'\n') {
        said.push(b'\n');
    }
    let _ = io::stderr().write_all(&said);
    let what = match end? {
        End::Exited(0) => return Ok(()),
        End::Exited(code) => format!("`{shown}` exited with {code}"),
        End::TimedOut => format!("`{shown}` did not finish in {limit} s, [execution] ci_timeout"),
    };
    refuse(
        "text-check-failed",
        format!("text_check failed ({what})"),
        "in a text-only PR the suite does not run; the project text check judges the content",
        format!("run `{shown}` at the root and fix the text"),
    )
}
