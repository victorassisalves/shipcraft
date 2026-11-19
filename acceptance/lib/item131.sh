# Item 131: public init only; no source reader, external service or real package manager.
item131_langs() { echo core; }
item131_cases() {
  local c
  for c in bare marker-variants precedence workspace kept invocation-npx invocation-pnpm invocation-fallback custom npm pnpm pnpm-workspace yarn bun lock-precedence lock-nonregular ready-untracked ready-status ready-nonregular git-errors modules modules-ignored later-onboarding before-ready probe-fail probe-stdout probe-silent probe-signal probe-pass probe-leftovers probe-rollback probe-list-fails probe-skipped probe-quoted probe-stream-boundary machine-control runner-control probe-control git-control ci-control; do echo "v1-131.$c"; done
}
item131_case() {
  EXPECT="item 131: ${CASE#v1-131.}"
  v1_start codex claude
  must_accept 'item 131 contract' cmd "$PY" - "${CASE#v1-131.}" "$(command -v shipcraft)" "$CW" <<'PY131'
import json,os,re,shlex,shutil,subprocess,sys
from pathlib import Path
try: import tomllib
except ImportError: import tomli as tomllib
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw)
realgit=shutil.which('git')
def write(name,data,mode=None):
 p=Path(name);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
 if mode is not None:p.chmod(mode)
def run(*args,env=None):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,env=env,timeout=40)
 print('$',shlex.join(map(str,args)),'exit',p.returncode,'stdout',repr(p.stdout),'stderr',repr(p.stderr),flush=True)
 return p
def git(*args):
 p=run(realgit,*args);assert p.returncode==0,('fixture git',p.stderr);return p.stdout
# Shared helpers build fixtures only; every expected value belongs to its case arm.
def fresh(name,local=True):
 root=cw/name;root.mkdir();os.chdir(root);git('init','-q','-b','main')
 git('config','user.name','Acceptance131');git('config','user.email','acceptance131@example.invalid')
 tools=root/'tools131';tools.mkdir();(tools/'git').symlink_to(realgit)
 for tool in ('sh','sleep'):(tools/tool).symlink_to(shutil.which(tool))
 for tool in ('codex','claude'):
  write(tools/tool,'#!/bin/sh\nexit 0\n',0o755)
 for tool in ('npm','yarn','bun','node','vitest','jest'):
  write(tools/tool,'#!'+sys.executable+'\nfrom pathlib import Path\nPath("tool-called131").write_text("'+tool+'")\nraise SystemExit(79)\n',0o755)
 env=dict(os.environ,PATH=str(tools),GIT_OPTIONAL_LOCKS='0')
 write('.git/shipcraft/sentinel131',b'preserve\r\n\0')
 call=binary
 if local:
  target=root/'node_modules/shipcraft/bin/shipcraft';target.parent.mkdir(parents=True);shutil.copy2(binary,target)
  call=root/'node_modules/.bin/shipcraft';call.parent.mkdir(parents=True);call.symlink_to('../shipcraft/bin/shipcraft')
 return root,tools,env,call
def probe(body,folder='.'):
 write('package.json','{"devDependencies":{"vitest":"*"}}')
 write(Path(folder)/'tsconfig.json','{"compilerOptions":{"composite":true},"files":["a.ts"]}')
 write(Path(folder)/'a.ts','export const a: number = "wrong";\n')
 if folder!='.':
  write('package.json',json.dumps({'workspaces':['packages/*']}))
  write(Path(folder)/'package.json','{"devDependencies":{"vitest":"*"}}')
  write(Path(folder)/'a.test.ts','test("fixture",()=>{});')
 git('add','package.json',str(Path(folder)/'tsconfig.json'),str(Path(folder)/'a.ts'))
 if folder!='.':git('add',folder)
 git('commit','-qm','fixture before init')
 write('node_modules/.bin/tsc','#!'+sys.executable+'\nimport os,sys,json,subprocess\nfrom pathlib import Path\nPath("probe-called131").write_text(json.dumps({"args":sys.argv[1:],"cwd":os.getcwd(),"token":os.environ.get("PROBE131")}))\n'+body,0o755)
 # npx only delegates to the fixture executable, never downloads anything.
 write('tools131/npx','#!/bin/sh\n[ "$1" = --no ] && [ "$2" = -- ] && [ "$3" = tsc ] || exit 89\nshift 3\nexec ./node_modules/.bin/tsc "$@"\n',0o755)
