# Item 156: project pytest plugin code, judged through public Git hooks and CI.
item156_langs() { echo python; }
item156_cases() {
  local c
  for c in repro conftest-plugin pythonpath command added-conftest conftest-edit symlink compact toml-array native pytest-toml ini-continuation tox quoted plugins-comma plugins-tuple plugins-group plugins-cr package-root override linked-base transitive package-init shadow-package shadow-base ci byte-order closed index removed log-failure close control-fake control-real control-names control-root control-no-pytest control-red control-merge control-precedence; do echo "v1-156.$c"; done
}
item156_case() {
  EXPECT='pytest plugin code is protected while a lock is open'
  v1_start codex claude
  setup_init
  must_accept 'item 156 contract' cmd "$PY" - "${CASE#v1-156.}" <<'PY156'
import json, os, subprocess, sys
from pathlib import Path
case=sys.argv[1]
def write(path,text):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True)
 if isinstance(text,bytes):p.write_bytes(text)
 else:p.write_text(text)
def put(path,value):
 p=Path(path)
 if value is None:p.unlink(missing_ok=True)
 else:write(path,value)
def run(*args):
 p=subprocess.run(args,capture_output=True,text=True,timeout=90)
 print('$',' '.join(map(str,args)),'[rc=%s]'%p.returncode,'\n'+p.stdout+p.stderr,flush=True)
 return p
def ok(*args):
 p=run(*args);assert p.returncode==0,(args,p.stdout,p.stderr);return p
def git(*args):return ok('git',*args).stdout.strip()
def commit(message):
 git('add','-A');return ok('git','commit','-qm',message)
def rows():return [json.loads(l) for l in Path('.git/shipcraft/runs.jsonl').read_text().splitlines()]
def seed(before=None,real=False,root='.',command=None,redsettings=None,globs=None,probe='myplugin.py'):
 Path('tests/test_smoke.py').unlink(missing_ok=True)
 for name,value in (before or {}).items():put(name,value)
 if not real:
  write(root+'/pytest156.py', '''import sys
from pathlib import Path
import xml.etree.ElementTree as E
p=Path('''+repr(probe)+''')
passed=(p.is_file() and b'PASS156' in p.read_bytes()) or 'return a+b' in Path('calc.py').read_text()
suite=E.Element('testsuite',tests='2',failures='0' if passed else '1')
for name in ('test_adds','test_control156'):
 c=E.SubElement(suite,'testcase',classname='tests.test_calc',name=name)
 if name=='test_adds' and not passed:E.SubElement(c,'failure',message='stub156')
E.ElementTree(suite).write(sys.argv[1])
with Path('.trace156').open('a') as f:f.write('fake156:'+str(passed)+'\\n')
raise SystemExit(0 if passed else 1)
''')
  cmd=command or 'python3 pytest156.py {junit}'
 else:cmd='.venv/bin/python -m pytest -p no:cacheprovider --junitxml={junit}'
 config='shipcraft_min="0.0"\nlang="python"\nrunner="pytest"\n'
 if root=='.':config+='test_command='+json.dumps(cmd)+'\ntest_globs='+json.dumps(globs or ['tests/**'])+'\n'
 config+='[execution]\nci="local"\nreview="off"\n'
 if root!='.':config+='[[suite]]\nname="api156"\nroot='+json.dumps(root)+'\ncommand='+json.dumps(cmd)+'\nglobs='+json.dumps(globs or ['tests/**'])+'\n'
 write('.shipcraft.toml',config)
 with Path('.gitignore').open('a') as f:f.write('\n.trace156\n**/__pycache__/\n')
 commit('baseline156')
 for name,value in (redsettings or {}).items():put(name,value)
 write(root+'/calc.py','def add(a,b):\n    raise NotImplementedError\n')
 write(root+'/tests/test_calc.py','from calc import add\ndef test_adds(): assert add(1,2)==3\ndef test_control156(): assert add.__name__=="add"\n')
 if real:ok('.venv/bin/python','-m','pytest','--version')
 ok('shipcraft','red');commit('RED156')
 return next(Path('.shipcraft/locks').glob('*.json'))
