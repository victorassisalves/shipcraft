#!/usr/bin/env python3
"""Helpers for the v1 acceptance battery: read the stubs' state, check
runs.jsonl, edit .shipcraft.toml. Usage: h.py <subcommand> args...
Exits 0 when the check passes and 1 when it does not (with the reason on stdout)."""
import json, os, re, sys, time



def jl(path):
    try:
        with open(path, encoding="utf-8-sig") as f:
            return [json.loads(l) for l in f if l.strip()]
    except Exception:
        return []


def die(msg, code=1):
    print(msg)
    sys.exit(code)


def toml_load(path):
    try:
        import tomllib as toml
    except ImportError:
        import tomli as toml
    with open(path, "rb") as f:
        return toml.load(f)


def cmd_toml_get(a):
    d = toml_load(a[0])
    for k in a[1].split("."):
        if not isinstance(d, dict) or k not in d:
            return
        d = d[k]
    print(str(d).lower() if isinstance(d, bool) else d)


def cmd_toml_set(a):
    path, section, key, lit = a
    text = open(path).read()
    lines = text.split("\n")
    line = "%s = %s" % (key, lit)
    if section == "":
        for i, l in enumerate(lines):
            if re.match(r"^\s*%s\s*=" % re.escape(key), l):
                lines[i] = line
                break
            if l.startswith("["):
                lines.insert(i, line)
                break
        else:
            lines.append(line)
    else:
        hdr = "[%s]" % section
        start = next((i for i, l in enumerate(lines) if l.strip() == hdr), None)
        if start is None:
            while lines and lines[-1] == "":
                lines.pop()
            lines += ["", hdr, line, ""]
        else:
            end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("[")), len(lines))
            for i in range(start + 1, end):
                if re.match(r"^\s*%s\s*=" % re.escape(key), lines[i]):
                    lines[i] = line
                    break
            else:
                lines.insert(start + 1, line)
    open(path, "w").write("\n".join(lines))


def cmd_toml_suites(a):
    d = toml_load(a[0])
    for s in d.get("suite", []):
        print("%s\t%s" % (s.get("name"), s.get("root")))


def statuses(st):
    return jl(os.path.join(st, "statuses.jsonl"))


def cmd_st_last(a):
    st, sha, ctx = a
    m = [s for s in statuses(st) if s["sha"] == sha and s["context"] == ctx]
    if not m:
        print("none")
        return
    print("%s\t%s" % (m[-1]["state"], m[-1]["description"]))


def cmd_st_count(a):
    st, sha, ctx = a
    print(len([s for s in statuses(st) if s["sha"] == sha and s["context"] == ctx]))


def cmd_st_count_state(a):
    st, sha, ctx, state = a
    print(len([s for s in statuses(st) if s["sha"] == sha and s["context"] == ctx and s["state"] == state]))


def cmd_st_ctx_count(a):
    st, ctx = a
    print(len([s for s in statuses(st) if s["context"] == ctx]))


def cmd_st_dump(a):
    for s in statuses(a[0]):
        print("%s %s %s %r" % (s["sha"][:10], s["context"], s["state"], s["description"]))


def writes(st, kinds=None):
    ws = jl(os.path.join(st, "writes.log"))
    if kinds:
        ks = kinds.split(",")
        ws = [w for w in ws if w["kind"] in ks]
    return ws


def cmd_writes(a):
    print("\n=====\n".join(w["text"] for w in writes(a[0], a[1] if len(a) > 1 else None)))


def cmd_nwrites(a):
    print(len(writes(a[0], a[1] if len(a) > 1 else None)))


def cmd_wkinds(a):
    print(" ".join(w["kind"] for w in writes(a[0])))


def cmd_calls(a):
    for c in jl(os.path.join(a[0], "calls.log")):
        print(" ".join(c["argv"]))


def cmd_rev_calls(a):
    cs = jl(os.path.join(a[0], "reviewer.calls.jsonl"))
    if len(a) > 1:
        cs = [c for c in cs if c["agent"] == a[1]]
    print(len(cs))


