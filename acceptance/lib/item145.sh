# Item 145: public CLI/output interface only; frozen acceptance fixtures, no implementation reads.
item145_langs() { echo core; }
item145_cases() {
  local c
  for c in repro block-bare block-local upgrade-bare upgrade-local status-upgrade export142 red-bare red-local green-bare green-local absent-red absent-green absent-both-off configured-control old-red old-green edited-block docs equal-control late-brief late-agents late-status; do echo "v1-145.$c"; done
}
item145_case() {
  EXPECT="item 145: ${CASE#v1-145.}"
  v1_start codex
  must_accept 'item 145 guidance interface' cmd "$PY" - "${CASE#v1-145.}" "$(command -v shipcraft)" "$CW" "$ACEITE" <<'PY145'
import ast,json,os,re,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw,acceptance=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw);acceptance=Path(acceptance)
def load(item,marker,names,functions=(),initial=None):
 source=(acceptance/'lib'/item).read_text().split("<<'"+marker+"'\n",1)[1].split('\n'+marker,1)[0];ns={} if initial is None else dict(initial)
 for node in ast.parse(source).body:
  if isinstance(node,ast.Assign) and all(isinstance(t,ast.Name) and t.id in names for t in node.targets):exec(compile(ast.Module(body=[node],type_ignores=[]),item,'exec'),ns)
  elif isinstance(node,ast.FunctionDef) and node.name in functions:exec(compile(ast.Module(body=[node],type_ignores=[]),item,'exec'),ns)
 return ns
f85=load('item85.sh','PY85',{'OLD84','ROOT_LINE','CLEANUP','NEW'},{'variant'})
f142=load('item142.sh','PY142',{'NEW_LINE','PIN'},initial={'f85':f85})
f84=load('item84.sh','PY84',{'HISTORICAL_BRIEFS','GREEN_LINE','OLD_GREEN_LINE'})
BLOCK_LINE=b"- Before starting either phase, the session the user talks to fixes the interface the tests call (what they call to reach the behavior: names, arguments, results, and the errors, exit codes or messages they check; for a command line, its commands, flags and output) and writes it in every prompt that starts a phase, a command given to the user included. The RED's tests and stubs use that interface; the GREEN never changes it (the code behind it is free), and a GREEN that finds it wrong stops and reports it as a wrong test: the repair above, with the corrected interface in the new RED's prompt and the GREEN's, through `shipcraft red --redo` and its limits.\n"
RED_LINE=b'- The tests call the interface your prompt fixes (names, arguments, results, and the errors, exit codes or messages they check), and the stubs have it. What the prompt leaves out, choose, list with the ambiguities and name in your report, so the GREEN gets it; where the prompt contradicts the intent or the existing tests, stop and report it before `shipcraft red`.\n'
GREEN_INTERFACE=b'- Never change the interface the locked tests call (names, arguments, results, and the errors, exit codes or messages they check); the code behind it is yours. If it looks wrong, stop and report it as a wrong test.\n'
CURRENT=f142['PIN'].replace(b'- Start each phase with the agent, model and effort',BLOCK_LINE+b'- Start each phase with the agent, model and effort',1)
# Item159: CURRENT stays the frozen 2.94.0 fixture; only new output changes.
TARGET=CURRENT.replace(b'- Start each phase with the agent, model and effort',b"- If the repair renames or drops a case, or changes a stub, and no GREEN commit exists after the RED (only redo commits and commits that change only Markdown files), the new RED session runs `shipcraft red --replace --reason '<why>'` instead of `shipcraft red --redo` (also in the steps given to the user, with both lock paths it prints in `git add`), commits both locks with the tests and stubs in one commit, and puts the line it prints in the commit body; this takes precedence over the repair above. After a GREEN commit, `--replace` refuses: repair with `--redo` or open the new RED on a new branch.\n"+b'- Start each phase with the agent, model and effort',1)
REDA=b'- Commit the tests, their stubs and the lock in one commit, and stop.\n'
GREENA=b'- Never edit a locked file or a lock (`.shipcraft/locks/*`).\n'
UNSET='not set (the session that starts the RED and GREEN chooses)'
try:import tomllib
except ImportError:import tomli as tomllib
version=tomllib.loads((acceptance.parent/'nucleo/Cargo.toml').read_text())['package']['version']
STAMP=('<!-- written by shipcraft '+version+' -->\n').encode()
def put(path,data):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
def run(*args,env=None):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,env=env,timeout=90)
 print('$',repr(args),'rc',p.returncode,'\n'+(p.stdout+p.stderr).decode(errors='replace'),flush=True);return p
