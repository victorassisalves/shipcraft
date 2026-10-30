# Item 68: public init only; historical block fixtures live with item 61.
item68_langs() { echo core; }
item68_cases() {
  local c kind name
  for c in block block-local block-append block-local-append upgrade-bare-bare upgrade-bare-local upgrade-local-bare upgrade-local-local legacy legacy-local briefs briefs-local other other-local equal-bare-bare equal-bare-local equal-local-bare equal-local-local closing closing-red closing-green closing-none folder-link folder-dangling folder-file parent-link parent-link-locks folder-readonly write-fails write-fails-kept write-partial core-file core-refused core-hooks; do echo "v1-68.$c"; done
  for kind in differs marker invalid link dangling directory unreadable; do
    for name in red green; do echo "v1-68.$kind-$name"; done
  done
}
item68_case() {
  EXPECT="item 68: ${CASE#v1-68.}"
  v1_start codex claude
  must_accept 'item 68 acceptance contract' cmd "$PY" - "${CASE#v1-68.}" "$(command -v shipcraft)" "$ACEITE" "$CW" <<'PY68'
import ast,os,re,shutil,stat,subprocess,sys
from pathlib import Path
try: import tomllib
except ImportError: import tomli as tomllib
case,binary,acceptance,cw=sys.argv[1:];binary=str(Path(binary).resolve())
version=tomllib.loads((Path(acceptance).parent/'nucleo/Cargo.toml').read_text())['package']['version']
# Reuse acceptance fixtures only, never the implementation. Execute just fixture constants/function.
source=(Path(acceptance)/'lib/item61.sh').read_text().split("<<'PY61'\n",1)[1].split('\nPY61',1)[0]
names={'OLD','PREVIOUS_BARE','ROOT_LINE','PREVIOUS_LOCAL','head','rest','READ_TESTS','REPAIR','ROLES'}
ns={}
for n in ast.parse(source).body:
 if isinstance(n,ast.Assign):
  targets={x.id for target in n.targets for x in ast.walk(target) if isinstance(x,ast.Name)}
  if targets and targets<=names:exec(compile(ast.Module(body=[n],type_ignores=[]),'item61-fixtures','exec'),ns)
 elif isinstance(n,ast.FunctionDef) and n.name=='expected_block':exec(compile(ast.Module(body=[n],type_ignores=[]),'item61-fixtures','exec'),ns)
IMPORT=b'<!-- shipcraft -->\nShipcraft workflow (required): @AGENTS.md\n<!-- /shipcraft -->\n'
BRIEFS=Path('.shipcraft/briefs'); NAMES=('red.md','green.md')
CI='CI runs on this machine through shipcraft pr. To run it on GitHub, see shipcraft docs/github-ci.md.'
def write(path,data,mode=None):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
 if mode is not None:p.chmod(mode)
def run(*args,ok=True,cwd=None):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,timeout=90,cwd=cwd)
 print('$',repr(args),'[rc='+str(p.returncode)+']\n'+text(p),flush=True)
 if ok:assert p.returncode==0,('init changed exit',p.returncode,text(p))
 return p
def text(p):return (p.stdout+p.stderr).decode(errors='replace')
def local_call(root):
 target=root/'node_modules/shipcraft-fixture/bin/shipcraft';target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(binary,target)
 call=root/'node_modules/.bin/shipcraft';call.parent.mkdir(parents=True,exist_ok=True);call.symlink_to(target);return call
root=Path(cw)/'project68';root.mkdir();os.chdir(root)
run('git','init','-q',str(root));write('requirements.txt','pytest\n')
call=local_call(root) if case.endswith('-local') or case.startswith('block-local') else binary
args=['--lang','other','--command','runner {junit}','--glob','tests/**'] if case.startswith('other') else []
def init(ok=True):return run(call,'init',*args,ok=ok)
def present(name):return (BRIEFS/name).is_file() and not (BRIEFS/name).is_symlink()
def need_briefs():
 for name in NAMES:assert present(name),'init did not write .shipcraft/briefs/'+name
def core_survived():
 assert Path('.shipcraft.toml').is_file(),'brief issue rolled back config'
 assert Path('AGENTS.md').is_file() and Path('CLAUDE.md').read_bytes()==IMPORT,'brief issue rolled back onboarding'
 assert Path('.shipcraft/locks').is_dir(),'brief issue rolled back locks'
 for event in ('commit-msg','post-commit'):assert os.access('.git/hooks/'+event,os.X_OK),'brief issue rolled back hooks'
