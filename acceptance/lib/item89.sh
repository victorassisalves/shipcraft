# Item 89: status classifies AGENTS.md, public binary only; RED phase.
item89_langs() { echo core; }
item89_cases() {
  local c
  for c in current-bare current-local cross-bare cross-local old22 old25 old26 old30 old31 old39 legacy legacy-suffix absent plain stray-end edited missing-end duplicate reversed crlf marker-near future claude surrounding legacy-edited symlink dangling folder invalid subfolder worktree later-format later-folder early-invalid early-missing early-min early-outside fixture-bare fixture-local fixture-history; do echo "v1-89.$c"; done
}
item89_case() {
  EXPECT="item 89: ${CASE#v1-89.}"
  v1_start codex claude
  must_accept 'item 89 status contract' cmd "$PY" - "${CASE#v1-89.}" "$(command -v shipcraft)" "$CW" <<'PY89'
import hashlib,json,os,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw)
START=b'<!-- shipcraft -->';END=b'<!-- /shipcraft -->'
ROOT_LINE=b"- Run Shipcraft commands from the repository root, where `npx -- shipcraft` runs this project's install.\n"
LEGACY=b'<!-- shipcraft -->\n## shipcraft: TDD with a lock (required in this repository)\n- Cycle: RED (a failing test) \xe2\x86\x92 `shipcraft red` \xe2\x86\x92 GREEN (code) \xe2\x86\x92 `git commit`. The git hook checks every commit.\n- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.\n- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.\n- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*`, never touch the hook or `core.hooksPath`.\n- When in doubt, run `shipcraft status`.\n'
HISTORY={'old22': b'<!-- shipcraft -->\n## shipcraft: TDD with a lock (required in this repository)\n- Cycle: RED (a failing test) \xe2\x86\x92 `shipcraft red` \xe2\x86\x92 GREEN (code) \xe2\x86\x92 `git commit`. The git hook checks every commit.\n- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.\n- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.\n- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).\n- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.\n- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back, and a RED session fixes it with `shipcraft red --redo`.\n- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.\n- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.\n- When in doubt, run `shipcraft status`.\n<!-- /shipcraft -->\n', 'old25': b"<!-- shipcraft -->\n## shipcraft: TDD with a lock (required in this repository)\n- Cycle: RED (a failing test) \xe2\x86\x92 `shipcraft red` \xe2\x86\x92 GREEN (code) \xe2\x86\x92 `git commit`. The git hook checks every commit.\n- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.\n- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.\n- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.\n- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).\n- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.\n- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.\n- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.\n- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.\n- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.\n- When in doubt, run `shipcraft status`.\n<!-- /shipcraft -->\n", 'old26': b"<!-- shipcraft -->\n## shipcraft: TDD with a lock (required in this repository)\n- Cycle: RED (a failing test) \xe2\x86\x92 `shipcraft red` \xe2\x86\x92 GREEN (code) \xe2\x86\x92 `git commit`. The git hook checks every commit.\n- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.\n- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.\n- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.\n- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).\n- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.\n- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.\n- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.\n- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.\n- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.\n- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.\n- When in doubt, run `shipcraft status`.\n<!-- /shipcraft -->\n", 'old30': b"<!-- shipcraft -->\n## shipcraft: TDD with a lock (required in this repository)\n- Cycle: RED (a failing test) \xe2\x86\x92 `shipcraft red` \xe2\x86\x92 GREEN (code) \xe2\x86\x92 `git commit`. The git hook checks every commit.\n- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.\n- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.\n- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.\n- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).\n- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.\n- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.\n- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.\n- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.\n- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.\n- If you run in a sandbox (for example Codex's `workspace-write`), run `shipcraft red`, `shipcraft red --redo` and `git commit` (its hook runs the locked tests) outside it when you can: inside, they can take many times longer, or fail when git cannot write its index. If you cannot, finish your files and stop (your files: those you added, changed or deleted, both sides of a rename), and give the user the steps to run in a POSIX shell where this project's tests run, each argument you fill in written in single quotes as above: first `cd` to this checkout's absolute path; for a RED, then `shipcraft red` (for a repair, `shipcraft red --redo`), which prints the lock's path; then `git --literal-pathspecs add -f --` with each of your files as its own argument and, for a RED, that lock path; then `git commit -m` with the message. A GREEN gets only the `cd`, `git add` and `git commit` steps. Tell the user to start from the first step that has not succeeded yet, and to stop and tell you if a step fails. If one of your files already had other changes before your phase, or `git diff --cached --name-only -z` lists a staged path that is not one of yours (or fails), say so and name those paths instead of handing the steps over. Change nothing after handing them over. Your phase ends there: you start no other phase, and a commit alone does not mean the lock closed (`shipcraft status` says).\n- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.\n- When in doubt, run `shipcraft status`.\n<!-- /shipcraft -->\n", 'old31': b"<!-- shipcraft -->\n## shipcraft: TDD with a lock (required in this repository)\n- Cycle: RED (a failing test) \xe2\x86\x92 `shipcraft red` \xe2\x86\x92 GREEN (code) \xe2\x86\x92 `git commit`. The git hook checks every commit.\n- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.\n- When the change fixes behavior a release already shipped, the RED runs `shipcraft red --fix`, with `--reported-at <time>` when the time the defect was first reported is known (for example `2026-10-31T00:36-03:00`) and `--fixes-release <tag>` when the release that shipped it is known (for example `v2.25.0`), so the lock records them.\n- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.\n- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.\n- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).\n- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.\n- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.\n- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.\n- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.\n- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.\n- If you run in a sandbox (for example Codex's `workspace-write`), run `shipcraft red`, `shipcraft red --redo` and `git commit` (its hook runs the locked tests) outside it when you can: inside, they can take many times longer, or fail when git cannot write its index. If you cannot, finish your files and stop (your files: those you added, changed or deleted, both sides of a rename), and give the user the steps to run in a POSIX shell where this project's tests run, each argument you fill in written in single quotes as above: first `cd` to this checkout's absolute path; for a RED, then `shipcraft red` (for a repair, `shipcraft red --redo`), which prints the lock's path; then `git --literal-pathspecs add -f --` with each of your files as its own argument and, for a RED, that lock path; then `git commit -m` with the message. A GREEN gets only the `cd`, `git add` and `git commit` steps. Tell the user to start from the first step that has not succeeded yet, and to stop and tell you if a step fails. If one of your files already had other changes before your phase, or `git diff --cached --name-only -z` lists a staged path that is not one of yours (or fails), say so and name those paths instead of handing the steps over. Change nothing after handing them over. Your phase ends there: you start no other phase, and a commit alone does not mean the lock closed (`shipcraft status` says).\n- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.\n- When in doubt, run `shipcraft status`.\n<!-- /shipcraft -->\n", 'old39': b"<!-- shipcraft -->\n## shipcraft: TDD with a lock (required in this repository)\n- Cycle: RED (a failing test) \xe2\x86\x92 `shipcraft red` \xe2\x86\x92 GREEN (code) \xe2\x86\x92 `git commit`. The git hook checks every commit.\n- Pick the lane first: a mechanical change, one that changes no behavior (text, config, data, content, a rename, docs), is committed directly once the tests it affects pass in one run, with no RED or GREEN; a behavior change takes the cycle.\n- A change that needs more than about 40 new test cases is split before its RED.\n- A review of the RED's tests before the lock takes at most one round and fixes contract bugs only (a test that asserts the wrong behavior).\n- Locally, the GREEN runs only the tests the change affects; the full suite runs once, in CI (where CI is off, once before the PR).\n- In PR review, only Blocking findings open another round; the others go to notes.\n- Small fixes from one request go in one PR.\n- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.\n- When the change fixes behavior a release already shipped, the RED runs `shipcraft red --fix`, with `--reported-at <time>` when the time the defect was first reported is known (for example `2026-10-31T00:36-03:00`) and `--fixes-release <tag>` when the release that shipped it is known (for example `v2.25.0`), so the lock records them.\n- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.\n- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.\n- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).\n- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.\n- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.\n- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.\n- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.\n- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.\n- If you run in a sandbox (for example Codex's `workspace-write`), run `shipcraft red`, `shipcraft red --redo` and `git commit` (its hook runs the locked tests) outside it when you can: inside, they can take many times longer, or fail when git cannot write its index. If you cannot, finish your files and stop (your files: those you added, changed or deleted, both sides of a rename), and give the user the steps to run in a POSIX shell where this project's tests run, each argument you fill in written in single quotes as above: first `cd` to this checkout's absolute path; for a RED, then `shipcraft red` (for a repair, `shipcraft red --redo`), which prints the lock's path; then `git --literal-pathspecs add -f --` with each of your files as its own argument and, for a RED, that lock path; then `git commit -m` with the message. A GREEN gets only the `cd`, `git add` and `git commit` steps. Tell the user to start from the first step that has not succeeded yet, and to stop and tell you if a step fails. If one of your files already had other changes before your phase, or `git diff --cached --name-only -z` lists a staged path that is not one of yours (or fails), say so and name those paths instead of handing the steps over. Change nothing after handing them over. Your phase ends there: you start no other phase, and a commit alone does not mean the lock closed (`shipcraft status` says).\n- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.\n- When in doubt, run `shipcraft status`.\n<!-- /shipcraft -->\n"}
CURRENT='shipcraft: AGENTS.md block: current'
EARLIER='shipcraft: AGENTS.md block: from an earlier version; run `shipcraft init` to update it'
NONE='shipcraft: AGENTS.md block: none; run `shipcraft init` to add it'
UNREAD='shipcraft: AGENTS.md block: could not read it'
DIFF="shipcraft: AGENTS.md block: differs from this version's; init keeps it, compare it with docs/spec.md by hand"
def run(*args,cwd=None):
 p=subprocess.run(list(map(str,args)),cwd=cwd,input=b'',capture_output=True,timeout=90)
 print('$',repr(args),'[rc='+str(p.returncode)+']\n'+(p.stdout+p.stderr).decode(errors='replace'),flush=True)
 return p