def ok(*args):
 p=run(*args);assert p.returncode==0,(p.stdout,p.stderr);return p.stdout
def init(call=binary):return run(call,'init','--lang','other','--command','sh tests/a.sh {junit}','--glob','tests/*.sh')
def local_call():
 target=Path('node_modules/shipcraft-fixture/bin/shipcraft');target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(binary,target)
 launcher=Path('node_modules/.bin/shipcraft');launcher.parent.mkdir(parents=True,exist_ok=True);launcher.symlink_to(target.resolve());return launcher.resolve()
def config(roles='',review='local'):
 put('.shipcraft.toml','shipcraft_min="2.20"\ntest_command="sh tests/a.sh {junit}"\ntest_globs=["tests/*.sh"]\n[execution]\nci="off"\nreview="'+review+'"\n[roles]\nreview="codex"\n'+roles)
def snapshot():return ok('git','status','--porcelain=v1','--untracked-files=all'),ok('git','diff','--binary'),{str(p):p.read_bytes() for p in Path('.shipcraft').rglob('*') if p.is_file()}
def status():
 trace=cw/'gh145.calls';trace.unlink(missing_ok=True);before=snapshot()
 p=run(binary,'status',env=dict(os.environ,PATH=str(cw/'tools145')+os.pathsep+os.environ['PATH']))
 assert snapshot()==before,'status changed repository'
 return p,([json.loads(l) for l in trace.read_text().splitlines()] if trace.exists() else [])
root=cw/"project145 space 'quote";root.mkdir();os.chdir(root)
ok('git','init','-q','-b','main');ok('git','config','user.name','Fixture145');ok('git','config','user.email','fixture@example.invalid')
put('tests/a.sh','printf \'<testsuites><testsuite><testcase classname="tests/a.sh" name="ok"/></testsuite></testsuites>\' > "$1"\n')
ok('git','add','tests/a.sh');ok('git','commit','-qm','fixture145')
put(cw/'tools145/gh','#!'+sys.executable+'\nimport json,sys\nwith open('+repr(str(cw/'gh145.calls'))+',"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nprint("gh: unavailable145",file=sys.stderr)\nsys.exit(1)\n');(cw/'tools145/gh').chmod(0o755)
if case=='repro':
 p=init();assert p.returncode==0;config();s,calls=status()
 observed=(BLOCK_LINE in Path('AGENTS.md').read_bytes(),[l for l in s.stdout.decode().splitlines() if l.startswith('shipcraft: roles:')])
 assert observed==(True,['shipcraft: roles: red '+UNSET+'; green '+UNSET+'; review codex']),observed
 assert s.returncode==0 and calls==[['api','repos/{owner}/{repo}/branches/main/protection']]
elif case=='block-bare':
 p=init();assert p.returncode==0
 assert Path('AGENTS.md').read_bytes()==TARGET,'machine block line/order/other bytes'
elif case=='block-local':
 p=init(local_call());assert p.returncode==0
 assert Path('AGENTS.md').read_bytes()==f85['variant'](TARGET,True),'local block line/order/command rewriting'
elif case=='upgrade-bare':
 put('AGENTS.md',b'prefix145\r\n\x00\n'+f142['PIN']+b'suffix145 no LF');Path('AGENTS.md').chmod(0o751)
 p=init();assert p.returncode==0
 assert Path('AGENTS.md').read_bytes()==b'prefix145\r\n\x00\n'+TARGET+b'suffix145 no LF','item142 machine upgrade'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
 assert b'it differs from this version' not in p.stdout+p.stderr
