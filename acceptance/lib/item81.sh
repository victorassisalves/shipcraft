# Item 81: real Git history and runner reports; implementation is never read.
item81_langs() { echo python node go; }
item81_cases() {
  echo v1-81.main; echo v1-81.same-suite
  [ "${l:-}" = python ] || return 0
  local c
  for c in stub-break guard guard-flaky all no-base no-merge git-failed map-fails map-suite-local added untracked modified protect edit-hook delete-hook edit-ci delete-ci close-ci second-suite second-cases second-passes flaky-order many escaped tree-error tree-status tree-signal tree-empty tree-prefix tree-folder tree-merge-base tree-once tree-unused path-bytes redo-exempt redo-same-file redo-unchanged same-file-unmapped log-fails write-fails refusal; do echo "v1-81.$c"; done
}
item81_case() {
  EXPECT="item 81: ${CASE#v1-81.}"; v1_start
  [ "$LP" != go ] || { PATH="$GOBIN:$PATH"; export PATH; }
  must_accept 'item 81 lock boundary with real suites' cmd "$PY" - "${CASE#v1-81.}" "$LP" "$(command -v shipcraft)" <<'PY81'
import hashlib,json,os,re,shlex,shutil,signal,subprocess,sys
from pathlib import Path
mode,lang,binary=sys.argv[1:]; binary=str(Path(binary).resolve())
parent=Path.cwd(); root=parent/'project81'; root.mkdir(); os.chdir(root)
errors=[]
def want(value,message):
 if not value: errors.append(message)
def write(path,text):
 p=Path(path); p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text)
def run(*args,ok=True,env=None):
 p=subprocess.run(args,capture_output=True,text=True,timeout=120,env=env)
 print('$',shlex.join(args),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 if ok: assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr)
 return p
def git(*args): return run('git',*args).stdout.strip()
def commit(msg): git('add','-A'); git('commit','-qm',msg)
def rows():
 p=Path('.git/shipcraft/runs.jsonl')
 return [json.loads(x) for x in p.read_text().splitlines()] if p.is_file() else []
def locks(): return sorted(Path('.shipcraft/locks').glob('*.json'))
def test(suite,name,body='False'):
 if lang=='python':
  path=suite+'/tests/test_'+name+'.py'; text='from pathlib import Path\nimport os,pytest\ndef test_'+name+'():\n    assert '+body+'\n'
 elif lang=='node':
  path=suite+'/tests/'+name+'.test.ts'; text="import {it,expect} from 'vitest';\nit('"+name+"',()=>expect(false).toBe(true));\n"
 else:
  path=suite+'/'+name+'_test.go'; text='package item81\nimport "testing"\nfunc Test'+name.title()+'(t *testing.T) { t.Fatal("'+name+'") }\n'
 write(path,text); return path

