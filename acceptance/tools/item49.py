#!/usr/bin/env python3
"""Black-box closing messages; reuse only existing acceptance fixture helpers."""
import os
from pathlib import Path
import subprocess
import sys
import item17 as f

mode = sys.argv[1]
f.locks = f.setup()
base = f.git('rev-parse', 'HEAD^')
if mode.startswith('two-'):
    # Names are not sealed fields. Keep two identical, genuinely generated RED
    # locks in the RED snapshot; their paths alone identify the two cycles.
    data = Path(f.locks[0]).read_bytes()
    Path(f.locks[0]).unlink()
    names = ['Z-last', 'a-first']  # byte order differs from case-folded order
    if mode == 'two-reverse':
        names.reverse()
    for name in names:
        Path('.shipcraft/locks', name + '.json').write_bytes(data)
    f.locks = [f'.shipcraft/locks/{name}.json' for name in names]
    f.git('add', '-A')
    f.git('commit', '--amend', '--no-edit', '-q')
    assert f.states() == ['open', 'open']
f.green()
if mode.startswith('legacy-'):
    # check's user-commit route writes a valid seal; hand-author the historical
    # closing commit with the old subject, without calling close at all.
    f.run('shipcraft', 'check')
    assert [f.state(Path(p).read_bytes()) for p in f.locks] == ['closed']
    f.git('add', '-A')
    old = 'shipcraft: close lock ' + Path(f.locks[0]).stem
    f.git('commit', '-qm', old)
    assert f.git('log', '-1', '--format=%s') == old
    # Closed means tests can change, even though the closing subject is old.
    with Path('tests/test_slug.py').open('a') as stream:
        stream.write('\n# changed after the historical close\n')
    f.git('add', 'tests/test_slug.py')
    if mode == 'legacy-hook':
        f.judge()
        assert not f.mark().exists(), 'old-subject closed lock was treated as open'
    else:
        f.git('commit', '-qm', 'test: after historical closure')
        f.run('shipcraft', 'ci', '--base', base)
else:
    if mode == 'post':
        os.environ['LEFTHOOK'] = '1'
        parent = f.head()
        f.commit()
        user = f.git('rev-parse', 'HEAD^')
        assert f.git('rev-parse', user + '^') == parent
    else:
        f.judge()
        assert f.mark().is_file()
        user = f.commit()
        if mode == 'retry':
            index = f.path('index').read_bytes()
            files = [Path(p).read_bytes() for p in f.locks]
            f.path('index.lock').write_text('occupied\n')
            out = f.close()
            assert 'shipcraft close' in out, out
            assert f.head() == user and f.mark().is_file()
            assert f.path('index').read_bytes() == index
            assert [Path(p).read_bytes() for p in f.locks] == files
            f.path('index.lock').unlink()
        if mode == 'post-ref-failure':
            # Let the closing commit exist, then obstruct its index repair.
            real_git = f.shutil.which('git')
            bindir = Path(os.environ['TMPDIR']) / 'item49-git'
            bindir.mkdir()
            trigger = bindir / 'triggered'
            index_path = f.path('index').resolve()
            saved = bindir / 'saved-index'
            q = f.shlex.quote
            wrapper = bindir / 'git'
            wrapper.write_text('#!/bin/sh\nif [ "$1" = update-ref ]; then\n  '
                + q(real_git) + ' "$@" || exit $?\n  mv ' + q(str(index_path))
                + ' ' + q(str(saved)) + '\n  mkdir ' + q(str(index_path))
                + '\n  touch ' + q(str(trigger)) + '\n  exit 0\nfi\nexec '
                + q(real_git) + ' "$@"\n')
            wrapper.chmod(0o755)
            old_path = os.environ['PATH']
            os.environ['PATH'] = str(bindir) + os.pathsep + old_path
            out = f.close()
            os.environ['PATH'] = old_path
            assert trigger.exists(), 'did not reach the later index repair failure'
            assert 'git ' in out and any(x in out for x in ('index', 'reset', 'restore')), out
            index_path.rmdir()
            f.shutil.move(str(saved), str(index_path))
        else:
            f.close()
    assert f.head() != user and f.git('rev-parse', 'HEAD^') == user
    assert f.states() == ['closed'] * len(f.locks)
    assert f.states('HEAD^') == ['open'] * len(f.locks)
    changed = f.git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD').splitlines()
    assert sorted(changed) == sorted(f.locks)
    ids = sorted((Path(p).stem for p in f.locks), key=lambda s: s.encode('utf-8'))
    expected = ('chore(shipcraft): close lock ' + ', '.join(ids) + '\n').encode()
    raw = subprocess.check_output(['git', 'cat-file', 'commit', 'HEAD']).split(b'\n\n', 1)[1]
    print('raw closing message:', repr(raw), 'expected:', repr(expected), flush=True)
    assert raw == expected, f'closing message bytes: expected {expected!r}, got {raw!r}'
    assert not f.mark().exists()
