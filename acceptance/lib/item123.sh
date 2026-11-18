# Item 123, spec 9721222: public report/CI only; no implementation reader.
item123_langs() { echo core; }
item123_cases() {
  local c
  for c in basic repeated commit red-filter red-commit green-filter green-commit green-flags green-other escape times times-invalid failed-array failed-legacy failed-count top5 byte-ids reader malformed json-whole json-fraction text-minute text-escape since github git-failure config-failure control-report control-github control-refusal iso-edges floor-utc invalid-at float-range cross-week weekly-sums weekly-ranking control-no-week; do echo "v1-123.$c"; done
}
item123_case() {
  EXPECT="item 123: ${CASE#v1-123.}"
  v1_start codex
  must_accept 'item 123 report contract' cmd "$PY" - "$CASE" "$(command -v shipcraft)" "$CW" <<'PY123'
import json,os,shlex,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/"repo123 space 'quote";root.mkdir();realgit=shutil.which('git');env=dict(os.environ)
for k in subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
def run(*args):
 p=subprocess.run(list(map(str,args)),cwd=root,env=env,input=b'',capture_output=True,timeout=120)
 print('COMMAND123',args,p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 return p
def git(*args):
 p=run(realgit,*args);assert p.returncode==0,('fixture git',p.stderr);return p.stdout.decode().strip()
def write(name,data):
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
def snapshot():
 return {str(p.relative_to(root)):(stat.S_IFMT(p.lstat().st_mode),stat.S_IMODE(p.lstat().st_mode),os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None) for p in root.rglob('*')}
def data(p):return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
git('init','-q','-b','main');git('config','gc.auto','0');git('config','maintenance.auto','false')
write('README.md','item123 fixture\n');write('.git/shipcraft/sentinel',b'keep123\x00\r\n')
tools=cw/'tools123';tools.mkdir();calls=cw/'git-calls123';ghcalls=cw/'gh-calls123';proof=cw/'proof123';fault=cw/'git-fault123';ghfault=cw/'gh-fault123'
# Transparent Git probe: public command recording and one injected read failure.
(tools/'git').write_text('#!'+sys.executable+'\n'+"import json,os,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith open("+repr(str(calls))+",'a') as f:f.write(json.dumps(a)+'\\n')\nif Path("+repr(str(fault))+").exists() and 'for-each-ref' in a:raise SystemExit(93)\nos.execv("+repr(realgit)+",["+repr(realgit)+",*a])\n");(tools/'git').chmod(0o755)
# gh 2.x pr-view JSON shape, as item 79; unexpected calls cannot access a service.
(tools/'gh').write_text('#!'+sys.executable+'\n'+"import json,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith open("+repr(str(ghcalls))+",'a') as f:f.write(json.dumps(a)+'\\n')\nif a!=['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']:raise SystemExit(91)\nif Path("+repr(str(ghfault))+").exists():raise SystemExit(92)\nprint(json.dumps(dict(number=97,state='OPEN',mergedAt=None,headRefOid='a'*40,mergeCommit=None)))\n");(tools/'gh').chmod(0o755)
env['PATH']=str(tools)+os.pathsep+env['PATH']
env.update(GIT_AUTHOR_DATE='1700000000 +0000',GIT_COMMITTER_DATE='1700000000 +0000')
git('add','README.md');git('commit','-qm','fixture123');git('tag','v1.0.0');base=git('rev-parse','HEAD')
env.update(GIT_AUTHOR_DATE='1700086400 +0000',GIT_COMMITTER_DATE='1700086400 +0000')
write('README.md','second release123\n');git('add','README.md');git('commit','-qm','release123');git('tag','v2.0.0')
log=root/'.git/shipcraft/runs.jsonl'
def row(**kw):
 r=dict(layer='ci',result='refused',code='suite-red',commit='foreign123',at=100,secs=45,lock='',locks=[],branch='topic123')
 r.update(kw);return r
def green(**kw):return row(**dict(dict(result='passed',code=''),**kw))
def wire(rs):return ''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in rs).encode()
def report(rs,args=('--json',)):
 if rs is not None:write('.git/shipcraft/runs.jsonl',rs if isinstance(rs,bytes) else wire(rs))
 before=snapshot();p=run(binary,'report',*args)
 assert p.returncode==0 and not p.stderr,(p.returncode,p.stdout,p.stderr)
 assert snapshot()==before,'report wrote repository state'
 if case not in ('v1-123.control-report','v1-123.control-github','v1-123.control-refusal','v1-123.control-no-week'):
  other=tuple(a for a in args if a!='--json') if '--json' in args else ('--json',*args)
  q=run(binary,'report',*other)
  assert q.returncode==0 and not q.stderr,(q.returncode,q.stdout,q.stderr)
  assert snapshot()==before,'alternate report format wrote repository state'
 return p.stdout.decode()
def objects(s,kind):return [r for r in (json.loads(x) for x in s.split('\n') if x) if r['kind']==kind]
def reds(s):return objects(s,'reds_week')
def lines(s):return [x for x in s.split('\n') if x.startswith('reds ')]
# Each oracle lives in its exact-id arm. No shared helper computes expected counts.
if case=='v1-123.basic':
 rs=[row(failed=['tests.db::insert']),green()]
 calls.unlink(missing_ok=True);s=report(rs);observed=data(calls)
 calls.unlink();report([dict(r,code='other') for r in rs])
 assert data(calls)==observed and not ghcalls.exists(),'new Git/network read'
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=1,cases=[dict(id='tests.db::insert',rows=1)])],s
 t=report(rs,args=());assert lines(t),t
