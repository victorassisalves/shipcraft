#!/usr/bin/env bash
# Releases shipcraft from the machine of whoever runs it (docs/spec.md, items 21.2 and 78).
#
# usage: release/publish.sh <version> [--local-build]     (1.2.0 or v1.2.0)
#
# Runs in the repository checkout (the current folder). It pins the commit at the start
# (HEAD, equal to the remote's main, clean tree, version equal to nucleo/Cargo.toml's,
# tag still free on the remote). Every gh call names the GitHub repository read once from
# origin's URL (-R github.com/<owner>/<repo>), whatever GH_HOST says.
#
# By default (item 78, POC-023 kept) it publishes the binaries the release-shadow workflow
# built and tested at that commit: the first successful push run of release-shadow.yml on
# main for the commit, its artifact checked against the artifact's SHA256SUMS and, on an
# arm64 Mac, against the version line. It builds nothing and runs no battery here.
#
# --local-build is the fallback (item 21's path): from a fresh checkout of the commit it
# builds both macOS targets, runs the whole battery against this machine's target (with
# acceptance/reuso.sh's per-tree reuse) and packages those.
#
# Either way it packages one archive per target, writes SHA256SUMS and creates the release
# with gh. It does not publish to brew, crates.io or npm.
set -u

refuse() { # refuse <what> <why> <next>: three lines, exits 1
  printf 'shipcraft refused: %s\nWhy: %s\nNext: %s\n' "$1" "$2" "$3" >&2
  exit 1
}

