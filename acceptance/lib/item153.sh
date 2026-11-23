# Item 153: init and status can keep hooks wired by hand.
item153_cases() {
  local c
  for c in repro pre-custom flow foreign-commit two-tools pre-foreign lefthook-invalid \
    pre-link foreign-post two-lefthooks extends lefthook-foreign symlink kept commit \
    dispatcher early-exit operator cr comments manual-pre \
    manual-local only-commit rollback check-only worktree pre-duplicate lefthook-duplicate \
    husky-pre husky-lefthook husky-empty husky-other husky-check husky-link git-bad \
    installed-check status-fallback status-custom status-partial control-own; do
    echo "v1-153.$c"
  done
}

item153_case() {
  EXPECT='item 153 hand-wired hooks contract'
  v1_start codex claude
  must_accept 'hand-wired hooks contract' cmd "$PY" - "${CASE#v1-153.}" "$CW" <<'PY153'
import ast
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

case, work = sys.argv[1], Path(sys.argv[2]).resolve()
binary = Path(shutil.which('shipcraft')).resolve()
env = os.environ.copy()
env.pop('LEFTHOOK_CONFIG', None)
# Invoke the judged binary by path and isolate hook tool discovery.
excluded = {'shipcraft', 'pre-commit', 'prek', 'lefthook', 'husky'}
path = []
for i, entry in enumerate(os.get_exec_path(env)):
    directory = Path(entry).resolve()
    if not any((directory / name).exists() for name in excluded):
        path.append(entry)
        continue
    shadow = work / f'path153-{i}'
    shadow.mkdir()
    for tool in directory.iterdir():
        if tool.name not in excluded:
            (shadow / tool.name).symlink_to(tool)
    path.append(str(shadow))
env['PATH'] = os.pathsep.join(path)
assert all(shutil.which(tool, path=env['PATH']) is None for tool in excluded)

root = work / 'project153'
root.mkdir()
os.chdir(root)
sys.path.insert(0, str(Path(os.environ['ACEITE']) / 'tools'))
from lefthook_fixture import snapshot

events = ('commit-msg', 'post-commit')
plain = Path('.git/hooks')
custom = Path('.githooks')
commit_call = b'shipcraft check --commit-msg "$1"'
post_call = b'shipcraft close'
pre = Path('.pre-commit-config.yaml')
lefthook = Path('lefthook.yml')
yaml_block = b'repos:\n  - repo: local\n    hooks: []\n'
yaml_flow = b'repos: [{repo: local, hooks: []}]\n'
lefthook_block = b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n'
kept_config = (b'# keep this file byte for byte\nshipcraft_min = "2.0"\n'
               b'test_command = "pytest --junitxml={junit}"\ntest_globs = ["tests/**"]\n'
               b'[execution]\nci = "off"\nreview = "off"\n')

why = 'Why: shipcraft does not replace or edit another tool\'s hook: when in doubt, this step stays manual'
custom_reason = 'core.hooksPath is ".githooks", and shipcraft only accepts .git/hooks, exactly'
pre_foreign = 'installed hook commit-msg (.git/hooks/commit-msg) is not from pre-commit or prek'
installed_check = 'the installed pre-commit hook runs `shipcraft check`'
twice = 'with it, the suite would run twice per commit: remove it and run `shipcraft init` again'
one_tool = 'keep only one and run `shipcraft init` again'
hand_status = 'shipcraft: hooks call shipcraft, wired by hand (commit-msg and post-commit)'
item101_status = 'shipcraft: hooks in core.hooksPath .githooks call shipcraft (commit-msg and post-commit)'


def run(*args, environment=env):
    result = subprocess.run(args, input=b'', env=environment, capture_output=True, timeout=45)
    print('$', *map(str, args), f'[rc={result.returncode}]', flush=True)
    print((result.stdout + result.stderr).decode(errors='replace'), end='', flush=True)
    return result


def git(*args, environment=env):
    result = run('git', *args, environment=environment)
    assert result.returncode == 0, (args, result.stderr)
    return result.stdout


def write(path, data, mode=0o644):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    path.chmod(mode)


def script(path, call, header=b'#!/bin/sh'):
    write(path, header + b'\n' + call + b'\n', 0o755)


def pair(folder, commit=commit_call, post=post_call, header=b'#!/bin/sh'):
    script(folder / 'commit-msg', commit, header)
    script(folder / 'post-commit', post, header)


def set_custom():
    git('config', 'core.hooksPath', str(custom))


def init(executable=binary):
    return run(executable, 'init', '--lang', 'python')


def hook_state(folder):
    return {name: (p.read_bytes(), stat.S_IMODE(p.stat().st_mode))
            for name in events for p in (folder / name,)}


def assert_line(output, expected):
    assert output.splitlines(keepends=True).count(expected.encode() + b'\n') == 1, (expected, output)


def assert_refusal(result, reason, next_text, explanation=why):
    expected = f'shipcraft refused: {reason}\n{explanation}\nNext: {next_text}\n'.encode()
    assert result.returncode == 1, result
    assert result.stdout + result.stderr == expected, (expected, result.stdout, result.stderr)


def paths(folder):
    return tuple(folder / event for event in events)


def plain_next(reason, rerun='shipcraft init'):
    return f'what prevents commit-msg integration: {reason}; fix it and run `{rerun}` again'


custom_next = plain_next(custom_reason)


def check_kept(result, before, folder):
    assert_line(result.stdout, f'shipcraft: commit-msg and post-commit hooks call shipcraft, wired by hand ({folder}/commit-msg, {folder}/post-commit), kept')
    assert hook_state(folder) == before, 'changed hook bytes or mode'
    assert not any(text in result.stdout for text in (
        b'added shipcraft to', b'still need to install', b'hooks have no stages',
        b"hooks call this project's install", b'hooks installed', b'hooks already installed',
    )), result.stdout
    ready, = [line for line in result.stdout.split(b'\n') if line.startswith(b'shipcraft: ready')]
    assert not any(name in ready for name in (b'commit-msg', b'post-commit')), ready
    assert Path('.shipcraft/locks/.gitkeep').is_file()
    assert Path('AGENTS.md').is_file()
    assert Path('CLAUDE.md').is_file()
    assert all(Path(f'.shipcraft/briefs/{phase}.md').is_file() for phase in ('red', 'green'))


def status():
    before = snapshot()
    result = run(binary, 'status')
    assert snapshot() == before, 'status changed the fixture'
    return result


def husky():
    git('config', 'core.hooksPath', '.husky/_')
    # Reuse the Husky 9.1 helper captured in the item 25 real-install fixture.
    source = (Path(os.environ['ACEITE']) / 'lib/item25.sh').read_text()
    python = source.split("<<'PY25'\n", 1)[1].split('\nPY25', 1)[0]
    constants = {node.targets[0].id: ast.literal_eval(node.value)
                 for node in ast.parse(python).body
                 if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name)
                 and node.targets[0].id == 'HUSKY_H'}
    write('.husky/_/h', constants['HUSKY_H'].encode())
    pair(Path('.husky/_'))


