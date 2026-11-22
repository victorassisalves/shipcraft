# Item 152: cached Poetry environments through real Git and pytest fixtures.
item152_cases() {
  local c
  for c in \
    repro missing-at-init dot-venv plain-venv uv-first uv-off-path \
    lock-link not-a-lock-file nonexec-poetry relative-path pep621 explicit-python \
    custom kept init-rollback hook-copy hook-tree red-linked \
    named-copy ci-copy quoted-path hook-log ignored-project-venv venv-file \
    parent-project explicit-project run-pytest python3-copy borrowed-venv redo-linked \
    missing-red missing-hook missing-ci missing-named poetry-no-report missing-linked \
    missing-redo narrowed-fallback guide-poetry guide-kept; do echo "v1-152.$c"; done
}
item152_case() {
  EXPECT='item 152 project Python contract'
  v1_start codex claude
  must_accept 'item 152 contract' cmd "$PY" - "${CASE#v1-152.}" "$CW" <<'PY152'
import json, os, shlex, shutil, subprocess, sys
from pathlib import Path
import tomli as tomllib
case=sys.argv[1]; cw=Path(sys.argv[2]); root=Path.cwd(); binary=shutil.which('shipcraft')
def write(path,text,mode=0o644):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text);p.chmod(mode)
def run(*args,cwd=None):
 p=subprocess.run(list(map(str,args)),cwd=cwd,env=env,input=b'',capture_output=True,timeout=90)
 print('$',shlex.join(list(map(str,args))),'[rc='+str(p.returncode)+']\n'+(p.stdout+p.stderr).decode('utf-8','backslashreplace'),flush=True)
 return p
# No inherited uv or interpreter can leak into the child PATH.
tools=cw/'path152';tools.mkdir()
for name in ('git','sh','bash','env','dirname','basename','uname','sed','cat','mkdir','rm','shipcraft','codex','claude'):
 found=shutil.which(name)
 if found:(tools/name).symlink_to(found)
for name in ('python3','python'):write(tools/name,'#!/bin/sh\nprintf "No module named pytest\\n" >&2\nexit 1\n',0o755)
env=dict(os.environ,PATH=str(tools))
for key in ('VIRTUAL_ENV','SHIPCRAFT_OUTPUT','GITHUB_ACTIONS'):
 env.pop(key,None)
write('pyproject.toml','[tool.poetry]\nname="p152"\nversion="0.0.0"\n')
# Preserve a real, relocatable copy of the battery venv, including its pytest.
saved=cw/'saved-venv';shutil.copytree('.venv',saved,symlinks=True)
root=root.resolve();cw=cw.resolve();shutil.rmtree('.venv')
write('poetry.lock','')
write('tests/test_ok.py','def test_ok(): assert True\n')
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
def config(command,check=None,suites=None,build=None):
 text='shipcraft_min="0.0"\nlang="python"\nrunner="pytest"\n'
 if suites is None:
  text+='test_command='+json.dumps(command)+'\ntest_globs=["tests/**"]\n'
  if check:text+='check='+json.dumps(check)+'\n'
 text+='[execution]\nci="local"\nreview="off"\n'
 if build is not None:text+='[build]\ncommand='+json.dumps(build)+'\n'
 if suites:
  for name,folder,cmd in suites:
   text+='[[suite]]\nname='+json.dumps(name)+'\nroot='+json.dumps(folder)+'\ncommand='+json.dumps(cmd)+'\nglobs=["tests/**"]\n'
 write('.shipcraft.toml',text)
def prepare(command='poetry run python'+flags,check=None,suites=None,build=None):
 config(command,check,suites,build);ok(binary,'init');commit('chore: fixture152');return git('rev-parse','HEAD')
def failing(folder='.'):
 write(Path(folder)/'shouty.py','def shout(s):\n    raise NotImplementedError\n')
 write(Path(folder)/'tests/test_shout.py','from shouty import shout\ndef test_shout():\n    assert shout("hi") == "HI!"\n')
def lock():
 paths=list(Path('.shipcraft/locks').glob('*.json'));assert len(paths)==1,paths
 return paths[0],json.loads(paths[0].read_text())
def git(*args,cwd=None):
 return ok('git',*args,cwd=cwd).stdout.decode().strip()

