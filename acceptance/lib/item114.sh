# Item 114: offline report suite check runs, exact case routing.
item114_langs() { echo core; }
item114_cases() {
 local c
 for c in preservation empty-checks basic names pr-order eligibility since dedup shared cache-failure atomic commits-shape commits-sha json check-shape check-entry dates conclusions skipped same-time new-commit precedence two-reds pages text partial missing-gh no-start signal call-order timeout timeout-before timeout-status config-reader control-no-round control-no-config control-empty control-plain control-invalid control-gh; do echo "v1-114.$c"; done
}
item114_case() {
 EXPECT="item 114: ${CASE#v1-114.}"
 v1_start codex
 must_accept "item 114 report contract" cmd "$PY" - "$CASE" "$(command -v shipcraft)" "$CW" "$ST" "$CB" <<'PY114'
import json,os,shutil,stat,subprocess,sys,time
from pathlib import Path
case,binary,cw,st,cb=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve();st=Path(st);cb=Path(cb);live_root=Path.cwd()
root=cw/"report114 space 'quote";root.mkdir();env=dict(os.environ);realgit=shutil.which('git')
for k in subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
def run(*args):
 p=subprocess.run(list(map(str,args)),cwd=root,env=env,input=b'',capture_output=True,timeout=90)
 print('COMMAND114',args,p.returncode,repr(p.stdout),repr(p.stderr),flush=True);return p
def git(*args):
 p=run(realgit,*args);assert p.returncode==0,p.stderr;return p.stdout.decode().strip()
def write(name,value):
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value if isinstance(value,bytes) else value.encode())
def data(p):return [json.loads(x) for x in p.read_text().splitlines()] if p.is_file() else []
def snapshot():
 return {str(p.relative_to(root)):(p.lstat().st_mode,os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None) for p in root.rglob('*')}
git('init','-q','-b','main');git('config','gc.auto','0');git('config','maintenance.auto','false')
write('README.md','fixture114\n');git('add','README.md');git('commit','-qm','fixture114');git('tag','v1.0.0')
tools=cw/'tools114';tools.mkdir();table=cw/'answers114';calls=cw/'calls114'
# API list-status shape: gh --paginate --slurp wraps each REST array in a page.
(tools/'gh').write_text('#!'+sys.executable+'\n'+'''import json,os,signal,sys,time
from pathlib import Path
'''+f'table=Path({str(table)!r});calls=Path({str(calls)!r})\n'+'''a=sys.argv[1:]
with calls.open('a') as f:f.write(json.dumps(a)+'\\n')
r=json.loads(table.read_text()).get(json.dumps(a),{'exit':91})
sys.stderr.write('private gh diagnostic114\\n')
if r.get('sleep'):time.sleep(r['sleep'])
if r.get('signal'):os.kill(os.getpid(),signal.SIGTERM)
sys.stdout.buffer.write(bytes.fromhex(r['raw']) if 'raw' in r else json.dumps(r.get('json')).encode())
raise SystemExit(r.get('exit',0))
''');(tools/'gh').chmod(0o755);env['PATH']=str(tools)+os.pathsep+env['PATH']
A='a'*40;B='b'*40;C='c'*40
P=['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']
def api(sha):return ['api','--paginate','--slurp',f'repos/{{owner}}/{{repo}}/commits/{sha}/statuses?per_page=100']
def row(**kw):
 r=dict(layer='review',result='passed',pr=7,commit='unavailable',at=100,secs=1,lock='',locks=[],branch='topic114',code='');r.update(kw);return r
def status(n=2,**kw):
 r=dict(context='shipcraft/review',description=f'on this machine: CHANGES REQUESTED, Blocking {n} (codex)',created_at='2026-01-02T03:04:05Z',state='failure');r.update(kw);return r
def answers(entries):table.write_text(json.dumps({json.dumps(k):v for k,v in entries}))
def report(rs,args=('--json','--github')):
 if rs is not None:write('.git/shipcraft/runs.jsonl',rs if isinstance(rs,bytes) else ''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in rs))
 before=snapshot();p=run(binary,'report',*args)
 assert p.returncode==0 and not p.stderr,(p.returncode,p.stderr)
 assert snapshot()==before,'report wrote repository state'
 return p.stdout.decode()