def closing(p,written,agents=True):
 lines=text(p).splitlines();ready=[s for s in lines if s.startswith('shipcraft: ready. Commit ')]
 assert len(ready)==1,('closing line missing/duplicated',ready)
 line=ready[0]
 for name in NAMES:assert ('.shipcraft/briefs/'+name in line)==(name in written),('closing must name only written briefs',written,line)
 if agents:
  tokens=['AGENTS.md','CLAUDE.md']+['.shipcraft/briefs/'+n for n in NAMES if n in written]
  assert all(t in line for t in tokens) and [line.index(t) for t in tokens]==sorted(line.index(t) for t in tokens),('closing file order',line)
 assert lines[-1]==CI,'CI line must stay last'
 assert lines[-3]==line and 'test' in lines[-2].lower() and 'then' in lines[-2].lower(),'closing gained a line or changed guidance order'
def notice(p,name,kind):
 line="shipcraft: .shipcraft/briefs/"+name+(' differs from this version\'s, kept: compare it with docs/spec.md' if kind=='differs' else ' could not be read, kept')
 assert text(p).splitlines().count(line)==1,('missing per-brief notice',line)
def snapshot(path):
 p=Path(path)
 if p.is_symlink():return ('link',os.readlink(p))
 if p.is_dir():return ('dir',stat.S_IMODE(p.stat().st_mode),{q.name:snapshot(q) for q in p.iterdir()})
 return ('file',stat.S_IMODE(p.stat().st_mode),p.read_bytes())
def sample(local=False):
 d=Path(cw)/('sample-local68' if local else 'sample-bare68');d.mkdir();run('git','init','-q',str(d));write(d/'requirements.txt','pytest\n')
 run(local_call(d) if local else binary,'init',cwd=d)
 for n in NAMES:assert (d/BRIEFS/n).is_file(),'sample init did not write .shipcraft/briefs/'+n
 return {n:(d/BRIEFS/n).read_bytes() for n in NAMES}
def brief_contract(data,name,local):
 assert b'\r' not in data and data.endswith(b'\n'),'brief must use LF and a final newline'
 assert data.splitlines()[-1]==('<!-- written by shipcraft '+version+' -->').encode(),'last line must stamp full Cargo version without build hash'
 s=data.decode();cmd='npx -- shipcraft' if local else 'shipcraft'
 # Deliberately check concepts/phrases, not a complete editorial template.
 patterns={
 'red.md':[r'intent',r'never.*?implementation',r'two cases',r'ordinary',r'boundary',r'(?:read|existing).*?tests',r'(?:before|first)',r'never contradict',r'(?:intent|change).*?changes',r'fail.*?right reason',re.escape(cmd)+r' red',r'passing control',r'lock.*?control',r'(?:fake|external).*?real output',r'commit.*?tests',r'stubs',r'lock',r'stop',r'ambiguit'],
 'green.md':[r'(?:start|from).*?RED commit',r'never.*?edit.*?locked file',r'(?:or|and).*?lock',r'product code',r'dependencies',r'config',r'locked tests.*?pass',r'other tests.*?(?:check|gate)',r'(?:not a gate|not.*?gate)',r'report.*?fail',r'hook.*?(?:verdict|decide)',r'CI.*?rest',r'stop.*?report.*?test',r'reason',r'(?:instead|rather|never).*?(?:work.*?around|workaround)',r'commit']}
 for pattern in patterns[name]:assert re.search(pattern,s,re.I|re.S),name+' missing brief concept: '+pattern
 if local:
  assert not re.search(r'(?<!npx -- )\bshipcraft\s+(?:red|status|check|close)\b',s),'bare command in local brief'
 else:assert 'npx -- shipcraft' not in s,'bare brief uses npx'

if case.startswith('block'):
 append=case.endswith('append');prefix=b'Rules68\r\nwithout final newline' if append else b''
 if append:write('AGENTS.md',prefix)
 p=init();expected=(prefix+b'\n\n' if append else b'')+ns['expected_block']('local' in case)
 assert Path('AGENTS.md').read_bytes()==expected,'block must make exactly three changes; all other bytes/order unchanged'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'CLAUDE block changed'
