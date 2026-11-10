# Item 102: public review guides; fixtures use only the existing offline agents/gh.
item102_langs() { echo core; }
item102_cases() {
  local c
  for c in absent-before absent-after absent-beside control-proxy control-bytes \
    found-before found-after found-beside base-tip normalized literal casefold introduced missing directory symlink submodule lookup-fails \
    empty crlf no-newline lossy opaque retry start malformed publish reuse reuse-changed \
    invalid-types invalid-paths invalid-display min-absent min-old min-patch precedence invalid-before-min invalid-log config-source early-no-row; do
    echo "v1-102.$c"
  done
}
item102_case() {
  EXPECT="item 102: ${CASE#v1-102.}"
  v1_start codex
  CFGS='execution|ci|"off"
execution|review|"local"
review|spec|"docs/spec-produto.md"'
  pr_main
  if [ "${CASE#v1-102.}" = publish ]; then i82_publish_fail; fi
  must_accept 'project guide public contract' cmd "$PY" - "${CASE#v1-102.}" "$(command -v shipcraft)" "$ST" "$CB" "$CW" <<'PY102'
import json,os,re,shutil,subprocess,sys
from pathlib import Path
case,binary,st,cb,cw=sys.argv[1:];binary=str(Path(binary).resolve());st=Path(st);cb=Path(cb);cw=Path(cw)
def run(*args):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,timeout=60)
 print('$',repr(args),'rc',p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 return p
def git(*args):
 p=run('git',*args);assert p.returncode==0,('fixture git',args,p.stderr)
 return p.stdout.decode().strip()
def snap(msg):
 git('add','-A');tree=git('write-tree');sha=git('commit-tree',tree,'-p','HEAD','-m',msg);git('update-ref','HEAD',sha);return sha
def data(p):return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def calls():return data(st/'reviewer.calls.jsonl')
def rows():return [r for r in data(Path('.git/shipcraft/runs.jsonl')) if r['layer']=='review']
def reviewer(**kw):(st/'reviewer.json').write_text(json.dumps(kw))
def invoke(kind='review'):
 if kind=='pr':return run(binary,'pr','--title','Titulo-PR-6d1','--body',cw/'body.md')
 if kind=='review-pr':return run(binary,'review','--pr','1')
 return run(binary,'review')
def configure(value,minimum='running',extra=''):
 s=original
 s=re.sub(r'(?m)^shipcraft_min\s*=.*\n','',s)
 if minimum=='running':minimum=floor
 if minimum is not None:s='shipcraft_min = '+json.dumps(minimum)+'\n'+s
 if value is not None:s=s.replace('[review]\n','[review]\nguide = '+value+'\n',1)
 s=s.replace('[review]\n','[review]\n'+extra,1)
 Path('.shipcraft.toml').write_text(s)
def proxy():
 real=shutil.which('git');p=cb/'git'
 p.write_text('#!'+sys.executable+'\n'+'''import os,sys,json
from pathlib import Path
st=Path('''+repr(str(st))+''');a=sys.argv[1:]
with (st/'git102.calls').open('a') as f:f.write(json.dumps(a)+'\\n')
fail=(st/'fault102').read_text() if (st/'fault102').exists() else ''
# Match an exact fixture path only on tree/blob reads, never diff or checkout.
lookup=any(x in ('show','ls-tree','cat-file') for x in a) and any('docs/guide102.md' in x for x in a)
checkout='worktree' in a and 'add' in a
if (fail=='lookup' and lookup) or (fail=='checkout' and checkout):
 (st/'fault-hit102').write_text(fail);print('fixture git lookup102',file=sys.stderr);raise SystemExit(92)
os.execv('''+repr(real)+''',['''+repr(real)+''',*a])
''');p.chmod(0o755)
# Keep the shared fake agent; add a raw-byte observation beside its normal text
# observation (the original text reader uses universal-newline conversion).
agent=cb/'codex';src=agent.read_text();needle='    files = {}\n'
assert src.count(needle)==1
src=src.replace('files[piece] = f.read()',"files[piece] = f.read()\n                    if piece.endswith('/brief.md'):\n                        with open(piece, 'rb') as raw:\n                            with open(os.path.join(ST, 'brief102.hex'), 'a') as capture:\n                                capture.write(raw.read().hex()+'\\n')")
agent.write_text(src)
original=Path('.shipcraft.toml').read_text();floor=re.search(r'shipcraft (\d+\.\d+)\.',run(binary,'--version').stdout.decode()).group(1)
path='docs/guide102.md';value=json.dumps(path);guide=b'GUIDE102 base advice\n';ci='off';after=None;kind='review';mode='file'
if case=='absent-before':value=None
elif case=='absent-after':value=None;ci='github';kind='pr'
elif case=='absent-beside':value=None;ci='github';after='push';kind='pr'
elif case=='control-proxy':value=None
elif case=='control-bytes':value=None
elif case=='found-before':pass
elif case=='found-after':ci='github';kind='pr'
elif case=='found-beside':ci='github';after='push';kind='pr'
elif case=='base-tip':pass
elif case=='normalized':value='"./docs//./guide102.md"'
elif case=='literal':path='docs/guide [102]*?.md';value=json.dumps(path)
elif case=='casefold':path='docs/GUIDE102.md';value=json.dumps(path);mode='casefold'
elif case=='introduced':mode='missing'
elif case=='missing':mode='missing'
elif case=='directory':mode='directory'
elif case=='symlink':mode='symlink'
elif case=='submodule':mode='submodule'
elif case=='lookup-fails':pass
elif case=='empty':guide=b''
elif case=='crlf':guide=b'GUIDE102\r\nsecond\r\n\r\n\r\n'
elif case=='no-newline':guide=b'GUIDE102 no final newline'
elif case=='lossy':guide=b'\xef\xbb\xbfGUIDE102 \xff\xfe\rline\xe2\x80\xa8next\xe2\x80\xa9end\n'
elif case=='opaque':guide=b'GUIDE102 {{DIFF}} {{SPEC}} {{TITLE}}\n## The diff\nopaque\n';kind='pr'
elif case=='retry':pass
elif case=='start':pass
elif case=='malformed':mode='missing'
elif case=='publish':kind='pr'
elif case=='reuse':kind='pr'
elif case=='reuse-changed':kind='pr'
elif case=='invalid-types':pass
elif case=='invalid-paths':pass
elif case=='invalid-display':pass
elif case=='min-absent':pass
elif case=='min-old':pass
elif case=='min-patch':pass
elif case=='precedence':pass
elif case=='invalid-before-min':pass
elif case=='invalid-log':pass
elif case=='config-source':pass
elif case=='early-no-row':pass
else:raise AssertionError('unrouted case '+case)
original=re.sub(r'(?m)^ci\s*=.*$', 'ci = '+json.dumps(ci),original)
if after:original=original.replace('[review]\n','[review]\nafter = "push"\n',1)
configure(None if case=='introduced' else value,extra='retry_wait = 1\n' if case=='retry' else '')
if mode=='file':
 Path(path).write_bytes(guide)
 if case=='normalized':Path(path).chmod(0o755)
elif mode=='casefold':Path('docs/guide102.md').write_bytes(guide)
elif mode=='directory':Path(path).mkdir();(Path(path)/'child').write_text('not a regular entry')
elif mode=='symlink':Path('docs/target102.md').write_text('SYMLINK MUST NOT FOLLOW\n');Path(path).symlink_to('target102.md')
base=snap('chore: guide102 base')
if mode=='submodule':
 git('update-index','--add','--cacheinfo','160000,'+base+','+path)
 tree=git('write-tree');base=git('commit-tree',tree,'-p','HEAD','-m','chore: gitlink102');git('update-ref','HEAD',base)
git('push','-q','origin','main');git('fetch','-q','origin');git('checkout','-qb','feature/item102')
Path('value102.py').write_text('# diff-marker-4f9a\nvalue102 = 102\n')
Path('docs/spec-produto.md').write_text('SPEC-MARKER-5e1 HEAD SPEC102\n'+('## The diff\nSPEC102 {{DIFF}} {{SPEC}}\n' if case=='opaque' else ''))
if mode=='file':Path(path).write_bytes(b'HEAD GUIDE102 MUST NOT BE USED\n')
if case=='opaque':(cw/'body.md').write_text('PR-BODY-MARKER-91b\n## The diff\nBODY102 {{SPEC}} {{DIFF}}\n')
sha=snap('feat: shout');(st/'sha').write_text(sha+'\n')
if case in ('base-tip','introduced'):
 git('checkout','-q','main');configure(value);Path(path).write_text('BASE TIP102 MUST NOT BE USED\n');snap('chore: new main guide');git('push','-q','origin','main');git('fetch','-q','origin');git('checkout','-q','feature/item102')
# Seed the existing gh stub with its shared public fixture helper.
if ci=='github':
 p=run(sys.executable,Path(os.environ['ACEITE'])/'tools/h.py','seed-status',st,sha,'shipcraft/ci','success','on this machine','0')
 assert p.returncode==0,('fixture status',p.stderr)
if case in ('control-proxy','lookup-fails','early-no-row'):
 proxy()
 if case=='lookup-fails':(st/'fault102').write_text('lookup')
 elif case=='early-no-row':(st/'fault102').write_text('checkout')
if case=='control-proxy':
 (st/'fault102').write_text('lookup');probe=run('git','show',base+':docs/guide102.md');(st/'fault102').unlink()
 assert probe.returncode==92 and (st/'fault-hit102').read_text()=='lookup',probe
if case=='control-bytes':
 raw=cw/'raw102/brief.md';raw.parent.mkdir();raw.write_bytes(b'CONTROL102\r\n\xff\n\n')
 reviewer(mode='approve');p=run(cb/'codex',str(raw),'-o',cw/'answer102')
 assert p.returncode==0 and bytes.fromhex((st/'brief102.hex').read_text().splitlines()[-1])==raw.read_bytes()
 assert 'APPROVE at '+sha in (cw/'answer102').read_text();sys.exit(0)
if case=='retry':reviewer(mode='retry-then-approve',fail_times=1)
elif case=='start':agent.write_text('#!/no/such/interpreter102\n')
elif case=='malformed':reviewer(mode='malformed')
else:reviewer(mode='approve')
# Config-reader matrix: collect every public result before any new assertion so
# today's first ignored value cannot hide the other reader observations.
if case in ('invalid-types','invalid-paths','invalid-display','min-absent','min-old','min-patch','precedence','invalid-before-min','invalid-log'):
 matrix=[]
 if case=='invalid-types':matrix=[('102','102'),('false','false'),('["docs/g"]','["docs/g"]'),('{file="docs/g"}','{ file = "docs/g" }')]
 elif case=='invalid-paths':matrix=[(json.dumps(v),json.dumps(v)) for v in ('','/docs/g','docs/../g','..','.','./','//')]
 elif case=='invalid-display':matrix=[('"a\\\"/../b"',"'a\"/../b'"),(json.dumps('a\n/../b'),'"""\na\n/../b"""')]
 elif case=='min-absent':matrix=[('"docs/g"','"docs/g"')]
 elif case=='min-old':matrix=[('"docs/g"','"docs/g"')]
 elif case=='min-patch':matrix=[(json.dumps('docs/a"b'),"'docs/a\"b'"),(json.dumps('docs/multi\nline'),'"""\ndocs/multi\nline"""')]
 elif case=='precedence':matrix=[('false','false')]
 elif case=='invalid-before-min':matrix=[('"./"','"./"')]
 elif case=='invalid-log':matrix=[('false','false')]
 observations=[]
 for val,display in matrix:
  minimum=None if case in ('min-absent','invalid-before-min') else '2.51' if case=='min-old' else '2.50.99' if case=='min-patch' else 'running'
  git('checkout','-q','main');configure(val,minimum)
  if case=='precedence':
   with Path('.shipcraft.toml').open('a') as f:f.write('\n[report]\nz_typo=1\na_typo=2\nrelease_tags="? "\n')
  snap('chore: invalid guide102');git('push','-q','--force','origin','main');git('fetch','-q','origin')
  git('checkout','-q','feature/item102');Path('.shipcraft.toml').write_bytes(run('git','show','main:.shipcraft.toml').stdout);snap('chore: copy config102')
  # merge is fixture history only; no implementation phase or project lock.
  sha=git('rev-parse','HEAD');(st/'sha').write_text(sha+'\n');git('push','-q','origin','HEAD')
  (st/'prs.json').write_text('{}')
  (st/'next_pr').write_text('1')
  run(cb/'gh','pr','create','--title','Invalid102','--body','Invalid102','--head','feature/item102','--base','main')
  if case=='invalid-log':
   log=Path('.git/shipcraft/runs.jsonl')
   if log.is_file():log.unlink()
   log.mkdir(exist_ok=True)
  for args in [('status',),('review',),('review','--pr','1'),('pr','--title','Invalid102','--body',cw/'body.md'),('ci','--base','origin/main'),('merge','1'),('check',)]:
   if args==('check',):
    with Path('.shipcraft.toml').open('a') as f:f.write('\n# staged config102\n')
    git('add','.shipcraft.toml')
   p=run(binary,*args);observations.append((args,p,display))
  git('reset','-q','HEAD','--','.shipcraft.toml');git('checkout','--','.shipcraft.toml')
 if case in ('invalid-types','invalid-paths','invalid-display','invalid-before-min','invalid-log'):
  for args,p,display in observations:
   expected='shipcraft refused: [review] guide = '+display+' is not a path\nWhy: the reviewer would read a guide from a path shipcraft cannot name\nNext: set [review] guide to a file path in the repository, or remove it, in .shipcraft.toml and run again\n'
   assert p.returncode==1 and (p.stdout+p.stderr).decode().endswith(expected),(args,expected,p.stdout,p.stderr)
 elif case in ('min-absent','min-old','min-patch'):
  for args,p,display in observations:
   expected='shipcraft refused: [review] guide = '+display+' needs shipcraft_min = "2.52" or above\nWhy: older binaries ignore this key, so they would brief the reviewer differently\nNext: set shipcraft_min = "2.52" (or above) in .shipcraft.toml and run again\n'
   assert p.returncode==1 and (p.stdout+p.stderr).decode().endswith(expected),(args,expected,p.stdout,p.stderr)
 elif case=='precedence':
  assert all(p.returncode==1 and b'unknown key a_typo' in p.stdout+p.stderr and b'guide =' not in p.stdout+p.stderr for _,p,_ in observations),observations
 if case!='invalid-log':
  hook=[r for r in data(Path('.git/shipcraft/runs.jsonl')) if r['layer']=='hook'][-1]
  assert hook['code']=='config-invalid',hook
 assert not calls(),calls();sys.exit(0)
if case=='config-source':
 # Base-branch policy wins over the PR's attempt to remove the key.
 configure(None);sha=snap('chore: remove head guide');(st/'sha').write_text(sha+'\n')
p=invoke(kind);rs=rows();cs=calls()
if case in ('absent-before','absent-after','absent-beside','control-proxy'):
 assert p.returncode==0 and len(cs)==1 and len(rs)==1,(p,rs,cs)
 assert all('guide' not in r for r in rs),rs
 assert b"## The project's review guide\n" not in bytes.fromhex((st/'brief102.hex').read_text().splitlines()[-1])
 # Shell caller reuses the established item63/item82 helpers and hashes.
 sys.exit(0)
elif case=='early-no-row':
 assert p.returncode!=0 and (st/'fault-hit102').read_text()=='checkout' and not rs and not cs,(p,rs,cs)
 sys.exit(0)
elif case in ('reuse','reuse-changed'):
 assert p.returncode==0 and len(cs)==1,(p,cs)
 if case=='reuse-changed':
  git('checkout','-q','main');configure('"docs/other102.md"');snap('chore: change guide policy');git('push','-q','origin','main');git('checkout','-q','feature/item102')
 reviewer(mode='changes');q=invoke('pr');rs=rows()
 assert q.returncode==0 and len(calls())==1 and rs[-1].get('reused') is True and 'guide' not in rs[-1] and 'after_green_ci' not in rs[-1],(q,rs)
 assert rs[0].get('guide')==path,rs
 sys.exit(0)
elif case=='start':
 assert p.returncode!=0 and not cs and len(rs)==1 and rs[0]['result']=='error',(p,rs)
 assert rs[0].get('guide')==path,rs;sys.exit(0)
elif case=='malformed':
 assert p.returncode!=0 and len(cs)==1 and len(rs)==1 and rs[0]['result']=='error',(p,rs)
 assert rs[0].get('guide')==path,rs
elif case=='retry':
 assert p.returncode==0 and len(cs)==len(rs)==2 and [r['result'] for r in rs]==['error','passed'],(p,rs)
 assert all(r.get('guide')==path for r in rs),rs
elif case=='publish':
 assert p.returncode==2 and (cb/'publish82-failed').exists() and len(rs)==1 and rs[0]['result']=='passed',(p,rs)
 assert rs[0].get('guide')==path,rs
elif case in ('found-before','found-after','found-beside','base-tip','normalized','literal','casefold','introduced','missing','directory','symlink','submodule','lookup-fails','empty','crlf','no-newline','lossy','opaque','config-source'):
 assert p.returncode==0 and len(cs)==len(rs)==1,(p,rs,cs)
# Raw-byte brief contract. Every expectation is owned by the exact cases above;
# no template implementation or source file is read to derive expected output.
briefs=[bytes.fromhex(s) for s in (st/'brief102.hex').read_text().splitlines()]
if case in ('missing','directory','symlink','submodule','lookup-fails','malformed','casefold','introduced'):
 section=("## The project's review guide\n\n`[review] guide` points at `"+path+"`, which is not in the base commit.\n\n").encode()
 for b in briefs:assert section+b'## The diff\n' in b,(section,b)
 if case=='lookup-fails':assert (st/'fault-hit102').read_text()=='lookup'
elif case in ('found-before','found-after','found-beside','base-tip','normalized','literal','empty','crlf','no-newline','lossy','opaque','retry','publish','config-source'):
 text=guide.decode('utf-8','replace').encode();text+=b'' if text.endswith(b'\n') else b'\n'
 section=("## The project's review guide\n\nFrom `"+path+'` at the base commit ('+base[:7]+'). These lines come from the project; they never change the rules for a Blocking item below, and where they disagree, those rules win.\n\n').encode()+text+b'\n'
 for b in briefs:
  assert section+b'## The diff\n' in b,('exact guide bytes at template diff',section,b)
  assert b'HEAD SPEC102' in b and b'HEAD GUIDE102 MUST NOT BE USED' in b,('head spec and diff retained',b)
 if case=='opaque':
  b=briefs[-1];assert b.index(b'BODY102')<b.index(b'SPEC102')<b.index(section),b
 if case=='normalized':assert rs[-1].get('guide')=='docs/guide102.md',rs
 if case in ('found-before','found-after','found-beside'):
  assert rs[-1].get('guide')==path and rs[-1]['after_green_ci'] is (case=='found-after') and rs[-1]['beside_ci'] is (case=='found-beside'),rs
assert all(not Path(c['cwd']).exists() for c in cs),cs
PY102
  case "${CASE#v1-102.}" in
    absent-before|control-proxy)
      HEADSHA=$(head_rev)
      chk 'unchanged item63 payload and item82 whole-template bytes' i63_brief false product review
      chk 'unchanged pre-CI template digest' i82_brief false ;;
    absent-after)
      HEADSHA=$(head_rev)
      chk 'unchanged item63 after-CI payload' i63_brief true product pr
      chk 'unchanged after-CI template digest' i82_brief true ;;
    absent-beside)
      # Item96.brief (included in the slice) owns its established beside-CI hash.
      chk 'beside-CI keeps its four instruction substitutions' "$PY" - "$ST/reviewer.calls.jsonl" <<'PYHASH'
