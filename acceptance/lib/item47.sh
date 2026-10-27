# Item 47: execution values at the existing config-reader boundaries.
item47_cases() {
  local c
  for c in ci-string ci-number ci-bool ci-uppercase ci-space ci-array ci-inline review-string review-number hook-ci hook-review red-ci red-review order-ci order-review order-merge malformed timeout table head-valid-tree-invalid defaults review-github-ci review-github-pr log-write-fails; do echo "v1-47.$c"; done
}
i47_code() {
  "$PY" - "$1" "$2" <<'PY'
import json,sys
rows=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl') if s.strip()]
assert any(r.get('layer')==sys.argv[1] and r.get('code')==sys.argv[2] for r in rows),rows
PY
}
item47_case() {
  local c=${CASE#v1-47.} key=ci value='"foo"' phase=ci code=execution-invalid
  EXPECT="item 47: $c"
  v1_start codex
  if [ "$c" = review-github-pr ]; then
    NV=1; CFGS='execution|review|"github"'
    pr_main; pr_feature
    shipcraft_pr
    chk 'reserved review refuses' rc_nonzero
    msg_check || fail "$MSGERR"
    chk 'reserved review keeps today text' last3_has 'not available.*yet'
    chk 'nothing published' eq "$(nwrites)" 0
    pass; return
  fi
  setup_init
  cp .shipcraft.toml "$CW/valid"
  BASE=$(head_rev)
  case "$c" in
    ci-array) value='["local"]' ;; ci-inline) value="'foo' # exact TOML literal" ;;
    ci-number) value=7 ;; ci-bool) value=true ;; ci-uppercase) value='"LOCAL"' ;; ci-space) value='"off "' ;;
    review-string|review-number|hook-review|red-review) key=review; [ "$c" != review-number ] || value=1 ;;
    review-github-*) key=review; value='"github"' ;;
    order-review) key=review ;; order-merge) key=merge; value='"rebase"' ;;
    malformed|timeout|table) code=config-invalid ;;
  esac
  H toml-set .shipcraft.toml execution "$key" "$value"
  case "$c" in
    order-ci) H toml-set .shipcraft.toml execution review '"bad-review"'; H toml-set .shipcraft.toml execution merge '"rebase"' ;;
    order-review) H toml-set .shipcraft.toml execution merge '"rebase"' ;;
    malformed) printf '\ninvalid [\n' >> .shipcraft.toml ;;
    timeout) H toml-set .shipcraft.toml execution ci_timeout '"bad"' ;;
    table) cp "$CW/valid" .shipcraft.toml; "$PY" - <<'PY'
from pathlib import Path
p=Path('.shipcraft.toml'); s=p.read_text(); start=s.find('[execution]'); end=s.find('\n[',start+1); s=s[:start]+s[end+1:] if end>=0 else s[:start]; p.write_text('execution = 7\n'+s)
PY
      ;;
    head-valid-tree-invalid) cp .shipcraft.toml "$CW/invalid"; cp "$CW/valid" .shipcraft.toml; printf '\n# valid HEAD snapshot\n' >> .shipcraft.toml ;;
    defaults) "$PY" - <<'PY'
from pathlib import Path
p=Path('.shipcraft.toml'); s=p.read_text()
import re
s=re.sub(r'(?m)^(ci|review|merge)\s*=.*\n','',s); p.write_text(s)
PY
      ;;
  esac
  case "$c" in
    hook-*)
      phase=hook
      chk 'no open lock' no_lock
      git add .shipcraft.toml
      cp "$CW/valid" .shipcraft.toml
      run_cmd commit_index 'chore: staged invalid layer' ;;
    red-*) phase=red; run_cmd shipcraft red ;;
    *)
      i42_commit 'chore: item 47 config'
      if [ "$c" = head-valid-tree-invalid ]; then cp "$CW/invalid" .shipcraft.toml; else cp "$CW/valid" .shipcraft.toml; fi
      if [ "$c" = log-write-fails ]; then rm -f .git/shipcraft/runs.jsonl; mkdir .git/shipcraft/runs.jsonl; fi
      run_cmd shipcraft ci --base "$BASE" ;;
  esac
  case "$c" in defaults|review-github-ci|head-valid-tree-invalid) chk 'existing accepted behavior' rc_zero; pass; return ;; esac
  chk 'config refuses' rc_nonzero
  msg_check || fail "$MSGERR"
  chk 'three refusal lines' "$PY" - "$OUT.last3" <<'PYMSG'
import pathlib,sys
lines=pathlib.Path(sys.argv[1]).read_text().splitlines()
assert all(s.startswith(p) for s,p in zip(lines,('shipcraft refused:', 'Why:', 'Next:'))),lines
PYMSG
  if [ "$code" = execution-invalid ]; then
    chk 'reason names exact key and rejected value' "$PY" - "$OUT.last3" "$key" "$value" <<'PY'
import pathlib,re,sys
line=pathlib.Path(sys.argv[1]).read_text().splitlines()[0]
assert re.search(r'\b'+re.escape(sys.argv[2])+r'\b',line),line
value='foo' if sys.argv[3].startswith("'foo'") else ('local' if sys.argv[3].startswith('[') else sys.argv[3].strip('"'))
assert value in line,(value,line)
if sys.argv[2]=='ci': assert 'bad-review' not in line and 'rebase' not in line,line
if sys.argv[2]=='review': assert 'rebase' not in line,line
PY
  elif [ "$code" = review-github ]; then
    chk 'reserved review keeps today text' last3_has 'not available.*yet'
  fi
  case "$phase:$c" in ci:log-write-fails|red:*|pr:*) ;; *) chk 'measured refusal code' i47_code "$phase" "$code" ;; esac
  pass
}
