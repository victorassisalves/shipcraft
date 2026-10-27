# Item 41: queue admission and PR measurements, through public commands only.
item41_cases() {
  local c
  for c in docs-root docs-tree product protected review review-fails github off github-fails timeout refuses; do
    echo "v1-41.$c"
  done
}
i41_rows() {
  "$PY" - "$1" "$HEAD" <<'PY'
import json,sys
rs=[json.loads(l) for l in open('.git/shipcraft/runs.jsonl') if l.strip()]
rs=[r for r in rs if r.get('layer')=='pr' and r.get('commit')==sys.argv[2]]
assert len(rs)==1,rs
r=rs[0]
assert 'queue_secs' in r,r
v=r['queue_secs']; want=sys.argv[1]
if want=='null': assert v is None,r
else:
 assert type(v) is int and v>=0,r
 assert (v>0 if want=='positive' else v==0),r
PY
}
i41_commit() {
  git add -A && git -c core.hooksPath="$CW/no-hooks" commit -qm "$1" >> "$LOG" 2>&1 || fail 'fixture commit'
}
item41_case() {
  local c="${CASE#v1-41.}" mode=zero
  EXPECT="item 41: $c"
  case "$c" in github|github-fails|off) mode=null ;; esac
  queue_projects 2 'execution|review|"off"' 7 0
  use_proj "$CW/proj/beta" "$CW/stubs/beta"
  # Publish the probe on the base, then make an exclusively documentation diff.
  git checkout -q main
  case "$c" in
    github|github-fails) H toml-set .shipcraft.toml execution ci '"github"' ;;
    off) H toml-set .shipcraft.toml execution ci '"off"' ;;
    review|review-fails|github-fails) H toml-set .shipcraft.toml execution review '"local"' ;;
  esac
  [ "$c" != github-fails ] || H toml-set .shipcraft.toml execution review '"local"'
  PNAME=beta; PSLEEP=0; probe_write
  printf 'base\n' > README.md
  case "$c" in
    protected) H toml-set .shipcraft.toml '' test_globs '["tests/**", "docs/contracts/**"]' ;;
    timeout) H toml-set .shipcraft.toml execution ci_timeout 1 ;;
  esac
  i41_commit 'test: base probe'
  git push -q origin main >> "$LOG" 2>&1 || fail 'fixture push'
  git checkout -q feature/beta
  git reset -q --hard main
  case "$c" in
    product) printf 'value = 41\n' > product.py; mode=positive ;;
    protected) mkdir -p docs/contracts; printf 'contract\n' > docs/contracts/rule.md; mode=positive ;;
    docs-tree) printf 'a,b\n' > docs/table.csv ;;
    *) printf 'changed\n' >> README.md ;;
  esac
  i41_commit 'docs: candidate'
  HEAD=$(git rev-parse HEAD)
  mkdir -p .git/shipcraft; : > .git/shipcraft/runs.jsonl
  case "$c" in
    review-fails) rev_cfg changes timeline="$TLINE" name=beta ;;
    github) H seed-status "$ST" "$HEAD" shipcraft/ci success workflow 0 ;;
    github-fails) H seed-status "$ST" "$HEAD" shipcraft/ci failure workflow 0 ;;
    timeout|refuses)
      # Delay/fail the CI history walk. Admission in the PR parent
      # still reads the real repository. Keep a real git for all other calls.
      local realgit; realgit=$(command -v git)
      cat > "$CB/git" <<GIT
#!/bin/sh
case " \$* " in
  *' rev-list --reverse '*)
    echo injected >> '$CW/child-fault'
    if [ '$c' = timeout ]; then sleep 4; else exit 1; fi ;;
esac
exec '$realgit' "\$@"
GIT
      chmod +x "$CB/git" ;;
  esac
  ( queue_one alfa ) & local holder=$!
  queue_wait_start alfa ci
  queue_one beta
  # Record overlap before joining the holder: bypass must finish while occupied.
  local occupied=0
  [ ! -f "$CW/rc-alfa" ] && occupied=1
  wait "$holder"
  use_proj "$CW/proj/beta" "$CW/stubs/beta"
  OUT="$CW/out-beta"
  case "$c" in
    docs-root|docs-tree)
      chk 'docs CI completes alongside the occupied slot' eq "$occupied" 1
      chk 'PR passed' eq "$(cat "$CW/rc-beta")" 0
      chk 'child still judges docs only' out_has '^docs only: the suites do not run$'
      chk 'suite skipped' eq "$(probe_runs)" 0
      chk 'CI success' eq "$(st_state "$HEAD" shipcraft/ci)" success ;;
    product|protected)
      chk 'PR passed' eq "$(cat "$CW/rc-beta")" 0
      chk 'suite ran' eq "$(probe_runs)" 1
      chk 'child judges full CI' i40_docs_only false ;;
    review|review-fails)
      chk 'review ran once' eq "$(rev_n)" 1
      chk 'review starts after holder CI ends' "$PY" -c "assert float('$(H tl-time "$TLINE" beta revisao start)') >= float('$(H tl-time "$TLINE" alfa ci end)')"
      chk 'CI remains docs only' i40_docs_only true
      chk 'review verdict preserved' eq "$(st_state "$HEAD" shipcraft/review)" "$([ "$c" = review ] && echo success || echo failure)" ;;
    timeout|refuses)
      chk 'CI child did not succeed' ne "$(st_state "$HEAD" shipcraft/ci)" success
      chk 'no review after child failure' eq "$(rev_n)" 0
      chk 'CI history fault exercised' test -s "$CW/child-fault"
      chk 'child error status preserved' eq "$(st_state "$HEAD" shipcraft/ci)" error
      chk 'failure rows preserved' "$PY" - "$c" "$HEAD" <<'FAILROWS'
import json,sys
rows=[json.loads(l) for l in open('.git/shipcraft/runs.jsonl') if l.strip()]
rows=[r for r in rows if r.get('commit')==sys.argv[2]]
ci=[r for r in rows if r['layer']=='ci']; pr=[r for r in rows if r['layer']=='pr']
assert len(ci)==len(pr)==1,rows
code='timed-out' if sys.argv[1]=='timeout' else 'error'
assert (ci[0]['result'],ci[0]['code'])==('error',code),ci
assert ci[0]['docs_only'] is (sys.argv[1]=='timeout'),ci
assert (pr[0]['result'],pr[0]['code'])==('refused','ci-'+code),pr
assert not any(r['layer']=='review' for r in rows),rows
FAILROWS
      ;;
    *) chk 'no local suite' eq "$(probe_runs)" 0 ;;
  esac
  case "$c" in
    product|protected|review|review-fails)
      chk 'waiting layer prints queue position' queue_line_with_number ;;
    *) chk 'CI prints no queue line' no_queue_line ;;
  esac
  chk 'PR row measures only CI queue wait' i41_rows "$mode"
  pass
}
