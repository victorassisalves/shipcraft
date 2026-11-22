# Item 127: public binary, real Git objects; helpers copied locally from 120/125.
item127_langs() { echo core; }
item127_cases() {
 local c
 for c in control-history control-fault control-gh control-findings merge branch refs deleted candidates first-lock red-rows parents paths modes replacement messages grammar line-endings encoding framing groups ratios text position since-tag since-merge window-empty once read-exit read-truncated read-garbage unavailable refused later-gh no-markers signed read-signal control-empty control-proxy no-first; do echo "v1-127.$c"; done
}
item127_case() {
 EXPECT="item 127: ${CASE#v1-127.}"; v1_start codex
 must_accept 'marker report contract' cmd "$PY" - "${CASE#v1-127.}" "$(command -v shipcraft)" "$CW" <<'PY127'
import hashlib,json,os,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/'repo127 space';root.mkdir();realgit=shutil.which('git');env=dict(os.environ,TZ='Pacific/Honolulu')
for k in subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
T=1700000000

def run(*args,data=None,at=T):
 e=dict(env,GIT_AUTHOR_DATE=f'{at} +0000',GIT_COMMITTER_DATE=f'{at} +0000')
 p=subprocess.run(list(map(str,args)),cwd=root,env=e,input=data,capture_output=True,timeout=60)
 print('COMMAND127',args,p.returncode,repr(p.stdout),repr(p.stderr),flush=True);return p

def git(*args,**kw):
 p=run(realgit,*args,**kw);assert p.returncode==0,('fixture git',args,p.stderr);return p.stdout.decode().strip()

def write(name,value):
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value if isinstance(value,bytes) else value.encode())

def commit(message=b'fixture127\n',parents=None,at=T):
 git('add','-A');tree=git('write-tree')
 if parents is None:
  p=run(realgit,'rev-parse','--verify','HEAD');parents=[p.stdout.decode().strip()] if p.returncode==0 else []
 sha=git('commit-tree',tree,*[x for p in parents for x in ('-p',p)],data=message,at=at);git('update-ref','HEAD',sha);return sha

def red(lock='A',message=b'order cases: yes\n',at=T+10,parent=None):
 if parent is not None:git('reset','--hard',parent)
 write('.shipcraft/locks/'+lock+'.json','{}\n');return commit(message,at=at)

def row(layer='red',lock='A',pr=7,at=T+1,**kw):
 r=dict(layer=layer,lock=lock,pr=pr,at=at,result='passed',secs=1,commit=base,branch='topic127',code='',base='main',default_branch='main');r.update(kw);return r

def rows(lock='A',pr=7,**kw):return [row(lock=lock,pr=pr,**kw),row('merge',lock,pr,T+100)]
def snapshot():return {str(p.relative_to(root)):(p.lstat().st_mode,os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None) for p in root.rglob('*')}
def records(p):return [json.loads(x) for x in p.read_text().splitlines()] if p.exists() else []
def report(rs,args=('--json',)):
 write('.git/shipcraft/runs.jsonl',''.join(json.dumps(r)+'\n' for r in rs));before=snapshot();p=run(binary,'report',*args)
 assert snapshot()==before,'report mutated repository';return p

def output(rs,args=('--json',)):
 p=report(rs,args);assert p.returncode==0 and not p.stderr,(p.returncode,p.stderr);return [json.loads(x) for x in p.stdout.splitlines()]