def objects(s,kind):return [r for r in map(json.loads,s.splitlines()) if r['kind']==kind]
def review(s):return objects(s,'review')[0]
def block(s):
 r=review(s);return tuple(r.get(k) for k in ('blocking','blocking_read','blocking_commits','blocking_missing','blocking_most'))

N=['zeta suite/β','alpha lint']
def config(names=N):
 write('.shipcraft.toml','shipcraft_min="2.18"\nlang="python"\nrunner="pytest"\ntest_command="echo {junit}"\n[execution]\nci="github"\nreview="off"\nsuite_checks='+json.dumps(names,ensure_ascii=False)+'\n')
config()
def commits(pr):return ['api','--paginate','--slurp',f'repos/{{owner}}/{{repo}}/pulls/{pr}/commits?per_page=100']
def checks(sha):return ['api','--paginate','--slurp',f'repos/{{owner}}/{{repo}}/commits/{sha}/check-runs?filter=all&per_page=100']
def runcheck(name=N[0],conclusion='failure',at='2026-01-02T03:04:05Z',**kw):
 r=dict(name=name,status='completed',conclusion=conclusion,completed_at=at);r.update(kw);return r
def pages(*runs):return [dict(total_count=len(runs),check_runs=list(runs))]
def listed(*shas):return [[dict(sha=s) for s in shas]]
def exercise(rs,entries,args=(),text=True):
 answers(entries);calls.unlink(missing_ok=True);s=report(rs,('--json','--github',*args));cs=data(calls)
 t=''
 if text:
  calls.unlink(missing_ok=True);t=report(rs,('--github',*args));assert data(calls)==cs,'text/JSON calls differ'
 return objects(s,'checks'),s,t,cs
if case=='v1-114.preservation':
 rs=[row(commit=A),row(result='refused',commit=A)]
 entries=[(api(A),{'json':[[status(4)]]}),(commits(7),{'json':listed(B)}),(checks(B),{'exit':9})]
 q,s,t,cs=exercise(rs,entries)
 assert q and q[0]['missing']=={'gh failed':1} and q[0]['names'][0]['runs']==0,s
 config([]);q0,s0,t0,cs0=exercise(rs,entries)
 assert [r for r in map(json.loads,s.splitlines()) if r['kind']!='checks']==list(map(json.loads,s0.splitlines())),(s,s0)
 assert '\n'.join(l for l in t.split('\n') if not l.startswith('checks:'))==t0,(t,t0)
 assert cs==[api(A),commits(7),checks(B)] and cs0==[api(A)],cs
elif case=='v1-114.empty-checks':
 q,s,t,cs=exercise([row(commit=A)],[(api(A),{'json':[[status(2),dict(context=N[0],state='failure',description=None,created_at='bad')]]}),(commits(7),{'json':listed(A)}),(checks(A),{'json':[dict(total_count=0,check_runs=[]),dict(total_count=0,check_runs=[])]})])
 assert q and q[0]==dict(kind='checks',prs=1,prs_read=1,missing={},names=[dict(name=n,runs=0,red=0,green_again=0,new_commit=0,still_red=0) for n in N]),s
 assert block(s)==(2,1,1,{},[dict(pr=7,blocking=2)]),s
elif case=='v1-114.basic':
 q,s,t,cs=exercise([row()],[(commits(7),{'json':listed(A)}),(checks(A),{'json':pages(runcheck(),runcheck(N[1],'success'))})])
 assert q==[dict(kind='checks',prs=1,prs_read=1,missing={},names=[dict(name=N[0],runs=1,red=1,green_again=0,new_commit=0,still_red=1),dict(name=N[1],runs=1,red=0,green_again=0,new_commit=0,still_red=0)])],s
 assert cs==[commits(7),checks(A)],cs
 assert [r['kind'] for r in map(json.loads,s.splitlines())]==['meta','review','checks','dora','github'],s
 assert objects(s,'github')==[dict(kind='github',selected=0,merge_filled=0,waiting_filled=0,missing={})],s
 assert objects(s,'review')[0]['blocking_missing']=={'no commit in the run log':1},s