def git_fault(expression,code):
 path=Path('tools131/git');path.unlink()
 write(path,'#!'+sys.executable+'\nimport os,sys\na=sys.argv[1:]\nif '+expression+':\n open("git-fault131","a").write(repr(a)+"\\n")\n sys.exit('+str(code)+')\nos.execv('+repr(realgit)+',['+repr(realgit)+']+a)\n',0o755)
root,tools,env,call=fresh('project131')
args=[];mode=None
form="init --lang other --command '<test command writing JUnit to {junit}>' --glob '<test files>'"
notice='shipcraft: node_modules is not ignored by git: add it to .gitignore before committing, or `git add -A` stages the installed packages'
ready='shipcraft: ready. Commit .shipcraft.toml, AGENTS.md, CLAUDE.md, .shipcraft/briefs/red.md, .shipcraft/briefs/green.md'
# The first acceptance case is the exact main reproduction, with its new required result.
if case=='bare':
 write('package.json','{"name":"barb","version":"1.0.0","devDependencies":{"shipcraft":"^2.73.0"}}');write('package-lock.json','{}')
 p=run(call,'init',env=env)
 assert p.returncode==0,('bare package.json must detect Node',p.stderr)
 assert b'shipcraft: language node (runner vitest)\n' in p.stdout
 actual=Path('.shipcraft.toml').read_bytes()
 other,ot,oe,oc=fresh('explicit131');write('package.json','{}');q=run(oc,'init','--lang','node',env=oe)
 assert q.returncode==0 and Path('.shipcraft.toml').read_bytes()==actual,'implicit config must equal explicit Node bytes'
 assert b'Install it with `npm install -D vitest`' in p.stdout
elif case=='marker-variants':
 for i,variant in enumerate(('invalid','utf8','directory','symlink','dangling','loop','absent')):
  r,t,e,c=fresh('marker'+str(i));f=Path('package.json')
  if variant=='invalid':write(f,'{broken')
  elif variant=='utf8':write(f,b'\xff')
  elif variant=='directory':f.mkdir()
  elif variant=='symlink':write('target','{}');f.symlink_to('target')
  elif variant=='dangling':f.symlink_to('missing')
  elif variant=='loop':f.symlink_to('package.json')
  p=run(c,'init',env=e)
  expected=1 if variant in ('dangling','loop','absent') else 0
  assert p.returncode==expected,(variant,p.stderr)
  if expected==0:assert b'language node (runner vitest)' in p.stdout
  else:assert b'could not recognize' in p.stderr and not Path('.shipcraft.toml').exists()
elif case=='precedence':
 for i,(marker,language) in enumerate((('pyproject.toml','python'),('go.mod','go'),('requirements-dev.txt','python'),('pyproject.toml/','python'),('go.mod/','go'))):
  r,t,e,c=fresh('precedence'+str(i));write('package.json','{}')
  if marker[-1]=='/':Path(marker).mkdir()
  else:write(marker,'')
  p=run(c,'init',env=e)
  assert p.returncode==0 and ('shipcraft: language '+language+' ').encode() in p.stdout,(marker,p.stderr)
  assert b'assumes vitest' not in p.stdout
elif case=='workspace':
 for i,variant in enumerate(('npm','pnpm','go')):
  r,t,e,c=fresh('workspace'+str(i));write('package.json','{}');write('packages/a/package.json','{}')
  if variant=='npm':write('package.json','{"workspaces":["packages/*"]}')
  elif variant=='pnpm':write('pnpm-workspace.yaml','packages:\n  - "packages/*"\n')
  else:write('go.work','go 1.21\nuse ./packages/a\n')
  p=run(c,'init',env=e)
  assert p.returncode==1 and b'could not recognize' in p.stderr,p.stderr
  assert b'npx -- shipcraft init --lang' in p.stderr and not Path('.shipcraft.toml').exists()
elif case=='kept':
 write('package.json','{}');data=b'# kept131\r\ntest_command="false {junit}"\r\ntest_globs=["tests/**"]\r\n';write('.shipcraft.toml',data)
 p=run(call,'init',env=env)
 assert p.returncode==0 and Path('.shipcraft.toml').read_bytes()==data
 assert b'already exists, kept' in p.stdout and b'language ' not in p.stdout and b'assumes vitest' not in p.stdout
