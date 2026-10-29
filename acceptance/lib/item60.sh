# Item 60: public commands, real pytest reports, Git confined to each temporary project.
item60_langs() { echo core; }
item60_cases() {
  local c
  for c in main lock-only growth unchanged all no-base bad-base deleted moved no-owner monorepo overlap drops filter build-fails check-fails write-fails log-fails without-lock; do echo "v1-60.$c"; done
}
item60_case() {
  EXPECT="item 60: ${CASE#v1-60.}"
  v1_start
  must_accept 'item 60 black box contract' cmd "$PY" - "${CASE#v1-60.}" "$(command -v shipcraft)" <<'PY60'
import hashlib,json,os,shlex,subprocess,sys
from pathlib import Path
mode,binary=sys.argv[1:]
project=Path('item60-project'); project.mkdir(); os.chdir(project)
errors=[]
def want(value,message):
 if not value: errors.append(message)
def write(path,text):
 p=Path(path); p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text)
def run(*args,ok=True):
 p=subprocess.run(args,capture_output=True,text=True,timeout=90)
 print('$',shlex.join(args),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 if ok: assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr)
 return p
def git(*args): return run('git',*args).stdout.strip()
def commit(msg):
 git('add','-A'); git('-c','core.hooksPath=/dev/null','commit','-qm',msg)
def rows():
 p=Path('.git/shipcraft/runs.jsonl')
 return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def locks(): return sorted(Path('.shipcraft/locks').glob('*.json'))
def marker(name): return str(Path('../'+name).resolve())
def test(path,names,mark=None):
 s='from pathlib import Path\n'
 if mark: s+='Path('+repr(marker(mark))+').open("a").write("ran\\n")\n'
 for name,passing in names:
  s+='\ndef test_'+name+'():\n    assert '+str(passing)+'\n'
 write(path,s)
def config(suites):
 s='shipcraft_min = "0.0"\nlang = "python"\nrunner = "pytest"\n[execution]\nci = "local"\nreview = "off"\n[build]\ncommand = '+json.dumps('test ! -f '+shlex.quote(marker('build-fail')))+'\n'
 for name,root in suites:
  command='pytest --junitxml={junit} tests'
  if mode=='filter': command+=' -k "$ITEM60_FILTER"'
  s+='\n[[suite]]\n'+('name = '+json.dumps(name)+'\n' if name is not None else '')+'root = '+json.dumps(root)+'\ncommand = '+json.dumps(command)+'\nglobs = ["tests/**"]\ncheck = '+json.dumps('echo checked >> '+shlex.quote(marker('check-'+str(name)))+'; test ! -f '+shlex.quote(marker('check-fail' if mode!='check-fails' or name=='jobs' else 'check-never-fail')))+'\n'
 write('.shipcraft.toml',s)
def event(p,reason=None,n=1,code=''):
 rs=rows(); want(len(rs)==before_rows+1,'redo must append exactly one row')
 r=rs[-1]
 want(all(k in r for k in ('selection','selected_files','fallback')),'redo row omitted selection fields')
 want(r.get('redo') is True,'missing redo:true')
 want(r.get('code')==code,'wrong refusal code: '+repr(r))
 want(r.get('layer')=='red' and r.get('result')==('refused' if code else 'passed') and r.get('lock')==lock.stem,'wrong redo event identity/status: '+repr(r))
 expected=('all',0,reason) if reason else ('changed',n,None)
 want(tuple(r.get(k) for k in ('selection','selected_files','fallback'))==expected,'selection fields: '+repr(r))
 if reason: line='shipcraft: red ran every suite: '+reason
 else:
  # Protection includes every configured suite file and config, even files never run.
  protected={'.shipcraft.toml'}
  for _,root in suites:
   protected.update(str(f) for f in Path(root,'tests').glob('*') if f.is_file())
  line=f'shipcraft: red ran the changed test files: {n} of {len(protected)}'
 want((p.stdout+p.stderr).count(line)==1,'missing/duplicate selection notice: '+line)

