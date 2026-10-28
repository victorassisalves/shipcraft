#!/usr/bin/env bash
# Shipcraft acceptance battery, version 1 (docs/spec.md; v0 is also in
# docs/spec.md and still holds wherever v1 does not change it).
#
# usage: run.sh <path-to-shipcraft-binary> [core|python|node|go|all]
#   core    = the language-independent cases (v1 items 1 to 5, 7, 9.2 and 10,
#             the 9.1 monorepo), run on the Python target
#   python, node, go = the v0 cases plus items 6, 8 and 9.1 per language
#
# Offline: gh and the reviewer agents are stubs in acceptance/stubs/ (see README.md). Only
# building the targets (pip, npm, go install) needs the network, or SHIPCRAFT_ACCEPTANCE_CACHE.
#
# Every case runs against a fresh target project built under $TMPDIR. Nothing is
# written outside one work dir under $TMPDIR, except the green reuse record below
# (isolated HOME, caches, GOPATH, npm and pip
# caches included). Passing cases remove their own t/ and cw/ directories immediately;
# failed cases and logs remain. Shared setup is removed at exit. SHIPCRAFT_ACCEPTANCE_KEEP=1
# keeps everything.
#
# Reuse: SHIPCRAFT_ACCEPTANCE_REUSE=0 turns off recording and the acceptance/local status.
# Metric: full batteries per head, target 1. Revert if an escape happens that the
# battery would have caught and reuse let through.
#
# Env:
#   SHIPCRAFT_ACCEPTANCE_CLONE=0  disable base clones; use cp -R (default: clone, copy on failure)
#   SHIPCRAFT_ACCEPTANCE_JOBS     parallel cases (default 4, capped at 4)
#   SHIPCRAFT_ACCEPTANCE_KEEP=1   keep the work dir (logs in <work>/logs)
#   SHIPCRAFT_ACCEPTANCE_RETAIN_HOURS  remove earlier work dirs older than this at start (default 24)
#   SHIPCRAFT_ACCEPTANCE_CACHE    absolute dir for pip/npm/go caches, reused across runs
#   SHIPCRAFT_ACCEPTANCE_VERBOSE=1  print the log tail of each failing case (on in GitHub Actions)
#   SHIPCRAFT_ACCEPTANCE_CASES    space-separated case ids to run (default: all)
#   SHIPCRAFT_ACCEPTANCE_SHARD    k/n: run only shard k of n (round robin), for split CI runs
#   SHIPCRAFT_ACCEPTANCE_CASE_TIMEOUT  seconds before a case is killed (default 900)
#   SHIPCRAFT_ACCEPTANCE_JUNIT    write a JUnit report there: one testcase per case (classname =
#                       profile, name = case id); FAIL = failure, harness error or no result
#                       (timeout, crash) = error, left out by SHIPCRAFT_ACCEPTANCE_CASES = skipped
#
# Portable: bash 3.2+, perl, python3, git, POSIX tools; clone flags are OS-specific.
set -u

