# Item 17: judgment and closing; item 20 init is out of scope.
item17_cases() {
  for c in julgamento indice-final ignorado solto recusa-limpa-marca marca-falha fecha-comum amend parcial destacado indice-preservado arvore-divergente varias-travas worktree outra-arvore outro-head abortada sem-reflog sem-marca marca-invalida merge cherry-pick revert rebase assinatura-ssh-env-1 assinatura-ssh-env-2 assinatura-ssh-repo assinatura-falha index-lock ref-andou pos-ref-falha primeiro-commit-verde-recusa primeiro-red-green-fecha configuracoes; do
    echo "v1-17.$c"
  done
}
item17_case() {
  EXPECT="item 17 contract"
  v1_start codex
  setup_init
  L stub; L spec_test
  must_accept "item 17 black box" cmd "$PY" "$ACEITE/tools/item17.py" "${CASE#v1-17.}"
  pass
}
