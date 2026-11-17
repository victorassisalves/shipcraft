# Item 113: public report, frozen rows, offline argument-keyed GitHub answers.
item113_langs() { echo core; }
item113_cases() {
 local c
 for c in basic grouping shared invalid-commits value-grouping eligibility since call-order failed-cache signal missing-gh no-start reader call-order-success malformed-json shapes entries dates grammar-valid grammar-invalid latest ties skipped no-count ranking top5 partial zero config-failure timeout timeout-lock control-report control-gh control-live live-count live-publish; do echo "v1-113.$c"; done
}
item113_case() {
 EXPECT="item 113: ${CASE#v1-113.}"
 v1_start codex
 case "$CASE" in
 v1-113.control-live|v1-113.live-count|v1-113.live-publish)
  CFGS='execution|ci|"off"'
  pr_main; pr_feature
  git rev-parse HEAD > "$ST/sha"
  pr_outside "$BR"
  ;;
 esac
 case "$CASE" in v1-113.live-publish) i82_publish_fail ;; esac
 must_accept 'item 113 report contract' cmd "$PY" - "$CASE" "$(command -v shipcraft)" "$CW" "$ST" "$CB" <<'PY113'
import json,os,shutil,stat,subprocess,sys,time
from pathlib import Path
case,binary,cw,st,cb=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve();st=Path(st);cb=Path(cb);live_root=Path.cwd()
root=cw/"report113 space 'quote";root.mkdir();env=dict(os.environ);realgit=shutil.which('git')
for k in subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
def run(*args):
 p=subprocess.run(list(map(str,args)),cwd=root,env=env,input=b'',capture_output=True,timeout=90)
 print('COMMAND113',args,p.returncode,repr(p.stdout),repr(p.stderr),flush=True);return p
def git(*args):
 p=run(realgit,*args);assert p.returncode==0,p.stderr;return p.stdout.decode().strip()
def write(name,value):
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value if isinstance(value,bytes) else value.encode())
def data(p):return [json.loads(x) for x in p.read_text().splitlines()] if p.is_file() else []
def snapshot():
 return {str(p.relative_to(root)):(p.lstat().st_mode,os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None) for p in root.rglob('*')}
git('init','-q','-b','main');git('config','gc.auto','0');git('config','maintenance.auto','false')
write('README.md','fixture113\n');git('add','README.md');git('commit','-qm','fixture113');git('tag','v1.0.0')
tools=cw/'tools113';tools.mkdir();table=cw/'answers113';calls=cw/'calls113'
# API list-status shape: gh --paginate --slurp wraps each REST array in a page.
(tools/'gh').write_text('#!'+sys.executable+'\n'+'''import json,os,signal,sys,time
from pathlib import Path
'''+f'table=Path({str(table)!r});calls=Path({str(calls)!r})\n'+'''a=sys.argv[1:]
with calls.open('a') as f:f.write(json.dumps(a)+'\\n')
r=json.loads(table.read_text()).get(json.dumps(a),{'exit':91})
sys.stderr.write('private gh diagnostic113\\n')
if r.get('sleep'):time.sleep(r['sleep'])
if r.get('signal'):os.kill(os.getpid(),signal.SIGTERM)
sys.stdout.buffer.write(bytes.fromhex(r['raw']) if 'raw' in r else json.dumps(r.get('json')).encode())
raise SystemExit(r.get('exit',0))
''');(tools/'gh').chmod(0o755);env['PATH']=str(tools)+os.pathsep+env['PATH']
A='a'*40;B='b'*40;C='c'*40
P=['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']
def api(sha):return ['api','--paginate','--slurp',f'repos/{{owner}}/{{repo}}/commits/{sha}/statuses?per_page=100']
def row(**kw):
 r=dict(layer='review',result='passed',pr=7,commit=A,at=100,secs=1,lock='',locks=[],branch='topic113',code='');r.update(kw);return r
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
def exercise(rs,entries,args=()):
 answers(entries);calls.unlink(missing_ok=True);s=report(rs,('--json','--github',*args));cs=data(calls)
 calls.unlink(missing_ok=True);t=report(rs,('--github',*args));assert data(calls)==cs,'text/JSON call disagreement'
 plain=report(rs,('--json',*args));text=report(rs,args)
 assert data(calls)==cs,'plain report called gh'
 # Preserve every pre-existing field and line (lock enrichment is tested by item79).
 stripped=[{k:v for k,v in r.items() if k not in ('blocking','blocking_read','blocking_commits','blocking_missing','blocking_most')} for r in objects(s,'review')]
 assert stripped==objects(plain,'review'),(s,plain)
 if objects(s,'review'):
  beforeline=next(x for x in text.splitlines() if x.startswith('review:'))
  afterline=next(x for x in t.splitlines() if x.startswith('review:'))
  assert afterline.split('; Blocking')[0]==beforeline,(t,text)
 return s,t,cs

