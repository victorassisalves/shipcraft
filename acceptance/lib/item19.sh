# Item 19: spec d509585; caixa-preta, sem ler nucleo/.
item19_cases() {
  local k d h e
  for k in pai caixa simbolica ausente absoluta arquivo normal-ponto-barra normal-barras vazia-protegida ponto-protegida vazia-texto ponto-texto; do
    echo "v1-19.arvore-$k"
  done
  for k in simples ponto barra ponto-barra ponto-final pontos-repetidos barras-repetidas; do
    echo "v1-19.raiz-$k"
  done
  for k in pr ci; do
    echo "v1-19.tempo-$k-mensagem"
    echo "v1-19.tempo-$k-processo"
  done
  for k in stdout stderr; do for d in sem-lf com-lf; do for h in ok falha; do
    echo "v1-19.saida-$k-$d-$h"
  done; done; done
  for k in ci-pr fila md acento espaco aspas tab newline cr crlf u2028 u2029 remove rename-texto rename-codigo docs-codigo txt misto vazio modo link tipo submodulo base-avanca base-ponta base-config lista-substitui lista-aceita lista-vazia glob-meio glob-um-nivel glob-recursiva glob-interrogacao glob-classe config-string config-numero config-bool config-tabela protegido-teste protegido-suite protegido-apoio protegido-sc2 protegido-config aberto historico build verifica texto-ok texto-exit texto-sinal texto-tempo texto-head normal-falha sem-pr desligado revisao-local revisao-pr pr revisao-bloqueia raso; do
    echo "v1-19.$k"
  done
  for d in raiz config; do for h in normal oculto local oculto-local; do for e in yml yaml json jsonc toml; do
    echo "v1-19.lefthook-$d-$h-$e"
  done; done; done
}
i19_commit() {
  git add -A || fail "fixture: git add"
  git diff --cached --quiet && return 0
  git -c core.hooksPath="$CW/sem-hooks" commit -q -m "$1" >> "$LOG" 2>&1 || fail "fixture: commit $1"
}
i19_setup() {
  v1_start codex
  pr_main
  [ "${CASE#v1-19.}" != fila ] || PSLEEP=8
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
  BASE=$(head_rev); BR=feature/texto
  git checkout -q -b "$BR" || fail 'fixture: branch'
}
i19_ci() {
  case "${CASE#v1-19.}" in
    aberto|historico|texto-exit|texto-sinal|texto-tempo|texto-head|normal-falha)
      run_cmd TMO 30 shipcraft ci --base "$BASE" --pr ;;
    *) shipcraft_pr ;;
  esac
}
i19_json() {
  "$PY" - .git/shipcraft/runs.jsonl "$1" <<'PY'
import json,sys
rows=[json.loads(x) for x in open(sys.argv[1]) if x.strip()]
rows=[x for x in rows if x.get('layer')=='ci']
assert rows, 'nenhuma linha ci'
assert all(x.get('text_only') is (sys.argv[2]=='true') for x in rows), rows
PY
}
i19_full() {
  chk 'CI normal passou' rc_zero
  chk 'suite realmente executada' eq "$(probe_runs)" 1
  chk 'sem anuncio do atalho' out_hasnt 'text only: the suite does not run'
  chk 'todas linhas ci com false' i19_json false
}
i19_short() {
  chk 'CI texto passou' rc_zero
  chk 'suite nao executada' eq "$(probe_runs)" 0
  chk 'anuncio em uma linha' out_has '^text only: the suite does not run$'
  chk 'todas linhas ci com true' i19_json true
}
i19_refusal() {
  msg_check || fail "$MSGERR"
  chk 'recusa: o que houve' grep -q '^shipcraft refused:' "$OUT.last3"
  chk 'recusa: por que' grep -q '^Why:' "$OUT.last3"
  chk 'recusa: como seguir' grep -q '^Next:' "$OUT.last3"
}
i19_brief_sem_bateria() {
  H rev-brief "$ST" | grep -Ei -q 'do not.*(install|run).*suite'
}
item19_case() {
  local k="${CASE#v1-19.}" path=README.md full=0
  EXPECT="item 19: $k"
  i19_setup
  case "$k" in arvore-*) i19_tree "$k"; return ;; raiz-*) i19_root "$k"; return ;; tempo-*|saida-*) i19_round2 "$k"; return ;; esac
  # 19.1: config da base, substituicao e semantica das globs.
  case "$k" in
    protegido-teste) H toml-set .shipcraft.toml '' test_globs '["**/test_*.py", "**/conftest.py", "tests/*.md"]'; H toml-set .shipcraft.toml pr text '["**/*", "*"]'; full=1 ;;
    protegido-suite)
      H toml-set .shipcraft.toml pr text '["**/*", "*"]'
      cat >> .shipcraft.toml <<'TOML'