elif case=='v1-123.repeated':
 s=report([row(failed=['a']),row(failed=['a'],secs=5),green(),green(),row(failed=['later'])])
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=3,green_again=2,green_again_share=2/3,green_again_secs=50,named=2,cases=[dict(id='a',rows=2)])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.commit':
 s=report([row(commit='AbC'),green(commit='abc'),row(commit=' x '),green(commit='x'),row(commit='foreign123',branch='one',lock='A',locks=['A']),green(commit='foreign123',branch='two',lock='B',locks=['B'],secs=999)])
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=3,green_again=1,green_again_share=1/3,green_again_secs=45,named=0,cases=[])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.red-filter':
 rs=[row(),green()]
 for key,values in [('layer',['hook','pr','review','CI',None,True]),('result',['passed','error','REFUSED',None]),('code',['no-report','lock-not-closed','case-broke','build-failed','timed-out','SUITE-RED',None])]:
  for v in values:rs.append(row(**{key:v}))
  r=row();r.pop(key);rs.append(r)
 s=report(rs);assert not objects(s,'gap'),s
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.red-commit':
 rs=[row(commit=' '),green(commit=' ')]
 for v in ('',None,False,1,1.0,[],{}):rs.append(row(commit=v))
 r=row();r.pop('commit');rs.append(r);s=report(rs);assert not objects(s,'gap'),s
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.green-filter':
 rs=[row()]
 for key,values in [('layer',['hook','pr','review','CI',None]),('result',['refused','error','PASSED',None])]:
  for v in values:rs.append(green(**{key:v}))
  r=green();r.pop(key);rs.append(r)
 s=report(rs)
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=1,green_again=0,green_again_share=0,green_again_secs=0,named=0,cases=[])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.green-commit':
 rs=[row()]+[green(commit=v) for v in ('',None,False,1,[],{},'different')]
 r=green();r.pop('commit');rs.append(r);s=report(rs);assert not objects(s,'gap'),s
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=1,green_again=0,green_again_share=0,green_again_secs=0,named=0,cases=[])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.green-flags':
 s=report([row(commit='docs'),green(commit='docs',docs_only=True),row(commit='checks'),green(commit='checks',suite_in_checks=True),row(commit='both'),green(commit='both',docs_only=True,suite_in_checks=True)])
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=3,green_again=0,green_again_share=0,green_again_secs=0,named=0,cases=[])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.green-other':
 rs=[row(commit='missing'),green(commit='missing',code='irrelevant')]
 for i,v in enumerate((False,None,0,1,'true',[],{})):
  rs += [row(commit=str(i),docs_only=True,suite_in_checks=True),green(commit=str(i),docs_only=v,suite_in_checks=v)]
 s=report(rs)
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=8,green_again=8,green_again_share=1,green_again_secs=360,named=0,cases=[])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.escape':
 s=report([row(escape=True),row(commit='b'),green(commit='b',escape=True),row(commit='c',escape=False),green(commit='c')])
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=2,green_again=1,green_again_share=0.5,green_again_secs=45,named=0,cases=[])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.times':
 s=report([row(secs=0),row(secs=1.25),row(secs=2),green(secs=999),row(secs=800)])
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=4,green_again=3,green_again_share=0.75,green_again_secs=3.25,named=0,cases=[])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.times-invalid':
 rs=[row(secs=v) for v in (-1,-0.5,True,False,None,'45',[],{})];r=row();r.pop('secs');rs += [r,green()]
 s=report(rs);assert not objects(s,'gap'),s
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=9,green_again=9,green_again_share=1,green_again_secs=0,named=0,cases=[])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.failed-array':
 s=report([row(failed=['a','a',None,1,True,{},[], '', 'b']),row(failed=[]),row(failed=[None,False]),green(),row(failed=['never'])])
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=4,green_again=3,green_again_share=0.75,green_again_secs=135,named=3,cases=[dict(id='',rows=1),dict(id='a',rows=1),dict(id='b',rows=1)])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.failed-legacy':
 rs=[row()]+[row(failed=v) for v in (None,'a',True,1,{})]+[green()];s=report(rs)
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=6,green_again=6,green_again_share=1,green_again_secs=270,named=0,cases=[])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.failed-count':
 s=report([row(failed=['a'],failed_count=999),row(failed=['a','b'],failed_count=0),row(failed_count=['bad']),green(failed=['green-only'])])
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=3,green_again=3,green_again_share=1,green_again_secs=135,named=2,cases=[dict(id='a',rows=2),dict(id='b',rows=1)])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.top5':
 s=report([row(failed=['z','f','e','d','c','b','a']),row(failed=['z']),green()])
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=2,green_again=2,green_again_share=1,green_again_secs=90,named=2,cases=[dict(id=x,rows=n) for x,n in [('z',2),('a',1),('b',1),('c',1),('d',1)]])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.byte-ids':
 s=report([row(failed=['é','e\u0301','api:t','t','API:t']),green()])
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=1,cases=[dict(id=x,rows=1) for x in ['API:t','api:t','e\u0301','t','é']])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.reader':
 raw=b'\xef\xbb\xbf'+wire([row(failed=['a\u2028\u2029'])]).replace(b'\n',b'\r\n')+b' \t\r\n'
 raw+=wire([row(failed=['BAD123'])]).replace(b'BAD123',b'\xff')
 raw+=wire([green()]).replace(b'"result": "passed"',b'"result": "error", "result": "passed"')[:-1]+b'\r'
 s=report(raw);assert not objects(s,'gap'),s
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=2,green_again=2,green_again_share=1,green_again_secs=90,named=2,cases=[dict(id='a\u2028\u2029',rows=1),dict(id='\ufffd',rows=1)])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.malformed':
 raw=wire([row()])+b'{broken123\n[]\nnull\n'+wire([row(secs='OVER123')]).replace(b'"OVER123"',b'1e400')+wire([green()])
 s=report(raw);assert [r['line'] for r in objects(s,'gap')]==[2,3,4,5],s
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],s
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.json-whole':
 s=report([row(secs=2.0),green()]);r=reds(s)
 assert r==[dict(kind='reds_week',week='1970-W01',suite_red=1,green_again=1,green_again_share=1,green_again_secs=2,named=0,cases=[])],s
 assert all(type(r[0][k]) is int for k in ('suite_red','green_again','green_again_share','green_again_secs','named')),r
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.json-fraction':
 s=report([row(secs=0.25),green(),row(),row()]);r=reds(s)
 assert r==[dict(kind='reds_week',week='1970-W01',suite_red=3,green_again=1,green_again_share=1/3,green_again_secs=0.25,named=0,cases=[])],s
 assert type(r[0]['suite_red']) is int and type(r[0]['named']) is int,r
 t=report(None,args=());assert lines(t),t
