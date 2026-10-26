#!/usr/bin/env python3
"""tmo.py <seconds> <command...>: runs the command in its own process group
and kills it (SIGKILL to the group) if it runs out of time. Exits 124 on timeout."""
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
    sys.stderr.write("tmo: timed out (%ss): %s\n" % (sys.argv[1], " ".join(sys.argv[2:])))
    sys.exit(124)
