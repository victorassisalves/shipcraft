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
            let _ = Command::new("sh").arg("-c").arg(format!("kill -KILL -- -{} 2>/dev/null", child.id())).status();
            let _ = child.kill();
            let _ = child.wait();
            return Ok(End::TimedOut);
        }
        sleep(Duration::from_millis(100));
    }
}
