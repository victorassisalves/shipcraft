# Item 100: real pytest reports and local bare origins, no network services.
item100_langs() { echo core; }
item100_cases() {
  local c
  for c in fixture-control main review-only defaults both-off feature detached no-origin other-default fallback-main unreadable-head main-not-default redo redo-unchanged log-fails refused write-fails redo-write-fails detached-pr named-pr; do echo "v1-100.$c"; done
}
item100_case() {
  EXPECT="item 100: ${CASE#v1-100.}"; v1_start
  must_accept 'default-branch warning contract' cmd "$PY" - "${CASE#v1-100.}" "$(command -v shipcraft)" <<'PY100'
import hashlib,json,os,shlex,subprocess,sys
from pathlib import Path
mode,binary=sys.argv[1:];binary=str(Path(binary).resolve())
parent=Path.cwd();root=parent/'project100';root.mkdir();os.chdir(root)
def write(path,text):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
def run(*args,ok=True):
 p=subprocess.run(list(map(str,args)),capture_output=True,text=True,timeout=90)
 print('$',shlex.join(list(map(str,args))),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 if ok:assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr)
 return p
def git(*args):return run('git',*args).stdout.strip()
def commit(message):git('add','-A');git('commit','-qm',message)
def locks():return sorted(Path('.shipcraft/locks').glob('*.json'))
def rows():
 p=Path('.git/shipcraft/runs.jsonl')
 return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []

git('init','-q','-b','main');git('config','user.name','RED100');git('config','user.email','red100@example.invalid')
write('.gitignore','__pycache__/\n.pytest_cache/\n')
write('requirements.txt','pytest\n')
execution='[execution]\nci = "local"\nreview = "off"\n'
branch='main'
if mode=='review-only':execution='[execution]\nci = "off"\nreview = "local"\n'
elif mode=='defaults':execution=''
elif mode=='both-off':execution='[execution]\nci = "off"\nreview = "off"\n'
config='shipcraft_min = "0.0"\nlang = "python"\nrunner = "pytest"\n'+execution
config+='[build]\ncommand = '+json.dumps("printf 'build100-ok\\n'")+'\n'
config+='[[suite]]\nroot = "."\ncommand = "pytest -q --junitxml={junit} tests"\nglobs = ["tests/**"]\n'
write('.shipcraft.toml',config)
write('tests/test_old100.py','def test_old100():\n    assert True\n')
commit('chore: base100');run(binary,'init','--lang','python');commit('chore: installation100')
origin=parent/'origin100.git';run('git','init','-q','--bare',origin)
run('git','--git-dir='+str(origin),'symbolic-ref','HEAD','refs/heads/main')
git('remote','add','origin',str(origin));git('push','-q','origin','main');git('fetch','-q','origin');git('remote','set-head','origin','main')
# The two PR cases exercise the real fetch of this bare origin and stop before gh.
if mode in ('detached-pr','named-pr'):
 before_pr=rows()
 named=run(binary,'pr',ok=False)
 assert named.returncode==1,(named.stdout,named.stderr)
 named_lines=(named.stdout+named.stderr).strip().splitlines()[-3:]
 assert named_lines[0]=='shipcraft refused: shipcraft pr needs a working branch, and HEAD is at main',named_lines
 assert named_lines[1:]==['Why: a PR brings a branch into main; main cannot open a PR into itself','Next: create a branch (git switch -c <name>) and run shipcraft pr on it'],named_lines
 assert rows()==before_pr,('early branch refusal changed run log',rows())
 if mode=='detached-pr':
  git('checkout','--detach','-q')
  detached=run(binary,'pr',ok=False)
  assert detached.returncode==1,(detached.stdout,detached.stderr)
  detached_lines=(detached.stdout+detached.stderr).strip().splitlines()[-3:]
  assert detached_lines[1:]==named_lines[1:],(detached_lines,named_lines)
  assert rows()==before_pr,('early branch refusal changed run log',rows())
  assert detached_lines[0]=='shipcraft refused: shipcraft pr needs a working branch, and HEAD is detached (no branch)',detached_lines
 assert not locks(),locks()
 sys.exit()
if mode in ('fixture-control','feature'):
 git('checkout','-qb','item/feature100');branch='item/feature100'
 assert git('symbolic-ref','--short','HEAD')=='item/feature100'
elif mode=='detached':
 git('checkout','--detach','-q');branch=''
 assert run('git','symbolic-ref','-q','--short','HEAD',ok=False).returncode!=0
elif mode=='no-origin':
 git('remote','remove','origin')
 assert run('git','remote','get-url','origin',ok=False).returncode!=0
elif mode=='other-default':
 git('branch','-m','release/100');branch='release/100'
 git('push','-q','origin','release/100');git('fetch','-q','origin');git('remote','set-head','origin','release/100')
 assert git('symbolic-ref','--short','refs/remotes/origin/HEAD')=='origin/release/100'
elif mode=='fallback-main':
 git('symbolic-ref','--delete','refs/remotes/origin/HEAD')
 assert run('git','symbolic-ref','-q','refs/remotes/origin/HEAD',ok=False).returncode!=0
elif mode=='unreadable-head':
 # A dangling symbolic target is still readable by symbolic-ref; use a non-symbolic ref.
 git('symbolic-ref','--delete','refs/remotes/origin/HEAD');git('update-ref','refs/remotes/origin/HEAD','HEAD')
 assert run('git','symbolic-ref','-q','refs/remotes/origin/HEAD',ok=False).returncode!=0
elif mode=='main-not-default':
 git('push','-q','origin','main:release/100');git('fetch','-q','origin');git('remote','set-head','origin','release/100')
 assert git('symbolic-ref','--short','HEAD')=='main'
 assert git('symbolic-ref','--short','refs/remotes/origin/HEAD')=='origin/release/100'
write('tests/test_pair100.py','def test_target100():\n    assert False\ndef test_control100():\n    assert True\n')
if mode=='refused':write('tests/test_pair100.py','def test_target100():\n    assert True\ndef test_control100():\n    assert True\n')
if mode=='log-fails':
 log=Path('.git/shipcraft/runs.jsonl');log.unlink(missing_ok=True);log.mkdir()
if mode=='write-fails':Path('.shipcraft/locks').chmod(0o555)
before_red=rows()
try:p=run(binary,'red',ok=False)
finally:
 if mode=='write-fails':Path('.shipcraft/locks').chmod(0o755)
if mode in ('refused','write-fails'):
 assert not locks(),locks()
 assert 'shipcraft: warning: this lock is on ' not in p.stdout+p.stderr,(p.stdout,p.stderr)
 if mode=='refused':
  assert p.returncode==1 and rows()[-1]['code']=='red-already-passes',(p,rows())
  refusal=(p.stdout+p.stderr).strip().splitlines()[-3:]
  assert len(refusal)==3 and all(line.startswith(prefix) for line,prefix in zip(refusal,('shipcraft refused:','Why:','Next:'))),refusal
 elif mode=='write-fails':
  assert p.returncode==2 and rows()[-1]['result']=='error',(p,rows())
 sys.exit()
assert p.returncode==0,(p.stdout,p.stderr)
assert len(locks())==1,locks()
lock=locks()[0];d=json.loads(lock.read_text())
assert d['cases']==['tests.test_pair100::test_control100','tests.test_pair100::test_target100'],d
assert d['failing_at_red']==['tests.test_pair100::test_target100'],d
assert d['controls']==['tests.test_pair100::test_control100'],d
for path,digest in d['files'].items():assert digest=='sha256:'+hashlib.sha256(Path(path).read_bytes()).hexdigest(),path
assert d['format']==5 and d['state']=='open' and d['kind']=='feature' and d['reported_at'] is None and d['fixes_release'] is None,d
canonical={k:d[k] for k in ('format','state','files','cases','failing_at_red','controls','kind','reported_at','fixes_release')}
assert list(d)==list(canonical)+['seal'],d
canonical['files']=dict(sorted(canonical['files'].items()));canonical['seal']=''
assert d['seal']==hashlib.sha256(json.dumps(canonical,ensure_ascii=False,separators=(',',':')).encode()).hexdigest(),d
if mode!='log-fails':
 assert rows()[:-1]==before_red and len(rows())==len(before_red)+1,rows()
 r=rows()[-1]
 assert set(r)=={'at','branch','code','commit','fallback','layer','lock','result','secs','selected_files','selection','rerun_dropped','kind','reported_at','fixes_release'},r
 assert r['layer']=='red' and r['result']=='passed' and r['code']=='' and r['branch']==branch,r
 assert (r['selection'],r['selected_files'],r['fallback'],r['rerun_dropped'])==('changed',1,None,0),r
lines=p.stdout.splitlines();controls='shipcraft: controls: 1 passing case(s) of the changed test files; the hook runs them too'
announcement=next(i for i,s in enumerate(lines) if s.startswith('shipcraft: RED locked at'))
assert lines[announcement-1]==controls,lines
assert lines[-1]=='shipcraft: next: the GREEN, in a new session ([roles] green not set)',lines
assert 'build100-ok' in p.stdout+p.stderr,(p.stdout,p.stderr)
# Redo cases do not demand the new warning from their setup RED.
if mode in ('redo','redo-unchanged','redo-write-fails'):
 commit('test: opening RED100');before=lock.read_bytes();stat=lock.stat()
 if mode in ('redo','redo-write-fails'):
  with Path('tests/test_pair100.py').open('a') as f:f.write('\n# clarified assertion description100\n')
 if mode=='redo-write-fails':lock.parent.chmod(0o555)
 try:p=run(binary,'red','--redo',ok=False)
 finally:
  if mode=='redo-write-fails':lock.parent.chmod(0o755)
 lines=p.stdout.splitlines()
 if mode=='redo-unchanged':
  assert p.returncode==0 and 'shipcraft: RED unchanged:' in p.stdout,(p.stdout,p.stderr)
  assert lock.read_bytes()==before and (lock.stat().st_ino,lock.stat().st_mtime_ns)==(stat.st_ino,stat.st_mtime_ns)
  assert 'shipcraft: warning: this lock is on ' not in p.stdout+p.stderr,(p.stdout,p.stderr)
  assert not any('shipcraft: next:' in line or line==controls for line in lines),lines
  assert rows()[-1]['redo'] is True and rows()[-1]['result']=='passed',rows()[-1]
  sys.exit()
 elif mode=='redo-write-fails':
  assert p.returncode==1 and rows()[-1]['code']=='redo-write-failed',(p,rows())
  assert lock.read_bytes()==before and 'shipcraft: warning: this lock is on ' not in p.stdout+p.stderr,(p.stdout,p.stderr)
  assert not any('shipcraft: next:' in line or line==controls for line in lines),lines
  sys.exit()
 assert p.returncode==0 and lock.read_bytes()!=before,(p.stdout,p.stderr)
 new=json.loads(lock.read_text())
 assert new['cases']==d['cases'] and new['controls']==d['controls'] and new['failing_at_red']==d['failing_at_red'],new
 announcement=next(i for i,line in enumerate(lines) if line.startswith('shipcraft: RED redone at'))
 assert lines[announcement-1]==controls,lines
 assert rows()[-1]['redo'] is True and rows()[-1]['result']=='passed',rows()[-1]
 assert lines[-1]=='shipcraft: next: the GREEN, in a new session ([roles] green not set)',lines
if mode=='fixture-control':
 assert git('remote','get-url','origin')==str(origin)
 assert d['files'].keys()=={'.shipcraft.toml','tests/test_old100.py','tests/test_pair100.py'},d
 assert 'shipcraft: red ran the changed test files: 1 of 3' in lines,lines
 expected=None
elif mode=='main':expected='main'
elif mode=='review-only':
 assert 'ci = "off"\nreview = "local"' in Path('.shipcraft.toml').read_text()
 expected='main'
elif mode=='defaults':
 assert '[execution]' not in Path('.shipcraft.toml').read_text()
 expected='main'
elif mode=='both-off':
 assert 'ci = "off"\nreview = "off"' in Path('.shipcraft.toml').read_text()
 expected=None
elif mode=='feature':expected=None
elif mode=='detached':expected=None
elif mode=='no-origin':expected=None
elif mode=='other-default':expected='release/100'
elif mode=='fallback-main':expected='main'
elif mode=='unreadable-head':expected='main'
elif mode=='main-not-default':expected=None
elif mode=='redo':expected='main'
elif mode=='log-fails':
 assert Path('.git/shipcraft/runs.jsonl').is_dir()
 expected='main'
else:raise AssertionError('unrouted case: '+mode)
warnings=[line for line in lines if line.startswith('shipcraft: warning: this lock is on ')]
if expected is None:assert not warnings,(mode,warnings)
else:
 warning='shipcraft: warning: this lock is on '+expected+', the default branch; shipcraft pr refuses to open a PR from it. Move the RED to its own branch before the GREEN (git switch -c item/<name>).'
 assert warnings==[warning] and lines[-2]==warning,('missing exact default-branch warning immediately before next:',p.stdout)
assert 'shipcraft: warning: this lock is on ' not in p.stderr,p.stderr
PY100
  pass
}
