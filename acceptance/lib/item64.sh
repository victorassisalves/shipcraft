# Item 64: public config readers, reviewer argv/rows and phase guidance.
# All mutations/commands below target disposable acceptance projects, never this checkout.
i64_matrix() {
  "$PY" - "$@" <<'PY'
import json,re,sys
cases={}
def add(n,roles,path=None,minimum='2.20',extra=''):
 cases[n]=(roles,path,minimum,extra)
for role in ('red','green','review'):
 for tag,value,suffix in [
  ('number','42',''),('array','["codex"]',''),('bool','false',''),
  ('unknown','"CODEX"',''),('space-agent','"codex "',''),
  ('missing','{}','.agent'),('missing-model','{ model = "m" }','.agent'),
  ('agent-type','{ agent = 1 }','.agent'),('agent-unknown','{ agent = "other" }','.agent'),
  ('unknown-key','{ agent = "codex", flavor = "x" }','.flavor'),
  ('unknown-keys','{ agent = "codex", zebra = 1, alpha = 2 }','.alpha')]:
  add(role+'-'+tag,role+' = '+value,'roles.'+role+suffix)
 for field in ('model','effort'):
  for tag,value in [('number','5'),('bool','true'),('array','[]'),('table','{}'),('empty','""'),('dash','"-high"'),
    ('space','"a b"'),('tab','"a\\tb"'),('newline','"a\\nb"'),('nul','"a\\u0000b"'),('del','"a\\u007Fb"'),
    ('nbsp','"a\\u00A0b"'),('nel','"a\\u0085b"'),('nbsp-edge','"\u00a0high"'),('nel-edge','"high\u0085"')]:
   add(role+'-'+field+'-'+tag,role+' = { agent = "codex", '+field+' = '+value+' }','roles.'+role+'.'+field)
 for agent,efforts in [('codex',['max','HIGH']),('claude',['minimal','MAX']),('gemini',['low','max'])]:
  for effort in efforts:
   add(role+'-'+agent+'-'+effort,role+' = { agent = "'+agent+'", effort = "'+effort+'" }','roles.'+role+'.effort')
# Priority fixtures contain multiple faults, so getting the first key right is discriminating.
add('order-red','review = 1\ngreen = 2\nred = 3','roles.red')
add('order-green','review = 1\ngreen = 2\nred = "codex"','roles.green')
add('order-review','review = 1\ngreen = "gemini"\nred = "claude"','roles.review')
add('order-agent','red = { model = "", effort = "", z = 1 }','roles.red.agent')
add('order-agent-unknown','red = { agent = "bad", a = 1, model = "", effort = "" }','roles.red.agent')
add('order-member','green = { agent = "codex", z = 1, a = 2, model = "", effort = "" }','roles.green.a')
add('order-model','review = { agent = "codex", model = "", effort = "" }','roles.review.model')
add('order-effort','review = { agent = "codex", model = "m", effort = "" }','roles.review.effort')
for n,m in [('absent',None),('old','2.19'),('patch-old','2.19.999')]:
 for form,role in [('red','red = "codex"'),('green','green = "claude"'),('table','review = { agent = "gemini" }')]:
  add('min-'+n+'-'+form,role,'shipcraft_min',m)
add('order-min','red = 7\ngreen = false','shipcraft_min','2.19')
add('order-execution','red = 7','ci','2.19','execution')
add('order-execution-review','red = 7','review','2.19','execution-review')
add('order-structure','red = 7','ci_timeout','2.19','structure')
add('order-parse','red = 7',None,'2.19','parse')
add('order-legacy','red = 7',None,'2.19','legacy')
add('order-future','red = 7',None,'999.0','future')
if sys.argv[1]=='list':
 for n in cases: print('v1-64.invalid-'+n)
else:
 roles,path,minimum,extra=cases[sys.argv[1]]
 p='.shipcraft.toml';s=open(p).read();s=re.sub(r'(?m)^shipcraft_min\s*=.*\n','',s)
 s=re.sub(r'(?ms)^\[roles(?:\.[^\]]+)?\]\n.*?(?=^\[|\Z)','',s)
 if minimum is not None:s='shipcraft_min = '+json.dumps(minimum)+'\n'+s
 if extra=='execution': s=re.sub(r'(?m)^ci\s*=.*$', 'ci = "bad64"',s)
 if extra=='execution-review':s=re.sub(r'(?m)^review\s*=.*$', 'review = "bad-review64"',s)
 if extra=='structure':s=re.sub(r'(?m)^ci_timeout\s*=.*$', 'ci_timeout = "bad64"',s)
 if extra=='legacy':s='verifica = "true"\n'+s
 s+='\n[roles]\n'+roles+'\n'
 if extra=='parse':s+='broken [\n'
 open(p,'w').write(s)
 print(path or '')
PY
}
item64_cases() {
  local PY=${PY:-python3} c a e
  i64_matrix list
  for c in status-default status-off status-strings status-inline status-section status-dotted status-model status-effort status-table-agent \
    min-valid min-patch min-leading-zero min-legacy min-no-roles \
    hook-invalid hook-staged-invalid hook-staged-valid hook-log-fails \
    reader-ci reader-pr reader-review reader-merge reader-base reader-head \
    phase-declared phase-declared-table red-unset red-set redo-unset redo-set red-refused redo-refused red-log-fails \
    reuse-same reuse-agent reuse-model reuse-effort reuse-null reuse-legacy reuse-wrong-agent reuse-wrong-model reuse-wrong-effort reuse-wrong-null-agent reuse-wrong-model-array reuse-wrong-effort-bool reuse-wrong-agent-object \
    row-pr row-pr-ci row-review-pr row-error row-error-pr row-no-start row-no-start-pr row-publish-fails row-reused-publish-fails \
    init-codex init-claude init-gemini init-none init-preserve version; do echo "v1-64.$c"; done
  for a in codex claude gemini; do
    for c in table string agent-only model-only section dotted base; do echo "v1-64.argv-$a-$c"; done
  done
  for a in codex claude; do
    if [ "$a" = codex ]; then e='minimal low medium high xhigh'; else e='low medium high xhigh max'; fi
    for c in $e; do echo "v1-64.effort-$a-$c"; done
  done
}
i64_config() { # replace roles, preserving all other init settings
  "$PY" - "$1" "${2:-2.20}" <<'PY'
import re,sys,json
p='.shipcraft.toml';s=open(p).read();s=re.sub(r'(?m)^shipcraft_min\s*=.*\n','',s)
s=re.sub(r'(?ms)^\[roles(?:\.[^\]]+)?\]\n.*?(?=^\[|\Z)','',s)
if sys.argv[2]!='absent':s='shipcraft_min = '+json.dumps(sys.argv[2])+'\n'+s
s=(sys.argv[1]+'\n'+s) if sys.argv[1].startswith('roles.') else (s+'\n'+sys.argv[1]+'\n');open(p,'w').write(s)
PY
}
i64_snapshot() { # Invalid-config fixtures use git plumbing; no hook/settings/lock is edited.
  git add -A || fail 'fixture index'
  local tree sha
  tree=$(git write-tree) || fail 'fixture tree'
  sha=$(printf '%s\n' "$1" | git commit-tree "$tree" -p HEAD) || fail 'fixture snapshot'
  git update-ref HEAD "$sha" || fail 'fixture ref'
}
i64_refusal() {
  chk 'config refused' rc_nonzero
  chk 'validation writes no lock' no_lock
  msg_check || fail "$MSGERR"
  chk 'three-line refusal; exact path is in the reason; no GREEN guidance' "$PY" - "$OUT" "${1:-}" <<'PY'
import pathlib,re,sys
s=pathlib.Path(sys.argv[1]).read_text();ls=[l for l in s.splitlines() if l.strip()][-3:]
assert [l.split(':',1)[0] for l in ls]==['shipcraft refused','Why','Next'],ls
if sys.argv[2]: assert re.search(r'(?<![\w.])'+re.escape(sys.argv[2])+r'(?![\w.])',ls[0]),(sys.argv[2],ls)
assert 'shipcraft: next: the GREEN' not in s,s
PY
}
i64_row() {
  "$PY" - "$1" "$2" "$3" "${4:-fresh}" <<'PY'
import json,sys
rs=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl') if json.loads(s).get('layer')=='review'];assert rs,'missing review row'
r=rs[-1];a,m,e,mode=sys.argv[1:]; m=None if m=='NULL' else m;e=None if e=='NULL' else e
assert r.get('agent')==a,r
assert 'model' in r and r['model']==m,('model',r)
assert 'effort' in r and r['effort']==e,('effort',r)
if mode=='reused':assert r.get('reused') is True and 'after_green_ci' not in r,r
else:
 assert r.get('reused') is not True and isinstance(r.get('after_green_ci'),bool),r
 if mode=='error':assert r['result']=='error' and r.get('code'),r
PY
}
i64_argv() {
  "$PY" - "$ST/reviewer.calls.jsonl" "$1" "$2" "$3" <<'PY'
import json,sys
r=json.loads(open(sys.argv[1]).readlines()[-1]);a,m,e=sys.argv[2:];argv=r['argv'];assert r['agent']==a,r
briefs=[v for k,v in r['files'].items() if k.endswith('/brief.md')];assert len(briefs)==1,r
assert 'SPEC-MARKER-5e1' in briefs[0] and 'diff-marker-4f9a' in briefs[0],briefs
# A prompt may name the brief or be its contents; it must follow every new option.
prompts=[i for i,v in enumerate(argv) if 'brief.md' in v or 'You are ' in v or 'What you are reviewing' in v]
assert prompts,('missing prompt',argv)
for flag,value in [(('--model' if a=='claude' else '-m'),m),(('--effort' if a=='claude' else '-c'),e if a=='claude' else 'model_reasoning_effort='+e)]:
 absent=(m=='NULL' if flag in ('-m','--model') else e=='NULL')
 if absent:
  if flag=='-c': assert not any(v.startswith('model_reasoning_effort=') for v in argv),argv
  else:assert flag not in argv,argv
 else:
  assert argv.count(flag)==1,(flag,argv)
  i=argv.index(flag);assert argv[i+1]==value and i+1<min(prompts),(flag,value,argv)
PY
}
i64_review_setup() {
  v1_start codex claude gemini
  CFGS='execution|ci|"off"
execution|review|"local"
review|spec|"docs/spec-produto.md"'
  pr_main
}
i64_review_ready() {
  i64_snapshot 'chore: roles64 base snapshot'
  git push -q origin main >> "$LOG" 2>&1 || fail 'fixture base push'
  git fetch -q origin >> "$LOG" 2>&1 || fail 'fixture fetch'
  BR=feature/alpha;git checkout -qb "$BR" || fail 'fixture feature branch'
  printf '# diff-marker-4f9a\ndef shout_marker(text):\n    return text.upper() + "!"\n' > shoutmod.py
  printf 'from shoutmod import shout_marker\n\ndef test_shout_marker():\n    assert shout_marker("hi") == "HI!"\n' > tests/test_shoutmod.py
  probe_write;i64_snapshot 'feat: shout'
  HEADSHA=$(head_rev);printf '%s\n' "$HEADSHA" > "$ST/sha"
}
i64_status() {
  run_cmd shipcraft status
  chk 'valid roles status' rc_zero
  chk 'exact roles line immediately follows unchanged layers line' "$PY" - "$OUT" "$1" <<'PY'
import sys,pathlib
ls=pathlib.Path(sys.argv[1]).read_text().splitlines();want='shipcraft: roles: '+sys.argv[2]
assert ls.count(want)==1,(want,ls)
i=ls.index(want);assert i>0 and ls[i-1].startswith('shipcraft: layers:'),ls
PY
}
i64_red_cmd() { shipcraft red "$@" 2> "$CW/red64-stderr"; }
i64_publish_fail() {
  mv "$CB/gh" "$CB/gh64-real"
  "$PY" - "$CB/gh" "$PY" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);p.write_text('#!'+sys.argv[2]+'\n'+'''import os,sys
from pathlib import Path
a=sys.argv[1:]
if a[:2] in (['pr','comment'],['pr','review']) or (a[:1]==['api'] and any('/comments' in s or s.endswith('/reviews') for s in a)):
 Path(__file__).with_name('publish64-failed').touch();sys.exit(1)
p=Path(__file__).with_name('gh64-real');os.execv(str(p),[str(p),*a])
''');p.chmod(0o755)
PY
}
item64_case() {
  local c=${CASE#v1-64.} a=codex m=NULL e=NULL role='' path='' form='' want='' n=2
  EXPECT="item 64: $c"
  case "$c" in
    version)
      chk 'version follows Cargo manifest including build suffix' "$PY" - "$ACEITE/../nucleo/Cargo.toml" "$(command -v shipcraft)" <<'PYVERSION'
import re,subprocess,sys
try:import tomllib
except ImportError:import tomli as tomllib
v=tomllib.load(open(sys.argv[1],'rb'))['package']['version'];p=subprocess.run([sys.argv[2],'--version'],capture_output=True,text=True)
assert p.returncode==0 and re.fullmatch(r'shipcraft '+re.escape(v)+r' \([0-9a-f]{12}\)\n',p.stdout),(v,p)
PYVERSION
      pass;return ;;
    invalid-*)
      v1_start codex; setup_init
      path=$(i64_matrix "${c#invalid-}") || fail 'fixture matrix'
      run_cmd shipcraft status
      i64_refusal "$path"
      case "$c" in
        invalid-order-parse) chk 'parse error wins' out_has 'parse|TOML' ;;
        invalid-order-legacy) chk 'legacy migration wins' out_has 'legacy config key.*verifica' ;;
        invalid-order-future) chk 'existing minimum wins' out_has '999.0' ;;
      esac
      # A second reader must give the same diagnosis, before any suite is run.
      git add .shipcraft.toml;run_cmd shipcraft check;i64_refusal "$path"
      case "$c" in *order-execution) want=execution-invalid ;; *order-execution-review) want=execution-invalid ;; *order-future) want=shipcraft-min ;; *) want=config-invalid ;; esac
      chk 'hook refusal code' i47_code hook "$want"
      pass; return ;;
    init-*)
      case "$c" in init-none) v1_start ;; init-claude) v1_start claude ;; init-gemini) v1_start gemini ;; *) v1_start codex claude gemini ;; esac
      must_accept 'init' cmd shipcraft init
      cp .shipcraft.toml "$CW/init64";cp AGENTS.md "$CW/agents64"
      [ "$c" != init-preserve ] || must_accept 'init again' cmd shipcraft init
      chk 'init default is string, no RED/GREEN; minimum follows Cargo' "$PY" - "$c" "$ACEITE/../nucleo/Cargo.toml" <<'PY'
