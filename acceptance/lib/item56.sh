# Item 56: real compiler, working-tree configs and per-suite decisions.
item56_langs() { echo node; }
item56_cases() {
  local c
  for c in solution empty-include jsonc jsonc-cr jsonc-ls jsonc-ps untracked build-fails missing-reference files include extends extends-null references-absent references-empty unparsable symlink files-null files-object files-absent include-null include-string references-null references-object nonobject workspace control existing; do echo "v1-56.$c"; done
}
item56_case() {
  local mode=${CASE#v1-56.}
  EXPECT="item 56: $mode"
  "$PY" "$ACEITE/tools/item56.py" "$mode" || fail 'harness: fixture'
  case "$mode" in
    solution|empty-include|jsonc|jsonc-cr|jsonc-ls|jsonc-ps|untracked|build-fails|missing-reference|workspace|control)
      local target=.
      [ "$mode" != workspace ] || target=packages/solution
      [ "$mode" != control ] || target=$(printf 'packages/sol\tution')
      npx --no -- tsc -b "$target" >> "$LOG" 2>&1
      local compiler_rc=$?
      case "$mode" in
        build-fails|missing-reference) chk 'real compiler refuses failing reference' test "$compiler_rc" -gt 0 ;;
        *) chk 'real compiler builds referenced project' test "$compiler_rc" -eq 0 ;;
      esac
      find projects -name dist -type d -exec rm -rf {} +
      find . -name '*.tsbuildinfo' -not -path './node_modules/*' -delete ;;
  esac
  git add -A
  [ "$mode" != untracked ] || git reset -q -- tsconfig.json
  git commit -q -m 'test: item 56 fixture' || fail 'harness: commit'
  if [ "$mode" = existing ]; then
    printf '# user config must survive\nlang = "node"\n' > .shipcraft.toml
    cp .shipcraft.toml "$CW/original"
  fi
  mkdir -p .git/shipcraft
  printf 'sentinel\n' > .git/shipcraft/preserve
  cp -R .git/shipcraft "$CW/state"
  run_cmd shipcraft init
  chk 'init exits zero' rc_zero
  chk 'init writes no run row and preserves state' diff -r "$CW/state" .git/shipcraft
  if [ "$mode" = existing ]; then
    chk 'existing config preserved byte for byte' cmp .shipcraft.toml "$CW/original"
    chk 'existing config emits no item 56 notice' sh -c '! grep -F "checks no file;" "$1"' sh "$OUT"
  else
    chk 'per-suite check keys, exact stdout notice, count and order' "$PY" "$ACEITE/tools/item56.py" "$mode" "$OUT"
  fi
  pass
}
