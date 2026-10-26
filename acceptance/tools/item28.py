#!/usr/bin/env python3
"""Item 28: Git real; falha de consulta injetada somente no limite do Git."""
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
        assert p.returncode == 0, f'saída {p.returncode}: {args}'
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
    # O contrato exige aspas mesmo quando shlex.quote dispensaria as aspas.
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
    assert p.returncode == baseline.returncode, 'aviso mudou o código de saída'
    lines = p.stdout.splitlines()
    warns = [line for line in lines if line.startswith('shipcraft: warning:') and not re.search(r'\band \d+ more\b', line)]
    if query_error:
        assert len(warns) == 1, f'esperado um aviso de consulta: {lines}'
        assert re.fullmatch(r'shipcraft: warning: could not read \.shipcraft/locks/ \(.+\)\.', warns[0]), warns
        assert 'item28-consulta-falhou' in warns[0], 'motivo do git perdido'
    else:
        assert warns == expected, f'avisos esperados {expected!r}, recebidos {warns!r}'
    counter = [line for line in lines if re.search(r'\band \d+ more\b', line)]
    assert len(counter) == (1 if extra else 0), f'contador indevido/ausente: {counter}'
    if extra:
        assert re.search(rf'\band {extra} more\b', counter[0]), counter
    # Avisos e contador têm de vir antes de qualquer saída do julgamento.
    prefix = len(warns) + len(counter)
    assert set(lines[:prefix]) == set(warns + counter), f'aviso tardio: {lines}'
    if baseline.returncode:
        last = [line for line in lines if line.strip()][-3:]
        old = [line for line in baseline.stdout.splitlines() if line.strip()][-3:]
        assert last == old, f'aviso mudou a recusa: {last!r} != {old!r}'
        assert last[0].startswith('shipcraft refused:') and last[1].startswith('Why:') and last[2].startswith('Next:'), last
    elif mode not in ('only', 'only-ignorado'):
        # Tempos e caminhos da cópia podem mudar; o veredito final não.
        tail = [line for line in lines[prefix:] if line.strip()][-1:]
        old = [line for line in baseline.stdout.splitlines() if line.strip()][-1:]
        assert tail == old, f'julgamento mudou: {tail!r} != {old!r}'


# .gitkeep é vazio por definição; removê-lo isola a regra que conta blobs vazios.
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
    # Não testa o valor que o init escreve; pede uma versão certamente futura.
    from h import toml_load
    current = toml_load(Path(__file__).resolve().parents[2] / 'nucleo/Cargo.toml')['package']['version']
    future = str(int(current.split('.')[0]) + 10) + '.0.0'
    cfg = repo / '.shipcraft.toml'
    cfg.write_text(re.sub(r'shipcraft_min\s*=\s*"[^"]*"', f'shipcraft_min = "{future}"', cfg.read_text()))
    git('add', '.shipcraft.toml')
elif mode == 'copia':
    # O índice mantém o stub vermelho; a árvore suja tem a implementação verde.
    write('textutil.py', 'import re, unicodedata\ndef slugify(text):\n    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()\n    return re.sub(r"[^a-zA-Z0-9]+", "-", text).strip("-").lower()\n')
elif mode == 'rastreado':
    write('.shipcraft/locks/rastreada.txt')
    git('add', '.shipcraft/locks/rastreada.txt')

baseline = hook()
assert 'shipcraft: warning:' not in baseline.stdout, f'controle já tinha aviso: {baseline.stdout}'
assert (baseline.returncode != 0) == (mode == 'recusa'), 'fixture com veredito inesperado'
if mode in ('sem-arquivos', 'rastreado'):
    check_output(hook(), baseline, [])
    sys.exit(0)

if mode in ('only', 'only-ignorado'):
    # O Git constrói e passa seu índice temporário ao hook de commit --only.
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
    assert 'shipcraft: warning:' not in hook().stdout, 'arquivo não vazio já está no índice normal'
    write('item28-pendente.txt', 'julgado\n')
    result = git('-c', f'core.hooksPath={hooks}', 'commit', '--only', '-qm', 'chore: julgado', '--', 'item28-pendente.txt', ok=False)
    assert receipt.read_text().strip() and not receipt.read_text().strip().endswith('/index'), 'Git não forneceu índice temporário'
    check_output(result, before, [warning(path, mode == 'only-ignorado')])
    assert git('ls-tree', '--name-only', 'HEAD', '--', path).stdout == '', 'trava entrou no commit --only'
    assert path in git('ls-files', '--', path).stdout, 'índice normal foi perdido'
    sys.exit(0)

entries = []
if mode in ('cinco', 'seis', 'sete'):
    # C.json vem antes de a.json em bytes, sem colisão em APFS sem caixa.
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

# Sonda do limite externo: delega todo Git, salvo a consulta cuja falha é testada.
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
        # Sem arquivos: a única linha é o aviso de que não conseguiu consultar.
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
            assert staged == (repo / path).read_text(), 'comando colado adicionou outro conteúdo'
    if mode == 'copia':
        rows = [json.loads(line) for line in trace.read_text().splitlines()]
        assert rows, 'consulta Git não observada'
        for row in rows:
            effective = Path(row['cwd'])
            for i, arg in enumerate(row['args'][:-1]):
                if arg == '-C':
                    effective = effective / row['args'][i + 1]
            effective = effective.resolve()
            assert effective == repo or repo in effective.parents, 'consulta feita na cópia julgada'
        assert 'unicodedata.normalize' in (repo / 'textutil.py').read_text(), 'hook mudou árvore original'
finally:
    if mode == 'ilegivel':
        (repo / entries[0][0]).chmod(0o644)
