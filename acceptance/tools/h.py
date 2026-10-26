#!/usr/bin/env python3
"""Ajudantes da bateria de aceitacao da v1: le o estado dos stubs, confere o
runs.jsonl, edita o .shipcraft.toml. Uso: h.py <subcomando> args...
Sai com 0 quando a conferencia passa e 1 quando nao (com o motivo no stdout)."""
import json, os, re, sys, time



def jl(path):
    try:
        with open(path) as f:
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
    """rev_cfg FILE MODE [k=v ...]: grava o reviewer.json do stub."""
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
    """jsonl_check FILE BRANCHES SHAS_FILE: formato de cada linha e as combinacoes esperadas.
    BRANCHES: lista separada por virgula; o ultimo e o branch das linhas de ci e revisao."""
    rows = jl(a[0])
    branches = a[1].split(",")
    shas = set(open(a[2]).read().split())
    if not rows:
        die("o runs.jsonl esta vazio ou nao existe")
    seen = set()
    for i, r in enumerate(rows):
        for k in ("layer", "secs", "result", "code", "branch", "commit"):
            if k not in r:
                die("linha %d sem a chave %r: %s" % (i + 1, k, r))
        if r["layer"] not in ("hook", "ci", "review"):
            if r.get("escape") is True or r["layer"] == "merge":
                continue
            die("linha %d: camada %r fora de hook|ci|revisao" % (i + 1, r["layer"]))
        if r["result"] not in ("passed", "refused", "error"):
            die("linha %d: resultado %r fora de passou|recusou|erro" % (i + 1, r["result"]))
        if isinstance(r["secs"], bool) or not isinstance(r["secs"], (int, float)) or r["secs"] < 0:
            die("linha %d: tempo nao e numero >= 0: %r" % (i + 1, r["secs"]))
        if not isinstance(r["commit"], str):
            die("linha %d: commit nao e texto: %r" % (i + 1, r["commit"]))
        if r["layer"] != "hook" and not r["commit"]:
            die("linha %d: commit vazio numa linha de %s" % (i + 1, r["layer"]))
        if r["branch"] not in branches:
            die("linha %d: branch %r, esperado um de %r" % (i + 1, r["branch"], branches))
        if r["layer"] != "hook" and r["branch"] != branches[-1]:
            die("linha %d: branch %r, esperado %r" % (i + 1, r["branch"], branches[-1]))
        if r["layer"] == "review" and "tokens" not in r:
            die("linha %d: linha da revisao sem a chave tokens" % (i + 1))
        if r["result"] == "refused" and not (isinstance(r["code"], str) and r["code"]):
            die("linha %d: recusa sem codigo: %r" % (i + 1, r))
        seen.add((r["layer"], r["result"]))
    want = [("hook", "passed"), ("hook", "refused"), ("ci", "passed"), ("ci", "refused"),
            ("review", "passed"), ("review", "refused"), ("review", "error")]
    miss = [w for w in want if w not in seen]
    if miss:
        die("faltam linhas para: %s (vistas: %s)" % (miss, sorted(seen)))
    ci_ok = [r for r in rows if r.get("layer") == "ci" and r["result"] == "passed"]
    if not any(r["commit"] in shas for r in ci_ok):
        die("nenhuma linha ci/passou tem como commit uma sha vista pela bateria: %s" % [r["commit"] for r in ci_ok])
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
        die("a trava nao tem chave de versao do formato (esperado uma chave com 'vers' ou 'format'): %s" % list(d))
    print(k)


def cmd_lock_bump(a):
    p = a[0]
    d = json.load(open(p))
    k = lock_key(d)
    if not k:
        die("sem chave de versao")
    d[k] = 999 if isinstance(d[k], int) and not isinstance(d[k], bool) else "999.0"
    # preserva a formatacao legivel da trava
    json.dump(d, open(p, "w"), indent=2)
    open(p, "a").write("\n")


def cmd_has_summary(a):
    """Existe um texto publicado que fala das tres camadas e dos tokens?"""
    for w in writes(a[0], "comment,pr-edit,pr-create"):
        t = w["text"]
        if re.search(r"(?i)hook", t) and re.search(r"(?i)\bci\b", t) and re.search(r"(?i)review", t) and re.search(r"(?i)tokens", t):
            print("OK")
            return
    die("nenhum texto publicado no PR cita hook, ci, revis* e tokens")


