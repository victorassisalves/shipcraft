# Item 61: onboarding, through the public binary only. Git stays in each case project.
item61_langs() { echo core; }
item61_cases() {
  local c
  for c in block local-block append append-empty append-lines replace-local replace-bare legacy equal edited edited-legacy duplicate end-first crlf marker-cr invalid readonly mode directory claude-present claude-absent claude-append claude-equal claude-edited claude-crlf claude-duplicate claude-invalid claude-readonly claude-link claude-dangling agents-link agents-kept agents-link-present agents-kept-present agents-kept-absent refused refused-late hint-version hint-noargs hint-help hint-h hint-longhelp hint-config hint-outside hint-git-fails; do echo "v1-61.$c"; done
}
item61_case() {
  EXPECT="item 61: ${CASE#v1-61.}"
  v1_start codex
  must_accept 'item 61 onboarding contract' cmd "$PY" - "${CASE#v1-61.}" "$(command -v shipcraft)" <<'PY61'
import os,re,shlex,shutil,stat,subprocess,sys
from pathlib import Path
case,binary=sys.argv[1:]; binary=str(Path(binary).resolve())
root=Path.cwd().resolve(); errors=[]
START=b'<!-- shipcraft -->'; END=b'<!-- /shipcraft -->'
IMPORT=START+b'\nShipcraft workflow (required): @AGENTS.md\n'+END+b'\n'
# Only AGENTS_BLOCK's text, copied from git show v2.14.0:nucleo/src/init.rs.
OLD='''<!-- shipcraft -->
## shipcraft: TDD with a lock (required in this repository)
- Cycle: RED (a failing test) → `shipcraft red` → GREEN (code) → `git commit`. The git hook checks every commit.
- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.
- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.
- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*`, never touch the hook or `core.hooksPath`.
- When in doubt, run `shipcraft status`.
'''.encode()
# Exact v2.22.0 fixture; only this historical constant and agents_text were read.
PREVIOUS_BARE='''<!-- shipcraft -->
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
'''.encode()
ROOT_LINE=b"- Run Shipcraft commands from the repository root, where `npx -- shipcraft` runs this project's install.\n"
PREVIOUS_LOCAL=PREVIOUS_BARE.replace(b'`shipcraft ',b'`npx -- shipcraft ')
head,rest=PREVIOUS_LOCAL.split(b'\n- ',1)
PREVIOUS_LOCAL=head+b'\n'+ROOT_LINE+b'- '+rest
READ_TESTS=b'- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.\n'
REPAIR=b"A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user."
ROLES=b'- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.\n'
FALLBACK=b"- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.\n"
SANDBOX=b"- If you run in a sandbox (for example Codex's `workspace-write`), run `shipcraft red`, `shipcraft red --redo` and `git commit` (its hook runs the locked tests) outside it when you can: inside, they can take many times longer, or fail when git cannot write its index. If you cannot, finish your files and stop (your files: those you added, changed or deleted, both sides of a rename), and give the user the steps to run in a POSIX shell where this project's tests run, each argument you fill in written in single quotes as above: first `cd` to this checkout's absolute path; for a RED, then `shipcraft red` (for a repair, `shipcraft red --redo`), which prints the lock's path; then `git --literal-pathspecs add -f --` with each of your files as its own argument and, for a RED, that lock path; then `git commit -m` with the message. A GREEN gets only the `cd`, `git add` and `git commit` steps. Tell the user to start from the first step that has not succeeded yet, and to stop and tell you if a step fails. If one of your files already had other changes before your phase, or `git diff --cached --name-only -z` lists a staged path that is not one of yours (or fails), say so and name those paths instead of handing the steps over. Change nothing after handing them over. Your phase ends there: you start no other phase, and a commit alone does not mean the lock closed (`shipcraft status` says).\n"
FIX_DATA=b'- When the change fixes behavior a release already shipped, the RED runs `shipcraft red --fix`, with `--reported-at <time>` when the time the defect was first reported is known (for example `2026-10-31T00:36-03:00`) and `--fixes-release <tag>` when the release that shipped it is known (for example `v2.25.0`), so the lock records them.\n'
def expected_block(local=False):
 lines=PREVIOUS_BARE.splitlines(keepends=True); result=[]
 for line in lines:
  if line.startswith(b'- The GREEN session '):
   line=line.replace(b'A test it finds wrong is reported back, and a RED session fixes it with `shipcraft red --redo`.',REPAIR)
  result.append(line)
  if line.startswith(b'- Cycle:'): result.append(b"- Pick the lane first: a mechanical change, one that changes no behavior (text, config, data, content, a rename, docs), is committed directly once the tests it affects pass in one run, with no RED or GREEN; a behavior change takes the cycle.\n- A change that needs more than about 40 new test cases is split before its RED.\n- A review of the RED's tests before the lock takes at most one round and fixes contract bugs only (a test that asserts the wrong behavior).\n- Locally, the GREEN runs only the tests the change affects; the full suite runs once, in CI (where CI is off, once before the PR).\n- In PR review, only Blocking findings open another round; the others go to notes.\n- Small fixes from one request go in one PR.\n")
  if line.startswith(b'- A behavior change:'): result.append(FIX_DATA); result.append(READ_TESTS)
  if line.startswith(b'- A session told it is '): result.append(ROLES); result.append(FALLBACK); result.append(SANDBOX)
 text=b''.join(result)
 if local:
  text=text.replace(b'`shipcraft ',b'`npx -- shipcraft ')
  head,rest=text.split(b'\n- ',1);text=head+b'\n'+ROOT_LINE+b'- '+rest
 return text
HINT='shipcraft: next step (required): run `shipcraft init` at the repository root to set up Shipcraft; until init runs, Shipcraft checks none of your commits; if init refuses, follow its Next line'
SKIP="shipcraft: CLAUDE.md not written: AGENTS.md does not hold this version's shipcraft block"
DIFF="; it differs from this version's: edit it by hand to match docs/spec.md"
def want(v,msg):
 if not v: errors.append(msg)
def write(p,b,mode=None):
 p=Path(p); p.parent.mkdir(parents=True,exist_ok=True); p.write_bytes(b if isinstance(b,bytes) else b.encode())
 if mode is not None: p.chmod(mode)
def run(*args,cwd=None,env=None,ok=True):
 p=subprocess.run(args,cwd=cwd,env=env,capture_output=True,timeout=90)
 print('$',shlex.join(map(str,args)),'[rc='+str(p.returncode)+']\n'+(p.stdout+p.stderr).decode(errors='replace'),flush=True)
 if ok: assert p.returncode==0,'command failed before assertion'
 return p
def output(p): return (p.stdout+p.stderr).decode(errors='replace')
def init(call=binary,ok=True): return run(str(call),'init',ok=ok)
def fresh(name,local=False):
 d=root/name; d.mkdir(); run('git','init','-q',str(d)); write(d/'requirements.txt','pytest\n')
 call=Path(binary)
 if local:
  call=d/'node_modules/shipcraft-fixture/bin/shipcraft'; call.parent.mkdir(parents=True); shutil.copy2(binary,call)
  launcher=d/'node_modules/.bin/shipcraft'; launcher.parent.mkdir(parents=True); launcher.symlink_to(call); call=launcher
 return d,call
def sample(name,local=False):
 d,call=fresh(name,local); run(str(call),'init',cwd=d); return (d/'AGENTS.md').read_bytes()
def current(): return sample('sample61')
def closed(b): return b.splitlines()[0]==START and b.splitlines()[-1]==END and b.endswith(b'\n') and b'\r' not in b
def notice(p,name,kind):
 s=output(p); want(name in s and kind in s,'missing '+name+' '+kind+' notice')
def closing(p,name):
 lines=[l for l in output(p).splitlines() if l.startswith('shipcraft: ready. Commit ')]
 want(len(lines)==1 and name in lines[0],'closing guidance omitted '+name)
def kept(p,name,b,diff=False):
 want(Path(name).read_bytes()==b,name+' bytes changed')
 if diff: notice(p,name,'already has the shipcraft block, kept'); want(DIFF in output(p),'missing manual-edit guidance')
def block_contract(b,local):
 want(closed(b),'new AGENTS block must have LF start/end lines')
 want(b==expected_block(local),'item 68 block must make exactly the three specified changes, with all other bytes and line order preserved')
 s=b.decode(); low=s.lower()
 patterns=[r'claude code',r'subagent',r'codex exec',r'resume',r'same (?:checkout|working tree)',r'RED.*?commit',r'stubs?',r'GREEN',r'dependenc',r'lockfiles?',r'config',r'red --redo',r'by hand',r'user',r'(?:not protect|unprotected|does not protect|outside.*?lock)']
 for pat in patterns: want(re.search(pat,s,re.I|re.S) is not None,'block omitted '+pat)
 want(re.search(r'(?:different|separate|new).*?sessions?',s,re.I|re.S) is not None,'missing separate-session instruction')
 want(re.search(r'RED(?:(?!GREEN).)*?commit(?:(?!GREEN).)*?stop',s,re.I|re.S) is not None,'RED must commit and stop')
 want(re.search(r'GREEN.*?(?:start|from).*?commit',s,re.I|re.S) is not None,'GREEN must start from RED commit')
 want(re.search(r'(?:starts? no|never start|do not start|must not start|does not start)',low) is not None,'phase session must start no other session')
 for old in ('--no-verify','core.hooksPath','.shipcraft/locks/*','status'): want(old in s,'lost existing rule '+old)
 commands=re.findall(r'`([^`\n]*shipcraft[^`\n]*)`',s)
 want(any(('npx -- shipcraft red' if local else 'shipcraft red') in c for c in commands),'missing RED command form')
 if local:
  want(all('npx -- shipcraft' in c for c in commands if re.search(r'\bshipcraft\s+(?:red|status|close|check)',c)),'bare Shipcraft command in local block')
  want('repository root' in low,'local block omitted repository root instruction')
 else: want('npx -- shipcraft' not in s,'machine block uses npx')

if case.startswith('hint-'):
 args={'hint-version':['--version'],'hint-noargs':[],'hint-help':['help'],'hint-h':['-h'],'hint-longhelp':['--help']}
 # No parent .git: place the outside control in the case-owned sibling directory.
 outside=Path(os.environ['HOME']).parent/'outside61'; outside.mkdir(exist_ok=True)
 env=dict(os.environ,GIT_CEILING_DIRECTORIES=str(outside.parent))
 log=Path('.git/shipcraft/runs.jsonl'); write(log,b'preserve-log61\n'); before=log.read_bytes()
 if case in args:
  a=args[case]; base=run(binary,*a,cwd=outside,env=env,ok=False)
  nested=Path('nested61'); nested.mkdir(); p=run(binary,*a,cwd=nested,ok=False)
  want(p.stdout==base.stdout and p.returncode==base.returncode,'hint changed stdout/exit')
  want(p.stderr==base.stderr+(HINT+'\n').encode(),'missing or inexact stderr hint')
 elif case=='hint-config':
  for kind in ('regular','symlink','directory','dangling'):
   cfg=Path('.shipcraft.toml')
   if kind=='regular': write(cfg,'invalid config: must not read\n')
   elif kind=='directory': cfg.mkdir()
   else: cfg.symlink_to('requirements.txt' if kind=='symlink' else 'missing61')
   for a in args.values():
    base=run(binary,*a,cwd=outside,env=env,ok=False); p=run(binary,*a,ok=False)
    want((p.stdout,p.stderr,p.returncode)==(base.stdout,base.stderr,base.returncode),'existing '+kind+' config changed usage')
   if cfg.is_dir(): cfg.rmdir()
   else: cfg.unlink()
 elif case=='hint-git-fails':
  tools=root/'fail-git61'; tools.mkdir(); write(tools/'git','#!/bin/sh\nexit 1\n',0o755)
  bad=dict(os.environ,PATH=str(tools)+os.pathsep+os.environ['PATH'])
  for a in args.values():
   base=run(binary,*a,cwd=outside,env=env,ok=False); p=run(binary,*a,env=bad,ok=False)
   want((p.stdout,p.stderr,p.returncode)==(base.stdout,base.stderr,base.returncode),'failed git lookup added hint/changed usage')
 else:
  for a in args.values():
   p=run(binary,*a,cwd=outside,env=env,ok=False); want(all(h not in p.stderr for h in (HINT.encode(), b'shipcraft: not set up in this repository: run shipcraft init (from a package install: pnpm exec shipcraft init, or npx shipcraft init)')),'outside repo printed hint')
 want(log.read_bytes()==before,'usage wrote a run-log row')
elif case in ('refused','refused-late'):
 if case=='refused': write('.git/hooks/commit-msg','#!/bin/sh\necho foreign61\n',0o755)
 else: write('.shipcraft','blocked61\n')
 log=Path('.git/shipcraft/sentinel61'); write(log,'keep61\n')
 # Claude is present so a premature write of either file is visible.
 write(Path(os.environ['PATH'].split(os.pathsep)[0])/'claude','#!/bin/sh\nexit 0\n',0o755)
 p=init(ok=False); want(p.returncode==(1 if case=='refused' else 2),'wrong init refusal/error exit')
 want(not Path('AGENTS.md').exists() and not Path('CLAUDE.md').exists(),'refused init wrote onboarding files')
 want(log.read_bytes()==b'keep61\n','refusal changed .git/shipcraft')
 if case=='refused':
  lines=output(p).strip().splitlines(); want(len(lines)>=3 and lines[-3].startswith('shipcraft refused: ') and lines[-2].startswith('Why: ') and lines[-1].startswith('Next: '),'refusal must end in three guidance lines')
elif case in ('block','local-block'):
 if case=='local-block':
  d,call=fresh('local61',True); os.chdir(d); p=init(call)
 else: p=init()
 b=Path('AGENTS.md').read_bytes(); block_contract(b,case=='local-block'); closing(p,'AGENTS.md')
elif case in ('replace-local','replace-bare'):
 bare=sample('bare61'); local=sample('local61',True)
 want(bare!=local,'current variants must differ in command form')
 old,new=(local,bare) if case=='replace-local' else (bare,local)
 prefix=b'# Before61\r\n\x00\n'; suffix=b'\nAfter61\r\nno final newline'
 write('AGENTS.md',prefix+old+suffix)
 call=binary
 if case=='replace-bare':
  call=root/'node_modules/shipcraft-fixture/bin/shipcraft'; call.parent.mkdir(parents=True); shutil.copy2(binary,call)
  launcher=root/'node_modules/.bin/shipcraft'; launcher.parent.mkdir(parents=True); launcher.symlink_to(call); call=launcher
 p=init(call); want(Path('AGENTS.md').read_bytes()==prefix+new+suffix,'other current variant not replaced with surrounding bytes preserved'); want(closed(new),'replacement must be the ended current block'); closing(p,'AGENTS.md')
elif case in ('append','append-empty','append-lines','legacy','equal','edited','edited-legacy','duplicate','end-first','crlf','marker-cr','invalid','readonly','mode','directory'):
 new=current(); prefix=b'# Rules61\r\n'; suffix=b'After61\r\nno final newline'
 if case=='append': before=b'Rules61 without newline'; expected=before+b'\n\n'+new
 elif case=='append-empty': before=b''; expected=new
 elif case=='append-lines': before=b'\xef\xbb\xbf<!-- shipcraft -->\n<!-- shipcraft --> \n<!-- shipcraft -->\xe2\x80\xa8not a marker\n'; expected=before+b'\n'+new
 elif case in ('legacy','mode'): before=prefix+OLD+suffix; expected=prefix+new+suffix
 elif case=='readonly': before=b'Owner cannot write61\n'
 elif case=='equal': before=prefix+new+suffix
 elif case=='edited': before=prefix+new.replace(b'\n',b'\nEdited61\n',1)+suffix
 elif case=='edited-legacy': before=prefix+OLD.replace(b'TDD',b'EDITED61',1)+suffix
 elif case=='duplicate': before=START+b'\n'+new
 elif case=='end-first': before=END+b'\n'+new
 elif case=='crlf': before=new.replace(b'\n',b'\r\n')
 elif case=='marker-cr': before=b'```\n'+START+b'\r\nforeign61\n'+END+b'\r\n```\n'
 elif case=='invalid': before=b'Rules61\xff\n'
 else: before=b''
 if case=='directory': Path('AGENTS.md').mkdir(); p=init(); want(Path('AGENTS.md').is_dir(),'nonregular AGENTS entry replaced'); notice(p,'AGENTS.md','kept')
 else:
  write('AGENTS.md',before,0o444 if case=='readonly' else 0o751 if case=='mode' else None)
  p=init()
  if case in ('append','append-empty','append-lines','legacy','mode'):
   want(Path('AGENTS.md').read_bytes()==expected,'append/migration did not preserve exact surrounding bytes')
   want(closed(new),'written block lacks end marker'); closing(p,'AGENTS.md')
  else:
   kept(p,'AGENTS.md',before,case in ('edited','edited-legacy','duplicate','end-first','crlf','marker-cr'))
   if case=='equal': notice(p,'AGENTS.md','already has the shipcraft block'); want(DIFF not in output(p),'equal block called different')
   if case in ('invalid','readonly'): notice(p,'AGENTS.md','could not write'); want('by hand' in output(p),'missing manual recovery guidance')
  if case in ('readonly','mode'): want(stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==(0o444 if case=='readonly' else 0o751),'permission bits changed')
  want(not [p for p in root.iterdir() if p.name not in {'.git','.gitignore','.venv','.shipcraft','.shipcraft.toml','AGENTS.md','CLAUDE.md','requirements.txt','textutil.py','tests','sample61','README.md','pyproject.toml'} and ('tmp' in p.name or 'AGENTS' in p.name)],'temporary rewrite file leaked')
else:
 present=case in ('claude-present','agents-link-present','agents-kept-present')
 if present: write(Path(os.environ['PATH'].split(os.pathsep)[0])/'claude','#!/bin/sh\nexit 0\n',0o755)
 agents_bad=case.startswith('agents-')
 if case in ('agents-link','agents-link-present'): write('agent-target61','outside61\n'); Path('AGENTS.md').symlink_to('agent-target61')
 elif agents_bad: write('AGENTS.md',START+b'\ncustom61\n'+END+b'\n')
 before=None
 if case in ('claude-append','agents-link','agents-kept'): before=b'# Claude rules61'; write('CLAUDE.md',before)
 elif case=='claude-equal': before=IMPORT; write('CLAUDE.md',before)
 elif case=='claude-edited': before=IMPORT.replace(b'@AGENTS.md',b'@OTHER.md'); write('CLAUDE.md',before)
 elif case=='claude-crlf': before=IMPORT.replace(b'\n',b'\r\n'); write('CLAUDE.md',before)
 elif case=='claude-duplicate': before=START+b'\n'+IMPORT; write('CLAUDE.md',before)
 elif case=='claude-invalid': before=b'\xff\n'; write('CLAUDE.md',before)
 elif case=='claude-readonly': before=b'Keep61\n'; write('CLAUDE.md',before,0o444)
 elif case in ('claude-link','claude-dangling'):
  if case=='claude-link': write('claude-target61','outside61\n')
  Path('CLAUDE.md').symlink_to('claude-target61')
 agent_before=Path('AGENTS.md').read_bytes() if agents_bad else None
 p=init(); f=Path('CLAUDE.md')
 if agents_bad: want(Path('AGENTS.md').read_bytes()==agent_before,'ineligible AGENTS bytes changed')
 if case=='claude-present':
  want(f.is_file() and f.read_bytes()==IMPORT,'Claude on PATH did not create exact three-line import'); closing(p,'CLAUDE.md')
  # Presence is independent of the configured review agent on re-init too.
  cfg=Path('.shipcraft.toml'); cfg.write_text(cfg.read_text().replace('review = "claude"','review = "codex"'))
  f.unlink(missing_ok=True); again=init()
  want(f.is_file() and f.read_bytes()==IMPORT,'configured codex reviewer suppressed Claude import'); closing(again,'CLAUDE.md')
 elif case in ('claude-absent','agents-kept-absent'): want(not f.exists(),'absent Claude created CLAUDE.md'); want(SKIP not in output(p),'unhandled CLAUDE.md printed skipped notice')
 elif case=='claude-append': want(f.read_bytes()==before+b'\n\n'+IMPORT,'existing CLAUDE.md without claude on PATH not appended'); closing(p,'CLAUDE.md')
 elif agents_bad:
  
  if before is None: want(not f.exists(),'ineligible AGENTS created CLAUDE.md')
  else: kept(p,'CLAUDE.md',before)
  want(output(p).splitlines().count(SKIP)==1,'missing/duplicate AGENTS qualification notice')
  if case in ('agents-link','agents-link-present'): want(Path('AGENTS.md').is_symlink() and Path('agent-target61').read_bytes()==b'outside61\n','AGENTS link changed')
 elif case in ('claude-link','claude-dangling'):
  want(f.is_symlink(),'CLAUDE symlink replaced'); notice(p,'CLAUDE.md','kept')
  if case=='claude-link': want(Path('claude-target61').read_bytes()==b'outside61\n','CLAUDE symlink target changed')
  else: want(not Path('claude-target61').exists(),'dangling target created')
 else:
  kept(p,'CLAUDE.md',before,case in ('claude-edited','claude-crlf','claude-duplicate')); notice(p,'CLAUDE.md','could not write' if case in ('claude-invalid','claude-readonly') else 'already has the shipcraft block')
assert not errors,'\n'.join(errors)
PY61
  pass
}
