# Item 98: public commands, real runner reports, disposable Git repositories only.
item98_langs() { echo python node go; }
item98_cases() {
  echo v1-98.fixture-control; echo v1-98.main
  [ "${l:-python}" = python ] || return 0
  local c
  for c in escaped-control hook-escaped full-fallback second-run all no-base unmapped suite-local red-log-fails red-write-fails red-refused redo redo-head redo4 redo-unchanged redo-write-fails hook-green hook-break hook-error hook-skipped hook-absent hook-no-report hook-precedence hook-many opening redo-commit list-write-fails hook-log-fails read-outside read-failing read-repeat read-order read-missing read-null read-nonstring legacy-controls legacy-judge seal-tamper; do echo "v1-98.$c"; done
}
item98_case() {
  EXPECT="item 98: ${CASE#v1-98.}"; v1_start
  [ "$LP" != go ] || { PATH="$GOBIN:$PATH"; export PATH; }
  must_accept 'controls in real reports and hook selection' cmd "$PY" - "${CASE#v1-98.}" "$LP" "$(command -v shipcraft)" <<'PY98'
import hashlib,json,os,re,shlex,shutil,subprocess,sys
from pathlib import Path
mode,lang,binary=sys.argv[1:];binary=str(Path(binary).resolve())
parent=Path.cwd();root=parent/'project98';root.mkdir();os.chdir(root)
errors=[]
def want(value,message):
 if not value:errors.append(message)
def write(path,text):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
def run(*args,ok=True):
 p=subprocess.run(list(map(str,args)),capture_output=True,text=True,timeout=120)
 print('$',shlex.join(list(map(str,args))),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 if ok:assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr)
 return p
def git(*args):return run('git',*args).stdout.strip()
def commit(message):git('add','-A');return run('git','commit','-qm',message)
def snapshot_commit(message):
 # Git plumbing creates documented reader fixtures, without changing hooks/settings.
 git('add','-A');tree=git('write-tree');oid=git('commit-tree',tree,'-p','HEAD','-m',message);git('update-ref','HEAD',oid);return oid
def rows():
 p=Path('.git/shipcraft/runs.jsonl');return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def locks():return sorted(Path('.shipcraft/locks').glob('*.json'))
def entries():return [json.loads(s) for s in record.read_text().splitlines()] if record.exists() else []
def canonical(d):
 c={k:d[k] for k in ('format','state','files','cases','failing_at_red')};c['files']=dict(sorted(c['files'].items()))
 if d['format']==5 and 'controls' in d:c['controls']=d['controls']
 if d['format'] in (4,5):c.update((k,d[k]) for k in ('kind','reported_at','fixes_release'))
 c['seal']='';return c
def save(d):
 d['seal']=hashlib.sha256(json.dumps(canonical(d),ensure_ascii=False,separators=(',',':')).encode()).hexdigest();lock.write_text(json.dumps(d,ensure_ascii=False)+'\n')
def refusal(p,code,layer='hook'):
 want(p.returncode==1,'expected refusal exit: '+str(p.returncode))
 lines=(p.stdout+p.stderr).strip().splitlines()[-3:]
 want(len(lines)==3 and all(s.startswith(t) for s,t in zip(lines,('shipcraft refused:','Why:','Next:'))),'three-line refusal: '+repr(lines))
 rs=[r for r in rows() if r['layer']==layer];want(bool(rs) and rs[-1]['code']==code,'expected '+code+' row: '+repr(rs[-1:]));return lines
def notice(p,count,redo=False):
 line=f'shipcraft: controls: {count} passing case(s) of the changed test files; the hook runs them too'
 lines=p.stdout.splitlines();want(lines.count(line)==1,'missing exact controls count: '+line)
 marker='shipcraft: RED '+('redone at' if redo else 'locked at')
 i=next((i for i,s in enumerate(lines) if s.startswith(marker)),-1)
 want(i>0 and lines[i-1]==line,'controls line immediately before lock announcement')
 want(lines and lines[-1].startswith('shipcraft: next: the GREEN'),'GREEN guidance last')
 want('shipcraft: controls:' not in p.stderr,'controls line on stderr')
def shape(d,controls):
 want(list(d)==['format','state','files','cases','failing_at_red','controls','kind','reported_at','fixes_release','seal'],'format 5 key order: '+repr(list(d)))
 want(d['format']==5 and d.get('controls')==controls,'format/controls: '+repr(d))
 want(d['seal']==hashlib.sha256(json.dumps(canonical(d),ensure_ascii=False,separators=(',',':')).encode()).hexdigest(),'seal covers controls in fixed order')

git('init','-q','-b','main');git('config','user.name','RED98');git('config','user.email','red98@example.invalid')
write('.gitignore','__pycache__/\n.pytest_cache/\nnode_modules/\n')
if lang=='node':(root/'node_modules').symlink_to(parent/'node_modules',target_is_directory=True)
if lang=='go':write('go.mod','module example.invalid/item98\n\ngo 1.21\n')
record=parent/'observed98.jsonl';os.environ['OBS98']=str(record);os.environ['MODE98']=mode
adapter=root/'adapter98.py'
write(adapter,'''import json,os,re,subprocess,sys
from pathlib import Path
import xml.etree.ElementTree as ET
suite,lang,junit=sys.argv[1:]
def read(key):
 p=os.environ.get(key)
 return Path(p).read_bytes().decode().split('\\0')[:-1] if p else None
cases=read('SHIPCRAFT_CASES');files=read('SHIPCRAFT_FILES')
with open(os.environ['OBS98'],'a') as f:f.write(json.dumps(dict(suite=suite,cases=cases,files=files,junit=junit,variant='real-'+lang+'-98'))+'\\n')
if lang=='python':
 paths=[str(Path(p).resolve()) for p in files or [] if Path(p).name.startswith('test_') and p.endswith('.py')]
 if cases:
  paths=[]
  for c in cases:
   c=c.split(':tests.',1)[-1] if ':tests.' in c else c
   if not c.startswith('tests.'):c='tests.'+c
   cls,name=c.split('::',1)
   path=cls.replace('.','/')+'.py'
   paths.append(path+'::'+name)
 cmd=['pytest','-q','-p','no:cacheprovider','--junitxml='+junit,*(paths or ['tests'])]
elif lang=='node':
 cmd=['node',str(Path('../node_modules/vitest/vitest.mjs').resolve()),'run','--maxWorkers=1','--reporter=junit','--outputFile='+junit]
 if files:cmd.extend(files)
 if cases:cmd+=['-t','^(?:'+'|'.join(re.escape(c.split('::')[-1]) for c in cases)+')$']
else:
 cmd=['gotestsum','--junitfile',junit,'--','-count=1']
 if cases:cmd+=['-run','^(?:'+'|'.join(re.escape(c.split('::')[-1]) for c in cases)+')$']
 cmd+=['./...']
if os.environ['MODE98'] in ('escaped-control','hook-escaped'):cmd+=['-o','disable_test_id_escaping_and_forfeit_all_rights_to_community_support=True']
p=subprocess.run(cmd)
mode=os.environ['MODE98'];phase=os.environ.get('PHASE98','red')
if lang=='python' and mode in ('unmapped','suite-local') and suite=='own':
 t=ET.parse(junit)
 for c in t.iter('testcase'):
  if c.get('name')=='test_unmapped98':c.set('classname','unknown98');c.set('name','unmapped98');c.attrib.pop('file',None)
 t.write(junit)
if phase=='hook' and mode=='hook-absent':
 t=ET.parse(junit)
 for s in t.iter('testsuite'):
  for c in list(s):
   if c.tag=='testcase' and c.get('name')=='test_a98':s.remove(c)
 t.write(junit)
if phase=='hook' and mode=='hook-no-report':Path(junit).unlink();sys.exit(1)
sys.exit(p.returncode)
''')
config='shipcraft_min = "0.0"\nlang = '+json.dumps(lang)+'\nrunner = '+json.dumps({'python':'pytest','node':'vitest','go':'gotestsum'}[lang])+'\n[execution]\nci = "local"\nreview = "off"\n'
suites=['own','other'] if mode=='suite-local' else ['own']
for suite in suites:
 Path(suite,'tests').mkdir(parents=True,exist_ok=True)
 command=shlex.join([sys.executable,str(adapter),suite,lang,'{junit}'])+(' # gotestsum' if lang=='go' else '')
 config+='\n[[suite]]\nname = '+json.dumps(suite)+'\nroot = '+json.dumps(suite)+'\nfilter = "command"\ncommand = '+json.dumps(command)+'\nglobs = '+json.dumps(['**/*_test.go'] if lang=='go' else ['tests/**'])+'\n'
write('.shipcraft.toml',config)
# Product state, rather than test bytes, changes the outcomes after RED.
write('value98','red');write('control98','green')
if lang=='python':
 path='own/tests/test_pair98.py'
 pair='''from pathlib import Path
import os,pytest
def test_target98():
    assert Path('../value98').read_text()=='green'
def test_z98():
    assert Path('../control98').read_text()!='red'
@pytest.fixture
def guard98():
    if Path('../control98').read_text()=='error':raise RuntimeError('control98 setup')
def test_a98(guard98):
    state=Path('../control98').read_text()
    if state=='skip':pytest.skip('control98')
    if state=='error':raise RuntimeError('control98')
    assert state=='green'
'''
else:
 if lang=='node':
  path='own/tests/pair98.test.ts'
  # The same reader must see BOM, CR, CRLF, Unicode separators, comments and quoted names.
  pair='\ufeffimport {it,expect} from "vitest";\r\nimport {readFileSync} from "node:fs";\rit("target98",()=>expect(readFileSync("../value98","utf8")).toBe("green"));\u2028// reader boundary\u2029it(\'z98\',()=>expect(true).toBe(true)); /* inline */\r\nit("a98",()=>expect(true).toBe(true));\n'
 else:
  path='own/pair98_test.go';pair='package item98\nimport("testing";"os")\nfunc TestTarget98(t *testing.T){v,_:=os.ReadFile("../value98");if string(v)!="green"{t.Fatal("red98")}}\nfunc TestZ98(t *testing.T){}\nfunc TestA98(t *testing.T){}\n'
# A pre-existing passing test must not enter controls on a full-run fallback.
if lang=='python':write('own/tests/test_old98.py','def test_old98():\n    assert True\n')
write('requirements.txt','pytest\n')
commit('chore: fixture base98');run(binary,'init','--lang',lang);commit('chore: installation98')
base=git('rev-parse','HEAD');git('update-ref','refs/remotes/origin/main',base);git('symbolic-ref','refs/remotes/origin/HEAD','refs/remotes/origin/main');git('checkout','-qb','feature/item98')
write(path,pair)
if mode=='second-run':
 with Path(path).open('a') as f:f.write('def test_flaky98():\n    marker=Path(os.environ["OBS98"]+".flaky")\n    seen=marker.exists()\n    marker.touch()\n    assert seen\n')
if mode in ('unmapped','suite-local'):
 with Path(path).open('a') as f:f.write('def test_unmapped98():\n    assert True\n')
if mode=='suite-local':write('other/tests/test_other98.py','def test_other98():\n    assert True\n')
if mode in ('escaped-control','hook-escaped'):
 with Path(path).open('a') as f:f.write('@pytest.mark.parametrize("n",[1],ids=["line\\nnext\\tend"])\ndef test_00escape98(n):\n    assert Path("../control98").read_text()=="green"\n@pytest.mark.parametrize("n",range(5))\ndef test_01many98(n):\n    assert Path("../control98").read_text()=="green"\n')
if mode=='hook-many':
 with Path(path).open('a') as f:
  for n in ('b98','c98','d98','e98'):f.write('def test_'+n+'():\n    assert True\n')
if mode=='full-fallback':write('.shipcraft.toml',config+'\n# full fallback98\n')
args=[]
if mode=='all':args=['--all']
if mode=='no-base':args=['--base','missing98']
if mode=='red-refused':write('value98','green')
if mode=='red-log-fails':
 log=Path('.git/shipcraft/runs.jsonl');log.unlink(missing_ok=True);log.mkdir()
if mode=='red-write-fails':Path('.shipcraft/locks').chmod(0o555)
record.unlink(missing_ok=True)
try:p=run(binary,'red',*args,ok=False)
finally:
 if mode=='red-write-fails':Path('.shipcraft/locks').chmod(0o755)
if mode=='red-refused':
 refusal(p,'red-already-passes','red');want(not locks(),'refusal wrote lock');want('shipcraft: controls:' not in p.stdout,'refusal announced controls')
 assert not errors,'\n'.join(errors);sys.exit()
if mode=='red-write-fails':
 want(p.returncode!=0 and not locks(),'write failure created lock');want('shipcraft: controls:' not in p.stdout,'write failure announced controls');want(rows()[-1]['result']=='error','write error row')
 assert not errors,'\n'.join(errors);sys.exit()
assert p.returncode==0 and len(locks())==1,('fixture RED failed',p.stdout,p.stderr)
lock=locks()[0];d=json.loads(lock.read_text());initial=d.copy();redbytes=lock.read_bytes()
if lang=='python':controls=['own:tests.test_pair98::test_a98','own:tests.test_pair98::test_z98'];failure='own:tests.test_pair98::test_target98'
elif lang=='node':controls=['own:'+path.split('/',1)[1]+'::a98','own:'+path.split('/',1)[1]+'::z98'];failure='own:'+path.split('/',1)[1]+'::target98'
else:controls=['own:example.invalid/item98/own::TestA98','own:example.invalid/item98/own::TestZ98'];failure='own:example.invalid/item98/own::TestTarget98'
# Real report identities are also checked in each native fixture control below.
if mode=='fixture-control':
 assert d['cases']==sorted(controls+[failure]),('native report identities',d)
 assert d['failing_at_red']==[failure],d
 assert len(entries())==2 and all(e['variant']=='real-'+lang+'-98' for e in entries()),entries()
 assert entries()[1]['cases']==[failure.split(':',1)[1]],entries()
 assert not Path(entries()[0]['junit']).exists(),'temporary report not removed'
 sys.exit()
if mode=='main':
 shape(d,controls);notice(p,2)
 want(set(rows()[-1])=={'at','branch','code','commit','fallback','layer','lock','result','secs','selected_files','selection','rerun_dropped','kind','reported_at','fixes_release'},'red row gained/lost fields')
elif mode=='escaped-control':
 assert any('test_00escape98[line\nnext\tend]' in c for c in d['cases']),d
 assert len(d['cases'])==9 and d['failing_at_red']==[failure],d
 assert len(entries())==2 and entries()[1]['cases']==[failure.split(':',1)[1]],entries()
elif mode=='full-fallback':shape(d,controls);notice(p,2);want(any('old98' in c for c in d['cases']),'full report did not include old passing test')
elif mode=='second-run':shape(d,controls);notice(p,2);want(any('flaky98' in c for c in d['cases']) and not any('flaky98' in c for c in d['failing_at_red']),'flaky confirmation boundary');want(p.stdout.index('passed on a second run:')<p.stdout.index('shipcraft: controls:') if 'shipcraft: controls:' in p.stdout else False,'confirmation notice before controls')
elif mode=='all':shape(d,[]);notice(p,0)
elif mode=='no-base':shape(d,[]);notice(p,0)
elif mode=='unmapped':
 want('own:unknown98::unmapped98' in d['cases'],'unmapped report variant absent');shape(d,[]);notice(p,0)
elif mode=='suite-local':
 want('own:unknown98::unmapped98' in d['cases'],'suite-local unmapped variant absent');shape(d,['other:tests.test_other98::test_other98']);notice(p,1)
elif mode=='red-log-fails':shape(d,controls);notice(p,2);want(Path('.git/shipcraft/runs.jsonl').is_dir(),'log blocker lost')
# The remaining arms exercise commands past RED, without an early writer-shape gate.
elif mode in ('redo','redo-head','redo4','redo-unchanged','redo-write-fails','redo-commit'):
 if mode=='redo4':
  d['format']=4;d.pop('controls',None);d.update(kind='fix',reported_at='2026-10-31T00:36-03:00',fixes_release='v2.25.0');save(d);snapshot_commit('test: legacy4 RED98')
 else:commit('test: opening RED98')
 before=lock.read_bytes();stat=lock.stat()
 if mode=='redo-head':git('update-ref','refs/remotes/origin/main','HEAD')
 if mode in ('redo','redo-commit'):
  with Path(path).open('a') as f:f.write('\ndef test_added98():\n    assert True\n')
 if mode=='redo-write-fails':
  with Path(path).open('a') as f:f.write('\n# repaired description98\n')
  lock.parent.chmod(0o555)
 try:q=run(binary,'red','--redo',ok=False)
 finally:
  if mode=='redo-write-fails':lock.parent.chmod(0o755)
 new=json.loads(lock.read_text())
 if mode=='redo':shape(new,sorted(controls+['own:tests.test_pair98::test_added98']));notice(q,3,True)
 elif mode=='redo-head':shape(new,controls);want(q.returncode==0 and lock.read_bytes()==before,'HEAD redo must retain controls byte-identically');want('shipcraft: controls:' not in q.stdout,'unchanged HEAD redo printed controls')
 elif mode=='redo4':shape(new,controls);notice(q,2,True);want(tuple(new[k] for k in ('kind','reported_at','fixes_release'))==('fix','2026-10-31T00:36-03:00','v2.25.0'),'upgrade lost fix metadata')
 elif mode=='redo-unchanged':shape(new,controls);want(lock.read_bytes()==before and lock.stat().st_mtime_ns==stat.st_mtime_ns,'unchanged redo replaced bytes');want('shipcraft: controls:' not in q.stdout and 'RED unchanged:' in q.stdout,'unchanged output')
 elif mode=='redo-write-fails':refusal(q,'redo-write-failed','red');want(lock.read_bytes()==before,'failed redo lost controls/old seal');want('shipcraft: controls:' not in q.stdout,'failed redo announced controls');shape(new,controls)
 elif mode=='redo-commit':
  record.unlink();os.environ['PHASE98']='hook';commit('test: redo98')
  want(len(entries())==1 and entries()[0]['cases']==[failure.split(':',1)[1]],'redo commit ran controls: '+repr(entries()));shape(new,sorted(controls+['own:tests.test_pair98::test_added98']))
elif mode in ('read-outside','read-failing','read-repeat','read-order','read-missing','read-null','read-nonstring','legacy-controls','seal-tamper'):
 d['format']=5;d['controls']=controls
 if mode=='read-outside':d['controls']=['own:tests.test_pair98::test_outside98']
 elif mode=='read-failing':d['controls']=[failure]
 elif mode=='read-repeat':d['controls']=[controls[0],controls[0]]
 elif mode=='read-order':d['controls']=list(reversed(controls))
 elif mode=='read-missing':d.pop('controls')
 elif mode=='read-null':d['controls']=None
 elif mode=='read-nonstring':d['controls']=[7]
 elif mode=='legacy-controls':d['format']=4
 save(d)
 if mode=='seal-tamper':
  d['controls']=[];lock.write_text(json.dumps(d)+'\n')
 snapshot_commit('test: reader fixture98');saved=lock.read_bytes();head=git('rev-parse','HEAD')
 write('product98','changed');git('add','product98');q=run(binary,'check',ok=False);refusal(q,'lock-edited');want(lock.read_bytes()==saved,'hook changed malformed bytes')
 snapshot_commit('feat: later snapshot98');q=run(binary,'ci','--base',head,ok=False);refusal(q,'lock-edited','ci');want(lock.read_bytes()==saved,'CI changed malformed bytes')
 if mode=='legacy-controls':
  for fmt in (2,3):
   d['format']=fmt;d['controls']=None if fmt==2 else []
   for k in ('kind','reported_at','fixes_release'):d.pop(k,None)
   if fmt==2:d['files']={k:v.removeprefix('sha256:') for k,v in d['files'].items()}
   else:d['files']={k:'sha256:'+v.removeprefix('sha256:') for k,v in d['files'].items()}
   save(d);snapshot_commit('test: legacy controls forbidden98');write('product98',str(fmt));git('add','product98');q=run(binary,'check',ok=False);refusal(q,'lock-edited')
elif mode=='legacy-judge':
 # Genuine legacy formats keep today's judgments, close format and redo upgrade.
 for fmt in (2,3,4):
  d=dict(initial);d['format']=fmt;d.pop('controls',None)
  if fmt in (2,3):
   for k in ('kind','reported_at','fixes_release'):d.pop(k,None)
  if fmt==2:d['files']={k:v.removeprefix('sha256:') for k,v in d['files'].items()}
  save(d);snapshot_commit('test: legacy format98')
  if fmt in (2,3):
   q=run(binary,'red','--redo');redone=json.loads(lock.read_text())
   assert redone['format']==3 and 'controls' not in redone and 'shipcraft: controls:' not in q.stdout,(redone,q.stdout)
   save(d);snapshot_commit('test: restore legacy closing fixture98')
  write('value98','green');git('add','value98');q=run(binary,'check');closed=json.loads(lock.read_text())
  assert closed['format']==fmt and closed['state']=='closed' and 'controls' not in closed,closed
  assert {k:v for k,v in closed.items() if k not in ('state','seal')}=={k:v for k,v in d.items() if k not in ('state','seal')},closed
  write('value98','red')
elif mode in ('hook-green','hook-break','hook-error','hook-skipped','hook-absent','hook-no-report','hook-precedence','hook-many','hook-escaped','opening','list-write-fails','hook-log-fails'):
 record.unlink();commit('test: opening RED98');os.environ['PHASE98']='hook'
 opening=entries();want(len(opening)==1 and opening[0]['cases']==[failure.split(':',1)[1]],'opening commit ran controls: '+repr(opening))
 record.unlink(missing_ok=True)
 if mode=='opening':shape(d,controls)
 else:
  write('value98','red' if mode=='hook-precedence' else 'green')
  if mode in ('hook-break','hook-precedence','hook-many','hook-escaped','hook-log-fails'):write('control98','red')
  elif mode=='hook-error':write('control98','error')
  elif mode=='hook-skipped':write('control98','skip')
  if mode=='list-write-fails':
   tmp=Path('.git/shipcraft/tmp');shutil.rmtree(tmp,ignore_errors=True);write(tmp,'blocked98')
  if mode=='hook-log-fails':
   log=Path('.git/shipcraft/runs.jsonl');log.unlink();log.mkdir()
  git('add','value98','control98');beforehead=git('rev-parse','HEAD');beforelock=lock.read_bytes()
  q=run('git','commit','-qm','feat: GREEN98',ok=False)
  if mode=='hook-green':
   want(q.returncode==0,'passing controls refused');want(len(entries())==1,'GREEN hook must run once');want(entries() and entries()[0]['cases']==[c.split(':',1)[1] for c in sorted(controls+[failure])],'hook selection excludes controls: '+repr(entries()))
   closed=json.loads(lock.read_text());want(closed['state']=='closed','passing controls did not close');want({k:v for k,v in closed.items() if k not in ('state','seal')}=={k:v for k,v in d.items() if k not in ('state','seal')},'closing changed controls or format')
  elif mode=='hook-escaped':
   lines=refusal(q,'control-failed')
   want(any('test_00escape98[line\nnext\tend]' in c for c in d['cases']),'fixture lost literal control characters')
   want('test_00escape98[line\\nnext\\tend]' in lines[0] and 'test_01many98[0]' in lines[0] and 'test_01many98[1]' in lines[0] and 'and 5 more' in lines[0],'escaped, byte-sorted three-item shortlist: '+repr(lines))
   want('test_a98' not in lines[0] and 'test_z98' not in lines[0] and lock.read_bytes()==beforelock,'truncated refusal named extra cases or changed lock')
  elif mode=='hook-no-report':refusal(q,'no-report');want(lock.read_bytes()==beforelock,'no-report changed lock')
  elif mode=='list-write-fails':
   want(q.returncode==0 and len(entries())==1,'list fallback must run once');want(entries() and entries()[0]['cases'] is None and entries()[0]['files'] is None,'list fallback exported selection');shape(d,controls)
  else:
   if mode=='hook-log-fails':
    want(q.returncode==1,'append failure accepted broken controls');lines=(q.stdout+q.stderr).strip().splitlines()[-3:];want(len(lines)==3 and lines[0].startswith('shipcraft refused:'),'append failure lost refusal')
   else:lines=refusal(q,'control-failed')
   bad=[controls[0]] if mode in ('hook-error','hook-skipped','hook-absent') else controls
   want(lock.read_bytes()==beforelock and json.loads(lock.read_text())['state']=='open','refusal changed/closed lock')
   want(git('rev-parse','HEAD')==beforehead,'refusal moved HEAD')
   if lines:
    want(str(lock) in lines[0] and all(c in lines[0] for c in bad),'refusal must name lock and only bad controls: '+repr(lines))
    want(failure not in lines[0] and all(c not in lines[0] for c in controls if c not in bad),'refusal named a failure or passing control')
    want(lines[1]=="Why: the GREEN makes the RED's cases pass without breaking the cases beside them that already passed",'control Why')
    want(lines[2]=='Next: fix the code until these cases pass again; if a control looks wrong, stop and tell the RED author','control Next')
   want(len(entries())==1,'refused hook reran suite')
   if mode=='hook-many':want('test_b98' not in lines[0] and 'test_e98' not in lines[0] and lines[0].find('test_a98')<lines[0].find('test_z98'),'only two broken controls among many, byte order')
else:raise AssertionError('unrouted case: '+mode)
assert not errors,'\n'.join(errors)
PY98
  pass
}
