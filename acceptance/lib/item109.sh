# Item 109, spec a332363: public report/CI only; no implementation reader.
item109_langs() { echo core; }
item109_cases() {
  local c
  for c in basic repeated order commit red-filter red-commit green-filter green-commit green-flags green-other escape times times-invalid failed-array failed-legacy failed-count ranking top5 byte-ids reader malformed json-whole json-fraction text-zero text-minute text-hour text-escape order-size order-day since github git-failure config-failure text-round control-refusal control-report control-github control-ci; do echo "v1-109.$c"; done
}
item109_case() {
  EXPECT="item 109: ${CASE#v1-109.}"
  v1_start codex
  must_accept 'item 109 report contract' cmd "$PY" - "$CASE" "$(command -v shipcraft)" "$CW" <<'PY109'
import json,os,shlex,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/"repo109 space 'quote";root.mkdir();realgit=shutil.which('git');env=dict(os.environ)
for k in subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
def run(*args):
 p=subprocess.run(list(map(str,args)),cwd=root,env=env,input=b'',capture_output=True,timeout=120)
 print('COMMAND109',args,p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 return p
def git(*args):
 p=run(realgit,*args);assert p.returncode==0,('fixture git',p.stderr);return p.stdout.decode().strip()
def write(name,data):
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
def snapshot():
 return {str(p.relative_to(root)):(stat.S_IFMT(p.lstat().st_mode),stat.S_IMODE(p.lstat().st_mode),os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None) for p in root.rglob('*')}
def data(p):return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
git('init','-q','-b','main');git('config','gc.auto','0');git('config','maintenance.auto','false')
write('README.md','item109 fixture\n');write('.git/shipcraft/sentinel',b'keep109\x00\r\n')
tools=cw/'tools109';tools.mkdir();calls=cw/'git-calls109';ghcalls=cw/'gh-calls109';proof=cw/'proof109';fault=cw/'git-fault109';ghfault=cw/'gh-fault109'
# Transparent Git probe: public command recording and one injected read failure.
(tools/'git').write_text('#!'+sys.executable+'\n'+"import json,os,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith open("+repr(str(calls))+",'a') as f:f.write(json.dumps(a)+'\\n')\nif Path("+repr(str(fault))+").exists() and 'for-each-ref' in a:raise SystemExit(93)\nos.execv("+repr(realgit)+",["+repr(realgit)+",*a])\n");(tools/'git').chmod(0o755)
# gh 2.x pr-view JSON shape, as item 79; unexpected calls cannot access a service.
(tools/'gh').write_text('#!'+sys.executable+'\n'+"import json,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith open("+repr(str(ghcalls))+",'a') as f:f.write(json.dumps(a)+'\\n')\nif a!=['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']:raise SystemExit(91)\nif Path("+repr(str(ghfault))+").exists():raise SystemExit(92)\nprint(json.dumps(dict(number=97,state='OPEN',mergedAt=None,headRefOid='a'*40,mergeCommit=None)))\n");(tools/'gh').chmod(0o755)
env['PATH']=str(tools)+os.pathsep+env['PATH']
env.update(GIT_AUTHOR_DATE='1700000000 +0000',GIT_COMMITTER_DATE='1700000000 +0000')
git('add','README.md');git('commit','-qm','fixture109');git('tag','v1.0.0');base=git('rev-parse','HEAD')
env.update(GIT_AUTHOR_DATE='1700086400 +0000',GIT_COMMITTER_DATE='1700086400 +0000')
write('README.md','second release109\n');git('add','README.md');git('commit','-qm','release109');git('tag','v2.0.0')
log=root/'.git/shipcraft/runs.jsonl'
def row(**kw):
 r=dict(layer='ci',result='refused',code='suite-red',commit='foreign109',at=100,secs=45,lock='',locks=[],branch='topic109')
 r.update(kw);return r
def green(**kw):return row(**dict(dict(result='passed',code=''),**kw))
def wire(rs):return ''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in rs).encode()
def report(rs,args=('--json',)):
 if rs is not None:write('.git/shipcraft/runs.jsonl',rs if isinstance(rs,bytes) else wire(rs))
 before=snapshot();p=run(binary,'report',*args)
 assert p.returncode==0 and not p.stderr,(p.returncode,p.stdout,p.stderr)
 assert snapshot()==before,'report wrote repository state'
 return p.stdout.decode()
def objects(s,kind):return [r for r in (json.loads(x) for x in s.split('\n') if x) if r['kind']==kind]
def reds(s):return objects(s,'reds')
def lines(s):return [x for x in s.split('\n') if x.startswith('reds:')]
# Each oracle lives in its exact-id arm. No shared helper computes expected counts.
if case=='v1-109.basic':
 rs=[row(failed=['tests.db::insert']),green()]
 calls.unlink(missing_ok=True);s=report(rs);observed=data(calls)
 calls.unlink();report([dict(r,code='other') for r in rs])
 assert data(calls)==observed and not ghcalls.exists(),'new Git/network read'
 assert reds(s)==[dict(kind='reds',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=1,cases=[dict(id='tests.db::insert',rows=1)])],s
elif case=='v1-109.repeated':
 s=report([row(failed=['a']),row(failed=['a'],secs=5),green(),green(),row(failed=['later'])])
 assert reds(s)==[dict(kind='reds',suite_red=3,green_again=2,green_again_share=2/3,green_again_secs=50,named=2,cases=[dict(id='a',rows=2)])],s
elif case=='v1-109.order':
 s=report([green(at=9999),row(at=0),row(commit='b',at=9999),green(commit='b',at=-1),row(commit='b',at=-2)])
 assert reds(s)==[dict(kind='reds',suite_red=3,green_again=1,green_again_share=1/3,green_again_secs=45,named=0,cases=[])],s
elif case=='v1-109.commit':
 s=report([row(commit='AbC'),green(commit='abc'),row(commit=' x '),green(commit='x'),row(commit='foreign109',branch='one',lock='A',locks=['A']),green(commit='foreign109',branch='two',lock='B',locks=['B'],secs=999)])
 assert reds(s)==[dict(kind='reds',suite_red=3,green_again=1,green_again_share=1/3,green_again_secs=45,named=0,cases=[])],s
elif case=='v1-109.red-filter':
 rs=[row(),green()]
 for key,values in [('layer',['hook','pr','review','CI',None,True]),('result',['passed','error','REFUSED',None]),('code',['no-report','lock-not-closed','case-broke','build-failed','timed-out','SUITE-RED',None])]:
  for v in values:rs.append(row(**{key:v}))
  r=row();r.pop(key);rs.append(r)
 s=report(rs);assert not objects(s,'gap'),s
 assert reds(s)==[dict(kind='reds',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],s
elif case=='v1-109.red-commit':
 rs=[row(commit=' '),green(commit=' ')]
 for v in ('',None,False,1,1.0,[],{}):rs.append(row(commit=v))
 r=row();r.pop('commit');rs.append(r);s=report(rs);assert not objects(s,'gap'),s
 assert reds(s)==[dict(kind='reds',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],s
elif case=='v1-109.green-filter':
 rs=[row()]
 for key,values in [('layer',['hook','pr','review','CI',None]),('result',['refused','error','PASSED',None])]:
  for v in values:rs.append(green(**{key:v}))
  r=green();r.pop(key);rs.append(r)
 s=report(rs)
 assert reds(s)==[dict(kind='reds',suite_red=1,green_again=0,green_again_share=0,green_again_secs=0,named=0,cases=[])],s
elif case=='v1-109.green-commit':
 rs=[row()]+[green(commit=v) for v in ('',None,False,1,[],{},'different')]
 r=green();r.pop('commit');rs.append(r);s=report(rs);assert not objects(s,'gap'),s
 assert reds(s)==[dict(kind='reds',suite_red=1,green_again=0,green_again_share=0,green_again_secs=0,named=0,cases=[])],s
elif case=='v1-109.green-flags':
 s=report([row(commit='docs'),green(commit='docs',docs_only=True),row(commit='checks'),green(commit='checks',suite_in_checks=True),row(commit='both'),green(commit='both',docs_only=True,suite_in_checks=True)])
 assert reds(s)==[dict(kind='reds',suite_red=3,green_again=0,green_again_share=0,green_again_secs=0,named=0,cases=[])],s
elif case=='v1-109.green-other':
 rs=[row(commit='missing'),green(commit='missing',code='irrelevant')]
 for i,v in enumerate((False,None,0,1,'true',[],{})):
  rs += [row(commit=str(i),docs_only=True,suite_in_checks=True),green(commit=str(i),docs_only=v,suite_in_checks=v)]
 s=report(rs)
 assert reds(s)==[dict(kind='reds',suite_red=8,green_again=8,green_again_share=1,green_again_secs=360,named=0,cases=[])],s
elif case=='v1-109.escape':
 s=report([row(escape=True),row(commit='b'),green(commit='b',escape=True),row(commit='c',escape=False),green(commit='c')])
 assert reds(s)==[dict(kind='reds',suite_red=2,green_again=1,green_again_share=0.5,green_again_secs=45,named=0,cases=[])],s
elif case=='v1-109.times':
 s=report([row(secs=0),row(secs=1.25),row(secs=2),green(secs=999),row(secs=800)])
 assert reds(s)==[dict(kind='reds',suite_red=4,green_again=3,green_again_share=0.75,green_again_secs=3.25,named=0,cases=[])],s
elif case=='v1-109.times-invalid':
 rs=[row(secs=v) for v in (-1,-0.5,True,False,None,'45',[],{})];r=row();r.pop('secs');rs += [r,green()]
 s=report(rs);assert not objects(s,'gap'),s
 assert reds(s)==[dict(kind='reds',suite_red=9,green_again=9,green_again_share=1,green_again_secs=0,named=0,cases=[])],s
elif case=='v1-109.failed-array':
 s=report([row(failed=['a','a',None,1,True,{},[], '', 'b']),row(failed=[]),row(failed=[None,False]),green(),row(failed=['never'])])
 assert reds(s)==[dict(kind='reds',suite_red=4,green_again=3,green_again_share=0.75,green_again_secs=135,named=3,cases=[dict(id='',rows=1),dict(id='a',rows=1),dict(id='b',rows=1)])],s
elif case=='v1-109.failed-legacy':
 rs=[row()]+[row(failed=v) for v in (None,'a',True,1,{})]+[green()];s=report(rs)
 assert reds(s)==[dict(kind='reds',suite_red=6,green_again=6,green_again_share=1,green_again_secs=270,named=0,cases=[])],s
elif case=='v1-109.failed-count':
 s=report([row(failed=['a'],failed_count=999),row(failed=['a','b'],failed_count=0),row(failed_count=['bad']),green(failed=['green-only'])])
 assert reds(s)==[dict(kind='reds',suite_red=3,green_again=3,green_again_share=1,green_again_secs=135,named=2,cases=[dict(id='a',rows=2),dict(id='b',rows=1)])],s
elif case=='v1-109.ranking':
 s=report([row(failed=['a','z','z']),row(failed=['z','b']),row(failed=['b','z']),green(),row(commit='unfixed',failed=['a']*20)])
 assert reds(s)==[dict(kind='reds',suite_red=4,green_again=3,green_again_share=0.75,green_again_secs=135,named=3,cases=[dict(id='z',rows=3),dict(id='b',rows=2),dict(id='a',rows=1)])],s
elif case=='v1-109.top5':
 s=report([row(failed=['z','f','e','d','c','b','a']),row(failed=['z']),green()])
 assert reds(s)==[dict(kind='reds',suite_red=2,green_again=2,green_again_share=1,green_again_secs=90,named=2,cases=[dict(id=x,rows=n) for x,n in [('z',2),('a',1),('b',1),('c',1),('d',1)]])],s
elif case=='v1-109.byte-ids':
 s=report([row(failed=['é','e\u0301','api:t','t','API:t']),green()])
 assert reds(s)==[dict(kind='reds',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=1,cases=[dict(id=x,rows=1) for x in ['API:t','api:t','e\u0301','t','é']])],s
elif case=='v1-109.reader':
 raw=b'\xef\xbb\xbf'+wire([row(failed=['a\u2028\u2029'])]).replace(b'\n',b'\r\n')+b' \t\r\n'
 raw+=wire([row(failed=['BAD109'])]).replace(b'BAD109',b'\xff')
 raw+=wire([green()]).replace(b'"result": "passed"',b'"result": "error", "result": "passed"')[:-1]+b'\r'
 s=report(raw);assert not objects(s,'gap'),s
 assert reds(s)==[dict(kind='reds',suite_red=2,green_again=2,green_again_share=1,green_again_secs=90,named=2,cases=[dict(id='a\u2028\u2029',rows=1),dict(id='\ufffd',rows=1)])],s
elif case=='v1-109.malformed':
 raw=wire([row()])+b'{broken109\n[]\nnull\n'+wire([row(secs='OVER109')]).replace(b'"OVER109"',b'1e400')+wire([green()])
 s=report(raw);assert [r['line'] for r in objects(s,'gap')]==[2,3,4,5],s
 assert reds(s)==[dict(kind='reds',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],s
elif case=='v1-109.json-whole':
 s=report([row(secs=2.0),green()]);r=reds(s)
 assert r==[dict(kind='reds',suite_red=1,green_again=1,green_again_share=1,green_again_secs=2,named=0,cases=[])],s
 assert all(type(r[0][k]) is int for k in ('suite_red','green_again','green_again_share','green_again_secs','named')),r
elif case=='v1-109.json-fraction':
 s=report([row(secs=0.25),green(),row(),row()]);r=reds(s)
 assert r==[dict(kind='reds',suite_red=3,green_again=1,green_again_share=1/3,green_again_secs=0.25,named=0,cases=[])],s
 assert type(r[0]['suite_red']) is int and type(r[0]['named']) is int,r
elif case=='v1-109.text-zero':
 s=report([row(failed=['not-green'])],args=())
 assert lines(s)==['reds: 1 suite-red, 0 green again on the same commit (0%), 0 s of CI; cases named in 0: none'],s
elif case=='v1-109.text-minute':
 s=report([row(secs=60,failed=['z','a']),row(secs=65,failed=['z']),green(),row()],args=())
 assert lines(s)==['reds: 3 suite-red, 2 green again on the same commit (67%), 2 min 5 s of CI; cases named in 2: "z" (2), "a" (1)'],s
elif case=='v1-109.text-hour':
 s=report([row(secs=3602.6,failed=[]),green()],args=())
 assert lines(s)==['reds: 1 suite-red, 1 green again on the same commit (100%), 1 h 0 min 3 s of CI; cases named in 1: none'],s
elif case=='v1-109.text-escape':
 ident='"\\\n\r\t\b\f\x00\x01\x1f, () / é\u2028\u2029'
 rs=[row(failed=[ident]),green()];s=report(rs,args=());j=report(rs)
 assert lines(s)==['reds: 1 suite-red, 1 green again on the same commit (100%), 45 s of CI; cases named in 1: '+json.dumps(ident,ensure_ascii=False)+' (1)'],repr(s)
 assert reds(j)[0]['cases']==[dict(id=ident,rows=1)],j
elif case=='v1-109.order-size':
 rs=[row(layer='red',lock='A',result='passed',at=1),row(layer='close',lock='A',result='passed',at=2),row(layer='pr',lock='A',locks=['A'],pr=97,product_lines=501,warn_lines=500),row(layer='merge',lock='A',locks=['A'],result='passed',base='main',default_branch='main'),row(),green()]
 raw=wire(rs)+b'{broken109\n';s=report(raw);t=report(raw,args=())
 assert [r['kind'] for r in map(json.loads,s.split('\n')[:-1])]==['meta','lock','day','size','reds','dora','gap'],s
 ls=t.split('\n');i=next(i for i,l in enumerate(ls) if l.startswith('reds:'));assert ls[i-1].startswith('size:') and ls[i+1]=='DORA',t
elif case=='v1-109.order-day':
 rs=[row(layer='red',lock='A',result='passed',at=1),row(layer='merge',lock='A',locks=['A'],result='passed',base='main',default_branch='main'),row(),green()]
 s=report(rs);t=report(rs,args=())
 assert [r['kind'] for r in map(json.loads,s.split('\n')[:-1])]==['meta','lock','day','reds','dora'],s
 ls=t.split('\n');i=next(i for i,l in enumerate(ls) if l.startswith('reds:'));assert ls[i-1].startswith('day ') and ls[i+1]=='DORA',t
elif case=='v1-109.since':
 rs=[row(at=1),green(at=2)];s=report(rs,args=('--json','--since','v2.0.0'));t=report(rs,args=('--since','v2.0.0'))
 assert objects(s,'dora')[0]['deploys']['n']==1,s
 assert reds(s)==[dict(kind='reds',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],s
 assert lines(t)==lines(report(rs,args=())),t
elif case=='v1-109.github':
 rs=[row(layer='red',lock='G',result='passed',at=1),row(layer='close',lock='G',result='passed',at=2),row(layer='pr',lock='G',locks=['G'],pr=97),row(layer='merge',lock='G',locks=['G'],pr=97,result='passed',base='main',default_branch='main'),row(),green()]
 s=report(rs,args=('--json','--github'));assert objects(s,'github')[0]['missing']=={'pr not merged':1},s
 ghfault.touch();f=report(rs,args=('--json','--github'));t=report(rs,args=('--github',))
 assert objects(f,'github')[0]['missing']=={'gh failed':1},f
 assert reds(s)==reds(f)==[dict(kind='reds',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],f
 assert lines(t)==lines(report(rs,args=())),t
elif case=='v1-109.git-failure':
 fault.touch();rs=[row(),green()];s=report(rs);t=report(rs,args=())
 assert objects(s,'dora')[0]['git']['reason'].endswith('exited 93'),s
 assert reds(s)==[dict(kind='reds',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],s
 assert lines(t)==['reds: 1 suite-red, 1 green again on the same commit (100%), 45 s of CI; cases named in 0: none'],t
elif case=='v1-109.config-failure':
 write('.shipcraft.toml','[report]\nrelease_tags=""\n');rs=[row(),green()];s=report(rs);t=report(rs,args=())
 assert objects(s,'dora')[0]['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags is empty',s
 assert reds(s)==[dict(kind='reds',suite_red=1,green_again=1,green_again_share=1,green_again_secs=45,named=0,cases=[])],s
 assert lines(t)==['reds: 1 suite-red, 1 green again on the same commit (100%), 45 s of CI; cases named in 0: none'],t
elif case=='v1-109.text-round':
 rs=[row(secs=59.5),green(),row(),row(),row()];s=report(rs,args=())
 assert lines(s)==['reds: 4 suite-red, 1 green again on the same commit (25%), 1 min 0 s of CI; cases named in 0: none'],s
 s=report([row(secs=0.49),green()],args=())
 assert lines(s)==['reds: 1 suite-red, 1 green again on the same commit (100%), 0 s of CI; cases named in 0: none'],s
elif case=='v1-109.control-refusal':
 write('.git/shipcraft/runs.jsonl',wire([row(),green()]))
 before=snapshot();p=run(binary,'report','--json','--since','v99.0.0')
 assert p.returncode==2 and not p.stdout and p.stderr.strip()==b'report: --since v99.0.0 is not a release tag on refs/heads/main',(p.returncode,p.stdout,p.stderr)
 assert snapshot()==before
 calls.unlink(missing_ok=True);p=run(binary,'report','--json','--json')
 assert p.returncode==2 and not p.stdout and b'invalid arguments:' in p.stderr and b'usage:' in p.stderr,(p.stdout,p.stderr)
 assert not calls.exists() and snapshot()==before
elif case=='v1-109.control-report':
 rs=[row(layer='red',lock='control109',at=17,result='passed'),row(layer='close',lock='control109',at=29,result='passed'),row(layer='merge',lock='control109',locks=['control109'],at=47,result='passed',base='main',default_branch='main')]
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
elif case=='v1-109.control-github':
 rs=[row(layer='red',lock='G',result='passed',at=1),row(layer='close',lock='G',result='passed',at=2),row(layer='pr',lock='G',locks=['G'],pr=97),row(layer='merge',lock='G',locks=['G'],pr=97,result='passed',base='main',default_branch='main')]
 s=report(rs,args=('--json','--github'));assert objects(s,'github')[0]['missing']=={'pr not merged':1},s
 assert data(ghcalls)==[['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']],data(ghcalls)
 ghfault.touch();s=report(rs,args=('--json','--github'));assert objects(s,'github')[0]['missing']=={'gh failed':1} and not reds(s),s
elif case=='v1-109.control-ci':
 # Real pytest JUnit, env switch only; the same committed adapter is run twice.
 write('tests/test_env109.py','import os\ndef test_env109():\n    assert os.environ["MODE109"] == "green"\n')
 trace=cw/'ci-trace109'
 write('adapter109.py','import os,subprocess,sys\nfrom pathlib import Path\nwith open(os.environ["TRACE109"],"a") as f:f.write(os.environ["MODE109"]+"\\n")\np=subprocess.run(["pytest","-q","-p","no:cacheprovider","--junitxml="+sys.argv[1],"tests"])\nraise SystemExit(p.returncode)\n')
 command=shlex.join([sys.executable,'adapter109.py','{junit}'])
 write('.shipcraft.toml','shipcraft_min="0.0"\nlang="python"\nrunner="pytest"\ntest_command='+json.dumps(command)+'\ntest_globs=["tests/**"]\n[execution]\nci="local"\nreview="off"\n')
 write('.gitignore','__pycache__/\n.pytest_cache/\n');git('add','-A');git('commit','-qm','fixture adapter109');head=git('rev-parse','HEAD')
 env.update(MODE109='red',TRACE109=str(trace));p=run(binary,'ci','--base',base)
 assert p.returncode==1,(p.stdout,p.stderr)
 env['MODE109']='green';q=run(binary,'ci','--base',base);assert q.returncode==0,(q.stdout,q.stderr)
 rs=data(log);ci=[r for r in rs if r['layer']=='ci']
 assert len(ci)==2 and ci[0]['code']=='suite-red' and ci[0]['result']=='refused' and ci[1]['result']=='passed',ci
 assert ci[0]['failed']==['tests.test_env109::test_env109'] and ci[0]['failed_count']==1,ci
 assert ci[0]['commit']==ci[1]['commit']==head and head and git('rev-parse','HEAD')==head,ci
 assert trace.read_text()=='red\ngreen\n' and git('status','--porcelain')=='',trace.read_text()
 s=report(None);t=report(None,args=());assert objects(s,'meta')[0]['ci']['count']==2 and objects(s,'meta')[0]['ci']['refusals']=={'suite-red':1},s
 assert 'suite-red' in t and trace.read_text()=='red\ngreen\n',t
else:raise AssertionError('unrouted '+case)
# Generic schema checks, without any case-specific numeric oracle.
if 's' in locals() and s.startswith('{'):
 for r in reds(s):
  assert set(r)=={'kind','suite_red','green_again','green_again_share','green_again_secs','named','cases'},r
  assert all(type(r[k]) is int for k in ('suite_red','green_again','named')),r
  assert type(r['green_again_share']) in (int,float) and type(r['green_again_secs']) in (int,float),r
  assert all(set(c)=={'id','rows'} and type(c['id']) is str and type(c['rows']) is int for c in r['cases']),r
PY109
  pass
}
