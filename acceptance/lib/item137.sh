# Item 137: release selection at RED and format 6; public commands only.
item137_langs() { echo core; }
item137_cases() {
  local c
  for c in repro annotated nonutf8 presence missing git-fail git-output default-refusal precedence red-suite-fails red-log-fails control-red control-pattern control-report control-fault control-shallow control-wire report-bare report-readers report-since report-missing report-since-unavailable report-label-window report-merge migration order-numeric order-name report-filter report-fix report-late-fail readme-step readme-install readme-lockfiles; do echo "v1-137.$c"; done
}
item137_case() {
  EXPECT="item 137: ${CASE#v1-137.}"; v1_start codex
  must_accept 'project fixes_release contract' cmd "$PY" - "${CASE#v1-137.}" "$(command -v shipcraft)" "$CW" "$ACEITE/../README.md" <<'PY137'
import hashlib,json,os,shlex,shutil,subprocess,sys
from pathlib import Path
case,binary,cw,readme=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/'repo137 space';root.mkdir();os.chdir(root)
env=dict(os.environ)
for k in subprocess.check_output(['git','rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
def run(*args):
 p=subprocess.run(list(map(str,args)),env=env,input='',capture_output=True,text=True,timeout=60)
 print('$',shlex.join(list(map(str,args))),'rc',p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 return p
def git(*args):
 p=run('git',*args);assert p.returncode==0,('fixture git',p.stderr);return p.stdout.strip()
def write(name,data):
 p=Path(name);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
stamp=1700000000
def commit():
 global stamp
 stamp+=86400;env['GIT_AUTHOR_DATE']=str(stamp)+' +0000';env['GIT_COMMITTER_DATE']=str(stamp)+' +0000'
 git('add','-A');git('-c','core.hooksPath=/dev/null','commit','-qm','fixture137')
def rows():
 p=Path('.git/shipcraft/runs.jsonl');return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def locks():return sorted(Path('.shipcraft/locks').glob('*.json'))
def snapshot():return {str(p):(p.lstat().st_mode,p.read_bytes() if p.is_file() else None) for p in Path('.').rglob('*') if '__pycache__' not in p.parts and '.pytest_cache' not in p.parts}
def seal(d):
 c={k:d[k] for k in ('format','state','files','cases','failing_at_red')};c['files']=dict(sorted(c['files'].items()))
 if d['format'] in (5,6):c['controls']=d['controls']
 if d['format'] in (4,5,6):c.update((k,d[k]) for k in ('kind','reported_at','fixes_release'))
 c['seal']='';return hashlib.sha256(json.dumps(c,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
def store(d):
 d['seal']=seal(d);lock.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
def fixture():
 git('init','-q','-b','main');git('config','user.name','RED137');git('config','user.email','red137@example.invalid')
 write('requirements.txt','pytest\n');p=run(binary,'init');assert p.returncode==0,(p.stdout,p.stderr)
 write('.gitignore','__pycache__/\n.pytest_cache/\nobserved137\nfail137\n')
 write('value137','red');write('.shipcraft.toml',base);commit()
 write('tests/test_value137.py','from pathlib import Path\ndef test_target137():\n    assert Path("value137").read_text()=="green"\ndef test_control137():\n    assert True\n')
def fresh(n):
 global root
 root=cw/('variant137-'+str(n));root.mkdir();os.chdir(root);fixture()
base='shipcraft_min="0.0"\nlang="python"\nrunner="pytest"\ntest_command="pytest -q --junitxml={junit} tests"\ntest_globs=["tests/**"]\ncheck="echo suite137 >> observed137; test ! -f fail137"\n[execution]\nci="local"\nreview="off"\n'
pattern='[report]\nrelease_tags="deploy-*"\n';tag='deploy-20261112-200036';time='2026-11-12T20:00:36-03:00'
fixture()
# Record/delegate real Git; fault injection is limited to the requested read.
realgit=shutil.which('git');tools=cw/'tools137';tools.mkdir();calls=cw/'calls137';fault=cw/'fault137';hit=cw/'hit137'
localvars=subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']
proxy=tools/'git'
proxy.write_text('#!'+sys.executable+'\n'+r'''
import json,os,signal,subprocess,sys
from pathlib import Path
a=sys.argv[1:]
with open(CALLS,'a') as f:f.write(json.dumps(dict(args=a,env={k:os.environ.get(k) for k in VARS+['GIT_NO_LAZY_FETCH','GIT_TERMINAL_PROMPT']}))+'\n')
mode=Path(FAULT).read_text() if Path(FAULT).exists() else ''
if ('for-each-ref' in a and mode in ('exit','signal','truncated','cr','space')) or ('log' in a and mode=='late'):
 Path(HIT).write_text(mode)
 if mode in ('exit','late'):raise SystemExit(93)
 if mode=='signal':os.kill(os.getpid(),signal.SIGTERM)
 p=subprocess.run([REAL,*a],capture_output=True)
 if p.returncode:raise SystemExit(p.returncode)
 data=p.stdout
 if mode=='truncated':data=data.rstrip(b'\n')
 if mode=='cr':data=data.replace(b'\n',b'\r\n')
 if mode=='space':data=b' '+data
 sys.stdout.buffer.write(data);raise SystemExit(0)
os.execve(REAL,[REAL,*a],dict(os.environ))
'''.replace('CALLS',repr(str(calls))).replace('VARS',repr(localvars)).replace('FAULT',repr(str(fault))).replace('HIT',repr(str(hit))).replace('REAL',repr(realgit)))
proxy.chmod(0o755);env['PATH']=str(tools)+os.pathsep+env['PATH']
# Fixture Git bypasses the recording proxy; only public-command reads are recorded.
def git(*args):
 p=run(realgit,*args);assert p.returncode==0,('fixture git',p.stderr);return p.stdout.strip()
def reads():return [json.loads(x) for x in calls.read_text().splitlines()] if calls.exists() else []
def report(*args):
 before=snapshot();p=run(binary,'report',*args);assert snapshot()==before,'report wrote state';return p
def decode(p):return next(json.loads(x) for x in p.stdout.splitlines() if json.loads(x)['kind']=='dora')
def releases(first='0.162.7',second='0.164.0'):
 # Real annotated and lightweight tags on distinct commits.
 git('tag','-a',first,'-m','release137');write('next137','second');commit();git('tag',second)
def closed(id,fixes=None):
 d=dict(format=6 if fixes else 5,state='closed',files={},cases=[],failing_at_red=[],controls=[],kind='fix' if fixes else 'feature',reported_at='2023-11-14T22:13:20Z' if fixes else None,fixes_release=fixes,seal='')
 d['seal']=seal(d);write('.shipcraft/locks/'+id+'.json',json.dumps(d)+'\n')
if case=='repro':
 git('tag','0.162.7');git('tag','0.164.0')
 p=run(binary,'red','--fix','--reported-at','2026-11-18T16:20-03:00','--fixes-release','0.162.7')
 assert p.returncode==0,(p.stdout,p.stderr)
 d=json.loads(locks()[0].read_text());assert (d['format'],d['kind'],d['reported_at'],d['fixes_release'])==(6,'fix','2026-11-18T16:20-03:00','0.162.7'),d
 assert rows()[-1]['fixes_release']=='0.162.7' and d['seal']==seal(d),d
elif case=='annotated':
 git('tag','-a','0.162.7','-m','annotated137');p=run(binary,'red','--fix','--fixes-release','0.162.7')
 assert p.returncode==0,(p.stdout,p.stderr)
 d=json.loads(locks()[0].read_text());assert d['format']==6 and d['fixes_release']=='0.162.7' and d['seal']==seal(d),d
elif case=='nonutf8':
 git('tag','0.162.7');sha=git('rev-parse','HEAD')
 git('tag','odd-x');git('pack-refs','--all','--prune');packed=Path('.git/packed-refs');packed.write_bytes(packed.read_bytes().replace(b'refs/tags/odd-x',b'refs/tags/odd-\xff'))
 listed=subprocess.check_output([realgit,'for-each-ref','refs/tags','--format=%(refname:strip=2)'],env=env);assert b'odd-\xff\n' in listed and b'0.162.7\n' in listed,listed
 p=run(binary,'red','--fix','--fixes-release','0.162.7');assert p.returncode==0,(p.stdout,p.stderr)
 assert json.loads(locks()[0].read_text())['fixes_release']=='0.162.7'
elif case=='presence':
 blob=subprocess.check_output([realgit,'hash-object','-w','--stdin'],input=b'blob137',env=env).decode().strip();git('tag','1.2.3',blob)
 git('checkout','-qb','side137');write('side137','side');commit();git('tag','1.2.4');git('checkout','-q','main')
 write('tests/test_value137.py','def test_presence137(): assert False\n')
 for t in ('1.2.3','1.2.4'):
  before={p.name for p in locks()};p=run(binary,'red','--fix','--fixes-release',t);assert p.returncode==0,(t,p.stdout,p.stderr)
  lock=next(p for p in locks() if p.name not in before);assert json.loads(lock.read_text())['fixes_release']==t
  lock.unlink()
elif case in ('missing','git-fail','git-output','default-refusal','precedence'):
 variants=['empty','other','prefix','path']
 if case=='git-fail':variants=['exit','signal']
 if case=='git-output':variants=['truncated','cr','space']
 if case=='default-refusal':variants=['missing','directory','utf8','toml','empty','deploy']
 if case=='precedence':
  p=run(binary,'red');assert p.returncode==0,(p.stdout,p.stderr);commit();variants=['minimum','toml']
 for variant in variants:
  git('tag','-l')
  for t in git('tag','-l').splitlines():git('tag','-d',t)
  config=Path('.shipcraft.toml')
  if config.is_dir():config.rmdir()
  write(config,base)
  if variant=='other':git('tag','v1.2.3')
  if variant=='prefix':git('tag','1.2.30')
  if variant=='path':git('tag','rel/1.2.3')
  if variant in ('exit','signal','truncated','cr','space'):git('tag','1.2.3');fault.write_text(variant)
  if variant=='missing':config.unlink()
  if variant=='directory':config.unlink();config.mkdir()
  if variant=='utf8':write(config,b'\xff')
  if variant=='toml':write(config,'broken [\n')
  if variant=='empty':write(config,base+'[report]\n')
  if variant=='deploy':write(config,base+'[report]\ndeploy="merge"\n')
  if variant=='minimum':write(config,base.replace('0.0','99999.0'))
  before=snapshot();calls.unlink(missing_ok=True);p=run(binary,'red','--fix','--fixes-release','1.2.3')
  assert p.returncode==2 and p.stdout=='' and p.stderr.splitlines()==['shipcraft: --fixes-release 1.2.3 is not a tag in this clone','Why: without [report] release_tags, red takes a release tag without v only when this clone holds a tag of that name, since an X.Y.Z number may name no release of this project.',"Next: fetch the project's tags (git fetch --tags), or pass the tag of the release that shipped the defect, or set [report] release_tags in .shipcraft.toml, then run red again."],(variant,p.stdout,p.stderr)
  assert snapshot()==before,'refusal wrote state'
  rr=reads();assert len(rr)==1 and rr[0]['args']==['-C',str(root),'for-each-ref','refs/tags','--format=%(refname:strip=2)'],rr
  assert all(rr[0]['env'][k] is None for k in localvars) and rr[0]['env']['GIT_NO_LAZY_FETCH']=='1' and rr[0]['env']['GIT_TERMINAL_PROMPT']=='0',rr
elif case=='red-suite-fails':
 git('tag','0.162.7');write('fail137','fail');p=run(binary,'red','--fix','--fixes-release','0.162.7')
 assert p.returncode==1 and not locks(),(p.stdout,p.stderr)
 assert rows()[-1]['result']=='refused' and rows()[-1]['kind']=='fix' and rows()[-1]['fixes_release']=='0.162.7',rows()
elif case=='red-log-fails':
 git('tag','0.162.7');log=Path('.git/shipcraft/runs.jsonl');log.unlink(missing_ok=True);log.mkdir(parents=True)
 p=run(binary,'red','--fix','--fixes-release','0.162.7');assert p.returncode==0 and len(locks())==1,(p.stdout,p.stderr)
 d=json.loads(locks()[0].read_text());assert d['format']==6 and d['fixes_release']=='0.162.7' and d['seal']==seal(d),d
elif case=='control-red':
 fault.write_text('exit');p=run(binary,'red','--fix','--fixes-release','v1.2.3');assert p.returncode==0,(p.stdout,p.stderr)
 d=json.loads(locks()[0].read_text());assert d['format']==5 and d['fixes_release']=='v1.2.3' and d['controls']==['tests.test_value137::test_control137'] and d['failing_at_red']==['tests.test_value137::test_target137'] and d['seal']==seal(d),d
 assert rows()[-1]['fixes_release']=='v1.2.3' and not hit.exists() and not any('for-each-ref' in r['args'] for r in reads()),reads()
elif case=='control-pattern':
 write('.shipcraft.toml',base+'[report]\nrelease_tags="rel*"\n');fault.write_text('exit')
 p=run(binary,'red','--fix','--fixes-release','rel-missing');assert p.returncode==0,(p.stdout,p.stderr)
 d=json.loads(locks()[0].read_text());assert d['format']==6 and d['fixes_release']=='rel-missing' and not hit.exists() and not any('for-each-ref' in r['args'] for r in reads()),d
elif case=='control-report':
 releases('v1.2.3','v2.0.0');d=decode(report('--json'))
 assert d['git']['releases']==2 and d['git']['release_tags'] is None and d['git']['deploy']=='release' and d['deploys']['n']==2,d
 assert 'release tags: vX.Y.Z' in report().stdout
 write('.shipcraft.toml',base+'[report]\nrelease_tags="deploy-*"\n');git('tag','0.162.7');git('tag','deploy-one');d=decode(report('--json'))
 assert d['git']['release_tags']=='deploy-*' and d['git']['releases']==1,d
elif case=='control-fault':
 releases('v1.2.3','v2.0.0');fault.write_text('late');d=decode(report('--json'))
 assert hit.read_text()=='late' and d['git']['reason'].endswith('exited 93') and d['git']['releases'] is None and d['git']['release_tags'] is None,d
elif case=='control-shallow':
 releases();origin=root;clone=cw/'shallow137';git('clone','--no-local','--depth=1',origin.as_uri(),clone);root=clone;os.chdir(root)
 d=decode(report('--json'));assert d['git']['reason']=='shallow clone: history incomplete' and d['git']['release_tags'] is None and d['git']['releases'] is None,d
 assert 'release tags: vX.Y.Z' in report().stdout and not any('for-each-ref' in r['args'] for r in reads()),reads()
elif case=='control-wire':
 closed('A');commit();git('tag','v0.9.0');closed('B');stamp-=86400;commit();git('tag','v0.10.0');d=decode(report('--json','--since','v0.10.0'))
 assert d['git']['releases']==2 and d['deploys']['n']==2 and d['rework_rate']['n']==2 and d['rework_rate']['value']==0,d
 closed('C','deploy-old');commit();git('tag','deploy-old','HEAD~1');git('tag','deploy-new');write('.shipcraft.toml',base+'[report]\nrelease_tags="deploy-*"\n');d=decode(report('--json'))
 assert d['change_failure_rate']==dict(value=0.5,n=2,missing=0,reason=None),d
elif case=='report-bare':
 releases();d=decode(report('--json'))
 assert d['git']==dict(default_branch='refs/heads/main',deploy='release',deploy_source='default',merges=None,reason=None,release_tags='vX.Y.Z or X.Y.Z',releases=2),d
 assert d['deploys']['n']==2 and d['deploys']['value']['first']==stamp-86400 and d['deploys']['value']['last']==stamp,d
 text=report().stdout
 assert 'git: default branch refs/heads/main; 2 release(s); lock rows without log times come from the branch tip; release tags: vX.Y.Z or X.Y.Z' in text,text
 rr=reads();assert sum('for-each-ref' in r['args'] for r in rr)==2,rr
elif case=='report-readers':
 releases();observed=[]
 for body in (None,'DIRECTORY',b'\xff','broken [\n',base,base+'[report]\n',base+'[report]\ndeploy="release"\n'):
  config=Path('.shipcraft.toml')
  if config.is_dir():config.rmdir()
  if body is None:config.unlink(missing_ok=True)
  elif body=='DIRECTORY':config.unlink(missing_ok=True);config.mkdir()
  else:write(config,body)
  observed.append(decode(report('--json')))
 assert all(d['git']['releases']==2 and d['git']['release_tags']=='vX.Y.Z or X.Y.Z' and d['deploys']['n']==2 for d in observed),observed
elif case=='report-since':
 releases();p=report('--json','--since','0.164.0');assert p.returncode==0,(p.stdout,p.stderr)
 d=decode(p);assert d['since']=='0.164.0' and d['deploys']['n']==1 and d['git']['releases']==2 and d['git']['release_tags']=='vX.Y.Z or X.Y.Z',d
elif case=='report-missing':
 releases();p=report('--json','--since','0.200.0')
 assert p.returncode==2 and p.stdout=='' and p.stderr=='report: --since 0.200.0 is not a release tag on refs/heads/main\n',(p.stdout,p.stderr)
elif case=='report-since-unavailable':
 releases();git('branch','-m','topic137');p=report('--json','--since','0.164.0');assert p.returncode==0,(p.stdout,p.stderr)
 d=decode(p);assert d['since']=='0.164.0' and d['git']['reason']=='no default branch' and d['git']['release_tags'] is None,d
elif case=='report-label-window':
 releases('0.162.7','v2.0.0');d=decode(report('--json','--since','v2.0.0'))
 assert d['deploys']['n']==1 and d['git']['release_tags']=='vX.Y.Z or X.Y.Z' and d['git']['releases']==2,d
 assert 'release tags: vX.Y.Z or X.Y.Z' in report('--since','v2.0.0').stdout
elif case=='report-merge':
 releases();write('.shipcraft.toml',base+'[report]\ndeploy="merge"\n');d=decode(report('--json'))
 assert d['git']['deploy']=='merge' and d['git']['deploy_source']=='config' and d['git']['releases']==2 and d['git']['release_tags']=='vX.Y.Z or X.Y.Z',d
 assert 'release tags: vX.Y.Z or X.Y.Z; deploys are merges to the default branch ([report] deploy = "merge")' in report().stdout
elif case=='migration':
 releases();sha=git('rev-parse','HEAD');p=report('--json','--since',sha)
 assert p.returncode==2 and 'invalid arguments:' in p.stderr and 'usage:' in p.stderr,(p.stdout,p.stderr)
 write('.shipcraft.toml',base+'[report]\ndeploy="merge"\n');p=report('--json','--since',sha);assert p.returncode==0,(p.stdout,p.stderr)
 d=decode(p);assert d['git']['deploy']=='merge' and d['since']==sha and d['deploys']['n']==1,d
elif case=='order-numeric':
 closed('A');commit();git('tag','0.9.0');closed('B');stamp-=86400;commit();git('tag','0.10.0');git('tag','100000000000000000000000000000.0.0')
 p=report('--json','--since','0.10.0');assert p.returncode==0,(p.stdout,p.stderr)
 d=decode(p);assert d['git']['releases']==3 and d['deploys']['n']==3 and d['rework_rate']['n']==2,d
elif case=='order-name':
 closed('A');commit();git('tag','1.2.3');closed('B');stamp-=86400;commit();git('tag','v1.2.3');git('tag','2.0.0');git('tag','v2.0.0');p=report('--json','--since','v1.2.3');assert p.returncode==0,(p.stdout,p.stderr)
 d=decode(p);assert d['git']['releases']==4 and d['deploys']['n']==4 and d['rework_rate']['n']==2,d
elif case=='report-filter':
 releases()
 for t in ('1.2','01.2.3','1.02.3','1.2.03','1.2.3rc1','1.2.3-rc.1','1.2.3+build'):git('tag',t)
 blob=subprocess.check_output([realgit,'hash-object','-w','--stdin'],input=b'blob137',env=env).decode().strip();git('tag','9.0.0',blob)
 git('checkout','-qb','side137');write('side137','side');commit();git('tag','8.0.0');git('checkout','-q','main')
 d=decode(report('--json'));assert d['git']['releases']==2 and d['git']['release_tags']=='vX.Y.Z or X.Y.Z',d
elif case=='report-fix':
 closed('A');commit();git('tag','0.162.7');closed('B','0.162.7');commit();git('tag','0.164.0');d=decode(report('--json'))
 assert d['git']['deploy']=='release' and d['change_failure_rate']==dict(value=0.5,n=2,missing=0,reason=None),d
elif case=='report-late-fail':
 releases();fault.write_text('late');p=report('--json','--since','0.164.0');assert p.returncode==0,(p.stdout,p.stderr)
 d=decode(p);assert hit.read_text()=='late' and d['git']['reason'].endswith('exited 93') and d['git']['release_tags'] is None and d['since']=='0.164.0',d
elif case=='readme-step':
 text=Path(readme).read_text();new="From the npm package, step 2 is `pnpm exec shipcraft init`, or `npx -- shipcraft init` with npm, yarn or bun (the hooks run this install from `node_modules/.bin`, so Yarn Plug'n'Play is not supported)."
 assert text.count(new)==1 and 'From the npm package, step 2 is `pnpm exec shipcraft init` or `npx -- shipcraft init`.' not in text
elif case=='readme-install':
 text=Path(readme).read_text();new='pnpm add -D shipcraft          # step 1, or: npm i -D shipcraft, yarn add -D shipcraft (yarn 1 at a workspaces root: yarn add -D -W shipcraft), bun add -d shipcraft'
 assert text.splitlines().count(new)==1 and 'pnpm add -D shipcraft          # step 1, or: npm i -D shipcraft' not in text.splitlines()
elif case=='readme-lockfiles':
 text=Path(readme).read_text();new='                                      # and package.json with its lockfile (pnpm-lock.yaml, package-lock.json, yarn.lock or bun.lock)'
 assert text.splitlines().count(new)==1 and '                                      # and package.json with pnpm-lock.yaml or package-lock.json' not in text.splitlines()
else:raise AssertionError(case)
PY137
  pass
}