[[suite]]
name = "principal"
root = "."
command = "python3 -m pytest -p no:cacheprovider --junitxml={junit}"
globs = ["**/test_*.py", "**/conftest.py"]

[[suite]]
name = "documentacao"
root = "docs"
command = "python3 -m pytest -p no:cacheprovider ../tests/test_smoke.py --junitxml={junit}"
globs = ["**/*.md"]
TOML
      full=1 ;;
    lista-aceita) H toml-set .shipcraft.toml pr text '["**/*.rst"]'; path=docs/guia.rst ;;
    lista-substitui) H toml-set .shipcraft.toml pr text '["**/*.rst"]'; full=1 ;;
    lista-vazia) H toml-set .shipcraft.toml pr text '[]'; full=1 ;;
    glob-meio) H toml-set .shipcraft.toml pr text '["man*/cap*/nota.*"]'; path='manual/capitulo/nota.rst' ;;
    glob-um-nivel) H toml-set .shipcraft.toml pr text '["docs/*.rst"]'; path='docs/a/b.rst'; full=1 ;;
    glob-recursiva) H toml-set .shipcraft.toml pr text '["docs/**/*.rst"]'; path='docs/a/b.rst' ;;
    glob-interrogacao) H toml-set .shipcraft.toml pr text '["doc?.rst"]'; path=docs.rst ;;
    glob-classe) H toml-set .shipcraft.toml pr text '["doc[ab].rst"]'; path=doca.rst ;;
    config-*)
      case "$k" in config-string) val='"**/*.md"';; config-numero) val=1;; config-bool) val=true;; config-tabela) val='{md = true}';; esac
      H toml-set .shipcraft.toml pr text "$val" ;;
    protegido-*|lefthook-*) H toml-set .shipcraft.toml pr text '["**/*", "*"]'; full=1 ;;
    build) H toml-set .shipcraft.toml build command '"exit 37"' ;;
    verifica) H toml-set .shipcraft.toml '' check '"exit 38"' ;;
    texto-*)
      cat > texto.sh <<EOF
