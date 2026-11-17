# Item 108: public PR accounting in disposable repositories.
item108_langs() { echo core; }
item108_cases() {
  local c
  for c in reproduction true values no-attrs nested head head-unmark dirty delete rename paths raw-path all-paths empty control failure-exit failure-empty failure-signal malformed-tail malformed-count malformed-path malformed-attr malformed-order malformed-extra raw-value mixed boundary exclusions shape population review-reuse report late-refused late-publish early-create early-title early-body body-edit-fail log-fail version; do echo "v1-108.$c"; done
}
item108_case() {
  EXPECT="item 108: ${CASE#v1-108.}"
  v1_start codex
  CFGS='execution|ci|"off"
execution|review|"local"
pr|warn_lines|4'
  pr_main
  must_accept 'item 108 public contract' cmd "$PY" - "${CASE#v1-108.}" "$(command -v shipcraft)" "$ST" "$CB" "$CW" "$ACEITE/../docs/spec.md" <<'PY108'
import json,os,re,shutil,subprocess,sys
from pathlib import Path
case,binary,st,cb,cw,spec=sys.argv[1:];binary=str(Path(binary).resolve());st=Path(st);cb=Path(cb);cw=Path(cw)
def run(*args,**kw):
 p=subprocess.run(list(map(str,args)),capture_output=True,timeout=65,**kw)
 print('$',repr(args),'rc',p.returncode,repr(p.stdout),repr(p.stderr),flush=True);return p
def git(*args):
 p=run('git',*args);assert p.returncode==0,('fixture git',args,p.stderr);return p.stdout.decode().strip()
def snap(msg):
 git('add','-A');tree=git('write-tree');sha=git('commit-tree',tree,'-p','HEAD','-m',msg);git('update-ref','HEAD',sha);return sha
def data(p):return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def write(p,s):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(s if isinstance(s,bytes) else s.encode())
def policy(key,value):
 p=Path('.shipcraft.toml');s=p.read_text();pattern=r'(?m)^'+key+r'\s*=.*$'
 s=re.sub(pattern,key+' = '+value,s,count=1) if re.search(pattern,s) else s.replace('[pr]\n','[pr]\n'+key+' = '+value+'\n',1)
 p.write_text(s)
realgit=shutil.which('git')
# Private proxy: only check-attr changes behavior; other calls exec real Git.
(cb/'git').write_text('#!'+sys.executable+'\n'+r'''
import json,os,signal,sys
from pathlib import Path
st=Path(__file__).parent/'state';a=sys.argv[1:]
if '--numstat' in a:
 with (st/'git108.jsonl').open('a') as f:f.write(json.dumps(dict(kind='numstat',argv=a))+'\n')
if 'check-attr' in a:
 raw=sys.stdin.buffer.read()
 with (st/'git108.jsonl').open('a') as f:f.write(json.dumps(dict(kind='attr',argv=a,stdin=raw.hex(),cwd=os.getcwd()))+'\n')
 mode=(st/'mode108').read_text() if (st/'mode108').exists() else ''
 if mode=='exit':sys.stderr.buffer.write(b'\nfirst108\r\nprivate second108\n');sys.exit(93)
 if mode=='empty':sys.stderr.buffer.write(b'\n\r\n');sys.exit(94)
 if mode=='signal':os.kill(os.getpid(),signal.SIGTERM)
 if mode=='answer':sys.stdout.buffer.write((st/'answer108').read_bytes());sys.exit(0)
 import subprocess
 p=subprocess.run([REAL,*a],input=raw,capture_output=True)
 sys.stdout.buffer.write(p.stdout);sys.stderr.buffer.write(p.stderr);sys.exit(p.returncode)
os.execv(REAL,[REAL,*a])
'''.replace('REAL',repr(realgit)));(cb/'git').chmod(0o755)
(cb/'gh').rename(cb/'gh108-real')
(cb/'gh').write_text('#!'+sys.executable+'\n'+r'''
import json,os,sys
from pathlib import Path
root=Path(__file__).parent;st=root/'state';a=sys.argv[1:]
mode=(st/'ghfault108').read_text() if (st/'ghfault108').exists() else ''
edit=a[:2]==['pr','edit'];create=a[:2]==['pr','create'];body=any(x in a for x in ('--body','--body-file'))
comment=a[:2] in (['pr','comment'],['pr','review']) or (a[:1]==['api'] and any('/comments' in x or x.endswith('/reviews') for x in a) and any(x in a for x in ('-f','-F','--input')))
if (mode=='create' and create) or (mode=='title' and edit and not body) or (mode=='body' and edit and body) or (mode=='comment' and comment):
 (st/'ghhit108').write_text(mode);print('gh fault108',file=sys.stderr);sys.exit(1)
os.execv(str(root/'gh108-real'),[str(root/'gh108-real'),*a])
''');(cb/'gh').chmod(0o755)
attrs='generated.py linguist-generated\n';basefiles={};files={'generated.py':'GENERATED108 = 1\n'*12};a=0;r=0;mode='';answer=None;reason=None;want_rc=0;late=None;early=None;existing=False;args=[];extra=None
# Each case owns its inputs and expected count; helpers only perform fixture I/O.
if case=='reproduction':extra='repro'
elif case=='true':attrs='generated.py linguist-generated=true\n'
elif case=='values':
 attrs='';files={};a=21
 for i,value in enumerate(('!linguist-generated','-linguist-generated','linguist-generated=false','linguist-generated=TRUE','linguist-generated=yes','linguist-generated=1','linguist-generated=other')):
  attrs+=f'value{i}.py {value}\n';files[f'value{i}.py']='x = 1\n'*3
 files['generated.py']='x = 1\n'*12;attrs+='generated.py linguist-generated\n'
elif case=='no-attrs':attrs=None;a=12
elif case=='nested':
 attrs='nested/** linguist-generated\n';basefiles={'nested/.gitattributes':'keep?.py -linguist-generated\n"space name.py" linguist-generated=true\n'}
 files={'nested/keep1.py':'x=1\n'*3,'nested/deep/gen.py':'x=1\n'*12,'nested/space name.py':'x=1\n'*12};a=3
elif case=='head':
 attrs='generated.py -linguist-generated\n';files['.gitattributes']='generated.py linguist-generated=true\n';a=1;r=1
elif case=='head-unmark':
 files['.gitattributes']='generated.py -linguist-generated\n';a=13;r=1
elif case=='dirty':extra='dirty'
elif case=='delete':basefiles={'generated.py':'old=1\n'*12,'manual.py':'old=1\n'*2};files={'generated.py':None,'manual.py':None};r=2
elif case=='rename':
 attrs='new*.py linguist-generated\n';basefiles={'old.py':''.join(f'x{i}={i}\n' for i in range(30)),'new-out.py':''.join(f'y{i}={i}\n' for i in range(30))}
 files={'old.py':None,'new-in.py':basefiles['old.py']+'added=1\n','new-out.py':None,'manual.py':basefiles['new-out.py']+'added=2\n'};a=1
elif case=='paths':
 attrs='* linguist-generated\n';files={n:'x=1\n'*12 for n in ('space name.py','tab\tname.py','line\nname.py','quote"name.py','back\\name.py','ação.py','bom\ufeff.py','unicode\u2028\u2029.py','cr\rname.py')}
elif case=='raw-path':
 attrs='* linguist-generated\n';files={};extra='raw';policy('review','"off"')
elif case=='all-paths':
 attrs='* linguist-generated\n';basefiles={'old.py':'x=1\n'*30};files={'old.py':None,'pure.py':basefiles['old.py'],'tests/test_extra.py':'assert True\n','Cargo.lock':'lock\n','binary.dat':b'\0binary\n','.shipcraft/cache/meta':'metadata\n','.shipcraft.toml':Path('.shipcraft.toml').read_text()+'\n# changed108\n','generated.py':'x=1\n'*12}
elif case=='empty':attrs=None;files={};extra='empty'
elif case=='control':attrs=None;a=12;extra='control';policy('shape_lines','7')
elif case=='failure-exit':mode='exit';reason='first108';a=12
elif case=='failure-empty':mode='empty';reason='git check-attr failed';files={'generated.py':'x=1\n'*3};a=3
elif case=='failure-signal':mode='signal';reason='git check-attr failed';a=12
elif case=='malformed-tail':extra='tail';reason='git check-attr gave an unreadable answer';a=15;files['manual.py']='x=1\n'*3
elif case=='malformed-count':extra='count';reason='git check-attr gave an unreadable answer';a=15;files['manual.py']='x=1\n'*3
elif case=='malformed-path':extra='path';reason='git check-attr gave an unreadable answer';a=15;files['manual.py']='x=1\n'*3
elif case=='malformed-attr':extra='attr';reason='git check-attr gave an unreadable answer';a=15;files['manual.py']='x=1\n'*3
elif case=='malformed-order':extra='order';reason='git check-attr gave an unreadable answer';a=15;files['manual.py']='x=1\n'*3
elif case=='malformed-extra':extra='extra';reason='git check-attr gave an unreadable answer';a=15;files['manual.py']='x=1\n'*3
elif case=='raw-value':extra='value';a=12
elif case=='mixed':
 policy('ci','"local"')
 basefiles={'generated.py':'old=1\n'*9,'manual.py':'old=1\n'*2};files={'generated.py':'new=1\n'*12,'manual.py':'new=1\n'*3};a=3;r=2
elif case=='boundary':files['manual.py']='x=1\n'*4;a=4
elif case=='exclusions':
 attrs='generated.py linguist-generated\n*.dat linguist-vendored\n*.js linguist-documentation\n'
 files.update({'tests/test_extra.py':'assert True\n'*10,'Cargo.lock':'lock\n'*10,'binary.bin':b'\0x\n'*10,'.shipcraft/cache/meta':'meta\n'*10,'Gemfile.lock':'counts\n'*2,'bundle.min.js':'// generated by fixture108\n','vendor.dat':'text\n'});a=4
elif case=='shape':policy('shape_lines','10');extra='shape'
elif case=='population':
 attrs='population/*.py linguist-generated\ngenerated.py linguist-generated\n';basefiles={f'population/p{i}.py':'x=1\n'*10 for i in range(100)};files={'generated.py':'x=1\n'*11};extra='population'
elif case=='review-reuse':extra='reuse'
elif case=='report':extra='report'
elif case=='late-refused':late='refused';want_rc=1
elif case=='late-publish':late='comment';want_rc=2
elif case=='early-create':mode='exit';early='create';want_rc=2
elif case=='early-title':mode='exit';early='title';existing=True;args=['--title','Changed108'];want_rc=2
elif case=='early-body':mode='exit';early='file';args=['--body',str(cw/'missing108')];want_rc=2
elif case=='body-edit-fail':mode='exit';reason='first108';a=12;existing=True;late='body'
elif case=='log-fail':extra='log'
elif case=='version':
 version=re.search(r'This contract is \*\*([0-9.]+)\*\*',Path(spec).read_text()).group(1)
 assert run(binary,'--version').stdout.decode().split()[1]==version,version
 raise SystemExit(0)
else:raise AssertionError('unrouted '+case)
if attrs is not None:write('.gitattributes',attrs)
for name,value in basefiles.items():write(name,value)
snap('chore: attributes108');git('push','-q','origin','main');git('fetch','-q','origin');git('checkout','-qb','feature/item108')
for name,value in files.items():
 if value is None:Path(name).unlink()
 else:write(name,value)
sha=snap('feat: regenerate108')
if extra=='raw':
 # Build the raw-name tree without asking the host filesystem to represent it.
 blob=subprocess.check_output([realgit,'hash-object','-w','--stdin'],input=b'x=1\n'*12).strip()
 entries=subprocess.check_output([realgit,'ls-tree','-z',sha])+b'100644 blob '+blob+b'\traw-\xff.py\0'
 tree=subprocess.check_output([realgit,'mktree','-z'],input=entries).decode().strip()
 sha=git('commit-tree',tree,'-p',sha,'-m','feat: raw path108');git('update-ref','HEAD',sha)
(st/'sha').write_text(sha+'\n')
# Independent native numstat is only the path-protocol oracle, never the size oracle.
native=subprocess.check_output([realgit,'diff','--numstat','-z','-M','origin/main',sha]);parts=native.split(b'\0');paths=[];i=0
while i<len(parts)-1:
 row=parts[i];i+=1;path=row.split(b'\t',2)[2]
 if path==b'':i+=1;path=parts[i];i+=1
 paths.append(path)
if extra in ('tail','count','path','attr','order','extra','value'):
 records=[[p,b'linguist-generated',b'set'] for p in paths]
 if extra=='extra':answer=b'\0'.join(x for record in records for x in record)+b'\0extra\0'
 elif extra=='value':answer=paths[0]+b'\0linguist-generated\0\xff\0'
 elif extra=='tail':answer=b'\0'.join(x for record in records for x in record) # no final NUL
 elif extra=='count':answer=b'\0'.join(records[0])+b'\0' # first valid record must not partially exclude
 elif extra=='path':records[-1][0]=b'wrong108';answer=b'\0'.join(x for record in records for x in record)+b'\0'
 elif extra=='attr':records[-1][1]=b'linguist-vendored';answer=b'\0'.join(x for record in records for x in record)+b'\0'
 elif extra=='order':answer=b'\0'.join(x for record in reversed(records) for x in record)+b'\0'
 mode='answer';write(st/'answer108',answer)
write(st/'mode108',mode)
if extra=='dirty':
 write('.gitattributes','generated.py -linguist-generated\n');git('add','.gitattributes');write('.gitattributes','generated.py linguist-generated=false\n')
if existing:
 git('push','-q','origin','HEAD');q=run(cb/'gh','pr','create','--title','Title108','--body','Intent108\n');assert q.returncode==0
if late=='refused':write(st/'reviewer.json',json.dumps(dict(mode='changes')))
if late in ('comment','body'):write(st/'ghfault108',late)
if early in ('create','title'):write(st/'ghfault108',early)
if extra=='control':
 # Same routing and proxies: assert real attributes, byte transport, all injected paths and delegation.
 q=run(cb/'git','check-attr','--source='+sha,'-z','--stdin','linguist-generated',input=b'generated.py\0')
 assert q.returncode==0 and q.stdout==b'generated.py\0linguist-generated\0unspecified\0',q.stdout
 for fault,rc in (('exit',93),('empty',94),('signal',-15)):
  write(st/'mode108',fault);q=run(cb/'git','check-attr','--source='+sha,'-z','--stdin','linguist-generated',input=b'generated.py\0');assert q.returncode==rc,(fault,q)
 write(st/'mode108','answer');write(st/'answer108',b'raw\xff\0linguist-generated\0TRUE\0');q=run(cb/'git','check-attr',input=b'raw\xff\0');assert q.stdout==b'raw\xff\0linguist-generated\0TRUE\0'
 write(st/'mode108','');assert git('rev-parse','HEAD')==sha
 git('push','-q','origin','HEAD');q=run(cb/'gh','pr','create','--title','Control108','--body','CONTROL108');assert q.returncode==0
 for fault,argv in (('create',['pr','create','--title','x','--body','x']),('title',['pr','edit','1','--title','x']),('body',['pr','edit','1','--body','x']),('comment',['pr','comment','1','--body','x'])):
  write(st/'ghfault108',fault);q=run(cb/'gh',*argv);assert q.returncode==1 and (st/'ghhit108').read_text()==fault
 write(st/'ghfault108','')
 assert next(iter(json.loads((st/'prs.json').read_text()).values()))['body']=='CONTROL108'
if extra=='log':
 log=Path('.git/shipcraft/runs.jsonl');log.unlink(missing_ok=True);log.mkdir()
before=Path('.git/shipcraft/runs.jsonl').read_bytes() if Path('.git/shipcraft/runs.jsonl').is_file() else b''
(st/'git108.jsonl').unlink(missing_ok=True)
p=run(binary,'pr',*args);o=(p.stdout+p.stderr).decode(errors='replace');stdout=p.stdout.decode(errors='replace')
assert p.returncode==want_rc,o
rs=data(Path('.git/shipcraft/runs.jsonl'));prrows=[x for x in rs if x['layer']=='pr'];events=data(st/'git108.jsonl');qs=[e for e in events if e['kind']=='attr']
warning='shipcraft: generated files were not left out of the size: '
if extra=='repro':
 body=next(iter(json.loads((st/'prs.json').read_text()).values()))['body']
 assert 'Size: 0 product lines against a limit of 4 (+0 / -0, counted as in the PR summary).' in body,body
if early:
 assert warning not in o and not prrows,(o,prrows)
 if early in ('create','title'):assert (st/'ghhit108').read_text()==early
 # Early body read may precede counting; do not force a question it never reaches.
 if early!='file':assert len(qs)==1,events
 raise SystemExit(0)
if extra=='control':
 assert 'Size: 12 product lines against a limit of 4 (+12 / -0, counted as in the PR summary).' in stdout,stdout
 assert prrows[-1]['product_lines']==12 and warning not in o,(prrows,o)
 summaries=[w['text'] for w in data(st/'writes.log') if w['kind']=='comment' and 'Size:' in w['text']]
 assert 'Shape: `generated.py` exceeded 7 lines (new -> 12); consider splitting.' in summaries[-1],summaries
 raise SystemExit(0)
if extra=='empty':assert not qs,events
else:
 assert len(qs)==1,('one attribute question',events)
 q=qs[0];assert q['argv'][q['argv'].index('check-attr'):]==['check-attr','--source='+sha,'-z','--stdin','linguist-generated'],q
 assert bytes.fromhex(q['stdin'])==b''.join(x+b'\0' for x in paths),('raw ordered paths',q,paths)
 assert Path(q['cwd']).resolve()==Path.cwd().resolve(),q
 assert any(e['kind']=='numstat' and '-M' in e['argv'] and e['argv'][-1]==sha for e in events[:events.index(q)]),events
if reason:
 line=warning+reason;ls=stdout.split('\n');assert ls.count(line)==1 and warning not in p.stderr.decode(errors='replace'),o
 sizeidx=next(i for i,s in enumerate(ls) if s.startswith('shipcraft: Size:'))
 assert ls[sizeidx+(2 if a+r>4 else 1)]==line,ls
 assert 'private second108' not in o,o
else:assert warning not in o,o
prs=json.loads((st/'prs.json').read_text());body=next(iter(prs.values()))['body']
line=f'Size: {a+r} product lines against a limit of 4 (+{a} / -{r}, counted as in the PR summary).'
assert 'shipcraft: '+line+'\n' in stdout,(line,stdout)
if late=='body':assert body=='Intent108\n' and (st/'ghhit108').read_text()=='body',body
else:assert line in body,(line,body)
assert ('Above the limit:' in stdout)==(a+r>4),stdout
assert warning not in body,body
comments=data(st/'comments.jsonl');writes=data(st/'writes.log');summaries=[w['text'] for w in writes if w['kind']=='comment' and 'Size:' in w['text']]
if late!='comment':
 assert summaries and f'Size: +{a} / -{r} product lines' in summaries[-1],summaries
 assert warning not in summaries[-1],summaries
if extra!='log':
 assert len(prrows)==1 and prrows[0]['product_lines']==a+r and type(prrows[0]['product_lines']) is int and prrows[0]['warn_lines']==4,prrows
 assert prrows[0]['result']==('refused' if late=='refused' else 'error' if late=='comment' else 'passed'),prrows
 assert Path('.git/shipcraft/runs.jsonl').read_bytes().startswith(before),'rewrote old rows'
 for row in rs:
  if row.get('commit')==sha and row['layer'] in ('ci','review'):assert row['product_lines']==a+r and 'warn_lines' not in row,row
else:assert Path('.git/shipcraft/runs.jsonl').is_dir() and not rs
if extra in ('shape','population'):
 assert 'Shape: `generated.py` exceeded 10 lines (new -> '+str(12 if extra=='shape' else 11)+'); consider splitting.' in summaries[-1],summaries
 assert [x for x in rs if x['layer']=='review'][-1]['shape_warnings']==1,rs
if extra=='reuse':
 reviews=data(st/'reviewer.calls.jsonl');assert len(reviews)==1,reviews
 payload='\n'.join(reviews[0]['files'].values());assert 'GENERATED108 = 1' in payload and line in payload,payload
 old=[x for x in rs if x['layer']=='review'][-1];write(st/'reviewer.json',json.dumps(dict(mode='changes')))
 q=run(binary,'pr');assert q.returncode==0,(q.stdout,q.stderr)
 now=[x for x in data(Path('.git/shipcraft/runs.jsonl')) if x['layer']=='review'][-1]
 assert len(data(st/'reviewer.calls.jsonl'))==1 and now.get('reused') is True and now['diff_sha256']==old['diff_sha256'] and now['text_sha256']==old['text_sha256'],now
if extra=='report':
 log=Path('.git/shipcraft/runs.jsonl');saved=log.read_bytes();q=run(binary,'report','--json');assert q.returncode==0,q.stderr
 size=[x for x in map(json.loads,q.stdout.splitlines()) if x['kind']=='size'];assert size==[dict(kind='size',prs=1,above=0,above_share=0,merged_prs=0,merged_above=0,merged_above_share=None)],size
 assert log.read_bytes()==saved,'report rewrote old rows'
PY108
  pass
}
