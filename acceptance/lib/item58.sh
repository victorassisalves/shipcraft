# Item 58: project-local install; all git commands stay in the case's project.
item58_langs() { echo node; }
item58_cases() {
  local c t
  for c in plain recognize recognize-absent cycle missing-commit missing-post symlink outside absent noexec directory nested prefix kept rollback; do echo "v1-58.$c"; done
  for t in lefthook husky pre; do
    for c in write recognize recognize-absent kept rollback; do echo "v1-58.$t.$c"; done
  done
}
item58_case() {
  EXPECT='item 58 project-local contract'
  v1_start codex
  if [ "$CASE" = v1-58.cycle ] || [ "$CASE" = v1-58.missing-commit ] || [ "$CASE" = v1-58.missing-post ]; then
    mkdir -p node_modules/shipcraft-fixture/bin node_modules/.bin
    cp "$(command -v shipcraft)" node_modules/shipcraft-fixture/bin/shipcraft
    ln -s ../shipcraft-fixture/bin/shipcraft node_modules/.bin/shipcraft
    must_accept 'local init' cmd node_modules/.bin/shipcraft init
    must_accept 'commit init' commit commit_all 'chore: init'
    L stub; L spec_test
    must_accept 'local RED' cmd node_modules/.bin/shipcraft red
    must_accept 'RED through commit-msg' commit commit_all 'test: RED'
    if [ "$CASE" = v1-58.cycle ]; then
      L implement
      must_accept 'GREEN through local hooks' commit commit_all 'feat: GREEN'
      chk 'closed through post-commit' one_lock_head_state closed
    else
      rm node_modules/.bin/shipcraft
      if [ "$CASE" = v1-58.missing-commit ]; then
        L implement; git add -A
        run_cmd git commit -qm 'feat: cannot commit without dependencies'
        chk 'missing dependency refuses with exit 1' eq "$RC" 1
        chk 'exact missing dependency line' grep -Fx "shipcraft: not installed in this checkout (node_modules/.bin/shipcraft): install the project's dependencies" "$OUT"
      else
        run_cmd .git/hooks/post-commit
        chk 'post-commit remains advisory' rc_zero
        chk 'exact open-lock guidance' grep -Fx "shipcraft: not installed in this checkout (node_modules/.bin/shipcraft): the lock stays open; install the project's dependencies and run node_modules/.bin/shipcraft close" "$OUT"
      fi
      chk 'lock remains open' one_lock_head_state open
    fi
    pass; return
  fi
  must_accept 'local install contract' cmd "$PY" - "${CASE#v1-58.}" <<'PY58'
import ast, os, shutil, subprocess, sys
from pathlib import Path
import yaml
sys.path.insert(0, str(Path(os.environ['ACEITE'])/'tools'))
from lefthook_fixture import HOOK
case=sys.argv[1]; tool, _, mode=case.partition('.')
if not mode: mode=tool; tool='plain'
root=Path.cwd().resolve(); machine=Path(shutil.which('shipcraft')).resolve()
def write(p,s,mode=None):
 p=Path(p); p.parent.mkdir(parents=True,exist_ok=True); p.write_text(s)
 if mode is not None: p.chmod(mode)
def run(*args,good=True):
 p=subprocess.run(args,capture_output=True,text=True,timeout=90); out=p.stdout+p.stderr
 print('$',*args,'[rc='+str(p.returncode)+']\n'+out,flush=True)
 if good: assert p.returncode==0, 'command failed: '+out
 return p,out
# Read only the known real-tool fixtures from the existing acceptance battery.
source=(Path(os.environ['ACEITE'])/'lib/item25.sh').read_text().split("<<'PY25'\n",1)[1].split('\nPY25',1)[0]
constants={}
for n in ast.parse(source).body:
 if isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Name) and n.targets[0].id in ('HUSKY_H','HUSKY_LAUNCHER','PRE_LAUNCHER','BASE_YAML'):
  constants[n.targets[0].id]=ast.literal_eval(n.value)
