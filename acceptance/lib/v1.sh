# Library of the v1 battery (docs/spec.md). Sourced by run.sh.
# Helpers (stubs, PR, "GitHub" state), per-language scenarios (items 6, 8, 9.1) and the v1 cases.
# Each case names the spec item and rule in its id and in a one-line comment.
# bash 3.2: no associative arrays; with `set -u`, never expand empty arrays.

# Fresh target per case; /. lets a partial attempt complete without nesting the base.
copy_base() { # copy_base <base> <target>
  if [ "${SHIPCRAFT_ACCEPTANCE_CLONE:-1}" != 0 ]; then
    case "$(uname -s)" in
      Darwin) cp -cR "$1/." "$2" 2>/dev/null && return 0 ;;
      Linux) cp -R --reflink=auto "$1/." "$2" 2>/dev/null && return 0 ;;
    esac
  fi
  cp -R "$1/." "$2"
}

H() { "$PY" "$ACEITE/tools/h.py" "$@"; }
TMO() { "$PY" "$ACEITE/tools/tmo.py" "$@"; }

# ---------------------------------------------------------------- case lists
fonte15a_cases() {
  echo v1-15a.fonte-config-arquivo
  echo v1-15a.fonte-config-arquivo-com-yaml
  # 15a.2: sources with no YAML config at the root; examples, edges and controls.
  for kind in config-yml toml oculto-jsonc local-yml config-local-yaml env-definida env-vazia config-ilegivel link-quebrado git-config-falha subpasta ausente parecido-extensao parecido-subpasta; do
    echo "v1-15a.fonte-$kind"
  done
}

core_cases() { # the language-independent cases; the queue ones (item 7) first, they are the longest
  english_cases
  item_cases core
  echo v1-7.1-fila-um-slot v1-7.1-fila-dois-slots v1-7.2-fila-posicao v1-7.2-fila-tempo-libera v1-7.2-ci-tempo-esgotado-libera v1-7.3-hook-fora-da-fila
  echo v1-1.1-padrao-local v1-1.1-sem-revisor v1-1.2-revisao-github-recusada v1-1.2-valor-invalido
  echo v1-1.3-base-config-desliga v1-1.3-base-config-liga
  echo v1-2.3-tela-do-init v1-2.3-padrao-primeiro-instalado
  echo v1-2.5-agents-novo v1-2.5-agents-acrescenta v1-2.5-agents-uma-vez v1-2.5-agents-link
  echo v1-3.1-push-e-pr v1-3.2-ci-local-publica-status v1-3.2-ci-falha-sem-revisao
  echo v1-3.3-revisao-local-status-e-comentario v1-3.4-ci-github-nada-local
  echo v1-3.4-ci-github-espera-success-e-revisa v1-3.4-ci-github-failure-nao-revisa v1-3.4-ci-github-sem-status-nao-revisa
  echo v1-3.5-desligado-publica-success v1-3.5-desligado-so-a-revisao
  echo v1-3.6-resumo-de-medicao-no-pr v1-3.7-revisao-local-sem-publicar
  echo v1-3.7-revisao-pr-copia-isolada v1-3.7-revisao-pr-fork-recusado
  echo v1-4.1-brief-completa v1-4.2-veredito-changes-requested v1-4.2-veredito-fora-da-primeira-linha
  echo v1-4.2-veredito-com-linha-em-branco-antes v1-4.2-veredito-com-texto-depois-da-sha v1-1.3-comando-do-runner-vem-da-base v1-1.3-config-da-ponta-do-branch-base
  echo v1-4.3-recusa-do-revisor v1-4.3-saida-nao-zero v1-4.3-tempo-esgotado v1-4.3-pending-velho-refeito
  echo v1-4.4-patch-id-reaproveita
  echo v1-5.1-merge-com-os-dois v1-5.1-merge-sem-revisao-recusa v1-5.1-merge-revisao-failure-recusa
  echo v1-5.1-merge-sem-ci-recusa v1-5.1-merge-status-de-outro-commit v1-5.1-merge-camada-desligada-nao-exige
  echo v1-5.2-sem-revisao-com-motivo v1-5.2-sem-revisao-nao-vale-para-o-ci
  echo v1-5.3-init-github-marca-obrigatorios v1-5.3-init-github-plano-gratis v1-5.4-status-nivel-de-protecao
  echo v1-5.5-ci-na-main-avisa-merges
  echo v1-9.1-monorepo-casos-por-suite v1-9.2-sc2-min v1-9.2-formato-da-trava
  echo v1-15c.trava-hook-comum v1-15c.trava-hook-borda v1-15c.trava-ci-comum v1-15c.trava-ci-borda
  echo v1-15c.status-sem-exec-borda
  echo v1-15c.trava-local-hook-comum v1-15c.trava-local-hook-borda
  echo v1-15c.trava-local-ci-comum v1-15c.trava-local-ci-borda
  fonte15a_cases
  echo v1-10.1-execucoes-jsonl
  echo v1-11.1-linha-de-tamanho v1-11.1-tamanho-desde-o-merge-base v1-11.1-pr-so-de-teste
  echo v1-11.2-testes-e-apoio-fora v1-11.2-globs-do-toml v1-11.2-globs-de-suite v1-11.2-renomeado-sem-mudanca-fora v1-11.2-lockfile-fora v1-11.2-binario-fora
  echo v1-11.3-aviso-acima-de-500 v1-11.3-sem-aviso-em-500 v1-11.3-aviso-linhas-maior-na-config v1-11.3-aviso-linhas-menor-na-config
  echo v1-11.4-linhas-produto-no-jsonl
  echo v1-15a.1-recusa-antes-de-perguntar-e-escrever v1-15a.1-decide-antes-e-desfaz-escrita-no-meio
  echo v1-15a.1-falha-preserva-config-simbolica
  echo v1-15a.2-hook-pre-commit-alheio v1-15a.2-hook-script-ou-link-quebrado
  echo v1-15a.2-core-hookspath-fora v1-15a.2-core-hookspath-absoluto-e-git-hooks
  echo v1-15a.2-core-hookspath-com-espacos
  echo v1-15a.3-core-hookspath-grafias-equivalentes v1-15a.3-core-hookspath-exato
  echo v1-15a.2-husky-ou-pre-commit-na-raiz v1-15a.2-husky-vazio-ou-junto-com-lefthook
  echo v1-15a.2-lefthook-dois-nomes-ou-hook-alheio v1-15a.2-lefthook-condicoes-do-15b-ponto-1
}
lang_v1_cases() { # v1 cases per language
  item_cases "$1"
  echo v1-6.1-fora-do-commit v1-6.2-nao-rastreado-fica-fora v1-6.2-ignorado-entra v1-6.3-so-os-casos-travados
  echo v1-8.1-arquivos-de-apoio
  echo v1-13.1-teste-antigo-nao-executa v1-13.1-teste-antigo-quebrado-nao-bloqueia v1-13.1-teste-antigo-editado-recusado v1-13.1-caso-executado-que-falha-bloqueia v1-13.1-caso-pulado-no-red-que-passa-a-falhar-bloqueia v1-13.1-mesmo-nome-em-dois-arquivos v1-13.1-mesmo-arquivo-em-duas-pastas v1-13.2-fecha-so-com-todos-os-do-red
  echo v1-13.1-erro-de-coleta-fora-do-red-nao-recusa
  echo v1-14.1-arquivo-solto-teste-com-git v1-14.1-copia-com-historia-e-ci-na-arvore-suja v1-14.1-primeiro-red-sem-commit
  [ "$1" = python ] && echo v1-6.3-teste-novo-que-nao-importa v1-6.3-teste-novo-com-glob-do-projeto v1-13.1-junit-prefix-nao-recusa v1-13.1-doctest-nao-recusa v1-13.1-erro-de-coleta-com-arquivos-no-comando-nao-recusa v1-13.1-arquivos-no-comando-teste-antigo-nao-executa
  case "$1" in
    node) echo v1-13.1-verifica-fora-do-hook v1-13.1-init-escreve-verifica v1-13.1-init-verifica-com-traco v1-13.1-ci-roda-verifica v1-9.1-init-pnpm v1-9.1-init-workspaces-do-package-json v1-12.1-npx-tsc-com-traco v1-12.1-todo-npx-com-traco v1-13.1-jest-teste-antigo-nao-executa v1-13.1-jest-rootdir-src-teste-antigo-nao-executa ;;
    go) echo v1-13.1-verifica-fora-do-hook v1-13.1-init-escreve-verifica v1-13.1-ci-roda-verifica v1-9.1-init-go-work ;;
  esac
}

# ---------------------------------------------------------------- general helpers
chk() { # chk <label> <command...>: fails the case with the last line of the command's output
  local label="$1" o; shift
  if o=$("$@" 2>&1); then echo "ok: $label" >> "$LOG"
  else echo "$o" >> "$LOG"; fail "$label${o:+: $(printf '%s' "$o" | tail -n 1 | cut -c1-90)}"; fi
}
eq() { [ "$1" = "$2" ] || { echo "got '$1', want '$2'"; return 1; }; }
ne() { [ "$1" != "$2" ] || { echo "both '$1'"; return 1; }; }
match() { printf '%s\n' "$2" | grep -E -q -- "$1" || { echo "no /$1/ in: $(printf '%s' "$2" | head -c 100)"; return 1; }; }
nomatch() { ! printf '%s\n' "$2" | grep -E -q -- "$1" || { echo "unexpected /$1/ in: $(printf '%s' "$2" | head -c 100)"; return 1; }; }
imatch() { printf '%s\n' "$2" | grep -E -i -q -- "$1" || { echo "no /$1/ (i) in: $(printf '%s' "$2" | head -c 100)"; return 1; }; }
out_has() { grep -E -q -- "$1" "$OUT" || { echo "output lacks /$1/; last: $(last_line)"; return 1; }; }
out_hasi() { grep -E -i -q -- "$1" "$OUT" || { echo "output lacks /$1/ (i); last: $(last_line)"; return 1; }; }
last3_has() { grep '[^[:space:]]' "$OUT" | tail -n 3 | grep -E -i -q -- "$1" || { echo "the last 3 lines lack /$1/"; return 1; }; }
last3_hasnt() { ! grep '[^[:space:]]' "$OUT" | tail -n 3 | grep -E -i -q -- "$1" || { echo "the last 3 lines match /$1/"; return 1; }; }
rc_zero() { [ "$RC" -eq 0 ] || { echo "rc=$RC: $(last_line)"; return 1; }; }
rc_nonzero() { [ "$RC" -ne 0 ] || { echo "rc=0, wanted a failure"; return 1; }; }
nonempty() { [ -n "$1" ] || { echo "empty"; return 1; }; }
tget() { H toml-get .shipcraft.toml "$1"; }
tset() { H toml-set .shipcraft.toml "$1" "$2" "$3"; }

# ---------------------------------------------------------------- environment of a v1 project
# Each project has a stubs folder ($CB: gh, agents, state in $CB/state) and a PATH with only
# what the case wants: no real gh or agent is visible.
stubs_for() { # stubs_for <cbdir> [agents...]
  local cb="$1"; shift
  mkdir -p "$cb/state"
  cp "$ACEITE/stubs/gh" "$cb/gh"; chmod +x "$cb/gh"
  local a
  for a in "$@"; do cp "$ACEITE/stubs/agent" "$cb/$a"; chmod +x "$cb/$a"; done
}
use_proj() { # use_proj <project dir> <stubs dir>
  T="$1"; CB="$2"; ST="$CB/state"
  cd "$T" || exit 1
  export VIRTUAL_ENV="$T/.venv"
  PATH="$CB:$T/.venv/bin:$WORK/bin:$CLEAN_REST"; export PATH
}
v1_start() { # v1_start [agents...]: the case's project ($T) with stubs in $CW/bin
  stubs_for "$CW/bin" "$@"
  use_proj "$T" "$CW/bin"
}
rev_cfg() { H rev-cfg "$ST/reviewer.json" "$@"; }
rev_n() { H rev-calls "$ST" "$@"; }
osha() { git --git-dir="$(cat "$ST/origin")" rev-parse -q --verify "refs/heads/$1" 2>/dev/null || true; }
probe_runs() { if [ -f "$CB/probe.log" ]; then grep -c ran "$CB/probe.log" || true; else echo 0; fi; }
old_runs() { if [ -f "$OLDLOG" ]; then grep -c ran "$OLDLOG" || true; else echo 0; fi; }
# the old test is locked (the lock names the file) and is not in failing_at_red (item 13, rule 1)
old_locked_not_failing() {
  local lf; lf=$(lock_files_head); [ "$(printf '%s\n' "$lf" | count_lines)" -eq 1 ] || { echo "want one committed lock, got: $lf"; return 1; }
  git show "HEAD:$lf" > "$CW/lock.json"
  grep -F -q -- "$OLDFILE" "$CW/lock.json" || { echo "the lock does not mention $OLDFILE"; return 1; }
  ! H lock-failing "$CW/lock.json" | grep -F -q -- old || { echo "failing_at_red lists the old test"; return 1; }
  [ "$(H lock-failing "$CW/lock.json" | count_lines)" -ge 1 ] || { echo "failing_at_red is empty"; return 1; }
}
failing_at_least() { [ "$(H lock-failing "$CW/lock.json" | count_lines)" -ge "$1" ] || { echo "fewer than $1 cases in failing_at_red"; return 1; }; }
# item 13 with jest: Node project with jest 29 and jest-junit; $1 = "rootdir-src" puts `rootDir: "src"` in jest.config.js
jest_old_project() {
  local ws="$CW/jp"
  mkdir -p "$ws/src"; cd "$ws" || exit 1
  git init -q -b main
  printf '{"name":"jp","private":true,"devDependencies":{"jest":"%s","jest-junit":"%s"}}\n' "${SHIPCRAFT_JEST_VERSION:-29.7.0}" "${SHIPCRAFT_JEST_JUNIT_VERSION:-16.0.0}" > package.json
  npm install --ignore-scripts --no-audit --no-fund --loglevel=error >> "$LOG" 2>&1 || fail "harness: npm install of jest"
  [ "${1:-}" = rootdir-src ] && printf 'module.exports = { rootDir: "src" };\n' > jest.config.js
  printf 'module.exports = 0;\n' > src/value.js
  printf 'test("new", () => expect(require("./value")).toBe(1));\n' > src/new.test.js
  printf 'ok\n' > legacy.txt
  cat > src/old.test.js <<JS
test("old", () => {
  require("fs").appendFileSync("$OLDLOG", "ran\n");
  expect(require("fs").readFileSync("legacy.txt", "utf8")).toBe("ok\n");
});
JS
  printf 'node_modules/\n' > .gitignore
  git add -A && git commit -q -m "initial jest project" || fail "harness: commit of the jest project"
}
jest_old_case() { # the old test (passes at RED, probe) does not run in the hook, whatever jest's rootDir
  OLDLOG="$CW/old.log"
  jest_old_project "$1"
  must_accept "shipcraft init" cmd shipcraft init
  chk "init recognised jest" grep -q 'runner = "jest"' .shipcraft.toml
  must_accept "commit of the init files" commit commit_all "chore: shipcraft init"
  BASE=$(head_rev)
  must_accept "shipcraft red" cmd shipcraft red
  must_accept "RED commit" commit commit_all "test: RED"
  git show "HEAD:$(lock_files_head)" > "$CW/lock.json"
  chk "only the new test fails at RED" eq "$(H lock-failing "$CW/lock.json" | count_lines)" 1
  : > "$OLDLOG"
  printf 'module.exports = 1;\n' > src/value.js; printf 'broken\n' > legacy.txt
  must_accept "GREEN: fixes the RED file and breaks the old test through a non-test file" commit commit_all "feat: value"
  chk "the lock closed" one_lock_head_state closed
  chk "the old test never ran in the hook" eq "$(old_runs)" 0
  must_refuse "shipcraft ci runs everything and sees the broken old test" cmd shipcraft ci --base "$BASE"
  pass
}
python_prefix_cfg() { # the project's test command uses --junit-prefix (case ids get a prefix)
  perl -pi -e 's/--junitxml=/--junit-prefix=project --junitxml=/' .shipcraft.toml
  grep -q -- '--junit-prefix=project' .shipcraft.toml || fail "harness: the test_command has no --junitxml= to prefix"
}
python_doctest_cfg() { # --doctest-modules: RED also runs the doctests of a product module
  printf '[pytest]\naddopts = --doctest-modules\n' > pytest.ini
  printf 'def ident(x):\n    """\n    >>> ident(2)\n    2\n    """\n    return x\n' > docmod.py
}
# item 13.1, runner config that breaks the case -> file map: the broken old test does not refuse GREEN
python_map_case() { # python_map_case <config scenario>
  OLDLOG="$CW/old.log"
  L old_probe; commit_all "test: an old test that already passes"
  setup_init
  L "$1"; commit_all "chore: runner config"
  BASE=$(head_rev)
  L stub; L spec_test
  must_accept "shipcraft red" cmd shipcraft red
  must_accept "RED commit" commit commit_all "test: RED"
  git show "HEAD:$(lock_files_head)" > "$CW/lock.json"
  chk "only the slug cases fail at RED" failing_at_least 2
  L implement; L legacy_break
  must_accept "GREEN commit while an old locked test now fails for an unrelated reason" commit commit_all "feat: slugify (and a legacy file changed)"
  chk "the lock closed" one_lock_head_state closed
  must_refuse "shipcraft ci runs the whole suite and sees the old test fail" cmd shipcraft ci --base "$BASE"
  pass
}
# item 13.1 (spec 50f33ed): a collection or compile error outside the RED files never refuses GREEN; it goes to CI
collect_case() { # collect_case [config scenario that changes the test command] [old test scenario] [breakage scenario]
  L "${2:-collect_old}"; commit_all "test: an old test that uses a product API"
  setup_init
  if [ -n "${1:-}" ]; then L "$1"; commit_all "chore: test command config"; BASE=$(head_rev); fi
  L stub; L spec_test
  must_accept "shipcraft red" cmd shipcraft red
  must_accept "RED commit" commit commit_all "test: RED"
  L implement; L "${3:-collect_break}"
  must_accept "GREEN commit while an old test no longer collects or compiles" commit commit_all "feat: slugify (and the legacy API is gone)"
  chk "the RED cases ran anyway: the lock closed" one_lock_head_state closed
  must_refuse "shipcraft ci runs everything and sees the old test fail" cmd shipcraft ci --base "$BASE"
  pass
}
verifica_needle() { case "$TL" in node) echo 'tsc --noEmit' ;; go) echo 'go vet' ;; esac; }
# item 12: an npm workspace with two TypeScript packages (tsconfig with outDir, no noEmit) and a really failing test
ws_ts_project() {
  local ws="$CW/ws" p
  mkdir -p "$ws/packages/api/src" "$ws/packages/web/src"; cd "$ws" || exit 1
  git init -q -b main
  printf '{"name":"root","private":true,"workspaces":["packages/*"]}\n' > package.json
  for p in api web; do
    printf '{"name":"%s","private":true,"type":"module","devDependencies":{"vitest":"%s","typescript":"%s"}}\n' "$p" "${SHIPCRAFT_VITEST_VERSION:-5.0.4}" "${SHIPCRAFT_TS_VERSION:-7.0.2}" > "packages/$p/package.json"
    printf '{"compilerOptions":{"target":"es2022","module":"esnext","moduleResolution":"bundler","strict":true,"outDir":"dist","rootDir":"src","skipLibCheck":true,"types":[]},"include":["src"]}\n' > "packages/$p/tsconfig.json"
    printf 'export function f(): number {\n  throw new Error("todo");\n}\n' > "packages/$p/src/mod.ts"
    printf 'import { expect, it } from "vitest";\nimport { f } from "./mod";\n\nit("f", () => {\n  expect(f()).toBe(1);\n});\n' > "packages/$p/src/mod.test.ts"
  done
  printf 'node_modules/\n' > .gitignore
  npm install --no-audit --no-fund --loglevel=error >> "$LOG" 2>&1 || fail "harness: npm install of the workspace"
  git add -A && git commit -q -m "initial workspace" || fail "harness: commit of the workspace"
}
no_build_output() { # no dist folder (and no new file) outside node_modules
  local d; d=$(find . -name dist -not -path '*/node_modules/*' | head -n 1)
  [ -z "$d" ] || { echo "build output at $d"; return 1; }
  local s; s=$(git status --porcelain --untracked-files=all | grep -v -E '^\?\? \.shipcraft/locks/' || true)
  [ -z "$s" ] || { echo "the tree has new files: $(printf '%s' "$s" | head -n 3 | tr '\n' ' ')"; return 1; }
}
st() { H st-last "$ST" "$1" "$2"; }
st_state() { st "$1" "$2" | cut -f1; }
st_desc() { st "$1" "$2" | cut -f2-; }
nwrites() { H nwrites "$ST" "$@"; }

run_cmd_stdin() { # run_cmd_stdin <file> <command...>
  local f="$1"; shift
  run_cmd "$BASH" -c 'f=$1; shift; exec "$@" < "$f"' _ "$f" "$@"
}

remote_setup() {
  local o="$CB/origin.git"
  git init -q --bare "$o" || fail "harness: git init --bare"
  git --git-dir="$o" symbolic-ref HEAD refs/heads/main
  printf '%s\n' "$o" > "$ST/origin"
  git remote add origin "$o" || fail "harness: remote add"
  git push -q origin main >> "$LOG" 2>&1 || fail "harness: push main"
  git fetch -q origin && git remote set-head origin main >/dev/null 2>&1
}

