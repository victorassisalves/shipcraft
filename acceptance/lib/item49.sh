# Item 49: literal closing messages, ordering, retry and historical subjects.
item49_cases() {
  for mode in post retry post-ref-failure two-forward two-reverse legacy-hook legacy-ci; do
    echo "v1-49.$mode"
  done
}
item49_case() {
  EXPECT="item 49 closing commit contract"
  v1_start codex
  setup_init
  L stub; L spec_test
  must_accept 'item 49 real-git contract' cmd "$PY" "$ACEITE/tools/item49.py" "${CASE#v1-49.}"
  pass
}
