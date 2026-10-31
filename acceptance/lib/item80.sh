# Item 80: real init and real Git repositories; public commands only.
item80_langs() { echo python; }
item80_cases() {
  local c
  for c in main husky-all config gitkeep red-brief green-brief husky-msg husky-post precommit lefthook dot-lefthook lefthook-yaml dot-lefthook-yaml ignored directory dangling unborn-one nested all-flag later-build later-check log-fails redo-husky redo-log-fails unreadable loop enotdir absent-briefs tracked-changed staged-config staged-deleted excluded first-husky precedence-open precedence-no-config precedence-invalid precedence-redo tree-exit tree-malformed tree-signal index-exit index-malformed index-signal head-exit head-signal tree-once index-once; do echo "v1-80.$c"; done
}
item80_case() {
  EXPECT="item 80: ${CASE#v1-80.}"
  v1_start codex claude
  must_accept 'item 80 install contract' cmd "$PY" - "${CASE#v1-80.}" "$(command -v shipcraft)" <<'PY80'
import ast,errno,json,os,shlex,shutil,signal,subprocess,sys
from pathlib import Path
mode,binary=sys.argv[1:]
errors=[]
def want(v,msg):
 if not v: errors.append(msg)
def run(*args,ok=True,env=None):
 p=subprocess.run(args,input='',capture_output=True,text=True,timeout=90,env=env)
 print('$',shlex.join(args),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 if ok: assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr)
 return p
def git(*args): return run('git',*args).stdout.strip()
def write(path,text):
 p=Path(path); p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text)
def locks(): return {str(p):p.read_bytes() for p in Path('.shipcraft/locks').glob('*.json')}
def rows():
 p=Path('.git/shipcraft/runs.jsonl')
 return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def commit(msg):
 git('add','-A'); git('commit','-qm',msg)
base=['.shipcraft.toml','.shipcraft/locks/.gitkeep','.shipcraft/briefs/red.md','.shipcraft/briefs/green.md']
paths={'config':base[0],'gitkeep':base[1],'red-brief':base[2],'green-brief':base[3],
 'husky-msg':'.husky/commit-msg','husky-post':'.husky/post-commit','precommit':'.pre-commit-config.yaml',
 'lefthook':'lefthook.yml','dot-lefthook':'.lefthook.yml','lefthook-yaml':'lefthook.yaml','dot-lefthook-yaml':'.lefthook.yaml'}
husky=mode in ('husky-msg','husky-post','husky-all','first-husky','redo-husky','redo-log-fails','unreadable','loop')
if mode in ('first-husky','unborn-one'):
 # The base project dependencies remain ignored; its history alone is removed.
 shutil.rmtree('.git'); git('init','-q','-b','main')
if husky:
 # Real husky 9.1.7 launcher bytes shared with item 25, never invented output.
 source=(Path(os.environ['ACEITE'])/'lib/item25.sh').read_text().split("<<'PY25'\n",1)[1].split('\nPY25',1)[0]
 constants={}
 for n in ast.parse(source).body:
  if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id in ('HUSKY_H','HUSKY_LAUNCHER') for t in n.targets):
   exec(compile(ast.Module(body=[n],type_ignores=[]),'item25-fixture','exec'),constants)
 git('config','core.hooksPath','.husky/_')
 write('.husky/_/h',constants['HUSKY_H'])
 for event in ('commit-msg','post-commit'):
  write('.husky/_/'+event,constants['HUSKY_LAUNCHER']); Path('.husky/_/'+event).chmod(0o755)
 write('.husky/_/.gitignore','*\n')
if mode=='precommit': write(paths[mode],'repos:\n  - repo: local\n    hooks: []\n')
if mode in ('lefthook','dot-lefthook','lefthook-yaml','dot-lefthook-yaml'):
 write(paths[mode],'pre-commit:\n  commands:\n    lint:\n      run: echo ok\n')
