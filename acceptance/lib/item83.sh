# Item 83: frozen run logs, real release history, offline gh; no product sources.
item83_langs() { echo core; }
item83_cases() {
  local c
  for c in times fractional-times negative-epoch duration-zero duration-seconds duration-minute duration-below-hour duration-hour duration-mixed duration-over-day duration-round-up duration-round-down duration-negative duration-negative-zero latency-whole latency-fraction share-rounded share-zero share-full dora-times dora-durations dora-duration-boundary dora-shares dora-share-zero dora-share-full rate-small rate-whole github-values github-late-failure empty-control json-local json-release json-github json-metrics json-fraction; do echo "v1-83.$c"; done
}
item83_case() {
  EXPECT="item 83: ${CASE#v1-83.}"
  v1_start codex
  must_accept 'human report values' cmd "$PY" - "$CASE" "$(command -v shipcraft)" "$CW" <<'PY83'
import datetime,hashlib,json,os,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/'report83 space';root.mkdir();realgit=shutil.which('git');env=dict(os.environ,TZ='Pacific/Honolulu')
for k in subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
def git(*args,at=1700000000,data=None):
 e=dict(env,GIT_AUTHOR_DATE=f'{at} +0000',GIT_COMMITTER_DATE=f'{at} +0000')
 p=subprocess.run([realgit,*map(str,args)],cwd=root,env=e,input=data,capture_output=True,timeout=20)
 assert p.returncode==0,('fixture git',args,p.stderr)
 return p.stdout.decode().strip()
def write(name,data):
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(data)
def save(at):
 git('add','-A');tree=git('write-tree')
 parents=['-p',git('rev-parse','HEAD')] if (root/'.git/refs/heads/main').exists() else []
 sha=git('commit-tree',tree,*parents,at=at,data=b'fixture83\n');git('update-ref','HEAD',sha);return sha
def lock(id,kind='feature',reported=None,fixes=None):
 d=dict(format=4,state='closed',files={'tests/test_value.py':'sha256:'+hashlib.sha256(b'def test_value(): assert False\n').hexdigest()},cases=['tests/test_value.py::test_value'],failing_at_red=['tests/test_value.py::test_value'],kind=kind,reported_at=reported,fixes_release=fixes,seal='')
 d['seal']=hashlib.sha256(json.dumps(d,separators=(',',':')).encode()).hexdigest()
 write(Path('.shipcraft/locks')/(id+'.json'),json.dumps(d)+'\n')
def row(layer,at,id='A',**kw):
 d=dict(layer=layer,at=at,lock=id,result='passed',secs=1,branch='feature/83',commit='a'*40,code='',reason='')
 if layer in ('merge','ci','pr','review'):d.update(locks=[id],base='main',default_branch='main')
 d.update(kw);return d
def cycle(red=100,close=140,merge=200,id='A',ci=None):
 rs=[row('red',red,id),row('close',close,id),row('merge',merge,id)]
 if ci is not None:rs.append(row('ci',ci,id))
 return rs
def snapshot():
 return {str(p.relative_to(root)):(stat.S_IMODE(p.lstat().st_mode),os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None) for p in root.rglob('*')}
def report(rs,args=()):
 # Always replace hook history after the last fixture commit, per item 38.
 write(Path('.git/shipcraft/runs.jsonl'),''.join(json.dumps(r)+'\n' for r in rs))
 before=snapshot()
 p=subprocess.run([binary,'report',*args],cwd=root,env=env,capture_output=True,timeout=20)
 print(p.stdout.decode(),flush=True);print(p.stderr.decode(),file=sys.stderr,flush=True)
 assert p.returncode==0 and p.stderr==b'',(p.returncode,p.stderr)
 assert snapshot()==before,'report wrote repository state or appended a run row'
 return p.stdout.decode()
def local(rs=None,args=()):
 return report(cycle() if rs is None else rs,args)
def releases(spacing=86400,lead=(100,200,400,800),recovery=(60,180),kinds=('feature','fix','feature','fix'),links=('v1.0.0','v1.1.0'),args=()):
 T=1700000000
 lock('A',kinds[0]);save(T-1000);git('tag','-a','v1.0.0','-m','release83',at=T)
 lock('B',kinds[1],utc(T+spacing-recovery[0]) if kinds[1]=='fix' else None,links[0] if kinds[1]=='fix' else None);lock('C',kinds[2]);save(T+spacing);git('tag','v1.1.0')
 (root/'.shipcraft/locks/A.json').unlink()
 lock('D',kinds[3],utc(T+3*spacing-recovery[1]) if kinds[3]=='fix' else None,links[1] if kinds[3]=='fix' else None)
 save(T+3*spacing-1000);git('tag','-a','v2.0.0','-m','release83',at=T+3*spacing)
 rs=[row('red',T+3*spacing-lead[3],'D'),row('red',T-lead[0],'A'),row('red',T+spacing-lead[1],'B'),row('red',T+spacing-lead[2],'C'),row('merge',T+1,'A')]
 return report(rs,args)
def utc(t):return datetime.datetime.fromtimestamp(t,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
def github(args=('--github',),fail=False):
 T=1700000000;lock('A');tip=save(T);git('tag','v1.0.0')
 rs=[row('red',T),row('close',T+60),row('pr',T+200,pr=97,result='error')]
 # Same gh 2.x JSON shapes as item 79's captured PR #97 and slurped API pages.
 P=['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']
 S=['api','--paginate','--slurp',f'repos/{{owner}}/{{repo}}/commits/{tip}/status?per_page=100']
 answers={json.dumps(P):[0,dict(number=97,state='MERGED',mergedAt=utc(T+4226),headRefOid=tip,mergeCommit={'oid':tip})],json.dumps(S):[1 if fail else 0,[dict(total_count=1,statuses=[dict(context='shipcraft/ci',state='success',created_at=utc(T+3600))])]]}
 tools=cw/'tools83';tools.mkdir();gh=tools/'gh'
 gh.write_text('#!'+sys.executable+'\nimport json,sys\nanswers='+repr(answers)+'\na=sys.argv[1:]\nr=answers.get(json.dumps(a))\nif r is None: raise SystemExit(91)\nprint(json.dumps(r[1]))\nraise SystemExit(r[0])\n');gh.chmod(0o755)
 env['PATH']=str(tools)+os.pathsep+env['PATH']
 return report(rs,args)
git('init','-q','-b','main');git('config','gc.auto','0');git('config','maintenance.auto','false')
write(Path('tests/test_value.py'),'def test_value(): assert False\n')
write(Path('.shipcraft.toml'),'shipcraft_min = "2.18"\nlang = "python"\nrunner = "pytest"\ntest_command = "echo must-not-run {junit}"\n[execution]\nci = "local"\nreview = "off"\n')
save(1700000000)
if case=='v1-83.times':
 s=local()
 assert 'first row at 1970-01-01T00:01:40Z, last row at 1970-01-01T00:03:20Z (UTC)' in s,s
 assert s.count('first row at 1970-01-01T00:01:40Z, last row at 1970-01-01T00:03:20Z (UTC)')==2,s
 assert 'red at 1970-01-01T00:01:40Z, close at 1970-01-01T00:02:20Z, merge at 1970-01-01T00:03:20Z' in s,s
elif case=='v1-83.fractional-times':
 s=local(cycle(100.9,140.9,200.9))
 assert s.count('first row at 1970-01-01T00:01:40Z, last row at 1970-01-01T00:03:20Z (UTC)')==2,s
 assert 'red at 1970-01-01T00:01:40Z, close at 1970-01-01T00:02:20Z, merge at 1970-01-01T00:03:20Z' in s,s
elif case=='v1-83.negative-epoch':
 s=local(cycle(-0.1,0.9,60.9))
 assert s.count('first row at 1969-12-31T23:59:59Z, last row at 1970-01-01T00:01:00Z (UTC)')==2,s
 assert 'red at 1969-12-31T23:59:59Z, close at 1970-01-01T00:00:00Z, merge at 1970-01-01T00:01:00Z' in s,s
elif case=='v1-83.duration-zero':
 s=local(cycle(100,100,100,ci=100))
 assert 'red to close 0 s, close to merge 0 s, red to merge 0 s; waiting 0 s;' in s,s
 assert 'median red to merge 0 s, median waiting 0 s' in s,s
elif case=='v1-83.duration-seconds':
 s=local(cycle(100,159,218,ci=159))
 assert 'red to close 59 s, close to merge 59 s, red to merge 1 min 58 s; waiting 59 s;' in s,s
 assert 'median red to merge 1 min 58 s, median waiting 59 s' in s,s
elif case=='v1-83.duration-minute':
 s=local(cycle(100,160,220,ci=160))
 assert 'red to close 1 min 0 s, close to merge 1 min 0 s, red to merge 2 min 0 s; waiting 1 min 0 s;' in s,s
 assert 'median red to merge 2 min 0 s, median waiting 1 min 0 s' in s,s
elif case=='v1-83.duration-below-hour':
 s=local(cycle(100,3699,7298,ci=3699))
 assert 'red to close 59 min 59 s, close to merge 59 min 59 s, red to merge 1 h 59 min 58 s; waiting 59 min 59 s;' in s,s
 assert 'median red to merge 1 h 59 min 58 s, median waiting 59 min 59 s' in s,s
elif case=='v1-83.duration-hour':
 s=local(cycle(100,3700,7300,ci=3700))
 assert 'red to close 1 h 0 min 0 s, close to merge 1 h 0 min 0 s, red to merge 2 h 0 min 0 s; waiting 1 h 0 min 0 s;' in s,s
 assert 'median red to merge 2 h 0 min 0 s, median waiting 1 h 0 min 0 s' in s,s
elif case=='v1-83.duration-mixed':
 s=local(cycle(100,4326,8552,ci=4326))
 assert 'red to close 1 h 10 min 26 s, close to merge 1 h 10 min 26 s, red to merge 2 h 20 min 52 s; waiting 1 h 10 min 26 s;' in s,s
 assert 'median red to merge 2 h 20 min 52 s, median waiting 1 h 10 min 26 s' in s,s
elif case=='v1-83.duration-over-day':
 s=local(cycle(100,97484,194868,ci=97484))
 assert 'red to close 27 h 3 min 4 s, close to merge 27 h 3 min 4 s, red to merge 54 h 6 min 8 s; waiting 27 h 3 min 4 s;' in s,s
 assert 'median red to merge 54 h 6 min 8 s, median waiting 27 h 3 min 4 s' in s,s
elif case=='v1-83.duration-round-up':
 s=local(cycle(100,159.8,219.6,ci=159.8))
 assert 'red to close 1 min 0 s, close to merge 1 min 0 s, red to merge 2 min 0 s; waiting 1 min 0 s;' in s,s
 assert 'median red to merge 2 min 0 s, median waiting 1 min 0 s' in s,s
elif case=='v1-83.duration-round-down':
 s=local(cycle(100,160.1,220.2,ci=160.1))
 assert 'red to close 1 min 0 s, close to merge 1 min 0 s, red to merge 2 min 0 s; waiting 1 min 0 s;' in s,s
 assert 'median red to merge 2 min 0 s, median waiting 1 min 0 s' in s,s
elif case=='v1-83.duration-negative':
 s=local(cycle(200,134.8,400))
 assert 'red to close -1 min 5 s, close to merge 4 min 25 s, red to merge 3 min 20 s;' in s,s
elif case=='v1-83.duration-negative-zero':
 s=local(cycle(200,199.8,400))
 assert 'red to close 0 s, close to merge 3 min 20 s, red to merge 3 min 20 s;' in s,s
elif case=='v1-83.latency-whole':
 rs=cycle()
 for layer in ('hook','ci'):
  for i,secs in enumerate([9, 9, 54.46]):rs.append(row(layer,110+i,secs=secs))
 s=local(rs)
 assert s.count('hook 3 (p50 9.0 s, p90 54.5 s, refusals {})')==2,s
 assert s.count('ci 3 (p50 9.0 s, p90 54.5 s, refusals {})')==2,s
elif case=='v1-83.latency-fraction':
 rs=cycle()
 for layer in ('hook','ci'):
  for i,secs in enumerate([0.64, 0.64, 1245.26]):rs.append(row(layer,110+i,secs=secs))
 s=local(rs)
 assert s.count('hook 3 (p50 0.6 s, p90 1245.3 s, refusals {})')==2,s
 assert s.count('ci 3 (p50 0.6 s, p90 1245.3 s, refusals {})')==2,s
elif case=='v1-83.share-rounded':
 rs=[]
 for id,result in zip(('A','B','C'),['passed', 'passed', 'refused']):rs+=cycle(id=id)+[row('review',150,id,result=result,code='no-report' if result=='refused' else '')]
 s=local(rs)
 assert 'approved on first review 67%' in s,s
 assert 'first approved true;' in s,s
elif case=='v1-83.share-zero':
 rs=[]
 for id,result in zip(('A','B','C'),['refused', 'refused', 'refused']):rs+=cycle(id=id)+[row('review',150,id,result=result,code='no-report' if result=='refused' else '')]
 s=local(rs)
 assert 'approved on first review 0%' in s,s
 assert 'first approved false;' in s,s
elif case=='v1-83.share-full':
 rs=[]
 for id,result in zip(('A','B','C'),['passed', 'passed', 'passed']):rs+=cycle(id=id)+[row('review',150,id,result=result,code='no-report' if result=='refused' else '')]
 s=local(rs)
 assert 'approved on first review 100%' in s,s
 assert 'first approved true;' in s,s
elif case=='v1-83.dora-times':
 s=releases()
 assert 'deploys: 3 release(s), first at 2023-11-14T22:13:20Z, last at 2023-11-17T22:13:20Z, per day 1.00 (n 3, missing 0)' in s,s
elif case=='v1-83.dora-durations':
 s=releases()
 assert 'lead time: median 5 min 0 s, p90 13 min 20 s (n 4, missing 0)' in s,s
 assert 'time to recover: median 2 min 0 s, p90 3 min 0 s (n 2, missing 0)' in s,s
elif case=='v1-83.dora-duration-boundary':
 s=releases(lead=(60,3600,97384,98000),recovery=(3600,97384))
 assert 'lead time: median 14 h 1 min 32 s, p90 27 h 13 min 20 s (n 4, missing 0)' in s,s
 assert 'time to recover: median 14 h 1 min 32 s, p90 27 h 3 min 4 s (n 2, missing 0)' in s,s
elif case=='v1-83.dora-shares':
 s=releases()
 assert 'rework rate: 67% (n 3, missing 0)' in s,s
 assert 'change failure rate: 67% (n 3, missing 0)' in s,s
elif case=='v1-83.dora-share-zero':
 s=releases(kinds=('feature','feature','feature','feature'))
 assert 'rework rate: 0% (n 3, missing 0)' in s,s
 assert 'change failure rate: 0% (n 3, missing 0)' in s,s
elif case=='v1-83.dora-share-full':
 s=releases(links=('v1.1.0','v2.0.0'),args=('--since','v1.1.0'))
 assert 'rework rate: 100% (n 2, missing 0)' in s,s
 assert 'change failure rate: 100% (n 2, missing 0)' in s,s
elif case=='v1-83.rate-small':
 s=releases(spacing=259200)
 assert 'per day 0.33 (n 3, missing 0)' in s,s
elif case=='v1-83.rate-whole':
 s=releases(spacing=43200)
 assert 'per day 2.00 (n 3, missing 0)' in s,s
elif case=='v1-83.github-values':
 s=github()
 assert 'merge at 2023-11-14T23:23:46Z; red to close 1 min 0 s, close to merge 1 h 9 min 26 s, red to merge 1 h 10 min 26 s; waiting 10 min 26 s;' in s,s
 assert '; from github: merge_at, close_to_merge, red_to_merge, waiting' in s,s
 assert 'github: selected 1, merge filled 1, waiting filled 1; missing none' in s,s
elif case=='v1-83.github-late-failure':
 s=github(fail=True)
 assert 'merge at 2023-11-14T23:23:46Z; red to close 1 min 0 s, close to merge 1 h 9 min 26 s, red to merge 1 h 10 min 26 s; waiting -;' in s,s
 assert '; from github: merge_at, close_to_merge, red_to_merge' in s,s
 assert 'github: selected 1, merge filled 1, waiting filled 0; missing gh failed 1' in s,s
elif case=='v1-83.empty-control':
 s=local([row('red',100)])
 assert 'merge at -; red to close -, close to merge -, red to merge -; waiting -;' in s,s
 assert 'reviews passed 0, refused 0, error 0, first approved -; redos 0; refusals {}, errors 0; hook 0 (p50 -, p90 -, refusals {}); ci 0 (p50 -, p90 -, refusals {})' in s,s
elif case=='v1-83.json-local':
 s=local(args=('--json',))
 expected='{"ci":{"count":0,"p50":null,"p90":null,"refusals":{}},"first_at":100,"hook":{"count":0,"p50":null,"p90":null,"refusals":{}},"kind":"meta","last_at":200}\n{"change_kind":null,"ci":{"count":0,"p50":null,"p90":null,"refusals":{}},"close_at":140,"close_to_merge":60,"errors":0,"first_review_approved":null,"fixes_release":null,"hook":{"count":0,"p50":null,"p90":null,"refusals":{}},"kind":"lock","lock":"A","merge_at":200,"red_at":100,"red_to_close":40,"red_to_merge":100,"redos":0,"refusals":{},"reported_at":null,"reviews":{"error":0,"passed":0,"refused":0},"state":"merged","unobserved":[],"waiting":null}\n{"day":"1970-01-01","first_review_approved_share":null,"kind":"day","merged_locks":1,"red_to_merge_median":100,"waiting_median":null}\n{"change_failure_rate":{"missing":0,"n":0,"reason":"no release read","value":null},"deploys":{"missing":0,"n":0,"reason":"no release read","value":null},"git":{"default_branch":"refs/heads/main","reason":null,"releases":0},"kind":"dora","lead_time":{"missing":0,"n":0,"reason":"no shipped lock in the releases read","value":null},"rework_rate":{"missing":0,"n":0,"reason":"no release read ships a lock","value":null},"since":null,"time_to_recover":{"missing":0,"n":0,"reason":"no shipped fix lock with reported_at","value":null}}\n'
 assert s==expected,(expected,s)
elif case=='v1-83.json-release':
 s=releases(args=('--json',))
 expected='{"ci":{"count":0,"p50":null,"p90":null,"refusals":{}},"first_at":1699999900,"hook":{"count":0,"p50":null,"p90":null,"refusals":{}},"kind":"meta","last_at":1700258400}\n{"change_kind":"fix","ci":{"count":0,"p50":null,"p90":null,"refusals":{}},"close_at":null,"close_to_merge":null,"errors":0,"first_review_approved":null,"fixes_release":"v1.1.0","hook":{"count":0,"p50":null,"p90":null,"refusals":{}},"kind":"lock","lock":"D","merge_at":null,"red_at":1700258400,"red_to_close":null,"red_to_merge":null,"redos":0,"refusals":{},"reported_at":"2023-11-17T22:10:20Z","reviews":{"error":0,"passed":0,"refused":0},"state":"merge_not_observed","unobserved":["close"],"waiting":null}\n{"change_kind":"feature","ci":{"count":0,"p50":null,"p90":null,"refusals":{}},"close_at":null,"close_to_merge":null,"errors":0,"first_review_approved":null,"fixes_release":null,"hook":{"count":0,"p50":null,"p90":null,"refusals":{}},"kind":"lock","lock":"A","merge_at":1700000001,"red_at":1699999900,"red_to_close":null,"red_to_merge":101,"redos":0,"refusals":{},"reported_at":null,"reviews":{"error":0,"passed":0,"refused":0},"state":"merged","unobserved":["close"],"waiting":null}\n{"change_kind":"fix","ci":{"count":0,"p50":null,"p90":null,"refusals":{}},"close_at":null,"close_to_merge":null,"errors":0,"first_review_approved":null,"fixes_release":"v1.0.0","hook":{"count":0,"p50":null,"p90":null,"refusals":{}},"kind":"lock","lock":"B","merge_at":null,"red_at":1700086200,"red_to_close":null,"red_to_merge":null,"redos":0,"refusals":{},"reported_at":"2023-11-15T22:12:20Z","reviews":{"error":0,"passed":0,"refused":0},"state":"merge_not_observed","unobserved":["close"],"waiting":null}\n{"change_kind":"feature","ci":{"count":0,"p50":null,"p90":null,"refusals":{}},"close_at":null,"close_to_merge":null,"errors":0,"first_review_approved":null,"fixes_release":null,"hook":{"count":0,"p50":null,"p90":null,"refusals":{}},"kind":"lock","lock":"C","merge_at":null,"red_at":1700086000,"red_to_close":null,"red_to_merge":null,"redos":0,"refusals":{},"reported_at":null,"reviews":{"error":0,"passed":0,"refused":0},"state":"merge_not_observed","unobserved":["close"],"waiting":null}\n{"day":"2023-11-14","first_review_approved_share":null,"kind":"day","merged_locks":1,"red_to_merge_median":101,"waiting_median":null}\n{"change_failure_rate":{"missing":0,"n":3,"reason":null,"value":0.6666666666666666},"deploys":{"missing":0,"n":3,"reason":null,"value":{"count":3,"first":1700000000,"last":1700259200,"per_day":1}},"git":{"default_branch":"refs/heads/main","reason":null,"releases":3},"kind":"dora","lead_time":{"missing":0,"n":4,"reason":null,"value":{"median":300,"p90":800}},"rework_rate":{"missing":0,"n":3,"reason":null,"value":0.6666666666666666},"since":null,"time_to_recover":{"missing":0,"n":2,"reason":null,"value":{"median":120,"p90":180}}}\n'
 assert s==expected,(expected,s)
elif case=='v1-83.json-github':
 s=github(args=('--json','--github'))
 expected='{"ci":{"count":0,"p50":null,"p90":null,"refusals":{}},"first_at":1700000000,"hook":{"count":0,"p50":null,"p90":null,"refusals":{}},"kind":"meta","last_at":1700000200}\n{"change_kind":"feature","ci":{"count":0,"p50":null,"p90":null,"refusals":{}},"close_at":1700000060,"close_to_merge":4166,"errors":1,"first_review_approved":null,"fixes_release":null,"github":["merge_at","close_to_merge","red_to_merge","waiting"],"hook":{"count":0,"p50":null,"p90":null,"refusals":{}},"kind":"lock","lock":"A","merge_at":1700004226,"red_at":1700000000,"red_to_close":60,"red_to_merge":4226,"redos":0,"refusals":{},"reported_at":null,"reviews":{"error":0,"passed":0,"refused":0},"state":"merge_not_observed","unobserved":[],"waiting":626}\n{"change_failure_rate":{"missing":0,"n":1,"reason":null,"value":0},"deploys":{"missing":0,"n":1,"reason":null,"value":{"count":1,"first":1700000000,"last":1700000000,"per_day":null}},"git":{"default_branch":"refs/heads/main","reason":null,"releases":1},"kind":"dora","lead_time":{"missing":1,"n":0,"reason":"1 shipped lock(s) without a passed red row in this run log, or released before it","value":null},"rework_rate":{"missing":0,"n":1,"reason":null,"value":0},"since":null,"time_to_recover":{"missing":0,"n":0,"reason":"no shipped fix lock with reported_at","value":null}}\n{"kind":"github","merge_filled":1,"missing":{},"selected":1,"waiting_filled":1}\n'
 assert s==expected,(expected,s)
elif case=='v1-83.json-metrics':
 rs=[]
 for id,result in zip(('A','B','C'),('passed','passed','refused')):rs+=cycle(id=id)+[row('review',150,id,result=result,code='no-report' if result=='refused' else '')]
 for layer in ('hook','ci'):
  for i,secs in enumerate((0.64,9,54.46)):rs.append(row(layer,110+i,secs=secs))
 s=local(rs,args=('--json',))
 expected='{"ci":{"count":3,"p50":9,"p90":54.46,"refusals":{}},"first_at":100,"hook":{"count":3,"p50":9,"p90":54.46,"refusals":{}},"kind":"meta","last_at":200}\n{"change_kind":null,"ci":{"count":3,"p50":9,"p90":54.46,"refusals":{}},"close_at":140,"close_to_merge":60,"errors":0,"first_review_approved":true,"fixes_release":null,"hook":{"count":3,"p50":9,"p90":54.46,"refusals":{}},"kind":"lock","lock":"A","merge_at":200,"red_at":100,"red_to_close":40,"red_to_merge":100,"redos":0,"refusals":{},"reported_at":null,"reviews":{"error":0,"passed":1,"refused":0},"state":"merged","unobserved":[],"waiting":88}\n{"change_kind":null,"ci":{"count":0,"p50":null,"p90":null,"refusals":{}},"close_at":140,"close_to_merge":60,"errors":0,"first_review_approved":true,"fixes_release":null,"hook":{"count":0,"p50":null,"p90":null,"refusals":{}},"kind":"lock","lock":"B","merge_at":200,"red_at":100,"red_to_close":40,"red_to_merge":100,"redos":0,"refusals":{},"reported_at":null,"reviews":{"error":0,"passed":1,"refused":0},"state":"merged","unobserved":[],"waiting":null}\n{"change_kind":null,"ci":{"count":0,"p50":null,"p90":null,"refusals":{}},"close_at":140,"close_to_merge":60,"errors":0,"first_review_approved":false,"fixes_release":null,"hook":{"count":0,"p50":null,"p90":null,"refusals":{}},"kind":"lock","lock":"C","merge_at":200,"red_at":100,"red_to_close":40,"red_to_merge":100,"redos":0,"refusals":{"no-report":1},"reported_at":null,"reviews":{"error":0,"passed":0,"refused":1},"state":"merged","unobserved":[],"waiting":null}\n{"day":"1970-01-01","first_review_approved_share":0.6666666666666666,"kind":"day","merged_locks":3,"red_to_merge_median":100,"waiting_median":88}\n{"change_failure_rate":{"missing":0,"n":0,"reason":"no release read","value":null},"deploys":{"missing":0,"n":0,"reason":"no release read","value":null},"git":{"default_branch":"refs/heads/main","reason":null,"releases":0},"kind":"dora","lead_time":{"missing":0,"n":0,"reason":"no shipped lock in the releases read","value":null},"rework_rate":{"missing":0,"n":0,"reason":"no release read ships a lock","value":null},"since":null,"time_to_recover":{"missing":0,"n":0,"reason":"no shipped fix lock with reported_at","value":null}}\n'
 assert s==expected,(expected,s)
elif case=='v1-83.json-fraction':
 s=local(cycle(100.9,140.9,200.9),args=('--json',))
 expected='{"ci":{"count":0,"p50":null,"p90":null,"refusals":{}},"first_at":100.9,"hook":{"count":0,"p50":null,"p90":null,"refusals":{}},"kind":"meta","last_at":200.9}\n{"change_kind":null,"ci":{"count":0,"p50":null,"p90":null,"refusals":{}},"close_at":140.9,"close_to_merge":60,"errors":0,"first_review_approved":null,"fixes_release":null,"hook":{"count":0,"p50":null,"p90":null,"refusals":{}},"kind":"lock","lock":"A","merge_at":200.9,"red_at":100.9,"red_to_close":40,"red_to_merge":100,"redos":0,"refusals":{},"reported_at":null,"reviews":{"error":0,"passed":0,"refused":0},"state":"merged","unobserved":[],"waiting":null}\n{"day":"1970-01-01","first_review_approved_share":null,"kind":"day","merged_locks":1,"red_to_merge_median":100,"waiting_median":null}\n{"change_failure_rate":{"missing":0,"n":0,"reason":"no release read","value":null},"deploys":{"missing":0,"n":0,"reason":"no release read","value":null},"git":{"default_branch":"refs/heads/main","reason":null,"releases":0},"kind":"dora","lead_time":{"missing":0,"n":0,"reason":"no shipped lock in the releases read","value":null},"rework_rate":{"missing":0,"n":0,"reason":"no release read ships a lock","value":null},"since":null,"time_to_recover":{"missing":0,"n":0,"reason":"no shipped fix lock with reported_at","value":null}}\n'
 assert s==expected,(expected,s)
else:raise AssertionError(('unrouted case',case))
PY83
  pass
}
