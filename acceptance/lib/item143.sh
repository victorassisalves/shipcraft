# Item 143: public init fixtures; captured husky 9.1.7/7.0.4 and pre-commit 4.3.0.
item143_langs() { echo core; }
item143_cases() {
 local c
 for c in plain precommit precommit-breaks precommit-indent precommit-local husky9 husky-existing husky7 agents-created agents-endings claude-project earlier-block local-block untracked edited-block husky-runner edited-precommit edited-hook symlinks lefthook project-files legacy-config open-lock lock-reader closed-locks copies tracked-paths dry-run idempotent nothing readme usage plan-failure copy-failure late-failure arguments worktrees control-plain control-managers control-locks; do echo "v1-143.$c"; done
}
item143_case() {
 EXPECT="item 143: ${CASE#v1-143.}"
 v1_start codex claude
 must_accept 'uninstall contract' cmd "$PY" - "${CASE#v1-143.}" "$(command -v shipcraft)" "$CW" "$ACEITE" <<'PY143'
import ast,json,os,re,resource,shlex,shutil,signal,stat,subprocess,sys
from pathlib import Path
case,binary,cw,acceptance=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw);acceptance=Path(acceptance)
os.environ['GIT_ALLOW_PROTOCOL']='file'
def run(*args,**kw):
 p=subprocess.run(list(map(str,args)),capture_output=True,timeout=90,**kw)
 print('$',repr(args),'exit',p.returncode,repr(p.stdout),repr(p.stderr),flush=True);return p
def ok(*args,**kw):
 p=run(*args,**kw);assert p.returncode==0,('fixture command',args,p.stdout,p.stderr);return p.stdout
def git(*args,**kw):return ok('git',*args,**kw).decode().strip()
def put(path,data,mode=0o644):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data.encode() if isinstance(data,str) else data);p.chmod(mode)
def entries(folder):
 result={}
 def walk(d):
  for p in d.iterdir():
   rel=str(p.relative_to(folder));m=stat.S_IMODE(p.lstat().st_mode)
   if p.is_symlink():result[rel]=('link',os.readlink(p),m)
   elif p.is_dir():result[rel]=('dir',m);walk(p)
   else:result[rel]=('file',p.read_bytes(),m)
 if folder.is_dir():walk(folder)
 return result
def snapshot():
 # Include raw tree/index/refs/hooks/log/copies, without git status refreshing index.
 return entries(Path('.'))
def commit(msg):
 git('add','-A');git('commit','-qm',msg);return git('rev-parse','HEAD')
def fixture(name,agents=b'# Rules\n\n- Keep it small.\n',manager='',local=False,ending=b'\n',indent=False,claude=None):
 root=cw/name;root.mkdir();os.chdir(root);git('init','-q','-b','main');git('config','user.name','Fixture143');git('config','user.email','fixture@example.invalid');git('config','gc.auto','0');git('config','maintenance.auto','false')
 put('run.sh',runner);put('tests/base.sh','test "$(cat value)" = 1\n');put('value','1\n')
 if agents is not None:put('AGENTS.md',agents)
 if claude is not None:put('CLAUDE.md',claude)
 if manager=='pre':
  put('.pre-commit-config.yaml',(b'# preserve143\nrepos:\n'+(b'  ' if indent else b'')+b'- repo: https://example.invalid/project\n'+(b'    ' if indent else b'  ')+b'rev: v1\n'+(b'    ' if indent else b'  ')+b'hooks: []\n').replace(b'\n',ending))
 elif manager in ('husky9','husky7'):
  git('config','core.hooksPath','.husky/_' if manager=='husky9' else '.husky')
  if manager=='husky9':
   put('.husky/_/h',constants['HUSKY_H'])
   for e in ('commit-msg','post-commit'):put('.husky/_/'+e,constants['HUSKY_LAUNCHER'],0o755)
  else:put('.husky/_/husky.sh',(acceptance/'fixtures/item133/husky.sh').read_bytes())
  put('.husky/pre-commit','# formatter143\n',0o755)
 call=binary
 if local:
  target=root/'node_modules/shipcraft-fixture/bin/shipcraft';target.parent.mkdir(parents=True);shutil.copy2(binary,target)
  link=root/'node_modules/.bin/shipcraft';link.parent.mkdir();link.symlink_to('../shipcraft-fixture/bin/shipcraft');call=str(target)
  put('.gitignore','node_modules/\n')
 base=commit('base143');before={k:v for k,v in entries(root).items() if k!='.git' and not k.startswith('.git/')}
 ok(call,'init','--lang','other','--command','sh run.sh {junit}','--glob','tests/*.sh')
 return root,call,base,before

def invariant(before):
 after=snapshot()
 # Uninstall's only Git writes are hooks and recovery copies. Index, refs,
 # measurement and per-worktree state remain byte-for-byte unchanged.
 keep=lambda s:{k:v for k,v in s.items() if k.startswith('.git/') and not k.startswith(('.git/hooks/','.git/shipcraft/uninstalled')) and k not in ('.git/hooks','.git/shipcraft')}
 assert keep(after)==keep(before),'uninstall changed Git index/refs/log/state'
