# Item 135, spec f00a1be. Real local Git objects; no network or gh.
item135_langs() { echo core; }
item135_cases() {
  local c
  for c in history untouched agents managers mixed nested fork deterministic detached modes empty-commit order plain paths messages folders headers uses-config uses-legacy lock-open lock-json lock-duplicate lock-closed merge exists current empty-range only-setup bad-base bad-branch unrelated arguments precedence git-failure read-failure ci-after docs fixture-control ci-control no-origin-control; do echo "v1-135.$c"; done
}
item135_case() {
  EXPECT="item 135: ${CASE#v1-135.}"
  v1_start
  must_accept 'export contract' cmd "$PY" - "${CASE#v1-135.}" "$(command -v shipcraft)" "$CW" "$ACEITE/.." <<'PY135'
import json,os,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw,source=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw);source=Path(source)
os.environ['GIT_ALLOW_PROTOCOL']='file'
os.environ['GIT_AUTHOR_DATE']='2001-02-03T04:05:06+0200'
os.environ['GIT_COMMITTER_DATE']='2002-03-04T05:06:07-0300'
def run(*args,**kw):
 p=subprocess.run(list(map(str,args)),capture_output=True,timeout=60,**kw)
 print('$',repr(args),'exit',p.returncode,repr(p.stdout),repr(p.stderr),flush=True);return p
def git(*args,**kw):
 p=run('git',*args,**kw);assert p.returncode==0,('fixture git',args,p.stderr);return p.stdout.rstrip(b'\n').decode()
def put(p,data):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data.encode() if isinstance(data,str) else data)
def commit(changes,msg='feature135',parents=None,extra=b''):
 # Hand-built committed fixtures, including malformed locks: never overwrite a
 # lock or run-log path used by a public command. All edits enter Git's index.
 for path,value in changes.items():
  if value is None:git('update-index','--force-remove','--',path);continue
  mode,data=value if isinstance(value,tuple) else ('100644',value)
  blob=git('hash-object','-w','--stdin',input=data.encode() if isinstance(data,str) else data)
  git('update-index','--add','--cacheinfo',mode,blob,path)
 tree=git('write-tree')
 if parents is None:
  p=run('git','rev-parse','--verify','HEAD');parents=[p.stdout.decode().strip()] if p.returncode==0 else []
 raw=('tree '+tree+'\n'+''.join('parent '+p+'\n' for p in parents)+'author Author 135 <author@example.invalid> 981173106 +0200\ncommitter Committer 135 <committer@example.invalid> 1015214767 -0300\n').encode()+extra+b'\n'+(msg.encode() if isinstance(msg,str) else msg)
 oid=git('hash-object','-t','commit','-w','--stdin',input=raw);git('update-ref','HEAD',oid);return oid

def observe_git():
 real=shutil.which('git');bindir=cw/'observe-bin';bindir.mkdir();trace=cw/'git-trace.jsonl'
 script="#!"+sys.executable+"\nimport json,os,sys\nfrom pathlib import Path\na=sys.argv[1:]\nfolders=[x.split('=',1)[1] for x in a if x.startswith('core.hooksPath=')]\nrow={'args':a,'lazy':os.environ.get('GIT_NO_LAZY_FETCH'),'replace':os.environ.get('GIT_NO_REPLACE_OBJECTS'),'empty_hooks':bool(folders) and all(Path(x).is_dir() and not list(Path(x).iterdir()) for x in folders)}\nwith open("+repr(str(trace))+",'a') as f:f.write(json.dumps(row)+'\\n')\nos.execv("+repr(real)+",["+repr(real)+",*a])\n"
 put(bindir/'git',script);(bindir/'git').chmod(0o755)
 return dict(os.environ,PATH=str(bindir)+os.pathsep+os.environ['PATH']),trace