def poetry(project=None):
 # Model the project-keyed environment and Poetry 2's -P/--project, which keeps cwd.
 # The stub runs the saved interpreter only for the declared project folder.
 write(tools/'poetry','#!/bin/sh\nexec '+shlex.quote(sys.executable)+' '+shlex.quote(str(cw/'poetry.py'))+' "$@"\n',0o755)
 write(cw/'poetry.py',"""import json, os, sys
from pathlib import Path

args = sys.argv[1:]
cwd = Path.cwd().resolve()
root = next((p for p in (cwd, *cwd.parents) if (p / '.git').exists()), cwd)
root_venv = root / '.venv'
with open({trace!r}, 'a') as log:
    log.write(json.dumps(dict(cwd=str(cwd), args=args, root_venv_link=root_venv.is_symlink(),
                         root_venv_file=root_venv.is_file(), cwd_venv_dir=(cwd / '.venv').is_dir())) + '\\n')
project = cwd
if args and args[0] in ('-P', '--project'):
    project = (cwd / args[1]).resolve()
    args = args[2:]
if args[:2] == ['run', 'python'] and project == Path({project!r}):
    interpreter = {interpreter!r}
    os.execv(interpreter, [interpreter, *args[2:]])
print('No module named pytest', file=sys.stderr)
sys.exit(1)
""".format(trace=str(cw/'poetry.jsonl'),project=str(Path(project or root).resolve()),
           interpreter=str(saved/'bin/python')))

def calls():
 trace=cw/'poetry.jsonl'
 return [json.loads(line) for line in trace.read_text().splitlines()] if trace.exists() else []

def following(data, before):
 lines=data.split(b'\n')
 return lines[lines.index(before)+1]

def choice():
 return tomllib.loads(Path('.shipcraft.toml').read_text())['test_command']

def linked():
 path=cw/'linked152'
 git('worktree','add','-qb','linked152',path)
 os.chdir(path)
 return path

def clear_calls():
 (cw/'poetry.jsonl').unlink(missing_ok=True)

def reds_open():
 ok(binary,'red')
 commit('test: RED152')

def stage_green():
 write('shouty.py','def shout(s):\n    return s.upper()+"!"\n')
 git('add','shouty.py')

def green_commit():
 return run('git','commit','-qm','feat: GREEN152')

def log_path(layer):
 return Path(git('rev-parse','--git-path',f'shipcraft/output/{layer}.log'))

def rows():
 path=root/'.git/shipcraft/runs.jsonl'
 return [json.loads(line) for line in path.read_text().splitlines()]

def passing_head():
 write('textutil.py','# committed version152\n')
 commit('feat: committed product152')

def dirty_tree():
 write('textutil.py','# unstaged version152\n')

def suite_lines(data):
 return [line for line in data.split(b'\n') if line.startswith(b'shipcraft: suite ') and b' runs poetry -P ' in line]

def placements(data):
 lines=data.split(b'\n')
 return [lines[i-1] for i,line in enumerate(lines) if line.startswith(b'shipcraft: running the suite (')]

def record_shell():
 shell=tools/'sh'
 real_shell=shell.resolve()
 shell.unlink()
 write(shell,'#!'+sys.executable+'\n'+f'''import json, os, sys
with open({str(cw/'shell.jsonl')!r}, 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
os.execv({str(real_shell)!r}, [{str(real_shell)!r}, *sys.argv[1:]])
''',0o755)

def shell_commands():
 path=cw/'shell.jsonl'
 invocations=[json.loads(line) for line in path.read_text().splitlines()]
 return [args[1] for args in invocations if args[:1]==['-c']]

def refusal(data):
 return [line for line in data.split(b'\n') if line.startswith((b'shipcraft refused:',b'Why:',b'Next:'))]

def init_choice_line(p):
 return following(p.stdout,b'shipcraft: language python (runner pytest)')

def guide():
 path=Path(os.environ['ACEITE']).parent/'docs/github-ci.md'
 return path.read_bytes().split(b'## Language setup\n',1)[1].split(b'## Setup limits\n',1)[0]

def guide_steps(section):
 import yaml
 return yaml.safe_load(section.split(b'```yaml\n',1)[1].split(b'```\n',1)[0])

if case=='repro':
 poetry()
 p=ok(binary,'init')
 actual=choice()
 print('test_command =',repr(actual),flush=True)
 assert actual=='poetry run python'+flags,('reproduction: init chose the wrong interpreter',actual)
 assert following(p.stdout,b'shipcraft: language python (runner pytest)')==b'shipcraft: Python through poetry run (poetry.lock and poetry on PATH, no runnable .venv/bin/python or venv/bin/python, and no uv.lock with uv on PATH); to use another, edit test_command in .shipcraft.toml'
 assert not calls() and b'is not ignored by git' not in p.stdout+p.stderr
 commit('chore: inferred Poetry')
 failing()
 ok(binary,'red')
 data=lock()[1]
 assert data['state']=='open' and any('test_shout' in name for name in data['failing_at_red'])
 assert len(calls())==2 and all(c['cwd']==str(root) and c['args'][:6]==['run','python','-m','pytest','-p','no:cacheprovider'] for c in calls()),calls()
