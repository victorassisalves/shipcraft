# Item 72: public init and the real installed TypeScript compiler only.
item72_langs() { echo node; }
item72_cases() {
  local c
  for c in forge root-composite root-references root-extends root-unjudged index-remove index-invalid index-add proof-mutates mixed mixed-reverse untracked tree-signal no-signal root-only proof-fails proof-reference manifest-invalid glob-invalid rollback-file rollback-hooks existing-check existing-absent; do echo "v1-72.$c"; done
}
item72_case() {
  local mode=${CASE#v1-72.}
  EXPECT="item 72: $mode"
  must_accept 'item 72 contract' cmd "$PY" - "$mode" "$(command -v shipcraft)" "$CW" <<'PY72'
import json, os, pathlib, shlex, shutil, subprocess, sys
import tomli
P=pathlib.Path
mode,binary,cw=sys.argv[1:]
def write(path,data):
 p=P(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(data)
def config(path,data):write(path,json.dumps(data))
def run(*args,ok=True):
 p=subprocess.run(args,capture_output=True,text=True,timeout=90)
 print('$',shlex.join(args),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 if ok:assert p.returncode==0,('command failed',args,p.returncode,p.stdout,p.stderr)
 return p
def project(folder,signal=True):
 d={'compilerOptions':{'types':[],'outDir':'dist'},'files':['value.ts']}
 if signal:d['compilerOptions']['composite']=True
 config(folder+'/tsconfig.json',d);write(folder+'/value.ts','export const value: number = 1;\n')
 return d
def package(name,signal=True):
 folder='packages/'+name
 config(folder+'/package.json',{'name':name,'private':True,'type':'module','devDependencies':{'vitest':'*'}})
 write(folder+'/tests/value.test.ts','import {it} from "vitest"; it("ok",()=>{});\n')
 return project(folder,signal)
root_mode=(mode.startswith(('root-','index-')) and mode!='root-only') or mode in ('proof-mutates','manifest-invalid')
pkg=json.loads(P('package.json').read_text())
expected_targets=[];omit=set();solution=set()
if root_mode:
 d=project('.',mode!='index-add')
 if mode=='root-references':d['compilerOptions'].pop('composite');d['references']=[]
 if mode=='root-extends':config('base.json',{'compilerOptions':{'strict':True}});d['extends']='./base.json'
 if mode=='root-unjudged':d.pop('files');d['include']=['value.ts']
 config('tsconfig.json',d);expected_targets=['.'];omit={'.'}
 if mode in ('index-invalid','index-add','manifest-invalid'):expected_targets=[];omit=set()
 if mode=='manifest-invalid':write('pnpm-workspace.yaml','packages: [packages/*, 42]\n')
else:
 # Forge-like workspace: tested composite projects, one referencing the other.
 pkg['workspaces']=['packages/*'];P('tsconfig.json').unlink()
 a=package('alpha');package('beta');a['references']=[{'path':'../beta'}];config('packages/alpha/tsconfig.json',a)
 expected_targets=['packages/alpha','packages/beta'];omit=set(expected_targets)
 if mode in ('mixed','mixed-reverse'):
  normal,sol=('alpha','beta') if mode=='mixed' else ('beta','alpha')
  config('projects/real/tsconfig.json',{'compilerOptions':{'composite':True,'types':[],'outDir':'dist'},'files':['value.ts']})
  write('projects/real/value.ts','export const n = 1;\n')
  config('packages/'+sol+'/tsconfig.json',{'files':[],'references':[{'path':'../../projects/real'}]})
  # Remove the reference to the solution package from the ordinary package.
  project('packages/'+normal)
  solution={'packages/'+sol}
 if mode in ('untracked','tree-signal','no-signal'):
  # beta remains a discovered suite but inference must not name its folder.
  a.pop('references');config('packages/alpha/tsconfig.json',a)
  project('packages/beta',signal=mode=='untracked');expected_targets=['packages/alpha'];omit={'packages/alpha'}
 if mode=='root-only':
  project('packages/alpha',False);project('packages/beta',False)
  config('tsconfig.json',{'files':[],'references':[{'path':'packages/alpha'},{'path':'packages/beta'}]})
  expected_targets=['.'];omit=set()
 if mode=='proof-fails':write('packages/beta/value.ts','export const value: number = "wrong";\n');expected_targets=[];omit=set()
 if mode=='proof-reference':
  a['references']=[{'path':'../missing'}];config('packages/alpha/tsconfig.json',a);expected_targets=[];omit=set()
 if mode in ('manifest-invalid','glob-invalid'):
  if mode=='manifest-invalid':write('pnpm-workspace.yaml','packages: [packages/*, 42]\n')
  else:pkg['workspaces']=['packages/*','modules/[ab]']
  expected_targets=[];omit=set()
config('package.json',pkg)
write('.gitignore','node_modules/\n**/dist/\n**/*.tsbuildinfo\n')
run('git','add','-A')
if mode=='untracked':run('git','reset','-q','--','packages/beta/tsconfig.json')
run('git','commit','-qm','test: item 72 fixture')
if mode=='tree-signal':project('packages/beta',True)
if mode=='index-remove':project('.',False)
if mode=='index-add':project('.',True)
if mode=='index-invalid':write('tsconfig.json','{not JSONC')
# A transparent wrapper runs real tsc, then changes the working-tree config.
# Inference already accepted the indexed folder: the suppression rule cannot reread it.
if mode=='proof-mutates':
 compiler=str(P('node_modules/.bin/tsc').resolve());P('node_modules/.bin/tsc').unlink()
 write('node_modules/.bin/tsc','#!/bin/sh\n'+shlex.quote(compiler)+' "$@"\nrc=$?\nif [ "$rc" = 0 ]; then printf "{not JSONC" > tsconfig.json; fi\nexit "$rc"\n');P('node_modules/.bin/tsc').chmod(0o755)
if mode.startswith('existing-'):
 # Sample valid current config, then keep exactly these user-edited bytes.
 run(binary,'init')
 s=P('.shipcraft.toml').read_text()
 if mode=='existing-absent':s='\n'.join(l for l in s.split('\n') if not l.startswith('check = '))
 write('.shipcraft.toml',s);original=P('.shipcraft.toml').read_bytes()
write('.git/shipcraft/sentinel','preserve72\n')
def state():return {str(p):p.read_bytes() for p in P('.git/shipcraft').rglob('*') if p.is_file()}
before_state=state()
rollback=mode.startswith('rollback-')
if rollback:
 if mode=='rollback-file':write('.shipcraft','blocked72\n')
 else:P('.git/hooks').chmod(0o500)
try:p=run(binary,'init',ok=not rollback)
finally:
 if mode=='rollback-hooks':P('.git/hooks').chmod(0o755)
assert state()==before_state,'init changed run state'
if rollback:
 assert p.returncode==2,(p.returncode,p.stdout,p.stderr)
 output=p.stdout+p.stderr
 assert 'shipcraft: undid what this run created' in output,output
 assert ('.shipcraft' if mode=='rollback-file' else 'commit-msg') in output,output
 assert not any('no check written for suite ' in l or 'checks no file;' in l for l in output.splitlines()),'notice leaked on rollback'
 assert not P('.shipcraft.toml').exists() and not P('AGENTS.md').exists() and not P('CLAUDE.md').exists(),'core rollback left created files'
 assert not P('.git/hooks/commit-msg').exists() and not P('.git/hooks/post-commit').exists(),'rollback left hooks'
 if mode=='rollback-file':assert P('.shipcraft').read_text()=='blocked72\n'
 else:assert not P('.shipcraft').exists()
 # Successful proof products survive a later core-write failure.
 assert all(P(folder,'dist/value.js').is_file() for folder in expected_targets),'rollback deleted compiler output'
 sys.exit()
if mode.startswith('existing-'):
 assert P('.shipcraft.toml').read_bytes()==original,'existing config rewritten'
 assert not any('no check written for suite ' in l or 'checks no file;' in l for l in (p.stdout+p.stderr).splitlines()),'kept config emitted suppression notice'
 sys.exit()
d=tomli.loads(P('.shipcraft.toml').read_text());print('GENERATED CONFIG\n'+P('.shipcraft.toml').read_text(),flush=True)
if expected_targets:
 assert shlex.split(d['build']['command'])==['npx','--no','--','tsc','-b']+expected_targets,d
 # Solution folders emit only referenced output; ordinary projects retain their output.
 for folder in set(expected_targets)-solution-({'.'} if mode=='root-only' else set()):assert P(folder,'dist/value.js').is_file(),('proof output missing',folder)
else:
 assert 'build' not in d,d
 if mode=='proof-fails':assert list(P('packages').rglob('*.tsbuildinfo')),'failed proof output was removed'
suites=d.get('suite',[d]);expected_roots=['.'] if root_mode else ['packages/alpha','packages/beta']
assert [s.get('root','.') for s in suites]==expected_roots,suites
# Check uncovered suites first so the RED still exercises the boundary.
for s in suites:
 if s.get('root','.') not in omit:assert s.get('check','').endswith('tsc --noEmit'),('uncovered suite lost check',s)
notices=[]
for s in suites:
 folder=s.get('root','.');name=s.get('name','default');path='tsconfig.json' if folder=='.' else folder+'/tsconfig.json'
 if folder in omit:
  if folder in solution:notices.append(f'shipcraft: {path} checks no file; no check written for suite {name}: [build] type-checks its references')
  else:notices.append(f'shipcraft: no check written for suite {name}: [build] type-checks {path}')
for s in suites:
 if s.get('root','.') in omit:assert 'check' not in s,('covered suite retained check',s)
actual=[l for l in p.stdout.splitlines() if 'no check written for suite ' in l or 'checks no file;' in l]
assert actual==notices,(actual,notices,p.stdout)
if notices:
 lines=p.stdout.splitlines();build_at=next(i for i,l in enumerate(lines) if 'npx --no -- tsc -b ' in l)
 assert lines[build_at+1:build_at+1+len(notices)]==notices,'notices must immediately follow build in suite order'
 assert lines.index(notices[-1])<next(i for i,l in enumerate(lines) if l.startswith('shipcraft: ready. Commit ')),'notice follows closing'
assert not any('no check written for suite ' in l or 'checks no file;' in l for l in p.stderr.splitlines()),'notice must be stdout'
assert P('.shipcraft/locks/.gitkeep').is_file() and P('.shipcraft/briefs/red.md').is_file() and P('.shipcraft/briefs/green.md').is_file(),'core files missing'
assert P('AGENTS.md').is_file() and os.access('.git/hooks/commit-msg',os.X_OK),'onboarding or hooks missing'
assert p.stdout.splitlines()[-1]=='CI runs on this machine through shipcraft pr. To run it on GitHub, see shipcraft docs/github-ci.md.','closing changed'
PY72
  pass
}