run(binary,'init')
install=base+(['.husky/commit-msg','.husky/post-commit'] if husky else [paths[mode]] if mode in ('precommit','lefthook','dot-lefthook','lefthook-yaml','dot-lefthook-yaml') else [])
# Keep the init config grammar and runner; instrument real build/check/pytest execution.
config=Path(base[0]); text=config.read_text()
text=text.replace('test_command = ', 'check = "echo CHECK80 >&2; touch .git/check80"\ntest_command = ',1)
text+='\n[build]\ncommand = "echo BUILD80 >&2; touch .git/build80"\n'
config.write_text(text)
write('tests/conftest.py','from pathlib import Path\nPath(".git/suite80").touch()\n')
# Commit setup with a passing suite and no lock. Each targeted path is then genuinely absent from HEAD/index.
accept=mode in ('enotdir','absent-briefs','tracked-changed','staged-config','staged-deleted','excluded','first-husky','tree-once','index-once')
early=mode.startswith('precedence-')
fault=mode.startswith(('tree-','index-','head-')) and not mode.endswith('-once')
redo=mode in ('redo-husky','redo-log-fails')
if mode=='first-husky': git('add','-A')
elif mode in ('main','husky-all'): pass
elif mode=='unborn-one':
 git('add','-A'); git('rm','--cached','--',base[3])
elif mode in paths:
 git('add','-A'); git('rm','--cached','--',paths[mode])
else:
 if redo:
  saved_post=Path('.husky/post-commit').read_text(); Path('.husky/post-commit').unlink()
 commit('chore: install80')
 if mode in ('staged-config','staged-deleted') or (mode.startswith('index-') and mode!='index-once'):
  # Move HEAD back to a genuine pre-install commit, keeping its install in the index.
  git('reset','--soft','HEAD^')
 if mode=='index-once':
  git('rm','--cached','--',base[3]); git('commit','-qm','chore: historical install missing green brief80'); git('add','--',base[3])
 if mode in ('ignored','directory','dangling','nested','all-flag','later-build','later-check','log-fails'):
  git('rm','--cached','--',base[3]); git('commit','-qm','chore: historical install without green brief')
 if mode in ('unreadable','loop'):
  git('rm','--cached','--','.husky/commit-msg','.husky/post-commit'); git('commit','-qm','chore: hook integration absent in HEAD')
 # Cleanup instrument markers left by setup hooks, never erase a Shipcraft-owned path.
for name in ('build80','check80','suite80'): Path('.git/'+name).unlink(missing_ok=True)
write('value80.py','def value():\n    return False\n')
write('tests/test_install80.py','from value80 import value\ndef test_install80():\n    assert value()\n')
if mode=='first-husky': git('add','-A')
if not accept and not early: write('outside/test_warning80.py','# deliberately outside tests/**\n')
expected=[]; code='install-not-committed'; args=[]
if mode in ('main','husky-all'): expected=install
elif mode in paths: expected=[paths[mode]]
elif mode=='unborn-one': expected=[base[3]]
elif mode in ('ignored','directory','dangling','nested','all-flag','later-build','later-check','log-fails'):
 expected=[base[3]]
 if mode=='ignored':
  with Path('.git/info/exclude').open('a') as f:f.write('\n'+base[3]+'\n')
 if mode=='directory': Path(base[3]).unlink(); Path(base[3]).mkdir(); write(base[3]+'/sentinel','keep80')
 if mode=='dangling': Path(base[3]).unlink(); Path(base[3]).symlink_to('missing80')
 if mode=='all-flag': args=['--all']
 if mode=='later-build': config.write_text(config.read_text().replace('echo BUILD80 >&2; touch .git/build80','echo BUILD80 >&2; touch .git/build80; exit 7'))
 if mode=='later-check': config.write_text(config.read_text().replace('echo CHECK80 >&2; touch .git/check80','echo CHECK80 >&2; touch .git/check80; exit 7'))
 if mode=='nested': Path('deep/nested').mkdir(parents=True)
elif mode in ('unreadable','loop'):
 expected=['.husky/commit-msg','.husky/post-commit']
 shutil.rmtree('.husky')
 if mode=='unreadable':
  # A two-link cycle fails even when the caller can bypass permissions.
  Path('.husky').symlink_to('.git/husky-cycle80')
  Path('.git/husky-cycle80').symlink_to('../.husky')
 else:
  Path('.husky').symlink_to('.husky')
 for name in expected:
  try: os.lstat(name)
  except OSError as error:
   assert error.errno==errno.ELOOP,('fixture must produce ELOOP',name,error)
  else: raise AssertionError('fixture lstat unexpectedly succeeded: '+name)