SELF="$0"
case "$SELF" in /*) ;; *) SELF="$(pwd)/$SELF" ;; esac
ACEITE="$(cd "$(dirname "$SELF")" && pwd)"

# ---------------------------------------------------------------- language profiles
# Each language provides: lang_vars and the scenario functions <lang>_<name>.

lang_vars() {
  case "$1" in
    python)
      RUNNER_RE='pytest'; LANG_FLAG=python
      TESTFILE=tests/test_slug.py; EXTRAFILE=tests/test_extra.py
      FOREIGN='panic(
_test.go
gotestsum
go test
vitest'
      ;;
    node)
      RUNNER_RE='vitest'; LANG_FLAG=node
      TESTFILE=src/slug.test.ts; EXTRAFILE=src/extra.test.ts
      FOREIGN='NotImplementedError
pytest
panic(
_test.go'
      ;;
    go)
      RUNNER_RE='gotestsum|go test'; LANG_FLAG=go
      TESTFILE=slug_test.go; EXTRAFILE=extra_test.go
      FOREIGN='NotImplementedError
pytest
vitest
throw new Error'
      ;;
  esac
}

# --- Python (pytest in a venv)
python_stub() { printf 'def slugify(text):\n    raise NotImplementedError\n' > textutil.py; }
python_spec_test() { cat > tests/test_slug.py <<'PY'
from textutil import slugify


def test_slug_basic():
    assert slugify("Olá Mundo!") == "ola-mundo"


def test_slug_spaces():
    assert slugify("  a  b ") == "a-b"
PY
}
python_implement() { cat > textutil.py <<'PY'
import re
import unicodedata


def slugify(text):
    t = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-zA-Z0-9]+", "-", t).strip("-").lower()
PY
}
python_wrong_impl() { printf 'def slugify(text):\n    return text\n' > textutil.py; }
python_red_import() { python_spec_test; perl -pi -e 's/^from textutil import/from nope import/' tests/test_slug.py; }
python_passing_red() { cat > tests/test_slug.py <<'PY'
from textutil import slugify


def test_slug_exists():
    assert callable(slugify)
PY
}
python_cheat_edit() { perl -pi -e 's/^from textutil import slugify$/slugify = lambda t: "ola-mundo" if "Ol" in t else "a-b"/' tests/test_slug.py; }
python_cheat_index_edit() { perl -pi -e 's/== "ola-mundo"/== slugify("Olá Mundo!")/; s/== "a-b"/== slugify("  a  b ")/' tests/test_slug.py; }
python_skip_infile() { perl -pi -e 's/^def test_slug/\@__import__("pytest").mark.skip\ndef test_slug/' tests/test_slug.py; }
python_skip_cfg() { cat > conftest.py <<'PY'
import pytest


def pytest_collection_modifyitems(items):
    for it in items:
        if "slug" in it.nodeid:
            it.add_marker(pytest.mark.skip(reason="later"))
PY
}
python_deselect_cfg() { printf '[pytest]\naddopts = -k "not slug"\n' > pytest.ini; }
python_toml_cheat() { perl -pi -e 's/pytest/pytest --ignore=tests\/test_slug.py/ if !$done++' .shipcraft.toml; }
python_shout_stub() { printf 'def shout(text):\n    raise NotImplementedError\n' > shouty.py; }
python_shout_test() { printf 'from shouty import shout\n\n\ndef test_shout():\n    assert shout("hi") == "HI!"\n' > tests/test_shout.py; }
python_shout_impl() { printf 'def shout(text):\n    return text.upper() + "!"\n' > shouty.py; }
python_extra_test() { printf 'from textutil import slugify\n\n\ndef test_extra():\n    assert slugify("X Y") == "x-y"\n' > tests/test_extra.py; }
python_edit_extra() { perl -pi -e 's/"X Y"\) == "x-y"/"Z") == "z"/' tests/test_extra.py; }
python_append_old_test() { printf '\n\ndef test_slug_lower():\n    assert slugify("AB") == "ab"\n' >> tests/test_slug.py; }

# --- Node (TypeScript + vitest, installed in the target)
node_stub() { printf 'export const name = "textutil";\n\nexport function slugify(text: string): string {\n  throw new Error("not implemented: " + text);\n}\n' > src/textutil.ts; }
node_spec_test() { cat > src/slug.test.ts <<'TS'
import { describe, expect, it } from "vitest";
import { slugify } from "./textutil";

describe("slugify", () => {
  it("basic", () => {
    expect(slugify("Olá Mundo!")).toBe("ola-mundo");
  });
  it("spaces", () => {
    expect(slugify("  a  b ")).toBe("a-b");
  });
});
TS
}
node_implement() { cat > src/textutil.ts <<'TS'
export const name = "textutil";

export function slugify(text: string): string {
  return text
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .toLowerCase();
}
TS
}
node_wrong_impl() { printf 'export const name = "textutil";\n\nexport function slugify(text: string): string {\n  return text;\n}\n' > src/textutil.ts; }
node_red_import() { node_stub; node_spec_test; perl -pi -e 's|from "./textutil"|from "./nope"|' src/slug.test.ts; }
node_passing_red() { cat > src/slug.test.ts <<'TS'
import { expect, it } from "vitest";
import { slugify } from "./textutil";

it("slugify exists", () => {
  expect(typeof slugify).toBe("function");
});
TS
}
node_cheat_edit() { perl -pi -e 's|^import \{ slugify \} from "./textutil";$|const slugify = (t: string) => (t.includes("Ol") ? "ola-mundo" : "a-b");|' src/slug.test.ts; }
node_cheat_index_edit() { perl -pi -e 's/toBe\("ola-mundo"\)/toBe(slugify("Olá Mundo!"))/; s/toBe\("a-b"\)/toBe(slugify("  a  b "))/' src/slug.test.ts; }
node_skip_infile() { perl -pi -e 's/^  it\(/  it.skip(/' src/slug.test.ts; }
node_skip_cfg() { printf 'import { defineConfig } from "vitest/config";\nexport default defineConfig({ test: { testNamePattern: "^(?!slugify)" } });\n' > vitest.config.ts; }
node_deselect_cfg() { printf 'import { defineConfig } from "vitest/config";\nexport default defineConfig({ test: { exclude: ["**/node_modules/**", "src/slug.test.ts"] } });\n' > vitest.config.ts; }
node_toml_cheat() { perl -pi -e 's/vitest run/vitest run --exclude=src\/slug.test.ts/ if !$done++' .shipcraft.toml; }
node_shout_stub() { printf 'export function shout(text: string): string {\n  throw new Error("not implemented: " + text);\n}\n' > src/shout.ts; }
node_shout_test() { printf 'import { expect, it } from "vitest";\nimport { shout } from "./shout";\n\nit("shout", () => {\n  expect(shout("hi")).toBe("HI!");\n});\n' > src/shout.test.ts; }
node_shout_impl() { printf 'export function shout(text: string): string {\n  return text.toUpperCase() + "!";\n}\n' > src/shout.ts; }
node_extra_test() { printf 'import { expect, it } from "vitest";\nimport { slugify } from "./textutil";\n\nit("extra", () => {\n  expect(slugify("X Y")).toBe("x-y");\n});\n' > src/extra.test.ts; }
node_edit_extra() { perl -pi -e 's/slugify\("X Y"\)\)\.toBe\("x-y"\)/slugify("Z")).toBe("z")/' src/extra.test.ts; }
node_append_old_test() { printf '\ndescribe("more", () => {\n  it("lower", () => {\n    expect(slugify("AB")).toBe("ab");\n  });\n});\n' >> src/slug.test.ts; }

# --- Go (go test via gotestsum, installed into a temp GOBIN)
go_stub() { printf 'package textutil\n\n// Slugify is a stub.\nfunc Slugify(s string) string { return "" }\n' > textutil.go; }
go_spec_test() { cat > slug_test.go <<'GO'
package textutil

import "testing"

func TestSlugBasic(t *testing.T) {
	if got := Slugify("Olá Mundo!"); got != "ola-mundo" {
		t.Fatalf("Slugify = %q", got)
	}
}

func TestSlugSpaces(t *testing.T) {
	if got := Slugify("  a  b "); got != "a-b" {
		t.Fatalf("Slugify = %q", got)
	}
}
GO
}
go_implement() { cat > textutil.go <<'GO'
package textutil

import (
	"strings"
	"unicode"
)

var fold = strings.NewReplacer("á", "a", "à", "a", "ã", "a", "â", "a", "é", "e", "ê", "e",
	"í", "i", "ó", "o", "ô", "o", "õ", "o", "ú", "u", "ç", "c")

// Slugify lowercases, strips accents and joins words with hyphens.
func Slugify(s string) string {
	var b strings.Builder
	dash := false
	for _, r := range fold.Replace(strings.ToLower(s)) {
		if r < 128 && (unicode.IsLetter(r) || unicode.IsDigit(r)) {
			b.WriteRune(r)
			dash = false
		} else if !dash && b.Len() > 0 {
			b.WriteByte('-')
			dash = true
		}
	}
	return strings.TrimRight(b.String(), "-")
}
GO
}
go_wrong_impl() { printf 'package textutil\n\n// Slugify is wrong on purpose.\nfunc Slugify(s string) string { return s }\n' > textutil.go; }
go_red_import() { go_stub; go_spec_test; perl -0pi -e 's/import "testing"/import (\n\t"testing"\n\n\tnope "example.com\/textutil\/nope"\n)/; s/:= Slugify\(/:= nope.Slugify(/g' slug_test.go; }
go_passing_red() { printf 'package textutil\n\nimport "testing"\n\nfunc TestSlugExists(t *testing.T) {\n\t_ = Slugify("x")\n}\n' > slug_test.go; }
go_cheat_edit() { perl -pi -e 's/:= Slugify\(/:= fake(/' slug_test.go
  printf '\nfunc fake(s string) string {\n\treturn map[string]string{"Olá Mundo!": "ola-mundo", "  a  b ": "a-b"}[s]\n}\n' >> slug_test.go; }
go_cheat_index_edit() { perl -pi -e 's/got != "ola-mundo"/got != Slugify("Olá Mundo!")/; s/got != "a-b"/got != Slugify("  a  b ")/' slug_test.go; }
go_skip_infile() { perl -0pi -e 's/(func TestSlug\w+\(t \*testing\.T\) \{\n)/$1\tt.Skip("later")\n/g' slug_test.go; }
go_skip_cfg() { printf 'package textutil\n\nimport (\n\t"flag"\n\t"os"\n\t"testing"\n)\n\nfunc TestMain(m *testing.M) {\n\tflag.Parse()\n\t_ = flag.Set("test.skip", "^TestSlug")\n\tos.Exit(m.Run())\n}\n' > zz_main_test.go; }
go_deselect_cfg() { printf 'package textutil\n\nimport (\n\t"flag"\n\t"os"\n\t"testing"\n)\n\nfunc TestMain(m *testing.M) {\n\tflag.Parse()\n\t_ = flag.Set("test.run", "^TestPackageBuilds$")\n\tos.Exit(m.Run())\n}\n' > zz_main_test.go; }
go_toml_cheat() { perl -pi -e 's/\.\/\.\.\./-run TestPackageBuilds .\/.../ if !$done++' .shipcraft.toml; }
go_build_tag() { { printf '//go:build ignore\n\n'; cat slug_test.go; } > slug_test.go.new && mv slug_test.go.new slug_test.go; }
go_shout_stub() { printf 'package textutil\n\n// Shout is a stub.\nfunc Shout(s string) string { return "" }\n' > shout.go; }
go_shout_test() { printf 'package textutil\n\nimport "testing"\n\nfunc TestShout(t *testing.T) {\n\tif got := Shout("hi"); got != "HI!" {\n\t\tt.Fatalf("Shout = %%q", got)\n\t}\n}\n' > shout_test.go; }
go_shout_impl() { printf 'package textutil\n\nimport "strings"\n\n// Shout uppercases and adds a bang.\nfunc Shout(s string) string { return strings.ToUpper(s) + "!" }\n' > shout.go; }
go_extra_test() { printf 'package textutil\n\nimport "testing"\n\nfunc TestExtra(t *testing.T) {\n\tif got := Slugify("X Y"); got != "x-y" {\n\t\tt.Fatalf("Slugify = %%q", got)\n\t}\n}\n' > extra_test.go; }
go_edit_extra() { perl -pi -e 's/Slugify\("X Y"\); got != "x-y"/Slugify("Z"); got != "z"/' extra_test.go; }
go_append_old_test() { printf '\nfunc TestSlugLower(t *testing.T) {\n\tif got := Slugify("AB"); got != "ab" {\n\t\tt.Fatalf("Slugify = %%q", got)\n\t}\n}\n' >> slug_test.go; }

# ---------------------------------------------------------------- case list
case_list() { # case ids for language $1, in table order
  if [ "$1" = core ]; then core_cases; echo r-legacy-config-init r-legacy-config-check r-legacy-config-red r-legacy-config-ci r-legacy-config-coexists r-legacy-config-unstaged-hooks r-legacy-config-commit-msg; return; fi
  echo init-detect init-files init-workflow init-lang-flag
  echo honest-red honest-green honest-ci
  echo red-compile-error red-import-error red-already-passes red-twice
  echo red-commit-tests-changed red-commit-already-green
  echo edit-tree edit-index delete-test skip-in-file skip-config deselect-config
  [ "$1" = go ] && echo build-tag
  echo toml-change lock-delete lock-edit
  echo intermediate-red new-test-in-green two-branches after-closed-edit new-cycle-after-closed
  echo ci-edit ci-delete ci-skip-in-file ci-skip-config ci-deselect-config ci-toml-change
  echo ci-lock-delete ci-lock-edit ci-red-tests-changed ci-red-already-green ci-green-not-closed
  echo partial-stage-close
  lang_v1_cases "$1"
}

# ---------------------------------------------------------------- case helpers
L() { "${LP}_$1"; }
commit_all() { git add -A && git commit -q -m "$1"; }
commit_nv() { git add -A && git commit -q --no-verify -m "$1"; }
commit_index() { git commit -q -m "$1"; }

finish() { # finish PASS|FAIL
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$CASE" "$TL" "$EXPECT" "$OBS" "${LAST_RC:--}" "$1" > "$RESULT"
  if [ "$1" = PASS ] && [ "${SHIPCRAFT_ACCEPTANCE_KEEP:-0}" != 1 ]; then
    cd "$WORK" || exit 0
    chmod -R u+w "$CASE_T" "$CW" 2>/dev/null
    rm -rf "$CASE_T" "$CW"
  fi
  exit 0
}
fail() { OBS="$1"; echo "FAIL: $1" >> "$LOG"; finish FAIL; }
pass() { OBS="${1:-$EXPECT}"; finish PASS; }

head_rev() { git rev-parse -q --verify HEAD 2>/dev/null || echo none; }
run_cmd() { # sets RC, MOVED; output in $OUT
  local before after
  before=$(head_rev)
  "$@" > "$OUT" 2>&1; RC=$?
  after=$(head_rev)
  MOVED=no; [ "$before" != "$after" ] && MOVED=yes
  LAST_RC=$RC
  { printf '\n$ %s   [rc=%s, new commit=%s]\n' "$*" "$RC" "$MOVED"; cat "$OUT"; } >> "$LOG"
}
last_line() { grep '[^[:space:]]' "$OUT" | tail -n 1 | cut -c1-80; }

# must_accept <label> <cmd|commit> <command...>
must_accept() {
  local label="$1" kind="$2"; shift 2
  run_cmd "$@"
  [ "$RC" -eq 0 ] || fail "$label: refused (rc=$RC): $(last_line)"
  [ "$kind" = commit ] && [ "$MOVED" = no ] && fail "$label: rc 0 but no commit was made"
  return 0
}
# must_refuse <label> <cmd|commit> <command...>: also checks the three-line message
must_refuse() {
  local label="$1" kind="$2"; shift 2
  run_cmd "$@"
  [ "$RC" -ne 0 ] || fail "$label: accepted (rc=0)"
  [ "$kind" = commit ] && [ "$MOVED" = yes ] && fail "$label: rc $RC but the commit was made"
  msg_check || fail "$label: refused, but $MSGERR"
  return 0
}
# Rule 7: a refusal ends with three non-empty lines (what / why / how), and the
# hint does not name another language's stub or tools.
msg_check() {
  local n tok
  n=$(grep -c '[^[:space:]]' "$OUT")
  [ "$n" -ge 3 ] || { MSGERR="the message has $n non-empty line(s), want 3"; return 1; }
  grep '[^[:space:]]' "$OUT" | tail -n 3 > "$OUT.last3"
  if awk 'length($0) < 6 { bad = 1 } END { exit bad ? 0 : 1 }' "$OUT.last3"; then
    MSGERR="one of the last three lines is shorter than 6 chars"; return 1
  fi
  if [ "$(sort -u "$OUT.last3" | wc -l | tr -d ' ')" -ne 3 ]; then
    MSGERR="the last three lines are not three distinct lines"; return 1
  fi
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    if grep -F -q -- "$tok" "$OUT.last3"; then MSGERR="the $TL hint mentions '$tok'"; return 1; fi
  done <<EOF
$FOREIGN
EOF
  return 0
}

check() { # check <label> <command...>: a harness-side assertion
  local label="$1"; shift
  if "$@" >> "$LOG" 2>&1; then echo "ok: $label" >> "$LOG"; else fail "$label"; fi
}
changed() { [ -n "$(git status --porcelain)" ]; }
apply() { # apply <scenario fn>: and make sure it changed the tree (harness guard)
  L "$1"
  changed || { OBS="harness: scenario $1 changed nothing"; finish FAIL; }
}

lock_files_tree() { find .shipcraft/locks -type f -name '*.json' 2>/dev/null | sort; }
lock_files_head() { git ls-tree -r --name-only HEAD -- .shipcraft/locks 2>/dev/null | grep '\.json$'; }
count_lines() { grep -c . || true; }
lock_state() { # lock_state <json file or -> : prints open|closed|?
  "$PY" - "$1" <<'PY'
import json, sys
src = sys.stdin if sys.argv[1] == "-" else open(sys.argv[1])
try:
    d = json.load(src)
except Exception:
    print("invalid-json"); sys.exit(0)
v = None
if isinstance(d, dict):
    for k in ("state", "status", "estado"):
        if k in d:
            v = d[k]; break
    else:
        vals = [x for x in d.values() if x in ("open", "closed")]
        v = vals[0] if len(vals) == 1 else None
print(v if v in ("open", "closed") else "?")
PY
}
head_lock_state() { # the heredoc is python's stdin, so the JSON goes in a file
  local f; f=$(mktemp "$WORK/cw/headlock.XXXXXX") || return 1
  git show "HEAD:$1" > "$f"; lock_state "$f"; rm -f "$f"
}
one_lock_tree_state() { # one_lock_tree_state <open|closed>
  local f; f=$(lock_files_tree)
  [ "$(printf '%s\n' "$f" | count_lines)" -eq 1 ] || { echo "want exactly one lock in .shipcraft/locks, got: $f"; return 1; }
  [ "$(lock_state "$f")" = "$1" ] || { echo "lock $f state $(lock_state "$f"), want $1"; return 1; }
}
one_lock_head_state() {
  local f; f=$(lock_files_head)
  [ "$(printf '%s\n' "$f" | count_lines)" -eq 1 ] || { echo "want exactly one lock committed in HEAD, got: $f"; return 1; }
  [ "$(head_lock_state "$f")" = "$1" ] || { echo "HEAD lock $f state $(head_lock_state "$f"), want $1"; return 1; }
}
no_lock() { [ -z "$(lock_files_tree)" ]; }
tree_clean() { s=$(git status --porcelain); [ -z "$s" ] || { echo "dirty: $s"; return 1; }; }
head_lock_lacks() { ! git show "HEAD:$(lock_files_head)" | grep -F -q -- "$1"; }

setup_init() {
  must_accept "shipcraft init" cmd shipcraft init
  must_accept "commit of the init files" commit commit_all "chore: shipcraft init"
  BASE=$(head_rev)
}
setup_red() {
  setup_init
  L stub; L spec_test
  must_accept "shipcraft red" cmd shipcraft red
  must_accept "RED commit" commit commit_all "test: RED slugify"
}
# setup_nv <scenario...>: RED committed through the hook, then the cheat committed
# with --no-verify; the case then expects `shipcraft ci --base <before RED>` to refuse.
nv_then_ci() {
  must_accept "cheat committed with --no-verify (harness)" commit commit_nv "cheat"
  must_refuse "shipcraft ci --base <before RED>" cmd shipcraft ci --base "$BASE"
  pass
}

# ---------------------------------------------------------------- v1 library
. "$ACEITE/lib/v1.sh"
. "$ACEITE/lib/rename.sh"

# ---------------------------------------------------------------- cases
run_case() {
  case "$CASE" in r-legacy-config-*) rename_case; return ;; esac
  case "$CASE" in e1-*) english_case; return ;; esac
  local _item
  for _item in $ITEMS; do # the items in lib/item<N>.sh: v1-<N>.* goes to item<N>_case
    case "$CASE" in "v1-$_item."*) "item${_item}_case"; return ;; esac
  done
  case "$CASE" in
  init-detect)
    EXPECT="detects $TL"
    must_accept "shipcraft init" cmd shipcraft init
    check ".shipcraft.toml exists" test -f .shipcraft.toml
    check "init requires the package major/minor" eq "$(tget shipcraft_min)" "$(H toml-get "$ACEITE/../nucleo/Cargo.toml" package.version | cut -d. -f1,2)"
    check ".shipcraft.toml names the $TL runner ($RUNNER_RE)" grep -E -q "$RUNNER_RE" .shipcraft.toml
    pass ;;
  init-files)
    EXPECT="config, locks, hook and the AGENTS.md block only"
    find .git -type f ! -path '.git/objects/*' ! -path '.git/logs/*' | sort > "$CW/git.before"
    must_accept "shipcraft init" cmd shipcraft init
    find .git -type f ! -path '.git/objects/*' ! -path '.git/logs/*' | sort > "$CW/git.after"
    check ".shipcraft.toml created" test -f .shipcraft.toml
    check "init does not create .github" test ! -e .github
    check ".shipcraft/locks/ created" test -d .shipcraft/locks
    check "commit-msg hook installed and executable" test -x .git/hooks/commit-msg
    check "post-commit hook installed and executable" test -x .git/hooks/post-commit
    check "AGENTS.md carries the shipcraft block" grep -q -F '<!-- shipcraft -->' AGENTS.md
    extra=$(git status --porcelain --untracked-files=all | grep -v -E '^\?\? (\.shipcraft\.toml|\.shipcraft/locks/.*|AGENTS\.md)$')
    [ -z "$extra" ] || fail "init touched other files: $(printf '%s' "$extra" | tr '\n' ' ')"
    gitextra=$(comm -13 "$CW/git.before" "$CW/git.after" | grep -v -x -e '.git/hooks/commit-msg' -e '.git/hooks/post-commit')
    [ -z "$gitextra" ] || fail "init created other files in .git: $(printf '%s' "$gitextra" | tr '\n' ' ')"
    pass ;;
  init-workflow)
    EXPECT="no workflow or .github directory"
    must_accept "shipcraft init" cmd shipcraft init
    check "no .github created" test ! -e .github
    pass ;;
  init-lang-flag)
    EXPECT="--lang $LANG_FLAG accepted"
    if [ "$TL" = python ]; then # no marker left: only --lang can tell
      git rm -q requirements.txt && git commit -q -m "no marker" || fail "harness: could not drop requirements.txt"
    fi
    must_accept "shipcraft init --lang $LANG_FLAG" cmd shipcraft init --lang "$LANG_FLAG"
    check ".shipcraft.toml names the $TL runner ($RUNNER_RE)" grep -E -q "$RUNNER_RE" .shipcraft.toml
    pass ;;

  honest-red)
    EXPECT="accepted, lock open"
    setup_init
    L stub; L spec_test
    must_accept "shipcraft red" cmd shipcraft red
    check "shipcraft red wrote one open lock in .shipcraft/locks/" one_lock_tree_state open
    must_accept "RED commit (lock + tests)" commit commit_all "test: RED slugify"
    check "the RED commit carries the open lock" one_lock_head_state open
    check "the RED commit carries the test file" git cat-file -e "HEAD:$TESTFILE"
    pass ;;
  honest-green)
    EXPECT="accepted, lock closed"
    setup_red
    L implement
    must_accept "GREEN commit" commit commit_all "feat: slugify"
    check "the GREEN commit closed the lock itself" one_lock_head_state closed
    check "nothing left uncommitted after the GREEN" tree_clean
    pass ;;
  honest-ci)
    EXPECT="ci accepted"
    setup_red
    L implement
    must_accept "GREEN commit" commit commit_all "feat: slugify"
    must_accept "shipcraft ci --base <before RED>" cmd shipcraft ci --base "$BASE"
    pass ;;

  red-compile-error)
    EXPECT="refused, no lock"
    setup_init
    L spec_test   # no stub: the symbol does not exist
    must_refuse "shipcraft red (compile/import error)" cmd shipcraft red
    check "no lock written" no_lock
    pass ;;
  red-import-error)
    EXPECT="refused, no lock"
    setup_init
    L red_import
    must_refuse "shipcraft red (missing module)" cmd shipcraft red
    check "no lock written" no_lock
    pass ;;
  red-already-passes)
    EXPECT="refused, no lock"
    setup_init
    L stub; L passing_red
    must_refuse "shipcraft red (suite passes)" cmd shipcraft red
    check "no lock written" no_lock
    pass ;;
  red-twice)
    EXPECT="refused"
    setup_red
    L shout_stub; L shout_test
    must_refuse "second shipcraft red with a lock open" cmd shipcraft red
    check "still exactly one lock" one_lock_tree_state open
    pass ;;
  red-commit-tests-changed)
    EXPECT="refused"
    setup_init
    L stub; L spec_test
    must_accept "shipcraft red" cmd shipcraft red
    apply cheat_edit
    must_refuse "RED commit with tests changed after shipcraft red" commit commit_all "test: RED"
    pass ;;
  red-commit-already-green)
    EXPECT="refused"
    setup_init
    L stub; L spec_test
    must_accept "shipcraft red" cmd shipcraft red
    L implement
    must_refuse "RED commit whose suite passes" commit commit_all "test: RED"
    pass ;;

  edit-tree)
    # ADAPTED by v1, item 6, rule 1 ("files outside the commit do not block and do not
    # affect the result"): in v0 a tree-only edit was refused; in v1 the hook judges
    # the index, so the commit goes through, with the original test, and the lock closes.
    EXPECT="accepted (v1): unstaged edit ignored"
    setup_red
    cp "$TESTFILE" "$CW/orig"
    L implement; git add -A
    apply cheat_edit   # edited in the tree only, not staged
    must_accept "commit with the locked test edited only in the tree" commit commit_index "feat"
    check "the commit holds the locked test as locked" sh -c "git show 'HEAD:$TESTFILE' | cmp -s - '$CW/orig'"
    check "the commit closed the lock (the index passes)" one_lock_head_state closed
    check "the unstaged edit is still in the tree, untouched" sh -c "! cmp -s '$TESTFILE' '$CW/orig'"
    pass ;;
  edit-index)
    EXPECT="refused"
    setup_red
    L implement
    cp "$TESTFILE" "$CW/orig"
    L cheat_index_edit
    git add -A
    cp "$CW/orig" "$TESTFILE"
    git diff --cached --quiet -- "$TESTFILE" && fail "harness: the index edit did not stick"
    must_refuse "commit with the locked test edited in the index only" commit commit_index "feat"
    pass ;;
  delete-test)
    EXPECT="refused"
    setup_red
    rm -f "$TESTFILE"
    must_refuse "commit deleting the locked test" commit commit_all "cheat"
    pass ;;
  skip-in-file)
    EXPECT="refused"
    setup_red
    apply skip_infile
    must_refuse "commit skipping the locked tests in the file" commit commit_all "cheat"
    pass ;;
  skip-config)
    EXPECT="refused"
    setup_red
    apply skip_cfg
    must_refuse "commit skipping the locked tests via config" commit commit_all "cheat"
    pass ;;
  deselect-config)
    EXPECT="refused"
    setup_red
    apply deselect_cfg
    must_refuse "commit deselecting the locked tests via config" commit commit_all "cheat"
    pass ;;
  build-tag)
    EXPECT="refused"
    setup_red
    apply build_tag
    must_refuse "commit with //go:build ignore on the locked test" commit commit_all "cheat"
    pass ;;
  toml-change)
    EXPECT="refused"
    setup_red
    L implement
    cp .shipcraft.toml "$CW/toml.orig"
    L toml_cheat
    cmp -s .shipcraft.toml "$CW/toml.orig" && printf '\n# changed\n' >> .shipcraft.toml
    must_refuse "commit changing .shipcraft.toml" commit commit_all "cheat"
    pass ;;
  lock-delete)
    EXPECT="refused"
    setup_red
    L implement
    lf=$(lock_files_tree); [ -n "$lf" ] || fail "harness: no lock file to delete"
    rm -f $lf
    must_refuse "commit deleting the lock" commit commit_all "cheat"
    pass ;;
  lock-edit)
    EXPECT="refused"
    setup_red
    lf=$(lock_files_tree); [ -n "$lf" ] || fail "harness: no lock file to edit"
    perl -pi -e 's/"open"/"closed"/g' $lf
    changed || fail "harness: no \"open\" value found in the lock to hand-edit"
    must_refuse "commit with the lock hand-edited to closed" commit commit_all "cheat"
    pass ;;

  intermediate-red)
    EXPECT="accepted, stays open"
    setup_red
    L wrong_impl
    must_accept "intermediate commit, suite still red" commit commit_all "wip"
    check "the lock is still open" one_lock_head_state open
    L implement
    must_accept "GREEN commit" commit commit_all "feat"
    check "the GREEN commit closed the lock" one_lock_head_state closed
    must_accept "shipcraft ci over RED, wip, GREEN" cmd shipcraft ci --base "$BASE"
    pass ;;
  new-test-in-green)
    EXPECT="accepted, not locked"
    setup_red
    L extra_test
    must_accept "commit adding a new test file (lock open)" commit commit_all "test: extra"
    check "the lock is still open" one_lock_head_state open
    check "the open lock does not list the new test file" head_lock_lacks "$(basename "$EXTRAFILE")"
    L edit_extra
    must_accept "commit editing the new (unlocked) test file" commit commit_all "test: extra edited"
    L implement
    must_accept "GREEN commit" commit commit_all "feat"
    check "the GREEN commit closed the lock" one_lock_head_state closed
    check "the lock still does not list the new test file" head_lock_lacks "$(basename "$EXTRAFILE")"
    must_accept "shipcraft ci over the range" cmd shipcraft ci --base "$BASE"
    pass ;;
  two-branches)
    EXPECT="independent locks"
    setup_red
    lock_a=$(lock_files_head)
    git checkout -q -b other "$BASE" || fail "harness: checkout"
    L shout_stub; L shout_test
    must_accept "shipcraft red on another branch while main has an open lock" cmd shipcraft red
    must_accept "RED commit on the other branch" commit commit_all "test: RED shout"
    check "the other branch holds exactly its own open lock" one_lock_head_state open
    lock_b=$(lock_files_head)
    [ "$lock_a" != "$lock_b" ] || fail "both branches use the same lock file $lock_a"
    git checkout -q main || fail "harness: checkout main"
    L implement
    must_accept "GREEN on main" commit commit_all "feat: slugify"
    check "main's lock closed" one_lock_head_state closed
    git checkout -q other || fail "harness: checkout other"
    check "the other branch's lock is still open" one_lock_head_state open
    L shout_impl
    must_accept "GREEN on the other branch" commit commit_all "feat: shout"
    check "the other branch's lock closed" one_lock_head_state closed
    git checkout -q main || fail "harness: checkout main"
    must_accept "merge of the two branches (no lock conflict)" commit git merge -q --no-edit other
    pass ;;
  after-closed-edit)
    EXPECT="accepted"
    setup_red
    L implement
    must_accept "GREEN commit" commit commit_all "feat"
    L append_old_test
    must_accept "commit editing a test of a closed lock" commit commit_all "test: more"
    pass ;;
  new-cycle-after-closed)
    EXPECT="accepted, 2nd lock"
    setup_red
    L implement
    must_accept "GREEN commit" commit commit_all "feat"
    L shout_stub; L shout_test
    must_accept "shipcraft red for a new cycle" cmd shipcraft red
    must_accept "RED commit of the new cycle" commit commit_all "test: RED shout"
    n=$(lock_files_head | count_lines)
    [ "$n" -eq 2 ] || fail "want 2 lock files after two cycles, got $n"
    pass ;;

  ci-edit)          EXPECT="ci refused"; setup_red; apply cheat_edit; nv_then_ci ;;
  ci-delete)        EXPECT="ci refused"; setup_red; rm -f "$TESTFILE"; nv_then_ci ;;
  ci-skip-in-file)  EXPECT="ci refused"; setup_red; apply skip_infile; nv_then_ci ;;
  ci-skip-config)   EXPECT="ci refused"; setup_red; apply skip_cfg; nv_then_ci ;;
  ci-deselect-config) EXPECT="ci refused"; setup_red; apply deselect_cfg; nv_then_ci ;;
  ci-toml-change)
    EXPECT="ci refused"; setup_red; L implement
    cp .shipcraft.toml "$CW/toml.orig"; L toml_cheat
    cmp -s .shipcraft.toml "$CW/toml.orig" && printf '\n# changed\n' >> .shipcraft.toml
    nv_then_ci ;;
  ci-lock-delete)
    EXPECT="ci refused"; setup_red; L implement
    lf=$(lock_files_tree); [ -n "$lf" ] || fail "harness: no lock file to delete"
    rm -f $lf; nv_then_ci ;;
  ci-lock-edit)
    EXPECT="ci refused"; setup_red
    lf=$(lock_files_tree); [ -n "$lf" ] || fail "harness: no lock file to edit"
    perl -pi -e 's/"open"/"closed"/g' $lf
    changed || fail "harness: no \"open\" value found in the lock to hand-edit"
    nv_then_ci ;;
  ci-red-tests-changed)
    EXPECT="ci refused"; setup_init; L stub; L spec_test
    must_accept "shipcraft red" cmd shipcraft red
    L cheat_edit; nv_then_ci ;;
  ci-red-already-green)
    EXPECT="ci refused"; setup_init; L stub; L spec_test
    must_accept "shipcraft red" cmd shipcraft red
    L implement; nv_then_ci ;;
  ci-green-not-closed)
    EXPECT="ci refused"; setup_red; L implement; nv_then_ci ;;

  partial-stage-close)
    # Rule 3: the lock closes in the commit whose committed code passes. Staged:
    # a wrong implementation; unstaged: the right one. The commit may be refused
    # or accepted with the lock still open, never committed with it closed.
    EXPECT="not closed; fix+ci ok"
    setup_red
    L wrong_impl; git add -A
    L implement   # in the tree only, not staged
    git diff --quiet && fail "harness: the unstaged implementation did not stick"
    run_cmd commit_index "feat: staged implementation still fails"
    if [ "$MOVED" = yes ]; then
      [ "$RC" -eq 0 ] || fail "partial-stage commit: rc $RC but the commit was made"
      check "the commit of a failing staged implementation keeps the lock open" one_lock_head_state open
    else
      [ "$RC" -ne 0 ] || fail "partial-stage commit: rc 0 but no commit was made"
      msg_check || fail "partial-stage commit: refused, but $MSGERR"
      check "the refused commit left the lock open" one_lock_head_state open
    fi
    L implement
    must_accept "later fix commit" commit commit_all "fix: slugify"
    check "the fix commit closed the lock" one_lock_head_state closed
    must_accept "shipcraft ci --base <before RED>" cmd shipcraft ci --base "$BASE"
    pass ;;

  *) run_case_v1 ;;
  esac
}

# Library mode, for checking the scenarios by hand.
if [ "${SHIPCRAFT_ACCEPTANCE_LIB:-}" = 1 ]; then return 0 2>/dev/null || exit 0; fi

# ---------------------------------------------------------------- one case (child process)
if [ "${1:-}" = __case ]; then
  TL="$2"; IDX="$3"; CASE="$4"
  LP="$TL"; [ "$TL" = core ] && LP=python   # core runs on the Python target
  lang_vars "$LP"
  RESULT="$WORK/results/$TL.$IDX.$CASE"
  [ -n "${SHIPCRAFT_ACCEPTANCE_JUNIT:-}" ] && perl -MTime::HiRes=time -e 'printf "%.3f\n", time' > "$WORK/starts/$TL.$IDX.$CASE"
  LOG="$WORK/logs/$TL-$CASE.log"
  CW="$WORK/cw/$TL-$CASE"; mkdir -p "$CW"
  OUT="$CW/out"
  EXPECT="?"; OBS="harness: case did not finish"; LAST_RC=""
  CASE_T="$WORK/t/$TL-$CASE"; T="$CASE_T"
  copy_base "$WORK/base/$LP" "$T" || { OBS="harness: copy of the base target failed"; finish FAIL; }
  cd "$T" || exit 1
  if [ "$LP" = python ]; then
    # Same-size stub/implementation edits can share Python's cached timestamp.
    export PYTHONDONTWRITEBYTECODE=1
    export VIRTUAL_ENV="$T/.venv"; PATH="$T/.venv/bin:$PATH"; export PATH
  fi
  echo "# $TL $CASE in $T" > "$LOG"
  if [ "$TL" = core ]; then # the queue is per machine (per HOME): each core case gets its own machine
    mkdir -p "$CW/home/.config" "$CW/tmp"
    cp "$GIT_CONFIG_GLOBAL" "$CW/home/.gitconfig"
    export HOME="$CW/home" XDG_CONFIG_HOME="$CW/home/.config" XDG_STATE_HOME="$CW/home/.state" \
      XDG_DATA_HOME="$CW/home/.local/share" GIT_CONFIG_GLOBAL="$CW/home/.gitconfig" TMPDIR="$CW/tmp"
  fi
  run_case
  exit 0
fi

# ---------------------------------------------------------------- driver
# The whole run goes under nice (children inherit it).
if [ -z "${SHIPCRAFT_ACCEPTANCE_NICED:-}" ]; then
  export SHIPCRAFT_ACCEPTANCE_NICED=1
  exec nice -n 10 bash "$SELF" "$@"
fi

usage() { echo "usage: $0 <path-to-shipcraft-binary> [core|python|node|go|all]" >&2; exit 2; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
BIN="$1"; WHICH="${2:-all}"
JUNIT="${SHIPCRAFT_ACCEPTANCE_JUNIT:-}"
case "$JUNIT" in ''|/*) ;; *) JUNIT="$(pwd)/$JUNIT" ;; esac
[ -n "$JUNIT" ] && export SHIPCRAFT_ACCEPTANCE_JUNIT="$JUNIT"
case "$WHICH" in core|python|node|go) LANGS="$WHICH" ;; all) LANGS="core python node go" ;; *) usage ;; esac
BUILD_LANGS=$(printf '%s\n' $LANGS | sed 's/^core$/python/' | awk '!seen[$0]++' | tr '\n' ' ')
if [ ! -f "$BIN" ] || [ ! -x "$BIN" ]; then
  echo "run.sh: the shipcraft binary '$BIN' does not exist or is not executable; no case ran." >&2
  echo "run.sh: build the shipcraft binary first (see acceptance/README.md)." >&2
  exit 2
fi
case "$BIN" in /*) ;; *) BIN="$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")" ;; esac

for tool in git perl python3 xargs; do
  command -v "$tool" >/dev/null 2>&1 || { echo "run.sh: missing tool: $tool" >&2; exit 2; }
done
for l in $BUILD_LANGS; do
  case "$l" in
    node) for tool in node npm; do command -v $tool >/dev/null 2>&1 || { echo "run.sh: missing tool for node: $tool" >&2; exit 2; }; done ;;
    go) command -v go >/dev/null 2>&1 || { echo "run.sh: missing tool for go: go" >&2; exit 2; } ;;
  esac
done

JOBS="${SHIPCRAFT_ACCEPTANCE_JOBS:-4}"
case "$JOBS" in ''|*[!0-9]*) JOBS=4 ;; esac
[ "$JOBS" -gt 4 ] && JOBS=4
[ "$JOBS" -lt 1 ] && JOBS=1

# Capture before the harness isolates HOME and tool configuration.
. "$ACEITE/reuso.sh"
REUSE_REPO="$(git -C "$ACEITE" rev-parse --show-toplevel)"
REUSE_HOME="$HOME"
REUSE_XDG="${XDG_CONFIG_HOME:-$HOME/.config}"
REUSE_GH="$(command -v gh || true)"
REUSE_SHA="$(git -C "$REUSE_REPO" rev-parse HEAD)"
REUSE_ID="$(acceptance_tree_id "$REUSE_REPO" HEAD)"
REUSE_CLEAN="$(git -C "$REUSE_REPO" status --porcelain --untracked-files=all -- nucleo/ acceptance/)" || REUSE_CLEAN=unknown
REUSE_START=$(date +%s)

TMPROOT="${TMPDIR:-/tmp}"; TMPROOT="${TMPROOT%/}/shipcraft.noindex"
mkdir -p "$TMPROOT" || exit 2
# Earlier runs leave logs and failed cases (about 1.5 GB for a failing full run), and a
# killed run leaves everything. Remove work dirs older than the retention whose run is gone.
# Metric: $TMPROOT size; 30 GB had piled up by 2026-10-28. Revert: drop this block.
RETAIN_H="${SHIPCRAFT_ACCEPTANCE_RETAIN_HOURS:-24}"
case "$RETAIN_H" in ''|*[!0-9]*|?????*) RETAIN_H=24 ;; esac
RETAIN_M=$(( 10#$RETAIN_H * 60 ))
# A dir is stale only when nothing in it changed within the retention (a live run writes logs)
# and its run.pid, when there is one, is not alive. The glob cannot split a name.
for old in "$TMPROOT"/shipcraft-acceptance.*; do
  [ -d "$old" ] && [ ! -L "$old" ] || continue
  recent=$(find "$old" -mmin -"$RETAIN_M" -print 2>/dev/null) || continue
  [ -z "$recent" ] || continue
  owner=$(cat "$old/run.pid" 2>/dev/null)
  case "$owner" in ''|*[!0-9]*) ;; *) kill -0 "$owner" 2>/dev/null && continue ;; esac
  chmod -R u+w "$old" 2>/dev/null; rm -rf "$old"
done
WORK=$(mktemp -d "$TMPROOT/shipcraft-acceptance.XXXXXX") || { echo "run.sh: mktemp failed" >&2; exit 2; }
WORK=$(cd "$WORK" && pwd -P)
echo $$ > "$WORK/run.pid"
# Dependency installers and Python tempfile must use the same confined work root.
mkdir -p "$WORK/tmp" || exit 2
export TMPDIR="$WORK/tmp"
cleanup() {
  cd / 2>/dev/null
  if [ "${SHIPCRAFT_ACCEPTANCE_KEEP:-0}" = 1 ]; then echo "run.sh: work dir kept: $WORK"; return; fi
  local d
  for d in base bin cache home shadow toolvenv tmp; do
    chmod -R u+w "$WORK/$d" 2>/dev/null; rm -rf "$WORK/$d"
  done
  echo "run.sh: logs and failed cases kept: $WORK"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$WORK/bin" "$WORK/home" "$WORK/base" "$WORK/t" "$WORK/cw" "$WORK/logs" "$WORK/results"
[ -n "$JUNIT" ] && mkdir -p "$WORK/starts" && : > "$WORK/skipped"
ln -s "$BIN" "$WORK/bin/shipcraft"
CACHE="${SHIPCRAFT_ACCEPTANCE_CACHE:-$WORK/cache}"
case "$CACHE" in /*) ;; *) echo "run.sh: SHIPCRAFT_ACCEPTANCE_CACHE must be absolute" >&2; exit 2 ;; esac
mkdir -p "$CACHE"

# Isolation: no tool may write to the real HOME or read the user's git config.
export WORK
export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" XDG_CACHE_HOME="$CACHE/xdg"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$WORK/home/.gitconfig"
export GIT_AUTHOR_NAME="shipcraft acceptance" GIT_AUTHOR_EMAIL="shipcraft-acceptance@example.invalid"
export GIT_COMMITTER_NAME="shipcraft acceptance" GIT_COMMITTER_EMAIL="shipcraft-acceptance@example.invalid"
export PIP_CACHE_DIR="$CACHE/pip" PIP_DISABLE_PIP_VERSION_CHECK=1
export npm_config_cache="$CACHE/npm" npm_config_update_notifier=false npm_config_fund=false npm_config_audit=false
export GOPATH="$CACHE/gopath" GOMODCACHE="$CACHE/gopath/pkg/mod" GOCACHE="$CACHE/gocache" GOBIN="$CACHE/gobin"
export GOTOOLCHAIN=local GOFLAGS="-p=2" CGO_ENABLED=0
# v1 cases run with a PATH where no real gh, codex, claude or gemini is visible: each
# directory of the original PATH that holds one of them is replaced by a mirror of
# symlinks without them (the stubs are put first in the PATH of each case).
mkdir -p "$WORK/shadow"
CLEAN_REST=""
_i=0
_oldifs="$IFS"; IFS=:
for _d in $PATH; do
  [ -d "$_d" ] || continue
  _hit=0
  for _n in gh codex claude gemini; do [ -e "$_d/$_n" ] && _hit=1; done
  if [ "$_hit" = 1 ]; then
    _i=$((_i + 1)); mkdir -p "$WORK/shadow/$_i"
    for _f in "$_d"/*; do
      _b="${_f##*/}"
      case "$_b" in gh|codex|claude|gemini) continue ;; esac
      ln -s "$_f" "$WORK/shadow/$_i/$_b" 2>/dev/null
    done
    _d="$WORK/shadow/$_i"
  fi
  CLEAN_REST="${CLEAN_REST:+$CLEAN_REST:}$_d"
