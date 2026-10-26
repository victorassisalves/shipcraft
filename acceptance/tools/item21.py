#!/usr/bin/env python3
"""Contrato 21: scripts copiados para Git local; nenhuma ferramenta publica de verdade."""
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

CASE, SOURCE, BINARY = sys.argv[1:]
SOURCE = Path(SOURCE).resolve()
ROOT = Path(os.environ['TMPDIR']) / 'item21'
ROOT.mkdir()
REAL_GIT = shutil.which('git')
PYTHON = sys.executable


def run(*args, cwd=None, ok=True, env=None):
    p = subprocess.run([str(a) for a in args], cwd=cwd, env=env, text=True,
                       capture_output=True, timeout=90)
    print('$', shlex.join(map(str, args)), '\n', p.stdout, p.stderr, flush=True)
    if ok:
        assert p.returncode == 0, f'{args}: saída {p.returncode}'
    return p


def git(*args, cwd=None):
    return run(REAL_GIT, *args, cwd=cwd).stdout.strip()


def executable(path, body):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body)
    path.chmod(0o755)


def refused(p, prefixes=('shipcraft refused:', 'Why:', 'Next:')):
    assert p.returncode != 0, 'deveria recusar'
    lines = [x for x in (p.stdout + p.stderr).splitlines() if x.strip()][-3:]
    assert len(lines) == 3 and all(line.startswith(prefix) for line, prefix in zip(lines, prefixes)), lines


def version():
    p = run(BINARY, '--version', cwd=ROOT)
    m = re.fullmatch(r'shipcraft (\d+\.\d+\.\d+) \(([0-9a-f]{12}|no-git)\)\n', p.stdout)
    assert m and not p.stderr, 'uma linha de versão, sem projeto'
    return tuple(map(int, m[1].split('.')))


if CASE == 'versao-fora':
    version()
    # Uma pasta com configuração inválida também não governa --version.
    (ROOT / '.shipcraft.toml').write_text('isto não é TOML [')
    version()
    sys.exit(0)
if CASE == 'versao-min-numerica':
    try:
        import tomllib as toml
    except ImportError:
        import tomli as toml
    with (SOURCE / 'nucleo/Cargo.toml').open('rb') as manifest:
        expected = toml.load(manifest)['package']['version']
    assert re.fullmatch(r'\d+\.\d+\.\d+', expected), 'package.version deve ser X.Y.Z'
    v = tuple(map(int, expected.split('.')))
    assert version() == v, '--version deve corresponder a package.version'
    git('init', '-q', '-b', 'main', cwd=ROOT)
    git('config', 'user.name', 'Aceite', cwd=ROOT)
    git('config', 'user.email', 'aceite@example.invalid', cwd=ROOT)
    (ROOT / 'pyproject.toml').write_text('[project]\nname="exemplo"\nversion="0.0.1"\n')
    (ROOT / 'tests').mkdir()
    (ROOT / 'tests/test_ok.py').write_text('def test_ok():\n    assert True\n')
    git('add', '.', cwd=ROOT); git('commit', '-qm', 'base', cwd=ROOT)
    run(BINARY, 'init', '--lang', 'python', cwd=ROOT, env=dict(os.environ, SHIPCRAFT_REVISOR='nenhum'))
    cfg = ROOT / '.shipcraft.toml'
    original = cfg.read_text()
    # 10 é maior que 9, embora seja menor em ordem lexicográfica.
    minima = [(v, True), ((v[0], v[1], v[2]+10), False), ((v[0], v[1]+10, 0), False), ((v[0]+10, 0, 0), False)]
    if v[0] > 0:
        minima.append(((v[0]-1, 99, 99), True))
    minima.append((tuple(f'0{n}' for n in v), True))
    for minimum, accepted in minima:
        text = '.'.join(map(str, minimum))
        configured, count = re.subn(r'shipcraft_min\s*=\s*"[^"]*"', f'shipcraft_min = "{text}"', original)
        if count == 0:
            configured = f'shipcraft_min = "{text}"\n' + original
        cfg.write_text(configured)
        git('add', '.shipcraft.toml', cwd=ROOT)
        p = run(BINARY, 'check', cwd=ROOT, ok=False)
        if accepted:
            assert p.returncode == 0, f'mínimo {text} recusado por versão {v}'
        else:
            refused(p, ('shipcraft refused:', 'Why:', 'Next:'))
            assert text in p.stdout+p.stderr, 'mínimo ausente da recusa'
    sys.exit(0)

