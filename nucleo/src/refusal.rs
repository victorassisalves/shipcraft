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
    /// Item 153: the manual branch's paths, each put in place of a `\u{1}` in `how`
    /// after item 146's rewrite, so a path is printed as git printed it.
    verbatim: Vec<String>,
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

    /// Item 153: the refusal printed after all, its Next ending with `branch`, whose
    /// `\u{1}` marks take `paths` in order, past item 146's rewrite.
    pub fn branch(mut self, branch: &str, paths: Vec<String>) -> Refusal {
        self.how.push_str(branch);
        self.verbatim = paths;
        self.yields = false;
        self
    }
}

impl fmt::Display for Refusal {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        writeln!(f, "shipcraft refused: {}", self.what)?;
        writeln!(f, "Why: {}", self.why)?;
        let mut next = crate::inv::route(&self.how);
        for path in &self.verbatim {
            next = next.replacen('\u{1}', path, 1);
        }
        write!(f, "Next: {next}")
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
    Err(Stop::Refused(Refusal {
        code,
        what: what.into(),
        why: why.into(),
        how: how.into(),
        yields: false,
        verbatim: Vec::new(),
    }))
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