git('init','-q','-b','main'); git('config','user.name','RED 60'); git('config','user.email','red60@example.invalid')
write('.gitignore','__pycache__/\n.pytest_cache/\n')
suites=[(None,'.')]
if mode in ('monorepo','check-fails','all'): suites=[('api','core'),('jobs','jobs')]
if mode=='overlap': suites=[('api','.'),('api:jobs','.')]
if mode=='no-owner': suites=[('former','.')]
config(suites)
roots=sorted({root for _,root in suites})
for root in roots:
 test(root+'/tests/test_legacy60.py',[('legacy60',False)],'legacy-'+root.replace('/','_'))
commit('test: base has unrelated failing files')
# A real origin and origin/HEAD, confined to this case's temporary project.
origin=Path('../origin60.git').resolve()
run('git','init','-q','--bare',str(origin)); run('git','--git-dir='+str(origin),'symbolic-ref','HEAD','refs/heads/main')
git('remote','add','origin',str(origin)); git('push','-q','origin','main'); git('fetch','-q','origin'); git('remote','set-head','origin','main')
git('checkout','-qb','feature/item60')
if mode=='without-lock':
 before_rows=len(rows()); p=run(binary,'red','--redo',ok=False)
 want(p.returncode==1,'redo without lock must refuse')
 rs=rows(); want(len(rs)==before_rows+1,'early refusal row missing')
 r=rs[-1]; want(r.get('code')=='redo-without-lock' and r.get('redo') is True,'early refusal fields: '+repr(r))
 want(all(k not in r for k in ('selection','selected_files','fallback')),'early refusal has selection fields')
 assert not locks(),'early refusal wrote lock'
 assert not errors,'\n'.join(errors)
 sys.exit()
active='core' if mode in ('monorepo','check-fails','all') else '.'
anchor=str(Path(active,'tests/test_anchor60.py'))
test(anchor,[('repair60',False),('remain60',False),('keep60',True)])
if mode=='lock-only': test(active+'/tests/test_passing60.py',[('passing60',True)])
os.environ['ITEM60_FILTER']=''
initial=run(binary,'red'); lock=locks()[0]; old=json.loads(lock.read_text())
assert len(old['cases'])==(6 if mode=='overlap' else 4 if mode=='lock-only' else 3),old
assert ('shipcraft: red ran the changed test files: '+('2' if mode=='lock-only' else '1')+' of') in initial.stdout+initial.stderr,initial
commit('test: committed narrow RED')
oldbytes=lock.read_bytes(); oldstat=lock.stat()
for root in roots: Path(marker('legacy-'+root.replace('/','_'))).unlink(missing_ok=True)
for name,_ in suites: Path(marker('check-'+str(name))).unlink(missing_ok=True)
reason=None; n=2 if mode=='lock-only' else 1; code=''; args=[]
if mode not in ('unchanged','drops','filter','deleted','moved','no-owner'):
 test(anchor,[('repair60',True),('remain60',False),('keep60',True)])
if mode=='lock-only':
 # Neither tracked nor untracked changed paths select tests; the lock alone must select one.
 git('update-ref','refs/remotes/origin/main','HEAD')
 # Restore the committed test bytes so even the repair is not a changed path.
 git('checkout','HEAD','--',anchor)
if mode=='growth':
 test(active+'/tests/test_added60.py',[('added60',False),('new_pass60',True)]); n=2
if mode=='all': args=['--all']; reason='--all'
if mode=='no-base': git('symbolic-ref','--delete','refs/remotes/origin/HEAD'); reason='no base'
if mode=='bad-base': args=['--base','nonexisting60']; reason='no base'
if mode in ('deleted','moved'):
 # The anchor was absent at base, so protected-file-removed must not mask lock mapping.
 Path(anchor).unlink()
 if mode=='moved': test(active+'/tests/test_moved60.py',[('repair60',False),('remain60',False),('keep60',True)])
 reason='case without file'; code='redo-drops-case'
if mode=='no-owner':
 suites=[('replacement','.')]; config(suites)
 commit('chore: suite renamed in fixture'); git('update-ref','refs/remotes/origin/main','HEAD')
 reason='case without file'; code='redo-drops-case'