git('init','-q','-b','main'); git('config','user.name','RED81'); git('config','user.email','red81@example.invalid')
write('.gitignore','__pycache__/\n.pytest_cache/\nnode_modules/\n')
if lang=='node': (root/'node_modules').symlink_to(parent/'node_modules',target_is_directory=True)
if lang=='go': write('go.mod','module example.invalid/item81\n\ngo 1.21\n')
# The adapter observes suite executions/lists and delegates to the real runner.
# Unmapped variants alter only the named case in the actual pytest report.
record=parent/'observed81.jsonl'; os.environ['OBS81']=str(record); os.environ['MODE81']=mode
adapter=root/'adapter81.py'
write(adapter,'''import json,os,subprocess,sys
from pathlib import Path
import xml.etree.ElementTree as ET
suite,lang,junit=sys.argv[1:]
c=os.environ.get('SHIPCRAFT_CASES');f=os.environ.get('SHIPCRAFT_FILES')
read=lambda p: Path(p).read_bytes().decode().split('\\0')[:-1] if p else None
with open(os.environ['OBS81'],'a') as out: out.write(json.dumps(dict(suite=suite,cases=read(c),files=read(f),tmp=os.environ.get('TMPDIR')))+'\\n')
if lang=='python':
 paths=[p for p in (read(f) or []) if Path(p).name.startswith('test_') and p.endswith('.py')]
 cmd=['pytest','-q','-p','no:cacheprovider','--junitxml='+junit,*(paths or ['tests'])]
 if os.environ['MODE81']=='escaped':cmd+=['-o','disable_test_id_escaping_and_forfeit_all_rights_to_community_support=True']
elif lang=='node': cmd=['node',str(Path('../node_modules/vitest/vitest.mjs').resolve()),'run','--maxWorkers=1','--reporter=junit','--outputFile='+junit]
else: cmd=['gotestsum','--junitfile',junit,'--','-count=1','./...']
p=subprocess.run(cmd)
if os.environ['MODE81']=='escaped' and suite=='old':
 names=[case.get('name','') for case in ET.parse(junit).iter('testcase')]
 ident=next(name for name in names if name.startswith('test_legacy81['))
 assert '\\n' in ident and '\\t' in ident,repr(ident)
 assert '\\\\n' not in ident and '\\\\t' not in ident,repr(ident)
 Path(os.environ['OBS81']+'.escaped').write_text(json.dumps(ident))
if os.environ['MODE81'].startswith('redo-') and os.environ.get('READY81') and f and not c:
 Path(junit).unlink();sys.exit(1)
if os.environ['MODE81'] in ('map-fails','map-suite-local','same-file-unmapped') and lang=='python':
 t=ET.parse(junit)
 for case in t.iter('testcase'):
  if case.get('name')=='test_unmapped81':case.set('classname','unknown81');case.set('name','unmapped81');case.attrib.pop('file',None)
 t.write(junit)
sys.exit(p.returncode)
''')
same=mode in ('same-suite','second-cases','map-fails','same-file-unmapped')
suites=['own'] if same else ['old','outside','own'] if mode=='map-suite-local' else ['old','alias','own'] if mode=='tree-once' else ['old','own']
config='shipcraft_min = "0.0"\nlang = '+json.dumps(lang)+'\nrunner = '+json.dumps({'python':'pytest','node':'vitest','go':'gotestsum'}[lang])+'\n[execution]\nci = "local"\nreview = "off"\n'
for suite in suites:
 suite_root='old' if suite=='alias' else suite
 Path(suite_root,'tests').mkdir(parents=True,exist_ok=True)
 command=shlex.join([sys.executable,str(adapter),suite,lang,'{junit}'])
 if lang=='go': command+=' # gotestsum'
 config+='\n[[suite]]\nname = '+json.dumps(suite)+'\nroot = '+json.dumps(suite_root)+'\nfilter = "command"\ncommand = '+json.dumps(command)+'\nglobs = '+json.dumps(['tests/**'] if lang!='go' else ['**/*_test.go'])+'\n'
write('.shipcraft.toml',config)
old_suite='own' if same else 'old'
old=test(old_suite,'legacy81', 'Path("../oldvalue81").read_text()=="green"' if mode=='stub-break' else 'False')
if mode=='guard-flaky':
 write(old,'from pathlib import Path\nimport os\ndef test_legacy81():\n    marker=Path(os.environ["OBS81"]+".flaky")\n    seen=marker.exists()\n    marker.touch()\n    assert seen\n')
if mode=='path-bytes':
 special='old/tests/test_é space \"quote\" \'single\'\tline\nend.py'
 Path(old).rename(special);old=special
oldbytes=Path(old).read_bytes(); write('oldvalue81','green' if mode=='stub-break' else 'red')
write('ownvalue81','red')
if mode=='stub-break':test('old','basefail81')
if mode=='many':
 for name in ('z81','a81','é81','b81'): test('old',name)
if mode in ('map-fails','map-suite-local','same-file-unmapped'): test(old_suite,'unmapped81')
if mode=='map-suite-local':test('outside','outside81')
if mode in ('redo-exempt','redo-same-file'):
 # Failing base test is unchanged by this RED. A separate selected test seeds HEAD's lock.
 write('own/tests/test_anchor81.py','from pathlib import Path\nimport os,pytest\ndef test_anchor81():\n    assert Path("../ownvalue81").read_text()=="green"\n'+('def test_later81():\n    if not os.environ.get("ENABLED81"): pytest.skip("not enabled")\n    assert False\n' if mode=='redo-same-file' else ''))
if mode=='escaped':
 # Parametrized names carry real JUnit character references, not invented reports.
 write(old,'import pytest\n@pytest.mark.parametrize("n",[1],ids=["line\\nnext\\tend"] )\ndef test_legacy81(n):\n    assert False\n'); oldbytes=Path(old).read_bytes()
