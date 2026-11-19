# Item 134: real project Python, with a deliberately unusable PATH Python.
item134_cases() {
  local c
  for c in repro-a venv priority invalid-dot uv uv-metadata fallback lang custom kept warning inner-ignore rollback late-write ignore-error control-fixture control-node missing-red missing-python3 missing-absolute missing-suite missing-uv missing-hook missing-copy missing-ci missing-redo worktree worktree-copy worktree-absent control-check control-fallback control-no-report control-uv status status-words status-suites status-control guide-python guide-uv control-reader; do echo "v1-134.$c"; done
}
item134_case() {
  EXPECT='item 134 project Python contract'
  v1_start codex claude
  must_accept 'item 134 contract' cmd "$PY" - "${CASE#v1-134.}" "$CW" <<'PY134'
import json, os, re, shlex, shutil, subprocess, sys
from pathlib import Path
import tomli as tomllib
case=sys.argv[1]; cw=Path(sys.argv[2]); root=Path.cwd(); binary=shutil.which('shipcraft')
def write(path,text,mode=0o644):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text);p.chmod(mode)
def run(*args,cwd=None):
 p=subprocess.run(list(map(str,args)),cwd=cwd,env=env,input='',capture_output=True,text=True,timeout=90)
 print('$',shlex.join(list(map(str,args))),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 return p
# No inherited uv or interpreter can leak into the child PATH.
tools=cw/'path134';tools.mkdir()
for name in ('git','sh','bash','env','dirname','basename','uname','sed','cat','mkdir','rm','shipcraft','codex','claude'):
 found=shutil.which(name)
 if found:(tools/name).symlink_to(found)
for name in ('python3','python'):write(tools/name,'#!/bin/sh\nprintf "No module named pytest\\n" >&2\nexit 1\n',0o755)
env=dict(os.environ,PATH=str(tools));env.pop('VIRTUAL_ENV',None)
write('pyproject.toml','[project]\nname="item134"\nversion="0.0.0"\n')
# Preserve a real, relocatable copy of the battery venv, including its pytest.
saved=cw/'saved-venv';shutil.copytree('.venv',saved,symlinks=True)
flags=' -m pytest -p no:cacheprovider --junitxml={junit}'
def ok(*args,cwd=None):
 p=run(*args,cwd=cwd);assert p.returncode==0,('fixture command failed',args,p.stdout,p.stderr);return p
def commit(message):
 ok('git','add','-A');return ok('git','commit','-qm',message)
def remove(path):
 p=Path(path)
 if p.is_symlink() or p.is_file():p.unlink()
 elif p.exists():shutil.rmtree(p)
def venv(where='.venv'):
 remove(where);shutil.copytree(saved,where,symlinks=True)
def uv(exit_code=None):
 write(tools/'uv','#!/bin/sh\nprintf "%s\n" "$@" >> '+shlex.quote(str(cw/'uv-args'))+'\n'+('exit '+str(exit_code)+'\n' if exit_code is not None else 'shift 3\nexec '+shlex.quote(str(root/'.venv/bin/python'))+' "$@"\n'),0o755)
def config(command,check=None,suites=None):
 text='shipcraft_min="0.0"\nlang="python"\nrunner="pytest"\n'
 if suites is None:
  text+='test_command='+json.dumps(command)+'\ntest_globs=["tests/**"]\n'
  if check:text+='check='+json.dumps(check)+'\n'
 text+='[execution]\nci="local"\nreview="off"\n'
 if suites:
  for name,folder,cmd in suites:
   text+='[[suite]]\nname='+json.dumps(name)+'\nroot='+json.dumps(folder)+'\ncommand='+json.dumps(cmd)+'\nglobs=["tests/**"]\n'
 write('.shipcraft.toml',text)
def prepare(command='.venv/bin/python'+flags,check=None,suites=None):
 config(command,check,suites);ok(binary,'init');commit('chore: fixture134')
def failing(folder='.'):
 write(Path(folder)/'shouty.py','def shout(s):\n    raise NotImplementedError\n')
 write(Path(folder)/'tests/test_shout.py','from shouty import shout\ndef test_shout():\n    assert shout("hi") == "HI!"\n')
def lock():
 paths=list(Path('.shipcraft/locks').glob('*.json'));assert len(paths)==1,paths
 return paths[0],json.loads(paths[0].read_text())
def rows():
 path=Path('.git/shipcraft/runs.jsonl')
 return [json.loads(l) for l in path.read_text().splitlines()] if path.is_file() else []
def state():
 return (Path('.shipcraft.toml').read_bytes(),run('git','status','--porcelain').stdout,Path('.git/shipcraft/runs.jsonl').read_bytes() if Path('.git/shipcraft/runs.jsonl').is_file() else None)
def chosen(p,word):
 # Only a reader: each arm owns its expected interpreter and line assertions.
 return tomllib.loads(Path('.shipcraft.toml').read_text())['test_command']==word+flags
if case=='repro-a':
 p=run(binary,'init');assert p.returncode==0,(p.stdout,p.stderr)
 cfg=tomllib.loads(Path('.shipcraft.toml').read_text());print('test_command =',repr(cfg['test_command']),flush=True)
 assert cfg['test_command']=='.venv/bin/python'+flags,('reproduction A: init still writes PATH python3',cfg['test_command'])
 assert cfg['runner']=='pytest' and 'check' not in cfg
 assert cfg['test_globs']==['**/test_*.py','**/*_test.py','**/conftest.py','**/tests/**/fixtures/**','**/tests/**/helpers/**','**/test/**/fixtures/**','**/test/**/helpers/**']
 expected="shipcraft: Python interpreter .venv/bin/python (the project's virtual environment); to use another, edit test_command in .shipcraft.toml"
 lines=p.stdout.splitlines();assert lines[lines.index('shipcraft: language python (runner pytest)')+1]==expected
 assert 'is not ignored by git' not in p.stdout
 commit('chore: inferred Python134');failing();p=run(binary,'red');assert p.returncode==0,(p.stdout,p.stderr)
 assert lock()[1]['state']=='open' and any('test_shout' in x for x in lock()[1]['failing_at_red'])
elif case=='venv':
 remove('.venv');venv('venv');write('.gitignore','venv/\n__pycache__/\n')
 p=run(binary,'init');assert p.returncode==0 and chosen(p,'venv/bin/python'),p.stdout+p.stderr
 expected="shipcraft: Python interpreter venv/bin/python (the project's virtual environment); to use another, edit test_command in .shipcraft.toml"
 lines=p.stdout.splitlines();assert lines[lines.index('shipcraft: language python (runner pytest)')+1]==expected
 commit('chore: venv134');failing();assert run(binary,'red').returncode==0
elif case=='priority':
 venv('venv');write('uv.lock','');uv(91)
 p=run(binary,'init');assert p.returncode==0 and chosen(p,'.venv/bin/python')
 assert not (cw/'uv-args').exists()
 # Executable symlink to the base interpreter is an ordinary venv, not a reason to use uv.
 assert Path('.venv/bin/python').is_symlink()
elif case=='invalid-dot':
 venv('venv')
 for kind in ('absent','dangling','nonexec','directory'):
  remove('.shipcraft.toml');remove('.venv/bin/python')
  if kind=='dangling':Path('.venv/bin/python').symlink_to('absent134')
  elif kind=='nonexec':write('.venv/bin/python','exit 0\n')
  elif kind=='directory':Path('.venv/bin/python').mkdir()
  p=run(binary,'init');assert p.returncode==0 and chosen(p,'venv/bin/python'),(kind,p.stdout,p.stderr)
elif case=='uv':
 remove('.venv');write('uv.lock','');uv()
 p=run(binary,'init');assert p.returncode==0 and chosen(p,'uv run --frozen python'),p.stdout+p.stderr
 expected='shipcraft: Python through uv run --frozen (uv.lock and uv on PATH, no runnable .venv/bin/python or venv/bin/python); to use another, edit test_command in .shipcraft.toml'
 lines=p.stdout.splitlines();assert lines[lines.index('shipcraft: language python (runner pytest)')+1]==expected
 assert not (cw/'uv-args').exists(),'init ran uv'
 # Stub models uv sync from the existing cached venv, never the network.
 venv();commit('chore: uv config134');failing();assert run(binary,'red').returncode==0
 commit('test: RED134');write('shouty.py','def shout(s):\n    return s.upper()+"!"\n');commit('feat: GREEN134')
 assert lock()[1]['state']=='closed'
 args=(cw/'uv-args').read_text().splitlines();assert args[:6]==['run','--frozen','python','-m','pytest','-p'],args
 assert Path('uv.lock').read_bytes()==b''
elif case=='uv-metadata':
 remove('.venv');uv(92)
 for kind in ('file','link','dangling','directory','nonexec-uv','relative-path'):
  remove('.shipcraft.toml');remove('uv.lock');(tools/'uv').chmod(0o755);env['PATH']=str(tools)
  if kind=='link':write('locked134','');Path('uv.lock').symlink_to('locked134')
  elif kind=='dangling':Path('uv.lock').symlink_to('absent134')
  elif kind=='directory':Path('uv.lock').mkdir()
  else:write('uv.lock','')
  if kind=='nonexec-uv':(tools/'uv').chmod(0o644)
  if kind=='relative-path':env['PATH']=os.path.relpath(tools,root)
  p=run(binary,'init');word='uv run --frozen python' if kind in ('file','link','relative-path') else 'python3'
  assert p.returncode==0 and chosen(p,word),(kind,p.stdout,p.stderr)
 assert not (cw/'uv-args').exists()
elif case=='fallback':
 remove('.venv')
 for locked in (False,True):
  remove('.shipcraft.toml')
  if locked:write('uv.lock','')
  p=run(binary,'init');assert p.returncode==0 and chosen(p,'python3')
  expected='shipcraft: Python interpreter python3 from PATH (no runnable .venv/bin/python or venv/bin/python, and no uv.lock with uv on PATH), so the hook runs whichever python3 is first on PATH at commit time; to use another, edit test_command in .shipcraft.toml'
  lines=p.stdout.splitlines();assert lines[lines.index('shipcraft: language python (runner pytest)')+1]==expected
elif case=='lang':
 Path('requirements.txt').unlink();Path('pyproject.toml').unlink()
 p=run(binary,'init','--lang','python');assert p.returncode==0 and chosen(p,'.venv/bin/python')
 assert 'shipcraft: Python interpreter .venv/bin/python' in p.stdout
elif case=='custom':
 command='python3 -m pytest --junitxml={junit} # literal134'
 p=run(binary,'init','--lang','other','--command',command,'--glob','tests/**')
 assert p.returncode==0 and tomllib.loads(Path('.shipcraft.toml').read_text())['test_command']==command
 assert not re.search(r'^shipcraft: Python',p.stdout,re.M)
 assert 'test command run as written' in p.stdout
elif case=='kept':
 config('python3'+flags);before=Path('.shipcraft.toml').read_bytes()
 p=run(binary,'init');assert p.returncode==0 and Path('.shipcraft.toml').read_bytes()==before
 assert not re.search(r'^shipcraft: (python|node|go)\b',p.stdout,re.I|re.M)
 assert '.shipcraft.toml already exists, kept' in p.stdout
elif case=='warning':
 for folder in ('.venv','venv'):
  if folder=='venv':remove('.shipcraft.toml');remove('.venv');venv('venv')
  write('.gitignore','__pycache__/\n');remove(folder+'/.gitignore')
  p=run(binary,'init');assert p.returncode==0
  expected='shipcraft: warning: '+folder+'/bin/python is not ignored by git, and the hook and ci run the suite in a copy that links only ignored files when the tree differs from what they judge: add '+folder+'/ to .gitignore before committing'
  lines=p.stdout.splitlines();assert lines[ next(i for i,l in enumerate(lines) if l.startswith('shipcraft: ready.'))-1]==expected,p.stdout
elif case=='inner-ignore':
 write('.gitignore','__pycache__/\n');write('.venv/.gitignore','*\n')
 p=run(binary,'init');assert p.returncode==0 and chosen(p,'.venv/bin/python')
 assert 'is not ignored by git' not in p.stdout
 assert run('git','check-ignore','-q','--','.venv/bin/python').returncode==0
elif case=='rollback':
 write('.gitignore','__pycache__/\n');remove('.venv/.gitignore');write('.shipcraft','block134\n')
 p=run(binary,'init');assert p.returncode==2 and not Path('.shipcraft.toml').exists()
 assert 'undid what this run created' in p.stdout+p.stderr
 assert 'shipcraft: Python interpreter .venv/bin/python' in p.stdout and 'is not ignored by git' not in p.stdout
elif case=='late-write':
 write('.gitignore','__pycache__/\n');remove('.venv/.gitignore');write('.shipcraft/briefs','block134\n')
 p=run(binary,'init');assert p.returncode==0 and Path('.shipcraft.toml').is_file()
 assert '.shipcraft/briefs not written' in p.stdout
 assert 'shipcraft: Python interpreter .venv/bin/python' in p.stdout and 'is not ignored by git' in p.stdout
elif case=='ignore-error':
 realgit=str((tools/'git').resolve());(tools/'git').unlink()
 write(tools/'git','#!/bin/sh\nif [ "$1" = check-ignore ]; then printf "%s\n" "$@" > '+shlex.quote(str(cw/'ignore-args'))+'; exit 73; fi\nexec '+shlex.quote(realgit)+' "$@"\n',0o755)
 p=run(binary,'init');assert p.returncode==0 and chosen(p,'.venv/bin/python')
 assert (cw/'ignore-args').read_text().splitlines()==['check-ignore','-q','--','.venv/bin/python']
 assert 'is not ignored by git' not in p.stdout
elif case=='control-fixture':
 # Proves the same venv, PATH, uv and Git wrapper ingredients without inference.
 for word in ('python','python3'):
  p=run(word,'-m','pytest');assert p.returncode==1 and p.stderr=='No module named pytest\n'
 uv();p=run('uv','run','--frozen','python','-m','pytest','-q','tests/test_smoke.py')
 assert p.returncode==0 and '1 passed' in p.stdout
 assert (cw/'uv-args').read_text().splitlines()==['run','--frozen','python','-m','pytest','-q','tests/test_smoke.py']
 realgit=str((tools/'git').resolve());(tools/'git').unlink()
 write(tools/'git','#!/bin/sh\nif [ "$1" = check-ignore ]; then printf "%s\n" "$@" > '+shlex.quote(str(cw/'ignore-args'))+'; exit 73; fi\nexec '+shlex.quote(realgit)+' "$@"\n',0o755)
 assert run('git','check-ignore','-q','--','.venv/bin/python').returncode==73
 assert (cw/'ignore-args').read_text().splitlines()==['check-ignore','-q','--','.venv/bin/python']
 prepare();failing();p=run(binary,'red');assert p.returncode==0 and any('test_shout' in x for x in lock()[1]['failing_at_red'])
elif case=='control-node':
 p=run(binary,'init','--lang','node');assert p.returncode==0
 assert 'language node (runner vitest)' in p.stdout and not re.search(r'^shipcraft: Python',p.stdout,re.M)
 assert tomllib.loads(Path('.shipcraft.toml').read_text())['runner']=='vitest'
elif case in ('missing-red','missing-python3','missing-absolute','missing-suite','missing-uv','missing-hook','missing-copy','missing-ci','missing-redo'):
 word='.venv/bin/python';folder='.';name='.';key='test_command';args=['red']
 if case=='missing-python3':word='.venv/bin/python3'
 elif case=='missing-absolute':word=str(cw/'absent/bin/python')
 elif case=='missing-suite':folder='packages/api';name='api134';key='command of [[suite]] api134';write(folder+'/tests/test_ok.py','def test_ok(): assert True\n')
 elif case=='missing-uv':word='uv'
 command='uv run --frozen python'+flags if word=='uv' else word+flags
 if case=='missing-suite':prepare(suites=[(name,folder,command)])
 else:prepare(command)
 base=ok('git','rev-parse','HEAD').stdout.strip();failing(folder)
 if case in ('missing-hook','missing-copy','missing-ci','missing-redo'):
  p=run(binary,'red');assert p.returncode==0,(p.stdout,p.stderr)
  ok('git','add','shouty.py','tests/test_shout.py','.shipcraft/locks');ok('git','commit','-qm','test: RED134')
  beforelock=lock()[0].read_bytes()
  if case=='missing-copy':
   write('.gitignore','__pycache__/\n');remove('.venv/.gitignore')
   p=run(binary,'red','--redo');assert p.returncode==0,(p.stdout,p.stderr)
  if case=='missing-redo':write('tests/test_extra.py','def test_extra(): assert False\n');args=['red','--redo']
  elif case=='missing-ci':args=['ci','--base',base]
  else:
   write('shouty.py','def shout(s):\n    return s.upper()+"!"\n');ok('git','add','shouty.py');args=None
  if case=='missing-copy':write('textutil.py',Path('textutil.py').read_text()+'# unstaged134\n')
 if case!='missing-copy':remove('.venv')
 if case=='missing-python3':
  write('.venv/bin/python3','#!/bin/sh\nrm -- "$0"\nprintf "interpreter removed itself134\n" >&2\nexit 1\n',0o755)
 beforehead=ok('git','rev-parse','HEAD').stdout
 p=run(binary,*args) if args else run('git','commit','-qm','feat: GREEN134')
 out=p.stdout+p.stderr;lines=[l for l in out.splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert p.returncode==1 and len(lines)==3,(p.returncode,out)
 assert 'did not write the JUnit report:' in lines[0]
 if case=='missing-uv':
  assert lines[0].endswith('; uv is not on PATH'),out
  assert lines[1]=="Why: the suite's command runs through uv"
  assert lines[2]=='Next: install uv or edit test_command in .shipcraft.toml; then try again'
 else:
  assert '; its interpreter '+word+" is missing or not executable at the suite's root "+folder in lines[0],out
  assert lines[1]=="Why: the suite's command names a Python interpreter that the folder where the suite ran does not have, as observed after it ran"
  expected=('Next: install that interpreter or edit '+key+' in .shipcraft.toml; then try again' if case=='missing-absolute' else "Next: create it at the suite's root (python3 -m venv .venv and install the test dependencies into it, or uv sync); if it exists in the working tree, add .venv/ to .gitignore, since the hook's copy links only ignored files; or edit "+key+' in .shipcraft.toml; then try again')
  assert lines[2]==expected,(lines[2],expected)
 assert rows()[-1]['code']=='no-report' and rows()[-1]['result']=='refused'
 assert ok('git','rev-parse','HEAD').stdout==beforehead
 if case in ('missing-hook','missing-copy','missing-ci','missing-redo'):assert lock()[0].read_bytes()==beforelock
 else:assert not list(Path('.shipcraft/locks').glob('*.json'))
 if case=='missing-absolute':
  # Later measurement failure must not replace the interpreter-specific refusal.
  remove('.git/shipcraft/runs.jsonl');Path('.git/shipcraft/runs.jsonl').mkdir()
  again=run(binary,'red');assert again.returncode==1
  againlines=[l for l in (again.stdout+again.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
  assert againlines==lines and Path('.git/shipcraft/runs.jsonl').is_dir()
elif case in ('worktree','worktree-copy','worktree-absent'):
 # Main path has a shell metacharacter: replacement must be single-quoted.
 moved=root.with_name(root.name+" space 'quote");root.rename(moved);root=moved;os.chdir(root)
 prepare();failing();ok(binary,'red');commit('test: RED134')
 wt=cw/'linked134';ok('git','worktree','add','-qb','linked134',wt)
 config_bytes=Path('.shipcraft.toml').read_bytes();os.chdir(wt)
 assert not Path('.venv').exists()
 if case=='worktree-absent':remove(root/'.venv')
 write('shouty.py','def shout(s):\n    return s.upper()+"!"\n');ok('git','add','shouty.py')
 if case=='worktree-copy':write('textutil.py',Path('textutil.py').read_text()+'# unstaged134\n')
 p=run('git','commit','-qm','feat: GREEN linked134')
 if case=='worktree-absent':
  assert p.returncode==1 and '; its interpreter .venv/bin/python is missing or not executable' in p.stdout+p.stderr
  assert "the main worktree's" not in p.stderr
 else:
  assert p.returncode==0,(p.stdout,p.stderr)
  expected='shipcraft: suite . runs '+str(root/'.venv/bin/python')+" (this worktree has no .venv; the main worktree's)"
  assert expected in p.stderr and p.stderr.index(expected)<p.stderr.index('running the suite'),p.stderr
  assert lock()[1]['state']=='closed'
 assert Path('.shipcraft.toml').read_bytes()==config_bytes
elif case=='control-check':
 remove('.venv');check='cp -R '+shlex.quote(str(saved))+' .venv'
 (tools/'cp').symlink_to(shutil.which('cp'))
 prepare(check=check);failing();p=run(binary,'red')
 assert p.returncode==0 and Path('.venv/bin/python').exists() and lock()[1]['state']=='open'
elif case=='control-fallback':
 # A shell fallback writes the real report, despite the missing first interpreter.
 prepare('.absent/bin/python'+flags+' || '+shlex.quote(str(saved/'bin/python'))+flags)
 failing();p=run(binary,'red');assert p.returncode==0 and lock()[1]['state']=='open'
 assert 'its interpreter' not in p.stdout+p.stderr
elif case=='control-no-report':
 for command in ('python3'+flags,'bin/python'+flags,'.venv/bin/python -c "pass" # {junit}','env .absent/bin/python'+flags,'".absent/bin/python"'+flags):
  config(command);ok(binary,'init');ok('git','add','.shipcraft.toml','.shipcraft','AGENTS.md','CLAUDE.md');failing();p=run(binary,'red')
  assert p.returncode==1 and 'did not write the JUnit report:' in p.stdout+p.stderr
  assert 'create the stub' in p.stdout+p.stderr and 'its interpreter' not in p.stdout+p.stderr
  assert rows()[-1]['code']=='no-report'
elif case=='control-uv':
 uv();prepare('uv run --frozen python'+flags);failing();p=run(binary,'red')
 assert p.returncode==0 and lock()[1]['state']=='open'
 assert (cw/'uv-args').read_text().splitlines()[:6]==['run','--frozen','python','-m','pytest','-p']
elif case=='status':
 venv('venv')
 prepare('python3'+flags);before=state();p=run(binary,'status');assert p.returncode==0 and state()==before
 expected="shipcraft: suite . runs python3 from PATH, but ./.venv/bin/python is the project's virtual environment; to use it, start test_command with .venv/bin/python in .shipcraft.toml"
 lines=p.stdout.splitlines();assert lines[next(i for i,l in enumerate(lines) if l.startswith('shipcraft: open locks:'))+1]==expected,p.stdout
elif case=='status-words':
 for word,space,folder in [('python','\t','.venv'),('python3','\r\n','venv')]:
  if folder=='venv':remove('.venv');venv('venv')
  config(space+word+'\t-m pytest --junitxml={junit}');p=run(binary,'status')
  expected='shipcraft: suite . runs '+word+' from PATH, but ./'+folder+"/bin/python is the project's virtual environment; to use it, start test_command with "+folder+'/bin/python in .shipcraft.toml'
  assert p.returncode==0 and expected in p.stdout,p.stdout
elif case=='status-suites':
 venv('packages/a/.venv');venv('packages/b/venv')
 config('',suites=[('beta','packages/b','python'+flags),('alpha','packages/a','python3'+flags)])
 before=state();p=run(binary,'status');assert p.returncode==0 and state()==before
 lines=p.stdout.splitlines();i=next(i for i,l in enumerate(lines) if l.startswith('shipcraft: open locks:'))
 expected=["shipcraft: suite beta runs python from PATH, but packages/b/venv/bin/python is the project's virtual environment; to use it, start command of [[suite]] beta with venv/bin/python in .shipcraft.toml", "shipcraft: suite alpha runs python3 from PATH, but packages/a/.venv/bin/python is the project's virtual environment; to use it, start command of [[suite]] alpha with .venv/bin/python in .shipcraft.toml"]
 assert lines[i+1:i+3]==expected,p.stdout
elif case=='status-control':
 for command in ('.venv/bin/python'+flags,'uv run --frozen python'+flags,'env python3'+flags,'"python3"'+flags,'python3x'+flags,'python3\u00a0-m pytest --junitxml={junit}'):
  config(command);p=run(binary,'status');assert p.returncode==0 and 'from PATH, but' not in p.stdout
  assert 'open locks: none' in p.stdout
 remove('.venv');config('python3'+flags);p=run(binary,'status');assert p.returncode==0 and 'from PATH, but' not in p.stdout
elif case in ('guide-python','guide-uv'):
 import yaml
 guide=(Path(os.environ['ACEITE']).parent/'docs/github-ci.md').read_text();part=guide.split('## Language setup',1)[1].split('## Setup limits',1)[0]
 blocks=[yaml.safe_load(b) for b in re.findall(r'```ya?ml\s*\n(.*?)```',part,re.S)]
 steps=[step for block in blocks if isinstance(block,list) for step in block]
 if case=='guide-python':
  matches=[s for s in steps if 'python3 -m venv .venv' in s.get('run','')];assert len(matches)==1,'Python setup must create .venv'
  step=matches[0];script=step['run'];assert step['if']=="steps.layer.outputs.run == 'true'"
  required=['python3 -m venv .venv','.venv/bin/python -m pip install pytest','for f in requirements*.txt; do','if [ -f "$f" ]; then .venv/bin/python -m pip install -r "$f"; fi','echo "$PWD/.venv/bin" >> "$GITHUB_PATH"']
  assert all(x in script for x in required) and [script.index(x) for x in required]==sorted(script.index(x) for x in required),script
  assert re.search(r'(?<![.\w])venv/bin/python',part) and re.search(r'replace|substitut|change',part,re.I)
  assert 'pyproject.toml' in guide.split('## Setup limits',1)[1] and 'requirements' in guide.split('## Setup limits',1)[1]
 else:
  installers=[s for s in steps if s.get('uses')=='astral-sh/setup-uv@v6'];assert len(installers)==1,'uv alternative setup missing'
  matches=[s for s in steps if 'uv sync --frozen' in s.get('run','')];assert len(matches)==1
  assert installers[0]['if']==matches[0]['if']=="steps.layer.outputs.run == 'true'"
  script=matches[0]['run'];assert 'echo "$PWD/.venv/bin" >> "$GITHUB_PATH"' in script and script.index('uv sync --frozen')<script.index('GITHUB_PATH')
  assert '--group' in part
elif case=='control-reader':
 # ASCII first-word limits and executable-but-no-pytest remain ordinary no-report.
 for command in ('\t.venv/bin/python -c "pass" # {junit}','python3\u00a0-m pytest --junitxml={junit}','X=1 .absent/bin/python'+flags):
  config(command);ok(binary,'init');ok('git','add','.shipcraft.toml','.shipcraft','AGENTS.md','CLAUDE.md');failing();p=run(binary,'red')
  assert p.returncode==1 and 'did not write the JUnit report:' in p.stdout+p.stderr and 'its interpreter' not in p.stdout+p.stderr
  assert 'create the stub' in p.stdout+p.stderr
else:raise AssertionError('unrouted '+case)
PY134
  pass
}
