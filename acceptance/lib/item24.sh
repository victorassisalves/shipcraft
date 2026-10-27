# Item 24: shape warning; fixtures and oracles only through public interfaces.
item24_cases() {
  i24_atrib_cases
  for c in comum limite ja-grande novo p90 p90-21 populacao pequena pequena-19 config-base config-ponta config-hex config-comentario wc-sem-final wc-crlf lfs renome teste-produto sem-renome categorias ordem corte nomes nomes-sem-quote json-zero json-null sem-registro status status-recusa blob-ausente glob-estrela glob-dupla glob-meio glob-interrogacao; do echo "v1-24.$c"; done
  for c in zero negativo texto bool fracao lista; do echo "v1-24.invalido-$c"; done
}
i24_write() { sz_gen "$1" "$2" "${3:-x}"; }
i24_summary() { H writes "$ST" comment,pr-edit,pr-create > "$CW/writes"; }
i24_line() {
  "$PY" - "$1" "$2" <<'PY'
import sys,os
# The stub records the published text; h.py provides the same flow through writes.
s=open(sys.argv[1]).read().split('=====')[-1] if os.path.isfile(sys.argv[1]) else ''
assert sys.argv[2] in s, 'literal line missing: '+sys.argv[2]+'\n'+s
PY
}
i24_has() { i24_summary; i24_line "$CW/writes" "$1"; }
i24_none() { i24_summary; ! grep -q 'Shape:' "$CW/writes"; }
i24_json() {
  "$PY" - "$HEAD" "$1" <<'PY'
import json,sys
rows=[json.loads(x) for x in open('.git/shipcraft/runs.jsonl')]
# Item 38 also records PR/RED/close events; shape's row count concerns CI/review.
rows=[r for r in rows if r.get('commit')==sys.argv[1] and r.get('layer') in ('ci','review')]
expected=json.loads(sys.argv[2])
for layer in ('ci','review'):
 rs=[r for r in rows if r.get('layer')==layer]
 assert len(rs)==1,(layer,rs)
 assert 'shape_warnings' in rs[0] and rs[0]['shape_warnings']==expected,rs
 assert type(rs[0]['shape_warnings']) is type(expected),rs
assert len(rows)==2,rows
PY
}
i24_warn() {
  local linha="Shape: \`$1\` exceeded $N lines ($2 -> $3); consider splitting."
  chk 'literal warning in the summary' i24_has "$linha"
  chk 'one warning per file' "$PY" - "$CW/writes" "$linha" <<'PYONCE'
import sys
s=open(sys.argv[1]).read().split('=====')[-1]
assert s.splitlines().count(sys.argv[2])==1,s
PYONCE
}
item24_case() {
  local c="${CASE#v1-24.}" f i v
  case "$c" in atributo-*) i24_atrib_case "$c"; return ;; esac
  EXPECT="item 24 shape warning: $c"
  N=10
  CFGS='pr|shape_lines|10'
  case "$c" in p90|p90-21|populacao|blob-ausente|pequena|pequena-19|json-null) CFGS='' ;; esac
  case "$c" in config-hex) CFGS='pr|shape_lines|0x0a' ;; config-comentario) CFGS='pr|shape_lines|10 # limite' ;; sem-registro) CFGS='pr|shape_lines|10
execution|ci|"off"
execution|review|"off"' ;; esac
  case "$c" in
    glob-estrela) CFGS="$CFGS
-|test_globs|[\"custom/*.py\"]" ;;
    glob-dupla) CFGS="$CFGS
-|test_globs|[\"custom/**/*.py\"]" ;;
    glob-meio) CFGS="$CFGS
-|test_globs|[\"custom/*/apoio.py\"]" ;;
    glob-interrogacao) CFGS="$CFGS
-|test_globs|[\"custom/apoio?.py\"]" ;;
  esac
  # Invalid configs are first published valid; the contract is exercised in the PR.
  sz_start
  if [ "$c" = blob-ausente ]; then
    git config maintenance.auto false
    git config gc.auto 0
  fi
  i24_write modulo.py 10 a
  case "$c" in
    p90|p90-21|pequena-19)
      "$PY" - "$c" <<'P90'
import subprocess,os,sys,fnmatch
try: import tomllib
except ImportError: import tomli as tomllib
globs=tomllib.load(open('.shipcraft.toml','rb'))['test_globs']
def produto(p):
 return p and not any(fnmatch.fnmatchcase(p,g) for g in globs)