elif case=='v1-114.names':
 config(['other: ,; "quoted" β','zeta suite/β'])
 q,s,t,cs=exercise([row()],[(commits(7),{'json':listed(A)}),(checks(A),{'json':pages(runcheck('other: ,; "quoted" β','success'),runcheck('zeta suite/β ','failure'),runcheck('Zeta suite/β','failure'))})])
 assert q and [(r['name'],r['runs'],r['red']) for r in q[0]['names']]==[('other: ,; "quoted" β',1,0),('zeta suite/β',0,0)],s
 assert json.dumps('other: ,; "quoted" β',ensure_ascii=False)+': 0 red in 1 run(s)' in t,t
elif case=='v1-114.pr-order':
 rs=[row(pr=20),row(pr=2),row(pr=20),row(pr=9007199254740993)]
 q,s,t,cs=exercise(rs,[(commits(n),{'json':[[]]}) for n in (20,2,9007199254740993)])
 assert q and (q[0]['prs'],q[0]['prs_read'])==(3,3),s
 assert cs==[commits(n) for n in (20,2,9007199254740993)],cs
elif case=='v1-114.eligibility':
 rs=[row(pr=8,reused=True),row(pr=9,result='error'),row(pr=10,layer='pr'),row(pr=11,layer='merge'),row(pr=True),row(pr=7.0),row(pr=0),row(pr=12,escape=True),row(pr=13,reused='true',result='refused'),row(pr=14,commit=None)]
 q,s,t,cs=exercise(rs,[(commits(n),{'json':[[]]}) for n in (13,14)])
 assert q and (q[0]['prs'],q[0]['prs_read'])==(2,2) and cs==[commits(13),commits(14)],s
elif case=='v1-114.since':
 q,s,t,cs=exercise([row(at=1),row(pr=8,at=2)],[(commits(n),{'json':[[]]}) for n in (7,8)],('--since','v1.0.0'))
 assert q and q[0]['prs_read']==2 and cs==[commits(7),commits(8)],s
elif case=='v1-114.dedup':
 q,s,t,cs=exercise([row()],[(commits(7),{'json':[[dict(sha=B),dict(sha=A)],[],[dict(sha=B),dict(sha=C),dict(sha=A)]]}),*[(checks(x),{'json':pages(runcheck())}) for x in (B,A,C)]])
 assert q and q[0]['names'][0]['runs']==3 and q[0]['names'][0]['still_red']==3,s
 assert cs==[commits(7),checks(B),checks(A),checks(C)],cs
elif case=='v1-114.shared':
 q,s,t,cs=exercise([row(),row(pr=8)],[(commits(7),{'json':listed(A,B)}),(commits(8),{'json':listed(A)}),(checks(A),{'json':pages(runcheck())}),(checks(B),{'json':pages(runcheck(conclusion='success',at='2026-01-03T00:00:00Z'))})])
 assert q and q[0]['names'][0]==dict(name=N[0],runs=3,red=2,green_again=0,new_commit=1,still_red=1),s
 assert cs==[commits(7),checks(A),checks(B),commits(8)],cs
elif case=='v1-114.cache-failure':
 entries=[(commits(n),{'json':listed(A,B)}) for n in (7,8)]+[(checks(A),{'exit':23,'json':pages(runcheck())})]
 q,s,t,cs=exercise([row(),row(pr=8)],entries)
 assert q and q[0]['missing']=={'gh failed':2} and q[0]['prs_read']==0,s
 assert cs==[commits(7),checks(A),commits(8)],cs
 q2,s2,t2,cs2=exercise([row(),row(pr=8)],entries)
 assert cs2==cs and q2==q,(s2,cs2)
