#!/usr/bin/env python3
"""Item 32: real Go/gotestsum; only the reader's failures are simulated."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tomli

kind = os.environ['I32_KIND']
suite = Path(os.environ['I32_SUITE'])
cw = Path(os.environ['ITEM32_CW'])


def setup():
    version = tomli.loads((Path(__file__).parents[2] / 'nucleo/Cargo.toml').read_text())['package']['version']
    module = Path('go.mod')
    if kind in ('modulo-suite', 'modulo-mais-proximo'):
        module = suite / 'go.mod'
    elif kind == 'modulo-intermediario':
        module = Path('services/go.mod')
    forms = {
        'tab': 'module\texample.com/textutil\n',
        'comentario': 'module example.com/textutil // comentario\n',
        'aspas': 'module "example.com/textutil"\n',
        'multilinha': 'module (\n example.com/textutil\n)\n',
        'crlf': 'module example.com/textutil\r\n',
        'espacos': '  module   example.com/textutil\n',
        'bloco-invalido': 'module ( example.com/textutil )\n',
    }
    if module != Path('go.mod'):
        if kind == 'modulo-mais-proximo':
            Path('go.mod').write_text('module example.com/ancestral\n\ngo 1.21\n')
        else:
            Path('go.mod').unlink()
    module.write_bytes((forms.get(kind, 'module example.com/textutil\n') + '\ngo 1.21\n').encode())
    no_module = kind in ('sem-go-mod', 'fora-repositorio', 'bloco-invalido')
    if kind in ('sem-go-mod', 'fora-repositorio'):
        module.unlink()
    if kind == 'fora-repositorio':
        Path('../go.mod').write_text('module example.com/externo\n\ngo 1.21\n')
    if not no_module:
        result = subprocess.run(['go', 'mod', 'edit', '-json', str(module.resolve())], check=True, capture_output=True, text=True)
        assert json.loads(result.stdout)['Module']['Path'] == 'example.com/textutil'
    else:
        # Only the test run uses GOPATH; the reader still sees the real go.mod.
        os.environ['GO111MODULE'] = 'off'
    command = 'gotestsum --junitfile {junit} -- -count=1 ./...'
    if no_module:
        command = 'GO111MODULE=off ' + command
    Path('.shipcraft.toml').write_text('shipcraft_min = ' + json.dumps(version) + '\nlang = "go"\nrunner = "gotestsum"\n[[suite]]\nname = "api"\nroot = ' + json.dumps(str(suite)) + '\ncommand = ' + json.dumps(command) + '\nglobs = ["**/*_test.go"]\n')


def wrappers():
    target = cw / 'leitor'
    target.mkdir()
    original_path = os.environ['PATH']
    real_go = shutil.which('go')
    real_sum = shutil.which('gotestsum')
    for name in ('go', 'gotestsum'):
        if kind == 'sem-go' and name == 'go':
            continue
        script = target / name
        script.write_text('#!' + sys.executable + '\n' +
            'import json,os,sys\nfrom pathlib import Path\n' +
            'name=' + repr(name) + '\nkind=' + repr(kind) + '\n' +
            'with open(' + repr(str(cw / 'calls.jsonl')) + ',"a") as f: f.write(json.dumps([name]+sys.argv[1:])+"\\n")\n' +
            ('if sys.argv[1:4]==["mod","edit","-json"]:\n'
             ' if kind=="comando-falha": sys.exit(7)\n'
             ' if kind=="json-invalido": print("{"); sys.exit(0)\n'
             ' if kind=="module-ausente": print("{}"); sys.exit(0)\n'
             ' if kind=="path-ausente": print(\'{"Module":{}}\'); sys.exit(0)\n'
             ' if kind=="path-vazio": print(\'{"Module":{"Path":""}}\'); sys.exit(0)\n' if name == 'go' else '') +
            'os.environ["PATH"]=' + repr(original_path) + '\n' +
            'os.execv(' + repr(real_go if name == 'go' else real_sum) + ',[' + repr(name) + ']+sys.argv[1:])\n')
        script.chmod(0o755)


def no_go_path():
    target = cw / 'no-go'
    target.mkdir()
    # Resolve before replacing PATH, including the gotestsum observer wrapper.
    for name in ('sh', 'git', 'shipcraft', 'gotestsum', 'python3', 'env', 'dirname',
                 'basename', 'cat', 'mkdir', 'rm', 'mv', 'cp', 'chmod', 'grep',
                 'sed', 'awk', 'sort', 'tail', 'head', 'cut', 'tr', 'wc', 'find',
                 'mktemp', 'readlink', 'uname', 'date', 'printf', 'touch', 'ln', 'test'):
        tool = shutil.which(name)
        if tool is None:
            raise RuntimeError('missing fixture tool: ' + name)
        (target / name).symlink_to(tool)


def verify():
    calls = [json.loads(line) for line in (cw / 'calls.jsonl').read_text().splitlines()]
    commands = [c[1:] for c in calls if c[0] == 'gotestsum']
    assert commands, calls
    if kind in ('sem-go', 'comando-falha', 'json-invalido', 'module-ausente', 'path-ausente', 'path-vazio', 'sem-go-mod', 'fora-repositorio', 'bloco-invalido'):
        if kind in ('sem-go-mod', 'fora-repositorio'):
            assert not any(c[0] == 'go' and c[1:4] == ['mod', 'edit', '-json'] for c in calls), calls
        return
    for args in commands:
        assert './...' not in args, ('package filter missing', args)
        assert '-run' in args, ('item 13 name filter missing', args)
    # The absolute path may be the judged copy's; the package subpath is stable.
    assert all(any(arg.endswith('/a') or arg == './a' for arg in args) for args in commands), commands


{'setup': setup, 'wrappers': wrappers, 'verify': verify, 'no-go-path': no_go_path}[sys.argv[1]]()