paths=subprocess.check_output(['git','ls-files','-z']).decode().split('\0')
base=[p for p in paths if produto(p)]
# modulo.py is not added yet.
base=list(set(base+['modulo.py']))
n={'p90':20,'p90-21':21,'pequena-19':19}[sys.argv[1]]
for i in range(n-len(base)):
 os.makedirs('produto',exist_ok=True)
 open(f'produto/posto{i}.py','w').write('x\n'*(20+i))
P90
      ;;
    populacao|blob-ausente)
      for f in tests/test_gigante.py tests/helpers/apoio.py nested/Cargo.lock; do i24_write "$f" 3000 z; done
      "$PY" -c 'open("grande.bin","wb").write(b"\0"+b"x\n"*4000)'
      for i in $(seq 1 30); do i24_write "tests/test_excluido$i.py" 3000 "e$i"; done
      # Two hundred eleven files: rank ceil(.9*n), without interpolation, lands in the block of 10.
      for i in $(seq 1 200); do i24_write "produto/p$i.py" 10 "p$i"; done
      for i in $(seq 1 11); do i24_write "produto/grande$i.py" 1000 "g$i"; done
      ;;
    ja-grande) i24_write modulo.py 11 a ;;
    renome|teste-produto) i24_write modulo.py 10 a; [ "$c" != teste-produto ] || mv modulo.py tests/test_anterior.py ;;
    wc-sem-final) printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nsem-final' > modulo.py ;;
    lfs) printf 'version https://git-lfs.github.com/spec/v1\noid sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nsize 99999999\n' > modulo.py; N=3; H toml-set .shipcraft.toml pr shape_lines 3 ;;
  esac
  if [ "$c" = blob-ausente ]; then printf 'medida somente da população\nsegunda linha exclusiva\n' > ausente.txt; fi
  sz_main_commit 'chore: população de forma'
  if [ "$c" = p90 ] || [ "$c" = p90-21 ]; then
    N=$("$PY" - "$c" <<'P90'
import subprocess,math,sys,fnmatch
try: import tomllib
except ImportError: import tomli as tomllib
globs=tomllib.load(open('.shipcraft.toml','rb'))['test_globs']
def produto(p):
 return p and not any(fnmatch.fnmatchcase(p,g) for g in globs)
paths=subprocess.check_output(['git','ls-tree','-rz','--name-only','HEAD']).decode().split('\0')
sizes=[subprocess.check_output(['git','show','HEAD:'+p]).count(b'\n') for p in paths if produto(p)]
assert len(sizes)==(20 if sys.argv[1]=='p90' else 21),sizes
print(sorted(sizes)[math.ceil(.9*len(sizes))-1])
P90
)
  fi
  sz_branch
  i24_write modulo.py "$((N+1))" a
  case "$c" in
    limite|json-zero) i24_write modulo.py 10 b ;;
    ja-grande) i24_write modulo.py 12 a ;;
    novo) i24_write novo.py 11 b ;;
    pequena|pequena-19|json-null) i24_write modulo.py 1000 a ;;
    config-base) H toml-set .shipcraft.toml pr shape_lines 1000 ;;
    config-ponta)
      git checkout -q main; H toml-set .shipcraft.toml pr shape_lines 12
      sz_main_commit 'chore: limite na ponta base'; git checkout -q "$BR"; N=12; i24_write modulo.py 13 a ;;
    wc-sem-final) printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nsem-final\n' > modulo.py ;;
    wc-crlf) "$PY" -c 'open("modulo.py","wb").write(b"x\r\n"*11+b"resto\r")' ;;
    lfs) printf 'version https://git-lfs.github.com/spec/v1\noid sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\nsize 99999999\nextra\n' > modulo.py ;;
    renome) git mv modulo.py destino.py; i24_write destino.py 11 a ;;
    teste-produto) rm modulo.py; git mv tests/test_anterior.py modulo.py; i24_write modulo.py 11 a ;;
    sem-renome) git restore modulo.py; git rm -q modulo.py; i24_write outro.py 11 z ;;
    categorias)
      for f in tests/test_fora.py tests/fora_test.py tests/conftest.py tests/helpers/apoio.py tests/fixtures/a.txt Cargo.lock package-lock.json pnpm-lock.yaml yarn.lock go.sum poetry.lock uv.lock nested/Cargo.lock; do i24_write "$f" 100 f; done
      "$PY" -c 'open("binario.dat","wb").write(b"\0"+b"x\n"*100)'
      i24_write Gemfile.lock 11 g ;;
    ordem|corte)
      i24_write modulo.py 10 b
      if [ "$c" = ordem ]; then
        for i in 5 4 3 2 1; do i24_write "novo0$i.py" 11 n; done
      else
        for i in $(seq 1 12); do i24_write "novo$(printf '%02d' "$i").py" "$((30-i))" n; done
      fi ;;
    nomes|nomes-sem-quote)
      [ "$c" != nomes-sem-quote ] || git config core.quotePath false
      "$PY" - "$c" <<'PY'