elif case=='v1-114.atomic':
 q,s,t,cs=exercise([row(),row(pr=8),row(pr=9)],[(commits(7),{'json':listed(A,B,C)}),(checks(A),{'json':pages(runcheck())}),(checks(B),{'exit':3}),(commits(8),{'json':listed(C)}),(checks(C),{'json':pages(runcheck(conclusion='success'))}),(commits(9),{'exit':4})])
 assert q and q[0]['prs_read']==1 and q[0]['missing']=={'gh failed':2} and q[0]['names'][0]['runs']==1 and q[0]['names'][0]['red']==0,s
 assert cs==[commits(7),checks(A),checks(B),commits(8),checks(C),commits(9)],cs
elif case=='v1-114.commits-shape':
 for value in ([],{},None,[{}],[None],[[None]],[[3]],[[[]]],[[{}]],[[dict(sha=A)],{}]):
  q,s,t,cs=exercise([row()],[(commits(7),{'json':value})])
  assert q and q[0]['missing']=={'unreadable answer from gh':1} and q[0]['prs_read']==0 and cs==[commits(7)],s
elif case=='v1-114.commits-sha':
 for sha in ('A'*40,'a'*39,'a'*41,'g'*40,' '+A,A+'\n',None,True,1,[],{}):
  q,s,t,cs=exercise([row()],[(commits(7),{'json':[[dict(sha=A)],[dict(sha=sha)]]})])
  assert q and q[0]['missing']=={'unreadable answer from gh':1} and cs==[commits(7)],s
elif case=='v1-114.json':
 for raw in (b'\xff',b'[[',b'\xef\xbb\xbf[[]]',b'[[]] trailing',b'[[{"sha":1e400}]]'):
  for endpoint in (commits(7),checks(A)):
   entries=[(commits(7),{'json':listed(A)}),(endpoint,{'raw':raw.hex()})]
   q,s,t,cs=exercise([row()],entries)
   assert q and q[0]['missing']=={'unreadable answer from gh':1} and q[0]['prs_read']==0,s
elif case=='v1-114.check-shape':
 for value in ([],{},None,[[]],[{}],[dict(total_count=True,check_runs=[])],[dict(total_count=0.0,check_runs=[])],[dict(total_count=-1,check_runs=[])],[dict(total_count=1,check_runs=[])],[dict(total_count=0,check_runs=None)],[dict(total_count=1,check_runs=[runcheck()]),dict(total_count=0,check_runs=[])]):
  q,s,t,cs=exercise([row()],[(commits(7),{'json':listed(A)}),(checks(A),{'json':value})])
  assert q and q[0]['missing']=={'unreadable answer from gh':1} and q[0]['names'][0]['runs']==0,s
elif case=='v1-114.check-entry':
 bad=[None,[],3,{},dict(name=None,status='queued',conclusion=None),dict(name='other',status=4,conclusion=None),dict(name='other',status='queued'),dict(name='other',status='queued',conclusion=3)]
 for entry in bad:
  q,s,t,cs=exercise([row()],[(commits(7),{'json':listed(A)}),(checks(A),{'json':pages(runcheck(),entry)})])
  assert q and q[0]['missing']=={'unreadable answer from gh':1} and q[0]['names'][0]['runs']==0,s
elif case=='v1-114.dates':
 for date in (None,True,2,'2025-02-29T00:00:00Z','0000-01-01T00:00:00Z','2026-01-02T24:00:00Z','2026-01-02T00:60:00Z','2026-01-02T00:00:60Z','2026-01-02T00:00:00+00:00','2026-01-02T00:00:00.1Z','2026-1-02T00:00:00Z','2026-01-02t00:00:00z','2026-01-02T00:00:00Z\n'):
  q,s,t,cs=exercise([row()],[(commits(7),{'json':listed(A)}),(checks(A),{'json':pages(runcheck(conclusion='cancelled',at=date))})])
  assert q and q[0]['missing']=={'unreadable answer from gh':1},s
elif case=='v1-114.conclusions':
 rs=[runcheck(conclusion=c) for c in ('failure','timed_out','success','cancelled','skipped','neutral','action_required','stale','unknown',None)]
 q,s,t,cs=exercise([row()],[(commits(7),{'json':listed(A)}),(checks(A),{'json':pages(*rs)})])
 assert q and q[0]['names'][0]==dict(name=N[0],runs=10,red=2,green_again=0,new_commit=0,still_red=2),s
