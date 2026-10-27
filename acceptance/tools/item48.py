#!/usr/bin/env python3
"""Reuse item 28's real-Git boundary and exact warning/verdict assertions."""
from pathlib import Path

# Load only the reusable definitions, before item 28 starts its scenario.
source = Path(__file__).with_name('item28.py').read_text()
exec(compile(source.split('# .gitkeep is empty by definition;', 1)[0], 'item28-helpers', 'exec'))

keep = locks / '.gitkeep'
assert keep.is_file() and keep.read_bytes() == b'', 'init did not leave its empty placeholder'
assert git('show', 'HEAD:.shipcraft/locks/.gitkeep').stdout == '', 'init placeholder not committed'
keep.unlink()
fixture_commit('chore: warning-free control')
write('item48-pending.txt', 'later commit\n')
git('add', 'item48-pending.txt')
baseline = hook()
assert baseline.returncode == 0 and 'shipcraft: warning:' not in baseline.stdout, baseline.stdout
expected = []
extra = 0
env = base_env
query_error = False
if mode == 'refusal':
    cfg = repo / '.shipcraft.toml'
    cfg.write_text(re.sub(r'shipcraft_min\s*=\s*"[^"]*"', 'shipcraft_min = "999999.0.0"', cfg.read_text()))
    git('add', '.shipcraft.toml')
    baseline = hook()
    assert baseline.returncode == 1 and 'shipcraft: warning:' not in baseline.stdout, baseline.stdout

if mode.startswith('only-'):
    hooks = scratch / 'hooks'
    hooks.mkdir()
    receipt = scratch / 'effective-index'
    installed = hooks / ('pre-commit' if route == 'pre' else 'commit-msg')
    installed.write_text('#!/bin/sh\n' + 'printf "%s\\n" "$GIT_INDEX_FILE" > ' + shlex.quote(str(receipt)) + '\n'
        + 'exec ' + shlex.quote(binary) + ' check' + (' --commit-msg "$1"' if route == 'msg' else '') + '\n')
    installed.chmod(0o755)
    # Commit a control through the same real Git temporary-index route.
    baseline = git('-c', f'core.hooksPath={hooks}', 'commit', '--only', '-qm', 'control', '--', 'item48-pending.txt')
    if mode == 'only-symlink':
        target = scratch / 'empty-target'
        target.write_bytes(b'')
        keep.symlink_to(target)
    else:
        write('.shipcraft/locks/.gitkeep', '' if mode == 'only-empty' else 'nonempty\n')
    git('add', keep)
    write('item48-pending.txt', 'next commit\n')
    result = git('-c', f'core.hooksPath={hooks}', 'commit', '--only', '-qm', 'judged', '--', 'item48-pending.txt', ok=False)
    assert receipt.read_text().strip() and not receipt.read_text().strip().endswith('/index'), 'missing temporary index'
    check_output(result, baseline, [] if mode == 'only-empty' else [warning('.shipcraft/locks/.gitkeep')])
    assert git('ls-tree', '--name-only', 'HEAD', '--', '.shipcraft/locks/.gitkeep').stdout == ''
    assert '.shipcraft/locks/.gitkeep' in git('ls-files', '--', '.shipcraft/locks/.gitkeep').stdout
    sys.exit(0)

if mode in ('nested', 'other-root'):
    # Another project root *inside the queried directory* remains an outside path.
    path = ('.shipcraft/locks/sub/.gitkeep' if mode == 'nested' else
            '.shipcraft/locks/other/.shipcraft/locks/.gitkeep')
    write(path, '')
    expected = [warning(path)]
elif mode in ('symlink', 'staged-symlink'):
    target = scratch / 'empty-target'
    target.write_bytes(b'')
    keep.symlink_to(target)
    if mode == 'staged-symlink':
        git('add', keep)
    else:
        expected = [warning('.shipcraft/locks/.gitkeep')]
else:
    write('.shipcraft/locks/.gitkeep', 'not empty\n' if mode in ('nonempty', 'committed-nonempty', 'committed-nonempty-outside', 'staged-nonempty', 'index-nonempty') else '')
    if mode in ('committed', 'committed-nonempty', 'committed-nonempty-outside'):
        fixture_commit('chore: restore placeholder')
        if mode == 'committed-nonempty-outside':
            git('rm', '--cached', keep)
            expected = [warning('.shipcraft/locks/.gitkeep')]
        write('item48-pending.txt', 'next commit\n')
        git('add', 'item48-pending.txt')
    elif mode == 'intent':
        git('add', '-N', keep)
    elif mode in ('staged', 'staged-nonempty', 'index-empty', 'index-nonempty'):
        git('add', keep)
        if mode == 'index-empty':
            keep.write_text('dirty nonempty tree; index stays empty\n')
        elif mode == 'index-nonempty':
            keep.write_bytes(b'')
    elif mode == 'ignored':
        with (repo / '.git/info/exclude').open('a') as f:
            f.write('\n.shipcraft/locks/.gitkeep\n')
        assert git('check-ignore', keep).returncode == 0
    elif mode == 'nonempty':
        expected = [warning('.shipcraft/locks/.gitkeep')]
    elif mode == 'six':
        names = ['Z.txt', 'a.txt', 'z.json', 'C.json', 'a.json', 'b.md']
        paths = ['.shipcraft/locks/' + name for name in names]
        for path in reversed(paths):
            write(path)
        paths.sort(key=lambda p: (not p.endswith('.json'), os.fsencode(p)))
        expected = [warning(path) for path in paths[:5]]
        extra = 1
    elif mode.startswith('query-'):
        bindir = scratch / 'git-probe'
        bindir.mkdir()
        wrapper = bindir / 'git'
        wrapper.write_text('#!' + sys.executable + '\n'
            'import os,sys\n'
            f'real={real_git!r}; mode={mode!r}\n'
            'args=sys.argv[1:]\n'
            'query="ls-files" in args and any(".shipcraft/locks" in a for a in args)\n'
            'ignored="--ignored" in args or "-i" in args\n'
            'if query and "--others" in args and ignored==(mode=="query-ignored"):\n'
            ' print("item28-consulta-falhou",file=sys.stderr); sys.exit(47)\n'
            'os.execv(real,[real]+args)\n')
        wrapper.chmod(0o755)
        env = dict(base_env, PATH=str(bindir) + os.pathsep + base_env['PATH'])
        query_error = True

# The hook is read-only with respect to the caller's index and worktree.
index_before = (repo / '.git/index').read_bytes()
keep_before = os.readlink(keep) if keep.is_symlink() else (keep.read_bytes() if keep.exists() else None)
result = hook(env)
check_output(result, baseline, expected, extra, query_error)
assert (repo / '.git/index').read_bytes() == index_before, 'warning changed the index'
keep_after = os.readlink(keep) if keep.is_symlink() else (keep.read_bytes() if keep.exists() else None)
assert keep_after == keep_before, 'warning changed the placeholder'
