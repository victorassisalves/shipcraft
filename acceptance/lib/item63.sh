# Item 63: black-box briefs, reviewer process boundary and review measurements.
item63_cases() {
  local c
  for c in brief-local brief-github brief-local-docs brief-github-docs brief-off brief-off-spoof brief-review brief-review-pr brief-review-pr-spoof \
    print-local print-github-docs env-codex-pr env-claude-pr env-gemini-pr env-codex-review env-claude-review env-gemini-review \
    no-verdict-local no-verdict-review start-fails-local start-fails-review publish-fails-local publish-fails-review-pr \
    reuse-pr reuse-review-pr reuse-cross legacy-reuse-pr legacy-reuse-review-pr version; do echo "v1-63.$c"; done
}
i63_row() {
  "$PY" - "$1" "${2:-fresh}" <<'PY'
import json,sys
rs=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl') if json.loads(s).get('layer')=='review']
assert rs,'missing review row'
r=rs[-1]
if sys.argv[2]=='reused':
 assert r.get('reused') is True,r
 assert 'after_green_ci' not in r,r
else:
 assert r.get('reused') is not True,r
 assert r.get('after_green_ci') is (sys.argv[1]=='true'),('after_green_ci',r)
 if sys.argv[2]=='error': assert r['result']=='error' and r.get('code'),r
PY
}
i63_brief() {
  "$PY" - "$ST/reviewer.calls.jsonl" "$HEADSHA" "$1" "${2:-product}" "${3:-pr}" <<'PY'
import hashlib,json,re,sys
r=json.loads(open(sys.argv[1]).readlines()[-1]); bs=[v for k,v in r['files'].items() if k.endswith('/brief.md')]
assert len(bs)==1, r
s=bs[0]; sha=sys.argv[2]; after=sys.argv[3]=='true'
for marker in ('SPEC-MARKER-5e1','- feat: shout' if sys.argv[5]=='review' else 'PR-BODY-MARKER-91b','test_bateria_marker_2c7','Titulo-PR-6d1' if after else '- Title:'):
 assert marker in s,marker
assert sha in s and 'python3 -m pytest' in s and '{junit}' in s,s
assert ('docs63-marker' if sys.argv[4]=='docs' else 'diff-marker-4f9a') in s,s
if after:
 opening=s.split('## What you are reviewing',1)[0]
 steps=s.split('## Steps',1)[1].split('## Rules for a Blocking item',1)[0]
 fmt=s.split('## Review format',1)[1].split('## Ground rules',1)[0]
 for label,part in (('opening',opening),('steps',steps)):
  assert 'CI is green' in part,(label,part)
  assert re.search(r"must not|do not|don't|never",part,re.I),(label,'missing no-suite instruction',part)
  assert re.search(r'suite',part,re.I) and re.search(r"CI.s job|CI.s responsibility|CI handles|CI runs|belongs to CI",part,re.I),(label,part)
 assert 'The suite: not rerun (CI green at '+sha[:7]+')' in fmt,fmt
 # Look across ALL instructions, so an updated opening cannot hide stale steps/format.
 instructions=opening+steps+s.split('## Rules for a Blocking item',1)[1]
 for stale in ('then run the\n   suite with the commands above','Record passed/total','The suite: passed/total','run its test\nsuite','the suite passed'):
  assert stale not in instructions,stale
 assert 'passed/total' not in instructions,instructions
 for sentence in re.split(r'(?<=[.!?])\s+|\n\s*\n',instructions):
  if re.search(r'\brun (?:the |its |this )?(?:full |whole )?(?:test )?suite\b',sentence,re.I):
   assert re.search(r"must not|do not|don't|never|not run",sentence,re.I),('suite mandate',sentence)
 assert re.search(r'install',steps,re.I),steps
 assert re.search(r'smallest|small selection|smallest selection',instructions,re.I),instructions
 assert re.search(r'file',instructions,re.I) and re.search(r'package',instructions,re.I) and re.search(r'test name|name of a test',instructions,re.I),instructions
 assert re.search(r'isolate',instructions,re.I) and re.search(r'never.{0,40}Blocking|not.{0,40}Blocking',instructions,re.I|re.S),instructions
 assert re.search(r'every case|all (?:the )?(?:cases|tests)',instructions,re.I),instructions
else:
 # Captured through the public reviewer stub on the pre-item 2.18.0 binary.
 # Keep every built-in byte; replace only runtime metadata and embedded payload.
 def normalize(s):
  s=re.sub(r'the branch [^\n]+ \(before its pull request\) in the project [^\n]+\.', 'pull request #PR in the project PROJECT.',s,count=1)
  s=re.sub(r'pull request #[^ ]+ in the project [^\n]+\.', 'pull request #PR in the project PROJECT.',s,count=1)
  s=re.sub(r'(?m)^- Title: .*$', '- Title: TITLE',s)
  s=re.sub(r'(?m)^- Head commit: .*$', '- Head commit: HEAD',s)
  s=re.sub(r'(?m)^- Merge base with the base branch: .*$', '- Merge base with the base branch: BASE',s)
  root=re.search(r'working directory: (.+)/arvore\n',s).group(1)
  s=s.replace(root,'SCRATCH')
  s=re.sub(r'## The intent \(the PR body\)\n.*?\n## Steps\n', 'PAYLOAD\n## Steps\n',s,flags=re.S)
  s=re.sub(r'(APPROVE at |CHANGES REQUESTED at )[0-9a-f]{40}',r'\1HEAD',s)
  return s
 assert hashlib.sha256(normalize(s).encode()).hexdigest()=='5fbb23cfac9701eab8fffa4e956cb45914db1bebef2525462e1dcca7c8607fb6',normalize(s)
PY
}
i63_env_stub() {
  # Instrument only case-owned copies of the common fake agents, before they read stdin.
  "$PY" - "$CB/$1" "$CW/launch63" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text(); needle='HERE = os.path.dirname(os.path.abspath(sys.argv[0]))'
s=s.replace(needle,"with open(os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), 'state', 'env63.json'), 'w') as f:\n    json.dump({k.hex(): v.hex() for k,v in os.environb.items()}, f)\n\n"+needle)
p.write_text(s)
Path(sys.argv[2]).write_text('''import os,sys
p=os.fsencode(sys.argv[1]); env=os.environb.copy()
env.update({b'SHIPCRAFT_X':b'invented', b'SHIPCRAFT_BAD':b'\\xff\\xfe', b'SHIPCRAFT_\\xff':b'raw name',
 b'SHIPCRAFT_PRODUCT_LINES':b'777', b'SHIPCRAFT_SHAPE_WARNINGS':b'13', b'SHIPCRAFT_PR_LOCKS':b'["lock63"]',
 b'ITEM63_KEEP':b' spaces \\n caf\\xc3\\xa9 ', b'ITEM63_RAW':b'\\xff\\xfe', b'ITEM63_\\xff':b'raw-name-value',
 b'SHIPCRAFT':b'no underscore', b'XSHIPCRAFT_X':b'not prefix'})
os.execve(p,[p,*map(os.fsencode,sys.argv[2:])],env)
''')
PY
}
i63_run() {
  if [ "$kind" = pr ]; then
    if [ "$envcase" = yes ]; then run_cmd TMO 180 "$PY" "$CW/launch63" "$(command -v shipcraft)" pr --title Titulo-PR-6d1 --body "$CW/body.md"
    else shipcraft_pr; fi
  elif [ "$kind" = review ]; then
    if [ "$envcase" = yes ]; then run_cmd TMO 180 "$PY" "$CW/launch63" "$(command -v shipcraft)" review
    else run_cmd TMO 180 shipcraft review; fi
  else run_cmd TMO 180 shipcraft review --pr "$PRN"; fi
}
item63_case() {
  local c="${CASE#v1-63.}" agent=codex ci=local kind=pr after=true docs=product envcase=no
  EXPECT="item 63: $c"
  if [ "$c" = version ]; then
    chk 'version follows Cargo manifest, including 12 hex build suffix' "$PY" - "$ACEITE/../nucleo/Cargo.toml" "$(command -v shipcraft)" <<'PY'
import re,subprocess,sys
try: import tomllib
except ImportError: import tomli as tomllib
v=tomllib.load(open(sys.argv[1],'rb'))['package']['version']
p=subprocess.run([sys.argv[2],'--version'],capture_output=True,text=True)
assert p.returncode==0 and re.fullmatch(r'shipcraft '+re.escape(v)+r' \([0-9a-f]{12}\)\n',p.stdout),(v,p)
PY
    pass; return
  fi
  case "$c" in *github*) ci=github ;; brief-off*) ci=off; after=false ;; esac
  case "$c" in *-review|brief-review) kind=review; after=false ;; *review-pr*) kind=review-pr; after=false ;; esac
  case "$c" in reuse-cross) kind=pr ;; esac
  case "$c" in *docs*) docs=docs ;; esac
  case "$c" in env-*) envcase=yes; agent=${c#env-}; agent=${agent%-*} ;; esac
  v1_start "$agent"
  CFGS="execution|ci|\"$ci\"
execution|review|\"local\"
review|spec|\"docs/spec-produto.md\"
pr|shape_lines|1"
  pr_main
  if [ "$docs" = docs ]; then
    BR=feature/docs63; git checkout -qb "$BR"; printf 'docs63-marker\n' > docs/change63.md; pr_commit 'docs: item63'
  else pr_feature; fi
  HEADSHA=$(head_rev); printf '%s\n' "$HEADSHA" > "$ST/sha"
  seed_ok "$HEADSHA" shipcraft/ci
  case "$c" in *spoof*) export SHIPCRAFT_AFTER_GREEN_CI=true SHIPCRAFT_CI_GREEN=true; seed_ok "$HEADSHA" shipcraft/review ;; esac
  [ "$kind" != review-pr ] || pr_outside "$BR"
  [ "$envcase" != yes ] || i63_env_stub "$agent"
  case "$c" in no-verdict-*) rev_cfg malformed ;; start-fails-*)
    # Exists at detection time but exec fails (missing interpreter).
    printf '#!/no/such/interpreter63\n' > "$CB/$agent"; chmod +x "$CB/$agent" ;;
  esac
  case "$c" in publish-fails-*)
    mv "$CB/gh" "$CB/gh63-real"
    "$PY" - "$CB/gh" "$PY" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);p.write_text('#!'+sys.argv[2]+'\n'+'''import os,sys
from pathlib import Path
a=sys.argv[1:]
if a[:2] in (['pr','comment'],['pr','review']) or (a[:1]==['api'] and any('/comments' in s or s.endswith('/reviews') for s in a)):
 Path(__file__).with_name('publish63-failed').touch()
 sys.exit(1)
p=Path(__file__).with_name('gh63-real');os.execv(str(p),[str(p),*a])
''');p.chmod(0o755)
PY
    ;;
  esac
  i63_run
  case "$c" in
    brief-*) chk 'review succeeded' rc_zero; chk 'exact brief choice and complete instructions' i63_brief "$after" "$docs" "$kind" ;;
    print-*)
      chk 'review succeeded' rc_zero
      chk 'review announcement ends exactly with CI green suffix, once' "$PY" - "$OUT" "$HEADSHA" <<'PY'