elif case=='missing-at-init':
 p=ok(binary,'init')
 expected=b'shipcraft: Python interpreter python3 from PATH (no runnable .venv/bin/python or venv/bin/python, no uv.lock with uv on PATH, and no poetry.lock with poetry on PATH), so the hook runs whichever python3 is first on PATH at commit time; to use another, edit test_command in .shipcraft.toml'
 assert choice()=='python3'+flags and init_choice_line(p)==expected,p.stdout
elif case=='dot-venv':
 venv()
 poetry()
 p=ok(binary,'init')
 expected=b"shipcraft: Python interpreter .venv/bin/python (the project's virtual environment); to use another, edit test_command in .shipcraft.toml"
 assert choice()=='.venv/bin/python'+flags and init_choice_line(p)==expected and not calls(),p.stdout
elif case=='plain-venv':
 venv('venv')
 poetry()
 write('.gitignore','venv/\n__pycache__/\n')
 p=ok(binary,'init')
 expected=b"shipcraft: Python interpreter venv/bin/python (the project's virtual environment); to use another, edit test_command in .shipcraft.toml"
 assert choice()=='venv/bin/python'+flags and init_choice_line(p)==expected and not calls(),p.stdout
elif case=='uv-first':
 poetry()
 write('uv.lock','')
 write(tools/'uv',f'#!/bin/sh\nprintf ran > {shlex.quote(str(cw/"uv-ran"))}\nexit 94\n',0o755)
 p=ok(binary,'init')
 expected=b'shipcraft: Python through uv run --frozen (uv.lock and uv on PATH, no runnable .venv/bin/python or venv/bin/python); to use another, edit test_command in .shipcraft.toml'
 assert choice()=='uv run --frozen python'+flags and init_choice_line(p)==expected,p.stdout
 assert not calls() and not (cw/'uv-ran').exists()
elif case=='uv-off-path':
 poetry()
 write('uv.lock','')
 p=ok(binary,'init')
 assert choice()=='poetry run python'+flags and not calls(),p.stdout
elif case=='lock-link':
 poetry()
 Path('poetry.lock').rename('lock-target')
 Path('poetry.lock').symlink_to('lock-target')
 p=ok(binary,'init')
 assert choice()=='poetry run python'+flags and not calls(),p.stdout
elif case=='not-a-lock-file':
 poetry()
 for kind in ('dangling','directory'):
  remove('.shipcraft.toml')
  remove('poetry.lock')
  if kind=='dangling':Path('poetry.lock').symlink_to('absent152')
  else:Path('poetry.lock').mkdir()
  p=ok(binary,'init')
  expected=b'shipcraft: Python interpreter python3 from PATH (no runnable .venv/bin/python or venv/bin/python, no uv.lock with uv on PATH, and no poetry.lock with poetry on PATH), so the hook runs whichever python3 is first on PATH at commit time; to use another, edit test_command in .shipcraft.toml'
  assert choice()=='python3'+flags and init_choice_line(p)==expected and not calls(),(kind,p.stdout)
elif case=='nonexec-poetry':
 poetry()
 (tools/'poetry').chmod(0o644)
 p=ok(binary,'init')
 expected=b'shipcraft: Python interpreter python3 from PATH (no runnable .venv/bin/python or venv/bin/python, no uv.lock with uv on PATH, and no poetry.lock with poetry on PATH), so the hook runs whichever python3 is first on PATH at commit time; to use another, edit test_command in .shipcraft.toml'
 assert choice()=='python3'+flags and init_choice_line(p)==expected and not calls(),p.stdout
elif case=='relative-path':
 poetry()
 env['PATH']=os.path.relpath(tools,root)
 p=ok(binary,'init')
 assert choice()=='poetry run python'+flags and not calls(),p.stdout
elif case=='pep621':
 poetry()
 write('pyproject.toml','[project]\nname="p152"\nversion="0.0.0"\n')
 p=ok(binary,'init')
 assert choice()=='poetry run python'+flags and not calls(),p.stdout
elif case=='explicit-python':
 poetry()
 remove('pyproject.toml')
 remove('requirements.txt')
 p=ok(binary,'init','--lang','python')
 assert choice()=='poetry run python'+flags and not calls(),p.stdout
elif case=='custom':
 poetry()
 command='python3 -m pytest --junitxml={junit} # exact152'
 p=ok(binary,'init','--lang','other','--command',command,'--glob','tests/**')
 assert choice()==command and b'test command run as written' in p.stdout
 assert b'shipcraft: Python ' not in p.stdout+p.stderr and not calls()
