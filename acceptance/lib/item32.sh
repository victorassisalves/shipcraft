# Item 32: modulo pelo leitor Go, limites da busca e fallback (spec/30-raiz-e-nome).
item32_cases() {
  local c
  for c in modulo-acima modulo-suite modulo-intermediario modulo-mais-proximo indice tab comentario aspas multilinha crlf espacos sem-go comando-falha json-invalido module-ausente path-ausente path-vazio sem-go-mod fora-repositorio bloco-invalido; do echo "v1-32.$c"; done
}
item32_case() {
  local k="${CASE#v1-32.}" fallback=0
  EXPECT="item 32: $k"
  v1_start
  if [ "$k" = fora-repositorio ]; then
    copy_base "$T" "$CW/project" || fail "fixture: projeto isolado"
    use_proj "$CW/project" "$CB"
  fi
  PATH="$GOBIN:$PATH"; export PATH
  setup_init
  OLDLOG="$CW/old.log"
  I32_KIND="$k"; I32_SUITE=.
  case "$k" in modulo-acima|modulo-suite|modulo-intermediario|modulo-mais-proximo|indice) I32_SUITE=services/api ;; esac
  ITEM32_CW="$CW"; export I32_KIND I32_SUITE ITEM32_CW
  mkdir -p "$I32_SUITE"
  (cd "$I32_SUITE" && go_same_name) || fail "fixture: pacotes Go"
  must_accept "fixture: config e go.mod pelo leitor Go" cmd "$PY" "$ACEITE/tools/item32.py" setup
  must_accept "fixture: config Go" commit commit_all "chore: suite Go"
  must_accept "RED real nos dois pacotes" cmd shipcraft red
  must_accept "commit RED" commit commit_all "test: RED api"
  : > "$OLDLOG"
  (cd "$I32_SUITE" && go_same_name_green) || fail "fixture: GREEN"
  git add -A || fail "fixture: prepara GREEN"
  if [ "$k" = indice ]; then
    printf 'module example.com/arvore\n\ngo 1.21\n' > go.mod
  fi
  case "$k" in
    sem-go|comando-falha|json-invalido|module-ausente|path-ausente|path-vazio|sem-go-mod|fora-repositorio|bloco-invalido) fallback=1 ;;
  esac
  must_accept "fixture: wrappers de observacao" cmd "$PY" "$ACEITE/tools/item32.py" wrappers
  PATH="$CW/leitor:$PATH"; export PATH
  if [ "$k" = sem-go ]; then
    # Keep a controlled tool directory: Go may share its directory with sh.
    # The gotestsum observer restores its original PATH only inside the runner.
    "$PY" "$ACEITE/tools/item32.py" no-go-path || fail "fixture: controlled PATH"
    PATH="$CW/no-go"; export PATH
    chk "go ausente no PATH do shipcraft" sh -c '! command -v go >/dev/null 2>&1'
  fi
  must_accept "GREEN sem recusa pelo leitor de modulo" commit commit_index "feat: api"
  chk "trava fechada" one_lock_head_state closed
  must_accept "filtro, pacote e leitura observados" cmd "$PY" "$ACEITE/tools/item32.py" verify
  if [ "$fallback" -eq 0 ]; then
    chk "pacote antigo nao executado no hook" eq "$(old_runs)" 0
  fi
  pass
}
item32_langs() { echo go; }