from pathlib import Path
import sys
s=Path(sys.argv[1]).read_text(); ls=[x for x in s.splitlines() if x.startswith('shipcraft: review by ')]
assert len(ls)==1,ls
assert ls[0].endswith('; CI is green at '+sys.argv[2][:7]+', so the suite is not rerun'),ls
assert 'the suite passed' not in s.lower(),s
PY
      ;;
    env-*)
      chk 'review succeeded despite raw environment bytes' rc_zero
      chk 'Shipcraft retains measurement context on its own rows' "$PY" - "$kind" <<'PY'
import json,sys
rows=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl')]
layers=('ci','review','pr') if sys.argv[1]=='pr' else ('review',)
for layer in layers:
 r=[r for r in rows if r['layer']==layer][-1]
 if layer!='pr':
  assert r.get('product_lines')==(3 if sys.argv[1]=='pr' else 777),r
  assert r.get('shape_warnings')==(1 if sys.argv[1]=='pr' else 13),r
 assert r.get('locks')==([] if sys.argv[1]=='pr' else ['lock63']),r
PY
      chk 'only reviewer loses every SHIPCRAFT_ byte-prefix; all other bytes survive' "$PY" - "$ST/env63.json" <<'PY'
import json,sys
r={bytes.fromhex(k):bytes.fromhex(v) for k,v in json.load(open(sys.argv[1])).items()}
for k,v in {b'ITEM63_KEEP':b' spaces \n caf\xc3\xa9 ',b'ITEM63_RAW':b'\xff\xfe',b'ITEM63_\xff':b'raw-name-value',b'SHIPCRAFT':b'no underscore',b'XSHIPCRAFT_X':b'not prefix'}.items(): assert r.get(k)==v,(k,r.get(k),v)
assert r.get(b'PATH') and r.get(b'HOME'),'missing PATH/HOME'
leaked=[k for k in r if k.startswith(b'SHIPCRAFT_')]
assert not leaked,('leaked variable names',leaked)
PY
      ;;
    no-verdict-*|start-fails-*) chk 'review failure still has an error row with origin flag' i63_row "$after" error; pass; return ;;
    publish-fails-*)
      chk 'publication attempted and failed after review' test -f "$CB/publish63-failed"
      chk 'publication error' rc_nonzero
      chk 'review ran exactly once' eq "$(rev_n)" 1 ;;
    *reuse*)
      chk 'first review succeeds' rc_zero
      cp .git/shipcraft/runs.jsonl "$CW/rows63-first"
      case "$c" in legacy-*)
        # Historical row fixtures are public JSONL data, never lock edits.
        "$PY" - <<'PY'
