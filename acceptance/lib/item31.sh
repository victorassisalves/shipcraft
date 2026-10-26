# Item 31.1: config validated where it enters; spec b179778, no naming rules.
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
  chk "what happened" grep -q '^shipcraft refused:' "$OUT.last3"
  chk "why" grep -q '^Why:' "$OUT.last3"
  chk "how to proceed" grep -q '^Next:' "$OUT.last3"
}
item31_case() {
  local k="${CASE#v1-31.1-}"
  EXPECT="item 31.1: $k"
  v1_start
  setup_init
  chk "no open lock" no_lock
  cp .shipcraft.toml "$CW/config-valida" || fail "fixture: save config"
  case "$k" in
    hook-toml-invalido|hook-suite-sem-comando|hook-indice-invalido-arvore-valida)
      i31_invalid "$k"
      git add .shipcraft.toml || fail "fixture: stage config"
      if [ "$k" = hook-indice-invalido-arvore-valida ]; then
        cp "$CW/config-valida" .shipcraft.toml || fail "fixture: restore tree"
      fi
      must_refuse "hook validates the index config" commit commit_index "chore: config invalida"
      i31_refusal ;;
    hook-indice-valido-arvore-invalida)
      printf '\n# configuracao preparada valida\n' >> .shipcraft.toml
      cp .shipcraft.toml "$CW/config-preparada"
      git add .shipcraft.toml || fail "fixture: stage config"
      i31_invalid "$k"
      must_accept "hook ignores an invalid config outside the index" commit commit_index "chore: config valida"
      git show HEAD:.shipcraft.toml > "$CW/config-head"
      chk "HEAD gets the index bytes" cmp -s "$CW/config-preparada" "$CW/config-head"
      chk "tree stays invalid" grep -q '^isto não é toml' .shipcraft.toml ;;
    ci-toml-invalido|ci-suite-sem-comando)
      i31_invalid "$k"
      must_accept "fixture: commit skips hook" commit commit_nv "chore: config invalida"
      cp "$CW/config-valida" .shipcraft.toml || fail "fixture: valid tree"
      must_refuse "CI validates the invalid HEAD config with a valid tree" cmd shipcraft ci --base "$BASE"
      i31_refusal ;;
    ci-head-valido-arvore-invalida)
      printf '\n# configuracao HEAD valida\n' >> .shipcraft.toml
      cp .shipcraft.toml "$CW/config-preparada"
      must_accept "fixture: commit skips hook" commit commit_nv "chore: config valida"
      i31_invalid "$k"
      must_accept "CI judges HEAD and ignores the invalid tree" cmd shipcraft ci --base "$BASE"
      git show HEAD:.shipcraft.toml > "$CW/config-head"
      chk "valid HEAD preserved" cmp -s "$CW/config-preparada" "$CW/config-head"
      chk "invalid tree preserved" grep -q '^isto não é toml' .shipcraft.toml ;;
    hook-apaga-config)
      git rm -q .shipcraft.toml || fail "fixture: remove config"
      must_accept "removing the config uninstalls without refusal" commit commit_index "chore: desinstala shipcraft"
      chk "config missing from HEAD" sh -c '! git cat-file -e HEAD:.shipcraft.toml 2>/dev/null' ;;
    ci-apaga-config)
      git rm -q .shipcraft.toml || fail "fixture: remove config"
      must_accept "fixture: commit skips hook" commit commit_nv "chore: desinstala shipcraft"
      must_accept "CI accepts the uninstall without a lock" cmd shipcraft ci --base "$BASE" ;;
    *) fail "unknown case: $k" ;;
  esac
  pass
}
