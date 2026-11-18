//! `shipcraft_min` and version numbers (item 9).

use super::VERSION;
use crate::refusal::{refuse, Result};

/// The English config contract requires this binary's major/minor version.
pub fn minimum_version() -> String {
    VERSION.split('.').take(2).collect::<Vec<_>>().join(".")
}

/// `shipcraft_min` is a well-formed version at `floor` or above.
pub fn min_reaches(table: &toml::Table, floor: &str) -> bool {
    table.get("shipcraft_min").and_then(|v| v.as_str()).is_some_and(|m| {
        let runs: Vec<&str> = m.split('.').collect();
        (2..=3).contains(&runs.len())
            && runs.iter().all(|r| !r.is_empty() && r.bytes().all(|b| b.is_ascii_digit()))
            && version_parts(m) >= version_parts(floor)
    })
}

/// Item 9, rule 2: an shipcraft older than `shipcraft_min` refuses instead of judging.
pub fn check_min(text: &str) -> Result<()> {
    let Ok(table) = text.parse::<toml::Table>() else { return Ok(()) };
    let Some(min) = table.get("shipcraft_min").and_then(|v| v.as_str()) else { return Ok(()) };
    if version_parts(min) <= version_parts(VERSION) {
        return Ok(());
    }
    refuse(
        "shipcraft-min",
        format!(".shipcraft.toml requires shipcraft {min} or newer, and this is {VERSION}"),
        "two machines cannot judge the same commit differently without warning",
        format!("update shipcraft to version {min} or newer and run again"),
    )
}

/// Splits a version into numbers, trailing zeros dropped, so 2.0 and 2.0.0 compare equal.
pub fn version_parts(v: &str) -> Vec<u64> {
    let mut parts: Vec<u64> = v.split('.').map(|p| p.trim().parse().unwrap_or(0)).collect();
    while parts.last() == Some(&0) {
        parts.pop();
    }
    parts
}
