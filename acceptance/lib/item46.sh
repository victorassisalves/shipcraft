# Item 46: public commands and sealed lock fixtures; no implementation reader.
item46_langs() { echo core; }
item46_cases() {
  local c
  for c in draken lists unchanged drops-pass-command without-lock uncommitted two-open drops-command rename-command passes-command error-command write-fails log-fails log-refusal other-check build-fails no-report bad-seal bad-format report-zero report-count drops-hook drops-ci mixed-product mixed-config mixed-hook mixed-rename accepted later-test passes-hook merge; do echo "v1-46.$c"; done
}
i46_test() {
  cat > tests/test_repair.py <<PY
from textutil import slugify

def test_fixture():
    fixture = '$1'
    assert fixture != 'invalid', 'database check rejected fixture'
    assert slugify(fixture) == 'a-b'

def test_keep():
    assert True
PY
}
i46_start() {
  v1_start codex; setup_init; L stub
  i46_test invalid
  must_accept 'wrong fixture RED' cmd shipcraft red
  lf=$(lock_files_tree)
  must_accept 'original RED committed' commit commit_all 'test: wrong fixture RED'
  cp "$lf" "$CW/old-lock"
  oldhead=$(head_rev)
}
# Build exactly ordinary red's current-format lock, keeping its original pathname.
# Temporarily point HEAD at the pre-RED snapshot; no implementation knowledge needed.
i46_candidate() {
  rm "$lf"
  git update-ref HEAD "$BASE" || fail 'fixture HEAD'
  must_accept 'ordinary RED creates candidate' cmd shipcraft red
  local fresh; fresh=$(lock_files_tree)
  cp "$fresh" "$CW/candidate"; rm "$fresh"; cp "$CW/candidate" "$lf"
  git update-ref HEAD "$oldhead" || fail 'restore fixture HEAD'
}
i46_row() {
  local known=''
  if [ -n "$lf" ] && git cat-file -e "HEAD:$lf" 2>/dev/null; then known=$lf; fi
  chk 'red row records redo and HEAD lock id' "$PY" - "$known" "$1" <<'PY'
import json,sys,pathlib
r=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl') if s.strip() and json.loads(s).get('layer')=='red'][-1]
assert r.get('redo') is True,r
assert r.get('result')==sys.argv[2],r
if sys.argv[1]: assert r.get('lock')==pathlib.Path(sys.argv[1]).stem,r
PY
}
i46_refuse() {
  chk 'refusal exit' eq "$RC" 1
  msg_check || fail "$MSGERR"
  if [ "$2" = red ]; then
    i46_row refused
    chk 'red refusal code' "$PY" - "$1" <<'PY'
import json,sys
r=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl') if s.strip() and json.loads(s).get('layer')=='red'][-1]
assert r.get('code')==sys.argv[1],r
PY
  else
    i43_refused "$1" "$2"
  fi
}
item46_case() {
  local c=${CASE#v1-46.} lf='' oldhead bad=''
  EXPECT="item 46: $c"
  case "$c" in
    without-lock|uncommitted)
      v1_start codex; setup_init
      if [ "$c" = uncommitted ]; then L stub; L spec_test; must_accept 'uncommitted RED' cmd shipcraft red; lf=$(lock_files_tree); cp "$lf" "$CW/old-lock"; fi
      run_cmd shipcraft red --redo; i46_refuse redo-without-lock red
      [ -z "$lf" ] || chk 'uncommitted lock untouched' cmp "$lf" "$CW/old-lock"
      pass; return ;;
    report-zero|report-count)
      v1_start codex; setup_init
      chk 'report fixture and redo counting' "$PY" - "$c" "$(command -v shipcraft)" <<'PY'
import json,pathlib,subprocess,sys
p=pathlib.Path('.git/shipcraft/runs.jsonl')
rows=[dict(layer='red',at=100,lock='cycle46',result='passed',secs=1,branch='main',commit='a'*40)]
if sys.argv[1]=='report-count':
 for at,result in [(110,'passed'),(120,'refused'),(130,'passed')]: rows.append(dict(rows[0],at=at,result=result,redo=True))
