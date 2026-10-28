# Item 54: exact PR text joins the file-version reuse key.
i54_review() { run_cmd TMO 180 shipcraft review --pr "$PRN"; }
i54_setup() {
  v1_start codex
  pr_main; pr_feature
  git rev-parse HEAD > "$ST/sha"
}
i54_rows() {
  "$PY" - "$ST/prs.json" "$1" "$ST/reviewer.calls.jsonl" <<'PY'
import hashlib,json,re,subprocess,sys
rows=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl')]
rows=[r for r in rows if r.get('layer')=='review']
assert rows,'missing review row'
mode=sys.argv[2]
if mode=='absent':
 assert 'text_sha256' not in rows[-1],rows[-1]
else:
 if mode in ('local','local-fresh'):
  call=json.loads(open(sys.argv[3]).readline())
  brief=next(v for k,v in call['files'].items() if k.endswith('/brief.md'))
  title='feat: shout'
  assert '- Title: '+title+'\n' in brief
  body=brief.split('## The intent (the PR body)\n\n',1)[1].split('\n\n## The spec of the project',1)[0]
 else:
  p=next(iter(json.load(open(sys.argv[1])).values())); title=p['title']; body=p['body']
 key=hashlib.sha256(title.encode()+b'\0'+body.encode()).hexdigest()
 for r in (rows if mode in ('both','local') else rows[-1:]):
  assert r.get('text_sha256')==key,('text_sha256',key,r)
  raw=subprocess.check_output(['git','diff','--raw','-z','--no-abbrev','--no-renames','--ignore-submodules=none','origin/main','HEAD'])
  assert r.get('diff_sha256')==hashlib.sha256(raw).hexdigest(),('diff meaning',r)
 if mode=='both': assert rows[-1].get('reused') is True,rows[-1]
PY
}
# Keep the field reproduction first.
item54_cases() {
  local c
  for c in body body-space unchanged title restored decoded empty reused-row legacy uppercase short type null-body publish-failure local local-rows; do echo "v1-54.$c"; done
}
i54_main_body() {
  rev_cfg changes; i54_review
  chk 'initial refusal' eq "$(st_state "$HEADSHA" shipcraft/review)" failure
  gh_quiet pr edit "$PRN" --body 'Corrected intent' >> "$LOG" 2>&1 || fail 'harness: edit'
  rev_cfg approve; i54_review
  echo "REPRO54: reviews=$(rev_n) status=$(st_state "$HEADSHA" shipcraft/review) rc=$RC" >> "$LOG"
  chk 'edited body requires second reviewer' eq "$(rev_n)" 2
  chk 'new verdict approves' eq "$(st_state "$HEADSHA" shipcraft/review)" success
}
item54_case() {
  local c="${CASE#v1-54.}"
  EXPECT="item54 $c"
  i54_setup
  if [ "$c" = local ] || [ "$c" = local-rows ]; then
    run_cmd TMO 180 shipcraft review
    chk 'local initial approval' rc_zero
    if [ "$c" = local-rows ]; then
      chk 'local fresh exact text key' i54_rows local-fresh
      pass; return
    fi
    rev_cfg changes
    run_cmd TMO 180 shipcraft review
    # Coordinator: item 54 adds the key to local rows but no local reuse; local review runs every time, as before.
    chk 'local review still runs every time' eq "$(rev_n)" 2
    chk 'local keys on both fresh rows' i54_rows local
    pass; return
  fi
  pr_outside "$BR"
  case "$c" in
    body) i54_main_body; pass; return ;;
    restored)
      gh_quiet pr edit "$PRN" --body-file "$CW/body.md" >> "$LOG" 2>&1 || fail 'harness: exact body A' ;;
    decoded)
      "$PY" - "$CW/text54" <<'PY'
import sys
open(sys.argv[1],'wb').write(' \t"quoted" \\ café e\u0301\r\n\ufeff\u2028\u2029\n '.encode())
PY
      gh_quiet pr edit "$PRN" --title ' Título "54" \ ' --body-file "$CW/text54" >> "$LOG" 2>&1 || fail 'harness: decoded text' ;;
    empty) gh_quiet pr edit "$PRN" --body '' >> "$LOG" 2>&1 || fail 'harness: empty body' ;;
    null-body)
      "$PY" - "$ST/prs.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); next(iter(d.values()))['body']=None
json.dump(d,open(p,'w'))
PY
      ;;
    publish-failure)
      mv "$CB/gh" "$CB/gh-real"
      "$PY" - "$CB/gh" "$PY" <<'PY'
