# Item 67: custom JUnit commands; only disposable projects and public commands.
item67_langs() { echo core; }
item67_cases() {
  local c
  for c in plain normalized onboarding onboarding-none onboarding-append typescript typescript-workspace kept kept-github quoted embedded split-globs literal-globs literal-classes github github-free rollback rollback-kept red red-space no-report no-report-exit detection detection-kept detection-multiple detection-multiple-reverse version; do echo "v1-67.$c"; done
  for c in repeat-command repeat-lang missing-command-value missing-glob-value missing-lang-value flag-as-value syntax-legacy syntax-lang syntax-glob syntax-hook legacy legacy-invalid command-no-lang glob-no-lang command-python glob-node missing-command missing-glob empty-command no-placeholder twice-placeholder whitespace nbsp control del c1 invalid-empty invalid-dot invalid-absolute invalid-parent invalid-inner-parent glob-order glob-order-reverse lang-before-glob glob-before-hook foreign-hook kept-invalid; do echo "v1-67.refuse-$c"; done
}
item67_case() {
  EXPECT="item 67: ${CASE#v1-67.}"
  case "$CASE" in *onboarding-none) v1_start ;; *) v1_start codex claude ;; esac
  export ST
  must_accept 'item 67 acceptance contract' cmd "$PY" - "${CASE#v1-67.}" "$(command -v shipcraft)" "$ACEITE/../nucleo/Cargo.toml" "$CW" <<'PY67'
import json,os,re,shutil,stat,subprocess,sys
from pathlib import Path
try: import tomllib
except ImportError: import tomli as tomllib
case,binary,manifest,cw=sys.argv[1:]; binary=str(Path(binary).resolve())
version=tomllib.loads(Path(manifest).read_text())['package']['version']
def run(*args,ok=True):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,timeout=90)
 print('$',repr(args),'[rc='+str(p.returncode)+']\n'+(p.stdout+p.stderr).decode(errors='replace'),flush=True)
 if ok: assert p.returncode==0,'command failed: '+(p.stdout+p.stderr).decode(errors='replace')
 return p
def write(path,data,mode=None):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
 if mode is not None:p.chmod(mode)
def snapshot(stable_git=False):
 def entry(p):
  return (stat.S_IMODE(p.lstat().st_mode), 'link',os.readlink(p)) if p.is_symlink() else (stat.S_IMODE(p.stat().st_mode),'file',p.read_bytes()) if p.is_file() else (stat.S_IMODE(p.stat().st_mode),'dir')
 # Refusals preserve working-tree bytes and Git state, not Git's cache bytes.
 result={str(p):entry(p) for p in Path('.').rglob('*') if not stable_git or p.parts[0]!='.git'}
 if stable_git:
  # Keep byte-level coverage for hooks and Shipcraft's own Git-local writes.
  for name in ('.git/hooks','.git/shipcraft'):
   p=Path(name)
   if p.exists() or p.is_symlink():
    result[str(p)]=entry(p)
    if p.is_dir() and not p.is_symlink():
     result.update((str(child),entry(child)) for child in p.rglob('*'))
  readers=[('rev-parse','HEAD'),('symbolic-ref','-q','HEAD'),('for-each-ref',),('ls-files','-s'),('status','--porcelain=v1','-z','--untracked-files=all'),('config','--local','--list')]
  for args in readers:
   p=run('git','--no-optional-locks',*args,ok=False)
   assert p.returncode==0 or (args[0]=='symbolic-ref' and p.returncode==1),('snapshot Git reader failed',args,p.returncode,text(p))
   result[('git',*args)]=(p.returncode,p.stdout)
 return result
def text(p):return (p.stdout+p.stderr).decode()
FULL="shipcraft init --lang other --command '<test command writing JUnit to {junit}>' --glob '<test files>'"
CMD='sh tests/run.sh {junit}'
GOOD=['--lang','other','--command',CMD,'--glob','tests/**']
def init(args=GOOD,ok=True):return run(binary,'init',*args,ok=ok)
def refusal(p,next_full=True,needle=None,init_only=True):
 assert p.returncode==1,('expected semantic refusal exit 1',p.returncode,text(p))
 lines=[s for s in text(p).splitlines() if s.strip()]
 if not init_only:lines=lines[-3:]
 assert len(lines)==3 and all(s.startswith(k) for s,k in zip(lines,['shipcraft refused:','Why:','Next:'])),lines
 if next_full:assert FULL in lines[-1],lines
 else:assert FULL not in lines[-1],lines
 if needle:assert needle in '\n'.join(lines[:2]),(needle,lines)
 assert 'provider' not in text(p)
 if init_only:assert not Path('.git/shipcraft/runs.jsonl').exists()
 return lines