RELEASE = CASE.startswith('release-')
script_name = 'release/publish.sh' if RELEASE else 'install.sh'
script = SOURCE / script_name
assert script.is_file(), f'item 21 ausente na base: {script_name}'
repo = ROOT / 'repo local'
repo.mkdir()
git('init', '-q', '-b', 'main', cwd=repo)
git('config', 'user.name', 'Aceite', cwd=repo)
git('config', 'user.email', 'aceite@example.invalid', cwd=repo)
(repo / script_name).parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(script, repo / script_name)
(repo / 'nucleo').mkdir()
(repo / 'nucleo/Cargo.toml').write_text('[package]\nname="shipcraft"\nversion="1.2.10"\nedition="2021"\n')
(repo / 'sentinela').write_text('preso\n')
# O runner externo é simulado no limite do script, não seus testes internos.
executable(repo / 'acceptance/run.sh', '#!/bin/sh\nexec "$I21_PY" "$I21_DRIVER" bateria "$@"\n')
git('add', '.', cwd=repo); git('commit', '-qm', 'fixture local', cwd=repo)
pinned = git('rev-parse', 'HEAD', cwd=repo)
remote = ROOT / 'remoto.git'
git('init', '-q', '--bare', remote)
git('remote', 'add', 'origin', remote, cwd=repo)
git('push', '-q', 'origin', 'main', cwd=repo)
state = ROOT / 'estado.json'
state.write_text(json.dumps(dict(case=CASE, repo=str(repo), pinned=pinned, calls=[], assets=[], deleted=[])))
bindir = ROOT / 'ferramentas'
bindir.mkdir()
driver = Path(__file__).with_name('item21_fake.py').resolve()
for name in ('gh', 'git', 'cargo', 'sysctl', 'uname', 'brew', 'npm', 'mv'):
    executable(bindir / name, '#!' + PYTHON + '\nimport runpy,sys\nsys.argv.insert(1,' + repr(name) + ')\nrunpy.run_path(' + repr(str(driver)) + ',run_name="__main__")\n')
# Proíbe também rede por curl/wget; downloads só pelo gh simulado.
for name in ('curl', 'wget'):
    executable(bindir / name, '#!/bin/sh\necho "rede proibida no item21" >&2\nexit 97\n')
env = dict(os.environ, PATH=str(bindir)+os.pathsep+os.environ['PATH'],
           I21_STATE=str(state), I21_GIT=REAL_GIT, I21_MV=shutil.which('mv'), I21_PY=PYTHON, I21_DRIVER=str(driver),
           SHIPCRAFT_ACCEPTANCE_REUSE='0', CARGO_BUILD_JOBS='4')
env.pop('SHIPCRAFT_REPO', None)


def data():
    return json.loads(state.read_text())


def calls(name):
    return [c for c in data()['calls'] if c['tool'] == name]


def invoke(*args):
    # Deliberadamente fora do repositório para instalar; release só na fixture.
    return run('bash', repo / script_name, *args, cwd=repo if RELEASE else ROOT,
               env=env, ok=False)


def no_publish():
    assert not any(c['args'][:2] == ['release', 'create'] or
                   (c['tool'] == 'gh' and any(x in c['args'] for x in ('POST','PATCH'))) for c in calls('gh')), 'publicou apesar da recusa'
    assert not any('push' in c['args'] for c in calls('git')), 'push apesar da recusa'