done
IFS="$_oldifs"
export CLEAN_REST
export PATH="$WORK/bin:$GOBIN:$PATH"
export ACEITE
printf '[init]\n\tdefaultBranch = main\n[user]\n\tname = shipcraft acceptance\n\temail = shipcraft-acceptance@example.invalid\n' > "$GIT_CONFIG_GLOBAL"
cd "$WORK" || exit 2

echo "run.sh: shipcraft = $BIN; languages = $LANGS; jobs = $JOBS; work dir = $WORK"

# A small venv for the harness itself (PyYAML to validate the generated workflow).
python3 -m venv "$WORK/toolvenv" >/dev/null 2>&1 \
  && "$WORK/toolvenv/bin/python" -m pip install -q pyyaml tomli >/dev/null 2>&1 \
  || { echo "run.sh: could not set up the harness venv (python3 -m venv + pip install pyyaml tomli)" >&2; exit 2; }
export PY="$WORK/toolvenv/bin/python"

# ---- target builders: one base per language; each case gets its own copy.
git_seed() { git init -q && git checkout -q -b main 2>/dev/null; git config user.name "shipcraft acceptance"; git config user.email "shipcraft-acceptance@example.invalid"; }
build_python() (
  d="$WORK/base/python"; mkdir -p "$d/tests" && cd "$d" || exit 1
  git_seed
  python3 -m venv .venv || exit 1
  .venv/bin/python -m pip install -q pytest || exit 1
  printf 'pytest\n' > requirements.txt
  printf '"""Text utilities (stub)."""\n' > textutil.py
  : > tests/__init__.py
  printf 'import textutil\n\n\ndef test_module_imports():\n    assert textutil is not None\n' > tests/test_smoke.py
  printf '.venv/\n__pycache__/\n.pytest_cache/\n' > .gitignore
  git add -A && git commit -q -m "initial project"
)
build_node() (
  d="$WORK/base/node"; mkdir -p "$d/src" && cd "$d" || exit 1
  git_seed
  printf '{\n  "name": "textutil",\n  "private": true,\n  "type": "module"\n}\n' > package.json
  npm install -D --no-audit --no-fund --loglevel=error "vitest@${SHIPCRAFT_VITEST_VERSION:-5.0.4}" "typescript@${SHIPCRAFT_TS_VERSION:-7.0.2}" >/dev/null || exit 1
  cat > tsconfig.json <<'JSON'
{
  "compilerOptions": {
    "target": "es2022",
    "module": "esnext",
    "moduleResolution": "bundler",
    "strict": true,
    "noEmit": true,
    "skipLibCheck": true,
    "types": []
  },
  "include": ["src"]
}
JSON
  printf '// Text utilities (stub).\nexport const name = "textutil";\n' > src/textutil.ts
  printf 'import { expect, it } from "vitest";\nimport * as textutil from "./textutil";\n\nit("module imports", () => {\n  expect(textutil.name).toBe("textutil");\n});\n' > src/smoke.test.ts
  printf 'node_modules/\n' > .gitignore
  git add -A && git commit -q -m "initial project"
)
build_go() (
  if [ ! -x "$GOBIN/gotestsum" ]; then
    go install gotest.tools/gotestsum@"${SHIPCRAFT_GOTESTSUM_VERSION:-v1.13.0}" || exit 1
  fi
  d="$WORK/base/go"; mkdir -p "$d" && cd "$d" || exit 1
  git_seed
  printf 'module example.com/textutil\n\ngo 1.21\n' > go.mod
  printf '// Package textutil: text utilities (stub).\npackage textutil\n' > textutil.go
  printf 'package textutil\n\nimport "testing"\n\nfunc TestPackageBuilds(t *testing.T) {}\n' > smoke_test.go
  git add -A && git commit -q -m "initial project"
)
for l in $BUILD_LANGS; do
  echo "run.sh: building the $l base target"
  if ! "build_$l" > "$WORK/logs/build-$l.log" 2>&1; then
    echo "run.sh: the $l target builder failed; log follows" >&2
    cat "$WORK/logs/build-$l.log" >&2
    exit 2
  fi
