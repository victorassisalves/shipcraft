#!/usr/bin/env python3
"""Item 28: real Git; query failure injected only at the Git boundary."""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys

case, binary, scratch = sys.argv[1:]
route, mode = case.split('-', 1)
repo = Path.cwd().resolve()
scratch = Path(scratch).resolve()
real_git = shutil.which('git')
locks = repo / '.shipcraft/locks'
base_env = dict(os.environ)


def run(args, env=None, ok=True):
    p = subprocess.run(list(map(str, args)), cwd=repo, env=env or base_env,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, timeout=60)
    print('$', shlex.join(map(str, args)), '\n', p.stdout, flush=True)
    if ok:
        assert p.returncode == 0, f'exit {p.returncode}: {args}'
    return p


def git(*args, **kwargs):
    return run([real_git, *args], **kwargs)


def fixture_commit(message):
    git('add', '-A')
    git('-c', 'core.hooksPath=/dev/null', 'commit', '-qm', message)


def write(rel, content='trava que não precisa ser lida\n'):
    p = repo / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    return p


def quote(path):
    # The contract requires quotes even where shlex.quote would leave them out.
    return "'" + path.replace("'", "'\\''") + "'"


def warning(path, ignored=False):
    return (f'shipcraft: warning: {path} is outside this commit. '
            'If this is the RED commit, add the lock: '
            f'git add {"-f " if ignored else ""}{quote(path)}'
            + (' (ignored by git)' if ignored else ''))


def hook(env=None):
    args = [binary, 'check']
    if route == 'msg':
        msg = repo / '.git/item28-message'
        msg.write_text('chore: cenário de aviso\n')
        args += ['--commit-msg', msg]
    return run(args, env=env, ok=False)


def check_output(p, baseline, expected, extra=0, query_error=False):
    assert p.returncode == baseline.returncode, 'warning changed the exit code'
    lines = p.stdout.splitlines()
    warns = [line for line in lines if line.startswith('shipcraft: warning:') and not re.search(r'\band \d+ more\b', line)]
    if query_error:
        assert len(warns) == 1, f'expected one query warning: {lines}'
        assert re.fullmatch(r'shipcraft: warning: could not read \.shipcraft/locks/ \(.+\)\.', warns[0]), warns
        assert 'item28-consulta-falhou' in warns[0], 'git reason lost'
    else:
        assert warns == expected, f'expected warnings {expected!r}, got {warns!r}'
    counter = [line for line in lines if re.search(r'\band \d+ more\b', line)]
    assert len(counter) == (1 if extra else 0), f'unexpected/missing counter: {counter}'
    if extra:
        assert re.search(rf'\band {extra} more\b', counter[0]), counter
    # Warnings and the counter must come before any judging output.
    prefix = len(warns) + len(counter)
    assert set(lines[:prefix]) == set(warns + counter), f'late warning: {lines}'
    if baseline.returncode:
        last = [line for line in lines if line.strip()][-3:]
        old = [line for line in baseline.stdout.splitlines() if line.strip()][-3:]
        assert last == old, f'warning changed the refusal: {last!r} != {old!r}'
        assert last[0].startswith('shipcraft refused:') and last[1].startswith('Why:') and last[2].startswith('Next:'), last
    elif mode not in ('only', 'only-ignorado'):
        # Times and copy paths may change; the final verdict may not.
        tail = [line for line in lines[prefix:] if line.strip()][-1:]
        old = [line for line in baseline.stdout.splitlines() if line.strip()][-1:]
        assert tail == old, f'judging changed: {tail!r} != {old!r}'


# .gitkeep is empty by definition; removing it isolates the rule that counts empty blobs.
keep = locks / '.gitkeep'
if keep.exists():
    keep.unlink()
write('item28-pendente.txt', 'base\n')
fixture_commit('chore: base isolada do aviso')
locks.mkdir(parents=True, exist_ok=True)

if mode in ('gitignore', 'negacao', 'only-ignorado'):
    with (repo / '.gitignore').open('a') as f:
        f.write('\n.shipcraft/locks/*.' + ('txt' if mode == 'only-ignorado' else 'json') + '\n')
        if mode == 'negacao':
            f.write('!.shipcraft/locks/manter.json\n')
    fixture_commit('chore: exclusões efetivas do git')
