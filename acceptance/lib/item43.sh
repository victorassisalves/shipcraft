# Item 43: public lock wire format only; never inspect the implementation.
item43_cases() {
  local c state value
  for c in new seal cycle check-close rewrite legacy-close legacy-check legacy-changed mixed min min-patch ci-fails scanner red-log-fails legacy-close-log-fails; do echo "v1-43.$c"; done
  for state in open closed; do
    for value in bare uppercase short prefix whitespace; do echo "v1-43.$state-$value"; done
  done
  echo v1-43.legacy-prefixed
}
i43_json() {
  "$PY" - "$@" <<'PY'
import json,sys,hashlib,pathlib,re
mode,path,*args=sys.argv[1:]; p=pathlib.Path(path); d=json.loads(p.read_text())
def canonical(d):
 c=dict(format=d['format'],state=d['state'],files=dict(sorted(d['files'].items())),cases=d['cases'],failing_at_red=d['failing_at_red'])
 if d['format']==4: c.update((k,d[k]) for k in ('kind','reported_at','fixes_release'))
 c['seal']=''; return c
def seal(d):
 return hashlib.sha256(json.dumps(canonical(d),ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
if mode=='verify':
 assert d['format']==4,d
 for f in ['.shipcraft.toml','tests/test_slug.py','conftest.py','tests/helpers/util.py','tests/fixtures/expected.txt','pytest.ini','tests/fixtures/auth-data.txt']:
  assert f in d['files'],(f,d)
 for f,v in d['files'].items():
  assert re.fullmatch(r'sha256:[0-9a-f]{64}',v),(f,v)
  assert v=='sha256:'+hashlib.sha256(pathlib.Path(f).read_bytes()).hexdigest(),(f,v)
 assert d['seal']==seal(d),(d['seal'],seal(d))
 sys.exit()
if mode=='seal':
 assert d['format']==4,d
 assert d['seal']==seal(d),(d['seal'],seal(d)); sys.exit()
if mode=='same':
 old=json.loads(pathlib.Path(args[0]).read_text())
 assert d['state']=='closed',d
 assert {k:v for k,v in d.items() if k not in ('state','seal')}=={k:v for k,v in old.items() if k not in ('state','seal')},(old,d)
 assert d['seal']==seal(d),d
 sys.exit()
if mode=='fixture':
 d['format']=int(args[0]);
 if d['format'] in (2,3):
  for k in ('kind','reported_at','fixes_release'): d.pop(k,None)
 d['files']={f:('sha256:' if d['format']==3 else '')+v.removeprefix('sha256:') for f,v in d['files'].items()}
if mode=='bad':
 f=sorted(d['files'])[0]; v=d['files'][f].removeprefix('sha256:'); kind=args[0]
 d['files'][f]={'bare':v,'uppercase':'sha256:'+v.upper(),'short':'sha256:'+v[:63],'prefix':'sha512:'+v,'whitespace':'sha256:'+v+' ','legacy-prefixed':'sha256:'+v}[kind]
if mode!='rewrite': d['seal']=seal(d)
if mode=='rewrite':
 d=dict(reversed(list(d.items()))); d['files']=dict(reversed(list(d['files'].items())))
p.write_text(json.dumps(d,ensure_ascii=False,indent=4)+'\n')
PY
}
i43_save() { must_accept 'fixture commit bypasses hook' commit commit_nv "$1"; }
i43_refused() {
  chk 'refused' rc_nonzero
  msg_check || fail "$MSGERR"
  chk "measured $1" "$PY" - "$1" "$2" <<'PY'
import json,sys
rows=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl') if s.strip()]
r=[r for r in rows if r.get('layer')==sys.argv[2]][-1]
assert r.get('code')==sys.argv[1],r
PY
}
item43_case() {
  local c="${CASE#v1-43.}" lf fmt=3
  EXPECT="item 43: $c"
  if [ "$c" = scanner ] && ! command -v gitleaks >/dev/null 2>&1; then
    echo "SKIP: optional gitleaks absent" >> "$LOG"; pass; return
  fi
  v1_start codex
  setup_init
  case "$c" in min|min-patch)
    local minimum=2.1
    [ "$c" = min-patch ] && minimum=1.0
    tset '' shipcraft_min "\"$minimum\""
    must_accept 'existing lower minimum' commit commit_all 'chore: project minimum'
    cp .shipcraft.toml "$CW/config-before" ;;
  esac
  L stub
  case "$c" in
    new|scanner)
      tset '' test_globs '["**/test_*.py", "**/conftest.py", "tests/helpers/**", "tests/fixtures/**", "pytest.ini"]'
      must_accept 'runner config explicitly in locked globs' commit commit_all 'chore: runner config glob'
      BASE=$(head_rev)
      L support_spec
      printf '[pytest]\n' > pytest.ini
      printf 'ordinary fixture bytes\n' > tests/fixtures/auth-data.txt ;;
    *) L spec_test ;;
  esac
  if [ "$c" = red-log-fails ]; then
    mkdir -p .git/shipcraft
    [ ! -e .git/shipcraft/runs.jsonl ] || mv .git/shipcraft/runs.jsonl "$CW/old-runs"
    mkdir .git/shipcraft/runs.jsonl
  fi
  must_accept 'RED writes lock' cmd shipcraft red
  lf=$(lock_files_tree)
  case "$c" in
    new) chk 'all categories use exact prefixed byte digests and canonical seal' i43_json verify "$lf"; pass; return ;;
    scanner)
      mkdir -p "$CW/scan-locks"; cp "$lf" "$CW/scan-locks/lock.json"
      run_cmd gitleaks dir "$CW/scan-locks" --no-banner --redact --report-format json --report-path "$CW/gitleaks.json"
      chk 'default gitleaks finds no secret in auth path lock' rc_zero
      chk 'scanner report has no findings' "$PY" -c 'import json,sys; assert json.load(open(sys.argv[1])) == []' "$CW/gitleaks.json"
      pass; return ;;
    red-log-fails) chk 'failed log append preserves new lock format and seal' i43_json seal "$lf"; pass; return ;;
    seal) chk 'new format and canonical prefixed seal' i43_json seal "$lf"; pass; return ;;
    min|min-patch) chk 'RED preserves entire existing config' cmp .shipcraft.toml "$CW/config-before"; pass; return ;;
    legacy-*|closed-*|mixed) fmt=2 ;;
  esac
  i43_json fixture "$lf" "$fmt" || fail 'fixture format/seal'
  i43_save 'test: sealed RED fixture'
  case "$c" in
    open-*|closed-*|legacy-prefixed)
      case "$c" in closed-*)
        # Reach a genuine close before corrupting its value, avoiding a closed-red fixture.
        L implement
        must_accept 'fixture GREEN closes' commit commit_all 'feat: GREEN'
        i43_json fixture "$lf" 3
        i43_save 'test: valid format 3 closed baseline' ;;
      esac
      local kind="${c#*-}"; [ "$c" = legacy-prefixed ] && kind=legacy-prefixed
      i43_json bad "$lf" "$kind" || fail 'fixture invalid syntax with correct seal'
      i43_save 'test: malformed lock bypasses hook'
      BASE=$(head_rev)
      cp "$lf" "$CW/malformed-before"
      printf 'unrelated product change\n' > item43.txt; git add item43.txt
      run_cmd shipcraft check
      i43_refused lock-edited hook
      chk 'refusal preserves malformed lock bytes' cmp "$lf" "$CW/malformed-before"
      i43_save 'feat: unchanged malformed lock in later snapshot'
      run_cmd shipcraft ci --base "$BASE"
      i43_refused lock-edited ci
      chk 'CI refusal preserves malformed lock bytes' cmp "$lf" "$CW/malformed-before"
      pass; return ;;
    legacy-changed)
      printf '\n# changed locked test\n' >> "$TESTFILE"; git add "$TESTFILE"
      run_cmd shipcraft check; i43_refused test-changed hook
      i43_save 'test: changed legacy locked test'
      run_cmd shipcraft ci --base "$BASE"; i43_refused test-changed ci
      pass; return ;;
    rewrite)
      i43_json rewrite "$lf" || fail 'fixture rewrite'
      git add "$lf"
      must_accept 'whitespace and reversed keys are not an edit' cmd shipcraft check
      must_accept 'rewritten RED commit' commit commit_all 'test: JSON presentation only' ;;
  esac
  cp "$lf" "$CW/before-close"
  L implement
  if [ "$c" = legacy-close-log-fails ]; then
    mv .git/shipcraft/runs.jsonl "$CW/old-runs"
    mkdir .git/shipcraft/runs.jsonl
  fi
  case "$c" in
    check-close|legacy-check)
      git add -A
      must_accept 'direct check closes' cmd shipcraft check
      chk 'direct close preserves format and values' i43_json same "$lf" "$CW/before-close"
      i43_save 'feat: checked GREEN' ;;
    *)
      must_accept 'GREEN hook closes' commit commit_all 'feat: GREEN'
      chk 'post-commit close preserves format and values' i43_json same "$lf" "$CW/before-close" ;;
  esac
  if [ "$c" = legacy-close-log-fails ]; then
    chk 'failed close log append preserves closed legacy format and values' i43_json same "$lf" "$CW/before-close"
    pass; return
  fi
  if [ "$c" = mixed ]; then
    # Closed legacy lock and new open format 3 coexist, then both survive CI history.
    L shout_stub; L shout_test
    must_accept 'second RED' cmd shipcraft red
    local second; second=$(lock_files_tree | while read -r f; do [ "$f" = "$lf" ] || echo "$f"; done)
    i43_json fixture "$second" 3; i43_save 'test: mixed format RED'
    L shout_impl
    must_accept 'mixed GREEN closes' commit commit_all 'feat: shout'
  fi
  if [ "$c" = ci-fails ]; then
    L extra_fail_test
    i43_save 'test: unrelated failing suite after close'
    run_cmd shipcraft ci --base "$BASE"
    i43_refused suite-red ci
    chk 'later CI failure preserves closed lock' i43_json same "$lf" "$CW/before-close"
  else
    must_accept 'CI walks RED/GREEN PR range' cmd shipcraft ci --base "$BASE"
  fi
  pass
}