elif case=='v1-114.skipped':
 rs=[runcheck(name='other',at=False),runcheck(status='queued',at=None),runcheck(status='in_progress',at='bad'),runcheck(status='Completed',at=[]),runcheck(conclusion='success',at='0001-01-01T00:00:00Z'),runcheck(at='9999-12-31T23:59:59Z'),runcheck(N[1],'neutral',at='2024-02-29T00:00:00Z')]
 q,s,t,cs=exercise([row()],[(commits(7),{'json':listed(A)}),(checks(A),{'json':pages(*rs)})])
 assert q and q[0]['names'][0]['runs']==2 and q[0]['names'][0]['still_red']==1 and q[0]['names'][1]['runs']==1,s
elif case=='v1-114.same-time':
 rs=[runcheck(conclusion='success'),runcheck(),runcheck(at='2026-01-01T00:00:00Z'),runcheck(at='2026-01-03T00:00:00Z')]
 q,s,t,cs=exercise([row()],[(commits(7),{'json':listed(A)}),(checks(A),{'json':pages(*rs)})])
 assert q and q[0]['names'][0]==dict(name=N[0],runs=4,red=3,green_again=1,new_commit=0,still_red=2),s
elif case=='v1-114.new-commit':
 q,s,t,cs=exercise([row()],[(commits(7),{'json':listed(B,A,C)}),(checks(B),{'json':pages(runcheck(conclusion='success',at='2026-01-04T00:00:00Z'))}),(checks(A),{'json':pages(runcheck(),runcheck(at='2026-01-03T00:00:00Z'))}),(checks(C),{'json':pages(runcheck(conclusion='success',at='2026-01-03T00:00:00Z'),runcheck(at='2026-01-05T00:00:00Z'))})])
 assert q and q[0]['names'][0]==dict(name=N[0],runs=5,red=3,green_again=0,new_commit=1,still_red=2),s
elif case=='v1-114.precedence':
 q,s,t,cs=exercise([row()],[(commits(7),{'json':listed(A,B)}),(checks(A),{'json':pages(runcheck(),runcheck(conclusion='success',at='2026-01-03T00:00:00Z'))}),(checks(B),{'json':pages(runcheck(conclusion='success',at='2026-01-04T00:00:00Z'),runcheck(N[1]))})])
 assert q and q[0]['names'][0]==dict(name=N[0],runs=3,red=1,green_again=1,new_commit=0,still_red=0) and q[0]['names'][1]['still_red']==1,s
elif case=='v1-114.two-reds':
 q,s,t,cs=exercise([row()],[(commits(7),{'json':listed(A)}),(checks(A),{'json':pages(runcheck(),runcheck(conclusion='timed_out'),runcheck(conclusion='success',at='2026-01-03T00:00:00Z'))})])
 assert q and q[0]['names'][0]==dict(name=N[0],runs=3,red=2,green_again=2,new_commit=0,still_red=0),s
elif case=='v1-114.pages':
 r=runcheck(id=9)
 value=[dict(total_count=3,check_runs=[r]),dict(total_count=3,check_runs=[]),dict(total_count=3,check_runs=[r,runcheck(conclusion='success',at='2026-01-03T00:00:00Z')])]
 raw=json.dumps(value,ensure_ascii=False).replace('"total_count": 3','"total_count": -1, "total_count": 3').encode()+b'\r\n'
 q,s,t,cs=exercise([row()],[(commits(7),{'json':[[],[dict(sha=A)],[]]}),(checks(A),{'raw':raw.hex()})])
 assert q and q[0]['names'][0]==dict(name=N[0],runs=3,red=2,green_again=2,new_commit=0,still_red=0),s