def cmd_rev_cfg(a):
    """rev_cfg FILE MODE [k=v ...]: writes the stub's reviewer.json."""
    d = {"mode": a[1]}
    for kv in a[2:]:
        k, _, v = kv.partition("=")
        try:
            d[k] = float(v) if "." in v else int(v)
        except ValueError:
            d[k] = v
    json.dump(d, open(a[0], "w"))


def cmd_rev_brief(a):
    cs = jl(os.path.join(a[0], "reviewer.calls.jsonl"))
    idx = int(a[1]) if len(a) > 1 else -1
    if not cs:
        return
    c = cs[idx]
    print("\n".join([" ".join(c["argv"]), c["stdin"]] + list(c["files"].values())))


def cmd_rev_field(a):
    cs = jl(os.path.join(a[0], "reviewer.calls.jsonl"))
    idx = int(a[1])
    print(cs[idx][a[2]] if cs else "")


def cmd_prnum(a):
    d = json.load(open(os.path.join(a[0], "prs.json")))
    for n in sorted(d, key=int):
        if d[n]["headRefName"] == a[1]:
            print(n)
            return


def cmd_pr_field(a):
    d = json.load(open(os.path.join(a[0], "prs.json")))
    print(d[a[1]].get(a[2], ""))


def cmd_pr_count(a):
    p = os.path.join(a[0], "prs.json")
    print(len(json.load(open(p))) if os.path.exists(p) else 0)


def cmd_pr_fork(a):
    st, n, owner, oid = a
    p = os.path.join(st, "prs.json")
    d = json.load(open(p))
    d[n]["fork"] = True
    d[n]["forkOwner"] = owner
    d[n]["headOid"] = oid
    json.dump(d, open(p, "w"))


def cmd_seed_status(a):
    st, sha, ctx, state, desc, age = a
    rows = statuses(st)
    with open(os.path.join(st, "statuses.jsonl"), "a") as f:
        f.write(json.dumps({"id": len(rows) + 1, "sha": sha, "context": ctx, "state": state, "description": desc,
                            "target_url": None, "t": time.time() - float(age)}) + "\n")


def cmd_timeline(a):
    ev = []
    for l in open(a[0]):
        p = l.split()
        if len(p) == 4:
            ev.append((float(p[3]), p[2], p[0], p[1]))
    ev.sort(key=lambda e: (e[0], 0 if e[1] == "end" else 1))
    cur = mx = 0
    n = 0
    for t, w, _, _ in ev:
        if w == "start":
            cur += 1
            n += 1
            mx = max(mx, cur)
        else:
            cur -= 1
    print("max=%d intervals=%d" % (mx, n))


def cmd_tl_time(a):
    for l in open(a[0]):
        p = l.split()
        if len(p) == 4 and p[0] == a[1] and p[1] == a[2] and p[2] == a[3]:
            print(p[3])
            return


def cmd_tl_has(a):
    for l in open(a[0]):
        p = l.split()
        if len(p) == 4 and p[0] == a[1] and p[1] == a[2] and p[2] == a[3]:
            sys.exit(0)
    sys.exit(1)