def live(mode='approve'):
 global root
 root=live_root
 (st/'reviewer.json').write_text(json.dumps(dict(mode=mode)))
 old=env['PATH'];env['PATH']=str(cb)+os.pathsep+old;p=run(binary,'review','--pr','1');env['PATH']=old
 return p,data(st/'statuses.jsonl')
if case=='v1-113.basic':
 s,t,cs=exercise([row()],[(api(A),{'json':[[status()]]})])
 assert block(s)==(2,1,1,{},[dict(pr=7,blocking=2)]),s
 assert cs==[api(A)],cs
 assert 'review: 1 PR(s) reviewed in 1 round(s), 0 requested changes; 0 needed a second round (0%): none; Blocking 2 in 1 of 1 reviewed commit(s): #7 (2)' in t,t
 assert [r['kind'] for r in map(json.loads,s.splitlines())]==['meta','review','dora','github'],s
elif case=='v1-113.grouping':
 s,t,cs=exercise([row(),row(commit=B),row(result='refused'),row(commit=B,at=999)],[(api(A),{'json':[[status(3)]]}),(api(B),{'json':[[status(4)]]})])
 assert block(s)==(7,2,2,{},[dict(pr=7,blocking=7)]) and review(s)['rounds']==4,s
 assert cs==[api(A),api(B)],cs
elif case=='v1-113.shared':
 s,t,cs=exercise([row(pr=20),row(pr=2),row(pr=20)],[(api(A),{'json':[[status(3)]]})])
 assert block(s)==(6,2,2,{},[dict(pr=2,blocking=3),dict(pr=20,blocking=3)]),s
 assert cs==[api(A)],cs
elif case=='v1-113.invalid-commits':
 vals=['A'*40,'a'*39,'a'*41,'g'*40,' '+A,A+'\n','',None,True,1,[],{}]
 rs=[row(commit=v) for v in vals];missing=row();missing.pop('commit');rs.append(missing)
 s,t,cs=exercise(rs,[])
 assert block(s)==(0,0,13,{'no commit in the run log':13},[]) and cs==[],s
 assert t.rstrip().endswith('missing none') and '; Blocking 0 in 0 of 13 reviewed commit(s): none; not read: no commit in the run log 13' in t,t
elif case=='v1-113.value-grouping':
 missing=row();missing.pop('commit')
 rs=[row(commit=v) for v in (None,None,1,1.0,True,{},[],{'x':1,'y':2},{'y':2,'x':1})]+[missing,missing]
 s,t,cs=exercise(rs,[])
 assert block(s)==(0,0,8,{'no commit in the run log':8},[]) and cs==[],s
elif case=='v1-113.eligibility':
 rs=[row()]+[row(commit=B,**kw) for kw in ({'reused':True},{'result':'error'},{'layer':'pr'},{'layer':'merge'},{'pr':None},{'pr':7.0},{'escape':True})]+[row(commit=C,reused='true',result='refused')]
 s,t,cs=exercise(rs,[(api(A),{'json':[[status(1)]]}),(api(C),{'json':[[status(2)]]})])
 assert block(s)==(3,2,2,{},[dict(pr=7,blocking=3)]) and cs==[api(A),api(C)],s