done

# ---- run the cases, at most $JOBS at a time, each under nice.
: > "$WORK/plan"
# SHIPCRAFT_ACCEPTANCE_SHARD=k/n runs every n-th case starting at the k-th (round robin over all
# languages), so CI can split the battery across n machines. A sharded run never saves a reuse result.
SHARD_K=0; SHARD_N=1; g=0
if [ -n "${SHIPCRAFT_ACCEPTANCE_SHARD:-}" ]; then
  SHARD_K=${SHIPCRAFT_ACCEPTANCE_SHARD%/*}; SHARD_N=${SHIPCRAFT_ACCEPTANCE_SHARD#*/}
  case "$SHARD_K/$SHARD_N" in *[!0-9/]*|/*|*/) echo "run.sh: SHIPCRAFT_ACCEPTANCE_SHARD must be k/n" >&2; exit 2 ;; esac
  [ "$SHARD_K" -ge 1 ] && [ "$SHARD_K" -le "$SHARD_N" ] || { echo "run.sh: shard k must be 1..n" >&2; exit 2; }
fi
for l in $LANGS; do
  i=0
  for c in $(case_list "$l"); do
    i=$((i + 1)); g=$((g + 1))
    if [ "$SHARD_N" -gt 1 ] && [ $(( (g - 1) % SHARD_N + 1 )) -ne "$SHARD_K" ]; then
      [ -n "$JUNIT" ] && echo "$l $c" >> "$WORK/skipped"; continue
    fi
    if [ -n "${SHIPCRAFT_ACCEPTANCE_CASES:-}" ]; then
      case " $SHIPCRAFT_ACCEPTANCE_CASES " in *" $c "*) ;; *) [ -n "$JUNIT" ] && echo "$l $c" >> "$WORK/skipped"; continue ;; esac
    fi
    printf '%s %03d %s\n' "$l" "$i" "$c" >> "$WORK/plan"
  done
