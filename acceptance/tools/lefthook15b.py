#!/usr/bin/env python3
"""Item 15b. Caixa-preta: fixtures YAML e hook instalado, sem lefthook real."""
import copy
import os
import re
from pathlib import Path
import subprocess
import sys
import yaml


def git(*args):
    subprocess.run(['git', *args], check=True, capture_output=True)


def snapshot():
    result = {}
    for root, dirs, files in os.walk('.'):
        dirs[:] = [d for d in dirs if d != '.venv']
        for name in dirs + files:
            p = Path(root, name)
            result[str(p)] = (p.lstat().st_mode, os.readlink(p) if p.is_symlink()
                              else p.read_bytes() if p.is_file() else None)
    return result


# lefthook v1.11.13: internal/templates/hook.tmpl, sem rc, exe fixo ou roots.
HOOK = '''#!/bin/sh

if [ "$LEFTHOOK_VERBOSE" = "1" -o "$LEFTHOOK_VERBOSE" = "true" ]; then
  set -x
fi

if [ "$LEFTHOOK" = "0" ]; then
  exit 0
fi

call_lefthook()
{
  if test -n "$LEFTHOOK_BIN"
  then
    "$LEFTHOOK_BIN" "$@"
  elif lefthook -h >/dev/null 2>&1
  then
    lefthook "$@"
  else
    dir="$(git rev-parse --show-toplevel)"
    osArch=$(uname | tr '[:upper:]' '[:lower:]')
    cpuArch=$(uname -m | sed 's/aarch64/arm64/;s/x86_64/x64/')
    if test -f "$dir/node_modules/lefthook-${osArch}-${cpuArch}/bin/lefthook"
    then
      "$dir/node_modules/lefthook-${osArch}-${cpuArch}/bin/lefthook" "$@"
    elif test -f "$dir/node_modules/@evilmartians/lefthook/bin/lefthook-${osArch}-${cpuArch}/lefthook"
    then
      "$dir/node_modules/@evilmartians/lefthook/bin/lefthook-${osArch}-${cpuArch}/lefthook" "$@"
    elif test -f "$dir/node_modules/@evilmartians/lefthook-installer/bin/lefthook"
    then
      "$dir/node_modules/@evilmartians/lefthook-installer/bin/lefthook" "$@"
    elif test -f "$dir/node_modules/lefthook/bin/index.js"
    then
      "$dir/node_modules/lefthook/bin/index.js" "$@"

    elif go tool lefthook -h >/dev/null 2>&1
    then
      go tool lefthook "$@"
    elif bundle exec lefthook -h >/dev/null 2>&1
    then
      bundle exec lefthook "$@"
    elif yarn lefthook -h >/dev/null 2>&1
    then
      yarn lefthook "$@"
    elif pnpm lefthook -h >/dev/null 2>&1
    then
      pnpm lefthook "$@"
    elif swift package lefthook >/dev/null 2>&1
    then
      swift package --build-path .build/lefthook --disable-sandbox lefthook "$@"
    elif command -v mint >/dev/null 2>&1
    then
      mint run csjones/lefthook-plugin "$@"
    elif uv run lefthook -h >/dev/null 2>&1
    then
      uv run lefthook "$@"
    elif mise exec -- lefthook -h >/dev/null 2>&1
    then
      mise exec -- lefthook "$@"
    else
      echo "Can't find lefthook in PATH"
    fi
  fi
}

call_lefthook run "pre-commit" "$@"
'''



def config_symlink(case):
    names = ('lefthook.yml', '.lefthook.yml', 'lefthook.yaml', '.lefthook.yaml')
    variants = [(names[0], False)] if case.endswith('exemplo') else (
        [(name, False) for name in names[1:]] + [(name, True) for name in names])
    for name, broken in variants:
        label = f'{name} ({"quebrado" if broken else "valido"})'
        target = Path('config-original.yml')
        if not broken:
            target.write_text('pre-commit:\n  commands:\n    lint:\n      run: echo lint\n      priority: 7\n')
        path = Path(name)
        path.symlink_to(target)
        before = snapshot()
        p = subprocess.run(['shipcraft', 'init'], input='', text=True, capture_output=True, timeout=45)
        out = p.stdout + p.stderr
        print(label + '\n' + out)
        assert p.returncode != 0, 'aceitou config simbolica: ' + label
        assert snapshot() == before, (
            'recusa escreveu na arvore ou no destino do link: ' + label)
        lines = [line for line in out.splitlines() if line.strip()]
        assert len(lines) == 3, 'recusa deve ter tres linhas: ' + label
        assert 'shipcraft check' in out, 'recusa sem orientacao manual: ' + label
        assert not any(word in out for word in ('RED', 'GREEN', 'provider', 'who reviews')), (
            'perguntou antes de recusar: ' + label)
        path.unlink()
        if not broken:
            target.unlink()


