# Item 99: real release repositories; public config/report boundaries only.
item99_langs() { echo core; }
item99_cases() {
  local c
  for c in control-default control-hook control-git-failure deploy prefix wildcard tie since-release since-missing since-offbranch since-mismatch fix-deploy fix-vstar git-failure nested-working reader-variants coverage-default fallback-malformed fallback-utf8 fallback-directory fallback-empty fallback-unrelated invalid-empty invalid-stars invalid-question invalid-bracket invalid-closing invalid-backslash invalid-space invalid-unicode invalid-control invalid-number invalid-array invalid-unknown invalid-nottable invalid-precedence invalid-since hook-source ci-source status-invalid; do echo "v1-99.$c"; done
}
item99_case() {
  EXPECT="item 99: ${CASE#v1-99.}"
  v1_start codex
  must_accept 'project release tag contract' cmd "$PY" - "${CASE#v1-99.}" "$(command -v shipcraft)" "$CW" <<'PY99'
import hashlib,json,os,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/'repo99 space';root.mkdir();realgit=shutil.which('git');env=dict(os.environ,TZ='Pacific/Honolulu')
for k in subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
def run(argv,cwd=None):
 p=subprocess.run(list(map(str,argv)),cwd=cwd or root,env=env,input=b'',capture_output=True,timeout=30)
 print('COMMAND99',argv,p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 return p
def git(*args,data=None,at=1700000000):
 e=dict(env,GIT_AUTHOR_DATE=f'{at} +0000',GIT_COMMITTER_DATE=f'{at} +0000')
 p=subprocess.run([realgit,*map(str,args)],cwd=root,env=e,input=data,capture_output=True,timeout=20)
 assert p.returncode==0,('fixture git',args,p.stderr)
 return p.stdout.decode().strip()
def write(name,value):
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value if isinstance(value,bytes) else value.encode())
def save(at):
 git('add','-A');tree=git('write-tree');parents=['-p',git('rev-parse','HEAD')] if (root/'.git/refs/heads/main').exists() else []
 sha=git('commit-tree',tree,*parents,at=at,data=b'fixture99\n');git('update-ref','HEAD',sha);return sha
def lock(id,kind='feature',fixes=None):
 d=dict(format=4,state='closed',files={'tests/test_value.py':'sha256:'+hashlib.sha256(b'def test_value(): assert False\n').hexdigest()},cases=['tests/test_value.py::test_value'],failing_at_red=['tests/test_value.py::test_value'],kind=kind,reported_at=None,fixes_release=fixes,seal='')
 d['seal']=hashlib.sha256(json.dumps(d,separators=(',',':')).encode()).hexdigest()
 write(Path('.shipcraft/locks')/(id+'.json'),json.dumps(d)+'\n')
def tags(names):
 git('tag','-a',names[0],r1,'-m','release99',at=T)
 git('tag',names[1],r2)
def config(body):write(Path('.shipcraft.toml'),base+body)
def snapshot():
 return {str(p.relative_to(root)):(stat.S_IFMT(p.lstat().st_mode),stat.S_IMODE(p.lstat().st_mode),os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None) for p in root.rglob('*')}
def report(*args,cwd=None):
 before=snapshot();p=run([binary,'report',*args],cwd)
 assert snapshot()==before,'report wrote repository state or a run-log row'
 assert not (cw/'forbidden99').exists(),'report started a service, test or agent'
 return p
def decoded(p):
 assert p.returncode==0 and p.stderr==b'',('report must succeed silently',p.returncode,p.stderr)
 rows=[json.loads(s) for s in p.stdout.splitlines()];d=next(r for r in rows if r['kind']=='dora')
 assert next(r for r in rows if r['kind']=='lock' and r['lock']=='A')['red_at']==T-100,rows
 assert next(r for r in rows if r['kind']=='gap')['line']==3,rows
 return d
T=1700000000
base='shipcraft_min = "0.0"\nlang = "python"\nrunner = "pytest"\ntest_command = "touch '+str(cw/'forbidden99')+'; echo {junit}"\n'
git('init','-q','-b','main');git('config','gc.auto','0');git('config','maintenance.auto','false')
write(Path('tests/test_value.py'),'def test_value(): assert False\n');config('')
lock('A');r1=save(T-1000);lock('B');r2=save(T+86400)
log=root/'.git/shipcraft/runs.jsonl';log.parent.mkdir(parents=True,exist_ok=True)
log.write_text(''.join(json.dumps(dict(layer='red',at=at,lock=id,result='passed',secs=1,branch='feature/99',commit='a'*40,code='',reason=''))+'\n' for id,at in [('A',T-100),('B',T+86200)])+'{broken99\n')
# Every report Git call is recorded and delegates to real Git unless this case
# explicitly injects a failure. External services have no delegation path.
tools=cw/'tools99';tools.mkdir();calls=cw/'git-calls99';failgit=cw/'fail-git99'
proxy=tools/'git';proxy.write_text('#!'+sys.executable+'\n'+"import os,sys\nfrom pathlib import Path\nwith open("+repr(str(calls))+",'a') as f:f.write(repr(sys.argv[1:])+'\\n')\nif Path("+repr(str(failgit))+").exists():raise SystemExit(93)\nos.execve("+repr(realgit)+",["+repr(realgit)+",*sys.argv[1:]],dict(os.environ))\n");proxy.chmod(0o755)
for name in ('gh','codex','claude','gemini','curl','wget','ssh'):
 p=tools/name;p.write_text('#!'+sys.executable+'\nfrom pathlib import Path\nPath('+repr(str(cw/'forbidden99'))+').touch()\nraise SystemExit(92)\n');p.chmod(0o755)
env['PATH']=str(tools)+os.pathsep+env['PATH']
if case=='control-default':
 lock('B','fix','v1.0.0');r2=save(T+86400);tags(('v1.0.0','v2.0.0'))
 d=decoded(report('--json'))
 assert d['git']['releases']==2 and d['git']['reason'] is None,d
 assert d['lead_time']['value']=={'median':150,'p90':200} and d['lead_time']['n']==2,d
 assert d['rework_rate']['value']==0.5 and d['change_failure_rate']['value']==0.5,d;assert calls.is_file() and '-C' in calls.read_text(),calls
elif case=='control-hook':
 config('[report]\nrelease_tags="deploy-*"\n')
 git('add','.shipcraft.toml');p=run([binary,'check'])
 assert p.returncode==0,(p.stdout,p.stderr)
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 assert rows[-1]['layer']=='hook' and rows[-1]['result']=='passed',rows
elif case=='control-git-failure':
 tags(('v1.0.0','v2.0.0'));failgit.touch()
 d=decoded(report('--json'))
 assert d['git']['reason'].endswith('exited 93') and d['deploys']['value'] is None,d
 assert calls.is_file() and calls.read_text(),calls
elif case=='deploy':
 tags(('deploy-20261107-1730','deploy-20261108-1730'));config('[report]\nrelease_tags="deploy-*"\n')
 d=decoded(report('--json'))
 assert d['deploys']==dict(value=dict(count=2,first=T,last=T+86400,per_day=2),n=2,missing=0,reason=None),d
 assert d['lead_time']==dict(value=dict(median=150,p90=200),n=2,missing=0,reason=None),d
 assert d['rework_rate']==dict(value=0,n=2,missing=0,reason=None),d
 assert d['git']['release_tags']=='deploy-*',d
 text=report().stdout.decode();coverage=next(s for s in text.splitlines() if s.startswith('git:'));assert coverage.endswith('; release tags: deploy-*') and not coverage.endswith('.; release tags: deploy-*'),text
elif case=='prefix':
 tags(('draken-platform-v0.1.0','draken-platform-v0.2.0'));git('tag','v1.0.0',r2)
 config('[report]\nrelease_tags="draken-platform-v*"\n')
 d=decoded(report('--json'));assert d['git']['releases']==2 and d['lead_time']['n']==2,d
 config('[report]\nrelease_tags="draken-platform-v0.2.0"\n')
 d=decoded(report('--json'));assert d['git']['releases']==1 and d['git']['release_tags']=='draken-platform-v0.2.0',d
elif case=='wildcard':
 tags(('prod/releases/end','prod/a/b/end'))
 for name in ('Xprod/a/end','prod/a/endX','prod/a/other'):git('tag',name,r2)
 git('checkout','-qb','side99',r1);side=save(T+10);git('tag','prod/off/end',side);git('checkout','-q','main')
 blob=git('hash-object','-w','--stdin',data=b'blob99');git('tag','prod/blob/end',blob);git('tag','prod/tree/end',git('rev-parse','HEAD^{tree}'))
 config('[report]\nrelease_tags="pr*od/*/e**nd"\n')
 d=decoded(report('--json'));assert d['git']['releases']==2 and d['lead_time']['n']==2,d
elif case=='tie':
 git('tag','-a','v1.9.0',r1,'-m','tie99',at=T+86400);git('tag','v1.10.0',r2)
 config('[report]\nrelease_tags="v*"\n')
 d=decoded(report('--json','--since','v1.9.0'))
 assert d['git']['releases']==1 and d['lead_time']['n']==0 and d['lead_time']['missing']==0,d
 assert d['rework_rate']['n']==0,d
elif case=='since-release':
 tags(('deploy-a','deploy-b'));config('[report]\nrelease_tags="deploy-*"\n')
 d=decoded(report('--since','deploy-b','--json'))
 assert d['since']=='deploy-b' and d['git']['releases']==1,d
 assert d['lead_time']==dict(value=dict(median=200,p90=200),n=1,missing=0,reason=None),d
elif case=='since-missing':
 tags(('deploy-a','deploy-b'));config('[report]\nrelease_tags="deploy-*"\n')
 p=report('--json','--since','deploy-absent')
 assert p.returncode==2 and p.stdout==b'' and p.stderr.strip()==b'report: --since deploy-absent is not a release tag on refs/heads/main',(p.returncode,p.stdout,p.stderr)
elif case=='since-offbranch':
 tags(('deploy-a','deploy-b'));config('[report]\nrelease_tags="deploy-*"\n')
 git('checkout','-qb','side99',r1);save(T+20);git('tag','deploy-side');git('checkout','-q','main')
 p=report('--json','--since','deploy-side')
 assert p.returncode==2 and p.stdout==b'' and p.stderr.strip()==b'report: --since deploy-side is not a release tag on refs/heads/main',(p.returncode,p.stdout,p.stderr)
elif case=='since-mismatch':
 tags(('deploy-a','deploy-b'));config('[report]\nrelease_tags="deploy-*"\n')
 calls.unlink(missing_ok=True);p=report('--json','--since','v1.0.0')
 assert p.returncode==2 and not p.stdout and b'invalid arguments:' in p.stderr and b'usage:' in p.stderr,(p.returncode,p.stderr)
 assert not calls.exists(),'grammar refusal read git'
elif case=='fix-deploy':
 lock('B','fix','v1.0.0');r2=save(T+86400);tags(('deploy-a', 'deploy-b'));config('[report]\nrelease_tags="deploy-*"\n')
 git('tag','v1.0.0',r1);d=decoded(report('--json')) # Fix linkage must use the active selection.
 assert d['change_failure_rate']['missing']==1 and d['change_failure_rate']['value']==None and d['change_failure_rate']['n']==2,d
 assert d['rework_rate']['value']==0.5 and d['rework_rate']['missing']==0,d
elif case=='fix-vstar':
 lock('B','fix','v1.0.0');r2=save(T+86400);tags(('v1.0.0', 'v2'));config('[report]\nrelease_tags="v*"\n')
 d=decoded(report('--json'))
 assert d['change_failure_rate']['missing']==0 and d['change_failure_rate']['value']==0.5 and d['change_failure_rate']['n']==2,d
 assert d['rework_rate']['value']==0.5 and d['rework_rate']['missing']==0,d
elif case=='git-failure':
 tags(('deploy-a','deploy-b'));config('[report]\nrelease_tags="deploy-*"\n');failgit.touch()
 d=decoded(report('--json'))
 assert d['git']['release_tags']=='deploy-*' and d['git']['reason'],d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
elif case=='nested-working':
 tags(('deploy-a','deploy-b'));config('[report]\nrelease_tags="deploy-*"\n')
 nested=root/'packages/deep';nested.mkdir(parents=True);(nested/'.shipcraft.toml').write_text('[report]\nrelease_tags="wrong-*"\n')
 d=decoded(report('--json',cwd=nested));assert d['git']['releases']==2 and d['git']['release_tags']=='deploy-*',d
 assert git('show','HEAD:.shipcraft.toml')==base.strip(),'fixture must leave root selection uncommitted'
elif case=='reader-variants':
 tags(('deploy-a','deploy-b'))
 for body in ('report = { release_tags = "deploy-*" } # inline\n', "report.release_tags = 'deploy-*' # dotted literal\r\n", '["report"]\r\n"release_tags" = "depl\\u006fy-*" # escape\r\n'):
  config(body);d=decoded(report('--json'));assert d['git']['release_tags']=='deploy-*' and d['git']['releases']==2,(body,d)
 git('tag','!release+().{}~',r2);config('[report]\nrelease_tags="!release+().{}~"\n')
 d=decoded(report('--json'));assert d['git']['releases']==1 and d['git']['release_tags']=='!release+().{}~',d
elif case=='coverage-default':
 tags(('v1.0.0','v2.0.0'))
 d=decoded(report('--json'));assert d['git']['release_tags'] is None,d
 assert list(d['git'])==['default_branch','reason','release_tags','releases'],d
 text=report().stdout.decode();coverage=next(s for s in text.splitlines() if s.startswith('git:'));assert coverage.endswith('; release tags: vX.Y.Z') and not coverage.endswith('.; release tags: vX.Y.Z'),text
elif case=='fallback-malformed':
 tags(('v1.0.0','v2.0.0'))
 config('broken [')
 d=decoded(report('--json'));assert d['git']['releases']==2 and d['git']['reason'] is None and d['lead_time']['n']==2,d
 p=report('--since','deploy-a','--json');assert p.returncode==2 and b'usage:' in p.stderr,(p.returncode,p.stderr)
 (root/'.shipcraft.toml').unlink()
 d=decoded(report('--json'));assert d['git']['releases']==2 and d['git']['reason'] is None,d
elif case=='fallback-utf8':
 tags(('v1.0.0','v2.0.0'))
 write(Path('.shipcraft.toml'),b'\xff')
 d=decoded(report('--json'));assert d['git']['releases']==2 and d['git']['reason'] is None and d['lead_time']['n']==2,d
 p=report('--since','deploy-a','--json');assert p.returncode==2 and b'usage:' in p.stderr,(p.returncode,p.stderr)
elif case=='fallback-directory':
 tags(('v1.0.0','v2.0.0'))
 (root/'.shipcraft.toml').unlink();(root/'.shipcraft.toml').mkdir()
 d=decoded(report('--json'));assert d['git']['releases']==2 and d['git']['reason'] is None and d['lead_time']['n']==2,d
 p=report('--since','deploy-a','--json');assert p.returncode==2 and b'usage:' in p.stderr,(p.returncode,p.stderr)
elif case=='fallback-empty':
 tags(('v1.0.0','v2.0.0'))
 config('[report]\n')
 d=decoded(report('--json'));assert d['git']['releases']==2 and d['git']['reason'] is None and d['lead_time']['n']==2,d
 p=report('--since','deploy-a','--json');assert p.returncode==2 and b'usage:' in p.stderr,(p.returncode,p.stderr)
elif case=='fallback-unrelated':
 tags(('v1.0.0','v2.0.0'))
 write(Path('.shipcraft.toml'),'shipcraft_min="99999.0"\nexecution=7\nsuite=false\n')
 d=decoded(report('--json'));assert d['git']['releases']==2 and d['git']['reason'] is None and d['lead_time']['n']==2,d
 p=report('--since','deploy-a','--json');assert p.returncode==2 and b'usage:' in p.stderr,(p.returncode,p.stderr)
elif case=='invalid-empty':
 tags(('v1.0.0','v2.0.0'));config('[report]\nrelease_tags=""\n')
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 text=report();assert text.returncode==0 and text.stderr==b'',(text.returncode,text.stderr)
 coverage=next(s for s in text.stdout.decode().splitlines() if s.startswith('git:'))
 assert '[report] in .shipcraft.toml is invalid: release_tags is empty' in coverage and coverage.endswith('; release tags: vX.Y.Z') and not coverage.endswith('.; release tags: vX.Y.Z'),coverage
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags is empty',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'release_tags' in '\n'.join(lines),lines
elif case=='invalid-stars':
 tags(('v1.0.0','v2.0.0'));config('[report]\nrelease_tags="***"\n')
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags is only *',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'release_tags' in '\n'.join(lines),lines
elif case=='invalid-question':
 tags(('v1.0.0','v2.0.0'));config('[report]\nrelease_tags="deploy-?"\n')
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags has ?, [, ] or \\',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'release_tags' in '\n'.join(lines),lines
elif case=='invalid-bracket':
 tags(('v1.0.0','v2.0.0'));config('[report]\nrelease_tags="deploy-[ab]"\n')
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags has ?, [, ] or \\',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'release_tags' in '\n'.join(lines),lines
elif case=='invalid-closing':
 tags(('v1.0.0','v2.0.0'));config('[report]\nrelease_tags="deploy-]"\n')
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags has ?, [, ] or \\',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'release_tags' in '\n'.join(lines),lines
elif case=='invalid-backslash':
 tags(('v1.0.0','v2.0.0'));config("[report]\nrelease_tags='deploy-\\x'\n")
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags has ?, [, ] or \\',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'release_tags' in '\n'.join(lines),lines
elif case=='invalid-space':
 tags(('v1.0.0','v2.0.0'));config('[report]\nrelease_tags="deploy- ?"\n')
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags has a byte outside 0x21-0x7E',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'release_tags' in '\n'.join(lines),lines
elif case=='invalid-unicode':
 tags(('v1.0.0','v2.0.0'));config('[report]\nrelease_tags="déploy-*"\n')
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags has a byte outside 0x21-0x7E',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'release_tags' in '\n'.join(lines),lines
elif case=='invalid-control':
 tags(('v1.0.0','v2.0.0'));config('[report]\nrelease_tags="deploy-\\u007f"\n')
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags has a byte outside 0x21-0x7E',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'release_tags' in '\n'.join(lines),lines
elif case=='invalid-number':
 tags(('v1.0.0','v2.0.0'));config('[report]\nrelease_tags=12\n')
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags is not a string',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'release_tags' in '\n'.join(lines),lines
elif case=='invalid-array':
 tags(('v1.0.0','v2.0.0'));config('[report]\nrelease_tags=["deploy-*"]\n')
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags is not a string',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'release_tags' in '\n'.join(lines),lines
elif case=='invalid-unknown':
 tags(('v1.0.0','v2.0.0'));config('[report]\nrelease_tag="deploy-*"\n')
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: unknown key release_tag',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'release_tag' in '\n'.join(lines),lines
elif case=='invalid-nottable':
 tags(('v1.0.0','v2.0.0'));config('report="deploy-*"\n')
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: [report] is not a table',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'report' in '\n'.join(lines),lines
elif case=='invalid-precedence':
 tags(('v1.0.0','v2.0.0'));config('[report]\nz_typo=1\na_typo=2\nrelease_tags="? "\n')
 # Observe both boundaries before asserting either, so an early report failure
 # cannot hide whether the same input reached hook validation.
 p=report('--json');git('add','.shipcraft.toml');h=run([binary,'check'])
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 d=decoded(p)
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: unknown key a_typo',d
 assert d['git']['release_tags'] is None,d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
 assert h.returncode!=0 and rows[-1]['layer']=='hook' and rows[-1]['code']=='config-invalid',(h.returncode,rows)
 lines=(h.stdout+h.stderr).decode().strip().splitlines()[-3:]
 assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),lines
 assert 'a_typo' in '\n'.join(lines),lines
