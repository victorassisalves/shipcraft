# Item 87: stderr reasons and bounded retries, through public commands only.
item87_langs() { echo core; }
item87_cases() {
  local c
  for c in reason-codex reason-last-error reason-fallback reason-empty reason-lossy reason-exact reason-control \
    retry-pr retry-review retry-review-pr retry-third retry-changes exhausted zero \
    nonretry-approve nonretry-changes nonretry-refuse nonretry-malformed nonretry-quota nonretry-timeout nonretry-start nonretry-case \
    stub-control sequence-control slot-control slot-free early-control early-second immutable publish-fails report \
    min-absent min-old-zero min-old-positive min-patch-old invalid-negative invalid-fraction invalid-string invalid-bool version; do echo "v1-87.$c"; done
}
item87_case() {
  EXPECT="item 87: ${CASE#v1-87.}"
  v1_start codex
  CFGS='execution|ci|"off"'
  # Baseline 2.40 must reach the reviewer rather than its future-version guard.
  # Gate cases independently require 2.41; GREEN uses the declared 2.41 floor.
  local floor
  floor=$(shipcraft --version 2>/dev/null | sed -E 's/^shipcraft ([0-9]+\.[0-9]+)\..*/\1/')
  CFGS="$CFGS
-|shipcraft_min|\"$floor\"
review|retry_wait|1"
  case "${CASE#v1-87.}" in
    retry-pr) CFGS="$CFGS
execution|ci|\"local\"" ;;
    retry-third) CFGS="$CFGS
review|timeout|1" ;;
  esac
  pr_main; pr_feature
  # Existing publication fixture; its baseline controls are selected from item 82.
  case "${CASE#v1-87.}" in publish-fails) i82_publish_fail ;; esac
  must_accept 'item 87 public contract' cmd "$PY" - "${CASE#v1-87.}" "$(command -v shipcraft)" "$ST" "$CB" "$CW" <<'PY87'