def uninstall(*args,call=None,**kw):
 before=snapshot();env,trace=observer();probe=cw/'forbidden-uninstall143';env.update(UNINSTALL143_PROBE=str(probe))
 p=run(call or binary,'uninstall',*args,env=env,**kw);invariant(before)
 assert not probe.exists(),'uninstall ran suite or gh'
 for a in (map(json.loads,trace.read_text().splitlines()) if trace.exists() else []):
  assert any(command in a for command in ('rev-parse','ls-files','ls-tree','cat-file','worktree')),('uninstall ran non-read Git command',a)
 return p
def success(p):
 assert p.returncode==0,('uninstall must accept valid command',p.returncode,p.stderr)
 assert p.stderr==b'',p.stderr
 return p.stdout.decode()
def refusal(p,path):
 assert p.returncode==1,('open lock must refuse',p.returncode,p.stderr)
 expected=(f'shipcraft refused: {path} is an open lock, so a RED commit is still waiting for its GREEN\n'
 'Why: removing the hooks and the config now would leave that change unjudged, and the lock would leave the tree before the commit that closes it; nothing was changed\n'
 'Next: finish the GREEN (the hook closes the lock when its cases pass), or drop the RED commit that opened the lock, then run shipcraft uninstall again\n').encode()
 assert p.stdout==b'' and p.stderr==expected,(p.stdout,p.stderr)
def backups(out):
 line=out.splitlines()[0];prefix='shipcraft: copying everything it removes or changes to '
 assert line.startswith(prefix),out
 folder=Path(line[len(prefix):]);assert re.fullmatch(r'\d{8}T\d{6}Z(?:-(?:[2-9]|[1-9][0-9]+))?',folder.name),folder
 assert folder.is_dir();return folder

def lock_blob(name,data,mode='100644',checkout=True):
 # Like item135: fixture history via real Git objects/index, never fabricated
 # runtime red output. Existing runtime lock files are never overwritten.
 blob=git('hash-object','-w','--stdin',input=data);git('update-index','--add','--cacheinfo',mode,blob,name)
 tree=git('write-tree');parent=git('rev-parse','HEAD');oid=git('commit-tree',tree,'-p',parent,input=b'lock reader fixture143\n');git('update-ref','HEAD',oid)
 if checkout:git('checkout-index','-f','--',name)
 return oid

def file_limit():
 signal.signal(signal.SIGXFSZ,signal.SIG_IGN);resource.setrlimit(resource.RLIMIT_FSIZE,(16384,16384))

def observer(fault=''):
 real=shutil.which('git');tools=cw/('git-'+str(len(list(cw.glob('git-*')))));tools.mkdir();trace=tools/'calls'
 put(tools/'git','#!'+sys.executable+'\nimport json,os,sys\na=sys.argv[1:]\nwith open('+repr(str(trace))+',"a") as f:f.write(json.dumps(a)+"\\n")\n'+
 "fault="+repr(fault)+"\nif 'ls-files' in a and fault:\n print('fatal: plan143' if fault=='exit' else 'malformed\\0record',end='',file=sys.stderr if fault=='exit' else sys.stdout);sys.exit(128 if fault=='exit' else 0)\n"+
 'os.execv('+repr(real)+',['+repr(real)+',*a])\n',0o755)
 put(tools/'gh','#!/bin/sh\nprintf gh143 > "$UNINSTALL143_PROBE"\nexit 97\n',0o755)
 return dict(os.environ,PATH=str(tools)+os.pathsep+os.environ['PATH']),trace
# Capture public acceptance constants, without executing another item's cases.
source=(acceptance/'lib/item25.sh').read_text().split("<<'PY25'\n",1)[1].split('\nPY25',1)[0]
constants={n.targets[0].id:ast.literal_eval(n.value) for n in ast.parse(source).body if isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Name) and n.targets[0].id in ('HUSKY_H','HUSKY_LAUNCHER','PRE_LAUNCHER')}
source=(acceptance/'lib/item85.sh').read_text().split("<<'PY85'\n",1)[1].split('\nPY85',1)[0];f85={}
for n in ast.parse(source).body:
 if isinstance(n,ast.Assign) and all(isinstance(t,ast.Name) and t.id in {'OLD84','ROOT_LINE','CLEANUP','NEW'} for t in n.targets):exec(compile(ast.Module(body=[n],type_ignores=[]),'fixture85','exec'),f85)
 elif isinstance(n,ast.FunctionDef) and n.name=='variant':exec(compile(ast.Module(body=[n],type_ignores=[]),'fixture85','exec'),f85)
