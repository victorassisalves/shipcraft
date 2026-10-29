# Item 62: public commands only; every Git operation runs in a case-owned project.
item62_cases() {
  local c
  for c in config-valid config-valid-patch config-not-array config-element config-empty-name config-control config-del config-leading config-trailing config-nbsp-leading config-nbsp-trailing config-duplicate config-ci-name config-review-name config-local config-off config-min-absent config-min-old config-min-text config-min-number config-min-future config-empty \
    reader-run reader-status reader-latest reader-two-green reader-failure reader-cancelled reader-null reader-status-failure reader-status-error reader-progress reader-status-pending reader-missing reader-near reader-status-near reader-two-producers reader-mixed-producers reader-run-error reader-status-error-call reader-run-shape reader-status-shape reader-run-count reader-status-count reader-run-element reader-status-element reader-run-json reader-status-json reader-run-bool-count reader-status-bool-count reader-encoding \
    merge-order merge-head-config merge-ci-first merge-review-after merge-waiver merge-green merge-pin-merge merge-pin-squash merge-pin-empty-merge merge-pin-empty-squash merge-race merge-race-squash merge-race-empty merge-race-waiver \
    pr-wait pr-wait-ci pr-head-config pr-failed pr-pending-before-failed pr-timeout pr-timeout-ci pr-timeout-unreadable pr-retry pr-review-fails \
    ci-light ci-base ci-dirty ci-docs ci-open ci-sealed ci-empty ci-bad-base ci-escape-unreadable status status-empty init init-preserve docs docs-migration version; do echo "v1-62.$c"; done
}
i62_commit() { git add -A && git -c core.hooksPath="$CW/no-hooks" commit -qm "$1" >> "$LOG" 2>&1 || fail 'fixture commit'; }
i62_config() {
  H toml-set .shipcraft.toml '' shipcraft_min '"2.18"'
  H toml-set .shipcraft.toml execution ci '"github"'
  H toml-set .shipcraft.toml execution review '"off"'
  H toml-set .shipcraft.toml execution suite_checks '["zeta suite", "alpha/β"]'
}
i62_row() {
  "$PY" - "$1" "$2" "${3:-}" <<'PY'
import json,sys,pathlib
p=pathlib.Path('.git/shipcraft/runs.jsonl'); rs=[json.loads(s) for s in p.read_text().splitlines()] if p.exists() else []
rs=[r for r in rs if (r['code']==sys.argv[2] if sys.argv[1]=='*' else r['layer']==sys.argv[1])]; assert rs,rs
r=rs[-1]; assert r['code']==sys.argv[2],r
if sys.argv[1]=='ci': assert r['suite_in_checks'] is (sys.argv[3]=='true'),r
PY
}
i62_message() {
  "$PY" - "$OUT" <<'PY'
import pathlib,sys
ls=[s for s in pathlib.Path(sys.argv[1]).read_text().splitlines() if s.strip()][-3:]
assert len(ls)==3 and ls[0].startswith('shipcraft refused:') and ls[1].startswith('Why:') and ls[2].startswith('Next:'),ls
PY
}
i62_state() {
  "$PY" - "$ST" "$HEADSHA" "$1" <<'PY'
import json,pathlib,sys
st=pathlib.Path(sys.argv[1]); sha=sys.argv[2]; mode=sys.argv[3]
def run(name='zeta suite',status='completed',conclusion='success',app=1,id=1):
 return dict(id=id,head_sha=sha,name=name,status=status,conclusion=conclusion,app={'id':app},check_suite={'id':app})
runs=[run(),run('alpha/β')]; statuses=[]; overrides={}
if mode in ('run','encoding','green'): pass
elif mode=='status': runs=[run('alpha/β')]; statuses=[('zeta suite','success')]
elif mode=='latest': runs=[run(conclusion='failure',id=1),run(id=2),run('alpha/β')]; statuses=[('zeta suite','success'),('zeta suite','failure')]
elif mode=='two-green': runs.append(run(app=2))
elif mode in ('failure','cancelled','null'): runs[0]['conclusion']={'failure':'failure','cancelled':'cancelled','null':None}[mode]
elif mode in ('status-failure','status-error','status-pending'): runs=runs[1:]; statuses=[('zeta suite',mode.removeprefix('status-'))]
elif mode=='progress': runs[0]['status']='in_progress'; runs[0]['conclusion']=None
elif mode in ('missing','near'): runs=runs[1:]+([run('zeta suite ')] if mode=='near' else [])
elif mode=='status-near': runs=runs[1:]; statuses=[('zeta suite ','success')]
elif mode=='two-producers': runs.append(run(conclusion='failure',app=2))
elif mode=='mixed-producers': statuses=[('zeta suite','failure')]
elif mode in ('run-error','status-error-call'): overrides['check-runs' if mode=='run-error' else 'status']={'error':True}
elif mode.startswith(('run-','status-')):
 endpoint='check-runs' if mode.startswith('run-') else 'status'; field='check_runs' if endpoint=='check-runs' else 'statuses'
 val={'total_count':0,field:[]}
 if mode.endswith('shape'): val={field:[]}
 if mode.endswith('count'): val['total_count']=True if mode.endswith('bool-count') else 1
 if mode.endswith('element'): val={'total_count':1,field:[{'name':'zeta suite','status':7,'conclusion':None} if field=='check_runs' else {'context':'zeta suite','state':False}]}
 overrides[endpoint]={'raw':'{broken JSON'} if mode.endswith('json') else {'json':val}
else: raise AssertionError(mode)
if mode=='near': overrides['check-runs']={'json':{'total_count':len(runs),'check_runs':runs}}
(st/'check-runs.json').write_text(json.dumps(runs)); (st/'responses.json').write_text(json.dumps(overrides))
# Append oldest first; combined status must expose the newest for each context.
with (st/'statuses.jsonl').open('a') as f:
 for i,(name,state) in enumerate(reversed(statuses)):
  f.write(json.dumps(dict(id=900+i,sha=sha,context=name,state=state,description='fixture',t=900+i))+'\n')
PY
}
i62_no_merge() {
  chk 'origin remains on base' eq "$(osha main)" "$BASE"
  chk 'PR remains open' eq "$(H pr-field "$ST" "$PRN" state)" OPEN
  chk 'no merge event' "$PY" - <<'PY'
import json,pathlib
p=pathlib.Path('.git/shipcraft/runs.jsonl')
assert not p.exists() or not any(json.loads(s)['layer']=='merge' for s in p.read_text().splitlines())
PY
}
i62_light_line() { printf '%s\n' 'shipcraft: suite not run here: it runs in the GitHub check(s) zeta suite, alpha/β ([execution] suite_checks)'; }
item62_case() {
  local c="${CASE#v1-62.}" mode expected= method=merge
  EXPECT="item 62: $c"
  v1_start codex
  case "$c" in
    docs|docs-migration|version)
      chk 'spec-linked static contract' "$PY" - "$c" "$ACEITE/../docs/spec.md" "$ACEITE/../docs/github-ci.md" "$(command -v shipcraft)" <<'PY'