elif case=='v1-113.since':
 s,t,cs=exercise([row(at=1,commit=B),row(at=2)],[(api(A),{'json':[[status(1)]]}),(api(B),{'json':[[status(4)]]})],('--since','v1.0.0'))
 assert block(s)==(5,2,2,{},[dict(pr=7,blocking=5)]) and cs==[api(B),api(A)],s
elif case=='v1-113.call-order':
 rs=[row(commit=B),row(layer='red',lock='G'),row(layer='merge',lock='G',locks=['G'],pr=97,base='main',default_branch='main'),row()]
 s,t,cs=exercise(rs,[(P,{'exit':4}),(api(A),{'json':[[status(1)]]}),(api(B),{'json':[[status(4)]]})])
 assert block(s)==(5,2,2,{},[dict(pr=7,blocking=5)]) and cs==[P,api(B),api(A)],s
 assert objects(s,'github')[0]==dict(kind='github',selected=1,merge_filled=0,waiting_filled=0,missing={'gh failed':1}),s
elif case=='v1-113.failed-cache':
 rs=[row(),row(pr=8),row(commit=B)]
 s,t,cs=exercise(rs,[(api(A),{'exit':23,'json':[[status(999)]]}),(api(B),{'json':[[status(4)]]})])
 assert block(s)==(4,1,3,{'gh failed':2},[dict(pr=7,blocking=4)]) and cs==[api(A),api(B)],s
 # A new command retries the same failed full argument list exactly once.
 assert data(calls)==[api(A),api(B)],data(calls)
elif case=='v1-113.signal':
 s,t,cs=exercise([row(),row(commit=B)],[(api(A),{'signal':True}),(api(B),{'json':[[status(1)]]})])
 assert block(s)==(1,1,2,{'gh failed':1},[dict(pr=7,blocking=1)]) and cs==[api(A),api(B)],s
elif case=='v1-113.missing-gh':
 (tools/'gh').unlink();(tools/'git').symlink_to(realgit);env['PATH']=str(tools)
 s=report([row(),row(pr=8),row(commit=None)]);t=report(None,('--github',))
 assert block(s)==(0,0,3,{'gh failed':2,'no commit in the run log':1},[]),s
 assert '; not read: gh failed 2, no commit in the run log 1' in t,t
elif case=='v1-113.no-start':
 (tools/'gh').write_text('#!/nonexistent113/interpreter\n')
 s=report([row()]);assert block(s)==(0,0,1,{'gh failed':1},[]),s
elif case=='v1-113.reader':
 raw=json.dumps([[status(6,created_at='0001-01-01T00:00:00Z'),status(8,created_at='9999-12-31T23:59:59Z')]],ensure_ascii=False).replace('"context":','"context": 17, "context":',1).encode()+b'\r\n'
 rs=b'\xef\xbb\xbf'+(json.dumps(row())+'\r\n').encode()
 s,t,cs=exercise(rs,[(api(A),{'raw':raw.hex()})])
 assert block(s)==(8,1,1,{},[dict(pr=7,blocking=8)]),s
elif case=='v1-113.call-order-success':
 write('.shipcraft.toml','shipcraft_min="2.18"\nlang="python"\nrunner="pytest"\ntest_command="echo {junit}"\n[execution]\nci="github"\nreview="off"\n')
 S=['api','--paginate','--slurp',f'repos/{{owner}}/{{repo}}/commits/{B}/status?per_page=100']
 rs=[row(),row(layer='red',lock='G',at=1),row(layer='merge',lock='G',locks=['G'],pr=97,at=2000000000,base='main',default_branch='main')]
 entries=[(P,{'json':dict(number=97,state='MERGED',mergedAt='2026-01-03T00:00:00Z',headRefOid=B,mergeCommit=None)}),(S,{'json':[dict(total_count=1,statuses=[dict(context='shipcraft/ci',state='success',created_at='2026-01-02T00:00:00Z')])]}),(api(A),{'exit':1})]
 s,t,cs=exercise(rs,entries)
 assert objects(s,'github')[0]['waiting_filled']==1 and objects(s,'github')[0]['missing']=={},s
 assert block(s)==(0,0,1,{'gh failed':1},[]) and cs==[P,S,api(A)],s
