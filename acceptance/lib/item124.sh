# Item 124: real first-parent histories, public commands, no network.
item124_langs() { echo core; }
item124_cases() {
 local c
 for c in control-release control-check control-fault control-since fallback outside custom readers merge-tags release-empty release-tags first-parent removed shipping-source times missing rework recover failure before after unknown ignores since since-empty git-failure bad-time signed shallow partial unavailable-default unavailable-config invalid-report check-merge check-release invalid-string invalid-type precedence status selection; do echo "v1-124.$c"; done
}
item124_case() {
 EXPECT="item 124: ${CASE#v1-124.}"; v1_start codex
 must_accept 'merge deployment contract' cmd "$PY" - "${CASE#v1-124.}" "$(command -v shipcraft)" "$CW" <<'PY124'
import datetime,hashlib,json,os,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/'repo124 space';root.mkdir();realgit=shutil.which('git');env=dict(os.environ,TZ='Pacific/Honolulu')
for k in subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
def run(*args,at=None,data=None):
 e=dict(env)
 if at is not None:e.update(GIT_AUTHOR_DATE=f'{at} +0000',GIT_COMMITTER_DATE=f'{at} +0000')
 p=subprocess.run(list(map(str,args)),cwd=root,env=e,input=data,capture_output=True,timeout=30)
 print('COMMAND124',args,p.returncode,repr(p.stdout),repr(p.stderr),flush=True);return p
def git(*args,**kw):
 p=run(realgit,*args,**kw);assert p.returncode==0,('fixture git',args,p.stderr);return p.stdout.decode().strip()
def write(name,value):
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value if isinstance(value,bytes) else value.encode())
def save(at,parents=None):
 git('add','-A');tree=git('write-tree')
 if parents is None:
  p=run(realgit,'rev-parse','--verify','HEAD');parents=[p.stdout.decode().strip()] if p.returncode==0 else []
 sha=git('commit-tree',tree,*[x for p in parents for x in ('-p',p)],at=at,data=b'fixture124\n');git('update-ref','HEAD',sha);return sha
