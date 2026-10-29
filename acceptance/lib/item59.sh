# Item 59: public commands, real pytest JUnit; every Git operation stays in this case's project.
item59_cases() {
  local c
  for c in files files-order files-suffix-py files-go files-ts files-mjs files-exclusions files-all files-config files-no-base files-many files-extensions files-globs files-base files-build-fails files-check-fails files-invalid \
    suites suites-no-base suites-passing suites-present suites-unnamed suites-empty suites-base-bad suites-base-missing suites-base-invalid suites-base-invalid-absent suites-base-reader suites-base suites-redo suites-redo-same suites-refusal stderr-closed \
    ci ci-mixed ci-present ci-unreadable ci-bad-config ci-longest ci-remedy; do echo "v1-59.$c"; done
}
item59_case() {
  EXPECT="item 59: ${CASE#v1-59.}"
  v1_start
  must_accept 'item 59 black box contract' cmd "$PY" - "${CASE#v1-59.}" "$(command -v shipcraft)" <<'PY59'
import hashlib,json,os,re,shlex,shutil,subprocess,sys
from pathlib import Path
mode,binary=sys.argv[1:]
project=Path('item59-project'); project.mkdir(); os.chdir(project)
errors=[]
def want(condition,message):
 if not condition: errors.append(message)
def write(p,s):
 p=Path(p); p.parent.mkdir(parents=True,exist_ok=True); p.write_text(s)
def run(*args,ok=True,closed=False,**kw):
 if closed:
  p=subprocess.run(['sh','-c','exec "$@" 2>&-', '_',*args],stdout=subprocess.PIPE,text=True,timeout=90,**kw); p.stderr=''
 else: p=subprocess.run(args,capture_output=True,text=True,timeout=90,**kw)
 print('$',shlex.join(args),'[rc='+str(p.returncode)+']\n'+p.stdout+(p.stderr or ''),flush=True)
 if ok: assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr)
 return p

def git(*args,**kw): return run('git',*args,**kw).stdout.strip()
def commit(msg):
 git('add','-A'); git('-c','core.hooksPath=/dev/null','commit','-qm',msg)
def test(root,passing=True,extra=False):
 write(root+'/value','green' if passing else 'red')
 write(root+'/tests/test_'+root+'.py','from pathlib import Path\ndef test_anchor():\n    assert Path("value").read_text() == "green"\n'+ ('\ndef test_extra():\n    assert True\n' if extra else ''))
def config(suites,keep=False):
 s='shipcraft_min = "0.0"\nlang = "python"\nrunner = "pytest"\n[execution]\nci = "local"\nreview = "off"\n[build]\ncommand = "echo BUILD59 >&2"\n'
 for name,root in suites:
  command='pytest --junitxml={junit} '+('tests/test_keep.py' if keep and root=='core' else 'tests')
  s+='\n[[suite]]\n'+('name = '+json.dumps(name)+'\n' if name is not None else '')+'root = '+json.dumps(root)+'\ncommand = '+json.dumps(command)+'\nglobs = ["tests/**"]\ncheck = "echo CHECK59 >&2"\n'
 write('.shipcraft.toml',s)
def locks(): return sorted(Path('.shipcraft/locks').glob('*.json'))
def rows():
 p=Path('.git/shipcraft/runs.jsonl')
 return [json.loads(s) for s in p.read_text().splitlines()] if p.exists() else []
