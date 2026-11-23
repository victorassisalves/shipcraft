# Item 155: Jest module literals and relative presets, through public commands.
item155_langs() { echo node; }
item155_cases() {
  local c
  for c in repro-t env preset-js preset-json preset-all preset-import transform-tuple reporters string-keys arrays mapper code-names resolve index nested-options packages rootdir manifest json-config notice redo vitest-control missing-transform missing-env absolute linked missing-preset preset-not-object preset-rootdir manifest-order text-order ci env-import preset-change product-control fake-control real-control log-failure redo-refused io-failure; do
    echo "v1-155.$c"
  done
}
item155_case() {
  EXPECT="item 155: ${CASE#v1-155.}"; v1_start
  must_accept 'Jest module and preset contract' cmd "$PY" - "${CASE#v1-155.}" "$(command -v shipcraft)" <<'PY155'
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys

case, binary = sys.argv[1:]
binary = str(Path(binary).resolve())
home = Path.cwd().resolve()
globs = ['**/*.test.*', '**/*.spec.*', '**/__tests__/**', '**/vitest.config.*', '**/jest.config.*']
command = "JEST_JUNIT_OUTPUT_FILE={junit} JEST_JUNIT_CLASSNAME='{filepath}' node_modules/.bin/jest --runInBand --reporters=default --reporters=jest-junit"
prefix = 'shipcraft: red also locked what '
stub = 'exports.sum = () => { throw new Error("stub155"); };\n'
repair = 'exports.sum = () => { return 3; };\n'
transform_config = r'module.exports = { cache: false, transform: { "\\.js$": "<rootDir>/jest/transform.js" } };'
transform = 'exports.process = (code) => ({code});\n'
substitute = '''exports.process = (code, filename) => ({
  code: filename.endsWith('/sum.js') ? 'exports.sum = () => 3;' : code
});
'''
base_files = {'.shipcraft.toml', 'src/sum.test.js', 'src/other.test.js'}
jest_files = base_files | {'jest.config.js'}

def run(*args):
    result = subprocess.run(args, capture_output=True, timeout=120)
    print(f'$ {shlex.join(args)} [rc={result.returncode}]', flush=True)
    for output in (result.stdout, result.stderr):
        sys.stdout.buffer.write(output)
        sys.stdout.buffer.flush()
    return result

def ok(*args):
    result = run(*args)
    assert result.returncode == 0, (args, result)
    return result

def git(*args):
    return ok('git', *args).stdout.decode().strip()

def write(path, content):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content if isinstance(content, bytes) else content.encode())

def commit(message):
    git('add', '-A')
    git('commit', '-qm', message)

def lock():
    paths = list(Path('.shipcraft/locks').glob('*.json'))
    assert len(paths) == 1, paths
    return paths[0], json.loads(paths[0].read_bytes())

def rows(layer):
    path = Path('.git/shipcraft/runs.jsonl')
    return [row for line in path.read_bytes().splitlines()
            if (row := json.loads(line))['layer'] == layer]

def fresh(name, real=False, suite_command=command):
    root = home / name
    root.mkdir()
    os.chdir(root)
    git('init', '-q', '-b', 'main')
    git('config', 'user.name', 'RED155')
    git('config', 'user.email', 'red155@example.invalid')
    write('.gitignore', 'node_modules/\n.trace155\nignored/\n')
    write('package.json', json.dumps({'private': True, 'devDependencies': {
        'jest': os.environ.get('SHIPCRAFT_JEST_VERSION', '29.7.0'),
        'jest-junit': os.environ.get('SHIPCRAFT_JEST_JUNIT_VERSION', '16.0.0'),
    }}))
    write('src/sum.js', stub)
    write('src/sum.test.js', 'const {sum}=require("./sum");test("adds",()=>expect(sum()).toBe(3));\n')
    write('src/other.test.js', 'test("control155",()=>expect(2+2).toBe(4));\n')
    write('src/setup.js', '// no mock\n')
    if real:
        ok('npm', 'install', '--ignore-scripts', '--no-audit', '--no-fund', '--loglevel=error')
    else:
        write('node_modules/.bin/jest', fake)
        Path('node_modules/.bin/jest').chmod(0o755)
        Path('node_modules/.bin/vitest').symlink_to('jest')
    write('.shipcraft.toml', 'shipcraft_min="0.0"\nlang="node"\nrunner="jest"\n'
          f'test_command={json.dumps(suite_command)}\ntest_globs={json.dumps(globs)}\n'
          '[execution]\nci="local"\nreview="off"\n')