def snap():
 refs=git('for-each-ref','--format=%(refname) %(objectname) %(symref)')
 files={}
 for p in root.rglob('*'):
  rel=p.relative_to(root).as_posix()
  if rel=='.git' or rel.startswith('.git/'):continue
  if p.is_symlink():files[rel]=('link',os.readlink(p))
  elif p.is_file():files[rel]=(stat.S_IMODE(p.stat().st_mode),p.read_bytes())
 rawrefs={p.relative_to(Path('.git')).as_posix():p.read_bytes() for p in Path('.git/refs').rglob('*') if p.is_file()}
 return (Path('.git/HEAD').read_bytes(),Path('.git/index').read_bytes(),files,Path('.git/shipcraft/runs.jsonl').read_bytes() if Path('.git/shipcraft/runs.jsonl').is_file() else None,refs,rawrefs)
root=cw/'project135';root.mkdir();os.chdir(root)
git('init','-q','-b','main');git('config','user.name','Fixture135');git('config','user.email','fixture@example.invalid')
f=commit({'src/calc.py':'value = 1\n','tests/test_calc.py':'def test_ok():\n    assert True\n','AGENTS.md':b'# Upstream rules\r\n\x00','gone':'remove me','mode':'mode\n'},'base135')
git('checkout','-qb','work135')
args=['export','--base','main','clean135'];branch='clean135';base='main';kept=[];omitted=[];original=[];trees=[];want=0;err=None;repeat=False;ci_after=False;docs=False;lock_variants=[];observe=False
# Expected trees are explicit fixture edits, not a second implementation of export.
if case=='history':
 a=commit({'.shipcraft.toml':'invalid config is not read','CLAUDE.md':'installed'},'add shipcraft');original.append(a)
 b=commit({'tests/test_sub.py':'def test_sub(): assert True\n','.shipcraft/locks/x.json':'{"state":"open"}'},'test: sub');original.append(b)
 c=commit({'src/calc.py':'value = 2\n'},'feat: sub');original.append(c)
 d=commit({'.shipcraft/locks/x.json':'{"state":"closed"}'},'chore(shipcraft): close lock x');omitted.append((d,'chore(shipcraft): close lock x'))
 trees=[{'CLAUDE.md':'installed'},{'CLAUDE.md':'installed','tests/test_sub.py':'def test_sub(): assert True\n'},{'CLAUDE.md':'installed','tests/test_sub.py':'def test_sub(): assert True\n','src/calc.py':'value = 2\n'}];kept=['.shipcraft.toml','.shipcraft/']
elif case=='untouched':
 observe=True
 original=[commit({'src/calc.py':'value = 3\n'},'dirty export')];trees=[{'src/calc.py':'value = 3\n'}]
 git('checkout-index','-a','-f');put('src/calc.py','staged135');git('add','src/calc.py');put('src/calc.py','unstaged135');put('untracked135','untracked')
 git('tag','keep135',f)
 for hook in ('commit-msg','post-commit','reference-transaction'):
  put('.git/hooks/'+hook,'#!/bin/sh\necho ran >> "'+str(cw/'hook-marker')+'"\n');Path('.git/hooks/'+hook).chmod(0o755)
elif case=='agents':
 original=[commit({'AGENTS.md':'replaced rules','CLAUDE.md':'new agent','src/new':'yes'})];trees=[{'AGENTS.md':'replaced rules','CLAUDE.md':'new agent','src/new':'yes'}];kept=[]
elif case=='managers':
 names=['.pre-commit-config.yaml','.husky/commit-msg','.husky/post-commit','lefthook.yml','.lefthook.yml','lefthook.yaml','.lefthook.yaml','lefthook-local.yml','.lefthook-local.yml','lefthook-local.yaml','.lefthook-local.yaml']
 git('checkout','-q','main');f=commit({n:'base '+n for n in names},'managers base');git('checkout','-q','work135');git('reset','--hard',f)
 original=[commit(dict({n:'changed '+n for n in names},**{'.husky/pre-commit':'keep this hook'}))];trees=[{'.husky/pre-commit':'keep this hook'}];kept=sorted(names)
elif case=='mixed':
 original=[commit({'.shipcraft.toml':'not TOML','src/new':'mixed'})];trees=[{'src/new':'mixed'}];kept=['.shipcraft.toml']
elif case=='nested':
 original=[commit({'docs/AGENTS.md':'nested','pkg/.shipcraft.toml':'nested config','pkg/.shipcraft/brief':'nested brief'})];trees=[{'docs/AGENTS.md':'nested','pkg/.shipcraft.toml':'nested config','pkg/.shipcraft/brief':'nested brief'}]