import sys
from pathlib import Path
p=Path(sys.argv[1]); p.write_text('#!'+sys.argv[2]+'\n'+'''import os,sys
from pathlib import Path
a=sys.argv[1:]
if a[:2] in (['pr','comment'],['pr','review']) or (a[:1]==['api'] and any('/comments' in s or s.endswith('/reviews') for s in a)):
 Path(__file__).with_name('publication54').write_text(str(a))
 os.environ['SHIPCRAFT_STUB_FAIL']='1'
p=Path(__file__).with_name('gh-real'); os.execv(str(p),[str(p),*a])
'''); p.chmod(0o755)
PY
      ;;
  esac
  i54_review
  chk 'first reviewer ran' eq "$(rev_n)" 1
  case "$c" in
    publish-failure)
      chk 'later publication failed' test -f "$CB/publication54"
      chk 'publication failure returns nonzero' rc_nonzero
      chk 'failed publication preserves text and diff key' i54_rows last
      pass; return ;;
    legacy|uppercase|short|type)
      "$PY" - "$c" <<'PY'
import json,sys
p='.git/shipcraft/runs.jsonl'; rows=[json.loads(s) for s in open(p)]
for r in rows:
 if r.get('layer')!='review': continue
 k=r.get('text_sha256','abcdef01'*8)
 if sys.argv[1]=='legacy': r.pop('text_sha256',None)
 elif sys.argv[1]=='uppercase': r['text_sha256']=k.upper()
 elif sys.argv[1]=='short': r['text_sha256']=k[:63]
 else: r['text_sha256']=[k]
open(p,'w').writelines(json.dumps(r)+'\n' for r in rows)
PY
      rev_cfg changes; i54_review
      chk 'invalid legacy text key cannot reuse' eq "$(rev_n)" 2
      chk 'fresh refusal wins' eq "$(st_state "$HEADSHA" shipcraft/review)" failure ;;
    body-space)
      gh_quiet pr edit "$PRN" --body "$(cat "$CW/body.md") " >> "$LOG" 2>&1 || fail 'harness: whitespace body'
      rev_cfg changes; i54_review
      chk 'body whitespace requires second reviewer' eq "$(rev_n)" 2
      chk 'whitespace edit gets new refusal' eq "$(st_state "$HEADSHA" shipcraft/review)" failure ;;
    reused-row)
      "$PY" - "$ST/prs.json" <<'PYSEED'
import hashlib,json,sys
p=next(iter(json.load(open(sys.argv[1])).values()))
k=hashlib.sha256(p['title'].encode()+b'\0'+p['body'].encode()).hexdigest()
f='.git/shipcraft/runs.jsonl'; rows=[json.loads(s) for s in open(f)]
for r in rows:
 if r.get('layer')=='review': r['text_sha256']=k
open(f,'w').writelines(json.dumps(r)+'\n' for r in rows)
PYSEED
      i54_review
      chk 'valid seeded source reuses' eq "$(rev_n)" 1
      chk 'reused row records its own key' i54_rows both ;;
    title)
      gh_quiet pr edit "$PRN" --title 'PR-de-fora ' >> "$LOG" 2>&1 || fail 'harness: title edit'
      rev_cfg changes; i54_review
      chk 'trailing title space requires reviewer' eq "$(rev_n)" 2
      chk 'new title verdict refuses' eq "$(st_state "$HEADSHA" shipcraft/review)" failure ;;
    restored)
      gh_quiet pr edit "$PRN" --body B >> "$LOG" 2>&1 || fail 'harness: body B'
      rev_cfg changes; i54_review
      chk 'body B reviewed separately' eq "$(rev_n)" 2
      chk 'B refuses' eq "$(st_state "$HEADSHA" shipcraft/review)" failure
      gh_quiet pr edit "$PRN" --body-file "$CW/body.md" >> "$LOG" 2>&1 || fail 'harness: restore A'
      i54_review
      chk 'restored A reuses earlier approval' eq "$(rev_n)" 2
      chk 'restored A approves' eq "$(st_state "$HEADSHA" shipcraft/review)" success
      chk 'restored row has exact text key' i54_rows last ;;
    null-body)
      chk 'unreadable text omits key' i54_rows absent
      i54_review
      chk 'unreadable text never reuses' eq "$(rev_n)" 2
      chk 'second unreadable row omits key' i54_rows absent ;;
    unchanged)
      rev_cfg changes; i54_review
      chk 'unchanged text reuses' eq "$(rev_n)" 1
      chk 'approval retained' rc_zero
      chk 'status keeps existing description' match 'same file versions' "$(st_desc "$HEADSHA" shipcraft/review)" ;;
    decoded|empty)
      chk 'fresh exact text key' i54_rows last
      rev_cfg changes; i54_review
      chk 'unchanged decoded text reuses' eq "$(rev_n)" 1
      chk 'fresh and reused exact keys' i54_rows both ;;
  esac
  pass
}
