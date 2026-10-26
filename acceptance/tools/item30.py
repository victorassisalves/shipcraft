"""Black-box helper for item 30: config and the paths in the observed lock."""
import json
import pathlib
import re
import sys
try:
    import tomllib
except ImportError:
    import tomli as tomllib

mode, *args = sys.argv[1:]
if mode == 'config':
    lang, root, glob = args
    p = pathlib.Path('.shipcraft.toml')
    old = tomllib.loads(p.read_text())
    command = {
        'python': 'python3 -m pytest -p no:cacheprovider --junitxml={junit}',
        'node': 'npx --no -- vitest run --maxWorkers=1 --reporter=junit --outputFile={junit}',
        'go': 'gotestsum --junitfile {junit} -- -count=1 ./...',
    }[lang]
    p.write_text(f'shipcraft_min = {json.dumps(old["shipcraft_min"])}\n'
                 f'lang = {json.dumps(lang)}\nrunner = {json.dumps({"python":"pytest","node":"vitest","go":"gotestsum"}[lang])}\n'
                 '[[suite]]\nname = "contrato-30"\n'
                 f'root = {json.dumps(root)}\ncommand = {json.dumps(command)}\n'
                 f'globs = [{json.dumps(glob)}]\n')
elif mode == 'side-suite':
    lang, root, failing = args
    commands = {
        'python': 'python3 -m pytest tests/test_smoke.py -p no:cacheprovider --junitxml={junit}',
        'node': 'npx --no -- vitest run src/smoke.test.ts --maxWorkers=1 --reporter=junit --outputFile={junit}',
        'go': 'gotestsum --junitfile {junit} -- -count=1 -run TestPackageBuilds ./...',
    }
    p = pathlib.Path('.shipcraft.toml')
    first = tomllib.loads(p.read_text())['suite'][0]
    name = 'contrato-30-extra' if failing == 'yes' else 'contrato-3'
    command = first['command'] if failing == 'yes' else commands[lang]
    with p.open('a') as f:
        f.write('\n[[suite]]\n' + f'name = {json.dumps(name)}\nroot = {json.dumps(root)}\n'
                + f'command = {json.dumps(command)}\nglobs = ["ausente/**"]\n')
elif mode == 'repo-message':
    text = pathlib.Path(args[0]).read_text()
    assert re.search(r"(?:[`'\"]\.[`'\"]|root\s*[:=]?\s+\.(?=\s|[,;)]|$))", text), text
elif mode == 'legacy-ci':
    rows = [json.loads(line) for line in pathlib.Path(args[0]).read_text().splitlines()]
    ci = [row for row in rows if row.get('layer') == 'ci']
    assert ci and ci[-1].get('code') != 'suite-without-tests', ci
elif mode == 'v0':
    p = pathlib.Path('.shipcraft.toml')
    old = tomllib.loads(p.read_text())
    suite = old.pop('suite')[0]
    old['test_command'] = suite['command']
    old['test_globs'] = suite['globs']
    p.write_text(''.join(f'{k} = {json.dumps(v)}\n' for k, v in old.items()))
elif mode == 'add-glob':
    p = pathlib.Path('.shipcraft.toml')
    old = tomllib.loads(p.read_text())['suite'][0]['globs']
    p.write_text(re.sub(r'^globs = .*$', lambda m: 'globs = ' + json.dumps(old + args), p.read_text(), flags=re.M))
elif mode == 'prefix-command':
    p = pathlib.Path('.shipcraft.toml')
    old = tomllib.loads(p.read_text())['suite'][0]['command']
    p.write_text(re.sub(r'^command = .*$', lambda m: 'command = ' + json.dumps(args[0] + old), p.read_text(), flags=re.M))
elif mode == 'command':
    p = pathlib.Path('.shipcraft.toml')
    p.write_text(re.sub(r'^command = .*$', lambda m: 'command = ' + json.dumps(args[0]), p.read_text(), flags=re.M))
elif mode == 'locked':
    data = json.loads(pathlib.Path(args[0]).read_text())
    path = args[1].removeprefix('./')
    def contains(value):
        if isinstance(value, dict):
            return path in value or any(contains(v) for v in value.values())
        if isinstance(value, list):
            return any(contains(v) for v in value)
        return value == path
    assert contains(data), f'path missing: {path}'
elif mode == 'brief':
    brief = pathlib.Path(args[0]).read_text()
    root = args[1]
    # 30.3 requires cd and the command inside the same subshell, joined by &&.
    quoted = ["'" + root.replace("'", escape) + "'" for escape in ["'\"'\"'", "'\\''"]]
    assert any(re.search(r"\(cd\s+" + re.escape(q) + r"\s+&&\s+[^\n]+\)", brief) for q in quoted), brief
    assert './packages//api/' not in brief, brief