git('init', '-q', '-b', 'main')
write('pyproject.toml', b'[project]\nname = "item153"\nversion = "0"\n')
write('tests/test_a.py', b'def test_a():\n    assert True\n')

def accept(folder):
    before_tree, before_hooks = snapshot(), hook_state(folder)
    result = init()
    assert result.returncode == 0, ('init should keep the hand-wired hooks', result)
    assert Path('.shipcraft.toml').is_file()
    check_kept(result, before_hooks, folder)
    after_tree = snapshot()
    assert after_tree.items() >= before_tree.items(), 'init changed preexisting files, hook folders or modes'
    additions = after_tree.keys() - before_tree.keys()
    assert not any(name.startswith(('.git/', '.githooks/', 'hook targets/')) for name in additions), additions
    return result


def refuse(reason, next_text, executable=binary, explanation=why):
    before = snapshot()
    result = init(executable)
    assert snapshot() == before, 'refused init changed the tree, modes or Git config'
    assert_refusal(result, reason, next_text, explanation)


def assert_status(expected, exit_code=0):
    result = status()
    assert result.returncode == exit_code, result
    assert_line(result.stdout, expected)
    hook_lines = [line for line in result.stdout.split(b'\n') if line.startswith((
        b'shipcraft: missing hook:', b'shipcraft: hooks call shipcraft, wired by hand',
        b'shipcraft: hooks in core.hooksPath', b'shipcraft: shipcraft hooks installed',
    ))]
    assert hook_lines == [expected.encode()], hook_lines
    return result


