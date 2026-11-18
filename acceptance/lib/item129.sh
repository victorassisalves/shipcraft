# Item 129: install selection, real pytest and local Git only.
item129_langs() { echo python; }
item129_cases() {
 local c
 for c in main staged tip-installed redo all no-base unchanged readded modified modified-tip modified-refusal retyped legacy-kept legacy-removed legacy-tip-only legacy-near legacy-folder read-exit read-signal support log-fails build-fails write-fails untracked explicit; do echo "v1-129.$c"; done
}
item129_case() {
  EXPECT="item 129: ${CASE#v1-129.}"; v1_start
  must_accept 'install selection contract' cmd "$PY" - "${CASE#v1-129.}" "$(command -v shipcraft)" <<'PY129'
import hashlib,json,os,shlex,shutil,subprocess,sys
from pathlib import Path
mode,binary=sys.argv[1:]
Path('project129').mkdir(); os.chdir('project129')
def run(*args,ok=True):
 p=subprocess.run(args,capture_output=True,text=True,timeout=90)
 print('$',shlex.join(args),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 if ok: assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr)
 return p
def git(*args): return run('git',*args).stdout.strip()
def commit(message):
 git('add','-A'); git('-c','core.hooksPath=/dev/null','commit','-qm',message)
def write(path,text):
 p=Path(path); p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text)

def locks(): return sorted(Path('.shipcraft/locks').glob('*.json'))
def rows():
 p=Path('.git/shipcraft/runs.jsonl')
 return [json.loads(x) for x in p.read_text().splitlines() if json.loads(x)['layer']=='red'] if p.is_file() else []
config='shipcraft_min = "0.0"\nlang = "python"\nrunner = "pytest"\ntest_command = "pytest --junitxml={junit} tests"\ntest_globs = ["tests/**"]\n[execution]\nci = "local"\nreview = "off"\n[build]\ncommand = "test ! -f .git/build-fail"\n'
# Each exact arm owns its expected outcome and fixture variant.
at_base=False; legacy=None; action=None; reason=None; count=1; code=''; args=[]; fault=None; read=True
if mode=='main': pass
elif mode=='staged': action='stage'
elif mode=='tip-installed': action='tip-install'
elif mode=='redo': action='redo'
elif mode=='all': args=['--all']; reason='--all'; count=0; read=False
elif mode=='no-base': args=['--base','missing129']; reason='no base'; count=0; read=False
elif mode=='unchanged': at_base=True; read=False
elif mode=='readded': at_base=True; action='readd'; read=False
elif mode=='modified': at_base=True; action='modify'; reason='config changed'; count=0; read=False
elif mode=='modified-tip': at_base=True; action='modify-tip'; reason='config changed'; count=0; read=False
elif mode=='modified-refusal': at_base=True; action='modify-pass'; reason='config changed'; count=0; code='red-already-passes'; read=False
elif mode=='retyped': at_base=True; action='retype'; reason='config changed'; count=0; read=False
elif mode=='legacy-kept': legacy='.sc2.toml'; reason='config changed'; count=0
elif mode=='legacy-removed': legacy='.sc2.toml'; action='remove-legacy'; reason='config changed'; count=0
elif mode=='legacy-tip-only': action='tip-legacy'
elif mode=='legacy-near': legacy='.sc2.toml.extra'
elif mode=='legacy-folder': legacy='.sc2.toml/child'
elif mode=='read-exit': fault='exit'; reason='config changed'; count=0
elif mode=='read-signal': fault='signal'; reason='config changed'; count=0
elif mode=='support': config=config.replace('["tests/**"]','["tests/**", "AGENTS.md"]'); count=2
elif mode=='log-fails': action='log-fail'
elif mode=='build-fails': action='build-fail'; code='build-failed'
elif mode=='write-fails': action='write-fail'
elif mode=='untracked': action='untracked'; code='install-not-committed'; read=False; count=0
elif mode=='explicit': action='explicit'
else: raise AssertionError('unrouted case '+mode)
git('init','-q','-b','main')
write('.gitignore','__pycache__/\n.pytest_cache/\n')
for name in ('a','b','c'):
 write('tests/test_'+name+'.py','from pathlib import Path\nPath(".git/collected_'+name+'").touch()\ndef test_'+name+'():\n assert True\n')