elif case=='v1-123.text-minute':
 s=report([row(secs=60,failed=['z','a']),row(secs=65,failed=['z']),green(),row()],args=())
 assert lines(s)==['reds 1970-W01: 3 suite-red, 2 green again on the same commit (67%), 2 min 5 s of CI; cases named in 2: "z" (2), "a" (1)'],s
elif case=='v1-123.text-escape':
 ident='"\\\n\r\t\b\f\x00\x01\x1f, () / é\u2028\u2029'
 rs=[row(failed=[ident]),green()];s=report(rs,args=());j=report(rs)
 assert lines(s)==['reds 1970-W01: 1 suite-red, 1 green again on the same commit (100%), 45 s of CI; cases named in 1: '+json.dumps(ident,ensure_ascii=False)+' (1)'],repr(s)
 assert reds(j)[0]['cases']==[dict(id=ident,rows=1)],j
elif case=='v1-123.since':
 rs=[row(at=1),green(at=2)];s=report(rs,args=('--json','--since','v2.0.0'));t=report(rs,args=('--since','v2.0.0'))
 assert objects(s,'dora')[0]['deploys']['n']==1,s
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],s
 assert lines(t)==lines(report(rs,args=())),t
elif case=='v1-123.github':
 rs=[row(layer='red',lock='G',result='passed',at=1),row(layer='close',lock='G',result='passed',at=2),row(layer='pr',lock='G',locks=['G'],pr=97),row(layer='merge',lock='G',locks=['G'],pr=97,result='passed',base='main',default_branch='main'),row(),green()]
 s=report(rs,args=('--json','--github'));assert objects(s,'github')[0]['missing']=={'pr not merged':1},s
 ghfault.touch();f=report(rs,args=('--json','--github'));t=report(rs,args=('--github',))
 assert objects(f,'github')[0]['missing']=={'gh failed':1},f
 assert reds(s)==reds(f)==[dict(kind='reds_week',week='1970-W01',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],f
 assert lines(t)==lines(report(rs,args=())),t
elif case=='v1-123.git-failure':
 fault.touch();rs=[row(),green()];s=report(rs);t=report(rs,args=())
 assert objects(s,'dora')[0]['git']['reason'].endswith('exited 93'),s
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],s
 assert lines(t)==['reds 1970-W01: 1 suite-red, 1 green again on the same commit (100%), 45 s of CI; cases named in 0: none'],t