import sys
paths=['aspas".py','quebra\nlinha.py','ação.py','com espaço.py']
if sys.argv[1]=='nomes': paths.append('crase`.py')
else: paths.append('barra\\invertida.py')
for p in paths:
 open(p,'w').write('x\n'*11)
PY
      ;;
    glob-estrela) i24_write custom/apoio.py 100 k; i24_write custom/sub/produto.py 11 p ;;
    glob-dupla) i24_write custom/sub/apoio.py 100 k; i24_write custom/sub/sub2/outro.py 100 k ;;
    glob-meio) i24_write custom/sub/apoio.py 100 k; i24_write custom/sub/produto.py 11 p ;;
    glob-interrogacao) i24_write custom/apoio1.py 100 k; i24_write custom/apoio12.py 11 p ;;
    status) : ;;
    invalido-*)
      case "$c" in *zero) v=0 ;; *negativo) v=-1 ;; *texto) v='"10"' ;; *bool) v=true ;; *fracao) v=1.5 ;; *lista) v='[10]' ;; esac
      # Update the base without running the hook so that shipcraft pr sees the error.
      git checkout -q main; H toml-set .shipcraft.toml pr shape_lines "$v"
      git -c core.hooksPath=/dev/null add .shipcraft.toml
      git -c core.hooksPath=/dev/null commit -qm 'chore: configuração inválida intencional'
      git push -q origin main; git fetch -q origin; git checkout -q "$BR" ;;
  esac
  sz_commit 'feat: cruza o tamanho normal'
  if [ "$c" = blob-ausente ]; then
    # Loose object of a product file the suite does not use; no commits/trees destroyed.
    git -c maintenance.auto=false -c gc.auto=0 push -q origin "$BR"
    f=$(git rev-parse HEAD:ausente.txt)
    rm "$(git rev-parse --git-path objects)/${f:0:2}/${f:2}"
    git config core.repositoryformatversion 1
    git config extensions.partialClone origin
    git config remote.origin.promisor true
    if GIT_NO_LAZY_FETCH=1 git cat-file -e "$f" 2>/dev/null; then
      fail 'harness: the blob is still readable before shipcraft pr'
    fi
  fi
  case "$c" in
    invalido-*) shipcraft_pr; chk 'invalid config refuses' test "$RC" -ne 0; chk 'three-line refusal' last3_has '(config|shape_lines|integer|positive)'; pass; return ;;
  esac
  if [ "$c" = status ] || [ "$c" = status-recusa ]; then
    [ "$c" != status-recusa ] || rev_cfg changes
    i24_write modulo.py 10 b; sz_commit 'chore: controle sem aviso'
    shipcraft_pr; local rc_controle="$RC"; HEAD=$(git rev-parse HEAD)
    local ci_controle rev_controle
    ci_controle=$(st_state "$HEAD" shipcraft/ci); rev_controle=$(st_state "$HEAD" shipcraft/review)
    i24_write modulo.py 11 a; sz_commit 'feat: aviso no mesmo controle'
  fi
  if [ "$c" = sem-registro ]; then
    if [ -f .git/shipcraft/runs.jsonl ]; then
      cp .git/shipcraft/runs.jsonl "$CW/metrics-before"
    else
      : > "$CW/metrics-before"
    fi
  fi
  if [ "$c" = status-recusa ]; then shipcraft_pr; HEAD=$(git rev-parse HEAD); else sz_pr; fi
  case "$c" in
    limite|ja-grande|pequena|pequena-19|json-null) chk 'no crossing or no N, no warning' i24_none; chk 'explicit measurement' i24_json "$([ "$c" = pequena ] || [ "$c" = pequena-19 ] || [ "$c" = json-null ] && echo null || echo 0)" ;;
    json-zero) chk 'explicit zero' i24_json 0 ;;
    novo) i24_warn novo.py new 11 ;;
    sem-renome) i24_warn outro.py new 11 ;;
    renome) i24_warn destino.py 10 11 ;;
    lfs) i24_warn modulo.py 3 4 ;;
    wc-sem-final|wc-crlf) i24_warn modulo.py 10 11 ;;
    ordem|corte)
      i24_summary
      chk 'order, cutoff and total count' "$PY" - "$CW/writes" "$c" <<'PY'
