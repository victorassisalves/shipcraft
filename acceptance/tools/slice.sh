#!/usr/bin/env bash
# slice.sh [--bin <shipcraft>] [--langs core|python|node|go|all] [--allow-large] [--done <file>]
#          [-f <ids file>] [<case id>...]
# Runs acceptance/run.sh on a slice: the given case ids, through SHIPCRAFT_ACCEPTANCE_CASES,
# with the binary (default: nucleo/target/release/shipcraft of this checkout) and languages
# (default: all) passed to run.sh.
# Prints the selected count first and refuses more than 400 cases without --allow-large
# (item 80's GREEN ran 1,943). Its last line is always `slice: exit <rc> ...`, and it writes
# the same line to a done marker (default: $TMPDIR/shipcraft-slice.<pid>.done, printed at
# the start), so a background run is never waited on after it ends (item 71 lost 20 min).
# Other SHIPCRAFT_ACCEPTANCE_* variables pass through to run.sh.
# Metric and revert: process/item-flow.md, "Item-time package" (shipcraft-v2).
set -u

here="$(cd "$(dirname "$0")" && pwd)"
limit=400 large=0 done_file="" ids="" bin="$here/../../nucleo/target/release/shipcraft" langs=all
while [ $# -gt 0 ]; do
  case "$1" in
    --allow-large) large=1 ;;
    --bin) [ $# -ge 2 ] || { echo "slice: --bin needs a path" >&2; exit 2; }; bin=$2; shift ;;
    --langs) [ $# -ge 2 ] || { echo "slice: --langs needs a value" >&2; exit 2; }; langs=$2; shift ;;
    --done) [ $# -ge 2 ] || { echo "slice: --done needs a file" >&2; exit 2; }; done_file=$2; shift ;;
    -f) [ $# -ge 2 ] && [ -r "$2" ] || { echo "slice: -f needs a readable file" >&2; exit 2; }
        ids="$ids $(tr -s ' \t\r' '\n' < "$2")"; shift ;;
    -*) echo "slice: unknown option $1" >&2; exit 2 ;;
    *) ids="$ids $1" ;;
  esac
  shift
done

# One id per word, duplicates dropped, order kept.
ids=$(printf '%s\n' $ids | awk 'NF && !seen[$0]++' | tr '\n' ' ')
n=$(printf '%s\n' $ids | grep -c .)
[ -n "$done_file" ] || done_file="${TMPDIR:-/tmp}/shipcraft-slice.$$.done"
rm -f "$done_file"
echo "slice: $n case(s) selected; done marker: $done_file"

finish() {
  line="slice: exit $1 ($n case(s), $(( $(date +%s) - start )) s)${2:+; $2}"
  echo "$line" > "$done_file"
  echo "$line"
  exit "$1"
}
start=$(date +%s)
trap 'finish 130 "interrupted"' INT TERM
[ "$n" -gt 0 ] || finish 2 "no case id given"
[ "$n" -le "$limit" ] || [ "$large" = 1 ] || finish 2 "more than $limit cases: pass --allow-large if the whole set is meant"

SHIPCRAFT_ACCEPTANCE_CASES="$ids" bash "$here/../run.sh" "$bin" "$langs"
finish $?
