#!/usr/bin/env python3
"""routing_check.py <item file> [--static | --logs <work dir> | --bin <shipcraft>] [--per-case]

Advisory check of an item's cases before `red` (RED brief rule 16). The RED answers
each warning in its report; nothing here refuses.

Static part (about a second):
- lists the item's case ids (`item<N>_cases`, sourced in bash);
- every routing by an id prefix or suffix (`case.startswith('pr-')`, a shell `pr-*)` arm),
  with the ids it captures; an id that is captured and also has its own exact arm is
  routed twice (item 79's `pr-array-only`);
- every shared Python helper that sets values the item's asserts read (item 79's
  `missing()`, which fixed the expected call list for every case that called it).
Run part (default; skipped with --static): runs the ids on the current binary through
tools/slice.sh, or reads an earlier kept run with --logs, and for each failing case says
whether the failing assertion is in the case's own arm, in a shared helper, in a prefix
arm, or in shared code, and which helper-set values it reads.
"""
import fnmatch, os, re, subprocess, sys, tempfile
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
MUTATION = [
    re.compile(r"\b([A-Za-z_]\w*)\[:\]\s*="),
    re.compile(r"\b([A-Za-z_]\w*)\.(?:clear|append|extend|update|pop|insert|setdefault|remove)\("),
    re.compile(r"\b([A-Za-z_]\w*)\[[^\]=]+\]\s*=(?!=)"),
]
GLOBAL = re.compile(r"\bglobal\s+([\w\s,]+)")
LITERAL = re.compile(r"""(['"])([^'"\\]+)\1""")
PREFIX = re.compile(r"""\.(startswith|endswith)\(\s*(\(.*?\)|(['"])[^'"]*\3)""")
SHELL_ARM = re.compile(r"^\s*\(?((?:[^\s()|;]+\|)*[^\s()|;]+)\)")


def case_ids(item):
    n = re.match(r"item(\w+)\.sh$", item.name)
    if not n:
        sys.exit("routing_check: expected acceptance/lib/item<N>.sh, got %s" % item)
    fn = "item%s_cases" % n.group(1)
    p = subprocess.run(["bash", "-c", 'source "$1" >/dev/null 2>&1; "$2"', "_", str(item), fn],
                       capture_output=True, text=True)
    ids = [l.strip() for l in p.stdout.splitlines() if l.strip()]
    if p.returncode != 0 or not ids:
        sys.exit("routing_check: %s listed no case id (exit %s): %s" % (fn, p.returncode, p.stderr.strip()))
    return ids


def short(cid):
    return re.sub(r"^v1-[^.]+\.", "", cid)


def heredocs(lines):
    """(first body line, last body line), 1-based, of each quoted heredoc."""
    out, i = [], 0
    while i < len(lines):
        m = re.search(r"<<-?'(\w+)'", lines[i])
        if m:
            j = i + 1
            while j < len(lines) and lines[j].strip() != m.group(1):
                j += 1
            out.append((i + 2, j))
            i = j
        i += 1
    return out


def indent(line):
    return len(line) - len(line.lstrip(" \t"))


