# Item 85: cleanup advice; public init and merge, offline GitHub only.
item85_langs() { echo core; }
item85_cases() {
  local c
  for c in fresh-bare upgrade-bare-bare upgrade-local-bare edited84-bare equal-new-bare historical-control-bare fresh-local upgrade-bare-local upgrade-local-local edited84-local equal-new-local historical-control-local older75 later-brief-fails brief-failure-control partial partial-control merge-default merge-default-waiver merge-other merge-other-waiver merge-control merge-refused merge-gh-fails-waiver; do echo "v1-85.$c"; done
}
item85_case() {
  EXPECT="item 85: ${CASE#v1-85.}"
  v1_start codex claude
  must_accept 'item 85 cleanup contract' cmd "$PY" - "${CASE#v1-85.}" "$(command -v shipcraft)" "$CW" "$ST" "$ACEITE" <<'PY85'
import ast,json,os,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw,st,acceptance=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw);st=Path(st)
# Item 86: only item 61's two block helpers, never its test execution.
source=(Path(acceptance)/'lib/item61.sh').read_text().split("<<'PY61'\n",1)[1].split('\nPY61',1)[0]
ns={}
for node in ast.parse(source).body:
 if isinstance(node,ast.FunctionDef) and node.name in ('has_lines','clean_block'):exec(compile(ast.Module(body=[node],type_ignores=[]),'item61-fixtures','exec'),ns)