pr_commit() { # commit_all, or --no-verify when NV is set (config invalid on purpose)
  if [ -n "${NV:-}" ]; then must_accept "$1 (harness)" commit commit_nv "$1"
  else must_accept "$1" commit commit_all "$1"; fi
}
# pr_main: shipcraft init + config ($CFGS: lines "section|key|literal") + markers on main,
# main pushed to origin. AGENTS (agents installed at init) comes from the case.
pr_main() {
  must_accept "shipcraft init" cmd shipcraft init
  if [ -n "${CFGS:-}" ]; then
    local s k v
    while IFS='|' read -r s k v; do
      [ -n "$s$k" ] || continue
      [ "$s" = - ] && s=""   # "-" = top-level key
      H toml-set .shipcraft.toml "$s" "$k" "$v" || fail "harness: toml-set $s $k"
    done <<EOF
$CFGS
EOF
  fi
  mkdir -p docs
  printf 'SPEC-MARKER-5e1: o produto deve ter um shout que grita.\n' > docs/spec-produto.md
  printf '\n\ndef test_bateria_marker_2c7():\n    assert True\n' >> tests/test_smoke.py
  printf 'PR-BODY-MARKER-91b\nIntencao: acrescentar o shout.\n' > "$CW/body.md"
  pr_commit "chore: shipcraft init e config"
  remote_setup
  BASE=$(head_rev)
}
probe_write() { # tests/test_probe.py: records that the suite ran; optionally the timeline
  cat > tests/test_probe.py <<EOF
import time

TL = "${TLINE:-}"
NAME = "${PNAME:-p}"


def test_probe_ci():
    with open("$CB/probe.log", "a") as f:
        f.write("ran\n")
    if TL:
        with open(TL, "a") as f:
            f.write("%s ci start %.3f\n" % (NAME, time.time()))
    time.sleep(${PSLEEP:-0})
    if TL:
        with open(TL, "a") as f:
            f.write("%s ci end %.3f\n" % (NAME, time.time()))
EOF
}
pr_feature() { # pr_feature [branch]: a module, its test and the CI probe, committed
  BR="${1:-feature/alpha}"
  git checkout -q -b "$BR" || fail "harness: checkout -b $BR"
  printf '# diff-marker-4f9a\ndef shout_marker(text):\n    return text.upper() + "!"\n' > shoutmod.py
  printf 'from shoutmod import shout_marker\n\n\ndef test_shout_marker():\n    assert shout_marker("hi") == "HI!"\n' > tests/test_shoutmod.py
  probe_write
  if [ -n "${FAILING:-}" ]; then printf 'def test_always_fails():\n    assert False\n' > tests/test_failing.py; fi
  pr_commit "feat: shout"
}
shipcraft_pr() { # shipcraft pr with title and body; the exit code goes to $RC, not judged
  git rev-parse HEAD > "$ST/sha"
  run_cmd TMO "${PR_TMO:-240}" shipcraft pr --title "Titulo-PR-6d1" --body "$CW/body.md" "$@"
}
gh_quiet() { SHIPCRAFT_STUB_QUIET=1 "$CB/gh" "$@"; }
# a PR not born from shipcraft pr: the branch goes to origin and the PR is opened in "GitHub" directly
pr_outside() { # pr_outside [branch] -> PRN, HEADSHA
  BR="${1:-feature/alpha}"
  git push -q origin "$BR" >> "$LOG" 2>&1 || fail "harness: push $BR"
  gh_quiet pr create --title "PR-de-fora" --body "$(cat "$CW/body.md")" --head "$BR" --base main >> "$LOG" 2>&1 || fail "harness: pr create"
  PRN=$(H prnum "$ST" "$BR")
  HEADSHA=$(git rev-parse "$BR")
}
seed_ok() { H seed-status "$ST" "$1" "$2" success "${3:-on this machine}" 0; }

# ---------------------------------------------------------------- per-language scenarios (items 6, 8)
# --- Python
python_dep_impl() { # the implementation imports a module (slughelper) that stays untracked
  cat > slughelper.py <<'PY'
import re
import unicodedata


def normalize(text):
    t = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-zA-Z0-9]+", "-", t).strip("-").lower()
PY
  printf 'from slughelper import normalize\n\n\ndef slugify(text):\n    return normalize(text)\n' > textutil.py
  DEP_STAGE="textutil.py"
}
python_ign_prepare() { printf 'generated_slug.py\n' >> .gitignore; }
python_ign_impl() { # the implementation imports a generated file, ignored by git
  cat > generated_slug.py <<'PY'
import re
import unicodedata


def convert(text):
    t = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-zA-Z0-9]+", "-", t).strip("-").lower()
PY
  printf 'from generated_slug import convert\n\n\ndef slugify(text):\n    return convert(text)\n' > textutil.py
}
python_extra_fail_test() { printf 'from textutil import slugify\n\n\ndef test_extra_fail():\n    assert slugify("X Y") == "WRONG"\n' > tests/test_extra_fail.py; }
python_support_spec() {
  printf 'import pytest\n\n\n@pytest.fixture\ndef raw_text():\n    return "Olá Mundo!"\n' > conftest.py
  mkdir -p tests/helpers tests/fixtures
  : > tests/helpers/__init__.py
  printf 'def expected():\n    return "ola-mundo"\n' > tests/helpers/util.py
  printf 'ola-mundo\n' > tests/fixtures/expected.txt
  cat > tests/test_slug.py <<'PY'
from pathlib import Path

from textutil import slugify
from tests.helpers.util import expected


def test_slug_support(raw_text):
    want = (Path(__file__).parent / "fixtures" / "expected.txt").read_text().strip()
    assert slugify(raw_text) == expected() == want
PY
  SUPPORT_FILES="conftest.py tests/helpers/util.py tests/fixtures/expected.txt"
}

# --- Items 13 and 14, Python
python_old_probe() { # old test: passes, records each run in $OLDLOG and reads legacy_state.txt (a non-test file)
  OLDFILE=tests/test_old.py
  printf 'ok\n' > legacy_state.txt
  cat > tests/test_old.py <<PY
from pathlib import Path


def test_old_probe():
    with open("$OLDLOG", "a") as f:
        f.write("ran\n")
    assert Path("legacy_state.txt").read_text().strip() == "ok"
PY
}
python_old_touch() { printf '\n# touched\n' >> tests/test_old.py; }
python_legacy_break() { printf 'changed\n' > legacy_state.txt; }
python_shout_odd_test() { # three cases whose names have a space, +, parentheses, brackets and .*
  cat > tests/test_shout.py <<'PY'
import pytest

from shouty import shout


@pytest.mark.parametrize(
    "text,want",
    [("hi", "HI!"), ("a b", "A B!"), ("x+y", "X+Y!")],
    ids=["plain", "with space", "a+b (c)[d].*"],
)
def test_shout_odd(text, want):
    assert shout(text) == want
PY
}
python_legacy_file() { printf 'ok\n' > legacy_state.txt; }
python_mixed_test() { # the same file: one case failing at RED and one passing at RED (reads legacy_state.txt)
  cat > tests/test_slug.py <<'PY'
from pathlib import Path

from textutil import slugify


def test_slug_basic():
    assert slugify("Olá Mundo!") == "ola-mundo"


def test_legacy_ok():
    assert Path("legacy_state.txt").read_text().strip() == "ok"
PY
}
python_flag_off() { printf 'ENABLED = False\n' > flags.py; }
python_flag_on() { printf 'ENABLED = True\n' > flags.py; }
python_skipped_test() { # one case failing at RED and one skipped at RED by a product flag
  cat > tests/test_slug.py <<'PY'
import pytest

import flags
from textutil import slugify


def test_slug_basic():
    assert slugify("Olá Mundo!") == "ola-mundo"


@pytest.mark.skipif(not flags.ENABLED, reason="flag off")
def test_flagged():
    assert False
PY
}
python_same_name() { # test_value in two files; only a's fails at RED; b's records the run and reads stateb.txt
  printf 'ok\n' > stateb.txt
  printf 'def value():\n    return 0\n' > moda.py
  printf 'import moda\n\n\ndef test_value():\n    assert moda.value() == 1\n' > tests/test_a.py
  cat > tests/test_b.py <<PY
from pathlib import Path


def test_value():
    with open("$OLDLOG", "a") as f:
        f.write("ran\n")
    assert Path("stateb.txt").read_text().strip() == "ok"
PY
}
python_same_name_green() { printf 'def value():\n    return 1\n' > moda.py; printf 'changed\n' > stateb.txt; }
python_two_dirs() { # test_value.py at the root (passes at RED, probe) and tests/test_value.py (fails at RED)
  printf 'ok\n' > legacy_value.txt
  printf 'def new():\n    return 0\n' > valuemod.py
  printf 'import valuemod\n\n\ndef test_new():\n    assert valuemod.new() == 1\n' > tests/test_value.py
  cat > test_value.py <<PY
from pathlib import Path


def test_legacy():
    with open("$OLDLOG", "a") as f:
        f.write("ran\n")
    assert Path("legacy_value.txt").read_text().strip() == "ok"
PY
}
python_two_dirs_green() { printf 'def new():\n    return 1\n' > valuemod.py; printf 'changed\n' > legacy_value.txt; }
python_ls_test() { # one case failing at RED and one passing at RED that calls git ls-files
  cat > tests/test_slug.py <<'PY'
import subprocess

from textutil import slugify


def test_slug_basic():
    assert slugify("Olá Mundo!") == "ola-mundo"


def test_git_lists_the_tests():
    out = subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout
    assert "tests/test_slug.py" in out.splitlines()
PY
}
python_collect_old() { # an old test that imports a product API
  printf 'def old():\n    return True\n' > legacy.py
  printf 'from legacy import old\n\n\ndef test_old():\n    assert old()\n' > tests/test_old.py
}
python_collect_break() { printf '# the legacy API was removed\n' > legacy.py; }
python_explicit_cfg() { # the project's test command names the test files
  perl -pi -e 's/-m pytest /-m pytest tests\/test_smoke.py tests\/test_slug.py tests\/test_old.py /' .shipcraft.toml
  grep -q 'tests/test_old.py' .shipcraft.toml || fail "harness: the test_command has no '-m pytest ' to extend"
}
python_git_test_basic() { # the case failing at RED also calls git
  cat > tests/test_slug.py <<'PY'
import subprocess

from textutil import slugify


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def test_slug_in_a_git_checkout():
    assert slugify("Olá Mundo!") == "ola-mundo"
    assert git("rev-parse", "--is-inside-work-tree").stdout.strip() == "true"
    assert git("rev-parse", "HEAD").returncode == 0
PY
}
python_git_test_deep() { # the copy's git has the history and the tracked files, like a clone
  cat > tests/test_slug.py <<'PY'
import subprocess

from textutil import slugify


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True)


def test_slug_in_a_git_clone():
    assert slugify("Olá Mundo!") == "ola-mundo"
    assert "test: RED slugify" in git("log", "--format=%s").stdout.splitlines()
    assert "tests/test_slug.py" in git("ls-files").stdout.split()
PY
}

# --- Node (TypeScript + vitest)
node_dep_impl() {
  printf 'export function normalize(text: string): string {\n  return text\n    .normalize("NFKD")\n    .replace(/[\\u0300-\\u036f]/g, "")\n    .replace(/[^a-zA-Z0-9]+/g, "-")\n    .replace(/^-+|-+$/g, "")\n    .toLowerCase();\n}\n' > src/slughelper.ts
  printf 'import { normalize } from "./slughelper";\n\nexport const name = "textutil";\n\nexport function slugify(text: string): string {\n  return normalize(text);\n}\n' > src/textutil.ts
  DEP_STAGE="src/textutil.ts"
}
node_ign_prepare() { printf 'src/gen_table.ts\n' >> .gitignore; }
node_ign_impl() {
  printf 'export function convert(text: string): string {\n  return text\n    .normalize("NFKD")\n    .replace(/[\\u0300-\\u036f]/g, "")\n    .replace(/[^a-zA-Z0-9]+/g, "-")\n    .replace(/^-+|-+$/g, "")\n    .toLowerCase();\n}\n' > src/gen_table.ts
  printf 'import { convert } from "./gen_table";\n\nexport const name = "textutil";\n\nexport function slugify(text: string): string {\n  return convert(text);\n}\n' > src/textutil.ts
}
node_extra_fail_test() { printf 'import { expect, it } from "vitest";\nimport { slugify } from "./textutil";\n\nit("extra fail", () => {\n  expect(slugify("X Y")).toBe("WRONG");\n});\n' > src/extra_fail.test.ts; }
node_support_spec() {
  mkdir -p src/__tests__/helpers
  printf 'import { defineConfig } from "vitest/config";\nexport default defineConfig({ test: {} });\n' > vitest.config.ts
  printf 'export default {};\n' > jest.config.js
  printf 'export function expected(): string {\n  return "ola-mundo";\n}\n' > src/__tests__/helpers/util.ts
  cat > src/slug.test.ts <<'TS'
import { expect, it } from "vitest";
import { slugify } from "./textutil";
import { expected } from "./__tests__/helpers/util";

it("support", () => {
  expect(slugify("Olá Mundo!")).toBe(expected());
});
TS
  SUPPORT_FILES="vitest.config.ts jest.config.js src/__tests__/helpers/util.ts"
}

# --- Items 13 and 14, Node
node_old_probe() { # in .js: the test command's tsc does not look at it
  OLDFILE=src/old.test.js
  printf 'ok\n' > legacy_state.txt
  cat > src/old.test.js <<JS
import { appendFileSync, readFileSync } from "node:fs";
import { expect, it } from "vitest";

it("old probe", () => {
  appendFileSync("$OLDLOG", "ran\n");
  expect(readFileSync("legacy_state.txt", "utf8").trim()).toBe("ok");
});
JS
}
node_old_touch() { printf '\n// touched\n' >> src/old.test.js; }
node_legacy_break() { printf 'changed\n' > legacy_state.txt; }
node_shout_odd_test() {
  cat > src/shout.test.ts <<'TS'
import { describe, expect, it } from "vitest";
import { shout } from "./shout";

describe("shout (odd) [names] .*", () => {
  it("plain", () => {
    expect(shout("hi")).toBe("HI!");
  });
  it("with space", () => {
    expect(shout("a b")).toBe("A B!");
  });
  it("a+b (c)[d].*", () => {
    expect(shout("x+y")).toBe("X+Y!");
  });
});
TS
}
node_legacy_file() { printf 'ok\n' > legacy_state.txt; }
node_mixed_test() {
  cat > src/slug.test.ts <<'TS'
// @ts-ignore: o alvo nao tem @types/node
import { readFileSync } from "node:fs";
import { expect, it } from "vitest";
import { slugify } from "./textutil";

it("slug basic", () => {
  expect(slugify("Olá Mundo!")).toBe("ola-mundo");
});

it("legacy ok", () => {
  expect(String(readFileSync("legacy_state.txt", "utf8")).trim()).toBe("ok");
});
TS
}
node_flag_off() { printf 'export const enabled: boolean = false;\n' > src/flags.ts; }
node_flag_on() { printf 'export const enabled: boolean = true;\n' > src/flags.ts; }
node_skipped_test() {
  cat > src/slug.test.ts <<'TS'
import { expect, it } from "vitest";
import { enabled } from "./flags";
import { slugify } from "./textutil";

it("slug basic", () => {
  expect(slugify("Olá Mundo!")).toBe("ola-mundo");
});

it.skipIf(!enabled)("flagged", () => {
  expect(true).toBe(false);
});
TS
}
node_same_name() {
  printf 'ok\n' > state_b.txt
  printf 'export const value = (): number => 0;\n' > src/moda.ts
  printf 'import { expect, it } from "vitest";\nimport { value } from "./moda";\n\nit("value", () => {\n  expect(value()).toBe(1);\n});\n' > src/a.test.ts
  cat > src/b.test.js <<JS
import { appendFileSync, readFileSync } from "node:fs";
import { expect, it } from "vitest";

it("value", () => {
  appendFileSync("$OLDLOG", "ran\n");
  expect(readFileSync("state_b.txt", "utf8").trim()).toBe("ok");
});
JS
}
node_same_name_green() { printf 'export const value = (): number => 1;\n' > src/moda.ts; printf 'changed\n' > state_b.txt; }
node_two_dirs() { # src/value.test.ts (passes at RED, probe) and src/sub/value.test.ts (fails at RED)
  mkdir -p src/sub
  printf 'ok\n' > legacy_value.txt
  printf 'export const newValue = (): number => 0;\n' > src/valuemod.ts
  printf 'import { expect, it } from "vitest";\nimport { newValue } from "../valuemod";\n\nit("new", () => {\n  expect(newValue()).toBe(1);\n});\n' > src/sub/value.test.ts
  cat > src/value.test.ts <<TS
// @ts-ignore: o alvo nao tem @types/node
import { appendFileSync, readFileSync } from "node:fs";
import { expect, it } from "vitest";

it("legacy", () => {
  appendFileSync("$OLDLOG", "ran\n");
  expect(String(readFileSync("legacy_value.txt", "utf8")).trim()).toBe("ok");
});
TS
}
node_two_dirs_green() { printf 'export const newValue = (): number => 1;\n' > src/valuemod.ts; printf 'changed\n' > legacy_value.txt; }
node_ls_test() {
  cat > src/slug.test.ts <<'TS'
// @ts-ignore: o alvo nao tem @types/node
import { execSync } from "node:child_process";
import { expect, it } from "vitest";
import { slugify } from "./textutil";

it("slug basic", () => {
  expect(slugify("Olá Mundo!")).toBe("ola-mundo");
});

it("git lists the tests", () => {
  expect(String(execSync("git ls-files", { encoding: "utf8" })).split("\n")).toContain("src/slug.test.ts");
});
TS
}
node_collect_old() {
  printf 'export const old = () => true;\n' > src/legacy.js
  cat > src/old.test.js <<'JS'
import { expect, it } from "vitest";
import { old } from "./legacy.js";

const probe = old.toString();

it("old", () => {
  expect(old()).toBe(true);
  expect(probe).not.toBe("");
});
JS
}
node_collect_break() { printf 'export const other = 1;\n' > src/legacy.js; }
node_ts_old() { # an old TypeScript test that uses a product API
  printf 'export const old = (): boolean => true;\n' > src/legacy.ts
  printf 'import { expect, it } from "vitest";\nimport { old } from "./legacy";\n\nit("old", () => {\n  expect(old()).toBe(true);\n});\n' > src/old.test.ts
}
node_ts_break() { printf 'export const other = 1;\n' > src/legacy.ts; }
node_type_error() { printf 'export const typed: number = "not a number";\n' > src/typed.ts; }
node_git_test_basic() {
  cat > src/slug.test.ts <<'TS'
// @ts-ignore: o alvo nao tem @types/node
import { execSync } from "node:child_process";
import { expect, it } from "vitest";
import { slugify } from "./textutil";

const git = (args: string): string => String(execSync("git " + args, { encoding: "utf8" }));

it("slug in a git checkout", () => {
  expect(slugify("Olá Mundo!")).toBe("ola-mundo");
  expect(git("rev-parse --is-inside-work-tree").trim()).toBe("true");
  git("rev-parse HEAD");
});
TS
}
node_git_test_deep() {
  cat > src/slug.test.ts <<'TS'
// @ts-ignore: o alvo nao tem @types/node
import { execSync } from "node:child_process";
import { expect, it } from "vitest";
import { slugify } from "./textutil";

const git = (args: string): string => String(execSync("git " + args, { encoding: "utf8" }));

it("slug in a git clone", () => {
  expect(slugify("Olá Mundo!")).toBe("ola-mundo");
  expect(git("log --format=%s").split("\n")).toContain("test: RED slugify");
  expect(git("ls-files").split("\n")).toContain("src/slug.test.ts");
});
TS
}

# --- Go
go_dep_impl() {
  cat > helper.go <<'GO'
package textutil

import (
	"strings"
	"unicode"
)

var foldTable = strings.NewReplacer("á", "a", "à", "a", "ã", "a", "â", "a", "é", "e", "ê", "e",
	"í", "i", "ó", "o", "ô", "o", "õ", "o", "ú", "u", "ç", "c")

func normalize(s string) string {
	var b strings.Builder
	dash := false
	for _, r := range foldTable.Replace(strings.ToLower(s)) {
		if r < 128 && (unicode.IsLetter(r) || unicode.IsDigit(r)) {
			b.WriteRune(r)
			dash = false
		} else if !dash && b.Len() > 0 {
			b.WriteByte('-')
			dash = true
		}
	}
	return strings.TrimRight(b.String(), "-")
}
GO
  printf 'package textutil\n\n// Slugify uses the helper.\nfunc Slugify(s string) string { return normalize(s) }\n' > textutil.go
  DEP_STAGE="textutil.go"
}
go_ign_prepare() { printf 'gen_table.go\n' >> .gitignore; }
go_ign_impl() {
  sed -e 's/func normalize/func convert/' -e 's/foldTable/genFold/g' > gen_table.go <<'GO'
package textutil

import (
	"strings"
	"unicode"
)

var foldTable = strings.NewReplacer("á", "a", "à", "a", "ã", "a", "â", "a", "é", "e", "ê", "e",
	"í", "i", "ó", "o", "ô", "o", "õ", "o", "ú", "u", "ç", "c")

func normalize(s string) string {
	var b strings.Builder
	dash := false
	for _, r := range foldTable.Replace(strings.ToLower(s)) {
		if r < 128 && (unicode.IsLetter(r) || unicode.IsDigit(r)) {
			b.WriteRune(r)
			dash = false
		} else if !dash && b.Len() > 0 {
			b.WriteByte('-')
			dash = true
		}
	}
	return strings.TrimRight(b.String(), "-")
}
GO
  printf 'package textutil\n\n// Slugify uses the generated table.\nfunc Slugify(s string) string { return convert(s) }\n' > textutil.go
}
go_extra_fail_test() { printf 'package textutil\n\nimport "testing"\n\nfunc TestExtraFail(t *testing.T) {\n\tif got := Slugify("X Y"); got != "WRONG" {\n\t\tt.Fatalf("Slugify = %%q", got)\n\t}\n}\n' > extra_fail_test.go; }
go_support_spec() {
  mkdir -p testdata
  printf 'ola-mundo\n' > testdata/expected.txt
  printf 'package textutil\n\nfunc expectedSlug() string { return "ola-mundo" }\n' > helper_test.go
  cat > slug_test.go <<'GO'
package textutil

import (
	"os"
	"strings"
	"testing"
)

func TestSlugSupport(t *testing.T) {
	want, err := os.ReadFile("testdata/expected.txt")
	if err != nil {
		t.Fatal(err)
	}
	if got := Slugify("Olá Mundo!"); got != expectedSlug() || got != strings.TrimSpace(string(want)) {
		t.Fatalf("Slugify = %q", got)
	}
}
GO
  SUPPORT_FILES="helper_test.go testdata/expected.txt"
}

