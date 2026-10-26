#!/usr/bin/env python3
"""Protocolos offline: gh CLI (URL/JSON), cargo build e sysctl do macOS."""
import json
import fcntl
import os
from pathlib import Path
import shutil
import subprocess
import sys

name, *args = sys.argv[1:]
state = Path(os.environ['I21_STATE'])
lock = open(str(state)+'.lock','w')
fcntl.flock(lock, fcntl.LOCK_EX)
d = json.loads(state.read_text())
case = d['case']
real_git = os.environ['I21_GIT']


def git(*a, cwd=None):
    return subprocess.check_output([real_git,*a], cwd=cwd, text=True).strip()


def save():
    state.write_text(json.dumps(d))


def option(*names, default=None):
    for i,a in enumerate(args):
        if a in names and i+1 < len(args):
            return args[i+1]
        for n in names:
            if a.startswith(n+'='):
                return a[len(n)+1:]
    return default


entry = dict(tool=name, args=args, cwd=os.getcwd())
d['calls'].append(entry)
save()
if name in ('brew','npm') or (name == 'cargo' and any(x in args for x in ('publish','install'))):
    sys.exit('publicação proibida no item21')
if name == 'mv':
    if d.get('installed') and args and Path(args[-1]).absolute() == Path(d['installed']).absolute():
        assert Path(d['installed']).exists(), 'apagou anterior antes da renomeação'
    os.execv(os.environ['I21_MV'], [os.environ['I21_MV'], *args])
if name == 'git':
    if 'ls-remote' in args:
        if case == 'release-remoto' or (case == 'release-tags-falha' and '--tags' in args):
            sys.exit(71)
        p = subprocess.run([real_git,*args], capture_output=True)
        sys.stdout.buffer.write(p.stdout); sys.stderr.buffer.write(p.stderr)
        sys.exit(p.returncode)
    if any(a.startswith(('https:','ssh:','git@','git://')) for a in args):
        sys.exit('remoto externo proibido no item21')
    if 'push' in args:
        # Somente o bare local, mesmo se o script tentar passar outra URL.
        assert all('github.com' not in a and not a.startswith(('https:','ssh:','git@')) for a in args)
    os.execv(real_git,[real_git,*args])
if name == 'sysctl':
    assert args == ['-n','hw.optional.arm64'], args
    print(0 if case in ('instala-intel','release-prefixo') else 1)
    sys.exit(0)
if name == 'uname':
    if '-m' in args or '-p' in args:
        print('x86_64' if case in ('instala-intel','instala-rosetta','release-prefixo') else 'arm64')
    else:
        print('Linux' if case == 'instala-linux' else 'Darwin')
    sys.exit(0)
if name == 'cargo':
    assert 'build' in args, args
    target = option('--target')
    assert target in ('aarch64-apple-darwin','x86_64-apple-darwin'), args
    if case == 'release-preso' and not d.get('moved'):
        (Path(d['repo']) / 'sentinela').write_text('mudou\n')
        subprocess.run([real_git,'add','sentinela'], cwd=d['repo'], check=True)
        subprocess.run([real_git,'commit','-qm','concorrente'], cwd=d['repo'], check=True)
        d['moved'] = True
    entry.update(target=target, head=git('rev-parse','HEAD'),
                 sentinela=(Path(git('rev-parse','--show-toplevel')) / 'sentinela').read_text())
    save()
    if case == 'release-build':
        sys.exit(72)
    dest = Path(os.environ.get('CARGO_TARGET_DIR','target')) / target / ('release' if '--release' in args else 'debug') / 'shipcraft'
    if not dest.is_absolute():
        # cargo --manifest-path nucleo/Cargo.toml usa target no núcleo.
        manifest = option('--manifest-path')
        dest = (Path(manifest).parent if manifest else Path('.')) / dest
    dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text('#!/bin/sh\necho "shipcraft 1.2.10 ('+d['pinned'][:12]+')"\n')
    dest.chmod(0o755)
    sys.exit(0)
if name == 'bateria':
    assert len(args) == 2 and args[-1] == 'all', args
    binary = Path(args[0]).resolve()
    assert binary.is_file(), binary
    entry.update(binary=str(binary), head=git('rev-parse','HEAD'))
    save()
    sys.exit(73 if case == 'release-bateria' else 0)
assert name == 'gh', name
if args[:2] == ['auth','status']:
    sys.exit(0)
if args[:2] == ['release','view']:
    tag = next((x for x in args[2:] if x.startswith('v1.')), None)
    if not tag:
        d['views'] = d.get('views',0)+1; save()
    version = tag or ('v1.2.10' if d['views'] == 1 else 'v9.9.9')
    if '--jq' in args or '-q' in args:
        print(version)
    else:
        print(json.dumps(dict(tagName=version,id=321,databaseId=321,url='https://github.com/victorassisalves/shipcraft/releases/tag/'+version)))
    sys.exit(0)
if args[:2] == ['release','download']:
    assert 'v1.2.10' in args, 'download sem tag fixada'
    dest = Path(option('--dir','-D',default='.')); dest.mkdir(parents=True,exist_ok=True)
    patterns = [args[i+1] for i,a in enumerate(args[:-1]) if a in ('--pattern','-p')]
    assert patterns, 'download deve selecionar assets'
    import fnmatch
    for p in Path(d['downloads']).iterdir():
        if any(fnmatch.fnmatch(p.name, pattern) for pattern in patterns):
            shutil.copyfile(p,dest/p.name)
    sys.exit(0)
if args[:2] == ['release','create']:
    d['create_args'] = args
    d['target_commitish'] = option('--target')
    notes = option('--notes','-n',default='')
    notesfile = option('--notes-file','-F')
    if notesfile:
        notes += Path(notesfile).read_text()
    d['notes'] = notes
    # Copia antes da limpeza do produto para os asserts do pai.
    kept = state.parent / 'publicados'; kept.mkdir(exist_ok=True)
    for a in args:
        p = Path(a.split('#')[0])
        if p.is_file() and (p.name.endswith('.tar.gz') or p.name == 'SHA256SUMS'):
            out = kept / p.name; shutil.copyfile(p,out); d['assets'].append(str(out))
    save()
    if case == 'release-incerto':
        print('conexão perdida',file=sys.stderr); sys.exit(74)
    print('https://github.com/victorassisalves/shipcraft/releases/tag/v1.2.10')
    if case == 'release-rollback':
        print('falha depois de receber identificação',file=sys.stderr); sys.exit(75)
    sys.exit(0)
if args[:2] == ['release','delete']:
    d['deleted'].append(' '.join(args)); save(); sys.exit(0)
if args[:2] == ['release','upload']:
    sys.exit(75 if case == 'release-rollback' else 0)
if args and args[0] == 'api':
    endpoint = next((x for x in args[1:] if x.startswith(('repos/','/repos/'))), '')
    if option('--method','-X') == 'DELETE':
        d['deleted'].append(endpoint); save(); sys.exit(0)
    if endpoint.endswith('/releases/tags/v1.2.10'):
        print(json.dumps(dict(id=321,tag_name='v1.2.10'))); sys.exit(0)
sys.exit('chamada não simulada: '+repr(args))