import sys
try:import tomllib
except ImportError:import tomli as tomllib
c=tomllib.load(open('.shipcraft.toml','rb'));v=tomllib.load(open(sys.argv[2],'rb'))['package']['version']
a={'init-claude':'claude','init-gemini':'gemini'}.get(sys.argv[1],'codex')
assert 'red' not in c.get('roles',{}) and 'green' not in c.get('roles',{}),c
if sys.argv[1]=='init-none':assert c['execution']['review']=='off',c
else:assert c['roles']['review']==a,c
assert c['shipcraft_min']=='.'.join(v.split('.')[:2]),c
PY
      chk 'reinit preserves config' cmp .shipcraft.toml "$CW/init64"
      chk 'reinit preserves agent block' cmp AGENTS.md "$CW/agents64"
      pass;return ;;
    status-*|min-*)
      v1_start codex; setup_init
      want="red not set (the orchestrator's choice); green not set (the orchestrator's choice); review codex"
      case "$c" in
        status-default) i64_config '' absent ;;
        status-off) tset execution review '"off"' ;;
        status-strings) i64_config $'[roles]\nred = "gemini"\ngreen = "claude"\nreview = "codex"';want='red gemini; green claude; review codex' ;;
        status-inline) i64_config $'[roles]\nred = {agent="codex",model="r64",effort="minimal"}\ngreen = {agent="claude",model="g64",effort="max"}\nreview = {agent="gemini",model="v64"}';want='red codex (r64, effort minimal); green claude (g64, effort max); review gemini (v64)' ;;
        status-section) i64_config $'[roles.review]\nagent="claude"\nmodel="m64"\neffort="xhigh"';want="red not set (the orchestrator's choice); green not set (the orchestrator's choice); review claude (m64, effort xhigh)" ;;
        status-dotted) i64_config $'roles.red.agent="gemini"\nroles.green.agent="claude"\nroles.review.agent="codex"';want='red gemini; green claude; review codex' ;;
        status-model) i64_config $'[roles]\nreview={agent="codex",model="opaque/模型:v64"}';want="red not set (the orchestrator's choice); green not set (the orchestrator's choice); review codex (opaque/模型:v64)" ;;
        status-effort) i64_config $'[roles]\nreview={agent="claude",effort="max"}';want="red not set (the orchestrator's choice); green not set (the orchestrator's choice); review claude (effort max)" ;;
        status-table-agent) i64_config $'[roles]\nred={agent="codex"}\ngreen={agent="claude"}\nreview={agent="gemini"}';want='red codex; green claude; review gemini' ;;
        min-valid|min-patch|min-leading-zero)
          local minimum=2.20;[ "$c" != min-patch ] || minimum=2.20.0;[ "$c" != min-leading-zero ] || minimum=02.020
          i64_config $'[roles]\nreview={agent="codex"}' "$minimum" ;;
        min-legacy|min-no-roles)
          role=$'[roles]\nreview="codex"';[ "$c" != min-no-roles ] || role=''
          i64_config "$role" 2.1
          run_cmd shipcraft status;chk 'old config unaffected' rc_zero;pass;return ;;
      esac
      i64_status "$want";chk 'status never starts a declared phase' eq "$(rev_n)" 0
      pass;return ;;
    hook-*|reader-*)
      v1_start codex;CFGS='execution|review|"off"';pr_main
      cp .shipcraft.toml "$CW/valid64"
      i64_config $'[roles]\nred="unknown64"' 2.20
      case "$c" in
        hook-staged-valid) cp .shipcraft.toml "$CW/bad64";cp "$CW/valid64" .shipcraft.toml;git add .shipcraft.toml;cp "$CW/bad64" .shipcraft.toml
          run_cmd shipcraft check;chk 'valid index wins over invalid tree' rc_zero
          run_cmd shipcraft status;i64_refusal roles.red;pass;return ;;
        hook-*) git add .shipcraft.toml
          [ "$c" != hook-staged-invalid ] || cp "$CW/valid64" .shipcraft.toml
          if [ "$c" = hook-log-fails ];then rm -f .git/shipcraft/runs.jsonl;mkdir .git/shipcraft/runs.jsonl;fi
          run_cmd shipcraft check;i64_refusal roles.red
          [ "$c" = hook-log-fails ] || chk 'hook config-invalid measurement' i47_code hook config-invalid
          pass;return ;;
        reader-head) cp .shipcraft.toml "$CW/bad64";cp "$CW/valid64" .shipcraft.toml;pr_feature;cp "$CW/bad64" .shipcraft.toml
          run_cmd shipcraft ci --base "$BASE";chk 'CI uses committed config' rc_zero
          run_cmd shipcraft status;i64_refusal roles.red;pass;return ;;
      esac
      i64_snapshot 'chore: invalid base fixture';git push -q origin main >> "$LOG" 2>&1;git fetch -q origin
      BASE=$(head_rev);git checkout -qb feature/roles64;printf 'docs64\n' > docs/item64.md;i64_snapshot 'docs: head fixture'
      cp "$CW/valid64" .shipcraft.toml
      [ "$c" != reader-base ] || i64_snapshot 'chore: valid HEAD with invalid base'
      case "$c" in
        reader-ci) run_cmd shipcraft ci --base "$BASE" ;;
        reader-pr|reader-base) shipcraft_pr ;;
        reader-review) run_cmd shipcraft review ;;
        reader-merge) pr_outside feature/roles64;run_cmd shipcraft merge "$PRN" ;;
      esac
      i64_refusal roles.red;pass;return ;;
    phase-declared|phase-declared-table)
      v1_start codex claude gemini;setup_init
      if [ "$c" = phase-declared ];then i64_config $'[roles]\nred="gemini"\ngreen="claude"'
      else i64_config $'[roles]\nred={agent="gemini",model="red64"}\ngreen={agent="claude",effort="max"}';fi
      must_accept 'valid declarative phase roles' commit commit_all 'chore: phase choices'
      BASE=$(head_rev);L stub;L spec_test
      must_accept 'RED is not restricted to declared author agent' cmd shipcraft red
      must_accept 'RED contract commit' commit commit_all 'test: phase contract'
      L implement
      must_accept 'GREEN author is not checked against roles' commit commit_all 'feat: phase implementation'
      must_accept 'CI validates roles and closed contract' cmd shipcraft ci --base "$BASE"
      chk 'phase agents are never started' eq "$(rev_n)" 0
      pass;return ;;
    red-*|redo-*)
      v1_start codex;setup_init
      case "$c" in *-set) i64_config $'[roles]\ngreen={agent="claude",model="green64",effort="max"}' ;; esac
      L stub;L spec_test
      case "$c" in
        redo-*) must_accept 'initial RED accepts the declared green role' cmd shipcraft red;must_accept 'RED fixture commit' commit commit_all 'test: RED64'
          printf '\n\ndef test_red64_boundary():\n    assert slugify("X") == "x"\n' >> "$TESTFILE" ;;
      esac
      case "$c" in red-refused) L implement ;; redo-refused) printf '\nthis is invalid python !!!\n' >> "$TESTFILE" ;; esac
      if [ "$c" = red-log-fails ];then rm -f .git/shipcraft/runs.jsonl;mkdir .git/shipcraft/runs.jsonl;fi
      case "$c" in redo-*) run_cmd i64_red_cmd --redo ;; *) run_cmd i64_red_cmd ;; esac
      case "$c" in *refused) chk 'RED refuses' rc_nonzero;chk 'refusal has no success guidance' out_hasnt 'shipcraft: next: the GREEN';pass;return ;; esac
      chk 'RED succeeded despite optional log write failure' rc_zero
      want='shipcraft: next: the GREEN, in a new session ([roles] green not set)'
      case "$c" in *-set) want='shipcraft: next: the GREEN, in a new session (claude (green64, effort max), [roles] green)' ;; esac
      chk 'success guidance is exactly the last stdout line, once' "$PY" - "$OUT" "$want" <<'PY'