# --- Items 13 and 14, Go
go_old_probe() {
  OLDFILE=old_test.go
  printf 'ok\n' > legacy_state.txt
  cat > old_test.go <<GO
package textutil

import (
	"os"
	"strings"
	"testing"
)

func TestOldProbe(t *testing.T) {
	f, err := os.OpenFile("$OLDLOG", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	f.WriteString("ran\n")
	f.Close()
	b, err := os.ReadFile("legacy_state.txt")
	if err != nil || strings.TrimSpace(string(b)) != "ok" {
		t.Fatalf("legacy_state = %q (%v)", b, err)
	}
}
GO
}
go_old_touch() { printf '\n// touched\n' >> old_test.go; }
go_legacy_break() { printf 'changed\n' > legacy_state.txt; }
go_shout_odd_test() {
  cat > shout_test.go <<'GO'
package textutil

import "testing"

func TestShoutOdd(t *testing.T) {
	for _, name := range []string{"plain", "with space", "a+b (c)[d].*"} {
		t.Run(name, func(t *testing.T) {
			if got := Shout("hi"); got != "HI!" {
				t.Fatalf("Shout = %q", got)
			}
		})
	}
}
GO
}
go_legacy_file() { printf 'ok\n' > legacy_state.txt; }
go_mixed_test() {
  cat > slug_test.go <<'GO'
package textutil

import (
	"os"
	"strings"
	"testing"
)

func TestSlugBasic(t *testing.T) {
	if got := Slugify("Olá Mundo!"); got != "ola-mundo" {
		t.Fatalf("Slugify = %q", got)
	}
}

func TestLegacyOK(t *testing.T) {
	b, err := os.ReadFile("legacy_state.txt")
	if err != nil || strings.TrimSpace(string(b)) != "ok" {
		t.Fatalf("legacy_state = %q (%v)", b, err)
	}
}
GO
}
go_flag_off() { printf 'package textutil\n\n// Enabled is a product flag.\nvar Enabled = false\n' > flags.go; }
go_flag_on() { printf 'package textutil\n\n// Enabled is a product flag.\nvar Enabled = true\n' > flags.go; }
go_skipped_test() {
  cat > slug_test.go <<'GO'
package textutil

import "testing"

func TestSlugBasic(t *testing.T) {
	if got := Slugify("Olá Mundo!"); got != "ola-mundo" {
		t.Fatalf("Slugify = %q", got)
	}
}

func TestFlagged(t *testing.T) {
	if !Enabled {
		t.Skip("flag off")
	}
	t.Fatal("enabled, and broken")
}
GO
}
go_same_name() { # TestValue in two packages; only a's fails at RED; b's records the run and reads state.txt
  mkdir -p a b
  printf 'package a\n\n// Value is a stub.\nfunc Value() int { return 0 }\n' > a/a.go
  printf 'package a\n\nimport "testing"\n\nfunc TestValue(t *testing.T) {\n\tif Value() != 1 {\n\t\tt.Fatalf("Value = %%d", Value())\n\t}\n}\n' > a/a_test.go
  printf 'package b\n\n// Value is fine.\nfunc Value() int { return 1 }\n' > b/b.go
  printf 'ok\n' > b/state.txt
  cat > b/b_test.go <<GO
package b

import (
	"os"
	"strings"
	"testing"
)

func TestValue(t *testing.T) {
	f, err := os.OpenFile("$OLDLOG", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	f.WriteString("ran\n")
	f.Close()
	b, err := os.ReadFile("state.txt")
	if err != nil || strings.TrimSpace(string(b)) != "ok" {
		t.Fatalf("state = %q (%v)", b, err)
	}
}
GO
}
go_same_name_green() { printf 'package a\n\n// Value is done.\nfunc Value() int { return 1 }\n' > a/a.go; printf 'changed\n' > b/state.txt; }
go_two_dirs() { # x/sub/value_test.go (nested package, passes at RED, probe) and x/value_test.go (fails at RED)
  mkdir -p x/sub
  printf 'package x\n\n// New is a stub.\nfunc New() int { return 0 }\n' > x/x.go
  printf 'package x\n\nimport "testing"\n\nfunc TestNew(t *testing.T) {\n\tif New() != 1 {\n\t\tt.Fatalf("New = %%d", New())\n\t}\n}\n' > x/value_test.go
  printf 'package sub\n\n// Doc is a package for the nested test.\nconst Doc = "sub"\n' > x/sub/sub.go
  printf 'ok\n' > x/sub/state.txt
  cat > x/sub/value_test.go <<GO
package sub

import (
	"os"
	"strings"
	"testing"
)

func TestLegacy(t *testing.T) {
	f, err := os.OpenFile("$OLDLOG", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	f.WriteString("ran\n")
	f.Close()
	b, err := os.ReadFile("state.txt")
	if err != nil || strings.TrimSpace(string(b)) != "ok" {
		t.Fatalf("state = %q (%v)", b, err)
	}
}
GO
}
go_two_dirs_green() { printf 'package x\n\n// New is done.\nfunc New() int { return 1 }\n' > x/x.go; printf 'changed\n' > x/sub/state.txt; }
go_ls_test() {
  cat > slug_test.go <<'GO'
package textutil

import (
	"os/exec"
	"strings"
	"testing"
)

func TestSlugBasic(t *testing.T) {
	if got := Slugify("Olá Mundo!"); got != "ola-mundo" {
		t.Fatalf("Slugify = %q", got)
	}
}

func TestGitListsTheTests(t *testing.T) {
	out, err := exec.Command("git", "ls-files").Output()
	if err != nil {
		t.Fatalf("git ls-files: %v", err)
	}
	for _, l := range strings.Split(string(out), "\n") {
		if l == "slug_test.go" {
			return
		}
	}
	t.Fatalf("slug_test.go is not listed: %q", out)
}
GO
}
go_collect_old() { # an old test in another package that stops compiling when the product loses the function
  mkdir -p old
  printf 'package old\n\n// Old is a legacy API.\nfunc Old() bool { return true }\n' > old/old.go
  printf 'package old\n\nimport "testing"\n\nfunc TestOld(t *testing.T) {\n\tif !Old() {\n\t\tt.Fatal("Old")\n\t}\n}\n' > old/old_test.go
}
go_collect_break() { printf 'package old\n\n// New replaces the legacy API.\nfunc New() bool { return true }\n' > old/old.go; }
go_type_error() { # compiles and the tests pass, but go vet (copylocks) refuses: outside the subset go test runs
  printf 'package textutil\n\nimport "sync"\n\n// Lock passes a mutex by value.\nfunc Lock(m sync.Mutex) { _ = m }\n' > locked.go
}
go_git_test_basic() {
  cat > slug_test.go <<'GO'
package textutil

import (
	"os/exec"
	"strings"
	"testing"
)

func git(t *testing.T, args ...string) string {
	t.Helper()
	out, err := exec.Command("git", args...).Output()
	if err != nil {
		t.Fatalf("git %v: %v", args, err)
	}
	return string(out)
}

func TestSlugInAGitCheckout(t *testing.T) {
	if got := Slugify("Olá Mundo!"); got != "ola-mundo" {
		t.Fatalf("Slugify = %q", got)
	}
	if strings.TrimSpace(git(t, "rev-parse", "--is-inside-work-tree")) != "true" {
		t.Fatal("not inside a work tree")
	}
	git(t, "rev-parse", "HEAD")
}
GO
}
go_git_test_deep() {
  cat > slug_test.go <<'GO'
package textutil

import (
	"os/exec"
	"strings"
	"testing"
)

func git(t *testing.T, args ...string) string {
	t.Helper()
	out, err := exec.Command("git", args...).Output()
	if err != nil {
		t.Fatalf("git %v: %v", args, err)
	}
	return string(out)
}

func has(lines string, want string) bool {
	for _, l := range strings.Split(lines, "\n") {
		if l == want {
			return true
		}
	}
	return false
}

func TestSlugInAGitClone(t *testing.T) {
	if got := Slugify("Olá Mundo!"); got != "ola-mundo" {
		t.Fatalf("Slugify = %q", got)
	}
	if !has(git(t, "log", "--format=%s"), "test: RED slugify") {
		t.Fatal("the history lacks the RED commit")
	}
	if !has(git(t, "ls-files"), "slug_test.go") {
		t.Fatal("slug_test.go is not tracked")
	}
}
GO
}

# ---------------------------------------------------------------- v1 cases
run_case_v1() {
  case "$CASE" in
  v1-15c.trava-*)
    # Item 15c.2/4: config locked in the hook and CI, in the index or a commit, under all four names.
    EXPECT="lefthook change refused with an open lock"
    v1_start codex
    setup_init
    INIT_HEAD=$(head_rev)
    names="lefthook.yml"
    case "$CASE" in *borda) names=".lefthook.yml lefthook.yaml .lefthook.yaml" ;; esac
    local_change=0
    case "$CASE" in
      *local*comum) names="lefthook-local.yml" ;;
      *local*borda) names="lefthook-local.yml .lefthook-local.yml lefthook-local.yaml .lefthook-local.yaml"; local_change=1 ;;
    esac
    for name in $names; do
      git reset --hard -q "$INIT_HEAD" >> "$LOG" 2>&1
      # Clean only the fixtures the previous iteration created.
      rm -f lefthook.yml .lefthook.yml lefthook.yaml .lefthook.yaml lefthook-local.yml .lefthook-local.yml lefthook-local.yaml .lefthook-local.yaml
      case "$CASE" in *local*) printf 'pre-commit:\n  commands:\n    shipcraft:\n      run: shipcraft check\n      priority: 1\n' > lefthook.yml ;; esac
      if [[ "$CASE" != *local* || "$local_change" = 1 ]]; then
        printf 'pre-commit:\n  commands:\n    shipcraft:\n      run: shipcraft check\n      priority: 9\n' > "$name"
      fi
      must_accept "config before RED" commit commit_all "chore: lefthook"
      BASE=$(head_rev)
      L stub; L spec_test
      must_accept "shipcraft red" cmd shipcraft red
      must_accept "commit RED" commit commit_all "test: RED"
      L implement
      printf '\n# alterado durante GREEN\n' >> "$name"
      case "$CASE" in
        *hook*)
          git add -A
          must_refuse "hook refuses $name" commit commit_index "chore: altera lefthook" ;;
        *ci-comum)
          must_accept "shortcut without hook" commit commit_nv "chore: altera lefthook"
          must_refuse "CI refuses $name" cmd shipcraft ci --base "$BASE" ;;
        *ci-borda)
          # CI judges the committed change under the other three names (15c.4).
          must_accept "shortcut without hook" commit commit_nv "chore: altera lefthook"
          must_refuse "CI refuses $name" cmd shipcraft ci --base "$BASE" ;;
      esac
      chk "refusal names the lefthook config in the three lines" last3_has 'lefthook'
    done
    pass ;;
  v1-15c.*)
    # Items 15c.1 and 15c.3: example and edge for init, status and existing commands.
    EXPECT="lefthook contract 15c"
    v1_start codex
    case "$CASE" in *status-*) setup_init ;; esac
    must_accept "$CASE" cmd "$PY" "$ACEITE/tools/lefthook15c.py" "${CASE#v1-15c.}"
    pass ;;
  v1-15a.fonte-*)
    EXPECT="single lefthook source with no YAML at the root"
    v1_start codex claude
    must_accept "${CASE}: single source contract" cmd "$PY" "$ACEITE/tools/fonte15a.py" "${CASE#v1-15a.fonte-}"
    pass ;;


  # ======================================================== per language: items 6, 8, 9.1
  v1-6.1-fora-do-commit)
    # Item 6, rule 1: untracked files, changes outside the index and editor backups neither block nor affect the commit.
    EXPECT="accepted, lock closed"
    printf 'um\n' > NOTES.md; commit_all "notes"
    setup_red
    L implement; git add -A
    printf 'dois\n' > NOTES.md                       # change outside the index, tracked file
    printf 'rascunho\n' > scratch-notes.txt          # untracked, not ignored
    cp "$TESTFILE" "${TESTFILE}~"                    # editor backup next to the locked test
    must_accept "GREEN commit with stray files around" commit commit_index "feat: slugify"
    chk "the commit closed the lock" one_lock_head_state closed
    chk "the stray files stayed out of the commit" sh -c "! git ls-tree -r --name-only HEAD | grep -E -q 'scratch-notes|~\$'"
    chk "the unstaged edit is still in the tree" sh -c "[ \"\$(cat NOTES.md)\" = dois ]"
    pass ;;
  v1-6.2-nao-rastreado-fica-fora)
    # Item 6, rule 2: an untracked, unignored file stays out (the PR 5 hole): a GREEN that depends on it does not close the lock.
    EXPECT="lock stays open until the helper is added"
    setup_red
    L dep_impl                      # the implementation and the helper, the latter never added to the index
    git add "$DEP_STAGE"
    git status --porcelain | grep -q '^??' || fail "harness: the helper should be untracked"
    run_cmd commit_index "feat: depends on an untracked file"
    if [ "$MOVED" = yes ]; then
      [ "$RC" -eq 0 ] || fail "rc $RC but the commit was made"
      chk "a commit that fails in a clean clone keeps the lock open" one_lock_head_state open
    else
      [ "$RC" -ne 0 ] || fail "rc 0 but no commit was made"
      msg_check || fail "refused, but $MSGERR"
      chk "the refusal is not about files outside the commit (item 6, rule 1)" last3_hasnt 'outside the commit|in the index|stash'
      chk "the refused commit left the lock open" one_lock_head_state open
    fi
    git add -A
    must_accept "commit with the helper added" commit commit_index "feat: add the helper"
    chk "with the helper in the index the lock closes" one_lock_head_state closed
    must_accept "shipcraft ci --base <before RED>" cmd shipcraft ci --base "$BASE"
    pass ;;
  v1-6.2-ignorado-entra)
    # Item 6, rule 2: the tree's ignored files are part of what the hook judges (dependencies, generated files, .env).
    EXPECT="accepted, lock closed"
    L ign_prepare; commit_all "chore: ignore the generated file"
    setup_red
    L ign_impl
    git status --porcelain | grep -q 'gen' && fail "harness: the generated file should be ignored"
    must_accept "GREEN commit depending on an ignored file" commit commit_all "feat: uses a generated file"
    chk "the ignored file counted: the lock closed" one_lock_head_state closed
    pass ;;
  v1-6.3-teste-novo-que-nao-importa)
    # Item 6, rule 3 (and v0, rule 6): the hook runs only the locked cases; a new, unlocked test that does not even import does not block a valid GREEN.
    EXPECT="accepted, lock closed; ci refuses"
    setup_red
    printf 'import unfinished_feature\n\n\ndef test_next():\n    assert unfinished_feature.ok()\n' > tests/test_next.py
    L implement
    must_accept "GREEN commit plus an unlocked test that fails to import" commit commit_all "feat: slugify + next test in progress"
    chk "the hook ran only the locked cases: the lock closed" one_lock_head_state closed
    must_refuse "shipcraft ci runs the whole suite and sees the import error" cmd shipcraft ci --base "$BASE"
    pass ;;
  v1-6.3-teste-novo-com-glob-do-projeto)
    # Item 6, rule 3: "only the locked cases" uses the test globs from the project's .shipcraft.toml, not fixed names (test_*.py): a project that discovers check_*.py can also have the new, unlocked test that does not import yet.
    EXPECT="accepted, lock closed; ci refuses"
    printf '[pytest]\npython_files = check_*.py\n' > pytest.ini
    setup_init
    H toml-set .shipcraft.toml "" test_globs '["**/check_*.py", "**/conftest.py"]' || fail "harness: toml-set"
    must_accept "commit of the project's discovery config" commit commit_all "chore: tests are check_*.py"
    BASE=$(head_rev)
    L stub
    cat > tests/check_slug.py <<'PY'
from textutil import slugify


def test_slug_basic():
    assert slugify("Olá Mundo!") == "ola-mundo"


def test_slug_spaces():
    assert slugify("  a  b ") == "a-b"
