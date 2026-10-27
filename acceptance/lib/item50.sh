# Item 50: exercise public PR summaries and measurements only.
item50_cases() {
  for c in reproduction config config-hint config-shape metrics hint shape explicit nested lookalikes rename population minimum missing review-refused; do echo "v1-50.$c"; done
}
i50_lock() {
  "$PY" - "$1" "${2:-600}" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1]);p.parent.mkdir(parents=True,exist_ok=True)
d=dict(format=3,state='closed',files={},cases=[],failing_at_red=[],seal='')
d['seal']=hashlib.sha256(json.dumps(d,separators=(',',':')).encode()).hexdigest()
p.write_text(json.dumps(d,indent=2)+'\n'*int(sys.argv[2]))
PY
}
item50_case() {
  local c="${CASE#v1-50.}" f i n=0 a=1 r=0
  EXPECT="item 50: $c"
  N=10
  CFGS='pr|shape_lines|10
pr|warn_lines|40'
  case "$c" in population|minimum|missing) CFGS='pr|warn_lines|40' ;; esac
  case "$c" in config-shape) CFGS='pr|shape_lines|100
pr|warn_lines|40' ;; esac
  sz_start
  i24_write anchor.py 1 anchor
  git add anchor.py
  if [ "$c" = reproduction ]; then
    L stub; L spec_test
  else
    i50_lock .shipcraft/locks/new.json 1
  fi
  case "$c" in
    rename) i24_write old.py 10 a ;;
    population) for i in $(seq 1 40); do i24_write "product/p$i.py" 10 a; i50_lock ".shipcraft/locks/base$i.json" 1000; done ;;
    minimum)
      # Exactly 19 eligible text files, including the untouched base target.
      "$PY" - <<'PY'
import subprocess,fnmatch,pathlib
try: import tomllib
except ImportError: import tomli as tomllib
g=tomllib.load(open('.shipcraft.toml','rb'))['test_globs']
ps=subprocess.check_output(['git','ls-files','-z']).decode().split('\0')
ps=[p for p in ps if p and p!='.shipcraft.toml' and not p.startswith('.shipcraft/') and not any(fnmatch.fnmatchcase(p,x) for x in g)]
for i in range(19-len(ps)):
 p=pathlib.Path(f'product/p{i}.py');p.parent.mkdir(exist_ok=True);p.write_text('x=1\n'*10)
PY
      i50_lock .shipcraft/locks/base.json ;;
    missing) git config maintenance.auto false; git config gc.auto 0; i24_write .shipcraft/cache/missing.txt 777 unique_missing ;;
  esac
  must_accept 'fixture base commit' commit commit_nv 'chore: item 50 base'
  git push -q origin main || fail 'push base'
  git fetch -q origin
  sz_branch
  if [ "$c" = reproduction ]; then
    must_accept 'real RED creates the new lock' cmd shipcraft red
    sz_commit 'test: real RED'
    L implement
    sz_commit 'feat: real GREEN'
    # This reproduction's only product path is the implementation already tested
    # by the existing language fixture. Native numstat fixes its exact line delta.
    read -r a r f < <(git diff --numstat main HEAD -- textutil.py)
  fi
  case "$c" in
    reproduction) : ;;
    nested) for f in packages/web/.shipcraft.toml src/.shipcraft/x.py; do i24_write "$f" 11 a; done; a=22; n=2 ;;
    lookalikes) for f in .shipcrafted.py .shipcraft.toml.bak; do i24_write "$f" 11 a; done; a=22; n=2 ;;
    rename) mkdir -p .shipcraft; git mv old.py .shipcraft/old.py; i24_write .shipcraft/old.py 11 a; a=0 ;;
    explicit) i24_write product.py 11 a; i50_lock .shipcraft/locks/new.json; a=11; n=1 ;;
    population) i24_write product/p1.py 11 a; n=1 ;;
    minimum|missing) i24_write product.py 11 a; a=11 ;;
    config|config-hint|config-shape|metrics) printf '\n# root metadata changed\n' >> .shipcraft.toml; i24_write product.py 1 a
      if [ "$c" != config ]; then
        for i in $(seq 1 200); do echo '# excluded config line' >> .shipcraft.toml; done
      fi
      [ "$c" != metrics ] || i50_lock .shipcraft/locks/new.json ;;
    *) i24_write product.py 1 a; i50_lock .shipcraft/locks/new.json ;;
  esac
  if [ "$c" != reproduction ]; then must_accept 'fixture commit' commit commit_nv 'feat: item 50 change'; fi
  if [ "$c" = missing ]; then
    git -c maintenance.auto=false -c gc.auto=0 push -q origin "$BR" || fail 'fixture push'
    f=$(git rev-parse main:.shipcraft/cache/missing.txt)
    rm "$(git rev-parse --git-path objects)/${f:0:2}/${f:2}"
    git config core.repositoryformatversion 1
    git config extensions.partialClone origin
    git config remote.origin.promisor true
    chk 'ordinary product blob remains readable' env GIT_NO_LAZY_FETCH=1 git cat-file -e HEAD:product.py
    if GIT_NO_LAZY_FETCH=1 git cat-file -e "$f" 2>/dev/null; then fail 'fixture blob still readable'; fi
  fi
  [ "$c" != review-refused ] || rev_cfg changes
  cp .git/shipcraft/runs.jsonl "$CW/before"
  shipcraft_pr; HEAD=$(git rev-parse HEAD)
  if [ "$c" = review-refused ]; then chk 'later review refuses' rc_nonzero
  else chk 'PR succeeds' rc_zero; fi
  # Separate cases put each regression first, so a wrong Size does not mask it.
  case "$c" in
    metrics) chk 'filtered run-log product_lines' sz_jsonl 1 ;;
    hint|config-hint) chk 'large excluded file gives no split hint' eq "$(H size-warn "$ST")" NAO ;;
    shape|config-shape) chk 'large excluded file is never named' i24_none ;;
    explicit) i24_warn product.py new 11; chk 'only product warns' i24_json 1 ;;
    population) N=10; i24_warn product/p1.py 10 11; chk 'metadata cannot inflate p90' i24_json 1 ;;
    minimum|missing) chk 'excluded files cannot supply a threshold or break measurement' i24_none; chk 'no threshold' i24_json null ;;
    review-refused) chk 'failed review keeps filtered measurements' sz_jsonl 1 ;;
    *) chk 'filtered product Size' sz_size "$a" "$r" ;;
  esac
  chk 'product Size' sz_size "$a" "$r"
  chk 'filtered product_lines on CI and review' sz_jsonl "$((a+r))"
  case "$c" in minimum|missing) : ;; *) chk 'shape count' i24_json "$n" ;; esac
  chk 'old run-log bytes preserved' "$PY" - "$CW/before" <<'PY'
import pathlib,sys
assert pathlib.Path('.git/shipcraft/runs.jsonl').read_bytes().startswith(pathlib.Path(sys.argv[1]).read_bytes())
PY
  pass
}
