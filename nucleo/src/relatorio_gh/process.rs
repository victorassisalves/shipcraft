//! Running `gh` in its own process group under the 60 s limit.

use crate::processo::kill_group;
use crate::relatorio::REPOSITORY_VARS;
use std::io::Read;
use std::os::unix::process::CommandExt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::sync::mpsc::{channel, TryRecvError};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

const LIMIT: Duration = Duration::from_secs(60);

/// Item 151: origin's repository at the root, read once per run before the first call.
static ORIGIN_REPO: OnceLock<Option<(String, String)>> = OnceLock::new();

pub(super) enum Ran {
    Out(Vec<u8>),
    Failed,
    TimedOut,
}

/// `gh <args>` at the root, in its own process group, stdin from /dev/null,
/// stderr discarded, without the repository-selecting git variables and with
/// no prompt, naming origin's repository (item 151). The limit covers its start, its output and its exit; at the
/// limit the group is killed and its output no longer waited for.
pub(super) fn run(root: &Path, args: &[&str]) -> Ran {
    let origin = ORIGIN_REPO.get_or_init(|| crate::origin_repo::read_quietly(root));
    let started = Instant::now();
    let mut command = Command::new("gh");
    command.args(args).current_dir(root).env("GH_PROMPT_DISABLED", "1");
    for var in REPOSITORY_VARS {
        command.env_remove(var);
    }
    if let Some((name, host)) = origin {
        command.env("GH_REPO", name).env("GH_HOST", host);
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
