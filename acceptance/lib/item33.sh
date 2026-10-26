# Item 33, spec cfc254b: safe suggestion to restore the lock in the hook.
item33_cases() {
  local r v
  for r in editada apagada fechada; do
    echo "v1-33.$r"
    for v in subpasta ci espaco acento aspas; do echo "v1-33.$r.$v"; done
  done
  for v in nova sem-head head-ilegivel duas merge nome-seguro; do echo "v1-33.editada.$v"; done
  echo v1-33.apagada.duas v1-33.fechada.merge v1-33.fechada.nome-seguro
}
i33_edit() {
  "$PY" - "$1" <<'PY'
import json,sys
p=sys.argv[1];d=json.load(open(p));d['state']='closed' if d['state']=='open' else 'open'
open(p,'w').write(json.dumps(d)+'\n')
PY
}
item33_case() {
  local rest="${CASE#v1-33.}" kind variant lf other='' want=sim
  kind="${rest%%.*}"; variant="${rest#*.}"; [ "$variant" != "$kind" ] || variant=comum
  EXPECT="item 33: $kind/$variant"
  v1_start codex
  git config maintenance.auto false; git config gc.auto 0
  case "$variant" in
    nova|sem-head)
      setup_init; L stub; L spec_test
      must_accept 'RED without a lock commit' cmd shipcraft red
      [ "$variant" != sem-head ] || git update-ref -d refs/heads/main
      want=nao ;;
    *) setup_red ;;
  esac
  lf=$(lock_files_tree)
  case "$variant" in
    espaco|acento|aspas|nome-seguro)
      local name
      case "$variant" in espaco) name='trava com espaco.json' ;; acento) name='ação.json' ;; aspas) name="aspas'\".json" ;; *) name='Trava_09.v2-A.json' ;; esac
      git mv -- "$lf" ".shipcraft/locks/$name" || fail 'harness: rename'
      lf=".shipcraft/locks/$name"
      must_accept 'fixture rename' commit git -c core.hooksPath=/dev/null commit -qm 'test: nome da trava'
      [ "$variant" = nome-seguro ] || want=nao ;;
    duas)
      cp "$lf" .shipcraft/locks/aaa-33.json
      git mv -- "$lf" .shipcraft/locks/zzz-33.json
      lf=.shipcraft/locks/aaa-33.json; other=.shipcraft/locks/zzz-33.json
      git add -A
      must_accept 'two fixture locks' commit git -c core.hooksPath=/dev/null commit -qm 'test: duas travas' ;;
    merge)
      git checkout -q -b lado-33
      L implement
      must_accept 'closes on the second parent' commit commit_all 'feat: segundo pai verde'
      git checkout -q main
      printf 'primeiro pai\n' > primeiro-pai.txt
      must_accept 'first parent stays RED' commit commit_all 'chore: primeiro pai'
      must_accept 'merge in progress' cmd git merge --no-ff --no-commit lado-33
      chk 'merge has a second parent' test -f .git/MERGE_HEAD
      chk 'HEAD is the first parent with an open lock' one_lock_head_state open
      chk 'second parent has a different lock' "$PY" - "$lf" <<'PARENTS'
import subprocess,sys,json
p=sys.argv[1]
a=subprocess.check_output(['git','show','HEAD:'+p]);b=subprocess.check_output(['git','show','MERGE_HEAD:'+p])
assert json.loads(a)['state']=='open' and json.loads(b)['state']=='closed'
PARENTS
      ;;
  esac
  if [ "$kind" = fechada ] && [ "$variant" != merge ]; then
    L implement
    must_accept 'lock validly closed by the hook' commit commit_all 'feat: fecha'
    must_accept 'back to the first RED with a GREEN index' cmd git reset --soft HEAD^
  fi
  case "$kind" in
    editada) i33_edit "$lf"; [ -z "$other" ] || i33_edit "$other" ;;
    apagada) git rm -q -- "$lf"; [ -z "$other" ] || git rm -q -- "$other" ;;
    fechada) L stub ;;
  esac
  git add -A
  if [ "$variant" = subpasta ]; then
    # Tree differs from the index: git add -A must not bring back the old copy.
    "$PY" - "$lf" <<'TREE'
import pathlib,sys
p=pathlib.Path(sys.argv[1])
p.write_bytes(p.read_bytes()+b'\n' if p.exists() else b'copia da arvore que nao deve voltar\n')
TREE
  fi
  if [ "$variant" = head-ilegivel ]; then
    want=nao
    "$PY" - "$lf" <<'MISSING'
