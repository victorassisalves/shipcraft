# Item 115: offline registry warnings, through public commands only.
item115_langs() { echo core; }
item115_cases() {
  local c
  for c in control-stub control-proxies control-old added scoped dedup sections specs paths invalid-manifests bom symlink rename version-move invalid-names age-boundary custom-days off invalid-switch invalid-days base-config git-diff git-tree git-blob timeout exit status malformed dates future unavailable signal no-retry repeat unreadable body-fail create-fail late-error reuse count-fail; do echo "v1-115.$c"; done
}
item115_case() {
  EXPECT="item 115: ${CASE#v1-115.}"
  v1_start codex
  CFGS='execution|ci|"off"
execution|review|"local"
pr|warn_lines|4'
  pr_main
  must_accept 'item 115 public contract' cmd "$PY" - "${CASE#v1-115.}" "$(command -v shipcraft)" "$ST" "$CB" "$CW" <<'PY115'
import datetime,hashlib,json,os,re,shutil,signal,subprocess,sys,time
from pathlib import Path
case,binary,st,cb,cw=sys.argv[1:];binary=str(Path(binary).resolve());st=Path(st);cb=Path(cb);cw=Path(cw)
def run(*args):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,timeout=65)
 print('$',repr(args),'rc',p.returncode,repr(p.stdout),repr(p.stderr),flush=True);return p
def git(*args):
 p=run('git',*args);assert p.returncode==0,('fixture git',args,p.stderr);return p.stdout.decode().strip()
def snap():
 git('add','-A');tree=git('write-tree');sha=git('commit-tree',tree,'-p','HEAD','-m','chore: fixture115');git('update-ref','HEAD',sha);return sha
def write(path,value):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value if isinstance(value,bytes) else value.encode())
def manifest(path,deps):write(path,json.dumps(deps))
def data(path):return [json.loads(s) for s in path.read_text().splitlines()] if path.is_file() else []
def policy(key,value):
 p=Path('.shipcraft.toml');s=p.read_text();s=s.replace('[pr]\n','[pr]\n'+key+' = '+value+'\n',1);p.write_text(s)
def registry(table):write(st/'registry.json',json.dumps(table))
def seed():
 git('push','-q','origin','HEAD');p=run(cb/'gh','pr','create','--title','Title115','--body','Intent115\n');assert p.returncode==0