elif mode=='enotdir': write('.husky','regular file80\n')
elif mode=='absent-briefs':
 for name in base[1:]:
  git('rm','--',name)
 git('commit','-qm','chore: pre-brief install')
elif mode=='tracked-changed': config.write_text(config.read_text()+'\n# changed only in tree80\n')
elif mode=='staged-deleted': Path(base[3]).unlink()
elif mode=='excluded':
 write('AGENTS.md','untracked agent80\n'); write('CLAUDE.md','untracked claude80\n')
 git('rm','--cached','--','AGENTS.md','CLAUDE.md'); git('commit','-qm','chore: docs absent from HEAD')
 for name in ('lefthook-local.yml','.lefthook-local.yaml','package.json','package-lock.json','.husky/_/extra80'):
  write(name,'untracked excluded80\n')
if redo or mode=='precedence-open':
 # A real RED creates and seals its own lock before a real commit; never forge a lock.
 run(binary,'red'); commit('test: first RED80')
 if redo:
  write('.husky/post-commit',saved_post)
  expected=['.husky/post-commit']; args=['--redo']
 else:
  # An additional untracked install cannot outrank lock-open.
  write('.husky/commit-msg','shipcraft check --commit-msg "$@"\n'); code='lock-open'
 for name in ('build80','check80','suite80'): Path('.git/'+name).unlink(missing_ok=True)
if mode=='precedence-no-config': config.unlink(); write('.husky/commit-msg','untracked80\n'); code='no-config'
if mode=='precedence-invalid': config.write_text('suite = [\n'); write('.husky/commit-msg','untracked80\n'); code='config-invalid'
if mode=='precedence-redo': write('.husky/commit-msg','untracked80\n'); args=['--redo']; code='redo-without-lock'
if mode in ('log-fails','redo-log-fails'):
 log=Path('.git/shipcraft/runs.jsonl'); log.unlink(missing_ok=True); log.mkdir(parents=True,exist_ok=True)
# Transparent Git shim: trace argv, fail only the new preflight operation, forward all other calls.
env=None; trace=Path('.git/trace80').resolve()
if fault or mode.endswith('-once'):
 realgit=shutil.which('git'); bindir=Path('.git/bin80').resolve(); bindir.mkdir()
 operation='ls-tree' if mode.startswith('tree-') else 'ls-files' if mode.startswith('index-') else 'rev-parse'
 target="a and a[0]=='"+operation+"'" if operation!='rev-parse' else "a==['rev-parse','-q','--verify','HEAD']"
 action='pass'
 if mode.endswith('-exit'): action='sys.exit(2)'
 if mode.endswith('-malformed'): action='sys.stdout.write(".shipcraft.toml"); sys.exit(0)'
 if mode.endswith('-signal'): action='os.kill(os.getpid(),signal.SIGTERM)'
 wrapper='#!'+sys.executable+'\nimport os,sys,json,signal\na=sys.argv[1:]\nwith open('+repr(str(trace))+',"a") as f: f.write(json.dumps(a)+"\\n")\n'
 wrapper+='if '+target+': '+action+'\nos.execv('+repr(realgit)+',['+repr(realgit)+']+a)\n'
 shim=bindir/'git'; shim.write_text(wrapper); shim.chmod(0o755)
 env=dict(os.environ,PATH=str(bindir)+os.pathsep+os.environ['PATH'])
before=rows(); original=locks(); index=git('ls-files','--stage'); head=run('git','rev-parse','-q','--verify','HEAD',ok=False).stdout
try:
 if mode=='nested': os.chdir('deep/nested')
 p=run(binary,'red',*args,ok=False,env=env)
finally:
 if mode=='nested': os.chdir('../..')
lines=(p.stdout+p.stderr).splitlines()
if accept:
 want(p.returncode==0,'staged/committed/absent install rejected: '+repr((p.returncode,p.stdout,p.stderr)))
 want(len(locks())==1,'accepted RED did not write its real open lock')
 if mode=='first-husky' and p.returncode==0:
  commit('test: unborn husky RED80')
  lf=next(iter(locks())); want(json.loads(git('show','HEAD:'+lf))['state']=='open','first RED commit did not retain open lock')
  write('value80.py','def value():\n    return True\n'); commit('feat: GREEN80')
  want(json.loads(git('show','HEAD:'+lf))['state']=='closed','first GREEN commit did not close lock')
