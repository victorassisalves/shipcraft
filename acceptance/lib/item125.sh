# Item 125: real first-parent histories, public commands, no network.
item125_langs() { echo core; }
item125_cases() {
 local c
 for c in control-merge control-tag control-release control-usage control-release-id control-unavailable control-fault control-collision full abbreviated root line-order unknown64 side ambiguous hex-grammar hex-tag merge-failure unavailable-merge github-refused fill-next fill-tip fill-fix fill-unnameable fill-whole-line fill-window fill-clean fill-empty control-json config-readers release-default-reads control-gh-failure failure-gh; do echo "v1-125.$c"; done
}
item125_case() {
 EXPECT="item 125: ${CASE#v1-125.}"; v1_start codex
 must_accept 'merge deployment contract' cmd "$PY" - "${CASE#v1-125.}" "$(command -v shipcraft)" "$CW" <<'PY125'
import datetime,hashlib,json,os,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/'repo125 space';root.mkdir();realgit=shutil.which('git');env=dict(os.environ,TZ='Pacific/Honolulu')
for k in subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
def run(*args,at=None,data=None):
 e=dict(env)
 if at is not None:e.update(GIT_AUTHOR_DATE=f'{at} +0000',GIT_COMMITTER_DATE=f'{at} +0000')
 p=subprocess.run(list(map(str,args)),cwd=root,env=e,input=data,capture_output=True,timeout=30)
 print('COMMAND125',args,p.returncode,repr(p.stdout),repr(p.stderr),flush=True);return p
def git(*args,**kw):
 p=run(realgit,*args,**kw);assert p.returncode==0,('fixture git',args,p.stderr);return p.stdout.decode().strip()
def write(name,value):
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value if isinstance(value,bytes) else value.encode())
def save(at,parents=None):
 git('add','-A');tree=git('write-tree')
 if parents is None:
  p=run(realgit,'rev-parse','--verify','HEAD');parents=[p.stdout.decode().strip()] if p.returncode==0 else []
 sha=git('commit-tree',tree,*[x for p in parents for x in ('-p',p)],at=at,data=b'fixture125\n');git('update-ref','HEAD',sha);return sha
