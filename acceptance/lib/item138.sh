# Item 138: pytest settings, public hook and CI contract.
item138_langs() { echo python; }
item138_cases() {
  local c
  for c in repro-a repro-b repro-c repro-d-setup repro-d-tox removed dot-ini toml dot-toml toml-native toml-invalid toml-scalar toml-nan control-toml-values control-project ini-crlf ini-continuation ini-duplicate ini-separators control-ini-sections nested ancestor control-sibling control-no-pytest ci byte-order symlink control-red control-no-lock index log-failure closed control-fake control-real invalid-utf8 empty-section control-merge toml-reader control-index symlink-existing; do echo "v1-138.$c"; done
}
item138_case() {
  EXPECT='pytest settings are protected while a lock is open'
  v1_start codex claude
  setup_init
  must_accept 'item 138 contract' cmd "$PY" - "${CASE#v1-138.}" <<'PY138'
import json, subprocess, sys
from pathlib import Path
case=sys.argv[1]
def write(path,text):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
def run(*args):
 p=subprocess.run(args,capture_output=True,text=True,timeout=90)
 print('$',' '.join(args),'[rc=%s]'%p.returncode,'\n'+p.stdout+p.stderr,flush=True)
 return p
def ok(*args):
 p=run(*args);assert p.returncode==0,(args,p.stdout,p.stderr);return p
def commit(message):
 ok('git','add','-A');return ok('git','commit','-qm',message)

def seed(before=None,real=False,root='.',command=None,redsettings=None):
 Path('tests/test_smoke.py').unlink(missing_ok=True)
 for name,value in (before or {}).items(): put(name,value)
 if not real:
  write(root+'/pytest138.py','''import sys
from pathlib import Path
import xml.etree.ElementTree as E
passed='return a+b' in Path('calc.py').read_text()
suite=E.Element('testsuite',tests='2',failures='0' if passed else '1')
for name in ('test_adds','test_control138'):
 c=E.SubElement(suite,'testcase',classname='tests.test_calc',name=name)
 if name=='test_adds' and not passed:E.SubElement(c,'failure',message='stub138')
E.ElementTree(suite).write(sys.argv[1])
with Path('.trace138').open('a') as f:f.write('fake138:'+str(passed)+'\\n')
raise SystemExit(0 if passed else 1)
''')
  cmd=command or 'python3 pytest138.py {junit}'
  config='shipcraft_min="0.0"\nlang="python"\nrunner="pytest"\n'
  if root=='.':config+='test_command='+json.dumps(cmd)+'\ntest_globs=["tests/**"]\n'
  config+='[execution]\nci="local"\nreview="off"\n'
  if root!='.':config+='[[suite]]\nname="api138"\nroot='+json.dumps(root)+'\ncommand='+json.dumps(cmd)+'\nglobs=["tests/**"]\n'
  write('.shipcraft.toml',config)
 with Path('.gitignore').open('a') as f:f.write('\n.trace138\n')
 commit('chore: baseline138')
 for name,value in (redsettings or {}).items():put(name,value)
 write(root+'/calc.py','def add(a,b):\n    raise NotImplementedError\n')
 write(root+'/tests/test_calc.py','from calc import add\ndef test_adds(): assert add(1,2)==3\ndef test_control138(): assert add.__name__=="add"\n')
 ok('shipcraft','red');commit('test: RED138')
 return next(Path('.shipcraft/locks').glob('*.json'))
def put(path,value):
 p=Path(path)
 if value is None:
  if p.exists() or p.is_symlink():p.unlink()
 elif isinstance(value,bytes):p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value)
 else:write(path,value)
def judge(changes,root='.',real=False,ci=False,close=False,logfail=False):
 base=ok('git','rev-parse','HEAD').stdout.strip()
 if not real:write(root+'/calc.py','def add(a,b):\n    return a+b\n')
 if close:
  ok('git','add','-A');ok('shipcraft','check')
 for name,value in changes.items():put(name,value)
 ok('git','add','-A')
 if logfail:
  Path('.git/shipcraft/runs.jsonl').unlink();Path('.git/shipcraft/runs.jsonl').mkdir()
 if ci:
  tree=ok('git','write-tree').stdout.strip()
  head=ok('git','commit-tree',tree,'-p',base,'-m','fixture138 CI snapshot').stdout.strip()
  ok('git','update-ref','HEAD',head)
  p=run('shipcraft','ci','--base',base)
 else:p=run('git','commit','-qm','feat: GREEN138')
 log=Path('.git/shipcraft/runs.jsonl')
 rows=[json.loads(l) for l in log.read_text().splitlines()] if log.is_file() else []
 return p,rows
