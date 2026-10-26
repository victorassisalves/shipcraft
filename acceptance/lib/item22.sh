# Item 22: ambiente da suíte, bytes NUL, fallback e composição dos filtros.
item22_cases() {
  for c in bytes-comum bytes-borda copia-indice arvore listas-dedup lista-grande duas-suites varias-travas sem-mapa parcial bash old-omitido sumiu-comando sumiu-sc2 sumiu-parcial pulado pulado-parcial temporario-falha ambiente-red ambiente-ci ambiente-verifica ambiente-build ambiente-vazio filtra-invalido filtra-invalido-vazio filtra-invalido-maiusculo filtra-invalido-numero filtra-invalido-bool filtra-invalido-lista; do
    echo "v1-22.$c"
  done
  for r in pytest vitest jest go; do
    for f in comando sc2 padrao comentario backup; do
      echo "v1-22.filtro-$f-$r"
    done
  done
}
item22_case() {
  local scenario="${CASE//sc2/shipcraft}"
  EXPECT="contrato do item 22"
  v1_start
  must_accept "item 22 caixa-preta" cmd "$PY" "$ACEITE/tools/item22.py" "${scenario#v1-22.}" "$(command -v shipcraft)"
  pass
}