elif case=='fork':
 original=[commit({'src/new':'fork'})];trees=[{'src/new':'fork'}]
 git('checkout','-q','main');commit({'upstream-new':'later upstream'});git('checkout','-q','work135')
elif case=='deterministic':
 original=[commit({'src/new':'repeat','.sc2.toml':'legacy'})];trees=[{'src/new':'repeat'}];kept=['.sc2.toml'];repeat=True
elif case=='detached':
 original=[commit({'src/new':'detached'})];trees=[{'src/new':'detached'}];git('checkout','-q','--detach')
elif case=='modes':
 git('update-index','--add','--cacheinfo','160000',f,'vendor');original=[commit({'gone':None,'mode':('100755','mode\n'),'link':('120000','src/calc.py')})];trees=[{'gone':None,'mode':('100755','mode\n'),'link':('120000','src/calc.py'),'vendor':('160000',f)}]
elif case=='empty-commit':
 e=commit({},'empty135');omitted=[(e,'empty135')];original=[commit({'src/new':'after empty'})];trees=[{'src/new':'after empty'}]
elif case=='order':
 args=['export','release/clean135','--base','main'];branch='release/clean135';original=[commit({'src/new':'order'})];trees=[{'src/new':'order'}]
elif case=='plain':
 original=[commit({'src/new':'one'}),commit({'src/new':'two'})];trees=[{'src/new':'one'},{'src/new':'two'}]
elif case=='paths':
 a=commit({'.shipcraft/z':'z','.shipcraft/a':'a','AGENTS.md':'changed','.sc2.toml':'legacy'},'setup paths')
 original=[a,commit({'.shipcraft/z':None,'AGENTS.md':b'# Upstream rules\r\n\x00','src/new':'paths'})];trees=[{'AGENTS.md':'changed'},{'src/new':'paths'}];kept=['.sc2.toml','.shipcraft/']
elif case=='messages':
 a=commit({},b'bad\t\x7f\xc2\x85\xff subject\nbody\n');b=commit({},b'\nempty first\n');omitted=[(a,'bad   \ufffd subject'),(b,'(no subject)')]
 original=[commit({'src/new':'message'},b'multi\n\nbody\r\nlast without newline')];trees=[{'src/new':'message'}]
elif case=='folders':
 original=[commit({'AGENTS.md':None,'AGENTS.md/guide.md':'folder','src/new':'folder'})];trees=[{'src/new':'folder'}];kept=['AGENTS.md']
 # Ancestor non-folder exception: preserve C's .husky symlink.
 git('checkout','-q','main');f=commit({'.husky/commit-msg':'base hook'},'ancestor base');git('checkout','-q','work135');git('reset','--hard',f)
 original=[commit({'.husky/commit-msg':None,'.husky':('120000','elsewhere'),'AGENTS.md':None,'AGENTS.md/guide.md':'folder','src/new':'folder'})];trees=[{'.husky/commit-msg':None,'.husky':('120000','elsewhere'),'src/new':'folder'}];kept=['.husky/commit-msg','AGENTS.md']
elif case=='headers':
 original=[commit({'src/new':'headers'},b'raw\xff message\n',extra=b'encoding ISO-8859-1\ngpgsig fake-signature\n continuation135\n')];trees=[{'src/new':'headers'}]
elif case=='uses-config':
 git('checkout','-q','main');f=commit({'.shipcraft.toml':'invalid','.sc2.toml':'legacy'},'base config');git('checkout','-q','work135');git('reset','--hard',f);commit({'src/new':'yes'});want=1
 err="shipcraft refused: main has .shipcraft.toml, so this project uses Shipcraft and its files belong in the PR\nWhy: export leaves out Shipcraft's files for a project that does not use Shipcraft; nothing was written\nNext: open the PR from this branch with shipcraft pr\n"
