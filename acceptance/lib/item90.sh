# Item 90: kept-config init, installed/public binary only.
item90_langs() { echo core; }
item90_cases() {
  local c
  for c in kept-none kept-multiple kept-reverse kept-subfolder kept-ci-local kept-ci-github control-detected control-history explicit-python explicit-node explicit-go explicit-other workspace-multiple workspace-flow workspace-invalid config-link config-dangling config-invalid config-folder config-unreadable foreign-hook foreign-before-invalid rollback rollback-multiple agents-link briefs-file no-config no-config-multiple flag-command flag-glob flag-unknown flag-other-invalid github github-failure control-github hook-raise hook-rollback control-hook control-rollback control-github-failure; do echo "v1-90.$c"; done
}
item90_case() {
  EXPECT="item 90: ${CASE#v1-90.}"
  v1_start codex claude
  must_accept 'item 90 init contract' cmd "$PY" - "${CASE#v1-90.}" "$(command -v shipcraft)" "$CW" "$ACEITE" "$ST" <<'PY90'
import ast,os,re,stat,subprocess,sys
from pathlib import Path
case,binary,cw,acceptance,st=sys.argv[1:]
binary=str(Path(binary).resolve());cw=Path(cw);st=Path(st)
sys.path.insert(0,str(Path(acceptance)/'tools'))
from lefthook_fixture import HOOK
# Frozen historical bytes from acceptance only; no implementation reader.
source=(Path(acceptance)/'lib/item61.sh').read_text().split("<<'PY61'\n",1)[1].split('\nPY61',1)[0]
old=next(ast.literal_eval(n.value.func.value).encode() for n in ast.parse(source).body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='PREVIOUS_BARE' for t in n.targets))
def run(*args,cwd=None):
 p=subprocess.run(list(map(str,args)),cwd=cwd,input=b'',capture_output=True,timeout=90)
 print('$',repr(args),'[rc='+str(p.returncode)+']\n'+(p.stdout+p.stderr).decode(errors='replace'),flush=True)
 return p
def ok(*args,cwd=None):
 p=run(*args,cwd=cwd);assert p.returncode==0,('fixture failed',p.returncode,p.stdout,p.stderr)
 return p
def write(name,data,mode=None):
 p=Path(name);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
 if mode is not None:p.chmod(mode)
def snapshot():
 result={}
 for p in Path('.').rglob('*'):
  mode=p.lstat().st_mode
  result[str(p)]=(stat.S_IMODE(mode),os.readlink(p) if stat.S_ISLNK(mode) else p.read_bytes() if stat.S_ISREG(mode) else None)
 return result
def multiple(reverse=False):
 for name,data in ([('go.mod','module example.com/item90\n\ngo 1.21\n'),('requirements.txt','pytest\n')] if reverse else [('requirements.txt','pytest\n'),('go.mod','module example.com/item90\n\ngo 1.21\n')]):write(name,data)
def workspace(flow=False):
 write('pnpm-workspace.yaml','packages: ["packages/*"]\n' if flow else 'packages:\n  - "packages/*"\n')
 write('package.json','{"name":"root","private":true}\n')
 write('packages/api/package.json','{"name":"api","devDependencies":{"vitest":"*"}}\n')
 write('packages/api/a.test.js','import {it} from "vitest"; it("ok",()=>{});\n')
 ok('git','add','packages','package.json','pnpm-workspace.yaml')
def hook():
 write('lefthook.yml','pre-commit:\n  commands:\n    lint:\n      run: echo lint90\n')
 for event in ('commit-msg','post-commit'):
  write('.git/hooks/'+event,HOOK.replace('run "pre-commit"','run "'+event+'"'),0o755)
def github():
 origin=cw/'origin90.git';ok('git','init','-q','--bare',origin)
 ok('git','add','README.md');ok('git','commit','-qm','fixture90')
 ok('git','remote','add','origin',origin);ok('git','push','-q','origin','main');ok('git','fetch','-q','origin');ok('git','remote','set-head','origin','main')
 write(st/'origin',str(origin)+'\n')
