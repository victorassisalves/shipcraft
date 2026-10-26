# Item 16b: init only, real npm/TypeScript, without reading the implementation.
item16b_cases() {
  local mode
  for mode in invalid-comment-root invalid-comment-package invalid-string-root invalid-string-package invalid-garbage-root invalid-garbage-package invalid-comma-root invalid-comma-package jsonc-closed-root jsonc-closed-package yaml-text yaml-number jsonc-bom jsonc-crlf shell-space shell-quotes yaml-mapping yaml-null workspace-null yarn-null jsonc-ls jsonc-ps composite references package-only package-references both-manifests outside-invalid jsonc-comments jsonc-bom-crlf jsonc-cr jsonc-string absent extends nested-key composite-false untracked-root invalid-root invalid-package build-type build-reference build-signal build-signal-output npm-list yarn-object star-boundary name-star question star-middle double-middle double-start exclude exclude-first untracked-package untracked-config yaml-block yaml-flow yaml-multiline yaml-alias yaml-unknown yaml-invalid yaml-nontext workspace-json workspace-invalid workspace-nontext yarn-nontext unknown-brace unknown-bracket unknown-plus unknown-at unknown-bang; do
    echo "v1-16b.1-$mode"
  done
}
item16b_case() {
  local mode="${CASE#v1-16b.1-}" want why real expected_version
  expected_version=$(H toml-get "$ACEITE/../nucleo/Cargo.toml" package.version) || fail 'harness: Cargo.toml version'
  expected_version=$(printf '%s\n' "$expected_version" | cut -d. -f1,2)
  [ -n "$expected_version" ] || fail 'harness: package.version missing'
  EXPECT="init infers build conservatively and tests real tsc"
  "$PY" "$ACEITE/tools/item16b.py" "$mode" "$CW/expected" "$CW/negative" || fail 'harness: fixture'
  want=$(cat "$CW/expected"); why=$(cat "$CW/negative")
  git add -A
  case "$mode" in
    untracked-root) git reset -q -- tsconfig.json ;;
    untracked-package) git reset -q -- packages/untracked/package.json ;;
    untracked-config) git reset -q -- packages/untracked/tsconfig.json ;;
  esac
  git commit -q -m 'test: fixture do init' >> "$LOG" 2>&1 || fail 'harness: commit fixture'
  # Independent precondition: the expected command compiles with the installed TypeScript.
  if [ -n "$want" ]; then
    "$PY" -c 'import json,subprocess,sys; sys.exit(subprocess.call(["npx","--no","--","tsc","-b"]+json.load(open(sys.argv[1]))))' "$CW/expected.json" >> "$LOG" 2>&1 || fail 'harness: fixture does not compile'
    find . -name dist -type d -not -path './node_modules/*' -exec rm -rf {} +
    find . -name '*.tsbuildinfo' -not -path './node_modules/*' -delete
  fi
  if [ "$mode" = build-type ] || [ "$mode" = build-reference ]; then
    npx --no -- tsc -b . >> "$LOG" 2>&1
    local tsc_rc=$?
    chk 'harness: fixture fails in the real compiler' test "$tsc_rc" -gt 0
    printf '%s' "$tsc_rc" > "$CW/tsc-exit"
    find . -name dist -type d -not -path './node_modules/*' -exec rm -rf {} +
    find . -name '*.tsbuildinfo' -not -path './node_modules/*' -delete
  fi
  case "$mode" in
    yaml-mapping|yaml-null|yaml-text|yaml-number|workspace-null|yarn-null)
      npx --no -- tsc -b . >> "$LOG" 2>&1 || fail 'harness: root signal does not compile'
      rm -rf dist; rm -f tsconfig.tsbuildinfo ;;
  esac
  case "$mode" in
    invalid-comment-*|invalid-string-*|invalid-garbage-*|invalid-comma-*)
      npx --no -- tsc -p "$why" > "$CW/tsc-invalid.out" 2>&1
      local invalid_rc=$?
      cat "$CW/tsc-invalid.out" >> "$LOG"
      chk 'harness: real tsc refuses the JSONC syntax' test "$invalid_rc" -gt 0
      chk 'harness: error is syntactic, not a type error' grep -E -q 'error TS(1002|1005|1010|1136|1012):' "$CW/tsc-invalid.out"
      find . -name dist -type d -not -path './node_modules/*' -exec rm -rf {} +
      find . -name '*.tsbuildinfo' -not -path './node_modules/*' -delete ;;
  esac
  # Transparent probe: delegates to the real executable, records invocation, arguments and cwd.
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
      # Interrupts the external process; the other cases delegate to the real tsc.
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
  chk 'init exits zero even without inference' rc_zero
  chk 'build is written only after compiling' test ! -e "$CW/too-early"
  chk 'init does not change run state' diff -r "$CW/state-before" .git/shipcraft
  if [ -n "$want" ]; then
    if [[ "$mode" = shell-* ]]; then
      chk 'command keeps targets as quoted arguments' "$PY" -c 'import json,shlex,sys; a=shlex.split(sys.argv[1]); assert a == ["npx","--no","--","tsc","-b"]+json.load(open(sys.argv[2]))' "$(tget build.command)" "$CW/expected.json"
      chk 'tsc gets each whole target once' "$PY" -c 'import json,pathlib,sys; assert pathlib.Path(sys.argv[1]).read_text().splitlines()==["-b"]+json.load(open(sys.argv[2]))' "$CW/tsc-args" "$CW/expected.json"
      chk 'build runs once at the root' eq "$(cat "$CW/tsc-calls")" "$PWD|-b $want"
      chk 'real build writes output in every package' "$PY" -c 'import json,pathlib,sys; assert all((pathlib.Path(p)/"dist/value.js").is_file() for p in json.load(open(sys.argv[1])))' "$CW/expected.json"
      chk 'init announces the command on one line' eq "$(grep -F -c "$(tget build.command)" "$OUT")" 1
      chk 'shipcraft_min matches package major/minor' eq "$(tget shipcraft_min)" "$expected_version"
      pass
    fi
    chk 'exact, ordered command' eq "$(tget build.command)" "npx --no -- tsc -b $want"
    chk 'build ran once at the root with all targets' eq "$(cat "$CW/tsc-calls")" "$PWD|-b $want"
    if [ "$mode" = package-only ] || [ "$mode" = package-references ]; then
      chk 'real tsc wrote the package output' test -f packages/alpha/dist/value.js
    else chk 'real tsc wrote output' test -f dist/value.js; fi
    chk 'init announces the command on one line' eq "$(grep -F -c "npx --no -- tsc -b $want" "$OUT")" 1
    chk 'shipcraft_min matches package major/minor' eq "$(tget shipcraft_min)" "$expected_version"
  else
    printf 'JSONC probe: build=%s; tsc calls=%s\n' "$(tget build.command)" "$(wc -l < "$CW/tsc-calls" | tr -d ' ')" >> "$LOG"
    chk 'no inferred build' eq "$(tget build.command)" ''
    case "$mode" in
      invalid-comment-*|invalid-string-*|invalid-garbage-*|invalid-comma-*)
        chk 'invalid JSONC writes no build section' sh -c '! grep -q "^[[:space:]]*\[build\]" .shipcraft.toml'
        chk 'invalid JSONC does not call tsc' test ! -s "$CW/tsc-calls" ;;
    esac
    if [ "$why" = silent ]; then
      chk 'no signal, no build run' test ! -s "$CW/tsc-calls"
    elif [ "$why" = build ]; then
      chk 'real build was tried once' eq "$(wc -l < "$CW/tsc-calls" | tr -d ' ')" 1
      b16b_diagnostic
      chk 'diagnostic names the command' grep -F -q 'npx --no -- tsc -b .' "$OUT.last3"
      case "$mode" in
        build-signal*) chk 'diagnostic names the signal or shell exit' grep -E -q '(143|signal.*(15|TERM))' "$OUT.last3" ;;
        *) chk 'diagnostic names the real tsc exit code' grep -E -q "(code|exited|exit).*$(cat "$CW/tsc-exit")([^0-9]|$)" "$OUT.last3" ;;
      esac
    else
      chk 'diagnostic names the file or glob' grep -F -q "$why" "$OUT"
      chk 'inference error does not run the build' test ! -s "$CW/tsc-calls"
      case "$mode" in invalid-*) ;; *) b16b_diagnostic ;; esac
    fi
  fi
  pass
}
b16b_diagnostic() {
  # Init succeeds: the inference warning has the three lines of the format.
  grep -E '^(shipcraft refused:|Why:|Next:)' "$OUT" > "$OUT.last3"
  chk 'warning has three lines' eq "$(wc -l < "$OUT.last3" | tr -d ' ')" 3
  chk 'order and format of the three lines' "$PY" -c 'import pathlib,sys; a=pathlib.Path(sys.argv[1]).read_text().splitlines(); assert len(a)==3 and all(line.startswith(prefix) for line,prefix in zip(a,["shipcraft refused:","Why:","Next:"]))' "$OUT.last3"
  chk 'suggests a manual build' grep -F -q '[build]' "$OUT.last3"
}
item16b_langs() { echo node; }
