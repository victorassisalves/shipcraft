# Item 70: public init/status; no agent is started by these cases.
item70_langs() { echo core; }
item70_cases() {
  local c source target
  for c in block upgrade-brief-fails edited write-fails write-partial refused; do
    for target in bare local; do echo "v1-70.$c-$target"; done
  done
  for source in bare local; do
    for target in bare local; do echo "v1-70.upgrade-$source-$target"; done
  done
  for c in config folder format malformed; do echo "v1-70.status-$c"; done
}
item70_case() {
  EXPECT="item 70: ${CASE#v1-70.}"
  v1_start codex claude
  must_accept 'item 70 fallback and migration contract' cmd "$PY" - "${CASE#v1-70.}" "$(command -v shipcraft)" "$ACEITE" "$CW" <<'PY70'
import ast,json,os,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,acceptance,cw=sys.argv[1:];binary=str(Path(binary).resolve())
# Exact AGENTS_BLOCK at v2.25.0. Only that constant and its variant function were read.
HISTORICAL_BARE=b"<!-- shipcraft -->\n## shipcraft: TDD with a lock (required in this repository)\n- Cycle: RED (a failing test) \xe2\x86\x92 `shipcraft red` \xe2\x86\x92 GREEN (code) \xe2\x86\x92 `git commit`. The git hook checks every commit.\n- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.\n- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.\n- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.\n- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).\n- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.\n- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (`git stash push --include-untracked`; it saved something only if `git rev-parse -q --verify refs/stash` changed, and `git status --porcelain` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with `shipcraft red --redo` and commits; then, if something was saved and `refs/stash` still names it, it restores it with `git stash pop`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, `red --redo` refuses: report it to the user.\n- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.\n- Start each phase with the agent, model and effort that `shipcraft status` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.\n- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.\n- When in doubt, run `shipcraft status`.\n<!-- /shipcraft -->\n"
# Load only existing acceptance expected-text fixtures, not their test execution.
source=(Path(acceptance)/'lib/item61.sh').read_text().split("<<'PY61'\n",1)[1].split('\nPY61',1)[0]
names={'OLD','PREVIOUS_BARE','ROOT_LINE','PREVIOUS_LOCAL','head','rest','READ_TESTS','REPAIR','ROLES','FALLBACK'}
ns={}
for node in ast.parse(source).body:
 if isinstance(node,ast.Assign):
  targets={n.id for t in node.targets for n in ast.walk(t) if isinstance(n,ast.Name)}
  if targets and targets<=names:exec(compile(ast.Module(body=[node],type_ignores=[]),'item61-fixtures','exec'),ns)
 elif isinstance(node,ast.FunctionDef) and node.name=='expected_block':exec(compile(ast.Module(body=[node],type_ignores=[]),'item61-fixtures','exec'),ns)
def variant(block,local):
 if not local:return block
 text=block.replace(b'`shipcraft ',b'`npx -- shipcraft ')
 head,rest=text.split(b'\n- ',1)
 return head+b'\n'+ns['ROOT_LINE']+b'- '+rest
# Brief bodies sampled through public v2.25.0 init in both install variants; stamp is dynamic.
BRIEF_BODIES={False: {'red.md': b'# shipcraft: the RED phase\n\nYou are the RED session: you write the failing tests for a change, not the change.\n\n- Write the failing tests from the intent, never from an implementation.\n- Write two cases per rule: the ordinary one, and a boundary a rushed GREEN would get wrong.\n- First read the existing tests that cover the behavior the change touches, and never contradict them unless the intent says that behavior changes.\n- Each test written for the new behavior must fail for the right reason before you run `shipcraft red`. Passing control tests are fine: they are locked as controls.\n- Fake external tools with their real output.\n- Commit the tests, their stubs and the lock in one commit, and stop.\n- List ambiguities instead of picking a reading silently.\n\n', 'green.md': b"# shipcraft: the GREEN phase\n\nYou are the GREEN session: you make the locked tests pass.\n\n- Start from the RED commit.\n- Never edit a locked file or a lock (`.shipcraft/locks/*`).\n- Change product code, dependencies or config until the locked tests pass.\n- Running the other tests the change touches is a check, not a gate: report a failure outside the locked tests, and let the hook's verdict decide the commit, since CI runs the rest.\n- If a test looks wrong, stop and report the test with the reason, instead of working around it.\n- Commit.\n\n"}, True: {'red.md': b'# shipcraft: the RED phase\n\nYou are the RED session: you write the failing tests for a change, not the change.\n\n- Write the failing tests from the intent, never from an implementation.\n- Write two cases per rule: the ordinary one, and a boundary a rushed GREEN would get wrong.\n- First read the existing tests that cover the behavior the change touches, and never contradict them unless the intent says that behavior changes.\n- Each test written for the new behavior must fail for the right reason before you run `npx -- shipcraft red`. Passing control tests are fine: they are locked as controls.\n- Fake external tools with their real output.\n- Commit the tests, their stubs and the lock in one commit, and stop.\n- List ambiguities instead of picking a reading silently.\n\n', 'green.md': b"# shipcraft: the GREEN phase\n\nYou are the GREEN session: you make the locked tests pass.\n\n- Start from the RED commit.\n- Never edit a locked file or a lock (`.shipcraft/locks/*`).\n- Change product code, dependencies or config until the locked tests pass.\n- Running the other tests the change touches is a check, not a gate: report a failure outside the locked tests, and let the hook's verdict decide the commit, since CI runs the rest.\n- If a test looks wrong, stop and report the test with the reason, instead of working around it.\n- Commit.\n\n"}}
IMPORT=b'<!-- shipcraft -->\nShipcraft workflow (required): @AGENTS.md\n<!-- /shipcraft -->\n'
PREFIX=b'# House rules70\r\n\x00\n';SUFFIX=b'\nAfter70\r\nno final newline'
def write(path,data,mode=None):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
 if mode is not None:p.chmod(mode)
def text(p):return (p.stdout+p.stderr).decode(errors='replace')
def run(*args,ok=True,preexec_fn=None):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,timeout=90,preexec_fn=preexec_fn)
 print('$',repr(args),'[rc='+str(p.returncode)+']\n'+text(p),flush=True)
 if ok:assert p.returncode==0,('command failed before assertion',p.returncode,text(p))
 return p