elif case=='uses-legacy':
 git('checkout','-q','main');f=commit({'.sc2.toml/child':'directory also counts'},'base legacy');git('checkout','-q','work135');git('reset','--hard',f);commit({'src/new':'yes'});want=1
 err="shipcraft refused: main has .sc2.toml, so this project uses Shipcraft and its files belong in the PR\nWhy: export leaves out Shipcraft's files for a project that does not use Shipcraft; nothing was written\nNext: open the PR from this branch with shipcraft pr\n"
elif case=='lock-open':
 commit({'.shipcraft/locks/z.json':'{"state":"open"}','.shipcraft/locks/.json':('120000','{"state":"open"}'),'src/new':'lock'});want=1
 err="shipcraft refused: HEAD has an open lock, .shipcraft/locks/.json, so its locked tests do not pass yet\nWhy: the branch you send upstream should hold finished work, and the lock closes only when its cases pass; nothing was written\nNext: finish the GREEN (the hook closes the lock when its cases pass), then run shipcraft export again\n"
elif case=='lock-json':
 lock_variants=[b'not json',b'[]',b'null',b'{"state":true}',b'{"state":"CLOSED"}',b'{"state":"closed"} trailing',b'\xff',b'{}']
 commit({'.shipcraft/locks/a.json':'\ufeff{"state":"closed"}','src/new':'lock'});want=1
 err="shipcraft refused: HEAD has an open lock, .shipcraft/locks/a.json, so its locked tests do not pass yet\nWhy: the branch you send upstream should hold finished work, and the lock closes only when its cases pass; nothing was written\nNext: finish the GREEN (the hook closes the lock when its cases pass), then run shipcraft export again\n"
elif case=='lock-duplicate':
 commit({'.shipcraft/locks/a.json':'{"state":"closed","state":"open"}','src/new':'lock'});want=1
 err="shipcraft refused: HEAD has an open lock, .shipcraft/locks/a.json, so its locked tests do not pass yet\nWhy: the branch you send upstream should hold finished work, and the lock closes only when its cases pass; nothing was written\nNext: finish the GREEN (the hook closes the lock when its cases pass), then run shipcraft export again\n"
elif case=='lock-closed':
 original=[commit({'.shipcraft/locks/a.json':'{"state":"open","state":"closed"}','.shipcraft/locks/sub/b.json':'bad','.shipcraft/locks/ignored.txt':'bad','src/new':'closed'})];trees=[{'src/new':'closed'}];kept=['.shipcraft/']
elif case=='merge':
 a=commit({'side':'side'});git('reset','--hard',f);b=commit({'src/new':'merge'});m=commit({},'merge135',parents=[b,a]);want=1
 err=f"shipcraft refused: {m[:7]} in main..HEAD is a merge commit, so export cannot replay the branch as one line of commits\nWhy: export writes each commit again on top of the one before it, and a merge has more than one parent; nothing was written\nNext: rebase the branch onto main (git rebase main), then run shipcraft export again\n"
elif case=='exists':
 commit({'src/new':'exists'});git('symbolic-ref','refs/heads/clean135','refs/heads/missing135');want=1
 err='shipcraft refused: branch clean135 already exists\nWhy: export never moves or overwrites a branch; nothing was written\nNext: pick another name, or remove clean135 yourself if you no longer need it, then run shipcraft export again\n'
elif case=='current':
 commit({'src/new':'current'});args[-1]='work135';branch='work135';want=1
 err='shipcraft refused: branch work135 already exists\nWhy: export never moves or overwrites a branch; nothing was written\nNext: pick another name, or remove work135 yourself if you no longer need it, then run shipcraft export again\n'
elif case=='empty-range':
 want=1;err="shipcraft refused: no commit in main..HEAD changes a file outside Shipcraft's files\nWhy: the branch would hold nothing to send upstream; nothing was written\nNext: commit your change on this branch, then run shipcraft export again\n"
elif case=='only-setup':
 commit({'.shipcraft.toml':'config'},'setup');commit({},'empty');want=1
 err="shipcraft refused: no commit in main..HEAD changes a file outside Shipcraft's files\nWhy: the branch would hold nothing to send upstream; nothing was written\nNext: commit your change on this branch, then run shipcraft export again\n"
elif case=='bad-base':
 args[2]='missing135';want=2;err='shipcraft: error: --base missing135 is not a commit in this repository\n'
