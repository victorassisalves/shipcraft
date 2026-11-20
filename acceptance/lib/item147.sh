# Item 147: public CLI, indexed build inputs and working-tree React declarations.
item147_langs() { echo core; }
item147_cases() {
  local c
  for c in glob manifest-json manifest-yaml jsonc-root jsonc-package glob-project glob-newline glob-controls jsonc-path rollback probe-keep other-keep react-vitest react-bare react-dev react-null react-pnpm react-yarn react-bun react-pnpm-root react-flow react-explicit react-both react-link react-tree react-lock-precedence jsdom-keep happy-dom-keep jest-keep kept-keep workspace-keep no-react-control build-control ci-control invalid-react-control utf8-react-control python-control go-control; do echo "v1-147.$c"; done
}
item147_case() {
  EXPECT="item 147: ${CASE#v1-147.}"
  v1_start
  must_accept 'item 147 contract' cmd "$PY" - "${CASE#v1-147.}" "$(command -v shipcraft)" "$CW" <<'PY147'
import json,os,shlex,shutil,subprocess,sys
from pathlib import Path
try: import tomllib
except ImportError: import tomli as tomllib
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw)
realgit=shutil.which('git')
def write(name,data,mode=None):
 p=Path(name);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
 if mode is not None:p.chmod(mode)
def run(*args,env=None):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,env=env,timeout=45)
 print('$',shlex.join(map(str,args)),'exit',p.returncode,'stdout',repr(p.stdout),'stderr',repr(p.stderr),flush=True)
 return p
def git(*args):
 p=run(realgit,*args);assert p.returncode==0,('fixture git',p.stderr);return p.stdout
# Fixture helpers create inputs only, never expected output.
def workspace(style='block'):
 write('pnpm-workspace.yaml',"packages:\n  - 'packages/*'\n" if style=='block' else "packages: ['packages/*']\n")
 write('packages/web/package.json','{"name":"web","devDependencies":{"vitest":"1"}}')
 write('packages/web/a.test.ts','test("fixture", () => {});\n')
def probe(code):
 write('node_modules/.bin/tsc','#!'+sys.executable+'\nimport sys,json,os\nfrom pathlib import Path\nPath("probe147").write_text(json.dumps({"args":sys.argv[1:],"cwd":os.getcwd()}))\n'+code,0o755)
 write(tools/'npx','#!/bin/sh\n[ "$1" = --no ] && [ "$2" = -- ] && [ "$3" = tsc ] || exit 89\nshift 3\nexec ./node_modules/.bin/tsc "$@"\n',0o755)
root=cw/"project147 space 'quote";root.mkdir();os.chdir(root)
git('init','-q','-b','main');git('config','user.name','Acceptance147');git('config','user.email','acceptance147@example.invalid')
tools=cw/'tools147';tools.mkdir()
for tool in ('git','sh'):(tools/tool).symlink_to(realgit if tool=='git' else shutil.which(tool))
for tool in ('npm','npx','pnpm','yarn','bun','node','tsc','vitest','jest'):
 write(tools/tool,'#!'+sys.executable+'\nfrom pathlib import Path\nPath('+repr(str(cw/'unexpected-tool147'))+').write_text('+repr(tool)+')\nraise SystemExit(79)\n',0o755)
env=dict(os.environ,PATH=str(tools),GIT_OPTIONAL_LOCKS='0')
assert not any((tools/t).exists() for t in ('shipcraft','codex','claude','gemini'))
write('.git/shipcraft/sentinel147',b'keep\r\n\0')
write('package.json','{"devDependencies":{"vitest":"1"}}')
call=binary;args=[];kind=None;what=None;why=None;react=None;install=None;rc=0;kept=None
if case=='glob':
 write('tsconfig.json','{"compilerOptions":{"composite":true}}');write('pnpm-workspace.yaml',"packages: ['packages/{a,b}']\n")
 kind='notice';what='cannot understand glob `packages/{a,b}` in pnpm-workspace.yaml';why='shipcraft only matches `*`, `?`, `**` and exclusion `!`; another wildcard would mean guessing which packages are included'
elif case=='manifest-json':
 write('package.json','{"devDependencies":{"vitest":"1"},"workspaces":42}');kind='notice';what='cannot read package.json, or its package list is not a list of strings';why='[build] comes from workspace packages, and shipcraft does not guess which ones'
elif case=='manifest-yaml':
 write('pnpm-workspace.yaml','packages: [\n');kind='notice';what='cannot read pnpm-workspace.yaml, or its package list is not a list of strings';why='[build] comes from workspace packages, and shipcraft does not guess which ones'
elif case=='jsonc-root':
 write('tsconfig.json','{"compilerOptions": { nope }');kind='notice';what='cannot read tsconfig.json as JSONC';why='init infers [build] only from tsconfig files it can read, and does not guess which folders the build needs'