elif case.startswith('upgrade-') or case.startswith('legacy'):
 local=case.endswith('-local');oldlocal=case.startswith('upgrade-local-')
 old=ns['OLD'] if case.startswith('legacy') else ns['PREVIOUS_LOCAL' if oldlocal else 'PREVIOUS_BARE']
 prefix=b'# Before68\r\n\x00\n';suffix=b'\nAfter68\r\nno final newline'
 write('AGENTS.md',prefix+old+suffix,0o751);write('CLAUDE.md',IMPORT)
 p=init();assert Path('AGENTS.md').read_bytes()==prefix+ns['expected_block'](local)+suffix,'known block not upgraded with surrounding bytes preserved'
 assert stat.S_IMODE(Path('AGENTS.md').stat().st_mode)==0o751,'upgrade changed mode'
 assert Path('CLAUDE.md').read_bytes()==IMPORT,'upgrade changed CLAUDE block'
 assert 'AGENTS.md' in next(l for l in text(p).splitlines() if l.startswith('shipcraft: ready. Commit '))
elif case in ('briefs','briefs-local','other','other-local'):
 p=init();need_briefs();core_survived()
 for n in NAMES:brief_contract((BRIEFS/n).read_bytes(),n,case.endswith('local'))
 closing(p,NAMES)
elif case.startswith('equal-'):
 _,source_variant,target_variant=case.split('-');data=sample(source_variant=='local')
 # Both current variants are silently accepted even when this install chooses the other.
 for n in NAMES:write(BRIEFS/n,data[n],0o444)
 before=snapshot(BRIEFS);p=init();core_survived();assert snapshot(BRIEFS)==before,'equal brief changed bytes/modes'
 assert not any('.shipcraft/briefs' in l for l in text(p).splitlines()),'equal brief must be kept silently'
 closing(p,[])
elif case.startswith('closing'):
 kept=set(NAMES) if case=='closing-none' else {'green.md'} if case=='closing-red' else {'red.md'} if case=='closing-green' else set()
 for n in kept:write(BRIEFS/n,'User brief68\n')
 p=init();closing(p,set(NAMES)-kept);core_survived()
 for n in kept:assert (BRIEFS/n).read_bytes()==b'User brief68\n';notice(p,n,'differs')
 for n in set(NAMES)-kept:assert present(n),'closing named an unwritten brief'
elif case.startswith('core-'):
 if case=='core-file':write('.shipcraft',b'blocked68\r\n')
 elif case=='core-refused':write('.git/hooks/commit-msg','#!/bin/sh\necho foreign68\n',0o755)
 else:Path('.git/hooks').chmod(0o500)
 before={str(p):snapshot(p) for p in root.iterdir() if p.name!='.git'}
 p=init(False)
 if case=='core-hooks':Path('.git/hooks').chmod(0o700)
 assert p.returncode==(1 if case=='core-refused' else 2),'core failure changed today\'s exit'
 assert not BRIEFS.exists(),'failed core init wrote briefs'
 assert before=={str(p):snapshot(p) for p in root.iterdir() if p.name!='.git'},'core failure did not roll back working tree'
 assert 'ready. Commit' not in text(p)
elif case in ('folder-link','folder-dangling','folder-file','parent-link','parent-link-locks','folder-readonly'):
 outside=Path(cw)/'outside68';outside.mkdir();write(outside/'sentinel',b'keep68\r\n')
 if case.startswith('parent-link'):
  if case.endswith('locks'):(outside/'locks').mkdir()
  Path('.shipcraft').symlink_to(outside,target_is_directory=True)
 elif case=='folder-file':write(BRIEFS,'blocked68\n')
 elif case=='folder-readonly':Path('.shipcraft').mkdir()
 else:
  Path('.shipcraft').mkdir();BRIEFS.symlink_to(outside if case=='folder-link' else outside/'missing',target_is_directory=True)
 # Read-only parent must still permit the core locks step; precreate that folder.
 if case=='folder-readonly':
  Path('.shipcraft').chmod(0o700);Path('.shipcraft/locks').mkdir();Path('.shipcraft').chmod(0o500)
 before=snapshot(outside)
 entry=Path('.shipcraft') if case.startswith('parent-link') else BRIEFS
 protected=snapshot(entry) if entry.exists() or entry.is_symlink() else None
 try:p=init();core_survived()
 finally:
  if case=='folder-readonly':Path('.shipcraft').chmod(0o700)
 assert any(l.startswith('shipcraft: .shipcraft/briefs not written: ') and len(l)>len('shipcraft: .shipcraft/briefs not written: ') for l in text(p).splitlines()),'missing folder notice'
 if protected is not None:assert snapshot(entry)==protected,'unsafe folder entry was replaced or modified'
 assert snapshot(outside)==(before if not case.startswith('parent-link') else ('dir',before[1],dict(before[2],locks=('dir',0o755,{'.gitkeep':('file',0o644,b'')})))),'brief writing followed parent/folder symlink or damaged target'
 for n in NAMES:assert not (BRIEFS/n).exists(),'unsafe folder got a brief'
 closing(p,[])