elif case=='invocation-npx':
 mode='refusal';inv='npx -- shipcraft';needle='could not recognize'
elif case=='invocation-pnpm':
 write('pnpm-lock.yaml','');write(tools/'pnpm','#!/bin/sh\nprintf ran > tool-called131\nexit 79\n',0o755)
 write('package.json','{"dependencies":{"vitest":null}}');write('pyproject.toml','')
 mode='refusal';inv='pnpm exec shipcraft';needle='more than one'
elif case=='invocation-fallback':
 for i,variant in enumerate(('no-path','symlink','directory','nested')):
  r,t,e,c=fresh('inv'+str(i));write('pnpm-lock.yaml','')
  if variant=='symlink':Path('pnpm-lock.yaml').unlink();write('real-lock','');Path('pnpm-lock.yaml').symlink_to('real-lock')
  if variant=='directory':Path('pnpm-lock.yaml').unlink();Path('pnpm-lock.yaml').mkdir()
  if variant!='no-path':write(t/'pnpm','#!/bin/sh\nprintf ran > tool-called131\nexit 79\n',0o755)
  inv='npx -- shipcraft'
  if variant=='nested':
   c=r/'packages/x/node_modules/shipcraft/bin/shipcraft';c.parent.mkdir(parents=True);shutil.copy2(binary,c);inv='shipcraft'
  p=run(c,'init',env=e)
  assert p.returncode==1 and p.stderr.decode().count(inv+' init --lang')==2,p.stderr
elif case=='custom':
 for i,a in enumerate((['--lang','other','--glob','tests/**'],['--lang','other','--command','run {junit}'],['--command','run {junit}'],['--lang','other','--command','bad','--glob','tests/**'])):
  r,t,e,c=fresh('custom'+str(i));p=run(c,'init',*a,env=e)
  assert p.returncode==1 and ('npx -- shipcraft '+form) in p.stderr.decode(),p.stderr
  assert not Path('.shipcraft.toml').exists()
elif case=='npm':
 mode='warning';install='npm install -D vitest';inv='npx -- shipcraft'
elif case=='pnpm':
 write('pnpm-lock.yaml','');mode='warning';install='pnpm add -D vitest';inv='npx -- shipcraft'
elif case=='pnpm-workspace':
 write('pnpm-lock.yaml','');Path('pnpm-workspace.yaml').symlink_to('missing-workspace');mode='warning';install='pnpm add -D -w vitest';inv='npx -- shipcraft'
elif case=='yarn':
 write('yarn.lock','');mode='warning';install='yarn add -D vitest';inv='npx -- shipcraft';call=binary;inv='shipcraft'
elif case=='bun':
 for i,name in enumerate(('bun.lock','bun.lockb')):
  r,t,e,c=fresh('bun'+str(i));write(name,b'\xff\0');p=run(c,'init','--lang','node',env=e)
  assert p.returncode==0 and b'Install it with `bun add -d vitest`' in p.stdout,p.stdout
elif case=='lock-precedence':
 for name in ('pnpm-lock.yaml','yarn.lock','bun.lock','bun.lockb'):write(name,'')
 write(tools/'pnpm','#!/bin/sh\nprintf ran > tool-called131\nexit 79\n',0o755)
 mode='warning';install='pnpm add -D vitest';inv='pnpm exec shipcraft'
elif case=='lock-nonregular':
 Path('pnpm-lock.yaml').symlink_to('missing');Path('yarn.lock').mkdir();write('bun-target','');Path('bun.lock').symlink_to('bun-target');write('bun.lockb','')
 mode='warning';install='bun add -d vitest';inv='npx -- shipcraft'
elif case=='ready-untracked':
 names=['package.json','pnpm-lock.yaml','yarn.lock','bun.lock','bun.lockb','package-lock.json']
 for name in names:write(name,'{}')
 args=['--lang','node'];mode='ready';expected=names