def ok(*args,cwd=None):
 p=run(*args,cwd=cwd);assert p.returncode==0,('fixture command failed',p.returncode,p.stdout,p.stderr)
 return p
def variant(block,local):
 if not local:return block
 text=block.replace(b'`shipcraft ',b'`npx -- shipcraft ')
 head,rest=text.split(b'\n- ',1)
 return head+b'\n'+ROOT_LINE+b'- '+rest
def fixture(name,local=False):
 root=cw/name;root.mkdir();ok('git','init','-q',root)
 (root/'requirements.txt').write_bytes(b'pytest\n')
 call=binary
 if local:
  target=root/'node_modules/shipcraft-fixture/bin/shipcraft';target.parent.mkdir(parents=True);shutil.copy2(binary,target)
  call=root/'node_modules/.bin/shipcraft';call.parent.mkdir(parents=True);call.symlink_to(target)
 p=ok(call,'init',cwd=root)
 assert b'AGENTS.md block:' not in p.stdout+p.stderr,'init gained status-only line'
 # A status run must never execute any of these commands.
 (root/'.shipcraft.toml').write_text('shipcraft_min="0.0"\ntest_command="touch ran89; exit 23 # {junit}"\ntest_globs=["tests/**"]\ncheck="touch checked89; exit 24"\n[build]\ncommand="touch built89; exit 25"\n[execution]\nci="off"\nreview="off"\n')
 return root,call,(root/'AGENTS.md').read_bytes()
