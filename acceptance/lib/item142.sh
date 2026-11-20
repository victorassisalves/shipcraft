# Item 142: public commands, real local Git; no network.
item142_langs() { echo core; }
item142_cases() {
  local c
  for c in repro empty-upstream append-ending absent-created absent-empty suffix above local earlier claude before-init agents-only executable delete unchanged-block malformed-edited malformed-start malformed-two malformed-reversed malformed-crlf malformed-end malformed-claude oldest-order symlink fallback-base-folder empty-refusal late-failure fresh-bare fresh-local upgrade old-status status-line status-other-base status-config status-legacy status-no-origin status-tag status-tree-fail docs-section fixture-control; do echo "v1-142.$c"; done
}
item142_case() {
  EXPECT="item 142: ${CASE#v1-142.}"
  v1_start codex claude
  must_accept 'item142 contract' cmd "$PY" - "${CASE#v1-142.}" "$(command -v shipcraft)" "$CW" "$ACEITE" <<'PY142'
import ast,json,os,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw,acceptance=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw);acceptance=Path(acceptance)
os.environ['GIT_ALLOW_PROTOCOL']='file'
def run(*args,**kw):
 p=subprocess.run(list(map(str,args)),capture_output=True,timeout=60,**kw)
 print('$',repr(args),'exit',p.returncode,repr(p.stdout),repr(p.stderr),flush=True);return p
def ok(*args,**kw):
 p=run(*args,**kw);assert p.returncode==0,('fixture command',args,p.stdout,p.stderr);return p.stdout
def git(*args,**kw):return ok('git',*args,**kw).decode().strip()
def put(path,data):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data.encode() if isinstance(data,str) else data)
def commit(message):
 git('add','-A');git('commit','-qm',message);return git('rev-parse','HEAD')
def snapshot():
 files={}
 for p in Path('.').rglob('*'):
  if '.git' in p.parts:continue
  if p.is_symlink():files[str(p)]=('link',os.readlink(p))
  elif p.is_file():files[str(p)]=(stat.S_IMODE(p.stat().st_mode),p.read_bytes())
 return (Path('.git/HEAD').read_bytes(),Path('.git/index').read_bytes(),files,Path('.git/shipcraft/runs.jsonl').read_bytes() if Path('.git/shipcraft/runs.jsonl').is_file() else None,git('for-each-ref','--format=%(refname) %(objectname) %(symref)'))
runner='''#!/bin/sh
out=$1
mkdir -p "$(dirname "$out")"
printf '<testsuites><testsuite name="shell142">' > "$out"
failed=0
for t in tests/*.sh; do
 printf '<testcase classname="%s" name="check" file="%s">' "$t" "$t" >> "$out"
 if ! sh "$t"; then printf '<failure message="wrong value"/>' >> "$out"; failed=1; fi
 printf '</testcase>' >> "$out"
done
printf '</testsuite></testsuites>' >> "$out"
exit "$failed"
'''

def frozen85():
 text=(acceptance/'lib/item85.sh').read_text().split("<<'PY85'\n",1)[1].split('\nPY85',1)[0];ns={}
 for node in ast.parse(text).body:
  if isinstance(node,ast.Assign) and all(isinstance(t,ast.Name) and t.id in {'OLD84','ROOT_LINE','CLEANUP','NEW'} for t in node.targets):exec(compile(ast.Module(body=[node],type_ignores=[]),'fixture85','exec'),ns)
  elif isinstance(node,ast.FunctionDef) and node.name=='variant':exec(compile(ast.Module(body=[node],type_ignores=[]),'fixture85','exec'),ns)
 return ns
f85=frozen85()
NEW_LINE=b"- To contribute to a project that does not use Shipcraft (its default branch has no `.shipcraft.toml` or `.sc2.toml`), open the PR from the branch `shipcraft export --base <base> <new branch>` writes once the lock is closed and `shipcraft ci --base <base>` passes on this branch: it leaves out Shipcraft's files and this block, and the project's own checks still apply to it. `shipcraft pr` is for projects that use Shipcraft.\n"
PIN=f85['NEW'].replace(b'- A behavior change:',NEW_LINE+b'- A behavior change:',1)
pin_source=(acceptance/'lib/item86.sh').read_text().split("<<'PY86'\n",1)[1].split('\nPY86',1)[0]
pin_ns={'item85':f85}
for node in ast.parse(pin_source).body:
 if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='PIN' for t in node.targets):exec(compile(ast.Module(body=[node],type_ignores=[]),'pin86','exec'),pin_ns)