runner='''#!/bin/sh
if [ -n "${UNINSTALL143_PROBE-}" ]; then printf suite143 > "$UNINSTALL143_PROBE"; exit 97; fi
out=$1
mkdir -p "$(dirname "$out")"
printf '<testsuites><testsuite name="shell143">' > "$out"
failed=0
for t in tests/*.sh; do
 printf '<testcase classname="%s" name="check" file="%s">' "$t" "$t" >> "$out"
 if ! sh "$t"; then printf '<failure message="wrong value"/>' >> "$out"; failed=1; fi
 printf '</testcase>' >> "$out"
done
printf '</testsuite></testsuites>' >> "$out"
exit "$failed"
'''
# Each exact arm owns its inputs and expected results.
if case=='plain':
 root,call,base,original=fixture('plain');commit('install143');before=snapshot();out=success(uninstall())
 assert Path('AGENTS.md').read_bytes()==b'# Rules\n\n- Keep it small.\n'
 assert not any(Path(p).exists() for p in ('CLAUDE.md','.shipcraft.toml','.shipcraft','.git/hooks/commit-msg','.git/hooks/post-commit'))
 after={k:v for k,v in entries(root).items() if k!='.git' and not k.startswith('.git/')};assert after==original,'plain tree did not return to base bytes/modes'
 lines=['shipcraft: removed the shipcraft block from AGENTS.md','shipcraft: removed CLAUDE.md','shipcraft: removed .git/hooks/commit-msg','shipcraft: removed .git/hooks/post-commit','shipcraft: removed .shipcraft/briefs/red.md','shipcraft: removed .shipcraft/briefs/green.md','shipcraft: removed .shipcraft/locks/.gitkeep','shipcraft: removed .shipcraft.toml']
 assert out.splitlines()[1:9]==lines,out
 backups(out);assert 'commit the removal: git -C '+str(root)+' commit -m "chore: remove shipcraft" -- AGENTS.md CLAUDE.md .shipcraft/briefs/red.md .shipcraft/briefs/green.md .shipcraft/locks/.gitkeep .shipcraft.toml\n' in out
 assert 'required checks, remove them from the default branch' in out and f'shipcraft: the binary stays ({binary}): remove it with install.sh --uninstall, or cargo uninstall shipcraft if you built it from source\n' in out
elif case=='precommit':
 root,call,base,original=fixture('pre',manager='pre');raw=original['.pre-commit-config.yaml'][1]
 for event in ('commit-msg','post-commit'):put('.git/hooks/'+event,constants['PRE_LAUNCHER'].replace('--hook-type=commit-msg','--hook-type='+event),0o755)
 launchers=entries(Path('.git/hooks'));out=success(uninstall());assert entries(Path('.git/hooks'))==launchers
 assert Path('.pre-commit-config.yaml').read_bytes()==raw
 assert 'shipcraft: removed the shipcraft hooks from .pre-commit-config.yaml\n' in out and 'pre-commit uninstall -t commit-msg -t post-commit (or prek uninstall ...)\n' in out
 assert not Path('.shipcraft.toml').exists()
elif case=='precommit-breaks':
 for i,br in enumerate((b'\r\n',b'\r',b'\xc2\x85',b'\xe2\x80\xa8',b'\xe2\x80\xa9')):
  root,call,base,original=fixture('break'+str(i),manager='pre',ending=br);out=success(uninstall());assert Path('.pre-commit-config.yaml').read_bytes()==original['.pre-commit-config.yaml'][1]
elif case=='precommit-indent':
 root,call,base,original=fixture('indent',manager='pre',indent=True);out=success(uninstall());assert Path('.pre-commit-config.yaml').read_bytes()==original['.pre-commit-config.yaml'][1]
elif case=='precommit-local':
 root,call,base,original=fixture('local-pre',manager='pre',local=True)
 raw=Path('.pre-commit-config.yaml').read_bytes();assert b'./node_modules/.bin/shipcraft' in raw
 # Legacy post-commit id is one of the proven forms too.
 put('.pre-commit-config.yaml',raw.replace(b'id: shipcraft-close',b'id: shipcraft-fecha'));out=success(uninstall(call=call));assert Path('.pre-commit-config.yaml').read_bytes()==original['.pre-commit-config.yaml'][1]
elif case=='husky9':
 root,call,base,original=fixture('h9',manager='husky9');out=success(uninstall());assert not Path('.husky/commit-msg').exists() and not Path('.husky/post-commit').exists()
 assert Path('.husky/_/h').read_text()==constants['HUSKY_H'] and Path('.husky/pre-commit').read_bytes()==b'# formatter143\n'
elif case=='husky-existing':
 root,call,base,original=fixture('existing',manager='husky9')
 put('.husky/commit-msg',b'#!/bin/sh\n# project143\n'+Path('.husky/commit-msg').read_bytes()+b'echo kept143\n',0o751)
 out=success(uninstall());assert Path('.husky/commit-msg').read_bytes()==b'#!/bin/sh\n# project143\necho kept143\n' and stat.S_IMODE(Path('.husky/commit-msg').stat().st_mode)==0o751
 assert 'removed the shipcraft line from .husky/commit-msg\n' in out
