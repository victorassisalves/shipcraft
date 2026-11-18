# Item 121: spec c58f518, public CLI only; recorded reviews and offline gh.
item121_langs() { echo core; }
item121_cases() {
 local c
 for c in args-order args-bounds args-invalid args-repeat args-github usage discovery missing-root bad-git list-shapes list-failure list-timeout comments-failure comments-timeout recorded152 recorded160 recorded13 headings heading-reject title location location-empty prefix lines count count-invalid pages classes priority unicode boundaries text json-order empty partial all-unread readonly live control-gh control-live; do echo "v1-121.$c"; done
}
item121_case() {
 EXPECT="item 121: ${CASE#v1-121.}"
 v1_start codex
 # The existing producer uses its established offline gh and real local origin.
 case "$CASE" in v1-121.live|v1-121.control-live)
  CFGS='execution|ci|"off"'
  pr_main; pr_feature
  git rev-parse HEAD > "$ST/sha"
  pr_outside "$BR"
  "$PY" - "$CB/codex" "$ST/reviewer.json" <<'PRODUCER'
from pathlib import Path
import json,sys
p=Path(sys.argv[1]);s=p.read_text();old='REVIEW-BODY-MARKER-3a9: nothing to point out beyond the above.'
assert s.count(old)==1
p.write_text(s.replace(old,'## Blocking 1 — Quartz121\\nLocation: producer121.py:7'))
Path(sys.argv[2]).write_text(json.dumps({'mode':'changes','blocking':1}))
PRODUCER
 ;;
 esac
 must_accept 'item 121 ledger contract' cmd "$PY" - "$CASE" "$(command -v shipcraft)" "$CW" "$ST" "$CB" "$ACEITE/fixtures/item121" <<'PY121'