def static(item, ids):
    lines = item.read_text(errors="replace").splitlines()
    names = {short(i): i for i in ids}
    names.update({i: i for i in ids})
    exact = defaultdict(list)    # id -> lines naming it in a comparison or arm
    prefix = []                  # (line, pattern text, captured ids)
    for no, text in enumerate(lines, 1):
        code = text.split("#", 1)[0] if not text.lstrip().startswith("#") else ""
        excluded = set()
        for m in re.finditer(r"""!=\s*(['"])([^'"]+)\1|not\s+in\s*\(([^)]*)\)""", code):
            for lit in [m.group(2)] if m.group(2) else [x[1] for x in LITERAL.findall(m.group(3) or "")]:
                if lit in names:
                    excluded.add(names[lit])
        if re.search(r"==|\bin\s*[(\[{]|^\s*\(?['\"\w.-]+(\|['\"\w.-]+)*\)", code):
            for _, lit in LITERAL.findall(code):
                if lit in names and names[lit] not in excluded:
                    exact[names[lit]].append(no)
            sm = SHELL_ARM.match(code)
            if sm and "*" not in sm.group(1):
                for pat in sm.group(1).split("|"):
                    pat = pat.strip("'\"")
                    if pat in names and names[pat] not in excluded:
                        exact[names[pat]].append(no)
        for m in PREFIX.finditer(code):
            lits = [x[1] for x in LITERAL.findall(m.group(2))]
            kind = m.group(1)
            hit = [i for i in ids if i not in excluded
                   and any(getattr(short(i), kind)(lit) or getattr(i, kind)(lit) for lit in lits)]
            if hit:
                prefix.append((no, "%s(%s)" % (kind, ", ".join(repr(l) for l in lits)), hit))
        sm = SHELL_ARM.match(code)
        if sm and "*" in sm.group(1) and not code.lstrip().startswith(("*)", "(*)")):
            pats = [p.strip("'\"") for p in sm.group(1).split("|")]
            hit = [i for i in ids if i not in excluded and any(fnmatch.fnmatchcase(short(i), p) or fnmatch.fnmatchcase(i, p) for p in pats)]
            if hit:
                prefix.append((no, "shell arm %s)" % sm.group(1), hit))

    # Shared Python helpers that set values an assert reads.
    helpers = {}
    asserted = set()
    docs = heredocs(lines)
    for first, last in docs:
        body = lines[first - 1:last]
        for text in body:
            if text.lstrip().startswith("assert"):
                asserted.update(re.findall(r"[A-Za-z_]\w*", text))
        i = 0
        while i < len(body):
            m = re.match(r"^(\s*)def\s+(\w+)\s*\(([^)]*)\)", body[i])
            if not m:
                i += 1
                continue
            base, name = len(m.group(1)), m.group(2)
            params = set(re.findall(r"[A-Za-z_]\w*", m.group(3)))
            j, sets = i + 1, set()
            rest = body[i][m.end():]
            chunk = [rest] if rest.strip(" :") else []
            while j < len(body) and (not body[j].strip() or indent(body[j]) > base):
                chunk.append(body[j])
                j += 1
            for text in chunk:
                for rx in MUTATION:
                    sets.update(rx.findall(text))
                for g in GLOBAL.findall(text):
                    sets.update(x.strip() for x in g.split(","))
            # Names the function binds itself are its own, not shared state.
            local = set()
            for text in chunk:
                local.update(re.findall(r"(?:^|[;:]\s*|^\s*)([A-Za-z_]\w*)\s*=(?!=)", text))
                local.update(re.findall(r"\bfor\s+([A-Za-z_]\w*)\s+in\b", text))
                local.update(re.findall(r"\bas\s+([A-Za-z_]\w*)", text))
            sets -= params | local
            if sets:
                helpers[name] = {"line": first + i, "end": first + j - 1, "sets": sets}
            i = j
    shared = {}
    for name, h in helpers.items():
        read = sorted(h["sets"] & asserted)
        if not read:
            continue
        calls = [no for no, text in enumerate(lines, 1)
                 if re.search(r"\b%s\(" % re.escape(name), text) and not re.match(r"\s*def\s", text)]
        if calls:
            shared[name] = dict(h, read=read, calls=calls)
    return lines, docs, exact, prefix, shared


def where(lines, docs, fileline, cid, exact, prefix, shared):
    for name, h in shared.items():
        if h["line"] <= fileline <= h["end"]:
            return "shared helper %s()" % name
    for first, last in docs:
        if not first <= fileline <= last:
            continue
        # Walk up to the routing line that holds this one (same line for `if x: stmt`).
        k, level = fileline, indent(lines[fileline - 1])
        while k >= first:
            text = lines[k - 1]
            if text.strip() and (k == fileline or indent(text) < level) and re.match(r"\s*(if|elif)\b", text):
                if k in exact.get(cid, []):
                    return "own arm (line %d)" % k
                if any(p[0] == k for p in prefix):
                    return "prefix arm (line %d)" % k
                level = indent(text)
                if level == 0:
                    break
            if text.strip() and indent(text) < level:
                level = indent(text)
            k -= 1
    return "shared code"


def failures(workdir, ids):
    out = {}
    for f in Path(workdir, "results").glob("*"):
        parts = f.read_text(errors="replace").rstrip("\n").split("\t")
        if parts and parts[0] in ids and parts[-1] == "FAIL":
            out[parts[0]] = (parts[1], parts[3] if len(parts) > 3 else "")
    return out