if mode=='drops': test(anchor,[('repair60',False),('remain60',False)]); code='redo-drops-case'
if mode=='filter': os.environ['ITEM60_FILTER']='not keep60'; code='redo-drops-case'
if mode=='build-fails': Path(marker('build-fail')).touch(); code='build-failed'
if mode=='check-fails': Path(marker('check-fail')).touch(); code='no-report'
if mode=='write-fails':
 lock.parent.chmod(0o555); code='redo-write-failed'
if mode=='log-fails':
 log=Path('.git/shipcraft/runs.jsonl'); log.unlink(); log.mkdir()
before_rows=len(rows())
try: p=run(binary,'red','--redo',*args,ok=False)
finally:
 if mode=='write-fails': lock.parent.chmod(0o755)
want(p.returncode==(1 if code else 0),'wrong redo exit: '+str(p.returncode))
if mode!='log-fails': event(p,reason,n,code)
else:
 want('shipcraft: red ran the changed test files: 1 of 3' in p.stdout+p.stderr,'failed log append lost narrowed notice')
if code:
 want(lock.read_bytes()==oldbytes,'refusal changed lock bytes')
 if mode=='check-fails':
  for name,_ in suites: want(Path(marker('check-'+str(name))).read_text()=='checked\n','later suite check did not run exactly once')
 if code=='redo-drops-case':
  missing=set(old['cases'])
  if mode in ('drops','filter'): missing={c for c in missing if 'keep60' in c}
  want(all(c in p.stdout+p.stderr for c in missing),'refusal did not name dropped identities')
else:
 d=json.loads(lock.read_text()); want(locks()==[lock],'redo changed lock path/id')
 expected=set(old['cases'])
 if mode=='growth': expected|={'tests.test_added60::test_added60','tests.test_added60::test_new_pass60'}
 if reason:
  for name,root in suites: expected.add((name+':' if name else '')+'tests.test_legacy60::test_legacy60')
 want(set(d['cases'])==expected,'unexpected lock growth: '+repr(d['cases']))
 want(set(old['cases'])<=set(d['cases']),'lock dropped cases')
 for path,h in d['files'].items(): want(h=='sha256:'+hashlib.sha256(Path(path).read_bytes()).hexdigest(),'bad protected hash: '+path)
 if mode=='unchanged':
  want(lock.read_bytes()==oldbytes,'unchanged redo wrote different bytes')
  want((lock.stat().st_ino,lock.stat().st_mtime_ns)==(oldstat.st_ino,oldstat.st_mtime_ns),'unchanged redo replaced or wrote lock')
  want(any(s in (p.stdout+p.stderr).lower() for s in ('nothing','unchanged','no changes')),'missing unchanged notice')
 elif mode!='lock-only':
  want(all('repair60' not in c for c in d['failing_at_red']),'fixed test still failing at RED')
  want(any('remain60' in c for c in d['failing_at_red']),'remaining RED failure lost')
 if not reason:
  want(all(not Path(marker('legacy-'+root.replace('/','_'))).exists() for root in roots),'untouched failing file ran')
 if mode in ('monorepo','overlap','all'):
  for name,_ in suites: want(Path(marker('check-'+str(name))).read_text()=='checked\n','suite check skipped or repeated: '+str(name))
  if mode=='overlap': want({c.split(':tests.')[0] for c in d['cases']}=={'api','api:jobs'},'overlapping file not selected for each owning suite')
  if mode=='all': want(Path(marker('legacy-jobs')).exists(),'--all did not run other suite')
if mode=='growth' and not errors:
 # Once admitted, new cases must also survive a later redo with no changed paths.
 commit('test: redo lock grew'); git('update-ref','refs/remotes/origin/main','HEAD')
 grown=lock.read_bytes(); before_rows=len(rows())
 p=run(binary,'red','--redo',ok=False); want(p.returncode==0,'later redo failed')
 event(p,n=2)
 want(lock.read_bytes()==grown,'later redo dropped the newly locked file or rewrote unchanged lock')
assert not errors,'\n'.join(errors)
PY60
  pass
}