import subprocess,sys,pathlib
sha=subprocess.check_output(['git','rev-parse','HEAD:'+sys.argv[1]],text=True).strip()
p=pathlib.Path(subprocess.check_output(['git','rev-parse','--git-path','objects'],text=True).strip())/sha[:2]/sha[2:]
assert p.is_file(), 'fixture needs a loose blob'
p.unlink()
assert subprocess.run(['git','cat-file','-e',sha],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0
MISSING
  fi
  if [ "$variant" = ci ]; then
    want=nao
    must_accept 'invalid commit only to judge history' commit git -c core.hooksPath=/dev/null commit -qm 'test: histórico recusável'
    run_cmd shipcraft ci --base "$BASE"
  else
    run_cmd shipcraft check
  fi
  if [ "$kind/$variant" = fechada/merge ]; then
    # The hook judges a merge against both parents, as CI does: a lock closed on the
    # merged branch is not an edit. A red suite after the merge is CI's suite-red.
    chk 'merge with a lock closed on the second parent accepts, as in CI' rc_zero
    pass
  fi
  chk 'same refusal verdict' rc_nonzero
  chk 'text, metric and restore contract' "$PY" - "$OUT" "$kind" "$variant" "$lf" "$other" "$want" <<'CHECK33'
import sys,json,subprocess,pathlib,shlex
out,kind,variant,lf,other,want=sys.argv[1:]
raw=pathlib.Path(out).read_text()
if variant=='head-ilegivel':
    # On main the missing blob aborts before the lock refusal; keep this error.
    rows=[json.loads(l) for l in pathlib.Path('.git/shipcraft/runs.jsonl').read_text().splitlines()]
    assert rows[-1]['code']=='error' and rows[-1]['layer']=='hook',rows[-1]
    assert 'shipcraft: error:' in raw and 'git cat-file blob' in raw and lf in raw,raw
    assert 'git restore' not in raw,raw
    sys.exit(0)
lines=[l for l in raw.splitlines() if l.strip()][-3:]
assert len(lines)==3 and lines[2].startswith('Next: '),raw
code={'editada':'lock-edited','apagada':'lock-deleted','fechada':'lock-closed-red'}[kind]
rows=[json.loads(l) for l in pathlib.Path('.git/shipcraft/runs.jsonl').read_text().splitlines()]
row=rows[-1]
assert row['code']==code and row['layer']==('ci' if variant=='ci' else 'hook'),row
# Two locks: use the one the refusal itself named; the other must stay changed.
if other:
    mentioned=[p for p in (lf,other) if p in lines[0]]
    assert len(mentioned)==1,lines
    lf,other=mentioned[0],next(p for p in (lf,other) if p!=mentioned[0])
old='Next: '+('restore the open lock and keep implementing until the locked cases pass' if kind=='fechada' else 'restore the lock as shipcraft left it; it closes automatically in the commit where locked cases pass')
context='in the pending commit' if variant!='ci' else 'in commit '+ subprocess.check_output(['git','rev-parse','--short','HEAD'],text=True).strip()
first={
  'editada':f'shipcraft refused: lock {lf} was edited outside shipcraft {context}',
  'apagada':f'shipcraft refused: open lock {lf} was deleted {context}',
  'fechada':f'shipcraft refused: lock {lf} arrives closed, but locked cases do not pass: tests.test_slug::test_slug_basic, tests.test_slug::test_slug_spaces',
}[kind]
why={
  'editada':'Why: only shipcraft changes the lock: `shipcraft red` opens it and the green commit closes it; editing it manually silently changes the contract',
  'apagada':'Why: the lock is the RED contract; deleting it discards the contract without fulfilling it',
  'fechada':'Why: the lock only closes in the commit where all locked cases pass',
}[kind]
assert lines[:2]==[first,why],lines
assert lines[2].startswith(old),lines
command=f"git restore --staged --worktree --source=HEAD -- ':/{lf}'"
if want=='nao':
    assert lines[2]==old and 'git restore' not in raw,raw
else:
    assert lines[2].count(command)==1 and lines[2].count('git restore')==1,lines[2]
    # The earlier content is not overwritten by the command, nor does it appear after it.
    assert lines[2].index(command)>=len(old),lines[2]
    before=subprocess.check_output(['git','show','HEAD:'+lf])
    sub=pathlib.Path('subpasta/mais-fundo');sub.mkdir(parents=True,exist_ok=True)
    subprocess.run(shlex.split(command),cwd='.' if variant=='comum' else sub,check=True)
    assert pathlib.Path(lf).read_bytes()==before,'tree not restored'
    assert subprocess.check_output(['git','show',':'+lf])==before,'index not restored'
    if other:
        now=subprocess.run(['git','diff','--cached','--quiet','HEAD','--',other])
        assert now.returncode==1,'command also restored the second lock'
CHECK33
  pass
}