import pathlib,re,subprocess,sys
mode,spec,doc,binary=sys.argv[1:]; s=pathlib.Path(spec).read_text(); d=pathlib.Path(doc).read_text()
if mode=='version':
 version=re.search(r'This contract is \*\*([0-9.]+)\*\*',s).group(1)
 p=subprocess.run([binary,'--version'],capture_output=True,text=True); assert p.returncode==0 and re.fullmatch(r'shipcraft '+re.escape(version)+r' \([0-9a-f]{12}\)\n',p.stdout),(version,p.stdout)
elif mode=='docs':
 for phrase in ('suite_checks','2.18','tomllib','pull_request.head.sha','fetch-depth: 0','always()','needs:'):
  assert phrase in d,phrase
else:
 # Stable concepts, not prose snapshots or YAML indentation.
 for phrase in ('suite_checks','--base','before','git show','shipcraft/ci','success','scope','none'):
  assert phrase in d,phrase
 assert re.search(r'first|First',d) and re.search(r'then|Then',d), 'migration order'
 assert re.search(r'exactly one|only one|single publisher',d), 'one publisher'
PY
      pass; return ;;
    init|init-preserve)
      must_accept 'init' cmd shipcraft init
      if [ "$c" = init-preserve ]; then
        printf '\n# retained user comment 62\n' >> .shipcraft.toml
        cp .shipcraft.toml "$CW/config62"
        must_accept 'second init' cmd shipcraft init
        chk 'second init preserves all existing config bytes' cmp .shipcraft.toml "$CW/config62"
      else
        chk 'new comments exactly above execution, no key written' "$PY" - <<'PY'