elif case=='jsonc-package':
 write('package.json','{"devDependencies":{"vitest":"1"},"workspaces":["packages/*"]}');write('packages/broken/package.json','{}');write('packages/broken/tsconfig.json','{"compilerOptions": { nope }')
 kind='notice';what='cannot read packages/broken/tsconfig.json as JSONC';why='init infers [build] only from tsconfig files it can read, and does not guess which folders the build needs'
elif case=='glob-project':
 target=root/'node_modules/shipcraft/bin/shipcraft';target.parent.mkdir(parents=True);shutil.copy2(binary,target);call=root/'node_modules/.bin/shipcraft';call.parent.mkdir(parents=True);call.symlink_to('../shipcraft/bin/shipcraft')
 write('pnpm-workspace.yaml',"packages: ['packages/{a,b}']\n");kind='notice';what='cannot understand glob `packages/{a,b}` in pnpm-workspace.yaml';why='shipcraft only matches `*`, `?`, `**` and exclusion `!`; another wildcard would mean guessing which packages are included'
elif case=='glob-newline':
 write('pnpm-workspace.yaml','packages: ["packages/{a,\\nb}"]\n');kind='notice';what='cannot understand glob `packages/{a, b}` in pnpm-workspace.yaml';why='shipcraft only matches `*`, `?`, `**` and exclusion `!`; another wildcard would mean guessing which packages are included'
elif case=='glob-controls':
 write('pnpm-workspace.yaml','\ufeffpackages: ["packages/{a,\\r\\t\\u2028\\u2029\\x01b}"] # reader boundary\r\n');kind='notice';what='cannot understand glob `packages/{a, b}` in pnpm-workspace.yaml';why='shipcraft only matches `*`, `?`, `**` and exclusion `!`; another wildcard would mean guessing which packages are included'
elif case=='jsonc-path':
 write('package.json','{"devDependencies":{"vitest":"1"},"workspaces":["packages/*"]}');write('packages/line\nbreak/package.json','{}');write('packages/line\nbreak/tsconfig.json','{,}')
 kind='notice';what='cannot read packages/line break/tsconfig.json as JSONC';why='init infers [build] only from tsconfig files it can read, and does not guess which folders the build needs'
elif case=='rollback':
 write('package.json','{"dependencies":{"react":"1"},"devDependencies":{"vitest":"1"}}');write('pnpm-workspace.yaml',"packages: ['packages/{a,b}']\n");write('.shipcraft','blocked147');rc=2
 kind='notice';what='cannot understand glob `packages/{a,b}` in pnpm-workspace.yaml';why='shipcraft only matches `*`, `?`, `**` and exclusion `!`; another wildcard would mean guessing which packages are included'
elif case=='probe-keep':
 write('tsconfig.json','{"compilerOptions":{"composite":true}}');probe('print("a.ts(1,7): error TS2322: Type \'string\' is not assignable to type \'number\'.",file=sys.stderr)\nsys.exit(2)\n');kind='probe'
elif case=='other-keep':
 write('pnpm-workspace.yaml',"packages: ['packages/{a,b}']\n");write('tsconfig.json','{,}');args=['--lang','other','--command','false {junit}','--glob','tests/**'];react=False;kind='other'
elif case=='react-vitest':
 write('package.json','{"dependencies":{"react":"1"},"devDependencies":{"vitest":"1"}}');react=True;install='npm install -D'
elif case=='react-bare':
 write('package.json','{"dependencies":{"react":"1"}}');target=root/'node_modules/shipcraft/bin/shipcraft';target.parent.mkdir(parents=True);shutil.copy2(binary,target);call=root/'node_modules/.bin/shipcraft';call.parent.mkdir(parents=True);call.symlink_to('../shipcraft/bin/shipcraft');react=True;install='npm install -D';kind='bare'
elif case=='react-dev':
 write('package.json','{"devDependencies":{"react":"1","vitest":"1"}}');react=True;install='npm install -D'
elif case=='react-null':
 write('package.json','{"dependencies":{"react":null,"vitest":false}}');react=True;install='npm install -D'
elif case=='react-pnpm':
 write('package.json','{"dependencies":{"react":"1","vitest":"1"}}');write('pnpm-lock.yaml','');react=True;install='pnpm add -D'
elif case=='react-yarn':
 write('package.json','{"dependencies":{"react":"1","vitest":"1"}}');write('yarn.lock','');react=True;install='yarn add -D'
elif case=='react-bun':
 write('package.json','{"dependencies":{"react":"1","vitest":"1"}}');write('bun.lockb','');react=True;install='bun add -d'
