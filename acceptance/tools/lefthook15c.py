#!/usr/bin/env python3
"""Item 15c. Real v1.11.13 hook; minimal offline runner for the commands."""
import os
from pathlib import Path
import subprocess
import sys
import yaml
from lefthook_fixture import HOOK


def run(*args):
    p = subprocess.run(args, input='', text=True, capture_output=True, timeout=90)
    print(p.stdout + p.stderr)
    return p


def hook_sem_exec(case):
    path = Path('lefthook.yml')
    hp = Path('.git/hooks/pre-commit')
    data = {'pre-commit': {'commands': {'projeto': {'run': 'echo projeto', 'priority': 3}}}}
    status = case.startswith('status-')
    if status:
        data['pre-commit']['commands']['shipcraft'] = {'run': 'shipcraft check', 'priority': 9}
    path.write_text(yaml.safe_dump(data, default_flow_style=False, sort_keys=False))
    hp.write_text(HOOK)
    hp.chmod(0o644)
    assert not os.access(hp, os.X_OK), 'the hook fixture must not be executable'
    p = run('shipcraft', 'status' if status else 'init')
    assert p.returncode == 0, 'init/status refused a non-executable lefthook hook'
    if status:
        out = (p.stdout + p.stderr).lower()
        assert 'hook through lefthook' not in out and 'missing' in out, 'status must say missing hook when lefthook lacks the execute bit'
    else:
        commands = yaml.safe_load(path.read_text())['pre-commit']['commands']
        assert commands.get('shipcraft', {}).get('run') == 'shipcraft check', 'init did not integrate shipcraft check with a non-executable hook'
        assert commands['projeto'] == data['pre-commit']['commands']['projeto'], 'init changed the project command'
        assert sum('lefthook install' in line for line in (p.stdout + p.stderr).splitlines()) == 1, 'non-executable hook: missing the one-line lefthook install hint'
    assert hp.read_text() == HOOK and hp.stat().st_mode & 0o777 == 0o644, 'init/status changed the non-executable lefthook hook'


def main(case):
    # The pre-commit integration cases left with the one hook route; status remains.
    assert case == 'status-sem-exec-borda', case
    return hook_sem_exec(case)

if __name__ == '__main__':
    try:
        main(sys.argv[1])
    except AssertionError as error:
        sys.exit('15c: ' + str(error))