elif case=='kept':
 poetry()
 config('python3'+flags)
 before=Path('.shipcraft.toml').read_bytes()
 p=ok(binary,'init')
 assert Path('.shipcraft.toml').read_bytes()==before and b'.shipcraft.toml already exists, kept' in p.stdout
 assert b'shipcraft: Python ' not in p.stdout+p.stderr and not calls()
 p=ok(binary,'status')
 assert b'open locks: none' in p.stdout and b'from PATH, but' not in p.stdout
elif case=='init-rollback':
 poetry()
 write('.shipcraft','block152\n')
 p=run(binary,'init')
 assert p.returncode==2 and b'undid what this run created' in p.stdout+p.stderr
 assert not Path('.shipcraft.toml').exists() and not calls()
 expected=b'shipcraft: Python through poetry run (poetry.lock and poetry on PATH, no runnable .venv/bin/python or venv/bin/python, and no uv.lock with uv on PATH); to use another, edit test_command in .shipcraft.toml'
 assert init_choice_line(p)==expected,p.stdout
elif case=='hook-copy':
 poetry()
 prepare()
 failing()
 reds_open()
 before=Path('.shipcraft.toml').read_bytes()
 stage_green()
 dirty_tree()
 clear_calls()
 p=green_commit()
 line=f'shipcraft: suite . runs poetry -P {root} (Poetry keys its environment to the project folder, and this run is in another folder)'.encode()
 assert placements(p.stderr)==[line] and suite_lines(p.stderr)==[line],p.stderr
 assert p.returncode==0 and lock()[1]['state']=='closed',p.stderr
 assert git('log','-1','--format=%s')=='chore(shipcraft): close lock '+lock()[0].stem
 call,=calls()
 assert call['args'][:8]==['-P',str(root),'run','python','-m','pytest','-p','no:cacheprovider'] and Path(call['cwd'])!=root,call
 assert Path('textutil.py').read_text()=='# unstaged version152\n' and Path('.shipcraft.toml').read_bytes()==before
elif case=='hook-tree':
 record_shell()
 poetry()
 prepare()
 failing()
 reds_open()
 stage_green()
 clear_calls()
 p=green_commit()
 assert p.returncode==0 and lock()[1]['state']=='closed',p.stderr
 assert git('log','-1','--format=%s')=='chore(shipcraft): close lock '+lock()[0].stem
 call,=calls()
 assert call['cwd']==str(root) and call['args'][:6]==['run','python','-m','pytest','-p','no:cacheprovider'],call
 assert not suite_lines(p.stderr)
 junit=next(arg.partition('=')[2] for arg in call['args'] if arg.startswith('--junitxml='))
 executed,=[command for command in shell_commands() if command.startswith('poetry ') and junit in command]
 headers=[entry for entry in log_path('hook').read_bytes().splitlines() if entry.startswith(b'shipcraft: `')]
 assert headers==[f'shipcraft: `{executed}`'.encode()],headers
elif case=='red-linked':
 poetry()
 prepare()
 path=linked()
 before=Path('.shipcraft.toml').read_bytes()
 failing()
 p=run(binary,'red')
 line=f'shipcraft: suite . runs poetry -P {root} (Poetry keys its environment to the project folder, and this run is in another folder)'.encode()
 assert p.returncode==0 and placements(p.stderr)==[line,line] and suite_lines(p.stderr)==[line,line],p.stderr
 assert lock()[1]['state']=='open' and Path('.shipcraft.toml').read_bytes()==before
 assert len(calls())==2 and all(c['cwd']==str(path) and c['args'][:4]==['-P',str(root),'run','python'] for c in calls()),calls()
 headers=[header for header in log_path('red').read_bytes().splitlines() if header.startswith(b'shipcraft: `')]
 assert len(headers)==2 and all(header.startswith(f"shipcraft: `poetry -P '{root}' run python ".encode()) for header in headers),headers
 lock()[0].unlink()
 folder=Path('.shipcraft/locks')
 folder.chmod(0o555)
 try:
  blocked=run(binary,'red')
 finally:
  folder.chmod(0o755)
 assert blocked.returncode==2 and placements(blocked.stderr)==[line,line],blocked.stderr
 assert b'RED locked at' not in blocked.stdout and not list(folder.glob('*.json'))
 new_headers=[entry for entry in log_path('red').read_bytes().splitlines() if entry.startswith(b'shipcraft: `')]
 assert len(new_headers)==2 and all(entry.startswith(f"shipcraft: `poetry -P '{root}' run python ".encode()) for entry in new_headers),new_headers