# Independently pinned acceptance bytes from item84 at 1397349 (2.39.0).
OLD84=b"<!-- shipcraft -->\n## shipcraft: TDD with a lock (required in this repository)\n- Cycle: RED (a failing test) \xe2\x86\x92 `shipcraft red` \xe2\x86\x92 GREEN (code) \xe2\x86\x92 `git commit`. The git hook checks every commit.\n- Pick the lane first: a mechanical change, one that changes no behavior (text, config, data, content, a rename, docs), is committed directly once the tests it affects pass in one run, with no RED or GREEN; a behavior change takes the cycle.\n- A change that needs more than about 40 new test cases is split before its RED.\n- A review of the RED's tests before the lock takes at most one round and fixes contract bugs only (a test that asserts the wrong behavior).\n- Locally, the GREEN runs only the tests the change affects; the full suite runs once, in CI (where CI is off, once before the PR).\n- In PR review, only Blocking findings open another round; the others go to notes.\n- Small fixes from one request go in one PR.\n- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.\n- When the change fixes behavior a release already shipped, the RED runs `shipcraft red --fix`, with `--reported-at <time>` when the time the defect was first reported is known (for example `2026-10-31T00:36-03:00`) and `--fixes-release <tag>` when the release that shipped it is known (for example `v2.25.0`), so the lock records them.\n- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.\n- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.\n- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).\n- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.\n- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.\n- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.\n- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.\n- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.\n- If you run in a sandbox (for example Codex's `workspace-write`), run `shipcraft red`, `shipcraft red --redo` and `git commit` (its hook runs the locked tests) outside it when you can: inside, they can take many times longer, or fail when git cannot write its index. If you cannot, finish your files and stop (your files: those you added, changed or deleted, both sides of a rename), and give the user the steps to run in a POSIX shell where this project's tests run, each argument you fill in written in single quotes as above: first `cd` to this checkout's absolute path; for a RED, then `shipcraft red` (for a repair, `shipcraft red --redo`), which prints the lock's path; then `git --literal-pathspecs add -f --` with each of your files as its own argument and, for a RED, that lock path; then `git commit -m` with the message. A GREEN gets only the `cd`, `git add` and `git commit` steps. Tell the user to start from the first step that has not succeeded yet, and to stop and tell you if a step fails. If one of your files already had other changes before your phase, or `git diff --cached --name-only -z` lists a staged path that is not one of yours (or fails), say so and name those paths instead of handing the steps over. Change nothing after handing them over. Your phase ends there: you start no other phase, and a commit alone does not mean the lock closed (`shipcraft status` says).\n- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.\n- When in doubt, run `shipcraft status`.\n<!-- /shipcraft -->\n"
OLD75=b"<!-- shipcraft -->\n## shipcraft: TDD with a lock (required in this repository)\n- Cycle: RED (a failing test) \xe2\x86\x92 `shipcraft red` \xe2\x86\x92 GREEN (code) \xe2\x86\x92 `git commit`. The git hook checks every commit.\n- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.\n- When the change fixes behavior a release already shipped, the RED runs `shipcraft red --fix`, with `--reported-at <time>` when the time the defect was first reported is known (for example `2026-10-31T00:36-03:00`) and `--fixes-release <tag>` when the release that shipped it is known (for example `v2.25.0`), so the lock records them.\n- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.\n- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.\n- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).\n- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.\n- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.\n- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.\n- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.\n- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.\n- If you run in a sandbox (for example Codex's `workspace-write`), run `shipcraft red`, `shipcraft red --redo` and `git commit` (its hook runs the locked tests) outside it when you can: inside, they can take many times longer, or fail when git cannot write its index. If you cannot, finish your files and stop (your files: those you added, changed or deleted, both sides of a rename), and give the user the steps to run in a POSIX shell where this project's tests run, each argument you fill in written in single quotes as above: first `cd` to this checkout's absolute path; for a RED, then `shipcraft red` (for a repair, `shipcraft red --redo`), which prints the lock's path; then `git --literal-pathspecs add -f --` with each of your files as its own argument and, for a RED, that lock path; then `git commit -m` with the message. A GREEN gets only the `cd`, `git add` and `git commit` steps. Tell the user to start from the first step that has not succeeded yet, and to stop and tell you if a step fails. If one of your files already had other changes before your phase, or `git diff --cached --name-only -z` lists a staged path that is not one of yours (or fails), say so and name those paths instead of handing the steps over. Change nothing after handing them over. Your phase ends there: you start no other phase, and a commit alone does not mean the lock closed (`shipcraft status` says).\n- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.\n- When in doubt, run `shipcraft status`.\n<!-- /shipcraft -->\n"
ROOT_LINE=b"- Run Shipcraft commands from the repository root, where `npx -- shipcraft` runs this project's install.\n"
IMPORT=b'<!-- shipcraft -->\nShipcraft workflow (required): @AGENTS.md\n<!-- /shipcraft -->\n'
DIFF="; it differs from this version's: edit it by hand to match docs/spec.md"
SKIP="shipcraft: CLAUDE.md not written: AGENTS.md does not hold this version's shipcraft block"
CLEANUP=b'- After a merge, clean up what this change created: its worktree, temp folders, and servers or databases you started. Never remove what you did not create, what other sessions may be using, or anything with unmerged work: report those instead.\n'
NEW=OLD84.replace(b'- A behavior change:',CLEANUP+b'- A behavior change:',1)
PREFIX=b'# House rules85\r\n\x00\n';SUFFIX=b'\nAfter85\r\nno final newline'
ADVICE=b'shipcraft: clean up what this change created (worktree, temp folders, servers you started).\n'
def variant(block,local):
 if not local:return block
 text=block.replace(b'`shipcraft ',b'`npx -- shipcraft ')
 head,rest=text.split(b'\n- ',1)
 return head+b'\n'+ROOT_LINE+b'- '+rest
def current(local):
 # Item 86: the current block through public init, holding this item's frozen lines in order.
 block=ns['clean_block'](binary,local)
 assert ns['has_lines'](block,variant(NEW,local)),'current block lost or reordered an owned line'
 return block
def write(path,data,mode=None):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
 if mode is not None:p.chmod(mode)
def run(*args,**kwargs):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,timeout=90,**kwargs)
 print('$',repr(args),'[rc='+str(p.returncode)+']\n'+(p.stdout+p.stderr).decode(errors='replace'),flush=True)
 return p
def output(p):return (p.stdout+p.stderr).decode(errors='replace')
def fixture(local):
 root=cw/"project85 space 'quote";root.mkdir();os.chdir(root)
 subprocess.run(['git','init','-q','-b','main'],check=True)
 write('requirements.txt',b'pytest\n')
 call=binary
 if local:
  target=root/'node_modules/shipcraft-fixture/bin/shipcraft';target.parent.mkdir(parents=True);shutil.copy2(binary,target)
  call=root/'node_modules/.bin/shipcraft';call.parent.mkdir(parents=True);call.symlink_to(target)
 return call
