# Item 79: real Git plumbing and case-owned, file-backed GitHub CLI answers.
item79_langs() { echo core; }
item79_cases() {
  local c reader
  for c in merged status-later zero-wait ci-after-merge observed-null-merge observed-no-pr pr-array-only no-default local-merge-end unobserved unobserved-missing-check unobserved-config unobserved-gh-failure unobserved-no-close unobserved-no-red text text-unobserved text-missing pages pages-late-failure suite-status mixed-producers duplicate-matches exact-name component-order selection no-pr several-prs duplicate-prs merge-pr-source cache-success cache-failure cache-unreadable cache-head failed-continue missing-gh no-start signal fail-child timeout-sleep timeout-pipe ci-off local-ci config-symlink config-nested environment readonly no-github no-github-text empty since since-refused flags-first flags-last repeat-github repeat-json repeat-since unknown help noargs shorthelp longhelp summary-sorted; do echo "v1-79.$c"; done
  for c in zero negative bool float string null absent; do echo "v1-79.log-pr-$c"; done
  for c in number absent state mergedAt head mergeCommit oid null-merge uppercase-head short-head uppercase-oid short-oid not-ancestor unknown-commit open draft malformed utf8 number-bool number-float merge-null-time merged-null-oid duplicate-keys; do echo "v1-79.pr-$c"; done
  for c in missing directory utf8 malformed legacy minimum suite root glob role execution; do echo "v1-79.config-$c"; done
  for reader in status check; do
    for c in missing nongreen pending null-time invalid-time unrelated-shape unrelated-time empty-pages object-page count-missing count-bool count-float count-negative count-mismatch page-count entry-array entry-fields malformed utf8 nonzero duplicate-keys zero-year; do echo "v1-79.$reader-$c"; done
  done
  for c in leap century minimum maximum month day hour minute second fraction offset lower short unicode trailing; do echo "v1-79.time-$c"; done
}
item79_case() {
  EXPECT="item 79: ${CASE#v1-79.}"
  v1_start codex
  must_accept 'GitHub report contract' cmd "$PY" - "${CASE#v1-79.}" "$(command -v shipcraft)" "$CW" <<'PY79'
import copy,datetime,hashlib,json,os,re,shutil,signal,stat,subprocess,sys,time
from pathlib import Path
from urllib.parse import quote
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/'repo79 space';root.mkdir();realgit=shutil.which('git');baseenv=os.environ.copy()
localvars=subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()
for k in localvars+['GIT_CEILING_DIRECTORIES']:baseenv.pop(k,None)
def run(a,env=None,cwd=None,data=None):
 return subprocess.run(list(map(str,a)),cwd=cwd or root,env=env or baseenv,input=data,capture_output=True,timeout=20)
def git(*a,**kw):
 p=run([realgit,*a],**kw);assert p.returncode==0,('fixture git',a,p.stderr);return p.stdout.decode().strip()
def write(p,s):
 p=root/p;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(s if isinstance(s,bytes) else s.encode())
def lock(id):
 d=dict(format=4,state='closed',files={'tests/test_value.py':'sha256:'+hashlib.sha256(b'def test_value(): assert False\n').hexdigest()},cases=['tests/test_value.py::test_value'],failing_at_red=['tests/test_value.py::test_value'],kind='feature',reported_at=None,fixes_release=None,seal='')
 d['seal']=hashlib.sha256(json.dumps(d,separators=(',',':')).encode()).hexdigest();write(Path('.shipcraft/locks')/(id+'.json'),json.dumps(d)+'\n')
def save(parent=None):
 git('add','-A');tree=git('write-tree');e=dict(baseenv,GIT_AUTHOR_DATE='1700000000 +0000',GIT_COMMITTER_DATE='1700000000 +0000')
 sha=git('commit-tree',tree,*(['-p',parent] if parent else []),env=e,data=b'fixture79\n');git('update-ref','HEAD',sha);return sha
def snapshot():
 result={}
 for p in root.rglob('*'):
  s=p.lstat();result[str(p.relative_to(root))]=(stat.S_IFMT(s.st_mode),stat.S_IMODE(s.st_mode),os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None)
 return result
T=1700000000
utc=lambda t:datetime.datetime.fromtimestamp(t,datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
def row(id,layer,at,**kw):
 d=dict(layer=layer,at=at,lock=id,result='passed',secs=1,branch='feature/79',commit='a'*40,code='',reason='')
 if layer in ('merge','pr','ci'):d.update(locks=[id],base='main',default_branch='main')
 d.update(kw);return d
def cycle(id='A',observed=True,pr=97,close=True):
 a=[row(id,'red',T)]
 if close:a.append(row(id,'close',T+100))
 a.append(row(id,'pr',T+200,pr=pr,result='error')) # Any PR result attributes the lock.
 if observed:a.append(row(id,'merge',T+600,pr=pr))
 return a
unobserved=case.startswith('unobserved') or case=='text-unobserved' or case in ('pr-null-merge','pr-uppercase-oid','pr-short-oid','pr-not-ancestor','pr-unknown-commit')
git('init','-q','-b','main');git('config','gc.auto','0');git('config','maintenance.auto','false')
write(Path('tests/test_value.py'),'def test_value(): assert False\n');lock('A')
checks=['zeta suite/β']
config='shipcraft_min = "2.18"\nlang = "python"\nrunner = "pytest"\ntest_command = "touch SHOULD-NOT-RUN79; echo {junit}"\ncheck = "touch SHOULD-NOT-CHECK79"\n[build]\ncommand = "touch SHOULD-NOT-BUILD79"\n[execution]\nci = "github"\nreview = "off"\nsuite_checks = '+json.dumps(checks,ensure_ascii=False)+'\n'
write(Path('.shipcraft.toml'),config);tip=save();git('tag','v1.0.0')
rs=cycle(observed=not unobserved,close=case!='unobserved-no-close')
if case=='unobserved-no-red':rs=[r for r in rs if r['layer']!='red']
selected=['A'];reasons={};mergefill=[];waitfill=['A'];expected_wait=150;expected_merge=T+650
if unobserved:mergefill=['A'];expected_wait=200
P=['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']
S=['api','--paginate','--slurp',f'repos/{{owner}}/{{repo}}/commits/{tip}/status?per_page=100']
def C(name=checks[0]):return ['api','--paginate','--slurp',f'repos/{{owner}}/{{repo}}/commits/{tip}/check-runs?check_name={quote(name,safe="")}&filter=latest&per_page=100']
pr=dict(number=97,state='MERGED',mergedAt=utc(T+650),headRefOid=tip,mergeCommit={'oid':tip})
status=[dict(total_count=2,statuses=[dict(context='shipcraft/ci',state='success',created_at=utc(T+400)),dict(context='unrelated',state='pending',created_at='ignored')])]
check=[dict(total_count=1,check_runs=[dict(name=checks[0],status='completed',conclusion='success',completed_at=utc(T+450))])]
expected_calls=[P,S,C()];faults={};raw={}
def missing(reason,calls=None):
 reasons['A']=reason;waitfill.clear()
 if calls is not None:expected_calls[:]=calls
if case in ('status-later','local-merge-end'):status[0]['statuses'][0]['created_at']=utc(T+500);expected_wait=100
if case=='ci-after-merge':check[0]['check_runs'][0]['completed_at']=utc(T+601);missing('ci finished after merge')
if case=='observed-null-merge':pr['mergeCommit']=None
if case=='observed-no-pr':
 rs=[dict(r,pr=None) if r['layer']=='merge' else r for r in rs];missing('no pr in the run log',[])
if case=='pr-array-only':
 rs=cycle(observed=False);rs[2]['lock']='';mergefill[:]=['A'];expected_wait=200
if case=='no-default':git('branch','-m','topic79')
if case=='zero-wait':check[0]['check_runs'][0]['completed_at']=utc(T+600);expected_wait=0
if case=='text-missing':missing('no pr in the run log',[]);rs=[dict(r,pr=None) if r['layer']=='merge' else r for r in rs]
if case in ('unobserved-missing-check','exact-name'):
 check[0]['check_runs'][0]['name']+=' ';missing(checks[0]+' missing at head')
if case=='unobserved-gh-failure':faults['check']='nonzero';missing('gh failed')
if case=='unobserved-config':write(Path('.shipcraft.toml'),'broken [');missing('config unreadable',[P])
if case in ('pages','pages-late-failure'):
 # Per-page total_count is the overall total, as returned by --paginate --slurp.
 status=[dict(total_count=3,statuses=[dict(context='unrelated',state='pending',created_at='ignored')]),dict(total_count=3,statuses=[dict(context='shipcraft/ci',state='success',created_at=utc(T+300)),dict(context='shipcraft/ci',state='success',created_at=utc(T+420))])]
 check=[dict(total_count=2,check_runs=[dict(name=checks[0],status='completed',conclusion='success',completed_at=utc(T+440))]),dict(total_count=2,check_runs=[dict(name=checks[0],status='completed',conclusion='success',completed_at=utc(T+480))])];expected_wait=120
 if case=='pages-late-failure':check[1]['check_runs'][0]['conclusion']='failure';missing(checks[0]+' not green at head now')
if case=='suite-status':
 status[0]['statuses'].append(dict(context=checks[0],state='success',created_at=utc(T+470)));status[0]['total_count']=3;check=[dict(total_count=0,check_runs=[])];expected_wait=130
if case=='mixed-producers':
 status[0]['statuses'].append(dict(context=checks[0],state='failure',created_at='not-a-time'));status[0]['total_count']=3;missing(checks[0]+' not green at head now')
if case=='duplicate-matches':
 check[0]['check_runs']*=2;check[0]['total_count']=2 # Both entries count, even identical entries.
if case=='component-order':
 checks.append('alpha later');write(Path('.shipcraft.toml'),config.replace(json.dumps(['zeta suite/β'],ensure_ascii=False),json.dumps(checks,ensure_ascii=False)))
 check[0]['check_runs'][0]['status']='in_progress';check[0]['check_runs'][0]['conclusion']=None;missing(checks[0]+' not green at head now')
if case=='selection':
 lock('B');lock('local');lock('open');tip2=save(tip);git('tag','-f','v1.0.0');pr['mergeCommit']={'oid':tip2}
 rs+=cycle('local')+[row('local','ci',T+590)]+[row('open','red',T),row('B','red',T)]
 selected.append('B');reasons['B']='no pr in the run log' # B at branch tip is unobserved, open is removed from tip below.
 (root/'.shipcraft/locks/open.json').unlink();save(tip2)
if case in ('no-pr','several-prs','duplicate-prs') or case.startswith('log-pr-'):
 rs=cycle(observed=False);mergefill[:]=['A'];expected_wait=200
 if case=='no-pr':rs=[r for r in rs if r['layer']!='pr'];mergefill.clear();missing('no pr in the run log',[])
 elif case=='several-prs':rs.append(row('','pr',T+201,locks=['A'],pr=98));mergefill.clear();missing('several prs in the run log',[])
 elif case=='duplicate-prs':
  rs.append(row('','pr',T+201,locks=['A'],pr=97,result='refused'));rs.append(row('A','review',T+202,pr=98))
 else:
  value={'zero':0,'negative':-1,'bool':True,'float':97.0,'string':'97','null':None,'absent':None}[case[7:]]
  rs[2]['pr']=value
  if case.endswith('absent'):rs[2].pop('pr')
  mergefill.clear();missing('no pr in the run log',[])
if case=='merge-pr-source':
 rs.insert(0,row('A','pr',T-1,pr=98));rs.append(row('A','merge',T+700,pr=99)) # Earliest passed merge determines merge_at and PR.
if case.startswith('cache-') or case=='failed-continue':
 rs+=cycle('B',pr=98 if case in ('cache-head','failed-continue') else 97);selected.append('B');waitfill.append('B')
 if case in ('cache-head','failed-continue'):expected_calls.append([*P[:2],'98',*P[3:]])
 if case in ('cache-failure','cache-unreadable'):
  faults['pr']='nonzero' if case=='cache-failure' else 'malformed';missing('gh failed' if case=='cache-failure' else 'unreadable answer from gh',[P]);reasons['B']=reasons['A'];waitfill.clear()
 if case=='failed-continue':faults['pr']='nonzero';missing('gh failed',[P,[*P[:2],'98',*P[3:]],S,C()]);waitfill[:]=['B']
if case in ('missing-gh','no-start','signal','fail-child','timeout-sleep','timeout-pipe'):
 fault={'missing-gh':'absent','no-start':'no-start','signal':'signal','fail-child':'fail-child','timeout-sleep':'sleep','timeout-pipe':'pipe'}[case];faults['pr']=fault
 missing('gh timed out' if case.startswith('timeout') else 'gh failed',[] if case in ('missing-gh','no-start') else [P])
 if case.startswith('timeout'):
  faults.pop('pr');faults['status' if case=='timeout-sleep' else 'check']=fault;expected_calls[:]=[P,S] if case=='timeout-sleep' else [P,S,C()]
  # B is cached on this PR; C would have no PR. Both must be timed out after A.
  rs+=cycle('B')+cycle('C',pr=None);selected+=['B','C'];reasons.update(B='gh timed out',C='gh timed out')
if case in ('ci-off','local-ci'):
 write(Path('.shipcraft.toml'),config.replace('ci = "github"','ci = "off"' if case=='ci-off' else 'ci = "local"').replace(json.dumps(checks,ensure_ascii=False),'[]'))
 expected_calls[:]=[P] if case=='ci-off' else [P,S]
 if case=='ci-off':missing('ci off')
 else:expected_wait=200
if case=='config-symlink':
 (root/'.shipcraft.toml').rename(root/'actual79.toml');(root/'.shipcraft.toml').symlink_to('actual79.toml')
if case.startswith('config-') and case not in ('config-symlink','config-nested'):
 mode=case[7:];bad={'utf8':b'\xff','malformed':'x = [',
  'legacy':'verifica = "true"\n'+config,
  'minimum':config.replace('shipcraft_min = "2.18"','shipcraft_min = "99999.0"'),
  'suite':config+'[[suite]]\nroot="."\n',
  'root':config+'[[suite]]\nroot="../bad"\ncommand="echo {junit}"\nglobs=["tests/**"]\n',
  'glob':'test_globs=["../bad"]\n'+config,
  'role':config.replace('shipcraft_min = "2.18"','shipcraft_min = "2.20"')+'[roles]\nred="unknown"\n',
  'execution':config.replace('ci = "github"','ci = 7')}
 if mode=='missing':(root/'.shipcraft.toml').unlink()
 elif mode=='directory':(root/'.shipcraft.toml').unlink();(root/'.shipcraft.toml').mkdir()
 else:write(Path('.shipcraft.toml'),bad[mode])
 missing('config unreadable',[P])
if case.startswith('pr-') and case!='pr-array-only':
 mode=case[3:];missing('unreadable answer from gh',[P]);mergefill.clear()
 if mode in ('number','absent','state','mergedAt','head','mergeCommit','oid'):
  if mode=='absent':pr.pop('number')
  elif mode=='number':pr['number']=98
  elif mode=='state':pr['state']=None
  elif mode=='mergedAt':pr['mergedAt']=9
  elif mode=='head':pr['headRefOid']=False
  elif mode=='mergeCommit':pr['mergeCommit']=[]
  else:pr['mergeCommit']={'oid':1}
 elif mode=='null-merge':pr['mergeCommit']=None
 elif mode in ('uppercase-head','short-head'):pr['headRefOid']=tip.upper() if mode=='uppercase-head' else tip[:39]
 elif mode in ('uppercase-oid','short-oid'):pr['mergeCommit']={'oid':tip.upper() if mode=='uppercase-oid' else tip[:39]}
 elif mode in ('not-ancestor','unknown-commit'):
  if mode=='unknown-commit':oid='f'*40
  else:oid=git('commit-tree',git('rev-parse','HEAD^{tree}'),data=b'unrelated79\n')
  pr['mergeCommit']={'oid':oid};missing('pr not merged into refs/heads/main')
 elif mode in ('open','draft'):pr['state']='OPEN' if mode=='open' else 'CLOSED';pr['mergedAt']=None;pr['headRefOid']='bad';missing('pr not merged')
 elif mode in ('malformed','utf8'):faults['pr']=mode
 elif mode in ('number-bool','number-float'):pr['number']=True if mode=='number-bool' else 97.0
 elif mode=='merge-null-time':pr['mergedAt']=None
 elif mode=='merged-null-oid':pr['mergeCommit']={'oid':None}
 elif mode=='duplicate-keys':
  reasons.pop('A');waitfill.append('A');expected_calls[:]=[P,S,C()];raw['pr']=json.dumps(pr).replace('"number":', '"number": 98, "number":',1).encode()
if case.startswith(('status-','check-')) and case!='status-later':
 reader,mode=case.split('-',1);pages=status if reader=='status' else check;field='statuses' if reader=='status' else 'check_runs';entry=pages[0][field][0];call=[P,S] if reader=='status' else [P,S,C()]
 name='shipcraft/ci' if reader=='status' else checks[0]
 missing('unreadable answer from gh',call)
 if mode=='missing':pages[0][field]=[];pages[0]['total_count']=0;missing(name+' missing at head')
 elif mode in ('nongreen','pending'):
  if reader=='status':entry['state']='failure' if mode=='nongreen' else 'pending'
  else:entry.update(status='completed' if mode=='nongreen' else 'in_progress',conclusion='failure' if mode=='nongreen' else None)
  entry['created_at' if reader=='status' else 'completed_at']='bad';missing(name+' not green at head now')
 elif mode=='zero-year':entry['created_at' if reader=='status' else 'completed_at']='0000-01-01T00:00:00Z'
 elif mode in ('null-time','invalid-time'):entry['created_at' if reader=='status' else 'completed_at']=None if mode=='null-time' else '2023-02-29T00:00:00Z'
 elif mode in ('unrelated-shape','unrelated-time'):
  other=dict(context='other',state='pending',created_at='bad') if reader=='status' else dict(name='other',status='queued',conclusion=None,completed_at='bad')
  if mode=='unrelated-shape':other['state' if reader=='status' else 'conclusion']=4
  else:reasons.pop('A');waitfill.append('A');expected_calls[:]=[P,S,C()]
  pages[0][field].append(other);pages[0]['total_count']+=1
 elif mode=='empty-pages':pages.clear()
 elif mode=='object-page':pages[:]=[[]]
 elif mode=='count-missing':pages[0].pop('total_count')
 elif mode in ('count-bool','count-float','count-negative','count-mismatch'):pages[0]['total_count']={'count-bool':True,'count-float':float(pages[0]['total_count']),'count-negative':-1,'count-mismatch':99}[mode]
 elif mode=='page-count':pages.append(dict(total_count=99,**{field:[]}))
 elif mode=='entry-array':pages[0][field][0]=[]
 elif mode=='entry-fields':entry.pop('context' if reader=='status' else 'conclusion')
 elif mode in ('malformed','utf8','nonzero'):
  faults[reader]=mode
  if mode=='nonzero':missing('gh failed')
 elif mode=='duplicate-keys':
  reasons.pop('A');waitfill.append('A');expected_calls[:]=[P,S,C()];raw[reader]=json.dumps(pages).replace('"total_count":','"total_count": -1, "total_count":',1).encode()
if case.startswith('time-'):
 mode=case[5:];valid={'leap':'2000-02-29T23:59:59Z','minimum':'0001-01-01T00:00:00Z','maximum':'9999-12-31T23:59:59Z'}
 invalid={'century':'1900-02-29T00:00:00Z','month':'2023-13-01T00:00:00Z','day':'2023-04-31T00:00:00Z','hour':'2023-01-01T24:00:00Z','minute':'2023-01-01T00:60:00Z','second':'2023-01-01T00:00:60Z','fraction':'2023-01-01T00:00:00.0Z','offset':'2023-01-01T00:00:00+00:00','lower':'2023-01-01t00:00:00z','short':'023-01-01T00:00:00Z','unicode':'２０２３-01-01T00:00:00Z','trailing':'2023-01-01T00:00:00Z\n'}
 if mode in valid:
  # mergedAt must validate even on observed merges, while their local merge end stays fixed.
  pr['mergedAt']=valid[mode]
 else:pr['mergedAt']=invalid[mode];missing('unreadable answer from gh',[P])
if case=='summary-sorted':
 rs=cycle(pr=None)+cycle('B',pr=98)+cycle('C',pr=99);selected+=['B','C'];waitfill.clear();reasons=dict(A='no pr in the run log',B='pr not merged',C='gh failed');faults['pr99']='nonzero';expected_calls[:]=[[*P[:2],'98',*P[3:]],[*P[:2],'99',*P[3:]]]
if case=='empty':rs=[];selected.clear();waitfill.clear();expected_calls.clear();(root/'.shipcraft/locks/A.json').unlink();save(tip)
log=root/'.git/shipcraft/runs.jsonl';log.parent.mkdir(parents=True,exist_ok=True);log.write_text(''.join(json.dumps(r)+'\n' for r in rs)+('{broken79\n' if case=='summary-sorted' else ''))
# File-backed fake gh. No delegation and no network implementation exists here.
tools=cw/'tools79';tools.mkdir();answers=cw/'answers79';answers.mkdir();calls=cw/'gh-calls79.jsonl';gitcalls=cw/'git-calls79.jsonl';manifest={}
def response(argv,value,fault='',rawbytes=None):
 index=str(len(manifest));path=answers/(index+'.json');path.write_bytes(rawbytes if rawbytes is not None else json.dumps(value,ensure_ascii=False).encode());manifest[json.dumps(argv)]=dict(path=str(path),fault=fault)
response(P,pr,faults.get('pr',''),raw.get('pr'))
response(S,status,faults.get('status',''),raw.get('status'));response(C(),check,faults.get('check',''),raw.get('check'))
for n in (98,99):
 other=dict(pr,number=n)
 if case=='summary-sorted' and n==98:other['state']='OPEN'
 response([*P[:2],str(n),*P[3:]],other,faults.get('pr99','') if n==99 else '')
(answers/'manifest.json').write_text(json.dumps(manifest))
gh=tools/'gh';gh.write_text('#!'+sys.executable+'\n'+'''import json,os,signal,subprocess,sys,time
from pathlib import Path
answers=Path('''+repr(str(answers))+''');calls=Path('''+repr(str(calls))+''')
a=sys.argv[1:]
with calls.open('a') as f:f.write(json.dumps(dict(args=a,cwd=os.getcwd(),stdin=os.read(0,1).hex(),env={k:os.environ.get(k) for k in '''+repr(localvars+['GIT_CEILING_DIRECTORIES','SHIPCRAFT_CASES','SHIPCRAFT_FILES','GH_PROMPT_DISABLED','GH_REPO','GH_HOST','KEEP79'])+'''}))+'\\n')
manifest=json.loads((answers/'manifest.json').read_text());r=manifest.get(json.dumps(a))
if r is None:raise SystemExit(91)
fault=r['fault'];print('PRIVATE-GH-ERROR79',file=sys.stderr,flush=True)
if fault in ('pipe','fail-child'):
 child=subprocess.Popen([sys.executable,'-c',"import pathlib,time; p=pathlib.Path("+repr(str(answers/'heartbeat'))+");\\nwhile True: p.write_text(str(time.time())); time.sleep(.1)"])
 (answers/'child').write_text(str(child.pid))
if fault=='sleep':time.sleep(90)
if fault=='signal':os.kill(os.getpid(),signal.SIGTERM)
if fault=='malformed':sys.stdout.buffer.write(b'{bad');raise SystemExit(0)
if fault=='utf8':sys.stdout.buffer.write(b'\\xff');raise SystemExit(0)
sys.stdout.buffer.write(Path(r['path']).read_bytes());sys.stdout.buffer.flush()
raise SystemExit(1 if fault in ('nonzero','fail-child') else 0)
''');gh.chmod(0o755)
# Transparent Git proxy retains item 76's real Git evidence, records ancestry and rejects network.
proxy=tools/'git';proxy.write_text('#!'+sys.executable+'\n'+'''import json,os,sys
with open('''+repr(str(gitcalls))+''','a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')
if any(a in ('fetch','pull','push','clone') for a in sys.argv[1:]):raise SystemExit(92)
os.execve('''+repr(realgit)+''',['''+repr(realgit)+''',*sys.argv[1:]],dict(os.environ))
''');proxy.chmod(0o755)
for tool in ('codex','claude','gemini','curl','wget','ssh','touch'):
 p=tools/tool;p.write_text('#!'+sys.executable+'\nfrom pathlib import Path\nPath('+repr(str(cw/'forbidden79'))+').touch()\nraise SystemExit(93)\n');p.chmod(0o755)
env=dict(baseenv,PATH=str(tools),GH_PROMPT_DISABLED='0',GH_REPO='fixture-owner/fixture79',GH_HOST='github.example79',KEEP79='preserved79',SHIPCRAFT_CASES='inherited-cases79',SHIPCRAFT_FILES='inherited-files79')
cwd=root
if case in ('config-nested','environment'):
 cwd=root/'packages/deep79';cwd.mkdir(parents=True);write(Path('packages/deep79/.shipcraft.toml'),'invalid nested [')
if case=='environment':
 other=cw/'other79';other.mkdir();run([realgit,'init','-q','-b','main',other]);env.update(GIT_DIR=str(other/'.git'),GIT_WORK_TREE=str(other),GIT_COMMON_DIR=str(other/'.git'),GIT_INDEX_FILE=str(other/'index'),GIT_OBJECT_DIRECTORY=str(other/'.git/objects'),GIT_ALTERNATE_OBJECT_DIRECTORIES=str(other/'.git/objects'),GIT_CEILING_DIRECTORIES=str(root))
if case=='missing-gh':gh.unlink()
if case=='no-start':gh.write_text('#!/nonexistent/interpreter79\n');gh.chmod(0o755)
if case=='readonly':
 for p in root.rglob('*'):
  if p.is_file():p.chmod(0o444)
before=snapshot()
def report(args):
 start=time.time();p=subprocess.Popen([binary,'report',*args],cwd=cwd,env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
 try:out,err=p.communicate(input=b'do-not-forward-parent-stdin79',timeout=70 if case.startswith('timeout') else 12)
 except subprocess.TimeoutExpired:
  os.killpg(p.pid,signal.SIGKILL);p.communicate();raise AssertionError('report exceeded wall-time limit')
 finally:
  # Cleanup also bounds broken implementations without orphaning our heartbeat child.
  child=answers/'child'
  if child.exists():
   heartbeat=answers/'heartbeat';a=heartbeat.read_bytes() if heartbeat.exists() else None;time.sleep(.3);b=heartbeat.read_bytes() if heartbeat.exists() else None
   try:os.kill(int(child.read_text()),signal.SIGKILL)
   except ProcessLookupError:pass
   assert a==b,'gh process group descendant survived report'
 elapsed=time.time()-start
 print('REPORT79',case,args,'rc',p.returncode,'elapsed',round(elapsed,3),repr(out),repr(err),flush=True)
 assert snapshot()==before,'report wrote files, Git state or run log'
 assert not (cw/'forbidden79').exists(),'report ran suite/build/check/network/agent'
 if gitcalls.exists():assert not any(a in ('fetch','pull','push','clone') for r in map(json.loads,gitcalls.read_text().splitlines()) for a in r),'report attempted Git network'
 return p.returncode,out,err,elapsed
# Baseline is also the byte-for-byte no-GitHub preservation reference.
rc,baseline,stderr,_=report(['--since','v1.0.0','--json'] if case in ('since','flags-first','flags-last') else ['--json']);assert rc==0 and not stderr,(rc,stderr)
assert not calls.exists(),'report without --github called gh'
base=[json.loads(s) for s in baseline.splitlines()];base_locks={r['lock']:r for r in base if r['kind']=='lock'}
if case in ('no-github','no-github-text'):
 if case=='no-github-text':
  rc,out,err,_=report([]);assert rc==0 and not err and b'from github:' not in out and b'github: selected' not in out
 assert not calls.exists() and all('github' not in r for r in base_locks.values());sys.exit()
if case in ('help','noargs','shorthelp','longhelp'):
 argv={'help':['help'],'noargs':[],'shorthelp':['-h'],'longhelp':['--help']}[case]
 p=run([binary,*argv],env=env,cwd=cwd);assert p.returncode==0 and b'shipcraft report [--json] [--since <tag>] [--github]' in p.stdout,(p.returncode,p.stdout,p.stderr);assert not calls.exists();assert snapshot()==before;sys.exit()
args=['--json','--github']
if case in ('since','flags-first'):args=['--github','--since','v1.0.0','--json']
if case=='flags-last':args=['--since','v1.0.0','--json','--github']
if case=='since-refused':args+=['--since','v9.0.0']
invalid={'repeat-github':['--github','--github'],'repeat-json':['--github','--json','--json'],'repeat-since':['--github','--since','v1.0.0','--since','v1.0.0'],'unknown':['--github','--gitlab']}
if case in invalid:
 gitcalls.unlink(missing_ok=True);rc,out,err,_=report(invalid[case]);assert rc==2 and not out and b'invalid arguments:' in err and b'usage:' in err,(rc,out,err);assert not calls.exists() and not gitcalls.exists(),'usage called git/gh';sys.exit()
rc,out,err,elapsed=report(args)
if case=='since-refused':
 assert rc==2 and not out and err.strip()==b'report: --since v9.0.0 is not a release tag on refs/heads/main',(rc,out,err);assert not calls.exists();sys.exit()
assert rc==0,('report --github must exit zero',rc,out,err)
assert not err,('gh/config error text leaked',err)
if case.startswith('timeout'):assert 58<=elapsed<=68,('60 s call limit',elapsed)
if case=='fail-child':assert elapsed<8,('nonzero exit must discard output without waiting for descendant pipe',elapsed)
rows=[json.loads(s) for s in out.splitlines()];locks={r['lock']:r for r in rows if r['kind']=='lock'}
summary=[r for r in rows if r['kind']=='github'];assert len(summary)==1,('one GitHub summary required',rows)
counts={r:list(reasons.values()).count(r) for r in sorted(set(reasons.values()),key=lambda s:s.encode())}
want=dict(kind='github',selected=len(selected),merge_filled=len(mergefill),waiting_filled=len(waitfill),missing=counts)
assert summary[0]==want,('GitHub summary',want,summary[0])
assert list(summary[0]['missing'])==list(counts),('missing keys byte-sorted',summary[0])
kinds=[r['kind'] for r in rows];assert kinds==sorted(kinds,key=['meta','lock','day','dora','github','gap'].index),kinds
assert set(locks)==set(base_locks),('GitHub changed lock row discovery',locks,base_locks)
for id,r in locks.items():
 old=copy.deepcopy(base_locks[id]);expected=[]
 if id in mergefill:
  for field,value in [('merge_at',expected_merge),('close_to_merge',None if old['close_at'] is None else expected_merge-old['close_at']),('red_to_merge',None if old['red_at'] is None else expected_merge-old['red_at'])]:
   old[field]=value
   if value is not None:expected.append(field)
 if id in waitfill:old['waiting']=expected_wait;expected.append('waiting')
 old['github']=expected
 assert r==old,('filled fields only; preserve state, unobserved, local stats',id,old,r)
# DORA, meta, gaps and every non-waiting daily field stay identical.
def comparable(rs):
 result=[]
 for r in rs:
  if r['kind'] in ('github','lock'):continue
  r=copy.deepcopy(r)
  if r['kind']=='day':r.pop('waiting_median')
  result.append(r)
 return result
assert comparable(rows)==comparable(base),('GitHub changed DORA/meta/day/gaps',rows,base)
for day in [r for r in rows if r['kind']=='day']:
 samples=[r['waiting'] for r in locks.values() if r['state']=='merged' and r['merge_at'] is not None and utc(r['merge_at'])[:10]==day['day'] and r['waiting'] is not None]
 import statistics
 assert day['waiting_median']==(statistics.median(samples) if samples else None),day
actual=[json.loads(s) for s in calls.read_text().splitlines()] if calls.exists() else []
assert [r['args'] for r in actual]==expected_calls,('argv, order, short-circuit and full-argv cache',expected_calls,actual)
for r in actual:
 assert Path(r['cwd'])==root and r['stdin']=='',('gh root and /dev/null stdin',r)
 e=r['env'];assert all(e[k] is None for k in localvars+['GIT_CEILING_DIRECTORIES','SHIPCRAFT_CASES','SHIPCRAFT_FILES']),('gh environment scrub',r)
 assert (e['GH_PROMPT_DISABLED'],e['GH_REPO'],e['GH_HOST'],e['KEEP79'])==('1','fixture-owner/fixture79','github.example79','preserved79'),r
if case.startswith('unobserved') or case in ('duplicate-prs',) or case.startswith('pr-'):
 ancestors=[a for a in map(json.loads,gitcalls.read_text().splitlines()) if 'merge-base' in a]
 if mergefill:assert any(a[:2]==['-C',str(root)] and a[-4:]==['merge-base','--is-ancestor',tip,tip] for a in ancestors),ancestors
if case in ('text','text-unobserved','text-missing','summary-sorted'):
 calls.unlink(missing_ok=True)
 rc,text,err,_=report(['--github']);assert rc==0 and not err
 text=text.decode();tail='; missing '+(', '.join(k+' '+str(v) for k,v in counts.items()) if counts else 'none')
 line=f'github: selected {len(selected)}, merge filled {len(mergefill)}, waiting filled {len(waitfill)}'+tail
 assert text.splitlines().count(line)==1,text
 assert next(i for i,s in enumerate(text.splitlines()) if re.search(r'\bDORA\b',s))<text.splitlines().index(line),text
 if waitfill:assert any('A' in s and s.endswith('; from github: '+', '.join(locks['A']['github'])) for s in text.splitlines()),text
 else:assert 'from github:' not in text,text
PY79
  pass
}