def snapshot(path):
 p=Path(path)
 if p.is_symlink():return ('link',os.readlink(p))
 if p.is_dir():return ('dir',stat.S_IMODE(p.stat().st_mode),{x.name:snapshot(x) for x in p.iterdir()})
 return ('file',stat.S_IMODE(p.stat().st_mode),p.read_bytes())
root=Path(cw)/"project70 space 'quote";root.mkdir();os.chdir(root)
run('git','init','-q',str(root));write('requirements.txt','pytest\n')
local=case.endswith('-local');call=binary
if local:
 target=root/'node_modules/shipcraft-fixture/bin/shipcraft';target.parent.mkdir(parents=True);shutil.copy2(binary,target)
 call=root/'node_modules/.bin/shipcraft';call.parent.mkdir(parents=True);call.symlink_to(target)
def init(**kw):return run(call,'init',**kw)
def exact_block(actual):
 expected=ns['expected_block'](local)
 assert actual==expected,'missing exact item 70 fallback line or changed other block bytes/order'
 fallback=ns['FALLBACK'].replace(b'`shipcraft ',b'`npx -- shipcraft ') if local else ns['FALLBACK']
 assert actual.count(fallback)==1,'fallback must occur once, as one LF-terminated line'
 assert ns['expected_block'](local).replace(fallback,b'',1)==variant(HISTORICAL_BARE,local),'fixture must add exactly one line to v2.25.0'
