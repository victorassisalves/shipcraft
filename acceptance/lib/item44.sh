# Item 44: CI's public output and status ownership, through public commands only.
item44_cases() {
  local mode path
  for mode in local github off; do
    for path in green green-pr docs empty empty-pr red base-pr; do echo "v1-44.$mode-$path"; done
  done
  echo v1-44.refused v1-44.error v1-44.pr-local v1-44.pr-review-fails
}
i44_line() {
  case "$1" in
    local) echo 'shipcraft: ci publishes no status; shipcraft pr runs CI and publishes shipcraft/ci on HEAD.' ;;
    github) echo 'shipcraft: ci publishes no status; the GitHub workflow publishes shipcraft/ci on HEAD.' ;;
    off) echo 'shipcraft: ci publishes no status; with ci = "off", shipcraft pr publishes shipcraft/ci as off.' ;;
  esac
}
# run_cmd normally merges streams. Preserve stdout and stderr separately here.
i44_exec() { "$@" 2> "$CW/stderr"; }
i44_tail() {
  "$PY" - "$OUT" "$CW/stderr" "$(i44_line "$1")" "${2:-ci}" <<'PY'
import pathlib,sys
out=pathlib.Path(sys.argv[1]).read_bytes(); err=pathlib.Path(sys.argv[2]).read_bytes()
line=sys.argv[3].encode(); pair=b'shipcraft: CI ok.\n'+line+b'\n'
assert out.count(line)==1, ('expected exactly one mode line on stdout',out)
assert out.count(b'shipcraft: ci publishes no status;')==1,out
assert b'ci publishes no status;' not in err,err
if sys.argv[4]=='ci': assert out.endswith(pair),('exact final two lines, no blank line',out)
else:
 assert pair in out,('CI child adjacent lines',out)
 after=out.split(pair,1)[1]
 assert b'shipcraft/ci' in after,('PR own status follows child output',after)
PY
}
i44_no_status() { chk 'direct CI never publishes any status' eq "$(nwrites status)" 0; }
i44_no_line() {
  chk 'no success guidance on stdout or stderr' "$PY" - "$OUT" "$CW/stderr" <<'PY'
import pathlib,sys
for p in sys.argv[1:]:
 b=pathlib.Path(p).read_bytes()
 assert b'ci publishes no status;' not in b,b
 assert b'shipcraft: CI ok.' not in b,b
PY
}
item44_case() {
  local c="${CASE#v1-44.}" mode=local path pr=
  EXPECT="item 44: $c"
  case "$c" in local-*|github-*|off-*) mode=${c%%-*}; path=${c#*-} ;; *) path=$c ;; esac
  v1_start codex
  CFGS="execution|ci|\"$mode\"
execution|review|\"off\""
  [ "$path" != pr-review-fails ] || CFGS='execution|ci|"local"
execution|review|"local"'
  pr_main
  case "$path" in
    empty|empty-pr) ;;
    docs)
      git checkout -qb feature/item44
      printf 'item 44\n' > docs/item44.txt
      i40_commit 'docs: item 44'; pr=--pr ;;
    red)
      git checkout -qb feature/item44
      L stub; L spec_test
      must_accept 'create genuine open RED lock' cmd shipcraft red
      i40_commit 'test: RED item 44' ;;
    *)
      [ "$path" != refused ] || FAILING=1
      pr_feature
      if [ "$path" = base-pr ]; then
        local headmode=off; [ "$mode" != off ] || headmode=github
        H toml-set .shipcraft.toml execution ci "\"$headmode\""
        i40_commit 'chore: head requests different CI mode'
      fi ;;
  esac
  case "$path" in *-pr) pr=--pr ;; esac
  case "$path" in
    pr-local|pr-review-fails)
      [ "$path" != pr-review-fails ] || rev_cfg changes
      git rev-parse HEAD > "$ST/sha"
      run_cmd i44_exec TMO 90 shipcraft pr --title 'Item 44' --body "$CW/body.md"
      if [ "$path" = pr-local ]; then chk 'PR accepted' rc_zero
      else chk 'later review refuses PR' eq "$RC" 1; fi
      chk 'PR publishes CI success on HEAD' eq "$(st_state "$(head_rev)" shipcraft/ci)" success
      chk 'PR publishes CI once' eq "$(H st-ctx-count "$ST" shipcraft/ci)" 1
      chk 'child guidance precedes PR own status output' i44_tail local pr
      pass; return ;;
    error) BASE=item44-ref-that-does-not-exist ;;
  esac
  run_cmd i44_exec TMO 60 shipcraft ci --base "$BASE" $pr
  case "$path" in
    refused|error)
      local want=1; [ "$path" != error ] || want=2
      chk 'exit code unchanged' eq "$RC" "$want"
      i44_no_status; i44_no_line ;;
    *)
      chk 'CI accepted' rc_zero
      i44_no_status
      [ "$path" != docs ] || chk 'docs-only shortcut taken' out_has '^docs only: the suites do not run$'
      chk 'exact mode-specific stdout ending' i44_tail "$mode" ;;
  esac
  pass
}