from pathlib import Path
s=Path('.shipcraft.toml').read_text()
expected='''# where each layer runs: "local" = on this machine, started by shipcraft pr; "github" = in this
# project's GitHub Actions (docs/github-ci.md); "off" = it does not run and shipcraft merge does not
# require it. shipcraft/ci re-checks every commit of the PR and runs the suite at its HEAD,
# unless suite_checks names GitHub checks that run the suite (docs/github-ci.md).
'''
assert expected+'[execution]' in s,s
assert not any(line.lstrip().startswith('suite_checks =') for line in s.splitlines()),s
PY
      fi
      pass; return ;;
  esac
  # Config fixtures are committed without invoking the measured hook.
  NV=1
  must_accept 'init fixture' cmd shipcraft init
  i62_config
  case "$c" in
    config-*)
      mode=${c#config-}
      case "$mode" in
        valid) ;;
        valid-patch) H toml-set .shipcraft.toml '' shipcraft_min '"2.18.0"' ;;
        not-array) H toml-set .shipcraft.toml execution suite_checks '"zeta suite"' ;;
        element) H toml-set .shipcraft.toml execution suite_checks '["zeta suite", 4]' ;;
        empty-name) H toml-set .shipcraft.toml execution suite_checks '[""]' ;;
        control) H toml-set .shipcraft.toml execution suite_checks '["zeta\u0009suite"]' ;;
        del) H toml-set .shipcraft.toml execution suite_checks '["zeta\u007Fsuite"]' ;;
        leading) H toml-set .shipcraft.toml execution suite_checks '[" zeta suite"]' ;;
        trailing) H toml-set .shipcraft.toml execution suite_checks '["zeta suite "]' ;;
        nbsp-leading) H toml-set .shipcraft.toml execution suite_checks '["\u00a0zeta suite"]' ;;
        nbsp-trailing) H toml-set .shipcraft.toml execution suite_checks '["zeta suite\u00a0"]' ;;
        duplicate) H toml-set .shipcraft.toml execution suite_checks '["zeta suite", "zeta suite"]' ;;
        ci-name|review-name) H toml-set .shipcraft.toml execution suite_checks "[\"shipcraft/${mode%-name}\"]" ;;
        local|off) H toml-set .shipcraft.toml execution ci "\"$mode\"" ;;
        min-absent) sed '/^shipcraft_min =/d' .shipcraft.toml > "$CW/config62"; cp "$CW/config62" .shipcraft.toml ;;
        min-old) H toml-set .shipcraft.toml '' shipcraft_min '"2.17"' ;;
        min-text) H toml-set .shipcraft.toml '' shipcraft_min '"two.eighteen"' ;;
        min-number) H toml-set .shipcraft.toml '' shipcraft_min '2.18' ;;
        min-future) H toml-set .shipcraft.toml '' shipcraft_min '"99999.0"'; H toml-set .shipcraft.toml execution suite_checks '[4]' ;;
        empty) H toml-set .shipcraft.toml execution suite_checks '[]'; H toml-set .shipcraft.toml '' shipcraft_min '"0.0"'; H toml-set .shipcraft.toml execution ci '"local"' ;;
      esac
      i62_commit 'chore: config fixture'; remote_setup; BASE=$(head_rev)
      git checkout -qb feature/item62; printf 'code\n' > value62; i62_commit 'feat: code'
      run_cmd TMO 60 shipcraft ci --base "$BASE" --pr
      case "$mode" in
        valid|valid-patch) chk 'valid suite config accepted' rc_zero; chk 'new light path taken' grep -Fxq "$(i62_light_line)" "$OUT"; chk 'true row' i62_row ci '' true ;;
        empty) chk 'empty retains old behavior' rc_zero; chk 'false row' i62_row ci '' false; chk 'no new line' out_hasnt 'suite not run here' ;;
        *) expected=execution-invalid; [ "$mode" != min-future ] || expected=shipcraft-min
          chk 'invalid suite config refuses' eq "$RC" 1
          chk 'three-line refusal' i62_message
          chk 'measured refusal and false field' i62_row ci "$expected" false
          [ "$mode" = min-future ] || chk 'key named' out_has 'suite_checks' ;;
      esac
      pass; return ;;
    status-empty|ci-empty|merge-pin-empty-*|merge-race-empty)
      H toml-set .shipcraft.toml execution suite_checks '[]'
      H toml-set .shipcraft.toml '' shipcraft_min '"0.0"' ;;
  esac
  case "$c" in
    merge-*-squash|merge-race-squash) method=squash ;;
  esac
  H toml-set .shipcraft.toml execution merge "\"$method\""
  case "$c" in pr-*) H toml-set .shipcraft.toml execution review '"local"'; H toml-set .shipcraft.toml execution ci_timeout 3
    case "$c" in pr-wait|pr-wait-ci|pr-retry) H toml-set .shipcraft.toml execution ci_timeout 30 ;; esac ;;
    merge-review-after|merge-waiver|merge-race-waiver) H toml-set .shipcraft.toml execution review '"local"' ;;
  esac
  case "$c" in
    ci-light|ci-dirty|ci-docs)
      H toml-set .shipcraft.toml build command "\"touch $CW/build-ran; exit 19\""
      H toml-set .shipcraft.toml '' check "\"touch $CW/check-ran; exit 18\""
      H toml-set .shipcraft.toml '' test_command "\"touch $CW/suite-ran; echo {junit}; exit 17\""
      ;;
  esac
  i62_commit 'chore: item62 base'; remote_setup; BASE=$(head_rev)
  case "$c" in
    status*)
      run_cmd TMO 60 shipcraft status
      chk 'status accepted' rc_zero
      if [ "$c" = status ]; then chk 'layers names in order' grep -Fq 'ci github (suite in GitHub checks: zeta suite, alpha/β)' "$OUT"
      else chk 'old layers retained' out_has 'ci github'; chk 'no suite layers' out_hasnt 'suite in GitHub checks'; fi
      pass; return ;;
  esac
  git checkout -qb feature/item62
  case "$c" in
    ci-open|ci-sealed)
      # The base owns the new CI policy. A feature config with ordinary suites
      # can open a genuine cycle even on the pre-item binary; no lock is forged.
      H toml-set .shipcraft.toml execution suite_checks '[]'
      H toml-set .shipcraft.toml '' shipcraft_min '"0.0"'
      i62_commit 'chore: ordinary feature suite before RED'
      L stub; L spec_test
      must_accept 'real RED opens lock' cmd shipcraft red
      i62_commit 'test: open RED'
      L implement
      if [ "$c" = ci-sealed ]; then printf '\n# sealed edit\n' >> "$TESTFILE"; fi
      i62_commit 'feat: passing product with cycle still open' ;;
    ci-docs) mkdir -p docs; printf 'documentation\n' > docs/item62.md; i62_commit 'docs: item62' ;;
    *) printf 'product\n' > value62; i62_commit 'feat: item62' ;;
  esac
  HEADSHA=$(head_rev)
  case "$c" in
    ci-base|merge-head-config|pr-head-config)
      H toml-set .shipcraft.toml execution suite_checks '[]'
      H toml-set .shipcraft.toml execution ci '"off"'
      H toml-set .shipcraft.toml execution review '"off"'
      H toml-set .shipcraft.toml '' shipcraft_min '"0.0"'
      i62_commit 'chore: head attempts to waive base checks'; HEADSHA=$(head_rev) ;;
    ci-escape-unreadable)
      printf 'Intent item62\n' > "$CW/body.md"
      pr_outside feature/item62
      gh_quiet pr merge "$PRN" --merge >> "$LOG" 2>&1 || fail 'fixture merge'
      git checkout -q main; git pull -q --no-rebase origin main >> "$LOG" 2>&1 || fail 'fixture pull'
      HEADSHA=$(head_rev) ;;
  esac
  case "$c" in
    ci-*)
      [ "$c" != ci-dirty ] || printf 'dirty\n' >> value62
      if [ "$c" = ci-bad-base ]; then BASE=missing-ref62; fi
      if [ "$c" = ci-escape-unreadable ]; then
        run_cmd env SHIPCRAFT_STUB_FAIL=1 shipcraft ci --base "$BASE"
      else run_cmd TMO 60 shipcraft ci --base "$BASE" --pr; fi
      case "$c" in
        ci-sealed) chk 'commit checks still refuse sealed edit' eq "$RC" 1; chk 'three lines' i62_message; chk 'false before light line' i62_row ci test-changed false ;;
        ci-bad-base) chk 'bad ref errors' eq "$RC" 2; chk 'false on early error' i62_row ci error false ;;
        ci-empty) chk 'ordinary ci succeeds' rc_zero; chk 'ordinary row false' i62_row ci '' false; chk 'no light line' out_hasnt 'suite not run here' ;;
        *) chk 'light CI accepts' rc_zero
          chk 'exact suite line once' "$PY" - "$OUT" "$(i62_light_line)" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(); assert s.splitlines().count(sys.argv[2])==1,s
