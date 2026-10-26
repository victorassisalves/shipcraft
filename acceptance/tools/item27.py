"""Item 27.2: the public guide, not the init implementation."""
import pathlib
import re
import sys
import yaml

p = pathlib.Path(sys.argv[1])
assert p.is_file(), 'docs/github-ci.md missing'
s = p.read_text()
if sys.argv[2] == 'passos':
    assert re.search(r'ci\s*=\s*["\']github["\']', s), 'step to turn ci on'
    assert '.github/workflows/shipcraft.yml' in s and re.search(r'copy', s, re.I), 'step to copy the workflow'
    assert 'SHIPCRAFT_URL' in s and re.search(r'variable', s, re.I), 'repository variable'
    assert re.search(r'\bPR\b', s) and re.search(r'config[\s\S]{0,100}base|base[\s\S]{0,100}config', s, re.I), 'PR judged by the base config'
    assert 'shipcraft pr' in s and re.search(r'CI[^.\n]{0,40}local|ci\s*=\s*"local"', s, re.I), 'change still judged locally'
    for term in ['pnpm', 'pyproject.toml', 'requirements', 'go.work', 'go.mod']:
        assert term in s, f'setup limit missing: {term}'
    sys.exit(0)
blocks = re.findall(r'```(?:yaml|yml)?\s*\n(.*?)```', s, re.S)
workflows = []
for block in blocks:
    try:
        value = yaml.safe_load(block)
    except yaml.YAMLError:
        continue
    if isinstance(value, dict) and isinstance(value.get('jobs'), dict):
        workflows.append(block)
assert workflows, 'YAML workflow with jobs missing'
w = '\n'.join(workflows)
for term in ['shipcraft ci --base', 'SHIPCRAFT_URL', 'actions/checkout', 'pull_request', 'push']:
    assert term in w, f'workflow without {term}'
assert re.search(r'setup-|python|node|go-version', s, re.I), 'language setup missing'
