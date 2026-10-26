#!/usr/bin/env python3
"""15a.2: lefthook source without the four names at the root; black box."""
import os
from pathlib import Path
import subprocess
import shlex
import shutil
import tempfile
import sys

import yaml

from lefthook_fixture import snapshot


def config_arquivo(case, env):
    # 15a.2: a .config file is not a source; with YAML at the root it does not change the integration.
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
            assert p.returncode == 0, 'init refused ' + str(root)
            assert (root / '.shipcraft.toml').is_file(), 'did not create its own config'
            assert not (root / '.github').exists(), 'created .github (item 27)'
            hook = root / '.git/hooks/commit-msg'
            if case.endswith('-com-yaml'):
                assert not hook.exists(), 'replaced the integration with its own hook'
                data = yaml.safe_load((root / 'lefthook.yml').read_text())
                assert data['pre-commit']['commands'] == {'lint': {'run': 'echo lint', 'priority': 1}}
                assert data['commit-msg']['commands']['shipcraft'] == {'run': 'shipcraft check --commit-msg'}
                assert data['post-commit']['commands']['shipcraft'] == {'run': 'shipcraft close'}
                results.append((root / 'lefthook.yml').read_bytes())
            else:
                assert hook.is_file() and os.access(hook, os.X_OK), 'did not install its own hook'
                commands = [shlex.split(line) for line in hook.read_text().splitlines()
                            if line.strip() and not line.lstrip().startswith('#')]
                assert any(len(cmd) == 5 and cmd[0] == 'exec' and
                           Path(cmd[1]).name == 'shipcraft' and cmd[2:] == ['check', '--commit-msg', '$1']
                           for cmd in commands), 'own hook does not run shipcraft check --commit-msg'
                results.append(hook.read_bytes())
        assert results[0] == results[1], '.config file changed the init result'
        assert Path('.config').read_bytes() == content, 'changed the .config file'


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
            raise AssertionError('fixture: user can read a folder without permission')
    elif case == 'link-quebrado':
        Path('.config').mkdir()
        Path('.config/lefthook.yml').symlink_to('inexistente.yml')
    elif case == 'git-config-falha':
        # An invalid include makes git config fail: that must not count as no source.
        Path('.git/include-quebrado').write_text('[secao\n')
        with Path('.git/config').open('a') as config:
            config.write('[include]\n\tpath = include-quebrado\n')
        probe = subprocess.run(['git', 'config', '--get', 'core.hooksPath'], capture_output=True)
        assert probe.returncode not in (0, 1), 'fixture: git config did not fail'
    elif case != 'ausente':
        raise AssertionError('unknown scenario: ' + case)
    if case == 'subpasta':
        cwd = Path('packages/api')
        cwd.mkdir(parents=True)
    for name in ('lefthook.yml', '.lefthook.yml', 'lefthook.yaml', '.lefthook.yaml',
                 '.git/hooks/commit-msg', '.shipcraft.toml', '.shipcraft', '.github'):
        assert not os.path.lexists(name), 'preexisting fixture: ' + name
    try:
        before = snapshot()
        p = subprocess.run(['shipcraft', 'init', '--github'], cwd=cwd, env=env,
                           input='', text=True, capture_output=True, timeout=45)
        out = p.stdout + p.stderr
        print(out)
        if accepts:
            assert p.returncode == 0, 'refused a project without a lefthook source: ' + case
            hook = Path('.git/hooks/commit-msg')
            assert hook.is_file() and os.access(hook, os.X_OK), 'did not install its own hook'
            commands = [shlex.split(line) for line in hook.read_text().splitlines()
                        if line.strip() and not line.lstrip().startswith('#')]
            assert any(len(cmd) == 5 and cmd[0] == 'exec' and
                       Path(cmd[1]).name == 'shipcraft' and cmd[2:] == ['check', '--commit-msg', '$1']
                       for cmd in commands), 'own hook does not run shipcraft check --commit-msg'
            assert Path('.shipcraft.toml').is_file(), 'did not create its own config'
            return
        assert p.returncode != 0, (
            'init accepted an unsafe source; own hook installed=' +
            str(Path('.git/hooks/commit-msg').exists()))
        assert snapshot() == before, 'refusal changed the snapshot (including .git and modes)'
        lines = [line for line in out.splitlines() if line.strip()]
        assert len(lines) == 3, 'refusal must have exactly three lines'
        assert len(set(lines)) == 3, 'refusal repeats lines'
        assert 'shipcraft check' in lines[-1], 'last line does not say where to put shipcraft check'
        assert not any(word in out.lower() for word in ('who reviews', 'which reviewer', 'provider', 'red', 'green')), 'asked before refusing'
    finally:
        if locked is not None:
            locked.chmod(0o755)


if __name__ == '__main__':
    try:
        main(sys.argv[1])
    except AssertionError as error:
        sys.exit('15a single source: ' + str(error))
