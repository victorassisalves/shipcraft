# Item 150: public CLI, real local Git, offline item146 project fixture.
item150_langs() { echo core; }
item150_cases() {
  local c
  for c in repro root-line red-bytes green-bytes no-pnpm lock-symlink no-lock machine-pnpm subfolder \
    npx-to-pnpm pnpm-to-npx pnpm-to-machine machine-to-pnpm old142 old85 equal edited old-pnpm claude \
    status-project status-machine status-npx status-old-pnpm \
    uninstall-created uninstall-appended uninstall-dry-run uninstall-edited export \
    brief-npx brief-pnpm brief-old machine \
    distinct-root late-brief late-claude late-green late-status late-uninstall late-export export-control
  do
    echo "v1-150.$c"
  done
}
item150_case() {
  EXPECT="item 150: ${CASE#v1-150.}"
  v1_start
  must_accept 'project invocation in onboarding files' cmd "$PY" - "${CASE#v1-150.}" "$(command -v shipcraft)" "$CW" "$CB" "$ACEITE" <<'PY150'
import ast
import hashlib
import os
import re
import resource
import shlex
import shutil
import signal
import stat
import subprocess
import sys
from pathlib import Path

case, binary, cw, cb, acceptance = sys.argv[1:]
binary = str(Path(binary).resolve())
cw, cb, acceptance = map(Path, (cw, cb, acceptance))
realgit = shutil.which('git')

def load(number, names, namespace):
    """Reuse selected acceptance fixtures without running their case dispatch."""
    marker = f'PY{number}'
    source = (acceptance / f'lib/item{number}.sh').read_text()
    source = source.split(f"<<'{marker}'\n", 1)[1].split(f'\n{marker}', 1)[0]
    for node in ast.parse(source).body:
        if isinstance(node, ast.FunctionDef) and node.name in names:
            exec(compile(ast.Module(body=[node], type_ignores=[]), f'item{number} fixture', 'exec'), namespace)
        elif isinstance(node, ast.Assign) and all(isinstance(t, ast.Name) and t.id in names for t in node.targets):
            exec(compile(ast.Module(body=[node], type_ignores=[]), f'item{number} fixture', 'exec'), namespace)
    return namespace

load(146, {'put', 'run', 'ok', 'git', 'commit', 'install', 'fresh', 'init', 'pnpm', 'proxy'}, globals())
f85 = load(85, {'OLD84', 'ROOT_LINE', 'CLEANUP', 'NEW', 'variant'}, {})
f142 = load(142, {'NEW_LINE', 'PIN'}, {'f85': f85})
f145 = load(145, {'BLOCK_LINE', 'CURRENT'}, {'f142': f142})
load(143, {'entries', 'file_limit'}, globals())

MACHINE = f145['CURRENT']
NPX = f85['variant'](MACHINE, True)
ROOT_LINE = b"- Run Shipcraft commands from the repository root, where `pnpm exec shipcraft` runs this project's install.\n"

def pnpm_form(block):
    lines = block.replace(b'`shipcraft ', b'`pnpm exec shipcraft ').splitlines(keepends=True)
    return b''.join(lines[:2] + [ROOT_LINE] + lines[2:])

PNPM = pnpm_form(MACHINE)
OLD_PNPM = pnpm_form(f142['PIN'])
EDITED = PNPM.replace(b'TDD with a lock', b'TDD with a project lock', 1)
RED_PNPM = b'''# shipcraft: the RED phase

You are the RED session: you write the failing tests for a change, not the change.

- Write the failing tests from the intent, never from an implementation.
- Write two cases per rule: the ordinary one, and a boundary a rushed GREEN would get wrong.
- First read the existing tests that cover the behavior the change touches, and never contradict them unless the intent says that behavior changes.
- Each test written for the new behavior must fail for the right reason before you run `pnpm exec shipcraft red`. Passing control tests are fine: they are locked as controls.
- Fake external tools with their real output.
- The tests call the interface your prompt fixes (names, arguments, results, and the errors, exit codes or messages they check), and the stubs have it. What the prompt leaves out, choose, list with the ambiguities and name in your report, so the GREEN gets it; where the prompt contradicts the intent or the existing tests, stop and report it before `pnpm exec shipcraft red`.
- Commit the tests, their stubs and the lock in one commit, and stop.
- List ambiguities instead of picking a reading silently.

<!-- written by shipcraft <version> -->
'''

AGENTS = Path('AGENTS.md')
RED = Path('.shipcraft/briefs/red.md')
GREEN = Path('.shipcraft/briefs/green.md')
LOCK = Path('pnpm-lock.yaml')
CLOSING = b'shipcraft: then write the failing test and stub, and run `pnpm exec shipcraft red`.'
REPLACED = b'shipcraft: replaced the shipcraft block in AGENTS.md'
KEPT = b'shipcraft: AGENTS.md already has the shipcraft block, kept'
DIFFERS = KEPT + b"; it differs from this version's: edit it by hand to match docs/spec.md"
CURRENT = b'shipcraft: AGENTS.md block: current'
STATUS_DIFFERS = b"shipcraft: AGENTS.md block: differs from this version's; init keeps it, compare it with docs/spec.md by hand"
BRIEF_DIFFERS = b"shipcraft: .shipcraft/briefs/red.md differs from this version's, kept: compare it with docs/spec.md"
LEFT = b"shipcraft: left AGENTS.md: its shipcraft markers do not hold a block Shipcraft writes (edited by hand, or from another version); remove it by hand"

def digest(data):
    return len(data), hashlib.sha256(data).hexdigest()

def pnpm_project(data=b'lockfileVersion: 9.0\n'):
    put(LOCK, data)
    pnpm()

def ready(output):
    return next(line for line in output.splitlines() if line.startswith(b'shipcraft: ready. Commit '))

def read_only_status(binary_to_run):
    before = entries(root)
    result = run(binary_to_run, 'status')
    return result, before == entries(root)

def status_lines(result):
    return [line for line in result.stdout.splitlines() if line.startswith(b'shipcraft: AGENTS.md block:')]

def recovery(output):
    prefix = b'shipcraft: copying everything it removes or changes to '
    return Path(os.fsdecode(next(line[len(prefix):] for line in output.splitlines() if line.startswith(prefix))))

def export_fixture(block):
    git('checkout', '-qb', 'contribution')
    init(call)
    commit('install Shipcraft')
    put(AGENTS, b'# Project contribution\n\n' + block, 0o755)
    put('value', b'1\n')
    commit('contribute product and project guidance')

def export_state():
    # Git objects are legitimate export output, including on a late ref failure.
    return {k: v for k, v in entries(root).items() if k != '.git/objects' and not k.startswith('.git/objects/')}

root, tools, call, base = fresh('project150')
version = re.search(rb'\b[0-9]+\.[0-9]+\.[0-9]+\b', ok(binary, '--version')).group()
pnpm_red = RED_PNPM.replace(b'<version>', version)
npx_red = pnpm_red.replace(b'`pnpm exec shipcraft ', b'`npx -- shipcraft ')
bare_red = pnpm_red.replace(b'`pnpm exec shipcraft ', b'`shipcraft ')

if case == 'repro':
    pnpm_project()
    commit('pnpm lockfile')
    assert shutil.which('shipcraft', path=env['PATH']) is None
    out = init(call)
    block, red = AGENTS.read_bytes(), RED.read_bytes()
    assert CLOSING in out.splitlines() and not (cw / 'pnpm-ran').exists(), out
    assert (digest(block), red.count(b'`pnpm exec shipcraft red`'), b'npx --' in red) == (
        (8603, 'a8d3aed6bc40289af3a75863ff0abf2bd14e3935fde94070b301798d2a6b477f'), 2, False
    ), (digest(block), red.count(b'`pnpm exec shipcraft red`'), b'npx --' in red)
elif case == 'root-line':
    pnpm_project()
    # Git's hook-path lookup is after init has selected its invocation and
    # before the first onboarding write. A second lookup would now yield npx.
    proxy("if '--git-path' in a and 'hooks/commit-msg' in a and Path('pnpm-lock.yaml').is_file():\n Path('pnpm-lock.yaml').rename('lock-moved-by-git')")
    out = init(call)
    assert not LOCK.exists() and Path('lock-moved-by-git').is_file()
    assert CLOSING in out.splitlines()
    assert AGENTS.read_bytes().splitlines(keepends=True)[2] == ROOT_LINE
    assert RED.read_bytes() == pnpm_red
elif case == 'red-bytes':
    pnpm_project()
    init(call)
    assert RED.read_bytes() == pnpm_red, RED.read_bytes()
elif case == 'green-bytes':
    pnpm_project()
    init(call)
    local_green = GREEN.read_bytes()
    fresh('machine-green150')
    init(binary)
    assert local_green == GREEN.read_bytes()
    assert local_green.endswith(b'\n\n<!-- written by shipcraft ' + version + b' -->\n')
    assert b'\r' not in local_green
elif case == 'no-pnpm':
    put(LOCK, b'lockfileVersion: 9.0\n')
    out = init(call)
    assert shutil.which('pnpm', path=env['PATH']) is None
    assert b'shipcraft: then write the failing test and stub, and run `npx -- shipcraft red`.' in out.splitlines()
    assert digest(AGENTS.read_bytes()) == (8540, '6df332bde585b49cbb354480b20aa0a3eb9416132e9bf24437486f7b6ff4f2fc')
    assert RED.read_bytes() == npx_red
elif case == 'lock-symlink':
    put('real-lock', b'lockfileVersion: 9.0\n')
    LOCK.symlink_to('real-lock')
    pnpm()
    init(call)
    assert LOCK.is_symlink() and LOCK.is_file() and os.access(tools / 'pnpm', os.X_OK)
    assert digest(AGENTS.read_bytes()) == (8540, '6df332bde585b49cbb354480b20aa0a3eb9416132e9bf24437486f7b6ff4f2fc')
    assert RED.read_bytes() == npx_red
elif case == 'no-lock':
    pnpm()
    init(call)
    assert not LOCK.exists() and os.access(tools / 'pnpm', os.X_OK)
    assert digest(AGENTS.read_bytes()) == (8540, '6df332bde585b49cbb354480b20aa0a3eb9416132e9bf24437486f7b6ff4f2fc')
    assert RED.read_bytes() == npx_red
elif case == 'machine-pnpm':
    pnpm_project()
    out = init(binary)
    assert b'shipcraft: then write the failing test and stub, and run `shipcraft red`.' in out.splitlines()
    assert digest(AGENTS.read_bytes()) == (8295, 'c4dea4f98d06f55e4a4833f9712ed3c0c4ed1df24f2a097840f5e9c30ac30373')
    assert RED.read_bytes() == bare_red
elif case == 'subfolder':
    pnpm_project(b'\xff\0not YAML\n')
    sub = root / 'packages/a/deep'
    sub.mkdir(parents=True)
    put(sub / 'AGENTS.md', b'package guidance\n')
    os.chdir(sub)
    out = init(call)
    assert CLOSING in out.splitlines()
    assert (sub / 'AGENTS.md').read_bytes() == b'package guidance\n'
    assert (root / AGENTS).read_bytes() == PNPM
elif case == 'npx-to-pnpm':
    init(call)
    pnpm_project()
    prefix, suffix = b'# Mine\n\n', b'\nafter\n'
    put(AGENTS, prefix + NPX + suffix, 0o751)
    out = init(call)
    assert (AGENTS.read_bytes(), REPLACED in out.splitlines()) == (prefix + PNPM + suffix, True)
    assert stat.S_IMODE(AGENTS.stat().st_mode) == 0o751
elif case == 'pnpm-to-npx':
    pnpm()
    put(AGENTS, PNPM)
    out = init(call)
    assert (AGENTS.read_bytes(), REPLACED in out.splitlines()) == (NPX, True)
elif case == 'pnpm-to-machine':
    pnpm_project()
    put(AGENTS, PNPM)
    out = init(binary)
    assert (AGENTS.read_bytes(), REPLACED in out.splitlines()) == (MACHINE, True)
elif case == 'machine-to-pnpm':
    pnpm_project()
    put(AGENTS, MACHINE)
    out = init(call)
    assert (AGENTS.read_bytes(), REPLACED in out.splitlines()) == (PNPM, True)
elif case == 'old142':
    pnpm_project()
    put(AGENTS, f85['variant'](f142['PIN'], True))
    out = init(call)
    assert (AGENTS.read_bytes(), REPLACED in out.splitlines()) == (PNPM, True)
elif case == 'old85':
    pnpm_project()
    put(AGENTS, f85['NEW'])
    out = init(call)
    assert (AGENTS.read_bytes(), REPLACED in out.splitlines()) == (PNPM, True)
elif case == 'equal':
    pnpm_project()
    put(AGENTS, PNPM)
    original = AGENTS.stat()
    out = init(call)
    assert AGENTS.read_bytes() == PNPM and AGENTS.stat().st_ino == original.st_ino
    assert KEPT in out.splitlines() and DIFFERS not in out.splitlines()
elif case == 'edited':
    pnpm_project()
    put(AGENTS, EDITED)
    put(tools / 'claude', '#!/bin/sh\nexit 79\n', 0o755)
    out = init(call)
    assert AGENTS.read_bytes() == EDITED and DIFFERS in out.splitlines()
    assert not Path('CLAUDE.md').exists()
    assert b"shipcraft: CLAUDE.md not written: AGENTS.md does not hold this version's shipcraft block" in out.splitlines()
elif case == 'old-pnpm':
    pnpm_project()
    put(AGENTS, OLD_PNPM)
    out = init(call)
    assert AGENTS.read_bytes() == OLD_PNPM and DIFFERS in out.splitlines()
elif case == 'claude':
    pnpm_project()
    put(AGENTS, NPX)
    put(tools / 'claude', '#!/bin/sh\nexit 79\n', 0o755)
    out = init(call)
    assert (AGENTS.read_bytes(), REPLACED in out.splitlines()) == (PNPM, True)
    assert b'Shipcraft workflow (required): @AGENTS.md' in Path('CLAUDE.md').read_bytes().splitlines()
    assert b'CLAUDE.md' in ready(out)
elif case == 'status-project':
    pnpm_project()
    init(call)
    put(AGENTS, PNPM)
    commit('install with pnpm form')
    result, unchanged = read_only_status(call)
    assert result.returncode == 0 and unchanged
    assert status_lines(result) == [CURRENT]
    lines = result.stdout.splitlines()
    i = lines.index(CURRENT)
    assert b'hook' in lines[i - 1].lower() and lines[i + 1].startswith(b'shipcraft: open locks:')
elif case == 'status-machine':
    pnpm_project()
    init(call)
    put(AGENTS, PNPM)
    result, unchanged = read_only_status(binary)
    assert result.returncode == 0 and unchanged
    assert status_lines(result) == [CURRENT]
elif case == 'status-npx':
    init(call)
    pnpm_project()
    assert AGENTS.read_bytes() == NPX
    (root / '.git/hooks/commit-msg').unlink()
    result, unchanged = read_only_status(call)
    assert result.returncode == 0 and unchanged
    assert status_lines(result) == [CURRENT]
    assert b'run `pnpm exec shipcraft init`' in result.stdout
elif case == 'status-old-pnpm':
    pnpm_project()
    init(call)
    put(AGENTS, OLD_PNPM)
    result, unchanged = read_only_status(call)
    assert result.returncode == 0 and unchanged
    assert status_lines(result) == [STATUS_DIFFERS]
elif case == 'uninstall-created':
    init(call)
    # Seed the bytes a pnpm init will create so uninstall is tested on its own.
    put(AGENTS, PNPM)
    pnpm_project()
    result = run(call, 'uninstall')
    assert result.returncode == 0 and not AGENTS.exists(), result.stdout
    assert b'shipcraft: removed AGENTS.md' in result.stdout.splitlines()
    assert (recovery(result.stdout) / AGENTS).read_bytes() == PNPM
elif case == 'uninstall-appended':
    init(call)
    text = b'# Project\n'
    put(AGENTS, text + b'\n' + PNPM, 0o751)
    result = run(binary, 'uninstall')
    assert result.returncode == 0 and AGENTS.read_bytes() == text, result.stdout
    assert b'shipcraft: removed the shipcraft block from AGENTS.md' in result.stdout.splitlines()
    assert stat.S_IMODE(AGENTS.stat().st_mode) == 0o751
    copy = recovery(result.stdout) / AGENTS
    assert copy.read_bytes() == text + b'\n' + PNPM and stat.S_IMODE(copy.stat().st_mode) == 0o751
elif case == 'uninstall-dry-run':
    pnpm_project()
    init(call)
    put(AGENTS, PNPM)
    before = entries(root)
    result = run(call, 'uninstall', '--dry-run')
    assert result.returncode == 0 and entries(root) == before
    assert b'shipcraft: would remove AGENTS.md' in result.stdout.splitlines()
    assert not Path('.git/shipcraft/uninstalled').exists()
elif case == 'uninstall-edited':
    for block in (EDITED, OLD_PNPM):
        init(call)
        put(AGENTS, block)
        result = run(call, 'uninstall')
        assert result.returncode == 0 and LEFT in result.stdout.splitlines()
        assert AGENTS.read_bytes() == block and not (recovery(result.stdout) / AGENTS).exists()
elif case == 'export':
    export_fixture(PNPM)
    before = export_state()
    result = run(binary, 'export', '--base', 'main', 'clean150')
    assert result.returncode == 0, result.stderr
    blob = run(realgit, 'show', 'clean150:AGENTS.md')
    assert (blob.returncode, blob.stdout) == (0, b'# Project contribution\n'), (blob.stderr, result.stdout)
    assert b'has a shipcraft block that is not one Shipcraft writes' not in result.stdout
    assert git('ls-tree', 'clean150', 'AGENTS.md').startswith('100755 blob ')
    assert git('rev-list', '--count', base + '..clean150') == '1'
    assert git('show', 'clean150:value') == '1'
    after = export_state()
    assert after.pop('.git/refs/heads/clean150')[0] == 'file'
    after.pop('.git/logs/refs/heads/clean150', None)
    assert after == before, 'export changed something besides objects and destination ref'
elif case == 'brief-npx':
    init(call)
    assert RED.read_bytes() == npx_red
    pnpm_project()
    GREEN.unlink()
    out = init(call)
    assert RED.read_bytes() == npx_red
    assert BRIEF_DIFFERS not in out.splitlines() and b'.shipcraft/briefs/red.md' not in ready(out)
    assert b'.shipcraft/briefs/green.md' in ready(out)
elif case == 'brief-pnpm':
    put(RED, pnpm_red)
    out = init(call)
    assert RED.read_bytes() == pnpm_red
    assert BRIEF_DIFFERS not in out.splitlines() and b'.shipcraft/briefs/red.md' not in ready(out)
    assert GREEN.is_file() and b'.shipcraft/briefs/green.md' in ready(out)
elif case == 'brief-old':
    pnpm_project()
    another_version = b'0.0.1' if version != b'0.0.1' else b'0.0.2'
    previous = npx_red.replace(b'shipcraft ' + version + b' -->', b'shipcraft ' + another_version + b' -->')
    put(RED, previous)
    out = init(call)
    assert RED.read_bytes() == previous and BRIEF_DIFFERS in out.splitlines()
    assert b'.shipcraft/briefs/red.md' not in ready(out)
elif case == 'machine':
    out = init(binary)
    green = GREEN.read_bytes()
    assert b'shipcraft: then write the failing test and stub, and run `shipcraft red`.' in out.splitlines()
    assert digest(AGENTS.read_bytes()) == (8295, 'c4dea4f98d06f55e4a4833f9712ed3c0c4ed1df24f2a097840f5e9c30ac30373')
    assert RED.read_bytes() == bare_red
    assert b'`shipcraft ' not in green and b'\r' not in green
    assert green.endswith(b'\n\n<!-- written by shipcraft ' + version + b' -->\n')
    assert b'node_modules/.bin/shipcraft' not in Path('.git/hooks/commit-msg').read_bytes()
elif case == 'distinct-root':
    pnpm_project()
    sub = root / 'nested'
    put(sub / '.git', 'gitdir: nowhere150\n')
    env['GIT_DIR'] = str(root / '.git')
    env['GIT_WORK_TREE'] = str(root)
    os.chdir(sub)
    assert Path(git('rev-parse', '--show-toplevel')).resolve() == root.resolve()
    out = init(call)
    assert CLOSING in out.splitlines() and not AGENTS.exists()
    assert (root / AGENTS).read_bytes() == PNPM and (root / RED).read_bytes() == pnpm_red
elif case == 'late-brief':
    pnpm_project()
    put('.shipcraft/briefs', b'blocked150\n')
    out = init(call)
    assert Path('.shipcraft/briefs').read_bytes() == b'blocked150\n'
    assert b'shipcraft: .shipcraft/briefs not written:' in out
    assert Path('.shipcraft.toml').is_file() and Path('.shipcraft/locks/.gitkeep').is_file()
    assert AGENTS.read_bytes() == PNPM
elif case == 'late-claude':
    pnpm_project()
    put('CLAUDE.md/project-only', b'keep150')
    out = init(call)
    assert Path('CLAUDE.md/project-only').read_bytes() == b'keep150'
    assert b'CLAUDE.md' in out and b'CLAUDE.md' not in ready(out)
    assert AGENTS.read_bytes() == PNPM
elif case == 'late-green':
    pnpm_project()
    put(GREEN / 'project-only', b'keep150')
    out = init(call)
    assert (GREEN / 'project-only').read_bytes() == b'keep150'
    assert b'shipcraft: .shipcraft/briefs/green.md could not be read, kept' in out.splitlines()
    assert b'.shipcraft/briefs/red.md' in ready(out) and b'.shipcraft/briefs/green.md' not in ready(out)
    assert RED.read_bytes() == pnpm_red
elif case == 'late-status':
    pnpm_project()
    init(call)
    put(AGENTS, PNPM)
    shutil.rmtree('.shipcraft/locks')
    put('.shipcraft/locks', b'blocked150')
    result, unchanged = read_only_status(call)
    assert result.returncode == 2 and unchanged and b'shipcraft: error:' in result.stderr
    assert status_lines(result) == [CURRENT]
elif case == 'late-uninstall':
    pnpm_project()
    init(call)
    put(AGENTS, PNPM)
    put(RED, b'R' * 65536)
    result = run(call, 'uninstall', preexec_fn=file_limit)
    assert result.returncode == 2 and b'shipcraft: error:' in result.stderr
    assert RED.read_bytes() == b'R' * 65536 and Path('.shipcraft.toml').is_file()
    assert b'commit the removal:' not in result.stdout
    assert not AGENTS.exists() and (recovery(result.stdout) / AGENTS).read_bytes() == PNPM
elif case == 'late-export':
    export_fixture(PNPM)
    git('branch', 'clean150/child', base)
    trace = cw / 'export-tip'
    proxy(f"if 'update-ref' in a and 'refs/heads/clean150' in a:\n Path({str(trace)!r}).write_text(a[a.index('refs/heads/clean150')+1])")
    before = export_state()
    result = run(binary, 'export', '--base', 'main', 'clean150')
    assert result.returncode == 2 and result.stdout == b'' and b'shipcraft: error:' in result.stderr
    assert export_state() == before and not (root / '.git/refs/heads/clean150').is_file()
    blob = run(realgit, 'show', trace.read_text() + ':AGENTS.md')
    assert (blob.returncode, blob.stdout) == (0, b'# Project contribution\n'), blob.stderr
elif case == 'export-control':
    export_fixture(NPX)
    git('branch', 'clean150/child', base)
    trace = cw / 'export-tip'
    proxy(f"if 'update-ref' in a and 'refs/heads/clean150' in a:\n Path({str(trace)!r}).write_text(a[a.index('refs/heads/clean150')+1])")
    before = export_state()
    result = run(binary, 'export', '--base', 'main', 'clean150')
    assert result.returncode == 2 and result.stdout == b'' and b'shipcraft: error:' in result.stderr
    assert export_state() == before and not (root / '.git/refs/heads/clean150').is_file()
    assert ok(realgit, 'show', trace.read_text() + ':AGENTS.md') == b'# Project contribution\n'
    assert git('show', trace.read_text() + ':value') == '1'
else:
    raise AssertionError('unrouted item150 case: ' + case)

assert not (cw / 'pnpm-ran').exists(), 'invocation classification executed pnpm'
PY150
  pass
}