elif case=='husky7':
 root,call,base,original=fixture('h7',manager='husky7');out=success(uninstall());assert not Path('.husky/commit-msg').exists() and not Path('.husky/post-commit').exists();assert Path('.husky/_/husky.sh').read_bytes()==original['.husky/_/husky.sh'][1]
elif case=='agents-created':
 root,call,base,original=fixture('created',agents=None);out=success(uninstall());assert not Path('AGENTS.md').exists() and 'shipcraft: removed AGENTS.md\n' in out
elif case=='agents-endings':
 for i,end in enumerate((b'',b'\n',b'\n\n',b'\n\n\n',b'\n\n\n\n')):
  root,call,base,original=fixture('ending'+str(i),agents=b'project143'+end);out=success(uninstall());assert Path('AGENTS.md').read_bytes()==b'project143'+(end if len(end)>=3 else b'\n')
 # Interior block: separators before it stay, suffix bytes are not normalized.
 root,call,base,original=fixture('suffix');put('AGENTS.md',Path('AGENTS.md').read_bytes()+b'after143\x00\r\nlast');out=success(uninstall());assert Path('AGENTS.md').read_bytes()==b'# Rules\n\n- Keep it small.\n\nafter143\x00\r\nlast'
elif case=='claude-project':
 root,call,base,original=fixture('claude',claude=b'# Claude project143\n');out=success(uninstall());assert Path('CLAUDE.md').read_bytes()==b'# Claude project143\n' and 'removed the shipcraft block from CLAUDE.md\n' in out
elif case=='earlier-block':
 for i,block in enumerate((f85['OLD84'],f85['NEW'],f85['variant'](f85['NEW'],True))):
  root,call,base,original=fixture('earlier'+str(i));put('AGENTS.md',b'old-project143\n\n'+block);out=success(uninstall());assert Path('AGENTS.md').read_bytes()==b'old-project143\n'
elif case=='local-block':
 root,call,base,original=fixture('project-local',local=True);assert b'npx -- shipcraft' in Path('AGENTS.md').read_bytes();out=success(uninstall(call=call))
 assert Path('AGENTS.md').read_bytes()==b'# Rules\n\n- Keep it small.\n' and not Path('.git/hooks/commit-msg').exists()
 assert 'shipcraft: the binary stays: remove the package with pnpm remove shipcraft (or npm rm shipcraft) and commit package.json with the lockfile\n' in out
 assert Path(call).is_file()
elif case=='untracked':
 root,call,base,original=fixture('untracked',agents=None);out=success(uninstall());assert 'commit the removal:' not in out and not Path('AGENTS.md').exists() and not Path('.shipcraft').exists()
elif case=='edited-block':
 for i,kind in enumerate(('edited','crlf','double','reversed','legacy-open','future')):
  root,call,base,original=fixture('edited'+str(i));raw=Path('AGENTS.md').read_bytes();block=raw[raw.index(b'<!-- shipcraft -->'):]
  edits={'edited':raw.replace(b'TDD with',b'EDIT with',1),'crlf':raw.replace(b'\n',b'\r\n'),'double':raw+block,'reversed':b'<!-- /shipcraft -->\n<!-- shipcraft -->\n','legacy-open':block.rsplit(b'<!-- /shipcraft -->',1)[0],'future':block.replace(b'- Cycle:',b'- Future:')}
  put('AGENTS.md',edits[kind]);out=success(uninstall());assert Path('AGENTS.md').read_bytes()==edits[kind]
  assert 'shipcraft: left AGENTS.md: its shipcraft markers do not hold a block Shipcraft writes (edited by hand, or from another version); remove it by hand\n' in out and not Path('.shipcraft.toml').exists()
elif case=='husky-runner':
 for i,line in enumerate(('npx --no -- shipcraft close\n','pnpm exec shipcraft close\n','shipcraft close\nshipcraft close\n','shipcraft close extra\n')):
  root,call,base,original=fixture('runner'+str(i),manager='husky9');put('.husky/post-commit',line);out=success(uninstall());assert Path('.husky/post-commit').read_text()==line and not Path('.husky/commit-msg').exists()
  assert 'shipcraft: left .husky/post-commit: it calls shipcraft in a line init does not write; remove it by hand\n' in out and '.shipcraft.toml: a hook that calls shipcraft is left (.husky/post-commit)' in out and Path('.shipcraft.toml').is_file()
elif case=='edited-precommit':
 root,call,base,original=fixture('edited-pre',manager='pre');raw=Path('.pre-commit-config.yaml').read_bytes().replace(b'language: system',b'language: python',1);put('.pre-commit-config.yaml',raw);out=success(uninstall())
 assert Path('.pre-commit-config.yaml').read_bytes()==raw and 'it mentions shipcraft outside the item init appends; remove it by hand\n' in out and Path('.shipcraft.toml').exists() and not Path('CLAUDE.md').exists()