def stdin_line(log):
    """The innermost `<stdin>` frame of the last traceback in a case log."""
    found = None
    for m in re.finditer(r'File "<stdin>", line (\d+)', log):
        found = int(m.group(1))
    return found


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    opts = set(a for a in argv if a.startswith("--"))
    logs = None
    if "--logs" in argv:
        i = argv.index("--logs")
        logs = argv[i + 1] if i + 1 < len(argv) else sys.exit("routing_check: --logs needs a work dir")
        args = [a for a in args if a != logs]
    binary = None
    if "--bin" in argv:
        i = argv.index("--bin")
        binary = argv[i + 1] if i + 1 < len(argv) else sys.exit("routing_check: --bin needs a path")
        args = [a for a in args if a != binary]
    if len(args) != 1:
        sys.exit(__doc__)
    item = Path(args[0]).resolve()
    ids = case_ids(item)
    lines, docs, exact, prefix, shared = static(item, ids)
    warnings = 0
    print("routing_check: %s: %d case id(s)" % (item.name, len(ids)))
    twice = defaultdict(list)
    plines = defaultdict(set)
    for no, _, hit in prefix:
        for h in hit:
            plines[h].add(no)
    for no, what, hit in prefix:
        warnings += 1
        print("WARN prefix routing, line %d: %s captures %d id(s): %s" % (no, what, len(hit), ", ".join(short(h) for h in hit[:8]) + (" ..." if len(hit) > 8 else "")))
        for h in hit:
            own = [l for l in exact.get(h, []) if l not in plines[h]]
            if own:
                twice[h].append((no, own))
    for h, where_ in twice.items():
        warnings += 1
        own = sorted(set(l for _, o in where_ for l in o))
        print("WARN routed twice: %s is captured by the prefix arm(s) at line(s) %s and has its own arm at line(s) %s"
              % (short(h), ", ".join(str(no) for no, _ in where_), ", ".join(map(str, own))))
    for name, h in sorted(shared.items(), key=lambda x: x[1]["line"]):
        warnings += 1
        print("WARN shared helper %s() (line %d) sets %s, which asserts read; called at line(s) %s: a case that calls it gets these expected values unless its own arm sets them again"
              % (name, h["line"], ", ".join(h["read"]), ", ".join(map(str, h["calls"]))))
    print("routing_check: static: %d warning(s)" % warnings)
    if "--static" in opts:
        return 0

    if logs is None:
        with tempfile.NamedTemporaryFile("w", suffix=".ids", delete=False) as f:
            f.write("\n".join(ids) + "\n")
        env = dict(os.environ)
        p = subprocess.run(["bash", str(HERE / "slice.sh"), "--allow-large", "-f", f.name]
                           + (["--bin", binary] if binary else []), env=env,
                           capture_output=True, text=True)
        os.unlink(f.name)
        m = re.search(r"(?:logs and failed cases kept|work dir kept): (\S+)", p.stdout + p.stderr)
        print((p.stdout.strip().splitlines() or [""])[-1])
        if not m:
            print("routing_check: no kept work dir in run.sh's output; nothing to attribute")
            return 0
        logs = m.group(1)
    failed = failures(logs, set(ids))
    groups = defaultdict(list)
    for cid in sorted(failed, key=ids.index):
        prof, _ = failed[cid]
        log = Path(logs, "logs", "%s-%s.log" % (prof, cid))
        text = log.read_text(errors="replace") if log.exists() else ""
        n = stdin_line(text)
        if n is None or not docs:
            groups[("no Python traceback; see the log", None)].append(cid)
            continue
        cands = [first + n - 1 for first, last in docs if first + n - 1 <= last]
        fileline = cands[0] if len(cands) == 1 else None
        if fileline is None:
            groups[("<stdin> line %d, heredoc ambiguous" % n, None)].append(cid)
            continue
        kind = where(lines, docs, fileline, cid, exact, prefix, shared)
        names = set(re.findall(r"[A-Za-z_]\w*", lines[fileline - 1]))
        via = sorted("%s (set by %s())" % (v, h) for h, s in shared.items() for v in s["read"] if v in names)
        both = "; also routed by the prefix arm(s) at line(s) %s" % ", ".join(str(no) for no, _ in twice[cid]) if cid in twice else ""
        groups[("line %d, %s%s%s" % (fileline, kind, "; reads " + ", ".join(via) if via else "", both), fileline)].append(cid)
    print("routing_check: %d failing case(s) of %d" % (len(failed), len(ids)))
    for (label, _), cids in sorted(groups.items(), key=lambda g: -len(g[1])):
        show = cids if "--per-case" in opts else cids[:6]
        print("FAIL %d case(s) at %s: %s%s" % (len(cids), label, ", ".join(short(c) for c in show), " ..." if len(show) < len(cids) else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