root=cw/"project90 space 'quote";root.mkdir();os.chdir(root)
ok('git','init','-q','-b','main')
for key,value in [('gc.auto','0'),('maintenance.auto','false'),('gc.autoDetach','false')]:ok('git','config',key,value)
write('README.md','hand-written project90\n')
write('.git/shipcraft/sentinel90',b'preserve90\r\n\x00')
config=b'# hand-written90\r\nshipcraft_min = "0.0"\r\ntest_command = "touch ran90; false # {junit}"\r\ntest_globs = ["tests/**"]\r\nfilter = "command"\r\n[execution]\r\nci = "off"\r\nreview = "off"\r\n'
write('.shipcraft.toml',config)
args=[];cwd=root;kind='success';diagnostic=None;language=None
if case=='kept-none':
 write('AGENTS.md',b'Before90\r\n'+old+b'After90 no newline',0o751)
elif case=='kept-multiple':
 multiple();write('AGENTS.md',b'Before90\r\n'+old+b'After90 no newline',0o751)
elif case=='kept-reverse':
 multiple(True)
elif case=='kept-subfolder':
 cwd=root/'nested90';cwd.mkdir();write(cwd/'.shipcraft.toml',b'not the root config90\n')
elif case=='kept-ci-local':
 config=config.replace(b'ci = "off"',b'ci = "local"');write('.shipcraft.toml',config)
elif case=='kept-ci-github':
 config=config.replace(b'ci = "off"',b'ci = "github"');write('.shipcraft.toml',config)
elif case=='control-detected':
 write('requirements.txt','pytest\n');language='python'
elif case=='control-history':
 write('requirements.txt','pytest\n');write('AGENTS.md',b'Before90\r\n'+old+b'After90 no newline',0o751);language='python'
elif case=='explicit-python':
 multiple();args=['--lang','python'];language='python'
elif case=='explicit-node':
 multiple();args=['--lang','node'];language='node'
elif case=='explicit-go':
 args=['--lang','go'];language='go'
elif case=='explicit-other':
 multiple();args=['--lang','other','--command','false {junit}','--glob','custom/**'];language='other'
elif case=='workspace-multiple':
 multiple();workspace();kind='workspace'
elif case=='workspace-flow':
 multiple(True);workspace(True) # Today's init does not plan a suite from this flow form.
elif case=='workspace-invalid':
 write('pnpm-workspace.yaml','packages: null\n') # Today's planner treats this as no workspace.
elif case=='config-link':
 Path('.shipcraft.toml').rename('target90');Path('.shipcraft.toml').symlink_to('target90');kind='refusal';diagnostic='shipcraft_min'
elif case=='config-dangling':
 Path('.shipcraft.toml').unlink();Path('.shipcraft.toml').symlink_to('missing90');kind='refusal';diagnostic='shipcraft_min'
elif case=='config-invalid':
 write('.shipcraft.toml','not TOML [\n');kind='refusal';diagnostic='shipcraft_min'
elif case=='config-folder':
 Path('.shipcraft.toml').unlink();Path('.shipcraft.toml').mkdir();kind='error';diagnostic='.shipcraft.toml'
elif case=='config-unreadable':
 Path('.shipcraft.toml').chmod(0);kind='error';diagnostic='.shipcraft.toml'
elif case=='foreign-hook':
 write('.git/hooks/commit-msg','#!/bin/sh\necho foreign90\n',0o755);kind='refusal';diagnostic='commit-msg'
elif case=='foreign-before-invalid':
 write('.shipcraft.toml','not TOML [\n');write('.git/hooks/post-commit','#!/bin/sh\necho foreign90\n',0o755);kind='refusal';diagnostic='post-commit'
