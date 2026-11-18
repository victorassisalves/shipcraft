//! `init --lang other`'s command and globs (item 67).

use super::{Options, OTHER_FORM};
use crate::refusal::{refuse, Result};
use crate::suite::shell_quote;

/// Item 67: a suite Shipcraft runs as written; its command and normalized globs.
pub(super) struct Custom {
    pub(super) command: String,
    pub(super) globs: Vec<String>,
}

/// Item 67: `--command` and `--glob` belong to `--lang other`, which needs both;
/// the command (step 3) is judged before the globs (step 4, the first invalid
/// one in argument order). Kept configs do not skip this.
pub(super) fn custom(options: &Options) -> Result<Option<Custom>> {
    let other_refusal = |what: String| {
        refuse(
            "lang-unknown",
            what,
            "shipcraft runs a test command it does not know as written: it needs the command, {junit} where it writes its JUnit report, and the test files",
            OTHER_FORM,
        )
    };
    if options.lang != Some("other") {
        let given = match (options.command.is_some(), !options.globs.is_empty()) {
            (true, true) => "--command and --glob",
            (true, false) => "--command",
            (false, true) => "--glob",
            (false, false) => return Ok(None),
        };
        return other_refusal(format!("{given} given without --lang other"));
    }
    let Some(command) = options.command else {
        return other_refusal("--lang other needs --command".to_string());
    };
    if options.globs.is_empty() {
        return other_refusal("--lang other needs at least one --glob".to_string());
    }
    if let Some(problem) = command_problem(command) {
        return other_refusal(format!("the --command value {problem}"));
    }
    let mut globs: Vec<String> = Vec::new();
    for glob in &options.globs {
        match crate::config::normal_glob(glob) {
            Ok(normal) if globs.contains(&normal) => {}
            Ok(normal) => globs.push(normal),
            Err(problem) => {
                return refuse(
                    "config-invalid",
                    format!("--glob {} {problem}", shell_quote(&crate::red::one_line(glob))),
                    "the lock covers test files by their path within the project, and shipcraft does not guess another",
                    OTHER_FORM,
                )
            }
        }
    }
    Ok(Some(Custom { command: command.to_string(), globs }))
}

/// What breaks item 67's rules for `--command`, if anything.
fn command_problem(command: &str) -> Option<&'static str> {
    if command.matches("{junit}").count() != 1 {
        return Some("must contain {junit} exactly once");
    }
    if command.replacen("{junit}", "", 1).chars().all(char::is_whitespace) {
        return Some("has nothing but whitespace besides {junit}");
    }
    if command.chars().any(char::is_control) {
        return Some("has a control character");
    }
    None
}
