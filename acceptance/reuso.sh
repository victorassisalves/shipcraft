# Shared by run.sh and review.sh; cache data is JSON, never shell code.
acceptance_tree_id() {
  local trees
  trees=$(git -C "$1" rev-parse "$2:nucleo" "$2:acceptance" 2>/dev/null) || return 1
  printf '%s\n' "$trees" | git -C "$1" hash-object --stdin
}

acceptance_cached_result() {
  [ "${SHIPCRAFT_ACCEPTANCE_REUSE:-1}" != 0 ] || return 1
  local id
  id=$(acceptance_tree_id "$1" "$2") || return 1
  python3 - "$HOME/.cache/shipcraft-acceptance/$id" "$id" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    assert d['tree'] == sys.argv[2] and d['state'] == 'success'
    assert type(d['total']) is int and d['total'] > 0
    assert type(d['passed']) is int and d['passed'] == d['total']
    assert type(d['seconds']) is int and d['seconds'] >= 0
    assert isinstance(d['sha'], str) and len(d['sha']) == 40 and all(c in '0123456789abcdef' for c in d['sha'])
    assert isinstance(d['date'], str) and d['date']
    print(f"{d['passed']}/{d['total']} local, {d['seconds']} s; HEAD {d['sha']}; date {d['date']}; tree {d['tree']}")
except (OSError, ValueError, KeyError, AssertionError, TypeError):
    sys.exit(1)
PY
}
