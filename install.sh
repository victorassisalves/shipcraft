#!/usr/bin/env bash
# Installs, updates and removes shipcraft (docs/spec.md, item 21.3).
#
# usage: install.sh [--version <v>] | install.sh --uninstall
#
# Downloads the release from victorassisalves/shipcraft (or SHIPCRAFT_REPO) with gh, which
# must be logged in, and puts the binary in ${SHIPCRAFT_BIN:-$HOME/.local/bin}/shipcraft.
# Any failure before the swap leaves the previous binary as it was.
set -u

refuse() { # refuse <what> <why> <next>: three lines, exits 1
  printf 'shipcraft refused: %s\nWhy: %s\nNext: %s\n' "$1" "$2" "$3" >&2
  exit 1
}
USAGE="usage: install.sh [--version <v>] | install.sh --uninstall"

REPO="${SHIPCRAFT_REPO:-victorassisalves/shipcraft}"
DEST="${SHIPCRAFT_BIN:-$HOME/.local/bin}"
TARGET_BIN="$DEST/shipcraft"

VERSION=""
case "$*" in
  "") ;;
  --uninstall)
    if [ -e "$TARGET_BIN" ] || [ -L "$TARGET_BIN" ]; then
      rm -f "$TARGET_BIN" || refuse "could not delete $TARGET_BIN" "the binary is still there" \
        "check the permissions of $DEST and run again"
      echo "install.sh: removed $TARGET_BIN; projects with shipcraft integrated will refuse commits until it is back or the integration is removed."
    else
      echo "install.sh: there is no $TARGET_BIN; projects with shipcraft integrated will refuse commits until it is back or the integration is removed."
    fi
    exit 0
    ;;
  *)
    [ $# -eq 2 ] && [ "$1" = --version ] || refuse "invalid arguments: $*" \
      "install.sh installs a version or removes the binary" "$USAGE"
    VERSION="${2#v}"
    printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || refuse \
      "version '$2' is not X.Y.Z or vX.Y.Z" \
      "shipcraft releases are vX.Y.Z" "run with --version 1.2.0, or without --version for the latest"
    ;;
esac

[ "$(uname -s)" = Darwin ] || refuse "there is no shipcraft package for $(uname -s)" \
  "releases only carry the macOS targets" "build it with cargo install --path nucleo"
for tool in gh shasum tar; do
  command -v "$tool" >/dev/null 2>&1 || refuse "$tool is not on PATH" \
    "install.sh downloads and verifies the release with it" "install $tool and run again"
done

# The version is resolved once; everything comes from that tag.
if [ -z "$VERSION" ]; then
  TAG=$(gh release view --repo "$REPO" --json tagName --jq .tagName 2>/dev/null) || refuse \
    "could not read the latest release of $REPO" \
    "gh must be logged in to read releases" \
    "run gh auth login (or check SHIPCRAFT_REPO) and run again"
  VERSION="${TAG#v}"
  printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || refuse \
    "the latest release of $REPO has tag '$TAG', which is not vX.Y.Z" \
    "install.sh only installs X.Y.Z versions" "run with --version <v>"
fi
TAG="v$VERSION"

if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
  PLATFORM=aarch64-apple-darwin
else
  PLATFORM=x86_64-apple-darwin
fi
PACKAGE="shipcraft-$VERSION-$PLATFORM.tar.gz"

TMPROOT="${TMPDIR:-/tmp}"; TMPROOT="${TMPROOT%/}"
WORK=$(mktemp -d "$TMPROOT/shipcraft-install.XXXXXX") || refuse "could not create a temporary folder" \
  "the package is verified before it gets near the installed binary" \
  "check the space and permissions in $TMPROOT and run again"
NEW=""
trap 'rm -rf "$WORK"; [ -z "$NEW" ] || rm -f "$NEW"' EXIT
trap 'exit 130' INT TERM

gh release download "$TAG" --repo "$REPO" --pattern "$PACKAGE" --pattern SHA256SUMS --dir "$WORK" \
  >/dev/null 2>&1 && [ -f "$WORK/$PACKAGE" ] && [ -f "$WORK/SHA256SUMS" ] || refuse \
  "could not download $PACKAGE and SHA256SUMS from release $TAG of $REPO" \
  "gh must be logged in, and the release must have this target's package" \
  "run gh auth login, check gh release view $TAG --repo $REPO, and run again"

LINES=$(awk -v p="$PACKAGE" '$2 == p || $2 == "*" p' "$WORK/SHA256SUMS")
N=$(printf '%s' "$LINES" | grep -c . || true)
[ "$N" = 1 ] || refuse "SHA256SUMS of $TAG has $N lines for $PACKAGE, and needs exactly one" \
  "without a single sum the package cannot be verified" "check release $TAG; the previous binary is as it was"
(cd "$WORK" && printf '%s\n' "$LINES" | shasum -a 256 -c - >/dev/null 2>&1) || refuse \
  "the sum of $PACKAGE does not match SHA256SUMS of $TAG" \
  "the package may be corrupted or replaced" "run again; if it repeats, check release $TAG"

mkdir "$WORK/x" && tar -xzf "$WORK/$PACKAGE" -C "$WORK/x" 2>/dev/null || refuse \
  "could not extract $PACKAGE" "the package may be corrupted" \
  "check the space in $TMPROOT and release $TAG, and run again"
CONTENTS=$(ls -A "$WORK/x")
[ "$CONTENTS" = shipcraft ] && [ -f "$WORK/x/shipcraft" ] && [ ! -L "$WORK/x/shipcraft" ] && [ -x "$WORK/x/shipcraft" ] || refuse \
  "$PACKAGE does not hold just one executable shipcraft at its root" \
  "the release package is a single executable file, shipcraft" "check release $TAG; the previous binary is as it was"
SAYS=$("$WORK/x/shipcraft" --version 2>/dev/null)
case "$SAYS" in
  "shipcraft $VERSION ("*")") ;;
  *) refuse "the shipcraft in $PACKAGE says '$SAYS', not version $VERSION" \
    "the installed binary must be the requested version" "check release $TAG; the previous binary is as it was" ;;