assert 'docs only: the suites do not run' not in s,s
assert s.endswith('shipcraft: CI ok.\nshipcraft: ci publishes no status; the GitHub workflow publishes shipcraft/ci on HEAD.\n'),s
PY
          chk 'true row' i62_row ci '' true
          chk 'docs_only preserved' "$PY" - "$c" <<'PY'
import json,sys
r=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl') if json.loads(s)['layer']=='ci'][-1]
assert r['docs_only'] is (sys.argv[1]=='ci-docs'),r
PY
          chk 'no build' test ! -e "$CW/build-ran"; chk 'no check' test ! -e "$CW/check-ran"; chk 'no suite' test ! -e "$CW/suite-ran" ;;
      esac
      pass; return ;;
  esac
  # Merge and PR tests use a real pushed branch, a local bare origin and gh fixtures.
  printf 'Intent item62\n' > "$CW/body.md"
  seed_ok "$HEADSHA" shipcraft/ci
  case "$c" in pr-*|merge-waiver|merge-race-waiver) ;; *) seed_ok "$HEADSHA" shipcraft/review ;; esac
  case "$c" in
    reader-*) i62_state "${c#reader-}" ;;
    *) i62_state green ;;
  esac
  case "$c" in
    pr-*)
      case "$c" in
        pr-failed|pr-head-config|pr-pending-before-failed)
          i62_state failure
          if [ "$c" = pr-pending-before-failed ]; then
            "$PY" - "$ST/check-runs.json" <<'PY'