elif case=='invalid-since':
 tags(('v1.0.0','v2.0.0'));config('[report]\nrelease_tags=""\n');failgit.touch()
 d=decoded(report('--json','--since','anything/not-a-version'))
 assert d['since']=='anything/not-a-version' and d['git']['release_tags'] is None,d
 assert d['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags is empty',d
 for key in ('deploys','lead_time','rework_rate','time_to_recover','change_failure_rate'):assert d[key]['value'] is None and d[key]['reason']==d['git']['reason'],d
elif case=='hook-source':
 config('[report]\nrelease_tags=""\n');git('add','.shipcraft.toml');config('[report]\nrelease_tags="deploy-*"\n')
 p=run([binary,'check']);assert p.returncode!=0 and b'release_tags' in p.stdout+p.stderr,(p.returncode,p.stdout,p.stderr)
 config('[report]\nrelease_tags="deploy-*"\n');git('add','.shipcraft.toml');config('[report]\nrelease_tags=""\n')
 p=run([binary,'check']);assert p.returncode==0,(p.stdout,p.stderr)
elif case=='ci-source':
 config('[report]\nrelease_tags=""\n');save(T+86401);config('[report]\nrelease_tags="deploy-*"\n')
 p=run([binary,'ci','--base',r2]);assert p.returncode!=0 and b'release_tags' in p.stdout+p.stderr,(p.returncode,p.stdout,p.stderr)
 rows=[json.loads(s) for s in log.read_text().splitlines() if s and s[0]=='{' and not s.startswith('{broken99')]
 assert rows[-1]['layer']=='ci' and rows[-1]['code']=='config-invalid',rows
elif case=='status-invalid':
 config('[report]\nrelease_tags="***"\n')
 p=run([binary,'status']);assert p.returncode!=0 and b'release_tags' in p.stdout+p.stderr,(p.returncode,p.stdout,p.stderr)
else:raise AssertionError(('unrouted case',case))
PY99
  pass
}
