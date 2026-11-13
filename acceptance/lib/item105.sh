# Item 105: release selection at RED and format 6; public commands only.
item105_langs() { echo core; }
item105_cases() {
  local c
  for c in control-v5 control-report control-row selected-v5 read-seal deploy wildcard literal grammar-valid grammar-invalid selection-default selection-pattern selection-invalid selection-readers fallback precedence-config precedence-suite precedence-open precedence-install read-status read-init read-hook read-ci read-close read-invalid v5-nonsemver redo redo-unchanged redo-log-fails redo-write-fails report-format6 report-row report-missing report-unavailable red-log-fails red-write-fails red-suite-fails; do echo "v1-105.$c"; done
}
item105_case() {
  EXPECT="item 105: ${CASE#v1-105.}"; v1_start codex
  must_accept 'project fixes_release contract' cmd "$PY" - "${CASE#v1-105.}" "$(command -v shipcraft)" "$CW" <<'PY105'
import hashlib,json,os,shlex,subprocess,sys
from pathlib import Path
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/'repo105 space';root.mkdir();os.chdir(root)
env=dict(os.environ)
for k in subprocess.check_output(['git','rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
def run(*args):
 p=subprocess.run(list(map(str,args)),env=env,input='',capture_output=True,text=True,timeout=60)
 print('$',shlex.join(list(map(str,args))),'rc',p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 return p
def git(*args):
 p=run('git',*args);assert p.returncode==0,('fixture git',p.stderr);return p.stdout.strip()
def write(name,data):
 p=Path(name);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
stamp=1700000000
def commit():
 global stamp
 stamp+=86400;env['GIT_AUTHOR_DATE']=str(stamp)+' +0000';env['GIT_COMMITTER_DATE']=str(stamp)+' +0000'
 git('add','-A');git('-c','core.hooksPath=/dev/null','commit','-qm','fixture105')
def rows():
 p=Path('.git/shipcraft/runs.jsonl');return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def locks():return sorted(Path('.shipcraft/locks').glob('*.json'))
def snapshot():return {str(p):p.read_bytes() for p in Path('.').rglob('*') if p.is_file() and '__pycache__' not in p.parts and '.pytest_cache' not in p.parts}
def seal(d):
 c={k:d[k] for k in ('format','state','files','cases','failing_at_red')};c['files']=dict(sorted(c['files'].items()))
 if d['format'] in (5,6):c['controls']=d['controls']
 if d['format'] in (4,5,6):c.update((k,d[k]) for k in ('kind','reported_at','fixes_release'))
 c['seal']='';return hashlib.sha256(json.dumps(c,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
def store(d):
 d['seal']=seal(d);lock.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
def fixture():
 git('init','-q','-b','main');git('config','user.name','RED105');git('config','user.email','red105@example.invalid')
 write('requirements.txt','pytest\n');p=run(binary,'init');assert p.returncode==0,(p.stdout,p.stderr)
 write('.gitignore','__pycache__/\n.pytest_cache/\nobserved105\nfail105\n')
 write('value105','red');write('.shipcraft.toml',base);commit()
 write('tests/test_value105.py','from pathlib import Path\ndef test_target105():\n    assert Path("value105").read_text()=="green"\ndef test_control105():\n    assert True\n')
def fresh(n):
 global root
 root=cw/('variant105-'+str(n));root.mkdir();os.chdir(root);fixture()
base='shipcraft_min="0.0"\nlang="python"\nrunner="pytest"\ntest_command="pytest -q --junitxml={junit} tests"\ntest_globs=["tests/**"]\ncheck="echo suite105 >> observed105; test ! -f fail105"\n[execution]\nci="local"\nreview="off"\n'
pattern='[report]\nrelease_tags="deploy-*"\n';tag='deploy-20261112-200036';time='2026-11-12T20:00:36-03:00'
fixture()
if case in ('control-v5','selected-v5'):
 if case=='selected-v5':write('.shipcraft.toml',base+'[report]\nrelease_tags="v*"\n')
 p=run(binary,'red','--fix','--fixes-release','v1.2.3');assert p.returncode==0,(p.stdout,p.stderr)
 d=json.loads(locks()[0].read_text());assert d['format']==5 and d['fixes_release']=='v1.2.3' and d['controls']==['tests.test_value105::test_control105'] and d['seal']==seal(d),d
 assert rows()[-1]['fixes_release']=='v1.2.3' and Path('observed105').read_text().count('suite105')>=1,rows()
elif case in ('deploy','wildcard','literal','grammar-valid','selection-readers'):
 variants=[(pattern,tag)]
 if case=='wildcard':variants=[('[report]\nrelease_tags="pack**ages/*/v*"\n','packages/api/deep/v01+rc'),('[report]\nrelease_tags="de*ploy-*"\n','deploy-')]
 if case=='literal':variants=[('[report]\nrelease_tags="!release+().{}"\n','!release+().{}')]
 if case=='grammar-valid':variants=[('[report]\nrelease_tags='+json.dumps(t[0]+'*')+'\n',t) for t in ('a','@x','a]b','x/a.x-no', 'x/ok.locked','x/'+'z'*1024)]
 if case=='selection-readers':variants=[(s,tag) for s in ('report = { release_tags = "deploy-*" } # inline\n',"report.release_tags = 'deploy-*' # literal\r\n",'["report"]\r\n"release_tags"="depl\\u006fy-*" # escaped\r\n')]
 for i,(body,t) in enumerate(variants):
  if i:fresh(i)
  write('.shipcraft.toml',body+base if case=='selection-readers' and i<2 else base+body)
  p=run(binary,'red','--fixes-release',t,'--reported-at',time,'--fix');assert p.returncode==0,('valid project release refused',t,p.stdout,p.stderr)
  lock=locks()[0];d=json.loads(lock.read_text())
  assert list(d)==['format','state','files','cases','failing_at_red','controls','kind','reported_at','fixes_release','seal'] and d['format']==6,d
  assert (d['kind'],d['reported_at'],d['fixes_release'])==('fix',time,t) and d['seal']==seal(d),d
  assert d['controls']==['tests.test_value105::test_control105'] and d['failing_at_red']==['tests.test_value105::test_target105'],d
  assert all(h=='sha256:'+hashlib.sha256(Path(f).read_bytes()).hexdigest() for f,h in d['files'].items()),d
  assert rows()[-1]['fixes_release']==t and rows()[-1]['kind']=='fix',rows()
  assert git('tag','--list')=='','matching nonexistent tag must not require git existence'
  lines=p.stdout.splitlines();n=next(n for n,s in enumerate(lines) if s.startswith('shipcraft: RED locked at'))
  assert lines[n-1]=='shipcraft: controls: 1 passing case(s) of the changed test files; the hook runs them too' and lines[-1].startswith('shipcraft: next: the GREEN'),p.stdout
elif case=='grammar-invalid':
 for t in ('','x y','x\t','x\r','x\n','x\x1f','x\x7f','déploy','x~','x^','x:','x?','x*','x[','x\\','-x','@','x..y','x@{y','/x','x/','x//y','x.','.x','x/.y','x/a.lock','a.lock/x'):
  write('.shipcraft.toml','broken [\n');before=snapshot();p=run(binary,'red','--fix','--fixes-release',t)
  assert p.returncode==2 and 'invalid arguments:' in p.stderr and 'usage:' in p.stderr,(t,p.stdout,p.stderr)
  assert snapshot()==before and not Path('observed105').exists(),('invalid tag had effects',t)
elif case in ('selection-default','selection-pattern','selection-invalid','fallback','precedence-config','precedence-suite','precedence-open','precedence-install'):
 variants=[(base,tag,'vX.Y.Z')]
 if case=='selection-pattern':variants=[(base+pattern,'v1.2.3','deploy-*'),(base+pattern,'Xdeploy-a','deploy-*'),(base+'[report]\nrelease_tags="deploy-*-end"\n','deploy-a-endX','deploy-*-end')]
 if case=='selection-invalid':variants=[(base+b,'v1.2.3','invalid: [report] in .shipcraft.toml is invalid: '+r) for b,r in (('[report]\nrelease_tags=""\n','release_tags is empty'),('[report]\nrelease_tags="***"\n','release_tags is only *'),('[report]\nrelease_tags=7\n','release_tags is not a string'),('report=7\n','[report] is not a table'),('[report]\nz_typo=1\na_typo=2\nrelease_tags="? "\n','unknown key a_typo'))]
 if case=='fallback':variants=[(s,tag,'vX.Y.Z') for s in (None,b'\xff','broken [\n','DIRECTORY')]
 if case=='precedence-config':variants=[(base.replace('0.0','99999.0')+pattern,'v1.2.3','deploy-*')]
 if case=='precedence-suite':variants=[(base+'[[suite]]\nname="broken"\nroot="absent105"\ncommand="false"\nglobs=["tests/**"]\n'+pattern,'v1.2.3','deploy-*')]
 if case=='precedence-open':
  p=run(binary,'red');assert p.returncode==0,(p.stdout,p.stderr);commit();variants=[(base+pattern,'v1.2.3','deploy-*')]
 if case=='precedence-install':
  write('AGENTS.md',Path('AGENTS.md').read_text()+'\n# uncommitted install105\n');variants=[(base+pattern,'v1.2.3','deploy-*')]
 for body,t,selection in variants:
  config=Path('.shipcraft.toml')
  if config.is_dir():config.rmdir()
  if body is None:config.unlink(missing_ok=True)
  elif body=='DIRECTORY':config.unlink();config.mkdir()
  else:write(config,body)
  before=snapshot();p=run(binary,'red','--fix','--fixes-release',t)
  assert p.returncode==2 and p.stdout=='' and p.stderr.splitlines()==[f'shipcraft: --fixes-release {t} is not a release tag of this project (release tags: {selection})','Why: report counts a fix only against a release it reads, so this lock would name a release report never counts.','Next: pass the tag of the release that shipped the defect, or set [report] release_tags in .shipcraft.toml, then run red again.'],(selection,p.stdout,p.stderr)
  assert snapshot()==before,('selection refusal wrote state',t)
  assert not Path('observed105').exists() or case=='precedence-open','selection ran suite'
elif case in ('red-log-fails','red-write-fails','red-suite-fails'):
 write('.shipcraft.toml',base+pattern)
 if case=='red-log-fails':
  log=Path('.git/shipcraft/runs.jsonl');log.unlink(missing_ok=True);log.mkdir(parents=True)
 if case=='red-write-fails':Path('.shipcraft/locks').chmod(0o555)
 if case=='red-suite-fails':write('fail105','fail')
 try:p=run(binary,'red','--fix','--fixes-release',tag)
 finally:
  if case=='red-write-fails':Path('.shipcraft/locks').chmod(0o755)
 if case=='red-log-fails':
  assert p.returncode==0 and len(locks())==1,(p.stdout,p.stderr)
  d=json.loads(locks()[0].read_text());assert d['format']==6 and d['fixes_release']==tag and d['seal']==seal(d),d
 elif case=='red-write-fails':
  assert p.returncode==2 and 'error: write ' in p.stderr and not locks(),(p.stdout,p.stderr)
  assert rows()[-1]['result']=='error',rows()
 else:
  assert p.returncode==1 and not locks(),(p.stdout,p.stderr)
  r=rows()[-1];assert r['result']=='refused' and (r['kind'],r['fixes_release'])==('fix',tag),r
else:
 # Seed via the proved real pytest control, then serialize only the public wire schema.
 p=run(binary,'red','--fix','--fixes-release','v1.2.3');assert p.returncode==0,(p.stdout,p.stderr)
 lock=locks()[0];d=json.loads(lock.read_text());d.update(format=6,kind='fix',reported_at=time,fixes_release=tag);write('.shipcraft.toml',base+pattern)
 # The fixture changed the config after RED; reflect its actual bytes in the sealed fixture.
 for f in d['files']:d['files'][f]='sha256:'+hashlib.sha256(Path(f).read_bytes()).hexdigest()
 store(d);commit();original=lock.read_bytes();parent=git('rev-parse','HEAD')
 if case=='read-status':
  before=snapshot();p=run(binary,'status');assert p.returncode==0 and lock.stem in p.stdout and 'open' in p.stdout,(p.stdout,p.stderr)
  assert snapshot()==before and lock.read_bytes()==original
 elif case=='read-init':
  write('lefthook.yml','pre-commit:\n  commands:\n    shipcraft:\n      run: shipcraft check\n      priority: 9\ncommit-msg:\n  commands:\n    shipcraft:\n      run: shipcraft check --commit-msg {1}\npost-commit:\n  commands:\n    shipcraft:\n      run: shipcraft close\n')
  p=run(binary,'init');assert p.returncode==1 and 'open lock' in p.stdout+p.stderr,(p.stdout,p.stderr)
  assert lock.read_bytes()==original
 elif case in ('read-hook','read-close','read-ci'):
  write('value105','green');git('add','value105')
  if case=='read-hook':
   log=Path('.git/shipcraft/runs.jsonl');log.unlink();log.mkdir()
   p=run(binary,'check')
  elif case=='read-close':
   p=run(binary,'check','--commit-msg','message105');assert p.returncode==0,(p.stdout,p.stderr)
   commit();p=run(binary,'close')
  else:
   d['state']='closed';store(d);commit();p=run(binary,'ci','--base',parent)
  assert p.returncode==0,(p.stdout,p.stderr)
  new=json.loads(lock.read_text());assert new['state']=='closed' and new['format']==6 and new['seal']==seal(new),new
  assert {k:v for k,v in new.items() if k not in ('state','seal')}=={k:v for k,v in d.items() if k not in ('state','seal')},new
 elif case in ('read-invalid','v5-nonsemver','read-seal'):
  variants=[('feature',tag,6),('fix',None,6),('fix','v1.2.3',6),('fix','x..y',6),('fix',7,6)]
  if case=='v5-nonsemver':variants=[('fix',tag,5)]
  if case=='read-seal':variants=[('fix',tag,6)]
  for kind,t,fmt in variants:
   d.update(format=fmt,kind=kind,fixes_release=t);store(d)
   if case=='read-seal':
    d['fixes_release']='deploy-tampered';lock.write_text(json.dumps(d)+'\n')
   commit();saved=lock.read_bytes();before=git('rev-parse','HEAD')
   write('product105',str(t));git('add','product105');p=run(binary,'check')
   assert p.returncode==1 and rows()[-1]['code']=='lock-edited',(p.stdout,p.stderr,rows())
   assert lock.read_bytes()==saved
   commit();p=run(binary,'ci','--base',before)
   assert p.returncode==1 and rows()[-1]['code']=='lock-edited',(p.stdout,p.stderr,rows())
   assert lock.read_bytes()==saved
 elif case in ('redo','redo-unchanged','redo-log-fails','redo-write-fails'):
  if case=='redo':write('.shipcraft.toml',base+'[report]\nrelease_tags="other-*"\n')
  if case in ('redo','redo-log-fails','redo-write-fails'):
   with Path('tests/test_value105.py').open('a') as f:f.write('\ndef test_added105():\n    assert True\n')
  if case=='redo-log-fails':
   log=Path('.git/shipcraft/runs.jsonl');log.unlink();log.mkdir()
  if case=='redo-write-fails':lock.parent.chmod(0o555)
  before=lock.stat().st_mtime_ns
  try:p=run(binary,'red','--redo')
  finally:
   if case=='redo-write-fails':lock.parent.chmod(0o755)
  if case=='redo-write-fails':
   assert p.returncode==1 and rows()[-1]['code']=='redo-write-failed' and lock.read_bytes()==original,(p.stdout,p.stderr,rows())
  else:
   assert p.returncode==0,(p.stdout,p.stderr)
   new=json.loads(lock.read_text());assert new['format']==6 and new['fixes_release']==tag and new['seal']==seal(new),new
   if case=='redo-unchanged':assert lock.read_bytes()==original and lock.stat().st_mtime_ns==before and 'RED unchanged:' in p.stdout and 'shipcraft: controls:' not in p.stdout,p.stdout
   else:assert 'tests.test_value105::test_added105' in new['controls'] and 'shipcraft: controls: 2 ' in p.stdout,(new,p.stdout)
 elif case in ('control-report','control-row','report-format6','report-row','report-missing','report-unavailable'):
  # Closed wire locks and passed RED rows describe two real release commits.
  lock.unlink();commit();first=git('rev-parse','HEAD');git('tag','deploy-old',first)
  d.update(state='closed',fixes_release='deploy-old');store(d)
  if case=='control-report':d.update(format=5,fixes_release='v1.2.3');store(d);git('tag','v1.2.3',first)
  if case in ('report-row','control-row'):
   lock.unlink();write('shipping105','row-only release105\n')
  if case=='report-missing':d['fixes_release']='deploy-absent';store(d)
  commit();git('tag','deploy-new')
  if case=='control-report':git('tag','v2.0.0')
  log=Path('.git/shipcraft/runs.jsonl');row=dict(layer='red',at=1700000000,lock=lock.stem,result='passed',secs=1,branch='main',commit=git('rev-parse','HEAD'),code='',kind='fix',reported_at=time,fixes_release='v9.8.7' if case=='control-row' else 'deploy-old')
  with log.open('a') as f:f.write(json.dumps(row)+'\n')
  if case=='control-report':write('.shipcraft.toml',base)
  if case=='report-unavailable':git('branch','-m','topic105')
  before=snapshot();p=run(binary,'report','--json');assert p.returncode==0 and snapshot()==before,(p.stdout,p.stderr)
  out=[json.loads(s) for s in p.stdout.splitlines()];r=next(r for r in out if r['kind']=='lock' and r['lock']==lock.stem);metric=next(r for r in out if r['kind']=='dora')
  if case=='control-report':assert r['fixes_release']=='v1.2.3' and r['change_kind']=='fix' and metric['change_failure_rate']['value']==0.5, (r,metric)
  elif case=='control-row':assert r['fixes_release']=='v9.8.7' and r['reported_at']==time and r['change_kind']=='fix' and metric['git']['releases']==2,(r,metric)
  elif case=='report-missing':assert r['fixes_release']=='deploy-absent' and metric['change_failure_rate']['value'] is None and metric['change_failure_rate']['missing']==1,(r,metric)
  elif case=='report-unavailable':assert r['fixes_release']=='deploy-old' and r['change_kind']=='fix' and metric['git']['reason']=='no default branch',(r,metric)
  elif case=='report-row':assert r['fixes_release']=='deploy-old' and r['change_kind']=='fix',r
  else:
   assert r['fixes_release']=='deploy-old' and metric['change_failure_rate']['value']==0.5 and metric['change_failure_rate']['missing']==0,(r,metric)
   p=run(binary,'report','--json','--since','deploy-new');m=next(json.loads(s) for s in p.stdout.splitlines() if json.loads(s)['kind']=='dora');assert m['change_failure_rate']['value']==0 and m['change_failure_rate']['n']==1 and m['change_failure_rate']['missing']==0,m
 else:raise AssertionError('unrouted case '+case)
PY105
  pass
}