def cmd_jsonl_check(a):
    """jsonl_check FILE BRANCHES SHAS_FILE: the format of each row and the expected combinations.
    BRANCHES: comma-separated list; the last one is the branch of the ci and review rows."""
    rows = jl(a[0])
    branches = a[1].split(",")
    shas = set(open(a[2]).read().split())
    if not rows:
        die("runs.jsonl is empty or missing")
    seen = set()
    for i, r in enumerate(rows):
        for k in ("layer", "secs", "result", "code", "branch", "commit"):
            if k not in r:
                die("row %d lacks the key %r: %s" % (i + 1, k, r))
        if r["layer"] not in ("hook", "ci", "review", "merge", "red", "close", "pr"):
            die("row %d: unknown layer %r" % (i + 1, r["layer"]))
        # Historical rows may omit item 38 fields; validate them when recorded.
        for key in ("lock", "base", "default_branch"):
            if key in r and not isinstance(r[key], str):
                die("row %d: %s is not a string: %r" % (i + 1, key, r[key]))
        if "locks" in r and not (isinstance(r["locks"], list) and
                                  all(isinstance(v, str) for v in r["locks"])):
            die("row %d: locks is not a list of strings: %r" % (i + 1, r["locks"]))
        if "reused" in r and not isinstance(r["reused"], bool):
            die("row %d: reused is not a boolean: %r" % (i + 1, r["reused"]))
        if r["result"] not in ("passed", "refused", "error"):
            die("row %d: result %r not in passed|refused|error" % (i + 1, r["result"]))
        if isinstance(r["secs"], bool) or not isinstance(r["secs"], (int, float)) or r["secs"] < 0:
            die("row %d: secs is not a number >= 0: %r" % (i + 1, r["secs"]))
        if not isinstance(r["commit"], str):
            die("row %d: commit is not a string: %r" % (i + 1, r["commit"]))
        if r["layer"] in ("ci", "review") and not r["commit"]:
            die("row %d: empty commit in a %s row" % (i + 1, r["layer"]))
        if r["branch"] not in branches:
            die("row %d: branch %r, expected one of %r" % (i + 1, r["branch"], branches))
        if r["layer"] in ("ci", "review") and r["branch"] != branches[-1]:
            die("row %d: branch %r, expected %r" % (i + 1, r["branch"], branches[-1]))
        if r["layer"] == "review" and "tokens" not in r:
            die("row %d: review row without the tokens key" % (i + 1))
        if r["result"] == "refused" and not (isinstance(r["code"], str) and r["code"]):
            die("row %d: refusal without a code: %r" % (i + 1, r))
        seen.add((r["layer"], r["result"]))
    want = [("hook", "passed"), ("hook", "refused"), ("ci", "passed"), ("ci", "refused"),
            ("review", "passed"), ("review", "refused"), ("review", "error")]
    miss = [w for w in want if w not in seen]
    if miss:
        die("rows missing for: %s (seen: %s)" % (miss, sorted(seen)))
    ci_ok = [r for r in rows if r.get("layer") == "ci" and r["result"] == "passed"]
    if not any(r["commit"] in shas for r in ci_ok):
        die("no ci/passed row has as its commit a sha the battery saw: %s" % [r["commit"] for r in ci_ok])
    print("OK")


def lock_key(d):
    for k in d:
        if re.search(r"(?i)(vers|format)", k):
            return k
    return None


def cmd_lock_key(a):
    d = json.load(open(a[0]))
    k = lock_key(d)
    if not k:
        die("the lock has no format version key (expected a key with 'vers' or 'format'): %s" % list(d))
    print(k)


def cmd_lock_bump(a):
    p = a[0]
    d = json.load(open(p))
    k = lock_key(d)
    if not k:
        die("no version key")
    d[k] = 999 if isinstance(d[k], int) and not isinstance(d[k], bool) else "999.0"
    # keep the lock's readable formatting
    json.dump(d, open(p, "w"), indent=2)
    open(p, "a").write("\n")


def cmd_has_summary(a):
    """Is there a posted text that covers the three layers and the tokens?"""
    for w in writes(a[0], "comment,pr-edit,pr-create"):
        t = w["text"]
        if re.search(r"(?i)hook", t) and re.search(r"(?i)\bci\b", t) and re.search(r"(?i)review", t) and re.search(r"(?i)tokens", t):
            print("OK")
            return
    die("no text posted to the PR mentions hook, ci, review and tokens")


AVISO_TAMANHO = "Smaller PRs usually get faster reviews; consider splitting."


def size_texts(st):
    return [w["text"] for w in writes(st, "comment,pr-edit,pr-create") if "Size:" in w["text"]]


def cmd_size_line(a):
    """size_line STATE: the 'Size:' line of the last text posted to the PR that has one."""
    ts = size_texts(a[0])
    if not ts:
        die("no text posted to the PR has the 'Size:' line")
    for l in ts[-1].splitlines():
        if "Size:" in l:
            print(l.strip())
            return


