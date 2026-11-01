# Item 84: byte-exact risk-based flow, public init only; RED phase.
item84_langs() { echo core; }
item84_cases() {
  local c
  for c in fresh-bare upgrade-bare-bare upgrade-local-bare older74-bare edited75-bare equal-new-bare green-bare red-body-control-bare red-stamp-bare old-green-bare later-brief-fails-bare partial-bare partial-control-bare fresh-local upgrade-bare-local upgrade-local-local older74-local edited75-local equal-new-local green-local red-body-control-local red-stamp-local old-green-local later-brief-fails-local partial-local partial-control-local old-green-control-bare old-green-control-local brief-failure-control; do echo "v1-84.$c"; done
}
item84_case() {
  EXPECT="item 84: ${CASE#v1-84.}"
  v1_start codex claude
  must_accept 'item 84 init flow contract' cmd "$PY" - "${CASE#v1-84.}" "$(command -v shipcraft)" "$CW" "$ACEITE/../nucleo/Cargo.toml" <<'PY84'
import os,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw,manifest=sys.argv[1:];binary=str(Path(binary).resolve())
try:import tomllib
except ImportError:import tomli as tomllib
version=tomllib.loads(Path(manifest).read_text())['package']['version']
OLD75=b"<!-- shipcraft -->\n## shipcraft: TDD with a lock (required in this repository)\n- Cycle: RED (a failing test) \xe2\x86\x92 `shipcraft red` \xe2\x86\x92 GREEN (code) \xe2\x86\x92 `git commit`. The git hook checks every commit.\n- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.\n- When the change fixes behavior a release already shipped, the RED runs `shipcraft red --fix`, with `--reported-at <time>` when the time the defect was first reported is known (for example `2026-10-31T00:36-03:00`) and `--fixes-release <tag>` when the release that shipped it is known (for example `v2.25.0`), so the lock records them.\n- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.\n- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.\n- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).\n- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.\n- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.\n- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.\n- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.\n- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.\n- If you run in a sandbox (for example Codex's `workspace-write`), run `shipcraft red`, `shipcraft red --redo` and `git commit` (its hook runs the locked tests) outside it when you can: inside, they can take many times longer, or fail when git cannot write its index. If you cannot, finish your files and stop (your files: those you added, changed or deleted, both sides of a rename), and give the user the steps to run in a POSIX shell where this project's tests run, each argument you fill in written in single quotes as above: first `cd` to this checkout's absolute path; for a RED, then `shipcraft red` (for a repair, `shipcraft red --redo`), which prints the lock's path; then `git --literal-pathspecs add -f --` with each of your files as its own argument and, for a RED, that lock path; then `git commit -m` with the message. A GREEN gets only the `cd`, `git add` and `git commit` steps. Tell the user to start from the first step that has not succeeded yet, and to stop and tell you if a step fails. If one of your files already had other changes before your phase, or `git diff --cached --name-only -z` lists a staged path that is not one of yours (or fails), say so and name those paths instead of handing the steps over. Change nothing after handing them over. Your phase ends there: you start no other phase, and a commit alone does not mean the lock closed (`shipcraft status` says).\n- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.\n- When in doubt, run `shipcraft status`.\n<!-- /shipcraft -->\n"
SIX=b"- Pick the lane first: a mechanical change, one that changes no behavior (text, config, data, content, a rename, docs), is committed directly once the tests it affects pass in one run, with no RED or GREEN; a behavior change takes the cycle.\n- A change that needs more than about 40 new test cases is split before its RED.\n- A review of the RED's tests before the lock takes at most one round and fixes contract bugs only (a test that asserts the wrong behavior).\n- Locally, the GREEN runs only the tests the change affects; the full suite runs once, in CI (where CI is off, once before the PR).\n- In PR review, only Blocking findings open another round; the others go to notes.\n- Small fixes from one request go in one PR.\n"
OLD74=b"<!-- shipcraft -->\n## shipcraft: TDD with a lock (required in this repository)\n- Cycle: RED (a failing test) \xe2\x86\x92 `shipcraft red` \xe2\x86\x92 GREEN (code) \xe2\x86\x92 `git commit`. The git hook checks every commit.\n- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.\n- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.\n- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.\n- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).\n- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.\n- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.\n- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.\n- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.\n- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.\n- If you run in a sandbox (for example Codex's `workspace-write`), run `shipcraft red`, `shipcraft red --redo` and `git commit` (its hook runs the locked tests) outside it when you can: inside, they can take many times longer, or fail when git cannot write its index. If you cannot, finish your files and stop (your files: those you added, changed or deleted, both sides of a rename), and give the user the steps to run in a POSIX shell where this project's tests run, each argument you fill in written in single quotes as above: first `cd` to this checkout's absolute path; for a RED, then `shipcraft red` (for a repair, `shipcraft red --redo`), which prints the lock's path; then `git --literal-pathspecs add -f --` with each of your files as its own argument and, for a RED, that lock path; then `git commit -m` with the message. A GREEN gets only the `cd`, `git add` and `git commit` steps. Tell the user to start from the first step that has not succeeded yet, and to stop and tell you if a step fails. If one of your files already had other changes before your phase, or `git diff --cached --name-only -z` lists a staged path that is not one of yours (or fails), say so and name those paths instead of handing the steps over. Change nothing after handing them over. Your phase ends there: you start no other phase, and a commit alone does not mean the lock closed (`shipcraft status` says).\n- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.\n- When in doubt, run `shipcraft status`.\n<!-- /shipcraft -->\n"
ROOT_LINE=b"- Run Shipcraft commands from the repository root, where `npx -- shipcraft` runs this project's install.\n"
HISTORICAL_BRIEFS={False: {'red.md': b'# shipcraft: the RED phase\n\nYou are the RED session: you write the failing tests for a change, not the change.\n\n- Write the failing tests from the intent, never from an implementation.\n- Write two cases per rule: the ordinary one, and a boundary a rushed GREEN would get wrong.\n- First read the existing tests that cover the behavior the change touches, and never contradict them unless the intent says that behavior changes.\n- Each test written for the new behavior must fail for the right reason before you run `shipcraft red`. Passing control tests are fine: they are locked as controls.\n- Fake external tools with their real output.\n- Commit the tests, their stubs and the lock in one commit, and stop.\n- List ambiguities instead of picking a reading silently.\n\n', 'green.md': b"# shipcraft: the GREEN phase\n\nYou are the GREEN session: you make the locked tests pass.\n\n- Start from the RED commit.\n- Never edit a locked file or a lock (`.shipcraft/locks/*`).\n- Change product code, dependencies or config until the locked tests pass.\n- Running the other tests the change touches is a check, not a gate: report a failure outside the locked tests, and let the hook's verdict decide the commit, since CI runs the rest.\n- If a test looks wrong, stop and report the test with the reason, instead of working around it.\n- Commit.\n\n"}, True: {'red.md': b'# shipcraft: the RED phase\n\nYou are the RED session: you write the failing tests for a change, not the change.\n\n- Write the failing tests from the intent, never from an implementation.\n- Write two cases per rule: the ordinary one, and a boundary a rushed GREEN would get wrong.\n- First read the existing tests that cover the behavior the change touches, and never contradict them unless the intent says that behavior changes.\n- Each test written for the new behavior must fail for the right reason before you run `npx -- shipcraft red`. Passing control tests are fine: they are locked as controls.\n- Fake external tools with their real output.\n- Commit the tests, their stubs and the lock in one commit, and stop.\n- List ambiguities instead of picking a reading silently.\n\n', 'green.md': b"# shipcraft: the GREEN phase\n\nYou are the GREEN session: you make the locked tests pass.\n\n- Start from the RED commit.\n- Never edit a locked file or a lock (`.shipcraft/locks/*`).\n- Change product code, dependencies or config until the locked tests pass.\n- Running the other tests the change touches is a check, not a gate: report a failure outside the locked tests, and let the hook's verdict decide the commit, since CI runs the rest.\n- If a test looks wrong, stop and report the test with the reason, instead of working around it.\n- Commit.\n\n"}}
GREEN_LINE=b"- Run the locked tests and the other tests the change affects, not the full suite unless the change affects all of it: CI runs it once (where CI is off, once before the PR). Report a failure outside the locked tests; it is not a gate: the hook's verdict decides the commit.\n"
OLD_GREEN_LINE=b"- Running the other tests the change touches is a check, not a gate: report a failure outside the locked tests, and let the hook's verdict decide the commit, since CI runs the rest.\n"
IMPORT=b'<!-- shipcraft -->\nShipcraft workflow (required): @AGENTS.md\n<!-- /shipcraft -->\n'
PREFIX=b'# House rules84\r\n\x00\n';SUFFIX=b'\nAfter84\r\nno final newline'
NEW=OLD75.replace(b'- A behavior change:',SIX+b'- A behavior change:',1)
STAMP=('<!-- written by shipcraft '+version+' -->\n').encode()
DIFF="; it differs from this version's: edit it by hand to match docs/spec.md"
SKIP="shipcraft: CLAUDE.md not written: AGENTS.md does not hold this version's shipcraft block"
def variant(block,local):
 if not local:return block
 text=block.replace(b'`shipcraft ',b'`npx -- shipcraft ')
 head,rest=text.split(b'\n- ',1)
 return head+b'\n'+ROOT_LINE+b'- '+rest
def write(path,data,mode=None):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
 if mode is not None:p.chmod(mode)
def run(*args,**kwargs):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,timeout=90,**kwargs)
 print('$',repr(args),'[rc='+str(p.returncode)+']\n'+(p.stdout+p.stderr).decode(errors='replace'),flush=True)
 return p