if RELEASE:
    arg = 'v1.2.10' if CASE == 'release-prefixo' else '1.2.10'
    if CASE == 'release-formato':
        arg = '1.2.10-rc1'
    if CASE == 'release-suja':
        (repo / 'solto').write_text('sujo')
    if CASE == 'release-versao':
        arg = '1.2.9'
    if CASE == 'release-head':
        git('commit', '--allow-empty', '-qm', 'só local', cwd=repo)
    if CASE == 'release-tag':
        git('tag', 'v1.2.10', cwd=repo); git('push', '-q', 'origin', 'v1.2.10', cwd=repo)
    if CASE == 'release-formato':
        for invalid in ('1.2', '1.2.10-rc1', 'v1.2.10.0', 'vv1.2.10', '1.x.10'):
            refused(invoke(invalid)); no_publish()
        sys.exit(0)
    p = invoke(arg)
    negative = CASE in ('release-formato','release-suja','release-versao','release-head','release-tag','release-remoto','release-tags-falha','release-bateria','release-build')
    if negative:
        refused(p); no_publish()
        if CASE in ('release-bateria', 'release-build'):
            assert calls('cargo'), 'não chegou ao build controlado'
        if CASE == 'release-bateria':
            assert calls('bateria'), 'não chegou à bateria vermelha'
    elif CASE in ('release-rollback','release-incerto'):
        refused(p)
        creates = [c for c in calls('gh') if c['args'][:2] == ['release','create']]
        assert creates, 'não tentou criar release'
        deletes = data()['deleted']
        if CASE == 'release-incerto':
            assert not deletes, 'apagou recurso sem confirmação de autoria'
            assert any(w in (p.stdout+p.stderr).lower() for w in ('confer','verifi','check')), 'falta orientação para conferir'
        else:
            assert deletes and all('v1.2.10' in x or '321' in x for x in deletes), 'rollback deve apagar apenas release própria'
    else:
        assert p.returncode == 0, 'release comum deve funcionar offline'
        d = data()
        remote_calls = [c['args'] for c in calls('git') if 'ls-remote' in c['args']]
        assert any('main' in a and 'origin' in a for a in remote_calls), 'não consultou main do remoto'
        assert any('--tags' in a for a in remote_calls), 'não consultou tags remotas'
        builds = calls('cargo')
        assert {c.get('target') for c in builds} >= {'aarch64-apple-darwin','x86_64-apple-darwin'}, 'faltou alvo'
        assert all(c['head'] == pinned and c['cwd'] != str(repo) and c['sentinela'] == 'preso\n' for c in builds), 'build não usou checkout novo preso'
        tests = calls('bateria')
        assert len(tests) == 1 and tests[0]['args'][-1] == 'all', 'bateria inteira exatamente uma vez'
        host = 'x86_64' if CASE == 'release-prefixo' else 'aarch64'
        other = 'aarch64' if host == 'x86_64' else 'x86_64'
        assert host+'-apple-darwin' in tests[0]['binary'], 'bateria usou outro alvo'
        assert tests[0]['head'] == pinned and tests[0]['cwd'] != str(repo), 'bateria fora do checkout preso'
        assets = {Path(a).name: Path(a) for a in d['assets']}
        packages = [f'shipcraft-1.2.10-{t}-apple-darwin.tar.gz' for t in ('aarch64','x86_64')]
        assert set(assets) == set(packages+['SHA256SUMS']), assets
        sums = assets['SHA256SUMS'].read_text().splitlines()
        assert len(sums) == 2
        for name in packages:
            with tarfile.open(assets[name]) as tf:
                members = tf.getmembers()
                assert len(members) == 1 and members[0].name in ('shipcraft','./shipcraft') and members[0].isfile() and members[0].mode & 0o111, 'pacote deve ter só shipcraft executável na raiz'
            assert any(re.fullmatch(hashlib.sha256(assets[name].read_bytes()).hexdigest()+r' [ *](?:\./)?'+re.escape(name), line) for line in sums), 'soma por pacote incorreta'
        tag = run(REAL_GIT, '--git-dir='+str(remote), 'rev-parse', '--verify', 'refs/tags/v1.2.10^{}', ok=False)
        if tag.returncode == 0:
            assert tag.stdout.strip() == pinned, 'tag remota não aponta ao commit preso'
        else:
            assert d.get('target_commitish') == pinned, 'criação da tag não fixa o commit preso'
        notes = d.get('notes','').lower()
        assert other in notes and any(w in notes for w in ('não','nao','not','apenas','somente')), 'limite do alvo não testado ausente'
    sys.exit(0)