PY
    must_accept "shipcraft red" cmd shipcraft red
    must_accept "RED commit" commit commit_all "test: RED slugify"
    printf 'import unfinished_feature\n\n\ndef test_next():\n    assert unfinished_feature.ok()\n' > tests/check_next.py
    L implement
    must_accept "GREEN commit plus an unlocked check_*.py that fails to import" commit commit_all "feat: slugify + next check in progress"
    chk "the hook ran only the locked cases: the lock closed" one_lock_head_state closed
    must_refuse "shipcraft ci runs the whole suite and sees the import error" cmd shipcraft ci --base "$BASE"
    pass ;;
  v1-6.3-so-os-casos-travados)
    # Item 6, rule 3, as item 13 changes it: the hook runs only the cases failing at RED; the whole suite belongs to CI, which refuses the new failing test.
    EXPECT="hook closes the lock; ci refuses"
    setup_red
    L extra_fail_test; L implement
    must_accept "GREEN commit with a new failing (unlocked) test" commit commit_all "feat: slugify + a failing extra test"
    chk "the hook ran only the locked cases: the lock closed" one_lock_head_state closed
    must_refuse "shipcraft ci runs the whole suite and sees the failing extra test" cmd shipcraft ci --base "$BASE"
    pass ;;
  v1-8.1-arquivos-de-apoio)
    # Item 8, rule 1: the init globs cover the language's support files; GREEN does not edit them during the cycle.
    EXPECT="each support file refused"
    setup_init
    L stub; L support_spec
    must_accept "shipcraft red" cmd shipcraft red
    must_accept "RED commit" commit commit_all "test: RED with support files"
    for f in $SUPPORT_FILES; do
      [ -f "$f" ] || fail "harness: $f missing"
      printf '%s\n' "x" >> "$f"
      must_refuse "commit editing the support file $f during the cycle" commit commit_all "cheat: $f"
      git reset -q && git checkout -q -- "$f"
    done
    pass ;;
  v1-13.1-teste-antigo-nao-executa)
    # Item 13, rule 1: the hook runs only the cases failing at RED; the old test (already passing) stays locked by hash and does not run.
    EXPECT="accepted, lock closed, old test never ran"
    OLDLOG="$CW/old.log"
    L old_probe; commit_all "test: an old test that already passes"
    setup_red
    chk "the old test is locked but did not fail at RED" old_locked_not_failing
    : > "$OLDLOG"     # RED ran everything; from here on only the hook counts
    L implement
    must_accept "GREEN commit" commit commit_all "feat: slugify"
    chk "the lock closed" one_lock_head_state closed
    chk "the hook did not execute the old test" eq "$(old_runs)" 0
    pass ;;
  v1-13.1-teste-antigo-quebrado-nao-bloqueia)
    # Item 13, rule 1 (edge): an old test that breaks for an unrelated reason does not block GREEN; only CI, with the whole suite, sees it.
    EXPECT="hook closes the lock; ci refuses"
    OLDLOG="$CW/old.log"
    L old_probe; commit_all "test: an old test that already passes"
    setup_red
    L implement; L legacy_break
    must_accept "GREEN commit while an old locked test now fails for an unrelated reason" commit commit_all "feat: slugify (and a legacy file changed)"
    chk "the lock closed" one_lock_head_state closed
    must_refuse "shipcraft ci runs the whole suite and sees the old test fail" cmd shipcraft ci --base "$BASE"
    pass ;;
  v1-13.1-teste-antigo-editado-recusado)
    # Item 13, rule 1 (edge): the old test stays locked by hash; a GREEN that edits or deletes it is refused.
    EXPECT="edit and delete of the old test refused"
    OLDLOG="$CW/old.log"
    L old_probe; commit_all "test: an old test that already passes"
    setup_red
    L implement
    L old_touch
    must_refuse "GREEN commit that edits the old locked test" commit commit_all "cheat: touch the old test"
    git reset -q && git checkout -q -- "$OLDFILE"
    rm -f "$OLDFILE"
    must_refuse "GREEN commit that deletes the old locked test" commit commit_all "cheat: delete the old test"
    git reset -q && git checkout -q -- "$OLDFILE"
    must_accept "the same GREEN without touching the old test" commit commit_all "feat: slugify"
    chk "the lock closed" one_lock_head_state closed
    pass ;;
  v1-13.1-caso-executado-que-falha-bloqueia)
    # Item 13, rule 1 (spec f643e28): the filter is per file; an executed case that fails blocks, even if it passed at RED.
    EXPECT="refused, lock open; accepted once fixed"
    L legacy_file; commit_all "chore: a file the tests read"
    setup_init
    L stub; L mixed_test
    must_accept "shipcraft red" cmd shipcraft red
    must_accept "RED commit" commit commit_all "test: RED with one failing and one passing case in the same file"
    git show "HEAD:$(lock_files_head)" > "$CW/lock.json"
    chk "only the slug case fails at RED" eq "$(H lock-failing "$CW/lock.json" | count_lines)" 1
    L implement; L legacy_break
    must_refuse "GREEN whose executed case (passing at RED) now fails" commit commit_all "feat: slugify (breaks the legacy file)"
    chk "the lock stays open" one_lock_head_state open
    printf 'ok\n' > legacy_state.txt
    must_accept "the same GREEN with the file intact" commit commit_all "feat: slugify"
    chk "the lock closed" one_lock_head_state closed
    pass ;;
  v1-13.1-caso-pulado-no-red-que-passa-a-falhar-bloqueia)
    # Item 13, rule 1: an executed case that fails blocks; this also holds for one skipped at RED (neither in failing_at_red nor among the passing ones) that a product flag turns on.
    EXPECT="refused, lock open"
    L flag_off; commit_all "chore: a product flag"
    setup_init
    L stub; L skipped_test
    must_accept "shipcraft red (one case fails, one is skipped)" cmd shipcraft red
    must_accept "RED commit" commit commit_all "test: RED with a skipped case in the file"
    git show "HEAD:$(lock_files_head)" > "$CW/lock.json"
    chk "only the slug case fails at RED" eq "$(H lock-failing "$CW/lock.json" | count_lines)" 1
    L implement; L flag_on
    must_refuse "GREEN whose flag un-skips a case that now fails" commit commit_all "feat: slugify (and the flag on)"
    chk "the lock stays open" one_lock_head_state open
    pass ;;
  v1-13.1-mesmo-nome-em-dois-arquivos)
    # Item 13, rule 1: the filter is by file (in Go, by package), not by case name; the same-name case in another file, which passed at RED, does not run.
    EXPECT="accepted, lock closed, same-name case never ran; ci refuses"
    OLDLOG="$CW/old.log"
    L same_name; commit_all "test: a passing test and a failing one with the same name"
    setup_init
    must_accept "shipcraft red" cmd shipcraft red
    must_accept "RED commit" commit commit_all "test: RED"
    git show "HEAD:$(lock_files_head)" > "$CW/lock.json"
    chk "only the case of the first file fails at RED" eq "$(H lock-failing "$CW/lock.json" | count_lines)" 1
    : > "$OLDLOG"
    L same_name_green
    must_accept "GREEN: fixes the first file and breaks the other through a non-test file" commit commit_all "feat: value"
    chk "the lock closed" one_lock_head_state closed
    chk "the same-name case of the other file never ran" eq "$(old_runs)" 0
    must_refuse "shipcraft ci runs everything and sees the broken case" cmd shipcraft ci --base "$BASE"
    pass ;;
  v1-13.1-mesmo-arquivo-em-duas-pastas)
    # Item 13, rule 1: a case is tied to its file by the full path, not part of the name: two test files with the same name in different folders (in Go, a package and a nested package) are not confused.
    EXPECT="accepted, lock closed, other folder's test never ran; ci refuses"
    OLDLOG="$CW/old.log"
    L two_dirs; commit_all "test: two test files with the same name in different folders"
    setup_init
    must_accept "shipcraft red" cmd shipcraft red
    must_accept "RED commit" commit commit_all "test: RED"
    git show "HEAD:$(lock_files_head)" > "$CW/lock.json"
    chk "only the case of one file fails at RED" eq "$(H lock-failing "$CW/lock.json" | count_lines)" 1
    : > "$OLDLOG"
    L two_dirs_green
    must_accept "GREEN: fixes the failing file and breaks the other one through a non-test file" commit commit_all "feat: new value"
    chk "the lock closed" one_lock_head_state closed
    chk "the test of the other folder never ran" eq "$(old_runs)" 0
    must_refuse "shipcraft ci runs everything and sees the broken case" cmd shipcraft ci --base "$BASE"
    pass ;;
  v1-13.1-jest-teste-antigo-nao-executa)
    # Item 13, rule 1, with jest 29 + jest-junit and the default rootDir: the old test (passing at RED) stays locked and does not run in the hook.
    EXPECT="accepted, lock closed, old test never ran; ci refuses"
    jest_old_case "" ;;
  v1-13.1-jest-rootdir-src-teste-antigo-nao-executa)
    # Item 13, rule 1, with jest.config.js `rootDir: "src"` and the tests in src/: excluding the old file works on the path jest sees, not the suite's.
    EXPECT="accepted, lock closed, old test never ran; ci refuses"
    jest_old_case rootdir-src ;;
  v1-13.1-junit-prefix-nao-recusa)
    # Item 13, rule 1 (spec df931ba): an error in the case -> file map costs time, never a false refusal; with `--junit-prefix` ids get a prefix and the broken old test cannot refuse GREEN.
    EXPECT="accepted, lock closed; ci refuses"
    python_map_case prefix_cfg ;;
  v1-13.1-doctest-nao-recusa)
    # Item 13, rule 1 (spec df931ba): only the cases failing at RED find the RED files (doctest does not count); with `--doctest-modules` the broken old test does not refuse GREEN.
    EXPECT="accepted, lock closed; ci refuses"
    python_map_case doctest_cfg ;;
  v1-13.1-erro-de-coleta-fora-do-red-nao-recusa)
    # Item 13, rule 1 (spec 50f33ed): an error outside the RED files (an old test that does not collect or compile) never blocks; the RED cases run anyway and the error goes to CI.
    EXPECT="accepted, lock closed; ci refuses"
    collect_case "" ;;
  v1-13.1-erro-de-coleta-com-arquivos-no-comando-nao-recusa)
    # Item 13, rule 1 (spec 50f33ed): the same, with the test files named in test_command (pytest collects what is in its arguments).
    EXPECT="accepted, lock closed; ci refuses"
    collect_case explicit_cfg ;;
  v1-13.1-verifica-fora-do-hook)
    # Item 13, rule 1 (spec dfe780d): the whole-project check (tsc, go vet) does not run in the hook; an old test that stops compiling because of the product does not refuse GREEN, and shipcraft ci catches it.
    EXPECT="accepted, lock closed; ci refuses"
    if [ "$TL" = node ]; then collect_case "" ts_old ts_break; else collect_case "" collect_old collect_break; fi ;;
  v1-13.1-init-escreve-verifica)
    # Item 13, rule 1 (spec dfe780d): init writes tsc --noEmit (Node) or go vet (Go) in `verifica`, and test_command no longer carries them.
    EXPECT="verifica holds tsc/go vet; test_command does not"
    must_accept "shipcraft init" cmd shipcraft init
    chk "verifica has the whole-project check and test_command does not" H verifica-check .shipcraft.toml "$(verifica_needle)"
    pass ;;
  v1-13.1-init-verifica-com-traco)
    # Item 13 + item 12: in a suite with a tsconfig, `verifica` carries npx with -- (npx --no -- tsc --noEmit) and the suite's command keeps only the runner.
    EXPECT="verifica has npx --no -- tsc --noEmit; command has no tsc"
    ws="$CW/ws"; mkdir -p "$ws/packages/api/src" "$ws/packages/lib/src"; cd "$ws" || exit 1
    git init -q -b main
    printf '{"name":"root","private":true,"workspaces":["packages/*"]}\n' > package.json
    printf '{"name":"api","private":true,"devDependencies":{"vitest":"5.0.4","typescript":"7.0.2"}}\n' > packages/api/package.json
    printf '{"name":"lib","private":true,"devDependencies":{"vitest":"5.0.4"}}\n' > packages/lib/package.json
    printf '{"compilerOptions":{"strict":true,"rootDir":"src","outDir":"dist"},"include":["src"]}\n' > packages/api/tsconfig.json
    printf 'import { it } from "vitest";\nit("api", () => {});\n' > packages/api/src/a.test.ts
    printf 'import { it } from "vitest";\nit("lib", () => {});\n' > packages/lib/src/c.spec.ts
    git add -A && git commit -q -m init
    must_accept "shipcraft init in a workspace with typescript" cmd shipcraft init
    chk "the api suite has verifica = npx --no -- tsc --noEmit and no command with tsc" H verifica-check .shipcraft.toml 'npx --no -- tsc --noEmit'
    chk "every npx the init wrote keeps the -- of item 12" H npx-check .shipcraft.toml .github/workflows/shipcraft.yml .git/hooks/commit-msg
    pass ;;
  v1-13.1-ci-roda-verifica)
    # Item 13, rule 1 (spec dfe780d): shipcraft ci runs `verifica` and then test_command; a type error (tsc) or vet error (go) with passing tests refuses.
    EXPECT="hook accepts; ci refuses on the whole-project check alone"
    setup_red
    L implement; L type_error
    must_accept "GREEN commit with a type/vet error and passing tests (the hook does not run verifica)" commit commit_all "feat: slugify (with a type error elsewhere)"
    chk "the lock closed" one_lock_head_state closed
    must_refuse "shipcraft ci runs verifica and refuses" cmd shipcraft ci --base "$BASE"
    pass ;;
  v1-13.1-arquivos-no-comando-teste-antigo-nao-executa)
    # Item 13, rule 1: with the test files named in test_command, the hook still runs only the RED files; the old test that collects fine (and passes) does not run.
    EXPECT="accepted, lock closed, old test never ran"
    OLDLOG="$CW/old.log"
    L old_probe; commit_all "test: an old test that already passes"
    setup_init
    L explicit_cfg; commit_all "chore: test command names the files"
    L stub; L spec_test
    must_accept "shipcraft red" cmd shipcraft red
    must_accept "RED commit" commit commit_all "test: RED"
    chk "the old test is locked but did not fail at RED" old_locked_not_failing
    : > "$OLDLOG"
    L implement
    must_accept "GREEN commit (product code only)" commit commit_all "feat: slugify"
    chk "the lock closed" one_lock_head_state closed
    chk "the hook did not execute the old test named in the command" eq "$(old_runs)" 0
    pass ;;
  v1-13.2-fecha-so-com-todos-os-do-red)
    # Item 13, rule 2: the lock closes when every case in failing_at_red passes (two files, one with case names full of metacharacters), with none left uncollected.
    EXPECT="open until both RED files pass, then closed"
    OLDLOG="$CW/old.log"
    L old_probe; commit_all "test: an old test that already passes"
    setup_init
    L stub; L spec_test; L shout_stub; L shout_odd_test
    must_accept "shipcraft red over two test files" cmd shipcraft red
    must_accept "RED commit" commit commit_all "test: RED in two files"
    chk "the old test is locked but did not fail at RED" old_locked_not_failing
    chk "the 2 slug cases and the 3 shout cases fail at RED" failing_at_least 5
    : > "$OLDLOG"
    L implement
    must_accept "GREEN of the first file only" commit commit_all "feat: slugify"
    chk "the lock stays open: the second file still fails" one_lock_head_state open
    L shout_impl
    must_accept "GREEN of the second file" commit commit_all "feat: shout"
    chk "every case that failed at RED passes: the lock closes" one_lock_head_state closed
    chk "the hook never executed the old test" eq "$(old_runs)" 0
    must_accept "shipcraft ci over the range" cmd shipcraft ci --base "$BASE"
    pass ;;

  v1-14.1-arquivo-solto-teste-com-git)
    # Item 14: the hook judges a git checkout; the test that calls git (rev-parse HEAD) passes even with a loose file in the tree.
    EXPECT="accepted, lock closed"
    setup_init
    L stub; L git_test_basic
    must_accept "shipcraft red" cmd shipcraft red
    must_accept "RED commit" commit commit_all "test: RED slugify"
    L implement; git add -A
    printf 'nota\n' > nota-solta.txt
    git status --porcelain | grep -q '^?? nota-solta' || fail "harness: the loose file should be untracked"
    must_accept "GREEN commit with a loose file in the tree" commit commit_index "feat: slugify"
    chk "the test that calls git passed in the hook: the lock closed" one_lock_head_state closed
    chk "the loose file stayed out of the commit" sh -c "! git ls-tree -r --name-only HEAD | grep -q nota-solta"
    pass ;;
  v1-14.1-primeiro-red-sem-commit)
    # Item 14: before the first commit the copy is also a git repository, with the index as content; the case that passes at RED and calls `git ls-files` keeps passing with a loose file.
    EXPECT="first RED accepted with a loose file; GREEN closes"
    [ -d .git ] && [ "$(pwd)" = "$T" ] || fail "harness: not in the case's project"
    rm -rf .git; git init -q -b main || fail "harness: git init"
    git rev-parse -q --verify HEAD >/dev/null 2>&1 && fail "harness: the repository should have no commit"
    must_accept "shipcraft init in a repository without commits" cmd shipcraft init
    L stub; L ls_test
    git add -A
    must_accept "shipcraft red" cmd shipcraft red
    git add -A
    printf 'nota\n' > nota-solta.txt
    git status --porcelain | grep -q '^?? nota-solta' || fail "harness: the loose file should be untracked"
    must_accept "the first commit (the RED) with a loose file in the tree" commit commit_index "test: RED, the first commit"
    chk "the lock entered open" one_lock_head_state open
    L implement; git add -u
    must_accept "GREEN commit with the loose file still in the tree" commit commit_index "feat: slugify"
    chk "the hook ran the file that calls git ls-files: the lock closed" one_lock_head_state closed
    chk "the loose file stayed out of the commits" sh -c "! git ls-tree -r --name-only HEAD | grep -q nota-solta"
    pass ;;
  v1-14.1-copia-com-historia-e-ci-na-arvore-suja)
    # Item 14 (edge): the copy is a real checkout (history and tracked files, not a git init of a snapshot), in the hook and in shipcraft ci with a dirty tree.
    EXPECT="accepted; ci accepted with a dirty tree"
    setup_init
    L stub; L git_test_deep
    must_accept "shipcraft red" cmd shipcraft red
    must_accept "RED commit" commit commit_all "test: RED slugify"
    L implement; git add -A
    printf 'nota\n' > nota-solta.txt
    must_accept "GREEN commit with a loose file in the tree" commit commit_index "feat: slugify"
    chk "the test saw the history and the tracked files: the lock closed" one_lock_head_state closed
    git status --porcelain | grep -q '^?? nota-solta' || fail "harness: the loose file should still be untracked"
    must_accept "shipcraft ci --base with the loose file still in the tree" cmd shipcraft ci --base "$BASE"
    pass ;;

  v1-12.1-npx-tsc-com-traco)
    # Item 12: init writes `npx --no -- tsc --noEmit`; tsc only checks and writes no build into the tree (npm 11 swallows --noEmit without the --).
    EXPECT="npx --no -- tsc --noEmit; no build output"
    ws_ts_project
    must_accept "shipcraft init in a workspace with typescript" cmd shipcraft init
    chk "each package with a tsconfig gets the literal command from the spec" eq "$(grep -c -F 'npx --no -- tsc --noEmit' .shipcraft.toml)" 2
    must_accept "commit of the init files" commit commit_all "chore: shipcraft init"
    BASE=$(head_rev)
    must_accept "shipcraft red" cmd shipcraft red
    chk "the type check wrote no build output in the tree" no_build_output
    chk "the lock holds no build output" sh -c "! cat .shipcraft/locks/*.json | grep -q 'dist/'"
    must_accept "RED commit" commit commit_all "test: RED"
    printf 'export function f(): number {\n  return 1;\n}\n' > packages/api/src/mod.ts
    printf 'export function f(): number {\n  return 1;\n}\n' > packages/web/src/mod.ts
    must_accept "GREEN commit" commit commit_all "feat: f"
    chk "the lock closed" one_lock_head_state closed
    chk "the hook wrote no build output either" no_build_output
    pass ;;
  v1-12.1-todo-npx-com-traco)
    # Item 12 (edge): every npx command init writes (tsc, vitest, jest, in any suite) has the -- before the tool's arguments.
    EXPECT="every npx has -- before the tool args"
    ws="$CW/ws"; mkdir -p "$ws/packages/api/src" "$ws/packages/web/src" "$ws/packages/lib/src"; cd "$ws" || exit 1
    git init -q -b main
    printf '{"name":"root","private":true,"workspaces":["packages/*"]}\n' > package.json
    printf '{"name":"api","private":true,"devDependencies":{"vitest":"5.0.4","typescript":"7.0.2"}}\n' > packages/api/package.json
    printf '{"name":"web","private":true,"devDependencies":{"jest":"29.0.0"}}\n' > packages/web/package.json
    printf '{"name":"lib","private":true,"devDependencies":{"vitest":"5.0.4"}}\n' > packages/lib/package.json
    printf '{"compilerOptions":{"strict":true,"rootDir":"src","outDir":"dist"},"include":["src"]}\n' > packages/api/tsconfig.json
    printf 'import { it } from "vitest";\nit("api", () => {});\n' > packages/api/src/a.test.ts
    printf 'it("web", () => {});\n' > packages/web/src/b.test.js
    printf 'import { it } from "vitest";\nit("lib", () => {});\n' > packages/lib/src/c.spec.ts
    git add -A && git commit -q -m init
    must_accept "shipcraft init in a workspace with vitest, jest and tsc" cmd shipcraft init
    chk "one [[suite]] per package" eq "$(H toml-suites .shipcraft.toml | sort)" "$(printf 'api\tpackages/api\nlib\tpackages/lib\nweb\tpackages/web')"
    chk "init wrote npx commands (the check is not empty)" grep -q -w npx .shipcraft.toml
    chk "every npx the init wrote has -- before the tool args" H npx-check .shipcraft.toml .github/workflows/shipcraft.yml .git/hooks/commit-msg
    pass ;;

  v1-9.1-init-pnpm)
    # Item 9, rule 1: init detects pnpm-workspace.yaml and writes one suite per package with tests.
    EXPECT="one suite per package with tests"
    ws="$CW/ws"; mkdir -p "$ws/packages/api/src" "$ws/packages/web/src" "$ws/packages/docs"; cd "$ws" || exit 1
    git init -q -b main
    printf 'packages:\n  - "packages/*"\n' > pnpm-workspace.yaml
    printf '{"name":"root","private":true}\n' > package.json
    printf '{"name":"api","private":true,"devDependencies":{"vitest":"5.0.4"}}\n' > packages/api/package.json
    printf '{"name":"web","private":true,"devDependencies":{"vitest":"5.0.4"}}\n' > packages/web/package.json
    printf '{"name":"docs","private":true}\n' > packages/docs/package.json
    printf 'import { it } from "vitest";\nit("api", () => {});\n' > packages/api/src/a.spec.ts
    printf 'import { it } from "vitest";\nit("web", () => {});\n' > packages/web/src/b.test.ts
    printf '# docs\n' > packages/docs/README.md
    git add -A && git commit -q -m init
    must_accept "shipcraft init in a pnpm workspace" cmd shipcraft init
    chk "one [[suite]] per package with tests, named after the folder" eq "$(H toml-suites .shipcraft.toml | sort)" "$(printf 'api\tpackages/api\nweb\tpackages/web')"
    pass ;;
  v1-9.1-init-workspaces-do-package-json)
    # Item 9, rule 1: init detects "workspaces" in package.json.
    EXPECT="one suite per package with tests"
    ws="$CW/ws"; mkdir -p "$ws/packages/api/src" "$ws/packages/web/src" "$ws/packages/docs"; cd "$ws" || exit 1
    git init -q -b main
    printf '{"name":"root","private":true,"workspaces":["packages/*"]}\n' > package.json
    printf '{"name":"api","private":true,"devDependencies":{"jest":"29.0.0"}}\n' > packages/api/package.json
    printf '{"name":"web","private":true,"devDependencies":{"vitest":"5.0.4"}}\n' > packages/web/package.json
    printf '{"name":"docs","private":true}\n' > packages/docs/package.json
    printf 'it("api", () => {});\n' > packages/api/src/a.test.js
    printf 'import { it } from "vitest";\nit("web", () => {});\n' > packages/web/src/b.spec.ts
    printf '# docs\n' > packages/docs/README.md
    git add -A && git commit -q -m init
    must_accept "shipcraft init in an npm workspace" cmd shipcraft init
    chk "one [[suite]] per package with tests, named after the folder" eq "$(H toml-suites .shipcraft.toml | sort)" "$(printf 'api\tpackages/api\nweb\tpackages/web')"
    pass ;;
  v1-9.1-init-go-work)
    # Item 9, rule 1: init detects go.work and writes one suite per module with tests.
    EXPECT="one suite per module with tests"
    ws="$CW/ws"; mkdir -p "$ws/svc/a" "$ws/svc/b" "$ws/svc/c"; cd "$ws" || exit 1
    git init -q -b main
    printf 'go 1.21\n\nuse (\n\t./svc/a\n\t./svc/b\n\t./svc/c\n)\n' > go.work
    for m in a b c; do
      printf 'module example.com/%s\n\ngo 1.21\n' "$m" > "svc/$m/go.mod"
      printf 'package %s\n\nfunc F() int { return 1 }\n' "$m" > "svc/$m/$m.go"
    done
    for m in a b; do printf 'package %s\n\nimport "testing"\n\nfunc TestF(t *testing.T) {\n\tif F() != 1 {\n\t\tt.Fatal("F")\n\t}\n}\n' "$m" > "svc/$m/${m}_test.go"; done
    git add -A && git commit -q -m init
    must_accept "shipcraft init in a go.work workspace" cmd shipcraft init
    chk "one [[suite]] per module with tests, named after the folder" eq "$(H toml-suites .shipcraft.toml | sort)" "$(printf 'a\tsvc/a\nb\tsvc/b')"
    pass ;;

  # ======================================================== core: item 1
  v1-1.1-padrao-local)
    # Review is on by default with the installed agent: init writes ci = local, review = local, roles = codex.
    EXPECT="ci=local review=local roles=codex"
    v1_start codex
    must_accept "shipcraft init" cmd shipcraft init
    chk "[execution] ci = local" eq "$(tget execution.ci)" local
    chk "[execution] review = local (a reviewer is installed)" eq "$(tget execution.review)" local
    chk "[roles] review = codex (the only installed agent)" eq "$(tget roles.review)" codex
    pass ;;
  v1-1.1-sem-revisor)
    # Without a reviewer installed review is also off and init says how to turn it on.
    EXPECT="review=off + how to turn on"
    v1_start
    must_accept "shipcraft init" cmd shipcraft init
    chk "[execution] ci = local" eq "$(tget execution.ci)" local
    chk "[execution] review = off (no reviewer installed)" eq "$(tget execution.review)" off
    chk "the init says how to turn it on (review = \"local\")" out_has 'review = "local"'
    pass ;;
  v1-1.2-revisao-github-recusada)
    # Item 1, rule 2: review = "github" is refused in three lines saying it does not exist yet, before any write.
    EXPECT="refused, nothing published"
    v1_start codex; NV=1
    CFGS='execution|review|"github"'
    pr_main; pr_feature
    shipcraft_pr
    chk "shipcraft pr failed" rc_nonzero
    msg_check || fail "refused, but $MSGERR"
    chk "the message says it does not exist yet" last3_has 'not available.*yet'
    chk "nothing was written to GitHub" eq "$(nwrites)" 0
    chk "the branch was not pushed" eq "$(osha "$BR")" ""
    pass ;;
  v1-1.2-valor-invalido)
    # Item 1, rule 2: only local, github and off are valid for ci; any other value is refused in three lines.
    EXPECT="refused, nothing published"
    v1_start codex; NV=1
    CFGS='execution|ci|"nuvem"'
    pr_main; pr_feature
    shipcraft_pr
    chk "shipcraft pr failed" rc_nonzero
    msg_check || fail "refused, but $MSGERR"
    chk "nothing was written to GitHub" eq "$(nwrites)" 0
    pass ;;
  v1-1.3-base-config-desliga)
    # Item 1, rule 3: the PR is judged by the base branch's config; a PR that turns review off and swaps the reviewer has no effect.
    EXPECT="base config wins: codex reviews"
    v1_start codex
    pr_main
    stubs_for "$CB" codex claude
    pr_feature
    tset execution review '"off"'; tset roles review '"claude"'
    must_accept "commit changing [execution] and [roles]" commit commit_all "chore: tries to turn the review off"
    shipcraft_pr
    HEAD=$(git rev-parse HEAD)
    chk "the review of the base config (codex) ran once" eq "$(rev_n codex)" 1
    chk "the reviewer the PR asked for (claude) did not run" eq "$(rev_n claude)" 0
    chk "shipcraft/review is a real verdict, not 'off'" nomatch 'off' "$(st_desc "$HEAD" shipcraft/review)"
    chk "shipcraft/review is success" eq "$(st_state "$HEAD" shipcraft/review)" success
    pass ;;
  v1-1.3-base-config-liga)
    # Item 1, rule 3: the base has review off; a PR that turns it on only counts after it reaches main.
    EXPECT="base config wins: review stays off"
    v1_start codex
    CFGS='execution|review|"off"'
    pr_main; pr_feature
    tset execution review '"local"'
    must_accept "commit turning the review on" commit commit_all "chore: tries to turn the review on"
    shipcraft_pr
    HEAD=$(git rev-parse HEAD)
    chk "no reviewer ran" eq "$(rev_n)" 0
    chk "shipcraft/review is success" eq "$(st_state "$HEAD" shipcraft/review)" success
    chk "shipcraft/review says it is off" match 'off in \.shipcraft\.toml' "$(st_desc "$HEAD" shipcraft/review)"
    pass ;;

  # ======================================================== core: item 2
  v1-2.3-tela-do-init)
    # Item 2: init asks nothing about review; it names the reviewer, says the diff goes to its provider and how to turn review off.
    EXPECT="no question, review by the first agent, how to turn off"
    v1_start codex claude
    run_cmd_stdin /dev/null shipcraft init
    chk "shipcraft init accepted" rc_zero
    chk "init did not ask the reviewer" out_hasnt '(who reviews|Which reviewer)'
    chk "init names the reviewer" out_has 'review by codex'
    chk "init says how to turn it off" out_has 'review = "off"'
    chk "init says the diff goes to the provider" out_has 'provider'
    chk "[execution] review = local" eq "$(tget execution.review)" local
    pass ;;
  v1-2.3-padrao-primeiro-instalado)
    # Item 2: [roles] review names the first agent installed, and review is on.
    EXPECT="roles=gemini"
    v1_start gemini
    run_cmd_stdin /dev/null shipcraft init
    chk "shipcraft init accepted" rc_zero
    chk "[roles] review = gemini (the only installed agent)" eq "$(tget roles.review)" gemini
    chk "[execution] review = local" eq "$(tget execution.review)" local
    pass ;;

  v1-2.5-agents-novo)
    # init creates AGENTS.md with the shipcraft block when the project has none.
    EXPECT="AGENTS.md created with the block"
    v1_start
    must_accept "shipcraft init" cmd shipcraft init
    chk "AGENTS.md has the block" grep -q -F '<!-- shipcraft -->' AGENTS.md
    chk "the block says to run shipcraft red" grep -q -F 'shipcraft red' AGENTS.md
    chk "init says to commit AGENTS.md" out_has 'ready\. Commit .*AGENTS\.md'
    pass ;;
  v1-2.5-agents-acrescenta)
    # An existing AGENTS.md keeps its text; the block is appended after it.
    EXPECT="block appended, text kept"
    v1_start
    printf '# House rules\nKEEP-MARKER-8a1\n' > AGENTS.md
    must_accept "shipcraft init" cmd shipcraft init
    chk "the old text is still first" eq "$(head -n 2 AGENTS.md | tail -n 1)" KEEP-MARKER-8a1
    chk "the block was appended" grep -q -F '<!-- shipcraft -->' AGENTS.md
    pass ;;
  v1-2.5-agents-uma-vez)
    # A second init (new clone, config removed) does not add the block twice.
    EXPECT="one block after two inits"
    v1_start
    must_accept "first init" cmd shipcraft init
    rm -f .shipcraft.toml
    must_accept "second init" cmd shipcraft init
    chk "exactly one block" eq "$(grep -c -F '<!-- shipcraft -->' AGENTS.md)" 1
    chk "init says it kept the block" out_has 'already has the shipcraft block'
    pass ;;
  v1-2.5-agents-link)
    # A symlinked AGENTS.md is never written through.
    EXPECT="symlink untouched"
    v1_start
    printf 'outside\n' > "$CW/outside.md"
    ln -s "$CW/outside.md" AGENTS.md
    must_accept "shipcraft init" cmd shipcraft init
    chk "the link target is unchanged" eq "$(cat "$CW/outside.md")" outside
    chk "AGENTS.md is still a link" test -L AGENTS.md
    pass ;;

  # ======================================================== core: item 3
  v1-3.1-push-e-pr)
    # Item 3, rule 1: shipcraft pr pushes the branch and opens the PR (given title and body), or updates the existing one.
    EXPECT="pushed, 1 PR, updated on rerun"
    v1_start codex
    CFGS='execution|review|"off"'
    pr_main; pr_feature
    shipcraft_pr
    chk "shipcraft pr succeeded" rc_zero
    chk "the branch is on origin at HEAD" eq "$(osha "$BR")" "$(git rev-parse HEAD)"
    chk "exactly one PR was created" eq "$(nwrites pr-create)" 1
    chk "the PR carries the title" eq "$(H text-has "$ST" pr-create 'Titulo-PR-6d1')" OK
    chk "the PR carries the body" eq "$(H text-has "$ST" pr-create 'PR-BODY-MARKER-91b')" OK
    printf '# mais\n' >> shoutmod.py
    must_accept "second commit" commit commit_all "feat: more"
    shipcraft_pr
    chk "second shipcraft pr succeeded" rc_zero
    chk "no second PR was created" eq "$(nwrites pr-create)" 1
    chk "the new commit was pushed" eq "$(osha "$BR")" "$(git rev-parse HEAD)"
    pass ;;
  v1-3.2-ci-local-publica-status)
    # Item 3, rule 2: with ci = local, shipcraft pr runs CI on this machine and publishes shipcraft/ci on the HEAD commit.
    EXPECT="suite ran once, shipcraft/ci success on HEAD"
    v1_start codex
    CFGS='execution|review|"off"'
    pr_main; pr_feature
    shipcraft_pr
    HEAD=$(git rev-parse HEAD)
    chk "shipcraft pr succeeded" rc_zero
    chk "the suite ran locally, once" eq "$(probe_runs)" 1
    chk "shipcraft/ci is success on the HEAD sha" eq "$(st_state "$HEAD" shipcraft/ci)" success
    pass ;;
  v1-3.2-ci-falha-sem-revisao)
    # Item 3, rules 2 and 3: red CI publishes shipcraft/ci without success and the review does not run.
    EXPECT="shipcraft/ci not success, no review"
    v1_start codex
    FAILING=1; pr_main; pr_feature
    shipcraft_pr
    HEAD=$(git rev-parse HEAD)
    chk "shipcraft/ci is failure or error" match '^(failure|error)$' "$(st_state "$HEAD" shipcraft/ci)"
    chk "the reviewer did not run" eq "$(rev_n)" 0
    chk "shipcraft/review is not success" ne "$(st_state "$HEAD" shipcraft/review)" success
    pass ;;
  v1-3.3-revisao-local-status-e-comentario)
    # Item 3, rule 3 (and item 1, table): with green CI the local review runs, publishes shipcraft/review and the comment; the layer shows as "on this machine".
    EXPECT="review ran; status + comment; 'on this machine'"
    v1_start codex
    pr_main; pr_feature
    shipcraft_pr
    HEAD=$(git rev-parse HEAD)
    chk "shipcraft pr succeeded" rc_zero
    chk "shipcraft/ci is success" eq "$(st_state "$HEAD" shipcraft/ci)" success
    chk "the reviewer ran once" eq "$(rev_n)" 1
    chk "shipcraft/review is success on the HEAD sha" eq "$(st_state "$HEAD" shipcraft/review)" success
    chk "the review was posted as a comment" eq "$(H text-has "$ST" comment 'REVIEW-BODY-MARKER-3a9')" OK
    chk "a local layer shows as 'on this machine' (output, comment, PR text or status)" shown_local
    pass ;;
  v1-3.4-ci-github-nada-local)
    # Item 3, rule 4: with ci = github nothing runs locally and shipcraft does not publish shipcraft/ci (the workflow does).
    EXPECT="no local suite, no shipcraft/ci"
    v1_start codex
    CFGS='execution|ci|"github"