def closing(p,agents=True,briefs=True):
 lines=text(p).splitlines();ready=[l for l in lines if l.startswith('shipcraft: ready. Commit ')]
 assert len(ready)==1 and lines[-3]==ready[0],'changed closing order'
 assert ('AGENTS.md' in ready[0])==agents,('closing AGENTS inclusion',ready)
 for name in ('red.md','green.md'):assert ('.shipcraft/briefs/'+name in ready[0])==briefs,('closing brief inclusion',ready)
 assert 'test' in lines[-2] and 'then' in lines[-2]
 assert lines[-1]=='CI runs on this machine through shipcraft pr. To run it on GitHub, see shipcraft docs/github-ci.md.'
def core():
 assert Path('.shipcraft.toml').is_file() and Path('.shipcraft/locks/.gitkeep').read_bytes()==b''
 for event in ('commit-msg','post-commit'):assert os.access('.git/hooks/'+event,os.X_OK)
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'init/status wrote a run-log row'
if case.startswith('status-'):
 init();kind=case[7:]
 # Status must never run the configured command, build, check or provider.
 write('.shipcraft.toml','shipcraft_min = "2.20"\ntest_command = "touch ran70; exit 23 # {junit}"\ntest_globs = ["tests/**"]\ncheck = "touch checked70; exit 24"\n[build]\ncommand = "touch built70; exit 25"\n[execution]\nci = "off"\nreview = "off"\n[roles]\nred = {agent="codex",model="r70",effort="medium"}\ngreen = "claude"\n')
 if kind=='config':write('.shipcraft.toml','invalid TOML [\n')
 elif kind=='folder':pass
 elif kind=='format':write('.shipcraft/locks/status70.json',json.dumps(dict(format=999,state='open',files={},cases=[],failing_at_red=[],seal='')))
 else:write('.shipcraft/locks/status70.json',b'{broken JSON\n')
 before=snapshot('.shipcraft');cfg=Path('.shipcraft.toml').read_bytes()
 if kind=='folder':Path('.shipcraft/locks').chmod(0o000)
 try:
  p=run(call,'status',ok=False)
  assert p.returncode==(2 if kind=='folder' else 0 if kind=='malformed' else 1),('status exit guard',p.returncode,text(p))
  if kind=='folder':assert 'shipcraft: error: ' in text(p),'missing lock-folder read error diagnostic'
  assert ('shipcraft: roles:' in text(p))==(kind!='config'),'status refusal ordering changed'
  if kind=='malformed':assert 'status70' in text(p) and 'open' in text(p),'unparseable lock must be listed open'
 finally:
  if kind=='folder':Path('.shipcraft/locks').chmod(0o755)
 assert snapshot('.shipcraft')==before and Path('.shipcraft.toml').read_bytes()==cfg,'status changed files'
 assert not any(Path(n).exists() for n in ('ran70','checked70','built70')),'status ran project tools'
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'status appended a row'
elif case.startswith('block-'):
 p=init();exact_block(Path('AGENTS.md').read_bytes());core();closing(p)
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'CLAUDE import changed'
elif case.startswith('refused-'):
 old=PREFIX+variant(HISTORICAL_BARE,local)+SUFFIX;write('AGENTS.md',old,0o751)
 write('.shipcraft','blocked70\r\n');write('CLAUDE.md',b'custom claude70\r\n')
 before={str(x):snapshot(x) for x in root.iterdir() if x.name!='.git'}
 p=init(ok=False);assert p.returncode==2 and '.shipcraft' in text(p),'did not reach later core failure'
 assert before=={str(x):snapshot(x) for x in root.iterdir() if x.name!='.git'},'refused init changed onboarding/briefs'
 assert 'ready. Commit' not in text(p)
