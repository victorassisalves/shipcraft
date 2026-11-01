# Item 75: public commands and public canonical lock schema; RED only.
item75_langs() { echo core; }
item75_cases() {
  local c
  for c in feature fix fix-time fix-release fix-both options-order options-order-boundary log-fails feature-log-fails refused-passing refused-build refused-check refused-open refused-config write-fails close-post close-check close-log-fails close-index-lock redo-feature redo-fix redo-unchanged redo-refused redo-log-fails legacy2-redo legacy3-redo legacy2-unchanged legacy3-unchanged future-hook future-ci future-status future-red read-status read-init; do echo "v1-75.$c"; done
  for c in leap leap-century minute seconds zero-negative offset-max day-end year-boundary; do echo "v1-75.time-$c"; done
  for c in leap-day century month-zero month-high day-zero day-high short-year short-month space lower-t lower-z no-zone no-offset-colon offset-hour offset-minute hour minute second leap-second fraction unicode leading trailing cr lf; do echo "v1-75.invalid-time-$c"; done
  for c in zero ordinary large; do echo "v1-75.tag-$c"; done
  for c in prefix missing-part extra-part leading-major leading-minor leading-patch negative prerelease build unicode space; do echo "v1-75.invalid-tag-$c"; done
  for c in repeated-fix repeated-time repeated-release no-fix-time no-fix-release redo-fix redo-time redo-release missing-time missing-release option-as-time option-as-release; do echo "v1-75.arguments-$c"; done
  for c in missing-kind missing-time missing-release kind-null kind-number kind-other time-number time-invalid release-number release-invalid feature-time feature-release extra-key seal-kind seal-time seal-release; do
    echo "v1-75.read-$c-hook"; echo "v1-75.read-$c-ci"
  done
  for c in 2 3; do
    for field in kind reported_at fixes_release; do echo "v1-75.legacy$c-$field-hook"; echo "v1-75.legacy$c-$field-ci"; done
  done
  for c in block-bare block-local append-bare append-local upgrade-bare-bare upgrade-bare-local upgrade-local-bare upgrade-local-local upgrade-brief-fails-bare upgrade-brief-fails-local write-fails-bare write-fails-local write-partial-bare write-partial-local edited-bare edited-local refused-bare refused-local; do echo "v1-75.block-$c"; done
}
item75_case() {
  case "$CASE" in v1-75.block-*) i75_block; return ;; esac
  EXPECT="item 75: ${CASE#v1-75.}"; v1_start codex
  must_accept 'item 75 fix metadata contract' cmd "$PY" - "${CASE#v1-75.}" "$(command -v shipcraft)" <<'PY75'