CURRENT_PIN=pin_ns['PIN']
IMPORT=b'<!-- shipcraft -->\nShipcraft workflow (required): @AGENTS.md\n<!-- /shipcraft -->\n'
def init(call=binary):
 return ok(call,'init','--lang','other','--command','sh run-tests.sh {junit}','--glob','tests/*.sh')
def base(changes):
 git('checkout','-q','main')
 for path,data in changes.items():
  p=Path(path)
  if p.is_symlink() or p.is_file():p.unlink()
  if data is not None:put(path,data)
 oid=commit('alternate upstream142');git('checkout','-q','fix');git('reset','--hard',oid);git('update-ref','refs/remotes/origin/main',oid);return oid
def change(changes,message='contribution142'):
 for path,data in changes.items():
  p=Path(path)
  if p.is_symlink() or p.is_file():p.unlink()
  if data is not None:put(path,data)
 return commit(message)
def export(branch='clean142'):
 before=snapshot();p=run(binary,'export','--base','origin/main',branch);after=snapshot()
 assert before[:4]==after[:4],'export changed HEAD/index/tree/log'
 if p.returncode:
  assert before==after,'failed export wrote refs'
 else:
  assert '\n'.join(l for l in after[4].splitlines() if not l.startswith('refs/heads/'+branch+' '))==before[4],'export moved another ref'
 return p
def blob(name='AGENTS.md',branch='clean142'):
 p=run('git','show',branch+':'+name);return p.stdout if p.returncode==0 else None
def gh_stub():
 bindir=cw/'gh142';bindir.mkdir();trace=cw/'gh142.calls'
 put(bindir/'gh','#!'+sys.executable+'\nimport json,sys\nwith open('+repr(str(trace))+',"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nprint("gh: unavailable142",file=sys.stderr)\nsys.exit(1)\n');(bindir/'gh').chmod(0o755)
 return dict(os.environ,PATH=str(bindir)+os.pathsep+os.environ['PATH']),trace
def status(env):
 before=snapshot();p=run(binary,'status',env=env);assert snapshot()==before,'status wrote repository state';return p

root=cw/'upstream142';root.mkdir();os.chdir(root)
git('init','-q','-b','main');git('config','user.name','Fixture142');git('config','user.email','fixture@example.invalid')
put('src/calc.txt','1\n');put('tests/calc.sh','test "$(cat src/calc.txt)" -ge 1\n');put('run-tests.sh',runner)
put('AGENTS.md','# Upstream rules\n\n- Keep it small.\n');f=commit('upstream142')
clone=cw/'clone142';git('clone','-q',root,clone);os.chdir(clone);git('config','user.name','Fixture142');git('config','user.email','fixture@example.invalid');git('checkout','-qb','fix')
if case=='repro':
 ok(binary,'init','--lang','other','--command','sh run-tests.sh {junit}','--glob','tests/*.sh');commit('add shipcraft')
 put('tests/sub.sh','test "$(cat src/calc.txt)" = 2\n');ok(binary,'red');commit('test: sub')
 put('src/calc.txt','2\n');put('AGENTS.md',Path('AGENTS.md').read_bytes().replace(b'- Keep it small.\n',b'- Keep it small.\n- Name the issue in the PR.\n'));commit('feat: sub')
 locks=list(Path('.shipcraft/locks').glob('*.json'));assert len(locks)==1 and json.loads(locks[0].read_text())['state']=='closed'
 before=snapshot();p=run(binary,'export','--base','origin/main','fix-upstream');after=snapshot()
 assert p.returncode==0 and before[:4]==after[:4],(p.stdout,p.stderr)
 exported=ok('git','show','fix-upstream:AGENTS.md');print('REPRO exported AGENTS.md:',repr(exported),flush=True)
 assert exported==b'# Upstream rules\n\n- Keep it small.\n- Name the issue in the PR.\n','export lost the contributor rule above the block'
 assert run('git','cat-file','-e','fix-upstream:CLAUDE.md').returncode!=0
 assert b'AGENTS.md' not in b'\n'.join(l for l in p.stdout.splitlines() if b'kept as in' in l)