elif case=='ready-status':
 write('package.json','{"devDependencies":{"vitest":"*"}}');write('pnpm-lock.yaml','');write('yarn.lock','');write('bun.lock','');write('bun.lockb','');write('.gitignore','bun.lockb\n')
 git('add','package.json','pnpm-lock.yaml','yarn.lock');git('commit','-qm','committed manifest and locks')
 write('pnpm-lock.yaml','modified');write('yarn.lock','staged');git('add','yarn.lock')
 args=['--lang','node'];mode='ready';expected=['pnpm-lock.yaml','yarn.lock','bun.lock']
elif case=='ready-nonregular':
 write('package.json','{"devDependencies":{"vitest":"*"}}');git('add','package.json');git('commit','-qm','manifest')
 write('target-lock','');Path('pnpm-lock.yaml').symlink_to('target-lock');Path('yarn.lock').mkdir();Path('bun.lock').symlink_to('missing')
 mode='ready';expected=[]
elif case=='git-errors':
 write('package.json','{"devDependencies":{"vitest":"*"}}');write('package-lock.json','{}')
 git_fault("'status' in a or 'check-ignore' in a",73)
 mode='ready';expected=[]
elif case=='modules':
 write('requirements.txt','');p=run(call,'init',env=env)
 assert p.returncode==0 and p.stdout.decode().splitlines()[-4]==notice,p.stdout
 assert not Path('.gitignore').exists() and p.stdout.decode().count(notice)==1 and notice not in p.stderr.decode()
elif case=='modules-ignored':
 write('package.json','{"devDependencies":{"vitest":"*"}}');write('.gitignore','node_modules/\n')
 p=run(call,'init',env=env)
 assert p.returncode==0 and notice not in (p.stdout+p.stderr).decode()
 assert Path('.gitignore').read_text()=='node_modules/\n'
elif case=='later-onboarding':
 write('package.json','{}');write('.shipcraft/briefs','blocked131');write('agents-target','preserved');Path('AGENTS.md').symlink_to('agents-target')
 mode='warning';install='npm install -D vitest';inv='npx -- shipcraft'
elif case=='before-ready':
 write('package.json','{"dependencies":{"vitest":"*"}}');write('.shipcraft','blocked131')
 p=run(call,'init',env=env)
 assert p.returncode==2 and notice not in (p.stdout+p.stderr).decode() and b'ready. Commit' not in p.stdout
 assert not Path('.shipcraft.toml').exists() and Path('.shipcraft').read_text()=='blocked131'
elif case=='probe-fail':
 probe('print("stdout first")\nprint("\\n  src/a.ts(1,14): error TS2322: Type \'string\' is not assignable to type \'number\'.  ",file=sys.stderr)\nprint("SECOND ERROR MUST NOT LEAK",file=sys.stderr)\nPath("tsconfig.app.tsbuildinfo").write_text("cache")\nPath("tsconfig.node.tsbuildinfo").write_text("cache")\nsys.exit(2)\n')
 mode='probe';how='exited with 2';first="src/a.ts(1,14): error TS2322: Type 'string' is not assignable to type 'number'.";left=['probe-called131','tsconfig.app.tsbuildinfo','tsconfig.node.tsbuildinfo'];rc=0
elif case=='probe-stdout':
 probe('sys.stdout.buffer.write(b"\\n\\t \\nstdout\\xff\\t fallback\\r detail\\xe2\\x80\\xa8tail\\xe2\\x80\\xa9done\\nSECOND ERROR MUST NOT LEAK\\n")\nprint(" \\n\\t",file=sys.stderr)\nsys.exit(2)\n')
 mode='probe';how='exited with 2';first='stdout� fallback detail tail done';left=['probe-called131'];rc=0
elif case=='probe-silent':
 probe('sys.exit(2)\n');mode='probe';how='exited with 2';first='';left=['probe-called131'];rc=0
elif case=='probe-signal':
 probe('os.kill(os.getpid(),15)\n');mode='probe';how=None;first=None;left=['probe-called131'];rc=0
elif case=='probe-pass':
 probe('print("SUCCESS STDOUT MUST NOT LEAK")\nprint("SUCCESS STDERR MUST NOT LEAK",file=sys.stderr)\nPath("pass.tsbuildinfo").write_text("keep")\n')
 p=run(call,'init',env=env);out=p.stdout.decode()
 assert p.returncode==0 and tomllib.loads(Path('.shipcraft.toml').read_text())['build']['command']=='npx --no -- tsc -b .'
 assert b'MUST NOT LEAK' not in p.stdout+p.stderr,'successful probe streams must be quiet'
 line='shipcraft: the build left files git does not ignore: pass.tsbuildinfo, probe-called131; add them to .gitignore before committing'
 assert line in out.splitlines() and out.index(line)<out.index('shipcraft: language'),out