if legacy: write(legacy,'# legacy tree entry129\n')
if at_base:
 write('.shipcraft.toml',config); run(binary,'init','--lang','python')
 config=Path('.shipcraft.toml').read_text()
 if action=='retype':
  Path('.shipcraft.toml').rename('config129')
  Path('.shipcraft.toml').symlink_to('config129')
commit('base tests129')
base=git('rev-parse','HEAD')
origin=Path('../origin.git').resolve()
git('init','--bare','-q',str(origin)); git('remote','add','origin',str(origin))
git('push','-q','-u','origin','main'); git('symbolic-ref','refs/remotes/origin/HEAD','refs/remotes/origin/main')
git('checkout','-qb','feature/item129')
if not at_base:
 write('.shipcraft.toml',config); run(binary,'init','--lang','python')
 if action=='remove-legacy': Path('.sc2.toml').unlink()
 if action=='stage': git('add','-A')
 elif action=='untracked':
  git('add','-A'); git('reset','-q','--','.shipcraft.toml')
 else: commit('install Shipcraft129')
if action in ('modify','modify-tip','modify-pass'):
 write('.shipcraft.toml',config+'\n# branch config129\n')
if action=='readd':
 Path('.shipcraft.toml').unlink(); write('.shipcraft.toml',config); git('add','.shipcraft.toml')
if action=='retype':
 Path('.shipcraft.toml').unlink(); write('.shipcraft.toml',config)
if action in ('tip-install','tip-legacy','modify-tip','explicit'):
 # Diverge the real base branch; its tip must not replace the merge base.
 current=Path('.shipcraft.toml').read_text()
 if at_base: write('.shipcraft.toml',config)
 git('checkout','-q','main')
 if action=='tip-legacy': write('.sc2.toml','# only at tip129\n')
 else: write('.shipcraft.toml',config+'\n# default tip129\n')
 commit('default branch advanced129')
 git('push','-q','origin','main')
 tip=git('rev-parse','HEAD'); assert tip!=base
 git('checkout','-q','feature/item129'); write('.shipcraft.toml',current)
 if action=='explicit': args=['--base',base]
write('tests/test_new.py','def test_new():\n assert '+str(action=='modify-pass')+'\ndef test_control():\n assert True\n' if action=='redo' else 'def test_new():\n assert '+str(action=='modify-pass')+'\n')
if action=='redo':
 # Establish a genuinely narrowed old lock using an explicit install commit.
 run(binary,'red','--base','HEAD'); commit('opening RED129')
 write('tests/test_new.py',Path('tests/test_new.py').read_text()+'\n# redo repair description129\n')
 args=['--redo']
for marker in Path('.git').glob('collected_*'): marker.unlink()
# Every case uses this transparent shim; unchanged proves its forwarding route.
realgit=shutil.which('git'); trace=Path('.git/trace129').resolve(); bindir=Path('.git/bin129').resolve(); bindir.mkdir()
target=['ls-tree','-r','-z','--name-only',base,'--','.sc2.toml']
wrapper='#!'+sys.executable+'\nimport os,sys,json,signal\nraw=sys.argv[1:]\na=list(raw)\nwhile a and a[0] in ("-C","--literal-pathspecs"):\n a=a[2:] if a[0]=="-C" else a[1:]\n'
wrapper+='with open('+repr(str(trace))+',"a") as f: f.write(json.dumps(a)+"\\n")\n'
wrapper+='if a=='+repr(target)+':\n'
wrapper+=(' sys.exit(73)\n' if fault=='exit' else ' os.kill(os.getpid(),signal.SIGTERM)\n' if fault=='signal' else ' pass\n')
wrapper+='os.execv('+repr(realgit)+',['+repr(realgit)+']+raw)\n'
write(bindir/'git',wrapper); (bindir/'git').chmod(0o755)
os.environ['PATH']=str(bindir)+os.pathsep+os.environ['PATH']
if fault:
 probe=run('git',*target,ok=False)
 assert probe.returncode==(73 if fault=='exit' else -15),'fault shim did not reproduce its designated failure'
 trace.unlink()
before=rows()
if action=='log-fail':
 log=Path('.git/shipcraft/runs.jsonl'); log.unlink(missing_ok=True); log.mkdir(parents=True)
if action=='build-fail': Path('.git/build-fail').touch()
if action=='write-fail': Path('.shipcraft/locks').chmod(0o555)
try: p=run(binary,'red',*args,ok=False)
finally:
 if action=='write-fail': Path('.shipcraft/locks').chmod(0o755)
