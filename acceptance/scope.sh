#!/usr/bin/env bash
# What a PR's CI runs, from the paths it changes (the battery by impact).
# Usage: acceptance/scope.sh <base-ref> [<head-ref>]   or   acceptance/scope.sh --full
# Prints three lines for $GITHUB_OUTPUT:
#   mode=none    only text nothing executes reads (docs/, root *.md, LICENSE, the points);
#   mode=items   only acceptance/lib/item*.sh files: their cases, in one shard;
#   mode=full    anything else, or any doubt: the whole battery in SHARDS (18) shards.
# Main and the daily run always run the whole battery; this script only scopes PRs.
set -euo pipefail
# 18, not 20: a free account runs 20 jobs at once, and the shipcraft-recheck job and this
# workflow's scope and build jobs run beside the shards. Revert: SHARDS=10.
SHARDS=18
full() { printf 'mode=full\ncases=\nshards=[%s]\n' "$(seq 1 "$SHARDS" | paste -sd, -)"; exit 0; }
[ "${1:-}" = --full ] && full
base="$1"; head="${2:-HEAD}"

merge_base=$(git merge-base "$base" "$head" 2>/dev/null) || full
changed=$(git diff --name-only --no-renames "$merge_base" "$head") || full
[ -n "$changed" ] || full

items=""
while IFS= read -r path; do
  case "$path" in
    docs/*|LICENSE|acceptance/pontos/*|acceptance/README.md) continue ;;
    */*) ;;
    *.md) continue ;;
  esac
  case "$path" in
    acceptance/lib/item[0-9]*.sh) [ -f "$path" ] || full; items="$items $path" ;;
    *) full ;;
  esac
done <<< "$changed"

if [ -z "$items" ]; then
  printf 'mode=none\ncases=\nshards=[]\n'
  exit 0
fi
cases=""
for f in $items; do
  n=$(basename "$f" .sh); n=${n#item}
  got=$(bash -c 'pass(){ :; }; source "$1"; "item$2_cases"' _ "$f" "$n" 2>/dev/null | tr '\n' ' ') || full
  [ -n "${got// /}" ] || full
  cases="$cases $got"
done
printf 'mode=items\ncases=%s\nshards=[1]\n' "$(echo $cases)"