elif case=='empty-upstream':
 f=base({'AGENTS.md':b''});init();change({'src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and blob()==b''
 assert b'AGENTS.md' not in b'\n'.join(l for l in p.stdout.splitlines() if b'kept as in' in l)
elif case=='append-ending':
 for i,ending in enumerate((b'',b'\n',b'\n\n',b'\r\n')):
  # A fresh clone per ending keeps init's installed hooks with their config.
  if i:
   fresh=cw/('ending-repo142-'+str(i));git('clone','-q',root,fresh);os.chdir(fresh);git('config','user.name','Fixture142');git('config','user.email','fixture@example.invalid');git('checkout','-qb','fix')
  f=base({'AGENTS.md':b'upstream142'+ending});init();change({'src/calc.txt':str(i+2)+'\n'},'init plus product142')
  p=export('ending'+str(i));assert p.returncode==0
  assert blob(branch='ending'+str(i))==b'upstream142'+ending
  assert b'AGENTS.md' not in b'\n'.join(l for l in p.stdout.splitlines() if b'kept as in' in l),'recognized append still named kept'
elif case=='absent-created':
 f=base({'AGENTS.md':None});init();put('AGENTS.md',b'contributor142\n\n'+Path('AGENTS.md').read_bytes());change({'src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and blob()==b'contributor142\n'
elif case=='absent-empty':
 f=base({'AGENTS.md':None});init();change({'src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and run('git','cat-file','-e','clean142:AGENTS.md').returncode!=0
 assert b'AGENTS.md' not in b'\n'.join(l for l in p.stdout.splitlines() if b'kept as in' in l)
elif case=='suffix':
 init();put('AGENTS.md',Path('AGENTS.md').read_bytes()+b'after142\x00\r\nno final newline');change({'src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and blob()==b'# Upstream rules\n\n- Keep it small.\n\nafter142\x00\r\nno final newline'
elif case=='above':
 init();put('AGENTS.md',Path('AGENTS.md').read_bytes().replace(b'Keep it small.',b'Keep it clear.'));change({'src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and blob()==b'# Upstream rules\n\n- Keep it clear.\n'
elif case=='local':
 init();put('AGENTS.md',b'local contributor142\n\n'+f85['variant'](f85['NEW'],True));change({'src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and blob()==b'local contributor142\n'
 change({'AGENTS.md':b'new local142\n\n'+f85['variant'](PIN,True)});p=export('new-local142')
 assert p.returncode==0 and blob(branch='new-local142')==b'new local142\n'
elif case=='earlier':
 init();put('AGENTS.md',b'earlier contributor142\n\n'+f85['OLD84']);change({'src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and blob()==b'earlier contributor142\n'
elif case=='claude':
 init();change({'CLAUDE.md':b'claude contributor142\n\n'+IMPORT});p=export()
 assert p.returncode==0 and blob('CLAUDE.md')==b'claude contributor142\n'
 assert b'CLAUDE.md' not in b'\n'.join(l for l in p.stdout.splitlines() if b'kept as in' in l)
elif case=='before-init':
 plain=b'pre-init142\xff\n\xef\xbb\xbf<!-- shipcraft -->\n<!-- shipcraft --> \n<!-- /shipcraft --> \n<!-- shipcraft -->\xe2\x80\xa8<!-- /shipcraft -->\xe2\x80\xa9'
 first=change({'AGENTS.md':plain});init();commit('setup142');p=export()
 assert p.returncode==0 and blob()==plain
 assert git('rev-list','--count',f+'..clean142')=='1'
 assert b'AGENTS.md' not in b'\n'.join(l for l in p.stdout.splitlines() if b'kept as in' in l)
elif case=='agents-only':
 init();setup=commit('setup142');put('AGENTS.md',Path('AGENTS.md').read_bytes().replace(b'Keep it small.',b'Only contributor142.'));commit('agents only142');p=export()
 assert p.returncode==0 and blob()==b'# Upstream rules\n\n- Only contributor142.\n'
 assert b'left out '+setup[:7].encode()+b' setup142:' in p.stdout
 assert git('rev-list','--count',f+'..clean142')=='1'
elif case=='executable':
 init();put('AGENTS.md',b'executable142\n\n'+PIN);Path('AGENTS.md').chmod(0o755);commit('executable142');trace=cw/'raw-git142.trace';os.environ['GIT_TRACE']=str(trace);p=export();del os.environ['GIT_TRACE']
 assert p.returncode==0 and blob()==b'executable142\n'
 assert git('ls-tree','clean142','AGENTS.md').startswith('100755 blob ')
 assert any('hash-object' in l.split() and all(flag in l.split() for flag in ('-w','--no-filters','--stdin')) for l in trace.read_text().splitlines())
elif case=='delete':
 init();change({'AGENTS.md':None});p=export()
 assert p.returncode==0 and run('git','cat-file','-e','clean142:AGENTS.md').returncode!=0
elif case=='unchanged-block':
 f=base({'AGENTS.md':b'upstream block142\n'+PIN});h=change({'src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and blob()==b'upstream block142\n'+PIN
 assert git('rev-parse','clean142')==h and b'kept as in' not in p.stdout
elif case=='malformed-edited':
 init();bad=change({'AGENTS.md':b'own142\n'+PIN.replace(b'TDD with',b'EDIT with',1),'src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and blob()==b'# Upstream rules\n\n- Keep it small.\n'
 assert f'shipcraft: AGENTS.md in {bad[:7]} has a shipcraft block that is not one Shipcraft writes, or markers that do not pair, so it is kept as in {f[:7]}\n'.encode() in p.stdout
elif case=='malformed-start':
 bad=change({'AGENTS.md':b'<!-- shipcraft -->\r\nonly142','src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and f'shipcraft: AGENTS.md in {bad[:7]} has a shipcraft block that is not one Shipcraft writes, or markers that do not pair, so it is kept as in {f[:7]}\n'.encode() in p.stdout
 assert blob()==b'# Upstream rules\n\n- Keep it small.\n'
elif case=='malformed-two':
 bad=change({'AGENTS.md':PIN+PIN,'src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and f'shipcraft: AGENTS.md in {bad[:7]} has a shipcraft block that is not one Shipcraft writes, or markers that do not pair, so it is kept as in {f[:7]}\n'.encode() in p.stdout
 assert blob()==b'# Upstream rules\n\n- Keep it small.\n'
elif case=='malformed-reversed':
 bad=change({'AGENTS.md':b'<!-- /shipcraft -->\n<!-- shipcraft -->','src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and f'shipcraft: AGENTS.md in {bad[:7]} has a shipcraft block that is not one Shipcraft writes, or markers that do not pair, so it is kept as in {f[:7]}\n'.encode() in p.stdout
 assert blob()==b'# Upstream rules\n\n- Keep it small.\n'
elif case=='malformed-crlf':
 bad=change({'AGENTS.md':PIN.replace(b'\n',b'\r\n'),'src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and f'shipcraft: AGENTS.md in {bad[:7]} has a shipcraft block that is not one Shipcraft writes, or markers that do not pair, so it is kept as in {f[:7]}\n'.encode() in p.stdout
 assert blob()==b'# Upstream rules\n\n- Keep it small.\n'
elif case=='malformed-end':
 bad=change({'AGENTS.md':b'<!-- /shipcraft -->\r','src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and f'shipcraft: AGENTS.md in {bad[:7]} has a shipcraft block that is not one Shipcraft writes, or markers that do not pair, so it is kept as in {f[:7]}\n'.encode() in p.stdout
 assert blob()==b'# Upstream rules\n\n- Keep it small.\n'
elif case=='malformed-claude':
 bad=change({'CLAUDE.md':IMPORT.replace(b'@AGENTS.md',b'@OTHER.md'),'src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and run('git','cat-file','-e','clean142:CLAUDE.md').returncode!=0
 assert f'shipcraft: CLAUDE.md in {bad[:7]} has a shipcraft block that is not one Shipcraft writes, or markers that do not pair, so it is kept as in {f[:7]}\n'.encode() in p.stdout
elif case=='oldest-order':
 a=change({'CLAUDE.md':b'<!-- shipcraft -->\n','src/calc.txt':'2\n'});b=change({'AGENTS.md':b'<!-- /shipcraft -->\n','CLAUDE.md':b'<!-- /shipcraft -->\n'});change({'AGENTS.md':b'<!-- shipcraft -->\n'});p=export()
 expected=[f'shipcraft: AGENTS.md in {b[:7]} has a shipcraft block that is not one Shipcraft writes, or markers that do not pair, so it is kept as in {f[:7]}',f'shipcraft: CLAUDE.md in {a[:7]} has a shipcraft block that is not one Shipcraft writes, or markers that do not pair, so it is kept as in {f[:7]}',f"shipcraft: kept as in {f[:7]}: AGENTS.md, CLAUDE.md; add any change of yours to them by hand"]
 assert p.returncode==0 and p.stdout.decode().splitlines()[-4:-1]==expected
elif case=='symlink':
 Path('AGENTS.md').unlink();Path('AGENTS.md').symlink_to('src/calc.txt');change({'src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and blob()==b'# Upstream rules\n\n- Keep it small.\n'
 assert b'has a shipcraft block' not in p.stdout and f'kept as in {f[:7]}: AGENTS.md;'.encode() in p.stdout
elif case=='fallback-base-folder':
 f=base({'AGENTS.md':None,'AGENTS.md/rules':'folder142'});shutil.rmtree('AGENTS.md');change({'AGENTS.md':b'regular142','src/calc.txt':'2\n'});p=export()
 assert p.returncode==0 and blob('AGENTS.md/rules')==b'folder142' and b'has a shipcraft block' not in p.stdout
elif case=='empty-refusal':
 change({'AGENTS.md':b'<!-- shipcraft -->\n'});p=export()
 assert p.returncode==1 and p.stdout==b'' and p.stderr==b"shipcraft refused: no commit in origin/main..HEAD changes a file outside Shipcraft's files\nWhy: the branch would hold nothing to send upstream; nothing was written\nNext: commit your change on this branch, then run shipcraft export again\n"
elif case=='late-failure':
 change({'AGENTS.md':b'<!-- shipcraft -->\n','src/calc.txt':'2\n'});git('branch','clean142/child',f);p=export()
 assert p.returncode==2 and p.stdout==b'' and p.stderr.startswith(b'shipcraft: error:')
elif case=='fresh-bare':
 init();actual=Path('AGENTS.md').read_bytes();assert actual==b'# Upstream rules\n\n- Keep it small.\n\n'+CURRENT_PIN
elif case=='fresh-local':
 target=Path('node_modules/shipcraft-fixture/bin/shipcraft');target.parent.mkdir(parents=True);shutil.copy2(binary,target);target=target.resolve();call=Path('node_modules/.bin/shipcraft');call.parent.mkdir();call.symlink_to(target);init(call.resolve())
 assert Path('AGENTS.md').read_bytes()==b'# Upstream rules\n\n- Keep it small.\n\n'+f85['variant'](CURRENT_PIN,True)
elif case=='upgrade':
 init()
 for local in (False,True):
  put('AGENTS.md',b'prefix142\n'+f85['variant'](f85['NEW'],local)+b'suffix142');init()
  assert Path('AGENTS.md').read_bytes()==b'prefix142\n'+CURRENT_PIN+b'suffix142'
elif case=='old-status':
 init();put('AGENTS.md',f85['NEW']);env,trace=gh_stub();p=status(env)
 assert p.returncode==0 and b'shipcraft: AGENTS.md block: from an earlier version; run `shipcraft init` to update it' in p.stdout
 init();p=status(env);assert b'shipcraft: AGENTS.md block: current\n' in p.stdout
elif case=='status-line':
 init();git('remote','set-url','origin','https://github.com/acme/project142.git');env,trace=gh_stub();p=status(env)
 expected="shipcraft: origin/main has no .shipcraft.toml: if this project does not use Shipcraft, make the branch for its PR with `shipcraft export --base origin/main <new branch>` once the lock is closed"
 lines=p.stdout.decode().splitlines();assert p.returncode==0 and lines[-2:]==[expected,'shipcraft: could not read branch protection (gh: unavailable142): use `shipcraft merge` as the gate']
 assert [json.loads(x) for x in trace.read_text().splitlines()]==[['api','repos/{owner}/{repo}/branches/main/protection']]
elif case=='status-other-base':
 init();git('branch','-m','main','trunk142');git('update-ref','refs/remotes/origin/trunk142',f);git('symbolic-ref','refs/remotes/origin/HEAD','refs/remotes/origin/trunk142');git('remote','set-url','origin','https://github.com/acme/project142.git');env,trace=gh_stub();p=status(env)
 expected="shipcraft: origin/trunk142 has no .shipcraft.toml: if this project does not use Shipcraft, make the branch for its PR with `shipcraft export --base origin/trunk142 <new branch>` once the lock is closed"
 assert p.returncode==0 and p.stdout.decode().splitlines()[-2]==expected
 assert [json.loads(x) for x in trace.read_text().splitlines()]==[['api','repos/{owner}/{repo}/branches/trunk142/protection']]
elif case=='status-config':
 f=base({'.shipcraft.toml':None,'.shipcraft.toml/child':'not a regular config142'});shutil.rmtree('.shipcraft.toml');init();git('remote','set-url','origin','https://github.com/acme/project142.git');env,trace=gh_stub();p=status(env)
 assert p.returncode==0 and b'if this project does not use Shipcraft' not in p.stdout
 assert p.stdout.decode().splitlines()[-1]=='shipcraft: could not read branch protection (gh: unavailable142): use `shipcraft merge` as the gate'
 assert [json.loads(x) for x in trace.read_text().splitlines()]==[['api','repos/{owner}/{repo}/branches/main/protection']]
elif case=='status-legacy':
 f=base({'.sc2.toml':'legacy142'});Path('.sc2.toml').unlink();init();git('remote','set-url','origin','https://github.com/acme/project142.git');env,trace=gh_stub();p=status(env)
 assert p.returncode==0 and b'if this project does not use Shipcraft' not in p.stdout
 assert [json.loads(x) for x in trace.read_text().splitlines()]==[['api','repos/{owner}/{repo}/branches/main/protection']]
elif case=='status-no-origin':
 init();git('remote','remove','origin');env,trace=gh_stub();p=status(env)
 assert p.returncode==0 and b'if this project does not use Shipcraft' not in p.stdout and [json.loads(x) for x in trace.read_text().splitlines()]==[['api','repos/{owner}/{repo}/branches/main/protection']]
 assert b'shipcraft: branch fix' in p.stdout and b'shipcraft: open locks: none' in p.stdout
elif case=='status-tag':
 init();git('tag','origin/main',f);git('update-ref','-d','refs/remotes/origin/main');git('remote','set-url','origin','https://github.com/acme/project142.git');env,trace=gh_stub();p=status(env)
 assert p.returncode==0 and b'if this project does not use Shipcraft' not in p.stdout
 assert [json.loads(x) for x in trace.read_text().splitlines()]==[['api','repos/{owner}/{repo}/branches/main/protection']]
elif case=='status-tree-fail':
 init();git('remote','set-url','origin','https://github.com/acme/project142.git');tree=git('rev-parse',f+'^{tree}');Path('.git/objects/'+tree[:2]+'/'+tree[2:]).unlink();env,trace=gh_stub();p=status(env)
 assert p.returncode==0 and b'if this project does not use Shipcraft' not in p.stdout
 assert [json.loads(x) for x in trace.read_text().splitlines()]==[['api','repos/{owner}/{repo}/branches/main/protection']]
elif case=='docs-section':
 text=(acceptance.parent/'docs/spec.md').read_text().split('## 3.',1)[1].split('## 4.',1)[0]
 assert "(item 135; `AGENTS.md` and `CLAUDE.md` keep everything but Shipcraft's block, item 142)" in text
 assert 'a line naming `export` when `origin/<default branch>` has no `.shipcraft.toml` (item 142), and one line with the real branch protection level' in text
 # README is intentionally not edited by RED.
 readme=(acceptance.parent/'README.md').read_text();assert "(config, locks, briefs, Shipcraft's block in `AGENTS.md` and `CLAUDE.md`, hook manager files)" in readme
elif case=='fixture-control':
 init();assert Path('CLAUDE.md').read_bytes()==IMPORT
 assert Path('AGENTS.md').read_bytes() ==b'# Upstream rules\n\n- Keep it small.\n\n'+CURRENT_PIN
 commit('setup control142')
 put('tests/sub.sh','test "$(cat src/calc.txt)" = 2\n');ok(binary,'red');commit('test control142');change({'src/calc.txt':'2\n'},'green control142')
 lock=list(Path('.shipcraft/locks').glob('*.json'));assert len(lock)==1 and json.loads(lock[0].read_text())['state']=='closed'
 assert ok('sh','run-tests.sh',cw/'control142.xml')==b'' and b'classname="tests/sub.sh"' in (cw/'control142.xml').read_bytes()
 p=export();assert p.returncode==0 and blob()==b'# Upstream rules\n\n- Keep it small.\n'
 assert git('rev-list','--count',f+'..clean142')=='2' and blob('tests/sub.sh')==b'test "$(cat src/calc.txt)" = 2\n'
 localroot=cw/'local-control142';localroot.mkdir();os.chdir(localroot);git('init','-q','-b','main')
 target=Path('node_modules/shipcraft-fixture/bin/shipcraft');target.parent.mkdir(parents=True);shutil.copy2(binary,target);target=target.resolve();call=Path('node_modules/.bin/shipcraft');call.parent.mkdir();call.symlink_to(target);init(call.resolve())
 assert Path('AGENTS.md').read_bytes() ==f85['variant'](CURRENT_PIN,True)
 assert Path('CLAUDE.md').read_bytes()==IMPORT
else:raise AssertionError('unrouted '+case)
PY142
  pass
}
