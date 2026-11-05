# Item 88: literal public briefs and preservation of verdict/notes behavior.
item88_langs() { echo core; }
item88_cases() {
  local c
  for c in brief-off brief-local brief-review brief-github-docs \
    notes-off notes-local notes-review-pr notes-review \
    changes-off changes-local publish-notes-off publish-notes-local \
    publish-changes-off publish-changes-local reuse-refusal reuse-refusal-text; do echo "v1-88.$c"; done
}
i88_note_stub() {
  # Modify only the copied recording agent's body, retaining its real fixture protocol.
  "$PY" - "$CB/codex" "$1" <<'PYSTUB'
from pathlib import Path
import json,sys
p=Path(sys.argv[1]);s=p.read_text()
old='    body = "REVIEW-BODY-MARKER-3a9: nothing to point out beyond the above.\\n"'
body=('REVIEW-BODY-MARKER-3a9\n## Notes\nNOTE88-'+sys.argv[2]+': Reproduced on a state nothing creates; this becomes Blocking if supported state reaches it.\n')
assert s.count(old)==1,'fixture: expected exactly one common body assignment'
p.write_text(s.replace(old,'    body = '+json.dumps(body)))
PYSTUB
}
item88_case() {
  local c=${CASE#v1-88.} ci=off kind=pr after=false docs=product envcase=no mode=approve publish=no reuse=no
  EXPECT="item 88: $c"
  case "$c" in
    brief-off) ;;
    brief-local) ci=local;after=true ;;
    brief-review) kind=review ;;
    brief-github-docs) ci=github;after=true;docs=docs ;;
    notes-off) ;;
    notes-local) ci=local;after=true ;;
    notes-review-pr) kind=review-pr ;;
    notes-review) kind=review ;;
    changes-off) mode=changes ;;
    changes-local) ci=local;after=true;mode=changes ;;
    publish-notes-off) publish=yes ;;
    publish-notes-local) ci=local;after=true;publish=yes ;;
    publish-changes-off) mode=changes;publish=yes ;;
    publish-changes-local) ci=local;after=true;mode=changes;publish=yes ;;
    reuse-refusal) mode=changes;reuse=yes ;;
    reuse-refusal-text) mode=changes;reuse=text ;;
    *) fail 'harness: unknown item 88 case' ;;
  esac
  v1_start codex
  CFGS="execution|ci|\"$ci\"
execution|review|\"local\"
review|spec|\"docs/spec-produto.md\""
  pr_main
  if [ "$docs" = docs ]; then
    BR=feature/docs88;git checkout -qb "$BR";printf 'docs63-marker\n' > docs/change88.md;pr_commit 'docs: item88'
  else pr_feature;fi
  HEADSHA=$(head_rev);printf '%s\n' "$HEADSHA" > "$ST/sha"
  seed_ok "$HEADSHA" shipcraft/ci
  [ "$kind" != review-pr ] || pr_outside "$BR"
  i88_note_stub "$c"
  rev_cfg "$mode"
  [ "$publish" != yes ] || i82_publish_fail
  i63_run
  if [ "$reuse" != no ]; then
    chk 'initial refusal is recorded' eq "$(st_state "$HEADSHA" shipcraft/review)" failure
    cp .git/shipcraft/runs.jsonl "$CW/first88.jsonl"
    cp "$ST/comments.jsonl" "$CW/comments88.jsonl"
    rev_cfg approve
    PRN=$(H prnum "$ST" "$BR");kind=review-pr
    if [ "$reuse" = text ]; then
      PRN=$(H prnum "$ST" "$BR")
      gh_quiet pr edit "$PRN" --body 'Changed intent88' >> "$LOG" 2>&1 || fail 'fixture: edit PR intent'
    fi
    i63_run
  fi
  cp "$OUT" "$CW/output88"
  must_accept 'item 88 public observations' cmd "$PY" - "$c" "$ST" "$CB" "$CW" "$CW/output88" "$RC" "$HEADSHA" "$after" <<'PY88'
