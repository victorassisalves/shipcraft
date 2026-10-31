# Item 73: public status and GitHub-wait output; offline gh fixtures only.
item73_cases() {
  local c
  for c in status-absent status-string status-table status-dotted \
    first-success first-pending first-failure first-error first-missing first-empty first-opaque \
    transition transition-absence dedup-status checks-words checks-failed checks-dedup \
    stop-failure stop-error slow-status slow-check later-gh-error later-review-fails later-summary-fails \
    control-gh-error control-log-error control-local control-off control-review control-merge control-ci; do
    echo "v1-73.$c"
  done
}
# Snapshots use plumbing, never a hook override or a fabricated lock.
i73_commit() {
  git add -A || fail 'fixture add'
  local tree parent commit
  tree=$(git write-tree) && parent=$(git rev-parse HEAD) && commit=$(printf '%s\n' "$1" | git commit-tree "$tree" -p "$parent") && git update-ref HEAD "$commit" || fail 'fixture snapshot'
}
i73_capture() {
  "$PY" - "$CW" "$@" <<'PY_CAPTURE'
import os,pathlib,selectors,subprocess,sys
root=pathlib.Path(sys.argv[1]);selector=selectors.DefaultSelector()
with (root/'stdout73').open('wb') as stdout, (root/'stderr73').open('wb') as stderr:
 p=subprocess.Popen(sys.argv[2:],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 selector.register(p.stdout,selectors.EVENT_READ,stdout);selector.register(p.stderr,selectors.EVENT_READ,stderr)
 while selector.get_map():
  for key,_ in selector.select():
   data=os.read(key.fileobj.fileno(),65536)
   if not data:selector.unregister(key.fileobj);continue
   key.data.write(data);key.data.flush();sys.stdout.buffer.write(data);sys.stdout.buffer.flush()
 sys.exit(p.wait())
PY_CAPTURE
}
item73_case() {
  local c="${CASE#v1-73.}"
  EXPECT="item 73: $c"
  v1_start codex
  must_accept 'init fixture' cmd shipcraft init
  H toml-set .shipcraft.toml execution ci '"github"'
  H toml-set .shipcraft.toml execution review '"local"'
  H toml-set .shipcraft.toml execution ci_timeout 20
  case "$c" in
    status-*)
      H toml-set .shipcraft.toml execution review '"off"'
      "$PY" - "$c" <<'PY'
from pathlib import Path
import re,sys
p=Path('.shipcraft.toml');s=p.read_text();s=re.sub(r'(?ms)^\[roles\]\n.*?(?=^\[|\Z)','',s)
mode=sys.argv[1]
if mode=='status-string':s+='\n[roles]\nreview="claude"\n'
if mode=='status-table':s+='\n[roles]\nred="gemini"\ngreen="claude"\nreview={agent="codex",model="model73",effort="high"}\n'
if mode=='status-dotted':s='roles.review.agent="claude"\nroles.review.model="other73"\nroles.review.effort="max"\n'+s
p.write_text(s)
PY
      # A full byte/mode snapshot includes the optional run log and hooks.
      chk 'off status exact lines, no phase or filesystem writes' "$PY" - "$c" "$(command -v shipcraft)" <<'PY'
import pathlib,subprocess,sys,stat
mode,binary=sys.argv[1:]
def snapshot():
 return {str(p):(stat.S_IMODE(p.lstat().st_mode),p.read_bytes() if p.is_file() and not p.is_symlink() else str(p.readlink()) if p.is_symlink() else None) for p in pathlib.Path('.').rglob('*')}
before=snapshot();p=subprocess.run([binary,'status'],capture_output=True,text=True)
assert p.returncode==0,(p.returncode,p.stderr)
assert snapshot()==before,'status wrote files'
ls=p.stdout.splitlines();layers=[s for s in ls if s.startswith('shipcraft: layers:')]
assert layers==['shipcraft: layers: ci github; review off'],p.stdout
roles='red gemini; green claude' if mode=='status-table' else "red not set (the orchestrator's choice); green not set (the orchestrator's choice)"
want='shipcraft: roles: '+roles+'; review off'
assert ls.count(want)==1 and ls.index(want)==ls.index(layers[0])+1,p.stdout
for phrase in ('shipcraft: branch','shipcraft: open locks:','hook','protection'):assert any(phrase in s for s in ls),p.stdout
PY
      chk 'no declared agent ran' eq "$(rev_n)" 0
      pass; return ;;
  esac
  case "$c" in
    first-pending|first-missing|first-empty|first-opaque|slow-check|checks-words|checks-dedup) H toml-set .shipcraft.toml execution ci_timeout 3 ;;
    slow-status) H toml-set .shipcraft.toml execution ci_timeout 1 ;;
    control-local) H toml-set .shipcraft.toml execution ci '"local"' ;;
    control-off) H toml-set .shipcraft.toml execution ci '"off"' ;;
  esac
  case "$c" in
    checks-*|stop-*|slow-check) H toml-set .shipcraft.toml execution suite_checks '["zeta suite", "alpha/β", "third73"]' ;;
  esac
  i73_commit 'chore: item73 base'; remote_setup
  BASE=$(head_rev); BR=feature/item73; git checkout -qb "$BR"
  printf 'value73 = 1\n' > value73.py; i73_commit 'feat: item73'
  HEADSHA=$(head_rev); printf '%s\n' "$HEADSHA" > "$ST/sha"
  printf 'Intent item73\n' > "$CW/body.md"
  case "$c" in later-review-fails) rev_cfg changes ;; esac
  # Existing gh response injection consumes one document per API call and repeats
  # the final document. These are GitHub REST shapes, not invented CLI text.
  "$PY" - "$ST" "$HEADSHA" "$c" <<'PY'