elif mode == 'info':
    with (repo / '.git/info/exclude').open('a') as f:
        f.write('\n.shipcraft/locks/*.json\n')
elif mode == 'global':
    excludes = scratch / 'excludes'
    excludes.write_text('.shipcraft/locks/*.json\n')
    git('config', 'core.excludesFile', excludes)
elif mode == 'recusa':
    # Does not test the value init writes; asks for a version that is surely in the future.
    from h import toml_load
    current = toml_load(Path(__file__).resolve().parents[2] / 'nucleo/Cargo.toml')['package']['version']
    future = str(int(current.split('.')[0]) + 10) + '.0.0'
    cfg = repo / '.shipcraft.toml'
    cfg.write_text(re.sub(r'shipcraft_min\s*=\s*"[^"]*"', f'shipcraft_min = "{future}"', cfg.read_text()))
    git('add', '.shipcraft.toml')
elif mode == 'copia':
    # The index keeps the red stub; the dirty tree has the green implementation.
    write('textutil.py', 'import re, unicodedata\ndef slugify(text):\n    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()\n    return re.sub(r"[^a-zA-Z0-9]+", "-", text).strip("-").lower()\n')
elif mode == 'rastreado':
    write('.shipcraft/locks/rastreada.txt')
    git('add', '.shipcraft/locks/rastreada.txt')

baseline = hook()
assert 'shipcraft: warning:' not in baseline.stdout, f'control already had a warning: {baseline.stdout}'
assert (baseline.returncode != 0) == (mode == 'recusa'), 'fixture with an unexpected verdict'
if mode in ('sem-arquivos', 'rastreado'):
    check_output(hook(), baseline, [])
    sys.exit(0)

if mode in ('only', 'only-ignorado'):
    # Git builds its temporary index and passes it to the commit --only hook.
    hooks = repo / '.git/item28-hooks'
    hooks.mkdir()
    installed = hooks / ('pre-commit' if route == 'pre' else 'commit-msg')
    receipt = scratch / 'hook-index'
    installed.write_text('#!/bin/sh\n'
                         + 'printf "%s\\n" "$GIT_INDEX_FILE" > ' + shlex.quote(str(receipt)) + '\n'
                         + 'exec ' + shlex.quote(binary) + ' check'
                         + (' --commit-msg "$1"' if route == 'msg' else '') + '\n')
    installed.chmod(0o755)
    write('item28-pendente.txt', 'controle\n')
    before = git('-c', f'core.hooksPath={hooks}', 'commit', '--only', '-qm', 'chore: controle', '--', 'item28-pendente.txt', ok=False)
    assert before.returncode == 0 and 'shipcraft: warning:' not in before.stdout, before.stdout
    path = '.shipcraft/locks/fora-do-only.txt'
    write(path)
    git('add', '-f', path)
    assert 'shipcraft: warning:' not in hook().stdout, 'non-empty file is already in the normal index'
    write('item28-pendente.txt', 'julgado\n')
    result = git('-c', f'core.hooksPath={hooks}', 'commit', '--only', '-qm', 'chore: julgado', '--', 'item28-pendente.txt', ok=False)
    assert receipt.read_text().strip() and not receipt.read_text().strip().endswith('/index'), 'Git did not provide a temporary index'
    check_output(result, before, [warning(path, mode == 'only-ignorado')])
    assert git('ls-tree', '--name-only', 'HEAD', '--', path).stdout == '', 'lock got into the commit --only'
    assert path in git('ls-files', '--', path).stdout, 'normal index was lost'
    sys.exit(0)

entries = []
if mode in ('cinco', 'seis', 'sete'):
    # C.json sorts before a.json by bytes, with no clash on case-insensitive APFS.
    names = ['Z.txt', 'a.txt', 'z.json', 'C.json', 'a.json', 'b.md', 'b.json']
    size = {'cinco': 5, 'seis': 6, 'sete': 7}[mode]
    for name in reversed(names[:size]):
        path = '.shipcraft/locks/' + name
        write(path)
        entries.append((path, False))