elif case=='bad-branch':
 commit({'src/new':'branch'});args[-1]='bad..name';want=2;err='shipcraft: error: bad..name is not a valid branch name\n'
elif case=='unrelated':
 git('read-tree','--empty');commit({'unrelated':'root'},parents=[]);want=2;err='shipcraft: error: main and HEAD share no commit\n'
elif case=='arguments':
 usage=run(binary,'--help').stdout.decode();expected_line='     | shipcraft ci --base <ref> [--pr] | shipcraft export --base <ref> <branch>\n'
 assert expected_line in usage,'usage lacks export'
 for invalid in (['export'],['export','main','clean'],['export','--base'],['export','--base','main'],['export','--base','main','a','b'],['export','--base','main','a','--base','main'],['export','--wrong','main','a'],['export','--base','--bad','a']):
  before=snap();p=run(binary,*invalid);assert p.returncode==2 and p.stdout==b'' and p.stderr.decode()=='shipcraft: error: invalid arguments: '+' '.join(invalid)+'; '+usage,(p.returncode,p.stderr);assert snap()==before
 raise SystemExit(0)
elif case=='precedence':
 # Base config outranks locks, no shared root, merge, invalid/existing branch and empty.
 git('checkout','-q','main');f=commit({'.shipcraft.toml':'base'},'configured');git('checkout','-q','work135');git('read-tree','--empty');commit({'.shipcraft/locks/x.json':'bad'},parents=[]);args[-1]='bad..name';want=1
 err="shipcraft refused: main has .shipcraft.toml, so this project uses Shipcraft and its files belong in the PR\nWhy: export leaves out Shipcraft's files for a project that does not use Shipcraft; nothing was written\nNext: open the PR from this branch with shipcraft pr\n"
elif case=='git-failure':
 commit({'src/new':'late failure'});git('branch','clean135/child',f);want=2
elif case=='read-failure':
 commit({'src/new':'missing tree'})
 missing=git('rev-parse','main^{tree}');Path('.git/objects/'+missing[:2]+'/'+missing[2:]).unlink();want=2
elif case=='ci-after':
 config='shipcraft_min = "0.0"\nlang = "python"\nrunner = "pytest"\n[execution]\nci = "off"\nreview = "off"\n[[suite]]\nroot = "."\ncommand = "pytest -q --junitxml={junit} tests"\nglobs = ["tests/**"]\n'
 original=[commit({'.shipcraft.toml':config,'src/new':'ci-after135'})];trees=[{'src/new':'ci-after135'}];kept=['.shipcraft.toml'];ci_after=True
 git('reset','--hard','HEAD')
elif case=='docs':
 docs=True
elif case=='fixture-control':
 h=commit({'src/new':'fixture-control135','.shipcraft/locks/a.json':'{"state":"closed"}'},b'fixture135\n\nbody\n')
 assert git('show',h+':src/new')=='fixture-control135';assert git('show',h+':.shipcraft/locks/a.json')=='{"state":"closed"}'
 assert git('cat-file','commit',h).endswith('fixture135\n\nbody')
 before=snap();p=run(binary,'--version');assert p.returncode==0 and p.stdout.startswith(b'shipcraft ');assert snap()==before
 assert git('rev-parse',h+'^')==f
 observer,trace=observe_git();hooks=cw/'empty-hooks';hooks.mkdir()
 p=run('git','-c','core.hooksPath='+str(hooks),'show',h+':src/new',env=dict(observer,GIT_NO_LAZY_FETCH='1',GIT_NO_REPLACE_OBJECTS='1'))
 assert p.returncode==0 and p.stdout==b'fixture-control135'
 records=[json.loads(x) for x in trace.read_text().splitlines()]
 assert len(records)==1 and records[0]=={'args':['-c','core.hooksPath='+str(hooks),'show',h+':src/new'],'lazy':'1','replace':'1','empty_hooks':True}
 raise SystemExit(0)