elif case=='react-pnpm-root':
 write('package.json','{"dependencies":{"react":"1","vitest":"1"}}');workspace();write('pnpm-lock.yaml','');args=['--lang','node'];react=True;install='pnpm add -D -w'
elif case=='react-flow':
 write('package.json','{"dependencies":{"react":"1","vitest":"1"}}');workspace('flow');react=True;install='npm install -D'
elif case=='react-explicit':
 write('package.json','{"dependencies":{"react":"1"}}');args=['--lang','node'];react=True;install='npm install -D';kind='assumption'
elif case=='react-both':
 write('package.json','{"dependencies":{"react":"1","vitest":"1","jest":"1"}}');react=True;install='npm install -D'
elif case=='react-link':
 write('manifest147','{"devDependencies":{"react":null,"vitest":"1"}}');Path('package.json').unlink();Path('package.json').symlink_to('manifest147');react=True;install='npm install -D'
elif case=='react-tree':
 kind='tree';react=True;install='npm install -D'
elif case=='react-lock-precedence':
 write('package.json','{"dependencies":{"react":"1","vitest":"1"}}');write('pnpm-lock.yaml','');write('yarn.lock','');write('bun.lock','');react=True;install='pnpm add -D'
elif case=='jsdom-keep':
 write('package.json','{"dependencies":{"react":"1","vitest":"1"},"devDependencies":{"jsdom":null}}');react=False;kind='jsdom'
elif case=='happy-dom-keep':
 write('package.json','{"dependencies":{"react":"1","vitest":"1","happy-dom":false}}');react=False;kind='happy-dom'
elif case=='jest-keep':
 write('package.json','{"dependencies":{"react":"1","jest":null}}');react=False;kind='jest'
elif case=='kept-keep':
 write('package.json','{"dependencies":{"react":"1","vitest":"1"}}');kept=b'# kept147\r\ntest_command="false {junit}"\r\ntest_globs=["tests/**"]\r\n';write('.shipcraft.toml',kept);react=False;kind='kept'
elif case=='workspace-keep':
 write('package.json','{"dependencies":{"react":"1","vitest":"1"}}');workspace();react=False;kind='workspace'
elif case=='no-react-control':
 react=False;kind='vitest'
elif case=='build-control':
 workspace();write('tsconfig.json','{"compilerOptions":{"composite":true}}');probe('Path("success147.tsbuildinfo").write_text("fake compiler passed")\n');kind='build'
elif case=='ci-control':
 write('.shipcraft.toml','test_command="false {junit}"\ntest_globs=["tests/**"]\n[build]\ncommand="printf build147 >&2; exit 23"\n');kind='ci'
elif case=='invalid-react-control':
 write('package.json','{"dependencies":{"react":"1"}, broken');args=['--lang','node'];react=False;kind='invalid'
elif case=='utf8-react-control':
 write('package.json',b'{"dependencies":{"react":"1"},"x":"\xff"}');args=['--lang','node'];react=False;kind='invalid'
elif case=='python-control':
 write('package.json','{"dependencies":{"react":"1","vitest":"1"}}');args=['--lang','python'];react=False;kind='python'
elif case=='go-control':
 write('package.json','{"dependencies":{"react":"1","vitest":"1"}}');args=['--lang','go'];react=False;kind='go'
else:raise AssertionError('unrouted case: '+case)
# All build inputs are committed before init; tools and installation are not input.
git('add','package.json')
for entry in root.iterdir():
 if entry.name not in ('.git','package.json','node_modules'):git('add','--',entry.name)
git('commit','-qm','fixture147')
if kind=='tree':write('package.json','{"dependencies":{"react":"1","vitest":"1"}}')
if kind=='ci':
 base=git('rev-parse','HEAD').decode().strip();write('product147','change');git('add','product147');git('commit','-qm','product')
 p=run(call,'ci','--base',base,env=env);text=(p.stdout+p.stderr).decode();lines=text.splitlines()
 assert p.returncode==1 and 'build147' in p.stderr.decode(),text
 assert any(l.startswith('shipcraft refused: the build failed') and 'exited with 23' in l for l in lines),text
 assert 'skipped the optional' not in text
 rows=[json.loads(l) for l in Path('.git/shipcraft/runs.jsonl').read_text().splitlines()]
 assert rows[-1]['code']=='build-failed' and rows[-1]['layer']=='ci',rows