done
total=$(grep -c . "$WORK/plan")
echo "run.sh: running $total cases"
xargs -P "$JOBS" -L 1 "$WORK/toolvenv/bin/python" "$ACEITE/tools/tmo.py" "${SHIPCRAFT_ACCEPTANCE_CASE_TIMEOUT:-900}" bash "$SELF" __case < "$WORK/plan"

# ---- report
pass=0; failn=0
printf '\n%-28s | %-8s | %-25s | %-60s | %-4s | %s\n' case language expected observed exit result
printf '%s\n' "-----------------------------+----------+---------------------------+--------------------------------------------------------------+------+-------"
while read -r l i c; do
  f="$WORK/results/$l.$i.$c"
  if [ -f "$f" ]; then
    IFS="$(printf '\t')" read -r rc_case rc_lang rc_exp rc_obs rc_exit rc_res < "$f"
  else
    rc_exp="?"; rc_obs="harness: no result (crash or timeout)"; rc_exit="-"; rc_res=FAIL
  fi
  [ "$rc_res" = PASS ] && pass=$((pass + 1)) || failn=$((failn + 1))
  printf '%-28s | %-8s | %-25s | %-60.60s | %-4s | %s\n' "$c" "$l" "$rc_exp" "$rc_obs" "$rc_exit" "$rc_res"