set -eu
test -f README.md
test "\$(cat README.md)" = ponta
git rev-parse HEAD > '$CW/texto-head'
printf 'rodou\\n' >> '$CW/texto-runs'
EOF
      case "$k" in texto-exit) echo 'exit 23' >> texto.sh;; texto-sinal) echo 'kill -TERM $$' >> texto.sh;; texto-tempo) echo 'sleep 30' >> texto.sh; H toml-set .shipcraft.toml execution ci_timeout 1;; esac
      H toml-set .shipcraft.toml pr text_check '"sh texto.sh"' ;;
    desligado) H toml-set .shipcraft.toml execution ci '"off"'; H toml-set .shipcraft.toml pr text_check "\"touch $CW/desligado; exit 29\"" ;;
  esac
  i19_commit 'chore: config base do cenario'
  i19_branch
  case "$k" in
    acento) path='docs/ação.md';; espaco) path='docs/duas palavras.md';; aspas) path='docs/"citado".md';;
    tab) path=$(printf 'docs/a\tb.md');; newline) path=$(printf 'docs/a\nb.md');;
    cr) path=$(printf 'docs/a\rb.md');; crlf) path=$(printf 'docs/a\r\nb.md');;
    u2028) path=$(printf 'docs/a\342\200\250b.md');; u2029) path=$(printf 'docs/a\342\200\251b.md');;
    docs-codigo) path=docs/conf.py; full=1;; txt) path=requirements.txt; full=1;;
    protegido-teste) path=tests/contrato.md;; protegido-suite) path=docs/contrato.md;; protegido-apoio) path=conftest.py;;
    protegido-sc2) path=.shipcraft/nota.md;; protegido-config) path=.shipcraft.toml;;
    lefthook-*)
      local rest="${k#lefthook-}" d="${k#lefthook-}" h e
      d="${rest%%-*}"; rest="${rest#*-}"; e="${rest##*-}"; h="${rest%-$e}"
      path=lefthook; case "$h" in oculto*) path=.lefthook;; esac
      case "$h" in *local) path="$path-local";; esac
      path="$path.$e"; [ "$d" != config ] || path=".config/$path" ;;
  esac
  mkdir -p "$(dirname "$path")"
  case "$k" in
    vazio) full=1 ;;
    remove) rm antigo.md ;;
    rename-texto) git mv antigo.md 'docs/renomeado.md' ;;
    rename-codigo) git mv velho.py novo.md; full=1 ;;
    modo) chmod +x README.md; full=1 ;;
    link) ln -s README.md link.md; full=1 ;;
    tipo) rm antigo.md; ln -s README.md antigo.md; full=1 ;;
    submodulo) mkdir modulo.md; git -C modulo.md init -q; git -C modulo.md -c core.hooksPath="$CW/sem-hooks" commit -q --allow-empty -m "fixture: submodulo"; git add modulo.md; full=1 ;;
    normal-falha) printf 'def test_falha():\n    assert False\n' > tests/test_falha.py; full=1 ;;
    misto) echo novo > codigo.py; echo ponta > README.md; full=1 ;;
    base-config) H toml-set .shipcraft.toml pr text '[]'; echo ponta > README.md; full=1 ;;
    base-avanca|base-ponta)
      echo ponta > README.md; i19_commit 'docs: ponta'
      git checkout -q main; echo produto > paralelo.py
      if [ "$k" = base-ponta ]; then H toml-set .shipcraft.toml pr text '[]'; full=1; fi
      i19_commit 'feat: main anda'; BASE=$(head_rev)
      git push -q origin main >> "$LOG" 2>&1 || fail 'fixture: main avancada'
      git fetch -q origin
      git checkout -q "$BR" ;;
    aberto|historico)
      python_shout_stub; python_shout_test
      must_accept 'RED aberto' cmd shipcraft red
      i19_commit 'test: RED aberto'
      if [ "$k" = historico ]; then
        cp tests/test_shout.py "$CW/original"
        echo '# alterado no meio' >> tests/test_shout.py; i19_commit 'test: alteracao intermediaria'
        git restore --source="$BASE" --staged --worktree . || fail 'fixture: desfaz ciclo inteiro'
        i19_commit 'test: desfaz ciclo inteiro'
        chk 'HEAD igual a base antes do Markdown' eq "$(git diff "$BASE" HEAD --name-only)" ""
        chk 'nenhuma trava aberta no HEAD' eq "$(lock_files_head)" ""
      fi
      echo ponta > README.md; full=1 ;;
    protegido-apoio) printf '# apoio valido\n' > conftest.py ;;
    protegido-config) printf '\n# comentario\n' >> .shipcraft.toml ;;
    *) printf 'ponta\n' > "$path" ;;
  esac
  if [ -n "$(git status --porcelain)" ]; then i19_commit 'docs: mudanca julgada'; fi
  : > "$CB/probe.log"
  case "$k" in
    config-*) i19_ci; chk 'config invalida recusada' rc_nonzero; i19_refusal; pass; return ;;
    ci-pr) run_cmd TMO 30 shipcraft ci --base "$BASE" --pr; i19_short; pass; return ;;
    fila)
      copy_base "$T" "$CW/ocupante"
      (cd "$CW/ocupante"; TMO 30 shipcraft ci --base "$BASE" > "$CW/ocupante.out" 2>&1) &
      local pid=$! i=0
      while [ "$(probe_runs)" = 0 ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i+1)); done
      chk 'ocupante entrou na suite' eq "$(probe_runs)" 1
      run_cmd TMO 4 shipcraft ci --base "$BASE" --pr
      local text_rc="$RC"
      wait "$pid"
      RC="$text_rc"
      chk 'texto passou enquanto slot ocupado' rc_zero
      chk 'nao entrou na fila' no_queue_line
      chk 'texto nao executou segunda suite' eq "$(probe_runs)" 1
      chk 'anuncio de texto' out_has 'text only: the suite does not run'
      pass; return ;;
    normal-falha)
      i19_ci
      chk 'CI comum recusou suite' rc_nonzero
      i19_refusal
      chk 'recusa comum tambem mede false' i19_json false
      pass; return ;;
    sem-pr) run_cmd TMO 30 shipcraft ci --base "$BASE"; i19_full; pass; return ;;
    aberto)
      run_cmd TMO 30 shipcraft ci --base "$BASE"
      local normal_rc="$RC"
      : > .git/shipcraft/runs.jsonl
      : > "$CB/probe.log"
      i19_ci
      chk 'mesmo resultado do CI sem atalho' eq "$RC" "$normal_rc"
      chk 'sem anuncio do atalho' out_hasnt 'text only: the suite does not run'
      chk 'ci false' i19_json false
      pass; return ;;
    raso)
      git clone -q --depth 1 --branch "$BR" "file://$T" "$CW/raso" || fail 'fixture clone raso'
      cd "$CW/raso"
      git fetch -q --depth 1 origin "$BASE" || fail 'fixture: busca base rasa'
      chk 'base existe no clone raso' git cat-file -e "$BASE^{commit}"
      chk 'HEAD existe no clone raso' git cat-file -e 'HEAD^{commit}'
      git merge-base "$BASE" HEAD > "$CW/merge-base" 2>&1
      chk 'ancestral comum ausente' eq "$?" 1
      run_cmd TMO 30 shipcraft ci --base "$BASE" --pr; i19_full; pass; return ;;
    revisao-*|pr)
      git rev-parse HEAD > "$ST/sha"
      [ "$k" != revisao-bloqueia ] || rev_cfg changes
      case "$k" in
        pr) shipcraft_pr ;;
        revisao-pr) pr_outside "$BR"; git checkout -q main; run_cmd TMO 60 shipcraft review --pr "$PRN" ;;
        *) run_cmd TMO 60 shipcraft review ;;
      esac
      if [ "$k" = revisao-bloqueia ]; then chk 'bloqueio por leitura vale' rc_nonzero; else chk 'revisao passou' rc_zero; fi
      chk 'revisor executou' eq "$(rev_n)" 1
      chk 'brief identifica so texto' match 'Text only' "$(H rev-brief "$ST")"
      chk 'brief dispensa bateria' i19_brief_sem_bateria
      if [ "$k" = pr ]; then chk 'resumo publicado so texto' H text-has "$ST" - 'text only'; chk 'CI nao rodou suite' eq "$(probe_runs)" 0; fi
      pass; return ;;
  esac
  [ "$k" != texto-head ] || printf 'arvore suja\n' > README.md
  i19_ci
  case "$k" in
    texto-exit|texto-sinal|texto-tempo)
      chk 'validacao texto recusou' rc_nonzero
      i19_refusal
      chk 'comando nas tres linhas' last3_has 'sh texto.sh'
      [ "$k" != texto-exit ] || chk 'codigo nas tres linhas' last3_has '23'
      [ "$k" != texto-sinal ] || chk 'sinal ou codigo shell' last3_has '(143|15|TERM)'
      chk 'sem suite apos falha' eq "$(probe_runs)" 0
      chk 'codigo de texto no registro' eq "$(H jsonl-field .git/shipcraft/runs.jsonl ci "$(head_rev)" code)" '"text-check-failed"'
      chk 'falha tambem leva so_texto' i19_json true ;;
    aberto|historico)
      chk 'historico ou trava aberta recusou' rc_nonzero
      i19_refusal
      chk 'sem atalho' out_hasnt 'text only: the suite does not run'
      if [ "$k" = historico ]; then chk 'diff texto, historico recusado' i19_json true; else chk 'ci false' i19_json false; fi ;;
    desligado) chk 'CI desligado aceito' rc_zero; chk 'suite nao roda' eq "$(probe_runs)" 0; chk 'validacao nao executada' test ! -e "$CW/desligado" ;;
    *)
      if [ "$full" = 1 ]; then i19_full; else i19_short; fi
      case "$k" in texto-ok|texto-head)
        chk 'validacao executou uma vez' eq "$(cat "$CW/texto-runs")" rodou
        chk 'validacao julgou HEAD na raiz' eq "$(cat "$CW/texto-head")" "$(head_rev)" ;;
      esac ;;
  esac
  pass
}

