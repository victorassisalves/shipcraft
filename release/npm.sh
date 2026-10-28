#!/usr/bin/env bash
# Publishes the npm packages of a released version (npm/README.md).
#
# usage: release/npm.sh <version>                  publish from the GitHub release
#        release/npm.sh <version> --pack <out> [--from <dir>]
#                                                  npm pack into <out> instead of publishing,
#                                                  from the release or from <dir> (archives + SHA256SUMS)
#
# The platform packages carry the release binary unchanged; their bytes are checked against
# the release's SHA256SUMS. Platform packages are published before the `shipcraft` package
# that depends on them. npm never lets a version be published twice, so this refuses a version
# that is already on the registry. Authentication is the user's own npm config.
set -u

refuse() { # refuse <what> <why> <next>: three lines, exits 1
  printf 'shipcraft refused: %s\nWhy: %s\nNext: %s\n' "$1" "$2" "$3" >&2
  exit 1
}
USAGE="usage: release/npm.sh <version> [--pack <out> [--from <dir>]]"

[ $# -ge 1 ] || refuse "missing version" "a publish is of one version" "$USAGE"
VERSION="${1#v}"; shift
printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || refuse \
  "version '$VERSION' is not X.Y.Z" "npm versions follow the release tags" "$USAGE"
PACK=""; FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pack) [ $# -ge 2 ] || refuse "--pack needs a folder" "packs go somewhere" "$USAGE"; PACK="$2"; shift 2 ;;
    --from) [ $# -ge 2 ] || refuse "--from needs a folder" "archives come from somewhere" "$USAGE"; FROM="$2"; shift 2 ;;
    *) refuse "invalid argument: $1" "only --pack and --from exist" "$USAGE" ;;
  esac
done
[ -z "$FROM" ] || [ -n "$PACK" ] || refuse "--from without --pack" \
  "only the release's own archives are published" "add --pack <out>, or drop --from to publish"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
for tool in node npm shasum tar; do
  command -v "$tool" >/dev/null 2>&1 || refuse "$tool is not on PATH" "packaging needs it" "install $tool and run again"
done
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/shipcraft-npm.XXXXXX") || exit 2
trap 'rm -rf "$STAGE"' EXIT

if [ -z "$PACK" ]; then
  for p in shipcraft shipcraft-darwin-arm64 shipcraft-darwin-x64; do
    if npm view "$p@$VERSION" version >/dev/null 2>&1; then
      refuse "$p@$VERSION is already on npm" "npm never accepts the same version twice, and a half-published version is not repaired in place" \
        "publish a new release and run this with its version"
    fi
  done
fi

ASSETS="$STAGE/assets"; mkdir -p "$ASSETS"
if [ -n "$FROM" ]; then
  cp "$FROM"/shipcraft-"$VERSION"-*.tar.gz "$FROM"/SHA256SUMS "$ASSETS"/ 2>/dev/null || refuse \
    "no archives of $VERSION in $FROM" "the packages carry the release archives" "build them, or drop --from"
else
  command -v gh >/dev/null 2>&1 || refuse "gh is not on PATH" "the archives come from the GitHub release" "install gh and run again"
  gh release download "v$VERSION" -R victorassisalves/shipcraft -D "$ASSETS" -p 'shipcraft-*.tar.gz' -p SHA256SUMS || refuse \
    "could not download release v$VERSION" "the packages carry the release archives" "publish the release first (release/publish.sh)"
fi
(cd "$ASSETS" && shasum -a 256 -c SHA256SUMS --ignore-missing --quiet) || refuse \
  "an archive does not match SHA256SUMS" "a package must carry the released bytes" "download the release again"

LICENSE_FILE="$ROOT/LICENSE"
REPO_URL="git+https://github.com/victorassisalves/shipcraft.git"
PLATFORMS=""
for pair in "aarch64-apple-darwin darwin arm64" "x86_64-apple-darwin darwin x64"; do
  set -- $pair; target=$1; os=$2; cpu=$3
  archive="$ASSETS/shipcraft-$VERSION-$target.tar.gz"
  if [ ! -f "$archive" ]; then
    [ -n "$PACK" ] && { echo "release/npm.sh: no $target archive, its package is skipped (pack only)"; continue; }
    refuse "the release has no $target archive" "every platform package ships together" "check release v$VERSION"
  fi
  # Only an archive SHA256SUMS lists, with a matching digest, is packaged.
  want=$(awk -v f="shipcraft-$VERSION-$target.tar.gz" '$2 == f || $2 == "*" f {print $1}' "$ASSETS/SHA256SUMS")
  have=$(shasum -a 256 "$archive" | cut -d' ' -f1)
  [ -n "$want" ] && [ "$want" = "$have" ] || refuse "the $target archive is not in SHA256SUMS with its digest" \
    "a package must carry the released bytes" "download the release again"
  name="shipcraft-$os-$cpu"; dir="$STAGE/$name"; mkdir -p "$dir/bin"
  tar -xzf "$archive" -C "$dir/bin" shipcraft || refuse "could not unpack $archive" "the package carries the binary" "download the release again"
  chmod 755 "$dir/bin/shipcraft"; cp "$LICENSE_FILE" "$dir/"
  cat > "$dir/package.json" <<JSON
{
  "name": "$name",
  "version": "$VERSION",
  "description": "The shipcraft binary for $os-$cpu. Install the shipcraft package instead.",
  "license": "Apache-2.0",
  "repository": { "type": "git", "url": "$REPO_URL" },
  "os": ["$os"],
  "cpu": ["$cpu"],
  "files": ["bin/shipcraft", "LICENSE"]
}
JSON
  PLATFORMS="$PLATFORMS $name"
done

main="$STAGE/shipcraft"; mkdir -p "$main/bin"
cp "$ROOT/npm/shipcraft/bin/shipcraft.js" "$main/bin/"; chmod 755 "$main/bin/shipcraft.js"
cp "$LICENSE_FILE" "$main/"; cp "$ROOT/README.md" "$main/"
deps=$(for p in shipcraft-darwin-arm64 shipcraft-darwin-x64; do printf '    "%s": "%s",\n' "$p" "$VERSION"; done | sed '$ s/,$//')
cat > "$main/package.json" <<JSON
{
  "name": "shipcraft",
  "version": "$VERSION",
  "description": "A seatbelt for test-driven development with coding agents: locks the tests at RED so GREEN cannot quietly undo them.",
  "license": "Apache-2.0",
  "repository": { "type": "git", "url": "$REPO_URL" },
  "homepage": "https://github.com/victorassisalves/shipcraft",
  "keywords": ["tdd", "testing", "git-hooks", "coding-agents", "ci"],
  "bin": { "shipcraft": "bin/shipcraft.js" },
  "files": ["bin/shipcraft.js", "LICENSE", "README.md"],
  "engines": { "node": ">=18" },
  "optionalDependencies": {
$deps
  }
}
JSON

if [ -n "$PACK" ]; then
  mkdir -p "$PACK" && PACK=$(cd "$PACK" && pwd) || exit 2
  for p in $PLATFORMS shipcraft; do (cd "$STAGE/$p" && npm pack --silent --pack-destination "$PACK") || exit 2; done
  echo "release/npm.sh: packed$PLATFORMS shipcraft $VERSION into $PACK"
  exit 0
fi
for p in $PLATFORMS shipcraft; do
  (cd "$STAGE/$p" && npm publish --access public) || refuse "npm publish of $p failed" \
    "the registry did not take the package" "check \`npm whoami\`; if some packages of $VERSION were published, publish a new release"
done
echo "release/npm.sh: published$PLATFORMS shipcraft $VERSION"