import hashlib,json,os,re,shlex,subprocess,sys
from pathlib import Path
mode,binary=sys.argv[1:]; binary=str(Path(binary).resolve())
root=Path('project75');root.mkdir();os.chdir(root)
def write(p,s):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
def run(*args,ok=True):
 p=subprocess.run(list(map(str,args)),input='',capture_output=True,text=True,timeout=90)
 print('$',shlex.join(list(map(str,args))),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 if ok:assert p.returncode==0,('command failed',p.returncode,p.stdout,p.stderr)
 return p
def git(*args):return run('git',*args).stdout.strip()
def commit(message,hooks=False):
 git('add','-A')
 if hooks:git('commit','-qm',message)
 else:git('-c','core.hooksPath=/dev/null','commit','-qm',message)
def locks():return sorted(Path('.shipcraft/locks').glob('*.json'))
def rows():
 p=Path('.git/shipcraft/runs.jsonl')
 return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def snapshot():
 return {str(p):p.read_bytes() for p in Path('.').rglob('*') if p.is_file() and '.git' not in p.parts and '__pycache__' not in p.parts and '.pytest_cache' not in p.parts}
def seal(d):
 c={k:d[k] for k in ('format','state','files','cases','failing_at_red')}
 c['files']=dict(sorted(c['files'].items()))
 if d['format']==4:c.update((k,d[k]) for k in ('kind','reported_at','fixes_release') if k in d)
 c['seal']=''
 return hashlib.sha256(json.dumps(c,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
def save(d):
 d['seal']=seal(d);lock.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
def fields(d,expected):
 assert all(k in d for k in ('kind','reported_at','fixes_release')),('missing fix fields',d)
 assert tuple(d[k] for k in ('kind','reported_at','fixes_release'))==expected,('metadata values',d,expected)
def valid_lock(d,expected):
 assert list(d)==['format','state','files','cases','failing_at_red','kind','reported_at','fixes_release','seal'],('format 4 fields/order',d)
 assert d['format']==4,('expected format 4',d)
 fields(d,expected);assert d['seal']==seal(d),('canonical format 4 seal',d)
 for f,h in d['files'].items():assert h=='sha256:'+hashlib.sha256(Path(f).read_bytes()).hexdigest(),(f,h)
def redrow(before,expected=None,code=None,redo=False):
 rs=rows();assert rs[:len(before)]==before and len(rs)==len(before)+1,('append exactly one row',rs,before)
 r=rs[-1];assert r['layer']=='red',r
 if redo:assert r.get('redo') is True and not any(k in r for k in ('kind','reported_at','fixes_release')),('redo row shape',r)
 else:fields(r,expected)
 if code is not None:assert (r['result'],r['code'])==('refused' if code else 'passed',code),r
 return r
def refusal(p,layer,code):
 assert p.returncode==1,('refusal exit',p.returncode)
 lines=(p.stdout+p.stderr).strip().splitlines()[-3:]
 assert len(lines)==3 and all(s.startswith(pre) for s,pre in zip(lines,('shipcraft refused:','Why:','Next:'))),lines
 assert [r for r in rows() if r['layer']==layer][-1]['code']==code,('wrong refusal',rows())
 return lines

git('init','-q','-b','main');git('config','user.name','RED 75');git('config','user.email','red75@example.invalid')
write('requirements.txt','pytest\n');run(binary,'init')
# Marker failures are outside the lock; the config does not change between judging runs.
write('.shipcraft.toml','shipcraft_min = "0.0"\nlang = "python"\nrunner = "pytest"\ntest_command = "pytest -q --junitxml={junit} tests"\ntest_globs = ["tests/**"]\ncheck = "touch checked75; test ! -f fail-check75"\n[build]\ncommand = "touch built75; test ! -f fail-build75"\n[execution]\nci = "local"\nreview = "off"\n')
write('.gitignore','__pycache__/\n.pytest_cache/\nbuilt75\nchecked75\nfail-build75\nfail-check75\n')
write('value75','red');commit('chore: base75');base=git('rev-parse','HEAD')
write('tests/test_value75.py','from pathlib import Path\ndef test_value75():\n    assert Path("value75").read_text() == "green"\n')
TIME='2026-10-31T00:36-03:00';TAG='v2.25.0';expected=('fix',TIME,TAG)
valid_times={'leap':'2024-02-29T23:59Z','leap-century':'2000-02-29T00:00:00+00:00','minute':'2026-10-31T00:36-03:00','seconds':'2026-10-31T00:36:09+03:00','zero-negative':'2026-01-01T00:00-00:00','offset-max':'2026-12-31T23:59:59+23:59','day-end':'2026-04-30T23:59:59-23:59','year-boundary':'0001-01-01T00:00Z'}
invalid_times={'leap-day':'2025-02-29T00:00Z','century':'1900-02-29T00:00Z','month-zero':'2026-00-01T00:00Z','month-high':'2026-13-01T00:00Z','day-zero':'2026-01-00T00:00Z','day-high':'2026-04-31T00:00Z','short-year':'026-01-01T00:00Z','short-month':'2026-1-01T00:00Z','space':'2026-01-01 00:00Z','lower-t':'2026-01-01t00:00Z','lower-z':'2026-01-01T00:00z','no-zone':'2026-01-01T00:00','no-offset-colon':'2026-01-01T00:00+0000','offset-hour':'2026-01-01T00:00+24:00','offset-minute':'2026-01-01T00:00-01:60','hour':'2026-01-01T24:00Z','minute':'2026-01-01T00:60Z','second':'2026-01-01T00:00:60Z','leap-second':'2016-12-31T23:59:60Z','fraction':'2026-01-01T00:00:00.1Z','unicode':'２０２６-01-01T00:00Z','leading':' 2026-01-01T00:00Z','trailing':'2026-01-01T00:00Z ','cr':'2026-01-01T00:00Z\r','lf':'2026-01-01T00:00Z\n'}
invalid_tags={'prefix':'2.25.0','missing-part':'v2.25','extra-part':'v2.25.0.1','leading-major':'v02.25.0','leading-minor':'v2.025.0','leading-patch':'v2.25.00','negative':'v-1.0.0','prerelease':'v2.25.0-rc1','build':'v2.25.0+build','unicode':'v２.25.0','space':'v2.25.0 '}
args=['--fix','--reported-at',TIME,'--fixes-release',TAG]
invalid=mode.startswith(('invalid-','arguments-'))
if mode.startswith('time-'):
 t=valid_times[mode[5:]];args=['--reported-at',t,'--fix'];expected=('fix',t,None)
if mode.startswith('tag-'):
 t={'zero':'v0.0.0','ordinary':TAG,'large':'v123456789012345678901234567890.98765432109876543210.1234567890'}[mode[4:]]
 args=['--fixes-release',t,'--fix'];expected=('fix',None,t)
if mode.startswith('invalid-time-'):args=['--fix','--reported-at',invalid_times[mode[13:]]]
if mode.startswith('invalid-tag-'):args=['--fix','--fixes-release',invalid_tags[mode[12:]]]
if mode.startswith('arguments-'):
 args={'repeated-fix':['--fix','--fix'],'repeated-time':['--fix','--reported-at',TIME,'--reported-at',TIME],'repeated-release':['--fix','--fixes-release',TAG,'--fixes-release',TAG],'no-fix-time':['--reported-at',TIME],'no-fix-release':['--fixes-release',TAG],'redo-fix':['--redo','--fix'],'redo-time':['--fix','--reported-at',TIME,'--redo'],'redo-release':['--redo','--fixes-release',TAG,'--fix'],'missing-time':['--fix','--reported-at'],'missing-release':['--fix','--fixes-release'],'option-as-time':['--fix','--reported-at','--all'],'option-as-release':['--fix','--fixes-release','--all']}[mode[10:]]
if invalid:
 # Invalid arguments must win even over invalid config and an existing log.
 write('.shipcraft.toml','invalid TOML [\n');before=rows();files=snapshot()
 p=run(binary,'red',*args,ok=False)
 assert p.returncode==2 and 'shipcraft: error: invalid arguments:' in p.stderr and 'usage:' in p.stderr,(p.stdout,p.stderr)
 assert rows()==before and snapshot()==files,'invalid arguments wrote a file/row'
 assert not Path('built75').exists() and not Path('checked75').exists(),'invalid arguments ran a command'
 sys.exit()

reader=mode.startswith(('read-','legacy2-','legacy3-','future-','close-','redo-'))
if reader:
 # Seed from today's public RED, then build only the documented wire format.
 run(binary,'red');lock=locks()[0];d=json.loads(lock.read_text())
 d.update(format=4,kind='fix',reported_at=TIME,fixes_release=TAG)
 if mode.startswith('read-seal-kind-'):d.update(kind='feature',reported_at=None,fixes_release=None)
 if mode in ('redo-feature',):d.update(kind='feature',reported_at=None,fixes_release=None);expected=('feature',None,None)
 legacy=mode.startswith(('legacy2-','legacy3-'))
 if legacy:
  d['format']=int(mode[6]);[d.pop(k) for k in ('kind','reported_at','fixes_release')]
  if d['format']==2:d['files']={k:v.removeprefix('sha256:') for k,v in d['files'].items()}
 save(d)
 if mode.startswith('future-'):d['format']=5;save(d)
 if mode.startswith('read-') and mode not in ('read-status','read-init'):
  defect=mode[5:].rsplit('-',1)[0]
  mutations={'kind-null':('kind',None),'kind-number':('kind',7),'kind-other':('kind','bug'),'time-number':('reported_at',7),'time-invalid':('reported_at','1900-02-29T00:00Z'),'release-number':('fixes_release',7),'release-invalid':('fixes_release','v02.0.0'),'extra-key':('extra',None)}
  if defect.startswith('missing-'):d.pop({'kind':'kind','time':'reported_at','release':'fixes_release'}[defect[8:]])
  elif defect.startswith('feature-'):
   d['kind']='feature'
   if defect=='feature-time':d['fixes_release']=None
   else:d['reported_at']=None
  elif defect.startswith('seal-'):
   d[{'kind':'kind','time':'reported_at','release':'fixes_release'}[defect[5:]]]={'kind':'fix','time':'2024-02-29T00:00Z','release':'v0.0.1'}[defect[5:]]
  else:k,v=mutations[defect];d[k]=v
  if defect.startswith('seal-'):lock.write_text(json.dumps(d)+'\n')
  else:save(d)
 if legacy and not mode.endswith(('redo','unchanged')):
  field=mode.split('-',2)[1];d[field]=None;save(d)
 commit('test: documented lock fixture75');original=lock.read_bytes();before=rows()
 if mode.startswith('future-'):
  command=mode[7:]
  if command=='hook':write('product75','changed');git('add','product75');p=run(binary,'check',ok=False);lines=refusal(p,'hook','lock-format')
  elif command=='ci':write('product75','changed');commit('feat: later product');p=run(binary,'ci','--base',git('rev-parse','HEAD~1'),ok=False);lines=refusal(p,'ci','lock-format')
  else:
   if command=='init':write('lefthook.yml','pre-commit:\n  commands:\n    shipcraft:\n      run: shipcraft check\n      priority: 9\ncommit-msg:\n  commands:\n    shipcraft:\n      run: shipcraft check --commit-msg {1}\npost-commit:\n  commands:\n    shipcraft:\n      run: shipcraft close\n')
   p=run(binary,command,ok=False);lines=(p.stdout+p.stderr).strip().splitlines()[-3:];assert p.returncode==1,(p.returncode,lines)
  assert lines==[f'shipcraft refused: lock {lock} needs a newer shipcraft (format 5; this one knows formats 2 to 4)','Why: a lock written by a newer shipcraft cannot be judged by an older one','Next: upgrade shipcraft to the version the project pins (package.json, or shipcraft_min), then run the command again'],lines
  assert lock.read_bytes()==original
 elif (mode.startswith('read-') and mode not in ('read-status','read-init')) or (legacy and not mode.endswith(('redo','unchanged'))):
  layer=mode.rsplit('-',1)[1]
  write('product75','changed');git('add','product75')
  if layer=='hook':p=run(binary,'check',ok=False)
  else:
   start=git('rev-parse','HEAD');commit('feat: later product');p=run(binary,'ci','--base',start,ok=False)
  refusal(p,layer,'lock-edited');assert lock.read_bytes()==original
 elif mode=='read-status':
  Path('built75').unlink();Path('checked75').unlink();files=snapshot()
  p=run(binary,'status');assert 'roles:' in p.stdout and lock.stem in p.stdout and 'open' in p.stdout,p.stdout
  assert lock.read_bytes()==original and rows()==before and snapshot()==files
  assert not Path('built75').exists() and not Path('checked75').exists(),'status ran project commands'
 elif mode=='read-init':
  # Duplicate integration asks to close HEAD's readable format 4 lock first.
  write('lefthook.yml','pre-commit:\n  commands:\n    shipcraft:\n      run: shipcraft check\n      priority: 9\ncommit-msg:\n  commands:\n    shipcraft:\n      run: shipcraft check --commit-msg {1}\npost-commit:\n  commands:\n    shipcraft:\n      run: shipcraft close\n')
  p=run(binary,'init',ok=False);assert p.returncode==1 and 'close' in p.stdout+p.stderr and 'open lock' in p.stdout+p.stderr,(p.stdout,p.stderr)
  assert rows()==before and lock.read_bytes()==original
 elif mode.startswith(('redo-','legacy')):
  if mode=='redo-refused':write('fail-build75','fail')
  elif not mode.endswith('unchanged'):
   with Path('tests/test_value75.py').open('a') as f:f.write('\n# repaired fixture description75\n')
  if mode=='redo-log-fails':Path('.git/shipcraft/runs.jsonl').unlink();Path('.git/shipcraft/runs.jsonl').mkdir()
  p=run(binary,'red','--redo',ok=False)
  if mode=='redo-refused':
   refusal(p,'red','build-failed');assert lock.read_bytes()==original
  else:
   assert p.returncode==0,('redo refused valid lock',p.stdout,p.stderr)
   new=json.loads(lock.read_text());assert locks()==[lock]
   if legacy:assert new['format']==3 and not any(k in new for k in ('kind','reported_at','fixes_release')),new
   else:fields(new,expected);assert new['format']==4,new
   assert new['seal']==seal(new),new
   if mode=='redo-unchanged':assert lock.read_bytes()==original,'unchanged redo replaced metadata'
  if mode!='redo-log-fails':redrow(before,redo=True,code='build-failed' if mode=='redo-refused' else '')
 else:
  write('value75','green');git('add','-A')
  if mode=='close-log-fails':Path('.git/shipcraft/runs.jsonl').unlink();Path('.git/shipcraft/runs.jsonl').mkdir()
  if mode=='close-check':run(binary,'check')
  elif mode=='close-index-lock':
   run(binary,'check','--commit-msg','message75');commit('feat: green75')
   write('.git/index.lock','occupied75')
   p=run(binary,'close');assert lock.read_bytes()==original and 'shipcraft close' in p.stdout+p.stderr
   Path('.git/index.lock').unlink();run(binary,'close')
  else:commit('feat: green75',hooks=True)
  new=json.loads(lock.read_text());assert new['state']=='closed',new
  assert {k:v for k,v in new.items() if k not in ('state','seal')}=={k:v for k,v in d.items() if k not in ('state','seal')},new
  assert new['seal']==seal(new),new
 sys.exit()

if mode in ('feature','feature-log-fails'):args=[];expected=('feature',None,None)
if mode=='fix':args=['--fix'];expected=('fix',None,None)
if mode=='fix-time':args=['--fix','--reported-at',TIME];expected=('fix',TIME,None)
if mode=='fix-release':args=['--fix','--fixes-release',TAG];expected=('fix',None,TAG)
if mode=='options-order':args=['--reported-at',TIME,'--base',base,'--fixes-release',TAG,'--all','--fix']
if mode=='options-order-boundary':args=['--all','--fixes-release',TAG,'--fix','--base',base,'--reported-at',TIME]
code=''
if mode=='refused-passing':write('value75','green');code='red-already-passes'
if mode=='refused-build':write('fail-build75','fail');code='build-failed'
if mode=='refused-check':write('fail-check75','fail');code='no-report'
if mode=='refused-config':
 write('.shipcraft.toml','invalid [\n');baseline_before=rows();baseline=run(binary,'red',ok=False);baseline_rows=len(rows())-len(baseline_before)
if mode=='refused-open':
 run(binary,'red');commit('test: first open lock');code='lock-open'
if mode=='write-fails':
 Path('.shipcraft/locks').chmod(0o555)
if mode in ('log-fails','feature-log-fails'):
 log=Path('.git/shipcraft/runs.jsonl');log.unlink(missing_ok=True);log.mkdir(parents=True)
before=rows();oldlocks={str(p):p.read_bytes() for p in locks()}
try:p=run(binary,'red',*args,ok=False)
finally:
 if mode=='write-fails':Path('.shipcraft/locks').chmod(0o755)
if mode=='refused-config':
 assert p.returncode==baseline.returncode and 'invalid arguments' not in p.stderr,(p.stdout,p.stderr)
 assert len(rows())-len(before)==baseline_rows,'changed invalid-config logging'
 for r in rows()[len(before):]:
  if r.get('result') in ('passed','refused'):fields(r,expected)
 assert not locks()
elif mode=='write-fails':
 assert p.returncode==2 and 'shipcraft: error: write ' in p.stderr,(p.stdout,p.stderr)
 rs=rows();assert rs[:len(before)]==before and len(rs)==len(before)+1
 assert rs[-1]['result']=='error' and rs[-1]['code']=='error',rs[-1]
 assert not locks()
elif code:
 refusal(p,'red',code);redrow(before,expected,code=code)
 assert {str(p):p.read_bytes() for p in locks()}==oldlocks
else:
 assert p.returncode==0,('valid fix options rejected',p.stdout,p.stderr)
 assert len(locks())==1,locks();lock=locks()[0];valid_lock(json.loads(lock.read_text()),expected)
 if mode not in ('log-fails','feature-log-fails'):redrow(before,expected,code='')
 assert p.stdout.splitlines()[-1].startswith('shipcraft: next: the GREEN'),('GREEN guidance must remain last',p.stdout)
PY75
  pass
}

i75_block() {
  EXPECT="item 75: ${CASE#v1-75.block-}"
  v1_start codex claude
  must_accept 'item 75 fallback and migration contract' cmd "$PY" - "${CASE#v1-75.block-}" "$(command -v shipcraft)" "$ACEITE" "$CW" <<'PY74'
import ast,json,os,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,acceptance,cw=sys.argv[1:];binary=str(Path(binary).resolve())
# Exact AGENTS_BLOCK at f4220f1 (version 2.30.0); only it and variant were read.
HISTORICAL_BARE=b"<!-- shipcraft -->\n## shipcraft: TDD with a lock (required in this repository)\n- Cycle: RED (a failing test) \xe2\x86\x92 `shipcraft red` \xe2\x86\x92 GREEN (code) \xe2\x86\x92 `git commit`. The git hook checks every commit.\n- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.\n- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.\n- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.\n- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).\n- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.\n- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.\n- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.\n- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.\n- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.\n- If you run in a sandbox (for example Codex's `workspace-write`), run `shipcraft red`, `shipcraft red --redo` and `git commit` (its hook runs the locked tests) outside it when you can: inside, they can take many times longer, or fail when git cannot write its index. If you cannot, finish your files and stop (your files: those you added, changed or deleted, both sides of a rename), and give the user the steps to run in a POSIX shell where this project's tests run, each argument you fill in written in single quotes as above: first `cd` to this checkout's absolute path; for a RED, then `shipcraft red` (for a repair, `shipcraft red --redo`), which prints the lock's path; then `git --literal-pathspecs add -f --` with each of your files as its own argument and, for a RED, that lock path; then `git commit -m` with the message. A GREEN gets only the `cd`, `git add` and `git commit` steps. Tell the user to start from the first step that has not succeeded yet, and to stop and tell you if a step fails. If one of your files already had other changes before your phase, or `git diff --cached --name-only -z` lists a staged path that is not one of yours (or fails), say so and name those paths instead of handing the steps over. Change nothing after handing them over. Your phase ends there: you start no other phase, and a commit alone does not mean the lock closed (`shipcraft status` says).\n- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.\n- When in doubt, run `shipcraft status`.\n<!-- /shipcraft -->\n"
# Load only existing acceptance expected-text fixtures, not their test execution.
source=(Path(acceptance)/'lib/item61.sh').read_text().split("<<'PY61'\n",1)[1].split('\nPY61',1)[0]
names={'OLD','PREVIOUS_BARE','ROOT_LINE','PREVIOUS_LOCAL','head','rest','READ_TESTS','REPAIR','ROLES','FALLBACK','SANDBOX','FIX_DATA'}
ns={}
for node in ast.parse(source).body:
 if isinstance(node,ast.Assign):
  targets={n.id for t in node.targets for n in ast.walk(t) if isinstance(n,ast.Name)}
  if targets and targets<=names:exec(compile(ast.Module(body=[node],type_ignores=[]),'item61-fixtures','exec'),ns)
 elif isinstance(node,ast.FunctionDef) and node.name=='expected_block':exec(compile(ast.Module(body=[node],type_ignores=[]),'item61-fixtures','exec'),ns)
def variant(block,local):
 if not local:return block
 text=block.replace(b'`shipcraft ',b'`npx -- shipcraft ')
 head,rest=text.split(b'\n- ',1)
 return head+b'\n'+ns['ROOT_LINE']+b'- '+rest
# Brief bodies sampled by item70 through public v2.25.0 init in both install variants; stamp is dynamic.
HISTORICAL_BRIEF_BODIES={False: {'red.md': b'# shipcraft: the RED phase\n\nYou are the RED session: you write the failing tests for a change, not the change.\n\n- Write the failing tests from the intent, never from an implementation.\n- Write two cases per rule: the ordinary one, and a boundary a rushed GREEN would get wrong.\n- First read the existing tests that cover the behavior the change touches, and never contradict them unless the intent says that behavior changes.\n- Each test written for the new behavior must fail for the right reason before you run `shipcraft red`. Passing control tests are fine: they are locked as controls.\n- Fake external tools with their real output.\n- Commit the tests, their stubs and the lock in one commit, and stop.\n- List ambiguities instead of picking a reading silently.\n\n', 'green.md': b"# shipcraft: the GREEN phase\n\nYou are the GREEN session: you make the locked tests pass.\n\n- Start from the RED commit.\n- Never edit a locked file or a lock (`.shipcraft/locks/*`).\n- Change product code, dependencies or config until the locked tests pass.\n- Running the other tests the change touches is a check, not a gate: report a failure outside the locked tests, and let the hook's verdict decide the commit, since CI runs the rest.\n- If a test looks wrong, stop and report the test with the reason, instead of working around it.\n- Commit.\n\n"}, True: {'red.md': b'# shipcraft: the RED phase\n\nYou are the RED session: you write the failing tests for a change, not the change.\n\n- Write the failing tests from the intent, never from an implementation.\n- Write two cases per rule: the ordinary one, and a boundary a rushed GREEN would get wrong.\n- First read the existing tests that cover the behavior the change touches, and never contradict them unless the intent says that behavior changes.\n- Each test written for the new behavior must fail for the right reason before you run `npx -- shipcraft red`. Passing control tests are fine: they are locked as controls.\n- Fake external tools with their real output.\n- Commit the tests, their stubs and the lock in one commit, and stop.\n- List ambiguities instead of picking a reading silently.\n\n', 'green.md': b"# shipcraft: the GREEN phase\n\nYou are the GREEN session: you make the locked tests pass.\n\n- Start from the RED commit.\n- Never edit a locked file or a lock (`.shipcraft/locks/*`).\n- Change product code, dependencies or config until the locked tests pass.\n- Running the other tests the change touches is a check, not a gate: report a failure outside the locked tests, and let the hook's verdict decide the commit, since CI runs the rest.\n- If a test looks wrong, stop and report the test with the reason, instead of working around it.\n- Commit.\n\n"}}
BRIEF_BODIES={local: {name: body.replace(b"- Running the other tests the change touches is a check, not a gate: report a failure outside the locked tests, and let the hook's verdict decide the commit, since CI runs the rest.\n",b"- Run the locked tests and the other tests the change affects, not the full suite unless the change affects all of it: CI runs it once (where CI is off, once before the PR). Report a failure outside the locked tests; it is not a gate: the hook's verdict decides the commit.\n") if name=='green.md' else body for name,body in bodies.items()} for local,bodies in HISTORICAL_BRIEF_BODIES.items()}
IMPORT=b'<!-- shipcraft -->\nShipcraft workflow (required): @AGENTS.md\n<!-- /shipcraft -->\n'
PREFIX=b'# House rules74\r\n\x00\n';SUFFIX=b'\nAfter70\r\nno final newline'
def write(path,data,mode=None):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
 if mode is not None:p.chmod(mode)
def text(p):return (p.stdout+p.stderr).decode(errors='replace')
def run(*args,ok=True,preexec_fn=None):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,timeout=90,preexec_fn=preexec_fn)
 print('$',repr(args),'[rc='+str(p.returncode)+']\n'+text(p),flush=True)
 if ok:assert p.returncode==0,('command failed before assertion',p.returncode,text(p))
 return p
def snapshot(path):
 p=Path(path)
 if p.is_symlink():return ('link',os.readlink(p))
 if p.is_dir():return ('dir',stat.S_IMODE(p.stat().st_mode),{x.name:snapshot(x) for x in p.iterdir()})
 return ('file',stat.S_IMODE(p.stat().st_mode),p.read_bytes())
root=Path(cw)/"project74 space 'quote";root.mkdir();os.chdir(root)
run('git','init','-q',str(root));write('requirements.txt','pytest\n')
local=case.endswith('-local');call=binary
if local:
 target=root/'node_modules/shipcraft-fixture/bin/shipcraft';target.parent.mkdir(parents=True);shutil.copy2(binary,target)
 call=root/'node_modules/.bin/shipcraft';call.parent.mkdir(parents=True);call.symlink_to(target)
def init(**kw):return run(call,'init',**kw)
def exact_block(actual):
 expected=ns['expected_block'](local)
 assert actual==expected,'missing exact item 75 fix-data line or changed other block bytes/order'
 sandbox=ns['SANDBOX'].replace(b'`shipcraft ',b'`npx -- shipcraft ') if local else ns['SANDBOX']
 fallback=ns['FALLBACK'].replace(b'`shipcraft ',b'`npx -- shipcraft ') if local else ns['FALLBACK']
 assert actual.count(sandbox)==1 and fallback+sandbox in actual,'sandbox line must occur once immediately after fallback, with LF'
 assert actual.replace(ns['FIX_DATA'].replace(b'`shipcraft ',b'`npx -- shipcraft ') if local else ns['FIX_DATA'],b'',1).replace(b"- Pick the lane first: a mechanical change, one that changes no behavior (text, config, data, content, a rename, docs), is committed directly once the tests it affects pass in one run, with no RED or GREEN; a behavior change takes the cycle.\n- A change that needs more than about 40 new test cases is split before its RED.\n- A review of the RED's tests before the lock takes at most one round and fixes contract bugs only (a test that asserts the wrong behavior).\n- Locally, the GREEN runs only the tests the change affects; the full suite runs once, in CI (where CI is off, once before the PR).\n- In PR review, only Blocking findings open another round; the others go to notes.\n- Small fixes from one request go in one PR.\n",b'',1)==variant(HISTORICAL_BARE,local),'fixture must add exactly one line to f4220f1'
def closing(p,agents=True,briefs=True):
 lines=text(p).splitlines();ready=[l for l in lines if l.startswith('shipcraft: ready. Commit ')]
 assert len(ready)==1 and lines[-3]==ready[0],'changed closing order'
 assert ('AGENTS.md' in ready[0])==agents,('closing AGENTS inclusion',ready)
 for name in ('red.md','green.md'):assert ('.shipcraft/briefs/'+name in ready[0])==briefs,('closing brief inclusion',ready)
 assert 'test' in lines[-2] and 'then' in lines[-2]
 assert lines[-1]=='CI runs on this machine through shipcraft pr. To run it on GitHub, see shipcraft docs/github-ci.md.'
def core():
 assert Path('.shipcraft.toml').is_file() and Path('.shipcraft/locks/.gitkeep').read_bytes()==b''
 for event in ('commit-msg','post-commit'):assert os.access('.git/hooks/'+event,os.X_OK)
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'init/status wrote a run-log row'
if case.startswith(('block-','append-')):
 prefix=b'House rules74\r\nwithout final newline' if case.startswith('append-') else b''
 if prefix:write('AGENTS.md',prefix,0o751)
 p=init();actual=Path('AGENTS.md').read_bytes()
 if prefix:
  assert actual.startswith(prefix+b'\n\n'),'append changed prefix or blank-line separator'
  actual=actual[len(prefix)+2:]
  assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'append changed mode'
 exact_block(actual);core();closing(p)
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'CLAUDE import changed'
elif case.startswith('refused-'):
 old=PREFIX+variant(HISTORICAL_BARE,local)+SUFFIX;write('AGENTS.md',old,0o751)
 write('.shipcraft','blocked70\r\n');write('CLAUDE.md',b'custom claude70\r\n')
 before={str(x):snapshot(x) for x in root.iterdir() if x.name!='.git'}
 p=init(ok=False);assert p.returncode==2 and '.shipcraft' in text(p),'did not reach later core failure'
 assert before=={str(x):snapshot(x) for x in root.iterdir() if x.name!='.git'},'refused init changed onboarding/briefs'
 assert 'ready. Commit' not in text(p)
else:
 # Seed current core/briefs through public init, so later failures isolate the upgrade.
 init()
 try:import tomllib
 except ImportError:import tomli as tomllib
 version=tomllib.loads((Path(acceptance).parent/'nucleo/Cargo.toml').read_text())['package']['version']
 for name,body in BRIEF_BODIES[local].items():
  assert Path('.shipcraft/briefs',name).read_bytes()==body+('<!-- written by shipcraft '+version+' -->\n').encode(),'item 75 changed brief body or running-version stamp'
 briefs=snapshot('.shipcraft/briefs')
 oldlocal=case.startswith('upgrade-local-') or (local and not case.startswith('upgrade-bare-'))
 old=PREFIX+variant(HISTORICAL_BARE,oldlocal)+SUFFIX
 if case.startswith('edited-'):
  old=old.replace(b'TDD',b'EDITED70',1)
  # A version change must preserve the previous release's unedited briefs with its notice.
  for name,body in HISTORICAL_BRIEF_BODIES[local].items():write(Path('.shipcraft/briefs')/name,body+b'<!-- written by shipcraft 2.25.0 -->\n',0o444)
  briefs=snapshot('.shipcraft/briefs')
 write('AGENTS.md',old,0o751);write('CLAUDE.md',IMPORT)
 if case.startswith('upgrade-brief-fails-'):
  shutil.rmtree('.shipcraft/briefs');write('.shipcraft/briefs',b'blocked briefs70\r\n')
 elif case.startswith('write-fails-'):Path('AGENTS.md').chmod(0o444)
 preexec=None
 if case.startswith('write-partial-'):
  import resource,signal
  limit=len(old)+8
  assert limit<len(PREFIX+ns['expected_block'](local)+SUFFIX),'size fixture does not discriminate new write'
  def preexec():
   signal.signal(signal.SIGXFSZ,signal.SIG_IGN);resource.setrlimit(resource.RLIMIT_FSIZE,(limit,limit))
 try:p=init(preexec_fn=preexec)
 finally:
  if case.startswith('write-fails-'):
   kept_mode=stat.S_IMODE(Path('AGENTS.md').stat().st_mode);Path('AGENTS.md').chmod(0o751)
   assert kept_mode==0o444,'read-only AGENTS mode changed'
 core();assert Path('CLAUDE.md').read_bytes()==IMPORT,'upgrade/failure modified CLAUDE import'
 if case.startswith(('edited-','write-fails-','write-partial-')):
  assert Path('AGENTS.md').read_bytes()==old,'kept/failed upgrade damaged old block'
  assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'kept block mode changed'
  if case.startswith('edited-'):
   assert "; it differs from this version's: edit it by hand to match docs/spec.md" in text(p),'edited block not reported'
   for name in BRIEF_BODIES[local]:
    notice="shipcraft: .shipcraft/briefs/"+name+" differs from this version's, kept: compare it with docs/spec.md"
    assert (notice in text(p))==(version!='2.25.0'),'old brief version comparison/notice changed'
  else:assert 'AGENTS.md' in text(p) and 'could not write' in text(p),'missing AGENTS write failure notice'
  assert "shipcraft: CLAUDE.md not written: AGENTS.md does not hold this version's shipcraft block" in text(p),'ineligible import guard missing'
  assert sorted(x.name for x in root.iterdir())==sorted(['.git','.shipcraft','.shipcraft.toml','AGENTS.md','CLAUDE.md','requirements.txt']+(['node_modules'] if local else [])),'temporary rewrite file leaked'
  closing(p,agents=False,briefs=False)
 else:
  actual=Path('AGENTS.md').read_bytes()
  assert actual==PREFIX+ns['expected_block'](local)+SUFFIX,'f4220f1 known block not upgraded with exact surrounding bytes'
  exact_block(actual[len(PREFIX):-len(SUFFIX)])
  assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'upgrade changed mode'
  closing(p,briefs=False)
 if case.startswith('upgrade-brief-fails-'):
  assert Path('.shipcraft/briefs').read_bytes()==b'blocked briefs70\r\n','later brief failure changed blocker'
  assert any(l.startswith('shipcraft: .shipcraft/briefs not written: ') for l in text(p).splitlines()),'missing later folder failure notice'
 else:assert snapshot('.shipcraft/briefs')==briefs,'block upgrade changed brief bodies/stamps/modes'
PY74
  pass
}