elif case=='v1-123.config-failure':
 write('.shipcraft.toml','[report]\nrelease_tags=""\n');rs=[row(),green()];s=report(rs);t=report(rs,args=())
 assert objects(s,'dora')[0]['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags is empty',s
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],s
 assert lines(t)==['reds 1970-W01: 1 suite-red, 1 green again on the same commit (100%), 45 s of CI; cases named in 0: none'],t
elif case=='v1-123.control-report':
 rs=[row(layer='red',lock='control123',at=17,result='passed'),row(layer='close',lock='control123',at=29,result='passed'),row(layer='merge',lock='control123',locks=['control123'],at=47,result='passed',base='main',default_branch='main')]
 s=report(rs);t=report(rs,args=())
 assert not reds(s) and not lines(t) and objects(s,'lock')[0]['red_to_merge']==30 and '30 s' in t,s
 assert objects(s,'dora')[0]['git']['releases']==2,s
 empty=report([]);emptytext=report([],args=());log.unlink()
 assert report(None)==empty and report(None,args=())==emptytext
 log.mkdir();assert report(None)==empty and report(None,args=())==emptytext;log.rmdir()
 ignored=[row(commit=''),row(escape=True),green(),row(code='no-report'),row(result='error')]
 assert not reds(report(ignored)) and not lines(report(ignored,args=()))
 fault.touch();s=report(rs);assert objects(s,'dora')[0]['git']['reason'].endswith('exited 93') and objects(s,'lock')[0]['red_to_merge']==30,s
 assert data(calls) and not ghcalls.exists()
elif case=='v1-123.control-github':
 rs=[row(layer='red',lock='G',result='passed',at=1),row(layer='close',lock='G',result='passed',at=2),row(layer='pr',lock='G',locks=['G'],pr=97),row(layer='merge',lock='G',locks=['G'],pr=97,result='passed',base='main',default_branch='main')]
 s=report(rs,args=('--json','--github'));assert objects(s,'github')[0]['missing']=={'pr not merged':1},s
 assert data(ghcalls)==[['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']],data(ghcalls)
 ghfault.touch();s=report(rs,args=('--json','--github'));assert objects(s,'github')[0]['missing']=={'gh failed':1} and not reds(s),s
elif case=='v1-123.control-refusal':
 write('.git/shipcraft/runs.jsonl',wire([row(),green()]))
 before=snapshot();p=run(binary,'report','--json','--since','v99.0.0')
 assert p.returncode==2 and not p.stdout and p.stderr.strip()==b'report: --since v99.0.0 is not a release tag on refs/heads/main',(p.returncode,p.stdout,p.stderr)
 assert snapshot()==before
 calls.unlink(missing_ok=True);p=run(binary,'report','--json','--json')
 assert p.returncode==2 and not p.stdout and b'invalid arguments:' in p.stderr and b'usage:' in p.stderr,(p.stdout,p.stderr)
 assert not calls.exists() and snapshot()==before
elif case=='v1-123.iso-edges':
 from datetime import datetime,timezone
 stamps=['2027-01-01','2024-12-30','2026-11-18','2021-01-03','2021-01-04']
 rs=[row(at=datetime.fromisoformat(x).replace(tzinfo=timezone.utc).timestamp()) for x in stamps]+[green(at=None)]
 s=report(rs);t=report(rs,args=())
 assert [r['week'] for r in reds(s)]==['2020-W53','2021-W01','2025-W01','2026-W47','2026-W53'],s
 assert all(r['suite_red']==r['green_again']==1 for r in reds(s)),s
 assert [x.split(':')[0] for x in lines(t)]==['reds '+x for x in ['2020-W53','2021-W01','2025-W01','2026-W47','2026-W53']],t