def install():
    ok(binary, 'init', '--lang', 'node')
    commit('baseline155')

def red(*args):
    return run(binary, 'red', *args)

def seed():
    install()
    result = red()
    assert result.returncode == 0, result
    commit('RED155')
    return result

def green(changes, ci=False):
    for path, content in changes.items():
        write(path, content)
    git('add', '-A')
    if ci:
        base = git('rev-parse', 'HEAD')
        tree = git('write-tree')
        snapshot = git('commit-tree', tree, '-p', base, '-m', 'CI snapshot155')
        git('update-ref', 'HEAD', snapshot)
        return run(binary, 'ci', '--base', base)
    return run('git', 'commit', '-qm', 'GREEN155')

def refusal(result, code, layer):
    lines = [line for line in (result.stdout + result.stderr).splitlines(keepends=True)
             if line.startswith((b'shipcraft refused:', b'Why:', b'Next:'))]
    assert result.returncode == 1 and len(lines) == 3, (result, lines)
    assert rows(layer)[-1]['code'] == code, rows(layer)[-1]
    return b''.join(lines)

def refusal_bytes(config, why):
    return (f'shipcraft refused: could not read the jest setup files of {config}: {why}\n'
            'Why: red locks the setup files it can name; one it cannot name could change what every locked case sees\n'
            f'Next: in {config}, write setupFiles, setupFilesAfterEnv, globalSetup and globalTeardown as string literals or arrays of them, and rootDir, if any, as one relative string literal in the config file itself, then run red again\n').encode()

fake = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
passed = 'return 3' in Path('src/sum.js').read_text()
for path in ('test/env.js', 'jest/transform.js', 'src/setup.js'):
    candidate = Path(path)
    if candidate.is_file() and 'PASS155' in candidate.read_text():
        passed = True
suite = ET.Element('testsuite', tests='2', failures=str(int(not passed)))
for file, name in [('src/sum.test.js', 'adds'), ('src/other.test.js', 'control155')]:
    test = ET.SubElement(suite, 'testcase', classname=file, name=name, file=file)
    if name == 'adds' and not passed:
        ET.SubElement(test, 'failure', message='stub155')
ET.ElementTree(suite).write(os.environ['JEST_JUNIT_OUTPUT_FILE'])
with Path('.trace155').open('a') as trace:
    files = os.environ.get('SHIPCRAFT_FILES')
    trace.write(json.dumps({'runner': 'fake155', 'passed': passed, 'files': Path(files).read_text() if files else None}) + '\n')