done < "$WORK/plan"
echo
for l in $LANGS; do
  lp=$(grep "^$l " "$WORK/plan" | while read -r a b c; do f="$WORK/results/$a.$b.$c"; [ -f "$f" ] && cut -f6 "$f"; done | grep -c '^PASS$')
  lt=$(grep -c "^$l " "$WORK/plan")
  echo "run.sh: $l: $lp of $lt cases pass"
done

if [ "$failn" -gt 0 ] && { [ "${SHIPCRAFT_ACCEPTANCE_VERBOSE:-0}" = 1 ] || [ "${GITHUB_ACTIONS:-}" = true ]; }; then
  while read -r l i c; do
    f="$WORK/results/$l.$i.$c"
    [ -f "$f" ] && [ "$(cut -f6 "$f")" = PASS ] && continue
    echo; echo "===== $l $c (log tail) ====="; tail -n 25 "$WORK/logs/$l-$c.log" 2>/dev/null
  done < "$WORK/plan"
fi
if [ -n "$JUNIT" ]; then
  python3 "$ACEITE/tools/junit.py" "$WORK" "$JUNIT" "${SHIPCRAFT_ACCEPTANCE_CASE_TIMEOUT:-900}" \
    && echo "run.sh: JUnit: $JUNIT" || echo "run.sh: warning: JUnit was not written to $JUNIT" >&2