import json,os,re,shutil,subprocess,sys,time
from pathlib import Path
case,binary,st,cb,cw=sys.argv[1:];binary=str(Path(binary).resolve());st=Path(st);cb=Path(cb);cw=Path(cw);root=Path.cwd()
def run(*args,env=None,timeout=30):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,env=env,timeout=timeout)
 print('$',repr(args),'rc',p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 return p
def git(*args):
 p=run('git',*args);assert p.returncode==0,('fixture git failed',args,p.stderr)
 return p.stdout.decode().strip()
def configure(wait=1,minimum=None):
 branch=git('branch','--show-current');git('checkout','-q','main')
 p=Path('.shipcraft.toml');s=p.read_text()
 if minimum is not None:
  s=re.sub(r'(?m)^shipcraft_min\s*=.*\n','',s)
  if minimum!='absent':s='shipcraft_min = '+json.dumps(minimum)+'\n'+s
 s=re.sub(r'(?m)^retry_wait\s*=.*$', 'retry_wait = '+str(wait),s)
 p.write_text(s)
 git('add','.shipcraft.toml');tree=git('write-tree');parent=git('rev-parse','HEAD')
 sha=git('commit-tree',tree,'-p',parent)
 git('update-ref','HEAD',sha);git('push','-q','origin','main');git('checkout','-q',branch)
def reviewer(**kw):
 (st/'reviewer.json').write_text(json.dumps(kw))
def calls():
 p=st/'reviewer.calls.jsonl'
 return [json.loads(s) for s in p.read_text().splitlines()] if p.exists() else []
def rows():
 p=Path('.git/shipcraft/runs.jsonl')
 return [json.loads(s) for s in p.read_text().splitlines()] if p.exists() else []
def invoke(kind='review',env=None):
 if kind=='pr':return run(binary,'pr','--title','Titulo-PR-6d1','--body',cw/'body.md',env=env)
 if kind=='review-pr':return run(binary,'review','--pr','1',env=env)
 return run(binary,'review',env=env)
def output(p):return (p.stdout+p.stderr).decode(errors='replace')
def mutate_live_text():
 # A case-owned extension of the recording launcher; values seed fixture data only.
 agent=cb/'codex';src=agent.read_text();needle='    timeline(c, "end")'
 inject="    if attempt == 1:\n        p = os.path.join(ST, 'prs.json')\n        d = json.load(open(p)); next(iter(d.values())).update(title='CHANGED87', body='CHANGED87')\n        json.dump(d, open(p, 'w'))\n"
 assert needle in src;agent.write_text(src.replace(needle,inject+needle))
def changes_on_approval():
 agent=cb/'codex';src=agent.read_text();needle='elif mode == "approve":\n        out = "APPROVE'
 assert src.count(needle)==1,'fixture: approval branch must match exactly once'
 agent.write_text(src.replace(needle,'elif mode == "approve":\n        out = "CHANGES REQUESTED'))
sha=git('rev-parse','HEAD');(st/'sha').write_text(sha+'\n')
if case=='reason-codex':
 reviewer(mode='codex-error',stderr_hex=b'ERROR: model access unavailable\ntokens used\n44,605\n'.hex())
 p=invoke('pr')
 assert p.returncode!=0 and len(calls())==1
 reason='the reviewer exited with code 1: ERROR: model access unavailable'
 assert reason in output(p),('reason must not be the token count',output(p))
 r=[r for r in rows() if r['layer']=='pr'][-1]
 assert reason in r['reason'] and r['code']=='review-error',r
elif case=='reason-last-error':
 reviewer(mode='codex-error',stderr_hex=b'ERROR: first\n \t\fERROR: final reason\r\ntrailing prose\ntokens used\n123\n'.hex())
 p=invoke();assert 'the reviewer exited with code 1: ERROR: final reason' in output(p),output(p)
elif case=='reason-fallback':
 reviewer(mode='codex-error',stderr_hex=b'old reason\n  final fallback  \r\nToKeNs UsEd: 321\n44,605\n\n'.hex())
 p=invoke();assert 'the reviewer exited with code 1: final fallback' in output(p),output(p)
elif case=='reason-empty':
 reviewer(mode='codex-error',stderr_hex='123\n\u00e9\nTOKENS USED\n44,605\n'.encode().hex())
 p=invoke();assert 'the reviewer exited with code 1: \n' in output(p),output(p)
elif case=='reason-lossy':
 reviewer(mode='codex-error',stderr_hex=b'ERROR: bad \xff byte\ntokens used\n123\n'.hex())
 p=invoke();assert 'the reviewer exited with code 1: ERROR: bad \ufffd byte' in output(p),output(p)
elif case=='reason-exact':
 raw='error: lower\n\x1b[31mERROR: colored\n\u00a0ERROR: non-ASCII trim\nlast fallback\ntokens used\n123\n'.encode()
 reviewer(mode='codex-error',stderr_hex=raw.hex())
 p=invoke();assert 'the reviewer exited with code 1: last fallback' in output(p),output(p)
elif case=='reason-control':
 reviewer(mode='quota');p=invoke()
 assert p.returncode!=0 and len(calls())==1
 assert 'the reviewer exited with code 1: Error: usage limit reached (quota exceeded). Try again later.' in output(p),output(p)
elif case=='stub-control':
 # Exercise the exact copied launcher, raw bytes and output-file interface without Shipcraft parsing.
 raw=b'ERROR: fixture87\ntokens used\n44,605\n';reviewer(mode='codex-error',stderr_hex=raw.hex())
 p=run(cb/'codex','-o',cw/'answer87')
 assert p.returncode==1 and p.stderr==raw and p.stdout==b'',p
 assert (cw/'answer87').read_bytes()==b'' and len(calls())==1
elif case=='sequence-control':
 reviewer(mode='retry-then-approve',fail_times=2)
 ps=[run(cb/'codex','-o',cw/'answer87') for _ in range(3)]
 assert [p.returncode for p in ps]==[1,1,0],ps
 assert [p.stderr for p in ps[:2]]==[('ERROR: stream disconnected before completion: Unable to verify model access right now. Please retry.\ntokens used\n%d\n'%n).encode() for n in (4322,4323)]
 assert (cw/'answer87').read_text().startswith('APPROVE at '+sha+'\nBlocking: 0\n')
 assert len(calls())==3
elif case in ('retry-pr','retry-review','retry-review-pr','retry-third','retry-changes','exhausted','zero','publish-fails','report','immutable','early-second','early-control'):
 kind='review';failures=1
 if case=='retry-pr':kind='pr';expected=2
 elif case=='retry-review':expected=2
 elif case=='retry-review-pr':kind='review-pr';expected=2
 elif case=='retry-third':failures=2;expected=3
 elif case=='retry-changes':kind='review-pr';expected=2
 elif case=='exhausted':kind='pr';failures=9;expected=3
 elif case=='zero':configure(0);expected=1
 elif case=='publish-fails':kind='review-pr';expected=2
 elif case=='report':failures=2;expected=3
 elif case=='immutable':kind='review-pr';expected=2
 elif case=='early-second':expected=1
 elif case=='early-control':expected=0
 # Every case above explicitly owns its expected attempt count.
 if kind=='review-pr':
  git('push','-q','origin','HEAD')
  p=run(cb/'gh','pr','create','--title','Original87','--body','Intent87','--head','feature/alpha','--base','main');assert p.returncode==0
 if case=='immutable':mutate_live_text()
 if case in ('early-second','early-control'):
  # A PATH git proxy refuses only worktree creation, before that attempt writes a row.
  realgit=shutil.which('git');proxy=cb/'git'
  proxy.write_text('#!'+sys.executable+'\n'+"import os,sys\nfrom pathlib import Path\na=sys.argv[1:]\nif 'worktree' in a and 'add' in a and Path("+repr(str(st/'block87'))+").exists():\n Path("+repr(str(st/'blocked87'))+").touch();raise SystemExit(87)\nos.execv("+repr(realgit)+",["+repr(realgit)+",*a])\n")
  proxy.chmod(0o755)
  if case=='early-control':(st/'block87').touch()
  else:
   agent=cb/'codex';src=agent.read_text();needle='    timeline(c, "end")'
   assert needle in src;agent.write_text(src.replace(needle,"    Path87 = os.path.join(ST, 'block87')\n    open(Path87, 'w').close()\n"+needle))
 if case=='retry-changes':changes_on_approval()
 reviewer(mode='retry-then-approve',fail_times=failures,blocking=2 if case=='retry-changes' else 0,sleep=.4 if case=='retry-third' else 0)
 env=dict(os.environ)
 if case=='report':env['SHIPCRAFT_PR_LOCKS']='["item87-observed"]'
 p=invoke(kind,env);cs=calls();rs=[r for r in rows() if r['layer']=='review']
 assert len(cs)==expected,('attempt count',expected,len(cs),output(p))
 if case in ('early-second','early-control'):
  assert (st/'blocked87').exists(),'next attempt did not reach the failing worktree boundary'
  assert p.returncode!=0 and len(rs)==expected,('pre-row error added a row or retried',rs)
  assert all(r['result']=='error' for r in rs),rs
 else:
  assert len(rs)==expected,('one review row per attempt',rs)
  assert [r['result'] for r in rs]==(['error']*expected if case in ('exhausted','zero') else ['error']*(expected-1)+['refused' if case=='retry-changes' else 'passed']),rs
  assert [r['tokens'] for r in rs]==list(range(4322,4322+expected)),rs
  assert all(r.get('after_green_ci') is (case=='retry-pr') and not r.get('reused',False) for r in rs),rs
  assert all(not any(k in r for k in ('attempt','attempts','retry_wait')) for r in rs),rs
  assert all(r.get('diff_sha256')==rs[0].get('diff_sha256') and r.get('text_sha256')==rs[0].get('text_sha256') and r['commit']==sha for r in rs),rs
  assert all('resume' not in c['argv'] and '--resume' not in c['argv'] for c in cs),cs
  assert len({c['cwd'] for c in cs})==expected,'each attempt needs a new isolated copy'
  assert all(not Path(c['cwd']).exists() for c in cs),'attempt copy leaked'
  lines=[l for l in output(p).splitlines() if l.startswith('shipcraft: review attempt ')]
  why='the reviewer exited with code 1: ERROR: stream disconnected before completion: Unable to verify model access right now. Please retry.'
  assert lines==['shipcraft: review attempt %d of 3 gave no verdict (%s); trying again in 1 s'%(n,why) for n in range(1,expected)],lines
  assert len([l for l in output(p).splitlines() if l.startswith('shipcraft: review by ')])==expected,output(p)
  assert all(cs[i+1]['start']-cs[i]['start']>=1 for i in range(len(cs)-1)),cs
  if case in ('exhausted','zero'):
   assert p.returncode!=0 and why in output(p),output(p)
  elif case=='retry-changes':
   assert p.returncode!=0 and 'CHANGES REQUESTED' in output(p) and 'Blocking 2' in output(p),output(p)
   assert 'REVIEW-BODY-MARKER-3a9' in (st/'comments.jsonl').read_text(), 'final verdict body was not published'
  elif case=='publish-fails':assert p.returncode!=0 and (cb/'publish82-failed').exists(),output(p)
  else:assert p.returncode==0,output(p)
  if kind=='pr':
   prs=[r for r in rows() if r['layer']=='pr'];assert len(prs)==1,prs
   assert prs[0]['result']==('refused' if case=='exhausted' else 'passed'),prs
   assert prs[0]['secs']-sum(r['secs'] for r in rs)>=expected-1-.1,prs
   statuses=[json.loads(s) for s in (st/'statuses.jsonl').read_text().splitlines() if json.loads(s).get('context')=='shipcraft/review']
   assert [s['state'] for s in statuses]==['pending','error' if case=='exhausted' else 'success'],statuses
  if case=='immutable':
   briefs=[next(v for k,v in c['files'].items() if k.endswith('/brief.md')) for c in cs]
   assert all('Original87' in b and 'Intent87' in b and 'CHANGED87' not in b and sha in b for b in briefs),briefs
  if case=='report':
   q=run(binary,'report','--json');assert q.returncode==0
   lock=next(r for r in map(json.loads,q.stdout.splitlines()) if r.get('kind')=='lock' and r.get('lock')=='item87-observed')
   assert lock['reviews']=={'error':2,'passed':1,'refused':0} and lock['errors']==2,lock
elif case in ('nonretry-approve','nonretry-changes','nonretry-refuse','nonretry-malformed','nonretry-quota','nonretry-timeout','nonretry-start','nonretry-case'):
 mode='approve';want=0;n=1
 if case=='nonretry-changes':mode='approve';want=1
 elif case=='nonretry-refuse':mode='refuse';want=1
 elif case=='nonretry-malformed':mode='malformed';want=1
 elif case=='nonretry-quota':mode='quota';want=1
 elif case=='nonretry-timeout':mode='hang';want=1
 elif case=='nonretry-start':want=1;n=0
 elif case=='nonretry-case':mode='codex-error';want=1
 if case in ('nonretry-approve','nonretry-changes','nonretry-refuse','nonretry-malformed','nonretry-timeout'):
  agent=cb/'codex';src=agent.read_text()
  if case in ('nonretry-approve','nonretry-changes'):src=src.replace('nothing to point out beyond the above.', 'Please retry is quoted verdict text.')
  elif case=='nonretry-refuse':src=src.replace("I can't assist with reviewing this code.", "I can't assist. Please retry.")
  elif case=='nonretry-malformed':src=src.replace('LGTM, ship it!', 'Please retry')
  elif case=='nonretry-timeout':src=src.replace('time.sleep(float(c.get("hang", 25)))', 'sys.stderr.write("ERROR: Please retry\\n"); sys.stderr.flush(); time.sleep(float(c.get("hang", 25)))')
  agent.write_text(src)
 if case=='nonretry-changes':changes_on_approval()
 reviewer(mode=mode,hang=5,blocking=2 if case=='nonretry-changes' else 0,stderr_hex=b'ERROR: please retry\ntokens used\n123\n'.hex())
 if case=='nonretry-timeout':
  # Same public config path, one-second per-attempt timeout.
  branch=git('branch','--show-current');git('checkout','-q','main')
  f=Path('.shipcraft.toml');s=f.read_text();s=re.sub(r'(?m)^timeout\s*=.*$','timeout = 1',s);f.write_text(s)
  git('add','.shipcraft.toml');tree=git('write-tree');commit=git('commit-tree',tree,'-p',git('rev-parse','HEAD'));git('update-ref','HEAD',commit);git('push','-q','origin','main');git('checkout','-q',branch)
 if case=='nonretry-approve':
  git('push','-q','origin','HEAD')
  q=run(cb/'gh','pr','create','--title','Original87','--body','Intent87','--head','feature/alpha','--base','main');assert q.returncode==0
  mutate_live_text()
 if case=='nonretry-start':(cb/'codex').write_text('#!/no/such/interpreter87\n')
 p=invoke();assert (p.returncode!=0)==bool(want) and len(calls())==n,output(p)
 assert 'shipcraft: review attempt ' not in output(p),output(p)
 rs=[r for r in rows() if r['layer']=='review'];assert len(rs)==1,rs
 assert rs[0]['result']==('passed' if case=='nonretry-approve' else 'refused' if case=='nonretry-changes' else 'error'),rs
 if case=='nonretry-approve':
  live=next(iter(json.loads((st/'prs.json').read_text()).values()))
  assert (live['title'],live['body'])==('CHANGED87','CHANGED87'), 'mutation fixture did not run through the public reviewer'
 if case=='nonretry-changes':assert 'CHANGES REQUESTED at '+sha+'\nBlocking: 2\n' in output(p),output(p)
 if case=='nonretry-malformed':assert 'Why: review fails closed: without a well-formed verdict there is no approval, and shipcraft retries only a \"Please retry\" failure' in output(p),output(p)
elif case in ('slot-control','slot-free'):
 timeline=cw/'slot87.timeline';other= cw/'other87';other.mkdir();(other/'state').mkdir()
 shutil.copy2(cb/'codex',other/'codex')
 (other/'state/sha').write_text(sha+'\n')
 (other/'state/reviewer.json').write_text(json.dumps(dict(mode='approve',timeline=str(timeline),name='other')))
 if case=='slot-control':reviewer(mode='approve',sleep=.5,timeline=str(timeline),name='first');expected=1
 elif case=='slot-free':reviewer(mode='retry-then-approve',fail_times=1,timeline=str(timeline),name='first');expected=2
 log=cw/'slot87.out';children=[]
 try:
  with log.open('wb') as f:
   first=subprocess.Popen([binary,'review'],stdin=subprocess.DEVNULL,stdout=f,stderr=subprocess.STDOUT);children.append(first)
   deadline=time.time()+15
   while time.time()<deadline:
    ready=('shipcraft: review attempt 1 of 3' in log.read_text()) if case=='slot-free' else bool(calls())
    if ready or first.poll() is not None:break
    time.sleep(.01)
   assert ready,('first review did not enter retry wait',log.read_text())
   env=dict(os.environ,PATH=str(other)+os.pathsep+os.environ['PATH'])
   second=subprocess.Popen([binary,'review'],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env);children.append(second)
   out,err=second.communicate(timeout=15);assert second.returncode==0,(out,err)
   assert first.wait(timeout=15)==0,log.read_text()
  events=[line.split() for line in timeline.read_text().splitlines()]
  first_ends=[float(t) for n,layer,event,t in events if n=='first' and event=='end']
  first_starts=[float(t) for n,layer,event,t in events if n=='first' and event=='start']
  other_start=next(float(t) for n,layer,event,t in events if n=='other' and event=='start')
  assert len(calls())==expected and len(first_starts)==expected,events
  assert other_start>=first_ends[0],('a running review held no slot',events)
  if case=='slot-free':assert other_start<first_starts[1],('retry wait held the machine slot',events)
  rs=[r for r in rows() if r['layer']=='review'];assert len(rs)==expected+1,rs
 finally:
  for child in children:
   if child.poll() is None:child.kill();child.wait()
elif case in ('min-absent','min-old-zero','min-old-positive','min-patch-old','invalid-negative','invalid-fraction','invalid-string','invalid-bool'):
 minimum=None;wait=1
 if case=='min-absent':minimum='absent'
 elif case=='min-old-zero':minimum='2.40';wait=0
 elif case=='min-old-positive':minimum='2.40'
 elif case=='min-patch-old':minimum='2.40.0';wait=0
 elif case=='invalid-negative':wait=-1
 elif case=='invalid-fraction':wait=1.5
 elif case=='invalid-string':wait='"1"'
 elif case=='invalid-bool':wait='true'
 configure(wait,minimum);p=invoke()
 assert p.returncode!=0 and len(calls())==0,('retry_wait config must refuse before reviewer',output(p))
 ls=[s for s in output(p).splitlines() if s.strip()][-3:]
 assert [s.split(':',1)[0] for s in ls]==['shipcraft refused','Why','Next'] and 'retry_wait' in '\n'.join(ls),ls
 if minimum is not None:assert 'shipcraft_min' in output(p) and '2.41' in output(p),output(p)
elif case=='version':
 contract=re.search(r'This contract is \*\*([0-9.]+)\*\*',(Path(os.environ['ACEITE']).parent/'docs/spec.md').read_text()).group(1)
 p=run(binary,'--version');assert re.fullmatch(rb'shipcraft '+re.escape(contract.encode())+rb' \([0-9a-f]{12}\)\n',p.stdout),(contract,p.stdout)
else:raise AssertionError('unrouted case: '+case)
PY87
  pass
}
