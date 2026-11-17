# Item 112: public report and real review rows; no implementation reader.
item112_langs() { echo core; }
item112_cases() {
  local c
  for c in basic interleaved layer result reused reused-other pr-types pr-integers metadata duplicates merge-independent errors-retry escape reader malformed ranking top5 ties whole-zero whole-full fraction text-example text-round text-quarter order-reds order-size order-day since github git-failure config-failure live-count live-publish control-live control-report control-github control-refusal; do echo "v1-112.$c"; done
}
item112_case() {
  EXPECT="item 112: ${CASE#v1-112.}"
  v1_start codex
  case "$CASE" in
    v1-112.control-live|v1-112.live-count|v1-112.live-publish)
      CFGS='execution|ci|"off"
review|retry_wait|1'
      pr_main; pr_feature
      git rev-parse HEAD > "$ST/sha"
      pr_outside "$BR"
      ;;
  esac
  case "$CASE" in v1-112.live-publish) i82_publish_fail ;; esac
  must_accept 'item 112 report contract' cmd "$PY" - "$CASE" "$(command -v shipcraft)" "$CW" "$ST" "$CB" <<'PY112'
import json,os,re,shlex,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw,st,cb=sys.argv[1:];st=Path(st);cb=Path(cb);live_root=Path.cwd();binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/"repo112 space 'quote";root.mkdir();realgit=shutil.which('git');env=dict(os.environ)
for k in subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
def run(*args):
 p=subprocess.run(list(map(str,args)),cwd=root,env=env,input=b'',capture_output=True,timeout=120)
 print('COMMAND112',args,p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 return p
def git(*args):
 p=run(realgit,*args);assert p.returncode==0,('fixture git',p.stderr);return p.stdout.decode().strip()
def write(name,data):
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
def snapshot():
 return {str(p.relative_to(root)):(stat.S_IFMT(p.lstat().st_mode),stat.S_IMODE(p.lstat().st_mode),os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None) for p in root.rglob('*')}
def data(p):return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
git('init','-q','-b','main');git('config','gc.auto','0');git('config','maintenance.auto','false')
write('README.md','item112 fixture\n');write('.git/shipcraft/sentinel',b'keep112\x00\r\n')
tools=cw/'tools112';tools.mkdir();calls=cw/'git-calls112';ghcalls=cw/'gh-calls112';proof=cw/'proof112';fault=cw/'git-fault112';ghfault=cw/'gh-fault112'
# Transparent Git probe: public command recording and one injected read failure.
(tools/'git').write_text('#!'+sys.executable+'\n'+"import json,os,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith open("+repr(str(calls))+",'a') as f:f.write(json.dumps(a)+'\\n')\nif Path("+repr(str(fault))+").exists() and 'for-each-ref' in a:raise SystemExit(93)\nos.execv("+repr(realgit)+",["+repr(realgit)+",*a])\n");(tools/'git').chmod(0o755)
# gh 2.x pr-view JSON shape, as item 79; unexpected calls cannot access a service.
(tools/'gh').write_text('#!'+sys.executable+'\n'+"import json,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith open("+repr(str(ghcalls))+",'a') as f:f.write(json.dumps(a)+'\\n')\nif a!=['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']:raise SystemExit(91)\nif Path("+repr(str(ghfault))+").exists():raise SystemExit(92)\nprint(json.dumps(dict(number=97,state='OPEN',mergedAt=None,headRefOid='a'*40,mergeCommit=None)))\n");(tools/'gh').chmod(0o755)
env['PATH']=str(tools)+os.pathsep+env['PATH']
env.update(GIT_AUTHOR_DATE='1700000000 +0000',GIT_COMMITTER_DATE='1700000000 +0000')
git('add','README.md');git('commit','-qm','fixture112');git('tag','v1.0.0');base=git('rev-parse','HEAD')
env.update(GIT_AUTHOR_DATE='1700086400 +0000',GIT_COMMITTER_DATE='1700086400 +0000')
write('README.md','second release112\n');git('add','README.md');git('commit','-qm','release112');git('tag','v2.0.0')
log=root/'.git/shipcraft/runs.jsonl'
def row(**kw):
 r=dict(layer='review',result='passed',pr=7,commit='foreign112',at=100,secs=45,lock='',locks=[],branch='topic112',code='')
 r.update(kw);return r
def wire(rs):return ''.join(json.dumps(r,ensure_ascii=False)+'\n' for r in rs).encode()
def report(rs,args=('--json',)):
 if rs is not None:write('.git/shipcraft/runs.jsonl',rs if isinstance(rs,bytes) else wire(rs))
 before=snapshot();p=run(binary,'report',*args)
 assert p.returncode==0 and not p.stderr,(p.returncode,p.stdout,p.stderr)
 assert snapshot()==before,'report wrote repository state'
 return p.stdout.decode()
def objects(s,kind):return [r for r in (json.loads(x) for x in s.split('\n') if x) if r['kind']==kind]
def reviews(s):return objects(s,'review')
def lines(s):return [x for x in s.split('\n') if x.startswith('review:')]
def live(mode='approve',**kw):
 global root,log
 root=live_root;log=root/'.git/shipcraft/runs.jsonl'
 env['PATH']=str(cb)+os.pathsep+env['PATH']
 (st/'reviewer.json').write_text(json.dumps(dict(mode=mode,**kw)))
 return run(binary,'review','--pr','1')
# Every case owns its count and text oracle; helpers only construct input/read output.
if case=='v1-112.basic':
 rs=[row(result='refused'),row()]
 calls.unlink(missing_ok=True);s=report(rs);observed=data(calls)
 calls.unlink();report([dict(r,pr=None) for r in rs])
 assert data(calls)==observed and not ghcalls.exists() and not data(st/'reviewer.calls.jsonl'),'new Git/network/reviewer read'
 assert reviews(s)==[dict(kind='review',prs=1,rounds=2,changes_requested=1,second_round=1,second_round_share=1,most=[dict(pr=7,rounds=2)])],s
 assert [r['kind'] for r in map(json.loads,s.splitlines())]==['meta','review','dora'],s
elif case=='v1-112.interleaved':
 rs=[row(pr=12,result='refused'),row(pr=9),row(pr=12),row(pr=8),row(pr=9,result='refused'),row(pr=12,result='refused'),row(pr=3)]
 s=report(rs)
 assert reviews(s)==[dict(kind='review',prs=4,rounds=7,changes_requested=3,second_round=2,second_round_share=.5,most=[dict(pr=12,rounds=3),dict(pr=9,rounds=2)])],s
elif case=='v1-112.layer':
 rs=[row()]+[row(layer=v,result='refused') for v in ('pr','merge','ci','hook','red','close','Review','review ',None,True,7,[],{})]
 r=row();r.pop('layer');rs.append(r);s=report(rs)
 assert not objects(s,'gap'),s
 assert reviews(s)==[dict(kind='review',prs=1,rounds=1,changes_requested=0,second_round=0,second_round_share=0,most=[])],s
elif case=='v1-112.result':
 rs=[row(result='refused')]+[row(result=v) for v in ('error','PASSED','REFUSED','passed ','',None,True,0,[],{})]
 r=row();r.pop('result');rs.append(r);s=report(rs)
 assert not objects(s,'gap'),s
 assert reviews(s)==[dict(kind='review',prs=1,rounds=1,changes_requested=1,second_round=0,second_round_share=0,most=[])],s
elif case=='v1-112.reused':
 rs=[row(),row(reused=True,result='refused'),row(pr=9,reused=True),row(pr=9,reused=True,result='refused')];s=report(rs)
 assert reviews(s)==[dict(kind='review',prs=1,rounds=1,changes_requested=0,second_round=0,second_round_share=0,most=[])],s
elif case=='v1-112.reused-other':
 rs=[row(result='refused')]+[row(reused=v) for v in (False,None,0,1,'true','false',[],{})];s=report(rs)
 assert not objects(s,'gap'),s
 assert reviews(s)==[dict(kind='review',prs=1,rounds=9,changes_requested=1,second_round=1,second_round_share=1,most=[dict(pr=7,rounds=9)])],s
elif case=='v1-112.pr-types':
 rs=[row(pr=1)]+[row(pr=v,result='refused') for v in (0,-1,7.0,'7',True,False,None,[],{})]
 r=row();r.pop('pr');rs.append(r);s=report(rs)
 assert not objects(s,'gap'),s
 assert reviews(s)==[dict(kind='review',prs=1,rounds=1,changes_requested=0,second_round=0,second_round_share=0,most=[])],s
elif case=='v1-112.pr-integers':
 raw=wire([row(pr=n) for n in (18446744073709551615,9007199254740992,9007199254740993,18446744073709551615)])
 for token in ('7.0','7e0','18446744073709551616','-0'):
  raw+=wire([row(pr='TOKEN112',result='refused')]).replace(b'"TOKEN112"',token.encode())
 s=report(raw);assert not objects(s,'gap'),s
 assert reviews(s)==[dict(kind='review',prs=3,rounds=4,changes_requested=0,second_round=1,second_round_share=1/3,most=[dict(pr=18446744073709551615,rounds=2)])],s
elif case=='v1-112.metadata':
 rs=[row(at=999999,commit='one',branch='one',lock='A',locks=['A'])]
 r=dict(layer='review',pr=7,result='refused');rs.append(r)
 rs.append(row(at=-99,commit=None,branch=[],lock='',locks=['B','C'],agent={},model=12,effort=False,code='reviewer-no-verdict',after_green_ci=True,beside_ci=True,diff_sha256='different',text_sha256=None,secs=-9))
 s=report(rs)
 assert reviews(s)==[dict(kind='review',prs=1,rounds=3,changes_requested=1,second_round=1,second_round_share=1,most=[dict(pr=7,rounds=3)])],s
elif case=='v1-112.duplicates':
 s=report([row(),row(),row(),row(pr=8)])
 assert reviews(s)==[dict(kind='review',prs=2,rounds=4,changes_requested=0,second_round=1,second_round_share=.5,most=[dict(pr=7,rounds=3)])],s
elif case=='v1-112.merge-independent':
 rs=[row(pr=8,layer='merge'),row(pr=8,layer='pr'),row(pr=8),row(pr=8),row(pr=7,result='refused'),row(pr=9,layer='pr'),row(pr=9,layer='merge')]
 s=report(rs)
 assert reviews(s)==[dict(kind='review',prs=2,rounds=3,changes_requested=1,second_round=1,second_round_share=.5,most=[dict(pr=8,rounds=2)])],s
elif case=='v1-112.errors-retry':
 rs=[row(result='error',code='reviewer-no-verdict'),row(),row(pr=8,result='error'),row(pr=8,result='refused'),row(pr=9,result='error'),row(pr=9,result='error')]
 s=report(rs)
 assert reviews(s)==[dict(kind='review',prs=2,rounds=2,changes_requested=1,second_round=0,second_round_share=0,most=[])],s
elif case=='v1-112.escape':
 rs=[row(escape=True,result='refused'),row(pr=8,escape=True),row(escape=False),row(pr=9,escape='true')];s=report(rs)
 assert reviews(s)==[dict(kind='review',prs=2,rounds=2,changes_requested=0,second_round=0,second_round_share=0,most=[])],s
elif case=='v1-112.reader':
 raw=b'\xef\xbb\xbf'+wire([row(reason='quoted " spaces \u2028\u2029')]).replace(b'\n',b'\r\n')+b' \t\r\n'
 raw+=wire([row(reason='INVALID112')]).replace(b'INVALID112',b'\xff')
 raw+=wire([row(pr=8)]).replace(b'"pr": 8',b'"pr": 99, "pr": 8')
 raw+=wire([row(pr=8,result='refused')])[:-1]+b'\r'
 s=report(raw);assert not objects(s,'gap'),s
 assert reviews(s)==[dict(kind='review',prs=2,rounds=4,changes_requested=1,second_round=2,second_round_share=1,most=[dict(pr=7,rounds=2),dict(pr=8,rounds=2)])],s
elif case=='v1-112.malformed':
 raw=wire([row()])+b'{broken112\n[]\nnull\n'+wire([row(pr='OVER112')]).replace(b'"OVER112"',b'1e400')+wire([row(result='refused')])
 s=report(raw);assert [r['line'] for r in objects(s,'gap')]==[2,3,4,5],s
 assert reviews(s)==[dict(kind='review',prs=1,rounds=2,changes_requested=1,second_round=1,second_round_share=1,most=[dict(pr=7,rounds=2)])],s
elif case=='v1-112.ranking':
 rs=[row(pr=3),row(pr=12),row(pr=12),row(pr=9),row(pr=12),row(pr=9)];s=report(rs)
 assert reviews(s)==[dict(kind='review',prs=3,rounds=6,changes_requested=0,second_round=2,second_round_share=2/3,most=[dict(pr=12,rounds=3),dict(pr=9,rounds=2)])],s
elif case=='v1-112.top5':
 rs=[row(pr=n) for n in (80,20,10,9,3,2) for _ in range(2)]+[row(pr=100) for _ in range(4)]+[row(pr=1)];s=report(rs)
 assert reviews(s)==[dict(kind='review',prs=8,rounds=17,changes_requested=0,second_round=7,second_round_share=.875,most=[dict(pr=100,rounds=4),dict(pr=2,rounds=2),dict(pr=3,rounds=2),dict(pr=9,rounds=2),dict(pr=10,rounds=2)])],s
 t=report(rs,args=());assert len(lines(t))==1 and lines(t)[0].endswith(': #100 (4), #2 (2), #3 (2), #9 (2), #10 (2)'),t
elif case=='v1-112.ties':
 s=report([row(pr=n) for n in (9007199254740993,9007199254740992,10,2) for _ in range(2)])
 assert reviews(s)==[dict(kind='review',prs=4,rounds=8,changes_requested=0,second_round=4,second_round_share=1,most=[dict(pr=2,rounds=2),dict(pr=10,rounds=2),dict(pr=9007199254740992,rounds=2),dict(pr=9007199254740993,rounds=2)])],s
elif case=='v1-112.whole-zero':
 rs=[row(pr=7),row(pr=8,result='refused')];s=report(rs);t=report(rs,args=())
 assert reviews(s)==[dict(kind='review',prs=2,rounds=2,changes_requested=1,second_round=0,second_round_share=0,most=[])],s
 assert type(reviews(s)[0]['second_round_share']) is int,s
 assert lines(t)==['review: 2 PR(s) reviewed in 2 round(s), 1 requested changes; 0 needed a second round (0%): none'],t
elif case=='v1-112.whole-full':
 rs=[row(result='refused'),row(result='refused')];s=report(rs);t=report(rs,args=())
 assert reviews(s)==[dict(kind='review',prs=1,rounds=2,changes_requested=2,second_round=1,second_round_share=1,most=[dict(pr=7,rounds=2)])],s
 assert type(reviews(s)[0]['second_round_share']) is int,s
 assert lines(t)==['review: 1 PR(s) reviewed in 2 round(s), 2 requested changes; 1 needed a second round (100%): #7 (2)'],t
elif case=='v1-112.fraction':
 s=report([row(),row(),row(pr=8),row(pr=9)])
 assert reviews(s)==[dict(kind='review',prs=3,rounds=4,changes_requested=0,second_round=1,second_round_share=1/3,most=[dict(pr=7,rounds=2)])],s
elif case=='v1-112.text-example':
 rs=[row(pr=12,result='refused'),row(pr=9),row(pr=12),row(pr=8),row(pr=9,result='refused'),row(pr=12,result='refused'),row(pr=3)]
 t=report(rs,args=())
 assert lines(t)==['review: 4 PR(s) reviewed in 7 round(s), 3 requested changes; 2 needed a second round (50%): #12 (3), #9 (2)'],t
elif case=='v1-112.text-round':
 t=report([row(pr=2),row(pr=2),row(pr=10),row(pr=10),row(pr=1)],args=())
 assert lines(t)==['review: 3 PR(s) reviewed in 5 round(s), 0 requested changes; 2 needed a second round (67%): #2 (2), #10 (2)'],t
elif case=='v1-112.text-quarter':
 t=report([row(pr=n) for n in (7,7,8,9,10)],args=())
 assert lines(t)==['review: 4 PR(s) reviewed in 5 round(s), 0 requested changes; 1 needed a second round (25%): #7 (2)'],t
elif case=='v1-112.order-reds':
 rs=[row(layer='red',lock='A',at=1),row(layer='pr',product_lines=9,warn_lines=2),row(layer='merge',lock='A',locks=['A'],at=2,base='main',default_branch='main'),row(layer='ci',result='refused',code='suite-red'),row()]
 raw=wire(rs)+b'{broken112\n';s=report(raw);t=report(raw,args=())
 assert [r['kind'] for r in map(json.loads,s.splitlines())]==['meta','lock','day','size','reds','review','dora','gap'],s
 ls=t.splitlines();i=next((i for i,l in enumerate(ls) if l.startswith('review:')),None)
 assert i is not None and ls[i-1].startswith('reds:') and ls[i+1]=='DORA',t
elif case=='v1-112.order-size':
 rs=[row(layer='pr',product_lines=9,warn_lines=2),row()];s=report(rs);t=report(rs,args=())
 assert [r['kind'] for r in map(json.loads,s.splitlines())]==['meta','size','review','dora'],s
 ls=t.splitlines();i=next((i for i,l in enumerate(ls) if l.startswith('review:')),None)
 assert i is not None and ls[i-1].startswith('size:') and ls[i+1]=='DORA',t
elif case=='v1-112.order-day':
 rs=[row(layer='merge',lock='A',at=100,base='main',default_branch='main'),row(layer='merge',lock='B',at=86400,base='main',default_branch='main'),row()];s=report(rs);t=report(rs,args=())
 assert [r['kind'] for r in map(json.loads,s.splitlines())]==['meta','lock','lock','day','day','review','dora'],s
 ls=t.splitlines();i=next((i for i,l in enumerate(ls) if l.startswith('review:')),None)
 assert i is not None and ls[i-1].startswith('day ') and ls[i+1]=='DORA',t
elif case=='v1-112.since':
 rs=[row(at=1),row(at=2),row(pr=9,at=3)];s=report(rs,args=('--since','v2.0.0','--json'));t=report(rs,args=('--since','v2.0.0'))
 assert objects(s,'dora')[0]['deploys']['n']==1 and objects(s,'dora')[0]['git']['releases']==2,s
 assert reviews(s)==reviews(report(rs)) and lines(t)==lines(report(rs,args=())),(s,t)
 assert reviews(s)==[dict(kind='review',prs=2,rounds=3,changes_requested=0,second_round=1,second_round_share=.5,most=[dict(pr=7,rounds=2)])],s
elif case=='v1-112.github':
 rs=[row(layer='red',lock='G',at=1),row(layer='close',lock='G',at=2),row(layer='merge',pr=97,lock='G',locks=['G'],base='main',default_branch='main'),row(pr=97),row(pr=97,result='refused'),row(pr=8)]
 s=report(rs,args=('--json','--github'));t=report(rs,args=('--github',))
 assert data(ghcalls)==[['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']]*2,data(ghcalls)
 ghfault.touch();f=report(rs,args=('--json','--github'));ft=report(rs,args=('--github',))
 assert objects(s,'github')[0]['missing']=={'pr not merged':1} and objects(f,'github')[0]['missing']=={'gh failed':1},(s,f)
 extra=dict(blocking=0,blocking_read=0,blocking_commits=2,blocking_missing={'no commit in the run log':2},blocking_most=[])
 assert reviews(s)==reviews(f)==[dict(reviews(report(rs))[0],**extra)],(s,f)
 assert lines(t)==lines(ft)==[lines(report(rs,args=()))[0]+'; Blocking 0 in 0 of 2 reviewed commit(s): none; not read: no commit in the run log 2'],t
 assert reviews(f)==[dict(kind='review',prs=2,rounds=3,changes_requested=1,second_round=1,second_round_share=.5,most=[dict(pr=97,rounds=2)],**extra)],f
elif case=='v1-112.git-failure':
 fault.touch();rs=[row(),row(result='refused')];s=report(rs);t=report(rs,args=())
 assert objects(s,'dora')[0]['git']['reason'].endswith('exited 93'),s
 assert reviews(s)==[dict(kind='review',prs=1,rounds=2,changes_requested=1,second_round=1,second_round_share=1,most=[dict(pr=7,rounds=2)])],s
 assert lines(t)==['review: 1 PR(s) reviewed in 2 round(s), 1 requested changes; 1 needed a second round (100%): #7 (2)'],t
elif case=='v1-112.config-failure':
 write('.shipcraft.toml','[report]\nrelease_tags=""\n');rs=[row()];s=report(rs);t=report(rs,args=())
 assert objects(s,'dora')[0]['git']['reason']=='[report] in .shipcraft.toml is invalid: release_tags is empty',s
 assert reviews(s)==[dict(kind='review',prs=1,rounds=1,changes_requested=0,second_round=0,second_round_share=0,most=[])],s
 assert lines(t)==['review: 1 PR(s) reviewed in 1 round(s), 0 requested changes; 0 needed a second round (0%): none'],t
elif case=='v1-112.live-count':
 p=live('retry-then-approve',fail_times=1);rs=[r for r in data(log) if r['layer']=='review']
 assert p.returncode==0 and [r['result'] for r in rs]==['error','passed'] and all(r['pr']==1 for r in rs),(p,rs)
 assert len(data(st/'reviewer.calls.jsonl'))==2
 s=report(None);t=report(None,args=())
 assert reviews(s)==[dict(kind='review',prs=1,rounds=1,changes_requested=0,second_round=0,second_round_share=0,most=[])],s
 assert lines(t)==['review: 1 PR(s) reviewed in 1 round(s), 0 requested changes; 0 needed a second round (0%): none'],t
elif case=='v1-112.live-publish':
 p=live('changes');rs=[r for r in data(log) if r['layer']=='review']
 assert p.returncode!=0 and (cb/'publish82-failed').exists() and len(rs)==1 and rs[0]['pr']==1 and rs[0]['result']=='refused',(p,rs)
 assert [r['state'] for r in data(st/'statuses.jsonl') if r['context']=='shipcraft/review']==['pending']
 s=report(None);t=report(None,args=())
 assert reviews(s)==[dict(kind='review',prs=1,rounds=1,changes_requested=1,second_round=0,second_round_share=0,most=[])],s
 assert lines(t)==['review: 1 PR(s) reviewed in 1 round(s), 1 requested changes; 0 needed a second round (0%): none'],t
elif case=='v1-112.control-live':
 p=live();rs=[r for r in data(log) if r['layer']=='review']
 assert p.returncode==0 and len(rs)==1 and rs[0]['pr']==1 and rs[0]['result']=='passed' and rs[0]['locks']==[],(p,rs)
 cs=data(st/'reviewer.calls.jsonl');assert len(cs)==1 and not Path(cs[0]['cwd']).exists(),cs
 assert [r['state'] for r in data(st/'statuses.jsonl') if r['context']=='shipcraft/review']==['pending','success']
 s=report(None);t=report(None,args=())
 assert objects(s,'meta')[0]['last_at']==max(r['at'] for r in data(log)),s
 assert 'runs recorded on this machine only' in t and len(data(st/'reviewer.calls.jsonl'))==1,t
elif case=='v1-112.control-report':
 rs=[row(layer='red',lock='control112',at=17),row(layer='close',lock='control112',at=29),row(layer='merge',lock='control112',locks=['control112'],at=47,base='main',default_branch='main')]
 s=report(rs);t=report(rs,args=())
 assert objects(s,'lock')[0]['red_to_merge']==30 and '30 s' in t and not reviews(s) and not lines(t),s
 assert objects(s,'dora')[0]['git']['releases']==2,s
 empty=report([]);emptytext=report([],args=());log.unlink()
 assert report(None)==empty and report(None,args=())==emptytext
 log.mkdir();assert report(None)==empty and report(None,args=())==emptytext;log.rmdir()
 for ignored in ([row(reused=True),row(reused=True,result='refused')],[row(result='error'),row(result='error')],[row(pr=None),row(pr=0),row(pr='7')]):
  assert not reviews(report(ignored)) and not lines(report(ignored,args=())),ignored
 fault.touch();s=report(rs)
 assert objects(s,'dora')[0]['git']['reason'].endswith('exited 93') and objects(s,'lock')[0]['red_to_merge']==30 and not reviews(s),s
 assert data(calls) and not ghcalls.exists()
elif case=='v1-112.control-github':
 rs=[row(layer='red',lock='G',at=1),row(layer='close',lock='G',at=2),row(layer='merge',pr=97,lock='G',locks=['G'],base='main',default_branch='main')]
 s=report(rs,args=('--json','--github'))
 assert objects(s,'github')[0]['missing']=={'pr not merged':1} and data(ghcalls)==[['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']],s
 ghfault.touch();s=report(rs,args=('--json','--github'))
 assert objects(s,'github')[0]['missing']=={'gh failed':1} and not reviews(s),s
elif case=='v1-112.control-refusal':
 write('.git/shipcraft/runs.jsonl',wire([row(),row()]));before=snapshot()
 p=run(binary,'report','--json','--since','v99.0.0')
 assert p.returncode==2 and not p.stdout and p.stderr.strip()==b'report: --since v99.0.0 is not a release tag on refs/heads/main',(p.stdout,p.stderr)
 assert snapshot()==before
 calls.unlink(missing_ok=True);p=run(binary,'report','--json','--json')
 assert p.returncode==2 and not p.stdout and b'invalid arguments:' in p.stderr and b'usage:' in p.stderr,(p.stdout,p.stderr)
 assert not calls.exists() and snapshot()==before
else:raise AssertionError('unrouted '+case)
# Schema only: numerical oracles remain in the individual arms above.
if 's' in locals() and s.startswith('{'):
 for r in reviews(s):
  assert set(r)==({'kind','prs','rounds','changes_requested','second_round','second_round_share','most'} | (set(extra) if case=='v1-112.github' else set())),r
  assert all(type(r[k]) is int for k in ('prs','rounds','changes_requested','second_round')),r
  assert type(r['second_round_share']) in (int,float),r
  assert all(set(x)=={'pr','rounds'} and type(x['pr']) is int and type(x['rounds']) is int for x in r['most']),r
PY112
  pass
}
