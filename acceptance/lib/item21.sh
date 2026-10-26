# Item 21: ferramentas externas offline, sem publicar nem executar release na árvore real.
item21_cases() {
  for c in versao-fora versao-min-numerica release-comum release-prefixo release-formato release-suja release-versao release-head release-tag release-remoto release-tags-falha release-preso release-bateria release-build release-rollback release-incerto instala-comum instala-repo instala-versao instala-rosetta instala-intel instala-linux instala-soma instala-linha instala-duplicada instala-extra instala-aninhado instala-modo instala-version instala-extracao instala-destino instala-permissao instala-igual instala-local instala-path remove; do
    echo "v1-21.$c"
  done
}
item21_case() {
  EXPECT="contrato do item 21, sem publicação"
  must_accept "item 21 caixa-preta" cmd "$PY" "$ACEITE/tools/item21.py" "${CASE#v1-21.}" "$ACEITE/.." "$(command -v shipcraft)"
  pass
}
