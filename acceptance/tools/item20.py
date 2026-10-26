#!/usr/bin/env python3
"""Item 20: init/status caixa-preta; template lefthook v1.11.13 do 15b."""
import re
import shutil
import subprocess
import sys
from pathlib import Path
import yaml
import tomli
from lefthook_fixture import HOOK, snapshot

PACKAGE_VERSION = tomli.loads((Path(__file__).resolve().parents[2] / 'nucleo/Cargo.toml').read_text())['package']['version']
CURRENT_MIN = '.'.join(PACKAGE_VERSION.split('.')[:2])
FUTURE_MIN = str(int(PACKAGE_VERSION.split('.')[0]) + 1) + '.0'

EVENTS = ('commit-msg', 'post-commit')
RUNS = dict(zip(EVENTS, ('shipcraft check --commit-msg', 'shipcraft close')))


def run(*args):
    p = subprocess.run(args, input='', text=True, capture_output=True, timeout=90)
    print('$', ' '.join(args), '\n', p.stdout, p.stderr, flush=True)
    return p, p.stdout + p.stderr


def installed(event, args=True, executable=True):
    p = Path('.git/hooks') / event
    p.write_text(HOOK.replace('run "pre-commit"', 'run "' + event + '"')
                 .removesuffix('call_lefthook run "' + event + '" "$@"\n') +
                 'call_lefthook run "' + event + '"' + (' "$@"' if args else '') + '\n')
    p.chmod(0o755 if executable else 0o644)


def pair(data):
    for event in EVENTS:
        data[event] = {'commands': {'shipcraft': {'run': RUNS[event]}}}


def check_pair(data):
    for event in EVENTS:
        assert ((data.get(event) or {}).get('commands') or {}).get('shipcraft') == {'run': RUNS[event]}, 'comando incorreto: ' + event
    assert 'shipcraft' not in (data.get('pre-commit') or {}).get('commands', {}), 'duplicou shipcraft no pre-commit'