LOCAL=0
[ $# -eq 2 ] && [ "$2" = --local-build ] && LOCAL=1
[ $# -eq 1 ] || [ "$LOCAL" = 1 ] || refuse "usage: release/publish.sh <version> [--local-build]" \
  "a release is of one version, given once; --local-build is the only option" \
  "run with the version, for example 1.2.0 or v1.2.0, adding --local-build only to build and test on this Mac"
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

# ---------------------------------------------------------------- the GitHub repository
# Read once from origin's URL; every gh call names it, so GH_HOST never picks another host.
ORIGIN=$(git remote get-url origin 2>/dev/null) || refuse \
  "could not read origin's URL (git remote get-url origin)" \
  "every gh call of the release names the GitHub repository origin points to" \
  "set origin to the GitHub repository (git remote -v) and run again"
OWNER_REPO=""
case "$ORIGIN" in
  https://github.com/*) OWNER_REPO="${ORIGIN#https://github.com/}" ;;
  ssh://git@github.com/*) OWNER_REPO="${ORIGIN#ssh://git@github.com/}" ;;
  git@github.com:*) OWNER_REPO="${ORIGIN#git@github.com:}" ;;
esac
OWNER_REPO="${OWNER_REPO%.git}"
{ printf '%s\n' "$OWNER_REPO" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$' \
  && [ "${OWNER_REPO#*/}" != . ] && [ "${OWNER_REPO#*/}" != .. ]; } || refuse \
  "origin ($ORIGIN) is not a github.com repository URL" \
  "the release is published on github.com, in the repository origin points to, whatever GH_HOST says" \
  "set origin to https://github.com/<owner>/<repo>.git, git@github.com:<owner>/<repo>.git or ssh://git@github.com/<owner>/<repo>.git and run again"
REPO="github.com/$OWNER_REPO"

TMPROOT="${TMPDIR:-/tmp}"; TMPROOT="${TMPROOT%/}"
WORK=$(mktemp -d "$TMPROOT/shipcraft-publish.XXXXXX") || { echo "publish.sh: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
TARGETS="aarch64-apple-darwin x86_64-apple-darwin"

if [ "$LOCAL" = 1 ]; then
  # -------------------------------------------------------------- --local-build: fresh checkout
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

  # -------------------------------------------------------------- --local-build: build and test
  export CARGO_TARGET_DIR="$SRC/nucleo/target"
  for target in $TARGETS; do
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
  BINDIR="$CARGO_TARGET_DIR"; BINSUFFIX=release/shipcraft
  NOTES="The whole battery (acceptance/run.sh all) ran against $PLATFORM: $BATTERY.
$OTHER was only built: the battery did not run against it (an accepted limit, item 21.2)."

else
  # -------------------------------------------------------------- the release-shadow run
  # Strict reading of gh run list --json databaseId,status,conclusion: one JSON array of
  # objects, each with a positive integer databaseId (kept as its digit string, of any
  # length, never converted to a number) and string status and conclusion
  # (other fields allowed). Exit 2: unreadable; exit 3: no row completed with success;
  # otherwise it prints the databaseId of the first such row, in the CLI's order.
  RUNS_AWK='
function err() { exit 2 }
function ch() { return substr(s, p, 1) }
function ws(   c) {
  while (p <= n) { c = substr(s, p, 1); if (c == " " || c == "\t" || c == "\n" || c == "\r") p++; else break }
}
function hexval(h,   i, v) {
  v = 0; h = tolower(h)
  for (i = 1; i <= length(h); i++) v = v * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1
  return v
}
function str(   c, out, h, v) {
  if (ch() != "\"") err()
  p++; out = ""
  while (1) {
    if (p > n) err()
    c = substr(s, p, 1)
    if (c == "\"") { p++; return out }
    if (index(ctl, c)) err()
    if (c == "\\") {
      p++; c = substr(s, p, 1)
      if (c == "\"" || c == "\\" || c == "/") out = out c
      else if (c == "b" || c == "f" || c == "n" || c == "r" || c == "t") out = out "\\" c
      else if (c == "u") {
        h = substr(s, p + 1, 4)
        if (h !~ /^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$/) err()
        v = hexval(h)
        if (v >= 32 && v < 127) out = out sprintf("%c", v); else out = out "\\u" h
        p += 4
      } else err()
      p++
    } else { out = out c; p++ }
  }
}
function digits() { if (ch() !~ /^[0-9]$/) err(); while (ch() ~ /^[0-9]$/) p++ }
function num(   start) {
  start = p
  if (ch() == "-") p++
  if (ch() == "0") p++
  else if (ch() ~ /^[1-9]$/) digits()
  else err()
  if (ch() == ".") { p++; digits() }
  if (ch() == "e" || ch() == "E") { p++; if (ch() == "+" || ch() == "-") p++; digits() }
  return substr(s, start, p - start)
}
function value(   c) {
  ws(); c = ch()
  if (c == "\"") { vtype = "string"; return str() }
  if (c == "{") { obj(0); vtype = "object"; return "" }
  if (c == "[") { arr(); vtype = "array"; return "" }
  if (c == "-" || c ~ /^[0-9]$/) { vtype = "number"; return num() }
  if (substr(s, p, 4) == "true") { p += 4; vtype = "bool"; return "" }
  if (substr(s, p, 5) == "false") { p += 5; vtype = "bool"; return "" }
  if (substr(s, p, 4) == "null") { p += 4; vtype = "null"; return "" }
  err()
}
function arr(   c) {
  p++; ws()
  if (ch() == "]") { p++; return }
  while (1) {
    value(); ws(); c = ch()
    if (c == ",") { p++; continue }
    if (c == "]") { p++; return }
    err()
  }
}
function obj(row,   c, key, v, t) {
  p++; ws()
  if (ch() == "}") { p++; return }
  while (1) {
    ws(); key = str(); ws()
    if (ch() != ":") err()
    p++
    v = value(); t = vtype
    if (row && key == "databaseId") {
      if (hasid++ || t != "number" || v !~ /^[1-9][0-9]*$/) err()
      rid = v
    } else if (row && key == "status") {
      if (hass++ || t != "string") err()
      rstatus = v
    } else if (row && key == "conclusion") {
      if (hasc++ || t != "string") err()
      rconc = v
    }
    ws(); c = ch()
    if (c == ",") { p++; continue }
    if (c == "}") { p++; return }
    err()
  }
}
{ s = s $0 "\n" }
END {
  for (i = 1; i < 32; i++) ctl = ctl sprintf("%c", i)
  n = length(s); p = 1; found = ""
  ws()
  if (ch() != "[") err()
  p++; ws()
  if (ch() == "]") p++
  else while (1) {
    ws()
    if (ch() != "{") err()
    hasid = 0; hass = 0; hasc = 0
    obj(1)
    if (!hasid || !hass || !hasc) err()
    if (found == "" && rstatus == "completed" && rconc == "success") found = rid
    ws(); c = ch()
    if (c == ",") { p++; continue }
    if (c == "]") { p++; break }
    err()
  }
  ws()
  if (p <= n) err()
  if (found == "") exit 3
  print found
  exit 0
}'
  RUNS=$(gh run list -R "$REPO" --workflow release-shadow.yml --branch main --event push --commit "$SHA" \
    --json databaseId,status,conclusion --limit 20) || refuse \
    "could not list the release-shadow runs for $SHA (gh run list -R $REPO)" \
    "the release publishes the binaries the release-shadow run built and tested at this commit" \
    "check gh auth status and the network and run again, or run with --local-build"
  RUN=$(printf '%s\n' "$RUNS" | LC_ALL=C awk "$RUNS_AWK")
  case $? in
    0) ;;
    3) refuse "no successful release-shadow run for $SHA" \
         "the published binaries must be the ones the whole battery passed on, at this exact commit" \
         "wait for the push run of release-shadow.yml on main to finish (gh run list -R $REPO --workflow release-shadow.yml), rerun a failed push run with gh run rerun <id> -R $REPO, or run with --local-build" ;;
    *) refuse "the output of gh run list for $SHA is unreadable (not a JSON array of runs with databaseId, status and conclusion)" \
         "the run is chosen only from an answer read in full" \
         "check gh --version and gh run list -R $REPO --workflow release-shadow.yml, or run with --local-build" ;;
  esac
  echo "publish.sh: binaries from release-shadow run $RUN"

  # -------------------------------------------------------------- the artifact
  CI="$WORK/ci"
  gh run download "$RUN" -R "$REPO" -n "shipcraft-darwin-$SHA" -D "$CI" >/dev/null || refuse \
    "could not download the artifact shipcraft-darwin-$SHA of release-shadow run $RUN" \
    "the release publishes those exact binaries; the run keeps its artifact 30 days" \
    "rerun that push run (gh run rerun $RUN -R $REPO) and run again, or run with --local-build"
  for target in $TARGETS; do
    { [ -d "$CI/$target" ] && [ ! -L "$CI/$target" ] \
      && [ -f "$CI/$target/shipcraft" ] && [ ! -L "$CI/$target/shipcraft" ]; } \
      || refuse "the artifact of release-shadow run $RUN has no regular file $target/shipcraft" \
        "the release carries both macOS targets, as the run uploaded them" \
        "rerun the release-shadow push run (gh run rerun $RUN -R $REPO) and run again, or run with --local-build"
  done
  { [ -f "$CI/SHA256SUMS" ] && [ ! -L "$CI/SHA256SUMS" ] && LC_ALL=C awk '
      { h = substr($0, 1, 64); rest = substr($0, 65) }
      length(h) == 64 && h ~ /^[0-9a-f]+$/ && rest == "  aarch64-apple-darwin/shipcraft" { arm++; next }
      length(h) == 64 && h ~ /^[0-9a-f]+$/ && rest == "  x86_64-apple-darwin/shipcraft" { intel++; next }
      { bad = 1 }
      END { exit !(NR == 2 && arm == 1 && intel == 1 && !bad) }' "$CI/SHA256SUMS"; } \
    || refuse "the artifact of release-shadow run $RUN has no valid SHA256SUMS (exactly one shasum line per binary)" \
      "the published binaries must be byte for byte the ones the run tested" \
      "rerun the release-shadow push run (gh run rerun $RUN -R $REPO) and run again, or run with --local-build"
  (cd "$CI" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1) || refuse \
    "the binaries of release-shadow run $RUN do not match its SHA256SUMS" \
    "the published binaries must be byte for byte the ones the run tested" \
    "rerun the release-shadow push run (gh run rerun $RUN -R $REPO) and run again, or run with --local-build"
  chmod 755 "$CI/aarch64-apple-darwin/shipcraft" "$CI/x86_64-apple-darwin/shipcraft" || refuse \
    "could not make the binaries of release-shadow run $RUN executable" \
    "the packages hold the executable shipcraft" "check the space in $TMPROOT and run again; nothing was published"

  # -------------------------------------------------------------- the version line
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = 1 ]; then
    WANT="shipcraft $VERSION (${SHA:0:12})"
    "$CI/aarch64-apple-darwin/shipcraft" --version >"$WORK/version.out" 2>/dev/null </dev/null || refuse \
      "the arm64 binary of release-shadow run $RUN failed shipcraft --version" \
      "the release's shipcraft --version must say the tag's version and commit" \
      "rerun the release-shadow push run (gh run rerun $RUN -R $REPO) and run again, or run with --local-build"
    printf '%s\n' "$WANT" >"$WORK/version.want" && cmp -s "$WORK/version.out" "$WORK/version.want" || refuse \
      "the arm64 binary of release-shadow run $RUN does not print exactly '$WANT' for --version" \
      "the release's shipcraft --version must say the tag's version and commit" \
      "check that run $RUN built commit $SHA, rerun it (gh run rerun $RUN -R $REPO), or run with --local-build"
    VERSIONCHECK="The arm64 binary's version line ($WANT) was checked on this Mac."
  else
    VERSIONCHECK="The version line check was skipped: this Mac is not arm64, so the arm64 binary was not run here."
  fi
  BINDIR="$CI"; BINSUFFIX=shipcraft
  NOTES="The whole battery ran green in release-shadow run $RUN (5 macOS shards, against the uploaded arm64 binary); this release publishes that run's binaries.