elif case=='edited-hook':
 for i,text in enumerate((None,b'#!/bin/sh\nexec "/custom/shipcraft" close\n')):
  root,call,base,original=fixture('edited-hook'+str(i));path=Path('.git/hooks/post-commit');raw=path.read_bytes()+b'# edited143\n' if text is None else text;put(path,raw,0o755);out=success(uninstall())
  reason='a shipcraft hook edited by hand' if text is None else 'it calls shipcraft and is not a hook init writes'
  assert f'shipcraft: left .git/hooks/post-commit: {reason}; remove it by hand\n' in out and path.read_bytes()==raw and Path('.shipcraft.toml').exists()
  assert '.shipcraft.toml: a hook that calls shipcraft is left (.git/hooks/post-commit)' in out and not Path('.git/hooks/commit-msg').exists()
elif case=='symlinks':
 for i,name in enumerate(('AGENTS.md','CLAUDE.md','.shipcraft/briefs','.shipcraft','.shipcraft.toml','.husky')):
  root,call,base,original=fixture('link'+str(i));target=cw/('target'+str(i));target.mkdir();put(target/'sentinel','outside143\n')
  p=Path(name)
  if p.is_dir():shutil.rmtree(p)
  elif p.exists():p.unlink()
  p.symlink_to(target);before=entries(target);out=success(uninstall());assert p.is_symlink() and entries(target)==before
  reason='not a regular folder' if name in ('.shipcraft/briefs','.shipcraft','.husky') else 'not a regular file'
  assert f'shipcraft: left {name}: {reason}; remove it by hand\n' in out
elif case=='lefthook':
 root,call,base,original=fixture('lefthook');raw=b'commit-msg:\n  commands:\n    shipcraft:\n      run: shipcraft check --commit-msg {1}\n';put('lefthook.yml',raw);out=success(uninstall())
 assert Path('lefthook.yml').read_bytes()==raw and 'uninstall does not edit lefthook files yet: remove the shipcraft commands under commit-msg and post-commit; remove it by hand\n' in out
 assert Path('.shipcraft.toml').exists() and not Path('CLAUDE.md').exists()
elif case=='project-files':
 root,call,base,original=fixture('project-files');put('.shipcraft/z/custom','custom143\n');put('.shipcraft/a','first143\n');Path('.shipcraft/link').symlink_to('z');out=success(uninstall())
 for name in ('.shipcraft/a','.shipcraft/link','.shipcraft/z/custom'):assert f'shipcraft: left {name}: not a file init or red writes; remove it by hand\n' in out
 assert Path('.shipcraft/z/custom').read_bytes()==b'custom143\n' and Path('.shipcraft/link').is_symlink() and not Path('.shipcraft.toml').exists()
elif case=='legacy-config':
 for i,config in enumerate((b'invalid = [\xff',b'shipcraft_min = "999.0"\n',None)):
  root,call,base,original=fixture('config'+str(i))
  if config is None:Path('.shipcraft.toml').unlink()
  else:put('.shipcraft.toml',config)
  put('.sc2.toml',b'older invalid143\xff');put('.shipcraft/briefs/red.md',b'own brief143\xff');out=success(uninstall());folder=backups(out)
  assert (not (folder/'.shipcraft.toml').exists() if config is None else (folder/'.shipcraft.toml').read_bytes()==config)
  assert (folder/'.shipcraft/briefs/red.md').read_bytes()==b'own brief143\xff'
  assert Path('.sc2.toml').read_bytes()==b'older invalid143\xff' and 'shipcraft: left .sc2.toml: the config of an older Shipcraft; remove it by hand\n' in out and not Path('.shipcraft.toml').exists()
elif case=='open-lock':
 root,call,base,original=fixture('open');commit('install143');put('tests/new.sh','test "$(cat new-value 2>/dev/null)" = 2\n');ok(binary,'red');commit('red143');lock=next(Path('.shipcraft/locks').glob('*.json'))
 for args in ((),('--dry-run',)):
  before=snapshot();p=uninstall(*args);refusal(p,str(lock));assert snapshot()==before
 # HEAD still protects the RED after the runtime file is deleted or overwritten.
 lock.unlink();before=snapshot();p=uninstall();refusal(p,str(lock));assert snapshot()==before