else:
 p=run(call,'init',*args,env=env);out=p.stdout.decode();text=out+p.stderr.decode();lines=out.splitlines()
 assert p.returncode==rc,(rc,text)
 assert Path('.git/shipcraft/sentinel147').read_bytes()==b'keep\r\n\0'
 assert not Path('.git/shipcraft/runs.jsonl').exists()
 if kind=='notice':
  next_line='Next: when the tests need a build first, add a [build] section to .shipcraft.toml with command = "npx --no -- tsc -b <directories with project references>", and remove the check of each suite in those directories, since tsc --noEmit refuses a composite project (TS6310)'
  expected=['shipcraft: skipped the optional [build] step: '+what,'Why: '+why+', so init goes on without it',next_line]
  assert not any(l.startswith('shipcraft refused:') for l in text.splitlines()),text
  at=next((i for i,l in enumerate(lines) if l==expected[0]),-1)
  assert at>=0 and lines[at:at+3]==expected,('exact skip lines',expected,text)
  assert sum(l.startswith('shipcraft: skipped the optional [build] step:') for l in lines)==1
  assert lines[at+1].count(', so init goes on without it')==1
  assert all(l not in p.stderr.decode() for l in expected)
  assert not Path('probe147').exists(),'a diagnostic must not probe'
  if rc==0:
   assert at+2<next(i for i,l in enumerate(lines) if l.startswith('shipcraft: language'))
   assert 'build' not in tomllib.loads(Path('.shipcraft.toml').read_text())
  else:
   assert 'undid what this run created' in text and Path('.shipcraft').read_text()=='blocked147'
   assert not any(Path(f).exists() for f in ('.shipcraft.toml','AGENTS.md','CLAUDE.md','.git/hooks/commit-msg','.git/hooks/post-commit'))
   assert 'ready. Commit' not in text and 'to test a component' not in text
 if rc==0:
  cfg=tomllib.loads(Path('.shipcraft.toml').read_text());ready=next(i for i,l in enumerate(lines) if l.startswith('shipcraft: ready. Commit'))
  assert ready==len(lines)-3,lines
  if react is True:
   expected='shipcraft: package.json depends on react: to test a component in a DOM with Testing Library, install them with `'+install+' jsdom @testing-library/react` and start each such test file with the line // @vitest-environment jsdom'
   assert lines.count(expected)==1,('missing/duplicate React advice',expected,text)
   at=lines.index(expected);assert expected not in p.stderr.decode()
   assert lines[at-1].startswith(('shipcraft: review by ','shipcraft: no review agent installed ')),lines
   assert at<ready and cfg['runner']=='vitest' and 'suite' not in cfg
   if kind=='bare':
    assert lines[at+1]=='shipcraft: node_modules is not ignored by git: add it to .gitignore before committing, or `git add -A` stages the installed packages'
    assert lines[at+2].startswith('shipcraft: warning: found neither vitest nor jest') and at+3==ready
   if kind=='assumption':assert lines[at+1].startswith('shipcraft: warning: found neither vitest nor jest') and at+2==ready
  elif react is False:
   assert 'to test a component' not in text and 'Testing Library' not in text,text
  if kind=='probe':
   expected=['shipcraft: skipped the optional [build] step: `npx --no -- tsc -b .` exited with 2: a.ts(1,7): error TS2322: Type \'string\' is not assignable to type \'number\'.','Why: init writes [build] only after it passes in the tree; a failing [build] would refuse every shipcraft ci and shipcraft red, so init goes on without it','Next: when `npx --no -- tsc -b .` passes (run it to see the errors), add a [build] section to .shipcraft.toml with command = "npx --no -- tsc -b ."']
   at=lines.index(expected[0]);assert lines[at:at+3]==expected and 'build' not in cfg and not p.stderr
   assert json.loads(Path('probe147').read_text())=={'args':['-b','.'],'cwd':str(root)}
  if kind=='build':
   assert cfg['build']['command']=='npx --no -- tsc -b .' and 'skipped the optional' not in text
   assert json.loads(Path('probe147').read_text())=={'args':['-b','.'],'cwd':str(root)}
   assert Path('success147.tsbuildinfo').read_text()=='fake compiler passed'
  if kind=='other':assert cfg['test_command']=='false {junit}' and 'skipped the optional' not in text
  if kind=='kept':assert Path('.shipcraft.toml').read_bytes()==kept and 'already exists, kept' in text
  if kind=='workspace':assert cfg['suite'][0]['name']=='web' and 'language node (runner vitest)' not in text
  if kind=='jest':assert cfg['runner']=='jest' and 'assumes vitest' not in text
  if kind in ('jsdom','happy-dom','vitest'):assert cfg['runner']=='vitest' and 'suite' not in cfg
  if kind=='invalid':assert 'assumes vitest' in lines[ready-1] and cfg['runner']=='vitest'
  if kind=='python':assert cfg['lang']=='python' and cfg['runner']=='pytest'
  if kind=='go':assert cfg['lang']=='go' and cfg['runner']=='gotestsum'
assert not (cw/'unexpected-tool147').exists(),'real or bait external tool must not run'
PY147
  pass
}
