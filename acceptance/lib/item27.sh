# Item 27, d44c1b5: o init não lê nem escreve workflow; mensagem usa a config final.
item27_cases() {
  local c
  for c in ausente monorepo igual diferente link ilegivel fifo github-protegido github-gratis mensagem-local mensagem-desligado mensagem-github docs-workflow docs-passos; do
    echo "v1-27.$c"
  done
}
b27_final() {
  local text
  case "$1" in
    local) text='CI runs on this machine through shipcraft pr. To run it on GitHub, see shipcraft docs/github-ci.md.' ;;
    desligado) text='CI is off ([execution] ci = "off").' ;;
    github) text='CI runs on GitHub: the workflow is in shipcraft docs/github-ci.md if the project does not have one yet.' ;;
  esac
  grep '[^[:space:]]' "$OUT" | tail -n 1 > "$CW/final27"
  chk "linha final literal do CI real" eq "$(cat "$CW/final27")" "$text"
}
item27_case() {
  EXPECT='contrato item 27: workflow intocado e CI real'
  v1_start codex
  case "$CASE" in
    v1-27.docs-*)
      must_accept "guia de CI do shipcraft" cmd "$PY" "$ACEITE/tools/item27.py" "$ACEITE/../docs/github-ci.md" "${CASE#v1-27.docs-}"
      pass ;;
    v1-27.monorepo)
      mkdir -p packages/api/src packages/web/src
      printf '{"name":"root","private":true,"workspaces":["packages/*"]}\n' > package.json
      for pkg in api web; do
        printf '{"name":"%s","devDependencies":{"vitest":"5.0.4"}}\n' "$pkg" > "packages/$pkg/package.json"
        printf 'import {it} from "vitest"; it("ok",()=>{});\n' > "packages/$pkg/src/a.test.ts"
      done
      git add packages package.json; git commit -q -m 'test: monorepo item 27' || fail 'fixture monorepo'
      ;;
    v1-27.mensagem-*)
      # Partir de uma config válida gerada, trocar o CI e reiniciar: o padrão
      # local do init não pode substituir a mensagem da configuração preservada.
      must_accept "primeiro init" cmd shipcraft init
      rm -rf .github
      local ci27="${CASE#v1-27.mensagem-}"
      tset execution ci "\"${ci27/desligado/off}\""
      cp .shipcraft.toml "$CW/config27"
      must_accept "init com config existente" cmd shipcraft init
      chk "config existente preservada" cmp -s .shipcraft.toml "$CW/config27"
      b27_final "$ci27"
      chk "sem .github com CI $ci27" test ! -e .github
      pass ;;
    v1-27.github-*)
      remote_setup
      if [ "$CASE" = v1-27.github-protegido ]; then echo none > "$ST/protection"
      else echo 403 > "$ST/protection"; fi
      must_accept "init --github" cmd shipcraft init --github
      if [ "$CASE" = v1-27.github-protegido ]; then
        chk "dois status obrigatórios" eq "$(H protect-ok "$ST")" OK
      else chk "plano grátis preservado" eq "$(cat "$ST/protection")" 403; fi
      chk "--github não cria .github" test ! -e .github
      b27_final local
      pass ;;
    v1-27.igual)
      # O workflow antigo igual é produzido pelo binário, sem cópia da implementação.
      must_accept "fixture do init" cmd shipcraft init
      if [ ! -f .github/workflows/shipcraft.yml ]; then
        mkdir -p .github/workflows
        printf '# workflow preexistente\n' > .github/workflows/shipcraft.yml
      fi
      cp .github/workflows/shipcraft.yml "$CW/workflow27"
      ;;
    v1-27.diferente|v1-27.link|v1-27.ilegivel|v1-27.fifo)
      mkdir -p .github/workflows
      printf '# workflow alheio\r\nname: preservação\r\njobs: {}\r\n' > "$CW/workflow27"
      case "$CASE" in
        *link) cp "$CW/workflow27" "$CW/alvo27"; ln -s "$CW/alvo27" .github/workflows/shipcraft.yml ;;
        *fifo) mkfifo .github/workflows/shipcraft.yml ;;
        *) cp "$CW/workflow27" .github/workflows/shipcraft.yml ;;
      esac
      [ "$CASE" != v1-27.ilegivel ] || chmod 000 .github/workflows/shipcraft.yml
      ;;
  esac
  case "$CASE" in
    v1-27.igual|v1-27.diferente|v1-27.link|v1-27.ilegivel|v1-27.fifo)
      "$PY" -c 'import os; s=os.lstat(".github/workflows/shipcraft.yml"); print(s.st_ino, s.st_mtime_ns, s.st_size)' > "$CW/stat27"
      find .github -print | sort > "$CW/paths27"
      ;;
  esac
  if [ "$CASE" = v1-27.fifo ]; then
    run_cmd_stdin /dev/null "$PY" "$ACEITE/tools/tmo.py" 10 shipcraft init
  else
    run_cmd_stdin /dev/null shipcraft init
  fi
  [ "$CASE" != v1-27.ilegivel ] || chmod 600 .github/workflows/shipcraft.yml
  chk "init aceita sem consultar workflow" rc_zero
  case "$CASE" in
    v1-27.igual|v1-27.diferente|v1-27.ilegivel)
      chk "bytes do workflow preservados" cmp -s .github/workflows/shipcraft.yml "$CW/workflow27" ;;
    v1-27.link)
      chk "link preservado" test -L .github/workflows/shipcraft.yml
      chk "destino do link preservado" eq "$(readlink .github/workflows/shipcraft.yml)" "$CW/alvo27"
      chk "alvo externo preservado" cmp -s "$CW/alvo27" "$CW/workflow27" ;;
    v1-27.fifo) chk "FIFO preservado sem leitura bloqueante" test -p .github/workflows/shipcraft.yml ;;
    *) chk "nenhum .github criado" test ! -e .github ;;
  esac
  if [ -f "$CW/stat27" ]; then
    "$PY" -c 'import os; s=os.lstat(".github/workflows/shipcraft.yml"); print(s.st_ino, s.st_mtime_ns, s.st_size)' > "$CW/stat27.after"
    chk "workflow não foi regravado nem recriado" cmp -s "$CW/stat27" "$CW/stat27.after"
    find .github -print | sort > "$CW/paths27.after"
    chk "nenhum outro arquivo em .github" cmp -s "$CW/paths27" "$CW/paths27.after"
  fi
  case "$CASE" in
    v1-27.ausente|v1-27.monorepo) b27_final local ;;
  esac
  pass
}
item27_langs() { echo python node go; }
