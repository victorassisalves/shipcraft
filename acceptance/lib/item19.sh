# Item 19: suite roots, read from the Git tree. The text-only PR path was removed.
item19_cases() {
  local k
  for k in pai caixa simbolica ausente absoluta arquivo; do
    echo "v1-19.arvore-$k"
  done
  for k in simples ponto barra ponto-barra ponto-final pontos-repetidos barras-repetidas; do
    echo "v1-19.raiz-$k"
  done
}
i19_commit() {
  git add -A || fail "fixture: git add"
  git diff --cached --quiet && return 0
  git -c core.hooksPath="$CW/sem-hooks" commit -q -m "$1" >> "$LOG" 2>&1 || fail "fixture: commit $1"
}
i19_setup() {
  v1_start codex
  pr_main
  probe_write
  printf 'base\n' > README.md
  printf 'codigo\n' > velho.py
  printf 'base\n' > antigo.md
  printf 'base\n' > "$CW/expected"
  i19_commit 'test: sonda e arquivos base'
}
i19_branch() {
  git push -q origin main >> "$LOG" 2>&1 || fail 'fixture: push base'
  git fetch -q origin
  BASE=$(head_rev); BR=feature/root
  git checkout -q -b "$BR" || fail 'fixture: branch'
}
i19_refusal() {
  msg_check || fail "$MSGERR"
  chk 'refusal: what happened' grep -q '^shipcraft refused:' "$OUT.last3"
  chk 'refusal: why' grep -q '^Why:' "$OUT.last3"
  chk 'refusal: next step' grep -q '^Next:' "$OUT.last3"
}
item19_case() {
  local k="${CASE#v1-19.}"
  EXPECT="item 19: $k"
  i19_setup
  case "$k" in arvore-*) i19_tree "$k" ;; raiz-*) i19_root "$k" ;; *) fail "unknown case $k" ;; esac
}


# 19.1 / RED brief 8: equivalent relative spellings the runner accepts.
i19_root() {
  local root
  case "$1" in
    raiz-simples) root=docs ;;
    raiz-ponto) root=./docs ;;
    raiz-barra) root=docs/ ;;
    raiz-ponto-barra) root=./docs/ ;;
    raiz-ponto-final) root=docs/./ ;;
    raiz-pontos-repetidos) root=././docs ;;
    raiz-barras-repetidas) root=docs// ;;
  esac
  cat > .shipcraft.toml <<EOF
[[suite]]
name = "documentacao"
root = "$root"
command = "sh ../runner.sh {junit}"
globs = ["**/*.md"]
EOF
  cat > runner.sh <<EOF
set -eu
printf 'ran\n' >> '$CW/docs-runs'
if grep -qx good contract.md; then
  printf '<testsuite><testcase name="contract"/></testsuite>' > "\$1"
else
  printf '<testsuite><testcase name="contract"><failure/></testcase></testsuite>' > "\$1"
fi
EOF
  printf 'good\n' > docs/contract.md
  i19_commit 'test: base verde do contrato Markdown'
  BASE=$(head_rev)
  run_cmd TMO 30 shipcraft ci --base "$BASE" --pr
  chk 'runner accepts the root and the base is green' rc_zero
  chk 'base ran the suite' eq "$(cat "$CW/docs-runs")" ran
  i19_branch
  printf 'bad\n' > docs/contract.md
  i19_commit 'test: contrato Markdown vermelho'
  chk 'PR changes only the Markdown test' eq "$(git diff --name-only "$BASE" HEAD)" docs/contract.md
  : > "$CW/docs-runs"
  : > .git/shipcraft/runs.jsonl
  run_cmd TMO 30 shipcraft ci --base "$BASE" --pr
  chk 'protected PR refuses red HEAD' rc_nonzero
  i19_refusal
  chk 'refused for the red suite' out_has 'suite fails at HEAD'
  chk 'PR ran the suite once' eq "$(cat "$CW/docs-runs")" ran
  pass
}

# Round 4: root validated in the Git tree, not resolved through the filesystem.
i19_tree() {
  local root=docs path=docs/contract.md
  case "$1" in
    arvore-pai) root=docs/../docs ;;
    arvore-caixa) root=Docs ;;
    arvore-simbolica) root=atalho; ln -s docs atalho ;;
    arvore-ausente) root=ausente ;;
    arvore-absoluta) root="$PWD/docs" ;;
    arvore-arquivo) root=arquivo; printf 'arquivo\n' > arquivo ;;
  esac
  mkdir -p docs
  printf 'good\n' > docs/contract.md
  cat > runner-tree.sh <<EOF
set -eu
printf 'ran\\n' >> '$CW/tree-runs'
if grep -qx good docs/contract.md; then
  printf '<testsuite><testcase name="contract"/></testsuite>' > "\$1"
else
  printf '<testsuite><testcase name="contract"><failure/></testcase></testsuite>' > "\$1"
fi
EOF
  # The sentinel suite is valid and comes first: even a missing root must judge the red HEAD,
  # not just fail on chdir.
  cat > .shipcraft.toml <<EOF
[[suite]]
name = "sentinela"
root = "."
command = "sh runner-tree.sh {junit}"
globs = ["**/*.py"]

[[suite]]
name = "documentacao"
root = "$root"
command = "exit 97"
globs = ["**/contract.md"]
EOF
  i19_commit 'test: raízes da árvore e contrato base'
  i19_branch
  printf 'bad\n' > "$path"
  i19_commit 'test: mudança única de Markdown'
  chk 'PR changes only one Markdown file' eq "$(git diff --name-only "$BASE" HEAD)" "$path"
  : > "$CW/tree-runs"
  run_cmd TMO 30 shipcraft ci --base "$BASE" --pr
  if [ "$1" = arvore-pai ] || [ "$1" = arvore-absoluta ]; then
    # Item 30.3 (5a54b4b): an invalid root refuses before any suite.
    chk 'invalid config refused' rc_nonzero
    i19_refusal
    chk 'refusal names the config' out_has '(config|\.shipcraft\.toml)'
    chk 'refusal names the root key' out_has 'root'
    chk 'refusal names the invalid value' grep -F -q -- "$root" "$OUT"
    chk 'invalid config does not run the sentinel' test ! -s "$CW/tree-runs"
  else
    chk 'red HEAD refused' rc_nonzero
    i19_refusal
    chk 'suite ran before the refusal' eq "$(cat "$CW/tree-runs")" ran
  fi
  pass
}
