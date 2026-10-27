# Item 38: black-box flow measurements. No implementation sources are read.
item38_cases() {
  local c
  for c in empty missing-log text timeline first-passed missing-steps open two-locks \
    default-base reviews review-errors reuse waiting waiting-missing daily utc \
    stats corrupt corrupt-last readonly offline red-event red-refusal close-event \
    aborted-commit append-failure pr-locks pr-locks-many many-locks ignored-escape \
    blank-lines bom crlf bom-crlf nonobject escape-only blank-only default-other \
    pr-publication-passed pr-publication-refused ci-config-locks ci-config-locks-many; do echo "v1-38.$c"; done
}
i38_attribution_failure() {
  local c="${CASE#v1-38.}"
  EXPECT="item 38 failure attribution: $c"
  v1_start codex
  CFGS='execution|review|"off"'
  pr_main
  git checkout -qb feature/flow38-failure
  L stub; L spec_test
  must_accept 'RED for attributed PR' cmd shipcraft red
  must_accept 'commit attributed RED' commit commit_all 'test: attributed RED'
  L implement
  must_accept 'commit attributed GREEN' commit commit_all 'feat: attributed GREEN'
  case "$c" in
    pr-publication-refused|ci-config-locks-many)
      L shout_stub; L shout_test
      must_accept 'second attributed RED' cmd shipcraft red
      must_accept 'commit second attributed RED' commit commit_all 'test: second attributed RED'
      L shout_impl
      must_accept 'commit second attributed GREEN' commit commit_all 'feat: second attributed GREEN' ;;
  esac
  lock_files_head > "$CW/expected-locks"
  case "$c" in
    ci-config-locks|ci-config-locks-many)
      printf 'shipcraft_min = [\n' > .shipcraft.toml
      git add .shipcraft.toml
      must_accept 'fixture commits invalid HEAD config' commit git -c core.hooksPath="$CW/no-hooks" commit -qm 'test: invalid PR config'
      pr_outside feature/flow38-failure
      cp .git/shipcraft/runs.jsonl "$CW/events-before"
      run_cmd env -u SHIPCRAFT_PR_LOCKS shipcraft ci --base "$BASE" --pr
      chk 'invalid HEAD config makes PR CI fail' rc_nonzero
      chk 'failed CI keeps PR lock attribution before config validation' "$PY" - "$CW/events-before" "$CW/expected-locks" "$CW/ci-event.json" <<'CIFAIL38'
import json,sys
from pathlib import Path
before=Path(sys.argv[1]).read_bytes();after=Path('.git/shipcraft/runs.jsonl').read_bytes()
assert after.startswith(before), 'CI rewrote recorded history'
rows=[json.loads(s) for s in after[len(before):].splitlines() if s.strip()]
assert len(rows)==1 and rows[0]['layer']=='ci', ('expected one failed CI event',rows)
r=rows[0]
assert r['result'] in ('refused','error'),r
expected=sorted(Path(s).stem for s in Path(sys.argv[2]).read_text().splitlines())
assert expected and sorted(r.get('locks',[]))==expected, ('config validation lost the PR locks',expected,r)
Path(sys.argv[3]).write_text(json.dumps(r))
CIFAIL38
      must_accept 'report reads the refusal even with invalid config' cmd shipcraft report --json
      chk 'report counts failed CI for every changed lock' "$PY" - "$OUT" "$CW/ci-event.json" <<'CIREPORT38'
import json,sys
rows=[json.loads(s) for s in open(sys.argv[1])]
event=json.load(open(sys.argv[2]))
locks={r['lock']:r for r in rows if r['kind']=='lock'}
for lock in event['locks']:
    r=locks[lock]
    assert r['ci']['count']==1,(lock,r)
    if event['result']=='error': assert r['errors']==1,(lock,r)
    else:
        assert event['code'] and r['refusals'].get(event['code'])==1,(lock,r)
        assert r['ci']['refusals'].get(event['code'])==1,(lock,r)
CIREPORT38
      pass; return ;;
    pr-publication-refused)
      L wrong_impl
      git add textutil.py
      must_accept 'fixture commits regressed product for refused CI' commit git -c core.hooksPath="$CW/no-hooks" commit -qm 'test: refused PR CI' ;;
  esac
  cp .git/shipcraft/runs.jsonl "$CW/events-before"
  # Wrap only this case's offline gh stub. Its existing failure switch supplies
  # the failure; every other gh operation keeps the normal stub behavior.
  mv "$CB/gh" "$CB/gh-real"
  "$PY" - "$CB/gh" "$PY" <<'GH38'
