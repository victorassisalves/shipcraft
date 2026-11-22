# Item 144, spec 3aaede0; real Git, offline SSH transport and battery gh.
item144_langs() { echo core; }
item144_cases() {
  local c
  for c in repro single existing review github inherited pushurl ssh-url alias ssh-github three-segments multi-url git-error ssh-failure ssh-no-host owner-case beside-ci create-error summary-error merge merge-waiver pr-merge merge-closed merge-inherited local-control merge-error merge-waiver-error merge-git-error review-control report-control ci-control status-control export-control suite-control docs stub-control permission-control transport-control fault-control; do echo "v1-144.$c"; done
}
item144_case() {
  EXPECT="item 144: ${CASE#v1-144.}"; v1_start codex
  must_accept 'origin repository selection' cmd "$PY" - "${CASE#v1-144.}" "$(command -v shipcraft)" "$CB" "$CW" "$ACEITE/.." <<'PY144'
import json,os,re,shlex,shutil,subprocess,sys,time
from pathlib import Path
case,binary,cb,cw,source=sys.argv[1:];cb=Path(cb);cw=Path(cw);st=cb/'state';source=Path(source);binary=str(Path(binary).resolve())
def run(*a,**kw):
 p=subprocess.run(list(map(str,a)),capture_output=True,text=True,timeout=90,**kw)
 print('$',shlex.join(map(str,a)),'exit',p.returncode,repr(p.stdout),repr(p.stderr),flush=True);return p
def git(*a,**kw):
 p=run('git',*a,**kw);assert p.returncode==0,('fixture git',a,p.stderr);return p.stdout.strip()
def put(p,s):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
def records(p):return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def snapshot(msg):
 git('add','-A');sha=git('commit-tree',git('write-tree'),'-p',git('rev-parse','HEAD'),input=msg+'\n');git('update-ref','HEAD',sha);return sha
initial=git('rev-parse','HEAD')
for key in ('GH_REPO','GH_HOST'):os.environ.pop(key,None)
url='git@github.example144:acme/proj.git';mapped='github.example144';ci='off';review='off';args=['pr','--title','Item144'];upstream=True
expected_repo='github.example144/acme/proj';expected_host='github.example144';want=0;seed=False;fault='';inherit=False;ssh_mode='ok';unrelated=False
if case=='repro':pass
elif case=='single':upstream=False
elif case=='existing':seed=True
elif case=='review':review='local'
elif case=='github':ci='github';review='local'
elif case=='inherited':inherit=True
elif case=='pushurl':pass
elif case=='ssh-url':url='ssh://git@github.example144:2222/acme/proj.git/'
elif case=='alias':url='git@work-gh:acme/proj.git';mapped='github.com';expected_repo='github.com/acme/proj';expected_host='github.com'
elif case=='ssh-github':url='git@SSH.GITHUB.COM:acme/proj.git';mapped='SSH.GITHUB.COM';expected_repo='github.com/acme/proj';expected_host='github.com'
elif case=='three-segments':url='git@github.example144:group/acme/proj.git';inherit=True;expected_repo='other/repo';expected_host='other.example'
elif case=='multi-url':pass
elif case=='git-error':fault='git';want=2
elif case=='ssh-failure':ssh_mode='fail'
elif case=='ssh-no-host':ssh_mode='no-host'
elif case=='owner-case':url='git@GITHUB.EXAMPLE144:Acme/Project.git';mapped='GITHUB.EXAMPLE144';expected_repo='github.example144/Acme/Project'
elif case=='beside-ci':ci='github';review='local'
elif case=='create-error':fault='create';want=2
elif case=='summary-error':fault='comment';want=2
elif case=='merge':seed=True;args=['merge','1'];ci='github'
elif case=='merge-waiver':seed=True;args=['merge','1','--no-review','waiver144'];review='local'
elif case=='pr-merge':args+=['--merge']
elif case=='merge-closed':seed=True;args=['merge','1'];want=1
elif case=='merge-inherited':seed=True;args=['merge','1'];inherit=True
elif case=='local-control':seed=True;args=['merge','1'];url=None;inherit=True;expected_repo='other/repo';expected_host='other.example'
elif case=='merge-error':seed=True;args=['merge','1'];fault='merge';want=2
elif case=='merge-waiver-error':seed=True;args=['merge','1','--no-review','waiver144'];review='local';fault='merge';want=2
elif case=='merge-git-error':seed=True;args=['merge','1'];fault='git';want=2
elif case=='review-control':seed=True;args=['review','--pr','1'];review='local';unrelated=True
elif case=='report-control':args=['report','--json','--github'];review='local';unrelated=True
elif case=='ci-control':args=['ci','--base',initial];unrelated=True
elif case=='status-control':args=['status'];unrelated=True
elif case=='export-control':args=['export','--base',initial,'export144'];unrelated=True
elif case=='suite-control':ci='local'
elif case=='docs':pass
elif case=='stub-control':pass
elif case=='permission-control':want=1
elif case=='transport-control':pass
elif case=='fault-control':fault='comment';want=2
else:raise AssertionError('unrouted '+case)
p=run(binary,'init');assert p.returncode==0,p.stderr
config=Path('.shipcraft.toml').read_text();a,b=config.split('[execution]',1);block,sep,tail=b.partition('[roles]')
block=re.sub(r'(?m)^ci\s*=.*$', 'ci = '+json.dumps(ci),block);block=re.sub(r'(?m)^review\s*=.*$', 'review = '+json.dumps(review),block)
if case=='github' or case=='merge' or case=='beside-ci':block+='\nsuite_checks = ["suite144"]\n'
config=a+'[execution]'+block+sep+tail
if case=='beside-ci':config=config.replace('[review]','[review]\nafter = "push"')
if case=='suite-control':
 # The actual suite records the child environment, then delegates to its real runner.
 probe=cw/'probe144.py';put(probe,'import json,os\nfrom pathlib import Path\nPath('+repr(str(st/'suite144.json'))+').write_text(json.dumps({k:os.environ.get(k) for k in ("GH_REPO","GH_HOST")}))\n')
 config=re.sub(r'(?m)^(test_command|command)\s*=\s*"(.*)"$',lambda m:m[1]+' = '+json.dumps(shlex.quote(sys.executable)+' '+shlex.quote(str(probe))+' && '+json.loads('"'+m[2]+'"')),config)
put('.shipcraft.toml',config);base=snapshot('base144')
origin=cb/'origin.git';git('init','-q','--bare',origin);git('--git-dir='+str(origin),'symbolic-ref','HEAD','refs/heads/main');put(st/'origin',str(origin))
git('remote','add','origin',origin);git('push','-q','origin','main');git('fetch','-q','origin');git('remote','set-head','origin','main')
if case=='repro':
 old=Path.cwd();clone=cw/'clone144';git('clone','-q',origin,clone);(clone/'.venv').symlink_to(old/'.venv',target_is_directory=True);os.chdir(clone)
if upstream:
 other=cb/'upstream.git';git('clone','-q','--bare',origin,other);git('remote','add','upstream',other)
git('checkout','-qb','feat');put('product144.py','value = 144\n');head=snapshot('feature144');put(st/'sha',head)
# Git uses this transport directly. It can only run local upload/receive-pack.
put(cb/'transport144','#!'+sys.executable+'\nimport os,shlex,sys\na=shlex.split(sys.argv[-1]);assert a[0] in ("git-upload-pack","git-receive-pack"),a\nos.execvp(a[0],[a[0],'+repr(str(origin))+'])\n');(cb/'transport144').chmod(0o755)
os.environ['GIT_SSH_VARIANT']='ssh'
os.environ['GIT_SSH_COMMAND']=shlex.quote(str(cb/'transport144'));os.environ['GIT_ALLOW_PROTOCOL']='file:ssh'
put(cb/'ssh','#!'+sys.executable+'\nimport json,sys\nfrom pathlib import Path\nst=Path(__file__).parent/"state"\nwith (st/"ssh144.log").open("a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nassert sys.argv[1:2]==["-G"],sys.argv\nif '+repr(ssh_mode)+'=="fail":sys.exit(17)\nprint("user fixture144" if '+repr(ssh_mode)+'=="no-host" else "hostname '+mapped+'")\n');(cb/'ssh').chmod(0o755)
if seed:
 git('push','-q','origin','feat')
 q=run('gh','pr','create','--title','Seed144','--body','seed144','--head','feat','--base','main');assert q.returncode==0,q.stderr
if url:git('remote','set-url','origin',url)
if case=='pushurl':git('config','remote.origin.pushurl',str(origin))
if case=='multi-url':
 git('config','--add','remote.origin.url','git@unused.example:wrong/repo.git');git('config','remote.origin.pushurl',str(origin))
if case=='merge-closed':
 d=json.loads((st/'prs.json').read_text());d['1']['state']='CLOSED';put(st/'prs.json',json.dumps(d))
if ci=='github':
 put(st/'statuses.jsonl',json.dumps(dict(id=1,sha=head,context='shipcraft/ci',state='success',description='seed144',t=time.time()))+'\n')
 put(st/'check-runs.json',json.dumps([dict(id=1,head_sha=head,name='suite144',status='completed',conclusion='success',app={'id':1},check_suite={'id':1})]))
if case=='permission-control':put(st/'repo-view.json',json.dumps({'*':{'fields':{'viewerPermission':'READ'}}}))
# An exact Git observer: forwarding and injected errors are proved in transport-control.
realgit=shutil.which('git')
put(cb/'git','#!'+sys.executable+'\nimport json,os,sys\nfrom pathlib import Path\na=sys.argv[1:];st=Path(__file__).parent/"state"\nwith (st/"git144.log").open("a") as f:f.write(json.dumps(a)+"\\n")\ni=0\nwhile i<len(a) and a[i].startswith("-"):\n i+=2 if a[i] in ("-C","-c","--git-dir","--work-tree") else 1\nif a[i:]==["remote","get-url","origin"] and (st/"git144.fail").exists():\n print("fatal: injected144 get-url",file=sys.stderr);sys.exit(128)\nos.execv('+repr(realgit)+',['+repr(realgit)+',*a])\n');(cb/'git').chmod(0o755)
if fault=='git':put(st/'git144.fail','yes')
if fault in ('create','comment','merge'):
 put(st/'gh144.fault',fault)
 shutil.move(cb/'gh',cb/'gh144-real')
 put(cb/'gh','#!'+sys.executable+'\nimport json,os,sys\nfrom pathlib import Path\na=sys.argv[1:];cb=Path(__file__).parent\nif a[:2]==["pr",(cb/"state/gh144.fault").read_text()]:\n with (cb/"state/gh-env.log").open("a") as f:f.write(json.dumps({"args":a,"GH_REPO":os.environ.get("GH_REPO"),"GH_HOST":os.environ.get("GH_HOST")})+"\\n")\n print("gh: injected144 '+fault+'",file=sys.stderr);sys.exit(1)\nos.execv(str(cb/"gh144-real"),[str(cb/"gh144-real"),*a])\n');(cb/'gh').chmod(0o755)
if inherit:os.environ.update(GH_REPO='other/repo',GH_HOST='other.example')
for n in ('gh-env.log','calls.log','writes.log'):(st/n).unlink(missing_ok=True)
# Dedicated controls exercise the same stubs, SSH transport and Git observer.
if case=='stub-control':
 for values in ({},{'GH_REPO':'','GH_HOST':''},{'GH_REPO':'control/repo','GH_HOST':'control.example'}):
  env=dict(os.environ,**values);q=run('gh','repo','view','--json','nameWithOwner',env=env);assert q.returncode==0 and json.loads(q.stdout)=={'nameWithOwner':'acme/proj'}
  assert records(st/'gh-env.log')[-1]==dict(args=['repo','view','--json','nameWithOwner'],GH_REPO=values.get('GH_REPO'),GH_HOST=values.get('GH_HOST'))
 assert len(records(st/'calls.log'))==3 and not records(st/'writes.log')
 before_calls=(st/'calls.log').read_bytes()
 q=run('gh','auth','status',env=dict(os.environ,SHIPCRAFT_STUB_QUIET='1'));assert q.returncode==0
 assert records(st/'gh-env.log')[-1]==dict(args=['auth','status'],GH_REPO=None,GH_HOST=None)
 assert (st/'calls.log').read_bytes()==before_calls
 q=run('gh','unsupported144');assert q.returncode==1 and 'unsupported gh' in q.stderr
 assert records(st/'gh-env.log')[-1]==dict(args=['unsupported144'],GH_REPO=None,GH_HOST=None)
 assert (st/'calls.log').read_bytes()==before_calls and not records(st/'writes.log')
if case=='transport-control':
 q=run('ssh','-G','github.example144');assert q.returncode==0 and q.stdout=='hostname github.example144\n'
 assert git('remote','get-url','origin')==url
 put(st/'git144.fail','yes');q=run('git','remote','get-url','origin');assert q.returncode==128 and q.stderr=='fatal: injected144 get-url\n';(st/'git144.fail').unlink()
 git('fetch','-q','origin');git('push','-q','origin','feat')
 assert git('--git-dir='+str(origin),'rev-parse','refs/heads/feat')==head
if case=='docs':
 text=(source/'docs/spec.md').read_text().split('## 3. Commands',1)[1].split('### `init`',1)[0]
 assert '(item 110); its `gh` calls name origin\'s repository (item 144).' in text
 assert 'Its `gh` calls name origin\'s repository (item 144).' in text
if case=='fault-control':
 for mode in ('create','comment','merge'):
  put(st/'gh144.fault',mode);q=run('gh','pr',mode,'1');assert q.returncode==1 and 'injected144' in q.stderr
  assert records(st/'gh-env.log')[-1]==dict(args=['pr',mode,'1'],GH_REPO=None,GH_HOST=None)
 q=run('gh','repo','view','--json','viewerPermission');assert q.returncode==0 and json.loads(q.stdout)=={'viewerPermission':'ADMIN'}
 assert records(st/'calls.log')[-1]['argv']==['repo','view','--json','viewerPermission'] and not records(st/'writes.log')
if case=='stub-control' or case=='docs' or case=='fault-control':sys.exit(0)
if case=='report-control':
 q=run(binary,'pr','--title','Report144');assert q.returncode==0,q.stderr
if case=='ci-control':git('update-ref','refs/heads/main',head);git('checkout','-q','main')
# Isolate fixture invocations from calls of the command under test.
for n in ('gh-env.log','calls.log','writes.log','git144.log','ssh144.log'):(st/n).unlink(missing_ok=True)
before=(Path('.git/shipcraft/runs.jsonl').read_bytes() if Path('.git/shipcraft/runs.jsonl').is_file() else b'')
p=run(binary,*args);assert p.returncode==want,(p.returncode,want,p.stderr)
calls=records(st/'gh-env.log');trace=records(st/'git144.log');rows=records(Path('.git/shipcraft/runs.jsonl'))
permission=[x for x in calls if x['args'][:2]==['repo','view']]
later=[x for x in calls if x['args'][:2]!=['repo','view']]
inherited_repo='other/repo' if inherit else None;inherited_host='other.example' if inherit else None
assert all('--repo' not in x['args'] and '-R' not in x['args'] for x in calls),calls
assert all(x['GH_REPO']==inherited_repo and x['GH_HOST']==inherited_host for x in permission),permission
if case=='git-error' or case=='merge-git-error':
 assert p.stderr.startswith('shipcraft: error:') and 'injected144 get-url' in p.stderr,p.stderr
 assert len(permission)==(1 if case=='git-error' else 0) and not later and not records(st/'writes.log'),calls
 assert not any('push' in a or 'fetch' in a for a in trace),trace
 assert not rows and before==b'',rows
else:
 if args[0]=='pr' and want!=1:
  assert git('--git-dir='+str(origin),'rev-parse','refs/heads/feat')==head
 if case=='permission-control':
  assert len(permission)==1 and not later and not records(st/'writes.log'),calls
  assert 'permission is READ' in p.stderr and len(p.stderr.splitlines())==3,p.stderr
  assert not any('push' in a or 'fetch' in a for a in trace),trace
 elif unrelated:
  if case=='review-control':assert any(x['args'][:2]==['pr','view'] for x in calls) and len(records(st/'reviewer.calls.jsonl'))==1,calls
  if case=='report-control' or case=='ci-control' or case=='status-control':assert calls,('unchanged path must exercise gh',calls)
  if case=='export-control':assert git('rev-parse','export144')!=head and not calls
  assert all(x['GH_REPO']=='github.example144/acme/proj' and x['GH_HOST']=='github.example144' for x in calls),calls
  # Invoke each unchanged command a second time with inherited selection.
  os.environ.update(GH_REPO='control/repo',GH_HOST='control.example')
  if case=='export-control':args[-1]='export144-again'
  (st/'gh-env.log').unlink(missing_ok=True);q=run(binary,*args);assert q.returncode==0,q.stderr
  assert all(x['GH_REPO']=='github.example144/acme/proj' and x['GH_HOST']=='github.example144' for x in records(st/'gh-env.log'))
 else:
  assert later,calls
  if case=='existing':assert any(x['args'][:2]==['pr','edit'] for x in later),later
  if case=='review':
   assert any(x['args'][:2]==['pr','view'] for x in later),later
   assert len(records(st/'reviewer.calls.jsonl'))==1
   assert any(r['context']=='shipcraft/review' and r['state']=='success' for r in records(st/'statuses.jsonl'))
  if case=='github' or case=='merge' or case=='beside-ci':assert any('/check-runs?' in ' '.join(x['args']) for x in later),later
  if case=='merge-waiver':assert any(x['args'][:2]==['pr','comment'] for x in later),later
  if case=='merge-closed':assert len(later)==1 and later[0]['args'][:2]==['pr','view'] and 'open' in p.stderr,p.stderr
  if case=='summary-error':assert any(r['layer']=='pr' and r['result']=='error' for r in rows),rows
  if case=='create-error':assert not rows,rows
  if case=='merge-error' or case=='merge-waiver-error':
   assert json.loads((st/'prs.json').read_text())['1']['state']=='OPEN'
   assert not any(r['layer']=='merge' for r in rows),rows
   if case=='merge-waiver-error':assert any('waiver144' in json.dumps(r) for r in records(st/'comments.jsonl'))
  if case=='merge' or case=='merge-waiver' or case=='merge-inherited' or case=='local-control' or case=='pr-merge':
   assert json.loads((st/'prs.json').read_text())['1']['state']=='MERGED'
   assert later[-1]['args'][:2]==['pr','merge'],later
   assert p.stdout.endswith('shipcraft: clean up what this change created (worktree, temp folders, servers you started).\n'),p.stdout
  if case=='suite-control':
   assert json.loads((st/'suite144.json').read_text())=={'GH_REPO':None,'GH_HOST':None}
  # Preservation controls deliberately retain today's unscoped behavior.
  if case=='stub-control' or case=='transport-control' or case=='docs' or case=='suite-control':
   assert json.loads((st/'prs.json').read_text())['1']['title']=='Item144'
  else:
   assert all(x['GH_REPO']==expected_repo and x['GH_HOST']==expected_host for x in later),later
   if case!='local-control' and case!='three-segments':assert len([a for a in trace if a[-3:]==['remote','get-url','origin']])==(2 if case=='pr-merge' else 1),trace
PY144
  pass
}