elif case=='lock-reader':
 variants=[b'\xef\xbb\xbf{"state":"closed"}',b'[]',b'null',b'{"state":true}',b'{"state":"CLOSED"}',b'{"state":"closed"} trailing',b'\xff',b'{}',b'{"state":"closed","state":"open"}']
 for i,data in enumerate(variants):
  root,call,base,original=fixture('json'+str(i));lock_blob('.shipcraft/locks/a.json',data);before=snapshot();p=uninstall('--dry-run');refusal(p,'.shipcraft/locks/a.json');assert snapshot()==before
 for i,kind in enumerate(('folder','link','unreadable','locks-link','locks-file')):
  root,call,base,original=fixture('nonregular'+str(i));p=Path('.shipcraft/locks/a.json')
  if kind=='folder':p.mkdir()
  elif kind=='link':p.symlink_to('missing143')
  elif kind=='unreadable':
   lock_blob(str(p),b'{"state":"closed"}');p.chmod(0)
  else:
   shutil.rmtree('.shipcraft/locks');p=Path('.shipcraft/locks')
   if kind=='locks-link':p.symlink_to('briefs')
   else:put(p,'not a folder143')
  # Snapshot cannot read chmod-000; capture with permissions restored, then drop.
  if kind=='unreadable':
   assert os.geteuid()!=0,'unreadable-file fixture requires non-root acceptance user';p.chmod(0o600);before=snapshot();p.chmod(0)
  else:before=snapshot()
  q=run(binary,'uninstall');refusal(q,str(p))
  if kind=='unreadable':p.chmod(0o600)
  assert snapshot()==before
elif case=='closed-locks':
 root,call,base,original=fixture('closed');commit('install143');put('new-value','0\n');put('tests/new.sh','test "$(cat new-value)" = 2\n');ok(binary,'red');commit('red143');put('new-value','2\n');commit('green143');lock=next(Path('.shipcraft/locks').glob('*.json'));assert json.loads(lock.read_bytes())['state']=='closed'
 lock_blob('.shipcraft/locks/.json',b'{"state":"open","state":"closed"}');out=success(uninstall());assert not Path('.shipcraft/locks').exists()
 assert out.index('removed .shipcraft/locks/.gitkeep')<out.index('removed .shipcraft/locks/.json')<out.index('removed '+str(lock)) and 'shipcraft: the locks stay in git history: git log -- .shipcraft/locks\n' in out
elif case=='copies':
 root,call,base,original=fixture('copies');commit('install143');put('PROJECT.md','no markers143\n');put('.git/hooks/pre-push','#!/bin/sh\necho foreign143\n',0o755);Path('AGENTS.md').chmod(0o751);before=snapshot();out=success(uninstall());folder=backups(out)
 names=['AGENTS.md','CLAUDE.md','.shipcraft/briefs/red.md','.shipcraft/briefs/green.md','.shipcraft/locks/.gitkeep','.shipcraft.toml','.git/hooks/commit-msg','.git/hooks/post-commit']
 expected={('hooks/'+Path(n).name if n.startswith('.git/hooks/') else n):before[n] for n in names}
 actual={k:v for k,v in entries(folder).items() if v[0]!='dir'};assert actual==expected,'copies lost bytes, modes, or copied unrelated files'
 assert folder.parent==Path('.git/shipcraft/uninstalled')
 assert Path('PROJECT.md').read_bytes()==b'no markers143\n' and Path('.git/hooks/pre-push').read_bytes()==b'#!/bin/sh\necho foreign143\n'
elif case=='tracked-paths':
 root,call,base,original=fixture('space and quote\'143');commit('install143');git('rm','--cached','CLAUDE.md');put('unrelated','staged143\n');git('add','unrelated');put('unrelated','unstaged143\n');before=snapshot();out=success(uninstall())
 line=next(l for l in out.splitlines() if l.startswith('shipcraft: commit the removal: '));command=line.split(': ',2)[2]
 words=shlex.split(command);assert words==['git','-C',str(root),'commit','-m','chore: remove shipcraft','--','AGENTS.md','.shipcraft/briefs/red.md','.shipcraft/briefs/green.md','.shipcraft/locks/.gitkeep','.shipcraft.toml'],words
 assert "'" in command and Path('.git/index').read_bytes()==before['.git/index'][1]
 # The printed --only form must succeed without staging unrelated content.
 ok(*words);assert 'unrelated' not in git('ls-tree','--name-only','HEAD').splitlines()
 assert git('diff','--cached','--name-only')=='CLAUDE.md\nunrelated'
 assert ok('git','show','HEAD:CLAUDE.md').startswith(b'<!-- shipcraft -->')
elif case=='dry-run':
 root,call,base,original=fixture('dry');commit('install143');before=snapshot();out=success(uninstall('--dry-run'));assert snapshot()==before
 assert out.splitlines()[:2]==['shipcraft: would remove the shipcraft block from AGENTS.md','shipcraft: would remove CLAUDE.md']
 assert 'shipcraft: would remove .shipcraft.toml\n' in out and out.endswith('shipcraft: dry run: nothing was changed\n') and 'copying everything' not in out and 'commit the removal:' not in out
elif case=='idempotent':
 root,call,base,original=fixture('twice');first=success(uninstall());folder=backups(first);before=snapshot();assert success(uninstall())=='shipcraft: nothing to remove\n' and snapshot()==before
 assert success(uninstall('--dry-run'))=='shipcraft: nothing to remove\n' and snapshot()==before
 # Reinstall creates another recovery folder even within the same UTC second.
 ok(binary,'init','--lang','other','--command','sh run.sh {junit}','--glob','tests/*.sh');other=backups(success(uninstall()));assert other!=folder and folder.is_dir()