def limited_size(limit):
 import resource,signal
 def limited():
  signal.signal(signal.SIGXFSZ,signal.SIG_IGN);resource.setrlimit(resource.RLIMIT_FSIZE,(limit,limit))
 return limited
def merge_fixture(base='main',ci=True,review=True,race=False):
 fixture(False)
 write('.shipcraft.toml',b'shipcraft_min="0.0"\ntest_command="echo {junit}"\ntest_globs=["tests/**"]\n[execution]\nci="local"\nreview="local"\n')
 def git(*args):return subprocess.check_output(['git',*map(str,args)],stderr=subprocess.STDOUT).decode().strip()
 git('config','user.name','RED85');git('config','user.email','red85@example.invalid')
 git('add','-A');tree=git('write-tree')
 tip=subprocess.check_output(['git','commit-tree',tree],input=b'fixture85 base\n').decode().strip();git('update-ref','HEAD',tip)
 origin=cw/'origin85.git';git('init','-q','--bare',origin);git('remote','add','origin',origin);git('push','-q','origin','main')
 if base!='main':git('branch',base);git('push','-q','origin',base)
 git('checkout','-q','-b','feature/cleanup85');write('change85',b'created by item85\n');git('add','-A');tree=git('write-tree')
 head=subprocess.check_output(['git','commit-tree',tree,'-p',tip],input=b'fixture85 change\n').decode().strip();git('update-ref','HEAD',head);git('push','-q','origin','HEAD')
 write(st/'origin',str(origin).encode());write(st/'sha',head.encode())
 subprocess.run(['gh','pr','create','--title','Cleanup85','--body','Item85','--head','feature/cleanup85','--base',base],check=True,env=dict(os.environ,SHIPCRAFT_STUB_QUIET='1'),capture_output=True)
 git('checkout','-q','main')
 statuses=[]
 for context,on in [('shipcraft/ci',ci),('shipcraft/review',review)]:
  if on:statuses.append(dict(id=len(statuses)+1,sha=head,context=context,state='success',description='item85 fixture',t=len(statuses)+1))
 write(st/'statuses.jsonl',b''.join((json.dumps(r)+'\n').encode() for r in statuses))
 if race:
  tree=git('rev-parse','feature/cleanup85^{tree}')
  moved=subprocess.check_output(['git','commit-tree',tree,'-p',head],input=b'fixture85 moved head\n').decode().strip()
  git('push','-q','origin',moved+':refs/heads/future85');write(st/'merge-head',moved.encode())
 return head,tip,origin
def rows():
 p=Path('.git/shipcraft/runs.jsonl')
 return [json.loads(s) for s in p.read_text().splitlines()] if p.exists() else []
if case=='fresh-bare':
 call=fixture(False);expected=variant(NEW,False)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert ns['has_lines'](Path('AGENTS.md').read_bytes(),expected),'missing the cleanup block on fresh init'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'CLAUDE import changed'