if case == 'repro':
    set_custom()
    pair(custom)
    before = hook_state(custom)
    result = init()
    assert result.returncode == 0, 'init refused executable hand-wired hooks in .githooks'
    assert Path('.shipcraft.toml').is_file()
    check_kept(result, before, custom)
    assert_status(item101_status)
elif case == 'pre-custom':
    set_custom()
    write(pre, yaml_block)
    pair(custom, header=b'#!/bin/bash')
    accept(custom)
    assert_status(hand_status)
elif case == 'flow':
    write(pre, yaml_flow)
    pair(plain)
    accept(plain)
    assert_status(hand_status)
    write('.shipcraft/locks/future153.json', b'{"format":999,"state":"open","files":{},"cases":[],"failing_at_red":[],"seal":""}\n')
    result = assert_status(hand_status, exit_code=1)
    assert b'format 999' in result.stdout + result.stderr
elif case == 'foreign-commit':
    script(plain / 'commit-msg', b'touch ran-hook153\n' + commit_call)
    script(plain / 'post-commit', post_call)
    accept(plain)
    assert_status(hand_status)
    assert not Path('ran-hook153').exists(), 'init or status ran the hook'
    (plain / 'post-commit').unlink()
    reason = 'a commit-msg hook not owned by shipcraft already exists (.git/hooks/commit-msg)'
    refuse(reason, plain_next(reason))
elif case == 'two-tools':
    write(pre, yaml_block)
    write(lefthook, lefthook_block)
    pair(plain)
    accept(plain)
    assert_status(hand_status)
elif case == 'pre-foreign':
    write(pre, yaml_block)
    pair(plain)
    accept(plain)
    assert_status(hand_status)
elif case == 'lefthook-invalid':
    write(lefthook, b'pre-commit:\n  commands: [unclosed\n')
    pair(plain)
    accept(plain)
    assert_status(hand_status)
elif case == 'pre-link':
    write('pre-source.yaml', yaml_block, 0o600)
    pre.symlink_to('pre-source.yaml')
    pair(plain)
    accept(plain)
elif case == 'foreign-post':
    # A marked, executable commit-msg leaves post-commit as the only foreign file.
    script(plain / 'commit-msg', b'# shipcraft hook\n' + commit_call)
    script(plain / 'post-commit', post_call)
    accept(plain)
elif case == 'two-lefthooks':
    write(lefthook, lefthook_block)
    write('.lefthook.yaml', lefthook_block)
    pair(plain)
    accept(plain)
elif case == 'extends':
    write(lefthook, b'extends:\n  - base.yml\n' + lefthook_block)
    pair(plain)
    accept(plain)
elif case == 'lefthook-foreign':
    write(lefthook, lefthook_block)
    pair(plain)
    accept(plain)
elif case == 'symlink':
    set_custom()
    targets = Path('hook targets')
    pair(targets, commit=b'\texec "/some path"/bin/"ship"craft check\t--commit-msg $1 # keep',
         post=b'./node_modules/.bin/shipcraft close\t# keep', header=b'#!/usr/bin/env sh\t ')
    custom.mkdir()
    for event in events:
        (custom / event).symlink_to('../hook targets/' + event)
    accept(custom)
    assert all(p.is_symlink() for p in paths(custom))