elif case=='v1-113.malformed-json':
 for raw in (b'\xff',b'[[',b'\xef\xbb\xbf[[]]',b'[[{"context":"other","n":1e400}]]',b'[[]] trailing'):
  s,t,cs=exercise([row()],[(api(A),{'raw':raw.hex()})])
  assert block(s)==(0,0,1,{'unreadable answer from gh':1},[]),s
elif case=='v1-113.shapes':
 for value in ([],{},None,[{}],[None],[[None]],[[3]],[[[]]],[[{}]],[[{'context':None}]],[[{'context':7}]]):
  s,t,cs=exercise([row()],[(api(A),{'json':value})])
  assert block(s)==(0,0,1,{'unreadable answer from gh':1},[]),s
elif case=='v1-113.entries':
 bad=[status(description=3),status(description=False),status(description=[]),status(description={}),status(created_at=None)]
 r=status();r.pop('description');bad.append(r);r=status();r.pop('created_at');bad.append(r)
 for entry in bad:
  s,t,cs=exercise([row()],[(api(A),{'json':[[status(5)],[entry]]})])
  assert block(s)==(0,0,1,{'unreadable answer from gh':1},[]),s
elif case=='v1-113.dates':
 for date in ('2025-02-29T00:00:00Z','2026-01-02T24:00:00Z','2026-01-02T00:60:00Z','2026-01-02T00:00:60Z','0000-01-01T00:00:00Z','2026-01-02T00:00:00+00:00','2026-01-02T00:00:00.1Z','2026-1-02T00:00:00Z',True):
  s,t,cs=exercise([row()],[(api(A),{'json':[[status(5),status(description=None,created_at=date)]]})])
  assert block(s)==(0,0,1,{'unreadable answer from gh':1},[]),s
elif case=='v1-113.grammar-valid':
 for desc,n in (('on this machine: APPROVE, Blocking 0',0),('on this machine: CHANGES REQUESTED, Blocking 007',7),('on this machine: APPROVE, Blocking 999999999 anything',999999999),('on this machine: APPROVE, Blocking 2 \r\n\u2028\u2029 "quoted"',2)):
  s,t,cs=exercise([row(result='refused')],[(api(A),{'json':[[status(description=desc,state=None,created_at='2024-02-29T00:00:00Z')]]})])
  assert block(s)==(n,1,1,{},[] if n==0 else [dict(pr=7,blocking=n)]),s
elif case=='v1-113.grammar-invalid':
 for desc in (None,'review in progress','review error','verdict from sha reused (same file versions)','off in .shipcraft.toml','on this machine: APPROVE, Blocking -1','on this machine: APPROVE, Blocking 1x','on this machine: APPROVE, Blocking 1000000000','on this machine: APPROVE, Blocking 0000000000','on this machine: APPROVE, Blocking ١','on this machine: APPROVE, Blocking 1\t','on this machine: APPROVE, Blocking 1\n','on this machine: APPROVE, Blocking 1\u00a0','on this machine: APPROVE, blocking 1',' on this machine: APPROVE, Blocking 1','on this machine: approve, Blocking 1','on this machine: APPROVE, Blocking '):
  s,t,cs=exercise([row()],[(api(A),{'json':[[status(description=desc)]]})])
  assert block(s)==(0,0,1,{'no blocking count at commit':1},[]),s
elif case=='v1-113.latest':
 s,t,cs=exercise([row()],[(api(A),{'json':[[status(9,created_at='2026-01-01T00:00:00Z')],[],[status(3,created_at='2026-01-03T00:00:00Z'),status(8,created_at='2026-01-02T00:00:00Z')]]})])
 assert block(s)==(3,1,1,{},[dict(pr=7,blocking=3)]),s
elif case=='v1-113.ties':
 s,t,cs=exercise([row()],[(api(A),{'json':[[status(4),status(7)],[status(8)]]})])
 assert block(s)==(4,1,1,{},[dict(pr=7,blocking=4)]),s