def state(expected=1):
 ls=locks(); assert len(ls)==expected,ls
 if not ls: return
 d=json.loads(ls[0].read_text()); assert d['state']=='open',d
 assert set(d)=={'format','state','files','cases','failing_at_red','seal'},d
 for f,h in d['files'].items(): assert h=='sha256:'+hashlib.sha256(Path(f).read_bytes()).hexdigest(),(f,h)
 assert d['cases'] and d['failing_at_red'],d
 expected_files={'.shipcraft.toml'}|{str(p) for _,root in current for p in Path(root+'/tests').glob('*') if p.is_file()}
 # The glob fixture additionally protects files which its command intentionally does not collect.
 if mode=='files-globs': expected_files|={'core/extra/fixture_test.py','core/extra/deep/a.test.ts'}
 assert set(d['files'])==expected_files,(d['files'],expected_files)
 expected_cases=set(); expected_failing=set()
 narrowed=rows()[-1].get('selection')=='changed'
 for name,root in current:
  prefix=(name+':') if name else ''
  for p in Path(root+'/tests').glob('test_*.py'):
   if narrowed and str(p)!='core/tests/test_core.py': continue
   for function in re.findall(r'^def (test_\w+)\(',p.read_text(),re.M):
    suffixes=['[%02d]'%i for i in range(40)] if mode=='files-many' and function=='test_anchor' else ['']
    ids={prefix+'tests.'+p.stem+'::'+function+suffix for suffix in suffixes}
    expected_cases|=ids
    if function=='test_added' or (function=='test_anchor' and Path(root+'/value').read_text()=='red'): expected_failing|=ids
 assert set(d['cases'])==expected_cases,(d['cases'],expected_cases)
 assert set(d['failing_at_red'])==expected_failing,(d['failing_at_red'],expected_failing)
 return d

def event(before,code='',redo=False):
 rs=rows(); assert len(rs)==len(before)+1 and rs[:len(before)]==before,rs
 r=rs[-1]; assert r['layer']=='red' and r['result']==('refused' if code else 'passed') and r['code']==code,r
 keys={'at','branch','code','commit','fallback','layer','lock','result','secs','selected_files','selection'}
 if not code and mode!='suites-redo-same': keys.add('rerun_dropped')
 if code=='shipcraft-min': keys-={'selection','selected_files','fallback'}
 if code: keys.add('reason')
 if redo: keys.add('redo')
 assert set(r)==keys,(set(r),keys,r)
 if redo: assert r['redo'] is True,r
 assert r['branch']=='feature/item59' and r['commit']==git('rev-parse','HEAD') and r['secs']>=0,r
 if not code: assert r['lock']==locks()[0].stem and r.get('rerun_dropped',0)==0,r
 return r

def fmt(items):
 items=sorted(set(items),key=lambda x:x.encode())
 return ', '.join(items[:3])+(' and '+str(len(items)-3)+' more' if len(items)>3 else '')
def wfiles(paths):
 return "shipcraft: warning: "+str(len(paths))+" changed test file(s) match no suite's globs and are not locked: "+fmt(paths)+"; widen a suite's globs, or add a [[suite]] for them (when the base has a .shipcraft.toml, CI judges a PR by the base's, so a new suite goes in a PR of its own first)"
def wsuites(names,ref='origin/HEAD'):
 return "shipcraft: warning: the lock has cases in suite(s) absent from "+ref+"'s .shipcraft.toml: "+fmt(names)+"; CI judges a PR by its base's config and will refuse them as case-missing; bring the suite to "+ref+" in a PR of its own, then rebase this branch"
def warnings(p,paths=(),names=(),ref='origin/HEAD',many=False):
 actual=[s for s in p.stderr.splitlines() if s.startswith('shipcraft: warning:')]
 expected=([wfiles(paths)] if paths and not many else [])+([wsuites(names,ref)] if names else [])
 if many:
  actual=[s for s in actual if "changed test file(s) match no suite's globs" not in s]
 want(actual==expected, 'warning lines differ: '+repr((actual,expected)))
 want('shipcraft: warning:' not in p.stdout,'warning leaked to stdout')
 if paths:
  lines=p.stderr.splitlines(); hits=[i for i,s in enumerate(lines) if "changed test file(s) match no suite's globs" in s]
  want(len(hits)==1,'missing/duplicate outside-globs warning')
  if hits:
   want(all(hits[0]<i for i,s in enumerate(lines) if 'BUILD59' in s or 'CHECK59' in s),'warning follows build/check')

def config_object(text):
 # Make an alternate base commit without changing this project's worktree or HEAD.
 index=str(Path('.git/alternate-index59').resolve()); env=dict(os.environ,GIT_INDEX_FILE=index)
 git('read-tree','HEAD',env=env)
 blob=git('hash-object','-w','--stdin',input=text)
 git('update-index','--add','--cacheinfo','100644,'+blob+',.shipcraft.toml',env=env)
 tree=git('write-tree',env=env)
 return git('commit-tree',tree,'-p','HEAD','-m','test: alternate base snapshot')