elif case == 'kept':
    write('.shipcraft.toml', kept_config, 0o600)
    pair(plain)
    result = accept(plain)
    assert Path('.shipcraft.toml').read_bytes() == kept_config
    assert_line(result.stdout, 'shipcraft: .shipcraft.toml already exists, kept')
    # Hook selection succeeds before the existing config is validated.
    write('.shipcraft.toml', b'shipcraft_min = [\n', 0o600)
    before = snapshot()
    result = init()
    assert result.returncode == 1, result
    assert b'.shipcraft.toml' in result.stderr and b'TOML' in result.stderr, result
    assert b'wired by hand' not in result.stdout
    assert snapshot() == before
elif case == 'commit':
    set_custom()
    pair(custom)
    accept(custom)
    log = Path('.git/shipcraft/runs.jsonl')
    assert not log.exists(), 'init wrote a run row'
    hook_bin = work / 'hook-bin'
    hook_bin.mkdir()
    (hook_bin / 'shipcraft').symlink_to(binary)
    hook_env = dict(env, PATH=str(hook_bin) + os.pathsep + env['PATH'])
    git('add', 'pyproject.toml', 'tests/test_a.py', '.shipcraft.toml')
    git('commit', '-qm', 'test: hand-wired commit', environment=hook_env)
    row, = map(json.loads, log.read_bytes().splitlines())
    assert row['layer'] == 'hook' and row['result'] == 'passed', row
elif case == 'dispatcher':
    set_custom()
    script(custom / 'dispatcher', b'case "$0" in\n  *commit-msg) : ;;\n  *post-commit) : ;;\nesac')
    for event in events:
        (custom / event).symlink_to('dispatcher')
    before = snapshot()
    first = init()
    assert snapshot() == before, 'first refused init changed dispatcher, links, modes or Git config'
    with (custom / 'commit-msg').open('ab') as hook:
        hook.write(commit_call + b'\n')
    with (custom / 'post-commit').open('ab') as hook:
        hook.write(post_call + b'\n')
    assert hook_state(custom)['commit-msg'][0] == hook_state(custom)['post-commit'][0]
    assert (custom / 'dispatcher').read_bytes().endswith(commit_call + b'\n' + post_call + b'\n')
    before = snapshot()
    second = init()
    assert snapshot() == before, 'second refused init changed dispatcher, links, modes or Git config'
    assert_refusal(first, custom_reason, custom_next)
    assert_refusal(second, custom_reason, custom_next)
elif case == 'early-exit':
    set_custom()
    for early in (b'exit 0', b'\texec true'):
        pair(custom, commit=early + b'\n' + commit_call)
        refuse(custom_reason, custom_next)
elif case == 'operator':
    set_custom()
    # Merged v1-153.trailing-command: keep its fixture and assertion.
    pair(custom, post=post_call + b'\nprintf done')
    refuse(custom_reason, custom_next)
    for suffix in (b' || true', b' &'):
        pair(custom, commit=commit_call + suffix)
        refuse(custom_reason, custom_next)
    pair(custom, post=post_call + b'; true')
    refuse(custom_reason, custom_next)
elif case == 'cr':
    set_custom()
    pair(custom)
    script(custom / 'post-commit', post_call + b'\r', b'#!/bin/sh\r')
    refuse(custom_reason, custom_next)
    pair(custom, header=b'#!/bin/sh -n')
    refuse(custom_reason, custom_next)
    pair(custom, header=b'\xef\xbb\xbf#!/bin/sh')
    refuse(custom_reason, custom_next)
elif case == 'comments':
    pair(plain, commit=commit_call + b'\n\n\t # comment \xff\n\t',
         post=b'\tshipcraft close  # terminal\n\n # comment', header=b'#!/usr/bin/env bash')
    accept(plain)