# Rodada 2: saída herdada e timeout externo, sem acesso à implementação.
i19_round2() {
  local k="$1" stream code=0 lf=0
  case "$k" in
    tempo-*)
      H toml-set .shipcraft.toml execution ci_timeout 1
      cat > texto.sh <<EOF
printf 'iniciou\\n' > '$CW/texto-iniciou'
sleep 4
printf 'sobreviveu\\n' > '$CW/texto-tardio'
EOF
      ;;
    saida-*)
      case "$k" in *-falha) code=23;; esac
      case "$k" in *-com-lf-*) lf=1;; esac
      stream=1; case "$k" in saida-stderr-*) stream=2;; esac
      if [ "$lf" = 1 ]; then
        printf "printf 'SONDA-TEXTO\\n' >&%s\nexit %s\n" "$stream" "$code" > texto.sh
      else
        printf "printf 'SONDA-TEXTO' >&%s\nexit %s\n" "$stream" "$code" > texto.sh
      fi
      ;;
  esac
  H toml-set .shipcraft.toml pr text_check '"sh texto.sh"'
  i19_commit 'chore: validação de texto da rodada 2'
  i19_branch
  printf 'ponta\n' > README.md
  i19_commit 'docs: texto julgado'
  : > "$CB/probe.log"
  case "$k" in tempo-pr-*) shipcraft_pr;; *) run_cmd TMO 30 shipcraft ci --base "$BASE" --pr;; esac
  case "$k" in
    tempo-*-processo)
      # Aguarda além do sleep do comando; checa antes de qualquer fail que abandone o caso.
      sleep 5
      chk 'verifica_texto chegou a executar' test -f "$CW/texto-iniciou"
      chk 'nenhum filho escreve depois do retorno' test ! -e "$CW/texto-tardio"
      chk 'timeout recusado' rc_nonzero
      ;;
    tempo-*-mensagem)
      # Deixa o eventual processo defeituoso terminar antes de encerrar a fixture.
      sleep 5
      chk 'timeout recusado' rc_nonzero
      i19_refusal
      chk 'timeout registra texto-falhou' eq "$(H jsonl-field .git/shipcraft/runs.jsonl ci "$(head_rev)" code)" '"text-check-failed"'
      chk 'comando nas ultimas tres linhas' last3_has 'sh texto.sh'
      chk 'tempo nas ultimas tres linhas' last3_has '(1 s|1 second)'
      i19_json true || fail 'timeout sem so_texto'
      ;;
    *-ok)
      i19_short
      chk 'saida do comando preservada numa linha' out_has '^SONDA-TEXTO$'
      ;;
    *-falha)
      chk 'validacao recusada' rc_nonzero
      i19_refusal
      chk 'comando nas ultimas tres linhas' last3_has 'sh texto.sh'
      chk 'codigo nas ultimas tres linhas' last3_has '23'
      chk 'saida do comando preservada numa linha' out_has '^SONDA-TEXTO$'
      chk 'registro texto-falhou' eq "$(H jsonl-field .git/shipcraft/runs.jsonl ci "$(head_rev)" code)" '"text-check-failed"'
      ;;
  esac
  chk 'suite nao executada' eq "$(probe_runs)" 0
  pass
}

