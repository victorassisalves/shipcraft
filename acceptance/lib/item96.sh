# Item 96: public PR scheduling, template bytes and measurements; no product reads.
item96_langs() { echo core; }
item96_cases() {
  local c
  for c in control-gh control-slot overlap ci-first review-first queue-timer brief brief-insertions \
    default explicit-ci local off review-off standalone review-pr reuse reuse-publish reuse-model retry \
    ci-stop-approve ci-stop-refuse ci-error-refuse review-publish-stop dual-error no-status start-fails checkout-fails summary-fails log-fails \
    invalid-string invalid-number invalid-bool invalid-array invalid-table invalid-space invalid-case min-absent min-old-ci min-patch-push head-config; do
    echo "v1-96.$c"
  done
}
item96_case() {
  EXPECT="item 96: ${CASE#v1-96.}"
  v1_start codex
  CFGS='execution|ci|"github"
execution|review|"local"
execution|ci_timeout|10
review|retry_wait|0
review|spec|"docs/spec-produto.md"'
  pr_main
  must_accept 'item 96 public contract' cmd "$PY" - "${CASE#v1-96.}" "$(command -v shipcraft)" "$ST" "$CB" "$CW" <<'PY96'
import hashlib,json,os,re,shutil,subprocess,sys,time
from pathlib import Path
title='Titulo-PR-6d1'
case,binary,st,cb,cw=sys.argv[1:];binary=str(Path(binary).resolve());st=Path(st);cb=Path(cb);cw=Path(cw)
def run(*a,timeout=35,env=None):
 p=subprocess.run(list(map(str,a)),stdin=subprocess.DEVNULL,capture_output=True,timeout=timeout,env=env)
 print('$',repr(a),'rc',p.returncode,p.stdout.decode(errors='replace'),p.stderr.decode(errors='replace'),flush=True)
 return p
def git(*a):
 p=run('git',*a);assert p.returncode==0,('fixture git',a,p.stderr)
 return p.stdout.decode().strip()
def snap(message):
 git('add','-A');tree=git('write-tree');sha=git('commit-tree',tree,'-p','HEAD','-m',message);git('update-ref','HEAD',sha)
 return sha
def data(path):
 return [json.loads(s) for s in path.read_text().splitlines()] if path.is_file() else []
def rows():return data(Path('.git/shipcraft/runs.jsonl'))
def calls():return data(st/'reviewer.calls.jsonl')
def text(p):return (p.stdout+p.stderr).decode(errors='replace')
def invoke(kind='pr'):
 if kind=='pr':return run(binary,'pr','--title',title,'--body',cw/'body.md')
 if kind=='review-pr':return run(binary,'review','--pr','1')
 return run(binary,'review')
def reviewer(**kw):(st/'reviewer.json').write_text(json.dumps(kw))
def ghconfig(**kw):(st/'fixture96.json').write_text(json.dumps(kw))
def checkout_proxy():
 realgit=shutil.which('git')
 (cb/'git').write_text('#!'+sys.executable+'\nimport os,sys\nfrom pathlib import Path\na=sys.argv[1:]\nif "worktree" in a and "add" in a:\n Path('+repr(str(st/'checkout-failed96'))+').touch();print("checkout fault96",file=sys.stderr);sys.exit(96)\nos.execv('+repr(realgit)+',['+repr(realgit)+',*a])\n');(cb/'git').chmod(0o755)
def refusal(p):
 ls=[s for s in text(p).splitlines() if s.strip()][-3:]
 assert [s.split(':',1)[0] for s in ls]==['shipcraft refused','Why','Next'],ls
 return '\n'.join(ls)
def origin(r):return (r.get('beside_ci') if type(r.get('beside_ci')) is bool else None,r.get('after_green_ci') if type(r.get('after_green_ci')) is bool else None,r.get('reused',False))
# Only disposable fixture commits use plumbing. No hook, lock or queue file is edited.
config=Path('.shipcraft.toml');s=config.read_text()
floor=re.search(r'shipcraft (\d+\.\d+)\.',run(binary,'--version').stdout.decode()).group(1)
s=re.sub(r'(?m)^shipcraft_min\s*=.*$', 'shipcraft_min = '+json.dumps(floor),s)
after='"push"';minimum=floor;ci='github';review='local';kind='pr';wait=0
if case=='default':after=None
elif case=='control-gh':after=None
elif case=='control-slot':after=None
elif case=='explicit-ci':after='"ci"'
elif case=='local':ci='local'
elif case=='off':ci='off'
elif case=='review-off':review='off'
elif case=='standalone':kind='review'
elif case=='review-pr':kind='review-pr'
elif case=='invalid-string':after='"later96"'
elif case=='invalid-number':after='96'
elif case=='invalid-bool':after='false'
elif case=='invalid-array':after='["push"]'
elif case=='invalid-table':after='{when="push"}'
elif case=='invalid-space':after='"push "'
elif case=='invalid-case':after='"PUSH"'
elif case=='min-absent':minimum=None
elif case=='min-old-ci':after='"ci"';minimum='2.45'
elif case=='min-patch-push':minimum='2.45.0'
elif case=='retry':wait=1
s=re.sub(r'(?m)^ci\s*=.*$', 'ci = '+json.dumps(ci),s)
s=re.sub(r'(?m)^review\s*=\s*"local"\s*$', 'review = '+json.dumps(review),s)
s=re.sub(r'(?m)^retry_wait\s*=.*$', 'retry_wait = '+str(wait),s)
s=re.sub(r'(?m)^shipcraft_min\s*=.*\n','',s)
if minimum is not None:s='shipcraft_min = '+json.dumps(minimum)+'\n'+s
if case=='min-absent':s=re.sub(r'(?m)^retry_wait\s*=.*\n','',s)
if case=='no-status':s=re.sub(r'(?m)^ci_timeout\s*=.*$', 'ci_timeout = 3',s)
if case=='queue-timer':s=re.sub(r'(?m)^ci_timeout\s*=.*$', 'ci_timeout = 1',s)
if after is not None:s=s.replace('[review]\n','[review]\nafter = '+after+'\n',1)
if case=='brief-insertions':
 literal='CI is green at this commit (literal96); CI already ran them; CI is green at this commit and the suite is CI\'s job; The suite: not rerun (CI green at literal96)'
 title='TITLE96 '+literal
 s=re.sub(r'(?m)^test_command = (.*)$',lambda m:'test_command = '+json.dumps(json.loads(m[1])+' # COMMAND96 '+literal),s)
 (cw/'body.md').write_text('BODY96 '+literal+'\n')
 Path('docs/spec-produto.md').write_text('SPEC96 '+literal+'\n')
 Path('tests/test_smoke.py').write_text(Path('tests/test_smoke.py').read_text()+'\n# BATTERY96 '+literal+'\n')
if case=='head-config':
 block=re.search(r'(?ms)^\[review\]\n(.*?)(?=^\[|\Z)',s)
 dotted=re.sub(r'(?m)^([a-z_]+)\s*=',r'review.\1 =',block[1].replace('after = "push"\n',''))
 s='review.after = "pu\\u0073h" # dotted96\n'+dotted+'\n'+s[:block.start()]+s[block.end():];s=s.replace('\n','\r\n')
if case=='brief-insertions':s=s.replace('after = "push"',"after = 'push' # literal96")
config.write_text(s);snap('chore: item96 fixture policy');git('push','-q','origin','main');git('fetch','-q','origin')
git('checkout','-qb','feature/item96')
Path('value96.py').write_text('value96 = 96\n'+('# DIFF96 '+literal+'\n' if case=='brief-insertions' else ''))
sha=snap('feat: item96');(st/'sha').write_text(sha+'\n')
if case=='head-config':
 config.write_text(config.read_text().replace('review.after = "pu\\u0073h" # dotted96','review.after = "ci"').replace('ci = "github"','ci = "off"'))
 sha=snap('chore: head tries to change policy');(st/'sha').write_text(sha+'\n')
# The wrapper preserves GitHub REST status shapes, delegates every other call to
# the existing offline gh, and records wall-clock boundaries outside its lock.
real=cb/'gh96-real';(cb/'gh').rename(real)
(cb/'gh').write_text('#!'+sys.executable+'\n'+r'''
import json,os,subprocess,sys,time
from pathlib import Path
root=Path(__file__).parent;st=root/'state';a=sys.argv[1:]
c=json.loads((st/'fixture96.json').read_text()) if (st/'fixture96.json').exists() else {}
def emit(**r):
 with (st/'events96.jsonl').open('a') as f:f.write(json.dumps(dict(t=time.time(),**r))+'\n')
status=a[:1]==['api'] and any('/commits/' in x and x.endswith('/statuses') for x in a)
comment=a[:2] in (['pr','comment'],['pr','review']) or (a[:1]==['api'] and any('/comments' in x or x.endswith('/reviews') for x in a) and any(x in ('-f','-F','--input') for x in a))
post=a[:1]==['api'] and any('/statuses/' in x for x in a)
if status:
 clock=st/'clock96';start=float(clock.read_text()) if clock.exists() else time.time()
 if not clock.exists():clock.write_text(str(start))
 emit(event='ci-start')
 if c.get('status_error'):
  emit(event='ci-error');print('gh: injected statuses failure (HTTP 503)',file=sys.stderr);sys.exit(1)
 state=c.get('state','success')
 if c.get('pending_for',0)>time.time()-start:state='pending'
 sha=(st/'sha').read_text().strip()
 print(json.dumps([dict(id=96,sha=sha,context='shipcraft/ci',state=state,description='fixture96',created_at='2026-01-01T00:00:00Z')]))
 emit(event='ci-end',state=state);sys.exit(0)
if comment:
 count=st/'comment-count96';n=int(count.read_text())+1 if count.exists() else 1;count.write_text(str(n))
 log=Path('.git/shipcraft/runs.jsonl');rr=[json.loads(x) for x in log.read_text().splitlines() if json.loads(x).get('layer')=='review'] if log.is_file() else []
 emit(event='comment',number=n,review_rows=len(rr))
 if c.get('fail_comment')==n:
  emit(event='publication-error');print('gh: injected comment failure (HTTP 503)',file=sys.stderr);sys.exit(1)
if post:
 emit(event='status-post',argv=a)
 if c.get('fail_final') and any(x=='state=success' for x in a):
  emit(event='publication-error');print('gh: injected final status failure (HTTP 503)',file=sys.stderr);sys.exit(1)
p=subprocess.run([str(root/'gh96-real'),*a]);sys.exit(p.returncode)
''');(cb/'gh').chmod(0o755)
ghconfig();reviewer(mode='approve')
if case=='control-gh':
 # Same wrapper, exact routing, real status JSON, delay transition and fault switches.
 ghconfig(pending_for=.15)
 u='repos/acme/proj/commits/'+sha+'/statuses'
 a=run(cb/'gh','api',u);assert json.loads(a.stdout)[0]['state']=='pending'
 time.sleep(.2);b=run(cb/'gh','api',u);assert json.loads(b.stdout)[0]['state']=='success'
 ghconfig(status_error=True);e=run(cb/'gh','api',u);assert e.returncode==1 and b'HTTP 503' in e.stderr
 git('push','-q','origin','HEAD');q=run(cb/'gh','pr','create','--title','control96','--body','control96');assert q.returncode==0
 ghconfig(fail_comment=1);e=run(cb/'gh','pr','comment','1','--body','blocked96');assert e.returncode==1 and b'comment failure' in e.stderr
 ghconfig(fail_final=True);e=run(cb/'gh','api','repos/acme/proj/statuses/'+sha,'-f','state=success','-f','context=shipcraft/review');assert e.returncode==1 and b'final status failure' in e.stderr
 assert [e['event'] for e in data(st/'events96.jsonl')].count('publication-error')==2
 checkout_proxy();q=run(cb/'git','worktree','add','unused96')
 assert q.returncode==96 and (st/'checkout-failed96').exists() and b'checkout fault96' in q.stderr
 q=run(cb/'git','rev-parse','HEAD');assert q.returncode==0 and q.stdout.decode().strip()==sha
elif case in ('invalid-string','invalid-number','invalid-bool','invalid-array','invalid-table','invalid-space','invalid-case','min-absent','min-old-ci','min-patch-push'):
 # Every public reader validates; the staged hook supplies the measured code.
 git('push','-q','origin','HEAD');q=run(cb/'gh','pr','create','--title','Invalid96','--body','Invalid96');assert q.returncode==0
 for args in [('status',),('review',),('review','--pr','1'),('pr','--title','Invalid96','--body',str(cw/'body.md')),('ci','--base','origin/main'),('merge','1'),('check',)]:
  p=run(binary,*args);assert p.returncode==1,('after config must refuse',args,text(p))
  msg=refusal(p);assert '[review] after' in msg,msg
  if case in ('min-absent','min-old-ci','min-patch-push'):assert 'shipcraft_min' in msg and '2.46' in msg,msg
  else:
   value={'invalid-string':'later96','invalid-number':'96','invalid-bool':'false','invalid-array':'push','invalid-table':'push','invalid-space':'push ','invalid-case':'PUSH'}[case]
   assert value in msg,(value,msg)
 assert not calls(),'config refusal started reviewer'
 hook=[r for r in rows() if r['layer']=='hook'][-1];assert hook['code']=='config-invalid',hook
 assert not [r for r in rows() if r['layer']=='pr'],'early invalid policy added PR row'
 if case=='invalid-number':
  log=Path('.git/shipcraft/runs.jsonl');before=log.read_bytes();log.unlink();log.mkdir()
  p=run(binary,'check');assert p.returncode==1 and '[review] after' in refusal(p),text(p)
  assert log.is_dir() and not list(log.iterdir()),'failed append changed refusal or rewrote history'
else:
 if case=='overlap':ghconfig(pending_for=3);reviewer(mode='approve',sleep=1)
 elif case=='ci-first':reviewer(mode='changes',sleep=3)
 elif case=='review-first':ghconfig(pending_for=4)
 elif case=='head-config':ghconfig(pending_for=3)
 elif case=='ci-stop-approve':ghconfig(state='failure');reviewer(mode='approve',sleep=.4)
 elif case=='ci-stop-refuse':ghconfig(state='failure');reviewer(mode='changes',sleep=.4)
 elif case=='ci-error-refuse':ghconfig(status_error=True);reviewer(mode='changes')
 elif case=='review-publish-stop':ghconfig(state='failure',fail_comment=1)
 elif case=='dual-error':ghconfig(status_error=True,fail_comment=1)
 elif case=='no-status':ghconfig(state='pending')
 elif case=='summary-fails':ghconfig(fail_comment=2)
 elif case=='start-fails':
  (cb/'codex').write_text('#!/missing/interpreter96\n');(cb/'codex').chmod(0o755)
 elif case=='checkout-fails':checkout_proxy()
 elif case=='retry':reviewer(mode='retry-then-approve',fail_times=1)
 elif case=='log-fails':
  p=Path('.git/shipcraft/runs.jsonl');p.unlink(missing_ok=True);p.mkdir()
 if case in ('reuse','reuse-publish','reuse-model'):
  # Cache comes from an ordinary explicit PR review, not a forged row.
  git('push','-q','origin','HEAD');q=run(cb/'gh','pr','create','--title','Titulo-PR-6d1','--body-file',cw/'body.md');assert q.returncode==0
  q=invoke('review-pr');assert q.returncode==0,text(q)
  if case=='reuse-model':
   p=Path('.git/shipcraft/runs.jsonl');rs=rows()
   for r in rs:
    if r['layer']=='review':r['model']='different96'
   p.write_text(''.join(json.dumps(r)+'\n' for r in rs))
  (st/'events96.jsonl').unlink(missing_ok=True);(st/'comment-count96').unlink(missing_ok=True)
  reviewer(mode='changes');ghconfig(state='failure')
  if case=='reuse':ghconfig(pending_for=4)
  if case=='reuse-publish':ghconfig(state='failure',fail_final=True)
  # Reused approval's final status is success; the dedicated wrapper fault targets it.
 if kind=='review-pr':
  git('push','-q','origin','HEAD');q=run(cb/'gh','pr','create','--title','Titulo-PR-6d1','--body-file',cw/'body.md');assert q.returncode==0
 children=[];holder=None
 try:
  if case in ('queue-timer','control-slot'):
   # An independent public review uses the same machine queue, a separate stub
   # directory and eight-second reviewer. Never seed machine slot files.
   other=cw/'holder96';other.mkdir();shutil.copy(cb/'codex',other/'codex');shutil.copytree(st,other/'state')
   (other/'state'/'reviewer.json').write_text(json.dumps(dict(mode='approve',sleep=8,timeline=str(cw/'holder-timeline96'),name='holder96')))
   env=dict(os.environ,PATH=str(other)+os.pathsep+os.environ['PATH'])
   hf=(cw/'holder-output96').open('wb');holder=subprocess.Popen([binary,'review'],stdin=subprocess.DEVNULL,stdout=hf,stderr=subprocess.STDOUT,env=env);children.append(holder)
   deadline=time.time()+12
   while not (other/'state'/'reviewer.calls.jsonl').exists() and holder.poll() is None and time.time()<deadline:time.sleep(.02)
   assert (other/'state'/'reviewer.calls.jsonl').exists(),('holder never acquired slot',(cw/'holder-output96').read_text())
   if case=='queue-timer':ghconfig(state='pending')
  before=time.time();p=invoke(kind);elapsed=time.time()-before
  if holder is not None:assert holder.wait(timeout=12)==0,(cw/'holder-output96').read_text();hf.close()
 finally:
  for child in children:
   if child.poll() is None:child.kill();child.wait()
 es=data(st/'events96.jsonl');cs=calls();rs=rows();rr=[r for r in rs if r['layer']=='review'];prs=[r for r in rs if r['layer']=='pr'];o=text(p)
 if case=='control-slot':
  holder_end=float((cw/'holder-timeline96').read_text().splitlines()[-1].split()[-1])
  assert p.returncode==0 and len(cs)==1 and cs[0]['start']>=holder_end,(cs,o)
  assert next(e['t'] for e in es if e['event']=='ci-start')<holder_end,es
  assert re.search(r'queue|position',o,re.I),o
 elif case=='overlap':
  assert p.returncode==0 and len(cs)==1,o
  green=next(e['t'] for e in es if e.get('state')=='success')
  assert cs[0]['start']<green,('review did not start while CI pending',cs,es)
  assert any(e.get('state')=='pending' for e in es),es
  assert origin(rr[-1])==(True,False,False),rr[-1];assert prs[-1]['review_after']=='push',prs
 elif case=='ci-first':
  assert p.returncode==1 and prs[-1]['code']=='review-changes-requested' and elapsed>=3,(elapsed,o)
  assert cs[0]['start']+3>next(e['t'] for e in es if e.get('state')=='success'),es
  assert len(data(st/'comments.jsonl'))==2,'review and summary must both publish'
  assert origin(rr[-1])==(True,False,False),rr[-1];assert prs[-1]['review_after']=='push',prs
 elif case=='review-first':
  assert p.returncode==0 and elapsed>=4,(elapsed,o)
  green=next(e['t'] for e in es if e.get('state')=='success')
  writes=data(st/'writes.log');final=next(e for e in writes if e['kind']=='status' and 'shipcraft/review' in e['text'] and 'success' in e['text'])
  assert final['t']<green,('review publication waited for CI',final,es)
  comments=[e for e in writes if e['kind']=='comment'];assert comments[0]['t']<green<=comments[-1]['t'],comments
  assert next(e for e in es if e['event']=='comment')['review_rows']==1,es
  statuses=[e for e in writes if e['kind']=='status' and 'shipcraft/review' in e['text']]
  assert len(statuses)==2 and 'pending' in statuses[0]['text'] and statuses[0]['t']<comments[0]['t']<statuses[1]['t'],writes
  assert origin(rr[-1])==(True,False,False),rr[-1];assert prs[-1]['review_after']=='push',prs
 elif case=='queue-timer':
  holder_end=float((cw/'holder-timeline96').read_text().splitlines()[-1].split()[-1])
  polls=[e for e in es if e['event']=='ci-end']
  assert p.returncode==1 and len(cs)==1,(cs,o)
  assert polls and polls[-1]['t']<holder_end,('CI timeout began after review acquired its slot',polls,holder_end)
  assert cs[0]['start']>=holder_end and 'review did not run' not in o,(cs,o)
  assert prs[-1]['code']=='ci-github-no-status' and prs[-1]['review_after']=='push',prs
  assert origin(rr[-1])==(True,False,False),rr[-1]
 elif case in ('brief','brief-insertions'):
  assert p.returncode==0 and len(cs)==1,o
  b=next(v for k,v in cs[0]['files'].items() if k.endswith('/brief.md'))
  payload=b.split('## The intent (the PR body)\n',1)[1].split('## Steps\n',1)[0]
  instructions=b.split('## The intent (the PR body)\n',1)[0]+b.split('## Steps\n',1)[1]
  if case=='brief-insertions':
   assert '- Title: TITLE96 '+literal+'\n' in b,b
   assert ' # COMMAND96 '+literal in b,b
   instructions=instructions.replace(' # COMMAND96 '+literal,'').replace('- Title: '+title,'- Title: TITLE')
  for phrase in ('CI is running at this commit ('+sha[:7]+')','CI runs them','CI is running at this commit and the suite is CI\'s job','The suite: not rerun (CI running at '+sha[:7]+')'):
   assert phrase in instructions,('missing exact template replacement',phrase,instructions)
  for phrase in ('CI is green at this commit','CI already ran them','CI green at '):assert phrase not in instructions,phrase
  if case=='brief-insertions':
   for marker in ('BODY96','SPEC96','BATTERY96','DIFF96'):assert marker+' '+literal in payload,('inserted text was rewritten',marker,payload)
  # Reverse ONLY the three built-in instruction regions, then use item82's
  # public normalized whole-template digest: all other instruction bytes fixed.
  if case=='brief-insertions':b=b.replace(' # COMMAND96 '+literal,'',1)
  b=b.replace('CI is running at this commit ('+sha[:7]+')','CI is green at this commit ('+sha[:7]+')',1)
  start=b.index('## Steps\n');b=b[:start]+b[start:].replace('CI runs them','CI already ran them',1).replace('CI is running at this commit and the suite is CI\'s job','CI is green at this commit and the suite is CI\'s job',1).replace('The suite: not rerun (CI running at '+sha[:7]+')','The suite: not rerun (CI green at '+sha[:7]+')',1)
  b=re.sub(r'pull request #[^ ]+ in the project [^\n]+\.', 'pull request #PR in the project PROJECT.',b,count=1)
  b=re.sub(r'(?m)^- Title: .*$', '- Title: TITLE',b);b=re.sub(r'(?m)^- Head commit: .*$', '- Head commit: HEAD',b);b=re.sub(r'(?m)^- Merge base with the base branch: .*$', '- Merge base with the base branch: BASE',b)
  scratch=re.search(r'working directory: (.+)/arvore\n',b).group(1);b=b.replace(scratch,'SCRATCH')
  b=re.sub(r'## The intent \(the PR body\)\n.*?\n## Steps\n','PAYLOAD\n## Steps\n',b,flags=re.S)
  b=re.sub(r'(APPROVE at |CHANGES REQUESTED at )[0-9a-f]{40}',r'\1HEAD',b);b=re.sub(r'(CI is green at this commit \()[0-9a-f]{7}(\))',r'\1HEAD7\2',b);b=re.sub(r'(CI green at )[0-9a-f]{7}(\))',r'\1HEAD7\2',b)
  assert hashlib.sha256(b.encode()).hexdigest()=='773a99d73de349ea8f13e93fcf3f8ee86bbd61a8a7b805e59219a5fb0e151c16',b
  announces=[l for l in o.splitlines() if l.startswith('shipcraft: review by ')]
  assert len(announces)==1 and announces[0].endswith('; CI is running at '+sha[:7]+', so the suite is not rerun'),announces
  assert origin(rr[-1])==(True,False,False),rr[-1]
 elif case=='default':
  assert p.returncode==0,o
  assert prs[-1].get('review_after')=='ci',prs
  assert origin(rr[-1])==(False,True,False),rr[-1]
 elif case=='explicit-ci':
  assert p.returncode==0,o
  assert cs[0]['start']>=next(e['t'] for e in es if e.get('state')=='success'),es
  assert '; CI is green at '+sha[:7]+', so the suite is not rerun' in o,o
  assert prs[-1].get('review_after')=='ci',prs;assert origin(rr[-1])==(False,True,False),rr[-1]
 elif case=='local':
  assert p.returncode==0 and not any(e['event']=='ci-start' for e in es),o
  assert 'CI is running' not in o,o
  assert origin(rr[-1])==(False,True,False),rr[-1];assert prs[-1].get('review_after')=='push',prs
 elif case=='off':
  assert p.returncode==0 and not any(e['event']=='ci-start' for e in es),o
  assert 'CI is running' not in o,o;assert origin(rr[-1])==(False,False,False),rr[-1];assert prs[-1].get('review_after')=='push',prs
 elif case=='review-off':
  assert p.returncode==0 and not cs and not rr,o
  assert 'CI is running' not in o,o;assert prs[-1].get('review_after')=='push',prs
 elif case=='standalone':
  assert p.returncode==0 and not any(e['event']=='ci-start' for e in es),o
  assert 'CI is running' not in o and not prs,o;assert origin(rr[-1])==(False,False,False),rr[-1]
 elif case=='review-pr':
  assert p.returncode==0 and not any(e['event']=='ci-start' for e in es),o
  assert 'CI is running' not in o and not prs,o;assert origin(rr[-1])==(False,False,False),rr[-1]
 elif case=='reuse':
  assert p.returncode==0 and len(cs)==1 and len(rr)==2,(cs,rr,o)
  r=rr[-1];assert r.get('reused') is True and 'beside_ci' not in r and 'after_green_ci' not in r,r
  assert prs[-1]['result']=='passed' and prs[-1].get('review_after')=='push',prs
  green=next(e['t'] for e in es if e.get('state')=='success')
  success=next(e['t'] for e in es if e['event']=='status-post' and 'state=success' in e['argv'])
  assert success<green,('reuse publication waited for CI',es)
  assert not [e for e in es if e['event']=='comment'] or len([e for e in es if e['event']=='comment'])==1,es
 elif case=='reuse-publish':
  assert p.returncode==2 and any(e['event']=='publication-error' for e in es),(o,es)
  assert len(cs)==1 and rr[-1].get('reused') is True and 'beside_ci' not in rr[-1] and 'after_green_ci' not in rr[-1],rr
  assert prs[-1]['result']=='error' and prs[-1].get('review_after')=='push',prs
 elif case=='reuse-model':
  assert p.returncode==1 and len(cs)==2,(cs,o)
  assert rr[-1]['code']=='changes-requested' and not rr[-1].get('reused',False),rr
  assert prs[-1]['code']=='ci-github' and prs[-1].get('review_after')=='push',prs;assert origin(rr[-1])==(True,False,False),rr[-1]
 elif case=='retry':
  assert p.returncode==0 and len(cs)==len(rr)==2,(cs,rr,o)
  assert [r['result'] for r in rr]==['error','passed'],rr
  for r in rr:assert origin(r)==(True,False,False),r
  assert prs[-1].get('review_after')=='push',prs
 elif case=='ci-stop-approve':
  assert p.returncode==1 and len(cs)==1 and rr[-1]['result']=='passed',(cs,rr,o)
  assert prs[-1]['code']=='ci-github' and 'review did not run' not in refusal(p),prs
  assert origin(rr[-1])==(True,False,False),rr[-1];assert prs[-1].get('review_after')=='push',prs
 elif case=='ci-stop-refuse':
  assert p.returncode==1 and len(cs)==1 and rr[-1]['code']=='changes-requested',(cs,rr,o)
  assert prs[-1]['code']=='ci-github' and 'review did not run' not in refusal(p),prs
  assert origin(rr[-1])==(True,False,False),rr[-1];assert prs[-1].get('review_after')=='push',prs
 elif case=='ci-error-refuse':
  assert p.returncode==2 and len(cs)==1 and rr[-1]['code']=='changes-requested',(cs,rr,o)
  errors=[l for l in o.splitlines() if l.startswith('shipcraft: error:')]
  assert errors and 'statuses failure' in errors[-1] and 'comment failure' not in errors[-1] and prs[-1]['result']=='error',o
  assert origin(rr[-1])==(True,False,False),rr[-1];assert prs[-1].get('review_after')=='push',prs
 elif case=='review-publish-stop':
  assert p.returncode==2 and any(e['event']=='publication-error' for e in es),(o,es)
  assert 'comment failure' in o and len(rr)==1 and rr[-1]['result']=='passed',o
  assert prs[-1]['result']=='error' and prs[-1].get('review_after')=='push',prs;assert origin(rr[-1])==(True,False,False),rr[-1]
 elif case=='dual-error':
  assert p.returncode==2 and any(e['event']=='publication-error' for e in es) and any(e['event']=='ci-error' for e in es),(o,es)
  errors=[l for l in o.splitlines() if l.startswith('shipcraft: error:')]
  assert errors and 'statuses failure' in errors[-1] and 'comment failure' not in errors[-1] and prs[-1]['result']=='error',o
  assert origin(rr[-1])==(True,False,False),rr[-1];assert prs[-1].get('review_after')=='push',prs
 elif case=='no-status':
  assert p.returncode==1 and len(cs)==1 and rr[-1]['result']=='passed',(cs,rr,o)
  assert prs[-1]['code']=='ci-github-no-status' and 'review did not run' not in refusal(p),prs
  assert origin(rr[-1])==(True,False,False),rr[-1];assert prs[-1].get('review_after')=='push',prs
 elif case=='start-fails':
  assert p.returncode==1 and not cs and len(rr)==1 and rr[-1]['result']=='error',(rr,o)
  assert origin(rr[-1])==(True,False,False),rr[-1];assert prs[-1].get('review_after')=='push',prs
 elif case=='checkout-fails':
  assert p.returncode==2 and (st/'checkout-failed96').exists() and not rr,(rr,o)
  assert any(e['event']=='ci-end' for e in es),es
  assert prs[-1]['result']=='error' and prs[-1].get('review_after')=='push',prs
 elif case=='summary-fails':
  assert p.returncode==2 and any(e['event']=='publication-error' for e in es),(o,es)
  assert rr[-1]['result']=='passed' and prs[-1]['result']=='error',rs
  assert origin(rr[-1])==(True,False,False),rr[-1];assert prs[-1].get('review_after')=='push',prs
 elif case=='log-fails':
  assert p.returncode==0 and len(cs)==1 and not rs,(cs,o)
  assert '; CI is running at '+sha[:7]+', so the suite is not rerun' in o,o
 elif case=='head-config':
  assert p.returncode==0 and len(cs)==1,o
  assert cs[0]['start']<next(e['t'] for e in es if e.get('state')=='success'),('head overrode base policy',es,cs)
  assert prs[-1].get('review_after')=='push',prs;assert origin(rr[-1])==(True,False,False),rr[-1]
 else:raise AssertionError('unrouted case '+case)
 # Every late failure keeps the already pushed branch and created PR.
 if kind=='pr':
  if prs:
   assert abs(prs[-1]['secs']-elapsed)<2,(elapsed,prs[-1])
   if ci=='github':assert prs[-1]['queue_secs'] is None,prs[-1]
   assert prs[-1]['locks']==[],prs[-1]
  assert git('ls-remote','origin','refs/heads/feature/item96').split()[0]==sha
  assert len(json.loads((st/'prs.json').read_text()))==1
 # Review copies are removed even when CI/publication later fails.
 assert all(not Path(c['cwd']).exists() for c in cs),cs
PY96
  pass
}
