# Item 30, spec 5a54b4b: black box only, real runners.
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
  must_accept "item 30 fixture" commit commit_all 'test: configuração item 30'
  BASE=$(head_rev)
}
b30_save_nv() { # config invalid on purpose: the fixture commit skips the hook (item 31)
  must_accept "item 30 fixture without hook" commit commit_nv 'test: configuração item 30'
  BASE=$(head_rev)
}
b30_refusal() {
  chk "refused" rc_nonzero
  msg_check || fail "refusal without three lines: $MSGERR"
  chk "what happened" grep -q '^shipcraft refused:' "$OUT.last3"
  chk "why" grep -q '^Why:' "$OUT.last3"
  chk "how to proceed" grep -q '^Next:' "$OUT.last3"
}
b30_do() { (cd "$ROOT30" && L "$1"); }
item30_case() {
  EXPECT='item 30 contract'
  b30_project
  case "$CASE" in
    v1-30.3-*glob-extra-*)
      local extra30 key30=globs
      case "$CASE" in *vazio) extra30='' ;; *absoluto) extra30='/tests/**' ;; *pai) extra30='tests/../tests/**' ;; esac
      "$PY" "$ACEITE/tools/item30.py" add-glob "$extra30" || fail "harness: later glob"
      case "$CASE" in *v0-*) "$PY" "$ACEITE/tools/item30.py" v0 || fail "harness: v0 conversion"; key30=test_globs ;; esac
      b30_save_nv
      run_cmd shipcraft red; b30_refusal
      chk "later glob is also an invalid config" last3_has '(config|\.shipcraft\.toml)'
      chk "key of the invalid globs" grep -F -q "$key30" "$OUT.last3"
      if [ -n "$extra30" ]; then chk "value of the later glob" grep -F -q -- "$extra30" "$OUT.last3"
      else chk "empty later glob" last3_has '(empty|""|\x27\x27)'; fi
      chk "no lock" no_lock; pass ;;
    v1-30.3-novo-solto|v1-30.3-novo-indice|v1-30.3-ignorado)
      # Only the new test matches; the base's other tests cannot satisfy the guard.
      mv "$ROOT30/$F30" "$CW/teste-novo"
      G30="$F30"; b30_config
      [ "$CASE" = v1-30.3-ignorado ] && printf '\n%s/%s\n' "$ROOT30" "$F30" >> .gitignore
      b30_save
      mv "$CW/teste-novo" "$ROOT30/$F30"
      [ "$CASE" = v1-30.3-novo-indice ] && git add "$ROOT30/$F30"
      if [ "$CASE" = v1-30.3-ignorado ]; then
        run_cmd shipcraft red; b30_refusal
        chk "glob of the ignored test" grep -F -q "$F30" "$OUT.last3"
        chk "ignored file opens no lock" no_lock
      else
        must_accept "new test counts for the guard" cmd shipcraft red
        chk "new test is in the lock" "$PY" "$ACEITE/tools/item30.py" locked "$(lock_files_tree)" "$ROOT30/$F30"
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
      chk "refusal names the suite without a regular file" grep -F -q contrato-30 "$OUT.last3"
      chk "glob without a regular file" grep -F -q apoio30 "$OUT.last3"
      chk "no lock" no_lock; pass ;;
    v1-30.3-suite-verde-vazia|v1-30.3-suite-falha-vazia)
      local failing30=no
      [ "$CASE" = v1-30.3-suite-falha-vazia ] && failing30=yes
      "$PY" "$ACEITE/tools/item30.py" side-suite "$LP" "$ROOT30" "$failing30"
      b30_save
      if [ "$failing30" = no ]; then
        must_accept "green suite with a similar name need not match files" cmd shipcraft red
        chk "lock of the real RED" one_lock_tree_state open
      else
        run_cmd shipcraft red; b30_refusal
        chk "refuses the empty suite that failed" grep -F -q contrato-30-extra "$OUT.last3"
        chk "glob of the second suite" grep -F -q ausente/** "$OUT.last3"
        chk "no partial lock" no_lock
      fi
      pass ;;
    v1-30.2-antiga-hook|v1-30.2-antiga-ci)
      # Historical empty-suite fixture from 6e579b4; E1 wire keys, config hash and seal migrated.
      cp "$ACEITE/fixtures/item30/$LP/config.toml" .shipcraft.toml
      b30_save
      mkdir -p .shipcraft/locks
      cp "$ACEITE/fixtures/item30/$LP/lock.json" .shipcraft/locks/antiga30.json
      must_accept "commit of an empty historical RED" commit commit_all 'test: RED histórico item 30'
      must_refuse "RED does not replace an open lock" cmd shipcraft red
      chk "stays open" one_lock_head_state open
      if [ "$CASE" = v1-30.2-antiga-ci ]; then
        must_accept "CI accepts an open historical RED" cmd shipcraft ci --base "$BASE"
        chk "CI does not apply the new guard to the old lock" "$PY" "$ACEITE/tools/item30.py" legacy-ci .git/shipcraft/runs.jsonl
      fi
      b30_do implement
      must_accept "hook closes the historical cycle" commit commit_all 'feat: GREEN histórico item 30'
      chk "old lock closed" one_lock_head_state closed
      must_accept "CI accepts the historical cycle" cmd shipcraft ci --base "$BASE"
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
      case "$CASE" in *v0-*) "$PY" "$ACEITE/tools/item30.py" v0 || fail "harness: v0 conversion"; key30=test_globs ;; esac
      "$PY" "$ACEITE/tools/item30.py" command "exit 37"
      b30_save_nv
      run_cmd shipcraft red; b30_refusal
      chk "invalid config refusal" last3_has '(config|\.shipcraft\.toml)'
      chk "refusal names the key" grep -F -q "$key30" "$OUT.last3"
      if [ -n "$value30" ]; then chk "refusal names the value" grep -F -q -- "$value30" "$OUT.last3"
      else chk "refusal names the empty value" last3_has '(empty|""|\x27\x27)'; fi
      chk "invalid config creates no lock" no_lock
      pass ;;
    v1-30.2-glob-sem-arquivos|v1-30.2-glob-normalizada-vazia|v1-30.2-repo-*|v1-30.2-caixa|v1-30.2-link)
      case "$CASE" in
        *glob-sem-arquivos|*repo-*) G30='ausente/**' ;;
        *glob-normalizada-vazia) R30='./packages//api/'; G30='./ausente//**' ;;
        *caixa) R30=packages/API
          # Works on a case-sensitive FS too: the ignored copy runs,
          # while git ls-files only holds packages/api.
          git add packages/api
          if [ ! -d packages/API ]; then cp -R packages/api packages/API; fi
          printf '\npackages/API/\n' >> .gitignore ;;
        *link) ln -s api packages/atalho; R30=packages/atalho ;;
      esac
      b30_config
      "$PY" "$ACEITE/tools/item30.py" prefix-command "printf ran > '$CW/ran30'; "
      b30_save
      run_cmd shipcraft red
      chk "guard comes after the run" test -s "$CW/ran30"
      b30_refusal
      chk "suite name" grep -F -q contrato-30 "$OUT.last3"
      local displayed_root30="$R30"
      [ "$ROOT30" = . ] && displayed_root30=.
      [ "$CASE" = v1-30.2-glob-normalizada-vazia ] && displayed_root30="$ROOT30"
      chk "suite root" grep -F -q "$displayed_root30" "$OUT.last3"
      if [ "$ROOT30" = . ]; then
        chk "repository root shows as a dot" "$PY" "$ACEITE/tools/item30.py" repo-message "$OUT.last3"
      fi
      local displayed30="$G30"
      [ "$CASE" = v1-30.2-glob-normalizada-vazia ] && displayed30="ausente/**"
      chk "suite globs" grep -F -q "$displayed30" "$OUT.last3"
      chk "opened no empty lock" no_lock
      pass ;;
    v1-30.2-inexistente|v1-30.2-comando|v1-30.1-recusa-normalizada)
      if [ "$CASE" = v1-30.2-inexistente ]; then R30=packages/ausente
      else R30='./packages//api/'; fi
      b30_config
      "$PY" "$ACEITE/tools/item30.py" command 'sh -c "echo diagnostico-30 >&2; exit 37"'
      # No name: the diagnostic must use the normalized folder.
      [ "$CASE" = v1-30.1-recusa-normalizada ] && perl -ni -e 'print unless /^name = /' .shipcraft.toml
      b30_save; run_cmd shipcraft red; b30_refusal
      if [ "$CASE" = v1-30.2-inexistente ]; then
        chk "missing folder still does not run" last3_has '(cannot run|report|JUnit)'
        chk "diagnostic for the missing folder" grep -F -q packages/ausente "$OUT.last3"
      else chk "no-report, not the glob guard" last3_has '(report|JUnit)'; fi
      if [ "$CASE" != v1-30.2-inexistente ]; then
        chk "stderr original" grep -F -q diagnostico-30 "$OUT.last3"
      fi
      if [ "$CASE" = v1-30.1-recusa-normalizada ]; then
        chk "normalized folder" grep -F -q packages/api "$OUT.last3"
        chk "no original spelling" last3_hasnt '\./packages//api/'
      fi
      chk "no lock" no_lock; pass ;;
    v1-30.2-apoio)
      # The guard counts files; it does not try to classify runnable tests.
      printf '# apoio\n' > "$ROOT30/conftest.py"
      G30=conftest.py; b30_config; b30_save
      must_accept "a tracked support file is enough" cmd shipcraft red
      chk "lock open" one_lock_tree_state open; pass ;;
    v1-30.1-nomes)
      # Space, double quotes and non-ASCII in the same tracked path.
      case "$LP" in
        python) N30='tests/test_ação "especial".py' ;;
        node) N30='src/ação "especial".test.ts' ;;
        go) N30='ação "especial"_test.go' ;;
      esac
      # Go rejects these names as code: a support file must still be locked.
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
      ROOT30="packages/api d'água"; R30="./$ROOT30/"; b30_config ;;
    v1-30.1-brief) R30='./packages//api/'; b30_config ;;
  esac
  b30_save
  if [[ "$CASE" = v1-30.1-brief* ]]; then
    printf '%s\n' "$(head_rev)" > "$ST/sha"
    rev_cfg approve
    must_accept "local review" cmd shipcraft review
    H rev-brief "$ST" > "$CW/brief"
    chk "normalized root in shell quotes" "$PY" "$ACEITE/tools/item30.py" brief "$CW/brief" "$ROOT30"
    pass
  fi
  must_accept "RED real" cmd shipcraft red
  chk "lock open" one_lock_tree_state open
  # Structural check that does not depend on the hash map name.
  "$PY" "$ACEITE/tools/item30.py" locked "$(lock_files_tree)" "${ROOT30#./}/$F30" >> "$LOG" 2>&1 || fail 'lock does not protect the normalized path'
  if [ "$CASE" = v1-30.1-nomes ] && [ "$LP" = go ]; then
    chk "support file with special characters locked" "$PY" "$ACEITE/tools/item30.py" locked "$(lock_files_tree)" "$ROOT30/$N30"
  fi
  must_accept "commit RED" commit commit_all 'test: RED item 30'
  if [ "$CASE" = v1-30.1-mapa ]; then
    : > "$OLDLOG"
    b30_do implement; b30_do legacy_break
    must_accept "GREEN filters the old file" commit commit_all 'feat: implementação item 30'
    chk "normalized map skips the old test" eq "$(old_runs)" 0
    chk "lock closed" one_lock_head_state closed
    pass
  fi
  b30_do implement
  printf '\n' >> "$ROOT30/$F30"
  must_refuse "hook protects the normalized test" commit commit_all 'test: tentativa de editar teste travado'
  chk "edit was not committed" eq "$MOVED" no
  if [ "$CASE" = v1-30.1-prefixo ]; then
    # 1c: PATH prefix; ids of the unnamed suite stay without a prefix.
    chk "refusal cites the file with the normalized prefix" grep -F -q "$ROOT30/$F30" "$OUT.last3"
    chk "refusal does not use the raw root" last3_hasnt '\./packages//api/'
  fi
  git reset -q
  git checkout -q -- "$ROOT30/$F30"
  must_accept "legitimate GREEN" commit commit_all 'feat: implementação item 30'
  chk "lock closed" one_lock_head_state closed
  pass
}
item30_langs() { echo python node go; }