def fixture(local):
 root=Path(cw)/"project84 space 'quote";root.mkdir();os.chdir(root)
 p=run('git','init','-q',root);assert p.returncode==0
 write('requirements.txt',b'pytest\n')
 call=binary
 if local:
  target=root/'node_modules/shipcraft-fixture/bin/shipcraft';target.parent.mkdir(parents=True);shutil.copy2(binary,target)
  call=root/'node_modules/.bin/shipcraft';call.parent.mkdir(parents=True);call.symlink_to(target)
 return call
def output(p):return (p.stdout+p.stderr).decode(errors='replace')
if case=='fresh-bare':
 call=fixture(False);expected=variant(NEW,False)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'missing exact six-line block on fresh init'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'CLAUDE import changed'
elif case=='upgrade-bare-bare':
 call=fixture(False);old=PREFIX+variant(OLD75,False)+SUFFIX;expected=PREFIX+variant(NEW,False)+SUFFIX
 write('AGENTS.md',old,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'item75 known block did not upgrade to exact new bytes'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'upgrade changed mode'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'upgrade omitted exact CLAUDE import'
elif case=='upgrade-local-bare':
 call=fixture(False);old=PREFIX+variant(OLD75,True)+SUFFIX;expected=PREFIX+variant(NEW,False)+SUFFIX
 write('AGENTS.md',old,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'item75 known block did not upgrade to exact new bytes'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'upgrade changed mode'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'upgrade omitted exact CLAUDE import'
elif case=='older74-bare':
 call=fixture(False);old=PREFIX+variant(OLD74,True)+SUFFIX;expected=PREFIX+variant(NEW,False)+SUFFIX
 write('AGENTS.md',old,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'older known block did not upgrade straight to new bytes'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
 assert Path('CLAUDE.md').read_bytes()==IMPORT
elif case=='edited75-bare':
 call=fixture(False);expected=PREFIX+variant(OLD75,False).replace(b'TDD',b'EDITED84',1)+SUFFIX
 write('AGENTS.md',expected,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
 assert DIFF in output(p) and SKIP in output(p),'edited historical block missing differs/skip notice'
 assert not Path('CLAUDE.md').exists(),'edited block imported'
elif case=='equal-new-bare':
 call=fixture(False);expected=PREFIX+variant(NEW,True)+SUFFIX
 write('AGENTS.md',expected,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
 assert 'AGENTS.md already has the shipcraft block, kept' in output(p),'missing already-has notice'
elif case=='green-bare':
 call=fixture(False);expected=HISTORICAL_BRIEFS[False]['green.md'].replace(OLD_GREEN_LINE,GREEN_LINE)+STAMP
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('.shipcraft/briefs/green.md').read_bytes().rsplit(b'<!-- written by shipcraft ',1)[0]==expected.rsplit(b'<!-- written by shipcraft ',1)[0],'GREEN brief body not exact'
 assert Path('.shipcraft/briefs/green.md').read_bytes()==expected,'GREEN brief stamp not exact'
elif case=='red-body-control-bare':
 call=fixture(False);expected=HISTORICAL_BRIEFS[False]['red.md']
 p=run(call,'init')
 assert p.returncode==0,output(p)
 actual=Path('.shipcraft/briefs/red.md').read_bytes()
 assert actual.rsplit(b'<!-- written by shipcraft ',1)[0]==expected,'RED body changed'
elif case=='red-stamp-bare':
 call=fixture(False);expected=HISTORICAL_BRIEFS[False]['red.md']+STAMP
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('.shipcraft/briefs/red.md').read_bytes()==expected,'RED body or running-version stamp changed'
elif case=='old-green-bare':
 call=fixture(False);expected=HISTORICAL_BRIEFS[True]['green.md']+b'<!-- written by shipcraft 2.38.0 -->\n'
 write('.shipcraft/briefs/green.md',expected,0o444)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('.shipcraft/briefs/green.md').read_bytes()==expected and stat.S_IMODE(Path('.shipcraft/briefs/green.md').stat().st_mode)==0o444
 assert "shipcraft: .shipcraft/briefs/green.md differs from this version's, kept: compare it with docs/spec.md" in output(p)
 assert Path('.shipcraft/briefs/red.md').is_file(),'kept green suppressed red'
elif case=='old-green-control-bare':
 call=fixture(False);expected=HISTORICAL_BRIEFS[True]['green.md']+b'<!-- written by shipcraft 2.25.0 -->\n'
 write('.shipcraft/briefs/green.md',expected,0o444)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('.shipcraft/briefs/green.md').read_bytes()==expected and stat.S_IMODE(Path('.shipcraft/briefs/green.md').stat().st_mode)==0o444
 assert "shipcraft: .shipcraft/briefs/green.md differs from this version's, kept: compare it with docs/spec.md" in output(p)
 assert Path('.shipcraft/briefs/red.md').is_file(),'kept green suppressed red'
elif case=='later-brief-fails-bare':
 call=fixture(False);expected=PREFIX+variant(NEW,False)+SUFFIX;blocker=b'blocked briefs84\r\n'
 write('AGENTS.md',PREFIX+variant(OLD75,True)+SUFFIX,0o751);write('.shipcraft/briefs',blocker)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'later brief failure undid or prevented upgrade'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751 and Path('CLAUDE.md').read_bytes()==IMPORT
 assert Path('.shipcraft/briefs').read_bytes()==blocker
 assert 'shipcraft: .shipcraft/briefs not written: ' in output(p)
 assert Path('.shipcraft.toml').is_file() and Path('.shipcraft/locks/.gitkeep').read_bytes()==b''
elif case=='partial-bare':
 call=fixture(False);expected=PREFIX+variant(OLD75,False)+SUFFIX
 p=run(call,'init');assert p.returncode==0,output(p)
 write('AGENTS.md',expected,0o751);Path('CLAUDE.md').unlink()
 import resource,signal
 limit=len(expected)+8
 assert limit<len(PREFIX+variant(NEW,False)+SUFFIX),'size fixture not discriminating'
 def limited():
  signal.signal(signal.SIGXFSZ,signal.SIG_IGN);resource.setrlimit(resource.RLIMIT_FSIZE,(limit,limit))
 p=run(call,'init',preexec_fn=limited)
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'failed temporary write damaged historical file'
 assert 'AGENTS.md' in output(p) and 'could not write' in output(p),'missing new-block write failure notice'
 assert SKIP in output(p) and not Path('CLAUDE.md').exists()
 assert sorted(x.name for x in Path('.').iterdir())==sorted(['.git','.shipcraft','.shipcraft.toml','AGENTS.md','requirements.txt']+(['node_modules'] if False else [])),'temporary file leaked'
elif case=='partial-control-bare':
 call=fixture(False);expected=PREFIX+variant(OLD74,False)+SUFFIX
 p=run(call,'init');assert p.returncode==0,output(p)
 write('AGENTS.md',expected,0o751);Path('CLAUDE.md').unlink()
 import resource,signal
 limit=len(expected)+8
 assert limit<len(PREFIX+variant(OLD75,False)+SUFFIX),'control limit not below current write'
 def limited():
  signal.signal(signal.SIGXFSZ,signal.SIG_IGN);resource.setrlimit(resource.RLIMIT_FSIZE,(limit,limit))
 p=run(call,'init',preexec_fn=limited)
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
 assert 'AGENTS.md' in output(p) and 'could not write' in output(p) and SKIP in output(p)
 assert not Path('CLAUDE.md').exists()
elif case=='fresh-local':
 call=fixture(True);expected=variant(NEW,True)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'missing exact six-line block on fresh init'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'CLAUDE import changed'
elif case=='upgrade-bare-local':
 call=fixture(True);old=PREFIX+variant(OLD75,False)+SUFFIX;expected=PREFIX+variant(NEW,True)+SUFFIX
 write('AGENTS.md',old,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'item75 known block did not upgrade to exact new bytes'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'upgrade changed mode'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'upgrade omitted exact CLAUDE import'
elif case=='upgrade-local-local':
 call=fixture(True);old=PREFIX+variant(OLD75,True)+SUFFIX;expected=PREFIX+variant(NEW,True)+SUFFIX
 write('AGENTS.md',old,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'item75 known block did not upgrade to exact new bytes'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'upgrade changed mode'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'upgrade omitted exact CLAUDE import'
elif case=='older74-local':
 call=fixture(True);old=PREFIX+variant(OLD74,False)+SUFFIX;expected=PREFIX+variant(NEW,True)+SUFFIX
 write('AGENTS.md',old,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'older known block did not upgrade straight to new bytes'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
 assert Path('CLAUDE.md').read_bytes()==IMPORT
elif case=='edited75-local':
 call=fixture(True);expected=PREFIX+variant(OLD75,True).replace(b'TDD',b'EDITED84',1)+SUFFIX
 write('AGENTS.md',expected,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
 assert DIFF in output(p) and SKIP in output(p),'edited historical block missing differs/skip notice'
 assert not Path('CLAUDE.md').exists(),'edited block imported'
elif case=='equal-new-local':
 call=fixture(True);expected=PREFIX+variant(NEW,False)+SUFFIX
 write('AGENTS.md',expected,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
 assert 'AGENTS.md already has the shipcraft block, kept' in output(p),'missing already-has notice'
elif case=='green-local':
 call=fixture(True);expected=HISTORICAL_BRIEFS[True]['green.md'].replace(OLD_GREEN_LINE,GREEN_LINE)+STAMP
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('.shipcraft/briefs/green.md').read_bytes().rsplit(b'<!-- written by shipcraft ',1)[0]==expected.rsplit(b'<!-- written by shipcraft ',1)[0],'GREEN brief body not exact'
 assert Path('.shipcraft/briefs/green.md').read_bytes()==expected,'GREEN brief stamp not exact'
elif case=='red-body-control-local':
 call=fixture(True);expected=HISTORICAL_BRIEFS[True]['red.md']
 p=run(call,'init')
 assert p.returncode==0,output(p)
 actual=Path('.shipcraft/briefs/red.md').read_bytes()
 assert actual.rsplit(b'<!-- written by shipcraft ',1)[0]==expected,'RED body changed'
elif case=='red-stamp-local':
 call=fixture(True);expected=HISTORICAL_BRIEFS[True]['red.md']+STAMP
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('.shipcraft/briefs/red.md').read_bytes()==expected,'RED body or running-version stamp changed'
elif case=='old-green-local':
 call=fixture(True);expected=HISTORICAL_BRIEFS[False]['green.md']+b'<!-- written by shipcraft 2.38.0 -->\n'
 write('.shipcraft/briefs/green.md',expected,0o444)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('.shipcraft/briefs/green.md').read_bytes()==expected and stat.S_IMODE(Path('.shipcraft/briefs/green.md').stat().st_mode)==0o444
 assert "shipcraft: .shipcraft/briefs/green.md differs from this version's, kept: compare it with docs/spec.md" in output(p)
 assert Path('.shipcraft/briefs/red.md').is_file(),'kept green suppressed red'
elif case=='old-green-control-local':
 call=fixture(True);expected=HISTORICAL_BRIEFS[False]['green.md']+b'<!-- written by shipcraft 2.25.0 -->\n'
 write('.shipcraft/briefs/green.md',expected,0o444)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('.shipcraft/briefs/green.md').read_bytes()==expected and stat.S_IMODE(Path('.shipcraft/briefs/green.md').stat().st_mode)==0o444
 assert "shipcraft: .shipcraft/briefs/green.md differs from this version's, kept: compare it with docs/spec.md" in output(p)
 assert Path('.shipcraft/briefs/red.md').is_file(),'kept green suppressed red'
elif case=='later-brief-fails-local':
 call=fixture(True);expected=PREFIX+variant(NEW,True)+SUFFIX;blocker=b'blocked briefs84\r\n'
 write('AGENTS.md',PREFIX+variant(OLD75,False)+SUFFIX,0o751);write('.shipcraft/briefs',blocker)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'later brief failure undid or prevented upgrade'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751 and Path('CLAUDE.md').read_bytes()==IMPORT
 assert Path('.shipcraft/briefs').read_bytes()==blocker
 assert 'shipcraft: .shipcraft/briefs not written: ' in output(p)
 assert Path('.shipcraft.toml').is_file() and Path('.shipcraft/locks/.gitkeep').read_bytes()==b''
elif case=='partial-local':
 call=fixture(True);expected=PREFIX+variant(OLD75,True)+SUFFIX
 p=run(call,'init');assert p.returncode==0,output(p)
 write('AGENTS.md',expected,0o751);Path('CLAUDE.md').unlink()
 import resource,signal
 limit=len(expected)+8
 assert limit<len(PREFIX+variant(NEW,True)+SUFFIX),'size fixture not discriminating'
 def limited():
  signal.signal(signal.SIGXFSZ,signal.SIG_IGN);resource.setrlimit(resource.RLIMIT_FSIZE,(limit,limit))
 p=run(call,'init',preexec_fn=limited)
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'failed temporary write damaged historical file'
 assert 'AGENTS.md' in output(p) and 'could not write' in output(p),'missing new-block write failure notice'
 assert SKIP in output(p) and not Path('CLAUDE.md').exists()
 assert sorted(x.name for x in Path('.').iterdir())==sorted(['.git','.shipcraft','.shipcraft.toml','AGENTS.md','requirements.txt']+(['node_modules'] if True else [])),'temporary file leaked'
elif case=='partial-control-local':
 call=fixture(True);expected=PREFIX+variant(OLD74,True)+SUFFIX
 p=run(call,'init');assert p.returncode==0,output(p)
 write('AGENTS.md',expected,0o751);Path('CLAUDE.md').unlink()
 import resource,signal
 limit=len(expected)+8
 assert limit<len(PREFIX+variant(OLD75,True)+SUFFIX),'control limit not below current write'
 def limited():
  signal.signal(signal.SIGXFSZ,signal.SIG_IGN);resource.setrlimit(resource.RLIMIT_FSIZE,(limit,limit))
 p=run(call,'init',preexec_fn=limited)
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
 assert 'AGENTS.md' in output(p) and 'could not write' in output(p) and SKIP in output(p)
 assert not Path('CLAUDE.md').exists()
elif case=='brief-failure-control':
 call=fixture(False);expected=b'blocked briefs84\r\n'
 write('.shipcraft/briefs',expected)
 p=run(call,'init')
 assert p.returncode==0 and Path('.shipcraft/briefs').read_bytes()==expected,output(p)
 assert 'shipcraft: .shipcraft/briefs not written: ' in output(p)
 assert Path('AGENTS.md').is_file() and Path('CLAUDE.md').read_bytes()==IMPORT
 assert Path('.shipcraft.toml').is_file() and Path('.shipcraft/locks/.gitkeep').read_bytes()==b''
else:raise AssertionError('unrouted case: '+case)
PY84
  pass
}