execution|review|"off"'
    pr_main; pr_feature
    shipcraft_pr
    chk "shipcraft pr succeeded" rc_zero
    chk "the suite did not run locally" eq "$(probe_runs)" 0
    chk "shipcraft published no shipcraft/ci status" eq "$(H st-ctx-count "$ST" shipcraft/ci)" 0
    pass ;;
  v1-3.5-desligado-publica-success)
    # Item 3, rule 5: a layer that is off publishes the status as success with the description "off in .shipcraft.toml".
    EXPECT="both statuses success + 'off in .shipcraft.toml'"
    v1_start codex
    CFGS='execution|ci|"off"
execution|review|"off"'
    pr_main; pr_feature
    shipcraft_pr
    HEAD=$(git rev-parse HEAD)
    chk "shipcraft pr succeeded" rc_zero
    for c in shipcraft/ci shipcraft/review; do
      chk "$c is success" eq "$(st_state "$HEAD" $c)" success
      chk "$c says 'off in .shipcraft.toml'" match 'off in \.shipcraft\.toml' "$(st_desc "$HEAD" $c)"
    done
    chk "the suite did not run" eq "$(probe_runs)" 0
    chk "no reviewer ran" eq "$(rev_n)" 0
    pass ;;
  v1-3.5-desligado-so-a-revisao)
    # Item 3, rule 5: only review off; CI really runs and its description does not say "off".
    EXPECT="real ci, review off"
    v1_start codex
    CFGS='execution|review|"off"'
    pr_main; pr_feature
    shipcraft_pr
    HEAD=$(git rev-parse HEAD)
    chk "the suite ran" eq "$(probe_runs)" 1
    chk "shipcraft/ci is success and does not say 'off'" nomatch 'off' "$(st_desc "$HEAD" shipcraft/ci)"
    chk "shipcraft/review says 'off in .shipcraft.toml'" match 'off in \.shipcraft\.toml' "$(st_desc "$HEAD" shipcraft/review)"
    chk "shipcraft/review is success" eq "$(st_state "$HEAD" shipcraft/review)" success
    pass ;;
  v1-3.6-resumo-de-medicao-no-pr)
    # Item 3, rule 6 (and item 10, rule 2): shipcraft pr posts the branch summary to the PR: layers, secs and tokens.
    EXPECT="summary posted in the PR"
    v1_start codex
    pr_main; pr_feature
    shipcraft_pr
    chk "shipcraft pr succeeded" rc_zero
    chk "a text posted to the PR covers hook, ci, review and tokens" eq "$(H has-summary "$ST")" OK
    pass ;;
  v1-3.7-revisao-local-sem-publicar)
    # Item 3, rule 7: shipcraft review reviews the local HEAD, shows the verdict and publishes nothing (no push either).
    EXPECT="verdict shown, nothing published"
    v1_start codex
    pr_main; pr_feature
    git rev-parse HEAD > "$ST/sha"
    run_cmd TMO 120 shipcraft review
    chk "approved: shipcraft review exits 0" rc_zero
    chk "the verdict is shown" out_has 'APPROVE'
    chk "the reviewer ran once" eq "$(rev_n)" 1
    chk "nothing was published to GitHub" eq "$(nwrites)" 0
    chk "nothing was pushed" eq "$(osha "$BR")" ""
    rev_cfg changes
    run_cmd TMO 120 shipcraft review
    chk "changes requested: shipcraft review exits non-zero" rc_nonzero
    chk "the verdict is shown" out_has 'CHANGES REQUESTED'
    chk "the finding is shown to the agent" out_has 'REVIEW-FINDING-MARKER-77c'
    chk "still nothing published" eq "$(nwrites)" 0
    pass ;;
  v1-3.7-revisao-pr-copia-isolada)
    # Item 3, rule 7: shipcraft review --pr N reviews a PR not born from shipcraft pr in an isolated copy and publishes the status.
    EXPECT="isolated copy, shipcraft/review on the PR head"
    v1_start codex
    pr_main; pr_feature
    pr_outside "$BR"
    git checkout -q main; MAIN0=$(git rev-parse HEAD)
    echo "$HEADSHA" > "$ST/sha"
    run_cmd TMO 180 shipcraft review --pr "$PRN"
    chk "shipcraft review --pr succeeded" rc_zero
    chk "the reviewer ran once" eq "$(rev_n)" 1
    chk "the reviewer did not run in the user's checkout" ne "$(H rev-field "$ST" 0 cwd)" "$(pwd -P)"
    chk "shipcraft/review is success on the PR head sha" eq "$(st_state "$HEADSHA" shipcraft/review)" success
    chk "the user's checkout is untouched (branch)" eq "$(git rev-parse --abbrev-ref HEAD)" main
    chk "the user's checkout is untouched (HEAD)" eq "$(git rev-parse HEAD)" "$MAIN0"
    chk "the user's checkout is untouched (tree)" eq "$(git status --porcelain)" ""
    chk "the PR body reached the reviewer" match 'PR-BODY-MARKER-91b' "$(H rev-brief "$ST")"
    pass ;;
  v1-3.7-revisao-pr-fork-recusado)
    # Item 3, rule 7: a fork PR is refused in v1, in three lines, without reviewing or publishing.
    EXPECT="refused, nothing reviewed or published"
    v1_start codex
    pr_main; pr_feature
    pr_outside "$BR"
    H pr-fork "$ST" "$PRN" mallory "$HEADSHA"
    git checkout -q main
    echo "$HEADSHA" > "$ST/sha"
    run_cmd TMO 120 shipcraft review --pr "$PRN"
    chk "shipcraft review --pr failed" rc_nonzero
    msg_check || fail "refused, but $MSGERR"
    chk "the reviewer did not run" eq "$(rev_n)" 0
    chk "no status or comment was published" eq "$(nwrites)" 0
    pass ;;

  # ======================================================== core: item 4
  v1-4.1-brief-completa)
    # Item 4, rule 1: the brief carries the project spec ([review] spec), the PR body, the diff and the battery.
    EXPECT="brief has spec, body, diff, battery"
    v1_start codex
    CFGS='review|spec|"docs/spec-produto.md"'
    pr_main; pr_feature
    shipcraft_pr
    chk "the reviewer ran once" eq "$(rev_n)" 1
    BRIEF=$(H rev-brief "$ST")
    chk "the brief carries the project spec" match 'SPEC-MARKER-5e1' "$BRIEF"
    chk "the brief carries the PR body" match 'PR-BODY-MARKER-91b' "$BRIEF"
    chk "the brief carries the diff" match 'diff-marker-4f9a' "$BRIEF"
    chk "the brief carries the battery (a test the PR did not touch)" match 'test_bateria_marker_2c7' "$BRIEF"
    pass ;;
  v1-4.2-veredito-changes-requested)
    # Item 4, rule 2: "CHANGES REQUESTED at <sha>" becomes shipcraft/review failure, with the reviewer's comment.
    EXPECT="shipcraft/review failure + comment"
    v1_start codex
    pr_main; pr_feature
    rev_cfg changes
    shipcraft_pr
    HEAD=$(git rev-parse HEAD)
    chk "the reviewer ran once" eq "$(rev_n)" 1
    chk "shipcraft/review is failure" eq "$(st_state "$HEAD" shipcraft/review)" failure
    chk "the findings were posted as a comment" eq "$(H text-has "$ST" comment 'REVIEW-FINDING-MARKER-77c')" OK
    pass ;;
  v1-4.2-veredito-fora-da-primeira-linha)
    # Item 4, rules 2 and 3: the first line must be the verdict; anything else is an error, never an approval.
    EXPECT="shipcraft/review error"
    v1_start codex
    pr_main; pr_feature
    rev_cfg preamble
    shipcraft_pr
    review_failed_closed ;;
  v1-4.2-veredito-com-linha-em-branco-antes)
    # Item 4, rules 2 and 3: the first line of output IS the verdict; a blank line before it is "anything else": error.
    EXPECT="shipcraft/review error"
    v1_start codex
    pr_main; pr_feature
    rev_cfg blankline
    shipcraft_pr
    review_failed_closed ;;
  v1-4.2-veredito-com-texto-depois-da-sha)
    # Item 4, rules 2 and 3: the verdict is exactly "APPROVE at <sha>"; text after the sha is "anything else": error.
    EXPECT="shipcraft/review error"
    v1_start codex
    pr_main; pr_feature
    rev_cfg suffix
    shipcraft_pr
    review_failed_closed ;;
  v1-1.3-comando-do-runner-vem-da-base)
    # Item 1, rule 3: the PR is judged by the base branch's config for the suite command too: a PR that filters out the failing test does not get a green shipcraft/ci.
    EXPECT="shipcraft/ci not success; base command used"
    v1_start codex
    CFGS='execution|review|"off"'
    FAILING=1; pr_main; pr_feature
    perl -pi -e 's/-m pytest/-m pytest --ignore=tests\/test_failing.py/' .shipcraft.toml
    git diff --quiet -- .shipcraft.toml && fail "harness: the test command was not changed"
    must_accept "commit changing the runner command to skip the failing test" commit commit_all "chore: tries to skip the failing test"
    shipcraft_pr
    HEAD=$(git rev-parse HEAD)
    chk "shipcraft pr did its job: the branch is on origin and the PR exists" eq "$(osha "$BR")-$(nwrites pr-create)" "$HEAD-1"
    chk "shipcraft/ci is failure or error: the base command ran the failing test" match '^(failure|error)$' "$(st_state "$HEAD" shipcraft/ci)"
    pass ;;
  v1-1.3-config-da-ponta-do-branch-base)
    # Item 1, rule 3: the base branch's config is the one at its TIP (origin/<base>), not at the merge-base: if main now runs every test, a branch that did not rebase does not get a green shipcraft/ci.
    EXPECT="shipcraft/ci not success; tip of base used"
    v1_start codex
    CFGS='execution|review|"off"