elif case=='v1-113.skipped':
 entries=[{'context':'shipcraft/review ','description':17,'created_at':False},{'context':'other'},status(description='review error',created_at='2027-01-01T00:00:00Z'),status(6),status(description=None,created_at='2028-01-01T00:00:00Z')]
 s,t,cs=exercise([row()],[(api(A),{'json':[entries]})])
 assert block(s)==(6,1,1,{},[dict(pr=7,blocking=6)]),s
elif case=='v1-113.no-count':
 for pages in ([[]],[[],[]],[[{'context':'other'}]],[[status(description=None)]]):
  s,t,cs=exercise([row()],[(api(A),{'json':pages})])
  assert block(s)==(0,0,1,{'no blocking count at commit':1},[]),s
elif case=='v1-113.ranking':
 rs=[row(pr=10),row(pr=2),row(pr=9,commit=B),row(pr=9,commit=C),row(pr=1,commit='d'*40)]
 s,t,cs=exercise(rs,[(api(A),{'json':[[status(5)]]}),(api(B),{'json':[[status(4)]]}),(api(C),{'json':[[status(3)]]}),(api('d'*40),{'json':[[status(0)]]})])
 assert block(s)==(17,5,5,{},[dict(pr=9,blocking=7),dict(pr=2,blocking=5),dict(pr=10,blocking=5)]),s
 assert '; Blocking 17 in 5 of 5 reviewed commit(s): #9 (7), #2 (5), #10 (5)' in t and '; not read:' not in t,t
elif case=='v1-113.top5':
 rs=[row(pr=n) for n in (9007199254740993,9007199254740992,20,10,9,3,2)]+[row(pr=100,commit=B)]
 s,t,cs=exercise(rs,[(api(A),{'json':[[status(2)]]}),(api(B),{'json':[[status(9)]]})])
 assert block(s)==(23,8,8,{},[dict(pr=100,blocking=9),dict(pr=2,blocking=2),dict(pr=3,blocking=2),dict(pr=9,blocking=2),dict(pr=10,blocking=2)]),s
elif case=='v1-113.partial':
 rs=[row(),row(commit=B),row(commit=C),row(commit='d'*40),row(commit=None),row(commit='e'*40)]
 s,t,cs=exercise(rs,[(api(A),{'json':[[status(7)]]}),(api(B),{'exit':1}),(api(C),{'json':[]}),(api('d'*40),{'json':[[]]}),(api('e'*40),{'json':[[status(2)]]})])
 assert block(s)==(9,2,6,{'gh failed':1,'unreadable answer from gh':1,'no blocking count at commit':1,'no commit in the run log':1},[dict(pr=7,blocking=9)]),s
 assert '; not read: gh failed 1, no blocking count at commit 1, no commit in the run log 1, unreadable answer from gh 1' in t,t
elif case=='v1-113.zero':
 s,t,cs=exercise([row(),row(pr=9)],[(api(A),{'json':[[status(0)]]})])
 assert block(s)==(0,2,2,{},[]) and '; Blocking 0 in 2 of 2 reviewed commit(s): none' in t and '; not read:' not in t,s