elif case=='probe-leftovers':
 write('.gitignore','ignored.tsbuildinfo\n');write('old.tsbuildinfo','old');write('tracked.tsbuildinfo','tracked');git('add','tracked.tsbuildinfo')
 probe('for n in ("z.tsbuildinfo","b\\nname.tsbuildinfo","a.tsbuildinfo","old.tsbuildinfo","tracked.tsbuildinfo","ignored.tsbuildinfo"):\n Path(n).write_text("rewritten")\nsubprocess.run(['+repr(realgit)+',"init","-q","nested"],check=True)\nsys.exit(2)\n')
 mode='probe';how='exited with 2';first='';left=['a.tsbuildinfo','b name.tsbuildinfo','nested/','probe-called131','z.tsbuildinfo'];rc=0
elif case=='probe-rollback':
 probe('print("rollback build error",file=sys.stderr)\nPath("survives.tsbuildinfo").write_text("keep")\nsys.exit(2)\n');write('.shipcraft','blocked131')
 mode='probe';how='exited with 2';first='rollback build error';left=['probe-called131','survives.tsbuildinfo'];rc=2
elif case=='probe-list-fails':
 probe('Path("survives.tsbuildinfo").write_text("keep")\nsys.exit(2)\n');git_fault("'ls-files' in a and '--others' in a",74)
 p=run(call,'init',env=env)
 assert p.returncode==0 and b'the build left files' not in p.stdout and Path('survives.tsbuildinfo').exists()
 assert Path('git-fault131').exists(),'new listing must actually have been attempted'
 assert b'skipped the optional [build] step:' in p.stdout
elif case=='probe-skipped':
 for i,variant in enumerate(('no-signal','other','kept')):
  r,t,e,c=fresh('skip'+str(i));probe('raise SystemExit("MUST NOT RUN")\n')
  a=[]
  if variant=='no-signal':git('rm','-q','tsconfig.json')
  elif variant=='other':a=['--lang','other','--command','false {junit}','--glob','tests/**']
  else:write('.shipcraft.toml','test_command="false {junit}"\ntest_globs=["tests/**"]\n')
  git_fault("'ls-files' in a and '--others' in a",75)
  p=run(c,'init',*a,env=e)
  assert p.returncode==0 and not Path('probe-called131').exists() and not Path('git-fault131').exists()
  assert b'the build left files' not in p.stdout
elif case=='probe-quoted':
 folder='packages/a"quoted\\path';probe('print("quoted diagnostic",file=sys.stderr)\nsys.exit(2)\n',folder)
 p=run(call,'init',env=env);out=p.stdout.decode()
 assert p.returncode==0 and b'skipped the optional [build] step:' in p.stdout,p.stdout
 line=next(l for l in out.splitlines() if l.startswith('Next: when `'))
 command=tomllib.loads(line.split('add a [build] section to .shipcraft.toml with ',1)[1])['command']
 assert shlex.split(command)==['npx','--no','--','tsc','-b',folder],line
 assert line.count('`'+command+'`')==1 and json.loads(Path('probe-called131').read_text())['args']==['-b',folder]
elif case=='probe-stream-boundary':
 probe('sys.stdout.buffer.write(b" "*73728+b"\\nstdout fallback\\n"+b"x"*262144)\nsys.stdout.flush()\nsys.stderr.buffer.write(b" \\n"+b"E"*4096+b"TRUNCATE-ME\\nSECOND ERROR MUST NOT LEAK\\n")\nsys.exit(2)\n')
 mode='probe';how='exited with 2';first='E'*4096;left=['probe-called131'];rc=0