import pathlib,sys
s=pathlib.Path(sys.argv[1]).read_text();assert s.splitlines()[-1]==sys.argv[2] and s.splitlines().count(sys.argv[2])==1,s
PY
      chk 'RED did not start GREEN' eq "$(rev_n)" 0;pass;return ;;
  esac
  # Review launch, fresh rows and reuse all use item 63's fake providers and base config.
  i64_review_setup
  case "$c" in
    argv-*) a=${c#argv-};form=${a#*-};a=${a%%-*};m=model64;e=high
      case "$form" in string|agent-only) m=NULL;e=NULL ;; model-only) e=NULL ;; esac
      [ "$a" != gemini ] || e=NULL ;;
    effort-*) a=${c#effort-};e=${a#*-};a=${a%%-*};form=table ;;
    row-*) form=table;m=model64;e=medium ;;
    reuse-*) form=table;m=model64;e=high
      case "$c" in reuse-legacy|reuse-wrong-*) form=string;m=NULL;e=NULL ;; reuse-null) form=agent-only;m=NULL;e=NULL ;; esac ;;
  esac
  role="agent=\"$a\"";[ "$m" = NULL ] || role="$role, model=\"$m\"";[ "$e" = NULL ] || role="$role, effort=\"$e\""
  case "$form" in
    string) i64_config "$(printf '[roles]\nreview="%s"' "$a")" 2.1 ;;
    section) i64_config "$(printf '[roles.review]\n%s' "${role//, /$'\n'}")" ;;
    dotted) i64_config "$(printf '%s\n' "${role//, /$'\n'}" | sed 's/^/roles.review./')" ;;
    *) i64_config "$(printf '[roles]\nreview={%s}' "$role")" ;;
  esac
  if [ "$c" = row-pr-ci ];then tset execution ci '"local"';fi
  i64_review_ready
  if [ "$form" = base ];then
    i64_config $'[roles]\nreview={agent="claude",model="wrong-head64",effort="max"}'
    i64_snapshot 'chore: head roles differ from base'
    HEADSHA=$(head_rev);printf '%s\n' "$HEADSHA" > "$ST/sha"
  fi
  case "$c" in
    row-pr|row-pr-ci) shipcraft_pr ;;
    row-review-pr|row-error-pr|row-no-start-pr|row-publish-fails|row-reused-publish-fails|reuse-*)
      pr_outside "$BR"
      [ "$c" != row-publish-fails ] || i64_publish_fail
      case "$c" in row-error-pr) rev_cfg exit1 ;; row-no-start-pr) printf '#!/no/such/interpreter64\n' > "$CB/codex";chmod +x "$CB/codex" ;; esac
      run_cmd TMO 180 shipcraft review --pr "$PRN" ;;
    row-error) rev_cfg exit1;run_cmd TMO 180 shipcraft review ;;
    row-no-start) printf '#!/no/such/interpreter64\n' > "$CB/codex";chmod +x "$CB/codex";run_cmd TMO 180 shipcraft review ;;
    *) run_cmd TMO 180 shipcraft review ;;
  esac
  case "$c" in
    row-error|row-error-pr|row-no-start|row-no-start-pr)
      local expected_calls=1
      case "$c" in row-no-start*) expected_calls=0 ;; esac
      chk 'CLI rejection/start failure is not retried' eq "$(rev_n)" "$expected_calls"
      chk 'review error retains requested fields' i64_row "$a" "$m" "$e" error;pass;return ;;
    row-publish-fails) chk 'publication attempted after reviewer' test -f "$CB/publish64-failed";chk 'publication failed' rc_nonzero ;;
    *) chk 'first review succeeds' rc_zero ;;
  esac
  case "$c" in
    reuse-*|row-reused-publish-fails)
      # Alter only public JSONL metadata: each candidate still has the exact diff/text keys.
      "$PY" - "$c" <<'PY'