elif case=='named-copy':
 folder=Path('packages/a')
 write(folder/'pyproject.toml','[project]\nname="a152"\n')
 write(folder/'tests/test_ok.py','def test_ok(): assert True\n')
 # The nearest pyproject wins even though the root has a linked .venv.
 venv()
 poetry(root/folder)
 prepare(suites=[('alpha',str(folder),'poetry run python'+flags)])
 failing(folder)
 reds_open()
 write(folder/'shouty.py','def shout(s):\n    return s.upper()+"!"\n')
 git('add',folder/'shouty.py')
 dirty_tree()
 clear_calls()
 p=green_commit()
 line=f'shipcraft: suite alpha runs poetry -P {root/folder} (Poetry keys its environment to the project folder, and this run is in another folder)'.encode()
 assert p.returncode==0 and placements(p.stderr)==[line] and suite_lines(p.stderr)==[line],p.stderr
 call,=calls()
 assert call['args'][:4]==['-P',str(root/folder),'run','python'] and Path(call['cwd'])!=root/folder and Path(call['cwd']).parts[-2:]==folder.parts,call
 assert lock()[1]['state']=='closed'
elif case=='ci-copy':
 poetry()
 base=prepare()
 passing_head()
 write('tests/test_ok.py','def test_working_tree_must_not_run(): assert False\n')
 p=run(binary,'ci','--base',base)
 line=f'shipcraft: suite . runs poetry -P {root} (Poetry keys its environment to the project folder, and this run is in another folder)'.encode()
 assert p.returncode==0 and suite_lines(p.stderr)==[line] and placements(p.stderr)==[line],p.stderr
 call,=calls()
 assert call['args'][:4]==['-P',str(root),'run','python'] and Path(call['cwd'])!=root,call
 assert Path('tests/test_ok.py').read_text()=='def test_working_tree_must_not_run(): assert False\n'
 headers=[x for x in log_path('ci').read_bytes().splitlines() if x.startswith(b'shipcraft: `')]
 assert len(headers)==1 and headers[0].startswith(f"shipcraft: `poetry -P '{root}' run python ".encode()),headers
elif case=='quoted-path':
 moved=root.with_name(root.name+" space 'café")
 root.rename(moved)
 root=moved.resolve()
 os.chdir(root)
 poetry()
 record_shell()
 # Leading and separating ASCII whitespace must survive the replacement.
 command="\tpoetry\trun\tpython"+flags
 base=prepare(command)
 passing_head()
 dirty_tree()
 p=run(binary,'ci','--base',base)
 line=f'shipcraft: suite . runs poetry -P {root} (Poetry keys its environment to the project folder, and this run is in another folder)'.encode()
 assert p.returncode==0 and suite_lines(p.stderr)==[line] and placements(p.stderr)==[line],p.stderr
 call,=calls()
 assert call['args'][:4]==['-P',str(root),'run','python'],call
 quoted="'"+str(root).replace("'","'\"'\"'")+"'"
 junit=next(arg.partition('=')[2] for arg in call['args'] if arg.startswith('--junitxml='))
 executed,=[invocation for invocation in shell_commands() if junit in invocation]
 expected=command.replace('poetry',f'poetry -P {quoted}',1).replace('{junit}',"'"+junit+"'")
 assert executed.encode()==expected.encode(),executed
elif case=='hook-log':
 poetry()
 prepare()
 failing()
 reds_open()
 stage_green()
 dirty_tree()
 clear_calls()
 p=green_commit()
 entries=[x for x in log_path('hook').read_bytes().splitlines() if x.startswith(b'shipcraft: `')]
 expected=f"shipcraft: `poetry -P '{root}' run python -m pytest -p no:cacheprovider --junitxml=".encode()
 assert len(entries)==1 and entries[0].startswith(expected) and b'{junit}' not in entries[0],entries
 assert p.returncode==0 and lock()[1]['state']=='closed',p.stderr
elif case=='ignored-project-venv':
 # Copy the ignored directory through Git's exporter. The stub still models only
 # its declared cached environment, so this alternate cwd produces no report.
 folder=Path('services/api')
 write(folder/'tests/test_ok.py','def test_ok(): assert True\n')
 venv()
 poetry(root/folder)
 base=prepare(suites=[('api',str(folder),'poetry run python'+flags)])
 passing_head()
 dirty_tree()
 p=run(binary,'ci','--base',base)
 call,=calls()
 assert call['args'][:2]==['run','python'] and Path(call['cwd'])!=root/folder and call['root_venv_link'],call
 assert p.returncode==1 and b'No module named pytest' in refusal(p.stderr)[0] and not suite_lines(p.stderr),p.stderr
elif case=='venv-file':
 write('.venv','not an environment\n')
 poetry()
 base=prepare()
 passing_head()
 dirty_tree()
 p=run(binary,'ci','--base',base)
 line=f'shipcraft: suite . runs poetry -P {root} (Poetry keys its environment to the project folder, and this run is in another folder)'.encode()
 assert p.returncode==0 and suite_lines(p.stderr)==[line],p.stderr
 call,=calls()
 assert call['args'][:4]==['-P',str(root),'run','python'] and call['root_venv_file'],call