-|test_command|"python3 -m pytest -p no:cacheprovider --junitxml={junit} tests/test_smoke.py"'
    FAILING=1; pr_main; pr_feature
    git checkout -q main
    H toml-set .shipcraft.toml "" test_command '"python3 -m pytest -p no:cacheprovider --junitxml={junit}"' || fail "harness: toml-set"
    must_accept "main now runs every test" commit commit_all "chore: main runs all tests"
    git push -q origin main >> "$LOG" 2>&1 || fail "harness: push main"
    git checkout -q "$BR"
    shipcraft_pr
    HEAD=$(git rev-parse HEAD)
    chk "shipcraft pr did its job: the branch is on origin and the PR exists" eq "$(osha "$BR")-$(nwrites pr-create)" "$HEAD-1"
    chk "shipcraft/ci is failure or error: main's current command ran the failing test" match '^(failure|error)$' "$(st_state "$HEAD" shipcraft/ci)"
    pass ;;
  v1-4.3-recusa-do-revisor)
    # Item 4, rule 3: a reviewer that refuses (refusal text, no verdict) becomes error, a single attempt.
    EXPECT="shipcraft/review error, no retry"
    v1_start codex
    pr_main; pr_feature
    rev_cfg refuse
    shipcraft_pr
    review_failed_closed ;;
  v1-4.3-saida-nao-zero)
    # Item 4, rule 3: quota exceeded (non-zero exit) becomes error, a single attempt.
    EXPECT="shipcraft/review error, no retry"
    v1_start codex
    pr_main; pr_feature
    rev_cfg quota
    shipcraft_pr
    review_failed_closed ;;
  v1-4.3-tempo-esgotado)
    # Item 4, rule 3: a reviewer that exceeds [review] timeout (seconds) is cut off and becomes error.
    EXPECT="shipcraft/review error after tempo_max"
    v1_start codex
    CFGS='review|timeout|2'
    pr_main; pr_feature
    rev_cfg hang hang=40
    T0=$(date +%s)
    shipcraft_pr
    ELAPSED=$(( $(date +%s) - T0 ))
    chk "shipcraft pr gave up long before the reviewer would have answered (took ${ELAPSED}s)" test "$ELAPSED" -lt 30
    review_failed_closed ;;
  v1-4.3-pending-velho-refeito)
    # Item 4, rule 3: a pending status older than timeout is redone on the next shipcraft pr.
    EXPECT="stale pending redone"
    v1_start codex
    CFGS='review|timeout|60'
    pr_main; pr_feature
    HEAD=$(git rev-parse HEAD)
    H seed-status "$ST" "$HEAD" shipcraft/review pending "revisao em andamento" 3600
    shipcraft_pr
    chk "the stale pending was redone: the reviewer ran" eq "$(rev_n)" 1
    chk "shipcraft/review is now success" eq "$(st_state "$HEAD" shipcraft/review)" success
    pass ;;
  v1-4.4-patch-id-reaproveita)
    # Items 4.4 and 35.3: a rebase with the same file versions reuses the verdict; different versions need a new review.
    EXPECT="verdict reused after rebase; redone after a change"
    v1_start codex
    pr_main; pr_feature
    shipcraft_pr
    SHA1=$(git rev-parse HEAD)
    chk "first review ran" eq "$(rev_n)" 1
    chk "review records diff_sha256 of file versions" i35_record "$(i35_key)"
    git checkout -q main && printf 'upstream\n' > UPSTREAM.md && commit_all "chore: upstream moves" && git push -q origin main >> "$LOG" 2>&1 || fail "harness: advance main"
    git checkout -q "$BR" && git rebase -q main >> "$LOG" 2>&1 || fail "harness: rebase"
    SHA2=$(git rev-parse HEAD)
    chk "the rebase changed the sha" ne "$SHA1" "$SHA2"
    chk "the rebase kept file versions" "$PY" -c 'import subprocess,sys; raw=lambda b,h: subprocess.check_output(["git","diff","--raw","-z","--no-abbrev","--no-renames","--ignore-submodules=none",b,h]); assert raw(sys.argv[1],sys.argv[2]) == raw(sys.argv[3],sys.argv[4])' "$BASE" "$SHA1" main "$SHA2"
    shipcraft_pr
    chk "shipcraft pr after the rebase succeeded" rc_zero
    chk "no new review for the same file versions" eq "$(rev_n)" 1
    chk "shipcraft/review is success on the rebased sha" eq "$(st_state "$SHA2" shipcraft/review)" success
    chk "reuse describes the same file versions" match 'same file versions' "$(st_desc "$SHA2" shipcraft/review)"
    printf '# muda o diff\n' >> shoutmod.py
    must_accept "commit changing the patch" commit commit_all "feat: changes the patch"
    shipcraft_pr
    chk "a changed patch is reviewed again" eq "$(rev_n)" 2
    pass ;;

  # ======================================================== core: item 5
  v1-5.1-merge-com-os-dois)
    # Item 5, rule 1: shipcraft merge merges with shipcraft/ci and shipcraft/review as success on the PR's HEAD.
    EXPECT="merged"
    merge_setup
    seed_ok "$HEADSHA" shipcraft/ci; seed_ok "$HEADSHA" shipcraft/review
    run_cmd TMO 120 shipcraft merge "$PRN"
    chk "shipcraft merge succeeded" rc_zero
    chk "the merge was asked of GitHub" test "$(nwrites merge)" -ge 1
    chk "the PR is merged" eq "$(H pr-field "$ST" "$PRN" state)" MERGED
    pass ;;
  v1-5.1-merge-sem-revisao-recusa)
    # Item 5, rule 1: without shipcraft/review as success the merge is refused in three lines.
    EXPECT="refused, not merged"
    merge_setup
    seed_ok "$HEADSHA" shipcraft/ci
    merge_must_refuse ;;
  v1-5.1-merge-revisao-failure-recusa)
    # Item 5, rule 1: shipcraft/review as failure (CHANGES REQUESTED) also refuses the merge.
    EXPECT="refused, not merged"
    merge_setup
    seed_ok "$HEADSHA" shipcraft/ci
    H seed-status "$ST" "$HEADSHA" shipcraft/review failure "CHANGES REQUESTED" 0
    merge_must_refuse ;;
  v1-5.1-merge-sem-ci-recusa)
    # Item 5, rule 1: without shipcraft/ci as success the merge is refused.
    EXPECT="refused, not merged"
    merge_setup
    seed_ok "$HEADSHA" shipcraft/review
    merge_must_refuse ;;
  v1-5.1-merge-status-de-outro-commit)
    # Item 5, rule 1: both successes must be on the PR's HEAD; success on an old commit does not count.
    EXPECT="refused, not merged"
    merge_setup
    OLD=$(git rev-parse "$BR~1")
    seed_ok "$OLD" shipcraft/ci; seed_ok "$OLD" shipcraft/review
    merge_must_refuse ;;
  v1-5.1-merge-camada-desligada-nao-exige)
    # Item 1 (table) and item 5, rule 1: a layer that is off in the base config is not required by the gate.
    EXPECT="merged without shipcraft/review"
    CFGS='execution|review|"off"'
    merge_setup
    seed_ok "$HEADSHA" shipcraft/ci
    run_cmd TMO 120 shipcraft merge "$PRN"
    chk "shipcraft merge succeeded without shipcraft/review" rc_zero
    chk "the PR is merged" eq "$(H pr-field "$ST" "$PRN" state)" MERGED
    pass ;;
  v1-5.2-sem-revisao-com-motivo)
    # Item 5, rule 2: --no-review "<reason>" merges without review and the reason goes to the PR and to the measurement.
    EXPECT="merged; reason in the PR and in the jsonl"
    merge_setup
    seed_ok "$HEADSHA" shipcraft/ci
    run_cmd TMO 120 shipcraft merge "$PRN" --no-review "motivo-sem-revisao-4b2"
    chk "shipcraft merge --no-review succeeded" rc_zero
    chk "the PR is merged" eq "$(H pr-field "$ST" "$PRN" state)" MERGED
    chk "the reason went to the PR" eq "$(H text-has "$ST" comment,pr-edit,merge 'motivo-sem-revisao-4b2')" OK
    chk "the reason went to the measurement (.git/shipcraft/runs.jsonl)" grep -q 'motivo-sem-revisao-4b2' .git/shipcraft/runs.jsonl
    pass ;;
  v1-5.2-sem-revisao-nao-vale-para-o-ci)
    # Item 5, rule 2: CI has no --no-review way out.
    EXPECT="refused, not merged"
    merge_setup
    seed_ok "$HEADSHA" shipcraft/review
    run_cmd TMO 120 shipcraft merge "$PRN" --no-review "motivo-qualquer"
    chk "shipcraft merge failed" rc_nonzero
    msg_check || fail "refused, but $MSGERR"
    chk "no merge was asked of GitHub" eq "$(nwrites merge)" 0
    pass ;;
  v1-5.3-init-github-marca-obrigatorios)
    # Item 5, rule 3: where GitHub protects branches, init --github marks shipcraft/ci and shipcraft/review as required.
    EXPECT="required checks written"
    v1_start codex
    remote_setup
    echo none > "$ST/protection"
    must_accept "shipcraft init --github" cmd shipcraft init --github
    chk "branch protection was written with shipcraft/ci and shipcraft/review" eq "$(H protect-ok "$ST")" OK
    pass ;;
  v1-5.3-init-github-plano-gratis)
    # Item 5, rules 3 and 4: on the free plan (403) init --github ends fine and nothing is marked required.
    EXPECT="init ok, nothing marked required"
    v1_start codex
    remote_setup
    echo 403 > "$ST/protection"
    must_accept "shipcraft init --github on a repo without branch protection" cmd shipcraft init --github
    chk "no protection was set" eq "$(cat "$ST/protection")" 403
    pass ;;
  v1-5.4-status-nivel-de-protecao)
    # Item 5, rule 4: shipcraft status states the real protection level in one line (no protection: the gate is shipcraft merge).
    EXPECT="one honest line per level"
    v1_start codex
    pr_main
    echo 403 > "$ST/protection"
    must_accept "shipcraft status (no branch protection)" cmd shipcraft status
    chk "exactly one line talks about branch protection" eq "$(clean_out | grep -c -i 'prote[cç]' || true)" 1
    chk "it says there is no protection" clean_out_hasi 'no branch protection'
    chk "it says the gate is shipcraft merge" clean_out_has 'shipcraft merge'
    echo full > "$ST/protection"; echo "shipcraft/ci shipcraft/review" > "$ST/protection.contexts"
    must_accept "shipcraft status (protected)" cmd shipcraft status
    chk "exactly one line talks about branch protection" eq "$(clean_out | grep -c -i 'prote[cç]' || true)" 1
    chk "it no longer says there is no protection" clean_out_hasnt 'no branch protection'
    pass ;;
  v1-5.5-ci-na-main-avisa-merges)
    # Item 5, rule 5: shipcraft ci on main warns (without refusing) about merges that skipped the gate; each one is an escape in the measurement.
    EXPECT="warns about PR 2 only; escape row"
    v1_start codex
    pr_main
    for k in 1 2 3; do
      git checkout -q -b "br-$k" main
      printf 'mod %s\n' "$k" > "mod$k.txt"; commit_all "feat: mod $k"
      git push -q origin "br-$k" >> "$LOG" 2>&1
      gh_quiet pr create --title "PR $k" --body "corpo $k" --head "br-$k" --base main >> "$LOG" 2>&1 || fail "harness: pr create $k"
    done
    git checkout -q main
    S1=$(git rev-parse br-1); S3=$(git rev-parse br-3)
    seed_ok "$S1" shipcraft/ci; seed_ok "$S1" shipcraft/review      # PR 1: the right path
    seed_ok "$S3" shipcraft/ci                                 # PR 3: no review, with --no-review
    run_cmd TMO 120 shipcraft merge 1
    chk "PR 1 merged through shipcraft merge" rc_zero
    gh_quiet pr merge 2 --merge >> "$LOG" 2>&1 || fail "harness: merge of PR 2 outside the gate"
    run_cmd TMO 120 shipcraft merge 3 --no-review "motivo-5.5"
    chk "PR 3 merged with --no-review" rc_zero
    git pull -q --no-rebase origin main >> "$LOG" 2>&1 || fail "harness: pull main"
    M2=$(gh_quiet api repos/o/r/pulls/2 -q .merge_commit_sha)
    run_cmd TMO 240 shipcraft ci --base "$BASE"
    chk "shipcraft ci warns, it does not refuse (rc 0)" rc_zero
    chk "the warning names the merge that skipped the gate (PR 2)" out_has "(#2([^0-9]|$)|$(printf '%s' "$M2" | cut -c1-7))"
    chk "the warning does not name PR 1 (it had both statuses)" sh -c "! grep -E -q '#1([^0-9]|\$)' '$OUT'"
    chk "the warning does not name PR 3 (merged with --no-review)" sh -c "! grep -E -q '#3([^0-9]|\$)' '$OUT'"
    chk "the skipped merge is an escape in the measurement" eq "$(H escape-rows .git/shipcraft/runs.jsonl)" "$M2"
    pass ;;

  # ======================================================== core: item 7
  v1-7.1-fila-um-slot)
    # Item 7, rule 1: with slots = 1 (default), CI and review of different projects never run at the same time.
    EXPECT="max 1 execution at a time"
    queue_projects 2 "" 2.5 2
    queue_run_all
    for n in alfa beta; do chk "$n: shipcraft pr succeeded" eq "$(cat "$CW/rc-$n")" 0; done
    chk "2 CI + 2 reviews ran, never two at a time" timeline_is 1 4
    pass ;;
  v1-7.1-fila-dois-slots)
    # Item 7, rule 1: [machine] slots = 2 allows two runs at once, never three.
    EXPECT="max 2 at a time"
    queue_projects 3 'machine|slots|2' 2.5 2
    mkdir -p "$HOME/.config/shipcraft"; printf '[machine]\nslots = 2\n' > "$HOME/.config/shipcraft/config.toml"
    queue_run_all
    for n in alfa beta gama; do chk "$n: shipcraft pr succeeded" eq "$(cat "$CW/rc-$n")" 0; done
    chk "3 CI + 3 reviews ran, two at a time at most, and two at once did happen" timeline_is 2 6
    pass ;;
  v1-7.2-fila-posicao)
    # Item 7, rule 2: whoever waits in the queue sees their position and what is running.
    EXPECT="waiting run shows queue position + the running one"
    queue_projects 2 "" 6 1
    ( queue_one alfa ) & PIDA=$!
    queue_wait_start alfa ci
    queue_one beta
    wait $PIDA
    chk "beta: shipcraft pr succeeded" eq "$(cat "$CW/rc-beta")" 0
    OUT="$CW/out-beta"
    chk "the waiting run printed a queue line with a position" queue_line_with_number
    chk "it says what is running (the other project)" clean_out_has 'alfa'
    pass ;;
  v1-7.2-fila-tempo-libera)
    # Item 7, rule 2: a run that exceeds the maximum secs frees the slot for whoever waits.
    EXPECT="the next run starts after the timeout"
    queue_projects 2 'review|timeout|3' 0 0
    use_proj "$CW/proj/alfa" "$CW/stubs/alfa"; rev_cfg hang hang=40 timeline="$TLINE" name=alfa
    ( queue_one alfa ) & PIDA=$!
    queue_wait_start alfa ci
    sleep 1
    queue_one beta
    wait $PIDA
    chk "beta: shipcraft pr succeeded" eq "$(cat "$CW/rc-beta")" 0
    TA=$(H tl-time "$TLINE" alfa revisao start); TB=$(H tl-time "$TLINE" beta revisao start)
    chk "both reviews started" nonempty "${TA}${TB}"
    chk "beta's review started well before alfa's reviewer would have finished (hang 40s)" "$PY" -c "import sys; sys.exit(0 if float('$TB') - float('$TA') < 25 else 1)"
    use_proj "$CW/proj/alfa" "$CW/stubs/alfa"; AH=$(git rev-parse HEAD)
    chk "alfa's review ended as error" eq "$(st_state "$AH" shipcraft/review)" error
    use_proj "$CW/proj/beta" "$CW/stubs/beta"; BH=$(git rev-parse HEAD)
    chk "beta's review is success" eq "$(st_state "$BH" shipcraft/review)" success
    pass ;;
  v1-7.2-ci-tempo-esgotado-libera)
    # Item 7, rule 2 (spec 323bfc3): local CI that exceeds [execution] ci_timeout (seconds) is stopped, becomes shipcraft/ci error and frees the slot.
    EXPECT="CI cut at tempo_max_ci; next run proceeds"
    PSL_ALFA=40
    queue_projects 2 'execution|ci_timeout|3' 0 0
    ( queue_one alfa ) & PIDA=$!
    queue_wait_start alfa ci
    sleep 1
    queue_one beta
    wait $PIDA
    chk "beta: shipcraft pr succeeded" eq "$(cat "$CW/rc-beta")" 0
    TA=$(H tl-time "$TLINE" alfa ci start); TB=$(H tl-time "$TLINE" beta ci start)
    chk "both CIs started" nonempty "${TA}${TB}"
    chk "beta's CI started well before alfa's suite would have finished (sleeps 40s)" "$PY" -c "import sys; sys.exit(0 if float('$TB') - float('$TA') < 25 else 1)"
    use_proj "$CW/proj/alfa" "$CW/stubs/alfa"; AH=$(git rev-parse HEAD)
    chk "alfa's shipcraft/ci ended as error" eq "$(st_state "$AH" shipcraft/ci)" error
    chk "the error carries a reason" nonempty "$(st_desc "$AH" shipcraft/ci)"
    chk "alfa's review never ran (the CI did not pass)" eq "$(rev_n)" 0
    use_proj "$CW/proj/beta" "$CW/stubs/beta"; BH=$(git rev-parse HEAD)
    chk "beta's shipcraft/ci is success" eq "$(st_state "$BH" shipcraft/ci)" success
    pass ;;
  v1-3.4-ci-github-espera-success-e-revisa)
    # Item 3, rule 4 (spec 323bfc3): with ci = github and review = local, shipcraft pr waits for GitHub's shipcraft/ci on HEAD and, on success, runs the review.
    EXPECT="waits for shipcraft/ci success, then reviews"
    v1_start codex
    CFGS='execution|ci|"github"
execution|ci_timeout|60'
    pr_main; pr_feature
    HEAD=$(git rev-parse HEAD)
    ( "$PY" -c "import time; time.sleep(4)"; H seed-status "$ST" "$HEAD" shipcraft/ci success "workflow" 0 ) & PIDS=$!
    shipcraft_pr
    wait $PIDS
    chk "shipcraft pr succeeded" rc_zero
    chk "the suite did not run locally" eq "$(probe_runs)" 0
    chk "the review ran once, after the status arrived" eq "$(rev_n)" 1
    chk "shipcraft/review is success on HEAD" eq "$(st_state "$HEAD" shipcraft/review)" success
    chk "shipcraft did not publish shipcraft/ci itself (only the workflow's)" eq "$(H st-count "$ST" "$HEAD" shipcraft/ci)" 1
    pass ;;
  v1-3.4-ci-github-failure-nao-revisa)
    # Item 3, rule 4 (spec 323bfc3): if GitHub's shipcraft/ci on HEAD is failure, the local review does not run.
    EXPECT="no review when GitHub's shipcraft/ci is failure"
    v1_start codex
    CFGS='execution|ci|"github"
execution|ci_timeout|60'
    pr_main; pr_feature
    HEAD=$(git rev-parse HEAD)
    H seed-status "$ST" "$HEAD" shipcraft/ci failure "workflow" 0
    shipcraft_pr
    chk "shipcraft pr did its job: the branch is on origin and the PR exists" eq "$(osha "$BR")-$(nwrites pr-create)" "$(git rev-parse HEAD)-1"
    chk "the suite did not run locally" eq "$(probe_runs)" 0
    chk "the reviewer did not run" eq "$(rev_n)" 0
    chk "shipcraft/review is not success" ne "$(st_state "$HEAD" shipcraft/review)" success
    pass ;;
  v1-3.4-ci-github-sem-status-nao-revisa)
    # Item 3, rule 4 (spec 323bfc3): the wait has a limit (ci_timeout); without the status the review does not run and shipcraft pr ends.
    EXPECT="gives up at tempo_max_ci, no review"
    v1_start codex
    CFGS='execution|ci|"github"
execution|ci_timeout|3'
    pr_main; pr_feature
    HEAD=$(git rev-parse HEAD)
    T0=$(date +%s)
    shipcraft_pr
    ELAPSED=$(( $(date +%s) - T0 ))
    chk "shipcraft pr did its job: the branch is on origin and the PR exists" eq "$(osha "$BR")-$(nwrites pr-create)" "$(git rev-parse HEAD)-1"
    chk "shipcraft pr stopped waiting (took ${ELAPSED}s)" test "$ELAPSED" -lt 60
    chk "the reviewer did not run" eq "$(rev_n)" 0
    chk "shipcraft/review is not success" ne "$(st_state "$HEAD" shipcraft/review)" success
    pass ;;
  v1-7.3-hook-fora-da-fila)
    # Item 7, rule 3: the hook does not queue; it runs even with the slot held by another project.
    EXPECT="hook commit runs while the slot is taken"
    queue_projects 1 "" 14 0
    # project "gama" only does a RED/GREEN cycle through the hook
    G="$CW/proj/gama"; copy_base "$WORK/base/python" "$G"; stubs_for "$CW/stubs/gama" codex
    use_proj "$G" "$CW/stubs/gama"
    setup_red
    L implement
    ( queue_one alfa ) & PIDA=$!
    queue_wait_start alfa ci
    use_proj "$G" "$CW/stubs/gama"
    must_accept "GREEN commit by the hook while another project holds the slot" commit commit_all "feat: slugify"
    chk "the hook did not wait for the slot (the other CI is still sleeping)" sh -c "! H tl-has '$TLINE' alfa ci end"
    chk "the hook closed the lock" one_lock_head_state closed
    chk "no queue message for the hook" no_queue_line
    wait $PIDA
    pass ;;

  # ======================================================== core: item 9 (version and monorepo)
  v1-9.1-monorepo-casos-por-suite)
    # Item 9, rule 1: with several suites a case is identified by suite and name (the same name in two suites is two cases).
    EXPECT="same test name in 2 suites = 2 cases"
    v1_start
    setup_init
    mkdir -p packages/a/tests packages/b/tests
    for p in a b; do
      printf 'def same():\n    raise NotImplementedError\n' > "packages/$p/mod.py"
    done
    printf 'from mod import same\n\n\ndef test_same():\n    assert same() == 1\n' > packages/a/tests/test_same.py
    printf 'from mod import same\n\n\ndef test_same():\n    assert same() == 2\n' > packages/b/tests/test_same.py
    cat > .shipcraft.toml <<'TOML'
shipcraft_min = "1.0"
lang = "python"
runner = "pytest"

[[suite]]
name = "a"
root = "packages/a"
command = "python3 -m pytest -p no:cacheprovider --junitxml={junit}"
globs = ["**/test_*.py", "**/conftest.py"]

[[suite]]
name = "b"
root = "packages/b"
command = "python3 -m pytest -p no:cacheprovider --junitxml={junit}"
globs = ["**/test_*.py", "**/conftest.py"]
TOML
    commit_all "chore: monorepo" || fail "harness: monorepo commit"
    BASE=$(head_rev)
    must_accept "shipcraft red over two suites" cmd shipcraft red
    must_accept "RED commit" commit commit_all "test: RED in both suites"
    chk "one open lock" one_lock_head_state open
    printf 'def same():\n    return 1\n' > packages/a/mod.py
    must_accept "GREEN of suite a only (hook)" commit commit_all "feat: a"
    chk "suite b still fails with the same test name: the lock stays open" one_lock_head_state open
    printf 'def same():\n    return 2\n' > packages/b/mod.py
    must_accept "GREEN of suite b" commit commit_all "feat: b"
    chk "both suites pass: the lock closes" one_lock_head_state closed
    must_accept "shipcraft ci over the range" cmd shipcraft ci --base "$BASE"
    pass ;;
  v1-9.2-sc2-min)
    # Generated configs require this package's major/minor; higher requirements refuse.
    EXPECT="init writes package minimum; a future version refuses"
    v1_start
    setup_init
    local expected_min future_min
    expected_min=$(H toml-get "$ACEITE/../nucleo/Cargo.toml" package.version | cut -d. -f1,2)
    future_min="$(( ${expected_min%%.*} + 1 )).0"
    chk "init writes the package major/minor minimum" eq "$(tget shipcraft_min)" "$expected_min"
    tset "" shipcraft_min "\"$future_min\""
    must_accept "fixture: config requires a future shipcraft" commit commit_nv "chore: future shipcraft_min"
    must_refuse "CI refuses the future minimum" cmd shipcraft ci --base "$BASE"
    chk "refusal names the future version" grep -F -q "$future_min" "$OUT.last3"
    printf 'x\n' > novo.txt
    must_refuse "hook refuses the future minimum" commit commit_all "feat: x"
    chk "refusal names the future version" grep -F -q "$future_min" "$OUT.last3"
    pass ;;
  v1-9.2-formato-da-trava)
    # Item 9, rule 2: the format version goes inside each lock; a lock in an unknown format is refused in three lines.
    EXPECT="lock has a format version; unknown refused"
    v1_start
    setup_red
    lf=$(lock_files_head)
    git show "HEAD:$lf" > "$CW/lock.json"
    chk "the lock has a format version key" H lock-key "$CW/lock.json"
    "$PY" - "$lf" <<'PY_LOCK'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
