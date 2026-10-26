# Item 32: module from the Go reader, search bounds and fallback (spec/30-raiz-e-nome).
item32_cases() {
  local c
  for c in modulo-acima modulo-suite modulo-intermediario modulo-mais-proximo indice tab comentario aspas multilinha crlf espacos sem-go comando-falha json-invalido module-ausente path-ausente path-vazio sem-go-mod fora-repositorio bloco-invalido; do echo "v1-32.$c"; done
}
item32_case() {
  local k="${CASE#v1-32.}" fallback=0
  EXPECT="item 32: $k"
  v1_start
  if [ "$k" = fora-repositorio ]; then
    copy_base "$T" "$CW/project" || fail "fixture: isolated project"
    use_proj "$CW/project" "$CB"
  fi
  PATH="$GOBIN:$PATH"; export PATH
  setup_init
  OLDLOG="$CW/old.log"
  I32_KIND="$k"; I32_SUITE=.
  case "$k" in modulo-acima|modulo-suite|modulo-intermediario|modulo-mais-proximo|indice) I32_SUITE=services/api ;; esac
  ITEM32_CW="$CW"; export I32_KIND I32_SUITE ITEM32_CW
  mkdir -p "$I32_SUITE"
  (cd "$I32_SUITE" && go_same_name) || fail "fixture: Go packages"
  must_accept "fixture: config and go.mod through the Go reader" cmd "$PY" "$ACEITE/tools/item32.py" setup
  must_accept "fixture: config Go" commit commit_all "chore: suite Go"
  must_accept "real RED in both packages" cmd shipcraft red
  must_accept "commit RED" commit commit_all "test: RED api"
  : > "$OLDLOG"
  (cd "$I32_SUITE" && go_same_name_green) || fail "fixture: GREEN"
  git add -A || fail "fixture: stage GREEN"
  if [ "$k" = indice ]; then
    printf 'module example.com/arvore\n\ngo 1.21\n' > go.mod
  fi
  case "$k" in
    sem-go|comando-falha|json-invalido|module-ausente|path-ausente|path-vazio|sem-go-mod|fora-repositorio|bloco-invalido) fallback=1 ;;
  esac
  must_accept "fixture: observer wrappers" cmd "$PY" "$ACEITE/tools/item32.py" wrappers
  PATH="$CW/leitor:$PATH"; export PATH
  if [ "$k" = sem-go ]; then
    # Keep a controlled tool directory: Go may share its directory with sh.
    # The gotestsum observer restores its original PATH only inside the runner.
    "$PY" "$ACEITE/tools/item32.py" no-go-path || fail "fixture: controlled PATH"
    PATH="$CW/no-go"; export PATH
    chk "go missing from shipcraft's PATH" sh -c '! command -v go >/dev/null 2>&1'
  fi
  must_accept "GREEN not refused by the module reader" commit commit_index "feat: api"
  chk "lock closed" one_lock_head_state closed
  must_accept "filter, package and read observed" cmd "$PY" "$ACEITE/tools/item32.py" verify
  if [ "$fallback" -eq 0 ]; then
    chk "old package not run in the hook" eq "$(old_runs)" 0
  fi
  pass
}
item32_langs() { echo go; }
