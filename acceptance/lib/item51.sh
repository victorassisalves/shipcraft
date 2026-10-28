# Item 51: real Vitest workspace selection, with argv captured before delegation.
item51_langs() { echo node; }
item51_cases() {
  for c in workspace arguments staged boundary command fallback; do echo "v1-51.$c"; done
}
item51_case() {
  EXPECT="item 51 positional RED files"
  v1_start
  must_accept 'real Vitest 2.1.9 contract' cmd "$PY" "$ACEITE/tools/item51.py" "${CASE#v1-51.}" "$(command -v shipcraft)"
  pass
}