elif case=='machine-control':
 p=run(binary,'init',env=env)
 assert p.returncode==1 and p.stderr.decode().splitlines()==['shipcraft refused: could not recognize the project language','Why: shipcraft recognizes a language by its project file, and found none it knows; it can also run any test command that writes JUnit','Next: specify the language: shipcraft init --lang python|node|go; for any other: shipcraft '+form]
 r,t,e,c=fresh('machine-success131',False);write('package.json','{}');write('package-lock.json','{}')
 p=run(c,'init','--lang','python',env=e)
 assert p.returncode==0 and p.stdout.decode().splitlines()[-3]==ready+' and .shipcraft/locks/;'
 assert p.stdout.decode().splitlines()[-2]=='shipcraft: then write the failing test and stub, and run `shipcraft red`.'
 assert notice not in (p.stdout+p.stderr).decode()
elif case=='runner-control':
 write('package.json','{"devDependencies":{"jest":null}}');write('.gitignore','node_modules/\n');git('add','package.json','.gitignore');git('commit','-qm','committed jest manifest')
 p=run(call,'init',env=env)
 assert p.returncode==0 and b'language node (runner jest)' in p.stdout
 assert tomllib.loads(Path('.shipcraft.toml').read_text())['runner']=='jest' and b'assumes vitest' not in p.stdout
 assert ready+' and .shipcraft/locks/;' in p.stdout.decode().splitlines()
elif case=='probe-control':
 probe('Path("control.tsbuildinfo").write_text("fixture success")\n')
 env['PROBE131']='inherited131';p=run(call,'init',env=env)
 assert p.returncode==0 and tomllib.loads(Path('.shipcraft.toml').read_text())['build']['command']=='npx --no -- tsc -b .'
 assert json.loads(Path('probe-called131').read_text())=={'args':['-b','.'],'cwd':str(root),'token':'inherited131'}
 assert Path('control.tsbuildinfo').read_text()=='fixture success'
 r,t,e,c=fresh('quoted-control131');folder='packages/a"quoted\\path'
 probe('Path("quoted-control.tsbuildinfo").write_text("quoted fixture success")\n',folder)
 q=run(c,'init',env=e)
 assert q.returncode==0 and shlex.split(tomllib.loads(Path('.shipcraft.toml').read_text())['build']['command'])==['npx','--no','--','tsc','-b',folder]
 assert json.loads(Path('probe-called131').read_text())['args']==['-b',folder] and Path('quoted-control.tsbuildinfo').read_text()=='quoted fixture success'
elif case=='git-control':
 git_fault("'rev-parse' in a",73)
 q=run(tools/'git','--version',env=env)
 assert q.returncode==0 and b'git version' in q.stdout,'git wrapper must forward ordinary calls'
 p=run(call,'init',env=env)
 assert p.returncode!=0 and Path('git-fault131').exists() and 'rev-parse' in Path('git-fault131').read_text()
 assert not Path('.shipcraft.toml').exists() and b'ready. Commit' not in p.stdout
elif case=='ci-control':
 probe('print("BUILD OUTPUT131",file=sys.stderr)\nsys.exit(2)\n')
 write('.gitignore','node_modules/\nprobe-called131\n');write('.shipcraft.toml','test_command="false {junit}"\ntest_globs=["tests/**"]\n[build]\ncommand="npx --no -- tsc -b ."\n')
 git('add','.gitignore','.shipcraft.toml');git('commit','-qm','manual build config');base=git('rev-parse','HEAD').decode().strip()
 write('change.txt','change');git('add','change.txt');git('commit','-qm','product change')
 # Tools live in the fixture but are not product input or a dirty build tree.
 write('.git/info/exclude','tools131/\n')
 p=run(call,'ci','--base',base,env=env)
 assert p.returncode==1 and b'BUILD OUTPUT131' in p.stderr and b'the build failed' in p.stdout+p.stderr,(p.stdout,p.stderr)
 assert b'skipped the optional' not in p.stdout+p.stderr
else:raise AssertionError('unrouted case: '+case)
if mode=='refusal':
 p=run(call,'init',env=env);lines=p.stderr.decode().splitlines()
 assert p.returncode==1 and len(lines)==3 and needle in lines[0],p.stderr
 assert lines[-1]=='Next: specify the language: '+inv+' init --lang python|node|go; for any other: '+inv+' '+form,p.stderr
 assert not Path('.shipcraft.toml').exists()