if case=='repro-a':
 ok('.venv/bin/python','-m','pytest','--version')
 write('calc.py','def add(a,b):\n    raise NotImplementedError\n')
 write('tests/test_calc.py','from calc import add\ndef test_adds(): assert add(1,2)==3\ndef test_control138(): assert add.__name__=="add"\n')
 ok('shipcraft','red');commit('test: RED138')
 write('pytest.ini','[pytest]\naddopts = -p shortcut\n')
 write('shortcut.py','import pytest\n@pytest.hookimpl(wrapper=True)\ndef pytest_runtest_makereport(item, call):\n    report = yield\n    if report.failed: report.outcome = "passed"\n    return report\n')
 ok('git','add','pytest.ini','shortcut.py')
 p=run('git','commit','-qm','feat: GREEN138 shortcut')
 assert p.returncode!=0,'2.78.0 accepted the pytest plugin shortcut; expected refusal'
 rows=[json.loads(l) for l in Path('.git/shipcraft/runs.jsonl').read_text().splitlines()]
 assert rows[-1]['code']=='pytest-config-changed',rows[-1]
elif case=='repro-b':
 lf=seed({'pytest.ini': '[pytest]\ntestpaths = tests\n'},real=True)
 p,rows=judge({'pytest.ini': '[pytest]\ntestpaths = tests\naddopts = -p shortcut\n', 'shortcut.py': "import pytest\n@pytest.hookimpl(wrapper=True)\ndef pytest_runtest_makereport(item, call):\n    report = yield\n    if report.failed: report.outcome = 'passed'\n    return report\n"},real=True)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in pytest.ini changed "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in pytest.ini; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='repro-c':
 lf=seed({'pyproject.toml': '[project]\nname="calc138"\nversion="0.0.0"\n[tool.pytest.ini_options]\n'},real=True)
 p,rows=judge({'pyproject.toml': '[project]\nname="calc138"\nversion="0.0.0"\n[tool.pytest.ini_options]\npythonpath=["shadow"]\n', 'shadow/calc.py': 'def add(a,b): return a+b\n'},real=True)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in pyproject.toml changed "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in pyproject.toml; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='repro-d-setup':
 lf=seed({'setup.cfg': '[metadata]\nname=calc138\n'},real=True)
 p,rows=judge({'setup.cfg': '[metadata]\nname=calc138\n[tool:pytest]\naddopts = -p shortcut\n', 'shortcut.py': "import pytest\n@pytest.hookimpl(wrapper=True)\ndef pytest_runtest_makereport(item, call):\n    report = yield\n    if report.failed: report.outcome = 'passed'\n    return report\n"},real=True)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in setup.cfg were added "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in setup.cfg; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='repro-d-tox':
 lf=seed({'tox.ini': '[tox]\nenvlist=py\n'},real=True)
 p,rows=judge({'tox.ini': '[tox]\nenvlist=py\n[pytest]\naddopts = -p shortcut\n', 'shortcut.py': "import pytest\n@pytest.hookimpl(wrapper=True)\ndef pytest_runtest_makereport(item, call):\n    report = yield\n    if report.failed: report.outcome = 'passed'\n    return report\n"},real=True)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in tox.ini were added "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in tox.ini; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='removed':
 lf=seed({'pytest.ini': '[pytest]\n'},real=False)
 p,rows=judge({'pytest.ini': None},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in pytest.ini were removed "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in pytest.ini; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='dot-ini':
 lf=seed({},real=False)
 p,rows=judge({'.pytest.ini': ''},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in .pytest.ini were added "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in .pytest.ini; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='toml':
 lf=seed({},real=False)
 p,rows=judge({'pytest.toml': ''},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in pytest.toml were added "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in pytest.toml; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='dot-toml':
 lf=seed({},real=False)
 p,rows=judge({'.pytest.toml': ''},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in .pytest.toml were added "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in .pytest.toml; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='toml-native':
 lf=seed({'pyproject.toml': '[project]\nname="a"\n'},real=False)
 p,rows=judge({'pyproject.toml': '[project]\nname="a"\n[tool.pytest]\naddopts=["-p", "shortcut"]\n'},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in pyproject.toml were added "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in pyproject.toml; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='toml-invalid':
 lf=seed({'pyproject.toml': '[tool.pytest.ini_options]\naddopts=""\n'},real=False)
 p,rows=judge({'pyproject.toml': '[tool.pytest.ini_options\naddopts=""\n'},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in pyproject.toml changed "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in pyproject.toml; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='toml-scalar':
 lf=seed({'pyproject.toml': '[tool]\npytest="old"\n'},real=False)
 p,rows=judge({'pyproject.toml': '[tool]\npytest="new"\n'},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in pyproject.toml changed "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in pyproject.toml; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='toml-nan':
 lf=seed({'pyproject.toml': '[tool.pytest]\nvalue=nan\n'},real=False)
 p,rows=judge({'product.txt': 'unrelated\n'},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in pyproject.toml changed "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in pyproject.toml; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='control-toml-values':
 lf=seed({"pyproject.toml":'[tool.pytest.ini_options]\naddopts=""\ntestpaths=["tests"]\n'})
 p,rows=judge({"pyproject.toml":"# comment\n[tool.pytest.ini_options]\ntestpaths = ['tests'] # same\naddopts = ''\n"})
 assert p.returncode==0 and json.loads(lf.read_text())["state"]=="closed"
 assert Path(".trace138").read_text().splitlines()[-1]=="fake138:True"
 assert Path("pyproject.toml").read_text()=="# comment\n[tool.pytest.ini_options]\ntestpaths = ['tests'] # same\naddopts = ''\n"
elif case=='control-project':
 lf=seed({"pyproject.toml":'[project]\nversion="1"\n[tool.pytest]\naddopts=[]\n'})
 p,rows=judge({"pyproject.toml":'[project]\nversion="2"\n[tool.pytest]\naddopts=[]\n'})
 assert p.returncode==0 and json.loads(lf.read_text())["state"]=="closed"
 assert Path(".trace138").read_text().splitlines()[-1]=="fake138:True"
 assert Path("pyproject.toml").read_text()=='[project]\nversion="2"\n[tool.pytest]\naddopts=[]\n'
elif case=='ini-crlf':
 lf=seed({'setup.cfg': '[metadata]\r\nname=a\r\n'},real=False)
 p,rows=judge({'setup.cfg': '[metadata]\r\nname=a\r\n[tool:pytest] ; comment\r\naddopts= -p shortcut\r\n'},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in setup.cfg were added "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in setup.cfg; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='ini-continuation':
 lf=seed({'setup.cfg': '[tool:pytest]\nx=one\n  [other]\n  old\n[unused\nold\n'},real=False)
 p,rows=judge({'setup.cfg': '[tool:pytest]\nx=one\n  [other]\n  new\n[unused\nnew\n'},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in setup.cfg changed "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in setup.cfg; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='ini-duplicate':
 lf=seed({'tox.ini': '[pytest]\nx=1\n[other]\ny=2\n[pytest]\nz=3\n'},real=False)
 p,rows=judge({'tox.ini': '[pytest]\nx=1\n[other]\ny=2\n[pytest]\nz=4\n'},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in tox.ini changed "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in tox.ini; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='ini-separators':
 lf=seed({'setup.cfg':'[metadata]\nname=a\n'})
 base=ok('git','rev-parse','HEAD').stdout.strip();bad=[]
 for sep in ('\n','\r\n','\r','\v','\f','\x1c','\x1d','\x1e','\x85','\u2028','\u2029'):
  p,rows=judge({'setup.cfg':'[metadata]'+sep+'name=a'+sep+'[tool:pytest] # comment'+sep+'x=1'+sep})
  if p.returncode!=1 or rows[-1]['code']!='pytest-config-changed':bad.append(repr(sep))
  ok('git','reset','--hard',base)
 assert not bad,('splitlines variants not protected',bad)
elif case=='control-ini-sections':
 lf=seed({'setup.cfg':'[metadata]\nname=a\n[tool:pytest]\nx=1\n[other]\ny=2\n','tox.ini':'[tox]\nenvlist=py\n[pytest]\nx=1\n'})
 p,rows=judge({'setup.cfg':'[metadata]\nname=b\n[tool:pytest]\nx=1\n[other]\ny=3\n[pytest]\nx=unrelated\n  [tool:pytest]\n','tox.ini':'[tox]\nenvlist=py3\n[pytest]\nx=1\n'})
 assert p.returncode==0 and json.loads(lf.read_text())['state']=='closed'
 assert Path('.trace138').read_text().splitlines()[-1]=='fake138:True'
elif case=='nested':
 lf=seed({},real=False)
 p,rows=judge({'examples/legacy/pytest.ini': '[pytest]\n'},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in examples/legacy/pytest.ini were added "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in examples/legacy/pytest.ini; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='ancestor':
 lf=seed(root='./svc//')
 p,rows=judge({'pytest.ini':'[pytest]\n'},root='svc')
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1])
 assert "pytest's settings in pytest.ini were added" in p.stdout+p.stderr
elif case=='control-sibling':
 lf=seed(root='svc')
 p,rows=judge({'sibling/pytest.ini':'[pytest]\n'},root='svc')
 assert p.returncode==0 and json.loads(lf.read_text())['state']=='closed'
 assert Path('svc/.trace138').read_text().splitlines()[-1]=='fake138:True'
elif case=='control-no-pytest':
 lf=seed(command='python3 runner138.py {junit}',before={'runner138.py':"import runpy\nrunpy.run_path('pytest138.py',run_name='__main__')\n"})
 p,rows=judge({'pytest.ini':'[pytest]\n'})
 assert p.returncode==0 and json.loads(lf.read_text())['state']=='closed'
 assert Path('.trace138').read_text().splitlines()[-1]=='fake138:True'
elif case=='ci':
 lf=seed({},real=False)
 p,rows=judge({'pytest.ini': '[pytest]\n'},real=False,ci=True)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in pytest.ini were added "+('in commit '+ok('git','rev-parse','--short','HEAD').stdout.strip())+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='ci'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in pytest.ini; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='byte-order':
 lf=seed({},real=False)
 p,rows=judge({'pytest.ini': '[pytest]\n', '.pytest.toml': '[pytest]\n', 'setup.cfg': '[tool:pytest]\n'},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in .pytest.toml were added "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in .pytest.toml; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='symlink':
 lf=seed({'pytest.ini': '[pytest]\n'},real=False)
 Path('pytest.ini').unlink();write('settings138','[pytest]\n');Path('pytest.ini').symlink_to('settings138')
 p,rows=judge({},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in pytest.ini are behind a symbolic link "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in pytest.ini; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='control-red':
 # RED may introduce settings; this lock has the unchanged current public fields.
 lf=seed(real=True,redsettings={'pytest.ini':'[pytest]\n'})
 d=json.loads(lf.read_text())
 assert d['state']=='open' and set(d['files'])=={'.shipcraft.toml','tests/test_calc.py'}
 assert any('test_adds' in x for x in d['failing_at_red'])
 assert 'pytest.ini' not in d['files']
elif case=='control-no-lock':
 write('pytest.ini','[pytest]\naddopts=-p absent138\n')
 commit('chore: settings without lock138')
 rows=[json.loads(l) for l in Path('.git/shipcraft/runs.jsonl').read_text().splitlines()]
 assert rows[-1]['result']=='passed' and not list(Path('.shipcraft/locks').glob('*.json'))
 assert ok('git','show','HEAD:pytest.ini').stdout=='[pytest]\naddopts=-p absent138\n'
elif case=='index':
 lf=seed()
 write('pytest.ini','[pytest]\naddopts=-p staged138\n');ok('git','add','pytest.ini')
 write('pytest.ini','[pytest]\n')
 p=run('shipcraft','check')
 rows=[json.loads(l) for l in Path('.git/shipcraft/runs.jsonl').read_text().splitlines()]
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1])
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='log-failure':
 lf=seed()
 p,rows=judge({'pytest.ini':'[pytest]\n'},logfail=True)
 assert p.returncode==1 and "pytest's settings in pytest.ini were added" in p.stdout+p.stderr,(p.returncode,p.stdout,p.stderr)
 assert Path('.git/shipcraft/runs.jsonl').is_dir() and json.loads(lf.read_text())['state']=='open'
 assert 'Next: undo the change to' in p.stdout+p.stderr
elif case=='closed':
 lf=seed({},real=False)
 p,rows=judge({'pytest.ini': '[pytest]\n'},real=False,close=True)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in pytest.ini were added "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in pytest.ini; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='control-fake':
 lf=seed()
 base=ok('git','rev-parse','HEAD').stdout.strip()
 d=json.loads(lf.read_text());assert any('test_adds' in x for x in d['failing_at_red'])
 assert Path('.trace138').read_text().splitlines()[-1]=='fake138:False'
 p,rows=judge({'product138.txt':'ordinary'},ci=True)
 assert p.returncode==1 and rows[-1]['code']=='lock-not-closed' and rows[-1]['layer']=='ci'
 ok('git','reset','--hard',base)
 p,rows=judge({'product138.txt':'ordinary'})
 assert p.returncode==0 and json.loads(lf.read_text())['state']=='closed'
 assert Path('.trace138').read_text().splitlines()[-1]=='fake138:True'
elif case=='control-real':
 lf=seed(real=True)
 p,rows=judge({'calc.py':'def add(a,b): return a+b\n'},real=True)
 assert p.returncode==0 and json.loads(lf.read_text())['state']=='closed'
 assert '2 passed' in p.stdout+p.stderr
elif case=='invalid-utf8':
 lf=seed({'setup.cfg': b'[tool:pytest]\nx=\xff\n'},real=False)
 p,rows=judge({'setup.cfg': b'[tool:pytest]\nx=\xfe\n'},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in setup.cfg changed "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in setup.cfg; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='empty-section':
 lf=seed({'tox.ini': '[tox]\nx=1\n'},real=False)
 p,rows=judge({'tox.ini': '[tox]\nx=1\n[pytest]\n'},real=False)
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1] if rows else None)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert len(lines)==3 and lines[0]=="shipcraft refused: pytest's settings in tox.ini were added "+('in the pending commit')+" with lock "+str(lf)+" open",lines
 assert rows[-1]['layer']=='hook'
 assert lines[1]=="Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game",lines
 assert lines[2]=="Next: undo the change to pytest's settings in tox.ini; if the suite needs it, make it after the cycle closes",lines
 assert 'running the suite' not in p.stdout+p.stderr
elif case=='control-merge':
 lf=seed()
 branch=ok('git','branch','--show-current').stdout.strip()
 ok('git','checkout','-qb','upstream138','HEAD^')
 write('pytest.ini','[pytest]\nx=parent138\n');commit('chore: upstream settings138')
 ok('git','checkout',branch)
 ok('git','merge','--no-commit','--no-ff','upstream138')
 write('calc.py','def add(a,b): return a+b\n');commit('feat: merged GREEN138')
 assert json.loads(lf.read_text())['state']=='closed'
 assert ok('git','show','HEAD:pytest.ini').stdout=='[pytest]\nx=parent138\n'
 assert len(ok('git','show','-s','--format=%P','HEAD^').stdout.split())==2
elif case=='toml-reader':
 lf=seed({'pyproject.toml':'[project]\nname="a"\n'})
 base=ok('git','rev-parse','HEAD').stdout.strip();bad=[]
 for value in (b'\xef\xbb\xbf[tool.pytest]\nx=1\n',b'[tool.pytest]\nx="\xff"\n',b'[tool.pytest]\nx=null\n',b'[tool]\npytest={x=1}\n',b'tool.pytest.x=1\r\n',b'["tool"."pytest"]\nx=[1,2] # comment\n'):
  p,rows=judge({'pyproject.toml':value})
  if p.returncode!=1 or rows[-1]['code']!='pytest-config-changed':bad.append(repr(value))
  ok('git','reset','--hard',base)
 assert not bad,('TOML variants not protected',bad)
elif case=='control-index':
 lf=seed({'pytest.ini':'[pytest]\n'})
 write('calc.py','def add(a,b): return a+b\n');ok('git','add','calc.py')
 write('pytest.ini','[pytest]\naddopts=-p unstaged138\n')
 p=run('git','commit','-qm','feat: indexed product138')
 assert p.returncode==0 and json.loads(lf.read_text())['state']=='closed'
 assert ok('git','show','HEAD:pytest.ini').stdout=='[pytest]\n'
 assert 'unstaged138' in Path('pytest.ini').read_text()
elif case=='symlink-existing':
 write('settings138','[pytest]\n');Path('pytest.ini').symlink_to('settings138')
 lf=seed()
 p,rows=judge({'settings138':'[pytest]\nx=changed\n'})
 assert p.returncode==1 and rows[-1]['code']=='pytest-config-changed',(p.returncode,rows[-1])
 assert "pytest's settings in pytest.ini are behind a symbolic link" in p.stdout+p.stderr
else:raise AssertionError('unrouted '+case)
PY138
  pass
}