elif case=='parent-project':
 folder=Path('services/api')
 write(folder/'tests/test_ok.py','def test_ok(): assert True\n')
 venv(folder/'.venv')
 with Path('.gitignore').open('a') as ignore:ignore.write('services/api/.venv/\n')
 poetry(root/folder)
 base=prepare(suites=[('api',str(folder),'poetry run python'+flags)])
 passing_head()
 dirty_tree()
 p=run(binary,'ci','--base',base)
 line=f'shipcraft: suite api runs poetry -P {root/folder} (Poetry keys its environment to the project folder, and this run is in another folder)'.encode()
 assert p.returncode==0 and placements(p.stderr)==[line],p.stderr
 call,=calls()
 assert call['args'][:4]==['-P',str(root/folder),'run','python'] and call['cwd_venv_dir'],call
elif case=='explicit-project':
 poetry()
 command='poetry --project . run python'+flags
 base=prepare(command)
 passing_head()
 dirty_tree()
 p=run(binary,'ci','--base',base)
 call,=calls()
 assert p.returncode==1 and call['args'][:4]==['--project','.','run','python'] and Path(call['cwd'])!=root,call
 assert not suite_lines(p.stderr) and b'No module named pytest' in refusal(p.stderr)[0],p.stderr
elif case=='run-pytest':
 poetry()
 command='poetry run pytest --junitxml={junit}'
 base=prepare(command)
 passing_head()
 dirty_tree()
 p=run(binary,'ci','--base',base)
 call,=calls()
 assert p.returncode==1 and call['args'][:2]==['run','pytest'] and Path(call['cwd'])!=root,call
 assert not suite_lines(p.stderr) and b'No module named pytest' in refusal(p.stderr)[0],p.stderr
elif case=='python3-copy':
 poetry()
 write(tools/'python3',f'#!/bin/sh\npwd -P > {shlex.quote(str(cw/"python3-cwd"))}\nprintf "python3-only152\\n" >&2\nexit 1\n',0o755)
 base=prepare('python3'+flags)
 passing_head()
 dirty_tree()
 p=run(binary,'ci','--base',base)
 assert p.returncode==1 and b'python3-only152' in refusal(p.stderr)[0] and not suite_lines(p.stderr) and not calls(),p.stderr
 assert Path((cw/'python3-cwd').read_text().strip())!=root
elif case=='borrowed-venv':
 poetry()
 venv()
 prepare('.venv/bin/python'+flags)
 linked()
 failing()
 p=run(binary,'red')
 line=f"shipcraft: suite . runs {root/'.venv/bin/python'} (this worktree has no .venv; the main worktree's)".encode()
 assert p.returncode==0 and placements(p.stderr)==[line,line] and not suite_lines(p.stderr) and not calls(),p.stderr
 assert lock()[1]['state']=='open'
elif case=='redo-linked':
 poetry()
 prepare()
 failing()
 reds_open()
 path=linked()
 before=lock()[0].read_bytes()
 write('tests/test_shout.py',Path('tests/test_shout.py').read_text().replace('== "HI!"','== "HI!", "redone152"'))
 clear_calls()
 p=run(binary,'red','--redo')
 line=f'shipcraft: suite . runs poetry -P {root} (Poetry keys its environment to the project folder, and this run is in another folder)'.encode()
 assert p.returncode==0 and placements(p.stderr)==[line,line] and suite_lines(p.stderr)==[line,line],p.stderr
 assert lock()[0].read_bytes()!=before and lock()[1]['state']=='open'
 assert len(calls())==2 and all(c['cwd']==str(path) and c['args'][:4]==['-P',str(root),'run','python'] for c in calls()),calls()
elif case=='missing-red':
 prepare()
 failing()
 p=run(binary,'red')
 out=refusal(p.stderr)
 assert p.returncode==1 and len(out)==3 and out[0].startswith(b'shipcraft refused: suite . did not write the JUnit report: '),p.stderr
 command='poetry run python'+flags
 diagnostic=run('sh','-c',command).stderr.split(b'\n',1)[0]
 expected=[
  b'shipcraft refused: suite . did not write the JUnit report: `'+command.encode()+b'` wrote to stderr: '+diagnostic+b'; poetry is not on PATH',
  b"Why: the suite's command runs through poetry",
  b'Next: install poetry or edit test_command in .shipcraft.toml; then try again',
 ]
 assert out==expected,out
 assert rows()[-1]['code']=='no-report' and rows()[-1]['result']=='refused'
 assert not list(Path('.shipcraft/locks').glob('*.json')) and b'create the stub' not in p.stdout+p.stderr
 # Measurement happens later and a blocked append may not replace the refusal.
 log=root/'.git/shipcraft/runs.jsonl'
 log.unlink()
 log.mkdir()
 again=run(binary,'red')
 assert again.returncode==1 and log.is_dir() and refusal(again.stderr)==expected