# Pacotes reais; conteúdo executável falso declara versão para conferir a instalação.
assets = ROOT / 'downloads'
assets.mkdir()
installed = ROOT / 'bin instalado' / 'shipcraft'
installed.parent.mkdir()
old = b'#!/bin/sh\necho "shipcraft 0.9.0 (aaaaaaaaaaaa)"\n'
installed.write_bytes(old); installed.chmod(0o755)
expected_version = '1.2.9' if CASE == 'instala-version' else '1.2.10'
new = ('#!' + PYTHON + '\nimport os,json,sys\nfrom pathlib import Path\n'
       'p=Path(os.environ["I21_INSTALLED"])\n'
       'with open(os.environ["I21_PROBE"],"a") as f: f.write(json.dumps(dict(args=sys.argv[1:],inode=p.stat().st_ino))+"\\n")\n'
       'print("shipcraft ' + expected_version + ' (bbbbbbbbbbbb)")\n').encode()
for target in ('aarch64','x86_64'):
    name = f'shipcraft-1.2.10-{target}-apple-darwin.tar.gz'
    with tarfile.open(assets / name, 'w:gz') as tf:
        member = tarfile.TarInfo('sub/shipcraft' if CASE == 'instala-aninhado' else 'shipcraft')
        member.size = len(new); member.mode = 0o644 if CASE == 'instala-modo' else 0o755
        tf.addfile(member, io.BytesIO(new))
        if CASE == 'instala-extra':
            extra = tarfile.TarInfo('surpresa'); extra.size = 1
            tf.addfile(extra, io.BytesIO(b'x'))
lines = [hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name for p in sorted(assets.glob('*.gz'))]
# Uma soma errada do OUTRO pacote não deve impedir instalar o escolhido.
if CASE == 'instala-comum':
    lines = [('0'*64+'  '+line.split('  ')[1]) if 'x86_64' in line else line for line in lines]
if CASE == 'instala-soma':
    lines = ['0'*64+'  '+line.split('  ')[1] for line in lines]
if CASE == 'instala-linha':
    lines = [line for line in lines if 'x86_64' in line]
if CASE == 'instala-duplicada':
    lines += [line for line in lines if 'aarch64' in line]
(assets / 'SHA256SUMS').write_text('\n'.join(lines)+'\n')
if CASE == 'instala-extracao':
    package = assets / 'shipcraft-1.2.10-aarch64-apple-darwin.tar.gz'
    package.write_bytes('não é tar'.encode())
    (assets / 'SHA256SUMS').write_text(hashlib.sha256(package.read_bytes()).hexdigest()+'  '+package.name+'\n')
if CASE in ('instala-igual','instala-local'):
    installed.write_bytes(new if CASE == 'instala-igual' else new+'# compilação local\n'.encode())
if CASE == 'instala-destino':
    installed.unlink(); installed.mkdir(); (installed / 'preservar').write_bytes(old)
if CASE == 'instala-path':
    executable(bindir / 'shipcraft', '#!/bin/sh\necho "outro shipcraft"\n')
env['SHIPCRAFT_BIN'] = str(installed.parent)
env['I21_INSTALLED'] = str(installed)
env['I21_PROBE'] = str(ROOT / 'version-probe')
if CASE == 'instala-repo':
    env['SHIPCRAFT_REPO'] = 'equipe/privado'
