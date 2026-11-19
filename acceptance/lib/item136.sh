# Item 136: public commands, offline GitHub stub and real repositories.
item136_cases() {
 local c
 for c in repro-b admin-status other-base stub-control protected unprotected upgrade init-admin init-not-found init-upgrade no-origin protection-reader go-full go-narrow go-fixture go-redo go-hook go-all go-no-base go-write-fail go-log-fail go-unchanged pytest-unmapped pytest-control closed close-earliest close-invalid merged tip github-closed closed-invalid-config real-close span-five span-below span-day release-five release-below release-day single zero; do echo "v1-136.$c"; done
}
item136_case() {
 EXPECT='item 136 observed output'; v1_start codex
 PATH="$GOBIN:$PATH"; export PATH
 must_accept 'item 136 contract' cmd "$PY" - "${CASE#v1-136.}" "$ST" <<'PY136'
import datetime,hashlib,json,os,re,shlex,shutil,subprocess,sys
from pathlib import Path
case=sys.argv[1];st=Path(sys.argv[2]);parent=Path.cwd();binary=shutil.which('shipcraft')
def run(*args):
 p=subprocess.run(args,capture_output=True,text=True,timeout=120)
 print('$',shlex.join(args),'[exit',p.returncode,']\n'+p.stdout+p.stderr,flush=True);return p
def ok(*args):
 p=run(*args);assert p.returncode==0,(args,p.stdout,p.stderr);return p
def write(path,text):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
def git(*args):return ok('git',*args).stdout.strip()
def commit(message):git('add','-A');git('commit','-qm',message)
def rows():
 p=Path('.git/shipcraft/runs.jsonl');return [json.loads(x) for x in p.read_text().splitlines()] if p.is_file() else []
def locks():return sorted(Path('.shipcraft/locks').glob('*.json'))
def contents(path):
 p=Path(path);return p.read_bytes() if p.is_file() else None
def error_gh(err,out):
 gh=st.parent/'gh'
 gh.write_text('#!'+sys.executable+'\nimport sys\nsys.stderr.write('+repr(err)+')\nsys.stdout.write('+repr(out)+')\nsys.exit(1)\n')
def protect(mode):
 ok(binary,'init');git('remote','add','origin','https://github.com/acme/proj.git');(st/'protection').write_text(mode)
def status():
 before=contents('.git/shipcraft/runs.jsonl');cfg=contents('.shipcraft.toml');p=run(binary,'status')
 assert p.returncode==0 and contents('.git/shipcraft/runs.jsonl')==before and contents('.shipcraft.toml')==cfg
 assert 'branch protection' not in p.stderr
 return p,[x for x in p.stdout.splitlines() if 'branch protection' in x]
if case=='repro-b':
 ok('shipcraft','init');ok('git','remote','add','origin','https://github.com/acme/proj.git')
 (st/'protection').write_text('not-found')
 before=contents('.git/shipcraft/runs.jsonl');p=run('shipcraft','status')
 assert p.returncode==0 and contents('.git/shipcraft/runs.jsonl')==before and 'branch protection' not in p.stderr
 assert 'main has no branch protection' not in p.stdout, 'reproduction B: non-admin 404 is not proof of no protection'
 expected='shipcraft: could not read branch protection on main (GitHub answers 404 when this account is not an admin of the repository, so protection may exist): use `shipcraft merge` as the gate'
 assert [x for x in p.stdout.splitlines() if 'branch protection' in x]==[expected]
elif case=='admin-status':
 protect('admin-required');p,lines=status()
 assert lines==['shipcraft: could not read branch protection (gh: Must have admin rights to Repository. (HTTP 403)): use `shipcraft merge` as the gate'],lines
elif case=='other-base':
 protect('not-found');git('update-ref','refs/remotes/origin/trunk136','HEAD');git('symbolic-ref','refs/remotes/origin/HEAD','refs/remotes/origin/trunk136')
 p,lines=status();assert lines==['shipcraft: could not read branch protection on trunk136 (GitHub answers 404 when this account is not an admin of the repository, so protection may exist): use `shipcraft merge` as the gate'],lines
elif case=='stub-control':
 for mode,code,message in [('not-found',404,'Not Found'),('admin-required',403,'Must have admin rights to Repository.')]:
  (st/'protection').write_text(mode)
  for method in ('GET','PUT'):
   p=run('gh','api','-X',method,'repos/acme/proj/branches/main/protection')
   assert p.returncode==1 and p.stderr==f'gh: {message} (HTTP {code})\n'
   assert p.stdout==json.dumps(dict(message=message,documentation_url='https://docs.github.com/rest/branches/branch-protection#get-branch-protection',status=str(code)),separators=(',',':'))+'\n'
 assert len([x for x in (st/'calls.log').read_text().splitlines() if 'protection' in x])==4
 protect('full');gh=st.parent/'gh';original=gh.read_bytes()
 try:
  error_gh('first136\nHTTP 503','stdout136')
  probe=run('gh','api','repos/acme/proj/branches/main/protection');assert (probe.returncode,probe.stdout,probe.stderr)==(1,'stdout136','first136\nHTTP 503')
  p,lines=status();assert lines==['shipcraft: could not read branch protection (first136): use `shipcraft merge` as the gate'],lines
 finally:gh.write_bytes(original)

elif case=='protected':
 protect('full');(st/'protection.contexts').write_text('shipcraft/ci shipcraft/review');p,lines=status()
 assert len(lines)==1 and 'shipcraft/ci' in lines[0] and 'shipcraft/review' in lines[0] and 'no branch protection' not in lines[0],lines
elif case=='unprotected':
 protect('none');p,lines=status();assert lines==['shipcraft: main has no branch protection: `shipcraft merge` is the gate'],lines
elif case=='upgrade':
 protect('403');p,lines=status();assert lines==['shipcraft: this repository has no branch protection (GitHub free plan): `shipcraft merge` is the gate'],lines
elif case=='init-admin':
 git('remote','add','origin','https://github.com/acme/proj.git');(st/'protection').write_text('admin-required');p=run(binary,'init','--github')
 assert p.returncode==0 and 'could not mark statuses as required (gh: Must have admin rights to Repository. (HTTP 403)' in p.stdout+p.stderr and 'no branch protection on its GitHub plan' not in p.stdout+p.stderr,(p.stdout,p.stderr)
 assert (st/'protection').read_text()=='admin-required' and 'protection' in (st/'writes.log').read_text()
elif case=='init-not-found':
 git('remote','add','origin','https://github.com/acme/proj.git');(st/'protection').write_text('not-found');p=run(binary,'init','--github')
 assert p.returncode==0 and 'could not mark statuses as required (gh: Not Found (HTTP 404)' in p.stdout+p.stderr and 'no branch protection on its GitHub plan' not in p.stdout+p.stderr,(p.stdout,p.stderr)
elif case=='init-upgrade':
 git('remote','add','origin','https://github.com/acme/proj.git');(st/'protection').write_text('403');p=run(binary,'init','--github')
 assert p.returncode==0 and 'this repository has no branch protection on its GitHub plan: `shipcraft merge` is the gate.' in p.stdout+p.stderr,(p.stdout,p.stderr)
elif case=='no-origin':
 ok(binary,'init');(st.parent/'gh').unlink();p,lines=status();assert len(lines)==1 and lines[0].startswith('shipcraft: could not read branch protection (') and lines[0].endswith('): use `shipcraft merge` as the gate'),lines
elif case=='protection-reader':
 protect('full');gh=st.parent/'gh';original=gh.read_bytes()
 # Error-only wrapper: these are message matching boundaries, never successful API documents.
 variants=[('first\nBranch not protected; HTTP 404','', 'shipcraft: main has no branch protection: `shipcraft merge` is the gate'),('Branch not protected; HTTP 404\nUpgrade to GitHub Pro','', 'shipcraft: this repository has no branch protection (GitHub free plan): `shipcraft merge` is the gate'),('','  gh: Not Found (HTTP 404)\n','shipcraft: could not read branch protection on main (GitHub answers 404 when this account is not an admin of the repository, so protection may exist): use `shipcraft merge` as the gate'),('lowercase branch not protected (HTTP 403)','', 'shipcraft: could not read branch protection (lowercase branch not protected (HTTP 403)): use `shipcraft merge` as the gate'),('first line\nHTTP 503','', 'shipcraft: could not read branch protection (first line): use `shipcraft merge` as the gate'),('bare 404 without HTTP prefix','', 'shipcraft: could not read branch protection (bare 404 without HTTP prefix): use `shipcraft merge` as the gate'),('first line\nHTTP 404','', 'shipcraft: could not read branch protection on main (GitHub answers 404 when this account is not an admin of the repository, so protection may exist): use `shipcraft merge` as the gate')]
 try:
  observed=[]
  for err,out,expected in variants:
   error_gh(err,out)
   probe=run('gh','api','repos/acme/proj/branches/main/protection');assert (probe.returncode,probe.stdout,probe.stderr)==(1,out,err)
   p,lines=status();observed.append((lines,expected))
  assert all(lines==[expected] for lines,expected in observed),observed
 finally:gh.write_bytes(original)
else:pass

def suite_fixture(lang='go',full=True):
 root=parent/'project136';root.mkdir();os.chdir(root);git('init','-q','-b','main')
 write('.gitignore','__pycache__/\n.pytest_cache/\n');write('value136','red');write('control136','green')
 if lang=='go':
  write('go.mod','module example.invalid/item136\n\ngo 1.21\n')
  for name,tag in [('posix','!windows'),('windows','windows')]:
   write('own/ambiguous_'+name+'_test.go','//go:build '+tag+'\n\npackage item136\nimport "testing"\nfunc TestAmbiguous136(t *testing.T) {\n t.Run("one",func(t *testing.T){})\n t.Run("two",func(t *testing.T){})\n}\n')
  write('own/old_test.go','package item136\nimport "testing"\nfunc TestOld136(t *testing.T) {}\n')
 else:write('own/tests/test_old136.py','def test_old136():\n    assert True\n')
 record=parent/'observed136.jsonl';os.environ['OBS136']=str(record)
 adapter=root/'adapter136.py'
 write(adapter,'''import json,os,re,subprocess,sys
from pathlib import Path
import xml.etree.ElementTree as ET
lang,junit=sys.argv[1:]
def read(k):
 p=os.environ.get(k);return Path(p).read_bytes().decode().split('\\0')[:-1] if p else None
cases=read('SHIPCRAFT_CASES');files=read('SHIPCRAFT_FILES')
if lang=='go':
 cmd=['gotestsum','--junitfile',junit,'--','-count=1']
 names=[c.split('::')[-1] for c in cases or []]
 if files and not cases:
  names=[n for f in files for n in re.findall(r'^func (Test\\w+)\\(',Path(f).read_text(),re.M)]
 if names:cmd+=['-run','^(?:'+'|'.join(re.escape(n) for n in names)+')$']
 cmd+=['./...']
else:
 paths=[c.split('::')[0].replace('.','/')+'.py::'+c.split('::')[1] for c in cases or []] or files or ['tests']
 cmd=['pytest','-q','-p','no:cacheprovider','--junitxml='+junit,*paths]
p=subprocess.run(cmd)
t=ET.parse(junit)
if lang=='python':
 for c in t.iter('testcase'):
  if c.get('name')=='test_unmapped136':c.set('classname','unknown136');c.set('name','unmapped136');c.attrib.pop('file',None)
 t.write(junit)
with open(os.environ['OBS136'],'a') as f:f.write(json.dumps(dict(lang=lang,cases=cases,files=files,ids=[c.get('classname','')+'::'+c.get('name','') for c in t.iter('testcase')]))+'\\n')
sys.exit(p.returncode)
''')
 config='shipcraft_min="0.0"\nlang='+json.dumps(lang)+'\nrunner='+json.dumps('gotestsum' if lang=='go' else 'pytest')+'\n[execution]\nci="local"\nreview="off"\n[[suite]]\nname="own"\nroot="own"\nfilter="command"\ncommand='+json.dumps(shlex.join([sys.executable,str(adapter),lang,'{junit}'])+(' # gotestsum' if lang=='go' else ''))+'\nglobs='+json.dumps(['**/*_test.go'] if lang=='go' else ['tests/**'])+'\n'
 write('.shipcraft.toml',config);commit('chore: base136');ok(binary,'init','--lang',lang);commit('chore: installation136')
 config=Path('.shipcraft.toml').read_text();base=git('rev-parse','HEAD');git('update-ref','refs/remotes/origin/main',base);git('symbolic-ref','refs/remotes/origin/HEAD','refs/remotes/origin/main');git('checkout','-qb','feature/item136')
 if lang=='go':
  path='own/pair_test.go';write(path,'package item136\nimport("testing";"os")\nfunc TestTarget136(t *testing.T) { v,_:=os.ReadFile("../value136");if string(v)!="green" {t.Fatal("red136")} }\nfunc TestZ136(t *testing.T) { v,_:=os.ReadFile("../control136");if string(v)!="green" {t.Fatal("control136")} }\nfunc TestA136(t *testing.T) {}\n')
 else:
  path='own/tests/test_pair136.py';write(path,'from pathlib import Path\ndef test_target136():\n    assert Path("../value136").read_text()=="green"\ndef test_z136():\n    assert True\ndef test_a136():\n    assert True\ndef test_unmapped136():\n    assert True\n')
 if full:write('.shipcraft.toml',config+'\n# full fallback136\n')
 return path,record

def read_lock():
 ls=locks();assert len(ls)==1,ls;return ls[0],json.loads(ls[0].read_text())
def control_line(p):return [l for l in p.stdout.splitlines() if l.startswith('shipcraft: controls:')]
if case=='go-full':
 path,record=suite_fixture();p=ok(binary,'red');lock,d=read_lock()
 assert 'red ran every suite: config changed' in p.stdout
 assert d['controls']==['own:example.invalid/item136/own::TestA136','own:example.invalid/item136/own::TestZ136'],d
 line='shipcraft: controls: 2 passing case(s) of the changed test files; the hook runs them too; 3 passing case(s) could not be tied to a single test file, so they are not controls'
 assert control_line(p)==[line] and p.stdout.splitlines()[p.stdout.splitlines().index(line)+1].startswith('shipcraft: RED locked at') and 'controls:' not in p.stderr,p.stdout
 assert d['format']==5 and d['failing_at_red']==['own:example.invalid/item136/own::TestTarget136']
 assert set(d)=={'format','state','files','cases','failing_at_red','controls','kind','reported_at','fixes_release','seal'}
elif case=='go-narrow':
 path,record=suite_fixture(full=False);p=ok(binary,'red');lock,d=read_lock()
 assert d['controls']==['own:example.invalid/item136/own::TestA136','own:example.invalid/item136/own::TestZ136'],d
 assert control_line(p)==['shipcraft: controls: 2 passing case(s) of the changed test files; the hook runs them too']
 assert not any('Ambiguous' in c or 'Old136' in c for c in d['cases']) and json.loads(record.read_text().splitlines()[0])['files']==[str(Path(path).resolve())]
elif case=='go-fixture':
 path,record=suite_fixture();p=ok(binary,'red');lock,d=read_lock();observed=[json.loads(x) for x in record.read_text().splitlines()]
 assert observed[0]['lang']=='go' and observed[0]['files'] is None and observed[1]['cases']==['example.invalid/item136/own::TestTarget136'],observed
 assert set(observed[0]['ids'])=={'example.invalid/item136/own::'+n for n in ('TestA136','TestZ136','TestTarget136','TestOld136','TestAmbiguous136','TestAmbiguous136/one','TestAmbiguous136/two')},observed
 assert d['failing_at_red']==['own:example.invalid/item136/own::TestTarget136'] and 'red ran every suite: config changed' in p.stdout
 assert git('diff','--name-only','main')=='.shipcraft.toml' and git('status','--porcelain','own/ambiguous_posix_test.go','own/ambiguous_windows_test.go','own/old_test.go')==''
elif case=='go-redo':
 path,record=suite_fixture();ok(binary,'red');commit('test: RED136');write(path,Path(path).read_text()+'\nfunc TestAdded136(t *testing.T) {}\n');p=ok(binary,'red','--redo');lock,d=read_lock()
 assert d['controls']==['own:example.invalid/item136/own::TestA136','own:example.invalid/item136/own::TestAdded136','own:example.invalid/item136/own::TestZ136'],d
 line='shipcraft: controls: 3 passing case(s) of the changed test files; the hook runs them too; 3 passing case(s) could not be tied to a single test file, so they are not controls'
 assert control_line(p)==[line] and p.stdout.splitlines()[p.stdout.splitlines().index(line)+1].startswith('shipcraft: RED redone at'),p.stdout
elif case=='go-hook':
 path,record=suite_fixture();ok(binary,'red');commit('test: RED136');lock,d=read_lock();before=lock.read_bytes();head=git('rev-parse','HEAD')
 write('value136','green');write('control136','red');git('add','value136','control136');p=run('git','commit','-qm','feat: broken control136')
 assert p.returncode==1 and rows()[-1]['code']=='control-failed',(p.stdout,p.stderr,rows())
 assert lock.read_bytes()==before and git('rev-parse','HEAD')==head
 assert 'TestZ136' in p.stdout+p.stderr and 'TestTarget136' not in (p.stdout+p.stderr).split('shipcraft refused:')[-1]
elif case=='go-all':
 path,record=suite_fixture();p=ok(binary,'red','--all');lock,d=read_lock()
 assert d['controls']==[] and any('TestAmbiguous136' in x for x in d['cases']) and control_line(p)==['shipcraft: controls: 0 passing case(s) of the changed test files; the hook runs them too']
elif case=='go-no-base':
 path,record=suite_fixture();p=ok(binary,'red','--base','absent136');lock,d=read_lock()
 assert d['controls']==[] and any('TestAmbiguous136' in x for x in d['cases']) and control_line(p)==['shipcraft: controls: 0 passing case(s) of the changed test files; the hook runs them too']
elif case=='go-write-fail':
 path,record=suite_fixture();Path('.shipcraft/locks').chmod(0o555)
 try:p=run(binary,'red')
 finally:Path('.shipcraft/locks').chmod(0o755)
 assert p.returncode!=0 and not locks() and not control_line(p) and rows()[-1]['result']=='error'
 assert 'TestAmbiguous136/one' in record.read_text()
elif case=='go-log-fail':
 path,record=suite_fixture();log=Path('.git/shipcraft/runs.jsonl');log.unlink(missing_ok=True);log.mkdir();p=ok(binary,'red');lock,d=read_lock()
 assert log.is_dir() and d['controls']==['own:example.invalid/item136/own::TestA136','own:example.invalid/item136/own::TestZ136'],d
 assert control_line(p)==['shipcraft: controls: 2 passing case(s) of the changed test files; the hook runs them too; 3 passing case(s) could not be tied to a single test file, so they are not controls']
elif case=='go-unchanged':
 path,record=suite_fixture(full=False);ok(binary,'red');commit('test: RED136');git('update-ref','refs/remotes/origin/main','HEAD');lock,d=read_lock();before=lock.read_bytes();p=ok(binary,'red','--redo')
 assert lock.read_bytes()==before and 'RED unchanged:' in p.stdout and not control_line(p) and len(d['controls'])==2
elif case=='pytest-unmapped':
 path,record=suite_fixture('python');p=ok(binary,'red');lock,d=read_lock()
 assert d['controls']==[] and 'own:unknown136::unmapped136' in d['cases']
 assert control_line(p)==['shipcraft: controls: 0 passing case(s) of the changed test files; the hook runs them too; 4 passing case(s) could not be tied to a single test file, so they are not controls'],p.stdout
elif case=='pytest-control':
 path,record=suite_fixture('python');p=ok(binary,'red');lock,d=read_lock();observed=[json.loads(x) for x in record.read_text().splitlines()]
 assert observed[0]['lang']=='python' and set(observed[0]['ids'])=={'tests.test_pair136::test_target136','tests.test_pair136::test_a136','tests.test_pair136::test_z136','tests.test_old136::test_old136','unknown136::unmapped136'},observed
 assert observed[1]['cases']==['tests.test_pair136::test_target136'] and d['controls']==[] and d['failing_at_red']==['own:tests.test_pair136::test_target136']
elif case=='real-close':
 path,record=suite_fixture(full=False);ok(binary,'red');commit('test: RED136');write('value136','green');commit('feat: GREEN136');lock,d=read_lock()
 p=ok(binary,'status');assert 'open locks: none' in p.stdout and d['state']=='closed'
 p=ok(binary,'report','--json');rs=[json.loads(x) for x in p.stdout.splitlines()];r=next(x for x in rs if x['kind']=='lock' and x['lock']==lock.stem)
 assert r['close_at'] is not None and r['state']=='closed',r
 assert f'lock {lock.stem}: closed; red at ' in ok(binary,'report').stdout

# Real Git plumbing gives exact deploy times without changing a process clock.
T=1700000000
def history(span=5,release=False,single=False):
 root=parent/'report136';root.mkdir();os.chdir(root);git('init','-q','-b','main');git('config','gc.auto','0');git('config','maintenance.auto','false')
 write('.shipcraft.toml','shipcraft_min="0.0"\nlang="python"\nrunner="pytest"\ntest_command="false"\n[execution]\nci="off"\nreview="off"\n[report]\ndeploy='+json.dumps('release' if release else 'merge')+'\n')
 a=save(T)
 if release:git('tag','v1.0.0',a)
 if not single:
  write('second','direct commit136');b=save(T+span)
  if release:git('tag','v2.0.0',b)
 git('checkout','-qb','feature/report136')
 return a

def save(at):
 git('add','-A');tree=git('write-tree');head=run('git','rev-parse','--verify','HEAD');parents=['-p',head.stdout.strip()] if head.returncode==0 else []
 env=dict(os.environ,GIT_AUTHOR_DATE=f'{at} +0000',GIT_COMMITTER_DATE=f'{at} +0000')
 p=subprocess.run(['git','commit-tree',tree,*parents,'-m','fixture136'],env=env,capture_output=True,text=True);assert p.returncode==0,p.stderr
 git('update-ref','HEAD',p.stdout.strip());return p.stdout.strip()
def event(layer,at,**kw):
 d=dict(layer=layer,at=at,lock='L136',result='passed',secs=1,branch='feature/report136',commit='a'*40,code='',reason='')
 if layer=='merge':d.update(locks=['L136'],base='main',default_branch='main')
 d.update(kw);return d

def log_events(events):write('.git/shipcraft/runs.jsonl',''.join(json.dumps(x)+'\n' for x in events))
def report(*args):
 before={str(p):p.read_bytes() for p in Path('.').rglob('*') if p.is_file()};p=ok(binary,'report',*args)
 assert before=={str(p):p.read_bytes() for p in Path('.').rglob('*') if p.is_file()},'report wrote state'
 return p

def decoded(*args):
 p=report('--json',*args);rs=[json.loads(s) for s in p.stdout.splitlines()];return rs,next(r for r in rs if r['kind']=='dora')
def closed_events():return [event('red',T),event('close',T+4)]
if case=='closed':
 history();log_events(closed_events());rs,d=decoded();r=next(r for r in rs if r['kind']=='lock')
 assert r['state']=='closed' and r['close_at']==T+4 and r['red_to_close']==4 and r['merge_at'] is None,r
 assert not any(r['kind']=='day' for r in rs)
 assert 'lock L136: closed; red at 2023-11-14T22:13:20Z, close at 2023-11-14T22:13:24Z' in report().stdout
elif case=='close-earliest':
 history();log_events([event('red',T),event('close',T+8),event('close',T+1,redo=True),event('close',T+2,result='error'),event('close',T+4),event('merge',T+6,base='other'),event('merge','unreadable')]);rs,d=decoded();r=next(r for r in rs if r['kind']=='lock')
 assert r['state']=='closed' and r['close_at']==T+4 and r['merge_at'] is None and not any(x['kind']=='day' for x in rs),r
elif case=='close-invalid':
 history();log_events([event('red',T),event('close',T+1,redo=True),event('close',T+2,result='refused'),event('close','invalid')]);rs,d=decoded();r=next(r for r in rs if r['kind']=='lock')
 assert r['state']=='open' and r['close_at'] is None and not any(x['kind']=='day' for x in rs),r
elif case=='merged':
 history();log_events(closed_events()+[event('merge',T+5)]);rs,d=decoded();r=next(r for r in rs if r['kind']=='lock')
 assert r['state']=='merged' and r['close_at']==T+4 and sum(x['merged_locks'] for x in rs if x['kind']=='day')==1,r
elif case=='tip':
 path,record=suite_fixture(full=False);ok(binary,'red');commit('test: RED136');write('value136','green');commit('feat: GREEN136');lock,d=read_lock();git('update-ref','refs/remotes/origin/main','HEAD');git('update-ref','refs/heads/main','HEAD');rs,dr=decoded();r=next(r for r in rs if r['kind']=='lock' and r['lock']==lock.stem)
 assert r['state']=='merge_not_observed' and r['close_at'] is not None and not any(x['kind']=='day' for x in rs),r
elif case=='github-closed':
 history();git('remote','add','origin','https://github.com/acme/proj.git');log_events(closed_events()+[event('pr',T+4,pr=97,locks=['L136'])]);before=contents(st/'calls.log');rs,d=decoded('--github');r=next(r for r in rs if r['kind']=='lock')
 assert r['state']=='closed' and not any(x['kind']=='day' for x in rs),r
 assert contents(st/'calls.log')==before and next(x for x in rs if x['kind']=='github')['selected']==0,rs
elif case=='closed-invalid-config':
 history();log_events(closed_events());write('.shipcraft.toml','[report]\ndeploy=7\n');rs,d=decoded();r=next(r for r in rs if r['kind']=='lock')
 assert r['state']=='closed' and r['close_at']==T+4 and d['deploys']['value'] is None and 'invalid' in d['git']['reason'],(r,d)
elif case=='span-five':
 history(5);rs,d=decoded();assert d['deploys']==dict(value=dict(count=2,first=T,last=T+5,per_day=None),n=2,missing=0,reason=None),d
 assert 'deploys: 2 merge(s), first at 2023-11-14T22:13:20Z, last at 2023-11-14T22:13:25Z, per day - (first to last under a day) (n 2, missing 0)' in report().stdout
elif case=='span-below':
 history(86399);rs,d=decoded();assert d['deploys']==dict(value=dict(count=2,first=T,last=T+86399,per_day=None),n=2,missing=0,reason=None),d
 assert 'per day - (first to last under a day) (n 2, missing 0)' in report().stdout
elif case=='span-day':
 history(86400);rs,d=decoded();assert d['deploys']==dict(value=dict(count=2,first=T,last=T+86400,per_day=2),n=2,missing=0,reason=None),d
 assert 'per day 2.00 (n 2, missing 0)' in report().stdout and 'first to last under a day' not in report().stdout
elif case=='release-five':
 history(5,release=True);rs,d=decoded();assert d['deploys']==dict(value=dict(count=2,first=T,last=T+5,per_day=None),n=2,missing=0,reason=None),d
 assert 'deploys: 2 release(s), first at 2023-11-14T22:13:20Z, last at 2023-11-14T22:13:25Z, per day - (first to last under a day) (n 2, missing 0)' in report().stdout
elif case=='release-below':
 history(86399,release=True);rs,d=decoded();assert d['deploys']==dict(value=dict(count=2,first=T,last=T+86399,per_day=None),n=2,missing=0,reason=None),d
 assert 'per day - (first to last under a day) (n 2, missing 0)' in report().stdout
elif case=='release-day':
 history(86400,release=True);rs,d=decoded();assert d['deploys']==dict(value=dict(count=2,first=T,last=T+86400,per_day=2),n=2,missing=0,reason=None),d
 assert 'per day 2.00 (n 2, missing 0)' in report().stdout and 'first to last under a day' not in report().stdout
elif case=='single':
 history(single=True);rs,d=decoded();assert d['deploys']==dict(value=dict(count=1,first=T,last=T,per_day=None),n=1,missing=0,reason=None),d
 assert 'per day - (n 1, missing 0)' in report().stdout and 'first to last under a day' not in report().stdout
elif case=='zero':
 history(0,release=True);rs,d=decoded();assert d['deploys']==dict(value=dict(count=2,first=T,last=T,per_day=None),n=2,missing=0,reason=None),d
 assert 'per day - (n 2, missing 0)' in report().stdout and 'first to last under a day' not in report().stdout

PY136
 pass
}
