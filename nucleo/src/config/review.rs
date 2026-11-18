//! `[review]` (items 87, 96, 102).

use super::version::min_reaches;
use super::{Config, CONFIG_FILE};
use crate::refusal::{refuse, Result};
use serde::Deserialize;

#[derive(Deserialize)]
#[serde(default)]
pub struct Revisao {
    pub spec: Option<String>,
    #[serde(rename = "timeout")]
    pub tempo_max: u64,
    /// Item 87: seconds between attempts after a `Please retry` failure; 0 is one attempt.
    pub retry_wait: u64,
    /// Item 96: `after` as written, any TOML value until `check_review_after`
    /// names a wrong one.
    #[serde(rename = "after")]
    pub(super) after_raw: Option<toml::Value>,
    /// Item 96: `[review] after = "push"`; `false` for `"ci"` and the absent key.
    #[serde(skip)]
    pub after_push: bool,
    /// Item 102: `[review] guide`, normalized; None when absent.
    #[serde(skip)]
    pub guide: Option<String>,
}

impl Default for Revisao {
    fn default() -> Self {
        Revisao { spec: None, tempo_max: 1200, retry_wait: 120, after_raw: None, after_push: false, guide: None }
    }
}

/// Item 87: any explicit `[review] retry_wait`, 0 included, needs 2.41, since
/// an older binary ignores the key and would reach another verdict.
pub(super) fn check_retry_wait(text: &str) -> Result<()> {
    let Ok(table) = text.parse::<toml::Table>() else { return Ok(()) };
    let Some(value) = table.get("review").and_then(|r| r.get("retry_wait")) else { return Ok(()) };
    if min_reaches(&table, "2.41") {
        return Ok(());
    }
    refuse(
        "config-invalid",
        format!("[review] retry_wait = {value} needs shipcraft_min = \"2.41\" or above"),
        "older binaries ignore this key, so they would try a review once and could reach another verdict",
        format!("set shipcraft_min = \"2.41\" (or above) in {CONFIG_FILE} and run again"),
    )
}

/// Item 96: `[review] after` is `"ci"` (the default) or `"push"`; any other
/// value refuses, and any explicit one needs 2.46, since an older binary
/// ignores the key. Returns whether it is `"push"`.
pub fn check_review_after(text: &str) -> Result<bool> {
    let Ok(table) = text.parse::<toml::Table>() else { return Ok(false) };
    let Some(value) = table.get("review").and_then(|r| r.get("after")) else { return Ok(false) };
    let push = match value.as_str() {
        Some("ci") => false,
        Some("push") => true,
        _ => {
            return refuse(
                "config-invalid",
                format!("[review] after = {value} is not \"ci\" or \"push\""),
                "the review starts after GitHub CI passed or beside it, and shipcraft does not guess which",
                format!("use after = \"ci\" or after = \"push\" under [review] in {CONFIG_FILE} and run again"),
            )
        }
    };
    if min_reaches(&table, "2.46") {
        return Ok(push);
    }
    refuse(
        "config-invalid",
        format!("[review] after = {value} needs shipcraft_min = \"2.46\" or above"),
        "older binaries ignore this key, so they would schedule the review differently",
        format!("set shipcraft_min = \"2.46\" (or above) in {CONFIG_FILE} and run again"),
    )
}

/// Item 102: the hook's early check of a staged config, as item 96's
/// `after`; it refuses for the guide only when no earlier check would, so
/// item 99's order holds.
pub fn check_review_guide(text: &str) -> Result<()> {
    if Config::parse_before_guide(text).is_ok() {
        crate::review_guide::check(text)?;
    }
    Ok(())
}