elif case=='rollback':
 write('.shipcraft','blocked90\r\n');kind='error';diagnostic='.shipcraft'
elif case=='rollback-multiple':
 multiple();write('.shipcraft','blocked90\r\n');kind='error';diagnostic='.shipcraft'
elif case=='agents-link':
 write('target-agents90','external90\r\n');Path('AGENTS.md').symlink_to('target-agents90')
elif case=='briefs-file':
 write('.shipcraft/briefs','blocked briefs90\r\n')
elif case=='no-config':
 Path('.shipcraft.toml').unlink();kind='refusal';diagnostic='could not recognize'
elif case=='no-config-multiple':
 Path('.shipcraft.toml').unlink();multiple();kind='refusal';diagnostic='more than one'
elif case=='flag-command':
 args=['--command','false {junit}'];kind='refusal';diagnostic='--lang other'
elif case=='flag-glob':
 multiple();args=['--glob','tests/**'];kind='refusal';diagnostic='--lang other'
elif case=='flag-unknown':
 args=['--lang','rust'];kind='refusal';diagnostic='rust'
elif case=='flag-other-invalid':
 args=['--lang','other','--command','false','--glob','tests/**'];kind='refusal';diagnostic='command'
elif case=='github':
 github();write(st/'protection','none\n');args=['--github']
elif case=='github-failure':
 multiple();github();write(st/'protection','403\n');args=['--github']
elif case=='control-github':
 write('requirements.txt','pytest\n');github();write(st/'protection','none\n');args=['--github'];language='python'
elif case=='hook-raise':
 hook();kind='integration'
elif case=='hook-rollback':
 multiple();hook();write('.shipcraft','blocked90\r\n');kind='error';diagnostic='.shipcraft'
elif case=='control-hook':
 write('requirements.txt','pytest\n');hook();kind='integration';language='python'
elif case=='control-rollback':
 write('requirements.txt','pytest\n');hook();write('.shipcraft','blocked90\r\n');kind='error';diagnostic='.shipcraft';language='python'
elif case=='control-github-failure':
 write('requirements.txt','pytest\n');github();write(st/'protection','403\n');args=['--github'];language='python'
else:raise AssertionError('unrouted case: '+case)
# Read permission fixture before denying the child read, without weakening its mode assertion.
if case=='config-unreadable':
 Path('.shipcraft.toml').chmod(0o600);before=snapshot();Path('.shipcraft.toml').chmod(0)
 before['.shipcraft.toml']=(0,config)
else:before=snapshot()
p=run(binary,'init',*args,cwd=cwd);text=(p.stdout+p.stderr).decode(errors='replace')
if case=='config-unreadable':
 Path('.shipcraft.toml').chmod(0o600);after=snapshot();Path('.shipcraft.toml').chmod(0)
 after['.shipcraft.toml']=(0,after['.shipcraft.toml'][1])
else:after=snapshot()
if kind in ('refusal','error'):
 assert p.returncode==(1 if kind=='refusal' else 2),('wrong later refusal/error',p.returncode,text)
 assert diagnostic.lower() in text.lower(),('wrong refusal/error reason',diagnostic,text)
 assert after==before,('refusal/error changed tree',sorted(k for k in set(before)|set(after) if before.get(k)!=after.get(k)))
 assert 'ready. Commit' not in text,text
 if kind=='refusal' or case in ('config-folder','config-unreadable'):assert 'already exists, kept' not in text,text
 if kind=='refusal':
  lines=[x for x in text.splitlines() if x.strip()]
  assert len(lines)==3 and all(x.startswith(prefix) for x,prefix in zip(lines,('shipcraft refused:','Why:','Next:'))),lines
 else:assert 'shipcraft: error:' in text,text
