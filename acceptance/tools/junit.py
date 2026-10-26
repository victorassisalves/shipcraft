#!/usr/bin/env python3
"""junit.py <work dir> <saida.xml> <segundos do timeout>: o JUnit da bateria.

Um testcase por caso do plano (classname = perfil, name = id do caso), na ordem do
plano: PASS passa, FAIL vira failure, erro de harness ou caso sem resultado (crash ou
timeout) vira error. Os casos que SHIPCRAFT_ACCEPTANCE_CASES deixou de fora viram skipped. O
tempo de cada caso vai do inicio (starts/) ao arquivo de resultado."""
import os, sys, tempfile, time
from xml.sax.saxutils import escape, quoteattr

work, out, tmo = sys.argv[1], sys.argv[2], float(sys.argv[3])


def clean(s):
    return ''.join(ch for ch in s if ch in '\t\n' or ord(ch) >= 32)


def start_of(key):
    try:
        with open(os.path.join(work, 'starts', key)) as f:
            return float(f.read().strip())
    except (OSError, ValueError):
        return None


cases = []  # (perfil, id, estado, tempo, mensagem, detalhe)
with open(os.path.join(work, 'plan')) as f:
    for line in f:
        if not line.strip():
            continue
        lang, idx, case = line.split()
        key = '%s.%s.%s' % (lang, idx, case)
        start = start_of(key)
        res = os.path.join(work, 'results', key)
        if os.path.isfile(res):
            with open(res, errors='replace') as r:
                fields = (r.read().rstrip('\n').split('\t') + [''] * 6)[:6]
            _, _, expect, obs, rc, verdict = fields
            secs = max(0.0, os.path.getmtime(res) - start) if start is not None else 0.0
            if verdict == 'PASS':
                state = 'pass'
            elif obs.startswith('harness:'):
                state = 'error'
            else:
                state = 'failure'
            detail = 'expected: %s\nobserved: %s\nexit: %s' % (expect, obs, rc)
        else:
            obs = 'harness: no result (crash or timeout)'
            secs = min(tmo, max(0.0, time.time() - start)) if start is not None else 0.0
            state, detail = 'error', obs
        cases.append((lang, case, state, secs, obs, detail))

skipped = os.path.join(work, 'skipped')
if os.path.isfile(skipped):
    with open(skipped) as f:
        for line in f:
            if line.strip():
                lang, case = line.split()
                cases.append((lang, case, 'skipped', 0.0, 'not selected by SHIPCRAFT_ACCEPTANCE_CASES', ''))

count = {s: sum(1 for c in cases if c[2] == s) for s in ('failure', 'error', 'skipped')}
total = sum(c[3] for c in cases)
lines = ['<?xml version="1.0" encoding="UTF-8"?>',
         '<testsuites tests="%d" failures="%d" errors="%d" skipped="%d" time="%.3f">'
         % (len(cases), count['failure'], count['error'], count['skipped'], total),
         '  <testsuite name="aceite" tests="%d" failures="%d" errors="%d" skipped="%d" time="%.3f">'
         % (len(cases), count['failure'], count['error'], count['skipped'], total)]
for lang, case, state, secs, msg, detail in cases:
    head = '    <testcase classname=%s name=%s time="%.3f"' % (quoteattr(lang), quoteattr(case), secs)
    if state == 'pass':
        lines.append(head + '/>')
        continue
    lines.append(head + '>')
    if state == 'skipped':
        lines.append('      <skipped message=%s/>' % quoteattr(clean(msg)))
    else:
        lines.append('      <%s message=%s>%s</%s>' % (state, quoteattr(clean(msg)), escape(clean(detail)), state))
    lines.append('    </testcase>')
lines += ['  </testsuite>', '</testsuites>', '']

folder = os.path.dirname(os.path.abspath(out))
fd, tmp = tempfile.mkstemp(prefix='.junit-', dir=folder)
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    os.replace(tmp, out)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
