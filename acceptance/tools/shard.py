"""shard.py <durations.tsv> <k> <n>: the battery's cases for CI shard k of n.
shard.py --order <durations.tsv>: the run plan ("<language> <index> <case>" lines) longest first.

Reads "<language> <case>" lines (every case, in table order) on stdin and prints the ones shard k
runs. The cases are spread by duration, longest first, each to the shard with the least total so
far (ties: table order, then the lowest shard), so the n shards finish close together. Durations
come from <durations.tsv> ("<language> <case> <seconds>" per line, from the JUnit reports of a full
CI run); a case it does not list counts as the median. Without the file the split is round robin,
as before. Every case lands in exactly one shard: the split is checked before anything prints.
"""
import statistics, sys


def read_secs(path):
    secs = {}
    try:
        with open(path) as f:
            for line in f:
                parts = line.split()
                if len(parts) == 3 and not line.startswith('#'):
                    secs[(parts[0], parts[1])] = float(parts[2])
    except OSError:
        pass
    return secs


if sys.argv[1] == '--order':
    # Longest first, so a long case never starts last and holds the shard open alone.
    secs = read_secs(sys.argv[2])
    median = statistics.median(secs.values()) if secs else 0.0
    plan = [line.split() for line in sys.stdin if line.strip()]
    for p in sorted(plan, key=lambda p: -secs.get((p[0], p[2]), median)):
        print(' '.join(p))
    sys.exit(0)

path, k, n = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
if not 1 <= k <= n:
    sys.exit('shard.py: shard k must be 1..n')
cases = [tuple(line.split()) for line in sys.stdin if line.strip()]

secs = read_secs(path)

shard_of = {}
if secs:
    median = statistics.median(secs.values())
    order = sorted(range(len(cases)), key=lambda i: (-secs.get(cases[i], median), i))
    load = [0.0] * n
    for i in order:
        s = min(range(n), key=lambda j: (load[j], j))
        load[s] += secs.get(cases[i], median)
        shard_of[i] = s + 1
else:
    for i in range(len(cases)):
        shard_of[i] = i % n + 1

# The guard: the union of the n shards is every case, and no case is in two.
if sorted(shard_of) != list(range(len(cases))) or any(not 1 <= s <= n for s in shard_of.values()):
    sys.exit('shard.py: the split lost or repeated a case')
for i, c in enumerate(cases):
    if shard_of[i] == k:
        print(' '.join(c))