ls=locks(); d=json.loads(ls[0].read_text()) if ls else None
r=rows()[-1] if rows() else None
print('OBSERVED cases='+repr(d['cases'] if d else None)+' row='+repr(r),flush=True)
errors=[]
def want(value,message):
 if not value: errors.append(message)
calls=[json.loads(x) for x in trace.read_text().splitlines()]
legacy_calls=[a for a in calls if a and a[0]=='ls-tree' and a[-1:]==['.sc2.toml']]
if mode=='unchanged':
 want(any('HEAD^{commit}' in a for a in calls),'forwarding shim must observe real base resolution')
 want(any(a and a[0]=='diff' for a in calls),'forwarding shim must observe real changed-path read')
want(legacy_calls==([target] if read else []),'legacy reader exact single merge-base lookup: '+repr(legacy_calls))
if action=='untracked':
 want(p.returncode==1 and not ls and not p.stdout,'install guard precedes selection')
 want(r['code']==code and not {'selection','selected_files','fallback'}&r.keys(),'early refusal row')
 lines=p.stderr.splitlines()
 want(len(lines)==3 and all(x.startswith(t) for x,t in zip(lines,('shipcraft refused:','Why:','Next:'))),'early three-line refusal')
 want(not list(Path('.git').glob('collected_*')),'early guard must not run suite')
else:
 notice='shipcraft: red ran every suite: '+reason if reason else f'shipcraft: red ran the changed test files: {count} of {6 if mode=="support" else 5}'
 if reason=='config changed': notice+=' (.shipcraft.toml differs from the merge base '+base[:7]+')'
 want(p.stdout.splitlines().count(notice)==1 and notice not in p.stderr,'exact stdout selection: '+notice)
 if action!='log-fail':
  want(len(rows())==len(before)+1 and rows()[:-1]==before,'one RED row, history preserved')
  keys={'at','branch','code','commit','fallback','layer','lock','result','secs','selected_files','selection'}
  keys|={'redo'} if action=='redo' else {'kind','reported_at','fixes_release'}
  if code: keys.add('reason')
  elif action!='write-fail': keys.add('rerun_dropped')
  want(set(r)==keys,'unchanged row fields: '+repr(r))
  if not code and action!='write-fail': want(r['result']=='passed' and r['code']=='','successful row verdict')
  want((r.get('selection'),r.get('selected_files'),r.get('fallback'))==('all' if reason else 'changed',count,reason),'selection row '+repr(r))
 if action=='write-fail':
  want(p.returncode==2 and not ls and r['result']=='error','failed lock write must leave no lock and record error')
 elif code:
  want(p.returncode==1 and not ls and r['code']==code,'later refusal preserves verdict/no lock')
  lines=[x for x in (p.stdout+p.stderr).splitlines() if x][-3:]
  want(len(lines)==3 and all(x.startswith(t) for x,t in zip(lines,('shipcraft refused:','Why:','Next:'))),'three refusal lines')
 else:
  want(p.returncode==0 and len(ls)==1,'one successful lock')
  if d:
   expected=['tests.test_new::test_new']
   if reason: expected+=['tests.test_'+n+'::test_'+n for n in ('a','b','c')]
   if action=='redo': expected+=['tests.test_new::test_control']
   want(set(d['cases'])==set(expected),'lock cases: '+repr(d['cases']))
   want(d['failing_at_red']==['tests.test_new::test_new'],'exact failures')
   want(d['controls']==(['tests.test_new::test_control'] if action=='redo' else []),'controls')
   protected={'.shipcraft.toml'}|{'tests/test_'+n+'.py' for n in ('a','b','c','new')}
   if mode=='support': protected.add('AGENTS.md')
   want(set(d['files'])==protected,'whole protection set')
   for f,h in d['files'].items(): want(h=='sha256:'+hashlib.sha256(Path(f).read_bytes()).hexdigest(),'hash '+f)
 if not reason and action!='build-fail':
  want(not list(Path('.git').glob('collected_*')),'untouched passing files executed')
 if mode=='support':
  want('shipcraft: red did not run the tests that may use the changed support file(s): AGENTS.md; CI runs them' in p.stdout.splitlines(),'install path remains support')
assert not errors,'\n'.join(errors)
PY129
  pass
}