import json,sys
p=sys.argv[1]; a=json.load(open(p)); a[0]['status']='in_progress'; a[0]['conclusion']=None; a[1]['conclusion']='failure'; json.dump(a,open(p,'w'))
PY
          fi ;;
        pr-timeout|pr-timeout-ci|pr-timeout-unreadable)
          i62_state progress
          "$PY" - "$ST/check-runs.json" <<'PY'
import json,sys
p=sys.argv[1]; a=json.load(open(p)); json.dump(a[:1],open(p,'w'))
PY
          if [ "$c" = pr-timeout-unreadable ]; then
            printf '{"check-runs":{"error":true}}\n' > "$ST/responses.json"
          fi
          if [ "$c" = pr-timeout-ci ]; then H seed-status "$ST" "$HEADSHA" shipcraft/ci pending workflow 0; fi ;;
        pr-wait|pr-wait-ci)
          i62_state progress
          if [ "$c" = pr-wait-ci ]; then H seed-status "$ST" "$HEADSHA" shipcraft/ci pending workflow 0; fi
          ( "$PY" -c 'import time; time.sleep(4)'; [ "$(rev_n)" = 0 ] && touch "$CW/review-waited"; i62_state green; seed_ok "$HEADSHA" shipcraft/ci ) & PIDS=$! ;;
        pr-retry)
          "$PY" - "$ST/responses.json" <<'PY'