def judge(changes,ci=False,logfail=False):
 base=git('rev-parse','HEAD')
 for name,value in changes.items():put(name,value)
 git('add','-A')
 if logfail:
  Path('.git/shipcraft/runs.jsonl').unlink();Path('.git/shipcraft/runs.jsonl').mkdir()
 if ci:
  ok('git','commit','--no-verify','-qm','bypass156')
  p=run('shipcraft','ci','--base',base)
 else:p=run('git','commit','-qm','GREEN156')
 return p
if case=='repro':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n'},real=True)
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'myplugin.py': 'import pytest\n@pytest.hookimpl(wrapper=True)\ndef pytest_runtest_makereport(item, call):\n    report = yield\n    if report.failed: report.outcome = "passed"\n    return report\n'})
 print('REPRODUCTION A: plugin-only GREEN; calc.py still raises; lock state='+json.loads(lock.read_text())['state'],flush=True)
 assert 'raise NotImplementedError' in Path('calc.py').read_text()
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='conftest-plugin':
 lock=seed({'conftest.py': 'pytest_plugins = ["helpers.plug"]\n', 'helpers/plug.py': '# no-op\n'},real=True)
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'helpers/plug.py': 'import pytest\n@pytest.hookimpl(wrapper=True)\ndef pytest_runtest_makereport(item, call):\n    report = yield\n    if report.failed: report.outcome = "passed"\n    return report\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in helpers/plug.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in helpers/plug.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='pythonpath':
 lock=seed({'pyproject.toml': '[tool.pytest.ini_options]\npythonpath=["./unused/../plugins//"]\naddopts="-p myplug"\n', 'plugins/myplug.py': '# no-op\n'},probe='plugins/myplug.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'plugins/myplug.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in plugins/myplug.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in plugins/myplug.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='command':
 lock=seed({'svc/cmdplug.py': '# no-op\n'},probe='cmdplug.py',root='svc',command='python3 pytest156.py {junit} -p cmdplug')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'svc/cmdplug.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in svc/cmdplug.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in svc/cmdplug.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='added-conftest':
 lock=seed({},real=True,globs=['tests/**', '**/conftest.py'])
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'conftest.py': 'import pytest\n@pytest.hookimpl(wrapper=True)\ndef pytest_runtest_makereport(item, call):\n    report = yield\n    if report.failed: report.outcome = "passed"\n    return report\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in conftest.py were added "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in conftest.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='conftest-edit':
 lock=seed({'conftest.py': '# no-op\n'},probe='conftest.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'conftest.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in conftest.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in conftest.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='symlink':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n'})
 Path('myplugin.py').unlink();Path('myplugin.py').symlink_to('target156')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'target156': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py are behind a symbolic link "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='compact':
 lock=seed({'pytest.ini': '[pytest]\naddopts=-pmyplugin\n', 'myplugin.py': '# no-op\n'},probe='myplugin.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'myplugin.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='toml-array':
 lock=seed({'pyproject.toml': '[tool.pytest.ini_options]\naddopts=["-p",7,"myplugin"]\n', 'myplugin.py': '# no-op\n'},probe='myplugin.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'myplugin.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='native':
 lock=seed({'pyproject.toml': '[tool.pytest]\naddopts=["-p", "myplugin"]\n', 'myplugin.py': '# no-op\n'},probe='myplugin.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'myplugin.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='pytest-toml':
 lock=seed({'pytest.toml': '[pytest]\naddopts=["-p", "myplugin"]\n', 'myplugin.py': '# no-op\n'},probe='myplugin.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'myplugin.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='ini-continuation':
 lock=seed({'setup.cfg': '[tool:pytest]\naddopts: -q\n # comment does not end value\n\n  -p myplugin\n', 'myplugin.py': '# no-op\n'},probe='myplugin.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'myplugin.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='tox':
 lock=seed({'tox.ini': '[tox]\nenvlist=py\n[pytest]\naddopts=-p unrelated\naddopts=-p myplugin\n', 'myplugin.py': '# no-op\n'},probe='myplugin.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'myplugin.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='quoted':
 lock=seed({'pytest.ini': '[pytest]\naddopts="-p" \'myplugin\'\n', 'myplugin.py': '# no-op\n'},probe='myplugin.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'myplugin.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='plugins-comma':
 lock=seed({'conftest.py': 'pytest_plugins = "a,b"\n', 'a.py': '# no-op\n', 'b.py': '# no-op\n'},probe='b.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'b.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in b.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in b.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='plugins-tuple':
 lock=seed({'conftest.py': 'pytest_plugins: tuple[str, ...] = (\n "a", # comment\n "b",\n)\n', 'a.py': '# no-op\n', 'b.py': '# no-op\n'},probe='b.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'b.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in b.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in b.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='plugins-group':
 lock=seed({'conftest.py': 'pytest_plugins = (\n # grouped, not a tuple\n "a,b"\n)\n', 'a.py': '# no-op\n', 'b.py': '# no-op\n'},probe='b.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'b.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in b.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in b.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='plugins-cr':
 lock=seed({'conftest.py': b'# physical CR lines\rpytest_plugins = ["b"]\r', 'b.py': '# no-op\n'},probe='b.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'b.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in b.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in b.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='package-root':
 lock=seed({'svc/__init__.py': '', 'svc/conftest.py': 'pytest_plugins = ["support"]\n', 'support.py': '# no-op\n'},probe='../support.py',root='svc')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'support.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in support.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in support.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='override':
 lock=seed({'myplugin.py': '# no-op\n'},probe='myplugin.py',command='python3 pytest156.py {junit} -o addopts="-p myplugin"')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'myplugin.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='linked-base':
 lock=seed({'pyproject.toml': '[tool.pytest.ini_options]\npythonpath=["plugins"]\naddopts="-p myplugin"\n', 'realplugins/myplugin.py': '# no-op\n'},probe='realplugins/myplugin.py')
 Path('plugins').symlink_to('realplugins',target_is_directory=True)
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'realplugins/myplugin.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in plugins are behind a symbolic link "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in plugins; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='transitive':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': 'pytest_plugins=["middle"]\n', 'middle.py': 'pytest_plugins=["leaf"]\n', 'leaf.py': 'pytest_plugins=["myplugin"]\n'},probe='leaf.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'leaf.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in leaf.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in leaf.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='package-init':
 lock=seed({'pytest.ini': '[pytest]\naddopts=-p pkg.mod\n', 'pkg/__init__.py': '# no-op\n', 'pkg/mod.py': '# no-op\n'},probe='pkg/__init__.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'pkg/__init__.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in pkg/__init__.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in pkg/__init__.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='shadow-package':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n'},probe='myplugin/__init__.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'myplugin/__init__.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin/__init__.py were added "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin/__init__.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='shadow-base':
 lock=seed({'pyproject.toml': '[tool.pytest.ini_options]\npythonpath=["plugins"]\naddopts="-p myplugin"\n', 'myplugin.py': '# no-op\n'},probe='plugins/myplugin.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'plugins/myplugin.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in plugins/myplugin.py were added "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in plugins/myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='ci':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n'})
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'myplugin.py': '# PASS156\n'},ci=True)
 assert p.returncode==1 and rows()[-1]['code']=='pytest-plugin-changed',(p.returncode,rows()[-1])
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py changed "+('in commit '+git('rev-parse','HEAD')[:7])+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='ci',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='byte-order':
 lock=seed({'pytest.ini': '[pytest]\naddopts=-p zplug -p aplug\n', 'aplug.py': '# no-op\n', 'zplug.py': '# no-op\n'},probe='zplug.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'zplug.py': '# PASS156\n', 'aplug.py': '# changed\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in aplug.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in aplug.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='closed':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n'})
 write('calc.py','def add(a,b): return a+b\n');git('add','calc.py');ok('shipcraft','check')
 assert json.loads(lock.read_text())['state']=='closed'
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'myplugin.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
elif case=='index':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n'})
 write('myplugin.py','# PASS156\n');git('add','myplugin.py');write('myplugin.py','# no-op\n')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=run('git','commit','-qm','index156')
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='removed':
 lock=seed({'pytest.ini': '[pytest]\naddopts=-p aplug -p zplug\n', 'aplug.py': '# no-op\n', 'zplug.py': '# no-op\n'},probe='zplug.py')
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'aplug.py': None, 'zplug.py': '# PASS156\n'})
 assert p.returncode==1,('expected plugin refusal before suite',p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in aplug.py were removed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in aplug.py; if the suite needs it, make it after the cycle closes"],lines
 assert rows()[-1]['code']=='pytest-plugin-changed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='log-failure':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n'})
 oldlog=Path('.git/shipcraft/output/hook.log').read_bytes()
 p=judge({'myplugin.py': '# PASS156\n'},logfail=True)
 assert p.returncode==1 and Path('.git/shipcraft/runs.jsonl').is_dir(),(p.returncode,p.stdout,p.stderr)
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==["shipcraft refused: pytest's plugins in myplugin.py changed "+('in the index')+f" with lock {lock} open", 'Why: pytest loads this file as plugin code before the tests (its hooks can skip, deselect or pass a case), so changing it during GREEN changes the judge mid-game', "Next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],lines
 assert 'running the suite' not in p.stdout+p.stderr
 assert Path('.git/shipcraft/output/hook.log').read_bytes()==oldlog
 assert json.loads(lock.read_text())['state']=='open'
elif case=='close':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n'})
 write('myplugin.py','# PASS156\n');git('add','myplugin.py');ok('git','commit','--no-verify','-qm','close156')
 sha=git('rev-parse','HEAD');before=Path('.git/shipcraft/runs.jsonl').read_bytes();tree=git('write-tree');trace=Path('.trace156').read_bytes()
 p=ok('shipcraft','close')
 assert Path('.git/shipcraft/runs.jsonl').read_bytes()==before and git('rev-parse','HEAD')==sha and git('write-tree')==tree and Path('.trace156').read_bytes()==trace
 assert p.stdout.splitlines()==[f"shipcraft: commit {sha[:7]} (commit) was not judged by the hook, with lock {lock.stem} open; checking it now against the locks, without the suite (CI judges it in full).", f"shipcraft: commit {sha[:7]} would be refused by CI (pytest-plugin-changed): pytest's plugins in myplugin.py changed in commit {sha[:7]} with lock {lock} open; next: undo the change to pytest's plugins in myplugin.py; if the suite needs it, make it after the cycle closes"],p.stdout
 assert ok('shipcraft','close').stdout==p.stdout
elif case=='control-fake':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n', 'unreached.py': '# no-op\n'})
 assert json.loads(lock.read_text())['failing_at_red']==['tests.test_calc::test_adds']
 assert Path('.trace156').read_text().splitlines()[-1]=='fake156:False'
 write('unreached.py','# PASS156\n');p=judge({'calc.py':'def add(a,b): return a+b\n','tests/test_new.py':'def test_new(): assert True\n'})
 assert p.returncode==0 and json.loads(lock.read_text())['state']=='closed'
 assert Path('.trace156').read_text().splitlines()[-1]=='fake156:True'
 # With no lock open even a named plugin edit is allowed.
 p=judge({'myplugin.py':'# PASS156\n'});assert p.returncode==0
 assert git('show','HEAD:myplugin.py')=='# PASS156'
elif case=='control-real':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n'},real=True)
 p=judge({'calc.py': 'def add(a,b): return a+b\n'})
 assert p.returncode==0 and json.loads(lock.read_text())['state']=='closed'
 assert '2 passed' in p.stdout+p.stderr and git('show','HEAD:myplugin.py')=='# no-op'
elif case=='control-names':
 lock=seed({'pytest.ini': '[pytest]\naddopts=-p no:myplugin -p bad-name\n', 'conftest.py': 'names=["myplugin"]\npytest_plugins = names\n"""\npytest_plugins = ["myplugin"]\n"""\n', 'myplugin.py': '# no-op\n', 'bad-name.py': '# no-op\n'})
 p=judge({'myplugin.py': '# PASS156\n', 'bad-name.py': '# PASS156\n'})
 assert p.returncode==0 and json.loads(lock.read_text())['state']=='closed'
 assert Path('.trace156').read_text().splitlines()[-1]=='fake156:True' and 'raise NotImplementedError' in Path('calc.py').read_text()
elif case=='control-root':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n', 'svc/myplugin.py': '# no-op\n'},root='./svc//',probe='../myplugin.py')
 p=judge({'myplugin.py': '# PASS156\n'})
 assert p.returncode==0 and json.loads(lock.read_text())['state']=='closed'
 assert Path('svc/.trace156').read_text().splitlines()[-1]=='fake156:True' and 'raise NotImplementedError' in Path('svc/calc.py').read_text()
elif case=='control-no-pytest':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n', 'runner156.py': "import runpy\nrunpy.run_path('pytest156.py',run_name='__main__')\n"},command='python3 runner156.py {junit}')
 p=judge({'myplugin.py': '# PASS156\n', 'conftest.py': '# new\n'})
 assert p.returncode==0 and json.loads(lock.read_text())['state']=='closed'
 assert Path('.trace156').read_text().splitlines()[-1]=='fake156:True'
elif case=='control-red':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n'},redsettings={'myplugin.py': '# no-op\n', 'conftest.py': 'pytest_plugins=["myplugin"]\n'},globs=['tests/test_*.py'])
 d=json.loads(lock.read_text());assert d['state']=='open' and set(d['files'])=={'.shipcraft.toml','tests/test_calc.py'}
 assert d['failing_at_red']==['tests.test_calc::test_adds'] and git('show','HEAD:myplugin.py')=='# no-op'
elif case=='control-merge':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n'})
 branch=git('branch','--show-current');git('checkout','-qb','upstream156','HEAD^')
 write('myplugin.py','# PASS156\n');commit('upstream156 plugin')
 git('checkout',branch);git('merge','--no-commit','--no-ff','upstream156');commit('merged GREEN156')
 assert json.loads(lock.read_text())['state']=='closed' and git('show','HEAD:myplugin.py')=='# PASS156'
 assert len(git('show','-s','--format=%P','HEAD^').split())==2 and 'raise NotImplementedError' in Path('calc.py').read_text()
elif case=='control-precedence':
 lock=seed({'pytest.ini': '[pytest]\naddopts = -p myplugin\n', 'myplugin.py': '# no-op\n', 'conftest.py': '# no-op\n', 'tests/plug.py': '# no-op\n'},globs=['tests/**', '**/conftest.py'])
 base=git('rev-parse','HEAD')
 for path in ('conftest.py','tests/plug.py'):
  p=judge({path:'# PASS156\n','myplugin.py':'# PASS156\n'})
  assert p.returncode==1 and rows()[-1]['code']=='test-changed' and rows()[-1]['layer']=='hook'
  git('reset','--hard',base)
 p=judge({'pytest.ini':'[pytest]\naddopts=-p myplugin -q\n','myplugin.py':'# PASS156\n'})
 assert p.returncode==1 and rows()[-1]['code']=='pytest-config-changed'
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert lines==[f"shipcraft refused: pytest's settings in pytest.ini changed in the index with lock {lock} open","Why: pytest reads how the suite runs from these settings (plugins, options, import paths), so changing them during GREEN changes the judge mid-game","Next: undo the change to pytest's settings in pytest.ini; if the suite needs it, make it after the cycle closes"],lines
else:raise AssertionError('unrouted '+case)
PY156
  pass
}
