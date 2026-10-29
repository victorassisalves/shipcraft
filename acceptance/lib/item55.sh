# Item 55: changed-file RED selection, exercised through real runner reports.
item55_langs() { echo python node go; }
item55_cases() {
  if [ "${l:-}" = go ]; then echo v1-55.package; return; fi
  local c
  for c in main all no-base config removed support support-test committed base ignored redo redo-base error environment log-fails all-log-fails missing-base repeated-all; do echo "v1-55.$c"; done
}
i55_write() {
  local path=$1 name=$2 value=${3:-False}
  if [ "$LP" = python ]; then
    printf 'def test_%s():\n    assert %s\n' "$name" "$value" > "$path"
  else
    [ "$value" != False ] || value=false
    [ "$value" != True ] || value=true
    printf "import {it,expect} from 'vitest';\nit('%s',()=>expect(%s).toBe(true));\n" "$name" "$value" > "$path"
  fi
}
i55_commit() { git add -A && git -c core.hooksPath="$CW/no-hooks" commit -qm "$1" || fail 'fixture commit'; }
i55_verify() {
  "$PY" - "$OUT" "$(lock_files_tree)" "$reason" "$selected" "$old" "$new" "$c" "$CW" <<'PY'
import hashlib,json,sys
from pathlib import Path
out,lf,reason,n,old,new,mode,cw=sys.argv[1:]; n=int(n)
s=Path(out).read_text(); d=json.load(open(lf))
for f,h in d['files'].items():
 assert h=='sha256:'+hashlib.sha256(Path(f).read_bytes()).hexdigest(),(f,h)
support='tests/conftest.py' if old.startswith('tests/') else 'src/setup55.ts'
smoke='tests/test_smoke.py' if old.startswith('tests/') else 'src/smoke.test.ts'
expected={'.shipcraft.toml',old,smoke}|{f for f in (new,support) if Path(f).exists()}
assert set(d['files'])==expected,(d['files'],expected)
for key in ('cases','failing_at_red'):
 ids=d[key]
 if not reason: assert len(ids)==1,(key,ids)
 if reason and key=='cases': assert any('module_imports' in x or 'module imports' in x for x in ids),ids
 assert any('fresh55' in x for x in ids) or mode in ('support','committed','removed') or (mode=='support-test' and key=='failing_at_red'),ids
 assert any('legacy55' in x for x in ids)==bool(reason), (key,ids,reason)
line=('shipcraft: red ran every suite: '+reason if reason else f'shipcraft: red ran the changed test files: {n} of {len(d["files"])}')
assert s.count(line)==1,(line,s)
if mode not in ('log-fails','all-log-fails'):
 rows=[json.loads(x) for x in Path('.git/shipcraft/runs.jsonl').read_text().splitlines() if json.loads(x).get('layer')=='red']
 assert len(rows)==(2 if mode.startswith('redo') else 1),rows
 r=rows[-1]; assert (r['selection'],r['selected_files'],r['fallback'])==('all' if reason else 'changed',n,reason or None),r
if not reason: assert not Path(cw,'legacy-collected').exists(),'unchanged failing test ran'
PY
}
item55_case() {
  local c=${CASE#v1-55.} old new support reason='' selected=1
  EXPECT="item 55: $c"; v1_start; setup_init
  if [ "$c" = package ]; then
    PATH="$GOBIN:$PATH"; export PATH
    printf 'package textutil\nimport "testing"\nfunc TestLegacy55(t *testing.T) { t.Fatal("old") }\n' > legacy_test.go
    i55_commit 'test: old failing package case'; remote_setup; git checkout -qb feature/package55
    printf 'package textutil\nimport "testing"\nfunc TestFresh55(t *testing.T) { t.Fatal("new") }\n' > fresh_test.go
    run_cmd shipcraft red
    chk 'package RED accepted' rc_zero
    chk 'whole package runs but only changed file cases locked' "$PY" - "$(lock_files_tree)" "$OUT" <<'PY55GO'
import json,sys
from pathlib import Path
d=json.load(open(sys.argv[1]))
for k in ('cases','failing_at_red'):
 assert any('TestFresh55' in x for x in d[k]) and not any('TestLegacy55' in x for x in d[k]),d[k]
assert 'legacy_test.go' in d['files']
r=[json.loads(x) for x in open('.git/shipcraft/runs.jsonl') if json.loads(x).get('layer')=='red'][-1]
assert (r['selection'],r['selected_files'],r['fallback'])==('changed',1,None),r
assert 'shipcraft: red ran the changed test files: 1 of' in Path(sys.argv[2]).read_text()
PY55GO
    pass; return
  fi
  if [ "$LP" = python ]; then old=tests/test_legacy55.py; new=tests/test_fresh55.py; support=tests/conftest.py
  else old=src/legacy55.test.ts; new=src/fresh55.test.ts; support=src/setup55.ts; fi
  i55_write "$old" legacy55
  if [ "$LP" = python ]; then printf '\nfrom pathlib import Path\nPath(%s).touch()\n' "\"$CW/legacy-collected\"" >> "$old"
  else printf '\n// @ts-ignore\nimport {writeFileSync} from "node:fs";\nwriteFileSync("%s", "seen");\n' "$CW/legacy-collected" >> "$old"; fi
  # Protect a runner support file without adding a case to it.
  printf '# support\n' > "$support"
  [ "$LP" = python ] || printf '// support\n' > "$support"
  "$PY" - "$support" <<'PY55CFG'
import json,sys
from pathlib import Path
p=Path('.shipcraft.toml'); s=p.read_text(); s=s.replace('test_globs = [','test_globs = ['+json.dumps(sys.argv[1])+', ',1); p.write_text(s)
PY55CFG
  i55_commit 'test: existing failing file and support'
  remote_setup
  BASE=$(head_rev)
  git checkout -qb feature/item55
  if [ "$c" = environment ]; then
    "$PY" - "$CW" <<'PY'
import json,sys
from pathlib import Path
p=Path('.shipcraft.toml'); s=p.read_text(); s=s[:s.index('[[suite]]')] if '[[suite]]' in s else s
s='\n'.join(l for l in s.splitlines() if not l.startswith(('command =','globs =','check =','filter =')))+'\n'
cmd='sh suite55.sh {junit}'
s+='\n[[suite]]\nname = "custom55"\nroot = "."\nfilter = "command"\ncommand = '+json.dumps(cmd)+'\nglobs = ["tests/**", "src/**/*.test.ts"]\n'
p.write_text(s)
PY
    cat > suite55.sh <<SH55
#!/bin/sh
if [ ! -f '$CW/env55' ]; then
  env > '$CW/env55'
  [ -z "\${SHIPCRAFT_FILES:-}" ] || cp "\$SHIPCRAFT_FILES" '$CW/files55'
fi
if [ -d tests ]; then exec pytest --junitxml="\$1" tests/test_fresh55.py tests/test_z55.py
else exec node_modules/.bin/vitest run --reporter=junit --outputFile="\$1" src/fresh55.test.ts src/z55.test.ts; fi
SH55
    i55_commit 'chore: custom runner'
    git update-ref refs/remotes/origin/main HEAD
  fi
  i55_write "$new" fresh55
  case "$c" in
    all|all-log-fails) reason=--all; selected=0 ;;
    no-base) git remote remove origin; reason='no base'; selected=0 ;;
    config) printf '\n# changed config\n' >> .shipcraft.toml; reason='config changed'; selected=0 ;;
    removed) rm "$support"; reason='protected file removed'; selected=0 ;;
    support|support-test)
      printf '\n' >> "$support"; reason='file without cases'; selected=2
      if [ "$c" = support ]; then rm "$new"; selected=1
      else i55_write "$new" fresh55 True; fi ;;
    committed) i55_commit 'test: already on base'; git update-ref refs/remotes/origin/main HEAD; reason='nothing selected'; selected=0 ;;
    base) i55_commit 'test: committed beyond explicit base'; git update-ref refs/remotes/origin/main HEAD ;;
    ignored)
      mkdir -p "$(dirname "$new")/ignored55"
      mv "$new" "$(dirname "$new")/ignored55/$(basename "$new")"; new="$(dirname "$new")/ignored55/$(basename "$new")"
      i55_write "$new" fresh55 True; git add -f "$new"; i55_commit 'test: tracked ignored folder'
      printf 'ignored55/\n' >> .gitignore; i55_commit 'chore: ignore'; git update-ref refs/remotes/origin/main HEAD
      i55_write "$new" fresh55 ;;
    redo|redo-base)
      must_accept 'initial narrow RED' cmd shipcraft red
      i55_commit 'test: open RED'
      if [ "$c" = redo-base ]; then reason='no base'; selected=0; fi ;;
    error) if [ "$LP" = python ]; then printf 'raise RuntimeError("collection55")\n' >> "$new"; else printf 'throw new Error("collection55");\n' >> "$new"; fi ;;
    environment)
      if [ "$LP" = python ]; then i55_write tests/test_z55.py z55; else i55_write src/z55.test.ts z55; fi ;;
  esac
  case "$c" in log-fails|all-log-fails) rm -f .git/shipcraft/runs.jsonl; mkdir .git/shipcraft/runs.jsonl ;; esac
  case "$c" in
    missing-base) run_cmd shipcraft red --base ;;
    repeated-all) run_cmd shipcraft red --all --all ;;
    all|all-log-fails) run_cmd shipcraft red --all ;;
    base) run_cmd shipcraft red --base "$BASE" ;;
    redo) run_cmd shipcraft red --redo ;;
    redo-base) run_cmd shipcraft red --redo --base nonexisting55 ;;
    *) run_cmd shipcraft red ;;
  esac
  case "$c" in
    missing-base|repeated-all) chk 'invalid arguments' eq "$RC" 2; pass; return ;;
    error)
      if [ "$LP" != python ]; then
        # vitest reports a module-level throw as a failed case, not an error (item 52, v1-52.precedence):
        # red locks it as today; only the selection is this item's.
        chk 'vitest import failure locked as today' rc_zero
        chk 'selection notice printed' match 'shipcraft: red ran the changed test files: 1 of' "$(cat "$OUT")"
        pass; return
      fi
      chk 'collection error refuses' eq "$RC" 1
      chk 'selection notice survives refusal' match 'shipcraft: red ran the changed test files: 1 of' "$(cat "$OUT")"
      chk 'refusal code and selection recorded' "$PY" - <<'PY'
import json
r=[json.loads(x) for x in open('.git/shipcraft/runs.jsonl') if json.loads(x).get('layer')=='red'][-1]
assert r['code']=='error-before-assertions' and r['selection']=='changed' and r['fallback'] is None,r
PY
      pass; return ;;
    environment)
      chk 'custom RED accepted' rc_zero
      chk 'first command gets sorted absolute NUL files only' "$PY" - "$CW" "$new" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]); env=(p/'env55').read_text(); assert 'SHIPCRAFT_CASES=' not in env,env
assert (p/'files55').exists(),'narrowed first run did not supply SHIPCRAFT_FILES'
b=(p/'files55').read_bytes(); paths=[Path(sys.argv[2]).resolve(),Path('tests/test_z55.py' if Path('tests').exists() else 'src/z55.test.ts').resolve()]
assert b==b''.join(x+b'\0' for x in sorted(str(x).encode() for x in paths)),b
PY
      pass; return ;;
  esac
  chk 'RED accepted' rc_zero
  chk 'selection, lock, hashes and execution boundary' i55_verify
  pass
}