lock = json.loads(path.read_text())
assert lock['format'] == 3 and 'formato' not in lock, lock
lock['formato'] = 1
lock.pop('format')
path.write_text(json.dumps(lock))
PY_LOCK
    git add "$lf" || fail "fixture: stage legacy lock"
    must_refuse "the hook refuses a legacy lock format" cmd shipcraft check
    chk "legacy lock uses the format refusal" eq "$(H jsonl-field .git/shipcraft/runs.jsonl hook "$(head_rev)" code | tail -n 1)" '"lock-format"'
    chk "legacy lock asks to recreate RED" last3_has 'shipcraft red'
    cp "$CW/lock.json" "$lf"
    git add "$lf" || fail "fixture: restore current lock"
    H lock-bump "$lf" || fail "harness: could not bump the lock version"
    must_accept "commit of a lock in an unknown format (harness)" commit commit_nv "cheat: lock format 999"
    must_refuse "shipcraft ci over a lock in an unknown format" cmd shipcraft ci --base "$BASE"
    chk "the message talks about the format or version" last3_has '(version|format)'
    printf 'x\n' > novo.txt
    must_refuse "a commit by the hook over a lock in an unknown format" commit commit_all "feat: x"
    chk "the message talks about the format or version" last3_has '(version|format)'
    pass ;;

  # ======================================================== core: item 10
  v1-10.1-execucoes-jsonl)
    # Item 10, rule 1: each run (hook, ci, review) writes a row to .git/shipcraft/runs.jsonl, outside version control.
    EXPECT="rows for hook/ci/review x passed/refused/error"
    v1_start codex
    pr_main
    git checkout -q -b feature/jsonl
    : > "$CW/shas"
    L stub; L spec_test
    must_accept "shipcraft red" cmd shipcraft red
    must_accept "RED commit" commit commit_all "test: RED"
    apply cheat_edit
    must_refuse "hook refusal (locked test edited)" commit commit_all "cheat"
    git reset -q && git checkout -q -- .
    apply cheat_edit
    must_accept "cheat committed with --no-verify (harness)" commit commit_nv "cheat"
    must_refuse "shipcraft ci refuses the cheat" cmd shipcraft ci --base "$BASE"
    git reset -q --hard HEAD~1
    L implement
    must_accept "GREEN commit (hook passes)" commit commit_all "feat: slugify"
    git rev-parse HEAD >> "$CW/shas"
    must_accept "shipcraft ci" cmd shipcraft ci --base "$BASE"
    git rev-parse HEAD > "$ST/sha"; git rev-parse HEAD >> "$CW/shas"
    run_cmd TMO 120 shipcraft review
    chk "approved review exits 0" rc_zero
    rev_cfg changes
    run_cmd TMO 120 shipcraft review
    rev_cfg malformed
    run_cmd TMO 120 shipcraft review
    chk "the jsonl exists in .git/shipcraft/" test -s .git/shipcraft/runs.jsonl
    chk "the jsonl is not versioned" sh -c "! git ls-files | grep -q execucoes"
    chk "every row has the fields of the spec; every layer/result combination appears" eq "$(H jsonl-check .git/shipcraft/runs.jsonl main,feature/jsonl "$CW/shas")" OK
    pass ;;

  # ======================================================== core: item 11
  v1-11.1-linha-de-tamanho)
    # Item 11, rule 1: the shipcraft pr summary carries "Size: +A / -R product lines" for the whole diff against the merge-base (several commits; a file that comes and goes does not count; a modified one counts its removed lines).
    EXPECT="Size: +21 / -1 product lines"
    sz_start
    sz_branch
    sz_gen calc.py 12 c
    sz_gen textutil.py 4 t
    sz_gen scratch_tmp.py 30 s
    sz_commit "feat: calc, textutil e um rascunho"
    git rm -q scratch_tmp.py
    sz_gen more.py 5 m
    sz_commit "feat: more, sem o rascunho"
    sz_pr
    chk "the summary says +21 / -1 (12 + 4 + 5 added; the 1-line textutil.py replaced; the draft that came and went does not count)" sz_size 21 1
    pass ;;
  v1-11.1-tamanho-desde-o-merge-base)
    # Item 11, rule 1: the diff is against the merge-base, not against main's tip (which moved); a new shipcraft pr updates the line.
    EXPECT="+8 / -0 with main ahead, then +12 / -0"
    sz_start
    sz_branch
    sz_gen calc.py 8 c
    sz_commit "feat: calc"
    git checkout -q main || fail "harness: checkout main"
    sz_gen mainonly.py 40 m
    sz_main_commit "feat: coisa so da main"
    git checkout -q "$BR" || fail "harness: checkout $BR"
    sz_pr
    chk "the summary counts only the branch's own lines (main moved on by 40 lines)" sz_size 8 0
    sz_gen calc2.py 4 d
    sz_commit "feat: calc2"
    sz_pr
    chk "the second shipcraft pr updates the line to +12 / -0" sz_size 12 0
    pass ;;
  v1-11.1-pr-so-de-teste)
    # Item 11, rules 1 and 4: a PR with no product line still carries the line, with zeros, and product_lines = 0 in the jsonl.
    EXPECT="Size: +0 / -0 product lines; product_lines = 0"
    sz_start
    sz_branch
    sz_gen tests/test_only.py 25 t
    sz_commit "test: so um teste"
    sz_pr
    chk "the summary says +0 / -0" sz_size 0 0
    chk "the ci and review rows carry product_lines = 0" sz_jsonl 0
    pass ;;
  v1-11.2-testes-e-apoio-fora)
    # Item 11, rule 2: test and support files (init globs) are left out of the count; only product code.
    EXPECT="Size: +6 / -0 product lines"
    sz_start
    sz_branch
    sz_gen calc.py 6 c
    sz_gen tests/test_calc.py 20 t
    sz_gen tests/calc_test.py 7 u
    sz_gen tests/conftest.py 15 k
    sz_gen tests/helpers/util.py 10 h
    sz_gen tests/fixtures/expected.txt 9 e
    sz_commit "feat: calc e os testes dele"
    sz_pr
    chk "only calc.py counts (test_*.py, *_test.py, conftest.py, helpers/ and fixtures/ are out)" sz_size 6 0
    pass ;;
  v1-11.2-globs-do-toml)
    # Item 11, rule 2: "test" is what the .shipcraft.toml globs say, not fixed names: with test_globs = check_*.py and conftest.py, tests/test_extra.py is product.
    EXPECT="Size: +15 / -0 product lines"
    CFGS='-|test_globs|["**/check_*.py", "**/conftest.py"]'
    sz_start
    sz_branch
    sz_gen calc.py 6 c
    sz_gen tests/test_extra.py 9 t
    sz_gen tests/check_calc.py 20 k
    sz_gen conftest.py 15 f
    sz_commit "feat: calc, um teste no estilo antigo e um check"
    sz_pr
    chk "calc.py and tests/test_extra.py count; check_calc.py and conftest.py do not" sz_size 15 0
    pass ;;
  v1-11.2-globs-de-suite)
    # Item 11, rule 2: with [[suite]], each suite's globs are relative to its root (point 17): only what matches under the suite root is a test.
    EXPECT="Size: +23 / -0 product lines"
    sz_start
    sz_monorepo_toml
    mkdir -p packages/a/tests packages/b/tests
    printf 'def test_base():\n    assert True\n' > packages/a/tests/test_base.py
    cp packages/a/tests/test_base.py packages/b/tests/test_base.py
    sz_main_commit "chore: monorepo com duas suites"
    sz_branch
    sz_gen packages/a/mod.py 5 a
    sz_gen packages/a/tests/data_a.py 8 d
    sz_gen packages/a/test_stray.py 3 s
    sz_gen packages/b/mod.py 4 b
    sz_gen packages/b/tests/test_b.py 6 t
    sz_gen packages/b/conftest.py 7 k
    sz_gen tests/helper_root.py 11 r
    sz_commit "feat: mexe nas duas suites e na raiz"
    sz_pr
    chk "product = a/mod.py 5 + a/test_stray.py 3 + b/mod.py 4 + tests/helper_root.py 11; suite a's tests/** and suite b's test_*.py/conftest.py are out" sz_size 23 0
    pass ;;
  v1-11.2-renomeado-sem-mudanca-fora)
    # Item 11, rule 2: a file renamed with no content change does not count (neither added nor removed lines).
    EXPECT="Size: +6 / -0 product lines"
    sz_start
    sz_gen legacy_big.py 50 l
    sz_main_commit "feat: um modulo grande"
    sz_branch
    git mv legacy_big.py moved_big.py || fail "harness: git mv"
    sz_gen calc.py 6 c
    sz_commit "refactor: renomeia o modulo grande; feat: calc"
    sz_pr
    chk "the 50-line pure rename is out: +6 / -0, not +56 / -50" sz_size 6 0
    pass ;;
  v1-11.2-lockfile-fora)
    # Item 11, rule 2: the seven listed lockfiles do not count (in any folder, added or removed); one not on the list counts.
    EXPECT="Size: +17 / -0 product lines"
    sz_start
    sz_gen uv.lock 20 u
    sz_main_commit "chore: um uv.lock"
    sz_branch
    sz_gen calc.py 5 c
    sz_gen uv.lock 6 w
    for f in Cargo.lock package-lock.json pnpm-lock.yaml yarn.lock go.sum poetry.lock packages/web/pnpm-lock.yaml crates/core/Cargo.lock; do
      sz_gen "$f" 10 l
    done
    sz_gen Gemfile.lock 12 g
    sz_commit "feat: calc e os lockfiles"
    sz_pr
    chk "calc.py 5 + Gemfile.lock 12 (not in the list) count; the 7 listed lockfiles, in any folder, added or removed, do not" sz_size 17 0
    pass ;;
  v1-11.2-binario-fora)
    # Item 11, rule 2: a binary file (what git treats as binary) does not count, even full of line breaks.
    EXPECT="Size: +5 / -0 product lines"
    sz_start
    sz_branch
    sz_gen calc.py 5 c
    mkdir -p assets
    "$PY" -c 'import sys; open(sys.argv[1], "wb").write(b"\x89PNG\x00" + b"linha\n" * 300)' assets/logo.png
    "$PY" -c 'import sys; open(sys.argv[1], "wb").write(b"\x00" * 16 + b"x\n" * 200)' blob.dat
    sz_commit "feat: calc e dois binarios"
    sz_pr
    chk "shipcraft pr did not choke on the binaries and only calc.py counts" sz_size 5 0
    pass ;;
  v1-11.3-aviso-acima-de-500)
    # Item 11, rule 3: above 500 (added + removed, here 300 + 201 = 501) the summary carries the warning, without changing the exit code or statuses.
    EXPECT="+300 / -201 and the warning; rc 0; statuses success"
    sz_start
    sz_gen legacy.py 250 l
    sz_main_commit "feat: um modulo de 250 linhas"
    sz_branch
    head -n 49 legacy.py > legacy.tmp && mv legacy.tmp legacy.py
    sz_gen calc.py 300 c
    sz_commit "feat: calc; poda o modulo"
    sz_pr
    chk "the summary says +300 / -201" sz_size 300 201
    chk "the same summary carries the warning (501 > 500; each side alone is under 500)" eq "$(H size-warn "$ST")" SIM
    chk "shipcraft/ci is still success" eq "$(st_state "$HEAD" shipcraft/ci)" success
    chk "shipcraft/review is still success" eq "$(st_state "$HEAD" shipcraft/review)" success
    pass ;;
  v1-11.3-sem-aviso-em-500)
    # Item 11, rule 3: "above" is strict: exactly 500 (300 + 200) does not warn; and test lines (300 here) are not in the sum.
    EXPECT="+300 / -200, no warning"
    sz_start
    sz_gen legacy.py 250 l
    sz_main_commit "feat: um modulo de 250 linhas"
    sz_branch
    head -n 50 legacy.py > legacy.tmp && mv legacy.tmp legacy.py
    sz_gen calc.py 300 c
    sz_gen tests/test_bulk.py 300 t
    sz_commit "feat: calc; poda o modulo; muitos testes"
    sz_pr
    chk "the summary says +300 / -200" sz_size 300 200
    chk "the summary has no warning at exactly 500" eq "$(H size-warn "$ST")" NAO
    chk "the warning appears nowhere in the PR" eq "$(H warn-count "$ST")" 0
    pass ;;
  v1-11.3-aviso-linhas-maior-na-config)
    # Item 11, rule 3: [pr] warn_lines rules: with 1000, a 600-line PR does not warn.
    EXPECT="+600 / -0, no warning with warn_lines = 1000"
    CFGS='pr|warn_lines|1000'
    sz_start
    sz_branch
    sz_gen calc.py 600 c
    sz_commit "feat: calc grande"
    sz_pr
    chk "the summary says +600 / -0" sz_size 600 0
    chk "no warning: 600 is not above the configured 1000" eq "$(H size-warn "$ST")" NAO
    chk "the warning appears nowhere in the PR" eq "$(H warn-count "$ST")" 0
    pass ;;
  v1-11.3-aviso-linhas-menor-na-config)
    # Item 11, rule 3: [pr] warn_lines rules: with 40, a 41-line PR (30 + 11) warns.
    EXPECT="+30 / -11 and the warning with warn_lines = 40"
    CFGS='pr|warn_lines|40'
    sz_start
    sz_gen legacy.py 20 l
    sz_main_commit "feat: um modulo de 20 linhas"
    sz_branch
    head -n 9 legacy.py > legacy.tmp && mv legacy.tmp legacy.py
    sz_gen calc.py 30 c
    sz_commit "feat: calc; poda o modulo"
    sz_pr
    chk "the summary says +30 / -11" sz_size 30 11
    chk "the summary carries the warning: 41 is above the configured 40" eq "$(H size-warn "$ST")" SIM
    pass ;;
  v1-11.4-linhas-produto-no-jsonl)
    # Item 11, rule 4: the ci and review rows of shipcraft pr in runs.jsonl carry product_lines = added + removed (an integer), the same sum as the summary.
    EXPECT="Size: +12 / -3; product_lines = 15 on ci and review rows"
    sz_start
    sz_gen legacy.py 10 l
    sz_main_commit "feat: um modulo de 10 linhas"
    sz_branch
    head -n 7 legacy.py > legacy.tmp && mv legacy.tmp legacy.py
    sz_gen calc.py 12 c
    sz_gen tests/test_big.py 40 t
    sz_commit "feat: calc; poda o modulo; um teste"
    sz_pr
    chk "the summary says +12 / -3" sz_size 12 3
    chk "the ci and review rows carry product_lines = 15 (an integer: 12 + 3, tests out)" sz_jsonl 15
    pass ;;

  # ======================================================== core: item 15a
  v1-15a.1-recusa-antes-de-perguntar-e-escrever)
    # Item 15a, rule 1: init decides everything before writing and before asking; the refusal comes before the reviewer screen and creates no .shipcraft.toml, workflow or .shipcraft/.
    EXPECT="refused without asking or writing"
    v1_start codex claude
    printf '#!/bin/sh\necho "hook do projeto"\n' > .git/hooks/commit-msg && chmod +x .git/hooks/commit-msg
    cp .git/hooks/commit-msg "$CW/hook.orig"
    run_cmd_stdin /dev/null shipcraft init
    chk "shipcraft init refused" rc_nonzero
    msg_check || fail "refused, but $MSGERR"
    chk "the refusal says where to put shipcraft check" last3_has 'shipcraft check'
    chk "init did not ask the reviewer before refusing" out_hasnt '(who reviews|provider|Which reviewer|created \.shipcraft\.toml)'
    chk "init did not create .shipcraft.toml, .github or .shipcraft" init_untouched
    chk "the tree is clean" tree_clean
    chk "the existing commit-msg hook was not modified" cmp -s .git/hooks/commit-msg "$CW/hook.orig"
    pass ;;
  v1-15a.1-decide-antes-e-desfaz-escrita-no-meio)
    # Item 15a, rule 1 (edge): decide before writing (without deleting a pre-existing file or hitting a .github write error before checking the hook) and undo what was written if a write fails midway.
    EXPECT="decides before writing; rolls back partial writes"
    v1_start codex claude
    printf '# rascunho-preexistente\n' > .shipcraft.toml
    printf 'pre-commit:\n  parallel: true\n  commands:\n    lint:\n      run: echo ok\n' > lefthook.yml
    cp lefthook.yml "$CW/lh.orig"
    printf '#!/bin/sh\necho alien\n' > .git/hooks/commit-msg && chmod +x .git/hooks/commit-msg
    mkdir .github && chmod 500 .github
    run_cmd_stdin /dev/null shipcraft init
    chmod 700 .github
    chk "shipcraft init refused" rc_nonzero
    msg_check || fail "decide-before-write: $MSGERR"
    chk "refusal is the alien-hook one (mentions shipcraft check), not an OS write error on .github" last3_has 'shipcraft check'
    chk "init did not ask the reviewer" out_hasnt '(who reviews|provider|Which reviewer)'
    chk "pre-existing .shipcraft.toml was not overwritten or deleted" eq "$(cat .shipcraft.toml 2>/dev/null)" "# rascunho-preexistente"
    chk "lefthook.yml was not modified" cmp -s lefthook.yml "$CW/lh.orig"
    chk ".shipcraft/ was not created" test ! -e .shipcraft
    rm -rf .github .shipcraft.toml lefthook.yml .git/hooks/commit-msg
    chmod 500 .git/hooks
    run_cmd_stdin /dev/null shipcraft init
    chmod 700 .git/hooks
    chk "init failed when writing .git/hooks/commit-msg failed in the middle" rc_nonzero
    chk "partial writes (.shipcraft.toml, .github, .shipcraft) were undone" init_untouched
    chk "the tree is clean after rollback on .git/hooks failure" tree_clean
    mkdir .github && chmod 500 .github
    run_cmd_stdin /dev/null shipcraft init
    chmod 700 .github
    chk "unwritable .github is irrelevant" rc_zero
    chk "nothing created inside .github" eq "$(find .github -mindepth 1 -print)" ""
    pass ;;
  v1-15a.1-falha-preserva-config-simbolica)
    # Item 15a, rule 1 and fixed point 62: a failure keeps the pre-existing config symlink, without creating or changing its target.
    EXPECT="failed init preserves the config symlink and its absent or existing target"
    v1_start codex claude
    chmod 500 .git/hooks
    printf 'off\n' > "$CW/resposta"
    for alvo in ausente existente; do
      if [ "$alvo" = existente ]; then
        printf '# config local preexistente\n' > local-shipcraft.toml
        cp local-shipcraft.toml "$CW/config.orig"
      fi
      ln -s local-shipcraft.toml .shipcraft.toml
      run_cmd_stdin "$CW/resposta" shipcraft init --lang python
      chk "$alvo: init failed writing the hook" rc_nonzero
      chk "$alvo: the pre-existing config symlink remains" test -L .shipcraft.toml
      chk "$alvo: the config symlink still points to local-shipcraft.toml" eq "$(readlink .shipcraft.toml)" local-shipcraft.toml
      if [ "$alvo" = ausente ]; then
        chk "init did not create the missing config target" sh -c '[ ! -e local-shipcraft.toml ] && [ ! -L local-shipcraft.toml ]'
      else
        chk "init did not change the existing config target" cmp -s local-shipcraft.toml "$CW/config.orig"
      fi
      chk "$alvo: no .github created" test ! -e .github
      chk "$alvo: no partial lock directory or hook remains" sh -c '[ ! -e .shipcraft ] && [ ! -L .shipcraft ] && [ ! -e .git/hooks/commit-msg ] && [ ! -L .git/hooks/commit-msg ]'
      rm .shipcraft.toml
    done
    chmod 700 .git/hooks
    pass ;;
  v1-15a.2-hook-pre-commit-alheio)
    # Item 15a, rule 2: another hook in pre-commit (husky, the pre-commit framework) is refused in three lines naming shipcraft check, writing nothing.
    EXPECT="husky and pre-commit hooks refused cleanly"
    v1_start codex claude
    cat > .git/hooks/commit-msg <<'SH'
#!/usr/bin/env sh
. "$(dirname -- "$0")/_/husky.sh"
npx lint-staged
SH
    chmod +x .git/hooks/commit-msg
    cp .git/hooks/commit-msg "$CW/husky.orig"
    init_must_refuse_hook "husky pre-commit hook"
    chk "husky hook untouched" cmp -s .git/hooks/commit-msg "$CW/husky.orig"
    cat > .git/hooks/commit-msg <<'SH'