def select(out,kind):return [r for r in out if r['kind']==kind]
def marks(out):return [r.get('markers','MISSING markers field') for r in select(out,'merged_pr')]
def logs():return [a for a in records(calls) if 'log' in a and '--first-parent' not in a and '--format=%ct' not in a]
git('init','-q','--object-format=sha1','-b','main');git('config','user.name','RED127');git('config','user.email','red127@example.invalid');git('config','gc.auto','0');git('config','maintenance.auto','false')
write('seed','127\n');base=commit();git('tag','v1.0.0')
tools=cw/'tools127';tools.mkdir();calls=cw/'calls127';fault=cw/'fault127';events=cw/'events127';ghcalls=cw/'gh127'
(tools/'git').write_text('#!'+sys.executable+'\n'+'''import json,os,subprocess,sys
from pathlib import Path
'''+f'a=sys.argv[1:];fault=Path({str(fault)!r});calls=Path({str(calls)!r});events=Path({str(events)!r})\n'+'''with calls.open('a') as f:f.write(json.dumps(a)+'\\n')
with events.open('a') as f:f.write('git '+json.dumps(a)+'\\n')
mode=fault.read_text() if fault.exists() else ''
is_marker='log' in a and '--first-parent' not in a and '--format=%ct' not in a
if mode=='preflight' and 'for-each-ref' in a:raise SystemExit(93)
if is_marker and mode:
 if mode=='exit':raise SystemExit(94)
 if mode=='signal':
  import signal
  os.kill(os.getpid(),signal.SIGTERM)
 if mode=='garbage':sys.stdout.buffer.write(b'incomplete\\x00record');raise SystemExit(0)
 if mode=='truncate':
  p=subprocess.run(['''+repr(realgit)+''',*a],capture_output=True);sys.stdout.buffer.write(p.stdout[:-5]);raise SystemExit(0)
os.execv('''+repr(realgit)+''',['''+repr(realgit)+''',*a])
''');(tools/'git').chmod(0o755)
(tools/'gh').write_text('#!'+sys.executable+'\nimport json,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith open('+repr(str(ghcalls))+',"a") as f:f.write(json.dumps(a)+"\\n")\nwith open('+repr(str(events))+',"a") as f:f.write("gh\\n")\nraise SystemExit(92)\n');(tools/'gh').chmod(0o755)
env['PATH']=str(tools)+os.pathsep+env['PATH']
if case=='control-history':
 sha=red(message=b'control fixture\n');s=output(rows());assert select(s,'merged_pr')[0]['red_to_merge']==99 and select(s,'dora')[0]['git']['releases']==1,s
 assert git('show',sha+':.shipcraft/locks/A.json')=='{}' and git('rev-parse',sha+'^')==base
elif case=='control-fault':
 red();fault.write_text('preflight');s=output(rows());assert select(s,'dora')[0]['git']['reason'].endswith('exited 93') and select(s,'merged_pr')[0]['red_to_merge']==99,s
elif case=='control-gh':
 red();s=output(rows(),('--json','--github'));assert records(ghcalls)==[['pr','view','7','--json','number,state,mergedAt,headRefOid,mergeCommit']] and select(s,'github')[0]['missing']=={'gh failed':1},s
elif case=='control-findings':
 red();s=output(rows(),('--findings','--json'));assert records(ghcalls)==[['pr','list','--state','merged','--limit','1000','--json','number']] and records(calls)==[['remote','get-url','origin']],s
 assert s==[dict(kind='findings_not_read',reason='gh failed')],s
elif case=='merge':
 git('checkout','-qb','topic');sha=red();git('checkout','main');write('main','diverged');main=commit(at=T+20);git('checkout',sha,'--','.shipcraft');commit(b'merge\n',[main,sha],T+30)
 s=output(rows());assert marks(s)==[{'order':'yes'}],s
elif case=='branch':
 git('checkout','-qb','topic');red();git('checkout','main');write('squash','without lock');commit(at=T+20)
 s=output(rows());assert marks(s)==[{'order':'yes'}],s
elif case=='refs':
 sha=red();git('tag','kept-red',sha);git('reset','--hard',base);a=output(rows());git('update-ref','refs/remotes/origin/kept',sha);git('tag','-d','kept-red');b=output(rows())
 assert marks(a)==marks(b)==[{'order':'yes'}],(a,b)
elif case=='deleted':
 red();git('reset','--hard',base);s=output(rows());assert marks(s)==[None] and not select(s,'marker'),s
