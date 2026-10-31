# Item 66: native runner reports, public RED commands, isolated Git fixtures.
item66_langs() { echo python node go; }
item66_cases() {
  echo v1-66.main; echo v1-66.head-boundary
  [ "${l:-}" = python ] || return 0
  local c
  for c in origin-head origin-main origin-master local-main local-master; do
    echo "v1-66.$c"; echo "v1-66.$c-first"
  done
  for c in noncommit noncommit-many unborn unborn-remote git-head git-candidate git-invalid git-status unrelated unrelated-first explicit explicit-bad explicit-blob explicit-unrelated warnings warnings-local redo redo-head redo-refusal committed committed-local passing collection build-fails check-fails log-fails lock-open all; do echo "v1-66.$c"; done
}
item66_case() {
  EXPECT="item 66: ${CASE#v1-66.}"; v1_start; setup_init
  [ "$LP" != go ] || { PATH="$GOBIN:$PATH"; export PATH; }
  must_accept 'item 66 base, notices, lock and real-run row' cmd "$PY" - "${CASE#v1-66.}" "$LP" "$(command -v shipcraft)" "$ACEITE/../nucleo/Cargo.toml" <<'PY66'
import hashlib,json,os,re,shlex,shutil,subprocess,sys
from pathlib import Path
mode,lang,binary,manifest=sys.argv[1:]
errors=[]
def want(v,msg):
 if not v: errors.append(msg)
def run(*args,ok=True,env=None):
 p=subprocess.run(args,capture_output=True,text=True,timeout=90,env=env,input="")
 print('$',shlex.join(args),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 if ok: assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr)
 return p
def git(*args): return run('git',*args).stdout.strip()
def commit(msg):
 git('add','-A'); git('-c','core.hooksPath=/dev/null','commit','-qm',msg)
def test(name,passing=False):
 if lang=='python': path='tests/test_'+name+'.py'; text='def test_'+name+'():\n    assert '+str(passing)+'\n'
 elif lang=='node': path='src/'+name+'.test.ts'; text="import {it,expect} from 'vitest';\nit('"+name+"',()=>expect("+str(passing).lower()+").toBe(true));\n"
 else: path=name+'_test.go'; text='package textutil\nimport "testing"\nfunc Test'+name.title()+'(t *testing.T) { '+('' if passing else 't.Fatal("'+name+'")')+' }\n'
 Path(path).write_text(text); return path
def locks(): return sorted(Path('.shipcraft/locks').glob('*.json'))
def rows():
 p=Path('.git/shipcraft/runs.jsonl')
 return [json.loads(s) for s in p.read_text().splitlines() if json.loads(s).get('layer')=='red'] if p.is_file() else []
def config(names):
 text='shipcraft_min = "0.0"\nlang = "python"\nrunner = "pytest"\n[execution]\nci = "local"\nreview = "off"\n'
 for name in names:
  text+='\n[[suite]]\nname = '+json.dumps(name)+'\nroot = '+json.dumps(name)+'\ncommand = "pytest --junitxml={junit} tests"\nglobs = ["tests/**"]\n'
  path=Path(name,'tests'); path.mkdir(parents=True,exist_ok=True)
  (path/('test_'+name+'66.py')).write_text('def test_'+name+'66():\n    assert False\n')
 Path('.shipcraft.toml').write_text(text)
warning=mode.startswith('warnings')
if warning: config(['core'])
old=test('legacy66'); commit('test: already-failing unrelated test66')
a=git('rev-parse','HEAD')
git('checkout','-qb','feature/item66'); git('branch','-D','main')
bridge=None
if mode not in ('main','head-boundary'):
 bridge=test('bridge66')
 if warning:
  config(['core','landing'])
  Path('outside').mkdir(exist_ok=True); Path('outside/test_committed66.py').write_text('# already in chosen base\n')
 commit('test: second base distinguishes candidate commits')
b=git('rev-parse','HEAD')
refs=[('origin-head','refs/remotes/origin/HEAD','origin/HEAD'),('origin-main','refs/remotes/origin/main','origin/main'),('origin-master','refs/remotes/origin/master','origin/master'),('local-main','refs/heads/main','main'),('local-master','refs/heads/master','master')]
chosen='HEAD'; reason=None; code=''; args=[]; redo=False; early=False; selected=[test('fresh66')]
if mode=='head-boundary':
 git('add',selected[0]); git('checkout','--detach','-q')
for index,(label,ref,short) in enumerate(refs):
 if mode in (label,label+'-first'):
  chosen=short; oid=b if mode.endswith('-first') else a
  git('update-ref',ref,oid)
  if oid==a and bridge: selected.append(bridge)
  if mode.endswith('-first'):
   # Every later candidate resolves to a different commit: first means first.
   for _,later,_ in refs[index+1:]: git('update-ref',later,a)
if mode in ('noncommit','noncommit-many'):
 blob=git('hash-object','-w','--stdin')
 for _,ref,_ in refs[:(3 if mode=='noncommit-many' else 1)]: git('update-ref',ref,blob)
 target=refs[4] if mode=='noncommit-many' else refs[1]
 git('update-ref',target[1],b); chosen=target[2]
if mode in ('unborn','unborn-remote'):
 if mode=='unborn-remote': git('update-ref','refs/remotes/origin/main',b)
 git('symbolic-ref','HEAD','refs/heads/unborn66'); reason='no base'; chosen=None
if mode in ('unrelated','unrelated-first','explicit-unrelated'):
 tree=git('rev-parse',b+'^{tree}'); other=git('commit-tree',tree,'-m','unrelated root66')
 git('update-ref','refs/remotes/origin/main',other); chosen='origin/main'; reason='no merge base'
 if mode=='unrelated-first': git('update-ref','refs/heads/main',b)
 if mode=='explicit-unrelated': args=['--base',other]; chosen=None
if mode.startswith('explicit'):
 if mode=='explicit':
  git('update-ref','refs/remotes/origin/HEAD',b); args=['--base',a]; selected.append(bridge)
 if mode=='explicit-bad': args=['--base','missing66']; reason='no base'
 if mode=='explicit-blob': args=['--base',git('hash-object','-w','--stdin')]; reason='no base'
 chosen=None
if warning:
 chosen='main' if mode=='warnings-local' else 'origin/main'
 git('update-ref','refs/heads/main' if mode=='warnings-local' else 'refs/remotes/origin/main',b)
 if mode=='warnings': git('update-ref','refs/heads/main',a)
 if mode=='warnings-local': git('reset','--soft',a) # chosen config is at the ref tip, beyond the merge base
 config(['core','landing','jobs'])
 Path('outside/test_new66.py').write_text('# changed outside every suite\n')
 reason='config changed'
if mode in ('committed','committed-local'):
 commit('test: tests already committed before red')
 if mode=='committed-local': git('update-ref','refs/heads/main','HEAD'); chosen='main'
 reason='nothing selected'
if mode in ('redo','redo-head','redo-refusal','lock-open'):
 git('update-ref','refs/remotes/origin/HEAD',b)
 initial=run(binary,'red'); assert locks(),initial
 commit('test: initial open lock66')
 git('update-ref','-d','refs/remotes/origin/HEAD')
 if mode=='redo': git('update-ref','refs/remotes/origin/main','HEAD'); chosen='origin/main'
 if mode=='lock-open': code='lock-open'; early=True
 else:
  redo=True; args=['--redo']
  with Path(selected[0]).open('a') as f: f.write('\n# redo changes the protected test\n')
  if mode=='redo-refusal': test('fresh66',True); code='red-already-passes'
if mode=='passing': test('fresh66',True); code='red-already-passes'
if mode=='collection':
 Path(selected[0]).write_text('raise RuntimeError("collection66")\n'); code='error-before-assertions'
if mode in ('build-fails','check-fails'):
 text=Path('.shipcraft.toml').read_text()
 # Commit the fixture config first so the later failure cannot be config changed.
 fresh=Path(selected[0]).read_bytes(); Path(selected[0]).unlink()
 sentinel=Path('.git/fail66').resolve()
 if mode=='build-fails': text+='\n[build]\ncommand = '+json.dumps('test ! -f '+shlex.quote(str(sentinel)))+'\n'; code='build-failed'
 else:
  # Native init uses top-level form; add check beside its command.
  text=re.sub(r'(?m)^(test_command|command) = ', 'check = '+json.dumps('test ! -f '+shlex.quote(str(sentinel)))+'\n\\1 = ',text,count=1); code='no-report'
 Path('.shipcraft.toml').write_text(text); commit('chore: configured later failure66')
 Path(selected[0]).write_bytes(fresh); sentinel.touch()
if mode=='log-fails':
 log=Path('.git/shipcraft/runs.jsonl'); log.unlink(missing_ok=True); log.mkdir(parents=True)
if mode=='all': args=['--all']; reason='--all'
# A transparent git shim records candidate resolution and injects only specified faults.
# Same forwarding pattern as item41, with real git handling every other command.
realgit=shutil.which('git'); bindir=Path('.git/bin66').resolve(); bindir.mkdir()
trace=Path('.git/trace66').resolve(); fault=''
if mode in ('git-head','git-invalid','git-status'): fault='HEAD^{commit}'; chosen=None; reason='git failed'
if mode=='git-candidate':
 fault='refs/remotes/origin/HEAD^{commit}'; chosen=None; reason='git failed'
 git('update-ref','refs/heads/main',b)
wrapper='#!'+sys.executable+'\nimport os,sys,json\na=sys.argv[1:]\nb=a[a.index("rev-parse"):] if "rev-parse" in a else a\n'
wrapper+='with open('+repr(str(trace))+',"a") as f: f.write(json.dumps(b)+"\\n")\n'
wrapper+='if b and b[0]=="rev-parse" and '+repr(fault)+' in b:\n'
wrapper+='    '+('print("not-a-commit"); sys.exit(0)' if mode=='git-invalid' else 'sys.exit(2)' if mode=='git-status' else 'sys.exit(128)')+'\n'
wrapper+='os.execv('+repr(realgit)+', ['+repr(realgit)+']+a)\n'
shim=bindir/'git'; shim.write_text(wrapper); shim.chmod(0o755)
env=dict(os.environ,PATH=str(bindir)+os.pathsep+os.environ['PATH'])
before=len(rows()); original=locks()[0].read_bytes() if locks() else None
p=run(binary,'red',*args,ok=False,env=env)
want(p.returncode==(1 if code else 0),'wrong RED exit: '+str(p.returncode))
ls=locks(); notice_prefix='shipcraft: red compared with '
lines=p.stdout.splitlines(); combined=(p.stdout+p.stderr).splitlines()
if not early:
 protected={'.shipcraft.toml'}
 if warning:
  protected|={str(f) for name in ('core','landing','jobs') for f in Path(name,'tests').glob('*.py')}
 else:
  protected|={str(f) for f in Path('tests' if lang=='python' else 'src' if lang=='node' else '.').glob('*.py' if lang=='python' else '*.test.ts' if lang=='node' else '*_test.go') if f.name!='__init__.py'}
 n=0 if reason else len(selected)
 selection='shipcraft: red ran every suite: '+reason if reason else f'shipcraft: red ran the changed test files: {n} of {len(protected)}'
 want(combined.count(selection)==1,'missing/duplicate exact selection notice: '+selection)
 expected_notice=None if chosen in (None,'origin/HEAD') else f'shipcraft: red compared with {chosen} (origin/HEAD is missing)'
 if expected_notice:
  want(lines.count(expected_notice)==1,'missing/duplicate exact stdout base notice: '+expected_notice)
  want(sum(s.startswith(notice_prefix) for s in combined)==1,'comparison notice must occur exactly once overall')
  want(not any(s.startswith(notice_prefix) for s in p.stderr.splitlines()),'base notice must be stdout')
  if expected_notice in lines: want(lines[lines.index(expected_notice)+1:lines.index(expected_notice)+2]==[selection],'base notice must immediately precede selection on stdout')
 else: want(not any(s.startswith(notice_prefix) for s in combined),'unexpected comparison notice')
else: want(not any(s.startswith(notice_prefix) or s.startswith('shipcraft: red ran ') for s in combined),'early refusal printed selection/base')
if mode!='log-fails':
 rs=rows(); want(len(rs)==before+1,'exactly one new red row'); r=rs[-1]
 keys={'at','branch','code','commit','layer','lock','result','secs'}
 if not early: keys|={'selection','selected_files','fallback'}
 if code: keys.add('reason')
 else: keys.add('rerun_dropped')
 if warning: keys.add('unchanged_dropped')
 if redo: keys.add('redo')
 else: keys.update(('kind','reported_at','fixes_release'))

 if not redo: want((r.get('kind'),r.get('reported_at'),r.get('fixes_release'))==('feature',None,None),'fix row values')
 want(set(r)==keys,'red row gained/lost fields: '+repr(r))
 if warning: want(r.get('unchanged_dropped')==(1 if mode=='warnings-local' else 2),'unchanged drop count')
 want(r.get('code')==code and r.get('result')==('refused' if code else 'passed'),'row verdict: '+repr(r))
 want(r.get('secs',-1)>=0 and r.get('layer')=='red','row identity/time')
 if mode not in ('unborn','unborn-remote'): want(r.get('commit')==git('rev-parse','HEAD'),'row commit must describe real run')
 if redo: want(r.get('redo') is True,'redo flag missing')
 if not early: want((r.get('selection'),r.get('selected_files'),r.get('fallback'))==('all' if reason else 'changed',n,reason),'real-run selection: '+repr(r))
if code:
 if original: want(len(ls)==1 and ls[0].read_bytes()==original,'refusal changed existing lock')
 else: want(not ls,'refusal wrote lock')
else:
 want(len(ls)==1,'one open lock')
 if ls:
  d=json.loads(ls[0].read_text())
  want((d.get('kind'),d.get('reported_at'),d.get('fixes_release'))==('feature',None,None),'fix lock values')
  want(set(d)=={'format','state','files','cases','failing_at_red','kind','reported_at','fixes_release','seal'} and d['state']=='open','lock format changed')
  want(set(d['files'])==protected,'protected files must not narrow: '+repr(d['files']))
  for f,h in d['files'].items(): want(h=='sha256:'+hashlib.sha256(Path(f).read_bytes()).hexdigest(),'wrong protected hash: '+f)
  for key in ('cases','failing_at_red'):
   ids=d[key]
   if warning: want(set(ids)=={name+':tests.test_'+name+'66::test_'+name+'66' for name in (('landing','jobs') if mode=='warnings-local' else ('jobs',))},'warning changed lock: '+repr(ids))
   else:
    expected_names={'fresh66'}|({'legacy66','bridge66'} if reason and bridge else {'legacy66'} if reason else {'bridge66'} if bridge in selected else set())
    expected_count=len(expected_names)+(1 if reason and key=='cases' else 0)
    want(len(ids)==expected_count and all(any(name in s.lower() for s in ids) for name in expected_names),'kept '+key+': '+repr(ids)+' expected '+repr(expected_names))
  if mode!='log-fails': want(r.get('lock')==ls[0].stem,'row lock id')
if warning:
 # Root-level fixture tests also lie outside core/, landing/ and jobs/.
 # The soft reset makes bridge66 a changed candidate only in warnings-local.
 paths=["outside/test_committed66.py","outside/test_new66.py","tests/test_bridge66.py","tests/test_fresh66.py"] if mode=="warnings-local" else ["outside/test_new66.py","tests/test_fresh66.py"]
 listing=", ".join(paths[:3])+(' and '+str(len(paths)-3)+' more' if len(paths)>3 else '')
 file_warning="shipcraft: warning: "+str(len(paths))+" changed test file(s) match no suite's globs and are not locked: "+listing+"; widen a suite's globs, or add a [[suite]] for them (when the base has a .shipcraft.toml, CI judges a PR by the base's, so a new suite goes in a PR of its own first)"
 suite_warning="shipcraft: warning: the lock has cases in suite(s) absent from "+chosen+"'s .shipcraft.toml: jobs; CI judges a PR by its base's config and will refuse them as case-missing; bring the suite to "+chosen+" in a PR of its own, then rebase this branch"
 want([s for s in p.stderr.splitlines() if s.startswith('shipcraft: warning:')]==[file_warning,suite_warning],'warnings must read chosen commit and name same short base: '+p.stderr)
# A resolving candidate is never reconsidered after merge-base failure.
if mode in ('unrelated','unrelated-first'):
 calls=[json.loads(s) for s in trace.read_text().splitlines()]
 want(not any('refs/heads/main^{commit}' in a for a in calls),'merge-base failure tried next candidate')
if mode.endswith('-first') and mode!='unrelated-first':
 index=next(i for i,(label,_,_) in enumerate(refs) if mode==label+'-first')
 calls=[json.loads(s) for s in trace.read_text().splitlines()]
 for _,later,_ in refs[index+1:]: want(not any(later+'^{commit}' in a for a in calls),'tried later candidate after success: '+later)
 resolutions=[a for a in calls if a and a[0]=='rev-parse' and any(s.endswith('^{commit}') for s in a)]
 expected=['HEAD^{commit}']+[ref+'^{commit}' for _,ref,_ in refs[:index+1]]
 want([a[-1] for a in resolutions]==expected and all(set(a[1:-1])=={'--verify','-q'} for a in resolutions),'resolve once, quietly, in candidate order; reuse the chosen id: '+repr(resolutions))
version=re.search(r'(?m)^version = "([^"]+)"',Path(manifest).read_text()).group(1)
want(run(binary,'--version').stdout.strip().startswith('shipcraft '+version),'version differs from Cargo manifest')
assert not errors,'\n'.join(errors)
PY66
  pass
}
