# Item 78: publish CI's bytes, using Git/gh fixtures only; no external publication.
item78_cases() {
  for c in success ordered json-pretty json-extra-fields ssh scp https-no-suffix ssh-no-suffix scp-no-suffix intel intel-query-fails \
    no-run running failed list-fails download-fails expired no-retry \
    json-text json-object json-null json-row json-id-zero json-id-negative json-id-bool json-id-float json-id-string json-status json-conclusion json-missing json-late-invalid \
    missing-arm missing-intel directory-arm directory-intel symlink-arm symlink-intel checksum-arm checksum-intel sums-missing sums-line-missing sums-extra sums-duplicate sums-uppercase sums-star sums-space sums-path sums-blank \
    version-commit version-number version-extra version-no-newline version-fails version-stderr \
    origin-local origin-other-host origin-lookalike origin-http \
    rollback uncertain package-fails sums-write-fails local-build local-rollback \
    usage-wrong usage-third; do
    echo "v1-78.$c"
  done
}
item78_case() {
  EXPECT='item 78: CI run, strict artifacts and pinned GitHub publication, offline'
  must_accept 'item 78 release black box' cmd "$PY" - "$ACEITE" "${CASE#v1-78.}" "$(command -v shipcraft)" <<'PY78'
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tarfile

aceite, scenario, binary = sys.argv[1:]
aceite = Path(aceite).resolve()
# Reuse item21's existing setup, not its verdicts: copies of the actual script,
# a real local bare origin, PATH tools and persistent call records.
scratch = Path(os.environ['TMPDIR']) / 'item78-tools'
scratch.mkdir()
helper = (aceite / 'tools/item21.py').read_text().split('\nif RELEASE:\n', 1)[0]
fake = (aceite / 'tools/item21_fake.py').read_text()
# The new fake still delegates local builds/battery/create/delete to item21.
fake = fake.replace("if name == 'git':\n", """if name == 'git':
    if args == ['remote','get-url','origin']:
        print(d['origin_url'])
        sys.exit(0)
""")
fake = fake.replace("if name == 'sysctl':\n", """if name == 'sysctl' and d.get('intel_query_fails'):
    sys.exit(1)
if name == 'sysctl' and d.get('intel'):
    print(0)
    sys.exit(0)
if name == 'sysctl':
""")
fake = fake.replace("assert name == 'gh', name\n", """assert name == 'gh', name
if args[:2] in (['run','list'], ['run','download']):
    assert option('-R') == 'github.com/equipe/shipcraft', ('repository not pinned', args)
    if args[:2] == ['run','list']:
        assert option('--workflow') == 'release-shadow.yml', args
        assert option('--branch') == 'main' and option('--event') == 'push', args
        assert option('--commit') == d['pinned'], args
        assert option('--json') == 'databaseId,status,conclusion' and option('--limit') == '20', args
        if d.get('list_fails'):
            sys.exit(81)
        print(d['run_output'])
        sys.exit(0)
    assert args[2] == str(d['chosen']), ('wrong run', args)
    assert option('-n') == 'shipcraft-darwin-'+d['pinned'], args
    dest = Path(option('-D'))
    assert dest.name == 'ci' and dest.parent.name.startswith('shipcraft-publish.'), dest
    assert dest.parent.parent.resolve() == Path(os.environ['TMPDIR']).resolve(), dest
    if d.get('download_fails'):
        sys.exit(82)
    shutil.copytree(d['artifact'], dest, dirs_exist_ok=True, symlinks=True)
    sys.exit(0)
""")
(scratch / 'item21_fake.py').write_text(fake)
(scratch / 'item21.py').write_text(helper)
sys.argv = [str(scratch / 'item21.py'), 'release-78', str(aceite.parent), binary]
namespace = {'__file__': str(scratch / 'item21.py'), '__name__': 'item78_fixture'}
exec(compile(helper, str(scratch / 'item21.py'), 'exec'), namespace)
# Keep fixture names local to this case's TMPDIR.
run = namespace['run']; git = namespace['git']; repo = namespace['repo']
state = namespace['state']; pinned = namespace['pinned']; env = namespace['env']
invoke = namespace['invoke']; data = namespace['data']; calls = namespace['calls']
refused = namespace['refused']; no_publish = namespace['no_publish']
env['GH_HOST'] = 'enterprise.invalid'
artifact = scratch / 'artifact'
artifact.mkdir()
targets = ('aarch64-apple-darwin', 'x86_64-apple-darwin')
expected = {}
for target in targets:
    path = artifact / target / 'shipcraft'
    path.parent.mkdir()
    version = 'shipcraft 1.2.10 ('+pinned[:12]+')\n'
    if scenario == 'version-commit': version = 'shipcraft 1.2.10 (ffffffffffff)\n'
    if scenario == 'version-number': version = 'shipcraft 1.2.11 ('+pinned[:12]+')\n'
    if scenario == 'version-extra': version += 'extra\n'
    if scenario == 'version-no-newline': version = version.rstrip('\n')
    # Executable payload is an OS-independent Python script. Download drops mode.
    body = ('#!'+sys.executable+'\nimport json,os,sys\n'
            'with open('+repr(str(scratch / 'versions'))+',"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n'
            'sys.stdout.write('+repr(version)+')\n')
    if scenario == 'version-stderr': body += 'sys.stderr.write("diagnostic ignored\\n")\n'
    if scenario == 'version-fails': body += 'sys.exit(7)\n'
    body += '# CI uploaded '+target+'\n'
    path.write_text(body); path.chmod(0o644)
    expected[target] = path.read_bytes()
lines = [hashlib.sha256(expected[t]).hexdigest()+'  '+t+'/shipcraft' for t in targets]
if scenario.startswith(('missing-', 'directory-', 'symlink-', 'checksum-')):
    target = targets[0 if scenario.endswith('arm') else 1]
    path = artifact / target / 'shipcraft'
    if scenario.startswith('checksum-'): path.write_bytes(b'tampered\n')
    else:
        path.unlink()
        if scenario.startswith('directory-'): path.mkdir()
        if scenario.startswith('symlink-'):
            outside = scratch / ('outside-'+target); outside.write_bytes(expected[target])
            path.symlink_to(outside)
if scenario == 'sums-line-missing': lines.pop()
if scenario == 'sums-extra': lines.append('0'*64+'  extra')
if scenario == 'sums-duplicate': lines.append(lines[0])
if scenario == 'sums-uppercase': lines[0] = lines[0][:64].upper()+lines[0][64:]
if scenario == 'sums-star': lines[0] = lines[0].replace('  ', ' *')
if scenario == 'sums-space': lines[0] = lines[0].replace('  ', ' ')
if scenario == 'sums-path': lines[0] = lines[0].replace('  ', '  ./')
if scenario == 'sums-blank': lines.append('')
if scenario != 'sums-missing': (artifact / 'SHA256SUMS').write_text('\n'.join(lines)+'\n')
row = dict(databaseId=731, status='completed', conclusion='success')
rows = [row]
if scenario == 'ordered':
    rows = [dict(databaseId=900,status='in_progress',conclusion=''),
            dict(databaseId=850,status='completed',conclusion='failure'),
            dict(databaseId=611,status='completed',conclusion='success'), row]
if scenario == 'json-extra-fields': rows = [dict(row, displayTitle='quoted \"success\"', ignored=None)]
if scenario == 'no-run': rows = []
if scenario == 'running': rows = [dict(row,status='in_progress',conclusion='')]
if scenario == 'failed': rows = [dict(row,conclusion='failure')]
if scenario == 'no-retry': rows.append(dict(row,databaseId=610))
bad = {
    'json-text': 'not JSON', 'json-object': '{}', 'json-null': 'null',
    'json-row': '[42]', 'json-id-zero': json.dumps([dict(row,databaseId=0)]),
    'json-id-negative': json.dumps([dict(row,databaseId=-1)]),
    'json-id-bool': json.dumps([dict(row,databaseId=True)]),
    'json-id-float': json.dumps([dict(row,databaseId=1.5)]),
    'json-id-string': json.dumps([dict(row,databaseId='731')]),
    'json-status': json.dumps([dict(row,status=None)]),
    'json-conclusion': json.dumps([dict(row,conclusion=False)]),
    'json-missing': '[{"databaseId":731,"status":"completed"}]',
    'json-late-invalid': json.dumps([row,dict(row,databaseId=0)])}
origin = {
    'ssh': 'ssh://git@github.com/equipe/shipcraft.git',
    'scp': 'git@github.com:equipe/shipcraft.git',
    'https-no-suffix': 'https://github.com/equipe/shipcraft',
    'ssh-no-suffix': 'ssh://git@github.com/equipe/shipcraft',
    'scp-no-suffix': 'git@github.com:equipe/shipcraft',
    'origin-local': str(namespace['remote']),
    'origin-other-host': 'https://gitlab.com/equipe/shipcraft.git',
    'origin-lookalike': 'https://github.com.evil.invalid/equipe/shipcraft.git',
    'origin-http': 'http://github.com/equipe/shipcraft.git',
}.get(scenario, 'https://github.com/equipe/shipcraft.git')
d = data()
d.update(case='release-rollback' if scenario in ('rollback','local-rollback') else
         'release-incerto' if scenario == 'uncertain' else 'release-comum',
         origin_url=origin, artifact=str(artifact), chosen=611 if scenario == 'ordered' else 731,
         run_output=bad.get(scenario,json.dumps(rows, indent=2 if scenario == 'json-pretty' else None)), list_fails=scenario == 'list-fails',
         download_fails=scenario in ('download-fails','expired','no-retry'),
         intel=scenario == 'intel', intel_query_fails=scenario == 'intel-query-fails')
state.write_text(json.dumps(d))
# Transparent real-tool probes also prove the checksum command and late-failure
# steps were reached. Only the named package/output failure is injected.
for tool in ('tar', 'shasum'):
    real = shutil.which(tool)
    wrapper = namespace['bindir'] / tool
    wrapper.write_text('#!'+sys.executable+'\nimport json,os,sys\n'
                       'with open('+repr(str(scratch / 'packaging-calls'))+',"a") as f: '
                       'f.write(json.dumps(dict(tool='+repr(tool)+',args=sys.argv[1:],cwd=os.getcwd()))+"\\n")\n'
                       + ('sys.exit(86)\n' if tool == 'tar' and scenario == 'package-fails' else
                          'if "-c" not in sys.argv: sys.exit(87)\n' if tool == 'shasum' and scenario == 'sums-write-fails' else '')
                       + 'os.execv('+repr(real)+',['+repr(real)+',*sys.argv[1:]])\n')
    wrapper.chmod(0o755)
before = git('status','--porcelain','--untracked-files=all',cwd=repo)
args = ['v1.2.10' if scenario == 'scp' else '1.2.10']
if scenario.startswith('local-'): args.append('--local-build')
if scenario == 'usage-wrong': args.append('--wrong')
if scenario == 'usage-third': args += ['--local-build','extra']
p = invoke(*args)
out = p.stdout+p.stderr
packaging_log = scratch / 'packaging-calls'
packaging = [json.loads(x) for x in packaging_log.read_text().splitlines()] if packaging_log.exists() else []
assert not list(Path(os.environ['TMPDIR']).glob('shipcraft-publish.*')), 'publish temporary folder leaked'
assert git('status','--porcelain','--untracked-files=all',cwd=repo) == before, 'wrote to caller working tree'
if scenario.startswith('usage-'):
    refused(p); assert p.returncode == 1 and 'usage:' in out, out
    no_publish(); assert not calls('cargo') and not calls('gh'), 'usage reached tools'
    sys.exit(0)
if scenario.startswith('origin-'):
    refused(p); assert p.returncode == 1 and any(w in out.lower() for w in ('origin','github','repository')), out
    no_publish(); assert not calls('gh'), 'untrusted origin reached gh'
    sys.exit(0)
if scenario.startswith('local-'):
    assert calls('cargo') and calls('bateria'), '--local-build did not reach the existing build/battery path'
    assert not [c for c in calls('gh') if c['args'][:1] == ['run']], 'fallback queried CI'
else:
    lookups = [c for c in calls('gh') if c['args'][:2] == ['run','list']]
    assert len(lookups) == 1, 'default release never looked up CI run (still built locally)'
    assert not calls('cargo') and not calls('bateria'), 'CI path built or ran battery'
    assert not any('clone' in c['args'] for c in calls('git')), 'CI path made a fresh checkout'
# Every actual gh call pins github.com even with GH_HOST set elsewhere.
for c in calls('gh'):
    a = c['args']; assert '-R' in a and a[a.index('-R')+1] == 'github.com/equipe/shipcraft', a
assert sum(c['args'] == ['remote','get-url','origin'] for c in calls('git')) == 1, 'origin not resolved exactly once'
assert 'publish.sh: v1.2.10 from commit '+pinned in out, 'start line lost'
refusal = scenario in ('no-run','running','failed','list-fails','download-fails','expired','no-retry',
                       'package-fails','sums-write-fails','rollback','uncertain','local-rollback') or scenario in bad or scenario.startswith(
                           ('missing-','directory-','symlink-','checksum-','sums-')) or scenario in (
                               'version-commit','version-number','version-extra','version-no-newline','version-fails')
downloads = [c for c in calls('gh') if c['args'][:2] == ['run','download']]
if refusal:
    refused(p); assert p.returncode == 1, p.returncode
    if scenario == 'package-fails': assert any(c['tool'] == 'tar' for c in packaging), 'did not reach failed packaging'
    if scenario == 'sums-write-fails': assert any(c['tool'] == 'shasum' and '-c' not in c['args'] for c in packaging), 'did not reach failed archive checksum write'
    if scenario in ('rollback','uncertain','local-rollback'):
        assert any(c['args'][:2] == ['release','create'] for c in calls('gh')), 'did not reach create failure'
        assert bool(data()['deleted']) == (scenario != 'uncertain'), 'wrong ownership rollback'
        if scenario == 'uncertain': assert all(w in out for w in ('gh release view','git ls-remote')), out
    else:
        no_publish()
    if scenario in ('no-run','running','failed'):
        assert 'no successful release-shadow run for '+pinned in out, out
        assert all(w in out.split('Next:')[-1] for w in ('push','gh run rerun','--local-build')), out
        assert not downloads, 'download despite no successful run'
    elif scenario == 'list-fails': assert 'could not list the release-shadow runs' in out, out
    elif scenario.startswith('json-'): assert 'unreadable' in out.lower(), out
    elif scenario not in ('package-fails','sums-write-fails','rollback','uncertain','local-rollback'):
        assert len(downloads) == 1 and '731' in out, 'artifact/version refusal must name chosen run; no retry'
else:
    assert p.returncode == 0, 'valid CI/fallback publication refused: '+out
    assets = {Path(a).name:Path(a) for a in data()['assets']}
    names = ['shipcraft-1.2.10-'+t+'.tar.gz' for t in targets]
    assert set(assets) == set(names+['SHA256SUMS']), assets
    sums = assets['SHA256SUMS'].read_text().splitlines()
    assert len(sums) == 2, sums
    for target, name in zip(targets,names):
        with tarfile.open(assets[name]) as tf:
            members = tf.getmembers()
            assert len(members) == 1 and members[0].name in ('shipcraft','./shipcraft') and members[0].isfile(), members
            assert members[0].mode & 0o777 == 0o755, 'mode not normalized to 755'
            if scenario != 'local-build': assert tf.extractfile(members[0]).read() == expected[target], 'published rebuilt or wrong bytes'
        assert any(re.fullmatch(hashlib.sha256(assets[name].read_bytes()).hexdigest()+r' [ *](?:\./)?'+re.escape(name), line) for line in sums), 'wrong archive checksum'
    assert data()['target_commitish'] == pinned, 'release target was not pinned'
    assert 'publish.sh: v1.2.10 published at commit '+pinned+': https://' in out, 'final line lost'
    notes = data()['notes'].lower()
    if scenario != 'local-build':
        assert len(downloads) == 1, 'artifact not selected once'
        checks = [c for c in packaging if c['tool'] == 'shasum' and c['args'] == ['-a','256','-c','SHA256SUMS']]
        assert len(checks) == 1 and Path(checks[0]['cwd']).name == 'ci', 'artifact not checked with shasum -a 256 -c in CI folder'
        assert all(w in notes for w in ('release-shadow',str(d['chosen']),'green','5','macos','arm64','x86_64')), notes
        assert any(w in notes for w in ('only built','apenas','somente')), notes
        probes = scratch / 'versions'
        if scenario in ('intel','intel-query-fails'):
            assert not probes.exists(), 'Intel ran arm64 version executable'
            assert any(w in notes for w in ('skip','not checked','not run')), 'Intel skip absent from notes'
        else:
            assert probes.exists() and probes.read_text().splitlines() == ['["--version"]'], 'arm64 version not checked exactly once'
PY78
  pass
}
