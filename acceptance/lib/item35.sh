# Item 35: versões completas dos arquivos, spec 456d6e7.
i35_commit() { must_accept "$1" commit commit_all "$1"; }
i35_indentacao() {
  EXPECT='nova revisão após mudança de indentação'
  v1_start codex
  pr_main
  git checkout -qb feature/indentacao
  printf 'def permitido(admin):\n    if admin:\n        pass\n        return True\n    return False\n' > app.py
  i35_commit 'feat: autorização'
  shipcraft_pr
  chk 'primeira revisão aprova' rc_zero
  chk 'primeiro revisor executou' eq "$(rev_n)" 1
  chk 'antes: visitante recusado' "$PY" -c 'from app import permitido; assert permitido(False) is False'
  printf 'def permitido(admin):\n    if admin:\n        pass\n    return True\n    return False\n' > app.py
  i35_commit 'feat: muda indentação'
  chk 'depois: visitante permitido' "$PY" -c 'from app import permitido; assert permitido(False) is True'
  rev_cfg changes
  shipcraft_pr
  echo "REPRO35: reviews=$(rev_n) status=$(st_state "$(head_rev)" shipcraft/review) rc=$RC" >> "$LOG"
  chk 'indentação exige nova revisão' eq "$(rev_n)" 2
  chk 'nova revisão recusa' rc_nonzero
  chk 'status do novo HEAD recusa' eq "$(st_state "$(head_rev)" shipcraft/review)" failure
  pass
}

# O caso inicial acima fica primeiro e reproduz o escape antes dos demais.
item35_cases() {
  echo v1-35.1-indentacao
  for c in conteudo linha modo binario atributo textconv submodulo rebase-igual rebase-arquivo; do echo "v1-35.1-$c"; done
  for c in erro vazio erro-com-saida; do echo "v1-35.2-$c"; done
  for c in registro legado maiusculo curto tipo; do echo "v1-35.3-$c"; done
  for c in externo textconv cor; do echo "v1-35.4-$c"; done
  for c in approve recusa erro; do echo "v1-35.5-$c"; done
}
i35_key() {
  git diff --raw -z --no-abbrev --no-renames --ignore-submodules=none origin/main HEAD | "$PY" -c 'import sys,hashlib; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
}
i35_record() { # chave da revisão fresca deve coincidir byte a byte com o Git
  "$PY" - "$1" "$(head_rev)" <<'PY'
import json,re,sys
rows=[json.loads(x) for x in open('.git/shipcraft/runs.jsonl')]
rows=[r for r in rows if r.get('layer')=='review' and r.get('commit')==sys.argv[2]]
assert rows, 'sem registro de revisão do HEAD'
k=rows[-1].get('diff_sha256')
assert isinstance(k,str) and re.fullmatch('[0-9a-f]{64}',k), ('diff_sha256 inválido',k)
assert k==sys.argv[1], (k,sys.argv[1])
PY
}
i35_again() {
  rev_cfg changes
  shipcraft_pr
  chk 'mudança exige segunda chamada' eq "$(rev_n)" 2
  chk 'segunda revisão recusa' rc_nonzero
  chk 'HEAD novo recebe failure' eq "$(st_state "$(head_rev)" shipcraft/review)" failure
}
item35_case() {
  [ "$CASE" != v1-35.1-indentacao ] || { i35_indentacao; return; }
  local c="${CASE#v1-35.}" oldkey newkey
  EXPECT="item35 $c"
  v1_start codex
  pr_main
  # Base com arquivo existente para distinguir mudanças nos dois lados do diff.
  seq 1 30 > contexto.txt
  printf 'app.py diff=oculto\n' > .gitattributes
  printf '#!/bin/sh\nprintf "RESUMO-OCULTO-35\\n"\n' > "$CB/converter35"
  chmod +x "$CB/converter35"
  case "$c" in
    1-atributo) printf 'app.py -diff\n' > .gitattributes ;;
    1-textconv|4-textconv) git config diff.oculto.textconv "$CB/converter35" ;;
  esac
  i35_commit 'test: base de versões'
  git push -q origin main || fail 'harness: publica base'
  git checkout -qb feature/versoes
  printf 'MARCADOR-REPOSITORIO-35\n' > app.py
  case "$c" in
    1-rebase-arquivo) printf 'fim do PR\n' >> contexto.txt ;;
    1-submodulo)
      git init -q "$CW/sub"
      git -C "$CW/sub" commit -q --allow-empty -m 'test: sub inicial'
      git -c protocol.file.allow=always submodule add -q "$CW/sub" modulo
      git config diff.ignoreSubmodules all ;;
    1-binario) printf '\000um\377' > dados.bin ;;
  esac
  i35_commit 'feat: versões iniciais'
  case "$c" in
    4-externo) git config diff.external "$CB/converter35" ;;
    4-cor) git config color.ui always; git config color.diff always ;;
  esac
  if [ "${c#4-}" != "$c" ]; then
    shipcraft_pr
    chk 'revisão executa' eq "$(rev_n)" 1
    chk 'PR válido' rc_zero
    local brief; brief=$(H rev-brief "$ST")
    chk 'diff contém bytes do repositório' match 'MARCADOR-REPOSITORIO-35' "$brief"
    chk 'resumo externo não entra' nomatch 'RESUMO-OCULTO-35' "$brief"
    chk 'diff sem escapes de cor' nomatch "$(printf '\033')" "$brief"
    pass; return
  fi
  case "$c" in 5-recusa) rev_cfg changes ;; 5-erro) rev_cfg malformed ;; esac
  shipcraft_pr
  chk 'primeiro revisor executa' eq "$(rev_n)" 1
  case "$c" in
    5-recusa) chk 'recusa inicial válida' eq "$(st_state "$(head_rev)" shipcraft/review)" failure ;;
    5-erro) chk 'erro inicial' eq "$(st_state "$(head_rev)" shipcraft/review)" error ;;
    *) chk 'aprovação inicial válida' rc_zero ;;
  esac
  oldkey=$(i35_key)
  case "$c" in
    3-registro) chk 'SHA256 exato do raw NUL' i35_record "$oldkey"; pass; return ;;
    3-legado|3-maiusculo|3-curto|3-tipo)
      "$PY" - "$c" <<'PY'