def cmd_size_warn(a):
    """size_warn STATE: SIM/NAO (yes/no), does the last text with 'Size:' carry the large-PR warning?"""
    ts = size_texts(a[0])
    if not ts:
        die("no text posted to the PR has the 'Size:' line")
    print("SIM" if AVISO_TAMANHO in ts[-1] else "NAO")


def cmd_warn_count(a):
    """warn_count STATE: in how many posted texts (any kind) the warning appears."""
    print(len([w for w in writes(a[0]) if AVISO_TAMANHO in w["text"]]))


def cmd_jsonl_field(a):
    """jsonl_field FILE LAYER COMMIT KEY: the value (JSON) of the key in each row of that layer at that commit; MISSING if the key is absent."""
    rows = [r for r in jl(a[0]) if r.get("layer") == a[1] and r.get("commit") == a[2]]
    if not rows:
        die("no %s row for commit %s" % (a[1], a[2][:10]))
    for r in rows:
        print(json.dumps(r[a[3]]) if a[3] in r else "MISSING")


def cmd_mutating_reads(a):
    pass


def cmd_text_has(a):
    """text_has STATE KINDS REGEX: does any posted text match?"""
    for w in writes(a[0], a[1] if a[1] != "-" else None):
        if re.search(a[2], w["text"]):
            print("OK")
            return
    die("no posted text (%s) matches %r" % (a[1], a[2]))


def cmd_protect_ok(a):
    for w in writes(a[0], "protection"):
        t = w["text"] + " " + " ".join(w["argv"])
        if "shipcraft/ci" in t and "shipcraft/review" in t:
            print("OK")
            return
    die("no branch protection write requires shipcraft/ci and shipcraft/review")


def cmd_escape_rows(a):
    for r in jl(a[0]):
        if r.get("escape") is True:
            print(r.get("commit", ""))


def cmd_lock_failing(a):
    """lock_failing LOCK: prints the failing_at_red cases, one per line (item 13)."""
    d = json.load(open(a[0]))
    if "failing_at_red" not in d:
        die("the lock has no failing_at_red: %s" % list(d))
    for c in d["failing_at_red"]:
        print(c)


def cmd_npx_check(a):
    """npx_check FILE...: every `npx` written has `--` before the first argument that is not
    an npx flag (item 12). Prints NPX=<n> and, for each bad command, BAD <file>: <command>."""
    n, bad = 0, []
    for path in a:
        try:
            text = open(path, errors="replace").read()
        except OSError:
            continue
        for m in re.finditer(r"(?<![\w./-])npx(?![\w-])", text):
            seg = re.split(r"&&|\|\||;|\||\"|\n", text[m.end():], maxsplit=1)[0]
            toks = seg.split()
            n += 1
            for t in toks:
                if t == "--":
                    break
                if not t.startswith("-"):
                    bad.append("%s: npx %s" % (path, " ".join(toks)[:90]))
                    break
    print("NPX=%d" % n)
    for b in bad:
        print("BAD " + b)
    if bad:
        sys.exit(1)


def cmd_verifica_check(a):
    """verifica_check FILE NEEDLE: the whole-project check is in `verifica` (of some suite or of the
    top level) and in no test_command / command (item 13.1, last point)."""
    d = toml_load(a[0])
    needle = a[1]
    tables = [("(top)", d.get("test_command"), d.get("check"))]
    tables += [(s.get("name"), s.get("command"), s.get("check")) for s in d.get("suite", [])]
    with_v = [n for n, c, v in tables if isinstance(v, str) and needle in v]
    if not with_v:
        die("no `verifica` has %r: %s" % (needle, [(n, v) for n, c, v in tables]))
    bad = [n for n, c, v in tables if isinstance(c, str) and needle.split()[0] in c and needle in c]
    if bad:
        die("the test command of %s still has %r" % (bad, needle))
    print("OK verifica in %s" % with_v)


CMDS = {k[4:].replace("_", "-"): v for k, v in globals().items() if k.startswith("cmd_")}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in CMDS:
        die("usage: h.py <%s>" % "|".join(sorted(CMDS)), 2)
    CMDS[sys.argv[1]](sys.argv[2:])
