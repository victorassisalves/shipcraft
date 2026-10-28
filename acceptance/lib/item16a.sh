# Item 16a: black box; real tsc and Vitest, without depending on item 16b's init.
item16a_cases() {
  echo v1-16a.1-red-build v1-16a.1-ci-so-head
  echo v1-16a.1-red-build-exit v1-16a.1-ci-build-exit
  echo v1-16a.1-red-build-stdout-sem-lf v1-16a.1-red-build-stderr-sem-lf v1-16a.1-red-build-stdout-com-lf
  echo v1-16a.1-red-build-sinal v1-16a.1-ci-build-sinal
  echo v1-16a.1-ci-suja-indice v1-16a.1-ci-suja-arvore
  echo v1-16a.1-hook-saida-ignorada v1-16a.1-hook-sem-saida
  echo v1-16a.2-nome-stderr v1-16a.2-pasta-stderr
  echo v1-16a.2-nome-exit v1-16a.2-pasta-exit
  echo v1-16a.2-stderr-apos-64k v1-16a.2-stderr-vazio-apos-64k
}

b16_project() {
  setup_init
  rm -rf src
  mkdir -p packages/alpha/src packages/alpha/tests packages/beta/src packages/beta/tests
  printf 'node_modules/\n**/dist/\n**/*.tsbuildinfo\n' > .gitignore
  printf '{"files":[],"references":[{"path":"packages/alpha"},{"path":"packages/beta"}]}\n' > tsconfig.json
  local p
  for p in alpha beta; do
    printf '{"compilerOptions":{"composite":true,"target":"es2022","module":"esnext","moduleResolution":"bundler","rootDir":"src","outDir":"dist","types":[],"skipLibCheck":true},"include":["src"]}\n' > "packages/$p/tsconfig.json"
    printf 'export function value(): number { return 0; }\n' > "packages/$p/src/mod.ts"
    cat > "packages/$p/tests/value.test.ts" <<'TS'
import { expect, it } from "vitest";
import { value } from "../dist/mod.js";
it("value", () => expect(value()).toBe(1));
TS
  done
  cat > build.sh <<SH
#!/bin/sh
set -e
test -f tsconfig.json
git rev-parse HEAD >> '$CW/build-heads'
printf 'build\\n' >> '$CW/order'
npx --no -- tsc -b
SH
  cat > suite.sh <<SH
#!/bin/sh
set -e
name="\$1"; report="\$2"; shift 2
if [ "\$name" = beta ] && [ -f ../../sem-junit.sh ]; then
  exec sh ../../sem-junit.sh "\$report"
fi
printf '%s\\n' "\$name" >> '$CW/order'
npx --no -- vitest run --maxWorkers=1 --reporter=junit --outputFile="\$report" "\$@"
SH
  cat > .shipcraft.toml <<'TOML'
shipcraft_min = "1.0"
lang = "node"
runner = "vitest"

[build]
command = "exec sh build.sh"

[[suite]]
name = "contrato-alpha"
root = "packages/alpha"
command = "sh ../../suite.sh alpha {junit}"
globs = ["tests/**"]

[[suite]]
name = "contrato-beta"
root = "packages/beta"
command = "sh ../../suite.sh beta {junit}"
globs = ["tests/**"]
TOML
  must_accept "TypeScript fixture and manual config" commit commit_all "test: workspace para build"
  BASE=$(head_rev)
  : > "$CW/order"; : > "$CW/build-heads"
}
b16_prepare_green() {
  # The setup does not depend on the current shipcraft knowing [build].
  sh build.sh >> "$LOG" 2>&1 || fail "harness: initial tsc -b"
  must_accept "fixture RED with prebuilt output" cmd shipcraft red
  must_accept "commit RED" commit commit_all "test: RED do build"
  printf 'export function value(): number { return 1; }\n' > packages/alpha/src/mod.ts
  printf 'export function value(): number { return 1; }\n' > packages/beta/src/mod.ts
  sh build.sh >> "$LOG" 2>&1 || fail "harness: tsc -b GREEN"
  must_accept "GREEN with updated ignored output" commit commit_all "feat: valores"
  chk "lock closed before CI" one_lock_head_state closed
  chk "clean tree before CI" tree_clean
  : > "$CW/order"; : > "$CW/build-heads"
}
b16_count() { wc -l < "$1" | tr -d ' '; }
b16_order() {
  chk "build once before both suites" eq "$(cat "$CW/order")" "$(printf 'build\nalpha\nbeta')"
  chk "build only on the judged HEAD" eq "$(cat "$CW/build-heads")" "$(git rev-parse HEAD)"
}
b16_refusal() {
  chk "refused" rc_nonzero
  msg_check || fail "refusal without three lines: $MSGERR"
  chk "what happened" grep -q '^shipcraft refused:' "$OUT.last3"
  chk "why" grep -q '^Why:' "$OUT.last3"
  chk "next step" grep -q '^Next:' "$OUT.last3"
}
b16_build_failure() {
  local phase="$1" mode="$2"
  b16_project
  [ "$phase" = ci ] && b16_prepare_green
  if [ "$mode" = exit ]; then
    printf '#!/bin/sh\nexit 23\n' > build.sh
  else
    printf '#!/bin/sh\nkill -TERM $$\n' > build.sh
  fi
  must_accept "failing build committed" commit commit_all "test: build interrompido"
  : > "$CW/order"; : > "$CW/build-heads"
  if [ "$phase" = red ]; then run_cmd shipcraft red
  else run_cmd shipcraft ci --base "$BASE"; fi
  b16_refusal
  chk "message names build and command" last3_has 'the build failed.*sh build.sh'
  if [ "$mode" = exit ]; then chk "real build exit code" last3_has 'exited with 23'
  else chk "build signal" last3_has '(exited with 143|signal.*(15|TERM))'; fi
  chk "reason: avoid judging old code" last3_has 'tests import the build output; without it, old code would be judged'
  chk "guidance to fix at the root" last3_has 'run.*sh build.sh.*at the root.*fix'
  [ "$phase" = red ] && chk "RED also mentions the stub" last3_has 'stub'
  chk "no suite run after build failure" eq "$(b16_count "$CW/order")" 0
  pass
}
# 16a.1: build output must not stick to the final message.
b16_build_output_failure() {
  local mode="$1"
  b16_project
  case "$mode" in
    stdout-sem-lf) printf "#!/bin/sh\nprintf 'Building...'\nexit 23\n" > build.sh ;;
    stderr-sem-lf) printf "#!/bin/sh\nprintf 'Building...' >&2\nexit 23\n" > build.sh ;;
    stdout-com-lf) printf "#!/bin/sh\nprintf 'Building...\\n'\nexit 23\n" > build.sh ;;
  esac
  must_accept "build with output committed" commit commit_all "test: saida do build"
  : > "$CW/order"; : > "$CW/build-heads"
  run_cmd shipcraft red
  chk "build failed" rc_nonzero
  # Check the suite even when the message fails the red check.
  chk "no suite run after build failure" eq "$(b16_count "$CW/order")" 0
  b16_refusal
  cat > "$CW/recusa-esperada" <<'MSG'
