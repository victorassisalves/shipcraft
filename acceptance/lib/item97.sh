# Item 97: public commands, real pytest/Vitest reports; no implementation reads.
item97_langs() { echo core node; }
item97_cases() {
  local c
  if [ "${l:-}" = node ]; then
    for c in control-group group group-mixed; do echo "v1-97.$c"; done
  else
    for c in control-report control-retry control-pr-summary control-pr-status main unnamed two-suites prefix-order cap50 cap51 retry-fail-pass retry-pass-error failure-error error-only zero-exit pr pr-summary-fails pr-status-fails pass no-report later-no-report error open-lock build-fails check-fails log-fails timeout; do echo "v1-97.$c"; done
  fi
}
item97_case() {
  EXPECT="item 97: ${CASE#v1-97.}"
  v1_start codex
  if [ "$LP" = node ]; then
    setup_init
  else
    CFGS='execution|review|"local"'
    pr_main
  fi
  must_accept 'item 97 run-log contract' cmd "$PY" - "${CASE#v1-97.}" "$(command -v shipcraft)" "$CB" "$ST" "$LP" <<'PY97'
import copy,json,os,re,shlex,subprocess,sys,xml.etree.ElementTree as ET
from pathlib import Path
case,binary,cb,st,lang=sys.argv[1:]; binary=str(Path(binary).resolve()); cb=Path(cb); st=Path(st)
def write(path,text):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
def run(*args):
 p=subprocess.run(args,capture_output=True,text=True,timeout=120)
 print('$',shlex.join(args),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 return p
def git(*args):
 p=run('git',*args);assert p.returncode==0,(args,p.stdout,p.stderr);return p.stdout.strip()
def snapshot(message):
 # Plumbing constructs intentionally failing history, leaving installed hooks alone.
 git('add','-A');tree=git('write-tree');oid=git('commit-tree',tree,'-p','HEAD','-m',message);git('reset','--hard',oid)
def rows():
 p=Path('.git/shipcraft/runs.jsonl')
 return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
trace=cb/'trace97.jsonl';os.environ['TRACE97']=str(trace);os.environ['MODE97']=case
write('adapter97.py', '''import copy,json,os,subprocess,sys,time
from pathlib import Path
import xml.etree.ElementTree as ET
suite,folder,report,lang=sys.argv[1:];mode=os.environ['MODE97']
with open(os.environ['TRACE97'],'a') as f:f.write(json.dumps(dict(suite=suite,report=report))+'\\n')
print('stdout97:'+suite,flush=True);print('stderr97:'+suite,file=sys.stderr,flush=True)
if mode=='timeout':time.sleep(5)
if mode=='no-report' or (mode=='later-no-report' and suite=='zeta'):sys.exit(19)
if lang=='node':cmd=['node','node_modules/vitest/vitest.mjs','run','--maxWorkers=1','--reporter=junit','--outputFile='+report,folder]
else:cmd=['pytest','-q','-p','no:cacheprovider','-o','disable_test_id_escaping_and_forfeit_all_rights_to_community_support=True','--junitxml='+report,folder]
p=subprocess.run(cmd)
if mode in ('retry-fail-pass','retry-pass-error','control-retry'):
 tree=ET.parse(report);parent=next(tree.iter('testsuite'));original=next(tree.iter('testcase'));retry=copy.deepcopy(original)
 if mode in ('retry-fail-pass','control-retry'):
  for child in list(retry):retry.remove(child)
  parent.append(retry)
 else:
  for child in list(original):original.remove(child)
  for child in list(retry):retry.remove(child)
  ET.SubElement(retry,'error',message='retry error97').text='retry error97';parent.append(retry)
 tree.write(report,encoding='utf-8',xml_declaration=True)
Path(os.environ['TRACE97']+'.'+suite+'.xml').write_bytes(Path(report).read_bytes())
sys.exit(0 if mode=='zero-exit' else p.returncode)
''')
anchor='from pathlib import Path\nimport pytest\ndef test_value():\n    assert Path("value97").read_text()=="green"\ndef test_pass97():\n    assert True\n@pytest.mark.skip(reason="skip97")\ndef test_skip97():\n    assert False\n'
write('pkg97/tests/test_value.py',anchor)
suites=[('api','pkg97/tests')];extra_config='';execution='ci = "local"\nreview = "local"\n'
if case=='main':pass
elif case=='unnamed':suites=[(None,'pkg97/tests')]
elif case=='two-suites':suites=[('zeta','pkg97/tests'),('api','pkg97/tests')]
elif case=='prefix-order':
 suites=[('zeta','pkg97/tests'),(None,'pkg97/tests')]
 write('pkg97/tests/test_bytes.py','import pytest\n@pytest.mark.parametrize("x",["z", "é & <space>", "a space"])\ndef test_bytes(x):\n    assert False\n')
elif case=='cap50':
 write('pkg97/tests/test_value.py','import pytest\n@pytest.mark.parametrize("n",range(49,-1,-1),ids=["%02d"%n for n in range(49,-1,-1)])\ndef test_value(n):\n    assert False\n')
elif case=='cap51':
 write('pkg97/tests/test_value.py','import pytest\n@pytest.mark.parametrize("n",range(50,-1,-1),ids=["%02d"%n for n in range(50,-1,-1)])\ndef test_value(n):\n    assert False\n')
elif case=='failure-error':
 suites=[('zeta','pkg97/tests'),('api','errors97')]
 write('errors97/test_setup.py','import pytest\n@pytest.fixture\ndef broken():\n    raise RuntimeError("setup97")\ndef test_error97(broken):\n    pass\n')
elif case=='error-only':
 write('pkg97/tests/test_value.py','import pytest\n@pytest.fixture\ndef broken():\n    raise RuntimeError("setup97")\ndef test_value(broken):\n    pass\n')
elif case=='later-no-report':suites=[('api','pkg97/tests'),('zeta','pkg97/tests')]
elif case=='build-fails':extra_config='\n[build]\ncommand = "exit 17"\n'
elif case=='check-fails':extra_config='\ncheck = "exit 18"\n'
elif case=='timeout':execution+='ci_timeout = 1\n'
elif case in ('control-group','group','group-mixed'):
 suites=[('api','src/group97.spec.ts')]
 write('src/group97.spec.ts',"import {describe,beforeAll,it,expect} from 'vitest';\ndescribe('group97',()=>{beforeAll(()=>{throw new Error('setup97')});it('one97',()=>expect(true).toBe(true));describe('inner97',()=>it('two97',()=>expect(true).toBe(true)));});\nit('pass97',()=>expect(true).toBe(true));\n"+ ("it('failure97',()=>expect(1).toBe(2));\n" if case=='group-mixed' else ''))
elif case in ('control-report','control-retry','control-pr-summary','control-pr-status','retry-fail-pass','retry-pass-error','zero-exit','pr','pr-summary-fails','pr-status-fails','pass','no-report','error','open-lock','log-fails'):pass
else:raise AssertionError('unrouted fixture '+case)
config='shipcraft_min = "0.0"\nlang = '+json.dumps(lang)+'\nrunner = '+json.dumps('vitest' if lang=='node' else 'pytest')+'\n[execution]\n'+execution
for name,folder in suites:
 command=shlex.join([sys.executable,'adapter97.py',name or 'unnamed',folder,'{junit}',lang])
 config+='\n[[suite]]\n'+('name = '+json.dumps(name)+'\n' if name else '')+'root = "."\ncommand = '+json.dumps(command)+'\nglobs = '+json.dumps(['src/**'] if lang=='node' else ['pkg97/tests/**','errors97/**'])+'\n'
config+=extra_config
write('.shipcraft.toml',config);write('value97','green');snapshot('test: item97 base fixture')
if lang=='node':
 git('init','-q','--bare',str(cb/'origin.git'));git('remote','add','origin',str(cb/'origin.git'))
git('push','-q','origin','main');base=git('rev-parse','HEAD');git('checkout','-qb','feature/item97')
write('value97','green' if case=='pass' else 'red');snapshot('test: item97 HEAD fixture');head=git('rev-parse','HEAD')
if case=='open-lock':
 q=run(binary,'red');assert q.returncode==0,(q.stdout,q.stderr);snapshot('test: genuine open cycle97')
 write('value97','green');snapshot('test: passing product with lock still open97');head=git('rev-parse','HEAD');trace.unlink()
if case=='log-fails':
 log=Path('.git/shipcraft/runs.jsonl');log.unlink(missing_ok=True);log.mkdir()
if case in ('pr-summary-fails','pr-status-fails','control-pr-summary','control-pr-status'):
 real=cb/'gh-real97';(cb/'gh').rename(real)
 write(cb/'gh','#!'+sys.executable+'\n'+'''import os,sys
from pathlib import Path
a=sys.argv[1:];mode=os.environ['MODE97']
summary=a[:2]==['pr','comment'] or (a[:1]==['api'] and any('/issues/' in x and x.endswith('/comments') for x in a) and any(x in ('-f','-F','--input') for x in a))
status=a[:1]==['api'] and any('/statuses/' in x for x in a) and 'state=failure' in a
env=dict(os.environ)
if (mode in ('pr-summary-fails','control-pr-summary') and summary) or (mode in ('pr-status-fails','control-pr-status') and status):
 Path(os.environ['TRACE97']+'.publication').write_text('summary' if summary else 'status');env['SHIPCRAFT_STUB_FAIL']='1'
real=Path(__file__).with_name('gh-real97');os.execve(str(real),[str(real),*a],env)
''');(cb/'gh').chmod(0o755)
before=rows()
if case in ('pr','pr-summary-fails','pr-status-fails','control-pr-summary','control-pr-status','timeout'):
 git('rev-parse','HEAD');(st/'sha').write_text(head+'\n')
 write(cb/'body97.md','Failing case measurements97\n')
 p=run(binary,'pr','--title','Item97','--body',str(cb/'body97.md'))
else:p=run(binary,'ci','--base','missing-ref97' if case=='error' else base)
new=rows()[len(before):];ci=[r for r in new if r['layer']=='ci']
if case=='log-fails':
 assert p.returncode==1 and 'shipcraft refused: the suite fails at HEAD and there is no open cycle\n' in p.stderr,(p.stdout,p.stderr)
 assert not new and Path('.git/shipcraft/runs.jsonl').is_dir(),new
else:
 assert len(ci)==1,new
 r=ci[0]
 assert r['commit']==head and r['branch']=='feature/item97',r
 assert r['secs']>=0 and type(r['at']) is int and r.get('lock') in (None,''),r
 # Other layers retain their old row shapes, including PR errors after CI refused.
 assert all('failed' not in x and 'failed_count' not in x for x in new if x['layer']!='ci'),new
entries=[json.loads(s) for s in trace.read_text().splitlines()] if trace.exists() else []
if case in ('build-fails','error'):assert not entries,entries
elif case=='check-fails':assert len(entries)==0,entries
else:
 assert len(entries)==len(suites),entries
 assert [e['suite'] for e in entries]==[name or 'unnamed' for name,_ in suites],entries
 for e in entries:
  assert re.fullmatch(r'shipcraft-junit-\d+-\d+\.xml',Path(e['report']).name),e
  assert not Path(e['report']).exists(),('report not removed',e)
  assert 'stdout97:'+e['suite'] in p.stderr and 'stderr97:'+e['suite'] in p.stderr,p.stderr
  assert 'stdout97:' not in p.stdout and 'stderr97:' not in p.stdout,p.stdout
if case in ('pr','pr-summary-fails','pr-status-fails','control-pr-summary','control-pr-status','timeout'):
 prs=[r for r in new if r['layer']=='pr'];assert len(prs)==1,new
 assert not [r for r in new if r['layer']=='review'],new
 assert git('ls-remote','origin','refs/heads/feature/item97').split()[0]==head
 assert len(json.loads((st/'prs.json').read_text()))==1
 if case in ('pr-summary-fails','pr-status-fails','control-pr-summary','control-pr-status'):
  assert p.returncode==2 and prs[0]['result']=='error' and Path(str(trace)+'.publication').is_file(),(p,new)
 elif case=='timeout':assert p.returncode==1 and r['result']=='error' and r['code']=='timed-out',(p,new)
 else:assert p.returncode==1 and prs[0]['code']=='ci-refused',new
# Each case sets its own expected ids; helpers contain no expected field values.
if case=='main':expected=['api:pkg97.tests.test_value::test_value'];count=1
elif case=='unnamed':expected=['pkg97.tests.test_value::test_value'];count=1
elif case=='two-suites':expected=['api:pkg97.tests.test_value::test_value','zeta:pkg97.tests.test_value::test_value'];count=2
elif case=='prefix-order':
 expected=sorted([prefix+ident for prefix in ('','zeta:') for ident in ('pkg97.tests.test_value::test_value','pkg97.tests.test_bytes::test_bytes[z]','pkg97.tests.test_bytes::test_bytes[é & <space>]','pkg97.tests.test_bytes::test_bytes[a space]')],key=lambda s:s.encode());count=8
elif case=='cap50':expected=['api:pkg97.tests.test_value::test_value[%02d]'%n for n in range(50)];count=50
elif case=='cap51':expected=['api:pkg97.tests.test_value::test_value[%02d]'%n for n in range(50)];count=51
elif case=='retry-fail-pass':expected=['api:pkg97.tests.test_value::test_value'];count=1
elif case=='retry-pass-error':expected=['api:pkg97.tests.test_value::test_value'];count=1
elif case=='failure-error':expected=['api:errors97.test_setup::test_error97','zeta:pkg97.tests.test_value::test_value'];count=2
elif case=='error-only':expected=['api:pkg97.tests.test_value::test_value'];count=1
elif case=='zero-exit':expected=['api:pkg97.tests.test_value::test_value'];count=1
elif case=='pr':expected=['api:pkg97.tests.test_value::test_value'];count=1
elif case=='pr-summary-fails':expected=['api:pkg97.tests.test_value::test_value'];count=1
elif case=='pr-status-fails':expected=['api:pkg97.tests.test_value::test_value'];count=1
elif case=='group':expected=['api:src/group97.spec.ts::group97'];count=1
elif case=='group-mixed':expected=['api:src/group97.spec.ts::failure97','api:src/group97.spec.ts::group97'];count=2
elif case=='control-pr-summary':
 assert Path(str(trace)+'.publication').read_text()=='summary' and r['code']=='suite-red' and prs[0]['result']=='error',new
elif case=='control-pr-status':
 assert Path(str(trace)+'.publication').read_text()=='status' and r['code']=='suite-red' and prs[0]['result']=='error',new
elif case=='control-report':
 nodes=list(ET.parse(str(trace)+'.api.xml').iter('testcase'))
 assert [(n.get('name'),[c.tag for c in n if c.tag in ('failure','error','skipped')]) for n in nodes]==[('test_value',['failure']),('test_pass97',[]),('test_skip97',['skipped'])],[(n.attrib,[c.tag for c in n]) for n in nodes]
 assert p.returncode==1 and r['code']=='suite-red' and r['reason']=='the suite fails at HEAD and there is no open cycle',r
elif case=='control-retry':
 nodes=list(ET.parse(str(trace)+'.api.xml').iter('testcase'))
 assert [n.get('name') for n in nodes]==['test_value','test_pass97','test_skip97','test_value'],[n.attrib for n in nodes]
 assert nodes[0].find('failure') is not None and nodes[-1].find('failure') is None and r['code']=='suite-red',r
elif case=='control-group':
 nodes=list(ET.parse(str(trace)+'.api.xml').iter('testcase'))
 assert any(n.get('name')=='group97' and n.find('failure') is not None for n in nodes),[n.attrib for n in nodes]
 assert len([n for n in nodes if n.find('skipped') is not None])==2 and r['code']=='suite-red',(r,[n.attrib for n in nodes])
elif case=='pass':assert p.returncode==0 and r['result']=='passed' and not r['code'] and 'failed' not in r and 'failed_count' not in r,r
elif case=='no-report':assert p.returncode==1 and r['code']=='no-report' and 'failed' not in r and 'failed_count' not in r,r
elif case=='later-no-report':assert p.returncode==1 and r['code']=='no-report' and 'failed' not in r and 'failed_count' not in r,r
elif case=='error':assert p.returncode==2 and r['result']=='error' and 'failed' not in r and 'failed_count' not in r,r
elif case=='open-lock':assert p.returncode==1 and r['code']=='lock-not-closed' and 'failed' not in r and 'failed_count' not in r,r
elif case=='build-fails':assert p.returncode==1 and r['code']=='build-failed' and 'failed' not in r and 'failed_count' not in r,r
elif case=='check-fails':assert p.returncode==1 and r['code']=='no-report' and 'failed' not in r and 'failed_count' not in r,r
elif case=='timeout':assert r['result']=='error' and r['code']=='timed-out' and 'failed' not in r and 'failed_count' not in r,r
elif case=='log-fails':pass
else:raise AssertionError('unrouted assertions '+case)
if case in ('main','unnamed','two-suites','prefix-order','cap50','cap51','retry-fail-pass','retry-pass-error','failure-error','error-only','zero-exit','pr','pr-summary-fails','pr-status-fails','group','group-mixed'):
 assert r['code']=='suite-red' and r['result']=='refused',r
 if case not in ('pr','pr-summary-fails','pr-status-fails'):
  assert p.returncode==1,p
  refusal='shipcraft refused: the suite fails at HEAD and there is no open cycle\nWhy: outside an open cycle the suite stays green; a new failing test starts with RED\nNext: fix the code, or open the new test cycle with `shipcraft red`\n'
  assert p.stderr.endswith(refusal) and 'suite-red' not in p.stdout+p.stderr,(p.stdout,p.stderr)
 assert r.get('failed')==expected,r
 assert type(r.get('failed_count')) is int and r['failed_count']==count,r
 assert r['reason']=='the suite fails at HEAD and there is no open cycle',r
 assert r['docs_only'] is False and r['suite_in_checks'] is False and r.get('locks',[])==[],r
PY97
  pass
}