elif case=='v1-114.text':
 q,s,t,cs=exercise([row()],[(commits(7),{'json':[[]]})])
 expected='checks: 1 of 1 reviewed PR(s) read; "zeta suite/β": 0 red in 0 run(s), 0 green again on the same commit, 0 fixed by a new commit, 0 still red; "alpha lint": 0 red in 0 run(s), 0 green again on the same commit, 0 fixed by a new commit, 0 still red'
 assert q and q[0]['prs_read']==1 and q[0]['missing']=={},s
 assert expected in t.splitlines(),t
 ls=t.splitlines();i=ls.index(expected);assert ls[i-1].startswith('review:') and ls[i+1]=='DORA',t
elif case=='v1-114.partial':
 q,s,t,cs=exercise([row(),row(pr=8),row(pr=9),row(pr=10)],[(commits(7),{'exit':5}),(commits(8),{'json':[]}),(commits(9),{'json':listed(A)}),(checks(A),{'json':pages(runcheck())}),(commits(10),{'exit':8})])
 assert q and q[0]['prs']==4 and q[0]['prs_read']==1 and q[0]['missing']=={'gh failed':2,'unreadable answer from gh':1} and q[0]['names'][0]['red']==1,s
 assert '; not read: gh failed 2, unreadable answer from gh 1' in t,t
elif case=='v1-114.missing-gh':
 (tools/'gh').unlink();(tools/'git').symlink_to(realgit);env['PATH']=str(tools)
 q,s,t,cs=exercise([row(),row(pr=8)],[])
 assert q and q[0]['missing']=={'gh failed':2} and q[0]['prs_read']==0,s
elif case=='v1-114.no-start':
 (tools/'gh').write_text('#!/nonexistent114/interpreter\n')
 q,s,t,cs=exercise([row(),row(pr=8)],[])
 assert q and q[0]['missing']=={'gh failed':2} and q[0]['prs_read']==0,s
elif case=='v1-114.signal':
 
 q,s,t,cs=exercise([row(),row(pr=8)],[(commits(7),{'signal':True}),(commits(8),{'json':[[]]})])
 assert q and q[0]['missing']=={'gh failed':1} and q[0]['prs_read']==1,s
elif case=='v1-114.call-order':
 rs=[row(layer='red',lock='G'),row(layer='merge',lock='G',locks=['G'],pr=97,base='main',default_branch='main'),row(commit=A)]
 q,s,t,cs=exercise(rs,[(P,{'exit':4}),(api(A),{'json':[[status(3)]]}),(commits(7),{'json':listed(A)}),(checks(A),{'exit':9})])
 assert q and q[0]['missing']=={'gh failed':1},s
 assert cs==[P,api(A),commits(7),checks(A)],cs
 assert block(s)==(3,1,1,{},[dict(pr=7,blocking=3)]) and objects(s,'github')[0]['missing']=={'gh failed':1},s
elif case=='v1-114.timeout':
 rs=[row(),row(pr=8),row(pr=9),row(pr=10)]
 entries=[(commits(7),{'json':listed(A)}),(checks(A),{'json':pages(runcheck())}),(commits(8),{'json':listed(B)}),(checks(B),{'sleep':75}),(commits(9),{'json':listed(A)})]
 start=time.time();q,s,t,cs=exercise(rs,entries,text=False)
 assert q and q[0]['prs_read']==1 and q[0]['missing']=={'gh timed out':3} and q[0]['names'][0]['red']==1,s
 assert cs==[commits(7),checks(A),commits(8),checks(B)] and 59<=time.time()-start<75,cs
elif case=='v1-114.timeout-before':
 rs=[row(layer='red',lock='G'),row(layer='merge',lock='G',locks=['G'],pr=97,base='main',default_branch='main'),row(),row(pr=8)]
 start=time.time();q,s,t,cs=exercise(rs,[(P,{'sleep':75})],text=False)
 assert q and q[0]['prs_read']==0 and q[0]['missing']=={'gh timed out':2} and cs==[P],s
 assert objects(s,'github')[0]['missing']=={'gh timed out':1} and 59<=time.time()-start<75,s
elif case=='v1-114.timeout-status':
 start=time.time();q,s,t,cs=exercise([row(commit=A),row(pr=8)],[(api(A),{'sleep':75})],text=False)
 assert q and q[0]['prs_read']==0 and q[0]['missing']=={'gh timed out':2} and cs==[api(A)],s
 assert objects(s,'review')[0]['blocking_missing']=={'gh timed out':1,'no commit in the run log':1} and 59<=time.time()-start<75,s