commit('test: base includes an unchanged assertion failure81')
# Let init install the real native hooks, then commit the install before this RED.
run(binary,'init','--lang',lang);config=Path('.shipcraft.toml').read_text()
commit('chore: commit Shipcraft installation81');base=git('rev-parse','HEAD')
git('update-ref','refs/remotes/origin/main',base); git('symbolic-ref','refs/remotes/origin/HEAD','refs/remotes/origin/main');git('checkout','-qb','feature/item81')
if mode=='stub-break':write('oldvalue81','red')
new=test('own','fresh81','Path("../ownvalue81").read_text()=="green"')
# Config change forces a full run while retaining a readable comparison and paths.
write('.shipcraft.toml',config+'\n# full-run reproduction81\n')
args=[]; dropping=True; expected_code=''; redo=False; unchanged=False
if mode=='all':args=['--all'];dropping=False
if mode=='no-base':args=['--base','missing81'];dropping=False
if mode=='no-merge':
 other=git('commit-tree',git('rev-parse',base+'^{tree}'),'-m','unrelated81');args=['--base',other];dropping=False
if mode=='git-failed':dropping=False
if mode in ('guard','guard-flaky'):
 Path(new).unlink();dropping=False
 if mode=='guard-flaky':expected_code='red-not-reproduced'
if mode in ('added','untracked','modified'):
 extra=test('own','extra81')
 if mode=='added':git('add',extra)
 if mode=='modified':
  # Modify the pre-existing failing file: no failing file is now outside this RED.
  with Path(old).open('a') as f:f.write('\n# changed by RED81\n')
  dropping=False
if mode in ('map-fails','same-file-unmapped'):dropping=False
if mode in ('second-passes','flaky-order'):
 body='bool(os.environ.get("SHIPCRAFT_CASES"))'
 if mode=='second-passes': test('own','fresh81',body);expected_code='red-not-reproduced'
 else:test('own','flaky81',body)
if mode=='refusal':
 write(new,'raise RuntimeError("collection81")\n');expected_code='error-before-assertions'
if mode in ('redo-exempt','redo-same-file','redo-unchanged'):
 # A narrowed opening lock keeps the already-failing old test out of HEAD's cases.
 write('.shipcraft.toml',config)
 if mode=='redo-unchanged':
  initial=run(binary,'red')
 else:
  # anchor is committed, but explicitly change it for the initial narrow RED.
  with Path('own/tests/test_anchor81.py').open('a') as f:f.write('\n# initial RED81\n')
  initial=run(binary,'red')
 assert locks(),initial.stdout
 assert not any('legacy81' in c.lower() for c in json.loads(locks()[0].read_text())['cases']),'fixture initial RED must narrow before redo'
 lock=locks()[0];commit('test: opening lock81');original=lock.read_bytes();original_stat=lock.stat()
 git('update-ref','refs/remotes/origin/main','HEAD');base=git('rev-parse','HEAD')
 if mode=='redo-same-file':os.environ['ENABLED81']='1'
 if mode=='redo-exempt':
  with Path(new).open('a') as f:f.write('\n# repair description in the other locked file81\n')
 # A missing narrowed report triggers the existing full-run fallback, without
 # changing protected bytes or mixing product/config edits into a redo commit.
 write('.shipcraft.toml',config);os.environ['READY81']='1'
 if mode=='redo-unchanged':unchanged=True
 args=['--redo'];redo=True
# Observe the exact public Git protocol; faults affect only the new tree lookup.
realgit=shutil.which('git');bindir=root/'.git/bin81';bindir.mkdir();trace=root/'.git/git81.jsonl'
alternate=None
if mode in ('tree-prefix','tree-folder'):
 # Actual alternate tree output has a longer path, never an equal entry.
 index=root/'.git/alternate81'; env=dict(os.environ,GIT_INDEX_FILE=str(index))
 subprocess.run(['git','read-tree',base],env=env,check=True)
 subprocess.run(['git','update-index','--force-remove',old],env=env,check=True)
 blob=git('rev-parse',base+':'+old)
 longer=old+'.longer' if mode=='tree-prefix' else old+'/child'
 subprocess.run(['git','update-index','--add','--cacheinfo','100644,'+blob+','+longer],env=env,check=True)
 alternate=subprocess.check_output(['git','write-tree'],env=env,text=True).strip();dropping=False