elif case=='candidates':
 a=red(message=b'order cases: no\n',at=T+30);git('tag','later',a);b=red(message=b'order cases: yes\n',at=T+10,parent=base);git('tag','earlier',b);s=output(rows())
 c=red(message=b'order cases: maybe\n',at=T+10,parent=base);t=output(rows())
 assert marks(s)==[{'order':'yes'}] and marks(t)==[{'order':'yes' if b<c else 'maybe'}],(s,t)
elif case=='first-lock':
 red('A',b'order cases: yes\n');red('B',b'order cases: no\n',parent=base);git('tag','B');red('C',b'order cases: maybe\n',parent=base);git('tag','C');red('A',b'order cases: yes\n',parent=base)
 rs=[row(lock='C',at=30),row(lock='A',at=10),row(lock='B',at=20),row('merge',lock='C',locks=['B','A'])];s=output(rs)
 rs[1]['at']=20;t=output(rs);assert marks(s)==[{'order':'yes'}] and marks(t)==[{'order':'no'}],(s,t)
elif case=='red-rows':
 red();rs=[row(at=1,redo=True,commit='f'*40),row(at=2,result='refused',commit='f'*40),row(at='0',commit='f'*40),row(at=4,commit=base),row(at=4,commit='e'*40),row(at=5,commit='d'*40),row('merge')];s=output(rs)
 assert marks(s)==[{'order':'yes'}],s
elif case=='parents':
 red();observations=[]
 for parent in (base[:12],base.upper(),None,'g'*40,'f'*64,'e'*40):
  calls.unlink(missing_ok=True);s=output(rows(commit=parent));observations.append((marks(s),len(logs())))
 assert observations==[([None],0)]*4+[([None],1)]*2,observations
elif case=='paths':
 ids=['space " tab\tline\n','café','cafe\u0301'];rs=[];blob=git('hash-object','-w','--stdin',data=b'{}\n')
 for i,lock in enumerate(ids,1):
  tree=git('mktree','-z',data=b'100644 blob '+blob.encode()+b'\t'+lock.encode()+b'.json\0'+b'100644 blob '+blob.encode()+b'\tbad\xff.json\0')
  tree=git('mktree','-z',data=b'040000 tree '+tree.encode()+b'\tlocks\0');tree=git('mktree','-z',data=b'040000 tree '+tree.encode()+b'\t.shipcraft\0')
  sha=git('commit-tree',tree,'-p',base,data=b'custom cases: 010\n',at=T+10);git('tag','path'+str(i),sha);rs+=rows(lock,i)
 s=output(rs);assert marks(s)==[{'custom':'010'}]*3,s
elif case=='modes':
 outcomes=[]
 for i,mode in enumerate(('executable','symlink','directory','existing','rename','merge','gitlink'),1):
  git('reset','--hard',base);path=root/'.shipcraft/locks/A.json';path.parent.mkdir(parents=True,exist_ok=True);parent=base
  if mode=='existing':path.symlink_to('missing');parent=commit()
  if mode=='merge':write('second-parent','distinct');parent=commit()
  if mode=='rename':write('old','{}');parent=commit()
  if path.is_symlink():path.unlink()
  if mode=='symlink':path.symlink_to('missing')
  elif mode=='directory':write('.shipcraft/locks/A.json/child','{}')
  else:write('.shipcraft/locks/A.json','{}')
  if mode=='executable':path.chmod(0o755)
  if mode=='rename':(root/'old').unlink()
  if mode=='gitlink':
   tree=git('mktree',data=f'160000 commit {base}\tA.json\n'.encode());tree=git('mktree',data=f'040000 tree {tree}\tlocks\n'.encode());tree=git('mktree',data=f'040000 tree {tree}\t.shipcraft\n'.encode());sha=git('commit-tree',tree,'-p',parent,data=b'order cases: yes\n');git('update-ref','HEAD',sha)
  else:sha=commit(b'order cases: yes\n',parents=[parent,base] if mode=='merge' else [parent])
  s=output(rows(commit=parent));outcomes.append(marks(s))
 assert outcomes==[[{'order':'yes'}],[None],[None],[None],[{'order':'yes'}],[None],[None]],outcomes