# 19.1 / brief RED 8: grafias relativas equivalentes aceitas pelo executor.
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
  chk 'executor aceita a raiz e base verde' rc_zero
  chk 'base executou suite' eq "$(cat "$CW/docs-runs")" ran
  i19_branch
  printf 'bad\n' > docs/contract.md
  i19_commit 'test: contrato Markdown vermelho'
  chk 'PR muda somente o teste Markdown' eq "$(git diff --name-only "$BASE" HEAD)" docs/contract.md
  : > "$CW/docs-runs"
  : > .git/shipcraft/runs.jsonl
  run_cmd TMO 30 shipcraft ci --base "$BASE" --pr
  chk 'PR protegido recusa HEAD vermelho' rc_nonzero
  i19_refusal
  chk 'recusa pela suite vermelha' out_has 'suite fails at HEAD'
  chk 'PR executou suite uma vez' eq "$(cat "$CW/docs-runs")" ran
  chk 'sem anuncio do atalho' out_hasnt 'text only: the suite does not run'
  chk 'classificacao protegida false' i19_json false
  pass
}

# Rodada 4: validação da raiz na árvore Git, sem resolver pelo filesystem.
i19_tree() {
  local root=docs short=0 path=docs/contract.md
  case "$1" in
    arvore-pai) root=docs/../docs ;;
    arvore-caixa) root=Docs ;;
    arvore-simbolica) root=atalho; ln -s docs atalho ;;
    arvore-ausente) root=ausente ;;
    arvore-absoluta) root="$PWD/docs" ;;
    arvore-arquivo) root=arquivo; printf 'arquivo\n' > arquivo ;;
    arvore-normal-ponto-barra) root=./docs/; short=1 ;;
    arvore-normal-barras) root=docs//; short=1 ;;
    arvore-vazia-*) root= ;;
    arvore-ponto-*) root=. ;;
  esac
  case "$1" in *-texto) short=1;; esac
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
  # A suíte sentinela é válida e vem primeiro: até raiz inexistente tem de
  # abandonar o atalho e julgar o HEAD vermelho, não apenas errar no chdir.
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
  if [ "$short" = 1 ]; then path=docs/guia.md; printf 'texto\n' > "$path"
  else printf 'bad\n' > "$path"; fi
  i19_commit 'test: mudança única de Markdown'
  chk 'PR muda somente um Markdown' eq "$(git diff --name-only "$BASE" HEAD)" "$path"
  : > "$CW/tree-runs"
  run_cmd TMO 30 shipcraft ci --base "$BASE" --pr
  if [ "$1" = arvore-pai ] || [ "$1" = arvore-absoluta ]; then
    # Item 30.3 (5a54b4b): raiz inválida recusa antes de qualquer suíte.
    chk 'configuração inválida recusada' rc_nonzero
    i19_refusal
    chk 'recusa identifica configuração' out_has '(config|\.shipcraft\.toml)'
    chk 'recusa identifica chave raiz' out_has 'root'
    chk 'recusa identifica valor inválido' grep -F -q -- "$root" "$OUT"
    chk 'configuração inválida não executa sentinela' test ! -s "$CW/tree-runs"
  elif [ "$short" = 1 ]; then
    i19_short
    chk 'sentinela não executou' test ! -s "$CW/tree-runs"
  else
    chk 'HEAD vermelho recusado' rc_nonzero
    i19_refusal
    chk 'suíte executada antes da recusa' eq "$(cat "$CW/tree-runs")" ran
    chk 'sem anúncio do atalho' out_hasnt 'text only: the suite does not run'
    chk 'raiz exige classificação false' i19_json false
  fi
  pass
}