elif case=='upgrade-local':
 put('AGENTS.md',b'prefix145\r\n\x00\n'+f85['variant'](f142['PIN'],True)+b'suffix145 no LF');Path('AGENTS.md').chmod(0o751)
 p=init(local_call());assert p.returncode==0
 assert Path('AGENTS.md').read_bytes()==b'prefix145\r\n\x00\n'+f85['variant'](TARGET,True)+b'suffix145 no LF','item142 local upgrade'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
elif case=='status-upgrade':
 assert init().returncode==0;config('red="codex"\ngreen="claude"\n')
 for local in (False,True):
  put('AGENTS.md',f85['variant'](f142['PIN'],local));p,calls=status()
  assert b'shipcraft: AGENTS.md block: from an earlier version; run `shipcraft init` to update it\n' in p.stdout,'item142 must become earlier'
  assert p.returncode==0 and calls==[['api','repos/{owner}/{repo}/branches/main/protection']]
  assert init().returncode==0;p,calls=status();assert b'shipcraft: AGENTS.md block: current\n' in p.stdout
elif case=='export142':
 # Both the newly historical and the new current forms must export contributor text.
 base=ok('git','rev-parse','HEAD').strip().decode();assert init().returncode==0
 for block,local,branch in ((f142['PIN'],False,'bare145'),(f142['PIN'],True,'local145'),(CURRENT,False,'new-bare145'),(CURRENT,True,'new-local145')):
  put('AGENTS.md',b'own145\n\n'+f85['variant'](block,local)+b'tail145\n');ok('git','add','AGENTS.md');ok('git','commit','-qm','contributor145')
  before=snapshot();p=run(binary,'export','--base',base,branch)
  assert p.returncode==0 and ok('git','show',branch+':AGENTS.md')==b'own145\n\ntail145\n'
  assert snapshot()==before and b'kept as in' not in p.stdout
elif case=='red-bare':
 assert init().returncode==0
 expected=f84['HISTORICAL_BRIEFS'][False]['red.md'].replace(REDA,RED_LINE+REDA)+STAMP
 assert Path('.shipcraft/briefs/red.md').read_bytes()==expected,'RED exact line/place/body/stamp'
elif case=='red-local':
 assert init(local_call()).returncode==0
 expected=f84['HISTORICAL_BRIEFS'][True]['red.md'].replace(REDA,RED_LINE.replace(b'`shipcraft ',b'`npx -- shipcraft ')+REDA)+STAMP
 assert Path('.shipcraft/briefs/red.md').read_bytes()==expected,'local RED exact body/stamp'
elif case=='green-bare':
 assert init().returncode==0
 expected=f84['HISTORICAL_BRIEFS'][False]['green.md'].replace(f84['OLD_GREEN_LINE'],f84['GREEN_LINE']).replace(GREENA,GREENA+GREEN_INTERFACE)+STAMP
 assert Path('.shipcraft/briefs/green.md').read_bytes()==expected,'GREEN exact line/place/body/stamp'
elif case=='green-local':
 assert init(local_call()).returncode==0
 expected=f84['HISTORICAL_BRIEFS'][True]['green.md'].replace(f84['OLD_GREEN_LINE'],f84['GREEN_LINE']).replace(GREENA,GREENA+GREEN_INTERFACE)+STAMP
 assert Path('.shipcraft/briefs/green.md').read_bytes()==expected,'local GREEN exact body/stamp'
elif case=='absent-red':
 assert init().returncode==0
 for review in ('local','off'):
  config('green={agent="claude",model="orchestrator",effort="max"}\n',review);p,calls=status()
  expected='shipcraft: roles: red '+UNSET+'; green claude (orchestrator, effort max); review '+('codex' if review=='local' else 'off')
  lines=p.stdout.decode().splitlines();assert lines.count(expected)==1,(expected,lines)
  assert lines[lines.index(expected)-1].startswith('shipcraft: layers:') and p.returncode==0
  assert calls==[['api','repos/{owner}/{repo}/branches/main/protection']]
elif case=='absent-green':
 assert init().returncode==0
 for review in ('local','off'):
  config('red={agent="codex",model="orchestrator",effort="high"}\n',review);p,calls=status()
  expected='shipcraft: roles: red codex (orchestrator, effort high); green '+UNSET+'; review '+('codex' if review=='local' else 'off')
  assert p.returncode==0 and expected in p.stdout.decode().splitlines(),p.stdout
  assert calls==[['api','repos/{owner}/{repo}/branches/main/protection']]