fi
# Only a complete green run of an unchanged, committed tree is reusable.
if [ "${SHIPCRAFT_ACCEPTANCE_REUSE:-1}" != 0 ] && [ "$WHICH" = all ] \
  && [ -z "${SHIPCRAFT_ACCEPTANCE_CASES:-}" ] && [ -z "${SHIPCRAFT_ACCEPTANCE_SHARD:-}" ] && [ "$failn" -eq 0 ] \
  && [ "$pass" -eq "$total" ] && [ "$total" -gt 0 ] \
  && [ -n "$REUSE_ID" ] && [ -z "$REUSE_CLEAN" ] \
  && [ "$(git -C "$REUSE_REPO" rev-parse HEAD)" = "$REUSE_SHA" ] \
  && REUSE_FINAL_CLEAN="$(git -C "$REUSE_REPO" status --porcelain --untracked-files=all -- nucleo/ acceptance/)" \
  && [ -z "$REUSE_FINAL_CLEAN" ]; then
  REUSE_SECONDS=$(( $(date +%s) - REUSE_START ))
  if python3 - "$REUSE_HOME/.cache/shipcraft-acceptance" "$REUSE_ID" "$REUSE_SHA" "$total" "$REUSE_SECONDS" <<'PY_CACHE'
import datetime, json, os, sys, tempfile
folder, tree, sha, total, seconds = sys.argv[1:]
try:
    os.makedirs(folder, exist_ok=True)
    fd, path = tempfile.mkstemp(prefix='.result-', dir=folder)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(dict(tree=tree, sha=sha, total=int(total), passed=int(total),
                           seconds=int(seconds), state='success',
                           date=datetime.datetime.now(datetime.timezone.utc).isoformat()), f)
        os.replace(path, os.path.join(folder, tree))
    finally:
        if os.path.exists(path): os.unlink(path)
except OSError:
    sys.exit(1)
PY_CACHE
  then
    echo "run.sh: result saved: $REUSE_ID ($total/$total, $REUSE_SECONDS s)"
    HOME="$REUSE_HOME" XDG_CONFIG_HOME="$REUSE_XDG" python3 - "$REUSE_GH" "$REUSE_SHA" "$total" "$REUSE_SECONDS" <<'PY_STATUS'
import subprocess, sys
try:
    subprocess.run([sys.argv[1], 'api', 'repos/victorassisalves/shipcraft-v2/statuses/' + sys.argv[2],
                    '-f', 'state=success', '-f', 'context=acceptance/local',
                    '-f', f'description={sys.argv[3]}/{sys.argv[3]} local, {sys.argv[4]} s'],
                   timeout=10, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
except (OSError, subprocess.SubprocessError):
    print('run.sh: warning: acceptance/local status was not published (gh failed or commit unavailable).')
PY_STATUS
  else
    echo "run.sh: warning: local result was not saved."
  fi
fi
cleanup
trap - EXIT
echo "run.sh: total: $pass of $total cases pass"
[ "$failn" -eq 0 ] && [ "$pass" -eq "$total" ] && [ "$total" -gt 0 ]