elif case=='ci-control':
 config='shipcraft_min = "0.0"\nlang = "python"\nrunner = "pytest"\n[execution]\nci = "off"\nreview = "off"\n[[suite]]\nroot = "."\ncommand = "pytest -q --junitxml={junit} tests"\nglobs = ["tests/**"]\n'
 h=commit({'.shipcraft.toml':config,'src/new':'ci-control135'});git('reset','--hard',h)
 before=snap();p=run(binary,'ci','--base','main');assert p.returncode==0,(p.stdout,p.stderr)
 rows=[json.loads(x) for x in Path('.git/shipcraft/runs.jsonl').read_text().splitlines()];assert rows[-1]['layer']=='ci' and rows[-1]['result']=='passed'
 assert f'shipcraft: 1 commit(s) checked in {f[:7]}..HEAD\n'.encode() in p.stdout and git('show','HEAD:src/new')=='ci-control135'
 raise SystemExit(0)
elif case=='no-origin-control':
 commit({'src/new':'no-origin135'});before=snap();p=run(binary,'pr','--title','item135')
 assert p.returncode==1 and p.stdout==b'' and p.stderr==b'shipcraft refused: this repository has no remote named origin, so shipcraft pr has nowhere to open a PR\nWhy: pr pushes the branch to origin and opens the PR on GitHub; nothing was fetched, pushed or sent\nNext: the work stays local, and `shipcraft ci --base main` is your finish line; to open PRs, add a GitHub repository you can push to: git remote add origin <url>\n',(p.returncode,p.stderr)
 assert snap()==before;raise SystemExit(0)
else:raise AssertionError('unrouted '+case)
if docs:
 readme=(source/'README.md').read_text()
 heading="### Contributing to a project that doesn't use Shipcraft"
 assert readme.count(heading)==1 and readme.index(heading)<readme.index('### Removing Shipcraft'),'README subsection missing'
 row="| `shipcraft export --base <ref> <branch>` | For a project that doesn't use Shipcraft: writes `<branch>` with your commits since `<ref>`, without Shipcraft's files (config, locks, briefs, Shipcraft's block in `AGENTS.md` and `CLAUDE.md`, hook manager files) and without the commits that change only them. Push it to your fork and open the PR from it. |"
 assert readme.count("Work as usual on your branch: `init`, RED, GREEN, `shipcraft ci --base <base>`. The setup, the locks and the closing commits stay on that branch, which keeps the guarantee and its history. When the lock is closed, `shipcraft export --base <base> <branch>` writes `<branch>`: the same commits on the same base, without `.shipcraft.toml`, `.shipcraft/`, the hook manager files and Shipcraft's block in `AGENTS.md` and `CLAUDE.md`, and without the commits that change only them. Your own changes to `AGENTS.md` and `CLAUDE.md` stay. It lists what it left out; a change of yours to the other files has to be added by hand. Push `<branch>` to your fork and open the PR from it; `shipcraft pr` is for projects that use Shipcraft.")==1
 assert readme.count(row)==1 and readme.index('| `shipcraft ci')<readme.index(row)
 spec=(source/'docs/spec.md').read_text();table=spec.split('## 7. Refusals',1)[1].split('## 8.',1)[0]
 labels=['execution-invalid','export-branch-exists','export-empty','export-lock-open','export-merge','export-uses-shipcraft','foreign-hook'];positions=[table.index('| `'+label+'`') for label in labels];assert positions==sorted(positions)
 for label in labels[1:-1]:assert table.count('| `'+label+'`')==1
 assert '| `export --base <ref> <branch>` |' in spec.split('## 3.',1)[1].split('## 4.',1)[0]
 raise SystemExit(0)
# Snapshot immediately around export, allowing only its new branch.
scratch=cw/'export-temp';scratch.mkdir();export_env=dict(os.environ,TMPDIR=str(scratch))
before=snap()
if observe:
 observer,trace=observe_git();export_env.update(PATH=observer['PATH'])
