# Item 53: real pytest/Vitest failures, deterministic first-execution flakiness.
item53_langs() { echo python node; }
item53_cases() { local c; for c in main all-flaky deterministic absent no-report environment redo log-fails all-flaky-log-fails; do echo "v1-53.$c"; done; }
i53_tests() {
  if [ "$LP" = python ]; then
    printf 'def test_intended():\n    assert False\n' > tests/test_intended.py
    cat > tests/test_flaky.py <<'PY'
import os
from pathlib import Path

def test_flaky():
    marker = Path(os.environ['ITEM53_MARKER'])
    seen = marker.exists()
    marker.touch()
    assert seen
PY
  else
    printf "import {it,expect} from 'vitest';\nit('intended',()=>expect(false).toBe(true));\n" > src/intended.test.ts
    cat > src/flaky.test.ts <<'TS'
// @ts-ignore node API is available at runtime
import {existsSync,writeFileSync} from 'node:fs';
import {it,expect} from 'vitest';
// @ts-ignore process is available at runtime
const marker=process.env.ITEM53_MARKER;
it('flaky',()=>{const seen=existsSync(marker);writeFileSync(marker,'seen');expect(seen).toBe(true)});
TS
  fi
}
i53_assert() {
  chk 'first-report cases retained; only reproduced failures locked; one red event' "$PY" - "$1" "$2" "$3" <<'PY'
import json,sys
from pathlib import Path
lock=json.load(open(sys.argv[1])); mode=sys.argv[2]
f=lock['failing_at_red']; cases=lock['cases']
assert any('flaky' in c for c in cases),cases
assert any('intended' in c for c in f),f
assert any('flaky' in c for c in f)==(mode in ('deterministic','absent','no-report')),f
rows=[json.loads(s) for s in Path('.git/shipcraft/runs.jsonl').read_text().splitlines() if json.loads(s).get('layer')=='red']
r=rows[-1]; assert len(rows)==(2 if mode=='redo' else 1),rows
assert r['result']=='passed' and r['rerun_dropped']==(0 if mode in ('deterministic','absent','no-report') else 1),r
assert bool(r.get('redo',False))==(mode=='redo'),r
s=Path(sys.argv[3]).read_text(); line='shipcraft: not locked, passed on a second run:'
assert (line in s)==(r['rerun_dropped']>0),s
if line in s:
    dropped=next(x for x in s.splitlines() if x.startswith(line)); assert 'flaky' in dropped and 'intended' not in dropped,dropped
PY
}
item53_case() {
  local c=${CASE#v1-53.} lf runner
  EXPECT="item 53: $c"; v1_start; setup_init
  export ITEM53_MARKER="$CW/flaky-marker"
  i53_tests
  if [ "$c" = redo ]; then
    touch "$ITEM53_MARKER"
    must_accept 'initial deterministic RED' cmd shipcraft red
    must_accept 'commit open RED' commit commit_all 'test: original RED'
    # Repair the assertion while preserving the test's identity and RED outcome.
    if [ "$LP" = python ]; then
      printf 'def test_intended():\n    assert 1 == 2\n' > tests/test_intended.py
    else
      printf "import {it,expect} from 'vitest';\nit('intended',()=>expect(1).toBe(2));\n" > src/intended.test.ts
    fi
    rm -f "$ITEM53_MARKER"
  fi
  case "$c" in
    all-flaky|all-flaky-log-fails)
      if [ "$LP" = python ]; then rm tests/test_intended.py; else rm src/intended.test.ts; fi ;;
    deterministic) touch "$ITEM53_MARKER"; # Both cases fail on every run.
      if [ "$LP" = python ]; then printf 'def test_flaky():\n    assert False\n' > tests/test_flaky.py
      else printf "import {it,expect} from 'vitest';\nit('flaky',()=>expect(false).toBe(true));\n" > src/flaky.test.ts; fi ;;
  esac
  if [ "$c" = absent ] || [ "$c" = no-report ] || [ "$c" = environment ]; then
    if [ "$LP" = python ]; then runner='pytest --junitxml="$report" tests'; else runner='node_modules/.bin/vitest run --reporter=junit --outputFile="$report"'; fi
    cat > suite53.sh <<SH53
