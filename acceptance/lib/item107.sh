# Item 107, spec 1513556: public init/report only; no implementation reader.
item107_langs() { echo core; }
item107_cases() {
  local c
  for c in init-python init-node init-jest init-go init-other init-workspace init-build init-workspace-build init-late-warning control-init basic boundary last-row last-limit results invalid-pr invalid-size invalid-limit integers merge merge-filter merge-types freeze after-merge reader malformed order text-fraction text-zero text-full since github git-failure config-failure control-report control-github; do echo "v1-107.$c"; done
}
item107_case() {
  EXPECT="item 107: ${CASE#v1-107.}"
  v1_start codex
  must_accept 'item 107 public contract' cmd "$PY" - "$CASE" "$(command -v shipcraft)" "$CW" <<'PY107'
import json,os,shutil,stat,subprocess,sys
from pathlib import Path
try: import tomllib
except ImportError: import tomli as tomllib
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/"repo107 space 'quote";root.mkdir();realgit=shutil.which('git');env=dict(os.environ)
for k in subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
def run(*args):
 p=subprocess.run(list(map(str,args)),cwd=root,env=env,input=b'',capture_output=True,timeout=40)
 print('COMMAND107',args,p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 return p
def git(*args):
 p=run(realgit,*args);assert p.returncode==0,('fixture git',p.stderr);return p.stdout.decode().strip()
def write(name,data):
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
def snapshot():
 return {str(p.relative_to(root)):(stat.S_IFMT(p.lstat().st_mode),stat.S_IMODE(p.lstat().st_mode),os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None) for p in root.rglob('*')}
def data(p):return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
git('init','-q','-b','main');git('config','gc.auto','0');git('config','maintenance.auto','false')
write('README.md','item107 fixture\n');write('.git/shipcraft/sentinel',b'keep107\x00\r\n')
tools=cw/'tools107';tools.mkdir();calls=cw/'git-calls107';ghcalls=cw/'gh-calls107';proof=cw/'proof107';fault=cw/'git-fault107';ghfault=cw/'gh-fault107'
# Transparent Git probe: public command recording and one injected read failure.
(tools/'git').write_text('#!'+sys.executable+'\n'+"import json,os,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith open("+repr(str(calls))+",'a') as f:f.write(json.dumps(a)+'\\n')\nif Path("+repr(str(fault))+").exists() and 'for-each-ref' in a:raise SystemExit(93)\nos.execv("+repr(realgit)+",["+repr(realgit)+",*a])\n");(tools/'git').chmod(0o755)
# gh 2.x pr-view JSON shape, as item 79; unexpected calls cannot access a service.
(tools/'gh').write_text('#!'+sys.executable+'\n'+"import json,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith open("+repr(str(ghcalls))+",'a') as f:f.write(json.dumps(a)+'\\n')\nif a!=['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']:raise SystemExit(91)\nif Path("+repr(str(ghfault))+").exists():raise SystemExit(92)\nprint(json.dumps(dict(number=97,state='OPEN',mergedAt=None,headRefOid='a'*40,mergeCommit=None)))\n");(tools/'gh').chmod(0o755)
# The compiler's success exit boundary (no invented output); no Vitest probe is eligible.
(tools/'npx').write_text('#!'+sys.executable+'\n'+"import json,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith open("+repr(str(proof))+",'a') as f:f.write(json.dumps(a)+'\\n')\nif a[:4]!=['--no','--','tsc','-b']:raise SystemExit(94)\nPath('proof-product107').write_text('compiler side effect107')\n");(tools/'npx').chmod(0o755)
env['PATH']=str(tools)+os.pathsep+env['PATH']
block=b'\n[pr]\n# product lines above which the PR body and the PR summary suggest a split; a line, never a refusal\nwarn_lines = 500\n'
def init_fixture(language='node',workspace=False,build=False,runner='vitest'):
 if language=='node':
  write('package.json',json.dumps(dict(private=True,devDependencies={runner:'*'},**({'workspaces':['packages/*']} if workspace else {}))))
  if workspace:
   for folder in ('packages/alpha','packages/beta'):
    write(folder+'/package.json',json.dumps(dict(name=Path(folder).name,devDependencies={runner:'*'})))
    write(folder+'/value.test.ts','// fixture test\n')
  if build:
   write('tsconfig.json','{"compilerOptions":{"composite":true,"types":[],"outDir":"dist"},"files":["value.ts"]}\n');write('value.ts','export const value = 1;\n')
 git('add','README.md',*(['package.json'] if language=='node' else []),*(['packages'] if workspace else []),*(['tsconfig.json','value.ts'] if build else []))
 return ([] if workspace else ['--lang',language])+(['--command','printf custom107 > {junit}','--glob','checks/**'] if language=='other' else [])
def init(args):
 p=run(binary,'init',*args)
 assert p.returncode==0,(p.stdout,p.stderr)
 assert (root/'.git/shipcraft/sentinel').read_bytes()==b'keep107\x00\r\n'
 assert not (root/'.git/shipcraft/runs.jsonl').exists(),'init appended a measurement'
 assert (root/'.shipcraft/locks/.gitkeep').read_bytes()==b''
 assert all(os.access(root/'.git/hooks'/h,os.X_OK) for h in ('commit-msg','post-commit'))
 assert b'warn_lines' not in p.stdout+p.stderr and b'[pr]' not in p.stdout+p.stderr,'new init announcement'
 return (root/'.shipcraft.toml').read_bytes(),p
# Each id has exactly one arm. Controls exercise the same public fixture helpers.
if case=='v1-107.init-python':
 b,p=init(init_fixture('python'));assert b'timeout = 1200\n'+block in b and b.endswith(block),b
 assert tomllib.loads(b.decode())['pr']=={'warn_lines':500}
elif case=='v1-107.init-node':
 b,p=init(init_fixture());assert b'timeout = 1200\n'+block in b and b.endswith(block),b
 assert tomllib.loads(b.decode())['runner']=='vitest'
elif case=='v1-107.init-jest':
 b,p=init(init_fixture(runner='jest'));assert b'timeout = 1200\n'+block in b and b.endswith(block),b
 assert tomllib.loads(b.decode())['runner']=='jest'
elif case=='v1-107.init-go':
 b,p=init(init_fixture('go'));assert b'timeout = 1200\n'+block in b and b.endswith(block),b
 assert tomllib.loads(b.decode())['runner']=='gotestsum'
elif case=='v1-107.init-other':
 b,p=init(init_fixture('other'));assert b'timeout = 1200\n'+block in b and b.endswith(block),b
 d=tomllib.loads(b.decode());assert d['test_command']=='printf custom107 > {junit}' and d['pr']=={'warn_lines':500} and 'lang' not in d,d
elif case=='v1-107.init-workspace':
 b,p=init(init_fixture(workspace=True));assert b'timeout = 1200\n'+block+b'\n[[suite]]\n' in b and b.count(b'[pr]')==1,b
 d=tomllib.loads(b.decode());assert d['pr']=={'warn_lines':500} and [s['root'] for s in d['suite']]==['packages/alpha','packages/beta'] and 'build' not in d,d
elif case=='v1-107.init-build':
 b,p=init(init_fixture(build=True));assert b'timeout = 1200\n'+block+b'\n[build]\n' in b and b.count(b'[pr]')==1,b
 d=tomllib.loads(b.decode());assert d['pr']=={'warn_lines':500} and d['build']['command']=='npx --no -- tsc -b .' and 'suite' not in d,d
elif case=='v1-107.init-workspace-build':
 b,p=init(init_fixture(workspace=True,build=True));assert b'timeout = 1200\n'+block+b'\n[build]\n' in b and b.count(b'[pr]')==1,b
 d=tomllib.loads(b.decode());assert d['pr']=={'warn_lines':500} and d['build']['command']=='npx --no -- tsc -b .' and len(d['suite'])==2,d
 assert b.index(block)<b.index(b'[build]')<b.index(b'[[suite]]'),b
elif case=='v1-107.init-late-warning':
 args=init_fixture();write('.shipcraft/briefs','blocked107\r\n');b,p=init(args)
 assert b'.shipcraft/briefs not written' in p.stdout+p.stderr and (root/'.shipcraft/briefs').read_bytes()==b'blocked107\r\n',(p.stdout,p.stderr)
 assert b'timeout = 1200\n'+block in b and b.endswith(block),b
elif case=='v1-107.control-init':
 args=init_fixture(workspace=True,build=True);b,p=init(args);d=tomllib.loads(b.decode())
 assert d['build']['command']=='npx --no -- tsc -b .' and [s['root'] for s in d['suite']]==['packages/alpha','packages/beta'],d
 assert data(proof)==[['--no','--','tsc','-b','.']] and (root/'proof-product107').read_text()=='compiler side effect107'
 # Preserve a custom limit and exact CRLF bytes; then exercise core-write rollback.
 kept=b'# kept107\r\nshipcraft_min="0.0"\r\ntest_command="false {junit}"\r\ntest_globs=["checks/**"]\r\n[pr]\r\nwarn_lines=17\r\n';write('.shipcraft.toml',kept)
 b,p=init(args);assert b==kept and data(proof)==[['--no','--','tsc','-b','.']],'existing config was reseeded'
 # Fresh second repository uses the same helpers; no generated hooks are altered.
 root=cw/'rollback107';root.mkdir();git('init','-q','-b','main');write('README.md','rollback107');write('.shipcraft','blocked107');args=init_fixture('python')
 p=run(binary,'init',*args);assert p.returncode==2 and b'undid what this run created' in p.stdout+p.stderr,(p.stdout,p.stderr)
 assert not any((root/n).exists() for n in ('.shipcraft.toml','AGENTS.md','CLAUDE.md','.git/hooks/commit-msg','.git/hooks/post-commit'))
 assert (root/'.shipcraft').read_text()=='blocked107'
else:
 # Report fixtures commit only before writing the append-only log, with no hooks.
 env.update(GIT_AUTHOR_DATE='1700000000 +0000',GIT_COMMITTER_DATE='1700000000 +0000')
 git('add','README.md');git('commit','-qm','fixture107');git('tag','v1.0.0')
 env.update(GIT_AUTHOR_DATE='1700086400 +0000',GIT_COMMITTER_DATE='1700086400 +0000')
 write('README.md','second release107\n');git('add','README.md');git('commit','-qm','release107');git('tag','v2.0.0')
 log=root/'.git/shipcraft/runs.jsonl'
 def row(layer='pr',pr=1,product_lines=501,warn_lines=500,**kw):
  r=dict(layer=layer,pr=pr,product_lines=product_lines,warn_lines=warn_lines,at=100,result='passed',base='main',default_branch='main',locks=[],lock='',secs=1)
  r.update(kw);return r
 def wire(rs):return ''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in rs).encode()
 def report(rs,args=('--json',)):
  write('.git/shipcraft/runs.jsonl',rs if isinstance(rs,bytes) else wire(rs));before=snapshot()
  p=run(binary,'report',*args)
  assert p.returncode==0 and not p.stderr,(p.returncode,p.stdout,p.stderr)
  assert snapshot()==before,'report wrote repository state'
  return p.stdout.decode()
 def sizes(s):return [r for r in map(json.loads,s.splitlines()) if r['kind']=='size']
 def objects(s,kind):return [r for r in map(json.loads,s.splitlines()) if r['kind']==kind]
 if case=='v1-107.basic':
  calls.unlink(missing_ok=True);s=report([row()]);measured_calls=data(calls)
  calls.unlink();legacy=row();legacy.pop('product_lines');legacy.pop('warn_lines');report([legacy])
  assert data(calls)==measured_calls and not ghcalls.exists(),'size added a Git read or network call'
  assert sizes(s)==[{'kind': 'size', 'prs': 1, 'above': 1, 'above_share': 1.0, 'merged_prs': 0, 'merged_above': 0, 'merged_above_share': None}],s
 elif case=='v1-107.boundary':
  s=report([row(pr=1,product_lines=500),row(pr=2,product_lines=499),row(pr=3,product_lines=0,warn_lines=0),row(pr=4,product_lines=1,warn_lines=0)])
  assert sizes(s)==[{'kind': 'size', 'prs': 4, 'above': 1, 'above_share': 0.25, 'merged_prs': 0, 'merged_above': 0, 'merged_above_share': None}],s
 elif case=='v1-107.last-row':
  s=report([row(at=9999),row(product_lines=2,at=1),row(pr=2,product_lines=3,at=1000),row(pr=2,product_lines=700,at=0)])
  assert sizes(s)==[{'kind': 'size', 'prs': 2, 'above': 1, 'above_share': 0.5, 'merged_prs': 0, 'merged_above': 0, 'merged_above_share': None}],s
 elif case=='v1-107.last-limit':
  s=report([row(product_lines=450,warn_lines=400),row(product_lines=450,warn_lines=999),row(pr=2,product_lines=300,warn_lines=500),row(pr=2,product_lines=300,warn_lines=200)])
  assert sizes(s)==[{'kind': 'size', 'prs': 2, 'above': 1, 'above_share': 0.5, 'merged_prs': 0, 'merged_above': 0, 'merged_above_share': None}],s
 elif case=='v1-107.results':
  s=report([row(pr=i,product_lines=i,warn_lines=1,result=result) for i,result in enumerate(['passed','refused','error','unknown',None],1)])
  assert sizes(s)==[{'kind': 'size', 'prs': 5, 'above': 4, 'above_share': 0.8, 'merged_prs': 0, 'merged_above': 0, 'merged_above_share': None}],s
 elif case=='v1-107.invalid-pr':
  rs=[row(pr=8,product_lines=0)]
  for value in (0,-1,True,False,1.0,'2',None,[],{}):rs.append(row(pr=value))
  r=row();r.pop('pr');rs.append(r)
  s=report(rs);assert not objects(s,'gap'),s
  assert sizes(s)==[{'kind': 'size', 'prs': 1, 'above': 0, 'above_share': 0.0, 'merged_prs': 0, 'merged_above': 0, 'merged_above_share': None}],s
 elif case=='v1-107.invalid-size':
  rs=[row(pr=8,product_lines=0)]
  for value in (-1,True,False,1.0,'2',None,[],{}):rs.append(row(pr=8,product_lines=value,warn_lines=0))
  r=row(pr=8);r.pop('product_lines');rs.append(r)
  rs.extend([row(layer='ci'),row(layer='review'),row(layer='PR'),row(escape=True)])
  s=report(rs);assert not objects(s,'gap'),s
  assert sizes(s)==[{'kind': 'size', 'prs': 1, 'above': 0, 'above_share': 0.0, 'merged_prs': 0, 'merged_above': 0, 'merged_above_share': None}],s
 elif case=='v1-107.invalid-limit':
  rs=[row(pr=8,product_lines=1,warn_lines=9)]
  for value in (-1,True,False,0.0,'0',None,[],{}):rs.append(row(pr=8,warn_lines=value))
  r=row(pr=8);r.pop('warn_lines');rs.append(r)
  s=report(rs);assert not objects(s,'gap'),s
  assert sizes(s)==[{'kind': 'size', 'prs': 1, 'above': 0, 'above_share': 0.0, 'merged_prs': 0, 'merged_above': 0, 'merged_above_share': None}],s
 elif case=='v1-107.integers':
  rs=[row(pr=18446744073709551615,product_lines=18446744073709551615,warn_lines=18446744073709551614),row(pr=9007199254740992,product_lines=0),row(pr=9007199254740993,product_lines=1,warn_lines=1)]
  raw=wire(rs)
  for field in ('pr','product_lines','warn_lines'):
   for token in ('1e0','1.0','18446744073709551616','-0'):
    r=row(pr=42,warn_lines=0);r[field]='TOKEN107';raw+=wire([r]).replace(b'"TOKEN107"',token.encode())
  s=report(raw);assert not objects(s,'gap'),s
  assert sizes(s)==[{'kind': 'size', 'prs': 3, 'above': 1, 'above_share': 0.3333333333333333, 'merged_prs': 0, 'merged_above': 0, 'merged_above_share': None}],s
 elif case=='v1-107.merge':
  s=report([row(pr=1),row(pr=2,product_lines=400),row(pr=3),row('merge',pr=1,locks=[]),row('merge',pr=1,locks=['irrelevant']),row('merge',pr=2,base='trunk',default_branch='trunk'),row('merge',pr=99)])
  assert sizes(s)==[{'kind': 'size', 'prs': 3, 'above': 2, 'above_share': 0.6666666666666666, 'merged_prs': 2, 'merged_above': 1, 'merged_above_share': 0.5}],s
 elif case=='v1-107.merge-filter':
  rs=[row(),row(pr=2,product_lines=0)]
  rs += [row('merge',result=result) for result in ('refused','error','PASSED',None)]
  rs += [row('merge',base='topic'),row('merge',escape=True),row('merge',pr=2)]
  s=report(rs)
  assert sizes(s)==[{'kind': 'size', 'prs': 2, 'above': 1, 'above_share': 0.5, 'merged_prs': 1, 'merged_above': 0, 'merged_above_share': 0.0}],s
 elif case=='v1-107.merge-types':
  rs=[row(),row(pr=2,product_lines=0)]
  for key in ('base','default_branch'):
   for value in (None,False,0,[],{}):rs.append(row('merge',**{key:value}))
   r=row('merge');r.pop(key);rs.append(r)
  for value in (True,1.0,'1',None,0,-1,[],{}):rs.append(row('merge',pr=value))
  rs.extend([row('merge',base=None,default_branch=None),row('merge',pr=2)])
  s=report(rs)
  assert sizes(s)==[{'kind': 'size', 'prs': 2, 'above': 1, 'above_share': 0.5, 'merged_prs': 1, 'merged_above': 0, 'merged_above_share': 0.0}],s
 elif case=='v1-107.freeze':
  s=report([row(at=999),row('merge',at=5),row(product_lines=0,at=1),row('merge',at=10000),row(pr=2,product_lines=0),row('merge',pr=2),row(pr=2,product_lines=9999)])
  assert sizes(s)==[{'kind': 'size', 'prs': 2, 'above': 1, 'above_share': 0.5, 'merged_prs': 2, 'merged_above': 1, 'merged_above_share': 0.5}],s
 elif case=='v1-107.after-merge':
  s=report([row('merge',pr=9),row(pr=9),row(pr=8,product_lines=None),row('merge',pr=8),row(pr=8),row(pr=3,product_lines=0),row('merge',pr=3,result='refused'),row(pr=3,product_lines=501),row('merge',pr=3)])
  assert sizes(s)==[{'kind': 'size', 'prs': 1, 'above': 1, 'above_share': 1.0, 'merged_prs': 1, 'merged_above': 1, 'merged_above_share': 1.0}],s
 elif case=='v1-107.reader':
  raw=b'\xef\xbb\xbf'+wire([row(pr=7,reason='quoted \" spaces \u2028\u2029')]).replace(b'\n',b'\r\n')+b'  \t\r\n'
  raw+=wire([row(pr=8,product_lines=0,reason='INVALID107')]).replace(b'INVALID107',b'\xff')
  raw+=wire([row(pr=8,product_lines=999)]).replace(b'"product_lines": 999',b'"product_lines": 999, "product_lines": 0')
  raw+=wire([row('merge',pr=7)])[:-1]
  s=report(raw);assert not objects(s,'gap'),s
  assert sizes(s)==[{'kind': 'size', 'prs': 2, 'above': 1, 'above_share': 0.5, 'merged_prs': 1, 'merged_above': 1, 'merged_above_share': 1.0}],s
 elif case=='v1-107.malformed':
  raw=wire([row(pr=7)])+b'{broken107\n[]\nnull\n'+wire([row(pr=7,product_lines='OVER107')]).replace(b'"OVER107"',b'1e400')+wire([row(pr=8,product_lines=0)])
  s=report(raw);assert [r['line'] for r in objects(s,'gap')]==[2,3,4,5],s
  assert sizes(s)==[{'kind': 'size', 'prs': 2, 'above': 1, 'above_share': 0.5, 'merged_prs': 0, 'merged_above': 0, 'merged_above_share': None}],s
 elif case=='v1-107.order':
  rs=[row('red',lock='A',at=1),row('close',lock='A',at=2),row(lock='A',locks=['A'],at=3),row('merge',lock='A',locks=['A'],at=4)]
  s=report(wire(rs)+b'{broken107\n')
  assert [r['kind'] for r in map(json.loads,s.splitlines())]==['meta','lock','day','size','merged_pr','week']+['size_bucket']*8+['limit','dora','gap'],s
  text=report(wire(rs)+b'{broken107\n',args=());lines=text.splitlines();i=next(i for i,l in enumerate(lines) if l.startswith('size:'));assert lines[i-1].startswith('day ') and lines[i+1].startswith('pr #1:'),text
  assert sizes(s)==[{'kind': 'size', 'prs': 1, 'above': 1, 'above_share': 1.0, 'merged_prs': 1, 'merged_above': 1, 'merged_above_share': 1.0}],s
 elif case=='v1-107.text-fraction':
  rs=[row(pr=1),row(pr=2,product_lines=0),row(pr=3),row('merge',pr=1),row('merge',pr=2)]
  s=report(rs,args=());assert [l for l in s.splitlines() if l.startswith('size:')]==['size: 3 PR(s) measured, 2 above their limit (67%); merged 2, 1 above (50%)'],s
  assert s.index('size:')<s.index('DORA'),s
 elif case=='v1-107.text-zero':
  s=report([row(product_lines=0)],args=());assert [l for l in s.splitlines() if l.startswith('size:')]==['size: 1 PR(s) measured, 0 above their limit (0%); merged 0, 0 above (-)'],s
  j=report([row(product_lines=0)]);r=sizes(j);assert r and type(r[0]['above_share']) is int and r[0]['merged_above_share'] is None,j
 elif case=='v1-107.text-full':
  rs=[row(),row('merge')];s=report(rs,args=());assert [l for l in s.splitlines() if l.startswith('size:')]==['size: 1 PR(s) measured, 1 above their limit (100%); merged 1, 1 above (100%)'],s
  j=report(rs);r=sizes(j);assert r and type(r[0]['above_share']) is int and type(r[0]['merged_above_share']) is int,j
 elif case=='v1-107.since':
  rs=[row(at=1),row('merge',at=2),row(pr=2,product_lines=0,at=3)]
  s=report(rs,args=('--since','v2.0.0','--json'))
  assert objects(s,'dora')[0]['deploys']['n']==1 and objects(s,'dora')[0]['git']['releases']==2,s
  assert sizes(s)==sizes(report(rs)),s
  a=report(rs,args=('--since','v2.0.0'));b=report(rs,args=());assert [l for l in a.splitlines() if l.startswith('size:')]==[l for l in b.splitlines() if l.startswith('size:')],(a,b)
  assert sizes(s)==[{'kind': 'size', 'prs': 2, 'above': 1, 'above_share': 0.5, 'merged_prs': 1, 'merged_above': 1, 'merged_above_share': 1.0}],s
 elif case=='v1-107.github':
  rs=[row('red',pr=97,lock='gh107',at=1),row('close',pr=97,lock='gh107',at=2),row(pr=97,lock='gh107',locks=['gh107'],at=3),row('merge',pr=97,lock='gh107',locks=['gh107'],at=4)]
  s=report(rs,args=('--json','--github'));assert data(ghcalls)==[['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']],data(ghcalls)
  assert sizes(s)==sizes(report(rs)),s
  # A later network failure changes only GitHub coverage, never the local measurement.
  ghfault.touch();s=report(rs,args=('--json','--github'));assert objects(s,'github')[0]['missing']=={'gh failed':1},s
  assert sizes(s)==[{'kind': 'size', 'prs': 1, 'above': 1, 'above_share': 1.0, 'merged_prs': 1, 'merged_above': 1, 'merged_above_share': 1.0}],s
 elif case=='v1-107.git-failure':
  fault.touch();s=report([row(),row('merge')]);assert objects(s,'dora')[0]['git']['reason'].endswith('exited 93'),s
  assert sizes(s)==[{'kind': 'size', 'prs': 1, 'above': 1, 'above_share': 1.0, 'merged_prs': 1, 'merged_above': 1, 'merged_above_share': 1.0}],s
 elif case=='v1-107.config-failure':
  write('.shipcraft.toml','[report]\nrelease_tags=""\n');s=report([row(),row('merge')]);assert objects(s,'dora')[0]['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags is empty',s
  assert sizes(s)==[{'kind': 'size', 'prs': 1, 'above': 1, 'above_share': 1.0, 'merged_prs': 1, 'merged_above': 1, 'merged_above_share': 1.0}],s
 elif case=='v1-107.control-report':
  # Legacy byte preservation, same reader/proxies, and absent/unreadable logs.
  rs=[row('red',lock='control107',at=17),row('close',lock='control107',at=29),row('merge',lock='control107',at=47)]
  for r in rs:r.pop('product_lines');r.pop('warn_lines')
  s=report(rs);assert not sizes(s) and objects(s,'lock')[0]['red_to_merge']==30 and objects(s,'day')[0]['merged_locks']==1,s
  assert objects(s,'dora')[0]['git']['releases']==2,s
  text=report(rs,args=());assert 'size:' not in text and 'control107' in text and '30 s' in text,text
  ignored=[row(pr=0),row(product_lines=None),row(layer='ci'),row(escape=True)]
  s=report(ignored);assert not sizes(s) and not objects(s,'gap'),s
  s=report([row('merge'),row()]);assert not sizes(s),s
  text=report([row('merge'),row()],args=());assert 'size:' not in text,text
  empty=report([]);emptytext=report([],args=());log.unlink()
  p=run(binary,'report','--json');assert p.returncode==0 and p.stdout.decode()==empty,(p.stdout,empty)
  log.mkdir();p=run(binary,'report');assert p.returncode==0 and p.stdout.decode()==emptytext,(p.stdout,emptytext)
  log.rmdir()
  fault.touch();s=report(rs);assert objects(s,'dora')[0]['git']['reason'].endswith('exited 93') and objects(s,'lock')[0]['red_to_merge']==30,s
  assert data(calls) and not ghcalls.exists(),'report probes not routed offline'
 elif case=='v1-107.control-github':
  rs=[row('red',pr=97,lock='gh107',at=1),row('close',pr=97,lock='gh107',at=2),row(pr=97,lock='gh107',locks=['gh107'],at=3),row('merge',pr=97,lock='gh107',locks=['gh107'],at=4)]
  for r in rs:r.pop('product_lines');r.pop('warn_lines')
  s=report(rs,args=('--json','--github'));assert objects(s,'github')[0]['missing']=={'pr not merged':1},s
  assert data(ghcalls)==[['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']],data(ghcalls)
  ghfault.touch();s=report(rs,args=('--json','--github'));assert objects(s,'github')[0]['missing']=={'gh failed':1},s
  assert not sizes(s) and objects(s,'lock')[0]['lock']=='gh107',s
 else:raise AssertionError('unrouted case: '+case)
 if 's' in locals() and s.startswith('{'):
  for r in sizes(s):
   assert set(r)=={'kind','prs','above','above_share','merged_prs','merged_above','merged_above_share'},r
   assert all(type(r[k]) is int for k in ('prs','above','merged_prs','merged_above')),r
   assert type(r['above_share']) in (int,float) and (r['merged_above_share'] is None or type(r['merged_above_share']) in (int,float)),r
PY107
  pass
}