elif case=='replacement':
 original=red(message=b'order cases: yes\n');replacement=red(message=b'order cases: no\n',at=T+20,parent=base);git('reset','--hard',original);git('replace',original,replacement);s=output(rows());assert marks(s)==[{'order':'yes'}],s
elif case=='messages':
 red(message=b'ledger cases: 11\n\norder cases: yes\nledger cases: 2\norder cases: no\n');s=output(rows());assert marks(s)==[{'ledger':'11','order':'yes'}],s
elif case=='grammar':
 message=('a cases: Z9\n'+'z'*32+' cases: '+'9'*32+'\n'+'x'*33+' cases: yes\nx cases: '+'1'*33+'\n order cases: yes\norder cases: yes \nOrder cases: yes\nx  cases: yes\nx cases:  yes\nx cases: \nx cases: -1\néd cases: yes\nx cases: ١\n')
 red(message=message.encode());s=output(rows());assert marks(s)==[{'a':'Z9','z'*32:'9'*32}],s
elif case=='line-endings':
 red(message='order cases: yes\r\nledger cases: 00\r\nplain cases: no\r\rx cases: yes\ny cases: yes\u2028z cases: no\n\ufeffbom cases: yes\nq cases: yes\u2029w cases: no\n'.encode());s=output(rows());assert marks(s)==[{'order':'yes','ledger':'00'}],s
elif case=='encoding':
 git('config','i18n.commitEncoding','ISO-8859-1');git('config','i18n.logOutputEncoding','ISO-8859-1');red(message=b'caf\xe9\norder cases: yes\n');s=output(rows());assert select(s,'dora')[0]['git']['releases']==1,s
 assert marks(s)==[{'order':'yes'}],s
elif case=='framing':
 sha=red(message=b'commit '+base.encode()+b'\n\x1e\x1f\t.shipcraft/locks/B.json\n\norder cases: yes\nnoise BADBYTE\nledger cases: 010\n')
 raw=run(realgit,'cat-file','commit',sha).stdout.replace(b'BADBYTE',b'\xff');sha=git('hash-object','-t','commit','-w','--stdin',data=raw);git('update-ref','HEAD',sha)
 s=output(rows());assert marks(s)==[{'order':'yes','ledger':'010'}] and not select(s,'gap'),s
elif case=='groups':
 rs=[]
 for i,value in enumerate(('yes','1','010','9'*32,'no','0','00','Yes','maybe','n2'),1):
  sha=red(str(i),f'order cases: {value}\n'.encode(),parent=base);git('tag','g'+str(i),sha);rs+=rows(str(i),i)
 rs+=rows('absent',11);s=output(rs);m=select(s,'marker');assert [(r['group'],r['merged_prs']) for r in m]==[('set',4),('unset',3),('none',4)],s
 assert all(set(r)=={'kind','marker','group','since','merged_prs','reviewed_prs','round1_approved_share','changes_requested_per_pr','three_rounds','three_rounds_share'} for r in m),m
 assert all(r['reviewed_prs']==0 and r['round1_approved_share'] is None and r['changes_requested_per_pr'] is None and r['three_rounds']==0 and r['three_rounds_share'] is None for r in m),m
elif case=='ratios':
 red();rs=sum((rows(pr=i) for i in range(1,5)),[])+[row('review',pr=1),row('review',pr=2,result='refused'),row('review',pr=2),row('review',pr=2,result='refused'),row('review',pr=3,result='refused'),row('review',pr=3,result='refused'),row('review',pr=3),row('review',pr=1,reused=True,result='refused')]
 s=output(rs);assert select(s,'marker') and select(s,'marker')[0]==dict(kind='marker',marker='order',group='set',since=None,merged_prs=4,reviewed_prs=3,round1_approved_share=1/3,changes_requested_per_pr=4/3,three_rounds=2,three_rounds_share=2/3),s
 t=report(rs,()).stdout.decode().splitlines();assert 'marker order cases set: 4 merged PR(s), 3 reviewed, approved on round 1 33%, 1.33 change requests per PR, 3 or more rounds 2 (67%)' in t,t
