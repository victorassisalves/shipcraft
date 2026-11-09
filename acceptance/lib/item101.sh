# Item 101: status inspects custom Git hooks without executing or changing them.
item101_cases() {
  local c
  for c in real quotes mixed-call mixed-noncall unclosed trailing-slash bytes separators noncalls argument-boundaries missing noexec directory unreadable symlink dangling order raw absolute equivalent worktree later-format later-folder lookup-commit lookup-post config-fail control-unset control-literal control-git; do
    echo "v1-101.$c"
  done
}
item101_case() {
  EXPECT='item 101 custom hooks status contract'
  v1_start codex
  must_accept 'custom hooks contract' cmd "$PY" - "${CASE#v1-101.}" "$CW" <<'PY101'
import hashlib, json, os, shlex, shutil, stat, subprocess, sys
from pathlib import Path
case=sys.argv[1]; cw=Path(sys.argv[2]); binary=shutil.which('shipcraft'); realgit=shutil.which('git')
root=cw/'project101'; root.mkdir()
def run(*args, cwd=None, env=None):
 p=subprocess.run(list(map(str,args)),cwd=cwd or root,env=env,input=b'',capture_output=True,timeout=90)
 print('$',shlex.join(list(map(str,args))),'[rc='+str(p.returncode)+']\n'+(p.stdout+p.stderr).decode(errors='replace'),flush=True)
 return p
def ok(*args, **kw):
 p=run(*args,**kw); assert p.returncode==0,('fixture command',args,p.stdout,p.stderr); return p
def write(path,data,mode=0o755):
 path=Path(path)
 if path.name in ('commit-msg','post-commit'):
  data=b'touch '+shlex.quote(str(root/'ran-hook101')).encode()+b'\n'+data
 path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data);path.chmod(mode)
def snap(path):
 # Read denied files only for the snapshot, restoring permission before status.
 if path.is_symlink(): return ('link',os.readlink(path))
 s=path.stat(); mode=stat.S_IMODE(s.st_mode)
 if path.is_dir():
  path.chmod(mode|0o500)
  try: value={p.name:snap(p) for p in path.iterdir()}
  finally:path.chmod(mode)
  return (mode,value)
 if stat.S_ISREG(s.st_mode):
  path.chmod(mode|0o400)
  try: value=hashlib.sha256(path.read_bytes()).hexdigest()
  finally:path.chmod(mode)
  return (mode,value)
 return (mode,None)
def status(env=None,cwd=None):
 before=snap(root)
 p=run(binary,'status',env=env,cwd=cwd)
 assert snap(root)==before,'status wrote files, modes, hooks or run log, or ran project commands'
 return p
def hookline(p,expected,rc=0):
 lines=p.stdout.decode().splitlines()
 assert p.returncode==rc,('status exit',p.returncode,p.stdout,p.stderr)
 assert lines.count(expected)==1,('wrong hook line',expected,lines)
 i=lines.index(expected)
 assert lines[i-1].startswith('shipcraft: roles:') and lines[i+1]=='shipcraft: AGENTS.md block: current',('hook line order',lines)
 assert expected.encode() not in p.stderr,'hook line belongs on stdout'
def shim(kind):
 bindir=cw/'git101';bindir.mkdir(exist_ok=True);log=cw/'git101.calls';log.write_text('')
 script='#!/usr/bin/env python3\nimport os,sys\noriginal=sys.argv[1:];a=list(original)\nwhile a[:1]==["-C"]:a=a[2:]\nif a[:1]==["--literal-pathspecs"]:a=a[1:]\nif a==["config","--get","core.hooksPath"]:a=["config","core.hooksPath"]\n'
 script+='kind='+repr(kind)+'\n'
 script+='hit = (a == ["config", "core.hooksPath"] and kind in ("config-fail", "control-git")) or (a == ["rev-parse", "--git-path", "hooks/"+kind.removeprefix("lookup-")] and kind in ("lookup-commit-msg", "lookup-post-commit"))\n'
 script+='if hit:\n with open('+repr(str(log))+',"a") as f:f.write(" ".join(a)+"\\n")\n sys.exit(1 if kind=="control-git" else 23)\nos.execv('+repr(realgit)+', ['+repr(realgit)+']+original)\n'
 write(bindir/'git',script.encode()); env=os.environ.copy();env['PATH']=str(bindir)+os.pathsep+env['PATH']; return env,log
