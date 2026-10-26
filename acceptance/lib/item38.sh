# Item 38: black-box flow measurements. No implementation sources are read.
item38_cases() {
  local c
  for c in empty missing-log text timeline first-passed missing-steps open two-locks \
    default-base reviews review-errors reuse waiting waiting-missing daily utc \
    stats corrupt corrupt-last readonly offline red-event red-refusal close-event \
    aborted-commit append-failure pr-locks; do echo "v1-38.$c"; done
}
item38_case() {
  local c="${CASE#v1-38.}"
  EXPECT="item 38: $c"
  case "$c" in
    red-event|red-refusal|close-event|aborted-commit|append-failure|pr-locks)
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
        must_accept 'report survives missing log' cmd shipcraft report --json
        chk 'report declares local observation' grep -q '"kind".*"meta"' "$OUT"
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
        close-event|aborted-commit|pr-locks)
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
            [ "$c" != pr-locks ] || shipcraft_pr
          fi ;;
      esac
      must_accept 'event contract' cmd "$PY" - "$c" <<'PY'
import json, pathlib, sys
c=sys.argv[1]
rows=[json.loads(s) for s in pathlib.Path('.git/shipcraft/runs.jsonl').read_text().splitlines()]
assert rows, 'no recorded events'
assert all('lock' in r and isinstance(r['lock'],str) for r in rows), 'every row carries lock'
red=[r for r in rows if r['layer']=='red']
assert len(red)==1, ('exactly one RED event',red)
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
if c=='pr-locks':
    pr=[r for r in rows if r['layer'] in ('pr','ci','review')]
    assert pr, 'no PR measurements'
    assert any(r['layer']=='pr' for r in pr), 'no pr event'
    assert all(r.get('locks')==[red[0]['lock']] for r in pr), pr
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
if c in ('timeline','text','readonly','offline'): cycle()
elif c=='first-passed':
    add('red',80,result='refused'); add('close',90,result='error')
    cycle(); add('red',110); add('close',150); add('merge',220)
elif c=='missing-steps': add('merge',200)
elif c=='open': add('red',100); add('close',140)
elif c=='two-locks': cycle(); cycle('lock-38-B',110,170,250)
elif c=='default-base':
    add('red',100); add('close',140); add('merge',160,base='feature/parent'); add('merge',200)
elif c in ('reviews','review-errors','reuse'):
    cycle()
    if c=='review-errors': add('review',150,result='error',code='error')
    add('review',160,result='passed' if c!='reviews' else 'refused',code='' if c!='reviews' else 'changes-requested')
    if c=='reuse': add('review',170,reused=True)
    else: add('review',180)
elif c=='waiting':
    cycle(); add('ci',150); add('ci',180); add('ci',190,result='refused',code='case-broke'); add('ci',199,'lock-38-B')
elif c=='waiting-missing': cycle(); add('ci',180,result='error')
elif c in ('daily','utc'):
    cycle(start=86300,close=86320,merge=86399)
    cycle('lock-38-B',86350,86390,86400)
    if c=='daily':
        cycle('lock-38-C',86200,86250,86399)
        add('ci',86379); add('ci',86359,'lock-38-C')
        add('review',86330); add('review',86300,'lock-38-C',result='refused',code='changes-requested')
elif c=='stats':
    cycle()
    for layer in ('hook','ci'):
        for i in range(10): add(layer,110+i,secs=i+1,result='refused' if i<2 else 'passed',code='case-broke' if i<2 else '')
    add('hook',130,'',secs=999)
elif c in ('corrupt','corrupt-last'): cycle()
if c!='missing-log':
    lines=[json.dumps(r) for r in rows]
    if c=='corrupt': lines.insert(1,'{broken-json'); lines.insert(3,'[not-a-row]')
    if c=='corrupt-last': lines.append('{"layer":')
    p.write_text('\n'.join(lines)+('\n' if lines else ''))
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
# JSON field spelling is a proposed fixed point pending coordinator resolution.
meta=out[0]; locks={r['lock']:r for r in out if r['kind']=='lock'}; days=[r for r in out if r['kind']=='day']; gaps=[r for r in out if r['kind']=='gap']
assert meta['first_at']==(min(r['at'] for r in rows) if rows else None), meta
assert meta['last_at']==(max(r['at'] for r in rows) if rows else None), meta
if c in ('empty','missing-log'):
    assert len(out)==1, out
    sys.exit()
a=locks['lock-38-A']
def fields(**expected):
    for k,v in expected.items(): assert a[k]==v,(k,v,a)
if c in ('timeline','first-passed','readonly','offline','default-base'):
    fields(red_at=100,close_at=140,merge_at=200,red_to_close=40,close_to_merge=60,red_to_merge=100,state='merged')
if c=='first-passed': assert a['refusals']==1 and a['errors']==1,a
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
        s=a[layer]; assert s['count']==10 and s['p50']==5.5 and s['p90'] in (9,9.1),s
        assert s['refusals']=={'case-broke':2},s
if c in ('daily','utc'):
    d={r['day']:r for r in days}; assert set(d)=={'1970-01-01','1970-01-02'},d
    assert d['1970-01-02']['merged_locks']==1,d
    if c=='daily':
        x=d['1970-01-01']; assert x['merged_locks']==2 and x['red_to_merge_median']==149 and x['waiting_median']==30 and x['first_review_approved_share']==0.5,x
if c in ('corrupt','corrupt-last'):
    assert [g['line'] for g in gaps]==([2,4] if c=='corrupt' else [4]),gaps
    assert a['red_to_merge']==100,a
    assert [r['kind'] for r in out]==sorted([r['kind'] for r in out],key=['meta','lock','day','gap'].index),out
PY
  pass
}
