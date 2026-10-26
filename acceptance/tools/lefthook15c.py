#!/usr/bin/env python3
"""Item 15c. Hook real v1.11.13; executor minimo offline dos commands."""
import os
from pathlib import Path
import subprocess
import shutil
import shlex
import sys
import yaml
from lefthook15b import HOOK


def run(*args):
    p = subprocess.run(args, input='', text=True, capture_output=True, timeout=90)
    print(p.stdout + p.stderr)
    return p


def hook_sem_exec(case):
    path = Path('lefthook.yml')
    hp = Path('.git/hooks/pre-commit')
    data = {'pre-commit': {'commands': {'projeto': {'run': 'echo projeto', 'priority': 3}}}}
    status = case.startswith('status-')
    if status:
        data['pre-commit']['commands']['shipcraft'] = {'run': 'shipcraft check', 'priority': 9}
    path.write_text(yaml.safe_dump(data, default_flow_style=False, sort_keys=False))
    hp.write_text(HOOK)
    hp.chmod(0o644)
    assert not os.access(hp, os.X_OK), 'fixture do hook deve estar sem execucao'
    p = run('shipcraft', 'status' if status else 'init')
    assert p.returncode == 0, 'init/status recusou hook lefthook sem execucao'
    if status:
        out = (p.stdout + p.stderr).lower()
        assert 'hook through lefthook' not in out and 'missing' in out, 'status deve indicar missing hook quando lefthook nao tem bit de execucao'
    else:
        commands = yaml.safe_load(path.read_text())['pre-commit']['commands']
        assert commands.get('shipcraft', {}).get('run') == 'shipcraft check', 'init nao integrou shipcraft check com hook sem execucao'
        assert commands['projeto'] == data['pre-commit']['commands']['projeto'], 'init alterou comando do projeto'
        assert sum('lefthook install' in line for line in (p.stdout + p.stderr).splitlines()) == 1, 'hook sem execucao: falta orientacao em uma linha para lefthook install'
    assert hp.read_text() == HOOK and hp.stat().st_mode & 0o777 == 0o644, 'init/status alterou hook lefthook sem execucao'


def main(case):
    if case in ('init-sem-exec-comum', 'status-sem-exec-borda'):
        return hook_sem_exec(case)
    edge = case.endswith('borda')
    name = '.lefthook.yaml' if edge else 'lefthook.yml'
    path = Path(name)
    data = {'pre-commit': {'commands': {'projeto': {'run': 'echo projeto >> projeto.log', 'priority': 3}}}}
    path.write_text(yaml.safe_dump(data, default_flow_style=False, sort_keys=False))
    hp = Path('.git/hooks/pre-commit')
    if case.startswith('status-'):
        data['pre-commit']['commands']['shipcraft'] = {'run': 'shipcraft check', 'priority': 9}
        path.write_text(yaml.safe_dump(data, default_flow_style=False, sort_keys=False))
        hp.write_text(HOOK)
        hp.chmod(0o755)
    p = run('shipcraft', 'status') if case.startswith('status-') else run('shipcraft', 'init')
    assert p.returncode == 0, 'init/status recusou integracao segura'
    commands = yaml.safe_load(path.read_text())['pre-commit']['commands']
    assert commands.get('shipcraft', {}).get('run') == 'shipcraft check', 'init nao integrou shipcraft check'
    if case.startswith('init-'):
        assert not hp.exists(), 'init instalou hook proprio sem lefthook instalado'
        assert sum('lefthook install' in s for s in (p.stdout+p.stderr).splitlines()) == 1, 'falta orientacao em uma linha: lefthook install'
        if edge:
            p = run('shipcraft', 'init')
            assert p.returncode == 0 and not hp.exists(), 'segundo init instalou hook proprio'
        p = run('shipcraft', 'status')
        out = (p.stdout+p.stderr).lower()
        assert 'hook through lefthook' not in out and 'missing' in out, 'status sem hook deve indicar ausente'
    elif case.startswith('status-'):
        p = run('shipcraft', 'status')
        assert 'hook through lefthook' in p.stdout+p.stderr, 'status nao reconhece hook real com comando shipcraft'
        if edge:
            for replacement in (None, {'run': 'echo shipcraft check', 'priority': 9}):
                d = yaml.safe_load(path.read_text())
                if replacement is None:
                    del d['pre-commit']['commands']['shipcraft']
                else:
                    d['pre-commit']['commands']['shipcraft'] = replacement
                path.write_text(yaml.safe_dump(d, default_flow_style=False, sort_keys=False))
                p = run('shipcraft', 'status')
                out = (p.stdout+p.stderr).lower()
                assert 'hook through lefthook' not in out and 'missing' in out, 'status anuncia lefthook sem comando shipcraft check valido'
    else:
        assert commands['projeto'] == data['pre-commit']['commands']['projeto'], 'init alterou comando do projeto'
        # Executa somente a superficie usada aqui; nao simula install nem reconhecimento.
        executor = Path(os.environ['TMPDIR']) / 'lefthook-executor.py'
        executor.write_text('#!' + sys.executable + '\n' + '''import subprocess, sys, yaml
from pathlib import Path
assert sys.argv[1:] == ['run', 'pre-commit']
p = next(p for p in map(Path, ['lefthook.yml','.lefthook.yml','lefthook.yaml','.lefthook.yaml']) if p.exists())
cs = yaml.safe_load(p.read_text())['pre-commit']['commands']
result = 0
for name, c in sorted(cs.items(), key=lambda pair: pair[1].get('priority', 0) or float('inf')):
    p = subprocess.run(c['run'], shell=True)
    if p.returncode: result = p.returncode
sys.exit(result)
''')
        executor.chmod(0o755)
        real_shipcraft = shutil.which('shipcraft')
        wrapper_dir = executor.parent / 'shipcraft-probe'
        wrapper_dir.mkdir()
        wrapper = wrapper_dir / 'shipcraft'
        wrapper.write_text('#!/bin/sh\necho shipcraft >> projeto.log\nexec ' + shlex.quote(real_shipcraft) + ' "$@"\n')
        wrapper.chmod(0o755)
        os.environ['PATH'] = str(wrapper_dir) + os.pathsep + os.environ['PATH']
        os.environ['LEFTHOOK_BIN'] = str(executor)
        hp.write_text(HOOK)
        hp.chmod(0o755)
        if edge:
            d = yaml.safe_load(path.read_text())
            d['pre-commit']['commands']['projeto']['run'] = 'echo projeto >> projeto.log; exit 23'
            path.write_text(yaml.safe_dump(d, default_flow_style=False, sort_keys=False))
        p = run('sh', str(hp))
        assert Path('projeto.log').read_text() == 'projeto\nshipcraft\n', 'comandos nao executaram na ordem projeto, shipcraft'
        if edge:
            assert p.returncode != 0, 'hook ignorou falha do comando do projeto'
        else:
            assert p.returncode == 0, 'hook integrado recusou projeto sem trava'


if __name__ == '__main__':
    try:
        main(sys.argv[1])
    except AssertionError as error:
        sys.exit('15c: ' + str(error))