elif case=='absent-both-off':
 assert init().returncode==0
 for review in ('off','local'):
  config(review=review);p,calls=status()
  expected='shipcraft: roles: red '+UNSET+'; green '+UNSET+'; review '+('off' if review=='off' else 'codex')
  assert p.returncode==0 and expected in p.stdout.decode().splitlines(),p.stdout
  assert calls==[['api','repos/{owner}/{repo}/branches/main/protection']]
elif case=='configured-control':
 assert init().returncode==0
 for review in ('off','local'):
  config('red={agent="codex",model="orchestrator",effort="high"}\ngreen={agent="claude",effort="max"}\n',review);p,calls=status()
  assert p.returncode==0 and 'shipcraft: roles: red codex (orchestrator, effort high); green claude (effort max); review '+('off' if review=='off' else 'codex') in p.stdout.decode().splitlines()
  assert calls==[['api','repos/{owner}/{repo}/branches/main/protection']]
  assert p.stdout.decode().splitlines()[-1]=='shipcraft: could not read branch protection (gh: unavailable145): use `shipcraft merge` as the gate'
elif case=='old-red':
 assert init().returncode==0
 for local in (False,True):
  old=f84['HISTORICAL_BRIEFS'][local]['red.md']+b'<!-- written by shipcraft 2.83.0 -->\n';put('.shipcraft/briefs/red.md',old)
  p=init();assert p.returncode==0 and Path('.shipcraft/briefs/red.md').read_bytes()==old
  assert b"shipcraft: .shipcraft/briefs/red.md differs from this version's, kept: compare it with docs/spec.md" in p.stdout+p.stderr
  Path('.shipcraft/briefs/red.md').unlink();assert init().returncode==0
  assert Path('.shipcraft/briefs/red.md').read_bytes()==f84['HISTORICAL_BRIEFS'][False]['red.md'].replace(REDA,RED_LINE+REDA)+STAMP,'deleted old RED must be regenerated'
elif case=='old-green':
 assert init().returncode==0
 for local in (False,True):
  body=f84['HISTORICAL_BRIEFS'][local]['green.md'].replace(f84['OLD_GREEN_LINE'],f84['GREEN_LINE']);old=body+b'<!-- written by shipcraft 2.83.0 -->\n';put('.shipcraft/briefs/green.md',old)
  p=init();assert p.returncode==0 and Path('.shipcraft/briefs/green.md').read_bytes()==old
  assert b"shipcraft: .shipcraft/briefs/green.md differs from this version's, kept: compare it with docs/spec.md" in p.stdout+p.stderr
  Path('.shipcraft/briefs/green.md').unlink();assert init().returncode==0
  assert Path('.shipcraft/briefs/green.md').read_bytes()==body.replace(GREENA,GREENA+GREEN_INTERFACE)+STAMP,'deleted old GREEN must be regenerated'
elif case=='edited-block':
 edited=f142['PIN'].replace(b'TDD with',b'CUSTOM145 with');put('AGENTS.md',edited);p=init()
 assert p.returncode==0 and Path('AGENTS.md').read_bytes()==edited
 assert b'it differs from this version' in p.stdout+p.stderr
 config();p,calls=status();assert b"AGENTS.md block: differs from this version's; init keeps it" in p.stdout
 # Owner merges only the new line; this remains an edited block and is kept.
 merged=edited.replace(b'- Start each phase with the agent, model and effort',BLOCK_LINE+b'- Start each phase with the agent, model and effort');put('AGENTS.md',merged)
 p=init();assert p.returncode==0 and Path('AGENTS.md').read_bytes()==merged
 Path('AGENTS.md').unlink();assert init().returncode==0
 assert Path('AGENTS.md').read_bytes()==TARGET,'fresh replacement must carry interface rule'