def main(case):
    parts = case.split('.')
    kind = parts[0]
    data = {'pre-commit': {'parallel': True, 'commands': {'lint': {'run': 'echo lint'}}}}
    refuse = False
    raw = None
    reason = None
    if kind == 'rota':
        value = parts[1]
        c = data['pre-commit']['commands']['lint']
        if value != 'parallel-true':
            data['pre-commit'].pop('parallel')
        if value in ('zero', 'negativa', 'maxima'):
            c['priority'] = {'zero': 0, 'negativa': -1, 'maxima': 2147483647}[value]
        elif value in EVENTS:
            c['priority'] = 7
            data[value] = {'commands': {'shipcraft': {'run': RUNS[value]}}}
        elif value == 'pre-restricoes':
            data['pre-commit'].update(skip=True, jobs=[{'run': 'echo job'}], scripts={'x': {'runner': 'bash'}})
    elif kind == 'vazio':
        event, value = parts[1:]
        # O outro bloco ja tem um comando de projeto: nao pode ser perdido.
        other = next(e for e in EVENTS if e != event)
        data[other] = {'commands': {'mensagem': {'run': 'echo mensagem'}}}
        if value != 'ausente':
            if value == 'commands-vazio':
                refuse = True  # 8aa952f: mapa vazio inline continua sendo flow.
            data[event] = {'nulo': None, 'commands-nulo': {'commands': None},
                           'commands-vazio': {'commands': {}}}[value]
    elif kind == 'bloco':
        event, key = parts[1:]
        refuse, reason = True, key
        data[event] = {key: True if key in ('parallel', 'piped', 'skip') else '*.py'}
    elif kind == 'shipcraft':
        event, value = parts[1:]
        pair(data)
        refuse, reason = True, event
        command = data[event]['commands']['shipcraft']
        if value == 'run':
            command['run'] += ' --outro'
        else:
            command[value] = 1 if value == 'priority' else True
    elif kind == 'hook':
        event, value = parts[1:]
        for e in ('pre-commit', *EVENTS):
            installed(e, args=value != 'sem-args', executable=not (e == event and value == 'sem-exec'))
        hp = Path('.git/hooks') / event
        if value == 'alheio':
            hp.write_text('#!/bin/sh\necho alheio\n')
            refuse, reason = True, event
        elif value == 'link':
            hp.unlink(); hp.symlink_to('inexistente')
            refuse, reason = True, event
    elif kind in ('min', 'min-alto', 'rollback'):
        p, _ = run('shipcraft', 'init')
        assert p.returncode == 0, 'fixture init inicial'
        # The plain-git init installed shipcraft's own hooks; lefthook installs its own.
        for e in EVENTS:
            Path('.git/hooks', e).unlink(missing_ok=True)
        cfg = Path('.shipcraft.toml')
        text = cfg.read_text()
        assert re.search(r'^shipcraft_min\s*=', text, re.M), 'fixture sem shipcraft_min'
        minimum = FUTURE_MIN if kind == 'min-alto' else '0.0'
        cfg.write_text(re.sub(r'^shipcraft_min\s*=.*$', 'shipcraft_min = "' + minimum + '"', text, flags=re.M) + '\n# comentario preservado\n')
        old_config = tomli.loads(cfg.read_text())
        if kind == 'rollback':
            # Falha posterior (item 27: sem .github): .shipcraft vira arquivo e o init nao cria .shipcraft/locks.
            shutil.rmtree('.shipcraft')
            Path('.shipcraft').write_bytes(b'nao substituir\r\n')
    elif kind in ('duplo', 'trava'):
        pair(data)
        data['pre-commit']['commands']['shipcraft'] = {'run': 'shipcraft check', 'priority': 9}
        refuse, reason = True, 'pre-commit'
        if kind == 'trava':
            Path('.git/hooks/pre-commit').unlink(missing_ok=True)
    elif kind == 'status':
        p, _ = run('shipcraft', 'init')
        assert p.returncode == 0, 'fixture status: init inicial falhou'
        Path('.git/hooks/pre-commit').unlink(missing_ok=True)
        pair(data)
        for e in EVENTS:
            installed(e)
        value = parts[1]
        if value != 'completo':
            event = parts[2]
            if value in ('comando', 'ambos'):
                del data[event]['commands']['shipcraft']
            if value in ('hook', 'ambos'):
                Path('.git/hooks', event).unlink()
            if value == 'invalido':
                data[event]['commands']['shipcraft']['skip'] = True
            if value == 'sem-exec':
                Path('.git/hooks', event).chmod(0o644)
    elif kind == 'fonte':
        refuse = True
        value = parts[1]
        if value == 'local': Path('lefthook-local.yml').write_text('# outra fonte\n')
        elif value == 'duplo': Path('.lefthook.yaml').write_text('# outra config\n')
        elif value == 'husky': Path('.husky').mkdir()
        elif value == 'link':
            Path('config-original.yml').write_text(yaml.safe_dump(data, sort_keys=False))
            Path('lefthook.yml').symlink_to('config-original.yml')
        else: data[value] = []
    elif kind == 'yaml':
        value = parts[1]
        base = yaml.safe_dump(data, sort_keys=False)
        if value in ('cr', 'ls', 'ps'):
            raw = base.replace('\n', {'cr': '\r', 'ls': '\u2028', 'ps': '\u2029'}[value])
        elif value == 'crlf': raw = base.replace('\n', '\r\n')
        elif value == 'bom': raw = '\ufeff' + base
        elif value == 'comentario': raw = base.replace('parallel: true', 'parallel: true # paralelo')
        elif value == 'literal':
            data['pre-commit']['commands']['lint']['run'] = 'echo "{...} <<: &ancora"'
        else:
            refuse = True
            raw = {'repetida-comando': base + 'commit-msg:\n  commands:\n    shipcraft:\n      run: shipcraft check --commit-msg\n      run: shipcraft check --commit-msg\n',
                   'repetida': base + 'commit-msg:\n  commands:\ncommit-msg:\n  commands:\n',
                   'flow': 'pre-commit: {parallel: true, commands: {lint: {run: echo lint}}}\n',
                   'aspas': base.replace('pre-commit:', '"pre-commit":'),
                   'ancora': base.replace('lint:', 'lint: &lint'),
                   'fim': base + '...\n'}[value]
    else:
        raise AssertionError('caso desconhecido: ' + case)
    path = Path('lefthook.yml')
    path.write_bytes((raw if raw is not None else yaml.safe_dump(data, sort_keys=False)).encode())
    before = snapshot()
    if kind == 'status':
        p, out = run('shipcraft', 'status')
        assert p.returncode == 0
        if parts[1] == 'completo':
            assert 'hook through lefthook (commit-msg)' in out.lower(), 'status nao reconheceu rota'
        else:
            assert 'missing hook' in out.lower() and 'hook through lefthook' not in out.lower(), 'status anuncia hook incompleto'
            assert parts[2] in out, 'status nao identifica evento que falta'
            if parts[1] in ('comando', 'ambos', 'invalido'): assert 'command' in out.lower(), 'status nao identifica comando ausente'
            if parts[1] in ('hook', 'ambos', 'sem-exec'):
                detail = out.lower().replace('missing hook', '')
                assert 'hook' in detail or 'lefthook install' in detail, 'status nao explica launcher ausente'
        assert snapshot() == before, 'status escreveu'
        return
    p, out = run('shipcraft', 'init', *(['--github'] if kind == 'rollback' else []))
    if refuse or kind == 'rollback':
        assert p.returncode != 0, 'aceitou configuracao que deve recusar'
        assert snapshot() == before, 'recusa/rollback mudou bytes, modos ou .git/shipcraft'
        if kind == 'rollback':
            assert '.shipcraft/locks' in out, 'nao chegou a falha posterior da transacao'
            assert not Path('.github').exists(), 'criou .github'
            return
        lines = [x for x in out.splitlines() if x.strip()]
        assert len(lines) == 3, 'recusa deve ter tres linhas, antes de perguntar'
        assert not re.search(r'(put|place|add|insert).*shipcraft check.*pre-commit', lines[-1], re.I), 'orientou shipcraft check no pre-commit paralelo'
        if reason: assert reason in lines[-1], 'terceira linha nao identifica impedimento: ' + reason
        if kind == 'trava': assert re.search(r'close', lines[-1], re.I), 'deve mandar fechar trava antes'
        return
    assert p.returncode == 0, 'recusou integracao segura'
    after = yaml.safe_load(path.read_text())
    check_pair(after)
    if kind == 'yaml':
        assert before['lefthook.yml'][1] in path.read_bytes(), 'reformatou bytes originais do YAML'
    assert 'commands: {}' not in path.read_text(), 'nao escreveu bloco vazio em bloco'
    assert after['pre-commit'] == data['pre-commit'], 'alterou pre-commit'
    for e in EVENTS:
        for name, command in ((data.get(e) or {}).get('commands') or {}).items():
            assert after[e]['commands'][name] == command, 'alterou comando existente'
    config = tomli.loads(Path('.shipcraft.toml').read_text())
    assert re.fullmatch(r'\d+\.\d+', str(config['shipcraft_min'])), 'shipcraft_min fora do formato 9.2'
    expected = FUTURE_MIN if kind == 'min-alto' else CURRENT_MIN
    assert config['shipcraft_min'] == expected, 'shipcraft_min must match package major/minor and preserve higher requirements'
    if kind in ('min', 'min-alto'):
        assert {k:v for k,v in config.items() if k != 'shipcraft_min'} == {k:v for k,v in old_config.items() if k != 'shipcraft_min'}, 'mudou restante do TOML'
        assert '# comentario preservado' in Path('.shipcraft.toml').read_text(), 'apagou comentario existente'
    assert 'lefthook.yml' in out, 'lista para commit omite lefthook'
    missing = [e for e in ('pre-commit', *EVENTS) if not Path('.git/hooks', e).exists() or not Path('.git/hooks', e).stat().st_mode & 0o111]
    notices = [line for line in out.splitlines() if 'lefthook install' in line]
    if missing:
        assert len(notices) == 1 and all(e in notices[0] for e in missing), 'aviso unico deve listar hooks que faltam'
    assert {k:v for k,v in snapshot().items() if k.startswith('.git/hooks/')} == {k:v for k,v in before.items() if k.startswith('.git/hooks/')}, 'init alterou hooks'
    stable = (path.read_bytes(), Path('.shipcraft.toml').read_bytes())
    p, _ = run('shipcraft', 'init')
    assert p.returncode == 0 and stable == (path.read_bytes(), Path('.shipcraft.toml').read_bytes()), 'init nao idempotente'


if __name__ == '__main__':
    try: main(sys.argv[1])
    except AssertionError as error: sys.exit('20: ' + str(error))
