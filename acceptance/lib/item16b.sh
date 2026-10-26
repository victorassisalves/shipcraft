# Item 16b: só init, npm/TypeScript reais, sem ler implementação.
item16b_cases() {
  local mode
  for mode in invalid-comment-root invalid-comment-package invalid-string-root invalid-string-package invalid-garbage-root invalid-garbage-package invalid-comma-root invalid-comma-package jsonc-closed-root jsonc-closed-package yaml-text yaml-number jsonc-bom jsonc-crlf shell-space shell-quotes yaml-mapping yaml-null workspace-null yarn-null jsonc-ls jsonc-ps composite references package-only package-references both-manifests outside-invalid jsonc-comments jsonc-bom-crlf jsonc-cr jsonc-string absent extends nested-key composite-false untracked-root invalid-root invalid-package build-type build-reference build-signal build-signal-output npm-list yarn-object star-boundary name-star question star-middle double-middle double-start exclude exclude-first untracked-package untracked-config yaml-block yaml-flow yaml-multiline yaml-alias yaml-unknown yaml-invalid yaml-nontext workspace-json workspace-invalid workspace-nontext yarn-nontext unknown-brace unknown-bracket unknown-plus unknown-at unknown-bang; do
    echo "v1-16b.1-$mode"
  done
}
item16b_case() {
  local mode="${CASE#v1-16b.1-}" want why real expected_version
  expected_version=$(H toml-get "$ACEITE/../nucleo/Cargo.toml" package.version) || fail 'harness: versão do Cargo.toml'
  expected_version=$(printf '%s\n' "$expected_version" | cut -d. -f1,2)
  [ -n "$expected_version" ] || fail 'harness: package.version ausente'
  EXPECT="init infere build conservadoramente e testa tsc real"
  "$PY" "$ACEITE/tools/item16b.py" "$mode" "$CW/expected" "$CW/negative" || fail 'harness: fixture'
  want=$(cat "$CW/expected"); why=$(cat "$CW/negative")
  git add -A
  case "$mode" in
    untracked-root) git reset -q -- tsconfig.json ;;
    untracked-package) git reset -q -- packages/untracked/package.json ;;
    untracked-config) git reset -q -- packages/untracked/tsconfig.json ;;
  esac
  git commit -q -m 'test: fixture do init' >> "$LOG" 2>&1 || fail 'harness: commit fixture'
  # Pré-condição independente: o comando esperado compila com o TypeScript instalado.
  if [ -n "$want" ]; then
    "$PY" -c 'import json,subprocess,sys; sys.exit(subprocess.call(["npx","--no","--","tsc","-b"]+json.load(open(sys.argv[1]))))' "$CW/expected.json" >> "$LOG" 2>&1 || fail 'harness: fixture nao compila'
    find . -name dist -type d -not -path './node_modules/*' -exec rm -rf {} +
    find . -name '*.tsbuildinfo' -not -path './node_modules/*' -delete
  fi
  if [ "$mode" = build-type ] || [ "$mode" = build-reference ]; then
    npx --no -- tsc -b . >> "$LOG" 2>&1
    local tsc_rc=$?
    chk 'harness: fixture falha no compilador real' test "$tsc_rc" -gt 0
    printf '%s' "$tsc_rc" > "$CW/tsc-exit"
    find . -name dist -type d -not -path './node_modules/*' -exec rm -rf {} +
    find . -name '*.tsbuildinfo' -not -path './node_modules/*' -delete
  fi
  case "$mode" in
    yaml-mapping|yaml-null|yaml-text|yaml-number|workspace-null|yarn-null)
      npx --no -- tsc -b . >> "$LOG" 2>&1 || fail 'harness: sinal raiz nao compila'
      rm -rf dist; rm -f tsconfig.tsbuildinfo ;;
  esac
  case "$mode" in
    invalid-comment-*|invalid-string-*|invalid-garbage-*|invalid-comma-*)
      npx --no -- tsc -p "$why" > "$CW/tsc-invalid.out" 2>&1
      local invalid_rc=$?
      cat "$CW/tsc-invalid.out" >> "$LOG"
      chk 'harness: tsc real recusa sintaxe JSONC' test "$invalid_rc" -gt 0
      chk 'harness: erro e sintatico, nao erro de tipos' grep -E -q 'error TS(1002|1005|1010|1136|1012):' "$CW/tsc-invalid.out"
      find . -name dist -type d -not -path './node_modules/*' -exec rm -rf {} +
      find . -name '*.tsbuildinfo' -not -path './node_modules/*' -delete ;;
  esac
  # Sonda transparente: delega ao executável real, mede invocação, argumentos e cwd.
  real=$("$PY" -c 'import os; print(os.path.realpath("node_modules/.bin/tsc"))')
  rm node_modules/.bin/tsc
  cat > node_modules/.bin/tsc <<EOF
