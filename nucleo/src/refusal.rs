//! How shipcraft stops: a refusal (the core says no, exit 1) or a failure (shipcraft could
//! not do its job, exit 2).

use std::fmt;

/// A refusal is three lines (rule 7): what happened, why (the practice), how to go on.
/// The code names the refusal in the measurement (`.git/shipcraft/runs.jsonl`).
#[derive(Debug)]
pub struct Refusal {
    pub code: &'static str,
    what: String,
    why: String,
    how: String,
    /// Item 153: the hand-wired route may replace this refusal (see `init::hand`).
    yields: bool,
}

impl Refusal {
    /// What happened: the first of the three lines, without its prefix.
    pub fn what(&self) -> &str {
        &self.what
    }

    /// How to go on: the third line, without its prefix.
    pub fn how(&self) -> &str {
        &self.how
    }

    /// Item 153: whether hooks wired by hand replace this refusal.
    pub fn yields(&self) -> bool {
        self.yields
    }
}

impl fmt::Display for Refusal {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        writeln!(f, "shipcraft refused: {}", self.what)?;
        writeln!(f, "Why: {}", self.why)?;
        write!(f, "Next: {}", crate::inv::route(&self.how))
    }
}

#[derive(Debug)]
pub enum Stop {
    Refused(Refusal),
    Failed(String),
}

pub type Result<T> = std::result::Result<T, Stop>;

pub fn refuse<T>(
    code: &'static str,
    what: impl Into<String>,
    why: impl Into<String>,
    how: impl Into<String>,
) -> Result<T> {
    Err(Stop::Refused(Refusal { code, what: what.into(), why: why.into(), how: how.into(), yields: false }))
}

/// Item 153: a refusal that hooks wired by hand replace (point 2).
pub fn refuse_yielding<T>(code: &'static str, what: String, why: &str, how: String) -> Result<T> {
    refuse(code, what, why, how).map_err(|stop| match stop {
        Stop::Refused(r) => Stop::Refused(Refusal { yields: true, ..r }),
        other => other,
    })
}

/// Item 153: a stop that no hook by hand gets past (point 2's refusals that do not yield).
pub fn firm(stop: Stop) -> Stop {
    match stop {
        Stop::Refused(r) => Stop::Refused(Refusal { yields: false, ..r }),
        other => other,
    }
}

pub fn failed(message: impl Into<String>) -> Stop {
    Stop::Failed(message.into())
}

/// A short list for a one-line message: the first three items and how many more.
pub fn short_list<S: AsRef<str>>(items: &[S]) -> String {
    let shown: Vec<&str> = items.iter().take(3).map(AsRef::as_ref).collect();
    match items.len() {
        n if n > 3 => format!("{} and {} more", shown.join(", "), n - 3),
        _ => shown.join(", "),
    }
}