elif case == 'manual-pre':
    write(pre, yaml_block)
    script(plain / 'commit-msg', b'echo foreign')
    refuse(pre_foreign, 'remove it and run `shipcraft init` again')
elif case == 'manual-local':
    set_custom()
    destination = root / 'node_modules/shipcraft-fixture/bin/shipcraft'
    destination.parent.mkdir(parents=True)
    shutil.copy2(binary, destination)
    executable = root / 'node_modules/.bin/shipcraft'
    executable.parent.mkdir()
    executable.symlink_to(destination)
    rerun = 'npx -- shipcraft init'
    before = snapshot()
    result = init(executable)
    assert snapshot() == before, 'refused init changed the tree, modes or Git config'
    assert b'node_modules/.bin/shipcraft' not in result.stdout + result.stderr
    assert_refusal(result, custom_reason, plain_next(custom_reason, rerun))
elif case == 'only-commit':
    set_custom()
    refuse(custom_reason, custom_next)
    script(custom / 'commit-msg', commit_call)
    refuse(custom_reason, custom_next)
    script(custom / 'post-commit', post_call)
    (custom / 'post-commit').chmod(0o644)
    refuse(custom_reason, custom_next)
elif case == 'rollback':
    set_custom()
    pair(custom)
    # A regular file makes the later locks-directory write fail on any filesystem.
    write('.shipcraft', b'keep this blocker\r\n')
    before = snapshot()
    result = init()
    assert result.returncode == 2, result
    assert_line(result.stdout + result.stderr, 'shipcraft: undid what this run created')
    assert b'wired by hand' not in result.stdout
    assert snapshot() == before, 'rollback left config, hooks, Git changes or onboarding files'
elif case == 'check-only':
    set_custom()
    for bad_call in (b'shipcraft check', b'shipcraft check --commit-msg-extra "$1"',
                     b'shipcraft check --commit-msg "$2"', b'npx --no -- ' + commit_call):
        pair(custom, commit=bad_call)
        refuse(custom_reason, custom_next)
elif case == 'worktree':
    git('add', '.')
    git('commit', '-qm', 'test: linked worktree base')
    linked = work / 'linked worktree153'
    git('worktree', 'add', '-qb', 'linked153', linked)
    script(plain / 'commit-msg', b'echo foreign')
    root_before = snapshot()
    os.chdir(linked)
    folder = root / plain
    reason = f'a commit-msg hook not owned by shipcraft already exists ({folder}/commit-msg)'
    assert paths(folder) == tuple(Path(os.fsdecode(git('rev-parse', '--git-path', f'hooks/{event}').rstrip(b'\n'))) for event in events)
    before = snapshot()
    refusal = init()
    assert snapshot() == before, 'linked refusal changed the linked tree or Git config'
    os.chdir(root)
    assert snapshot() == root_before, 'linked refusal changed the main repository'
    pair(folder)
    root_before = snapshot()
    os.chdir(linked)
    accept(folder)
    os.chdir(root)
    assert snapshot() == root_before, 'linked init changed the main repository'
    assert_refusal(refusal, reason, plain_next(reason))
elif case == 'pre-duplicate':
    write(pre, b'repos:\n  - repo: local\n    hooks:\n      - id: check\n        name: check\n'
               b'        entry: shipcraft check\n        language: system\n        stages: [pre-commit]\n')
    pair(plain)
    refuse('.pre-commit-config.yaml has an `shipcraft check` in pre-commit', twice)
elif case == 'lefthook-duplicate':
    write(lefthook, b'pre-commit:\n  commands:\n    shipcraft:\n      run: shipcraft check\n      priority: 9\n')
    pair(plain)
    refuse('lefthook.yml has an `shipcraft` command in pre-commit, and integration uses commit-msg',
           'remove the shipcraft command from lefthook.yml pre-commit and run `shipcraft init` again',
           explanation='Why: with both, the suite would run twice per commit')
elif case == 'husky-pre':
    husky()
    write(pre, yaml_block)
    refuse('the project uses two hook tools: husky (.husky/) and the pre-commit framework (.pre-commit-config.yaml)',
           one_tool)
