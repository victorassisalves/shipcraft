# Item 103: PR size block; only public commands in disposable fixture repositories.
item103_langs() { echo core; }
item103_cases() {
  local c
  for c in control new-empty new-file above boundary default zero base classification replace crlf last-start embedded fence unmatched near-marker unicode lone-cr whitespace rest nonnewline file-override null absent unreadable unreadable-file idempotent title body-edit-fail body-file-fail create-fail title-fail count-fail reuse review-pr-key no-final-newline-key row-refused row-error brief version; do
    echo "v1-103.$c"
  done
}
item103_case() {
  EXPECT="item 103: ${CASE#v1-103.}"
  v1_start codex
  CFGS='execution|ci|"off"
execution|review|"local"
pr|warn_lines|4'
  pr_main
  must_accept 'item 103 public contract' cmd "$PY" - "${CASE#v1-103.}" "$(command -v shipcraft)" "$ST" "$CB" "$CW" "$ACEITE/../docs/spec.md" <<'PY103'
import hashlib,json,os,re,shutil,subprocess,sys
from pathlib import Path
case,binary,st,cb,cw,spec=sys.argv[1:];binary=str(Path(binary).resolve());st=Path(st);cb=Path(cb);cw=Path(cw)
def run(*args):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,timeout=65)
 print('$',repr(args),'rc',p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 return p
def git(*args):
 p=run('git',*args);assert p.returncode==0,('fixture git',args,p.stderr);return p.stdout.decode().strip()
def snap(msg):
 git('add','-A');tree=git('write-tree');sha=git('commit-tree',tree,'-p','HEAD','-m',msg);git('update-ref','HEAD',sha);return sha
def data(p):return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def rows():return data(Path('.git/shipcraft/runs.jsonl'))
def prs():return json.loads((st/'prs.json').read_text()) if (st/'prs.json').exists() else {}
def body():return next(iter(prs().values()))['body']
def calls():return data(st/'calls103.jsonl')
def reviews():return data(st/'reviewer.calls.jsonl')
def policy(key,value):
 p=Path('.shipcraft.toml');s=p.read_text();s=re.sub(r'(?m)^'+key+r'\s*=.*$',key+' = '+value,s);p.write_text(s)
def seed(text):
 git('push','-q','origin','HEAD');p=run(cb/'gh','pr','create','--title','Title103','--body',text);assert p.returncode==0,p.stderr
 (st/'calls103.jsonl').unlink(missing_ok=True)
def invoke(*args):return run(binary,'pr',*args)
def fault(value):(st/'fault103').write_text(value)
def outcome(p):return (p.stdout+p.stderr).decode(errors='replace')
# Transparent wrapper around the existing battery gh protocol, not a new tool format.
(cb/'gh').rename(cb/'gh103-real')
# Python's default text reader normalizes CRLF; gh passes file bytes unchanged.
p=cb/'gh103-real';source=p.read_text();needle='with open(o["body_file"]) as f:'
assert source.count(needle)==1
p.write_text(source.replace(needle, 'with open(o["body_file"], newline="") as f:'))
(cb/'gh').write_text('#!'+sys.executable+'\n'+r'''
import json,os,subprocess,sys
from pathlib import Path
root=Path(__file__).parent;st=root/'state';a=sys.argv[1:]
with (st/'calls103.jsonl').open('a') as f:f.write(json.dumps(a)+'\n')
fault=(st/'fault103').read_text() if (st/'fault103').exists() else ''
edit=a[:2]==['pr','edit'];create=a[:2]==['pr','create'];comment=a[:2] in (['pr','comment'],['pr','review']) or (a[:1]==['api'] and any('/comments' in x or x.endswith('/reviews') for x in a) and any(x in ('-f','-F','--input') for x in a))
hasbody=any(x in ('--body','--body-file') for x in a)
if hasbody:
 if '--body-file' in a:
  with open(a[a.index('--body-file')+1],newline='') as f:submitted=f.read()
 else:submitted=a[a.index('--body')+1]
 with (st/'submitted103.jsonl').open('a') as f:f.write(json.dumps(dict(argv=a,body=submitted))+'\n')
if (fault=='body' and edit and hasbody) or (fault=='title' and edit and not hasbody) or (fault=='create' and create) or (fault=='comment' and comment):
 (st/'hit103').write_text(fault);print('fault103 first line\nsecond line must stay private',file=sys.stderr);sys.exit(1)
if a[:2]==['pr','list'] and (st/'body-shape103').exists():
 p=subprocess.run([str(root/'gh103-real'),*a],capture_output=True)
 d=json.loads(p.stdout);mode=(st/'body-shape103').read_text()
 for row in d:
  if mode=='absent':row.pop('body',None)
  else:row['body']=json.loads(mode)
 print(json.dumps(d));sys.exit(p.returncode)
os.execv(str(root/'gh103-real'),[str(root/'gh103-real'),*a])
''');(cb/'gh').chmod(0o755)
realgit=shutil.which('git')
(cb/'git').write_text('#!'+sys.executable+'\n'+'''import os,sys,json
from pathlib import Path
st=Path('''+repr(str(st))+''');a=sys.argv[1:]
if '--numstat' in a and (st/'count-fault103').exists():
 (st/'count-hit103').touch();print('count fault103',file=sys.stderr);sys.exit(93)
os.execv('''+repr(realgit)+''',['''+repr(realgit)+''',*a])
''');(cb/'git').chmod(0o755)
start='<!-- shipcraft:size -->\n';end='<!-- /shipcraft:size -->\n'
old=start+'Size: old author edit\n'+end
hint='Above the limit: if this change can ship in working slices, the first slice can be its own PR; if it cannot, a line here saying why helps the reviewer.\n'
a=3;r=0;limit=4;rest='Intent103\n';base=rest;args=[];new=False;expected=None
# Fixed base product lines make removals independently observable.
Path('remove103.py').write_text('old103 = 1\nold103 = 2\n');snap('chore: base size103');git('push','-q','origin','main');git('fetch','-q','origin')
git('checkout','-qb','feature/item103');Path('product103.py').write_text('x103 = 1\n'*3)
if case=='control':
 seed('CONTROL103\r\n')
 assert body()=='CONTROL103\r\n',prs()
 assert data(st/'submitted103.jsonl')[-1]['body']=='CONTROL103\r\n'
 (cw/'control103').write_bytes(b'FILE CONTROL103\r\n\r\n');p=run(cb/'gh','pr','edit','1','--body-file',cw/'control103');assert p.returncode==0 and body()=='FILE CONTROL103\r\n\r\n'
 p=run(cb/'gh','pr','edit','1','--body','CONTROL103\r\n');assert p.returncode==0
 fault('body');p=run(cb/'gh','pr','edit','1','--body','bad');assert p.returncode==1 and (st/'hit103').read_text()=='body' and body()=='CONTROL103\r\n'
 fault('title');p=run(cb/'gh','pr','edit','1','--title','blocked');assert p.returncode==1 and (st/'hit103').read_text()=='title'
 fault('create');p=run(cb/'gh','pr','create','--title','blocked','--body','blocked');assert p.returncode==1 and (st/'hit103').read_text()=='create'
 fault('comment');p=run(cb/'gh','api','repos/acme/proj/issues/1/comments','-f','body=blocked');assert p.returncode==1 and (st/'hit103').read_text()=='comment'
 fault('');(st/'body-shape103').write_text('false');p=run(cb/'gh','pr','list','--json','body');assert json.loads(p.stdout)[0]['body'] is False
 (st/'count-fault103').touch();p=run(cb/'git','diff','--numstat','main','HEAD');assert p.returncode==93 and (st/'count-hit103').exists()
 (st/'count-fault103').unlink();p=run(cb/'git','rev-parse','HEAD');assert p.returncode==0
 raise SystemExit(0)
elif case=='new-empty':new=True;rest='';base=''
elif case=='new-file':new=True;rest='File103\n\n';base=rest;args=['--body',cw/'input103']
elif case=='above':Path('remove103.py').unlink();r=2
elif case=='boundary':Path('product103.py').write_text('x103 = 1\n'*4);a=4
elif case=='default':
 Path('product103.py').unlink() # Keep the pending feature addition out of main's config commit.
 git('checkout','main');p=Path('.shipcraft.toml');p.write_text(re.sub(r'(?m)^warn_lines\s*=.*\n','',p.read_text()));snap('chore: default limit');git('push','-q','origin','main');git('checkout','feature/item103');Path('product103.py').write_text('x103 = 1\n'*3);limit=500
elif case=='zero':Path('product103.py').unlink();Path('tests/test_zero103.py').write_text('def test_zero103():\n assert True\n');a=0
elif case=='base':
 Path('product103.py').unlink() # The shared feature snapshot below commits the product addition.
 policy('warn_lines','999');git('checkout','main');policy('warn_lines','2');snap('chore: moved base policy');git('push','-q','origin','main');git('checkout','feature/item103');Path('product103.py').write_text('x103 = 1\n'*3);policy('warn_lines','999');limit=2
elif case=='classification':
 Path('tests/test_helper103.py').write_text('# excluded\n'*20);Path('Cargo.lock').write_text('excluded\n'*20);Path('binary103').write_bytes(b'\0x\n'*20);Path('.shipcraft/cache').mkdir(exist_ok=True);Path('.shipcraft/cache/meta').write_text('excluded\n'*20);Path('Gemfile.lock').write_text('counts\n'*2);a=5
elif case=='replace':base=rest+'\n'+old.rstrip('\n')
elif case=='crlf':rest='\ufeffIntent103\r\n';base=rest+'\n'+old.replace('\n','\r\n')
elif case=='last-start':rest='Intent103\n'+old+'Retained103\n';base=rest+'\n'+old
elif case=='embedded':rest='Intent103\n'+old+'after103\n';base=rest
elif case=='fence':rest='```html\n'+old+'```\n';base=rest
elif case=='unmatched':rest='Intent103\n'+start+'unfinished103\n';base=rest
elif case=='near-marker':rest='Intent103\n <!-- shipcraft:size -->\nold\n'+end;base=rest
elif case=='unicode':rest='Intent103\u2028'+start+'old\u2029'+end;base=rest
elif case=='lone-cr':rest='Intent103\r'+start+'old\r'+end;base=rest
elif case=='whitespace':base=rest+'\n'+old+' \t\r\n\r\n'
elif case=='rest':rest=' \tIntent103\r\n\n\n';base=rest+'\n'+old
elif case=='nonnewline':rest='Intent103';base=rest
elif case=='file-override':base='Existing103\n'+old;rest='Replacement103\n';args=['--body',cw/'input103','--title','New103']
elif case=='null':rest='';base='seed103';(st/'body-shape103').write_text('null')
elif case=='absent':rest='';base='seed103';(st/'body-shape103').write_text('absent')
elif case=='unreadable':base='Seed unreadable103\n';(st/'body-shape103').write_text('false')
elif case=='unreadable-file':base='Seed unreadable103\n';rest='Readable file103\n';args=['--body',cw/'input103'];(st/'body-shape103').write_text('{"not":"string"}')
elif case=='idempotent':pass
elif case=='title':args=['--title','Changed title103']
elif case=='body-edit-fail':fault('body')
elif case=='body-file-fail':fault('body');args=['--body',cw/'input103']
elif case=='create-fail':fault('create');new=True;rest='';base=''
elif case=='title-fail':fault('title');args=['--title','Changed title103']
elif case=='count-fail':(st/'count-fault103').touch();args=['--body',cw/'input103']
elif case=='reuse':pass
elif case=='review-pr-key':base=rest+'\n'+old
elif case=='no-final-newline-key':rest='Intent103';base=rest
elif case=='row-refused':(st/'reviewer.json').write_text(json.dumps(dict(mode='changes')))
elif case=='row-error':fault('comment')
elif case=='brief':pass
elif case=='version':
 version=re.search(r'This contract is \*\*([0-9.]+)\*\*',Path(spec).read_text()).group(1)
 assert run(binary,'--version').stdout.decode().split()[1]==version,version
 raise SystemExit(0)
else:raise AssertionError('unrouted '+case)
sha=snap('feat: product size103');(st/'sha').write_text(sha+'\n')
line=f'Size: {a+r} product lines against a limit of {limit} (+{a} / -{r}, counted as in the PR summary).\n'
block=start+line+(hint if a+r>limit else '')+end
expected=block if rest=='' else rest+('' if rest.endswith('\n') else '\n')+'\n'+block
(cw/'input103').write_bytes((rest+'\n'+old if case=='new-file' else rest).encode())
if not new:seed(base)
if case=='idempotent':
 d=prs();next(iter(d.values()))['body']=expected;(st/'prs.json').write_text(json.dumps(d))
if case in ('reuse','no-final-newline-key'):
 p=run(binary,'review','--pr','1');assert p.returncode==0,outcome(p)
 (st/'reviewer.json').write_text(json.dumps(dict(mode='changes')))
if case=='review-pr-key':
 p=run(binary,'review','--pr','1');assert p.returncode==0,outcome(p)
 rr=[x for x in rows() if x['layer']=='review'][-1]
 assert rr['text_sha256']==hashlib.sha256(b'Title103\0'+rest.encode()).hexdigest(),rr
 raise SystemExit(0)
p=invoke(*args);o=outcome(p);cs=calls();edits=[x for x in cs if x[:2]==['pr','edit']];creates=[x for x in cs if x[:2]==['pr','create']];prrows=[x for x in rows() if x['layer']=='pr']
if case=='count-fail':
 assert p.returncode==2 and (st/'count-hit103').exists(),o
 assert any(x[:2]==['pr','list'] for x in cs) and not edits and not creates,cs
 assert body()==base and not prrows,(body(),prrows)
elif case=='create-fail':
 assert p.returncode==2 and (st/'hit103').read_text()=='create' and not prs(),(o,prs())
 assert len(creates)==1,cs
 assert data(st/'submitted103.jsonl')[-1]['body']==expected,data(st/'submitted103.jsonl')
 # Failure precedes a known PR and retains today's absence of a PR row.
 assert not prrows,prrows
elif case in ('body-file-fail','title-fail'):
 assert p.returncode==2 and (st/'hit103').exists() and body()==base,(o,cs)
 assert len(edits)==1,cs
 if case=='body-file-fail':assert data(st/'submitted103.jsonl')[-1]['body']==expected,data(st/'submitted103.jsonl')
 assert not prrows,prrows
elif case=='body-edit-fail':
 assert (st/'hit103').exists(),'body-only edit never attempted'
 assert p.returncode==0 and body()==base,(o,body())
 warnings=[s for s in o.split('\n') if s.startswith('shipcraft: the size line could not be written to the PR body: ')]
 assert len(warnings)==1 and warnings[0].endswith('fault103 first line'),o
 assert 'second line must stay private' not in o,o
 b=next(v for k,v in reviews()[-1]['files'].items() if k.endswith('/brief.md'));assert base in b and block not in b,b
elif case=='unreadable':
 assert p.returncode==0 and not edits and body()==base,(o,cs)
 assert 'shipcraft: the size line was not written: the PR body could not be read\n' in o,o
else:
 if case=='row-refused':assert p.returncode==1,o
 elif case=='row-error':assert p.returncode==2 and (st/'hit103').exists(),o
 elif case=='no-final-newline-key':assert p.returncode==1 and len(reviews())==2,(o,reviews())
 else:assert p.returncode==0,o
 assert body()==expected,('exact body',repr(body()),repr(expected))
 if case=='idempotent':assert not edits,cs
 elif case=='title':
  assert len(edits)==2 and '--title' in edits[0] and '--body' not in edits[0] and '--body-file' not in edits[0] and '--title' not in edits[1],cs
 elif case=='file-override':assert len(edits)==1 and '--title' in edits[0],cs
 elif new:assert len(creates)==1 and not edits,cs
 else:assert len(edits)==1 and '--title' not in edits[0],cs
 if case=='reuse':assert len(reviews())==1 and [x for x in rows() if x['layer']=='review'][-1].get('reused') is True,rows()
 if case=='brief':
  b=next(v for k,v in reviews()[-1]['files'].items() if k.endswith('/brief.md'));assert expected in b,b
# Every late result keeps the PR row's numeric measurements and old layer fields.
if prrows:
 assert len(prrows)==1,prrows
 row=prrows[0];assert type(row.get('product_lines')) is int and row['product_lines']==a+r,row
 assert type(row.get('warn_lines')) is int and row['warn_lines']==limit,row
 assert row['locks']==[] and row['queue_secs'] is None,row
 if case=='row-refused':assert row['result']=='refused',row
 if case=='row-error':assert row['result']=='error',row
 for row in rows():
  if row['layer']!='pr':assert 'warn_lines' not in row,row
if case not in ('count-fail','create-fail','body-file-fail','title-fail'):
 assert len(prrows)==1,prrows
 ls=o.splitlines();i=next(i for i,s in enumerate(ls) if s.startswith('shipcraft: PR #'))
 assert ls[i+1]=='shipcraft: '+line.rstrip('\n'),ls
 if a+r>limit:assert ls[i+2]=='shipcraft: '+hint.rstrip('\n'),ls
 else:assert 'shipcraft: '+hint.rstrip('\n') not in ls,ls
PY103
  pass
}