elif case=='missing-hook':
 poetry()
 prepare()
 failing()
 reds_open()
 stage_green()
 dirty_tree()
 before=git('rev-parse','HEAD')
 lock_before=lock()[0].read_bytes()
 remove(tools/'poetry')
 p=green_commit()
 out=refusal(p.stderr)
 assert p.returncode==1 and len(out)==3 and out[0].startswith(b'shipcraft refused: suite . did not write the JUnit report: '),p.stderr
 assert out[0].endswith(b'; poetry is not on PATH') and out[1:]==[b"Why: the suite's command runs through poetry",b'Next: install poetry or edit test_command in .shipcraft.toml; then try again'],out
 assert rows()[-1]['code']=='no-report' and rows()[-1]['result']=='refused'
 assert git('rev-parse','HEAD')==before and lock()[0].read_bytes()==lock_before
 log=log_path('hook').read_bytes()
 assert f"shipcraft: `poetry -P '{root}' run python ".encode() in log,log
elif case=='missing-ci':
 base=prepare()
 passing_head()
 p=run(binary,'ci','--base',base)
 out=refusal(p.stderr)
 assert p.returncode==1 and len(out)==3 and out[0].startswith(b'shipcraft refused: suite . did not write the JUnit report: '),p.stderr
 assert out[0].endswith(b'; poetry is not on PATH') and out[1:]==[b"Why: the suite's command runs through poetry",b'Next: install poetry or edit test_command in .shipcraft.toml; then try again'],out
 assert rows()[-1]['code']=='no-report' and rows()[-1]['result']=='refused' and not suite_lines(p.stderr)
elif case=='missing-named':
 folder=Path('packages/b')
 write(folder/'tests/test_ok.py','def test_ok(): assert True\n')
 # First-word reading does not depend on the run/python words, even after a tab.
 prepare(suites=[('beta',str(folder),'\tpoetry\trun pytest --junitxml={junit}')])
 failing(folder)
 p=run(binary,'red')
 out=refusal(p.stderr)
 assert p.returncode==1 and len(out)==3 and out[0].startswith(b'shipcraft refused: suite beta did not write the JUnit report: '),p.stderr
 assert out[0].endswith(b'; poetry is not on PATH') and out[1:]==[b"Why: the suite's command runs through poetry",b'Next: install poetry or edit command of [[suite]] beta in .shipcraft.toml; then try again'],out
 assert rows()[-1]['code']=='no-report' and rows()[-1]['result']=='refused' and not suite_lines(p.stderr)
elif case=='poetry-no-report':
 poetry(cw)
 prepare()
 failing()
 p=run(binary,'red')
 out=refusal(p.stderr)
 assert p.returncode==1 and len(out)==3 and out[0].startswith(b'shipcraft refused: suite . did not write the JUnit report: '),p.stderr
 assert out[0].endswith(b' wrote to stderr: No module named pytest'),out
 assert b'create the stub' in out[2] and not suite_lines(p.stderr),p.stderr
 assert rows()[-1]['code']=='no-report' and rows()[-1]['result']=='refused'
 assert calls() and all(c['cwd']==str(root) and c['args'][:2]==['run','python'] for c in calls()),calls()
elif case=='missing-linked':
 prepare()
 linked()
 failing()
 p=run(binary,'red')
 out=refusal(p.stderr)
 assert p.returncode==1 and len(out)==3 and out[0].startswith(b'shipcraft refused: suite . did not write the JUnit report: '),p.stderr
 assert out[0].endswith(b'; poetry is not on PATH') and out[1:]==[b"Why: the suite's command runs through poetry",b'Next: install poetry or edit test_command in .shipcraft.toml; then try again'],out
 line=f'shipcraft: suite . runs poetry -P {root} (Poetry keys its environment to the project folder, and this run is in another folder)'.encode()
 assert suite_lines(p.stderr) and all(x==line for x in placements(p.stderr)) and suite_lines(p.stderr)==placements(p.stderr),p.stderr
 assert rows()[-1]['code']=='no-report' and rows()[-1]['result']=='refused'
elif case=='missing-redo':
 poetry()
 prepare()
 failing()
 reds_open()
 before=lock()[0].read_bytes()
 write('tests/test_shout.py',Path('tests/test_shout.py').read_text().replace('== "HI!"','== "HI!", "redone152"'))
 remove(tools/'poetry')
 p=run(binary,'red','--redo')
 out=refusal(p.stderr)
 assert p.returncode==1 and len(out)==3 and out[0].startswith(b'shipcraft refused: suite . did not write the JUnit report: '),p.stderr
 assert out[0].endswith(b'; poetry is not on PATH') and out[1:]==[b"Why: the suite's command runs through poetry",b'Next: install poetry or edit test_command in .shipcraft.toml; then try again'],out
 assert rows()[-1]['code']=='no-report' and rows()[-1]['result']=='refused' and lock()[0].read_bytes()==before