p.write_text(''.join(json.dumps(r)+'\n' for r in rows))
a=subprocess.run([sys.argv[2],'report','--json'],capture_output=True,text=True); assert a.returncode==0,a.stderr
d=[json.loads(line) for line in a.stdout.splitlines()]
def objects(v):
 if isinstance(v,dict):
  yield v
  for x in v.values(): yield from objects(x)
 elif isinstance(v,list):
  for x in v: yield from objects(x)
cycles=[x for x in objects(d) if x.get('lock')=='cycle46']; assert len(cycles)==1,d
assert cycles[0].get('redos',0)==(2 if sys.argv[1]=='report-count' else 0),d
PY
      pass; return ;;
  esac
  i46_start
  case "$c" in
    bad-seal|bad-format)
      if [ "$c" = bad-seal ]; then
        "$PY" - "$lf" <<'PYSEAL46'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['seal']='0'*64; open(p,'w').write(json.dumps(d)+'\n')
PYSEAL46
        bad=lock-edited
      else
        "$PY" - "$lf" <<'PY46'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['format']=999; open(p,'w').write(json.dumps(d)+'\n')
PY46
        bad=lock-format
      fi
      i43_save 'test: invalid HEAD lock fixture'
      cp "$lf" "$CW/old-lock"
      run_cmd shipcraft red --redo; i46_refuse "$bad" red
      chk 'invalid HEAD bytes untouched' cmp "$lf" "$CW/old-lock"
      pass; return ;;
    other-check|build-fails|no-report)
      i46_test 'a b'
      if [ "$c" = build-fails ]; then
        # Match the established build-command fixture helper.
        tset build command '"exit 23"'
        bad=build-failed
      else
        mkdir -p secondary/tests
        printf 'def test_secondary():\n    assert True\n' > secondary/tests/test_secondary.py
        cat > .shipcraft.toml <<'TOML46'
shipcraft_min = "1.0"
lang = "python"
runner = "pytest"
[[suite]]
root = "."
command = "pytest -q --junitxml={junit} tests"
globs = ["tests/**"]
[[suite]]
name = "secondary"
root = "secondary"
check = "exit 23"
command = "pytest -q --junitxml={junit} tests"
globs = ["tests/**"]
TOML46
        if [ "$c" = no-report ]; then
          perl -pi -e 's/check = "exit 23"/check = "exit 0"/; s/command = "pytest -q --junitxml=\{junit\} tests"/command = "exit 24"/ if $. > 10' .shipcraft.toml
        fi
        bad=no-report
      fi
      run_cmd shipcraft red --redo; i46_refuse "$bad" red
      chk 'later suite or build failure preserves old bytes' cmp "$lf" "$CW/old-lock"
      if [ "$c" = other-check ]; then chk 'other suite check is run' grep -q 'secondary.*check' "$OUT.last3"; fi
      pass; return ;;
  esac
  case "$c" in
    two-open)
      cp "$lf" "${lf%.json}-second.json"; i43_save 'test: two open fixture'
      run_cmd shipcraft red --redo; i46_refuse lock-open red; pass; return ;;
    drops-pass-command) printf 'def test_keep():\n    assert True\n' > tests/test_repair.py ;;
    drops-command) sed '/def test_keep/,$d' tests/test_repair.py > "$CW/test"; cp "$CW/test" tests/test_repair.py ;;
    rename-command) perl -pi -e 's/test_fixture/test_renamed/' tests/test_repair.py ;;
    passes-command) printf 'def test_fixture():\n    assert True\n\ndef test_keep():\n    assert True\n' > tests/test_repair.py ;;
    error-command) printf 'import nonexistent_item46\n' > tests/test_repair.py ;;
    unchanged) ;;
    *) i46_test 'a b' ;;
  esac
  case "$c" in
    drops-command|drops-pass-command|rename-command|passes-command|error-command|log-refusal)
      [ "$c" != log-refusal ] || printf 'def test_fixture():\n    assert True\n\ndef test_keep():\n    assert True\n' > tests/test_repair.py
      run_cmd shipcraft red --redo
      case "$c" in drops-command|drops-pass-command|rename-command) bad=redo-drops-case ;; error-command) bad=error-before-assertions ;; *) bad=red-already-passes ;; esac
      i46_refuse "$bad" red
      chk 'refusal preserves exact old bytes' cmp "$lf" "$CW/old-lock"
      if [ "$bad" = redo-drops-case ]; then chk 'names removed case' grep -q "test_" "$OUT.last3"; fi
      pass; return ;;
    unchanged)
      cp -p "$lf" "$CW/timestamp"
      run_cmd shipcraft red --redo; chk 'unchanged redo succeeds' rc_zero
      chk 'unchanged bytes' cmp "$lf" "$CW/old-lock"
      chk 'no replacement (mtime)' "$PY" - "$lf" "$CW/timestamp" <<'PY'
