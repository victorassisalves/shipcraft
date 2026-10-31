# Item 69: hints through the public binary; all fixtures live in the case CW.
item69_langs() { echo core; }
item69_cases() {
  local c e
  for e in version noargs help h longhelp; do
    echo "v1-69.machine-$e"; echo "v1-69.machine-nested-$e"
  done
  for c in local pnpm pnpm-store pnpm-no-path lock-symlink lock-dangling lock-directory lock-absent pnpm-noexec nested launcher-absent launcher-noexec launcher-directory prefix canonical config config-local outside git-fails git-empty git-newline root-newline root-cr invalid invalid-local; do echo "v1-69.$c"; done
}
item69_case() {
  EXPECT="item 69: ${CASE#v1-69.}"
  v1_start codex
  must_accept 'item 69 hint contract' cmd "$PY" - "${CASE#v1-69.}" "$(command -v shipcraft)" "$CW" "$ACEITE/../nucleo/Cargo.toml" <<'PY69'
import os,re,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw,manifest=sys.argv[1:]; binary=str(Path(binary).resolve()); cw=Path(cw).resolve()/'fixtures69';cw.mkdir()
errors=[]
def want(value,message):
 if not value: errors.append(message)
def write(p,data,mode=None):
 p=Path(p); p.parent.mkdir(parents=True,exist_ok=True); p.write_bytes(data if isinstance(data,bytes) else data.encode())
 if mode is not None:p.chmod(mode)
def run(call,args,cwd,env,merged=False):
 p=subprocess.run([str(call),*args],cwd=cwd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT if merged else subprocess.PIPE,timeout=30)
 print(repr((str(call),args,str(cwd))), 'rc=',p.returncode,'stdout=',repr(p.stdout),'stderr=',repr(p.stderr),flush=True)
 return p
def snapshot():
 result={}
 for p in cw.rglob('*'):
  s=p.lstat(); kind=stat.S_IFMT(s.st_mode)
  result[str(p.relative_to(cw))]=(kind,stat.S_IMODE(s.st_mode),os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None)
 return result
root=cw/'project69';root.mkdir(); subprocess.run(['git','init','-q',str(root)],check=True)
outside=cw/'outside69';outside.mkdir()
# A minimal PATH makes presence/absence independent of the host; no npx/node is needed.
tools=cw/'tools69';tools.mkdir();realgit=shutil.which('git');(tools/'git').symlink_to(realgit)
env=dict(os.environ,PATH=str(tools),GIT_CEILING_DIRECTORIES=str(cw))
baseline_tools=cw/'baseline-tools69';baseline_tools.mkdir();(baseline_tools/'git').symlink_to(realgit)
baseline_env=dict(env,PATH=str(baseline_tools))
entries={'version':['--version'],'noargs':[],'help':['help'],'h':['-h'],'longhelp':['--help']}
old=b'shipcraft: not set up in this repository:'
prefix=b'shipcraft: next step (required):'
def hint(command):return ('shipcraft: next step (required): run `'+command+'` at the repository root to set up Shipcraft; until init runs, Shipcraft checks none of your commits; if init refuses, follow its Next line\n').encode()
version=re.search(r'(?m)^version = "([^"]+)"',Path(manifest).read_text()).group(1)
def check(call,args,cwd,command,invalid=False):
 baseline=run(binary,args,outside,baseline_env);before=snapshot()
 p=run(call,args,cwd,env);combined=run(call,args,cwd,env,True)
 want(snapshot()==before,'entry point wrote/changed a fixture file or folder (including run log)')
 want((p.stdout,p.returncode)==(baseline.stdout,baseline.returncode),'usual stdout/exit changed')
 want(p.returncode==(2 if invalid else 0),'wrong exit code')
 if invalid:
  want(b'shipcraft: error: invalid arguments: ' in p.stdout+p.stderr,'missing invalid-arguments diagnostic')
  want(b'usage:' in (p.stdout+p.stderr).lower(),'invalid arguments lost usage')
 elif args==['--version']:
  want(re.fullmatch(rb'shipcraft '+re.escape(version.encode())+rb' \([0-9a-f]{12}\)\n',p.stdout) is not None,'version line changed')
 else:want(b'usage:' in p.stdout.lower(),'usual usage missing from stdout')
 expected=baseline.stderr+(hint(command) if command else b'')
 want(p.stderr==expected,'inexact stderr: expected '+repr(expected)+' got '+repr(p.stderr))
 if command:
  want(p.stderr.count(b'`')==2 and len(p.stderr.splitlines())==1,'hint must be one line with exactly one backtick pair')
  want(combined.stdout==p.stdout+p.stderr,'hint must follow usual stdout in merged stream')
 else:
  want(old not in p.stdout+p.stderr and prefix not in p.stdout+p.stderr,'suppressed entry point printed old/new hint')
 want(combined.returncode==p.returncode,'merged stream changed status')
# Seed existing state too: a hint must never append to the log or touch a hook.
write(root/'.git/shipcraft/runs.jsonl',b'preserve69\r\n');write(root/'.git/hooks/sentinel69',b'keep69\0')
call=Path(binary);cwd=root;command='shipcraft init'
local_cases={'local','pnpm','pnpm-store','pnpm-no-path','lock-symlink','lock-dangling','lock-directory','lock-absent','pnpm-noexec','nested','launcher-absent','launcher-noexec','launcher-directory','prefix','canonical','config-local','invalid-local'}
if case in local_cases:
 location='packages/x/node_modules' if case=='nested' else 'node_modules-other' if case=='prefix' else 'node_modules'
 sub='.pnpm/shipcraft@fixture/node_modules/shipcraft/bin/shipcraft' if case=='pnpm-store' else 'shipcraft-fixture/bin/shipcraft'
 call=root/location/sub;call.parent.mkdir(parents=True);shutil.copy2(binary,call)
 launcher=root/'node_modules/.bin/shipcraft';launcher.parent.mkdir(parents=True,exist_ok=True);launcher.symlink_to(call)
 command='npx -- shipcraft init'
 if case in ('nested','prefix','launcher-absent','launcher-noexec','launcher-directory'):command='shipcraft init'
 if case=='launcher-absent':launcher.unlink()
 if case=='launcher-noexec':launcher.unlink();write(launcher,'#!/bin/sh\nexit 0\n',0o644)
 if case=='launcher-directory':launcher.unlink();launcher.mkdir()
 # The pnpm stub would leave evidence and fail if executed: lookup alone is allowed.
 if case!='pnpm-no-path':write(tools/'pnpm','#!'+sys.executable+'\nfrom pathlib import Path\nPath('+repr(str(cw/'pnpm-ran'))+').write_text("ran")\nraise SystemExit(79)\n',0o644 if case=='pnpm-noexec' else 0o755)
 lock=root/'pnpm-lock.yaml'
 if case=='lock-directory':lock.mkdir()
 elif case in ('lock-symlink','lock-dangling'):
  if case=='lock-symlink':write(root/'real-lock69',b'not parsed\x00\xff')
  lock.symlink_to('real-lock69' if case=='lock-symlink' else 'missing69')
 elif case not in ('local','lock-absent'):write(lock,b'not YAML: \x00\xff\n')
 if case in ('pnpm','pnpm-store','canonical','config-local','invalid-local'):command='pnpm exec shipcraft init'
 if case=='canonical':
  alias=cw/'alias69';alias.symlink_to(root,target_is_directory=True);cwd=alias/'nested69';cwd.mkdir();call=alias/call.relative_to(root)
if case.startswith('machine-'):
 entry=case.removeprefix('machine-').removeprefix('nested-')
 if case.startswith('machine-nested-'):cwd=root/'packages/x/deep69';cwd.mkdir(parents=True)
 check(call,entries[entry],cwd,command)
elif case in ('config','config-local'):
 for kind in ('regular','symlink','dangling','directory','fifo'):
  cfg=root/'.shipcraft.toml'
  if kind=='regular':write(cfg,b'not TOML \x00\xff')
  elif kind=='directory':cfg.mkdir()
  elif kind=='fifo':os.mkfifo(cfg)
  else:cfg.symlink_to('pnpm-lock.yaml' if case=='config-local' and kind=='symlink' else '.git' if kind=='symlink' else 'missing-config69')
  nested=root/'nested69';nested.mkdir(exist_ok=True)
  for args in entries.values():check(call,args,nested,None)
  if kind=='directory':cfg.rmdir()
  else:cfg.unlink()
elif case in ('invalid','invalid-local'):
 for args in (['--bogus69'],['help','extra69'],['--version','extra69'],['init','--bogus69']):check(call,args,cwd,None,True)
elif case in ('outside','git-fails','git-empty','git-newline'):
 if case=='outside':cwd=outside
 else:
  (tools/'git').unlink()
  data=b'' if case=='git-empty' else b'\n'
  write(tools/'git','#!'+sys.executable+'\nimport sys\nsys.stdout.buffer.write('+repr(data)+')\nraise SystemExit('+('1' if case=='git-fails' else '0')+')\n',0o755)
 for args in entries.values():check(call,args,cwd,None)
elif case in ('root-newline','root-cr'):
 # Synthetic rev-parse output is raw Unix path bytes, not text to trim or decode as UTF-8.
 name={'root-newline':b'root69\n','root-cr':b'root69\r'}[case]
 raw=os.fsencode(cw)+b'/'+name;special=Path(os.fsdecode(raw));special.mkdir();cwd=special
 (tools/'git').unlink();write(tools/'git','#!'+sys.executable+'\nimport sys\nsys.stdout.buffer.write('+repr(raw+b'\n')+')\n',0o755)
 for args in entries.values():check(call,args,cwd,command)
 # Removing exactly one LF must find this config and suppress every hint too.
 write(special/'.shipcraft.toml',b'not TOML\xff')
 for args in entries.values():check(call,args,cwd,None)
else:
 for args in entries.values():check(call,args,cwd,command)
assert not errors,'\n'.join(errors)
PY69
  pass
}