def utc(t):return datetime.datetime.fromtimestamp(t,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
def lock(id,kind='feature',reported=None,fixes=None,fmt=4):
 d=dict(format=fmt,state='closed',files={'tests/test_value.py':'sha256:'+hashlib.sha256(b'def test_value(): assert False\n').hexdigest()},cases=['tests/test_value.py::test_value'],failing_at_red=['tests/test_value.py::test_value'])
 if fmt==4:d.update(kind=kind,reported_at=reported,fixes_release=fixes)
 d['seal']='';d['seal']=hashlib.sha256(json.dumps(d,separators=(',',':')).encode()).hexdigest();write('.shipcraft/locks/'+id+'.json',json.dumps(d)+'\n')
def config(body):write('.shipcraft.toml',base+body)
def tags():
 git('tag','-a','v1.0.0',r1,'-m','release125',at=T);git('tag','v2.0.0',r2);git('tag','v3.0.0',r3)
def snapshot():
 return {str(p.relative_to(root)):(stat.S_IFMT(p.lstat().st_mode),stat.S_IMODE(p.lstat().st_mode),os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None) for p in root.rglob('*')}
def report(*args):
 before=snapshot();p=run(binary,'report',*args);assert snapshot()==before,'report wrote repository state'
 assert not forbidden.exists(),'report started an external service or verifier'
 return p
def decoded(p):
 rows=[json.loads(s) for s in p.stdout.splitlines()];return next(r for r in rows if r['kind']=='dora'),{r['lock']:r for r in rows if r['kind']=='lock'}
def history(bkind='fix',reported=None,fixes='v1.0.0',fmt=4,times=None):
 global r1,r2,r3
 times=times or (T,T+100,T+200)
 lock('A');r1=save(times[0]);lock('B',bkind,reported,fixes,fmt);r2=save(times[1]);write('third','direct push / squash\n');r3=save(times[2])
 write('.git/shipcraft/runs.jsonl',''.join(json.dumps(dict(layer='red',at=at,lock=id,result='passed',secs=1,branch='item/125',commit=r1,code='',reason=''))+'\n' for id,at in [('A',T-10),('B',T+80)]))
T=1700000000;base='shipcraft_min="0.0"\nlang="python"\nrunner="pytest"\ntest_command="echo never125 {junit}"\n'
git('init','-q','--object-format=sha1','-b','main');git('config','user.name','RED125');git('config','user.email','red125@example.invalid');git('config','gc.auto','0');git('config','maintenance.auto','false')
write('tests/test_value.py','def test_value(): assert False\n');config('')
tools=cw/'tools125';tools.mkdir();calls=cw/'git-calls125';fault=cw/'fault125';hit=cw/'fault-hit125';forbidden=cw/'forbidden125'
proxy=tools/'git';proxy.write_text('#!'+sys.executable+'\nimport os,sys,json\nfrom pathlib import Path\na=sys.argv[1:]\nwith open('+repr(str(calls))+',"a") as f:f.write(json.dumps(a)+"\\n")\nf=Path('+repr(str(fault))+')\nmode=f.read_text() if f.exists() else ""\nif mode and ("log" in a or "rev-list" in a):\n Path('+repr(str(hit))+').write_text(mode)\n if mode=="bad-time":print("not-a-time");raise SystemExit(0)\n raise SystemExit(93)\nos.execve('+repr(realgit)+',['+repr(realgit)+',*a],dict(os.environ))\n');proxy.chmod(0o755)
for name in ('gh','codex','claude','curl','wget','ssh','verifier125'):
 p=tools/name;p.write_text('#!'+sys.executable+'\nfrom pathlib import Path\nPath('+repr(str(forbidden))+').touch()\nraise SystemExit(92)\n');p.chmod(0o755)
ghcalls=cw/'gh-calls125'
(tools/'gh').write_text('#!'+sys.executable+'\nimport json,sys\nfrom pathlib import Path\nPath('+repr(str(ghcalls))+').write_text(json.dumps(sys.argv[1:]))\nraise SystemExit(92)\n')
env['PATH']=str(tools)+os.pathsep+env['PATH']
# Replacement refs are part of item 124's real first-parent contract. Mine two
# real commit objects with a seven-digit collision, then graft one onto the other.
def collision():
 git('add','-A');tree=git('write-tree');seen={}
 for n in range(200000):
  raw=f'tree {tree}\nauthor RED125 <red125@example.invalid> {T} +0000\ncommitter RED125 <red125@example.invalid> {T} +0000\n\ncollision {n}\n'.encode()
  sha=hashlib.sha1(b'commit '+str(len(raw)).encode()+b'\0'+raw).hexdigest();prefix=sha[:7]
  if prefix in seen:
   old,oldraw=seen[prefix];git('hash-object','-t','commit','-w','--stdin',data=oldraw);git('hash-object','-t','commit','-w','--stdin',data=raw)
   git('update-ref','HEAD',sha);git('replace','--graft',sha,old);return old,sha
  seen[prefix]=(sha,raw)
 raise AssertionError('fixture collision search exhausted')
if case=='control-merge':
 history(reported=utc(T+50));p=report('--json');assert p.returncode==0 and not p.stderr,p.stderr
 d,ls=decoded(p);assert d['git']['merges']==3 and d['git']['deploy_source']=='fallback' and d['rework_rate']['value']==.5 and d['change_failure_rate']['missing']==0 and ls['B']['reported_at']==utc(T+50),d
 assert calls.is_file() and not any(l.startswith('to fill ') for l in report().stdout.decode().splitlines())
elif case=='control-tag':
 history(reported=utc(T+50));tags();config('[report]\ndeploy="merge"\n');p=report('--json','--since','v2.0.0');assert p.returncode==0,p.stderr
 d,_=decoded(p);assert d['deploys']['n']==2 and d['git']['merges']==3 and d['git']['releases']==3 and d['change_failure_rate']==dict(value=0,n=2,missing=0,reason=None),d
elif case=='control-release':
 history(fmt=3);tags();a=report();config('[report]\ndeploy="release"\n');b=report()
 assert a.returncode==b.returncode==0 and a.stdout==b.stdout and not a.stderr and not b.stderr
 lines=b.stdout.decode().splitlines();assert 'change failure rate: - (n 3, missing 1; 1 shipped lock(s) with an unknown change_kind, or fix lock(s) naming no release)' in lines,lines
 assert not any(l.startswith('to fill ') for l in lines),lines
elif case=='control-usage':
 history();a=report('--since','main~1');b=report('--since','ABCDEF0');c=report('--since','abcdef');assert a.returncode==b.returncode==c.returncode==2 and not a.stdout and not b.stdout and not c.stdout and b.stderr==a.stderr.replace(b'main~1',b'ABCDEF0') and c.stderr==a.stderr.replace(b'main~1',b'abcdef') and not calls.exists(),(a,b,c)
elif case=='control-release-id':
 history();config('[report]\ndeploy="release"\n');a=report('--since','main~1');b=report('--since',r2)
 assert b.returncode==2 and not b.stdout and b.stderr==a.stderr.replace(b'main~1',r2.encode()) and not calls.exists(),b
 config('');tags();calls.unlink(missing_ok=True);c=report('--since',r2);assert c.returncode==2 and not c.stdout and c.stderr==a.stderr.replace(b'main~1',r2.encode()),c
elif case=='control-unavailable':
 history();git('branch','-m','topic125');a=report('--since','main~1');b=report('--since',r2)
 assert b.returncode==2 and not b.stdout and b.stderr==a.stderr.replace(b'main~1',r2.encode()),b
 config('[report]\ndeploy=7\n');c=report('--json','--since',r2);assert c.returncode==0,c.stderr
 d,_=decoded(c);assert d['since']==r2 and d['git']['reason']=='[report] in .shipcraft.toml is invalid: deploy is not "merge" or "release"',d
elif case=='control-fault':
 history();fault.write_text('exit');p=report('--json');assert p.returncode==0,p.stderr
 d,ls=decoded(p);assert hit.read_text()=='exit' and d['git']['reason'].endswith('exited 93') and d['deploys']['value'] is None and ls['A']['state']=='open',d
elif case=='control-collision':
 a,b=collision();assert a!=b and a[:7]==b[:7] and git('log','--first-parent','--format=%H').splitlines()==[b,a]
 p=report('--json');assert p.returncode==0,p.stderr
 d,_=decoded(p);assert d['git']['merges']==2 and d['deploys']['n']==2 and d['git']['deploy']=='merge',d
elif case=='full':
 history(reported=utc(T+50));before=report('--json');p=report('--json','--since',r2);assert p.returncode==0 and not p.stderr,p.stderr
 d,_=decoded(p);assert d['since']==r2 and d['git']['merges']==3 and d['deploys']['n']==2 and d['lead_time']['value']==dict(median=20,p90=20) and d['change_failure_rate']==dict(value=0,n=2,missing=0,reason=None),d
 assert [l for l in before.stdout.splitlines() if json.loads(l)['kind']!='dora']==[l for l in p.stdout.splitlines() if json.loads(l)['kind']!='dora']
 assert not any('rev-parse' in a and any(r2 in x for x in a) for a in map(json.loads,calls.read_text().splitlines()))
elif case=='abbreviated':
 history(reported=utc(T+50));short=r2[:7];p=report('--json','--since',short);assert p.returncode==0 and not p.stderr,p.stderr
 d,_=decoded(p);assert d['since']==short and d['deploys']['n']==2 and d['rework_rate']==dict(value=1,n=1,missing=0,reason=None),d
 lines=report('--since',short).stdout.decode().splitlines();assert f'git: default branch refs/heads/main; 2 merge(s), since {short}; lock rows without log times come from the branch tip; release tags: vX.Y.Z; deploys are merges to the default branch (no release tag read)' in lines,lines
elif case=='root':
 history(reported=utc(T+50));a=report('--json');p=report('--json','--since',r1);assert p.returncode==0,p.stderr
 d,_=decoded(p);old,_=decoded(a);old['since']=r1;assert d==old,(d,old)
elif case=='line-order':
 history(reported=utc(T+50),times=(T+300,T+100,T));p=report('--json','--since',r2);assert p.returncode==0,p.stderr
 d,_=decoded(p);assert d['deploys']==dict(value=dict(count=2,first=T,last=T+100,per_day=None),n=2,missing=0,reason=None) and d['rework_rate']['n']==1,d
elif case=='unknown64':
 history();value='f'*64;p=report('--since',value);assert p.returncode==2 and not p.stdout and p.stderr==f'report: --since {value} is not a merge on refs/heads/main\n'.encode(),p.stderr
elif case=='side':
 lock('A');r1=save(T);git('checkout','-qb','side125');lock('side');side=save(T+10);git('checkout','-q','main');write('direct','main');direct=save(T+20);git('checkout',side,'--','.shipcraft/locks/side.json');save(T+100,[direct,side])
 p=report('--since',side);assert p.returncode==2 and not p.stdout and p.stderr==f'report: --since {side} is not a merge on refs/heads/main\n'.encode(),p.stderr
elif case=='ambiguous':
 a,b=collision();value=a[:7];p=report('--since',value);assert p.returncode==2 and not p.stdout and p.stderr==f'report: --since {value} is not a merge on refs/heads/main\n'.encode(),p.stderr
elif case=='hex-grammar':
 history();config('[report]\nrelease_tags="a*"\n');p=report('--since','abcdef0');assert p.returncode==2 and not p.stdout and p.stderr==b'report: --since abcdef0 is not a merge on refs/heads/main\n',p.stderr
elif case=='hex-tag':
 history(reported=utc(T+50));git('tag','-a',r2,r1,'-m','hex release wins',at=T+200);config('[report]\ndeploy="merge"\nrelease_tags="'+r2[0]+'*"\n')
 p=report('--json','--since',r2);assert p.returncode==0,p.stderr
 d,_=decoded(p);assert d['deploys']['n']==1 and d['git']['releases']==1 and d['git']['merges']==3 and d['rework_rate']['n']==0,d
 # Pair the preserved tag precedence with the new merge-only abbreviated input.
 p=report('--json','--since',r2[:7]);assert p.returncode==0,p.stderr
 d,_=decoded(p);assert d['deploys']['n']==2 and d['since']==r2[:7],d
elif case=='merge-failure':
 history();fault.write_text('exit');p=report('--json','--since',r2);assert p.returncode==0 and not p.stderr,p.stderr
 d,ls=decoded(p);assert hit.read_text()=='exit' and d['since']==r2 and d['git']['reason'].endswith('exited 93') and ls['A']['state']=='open' and ls['A']['red_at']==T-10,d
 assert all(d[k]['value'] is None for k in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate')),d
 fault.unlink();p=report('--json','--since',r2);assert p.returncode==0,p.stderr
 d,_=decoded(p);assert d['deploys']['n']==2,d
elif case=='unavailable-merge':
 history();git('branch','-m','topic125');config('[report]\ndeploy="merge"\n');p=report('--json','--since',r2);assert p.returncode==0,p.stderr
 d,ls=decoded(p);assert d['since']==r2 and d['git']['reason']=='no default branch' and ls['A']['red_at']==T-10 and all(d[k]['value'] is None for k in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate')),d
elif case=='github-refused':
 history();value='e'*40;p=report('--github','--since',value);assert p.returncode==2 and not p.stdout and p.stderr==f'report: --since {value} is not a merge on refs/heads/main\n'.encode() and not ghcalls.exists(),p.stderr
elif case=='fill-next':
 history(fmt=3);p=report();assert p.returncode==0 and not p.stderr,p.stderr
 lines=p.stdout.decode().splitlines();expected=f'to fill rework rate and change failure rate: report --since {r3} (the first merge after {r2}, the last merge that ships a lock counted missing)'
 assert lines.count(expected)==1 and lines[lines.index(expected)-1]=='change failure rate: - (n 3, missing 1; 1 shipped lock(s) with an unknown change_kind, or fix lock(s) with no merge before their reported_at)',lines
elif case=='fill-tip':
 history(fmt=3);lock('C',fmt=2);tip=save(T+300);lines=report().stdout.decode().splitlines()
 expected=f'to fill rework rate and change failure rate: no merge after {tip}, the last merge that ships a lock counted missing'
 assert lines.count(expected)==1,lines
elif case=='fill-fix':
 history(reported=None);lines=report().stdout.decode().splitlines();expected=f'to fill rework rate and change failure rate: report --since {r3} (the first merge after {r2}, the last merge that ships a lock counted missing)'
 assert lines.count(expected)==1 and 'rework rate: 50% (n 2, missing 0)' in lines,lines
elif case=='fill-unnameable':
 history(reported=utc(T-1));lines=report().stdout.decode().splitlines();expected=f'to fill rework rate and change failure rate: report --since {r3} (the first merge after {r2}, the last merge that ships a lock counted missing)'
 assert lines.count(expected)==1,lines
elif case=='fill-whole-line':
 history(fmt=3);lock('C',fmt=3);last=save(T-100);write('tail','empty');nxt=save(T-200);git('tag','-a','v1.0.0',r1,'-m','window excludes latest missing',at=T+50);config('[report]\ndeploy="merge"\n')
 lines=report('--since','v1.0.0').stdout.decode().splitlines();expected=f'to fill rework rate and change failure rate: report --since {nxt} (the first merge after {last}, the last merge that ships a lock counted missing)'
 assert lines.count(expected)==1,lines
elif case=='fill-window':
 history(fmt=3);p=report('--since',r2);assert p.returncode==0,p.stderr
 lines=p.stdout.decode().splitlines();expected=f'to fill rework rate and change failure rate: report --since {r3} (the first merge after {r2}, the last merge that ships a lock counted missing)'
 assert lines.count(expected)==1,lines
elif case=='fill-clean':
 history(fmt=3);lock('C');tip=save(T+300);p=report('--json','--since',r3);assert p.returncode==0,p.stderr
 d,_=decoded(p);assert d['rework_rate']==dict(value=0,n=1,missing=0,reason=None) and d['change_failure_rate']==dict(value=0,n=2,missing=0,reason=None),d
 assert not any(l.startswith('to fill ') for l in report('--since',r3).stdout.decode().splitlines())
elif case=='fill-empty':
 history(fmt=3);p=report('--json','--since',r3);assert p.returncode==0,p.stderr
 d,_=decoded(p);assert d['rework_rate']==dict(value=None,n=0,missing=0,reason='no merge read ships a lock') and d['change_failure_rate']==dict(value=0,n=1,missing=0,reason=None),d
 assert not any(l.startswith('to fill ') for l in report('--since',r3).stdout.decode().splitlines())
elif case=='control-json':
 history(fmt=3);p=report('--json');assert p.returncode==0 and not p.stderr,p.stderr
 assert hashlib.sha256(p.stdout).hexdigest()=='9fd926175c7a357a4088e2afe463e435b68b2f8aa0387b6d36c6753a10da76a2',p.stdout
elif case=='config-readers':
 history(reported=utc(T+50));observations=[]
 for content in (None,b'bad [ TOML',b'\xff',b'[report]\n',b''):
  path=root/'.shipcraft.toml';path.unlink(missing_ok=True)
  if content is None:path.mkdir()
  else:path.write_bytes(content)
  observations.append(report('--json','--since',r2))
  if path.is_dir():path.rmdir()
 (root/'.shipcraft.toml').unlink();observations.append(report('--json','--since',r2))
 assert all(p.returncode==0 and not p.stderr for p in observations),[(p.returncode,p.stderr) for p in observations]
 for p in observations:
  d,_=decoded(p);assert d['since']==r2 and d['deploys']['n']==2 and d['git']['deploy_source']=='fallback',d
elif case=='release-default-reads':
 history();tags();a=report('--since','main~1');p=report('--since',r2)
 assert p.returncode==2 and not p.stdout and p.stderr==a.stderr.replace(b'main~1',r2.encode()),p.stderr
 assert calls.is_file() and any('for-each-ref' in a for a in map(json.loads,calls.read_text().splitlines())),'default release mode must be determined from real tags before refusing a merge id'
elif case=='control-gh-failure':
 history();write('.git/shipcraft/runs.jsonl',json.dumps(dict(layer='merge',at=T+300,lock='A',locks=['A'],pr=7,base='main',default_branch='main',result='passed',secs=1,branch='main',commit=r3,code='',reason=''))+'\n')
 fault.write_text('exit');p=report('--json','--github');assert p.returncode==0 and not p.stderr,p.stderr
 rows=list(map(json.loads,p.stdout.splitlines()));g=next(r for r in rows if r['kind']=='github')
 assert ghcalls.exists() and json.loads(ghcalls.read_text())==['pr','view','7','--json','number,state,mergedAt,headRefOid,mergeCommit'] and g==dict(kind='github',selected=1,merge_filled=0,waiting_filled=0,missing={'gh failed':1}),rows
elif case=='failure-gh':
 history();write('.git/shipcraft/runs.jsonl',json.dumps(dict(layer='merge',at=T+300,lock='A',locks=['A'],pr=7,base='main',default_branch='main',result='passed',secs=1,branch='main',commit=r3,code='',reason=''))+'\n');fault.write_text('exit')
 p=report('--json','--github','--since',r2);assert p.returncode==0 and not p.stderr,p.stderr
 rows=list(map(json.loads,p.stdout.splitlines()));d,ls=decoded(p);g=next(r for r in rows if r['kind']=='github')
 assert hit.read_text()=='exit' and ghcalls.exists() and json.loads(ghcalls.read_text())==['pr','view','7','--json','number,state,mergedAt,headRefOid,mergeCommit'] and g['missing']=={'gh failed':1} and d['since']==r2 and d['git']['reason'].endswith('exited 93') and ls['A']['state']=='merged' and 'B' not in ls,(d,ls,g)
else:raise AssertionError(('unrouted',case))
PY125
 pass
}