elif case=='narrowed-fallback':
 poetry()
 # Use a runner file so the default pytest filter can append its arguments.
 write('runner152.py',
       'import os, subprocess, sys\n'
       'from pathlib import Path\n'
       'junit, *filters = sys.argv[1:]\n'
       'result = subprocess.run([sys.executable, "-m", "pytest", "-p", "no:cacheprovider",\n'
       '                         "--junitxml=" + junit, *filters])\n'
       'if os.environ.get("SHIPCRAFT_FILES") and not os.environ.get("SHIPCRAFT_CASES"):\n'
       '    Path(junit).unlink(missing_ok=True)\n'
       'sys.exit(result.returncode)\n')
 command='poetry run python runner152.py {junit}'
 check="poetry run python -c 'print(\"check152\")' || :"
 build="poetry run python -c 'print(\"build152\")' || :"
 base=prepare(command,check=check,build=build)
 git('update-ref','refs/remotes/origin/main',base)
 git('symbolic-ref','refs/remotes/origin/HEAD','refs/remotes/origin/main')
 path=linked()
 failing()
 clear_calls()
 p=run(binary,'red')
 line=f'shipcraft: suite . runs poetry -P {root} (Poetry keys its environment to the project folder, and this run is in another folder)'.encode()
 assert p.returncode==0 and len(suite_lines(p.stderr))==3 and placements(p.stderr)==[line]*3,p.stderr
 assert b'red ran every suite: no report' in p.stdout and lock()[1]['state']=='open',p.stdout
 trace=calls()
 assert trace[0]['args']==['run','python','-c','print("build152")'],trace
 checks=[i for i,c in enumerate(trace) if 'print("check152")' in c['args']]
 assert checks and all(trace[i]['args']==['run','python','-c','print("check152")'] for i in checks),trace
 runs=[i for i,c in enumerate(trace) if 'runner152.py' in c['args']]
 assert len(runs)==3 and all(trace[i]['args'][:4]==['-P',str(root),'run','python'] for i in runs),trace
 assert checks[0]<runs[0] and all(c['cwd']==str(path) for c in trace),trace
elif case=='guide-poetry':
 heading=b'Python with Poetry (instead of the blocks above, for a project with poetry.lock):\n'
 part=guide()
 assert part.count(heading)==1,'missing exact Poetry heading'
 uv_end=part.index(b'`uv sync --frozen` installs')
 start=part.index(heading)
 end=part.index(b'\nNode:\n',start)
 assert uv_end<start<end
 block=part[start:end]
 raw=block.split(b'```yaml\n',1)[1].split(b'```\n',1)[0]
 assert b'python-version: "3.x"' in [line.lstrip() for line in raw.split(b'\n')],raw
 condition="steps.layer.outputs.run == 'true'"
 setup,install=guide_steps(block)
 assert setup=={'uses':'actions/setup-python@v5','if':condition,'with':{'python-version':'3.x'}},setup
 assert install=={'name':'Install dependencies','if':condition,'run':'pipx install poetry\npoetry env use python3\npoetry install\n'},install
 notes=b' '.join(block.split(b'```\n',1)[1].split())
 assert all(fragment in notes for fragment in (b'`poetry install`',b'`poetry run`',b'`--with <name>`',b'`requires-python`',b'`poetry env use python3`')),notes
elif case=='guide-kept':
 part=guide()
 python=guide_steps(part.split(b'\nPython:\n',1)[1])
 uv=guide_steps(part.split(b'\nPython with uv (',1)[1])
 condition="steps.layer.outputs.run == 'true'"
 assert python==[
  {'uses':'actions/setup-python@v5','if':condition,'with':{'python-version':'3.x'}},
  {'name':'Install dependencies','if':condition,'run':'''python3 -m venv .venv
.venv/bin/python -m pip install pytest
for f in requirements*.txt; do
  if [ -f "$f" ]; then .venv/bin/python -m pip install -r "$f"; fi
done
echo "$PWD/.venv/bin" >> "$GITHUB_PATH"
'''}],python
 assert uv==[
  {'uses':'astral-sh/setup-uv@v6','if':condition},
  {'name':'Install dependencies','if':condition,'run':'uv sync --frozen\necho "$PWD/.venv/bin" >> "$GITHUB_PATH"\n'}],uv
else:
 raise AssertionError('unrouted '+case)
PY152
  pass
}