def snapshot(root):
 result={}
 for p in root.rglob('*'):
  mode=p.lstat().st_mode
  result[str(p.relative_to(root))]=(mode,os.readlink(p) if stat.S_ISLNK(mode) else hashlib.sha256(p.read_bytes()).hexdigest() if stat.S_ISREG(mode) else None)
 return result
def observed():
 # Only disposable repositories and their owned targets. Harness stdout and gh's call log live beside them.
 return {p.name:snapshot(p) for p in cw.iterdir() if p.name in ("project89 space 'quote",'sample-local','sample-bare','linked89','outside89')}
def status(root,call,cwd=None):
 before=observed()
 p=run(call,'status',cwd=cwd or root)
 after=observed()
 assert after==before,('status changed a file, mode, symlink or run log',[(k,before.get(k),after.get(k)) for k in set(before)|set(after) if before.get(k)!=after.get(k)])
 return p
def line(p,expected,rc=0,later=False):
 text=(p.stdout+p.stderr).decode();ls=p.stdout.decode().splitlines()
 assert p.returncode==rc,('status exit changed',rc,p.returncode,text)
 assert [s for s in ls if s.startswith('shipcraft: AGENTS.md block:')]==[expected],('missing or wrong AGENTS line',expected,text)
 i=ls.index(expected)
 assert i>0 and 'hook' in ls[i-1].lower(),('line must immediately follow hook',ls)
 if not later:assert ls[i+1].startswith('shipcraft: open locks:'),('line must immediately precede locks',ls)
 assert 'AGENTS.md block:' not in p.stderr.decode(),('line belongs on stdout',text)
 if later:
  combined=(p.stdout+p.stderr).decode()
  assert combined.index(expected)<combined.index('shipcraft refused:' if rc==1 else 'shipcraft: error:'),combined
 return text