#!/bin/sh
report="\$1"
if [ -n "\${SHIPCRAFT_CASES:-}" ]; then
  printf 'rerun\\n' >> '$CW/observed'
  cat "\$SHIPCRAFT_CASES" > '$CW/cases'
  [ -z "\${SHIPCRAFT_FILES:-}" ] || cat "\$SHIPCRAFT_FILES" > '$CW/files'
  [ '$c' != no-report ] || exit 1
  if [ '$c' = absent ]; then
    if [ -d tests ]; then exec pytest --junitxml="\$report" tests/test_intended.py; else exec node_modules/.bin/vitest run --reporter=junit --outputFile="\$report" src/intended.test.ts; fi
  fi
else printf 'first\\n' >> '$CW/observed'; fi
$runner
SH53
    # Explicit suites: only the failing suite reruns; checks/build run once.
    "$PY" - "$CW" <<'PY'
import json,sys
from pathlib import Path
cw=sys.argv[1]
p=Path('.shipcraft.toml'); s=p.read_text(); s=s[:s.index('[[suite]]')] if '[[suite]]' in s else s
# Drop top-level command/globs/check so explicit suites own execution.
s='\n'.join(l for l in s.splitlines() if not l.startswith(('command =','globs =','check =','filter =')))+'\n'
s+='[build]\ncommand = '+json.dumps('echo build >> '+cw+'/order')+'\n'
for name,cmd in [('primary','sh suite53.sh {junit}'),('passing',"printf '<testsuite><testcase classname=\"passing\" name=\"ok\"/></testsuite>' > {junit}; echo passing >> "+cw+'/order')]:
 s+='\n[[suite]]\nname = '+json.dumps(name)+'\nroot = "."\nfilter = "command"\ncommand = '+json.dumps(cmd)+'\nglobs = ["tests/**", "src/**"]\ncheck = '+json.dumps('echo check-'+name+' >> '+cw+'/order')+'\n'
p.write_text(s)
PY
  fi
  case "$c" in log-fails|all-flaky-log-fails) rm -f .git/shipcraft/runs.jsonl; mkdir .git/shipcraft/runs.jsonl ;; esac
  if [ "$c" = redo ]; then run_cmd shipcraft red --redo; else run_cmd shipcraft red; fi
  case "$c" in
    all-flaky|all-flaky-log-fails)
      chk 'all transient failures refuse' eq "$RC" 1
      msg_check || fail "$MSGERR"
      chk 'no lock' no_lock
      chk 'refusal names flaky case and gives rerun advice' "$PY" - "$OUT" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(); r=s[s.index('shipcraft refused:'):].strip().splitlines()
assert len(r)==3 and 'flaky' in r[0] and r[1].startswith('Why:') and r[2].startswith('Next:'),r
assert 'again' in r[2].lower() and 'red-not-reproduced' not in s,r
PY
      if [ "$c" = all-flaky ]; then
        chk 'one red-not-reproduced event' "$PY" - <<'PY'
import json
r=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl') if json.loads(s).get('layer')=='red']
assert len(r)==1 and r[0]['result']=='refused' and r[0]['code']=='red-not-reproduced',r
PY
      fi
      pass; return ;;
  esac
  chk 'RED accepted' rc_zero
  lf=$(lock_files_tree)
  if [ "$c" = log-fails ]; then
    chk 'log failure leaves correct lock and notice' "$PY" - "$lf" "$OUT" <<'PY'
import json,sys
f=json.load(open(sys.argv[1]))['failing_at_red']; assert len(f)==1 and 'intended' in f[0],f
assert 'shipcraft: not locked, passed on a second run:' in open(sys.argv[2]).read()
PY
  else i53_assert "$lf" "$c" "$OUT"; fi
  case "$c" in absent|no-report|environment)
    chk 'only failing suite reruns; build/check once; full first failure lists' "$PY" - "$CW" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); assert (p/'observed').read_text().splitlines()==['first','rerun']
a=(p/'order').read_text().splitlines(); assert a==['build','check-primary','check-passing','passing'],a
for name in ('cases','files'):
 b=(p/name).read_bytes(); assert b.endswith(b'\0') and b'intended' in b and b'flaky' in b,(name,b)
PY
    ;;
  esac
  [ "$c" != main ] || must_accept 'RED commit hook accepts only reproduced failure' commit commit_all 'test: confirmed RED'
  pass
}
