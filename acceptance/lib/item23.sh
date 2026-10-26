# Item 23 (bd054cb): HTTP local, leitores, métricas e leitura sem efeitos.
item23_cases() {
  local c
  for c in servidor portas-primeira portas-simultaneas portas-esgotadas porta-explicita porta-ocupada porta-zero porta-texto porta-alta porta-negativa sigint totais por-dia tipos-linha bytes-invalidos ultima-linha ultima-valida campos-ausentes tokens quantis fuso ausente ilegivel subpasta worktree travas-arvore travas-fechadas travas-worktree travas-invalidas escape atualiza nao-grava falha-nao-grava; do
    echo "v1-23.$c"
  done
}
item23_case() {
  EXPECT="item 23: ${CASE#v1-23.}"
  v1_start codex
  case "$CASE" in
    *.travas-*|*.escape) setup_red ;;
  esac
  if [ "$CASE" = v1-23.travas-fechadas ]; then
    L implement
    must_accept "fixture: fechamento real" commit commit_all "feat: fecha trava"
  fi
  # Probe fora do repositório; trap cobre inclusive uma falha do harness.
  trap 'if [ -f "$CW/painel.pids" ]; then while read -r p; do kill -TERM "$p" 2>/dev/null || :; done < "$CW/painel.pids"; fi' EXIT
  cat > "$CW/item23.py" <<'PY'
import concurrent.futures
import fcntl
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import shlex
import signal
import socket
import subprocess
import sys
import time
import urllib.request

case, cw = sys.argv[1], Path(sys.argv[2])
root = Path.cwd()
processes, sockets = [], []
# Os casos de faixa padrão se excluem só dentro deste recorte; não matam
# nem desalojam serviços alheios. Portas explícitas usam bind(0) no fixture.
range_lock = None

def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()

common = Path(git('rev-parse', '--git-common-dir')).resolve()
log = common / 'shipcraft/runs.jsonl'

def put(rows, tail=b''):
    log.parent.mkdir(parents=True, exist_ok=True)
    log.write_bytes(b''.join(json.dumps(r, ensure_ascii=False).encode() + b'\n' for r in rows) + tail)

def row(layer='hook', result='passed', **kw):
    return dict(layer=layer, result=result, code='', secs=1,
                at=1704110400, branch='main', commit=git('rev-parse','HEAD'), **kw) if not kw else dict(row(layer, result), **kw)

class Page(HTMLParser):
    def __init__(self, raw):
        super().__init__(convert_charrefs=True)
        self.parts, self.chunks, self.attrs = [], [], []
        self.hidden = 0
        self.feed(raw)
        self.text = ' '.join(' '.join(self.parts).split())
        self.raw = raw
    def handle_starttag(self, tag, attrs):
        self.attrs.extend((tag, k, v or '') for k,v in attrs)
        if tag in ('script','style'): self.hidden += 1
        if tag in ('tr','li','p','div','section','h1','h2','h3'): self.parts.append('\n')
    def handle_endtag(self, tag):
        if tag in ('script','style'): self.hidden -= 1
        if tag in ('tr','li','p','div','section','h1','h2','h3'): self.parts.append('\n')
    def handle_data(self, data):
        if not self.hidden: self.parts.append(data)

def has(page, pattern):
    assert re.search(pattern, page.text, re.I), (pattern, page.text)

def value(page, label, number):
    # Aceita tabela, cartões, unidades e separador decimal local, sem fixar CSS.
    n = re.escape(str(number)).replace(r'\.', '[.,]')
    assert re.search(r'(?<!\w)' + label + r'(?!\w)\s*[:|=–—-]?\s*' + n + r'(?![\d.,])', page.text, re.I), (label, number, page.text)

def no_external(page):
    assert 'https://' not in page.raw.lower() and 'http://' not in page.raw.lower(), 'URL externa na pagina'
    for tag,k,v in page.attrs:
        if k in ('src','href','action'):
            assert not v.startswith('//'), ('recurso externo', v)