from pathlib import Path
import sys
p=Path(sys.argv[1])
p.write_text('#!'+sys.argv[2]+'\n'+'''import json,os,re,sys
from pathlib import Path
args=sys.argv[1:]
comments=bool(args and args[0]=='api' and any(re.search(r'/issues/\\d+/comments$',a) for a in args))
post=any(a in ('-f','-F','--input') for a in args) or any(args[i] in ('-X','--method') and args[i+1]=='POST' for i in range(len(args)-1))
publication=args[:2]==['pr','comment'] or (comments and post)
env=os.environ.copy()
if publication:
    Path(__file__).with_name('publication-failed.json').write_text(json.dumps(args))
    env['SHIPCRAFT_STUB_FAIL']='1'
real=Path(__file__).with_name('gh-real')
os.execve(str(real),[str(real),*args],env)
''')
p.chmod(0o755)
GH38
  shipcraft_pr
  chk 'publication failure makes PR command fail' rc_nonzero
  chk 'summary publication actually reached injected gh failure' test -f "$CB/publication-failed.json"
  chk 'PR existed before publication failed' "$PY" - "$ST/prs.json" <<'PREXISTS38'
import json,sys
assert len(json.load(open(sys.argv[1])))==1, 'PR was not created'
PREXISTS38
  chk 'failed PR still records one attributed error event' "$PY" - "$CW/events-before" "$CW/expected-locks" "$c" <<'PRFAIL38'
import json,sys
from pathlib import Path
before=Path(sys.argv[1]).read_bytes();after=Path('.git/shipcraft/runs.jsonl').read_bytes()
assert after.startswith(before), 'PR rewrote recorded history'
rows=[json.loads(s) for s in after[len(before):].splitlines() if s.strip()]
ci=[r for r in rows if r['layer']=='ci']
outcome='refused' if sys.argv[3]=='pr-publication-refused' else 'passed'
assert len(ci)==1 and ci[0]['result']==outcome, ('CI did not reach the intended outcome',ci)
pr=[r for r in rows if r['layer']=='pr']
assert len(pr)==1, ('failed publication lost or duplicated the PR event',pr)
expected=sorted(Path(s).stem for s in Path(sys.argv[2]).read_text().splitlines())
assert expected and sorted(pr[0]['locks'])==expected, (expected,pr)
assert sorted(ci[0]['locks'])==expected,(expected,ci)
assert pr[0]['result']=='error', ('publication error was not recorded as error',pr)
PRFAIL38
  pass
}
item38_case() {
  local c="${CASE#v1-38.}"
  case "$c" in pr-publication-passed|pr-publication-refused|ci-config-locks|ci-config-locks-many) i38_attribution_failure; return ;; esac
  EXPECT="item 38: $c"
  case "$c" in
    red-event|red-refusal|close-event|aborted-commit|append-failure|pr-locks|pr-locks-many)
      v1_start codex
      pr_main
      git checkout -qb feature/flow38
      mkdir -p .git/shipcraft
      : > .git/shipcraft/runs.jsonl
      L stub; L spec_test
      if [ "$c" = append-failure ]; then
        rm .git/shipcraft/runs.jsonl
        mkdir .git/shipcraft/runs.jsonl
        must_accept 'RED survives failed append' cmd shipcraft red
        rmdir .git/shipcraft/runs.jsonl
        must_accept 'commit RED with lost event' commit commit_all 'test: RED with lost append'
        L implement
        must_accept 'commit GREEN after lost RED event' commit commit_all 'feat: close observed locally'
        must_accept 'report survives lost append' cmd shipcraft report --json
        chk 'lost RED is unobserved, never a fabricated gap' "$PY" - "$OUT" <<'PYLOST'