AVISO_TAMANHO = "Smaller PRs usually get faster reviews; consider splitting."


def size_texts(st):
    return [w["text"] for w in writes(st, "comment,pr-edit,pr-create") if "Size:" in w["text"]]


def cmd_size_line(a):
    """size_line STATE: a linha 'Size:' do ultimo texto publicado no PR que a traz."""
    ts = size_texts(a[0])
    if not ts:
        die("nenhum texto publicado no PR traz a linha 'Size:'")
    for l in ts[-1].splitlines():
        if "Size:" in l:
            print(l.strip())
            return


def cmd_size_warn(a):
    """size_warn STATE: SIM/NAO, o ultimo texto com 'Size:' traz o aviso de PR grande?"""
    ts = size_texts(a[0])
    if not ts:
        die("nenhum texto publicado no PR traz a linha 'Size:'")
    print("SIM" if AVISO_TAMANHO in ts[-1] else "NAO")


def cmd_warn_count(a):
    """warn_count STATE: em quantos textos publicados (qualquer tipo) o aviso aparece."""
    print(len([w for w in writes(a[0]) if AVISO_TAMANHO in w["text"]]))


def cmd_jsonl_field(a):
    """jsonl_field FILE CAMADA COMMIT CHAVE: o valor (JSON) da chave em cada linha da camada nesse commit; MISSING se a chave falta."""
    rows = [r for r in jl(a[0]) if r.get("layer") == a[1] and r.get("commit") == a[2]]
    if not rows:
        die("nenhuma linha %s para o commit %s" % (a[1], a[2][:10]))
    for r in rows:
        print(json.dumps(r[a[3]]) if a[3] in r else "MISSING")


def cmd_mutating_reads(a):
    pass


def cmd_text_has(a):
    """text_has STATE KINDS REGEX: algum texto publicado casa?"""
    for w in writes(a[0], a[1] if a[1] != "-" else None):
        if re.search(a[2], w["text"]):
            print("OK")
            return
    die("nenhum texto publicado (%s) casa %r" % (a[1], a[2]))


def cmd_protect_ok(a):
    for w in writes(a[0], "protection"):
        t = w["text"] + " " + " ".join(w["argv"])
        if "shipcraft/ci" in t and "shipcraft/review" in t:
            print("OK")
            return
    die("nenhuma escrita de protecao de branch cita shipcraft/ci e shipcraft/review")


def cmd_escape_rows(a):
    for r in jl(a[0]):
        if r.get("escape") is True:
            print(r.get("commit", ""))


def cmd_lock_failing(a):
    """lock_failing TRAVA: imprime, um por linha, os casos de failing_at_red (item 13)."""
    d = json.load(open(a[0]))
    if "failing_at_red" not in d:
        die("a trava nao tem failing_at_red: %s" % list(d))
    for c in d["failing_at_red"]:
        print(c)


def cmd_npx_check(a):
    """npx_check ARQUIVO...: todo `npx` escrito traz `--` antes do primeiro argumento que nao e flag
    da propria npx (item 12). Imprime NPX=<n> e, para cada comando ruim, BAD <file>: <comando>."""
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
    """verifica_check ARQUIVO AGULHA: a checagem do projeto inteiro esta em `verifica` (de alguma suite ou do
    primeiro nivel) e em nenhum test_command / comando (item 13.1, ultimo ponto)."""
    d = toml_load(a[0])
    needle = a[1]
    tables = [("(topo)", d.get("test_command"), d.get("check"))]
    tables += [(s.get("name"), s.get("command"), s.get("check")) for s in d.get("suite", [])]
    with_v = [n for n, c, v in tables if isinstance(v, str) and needle in v]
    if not with_v:
        die("nenhum `verifica` traz %r: %s" % (needle, [(n, v) for n, c, v in tables]))
    bad = [n for n, c, v in tables if isinstance(c, str) and needle.split()[0] in c and needle in c]
    if bad:
        die("o comando de teste de %s ainda traz %r" % (bad, needle))
    print("OK verifica em %s" % with_v)


CMDS = {k[4:].replace("_", "-"): v for k, v in globals().items() if k.startswith("cmd_")}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in CMDS:
        die("uso: h.py <%s>" % "|".join(sorted(CMDS)), 2)
    CMDS[sys.argv[1]](sys.argv[2:])