elif case=='text':
 red();rs=rows()+[row('review')];p=report(rs,());lines=p.stdout.decode().split('\n');assert p.returncode==0 and not p.stderr
 assert [l for l in lines if l.startswith('marker ')]==['marker order cases set: 1 merged PR(s), 1 reviewed, approved on round 1 100%, 0.00 change requests per PR, 3 or more rounds 0 (0%)','marker order cases unset: 0 merged PR(s), 0 reviewed, approved on round 1 -, - change requests per PR, 3 or more rounds 0 (-)','marker order cases none: 0 merged PR(s), 0 reviewed, approved on round 1 -, - change requests per PR, 3 or more rounds 0 (-)'],lines
elif case=='position':
 red(message=b'z cases: yes\na cases: no\n');rs=[row('pr',pr=7,product_lines=20,warn_lines=600)]+rows(pr=7);s=output(rs);ks=[r['kind'] for r in s];assert 'limit' in ks and select(s,'merged_pr')[0]['product_lines']==20,s
 m=select(s,'marker');assert [(r['marker'],r['group']) for r in m]==[(w,g) for w in ('a','z') for g in ('set','unset','none')],s
 i=ks.index('marker');assert ks[i-1]=='limit' and ks[i+6]=='dora';t=report(rs,()).stdout.decode().splitlines();j=t.index('DORA');assert all(l.startswith('marker ') for l in t[j-6:j]) and t[j-7].startswith('suggested limit:'),t
elif case=='since-tag':
 red();git('tag','-a','v2.0.0','-m','window',at=T+50);rs=rows()+rows(pr=8)+rows(pr=9);rs[1]['at']=T+49;rs[3]['at']=T+50;rs[5]['at']=None;s=output(rs,('--json','--since','v2.0.0'))
 assert len(select(s,'merged_pr'))==3 and select(s,'marker') and select(s,'marker')[0]['merged_prs']==1 and all(r['since']=='v2.0.0' for r in select(s,'marker')),s
 t=report(rs,('--since','v2.0.0')).stdout.decode().splitlines();assert 'marker order cases set: 1 merged PR(s), 0 reviewed, approved on round 1 -, - change requests per PR, 3 or more rounds 0 (-); since v2.0.0' in t,t
elif case=='since-merge':
 sha=red(at=T+50);write('.shipcraft.toml','[report]\ndeploy="merge"\n');rs=rows()+rows(pr=8);rs[1]['at']=T+49;rs[3]['at']=T+50;s=output(rs,('--json','--since',sha[:9]));assert len(select(s,'merged_pr'))==2 and select(s,'marker') and select(s,'marker')[0]['merged_prs']==1 and select(s,'marker')[0]['since']==sha[:9],s
elif case=='window-empty':
 red();git('tag','-a','v2.0.0','-m','future',at=T+200);s=output(rows(),('--json','--since','v2.0.0'));assert marks(s)==[{'order':'yes'}] and not select(s,'marker'),s
elif case=='once':
 red();rs=sum((rows(pr=i) for i in range(1,21)),[]);s=output(rs);assert len(logs())==1 and marks(s)==[{'order':'yes'}]*20,(s,records(calls))
elif case=='read-exit':
 red();before=output(rows());calls.unlink();fault.write_text('exit');s=output(rows());assert len(logs())==1 and marks(s)==[None] and not select(s,'marker') and select(s,'dora')==select(before,'dora') and not select(s,'gap'),s
elif case=='read-truncated':
 red();fault.write_text('truncate');s=output(rows()+rows(pr=8));assert len(logs())==1 and marks(s)==[None,None] and not select(s,'marker') and not select(s,'gap'),s
elif case=='read-garbage':
 red();fault.write_text('garbage');s=output(rows());assert len(logs())==1 and marks(s)==[None] and not select(s,'marker') and not select(s,'gap'),s