else:
 # Seed current core/briefs through public init, so later failures isolate the upgrade.
 init()
 try:import tomllib
 except ImportError:import tomli as tomllib
 version=tomllib.loads((Path(acceptance).parent/'nucleo/Cargo.toml').read_text())['package']['version']
 for name,body in BRIEF_BODIES[local].items():
  assert Path('.shipcraft/briefs',name).read_bytes()==body+('<!-- written by shipcraft '+version+' -->\n').encode(),'item 70 changed brief body or running-version stamp'
 briefs=snapshot('.shipcraft/briefs')
 oldlocal=case.startswith('upgrade-local-') or (local and not case.startswith('upgrade-bare-'))
 old=PREFIX+variant(HISTORICAL_BARE,oldlocal)+SUFFIX
 if case.startswith('edited-'):
  old=old.replace(b'TDD',b'EDITED70',1)
  # A version change must preserve the previous release's unedited briefs with its notice.
  for name,body in BRIEF_BODIES[local].items():write(Path('.shipcraft/briefs')/name,body+b'<!-- written by shipcraft 2.25.0 -->\n',0o444)
  briefs=snapshot('.shipcraft/briefs')
 write('AGENTS.md',old,0o751);write('CLAUDE.md',IMPORT)
 if case.startswith('upgrade-brief-fails-'):
  shutil.rmtree('.shipcraft/briefs');write('.shipcraft/briefs',b'blocked briefs70\r\n')
 elif case.startswith('write-fails-'):Path('AGENTS.md').chmod(0o444)
 preexec=None
 if case.startswith('write-partial-'):
  import resource,signal
  limit=len(old)+8
  assert limit<len(PREFIX+ns['expected_block'](local)+SUFFIX),'size fixture does not discriminate new write'
  def preexec():
   signal.signal(signal.SIGXFSZ,signal.SIG_IGN);resource.setrlimit(resource.RLIMIT_FSIZE,(limit,limit))
 try:p=init(preexec_fn=preexec)
 finally:
  if case.startswith('write-fails-'):
   kept_mode=stat.S_IMODE(Path('AGENTS.md').stat().st_mode);Path('AGENTS.md').chmod(0o751)
   assert kept_mode==0o444,'read-only AGENTS mode changed'
 core();assert Path('CLAUDE.md').read_bytes()==IMPORT,'upgrade/failure modified CLAUDE import'
 if case.startswith(('edited-','write-fails-','write-partial-')):
  assert Path('AGENTS.md').read_bytes()==old,'kept/failed upgrade damaged old block'
  assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'kept block mode changed'
  if case.startswith('edited-'):
   assert "; it differs from this version's: edit it by hand to match docs/spec.md" in text(p),'edited block not reported'
   for name in BRIEF_BODIES[local]:
    notice="shipcraft: .shipcraft/briefs/"+name+" differs from this version's, kept: compare it with docs/spec.md"
    assert (notice in text(p))==(version!='2.25.0'),'old brief version comparison/notice changed'
  else:assert 'AGENTS.md' in text(p) and 'could not write' in text(p),'missing AGENTS write failure notice'
  assert "shipcraft: CLAUDE.md not written: AGENTS.md does not hold this version's shipcraft block" in text(p),'ineligible import guard missing'
  assert sorted(x.name for x in root.iterdir())==sorted(['.git','.shipcraft','.shipcraft.toml','AGENTS.md','CLAUDE.md','requirements.txt']+(['node_modules'] if local else [])),'temporary rewrite file leaked'
  closing(p,agents=False,briefs=False)
 else:
  actual=Path('AGENTS.md').read_bytes()
  assert actual==PREFIX+ns['expected_block'](local)+SUFFIX,'v2.25.0 known block not upgraded with exact surrounding bytes'
  exact_block(actual[len(PREFIX):-len(SUFFIX)])
  assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'upgrade changed mode'
  closing(p,briefs=False)
 if case.startswith('upgrade-brief-fails-'):
  assert Path('.shipcraft/briefs').read_bytes()==b'blocked briefs70\r\n','later brief failure changed blocker'
  assert any(l.startswith('shipcraft: .shipcraft/briefs not written: ') for l in text(p).splitlines()),'missing later folder failure notice'
 else:assert snapshot('.shipcraft/briefs')==briefs,'block upgrade changed brief bodies/stamps/modes'
PY70
  pass
}