import json,pathlib,sys
st=pathlib.Path(sys.argv[1]);sha=sys.argv[2];mode=sys.argv[3]
def status(state,desc='fixture',id=1):
 return {'json':[] if state is None else [dict(id=id,sha=sha,context='shipcraft/ci',state=state,description=desc)]}
def run(name,word,id=1):
 if word=='unreadable':return {'error':True}
 if word=='bad-json':return {'raw':'{broken'}
 runs=[] if word=='missing' else [dict(id=id,head_sha=sha,name=name,status='in_progress' if word=='pending' else 'completed',conclusion=None if word=='pending' else 'failure' if word=='failed' else 'success',app={'id':1},check_suite={'id':1})]
 return {'json':{'total_count':len(runs),'check_runs':runs}}
seq=['success'];checks=[]
if mode.startswith('first-'):seq=[{'pending':'pending','failure':'failure','error':'error','missing':None,'empty':'','opaque':'queued73','success':'success'}[mode[6:]]]
if mode=='transition':seq=['pending','pending','success']
if mode=='transition-absence':seq=[None,'','queued73','pending','success']
if mode=='dedup-status':seq=['pending','pending','pending','success']
if mode in ('stop-failure','stop-error'):seq=[mode[5:]]
if mode=='slow-status':seq=['pending']
if mode in ('later-gh-error','control-gh-error','control-log-error'):seq=['pending', 'GHERROR'] if mode=='later-gh-error' else ['GHERROR']
responses={'statuses':[{'error':True} if x=='GHERROR' else status(x,desc='description '+str(i),id=i+1) for i,x in enumerate(seq)]}
names=['zeta suite','alpha/β','third73']
if mode=='checks-words':vectors=[['missing','pending','unreadable'],['green','green','green']]
elif mode=='checks-failed':vectors=[['pending','failed','missing']]
elif mode=='checks-dedup':vectors=[['green','unreadable','pending'],['green','bad-json','pending'],['green','bad-json','pending']]
elif mode=='slow-check':vectors=[['green','pending','missing']]
else:vectors=[]
for i,vector in enumerate(vectors):
 for name,word in zip(names,vector):checks.append(run(name,word,id=i+1))
if mode=='dedup-status':
 for i,response in enumerate(responses['statuses']):
  unrelated=dict(id=90+i,sha=sha,context='other/context',state='pending',description='unrelated')
  response['json'].insert(0 if i%2 else len(response['json']),unrelated)
if mode=='checks-dedup':
 for i,response in enumerate(checks):
  if 'json' in response and response['json']['check_runs']:
   runs=response['json']['check_runs'];other={**runs[0],'id':800+i,'app':{'id':2},'check_suite':{'id':2}}
   runs.insert(0 if i%2 else len(runs),other);response['json']['total_count']=len(runs)