import json,sys
json.dump({'check-runs':[{'error':True},{'json':{'total_count':0,'check_runs':[]}}]},open(sys.argv[1],'w'))
PY
          # Clear the injected response after a poll; success must then reach the reviewer.
          ( "$PY" -c 'import time; time.sleep(4)'; printf '{}\n' > "$ST/responses.json" ) & PIDS=$! ;;
        pr-review-fails) rev_cfg changes ;;
      esac
      shipcraft_pr
      case "$c" in pr-wait|pr-wait-ci|pr-retry) wait "$PIDS" ;; esac
      case "$c" in
        pr-wait|pr-wait-ci|pr-retry)
          chk 'PR succeeds after all checks green' eq "$RC" 0
          case "$c" in pr-wait|pr-wait-ci) chk 'review absent before green' test -f "$CW/review-waited" ;; esac
          chk 'review ran once' eq "$(rev_n)" 1
          chk 'suite actually polled multiple times' "$PY" - "$ST/calls.log" <<'PY'
import json,sys
calls=[json.loads(s)['argv'] for s in open(sys.argv[1])]; assert sum(any('/check-runs?' in a for a in c) for c in calls)>=4,calls
PY
          ;;
        pr-review-fails) chk 'later review refuses' eq "$RC" 1; chk 'suite gate reached before failed review' eq "$(rev_n)" 1; chk 'suite APIs read' grep -q 'check-runs?' "$ST/calls.log" ;;
        *) chk 'review never runs' eq "$(rev_n)" 0
          expected=ci-github; case "$c" in pr-timeout*) expected=ci-github-no-status ;; esac
          chk 'wait refusal code' i62_row '*'  "$expected"
          case "$c" in
            pr-failed|pr-head-config) chk 'failed name' out_has 'zeta suite' ;;
            pr-pending-before-failed) chk 'failure beats earlier pending' out_has 'alpha/β' ;;
            pr-timeout*) chk 'all not green contexts ordered' "$PY" - "$OUT" "$c" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(); lines=[x for x in s.splitlines() if x.startswith('shipcraft refused:')]; assert lines,s
r=lines[-1]; assert r.index('zeta suite')<r.index('alpha/β'),r
if sys.argv[2]=='pr-timeout-unreadable': assert r.count('unreadable')>=2,r
else: assert 'pending' in r and 'missing' in r,r
if sys.argv[2]=='pr-timeout-ci': assert r.index('shipcraft/ci')<r.index('zeta suite'),r
PY
              ;;
          esac ;;
      esac
      pass; return ;;
  esac
  pr_outside feature/item62
  git checkout -q main
  case "$c" in
    merge-order) i62_state progress; H seed-status "$ST" "$HEADSHA" alpha/β failure workflow 0 ;;
    merge-ci-first) i62_state failure; H seed-status "$ST" "$HEADSHA" shipcraft/ci failure workflow 0 ;;
    merge-review-after) H seed-status "$ST" "$HEADSHA" shipcraft/review failure workflow 0 ;;
    merge-waiver|merge-head-config) i62_state missing ;;
    merge-race*)
      # Construct a distinct, real commit in this case's project, then return to main.
      git checkout -q feature/item62; printf 'moved\n' >> value62; i62_commit 'feat: moved after gate'
      git push -q origin HEAD:refs/heads/future62 >> "$LOG" 2>&1 || fail 'fixture future head'
      head_rev > "$ST/merge-head"; git checkout -q main ;;
  esac
  case "$c" in
    merge-waiver|merge-race-waiver) run_cmd TMO 60 shipcraft merge "$PRN" --no-review 'item62 waiver' ;;
    *) run_cmd TMO 60 shipcraft merge "$PRN" ;;
  esac
  case "$c" in
    reader-run|reader-status|reader-latest|reader-two-green|reader-encoding|merge-green|merge-pin-*)
      chk 'green merges' rc_zero
      if [ "$c" = reader-encoding ]; then
        chk 'exact encoded reader URLs' "$PY" - "$ST/calls.log" "$HEADSHA" <<'PYURL'
