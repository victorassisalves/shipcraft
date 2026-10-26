#!/usr/bin/env bash
# Instala, atualiza e remove o shipcraft (docs/spec.md, item 21.3).
#
# usage: instalar.sh [--versao <v>] | instalar.sh --remover
#
# Baixa a release de victorassisalves/shipcraft-v2 (ou de SHIPCRAFT_REPO) com o gh, que
# precisa estar logado (o repositório é privado), e põe o binário em
# ${SHIPCRAFT_BIN:-$HOME/.local/bin}/shipcraft. Qualquer falha antes da troca deixa o binário
# anterior como estava.
set -u

recusa() { # recusa <o que> <por quê> <como seguir>: três linhas, sai com 1
  printf 'shipcraft recusou: %s\nPor quê: %s\nComo seguir: %s\n' "$1" "$2" "$3" >&2
  exit 1
}
USO="uso: instalar.sh [--versao <v>] | instalar.sh --remover"

REPO="${SHIPCRAFT_REPO:-victorassisalves/shipcraft-v2}"
DEST="${SHIPCRAFT_BIN:-$HOME/.local/bin}"
ALVO_BIN="$DEST/shipcraft"

VERSAO=""
case "$*" in
  "") ;;
  --remover)
    if [ -e "$ALVO_BIN" ] || [ -L "$ALVO_BIN" ]; then
      rm -f "$ALVO_BIN" || recusa "não consegui apagar $ALVO_BIN" "o binário continua lá" \
        "confira a permissão da pasta $DEST e rode de novo"
      echo "instalar.sh: removi $ALVO_BIN; os projetos com o shipcraft integrado vão recusar o commit até ele voltar ou a integração sair."
    else
      echo "instalar.sh: não há $ALVO_BIN; os projetos com o shipcraft integrado vão recusar o commit até ele voltar ou a integração sair."
    fi
    exit 0
    ;;
  *)
    [ $# -eq 2 ] && [ "$1" = --versao ] || recusa "argumentos inválidos: $*" \
      "o instalar.sh instala uma versão ou remove o binário" "$USO"
    VERSAO="${2#v}"
    printf '%s\n' "$VERSAO" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || recusa \
      "a versão '$2' não tem a forma X.Y.Z ou vX.Y.Z" \
      "as releases do shipcraft são vX.Y.Z" "rode com --versao 1.2.0, ou sem --versao para a última"
    ;;
esac

[ "$(uname -s)" = Darwin ] || recusa "não há pacote do shipcraft para $(uname -s)" \
  "as releases só trazem os alvos do macOS" "compile com cargo install --path nucleo"
for tool in gh shasum tar; do
  command -v "$tool" >/dev/null 2>&1 || recusa "falta o $tool no PATH" \
    "o instalar.sh baixa e confere a release com ele" "instale o $tool e rode de novo"
done

# A versão é resolvida uma vez; tudo sai dessa tag.
if [ -z "$VERSAO" ]; then
  TAG=$(gh release view --repo "$REPO" --json tagName --jq .tagName 2>/dev/null) || recusa \
    "não consegui ver a última release de $REPO" \
    "o repositório é privado: o gh precisa estar logado com acesso a ele" \
    "rode gh auth login (ou confira SHIPCRAFT_REPO) e rode de novo"
  VERSAO="${TAG#v}"
  printf '%s\n' "$VERSAO" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || recusa \
    "a última release de $REPO tem a tag '$TAG', que não é vX.Y.Z" \
    "o instalar.sh só instala versões X.Y.Z" "rode com --versao <v>"
fi
TAG="v$VERSAO"

if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
  ALVO=aarch64-apple-darwin
else
  ALVO=x86_64-apple-darwin
fi
PACOTE="shipcraft-$VERSAO-$ALVO.tar.gz"

TMPROOT="${TMPDIR:-/tmp}"; TMPROOT="${TMPROOT%/}"
WORK=$(mktemp -d "$TMPROOT/shipcraft-instalar.XXXXXX") || recusa "não consegui criar a pasta temporária" \
  "o pacote é conferido antes de chegar perto do binário instalado" \
  "confira o espaço e a permissão em $TMPROOT e rode de novo"
NOVO=""
trap 'rm -rf "$WORK"; [ -z "$NOVO" ] || rm -f "$NOVO"' EXIT
trap 'exit 130' INT TERM

gh release download "$TAG" --repo "$REPO" --pattern "$PACOTE" --pattern SHA256SUMS --dir "$WORK" \
  >/dev/null 2>&1 && [ -f "$WORK/$PACOTE" ] && [ -f "$WORK/SHA256SUMS" ] || recusa \
  "não consegui baixar $PACOTE e SHA256SUMS da release $TAG de $REPO" \
  "o repositório é privado (o gh precisa estar logado) e a release precisa ter o pacote deste alvo" \
  "rode gh auth login, confira gh release view $TAG --repo $REPO, e rode de novo"

LINHAS=$(awk -v p="$PACOTE" '$2 == p || $2 == "*" p' "$WORK/SHA256SUMS")
N=$(printf '%s' "$LINHAS" | grep -c . || true)
[ "$N" = 1 ] || recusa "o SHA256SUMS da $TAG tem $N linhas para $PACOTE, e precisa de exatamente uma" \
  "sem uma soma só não dá para conferir o pacote" "confira a release $TAG; o binário anterior ficou como estava"
(cd "$WORK" && printf '%s\n' "$LINHAS" | shasum -a 256 -c - >/dev/null 2>&1) || recusa \
  "a soma de $PACOTE não confere com o SHA256SUMS da $TAG" \
  "o pacote pode estar corrompido ou trocado" "rode de novo; se repetir, confira a release $TAG"

mkdir "$WORK/x" && tar -xzf "$WORK/$PACOTE" -C "$WORK/x" 2>/dev/null || recusa \
  "não consegui extrair $PACOTE" "o pacote pode estar corrompido" \
  "confira o espaço em $TMPROOT e a release $TAG, e rode de novo"
CONTEUDO=$(ls -A "$WORK/x")
[ "$CONTEUDO" = shipcraft ] && [ -f "$WORK/x/shipcraft" ] && [ ! -L "$WORK/x/shipcraft" ] && [ -x "$WORK/x/shipcraft" ] || recusa \
  "$PACOTE não traz só um shipcraft executável na raiz" \
  "o pacote da release é um único arquivo, shipcraft, executável" "confira a release $TAG; o binário anterior ficou como estava"
DIZ=$("$WORK/x/shipcraft" --version 2>/dev/null)
case "$DIZ" in
  "shipcraft $VERSAO ("*")") ;;
  *) recusa "o shipcraft de $PACOTE diz '$DIZ', e não a versão $VERSAO" \
    "o binário instalado tem de ser o da versão pedida" "confira a release $TAG; o binário anterior ficou como estava" ;;
