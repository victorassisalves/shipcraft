//! The form of the config's paths and globs (items 30.1, 67).

use super::CONFIG_FILE;
use crate::refusal::{refuse, Result};

/// A path of the config without its `.` and empty parts; an absolute one, or
/// one with `..`, is an invalid config (item 30.1).
pub(super) fn normal_path(key: &str, value: &str) -> Result<String> {
    normal_form(value).or_else(|problem| invalid(key, value, problem))
}

/// Item 30.1's form of a path, or what is wrong with it.
fn normal_form(value: &str) -> std::result::Result<String, &'static str> {
    let parts: Vec<&str> = value.split('/').filter(|p| !p.is_empty() && *p != ".").collect();
    if value.starts_with('/') || parts.contains(&"..") {
        return Err("is outside the project");
    }
    Ok(parts.join("/"))
}

/// One glob in item 30.1's form, or what is wrong with it (item 67 reuses it
/// for `init --glob`).
pub fn normal_glob(value: &str) -> std::result::Result<String, &'static str> {
    match normal_form(value)? {
        empty if empty.is_empty() => Err("matches no files"),
        glob => Ok(glob),
    }
}

pub(super) fn normal_globs(key: &str, globs: &[String]) -> Result<Vec<String>> {
    globs.iter().map(|g| normal_glob(g).or_else(|problem| invalid(key, g, problem))).collect()
}

fn invalid<T>(key: &str, value: &str, problem: &str) -> Result<T> {
    refuse(
        "config-invalid",
        format!("{key} = \"{value}\" in {CONFIG_FILE} {problem}"),
        "the lock covers test files by their path within the project, and shipcraft does not guess another",
        format!("use a path relative to the project root in {key}, without `..`, and run again"),
    )
}
