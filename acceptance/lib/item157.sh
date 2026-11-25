# Item 157: the battery writes no git config outside its work folder (docs/spec.md, item 157).
# Each case but own-identity runs a nested core battery on a copy of this acceptance/ folder,
# committed in a fresh repository in the case's folder, and compares that repository's config.
item157_langs() { echo core; }
item157_cases() { for c in hook-env linked-env other-vars guard guard-worktree quiet-control own-identity; do echo "v1-157.$c"; done; }

item157_src() { # the copy: $SRC157 (physical), committed; $1 = 1 adds the probe case; $2 its folder name
  SRC157="$CW/${2:-src157}"; mkdir -p "$SRC157" || fail 'fixture mkdir'
  cp -R "$ACEITE" "$SRC157/acceptance" || fail 'fixture copy of acceptance/'
  if [ "${1:-0}" = 1 ]; then
    cat > "$SRC157/acceptance/lib/item157probe.sh" <<'PROBE'
item157probe_langs() { echo core; }
item157probe_cases() { echo v1-157probe.write; }
item157probe_case() { EXPECT=probe; git -C "$ACEITE/.." config "${PROBE157_SCOPE:---local}" probe157.leak yes; OBS=probe; finish PASS; }
PROBE
  fi
  SRC157=$(cd "$SRC157" && pwd -P)
  (cd "$SRC157" && git init -q . && git add -A && git commit -q -m 'copy157') || fail 'fixture repository'
  cp "$SRC157/.git/config" "$CW/config157.before"
}
item157_nest() { # item157_nest <dir> <cases> [VAR=value...]: nested battery, output $CW/nest157.out, exit NRC
  local dir="$1" cases="$2"; shift 2
  mkdir -p "$CW/tmp157"
  (cd "$dir" && env -u SHIPCRAFT_ACCEPTANCE_JUNIT -u SHIPCRAFT_ACCEPTANCE_FILES -u SHIPCRAFT_ACCEPTANCE_SHARD \
      -u SHIPCRAFT_ACCEPTANCE_KEEP -u SHIPCRAFT_ACCEPTANCE_CASES -u SHIPCRAFT_ACCEPTANCE_VERBOSE -u GITHUB_ACTIONS \
      SHIPCRAFT_ACCEPTANCE_REUSE=0 SHIPCRAFT_ACCEPTANCE_CASE_TIMEOUT=300 SHIPCRAFT_ACCEPTANCE_CACHE="${XDG_CACHE_HOME%/xdg}" \
      SHIPCRAFT_ACCEPTANCE_CASES="$cases" SHIPCRAFT_ACCEPTANCE_JUNIT="$CW/nest157.xml" TMPDIR="$CW/tmp157" "$@" \
      bash acceptance/run.sh "$WORK/bin/shipcraft" core) > "$CW/nest157.out" 2>&1
  NRC=$?
  cat "$CW/nest157.out" >> "$LOG"
}
item157_guard_msg() { # item157_guard_msg <expected message|->: the JUnit guard testcase (- = none)
  "$PY" - "$CW/nest157.xml" "$1" <<'PY157'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
hits = [t for t in root.iter('testcase') if t.get('name') == 'core::harness-git-config']
if sys.argv[2] == '-':
    assert not hits, 'unexpected guard testcase'
    sys.exit(0)
assert len(hits) == 1, [t.get('name') for t in root.iter('testcase')]
t = hits[0]; e = t.find('error')
assert t.get('classname') == 'acceptance/run.sh', t.get('classname')
assert e is not None and e.get('message') == sys.argv[2], (e is not None and e.get('message'), sys.argv[2])
PY157
}
item157_same() { cmp -s "$CW/config157.before" "$SRC157/.git/config" || { diff "$CW/config157.before" "$SRC157/.git/config"; return 1; }; }

item157_case() {
  local c=${CASE#v1-157.} nwork
  EXPECT="item 157: $c"
  case "$c" in
    hook-env)
      item157_src
      item157_nest "$SRC157" e1-english-ci GIT_DIR="$SRC157/.git" GIT_INDEX_FILE="$SRC157/.git/index"
      chk 'nested battery with a hook GIT_DIR passes' eq "$NRC" 0
      chk 'the repository config is byte-identical' item157_same ;;
    linked-env)
      item157_src
      git -C "$SRC157" worktree add -q --detach "$CW/wt157" || fail 'fixture linked worktree'
      item157_nest "$CW/wt157" e1-english-ci GIT_DIR="$SRC157/.git/worktrees/wt157" GIT_INDEX_FILE="$SRC157/.git/worktrees/wt157/index"
      chk 'nested battery from a linked worktree with its hook GIT_DIR passes' eq "$NRC" 0
      chk 'the shared config is byte-identical' item157_same
      chk 'shared core.bare stays false' eq "$(git -C "$SRC157" config core.bare)" false ;;
    other-vars)
      item157_src
      item157_nest "$SRC157" e1-english-ci GIT_COMMON_DIR="$SRC157/.git" GIT_WORK_TREE="$SRC157"
      chk 'nested battery with GIT_COMMON_DIR and GIT_WORK_TREE passes' eq "$NRC" 0
      chk 'the repository config is byte-identical' item157_same ;;
    guard)
      item157_src 1
      item157_nest "$SRC157" v1-157probe.write
      nwork=$(sed -n 's/^run\.sh: .*; work dir = //p' "$CW/nest157.out" | head -n 1)
      chk 'a run that changed the config exits 1' eq "$NRC" 1
      chk 'the total counts the guard row' grep -F -q -x 'run.sh: total: 1 of 2 cases pass' "$CW/nest157.out"
      chk 'JUnit has the guard error naming the config' item157_guard_msg "harness: the battery changed $SRC157/.git/config of the repository it runs from; the bytes at start are in $nwork/guard/"
      chk 'the guard keeps the bytes from start' cmp "$CW/config157.before" "$nwork/guard/1"
      chk 'the guard repairs nothing' eq "$(git -C "$SRC157" config probe157.leak)" yes ;;
    guard-worktree)
      item157_src 1 'src 157' # a space in the main repository's path (PR 180 review round 1)
      git -C "$SRC157" config extensions.worktreeConfig true || fail 'fixture worktreeConfig'
      git -C "$SRC157" worktree add -q --detach "$CW/wt157" || fail 'fixture linked worktree'
      item157_nest "$CW/wt157" v1-157probe.write PROBE157_SCOPE=--worktree
      nwork=$(sed -n 's/^run\.sh: .*; work dir = //p' "$CW/nest157.out" | head -n 1)
      chk 'a run that wrote config.worktree exits 1' eq "$NRC" 1
      chk 'JUnit names the worktree config' item157_guard_msg "harness: the battery changed $SRC157/.git/worktrees/wt157/config.worktree of the repository it runs from; the bytes at start are in $nwork/guard/"
      chk 'it was absent at start' test -e "$nwork/guard/3.absent" ;;
    quiet-control)
      item157_src
      item157_nest "$SRC157" e1-english-ci
      chk 'nested battery passes' eq "$NRC" 0
      chk 'no guard testcase' item157_guard_msg -
      chk 'no guard line' sh -c "! grep -i -q guard '$CW/nest157.out'"
      chk 'the repository config is byte-identical' item157_same ;;
    own-identity)
      chk 'the base repository has the identity' eq "$(git config --local user.name)" 'shipcraft acceptance'
      chk 'the base commit carries it' eq "$(git log -1 --format='%an <%ae>')" 'shipcraft acceptance <shipcraft-acceptance@example.invalid>' ;;
  esac
  pass
}