ok(realgit,'init','-q');write(root/'requirements.txt',b'pytest\n',0o644);ok(binary,'init')
# Keep today's remaining status output, but detect accidental execution of any project command.
write(root/'.shipcraft.toml',b'shipcraft_min="0.0"\ntest_command="touch ran101; exit 23 # {junit}"\ntest_globs=["tests/**"]\ncheck="touch checked101; exit 24"\n[build]\ncommand="touch built101; exit 25"\n[execution]\nci="off"\nreview="off"\n',0o644)
dir='scripts/hooks'; hooks=root/dir
commit=b'#!/bin/sh\nexec "$HOME/.local/shipcraft-2/bin/shipcraft" check --commit-msg "$1"\n'
post=b'#!/bin/sh\nexec "$HOME/.local/shipcraft-2/bin/shipcraft" close\n'
installed='shipcraft: shipcraft hooks installed (commit-msg and post-commit)'
if case=='control-unset':
 hookline(status(),installed)
elif case=='control-literal':
 ok(realgit,'config','core.hooksPath','.git/hooks');hookline(status(),installed)
elif case=='config-fail':
 ok(realgit,'config','core.hooksPath',dir);env,log=shim('config-fail')
 p=status(env);assert log.read_text()=='config core.hooksPath\n';hookline(p,'shipcraft: missing hook: the commit does not go through `shipcraft check`; run `shipcraft init`')
elif case=='control-git':
 ok(realgit,'config','core.hooksPath',dir);env,log=shim('control-git')
 p=status(env);assert log.read_text()=='config core.hooksPath\n';hookline(p,'shipcraft: missing hook: the commit does not go through `shipcraft check`; run `shipcraft init`')