elif case=='nothing':
 root,call,base,original=fixture('nothing');success(uninstall());before=snapshot();assert success(uninstall())=='shipcraft: nothing to remove\n' and snapshot()==before
 clean=cw/'never-init';clean.mkdir();os.chdir(clean);git('init','-q','-b','main');before=snapshot();assert success(uninstall())=='shipcraft: nothing to remove\n' and snapshot()==before
elif case=='readme':
 text=(acceptance.parent/'README.md').read_text();section=text.split('### Removing Shipcraft\n\n',1)[1].split('\nUpgrading:',1)[0]
 assert section.startswith('Run `shipcraft uninstall`, with no lock open.'),'README missing uninstall instructions'
 assert section.count('Run `shipcraft uninstall`')==1 and 'By hand, for what `uninstall` leaves (lefthook files, anything edited by hand):\n\n1. Delete' in section
 assert 'the whole `- repo: local` item that holds `shipcraft-check` and `shipcraft-close`, not only its `shipcraft` lines.' in section
 row='| `shipcraft uninstall [--dry-run]` | Removes what `init` wrote from the working tree and the hooks folder, keeping a copy, and prints the commit to make. |'
 assert text.count(row)==1 and text.index(row)>text.index('| `shipcraft status`')
elif case=='usage':
 p=run(binary,'--help');assert p.returncode==0 and p.stdout.endswith(b'     | shipcraft uninstall [--dry-run]\n'),'usage missing final uninstall line'
 root,call,base,original=fixture('usage');before=snapshot()
 for args in (['uninstall','--dry-run','--dry-run'],['uninstall','--unknown'],['uninstall','value'],['uninstall','--dry-run=yes']):
  q=run(binary,*args);assert q.returncode==2 and q.stdout==b'' and q.stderr==b'shipcraft: error: invalid arguments: '+ ' '.join(args).encode()+b'; '+p.stdout and snapshot()==before
elif case=='plan-failure':
 for i,fault in enumerate(('exit','malformed')):
  root,call,base,original=fixture('plan'+str(i));env,trace=observer(fault)
  for args in ((),('--dry-run',)):
   before=snapshot();p=run(binary,'uninstall',*args,env=env);assert p.returncode==2 and p.stdout==b'' and p.stderr.startswith(b'shipcraft: error:') and b'invalid arguments:' not in p.stderr,'planning failure must be an operational error'
   assert snapshot()==before and any('ls-files' in a for a in map(json.loads,trace.read_text().splitlines()))
elif case=='copy-failure':
 root,call,base,original=fixture('copy-failure');put('.git/shipcraft/uninstalled','blocked143\n');before=snapshot();p=uninstall();assert p.returncode==2 and p.stdout==b'' and p.stderr.startswith(b'shipcraft: error:') and b'invalid arguments:' not in p.stderr,'copy-folder failure must precede changes';assert snapshot()==before
elif case=='late-failure':
 root,call,base,original=fixture('late-failure');put('.shipcraft/briefs/red.md',b'R'*65536);before=snapshot()
 p=uninstall(preexec_fn=file_limit);assert p.returncode==2 and p.stderr.startswith(b'shipcraft: error:') and b'invalid arguments:' not in p.stderr,'later copy failure must be operational'
 out=p.stdout.decode();folder=backups(out);assert 'removed CLAUDE.md\n' in out and not Path('CLAUDE.md').exists() and (folder/'CLAUDE.md').read_bytes()==before['CLAUDE.md'][1]
 assert Path('.shipcraft/briefs/red.md').read_bytes()==b'R'*65536 and not (folder/'.shipcraft/briefs/red.md').exists() and Path('.shipcraft.toml').is_file()
 assert 'commit the removal:' not in out;other=backups(success(uninstall()));assert other!=folder and (other/'.shipcraft/briefs/red.md').read_bytes()==b'R'*65536
elif case=='arguments':
 root,call,base,original=fixture('nested');commit('install143');put('.shipcraft.toml',b'not toml143\xff');nested=root/'sub'/'folder';nested.mkdir(parents=True);out=success(uninstall(cwd=nested));assert not (root/'.shipcraft.toml').exists() and 'git -C '+str(root)+' commit' in out
 outside=cw/'outside';outside.mkdir();env=dict(os.environ,GIT_CEILING_DIRECTORIES=str(cw));q=run(binary,'uninstall',cwd=outside,env=env);assert q.returncode==1 and b'invalid arguments:' not in q.stderr and b'git' in q.stderr
