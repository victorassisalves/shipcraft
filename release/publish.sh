#!/usr/bin/env bash
# Releases shipcraft from the machine of whoever runs it (docs/spec.md, item 21.2).
#
# usage: release/publish.sh <version> [--local-build]     (1.2.0 or v1.2.0)
#
# Runs in the repository checkout (the current folder). It pins the commit at the start
# (HEAD, equal to the remote's main, clean tree, version equal to nucleo/Cargo.toml's,
# tag still free on the remote).
#
# By default (POC-023, kept 2026-10-31) it publishes the binaries the release-shadow
# workflow built and tested on GitHub's macOS runners at that exact commit: it requires a
# successful push run of release-shadow.yml on main for the pinned commit, downloads its
# artifact, checks it against the artifact's SHA256SUMS and the version line, packages
# those binaries unchanged and creates the release with gh. A missing, running or failed
# run refuses.
#
# --local-build is the fallback (the previous behavior): from a fresh checkout of the
# commit it builds both macOS targets, runs the whole battery against this machine's
# target (with acceptance/reuso.sh's per-tree reuse) and packages those.
#
# It does not publish to brew, crates.io or npm.
set -u

refuse() { # refuse <what> <why> <next>: three lines, exits 1
  printf 'shipcraft refused: %s\nWhy: %s\nNext: %s\n' "$1" "$2" "$3" >&2
  exit 1
}

LOCAL=0
case $# in
  1) ;;
  2) [ "$2" = --local-build ] && LOCAL=1 ;;