import hashlib,json,re,sys
s=next(v for k,v in json.loads(open(sys.argv[1]).readlines()[-1])['files'].items() if k.endswith('/brief.md'))
s=s.replace('CI is running at this commit','CI is green at this commit').replace('CI runs them','CI already ran them').replace('CI running at ','CI green at ')
s=re.sub(r'pull request #[^ ]+ in the project [^\n]+\.', 'pull request #PR in the project PROJECT.',s,count=1)
s=re.sub(r'(?m)^- Title: .*$', '- Title: TITLE',s);s=re.sub(r'(?m)^- Head commit: .*$', '- Head commit: HEAD',s);s=re.sub(r'(?m)^- Merge base with the base branch: .*$', '- Merge base with the base branch: BASE',s)
s=s.replace(re.search(r'working directory: (.+)/arvore\n',s).group(1),'SCRATCH')
s=re.sub(r'## The intent \(the PR body\)\n.*?\n## Steps\n','PAYLOAD\n## Steps\n',s,flags=re.S)
s=re.sub(r'(APPROVE at |CHANGES REQUESTED at )[0-9a-f]{40}',r'\1HEAD',s);s=re.sub(r'(CI is green at this commit \()[0-9a-f]{7}(\))',r'\1HEAD7\2',s);s=re.sub(r'(CI green at )[0-9a-f]{7}(\))',r'\1HEAD7\2',s)
assert hashlib.sha256(s.encode()).hexdigest()=='773a99d73de349ea8f13e93fcf3f8ee86bbd61a8a7b805e59219a5fb0e151c16',s
PYHASH
      ;;
  esac
  pass
}
