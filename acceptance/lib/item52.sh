# Item 52: public commands and real, unmodified Vitest JUnit only.
item52_langs() { echo node; }
item52_cases() {
  local c
  for c in throw timeout mixed same-name plain redo precedence newline sorted build check no-report log-fails; do echo "v1-52.$c"; done
}
i52_group() {
  cat > src/a.spec.ts <<'TS'
import {describe,beforeAll,it,expect} from 'vitest';
describe('licensing store',()=>{
 beforeAll(()=>{throw new Error('setup boom')});
 it('one',()=>expect(true).toBe(true));
 describe('inner',()=>it('two',()=>expect(true).toBe(true)));
});
it('top',()=>expect(true).toBe(true));
TS
}
i52_plain() {
  printf "import {it,expect} from 'vitest';\nit('store',()=>expect(1).toBe(2));\n" > src/a.spec.ts
}
i52_row() {
  chk 'red refusal row and redo flag' "$PY" - "$1" "$2" <<'PY'
import json,sys
r=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl') if s.strip() and json.loads(s).get('layer')=='red'][-1]
assert r['result']=='refused' and r.get('code')==sys.argv[1],r
assert bool(r.get('redo',False))==(sys.argv[2]=='redo'),r
PY
}
i52_refuse() {
  chk 'refusal exit' eq "$RC" 1
  msg_check || fail "$MSGERR"
  i52_row "$1" "$2"
}
item52_case() {
  local c=${CASE#v1-52.} lf='' mode=ordinary code=group-failed
  EXPECT="item 52: $c"; v1_start; setup_init
  if [ "$c" = redo ]; then
    i52_plain
    must_accept 'ordinary RED opens lock' cmd shipcraft red
    lf=$(lock_files_tree)
    must_accept 'commit original open lock' commit commit_all 'test: ordinary RED'
    cp "$lf" "$CW/old-lock"
    mode=redo
  fi
  i52_group
  case "$c" in
    timeout) perl -pi -e "s/beforeAll\(\(\)=>\{throw new Error\('setup boom'\)\}\);/beforeAll(async()=>{await new Promise(r=>setTimeout(r,500))},100);/" src/a.spec.ts ;;
    mixed) printf "import {it,expect} from 'vitest';\nit('real failure',()=>expect(1).toBe(2));\n" > src/z.spec.ts ;;
    same-name)
      i52_plain
      printf "import {describe} from 'vitest';\ndescribe('store',()=>it('child',()=>expect(1).toBe(1)));\n" >> src/a.spec.ts ;;
    plain) i52_plain ;;
    precedence) printf "// @ts-ignore deliberate runtime import error\nimport 'nonexistent-item52-module';\n" > src/z.spec.ts; code=group-failed ;;
    newline) perl -pi -e 's/licensing store/licensing\\nstore/' src/a.spec.ts ;;
    sorted)
      # Source order differs from byte order; XML escaping and UTF-8 are real reporter output.
      perl -pi -e 's/licensing store/z & <store>/' src/a.spec.ts
      cat >> src/a.spec.ts <<'TS'
describe('a café',()=>{beforeAll(()=>{throw new Error('second setup')});it('child',()=>expect(true).toBe(true));});
TS
      ;;
    build) tset build command '"exit 23"'; code=build-failed ;;
    check|no-report)
      cat >> .shipcraft.toml <<'TOML'

[[suite]]
name = "primary"
root = "."
command = "node_modules/.bin/vitest run --reporter=junit --outputFile={junit}"
globs = ["src/**"]

[[suite]]
name = "later"
root = "."
command = "exit 24"
globs = ["src/**"]
TOML
      if [ "$c" = check ]; then
        printf 'check = "exit 23"\n' >> .shipcraft.toml
      fi
      code=no-report ;;
    log-fails) rm -f .git/shipcraft/runs.jsonl; mkdir .git/shipcraft/runs.jsonl ;;
  esac
  # Independently verify the runner contract before judging shipcraft's verdict.
  if [ "$code" = group-failed ] && [ "$c" != same-name ] && [ "$c" != plain ]; then
    run_cmd node_modules/.bin/vitest run --reporter=junit --outputFile="$CW/group.xml"
    chk 'real reporter has failed block and skipped descendants' "$PY" - "$CW/group.xml" "$c" <<'PY52'
import sys,xml.etree.ElementTree as ET
cases=list(ET.parse(sys.argv[1]).iter('testcase'))
groups=[]
for n in cases:
 children=[x for x in cases if x.get('classname')==n.get('classname') and x.get('name','').startswith(n.get('name','')+' > ')]
 if n.find('failure') is not None and children and all(x.find('skipped') is not None for x in children): groups.append(n)
assert groups,[(x.attrib,[c.tag for c in x]) for x in cases]
if sys.argv[2]=='newline': assert 'name="licensing\nstore"' in open(sys.argv[1]).read(), 'Vitest did not preserve newline'
print('real group ids:', [n.attrib for n in groups])
PY52
  fi
  if [ "$mode" = redo ]; then run_cmd shipcraft red --redo; else run_cmd shipcraft red; fi
  case "$c" in
    same-name|plain)
      chk 'real failure still locks' rc_zero
      chk 'exact real failing identity' "$PY" - "$(lock_files_tree)" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); assert r['failing_at_red']==['src/a.spec.ts::store'],r
PY
      pass; return ;;
    log-fails)
      chk 'failed log append does not turn refusal into lock' eq "$RC" 1
      msg_check || fail "$MSGERR" ;;
    *) i52_refuse "$code" "$mode" ;;
  esac
  if [ "$mode" = redo ]; then
    chk 'redo preserves exact committed lock bytes' cmp "$lf" "$CW/old-lock"
  else
    chk 'no lock created' no_lock
  fi
  if [ "$code" = group-failed ]; then
    chk 'three-line refusal with block identities and actionable explanation' "$PY" - "$OUT" "$c" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(); lines=[x for x in s.splitlines() if x.strip()]
# Runner output precedes the refusal; assert the refusal itself remains three lines.
starts=[i for i,x in enumerate(lines) if x.startswith('shipcraft refused:')]
assert starts, s
r=lines[starts[-1]:] if len(starts)==1 else lines[starts[0]:]
assert len(r)==3,r
assert r[1].startswith('Why:') and r[2].startswith('Next:'),r
assert 'group-failed' not in '\n'.join(r),r
assert 'hook' in r[1].lower() and 'hook' in r[2].lower(),r
assert 'test' in r[1].lower() and ('again' in r[2].lower() or 'rerun' in r[2].lower()),r
if sys.argv[2]=='sorted':
 a='src/a.spec.ts::a café'; z='src/a.spec.ts::z & <store>'
 assert a in r[0] and z in r[0] and r[0].index(a)<r[0].index(z),r
elif sys.argv[2]=='newline':
 assert 'src/a.spec.ts::licensing' in r[0] and 'store' in r[0],r
else:
 assert 'src/a.spec.ts::licensing store' in r[0],r
PY
  fi
  pass
}
