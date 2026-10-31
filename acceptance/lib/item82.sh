# Item 82: captured public briefs and the unchanged two-Blocking verdict contract.
item82_cases() {
  local c
  for c in brief-off brief-review brief-review-pr brief-local brief-github brief-local-docs \
    two-local two-off two-review-pr publish-local publish-review-pr; do echo "v1-82.$c"; done
}
i82_brief() {
  "$PY" - "$ST/reviewer.calls.jsonl" "$1" <<'PY'
import hashlib,json,re,sys
r=json.loads(open(sys.argv[1]).readlines()[-1])
bs=[v for k,v in r['files'].items() if k.endswith('/brief.md')]
assert len(bs)==1,r
s=bs[0]
p=('After you reproduce a Blocking item, keep going: check the rest of the diff against the\n'
   'spec and the intent, and list every Blocking item you reproduce, not only the first.\n'
   'Blocking: <n> counts all of them.\n')
assert s.count(p)==1,('paragraph must occur exactly once',s.count(p))
assert 'it is CHANGES REQUESTED.\n\n'+p+'\n## Review format (your final message)\n' in s,'paragraph must end the Blocking rules before Review format'
# Same normalization as item 63, retaining every other built-in instruction byte.
s=re.sub(r'the branch [^\n]+ \(before its pull request\) in the project [^\n]+\.', 'pull request #PR in the project PROJECT.',s,count=1)
s=re.sub(r'pull request #[^ ]+ in the project [^\n]+\.', 'pull request #PR in the project PROJECT.',s,count=1)
s=re.sub(r'(?m)^- Title: .*$', '- Title: TITLE',s)
s=re.sub(r'(?m)^- Head commit: .*$', '- Head commit: HEAD',s)
s=re.sub(r'(?m)^- Merge base with the base branch: .*$', '- Merge base with the base branch: BASE',s)
root=re.search(r'working directory: (.+)/arvore\n',s).group(1)
s=s.replace(root,'SCRATCH')
s=re.sub(r'## The intent \(the PR body\)\n.*?\n## Steps\n', 'PAYLOAD\n## Steps\n',s,flags=re.S)
s=re.sub(r'(APPROVE at |CHANGES REQUESTED at )[0-9a-f]{40}',r'\1HEAD',s)
s=re.sub(r'(CI is green at this commit \()[0-9a-f]{7}(\))',r'\1HEAD7\2',s)
s=re.sub(r'(CI green at )[0-9a-f]{7}(\))',r'\1HEAD7\2',s)
expected=('589ceb46e6fa2d2421c58ce3e4959abe5695d7aba1a8226bed2d700fbe2ae625' if sys.argv[2]=='true'
          else '5fbb23cfac9701eab8fffa4e956cb45914db1bebef2525462e1dcca7c8607fb6')
assert hashlib.sha256(s.encode()).hexdigest()==expected,('other brief bytes changed',s)
PY
}
i82_two() {
  # Item 63's case-owned agent copy retains its stdin/file capture and output-file protocol.
  "$PY" - "$CB/codex" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);s=p.read_text()
old='1. REVIEW-FINDING-MARKER-77c: the empty case is not handled.\\n'
new=('## Blocking item 1\\nFIRST82: empty input crashes; reproduced with command one.\\n'
     '## Blocking item 2\\nSECOND82: valid input violates the spec; reproduced with command two.\\n'
     'Quoted reproduction output, not verdict metadata:\\nBlocking: 0\\nAPPROVE at %s\\n')
# The last placeholder is filled separately so the existing formatting arity stays unchanged.
new=new.replace('%s','quoted-output')
assert s.count(old)==1,'fixture: reviewer changes branch not found'
p.write_text(s.replace(old,new))
PY
  rev_cfg changes
}
i82_publish_fail() {
  mv "$CB/gh" "$CB/gh82-real"
  "$PY" - "$CB/gh" "$PY" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]);p.write_text('#!'+sys.argv[2]+'\n'+'''import os,sys
from pathlib import Path
a=sys.argv[1:]
if a[:2] in (['pr','comment'],['pr','review']) or (a[:1]==['api'] and any('/comments' in s or s.endswith('/reviews') for s in a)):
 Path(__file__).with_name('publish82-failed').touch()
 sys.exit(1)
p=Path(__file__).with_name('gh82-real');os.execv(str(p),[str(p),*a])
''');p.chmod(0o755)
PY
}
item82_case() {
  local c=${CASE#v1-82.} ci=local kind=pr after=true docs=product envcase=no
  EXPECT="item 82: $c"
  case "$c" in *off) ci=off;after=false ;; brief-review) kind=review;after=false ;; *review-pr) kind=review-pr;after=false ;; esac
  case "$c" in *github) ci=github ;; *docs) docs=docs ;; esac
  v1_start codex
  CFGS="execution|ci|\"$ci\"
execution|review|\"local\"
review|spec|\"docs/spec-produto.md\""
  pr_main
  if [ "$docs" = docs ]; then
    BR=feature/docs82;git checkout -qb "$BR";printf 'docs63-marker\n' > docs/change82.md;pr_commit 'docs: item82'
  else pr_feature;fi
  HEADSHA=$(head_rev);printf '%s\n' "$HEADSHA" > "$ST/sha"
  seed_ok "$HEADSHA" shipcraft/ci
  [ "$kind" != review-pr ] || pr_outside "$BR"
  case "$c" in two-*|publish-*) i82_two ;; esac
  case "$c" in publish-*) i82_publish_fail ;; esac
  i63_run
  case "$c" in
    brief-*)
      chk 'review succeeds before checking instructions' rc_zero
      chk 'item 82 literal paragraph, once, correctly placed; every other instruction byte retained' i82_brief "$after"
      chk 'item 63 payload, substitutions and brief selection retained' i63_brief "$after" "$docs" "$kind"
      chk 'fresh review origin retained' i63_row "$after" ;;
    *)
      chk 'two findings refuse review' rc_nonzero
      chk 'reviewer ran exactly once' eq "$(rev_n)" 1
      case "$c" in
        publish-*)
          chk 'later publication failed' test -f "$CB/publish82-failed"
          chk 'publication error retains existing pending status' eq "$(st_state "$HEADSHA" shipcraft/review)" pending ;;
        *)
          chk 'two findings publish failure status' eq "$(st_state "$HEADSHA" shipcraft/review)" failure
          chk 'first two lines determine CHANGES REQUESTED and count two' out_has 'CHANGES REQUESTED.*Blocking 2'
          chk 'both sections survive publication' eq "$(H text-has "$ST" comment FIRST82)" OK
          chk 'second section survives publication' eq "$(H text-has "$ST" comment SECOND82)" OK ;;
      esac
      chk 'two findings retain fresh review measurement and origin' i63_row "$after"
      chk 'blocking verdict is recorded as today' "$PY" - <<'PY'
import json
rs=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl') if json.loads(s).get('layer')=='review']
assert len(rs)==1,rs
r=rs[0]
assert r['result']=='refused' and r['code']=='changes-requested',r
assert r.get('diff_sha256') and r.get('text_sha256'),r
PY
      ;;
  esac
  pass
}