elif case=='v1-123.floor-utc':
 env['TZ']='Pacific/Honolulu'
 rs=[row(at=345599.99),row(at=345600),row(at=0),green(at=-1)]
 s=report(rs);t=report(rs,args=())
 assert [(r['week'],r['suite_red'],r['green_again']) for r in reds(s)]==[('1970-W01',2,2),('1970-W02',1,1)],s
 assert len(lines(t))==2,t
elif case=='v1-123.invalid-at':
 rs=[row(at=v) for v in (None,True,False,'100',[],{},-0.01,253402300800,1e100)]
 r=row();r.pop('at');rs += [r,row(),green()]
 s=report(rs);t=report(rs,args=())
 assert not objects(s,'gap') and objects(s,'reds')[0]['suite_red']==11,s
 assert reds(s)==[dict(kind='reds_week',week='1970-W01',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],s
 assert len(lines(t))==1,t
elif case=='v1-123.float-range':
 raw=wire([row(at='EDGE'),row(at='ROUND'),row(at=-0.0),green()]).replace(b'"EDGE"',b'253402300799.9999').replace(b'"ROUND"',b'253402300799.999999999999')
 s=report(raw);t=report(raw,args=())
 assert not objects(s,'gap') and objects(s,'reds')[0]['suite_red']==3,s
 assert [(r['week'],r['suite_red']) for r in reds(s)]==[('1970-W01',1),('9999-W52',1)],s
 assert len(lines(t))==2,t
elif case=='v1-123.cross-week':
 rs=[green(at=999999),row(at=100,failed=['a']),row(commit='other',at=604800),row(layer='hook',commit='other'),green(at=None),row(at=604800,failed=['unresolved'])]
 s=report(rs);t=report(rs,args=())
 assert [(r['week'],r['suite_red'],r['green_again'],r['cases']) for r in reds(s)]==[('1970-W01',1,1,[dict(id='a',rows=1)]),('1970-W02',2,0,[])],s
 assert lines(t)[1]=='reds 1970-W02: 2 suite-red, 0 green again on the same commit (0%), 0 s of CI; cases named in 0: none',t
elif case=='v1-123.weekly-sums':
 rs=[row(at=604800,secs=2,failed=['z']),row(at=100,secs=.25,failed=[]),row(at=None,secs=9,failed=['excluded']),green(),row(at=100,secs=77)]
 s=report(rs);t=report(rs,args=());w=reds(s);total=objects(s,'reds')[0]
 assert len(w)==2,s
 assert [sum(r[k] for r in w) for k in ('suite_red','green_again','named','green_again_secs')]==[total['suite_red']-1,total['green_again']-1,total['named']-1,total['green_again_secs']-9],s
 assert w[0]['green_again_share']==.5 and w[1]['green_again_share']==1 and len(lines(t))==2,(s,t)
elif case=='v1-123.weekly-ranking':
 rs=[row(at=604800,failed=['a','b','c','d','e','f','z']),row(at=604800,failed=['z','z']),row(at=100,failed=['f','f']),row(at=100,failed=['f']),green(),row(at=100,failed=['a'])]
 s=report(rs);t=report(rs,args=())
 assert [r['cases'] for r in reds(s)]==[[dict(id='f',rows=2)],[dict(id=x,rows=n) for x,n in [('z',2),('a',1),('b',1),('c',1),('d',1)]]] ,s
 assert len(lines(t))==2 and '"f" (2)' in lines(t)[0],t
elif case=='v1-123.control-no-week':
 rs=[row(at=None,failed=['legacy123']),green()]
 s=report(rs);t=report(rs,args=())
 assert not reds(s) and not lines(t),s
 assert objects(s,'reds')==[dict(kind='reds',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=1,cases=[dict(id='legacy123',rows=1)])],s
 assert 'reds: 1 suite-red, 1 green again' in t,t
else:raise AssertionError('unrouted '+case)
if 's' in locals() and s.startswith('{'):
 for r in reds(s):
  assert set(r)=={'kind','week','suite_red','green_again','green_again_share','green_again_secs','named','cases'},r
  assert all(type(r[k]) is int for k in ('suite_red','green_again','named')),r
  assert all(set(c)=={'id','rows'} and type(c['rows']) is int for c in r['cases']),r
PY123
  pass
}
