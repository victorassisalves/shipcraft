# Item 40: docs-only PRs (docs/spec.md, "Docs-only PRs"). Black box: no reading of nucleo/.
item40_cases() {
  local k
  for k in raiz-md docs-qualquer rename-para-docs build-falha pr-local \
           md-no-codigo misto docs-aninhado teste-em-docs config trava-aberta \
           sem-pr vazio link rename-de-fora modo; do
    echo "v1-40.$k"
  done
}
i40_commit() {
  git add -A || fail "fixture: git add"
  git diff --cached --quiet && return 0
  git -c core.hooksPath="$CW/sem-hooks" commit -q -m "$1" >> "$LOG" 2>&1 || fail "fixture: commit $1"
}
i40_docs_only() { # i40_docs_only true|false: every ci row of runs.jsonl carries docs_only with this value
  "$PY" - .git/shipcraft/runs.jsonl "$1" <<'PY'
import json,sys
rows=[json.loads(x) for x in open(sys.argv[1]) if x.strip()]
rows=[x for x in rows if x.get('layer')=='ci']
assert rows, 'no ci row'
assert all(x.get('docs_only') is (sys.argv[2]=='true') for x in rows), rows
PY
}
i40_skipped() {
  chk 'CI passed' rc_zero
  chk 'history still checked' out_has 'commit\(s\) checked'
  chk 'the suite did not run' eq "$(probe_runs)" 0
  chk 'one line says docs only' out_has '^docs only: the suites do not run$'
  chk 'ci row has docs_only true' i40_docs_only true
}
i40_full() {
  chk 'the suite ran' eq "$(probe_runs)" 1
  chk 'no docs-only line' out_hasnt 'docs only'
  chk 'ci row has docs_only false' i40_docs_only false
}
item40_case() {
  local k="${CASE#v1-40.}" pr=--pr
  EXPECT="item 40: $k"
  v1_start codex
  CFGS='execution|review|"off"'
  pr_main
  probe_write
  printf 'readme\n' > README.md
  mkdir -p src && printf 'code\n' > src/app.py && printf 'embedded\n' > src/brief.md
  printf 'guide\n' > guia.md
  case "$k" in
    build-falha) H toml-set .shipcraft.toml build command '"exit 37"' ;;
    teste-em-docs) H toml-set .shipcraft.toml '' test_globs '["tests/**", "docs/contracts/**"]' ;;
    modo) printf '#!/bin/sh\n' > docs/run.sh ;;
  esac
  i40_commit 'test: probe and base files'
  git push -q origin main >> "$LOG" 2>&1 || fail 'fixture: push base'
  BASE=$(head_rev)
  git checkout -q -b docs/change || fail 'fixture: branch'
  case "$k" in
    raiz-md|sem-pr|build-falha|pr-local) printf 'changed\n' >> README.md ;;
    docs-qualquer) printf 'a,b\n' > docs/table.csv ;;
    rename-para-docs) git mv guia.md docs/guia.md ;;
    md-no-codigo) printf 'changed\n' >> src/brief.md ;;
    misto) printf 'changed\n' >> README.md; printf 'changed\n' >> src/app.py ;;
    docs-aninhado) mkdir -p pkg/docs && printf 'x\n' > pkg/docs/notes.md ;;
    teste-em-docs) mkdir -p docs/contracts && printf 'x\n' > docs/contracts/rule.md ;;
    config) printf 'changed\n' >> README.md; printf '\n# comment\n' >> .shipcraft.toml ;;
    trava-aberta)
      printf 'def test_new():\n    assert False\n' > tests/test_new.py
      must_accept 'shipcraft red' cmd shipcraft red
      i40_commit 'test: RED'
      printf 'changed\n' >> README.md ;;
    vazio) ;;
    link) ln -s README.md LEIA.md ;;
    rename-de-fora) git mv src/brief.md docs/brief.md ;;
    modo) chmod +x docs/run.sh ;;
  esac
  [ "$k" = sem-pr ] && pr=
  i40_commit "docs: $k"
  mkdir -p .git/shipcraft && : > .git/shipcraft/runs.jsonl
  : > "$CB/probe.log"
  if [ "$k" = pr-local ]; then
    shipcraft_pr
  else
    run_cmd TMO 60 shipcraft ci --base "$BASE" $pr
  fi
  case "$k" in
    raiz-md|docs-qualquer|rename-para-docs|build-falha) i40_skipped ;;
    pr-local)
      chk 'shipcraft pr passed' rc_zero
      chk 'the suite did not run' eq "$(probe_runs)" 0
      chk 'ci row has docs_only true' i40_docs_only true ;;
    trava-aberta)
      chk 'open cycle: CI passes with the RED case red' rc_zero
      i40_full ;;
    *)
      chk 'CI passed' rc_zero
      i40_full ;;
  esac
  pass
}