if tool=='lefthook':
 write('lefthook.yml','pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 for e in ('commit-msg','post-commit','pre-commit'): write('.git/hooks/'+e,HOOK.replace('run "pre-commit"','run "'+e+'"'),0o755)
elif tool=='husky':
 run('git','config','core.hooksPath','.husky/_'); write('.husky/_/h',constants['HUSKY_H'])
 for e in ('commit-msg','post-commit','pre-commit'): write('.husky/_/'+e,constants['HUSKY_LAUNCHER'],0o755)
 write('.husky/pre-commit','echo formatter\n')
elif tool=='pre':
 write('.pre-commit-config.yaml',constants['BASE_YAML'])
 for e in ('commit-msg','post-commit','pre-commit'): write('.git/hooks/'+e,constants['PRE_LAUNCHER'].replace('--hook-type=commit-msg','--hook-type='+e),0o755)
paths={'plain':['.git/hooks/commit-msg','.git/hooks/post-commit'],'lefthook':['lefthook.yml'],'husky':['.husky/commit-msg','.husky/post-commit'],'pre':['.pre-commit-config.yaml']}[tool]
notice="shipcraft: hooks call this project's install (node_modules/.bin/shipcraft); upgrade it with your package manager"
if mode=='kept': run(str(machine),'init')
prefix='packages/x/node_modules' if mode=='nested' else 'node_modules-other' if mode=='prefix' else 'node_modules'
binary=root/prefix/'shipcraft-fixture/bin/shipcraft'; binary.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(machine,binary)
launcher=root/'node_modules/.bin/shipcraft'; launcher.parent.mkdir(parents=True,exist_ok=True)
launcher.symlink_to(binary)
if mode=='absent': launcher.unlink()
if mode=='noexec': binary.chmod(0o644)
if mode=='directory': launcher.unlink(); launcher.mkdir()
call=machine if mode=='outside' else binary
if mode in ('plain','write','kept'): call=launcher
if mode=='noexec': call=binary; binary.chmod(0o755); launcher.unlink(); write(launcher,'#!/bin/sh\n',0o644)
if mode=='symlink':
 alias=root.parent/(root.name+'-alias58'); alias.symlink_to(root,target_is_directory=True); call=alias/launcher.relative_to(root); os.chdir(alias)
if mode.startswith('recognize'):
 run(str(machine),'init')
 for p in paths:
  f=Path(p); text=f.read_text()
  if tool=='plain':
   args='check --commit-msg "$1"' if p.endswith('commit-msg') else 'close'
   text='#!/bin/sh\n# shipcraft hook\n"$(git rev-parse --show-toplevel)/node_modules/.bin/shipcraft" '+args+'\n'
  elif tool=='lefthook': text=text.replace('run: shipcraft ', 'run: ./node_modules/.bin/shipcraft ')
  elif tool=='pre': text=text.replace('entry: shipcraft ', 'entry: ./node_modules/.bin/shipcraft ')
  else: text=text.replace('shipcraft check','./node_modules/.bin/shipcraft check').replace('shipcraft close','./node_modules/.bin/shipcraft close')
  f.write_text(text)
 if mode=='recognize-absent': launcher.unlink()
 before={p:Path(p).read_bytes() for p in paths}
 _,out=run(str(machine),'status')
 label={'plain':'shipcraft hooks installed (commit-msg and post-commit)','lefthook':'hook through lefthook (commit-msg)','husky':'hook through husky (commit-msg)','pre':'hook through pre-commit (commit-msg)'}[tool]
 assert label in out.lower(), 'local integration not recognized by status'
 _,out=run(str(call),'init'); assert notice not in out
 assert before=={p:Path(p).read_bytes() for p in paths}, 'reinit changed local integration'
 sys.exit()
if mode=='rollback':
 run(str(machine),'init')
 for p in paths: Path(p).unlink(missing_ok=True)
 # Tool source must remain valid while the later locks-directory creation fails.
 if tool=='lefthook': write('lefthook.yml','pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 if tool=='pre': write('.pre-commit-config.yaml',constants['BASE_YAML'])
 shutil.rmtree('.shipcraft'); write('.shipcraft','blocked\r\n')
before={p:Path(p).read_bytes() if Path(p).exists() else None for p in paths}
p,out=run(str(call),'init',good=mode!='rollback')
if mode=='rollback':
 assert p.returncode!=0, 'expected later write failure'
 assert before=={p:Path(p).read_bytes() if Path(p).exists() else None for p in paths}, 'failed init retained integration writes'
 assert notice not in out, 'failed init announced local hooks'
 assert Path('.shipcraft').read_bytes()==b'blocked\r\n'
elif mode=='kept':
 assert before=={p:Path(p).read_bytes() for p in paths}, 'existing integration changed'
 assert notice not in out
elif mode in ('outside','absent','noexec','directory','nested','prefix'):
 assert notice not in out, 'false local install detection'
 text='\n'.join(Path(p).read_text() for p in paths)
 assert str(call) in text, 'machine wiring no longer names running binary'
 if mode=='nested':
  assert f"shipcraft: installed under {root}/packages/x/node_modules; hooks call this binary by its path (only the root node_modules is wired as the project's)" in out.splitlines(), 'missing nested install guidance'
 else: assert 'only the root node_modules' not in out
else:
 text='\n'.join(Path(p).read_text() for p in paths)
 if tool=='plain':
  for event,args in [('commit-msg','check --commit-msg "$1"'),('post-commit','close')]:
   text=Path('.git/hooks/'+event).read_text()
   assert '# shipcraft hook' in text
   assert '"$(git rev-parse --show-toplevel)/node_modules/.bin/shipcraft" '+args in text, 'hook does not call checkout launcher'
 else:
  assert './node_modules/.bin/shipcraft check --commit-msg' in text, 'missing local check command'
  assert './node_modules/.bin/shipcraft close' in text, 'missing local close command'
 lines=out.splitlines(); assert lines.count(notice)==1, 'missing/duplicate local install notice'
 assert lines.index(notice)<next(i for i,l in enumerate(lines) if l.startswith('shipcraft: ready. Commit ')), 'notice follows closing guidance'
 stable={p:Path(p).read_bytes() for p in paths}
 _,out=run(str(call),'init'); assert notice not in out
 assert stable=={p:Path(p).read_bytes() for p in paths}
PY58
  pass
}