elif mode == 'negacao':
    for name, ignored in [('ignorar.json', True), ('manter.json', False)]:
        path = '.shipcraft/locks/' + name
        write(path)
        entries.append((path, ignored))
else:
    names = {'subpasta': 'sub/pasta/trava.json', 'espaco': 'duas palavras.json',
             'aspas': "d'agua.json", 'intencao': 'intencao.txt',
             'blob-vazio': 'vazia.txt', 'link-arquivo': 'link.json',
             'link-pasta': 'pasta-link', 'ilegivel': 'sem-leitura.json'}
    path = '.shipcraft/locks/' + names.get(mode, 'solta.json')
    if mode.startswith('link-'):
        target = scratch / 'alvo'
        if mode == 'link-pasta':
            target.mkdir()
            (target / 'não-deve-aparecer.json').write_text('fora\n')
        else:
            target.write_text('fora\n')
        (repo / path).symlink_to(target, target_is_directory=mode == 'link-pasta')
    else:
        write(path, '' if mode == 'blob-vazio' else 'conteúdo deliberadamente não JSON\n')
    if mode == 'ilegivel':
        (repo / path).chmod(0)
    if mode == 'intencao':
        git('add', '-N', path)
    elif mode == 'blob-vazio':
        git('add', path)
    entries.append((path, mode in ('gitignore', 'info', 'global')))

# Probe at the outer boundary: delegates all of Git except the query whose failure is tested.
env = base_env
if mode in ('consulta-outros', 'consulta-ignorados', 'copia'):
    bindir = scratch / 'git-probe'
    bindir.mkdir()
    trace = scratch / 'consultas.jsonl'
    wrapper = bindir / 'git'
    wrapper.write_text('#!' + sys.executable + '\n'
                       'import json,os,subprocess,sys\n'
                       f'real={real_git!r}; trace={str(trace)!r}; mode={mode!r}\n'
                       'args=sys.argv[1:]\n'
                       'query="ls-files" in args and (any(".shipcraft/locks" in a for a in args) or ".shipcraft/locks" in os.getcwd())\n'
                       'if query:\n'
                       '    with open(trace,"a") as f: f.write(json.dumps(dict(cwd=os.getcwd(),args=args,index=os.environ.get("GIT_INDEX_FILE")))+"\\n")\n'
                       '    ignored="--ignored" in args or "-i" in args\n'
                       '    if (mode=="consulta-ignorados" and ignored) or (mode=="consulta-outros" and "--others" in args and not ignored):\n'
                       '        print("item28-consulta-falhou",file=sys.stderr); sys.exit(47)\n'
                       'os.execv(real,[real]+args)\n')
    wrapper.chmod(0o755)
    env = dict(base_env, PATH=str(bindir) + os.pathsep + base_env['PATH'])
    if mode.startswith('consulta-'):
        # No files: the only line is the warning that the query failed.
        (repo / entries[0][0]).unlink()
        entries = []

ordered = sorted(entries, key=lambda entry: (not entry[0].endswith('.json'), os.fsencode(entry[0])))
expected = [warning(path, ignored) for path, ignored in ordered[:5]]
result = hook(env)
try:
    check_output(result, baseline, expected, max(0, len(entries) - 5), mode.startswith('consulta-'))
    if mode in ('espaco', 'aspas', 'gitignore', 'info', 'global', 'negacao'):
        for line in expected:
            command = line.split('add the lock: ', 1)[1].removesuffix(' (ignored by git)')
            run(['sh', '-c', command])
        for path, _ in entries:
            staged = git('show', ':' + path).stdout
            assert staged == (repo / path).read_text(), 'pasted command added other content'
    if mode == 'copia':
        rows = [json.loads(line) for line in trace.read_text().splitlines()]
        assert rows, 'Git query not observed'
        for row in rows:
            effective = Path(row['cwd'])
            for i, arg in enumerate(row['args'][:-1]):
                if arg == '-C':
                    effective = effective / row['args'][i + 1]
            effective = effective.resolve()
            assert effective == repo or repo in effective.parents, 'query ran in the judged copy'
        assert 'unicodedata.normalize' in (repo / 'textutil.py').read_text(), 'hook changed the original tree'
finally:
    if mode == 'ilegivel':
        (repo / entries[0][0]).chmod(0o644)
