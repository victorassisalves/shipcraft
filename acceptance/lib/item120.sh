# Item 120: spec bf2a026; public report contract, no implementation reader.
item120_langs() { echo core; }
item120_cases() {
  local c
  for c in week-text control-sample limit-edge-grid number-forms control-fixture control-reader control-github control-no-merged basic merge-choice merge-types pr-integers locks iso-weeks floor-time range-time size-freeze size-invalid rounds round-filters red-selection red-redo nonfinite reader week-ratios week-median week-null bucket-edges bucket-ratios limit-default limit-minimum limit-zero limit-support limit-strict limit-share limit-cumulative limit-largest order since later-failures; do echo "v1-120.$c"; done
}
item120_case() {
  EXPECT="item 120: ${CASE#v1-120.}"
  v1_start codex
  must_accept 'item 120 report contract' cmd "$PY" - "$CASE" "$(command -v shipcraft)" "$CW" <<'PY120'
import json,os,re,shlex,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/"repo120 space 'quote";root.mkdir();realgit=shutil.which('git');env=dict(os.environ)
for k in subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
def run(*args):
 p=subprocess.run(list(map(str,args)),cwd=root,env=env,input=b'',capture_output=True,timeout=120)
 print('COMMAND120',args,p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 return p
def git(*args):
 p=run(realgit,*args);assert p.returncode==0,('fixture git',p.stderr);return p.stdout.decode().strip()
def write(name,data):
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
def snapshot():
 return {str(p.relative_to(root)):(stat.S_IFMT(p.lstat().st_mode),stat.S_IMODE(p.lstat().st_mode),os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None) for p in root.rglob('*')}
def data(p):return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
git('init','-q','-b','main');git('config','gc.auto','0');git('config','maintenance.auto','false')
write('README.md','item120 fixture\n');write('.git/shipcraft/sentinel',b'keep120\x00\r\n')
tools=cw/'tools120';tools.mkdir();calls=cw/'git-calls120';ghcalls=cw/'gh-calls120';proof=cw/'proof120';fault=cw/'git-fault120';ghfault=cw/'gh-fault120'
# Transparent Git probe: public command recording and one injected read failure.
(tools/'git').write_text('#!'+sys.executable+'\n'+"import json,os,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith open("+repr(str(calls))+",'a') as f:f.write(json.dumps(a)+'\\n')\nif Path("+repr(str(fault))+").exists() and 'for-each-ref' in a:raise SystemExit(93)\nos.execv("+repr(realgit)+",["+repr(realgit)+",*a])\n");(tools/'git').chmod(0o755)
# gh 2.x pr-view JSON shape, as item 79; unexpected calls cannot access a service.
(tools/'gh').write_text('#!'+sys.executable+'\n'+"import json,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith open("+repr(str(ghcalls))+",'a') as f:f.write(json.dumps(a)+'\\n')\nif a!=['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']:raise SystemExit(91)\nif Path("+repr(str(ghfault))+").exists():raise SystemExit(92)\nprint(json.dumps(dict(number=97,state='OPEN',mergedAt=None,headRefOid='a'*40,mergeCommit=None)))\n");(tools/'gh').chmod(0o755)
env['PATH']=str(tools)+os.pathsep+env['PATH']
env.update(GIT_AUTHOR_DATE='1700000000 +0000',GIT_COMMITTER_DATE='1700000000 +0000')
git('add','README.md');git('commit','-qm','fixture120');git('tag','v1.0.0');base=git('rev-parse','HEAD')
env.update(GIT_AUTHOR_DATE='1700086400 +0000',GIT_COMMITTER_DATE='1700086400 +0000')
write('README.md','second release120\n');git('add','README.md');git('commit','-qm','release120');git('tag','v2.0.0')
log=root/'.git/shipcraft/runs.jsonl'
def row(**kw):
 r=dict(layer='review',result='passed',pr=7,commit='foreign120',at=100,secs=45,lock='',locks=[],branch='topic120',code='')
 r.update(kw);return r
def wire(rs):return ''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in rs).encode()
def report(rs,args=('--json',)):
 if rs is not None:write('.git/shipcraft/runs.jsonl',rs if isinstance(rs,bytes) else wire(rs))
 before=snapshot();p=run(binary,'report',*args)
 assert p.returncode==0 and not p.stderr,(p.returncode,p.stdout,p.stderr)
 assert snapshot()==before,'report wrote repository state'
 return p.stdout.decode()
def objects(s,kind):return [r for r in (json.loads(x) for x in s.split('\n') if x) if r['kind']==kind]
def reviews(s):return objects(s,'review')
def lines(s):return [x for x in s.split('\n') if x.startswith('review:')]
def merge(pr=7,**kw):
 r=dict(layer='merge',pr=pr,base='main',default_branch='main');r.update(kw);return row(**r)
def measured(pr=7,size=20,**kw):return row(layer='pr',pr=pr,product_lines=size,warn_lines=500,**kw)
def sample(sizes,verdicts=None):
 rs=[]
 for i,size in enumerate(sizes,1):
  rs.extend([measured(i,size),merge(i)])
  for verdict in (['passed'] if verdicts is None else verdicts[i-1]):rs.append(row(pr=i,result=verdict))
 return rs
def pair(rs,args=()):return report(rs,('--json',*args)),report(rs,args)
def prs(s):return objects(s,'merged_pr')
def weeks(s):return objects(s,'week')
def buckets(s):return objects(s,'size_bucket')
def limits(s):return objects(s,'limit')
def selected(s):return [r for r in map(json.loads,s.split('\n')[:-1]) if r['kind'] in ('merged_pr','week','size_bucket','limit')]
def textlines(t,prefix):return [l for l in t.split('\n') if l.startswith(prefix)]
# Every oracle belongs to its exact case arm, including the controls.
if case=='v1-120.control-fixture':
 rs=[row(layer='red',lock='fixture120',at=17),row(layer='close',lock='fixture120',at=29),merge(pr=None,lock='fixture120',at=47)]
 s,t=pair(rs)
 assert objects(s,'lock')[0]['red_to_merge']==30 and '30 s' in t and objects(s,'dora')[0]['git']['releases']==2,s
 fault.touch();s,t=pair(rs)
 assert objects(s,'dora')[0]['git']['reason'].endswith('exited 93') and objects(s,'lock')[0]['red_to_merge']==30,s
 write('.shipcraft.toml','[report]\nrelease_tags=""\n');fault.unlink();s,t=pair(rs)
 assert objects(s,'dora')[0]['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags is empty',s
 assert not selected(s) and not ghcalls.exists()
elif case=='v1-120.control-reader':
 raw=b'\xef\xbb\xbf'+wire([row(pr=8,reason='space " \u2028\u2029')]).replace(b'\n',b'\r\n')+b' \t\r\n'
 raw+=wire([row(pr=8,result='refused',reason='BAD120')]).replace(b'BAD120',b'\xff')[:-1]+b'\r\n{bad\n'
 s,t=pair(raw)
 assert objects(s,'review')==[dict(kind='review',prs=1,rounds=2,changes_requested=1,second_round=1,second_round_share=1,most=[dict(pr=8,rounds=2)])],s
 assert [r['line'] for r in objects(s,'gap')]==[4] and not selected(s),s
 assert 'review: 1 PR(s) reviewed in 2 round(s)' in t,t
elif case=='v1-120.control-github':
 rs=[row(layer='red',lock='G',at=1),row(layer='close',lock='G',at=2),merge(pr=97,lock='G',at=100)]
 s,t=pair(rs,('--github',))
 assert objects(s,'github')[0]['missing']=={'pr not merged':1},s
 assert data(ghcalls)==[['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']]*2
 ghfault.touch();s,t=pair(rs,('--github',))
 assert objects(s,'github')[0]['missing']=={'gh failed':1} and 'gh failed' in t,s
 write('.shipcraft.toml','shipcraft_min="2.18"\nlang="python"\nrunner="pytest"\ntest_command="echo {junit}"\n[execution]\nci="github"\nreview="off"\nsuite_checks=["fixture120"]\n')
 s,t=pair(rs+[row(pr=97)],('--github',))
 assert objects(s,'checks')==[dict(kind='checks',prs=1,prs_read=0,missing={'gh failed':1},names=[dict(name='fixture120',runs=0,red=0,green_again=0,new_commit=0,still_red=0)])],s
 assert ['api','--paginate','--slurp','repos/{owner}/{repo}/pulls/97/commits?per_page=100'] in data(ghcalls) and 'checks: 0 of 1 reviewed PR(s) read;' in t,t
elif case=='v1-120.control-no-merged':
 # Identical bytes for the legacy paths, despite ineligible PR references.
 rs=[row(layer='red',lock='A',at=1),row(layer='close',lock='A',at=2),merge(pr=None,lock='A',at=10),measured(),row()]
 s,t=pair(rs)
 import hashlib
 assert [hashlib.sha256(x.encode()).hexdigest() for x in (s,t)]==['3f0e6cd2b436012e978f8955d54a4a5e612f893dbed086c0f36e90b851ddff30', 'c2c275dd3ec8284406d53d7fb8b877ccdd2a9878646cdbf5bc0596a4451362e7'],(s,t)
 other=[dict(r,pr='7') if r['layer']=='merge' else r for r in rs]
 assert pair(other)==(s,t) and not selected(s),(s,t)
 assert [r['kind'] for r in map(json.loads,s.splitlines())]==['meta','lock','day','size','review','dora'],s
 assert textlines(t,'size:')==['size: 1 PR(s) measured, 0 above their limit (0%); merged 0, 0 above (-)'],t
 empty=pair([]);log.unlink();assert pair(None)==empty
 log.mkdir();assert pair(None)==empty;log.rmdir()
elif case=='v1-120.basic':
 rs=[row(layer='red',lock='8c042eb7c328',at=1794963289),measured(140,1429),row(pr=140),merge(140,at=1794963902,lock='8c042eb7c328')]
 calls.unlink(missing_ok=True);s,t=pair(rs);observed=data(calls);calls.unlink()
 pair([dict(r,pr=None) if r['layer']=='merge' else r for r in rs])
 assert data(calls)==observed and not ghcalls.exists(),'extra Git/network call'
 assert prs(s)==[dict(kind='merged_pr',pr=140,locks=['8c042eb7c328'],merge_at=1794963902,week='2026-W47',product_lines=1429,rounds=1,changes_requested=0,first_round_approved=True,red_to_merge=613,markers=None)],s
 assert textlines(t,'pr #')==['pr #140: merged at 2026-11-18T01:05:02Z (2026-W47); locks 8c042eb7c328; 1429 product lines; 1 review round(s), 0 requested changes, approved on round 1 yes; red to merge 10 min 13 s'],t
elif case=='v1-120.merge-choice':
 rs=[merge(result='refused',at=3),merge(base='other',at=4),merge(escape=True,at=5),merge(at=200,lock='first'),merge(at=10,lock='later'),merge(2,at=90),merge(10,at=80)]
 s,t=pair(rs)
 assert [(r['pr'],r['merge_at'],r['locks']) for r in prs(s)]==[(2,90,[]),(7,200,['first']),(10,80,[])],s
 assert [l.split(':')[0] for l in textlines(t,'pr #')]==['pr #2','pr #7','pr #10'],t
elif case=='v1-120.merge-types':
 rs=[merge(19)]+[merge(20+i,**kw) for i,kw in enumerate([dict(result='error'),dict(result='Passed'),dict(base=None,default_branch=None),dict(base=1,default_branch=1),dict(base=[],default_branch=[]),dict(layer='pr'),dict(escape=True)])]
 rs += [merge(pr=v) for v in (0,-1,7.0,'7',True,None,[],{})]
 raw=wire(rs)+wire([merge(pr='TOKEN')]).replace(b'"TOKEN"',b'7e0')+wire([merge(pr='TOKEN')]).replace(b'"TOKEN"',b'18446744073709551616')
 s,t=pair(raw)
 assert [r['pr'] for r in prs(s)]==[19] and not objects(s,'gap'),s
 assert len(textlines(t,'pr #'))==1,t
elif case=='v1-120.pr-integers':
 s,t=pair([merge(n) for n in (18446744073709551615,9007199254740993,2,9007199254740992,18446744073709551615)])
 assert [r['pr'] for r in prs(s)]==[2,9007199254740992,9007199254740993,18446744073709551615],s
 assert 'pr #18446744073709551615:' in t,t
elif case=='v1-120.locks':
 rs=[measured(7,locks=['wrong']),merge(lock='A',locks=['B','A','',None,False,9,'B','space " \u2028\u2029']),merge(8,lock=12,locks='wrong')]
 s,t=pair(rs)
 assert [r['locks'] for r in prs(s)]==[['A','B','space " \u2028\u2029'],[]],s
 assert '; locks A, B, space " \u2028\u2029;' in t and 'pr #8:' in t and '; locks none;' in t,t
elif case=='v1-120.iso-weeks':
 import datetime
 days=['2027-01-01','2024-12-30','2026-11-18','2021-01-03','2021-01-04']
 rs=[merge(i+1,at=int(datetime.datetime.fromisoformat(d).replace(tzinfo=datetime.timezone.utc).timestamp())) for i,d in enumerate(days)]
 s,t=pair(rs)
 assert [r['week'] for r in prs(s)]==['2026-W53','2025-W01','2026-W47','2020-W53','2021-W01'],s
 assert [r['week'] for r in weeks(s)]==['2020-W53','2021-W01','2025-W01','2026-W47','2026-W53'],s
 assert '(2026-W53)' in t and '(2025-W01)' in t,t
elif case=='v1-120.floor-time':
 s,t=pair([merge(1,at=345599.99),merge(2,at=345600),merge(3,at=-.01),merge(4,at=0)])
 assert [(r['merge_at'],r['week']) for r in prs(s)]==[(345599.99,'1970-W01'),(345600,'1970-W02'),(-.01,None),(0,'1970-W01')],s
 assert '1970-01-04T23:59:59Z (1970-W01)' in t and '1970-01-05T00:00:00Z (1970-W02)' in t,t
elif case=='v1-120.range-time':
 rs=[measured(i,10) for i in range(1,7)]+[merge(i,at=a) for i,a in enumerate([253402300799.9,253402300800,-1,'100',True,None],1)]
 s,t=pair(rs)
 assert [r['week'] for r in prs(s)]==['9999-W52',None,None,None,None,None],s
 assert [r['merge_at'] for r in prs(s)]==[253402300799.9,253402300800,-1,None,None,None],s
 assert len(weeks(s))==1 and buckets(s)[0]['merged_prs']==6 and not objects(s,'gap'),s
 assert 'pr #4: merged at - (-)' in t,t
elif case=='v1-120.size-freeze':
 rs=[measured(size=100,at=900),merge(result='refused'),measured(size=101,at=1,result='error'),merge(at=20),measured(size=999),merge(at=30),merge(8),measured(8,200),measured(9,0,result='refused'),merge(9)]
 s,t=pair(rs)
 assert [(r['pr'],r['product_lines']) for r in prs(s)]==[(7,101),(8,None),(9,0)],s
 assert '; 101 product lines;' in t and '; - product lines;' in t and '; 0 product lines;' in t,t
elif case=='v1-120.size-invalid':
 rs=[measured(size=42)]
 for val in (None,True,-1,1.0,'2',[],{}):rs += [measured(size=val),dict(measured(size=99),warn_lines=val)]
 rs += [dict(layer='pr',pr=7,product_lines=777),measured(size=777,escape=True),merge(),dict(layer='pr',pr=8,product_lines=10),merge(8)]
 raw=wire(rs[:-3])
 for key in ('product_lines','warn_lines'):
  for token in ('1e0','-0','18446744073709551616'):
   raw+=wire([dict(measured(size=88),**{key:'TOKEN'})]).replace(b'"TOKEN"',token.encode())
 raw+=wire(rs[-3:]);s,t=pair(raw)
 assert [r['product_lines'] for r in prs(s)]==[42,None] and not objects(s,'gap'),s
 assert '; 42 product lines;' in t and '; - product lines;' in t,t
elif case=='v1-120.rounds':
 rs=[row(pr=7,result='refused',at=999,locks=['A','B']),merge(lock='A',locks=['B']),row(pr=7,at=0,locks=['A','B']),row(pr=7,result='refused'),merge(8),row(pr=8),merge(9)]
 s,t=pair(rs)
 assert [(r['rounds'],r['changes_requested'],r['first_round_approved']) for r in prs(s)]==[(3,2,False),(1,0,True),(0,0,None)],s
 assert '3 review round(s), 2 requested changes, approved on round 1 no' in t and 'approved on round 1 -' in t,t
elif case=='v1-120.round-filters':
 rs=[merge(),row(result='error'),row(result='refused',reused=True),row(result='refused',escape=True),row(pr='7',result='refused'),row(layer='ci',result='refused'),row(result='PASSED')]
 rs += [row(reused=v) for v in (False,None,0,'true',[],{})]+[row(result='refused',reused='true')]
 s,t=pair(rs)
 assert [(r['rounds'],r['changes_requested'],r['first_round_approved']) for r in prs(s)]==[(7,1,True)],s
 assert '7 review round(s), 1 requested changes, approved on round 1 yes' in t,t
elif case=='v1-120.red-selection':
 rs=[row(layer='red',lock='A',at=80),row(layer='red',lock='B',at=20),row(layer='red',lock='A',at=30),row(layer='red',lock='outside',at=1),merge(at=100,lock='A',locks=['B']),merge(8,at=10,lock='A')]
 s,t=pair(rs)
 assert [r['red_to_merge'] for r in prs(s)]==[80,-20],s
 assert 'red to merge 1 min 20 s' in t and 'red to merge -20 s' in t,t
elif case=='v1-120.red-redo':
 rs=[row(layer='red',lock='A',at=1,redo=True),row(layer='red',lock='A',at=2,result='refused'),row(layer='red',lock='A',at=3,escape=True),row(layer='red',lock='A',at='4'),row(layer='red',locks=['A'],at=10,redo='true'),row(layer='red',lock='A',at=20,redo=False),merge(at=40,lock='A'),merge(8,at=50,lock='missing')]
 s,t=pair(rs)
 assert [r['red_to_merge'] for r in prs(s)]==[30,None],s
 assert 'red to merge 30 s' in t and 'red to merge -' in t,t
elif case=='v1-120.nonfinite':
 rs=[row(layer='red',lock='A',at=-1e308),merge(at=1e308,lock='A'),row(layer='red',lock='B',at=1e308),merge(8,at=-1e308,lock='B'),merge(9,at=9000000000000000)]
 s,t=pair(rs)
 assert [r['red_to_merge'] for r in prs(s)]==[None,None,None] and not objects(s,'gap'),s
 assert prs(s)[0]['merge_at']==1e308 and type(prs(s)[2]['merge_at']) is float,s
 assert len(textlines(t,'pr #'))==3,t
elif case=='v1-120.reader':
 raw=b'\xef\xbb\xbf'+wire([merge(7,reason='quote " \u2028\u2029')]).replace(b'\n',b'\r\n')+b' \r\n'
 raw+=wire([merge(8,reason='BAD120')]).replace(b'BAD120',b'\xff')
 raw+=b'{bad\n[]\nnull\n'+wire([merge(pr='TOKEN')]).replace(b'"TOKEN"',b'1e400')
 raw+=wire([merge(9)]).replace(b'"pr": 9',b'"pr": 18, "pr": 9')[:-1]+b'\r'
 s,t=pair(raw)
 assert [r['line'] for r in objects(s,'gap')]==[4,5,6,7],s
 assert [r['pr'] for r in prs(s)]==[7,8,9],s
 assert len(textlines(t,'pr #'))==3,t
elif case=='v1-120.week-ratios':
 rs=[merge(i) for i in range(1,5)]+[row(pr=1),row(pr=2,result='refused'),row(pr=2),row(pr=2,result='refused'),row(pr=3,result='refused'),row(pr=3,result='refused'),row(pr=3)]
 s,t=pair(rs)
 assert weeks(s)==[dict(kind='week',week='1970-W01',merged_prs=4,red_to_merge_median=None,reviewed_prs=3,round1_approved_share=1/3,changes_requested_per_pr=4/3,three_rounds=2,three_rounds_share=2/3)],s
 assert textlines(t,'week ')==['week 1970-W01: 4 merged PR(s), median red to merge -; 3 reviewed, approved on round 1 33%, 1.33 change requests per PR, 3 or more rounds 2 (67%)'],t
elif case=='v1-120.week-median':
 rs=[row(layer='red',lock=str(i),at=100-d) for i,d in enumerate([-20,10,30,100],1)]+[merge(i,lock=str(i)) for i in range(1,6)]
 s,t=pair(rs)
 assert len(weeks(s))==1 and weeks(s)[0]['red_to_merge_median']==20 and weeks(s)[0]['merged_prs']==5,s
 assert 'median red to merge 20 s;' in t,t
 rs += [row(layer='red',lock='5',at=60)];s,t=pair(rs)
 assert weeks(s)[0]['red_to_merge_median']==30 and 'median red to merge 30 s;' in t,s
elif case=='v1-120.week-null':
 s,t=pair([merge(),merge(8,at=None),merge(9,at=-1)])
 assert weeks(s)==[dict(kind='week',week='1970-W01',merged_prs=1,red_to_merge_median=None,reviewed_prs=0,round1_approved_share=None,changes_requested_per_pr=None,three_rounds=0,three_rounds_share=None)],s
 assert textlines(t,'week ')==['week 1970-W01: 1 merged PR(s), median red to merge -; 0 reviewed, approved on round 1 -, - change requests per PR, 3 or more rounds 0 (-)'],t
 assert not buckets(s) and not limits(s),s
elif case=='v1-120.bucket-edges':
 s,t=pair(sample([0,100,101,200,201,300,301,400,401,600,601,800,801,1200,1201,9999],[[]]*16))
 assert [(r['from'],r['to'],r['merged_prs'],r['reviewed_prs'],r['round1_approved_share'],r['changes_requested_per_pr']) for r in buckets(s)]==[(a,b,2,0,None,None) for a,b in [(0,100),(100,200),(200,300),(300,400),(400,600),(600,800),(800,1200),(1200,None)]],s
 assert textlines(t,'size ')==[f'size {label}: 2 merged PR(s), 0 reviewed, approved on round 1 -, - change requests per PR' for label in ['0-100','100-200','200-300','300-400','400-600','600-800','800-1200','1200+']],t
elif case=='v1-120.bucket-ratios':
 s,t=pair(sample([0,100,100,101],[['passed'],['refused','passed'],[],['refused','refused','passed']]))
 assert len(buckets(s))==8 and [(r['merged_prs'],r['reviewed_prs'],r['round1_approved_share'],r['changes_requested_per_pr']) for r in buckets(s)[:2]]==[(3,2,.5,.5),(1,1,0,2)],s
 assert textlines(t,'size ')[:2]==['size 0-100: 3 merged PR(s), 2 reviewed, approved on round 1 50%, 0.50 change requests per PR','size 100-200: 1 merged PR(s), 1 reviewed, approved on round 1 0%, 2.00 change requests per PR'],t
 assert all(r['merged_prs']==0 and r['round1_approved_share'] is None for r in buckets(s)[2:]),s
elif case=='v1-120.limit-default':
 s,t=pair(sample([20]*29)+[measured(99,20),merge(99),measured(100,20),row(pr=100),merge(101),row(pr=101)])
 assert limits(s)==[dict(kind='limit',sample=29,minimum=30,default=600,limit=600,basis='default')],s
 assert textlines(t,'suggested limit:')==['suggested limit: 600 product lines (the default): 29 reviewed merged PR(s), no supported edge (30 or more PRs up to it, one in its interval)'],t
elif case=='v1-120.limit-minimum':
 s,t=pair(sample([2000]*29+[50]))
 assert limits(s)==[dict(kind='limit',sample=30,minimum=30,default=600,limit=600,basis='default')],s
 assert '600 product lines (the default): 30 reviewed merged PR(s)' in t,t
elif case=='v1-120.limit-zero':
 s,t=pair(sample([0]*30))
 assert limits(s)==[dict(kind='limit',sample=30,minimum=30,default=600,limit=100,basis='data')],s
 assert buckets(s)[0]['merged_prs']==30 and 'suggested limit: 100 product lines, from 30 reviewed merged PR(s):' in t,t
elif case=='v1-120.limit-support':
 s,t=pair(sample([20]*30))
 assert limits(s)==[dict(kind='limit',sample=30,minimum=30,default=600,limit=100,basis='data')],s
 assert textlines(t,'suggested limit:')==['suggested limit: 100 product lines, from 30 reviewed merged PR(s): the largest supported edge (30 or more PRs up to it, one in its interval) whose PRs up to it average under 1 change request each with at least 50% approved on round 1'],t
elif case=='v1-120.limit-strict':
 s,t=pair(sample([600]*30,[['passed','refused']]*30))
 assert limits(s)==[dict(kind='limit',sample=30,minimum=30,default=600,limit=None,basis='none')],s
 assert textlines(t,'suggested limit:')==['suggested limit: none: at no supported edge (30 or more PRs up to it, one in its interval) do the PRs up to it average under 1 change request each with at least 50% approved on round 1 (30 reviewed merged PR(s))'],t
elif case=='v1-120.limit-share':
 s,t=pair(sample([500]*30,[['passed']]*15+[['refused','passed']]*15))
 assert limits(s)==[dict(kind='limit',sample=30,minimum=30,default=600,limit=500,basis='data')],s
 assert 'suggested limit: 500 product lines, from 30 reviewed merged PR(s):' in t,t
 s,t=pair(sample([500]*30,[['passed']]*14+[['refused','passed']]*16))
 assert limits(s)==[dict(kind='limit',sample=30,minimum=30,default=600,limit=None,basis='none')],s
 assert 'suggested limit: none:' in t,t
elif case=='v1-120.limit-cumulative':
 s,t=pair(sample([20]*30+[1400],[['passed']]*30+[['refused']*10+['passed']]))
 assert limits(s)==[dict(kind='limit',sample=31,minimum=30,default=600,limit=1500,basis='data')],s
 assert buckets(s)[7]['changes_requested_per_pr']==10 and 'suggested limit: 1500 product lines, from 31 reviewed merged PR(s):' in t,t
elif case=='v1-120.limit-largest':
 s,t=pair(sample([100]*30+[200,300,400,500,600,800,1000,1500,1501]))
 assert limits(s)==[dict(kind='limit',sample=39,minimum=30,default=600,limit=1500,basis='data')],s
 assert 'suggested limit: 1500 product lines, from 39 reviewed merged PR(s):' in t,t
 # Largest qualifying edge can precede a supported but nonqualifying edge.
 s,t=pair(sample([1000]*30+[1500],[['passed']]*30+[['refused']*31]))
 assert limits(s)==[dict(kind='limit',sample=31,minimum=30,default=600,limit=1000,basis='data')],s
 assert 'suggested limit: 1000 product lines,' in t,t
elif case=='v1-120.order':
 write('.shipcraft.toml','shipcraft_min="2.18"\nlang="python"\nrunner="pytest"\ntest_command="echo {junit}"\n[execution]\nci="github"\nreview="off"\nsuite_checks=["fixture120"]\n')
 rs=[row(layer='red',lock='A',at=1),row(layer='close',lock='A',at=2),measured(97,100),row(pr=97),row(layer='ci',result='refused',code='suite-red'),merge(97,lock='A')]
 s,t=pair(wire(rs)+b'{bad\n',('--github',))
 kinds=[r['kind'] for r in map(json.loads,s.splitlines())]
 assert kinds==['meta','lock','day','size','reds','reds_week','review','checks','merged_pr','week']+['size_bucket']*8+['limit','dora','github','gap'],s
 ls=t.split('\n');i=next(i for i,l in enumerate(ls) if l.startswith('pr #97:'))
 assert ls[i-1].startswith('checks:') and ls[i+1].startswith('week ') and all(l.startswith('size ') for l in ls[i+2:i+10]) and ls[i+10].startswith('suggested limit:') and ls[i+11]=='DORA',t
elif case=='v1-120.since':
 rs=sample([20]*30);s,t=pair(rs,('--since','v2.0.0'))
 assert objects(s,'dora')[0]['deploys']['n']==1,s
 assert selected(s)==selected(report(rs)),s
 assert limits(s)==[dict(kind='limit',sample=30,minimum=30,default=600,limit=100,basis='data')],s
 for prefix in ('pr #','week ','size ','suggested limit:'):assert textlines(t,prefix)==textlines(report(rs,()),prefix),t
elif case=='v1-120.later-failures':
 rs=[row(layer='red',lock='G',at=1),row(layer='close',lock='G',at=2),measured(97,20),merge(97,lock='G')]
 plain,pt=pair(rs);ghfault.touch();s,t=pair(rs,('--github',))
 assert objects(s,'github')[0]['missing']=={'gh failed':1},s
 assert selected(s)==selected(plain) and len(prs(s))==1 and len(weeks(s))==1 and len(buckets(s))==8 and len(limits(s))==1,s
 for prefix in ('pr #','week ','size ','suggested limit:'):assert textlines(t,prefix)==textlines(pt,prefix),t
 fault.touch();s,t=pair(rs)
 assert objects(s,'dora')[0]['git']['reason'].endswith('exited 93') and selected(s)==selected(plain),s
 write('.shipcraft.toml','[report]\nrelease_tags=""\n');fault.unlink();s,t=pair(rs)
 assert objects(s,'dora')[0]['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags is empty' and selected(s)==selected(plain),s
 for prefix in ('pr #','week ','size ','suggested limit:'):assert textlines(t,prefix)==textlines(pt,prefix),t
elif case=='v1-120.control-sample':
 s,t=pair(sample([20,800],[['passed'],['refused','passed']]))
 assert objects(s,'size')==[dict(kind='size',prs=2,above=1,above_share=.5,merged_prs=2,merged_above=1,merged_above_share=.5)],s
 assert objects(s,'review')==[dict(kind='review',prs=2,rounds=3,changes_requested=1,second_round=1,second_round_share=.5,most=[dict(pr=2,rounds=2)])],s
 assert textlines(t,'size:')==['size: 2 PR(s) measured, 1 above their limit (50%); merged 2, 1 above (50%)'],t
elif case=='v1-120.limit-edge-grid':
 for edge in (100,200,300,400,500,600,800,1000,1500):
  s,t=pair(sample([edge]*30))
  assert limits(s)==[dict(kind='limit',sample=30,minimum=30,default=600,limit=edge,basis='data')],s
  assert f'suggested limit: {edge} product lines, from 30 reviewed merged PR(s):' in t,t
 s,t=pair(sample([1501]*30))
 assert limits(s)==[dict(kind='limit',sample=30,minimum=30,default=600,limit=600,basis='default')],s
 assert '600 product lines (the default):' in t,t
elif case=='v1-120.week-text':
 rs=[merge(i) for i in (1,2,3)]+[row(pr=1),row(pr=2,result='refused'),row(pr=2,result='refused'),row(pr=3,result='refused'),row(pr=3,result='refused'),row(pr=3,result='refused')]
 s,t=pair(rs)
 assert len(weeks(s))==1 and weeks(s)[0]['changes_requested_per_pr']==5/3,s
 assert textlines(t,'week ')==['week 1970-W01: 3 merged PR(s), median red to merge -; 3 reviewed, approved on round 1 33%, 1.67 change requests per PR, 3 or more rounds 1 (33%)'],t
 s,t=pair([merge(),row()])
 assert weeks(s)==[dict(kind='week',week='1970-W01',merged_prs=1,red_to_merge_median=None,reviewed_prs=1,round1_approved_share=1,changes_requested_per_pr=0,three_rounds=0,three_rounds_share=0)],s
 assert all(type(weeks(s)[0][k]) is int for k in ('round1_approved_share','changes_requested_per_pr','three_rounds_share')),s
 assert textlines(t,'week ')==['week 1970-W01: 1 merged PR(s), median red to merge -; 1 reviewed, approved on round 1 100%, 0.00 change requests per PR, 3 or more rounds 0 (0%)'],t
elif case=='v1-120.number-forms':
 rs=[row(layer='red',lock='A',at=1.25),merge(1,at=2.875,lock='A'),merge(2,at=100.0),merge(3,at=8999999999999999),measured(4,18446744073709551615),merge(4)]
 s,t=pair(rs)
 assert len(prs(s))==4 and prs(s)[0]['red_to_merge']==1.625 and type(prs(s)[0]['merge_at']) is float,s
 assert type(prs(s)[1]['merge_at']) is int and type(prs(s)[2]['merge_at']) is int,s
 assert prs(s)[3]['product_lines']==18446744073709551615,s
 assert 'red to merge 2 s' in t and '; 18446744073709551615 product lines;' in t,t
else:raise AssertionError('unrouted '+case)
# Schemas only; each case above owns its numeric and text expectations.
for r in selected(s):
 if r['kind']=='merged_pr':
  assert set(r)=={'kind','pr','locks','merge_at','week','product_lines','rounds','changes_requested','first_round_approved','red_to_merge','markers'},r
  assert all(type(r[k]) is int for k in ('pr','rounds','changes_requested')),r
  assert r['product_lines'] is None or type(r['product_lines']) is int,r
  assert r['first_round_approved'] is None or type(r['first_round_approved']) is bool,r
 elif r['kind']=='week':
  assert set(r)=={'kind','week','merged_prs','red_to_merge_median','reviewed_prs','round1_approved_share','changes_requested_per_pr','three_rounds','three_rounds_share'},r
  assert all(type(r[k]) is int for k in ('merged_prs','reviewed_prs','three_rounds')),r
 elif r['kind']=='size_bucket':
  assert set(r)=={'kind','from','to','merged_prs','reviewed_prs','round1_approved_share','changes_requested_per_pr'},r
  assert all(type(r[k]) is int for k in ('from','merged_prs','reviewed_prs')),r
 elif r['kind']=='limit':
  assert set(r)=={'kind','sample','minimum','default','limit','basis'},r
  assert all(type(r[k]) is int for k in ('sample','minimum','default')),r
PY120
  pass
}