root=Path(cw)/('project 67' if case=='red-space' else 'project67');root.mkdir();os.chdir(root)
run('git','init','-q','-b','main');write('README.md','Markerless project\n')
run('git','add','.');run('git','commit','-q','-m','fixture: markerless repository')
write('.git/shipcraft/sentinel',b'keep67\r\n\x00')
if case=='version':
 p=run(binary,'--version');assert re.fullmatch(r'shipcraft '+re.escape(version)+r' \([0-9a-f]{12}\)\n',p.stdout.decode());sys.exit()
if case.startswith('detection'):
 if 'multiple' in case:
  # Creation order cannot decide the language.
  for name,data in ([('requirements.txt','pytest'),('go.mod','module example.com/m\n\ngo 1.21\n')] if not case.endswith('reverse') else [('go.mod','module example.com/m\n\ngo 1.21\n'),('requirements.txt','pytest')]):write(name,data)
 if case=='detection-kept':write('.shipcraft.toml','test_command = "sh tests/run.sh {junit}"\ntest_globs = ["tests/**"]\nfilter = "command"\n')
 before=snapshot();p=init([],False);refusal(p)
 assert snapshot()==before,'refused init changed files'
 if 'multiple' not in case:
  assert 'could not recognize' in text(p).lower(),text(p)
  assert 'JUnit' in text(p).split('Why:',1)[1].split('Next:',1)[0],text(p)
 else:assert re.search('more than one|multiple',text(p),re.I),text(p)
 sys.exit()
if case.startswith('refuse-'):
 c=case[7:];args=GOOD[:];syntax=False;full=True;needle=None
 matrix={
 'repeat-command':GOOD+['--command',CMD], 'repeat-lang':GOOD+['--lang','other'],
 'missing-command-value':['--lang','other','--command'], 'missing-glob-value':['--lang','other','--command',CMD,'--glob'],
 'missing-lang-value':['--lang'], 'flag-as-value':['--lang','other','--command','--glob','x'],
 'command-no-lang':['--command',CMD,'--glob','tests/**'], 'glob-no-lang':['--glob','tests/**'],
 'command-python':['--lang','python','--command',CMD,'--glob','tests/**'],
 'glob-node':['--lang','node','--glob','tests/**'],
 'missing-command':['--lang','other','--glob','tests/**'], 'missing-glob':['--lang','other','--command',CMD],
 }
 commands={'empty-command':'','no-placeholder':'sh tests/run.sh','twice-placeholder':'run {junit} {junit}', 'whitespace':' \u2003{junit} ', 'nbsp':'\u00a0{junit}\u00a0','control':'run\t{junit}','del':'run\x7f {junit}','c1':'run\u0085{junit}'}
 globs={'invalid-empty':'','invalid-dot':'./','invalid-absolute':'/tests/**','invalid-parent':'../tests/**','invalid-inner-parent':'tests/../support/**'}
 if c in matrix:args=matrix[c]
 if c in ('command-no-lang','glob-no-lang','command-python','glob-node'):needle='--lang other'
 if c=='missing-command' or c in commands:needle='command'
 if c=='missing-glob':needle='glob'
 if c in commands:args=['--lang','other','--command',commands[c],'--glob','tests/**']
 if c in globs:args=['--lang','other','--command',CMD,'--glob',globs[c]];needle=globs[c] if c not in ('invalid-empty','invalid-dot') else 'glob'
 if c in ('repeat-command','repeat-lang','missing-command-value','missing-glob-value','missing-lang-value','flag-as-value') or c.startswith('syntax-'):syntax=True
 if c.startswith('syntax-'):
  args=GOOD+['--command',CMD]
  if c=='syntax-legacy':write('.sc2.toml','# legacy\n')
  if c=='syntax-lang':args=['--lang','other','--lang','python','--glob','tests/**']
  if c=='syntax-glob':args=GOOD+['--glob','../bad','--command',CMD]
  if c=='syntax-hook':write('.git/hooks/commit-msg','#!/bin/sh\necho foreign\n',0o755)
 if c in ('legacy','legacy-invalid'):
  write('.sc2.toml','# legacy67\n');args=['--lang','other'] if c=='legacy-invalid' else GOOD;full=False;needle='.sc2.toml'
 if c in ('glob-order','glob-order-reverse'):
  a,b=('../first67/**','/second67/**') if c=='glob-order' else ('/second67/**','../first67/**')
  args=GOOD+['--glob',a,'--glob',b];needle=a
 if c=='lang-before-glob':args=['--lang','other','--command','bad','--glob','../bad67'];needle='command'
 if c in ('glob-before-hook','foreign-hook'):
  write('.git/hooks/commit-msg','#!/bin/sh\necho foreign67\n',0o755)
  if c=='glob-before-hook':args=GOOD+['--glob','../bad67'];needle='../bad67'
  else:full=False
 if c=='kept-invalid':write('.shipcraft.toml','# kept67\n');args=['--lang','other','--command','bad','--glob','tests/**'];needle='command'
 before=snapshot(stable_git=True);p=init(args,False)
 if syntax:
  assert p.returncode==2,(p.returncode,text(p));assert text(p).startswith('shipcraft: error:'),text(p)
  assert not any(l.startswith('Next:') and FULL in l for l in text(p).splitlines()),text(p)
 else:
  lines=refusal(p,full,needle)
  if c=='foreign-hook':assert 'shipcraft check' in lines[-1],lines
  if c in ('glob-order','glob-order-reverse'):assert b not in '\n'.join(lines[:2]),lines
 assert snapshot(stable_git=True)==before,'refused init changed tree or git state'
 sys.exit()
