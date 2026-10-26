#!/usr/bin/env python3
"""tmo.py <segundos> <comando...>: roda o comando num grupo de processos proprio
e o mata (SIGKILL no grupo) se passar do tempo. Sai com 124 no tempo esgotado."""
import os, signal, subprocess, sys

secs = float(sys.argv[1])
p = subprocess.Popen(sys.argv[2:], start_new_session=True)
try:
    sys.exit(p.wait(timeout=secs))
except subprocess.TimeoutExpired:
    try:
        os.killpg(p.pid, signal.SIGKILL)
    except Exception:
        pass
    p.wait()
    sys.stderr.write("tmo: tempo esgotado (%ss): %s\n" % (sys.argv[1], " ".join(sys.argv[2:])))
    sys.exit(124)
