#!/usr/bin/env python3
"""Item 22: contract observed in the suite process; without reading the core."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


def run(*args, ok=True, env=None):
    p = subprocess.run(args, text=True, capture_output=True, timeout=90, env=env)
    print('$', shlex.join(args), '\n', p.stdout, p.stderr, flush=True)
    if ok:
        assert p.returncode == 0, f'exit {p.returncode}: {args}'
    return p


def git(*args):
    return run('git', *args).stdout.strip()


def runner():
    data = json.loads(Path('cases.json').read_text())
    phase = Path('value').read_text().strip()
    row = dict(cwd=os.getcwd(), phase=phase, argv=sys.argv[2:], env={})
    for key in ('SHIPCRAFT_CASES', 'SHIPCRAFT_FILES'):
        val = os.environ.get(key)
        row['env'][key] = None if val is None else dict(path=val, hex=Path(val).read_bytes().hex() if Path(val).is_file() else None)
    row['tmp'] = str(Path(subprocess.check_output(['git', 'rev-parse', '--git-path', 'shipcraft/tmp'], text=True).strip()).resolve())
    with open(os.environ['ITEM22_LOG'], 'a') as f:
        f.write(json.dumps(row) + '\n')
    if sys.argv[2] == 'probe':
        return
    target = next((a.split('=', 1)[1] for a in sys.argv[2:] if a.startswith('--junitxml=') or a.startswith('--outputFile=') or a.startswith('--junitfile=')), sys.argv[2])
    selected = sys.argv[sys.argv.index('--selected') + 1:] if '--selected' in sys.argv else None
    suite = ET.Element('testsuite')
    for c in data:
        ident = (c.get('class', '') + '::' if c.get('class') else '') + c['name']
        if (phase == 'omit' or (phase == 'omit-one' and c['name'] == 'test_0')) and c.get('red'):
            continue
        if selected is not None and ident not in selected:
            continue
        attrs = dict(name=c['name'])
        if c.get('class'):
            attrs['classname'] = c['class']
        if c.get('file'):
            attrs['file'] = c['file']
        node = ET.SubElement(suite, 'testcase', attrs)
        if (phase == 'red' and c.get('red')) or (phase == 'old-fails' and not c.get('red')):
            ET.SubElement(node, 'failure', message='falha deliberada')
        if (phase == 'skip' or (phase == 'skip-one' and c['name'] == 'test_0')) and c.get('red'):
            ET.SubElement(node, 'skipped')
    Path(target).parent.mkdir(parents=True, exist_ok=True)
    ET.ElementTree(suite).write(target, encoding='utf-8', xml_declaration=True)


def rows():
    return [json.loads(x) for x in Path(os.environ['ITEM22_LOG']).read_text().splitlines()]


def clear():
    Path(os.environ['ITEM22_LOG']).write_text('')


def main(case, binary):
    os.environ['ITEM22_LOG'] = str(Path(os.environ['TMPDIR']) / 'item22-observed.jsonl')
    clear()
    # A project of its own, with its own minimum version; it does not test the version init writes.
    root = Path('item22-project')
    root.mkdir()
    os.chdir(root)
    git('init', '-q', '-b', 'main')
    git('config', 'user.name', 'Aceite RED')
    git('config', 'user.email', 'red@example.invalid')
    temp_root = Path(git('rev-parse', '--git-path', 'shipcraft/tmp')).resolve()
    shutil.copyfile(__file__, 'runner.py')
    Path('tests').mkdir()
    names = ['test_z.py', 'test_espaço.py', 'test_"aspas.py', "test_'simples.py", 'test_linha\nsegunda.py'] if case in ('bytes-borda', 'bash') else ['test_a.py', 'test_b.py']
    data = []
    for i, name in enumerate(names):
        Path('tests', name).write_text('teste travado\n')
        data.append(dict(name=['z comum', 'é "aspas"', "a 'simples'", 'linha\nsegunda', 'sem classe'][i] if case in ('bytes-borda', 'bash') else 'test_' + str(i),
                         **({'class': 'tests.' + name[:-3]} if i != len(names)-1 or case not in ('bytes-borda', 'bash') else {}), file='tests/' + name, red=True))
    data.append(dict(name='old', **{'class': 'tests.test_old'}, file='tests/test_old.py', red=False))
    Path('tests/test_old.py').write_text('antigo\n')
    Path('tests/helpers').mkdir()
    Path('tests/helpers/fixture.txt').write_text('apoio\n')
    if case in ('sem-mapa', 'parcial'):
        for c in data[:len(names) if case == 'sem-mapa' else 1]:
            c.pop('file', None)
            c['class'] = 'externo'
    if case.startswith('filtro-') and case.split('-')[-1] in ('jest', 'vitest'):
        for c in data:
            old = c['file']
            c['file'] = old.replace('.py', '.test.ts')
            Path(old).rename(c['file'])
            c['class'] = c['file']
    if case == 'lista-grande':
        data = [dict(data[0], name=f'caso-{i:05d}-' + 'x' * 256) for i in range(2000)] + [data[-1]]
    if case == 'listas-dedup':
        data.insert(1, dict(data[0], name='outro caso'))
        data.insert(2, dict(data[0]))
    Path('cases.json').write_text(json.dumps(data))
    Path('value').write_text('red')
    Path('.gitignore').write_text('.reports/\n')
    py = shlex.quote(sys.executable)
    # Bash example: NUL kept, a single call; absence means the whole suite.
    Path('suite.sh').write_text('''#!/usr/bin/env bash
args=()
if [ -n "${SHIPCRAFT_CASES:-}" ]; then
  args+=(--selected)
  while IFS= read -r -d '' caso; do args+=("$caso"); done < "$SHIPCRAFT_CASES"
fi
exec ''' + py + ''' runner.py --runner "$1" "${args[@]}"
''')
    filtra = 'command' if case in ('bash', 'old-omitido', 'sumiu-comando', 'sumiu-parcial') or case.startswith('filtro-comando') else 'shipcraft'
    cmd = f'{py} runner.py --runner {{junit}}'
    runner_name = 'desconhecido'
    if case in ('bash', 'old-omitido'):
        cmd = 'bash suite.sh {junit}'
    if case.startswith('filtro-'):
        parts = case.split('-')
        runner_name = parts[-1]
        Path('bin').mkdir()
        exe = Path('bin', runner_name)
        exe.write_text('#!/bin/sh\nexec ' + py + ' runner.py --runner "$@"\n')
        exe.chmod(0o755)
        os.environ['PATH'] = str(Path('bin').resolve()) + ':' + os.environ['PATH']
        args = {'pytest': '--junitxml={junit} tests', 'vitest': 'run --reporter=junit --outputFile={junit}', 'jest': '--outputFile={junit}', 'go': 'test ./... --junitfile={junit}'}
        cmd = runner_name + ' ' + args[runner_name]
        if 'comentario' in case:
            cmd = '# SHIPCRAFT_CASES\n' + cmd
        if 'backup' in case:
            cmd = 'SHIPCRAFT_CASES_BACKUP=qualquer ' + cmd
    field = '' if 'padrao' in case or 'comentario' in case or 'backup' in case else 'filter = ' + json.dumps({'filtra-invalido': 'errado', 'filtra-invalido-vazio': '', 'filtra-invalido-maiusculo': 'SHIPCRAFT', 'filtra-invalido-numero': 3, 'filtra-invalido-bool': True, 'filtra-invalido-lista': []}.get(case, filtra)) + '\n'
    probe = f'{py} runner.py --runner probe'
    Path('.shipcraft.toml').write_text('shipcraft_min = "0.0"\nlang = "python"\nrunner = ' + json.dumps(runner_name) + '\n[[suite]]\nname = "api"\nroot = "."\n' + field + 'command = ' + json.dumps(cmd) + '\nglobs = ["tests/**"]\ncheck = ' + json.dumps(probe + ' verifica') + '\n')
    if case in ('duas-suites', 'ambiente-vazio'):
        sub = Path('pacote com espaço')
        sub.mkdir()
        for name in ('runner.py', 'cases.json', 'value'):
            shutil.copyfile(name, sub / name)
        shutil.copytree('tests', sub / 'tests')
        other = [dict(c, name='beta:' + c['name'], red=c.get('red') and case != 'ambiente-vazio') for c in data]
        (sub / 'cases.json').write_text(json.dumps(other))
        with open('.shipcraft.toml', 'a') as f:
            f.write('\n[[suite]]\nname = "beta"\nroot = "pacote com espaço"\ncommand = ' + json.dumps(cmd) + '\nglobs = ["tests/**"]\n')
    git('add', '.')
    git('commit', '-qm', 'test: projeto base')
    base = git('rev-parse', 'HEAD')
    if case == 'ambiente-build':
        with open('.shipcraft.toml', 'a') as f:
            f.write('\n[build]\ncommand = ' + json.dumps(probe + ' build') + '\n')
        git('add', '.shipcraft.toml')
        git('commit', '-qm', 'test: build')
    if case.startswith('filtra-invalido'):
        p = run(binary, 'red', ok=False)
        assert p.returncode != 0, 'invalid filter accepted'
        assert not rows(), 'invalid config ran a command'
        assert 'filter' in p.stdout + p.stderr
        return
    inherited = dict(os.environ, SHIPCRAFT_CASES='/inexistente/herdado-casos', SHIPCRAFT_FILES='/inexistente/herdado-arquivos')
    run(binary, 'red', env=inherited if case in ('ambiente-red', 'ambiente-build') else None)
    if case in ('ambiente-red', 'ambiente-build'):
        assert len(rows()) == (4 if case == 'ambiente-build' else 3), rows()
        assert all(all(v is None for v in r['env'].values()) for r in rows()[:-1]), 'inherited environment reached first RED/build/check'
        assert all(v and v['hex'] is not None for v in rows()[-1]['env'].values()), 'second RED missing fresh lists'
        if case == 'ambiente-build':
            assert any(r['argv'] == ['probe', 'build'] for r in rows()), 'build did not run'
        return
    locks = list(Path('.shipcraft/locks').glob('*.json'))
    assert len(locks) == 1
    if case == 'bash':
        assert len(rows()) == 3, 'RED must run verifica, full suite, then filtered suite'
        assert all('--selected' not in r['argv'] for r in rows()[:2]), 'first run must run whole suite'
        assert '--selected' in rows()[-1]['argv'], 'second run must receive cases'
    d = json.loads(locks[0].read_text())
    assert len(d['failing_at_red']) == len({((c.get('class', '') + '::' if c.get('class') else '') + c['name']) for c in data if c.get('red')}) * (2 if case == 'duas-suites' else 1), d
    git('add', '.')
    git('commit', '-qm', 'test: RED registrado')
    if case == 'varias-travas':
        first = git('rev-parse', 'HEAD')
        git('switch', '-qc', 'segundo-red', base)
        second = [dict(c, name='segundo:' + c['name']) for c in data if c.get('red')]
        Path('cases.json').write_text(json.dumps(second + [data[-1]]))
        git('add', 'cases.json')
        git('commit', '-qm', 'test: segundo contrato')
        run(binary, 'red')
        git('add', '.')
        git('commit', '-qm', 'test: segundo RED registrado')
        git('cherry-pick', first)
        locks = list(Path('.shipcraft/locks').glob('*.json'))
        assert len(locks) == 2, 'fixture did not create two real locks'
        first_data = data
        data = data[:-1] + second + [data[-1]]
        Path('cases.json').write_text(json.dumps(data))
        git('add', 'cases.json')
    clear()
    phase = 'omit-one' if case == 'sumiu-parcial' else 'skip-one' if case == 'pulado-parcial' else 'omit' if case.startswith('sumiu') else 'skip' if case == 'pulado' else 'old-fails' if case == 'old-omitido' else 'green'
    Path('value').write_text(phase)
    git('add', 'value')
    if case in ('duas-suites', 'ambiente-vazio'):
        Path('pacote com espaço/value').write_text(phase)
        git('add', 'pacote com espaço/value')
    if case == 'copia-indice':
        Path('value').write_text('red')
    if case == 'arvore':
        git('commit', '-qm', 'feat: GREEN limpo')
    if case == 'temporario-falha':
        temp = Path(git('rev-parse', '--git-path', 'shipcraft/tmp'))
        temp.parent.mkdir(parents=True, exist_ok=True)
        temp.write_text('impede criar diretório')
    p = run(binary, 'check', ok=False, env=inherited if case.startswith('ambiente') else None)
    observed = [r for r in rows() if r['argv'][0] != 'probe']
    if case == 'copia-indice':
        assert observed and all(r['phase'] == 'green' and Path(r['cwd']) != Path.cwd() for r in observed), 'did not judge a copy of the index'
    if case == 'arvore':
        assert observed and all(Path(r['cwd']) == Path.cwd() for r in observed), 'the clean tree was not used'
    assert observed, 'suite did not run'
    for r in observed:
        for v in r['env'].values():
            if v and v['hex'] is not None:
                assert not Path(v['path']).exists(), 'temporary file survived the run'
    if case.startswith('sumiu') or case in ('pulado', 'pulado-parcial'):
        assert p.returncode != 0, 'missing/skipped RED closed'
        assert all(json.loads(f.read_text()).get('state') == 'open' for f in locks), 'refusal closed the lock'
        lines = [x for x in (p.stdout + p.stderr).splitlines() if x.strip()][-3:]
        assert len(lines) == 3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'), lines
        assert not Path(git('rev-parse', '--git-path', 'shipcraft/close')).exists()
        if case.startswith('sumiu'):
            out = p.stdout + p.stderr
            assert 'test_0' in out, out
            metric = Path(git('rev-parse', '--git-common-dir')) / 'shipcraft/runs.jsonl'
            events = [json.loads(x) for x in metric.read_text().splitlines()]
            assert events[-1]['code'] == 'case-missing', events[-1]
            assert ('the command filters by case' in out) == (case in ('sumiu-comando', 'sumiu-parcial')), out
        return
    assert p.returncode == 0, 'GREEN hook refused'
    assert all(json.loads(f.read_text()).get('state') == 'closed' for f in locks), 'lock did not close'
    if case == 'temporario-falha':
        assert all(all(v is None for v in r['env'].values()) for r in observed), 'partial fallback'
        return
    if case.startswith('filtro-'):
        args = observed[-1]['argv']
        changed = any(x.startswith(('--ignore', '--exclude', '--testPathIgnorePatterns')) or x == '-run' for x in args)
        if filtra == 'command':
            assert not changed, args
            if runner_name == 'go':
                assert './...' in args, args
        else:
            assert changed or (runner_name == 'go' and './...' not in args), 'shipcraft filter disappeared: ' + repr(args)
        return
    if case in ('ambiente-ci', 'ambiente-verifica'):
        # No hook: CI runs on HEAD; an inherited value must not reach even verifica.
        git('commit', '-qm', 'feat: GREEN')
        clear()
        run(binary, 'ci', '--base', base, env=inherited, ok=False)
        assert rows(), 'CI ran no commands'
        assert any(r['argv'] == ['probe', 'verifica'] for r in rows()), 'verifica did not run'
        assert all(all(v is None for v in r['env'].values()) for r in rows()), 'inherited environment reached CI'
        return
    want = sorted(set(((c.get('class', '') + '::' if c.get('class') else '') + c['name']).encode() for c in data if c.get('red')))
    covered = set()
    for r in observed:
        local = other if case in ('duas-suites', 'ambiente-vazio') and Path(r['cwd']).name == 'pacote com espaço' else data
        want = sorted(set(((c.get('class', '') + '::' if c.get('class') else '') + c['name']).encode() for c in local if c.get('red')))
        val = r['env']['SHIPCRAFT_CASES']
        if not want:
            assert all(v is None for v in r['env'].values()), 'empty list received an inherited variable'
            continue
        assert val is not None, 'SHIPCRAFT_CASES missing in the hook'
        assert val['hex'] is not None, 'inherited variable reached the suite: ' + repr(val)
        got = bytes.fromhex(val['hex'])
        if case == 'varias-travas':
            groups = [sorted(set((c['class'] + '::' + c['name']).encode() for c in group if c.get('red'))) for group in (first_data, second, data)]
            assert got in [b''.join(x + b'\0' for x in group) for group in groups], val
            covered.update(got.split(b'\0')[:-1])
        else:
            assert got == b''.join(x + b'\0' for x in want), val
        for v in r['env'].values():
            if v:
                assert Path(v['path']).is_absolute()
                assert Path(v['path']).parent == temp_root, (v, str(temp_root))
                assert not Path(v['path']).exists(), 'temporary file survived'
        files = r['env']['SHIPCRAFT_FILES']
        # Without classname, the id 'sem classe' stays in SHIPCRAFT_CASES, but the map is partial.
        if case in ('sem-mapa', 'parcial', 'bytes-borda', 'bash'):
            assert files is None, 'incomplete map exported files'
        else:
            assert files is not None, 'SHIPCRAFT_FILES missing with a complete map'
            expected = sorted(set(str(Path(r['cwd'], c['file'])).encode() for c in local if c.get('red')))
            assert bytes.fromhex(files['hex']) == b''.join(x + b'\0' for x in expected), files
    if case == 'varias-travas':
        assert covered == set(want), 'cases of one lock were not run'
    if case == 'duas-suites':
        assert {Path(r['cwd']).name for r in observed} >= {'pacote com espaço'}, observed
        assert len({r['cwd'] for r in observed}) == 2, observed
    if case == 'bash':
        assert len(observed) == 1, 'runner called in batches'
        assert observed[0]['argv'][1:] == ['--selected'] + [x.decode() for x in want]



if __name__ == '__main__':
    if sys.argv[1] == '--runner':
        runner()
    else:
        main(*sys.argv[1:])
