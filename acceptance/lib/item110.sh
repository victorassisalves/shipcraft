# Item 110; spec 2c85366. Real local Git, existing offline gh and agent protocols.
item110_langs() { echo core; }
item110_cases() {
  local c
  for c in flag-first flag-middle flag-last title-value body-value duplicate flag-value unknown missing-title missing-body no-review local squash off existing closed missing-ci missing-review suite-failed suite-unreadable view-error fetch-error status-error merge-error changed-config newer-head pin-race permissive log-fails ci-red review-changes review-error main detached body-error create-error summary-error control-local control-off control-gate; do echo "v1-110.$c"; done
}
item110_case() {
  EXPECT="item 110: ${CASE#v1-110.}"
  v1_start codex
  must_accept 'item110 contract' cmd "$PY" - "${CASE#v1-110.}" "$(command -v shipcraft)" "$CB" "$CW" <<'PY110'
import json,os,re,shutil,subprocess,sys,time
from pathlib import Path
case,binary,cb,cw=sys.argv[1:];cb=Path(cb);cw=Path(cw);st=cb/'state';binary=str(Path(binary).resolve())
def run(*args,**kw):
 p=subprocess.run(list(map(str,args)),capture_output=True,text=True,timeout=90,**kw)
 print('$',repr(args),'rc',p.returncode,'\n'+p.stdout+p.stderr,flush=True)
 return p
def git(*args,**kw):
 p=run('git',*args,**kw);assert p.returncode==0,p.stderr
 return p.stdout.strip()
def write(p,s):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
def snapshot(msg):
 git('add','-A');tree=git('write-tree');parent=git('rev-parse','HEAD')
 sha=git('commit-tree',tree,'-p',parent,input=msg+'\n');git('update-ref','HEAD',sha);return sha
def rows():
 p=Path('.git/shipcraft/runs.jsonl');return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def records(p):return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
# Each exact arm supplies its input and oracle; helpers supply no case expectations.
ci='off';review='off';method='merge';args=['--title','Item110','--body',str(cw/'body110'),'--merge'];want=0;phase='merged';fault={};review_mode=None;branch='feature/item110';prn=1;reason='';bad=False
if case=='flag-first':args=['--merge']
elif case=='flag-middle':args=['--title','Middle110','--merge','--body',str(cw/'body110')]
elif case=='flag-last':args=['--body',str(cw/'body110'),'--merge']
elif case=='title-value':args=['--title','--merge','--body',str(cw/'body110')];phase='ready'
elif case=='body-value':args=['--body','--merge'];phase='ready'
elif case=='duplicate':args=['--merge','--title','T','--merge'];want=2;phase='invalid';bad=True
elif case=='flag-value':args=['--merge','yes'];want=2;phase='invalid';bad=True
elif case=='unknown':args=['--merge','--bogus110'];want=2;phase='invalid';bad=True
elif case=='missing-title':args=['--merge','--title'];want=2;phase='invalid';bad=True
elif case=='missing-body':args=['--merge','--body'];want=2;phase='invalid';bad=True
elif case=='no-review':args=['--merge','--no-review','because'];want=2;phase='invalid';bad=True
elif case=='local':ci='local';review='local'
elif case=='squash':method='squash'
elif case=='off':pass
elif case=='existing':prn=7
elif case=='closed':fault={'view':{'state':'CLOSED'}};want=1;phase='gate';reason='open'
elif case=='missing-ci':ci='github';fault={'statuses':[]};want=1;phase='gate';reason='shipcraft/ci'
elif case=='missing-review':review='local';fault={'statuses':[]};want=1;phase='gate';reason='shipcraft/review'
elif case=='suite-failed':ci='github';fault={'suite':'failed'};want=1;phase='gate';reason='failed'
elif case=='suite-unreadable':ci='github';fault={'suite':'unreadable'};want=1;phase='gate';reason='unreadable'
elif case=='view-error':fault={'fail_view':True};want=2;phase='gate';reason='injected110'
elif case=='fetch-error':fault={'view':{'baseRefName':'missing-base110'}};want=2;phase='gate';reason='missing-base110'
elif case=='status-error':ci='github';fault={'status_error':True};want=2;phase='gate';reason='injected110'
elif case=='merge-error':fault={'fail_merge':True};want=2;phase='gate';reason='injected110'
elif case=='changed-config':fault={'change_base':True,'statuses':[]};want=1;phase='gate';reason='shipcraft/review'
elif case=='newer-head':ci='github';fault={'new_head':True}
elif case=='pin-race':fault={'race':True};want=2;phase='gate';reason='Head'
elif case=='permissive':fault={'view':{'number':'wrong','state':None,'headRefOid':3,'headRefName':False,'baseRefName':[]}};want=1;phase='gate';reason='open'
elif case=='log-fails':fault={'block_log':True}
elif case=='ci-red':ci='local';want=1;phase='pr';reason='CI'
elif case=='review-changes':review='local';review_mode='changes';want=1;phase='pr';reason='review'
elif case=='review-error':review='local';review_mode='malformed';want=1;phase='pr';reason='review'
elif case=='main':branch='main';want=1;phase='early';reason='working branch'
elif case=='detached':branch='';want=1;phase='early';reason='detached'
elif case=='body-error':args=['--body',str(cw/'absent110'),'--merge'];want=2;phase='early';reason='absent110'
elif case=='create-error':fault={'fail_create':True};want=2;phase='early';reason='injected110'
elif case=='summary-error':fault={'fail_comment':True};want=2;phase='pr';reason='injected110'
elif case=='control-local':ci='local';review='local';args=args[:-1];phase='ready'
elif case=='control-off':args=args[:-1];phase='ready'
elif case=='control-gate':args=args[:-1];ci='github';fault={'new_head':True}
else:raise AssertionError('unrouted '+case)
p=run(binary,'init');assert p.returncode==0,p.stderr
config=Path('.shipcraft.toml').read_text()
# Replace only execution keys, leaving roles.review intact.
a,b=config.split('[execution]',1);block,sep,tail=b.partition('[roles]')
block=re.sub(r'(?m)^ci\s*=.*$', 'ci = '+json.dumps(ci),block)
block=re.sub(r'(?m)^review\s*=.*$', 'review = '+json.dumps(review),block)
block+='\nmerge = '+json.dumps(method)+'\n'
if fault.get('suite'):block+='suite_checks = ["suite 110/β"]\n'
config=a+'[execution]'+block+sep+tail
write('.shipcraft.toml',config);write(cw/'body110','Body marker110\n');write('--merge','File named flag110\n')
base=snapshot('chore: fixture110 base')
origin=cb/'origin.git';git('init','-q','--bare',origin);git('--git-dir='+str(origin),'symbolic-ref','HEAD','refs/heads/main');write(st/'origin',str(origin))
git('remote','add','origin',str(origin));git('push','-q','origin','main');git('fetch','-q','origin');git('remote','set-head','origin','main')
if branch and branch!='main':git('checkout','-qb',branch)
elif not branch:git('checkout','-q','--detach')
write('product110.py','value = 110\n')
if case=='ci-red':write('tests/test_red110.py','def test_red110():\n    assert False\n')
head=snapshot('feat: item110');write(st/'sha',head)
if review_mode:write(st/'reviewer.json',json.dumps({'mode':review_mode}))
# Prepare real alternate commits without changing the working tree or hook.
if fault.get('new_head') or fault.get('race'):
 newer=git('commit-tree',git('rev-parse','HEAD^{tree}'),'-p',head,input='newer110\n')
 git('push','-q','origin',newer+':refs/heads/future110');fault['newer']=newer
if fault.get('change_base'):
 idx=cw/'index110';env=dict(os.environ,GIT_INDEX_FILE=str(idx));git('read-tree',base,env=env)
 text=config.replace('review = "off"','review = "local"',1)
 blob=git('hash-object','-w','--stdin',input=text)
 git('update-index','--cacheinfo','100644,'+blob+',.shipcraft.toml',env=env)
 changed=git('commit-tree',git('write-tree',env=env),'-p',base,input='policy changed110\n');fault['changed']=changed
 git('push','-q','origin',changed+':refs/heads/policy110')
if prn==7:
 git('push','-q','origin',branch)
 p=run('gh','pr','create','--title','existing110','--body','old110','--head',branch,'--base','main');assert p.returncode==0
 d=json.loads((st/'prs.json').read_text());entry=d.pop('1');entry['number']=7;write(st/'prs.json',json.dumps({'7':entry}))
# A local proxy delegates unchanged calls to the established stub, with explicit
# faults at the merge's five-field view. Its trace includes parent PID and the
# row/stdout snapshots visible BEFORE the gate, proving ordering and same process.
write(st/'fault110.json',json.dumps(fault));write(st/'root110',str(Path.cwd()));write(st/'stdout110',str(cw/'stdout110'))
shutil.move(cb/'gh',cb/'gh110-real')
write(cb/'gh',r'''#!/usr/bin/env python3
import json,os,subprocess,sys,time
from pathlib import Path
cb=Path(__file__).parent;st=cb/'state';args=sys.argv[1:];f=json.loads((st/'fault110.json').read_text());root=Path((st/'root110').read_text())
def put(p,s):p.write_text(s)
def trace(kind):
 with (st/'trace110').open('a') as out:out.write(json.dumps({'argv':args,'pid':os.getppid(),'kind':kind})+'\n')
def fail():print('gh: injected110 failure (HTTP 503)',file=sys.stderr);sys.exit(1)
def real():return subprocess.run([str(cb/'gh110-real'),*args],capture_output=True)
gate=args[:2]==['pr','view'] and '--json' in args and set(args[args.index('--json')+1].split(','))==set(['number','state','headRefOid','headRefName','baseRefName'])
trace('gate' if gate else 'call')
if gate:
 p=root/'.git/shipcraft/runs.jsonl';put(st/'gate-rows110',p.read_text() if p.is_file() else '')
 out=Path((st/'stdout110').read_text());put(st/'gate-stdout110',out.read_text() if out.exists() else '')
 if f.get('change_base'):subprocess.run(['git','--git-dir='+str(cb/'origin.git'),'update-ref','refs/heads/main',f['changed']],check=True)
 if f.get('new_head'):
  d=json.loads((st/'prs.json').read_text());n=next(iter(d));d[n]['headOid']=f['newer'];put(st/'prs.json',json.dumps(d))
  subprocess.run(['git','--git-dir='+str(cb/'origin.git'),'update-ref','refs/heads/'+d[n]['headRefName'],f['newer']],check=True)
  with (st/'statuses.jsonl').open('a') as out:out.write(json.dumps(dict(id=999,sha=f['newer'],context='shipcraft/ci',state='success',description='new head110',t=time.time()))+'\n')
 if f.get('race'):put(st/'merge-head',f['newer'])
 put(st/'gate-seen110','yes')
 if f.get('fail_view'):fail()
 p=real()
 if p.returncode==0 and 'view' in f:
  d=json.loads(p.stdout);d.update(f['view']);print(json.dumps(d));sys.exit(0)
 sys.stdout.buffer.write(p.stdout);sys.stderr.buffer.write(p.stderr);sys.exit(p.returncode)
if args[:2]==['pr','create'] and f.get('fail_create'):fail()
if args[:2]==['pr','comment'] and f.get('fail_comment'):fail()
if (st/'gate-seen110').exists():
 if any('/commits/' in a and a.endswith('/statuses') for a in args):
  if f.get('status_error'):fail()
  if 'statuses' in f:print(json.dumps(f['statuses']));sys.exit(0)
 if any('/check-runs?' in a for a in args) and f.get('suite'):
  if f['suite']=='unreadable':fail()
  sha=(st/'sha').read_text().strip();print(json.dumps({'total_count':1,'check_runs':[{'id':1,'head_sha':sha,'name':'suite 110/β','status':'completed','conclusion':'failure','app':{'id':1},'check_suite':{'id':1}}]}));sys.exit(0)
 if args[:2]==['pr','merge'] and f.get('fail_merge'):fail()
os.execv(str(cb/'gh110-real'),[str(cb/'gh110-real'),*args])
''');(cb/'gh').chmod(0o755)
# Git trace proves invalid arguments do not fetch or push (a no-op fetch still counts).
real_git=shutil.which('git');write(cb/'git','#!/usr/bin/env python3\nimport json,os,sys\nwith open('+repr(str(st/'git110'))+',"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nos.execv('+repr(real_git)+',['+repr(real_git)+',*sys.argv[1:]])\n');(cb/'git').chmod(0o755)
if ci=='github' and not (case=='missing-ci'):
 write(st/'statuses.jsonl',json.dumps(dict(id=1,sha=head,context='shipcraft/ci',state='success',description='seed110',t=time.time()))+'\n')
if fault.get('block_log'):
 log=Path('.git/shipcraft/runs.jsonl');log.unlink(missing_ok=True);log.mkdir(parents=True)
before=rows()
for name in ('trace110','git110','calls.log','writes.log'):(st/name).unlink(missing_ok=True)
with (cw/'stdout110').open('w') as out,(cw/'stderr110').open('w') as err:
 p=subprocess.Popen([binary,'pr',*args],stdout=out,stderr=err);pid=p.pid;rc=p.wait(timeout=90)
if case=='control-gate':
 assert rc==0,'control PR failed'
 with (cw/'stdout110').open('a') as out,(cw/'stderr110').open('a') as err:
  p=subprocess.Popen([binary,'merge',str(prn)],stdout=out,stderr=err);pid=p.pid;rc=p.wait(timeout=90)
stdout=(cw/'stdout110').read_text();stderr=(cw/'stderr110').read_text();print('PR rc',rc,'STDOUT\n'+stdout+'STDERR\n'+stderr,flush=True)
if not bad:assert 'invalid arguments:' not in stderr,('valid PR arguments rejected',case,stderr)
assert rc==want,('wrong exit',case,want,rc,stderr)
trace=records(st/'trace110');gates=[x for x in trace if x['kind']=='gate'];merges=[x for x in trace if x['argv'][:2]==['pr','merge']]
rs=rows();prs=[r for r in rs[len(before):] if r['layer']=='pr'];mrs=[r for r in rs[len(before):] if r['layer']=='merge']
pr_keys=set('at base branch code commit layer lock locks pr product_lines queue_secs result review_after secs warn_lines'.split())
merge_keys=set('at base branch code commit default_branch layer lock locks method pr reason result secs'.split())
assert all(set(r)==pr_keys | ({'reason'} if r['result']=='refused' else set()) for r in prs),prs
assert all(set(r)==merge_keys for r in mrs),mrs
ready=f'shipcraft: PR #{prn} ready: enabled layers passed; merge with `shipcraft merge {prn}`.\n'
advice='shipcraft: clean up what this change created (worktree, temp folders, servers you started).\n'
if bad:
 assert stdout=='' and stderr.startswith('shipcraft: error: invalid arguments: ') and '; usage: ' in stderr,stderr
 usage = 'usage: shipcraft --version | shipcraft init [--lang python|node|go] [--github]\n     | shipcraft init --lang other --command <cmd> --glob <glob>... [--github]\n     | shipcraft red [--redo] [--base <ref>] [--all] [--fix [--reported-at <time>] [--fixes-release <tag>]]\n     | shipcraft check [--commit-msg <file>] | shipcraft close\n     | shipcraft ci --base <ref> [--pr]\n     | shipcraft pr [--title <t>] [--body <file>] [--merge] | shipcraft review [--pr <n>]\n     | shipcraft merge <pr> [--no-review "<reason>"] | shipcraft status | shipcraft report [--json] [--since <tag>] [--github]\n'
 assert stderr[stderr.index('usage: '):]==usage,stderr
 assert not trace and not any('fetch' in a or 'push' in a for a in records(st/'git110')),'argument parsing caused external work'
 assert rs==before,'argument parsing wrote a row'
elif phase in ('merged','gate','ready'):
 assert stdout.count(ready)==1,stdout
 assert prs==[] if fault.get('block_log') else len(prs)==1 and prs[0]['result']=='passed',prs
 if phase=='ready':
  assert stdout.endswith(ready) and not gates and not merges and not mrs,(stdout,trace,rs)
  d=json.loads((st/'prs.json').read_text())[str(prn)];assert d['state']=='OPEN',d
  if case=='title-value':assert d['title']=='--merge',d
  if case=='body-value':assert 'File named flag110' in d['body'],d
  if case=='control-local':
   assert any(r['layer']=='ci' and r['result']=='passed' for r in rs) and any(r['layer']=='review' and r['result']=='passed' for r in rs),rs
   assert len(records(st/'reviewer.calls.jsonl'))==1
  if case=='control-off':
   statuses=records(st/'statuses.jsonl');assert {r['context'] for r in statuses if r['state']=='success' and 'off in .shipcraft.toml' in r['description']}=={'shipcraft/ci','shipcraft/review'},statuses
 else:
  assert len(gates)==1 and gates[0]['pid']==pid,('gate must run in same process',gates,pid)
  visible=(st/'gate-stdout110').read_text();assert visible.endswith(ready),visible
  gate_rows=records(st/'gate-rows110');assert gate_rows==rs[:len(gate_rows)],'merge changed preexisting PR rows'
  assert fault.get('block_log') or gate_rows[-1]==prs[0],gate_rows
  if phase=='merged':
   expected_head=fault.get('newer',head)
   assert len(merges)==1 and merges[0]['pid']==pid,merges
   a=merges[0]['argv'];assert a[:3]==['pr','merge',str(prn)] and '--'+method in a and a[a.index('--match-head-commit')+1]==expected_head,a
   assert '--no-review' not in a and '--delete-branch' not in a,a
   assert stdout.split(ready,1)[1]==f'shipcraft: PR #{prn} merged into main.\n'+advice,stdout
   assert advice not in stderr,stderr
   assert mrs==[] if fault.get('block_log') else len(mrs)==1 and mrs[0]['commit']==expected_head and mrs[0]['method']==method and mrs[0]['result']=='passed',mrs
   assert json.loads((st/'prs.json').read_text())[str(prn)]['state']=='MERGED'
   assert git('--git-dir='+str(origin),'rev-parse','refs/heads/'+branch)==expected_head
   if case=='squash':assert git('--git-dir='+str(origin),'show','-s','--format=%P','main')==base
   if case=='local':assert {r['layer'] for r in rs}>={'ci','review','pr','merge'},rs
  else:
   assert not mrs and stdout.endswith(ready) and advice not in stderr,(stdout,stderr,mrs)
   assert reason.lower() in stderr.lower(),stderr
   if want==1:
    lines=stderr.strip().splitlines();assert (len(lines)>=3 if ci!='off' or review!='off' else len(lines)==3) and all(s.startswith(prefix) for s,prefix in zip(lines[-3:],['shipcraft refused:','Why:','Next:'])),stderr
    assert not merges,merges
   else:assert 'shipcraft: error:' in stderr,stderr
   assert json.loads((st/'prs.json').read_text())[str(prn)]['state']=='OPEN'
   assert git('--git-dir='+str(origin),'rev-parse','main')==fault.get('changed',base)
   assert (st/'comments.jsonl').is_file(),'summary/review lost on later failure'
else:
 assert not gates and not merges and not mrs and ready not in stdout,(trace,rs,stdout)
 assert reason.lower() in (stdout+stderr).lower(),stderr
 if phase=='early':assert not prs,prs
 else:assert len(prs)==1 and prs[0]['result']==('error' if want==2 else 'refused'),prs
 if want==1:
  lines=stderr.strip().splitlines();assert (len(lines)>=3 if ci!='off' or review!='off' else len(lines)==3) and all(s.startswith(prefix) for s,prefix in zip(lines[-3:],['shipcraft refused:','Why:','Next:'])),stderr
 else:assert 'shipcraft: error:' in stderr,stderr
PY110
  pass
}