else:
 if case=='raw':dir=" scripts/hooks space 'quoted' "
 elif case=='absolute':dir=str(root/'outside hooks')
 elif case=='equivalent':dir='./.git/hooks'
 elif case=='trailing-slash':dir='scripts/hooks/'
 hooks=root/dir;ok(realgit,'config','core.hooksPath',dir)
 write(hooks/'commit-msg',commit);write(hooks/'post-commit',post)
 # Poison fallback .git/hooks: scanning the wrong directory cannot satisfy custom hooks.
 if case!='equivalent':
  write(root/'.git/hooks/commit-msg',b'#!/bin/sh\necho unrelated\n')
  write(root/'.git/hooks/post-commit',b'#!/bin/sh\necho unrelated\n')
 good=f'shipcraft: hooks in core.hooksPath {dir} call shipcraft (commit-msg and post-commit)'
 prefix='shipcraft: missing hook: '; suffix='; add the shipcraft calls there (shipcraft init does not write under core.hooksPath)'
 if case=='real':
  hookline(status(),good)
 elif case=='quotes':
  for c,p in ((b"  exec\t'/a directory/shipcraft' check --commit-msg\t'$1'",b'\t/usr/local/bin/shipcraft close'),(b'shipcraft check --commit-msg',b"\t '/path with spaces/shipcraft'\tclose")):
   write(hooks/'commit-msg',c);write(hooks/'post-commit',p);hookline(status(),good)
 elif case=='mixed-call':
  for c,p in ((b'"$HOME"/bin/shipcraft check --commit-msg',b'"$HOME"/bin/shipcraft close'),(b"exec '/a directory'"+b'/bin/"ship"craft check --commit-msg',b"'/a directory'/bin/ship"+b'"craft" close')):
   write(hooks/'commit-msg',c);write(hooks/'post-commit',p);hookline(status(),good)
 elif case=='mixed-noncall':
  write(hooks/'commit-msg',b'"$HOME"/bin/shipcraft-old check --commit-msg')
  write(hooks/'post-commit',b'"$HOME"/bin/shipcraft-old close')
  hookline(status(),prefix+f'{dir}/commit-msg does not call shipcraft check --commit-msg, {dir}/post-commit does not call shipcraft close'+suffix)
 elif case=='unclosed':
  for quote in (b'"',b"'"):
   write(hooks/'commit-msg',b'/bin/'+quote+b'shipcraft check --commit-msg')
   write(hooks/'post-commit',b'/bin/'+quote+b'shipcraft close')
   hookline(status(),prefix+f'{dir}/commit-msg does not call shipcraft check --commit-msg, {dir}/post-commit does not call shipcraft close'+suffix)
 elif case=='trailing-slash':
  (hooks/'commit-msg').unlink();write(hooks/'post-commit',b'shipcraft closed')
  hookline(status(),prefix+'scripts/hooks/commit-msg is missing or not executable, scripts/hooks/post-commit does not call shipcraft close'+suffix)
  write(hooks/'commit-msg',commit);write(hooks/'post-commit',post);hookline(status(),good)
 elif case=='bytes':
  write(hooks/'commit-msg',b'#!/bin/sh\r\n# caf\xe9\r\n\texec "a/shipcraft" check --commit-msg\t"$1"\r\n')
  write(hooks/'post-commit',b'# Latin1 \xff\nshipcraft close\r');hookline(status(),good)
 elif case=='separators':
  for sep in (b'\r',b'\xe2\x80\xa8',b'\xe2\x80\xa9'):
   write(hooks/'commit-msg',b'# comment'+sep+b'shipcraft check --commit-msg')
   write(hooks/'post-commit',b'# comment'+sep+b'shipcraft close')
   hookline(status(),prefix+f'{dir}/commit-msg does not call shipcraft check --commit-msg, {dir}/post-commit does not call shipcraft close'+suffix)
  write(hooks/'commit-msg',b'\xef\xbb\xbfshipcraft check --commit-msg')
  write(hooks/'post-commit',b'\xef\xbb\xbfshipcraft close')
  hookline(status(),prefix+f'{dir}/commit-msg does not call shipcraft check --commit-msg, {dir}/post-commit does not call shipcraft close'+suffix)
 elif case=='noncalls':
  for c,p in ((b'# shipcraft check --commit-msg',b'# shipcraft close'),(b'echo shipcraft check --commit-msg',b'echo shipcraft close'),(b'shipcraft-old check --commit-msg',b'shipcraft-old close'),(b'execshipcraft check --commit-msg',b'execshipcraft close')):
   write(hooks/'commit-msg',c);write(hooks/'post-commit',p)
   hookline(status(),prefix+f'{dir}/commit-msg does not call shipcraft check --commit-msg, {dir}/post-commit does not call shipcraft close'+suffix)
 elif case=='argument-boundaries':
  for c,p in ((b'shipcraft check --commit-msg-extra',b'shipcraft closed'),(b'shipcraft check --commit-msg; echo x',b'shipcraft close; echo x'),(b'shipcraft check --commit-msgX',b'shipcraft\tcloseX')):
   write(hooks/'commit-msg',c);write(hooks/'post-commit',p)
   hookline(status(),prefix+f'{dir}/commit-msg does not call shipcraft check --commit-msg, {dir}/post-commit does not call shipcraft close'+suffix)
 elif case=='missing':
  (hooks/'commit-msg').unlink();hookline(status(),prefix+f'{dir}/commit-msg is missing or not executable'+suffix)
 elif case=='noexec':
  (hooks/'post-commit').chmod(0o644);hookline(status(),prefix+f'{dir}/post-commit is missing or not executable'+suffix)
 elif case=='directory':
  (hooks/'commit-msg').unlink();(hooks/'commit-msg').mkdir();hookline(status(),prefix+f'{dir}/commit-msg is missing or not executable'+suffix)
 elif case=='unreadable':
  (hooks/'post-commit').chmod(0o111)
  try:
   (hooks/'post-commit').read_bytes()
  except PermissionError:pass
  else:raise AssertionError('fixture requires actual read denial')
  hookline(status(),prefix+f'{dir}/post-commit is missing or not executable'+suffix)
 elif case=='symlink':
  for event in ('commit-msg','post-commit'):
   target=root/('target-'+event);(hooks/event).rename(target);(hooks/event).symlink_to(target)
  for bit in (0o100,0o010,0o001):
   for event in ('commit-msg','post-commit'):(root/('target-'+event)).chmod(0o644|bit)
   hookline(status(),good)
 elif case=='dangling':
  (hooks/'post-commit').unlink();(hooks/'post-commit').symlink_to('absent101');hookline(status(),prefix+f'{dir}/post-commit is missing or not executable'+suffix)
 elif case=='order':
  write(hooks/'commit-msg',b'echo shipcraft check --commit-msg\n');(hooks/'post-commit').chmod(0o644)
  hookline(status(),prefix+f'{dir}/commit-msg does not call shipcraft check --commit-msg, {dir}/post-commit is missing or not executable'+suffix)
  (hooks/'commit-msg').unlink();write(hooks/'post-commit',b'shipcraft closed\n')
  hookline(status(),prefix+f'{dir}/commit-msg is missing or not executable, {dir}/post-commit does not call shipcraft close'+suffix)
 elif case=='raw':
  hookline(status(),good)
 elif case=='absolute':
  hookline(status(),good)
 elif case=='equivalent':
  hookline(status(),good)
 elif case=='worktree':
  ok(realgit,'add','requirements.txt');ok(realgit,'-c','core.hooksPath=/dev/null','commit','-qm','fixture101')
  wt=cw/'linked101';ok(realgit,'worktree','add','-qb','linked101',wt)
  shutil.copy2(root/'.shipcraft.toml',wt/'.shipcraft.toml');shutil.copy2(root/'AGENTS.md',wt/'AGENTS.md')
  write(wt/dir/'commit-msg',commit);write(wt/dir/'post-commit',post)
  before=snap(wt);p=status(cwd=wt);assert snap(wt)==before,'status changed linked tree';hookline(p,good)
 elif case=='later-format':
  write(root/'.shipcraft/locks/future101.json',json.dumps(dict(format=999,state='open',files={},cases=[],failing_at_red=[],seal='')).encode(),0o644)
  p=status();hookline(p,good,1)
  assert b'format 999' in p.stdout+p.stderr,'later format refusal missing'
  (hooks/'commit-msg').unlink()
  p=status();hookline(p,prefix+f'{dir}/commit-msg is missing or not executable'+suffix,1)
  assert b'format 999' in p.stdout+p.stderr,'later format refusal missing'
 elif case=='later-folder':
  (root/'.shipcraft/locks').chmod(0)
  try:p=status();hookline(p,good,2);assert b'shipcraft: error:' in p.stdout+p.stderr
  finally:(root/'.shipcraft/locks').chmod(0o755)
 elif case=='lookup-commit':
  env,log=shim('lookup-commit-msg');p=status(env)
  assert log.read_text()=='rev-parse --git-path hooks/commit-msg\n','hook lookup not attempted'
  hookline(p,f'shipcraft: missing hook: could not read the hooks under core.hooksPath {dir}')
 elif case=='lookup-post':
  env,log=shim('lookup-post-commit');p=status(env)
  assert log.read_text()=='rev-parse --git-path hooks/post-commit\n','hook lookup not attempted'
  hookline(p,f'shipcraft: missing hook: could not read the hooks under core.hooksPath {dir}')
 else:raise AssertionError('unrouted item101 case: '+case)
PY101
  pass
}