def history_checks(root,call,current,key):
 # Both historical forms, with NUL/CRLF surrounding bytes, then public init migration.
 for local in (False,True):
  old=b'Before89\r\n\x00\n'+variant(HISTORY[key],local)+b'\nAfter89 no newline'
  (root/'AGENTS.md').write_bytes(old)
  p=status(root,call);line(p,EARLIER)
  ok(call,'init',cwd=root)
  assert (root/'AGENTS.md').read_bytes()==b'Before89\r\n\x00\n'+current+b'\nAfter89 no newline','historical init migration changed'
  line(status(root,call),CURRENT)
root,call,current=fixture("project89 space 'quote",case in ('current-local','cross-local','fixture-local'))
a=root/'AGENTS.md'
if case=='current-bare':
 line(status(root,call),CURRENT)
elif case=='current-local':
 line(status(root,call),CURRENT)
elif case=='cross-bare':
 _,_,other=fixture('sample-local',True);a.write_bytes(other)
 line(status(root,call),CURRENT)
elif case=='cross-local':
 _,_,other=fixture('sample-bare');a.write_bytes(other)
 line(status(root,call),CURRENT)
elif case=='old22':
 history_checks(root,call,current,'old22')
elif case=='old25':
 history_checks(root,call,current,'old25')
elif case=='old26':
 history_checks(root,call,current,'old26')
elif case=='old30':
 history_checks(root,call,current,'old30')
elif case=='old31':
 history_checks(root,call,current,'old31')
elif case=='old39':
 history_checks(root,call,current,'old39')
elif case=='legacy':
 a.write_bytes(LEGACY);line(status(root,call),EARLIER)
 ok(call,'init',cwd=root);assert a.read_bytes()==current;line(status(root,call),CURRENT)
elif case=='legacy-suffix':
 tail=b'User notes89\r\n<!-- other -->\nno final newline';a.write_bytes(LEGACY+tail)
 line(status(root,call),EARLIER)
 ok(call,'init',cwd=root);assert a.read_bytes()==current+tail;line(status(root,call),CURRENT)
elif case=='absent':
 a.unlink();line(status(root,call),NONE)
elif case=='plain':
 for data in (b'House rules89\n',b''):
  a.write_bytes(data);line(status(root,call),NONE)
elif case=='stray-end':
 a.write_bytes(END+b'\n'+END+b'\n');line(status(root,call),NONE)
elif case=='edited':
 a.write_bytes(current.replace(b'TDD',b'EDITED89',1));line(status(root,call),DIFF)
 before=a.read_bytes();ok(call,'init',cwd=root);assert a.read_bytes()==before
