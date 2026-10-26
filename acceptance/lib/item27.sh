# Item 27, d44c1b5: init neither reads nor writes the workflow; the message uses the final config.
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
  chk "literal final line for the real CI" eq "$(cat "$CW/final27")" "$text"
}
item27_case() {
  EXPECT='item 27 contract: workflow untouched and real CI'
  v1_start codex
  case "$CASE" in
    v1-27.docs-*)
      must_accept "shipcraft CI guide" cmd "$PY" "$ACEITE/tools/item27.py" "$ACEITE/../docs/github-ci.md" "${CASE#v1-27.docs-}"
      pass ;;
    v1-27.monorepo)
      mkdir -p packages/api/src packages/web/src
      printf '{"name":"root","private":true,"workspaces":["packages/*"]}\n' > package.json
      for pkg in api web; do
        printf '{"name":"%s","devDependencies":{"vitest":"5.0.4"}}\n' "$pkg" > "packages/$pkg/package.json"
        printf 'import {it} from "vitest"; it("ok",()=>{});\n' > "packages/$pkg/src/a.test.ts"
      done
      git add packages package.json; git commit -q -m 'test: monorepo item 27' || fail 'monorepo fixture'
      ;;
    v1-27.mensagem-*)
      # Start from a valid generated config, change the CI and run init again: the
      # init's local default must not replace the message of the preserved config.
      must_accept "first init" cmd shipcraft init
      rm -rf .github
      local ci27="${CASE#v1-27.mensagem-}"
      tset execution ci "\"${ci27/desligado/off}\""
      cp .shipcraft.toml "$CW/config27"
      must_accept "init with existing config" cmd shipcraft init
      chk "existing config preserved" cmp -s .shipcraft.toml "$CW/config27"
      b27_final "$ci27"
      chk "no .github with CI $ci27" test ! -e .github
      pass ;;
    v1-27.github-*)
      remote_setup
      if [ "$CASE" = v1-27.github-protegido ]; then echo none > "$ST/protection"
      else echo 403 > "$ST/protection"; fi
      must_accept "init --github" cmd shipcraft init --github
      if [ "$CASE" = v1-27.github-protegido ]; then
        chk "two required statuses" eq "$(H protect-ok "$ST")" OK
      else chk "free plan preserved" eq "$(cat "$ST/protection")" 403; fi
      chk "--github does not create .github" test ! -e .github
      b27_final local
      pass ;;
    v1-27.igual)
      # The identical old workflow comes from the binary, not from a copy of the implementation.
      must_accept "init fixture" cmd shipcraft init
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
  chk "init accepts without reading the workflow" rc_zero
  case "$CASE" in
    v1-27.igual|v1-27.diferente|v1-27.ilegivel)
      chk "workflow bytes preserved" cmp -s .github/workflows/shipcraft.yml "$CW/workflow27" ;;
    v1-27.link)
      chk "link preserved" test -L .github/workflows/shipcraft.yml
      chk "link target preserved" eq "$(readlink .github/workflows/shipcraft.yml)" "$CW/alvo27"
      chk "external target preserved" cmp -s "$CW/alvo27" "$CW/workflow27" ;;
    v1-27.fifo) chk "FIFO preserved without a blocking read" test -p .github/workflows/shipcraft.yml ;;
    *) chk "no .github created" test ! -e .github ;;
  esac
  if [ -f "$CW/stat27" ]; then
    "$PY" -c 'import os; s=os.lstat(".github/workflows/shipcraft.yml"); print(s.st_ino, s.st_mtime_ns, s.st_size)' > "$CW/stat27.after"
    chk "workflow was neither rewritten nor recreated" cmp -s "$CW/stat27" "$CW/stat27.after"
    find .github -print | sort > "$CW/paths27.after"
    chk "no other file in .github" cmp -s "$CW/paths27" "$CW/paths27.after"
  fi
  case "$CASE" in
    v1-27.ausente|v1-27.monorepo) b27_final local ;;
  esac
  pass
}
item27_langs() { echo python node go; }
