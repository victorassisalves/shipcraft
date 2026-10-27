# Item 42: squash gate, default-branch evidence and escape detection.
item42_cases() {
  local c
  for c in squash absent merge head-config invalid-string invalid-number invalid-bool \
    missing-ci missing-review no-review no-review-missing-ci merge-fails \
    closed-ok closed-no-ci closed-no-review closed-direct closed-offline \
    escape-bad escape-ok escape-direct escape-offline; do echo "v1-42.$c"; done
}
i42_commit() {
  git add -A && git -c core.hooksPath="$CW/no-hooks" commit -qm "$1" >> "$LOG" 2>&1 || fail 'fixture commit'
}
i42_rows() {
  "$PY" - "$1" "${HEADSHA:-}" <<'PY'
import json,sys,pathlib
p=pathlib.Path('.git/shipcraft/runs.jsonl')
rows=[json.loads(s) for s in p.read_text().splitlines() if s.strip()] if p.exists() else []
merges=[r for r in rows if r.get('layer')=='merge']
if sys.argv[1]=='none':
 assert not merges,merges
 assert not any('method' in r for r in rows),rows
else:
 assert len(merges)==1,merges
 r=merges[0]
 assert r.get('method')==sys.argv[1],r
 assert r['commit']==sys.argv[2] and r['result']=='passed',r
 assert all('method' not in r for r in rows if r['layer']!='merge'),rows
PY
}
i42_fault() {
  mv "$CB/gh" "$CB/gh-real"
  cat > "$CB/gh" <<EOF42
#!/bin/sh
lookup=no
case "\$*" in *commits/*/pulls*) lookup=yes ;; esac
if { [ '$1' = all ] && [ "\$lookup" = yes ]; } || { [ '$1' = merge ] && [ "\$1" = pr ] && [ "\$2" = merge ]; }; then
  echo reached >> '$CW/gh-fault'
  SHIPCRAFT_STUB_FAIL=1 exec '$CB/gh-real' "\$@"
fi
exec '$CB/gh-real' "\$@"
EOF42
  chmod +x "$CB/gh"
}
i42_code() {
  "$PY" - "$1" <<'PY'
import json,sys
rows=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl') if s.strip()]
assert any(r.get('layer')=='ci' and r.get('code')==sys.argv[1] for r in rows),rows
PY
}
item42_case() {
  local c="${CASE#v1-42.}" method=squash
  EXPECT="item 42: $c"
  CFGS='execution|merge|"squash"'
  case "$c" in
    absent) CFGS=''; method=merge ;;
    merge|head-config|escape-ok) CFGS='execution|merge|"merge"'; method=merge ;;
    invalid-string) CFGS='execution|merge|"rebase"' ;;
    invalid-number) CFGS='execution|merge|7' ;;
    invalid-bool) CFGS='execution|merge|true' ;;
  esac
  # Commit invalid base configs through Git, without invoking the measured hook.
  case "$c" in invalid-*) NV=1 ;; esac
  v1_start codex
  pr_main
  git checkout -qb feature/item42
  case "$c" in
    closed-*)
      L stub; L spec_test
      must_accept 'RED creates real lock' cmd shipcraft red
      must_accept 'commit open lock' commit commit_all 'test: item42 RED'
      L implement
      must_accept 'commit closed lock' commit commit_all 'feat: item42 GREEN'
      chk 'fixture lock closed' one_lock_head_state closed ;;
    *)
      printf 'first\n' > item42.txt; i42_commit 'feat: first item42 commit'
      printf 'second\n' >> item42.txt; i42_commit 'feat: second item42 commit' ;;
  esac
  if [ "$c" = head-config ]; then
    H toml-set .shipcraft.toml execution merge '"squash"'
    i42_commit 'chore: head asks for squash'
  fi
  pr_outside feature/item42
  git checkout -q main
  case "$c" in missing-ci|no-review-missing-ci|closed-no-ci|escape-bad) ;; *) seed_ok "$HEADSHA" shipcraft/ci ;; esac
  case "$c" in missing-review|no-review|closed-no-review|escape-bad) ;; *) seed_ok "$HEADSHA" shipcraft/review ;; esac
  mkdir -p .git/shipcraft; : > .git/shipcraft/runs.jsonl
  case "$c" in
    closed-*|escape-*)
      case "$c" in
        *-direct)
          git merge --squash feature/item42 >> "$LOG" 2>&1 || fail 'fixture squash direct push'
          i42_commit 'feat: direct push'
          git push -q origin main >> "$LOG" 2>&1 || fail 'fixture direct push' ;;
        *)
          gh_quiet pr merge "$PRN" --squash >> "$LOG" 2>&1 || fail 'fixture GitHub squash'
          git pull -q --no-rebase origin main >> "$LOG" 2>&1 || fail 'fixture pull' ;;
      esac
      case "$c" in *-offline) i42_fault all ;; esac
      run_cmd TMO 240 shipcraft ci --base "$BASE"
      case "$c" in
        closed-ok) chk 'successful PR evidence admits arriving closed lock' rc_zero ;;
        closed-*)
          chk 'unproven closed lock refuses' rc_nonzero
          msg_check || fail "$MSGERR"
          chk 'closed lock refuses lock-edited' i42_code lock-edited ;;
        escape-*)
          chk 'escape check only warns' rc_zero
          case "$c" in
            escape-bad)
              chk 'warning identifies squashed PR' out_has "#1([^0-9]|$)|$(git rev-parse --short HEAD)"
              chk 'squash escape records actual commit' eq "$(H escape-rows .git/shipcraft/runs.jsonl)" "$(git rev-parse HEAD)" ;;
            escape-offline)
              chk 'first-parent squash lookup reaches network failure' test -s "$CW/gh-fault"
              chk 'escape lookup stops after first failure' eq "$(wc -l < "$CW/gh-fault" | tr -d ' ')" 1
              chk 'unreadable GitHub warns' out_hasi 'warn.*(github|gh|escape|merge)|(github|gh|escape|merge).*warn'
              chk 'unreadable GitHub invents no escapes' eq "$(H escape-rows .git/shipcraft/runs.jsonl)" '' ;;
            *)
              chk 'no PR escape warning' out_hasnt '#1([^0-9]|$)'
              chk 'no fabricated escapes' eq "$(H escape-rows .git/shipcraft/runs.jsonl)" '' ;;
          esac ;;
      esac
      pass; return ;;
    merge-fails) i42_fault merge ;;
  esac
  case "$c" in
    no-review|no-review-missing-ci) run_cmd TMO 120 shipcraft merge "$PRN" --no-review 'item42 waiver' ;;
    *) run_cmd TMO 120 shipcraft merge "$PRN" ;;
  esac
  case "$c" in
    invalid-*|missing-*|no-review-missing-ci|merge-fails)
      chk 'merge refuses' rc_nonzero
      chk 'PR remains open' eq "$(H pr-field "$ST" "$PRN" state)" OPEN
      chk 'base unchanged' eq "$(git --git-dir="$CB/origin.git" rev-parse main)" "$BASE"
      chk 'failure writes no merge event or method' i42_rows none
      if [ "$c" = merge-fails ]; then
        chk 'gate reached gh merge failure' test -s "$CW/gh-fault"
      else
        msg_check || fail "$MSGERR"
        chk 'no merge call' eq "$(nwrites merge)" 0
        case "$c" in invalid-*)
          chk 'invalid execution explains key' out_hasi 'execution.*merge|merge.*(invalid|must|expected)'
          run_cmd TMO 120 shipcraft ci --base "$BASE"
          chk 'CI also refuses invalid merge config' rc_nonzero
          msg_check || fail "$MSGERR"
          chk 'measured config refusal is execution-invalid' i42_code execution-invalid ;;
        esac
      fi ;;
    *)
      chk 'merge succeeds' rc_zero
      git fetch -q origin main || fail 'fixture fetch'
      local oid; oid=$(git rev-parse origin/main)
      chk 'same resulting tree' eq "$(git rev-parse "$oid^{tree}")" "$(git rev-parse "$HEADSHA^{tree}")"
      if [ "$method" = squash ]; then
        chk 'one commit on base' eq "$(git rev-list --count "$BASE..$oid")" 1
        chk 'single parent' eq "$(git show -s --format=%P "$oid")" "$BASE"
        chk 'repository title used' eq "$(git show -s --format=%s "$oid")" 'PR-de-fora (#1)'
        chk 'no title/body overrides' "$PY" - "$ST/calls.log" <<'PY'
import json,sys
calls=[json.loads(s)['argv'] for s in open(sys.argv[1])]
a=[a for a in calls if a[:2]==['pr','merge']]
assert len(a)==1 and '--squash' in a[0],a
assert not any(x in a[0] for x in ('--title','--subject','-t','--body','-b','--body-file')),a
PY
      else
        chk 'merge has base and PR parents' eq "$(git show -s --format=%P "$oid")" "$BASE $HEADSHA"
      fi
      if [ "$c" = no-review ]; then
        chk 'waiver posted' eq "$(H text-has "$ST" comment,pr-edit,merge 'item42 waiver')" OK
        chk 'waiver measured' grep -q 'item42 waiver' .git/shipcraft/runs.jsonl
      fi
      chk 'successful merge records method and PR head' i42_rows "$method" ;;
  esac
  pass
}
