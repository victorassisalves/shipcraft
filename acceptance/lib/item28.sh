# Item 28, spec 119a6d6: consultas Git na árvore original; só aviso.
item28_cases() {
  local route mode
  for route in pre msg; do
    for mode in comum gitignore info global negacao subpasta link-arquivo link-pasta ilegivel intencao blob-vazio espaco aspas cinco seis sete recusa consulta-outros consulta-ignorados only only-ignorado copia sem-arquivos rastreado; do
      echo "v1-28.$route-$mode"
    done
  done
}
item28_case() {
  local mode="${CASE#v1-28.}"
  EXPECT="aviso do item 28 preserva o julgamento e o índice"
  v1_start codex
  case "$mode" in *-copia) setup_red ;; *) setup_init ;; esac
  must_accept 'item 28 caixa-preta' cmd "$PY" "$ACEITE/tools/item28.py" "$mode" "$(command -v shipcraft)" "$CW"
  pass
}
