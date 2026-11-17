//! Running a child with a time limit: in its own process group, so the whole
//! group (the runner and everything it started) stops when time runs out.

use crate::refusal::{failed, Result};
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::process::Command;
use std::thread::sleep;
use std::time::{Duration, Instant};

pub enum End {
    /// The exit code; a child killed by a signal counts as the shell does (128 + signal).
    Exited(i32),
    TimedOut,
}

pub fn run(cmd: &mut Command, limit_secs: u64) -> Result<End> {
    run_for(cmd, Duration::from_secs(limit_secs))
}

pub fn run_for(cmd: &mut Command, limit: Duration) -> Result<End> {
    let mut child = cmd.process_group(0).spawn().map_err(|e| failed(format!("start {:?}: {e}", cmd.get_program())))?;
    let started = Instant::now();
    loop {
        if let Some(status) = child.try_wait().map_err(|e| failed(format!("wait for the process: {e}")))? {
            return Ok(End::Exited(status.code().unwrap_or_else(|| 128 + status.signal().unwrap_or(0))));
        }
        if started.elapsed() >= limit {
            // Kill the whole group shipcraft created at spawn, by system call: a shell `kill -- -pgid` is not
            // understood by every /bin/sh (dash), and then the group survived the timeout.
            if let Err(e) = kill_group(child.id()) {
                eprintln!("shipcraft: could not stop the process group {}: {e}", child.id());
            }
            let _ = child.kill();
            let _ = child.wait();
            return Ok(End::TimedOut);
        }
        sleep(Duration::from_millis(100));
    }
}

extern "C" {
    fn killpg(pgrp: i32, sig: i32) -> i32;
}

const SIGKILL: i32 = 9;
const ESRCH: i32 = 3;

/// SIGKILL to the process group `pgid`. A group that is already gone is not an error.
pub(crate) fn kill_group(pgid: u32) -> std::io::Result<()> {
    // SAFETY: killpg only reads its two integer arguments.
    if unsafe { killpg(pgid as i32, SIGKILL) } == 0 {
        return Ok(());
    }
    let err = std::io::Error::last_os_error();
    if err.raw_os_error() == Some(ESRCH) {
        Ok(())
    } else {
        Err(err)
    }
}

/// How a child whose stdout is read ended (item 115's `curl`).
pub enum Captured {
    /// The child could not be started.
    NotStarted,
    /// Still running at the limit: its group was killed.
    TimedOut,
    /// Ended by this signal.
    Signal(i32),
    /// Exited with this code; the stdout read in full, `None` when reading
    /// it or waiting for the child failed.
    Exited(i32, Option<Vec<u8>>),
    /// Waiting for the child failed.
    WaitFailed,
}

/// Runs `cmd` in its own process group with its stdout read in full; the
/// group is killed when the child (or what holds its stdout) is still
/// running after `limit`. Stdin and stderr are the caller's to set.
pub fn run_capture(cmd: &mut Command, limit: Duration) -> Captured {
    let spawned = cmd.process_group(0).stdout(std::process::Stdio::piped()).spawn();
    let Ok(mut child) = spawned else { return Captured::NotStarted };
    let started = Instant::now();
    let (send, read) = std::sync::mpsc::channel();
    let stdout = child.stdout.take();
    std::thread::spawn(move || {
        let mut bytes = Vec::new();
        let ok = match stdout {
            Some(mut out) => std::io::Read::read_to_end(&mut out, &mut bytes).is_ok(),
            None => false,
        };
        let _ = send.send(ok.then_some(bytes));
    });
    let stop = |child: &mut std::process::Child| {
        let _ = kill_group(child.id());
        let _ = child.kill();
        let _ = child.wait();
    };
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) => {}
            Err(_) => {
                stop(&mut child);
                return Captured::WaitFailed;
            }
        }
        if started.elapsed() >= limit {
            stop(&mut child);
            return Captured::TimedOut;
        }
        sleep(Duration::from_millis(10));
    };
    // The child exited; what it started may still hold its stdout open.
    let out = match read.recv_timeout(limit.saturating_sub(started.elapsed())) {
        Ok(out) => out,
        Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
            let _ = kill_group(child.id());
            return Captured::TimedOut;
        }
        Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => None,
    };
    match (status.code(), status.signal()) {
        (Some(code), _) => Captured::Exited(code, out),
        (None, Some(signal)) => Captured::Signal(signal),
        (None, None) => Captured::WaitFailed,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sh(script: &str, limit: Duration) -> Captured {
        run_capture(Command::new("sh").args(["-c", script]).stdin(std::process::Stdio::null()), limit)
    }

    #[test]
    fn run_capture_reads_stdout_and_ends() {
        let long = Duration::from_secs(10);
        assert!(matches!(sh("printf 'x\\n404'", long), Captured::Exited(0, Some(out)) if out == b"x\n404"));
        assert!(matches!(sh("exit 6", long), Captured::Exited(6, _)));
        assert!(matches!(sh("kill -TERM $$", long), Captured::Signal(15)));
        assert!(matches!(
            run_capture(&mut Command::new("/nonexistent/shipcraft-no-such-program"), long),
            Captured::NotStarted
        ));
        let started = Instant::now();
        assert!(matches!(sh("sleep 5", Duration::from_millis(200)), Captured::TimedOut));
        // A child left holding stdout after the shell exits is killed with the group.
        assert!(matches!(sh("sleep 5 & exit 0", Duration::from_millis(300)), Captured::TimedOut));
        assert!(started.elapsed() < Duration::from_secs(3));
    }
}