import json,sys,subprocess
diff=subprocess.check_output(['git','diff','origin/main','HEAD'])
legacy=subprocess.check_output(['git','patch-id','--stable'],input=diff).decode().split()[0]
p='.git/shipcraft/runs.jsonl'; rows=[json.loads(x) for x in open(p)]
for r in rows:
 if r.get('layer')!='review': continue
 k=r.get('diff_sha256','a'*64)
 if sys.argv[1]=='3-legado':
  r.pop('diff_sha256',None); r['patch_id']=legacy
 elif sys.argv[1]=='3-maiusculo': r['diff_sha256']=k.upper()
 elif sys.argv[1]=='3-curto': r['diff_sha256']=k[:63]
 else: r['diff_sha256']=[k]
open(p,'w').writelines(json.dumps(r)+'\n' for r in rows)
PY
      i35_again; pass; return ;;
    2-*)
      # Intercepta só a inferência raw, preservando Git real no CI e no revisor.
      local realgit; realgit=$(command -v git)
      cat > "$CB/git" <<EOF_GIT
#!/bin/bash
raw=0
for a in "\$@"; do [ "\$a" != --raw ] || raw=1; done
if [ "\$raw" = 1 ]; then
  echo raw >> '$CW/raw.calls'
  case '$c' in
    2-erro) exit 7 ;;
    2-vazio) exit 0 ;;
    2-erro-com-saida) printf 'saida parcial'; exit 9 ;;
  esac
fi
exec '$realgit' "\$@"
EOF_GIT
      chmod +x "$CB/git"
      i35_again
      chk 'falha raw foi exercitada' test -s "$CW/raw.calls"
      chk 'falha não grava chave' "$PY" - <<'PY'
import json
r=[json.loads(s) for s in open('.git/shipcraft/runs.jsonl') if json.loads(s).get('layer')=='review'][-1]
assert r.get('diff_sha256') is None,r
PY
      pass; return ;;
    5-*)
      shipcraft_pr
      if [ "$c" = 5-erro ]; then
        chk 'erro não é reaproveitado' eq "$(rev_n)" 2
        chk 'erro permanece error' eq "$(st_state "$(head_rev)" shipcraft/review)" error
      else
        chk 'veredito válido reaproveitado' eq "$(rev_n)" 1
        if [ "$c" = 5-approve ]; then chk 'aprovação preservada' rc_zero
        else chk 'recusa preservada' rc_nonzero; fi
        chk 'status explica mesmas versões' match 'same file versions' "$(st_desc "$(head_rev)" shipcraft/review)"
      fi
      pass; return ;;
    1-rebase-igual|1-rebase-arquivo)
      local first; first=$(head_rev)
      git checkout -q main
      if [ "$c" = 1-rebase-igual ]; then printf 'upstream\n' > outro.txt
      else { printf 'linha nova\n'; seq 1 30; } > contexto.txt; fi
      i35_commit 'feat: avança main'
      git push -q origin main || fail 'harness: main'
      git checkout -q feature/versoes
      git rebase -q main || fail 'harness: rebase'
      if [ "$c" = 1-rebase-arquivo ]; then
        chk 'base mudou versões do arquivo do PR' ne "$oldkey" "$(i35_key)"
        i35_again
        pass; return
      fi
      chk 'rebase muda commit' ne "$first" "$(head_rev)"
      chk 'rebase mantém versões' eq "$oldkey" "$(i35_key)"
      shipcraft_pr
      chk 'rebase reaproveita' eq "$(rev_n)" 1
      chk 'status do rebase explica versões' match 'same file versions' "$(st_desc "$(head_rev)" shipcraft/review)"
      pass; return ;;
    1-conteudo) printf 'outro conteúdo\n' >> app.py ;;
    1-linha) printf '\nMARCADOR-REPOSITORIO-35\n' > app.py ;;
    1-modo) chmod +x app.py ;;
    1-binario) printf '\000dois\377' > dados.bin ;;
    1-atributo|1-textconv) printf 'conteúdo oculto diferente\n' >> app.py ;;
    1-submodulo)
      git -C "$CW/sub" commit -q --allow-empty -m 'test: segundo commit'
      git -C modulo fetch -q
      git -C modulo checkout -q FETCH_HEAD ;;
  esac
  i35_commit 'feat: muda versões'
  newkey=$(i35_key)
  chk 'fixture muda a lista de versões' ne "$oldkey" "$newkey"
  i35_again
  chk 'registro novo usa raw' i35_record "$newkey"
  pass
}