import sys
s=open(sys.argv[1]).read().split('=====')[-1]; lines=[x.strip() for x in s.splitlines() if x.strip().startswith('Shape:')]
want=[f'Shape: `novo{i:02}.py` exceeded 10 lines (new -> {11 if sys.argv[2]=="ordem" else 30-i}); consider splitting.' for i in range(1,6)]
assert lines==want,(lines,want)
assert ('and 7 more files' in s) if sys.argv[2]=='corte' else ('and ' not in s),s
PY
      chk 'total without cutoff' i24_json "$([ "$c" = ordem ] && echo 5 || echo 12)" ;;
    nomes|nomes-sem-quote)
      i24_summary
      chk 'path quoting and tie-break by bytes' "$PY" - "$CW/writes" "$c" <<'PY'
import sys,subprocess
s=open(sys.argv[1]).read(); paths=['aspas".py','quebra\nlinha.py','ação.py','com espaço.py']
if sys.argv[2]=='nomes': paths.append('crase`.py')
else: paths.append('barra\\invertida.py')
# Use git as the quoting oracle; never split raw names on newline.
expected=[]
for p in sorted(paths,key=lambda x:x.encode()):
 q=subprocess.check_output(['git','--literal-pathspecs','-c','core.quotePath=true','ls-files','--',p]).decode().rstrip('\n')
 assert q,('git did not find the literal path',p)
 expected.append(f'Shape: `{q}` exceeded 10 lines (new -> 11); consider splitting.')
positions=[s.find(x) for x in expected]
assert all(x>=0 for x in positions) and positions==sorted(positions),(expected,s)
PY
      ;;
    sem-registro)
      i24_warn modulo.py 10 11
      chk 'off layers add only the PR event, without rewriting history' "$PY" - "$CW/metrics-before" <<'METRICS24'
import json,sys
from pathlib import Path
before=Path(sys.argv[1]).read_bytes()
after=Path('.git/shipcraft/runs.jsonl').read_bytes()
assert after.startswith(before), 'PR rewrote the metrics'
rows=[json.loads(line) for line in after[len(before):].splitlines() if line.strip()]
assert len(rows)==1 and rows[0]['layer']=='pr' and rows[0]['result']=='passed', rows
assert rows[0]['lock']=='' and rows[0]['locks']==[], rows
METRICS24
      ;;
    blob-ausente)
      chk 'measurement failure visible' i24_has 'Shape: unmeasured ('
      chk 'non-empty reason and punctuation' "$PY" - "$CW/writes" <<'WHY'
import re,sys
s=open(sys.argv[1]).read().split('=====')[-1]
assert re.search(r'^Shape: unmeasured \([^\n]+\)\.$',s,re.M),s
assert not re.search(r'^Shape: .*exceeded',s,re.M),s
WHY
      chk 'no lazy fetch' test ! -e "$(git rev-parse --git-path objects)/${f:0:2}/${f:2}"
      chk 'null without measurement' i24_json null ;;
    categorias) i24_warn modulo.py 10 11; i24_warn Gemfile.lock new 11; chk 'only two product files' i24_json 2 ;;
    status|status-recusa)
      chk "same exit code" eq "$RC" "$rc_controle"
      chk "same ci" eq "$(st_state "$HEAD" shipcraft/ci)" "$ci_controle"
      chk "same review" eq "$(st_state "$HEAD" shipcraft/review)" "$rev_controle"
      i24_warn modulo.py 10 11
      ;;
    glob-estrela|glob-meio|glob-interrogacao)
      i24_warn modulo.py 10 11; chk 'glob excludes only matching paths' i24_json 2 ;;
    config-ponta) i24_warn modulo.py 10 13; chk "count" i24_json 1 ;;
    *) i24_warn modulo.py 10 "$((N+1))"; chk 'integer count' i24_json 1 ;;
  esac
  pass
}

