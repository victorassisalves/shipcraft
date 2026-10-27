# Item 48: the exact empty root placeholder is not an outside lock.
item48_cases() {
  local route mode
  for route in pre msg; do
    for mode in committed untracked ignored intent staged index-empty index-nonempty nonempty committed-nonempty committed-nonempty-outside staged-nonempty only-empty only-nonempty only-symlink symlink staged-symlink nested other-root six query-others query-ignored refusal; do
      echo "v1-48.$route-$mode"
    done
  done
}
item48_case() {
  EXPECT="empty root .gitkeep excluded; verdict unchanged"
  v1_start codex
  setup_init
  must_accept 'item 48 real-git contract' cmd "$PY" "$ACEITE/tools/item48.py" "${CASE#v1-48.}" "$(command -v shipcraft)" "$CW"
  pass
}