import json,sys,urllib.parse
cs=[json.loads(s)['argv'] for s in open(sys.argv[1])]
urls=[a[1] for a in cs if a[0]=='api' and len(a)>1]
for name in ('zeta suite','alpha/β'):
 suffix='/commits/'+sys.argv[2]+'/check-runs?check_name='+urllib.parse.quote(name,safe='')+'&filter=latest&per_page=100'
 assert any(u.endswith(suffix) for u in urls),(suffix,urls)
assert any(u.endswith('/commits/'+sys.argv[2]+'/status?per_page=100') for u in urls),urls
PYURL
      fi
      chk 'merged once' eq "$(nwrites merge)" 1
      chk 'gate SHA pinned with configured method' "$PY" - "$ST/calls.log" "$HEADSHA" "$method" <<'PY'
import json,sys
cs=[json.loads(s)['argv'] for s in open(sys.argv[1])]; a=[a for a in cs if a[:2]==['pr','merge']]; assert len(a)==1,a
assert '--'+sys.argv[3] in a[0],a
assert '--match-head-commit' in a[0] and a[0][a[0].index('--match-head-commit')+1]==sys.argv[2],a
PY
      ;;
    merge-race*)
      chk 'gh race fails as gh failure' eq "$RC" 2
      chk 'message names checked full head' grep -Fq "$HEADSHA" "$OUT"
      i62_no_merge
      [ "$c" != merge-race-waiver ] || chk 'waiver comment remains' eq "$(H text-has "$ST" comment 'item62 waiver')" OK ;;
    *)
      chk 'non-green refuses' eq "$RC" 1
      chk 'three-line refusal' i62_message
      i62_no_merge
      case "$c" in
        merge-review-after) chk 'review checked after green suites' out_has 'review'; chk 'suite reads precede review refusal' grep -q 'check-runs?' "$ST/calls.log" ;;
        merge-ci-first) chk 'shipcraft CI checked first' out_has 'shipcraft/ci' ;;
        *)
          expected=failed
          case "$c" in
            reader-progress|reader-status-pending|merge-order) expected=pending ;;
            reader-missing|reader-near|reader-status-near|merge-waiver|merge-head-config) expected=missing ;;
            reader-*-error|reader-status-error-call|reader-*-shape|reader-*-count|reader-*-element|reader-*-json) expected=unreadable ;;
          esac
          # status-error is a valid failed status; run-error is an API failure.
          [ "$c" != reader-status-error ] || expected=failed
          chk 'exact first non-green reason' "$PY" - "$OUT" "$PRN" "$HEADSHA" "$expected" <<'PYREASON'
import re,sys
from pathlib import Path
s=Path(sys.argv[1]).read_text(); lines=[x for x in s.splitlines() if x.startswith('shipcraft refused:')]
assert len(lines)==1,lines
m=re.fullmatch(r'shipcraft refused: PR #'+sys.argv[2]+r' has no green check zeta suite at its HEAD \(([0-9a-f]{7,39})\): '+sys.argv[4],lines[0])
assert m and sys.argv[3].startswith(m[1]),lines
PYREASON
          chk 'suite Why and Next' "$PY" - "$OUT" "$PRN" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(); assert "Why: merging requires the project's suite green on the latest PR commit" in s,s
assert 'Next: wait for the check or fix what failed' in s and 'shipcraft merge '+sys.argv[2] in s,s
PY
          ;;
      esac ;;
  esac
  pass
}