import json,sys
from pathlib import Path
case,st,cb,cw,out,rc,sha,after=sys.argv[1:];st=Path(st);cb=Path(cb);cw=Path(cw);rc=int(rc)
calls=[json.loads(s) for s in (st/'reviewer.calls.jsonl').read_text().splitlines()]
rows=[json.loads(s) for s in Path('.git/shipcraft/runs.jsonl').read_text().splitlines() if json.loads(s).get('layer')=='review']
text=Path(out).read_text();note='NOTE88-'+case+':'
comments=(st/'comments.jsonl').read_text() if (st/'comments.jsonl').exists() else ''
statuses=[json.loads(s)['state'] for s in (st/'statuses.jsonl').read_text().splitlines() if json.loads(s).get('context')=='shipcraft/review'] if (st/'statuses.jsonl').exists() else []
brief=next(v for k,v in calls[-1]['files'].items() if k.endswith('/brief.md'))
# Literal contract from item 88; no implementation or runtime spec reader.
rules = "A Blocking item must be ALL of these:\n- reproduced by you, with the exact commands and their observed output;\n- either a violation of a specific rule of the spec or of the stated intent (quote it),\n  or a crash (panic, abort, or an unhandled error on valid input); and\n- either reachable or a risk to data or access; say which, and why. Reachable: a real\n  user or system gets there in use, through an entry point of the product, a public API\n  or documented configuration, from input it would really send or state it really holds\n  (a supported older state counts). Timing counts if it can happen in use, even if you\n  forced it to reproduce it. A risk to data or access: it can lose, corrupt or expose\n  data, a secret included, or let someone act without permission, however rare the\n  trigger.\n\nA reproduced defect that fails the last test is a note, never Blocking: a state nothing\ncreates or has created, input nobody would really send, or timing that cannot happen in\nuse. Finding no caller in this repository proves nothing about a public API or a\ndocumented configuration. The note says what would make it Blocking. A failing test that\nthe project's suite runs is reachable.\n"
if case in ('brief-off','brief-local','brief-review','brief-github-docs'):
 assert rc==0 and len(calls)==1 and len(rows)==1,(rc,calls,rows)
 section=brief.split('## Rules for a Blocking item\n',1)[1].split('## Review format (your final message)\n',1)[0]
 assert section.startswith('\n'+rules+'\nA failing test of the battery'),('new ALL list and notes paragraph must precede existing battery paragraph',section)
 assert brief.count(rules)==1 and 'must be BOTH' not in brief,brief
 p=('After you reproduce a Blocking item, keep going: check the rest of the diff against the\n'
    'spec and the intent, and list every Blocking item you reproduce, not only the first.\n'
    'Blocking: <n> counts all of them.\n')
 assert section.endswith(p+'\n') and section.count(p)==1,section
 assert 'SPEC-MARKER-5e1' in brief and sha in brief,brief
elif case in ('notes-off','notes-local','notes-review-pr'):
 assert rc==0 and len(calls)==1 and len(rows)==1,(rc,text,rows)
 assert statuses==['pending','success'],statuses
 assert note in comments and '## Notes' in comments,comments
 assert rows[0]['result']=='passed' and not rows[0].get('reused',False),rows
elif case=='notes-review':
 assert rc==0 and len(calls)==1 and len(rows)==1,(rc,text,rows)
 assert note in text and '## Notes' in text,text
 assert not statuses and not comments,(statuses,comments)
 assert rows[0]['result']=='passed',rows
elif case in ('changes-off','changes-local'):
 assert rc==1 and len(calls)==1 and len(rows)==1,(rc,text,rows)
 assert statuses==['pending','failure'] and note in comments,(statuses,comments)
 assert 'REVIEW-FINDING-MARKER-77c' in comments and 'Blocking: 2' in comments,comments
 assert rows[0]['result']=='refused' and rows[0]['code']=='changes-requested',rows
elif case in ('publish-notes-off','publish-notes-local'):
 assert rc!=0 and (cb/'publish82-failed').exists(),(rc,text)
 assert len(calls)==1 and len(rows)==1 and statuses==['pending'],(calls,rows,statuses)
 assert rows[0]['result']=='passed' and not rows[0].get('reused',False),rows
 assert not comments,comments
elif case in ('publish-changes-off','publish-changes-local'):
 assert rc!=0 and (cb/'publish82-failed').exists(),(rc,text)
 assert len(calls)==1 and len(rows)==1 and statuses==['pending'],(calls,rows,statuses)
 assert rows[0]['result']=='refused' and rows[0]['code']=='changes-requested',rows
 assert not comments,comments
elif case=='reuse-refusal':
 assert rc==1 and len(calls)==1 and len(rows)==2,(rc,text,calls,rows)
 assert rows[1].get('reused') is True and 'after_green_ci' not in rows[1],rows
 assert rows[1]['result']=='refused' and rows[1]['code']=='changes-requested',rows
 original=[json.loads(s) for s in (cw/'comments88.jsonl').read_text().splitlines() if note in json.loads(s).get('body','')]
 current=[json.loads(s) for s in comments.splitlines() if note in json.loads(s).get('body','')]
 assert current==original and len(current)==1,comments
 assert statuses==['pending','failure','failure'],statuses
 for key in ('diff_sha256','text_sha256'):
  assert rows[0][key]==rows[1][key],rows
elif case=='reuse-refusal-text':
 assert rc==0 and len(calls)==2 and len(rows)==2,(rc,text,calls,rows)
 assert rows[0]['result']=='refused' and rows[1]['result']=='passed' and not rows[1].get('reused',False),rows
 assert rows[0]['diff_sha256']==rows[1]['diff_sha256'] and rows[0]['text_sha256']!=rows[1]['text_sha256'],rows
 assert statuses==['pending','failure','pending','success'],statuses
 assert len([s for s in comments.splitlines() if note in json.loads(s).get('body','')])==2,comments
else:raise AssertionError(('unknown item88 routing',case))
for r in rows:
 assert r.get('diff_sha256') and r.get('text_sha256'),r
 if not r.get('reused',False): assert r.get('after_green_ci') is (after=='true'),r
assert all(not Path(c['cwd']).exists() for c in calls),'review worktree cleanup changed'
PY88
  pass
}