esac
{ [ $# -eq 1 ] || [ "$LOCAL" = 1 ]; } || refuse "usage: release/publish.sh <version> [--local-build]" \
  "a release is of one version, given once" "run with the version, for example 1.2.0 or v1.2.0"
VERSION="${1#v}"
printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || refuse \
  "version '$1' is not X.Y.Z or vX.Y.Z" \
  "a shipcraft version is always numeric X.Y.Z, without a pre-release suffix" \
  "run with the version in nucleo/Cargo.toml, for example 1.2.0"
TAG="v$VERSION"

[ "$(uname -s)" = Darwin ] || refuse "a release only comes from macOS" \
  "the packages are the two macOS targets, and the battery runs against this machine's target" \
  "run it on a Mac"
for tool in git gh cargo shasum tar; do
  command -v "$tool" >/dev/null 2>&1 || refuse "$tool is not on PATH" \
    "the release builds, packages and publishes with it" "install $tool and run again"
done

# ---------------------------------------------------------------- the pinned commit
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || refuse "the current folder is not a git repository" \
  "the release comes from the commit of the runner's checkout" "run at the root of the shipcraft checkout"
cd "$ROOT" || exit 2
SHA=$(git rev-parse --verify HEAD 2>/dev/null) || refuse "the repository has no HEAD" \
  "the release comes from a commit" "run in a checkout of main"

REMOTE=$(git ls-remote origin main 2>/dev/null) || refuse \
  "could not query the remote's main (git ls-remote origin main)" \
  "without the remote there is no way to know whether HEAD is the published main" \
  "check the network and access to origin and run again"
REMOTE=$(printf '%s\n' "$REMOTE" | awk '$2 == "refs/heads/main" { print $1 }')
[ -n "$REMOTE" ] || refuse "the remote has no main" \
  "the release comes from the remote's main" "check origin and run again"
[ "$SHA" = "$REMOTE" ] || refuse "HEAD ($SHA) is not the remote's main ($REMOTE)" \
  "a release only comes from the published main, which anyone can check" \
  "run git switch main and git pull --ff-only, and run again"
[ -z "$(git status --porcelain --untracked-files=all)" ] || refuse "the tree is not clean" \
  "the pinned commit must be what is in the folder, with no change on top" \
  "commit or discard what changed (git status) and run again"
CARGO_VERSION=$(git show "$SHA:nucleo/Cargo.toml" 2>/dev/null | awk '
  /^\[/ { pkg = ($0 == "[package]") }
  pkg && /^version[ \t]*=/ { sub(/^[^"]*"/, ""); sub(/".*$/, ""); print; exit }')
[ "$CARGO_VERSION" = "$VERSION" ] || refuse \
  "the requested version ($VERSION) is not the one in nucleo/Cargo.toml (${CARGO_VERSION:-none})" \
  "the release's shipcraft --version must say the tag's version" \
  "bump the version in nucleo/Cargo.toml in a PR, or run with $CARGO_VERSION"
TAGS=$(git ls-remote --tags origin "refs/tags/$TAG" 2>/dev/null) || refuse \
  "could not query the remote's tags (git ls-remote --tags origin)" \
  "without the remote there is no way to know whether $TAG already exists" \
  "check the network and access to origin and run again"
[ -z "$TAGS" ] || refuse "tag $TAG already exists on the remote" \
  "a published version does not change" "bump the version in nucleo/Cargo.toml and run with the new one"
echo "publish.sh: $TAG from commit $SHA"

# ---------------------------------------------------------------- the fresh checkout
TMPROOT="${TMPDIR:-/tmp}"; TMPROOT="${TMPROOT%/}"
WORK=$(mktemp -d "$TMPROOT/shipcraft-publish.XXXXXX") || { echo "publish.sh: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
if [ "$LOCAL" = 1 ]; then
  SRC="$WORK/src"
  { git clone -q --no-checkout "$ROOT" "$SRC" && git -C "$SRC" checkout -q --detach "$SHA"; } \
    || refuse "could not make a fresh checkout of $SHA" \
      "the release comes from its own checkout, which the runner's checkout does not change" \
      "check the space in $TMPROOT and run again"

  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
    PLATFORM=aarch64-apple-darwin; OTHER=x86_64-apple-darwin
  else
    PLATFORM=x86_64-apple-darwin; OTHER=aarch64-apple-darwin
  fi

  # ---------------------------------------------------------------- build and test
  export CARGO_TARGET_DIR="$SRC/nucleo/target"
  for target in aarch64-apple-darwin x86_64-apple-darwin; do
    (cd "$SRC/nucleo" && nice -n 10 cargo build --release --locked -j 4 --target "$target") \
      && [ -x "$CARGO_TARGET_DIR/$target/release/shipcraft" ] \
      || refuse "the build for $target failed" \
        "the release carries both macOS targets" \
        "install the target (rustup target add $target), check the build and run again"
  done
  BIN="$CARGO_TARGET_DIR/$PLATFORM/release/shipcraft"

  BATTERY=""
  if [ -f "$SRC/acceptance/reuso.sh" ]; then
    . "$SRC/acceptance/reuso.sh"
    BATTERY=$(acceptance_cached_result "$SRC" HEAD) || BATTERY=""
  fi
  if [ -n "$BATTERY" ]; then
    echo "publish.sh: battery reused for this tree: $BATTERY"
  else
    (cd "$SRC" && nice -n 10 bash acceptance/run.sh "$BIN" all) || refuse \
      "the whole battery is red against $PLATFORM" \
      "a release only comes from a commit with a green battery" \
      "fix it on main through a PR and run again; nothing was published"
    BATTERY="green in this run"
  fi

  # ---------------------------------------------------------------- package
  OUT="$WORK/out"; mkdir -p "$OUT"
  for target in aarch64-apple-darwin x86_64-apple-darwin; do
    mkdir -p "$WORK/pkg/$target" && cp "$CARGO_TARGET_DIR/$target/release/shipcraft" "$WORK/pkg/$target/shipcraft" \
      && chmod 755 "$WORK/pkg/$target/shipcraft" \
      && COPYFILE_DISABLE=1 tar -czf "$OUT/shipcraft-$VERSION-$target.tar.gz" -C "$WORK/pkg/$target" shipcraft \
      || refuse "could not package $target" "the release carries one package per target" \
        "check the space in $TMPROOT and run again; nothing was published"
  done
  (cd "$OUT" && shasum -a 256 "shipcraft-$VERSION-aarch64-apple-darwin.tar.gz" \
    "shipcraft-$VERSION-x86_64-apple-darwin.tar.gz" > SHA256SUMS) \
    || refuse "could not write SHA256SUMS" "whoever installs checks the package's sum" \
      "run again; nothing was published"
else
  # -------------------------------------------------------------- the CI binaries (POC-023)
  PLATFORM=aarch64-apple-darwin; OTHER=x86_64-apple-darwin
  RUN=$(gh run list --workflow release-shadow.yml --branch main --event push --commit "$SHA" \
    --json databaseId,status,conclusion -L 20 \
    --jq '[.[] | select(.status == "completed" and .conclusion == "success")][0].databaseId // empty' 2>/dev/null) \
    || refuse "could not list the release-shadow runs for $SHA (gh run list)" \
      "the release publishes the binaries the shadow run built and tested at this commit" \
      "check gh auth and the network and run again, or run with --local-build"
  [ -n "$RUN" ] || refuse "no successful release-shadow run for $SHA" \
    "the published binary must be the one the whole battery passed on, at this exact commit" \
    "wait for the release-shadow run on main to pass (gh run list --workflow release-shadow.yml), rerun it if it failed, or run with --local-build"
  echo "publish.sh: binaries from release-shadow run $RUN"
  CI="$WORK/ci"
  gh run download "$RUN" -n "shipcraft-darwin-$SHA" -D "$CI" >/dev/null 2>&1 \
    || refuse "could not download the artifact shipcraft-darwin-$SHA of run $RUN" \
      "the release publishes those exact binaries" "check gh and the run's artifacts and run again, or run with --local-build"
  (cd "$CI" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1) || refuse \
    "the artifact of run $RUN does not match its SHA256SUMS" \
    "the published binary must be byte for byte the tested one" "rerun the release-shadow workflow and run again"
  for target in aarch64-apple-darwin x86_64-apple-darwin; do
    [ -f "$CI/$target/shipcraft" ] || refuse "the artifact of run $RUN has no $target binary" \
      "the release carries both macOS targets" "rerun the release-shadow workflow and run again"
  done
  chmod 755 "$CI"/*/shipcraft
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
    LINE=$("$CI/aarch64-apple-darwin/shipcraft" --version 2>/dev/null)
    case "$LINE" in
      "shipcraft $VERSION (${SHA:0:12})"*) ;;
      *) refuse "the CI binary says '$LINE', not shipcraft $VERSION (${SHA:0:12})" \
        "the release's shipcraft --version must say the tag's version and commit" "rerun the release-shadow workflow and run again" ;;
    esac
  fi
  BATTERY="green in release-shadow run $RUN (5 macOS shards, against this exact uploaded binary)"
  OUT="$WORK/out"; mkdir -p "$OUT"
  for target in aarch64-apple-darwin x86_64-apple-darwin; do
    mkdir -p "$WORK/pkg/$target" && cp "$CI/$target/shipcraft" "$WORK/pkg/$target/shipcraft" \
      && chmod 755 "$WORK/pkg/$target/shipcraft" \
      && COPYFILE_DISABLE=1 tar -czf "$OUT/shipcraft-$VERSION-$target.tar.gz" -C "$WORK/pkg/$target" shipcraft \
      || refuse "could not package $target" "the release carries one package per target" \
        "check the space in $TMPROOT and run again; nothing was published"
  done
  (cd "$OUT" && shasum -a 256 "shipcraft-$VERSION-aarch64-apple-darwin.tar.gz" \
    "shipcraft-$VERSION-x86_64-apple-darwin.tar.gz" > SHA256SUMS) \
    || refuse "could not write SHA256SUMS" "whoever installs checks the package's sum" \
      "run again; nothing was published"
fi
cat > "$WORK/notes.md" <<EOF
shipcraft $VERSION, from commit $SHA.

The whole battery (acceptance/run.sh all) ran against $PLATFORM: $BATTERY.
$OTHER was only built: the battery did not run against it (an accepted limit, item 21.2).

Install: run \`install.sh\` from the repository root (needs gh logged in).
EOF

# ---------------------------------------------------------------- publish
# gh release create creates the tag at the pinned commit and the release with the packages.
# If it fails after returning the URL, the release is this run's and is deleted; without
# the URL, the answer may have been lost, and nothing is deleted.
URL=$(gh release create "$TAG" --target "$SHA" --title "$TAG" --notes-file "$WORK/notes.md" \
  "$OUT/shipcraft-$VERSION-aarch64-apple-darwin.tar.gz" "$OUT/shipcraft-$VERSION-x86_64-apple-darwin.tar.gz" \
  "$OUT/SHA256SUMS")
CREATED=$?
if [ "$CREATED" -ne 0 ]; then
  case "$URL" in
    *"/releases/tag/$TAG"*)
      gh release delete "$TAG" --yes --cleanup-tag >/dev/null 2>&1 && refuse \
        "gh release create failed after creating $TAG; deleted the release and the tag it created" \
        "a half-made release would install packages that do not check out" "fix it and run again"
      refuse "gh release create failed after creating $TAG, and it could not be deleted" \
        "a half-made release would install packages that do not check out" \
        "delete it with gh release delete $TAG --yes --cleanup-tag and run again"
      ;;
  esac
  printf 'shipcraft refused: gh release create failed and did not return the release\nWhy: the answer may have been lost with the release created, and deleting blindly may delete someone else'"'"'s\nNext: before running again, check gh release view %s and git ls-remote --tags origin %s; delete with gh release delete %s --cleanup-tag if it is half made\n' "$TAG" "$TAG" "$TAG" >&2
  exit 1
fi
echo "publish.sh: $TAG published at commit $SHA: $URL"
