#!/usr/bin/env bash
# acceptance/shipcraft.sh <junit>: Shipcraft's own suite adapter.
# Builds the judged core, translates NUL-terminated SHIPCRAFT_CASES IDs into
# profile/case selection, and writes one JUnit testcase per stable case ID.
# Shipcraft judges the report, never the process exit code.
# Unset or empty SHIPCRAFT_CASES runs all profiles. Both list variables are
# removed before case execution. Dependency cache defaults to
# ~/.cache/shipcraft-acceptance-deps; reuse recording defaults to off here.
set -u

[ $# -eq 1 ] || { echo "usage: acceptance/shipcraft.sh <junit>" >&2; exit 2; }
JUNIT="$1"
case "$JUNIT" in /*) ;; *) JUNIT="$(pwd)/$JUNIT" ;; esac
ACEITE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$ACEITE/.." && pwd)"

CASES=""; WHICH=all
if [ -n "${SHIPCRAFT_CASES:-}" ]; then
  if [ -r "$SHIPCRAFT_CASES" ]; then
    profiles=""
    while IFS= read -r -d '' id; do
      case "$id" in
        *::*) p="${id%%::*}"; name="${id#*::}" ;;
        *) p=""; name="$id" ;;
      esac
      [ -n "$name" ] || continue
      CASES="$CASES $name"
      case " $profiles " in *" $p "*) ;; *) profiles="$profiles $p" ;; esac
    done < "$SHIPCRAFT_CASES"
    case "$profiles" in
      " core"|" python"|" node"|" go") WHICH="${profiles# }" ;;
    esac
  else
    echo "acceptance/shipcraft.sh: warning: cannot read SHIPCRAFT_CASES ($SHIPCRAFT_CASES); running the full battery." >&2
  fi
fi
unset SHIPCRAFT_CASES SHIPCRAFT_FILES

TARGET="${CARGO_TARGET_DIR:-target}"
case "$TARGET" in /*) ;; *) TARGET="$ROOT/nucleo/$TARGET" ;; esac
(cd "$ROOT/nucleo" && nice -n 10 cargo build --release -j 4 --quiet) || {
  echo "acceptance/shipcraft.sh: cargo build in nucleo/ failed; no case ran." >&2
  exit 2
}

export SHIPCRAFT_ACCEPTANCE_JUNIT="$JUNIT"
export SHIPCRAFT_ACCEPTANCE_CACHE="${SHIPCRAFT_ACCEPTANCE_CACHE:-$HOME/.cache/shipcraft-acceptance-deps}"
export SHIPCRAFT_ACCEPTANCE_REUSE="${SHIPCRAFT_ACCEPTANCE_REUSE:-0}"
if [ -n "$CASES" ]; then
  export SHIPCRAFT_ACCEPTANCE_CASES="${CASES# }"
else
  unset SHIPCRAFT_ACCEPTANCE_CASES
fi
exec bash "$ACEITE/run.sh" "$TARGET/release/shipcraft" "$WHICH"
