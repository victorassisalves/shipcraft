#!/usr/bin/env bash
# Release do shipcraft na máquina de quem roda (docs/spec.md, item 21.2).
#
# usage: release/publica.sh <versão>     (1.2.0 ou v1.2.0)
#
# Roda no checkout do repositório (a pasta atual). Prende o commit no começo (o HEAD,
# igual ao main do remoto, árvore limpa, versão igual à do nucleo/Cargo.toml, tag
# ainda livre no remoto) e daí em diante tudo sai de um checkout novo desse commit:
# compila os dois alvos do macOS, roda a bateria inteira contra o alvo da máquina
# (com o reúso por árvore do acceptance/reuso.sh), empacota e cria a release com o gh.
# Não publica em brew, crates.io nem npm.
set -u

recusa() { # recusa <o que> <por quê> <como seguir>: três linhas, sai com 1
  printf 'shipcraft recusou: %s\nPor quê: %s\nComo seguir: %s\n' "$1" "$2" "$3" >&2
  exit 1
}

[ $# -eq 1 ] || recusa "uso: release/publica.sh <versão>" \
  "a release é de uma versão só, dita uma vez" "rode com a versão, por exemplo 1.2.0 ou v1.2.0"
VERSAO="${1#v}"
printf '%s\n' "$VERSAO" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || recusa \
  "a versão '$1' não tem a forma X.Y.Z ou vX.Y.Z" \
  "a versão do shipcraft é sempre X.Y.Z numérico, sem sufixo de pré-release" \
  "rode com a versão do nucleo/Cargo.toml, por exemplo 1.2.0"
TAG="v$VERSAO"

[ "$(uname -s)" = Darwin ] || recusa "a release só sai de um macOS" \
  "os pacotes são dos dois alvos do macOS, e a bateria roda contra o alvo da máquina" \
  "rode num Mac"
for tool in git gh cargo shasum tar; do
  command -v "$tool" >/dev/null 2>&1 || recusa "falta o $tool no PATH" \
    "a release compila, empacota e publica com ele" "instale o $tool e rode de novo"
done

# ---------------------------------------------------------------- o commit preso
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || recusa "a pasta atual não é um repositório git" \
  "a release sai do commit do checkout de quem roda" "rode na raiz do checkout do shipcraft-v2"
cd "$ROOT" || exit 2
SHA=$(git rev-parse --verify HEAD 2>/dev/null) || recusa "o repositório não tem HEAD" \
  "a release sai de um commit" "rode num checkout do main"

REMOTO=$(git ls-remote origin main 2>/dev/null) || recusa \
  "não consegui consultar o main do remoto (git ls-remote origin main)" \
  "sem o remoto não dá para saber se o HEAD é o main publicado" \
  "confira a rede e o acesso ao origin e rode de novo"
REMOTO=$(printf '%s\n' "$REMOTO" | awk '$2 == "refs/heads/main" { print $1 }')
[ -n "$REMOTO" ] || recusa "o remoto não tem main" \
  "a release sai do main do remoto" "confira o origin e rode de novo"
[ "$SHA" = "$REMOTO" ] || recusa "o HEAD ($SHA) não é o main do remoto ($REMOTO)" \
  "a release sai só do main publicado, o que todo mundo pode conferir" \
  "faça git switch main e git pull --ff-only, e rode de novo"
[ -z "$(git status --porcelain --untracked-files=all)" ] || recusa "a árvore não está limpa" \
  "o commit preso tem de ser o que está na pasta, sem alteração por cima" \
  "commite ou descarte o que mudou (git status) e rode de novo"
CARGO_VERSAO=$(git show "$SHA:nucleo/Cargo.toml" 2>/dev/null | awk '
  /^\[/ { pkg = ($0 == "[package]") }
  pkg && /^version[ \t]*=/ { sub(/^[^"]*"/, ""); sub(/".*$/, ""); print; exit }')
[ "$CARGO_VERSAO" = "$VERSAO" ] || recusa \
  "a versão pedida ($VERSAO) não é a do nucleo/Cargo.toml (${CARGO_VERSAO:-nenhuma})" \
  "o shipcraft --version da release tem de dizer a versão da tag" \
  "suba a versão no nucleo/Cargo.toml num PR, ou rode com $CARGO_VERSAO"
TAGS=$(git ls-remote --tags origin "refs/tags/$TAG" 2>/dev/null) || recusa \
  "não consegui consultar as tags do remoto (git ls-remote --tags origin)" \
  "sem o remoto não dá para saber se a $TAG já existe" \
  "confira a rede e o acesso ao origin e rode de novo"
[ -z "$TAGS" ] || recusa "a tag $TAG já existe no remoto" \
  "uma versão publicada não muda" "suba a versão no nucleo/Cargo.toml e rode com a nova"
echo "publica.sh: $TAG do commit $SHA"

# ---------------------------------------------------------------- o checkout novo
TMPROOT="${TMPDIR:-/tmp}"; TMPROOT="${TMPROOT%/}"
WORK=$(mktemp -d "$TMPROOT/shipcraft-publica.XXXXXX") || { echo "publica.sh: mktemp falhou" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
SRC="$WORK/src"
{ git clone -q --no-checkout "$ROOT" "$SRC" && git -C "$SRC" checkout -q --detach "$SHA"; } \
  || recusa "não consegui fazer o checkout novo de $SHA" \
    "a release sai de um checkout próprio, que o checkout de quem roda não muda" \
    "confira o espaço em $TMPROOT e rode de novo"

if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
  ALVO=aarch64-apple-darwin; OUTRO=x86_64-apple-darwin
else
  ALVO=x86_64-apple-darwin; OUTRO=aarch64-apple-darwin
fi

# ---------------------------------------------------------------- compila e testa
export CARGO_TARGET_DIR="$SRC/nucleo/target"
for alvo in aarch64-apple-darwin x86_64-apple-darwin; do
  (cd "$SRC/nucleo" && nice -n 10 cargo build --release --locked -j 4 --target "$alvo") \
    && [ -x "$CARGO_TARGET_DIR/$alvo/release/shipcraft" ] \
    || recusa "a compilação para $alvo falhou" \
      "a release leva os dois alvos do macOS" \
      "instale o alvo (rustup target add $alvo), confira o build e rode de novo"
done
BIN="$CARGO_TARGET_DIR/$ALVO/release/shipcraft"

BATERIA=""
if [ -f "$SRC/acceptance/reuso.sh" ]; then
  . "$SRC/acceptance/reuso.sh"
  BATERIA=$(acceptance_cached_result "$SRC" HEAD) || BATERIA=""
fi
if [ -n "$BATERIA" ]; then
  echo "publica.sh: bateria reusada pela árvore: $BATERIA"
else
  (cd "$SRC" && nice -n 10 bash acceptance/run.sh "$BIN" all) || recusa \
    "a bateria inteira ficou vermelha contra o $ALVO" \
    "a release só sai de um commit com a bateria verde" \
    "corrija no main por um PR e rode de novo; nada foi publicado"
  BATERIA="verde nesta execução"
fi

# ---------------------------------------------------------------- empacota
OUT="$WORK/out"; mkdir -p "$OUT"
for alvo in aarch64-apple-darwin x86_64-apple-darwin; do
  mkdir -p "$WORK/pkg/$alvo" && cp "$CARGO_TARGET_DIR/$alvo/release/shipcraft" "$WORK/pkg/$alvo/shipcraft" \
    && chmod 755 "$WORK/pkg/$alvo/shipcraft" \
    && COPYFILE_DISABLE=1 tar -czf "$OUT/shipcraft-$VERSAO-$alvo.tar.gz" -C "$WORK/pkg/$alvo" shipcraft \
    || recusa "não consegui empacotar o $alvo" "a release leva um pacote por alvo" \
      "confira o espaço em $TMPROOT e rode de novo; nada foi publicado"
done
(cd "$OUT" && shasum -a 256 "shipcraft-$VERSAO-aarch64-apple-darwin.tar.gz" \
  "shipcraft-$VERSAO-x86_64-apple-darwin.tar.gz" > SHA256SUMS) \
  || recusa "não consegui escrever o SHA256SUMS" "quem instala confere a soma do pacote" \
    "rode de novo; nada foi publicado"
cat > "$WORK/notas.md" <<EOF
shipcraft $VERSAO, do commit $SHA.

A bateria inteira (acceptance/run.sh all) rodou contra o $ALVO: $BATERIA.
O $OUTRO foi só compilado: não rodou a bateria (limite aceito, item 21.2).

Instalar: rode o \`instalar.sh\` da raiz do repositório (precisa do gh logado).
EOF

# ---------------------------------------------------------------- publica
# O gh release create cria a tag no commit preso e a release com os pacotes. Se ele
# falha depois de devolver o endereço, a release é desta execução e é apagada; sem
# o endereço, a resposta pode ter se perdido, e nada é apagado.
URL=$(gh release create "$TAG" --target "$SHA" --title "$TAG" --notes-file "$WORK/notas.md" \
  "$OUT/shipcraft-$VERSAO-aarch64-apple-darwin.tar.gz" "$OUT/shipcraft-$VERSAO-x86_64-apple-darwin.tar.gz" \
  "$OUT/SHA256SUMS")
CRIOU=$?
if [ "$CRIOU" -ne 0 ]; then
  case "$URL" in
    *"/releases/tag/$TAG"*)
      gh release delete "$TAG" --yes --cleanup-tag >/dev/null 2>&1 && recusa \
        "o gh release create falhou depois de criar a $TAG; apaguei a release e a tag que criei" \
        "uma release pela metade instalaria pacotes que não conferem" "corrija e rode de novo"
      recusa "o gh release create falhou depois de criar a $TAG, e não consegui apagá-la" \
        "uma release pela metade instalaria pacotes que não conferem" \
        "apague com gh release delete $TAG --yes --cleanup-tag e rode de novo"
      ;;
  esac
  printf 'shipcraft recusou: o gh release create falhou e não devolveu a release\nPor quê: a resposta pode ter se perdido com a release criada, e apagar às cegas pode apagar a de outro\nComo seguir: antes de rodar de novo, vá conferir gh release view %s e git ls-remote --tags origin %s; apague com gh release delete %s --cleanup-tag se ficou pela metade\n' "$TAG" "$TAG" "$TAG" >&2
  exit 1
fi
echo "publica.sh: $TAG publicada no commit $SHA: $URL"