# Review #87: binary by Git's classification, without any NUL byte.
i24_atrib_cases() {
  local a m
  for a in binary menos-diff driver-binario; do
    for m in candidato populacao; do echo "v1-24.atributo-$a-$m"; done
  done
  echo v1-24.atributo-binary-minimo
  echo v1-24.atributo-sem-atributo v1-24.atributo-driver-texto v1-24.atributo-driver-automatico
}
i24_atrib_case() {
  local c="$1" attr='' modo=candidato i
  EXPECT="binary by Git attribute: $c"
  N=10; CFGS='pr|shape_lines|10'
  case "$c" in *-populacao) modo=populacao; CFGS='' ;; *-minimo) modo=minimo; CFGS='' ;; esac
  sz_start
  case "$c" in
    atributo-binary-*) attr=binary ;;
    atributo-menos-diff-*) attr=-diff ;;
    atributo-driver-binario-*) attr=diff=forca; git config diff.forca.binary true ;;
    atributo-driver-texto) attr=diff=texto; git config diff.texto.binary false ;;
    atributo-driver-automatico) attr=diff=automatico ;;
  esac
  if [ -n "$attr" ]; then printf '*.dat %s\n' "$attr" > .gitattributes
  else printf '# nenhum atributo para asset.dat\n' > .gitattributes; fi
  if [ "$modo" = candidato ]; then
    i24_write asset.dat 10 a
  else
    i24_write normal.py 10 p
    for i in $(seq 1 40); do i24_write "assets/asset$i.dat" 1000 b; done
    if [ "$modo" = populacao ]; then
      for i in $(seq 1 40); do i24_write "produto/p$i.py" 10 p; done
    fi
  fi
  sz_main_commit 'chore: atributos Git e população de forma'
  BASE=$(git rev-parse HEAD)
  if [ "$modo" != candidato ]; then
    chk 'native population excludes dat without NUL' "$PY" - "$modo" <<'POPATTR'
import subprocess,sys,fnmatch,math
try: import tomllib
except ImportError: import tomli as tomllib
cfg=tomllib.load(open('.shipcraft.toml','rb')); globs=cfg['test_globs']
empty=subprocess.check_output(['git','hash-object','-w','-t','tree','--stdin'],input=b'').decode().strip()
rows=subprocess.check_output(['git','diff','--numstat','-z',empty,'HEAD']).split(b'\0')
sizes=[]; binary=0
for row in rows:
 if not row: continue
 a,r,path=row.decode().split('\t',2)
 if a==r=='-':
  assert path.endswith('.dat'),path
  assert b'\0' not in subprocess.check_output(['git','show','HEAD:'+path])
  binary+=1; continue
 if not any(fnmatch.fnmatchcase(path,g) for g in globs):
  sizes.append(subprocess.check_output(['git','show','HEAD:'+path]).count(b'\n'))
assert binary==40,binary
if sys.argv[1]=='minimo': assert len(sizes)<20,sizes
else:
 assert len(sizes)>=20,sizes
 assert sorted(sizes)[math.ceil(.9*len(sizes))-1]==10,sizes
POPATTR
  fi
  sz_branch
  if [ "$modo" = candidato ]; then i24_write asset.dat 11 a
  else i24_write normal.py 11 p; fi
  sz_commit 'feat: cresce um arquivo sem NUL'
  chk 'numstat confirms the candidate classification' "$PY" - "$modo" "$c" "$BASE" <<'NUMATTR'
import subprocess,sys
mode,case,base=sys.argv[1:]
path='asset.dat' if mode=='candidato' else 'normal.py'
raw=subprocess.check_output(['git','diff','--numstat',base,'HEAD','--',path],text=True).strip()
fields=raw.split('\t')
textual=mode!='candidato' or case in ('atributo-sem-atributo','atributo-driver-texto','atributo-driver-automatico')
assert fields==(['1','0',path] if textual else ['-','-',path]),raw
NUMATTR
  sz_pr
  case "$modo/$c" in
    candidato/atributo-sem-atributo|candidato/atributo-driver-texto|candidato/atributo-driver-automatico)
      chk 'item11 counts the text' sz_size 1 0
      i24_warn asset.dat 10 11; chk 'one warning' i24_json 1 ;;
    candidato/*)
      chk 'item11 excludes the binary' sz_size 0 0
      chk 'binary does not warn' i24_none; chk 'zero warnings' i24_json 0 ;;
    populacao/*)
      chk 'item11 counts only normal.py' sz_size 1 0
      i24_warn normal.py 10 11; chk 'N not inflated by the dat files' i24_json 1 ;;
    minimo/*)
      chk 'item11 counts only normal.py' sz_size 1 0
      chk 'no N, no warning' i24_none; chk 'real population below 20' i24_json null ;;
  esac
  pass
}
