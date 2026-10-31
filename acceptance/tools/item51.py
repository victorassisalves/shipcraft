#!/usr/bin/env python3
"""Only public commands and real Vitest output; never import the implementation."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time

# A network step (npm install from the registry) gets its own, longer limit: GitHub's macOS
# runners took more than 120 s on it once (POC-023). Each run prints its duration.
NET_TIMEOUT = int(os.environ.get('SHIPCRAFT_ACCEPTANCE_NET_TIMEOUT', '600'))


def run(*args, ok=True, timeout=120):
    start = time.monotonic()
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        print('$', shlex.join(args), f'[{time.monotonic() - start:.1f} s of {timeout}: timed out]', flush=True)
        raise
    print('$', shlex.join(args), f'[{time.monotonic() - start:.1f} s of {timeout}]', '\n', p.stdout, p.stderr, flush=True)
    if ok:
        assert p.returncode == 0, (args, p.returncode)
    return p


def git(*args):
    return run('git', *args).stdout.strip()


def put(name, text):
    p = Path(name)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def main(case, binary):
    external = Path.cwd().resolve() / 'item51-observations'
    external.mkdir()
    os.environ['ITEM51_OBSERVATIONS'] = str(external)
    os.environ['ITEM51_MODE'] = case
    root = Path('item51-project').resolve()
    root.mkdir()
    os.chdir(root)
    git('init', '-q', '-b', 'main')
    git('config', 'user.name', 'Acceptance RED')
    git('config', 'user.email', 'red@example.invalid')
    put('package.json', '{"private":true,"type":"module","devDependencies":{"vitest":"2.1.9"}}\n')
    run('npm', 'install', '--no-audit', '--no-fund', '--loglevel=error', timeout=NET_TIMEOUT)
    os.environ['ITEM51_REAL'] = str(root / 'node_modules/vitest/vitest.mjs')
    # The public command is still `vitest run ...`; the wrapper records actual
    # shell-split argv then delegates unchanged to the installed runner.
    wrapper = external / 'vitest'
    wrapper.write_text('#!/usr/bin/env python3\n' + WRAPPER)
    wrapper.chmod(0o755)
    os.environ['PATH'] = str(external) + ':' + os.environ['PATH']
    put('.gitignore', 'node_modules/\n')
    put('value.js', 'export const value = 0;\n')
    put('legacy.txt', 'ok\n')
    put('guard.txt', 'ok\n')
    put('vitest.workspace.ts', 'import {defineWorkspace} from "vitest/config";\nexport default defineWorkspace(["packages/*/vitest.config.ts"]);\n')
    for project in ('api', 'web'):
        put(f'packages/{project}/vitest.config.ts', 'import {defineProject} from "vitest/config";\nexport default defineProject({test:{name:' + json.dumps(project) + ',root:import.meta.dirname}});\n')
    reds = ['packages/api/src/red file.spec.ts']
    if case == 'arguments':
        reds += ['packages/web/src/z.spec.ts']
    test = 'import {it,expect} from "vitest";\nimport {value} from "../../../value.js";\nit("red one",()=>expect(value).toBe(1));\nit("red two",()=>expect(value).toBe(1));\n'
    test += 'import {readFileSync} from "node:fs";\nit("passing guard",()=>expect(readFileSync(new URL("../../../guard.txt",import.meta.url),"utf8")).toBe("ok\\n"));\n'
    for red in reversed(reds):
        put(red, test)
    old = 'packages/web/tests/old.test.ts'
    put(old, '''import {it,expect} from "vitest";
import {appendFileSync,readFileSync} from "node:fs";
it("old",()=>{appendFileSync(process.env.ITEM51_OBSERVATIONS+"/old", "ran\\n");expect(readFileSync("../../legacy.txt","utf8")).toBe("ok\\n");});
'''.replace('readFileSync("../../legacy.txt"', 'readFileSync(new URL("../../../legacy.txt",import.meta.url)'))
    containing = reds[0] + '.test.ts'
    if case == 'boundary':
        put(containing, '''import {it,expect} from "vitest";
import {value} from "../../../value.js";
import {appendFileSync} from "node:fs";
it("containing path",()=>{appendFileSync(process.env.ITEM51_OBSERVATIONS+"/containing","ran\\n");expect(value).toBe(0);});
''')
    command = 'vitest run --maxWorkers=1 --minWorkers=1 --reporter=junit --outputFile={junit}'
    put('.shipcraft.toml', 'shipcraft_min = "0.0"\nlang = "node"\nrunner = "vitest"\n[[suite]]\nname = "workspace"\nroot = "."\nfilter = ' + json.dumps('command' if case == 'command' else 'shipcraft') + '\ncommand = ' + json.dumps(command) + '\nglobs = ["packages/**/*.spec.ts", "packages/**/*.test.ts"]\n')
    git('add', '.')
    git('commit', '-qm', 'chore: workspace fixture')
    run(binary, 'init')
    git('add', '.')
    git('commit', '-qm', 'chore: init')
    run(binary, 'red')
    locks = list(Path('.shipcraft/locks').glob('*.json'))
    assert len(locks) == 1
    assert len(json.loads(locks[0].read_text())['failing_at_red']) == 2 * len(reds)
    git('add', '.')
    if case == 'staged':
        # The index matches the RED lock; an unstaged test would fail collection.
        put(reds[0], 'throw new Error("UNSTAGED TEST MUST NOT BE JUDGED");\n')
    (external / 'argv').write_text('')
    for marker in ('old', 'containing'):
        (external / marker).unlink(missing_ok=True)
    git('commit', '-qm', 'test: RED')
    red_rows = rows(external)
    if case == 'staged':
        put(reds[0], test)
    # A case that passed at RED in a RED file still blocks a later GREEN.
    put('value.js', 'export const value = 1;\n')
    put('guard.txt', 'ok\n' if case == 'fallback' else 'broken\n')
    git('add', 'value.js', 'guard.txt')
    if case != 'fallback':
        refused = run('git', 'commit', '-qm', 'feat: GREEN with broken guard', ok=False)
        assert refused.returncode != 0, 'executed case in RED file stopped blocking'
        assert json.loads(locks[0].read_text())['state'] == 'open'
        assert len([x for x in (refused.stdout + refused.stderr).splitlines() if x.strip()]) >= 3
    put('guard.txt', 'ok\n')
    git('add', 'guard.txt')
    (external / 'argv').write_text('')
    for marker in ('old', 'containing'):
        (external / marker).unlink(missing_ok=True)
    put('value.js', 'export const value = 1;\n')
    if case == 'boundary':
        put('legacy.txt', 'broken\n')
    git('add', 'value.js', 'legacy.txt')
    git('commit', '-qm', 'feat: GREEN')
    assert json.loads(locks[0].read_text())['state'] == 'closed'
    green_rows = rows(external)
    assert green_rows, 'hook suite did not run'
    if case == 'workspace':
        assert not (external / 'old').exists(), 'old file in another project executed in GREEN hook'
    for row in red_rows + green_rows:
        args = row['args']
        positional = [a for a in args[1:] if not a.startswith('-')]
        expected = sorted(str(Path(row['cwd']) / p) for p in reds)
        if case in ('command', 'fallback'):
            assert positional == [], f'{case} added positional files: {args}'
        else:
            assert positional == expected, f'expected distinct byte-ordered judged absolute paths {expected}; got {args}'
            assert row['files'] == expected, 'argv differs from SHIPCRAFT_FILES'
            assert all(row['contents'][p] == test for p in expected), 'judged checkout used unstaged tests'
            assert '--exclude=' + str(Path(row['cwd']) / old) in args, 'existing exclusion disappeared'
    if case == 'boundary':
        assert (external / 'containing').exists(), 'substring-matching file must run'
        assert not (external / 'old').exists(), 'unrelated old file ran'


def rows(external):
    return [json.loads(line) for line in (external / 'argv').read_text().splitlines()]


WRAPPER = r'''
import json,os,subprocess,sys
from pathlib import Path
import xml.etree.ElementTree as ET
out=Path(os.environ['ITEM51_OBSERVATIONS'])
files=os.environ.get('SHIPCRAFT_FILES')
files=Path(files).read_bytes().decode().strip('\0').split('\0') if files else None
row=dict(cwd=os.getcwd(),args=sys.argv[1:],files=files,contents={p:Path(p).read_text() for p in files or []})
with (out/'argv').open('a') as f: f.write(json.dumps(row)+'\n')
p=subprocess.run(['node',os.environ['ITEM51_REAL'],*sys.argv[1:]])
if os.environ['ITEM51_MODE']=='fallback':
 target=next(a.split('=',1)[1] for a in sys.argv if a.startswith('--outputFile='))
 tree=ET.parse(target)
 for node in tree.iter('testcase'):
  if node.attrib.get('name')=='red one':
   node.set('classname','external-unmapped');node.attrib.pop('file',None)
 tree.write(target,encoding='utf-8',xml_declaration=True)
sys.exit(p.returncode)
'''

if __name__ == '__main__':
    main(*sys.argv[1:])