def reserve(port=0):
    s = socket.socket()
    s.bind(('127.0.0.1', port)); s.listen(8)
    sockets.append(s)
    return s.getsockname()[1]

def free_port():
    port = reserve(); sockets.pop().close(); return port

def start(args=None, cwd=None, env=None):
    if args is None: args = ['--port',str(free_port())]
    p = subprocess.Popen(['shipcraft','dashboard',*args], cwd=cwd or root, env=env,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         start_new_session=True)
    processes.append(p)
    with (cw/'painel.pids').open('a') as f: f.write(str(p.pid)+'\n')
    os.set_blocking(p.stdout.fileno(), False)
    return p

def output(p):
    b = getattr(p, 'captured', b'')
    try: b += os.read(p.stdout.fileno(),65536)
    except BlockingIOError: pass
    p.captured = b
    return b.decode('utf-8', errors='replace')

def address(p):
    end = time.monotonic()+8
    while time.monotonic() < end:
        out = output(p)
        m = re.search(r'http://127\.0\.0\.1:(\d+)',out)
        if m:
            print('$ shipcraft dashboard; endereco:',m.group(0),flush=True)
            return m.group(0), int(m.group(1))
        assert p.poll() is None, 'painel encerrou antes de servir: '+out
        time.sleep(.04)
    raise AssertionError('painel nao anunciou endereco numa linha: '+output(p))

def get(url):
    # Proxy da máquina nunca participa do HTTP local.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(url, timeout=4) as r:
        assert r.status == 200
        assert 'html' in r.headers.get('Content-Type','').lower()
        return Page(r.read().decode('utf-8'))

def page(cwd=None,env=None):
    p=start(cwd=cwd,env=env); url,_=address(p)
    result=get(url); no_external(result)
    return p,url,result

def refusal(args, phrase=None):
    p=start(args)
    try: p.wait(timeout=5)
    except subprocess.TimeoutExpired: raise AssertionError('porta invalida/ocupada manteve servidor vivo')
    out=output(p); print('$ shipcraft dashboard',shlex.join(args),'rc=',p.returncode,'\n'+out,flush=True)
    assert p.returncode != 0
    lines=[x for x in out.splitlines() if x.strip()][-3:]
    assert len(lines)==3 and all(s.startswith(prefix) for s,prefix in zip(lines,('shipcraft refused:','Why:','Next:'))), out
    if phrase: assert re.search(phrase,out,re.I),out

def snapshot():
    # Conteúdo, modo, mtime e diretórios; atime é efeito de leitura permitido.
    data={}
    for base in (root,common,cw/'bin/state'):
        for p in [base,*base.rglob('*')]:
            if p.is_symlink(): v=('link',os.readlink(p))
            elif p.is_file(): v=('file',p.stat().st_mode,p.stat().st_mtime_ns,hashlib.sha256(p.read_bytes()).hexdigest())
            elif p.is_dir(): v=('dir',p.stat().st_mode)
            else: continue
            data[str(p)]=v
    return data

def stop(p):
    if p.poll() is None:
        os.killpg(p.pid,signal.SIGINT)
        try: p.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid,signal.SIGKILL); p.wait()
            raise AssertionError('SIGINT nao encerrou painel')