def main(case):
    if case.startswith('config-link-'):
        return config_symlink(case)
    # Item 20 substitui a recusa que era somente pela ordem.
    migration = case in {
        'numero-omitido', 'numero-zero', 'numero-negativo', 'numero-minimo',
        'numero-limite', 'bloco-parallel', 'prioridade-borda',
    }
    name = 'lefthook.yml'
    data = {'pre-commit': {'commands': {'lint': {'run': 'echo lint', 'priority': 7}}}}
    refuse = False
    hook = None
    raw = None
    env = os.environ.copy()
    rollback = case.startswith('rollback-')
    if case.startswith('fonte-'):
        refuse = True
        kind = case[6:]
        if kind.startswith('env-'):
            env['LEFTHOOK_CONFIG'] = '' if kind.endswith('vazia') else 'outra.yml'
        elif kind in ('remotes', 'rc'):
            data[kind] = [] if kind == 'remotes' else ''
        else:
            extra = Path(kind.replace('config-', '.config/'))
            extra.parent.mkdir(parents=True, exist_ok=True)
            extra.write_text('# outra fonte\n')
    elif case.startswith('layout-'):
        refuse = True
        base = yaml.safe_dump(data, sort_keys=False)
        raw = {
            'flow': 'pre-commit: {commands: {lint: {run: echo lint, priority: 7}}}\n',
            'vazio': 'pre-commit:\n  commands: {}\n',
            'aspas': base.replace('pre-commit:', '"pre-commit":'),
            'aspas-fora': base + '"pre-push":\n  commands:\n',
            'flow-fora': base + 'pre-push: {commands: {push: {run: echo push}}}\n',
            'ancora': base.replace('lint:', 'lint: &lint'),
            'alias': 'defaults: &defaults\n  run: echo lint\n  priority: 7\npre-commit:\n  commands:\n    lint: *defaults\n',
            'ancora-fora': base + 'pre-push: &push\n  commands:\n',
            'merge': 'defaults: &defaults\n  priority: 7\npre-commit:\n  commands:\n    lint:\n      <<: *defaults\n      run: echo lint\n',
            'fim': base + '...\n',
        }[case[7:]]
    elif case.startswith('bytes-') or rollback:
        indent = '    ' if case.endswith('borda') else '  '
        raw = ('# preservar CRLF e comentarios\r\npre-commit:\r\n' + indent + 'commands:\r\n' +
               indent * 2 + 'lint: # corretor\r\n' + indent * 3 + 'run: |\r\n' +
               indent * 4 + 'echo "{...} <<: &ancora"\r\n' + indent * 3 + 'priority: 7\r\n')
        data = yaml.safe_load(raw)
        if rollback:
            # Falha posterior (item 27: sem .github): o init precisa criar .shipcraft/locks, mas .shipcraft e arquivo.
            Path('.shipcraft').write_bytes(b'nao substituir\x00\r\n')
    elif case == 'arquivo-comentario':
        raw, data = '# sem pre-commit\n', {}
    elif case == 'commands-vazio':
        raw = 'pre-commit:\n  commands:\n'
        data = {'pre-commit': {'commands': {}}}
    elif case.startswith('extra-sc2-'):
        refuse = True
        key = case[10:]
        data['pre-commit']['commands']['shipcraft'] = {'run': 'shipcraft check', 'priority': 99, key: {} if key == 'env' else '.'}
    elif case.startswith('numero-'):
        kind = case[7:]
        if kind.endswith('-existente'):
            kind = kind[:-10]
            data['pre-commit']['commands']['shipcraft'] = {'run': 'shipcraft check', 'priority': 99}
        refuse = kind != 'limite-valido'
        values = {'zero': 0, 'negativo': -1, 'minimo': -2147483648,
                  'limite': 2147483647, 'fora': 2147483648, 'fracao': 1.5,
                  'texto': '7', 'bool': True, 'limite-valido': 2147483646}
        if kind in ('hex', 'cientifico'):
            raw = yaml.safe_dump(data, sort_keys=False).replace('priority: 7', 'priority: ' + ('0x7' if kind == 'hex' else '7e0'))
        elif kind == 'omitido':
            del data['pre-commit']['commands']['lint']['priority']
        else:
            data['pre-commit']['commands']['lint']['priority'] = values[kind]
    elif case.startswith('nome-'):
        name = {'comum': 'lefthook.yml', 'oculto': '.lefthook.yml',
                'yaml': 'lefthook.yaml', 'oculto-yaml': '.lefthook.yaml'}[case[5:]]
    elif case.startswith('duplo-'):
        refuse = True
        Path('.lefthook.yaml' if case.endswith('borda') else 'lefthook.yaml').write_text('{}\n')
    elif case.startswith('hook-'):
        hook = HOOK
        if case == 'foreign-hook':
            hook, refuse = '#!/bin/sh\necho outro\n', True
        elif case == 'hook-menciona-lefthook':
            hook, refuse = '#!/bin/sh\n# lefthook\necho outro\n', True
        elif case == 'hook-path-fora':
            git('config', 'core.hooksPath', '.hooks')
            Path('.hooks').mkdir()
            refuse = True
        elif case == 'hook-path-padrao':
            git('config', 'core.hooksPath', '.git/hooks')
        elif case == 'hook-link-quebrado':
            Path('.git/hooks/pre-commit').symlink_to('inexistente')
            refuse, hook = True, None
    elif case.startswith('yaml-'):
        refuse = True
        raw = {'yaml-quebrado': 'pre-commit: [\n',
               'yaml-quase': 'pre-commit:\n  commands: [lint, fmt]\n',
               }[case]
    elif case.startswith(('extends-', 'jobs-')):
        refuse = True
        key, edge = case.split('-')
        if edge == 'comum':
            data[key] = ['base.yml'] if key == 'extends' else [{'run': 'echo job'}]
        else:
            data['pre-commit'][key] = []
    elif case == 'bloco-parallel-fluxo':
        refuse = True
        raw = 'pre-commit: {commands: {lint: {run: echo lint}}, parallel: true}\n'
    elif case.startswith('bloco-'):
        refuse = True
        data['pre-commit']['parallel' if case.endswith('parallel') else 'scripts'] = (
            True if case.endswith('parallel') else {'teste': {'runner': 'bash'}})
    elif case.startswith('filtro-'):
        refuse = True
        key, edge = case[7:].rsplit('-', 1)
        data['pre-commit'][key] = [] if edge == 'borda' else ('*.py' if key == 'glob' else ['teste'])
    elif case.startswith('prioridade-'):
        if case.endswith('borda'):
            data['pre-commit']['commands']['fmt'] = {'run': 'echo fmt && git add .', 'priority': 1000001}
            data['pre-commit']['commands']['sem-prioridade'] = {'run': 'echo zero'}
            refuse = True
    elif case.startswith('preserva-'):
        data['pre-push'] = {'commands': {'push': {'run': 'echo push'}}}
        if case.endswith('borda'):
            data['pre-push'] = {'jobs': [{'run': 'echo push'}]}
            data['pre-commit']['commands']['lint'].update(
                glob='*.py', skip=['merge'], only=['rebase'], exclude=['vendor/**'],
                files='git diff --name-only', stage_fixed=True, env={'TEXTO': 'a: b # c'})
    elif case.startswith('existente-'):
        data['pre-commit']['commands']['shipcraft'] = {'run': 'shipcraft check', 'priority': 99}
        if case.endswith('borda'):
            data['pre-commit']['commands']['lint']['priority'] = 98
    elif case.startswith('ocupado-'):
        refuse = True
        data['pre-commit']['commands']['shipcraft'] = {'run': 'echo ocupado', 'priority': 99} if case.endswith('comum') else {'run': 'shipcraft check', 'priority': 7}
        if case.endswith('filtro'):
            data['pre-commit']['commands']['shipcraft'] = {'run': 'shipcraft check', 'priority': 99, 'glob': '*.py'}
    elif case.startswith('sem-bloco-'):
        refuse = case.endswith('comum')
        data = {} if case.endswith('comum') else {'pre-push': {'commands': {'push': {'run': 'echo push'}}}}
    else:
        raise AssertionError('cenario desconhecido: ' + case)
    path = Path(name)
    path.write_bytes((raw if raw is not None else yaml.safe_dump(data, sort_keys=False)).encode())
    if hook is not None:
        hp = Path('.hooks/pre-commit' if case == 'hook-path-fora' else '.git/hooks/pre-commit')
        hp.write_text(hook)
        hp.chmod(0o755)
    before = snapshot()
    original = path.read_bytes()
    p = subprocess.run(['shipcraft', 'init'] + (['--github'] if rollback else []), env=env, input='', text=True, capture_output=True, timeout=45)
    out = p.stdout + p.stderr
    print(out)
    if rollback:
        assert p.returncode != 0, 'aceitou escrita impossivel'
        assert '.shipcraft/locks' in out, 'nao chegou a falha de escrita posterior em .shipcraft/locks'
        assert not Path('.github').exists(), 'criou .github'
        assert snapshot() == before, 'rollback nao restaurou bytes e modos, inclusive lefthook e .git/shipcraft'
        return
    if migration:
        from item20 import check_pair
        assert p.returncode == 0, 'item 20 deve integrar pela nova rota: ' + case
        after = yaml.safe_load(path.read_text())
        check_pair(after)
        assert after.pop('pre-commit') == data['pre-commit'], 'mudou pre-commit'
        for event in ('commit-msg', 'post-commit'):
            after.pop(event)
        assert after == {k:v for k,v in data.items() if k != 'pre-commit'}, 'mudou outros blocos'
        stable = path.read_bytes()
        repeat = subprocess.run(['shipcraft', 'init'], input='', text=True, capture_output=True, timeout=45)
        assert repeat.returncode == 0 and path.read_bytes() == stable, 'nova rota nao idempotente'
        return
    if refuse:
        assert p.returncode != 0, 'aceitou configuracao insegura: ' + case
        assert snapshot() == before, 'recusa escreveu na arvore: ' + case
        lines = [s for s in out.splitlines() if s.strip()]
        assert len(lines) == 3, 'recusa deve ter tres linhas antes de perguntar'
        if case in ('numero-omitido-existente', 'numero-zero-existente', 'numero-negativo-existente'):
            follow = lines[-1].lower()
            assert 'pre-commit' in follow and 'shipcraft' in follow, 'nao identifica shipcraft antigo'
            assert re.search(r'(remove|delete)', follow), 'nao manda tirar shipcraft do pre-commit'
            assert 'init' in follow, 'nao manda rodar init de novo'
            assert not re.search(r'(put|place|add|insert).*shipcraft check.*pre-commit', follow), 'manda duplicar shipcraft no pre-commit'
        else:
            assert 'shipcraft check' in out, 'recusa sem orientacao manual'
        assert not any(s in out for s in ['RED', 'GREEN', 'provider']), 'perguntou antes de recusar'
        return
    assert p.returncode == 0, 'recusou integracao segura: ' + case
    after = yaml.safe_load(path.read_text())
    commands = after.get('pre-commit', {}).get('commands', {})
    assert 'shipcraft' in commands, 'nao integrou comando shipcraft em ' + name
    shipcraft = commands.pop('shipcraft')
    assert shipcraft.get('run') == 'shipcraft check', 'run deve ser shipcraft check'
    assert type(shipcraft.get('priority')) is int, 'priority deve ser inteiro'
    assert set(shipcraft) == {'run', 'priority'}, 'shipcraft tem chaves extras'
    assert all(shipcraft['priority'] > c['priority'] for c in commands.values()), 'shipcraft nao roda estritamente por ultimo'
    if not case.startswith('existente-'):
        assert shipcraft['priority'] == max((c['priority'] for c in commands.values()), default=0) + 1, 'priority nao e maximo + 1'
    expected = copy.deepcopy(data)
    expected.setdefault('pre-commit', {}).setdefault('commands', {}).pop('shipcraft', None)
    assert after == expected, 'alterou outros comandos ou blocos'
    for file in ('lefthook.yml', '.lefthook.yml', 'lefthook.yaml', '.lefthook.yaml'):
        assert file == name or not Path(file).exists(), 'criou config concorrente'
    hooks_before = {k: v for k, v in before.items() if k.startswith('.git/hooks/')}
    hooks_after = {k: v for k, v in snapshot().items() if k.startswith('.git/hooks/')}
    assert hooks_after == hooks_before, 'criou ou substituiu hook ao integrar lefthook'
    assert name in out, 'lista para commit nao cita arquivo lefthook'
    if case.startswith('existente-'):
        assert path.read_bytes() == original, 'comando shipcraft igual reescreveu arquivo'
    if case.startswith('bytes-'):
        lines = path.read_bytes().splitlines(keepends=True)
        start = next(i for i, line in enumerate(lines) if line.strip() == b'shipcraft:')
        assert b''.join(lines[:start] + lines[start + 3:]) == original, 'reformatou bytes fora do shipcraft'
    before_repeat = path.read_bytes()
    repeat = subprocess.run(['shipcraft', 'init'], input='', text=True, capture_output=True, timeout=45)
    assert repeat.returncode == 0 and path.read_bytes() == before_repeat, 'segundo init nao e idempotente'


if __name__ == '__main__':
    try:
        main(sys.argv[1])
    except AssertionError as error:
        sys.exit('15b: ' + str(error))
