#!/usr/bin/env python3
"""Item 17, caixa-preta. Marcas sempre produzidas pelo shipcraft, nunca fabricadas."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
from lefthook_fixture import HOOK


def run(*args, ok=True, env=None):
    p = subprocess.run(args, capture_output=True, text=True, timeout=90, env=env)
    print('$', shlex.join(args), '\n', p.stdout, p.stderr, flush=True)
    if ok:
        assert p.returncode == 0, f'{args}: saida {p.returncode}'
    return p


def git(*args):
    return run('git', *args).stdout.strip()


def path(*args):
    return Path(git('rev-parse', '--git-path', *args))


def head():
    return git('rev-parse', 'HEAD')


def blob(ref, name):
    return subprocess.check_output(['git', 'show', f'{ref}:{name}'])


def state(data):
    d = json.loads(data)
    return next((d[k] for k in ('state', 'status', 'estado') if k in d), '?')


def states(ref='HEAD'):
    return [state(blob(ref, f)) for f in locks]


def mark():
    return path('shipcraft/close')


def green():
    Path('textutil.py').write_text('def slugify(text):\n    return "ola-mundo" if "Ol" in text else "a-b"\n')
    git('add', 'textutil.py')


def judge(ok=True):
    # Caminho com espacos, que nao precisa existir: argumento deve ser ignorado.
    before = metrics()
    p = run('shipcraft', 'check', '--commit-msg', 'mensagem com espacos.txt', ok=ok)
    if p.returncode == 0:
        after = metrics()
        assert after.startswith(before), 'julgamento reescreveu metricas'
        rows = [json.loads(line) for line in after[len(before):].splitlines() if line.strip()]
        assert len(rows) == 1 and rows[0]['layer'] == 'hook', 'julgamento nao registrou exatamente um hook'
    return p


def metrics():
    f = Path(git('rev-parse', '--git-common-dir')) / 'shipcraft/runs.jsonl'
    return f.read_bytes() if f.exists() else b''


def close():
    before = metrics()
    p = run('shipcraft', 'close')
    assert metrics() == before, 'fecha escreveu runs.jsonl'
    return p.stdout + p.stderr


def commit(*args):
    git('commit', '-qm', 'feat: usuario', *args)
    return head()


def closes(user):
    assert head() != user, 'fecha nao criou commit'
    assert git('rev-parse', 'HEAD^') == user, 'fechamento nao e filho do commit julgado'
    assert states() == ['closed'] * len(locks), 'travas nao fecharam'
    assert states('HEAD^') == ['open'] * len(locks), 'commit do usuario ja alterou trava'
    changed = git('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD').splitlines()
    assert sorted(changed) == sorted(locks), 'fechamento levou algo alem das travas'
    msg = git('log', '-1', '--format=%s')
    assert msg.startswith('shipcraft: close lock '), msg
    assert sorted(x.strip() for x in msg.removeprefix('shipcraft: close lock ').split(',')) == sorted(Path(f).stem for f in locks)
    assert not mark().exists(), 'marca nao removida'


def install():
    # Mesmo template do 15b, renderizado para os dois eventos novos.
    for event in ('commit-msg', 'post-commit'):
        p = path('hooks/' + event)
        p.write_text(HOOK.replace('run "pre-commit"', f'run "{event}"'))
        p.chmod(0o755)
    # Executor offline: somente despacho dos dois comandos, sem simular parallel.
    exe = Path(os.environ['TMPDIR']) / 'item17-lefthook'
    exe.write_text('#!/bin/sh\nif [ -n "$ITEM17_PROBE" ]; then touch "$ITEM17_PROBE"; exit 99; fi\n[ "$1" = run ] || exit 91\nshift\nevent="$1"; shift\ncase "$event" in\ncommit-msg) exec shipcraft check --commit-msg "$@";;\npost-commit) exec shipcraft close;;\n*) exit 92;;\nesac\n')
    exe.chmod(0o755)
    os.environ['LEFTHOOK_BIN'] = str(exe)


def setup(unborn=False):
    p = path('hooks/pre-commit')
    if p.exists():
        p.unlink()
    Path('lefthook.yml').write_text('pre-commit:\n  parallel: true\n  commands:\n    lint:\n      run: echo lint\ncommit-msg:\n  commands:\n    shipcraft:\n      run: shipcraft check --commit-msg {1}\npost-commit:\n  commands:\n    shipcraft:\n      run: shipcraft close\n')
    # Os casos de nascimento usam Git novo, sem refs, objetos ou reflog antigos.
    if unborn:
        assert Path('.git').is_dir(), 'fixture precisa de repositorio proprio'
        shutil.rmtree('.git')
        git('init', '-q', '-b', 'main')
    # Testes/config entram antes do RED, mas produto segue stub.
    git('add', '-A')
    if not unborn:
        commit()
    run('shipcraft', 'red')
    git('add', '-A')
    if not unborn:
        run('shipcraft', 'check')
        git('add', '-A')
        commit()
    names = git('ls-files', '.shipcraft/locks/*.json').splitlines()
    if not names:
        names = [str(p) for p in Path('.shipcraft').rglob('*.json') if state(p.read_bytes()) == 'open']
    assert len(names) == 1, f'fixture sem trava unica: {names}'
    install()
    os.environ['LEFTHOOK'] = '0'
    return names


def signed_cycle(case):
    assert shutil.which('ssh-keygen'), 'fixture requer ssh-keygen para assinatura SSH real'
    # Chaves descartaveis ficam fora do repositorio e somem com o TMPDIR do caso.
    key = Path(os.environ['TMPDIR']) / 'chave ssh item17'
    run('ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(key))
    allowed = key.parent / 'assinantes permitidos'
    allowed.write_text('* ' + Path(str(key) + '.pub').read_text())
    git('config', 'gpg.format', 'ssh')
    git('config', 'gpg.ssh.allowedSignersFile', str(allowed))
    # Evita que a maquina de quem roda forneca configuracao ao controle.
    for name in list(os.environ):
        if name.startswith(('GIT_CONFIG_KEY_', 'GIT_CONFIG_VALUE_')) or name in ('GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS'):
            del os.environ[name]
    if case == 'assinatura-ssh-env-2':
        os.environ.update(GIT_CONFIG_COUNT='2', GIT_CONFIG_KEY_0='user.signingkey',
                          GIT_CONFIG_VALUE_0=str(key), GIT_CONFIG_KEY_1='commit.gpgsign',
                          GIT_CONFIG_VALUE_1='true')
    else:
        git('config', 'user.signingkey', str(key))
        if case == 'assinatura-ssh-env-1':
            os.environ.update(GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='commit.gpgsign',
                              GIT_CONFIG_VALUE_0='true')
        else:
            git('config', 'commit.gpgsign', 'true')
    assert git('config', '--type=bool', 'commit.gpgsign') == 'true'
    assert git('config', 'user.signingkey') == str(key)
    os.environ['LEFTHOOK'] = '1'
    parent = head()
    before = metrics()
    commit()
    user = git('rev-parse', 'HEAD^')
    assert git('rev-parse', user + '^') == parent, 'GREEN/fechamento nao formam dois commits'
    closes(user)
    for ref in (user, 'HEAD'):
        raw = subprocess.check_output(['git', 'cat-file', 'commit', ref])
        assert b'\ngpgsig -----BEGIN SSH SIGNATURE-----' in raw, f'{ref}: commit sem assinatura SSH (GREEN deve assinar e filho deve preservar configuracao)'
        run('git', 'verify-commit', ref)
    after = metrics()
    assert after.startswith(before)
    rows = [json.loads(line) for line in after[len(before):].splitlines() if line.strip()]
    assert len(rows) == 1 and rows[0]['layer'] == 'hook', 'post-commit acrescentou metrica'


def main(case):
    global locks
    unborn = case in ('primeiro-commit-verde-recusa', 'primeiro-red-green-fecha')
    locks = setup(unborn=unborn)
    if unborn:
        assert run('git', 'rev-parse', '--verify', 'HEAD', ok=False).returncode != 0
        assert [state(Path(f).read_bytes()) for f in locks] == ['open']
        assert not mark().exists()
        if case == 'primeiro-commit-verde-recusa':
            green()
            control = run('shipcraft', 'check', ok=False)
            assert control.returncode != 0, 'controle shipcraft check aceitou RED ja verde'
            tail = lambda p: [s for s in (p.stdout+p.stderr).splitlines() if s.strip()][-3:]
            expected = tail(control)
            assert len(expected) == 3 and expected[0].startswith('shipcraft refused:') and expected[1].startswith('Why:') and expected[2].startswith('Next:'), expected
            assert json.loads(metrics().splitlines()[-1])['code'] == 'red-already-passes'
            p = judge(ok=False)
            assert p.returncode != 0 and tail(p) == expected, 'commit-msg divergiu da recusa red-ja-passa de shipcraft check'
            assert json.loads(metrics().splitlines()[-1])['code'] == 'red-already-passes'
            assert not mark().exists(), 'RED ja verde produziu marca antes do primeiro commit'
            assert run('git', 'rev-parse', '--verify', 'HEAD', ok=False).returncode != 0
            assert [state(Path(f).read_bytes()) for f in locks] == ['open']
            return
        judge()
        assert not mark().exists(), 'primeiro RED produziu marca de fechamento'
        first = commit()
        assert git('rev-list', '--count', 'HEAD') == '1', 'RED nao foi primeiro commit'
        assert states() == ['open'] and close() == ''
        green()
        judge()
        assert mark().is_file(), 'GREEN depois do primeiro RED nao produziu marca'
        user = commit()
        assert git('rev-parse', 'HEAD@{1}') == first, 'reflog nao aponta para primeiro RED'
        close()
        closes(user)
        assert git('rev-list', '--count', 'HEAD') == '3', 'esperados RED, GREEN e fechamento'
        return
    assert states() == ['open']
    if case in ('sem-marca', 'marca-invalida'):
        if case == 'marca-invalida':
            mark().parent.mkdir(parents=True, exist_ok=True)
            mark().write_bytes(b'{invalida\xff')
        old = head()
        assert close() == '', 'sem marca legivel deve ser silencioso'
        assert head() == old and states() == ['open']
        return
    green()
    if case in ('assinatura-ssh-env-1', 'assinatura-ssh-env-2', 'assinatura-ssh-repo'):
        signed_cycle(case)
        return
    common_mark = None
    if case == 'worktree':
        common_mark = mark().resolve()
        common_mark.parent.mkdir(parents=True, exist_ok=True)
        common_mark.write_text('marca de outra worktree')
        wt = Path(os.environ['TMPDIR']) / 'ligado'
        git('worktree', 'add', '-b', 'ligado', str(wt), 'HEAD')
        os.chdir(wt)
        green()
    if case == 'varias-travas':
        # Dois ciclos reais em branches distintos, unidos com as travas abertas.
        git('reset', '--hard', 'HEAD')
        first_branch = git('branch', '--show-current')
        git('checkout', '-b', 'segundo-red', 'HEAD^')
        Path('shouty.py').write_text('def shout(s):\n    raise NotImplementedError\n')
        Path('tests/test_shout.py').write_text('from shouty import shout\ndef test_shout():\n    assert shout("hi") == "HI!"\n')
        run('shipcraft', 'red'); git('add', '-A'); run('shipcraft', 'check'); git('add', '-A'); commit()
        git('checkout', first_branch)
        git('merge', '--no-ff', '--no-edit', 'segundo-red')
        locks = git('ls-files', '.shipcraft/locks/*.json').splitlines() or [str(p) for p in Path('.shipcraft').rglob('*.json') if state(p.read_bytes()) == 'open']
        assert len(locks) == 2, 'fixture precisa de duas travas reais'
        green(); Path('shouty.py').write_text('def shout(s):\n    return s.upper() + "!"\n'); git('add', 'shouty.py')
    if case == 'destacado':
        git('checkout', '--detach')
    if case == 'marca-falha':
        judge()
        assert mark().is_file(), 'controle nao produziu marca'
        mark().unlink()
        mark().parent.mkdir(parents=True, exist_ok=True)
        mark().mkdir(); (mark() / 'ocupada').write_text('x')
        p = judge(ok=False)
        assert p.returncode != 0, 'falha gravando marca deveria recusar'
        assert states() == ['open']
        lines = [line for line in (p.stdout+p.stderr).splitlines() if line.strip()][-3:]
        assert len(lines) == 3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'), lines
        return
    if case in ('ignorado', 'solto'):
        if case == 'solto':
            judge()
            assert mark().is_file(), 'controle GREEN nao produziu marca'
            mark().unlink()
        Path('apoio.py').write_text(Path('textutil.py').read_text())
        Path('textutil.py').write_text('from apoio import slugify\n')
        git('add', 'textutil.py')
        if case == 'ignorado':
            with path('info/exclude').open('a') as f:
                f.write('\napoio.py\n')
            git('check-ignore', 'apoio.py')
        else:
            assert run('git', 'check-ignore', 'apoio.py', ok=False).returncode != 0
            p = judge(ok=False)
            assert not mark().exists(), 'arquivo solto entrou na copia julgada'
            assert states() == ['open']
            # Erro de coleta pode recusar; nunca pode anunciar fechamento.
            return
    before = {f: (Path(f).read_bytes(), subprocess.check_output(['git','show', ':'+f])) for f in locks}
    if case == 'indice-final':
        # Arvore boa e indice ruim: nao pode usar produto da arvore.
        git('restore', '--staged', 'textutil.py')
        judge()
        assert not mark().exists(), 'indice ainda RED nao deve fechar'
        green()
        Path('textutil.py').write_text('raise RuntimeError("fora do indice")\n')
    if case == 'fecha-comum':
        os.environ['LEFTHOOK'] = '1'
        install()
        user_parent = head()
        commit()
        user = git('rev-parse', 'HEAD^')
        assert git('rev-parse', user+'^') == user_parent
        closes(user)
        run('shipcraft', 'ci', '--base', git('rev-parse', 'HEAD~3'))
        return
    judge()
    assert mark().is_file(), 'check --commit-msg nao gravou marca'
    assert all(Path(f).read_bytes() == a and subprocess.check_output(['git','show', ':'+f]) == b for f,(a,b) in before.items()), 'commit-msg escreveu a trava'
    if case == 'julgamento':
        assert states() == ['open']
        return
    if case == 'recusa-limpa-marca':
        Path('tests/test_slug.py').write_text('# adulterado\n'); git('add','tests/test_slug.py')
        p = judge(ok=False)
        assert p.returncode != 0 and not mark().exists(), 'recusa deixou marca antiga'
        assert 'Why:' in p.stdout+p.stderr and 'Next:' in p.stdout+p.stderr
        return
    if case == 'configuracoes':
        # Referencias 15b/15c: todos os nomes, locais inclusive; YAML nao muda a protecao por bytes.
        for name in ('lefthook.yml','.lefthook.yml','lefthook.yaml','.lefthook.yaml','lefthook-local.yml','.lefthook-local.yml','lefthook-local.yaml','.lefthook-local.yaml'):
            Path(name).write_text('{pre-commit: {parallel: true}} # comentario\r\n')
            git('add', name)
            p = judge(ok=False)
            assert p.returncode != 0 and not mark().exists(), name
            git('reset', '--', name)
            if name == 'lefthook.yml': git('restore', name)
            else: Path(name).unlink()
        return
    if case == 'abortada':
        # Julgou uma tentativa abortada. Outro commit muda HEAD e depois repete a mesma arvore.
        git('commit', '--allow-empty', '-qm', 'tentativa seguinte', '--only', 'lefthook.yml')
        commit()
    elif case == 'outra-arvore':
        Path('extra.txt').write_text('entrou depois do julgamento'); git('add','extra.txt'); commit()
    elif case == 'outro-head':
        # Mesmo tree, commit intermediario vazio entre julgamento e commit usuario.
        tree = git('rev-parse','HEAD^{tree}')
        mid = git('commit-tree',tree,'-p',head(),'-m','intermediario')
        git('update-ref','HEAD',mid,head()); commit()
    elif case == 'amend':
        commit('--amend')
    elif case == 'parcial':
        # commit --only usa indice temporario; check ve esse indice.
        Path('fora.txt').write_text('preparado fora do commit'); git('add','fora.txt')
        os.environ['LEFTHOOK'] = '1'
        install(); path('hooks/post-commit').unlink()
        commit('--only','textutil.py')
    else:
        commit()
    user = head()
    if case in ('outra-arvore','outro-head','abortada','sem-reflog'):
        if case == 'sem-reflog':
            path('logs/HEAD').unlink(missing_ok=True)
        out = close()
        assert head() == user and states() == ['open'] and not mark().exists(), 'marca obsoleta fechou ou ficou'
        assert len(out.strip().splitlines()) == 1 and 'open' in out.lower(), out
        return
    if case in ('merge','cherry-pick','revert','rebase'):
        p = path({'merge':'MERGE_HEAD','cherry-pick':'CHERRY_PICK_HEAD','revert':'REVERT_HEAD','rebase':'rebase-merge'}[case])
        if case == 'rebase': p.mkdir()
        else: p.write_text(git('rev-parse','HEAD^')+'\n')
        status_env = dict(os.environ, LC_ALL='C', LANG='C')
        status = run('git', 'status', env=status_env).stdout.lower()
        assert {'merge':'merg', 'cherry-pick':'cherry', 'revert':'revert', 'rebase':'rebas'}[case] in status, 'fixture nao detectada por git status'
        close()
        assert head() == user and states() == ['open'] and not mark().exists(), 'operacao Git fechou'
        return
    if case == 'pos-ref-falha':
        real_git = shutil.which('git')
        bindir = Path(os.environ['TMPDIR']) / 'git-pos-ref'
        bindir.mkdir()
        trigger = bindir / 'disparou'
        index_path = path('index').resolve()
        saved_index = bindir / 'indice-original'
        wrapper = bindir / 'git'
        wrapper.write_text('#!/bin/sh\nif [ "$1" = update-ref ]; then\n  ' + shlex.quote(real_git) + ' "$@" || exit $?\n  mv ' + shlex.quote(str(index_path)) + ' ' + shlex.quote(str(saved_index)) + '\n  mkdir ' + shlex.quote(str(index_path)) + '\n  touch ' + shlex.quote(str(trigger)) + '\n  exit 0\nfi\nexec ' + shlex.quote(real_git) + ' "$@"\n')
        wrapper.chmod(0o755)
        old_path = os.environ['PATH']
        os.environ['PATH'] = str(bindir) + os.pathsep + old_path
        out = close()
        os.environ['PATH'] = old_path
        assert trigger.exists(), 'fixture: ref nao passou pelo executavel git'
        assert head() != user and states() == ['closed'], 'falha depois do ref desfez commit'
        assert 'git ' in out and any(x in out for x in ('index', 'reset', 'restore')), 'falta comando para acertar indice: ' + out
        index_path.rmdir()
        shutil.move(str(saved_index), str(index_path))
        return
    if case == 'ref-andou':
        real_git = shutil.which('git')
        concurrent = git('commit-tree', git('rev-parse','HEAD^{tree}'), '-p', user, '-m', 'concorrente')
        bindir = Path(os.environ['TMPDIR']) / 'git-race'
        bindir.mkdir()
        trigger = bindir / 'disparou'
        wrapper = bindir / 'git'
        wrapper.write_text('#!/bin/sh\nif [ "$1" = update-ref ] && [ ! -e ' + shlex.quote(str(trigger)) + ' ]; then\n  touch ' + shlex.quote(str(trigger)) + '\n  ' + shlex.quote(real_git) + ' update-ref HEAD ' + concurrent + ' ' + user + '\nfi\nexec ' + shlex.quote(real_git) + ' "$@"\n')
        wrapper.chmod(0o755)
        old_path = os.environ['PATH']
        os.environ['PATH'] = str(bindir) + os.pathsep + old_path
        out = close()
        os.environ['PATH'] = old_path
        assert trigger.exists(), 'fixture: fechamento nao passou por git update-ref'
        assert head() == concurrent and mark().exists() and states() == ['open'], 'fecha atropelou ref concorrente ou perdeu marca'
        assert len(out.strip().splitlines()) == 1 and 'shipcraft close' in out, out
        return
    if case in ('assinatura-falha','index-lock'):
        if case == 'index-lock': path('index.lock').write_text('ocupado')
        else:
            git('config','commit.gpgsign','true'); git('config','gpg.program','/nao-existe-item17')
        index = path('index').read_bytes(); files = [Path(f).read_bytes() for f in locks]
        out = close()
        assert head() == user and path('index').read_bytes() == index and [Path(f).read_bytes() for f in locks] == files and mark().exists(), 'falha antes do ref alterou estado/perdeu marca'
        assert len(out.strip().splitlines()) == 1 and 'shipcraft close' in out, out
        if case == 'index-lock': path('index.lock').unlink()
        else: git('config','commit.gpgsign','false')
        close(); closes(user)
        return
    if case in ('indice-preservado','parcial'):
        Path('outro.txt').write_text('indice depois do julgamento'); git('add','outro.txt')
        saved = subprocess.check_output(['git','ls-files','--stage','--','outro.txt','fora.txt'])
    if case == 'arvore-divergente':
        Path(locks[0]).write_bytes(Path(locks[0]).read_bytes()+b'\n ')
        saved = Path(locks[0]).read_bytes()
    # Nenhum hook deve rodar no commit de plumbing.
    probe = Path(os.environ['TMPDIR']) / 'hook-indevido'
    os.environ['ITEM17_PROBE'] = str(probe)
    os.environ['LEFTHOOK'] = '1'
    out = close()
    closes(user)
    assert not probe.exists(), 'fechamento executou hook'
    if common_mark:
        assert common_mark.read_text() == 'marca de outra worktree', 'worktree alterou marca comum'
    if case in ('indice-preservado','parcial'):
        assert subprocess.check_output(['git','ls-files','--stage','--','outro.txt','fora.txt']) == saved, 'fecha alterou outras entradas'
        assert git('ls-tree','HEAD','outro.txt','fora.txt') == '', 'fecha levou indice'
    if case == 'arvore-divergente':
        assert Path(locks[0]).read_bytes() == saved, 'fecha sobrescreveu trava editada'
        assert len(out.strip().splitlines()) == 1, out
    else:
        assert all(Path(f).read_bytes() == blob('HEAD', f) for f in locks), 'arquivo igual ao HEAD nao atualizado'
    assert all(subprocess.check_output(['git','show', ':'+f]) == blob('HEAD', f) for f in locks), 'indice da trava nao atualizado'
    assert close() == '', 'segunda chamada nao foi silenciosa'


if __name__ == '__main__':
    main(sys.argv[1])