# Successful custom init must neither execute the command nor infer a language runner.
args=GOOD[:];expected_globs=['tests/**'];command=CMD
if case=='normalized':
 expected_globs=['tests/**/*.case','support/?.sh','odd name/**'];args=['--lang','other','--command',CMD]
 for g in ['./tests//**/*.case','support//?.sh','tests/**/*.case','./odd name//**','./support/?.sh']:args+=['--glob',g]
if case in ('quoted','embedded'):
 command='runner --junit="{junit}"' if case=='quoted' else 'runner --junitxml={junit}'
 args=['--lang','other','--command',command,'--glob','tests/**']
if case=='split-globs':
 expected_globs=['**/*.test.ts','**/*.spec.ts'];args=['--lang','other','--command',CMD,'--glob',expected_globs[0],'--glob',expected_globs[1]]
if case in ('literal-globs','literal-classes'):
 expected_globs=['**/*.{test,spec}.ts','**/*.test.ts'] if case=='literal-globs' else ['tests/[ab].case','tests/?.case']
 args=['--lang','other','--command',CMD]
 for g in expected_globs:args+=['--glob',g]
if case.startswith('typescript'):
 write('tsconfig.json','{"files":[],"references":[{"path":"packages/a"}]}\n')
 write('packages/a/tsconfig.json','{"compilerOptions":{"composite":true},"files":["value.ts"]}')
 write('packages/a/value.ts','export const n = 1;\n')
 if case.endswith('workspace'):write('package.json','{"workspaces":["packages/*"]}');write('packages/a/package.json','{"devDependencies":{"vitest":"*"}}')
 run('git','add','.');run('git','commit','-q','-m','fixture: tracked references')
 write(Path(os.environ['PATH'].split(os.pathsep)[0])/'npx','#!/bin/sh\nprintf "%s\\n" "$*" >> "'+cw+'/npx67-calls"\nexit 0\n',0o755)
if case=='onboarding-append':write('AGENTS.md','Project rules67');write('CLAUDE.md','Claude rules67')
kept=case in ('kept','kept-github','rollback-kept')
if kept:
 write('.shipcraft.toml',b'# user67\r\ntest_command = "false {junit}"\r\ntest_globs = ["custom/**"]\r\nfilter = "command"\r\n[execution]\r\nci = "off"\r\nreview = "off"\r\n')
 original=Path('.shipcraft.toml').read_bytes()
if case in ('github','github-free','kept-github'):
 # Same gh state protocol and local bare remote as v1's --github cases.
 run('git','init','-q','--bare',str(Path(cw)/'origin67.git'));run('git','remote','add','origin',str(Path(cw)/'origin67.git'))
 st=Path(os.environ['ST']);write(st/'origin',str(Path(cw)/'origin67.git')+'\n')
 run('git','push','-q','origin','main');run('git','fetch','-q','origin');run('git','remote','set-head','origin','main')
 write(st/'protection','403\n' if case=='github-free' else 'none\n');args+=['--github']
if case.startswith('rollback'):
 write('.shipcraft','blocked67\r\n');before=snapshot();p=init(args,False)
 assert p.returncode==2,('late write failure must be exit 2',p.returncode,text(p))
 assert '.shipcraft' in text(p).split('shipcraft: error:',1)[-1],('did not reach late write failure',text(p))
 assert snapshot()==before,'late failure failed to restore bytes/modes'
 assert 'ready. Commit' not in text(p),text(p)
 sys.exit()
# Runner exists but must never be executed by init.
write('tests/run.sh','#!/bin/sh\nprintf ran\\n >> calls67\ncat > "$1" <<\'XML\'\n<testsuite tests="1" failures="1"><testcase classname="shell67" name="fails" file="tests/example.case"><failure message="expected RED">assertion failed</failure></testcase></testsuite>\nXML\nexit 1\n')
write('tests/example.case','expected RED67\n')
if case=='red-space':command='sh tests/run.sh --report={junit}';args=['--lang','other','--command',command,'--glob','tests/**'];write('tests/run.sh',Path('tests/run.sh').read_text().replace('"$1"','"${1#--report=}"'))
if case.startswith('no-report'):
 command='sh tests/run.sh {junit}';write('tests/run.sh','#!/bin/sh\necho ran >> calls67\nexit '+('37' if case.endswith('exit') else '0')+'\n')
