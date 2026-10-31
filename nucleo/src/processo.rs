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
