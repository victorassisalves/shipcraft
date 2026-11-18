//! Item 79: `report --github`, the selected locks' waiting and merge times
//! asked of GitHub through `gh`. Separate from gh.rs's readers: every call has
//! a 60 s limit in its own process group, its outcome is reused by argument
//! list, and a failure is a `missing` reason, never a refusal nor printed text.

use serde_json::Value;

mod answers;
mod asker;
mod blocking;
mod checks;
mod process;

pub use answers::oid;
pub use asker::Asker;

const FAILED: &str = "gh failed";
const UNREADABLE: &str = "unreadable answer from gh";
const TIMED_OUT: &str = "gh timed out";

/// The PR a lock went through, from the run log.
pub enum Pr {
    None,
    Several,
    One(u64),
}

/// A call's outcome: its answer, or the reason it gives.
type Outcome = Result<Value, &'static str>;

#[cfg(test)]
mod tests;