git('init','-q','-b','main'); git('config','user.name','RED 59'); git('config','user.email','red59@example.invalid')
write('.gitignore','__pycache__/\n.pytest_cache/\n')
test('core'); write('core/tests/test_keep.py','def test_keep():\n    assert True\n')
ci=mode.startswith('ci')
base_suites=[('core','core')]
if mode=='ci-longest': base_suites=[('core','core'),('api','api')]; test('api')
if mode in ('suites-present','suites-base-invalid','suites-base-reader'): base_suites.append(('jobs','oldjobs')); test('oldjobs')
config(base_suites,keep=mode in ('ci-mixed','ci-present','ci-unreadable','ci-bad-config','files-many'))
if mode=='suites-base-bad': write('.shipcraft.toml','suite = [\n')
if mode=='suites-base-missing': Path('.shipcraft.toml').unlink()
if mode in ('suites-base-invalid','suites-base-invalid-absent'):
 # Valid TOML with a minimum above this binary; names alone decide presence.
 version=run(binary,'--version').stdout; major=int(re.search(r'\d+',version).group())+10
 p=Path('.shipcraft.toml'); p.write_text(p.read_text().replace('shipcraft_min = "0.0"','shipcraft_min = "'+str(major)+'.0"'))
if mode=='suites-present':
 p=Path('.shipcraft.toml'); p.write_text(p.read_text().replace('root = "oldjobs"\ncommand = "pytest --junitxml={junit} tests"','root = "oldjobs"\ncommand = "pytest --junitxml={junit} tests/test_oldjobs.py"'))
if mode=='suites-base-reader':
 version=run(binary,'--version').stdout; major=int(re.search(r'\d+',version).group())+10
 write('.shipcraft.toml',"shipcraft_min = '"+str(major)+".0'\r\nlegacy_invalid = true\r\n[[suite]] # TOML alone, no config validation\r\nname = 'core'\r\n[[suite]]\r\nname = 'jobs' # present by name only\r\n[[suite]]\r\nname = 17\r\n[[suite]]\r\nname = ''\r\n[[suite]]\r\nroot = '.'\r\n")
if mode=='files-order': write('outside/test_é.py','tracked old')
if mode=='files-exclusions': write('outside/test_deleted.py','gone'); write('outside/test_link.py','old')
if mode in ('ci-unreadable','ci-bad-config'):
 write('core/tests/conftest.py', "import os,subprocess\nfrom pathlib import Path\ndef pytest_sessionfinish(session,exitstatus):\n    if os.environ.get('ITEM59_READY'):\n        Path(os.environ['ITEM59_READY']).touch()\n")
commit('test: base suite')
git('init','-q','--bare','.git/origin.git'); git('--git-dir=.git/origin.git','symbolic-ref','HEAD','refs/heads/main')
git('remote','add','origin',str(Path('.git/origin.git').resolve())); git('push','-q','origin','main'); git('fetch','-q','origin'); git('remote','set-head','origin','main')
base=git('rev-parse','HEAD'); git('checkout','-qb','feature/item59')
current=[('core','core')]; absent=[]; paths=[]; args=[]
test('core',False)
# Ensure a protected test is changed, so ordinary file diagnostics also pin narrowed selection.
with open('core/tests/test_core.py','a') as f: f.write('\n# changed RED file\n')
if ci or mode.startswith('suites') or mode=='stderr-closed':
 if mode=='ci-longest': current += [('api','api'),('api:v2','jobs')]; absent=['api:v2']
 elif mode in ('suites-unnamed','suites-empty'):
  current += [(None if mode=='suites-unnamed' else '', 'jobs')]
 else:
  current += [('zeta','zeta'),('jobs','jobs')]; absent=['jobs','zeta']
  if mode in ('suites-present','suites-base-invalid'):
   current=[('core','core'),('jobs','jobs')]; absent=[]
 for name,root in current[1:]: test(root,passing=mode=='suites-passing',extra=root=='jobs')
 config(current)
 if mode in ('suites-base-bad','suites-base-missing'): absent=[]
 if mode=='suites-base-reader': absent=['zeta']
 if mode=='suites-refusal':
  for _,root in current: write(root+'/value','green')
 if mode=='ci-present': current=[('core','core')]; config(current); absent=[]
 if mode=='suites-no-base':
  git('symbolic-ref','--delete','refs/remotes/origin/HEAD'); absent=[]
 if mode=='suites-base':
  # Explicit ref has the new names; origin/HEAD does not. Its tip is not the merge base.
  oid=config_object(Path('.shipcraft.toml').read_text()+'\n# alternate tip\n')
  git('update-ref','refs/heads/landing59',oid); args=['--base','landing59']; absent=[]
 if mode=='stderr-closed': paths=['outside/test_jobs.py']; write(paths[0],'uncollected')