elif case=='upgrade-bare-bare':
 call=fixture(False);expected=PREFIX+current(False)+SUFFIX
 write('AGENTS.md',PREFIX+variant(OLD84,False)+SUFFIX,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'item84 known block did not upgrade to exact cleanup bytes'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'upgrade changed mode'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'upgrade omitted exact import'
elif case=='upgrade-local-bare':
 call=fixture(False);expected=PREFIX+current(False)+SUFFIX
 write('AGENTS.md',PREFIX+variant(OLD84,True)+SUFFIX,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'item84 known block did not upgrade to exact cleanup bytes'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'upgrade changed mode'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'upgrade omitted exact import'
elif case=='edited84-bare':
 call=fixture(False);expected=PREFIX+variant(OLD84,False).replace(b'TDD',b'EDITED85',1)+SUFFIX
 write('AGENTS.md',expected,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
 assert DIFF in output(p) and SKIP in output(p),'edited item84 block missing differs/skip notices'
 assert not Path('CLAUDE.md').exists(),'edited block imported'
elif case=='equal-new-bare':
 call=fixture(False);expected=PREFIX+current(False)+SUFFIX
 write('AGENTS.md',expected,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
 assert 'AGENTS.md already has the shipcraft block, kept' in output(p)
 assert DIFF not in output(p),'equal new block was treated as unknown'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'equal current block must qualify for import'
elif case=='historical-control-bare':
 call=fixture(False);before=PREFIX+variant(OLD84,True)+SUFFIX
 write('AGENTS.md',before,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 actual=Path('AGENTS.md').read_bytes()
 assert actual in (PREFIX+variant(OLD84,False)+SUFFIX,PREFIX+current(False)+SUFFIX),'historical fixture not recognized or wrong install variant'
 assert actual!=before,'cross-variant historical fixture took the keep-unknown path'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751 and Path('CLAUDE.md').read_bytes()==IMPORT
 assert DIFF not in output(p) and SKIP not in output(p)
elif case=='fresh-local':
 call=fixture(True);expected=variant(NEW,True)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert ns['has_lines'](Path('AGENTS.md').read_bytes(),expected),'missing the cleanup block on fresh init'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'CLAUDE import changed'
elif case=='upgrade-bare-local':
 call=fixture(True);expected=PREFIX+current(True)+SUFFIX
 write('AGENTS.md',PREFIX+variant(OLD84,False)+SUFFIX,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'item84 known block did not upgrade to exact cleanup bytes'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'upgrade changed mode'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'upgrade omitted exact import'
elif case=='upgrade-local-local':
 call=fixture(True);expected=PREFIX+current(True)+SUFFIX
 write('AGENTS.md',PREFIX+variant(OLD84,True)+SUFFIX,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'item84 known block did not upgrade to exact cleanup bytes'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'upgrade changed mode'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'upgrade omitted exact import'
elif case=='edited84-local':
 call=fixture(True);expected=PREFIX+variant(OLD84,True).replace(b'TDD',b'EDITED85',1)+SUFFIX
 write('AGENTS.md',expected,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
 assert DIFF in output(p) and SKIP in output(p),'edited item84 block missing differs/skip notices'
 assert not Path('CLAUDE.md').exists(),'edited block imported'
elif case=='equal-new-local':
 call=fixture(True);expected=PREFIX+current(True)+SUFFIX
 write('AGENTS.md',expected,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
 assert 'AGENTS.md already has the shipcraft block, kept' in output(p)
 assert DIFF not in output(p),'equal new block was treated as unknown'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'equal current block must qualify for import'
elif case=='historical-control-local':
 call=fixture(True);before=PREFIX+variant(OLD84,False)+SUFFIX
 write('AGENTS.md',before,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 actual=Path('AGENTS.md').read_bytes()
 assert actual in (PREFIX+variant(OLD84,True)+SUFFIX,PREFIX+current(True)+SUFFIX),'historical fixture not recognized or wrong install variant'
 assert actual!=before,'cross-variant historical fixture took the keep-unknown path'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751 and Path('CLAUDE.md').read_bytes()==IMPORT
 assert DIFF not in output(p) and SKIP not in output(p)
elif case=='older75':
 call=fixture(False);expected=PREFIX+current(False)+SUFFIX
 write('AGENTS.md',PREFIX+variant(OLD75,True)+SUFFIX,0o751)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'older75 did not upgrade straight to cleanup block'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751 and Path('CLAUDE.md').read_bytes()==IMPORT
elif case=='later-brief-fails':
 call=fixture(False);expected=PREFIX+current(False)+SUFFIX;blocker=b'blocked briefs85\r\n'
 write('AGENTS.md',PREFIX+variant(OLD84,True)+SUFFIX,0o751);write('.shipcraft/briefs',blocker)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected,'later brief failure prevented or undid cleanup upgrade'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751 and Path('CLAUDE.md').read_bytes()==IMPORT
 assert Path('.shipcraft/briefs').read_bytes()==blocker and 'shipcraft: .shipcraft/briefs not written: ' in output(p)
 assert Path('.shipcraft.toml').is_file() and Path('.shipcraft/locks/.gitkeep').read_bytes()==b''
elif case=='brief-failure-control':
 call=fixture(False);blocker=b'blocked briefs85\r\n'
 write('.shipcraft/briefs',blocker)
 p=run(call,'init')
 assert p.returncode==0,output(p)
 assert Path('.shipcraft/briefs').read_bytes()==blocker and 'shipcraft: .shipcraft/briefs not written: ' in output(p)
 assert Path('CLAUDE.md').read_bytes()==IMPORT and Path('.shipcraft.toml').is_file() and Path('.shipcraft/locks/.gitkeep').read_bytes()==b''
elif case=='partial':
 call=fixture(False);expected=PREFIX+OLD84+SUFFIX
 p=run(call,'init');assert p.returncode==0,output(p)
 write('AGENTS.md',expected,0o751);Path('CLAUDE.md').unlink()
 limit=len(expected)+8
 assert limit<len(PREFIX+NEW+SUFFIX),'write-limit fixture not discriminating'
 p=run(call,'init',preexec_fn=limited_size(limit))
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'partial write damaged original'
 assert 'AGENTS.md' in output(p) and 'could not write' in output(p),'missing attempted-upgrade write-failure notice'
 assert SKIP in output(p) and not Path('CLAUDE.md').exists()
 assert sorted(p.name for p in Path('.').iterdir())==sorted(['.git','.shipcraft','.shipcraft.toml','AGENTS.md','requirements.txt']),'temporary file leaked'
elif case=='partial-control':
 call=fixture(False);expected=PREFIX+OLD75+SUFFIX
 p=run(call,'init');assert p.returncode==0,output(p)
 write('AGENTS.md',expected,0o751);Path('CLAUDE.md').unlink()
 limit=len(expected)+8
 assert limit<len(PREFIX+OLD84+SUFFIX),'write-limit fixture not discriminating'
 p=run(call,'init',preexec_fn=limited_size(limit))
 assert p.returncode==0,output(p)
 assert Path('AGENTS.md').read_bytes()==expected and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'partial write damaged original'
 assert 'AGENTS.md' in output(p) and 'could not write' in output(p),'missing attempted-upgrade write-failure notice'
 assert SKIP in output(p) and not Path('CLAUDE.md').exists()
 assert sorted(p.name for p in Path('.').iterdir())==sorted(['.git','.shipcraft','.shipcraft.toml','AGENTS.md','requirements.txt']),'temporary file leaked'
elif case=='merge-default':
 head,tip,origin=merge_fixture('main',review=True)
 p=run(binary,'merge','1')
 assert p.returncode==0,output(p)
 assert len(rows())==1 and rows()[0]['layer']=='merge' and rows()[0]['commit']==head
 assert subprocess.check_output(['git','--git-dir='+str(origin),'rev-parse','refs/heads/feature/cleanup85']).decode().strip()==head,'merge deleted head branch'
 lines=p.stdout.splitlines(keepends=True);expected=ADVICE
 merged=[i for i,line in enumerate(lines) if line.startswith(b'shipcraft: PR #1 merged into '+b'main')]
 assert len(merged)==1,'existing merged line changed'
 assert lines.count(expected)==1 and lines[merged[0]+1:merged[0]+2]==[expected],'missing exact cleanup advice immediately after merged line on stdout'
 assert expected not in p.stderr,'cleanup advice on stderr'
elif case=='merge-default-waiver':
 head,tip,origin=merge_fixture('main',review=False)
 p=run(binary,'merge','1','--no-review','item85 waiver')
 assert p.returncode==0,output(p)
 assert len(rows())==1 and rows()[0]['layer']=='merge' and rows()[0]['commit']==head
 assert subprocess.check_output(['git','--git-dir='+str(origin),'rev-parse','refs/heads/feature/cleanup85']).decode().strip()==head,'merge deleted head branch'
 lines=p.stdout.splitlines(keepends=True);expected=ADVICE
 merged=[i for i,line in enumerate(lines) if line.startswith(b'shipcraft: PR #1 merged into '+b'main')]
 assert len(merged)==1,'existing merged line changed'
 assert lines.count(expected)==1 and lines[merged[0]+1:merged[0]+2]==[expected],'missing exact cleanup advice immediately after merged line on stdout'
 assert expected not in p.stderr,'cleanup advice on stderr'
elif case=='merge-other':
 head,tip,origin=merge_fixture('release/85',review=True)
 p=run(binary,'merge','1')
 assert p.returncode==0,output(p)
 assert len(rows())==1 and rows()[0]['layer']=='merge' and rows()[0]['commit']==head
 assert subprocess.check_output(['git','--git-dir='+str(origin),'rev-parse','refs/heads/feature/cleanup85']).decode().strip()==head,'merge deleted head branch'
 lines=p.stdout.splitlines(keepends=True);expected=ADVICE
 merged=[i for i,line in enumerate(lines) if line.startswith(b'shipcraft: PR #1 merged into '+b'release/85')]
 assert len(merged)==1,'existing merged line changed'
 assert lines.count(expected)==1 and lines[merged[0]+1:merged[0]+2]==[expected],'missing exact cleanup advice immediately after merged line on stdout'
 assert expected not in p.stderr,'cleanup advice on stderr'
elif case=='merge-other-waiver':
 head,tip,origin=merge_fixture('release/85',review=False)
 p=run(binary,'merge','1','--no-review','item85 waiver')
 assert p.returncode==0,output(p)
 assert len(rows())==1 and rows()[0]['layer']=='merge' and rows()[0]['commit']==head
 assert subprocess.check_output(['git','--git-dir='+str(origin),'rev-parse','refs/heads/feature/cleanup85']).decode().strip()==head,'merge deleted head branch'
 lines=p.stdout.splitlines(keepends=True);expected=ADVICE
 merged=[i for i,line in enumerate(lines) if line.startswith(b'shipcraft: PR #1 merged into '+b'release/85')]
 assert len(merged)==1,'existing merged line changed'
 assert lines.count(expected)==1 and lines[merged[0]+1:merged[0]+2]==[expected],'missing exact cleanup advice immediately after merged line on stdout'
 assert expected not in p.stderr,'cleanup advice on stderr'
elif case=='merge-control':
 head,tip,origin=merge_fixture('release/85')
 p=run(binary,'merge','1')
 assert p.returncode==0,output(p)
 assert b'shipcraft: PR #1 merged into release/85' in p.stdout,'wrong base path'
 assert len(rows())==1 and rows()[0]['layer']=='merge' and rows()[0]['commit']==head and rows()[0]['base']=='release/85' and rows()[0]['default_branch']=='main'
 assert subprocess.check_output(['git','--git-dir='+str(origin),'rev-parse','refs/heads/release/85']).decode().strip()!=tip
 assert subprocess.check_output(['git','--git-dir='+str(origin),'rev-parse','refs/heads/main']).decode().strip()==tip
elif case=='merge-refused':
 head,tip,origin=merge_fixture(ci=False)
 p=run(binary,'merge','1')
 assert p.returncode==1,output(p)
 lines=output(p).strip().splitlines()
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:') and 'shipcraft/ci' in output(p)
 assert rows()==[],'refused merge appended row'
 assert ADVICE not in p.stdout+p.stderr,'refused merge printed cleanup advice'
 assert subprocess.check_output(['git','--git-dir='+str(origin),'rev-parse','main']).decode().strip()==tip
 assert not any(json.loads(s)['argv'][:2]==['pr','merge'] for s in (st/'calls.log').read_text().splitlines())
elif case=='merge-gh-fails-waiver':
 head,tip,origin=merge_fixture(review=False,race=True)
 p=run(binary,'merge','1','--no-review','item85 failed waiver')
 assert p.returncode==2,output(p)
 assert head in output(p),'failed pinned merge did not name checked head'
 assert rows()==[] and ADVICE not in p.stdout+p.stderr,'failed merge wrote row or cleanup advice'
 assert subprocess.check_output(['git','--git-dir='+str(origin),'rev-parse','main']).decode().strip()==tip
 calls=[json.loads(s)['argv'] for s in (st/'calls.log').read_text().splitlines()]
 merges=[a for a in calls if a[:2]==['pr','merge']]
 assert len(merges)==1 and '--match-head-commit' in merges[0] and merges[0][merges[0].index('--match-head-commit')+1]==head
 comments=[json.loads(s) for s in (st/'writes.log').read_text().splitlines() if json.loads(s).get('kind')=='comment']
 assert len(comments)==1 and 'item85 failed waiver' in json.dumps(comments),'waiver comment lost on later failure'
else:raise AssertionError('unrouted case: '+case)
PY85
  pass
}