def utc(t):return datetime.datetime.fromtimestamp(t,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
def lock(id,kind='feature',reported=None,fixes=None,fmt=4):
 d=dict(format=fmt,state='closed',files={'tests/test_value.py':'sha256:'+hashlib.sha256(b'def test_value(): assert False\n').hexdigest()},cases=['tests/test_value.py::test_value'],failing_at_red=['tests/test_value.py::test_value'])
 if fmt==4:d.update(kind=kind,reported_at=reported,fixes_release=fixes)
 d['seal']='';d['seal']=hashlib.sha256(json.dumps(d,separators=(',',':')).encode()).hexdigest();write('.shipcraft/locks/'+id+'.json',json.dumps(d)+'\n')
def config(body):write('.shipcraft.toml',base+body)
def tags():
 git('tag','-a','v1.0.0',r1,'-m','release124',at=T);git('tag','v2.0.0',r2);git('tag','v3.0.0',r3)
def snapshot():
 return {str(p.relative_to(root)):(stat.S_IFMT(p.lstat().st_mode),stat.S_IMODE(p.lstat().st_mode),os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None) for p in root.rglob('*')}
def report(*args):
 before=snapshot();p=run(binary,'report',*args);assert snapshot()==before,'report wrote repository state'
 assert not forbidden.exists(),'report started an external service or verifier';return p
def decoded(*args):
 p=report('--json',*args);assert p.returncode==0 and not p.stderr,(p.returncode,p.stderr)
 rows=[json.loads(s) for s in p.stdout.splitlines()];return next(r for r in rows if r['kind']=='dora'),{r['lock']:r for r in rows if r['kind']=='lock'}
def history(bkind='fix',reported=None,fixes='v1.0.0',fmt=4,times=None):
 global r1,r2,r3
 times=times or (T,T+100,T+200)
 lock('A');r1=save(times[0]);lock('B',bkind,reported,fixes,fmt);r2=save(times[1]);write('third','direct push / squash\n');r3=save(times[2])
 write('.git/shipcraft/runs.jsonl',''.join(json.dumps(dict(layer='red',at=at,lock=id,result='passed',secs=1,branch='item/124',commit=r1,code='',reason=''))+'\n' for id,at in [('A',T-10),('B',T+80)]))
T=1700000000;base='shipcraft_min="0.0"\nlang="python"\nrunner="pytest"\ntest_command="echo never124 {junit}"\n'
git('init','-q','-b','main');git('config','user.name','RED124');git('config','user.email','red124@example.invalid');git('config','gc.auto','0');git('config','maintenance.auto','false')
write('tests/test_value.py','def test_value(): assert False\n');config('')
tools=cw/'tools124';tools.mkdir();calls=cw/'git-calls124';fault=cw/'fault124';hit=cw/'fault-hit124';forbidden=cw/'forbidden124'
proxy=tools/'git';proxy.write_text('#!'+sys.executable+'\nimport os,sys,json\nfrom pathlib import Path\na=sys.argv[1:]\nwith open('+repr(str(calls))+',"a") as f:f.write(json.dumps(a)+"\\n")\nf=Path('+repr(str(fault))+')\nmode=f.read_text() if f.exists() else ""\nif mode and ("log" in a or "rev-list" in a):\n Path('+repr(str(hit))+').write_text(mode)\n if mode=="bad-time":print("not-a-time");raise SystemExit(0)\n raise SystemExit(93)\nos.execve('+repr(realgit)+',['+repr(realgit)+',*a],dict(os.environ))\n');proxy.chmod(0o755)
for name in ('gh','codex','claude','curl','wget','ssh','verifier124'):
 p=tools/name;p.write_text('#!'+sys.executable+'\nfrom pathlib import Path\nPath('+repr(str(forbidden))+').touch()\nraise SystemExit(92)\n');p.chmod(0o755)
env['PATH']=str(tools)+os.pathsep+env['PATH']
if case=='control-release':
 history(reported=utc(T+50));tags();d,ls=decoded()
 assert d['deploys']==dict(value=dict(count=3,first=T,last=T+200,per_day=1296),n=3,missing=0,reason=None),d
 assert d['lead_time']['value']==dict(median=15,p90=20) and d['rework_rate']['value']==0.5 and d['change_failure_rate']['value']==1/3 and d['time_to_recover']['value']==dict(median=50,p90=50),d
 assert ls['B']['reported_at']==utc(T+50) and ls['B']['fixes_release']=='v1.0.0' and calls.is_file(),ls
elif case=='control-check':
 save(T);config('[report]\nrelease_tags="deploy-*"\n');git('add','.shipcraft.toml');p=run(binary,'check')
 assert p.returncode==0 and b'shipcraft: no open lock; commit allowed.' in p.stdout,(p.stdout,p.stderr)
 row=json.loads((root/'.git/shipcraft/runs.jsonl').read_text().splitlines()[-1]);assert row['layer']=='hook' and row['result']=='passed',row
elif case=='control-fault':
 history(reported=utc(T+50));tags();fault.write_text('exit');d,_=decoded()
 assert hit.read_text()=='exit' and d['git']['reason'].endswith('exited 93') and d['deploys']['value'] is None,d
elif case=='control-since':
 history(reported=utc(T+50));fault.write_text('exit');p=report('--json','--since','v9.0.0')
 assert p.returncode==2 and not p.stdout and p.stderr==b'report: --since v9.0.0 is not a release tag on refs/heads/main\n' and not hit.exists(),p
elif case=='fallback':
 history(reported=utc(T+50));(root/'.shipcraft.toml').unlink();d,_=decoded()
 assert d['deploys']==dict(value=dict(count=3,first=T,last=T+200,per_day=1296),n=3,missing=0,reason=None),d
 assert d['git']==dict(default_branch='refs/heads/main',deploy='merge',deploy_source='fallback',merges=3,reason=None,release_tags=None,releases=0),d
 s=report().stdout.decode();assert 'git: default branch refs/heads/main; 3 merge(s); lock rows without log times come from the branch tip; release tags: vX.Y.Z; deploys are merges to the default branch (no release tag read)' in s,s
 assert 'deploys: 3 merge(s), first at '+utc(T)+', last at '+utc(T+200)+', per day 1296.00 (n 3, missing 0)' in s,s
elif case=='outside':
 history(reported=utc(T+50));git('tag','draken-platform-v0.1.0');d,_=decoded()
 assert d['deploys']['n']==3 and d['git']['releases']==0 and d['git']['deploy_source']=='fallback',d
elif case=='custom':
 history(reported=utc(T+50));tags();config('[report]\nrelease_tags="deploy-*"\n');d,_=decoded()
 assert d['deploys']['n']==3 and d['git']['releases']==0 and d['git']['release_tags']=='deploy-*' and d['git']['deploy']=='merge',d
elif case=='readers':
 history(reported=utc(T+50));observed=[]
 for content in (None,b'bad [ TOML',b'\xff',b'[report]\n',b''):
  p=root/'.shipcraft.toml';p.unlink(missing_ok=True)
  if content is None:p.mkdir()
  else:p.write_bytes(content)
  observed.append(decoded()[0])
  if p.is_dir():p.rmdir()
 assert all(d['deploys']['n']==3 and d['git']['deploy_source']=='fallback' for d in observed),observed
elif case=='merge-tags':
 history(reported=utc(T+50));tags();config('report = {deploy="merge"} # inline\n');d,_=decoded()
 assert d['deploys']['n']==3 and d['git']['deploy']=='merge' and d['git']['deploy_source']=='config' and d['git']['releases']==3 and d['git']['merges']==3,d
 s=report().stdout.decode();assert 'deploys are merges to the default branch ([report] deploy = "merge")' in s,s
elif case=='release-empty':
 history(reported=utc(T+50));config('[report]\ndeploy="release"\n');d,_=decoded()
 assert d['deploys']==dict(value=None,n=0,missing=0,reason='no release read') and d['git']['deploy']=='release' and d['git']['merges'] is None,d
elif case=='release-tags':
 history(reported=utc(T+50));tags();before=report().stdout;config('[report]\ndeploy="release"\n');after=report().stdout;d,_=decoded()
 assert before==after,(before,after)
 assert d['git']['deploy']=='release' and d['git']['deploy_source']=='config' and d['git']['merges'] is None and d['lead_time']['n']==2,d
elif case=='first-parent':
 lock('A');r1=save(T);git('checkout','-qb','side124');lock('side');side=save(T+10);write('side-more','second PR commit');side2=save(T+20);git('checkout','-q','main');write('direct','direct');direct=save(T+30)
 git('checkout',side2,'--','.shipcraft/locks/side.json');merge=save(T+100,[direct,side2]);write('squash','squashed PR');save(T+200)
 d,_=decoded();assert d['deploys']['n']==4 and d['git']['merges']==4 and d['rework_rate']['n']==2 and d['lead_time']['missing']==2,d
elif case=='removed':
 history(reported=utc(T+50));(root/'.shipcraft/locks/A.json').unlink();save(T+300);(root/'.git/shipcraft/runs.jsonl').unlink();d,ls=decoded()
 assert d['rework_rate']['n']==2 and d['rework_rate']['value']==0.5 and d['lead_time']['missing']==2 and 'A' not in ls,d
elif case=='shipping-source':
 history(reported=utc(T+50));lock('B','feature');save(T+300);(root/'.shipcraft/locks/B.json').unlink();save(T+400)
 git('checkout','-qb','head124');lock('B','fix',utc(T+25),'v9.0.0');save(T+500);d,ls=decoded()
 assert ls['B']['reported_at']==utc(T+50) and ls['B']['fixes_release']=='v1.0.0' and d['time_to_recover']['value']==dict(median=50,p90=50), (d,ls)
elif case=='times':
 history(reported=utc(T-50),times=(T+200,T+100,T));d,_=decoded()
 assert d['deploys']['value']==dict(count=3,first=T,last=T+200,per_day=1296),d
 assert d['lead_time']['value']==dict(median=115,p90=210) and d['change_failure_rate']['missing']==1,d
elif case=='missing':
 history(reported=utc(T+50));write('.git/shipcraft/runs.jsonl','');d,_=decoded()
 assert d['lead_time']==dict(value=None,n=0,missing=2,reason='2 shipped lock(s) without a passed red row in this run log, or merged before it'),d
elif case=='rework':
 history(reported=utc(T+50));d,_=decoded()
 assert d['rework_rate']==dict(value=0.5,n=2,missing=0,reason=None),d
elif case=='recover':
 history(reported=utc(T+50));d,_=decoded()
 assert d['time_to_recover']==dict(value=dict(median=50,p90=50),n=1,missing=0,reason=None),d
elif case=='failure':
 history(reported=utc(T+40),times=(T+40,T+20,T+200));lock('C','fix',utc(T+50));save(T+300);d,_=decoded()
 # B names A in the same second; C names B (latest on the line), not A (latest time).
 assert d['change_failure_rate']==dict(value=0.5,n=4,missing=0,reason=None),d
elif case=='before':
 history(reported=utc(T-1));d,_=decoded()
 assert d['change_failure_rate']==dict(value=None,n=3,missing=1,reason='1 shipped lock(s) with an unknown change_kind, or fix lock(s) with no merge before their reported_at'),d
elif case=='after':
 history(reported=utc(T+500));d,_=decoded()
 assert d['change_failure_rate']==dict(value=1/3,n=3,missing=0,reason=None),d
 assert d['time_to_recover']==dict(value=None,n=0,missing=1,reason='1 shipped fix lock(s) without reported_at, or merged before it'),d
elif case=='unknown':
 history(fmt=3);d,_=decoded()
 assert d['rework_rate']==dict(value=None,n=2,missing=1,reason='1 shipped lock(s) with an unknown change_kind'),d
 assert d['change_failure_rate']['n']==3 and d['change_failure_rate']['missing']==1,d
elif case=='ignores':
 history(reported=utc(T+50),fixes=None);d,ls=decoded()
 assert d['change_failure_rate']==dict(value=1/3,n=3,missing=0,reason=None) and ls['B']['fixes_release'] is None,d
elif case=='since':
 history(reported=utc(T+50));tags();config('[report]\ndeploy="merge"\n');d,_=decoded('--since','v2.0.0')
 assert d['git']['merges']==3 and d['git']['releases']==3 and d['deploys']['n']==2 and d['lead_time']['value']==dict(median=20,p90=20),d
 assert d['change_failure_rate']==dict(value=0,n=2,missing=0,reason=None),d
elif case=='since-empty':
 history(reported=utc(T+50));git('tag','-a','v9.0.0','-m','late tag',at=T+300);config('[report]\ndeploy="merge"\n');d,_=decoded('--since','v9.0.0')
 assert d['deploys']==dict(value=None,n=0,missing=0,reason='no merge read') and d['git']['merges']==3,d
 assert d['lead_time']['reason']=='no shipped lock in the merges read' and d['rework_rate']['reason']=='no merge read ships a lock' and d['change_failure_rate']['reason']=='no merge read',d
elif case=='git-failure':
 history(reported=utc(T+50));fault.write_text('exit');d,ls=decoded()
 assert d['git']['reason'] is not None and d['git']['reason'].startswith('git failed:') and d['git']['reason'].endswith('exited 93') and hit.read_text()=='exit',d
 assert d['git']['deploy'] is None and d['git']['deploy_source'] is None and d['git']['merges'] is None and ls['A']['red_at']==T-10,d
 fault.unlink();d,_=decoded();assert d['deploys']['n']==3,d
elif case=='bad-time':
 history(reported=utc(T+50));fault.write_text('bad-time');d,_=decoded()
 assert d['git']['reason'] is not None and d['git']['reason'].startswith('git failed:') and d['deploys']['value'] is None and hit.read_text()=='bad-time',d
elif case=='signed':
 history(reported=utc(T+50));key=cw/'signing124';p=run('ssh-keygen','-q','-t','ed25519','-N','','-f',key);assert p.returncode==0,p.stderr
 git('config','gpg.format','ssh');git('config','user.signingkey',key)
 sha=git('commit-tree','-S',git('rev-parse','HEAD^{tree}'),'-p',r3,at=T+300,data=b'signed124\n');assert 'gpgsig -----BEGIN SSH SIGNATURE-----' in git('cat-file','commit',sha);git('update-ref','HEAD',sha)
 git('config','log.showSignature','true');git('config','gpg.program',tools/'verifier124');git('config','gpg.ssh.program',tools/'verifier124');d,_=decoded()
 assert d['deploys']['n']==4 and d['git']['merges']==4 and not forbidden.exists(),d
elif case=='shallow':
 history(reported=utc(T+50));origin=root;clone=cw/'shallow124';git('clone','--no-local','--depth=1',origin.as_uri(),clone);root=clone;config('[report]\ndeploy="merge"\n');d,_=decoded()
 assert d['git']['reason']=='shallow clone: history incomplete' and d['git']['deploy']=='merge' and d['git']['deploy_source']=='config' and d['git']['merges'] is None,d
elif case=='partial':
 history(reported=utc(T+50));origin=root;git('config','uploadpack.allowFilter','true');clone=cw/'partial124';git('clone','--filter=blob:none','--no-checkout',origin.as_uri(),clone);root=clone;config('[report]\ndeploy="release"\n');shutil.rmtree(origin);d,_=decoded()
 assert d['git']['reason']=='partial clone: report reads no network' and d['git']['deploy']=='release' and d['git']['deploy_source']=='config' and d['git']['merges'] is None,d
elif case=='unavailable-default':
 history(reported=utc(T+50));git('branch','-m','topic124');d,_=decoded()
 assert list(d['git'])==['default_branch','deploy','deploy_source','merges','reason','release_tags','releases'] and d['git']['deploy'] is None and d['git']['deploy_source'] is None and d['git']['merges'] is None and d['git']['reason']=='no default branch',d
elif case=='unavailable-config':
 history(reported=utc(T+50));git('branch','-m','topic124');config('[report]\ndeploy="merge"\n');d,_=decoded('--since','v9.0.0')
 assert d['git']['reason']=='no default branch' and d['git']['deploy']=='merge' and d['git']['deploy_source']=='config' and d['git']['merges'] is None and d['since']=='v9.0.0',d
elif case=='invalid-report':
 history(reported=utc(T+50));config('[report]\ndeploy="Merge"\n');d,ls=decoded('--since','not/a/release')
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: deploy is not "merge" or "release"' and d['git']['deploy'] is None and d['git']['deploy_source'] is None and ls['A']['red_at']==T-10,d
 assert all(d[k]['value'] is None and d[k]['reason']==d['git']['reason'] for k in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate')),d
elif case=='check-merge':
 save(T);config('report.deploy="merge" # dotted\r\n');git('add','.shipcraft.toml');config('[report]\ndeploy=7\n');p=run(binary,'check')
 assert p.returncode==0 and b'no open lock; commit allowed.' in p.stdout,(p.stdout,p.stderr)
elif case=='check-release':
 save(T);config('["report"]\r\n"deploy"="rele\\u0061se" # escaped\r\n');git('add','.shipcraft.toml');p=run(binary,'check')
 log=root/'.git/shipcraft/runs.jsonl';log.unlink();log.mkdir();later=run(binary,'check')
 assert p.returncode==0 and later.returncode==0 and b'no open lock; commit allowed.' in p.stdout and b'no open lock; commit allowed.' in later.stdout,(p.stdout,p.stderr,later.stdout,later.stderr)
elif case=='invalid-string':
 save(T);config('[report]\ndeploy="MERGE"\n');git('add','.shipcraft.toml');p=run(binary,'check');assert p.returncode==1 and (p.stdout+p.stderr).decode().endswith('shipcraft refused: [report] in .shipcraft.toml is invalid: deploy is not "merge" or "release"\nWhy: report reads its releases by this pattern, and shipcraft does not guess one it cannot read\nNext: set release_tags = "<pattern>" (printable ASCII, `*` the only wildcard, not only `*`) as the only key of [report] in .shipcraft.toml, or remove [report], and run again\n'),(p.returncode,p.stdout,p.stderr)
 row=json.loads((root/'.git/shipcraft/runs.jsonl').read_text().splitlines()[-1]);assert row['code']=='config-invalid',row
elif case=='invalid-type':
 save(T);config('[report]\ndeploy=["merge"]\n');git('add','.shipcraft.toml');p=run(binary,'check');assert p.returncode==1 and (p.stdout+p.stderr).decode().endswith('shipcraft refused: [report] in .shipcraft.toml is invalid: deploy is not "merge" or "release"\nWhy: report reads its releases by this pattern, and shipcraft does not guess one it cannot read\nNext: set release_tags = "<pattern>" (printable ASCII, `*` the only wildcard, not only `*`) as the only key of [report] in .shipcraft.toml, or remove [report], and run again\n'),(p.returncode,p.stdout,p.stderr)
elif case=='precedence':
 save(T);config('[report]\nrelease_tags=""\ndeploy=7\n');git('add','.shipcraft.toml');p=run(binary,'check');assert p.returncode==1 and (p.stdout+p.stderr).decode().endswith('shipcraft refused: [report] in .shipcraft.toml is invalid: release_tags is empty\nWhy: report reads its releases by this pattern, and shipcraft does not guess one it cannot read\nNext: set release_tags = "<pattern>" (printable ASCII, `*` the only wildcard, not only `*`) as the only key of [report] in .shipcraft.toml, or remove [report], and run again\n'),(p.returncode,p.stdout,p.stderr)
elif case=='status':
 save(T);config('[report]\ndeploy=false\n');before=snapshot();p=run(binary,'status');assert snapshot()==before and not forbidden.exists();assert p.returncode==1 and (p.stdout+p.stderr).decode().endswith('shipcraft refused: [report] in .shipcraft.toml is invalid: deploy is not "merge" or "release"\nWhy: report reads its releases by this pattern, and shipcraft does not guess one it cannot read\nNext: set release_tags = "<pattern>" (printable ASCII, `*` the only wildcard, not only `*`) as the only key of [report] in .shipcraft.toml, or remove [report], and run again\n'),(p.returncode,p.stdout,p.stderr)
elif case=='selection':
 save(T);config('[report]\nrelease_tags="deploy-*"\ndeploy="merge"\n');before=snapshot();p=run(binary,'red','--fix','--fixes-release','v1.0.0')
 assert p.returncode==2 and snapshot()==before and b'(release tags: deploy-*)' in p.stderr and b'unknown key' not in p.stderr,(p.stdout,p.stderr)
else:raise AssertionError(('unrouted',case))
PY124
 pass
}