realgit=shutil.which('git')
(cb/'git').write_text('#!'+sys.executable+'\n'+r'''
import os,sys,json
from pathlib import Path
st=Path(__file__).parent/'state';a=sys.argv[1:]
with (st/'git115.log').open('a') as f:f.write(json.dumps(a)+'\n')
mode=(st/'gitfault').read_text() if (st/'gitfault').exists() else ''
if (mode=='diff' and '--name-only' in a and '--diff-filter=AM' in a) or (mode=='tree' and 'ls-tree' in a and a[-1].endswith('package.json')) or (mode=='blob' and any(a[i:i+2]==['cat-file','blob'] for i in range(len(a)-2)) and (st/'blob115').exists() and a[-1]==(st/'blob115').read_text()) or (mode=='count' and '--numstat' in a):
 (st/'githit').write_text(mode);sys.exit(93)
os.execv(REAL,[REAL,*a])
'''.replace('REAL',repr(realgit)));(cb/'git').chmod(0o755)
(cb/'gh').rename(cb/'gh-real115')
(cb/'gh').write_text('#!'+sys.executable+'\n'+r'''
import os,sys,json,subprocess
from pathlib import Path
root=Path(__file__).parent;st=root/'state';a=sys.argv[1:]
mode=(st/'ghfault').read_text() if (st/'ghfault').exists() else ''
with (st/'gh115.log').open('a') as f:f.write(json.dumps(a)+'\n')
if '--body-file' in a or '--body' in a:
 body=Path(a[a.index('--body-file')+1]).read_text() if '--body-file' in a else a[a.index('--body')+1]
 with (st/'submitted115.log').open('a') as f:f.write(json.dumps({'argv':a,'body':body,'curl':(st/'curl.log').read_text() if (st/'curl.log').exists() else ''})+'\n')
if (mode=='create' and a[:2]==['pr','create']) or (mode=='body' and a[:2]==['pr','edit']) or (mode=='comment' and (a[:2]==['pr','comment'] or (a[:1]==['api'] and any('/comments' in x for x in a) and '-f' in a))):
 (st/'ghhit').write_text(mode);print('fault115',file=sys.stderr);sys.exit(1)
if mode=='unreadable' and a[:2]==['pr','list']:
 p=subprocess.run([str(root/'gh-real115'),*a],capture_output=True);d=json.loads(p.stdout)
 for row in d:row['body']=False
 print(json.dumps(d));sys.exit(p.returncode)
os.execv(str(root/'gh-real115'),[str(root/'gh-real115'),*a])
''');(cb/'gh').chmod(0o755)
# Observe the process boundary while delegating all answers to the shared stub.
(cb/'curl').rename(cb/'curl-stub115')
(cb/'curl').write_text('#!'+sys.executable+'\n'+r''' 
import json,os,signal,subprocess,sys,time
from pathlib import Path
root=Path(__file__).parent;st=root/'state'
with (st/'curlmeta115.log').open('a') as f:f.write(json.dumps(dict(cwd=os.getcwd(),pid=os.getpid(),group=os.getpgrp(),stdin_null=os.fstat(0).st_rdev==os.stat('/dev/null').st_rdev,stdin=sys.stdin.buffer.read().hex()))+'\n')
mode=(st/'curlmode115').read_text() if (st/'curlmode115').exists() else ''
if mode=='signal':os.kill(os.getpid(),signal.SIGTERM)
if mode=='hang':
 with (st/'curl.log').open('a') as f:f.write(json.dumps(sys.argv[1:])+'\n')
 delay=float((st/'child-delay115').read_text())
 child=subprocess.Popen([sys.executable,'-c',"import time;from pathlib import Path;time.sleep("+str(delay)+");Path("+repr(str(st/'child-survived115'))+").touch()"])
 (st/'child-started115').write_text(str(child.pid));time.sleep(30);sys.exit(0)
os.execv(str(root/'curl-stub115'),[str(root/'curl-stub115'),*sys.argv[1:]])
''');(cb/'curl').chmod(0o755)
base={};files={};table={};expected_names=[];warnings=[];counts=(0,0,0);config={};fault='';ghfault='';want=0;existing=False;repeat=False;control=False;special=''
if case=='control-stub':
 # Exercise every table mode directly, through the same installed offline executable.
 registry({'@scope/probe':{'status':404,'body':'probe115'},'raw':{'stdout':'raw115\n503'},'exit':{'exit':28},'date':{'created':'2001-02-03T04:05:06Z'},'ago':{'created_ago':3600}})
 for name,rc,out in [('@scope%2Fprobe',0,b'probe115\n404'),('raw',0,b'raw115\n503'),('exit',28,b''),('date',0,b'{"time": {"created": "2001-02-03T04:05:06Z"}}\n200')]:
  p=run(cb/'curl','https://registry.npmjs.org/'+name);assert p.returncode==rc and p.stdout==out,(name,p)
 p=run(cb/'curl','https://registry.npmjs.org/ago');created=json.loads(p.stdout[:-4])['time']['created'];age=time.time()-datetime.datetime.strptime(created,'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).timestamp();assert 3590<age<3620,age
 assert data(st/'curl.log')[0]==['https://registry.npmjs.org/@scope%2Fprobe']
 assert data(st/'curlmeta115.log')[0]['cwd']==str(Path.cwd()) and data(st/'curlmeta115.log')[0]['stdin']=='',data(st/'curlmeta115.log')
 write(st/'curlmode115','signal');p=run(cb/'curl','https://registry.npmjs.org/raw');assert p.returncode==-15,p
 write(st/'curlmode115','hang');write(st/'child-delay115','1')
 proc=subprocess.Popen([str(cb/'curl'),'control-hang115'],stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
 try:
  until=time.time()+5
  while not (st/'child-started115').exists() and time.time()<until:time.sleep(.02)
  assert (st/'child-started115').exists(),'hang child never started'
  os.killpg(proc.pid,signal.SIGTERM);proc.communicate(timeout=5);assert proc.returncode==-15
  time.sleep(1.2);assert not (st/'child-survived115').exists(),'control child survived group kill'
 finally:
  if proc.poll() is None:os.killpg(proc.pid,signal.SIGKILL);proc.communicate()
 write(st/'curlmode115','');(st/'child-started115').unlink()
 registry([]);p=run(cb/'curl','https://registry.npmjs.org/x');assert p.returncode==99 and p.stderr==b'acceptance-stub: bad registry.json\n'
 (st/'registry.json').unlink();p=run(cb/'curl','https://registry.npmjs.org/default');assert p.returncode==0 and p.stdout.endswith(b'\n200') and int(json.loads(p.stdout[:-4])['time']['created'][:4])<datetime.datetime.now().year-9
 raise SystemExit(0)
elif case=='control-proxies':control=True;special='proxies'
elif case=='control-old':control=True;files={'package.json':{'dependencies':{'old115':'*'}}};table={'old115':{'created':'2000-01-01T00:00:00Z'}}
elif case=='added':files={'package.json':{'dependencies':{'missing115':'^1'}}};table={'missing115':{'status':404}};expected_names=['missing115'];warnings=[('missing115','package.json',None)];counts=(1,1,0);special='other-commands'
elif case=='scoped':files={'nested space/é/package.json':{'dependencies':{'@scope/pkg':'latest'}}};table={'@scope/pkg':{'status':404}};expected_names=['@scope/pkg'];warnings=[('@scope/pkg','nested space/é/package.json',None)];counts=(1,1,0)
elif case=='dedup':
 base={'a/package.json':{'dependencies':{'dup115':'1'}}};files={'a/package.json':{'dependencies':{'dup115':'2'}},'b/package.json':{'dependencies':{'dup115':'1','z115':'1'}},'c/package.json':{'peerDependencies':{'dup115':'*','a115':'1'}}};table={n:{'status':404} for n in ('dup115','z115','a115')};expected_names=['a115','dup115','z115'];warnings=[('a115','c/package.json',None),('dup115','b/package.json',None),('z115','b/package.json',None)];counts=(3,3,0)
elif case=='sections':
 files={'package.json':{k:{'dep'+str(i):v} for i,(k,v) in enumerate(zip(('dependencies','devDependencies','optionalDependencies','peerDependencies'),('^1','latest','*','')))}};expected_names=['dep0','dep1','dep2','dep3'];table={n:{'status':404} for n in expected_names};warnings=[(n,'package.json',None) for n in expected_names];counts=(4,4,0)
elif case=='specs':
 specs=['workspace:*','file:../x','link:x','portal:x','npm:other@1','git:x','git+ssh:x','github:x','gitlab:x','bitbucket:x','http:x','https:x','user/repo','./pkg',None,42,True,{},[]]
 files={'package.json':{'dependencies':dict([('skip'+str(i),v) for i,v in enumerate(specs)]+[('yes115','1.2.3')]),'devDependencies':None,'peerDependencies':[]}};expected_names=['yes115'];counts=(1,0,0)
elif case=='paths':
 files={p:{'dependencies':{'skip115':'1'}} for p in ('node_modules/package.json','a/node_modules/b/package.json','upper/Package.json','lf\n/package.json','cr\r/package.json','tab\t/package.json','del\x7f/package.json','ls\u2028/package.json','ps\u2029/package.json')};files['node_modules-x/package.json']={'dependencies':{'yes115':'1'}};expected_names=['yes115'];counts=(1,0,0);special='rawpaths'
elif case=='invalid-manifests':
 base={'badbase/package.json':'{','arraybase/package.json':[],'utfbase/package.json':b'\xff'};files={p:{'dependencies':{'skip115':'1'}} for p in base};files.update({p:v for p,v in [('badhead/package.json','{'),('null/package.json',None),('array/package.json',[]),('utf/package.json',b'\xff'),('doublebom/package.json',b'\xef\xbb\xbf\xef\xbb\xbf{}')]});files['ok/package.json']={'dependencies':{'yes115':'1'}};expected_names=['yes115'];counts=(1,0,0)
elif case=='bom':config={'new_dependencies':"'warn' # literal TOML with comment"};files={'package.json':b'\xef\xbb\xbf{\r\n"dependencies": {"bom115":"1"}\r}\n'};expected_names=['bom115'];counts=(1,0,0)
elif case=='symlink':files={'real.json':{'dependencies':{'skip115':'1'}},'ok/package.json':{'dependencies':{'yes115':'1'}}};special='link';expected_names=['yes115'];counts=(1,0,0)
elif case=='rename':base={'old/package.json':{'dependencies':{'renamed115':'1'}}};files={'old/package.json':'DELETE','new/package.json':base['old/package.json']};expected_names=['renamed115'];counts=(1,0,0)
elif case=='version-move':base={'package.json':{'dependencies':{'version115':'^1','transition115':'workspace:*'},'devDependencies':{'move115':'1'}}};files={'package.json':{'dependencies':{'version115':'^2','move115':'2','transition115':'*'}}};expected_names=['transition115'];counts=(1,0,0)
elif case=='invalid-names':
 names=['bad name','+bad','.bad','@scope','@scope/','a'*215,'é'];files={'package.json':{'dependencies':{n:'1' for n in names+['ok115','bad\nkey','bad\rkey','bad\u2028key','bad\u2029key']}}};expected_names=['ok115'];warnings=[(n,'package.json',None) for n in sorted(names,key=lambda s:s.encode())];counts=(8,7,0)
elif case=='age-boundary':files={'package.json':{'dependencies':{'a-young':'1','b-old':'1'}}};table={'a-young':{'created_ago':30*86400-3600},'b-old':{'created_ago':30*86400+3600}};expected_names=['a-young','b-old'];warnings=[('a-young','package.json',29)];counts=(2,1,0)
elif case=='custom-days':config={'new_dependency_days':'36500'};files={'package.json':{'dependencies':{'century115':'1'}}};table={'century115':{'created_ago':100*86400+3600}};expected_names=['century115'];warnings=[('century115','package.json',100)];counts=(1,1,0)
elif case=='off':config={'new_dependencies':'"off"'};files={'package.json':{'dependencies':{'missing115':'1'}}};table={'missing115':{'status':404}};counts=(None,None,None)
elif case=='invalid-switch':special='invalid-switch'
elif case=='invalid-days':special='invalid-days'
elif case=='base-config':config={'new_dependencies':'"off"','new_dependency_days':'1'};files={'package.json':{'dependencies':{'missing115':'1'}}};counts=(None,None,None);special='head-warn'
elif case=='git-diff':fault='diff';counts=(None,None,None)
elif case=='git-tree':fault='tree';counts=(None,None,None)
elif case=='git-blob':fault='blob';counts=(None,None,None)
elif case=='timeout':table={'a115':{'exit':28}};special='timeout';reason='timed out'
elif case=='exit':table={'a115':{'exit':7}};special='failure';reason='curl failed (exit 7)'
elif case=='status':table={'a115':{'status':429}};special='failure';reason='the registry answered 429'
elif case=='malformed':special='malformed'
elif case=='dates':special='dates'
elif case=='future':files={'package.json':{'dependencies':{'future115':'1'}}};table={'future115':{'created':'2999-01-01T00:00:00.123456789Z'}};expected_names=['future115'];warnings=[('future115','package.json',0)];counts=(1,1,0)
elif case=='unavailable':special='unavailable';reason='curl could not start';counts=(1,0,1)
elif case=='signal':special='signal';reason='curl failed (signal 15)';counts=(1,0,1)
elif case=='no-retry':special='failure';files={'package.json':{'dependencies':{'a115':'1','b115':'1','c115':'1'}}};table={'a115':{'status':404},'b115':{'status':503},'c115':{'status':404}};expected_names=['a115','b115'];warnings=[('a115','package.json',None)];counts=(3,1,2);reason='the registry answered 503'
elif case=='repeat':repeat=True;files={'package.json':{'dependencies':{'again115':'1'}}};table={'again115':{'status':404}};expected_names=['again115'];warnings=[('again115','package.json',None)];counts=(1,1,0)
elif case=='unreadable':existing=True;ghfault='unreadable'
elif case=='body-fail':existing=True;ghfault='body'
elif case=='create-fail':ghfault='create';want=2
elif case=='late-error':ghfault='comment';want=2;special='log-after'
elif case=='reuse':existing=True;special='reuse'
elif case=='count-fail':fault='count';want=2;control=True
else:raise AssertionError('unrouted '+case)
if special in ('invalid-switch','invalid-days'):
 values=['"WARN"','""','1','true','[]','{}'] if special=='invalid-switch' else ['0','36501','-1','1.5','true','"30"','[]','{}']
 key='new_dependencies' if special=='invalid-switch' else 'new_dependency_days'
 original=Path('.shipcraft.toml').read_text()
 for value in values:
  Path('.shipcraft.toml').write_text(original);policy(key,value);snap();git('push','-q','origin','main');git('checkout','-B','feature/invalid115')
  p=run(binary,'pr');err=p.stderr.decode();assert p.returncode==1 and len(err.strip().splitlines())==3,(value,p.returncode,err)
  assert all(l.startswith(prefix) for l,prefix in zip(err.strip().splitlines(),['shipcraft refused:','Why:','Next:'])) and key in err and 'line' in err,err
  assert not data(st/'curl.log') and not (st/'prs.json').exists()
  git('checkout','main')
 raise SystemExit(0)
for k,v in config.items():policy(k,v)
if special=='rawpaths':
 p=Path('.shipcraft.toml');p.write_text(p.read_text().replace('review = "local"','review = "off"',1))
for path,value in base.items():
 if isinstance(value,(bytes,str)):write(path,value)
 else:manifest(path,value)
snap();git('push','-q','origin','main');git('fetch','-q','origin');git('checkout','-qb','feature/item115')
if special=='head-warn':
 p=Path('.shipcraft.toml');p.write_text(p.read_text().replace('new_dependencies = "off"','new_dependencies = "warn"'))
if ghfault or special=='reuse':
 files={'package.json':{'dependencies':{'missing115':'1'}}};table={'missing115':{'status':404}};expected_names=['missing115'];warnings=[('missing115','package.json',None)];counts=(1,1,0)
if fault:files={'package.json':{'dependencies':{'probe115':'1'}}}
if special in ('failure','timeout','malformed','dates','unavailable','signal') and not files:
 files={'package.json':{'dependencies':{'a115':'1','z115':'1'}}};expected_names=['a115'];counts=(2,0,2)
 if special in ('unavailable','signal'):files={'package.json':{'dependencies':{'a115':'1'}}};expected_names=[];counts=(1,0,1)
for path,value in files.items():
 if value=='DELETE':Path(path).unlink()
 elif isinstance(value,(bytes,str)):write(path,value)
 else:manifest(path,value)
if special=='link':Path('package.json').symlink_to('real.json')
sha=snap()
if special=='rawpaths':
 blob=subprocess.check_output([realgit,'hash-object','-w','--stdin'],input=b'{"dependencies":{"rawskip115":"1"}}').strip()
 subtree=subprocess.check_output([realgit,'mktree','-z'],input=b'100644 blob '+blob+b'\tpackage.json\0').strip()
 entries=subprocess.check_output([realgit,'ls-tree','-z',sha])+b'040000 tree '+subtree+b'\traw-\xff\0'
 tree=subprocess.check_output([realgit,'mktree','-z'],input=entries).decode().strip()
 sha=git('commit-tree',tree,'-p',sha,'-m','chore: raw manifest115');git('update-ref','HEAD',sha)
write(st/'sha',sha+'\n');registry(table)
if fault=='blob':write(st/'blob115',git('rev-parse','HEAD:package.json'))
if existing:seed()
if special=='proxies':
 write(st/'blob115','control-oid115')
 seed()
 for mode,argv in [('create',['pr','create','--title','x','--body','x']),('body',['pr','edit','1','--body','x']),('comment',['pr','comment','1','--body','x'])]:
  write(st/'ghfault',mode);p=run(cb/'gh',*argv);assert p.returncode==1 and (st/'ghhit').read_text()==mode
 write(st/'ghfault','unreadable');p=run(cb/'gh','pr','list','--json','body');assert json.loads(p.stdout)[0]['body'] is False
 write(st/'ghfault','')
 for mode,argv in [('diff',['diff','--name-only','--diff-filter=AM','main','HEAD']),('tree',['ls-tree','HEAD','--','package.json']),('blob',['cat-file','blob','control-oid115']),('blob',['-C',str(Path.cwd()),'--literal-pathspecs','cat-file','blob','control-oid115']),('count',['diff','--numstat','main','HEAD'])]:
  write(st/'gitfault',mode);p=run(cb/'git',*argv);assert p.returncode==93 and (st/'githit').read_text()==mode
 write(st/'gitfault','');assert git('rev-parse','HEAD')==sha
 assert next(iter(json.loads((st/'prs.json').read_text()).values()))['body']=='Intent115\n'
if special=='reuse':
 p=run(binary,'review','--pr','1');assert p.returncode==0 and not data(st/'curl.log'), 'explicit review called registry'
 write(st/'reviewer.json',json.dumps({'mode':'changes'}))
if special=='unavailable':(cb/'curl').chmod(0o644)
if special=='signal':
 write(st/'curlmode115','signal')
write(st/'gitfault',fault);write(st/'ghfault',ghfault)
answers=[None]
if special=='malformed':answers=['{}','{}\n200\n','{}\n20','{}\n２００','[]\n200','null\n200','{"time":null}\n200','{"time":{"created":3}}\n200','{"time":{"created":"bad"}}\n200']
if special=='dates':answers=[json.dumps({'time':{'created':d}})+'\n200' for d in ['2025-02-29T00:00:00Z','2024-13-01T00:00:00Z','2024-01-01T24:00:00Z','2024-01-01T00:00:60Z','2024-01-01T00:00:00+00:00','2024-01-01T00:00:00.Z','2024-01-01T00:00:00.1234567890Z']]
if repeat:answers=[None,None]
if special=='timeout':answers=[None,'HANG115']
for answer in answers:
 if answer=='HANG115':write(st/'curlmode115','hang');write(st/'child-delay115','17')
 elif answer is not None:registry({'a115':{'stdout':answer}});reason='unreadable answer from the registry'
 (st/'curl.log').unlink(missing_ok=True);(st/'curlmeta115.log').unlink(missing_ok=True)
 before_run=time.time();p=run(binary,'pr');out=p.stdout.decode(errors='replace');err=p.stderr.decode(errors='replace');assert p.returncode==want,(out,err)
 if answer=='HANG115':
  assert (st/'child-started115').exists() and 14<=time.time()-before_run<30,(time.time()-before_run,out,err)
  time.sleep(max(0,19-(time.time()-before_run)));assert not (st/'child-survived115').exists(),'curl child escaped timeout group kill'
 calls=data(st/'curl.log');rows=data(Path('.git/shipcraft/runs.jsonl'));prs=[r for r in rows if r['layer']=='pr']
 if fault=='count':
  assert not calls and not prs and (st/'githit').read_text()=='count',(calls,prs);raise SystemExit(0)
 if control:
  body=next(iter(json.loads((st/'prs.json').read_text()).values()))['body'];assert 'New dependenc' not in body and 'shipcraft: Size:' in out and prs[-1]['result']=='passed',(body,out,prs)
  if special=='proxies':assert body.startswith('Intent115\n\n<!-- shipcraft:size -->'),body
  else:
   assert 'Size: 1 product lines' in body,body
   brief='\n'.join(data(st/'reviewer.calls.jsonl')[-1]['files'].values());assert 'old115' in brief,brief
  raise SystemExit(0)
 expected_calls=[['--disable','--silent','--show-error','--compressed','--max-time','10','--header','Accept: application/json','--write-out','\n%{http_code}','https://registry.npmjs.org/'+n.replace('/','%2F')] for n in expected_names]
 assert calls==expected_calls,('registry calls',calls,expected_calls)
 meta=data(st/'curlmeta115.log')
 assert len(meta)==len(expected_calls)+(1 if special=='signal' else 0),meta
 assert all(Path(m['cwd']).resolve()==Path.cwd().resolve() and m['group']==m['pid'] and m['stdin_null'] and m['stdin']=='' for m in meta),meta
 lines=[]
 for name,path,age in warnings:
  lines.append(f'New dependency not in the npm registry: {name} ({path}). Check the name: anyone can publish a package under a name that does not exist yet.' if age is None else f'New dependency first published {age} day(s) ago on npm: {name} ({path}). Check it is the package you meant.')
 if fault:lines=['New dependencies not checked: git could not read the package.json files.'];assert (st/'githit').exists() and (st/'githit').read_text()==fault, 'missing dependency git read: '+fault
 elif counts[2]:lines.append(f'New dependencies not checked: {counts[2]} of {counts[0]}; the npm registry could not be read ({reason}).')
 if counts==(None,None,None) and not fault:
  assert not any('--diff-filter=AM' in a for a in data(st/'git115.log')), 'off read manifests'
 if ghfault=='create':
  assert not prs and not (st/'prs.json').exists()
  submitted=data(st/'submitted115.log')[-1];assert all(l in submitted['body'] for l in lines) and submitted['curl'],submitted
  assert 'shipcraft: New dependenc' not in out
  continue
 assert prs,rows
 row=prs[-1];keys=('new_dependencies','dependency_warnings','dependencies_not_checked')
 assert all(k in row for k in keys) and tuple(row[k] for k in keys)==counts,('dependency row',row,counts)
 assert all(type(row[k]) is int if v is not None else row[k] is None for k,v in zip(keys,counts)),row
 assert row['result']==('error' if want==2 else 'passed'),row
 assert all(not any(k in r for k in keys) for r in rows if r['layer']!='pr'),rows
 body=next(iter(json.loads((st/'prs.json').read_text()).values()))['body']
 actual=[l for l in out.split('\n') if l.startswith('shipcraft: New dependenc')];assert actual==['shipcraft: '+l for l in lines],out
 if lines:
  ls=out.split('\n');index=next(i for i,l in enumerate(ls) if l.startswith('shipcraft: Size:'));index+=2 if ls[index+1].startswith('shipcraft: Above the limit:') else 1;assert ls[index:index+len(lines)]==actual,out
 if ghfault in ('body','unreadable'):
  assert body=='Intent115\n' and 'shipcraft: the size line' in out,(body,out)
 else:
  assert [l for l in body.split('\n') if l.startswith('New dependenc')]==lines,body
  if lines:assert '\n'.join(lines)+'\n<!-- /shipcraft:size -->' in body,body
 for w in data(st/'writes.log'):
  if w['kind']=='comment' and 'Size:' in w['text']:assert 'New dependenc' not in w['text'],w
 if special=='other-commands':
  for argv in [('ci','--base','main'),('review','--pr','1'),('merge','1')]:
   (st/'curl.log').unlink(missing_ok=True);q=run(binary,*argv);assert q.returncode==0 and not data(st/'curl.log'),(argv,q.stdout,q.stderr,data(st/'curl.log'))
 if special=='log-after':
  write(st/'ghfault','');log=Path('.git/shipcraft/runs.jsonl');log.unlink();log.mkdir()
  again=run(binary,'pr');assert again.returncode==0 and log.is_dir() and not data(log),again.stderr
  assert all(('shipcraft: '+l) in again.stdout.decode() for l in lines),again.stdout
 if special=='reuse':
  assert len(data(st/'reviewer.calls.jsonl'))==1 and [r for r in rows if r['layer']=='review'][-1].get('reused') is True,rows
  assert [r for r in rows if r['layer']=='review'][-1]['text_sha256']==hashlib.sha256(b'Title115\0Intent115\n').hexdigest()
PY115
  pass
}