state=Path('.git/shipcraft/sentinel').read_bytes();before_init=snapshot();p=init(args)
allowed={'.shipcraft.toml','AGENTS.md','CLAUDE.md','.git/hooks/commit-msg','.git/hooks/post-commit'}
assert all(k in allowed or k.startswith('.shipcraft/locks/') or v[-1]=='dir' for k,v in snapshot().items() if k not in before_init), 'init wrote an unexpected file or stub'
assert not Path('calls67').exists(),'init ran custom command'
assert not Path(cw,'npx67-calls').exists(),'other init invoked npx/tsc'
assert Path('.git/shipcraft/sentinel').read_bytes()==state and not Path('.git/shipcraft/runs.jsonl').exists(),'init changed run state'
c=tomllib.loads(Path('.shipcraft.toml').read_text())
if kept:
 assert Path('.shipcraft.toml').read_bytes()==original,'existing config rewritten'
 assert text(p).splitlines().count('shipcraft: .shipcraft.toml exists and was kept; --command and --glob only seed a new config')==1,text(p)
 assert text(p).strip().endswith('CI is off ([execution] ci = "off").'),text(p)
else:
 assert c['test_command']==command and c['test_globs']==expected_globs and c['filter']=='command',c
 assert all(k not in c for k in ('lang','runner','check','build','suite')),c
 assert c['shipcraft_min']=='.'.join(version.split('.')[:2]),c
 assert c['execution']['ci']=='local',c
 assert c['execution']['review']==('off' if case=='onboarding-none' else 'local'),c
 assert 'red' not in c.get('roles',{}) and 'green' not in c.get('roles',{}),c
 if case!='onboarding-none':assert c['roles']['review']=='codex' and isinstance(c['roles']['review'],str),c
assert Path('.shipcraft/locks').is_dir()
for hook,cmd in [('commit-msg','check --commit-msg'),('post-commit','close')]:
 f=Path('.git/hooks')/hook;assert os.access(f,os.X_OK) and cmd in f.read_text(),f
agents=Path('AGENTS.md').read_text();assert agents.count('<!-- shipcraft -->')==1 and '<!-- /shipcraft -->' in agents and 'codex exec' in agents and 'red --redo' in agents,agents
if case!='onboarding-none':
 imp='<!-- shipcraft -->\nShipcraft workflow (required): @AGENTS.md\n<!-- /shipcraft -->\n'
 assert Path('CLAUDE.md').read_text()==('Claude rules67\n\n' if case=='onboarding-append' else '')+imp
if case=='onboarding-append':assert agents.startswith('Project rules67\n\n'),agents
assert not Path('.github').exists(),'init wrote workflow'
assert not re.search('who reviews|Which reviewer',text(p)),text(p)
if case=='onboarding-none':
 assert not Path('CLAUDE.md').exists()
 assert 'review = "local"' in text(p),text(p)
elif not kept:assert 'provider' in text(p) and 'review = "off"' in text(p),text(p)
if case in ('github','kept-github'):
 if kept:assert Path(os.environ['ST'],'protection').read_text().strip()!='none'
 else:assert run(os.environ['PY'],Path(os.environ['ACEITE'])/'tools/h.py','protect-ok',os.environ['ST']).stdout.strip()==b'OK'
if case=='github-free':assert Path(os.environ['ST'],'protection').read_text().strip()=='403'
if case in ('red','red-space','no-report','no-report-exit'):
 run('git','add','.');run('git','commit','-q','-m','chore: custom init');run('git','checkout','-qb','feature/custom67')
 write('tests/example.case','new RED assertion67\n')
 p=run(binary,'red',ok=False);assert Path('calls67').exists(),'first RED did not run configured command'
 locks=list(Path('.shipcraft/locks').glob('*.json'))
 if case.startswith('no-report'):
  refusal(p,False,init_only=False);assert 'JUnit' in text(p) or 'report' in text(p),text(p);assert not locks
  row=json.loads(Path('.git/shipcraft/runs.jsonl').read_text().splitlines()[-1]);assert row['code']=='no-report',row
 else:
  assert p.returncode==0,text(p);assert len(locks)==1,locks
  lock=json.loads(locks[0].read_text());assert lock['state']=='open' and any('fails' in x for x in lock['failing_at_red']),lock
  assert 'tests/example.case' in locks[0].read_text(),lock
PY67
  pass
}