import json,sys
rows=[json.loads(s) for s in open(sys.argv[1])]
assert not [r for r in rows if r['kind']=='gap'], rows
locks=[r for r in rows if r['kind']=='lock']
assert len(locks)==1, rows
r=locks[0]
assert r['red_at'] is None and r['close_at'] is not None and r['red_to_close'] is None, r
assert 'red' in r['unobserved'], r
PYLOST
        pass; return
      fi
      if [ "$c" = red-refusal ]; then
        L implement
        run_cmd shipcraft red
        chk 'already-green RED refuses' rc_nonzero
      else
        must_accept 'RED writes lock' cmd shipcraft red
      fi
      case "$c" in
        close-event|aborted-commit|pr-locks|pr-locks-many)
          must_accept 'commit RED' commit commit_all 'test: flow38 RED'
          L implement
          if [ "$c" = aborted-commit ]; then
            # Abort after the installed Shipcraft commit-msg check has returned.
            printf '#!/bin/sh\nshipcraft check --commit-msg "$1" || exit $?\nexit 1\n' > .git/hooks/commit-msg
            chmod +x .git/hooks/commit-msg
            run_cmd commit_all 'feat: aborted GREEN'
            chk 'later hook aborts commit' rc_nonzero
          else
            must_accept 'commit GREEN' commit commit_all 'feat: flow38 GREEN'
            must_accept 'explicit close is idempotent' cmd shipcraft close
            if [ "$c" = pr-locks-many ]; then
              L shout_stub; L shout_test
              must_accept 'second RED on the same branch' cmd shipcraft red
              must_accept 'commit second RED' commit commit_all 'test: second flow38 lock'
              L shout_impl
              must_accept 'commit second GREEN' commit commit_all 'feat: second flow38 lock'
            fi
            case "$c" in pr-locks|pr-locks-many) shipcraft_pr; chk 'PR layers pass' rc_zero ;; esac
          fi ;;
      esac
      must_accept 'event contract' cmd "$PY" - "$c" <<'PY'
import json, pathlib, sys
c=sys.argv[1]
rows=[json.loads(s) for s in pathlib.Path('.git/shipcraft/runs.jsonl').read_text().splitlines()]
assert rows, 'no recorded events'
assert all('lock' in r and isinstance(r['lock'],str) for r in rows), 'every row carries lock'
red=[r for r in rows if r['layer']=='red']
assert len(red)==(2 if c=='pr-locks-many' else 1), ('one RED event per step',red)
if c=='red-refusal':
    assert red[0]['result']=='refused', red
else:
    assert red[0]['result']=='passed' and red[0]['lock'], red
    locks=[p.stem for p in pathlib.Path('.shipcraft/locks').glob('*.json')]
    assert red[0]['lock'] in locks, (red,locks)
close=[r for r in rows if r['layer']=='close' and r['result']=='passed']
if c=='close-event':
    assert len(close)==1 and close[0]['lock']==red[0]['lock'], close
    assert close[0]['commit']==__import__('subprocess').check_output(['git','rev-parse','HEAD'],text=True).strip(), close
if c=='aborted-commit': assert not close, ('aborted commit recorded a close',close)
if c in ('pr-locks','pr-locks-many'):
    pr=[r for r in rows if r['layer'] in ('pr','ci','review')]
    assert pr, 'no PR measurements'
    assert any(r['layer']=='pr' for r in pr), 'no pr event'
    expected={r['lock'] for r in red}
    assert all(isinstance(r.get('locks'),list) and len(r['locks'])==len(expected) and set(r['locks'])==expected for r in pr), pr
PY
      pass; return ;;
  esac
  must_accept 'report black-box contract' cmd "$PY" - "$c" "$(command -v shipcraft)" "$CW" <<'PY'
import json, os, pathlib, subprocess, sys
c,binary,cw=sys.argv[1:]
p=pathlib.Path('.git/shipcraft/runs.jsonl'); p.parent.mkdir(parents=True,exist_ok=True)
rows=[]
def add(layer,at,lock='lock-38-A',result='passed',**extra):
    r=dict(layer=layer,at=at,lock=lock,result=result,code='',secs=1,branch='same/reused',commit='f'*40,reason='')
    if layer in ('pr','merge','ci','review'): r.update(locks=[lock] if lock else [],base='main',default_branch='main')
    r.update(extra); rows.append(r)
def cycle(lock='lock-38-A',start=100,close=140,merge=200):
    add('red',start,lock); add('close',close,lock); add('merge',merge,lock)