elif case=='worktrees':
 root,call,base,original=fixture('main-worktree');commit('install143');other=cw/'other worktree\n143';git('worktree','add','-qb','other143',other)
 os.chdir(other);oid=lock_blob('.shipcraft/locks/a.json',b'{"state":"open"}');os.chdir(root);before=snapshot();other_before=entries(other)
 p=uninstall();refusal(p,str(other/'.shipcraft/locks/a.json'));assert snapshot()==before and entries(other)==other_before
 (other/'.shipcraft/locks/a.json').unlink();before=snapshot();p=uninstall('--dry-run');refusal(p,str(other)+':.shipcraft/locks/a.json');assert snapshot()==before
 # A missing worktree still has its HEAD's RED; never prune or guess it safe.
 shutil.rmtree(other);before=snapshot();p=uninstall();refusal(p,str(other)+':.shipcraft/locks/a.json');assert snapshot()==before
elif case=='control-plain':
 root,call,base,original=fixture('control-plain');assert Path('CLAUDE.md').read_bytes()==b'<!-- shipcraft -->\nShipcraft workflow (required): @AGENTS.md\n<!-- /shipcraft -->\n'
 assert b'exec ' in Path('.git/hooks/commit-msg').read_bytes();commit('install control143')
 env,trace=observer();actual=ok('git','ls-files','-z','--cached','--full-name',env=env);assert b'AGENTS.md\0' in actual and json.loads(trace.read_text().splitlines()[-1])==['ls-files','-z','--cached','--full-name']
 # Marker-free project file and foreign, non-Shipcraft hook survive public init.
 put('AGENTS.md','# root without markers143\n');put('project.txt','no marker, leave byte-for-byte143\xff');put('.git/hooks/pre-push','#!/bin/sh\necho foreign143\n',0o755);before=snapshot();ok(binary,'init','--lang','other','--command','sh run.sh {junit}','--glob','tests/*.sh',env=env)
 assert Path('project.txt').read_bytes()==before['project.txt'][1]
 assert Path('.git/hooks/pre-push').read_bytes()==before['.git/hooks/pre-push'][1] and Path('AGENTS.md').read_bytes().startswith(b'# root without markers143\n')
 ok('sh','run.sh',cw/'control.xml');assert b'classname="tests/base.sh"' in (cw/'control.xml').read_bytes()
 root,call,base,original=fixture('control-local',local=True);assert b'npx -- shipcraft' in Path('AGENTS.md').read_bytes() and b'node_modules/.bin/shipcraft' in Path('.git/hooks/commit-msg').read_bytes()
 assert f85['variant'](f85['NEW'],True).startswith(b'<!-- shipcraft -->\n') and b'After a merge' in f85['NEW']
 probe=cw/'limit-probe';q=run(sys.executable,'-c',"import errno,sys\ntry:\n with open(sys.argv[1],'wb',buffering=0) as f:\n  for i in range(64):f.write(b'R'*1024)\nexcept OSError as e:\n assert e.errno==errno.EFBIG;print('limit143: EFBIG')\n",probe,preexec_fn=file_limit)
 assert q.returncode==0 and q.stdout==b'limit143: EFBIG\n' and probe.stat().st_size==16384
elif case=='control-managers':
 for i,manager in enumerate(('pre','husky9','husky7')):
  root,call,base,original=fixture('control-manager'+str(i),manager=manager,local=(manager=='pre'),ending=b'\r\n' if manager=='pre' else b'\n',indent=(manager=='pre'))
  if manager=='pre':
   raw=Path('.pre-commit-config.yaml').read_bytes();assert b'\r\n' in raw and b'id: shipcraft-check' in raw and b'id: shipcraft-close' in raw and b'./node_modules/.bin/shipcraft' in raw
  else:
   assert Path('.husky/commit-msg').read_bytes()==(b'#!/bin/sh\n. "$(dirname "$0")/_/husky.sh"\n\n' if manager=='husky7' else b'')+b'shipcraft check --commit-msg "$1"\n'
   assert Path('.husky/post-commit').read_bytes().endswith(b'shipcraft close\n')
  before=snapshot();ok(call,'init','--lang','other','--command','sh run.sh {junit}','--glob','tests/*.sh');assert snapshot()==before,'manager control reinit changed seeded variant'
elif case=='control-locks':
 root,call,base,original=fixture('control-locks');commit('install143');put('new-value','0\n');put('tests/new.sh','test "$(cat new-value)" = 2\n');ok(binary,'red');commit('red143');put('new-value','2\n');commit('green143')
 locks=list(Path('.shipcraft/locks').glob('*.json'));assert len(locks)==1 and json.loads(locks[0].read_bytes())['state']=='closed' and git('log','-1','--format=%s').startswith('chore(shipcraft): close lock ')
 oid=lock_blob('.shipcraft/locks/reader.json',b'{"state":"open","state":"closed"}');assert ok('git','show',oid+':.shipcraft/locks/reader.json')==b'{"state":"open","state":"closed"}' and Path('.shipcraft/locks/reader.json').read_bytes()==b'{"state":"open","state":"closed"}'
 before=snapshot();p=run(binary,'--version');assert p.returncode==0 and p.stdout.startswith(b'shipcraft ') and snapshot()==before
else:raise AssertionError('unrouted '+case)
PY143
 pass
}