elif case=='v1-113.config-failure':
 write('.shipcraft.toml','[report]\nrelease_tags=""\n')
 s,t,cs=exercise([row()],[(api(A),{'json':[[status(4)]]})])
 assert objects(s,'dora')[0]['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags is empty',s
 assert block(s)==(4,1,1,{},[dict(pr=7,blocking=4)]) and cs==[api(A)],s
elif case=='v1-113.timeout':
 answers([(api(A),{'json':[[status(4)]]}),(api(B),{'sleep':75})]);start=time.time()
 s=report([row(),row(pr=8),row(commit=B),row(commit=C),row(commit=None)])
 assert block(s)==(8,2,5,{'gh timed out':2,'no commit in the run log':1},[dict(pr=7,blocking=4),dict(pr=8,blocking=4)]),s
 assert data(calls)==[api(A),api(B)] and 59<=time.time()-start<75,data(calls)
elif case=='v1-113.timeout-lock':
 answers([(P,{'sleep':75})]);start=time.time()
 s=report([row(layer='red',lock='G'),row(layer='merge',pr=97,lock='G',locks=['G'],base='main',default_branch='main'),row(),row(commit=B),row(commit=None)])
 assert block(s)==(0,0,3,{'gh timed out':2,'no commit in the run log':1},[]) and data(calls)==[P],s
 assert objects(s,'github')[0]['missing']=={'gh timed out':1} and 59<=time.time()-start<75,s
elif case=='v1-113.control-report':
 s,t,cs=exercise([row(),row(result='refused')],[])
 plain=report(None,('--json',));assert review(plain)==dict(kind='review',prs=1,rounds=2,changes_requested=1,second_round=1,second_round_share=1,most=[dict(pr=7,rounds=2)]),plain
 # Plain path is independently proven with the same valid commit fixture.
 calls.unlink(missing_ok=True);report(None,());assert not calls.exists()
 for rs in ([],[row(result='error')],[row(reused=True)],[row(pr=None)]):
  s,t,cs=exercise(rs,[]);assert not objects(s,'review') and cs==[],s
elif case=='v1-113.control-gh':
 answers([(P,{'json':dict(number=97,state='OPEN',mergedAt=None,headRefOid=A,mergeCommit=None)}),(api(A),{'json':[[status(13)]]})])
 p=run(tools/'gh',*api(A));assert p.returncode==0 and json.loads(p.stdout)==[[status(13)]],p
 calls.unlink();s=report([row(layer='merge',pr=97,lock='G',locks=['G'],base='main',default_branch='main')])
 assert objects(s,'github')[0]['missing']=={'pr not merged':1} and data(calls)==[P] and not objects(s,'review'),s
elif case=='v1-113.control-live':
 p,posted=live();assert p.returncode==0,(p.stdout,p.stderr)
 final=[r for r in posted if r['context']=='shipcraft/review'][-1]
 assert final['state']=='success' and final['description']=='on this machine: APPROVE, Blocking 0 (codex)',final
 answers([(api(final['sha']),{'json':[[status(description=final['description'])]]})])
 q=run(tools/'gh',*api(final['sha']));assert json.loads(q.stdout)[0][0]['description']==final['description'],q.stdout
 s=report(None,('--json',));assert review(s)['rounds']==1 and len(data(st/'reviewer.calls.jsonl'))==1,s
elif case=='v1-113.live-count':
 p,posted=live('changes');assert p.returncode!=0,(p.stdout,p.stderr)
 final=[r for r in posted if r['context']=='shipcraft/review'][-1]
 s,t,cs=exercise(None,[(api(final['sha']),{'json':[[status(description=final['description'])]]})])
 assert block(s)==(2,1,1,{},[dict(pr=1,blocking=2)]) and cs==[api(final['sha'])],s
elif case=='v1-113.live-publish':
 p,posted=live();assert p.returncode!=0 and (cb/'publish82-failed').exists(),p
 assert [r['state'] for r in posted if r['context']=='shipcraft/review']==['pending'],posted
 rs=[r for r in data(root/'.git/shipcraft/runs.jsonl') if r['layer']=='review'];assert len(rs)==1 and rs[0]['result']=='passed',rs
 s,t,cs=exercise(None,[(api(rs[0]['commit']),{'json':[[status(description=posted[-1]['description'])]]})])
 assert block(s)==(0,0,1,{'no blocking count at commit':1},[]),s
else:raise AssertionError('unrouted '+case)
if 's' in locals():
 for r in objects(s,'review'):
  if 'blocking' in r:
   assert set(r)=={'kind','prs','rounds','changes_requested','second_round','second_round_share','most','blocking','blocking_read','blocking_commits','blocking_missing','blocking_most'},r
   assert all(type(r[k]) is int for k in ('blocking','blocking_read','blocking_commits')),r
   assert all(type(v) is int for v in r['blocking_missing'].values()),r
   assert all(set(x)=={'pr','blocking'} and type(x['pr']) is int and type(x['blocking']) is int for x in r['blocking_most']),r
PY113
 pass
}
