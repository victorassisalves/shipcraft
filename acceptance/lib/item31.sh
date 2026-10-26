# Item 31.1: config validada onde entra; spec b179778, sem regras de nomes.
item31_cases() {
  echo v1-31.1-hook-toml-invalido v1-31.1-hook-suite-sem-comando
  echo v1-31.1-hook-indice-invalido-arvore-valida v1-31.1-hook-indice-valido-arvore-invalida
  echo v1-31.1-ci-toml-invalido v1-31.1-ci-suite-sem-comando v1-31.1-ci-head-valido-arvore-invalida
  echo v1-31.1-hook-apaga-config v1-31.1-ci-apaga-config
}
i31_invalid() {
  case "$1" in
    *suite-sem-comando)
      cat > .shipcraft.toml <<'TOML'
shipcraft_min = "0.0"
lang = "python"
runner = "pytest"
[[suite]]
name = "api"
root = "."
globs = ["**/test_*.py"]
TOML
      ;;
    *) printf 'isto não é toml [\n' > .shipcraft.toml ;;
  esac
}
i31_refusal() {
  chk "o que houve" grep -q '^shipcraft refused:' "$OUT.last3"
  chk "por que" grep -q '^Why:' "$OUT.last3"
  chk "como seguir" grep -q '^Next:' "$OUT.last3"
}
item31_case() {
  local k="${CASE#v1-31.1-}"
  EXPECT="item 31.1: $k"
  v1_start
  setup_init
  chk "sem trava aberta" no_lock
  cp .shipcraft.toml "$CW/config-valida" || fail "fixture: salva config"
  case "$k" in
    hook-toml-invalido|hook-suite-sem-comando|hook-indice-invalido-arvore-valida)
      i31_invalid "$k"
      git add .shipcraft.toml || fail "fixture: prepara config"
      if [ "$k" = hook-indice-invalido-arvore-valida ]; then
        cp "$CW/config-valida" .shipcraft.toml || fail "fixture: restaura arvore"
      fi
      must_refuse "hook valida config do indice" commit commit_index "chore: config invalida"
      i31_refusal ;;
    hook-indice-valido-arvore-invalida)
      printf '\n# configuracao preparada valida\n' >> .shipcraft.toml
      cp .shipcraft.toml "$CW/config-preparada"
      git add .shipcraft.toml || fail "fixture: prepara config"
      i31_invalid "$k"
      must_accept "hook ignora config invalida fora do indice" commit commit_index "chore: config valida"
      git show HEAD:.shipcraft.toml > "$CW/config-head"
      chk "HEAD recebe bytes do indice" cmp -s "$CW/config-preparada" "$CW/config-head"
      chk "arvore continua invalida" grep -q '^isto não é toml' .shipcraft.toml ;;
    ci-toml-invalido|ci-suite-sem-comando)
      i31_invalid "$k"
      must_accept "fixture: commit ignora hook" commit commit_nv "chore: config invalida"
      cp "$CW/config-valida" .shipcraft.toml || fail "fixture: arvore valida"
      must_refuse "CI valida config invalida do HEAD com arvore valida" cmd shipcraft ci --base "$BASE"
      i31_refusal ;;
    ci-head-valido-arvore-invalida)
      printf '\n# configuracao HEAD valida\n' >> .shipcraft.toml
      cp .shipcraft.toml "$CW/config-preparada"
      must_accept "fixture: commit ignora hook" commit commit_nv "chore: config valida"
      i31_invalid "$k"
      must_accept "CI julga HEAD e ignora arvore invalida" cmd shipcraft ci --base "$BASE"
      git show HEAD:.shipcraft.toml > "$CW/config-head"
      chk "HEAD valido preservado" cmp -s "$CW/config-preparada" "$CW/config-head"
      chk "arvore invalida preservada" grep -q '^isto não é toml' .shipcraft.toml ;;
    hook-apaga-config)
      git rm -q .shipcraft.toml || fail "fixture: remove config"
      must_accept "remover config desinstala sem recusa" commit commit_index "chore: desinstala shipcraft"
      chk "config ausente no HEAD" sh -c '! git cat-file -e HEAD:.shipcraft.toml 2>/dev/null' ;;
    ci-apaga-config)
      git rm -q .shipcraft.toml || fail "fixture: remove config"
      must_accept "fixture: commit ignora hook" commit commit_nv "chore: desinstala shipcraft"
      must_accept "CI aceita desinstalacao sem trava" cmd shipcraft ci --base "$BASE" ;;
    *) fail "caso desconhecido: $k" ;;
  esac
  pass
}