elif case=='unavailable':
 red();write('.shipcraft.toml','[report]\nrelease_tags=""\n');s=output(rows());assert marks(s)==[None] and not logs() and not select(s,'marker') and 'invalid' in select(s,'dora')[0]['git']['reason'],s
elif case=='refused':
 red();p=report(rows(),('--since','v9.9.9','--github'));assert p.returncode==2 and not p.stdout and p.stderr==b'report: --since v9.9.9 is not a release tag on refs/heads/main\n' and not logs() and not ghcalls.exists(),p.stderr
elif case=='later-gh':
 red();s=output(rows(),('--json','--github'));assert marks(s)==[{'order':'yes'}] and select(s,'marker')[0]['merged_prs']==1 and select(s,'github')[0]['missing']=={'gh failed':1},s
 ev=events.read_text().splitlines();assert len(logs())==1 and next(i for i,x in enumerate(ev) if x=='git '+json.dumps(logs()[0]))<ev.index('gh'),ev
elif case=='no-markers':
 red(message=b'ordinary RED\n');s=output(rows()+rows('missing',8));assert marks(s)==[{},None] and not select(s,'marker'),s
elif case=='signed':
 key=cw/'key127';p=run('ssh-keygen','-q','-t','ed25519','-N','','-f',key);assert p.returncode==0,p.stderr
 git('config','gpg.format','ssh');git('config','user.signingkey',str(key));write('.shipcraft/locks/A.json','{}');git('add','-A');tree=git('write-tree');sha=git('commit-tree','-S',tree,'-p',base,data=b'order cases: yes\n',at=T+10);git('update-ref','HEAD',sha)
 proof=cw/'verifier-hit';verifier=tools/'verifier';verifier.write_text('#!'+sys.executable+'\nfrom pathlib import Path\nPath('+repr(str(proof))+').touch()\nraise SystemExit(91)\n');verifier.chmod(0o755);git('config','log.showSignature','true');git('config','gpg.ssh.program',str(verifier));git('config','gpg.program',str(verifier))
 s=output(rows());assert marks(s)==[{'order':'yes'}] and not proof.exists(),s
elif case=='read-signal':
 red();fault.write_text('signal');s=output(rows());assert len(logs())==1 and marks(s)==[None] and not select(s,'marker') and not select(s,'gap'),s
elif case=='control-empty':
 a=report([]);b=report([row('merge',pr=None)]);assert a.returncode==b.returncode==0 and not a.stderr and not b.stderr and not logs()
 assert [r['kind'] for r in map(json.loads,a.stdout.splitlines())]==['meta','dora']
 assert select(list(map(json.loads,a.stdout.splitlines())),'dora')==select(list(map(json.loads,b.stdout.splitlines())),'dora')
elif case=='control-proxy':
 sha=red();p=run('git','log','-1','--format=%H');assert p.returncode==0 and p.stdout.strip()==sha.encode(),p
 fault.write_text('exit');p=run('git','log','-1','--format=%H');assert p.returncode==94 and not p.stdout,p
 fault.write_text('garbage');p=run('git','log','-1','--format=%H');assert p.returncode==0 and p.stdout==b'incomplete\x00record',p
 fault.write_text('truncate');p=run('git','log','-1','--format=%H');assert p.returncode==0 and p.stdout==sha.encode()[:-4],p
 fault.write_text('signal');p=run('git','log','-1','--format=%H');assert p.returncode<0,p
 fault.unlink();s=output(rows());assert select(s,'merged_pr')[0]['red_to_merge']==99,s
elif case=='no-first':
 red();rs=[row('merge',pr=1,lock='never'),row('merge',pr=2,lock='',locks=[]),row(lock='absent',pr=3,at=1),row(pr=3,at=2),row('merge',pr=3,lock='absent',locks=['A'])]
 s=output(rs);assert marks(s)==[None,None,None] and not select(s,'marker'),s
else:raise AssertionError(('unrouted',case))
PY127
 pass
}