x86_64-apple-darwin was only built: the battery did not run against it (an accepted limit, item 78).
$VERSIONCHECK"
fi

# ---------------------------------------------------------------- package
OUT="$WORK/out"; mkdir -p "$OUT"
for target in $TARGETS; do
  mkdir -p "$WORK/pkg/$target" && cp "$BINDIR/$target/$BINSUFFIX" "$WORK/pkg/$target/shipcraft" \
    && chmod 755 "$WORK/pkg/$target/shipcraft" \
    && COPYFILE_DISABLE=1 tar -czf "$OUT/shipcraft-$VERSION-$target.tar.gz" -C "$WORK/pkg/$target" shipcraft \
    || refuse "could not package $target" "the release carries one package per target" \
      "check the space in $TMPROOT and run again; nothing was published"
done
(cd "$OUT" && shasum -a 256 "shipcraft-$VERSION-aarch64-apple-darwin.tar.gz" \
  "shipcraft-$VERSION-x86_64-apple-darwin.tar.gz" > SHA256SUMS) \
  || refuse "could not write SHA256SUMS" "whoever installs checks the package's sum" \
    "run again; nothing was published"
cat > "$WORK/notes.md" <<EOF
shipcraft $VERSION, from commit $SHA.

$NOTES

Install: run \`install.sh\` from the repository root (needs gh logged in).
EOF

# ---------------------------------------------------------------- publish
# gh release create creates the tag at the pinned commit and the release with the packages.
# If it fails after returning the URL, the release is this run's and is deleted; without
# the URL, the answer may have been lost, and nothing is deleted.
URL=$(gh release create "$TAG" -R "$REPO" --target "$SHA" --title "$TAG" --notes-file "$WORK/notes.md" \
  "$OUT/shipcraft-$VERSION-aarch64-apple-darwin.tar.gz" "$OUT/shipcraft-$VERSION-x86_64-apple-darwin.tar.gz" \
  "$OUT/SHA256SUMS")
CREATED=$?
if [ "$CREATED" -ne 0 ]; then
  case "$URL" in
    *"/releases/tag/$TAG"*)
      gh release delete "$TAG" -R "$REPO" --yes --cleanup-tag >/dev/null 2>&1 && refuse \
        "gh release create failed after creating $TAG; deleted the release and the tag it created" \
        "a half-made release would install packages that do not check out" "fix it and run again"
      refuse "gh release create failed after creating $TAG, and it could not be deleted" \
        "a half-made release would install packages that do not check out" \
        "delete it with gh release delete $TAG -R $REPO --yes --cleanup-tag and run again"
      ;;
  esac
  printf 'shipcraft refused: gh release create failed and did not return the release\nWhy: the answer may have been lost with the release created, and deleting blindly may delete someone else'"'"'s\nNext: before running again, check gh release view %s -R %s and git ls-remote --tags origin %s; delete with gh release delete %s -R %s --cleanup-tag if it is half made\n' "$TAG" "$REPO" "$TAG" "$TAG" "$REPO" >&2
  exit 1
fi
echo "publish.sh: $TAG published at commit $SHA: $URL"
