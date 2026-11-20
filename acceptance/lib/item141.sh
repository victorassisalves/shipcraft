# Item 141: commits that bypass commit-msg, public commands and real Git only.
item141_langs() { echo python; }
item141_cases() {
  for c in repro tree-hook tree-index cherry-pick cherry-green rebase-pick rebase-fixup rebase-continue bypass-refused close-repeat close-failure close-format close-action sha256 parent-lock reader-evidence reader-amend reader-invalid status-range status-cutoff status-reader status-parents status-common status-am status-shallow status-origin pr-off pr-local pr-github pr-push-fails pr-later-fails pr-cap control-fixture control-judged control-root control-no-lock control-mark control-legacy control-pr control-git; do echo "v1-141.$c"; done
}
item141_case() {
  EXPECT="item 141: ${CASE#v1-141.}"; v1_start codex
  setup_init
  must_accept 'unjudged commit contract' cmd "$PY" - "${CASE#v1-141.}" "$CB" "$CW" <<'PY141'
import json,os,re,shlex,shutil,subprocess,sys
import tomli as tomllib
from pathlib import Path
case=sys.argv[1];cb=Path(sys.argv[2]);cw=Path(sys.argv[3]);st=cb/'state'
os.environ['TRACE141']=str(cw/'suite141.trace')
def run(*args,env=None):
 p=subprocess.run(list(map(str,args)),capture_output=True,text=True,timeout=90,env=env)
 print('$',shlex.join(map(str,args)),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 return p
def ok(*args,env=None):
 p=run(*args,env=env);assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr);return p
def git(*args):return ok('git',*args).stdout.strip()
def write(path,text):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
def commit(message):git('add','-A');return ok('git','commit','-qm',message)
def head():return git('rev-parse','HEAD')
def logbytes():
 p=Path(git('rev-parse','--git-common-dir'))/'shipcraft/runs.jsonl'
 return p.read_bytes() if p.is_file() else b''
def rows():return [json.loads(s) for s in logbytes().splitlines()]
def seed(ci='local',both=False):
 cfg=Path('.shipcraft.toml').read_text()
 prefix,block=cfg.split('[execution]',1);execution,sep,tail=block.partition('[roles]')
 execution=re.sub(r'(?m)^ci\s*=.*$', 'ci = '+json.dumps(ci),execution)
 execution=re.sub(r'(?m)^review\s*=.*$', 'review = "off"',execution)
 cfg=prefix+'[execution]'+execution+sep+tail
 if both:
  command=tomllib.loads(cfg)['test_command']
  cfg=re.sub(r'(?m)^test_command\s*=.*$',lambda _: 'test_command = '+json.dumps(command+' # vitest jest'),cfg)
 write('.shipcraft.toml',cfg)
 git('checkout','-qb','fixture141')
 write('textutil.py','def slugify(text):\n    raise NotImplementedError\n')
 write('tests/test_old.py','def test_old(): assert 2+2==4\n')
 commit('old test before T')
 write('tests/test_old.py','def test_old(): assert 3+3==6\n')
 commit('T: old test edit');t=head();git('branch','main141',t);git('update-ref','refs/heads/main',t)
 git('checkout','-qb','item141')
 write('textutil.py','def slugify(text):\n    raise NotImplementedError\n')
 write('tests/test_slug.py','import os\nfrom textutil import slugify\ndef test_slug():\n    with open(os.environ["TRACE141"], "a") as f: f.write("pytest141\\n")\n    assert slugify("Hello")=="hello"\n')
 ok('shipcraft','red','--all');commit('RED141')
 lock=next(Path('.shipcraft/locks').glob('*.json'))
 return t,lock
def logpath():return Path(git('rev-parse','--git-common-dir'))/'shipcraft/runs.jsonl'
def save_rows(values):
 p=logpath();p.parent.mkdir(parents=True,exist_ok=True)
 p.write_text(''.join(json.dumps(v)+'\n' for v in values))
def append_rows(values):
 with logpath().open('a') as f:
  for v in values:f.write(json.dumps(v)+'\n')
def snapshot(message):
 git('add','-A');tree=git('write-tree');sha=git('commit-tree',tree,'-p',head(),'-m',message)
 git('update-ref','-m','fixture141: '+message,'HEAD',sha);return sha
def bypass(message='unjudged141'):
 git('add','-A');return ok('git','commit','--no-verify','-qm',message)
def green():write('textutil.py','def slugify(text):\n    return text.lower()\n')
def trace():return (cw/'suite141.trace').read_bytes() if (cw/'suite141.trace').exists() else b''
def localclose():return ok('shipcraft','close')
def notices(p):return [l for l in p.stdout.splitlines() if l.startswith('shipcraft: commit ')]
def statuslines(p):return [l for l in p.stdout.splitlines() if l.startswith('shipcraft: commits with a lock open that the hook did not judge:')]
def warninglines(p):return [l for l in p.stdout.splitlines() if l.startswith('shipcraft: warning:') and 'hook did not judge them' in l]
def evidence(commit,tree=None,**kw):
 return dict(layer='hook',result='passed',commit=commit,tree=tree if tree is not None else git('rev-parse','HEAD^{tree}'),at=0,**kw)
def cutoff():
 append_rows([dict(layer='red',result='passed',commit='',tree='',at=0),evidence(git('rev-parse','HEAD^'))])
def remote(base):
 origin=cb/'origin141.git';git('init','-q','--bare',origin)
 git('--git-dir='+str(origin),'symbolic-ref','HEAD','refs/heads/main')
 write(st/'origin',str(origin));git('remote','add','origin',origin)
 git('push','-q','origin',base+':refs/heads/main');git('fetch','-q','origin');git('remote','set-head','origin','main')
def pr():
 write(st/'sha',head());write(cw/'body141','Body141\n')
 return run('shipcraft','pr','--title','Item141','--body',cw/'body141')
def gitproxy(code):
 real=shutil.which('git');folder=cw/'git141';folder.mkdir()
 write(folder/'git','#!'+sys.executable+'\nimport os,sys\na=sys.argv[1:]\n'+code+'\nos.execv('+repr(real)+',['+repr(real)+',*a])\n')
 (folder/'git').chmod(0o755);os.environ['PATH']=str(folder)+os.pathsep+os.environ['PATH']
 return folder/'git'
if case=='repro':
 t,lock=seed();before=logbytes()
 p=ok('git','revert','--no-edit',t);sha=head();short=sha[:7]
 assert logbytes()==before,'revert unexpectedly wrote a judgment row'
 q=run('shipcraft','ci','--base','main141')
 assert q.returncode==1 and rows()[-1]['code']=='test-changed',(q.returncode,q.stdout,q.stderr,rows()[-1])
 print('REPRODUCTION: git revert --no-edit T stderr='+repr(p.stderr)+'; CI refuses locked test edit',flush=True)
 what=next(l.removeprefix('shipcraft refused: ') for l in (q.stdout+q.stderr).splitlines() if l.startswith('shipcraft refused: '))
 nextstep=next(l.removeprefix('Next: ') for l in (q.stdout+q.stderr).splitlines() if l.startswith('Next: '))
 expected=[f'shipcraft: commit {short} (revert) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).',f'shipcraft: commit {short} would be refused by CI (test-changed): {what}; next: {nextstep}']
 assert [l for l in p.stderr.splitlines() if l.startswith('shipcraft:')]==expected,(p.stdout,p.stderr,expected)
elif case=='tree-hook':
 t,lock=seed();parent=head();write('unlocked141','staged');git('add','unlocked141')
 p=ok('shipcraft','check','--commit-msg','unused message')
 r=rows()[-1];tree=git('write-tree')
 assert r['layer']=='hook' and r['result']=='passed' and r['commit']==parent and r.get('tree')==tree,r
 write('tests/test_old.py','# changed\n');git('add','tests/test_old.py')
 p=run('shipcraft','check','--commit-msg','unused message')
 assert p.returncode==1 and rows()[-1].get('tree')==git('write-tree') and rows()[-1]['result']=='refused',rows()[-1]
 # Even a failed hook run with an unmerged index records the explicit empty tree.
 blob=git('rev-parse','HEAD:tests/test_old.py')
 git('update-index','--force-remove','tests/test_old.py')
 data=''.join('100644 '+blob+' '+str(i)+'\ttests/test_old.py\n' for i in (1,2,3))
 q=subprocess.run(['git','update-index','--index-info'],input=data,text=True,capture_output=True)
 assert q.returncode==0,q.stderr
 run('shipcraft','check','--commit-msg','unused message')
 assert rows()[-1]['layer']=='hook' and rows()[-1].get('tree')=='',rows()[-1]
elif case=='tree-index':
 t,lock=seed();parent=head()
 write('ordinary141','outside partial commit');git('add','ordinary141')
 write('only141','inside partial commit');git('add','only141')
 p=ok('git','commit','--only','-qm','partial141','--','only141')
 r=rows()[-1]
 assert r.get('tree')==git('rev-parse','HEAD^{tree}') and r['commit']==parent,r
 assert git('write-tree')!=r['tree'] and not notices(p)
 green();git('add','textutil.py');ok('shipcraft','check')
 assert rows()[-1].get('tree')==git('write-tree'),rows()[-1]
 assert json.loads(lock.read_text())['state']=='closed'
elif case=='cherry-pick':
 t,lock=seed();red=head()
 git('checkout','-qb','side141',t);write('tests/test_old.py','def test_old(): assert 5==5\n');commit('S2');s2=head()
 git('checkout','item141');before=logbytes();calls=trace()
 p=ok('git','cherry-pick',s2);sha=head();short=sha[:7]
 assert logbytes()==before and trace()==calls and json.loads(lock.read_text())['state']=='open'
 expected=[f'shipcraft: commit {short} (cherry-pick) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).',f'shipcraft: commit {short} would be refused by CI (test-changed): locked test tests/test_old.py changed after RED (in commit {short}); next: undo the change in tests/test_old.py; if the test looks wrong, stop and tell the RED author']
 assert [l for l in p.stderr.splitlines() if l.startswith('shipcraft: commit ')]==expected,(p.stdout,p.stderr,expected)
elif case=='cherry-green':
 t,lock=seed()
 git('checkout','-qb','side141',t);green();commit('S1');s1=head()
 git('checkout','item141');before=logbytes();calls=trace()
 p=ok('git','cherry-pick',s1);short=head()[:7]
 assert logbytes()==before and trace()==calls and json.loads(lock.read_text())['state']=='open'
 expected=[f'shipcraft: commit {short} (cherry-pick) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).',f'shipcraft: commit {short} keeps the locks\' files (the suite did not run); if the locked cases pass now, a commit through the hook closes the lock: git commit --allow-empty -m "close lock"']
 assert [l for l in p.stderr.splitlines() if l.startswith('shipcraft: commit ')]==expected,(p.stdout,p.stderr,expected)
 ok('git','commit','--allow-empty','-qm','close lock')
 assert json.loads(lock.read_text())['state']=='closed' and git('log','-1','--format=%s')=='chore(shipcraft): close lock '+lock.stem
elif case=='rebase-pick':
 t,lock=seed();oldred=head()
 git('checkout','-qb','onto141',t);write('onto141','new base');commit('onto');onto=head()
 git('checkout','item141');before=logbytes();calls=trace()
 p=ok('git','rebase','--onto',onto,t);short=head()[:7]
 assert head()!=oldred and logbytes()==before and trace()==calls
 expected=[f'shipcraft: commit {short} (rebase (pick)) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).',f'shipcraft: commit {short} keeps the locks\' files (the suite did not run); if the locked cases pass now, a commit through the hook closes the lock: git commit --allow-empty -m "close lock"']
 assert [l for l in p.stderr.splitlines() if l.startswith('shipcraft: commit ')]==expected,(p.stdout,p.stderr,expected)
elif case=='rebase-fixup':
 t,lock=seed();red=head();write('tests/test_old.py','def test_old(): assert 9==9\n');bypass('bad141')
 write('extra141','fixup product');bypass('fixup! bad141')
 editor=cw/'sequence141';write(editor,'#!/bin/sh\nexit 0\n');editor.chmod(0o755)
 before=logbytes();calls=trace()
 p=ok('git','-c','sequence.editor='+str(editor),'rebase','-i','--autosquash',red);short=head()[:7]
 assert logbytes()==before and trace()==calls
 expected=[f'shipcraft: commit {short} (rebase (fixup)) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).',f'shipcraft: commit {short} would be refused by CI (test-changed): locked test tests/test_old.py changed after RED (in commit {short}); next: undo the change in tests/test_old.py; if the test looks wrong, stop and tell the RED author']
 assert [l for l in p.stderr.splitlines() if l.startswith('shipcraft: commit ')][-2:]==expected and len([l for l in p.stderr.splitlines() if l.startswith('shipcraft: commit ')])%2==0,(p.stdout,p.stderr,expected)
elif case=='rebase-continue':
 t,lock=seed();red=head();write('conflict141','item\n');bypass('item conflict')
 git('checkout','-qb','onto141',red);write('conflict141','onto\n');bypass('onto conflict')
 git('checkout','item141');p=run('git','rebase','onto141');assert p.returncode!=0 and Path('.git/rebase-merge').is_dir()
 write('conflict141','resolved\n');write('tests/test_old.py','def test_old(): assert 11==11\n');git('add','-A')
 before=logbytes();calls=trace();p=ok('git','-c','core.editor=true','rebase','--continue');short=head()[:7]
 assert logbytes()==before and trace()==calls
 expected=[f'shipcraft: commit {short} (rebase (continue)) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).',f'shipcraft: commit {short} would be refused by CI (test-changed): locked test tests/test_old.py changed after RED (in commit {short}); next: undo the change in tests/test_old.py; if the test looks wrong, stop and tell the RED author']
 assert [l for l in p.stderr.splitlines() if l.startswith('shipcraft: commit ')]==expected,(p.stdout,p.stderr,expected)
elif case=='bypass-refused':
 t,lock=seed();write('tests/test_old.py','def test_old(): assert 12==12\n');git('add','-A')
 p=run('git','commit','-qm','refused141');assert p.returncode==1 and rows()[-1]['result']=='refused'
 before=logbytes();calls=trace();p=bypass();short=head()[:7]
 assert logbytes()==before and trace()==calls
 expected=[f'shipcraft: commit {short} (commit) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).',f'shipcraft: commit {short} would be refused by CI (test-changed): locked test tests/test_old.py changed after RED (in commit {short}); next: undo the change in tests/test_old.py; if the test looks wrong, stop and tell the RED author']
 assert [l for l in p.stderr.splitlines() if l.startswith('shipcraft: commit ')]==expected,(p.stdout,p.stderr,expected)
elif case=='close-repeat':
 t,lock=seed(both=True);red=head();write('loose141','unjudged');sha=snapshot('unjudged');short=sha[:7]
 expected=[f'shipcraft: commit {short} (fixture141) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).',f'shipcraft: commit {short} keeps the locks\' files (the suite did not run); if the locked cases pass now, a commit through the hook closes the lock: git commit --allow-empty -m "close lock"']
 before=logbytes();calls=trace();state=git('status','--porcelain')
 a=localclose();b=localclose()
 assert a.stdout.splitlines()==b.stdout.splitlines()==expected and not a.stderr+b.stderr,(a.stdout,b.stdout,expected)
 assert logbytes()==before and trace()==calls and git('status','--porcelain')==state and head()==sha
 # Broken working config and invalid mark must not obstruct the snapshot-only check.
 write('.shipcraft.toml','broken = [\n');write('.git/shipcraft/close','{invalid')
 assert localclose().stdout.splitlines()==expected
 # HEAD's per-commit guard order must include integrations and both runner settings.
 observed=[]
 for path,value,code in [
  ('lefthook-local.yml','pre-commit: {}\n','hook-config-changed'),
  ('vitest.config.ts','export default {};\n','runner-config-added'),
  ('pytest.ini','[pytest]\n','pytest-config-changed'),
  ('package.json','{"jest":{"testEnvironment":"node"}}\n','jest-config-changed')]:
  git('reset','--hard',red)
  # No untracked leftovers from another variant enter the next snapshot.
  for other in ('lefthook-local.yml','vitest.config.ts','pytest.ini','package.json','loose141'):
   Path(other).unlink(missing_ok=True)
  write(path,value);sha=snapshot('per-commit '+code);short=sha[:7]
  q=run('shipcraft','ci','--base',red);assert q.returncode==1 and rows()[-1]['code']==code,(path,q.stdout,q.stderr,rows()[-1])
  lines=(q.stdout+q.stderr).splitlines()
  what=next(l.removeprefix('shipcraft refused: ') for l in lines if l.startswith('shipcraft refused: '))
  step=next(l.removeprefix('Next: ') for l in lines if l.startswith('Next: '))
  before=logbytes();calls=trace();p=localclose()
  wanted=[f'shipcraft: commit {short} (fixture141) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).',f'shipcraft: commit {short} would be refused by CI ({code}): {what}; next: {step}']
  observed.append((p.stdout.splitlines(),wanted))
  assert p.stderr=='' and logbytes()==before and trace()==calls
 assert all(actual==wanted for actual,wanted in observed),observed
elif case=='close-failure':
 t,lock=seed();write('loose141','unjudged');snapshot('unjudged');short=head()[:7]
 target=head()
 proxy=gitproxy("if any(x in ('show','cat-file') for x in a) and any(x.startswith("+repr(target+":.shipcraft/locks")+") for x in a):\n print('fatal: read141 failed',file=sys.stderr);sys.exit(73)")
 # Confirm the obstruction is on the real object-reading path before testing close.
 p=run(proxy,'show',target+':'+str(lock));assert p.returncode==73 and 'read141 failed' in p.stderr
 before=logbytes();calls=trace();p=localclose()
 assert len(notices(p))==2 and notices(p)[1].startswith(f'shipcraft: commit {short} could not be checked (') and notices(p)[1].endswith('); CI checks it'),p.stdout
 assert logbytes()==before and trace()==calls
elif case=='close-format':
 t,lock=seed()
 # Obtain the unsupported-format snapshot without editing the real lock pathname.
 raw=json.loads(lock.read_text());raw['format']=999
 tmp=cw/'future141.json';tmp.write_text(json.dumps(raw))
 blob=git('hash-object','-w',tmp);git('update-index','--cacheinfo','100644,'+blob+','+str(lock))
 tree=git('write-tree');sha=git('commit-tree',tree,'-p',head(),'-m','future lock')
 git('update-ref','-m','fixture141: future','HEAD',sha);short=sha[:7]
 q=run('shipcraft','ci','--base',sha+'^');assert q.returncode==1 and rows()[-1]['code']=='lock-format',(q.stdout,q.stderr)
 lines=(q.stdout+q.stderr).splitlines()
 what=next(l.removeprefix('shipcraft refused: ') for l in lines if l.startswith('shipcraft refused: '))
 step=next(l.removeprefix('Next: ') for l in lines if l.startswith('Next: '))
 before=logbytes();calls=trace();p=localclose()
 expected=[f'shipcraft: commit {short} (fixture141) was not judged by the hook, with lock {lock.stem}, unknown open; checking it now against the locks, without the suite (CI judges it in full).',f'shipcraft: commit {short} would be refused by CI (lock-format): {what}; next: {step}']
 assert p.stdout.splitlines()==expected and p.stderr=='',(p.stdout,expected)
 assert logbytes()==before and trace()==calls
elif case=='close-action':
 t,lock=seed();write('loose141','unjudged');snapshot('unjudged');short=head()[:7]
 reflog=Path(git('rev-parse','--git-path','logs/HEAD'))
 raw=reflog.read_bytes();prefix=raw.rsplit(b'\t',1)[0]
 reflog.write_bytes(prefix+b'\tcustom\x01\x7f: detail\n')
 p=localclose()
 expected=f'shipcraft: commit {short} (custom  ) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).'
 assert notices(p)[:1]==[expected],p.stdout
 reflog.unlink();q=localclose()
 assert notices(q)[:1]==[expected.replace('(custom  )','(unknown)')],q.stdout
elif case=='sha256':
 original=Path.cwd();root=cw/'sha256141';root.mkdir();os.chdir(root)
 git('init','-q','--object-format=sha256','-b','main');git('config','user.name','RED141');git('config','user.email','red141@example.invalid')
 write('.gitignore','.venv/\n__pycache__/\n.pytest_cache/\n')
 (root/'.venv').symlink_to(original/'.venv',target_is_directory=True)
 write('requirements.txt','pytest\n');ok('shipcraft','init','--lang','python');commit('init SHA256')
 t,lock=seed();parent=head();r=rows()[-1];tree=git('rev-parse','HEAD^{tree}');previous=git('rev-parse','HEAD^')
 write('tests/test_old.py','# changed256\n');p=bypass();short=head()[:7]
 assert [l for l in p.stderr.splitlines() if l.startswith('shipcraft: commit ')][-1:]==[f'shipcraft: commit {short} would be refused by CI (test-changed): locked test tests/test_old.py changed after RED (in commit {short}); next: undo the change in tests/test_old.py; if the test looks wrong, stop and tell the RED author'],(p.stdout,p.stderr)
 assert len(tree)==64 and r.get('tree')==tree and r['commit']==previous,r
elif case=='parent-lock':
 t,lock=seed();git('rm','--cached',str(lock))
 tree=git('write-tree');sha=git('commit-tree',tree,'-p',head(),'-m','removed lock');git('update-ref','-m','fixture141: removed lock','HEAD',sha);short=sha[:7]
 q=run('shipcraft','ci','--base',sha+'^');assert q.returncode==1 and rows()[-1]['code']=='lock-deleted',(q.stdout,q.stderr)
 lines=(q.stdout+q.stderr).splitlines()
 what=next(l.removeprefix('shipcraft refused: ') for l in lines if l.startswith('shipcraft refused: '))
 step=next(l.removeprefix('Next: ') for l in lines if l.startswith('Next: '))
 before=logbytes();calls=trace()
 p=localclose()
 expected=[f'shipcraft: commit {short} (fixture141) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).',f'shipcraft: commit {short} would be refused by CI (lock-deleted): {what}; next: {step}']
 assert p.stdout.splitlines()==expected and not p.stderr and logbytes()==before and trace()==calls,(p.stdout,expected)
elif case=='reader-evidence':
 t,lock=seed();parent=head();write('loose141','unjudged');snapshot('unjudged')
 saved=rows();append_rows([evidence(parent,branch='some-other-branch141')])
 assert localclose().stdout=='','exact tree and parent must count'
 save_rows(saved);append_rows([evidence(parent,tree=git('rev-parse',parent+'^{tree}'))])
 p=localclose();short=head()[:7]
 assert notices(p)[:1]==[f'shipcraft: commit {short} (fixture141) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).'],p.stdout
elif case=='reader-amend':
 t,lock=seed();parent=head();write('loose141','first');original=snapshot('original')
 write('loose141','amended');tree=git('write-tree') # stage the amendment explicitly below
 git('add','-A');tree=git('write-tree');sha=git('commit-tree',tree,'-p',parent,'-m','rewritten');git('update-ref','HEAD',sha)
 saved=rows();append_rows([evidence(original,tree=tree)])
 assert localclose().stdout=='','amend row should count by first parent'
 save_rows(saved);append_rows([evidence(t,tree=tree)])
 p=localclose()
 assert len(notices(p))==2 and 'was not judged by the hook' in notices(p)[0],p.stdout
elif case=='reader-invalid':
 t,lock=seed();parent=head();write('loose141','unjudged');snapshot('unjudged');short=head()[:7]
 good=evidence(parent);saved=rows();observed=[]
 for bad in [dict(good,result='refused'),dict(good,result='error'),dict(good,layer='ci'),dict(good,tree=None),dict(good,commit=7),dict(good,layer=7),dict(good,result=True),dict(good,commit='f'*40),dict(layer='close',result='refused',commit=head()),[],None]:
  save_rows(saved);append_rows([bad]);p=localclose();observed.append(p.stdout)
 expected=f'shipcraft: commit {short} (fixture141) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).'
 assert all(x.splitlines()[:1]==[expected] for x in observed),observed
 logpath().unlink();logpath().mkdir()
 p=localclose()
 assert p.stdout.splitlines()[:1]==[expected] and logpath().is_dir(),p.stdout
elif case=='status-range':
 t,lock=seed();cutoff()
 for i in range(7):write('counter141',str(i));snapshot('counter '+str(i))
 write('.shipcraft.toml',Path('.shipcraft.toml').read_text().replace('.venv/bin/python','python3'))
 before=logbytes();calls=trace();state=git('status','--porcelain');p=ok('shipcraft','status')
 ids=git('rev-list','--topo-order',t+'..HEAD').splitlines()[:-1]
 expected=f'shipcraft: commits with a lock open that the hook did not judge: 7 ({", ".join(x[:7] for x in ids[:5])} and 2 more); shipcraft ci --base main judges them'
 assert statuslines(p)==[expected],(p.stdout,expected)
 assert p.stdout.index('shipcraft: open locks:')<p.stdout.index(expected)
 assert p.stdout.index('shipcraft: suite . runs python3 from PATH')<p.stdout.index(expected)
 assert logbytes()==before and trace()==calls and git('status','--porcelain')==state
elif case=='status-cutoff':
 t,lock=seed();red=head()
 legacy=[{k:v for k,v in r.items() if k!='tree'} for r in rows()];save_rows(legacy)
 write('counter141','unjudged');sha=snapshot('dated');date=int(git('show','-s','--format=%ct',sha))
 assert not statuslines(ok('shipcraft','status')),'legacy-only log establishes no cutoff'
 append_rows([dict(layer='red',result='passed',commit='',tree='',at=value) for value in (-1,True,'0',None)])
 assert not statuslines(ok('shipcraft','status')),'wrong at types cannot establish a cutoff'
 append_rows([dict(layer='anything',result='anything',commit='',tree='',at=date+1)])
 assert not statuslines(ok('shipcraft','status')),'before cutoff stays unnamed'
 append_rows([dict(layer='anything',result='anything',commit='',tree='',at=date),dict(evidence(git('rev-parse',red+'^'),tree=git('rev-parse',red+'^{tree}')),at=date)])
 p=ok('shipcraft','status')
 expected=f'shipcraft: commits with a lock open that the hook did not judge: 1 ({sha[:7]}); shipcraft ci --base main judges them'
 assert statuslines(p)==[expected],(p.stdout,expected)
elif case=='status-reader':
 t,lock=seed();cutoff();parent=head();write('counter141','unjudged');sha=snapshot('reader');saved=logbytes()
 # Malformed/BOM lines and wrong cutoff types never hide a later valid row.
 logpath().write_bytes(b'\xef\xbb\xbf'+json.dumps(evidence(parent)).encode()+b'\n'+saved+b'{broken\n[]\nnull\n')
 append_rows([dict(tree='',at=-1),dict(tree='',at=True),dict(tree='',at='0'),dict(evidence(parent),result='refused'),dict(evidence(parent),tree=7)])
 before=logbytes();p=ok('shipcraft','status')
 expected=f'shipcraft: commits with a lock open that the hook did not judge: 1 ({sha[:7]}); shipcraft ci --base main judges them'
 assert statuslines(p)==[expected] and logbytes()==before,(p.stdout,expected)
 append_rows([evidence(parent)]);assert not statuslines(ok('shipcraft','status'))
elif case=='status-parents':
 t,lock=seed();cutoff();red=head()
 green();git('add','textutil.py');ok('shipcraft','check')
 write('unjudged-closing141','after the judged tree')
 # check supplies correctly closed bytes; a bypassed closing snapshot has an open parent.
 sha=snapshot('closed but unjudged');assert json.loads(lock.read_text())['state']=='closed'
 p=ok('shipcraft','status')
 expected=f'shipcraft: commits with a lock open that the hook did not judge: 1 ({sha[:7]}); shipcraft ci --base main judges them'
 assert statuslines(p)==[expected],(p.stdout,expected)
 # A close row is sufficient, without any tree key.
 append_rows([dict(layer='close',result='passed',commit=sha,at=0)])
 assert not statuslines(ok('shipcraft','status'))
elif case=='status-common':
 t,lock=seed();cutoff();parent=head();write('counter141','unjudged');sha=snapshot('common')
 original=Path.cwd();wt=cw/'linked141';git('worktree','add','-qb','linked141',wt);common=logpath().resolve()
 os.chdir(wt);(wt/'.venv').symlink_to(original/'.venv',target_is_directory=True)
 before=common.read_bytes();p=ok('shipcraft','status')
 expected=f'shipcraft: commits with a lock open that the hook did not judge: 1 ({sha[:7]}); shipcraft ci --base main judges them'
 assert statuslines(p)==[expected] and common.read_bytes()==before,(p.stdout,expected)
 append_rows([evidence(parent)]);assert not statuslines(ok('shipcraft','status'))
elif case=='status-am':
 t,lock=seed();cutoff();red=head()
 git('checkout','-qb','mail141',red);write('mail141','patch');snapshot('mail patch');patch=git('format-patch','-1','--stdout')
 git('checkout','item141');before=logbytes();calls=trace()
 p=subprocess.run(['git','am'],input=patch,text=True,capture_output=True)
 print('git am stdout:',p.stdout,'stderr:',p.stderr,flush=True)
 assert p.returncode==0 and not notices(p) and logbytes()==before and trace()==calls
 sha=head();q=ok('shipcraft','status')
 expected=f'shipcraft: commits with a lock open that the hook did not judge: 1 ({sha[:7]}); shipcraft ci --base main judges them'
 assert statuslines(q)==[expected],(q.stdout,expected)
elif case=='status-shallow':
 t,lock=seed();cutoff();red=head();original=Path.cwd()
 clone=cw/'shallow141';git('clone','-q','--depth=1','--branch','item141',original.as_uri(),clone)
 os.chdir(clone);(clone/'.venv').symlink_to(original/'.venv',target_is_directory=True)
 git('update-ref','refs/remotes/origin/main',red);git('symbolic-ref','refs/remotes/origin/HEAD','refs/remotes/origin/main')
 # Give the range a descendant; the boundary's exact hook row must not turn it into a root.
 git('config','user.name','RED141');git('config','user.email','red141@example.invalid')
 write('shallow141','descendant');sha=snapshot('shallow descendant')
 git('update-ref','refs/remotes/origin/main',sha);git('update-ref','refs/heads/main',red)
 # A shallow boundary must not match a root-style row, even with the same tree.
 git('reset','--hard',red)
 save_rows([evidence('',tree=git('rev-parse','HEAD^{tree}'))])
 empty=cw/'empty141';empty.write_text('')
 emptytree=git('hash-object','-t','tree','-w',empty)
 base=git('commit-tree',emptytree,'-m','unrelated base')
 git('update-ref','refs/remotes/origin/main',base)
 p=ok('shipcraft','status')
 expected=f'shipcraft: commits with a lock open that the hook did not judge: 1 ({red[:7]}); shipcraft ci --base origin/main judges them'
 assert statuslines(p)==[expected],(p.stdout,expected)
 p=localclose()
 assert len(notices(p))==2 and 'could not be checked (' in notices(p)[1] and notices(p)[1].endswith('); CI checks it'),p.stdout
elif case=='status-origin':
 t,lock=seed();cutoff();red=head();write('counter141','one');a=snapshot('one')
 write('counter141','two');b=snapshot('two')
 git('update-ref','refs/remotes/origin/main',a);git('symbolic-ref','refs/remotes/origin/HEAD','refs/remotes/origin/main')
 p=ok('shipcraft','status')
 expected=f'shipcraft: commits with a lock open that the hook did not judge: 1 ({b[:7]}); shipcraft ci --base origin/main judges them'
 assert statuslines(p)==[expected],(p.stdout,expected)
 git('update-ref','-d','refs/remotes/origin/main');q=ok('shipcraft','status')
 expected=f'shipcraft: commits with a lock open that the hook did not judge: 2 ({b[:7]}, {a[:7]}); shipcraft ci --base main judges them'
 assert statuslines(q)==[expected],(q.stdout,expected)
elif case=='pr-off':
 t,lock=seed(ci='off');cutoff();remote(t);write('counter141','unjudged');sha=snapshot('PR off')
 before=trace();p=pr()
 expected=f'shipcraft: warning: 1 commit(s) on item141 were made with a lock open and the hook did not judge them ({sha[:7]}); CI is off ([execution] ci), so nothing re-checks them; check them: shipcraft ci --base origin/main'
 assert p.returncode==0 and warninglines(p)==[expected],(p.returncode,p.stdout,p.stderr,expected)
 assert p.stdout.index(expected)<p.stdout.index('published to origin') and trace()==before
 assert git('--git-dir='+str(cb/'origin141.git'),'rev-parse','item141')==sha
 assert all('hook did not judge them' not in f.read_text() for f in (logpath(),st/'statuses.jsonl',st/'prs.json',st/'comments.jsonl') if f.is_file())
elif case=='pr-local':
 t,lock=seed(ci='local');cutoff();remote(t);green();write('counter141','unjudged');sha=snapshot('PR local')
 p=pr()
 expected=f'shipcraft: warning: 1 commit(s) on item141 were made with a lock open and the hook did not judge them ({sha[:7]}); shipcraft/ci re-checks every commit of the PR; to check them first: shipcraft ci --base origin/main'
 assert warninglines(p)==[expected],(p.stdout,p.stderr,expected)
 assert p.stdout.index(expected)<p.stdout.index('published to origin') and p.returncode!=0
 assert any(r['layer']=='ci' and r['result']=='refused' for r in rows())
elif case=='pr-github':
 t,lock=seed(ci='github');cutoff();remote(t);write('counter141','unjudged');sha=snapshot('PR github')
 before=trace();p=pr()
 expected=f'shipcraft: warning: 1 commit(s) on item141 were made with a lock open and the hook did not judge them ({sha[:7]}); shipcraft/ci re-checks every commit of the PR; to check them first: shipcraft ci --base origin/main'
 assert p.returncode==0 and warninglines(p)==[expected],(p.returncode,p.stdout,p.stderr,expected)
 assert p.stdout.index(expected)<p.stdout.index('published to origin') and trace()==before
 assert not any(r['layer']=='ci' for r in rows())
elif case=='pr-push-fails':
 t,lock=seed(ci='off');cutoff();remote(t);write('counter141','unjudged');sha=snapshot('PR failing push')
 proxy=gitproxy("if 'push' in a:\n print('fatal: push141 failed',file=sys.stderr);sys.exit(73)")
 p=pr()
 expected=f'shipcraft: warning: 1 commit(s) on item141 were made with a lock open and the hook did not judge them ({sha[:7]}); CI is off ([execution] ci), so nothing re-checks them; check them: shipcraft ci --base origin/main'
 assert p.returncode==2 and 'push141 failed' in p.stderr and warninglines(p)==[expected],(p.returncode,p.stdout,p.stderr,expected)
 assert not any(r['layer']=='pr' for r in rows())
 assert run('git','--git-dir='+str(cb/'origin141.git'),'rev-parse','--verify','refs/heads/item141').returncode!=0
elif case=='pr-later-fails':
 t,lock=seed(ci='off');cutoff();remote(t);write('counter141','unjudged');sha=snapshot('PR late failure')
 # Standard gh stub remains the only GitHub implementation; fail its comment call.
 gh=cb/'gh';saved=cb/'gh141-real';gh.rename(saved)
 write(gh,'#!'+sys.executable+'\nimport os,sys\na=sys.argv[1:]\nif a[:2]==["pr","comment"] or (a[:1]==["api"] and any("/comments" in x for x in a) and any(x in ("POST","-f","-F","--input") for x in a)):\n os.environ["SHIPCRAFT_STUB_FAIL"]="1"\nos.execv('+repr(str(saved))+',['+repr(str(saved))+',*a])\n');gh.chmod(0o755)
 p=pr()
 expected=f'shipcraft: warning: 1 commit(s) on item141 were made with a lock open and the hook did not judge them ({sha[:7]}); CI is off ([execution] ci), so nothing re-checks them; check them: shipcraft ci --base origin/main'
 assert p.returncode==2 and warninglines(p)==[expected],(p.returncode,p.stdout,p.stderr,expected)
 assert git('--git-dir='+str(cb/'origin141.git'),'rev-parse','item141')==sha
 assert any(r['layer']=='pr' and r['result']=='error' for r in rows())
elif case=='pr-cap':
 t,lock=seed(ci='off');cutoff();remote(t)
 for i in range(6):write('counter141',str(i));snapshot('PR counter '+str(i))
 ids=git('rev-list','--topo-order','origin/main..HEAD').splitlines()[:-1]
 p=pr()
 expected=f'shipcraft: warning: 6 commit(s) on item141 were made with a lock open and the hook did not judge them ({", ".join(x[:7] for x in ids[:5])} and 1 more); CI is off ([execution] ci), so nothing re-checks them; check them: shipcraft ci --base origin/main'
 assert p.returncode==0 and warninglines(p)==[expected],(p.returncode,p.stdout,p.stderr,expected)
elif case=='control-fixture':
 t,lock=seed(both=True);d=json.loads(lock.read_text())
 assert ' # vitest jest' in tomllib.loads(Path('.shipcraft.toml').read_text())['test_command']
 assert d['failing_at_red']==['tests.test_slug::test_slug'] and 'tests/test_old.py' in d['files'],d
 assert trace().count(b'pytest141\n')>=3,trace()
 red=head()
 for path,value,code in [
  ('lefthook-local.yml','pre-commit: {}\n','hook-config-changed'),
  ('vitest.config.ts','export default {};\n','runner-config-added'),
  ('pytest.ini','[pytest]\n','pytest-config-changed'),
  ('package.json','{"jest":{"testEnvironment":"node"}}\n','jest-config-changed')]:
  write(path,value);snapshot('control '+code);calls=trace()
  q=run('shipcraft','ci','--base',red)
  assert q.returncode==1 and rows()[-1]['code']==code and trace()==calls,(path,q.stdout,q.stderr,rows()[-1])
  git('reset','--hard',red)
 green();p=commit('ordinary GREEN141')
 assert json.loads(lock.read_text())['state']=='closed'
 assert git('log','-1','--format=%s')=='chore(shipcraft): close lock '+lock.stem and not notices(p)
 assert rows()[-1]['layer']=='close' and rows()[-1]['commit']==head()
 assert localclose().stdout==''
elif case=='control-judged':
 t,lock=seed();before=trace();write('ordinary141','one');p=commit('ordinary141');assert not notices(p)
 p=ok('git','commit','--amend','--no-edit');assert not notices(p)
 git('checkout','-qb','merge141',t);write('merge141','branch');commit('merge side')
 git('checkout','item141');p=ok('git','merge','--no-ff','--no-edit','merge141')
 assert len(git('show','-s','--format=%P','HEAD').split())==2 and not notices(p)
 assert localclose().stdout=='' and json.loads(lock.read_text())['state']=='open' and len(trace())>len(before)
 # reword uses commit-msg; its hook sees the old rewritten commit as HEAD.
 write('reword141','one');commit('to reword141')
 editor=cw/'reword-editor';write(editor,'#!/bin/sh\nprintf "reworded141\\n" > "$1"\n');editor.chmod(0o755)
 seq=cw/'reword-sequence';write(seq,'#!/bin/sh\nsed "s/^pick /reword /" "$1" > "$1.tmp" && mv "$1.tmp" "$1"\n');seq.chmod(0o755)
 p=ok('git','rebase','-i','HEAD^',env=dict(os.environ,GIT_EDITOR=str(editor),GIT_SEQUENCE_EDITOR=str(seq)))
 assert git('log','-1','--format=%s')=='reworded141' and not notices(p),p.stdout
elif case=='control-root':
 original=Path.cwd();root=cw/'root141';root.mkdir();os.chdir(root)
 git('init','-q','-b','main');git('config','user.name','RED141');git('config','user.email','red141@example.invalid')
 write('.gitignore','.venv/\n__pycache__/\n.pytest_cache/\n')
 (root/'.venv').symlink_to(original/'.venv',target_is_directory=True)
 write('requirements.txt','pytest\n');ok('shipcraft','init','--lang','python')
 write('value141','red');write('tests/test_root141.py','from pathlib import Path\ndef test_root141(): assert Path("value141").read_text()=="green"\n')
 git('add','-A');ok('shipcraft','red');p=commit('root RED141')
 assert git('rev-list','--count','HEAD')=='1' and not notices(p)
 assert rows()[-1]['layer']=='hook' and rows()[-1]['commit']=='' and localclose().stdout==''
elif case=='control-no-lock':
 # No lock makes even an unjudged plumbing commit silent, with no rows.
 write('counter141','unbound');sha=snapshot('no lock');before=logbytes()
 p=localclose();assert p.stdout==p.stderr=='' and head()==sha and logbytes()==before
 assert not statuslines(ok('shipcraft','status'))
 # A legacy repository without root config is also silent despite a real open lock.
 t,lock=seed();git('rm','--cached','.shipcraft.toml')
 tree=git('write-tree');sha=git('commit-tree',tree,'-p',head(),'-m','remove config');git('update-ref','HEAD',sha)
 tree=git('rev-parse','HEAD^{tree}');sha=git('commit-tree',tree,'-p',sha,'-m','neither snapshot has config');git('update-ref','HEAD',sha)
 assert localclose().stdout==''
elif case=='control-mark':
 t,lock=seed();green();git('add','textutil.py');ok('shipcraft','check','--commit-msg','unused')
 mark=Path(git('rev-parse','--git-path','shipcraft/close'));assert mark.is_file()
 # Move via plumbing to a different tree: existing stale-mark line owns this call.
 write('different141','after judgment');sha=snapshot('different tree');before=logbytes();p=localclose()
 assert mark.exists()==False and head()==sha and json.loads(lock.read_text())['state']=='open'
 assert len((p.stdout+p.stderr).strip().splitlines())==1 and 'open' in p.stdout+p.stderr and not notices(p),(p.stdout,p.stderr)
 assert logbytes()==before
elif case=='control-legacy':
 t,lock=seed();legacy=[{k:v for k,v in r.items() if k!='tree'} for r in rows()];save_rows(legacy)
 write('counter141','unjudged');snapshot('legacy only');before=logbytes()
 assert not statuslines(ok('shipcraft','status')) and logbytes()==before
 # A resolvable base is mandatory, even with a valid cutoff and unjudged history.
 cutoff();git('update-ref','-d','refs/heads/main');p=ok('shipcraft','status')
 assert not statuslines(p) and 'branch item141' in p.stdout
elif case=='control-pr':
 t,lock=seed(ci='off');remote(t);write('counter141','judged');commit('ordinary PR141');sha=head();before=trace()
 p=pr();assert p.returncode==0 and not warninglines(p),(p.returncode,p.stdout,p.stderr)
 assert git('--git-dir='+str(cb/'origin141.git'),'rev-parse','item141')==sha and trace()==before
 prs=json.loads((st/'prs.json').read_text());assert prs['1']['title']=='Item141' and prs['1']['headRefName']=='item141',prs
 # Exercise the same comment-failure delegate as pr-later-fails and the stub's failure switch.
 gh=cb/'gh';saved=cb/'gh141-real';gh.rename(saved)
 write(gh,'#!'+sys.executable+'\nimport os,sys\na=sys.argv[1:]\nif a[:2]==["pr","comment"] or (a[:1]==["api"] and any("/comments" in x for x in a) and any(x in ("POST","-f","-F","--input") for x in a)):\n os.environ["SHIPCRAFT_STUB_FAIL"]="1"\nos.execv('+repr(str(saved))+',['+repr(str(saved))+',*a])\n');gh.chmod(0o755)
 p=pr();assert p.returncode==2 and not warninglines(p) and any(r['layer']=='pr' and r['result']=='error' for r in rows()),(p.returncode,p.stdout,p.stderr)
elif case=='control-git':
 t,lock=seed();target=head()
 proxy=gitproxy("if ('show' in a and any(x.startswith("+repr(target+":.shipcraft/locks")+") for x in a)) or 'push' in a:\n print('fatal: proxy141 controlled',file=sys.stderr);sys.exit(73)")
 p=run(proxy,'show',target+':'+str(lock));assert p.returncode==73 and p.stderr=='fatal: proxy141 controlled\n'
 assert git('rev-parse','HEAD')==target and git('show','HEAD:tests/test_old.py')=='def test_old(): assert 3+3==6'
 p=run(proxy,'push');assert p.returncode==73 and p.stderr=='fatal: proxy141 controlled\n'
 assert localclose().stdout=='' and json.loads(lock.read_text())['state']=='open'
else:raise AssertionError('unrouted case: '+case)
PY141
  pass
}