if checks:responses['check-runs']=checks
(st/'responses.json').write_text(json.dumps(responses))
(st/'mode73').write_text(mode)
PY
  # Delegate all ordinary CLI behavior to the established offline gh stub.
  # Delays measure completion time, and the fault occurs only at the summary.
  mv "$CB/gh" "$CB/gh73-real"
  cat > "$CB/gh" <<'PY'
#!/usr/bin/env python3
import pathlib,subprocess,sys,time,json
root=pathlib.Path(__file__).parent;st=root/'state';mode=(st/'mode73').read_text();args=sys.argv[1:]
is_status=any('/commits/' in a and a.endswith('/statuses') for a in args)
is_check=any('/check-runs?' in a for a in args)
if mode=='later-summary-fails' and args[:2]==['pr','comment']:
 nfile=st/'comments73';n=int(nfile.read_text())+1 if nfile.exists() else 1;nfile.write_text(str(n))
 if n==2:print('gh: injected summary failure (HTTP 503)',file=sys.stderr);sys.exit(1)
start=time.time()
captured=root.parent/'stdout73'
visible=sum(x.startswith('shipcraft: CI at ') for x in captured.read_text().splitlines()) if captured.exists() else 0
if (mode=='slow-status' and is_status) or (mode=='slow-check' and is_check):time.sleep(2.2)
p=subprocess.run([str(root/'gh73-real'),*args])
if is_status or is_check:
 with (st/'timing73.jsonl').open('a') as f:f.write(json.dumps(dict(start=start,end=time.time(),status=is_status,check=is_check,visible=visible))+'\n')
sys.exit(p.returncode)
PY
  chmod +x "$CB/gh"
  case "$c" in
    control-log-error) mkdir -p .git/shipcraft/runs.jsonl ;;
    control-review|control-merge)
      # These readers use actual stored statuses, not the wait-only injection.
      printf '{}\n' > "$ST/responses.json"
      seed_ok "$HEADSHA" shipcraft/ci; seed_ok "$HEADSHA" shipcraft/review
      ;;
  esac
  case "$c" in
    control-review) run_cmd i73_capture "$PY" "$ACEITE/tools/tmo.py" 60 shipcraft review ;;
    control-merge) pr_outside "$BR"; run_cmd i73_capture "$PY" "$ACEITE/tools/tmo.py" 60 shipcraft merge "$PRN" ;;
    control-ci) run_cmd i73_capture "$PY" "$ACEITE/tools/tmo.py" 60 shipcraft ci --base "$BASE" ;;
    *) run_cmd i73_capture "$PY" "$ACEITE/tools/tmo.py" 90 shipcraft pr --title "Item73" --body "$CW/body.md" ;;
  esac
  # The harness retains combined output; state lines must be on stdout alone.
  chk 'existing outcome and progress state vector' "$PY" - "$c" "$OUT" "$RC" "$ST" "$HEADSHA" "$BR" <<'PY'
import json,pathlib,re,sys
mode,out,rc,st,sha,branch=sys.argv[1:];rc=int(rc);st=pathlib.Path(st);s=pathlib.Path(out).read_text()
stdout=(pathlib.Path(out).parent/'stdout73').read_text();stderr=(pathlib.Path(out).parent/'stderr73').read_text()
assert 'shipcraft: CI at ' not in stderr,stderr
lines=s.splitlines();progress=[x for x in stdout.splitlines() if x.startswith('shipcraft: CI at ')]
control=mode.startswith('control-')
rowsfile=pathlib.Path('.git/shipcraft/runs.jsonl')
rows=[json.loads(x) for x in rowsfile.read_text().splitlines()] if rowsfile.is_file() else []
pr=[r for r in rows if r['layer']=='pr']
error=mode in ('later-gh-error','control-gh-error','control-log-error','later-summary-fails')
timeout=mode in ('first-pending','first-missing','first-empty','first-opaque','checks-dedup','slow-status','slow-check')
failed=mode in ('first-failure','first-error','stop-failure','stop-error','checks-failed','later-review-fails')
assert rc==(2 if error else 1 if timeout or failed else 0),(mode,rc,s)
if not control or mode in ('control-gh-error','control-log-error','control-local','control-off'):
 # The already published branch and created PR survive every later failure.
 import subprocess
 assert subprocess.check_output(['git','ls-remote','origin','refs/heads/'+branch],text=True).split()[0]==sha
 assert any('PR #1' in x for x in lines),s
 if mode!='control-log-error':
  assert len(pr)==1,rows
  assert pr[0]['result']==('error' if error else 'refused' if timeout or failed else 'passed'),pr
  if mode!='later-review-fails':assert pr[0]['code']==('error' if error else 'ci-github-no-status' if timeout else 'ci-github' if failed else ''),pr
 if error and mode!='later-summary-fails':
  assert 'shipcraft: error:' in s,s
  assert not any(r['layer']=='review' for r in rows),rows
  assert not any(json.loads(x).get('kind')=='comment' for x in (st/'writes.log').read_text().splitlines()),s