if mode=='tree-empty':dropping=False
if mode in ('tree-error','tree-status','tree-signal'):dropping=False
if mode=='tree-merge-base':
 # The chosen ref's tip lacks old, but its merge base with HEAD still has it.
 idx=root/'.git/tip-index81';e=dict(os.environ,GIT_INDEX_FILE=str(idx))
 subprocess.run(['git','read-tree',base],env=e,check=True);subprocess.run(['git','update-index','--force-remove',old],env=e,check=True)
 tree=subprocess.check_output(['git','write-tree'],env=e,text=True).strip();tip=git('commit-tree',tree,'-p',base,'-m','comparison tip81');git('update-ref','refs/remotes/origin/main',tip)
if mode=='tree-unused':
 with Path(old).open('a') as f:f.write('\n# this RED changes every failing file81\n')
 dropping=False
wrapper='#!'+sys.executable+'\nimport json,os,signal,sys\na=sys.argv[1:]\n'
wrapper+='with open('+repr(str(trace))+',"a") as f:f.write(json.dumps(a)+"\\n")\n'
if mode=='git-failed':wrapper+='if "HEAD^{commit}" in a:sys.exit(128)\n'
wrapper+='if a and a[0]=="ls-tree" and "-r" in a and '+repr(base)+' in a:\n'
if mode=='tree-error':wrapper+=' sys.stderr.write("fatal: lookup81 failed\\nsecond line81\\n");sys.exit(128)\n'
elif mode=='tree-status':wrapper+=' sys.exit(73)\n'
elif mode=='tree-signal':wrapper+=' os.kill(os.getpid(),signal.SIGTERM)\n'
elif mode=='tree-empty':wrapper+=' sys.exit(0)\n'
elif alternate:
 wrapper+=' a=[x.replace('+repr(base)+','+repr(alternate)+') for x in a]\n'
 if mode=='tree-prefix':wrapper+=' a[-1]='+repr(longer)+'\n'
else:wrapper+=' pass\n'
wrapper+='os.execv('+repr(realgit)+',['+repr(realgit)+',*a])\n'
write(bindir/'git',wrapper);(bindir/'git').chmod(0o755);env=dict(os.environ,PATH=str(bindir)+os.pathsep+os.environ['PATH'])
if mode=='log-fails':
 log=Path('.git/shipcraft/runs.jsonl');log.unlink(missing_ok=True);log.mkdir(parents=True)
if mode=='write-fails':
 Path('.shipcraft/locks').mkdir(parents=True,exist_ok=True);Path('.shipcraft/locks').chmod(0o555)
before=rows();record.unlink(missing_ok=True)
try:p=run(binary,'red',*args,ok=False,env=env)
finally:
 if mode=='write-fails':Path('.shipcraft/locks').chmod(0o755)
# Observe both exclusion and the subsequent public protection/closure commands.
ls=locks();d=json.loads(ls[0].read_text()) if ls else None
r=rows()[-1] if rows() else None
calls=[json.loads(x) for x in trace.read_text().splitlines()];treecalls=[a for a in calls if a and a[0]=='ls-tree' and '-r' in a and base in a]
entries=[json.loads(x) for x in record.read_text().splitlines()]
if mode=='escaped':
 observed_id=json.loads(Path(str(record)+'.escaped').read_text())
 want('\n' in observed_id and '\t' in observed_id,'fixture JUnit ID lacks actual LF/tab')
prefix='shipcraft: not locked, failing in test files this RED did not change: '
base_error='shipcraft: every failing case is locked: could not read the base tree ('
if expected_code:
 want(p.returncode==1,'refusal exit');want(not ls,'refusal wrote lock')
 want(r and r['code']==expected_code,'wrong refusal: '+repr(r))
 want('unchanged_dropped' not in r,'refusal has drop field')
 want(prefix not in p.stdout and base_error not in p.stdout,'refusal announced unwritten lock')
 lines=[s for s in (p.stdout+p.stderr).splitlines() if s.strip()][-3:]
 want(len(lines)==3 and all(s.startswith(t) for s,t in zip(lines,('shipcraft refused:','Why:','Next:'))),'three-line refusal')
 if mode=='second-passes':want([e['suite'] for e in entries]==['old','own','own'],'confirmation reran excluded suite')
elif mode=='write-fails':
 want(len(treecalls)==1,'exclusion was never computed before the lock write failed')
 want(p.returncode!=0 and not ls,'failed lock write succeeded')
 want(prefix not in p.stdout and base_error not in p.stdout,'write failure announced unwritten lock')
 want(r and 'unchanged_dropped' not in r,'write failure row announced drops')