elif case=='missing-end':
 a.write_bytes(current.replace(END+b'\n',b''));line(status(root,call),DIFF)
 before=a.read_bytes();ok(call,'init',cwd=root);assert a.read_bytes()==before
elif case=='duplicate':
 a.write_bytes(START+b'\n'+current);line(status(root,call),DIFF)
 before=a.read_bytes();ok(call,'init',cwd=root);assert a.read_bytes()==before
elif case=='reversed':
 a.write_bytes(END+b'\n'+current);line(status(root,call),DIFF)
elif case=='crlf':
 a.write_bytes(current.replace(b'\n',b'\r\n'));line(status(root,call),DIFF)
elif case=='marker-near':
 # BOM, Unicode separators and trailing spaces do not make a start marker.
 for data in (b'\xef\xbb\xbf'+START+b'\n',START+b' \n',START+b'\xe2\x80\xa8',START+b'\xe2\x80\xa9'):
  a.write_bytes(data);line(status(root,call),NONE)
 # The shared init reader accepts a terminal CR as a marker line, but the bytes differ.
 a.write_bytes(START+b'\r');line(status(root,call),DIFF)
 # An exact start with a near-match end is an unpaired block.
 for end in (END+b' \n',END+b'\r\n',END+b'\xe2\x80\xa8'):
  a.write_bytes(START+b'\ncustom89\n'+end);line(status(root,call),DIFF)
elif case=='future':
 a.write_bytes(current.replace(END,b'- Future rule89\n'+END));line(status(root,call),DIFF)
elif case=='claude':
 # CLAUDE never substitutes for AGENTS, and an unreadable import does not poison a current block.
 cl=root/'CLAUDE.md';cl.write_bytes(b'\xff')
 line(status(root,call),CURRENT)
 cl.write_bytes(current);a.unlink();line(status(root,call),NONE)
elif case=='surrounding':
 a.write_bytes(b'Before89\r\n\x00\n'+current+b'After89 no newline');line(status(root,call),CURRENT)
elif case=='legacy-edited':
 a.write_bytes(LEGACY.replace(b'TDD',b'EDITED89',1)+b'user tail89');line(status(root,call),DIFF)
elif case=='symlink':
 target=root/'target89';target.write_bytes(current);a.unlink();a.symlink_to(target)
 line(status(root,call),UNREAD)
elif case=='dangling':
 a.unlink();a.symlink_to(root/'missing89');line(status(root,call),UNREAD)
elif case=='folder':
 a.unlink();a.mkdir();(a/'sentinel').write_bytes(b'keep89');line(status(root,call),UNREAD)
elif case=='invalid':
 # UTF-8 is checked before marker classification, even when no marker is present.
 for data in (b'\xff\n',current+b'\xff'):
  a.write_bytes(data);line(status(root,call),UNREAD)
elif case=='subfolder':
 nested=root/'packages/deep89';nested.mkdir(parents=True);(nested/'AGENTS.md').write_bytes(b'not root89\n')
 line(status(root,call,nested),CURRENT)
elif case=='worktree':
 # Use normal public Git setup; hook-written rows are included in the snapshot baseline.
 ok('git','add','requirements.txt',cwd=root);ok('git','commit','-qm','fixture89',cwd=root)
 wt=cw/'linked89';ok('git','worktree','add','-q','-b','linked89',wt,cwd=root)
 ok(call,'init',cwd=wt);(wt/'.shipcraft.toml').write_bytes((root/'.shipcraft.toml').read_bytes())
 (wt/'AGENTS.md').write_bytes(b'linked has no block89\n')
 nested=wt/'nested89';nested.mkdir();(nested/'AGENTS.md').write_bytes(current)
 line(status(wt,call,nested),NONE)