import os,sys
assert os.stat(sys.argv[1]).st_mtime_ns==os.stat(sys.argv[2]).st_mtime_ns
PY
      chk 'says unchanged' grep -Ei -q 'nothing|unchanged|no changes' "$OUT"
      pass; return ;;
    draken|lists|write-fails|log-fails)
      if [ "$c" = lists ]; then
        printf '\ndef test_added_z():\n    assert False\n\ndef test_added_a():\n    assert False\n' >> tests/test_repair.py
        # Original fixture now passes, while newly added cases fail.
        perl -pi -e "s/assert slugify\(fixture\) == 'a-b'/assert True/" tests/test_repair.py
      fi
      if [ "$c" = log-fails ]; then rm .git/shipcraft/runs.jsonl; mkdir .git/shipcraft/runs.jsonl; fi
      if [ "$c" = write-fails ]; then
        chmod a-w "$(dirname "$lf")"
        run_cmd shipcraft red --redo
        chmod u+w "$(dirname "$lf")"
        chk 'write failure exit' eq "$RC" 1
        chk 'write-specific reason' grep -Ei -q 'writ|permission|replace|denied' "$OUT"
        chk 'write failure leaves old bytes' cmp "$lf" "$CW/old-lock"
        msg_check || fail "$MSGERR"; pass; return
      fi
      run_cmd shipcraft red --redo; chk 'fixture repair redo succeeds' rc_zero
      [ "$c" = log-fails ] || i46_row passed
      chk 'one lock, same path' eq "$(lock_files_tree)" "$lf"
      chk 'valid seal' i43_json seal "$lf"
      cp "$lf" "$CW/redo"
      cp "$OUT" "$CW/redo-output"
      i46_candidate
      chk 'redo equals ordinary red contents' "$PY" - "$lf" "$CW/redo" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))==json.load(open(sys.argv[2]))
PY
      if [ "$c" = lists ]; then
        chk 'prints path and sorted case delta lists' "$PY" - "$CW/redo-output" "$lf" <<'PY'
import pathlib,sys
s=pathlib.Path(sys.argv[1]).read_text(); assert sys.argv[2] in s,s
s=s.split(sys.argv[2],1)[1]
assert 'test_added_a' in s and 'test_added_z' in s and 'test_fixture' in s,s
assert s.index('test_added_a')<s.index('test_added_z'),s
assert 'added' in s.lower() and 'no longer' in s.lower() and 'newly' in s.lower(),s
PY
        pass; return
      fi
      must_accept 'commit repaired test and rewritten lock' commit commit_all 'test: redo fixture'
      L implement
      must_accept 'GREEN closes repaired lock' commit commit_all 'feat: GREEN after repair'
      chk 'new lock closed' one_lock_head_state closed
      must_accept 'PR CI accepts original RED, redo, GREEN' cmd shipcraft ci --base "$BASE"
      pass; return ;;
  esac
  # Independent commit validation fixtures, produced by ordinary RED.
  case "$c" in
    drops-hook|drops-ci) sed '/def test_keep/,$d' tests/test_repair.py > "$CW/test"; cp "$CW/test" tests/test_repair.py ;;
    passes-hook) printf 'def test_fixture():\n    assert True\n\ndef test_keep():\n    assert True\n' > tests/test_repair.py ;;
  esac
  if [ "$c" = passes-hook ]; then
    # Valid lock hashes with all cases passing: obtain from a failing assertion,
    # then reseal after replacing the digest (public canonical format).
    i46_test 'a b'; i46_candidate
    printf 'def test_fixture():\n    assert True\n\ndef test_keep():\n    assert True\n' > tests/test_repair.py
    "$PY" - "$lf" <<'PY'