elif mode=='warning':
 p=run(call,'init','--lang','node',env=env);lines=p.stdout.decode().splitlines()
 expected='shipcraft: warning: found neither vitest nor jest in package.json, so the test command assumes vitest. Install it with `'+install+'`, or for another runner, from the repository root, remove .shipcraft.toml and run: '+inv+' '+form
 assert p.returncode==0 and lines.count(expected)==1,('exact warning',p.stdout,p.stderr)
 at=next(i for i,l in enumerate(lines) if l.startswith('shipcraft: ready. Commit'))
 assert lines[at-1]==expected and expected not in p.stderr.decode()
 assert lines[-2]=='shipcraft: then write the failing test and stub, and run `'+inv+' red`.'
 if call!=binary:assert lines[at-2]==notice
 assert not Path('tool-called131').exists(),'install advice must not run package manager'
 if case=='later-onboarding':assert Path('.shipcraft/briefs').read_text()=='blocked131' and Path('agents-target').read_text()=='preserved'
elif mode=='ready':
 p=run(call,'init',*args,env=env);lines=p.stdout.decode().splitlines()
 wanted=ready+('' if not expected else ', '+', '.join(expected))+' and .shipcraft/locks/;'
 assert p.returncode==0 and lines[-3]==wanted,('ready files/order',wanted,p.stdout,p.stderr)
 assert lines[-2]=='shipcraft: then write the failing test and stub, and run `npx -- shipcraft red`.'
 if case=='git-errors':assert notice not in p.stdout.decode() and Path('git-fault131').exists()
elif mode=='probe':
 p=run(call,'init',env=env);out=p.stdout.decode(errors='replace');lines=out.splitlines()
 assert p.returncode==rc,(rc,p.stdout,p.stderr)
 prefix='shipcraft: skipped the optional [build] step: `npx --no -- tsc -b .` '
 skips=[l for l in lines if l.startswith(prefix)]
 assert len(skips)==1,('missing optional-build diagnostic',p.stdout,p.stderr)
 if how is not None:assert skips[0]==prefix+how+(': '+first if first else ''),skips
 else:assert re.search(r'(killed by signal 15|exited with 143)',skips[0]),skips
 at=lines.index(skips[0])
 assert lines[at+1]=='Why: init writes [build] only after it passes in the tree; a failing [build] would refuse every shipcraft ci and shipcraft red, so init goes on without it'
 assert lines[at+2]=='Next: when `npx --no -- tsc -b .` passes (run it to see the errors), add a [build] section to .shipcraft.toml with command = "npx --no -- tsc -b ."'
 short=', '.join(left[:3])+(' and '+str(len(left)-3)+' more' if len(left)>3 else '')
 leftover_line=lines[at+3]
 if len(left)<=3:
  assert leftover_line=='shipcraft: the build left files git does not ignore: '+short+'; add them to .gitignore before committing',lines
 else:
  assert leftover_line.startswith('shipcraft: the build left files git does not ignore: '+', '.join(left[:3])) and leftover_line.endswith('and '+str(len(left)-3)+' more; add them to .gitignore before committing'),lines
  assert all(name not in leftover_line for name in left[3:]),leftover_line
 assert not any(l.startswith('shipcraft refused:') for l in lines)
 assert 'stdout first' not in out and b'rollback build error' not in p.stderr,'failed probe stream leaked'
 if first:assert out.count(first)==1,'probe first line duplicated outside skip diagnostic'
 assert b'SECOND ERROR MUST NOT LEAK' not in p.stdout+p.stderr and b'TRUNCATE-ME' not in p.stdout+p.stderr
 if rc==0:
  assert not p.stderr,('probe output leaked to stderr',p.stderr)
  assert 'build' not in tomllib.loads(Path('.shipcraft.toml').read_text())
  assert at+3<next(i for i,l in enumerate(lines) if l.startswith('shipcraft: language'))
 else:
  assert not Path('.shipcraft.toml').exists() and Path('survives.tsbuildinfo').read_text()=='keep'
  assert notice not in out and 'ready. Commit' not in out and 'undid what this run created' in out+p.stderr.decode()
 assert not Path('.gitignore').exists() or case=='probe-leftovers','init wrote an ignore file'
assert not Path('tool-called131').exists(),'package manager must not be started'
if case!='ci-control':
 assert Path('.git/shipcraft/sentinel131').read_bytes()==b'preserve\r\n\0'
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'init wrote measurement row'
PY131
  pass
}