import json
p='.git/shipcraft/runs.jsonl';rs=[json.loads(s) for s in open(p)]
for r in rs: r.pop('after_green_ci',None)
open(p,'w').writelines(json.dumps(r)+'\n' for r in rs)
PY
        ;; esac
      rev_cfg changes
      if [ "$c" = reuse-cross ]; then PRN=$(H prnum "$ST" "$BR"); kind=review-pr; fi
      i63_run
      chk 'same keys reuse approval without invoking reviewer again' eq "$(rev_n)" 1
      chk 'cached approval wins over changed fake reviewer' rc_zero
      chk 'reused row omits after_green_ci' i63_row false reused
      chk 'reuse keeps row count and existing lookup keys' "$PY" - <<'PYROWS'
import json
rs=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl') if json.loads(s)['layer']=='review']
assert len(rs)==2,rs
for k in ('diff_sha256','text_sha256','agent','result','code'):
 assert rs[0].get(k)==rs[1].get(k),(k,rs)
assert rs[0].get('diff_sha256') and rs[0].get('text_sha256'),rs
PYROWS
      chk 'fresh original records origin (reuse test must also discriminate pre-item)' "$PY" - "$CW/rows63-first" "$after" <<'PY'
import json,sys
r=[json.loads(s) for s in open(sys.argv[1]) if json.loads(s)['layer']=='review'][-1]
assert r.get('after_green_ci') is (sys.argv[2]=='true'),r
PY
      pass; return ;;
  esac
  chk 'fresh review row records actual CI origin' i63_row "$after"
  pass
}