elif case=='write-partial':
 # Real OS write failure after a temporary file can be created, not just open denial.
 # Seed unchanged core files first so the size limit applies only to brief writes.
 import resource,signal
 data=sample();init();need_briefs()
 for n in NAMES:(BRIEFS/n).unlink()
 limit=max(1,min(len(b) for b in data.values())-1)
 def limited():
  signal.signal(signal.SIGXFSZ,signal.SIG_IGN)
  resource.setrlimit(resource.RLIMIT_FSIZE,(limit,limit))
 p=subprocess.run([str(call),'init'],input=b'',capture_output=True,timeout=90,preexec_fn=limited)
 print('$ init with RLIMIT_FSIZE',limit,'[rc='+str(p.returncode)+']\n'+text(p),flush=True)
 assert p.returncode==0,('brief partial-write failure changed init exit',p.returncode,text(p))
 core_survived()
 assert list(BRIEFS.iterdir())==[],'partial-write failure left a temporary or partly written brief'
 for n in NAMES:assert any(l.startswith('shipcraft: .shipcraft/briefs/'+n+' not written: ') for l in text(p).splitlines()),'partial-write failure skipped '+n
 closing(p,[],agents=False)
elif case.startswith('write-fails'):
 data=sample() if case.endswith('kept') else None
 BRIEFS.mkdir(parents=True)
 if data:write(BRIEFS/'green.md',data['green.md'])
 before=snapshot(BRIEFS);BRIEFS.chmod(0o500)
 try:p=init();core_survived()
 finally:BRIEFS.chmod(0o755)
 assert snapshot(BRIEFS)==before,'brief write failure leaked temporary/partial files or changed old bytes'
 for n in (('red.md',) if data else NAMES):
  assert any(l.startswith('shipcraft: .shipcraft/briefs/'+n+' not written: ') for l in text(p).splitlines()),'missing write-failure notice for '+n
 closing(p,[])
else:
 kind,name=case.rsplit('-',1);name+='.md';other=next(n for n in NAMES if n!=name);f=BRIEFS/name
 BRIEFS.mkdir(parents=True);target=Path(cw)/'target68';write(target,b'outside68\r\n')
 if kind=='differs':write(f,b'User UTF-8: caf\xc3\xa9\r\nno final newline')
 elif kind=='marker':write(f,('<!-- written by shipcraft '+version+' -->\n<!-- shipcraft -->\ncustom\n<!-- /shipcraft -->\n').encode())
 elif kind=='invalid':write(f,b'\xff\n')
 elif kind=='directory':f.mkdir();write(f/'sentinel',b'directory68\n')
 elif kind=='unreadable':write(f,b'private68\n',0o000)
 else:f.symlink_to(target if kind=='link' else Path(cw)/'missing68')
 # Unreadable bytes are saved before dropping read permission; compare after restoring it.
 if kind=='unreadable':f.chmod(0o600);before=f.read_bytes();f.chmod(0o000)
 else:before=snapshot(f)
 try:
  p=init();core_survived()
  if kind=='unreadable':assert stat.S_IMODE(f.stat().st_mode)==0,'kept unreadable brief mode changed'
 finally:
  if kind=='unreadable':f.chmod(0o600)
 assert (f.read_bytes()==before if kind=='unreadable' else snapshot(f)==before),'kept brief was modified'
 assert target.read_bytes()==b'outside68\r\n' and not Path(cw,'missing68').exists(),'brief symlink target changed'
 notice(p,name,'differs' if kind in ('differs','marker') else 'read')
 assert present(other),'kept/problematic brief prevented writing the other brief'
 closing(p,[other])
PY68
  pass
}