p=run(binary,*args,env=export_env);after=snap()
assert not list(scratch.iterdir()),'export leaked temporary files'
assert after[:4]==before[:4],'export changed HEAD/index/worktree/run log'
assert not (cw/'hook-marker').exists(),'export ran a hook'
if want:
 assert after[4:]==before[4:],'failed export changed refs'
 assert p.returncode==want and p.stdout==b'',('expected failure',want,p.returncode,p.stdout,p.stderr)
 if err is not None:assert p.stderr.decode()==err,(err,p.stderr)
 else:assert p.stderr.startswith(b'shipcraft: error:') and b'invalid arguments' not in p.stderr,p.stderr
 for value in lock_variants:
  commit({'.shipcraft/locks/a.json':value});before=snap();p=run(binary,*args,env=export_env);assert snap()==before
  assert p.returncode==1 and p.stdout==b'' and p.stderr.decode()==err,(value,p.returncode,p.stderr)
 raise SystemExit(0)
assert p.returncode==0 and p.stderr==b'',('expected export success',p.returncode,p.stderr)
if observe:
 records=[json.loads(x) for x in trace.read_text().splitlines()];assert records,'export must use git'
 for r in records:
  assert r['lazy']=='1' and r['replace']=='1' and r['empty_hooks'],r
  assert any(a=='-c' and b.startswith('core.hooksPath=') for a,b in zip(r['args'],r['args'][1:])),r

tip=git('rev-parse','refs/heads/'+branch)
assert {k:v for k,v in after[5].items() if k!='refs/heads/'+branch}==before[5]
assert '\n'.join(x for x in after[4].splitlines() if not x.startswith('refs/heads/'+branch+' '))==before[4]
exported=git('rev-list','--reverse',f+'..'+tip).splitlines();assert len(exported)==len(original),(exported,original)
# Compare each complete exported tree to an independently constructed literal tree.
index=cw/'oracle-index';env=dict(os.environ,GIT_INDEX_FILE=str(index))
for oid,old,changes in zip(exported,original,trees):
 git('read-tree',f,env=env)
 for path,value in changes.items():
  if value is None:git('update-index','--force-remove','--',path,env=env);continue
  mode,data=value if isinstance(value,tuple) else ('100644',value);blob=data if mode=='160000' else git('hash-object','-w','--stdin',input=data.encode() if isinstance(data,str) else data);git('update-index','--add','--cacheinfo',mode,blob,path,env=env)
 assert git('rev-parse',oid+'^{tree}')==git('write-tree',env=env),'wrong exported tree'
 raw=run('git','cat-file','commit',old).stdout;headers,message=raw.split(b'\n\n',1)
 author=next(x for x in headers.split(b'\n') if x.startswith(b'author '));committer=next(x for x in headers.split(b'\n') if x.startswith(b'committer '))
 parent=f if oid==exported[0] else exported[exported.index(oid)-1]
 expected=b'tree '+git('rev-parse',oid+'^{tree}').encode()+b'\nparent '+parent.encode()+b'\n'+author+b'\n'+committer+b'\n\n'+message
 assert run('git','cat-file','commit',oid).stdout==expected,'raw exported commit differs'
index.unlink(missing_ok=True)
total=len(git('rev-list',base+'..HEAD').splitlines())
output=f"shipcraft: exported {len(exported)} of {total} commit(s) in {base}..HEAD to {branch} ({tip[:7]}), on {f[:7]}, without Shipcraft's files\n"
for oid,subject in omitted:output+=f"shipcraft: left out {oid[:7]} {subject}: no change outside Shipcraft's files\n"
if kept:output+=f"shipcraft: kept as in {f[:7]}: {', '.join(kept)}; add any change of yours to them by hand\n"
output+=f"shipcraft: next: push {branch} to your fork and open the PR from it; this branch keeps the locks and the hook's history\n"
assert p.stdout.decode()==output,(output,p.stdout)
if ci_after:
 head=git('rev-parse','HEAD');p=run(binary,'ci','--base','main');assert p.returncode==0,(p.stdout,p.stderr)
 rows=[json.loads(x) for x in Path('.git/shipcraft/runs.jsonl').read_text().splitlines()];assert rows[-1]['layer']=='ci' and rows[-1]['result']=='passed'
 assert git('rev-parse','HEAD')==head and git('rev-parse',branch)==tip
if repeat:
 git('branch','-D',branch);before=snap();again=run(binary,*args);after=snap();assert again.returncode==0 and again.stdout==p.stdout and again.stderr==b'';assert git('rev-parse',branch)==tip and before[:4]==after[:4]
PY135
  pass
}