try:
    if case.startswith('portas-') or case=='servidor':
        range_lock=open(Path(os.environ['WORK'])/'item23-portas.lock','a')
        fcntl.flock(range_lock,fcntl.LOCK_EX)
    if case=='servidor':
        # A primeira porta está realmente livre, e não apenas sondada antes.
        port=reserve(7420); sockets.pop().close()
        p=start([]); url,n=address(p); assert n==7420
        get(url)
        # Um listener wildcard aceita também 127.0.0.2; o contratado não aceita.
        probe=socket.socket(); probe.settimeout(.5)
        try: assert probe.connect_ex(('127.0.0.2',n))!=0, 'listener fora de 127.0.0.1'
        finally: probe.close()
    elif case=='portas-primeira':
        for n in range(7420,7423): reserve(n)
        p=start([]); url,n=address(p); assert n==7423; get(url)
    elif case=='portas-simultaneas':
        p=start([]); q=start([])
        url,n=address(p); url2,m=address(q)
        assert {n,m}=={7420,7421}; get(url); get(url2)
    elif case in ('portas-esgotadas','falha-nao-grava'):
        if case=='falha-nao-grava':
            n=reserve(); before=snapshot(); refusal(['--port',str(n)],r'busy|open|port'); assert snapshot()==before
        else:
            for n in range(7420,7440): reserve(n)
            refusal([],r'7420.*7439|20.*ports|ports.*20')
    elif case=='porta-explicita':
        n=free_port(); p=start(['--port',str(n)]); url,m=address(p); assert n==m; get(url)
    elif case=='porta-ocupada':
        n=reserve(); refusal(['--port',str(n)],r'busy|open|port')
    elif case in ('porta-zero','porta-texto','porta-alta','porta-negativa'):
        refusal(['--port',{'porta-zero':'0','porta-texto':'nao-numero','porta-alta':'65536','porta-negativa':'-1'}[case]],r'port|1.*65535')
    elif case=='sigint':
        p,url,_=page(); stop(p)
        with socket.socket() as s:
            s.settimeout(.5); assert s.connect_ex(('127.0.0.1',int(url.rsplit(':',1)[1])))!=0
    elif case=='totais':
        rows=[row(layer,result) for layer,n in [('hook',7),('ci',11),('review',13)] for result in ['passed']*n]
        rows += [row('hook','refused',code='defeito-azul') for _ in range(3)]
        rows += [row('ci','error') for _ in range(2)]
        put(rows); _,_,pg=page()
        value(pg,r'hook',10); value(pg,r'ci',13); value(pg,r'review',13)
        value(pg,r'defeito-azul',3); value(pg,r'total',36); has(pg,r'2024-01-01|01/01/2024')
    elif case=='por-dia':
        put([row('hook',secs=2) for _ in range(3)]+
            [row('ci',at=1704196800) for _ in range(5)]+
            [row('review',at=None,tokens=7) for _ in range(2)])
        _,_,pg=page()
        value(pg,'hook',3); value(pg,'ci',5); value(pg,r'review',2)
        value(pg,'no date',2)
        # Em tabelas ou blocos diários, a data e seu total ficam juntos.
        has(pg,r'(2024-01-01|01/01/2024).{0,120}?\b3(?!\d)')
        has(pg,r'(2024-01-02|02/01/2024).{0,120}?\b5(?!\d)')
    elif case=='tipos-linha':
        put([row(), {'escape':True}, {'escape':False,'layer':'hook'},
             {'reason':'manual'}, {'layer':'fora','result':'passed'},
             {'layer':'ci','result':'desconhecido'}])
        _,_,pg=page(); value(pg,'hook',1)
        value(pg,'escape',2); value(pg,'reason',1); value(pg,'layer',2)
        has(pg,r'other records');
        if re.search(r'unreadable lines',pg.text,re.I): value(pg,r'unreadable lines',0)
    elif case=='bytes-invalidos':
        put([row()]); log.write_bytes(log.read_bytes()+b'\xff\n{quebrado\n[]\nnull\n42\n"texto"\n')
        _,_,pg=page(); value(pg,r'unreadable lines',6); value(pg,'hook',1)
    elif case=='ultima-linha':
        put([row()],b'{pendente'); p,url,pg=page()
        value(pg,'hook',1);
        if re.search(r'unreadable lines',pg.text,re.I): value(pg,r'unreadable lines',0)
        # A linha parcial completa só passa a valer na leitura seguinte.
        with log.open('ab') as f: f.write(b'\n')
        time.sleep(10.2); value(get(url),r'unreadable lines',1)
    elif case=='ultima-valida':
        put([row()],json.dumps(row()).encode())
        p,url,pg=page(); value(pg,'hook',1)
        with log.open('ab') as f: f.write(b'\n')
        time.sleep(10.2); value(get(url),'hook',2)
    elif case=='campos-ausentes':
        rows=[row(secs=None,at=None),row(secs='999',at='1704110400'),row(secs=True,at=True),row(secs=None,at=1704110400.5),row(secs=17)]
        del rows[0]['secs']; del rows[0]['at']
        put(rows); _,_,pg=page(); value(pg,'hook',5)
        value(pg,'no date',4); value(pg,'p50',17); value(pg,'p90',17)
    elif case=='tokens':
        rows=[row('review',tokens=50000),row('review',tokens=7000),row('review',tokens=None),row('review'),row('review',tokens='900000'),row('review',tokens=True)]
        put(rows); _,_,pg=page()
        has(pg,r'Review tokens\s*:?\s*(57\s*thousand|57[. ]?000)')
        has(pg,r'4 reviews unmeasured'); value(pg,r'review',6)
    elif case=='quantis':
        # n=4: nearest rank dá 20/100; interpolação dá 30/82.
        put([row(result=r,secs=t) for r,t in [('passed',10),('refused',20),('error',40),('passed',100)]]+[row('ci',secs=999,at=1704196800)])
        _,_,pg=page(); value(pg,'p50',20); value(pg,'p90',100)
        has(pg,r'2024-01-02|02/01/2024'); has(pg,'—')
    elif case=='fuso':
        # 2024-01-02 00:30Z é 2024-01-01 em São Paulo.
        put([row(at=1704155400)])
        _,_,pg=page(env=dict(os.environ,TZ='America/Sao_Paulo'))
        has(pg,r'2024-01-01|01/01/2024')
        assert not re.search(r'2024-01-02|02/01/2024',pg.text),pg.text
    elif case=='ausente':
        if log.exists(): log.unlink()
        _,_,pg=page(); has(pg,r'no runs yet')
    elif case=='ilegivel':
        put([row()]); log.chmod(0)
        assert not os.access(log,os.R_OK),'fixture chmod 000 requer usuario sem privilegio'
        try:
            _,_,pg=page(); has(pg,r'could not read runs\.jsonl:\s*\S+')
            assert not re.search(r'no runs yet',pg.text,re.I)
        finally: log.chmod(0o600)
    elif case in ('subpasta','worktree'):
        put([row('ci','refused',code='origem-comum-unica')])
        if case=='subpasta': dest=root/'fundo/do/projeto'; dest.mkdir(parents=True)
        else:
            dest=cw/'worktree ligada'; git('worktree','add','-b','painel-ligado',str(dest),'HEAD')
        _,_,pg=page(cwd=dest); value(pg,'origem-comum-unica',1)
        has(pg,r'runs\.jsonl'); has(pg,r'read|refresh')
    elif case in ('travas-arvore','travas-fechadas','travas-worktree','travas-invalidas','escape'):
        locks=list((root/'.shipcraft/locks').glob('*.json')); assert len(locks)==1
        original=locks[0]; data=json.loads(original.read_text())
        if case=='travas-fechadas':
            assert data.get('state',data.get('status',data.get('estado'))) == 'closed'
            _,_,pg=page(); assert original.stem not in pg.text, 'trava fechada listada como aberta'
        elif case=='travas-worktree':
            dest=cw/'outra arvore'; git('worktree','add','-b','arvore-do-painel',str(dest),'HEAD')
            local=dest/'.shipcraft/locks'/original.name; local.unlink()
            (local.parent/'aberta-so-nesta-worktree.json').write_text(json.dumps(data))
            _,_,pg=page(cwd=dest); has(pg,'aberta-so-nesta-worktree')
            assert original.stem not in pg.text, 'leu travas da worktree principal'
        elif case=='travas-arvore':
            original.unlink() # HEAD/index ainda têm a trava aberta; não devem ser usados.
            fresh=root/'.shipcraft/locks/so-na-arvore.json'; fresh.write_text(json.dumps(data))
            _,_,pg=page(); has(pg,'so-na-arvore')
            assert original.name not in pg.text, 'painel leu indice/HEAD'
        elif case=='travas-invalidas':
            bad=dict(data); key=next(k for k in bad if 'vers' in k or 'format' in k)
            bad[key]=999 if isinstance(bad[key],int) else '999.0'
            (original.parent/'formato-futuro.json').write_text(json.dumps(bad))
            # Mesmo JSON, mas conteúdo do contrato sem recalcular o selo.
            bad=json.loads(original.read_text())
            def corrupt(v):
                if isinstance(v,dict):
                    for k in v:
                        if 'seal' in k or 'selo' in k or 'hash' in k:
                            v[k]='0'*64; return True
                        if corrupt(v[k]): return True
                elif isinstance(v,list):
                    return any(corrupt(x) for x in v)
                return False
            assert corrupt(bad),'fixture nao encontrou selo no formato publico'
            (original.parent/'selo-errado.json').write_text(json.dumps(bad))
            (original.parent/'truncada.json').write_bytes(b'{"')
            _,_,pg=page(); has(pg,r'unreadable locks')
            for name in ('formato-futuro','selo-errado','truncada'): has(pg,name)
            has(pg,re.escape(original.stem))
        else:
            name='trava <script>alert(23)<script> " &.json'
            original.rename(original.parent/name)
            code='<script>alert(23)</script> " &'
            put([row('ci','refused',code=code),{'<script>campo</script> " &':True}])
            _,_,pg=page(); assert name in pg.text and code in pg.text and '<script>campo</script> " &' in pg.text
            assert not re.search(r'<script[^>]*>\s*(alert\(23\)|campo)',pg.raw,re.I),'dado executavel'
            no_external(pg)
    elif case=='atualiza':
        put([row('ci','refused',code='antes-da-atualizacao')])
        p,url,pg=page(); has(pg,'antes-da-atualizacao')
        # Sem biblioteca externa: refresh HTML ou timer JS com 10 segundos.
        refresh=any(k=='http-equiv' and v.lower()=='refresh' for _,k,v in pg.attrs)
        if refresh:
            assert any(k=='content' and re.match(r'10(?:\D|$)',v) for _,k,v in pg.attrs)
        else:
            assert re.search(r'(setTimeout|setInterval)[\s\S]*?(10_?000|10\s*\*\s*1000)',pg.raw), 'sem atualizacao automatica a cada 10 s'
        put([row('ci','refused',code='depois-da-atualizacao')])
        time.sleep(10.2)
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            pages=list(pool.map(lambda _:get(url),range(4)))
        for updated in pages:
            has(updated,'depois-da-atualizacao'); assert 'antes-da-atualizacao' not in updated.text
            has(updated,r'(refresh|read)[\s\S]{0,100}\d+[.,]?\d*\s*(ms|s|seconds|milliseconds)')
    elif case=='nao-grava':
        # Sem shipcraft/ nem .shipcraft/: servir e encerrar não podem criá-los.
        before=snapshot(); p,url,_=page(); get(url); stop(p)
        assert snapshot()==before,'painel escreveu no repositorio ou no git common dir'
        put([row()]); before=snapshot(); p,url,_=page(); get(url); stop(p)
        assert snapshot()==before,'painel alterou execucoes ou criou arquivos'
    else: raise AssertionError('caso desconhecido '+case)
finally:
    for p in processes:
        if p.poll() is None:
            os.killpg(p.pid,signal.SIGTERM)
            try: p.wait(timeout=2)
            except subprocess.TimeoutExpired: os.killpg(p.pid,signal.SIGKILL); p.wait()
    for s in sockets: s.close()
    if range_lock: range_lock.close()
PY
  must_accept "painel caixa-preta" cmd "$PY" "$CW/item23.py" "${CASE#v1-23.}" "$CW"
  pass
}
