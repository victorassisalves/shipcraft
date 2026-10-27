# Item 45: failing suite checks, observed through red/ci only.
item45_cases() {
  local phase kind
  for phase in red ci; do
    for kind in stdout both blank silent signal shell-status late-stdout late-stderr unnamed order test-no-report log-write-fails; do
      echo "v1-45.$phase-$kind"
    done
  done
  echo v1-45.ci-log-code
}
i45_exec() { "$@" 2> "$CW/stderr"; }
item45_case() {
  local scenario=${CASE#v1-45.} phase kind root='packages/check root' name='check-contract' check='exec sh check.sh'
  phase=${scenario%%-*}; kind=${scenario#*-}
  EXPECT="item 45: $scenario"
  v1_start
  setup_init
  mkdir -p "$root/tests"
  printf 'def test_ok():\n    assert True\n' > "$root/tests/test_ok.py"
  cat > "$root/check.sh" <<'SH'
printf '\n  src/value.ts(7,3): error TS2322: wrong type  \nwrong last stdout\n'
exit 2
SH
  case "$kind" in
    both) cat > "$root/check.sh" <<'SH'
printf 'stdout arrived first\n'
sleep 0.05
printf '\n  stderr wins  \nwrong last stderr\n' >&2
exit 19
SH
      ;;
    silent) printf 'exit 31\n' > "$root/check.sh" ;;
    blank) printf "printf ' \\n\\t\\n'\nprintf '  \\n' >&2\nexit 31\n" > "$root/check.sh" ;;
    signal) printf 'kill -TERM $$\n' > "$root/check.sh" ;;
    shell-status) check='sh check.sh; exit 29' ;;
    late-stdout|late-stderr)
      cat > "$root/check.sh" <<'SH'
python3 - <<'PY'
import sys
stream = sys.stderr if 'stderr' in sys.argv else sys.stdout
stream.write(' ' * 73728 + '\n \t\n  late diagnostic  \nwrong last line\n')
PY
exit 37
SH
      [ "$kind" != late-stderr ] || perl -pi -e "s/python3 - <</python3 - stderr <</" "$root/check.sh"
      ;;
    unnamed) name="$root" ;;
    test-no-report) printf 'exit 0\n' > "$root/check.sh" ;;
  esac
  cat > "$root/test.sh" <<SH
printf 'tests\\n' >> '$CW/order'
exec pytest -q --junitxml="\$1" tests
SH
  if [ "$kind" = test-no-report ]; then
    cat > "$root/test.sh" <<'SH'
printf 'stdout must stay absent from reason\n'
printf '\n  runner stderr stays  \n' >&2
exit 38
SH
  fi
  "$PY" - "$root" "$name" "$check" "$kind" <<'PY'
import json,sys
root,name,check,kind=sys.argv[1:]
q=json.dumps
with open('.shipcraft.toml','w') as f:
 f.write('shipcraft_min = "1.0"\nlang = "python"\nrunner = "pytest"\n')
 if kind=='order':
  f.write('\n[[suite]]\nname = "earlier"\nroot = "earlier"\ncheck = "exec sh check.sh"\ncommand = "sh test.sh {junit}"\nglobs = ["tests/**"]\n')
 f.write('\n[[suite]]\n')
 if kind!='unnamed': f.write('name = '+q(name)+'\n')
 f.write('root = '+q(root)+'\ncheck = '+q(check)+'\ncommand = "sh test.sh {junit}"\nglobs = ["tests/**"]\n')
PY
  if [ "$kind" = order ]; then
    mkdir -p earlier/tests
    cp "$root/tests/test_ok.py" earlier/tests/
    printf "printf 'earlier check\\n' >> '%s'\n" "$CW/order" > earlier/check.sh
    cp "$root/test.sh" earlier/test.sh
  fi
  i40_commit 'chore: item 45 suite config'
  BASE=$(head_rev)
  printf 'item 45 product change\n' > product.txt
  i40_commit 'feat: item 45 HEAD'
  : > "$CW/order"
  # Later log-write failure must not replace the check verdict (brief rule 4b).
  if [ "$kind" = log-write-fails ]; then
    rm -f .git/shipcraft/runs.jsonl
    mkdir .git/shipcraft/runs.jsonl
  fi
  if [ "$phase" = red ]; then run_cmd i45_exec shipcraft red
  else run_cmd i45_exec shipcraft ci --base "$BASE"; fi
  chk 'refusal exit is 1' eq "$RC" 1
  # msg_check expects merged output; the separate capture also proves forwarding.
  cat "$CW/stderr" >> "$OUT"
  msg_check || fail "refusal without three lines: $MSGERR"
  if [ "$kind" = order ]; then
    chk 'earlier check and tests precede later failing check' eq "$(cat "$CW/order")" "$(printf 'earlier check\ntests')"
  elif [ "$kind" != test-no-report ]; then
    chk 'failed check prevents its tests' test ! -s "$CW/order"
  fi
  if [ "$phase" = ci ] && [ "$kind" != log-write-fails ]; then
    chk 'CI log still records no-report' eq "$(H jsonl-field .git/shipcraft/runs.jsonl ci "$(head_rev)" code | tail -n 1)" '"no-report"'
  fi
  if [ "$kind" = log-code ]; then pass; return; fi
  chk 'reason and guidance contract' "$PY" - "$OUT.last3" "$phase" "$kind" "$name" "$root" "$check" <<'PY'
import pathlib,re,sys
p,phase,kind,name,root,check=sys.argv[1:]
reason,why,nxt=pathlib.Path(p).read_text().splitlines()
if kind=='test-no-report':
 assert 'did not write the JUnit report' in reason,reason
 assert 'runner stderr stays' in reason,reason
 assert 'stdout must stay absent' not in reason,reason
 assert 'the check' not in reason,reason
 sys.exit()
command=' '.join(check.splitlines())
how={'both':'exited with 19','silent':'exited with 31','blank':'exited with 31','shell-status':'exited with 29','late-stdout':'exited with 37','late-stderr':'exited with 37'}.get(kind,'exited with 2')
line={'both':'stderr wins','late-stdout':'late diagnostic','late-stderr':'late diagnostic'}.get(kind,'src/value.ts(7,3): error TS2322: wrong type')
if kind in ('silent','blank','signal'): line=''
prefix=f'shipcraft refused: suite {name}: the check `{command}` failed ('
if kind=='signal':
 assert re.fullmatch(re.escape(prefix)+r'(?:signal[^)]*(?:15|TERM)[^)]*|(?:killed|terminated) by signal[^)]*(?:15|TERM)[^)]*)\)',reason),reason
else:
 expected=prefix+how+')'+(': '+line if line else '')
 assert reason==expected,(reason,expected)
assert 'did not write the JUnit report' not in reason,reason
assert why.startswith('Why:') and 'check' in why and re.search(r'(only|before|after)',why),why
assert nxt.startswith('Next:') and root in nxt and f'`{command}`' in nxt,nxt
assert 'fix' in nxt and re.search(r'(code|stub)',nxt) and re.search(r'(tool|dependenc)',nxt),nxt
if phase=='red': assert nxt.endswith('then run `shipcraft red` again'),nxt
PY
  if [ "$kind" = stdout ] || [ "$kind" = both ]; then
    chk 'check output forwarded to stderr' grep -E -q 'wrong last stdout|stdout arrived first' "$CW/stderr"
  fi
  pass
}
