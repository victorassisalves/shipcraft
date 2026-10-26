# Item 30, spec 5a54b4b: somente caixa-preta, runners reais.
item30_cases() {
  local c
  for c in glob-extra-vazio glob-extra-absoluto glob-extra-pai v0-glob-extra-vazio v0-glob-extra-absoluto v0-glob-extra-pai novo-solto novo-indice ignorado link-arquivo diretorio cached-apagado suite-verde-vazia suite-falha-vazia; do echo "v1-30.3-$c"; done
  for c in ponto barra ambos dupla repo-ponto repo-barra repo-vazia glob-ponto nomes mapa prefixo brief brief-aspas recusa-normalizada v0-glob-ponto v0-glob-vazio v0-glob-absoluto v0-glob-pai; do echo "v1-30.1-$c"; done
  for c in raiz-absoluta raiz-barra raiz-barra-ponto raiz-pai raiz-pai-interno glob-vazio glob-absoluto glob-pai; do echo "v1-30.1-$c"; done
  for c in glob-sem-arquivos glob-normalizada-vazia repo-vazia repo-ponto repo-barra caixa link apoio inexistente comando antiga-hook antiga-ci; do echo "v1-30.2-$c"; done
}
b30_config() {
  "$PY" "$ACEITE/tools/item30.py" config "$LP" "$R30" "$G30" || fail "harness: config item 30"
}
b30_project() {
  v1_start codex
  [ "$LP" = go ] && PATH="$GOBIN:$PATH"
  export PATH
  setup_init
  L stub; L spec_test
  ROOT30=packages/api
  case "$CASE" in *repo-*|*v0-*) ROOT30=. ;; esac
  if [ "$ROOT30" != . ]; then
    mkdir -p "$ROOT30"
    case "$LP" in
      python) mv textutil.py tests "$ROOT30/" ;;
      node) mv src tsconfig.json "$ROOT30/" ;;
      go) mv ./*.go go.mod "$ROOT30/" ;;
    esac
  fi
  R30="$ROOT30"
  case "$LP" in
    python) G30='tests/**'; F30=tests/test_slug.py ;;
    node) G30='**/*.test.*'; F30=src/slug.test.ts ;;
    go) G30='**/*_test.go'; F30=slug_test.go ;;
  esac
  case "$CASE" in
    *-ponto) R30="./$ROOT30" ;;
    *-barra) R30="$ROOT30/" ;;
    *-ambos) R30="./$ROOT30/" ;;
    *-dupla) R30='packages//api' ;;
  esac
  case "$CASE" in
    *repo-ponto) R30=. ;; *repo-barra) R30=./ ;; *repo-vazia) R30='' ;;
    *glob-ponto) G30="./$G30" ;;
  esac
  b30_config
  case "$CASE" in v1-30.1-v0-*) "$PY" "$ACEITE/tools/item30.py" v0 || fail "harness: config v0" ;; esac
}
b30_save() {
  must_accept "fixture item 30" commit commit_all 'test: configuração item 30'
  BASE=$(head_rev)
}
b30_save_nv() { # config inválida de propósito: o commit da fixture não passa pelo hook (item 31)
  must_accept "fixture item 30 sem hook" commit commit_nv 'test: configuração item 30'
  BASE=$(head_rev)
}
b30_refusal() {
  chk "refused" rc_nonzero
  msg_check || fail "recusa sem três linhas: $MSGERR"
  chk "o que houve" grep -q '^shipcraft refused:' "$OUT.last3"
  chk "por quê" grep -q '^Why:' "$OUT.last3"
  chk "como seguir" grep -q '^Next:' "$OUT.last3"
}
b30_do() { (cd "$ROOT30" && L "$1"); }
item30_case() {
  EXPECT='contrato item 30'
  b30_project
  case "$CASE" in
    v1-30.3-*glob-extra-*)
      local extra30 key30=globs
      case "$CASE" in *vazio) extra30='' ;; *absoluto) extra30='/tests/**' ;; *pai) extra30='tests/../tests/**' ;; esac
      "$PY" "$ACEITE/tools/item30.py" add-glob "$extra30" || fail "harness: glob posterior"
      case "$CASE" in *v0-*) "$PY" "$ACEITE/tools/item30.py" v0 || fail "harness: conversão v0"; key30=test_globs ;; esac
      b30_save_nv
      run_cmd shipcraft red; b30_refusal
      chk "glob posterior também é config inválida" last3_has '(config|\.shipcraft\.toml)'
      chk "chave dos globs inválidos" grep -F -q "$key30" "$OUT.last3"
      if [ -n "$extra30" ]; then chk "valor do glob posterior" grep -F -q -- "$extra30" "$OUT.last3"
      else chk "glob posterior vazio" last3_has '(empty|""|\x27\x27)'; fi
      chk "sem trava" no_lock; pass ;;
    v1-30.3-novo-solto|v1-30.3-novo-indice|v1-30.3-ignorado)
      # Só o teste novo casa; demais testes da base não podem satisfazer a guarda.
      mv "$ROOT30/$F30" "$CW/teste-novo"
      G30="$F30"; b30_config
      [ "$CASE" = v1-30.3-ignorado ] && printf '\n%s/%s\n' "$ROOT30" "$F30" >> .gitignore
      b30_save
      mv "$CW/teste-novo" "$ROOT30/$F30"
      [ "$CASE" = v1-30.3-novo-indice ] && git add "$ROOT30/$F30"
      if [ "$CASE" = v1-30.3-ignorado ]; then
        run_cmd shipcraft red; b30_refusal
        chk "glob do teste ignorado" grep -F -q "$F30" "$OUT.last3"
        chk "ignorado não abre trava" no_lock
      else
        must_accept "teste novo conta para guarda" cmd shipcraft red
        chk "teste novo entra na trava" "$PY" "$ACEITE/tools/item30.py" locked "$(lock_files_tree)" "$ROOT30/$F30"
      fi
      pass ;;
    v1-30.3-link-arquivo|v1-30.3-diretorio|v1-30.3-cached-apagado)
      G30=apoio30
      case "$CASE" in
        *link-arquivo) printf 'apoio\n' > "$ROOT30/alvo30"; ln -s alvo30 "$ROOT30/apoio30" ;;
        *diretorio) mkdir "$ROOT30/apoio30"; printf 'apoio\n' > "$ROOT30/apoio30/filho" ;;
        *cached-apagado) printf 'apoio\n' > "$ROOT30/apoio30" ;;
      esac
      b30_config; b30_save
      [ "$CASE" = v1-30.3-cached-apagado ] && rm "$ROOT30/apoio30"
      run_cmd shipcraft red; b30_refusal
      chk "recusa identifica suíte sem arquivo regular" grep -F -q contrato-30 "$OUT.last3"
      chk "glob sem arquivo regular" grep -F -q apoio30 "$OUT.last3"
      chk "sem trava" no_lock; pass ;;
    v1-30.3-suite-verde-vazia|v1-30.3-suite-falha-vazia)
      local failing30=no
      [ "$CASE" = v1-30.3-suite-falha-vazia ] && failing30=yes
      "$PY" "$ACEITE/tools/item30.py" side-suite "$LP" "$ROOT30" "$failing30"
      b30_save
      if [ "$failing30" = no ]; then
        must_accept "suíte verde de nome parecido não precisa casar arquivos" cmd shipcraft red
        chk "trava do RED real" one_lock_tree_state open
      else
        run_cmd shipcraft red; b30_refusal
        chk "recusa a suíte vazia que falhou" grep -F -q contrato-30-extra "$OUT.last3"
        chk "glob da segunda suíte" grep -F -q ausente/** "$OUT.last3"
        chk "nenhuma trava parcial" no_lock
      fi
      pass ;;
    v1-30.2-antiga-hook|v1-30.2-antiga-ci)
      # Historical empty-suite fixture from 6e579b4; E1 wire keys, config hash and seal migrated.
      cp "$ACEITE/fixtures/item30/$LP/config.toml" .shipcraft.toml
      b30_save
      mkdir -p .shipcraft/locks
      cp "$ACEITE/fixtures/item30/$LP/lock.json" .shipcraft/locks/antiga30.json
      must_accept "commit de RED histórico vazio" commit commit_all 'test: RED histórico item 30'
      must_refuse "RED não substitui trava aberta" cmd shipcraft red
      chk "continua aberta" one_lock_head_state open
      if [ "$CASE" = v1-30.2-antiga-ci ]; then
        must_accept "CI aceita RED histórico aberto" cmd shipcraft ci --base "$BASE"
        chk "CI não aplica guarda nova à trava antiga" "$PY" "$ACEITE/tools/item30.py" legacy-ci .git/shipcraft/runs.jsonl
      fi
      b30_do implement
      must_accept "hook fecha ciclo histórico" commit commit_all 'feat: GREEN histórico item 30'
      chk "trava antiga fechada" one_lock_head_state closed
      must_accept "CI aceita ciclo histórico" cmd shipcraft ci --base "$BASE"
      pass ;;
    v1-30.1-raiz-*|v1-30.1-glob-vazio|v1-30.1-glob-absoluto|v1-30.1-glob-pai|v1-30.1-v0-glob-vazio|v1-30.1-v0-glob-absoluto|v1-30.1-v0-glob-pai)
      local key30=root value30
      case "$CASE" in
        *raiz-absoluta) R30='/packages/api' ;; *raiz-barra) R30=/ ;;
        *raiz-barra-ponto) R30=/. ;; *raiz-pai) R30='../packages/api' ;;
        *raiz-pai-interno) R30='packages/../packages/api' ;;
        *glob-vazio) G30=''; key30=globs ;; *glob-absoluto) G30='/tests/**'; key30=globs ;;
        *glob-pai) G30='tests/../tests/**'; key30=globs ;;
      esac
      value30="$R30"; [ "$key30" = globs ] && value30="$G30"
      b30_config
      case "$CASE" in *v0-*) "$PY" "$ACEITE/tools/item30.py" v0 || fail "harness: conversão v0"; key30=test_globs ;; esac
      "$PY" "$ACEITE/tools/item30.py" command "exit 37"
      b30_save_nv
      run_cmd shipcraft red; b30_refusal
      chk "recusa de configuração inválida" last3_has '(config|\.shipcraft\.toml)'
      chk "recusa identifica chave" grep -F -q "$key30" "$OUT.last3"
      if [ -n "$value30" ]; then chk "recusa identifica valor" grep -F -q -- "$value30" "$OUT.last3"
      else chk "recusa identifica vazio" last3_has '(empty|""|\x27\x27)'; fi
      chk "config inválida não cria trava" no_lock
      pass ;;
    v1-30.2-glob-sem-arquivos|v1-30.2-glob-normalizada-vazia|v1-30.2-repo-*|v1-30.2-caixa|v1-30.2-link)
      case "$CASE" in
        *glob-sem-arquivos|*repo-*) G30='ausente/**' ;;
        *glob-normalizada-vazia) R30='./packages//api/'; G30='./ausente//**' ;;
        *caixa) R30=packages/API
          # Funciona também em FS sensível a caixa: cópia ignorada executa,
          # enquanto git ls-files só contém packages/api.
          git add packages/api
          if [ ! -d packages/API ]; then cp -R packages/api packages/API; fi
          printf '\npackages/API/\n' >> .gitignore ;;
        *link) ln -s api packages/atalho; R30=packages/atalho ;;
      esac
      b30_config
      "$PY" "$ACEITE/tools/item30.py" prefix-command "printf ran > '$CW/ran30'; "
      b30_save
      run_cmd shipcraft red
      chk "guarda vem depois da execução" test -s "$CW/ran30"
      b30_refusal
      chk "nome da suíte" grep -F -q contrato-30 "$OUT.last3"
      local displayed_root30="$R30"
      [ "$ROOT30" = . ] && displayed_root30=.
      [ "$CASE" = v1-30.2-glob-normalizada-vazia ] && displayed_root30="$ROOT30"
      chk "raiz da suíte" grep -F -q "$displayed_root30" "$OUT.last3"
      if [ "$ROOT30" = . ]; then
        chk "raiz do repositório aparece como ponto" "$PY" "$ACEITE/tools/item30.py" repo-message "$OUT.last3"
      fi
      local displayed30="$G30"
      [ "$CASE" = v1-30.2-glob-normalizada-vazia ] && displayed30="ausente/**"
      chk "globs da suíte" grep -F -q "$displayed30" "$OUT.last3"
      chk "não abriu trava vazia" no_lock
      pass ;;
    v1-30.2-inexistente|v1-30.2-comando|v1-30.1-recusa-normalizada)
      if [ "$CASE" = v1-30.2-inexistente ]; then R30=packages/ausente
      else R30='./packages//api/'; fi
      b30_config
      "$PY" "$ACEITE/tools/item30.py" command 'sh -c "echo diagnostico-30 >&2; exit 37"'
      # Sem nome: o diagnóstico deve usar a pasta normalizada.
      [ "$CASE" = v1-30.1-recusa-normalizada ] && perl -ni -e 'print unless /^name = /' .shipcraft.toml
      b30_save; run_cmd shipcraft red; b30_refusal
      if [ "$CASE" = v1-30.2-inexistente ]; then
        chk "pasta inexistente continua sem execução" last3_has '(cannot run|report|JUnit)'
        chk "diagnóstico da pasta inexistente" grep -F -q packages/ausente "$OUT.last3"
      else chk "no-report, não guarda de glob" last3_has '(report|JUnit)'; fi
      if [ "$CASE" != v1-30.2-inexistente ]; then
        chk "stderr original" grep -F -q diagnostico-30 "$OUT.last3"
      fi
      if [ "$CASE" = v1-30.1-recusa-normalizada ]; then
        chk "pasta normalizada" grep -F -q packages/api "$OUT.last3"
        chk "sem grafia original" last3_hasnt '\./packages//api/'
      fi
      chk "sem trava" no_lock; pass ;;
    v1-30.2-apoio)
      # A guarda conta arquivos, não tenta classificar testes executáveis.
      printf '# apoio\n' > "$ROOT30/conftest.py"
      G30=conftest.py; b30_config; b30_save
      must_accept "apoio rastreado basta" cmd shipcraft red
      chk "trava aberta" one_lock_tree_state open; pass ;;
    v1-30.1-nomes)
      # Espaço, aspas duplas e não ASCII no mesmo caminho rastreado.
      case "$LP" in
        python) N30='tests/test_ação "especial".py' ;;
        node) N30='src/ação "especial".test.ts' ;;
        go) N30='ação "especial"_test.go' ;;
      esac
      # Go rejeita estes nomes como código: arquivo de apoio ainda deve travar.
      if [ "$LP" = go ]; then N30='apoio ação "especial".txt'; printf 'apoio\n' > "$ROOT30/$N30"; b30_config; "$PY" "$ACEITE/tools/item30.py" add-glob "$N30"
      else mv "$ROOT30/$F30" "$ROOT30/$N30"; F30="$N30"; fi ;;
    v1-30.1-prefixo)
      R30="./packages//api/"; b30_config
      perl -ni -e 'print unless /^name = /' .shipcraft.toml
      ;;
    v1-30.1-mapa)
      R30='./packages//api/'; b30_config
      OLDLOG="$CW/old.log"
      (cd "$ROOT30" && L old_probe)
      ;;
    v1-30.1-brief-aspas)
      mv packages/api "packages/api d'água"
      ROOT30="packages/api d'água"; R30="./$ROOT30/"; b30_config; tset execution review '"local"' ;;
    v1-30.1-brief) R30='./packages//api/'; b30_config; tset execution review '"local"' ;;
  esac
  b30_save
  if [[ "$CASE" = v1-30.1-brief* ]]; then
    printf '%s\n' "$(head_rev)" > "$ST/sha"
    rev_cfg approve
    must_accept "revisão local" cmd shipcraft review
    H rev-brief "$ST" > "$CW/brief"
    chk "raiz normalizada entre aspas de shell" "$PY" "$ACEITE/tools/item30.py" brief "$CW/brief" "$ROOT30"
    pass
  fi
  must_accept "RED real" cmd shipcraft red
  chk "trava aberta" one_lock_tree_state open
  # Conferência estrutural sem depender do nome do mapa de hashes.
  "$PY" "$ACEITE/tools/item30.py" locked "$(lock_files_tree)" "${ROOT30#./}/$F30" >> "$LOG" 2>&1 || fail 'trava não protege caminho normalizado'
  if [ "$CASE" = v1-30.1-nomes ] && [ "$LP" = go ]; then
    chk "apoio com caracteres especiais travado" "$PY" "$ACEITE/tools/item30.py" locked "$(lock_files_tree)" "$ROOT30/$N30"
  fi
  must_accept "commit RED" commit commit_all 'test: RED item 30'
  if [ "$CASE" = v1-30.1-mapa ]; then
    : > "$OLDLOG"
    b30_do implement; b30_do legacy_break
    must_accept "GREEN filtra arquivo antigo" commit commit_all 'feat: implementação item 30'
    chk "mapa normalizado evita teste antigo" eq "$(old_runs)" 0
    chk "trava fechou" one_lock_head_state closed
    pass
  fi
  b30_do implement
  printf '\n' >> "$ROOT30/$F30"
  must_refuse "hook protege teste normalizado" commit commit_all 'test: tentativa de editar teste travado'
  chk "edição não foi commitada" eq "$MOVED" no
  if [ "$CASE" = v1-30.1-prefixo ]; then
    # 1c: prefixo de CAMINHO; ids da suíte sem nome continuam sem prefixo.
    chk "recusa cita arquivo com prefixo normalizado" grep -F -q "$ROOT30/$F30" "$OUT.last3"
    chk "recusa não usa raiz crua" last3_hasnt '\./packages//api/'
  fi
  git reset -q
  git checkout -q -- "$ROOT30/$F30"
  must_accept "GREEN legítimo" commit commit_all 'feat: implementação item 30'
  chk "trava fechou" one_lock_head_state closed
  pass
}
item30_langs() { echo python node go; }