import json,hashlib,pathlib,sys
p=pathlib.Path(sys.argv[1]); d=json.loads(p.read_text())
d['files']['tests/test_repair.py']='sha256:'+hashlib.sha256(pathlib.Path('tests/test_repair.py').read_bytes()).hexdigest()
c=dict(format=d['format'],state=d['state'],files=dict(sorted(d['files'].items())),cases=d['cases'],failing_at_red=d['failing_at_red'])
if d['format']==4: c.update((k,d[k]) for k in ('kind','reported_at','fixes_release'))
c['seal']=''; d['seal']=hashlib.sha256(json.dumps(c,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
p.write_text(json.dumps(d)+'\n')
PY
  else i46_candidate; fi
  case "$c" in
    mixed-product) printf 'mixed\n' > product.txt; bad=product.txt ;;
    mixed-config) printf '\n# mixed\n' >> .shipcraft.toml; bad=.shipcraft.toml ;;
    mixed-hook) mkdir -p .husky; printf '# mixed\n' > .husky/commit-msg; bad=.husky/commit-msg ;;
    mixed-rename) mv tests/test_repair.py unprotected.py; bad=unprotected.py ;;
  esac
  git add -A
  case "$c" in
    drops-hook|drops-ci|mixed-*)
      if [ "$c" = drops-ci ]; then i43_save 'test: sealed drop'; run_cmd shipcraft ci --base "$BASE"; i46_refuse redo-drops-case ci
      else
        run_cmd shipcraft check
        case "$c" in drops-hook) i46_refuse redo-drops-case hook ;; *) i46_refuse redo-mixed hook; chk 'names mixed path' grep -F -q "$bad" "$OUT.last3" ;; esac
      fi ;;
    passes-hook)
      git update-ref HEAD "$BASE" || fail 'opening RED baseline HEAD'
      run_cmd shipcraft check
      chk 'ordinary opening RED that passes refuses' rc_nonzero
      msg_check || fail "$MSGERR"
      local opening_code
      opening_code=$("$PY" -c 'import json; print([json.loads(s) for s in open(".git/shipcraft/runs.jsonl") if json.loads(s).get("layer")=="hook"][-1]["code"])')
      git update-ref HEAD "$oldhead" || fail 'restore redo parent'
      run_cmd shipcraft check
      i46_refuse "$opening_code" hook
      chk 'same RED passing reason' grep -Ei -q 'already pass|must fail|passes' "$OUT.last3" ;;
    merge)
      # Two parents both hold the old lock; a merge-only rewrite is not redo.
      local tree other merge
      tree=$(git write-tree); other=$(printf 'other\n' | git commit-tree "$(git rev-parse HEAD^{tree})" -p "$oldhead")
      merge=$(printf 'merge rewrite\n' | git commit-tree "$tree" -p "$oldhead" -p "$other")
      git reset -q --hard "$merge"
      run_cmd shipcraft ci --base "$BASE"; i46_refuse lock-edited ci ;;
    accepted|later-test)
      must_accept 'hook accepts sealed redo commit' commit commit_index 'test: redo'
      if [ "$c" = later-test ]; then
        printf '\n# second repair\n' >> tests/test_repair.py; git add -A
        run_cmd shipcraft check; i46_refuse test-changed hook
      else
        L implement; must_accept 'GREEN after sealed redo' commit commit_all 'feat: GREEN'
        must_accept 'CI accepts redo in range' cmd shipcraft ci --base "$BASE"
      fi ;;
  esac
  pass
}