if not control:
 calls=st/'reviewer.calls.jsonl';reviews=calls.read_text().splitlines() if calls.exists() else []
 expected_reviews=0 if timeout or failed and mode!='later-review-fails' or mode=='later-gh-error' else 1
 assert len(reviews)==expected_reviews,(mode,reviews)
if control:
 assert not progress,(mode,progress)
else:
 names=['zeta suite','alpha/β','third73']
 def vector(state,words=()):return 'shipcraft/ci '+state+''.join('; '+n+' '+w for n,w in zip(names,words))
 expected=[vector('success')]
 if mode.startswith('first-'):expected=[vector({'missing':'no status','empty':'no state','opaque':'queued73'}.get(mode[6:],mode[6:]))]
 if mode=='transition':expected=[vector('pending'),vector('success')]
 if mode=='transition-absence':expected=[vector(x) for x in ('no status','no state','queued73','pending','success')]
 if mode=='dedup-status':expected=[vector('pending'),vector('success')]
 if mode=='checks-words':expected=[vector('success',['missing','pending','unreadable']),vector('success',['green']*3)]
 if mode=='checks-failed':expected=[vector('success',['pending','failed','missing'])]
 if mode=='checks-dedup':expected=[vector('success',['green','unreadable','pending'])]
 if mode.startswith('stop-'):expected=[vector(mode[5:])]
 if mode in ('slow-status','later-gh-error'):expected=[vector('pending')]
 if mode=='slow-check':expected=[vector('success',['green','pending','missing'])]
 parsed=[re.fullmatch(r'shipcraft: CI at ([0-9]+) s: (.*)',x) for x in progress]
 assert all(parsed),progress
 actual=[m[2] for m in parsed]
 assert actual==expected,('missing/incorrect CI state lines',expected,actual,s)
 elapsed=[int(m[1]) for m in parsed];assert elapsed==sorted(elapsed),elapsed
 wait=next(i for i,x in enumerate(lines) if x.startswith('shipcraft: waiting for '))
 assert all(lines.index(x)>wait for x in progress),s
 if mode in ('slow-status','slow-check'):
  ts=[json.loads(x) for x in (st/'timing73.jsonl').read_text().splitlines()]
  duration=ts[-1]['end']-ts[0]['start']
  assert int(duration)<=elapsed[0]<=int(duration)+1,(duration,elapsed)
  assert elapsed[0]>3 if mode=='slow-check' else elapsed[0]>=2,elapsed
 if timeout or failed:
  refusal=next(i for i,x in enumerate(lines) if x.startswith('shipcraft refused:'))
  assert lines.index(progress[-1])<refusal,s
  tail=[x for x in lines[refusal:] if x.strip()]
  assert len(tail)==3 and tail[1].startswith('Why:') and tail[2].startswith('Next:'),tail
 if mode in ('first-failure','first-error','stop-failure','stop-error'):
  assert not any('/check-runs?' in a or '/status?' in a for x in (st/'calls.log').read_text().splitlines() for a in json.loads(x)['argv']),'checks read after terminal CI'
 if mode in ('transition','transition-absence','dedup-status','checks-words','later-review-fails','later-summary-fails','first-success'):
  review=next(i for i,x in enumerate(lines) if x.startswith('shipcraft: review by '))
  assert lines.index(progress[-1])<review,s
 if mode in ('transition','dedup-status','checks-dedup'):
  ts=[json.loads(x) for x in (st/'timing73.jsonl').read_text().splitlines() if json.loads(x)['status']]
  assert len(ts)>=2,ts
  assert ts[1]['visible']>=1,('first line was not visible by the next read',ts)
  assert all(b['start']-a['end']>=1.8 for a,b in zip(ts,ts[1:])),ts
PY
  pass
}