elif case == 'husky-lefthook':
    husky()
    write(lefthook, lefthook_block)
    refuse('the project uses two hook tools: husky and lefthook (found lefthook.yml)', one_tool)
elif case == 'husky-empty':
    husky()
    write('.husky/_/h', b'')
    refuse('.husky/_/h is empty: husky installation was interrupted',
           'run `npx husky` and run `shipcraft init` again')
elif case == 'husky-other':
    husky()
    write('.husky/commit-msg', b'shipcraft status\n')
    refuse('.husky/commit-msg already calls shipcraft another way (shipcraft status)',
           'keep only `shipcraft check --commit-msg "$1"` and run `shipcraft init` again')
elif case == 'husky-check':
    husky()
    write('.husky/pre-commit', b'shipcraft check\n')
    refuse('.husky/pre-commit has an `shipcraft check`', twice)
elif case == 'husky-link':
    husky()
    write('.husky/target', b'echo unrelated\n')
    Path('.husky/commit-msg').symlink_to('target')
    refuse('.husky/commit-msg is a symbolic link', 'replace it with the file and run `shipcraft init` again')
elif case == 'git-bad':
    pair(plain)
    config = Path('.git/config')
    raw = config.read_bytes() + b'[core]\n\titem153 = "broken\n'
    line = raw.count(b'\n')
    config.write_bytes(raw)
    reason = f'git cannot open this repository (fatal: bad config line {line} in file .git/config)'
    refuse(reason, plain_next(reason))
elif case == 'installed-check':
    pair(plain)
    script(plain / 'pre-commit', b'exec ./node_modules/.bin/shipcraft check --commit-msg')
    refuse(installed_check, twice)
    write('.shipcraft.toml', kept_config)
    assert_status('shipcraft: missing hook: `shipcraft init` refuses: ' + installed_check)
    script(plain / 'pre-commit', b'# shipcraft hook\necho not-a-call')
    refuse(installed_check, twice)
    (plain / 'pre-commit').chmod(0o644)
    accept(plain)
    assert_status(hand_status)
elif case == 'status-fallback':
    pair(plain)
    write('.shipcraft.toml', kept_config)
    write(pre, yaml_flow)
    assert_status(hand_status)
    pre.unlink()
    assert_status(hand_status)
    write(pre, yaml_block)
    write(lefthook, lefthook_block)
    assert_status(hand_status)
    script(plain / 'pre-commit', b'shipcraft check')
    assert_status('shipcraft: missing hook: `shipcraft init` refuses: ' + installed_check)
elif case == 'status-custom':
    set_custom()
    pair(custom, post=post_call + b'\nprintf done')
    script(custom / 'pre-commit', b'shipcraft check')
    write('.shipcraft.toml', kept_config)
    assert_status(item101_status)
elif case == 'status-partial':
    write(pre, yaml_block)
    script(plain / 'commit-msg', commit_call)
    write('.shipcraft.toml', kept_config)
    assert_status('shipcraft: missing hook: `shipcraft init` refuses: ' + pre_foreign)
    (plain / 'commit-msg').unlink()
    result = init()
    assert result.returncode == 0, result
    assert_status('shipcraft: missing hook: missing hook commit-msg, hook post-commit; run `shipcraft init` and `pre-commit install -t commit-msg -t post-commit`')
elif case == 'control-own':
    result = init()
    assert result.returncode == 0, result
    assert Path('.shipcraft.toml').is_file()
    for name, args in zip(events, (b'check --commit-msg "$1"', b'close')):
        p = plain / name
        assert b'# shipcraft hook' in p.read_bytes() and args in p.read_bytes()
        assert p.stat().st_mode & 0o111
    assert_status('shipcraft: shipcraft hooks installed (commit-msg and post-commit)')
else:
    raise AssertionError(f'unrouted item 153 case {case}')
PY153
  pass
}
