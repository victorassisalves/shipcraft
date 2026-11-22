# Item 151 (cfe2f80): item 144's offline transport and gh environment log.
item151_cases() {
  local c
  for c in repro review-inherited review-local review-fork review-comment-failed review-status-failed \
    status status-inherited status-no-origin ci ci-inherited ci-squash ci-squash-read-failed ci-feature \
    init-github init-no-origin init-local report report-inherited report-root report-local \
    findings findings-comments-failed report-plain report-read-failed review-read-failed status-read-failed \
    init-read-failed ci-read-failed review-once status-once pr-permission pr-merge docs \
    harness-control review-control status-control; do
    echo "v1-151.$c"
  done
}

item151_case() {
  EXPECT="item 151: ${CASE#v1-151.}"; v1_start codex
  must_accept 'origin repository selection' cmd "$PY" - "${CASE#v1-151.}" "$(command -v shipcraft)" "$CB" "$CW" "$ACEITE/.." <<'PY151'
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

case, binary, cb, cw, source = sys.argv[1:]
binary = str(Path(binary).resolve())
cb, cw, source = map(Path, (cb, cw, source))
state = cb / 'state'
gh_log = state / 'gh-env.log'
git_log = state / 'git151.log'
ssh_log = state / 'ssh151.log'
git_fault = state / 'git151.fail'
url = 'git@github.example151:acme/proj.git'
get_url = ['remote', 'get-url', 'origin']
pair = ('github.example151/acme/proj', 'github.example151')
for key in ('GH_REPO', 'GH_HOST'):
    os.environ.pop(key, None)
for name in ('TMPDIR', 'XDG_STATE_HOME'):
    directory = cw / name
    directory.mkdir()
    os.environ[name] = str(directory)

def run(*args, **kwargs):
    args = list(map(str, args))
    result = subprocess.run(args, capture_output=True, text=True, timeout=90, **kwargs)
    print('$', shlex.join(args), 'exit', result.returncode,
          repr(result.stdout), repr(result.stderr), flush=True)
    return result

def ok(*args, **kwargs):
    result = run(*args, **kwargs)
    assert result.returncode == 0, (args, result.stderr)
    return result.stdout

def git(*args, **kwargs):
    return ok('git', *args, **kwargs).strip()

def records(path):
    return [json.loads(line) for line in path.read_text().splitlines()] if path.is_file() else []

def snapshot(message):
    git('add', '-A')
    tree = git('write-tree')
    sha = git('commit-tree', tree, '-p', git('rev-parse', 'HEAD'), input=message + '\n')
    git('update-ref', 'HEAD', sha)
    return sha

def script(name, body):
    path = cb / name
    path.write_text('#!' + sys.executable + '\n' + body)
    path.chmod(0o755)
    return path

def set_layers(ci, review):
    path = Path('.shipcraft.toml')
    prefix, contents = path.read_text().split('[execution]', 1)
    execution, sep, rest = contents.partition('[roles]')
    execution = re.sub(r'(?m)^ci\s*=.*$', 'ci = ' + json.dumps(ci), execution)
    execution = re.sub(r'(?m)^review\s*=.*$', 'review = ' + json.dumps(review), execution)
    path.write_text(prefix + '[execution]' + execution + sep + rest)

def install_observers(origin):
    # Git's SSH transport only runs local upload-pack and receive-pack.
    transport = script('transport151', f"""
import os, shlex, sys
args = shlex.split(sys.argv[-1])
assert args[0] in ('git-upload-pack', 'git-receive-pack'), args
os.execvp(args[0], [args[0], {str(origin)!r}])
""")
    os.environ.update(GIT_SSH_VARIANT='ssh', GIT_SSH_COMMAND=shlex.quote(str(transport)),
                      GIT_ALLOW_PROTOCOL='file:ssh')
    script('ssh', f"""
import json, sys
with open({str(ssh_log)!r}, 'a') as stream:
    stream.write(json.dumps(sys.argv[1:]) + '\\n')
assert len(sys.argv) == 3 and sys.argv[1] == '-G', sys.argv
print('hostname ' + sys.argv[2])
""")
    real_git = shutil.which('git')
    script('git', f"""
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
index = 0
while index < len(args) and args[index].startswith('-'):
    index += 2 if args[index] in ('-C', '-c', '--git-dir', '--work-tree') else 1
command = args[index:]
if not os.environ.get('I151_GH_STUB'):
    with open({str(git_log)!r}, 'a') as stream:
        stream.write(json.dumps(dict(args=command, cwd=os.getcwd(),
                                     git_dir=os.environ.get('GIT_DIR'),
                                     git_work_tree=os.environ.get('GIT_WORK_TREE'))) + '\\n')
if command == ['remote', 'get-url', 'origin'] and Path({str(git_fault)!r}).exists():
    print('fatal: injected151 get-url', file=sys.stderr)
    raise SystemExit(128)
os.execv({real_git!r}, [{real_git!r}, *args])
""")

def adapt_gh_stub(mode):
    stub = cb / 'gh151-real'
    (cb / 'gh').rename(stub)
    script('gh', f"""
import json, os, subprocess, sys
args = sys.argv[1:]
mode = {mode!r}
os.environ['I151_GH_STUB'] = '1'
comments_read = args[:1] == ['api'] and any('/issues/1/comments?' in arg for arg in args)
if mode == 'slurp' and comments_read and '--slurp' in args:
    # The battery stub emits a single page; real gh --slurp wraps it in an array.
    result = subprocess.run([{str(stub)!r}, *args], stdout=subprocess.PIPE)
    if result.returncode == 0:
        print(json.dumps([json.loads(result.stdout)]))
    raise SystemExit(result.returncode)
if ((mode == 'comment' and args[:2] == ['pr', 'comment'])
        or (mode == 'status' and args[:3] == ['api', '-X', 'POST'] and 'state=success' in args)
        or (mode == 'comments-read' and comments_read)):
    os.environ['SHIPCRAFT_STUB_FAIL'] = '1'
os.execv({str(stub)!r}, [{str(stub)!r}, *args])
""")
    return stub

def clear_logs():
    for path in (gh_log, git_log, ssh_log, state / 'calls.log', state / 'writes.log'):
        path.unlink(missing_ok=True)

def open_pr():
    git('push', '-q', 'origin', 'feat')
    ok('gh', 'pr', 'create', '--title', 'Item151', '--body', 'seed151', '--head', 'feat', '--base', 'main')

def fixture(*, ci='off', review='off', clone=False, upstream=False, fresh=False):
    if fresh:
        base = git('rev-parse', 'HEAD')
    else:
        ok(binary, 'init')
        set_layers(ci, review)
        base = snapshot('base151')
    origin = cb / 'origin.git'
    git('init', '-q', '--bare', origin)
    git('--git-dir=' + str(origin), 'symbolic-ref', 'HEAD', 'refs/heads/main')
    (state / 'origin').write_text(str(origin))
    git('remote', 'add', 'origin', origin)
    git('push', '-q', 'origin', 'main')
    git('remote', 'set-head', 'origin', 'main')
    if clone:
        previous = Path.cwd()
        checkout = cw / 'clone151'
        git('clone', '-q', origin, checkout)
        (checkout / '.venv').symlink_to(previous / '.venv', target_is_directory=True)
        os.chdir(checkout)
    if upstream:
        other = cb / 'upstream.git'
        git('clone', '-q', '--bare', origin, other)
        git('remote', 'add', 'upstream', other)
    git('checkout', '-qb', 'feat')
    Path('product151.py').write_text('value = 151\n')
    head = snapshot('feature151')
    (state / 'sha').write_text(head)
    install_observers(origin)
    return base, head, origin

def pin(calls, expected):
    assert calls and all((call['GH_REPO'], call['GH_HOST']) == expected for call in calls), calls
    assert all('--repo' not in call['args'] and '-R' not in call['args'] for call in calls), calls

def git_trace():
    return [call['args'] for call in records(git_log)]

def observed(*args, **kwargs):
    clear_logs()
    result = run(binary, *args, **kwargs)
    return result, records(gh_log)

def ssh_origin():
    git('remote', 'set-url', 'origin', url)

def inherit():
    os.environ.update(GH_REPO='other/repo', GH_HOST='other.example')

def rows():
    return records(Path('.git/shipcraft/runs.jsonl'))

def read_count(count, fallback=0, ssh=None):
    trace = git_trace()
    assert trace.count(get_url) == count and trace.count(['remote']) == fallback, trace
    if ssh is not None:
        assert records(ssh_log) == ssh, records(ssh_log)

def review_succeeded(result, calls):
    assert result.returncode == 0 and 'APPROVE' in result.stdout, result
    assert calls and calls[0]['args'][:3] == ['pr', 'view', '1'], calls
    assert len(records(state / 'reviewer.calls.jsonl')) == 1
    assert [status['state'] for status in records(state / 'statuses.jsonl')
            if status['context'] == 'shipcraft/review'] == ['pending', 'success']
    assert any(call['args'][:3] == ['pr', 'comment', '1'] for call in calls), calls

def protection_read(result, calls):
    assert result.returncode == 0, result
    assert len(calls) == 1 and calls[0]['args'][0] == 'api', calls
    assert calls[0]['args'][1].endswith('/branches/main/protection'), calls

def protection_write(result, calls):
    assert result.returncode == 0 and Path('.shipcraft.toml').is_file(), result
    assert len(calls) == 1 and calls[0]['args'][:3] == ['api', '-X', 'PUT'], calls
    assert calls[0]['args'][3].endswith('/branches/main/protection'), calls
    assert (state / 'protection').read_text().strip() == 'full'

def seed_status(head, context):
    with (state / 'statuses.jsonl').open('a') as stream:
        stream.write(json.dumps(dict(id=len(records(state / 'statuses.jsonl')) + 1,
                                     sha=head, context=context, state='success',
                                     description='fixture151', t=1700000000)) + '\n')

def arrive_on_main(*, closed=False):
    # Item 42's GitHub-button squash. The sealed closed lock follows item 79's fixture.
    base, head, _ = fixture(ci='local', review='local')
    if closed:
        test_path = Path('tests/test_151.py')
        test_path.write_text('def test_item151(): assert True\n')
        case_id = str(test_path) + '::test_item151'
        red_bytes = b'def test_item151(): assert False\n'
        lock = dict(format=4, state='closed',
                    files={str(test_path): 'sha256:' + hashlib.sha256(red_bytes).hexdigest()},
                    cases=[case_id], failing_at_red=[case_id], kind='feature',
                    reported_at=None, fixes_release=None, seal='')
        lock['seal'] = hashlib.sha256(json.dumps(lock, separators=(',', ':')).encode()).hexdigest()
        Path('.shipcraft/locks/a151.json').write_text(json.dumps(lock) + '\n')
        head = snapshot('closed fixture lock')
    open_pr()
    seed_status(head, 'shipcraft/ci')
    if closed:
        seed_status(head, 'shipcraft/review')
    ok('gh', 'pr', 'merge', '1', '--squash')
    git('checkout', '-q', 'main')
    git('pull', '-q', '--ff-only', 'origin', 'main')
    return base, git('rev-parse', 'HEAD'), head

def escape_warning(result, calls, merge, head, *, closed=False):
    assert result.returncode == 0, result
    endpoints = [arg for call in calls for arg in call['args'] if arg.startswith('repos/')]
    assert any(arg.endswith(f'/commits/{merge}/pulls') for arg in endpoints), endpoints
    assert any(arg.endswith(f'/commits/{head}/statuses') for arg in endpoints), endpoints
    if closed:
        assert not any(row.get('escape') for row in rows()), rows()
    else:
        assert any(arg.endswith('/issues/1/comments') for arg in endpoints), endpoints
        assert '#1' in result.stdout + result.stderr or merge[:7] in result.stdout + result.stderr, result
        assert any(row.get('escape') and row['commit'] == merge for row in rows()), rows()

def prepare_report():
    fixture(review='local', clone=True, upstream=True)
    ssh_origin()
    ok(binary, 'pr', '--title', 'Report151')
    assert any(row['layer'] == 'review' and row.get('pr') == 1 for row in rows()), rows()

def report_call():
    before = Path('.git/shipcraft/runs.jsonl').read_bytes()
    result, calls = observed('report', '--json', '--github')
    assert result.returncode == 0 and not result.stderr, result
    assert any(row['kind'] == 'github' for row in map(json.loads, result.stdout.splitlines()))
    assert any('statuses' in ' '.join(call['args']) for call in calls), calls
    assert Path('.git/shipcraft/runs.jsonl').read_bytes() == before
    return calls

failed_read = "could not read origin's repository: `git remote get-url origin` failed: fatal: injected151 get-url"
review_fields = 'number,title,body,headRefOid,headRefName,baseRefName,isCrossRepository'
ssh_once = [['-G', 'github.example151']]
other = ('other/repo', 'other.example')

if case == 'repro':
    fixture(review='local', clone=True, upstream=True)
    open_pr()
    git('remote', 'set-url', 'origin', url)
    clear_logs()
    result = run(binary, 'review', '--pr', '1')
    calls = records(gh_log)
    review_succeeded(result, calls)
    pin(calls, pair)
    assert git_trace().count(get_url) == 1, git_trace()
    assert records(ssh_log) == [['-G', 'github.example151']], records(ssh_log)
elif case == 'review-inherited':
    fixture(review='local', clone=True)
    open_pr()
    ssh_origin()
    inherit()
    result, calls = observed('review', '--pr', '1')
    review_succeeded(result, calls)
    pin(calls, pair)
elif case == 'review-local':
    fixture(review='local', clone=True)
    open_pr()
    inherit()
    result, calls = observed('review', '--pr', '1')
    review_succeeded(result, calls)
    pin(calls, other)
    assert not records(ssh_log)
elif case == 'review-fork':
    fixture(review='local')
    open_pr()
    path = state / 'prs.json'
    prs = json.loads(path.read_text())
    prs['1']['fork'] = True
    path.write_text(json.dumps(prs))
    ssh_origin()
    result, calls = observed('review', '--pr', '1')
    refusal = result.stderr.splitlines()
    assert result.returncode == 1 and len(refusal) == 3 and 'fork' in refusal[0], result
    assert refusal[1].startswith('Why:') and refusal[2].startswith('Next:'), refusal
    assert len(calls) == 1 and calls[0]['args'][:3] == ['pr', 'view', '1'], calls
    assert not records(state / 'writes.log') and not records(state / 'reviewer.calls.jsonl')
    pin(calls, pair)
elif case == 'review-comment-failed':
    fixture(review='local')
    open_pr()
    ssh_origin()
    adapt_gh_stub('comment')
    result, calls = observed('review', '--pr', '1')
    assert result.returncode == 2 and 'injected failure' in result.stderr, result
    assert calls[-1]['args'][:3] == ['pr', 'comment', '1'], calls
    assert not records(state / 'comments.jsonl')
    assert [row['state'] for row in records(state / 'statuses.jsonl')] == ['pending']
    assert any(row['layer'] == 'review' and row['result'] == 'passed' for row in rows()), rows()
    pin(calls, pair)
elif case == 'review-status-failed':
    fixture(review='local')
    open_pr()
    ssh_origin()
    adapt_gh_stub('status')
    result, calls = observed('review', '--pr', '1')
    assert result.returncode == 2 and 'injected failure' in result.stderr, result
    assert calls[-1]['args'][:3] == ['api', '-X', 'POST'] and 'state=success' in calls[-1]['args'], calls
    assert len(records(state / 'comments.jsonl')) == 1
    assert [row['state'] for row in records(state / 'statuses.jsonl')] == ['pending']
    assert any(row['layer'] == 'review' and row['result'] == 'passed' for row in rows()), rows()
    pin(calls, pair)
elif case == 'status':
    fixture()
    baseline, baseline_calls = observed('status')
    protection_read(baseline, baseline_calls)
    ssh_origin()
    result, calls = observed('status')
    protection_read(result, calls)
    assert result.stdout == baseline.stdout, result
    pin(calls, pair)
elif case == 'status-inherited':
    fixture()
    ssh_origin()
    inherit()
    result, calls = observed('status')
    protection_read(result, calls)
    pin(calls, pair)
elif case == 'status-no-origin':
    fixture()
    git('remote', 'remove', 'origin')
    baseline, baseline_calls = observed('status')
    protection_read(baseline, baseline_calls)
    inherit()
    result, calls = observed('status')
    protection_read(result, calls)
    assert result.stdout == baseline.stdout, result
    pin(calls, other)
elif case == 'ci':
    base, merge, head = arrive_on_main()
    ssh_origin()
    result, calls = observed('ci', '--base', base)
    escape_warning(result, calls, merge, head)
    pin(calls, pair)
elif case == 'ci-inherited':
    base, merge, head = arrive_on_main()
    ssh_origin()
    inherit()
    result, calls = observed('ci', '--base', base)
    escape_warning(result, calls, merge, head)
    pin(calls, pair)
elif case == 'ci-squash':
    base, merge, head = arrive_on_main(closed=True)
    ssh_origin()
    result, calls = observed('ci', '--base', base)
    escape_warning(result, calls, merge, head, closed=True)
    assert [arg for arg in calls[0]['args'] if arg.endswith(f'/commits/{merge}/pulls')], calls
    pin(calls, pair)
elif case == 'ci-squash-read-failed':
    base, merge, _ = arrive_on_main(closed=True)
    ssh_origin()
    git_fault.touch()
    result, calls = observed('ci', '--base', base)
    refusal = result.stderr.splitlines()
    assert result.returncode == 1 and any(line.startswith('shipcraft refused:') for line in refusal), result
    assert any(line.startswith('Why:') for line in refusal) and any(line.startswith('Next:') for line in refusal)
    assert any(row['layer'] == 'ci' and row.get('code') == 'lock-edited' for row in rows()), rows()
    assert not calls and not any(row.get('escape') for row in rows()), calls
    read_count(1, fallback=1, ssh=[])
elif case == 'ci-feature':
    base, head, _ = fixture()
    ssh_origin()
    result, calls = observed('ci', '--base', base)
    assert result.returncode == 0 and any(row['layer'] == 'ci' and row['commit'] == head for row in rows()), result
    assert not calls, calls
    read_count(0, ssh=[])
elif case == 'init-github':
    fixture(fresh=True)
    ssh_origin()
    (state / 'protection').write_text('none')
    result, calls = observed('init', '--github')
    protection_write(result, calls)
    assert 'requires' in result.stdout and 'shipcraft/ci' in result.stdout, result
    pin(calls, pair)
elif case == 'init-no-origin':
    fixture(fresh=True)
    git('remote', 'remove', 'origin')
    inherit()
    (state / 'protection').write_text('none')
    result, calls = observed('init', '--github')
    protection_write(result, calls)
    pin(calls, other)
elif case == 'init-local':
    fixture(fresh=True)
    ssh_origin()
    result, calls = observed('init')
    assert result.returncode == 0 and Path('.shipcraft.toml').is_file(), result
    assert not calls, calls
    read_count(0, ssh=[])
elif case == 'report':
    prepare_report()
    calls = report_call()
    pin(calls, pair)
    read_count(1, ssh=ssh_once)
elif case == 'report-inherited':
    prepare_report()
    inherit()
    calls = report_call()
    pin(calls, pair)
elif case == 'report-root':
    prepare_report()
    root = Path.cwd()
    other_checkout = cw / 'different151'
    git('init', '-q', '-b', 'main', other_checkout)
    git('-C', other_checkout, 'remote', 'add', 'origin', 'git@github.example151:other/repo.git')
    nested = root / 'nested'
    nested.mkdir()
    os.chdir(nested)
    try:
        env = dict(os.environ, GIT_DIR=str(other_checkout / '.git'), GIT_WORK_TREE=str(other_checkout))
        # The report still discovers the real root when invoked from inside it.
        result, calls = observed('report', '--json', '--github', env=env)
    finally:
        os.chdir(root)
    assert result.returncode == 0 and not result.stderr, result
    assert any('statuses' in ' '.join(call['args']) for call in calls), calls
    pin(calls, pair)
    reads = [call for call in records(git_log) if call['args'] == get_url]
    assert reads == [dict(args=get_url, cwd=str(root), git_dir=None, git_work_tree=None)], reads
elif case == 'report-local':
    prepare_report()
    git('remote', 'set-url', 'origin', (state / 'origin').read_text())
    inherit()
    pin(report_call(), other)
    assert not records(ssh_log)
elif case == 'findings':
    fixture()
    open_pr()
    ok('gh', 'pr', 'comment', '1', '--body',
       '**shipcraft: review executed by codex, on this machine**\n\nBlocking: 1\n## Blocking 1 — Delayed update')
    ok('gh', 'pr', 'merge', '1', '--squash')
    ssh_origin()
    adapt_gh_stub('slurp')
    result, calls = observed('report', '--findings', '--json')
    assert result.returncode == 0 and not result.stderr, result
    findings = [json.loads(line) for line in result.stdout.splitlines()]
    assert [(row['kind'], row['pr'], row['title']) for row in findings] == [('finding', 1, 'Delayed update')], findings
    assert calls[0]['args'][:2] == ['pr', 'list'], calls
    assert any('issues/1/comments' in ' '.join(call['args']) for call in calls), calls
    assert all(args == get_url for args in git_trace()), git_trace()
    pin(calls, pair)
    assert git_trace() == [get_url], git_trace()
elif case == 'findings-comments-failed':
    fixture()
    open_pr()
    ok('gh', 'pr', 'merge', '1', '--squash')
    ssh_origin()
    adapt_gh_stub('comments-read')
    result, calls = observed('report', '--findings', '--json')
    assert result.returncode == 0 and 'PR 1' in result.stderr, result
    findings = [json.loads(line) for line in result.stdout.splitlines()]
    assert findings == [dict(kind='pr_not_read', pr=1, reason='gh failed')], findings
    assert len(calls) == 2 and calls[0]['args'][:2] == ['pr', 'list'], calls
    assert any('/issues/1/comments?' in arg for arg in calls[1]['args']), calls
    pin(calls, pair)
    assert git_trace() == [get_url], git_trace()
elif case == 'report-plain':
    prepare_report()
    result, calls = observed('report', '--json')
    assert result.returncode == 0 and any(json.loads(line)['kind'] == 'review' for line in result.stdout.splitlines()), result
    assert not calls, calls
    read_count(0, ssh=[])
elif case == 'report-read-failed':
    prepare_report()
    git_fault.touch()
    inherit()
    pin(report_call(), other)
    read_count(1, ssh=[])
elif case == 'review-read-failed':
    fixture(review='local')
    open_pr()
    ssh_origin()
    before = rows()
    git_fault.touch()
    result, calls = observed('review', '--pr', '1')
    assert result.returncode == 2, result
    assert result.stderr == f'shipcraft: error: `gh pr view 1 --json {review_fields}` failed: {failed_read}\n', result
    assert not calls and not records(state / 'writes.log') and rows() == before, calls
    assert not records(state / 'reviewer.calls.jsonl')
    read_count(1, fallback=1, ssh=[])
elif case == 'status-read-failed':
    fixture()
    ssh_origin()
    git_fault.touch()
    result, calls = observed('status')
    assert result.returncode == 0, result
    assert f'shipcraft: could not read branch protection ({failed_read}): use `shipcraft merge` as the gate' in result.stdout.splitlines(), result
    assert not calls, calls
    read_count(1, fallback=1, ssh=[])
elif case == 'init-read-failed':
    fixture(fresh=True)
    ssh_origin()
    git_fault.touch()
    result, calls = observed('init', '--github')
    assert result.returncode == 0, result
    assert f'shipcraft: could not mark statuses as required ({failed_read}); `shipcraft merge` is the gate.' in result.stdout.splitlines(), result
    assert not calls and not records(state / 'writes.log'), calls
    assert all(Path(path).is_file() for path in ('.shipcraft.toml', 'AGENTS.md', '.shipcraft/locks/.gitkeep',
                                               '.shipcraft/briefs/red.md', '.shipcraft/briefs/green.md',
                                               '.git/hooks/commit-msg', '.git/hooks/post-commit')), result
    read_count(1, fallback=1, ssh=[])
elif case == 'ci-read-failed':
    base, merge, _ = arrive_on_main()
    ssh_origin()
    git_fault.touch()
    result, calls = observed('ci', '--base', base)
    assert result.returncode == 0, result
    warning = f'shipcraft: warning: could not check merges on main through gh: {failed_read}'
    assert warning in (result.stdout + result.stderr).splitlines(), result
    assert not calls and not any(row.get('escape') for row in rows()), calls
    assert any(row['layer'] == 'ci' and row['commit'] == merge and row['result'] == 'passed' for row in rows()), rows()
    read_count(1, fallback=1, ssh=[])
elif case == 'review-once':
    fixture(review='local', clone=True)
    open_pr()
    inherit()
    result, calls = observed('review', '--pr', '1')
    review_succeeded(result, calls)
    pin(calls, other)
    read_count(1, ssh=[])
elif case == 'status-once':
    fixture()
    git('remote', 'remove', 'origin')
    git('remote', 'add', 'origin-backup', (state / 'origin').read_text())
    inherit()
    result, calls = observed('status')
    protection_read(result, calls)
    pin(calls, other)
    read_count(1, fallback=1, ssh=[])
elif case == 'pr-permission':
    fixture()
    ssh_origin()
    inherit()
    result, calls = observed('pr', '--title', 'Item151 permission')
    assert result.returncode == 0 and json.loads((state / 'prs.json').read_text())['1']['title'] == 'Item151 permission', result
    assert calls[0]['args'][:3] == ['repo', 'view', url], calls
    pin(calls[:1], other)
    pin(calls[1:], pair)
    read_count(1, ssh=ssh_once)
elif case == 'pr-merge':
    fixture()
    ssh_origin()
    result, calls = observed('pr', '--title', 'Item151 merge', '--merge')
    assert result.returncode == 0 and json.loads((state / 'prs.json').read_text())['1']['state'] == 'MERGED', result
    assert calls[-1]['args'][:3] == ['pr', 'merge', '1'], calls
    pin(calls[1:], pair)
    read_count(2, ssh=ssh_once * 2)
elif case == 'docs':
    spec = (source / 'docs/spec.md').read_bytes()
    commands = spec.split(b'## 3. Commands\n', 1)[1].split(b'\n## ', 1)[0]
    anchor = b'`init` writes no run-log row; `red` and `close` write one each (item 38).'
    paragraph = (b"Every `gh` call a command makes names origin's repository (`GH_REPO` and `GH_HOST`) "
                 b"when origin's fetch URL reads as one, except item 130's `gh repo view <url>`, "
                 b"which names the URL it checks (item 151).")
    assert commands.count(anchor + b'\n\n' + paragraph + b'\n') == 1
elif case == 'harness-control':
    _, head, origin = fixture()
    ssh_origin()
    clear_logs()
    assert ok('ssh', '-G', 'github.example151').split() == ['hostname', 'github.example151']
    assert git('remote', 'get-url', 'origin') == url
    git_fault.touch()
    failure = run('git', 'remote', 'get-url', 'origin')
    assert failure.returncode == 128 and 'injected151 get-url' in failure.stderr, failure
    assert git('remote') == 'origin'
    git_fault.unlink()
    git('push', '-q', 'origin', 'feat')
    git('update-ref', '-d', 'refs/remotes/origin/feat')
    git('fetch', '-q', 'origin')
    assert git('rev-parse', 'refs/remotes/origin/feat') == head
    assert git('--git-dir=' + str(origin), 'rev-parse', 'refs/heads/feat') == head
    ok('gh', 'repo', 'view', url, '--json', 'viewerPermission')
    inherit()
    ok('gh', 'repo', 'view', url, '--json', 'viewerPermission')
    calls = records(gh_log)
    assert len(calls) == 2 and all(call['args'][:3] == ['repo', 'view', url] for call in calls), calls
    pin(calls[:1], (None, None))
    pin(calls[1:], other)
    read_count(2, fallback=1, ssh=ssh_once)
    open_pr()
    ok('gh', 'pr', 'comment', '1', '--body', 'Slurp fixture151')
    stub = adapt_gh_stub('slurp')
    pages = json.loads(ok('gh', 'api', '--paginate', '--slurp', 'repos/acme/proj/issues/1/comments?per_page=100'))
    assert len(pages) == 1 and [entry['body'] for entry in pages[0]] == ['Slurp fixture151'], pages
    stub.replace(cb / 'gh')
    for mode, args in (
        ('comment', ('pr', 'comment', '1', '--body', 'unpublished')),
        ('status', ('api', '-X', 'POST', f'repos/acme/proj/statuses/{head}',
                    '-f', 'context=shipcraft/review', '-f', 'state=success')),
        ('comments-read', ('api', '--paginate', '--slurp',
                           'repos/acme/proj/issues/1/comments?per_page=100')),
    ):
        stub = adapt_gh_stub(mode)
        failure = run('gh', *args)
        assert failure.returncode == 1 and 'injected failure' in failure.stderr, failure
        assert records(gh_log)[-1]['args'] == list(args)
        assert json.loads(ok('gh', 'repo', 'view', url, '--json', 'viewerPermission'))['viewerPermission'] == 'ADMIN'
        stub.replace(cb / 'gh')
elif case == 'review-control':
    fixture(review='local', clone=True)
    open_pr()
    ssh_origin()
    result, calls = observed('review', '--pr', '1')
    review_succeeded(result, calls)
    assert any('Item151' in brief for call in records(state / 'reviewer.calls.jsonl')
               for brief in call['files'].values())
elif case == 'status-control':
    fixture()
    result, calls = observed('status')
    protection_read(result, calls)
    assert 'GitHub free plan' in result.stdout, result
    pin(calls, (None, None))
else:
    raise AssertionError('unrouted ' + case)
PY151
  pass
}