esac

if [ -e "$ALVO_BIN" ] || [ -L "$ALVO_BIN" ]; then
  [ -f "$ALVO_BIN" ] && [ ! -L "$ALVO_BIN" ] || recusa "$ALVO_BIN existe e não é um arquivo" \
    "a troca só substitui um binário, nunca uma pasta ou um link" \
    "confira o que está em $ALVO_BIN, ou use SHIPCRAFT_BIN=<pasta>, e rode de novo"
fi
SOMA=$(shasum -a 256 "$WORK/x/shipcraft" | awk '{ print $1 }')
if [ -f "$ALVO_BIN" ] && [ "$(shasum -a 256 "$ALVO_BIN" 2>/dev/null | awk '{ print $1 }')" = "$SOMA" ]; then
  echo "instalar.sh: o shipcraft $VERSAO já está em $ALVO_BIN"
  exit 0
fi

# A troca: uma cópia na mesma pasta e uma renomeação atômica por cima do anterior.
mkdir -p "$DEST" 2>/dev/null || recusa "não consegui criar a pasta $DEST" \
  "o shipcraft vai em \${SHIPCRAFT_BIN:-\$HOME/.local/bin}" "confira a permissão ou use SHIPCRAFT_BIN=<pasta>, e rode de novo"
NOVO="$DEST/.shipcraft.novo.$$"
{ cp "$WORK/x/shipcraft" "$NOVO" && chmod 755 "$NOVO"; } 2>/dev/null || recusa \
  "não consegui copiar o shipcraft para $DEST" "falta permissão ou disco; o binário anterior ficou como estava" \
  "confira a pasta $DEST e o espaço livre, e rode de novo"
mv -f "$NOVO" "$ALVO_BIN" 2>/dev/null || recusa "não consegui trocar $ALVO_BIN" \
  "a troca é uma renomeação; o binário anterior ficou como estava" "confira a permissão de $DEST e rode de novo"
NOVO=""
echo "instalar.sh: instalei o shipcraft $VERSAO ($ALVO) em $ALVO_BIN"

ACHADO=$(command -v shipcraft 2>/dev/null || true)
REAL_DEST=$(cd "$DEST" && pwd -P)
case "$ACHADO" in
  /*) REAL_ACHADO="$(cd "$(dirname "$ACHADO")" && pwd -P)/shipcraft" ;;
  *) REAL_ACHADO="" ;;
esac
if [ "$REAL_ACHADO" != "$REAL_DEST/shipcraft" ]; then
  echo "instalar.sh: o PATH resolve o shipcraft em ${ACHADO:-nenhum lugar}, e não em $ALVO_BIN; ponha a pasta antes: export PATH=\"$DEST:\$PATH\""
fi