elif case=='docs':
 text=(acceptance.parent/'docs/spec.md').read_text();s4=text.split('## 4.',1)[1].split('## 5.',1)[0];s10=text.split('## 10.',1)[1].split('## 11.',1)[0]
 assert 'The agent (string or table, as `review`) the session that starts the RED and GREEN uses for each phase' in s4
 assert 'sessions that the session the user talks to starts' in s4 and 'absent means that session chooses' in s4
 assert 'That session reads the roles from `shipcraft status`' in s4 and 'telling the session the user talks to to start each phase' in s4
 assert 'the session the user talks to starts them, `[roles] red` and `green` only record its choice (item 64)' in s10
 assert init().returncode==0;config();p,calls=status()
 assert all(b"the orchestrator's choice" not in data for data in (p.stdout,p.stderr,Path('AGENTS.md').read_bytes(),Path('.shipcraft/briefs/red.md').read_bytes(),Path('.shipcraft/briefs/green.md').read_bytes())),'old placeholder still emitted'
elif case=='equal-control':
 # Dynamic current block proves the equality path on either binary, in both forms.
 for local in (False,True):
  call=local_call() if local else binary;p=init(call);assert p.returncode==0
  current=Path('AGENTS.md').read_bytes();assert f85['variant'](f142['PIN'],local).splitlines()[0] in current
  # Change variants through init, then exercise exact equality with surrounding bytes/mode.
  put('AGENTS.md',b'prefix-control145\n'+current+b'suffix-control145');Path('AGENTS.md').chmod(0o751)
  before=Path('AGENTS.md').read_bytes();briefs={name:Path('.shipcraft/briefs',name).read_bytes() for name in ('red.md','green.md')};p=init(call)
  assert p.returncode==0 and Path('AGENTS.md').read_bytes()==before and stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751
  assert b'already has the shipcraft block, kept' in p.stdout+p.stderr and b'it differs from this version' not in p.stdout+p.stderr
  assert all(Path('.shipcraft/briefs',name).read_bytes()==body for name,body in briefs.items())
  assert b'differs from this version' not in p.stdout+p.stderr
  # Both fresh variants are exercised, rather than appending to a previous control.
  Path('AGENTS.md').unlink()
 base=ok('git','rev-parse','HEAD').strip().decode()
 put('AGENTS.md',b'export-control145\n\n'+f142['PIN']);ok('git','add','AGENTS.md');ok('git','commit','-qm','export fixture control145')
 p=run(binary,'export','--base',base,'control145')
 assert p.returncode==0 and ok('git','show','control145:AGENTS.md')==b'export-control145\n'
elif case=='late-brief':
 put('.shipcraft/briefs','blocked-brief-folder145\n');p=init()
 assert p.returncode==0 and Path('.shipcraft/briefs').read_bytes()==b'blocked-brief-folder145\n'
 assert b'shipcraft: .shipcraft/briefs not written: ' in p.stdout+p.stderr
 assert Path('.shipcraft.toml').is_file() and Path('.shipcraft/locks/.gitkeep').is_file()
 assert Path('AGENTS.md').read_bytes()==TARGET,'later brief-folder failure must keep new block'
elif case=='late-agents':
 Path('CLAUDE.md').mkdir();put('CLAUDE.md/keep','keep145');p=init()
 assert p.returncode==0 and Path('CLAUDE.md/keep').read_bytes()==b'keep145'
 assert b'CLAUDE.md' in p.stdout+p.stderr and Path('.shipcraft.toml').is_file() and Path('.shipcraft/locks/.gitkeep').is_file()
 assert Path('AGENTS.md').read_bytes()==TARGET,'later CLAUDE failure must keep new block'
elif case=='late-status':
 assert init().returncode==0;config()
 # Real lock-directory read error, without inventing a lock or a run-log row.
 folder=Path('.shipcraft/locks');folder.chmod(0)
 try:p,calls=status()
 finally:folder.chmod(0o755)
 assert p.returncode==2 and calls==[] and b'shipcraft: error:' in p.stderr+p.stdout
 assert 'shipcraft: roles: red '+UNSET+'; green '+UNSET+'; review codex' in p.stdout.decode().splitlines(),'new role words survive later status error'
else:raise AssertionError('unrouted '+case)
PY145
  pass
}