elif case=='later-format':
 # Every table row must survive a later refusal, with its original exit 1 and three lines.
 lock=root/'.shipcraft/locks/future89.json'
 lock.write_text(json.dumps(dict(format=999,state='open',files={},cases=[],failing_at_red=[],seal='')))
 for data,expected in ((current,CURRENT),(HISTORY['old22'],EARLIER),(b'plain89',NONE),(current.replace(b'TDD',b'EDIT89'),DIFF),(b'\xff',UNREAD)):
  a.write_bytes(data);p=status(root,call);text=line(p,expected,1,True)
  refusal=text[text.index('shipcraft refused:'):].strip().splitlines()
  assert len(refusal)==3 and 'format 999' in refusal[0] and refusal[1].startswith('Why:') and refusal[2].startswith('Next:'),text
elif case=='later-folder':
 folder=root/'.shipcraft/locks';folder.chmod(0)
 try:
  p=status(root,call);line(p,CURRENT,2,True)
 finally:folder.chmod(0o755)
elif case=='early-invalid':
 (root/'.shipcraft.toml').write_bytes(b'invalid TOML [\n');p=status(root,call)
 assert p.returncode==1 and b'AGENTS.md block:' not in p.stdout+p.stderr and b'hooks installed' not in p.stdout
elif case=='early-missing':
 (root/'.shipcraft.toml').unlink();p=status(root,call)
 assert p.returncode==1 and b'AGENTS.md block:' not in p.stdout+p.stderr and b'hooks installed' not in p.stdout
elif case=='early-min':
 version=ok(binary,'--version',cwd=root).stdout.decode().split()[1];major=int(version.split('.')[0])+1
 cfg=root/'.shipcraft.toml';cfg.write_text(cfg.read_text().replace('shipcraft_min="0.0"',f'shipcraft_min="{major}.0"'))
 p=status(root,call);assert p.returncode==1 and b'AGENTS.md block:' not in p.stdout+p.stderr and b'hooks installed' not in p.stdout
elif case=='early-outside':
 outside=cw/'outside89';outside.mkdir();p=status(outside,call)
 assert p.returncode==1 and b'AGENTS.md block:' not in p.stdout+p.stderr and b'hooks installed' not in p.stdout
elif case=='fixture-bare':
 assert current[:len(START)+1]==START+b'\n' and current.endswith(END+b'\n')
 assert b'`shipcraft red`' in current and b'`npx -- shipcraft red`' not in current and ROOT_LINE not in current
 p=status(root,call);assert p.returncode==0 and b'shipcraft: open locks: none' in p.stdout
elif case=='fixture-local':
 assert current[:len(START)+1]==START+b'\n' and current.endswith(END+b'\n')
 assert b'`npx -- shipcraft red`' in current and ROOT_LINE in current and b'`shipcraft red`' not in current
 p=status(root,call);assert p.returncode==0 and b'shipcraft: open locks: none' in p.stdout
elif case=='fixture-history':
 # Prove every frozen historical input is recognized: changed bytes and no manual-edit notice.
 for key,block in HISTORY.items():
  for local in (False,True):
   old=b'prefix89\r\n'+variant(block,local)+b'suffix89';a.write_bytes(old)
   p=ok(call,'init',cwd=root)
   assert a.read_bytes()==b'prefix89\r\n'+current+b'suffix89' and a.read_bytes()!=old,(key,local,'historical input not upgraded')
   assert b'it differs from this version' not in p.stdout+p.stderr,(key,local)
 # Prove the near-marker fixture against the existing public init reader too.
 for data in (b'\xef\xbb\xbf'+START+b'\n',START+b' \n',START+b'\xe2\x80\xa8',START+b'\xe2\x80\xa9'):
  a.write_bytes(data);ok(call,'init',cwd=root)
  assert a.read_bytes()!=data and a.read_bytes().endswith(current),('near start was not marker-free',data)
 a.write_bytes(START+b'\r');ok(call,'init',cwd=root)
 assert a.read_bytes()==START+b'\r','terminal CR reader changed'
 for end in (END+b' \n',END+b'\r\n',END+b'\xe2\x80\xa8'):
  data=START+b'\ncustom89\n'+end;a.write_bytes(data);ok(call,'init',cwd=root)
  assert a.read_bytes()==data,('unpaired or edited block not kept',end)
else:raise AssertionError('unrouted item89 case: '+case)
PY89
  pass
}