else:
 families={'files':'outside/test_jobs.py','files-suffix-py':'outside/jobs_test.py','files-go':'outside/jobs_test.go','files-ts':'outside/jobs.test.ts','files-mjs':'outside/jobs.spec.mjs'}
 if mode in families: paths=[families[mode]]
 elif mode=='files-order': paths=['outside/z.spec.mjs','outside/test_é.py','outside/a jobs_test.py']
 elif mode=='files-exclusions':
  Path('outside/test_deleted.py').unlink(); Path('outside/test_link.py').unlink(); Path('outside/test_link.py').symlink_to('../core/tests/test_core.py')
  for p in ('outside/readme.py','outside/test.py','outside/foo.test.txt','outside/Test_x.py'): write(p,'near miss')
 elif mode=='files-extensions':
  paths=['outside/'+p for p in ('test_.py','_test.py','_test.go','.test.js','.spec.jsx','a.test.mjs','a.spec.cjs','a.test.ts','a.spec.tsx','a.test.mts','a.spec.cts')]
 elif mode=='files-globs':
  config(current)
  p=Path('.shipcraft.toml'); p.write_text(p.read_text().replace('globs = ["tests/**"]','globs = ["tests/**", "extra/*_test.py", "extra/**/?.test.ts"]'))
  write('core/extra/fixture_test.py','protected but not collected'); write('core/extra/deep/a.test.ts','protected but not collected')
  paths=['extra/deep/a.test.ts','core/extra/deep/ab.test.ts']
  # ab.test.ts is outside the single-character ? glob, and is therefore not locked.
 elif mode=='files-many': paths=['outside/%02d.test.ts'%i for i in range(40)]
 else: paths=['outside/test_jobs.py']
 for p in paths: write(p,'uncollected\n')
 if mode=='files-all': args=['--all']
 if mode in ('files-config','files-invalid'): write('.shipcraft.toml',Path('.shipcraft.toml').read_text()+'\n# working tree config changed\n')
 if mode=='files-no-base': git('symbolic-ref','--delete','refs/remotes/origin/HEAD')
 if mode=='files-base':
  git('update-ref','refs/heads/before59',base)
  commit('test: outside file already at default base'); git('update-ref','refs/remotes/origin/main','HEAD')
  args=['--base','before59']
 if mode=='files-build-fails':
  p=Path('.shipcraft.toml'); p.write_text(p.read_text().replace('echo BUILD59 >&2','echo BUILD59 >&2; exit 23'))
 if mode=='files-check-fails':
  p=Path('.shipcraft.toml'); p.write_text(p.read_text().replace('echo CHECK59 >&2','echo CHECK59 >&2; exit 24'))
 if mode=='files-invalid':
  version=run(binary,'--version').stdout; major=int(re.search(r'\d+',version).group())+10
  write('.shipcraft.toml','shipcraft_min = "'+str(major)+'.0"\n')
 if mode=='files-many':
  config(current)
  write('core/tests/test_core.py','import pytest\nfrom pathlib import Path\n@pytest.mark.parametrize("n", range(40), ids=["%02d"%i for i in range(40)])\ndef test_anchor(n):\n    assert Path("value").read_text()=="green"\n')

ref='before59' if mode=='files-base' else 'landing59' if mode=='suites-base' else 'origin/HEAD'
# For successful --all comparisons, removing only the diagnostic inputs must leave
# lock bytes and every stable event field identical. secs/at/lock-id are per-run.
def normalized(r): return {k:v for k,v in r.items() if k not in ('at','secs','lock')}
control=None
if mode in ('files-all','stderr-closed','suites','suites-passing'):
 args=['--all']
 saved={p:Path(p).read_bytes() for p in paths}
 for p in paths: Path(p).unlink()
 old=git('rev-parse','origin/main')
 oid=config_object(Path('.shipcraft.toml').read_text()+'\n# control has all current names\n')
 git('update-ref','refs/remotes/origin/main',oid)
 before=rows(); cp=run(binary,'red',*args); cd=state(); cr=event(before)
 warnings(cp)
 control=(locks()[0].read_bytes(),normalized(cr))
 locks()[0].unlink(); git('update-ref','refs/remotes/origin/main',old)
 for p,b in saved.items(): Path(p).write_bytes(b)