d = data(); d['downloads'] = str(assets); d['installed'] = str(installed); state.write_text(json.dumps(d))
before = installed.stat()
if CASE == 'instala-permissao':
    installed.parent.chmod(0o500)
    assert not os.access(installed.parent, os.W_OK), 'fixture requer usuário sem privilégio de escrita'
p = invoke(*(['--uninstall'] if CASE == 'remove' else ['--version','v1.2.10'] if CASE == 'instala-versao' else []))
if CASE == 'instala-permissao':
    installed.parent.chmod(0o700)
if CASE == 'remove':
    assert p.returncode == 0 and not installed.exists(), 'remoção falhou'
    assert (installed.parent).is_dir() and (assets / 'SHA256SUMS').exists(), 'removeu algo além do binário'
    lines = [s for s in (p.stdout+p.stderr).splitlines() if s.strip()]
    assert len(lines) == 1 and 'project' in lines[0].lower() and 'commit' in lines[0].lower(), 'aviso aos projetos ausente'
    assert not calls('gh'), 'remoção dependeu de GitHub'
elif CASE in ('instala-linux','instala-soma','instala-linha','instala-duplicada','instala-extra','instala-aninhado','instala-modo','instala-version','instala-extracao','instala-destino','instala-permissao'):
    refused(p)
    if installed.is_file():
        assert installed.read_bytes() == old and installed.stat().st_ino == before.st_ino, 'falha perdeu binário anterior'
    else:
        assert (installed / 'preservar').read_bytes() == old, 'falha alterou destino existente'
    if CASE == 'instala-linux':
        assert 'cargo install --path nucleo' in p.stdout+p.stderr
else:
    assert p.returncode == 0, 'instalação deve funcionar offline'
    assert installed.read_bytes() == new, 'não instalou binário esperado'
    assert os.access(installed, os.X_OK), 'binário não executável'
    requests = calls('gh')
    wanted_repo = env.get('SHIPCRAFT_REPO','victorassisalves/shipcraft')
    assert requests and all(wanted_repo in ' '.join(c['args']) for c in requests), 'repositório não ficou fixo'
    downloads = [c for c in requests if c['args'][:2] == ['release','download']]
    assert downloads and all('v1.2.10' in c['args'] for c in downloads), 'downloads não presos à versão resolvida'
    assert all('latest' not in c['args'] for c in downloads)
    views = [c for c in requests if c['args'][:2] == ['release','view'] and not any(x.startswith('v1.') for x in c['args'])]
    assert len(views) <= 1, 'resolveu última versão mais de uma vez'
    wanted = 'x86_64' if CASE == 'instala-intel' else 'aarch64'
    patterns = ' '.join(' '.join(c['args']) for c in downloads)
    assert wanted in patterns, 'alvo não veio do hardware'
    if CASE == 'instala-igual':
        after = installed.stat()
        assert (after.st_ino,after.st_mtime_ns) == (before.st_ino,before.st_mtime_ns), 'mesma versão/soma foi substituída'
        assert 'already' in (p.stdout+p.stderr).lower(), 'did not announce already installed'
    else:
        assert installed.stat().st_ino != before.st_ino, 'troca não foi por rename de arquivo novo'
        probes = [json.loads(x) for x in (ROOT / 'version-probe').read_text().splitlines()]
        assert any(x['args'] == ['--version'] and x['inode'] == before.st_ino for x in probes), '--version não foi conferido antes da troca'
    if CASE == 'instala-path':
        assert str(bindir / 'shipcraft') in p.stdout+p.stderr and str(installed.parent) in p.stdout+p.stderr, 'falta aviso do PATH e como corrigir'
# ROOT contém fixtures persistentes; só temporários criados pelo script devem sumir.
leftovers = [p for p in Path(os.environ['TMPDIR']).iterdir() if p != ROOT]
assert not leftovers, f'temporários vazaram: {leftovers}'