import itertools,json,os,shutil,signal,subprocess,sys,time
from pathlib import Path
case,binary,cw,st,cb,fixtures=sys.argv[1:]
binary=str(Path(binary).resolve());cw=Path(cw).resolve();st=Path(st);cb=Path(cb);fixtures=Path(fixtures);live_root=Path.cwd()
root=cw/"ledger121 space 'quote";root.mkdir();(root/'.git').mkdir();cwd=root
env=dict(os.environ)
realgit=shutil.which('git')
for k in subprocess.check_output([realgit,'rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES']:env.pop(k,None)
tools=cw/'tools121';tools.mkdir();table=cw/'answers121.json';calls=cw/'calls121.jsonl';gitcalls=cw/'git121.jsonl'
(tools/'gh').write_text('#!'+sys.executable+'\n'+'''import json,os,signal,sys,time
from pathlib import Path
'''+f'table=Path({str(table)!r});calls=Path({str(calls)!r})\n'+'''a=sys.argv[1:]
with calls.open('a') as f:f.write(json.dumps({'args':a,'cwd':os.getcwd()})+'\n')
r=json.loads(table.read_text()).get(json.dumps(a),{'exit':91})
sys.stderr.write('private gh diagnostic121\n')
if r.get('sleep'):time.sleep(r['sleep'])
if r.get('signal'):os.kill(os.getpid(),signal.SIGTERM)
sys.stdout.buffer.write(bytes.fromhex(r['raw']) if 'raw' in r else json.dumps(r.get('json'),ensure_ascii=False).encode())
raise SystemExit(r.get('exit',0))
'''.replace("+'\n'","+'\\n'").replace("diagnostic121\n'","diagnostic121\\n'"))
(tools/'gh').chmod(0o755)
(tools/'git').write_text('#!'+sys.executable+'\nimport sys\nfrom pathlib import Path\nPath('+repr(str(gitcalls))+').write_text(repr(sys.argv))\nraise SystemExit(92)\n');(tools/'git').chmod(0o755)
env['PATH']=str(tools) # Never fall through to a real gh, git or reviewer.
P=['pr','list','--state','merged','--limit','1000','--json','number']
def C(n):return ['api','--paginate','--slurp',f'repos/{{owner}}/{{repo}}/issues/{n}/comments?per_page=100']
def records(p):return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def answers(entries):table.write_text(json.dumps({json.dumps(k):v for k,v in entries}))
def snapshot():return {str(p.relative_to(root)):(p.lstat().st_mode,os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None) for p in root.rglob('*')}
def run(args):
 before=snapshot();calls.unlink(missing_ok=True);gitcalls.unlink(missing_ok=True);start=time.time()
 p=subprocess.run([binary,*args],cwd=cwd,env=env,input=b'',capture_output=True,timeout=72)
 print('COMMAND121',args,p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 assert snapshot()==before,'command wrote repository state'
 return p,records(calls),time.time()-start
prefix='**shipcraft: review executed by codex, on this machine**\n'
def body(s):return {'body':prefix+s}
def finding(title,cls='Other',pr=7,location=None):return dict(kind='finding',pr=pr,**{'class':cls},title=title,location=location)
classes=[
'Typed input lost (leave, reload, refresh over a dirty form)',
'Session, workspace or project boundary (sign-out, another user, slug, tenant)',
'Order and overlap (late or out-of-order response, overlapping saves, retry, during a refresh)',
'Failure paths (error, refusal, 4xx/5xx, partial failure)',
'Permissions and roles',
'Consent, tracking and conversions (pixel, cookies, attribution, events)',
'Markdown, MDX and link handling (a syntax form that slips past a check)',
'Signature, review and publish state (draft, live, export, deploy)',
'Dates, numbers and declared limits',
'Paths, files and locks (symlink, slash, backup, directory)',
'Setup, docs and deploy wiring (entry point, provisioning, migration)',
'Other']
header='# Review findings\n\nEvery Blocking finding the review raised on merged PRs, grouped by class, from the highest PR number down.\nGenerated by `shipcraft report --findings`; do not edit by hand.\n\n'
usage='usage: shipcraft --version | shipcraft init [--lang python|node|go] [--github]\n     | shipcraft init --lang other --command <cmd> --glob <glob>... [--github]\n     | shipcraft red [--redo] [--base <ref>] [--all] [--fix [--reported-at <time>] [--fixes-release <tag>]]\n     | shipcraft check [--commit-msg <file>] | shipcraft close\n     | shipcraft ci --base <ref> [--pr]\n     | shipcraft pr [--title <t>] [--body <file>] [--merge] | shipcraft review [--pr <n>]\n     | shipcraft merge <pr> [--no-review "<reason>"] | shipcraft status | shipcraft report [--json] [--since <tag>] [--github] | shipcraft report --findings [--json] [--since <pr>]\n'
# Scenarios hold complete case-owned inputs and oracles. Shared code checks only
# mechanics, exact rows/text, read-only state, and the case-provided call sequence.
scenarios=[]
if case=='v1-121.args-order':
 for flags in itertools.permutations([['--findings'],['--json'],['--since','007']]):
  scenarios.append(dict(args=sum(flags,[]),entries=[(P,{'json':[{'number':6},{'number':7},{'number':9},{'number':7}]}),(C(9),{'json':[[body('## Blocking 1 Quartz9')]]}),(C(7),{'json':[[body('## Blocking 1 Quartz7')]]})],rows=[finding('Quartz9',pr=9),finding('Quartz7')],calls=[P,C(9),C(7)]))
elif case=='v1-121.args-bounds':
 for n in ('1','0000000000000000001','9999999999999999999'):
  scenarios.append(dict(args=['--findings','--since',n,'--json'],entries=[(P,{'json':[{'number':18446744073709551615},{'number':int(n)}]}),(C(18446744073709551615),{'json':[[]]}),(C(int(n)),{'json':[[]]})],rows=[],calls=[P,C(18446744073709551615),C(int(n))]))
elif case=='v1-121.args-invalid':
 for tail in (['--since'],*(['--since',v] for v in ('0','-3','v2.1.0','1.5','','10000000000000000000','18446744073709551616','١','+1',' 7','7\n','7e0','7_0'))):
  scenarios.append(dict(args=['--findings',*tail],invalid=True,calls=[]))
elif case=='v1-121.args-repeat':
 for args in (['--findings','--findings'],['--findings','--json','--json'],['--since','7','--findings','--since','8'],['--findings','--wat'],['--Findings'],['--findings=yes']):scenarios.append(dict(args=args,invalid=True,calls=[]))
elif case=='v1-121.args-github':
 for args in (['--findings','--github'],['--github','--json','--findings'],['--findings','--since','0','--github']):scenarios.append(dict(args=args,invalid=True,calls=[]))
elif case=='v1-121.usage':
 for args in ([],['help'],['-h'],['--help']):
  p,cs,_=run(args);assert p.returncode==0 and p.stdout.decode()==usage,(p.stdout,p.stderr);assert cs==[]
elif case=='v1-121.discovery':
 # A relative gitdir and commondir, nested cwd and broken config/log must not
 # redirect discovery or provoke git/config/log readers.
 (root/'.git').rmdir();(root/'.git').write_text('gitdir: metadata/worktree\n');(root/'metadata/worktree').mkdir(parents=True);(root/'metadata/worktree/commondir').write_text('../common\n');(root/'metadata/common').mkdir()
 cwd=root/'packages/deep';cwd.mkdir(parents=True);(cwd/'.shipcraft.toml').write_text('not TOML [')
 (root/'.shipcraft.toml').write_bytes(b'\xff');(root/'metadata/common/shipcraft').mkdir();(root/'metadata/common/shipcraft/runs.jsonl').mkdir()
 scenarios.append(dict(entries=[(P,{'json':[{'number':7}]}),(C(7),{'json':[[body('## Blocking 1 Quartz')]]})],rows=[finding('Quartz')],calls=[P,C(7)]))
elif case=='v1-121.missing-root':
 (root/'.git').rmdir()
 for args in (['--findings'],['--findings','--json']):scenarios.append(dict(args=args,notread='no git repository found',calls=[]))
elif case=='v1-121.bad-git':
 (root/'.git').rmdir()
 for raw in (b'not a gitdir\n',b'\xff'):
  scenarios.append(dict(gitfile=raw,notread='no git repository found',calls=[]))
 # A self-referential link fails open/read without OS-dependent chmod behavior.
 scenarios.append(dict(gitfile='symlink-loop',notread='no git repository found',calls=[]))
elif case=='v1-121.list-shapes':
 for raw in (b'{}',b'null',b'[1]',b'[{}]',b'[{"number":0}]',b'[{"number":-1}]',b'[{"number":true}]',b'[{"number":null}]',b'[{"number":[]}]',b'[{"number":{}}]',b'[{"number":"7"}]',b'[{"number":7.0}]',b'[{"number":7e0}]',b'[{"number":18446744073709551616}]',b'[{"number":7},{}]',b'\xff',b'[',b'\xef\xbb\xbf[]',b'[] trailing'):
  scenarios.append(dict(entries=[(P,{'raw':raw.hex()})],notread='unreadable answer from gh',calls=[P]))
elif case=='v1-121.list-failure':
 for fault in ({'exit':3,'json':[{'number':7}]},{'signal':True},{'missing':True},{'no_start':True}):
  scenarios.append(dict(entries=[(P,fault)],fault=fault,notread='gh failed',calls=[] if 'missing' in fault or 'no_start' in fault else [P]))
elif case=='v1-121.list-timeout':
 scenarios.append(dict(entries=[(P,{'sleep':65})],notread='gh timed out',calls=[P],timeout=True))
elif case=='v1-121.comments-failure':
 for fault,reason in [({'exit':3,'json':[[body('## Blocking 1 Lost')]]},'gh failed'),({'signal':True},'gh failed')]+[({'raw':raw.hex()},'unreadable answer from gh') for raw in (b'\xff',b'[',b'[]',b'{}',b'[{}]',b'[[null]]',b'[[{}]]',b'[[{"body":null}]]',b'[[{"body":3}]]',b'[[{"body":true}]]',b'[[{"body":[]}]]',b'[[{"body":{}}]]')]:
  scenarios.append(dict(entries=[(P,{'json':[{'number':8},{'number':7},{'number':6}]}),(C(8),{'json':[[body('Blocking: 2\n## Blocking 1 Quartz8')]]}),(C(7),fault),(C(6),{'json':[[body('## Blocking 1 Quartz6')]]})],rows=[dict(kind='pr_not_read',pr=7,reason=reason),finding('Quartz8',pr=8),finding('Quartz6',pr=6)],stderr='report: PR 8: the review says Blocking: 2, 1 Blocking heading(s) read\n'+f'report: PR 7: review comments not read: {reason}\n',calls=[P,C(8),C(7),C(6)]))
elif case=='v1-121.comments-timeout':
 scenarios.append(dict(entries=[(P,{'json':[{'number':9},{'number':8},{'number':7}]}),(C(9),{'json':[[body('## Blocking 1 Quartz9')]]}),(C(8),{'sleep':65}),(C(7),{'json':[[body('## Blocking 1 Never')]]})],rows=[dict(kind='pr_not_read',pr=8,reason='gh timed out'),dict(kind='pr_not_read',pr=7,reason='gh timed out'),finding('Quartz9',pr=9)],stderr='report: PR 8: review comments not read: gh timed out\nreport: PR 7: review comments not read: gh timed out\n',calls=[P,C(9),C(8)],timeout=True))
elif case in ('v1-121.recorded152','v1-121.recorded160','v1-121.recorded13'):
 # Explicit frozen oracles, not a second Markdown parser/classifier.
 name,n={'v1-121.recorded152':('handsoff-152',152),'v1-121.recorded160':('handsoff-160',160),'v1-121.recorded13':('draken-13',13)}[case]
 expected=json.loads((fixtures/(name+'-expected.json')).read_text())
 scenarios.append(dict(entries=[(P,{'json':[{'number':n}]}),(C(n),{'raw':(fixtures/(name+'.json')).read_bytes().hex()})],rows=expected,calls=[P,C(n)]))
elif case=='v1-121.headings':
 text='## Blocking 1 — Quartz\n###  Blocking 02: Amber\n#### Blocking 003\n**Blocking 4 - Opal**\n```md\n## Blocking 5: Jade\n```\n## Blocking 123abc\n'
 scenarios.append(dict(comments=[[body(text)]],rows=[finding(t) for t in ('Quartz','Amber','(no title)','Opal','Jade','abc')]))
elif case=='v1-121.heading-reject':
 text='\n'.join(['# Blocking 1 One','##### Blocking 2 Two',' ## Blocking 3 Three','- **Blocking 4** — Four','## blocking 5 Five','## Blocking findings','**Blocking:**','Blocking: 4','## Blocking ١ Six','## Blocking1 Seven','##\tBlocking 8 Eight','## Blocking\t9 Nine','**Blocking 10 has * star**','**Blocking 11** suffix','## Blocking 12 — Quartz'])
 scenarios.append(dict(comments=[[body(text)]],rows=[finding('Quartz')],stderr='report: PR 7: the review says Blocking: 4, 1 Blocking heading(s) read\n'))
elif case=='v1-121.title':
 text='## Blocking 1 \t:.-—–  Quartz, / % # ..\t \n### Blocking 2 : . - — –\t\n**Blocking 3: literal **\n## Blocking 4: "quote" \\ glyph\x00\n'
 scenarios.append(dict(comments=[[body(text)]],rows=[finding('Quartz, / % # ..'),finding('(no title)'),finding('literal'),finding('"quote" \\ glyph\x00')]))
elif case=='v1-121.location':
 comments=[[body('## Blocking 1 Quartz\n'+label+' \t'+loc+' \t\nLocation: ignored') for label,loc in [('Location:','a.py:1'),('Locations:','a.py:2, b.py:3'),('**Location:**','`p (x).py:4`'),('**Locations:**','[p](p#L5) / %')]]]
 scenarios.append(dict(comments=comments,rows=[finding('Quartz',location=v) for v in ('a.py:1','a.py:2, b.py:3','`p (x).py:4`','[p](p#L5) / %')]))
elif case=='v1-121.location-empty':
 scenarios.append(dict(comments=[[body('## Blocking 1 Quartz\nLocation:\t \nLocation: not fallback\n## Blocking 2 Amber\n location: no\n Location: no\n**Location**: no\n## Blocking 3 Opal'),body('Location: no spill\n## Blocking 1 Jade')]],rows=[finding(t) for t in ('Quartz','Amber','Opal','Jade')]))
elif case=='v1-121.prefix':
 ignored=[' '+prefix,'\ufeff'+prefix,prefix.replace('shipcraft','Shipcraft'),'**shipcraft: review gave no verdict by codex**\n','ordinary\n'+prefix]
 scenarios.append(dict(comments=[[{'body':p+'## Blocking 1 Lost\nBlocking: 99'} for p in ignored]+[body('APPROVE\n## Blocking 1 Quartz')]],rows=[finding('Quartz')]))
elif case=='v1-121.lines':
 # CRLF, trailing tabs/spaces; U+2028/U+2029 and lone CR are NOT separators.
 scenarios.append(dict(comments=[[body('Blocking: 2 \t\r\n## Blocking 1: Quartz \t\r\nLocation: alpha \t\r\n## Blocking 2: Amber\u2028## Blocking 3: embedded\u2029tail\rinside\n')]],rows=[finding('Quartz',location='alpha'),finding('Amber\u2028## Blocking 3: embedded\u2029tail\rinside')]))
elif case=='v1-121.count':
 scenarios.append(dict(comments=[[body('Blocking: 002\nBlocking: 1\n## Blocking 1 Quartz'),body('Blocking: 0\n## Blocking 1 Amber'),body('Blocking: 9999999999999999999')]],rows=[finding('Quartz'),finding('Amber')],stderr='report: PR 7: the review says Blocking: 002, 1 Blocking heading(s) read\nreport: PR 7: the review says Blocking: 0, 1 Blocking heading(s) read\nreport: PR 7: the review says Blocking: 9999999999999999999, 0 Blocking heading(s) read\n'))
elif case=='v1-121.count-invalid':
 text='\n'.join('Blocking: '+n for n in ('','-1','+1','١','1x','10000000000000000000','1.0','1  x'))+'\n Blocking: 2\nblocking: 2\nBlocking: 1\n## Blocking 1 Quartz'
 scenarios.append(dict(comments=[[body(text)]],rows=[finding('Quartz')]))
elif case=='v1-121.pages':
 scenarios.append(dict(comments=[[],[body('## Blocking 1 Quartz'),body('## Blocking 1 Quartz')],[],[body('## Blocking 1 Amber')]],rows=[finding('Quartz'),finding('Quartz'),finding('Amber')]))
 # Entire shape checked before reading even a valid preceding mismatched count.
 for bad in ({'body':None},{},[],7):
  scenarios.append(dict(comments=[[body('Blocking: 99\n## Blocking 1 Lost')],[bad]],rows=[dict(kind='pr_not_read',pr=7,reason='unreadable answer from gh')],stderr='report: PR 7: review comments not read: unreadable answer from gh\n'))
elif case=='v1-121.classes':
 titles=['TYPED','tenant','delayed','falha','permission','cookie','MDX','assinatura','número','slash','provision','Quartz']
 scenarios.append(dict(comments=[[body('\n'.join(f'## Blocking {i+1} {t}' for i,t in enumerate(reversed(titles))))]],rows=[finding(t,c) for t,c in zip(titles,classes)]))
elif case=='v1-121.priority':
 titles=['dirty secret retry error admin cookie link publish date path image','cross retry error admin cookie link publish date path image','retry error admin cookie link publish date path image','error admin cookie link publish date path image','admin cookie link publish date path image','cookie link publish date path image','link publish date path image','publish date path image','date path image','path image','image']
 scenarios.append(dict(comments=[[body('\n'.join(f'## Blocking {i+1} {t}' for i,t in enumerate(titles)))]],rows=[finding(t,c) for t,c in zip(titles,classes)]))
elif case=='v1-121.unicode':
 titles=[('ÂNCORA',6),('PARÊNTESES',6),('PRÉVIA',7),('NÚMERO',8),('DIRETÓRIO',9),('éinputé',11),('éformé',11),('éleadé',11),('édayé',11)]
 scenarios.append(dict(comments=[[body('\n'.join(f'## Blocking {i+1} {t}' for i,(t,_) in enumerate(titles)))]],rows=[finding(t,classes[i]) for t,i in titles]))
elif case=='v1-121.boundaries':
 titles=[('input',0),('leave now',0),('sign-out',1),('signXin',1),('mixup',1),('late',2),('in flight',2),('503',3),('oppref',5),('URL',6),('signage',7),('daylight',8),('pathway',9),('documented',10),('inputs reform plate 1503 locked',11)]
 scenarios.append(dict(comments=[[body('\n'.join(f'## Blocking {n+1} {t}' for n,(t,_) in enumerate(titles)))]],rows=[finding(t,classes[i]) for t,i in titles]))
elif case=='v1-121.text':
 scenarios.append(dict(args=['--since','007','--findings'],comments=[[body('## Blocking 1 Quartz\nLocation: `x.py:2`\n## Blocking 2 dirty\n## Blocking 3 :')]],text=header.replace('--findings`','--findings --since 7`')+'## '+classes[0]+' (1)\n\n- dirty (PR 7)\n\n## Other (2)\n\n- Quartz (`x.py:2`) (PR 7)\n- (no title) (PR 7)\n\n'))
elif case=='v1-121.json-order':
 scenarios.append(dict(entries=[(P,{'json':[{'number':7},{'number':10},{'number':2},{'number':10}]}),*[(C(n),{'json':[[body(f'## Blocking 1 Quartz{n}\n## Blocking 2 dirty{n}')],[body(f'## Blocking 1 Amber{n}')]]}) for n in (10,7,2)]],rows=[finding('dirty'+str(n),classes[0],n) for n in (10,7,2)]+[finding(t+str(n),pr=n) for n in (10,7,2) for t in ('Quartz','Amber')],calls=[P,C(10),C(7),C(2)]))
elif case=='v1-121.empty':
 for comments in ([[]],[[],[]],[[{'body':'not review\n## Blocking 1 Lost'}]],[[body('APPROVE\nBlocking: 0')]]):
  scenarios.append(dict(comments=comments,rows=[]));scenarios.append(dict(args=['--findings'],comments=comments,text=header))
 scenarios.append(dict(entries=[(P,{'json':[]})],rows=[],calls=[P]));scenarios.append(dict(args=['--findings'],entries=[(P,{'json':[]})],text=header,calls=[P]))
elif case=='v1-121.partial':
 scenarios.append(dict(args=['--findings'],entries=[(P,{'json':[{'number':7},{'number':9},{'number':8}]}),(C(9),{'exit':1}),(C(8),{'json':[[body('## Blocking 1 Quartz')]]}),(C(7),{'json':[]})],calls=[P,C(9),C(8),C(7)],stderr='report: PR 9: review comments not read: gh failed\nreport: PR 7: review comments not read: unreadable answer from gh\n',text=header+'Not read: PR 9 (gh failed), PR 7 (unreadable answer from gh).\n\n## Other (1)\n\n- Quartz (PR 8)\n\n'))
elif case=='v1-121.all-unread':
 entries=[(P,{'json':[{'number':8},{'number':7}]}),(C(8),{'exit':1}),(C(7),{'json':[]})]
 err='report: PR 8: review comments not read: gh failed\nreport: PR 7: review comments not read: unreadable answer from gh\n'
 scenarios.append(dict(entries=entries,calls=[P,C(8),C(7)],rows=[dict(kind='pr_not_read',pr=8,reason='gh failed'),dict(kind='pr_not_read',pr=7,reason='unreadable answer from gh')],stderr=err))
 scenarios.append(dict(args=['--findings'],entries=entries,calls=[P,C(8),C(7)],text=header+'Not read: PR 8 (gh failed), PR 7 (unreadable answer from gh).\n\n',stderr=err))
elif case=='v1-121.readonly':
 # Absent/unreadable/malformed irrelevant readers cannot affect this command.
 for mode in ('absent','directory','malformed'):
  scenarios.append(dict(irrelevant=mode,comments=[[body('## Blocking 1 Quartz')]],rows=[finding('Quartz')]))
elif case in ('v1-121.live','v1-121.control-live'):
 root=live_root;cwd=root
 liveenv=dict(os.environ,TMPDIR=str(cw/'review-tmp121'),XDG_STATE_HOME=str(cw/'review-state121'))
 Path(liveenv['TMPDIR']).mkdir();Path(liveenv['XDG_STATE_HOME']).mkdir()
 p=subprocess.run([binary,'review','--pr','1'],cwd=root,env=liveenv,capture_output=True,timeout=90)
 assert p.returncode==1,(p.stdout,p.stderr)
 rs=records(root/'.git/shipcraft/runs.jsonl');assert rs[-1]['code']=='changes-requested' and rs[-1]['result']=='refused',rs
 posted=records(st/'comments.jsonl');assert len(posted)==1,posted
 comment=posted[0]['body'];assert comment.startswith(prefix.rstrip('\n')) and 'Blocking: 1\n' in comment and comment.count('## Blocking 1 — Quartz121')==1,comment
 statuses=records(st/'statuses.jsonl');assert statuses[-1]['state']=='failure' and statuses[-1]['description']=='on this machine: CHANGES REQUESTED, Blocking 1 (codex)',statuses
 answers([(C(1),{'json':[[{'body':comment}]]})]);q=subprocess.run([str(tools/'gh'),*C(1)],capture_output=True)
 assert q.returncode==0 and json.loads(q.stdout)==[[{'body':comment}]] and records(calls)[-1]['args']==C(1),q
 if case=='v1-121.live':scenarios.append(dict(entries=[(P,{'json':[{'number':1}]}),(C(1),{'json':[[{'body':comment}]]})],rows=[finding('Quartz121',pr=1,location='producer121.py:7')],calls=[P,C(1)]))
 else:
  assert len(records(st/'reviewer.calls.jsonl'))==1
  assert not list(Path(liveenv['TMPDIR']).glob('shipcraft-revisao-*'))
elif case=='v1-121.control-gh':
 # The same fake receives an existing report --github query; its unique OPEN
 # PR answer must drive the preexisting pr-not-merged result.
 (root/'.git').rmdir();subprocess.run([realgit,'init','-q','-b','main',str(root)],check=True)
 (root/'.git/shipcraft').mkdir();(root/'.git/shipcraft/runs.jsonl').write_text(json.dumps(dict(layer='merge',result='passed',pr=97,lock='G',locks=['G'],base='main',default_branch='main',at=100,commit='a'*40))+'\n')
 query=['pr','view','97','--json','number,state,mergedAt,headRefOid,mergeCommit']
 answers([(query,{'json':dict(number=97,state='OPEN',mergedAt=None,headRefOid='a'*40,mergeCommit=None)}),(C(7),{'json':[[body('## Blocking 1 Quartz')]]})])
 q=subprocess.run([str(tools/'gh'),*C(7)],capture_output=True);assert q.returncode==0 and json.loads(q.stdout)==[[body('## Blocking 1 Quartz')]],q
 (tools/'git').unlink();(tools/'git').symlink_to(realgit)
 p,cs,_=run(['report','--github','--json']);rows=[json.loads(s) for s in p.stdout.splitlines()]
 assert p.returncode==0 and not p.stderr and [r for r in rows if r['kind']=='github']==[dict(kind='github',selected=1,merge_filled=0,waiting_filled=0,missing={'pr not merged':1})],(p,rows)
 assert [r['args'] for r in cs]==[query],cs
else:raise AssertionError('unrouted '+case)
original_gh=(tools/'gh').read_bytes()
for s in scenarios:
 if 'gitfile' in s:
  (root/'.git').unlink(missing_ok=True)
  if s['gitfile']=='symlink-loop':(root/'.git').symlink_to('.git')
  else:(root/'.git').write_bytes(s['gitfile'])
 if 'irrelevant' in s:
  for path in (root/'.shipcraft.toml',root/'.git/shipcraft/runs.jsonl'):
   if path.is_dir():path.rmdir()
   else:path.unlink(missing_ok=True)
   path.parent.mkdir(parents=True,exist_ok=True)
   if s['irrelevant']=='directory':path.mkdir()
   elif s['irrelevant']=='malformed':path.write_bytes(b'\xff malformed [')
 entries=s.get('entries',[(P,{'json':[{'number':7,'ignored':True}]}),(C(7),{'json':s.get('comments',[[]])})]);answers(entries)
 (tools/'gh').write_bytes(original_gh);(tools/'gh').chmod(0o755)
 if s.get('fault',{}).get('missing'):(tools/'gh').unlink()
 if s.get('fault',{}).get('no_start'):(tools/'gh').write_text('#!/nonexistent121/interpreter\n')
 args=s.get('args',['--findings','--json']);p,cs,elapsed=run(['report',*args])
 if s.get('invalid'):
  assert p.returncode==2 and p.stdout==b'' and p.stderr.decode().startswith('shipcraft: error: invalid arguments: '),(p.returncode,p.stdout,p.stderr)
  assert p.stderr.decode()=='shipcraft: error: invalid arguments: '+' '.join(['report',*args])+'; '+usage,p.stderr
 else:
  assert p.returncode==0,('valid findings command must exit zero',p.returncode,p.stderr)
  assert p.stderr.decode()==s.get('stderr',''),p.stderr
  if 'notread' in s:
   if '--json' in args:assert [json.loads(x) for x in p.stdout.splitlines()]==[dict(kind='findings_not_read',reason=s['notread'])],p.stdout
   else:assert p.stdout.decode()=='review findings not read: '+s['notread']+'\n',p.stdout
  elif 'text' in s:assert p.stdout.decode()==s['text'],p.stdout
  else:
   assert [json.loads(x) for x in p.stdout.splitlines()]==s['rows'],p.stdout
   assert not p.stdout or p.stdout.endswith(b'\n'),p.stdout
 assert [r['args'] for r in cs]==s.get('calls',[P,C(7)]),cs
 assert all(Path(r['cwd'])==root for r in cs),cs
 assert not gitcalls.exists(),'findings/usage launched git'
 if s.get('timeout'):assert 58<=elapsed<70,elapsed
PY121
 pass
}
