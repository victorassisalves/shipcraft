# Item 130, spec febd97e. Offline Git and gh only; never read implementation.
item130_langs() { echo core; }
item130_cases() {
  local c
  for c in no-origin main detached master neither pr-merge merge waiver precedence upstream read triage none empty null fallback-name controls-json wrong-types missing malformed gh-error gh-empty gh-missing write maintain admin-control merge-control multi-stop multi-pass pushurl rewrite userinfo scp url-bytes duplicate-json later-failure git-failure docs-readme docs-refusals stub-control; do echo "v1-130.$c"; done
}
item130_case() {
  EXPECT="item 130: ${CASE#v1-130.}"
  v1_start
  must_accept 'origin preflight contract' cmd "$PY" - "${CASE#v1-130.}" "$(command -v shipcraft)" "$CB" "$CW" "$ACEITE/.." <<'PY130'
import json,os,re,shutil,subprocess,sys
from pathlib import Path
case,binary,cb,cw,source=sys.argv[1:];binary=str(Path(binary).resolve());cb=Path(cb);cw=Path(cw);source=Path(source);st=cb/'state'
os.environ['GIT_ALLOW_PROTOCOL']='file'
def run(*a,**kw):
 p=subprocess.run(list(map(str,a)),capture_output=True,text=True,timeout=60,**kw)
 print('$',repr(a),'exit',p.returncode,repr(p.stdout),repr(p.stderr),flush=True);return p
def git(*a,**kw):
 p=run('git',*a,**kw);assert p.returncode==0,('fixture git',a,p.stderr);return p.stdout.strip()
def put(p,s):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
def records(p):return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def content(p):return p.read_bytes() if p.is_file() else None
root=cw/'project130';root.mkdir();os.chdir(root)
git('init','-q','-b','main');git('config','user.name','Acceptance');git('config','user.email','acceptance@example.invalid')
put('.shipcraft.toml','shipcraft_min = "0.0"\nlang = "python"\nrunner = "pytest"\n[execution]\nci = "off"\nreview = "off"\n[[suite]]\nroot = "."\ncommand = "pytest -q --junitxml={junit} tests"\nglobs = ["tests/**"]\n')
put('tests/test_ok.py','def test_ok():\n    assert True\n');git('add','-A');git('commit','-qm','base130');base=git('rev-parse','HEAD')
origin=cb/'origin.git';git('init','-q','--bare',origin);git('--git-dir='+str(origin),'symbolic-ref','HEAD','refs/heads/main');put(st/'origin',str(origin))
git('remote','add','origin',origin);git('push','-q','origin','main');git('fetch','-q','origin');git('remote','set-head','origin','main')
git('checkout','-qb','feat');put('product.py','value = 130\n');git('add','-A');git('commit','-qm','feature130');head=git('rev-parse','HEAD')
p=run(binary,'ci','--base','main');assert p.returncode==0,('fixture CI',p.stderr)
assert records(root/'.git/shipcraft/runs.jsonl'), 'fixture CI produced no real measurement'
# Sentinel is created only on origin after initial fetch: even a no-op fetch is observable.
git('--git-dir='+str(origin),'update-ref','refs/heads/unfetched130',base)
args=['pr','--title','t'];kind='deny';name='acme/proj';permission='READ';reason='gh did not return your permission on origin';base_name='main';answer={'fields':{'viewerPermission':'READ'}};urls=[str(origin)];expected_urls=list(urls);fault={};no_origin=False;success=False;control=False;variants=None
if case=='no-origin':no_origin=True;kind='absent'
elif case=='main':no_origin=True;kind='absent';git('checkout','-q','main')
elif case=='detached':no_origin=True;kind='absent';git('checkout','-q','--detach')
elif case=='master':no_origin=True;kind='absent';git('branch','-m','main','master');base_name='master'
elif case=='neither':no_origin=True;kind='absent';git('tag','main','main');git('branch','-D','main');base_name='<base branch>'
elif case=='pr-merge':no_origin=True;kind='absent';args+=['--merge','--body',str(cw/'absent-body')]
elif case=='merge':
 no_origin=True;kind='absent';args=['merge','1'];variants=[{'command':['merge','1']},{'command':['merge','1','--no-review','explicit waiver']}]
elif case=='waiver':no_origin=True;kind='waiver';args=['merge','1','--no-review','']
elif case=='precedence':
 no_origin=True;kind='absent';put('.shipcraft.toml','invalid config');args+=['--body',str(cw/'absent-body')]
elif case=='upstream':no_origin=True;kind='absent';git('remote','add','upstream',origin)
elif case=='read':
 git('branch','release/130','main');git('update-ref','refs/remotes/origin/release/130',base);git('symbolic-ref','refs/remotes/origin/HEAD','refs/remotes/origin/release/130');base_name='release/130'
elif case=='triage':
 permission='TRIAGE';answer={'fields':{'viewerPermission':'TRIAGE'}};git('symbolic-ref','--delete','refs/remotes/origin/HEAD');git('branch','-m','main','master');base_name='master'
elif case=='none':
 permission='NONE';answer={'fields':{'viewerPermission':'NONE'}};git('symbolic-ref','--delete','refs/remotes/origin/HEAD');git('branch','-D','main');base_name='<base branch>'
elif case=='empty':permission='none';answer={'fields':{'viewerPermission':''}}
elif case=='null':permission='none';answer={'fields':{'viewerPermission':None}}
elif case=='fallback-name':
 name='a GitHub repository';variants=[{'fields':{'viewerPermission':'READ','nameWithOwner':v}} for v in ('',None,42,[],{})]+[{'fields':{'viewerPermission':'READ'},'omit':['nameWithOwner']}]
elif case=='controls-json':
 name='acme  proj ';permission='R E A D ';answer={'fields':{'nameWithOwner':'acme\n\tproj\x85','viewerPermission':'R\rE\x00A\x7fD\x9f'}}
elif case=='wrong-types':kind='unverified';variants=[{'fields':{'viewerPermission':v}} for v in (True,7,[],{})]+[{'raw':v} for v in ('null','[]','"WRITE"','42')]
elif case=='missing':kind='unverified';answer={'omit':['viewerPermission']}
elif case=='malformed':kind='unverified';variants=[{'raw':s} for s in ('not-json','{"viewerPermission":','\ufeff{"viewerPermission":"WRITE"}')]
elif case=='gh-error':
 kind='unverified';answer={'exit':3,'stderr':' \n first\terror\x85line\nprivate second line\n','stdout':'other output'};reason='first error line'
 variants=[None,{'exit':2,'stderr':' stderr130 ','stdout':' stdout130 ','oracle_reason':'stderr130 stdout130'},{'exit':1,'stderr':'','stdout':' output-only130\nnot shown','oracle_reason':'output-only130'}]
elif case=='gh-empty':kind='unverified';answer={'exit':1,'stderr':' \n','stdout':'\t '};reason='gh failed with no message'
elif case=='gh-missing':kind='missing-gh';(cb/'gh').unlink()
elif case=='write':success=True;answer={'fields':{'viewerPermission':'WRITE'}}
elif case=='maintain':success=True;answer={'fields':{'viewerPermission':'MAINTAIN'}};args+=['--merge']
elif case=='admin-control':success=True;control=True;answer=None
elif case=='merge-control':
 success=True;control=True;args=['merge','1'];git('push','-q','origin','feat');p=run(cb/'gh','pr','create','--title','seed130','--body','seed130','--head','feat');assert p.returncode==0
elif case=='multi-stop':
 urls=[str(origin),str(cb/'denied.git'),str(cb/'never.git')];expected_urls=urls[:2];answer=None
elif case=='multi-pass':
 success=True;second=cb/'second.git';git('clone','-q','--bare',origin,second);git('push','-q',second,'HEAD:refs/heads/feat');urls=[str(origin),str(second)];expected_urls=urls;answer={'fields':{'viewerPermission':'WRITE'}}
elif case=='pushurl':urls=[str(cb/'push-only.git')];expected_urls=urls
elif case=='rewrite':
 urls=['alias130:project'];expected_urls=[str(cb/'rewritten.git')];git('config','url.'+str(cb/'rewritten.git')+'.insteadOf','alias130:project')
elif case=='userinfo':urls=['https://alice:secret130@github.com/acme/proj.git'];expected_urls=['https://github.com/acme/proj.git']
elif case=='scp':urls=['git@github.com:acme/proj.git'];expected_urls=urls
elif case=='url-bytes':
 # Git prints these exact real configuration values; no synthetic Git parser output.
 urls=[str(cb/' leading and trailing ')+ '\r'];expected_urls=[urls[0][:-1]]
 variants=[None,{'git':{'output_hex':b'\n  local-\xff  \r\n\n'.hex()},'expected_urls':['  local-\ufffd  ']},{'git':{'output_hex':b'\n\r\n'.hex()},'expected_urls':[],'kind':'unverified','oracle_reason':'origin has no push URL'}]
elif case=='duplicate-json':answer={'raw':'{"viewerPermission":"WRITE","nameWithOwner":"acme/proj","viewerPermission":"READ"}'}
elif case=='later-failure':success=True;kind='later';answer={'fields':{'viewerPermission':'WRITE'}};args+=['--body',str(cw/'absent-body')]
elif case=='git-failure':
 kind='git-error';fault={'exit':128};variants=[{'git':{'exit':1}},{'git':{'exit':128}},{'git':{'signal':15}}]
elif case=='stub-control':
 # Same executable, same exact-URL dispatch and logs used by product cases.
 for value in ('READ','TRIAGE','WRITE','MAINTAIN','',None,False,3,[],{}):
  put(st/'repo-view.json',json.dumps({str(origin):{'fields':{'viewerPermission':value}}}))
  p=run(cb/'gh','repo','view',origin,'--json','nameWithOwner,viewerPermission');assert p.returncode==0 and json.loads(p.stdout)=={'nameWithOwner':'acme/proj','viewerPermission':value},p.stdout
 put(st/'repo-view.json',json.dumps({'*':{'omit':['viewerPermission']}}));p=run(cb/'gh','repo','view',origin,'--json','nameWithOwner,viewerPermission');assert json.loads(p.stdout)=={'nameWithOwner':'acme/proj'}
 put(st/'repo-view.json',json.dumps({'*':{'raw':'bad-json\n'}}));p=run(cb/'gh','repo','view',origin,'--json','viewerPermission');assert p.stdout=='bad-json\n' and p.returncode==0
 put(st/'repo-view.json',json.dumps({'*':{'exit':7,'stdout':'out130','stderr':'err130'}}));p=run(cb/'gh','repo','view',origin,'--json','viewerPermission');assert (p.returncode,p.stdout,p.stderr)==(7,'out130','err130')
 (st/'repo-view.json').unlink();p=run(cb/'gh','repo','view',origin,'--json','viewerPermission');assert json.loads(p.stdout)=={'viewerPermission':'ADMIN'}
 assert records(st/'calls.log')[-1]['argv']==['repo','view',str(origin),'--json','viewerPermission'] and not records(st/'writes.log')
 success=True;control=True;answer=None
elif case=='docs-readme':
 sentence='Optional, for `shipcraft pr` and `shipcraft merge`: a GitHub remote named `origin` and `gh` logged in; for `shipcraft pr`, also write access to `origin` for the `gh` account, which `pr` checks before it pushes anything. Without a remote, the work stays local and `shipcraft ci --base <base>` is its finish line.'
 assert (source/'README.md').read_text().count(sentence)==1,'README requirement sentence missing or duplicated'
 raise SystemExit(0)
elif case=='docs-refusals':
 text=(source/'docs/spec.md').read_text().split('## 7. Refusals',1)[1].split('## 8.',1)[0]
 for row in ('| `no-origin` | `pr` or `merge` in a repository with no remote named `origin` (item 130). |','| `origin-not-writable` | `pr` when GitHub says your permission on origin is below write (item 130). |','| `origin-unverified` | `pr` when `gh` cannot say whether you can push to origin (item 130). |'):assert text.count(row)==1,row
 assert text.index('| `no-git`')<text.index('| `no-origin`')<text.index('| `no-report`') and text.index('| `no-review-without-reason`')<text.index('| `origin-not-writable`')<text.index('| `origin-unverified`')<text.index('| `pr-from-fork`')
 assert 'writes none' in text and 'before its row exists' in text
 raise SystemExit(0)
else:raise AssertionError('unrouted '+case)
if no_origin:git('remote','remove','origin');expected_urls=[]
else:
 for u in urls:git('config','--add','remote.origin.pushurl',u)
if case=='multi-stop':put(st/'repo-view.json',json.dumps({urls[0]:{'fields':{'viewerPermission':'ADMIN'}},urls[1]:{'fields':{'viewerPermission':'READ'}},urls[2]:{'exit':99,'stderr':'must not run'}}))
elif answer is not None:put(st/'repo-view.json',json.dumps({'*':answer}))
# Transparent Git observer. Non-file transports are also disabled in the environment.
realgit=shutil.which('git');put(st/'gitfault130',json.dumps(fault))
put(cb/'git','#!'+sys.executable+'\n'+r'''
import json,os,signal,sys
from pathlib import Path
st=Path(__file__).parent/'state';a=sys.argv[1:]
with (st/'git130.jsonl').open('a') as f:f.write(json.dumps(a)+'\n')
fault=json.loads((st/'gitfault130').read_text())
# Match the subcommand after Git's global options; preserve argv for forwarding.
i=0
while i<len(a) and a[i].startswith('-'):
 if a[i] in ('-C','-c','--git-dir','--work-tree','--namespace','--config-env','--super-prefix'):i+=2
 else:i+=1
if a[i:]==['remote','get-url','--push','--all','origin'] and fault:
 if 'output_hex' in fault:sys.stdout.buffer.write(bytes.fromhex(fault['output_hex']));sys.exit(0)
 print('git130 lookup failed',file=sys.stderr,flush=True)
 if 'signal' in fault:os.kill(os.getpid(),fault['signal'])
 sys.exit(fault['exit'])
os.execv(REAL,[REAL,*a])
'''.replace('REAL',repr(realgit)));(cb/'git').chmod(0o755)
if case=='stub-control':
 assert git('rev-parse','HEAD')==head
 for prefix in ([],['-C',str(root),'--literal-pathspecs'],['-c','probe130.value=remote','--no-pager'],['--git-dir='+str(root/'.git'),'--no-pager'],['--git-dir',str(root/'.git'),'--work-tree',str(root)]):
  lookup=['git',*prefix,'remote','get-url','--push','--all','origin']
  for code in (1,128):
   put(st/'gitfault130',json.dumps({'exit':code}));probe=run(*lookup);assert probe.returncode==code and probe.stderr=='git130 lookup failed\n'
  put(st/'gitfault130',json.dumps({'output_hex':b'\n  byte-\xff  \r\n'.hex()}));probe=subprocess.run(lookup,capture_output=True);assert probe.returncode==0 and probe.stdout==b'\n  byte-\xff  \r\n'
  put(st/'gitfault130',json.dumps({'signal':15}));probe=run(*lookup);assert probe.returncode==-15 and probe.stderr=='git130 lookup failed\n'
  assert git(*prefix,'rev-parse','HEAD')==head
  put(st/'gitfault130','{}');probe=run(*lookup);assert probe.returncode==0 and probe.stdout==str(origin)+'\n'
log=root/'.git/shipcraft/runs.jsonl';before=content(log);before_refs=git('--git-dir='+str(origin),'show-ref');before_fetch=content(root/'.git/FETCH_HEAD')
for variant in (variants or [None]):
 if variant is not None:
  if 'git' in variant:put(st/'gitfault130',json.dumps(variant['git']))
  elif 'command' in variant:args=variant['command']
  else:put(st/'repo-view.json',json.dumps({'*':variant}))
  if 'expected_urls' in variant:expected_urls=variant['expected_urls']
  if 'kind' in variant:kind=variant['kind']
  if 'oracle_reason' in variant:reason=variant['oracle_reason']
 for n in ('calls.log','writes.log','git130.jsonl'):(st/n).unlink(missing_ok=True)
 p=run(binary,*args);calls=records(st/'calls.log');argv=[r['argv'] for r in calls];trace=records(st/'git130.jsonl')
 if success:
  if kind=='later':
   assert p.returncode==2 and 'absent-body' in p.stderr and content(log)==before,(p.returncode,p.stderr)
   assert not any('push' in a for a in trace),trace
  else:
   assert p.returncode==0,(p.returncode,p.stderr)
   assert git('--git-dir='+str(origin),'rev-parse','refs/heads/feat')==head
   ps=json.loads((st/'prs.json').read_text());entry=next(iter(ps.values()))
   assert entry['state']==('MERGED' if args[0]=='merge' or '--merge' in args else 'OPEN'),entry
   rs=records(log);assert any(r['layer']==args[0] and r['result']=='passed' for r in rs),rs
   if args[0]=='pr':
    assert f'shipcraft: feat published to origin ({git("rev-parse","--short","HEAD")})' in p.stdout,p.stdout
    assert {r['context'] for r in records(st/'statuses.jsonl') if r['state']=='success'}=={'shipcraft/ci','shipcraft/review'}
    assert any(r['kind']=='pr-create' for r in records(st/'writes.log'))
  checks=[a for a in argv if a[:2]==['repo','view'] and a[-1]=='nameWithOwner,viewerPermission']
  if control:
   if args[0]=='merge':assert not checks,checks
   else:assert entry['title']=='t' and 'value = 130' in (root/'product.py').read_text()
  else:
   assert checks==[['repo','view',u,'--json','nameWithOwner,viewerPermission'] for u in expected_urls],checks
   assert argv[0]==checks[0],argv
  if len(urls)==2:assert git('--git-dir='+urls[1],'rev-parse','refs/heads/feat')==head
  continue
 if kind=='waiver':
  assert p.returncode==1 and len(p.stderr.splitlines())==3 and 'reason' in p.stderr.lower(),p.stderr
 elif kind=='git-error':
  assert p.returncode==2 and p.stderr.startswith('shipcraft: error:') and 'git130 lookup failed' in p.stderr,p.stderr
 else:
  if kind=='absent':
   what='this repository has no remote named origin, so shipcraft '+args[0]+(' has nowhere to open a PR' if args[0]=='pr' else ' has no PR to merge')
   why='pr pushes the branch to origin and opens the PR on GitHub; nothing was fetched, pushed or sent' if args[0]=='pr' else 'merge reads the PR and its statuses on GitHub through origin; nothing was fetched or sent'
   nxt=f'the work stays local, and `shipcraft ci --base {base_name}` is your finish line; to open PRs, add a GitHub repository you can push to: git remote add origin <url>'
  elif kind=='deny':
   what=f'origin is {name}, where your GitHub permission is {permission}, so shipcraft pr cannot push to it'
   why="pr pushes the branch to origin before anything else, and a branch pushed to a repository that is not yours fails or lands in someone else's project; nothing was fetched, pushed or sent"
   nxt=f"point origin's push URL at a GitHub repository you can push to, such as your fork (git remote set-url origin <url>; when git remote -v shows other push URLs, git remote set-url --push origin <url>), or keep the work local: `shipcraft ci --base {base_name}` is your finish line; for a project that does not use Shipcraft, `shipcraft export --base {base_name} <new branch>` first makes a branch without Shipcraft's files"
  else:
   what='shipcraft pr could not confirm that you can push to origin: '+reason
   why='pr pushes only to a repository GitHub says you can write to, and every later step needs gh too; nothing was fetched, pushed or sent'
   nxt=f'check that origin is a GitHub repository (git remote get-url origin) and that gh is logged in (gh auth status), then run shipcraft pr again; or keep the work local: `shipcraft ci --base {base_name}` is your finish line'
  assert p.returncode==1,('expected refusal exit 1',p.returncode,p.stderr)
  if kind=='missing-gh':
   lines=p.stderr.splitlines();assert len(lines)==3 and lines[0].startswith('shipcraft refused: shipcraft pr could not confirm that you can push to origin: run gh: '),p.stderr
   assert lines[1:]==['Why: '+why,'Next: '+nxt],p.stderr
  else:assert p.stderr=='shipcraft refused: '+what+'\nWhy: '+why+'\nNext: '+nxt+'\n',p.stderr
 assert p.stdout=='' and content(log)==before,(p.stdout,content(log))
 assert not records(st/'writes.log') and not any('fetch' in a or 'push' in a for a in trace),trace
 assert content(root/'.git/FETCH_HEAD')==before_fetch
 assert git('--git-dir='+str(origin),'show-ref')==before_refs
 expected=[] if kind in ('absent','waiver','git-error','missing-gh') else [['repo','view',u,'--json','nameWithOwner,viewerPermission'] for u in expected_urls]
 assert argv==expected,argv
 assert all(r['cwd']==str(root) for r in calls),calls
 assert 'secret130' not in p.stdout+p.stderr+json.dumps(argv),'credential leaked'
PY130
  pass
}