else:
 assert p.returncode==0,('kept config must permit init',p.returncode,text)
 if kind!='integration':assert Path('.shipcraft.toml').read_bytes()==config,'config bytes changed'
 assert 'already exists, kept' in text and 'ready. Commit' in text,text
 assert Path('.shipcraft/locks/.gitkeep').read_bytes()==b''
 if kind=='integration':
  version=ok(binary,'--version').stdout.decode().split()[1]
  minimum='.'.join(version.split('.')[:2]).encode()
  assert Path('.shipcraft.toml').read_bytes()==config.replace(b'shipcraft_min = "0.0"',b'shipcraft_min = "'+minimum+b'"'),'integration changed bytes beyond minimum'
  assert 'shipcraft_min' in text,text
  data=Path('lefthook.yml').read_text()
  assert 'run: shipcraft check --commit-msg' in data and 'run: shipcraft close' in data,data
  for event in ('commit-msg','post-commit'):assert Path('.git/hooks/'+event).read_bytes()==before['.git/hooks/'+event][1]
 else:
  for event,command in [('commit-msg','check --commit-msg'),('post-commit','close')]:
   f=Path('.git/hooks/'+event);assert os.access(f,os.X_OK) and command in f.read_text(),event
 if kind=='workspace':assert 'shipcraft: workspace node with 1 suite(s)' in text,text
 elif language is None:
  assert not re.search(r'(?im)^shipcraft: (?:language|runner|workspace)\b|run as written',text),text
  assert not re.search(r'(?im)^shipcraft: (?:python|node|go)\b',text),text
 elif language=='other':assert 'test command run as written' in text and 'only seed a new config' in text,text
 else:assert re.search(language,text,re.I) and re.search('pytest|vitest|jest|gotestsum|go test',text),text
 if case in ('kept-none','kept-multiple','control-history'):
  agents=Path('AGENTS.md').read_bytes()
  assert agents!=before['AGENTS.md'][1] and agents.startswith(b'Before90\r\n') and agents.endswith(b'After90 no newline')
  assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
  before_status=snapshot();s=run(binary,'status');assert s.returncode==0 and b'shipcraft: AGENTS.md block: current\n' in s.stdout,(s.stdout,s.stderr)
  assert snapshot()==before_status,'status changed files'
 if case=='agents-link':
  assert Path('AGENTS.md').is_symlink() and Path('target-agents90').read_bytes()==b'external90\r\n'
  assert 'AGENTS.md' in text and ('could not' in text or 'not written' in text),text
 if case=='briefs-file':
  assert Path('.shipcraft/briefs').read_bytes()==b'blocked briefs90\r\n'
  assert '.shipcraft/briefs' in text and ('could not' in text or 'not written' in text),text
 if case in ('github','control-github'):
  assert (st/'protection').read_text().strip()!='none','protect not attempted'
  result=ok(os.environ['PY'],Path(acceptance)/'tools/h.py','protect-ok',st);assert result.stdout.strip()==b'OK'
 if case in ('github-failure','control-github-failure'):assert (st/'protection').read_text().strip()=='403' and 'no branch protection on its GitHub plan' in text,text
 ci=re.search(rb'ci = "([^"]+)"',config).group(1).decode()
 last=text.strip().splitlines()[-1]
 assert last=={'off':'CI is off ([execution] ci = "off").','local':'CI runs on this machine through shipcraft pr. To run it on GitHub, see shipcraft docs/github-ci.md.','github':'CI runs on GitHub: the workflow is in shipcraft docs/github-ci.md if the project does not have one yet.'}[ci],last
 assert not Path('ran90').exists() and not Path('.github').exists(),'init executed command or created workflow'
if language is None and kind!='workspace':
 assert not re.search(r'(?im)^shipcraft: (?:language|runner|workspace)\b|run as written',text),text
assert Path('.git/shipcraft/sentinel90').read_bytes()==b'preserve90\r\n\x00'
assert not Path('.git/shipcraft/runs.jsonl').exists(),'init wrote a measurement row'
PY90
  pass
}
