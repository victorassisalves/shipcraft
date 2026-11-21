//! The `AGENTS.md` block and the `CLAUDE.md` import (items 61, 68, 70, 74, 75, 84, 85, 89, 142, 145).

use super::files::on_path;
use crate::git::Repo;
use std::fs;
use std::path::Path;

const AGENTS_FILE: &str = "AGENTS.md";
const CLAUDE_FILE: &str = "CLAUDE.md";
const START_LINE: &str = "<!-- shipcraft -->";
const END_LINE: &str = "<!-- /shipcraft -->";
/// Item 75: the line the current block gains right after the behavior-change line.
const FIX_LINE: &str = "- When the change fixes behavior a release already shipped, the RED runs `shipcraft red --fix`, with `--reported-at <time>` when the time the defect was first reported is known (for example `2026-10-31T00:36-03:00`) and `--fixes-release <tag>` when the release that shipped it is known (for example `v2.25.0`), so the lock records them.\n";
/// Item 84: the lines the current block gains right after the `- Cycle:` line (flow matched to risk).
const RISK_LINES: &str = "- Pick the lane first: a mechanical change, one that changes no behavior (text, config, data, content, a rename, docs), is committed directly once the tests it affects pass in one run, with no RED or GREEN; a behavior change takes the cycle.
- A change that needs more than about 40 new test cases is split before its RED.
- A review of the RED's tests before the lock takes at most one round and fixes contract bugs only (a test that asserts the wrong behavior).
- Locally, the GREEN runs only the tests the change affects; the full suite runs once, in CI (where CI is off, once before the PR).
- In PR review, only Blocking findings open another round; the others go to notes.
- Small fixes from one request go in one PR.
";
/// Item 85: the line the current block gains right after the `- Small fixes` line (cleanup after the merge).
const CLEANUP_LINE: &str = "- After a merge, clean up what this change created: its worktree, temp folders, and servers or databases you started. Never remove what you did not create, what other sessions may be using, or anything with unmerged work: report those instead.\n";
/// Item 142: the line the current block gains right after the cleanup line (contributing with `export`).
const EXPORT_LINE: &str = "- To contribute to a project that does not use Shipcraft (its default branch has no `.shipcraft.toml` or `.sc2.toml`), open the PR from the branch `shipcraft export --base <base> <new branch>` writes once the lock is closed and `shipcraft ci --base <base>` passes on this branch: it leaves out Shipcraft's files and this block, and the project's own checks still apply to it. `shipcraft pr` is for projects that use Shipcraft.\n";
/// Item 145: the line the current block gains right after the `- A session told it is the RED or the GREEN` line (who fixes the interface).
const INTERFACE_LINE: &str = "- Before starting either phase, the session the user talks to fixes the interface the tests call (what they call to reach the behavior: names, arguments, results, and the errors, exit codes or messages they check; for a command line, its commands, flags and output) and writes it in every prompt that starts a phase, a command given to the user included. The RED's tests and stubs use that interface; the GREEN never changes it (the code behind it is free), and a GREEN that finds it wrong stops and reports it as a wrong test: the repair above, with the corrected interface in the new RED's prompt and the GREEN's, through `shipcraft red --redo` and its limits.\n";
/// Item 74's block (commit f4220f1, v2.30.0), a known block in both variants;
/// item 75's is it with `FIX_LINE` (`agents_block_2_31`). Item 61's block
/// with item 68's rules: the machine install's block; a project-local install
/// gets it with `npx -- shipcraft` and the repository-root line (`variant`).
const AGENTS_BLOCK_2_30: &str = r#"<!-- shipcraft -->
## shipcraft: TDD with a lock (required in this repository)
- Cycle: RED (a failing test) → `shipcraft red` → GREEN (code) → `git commit`. The git hook checks every commit.
- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.
- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.
- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.
- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).
- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.
- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.
- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.
- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.
- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.
- If you run in a sandbox (for example Codex's `workspace-write`), run `shipcraft red`, `shipcraft red --redo` and `git commit` (its hook runs the locked tests) outside it when you can: inside, they can take many times longer, or fail when git cannot write its index. If you cannot, finish your files and stop (your files: those you added, changed or deleted, both sides of a rename), and give the user the steps to run in a POSIX shell where this project's tests run, each argument you fill in written in single quotes as above: first `cd` to this checkout's absolute path; for a RED, then `shipcraft red` (for a repair, `shipcraft red --redo`), which prints the lock's path; then `git --literal-pathspecs add -f --` with each of your files as its own argument and, for a RED, that lock path; then `git commit -m` with the message. A GREEN gets only the `cd`, `git add` and `git commit` steps. Tell the user to start from the first step that has not succeeded yet, and to stop and tell you if a step fails. If one of your files already had other changes before your phase, or `git diff --cached --name-only -z` lists a staged path that is not one of yours (or fails), say so and name those paths instead of handing the steps over. Change nothing after handing them over. Your phase ends there: you start no other phase, and a commit alone does not mean the lock closed (`shipcraft status` says).
- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.
- When in doubt, run `shipcraft status`.
<!-- /shipcraft -->
"#;
/// Item 74: item 70's block (commit e642432, v2.26.0 to v2.29.0), a known block in both variants.
const AGENTS_BLOCK_2_26: &str = r#"<!-- shipcraft -->
## shipcraft: TDD with a lock (required in this repository)
- Cycle: RED (a failing test) → `shipcraft red` → GREEN (code) → `git commit`. The git hook checks every commit.
- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.
- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.
- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.
- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).
- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.
- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.
- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.
- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.
- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.
- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.
- When in doubt, run `shipcraft status`.
<!-- /shipcraft -->
"#;
/// Item 70: the block at v2.25.0 (`git show v2.25.0:nucleo/src/init.rs`), a known block in both variants.
const AGENTS_BLOCK_2_25: &str = "<!-- shipcraft -->
## shipcraft: TDD with a lock (required in this repository)
- Cycle: RED (a failing test) → `shipcraft red` → GREEN (code) → `git commit`. The git hook checks every commit.
- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.
- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.
- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.
- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).
- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.
- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.
- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.
- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.
- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.
- When in doubt, run `shipcraft status`.
<!-- /shipcraft -->
";
/// Item 68: the block at v2.22.0 (`git show v2.22.0:nucleo/src/init.rs`), a known block in both variants.
const AGENTS_BLOCK_2_22: &str = "<!-- shipcraft -->
## shipcraft: TDD with a lock (required in this repository)
- Cycle: RED (a failing test) → `shipcraft red` → GREEN (code) → `git commit`. The git hook checks every commit.
- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.
- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.
- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).
- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.
- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back, and a RED session fixes it with `shipcraft red --redo`.
- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.
- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.
- When in doubt, run `shipcraft status`.
<!-- /shipcraft -->
";
/// Item 150: the three forms of the block and the briefs, by the project's invocation (item 131).
pub(crate) const FORMS: [&str; 3] = ["shipcraft", "npx -- shipcraft", "pnpm exec shipcraft"];
/// The 2.14.0 block (`git show v2.14.0:nucleo/src/init.rs`): a start line, no end line.
const AGENTS_BLOCK_2_14: &str = "<!-- shipcraft -->
## shipcraft: TDD with a lock (required in this repository)
- Cycle: RED (a failing test) → `shipcraft red` → GREEN (code) → `git commit`. The git hook checks every commit.
- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.
- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.
- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*`, never touch the hook or `core.hooksPath`.
- When in doubt, run `shipcraft status`.
";
const CLAUDE_BLOCK: &str = "<!-- shipcraft -->\nShipcraft workflow (required): @AGENTS.md\n<!-- /shipcraft -->\n";
const DIFFERS: &str = "; it differs from this version's: edit it by hand to match docs/spec.md";

/// Item 61: the block's current variant; from a project-local install (item 58)
/// every command is the project's invocation (item 150), run from the root.
fn agents_text(inv: &str) -> String {
    variant(&current_block(), inv)
}

/// Item 75's block (commit c3a919d, v2.31.0 to v2.38.0), a known block in both
/// variants: item 74's block with `FIX_LINE` right after the line that starts
/// `- A behavior change: write the failing test first`.
fn agents_block_2_31() -> String {
    after_line(AGENTS_BLOCK_2_30, "\n- A behavior change: write the failing test first", FIX_LINE)
}

/// Item 84's block (commit 1397349, v2.39.0), a known block in both variants:
/// item 75's block with `RISK_LINES` right after the line that starts `- Cycle:`.
fn agents_block_2_39() -> String {
    after_line(&agents_block_2_31(), "\n- Cycle:", RISK_LINES)
}

/// Item 85's block (commit 182f194, v2.81.0), a known block in both variants:
/// item 84's block with `CLEANUP_LINE` right after the `- Small fixes` line.
fn agents_block_2_81() -> String {
    after_line(&agents_block_2_39(), "\n- Small fixes from one request go in one PR.", CLEANUP_LINE)
}

/// Item 142's block (v2.82.0 to v2.85.0), a known block in both variants:
/// item 85's block with `EXPORT_LINE` right after the cleanup line.
fn agents_block_2_82() -> String {
    after_line(&agents_block_2_81(), "\n- After a merge, clean up", EXPORT_LINE)
}

/// Item 145: item 142's block with `INTERFACE_LINE` right after the line that
/// starts `- A session told it is the RED or the GREEN`.
fn current_block() -> String {
    after_line(
        &agents_block_2_82(),
        "\n- A session told it is the RED or the GREEN does that phase only",
        INTERFACE_LINE,
    )
}

/// `block` with `lines` right after the line that starts at `start` (a `\n` and the line's start).
fn after_line(block: &str, start: &str, lines: &str) -> String {
    let at = block.find(start).expect("the block has the line");
    let end = at + 1 + block[at + 1..].find('\n').expect("the line ends") + 1;
    format!("{}{lines}{}", &block[..end], &block[end..])
}

/// A block (this version's, v2.82.0's, v2.81.0's, v2.39.0's, v2.31.0's, v2.30.0's, v2.26.0's, v2.25.0's or v2.22.0's) in the form of `inv` (item 150).
fn variant(block: &str, inv: &str) -> String {
    if inv == FORMS[0] {
        return block.to_string();
    }
    let text = block.replace("`shipcraft ", &format!("`{inv} "));
    let (head, rest) = text.split_at(text.find("\n- ").unwrap() + 1);
    format!(
        "{head}- Run Shipcraft commands from the repository root, where `{inv}` runs this project's install.\n{rest}"
    )
}

/// The blocks `init` replaces for a run of form `inv`: this version's other two
/// forms first, then every earlier block in the machine and `npx -- shipcraft` forms.
fn known_blocks(inv: &str) -> Vec<String> {
    let earlier = [
        AGENTS_BLOCK_2_22.to_string(),
        AGENTS_BLOCK_2_25.to_string(),
        AGENTS_BLOCK_2_26.to_string(),
        AGENTS_BLOCK_2_30.to_string(),
        agents_block_2_31(),
        agents_block_2_39(),
        agents_block_2_81(),
        agents_block_2_82(),
    ];
    let mut known: Vec<String> = FORMS.iter().filter(|f| **f != inv).map(|f| agents_text(f)).collect();
    for block in &earlier {
        known.push(variant(block, FORMS[0]));
        known.push(variant(block, FORMS[1]));
    }
    known
}

/// Item 142: the blocks Shipcraft writes in `name` (`AGENTS.md` or `CLAUDE.md`),
/// which `export` reads out: for `AGENTS.md` this version's block and every
/// block `init` replaces (not the 2.14.0 legacy one), this version's in its three forms.
pub(crate) fn written_blocks(name: &str) -> Vec<String> {
    if name == CLAUDE_FILE {
        return vec![CLAUDE_BLOCK.to_string()];
    }
    let mut blocks = vec![agents_text(FORMS[0])];
    blocks.extend(known_blocks(FORMS[0]));
    blocks
}

/// Item 61's marker rule over bytes: each line (`\n`-ended, the last possibly
/// not) that, without its `\n` and one trailing `\r`, is the start or end line,
/// as (is the start line, first byte, byte after its end).
pub(crate) fn marker_lines(bytes: &[u8]) -> Vec<(bool, usize, usize)> {
    let mut markers = Vec::new();
    let mut at = 0;
    for line in bytes.split_inclusive(|b| *b == b'\n') {
        let bare = line.strip_suffix(b"\n").unwrap_or(line);
        let bare = bare.strip_suffix(b"\r").unwrap_or(bare);
        if bare == START_LINE.as_bytes() || bare == END_LINE.as_bytes() {
            markers.push((bare == START_LINE.as_bytes(), at, at + line.len()));
        }
        at += line.len();
    }
    markers
}

/// Item 89: `status`'s line on `AGENTS.md`'s block, read with `init`'s rules. It writes nothing.
pub fn agents_block_status(repo: &Repo) -> String {
    let unreadable = "shipcraft: AGENTS.md block: could not read it";
    let path = repo.path(AGENTS_FILE);
    let text = match path.symlink_metadata() {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => None,
        Err(_) => return unreadable.to_string(),
        Ok(meta) if !meta.is_file() => return unreadable.to_string(),
        Ok(_) => match fs::read_to_string(&path) {
            Ok(text) => Some(text),
            Err(_) => return unreadable.to_string(),
        },
    };
    let new = agents_text(FORMS[0]);
    let known = known_blocks(FORMS[0]);
    let refs: Vec<&str> = known.iter().map(String::as_str).collect();
    let found = text.as_deref().map(|t| (t, find_block(t, &new, &refs, Some(AGENTS_BLOCK_2_14))));
    match found {
        None | Some((_, Found::None)) => "shipcraft: AGENTS.md block: none; run `shipcraft init` to add it",
        Some((_, Found::Equal)) => "shipcraft: AGENTS.md block: current",
        // A project-local install's forms are this version's too; `known[..2]` are those (item 150).
        Some((t, Found::Known(range))) if known[..2].iter().any(|k| t[range.clone()] == **k) => {
            "shipcraft: AGENTS.md block: current"
        }
        Some((_, Found::Known(_))) => {
            "shipcraft: AGENTS.md block: from an earlier version; run `shipcraft init` to update it"
        }
        Some((_, Found::Differs)) => {
            "shipcraft: AGENTS.md block: differs from this version's; init keeps it, compare it with docs/spec.md by hand"
        }
    }
    .to_string()
}

/// Tells agents the workflow where they already look: `AGENTS.md` gets the
/// block, and `CLAUDE.md` imports it where Claude Code reads it (item 61). A
/// failure here never undoes the init. Returns the files it wrote, `, AGENTS.md`.
pub(super) fn agents_block(repo: &Repo, inv: &str) -> String {
    let new = agents_text(inv);
    let known = known_blocks(inv);
    let known: Vec<&str> = known.iter().map(String::as_str).collect();
    let (wrote, current) = onboard(repo, AGENTS_FILE, &new, &known, Some(AGENTS_BLOCK_2_14));
    let mut listed = if wrote { format!(", {AGENTS_FILE}") } else { String::new() };
    let claude = match repo.path(CLAUDE_FILE).symlink_metadata() {
        Ok(_) => true,
        Err(e) => e.kind() != std::io::ErrorKind::NotFound,
    };
    if claude || on_path("claude") {
        if !current {
            println!(
                "shipcraft: {CLAUDE_FILE} not written: {AGENTS_FILE} does not hold this version's shipcraft block"
            );
        } else if onboard(repo, CLAUDE_FILE, CLAUDE_BLOCK, &[], None).0 {
            listed.push_str(&format!(", {CLAUDE_FILE}"));
        }
    }
    listed
}

/// Writes `new` into `file`: created, appended once, or replacing a known block
/// (`known`, or `legacy` and what follows it); anything else is kept. A symlink
/// is left alone. Returns whether it wrote, and whether the file is a regular
/// one that now holds `new`.
fn onboard(repo: &Repo, file: &str, new: &str, known: &[&str], legacy: Option<&str>) -> (bool, bool) {
    let path = repo.path(file);
    let written = match path.symlink_metadata() {
        Ok(meta) if !meta.is_file() => {
            println!(
                "shipcraft: {file} is not a regular file, kept; add the shipcraft block from docs/spec.md by hand"
            );
            return (false, false);
        }
        Ok(_) => match fs::read_to_string(&path) {
            Ok(text) => match find_block(&text, new, known, legacy) {
                Found::None => {
                    let sep = if text.is_empty() || text.ends_with("\n\n") {
                        ""
                    } else if text.ends_with('\n') {
                        "\n"
                    } else {
                        "\n\n"
                    };
                    rewrite(&path, format!("{text}{sep}{new}")).map(|()| "added the shipcraft block to")
                }
                Found::Equal => {
                    println!("shipcraft: {file} already has the shipcraft block, kept");
                    return (false, true);
                }
                Found::Known(range) => {
                    let text = format!("{}{new}{}", &text[..range.start], &text[range.end..]);
                    rewrite(&path, &text).map(|()| "replaced the shipcraft block in")
                }
                Found::Differs => {
                    println!("shipcraft: {file} already has the shipcraft block, kept{DIFFERS}");
                    return (false, false);
                }
            },
            Err(e) => Err(e),
        },
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => fs::write(&path, new).map(|()| "created"),
        Err(e) => Err(e),
    };
    match written {
        Ok(verb) => {
            println!("shipcraft: {verb} {file}");
            (true, true)
        }
        Err(e) => {
            println!("shipcraft: could not write {file} ({e}); add the shipcraft block from docs/spec.md by hand");
            (false, false)
        }
    }
}

enum Found {
    None,
    Equal,
    Known(std::ops::Range<usize>),
    Differs,
}

/// Item 61: a marker is a whole line (`\n`-ended, a trailing `\r` ignored)
/// equal to the start or end line; a block runs from a start line through the
/// next end line. Only one start and one end, or the legacy start alone, are read.
fn find_block(text: &str, new: &str, known: &[&str], legacy: Option<&str>) -> Found {
    match marker_lines(text.as_bytes()).as_slice() {
        m if !m.iter().any(|(start, ..)| *start) => Found::None,
        [(true, from, _), (false, _, to)] => match &text[*from..*to] {
            block if block == new => Found::Equal,
            block if known.contains(&block) => Found::Known(*from..*to),
            _ => Found::Differs,
        },
        [(true, from, _)] => match legacy {
            Some(old) if text[*from..].starts_with(old) => Found::Known(*from..from + old.len()),
            _ => Found::Differs,
        },
        _ => Found::Differs,
    }
}

/// Rewrites an existing file through a temporary one in its folder, with the
/// old permission bits, renamed over it; a failure leaves the old bytes. A file
/// the owner may not write is not rewritten.
pub(crate) fn rewrite(path: &Path, text: impl AsRef<[u8]>) -> std::io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
    let mode = fs::metadata(path)?.permissions().mode() & 0o7777;
    if mode & 0o200 == 0 {
        return Err(std::io::ErrorKind::PermissionDenied.into());
    }
    let name = path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
    // A name of its own, created exclusively: an existing entry is never touched.
    let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_nanos());
    let mut attempt = 0u32;
    let (temp, mut file) = loop {
        let temp = path.with_file_name(format!(".{name}.shipcraft-{}-{nanos}-{attempt}.tmp", std::process::id()));
        match fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temp) {
            Ok(file) => break (temp, file),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists && attempt < 100 => attempt += 1,
            Err(e) => return Err(e),
        }
    };
    let result = file
        .write_all(text.as_ref())
        .and_then(|()| file.sync_all())
        .and_then(|()| fs::set_permissions(&temp, fs::Permissions::from_mode(mode)))
        .and_then(|()| fs::rename(&temp, path));
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn known_blocks_hold_this_versions_other_forms_and_no_earlier_pnpm_form() {
        let pnpm = agents_text(FORMS[2]);
        assert_eq!(pnpm.len(), 8603);
        assert!(pnpm.lines().nth(2).unwrap().contains("where `pnpm exec shipcraft` runs"));
        let known = known_blocks(FORMS[2]);
        assert_eq!(known[..2], [agents_text(FORMS[0]), agents_text(FORMS[1])]);
        assert!(!known.contains(&pnpm) && !known[2..].iter().any(|k| k.contains("pnpm exec")));
        assert!(written_blocks(AGENTS_FILE).contains(&pnpm));
    }
}
