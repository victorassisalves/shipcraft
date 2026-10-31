# Item 76: public report, real Git history and independently sealed wire fixtures.
item76_langs() { echo core; }
item76_cases() {
  local c
  for c in metrics removed since since-order since-empty since-unavailable since-not-release since-offline-tag \
    text text-empty since-text-coverage rows states kinds-tip kinds-release kinds-head kinds-red kinds-legacy kinds-legacy2 invalid-seal invalid-schema \
    lead-missing lead-nonpositive lead-redo recover-missing recover-nonpositive recover-offset \
    rework-unknown failure-unknown failure-absent failure-null failure-scoped first-shipment \
    tags tag-blob tag-no-tagger tie tie-huge origin-main local-main origin-head master no-default \
    nested environment signed shallow partial git-absent git-failure git-late-failure git-bad-time git-bad-shallow git-missing-object git-bad-utf8 \
    empty no-releases readonly invalid-config log-directory worktree removed-no-log since-partial; do echo "v1-76.$c"; done
  for c in true yes on one mixed false zero legacy; do echo "v1-76.promisor-$c"; done
  for c in missing repeat-json repeat-since unknown extra leading-zero unicode suffix empty flag-value; do echo "v1-76.arguments-$c"; done
}
item76_case() {
  EXPECT="item 76: ${CASE#v1-76.}"
  v1_start codex
  must_accept 'DORA report contract' cmd "$PY" - "${CASE#v1-76.}" "$(command -v shipcraft)" "$CW" <<'PY76'
import datetime,hashlib,json,os,re,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
realgit=shutil.which('git');root=cw/'repo76 space';root.mkdir();os.chdir(root)
baseenv=os.environ.copy()
# Keep inherited repository selection out of fixture creation as well.
localvars=subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()
for k in localvars+['GIT_CEILING_DIRECTORIES']:baseenv.pop(k,None)
def run(argv,env=None,cwd=None,data=None,ok=True):
 p=subprocess.run(list(map(str,argv)),cwd=cwd or root,env=env or baseenv,input=data,capture_output=True,timeout=60)
 if not ok or p.returncode:print(repr(argv),'rc',p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 if ok:assert p.returncode==0,('fixture command failed',argv,p.returncode,p.stderr)
 return p
def git(*a,**kw):return run([realgit,*a],**kw).stdout.decode().strip()
def write(p,s):
 p=root/p;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(s if isinstance(s,bytes) else s.encode())
def save(at=1700000000):
 git('add','-A');tree=git('write-tree');parents=['-p',git('rev-parse','HEAD')] if run([realgit,'rev-parse','--verify','HEAD'],ok=False).returncode==0 else []
 e=dict(baseenv,GIT_AUTHOR_DATE=f'{at} +0000',GIT_COMMITTER_DATE=f'{at} +0000')
 sha=git('commit-tree',tree,*parents,env=e,data=b'fixture76\n');git('update-ref','HEAD',sha);return sha
def lock(id,fmt=4,kind='feature',reported=None,fixes=None,state='closed',bad=None):
 files={'tests/test_value.py':('sha256:' if fmt!=2 else '')+hashlib.sha256(b'def test_value(): assert False\n').hexdigest()}
 d=dict(format=fmt,state=state,files=files,cases=['tests/test_value.py::test_value'],failing_at_red=['tests/test_value.py::test_value'])
 if fmt==4:d.update(kind=kind,reported_at=reported,fixes_release=fixes)
 if bad=='schema':d['kind']=None
 canonical=dict(d);canonical['files']=dict(sorted(files.items()));canonical['seal']=''
 d['seal']=hashlib.sha256(json.dumps(canonical,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
 if bad=='seal':d['seal']='0'*64
 write(Path('.shipcraft/locks')/(id+'.json'),json.dumps(d)+'\n')
def tag(name,at=None):
 if at is None:git('tag',name)
 else:git('tag','-a',name,'-m','release76',env=dict(baseenv,GIT_COMMITTER_DATE=f'{at} +0000'))
def row(id,at,layer='red',**extra):
 r=dict(layer=layer,at=at,lock=id,result='passed',secs=1,branch='feature/76',commit='a'*40,code='',reason='')
 if layer=='merge':r.update(locks=[id],base='main',default_branch='main')
 r.update(extra);return r
def snapshot(folder):
 result={}
 for p in folder.rglob('*'):
  s=p.lstat()
  result[str(p.relative_to(folder))]=(stat.S_IFMT(s.st_mode),stat.S_IMODE(s.st_mode),os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None)
 return result
git('init','-q','-b','main');git('config','gc.auto','0');git('config','maintenance.auto','false')
write(Path('tests/test_value.py'),'def test_value(): assert False\n');write(Path('.shipcraft.toml'),'invalid [ TOML\n' if case=='invalid-config' else 'shipcraft_min = "0.0"\nlang = "python"\nrunner = "pytest"\ntest_command = "touch SHOULD-NOT-RUN76"\n')
T1=1700000000;T2=T1+86400;T3=T1+259200
# Main release line: annotated, lightweight, annotated; A is removed after shipping.
if case=='failure-scoped':
 lock('old',fmt=3);save(T1-2000);tag('v0.9.0',T1-1500);(root/'.shipcraft/locks/old.json').unlink()
lock('A');r1=save(T1-1000);tag('v1.0.0',T1)
reported=lambda t:datetime.datetime.fromtimestamp(t,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
lock('B',kind='fix',reported=reported(T2-60),fixes='v1.0.0');lock('C')
if case=='kinds-release':lock('B')
r2=save(T2);tag('v1.1.0')
(root/'.shipcraft/locks/A.json').unlink()
lock('D',kind='fix',reported=reported(T3-180),fixes='v1.1.0')
if case=='kinds-release':lock('B',kind='fix',reported=reported(T2-60),fixes='v1.0.0')
r3=save(T3-1000);tag('v2.0.0',T3)
rs=[row('D',T3-800),row('A',T1-100),row('B',T2-200),row('C',T2-400),row('A',T1+1,'merge')]
args=['--json'];env=dict(baseenv);cwd=root;unavailable=None;want_branch='refs/heads/main'
# Separate real repositories, without a service or network dependency.
if case in ('shallow','partial','since-partial'):
 origin=cw/'origin76.git';git('clone','--bare',root,origin);git('-C',origin,'config','uploadpack.allowFilter','true')
 clone=cw/'clone76'
 git('clone','--no-local',*(['--depth=1'] if case=='shallow' else ['--filter=blob:none','--no-checkout']),origin.as_uri(),clone)
 root=clone;cwd=root
 if case=='shallow':assert git('rev-parse','--is-shallow-repository')=='true';unavailable='shallow clone: history incomplete'
 else:
  assert git('config','--get','remote.origin.promisor')=='true';unavailable='partial clone: report reads no network'
  # No promised blob is read in fixture setup; deleting the origin makes any fetch fail.
  shutil.rmtree(origin)
if case=='worktree':
 wt=cw/'worktree76';git('worktree','add','-q','-b','work76',wt);root=wt;cwd=root
 # The run log follows the .git file and commondir, per item 38.
 logroot=Path(git('rev-parse','--git-common-dir'));logroot=(root/logroot).resolve()
else:logroot=root/'.git'
logpath=logroot/'shipcraft/runs.jsonl';logpath.parent.mkdir(parents=True,exist_ok=True)
if case in ('empty','text-empty'):rs=[]
if case=='rows':
 rs=[row('D',T3-800),row('log-only',100,kind='feature')]
 lock('aa');lock('Z');save(T3+1)
if case=='states':rs=[row('B',10),row('D',20,'merge'),row('not-on-main',30)]
if case.startswith('kinds-'):
 rs=[row('B',10,kind='feature',reported_at=None,fixes_release=None)]
 if case=='kinds-tip':
  lock('B',kind='fix',reported=reported(T3-15),fixes='v1.1.0');save(T3+1)
  git('checkout','-qb','feature76');lock('B');save(T3+2)
 elif case=='kinds-release':(root/'.shipcraft/locks/B.json').unlink();save(T3+2)
 elif case=='kinds-head':
  git('checkout','-qb','feature76');lock('head-only',kind='fix',reported=reported(T1),fixes='v1.0.0');save(T3+2);rs=[row('head-only',10,kind='feature')]
 elif case=='kinds-red':rs=[row('no-file',5,result='refused',kind='feature'),row('no-file',6,redo=True,kind='feature'),row('no-file',20,kind='fix',reported_at=reported(T1),fixes_release='v1.0.0'),row('no-file',10,kind='feature'),row('no-file',10,kind='fix')]
 elif case in ('kinds-legacy','kinds-legacy2'):lock('B',fmt=2 if case.endswith('2') else 3);save(T3+2)
if case in ('invalid-seal','invalid-schema'):
 lock('B',bad='seal' if case=='invalid-seal' else 'schema');save(T3+2)
 # Corrupt every source so a valid release fallback cannot mask the invalid-lock rule.
 for t in ('v1.1.0','v2.0.0'):git('tag','-f',t)
 rs=[row('B',10)]
if case=='lead-missing':rs=[r for r in rs if r['lock']!='C']
if case=='lead-nonpositive':rs=[dict(r,at=T2) if r['lock']=='B' else r for r in rs]
if case=='lead-redo':rs=[row('B',1,redo=True),row('B',2,result='refused')]+rs
if case in ('recover-missing','recover-nonpositive','recover-offset','rework-unknown','failure-unknown','failure-absent','failure-null'):
 kw={'kind':'fix','reported':reported(T3-180),'fixes':'v1.1.0'}
 if case=='recover-missing':kw['reported']=None
 if case=='recover-nonpositive':kw['reported']=reported(T3)
 if case=='recover-offset':kw['reported']=datetime.datetime.fromtimestamp(T3-180,datetime.timezone(datetime.timedelta(hours=-3))).isoformat(timespec='seconds')
 if case in ('rework-unknown','failure-unknown'):kw={'fmt':3}
 if case=='failure-absent':kw['fixes']='v9.9.9'
 if case=='failure-null':kw['fixes']=None
 lock('D',**kw);save(T3-1000);git('tag','-d','v2.0.0');tag('v2.0.0',T3)
if case=='first-shipment':
 # A is shipped once even if it reappears, with a changed kind, in a later release.
 lock('A',kind='fix',reported=reported(T3-30),fixes='v1.0.0');save(T3-999);git('tag','-d','v2.0.0');tag('v2.0.0',T3)
if case in ('since','since-order','failure-scoped','since-empty'):
 args=['--since','v1.1.0','--json'] if case=='since-order' else ['--json','--since','v1.1.0']
 if case=='since-empty':save(T3+86400);tag('v3.0.0');args=['--json','--since','v3.0.0']
if case=='since-not-release':args+=['--since','v99.0.0']
if case=='since-offline-tag':
 git('checkout','-qb','unmerged76',r1);save(T1);tag('v99.0.0');git('checkout','main');args+=['--since','v99.0.0']
if case in ('text','text-empty'):args=[]
if case=='since-text-coverage':args=['--since','v2.0.0']
if case=='tags':
 for t in ('release','v01.0.0','v1.01.0','v1.0.00','v1.0.0-rc1','packages/v8.0.0','v１.0.0'):tag(t)
 git('checkout','-qb','not-default76',r1);save(T1);tag('v99.0.0');git('checkout','main')
if case=='tag-blob':
 blob=git('hash-object','-w','--stdin',data=b'not a commit\n');git('tag','v8.0.0',blob)
if case=='tag-no-tagger':
 # A genuine annotated Git tag object, with the optional tagger header omitted.
 raw=f'object {r3}\ntype commit\ntag v3.0.0\n\nimported annotated tag\n'.encode()
 obj=git('hash-object','--literally','-t','tag','-w','--stdin',data=raw);git('update-ref','refs/tags/v3.0.0',obj)
if case in ('tie','tie-huge'):
 for t in ('v1.0.0','v1.1.0','v2.0.0'):git('tag','-d',t)
 git('checkout','-q','--detach',r1);tag('v1.9.0',T1)
 git('checkout','-q','main');lock('A');save(T1);tag('v1.10.0',T1)
 if case=='tie-huge':tag('v100000000000000000000000000000000000000.0.0',T1)
 rs=[row('A',T1-10),row('B',T1-20),row('C',T1-30),row('D',T1-40)]
 args+=['--since','v100000000000000000000000000000000000000.0.0' if case=='tie-huge' else 'v1.10.0']
if case in ('origin-main','origin-head','master','no-default'):
 git('branch','-m','topic76')
 if case=='origin-main':git('update-ref','refs/remotes/origin/main',r3);want_branch='refs/remotes/origin/main'
 if case=='origin-head':
  git('update-ref','refs/remotes/origin/trunk',r3);git('symbolic-ref','refs/remotes/origin/HEAD','refs/remotes/origin/trunk');git('branch','main',r1);want_branch='refs/remotes/origin/HEAD'
 if case=='master':git('branch','master',r3);want_branch='refs/heads/master'
 if case=='no-default':unavailable='no default branch'
if case=='nested':cwd=root/'packages/pkg/deep';cwd.mkdir(parents=True)
if case=='environment':
 other=cw/'other76';git('init','-q','-b','main',other)
 env.update(GIT_DIR=str(other/'.git'),GIT_WORK_TREE=str(other),GIT_COMMON_DIR=str(other/'.git'),GIT_INDEX_FILE=str(other/'alternate-index'),GIT_OBJECT_DIRECTORY=str(other/'.git/objects'),GIT_ALTERNATE_OBJECT_DIRECTORIES=str(other/'.git/objects'),GIT_CEILING_DIRECTORIES=str(root))
if case=='signed':
 # Actual SSH signing, no keyring/agent/network. Block both Git verifier interfaces.
 key=cw/'signing76';run(['ssh-keygen','-q','-t','ed25519','-N','','-f',key])
 git('config','gpg.format','ssh');git('config','user.signingkey',str(key))
 allowed=cw/'allowed-signers76';allowed.write_text('* '+key.with_suffix('.pub').read_text());git('config','gpg.ssh.allowedSignersFile',str(allowed))
 tree=git('rev-parse','HEAD^{tree}');signed=git('commit-tree','-S',tree,'-p',r3,data=b'signed76\n',env=dict(baseenv,GIT_AUTHOR_DATE=f'{T3+1} +0000',GIT_COMMITTER_DATE=f'{T3+1} +0000'))
 assert 'gpgsig -----BEGIN SSH SIGNATURE-----' in git('cat-file','commit',signed)
 git('update-ref','refs/heads/main',signed);tag('v3.0.0')
 verifier=cw/'verifier76';verifier.write_text('#!'+sys.executable+'\nfrom pathlib import Path\nPath('+repr(str(cw/'verifier-called'))+').touch()\nraise SystemExit(91)\n');verifier.chmod(0o755)
 git('config','log.showSignature','true');git('config','gpg.program',str(verifier));git('config','gpg.ssh.program',str(verifier))
if case=='removed-no-log':rs=[r for r in rs if r['lock']!='A']
if case=='no-releases':
 for t in ('v1.0.0','v1.1.0','v2.0.0'):git('tag','-d',t)
if case=='since-partial':args+=['--since','v99.0.0']
if case.startswith('promisor-'):
 mode=case[9:];value={'true':'true','yes':'yes','on':'on','one':'1','mixed':'TrUe','false':'false','zero':'0','legacy':'origin'}[mode]
 git('config','extensions.partialclone' if mode=='legacy' else 'remote.backup.promisor',value)
 if mode not in ('false','zero'):unavailable='partial clone: report reads no network'
if case=='log-directory':logpath.unlink(missing_ok=True);logpath.mkdir()
else:logpath.write_text(''.join(json.dumps(r)+'\n' for r in rs))
if case=='git-late-failure':
 with logpath.open('a') as f:f.write('{broken-json\n')
if case=='git-missing-object':
 oid=git('rev-parse','HEAD:.shipcraft/locks/B.json');obj=root/'.git/objects'/oid[:2]/oid[2:]
 assert obj.is_file(),'fixture requires a real loose blob';obj.unlink()
if case=='readonly':
 for p in root.rglob('*'):
  if p.is_file():p.chmod(0o444)
if case.startswith('arguments-'):
 mode=case[10:]
 args={'missing':['--since'],'repeat-json':['--json','--json'],'repeat-since':['--since','v1.0.0','--since','v1.1.0'],'unknown':['--github'],'extra':['word'],'leading-zero':['--since','v01.0.0'],'unicode':['--since','v１.0.0'],'suffix':['--since','v1.0.0-rc1'],'empty':['--since',''],'flag-value':['--since','--json']}[mode]
# Record all report git calls while delegating to real git. Failure injection happens
# only at the named public read boundary; no fabricated log/tag output is used.
tools=cw/'tools76';tools.mkdir();calls=cw/'git-calls76.jsonl'
proxy=tools/'git';proxy.write_text('#!'+sys.executable+'\n'+'''import json,os,subprocess,sys
from pathlib import Path
a=sys.argv[1:];env=os.environ
with open('''+repr(str(calls))+''','a') as f:f.write(json.dumps({'args':a,'env':{k:env.get(k) for k in '''+repr(localvars+['GIT_CEILING_DIRECTORIES','GIT_NO_LAZY_FETCH','GIT_TERMINAL_PROMPT'])+'''}})+'\\n')
mode='''+repr(case)+'''
if mode.startswith('arguments-'):raise SystemExit(96)
if mode in ('git-failure','since-unavailable'):raise SystemExit(93)
if mode=='git-late-failure' and 'cat-file' in a:raise SystemExit(94)
if mode=='git-bad-utf8' and 'for-each-ref' in a:sys.stdout.buffer.write(bytes([255]));raise SystemExit(0)
if mode=='git-bad-time' and 'log' in a:print('not-seconds');raise SystemExit(0)
if mode=='git-bad-shallow' and '--is-shallow-repository' in a:print('perhaps');raise SystemExit(0)
if any(x in a for x in ('fetch','pull','push','clone')):raise SystemExit(95)
os.execve('''+repr(realgit)+''',['''+repr(realgit)+''',*a],dict(env))
''');proxy.chmod(0o755)
for tool in ('gh','codex','claude','gemini','curl','wget','ssh'):
 p=tools/tool;p.write_text('#!'+sys.executable+'\nfrom pathlib import Path\nPath('+repr(str(cw/'forbidden-called'))+').touch()\nraise SystemExit(92)\n');p.chmod(0o755)
env['PATH']=str(tools)+os.pathsep+env['PATH']
if case=='git-absent':proxy.unlink();env['PATH']=str(tools)
if case=='since-unavailable':args+=['--since','v99.0.0']
before=snapshot(root)
common_before=snapshot(logroot) if logroot!=root/'.git' else None
def report(args=args,cwd=cwd,env=env):
 p=run([binary,'report',*args],cwd=cwd,env=env,ok=False)
 print('REPORT',case,p.returncode,p.stdout.decode(errors='replace'),p.stderr.decode(errors='replace'),flush=True)
 assert snapshot(root)==before,'report wrote a file, object, index, ref, hook or run-log row'
 if common_before is not None:assert snapshot(logroot)==common_before,'report changed shared worktree Git state or run log'
 assert not (cw/'forbidden-called').exists(),'report started network/service/agent'
 assert not (cw/'verifier-called').exists(),'report started a signature verifier'
 return p
p=report()
if case.startswith('arguments-'):
 assert p.returncode==2 and b'invalid arguments:' in p.stderr and b'usage:' in p.stderr,(p.returncode,p.stderr)
 assert not calls.exists(),'usage refusal read git'
 sys.exit()
if case in ('since-not-release','since-offline-tag'):
 assert p.returncode==2 and p.stdout==b'',('non-release must refuse before any stdout',p.returncode,p.stdout)
 assert p.stderr.decode().strip()==f'report: --since v99.0.0 is not a release tag on {want_branch}',p.stderr
 sys.exit()
assert p.returncode==0,('report must exit zero',p.returncode)
if case in ('text','text-empty','since-text-coverage'):
 text=p.stdout.decode();lines=text.splitlines()
 # Item 38's report opening stays separate from the new DORA block.
 assert lines and re.search('machine|local',lines[0],re.I),lines
 if case=='text':assert all(str(x) in lines[0] for x in (T1-100,T3-800)),lines
 start=next((i for i,line in enumerate(lines) if re.search(r'\bDORA\b',line)),None)
 assert start is not None,('missing DORA block',lines)
 block=[line for line in lines[start:] if line.strip()]
 # Permit either a standalone heading or DORA on the first coverage line.
 coverage=block if re.search('machine|local',block[0],re.I) else block[1:]
 assert len(coverage)>=2 and re.search('machine|local',coverage[0],re.I),block
 if case=='text':assert all(str(x) in coverage[0] for x in (T1-100,T3-800)),coverage
 count=1 if case=='since-text-coverage' else 3
 assert re.search(r'\bmain\b',coverage[1]) and re.search(r'\b'+str(count)+r'\b',coverage[1]),coverage
 if case=='since-text-coverage':assert 'v2.0.0' in coverage[1] and not re.search(r'\b3\b',coverage[1]),coverage
 assert re.search('branch.*tip|tip.*branch',coverage[1],re.I),coverage
 assert all(re.search(k,'\n'.join(block),re.I) for k in ('deploy','lead[ _-]time','rework','recover','change[ _-]failure')),block
 sys.exit()
output=[json.loads(s) for s in p.stdout.splitlines()];ds=[r for r in output if r.get('kind')=='dora']
assert len(ds)==1,('expected one DORA object',output)
d=ds[0];locks={r['lock']:r for r in output if r.get('kind')=='lock'}
assert [r['kind'] for r in output]==sorted([r['kind'] for r in output],key=['meta','lock','day','dora','gap'].index),output
metrics=('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate')
for k in metrics:
 assert all(x in d[k] for x in ('value','n','missing','reason')),(k,d)
 if d[k]['value'] is None:assert isinstance(d[k]['reason'],str) and d[k]['reason'],(k,d)
def metric(k,value,n,missing=0):
 m=d[k];assert m['value']==value and m['n']==n and m['missing']==missing,(k,value,n,missing,m)
 if value is not None and missing==0:assert m['reason'] is None,(k,m)
for r in ([json.loads(s) for s in calls.read_text().splitlines()] if calls.exists() else []):
 assert r['args'][:2]==['-C',str(root)],('git must address the discovered root',r)
 assert r['env']['GIT_NO_LAZY_FETCH']=='1' and r['env']['GIT_TERMINAL_PROMPT']=='0',r
 assert all(r['env'][k] is None for k in localvars+['GIT_CEILING_DIRECTORIES']),('inherited repository selection',r)
if unavailable or case in ('git-absent','git-failure','git-late-failure','git-bad-time','git-bad-shallow','git-missing-object','git-bad-utf8','since-unavailable'):
 assert d['git']['reason'] and d['git']['default_branch'] is None and d['git']['releases'] is None,d
 if unavailable:assert d['git']['reason']==unavailable,d
 for k in metrics:assert d[k]['value'] is None and d[k]['reason']==d['git']['reason'],(k,d)
 assert locks['A']['state']=='merged' and locks['A']['red_at']==T1-100 and locks['A']['merge_at']==T1+1,locks
 assert locks['D']['red_at']==T3-800 and locks['D']['merge_at'] is None,locks
 if case=='git-late-failure':
  gaps=[r for r in output if r['kind']=='gap'];assert len(gaps)==1 and gaps[0]['line']==6,gaps
 if case in ('partial','shallow','since-partial') or (case.startswith('promisor-') and unavailable):
  reads=[json.loads(s)['args'][2:] for s in calls.read_text().splitlines()]
  assert reads==[['config','--get-regexp',r'^(extensions\.partialclone|remote\..*\.promisor)$']]+([['rev-parse','--is-shallow-repository']] if case=='shallow' else []),reads
 if case in ('since-unavailable','since-partial'):assert d['since']=='v99.0.0',d
 sys.exit()
assert d['git']['reason'] is None and d['git']['default_branch']==want_branch,d
if case in ('nested','environment'):
 clean=report(['--json'],root,dict(baseenv,PATH=env['PATH']));assert (p.stdout,p.stderr)==(clean.stdout,clean.stderr),'root/environment changed report'
if case=='rows':
 assert list(locks)==['D','log-only','B','C','Z','aa'],locks
 for id in ('B','C','Z','aa'):assert locks[id]['red_at'] is None and locks[id]['merge_at'] is None and locks[id]['state']=='merge_not_observed',locks[id]
if case=='states':
 assert locks['B']['state']=='merge_not_observed' and locks['B']['merge_at'] is None and locks['B']['red_to_merge'] is None,locks
 assert locks['D']['state']=='merged' and locks['not-on-main']['state']=='open',locks
 days=[r for r in output if r['kind']=='day'];assert sum(r['merged_locks'] for r in days)==1,days
if case.startswith('kinds-'):
 id='head-only' if case=='kinds-head' else 'no-file' if case=='kinds-red' else 'B';r=locks[id]
 expected=None if case in ('kinds-legacy','kinds-legacy2') else 'feature' if case=='kinds-red' else 'fix'
 assert r['change_kind']==expected,(case,r)
 if expected=='fix':
  expected_time=reported(T1) if case=='kinds-head' else reported(T3-15) if case=='kinds-tip' else reported(T2-60)
  assert r['reported_at']==expected_time and r['fixes_release']==('v1.1.0' if case=='kinds-tip' else 'v1.0.0'),r
 if expected=='feature':assert r['reported_at'] is None and r['fixes_release'] is None,r
 if expected is None:assert r['reported_at'] is None and r['fixes_release'] is None,r
if case in ('invalid-seal','invalid-schema'):
 assert locks['B']['change_kind'] is None,locks
if case=='invalid-config':
 assert locks['B']['change_kind']=='fix',locks
if case in ('metrics','removed','nested','environment','readonly','invalid-config','worktree','origin-main','local-main','origin-head','master','tags','tag-blob','lead-redo'):
 assert d['since'] is None and d['git']['releases']==3,d
 metric('deploys',dict(count=3,first=T1,last=T3,per_day=1.0),3)
 metric('lead_time',dict(median=300.0,p90=800.0),4)
 metric('rework_rate',2/3,3);metric('time_to_recover',dict(median=120.0,p90=180.0),2);metric('change_failure_rate',2/3,3)
 if case=='removed':assert 'A' in locks and locks['A']['change_kind']=='feature',locks
if case in ('since','since-order','failure-scoped'):
 assert d['since']=='v1.1.0',d
 metric('deploys',dict(count=2,first=T2,last=T3,per_day=1.0),2)
 metric('lead_time',dict(median=400.0,p90=800.0),3)
 metric('rework_rate',1.0,2);metric('time_to_recover',dict(median=120.0,p90=180.0),2);metric('change_failure_rate',0.5,2)
if case=='since-empty':
 metric('deploys',dict(count=1,first=T3+86400,last=T3+86400,per_day=None),1)
 for k in ('lead_time','rework_rate','time_to_recover'):metric(k,None,0)
 metric('change_failure_rate',0.0,1)
if case in ('lead-missing','lead-nonpositive'):
 metric('lead_time',dict(median=200.0 if case=='lead-missing' else 400.0,p90=800.0),3,1)
 assert d['lead_time']['reason'],d
if case in ('recover-missing','recover-nonpositive'):
 metric('time_to_recover',dict(median=60.0,p90=60.0),1,1);assert d['time_to_recover']['reason'],d
if case=='recover-offset':metric('time_to_recover',dict(median=120.0,p90=180.0),2)
if case in ('rework-unknown','failure-unknown'):
 metric('rework_rate',None,3,1);metric('change_failure_rate',None,3,1)
if case in ('failure-absent','failure-null'):metric('change_failure_rate',None,3,1)
if case=='first-shipment':metric('lead_time',dict(median=300.0,p90=800.0),4)
if case=='tag-no-tagger':assert d['git']['releases']==4 and d['deploys']['value']['first']==T1 and d['deploys']['value']['last']==T3,d
if case in ('tie','tie-huge'):
 assert d['git']['releases']==(2 if case=='tie' else 3),d
 metric('lead_time',dict(median=25.0,p90=40.0),4)
 metric('rework_rate',0.5,2)
 assert d['deploys']['value']['per_day'] is None,d
if case in ('empty','log-directory'):
 assert output[0]['first_at'] is None and output[0]['last_at'] is None,output
 metric('lead_time',None,0,4)
if case=='removed-no-log':
 assert 'A' not in locks,locks
 metric('lead_time',dict(median=400.0,p90=800.0),3,1)
 assert d['rework_rate']['missing']==0 and d['change_failure_rate']['missing']==0,d
if case=='no-releases':
 assert d['git']['releases']==0,d
 for k in metrics:metric(k,None,0)
if case.startswith('promisor-'):assert d['git']['releases']==3,d
if case=='signed':assert d['git']['releases']==4,d
PY76
  pass
}