else:
 want(p.returncode==0 and len(ls)==1,'RED did not write one lock')
 if d:
  dropped=[c for c in d['cases'] if 'legacy81' in c.lower() or any('test_'+n in c for n in ('z81','a81','é81','b81'))]
  want(bool(dropped)==(not dropping or mode=='map-suite-local'),'unchanged failures in cases: '+repr(d['cases']))
  for key in ('cases','failing_at_red'):
   want(any('legacy81' in c.lower() for c in d[key])==(not dropping or mode=='map-suite-local'),'legacy boundary '+key+': '+repr(d[key]))
   if mode not in ('guard','guard-flaky'):want(any('fresh81' in c.lower() for c in d[key]),'lost own failure '+key)
  want(d['format']==4 and d['state']=='open','format/state changed')
  want(set(d)=={'format','state','files','cases','failing_at_red','kind','reported_at','fixes_release','seal'},'lock schema changed')
  want(old in d['files'],'excluded test lost protection')
  eligible=subprocess.check_output(['git','ls-files','-c','-o','--exclude-standard','-z']).decode().split('\0')
  expected_files={'.shipcraft.toml'}|{f for f in eligible if f and Path(f).is_file() and (f.endswith('_test.go') if lang=='go' else any(f.startswith(('old' if suite=='alias' else suite)+'/tests/') for suite in suites))}
  want(set(d['files'])==expected_files,'protected file set changed: '+repr(d['files']))
  for f,h in d['files'].items():want(h=='sha256:'+hashlib.sha256(Path(f).read_bytes()).hexdigest(),'wrong hash '+f)
  want(d.get('kind')=='feature' and d.get('reported_at') is None and d.get('fixes_release') is None,'feature metadata changed')
  if mode in ('added','untracked'):
   for key in ('cases','failing_at_red'):want(any('extra81' in c for c in d[key]),'new file lost '+key)
  if mode in ('redo-exempt','redo-same-file'):
   want(any('anchor81' in c for c in d['failing_at_red']),'HEAD case not exempt')
   if mode=='redo-same-file':want(any('later81' in c for c in d['failing_at_red']),'same-file skipped case was dropped')
  if mode=='map-suite-local':
   want(any('unmapped81' in c for c in d['failing_at_red']),'failed map suite was filtered')
   want(not any('outside81' in c for c in d['cases']),'map failure crossed suite boundary')
  expected_drop=5 if mode=='many' else 2 if mode in ('tree-once','stub-break') else 1
  lines=p.stdout.splitlines();notices=[s for s in lines if s.startswith(prefix)]
  want(len(notices)==(1 if dropping and not unchanged else 0),'drop notice count: '+repr(notices))
  if dropping and notices:
   notice=notices[0];want(notice.endswith('; CI runs them'),'drop notice suffix')
   want(('outside81' if mode=='map-suite-local' else 'legacy81') in notice.lower() and 'fresh81' not in notice.lower(),'drop notice identities')
   want(prefix not in p.stderr,'drop notice on stderr')
   lockline=next((i for i,s in enumerate(lines) if s.startswith('shipcraft: RED '+('redone at' if redo else 'locked at'))),-1)
   notice_index=lines.index(notice)
   want(0<=notice_index<lockline,'notice must precede lock line')
   confirmations=[i for i,line in enumerate(lines) if line.startswith('shipcraft: not locked, passed on a second run:')]
   want(all(i<notice_index for i in confirmations),'confirmation notice must precede exclusion notice')
   if mode=='many':want('and 2 more' in notice and notice.index('test_a81')<notice.index('test_b81')<notice.index('test_legacy81'),'byte-sorted truncated list')
   if mode=='escaped':want('test_legacy81[line\\nnext\\tend]' in notice,'control characters must escape with one backslash')
  if mode!='log-fails':
   want(len(rows())==len(before)+1,'one red row per command');want(r['layer']=='red' and r['result']=='passed' and r['code']=='','wrong row verdict')
   if mode in ('tree-error','tree-status','tree-signal'):want('unchanged_dropped' in r and r['unchanged_dropped'] is None,'failed tree read requires null sentinel')
   elif dropping and not unchanged:want(r.get('unchanged_dropped')==expected_drop,'drop count: '+repr(r))
   else:want('unchanged_dropped' not in r,'zero drop must omit field')
  if unchanged:
   want(ls[0].read_bytes()==original and ls[0].stat().st_mtime_ns==original_stat.st_mtime_ns,'unchanged redo wrote/replaced lock')
   want('RED unchanged:' in p.stdout and 'rerun_dropped' not in r and 'unchanged_dropped' not in r,'unchanged redo output/row changed')
  else:want(lines[-1].startswith('shipcraft: next step') or 'GREEN' in lines[-1],'GREEN guidance no longer last')
 if mode in ('tree-error','tree-status','tree-signal'):
  notices=[s for s in p.stdout.splitlines() if s.startswith(base_error)]
  want(len(notices)==1,'missing base-tree failure notice')
  if notices:
   want(('fatal: lookup81 failed' in notices[0] and 'second line81' not in notices[0]) if mode=='tree-error' else ('73' in notices[0] if mode=='tree-status' else ('15' in notices[0] or 'SIGTERM' in notices[0])),'wrong tree error: '+notices[0])
 if mode.startswith('tree-') and mode!='tree-unused':
  want(len(treecalls)==1,'base paths must be read in one git call: '+repr(treecalls))
  if treecalls:
   a=treecalls[0];want(a[:5]==['ls-tree','-r','-z','--name-only',base] and a[5:]==['--',old],'exact merge-base/path protocol: '+repr(a))
 if mode=='tree-unused':want(not treecalls,'unnecessary base-tree lookup without candidate files')
 if mode in ('second-suite','main') and lang=='python':want([e['suite'] for e in entries]==['old','own','own'],'excluded-only suite reran: '+repr(entries))
 if mode=='second-cases':
  reruns=[e for e in entries if e['cases'] is not None]
  want(len(reruns)==1 and len(reruns[0]['cases'])==1 and 'fresh81' in reruns[0]['cases'][0],'second-run list includes excluded failure: '+repr(entries))
 if mode=='flaky-order':
  want(r.get('rerun_dropped')==1,'confirmation no longer drops flaky case')
  i=p.stdout.find('shipcraft: not locked, passed on a second run:');j=p.stdout.find(prefix)
  want(0<=i<j,'confirmation/exclusion notices out of order')
 if mode in ('redo-exempt','redo-same-file') and d:
  git('add','-A');q=run('git','commit','-qm','test: redo exemption81',ok=False)
  want(q.returncode==0,'hook rejected the same-file/exempt redo commit')
 if mode in ('edit-hook','delete-hook','edit-ci','delete-ci','close-ci') and d:
  # Exercise the actual installed commit hook and CI, retaining all protected bytes.
  git('add','-A');run(binary,'check');commit('test: RED81')
  redhead=git('rev-parse','HEAD');saved=ls[0].read_bytes()
  write('ownvalue81','green')
  if mode!='close-ci':
   if mode.startswith('delete'):Path(old).unlink();code='locked-file-deleted'
   else:
    with Path(old).open('a') as f:f.write('\n# forbidden repair81\n')
    code='test-changed'
   git('add','-A')
   if mode.endswith('hook'):
    q=run('git','commit','-qm','invalid GREEN81',ok=False);layer='hook'
   else:
    # A deliberately invalid historical commit is built with Git plumbing, leaving
    # installed hooks untouched; CI must reject it on the protected test bytes.
    tree=git('write-tree');oid=git('commit-tree',tree,'-p',redhead,'-m','invalid GREEN81');git('reset','--hard',oid)
    q=run(binary,'ci','--base',redhead,ok=False);layer='ci'
   want(q.returncode!=0,'protected file accepted');want(rows()[-1].get('layer')==layer and rows()[-1].get('code')==code,'wrong protection refusal: '+repr(rows()[-1]))
   want(ls[0].read_bytes()==saved,'refusal rewrote lock')
  else:
   beforegreen=len(rows());git('add','-A');commit('feat: own GREEN81');run(binary,'close')
   want([r['layer'] for r in rows()[beforegreen:]]==['hook','close'],'GREEN must append hook plus close rows only')
   want(git('log','-1','--format=%s')=='chore(shipcraft): close lock '+ls[0].stem,'missing post-commit child commit')
   want(json.loads(ls[0].read_text())['state']=='closed','excluded failure blocks close')
   q=run(binary,'ci','--base',base,ok=False)
   want(q.returncode==1 and rows()[-1].get('code')=='suite-red','CI did not catch excluded failure: '+repr(rows()[-1]))
assert not errors,'\n'.join(errors)
PY81
  pass
}