esac

if [ -e "$TARGET_BIN" ] || [ -L "$TARGET_BIN" ]; then
  [ -f "$TARGET_BIN" ] && [ ! -L "$TARGET_BIN" ] || refuse "$TARGET_BIN exists and is not a file" \
    "the swap only replaces a binary, never a folder or a link" \
    "check what is at $TARGET_BIN, or use SHIPCRAFT_BIN=<folder>, and run again"
fi
SUM=$(shasum -a 256 "$WORK/x/shipcraft" | awk '{ print $1 }')
if [ -f "$TARGET_BIN" ] && [ "$(shasum -a 256 "$TARGET_BIN" 2>/dev/null | awk '{ print $1 }')" = "$SUM" ]; then
  echo "install.sh: shipcraft $VERSION is already at $TARGET_BIN"
  exit 0
fi

# The swap: a copy in the same folder and an atomic rename over the previous one.
mkdir -p "$DEST" 2>/dev/null || refuse "could not create the folder $DEST" \
  "shipcraft goes in \${SHIPCRAFT_BIN:-\$HOME/.local/bin}" "check the permissions or use SHIPCRAFT_BIN=<folder>, and run again"
NEW="$DEST/.shipcraft.new.$$"
{ cp "$WORK/x/shipcraft" "$NEW" && chmod 755 "$NEW"; } 2>/dev/null || refuse \
  "could not copy shipcraft to $DEST" "missing permission or disk space; the previous binary is as it was" \
  "check the folder $DEST and the free space, and run again"
mv -f "$NEW" "$TARGET_BIN" 2>/dev/null || refuse "could not replace $TARGET_BIN" \
  "the swap is a rename; the previous binary is as it was" "check the permissions of $DEST and run again"
NEW=""
echo "install.sh: installed shipcraft $VERSION ($PLATFORM) at $TARGET_BIN"

FOUND=$(command -v shipcraft 2>/dev/null || true)
REAL_DEST=$(cd "$DEST" && pwd -P)
case "$FOUND" in
  /*) REAL_FOUND="$(cd "$(dirname "$FOUND")" && pwd -P)/shipcraft" ;;
  *) REAL_FOUND="" ;;
esac
if [ "$REAL_FOUND" != "$REAL_DEST/shipcraft" ]; then
  echo "install.sh: PATH resolves shipcraft to ${FOUND:-nowhere}, not $TARGET_BIN; put the folder first: export PATH=\"$DEST:\$PATH\""
fi