#!/usr/bin/env bash
# File generated by pre-commit: https://pre-commit.com
HERE="$(cd "$(dirname "$0")" && pwd)"
exec pre-commit hook-impl --config=.pre-commit-config.yaml --hook-type=pre-commit --hook-dir "$HERE" -- "$@"
SH
    chmod +x .git/hooks/commit-msg
    cp .git/hooks/commit-msg "$CW/precommit.orig"
    init_must_refuse_hook "pre-commit framework hook"
    chk "pre-commit framework hook untouched" cmp -s .git/hooks/commit-msg "$CW/precommit.orig"
    pass ;;
  v1-15a.2-hook-script-ou-link-quebrado)
    # Item 15a, rule 2 (edge): a broken symlink or any script in pre-commit is also refused in three lines naming shipcraft check, writing nothing.
    EXPECT="broken symlink and custom script refused cleanly"
    v1_start codex claude
    ln -s /caminho/inexistente/pre-commit .git/hooks/commit-msg
    init_must_refuse_hook "broken symlink in .git/hooks/commit-msg"
    chk "broken symlink preserved" test -L .git/hooks/commit-msg
    rm -f .git/hooks/commit-msg
    printf '#!/bin/sh\nmake lint\n' > .git/hooks/commit-msg && chmod +x .git/hooks/commit-msg
    cp .git/hooks/commit-msg "$CW/script.orig"
    init_must_refuse_hook "custom script in .git/hooks/commit-msg"
    chk "custom script untouched" cmp -s .git/hooks/commit-msg "$CW/script.orig"
    chmod -x .git/hooks/commit-msg
    init_must_refuse_hook "non-executable hook in .git/hooks/commit-msg"
    chk "non-executable hook untouched" cmp -s .git/hooks/commit-msg "$CW/script.orig"
    pass ;;
  v1-15a.2-core-hookspath-fora)
    # Item 15a, rule 2: core.hooksPath pointing outside .git/hooks is refused in three lines naming shipcraft check, writing nothing.
    EXPECT="core.hooksPath outside .git/hooks refused"
    v1_start codex claude
    mkdir -p .githooks
    git config core.hooksPath .githooks
    init_must_refuse_hook "core.hooksPath = .githooks"
    chk "no pre-commit created in .githooks" test ! -e .githooks/pre-commit
    chk "no pre-commit created in .git/hooks" test ! -e .git/hooks/commit-msg
    pass ;;
  v1-15a.2-core-hookspath-com-espacos)
    # Item 15a, rules 2 and 3: only the exact value .git/hooks is accepted; trailing or leading spaces must not be normalized.
    EXPECT="hooksPath with trailing or leading space refused before asking or writing"
    v1_start codex claude
    for hooks in '.git/hooks ' ' .git/hooks'; do
      git config core.hooksPath "$hooks"
      cp .git/config "$CW/git-config.orig"
      chk "the fixture preserves the literal hooksPath [$hooks]" eq "$(git config core.hooksPath)" "$hooks"
      init_must_refuse_hook "core.hooksPath = [$hooks]"
      chk "hooksPath [$hooks]: git config unchanged" cmp -s .git/config "$CW/git-config.orig"
      chk "hooksPath [$hooks]: no alternate hooks directory created" test ! -e "$hooks"
      chk "hooksPath [$hooks]: no hook created in .git/hooks" sh -c '[ ! -e .git/hooks/commit-msg ] && [ ! -L .git/hooks/commit-msg ]'
      chk "hooksPath [$hooks]: the tree remains clean" tree_clean
    done
    pass ;;
  v1-15a.3-core-hookspath-grafias-equivalentes)
    # Item 15a.3: equivalent spellings are not the literal .git/hooks; each one refuses before asking or writing.
    EXPECT="all three equivalent spellings refused without asking or writing"
    v1_start codex claude
    erros=""
    for grafia in barra ponto absoluto; do
      mkdir -p "$CW/hooks-$grafia"
      cd "$CW/hooks-$grafia" || fail "harness: cd to fresh repository"
      git init -q || fail "harness: git init"
      case "$grafia" in
        barra) hooks='.git/hooks/' ;;
        ponto) hooks='./.git/hooks' ;;
        absoluto) hooks="$(pwd -P)/.git/hooks" ;;
      esac
      git config core.hooksPath "$hooks"
      cp .git/config "$CW/config-$grafia.orig"
      run_cmd_stdin /dev/null shipcraft init --lang python
      if init_literal_refused "$CW/config-$grafia.orig"; then
        echo "$grafia [$hooks]: refused correctly" >> "$LOG"
      else
        echo "$grafia [$hooks]: rc=$RC; $MSGERR" >> "$LOG"
        cat "$OUT" >> "$LOG"
        erros="$erros $grafia"
      fi
    done
    chk "all spellings refused correctly (failures:$erros)" eq "$erros" ""
    pass ;;
  v1-15a.3-core-hookspath-exato)
    # Item 15a.3 (edge): refusing everything is not enough; the literal .git/hooks integrates normally.
    EXPECT="literal .git/hooks accepted with config, locks and executable hook"
    v1_start codex claude
    git config core.hooksPath .git/hooks
    cp .git/config "$CW/git-config.orig"
    run_cmd_stdin /dev/null shipcraft init --lang python
    chk "literal .git/hooks accepted" rc_zero
    chk "git config unchanged" cmp -s .git/config "$CW/git-config.orig"
    chk ".shipcraft.toml created" test -f .shipcraft.toml
    chk "no .github created" test ! -e .github
    chk "lock directory created" test -d .shipcraft/locks
    chk "executable commit-msg installed" test -x .git/hooks/commit-msg
    chk "installed hook invokes shipcraft check" grep -E -q 'shipcraft.*check' .git/hooks/commit-msg
    pass ;;
  v1-15a.2-core-hookspath-absoluto-e-git-hooks)
    # Item 15a, rule 2 (edge): an absolute core.hooksPath outside .git/hooks (even with a shipcraft hook there) is refused; pointing to .git/hooks is accepted.
    EXPECT="outside paths refused; .git/hooks accepted"
    v1_start codex claude
    mkdir -p "$CW/ext-hooks"
    git config core.hooksPath "$CW/ext-hooks"
    init_must_refuse_hook "core.hooksPath absolute outside .git/hooks"
    chk "no pre-commit created in ext-hooks" test ! -e "$CW/ext-hooks/pre-commit"
    printf '#!/bin/sh\nexec shipcraft check\n' > "$CW/ext-hooks/pre-commit" && chmod +x "$CW/ext-hooks/pre-commit"
    init_must_refuse_hook "core.hooksPath outside .git/hooks even with shipcraft check in it"
    git config core.hooksPath .git/hooks
    run_cmd_stdin /dev/null shipcraft init
    chk "core.hooksPath = .git/hooks is accepted" rc_zero
    chk ".shipcraft.toml created" test -f .shipcraft.toml
    chk ".git/hooks/commit-msg installed" test -x .git/hooks/commit-msg
    pass ;;
  v1-15a.2-husky-ou-pre-commit-na-raiz)
    # Items 15a.2 and 25: husky without the v9 layout refuses; block-style repos with empty hooks integrates with no launcher installed.
    EXPECT="husky without v9 layout refuses; block-style pre-commit integrates without launcher"
    v1_start codex claude
    mkdir -p .husky && printf 'npx lint-staged\n' > .husky/pre-commit
    init_must_refuse_hook ".husky/ at root without installed hook"
    chk "no hook installed in .git/hooks" test ! -e .git/hooks/commit-msg
    rm -rf .husky
    printf 'repos:\n  - repo: local\n    hooks: []\n' > .pre-commit-config.yaml
    cp .pre-commit-config.yaml "$CW/pcc.orig"
    must_accept "block-style .pre-commit-config.yaml integrates without launcher (item 25)" cmd shipcraft init
    chk "prefix kept and the exact local pair of item 25" "$PY" -c 'import pathlib,sys,yaml; p=pathlib.Path(".pre-commit-config.yaml"); assert p.read_bytes().startswith(pathlib.Path(sys.argv[1]).read_bytes()); repos=yaml.safe_load(p.read_bytes())["repos"]; assert repos[0] == {"repo":"local","hooks":[]}; expected=[dict(id=i,name=n,entry=c,language="system",always_run=True,pass_filenames=False,stages=[e]) for i,n,c,e in [("shipcraft-check","shipcraft check","shipcraft check --commit-msg","commit-msg"),("shipcraft-fecha","shipcraft close","shipcraft close","post-commit")]]; assert len(repos)==2 and repos[1]["repo"]=="local" and sorted(repos[1]["hooks"],key=lambda h:h["id"])==sorted(expected,key=lambda h:h["id"])' "$CW/pcc.orig"
    chk "no hook installed in .git/hooks" test ! -e .git/hooks/commit-msg
    pass ;;
  v1-15a.2-husky-vazio-ou-junto-com-lefthook)
    # Item 15a, rule 2 (edge): .husky/ at the root even when empty, or .husky/ and .pre-commit-config.yaml at the root together with lefthook.yml, are refused without touching anything.
    EXPECT="empty .husky/ and coexistence with lefthook.yml refused"
    v1_start codex claude
    mkdir -p .husky
    init_must_refuse_hook "empty .husky/ directory at root"
    rm -rf .husky
    printf 'pre-commit:\n  commands:\n    lint:\n      run: echo ok\n' > lefthook.yml
    cp lefthook.yml "$CW/lh.orig"
    printf 'repos: []\n' > .pre-commit-config.yaml
    init_must_refuse_hook ".pre-commit-config.yaml alongside lefthook.yml"
    chk "lefthook.yml was not modified" cmp -s lefthook.yml "$CW/lh.orig"
    rm -f .pre-commit-config.yaml
    mkdir -p .husky && printf 'npm test\n' > .husky/pre-commit
    init_must_refuse_hook ".husky/ alongside lefthook.yml"
    chk "lefthook.yml was not modified" cmp -s lefthook.yml "$CW/lh.orig"
    pass ;;
  v1-15a.2-lefthook-dois-nomes-ou-hook-alheio)
    # Item 15a, rule 2 (and 15b, point 1): two lefthook files together at the root, lefthook at the root with another pre-commit installed, or a lefthook hook with no config at the root are refused without touching anything.
    EXPECT="two lefthook files or mismatched hook refused"
    v1_start codex claude
    printf 'pre-commit:\n  commands:\n    a:\n      run: echo a\n' > "$CW/lh1"
    printf 'pre-commit:\n  commands:\n    b:\n      run: echo b\n' > "$CW/lh2"
    for pair in "lefthook.yml .lefthook.yml" "lefthook.yml lefthook.yaml" ".lefthook.yml .lefthook.yaml"; do
      set -- $pair
      cp "$CW/lh1" "$1"; cp "$CW/lh2" "$2"
      init_must_refuse_hook "two lefthook files ($1 + $2)"
      chk "$1 untouched" cmp -s "$1" "$CW/lh1"
      chk "$2 untouched" cmp -s "$2" "$CW/lh2"
      rm -f "$1" "$2"
    done
    cp "$CW/lh1" lefthook.yml
    printf '#!/bin/sh\necho "outro hook"\n' > .git/hooks/commit-msg && chmod +x .git/hooks/commit-msg
    cp .git/hooks/commit-msg "$CW/hook.orig"
    init_must_refuse_hook "lefthook.yml with alien .git/hooks/commit-msg"
    chk "lefthook.yml untouched" cmp -s lefthook.yml "$CW/lh1"
    chk ".git/hooks/commit-msg untouched" cmp -s .git/hooks/commit-msg "$CW/hook.orig"
    rm -f lefthook.yml .git/hooks/commit-msg
    printf '#!/bin/sh\n# File generated by lefthook\nlefthook run commit-msg "$@"\n' > .git/hooks/commit-msg && chmod +x .git/hooks/commit-msg
    cp .git/hooks/commit-msg "$CW/lhhook.orig"
    init_must_refuse_hook "lefthook hook in .git/hooks/commit-msg without lefthook config at root"
    chk "lefthook hook in .git/hooks/commit-msg untouched" cmp -s .git/hooks/commit-msg "$CW/lhhook.orig"
    pass ;;
  v1-15a.2-lefthook-condicoes-do-15b-ponto-1)
    # Item 15a, rule 2 (edge, item 15b point 1): a lefthook file with invalid YAML, extends, jobs or an extra filter/key in the pre-commit block is refused without touching the file.
    EXPECT="each failing condition of 15b.1 refused cleanly"
    v1_start codex claude
    check_bad_lh() { # check_bad_lh <file-name> <label> <content>
      local fn="$1" lbl="$2" body="$3"
      printf '%s\n' "$body" > "$fn"
      cp "$fn" "$CW/lh.bad"
      init_must_refuse_hook "$lbl ($fn)"
      chk "$fn untouched after $lbl" cmp -s "$fn" "$CW/lh.bad"
      chk "no commit-msg installed after $lbl" test ! -e .git/hooks/commit-msg
      rm -f "$fn"
    }
    check_bad_lh lefthook.yml "invalid YAML" "$(printf 'pre-commit:\n  commands: [unclosed')"
    check_bad_lh .lefthook.yml "extends" "$(printf 'extends:\n  - base.yml\npre-commit:\n  commands:\n    lint:\n      run: echo ok')"
    check_bad_lh .lefthook.yaml "top-level jobs" "$(printf 'jobs:\n  - name: lint\n    run: echo ok\npre-commit:\n  commands:\n    lint:\n      run: echo ok')"
    must_accept "parallel now integrates through commit-msg (item 20)" cmd "$PY" "$ACEITE/tools/item20.py" rota.parallel-true
    pass ;;

  *) OBS="harness: unknown case $CASE"; finish FAIL ;;
  esac
}

# ---------------------------------------------------------------- item 15a helpers
out_hasnt() { ! grep -E -q -- "$1" "$OUT" || { echo "output unexpectedly matches /$1/"; return 1; }; }
init_untouched() {
  local p
  for p in .shipcraft.toml .github .shipcraft; do
    [ ! -e "$p" ] && [ ! -L "$p" ] || { echo "$p was created"; return 1; }
  done
}
init_literal_refused() { # returns without ending the case, to probe every spelling even at RED
  MSGERR="accepted (rc=0)"
  [ "$RC" -ne 0 ] || return 1
  msg_check || return 1
  MSGERR="refusal must precede questions and writes, preserve config"
  last3_has 'shipcraft check' &&
    out_hasnt '(who reviews|provider|Which reviewer|created \.shipcraft\.toml)' &&
    init_untouched &&
    [ ! -e .git/hooks/commit-msg ] && [ ! -L .git/hooks/commit-msg ] &&
    cmp -s .git/config "$1"
}
init_must_refuse_hook() { # alien-hook refusal: rc != 0, 3 lines with shipcraft check, nothing created and no reviewer question
  local label="$1"
  run_cmd_stdin /dev/null shipcraft init
  [ "$RC" -ne 0 ] || fail "$label: accepted (rc=0)"
  msg_check || fail "$label: refused, but $MSGERR"
  chk "$label: last 3 lines mention shipcraft check" last3_has 'shipcraft check'
  chk "$label: did not create .shipcraft.toml, .github or .shipcraft" init_untouched
  chk "$label: did not ask the reviewer before refusing" out_hasnt '(who reviews|provider|Which reviewer|created \.shipcraft\.toml)'
}

# ---------------------------------------------------------------- helpers for the larger v1 cases
tl_has_not() { ! H tl-has "$@"; }
# the output without the battery's own paths (the case name has "fila" and numbers)
clean_out() { sed -e "s|$CW|.|g" -e "s|$T|.|g" -e "s|$WORK|.|g" "$OUT"; }
clean_out_hasi() { clean_out | grep -E -i -q -- "$1" || { echo "output lacks /$1/ (i)"; return 1; }; }
clean_out_hasnt() { ! clean_out | grep -E -i -q -- "$1" || { echo "output has /$1/"; return 1; }; }
clean_out_has() { clean_out | grep -E -q -- "$1" || { echo "output lacks /$1/"; return 1; }; }
queue_line_with_number() { clean_out | grep -i 'queue' | grep -q '[0-9]' || { echo "no line with 'queue' and a number; output: $(clean_out | head -c 200)"; return 1; }; }
no_queue_line() { ! clean_out | grep -i -q 'queue' || { echo "queue message in the hook output"; return 1; }; }
shown_local() {
  grep -q 'on this machine' "$OUT" && return 0
  H text-has "$ST" - 'on this machine' >/dev/null && return 0
  H st-dump "$ST" | grep -q 'on this machine' && return 0
  echo "'on this machine' appears nowhere"; return 1
}
review_failed_closed() { # the review failed closed: error with a reason, one attempt, never success
  HEAD=$(git rev-parse HEAD)
  chk "the reviewer ran exactly once (no retry)" eq "$(rev_n)" 1
  chk "shipcraft/review is error on the HEAD sha" eq "$(st_state "$HEAD" shipcraft/review)" error
  chk "the error carries a reason (description)" nonempty "$(st_desc "$HEAD" shipcraft/review)"
  chk "shipcraft/review never reached success" eq "$(H st-count-state "$ST" "$HEAD" shipcraft/review success)" 0
  pass
}
merge_setup() { # an outside PR with the branch on origin; a clean main checked out
  v1_start codex
  pr_main; pr_feature
  pr_outside "$BR"
  git checkout -q main
}
merge_must_refuse() {
  run_cmd TMO 120 shipcraft merge "$PRN"
  chk "shipcraft merge failed" rc_nonzero
  msg_check || fail "refused, but $MSGERR"
  chk "no merge was asked of GitHub" eq "$(nwrites merge)" 0
  chk "the PR is still open" eq "$(H pr-field "$ST" "$PRN" state)" OPEN
  pass
}
# Several projects on the same machine (same HOME) for the queue cases.
# queue_projects <n> <extra cfg> <CI probe seconds> <reviewer seconds>
queue_projects() {
  local n="$1" extra="$2" psl="$3" rsl="$4" names="alfa beta gama" name i=0
  TLINE="$CW/timeline.log"; : > "$TLINE"
  QNAMES=""
  for name in $names; do
    i=$((i + 1)); [ "$i" -le "$n" ] || break
    QNAMES="$QNAMES $name"
    mkdir -p "$CW/proj"; copy_base "$WORK/base/python" "$CW/proj/$name"
    stubs_for "$CW/stubs/$name" codex
    use_proj "$CW/proj/$name" "$CW/stubs/$name"
    PNAME="$name"; PSLEEP="$psl"; CFGS="$extra"
    [ "$name" = alfa ] && PSLEEP="${PSL_ALFA:-$psl}"
    pr_main; pr_feature "feature/$name"
    rev_cfg approve sleep="$rsl" timeline="$TLINE" name="$name"
  done
}
queue_one() { # queue_one <name>: shipcraft pr in that project; output and code in $CW/out-<name> and rc-<name>
  local name="$1"
  use_proj "$CW/proj/$name" "$CW/stubs/$name"
  git rev-parse HEAD > "$ST/sha"
  TMO 240 shipcraft pr --title "Titulo-PR-6d1" --body "$CW/body.md" > "$CW/out-$name" 2>&1
  echo $? > "$CW/rc-$name"
}
queue_run_all() { # all at the same time
  local name
  for name in $QNAMES; do ( queue_one "$name" ) & done
  wait
}
queue_wait_start() { # queue_wait_start <name> <layer>: waits for the "start" line in the timeline (up to 90 s)
  local i=0
  while ! H tl-has "$TLINE" "$1" "$2" start; do
    if [ -f "$CW/rc-$1" ]; then
      fail "shipcraft pr in $1 ended (rc=$(cat "$CW/rc-$1")) before its $2 ran: $(tail -n 1 "$CW/out-$1" | cut -c1-80)"
    fi
    i=$((i + 1)); [ "$i" -le 180 ] || fail "$1 never reached $2 start in 90 s"
    sleep 0.5
  done
}
timeline_is() { # timeline_is <max> <min intervals>
  local o; o=$(H timeline "$TLINE")
  case "$o" in "max=$1 "*) ;; *) echo "$o (want max=$1)"; return 1 ;; esac
  local n="${o##*intervals=}"
  [ "$n" -ge "$2" ] || { echo "$o (want at least $2 intervals)"; return 1; }
}

# ---------------------------------------------------------------- item 11 helpers (PR size)
sz_gen() { # sz_gen <file> <n> [prefix]: n lines of valid python (<prefix><i> = <i>), folders created
  mkdir -p "$(dirname "$1")"
  awk -v n="$2" -v p="${3:-v}" 'BEGIN { for (i = 1; i <= n; i++) printf "%s%d = %d\n", p, i, i }' > "$1"
}
sz_start() { v1_start codex; pr_main; }
sz_main_commit() { # commit on main and push to origin ("GitHub"'s main moves)
  must_accept "$1 (main)" commit commit_all "$1"
  git push -q origin main >> "$LOG" 2>&1 || fail "harness: push main"
  git fetch -q origin
}
sz_branch() { BR=feature/size; git checkout -q -b "$BR" || fail "harness: checkout -b $BR"; }
sz_commit() { must_accept "$1" commit commit_all "$1"; }
sz_pr() { shipcraft_pr; chk "shipcraft pr succeeded" rc_zero; HEAD=$(git rev-parse HEAD); }
sz_size() { # sz_size <added> <removed>: the "Size:" line of the last summary in the PR
  local l
  l=$(H size-line "$ST") || { echo "$l"; return 1; }
  match "Size: \\+$1 / -$2 product lines" "$l" || { echo "the line is: $l"; return 1; }
}
sz_jsonl() { # sz_jsonl <total>: the ci and review rows of the HEAD commit carry product_lines = total (an integer)
  local c v
  for c in ci review; do
    v=$(H jsonl-field .git/shipcraft/runs.jsonl "$c" "$HEAD" product_lines | sort -u) || { echo "$v"; return 1; }
    [ "$v" = "$1" ] || { echo "$c row(s): product_lines = $v, want $1"; return 1; }
  done
}
sz_monorepo_toml() { # a two-suite monorepo; review stays local (codex)
  cat > .shipcraft.toml <<'TOML'
shipcraft_min = "1.0"
lang = "python"
runner = "pytest"

[execution]
ci = "local"
review = "local"
ci_timeout = 1800

[roles]
review = "codex"

[review]
timeout = 1200

[[suite]]
name = "a"
root = "packages/a"
command = "python3 -m pytest -p no:cacheprovider --junitxml={junit}"
globs = ["tests/**"]

[[suite]]
name = "b"
root = "packages/b"
command = "python3 -m pytest -p no:cacheprovider --junitxml={junit}"
globs = ["**/test_*.py", "**/conftest.py"]
TOML
}

# ---------------------------------------------------------------- items, discovered
# Each item lives in lib/item<N>.sh, sourced in name order: item<N>_cases lists the ids
# (all v1-<N>.*), item<N>_case runs one of them and item<N>_langs, if present, says where
# they run (core, python, node, go; without it, core). A new item changes neither run.sh nor v1.sh.
ITEMS=""
for _f in "$ACEITE"/lib/item*.sh; do
  [ -f "$_f" ] || continue
  _n="${_f##*/item}"; ITEMS="$ITEMS ${_n%.sh}"
  . "$_f"
done
item_cases() { # item_cases <core|python|node|go>: the ids of the items that run there
  local _item
  for _item in $ITEMS; do
    if type "item${_item}_langs" >/dev/null 2>&1; then
      case " $("item${_item}_langs") " in *" $1 "*) ;; *) continue ;; esac
    elif [ "$1" != core ]; then
      continue
    fi
    "item${_item}_cases"
  done
}

. "$ACEITE/lib/english.sh"