shipcraft refused: the build failed (`exec sh build.sh` exited with 23)
Why: tests import the build output; without it, old code would be judged
Next: run `exec sh build.sh` at the root and fix the error; if it fails because the stub is missing, create the stub: export the function with the right signature and body `throw new Error("not implemented")`
MSG
  chk "last three lines are exactly the build-failed refusal" cmp -s "$CW/recusa-esperada" "$OUT.last3"
  pass
}
b16_missing_report() {
  local naming="$1" diagnostic="$2" exit16=37
  [ "$naming" = pasta ] && exit16=0
  b16_project
  # Only the second suite writes no JUnit; the first runs real Vitest.
  if [ "$naming" = pasta ]; then
    perl -ni -e 'print unless /^name = /' .shipcraft.toml
    SUITE16='packages/beta'
    must_accept "unnamed suites before RED" commit commit_all "test: suites identificadas pela pasta"
    BASE=$(head_rev)
    b16_prepare_green
  else SUITE16='contrato-beta'; fi
  if [ "$diagnostic" = longo ] || [ "$diagnostic" = longo-vazio ]; then
    cat > sem-junit.sh <<'SH'
#!/bin/sh
python3 - <<'PYERR'
import sys
sys.stderr.write(" " * 73728 + "\n   \n\n")
PYERR
SH
    if [ "$diagnostic" = longo ]; then
      printf 'printf "missing dependency in runner\\nmisleading last line\\n" >&2\n' >> sem-junit.sh
    fi
    printf 'exit 37\n' >> sem-junit.sh
  elif [ "$diagnostic" = stderr ]; then
    printf '#!/bin/sh\nprintf "\\n   \\noriginal error 16a\\nmisleading last line\\n" >&2\nexit 37\n' > sem-junit.sh
  else
    printf '#!/bin/sh\nprintf "saida so no stdout 16a\\n"\nexit %s\n' "$exit16" > sem-junit.sh
  fi
  must_accept "command without report committed" commit commit_all "test: runner sem JUnit"
  sh build.sh >> "$LOG" 2>&1 || fail "harness: tsc to test the diagnostic in isolation"
  if [ "$naming" = pasta ]; then run_cmd shipcraft ci --base "$BASE"
  else run_cmd shipcraft red; fi
  b16_refusal
  chk "refusal names the second suite" grep -F -q "$SUITE16" "$OUT.last3"
  chk "refusal names the command without JUnit" grep -F -q 'sh ../../suite.sh beta' "$OUT.last3"
  if [ "$diagnostic" = longo ]; then
    chk "first refusal line keeps stderr after 72 KiB of blanks" sh -c 'head -n 1 "$1" | grep -F -q "missing dependency in runner"' sh "$OUT.last3"
    chk "does not swap in the last line" last3_hasnt 'misleading last line'
  elif [ "$diagnostic" = longo-vazio ]; then
    chk "first refusal line reports exit 37 without a real line" sh -c 'head -n 1 "$1" | grep -E -q "(code|exit|exited).*37([^0-9]|$)"' sh "$OUT.last3"
    chk "blanks do not become a diagnostic" last3_hasnt 'wrote to stderr:'
  elif [ "$diagnostic" = stderr ]; then
    chk "first non-empty stderr line in the refusal" grep -F -q 'original error 16a' "$OUT.last3"
    chk "does not swap in the last line" last3_hasnt 'misleading last line'
  else
    chk "without stderr, reports the runner exit code" last3_has "(code|exit|exited).*${exit16}([^0-9]|$)"
    chk "stdout does not replace stderr" last3_hasnt 'saida so no stdout 16a'
  fi
  pass
}
item16a_case() {
  EXPECT="16a contract holds"
  case "$CASE" in
    v1-16a.1-red-build)
      # 16a.1 example: a clean RED builds at the root before any suite.
      b16_project
      run_cmd shipcraft red
      chk "build once then both suites twice in config order" eq "$(cat "$CW/order")" "$(printf 'build\nalpha\nbeta\nalpha\nbeta')"
      chk "build only on judged HEAD" eq "$(cat "$CW/build-heads")" "$(git rev-parse HEAD)"
      chk "real RED accepted" rc_zero
      chk "output written in the tree itself" test -f packages/alpha/dist/mod.js
      chk "generated output is ignored" git check-ignore -q packages/alpha/dist/mod.js
      chk "real JUnit produced a lock" one_lock_tree_state open
      pass ;;
    v1-16a.1-ci-so-head)
      # 16a.1 edge: history has a RED with 0; only HEAD with 1 is built.
      b16_project; b16_prepare_green
      rm -rf packages/alpha/dist packages/beta/dist
      rm -f packages/alpha/tsconfig.tsbuildinfo packages/beta/tsconfig.tsbuildinfo
      run_cmd shipcraft ci --base "$BASE"
      b16_order
      chk "CI accepts rebuilt HEAD without judging the old RED with a build" rc_zero
      chk "CI left output in the tree itself" test -f packages/beta/dist/mod.js
      pass ;;
    v1-16a.1-red-build-exit) b16_build_failure red exit ;;
    v1-16a.1-ci-build-exit) b16_build_failure ci exit ;;
    v1-16a.1-red-build-stdout-sem-lf) b16_build_output_failure stdout-sem-lf ;;
    v1-16a.1-red-build-stderr-sem-lf) b16_build_output_failure stderr-sem-lf ;;
    v1-16a.1-red-build-stdout-com-lf) b16_build_output_failure stdout-com-lf ;;
    v1-16a.1-red-build-sinal) b16_build_failure red sinal ;;
    v1-16a.1-ci-build-sinal) b16_build_failure ci sinal ;;
    v1-16a.1-ci-suja-indice|v1-16a.1-ci-suja-arvore)
      # 16a.1 copy: CI with a build refuses both staged and unstaged changes.
      b16_project; b16_prepare_green
      printf '// alteracao pendente\n' >> packages/alpha/src/mod.ts
      [ "$CASE" = v1-16a.1-ci-suja-indice ] && git add packages/alpha/src/mod.ts
      run_cmd shipcraft ci --base "$BASE"
      b16_refusal
      chk "refusal mentions build" last3_has 'build'
      chk "explains dirty tree" last3_has '(dirty|chang|pending)'
      chk "suggests commit or stash" last3_has '(commit|stash)'
      chk "neither build nor suites run" eq "$(b16_count "$CW/order")" 0
      pass ;;
    v1-16a.1-hook-saida-ignorada|v1-16a.1-hook-sem-saida)
      # 16a.1 copy: the hook uses existing ignored output; it does not build missing output.
      b16_project
      sh build.sh >> "$LOG" 2>&1 || fail "harness: manual build"
      must_accept "prebuilt RED" cmd shipcraft red
      must_accept "commit RED" commit commit_all "test: RED"
      printf 'export function value(): number { return 1; }\n' > packages/alpha/src/mod.ts
      printf 'export function value(): number { return 1; }\n' > packages/beta/src/mod.ts
      sh build.sh >> "$LOG" 2>&1 || fail "harness: manual GREEN build"
      if [ "$CASE" = v1-16a.1-hook-sem-saida ]; then
        rm -rf packages/alpha/dist packages/beta/dist
      fi
      : > "$CW/order"; : > "$CW/build-heads"
      run_cmd commit_all "feat: valores"
      chk "hook never runs the build" eq "$(b16_count "$CW/build-heads")" 0
      if [ "$CASE" = v1-16a.1-hook-saida-ignorada ]; then
        chk "commit accepted with ignored output" rc_zero
        chk "ignored output closes the lock" one_lock_head_state closed
      else
        chk "hook did not create the output" test ! -e packages/alpha/dist/mod.js
        chk "no output, lock stays open" one_lock_tree_state open
      fi
      pass ;;
    v1-16a.2-stderr-apos-64k) b16_missing_report nome longo ;;
    v1-16a.2-stderr-vazio-apos-64k) b16_missing_report nome longo-vazio ;;
    v1-16a.2-nome-stderr) b16_missing_report nome stderr ;;
    v1-16a.2-pasta-stderr) b16_missing_report pasta stderr ;;
    v1-16a.2-nome-exit) b16_missing_report nome exit ;;
    v1-16a.2-pasta-exit) b16_missing_report pasta exit ;;
  esac
}
item16a_langs() { echo node; }