if mode in ('suites-redo','suites-redo-same'):
 p=run(binary,'red'); state(); commit('test: original open RED')
 oldlock=locks()[0].read_bytes()
 if mode=='suites-redo':
  write('jobs/tests/test_added.py','def test_added():\n    assert False\n')
 args=['--redo']
before=rows()
code={'suites-refusal':'red-already-passes','files-build-fails':'build-failed','files-check-fails':'no-report','files-invalid':'shipcraft-min'}.get(mode,'')
p=run(binary,'red',*args,ok=not code,closed=mode=='stderr-closed')
assert p.returncode==(1 if code else 0),p.returncode
if code:
 state(0); event(before,code)
 lines=[s for s in (p.stdout+p.stderr).splitlines() if s.strip()][-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 warnings(p,paths if mode in ('files-build-fails','files-check-fails') else ())
else:
 d=state(); r=event(before,redo=mode in ('suites-redo','suites-redo-same'))
 if control:
  assert locks()[0].read_bytes()==control[0], 'warning changed lock bytes'
  assert normalized(r)==control[1],('warning changed run log',r,control)
 if mode=='suites-redo-same': assert locks()[0].read_bytes()==oldlock,'unchanged redo rewrote lock'
 if mode=='suites-redo': assert locks()[0].read_bytes()!=oldlock and any('test_added' in c for c in d['cases']),d
 if mode=='suites-passing':
  for n in absent:
   assert any(c.startswith(n+':') for c in d['cases']) and not any(c.startswith(n+':') for c in d['failing_at_red']),d
 if mode.startswith('files') and mode not in ('files-all','files-config','files-no-base','files-globs','files-many','files-base'):
  assert (r['selection'],r['selected_files'],r['fallback'])==('changed',1,None),r
 if mode=='files-all': assert (r['selection'],r['selected_files'],r['fallback'])==('all',0,'--all'),r
 if mode=='files-config': assert (r['selection'],r['selected_files'],r['fallback'])==('all',0,'config changed'),r
 if mode=='files-no-base': assert r['fallback']=='no base',r
 if mode!='stderr-closed' and not ci: warnings(p,() if mode=='files-no-base' else paths,() if mode=='suites-redo-same' else absent,ref,many=mode=='files-many')

if ci or mode=='files-many':
 # Commit the real lock with its RED tests, then fix product only. No protected
 # tests or lock bytes are edited to manufacture CI's missing-case result.
 redlock=locks()[0].read_bytes()
 commit('test: RED suites')
 checked=git('rev-parse','HEAD')
 for _,root in current: write(root+'/value','green')
 git('add','-A'); run(binary,'check'); commit('feat: GREEN product')
 redlock=locks()[0].read_bytes()
 assert json.loads(redlock)['state']=='closed','fixture must close GREEN through the public hook command'
 cienv=os.environ.copy()
 if mode in ('ci-unreadable','ci-bad-config'):
  realgit=shutil.which('git'); bindir=Path('.git/bin59').resolve(); ready=Path('.git/diagnostic-ready59').resolve()
  cienv.update(ITEM59_CHECKED=checked+','+git('rev-parse','HEAD'),ITEM59_READY=str(ready),PATH=str(bindir)+os.pathsep+cienv['PATH'])
  # These are Git's public blob-reading interfaces, not a substitute report or lock.
  wrapper="#!"+sys.executable+"\nimport os,sys,subprocess\nfrom pathlib import Path\na=sys.argv[1:]\nreal="+repr(realgit)+"\n"
  wrapper+="target=os.environ.get('ITEM59_CHECKED','')\nready=Path(os.environ['ITEM59_READY'])\n"
  wrapper+="if ready.exists() and a and a[0] in ('show','cat-file'):\n    for arg in a[1:]:\n        if arg.endswith(':.shipcraft.toml'):\n            ref=arg.rsplit(':',1)[0]\n            p=subprocess.run([real,'rev-parse','-q','--verify',ref],capture_output=True,text=True)\n            if p.returncode==0 and p.stdout.strip() in set(target.split(',')):\n"
  if mode=='ci-unreadable': wrapper+="                sys.stderr.write('fatal: item59 config object unreadable\\n'); sys.exit(128)\n"
  else: wrapper+="                sys.stdout.write('suite = [\\n'); sys.exit(0)\n"
  wrapper+="os.execv(real,[real,*a])\n"
  write(bindir/'git',wrapper); (bindir/'git').chmod(0o755)
 beforeci=rows(); result=run(binary,'ci','--base','origin/main','--pr',ok=False,env=cienv)
 if mode in ('ci-unreadable','ci-bad-config'): assert ready.exists(),'checked commit never reached its real suite report'
 assert result.returncode==1,result.returncode
 rs=rows(); assert rs[:len(beforeci)]==beforeci and len(rs)==len(beforeci)+1,rs
 row=rs[-1]
 assert set(row)=={'at','branch','code','commit','docs_only','layer','lock','locks','reason','result','secs'},row
 assert row['locks']==[locks()[0].stem] and row['branch']=='feature/item59' and row['commit']==git('rev-parse','HEAD') and row['secs']>=0,row
 assert row['layer']=='ci' and row['result']=='refused' and row['code']=='case-missing',row
 assert locks()[0].read_bytes()==redlock,'CI diagnosis changed the lock'
 lines=[s for s in (result.stdout+result.stderr).splitlines() if s.strip()][-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 reason=lines[0]; newtext='belong to suite(s) that the .shipcraft.toml CI judges with does not have:'
 if mode in ('ci-present','ci-unreadable','ci-bad-config','files-many'):
  assert 'are missing from the report' in reason and newtext not in reason,reason
 else:
  missing_names=['api:v2'] if mode=='ci-longest' else ['jobs','zeta']
  count=sum(1 for c in d['cases'] if any(c.startswith(n+':') for n in missing_names))
  expected='shipcraft refused: case(s) from lock '+str(locks()[0])+' '+newtext+' '+', '.join(sorted(missing_names))+' ('+str(count)+' case(s))'
  want(reason==expected,'CI diagnosis differs: '+repr((reason,expected)))
  want('base' in lines[1] and 'config' in lines[1] and 'branch' in lines[1], 'CI Why omits base-config cause')
  want(all(s in lines[2] for s in ('[[suite]]','passing test','rebase','shipcraft ci')), 'CI Next omits documented remedy')
  assert row['reason']==reason.removeprefix('shipcraft refused: '),row
 if mode=='files-many':
  # Use today's public case-missing refusal as the list-format oracle. Substitute
  # each known, sorted case id with the corresponding sorted repository path.
  listing=reason.split('are missing from the report: ',1)[1]
  for case,path in sorted(zip(sorted(d['cases']),paths),key=lambda x:-len(x[0])): listing=listing.replace(case,path)
  want(not any(c in listing for c in d['cases']),'formatter oracle left a case id')
  want('more' in listing and paths[-1] not in listing,'formatter oracle did not truncate')
  expected=wfiles(paths).replace(fmt(paths),listing)
  want(expected in p.stderr.splitlines(),'truncated warning differs from existing case-list formatting: '+repr((listing,[s for s in p.stderr.splitlines() if s.startswith('shipcraft: warning:')])))
 if mode=='ci-remedy':
  # Land the package, named suites and one passing test on the actual base.
  # Keep the branch's RED test/config blobs byte-identical to the landed ones.
  git('checkout','-q','main')
  config(current)
  for _,root in current[1:]: test(root,True,extra=root=='jobs')
  commit('feat: land suites with passing tests first')
  git('push','-q','origin','main'); git('fetch','-q','origin')
  git('checkout','-q','feature/item59'); git('-c','core.hooksPath=/dev/null','rebase','-X','theirs','-q','main')
  beforepass=rows(); result=run(binary,'ci','--base','origin/main','--pr')
  assert len(rows())==len(beforepass)+1 and rows()[-1]['result']=='passed' and not rows()[-1]['code'],rows()
  assert 'shipcraft: CI ok.' in result.stdout,result.stdout
assert not errors,'\n'.join(errors)
PY59
  pass
}