#!/bin/sh
printf '%s|%s\\n' "\$PWD" "\$*" >> '$CW/tsc-calls'
if grep -q '^[[:space:]]*\[build\]' .shipcraft.toml 2>/dev/null; then touch '$CW/too-early'; fi
printf '%s\\n' "\$@" >> '$CW/tsc-args'
exec '$real' "\$@"
EOF
  case "$mode" in
    build-signal|build-signal-output)
      # Interrupção do processo externo; os demais casos delegam ao tsc real.
      sed '$d' node_modules/.bin/tsc > "$CW/tsc-wrapper"
      cp "$CW/tsc-wrapper" node_modules/.bin/tsc
      [ "$mode" = build-signal-output ] && printf "printf 'Building...'\n" >> node_modules/.bin/tsc
      printf 'kill -TERM $$\n' >> node_modules/.bin/tsc ;;
  esac
  chmod +x node_modules/.bin/tsc
  : > "$CW/tsc-calls"
  mkdir -p .git/shipcraft
  printf 'sentinela\n' > .git/shipcraft/preservar
  cp -R .git/shipcraft "$CW/state-before"
  if [ "$mode" = workspace-json ]; then run_cmd shipcraft init --lang node
  else run_cmd shipcraft init; fi
  chk 'init sai zero mesmo sem inferencia' rc_zero
  chk 'build so e gravado depois de compilar' test ! -e "$CW/too-early"
  chk 'init nao altera estado de execucoes' diff -r "$CW/state-before" .git/shipcraft
  if [ -n "$want" ]; then
    if [[ "$mode" = shell-* ]]; then
      chk 'comando preserva alvos como argumentos citados' "$PY" -c 'import json,shlex,sys; a=shlex.split(sys.argv[1]); assert a == ["npx","--no","--","tsc","-b"]+json.load(open(sys.argv[2]))' "$(tget build.command)" "$CW/expected.json"
      chk 'tsc recebe cada alvo inteiro uma vez' "$PY" -c 'import json,pathlib,sys; assert pathlib.Path(sys.argv[1]).read_text().splitlines()==["-b"]+json.load(open(sys.argv[2]))' "$CW/tsc-args" "$CW/expected.json"
      chk 'build roda uma vez na raiz' eq "$(cat "$CW/tsc-calls")" "$PWD|-b $want"
      chk 'build real gera saida em todos os pacotes' "$PY" -c 'import json,pathlib,sys; assert all((pathlib.Path(p)/"dist/value.js").is_file() for p in json.load(open(sys.argv[1])))' "$CW/expected.json"
      chk 'init anuncia comando numa linha' eq "$(grep -F -c "$(tget build.command)" "$OUT")" 1
      chk 'shipcraft_min matches package major/minor' eq "$(tget shipcraft_min)" "$expected_version"
      pass
    fi
    chk 'comando exato e ordenado' eq "$(tget build.command)" "npx --no -- tsc -b $want"
    chk 'build rodou uma vez na raiz com todos os alvos' eq "$(cat "$CW/tsc-calls")" "$PWD|-b $want"
    if [ "$mode" = package-only ] || [ "$mode" = package-references ]; then
      chk 'tsc real gerou saida do pacote' test -f packages/alpha/dist/value.js
    else chk 'tsc real gerou saida' test -f dist/value.js; fi
    chk 'init anuncia comando numa linha' eq "$(grep -F -c "npx --no -- tsc -b $want" "$OUT")" 1
    chk 'shipcraft_min matches package major/minor' eq "$(tget shipcraft_min)" "$expected_version"
  else
    printf 'sonda JSONC: build=%s; chamadas tsc=%s\n' "$(tget build.command)" "$(wc -l < "$CW/tsc-calls" | tr -d ' ')" >> "$LOG"
    chk 'sem build inferido' eq "$(tget build.command)" ''
    case "$mode" in
      invalid-comment-*|invalid-string-*|invalid-garbage-*|invalid-comma-*)
        chk 'JSONC invalido nao grava secao build' sh -c '! grep -q "^[[:space:]]*\[build\]" .shipcraft.toml'
        chk 'JSONC invalido nao chama tsc' test ! -s "$CW/tsc-calls" ;;
    esac
    if [ "$why" = silent ]; then
      chk 'sem sinal nao executa build' test ! -s "$CW/tsc-calls"
    elif [ "$why" = build ]; then
      chk 'build real foi tentado uma vez' eq "$(wc -l < "$CW/tsc-calls" | tr -d ' ')" 1
      b16b_diagnostic
      chk 'diagnostico cita comando' grep -F -q 'npx --no -- tsc -b .' "$OUT.last3"
      case "$mode" in
        build-signal*) chk 'diagnostico cita sinal ou saida do shell' grep -E -q '(143|signal.*(15|TERM))' "$OUT.last3" ;;
        *) chk 'diagnostico cita codigo real do tsc' grep -E -q "(code|exited|exit).*$(cat "$CW/tsc-exit")([^0-9]|$)" "$OUT.last3" ;;
      esac
    else
      chk 'diagnostico identifica arquivo ou glob' grep -F -q "$why" "$OUT"
      chk 'erro de inferencia nao executa build' test ! -s "$CW/tsc-calls"
      case "$mode" in invalid-*) ;; *) b16b_diagnostic ;; esac
    fi
  fi
  pass
}
b16b_diagnostic() {
  # Init conclui com sucesso: o aviso de inferência tem as três linhas do formato.
  grep -E '^(shipcraft refused:|Why:|Next:)' "$OUT" > "$OUT.last3"
  chk 'aviso tem tres linhas' eq "$(wc -l < "$OUT.last3" | tr -d ' ')" 3
  chk 'ordem e formato das tres linhas' "$PY" -c 'import pathlib,sys; a=pathlib.Path(sys.argv[1]).read_text().splitlines(); assert len(a)==3 and all(line.startswith(prefix) for line,prefix in zip(a,["shipcraft refused:","Why:","Next:"]))' "$OUT.last3"
  chk 'orienta build manual' grep -F -q '[build]' "$OUT.last3"
}
item16b_langs() { echo node; }