print('fake155:' + str(passed))
sys.exit(0 if passed else 1)
'''

if case == 'repro-t':
    fresh('repro-t', real=True)
    write('jest.config.js', transform_config)
    write('jest/transform.js', transform)
    seed()
    red_files = set(lock()[1]['files'])
    assert lock()[1]['failing_at_red'] == ['src/sum.test.js:: adds']
    head = git('rev-parse', 'HEAD')
    result = green({'jest/transform.js': substitute})
    state = lock()[1]['state']
    print(f'REPRODUCTION T: GREEN rc={result.returncode}; lock={state}; RED files={sorted(red_files)}',
          flush=True)
    assert Path('src/sum.js').read_text() == stub
    assert result.returncode == 1, 'transform-only GREEN accepted; expected test-changed'
    assert b'locked test jest/transform.js changed after RED' in refusal(result, 'test-changed', 'hook')
    assert git('rev-parse', 'HEAD') == head and state == 'open'
    assert red_files == jest_files | {'jest/transform.js'}, red_files
    result = green({'jest/transform.js': transform, 'src/sum.js': repair})
    assert result.returncode == 0 and lock()[1]['state'] == 'closed', result
    assert git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD^') == 'src/sum.js'
elif case == 'env':
    fresh(case); write('jest.config.js', 'module.exports={testEnvironment:"<rootDir>/test/env.js"};')
    write('test/env.js', 'module.exports=require("jest-environment-node").TestEnvironment;'); seed()
    result = green({'test/env.js': 'module.exports=class extends require("jest-environment-node").TestEnvironment {handleTestEvent(event){if(event.name==="test_done")event.test.errors=[];}}; // PASS155'})
    assert b'locked test test/env.js changed after RED' in refusal(result, 'test-changed', 'hook')
    assert set(lock()[1]['files']) == jest_files | {'test/env.js'} and lock()[1]['state'] == 'open'
elif case == 'preset-js':
    fresh(case); write('jest.config.js', 'module.exports={preset:"./jest-preset.js"};')
    write('jest-preset.js', 'module.exports={setupFiles:["<rootDir>/src/setup.js"]};'); seed()
    result = green({'jest-preset.js': 'module.exports={}; // PASS155', 'src/sum.js': repair})
    assert b'locked test jest-preset.js changed after RED' in refusal(result, 'test-changed', 'hook')
    assert set(lock()[1]['files']) == jest_files | {'jest-preset.js', 'src/setup.js'} and lock()[1]['state'] == 'open'
elif case == 'preset-json':
    fresh(case); write('jest.config.js', 'module.exports={preset:"./presets/base"};')
    write('presets/base.json', '{"testEnvironment":"<rootDir>/test/env.js"}'); write('test/env.js', '// env')
    install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files | {'presets/base.json', 'test/env.js'}
elif case == 'preset-all':
    fresh(case); write('jest.config.js', 'module.exports={preset:"<rootDir>/presets/web"};')
    write('presets/web.js', 'module.exports={preset:"./missing",testEnvironment:"node"};')
    write('presets/web/jest-preset.cjs', 'module.exports={testEnvironment:"<rootDir>/test/env.js"};'); write('test/env.js', '// env')
    install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files | {'presets/web.js', 'presets/web/jest-preset.cjs', 'test/env.js'}
elif case == 'preset-import':
    fresh(case); write('jest.config.js', 'module.exports={preset:"./jest-preset.js"};')
    write('jest-preset.js', 'module.exports=require("./preset-base.js");')
    write('preset-base.js', 'module.exports={transform:{x:"./jest/t.js"},preset:"./missing"};'); write('jest/t.js', '// transform')
    install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files | {'jest-preset.js', 'preset-base.js', 'jest/t.js'}
elif case == 'transform-tuple':
    fresh(case); write('jest.config.js', r'module.exports={transform:{"\\.ts$":["<rootDir>/jest/ts.js",{tsconfig:"./tsconfig.jest.json",filter:"./data/missing.json"}],"\\.css$":"./jest/css.js"}};')
    write('jest/ts.js', 'require(name); // named files are not scanned'); write('jest/css.js', '// CSS'); write('tsconfig.jest.json', '{}')
    install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files | {'jest/ts.js', 'jest/css.js'}
elif case == 'reporters':
    fresh(case); write('jest.config.js', 'module.exports={reporters:["default",["<rootDir>/jest/rep.js",{outputDirectory:"out"}]]};')
    write('jest/rep.js', '// reporter'); install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files | {'jest/rep.js'}
elif case == 'string-keys':
    fresh(case)
    keys = ['resolver','snapshotResolver','testSequencer','testRunner','runner','runtime','testResultsProcessor','dependencyExtractor','filter','prettierPath']
    body = ','.join(json.dumps(k)+':"./jest/'+k+'.js"' for k in keys)
    write('jest.config.js', '\ufeffmodule.exports={'+body+',haste:{hasteImplModulePath:`./jest/hasteImplModulePath.js`}};')
    paths = {'jest/'+k+'.js' for k in keys+['hasteImplModulePath']}
    for path in paths: write(path, '// '+path)
    install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files | paths
elif case == 'arrays':
    fresh(case); write('jest.config.js', 'module.exports={snapshotSerializers\r: ["./jest/ser.js",],watchPlugins\u2028:/*tuple*/[[`./jest/watch.js`,{key:"k"}]]};')
    write('jest/ser.js', '// serializer'); write('jest/watch.js', '// watcher'); install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files | {'jest/ser.js', 'jest/watch.js'}
elif case == 'mapper':
    fresh(case); write('jest.config.js', 'module.exports={moduleNameMapper:{"^a$":"<rootDir>/test/fake.js","^b$":["<rootDir>/opt/none.js","<rootDir>/test/alt.js","<rootDir>/src/$1"],"^c$":"./test/rel.js","^d$":"identity-obj-proxy","^e$":"<rootDir>/test/price$.js"}};')
    for path in ('test/fake.js','test/alt.js','test/rel.js','test/price$.js'): write(path, '// mapping')
    install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files | {'test/fake.js','test/alt.js','test/price$.js'}
elif case == 'code-names':
    fresh(case); write('jest.config.js', r'module.exports={transform:{...preset.transform,"\\.ts$":path.join(__dirname,"jest/t.js")},testEnvironment:"./env.js"+"",reporters:["./r.js"].concat([]),preset:name,runtime:null,runner:42,snapshotSerializers:[false,{resolver:"./missing"}],snapshotResolver:(variable),filter:({}) as const}; transform(src);')
    for path in ('jest/t.js','env.js','r.js'): write(path, '// dynamic name')
    install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files and prefix.encode() not in result.stdout
    assert b'fake155:False' in Path('.git/shipcraft/output/red.log').read_bytes()
elif case == 'resolve':
    fresh(case); write('config/jest.config.js', 'module.exports={rootDir:"../src",transform:{x:require.resolve("./jest/t.js")},preset:require.resolve("./p.js")};')
    write('config/jest/t.js', '// correct module folder'); write('src/jest/t.js', '// wrong root')
    write('config/p.js', 'module.exports={testEnvironment:"./env.js"};'); write('src/env.js', '// preset inherits root')
    install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == base_files | {'config/jest.config.js','config/jest/t.js','config/p.js','src/env.js'}
    fresh('resolve-missing'); write('jest.config.js', 'module.exports={testEnvironment:require.resolve("./missing.js")};'); install(); result = red()
    lines = refusal(result, 'setup-unreadable', 'red')
    assert lines == refusal_bytes('jest.config.js', './missing.js names no file in the repository')
    assert not list(Path('.shipcraft/locks').glob('*.json'))
elif case == 'index':
    fresh(case); write('jest.config.js', 'module.exports={testEnvironment:"./test/env"};')
    write('test/env/index.js', '// index'); write('test/env/index.ts', '// another existing candidate')
    install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files | {'test/env/index.js','test/env/index.ts'}
elif case == 'nested-options':
    fresh(case); write('jest.config.js', 'module.exports={reporters:[["./jest/rep.js",{resolver:"./templates/none.txt"}]],testEnvironmentOptions:{filter:"./data/none.json"},globals:{runtime:"./missing"},moduleNameMapper:{"^s$":require.resolve("./test/mock.js")}};')
    write('jest/rep.js', '// reporter'); write('test/mock.js', '// mock'); install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files | {'jest/rep.js','test/mock.js'}
elif case == 'packages':
    fresh(case); write('jest.config.js', r'module.exports={transform:{"\\.js$":"babel-jest"},testEnvironment:"jsdom",preset:"ts-jest",resolver:require.resolve("some-package")};')
    install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files and prefix.encode() not in result.stdout
    assert b'fake155:False' in Path('.git/shipcraft/output/red.log').read_bytes()
elif case == 'rootdir':
    fresh(case); write('jest.config.js', 'module.exports={rootDir:"src",testEnvironment:"<rootDir>/env.js"};')
    write('examples/demo/jest.config.js', 'module.exports={transform:{x:"./t.js"}};')
    for path in ('src/env.js','examples/demo/t.js','env.js','t.js'): write(path, '// '+path)
    install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files | {'src/env.js','examples/demo/jest.config.js','examples/demo/t.js'}
elif case == 'manifest':
    fresh(case); value = json.loads(Path('package.json').read_bytes())
    value['jest'] = {'preset':'./jest-preset.json','transform':{'x':'<rootDir>/jest/t.js'}}
    write('package.json', json.dumps(value)); write('jest-preset.json', '{"testEnvironment":"<rootDir>/test/env.js"}')
    write('jest/t.js', '// transform'); write('test/env.js', '// env'); install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == base_files | {'jest-preset.json','jest/t.js','test/env.js'}
elif case == 'json-config':
    fresh(case); write('jest.config.json', '\ufeff{ /* JSONC */ "projects":[{"rootDir":"<rootDir>/pkg","testEnvironment":".\\/env.js","reporters":[["./rep.js",{"resolver":"./missing"}]]}],}')
    write('pkg/env.js', '// project env'); write('pkg/rep.js', '// project reporter'); install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == base_files | {'jest.config.json','pkg/env.js','pkg/rep.js'}
elif case == 'notice':
    fresh(case); write('jest.config.js', transform_config); write('jest/transform.js', transform)
    install(); result = red(); lines = result.stdout.splitlines(keepends=True)
    line = b'shipcraft: red also locked what jest reads beside the tests: jest/transform.js\n'
    assert result.returncode == 0 and lines.count(line) == 1
    at = lines.index(line)
    assert lines[at-1].startswith(b'shipcraft: controls:') and lines[at+1].startswith(b'shipcraft: RED locked at ')
    assert b': 5 file(s),' in lines[at+1] and set(lock()[1]['files']) == jest_files | {'jest/transform.js'}
    assert all('jest/transform.js' not in (json.loads(l)['files'] or '') for l in Path('.trace155').read_text().splitlines())
elif case == 'redo':
    fresh(case); write('jest.config.js', 'module.exports={};'); seed(); before = set(lock()[1]['files'])
    write('jest.config.js', 'module.exports={testEnvironment:"./test/env.js"};'); write('test/env.js', '// env')
    result = red('--redo'); lines = result.stdout.splitlines()
    assert result.returncode == 0 and set(lock()[1]['files']) == before | {'test/env.js'}
    at = next(i for i,l in enumerate(lines) if l.startswith(b'shipcraft: RED redone at '))
    assert lines[at-1] == b'shipcraft: red also locked what jest reads beside the tests: test/env.js' and b': 5 file(s),' in lines[at]
    commit('redo155'); saved = lock()[0].read_bytes(); result = red('--redo')
    assert result.returncode == 0 and b'RED unchanged' in result.stdout and prefix.encode() not in result.stdout and lock()[0].read_bytes() == saved
elif case == 'vitest-control':
    fresh(case, suite_command=command.replace('/jest ', '/vitest '))
    write('vitest.config.ts', 'export default {transform:{x:"./jest/t.js"},preset:"./p.js"};')
    install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == base_files | {'vitest.config.ts'} and prefix.encode() not in result.stdout
    assert b'fake155:False' in Path('.git/shipcraft/output/red.log').read_bytes()
elif case == 'missing-transform':
    fresh(case); write('jest.config.js', r'module.exports={transform:{"\\.js$":"<rootDir>/jest/missing.js"}};'); install(); result = red()
    assert refusal(result, 'setup-unreadable', 'red') == refusal_bytes('jest.config.js', '<rootDir>/jest/missing.js names no file in the repository')
    assert not list(Path('.shipcraft/locks').glob('*.json')) and prefix.encode() not in result.stdout
    assert b'fake155:False' in Path('.git/shipcraft/output/red.log').read_bytes()
elif case == 'missing-env':
    fresh(case); write('jest.config.js', 'module.exports={testEnvironment:"./test/none.js"};'); install(); result = red()
    assert refusal(result, 'setup-unreadable', 'red') == refusal_bytes('jest.config.js', './test/none.js names no file in the repository')
    assert not list(Path('.shipcraft/locks').glob('*.json')) and prefix.encode() not in result.stdout
elif case == 'absolute':
    fresh(case); write('jest.config.js', 'module.exports={resolver:"/opt/r.js"};'); install(); result = red()
    assert refusal(result, 'setup-unreadable', 'red') == refusal_bytes('jest.config.js', '/opt/r.js is an absolute path')
    assert not list(Path('.shipcraft/locks').glob('*.json')) and prefix.encode() not in result.stdout
elif case == 'linked':
    fresh(case); write('jest.config.js', 'module.exports={testEnvironment:"<rootDir>/test/env.js"};')
    Path('test').mkdir(); Path('test/env.js').symlink_to('../src/setup.js'); install(); result = red()
    assert refusal(result, 'setup-unreadable', 'red') == refusal_bytes('jest.config.js', 'test/env.js is a symbolic link')
    assert not list(Path('.shipcraft/locks').glob('*.json')) and prefix.encode() not in result.stdout
elif case == 'missing-preset':
    fresh(case); write('jest.config.js', 'module.exports={preset:"./nope"};'); install(); result = red()
    assert refusal(result, 'setup-unreadable', 'red') == refusal_bytes('jest.config.js', './nope names no file in the repository')
    assert not list(Path('.shipcraft/locks').glob('*.json')) and prefix.encode() not in result.stdout
elif case == 'preset-not-object':
    fresh(case); write('jest.config.js', 'module.exports={preset:"./p.json"};'); write('p.json', '[1]'); install(); result = red()
    assert refusal(result, 'setup-unreadable', 'red') == refusal_bytes('p.json', 'it is not a JSON object')
    assert not list(Path('.shipcraft/locks').glob('*.json')) and prefix.encode() not in result.stdout
elif case == 'preset-rootdir':
    fresh(case); write('jest.config.js', 'module.exports={preset:"./p.js"};'); write('p.js', 'module.exports={rootDir:"src"};'); install(); result = red()
    assert refusal(result, 'setup-unreadable', 'red') == refusal_bytes('p.js', 'it sets rootDir')
    assert not list(Path('.shipcraft/locks').glob('*.json')) and prefix.encode() not in result.stdout
elif case == 'manifest-order':
    fresh(case); write('package.json', '{"jest":{"transform":{"x":"./a-missing.js"},"preset":"./b-missing"}}'); install(); result = red()
    assert refusal(result, 'setup-unreadable', 'red') == refusal_bytes('package.json', './b-missing names no file in the repository')
    assert not list(Path('.shipcraft/locks').glob('*.json')) and prefix.encode() not in result.stdout
elif case == 'text-order':
    fresh(case, suite_command=command+' # vitest'); write('jest.config.js', 'module.exports={reporters:["./r-missing.js"],setupFiles:"./s-missing.js"};'); install(); result = red()
    assert refusal(result, 'setup-unreadable', 'red') == refusal_bytes('jest.config.js', './r-missing.js names no file in the repository')
    assert not list(Path('.shipcraft/locks').glob('*.json')) and prefix.encode() not in result.stdout
    write('a/vitest.config.ts', 'export default {setupFiles:variable};'); result = red()
    assert refusal(result, 'setup-unreadable', 'red') == (b'shipcraft refused: could not read the vitest setup files of a/vitest.config.ts: setupFiles is not a string or an array of strings\n'
        b'Why: red locks the setup files it can name; one it cannot name could change what every locked case sees\n'
        b'Next: in a/vitest.config.ts, write setupFiles and globalSetup as string literals or arrays of them, with paths relative to the file and no root key, then run red again\n')
elif case == 'ci':
    fresh(case); write('jest.config.js', transform_config); write('jest/transform.js', transform); seed()
    result = green({'jest/transform.js': '// PASS155'}, ci=True)
    assert b'locked test jest/transform.js changed after RED (in commit ' in refusal(result, 'test-changed', 'ci')
    assert lock()[1]['state'] == 'open' and Path('src/sum.js').read_text() == stub
elif case == 'env-import':
    fresh(case); write('jest.config.js', 'module.exports={testEnvironment:require("./environment-name")};')
    write('environment-name.js', 'module.exports="./unfollowed.js";'); write('unfollowed.js', '// not read as a path')
    install(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files | {'environment-name.js'}
    assert b'fake155:False' in Path('.git/shipcraft/output/red.log').read_bytes()
elif case == 'preset-change':
    fresh(case); write('jest.config.js', 'module.exports={preset:"ts-jest"};'); seed()
    result = green({'jest.config.js': 'module.exports={preset:"other"};', 'src/sum.js': repair})
    assert b'locked test jest.config.js changed after RED' in refusal(result, 'test-changed', 'hook') and lock()[1]['state'] == 'open'
elif case == 'product-control':
    fresh(case); write('jest.config.js', 'module.exports={testEnvironment:"./test/env.js",transform:{x:"./jest/transform.js"},preset:"./p.js",reporters:["./r.js"],moduleNameMapper:{x:"<rootDir>/mock.js"}};')
    for path in ('test/env.js','jest/transform.js','r.js','mock.js'): write(path, '// '+path)
    write('p.js', 'module.exports={setupFiles:"./src/setup.js"};'); seed()
    result = green({'src/sum.js': repair})
    assert result.returncode == 0 and lock()[1]['state'] == 'closed'
    trace = [json.loads(l) for l in Path('.trace155').read_text().splitlines()]
    assert trace[-1]['runner'] == 'fake155' and trace[-1]['passed'] and trace[-1]['files'] == str(Path('src/sum.test.js').resolve())+'\0'
elif case == 'fake-control':
    fresh(case); seed(); data = lock()[1]
    assert data['failing_at_red'] == ['src/sum.test.js::adds'] and 'src/other.test.js::control155' in data['cases']
    original = Path('src/sum.test.js').read_text()
    result = green({'src/sum.test.js': original+'// changed'})
    assert b'locked test src/sum.test.js changed after RED' in refusal(result, 'test-changed', 'hook')
    write('src/sum.test.js', original)
    result = green({'product-note':'CI control155'}, ci=True)
    assert result.returncode == 0 and rows('ci')[-1]['result'] == 'passed'
    assert git('show', 'HEAD:product-note') == 'CI control155' and lock()[1]['state'] == 'open'
    result = green({'src/sum.js': repair})
    assert result.returncode == 0 and lock()[1]['state'] == 'closed'
    trace = [json.loads(l) for l in Path('.trace155').read_text().splitlines()]
    assert trace[-1] == {'runner':'fake155','passed':True,'files':str(Path('src/sum.test.js').resolve())+'\0'} and any(not t['passed'] for t in trace)
elif case == 'real-control':
    fresh(case, real=True); write('jest.config.js', transform_config); write('jest/transform.js', transform); seed()
    assert lock()[1]['failing_at_red'] == ['src/sum.test.js:: adds'] and b'stub155' in Path('.git/shipcraft/output/red.log').read_bytes()
    result = green({'src/sum.js': repair})
    assert result.returncode == 0 and lock()[1]['state'] == 'closed' and Path('jest/transform.js').read_text() == transform
elif case == 'log-failure':
    fresh(case); write('jest.config.js', transform_config); write('jest/transform.js', transform); install()
    log = Path('.git/shipcraft/runs.jsonl'); log.unlink(); log.mkdir(); result = red()
    assert result.returncode == 0 and set(lock()[1]['files']) == jest_files | {'jest/transform.js'}
    assert b'shipcraft: red also locked what jest reads beside the tests: jest/transform.js\n' in result.stdout and log.is_dir()
    log.rmdir(); commit('RED155'); log.unlink(); log.mkdir(); result = green({'jest/transform.js':'// PASS155'})
    assert result.returncode == 1 and b'locked test jest/transform.js changed after RED' in result.stdout+result.stderr and lock()[1]['state'] == 'open' and log.is_dir()
elif case == 'redo-refused':
    fresh(case); write('jest.config.js', 'module.exports={};'); seed(); saved = lock()[0].read_bytes()
    write('jest.config.js', 'module.exports={preset:"./p.json"};'); write('p.json', '{/* strict JSON rejects comments */}')
    result = red('--redo')
    assert refusal(result, 'setup-unreadable', 'red') == refusal_bytes('p.json', 'it is not a JSON object')
    assert lock()[0].read_bytes() == saved and rows('red')[-1]['redo'] is True and prefix.encode() not in result.stdout
    log = Path('.git/shipcraft/runs.jsonl'); log.unlink(); log.mkdir(); result = red('--redo')
    assert result.returncode == 1 and refusal_bytes('p.json', 'it is not a JSON object') in result.stdout+result.stderr
    assert lock()[0].read_bytes() == saved and log.is_dir() and b'fake155:False' in Path('.git/shipcraft/output/red.log').read_bytes()
elif case == 'io-failure':
    fresh(case); write('jest.config.js', 'module.exports={preset:"./p.js",testEnvironment:"./missing"};')
    write('p.js', 'module.exports={};'); install(); Path('p.js').unlink(); result = red()
    assert result.returncode == 2 and not list(Path('.shipcraft/locks').glob('*.json')) and prefix.encode() not in result.stdout
    assert b'fake155:False' in Path('.git/shipcraft/output/red.log').read_bytes()
    fresh('io-write'); write('jest.config.js', transform_config); write('jest/transform.js', transform); install()
    folder = Path('.shipcraft/locks'); folder.chmod(0o555)
    try: result = red()
    finally: folder.chmod(0o755)
    assert result.returncode == 2 and not list(folder.glob('*.json')) and prefix.encode() not in result.stdout
    assert rows('red')[-1]['result'] == 'error' and b'fake155:False' in Path('.git/shipcraft/output/red.log').read_bytes()
else:
    raise AssertionError('unrouted ' + case)
PY155
  pass
}