if c in ('timeline','text','readonly','offline','blank-lines','bom','crlf','bom-crlf','nonobject','ignored-escape'): cycle()
elif c=='first-passed':
    add('red',80,result='refused',code='red-already-green'); add('close',90,result='error')
    add('red',110); add('close',150); add('merge',220); cycle()
elif c=='missing-steps': add('merge',200)
elif c=='open': add('red',100); add('close',140)
elif c=='two-locks': cycle(); cycle('lock-38-B',110,170,250)
elif c=='many-locks':
    add('red',100); add('close',140); add('red',120,'lock-38-B'); add('close',170,'lock-38-B')
    add('pr',180,'',locks=['lock-38-A','lock-38-B'])
    add('merge',200,'',locks=['lock-38-A','lock-38-B'])
elif c in ('default-base','default-other'):
    add('red',100); add('close',140)
    if c=='default-base': add('merge',160,base='feature/parent'); add('merge',200)
    else:
        add('merge',160,base='main',default_branch='trunk')
        add('merge',200,base='trunk',default_branch='trunk')
elif c in ('reviews','review-errors','reuse'):
    cycle()
    if c=='review-errors': add('review',150,result='error',code='error')
    if c=='reuse': add('review',150,result='refused',code='changes-requested',reused=True)
    add('review',160,result='passed' if c!='reviews' else 'refused',code='' if c!='reviews' else 'changes-requested')
    if c!='reuse': add('review',180)
elif c=='waiting':
    cycle(); add('ci',150); add('ci',180); add('ci',190,result='refused',code='case-broke'); add('ci',199,'lock-38-B'); add('ci',250)
elif c=='waiting-missing': cycle(); add('ci',180,result='error')
elif c in ('daily','utc'):
    cycle(start=86300,close=86320,merge=86399)
    cycle('lock-38-B',86350,86390,86400)
    if c=='daily':
        cycle('lock-38-C',86200,86250,86399)
        add('merge',86399,'lock-38-D')  # No first review or earlier local steps.
        add('ci',86379); add('ci',86359,'lock-38-C')
        add('review',86330); add('review',86300,'lock-38-C',result='refused',code='changes-requested')
elif c=='stats':
    cycle()
    for layer in ('hook','ci'):
        for i in range(10): add(layer,110+i,secs=i+1,result='refused' if i<2 else 'passed',code='case-broke' if i<2 else '')
    add('hook',130,'',secs=999)
elif c in ('corrupt','corrupt-last'): cycle()
if c in ('ignored-escape','escape-only'):
    add('red',1,escape=True); add('merge',300,escape=True)
    add('merge',400,'escape-only',escape=True)
if c!='missing-log':
    lines=[json.dumps(r) for r in rows]
    if c=='corrupt': lines.insert(1,'{broken-json'); lines.insert(3,'[not-a-row]')
    if c=='corrupt-last': lines.append('{"layer":')
    if c=='nonobject': lines.insert(1,'[]'); lines.insert(3,'null')
    if c in ('blank-lines','blank-only'): lines.insert(0,''); lines.insert(2,'  \t'); lines.append('')
    newline='\r\n' if c in ('crlf','bom-crlf') else '\n'
    content=newline.join(lines)+(newline if lines else '')
    if c in ('bom','bom-crlf'): content='\ufeff'+content
    p.write_bytes(content.encode())
before=p.read_bytes() if p.exists() else None
# Trap external command use: report must need neither Git history nor a service.
env=os.environ.copy(); env['TZ']='Pacific/Honolulu'
if c=='offline':
    trap=pathlib.Path(cw)/'forbidden'; trap.mkdir()
    for tool in ('git','gh','codex','claude','gemini'):
        q=trap/tool; q.write_text('#!/bin/sh\necho forbidden >> "'+str(pathlib.Path(cw)/'calls')+'"\nexit 97\n'); q.chmod(0o755)
    env['PATH']=str(trap)+os.pathsep+env['PATH']
a=subprocess.run([binary,'report']+([] if c=='text' else ['--json']),capture_output=True,text=True,env=env)
print(a.stdout); print(a.stderr,file=sys.stderr)
assert a.returncode==0, ('report must never refuse',a.returncode)
assert (p.read_bytes() if p.exists() else None)==before, 'report changed log'
assert not (pathlib.Path(cw)/'calls').exists(), 'report called external service/history'
if c=='text':
    first=a.stdout.splitlines()[0].lower()
    assert 'machine' in first or 'local' in first, first
    assert '100' in first and '200' in first, first
    assert 'lock-38-A' in a.stdout, 'no per-lock row'
    sys.exit()