else:
 want(p.returncode==(2 if fault else 1),'wrong exit '+str(p.returncode))
 want(locks()==original,'early refusal/error changed or wrote a lock')
 want(not p.stdout,'early refusal/error printed stdout: '+p.stdout)
 want(not any(Path('.git/'+n).exists() for n in ('build80','check80','suite80')),'build/check/suite ran before refusal')
 want(git('ls-files','--stage')==index,'refusal changed index')
 want(run('git','rev-parse','-q','--verify','HEAD',ok=False).stdout==head,'refusal changed HEAD')
 if fault:
  want(any(s.startswith('shipcraft: error: ') for s in lines),'Git failure must remain ordinary error')
 elif not early:
  expected=sorted(expected,key=lambda s:s.encode())
  first='shipcraft refused: the Shipcraft install is not committed or staged: '+', '.join(expected)
  if mode in ('unreadable','loop'):
   want(len(lines)==3 and lines[0].startswith('shipcraft refused: the Shipcraft install is not committed or staged: '),'unreadable refusal shape')
   if lines:
    # OS error text varies; require each path followed by its own nonempty error.
    import re
    want(re.fullmatch(re.escape(first.split(': ',2)[0]+': '+first.split(': ',2)[1]+': ')+', '.join(re.escape(n)+r' \(could not be read: .+?\)' for n in expected),lines[0]) is not None,'unreadable path/error list: '+lines[0])
  else: want(len(lines)==3 and lines[0]==first,'exact refusal path list: '+repr(lines))
  why="Why: the lock protects .shipcraft.toml and the hook judges the commit's index against HEAD, so an install file the commit lacks reads as a locked file deleted, or a hook file created while the lock is open, and the RED commit is refused"
  nxt="Next: stage the install (`git add -- "+' '.join(expected)+"`), with the other files init's `shipcraft: ready. Commit ...` line named when they changed (AGENTS.md, CLAUDE.md, and package.json with its lockfile for a project install), or commit them; then run `shipcraft red"+(' --redo' if redo else '')+"` again"
  want(lines[1:]==[why,nxt],'exact Why/Next or redo guidance changed: '+repr(lines[1:]))
 else: want(len(lines)==3 and [s.split(':',1)[0] for s in lines]==['shipcraft refused','Why','Next'],'precedence refusal shape')
 if mode not in ('log-fails','redo-log-fails'):
  after=rows(); want(after[:len(before)]==before and len(after)==len(before)+1,'exactly one appended run-log row')
  if len(after)>len(before):
   r=after[-1]; want(r.get('layer')=='red' and r.get('result')==('error' if fault else 'refused'),'row verdict '+repr(r))
   if not fault:
    want(r.get('code')==code,'wrong refusal precedence/code '+repr(r))
    keys={'at','branch','code','commit','layer','lock','result','secs','reason'}|({'redo'} if '--redo' in args else {'kind','reported_at','fixes_release'})
    want(set(r)==keys,'refusal row shape: '+repr(r))
   want(not {'selection','selected_files','fallback'}&r.keys(),'early row contains selection fields')
   if '--redo' in args: want(r.get('redo') is True,'redo row missing redo:true')
   elif not fault: want((r.get('kind'),r.get('reported_at'),r.get('fixes_release'))==('feature',None,None),'non-redo feature metadata')
if mode.endswith('-once'):
 calls=[json.loads(s) for s in trace.read_text().splitlines()]
 trees=[a for a in calls if a and a[0]=='ls-tree']; indices=[a for a in calls if a and a[0]=='ls-files' and '--cached' in a]
 expected_tree=['ls-tree','-z','--name-only','HEAD','--']+sorted(install,key=lambda s:s.encode())
 want(any(a[:5]==expected_tree[:5] and set(a[5:])==set(install) for a in trees),'one batched install ls-tree with existing paths: '+repr(trees))
 want(len([a for a in trees if a[:5]==expected_tree[:5] and set(a[5:])==set(install)])==1,'install ls-tree repeated')
 if mode=='tree-once': want(not indices,'index queried although HEAD holds every install path')
 else: want(len(indices)==1 and indices[0][:4]==['ls-files','-z','--cached','--'] and set(indices[0][4:])=={base[3]},'one batched index query for HEAD-missing paths: '+repr(indices))
assert not errors,'\n'.join(errors)

PY80
  pass
}