elif case=='v1-114.config-reader':
 p=root/'.shipcraft.toml';original=p.read_text();write('nested/.shipcraft.toml','invalid')
 write('config114.toml',original.replace('[execution]','[execution] # comment').replace('\n','\r\n'));p.unlink();p.symlink_to('config114.toml')
 q,s,t,cs=exercise([row()],[(commits(7),{'json':[[]]})])
 assert q and q[0]['prs_read']==1 and [r['name'] for r in q[0]['names']]==N and cs==[commits(7)],s
elif case=='v1-114.control-no-round':
 q,s,t,cs=exercise([row(reused=True),row(pr=8,result='error'),row(pr=None)],[])
 assert q==[] and not objects(s,'review') and cs==[] and 'checks:' not in t,s
elif case=='v1-114.control-no-config':
 (root/'.shipcraft.toml').unlink()
 q,s,t,cs=exercise([row()],[])
 assert not q and cs==[] and objects(s,'review')[0]['rounds']==1 and 'checks:' not in t,s
elif case=='v1-114.control-empty':
 config([])
 q,s,t,cs=exercise([row(),row(result='refused')],[])
 assert not q and cs==[] and objects(s,'review')[0]['changes_requested']==1 and objects(s,'review')[0]['second_round']==1 and 'checks:' not in t,s
elif case=='v1-114.control-plain':
 answers([]);s=report([row(),row(pr=8)],('--json',));t=report(None,())
 assert not objects(s,'checks') and not calls.exists() and objects(s,'review')[0]==dict(kind='review',prs=2,rounds=2,changes_requested=0,second_round=0,second_round_share=0,most=[]),s
 assert 'checks:' not in t and 'review: 2 PR(s) reviewed in 2 round(s)' in t,t
elif case=='v1-114.control-invalid':
 original=(root/'.shipcraft.toml').read_text()
 for value in ('not TOML',original.replace('ci="github"','ci="local"'),original.replace('"2.18"','"2.17"'),original.replace(json.dumps(N,ensure_ascii=False),'["duplicate", "duplicate"]'),original.replace(json.dumps(N,ensure_ascii=False),'[4]')):
  write('.shipcraft.toml',value);q,s,t,cs=exercise([row()],[])
  assert not q and cs==[] and objects(s,'review')[0]['rounds']==1 and 'checks:' not in t,s
 (root/'.shipcraft.toml').unlink();(root/'.shipcraft.toml').mkdir()
 q,s,t,cs=exercise([row()],[])
 assert not q and cs==[] and objects(s,'review')[0]['rounds']==1,s
elif case=='v1-114.control-gh':
 entries=[(api(A),{'json':[[status(17)]]}),(commits(7),{'json':listed(B,A)}),(checks(B),{'json':pages(runcheck(N[1],'neutral'))})]
 answers(entries)
 for argv,response in entries:
  p=run(tools/'gh',*argv);assert p.returncode==0 and json.loads(p.stdout)==response['json'],p.stdout
 config([])
 q,s,t,cs=exercise([row(commit=A)],entries)
 assert not q and block(s)==(17,1,1,{},[dict(pr=7,blocking=17)]) and cs==[api(A)],s
else:raise AssertionError('unrouted '+case)
if 'q' in locals() and q:
 assert len(q)==1 and set(q[0])=={'kind','prs','prs_read','missing','names'},q
 assert type(q[0]['prs']) is int and type(q[0]['prs_read']) is int,q
 assert list(q[0]['missing'])==sorted(q[0]['missing']) and all(type(v) is int for v in q[0]['missing'].values()),q
 for r in q[0]['names']:
  assert set(r)=={'name','runs','red','green_again','new_commit','still_red'},r
  assert all(type(r[k]) is int for k in ('runs','red','green_again','new_commit','still_red')),r
  assert r['red']==r['green_again']+r['new_commit']+r['still_red'],r
PY114
 pass
}