out=[json.loads(s) for s in a.stdout.splitlines()]
assert out and out[0].get('kind')=='meta', 'meta must be first'
assert all(isinstance(r,dict) and r.get('kind') in ('meta','lock','day','gap') for r in out), out
# JSON field spelling follows the fixed readings in docs/spec.md (44318a0).
meta=out[0]; locks={r['lock']:r for r in out if r['kind']=='lock'}; days=[r for r in out if r['kind']=='day']; gaps=[r for r in out if r['kind']=='gap']
observed=[r for r in rows if not r.get('escape',False)]
assert meta['first_at']==(min(r['at'] for r in observed) if observed else None), meta
assert meta['last_at']==(max(r['at'] for r in observed) if observed else None), meta
if c in ('empty','missing-log','escape-only','blank-only'):
    assert len(out)==1, out
    sys.exit()
a=locks['lock-38-A']
def fields(**expected):
    for k,v in expected.items(): assert a[k]==v,(k,v,a)
if c in ('timeline','first-passed','readonly','offline','default-base','default-other'):
    fields(red_at=100,close_at=140,merge_at=200,red_to_close=40,close_to_merge=60,red_to_merge=100,state='merged')
if c=='first-passed': assert a['refusals']=={'red-already-green':1} and a['errors']==1,a
if c=='missing-steps':
    fields(red_at=None,close_at=None,merge_at=200,red_to_close=None,close_to_merge=None,red_to_merge=None,state='merged')
    assert set(a['unobserved'])=={'red','close'},a
if c=='open': fields(merge_at=None,red_to_close=40,close_to_merge=None,red_to_merge=None,state='open'); assert not days,days
if c=='two-locks':
    assert set(locks)=={'lock-38-A','lock-38-B'},locks
    assert locks['lock-38-B']['red_to_merge']==140,locks
if c in ('reviews','review-errors','reuse'):
    expected={'passed':1,'refused':1,'error':0} if c=='reviews' else {'passed':2 if c=='review-errors' else 1,'refused':0,'error':1 if c=='review-errors' else 0}
    assert all(a['reviews'][k]==v for k,v in expected.items()),a
    assert a['first_review_approved'] is (c!='reviews'),a
if c=='waiting': fields(waiting=20)
if c=='waiting-missing': fields(waiting=None)
if c=='stats':
    for layer in ('hook','ci'):
        s=a[layer]; assert s['count']==10 and s['p50']==5.5 and s['p90']==9,s
        assert s['refusals']=={'case-broke':2},s
if c in ('daily','utc'):
    d={r['day']:r for r in days}; assert set(d)=={'1970-01-01','1970-01-02'},d
    assert d['1970-01-02']['merged_locks']==1,d
    assert d['1970-01-02']['first_review_approved_share'] is None,d
    if c=='daily':
        x=d['1970-01-01']; assert x['merged_locks']==3 and x['red_to_merge_median']==149 and x['waiting_median']==30 and x['first_review_approved_share']==0.5,x
if c in ('corrupt','corrupt-last','nonobject'):
    assert [g['line'] for g in gaps]==([2,4] if c in ('corrupt','nonobject') else [4]),gaps
    assert all(isinstance(g.get('reason'),str) and g['reason'] for g in gaps),gaps
    assert a['red_to_merge']==100,a
    assert [r['kind'] for r in out]==sorted([r['kind'] for r in out],key=['meta','lock','day','gap'].index),out
if c in ('blank-lines','bom','crlf','bom-crlf','ignored-escape'):
    fields(red_at=100,close_at=140,merge_at=200,red_to_merge=100)
    assert not gaps and set(locks)=={'lock-38-A'},out
if c=='many-locks':
    assert set(locks)=={'lock-38-A','lock-38-B'},locks
    assert locks['lock-38-A']['merge_at']==locks['lock-38-B']['merge_at']==200,locks
    assert locks['lock-38-A']['red_to_merge']==100 and locks['lock-38-B']['red_to_merge']==80,locks
    assert len(days)==1 and days[0]['merged_locks']==2,days
PY
  pass
}
