#!/usr/bin/env python3
"""15a.2: fonte do lefthook sem os quatro nomes na raiz; caixa-preta."""
import os
from pathlib import Path
import subprocess
import shlex
import shutil
import tempfile
import sys

import yaml

from lefthook15b import snapshot


def config_arquivo(case, env):
    # 15a.2: arquivo .config nao e fonte; com YAML na raiz nao muda a integracao.
    content = b'unrelated configuration\n'
    with tempfile.TemporaryDirectory(prefix='fonte15a-controle-') as tmp:
        control = Path(tmp) / 'repo'
        shutil.copytree(Path.cwd(), control)
        if case.endswith('-com-yaml'):
            original = 'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n      priority: 1\n'
            Path('lefthook.yml').write_text(original)
            (control / 'lefthook.yml').write_text(original)
        Path('.config').write_bytes(content)
        results = []
        for root in (control, Path.cwd()):
            p = subprocess.run(['shipcraft', 'init', '--lang', 'python', '--github'],
                               cwd=root, env=env, input='', text=True,
                               capture_output=True, timeout=45)
            print(p.stdout + p.stderr)
            assert p.returncode == 0, 'init recusou ' + str(root)
            assert (root / '.shipcraft.toml').is_file(), 'nao criou config propria'
            assert not (root / '.github').exists(), 'criou .github (item 27)'
            hook = root / '.git/hooks/pre-commit'
            if case.endswith('-com-yaml'):
                assert not hook.exists(), 'substituiu integracao por hook proprio'
                data = yaml.safe_load((root / 'lefthook.yml').read_text())
                commands = data['pre-commit']['commands']
                assert commands['lint'] == {'run': 'echo lint', 'priority': 1}
                assert commands['shipcraft'] == {'run': 'shipcraft check', 'priority': 2}
                results.append((root / 'lefthook.yml').read_bytes())
            else:
                assert hook.is_file() and os.access(hook, os.X_OK), 'nao instalou hook proprio'
                commands = [shlex.split(line) for line in hook.read_text().splitlines()
                            if line.strip() and not line.lstrip().startswith('#')]
                assert any(len(cmd) == 3 and cmd[0] == 'exec' and
                           Path(cmd[1]).name == 'shipcraft' and cmd[2] == 'check'
                           for cmd in commands), 'hook proprio nao roda shipcraft check'
                results.append(hook.read_bytes())
        assert results[0] == results[1], '.config arquivo mudou o resultado do init'
        assert Path('.config').read_bytes() == content, 'alterou .config arquivo'


def main(case):
    env = os.environ.copy()
    env.pop('LEFTHOOK_CONFIG', None)
    if case in ('config-arquivo', 'config-arquivo-com-yaml'):
        return config_arquivo(case, env)
    cwd = Path.cwd()
    locked = None
    accepts = case in ('ausente', 'parecido-extensao', 'parecido-subpasta')
    paths = {
        'config-yml': '.config/lefthook.yml',
        'toml': 'lefthook.toml',
        'oculto-jsonc': '.lefthook.jsonc',
        'local-yml': 'lefthook-local.yml',
        'config-local-yaml': '.config/lefthook-local.yaml',
        'subpasta': '.config/lefthook.yml',
        'parecido-extensao': 'lefthook.txt',
        'parecido-subpasta': 'outra/lefthook.yml',
    }
    if case in paths:
        path = Path(paths[case])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('pre-commit:\n  commands:\n')
    elif case.startswith('env-'):
        env['LEFTHOOK_CONFIG'] = '' if case == 'env-vazia' else 'inexistente.yml'
    elif case == 'config-ilegivel':
        locked = Path('.config')
        locked.mkdir()
        locked.chmod(0o111)
        try:
            os.listdir(locked)
        except PermissionError:
            pass
        else:
            locked.chmod(0o755)
            raise AssertionError('fixture: usuario consegue ler pasta sem permissao')
    elif case == 'link-quebrado':
        Path('.config').mkdir()
        Path('.config/lefthook.yml').symlink_to('inexistente.yml')
    elif case == 'git-config-falha':
        # Um include invalido faz git config falhar: nao pode virar ausencia de fonte.
        Path('.git/include-quebrado').write_text('[secao\n')
        with Path('.git/config').open('a') as config:
            config.write('[include]\n\tpath = include-quebrado\n')
        probe = subprocess.run(['git', 'config', '--get', 'core.hooksPath'], capture_output=True)
        assert probe.returncode not in (0, 1), 'fixture: git config nao falhou'
    elif case != 'ausente':
        raise AssertionError('cenario desconhecido: ' + case)
    if case == 'subpasta':
        cwd = Path('packages/api')
        cwd.mkdir(parents=True)
    for name in ('lefthook.yml', '.lefthook.yml', 'lefthook.yaml', '.lefthook.yaml',
                 '.git/hooks/pre-commit', '.shipcraft.toml', '.shipcraft', '.github'):
        assert not os.path.lexists(name), 'fixture preexistente: ' + name
    try:
        before = snapshot()
        p = subprocess.run(['shipcraft', 'init', '--github'], cwd=cwd, env=env,
                           input='', text=True, capture_output=True, timeout=45)
        out = p.stdout + p.stderr
        print(out)
        if accepts:
            assert p.returncode == 0, 'recusou projeto sem fonte lefthook: ' + case
            hook = Path('.git/hooks/pre-commit')
            assert hook.is_file() and os.access(hook, os.X_OK), 'nao instalou hook proprio'
            commands = [shlex.split(line) for line in hook.read_text().splitlines()
                        if line.strip() and not line.lstrip().startswith('#')]
            assert any(len(cmd) == 3 and cmd[0] == 'exec' and
                       Path(cmd[1]).name == 'shipcraft' and cmd[2] == 'check'
                       for cmd in commands), 'hook proprio nao roda shipcraft check'
            assert Path('.shipcraft.toml').is_file(), 'nao criou config propria'
            return
        assert p.returncode != 0, (
            'init aceitou fonte insegura; hook proprio instalado=' +
            str(Path('.git/hooks/pre-commit').exists()))
        assert snapshot() == before, 'recusa alterou snapshot (inclusive .git e modos)'
        lines = [line for line in out.splitlines() if line.strip()]
        assert len(lines) == 3, 'recusa deve ter exatamente tres linhas'
        assert len(set(lines)) == 3, 'recusa repete linhas'
        assert 'shipcraft check' in lines[-1], 'ultima linha nao orienta onde por shipcraft check'
        assert not any(word in out.lower() for word in ('who reviews', 'which reviewer', 'provider', 'red', 'green')), 'perguntou antes de recusar'
    finally:
        if locked is not None:
            locked.chmod(0o755)


if __name__ == '__main__':
    try:
        main(sys.argv[1])
    except AssertionError as error:
        sys.exit('15a fonte unica: ' + str(error))