import json,sys
p='.git/shipcraft/runs.jsonl';rs=[json.loads(l) for l in open(p)];c=sys.argv[1]
for r in rs:
 if r.get('layer')!='review':continue
 if c=='reuse-agent':r['agent']='claude'
 if c=='reuse-model':r['model']='other-model64'
 if c=='reuse-effort':r['effort']='low'
 if c=='reuse-null':r.update(model=None,effort=None)
 if c=='reuse-legacy':r.pop('model',None);r.pop('effort',None)
 if c.startswith('reuse-wrong-'):
  field=c.removeprefix('reuse-wrong-')
  if field=='null-agent':r['agent']=None
  elif field.endswith('-array'):r[field.split('-')[0]]=[]
  elif field.endswith('-bool'):r[field.split('-')[0]]=False
  elif field.endswith('-object'):r[field.split('-')[0]]={}
  else:r[field]=7
open(p,'w').writelines(json.dumps(r)+'\n' for r in rs)
PY
      case "$c" in reuse-same|reuse-null|reuse-legacy|row-reused-publish-fails) n=1;want=reused ;; *) n=2;want=fresh ;; esac
      # Different provider output proves reuse preserves source verdict; nonreuse must see changes.
      rev_cfg changes
      [ "$c" != row-reused-publish-fails ] || i64_publish_fail
      run_cmd TMO 180 shipcraft review --pr "$PRN"
      chk 'reuse matches agent AND model AND effort, with typed source fields' eq "$(rev_n)" "$n"
      if [ "$c" = row-reused-publish-fails ];then chk 'reused publication attempted' test -f "$CB/publish64-failed";chk 'publication refused' rc_nonzero
      elif [ "$n" = 1 ];then chk 'source approval reused' rc_zero
      else chk 'new review sees CHANGES REQUESTED' rc_nonzero;fi
      chk 'latest row carries chosen/source model and effort' i64_row "$a" "$m" "$e" "$want"
      pass;return ;;
  esac
  case "$c" in argv-*|effort-*) chk 'separate options before prompt; common brief retained' i64_argv "$a" "$m" "$e" ;; esac
  chk 'fresh review row records model/effort, including null' i64_row "$a" "$m" "$e"
  pass
}
