//! The `.shipcraft.toml` text `init` writes, and the review agent it names (items 2, 62, 67, 71, 107).

use super::custom::Custom;
use super::files::on_path;
use crate::config::minimum_version;
use crate::lang::{Lang, Profile};

pub const AGENTS: [&str; 3] = ["codex", "claude", "gemini"];

const HEADER: &str = "\
# shipcraft: how the suite runs and where each layer runs. Changing this file with an
# open lock is refused. In test_command (and command), {junit} becomes the
# path where the runner writes its JUnit report. Optional check checks the
# whole project before tests: it runs in shipcraft ci and RED, never in the hook.
";

/// Review is on by default with the first agent installed, and off when none
/// is; init asks nothing, and either way the change is one line.
pub(super) fn reviewer() -> Option<String> {
    AGENTS.into_iter().find(|a| on_path(a)).map(str::to_string)
}

fn quoted(s: &str) -> String {
    toml::Value::String(s.to_string()).to_string()
}

pub(super) fn config_text(
    lang: Option<Lang>,
    custom: Option<&Custom>,
    suites: &[(String, String, Profile)],
    named: bool,
    reviewer: &Option<String>,
    build: Option<&str>,
) -> String {
    let globs = |p: &Profile| {
        toml::Value::Array(p.globs.iter().map(|g| toml::Value::String(g.to_string())).collect()).to_string()
    };
    let check = |p: &Profile| p.check.as_ref().map_or(String::new(), |c| format!("check = {}\n", quoted(c)));
    let min = minimum_version();
    let mut text = format!("{HEADER}shipcraft_min = {}\n", quoted(&min));
    if let Some(lang) = lang {
        text += &format!("lang = {}\n", quoted(lang.name()));
    }
    // Item 67: no lang, runner, check or [build]; the command filters itself.
    if let Some(custom) = custom {
        let globs = toml::Value::Array(custom.globs.iter().map(|g| toml::Value::String(g.clone())).collect());
        text += &format!("test_command = {}\ntest_globs = {globs}\nfilter = \"command\"\n", quoted(&custom.command));
    }
    if let [(_, raiz, profile)] = suites {
        if raiz == "." && !named {
            text += &format!(
                "runner = {}\n{}test_command = {}\ntest_globs = {}\n",
                quoted(profile.runner),
                check(profile),
                quoted(&profile.command),
                globs(profile)
            );
        }
    }
    let review = if reviewer.is_some() { "local" } else { "off" };
    // Item 62: what each value means, and that suite_checks moves the suite
    // out of shipcraft/ci; above the table, and no suite_checks written.
    text += "\n# where each layer runs: \"local\" = on this machine, started by shipcraft pr; \"github\" = in this
# project's GitHub Actions (docs/github-ci.md); \"off\" = it does not run and shipcraft merge does not
# require it. shipcraft/ci re-checks every commit of the PR and runs the suite at its HEAD,
# unless suite_checks names GitHub checks that run the suite (docs/github-ci.md).
";
    text += &format!("[execution]\nci = \"local\"\nreview = \"{review}\"\nci_timeout = 1800\n");
    text += &format!(
        "\n[roles]\n# the review agent: codex, claude or gemini\nreview = {}\n",
        quoted(reviewer.as_deref().unwrap_or("codex"))
    );
    text +=
        "\n[review]\n# seconds; optional project spec included in the brief: spec = \"docs/spec.md\"\ntimeout = 1200\n";
    // Item 107: the default size limit, in every config init writes.
    text += "\n[pr]\n# product lines above which the PR body and the PR summary suggest a split; a line, never a refusal\nwarn_lines = 500\n";
    if let Some(command) = build {
        text += &format!(
            "\n[build]\n# runs once at the root, before suites, in shipcraft ci and shipcraft red\ncommand = {}\n",
            quoted(command)
        );
    }
    // Item 71: a converted suite keeps the [[suite]] form, even alone at root ".".
    if named || suites.len() > 1 || suites.first().is_some_and(|s| s.1 != ".") {
        for (nome, raiz, profile) in suites {
            text += &format!(
                "\n[[suite]]\nname = {}\nroot = {}\n{}command = {}\nglobs = {}\n",
                quoted(nome),
                quoted(raiz),
                check(profile),
                quoted(&profile.command),
                globs(profile)
            );
        }
    }
    text
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn config_text_writes_the_size_limit_after_review_and_before_build() {
        const PR: &str = "timeout = 1200\n\n[pr]\n# product lines above which the PR body and the PR summary suggest a split; a line, never a refusal\nwarn_lines = 500\n";
        let plain = config_text(None, None, &[], false, &None, None);
        assert!(plain.ends_with(PR), "{plain}");
        let built = config_text(None, None, &[], false, &Some("claude".to_string()), Some("make"));
        assert!(built.contains(&format!("{PR}\n[build]\n")), "{built}");
        for text in [plain, built] {
            assert_eq!(text.matches("[pr]").count(), 1);
            let table: toml::Table = text.parse().unwrap();
            assert_eq!(table["pr"]["warn_lines"].as_integer(), Some(500));
        }
    }

    #[test]
    fn a_local_failure_never_reads_as_a_plan_without_protection() {
        let e = "could not read origin's repository: `git remote get-url origin` failed: fatal: bad include Upgrade to GitHub Pro";
        let line = super::super::protect_line(Err(crate::gh::Failure::Local(e.to_string())), "shipcraft/ci", "main");
        assert!(
            line.contains(&format!(
                "shipcraft: could not mark statuses as required ({e}); `shipcraft merge` is the gate."
            )),
            "{line}"
        );
        let line = super::super::protect_line(
            Err(crate::gh::Failure::Answer("gh: Upgrade to GitHub Pro (HTTP 403)".into())),
            "shipcraft/ci",
            "main",
        );
        assert!(line.contains("no branch protection on its GitHub plan"), "{line}");
    }
}
