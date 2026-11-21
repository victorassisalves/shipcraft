# Item 149: CI capture, synthetic item139 runner and item141 offline PR harness.
item149_langs() { echo core node go; }
item149_cases() {
  if [ "${l:-core}" = node ]; then echo v1-149.node; return; fi
  if [ "${l:-core}" = go ]; then echo v1-149.go; return; fi
  local c
  for c in repro bytes boundary4096 commands dirty worktree isolation no-command suite-red no-report blocked-parent midwrite ci-pr pr-local github env-values ci-env full red-hook version control-fixture control-pr nonregular truncate late-drop check-failure build-failure row-failure pr-timeout github-pr; do echo "v1-149.$c"; done
}
item149_case() {
  EXPECT="item 149: ${CASE#v1-149.}"; v1_start codex
  must_accept 'CI runner output contract' cmd "$PY" - "${CASE#v1-149.}" "$(command -v shipcraft)" "$CW" "$CB" <<'PY149'
import json,os,re,shlex,shutil,subprocess,sys,time,signal,resource,socket
from pathlib import Path
case,binary,cw,cb=sys.argv[1:];cb=Path(cb).resolve();binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/'repo139 space';root.mkdir();os.chdir(root)
env=dict(os.environ)
for k in subprocess.check_output(['git','rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES','SHIPCRAFT_OUTPUT','GITHUB_ACTIONS','CI']:env.pop(k,None)
def write(path,data):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
def run(*args,extra=None,**kw):
 p=subprocess.run(list(map(str,args)),env=dict(env,**(extra or {})),capture_output=True,timeout=45,**kw)
 print('$',shlex.join(map(str,args)),'exit',p.returncode,'stdout bytes',len(p.stdout),'stderr bytes',len(p.stderr),flush=True)
 (cw/'last.stdout').write_bytes(p.stdout);(cw/'last.stderr').write_bytes(p.stderr)
 return p
def ok(*args):
 p=run(*args);assert p.returncode==0,('fixture command',args,p.stdout,p.stderr);return p

def git(*args):return ok('git',*args).stdout.decode().strip()
def commit(message):git('add','-A');return ok('git','commit','-qm',message)
def locks():return sorted(Path('.shipcraft/locks').glob('*.json'))
def logpath(name='red'):
 p=Path(git('rev-parse','--git-path','shipcraft/output/'+name+'.log'));return p if p.is_absolute() else Path.cwd()/p
def without_lines(data,prefixes):
 # Split only at LF: other byte separators belong to the runner's output.
 return b'\n'.join(line for line in data.split(b'\n') if not line.startswith(prefixes))
def log_output():return without_lines(logpath().read_bytes(),(b'shipcraft: `',))
def screen_output(p):
 # Command announcements contain interpreter, runner and temporary JUnit paths.
 return without_lines(p.stderr,(b'shipcraft: running the suite (',b'shipcraft: running the build (',b'shipcraft: checking the project ('))

def payload(data,err=b'',mode='suite'):
 write(cw/(mode+'.out'),data);write(cw/(mode+'.err'),err)
runner=cw/'runner139.py'
write(runner,'''import json,os,sys,time,subprocess
from pathlib import Path
import xml.etree.ElementTree as E
home=Path(__file__).parent
mode=sys.argv[1]
a=(home/(mode+'.out')).read_bytes() if (home/(mode+'.out')).exists() else b''
b=(home/(mode+'.err')).read_bytes() if (home/(mode+'.err')).exists() else b''
os.write(1,a);os.write(2,b)
with (home/'trace139').open('a') as f:f.write(json.dumps(dict(cwd=os.getcwd(),mode=mode,files=os.environ.get('SHIPCRAFT_FILES'),cases=os.environ.get('SHIPCRAFT_CASES'),argv=sys.argv[2:]))+'\\n')
if mode!='suite':sys.exit(37 if (home/(mode+'.fail')).exists() else 0)
if (home/'late139').exists():
 subprocess.Popen([sys.executable,'-c',"import os,time;time.sleep(3);os.write(1,b'LATE139\\\\n')"])
if (home/'no-report').exists():sys.exit(38)
passed=Path('value139').read_text()=='green'
t=E.Element('testsuite',tests='1',failures=str(int(not passed)))
c=E.SubElement(t,'testcase',classname=os.environ['CLASS139'],name=os.environ['NAME139'],file=os.environ['FILE139'])
if not passed:E.SubElement(c,'failure',message='red139').text='red139'
E.ElementTree(t).write(sys.argv[2],encoding='utf-8',xml_declaration=True)
sys.exit(0 if passed else 1)
''')
lang='node' if case=='node' else 'go' if case=='go' else 'python'
file139={'python':'tests/test_target139.py','node':'src/target139.test.ts','go':'target139_test.go'}[lang]
env.update(CLASS139={'python':'tests.test_target139','node':'src/target139.test.ts','go':'example.invalid/item139'}[lang],NAME139='TestTarget139' if lang=='go' else 'target139' if lang=='node' else 'test_target139',FILE139=file139)
command=shlex.join([sys.executable,str(runner),'suite'])+' {junit}'
config='shipcraft_min="0.0"\nlang="python"\nrunner="pytest"\ntest_command='+json.dumps(command)+'\ntest_globs=["tests/**"]\n[execution]\nci="local"\nreview="off"\n'
config=config.replace('lang="python"', 'lang='+json.dumps(lang)).replace('runner="pytest"','runner='+json.dumps({'python':'pytest','node':'vitest','go':'gotestsum'}[lang])).replace('test_globs=["tests/**"]','test_globs='+json.dumps([file139]))
if case in ('commands','midwrite','build-failure'):config+='[build]\ncommand='+json.dumps(shlex.join([sys.executable,str(runner),'build']))+'\n'
if case in ('commands','midwrite','check-failure'):config=config.replace('[execution]','check='+json.dumps(shlex.join([sys.executable,str(runner),'check']))+'\n[execution]')
if case=='pr-timeout':config=config.replace('ci="local"','ci="local"\nci_timeout=1')
git('init','-q','-b','main');write('.shipcraft.toml',config);write('requirements.txt','pytest\n');write('value139','red')
if lang=='go':write('go.mod','module example.invalid/item139\n\ngo 1.21\n')
ok(binary,'init');commit('chore: fixture139');base139=git('rev-parse','HEAD')
write(file139,{'python':'def test_target139():\n    assert False\n','node':'import {it,expect} from "vitest"; it("target139",()=>expect(false).toBe(true));\n','go':'package item139\nimport "testing"\nfunc TestTarget139(t *testing.T){t.Fatal("red139")}\n'}[lang])
testbytes139=Path(file139).read_bytes()
def restart(n):
 commit('test: completed opening139')
 git('checkout','-qb','variant139-'+str(n),base139)
 write(file139,testbytes139)
def cuts(p):return [x for x in p.stderr.split(b'\n') if x.startswith(b'shipcraft: output cut:')]
def screen_tail(p):
 b=p.stderr;start=b.index(b'\n',b.index(b'running the suite'))+1
 end=b.index(b'shipcraft: output cut:',start)
 return b[start:end]
def red(*args,**kw):return run(binary,'red',*args,**kw)
def entries():return [json.loads(x) for x in (cw/'trace139').read_text().splitlines()]
def rows():return [json.loads(x) for x in Path(git('rev-parse','--git-path','shipcraft/runs.jsonl')).read_text().splitlines()]
write('value139','green');commit('test: passing CI149 fixture');git('checkout','-qb','item149')
def ci(*args,**kw):return run(binary,'ci','--base',base139,*args,**kw)
def ci_file():return logpath('ci')
def ci_rows():return [r for r in rows() if r['layer']=='ci']
def remote():
 st=cb/'state';origin=cb/'origin149.git';git('init','-q','--bare',origin)
 git('--git-dir='+str(origin),'symbolic-ref','HEAD','refs/heads/main')
 write(st/'origin',str(origin));git('remote','add','origin',origin)
 git('push','-q','origin',base139+':refs/heads/main');git('fetch','-q','origin');git('remote','set-head','origin','main')
def pr():
 write(cb/'state/sha',git('rev-parse','HEAD'));write(cw/'body149','Body149\n')
 return run(binary,'pr','--title','Item149','--body',cw/'body149')
if case=='repro':
 payload(b'O'*150000,b'E'*150000)
 whole=ci(extra={'SHIPCRAFT_OUTPUT':'full'});p=ci()
 print('REPRO149 combined bytes:',len(p.stdout)+len(p.stderr),flush=True)
 assert p.returncode==whole.returncode==0,(p.returncode,whole.returncode,p.stderr[-1000:])
 assert len(p.stdout)+len(p.stderr)<=20000,('reproduction: runner floods terminal',len(p.stdout)+len(p.stderr))
elif case=='bytes':
 payload(b'O'*150000,b'E'*150000);p=ci()
 expected=b'shipcraft: output cut: the command wrote 300000 bytes; shown: the first 4096 and the last 1 line(s); all of it: .git/shipcraft/output/ci.log (SHIPCRAFT_OUTPUT=full prints everything)'
 assert p.returncode==0 and cuts(p)==[expected],cuts(p)
 f=ci_file().read_bytes();header,data=f.split(b'`\n',1)
 assert header==('shipcraft: `'+command.replace('{junit}',entries()[-1]['argv'][0])).encode(),header
 assert data.count(b'O')==150000 and data.count(b'E')==150000 and len(data)==300001 and data.endswith(b'\n')
 screen=screen_tail(p)
 assert screen==data[:4096]+b'\n'+data[-4097:-1]+b'\n'
 assert b'output cut:' not in p.stdout and b'CI ok.' in p.stdout
elif case=='boundary4096':
 payload(b'A'*4096);p=ci()
 assert p.returncode==0 and not cuts(p) and p.stderr.count(b'A'*4096+b'\n')==1
 assert ci_file().is_file(),'short output must also be captured'
 assert ci_file().read_bytes().split(b'`\n',1)[1]==b'A'*4096+b'\n'
elif case=='commands':
 payload(b'S'*10000);payload(b'B'*10000,mode='build');payload(b'C'*10000,mode='check');p=ci()
 assert p.returncode==0 and len(cuts(p))==3,cuts(p)
 f=ci_file().read_bytes()
 assert [x['mode'] for x in entries()]==['build','check','suite']
 assert f.count(b'shipcraft: `')==3 and f.index(b'B'*10000)<f.index(b'C'*10000)<f.index(b'S'*10000)
 assert all(b'wrote 10000 bytes' in c for c in cuts(p))
elif case=='dirty':
 payload(b'D'*10000);write('value139','red');p=ci()
 assert p.returncode==0 and len(cuts(p))==1,cuts(p)
 assert entries()[-1]['cwd']!=str(Path.cwd()) and Path('value139').read_text()=='red'
 assert ci_file().read_bytes().count(b'D'*10000)==1 and b'.git/shipcraft/output/ci.log' in cuts(p)[0]
elif case=='worktree':
 main=Path.cwd();wt=cw/'linked149';git('worktree','add','-qb','linked149',wt);os.chdir(wt)
 payload(b'W'*10000);p=ci();f=ci_file()
 assert p.returncode==0 and len(cuts(p))==1,cuts(p)
 assert f.is_absolute() and f.is_file() and str(f).encode() in cuts(p)[0]
 assert not (main/'.git/shipcraft/output/ci.log').exists() and f.read_bytes().count(b'W'*10000)==1
elif case=='isolation':
 payload(b'I'*10000);write(logpath('red'),b'red-sentinel149');write(logpath('hook'),b'hook-sentinel149');p=ci()
 assert p.returncode==0 and len(cuts(p))==1,cuts(p)
 assert logpath('red').read_bytes()==b'red-sentinel149' and logpath('hook').read_bytes()==b'hook-sentinel149'
 before=ci_file().read_bytes();write('value139','red');write(file139,Path(file139).read_text()+'\n# new RED149\n');q=red()
 assert q.returncode==0 and ci_file().read_bytes()==before
elif case=='no-command':
 write(ci_file(),b'keep149\x00');p=run(binary,'ci','--base','not-a-commit149')
 assert p.returncode==2 and ci_file().read_bytes()==b'keep149\x00' and not (cw/'trace139').exists()
 assert b'--base not-a-commit149 is not a commit' in p.stderr
elif case=='suite-red':
 write('value139','red');commit('product: red149');payload(b'R'*150000,b'F'*150000);p=ci()
 assert p.returncode==1 and len(cuts(p))==1,(p.returncode,cuts(p))
 refusal=p.stderr.split(cuts(p)[0]+b'\n',1)[1].splitlines()
 assert len(refusal)==3 and refusal[0].startswith(b'shipcraft refused:') and refusal[1].startswith(b'Why:') and refusal[2].startswith(b'Next:'),refusal
 r=ci_rows()[-1];assert r['result']=='refused' and r['code']=='suite-red' and r['failed']==['tests.test_target139::test_target139'],r
 assert ci_file().read_bytes().split(b'`\n',1)[1].count(b'R')==150000
elif case=='no-report':
 payload(b'O'*12000,b' '*8000+b'\nfirst diagnostic149\nwrong last149\n');write(cw/'no-report','yes');p=ci()
 assert p.returncode==1 and len(cuts(p))==1,(p.returncode,cuts(p))
 reason=p.stderr.split(b'shipcraft refused:')[-1]
 assert b'first diagnostic149' in reason and b'wrong last149' not in reason and ci_rows()[-1]['code']=='no-report'
 assert ci_file().read_bytes().count(b'O'*12000)==1
elif case=='blocked-parent':
 payload(b'P'*10000);f=ci_file();write(f.parent,b'blocked149');p=ci()
 assert p.returncode==0 and not cuts(p) and p.stderr.count(b'P'*10000)==1 and f.parent.read_bytes()==b'blocked149'
 assert ci_rows()[-1]['result']=='passed'
elif case=='midwrite':
 payload(b'M'*30000);payload(b'B'*30000,mode='build');payload(b'C'*30000,mode='check')
 def limit():
  signal.signal(signal.SIGXFSZ,signal.SIG_IGN);resource.setrlimit(resource.RLIMIT_FSIZE,(8192,8192))
 p=ci(preexec_fn=limit)
 assert p.returncode==0 and len(cuts(p))==3,(p.returncode,cuts(p))
 assert all(c.endswith(b'; the file .git/shipcraft/output/ci.log is incomplete (a write failed)') for c in cuts(p)),cuts(p)
 assert ci_file().stat().st_size<=8192 and all(b'all of it:' not in c for c in cuts(p))
elif case=='ci-pr':
 payload(b'P'*10000);p=ci('--pr')
 assert p.returncode==0 and len(cuts(p))==1,cuts(p)
 assert ci_file().read_bytes().count(b'P'*10000)==1 and ci_rows()[-1]['result']=='passed'
elif case=='pr-local':
 remote();payload(b'P'*10000);p=pr()
 assert p.returncode==0 and len(cuts(p))==1,(p.returncode,cuts(p),p.stdout,p.stderr[-1000:])
 assert ci_file().read_bytes().count(b'P'*10000)==1 and ci_rows()[-1]['result']=='passed'
 statuses=[json.loads(x) for x in (cb/'state/statuses.jsonl').read_text().splitlines()]
 assert any(r['context']=='shipcraft/ci' and r['state']=='success' and r['description']=='on this machine: CI passed' for r in statuses),statuses
 assert any(r['layer']=='pr' and r['result']=='passed' for r in rows())
elif case=='github':
 payload(b'G'*150000,b'H'*150000);f=ci_file();write(f,b'keep-github149');observed=[]
 for extra in ({'GITHUB_ACTIONS':'true'},{'GITHUB_ACTIONS':'true','SHIPCRAFT_OUTPUT':'FULL'}):
  p=ci(extra=extra);observed.append((p.returncode,len(cuts(p)),p.stderr.count(b'G'),p.stderr.count(b'H'),f.read_bytes()))
 assert observed==[(0,0,150000,150000,b'keep-github149')]*2,observed
 f.unlink();p=ci(extra={'GITHUB_ACTIONS':'true'})
 assert p.returncode==0 and not cuts(p) and not f.exists() and p.stderr.count(b'G')==150000
elif case=='env-values':
 payload(b'V'*10000);observed=[]
 for value in ('TRUE','1','',' true','true ','true\n',os.fsdecode(b'true\xff')):
  p=ci(extra={'GITHUB_ACTIONS':value});observed.append((value,p.returncode,len(cuts(p))))
 assert all(rc==0 and n==1 for _,rc,n in observed),observed
 assert ci_file().read_bytes().count(b'V'*10000)==1
elif case=='ci-env':
 payload(b'C'*10000);p=ci(extra={'CI':'true'})
 assert p.returncode==0 and len(cuts(p))==1,cuts(p)
 assert ci_file().read_bytes().count(b'C'*10000)==1
elif case=='full':
 payload(b'F'*150000,b'U'*150000);f=ci_file();write(f,b'keep-full149');p=ci(extra={'SHIPCRAFT_OUTPUT':'full'})
 assert p.returncode==0 and not cuts(p) and p.stderr.count(b'F')==150000 and p.stderr.count(b'U')==150000 and f.read_bytes()==b'keep-full149'
 f.unlink();p=ci(extra={'SHIPCRAFT_OUTPUT':'full'})
 assert p.returncode==0 and not cuts(p) and not f.exists()
elif case=='red-hook':
 payload(b'R'*10000);write('value139','red');write(file139,Path(file139).read_text()+'\n# opening149\n');write(ci_file(),b'keep-red149')
 p=red(extra={'GITHUB_ACTIONS':'true'});git('add','-A');q=run('git','commit','-qm','test: opening149',extra={'GITHUB_ACTIONS':'true'})
 assert p.returncode==q.returncode==0 and len(cuts(p))==2 and len(cuts(q))==1
 assert logpath('red').read_bytes().count(b'R'*10000)==2 and logpath('hook').read_bytes().count(b'R'*10000)==1 and ci_file().read_bytes()==b'keep-red149'
elif case=='node':
 payload(b'N'*10000);p=ci()
 assert p.returncode==0 and len(cuts(p))==1,cuts(p)
 assert ci_file().read_bytes().count(b'N'*10000)==1 and env['CLASS139']=='src/target139.test.ts'
elif case=='go':
 payload(b'G'*10000);p=ci()
 assert p.returncode==0 and len(cuts(p))==1,cuts(p)
 assert ci_file().read_bytes().count(b'G'*10000)==1 and env['CLASS139']=='example.invalid/item139'
elif case=='version':
 spec=Path(os.environ['ACEITE']).parent/'docs/spec.md'
 version=re.search(r'This contract is \*\*([0-9.]+)\*\*',spec.read_text()).group(1)
 assert ok(binary,'--version').stdout.split()[1].decode()==version,version
elif case=='control-fixture':
 payload(b'fixture149-out\n',b'fixture149-err\n');p=ci()
 assert p.returncode==0 and p.stderr.count(b'fixture149-out\n')==1 and p.stderr.count(b'fixture149-err\n')==1
 assert [x['mode'] for x in entries()]==['suite'] and entries()[0]['cwd']==str(Path.cwd())
 assert ci_rows()[-1]['result']=='passed' and not cuts(p)
 write('value139','red');commit('product: control red149');q=ci()
 assert q.returncode==1 and ci_rows()[-1]['code']=='suite-red' and ci_rows()[-1]['failed']==['tests.test_target139::test_target139']
elif case=='control-pr':
 remote();payload(b'control-pr149\n');p=pr()
 assert p.returncode==0 and p.stderr.count(b'control-pr149\n')==1,(p.returncode,p.stdout,p.stderr)
 prs=json.loads((cb/'state/prs.json').read_text());assert prs['1']['title']=='Item149' and prs['1']['headRefName']=='item149',prs
 assert ci_rows()[-1]['result']=='passed' and any(r['layer']=='pr' and r['result']=='passed' for r in rows())
 statuses=[json.loads(x) for x in (cb/'state/statuses.jsonl').read_text().splitlines()]
 assert any(r['context']=='shipcraft/ci' and r['state']=='success' and r['description']=='on this machine: CI passed' for r in statuses),statuses
elif case=='nonregular':
 payload(b'N'*10000);f=ci_file();f.parent.mkdir(parents=True);target=cw/'target149';write(target,b'untouched149');observed=[]
 for kind in ('symlink','fifo','directory'):
  if kind=='symlink':f.symlink_to(target)
  elif kind=='fifo':os.mkfifo(f)
  else:f.mkdir()
  p=ci();observed.append((kind,p.returncode,len(cuts(p)),p.stderr.count(b'N'*10000)))
  if f.is_dir():f.rmdir()
  else:f.unlink()
 assert observed==[(k,0,0,1) for k in ('symlink','fifo','directory')] and target.read_bytes()==b'untouched149',observed
elif case=='truncate':
 payload(b'OLD149'*3000);p=ci();payload(b'new149\n');q=ci()
 assert p.returncode==q.returncode==0 and len(cuts(p))==1 and not cuts(q),cuts(p)
 assert ci_file().read_bytes().count(b'new149\n')==1 and b'OLD149' not in ci_file().read_bytes()
elif case=='late-drop':
 payload(b'H'*4096+b'last149\n');write(cw/'late139','yes');p=ci();time.sleep(3.2)
 assert p.returncode==0 and len(cuts(p))==1,cuts(p)
 assert b'LATE139' not in p.stdout+p.stderr and b'LATE139' not in ci_file().read_bytes()
elif case=='check-failure':
 payload(b'O'*10000,b' '*9000+b'\ncheck diagnostic149\nwrong149\n',mode='check');write(cw/'check.fail','yes');p=ci()
 assert p.returncode==1 and len(cuts(p))==1,(p.returncode,cuts(p))
 reason=p.stderr.split(b'shipcraft refused:')[-1]
 assert b'check diagnostic149' in reason and b'wrong149' not in reason and ci_rows()[-1]['code']=='no-report'
 assert [x['mode'] for x in entries()]==['check'] and ci_file().read_bytes().count(b'O'*10000)==1
elif case=='build-failure':
 payload(b'B'*10000,b'build diagnostic149\n',mode='build');write(cw/'build.fail','yes');p=ci()
 assert p.returncode==1 and len(cuts(p))==1,(p.returncode,cuts(p))
 assert ci_rows()[-1]['code']=='build-failed' and [x['mode'] for x in entries()]==['build']
 assert ci_file().read_bytes().count(b'B'*10000)==1 and b'build diagnostic149' in ci_file().read_bytes()
elif case=='row-failure':
 f=Path(git('rev-parse','--git-path','shipcraft/runs.jsonl'));f.unlink(missing_ok=True);f.mkdir();payload(b'J'*10000);p=ci()
 assert p.returncode==0 and len(cuts(p))==1,cuts(p)
 assert f.is_dir() and ci_file().read_bytes().count(b'J'*10000)==1 and b'CI ok.' in p.stdout
elif case=='pr-timeout':
 remote()
 # Delay after the runner has emitted bytes, retaining the child's unfinished log.
 text=runner.read_text().replace("if mode!='suite':", "if (home/'timeout149').exists():time.sleep(15)\nif mode!='suite':")
 write(runner,text);write(cw/'timeout149','yes');payload(b'T'*10000);p=pr()
 assert p.returncode!=0 and not cuts(p) and ci_file().is_file(),(p.returncode,cuts(p),'CI log missing')
 assert ci_file().read_bytes().count(b'T'*10000)==1
 statuses=[json.loads(x) for x in (cb/'state/statuses.jsonl').read_text().splitlines()]
 assert any(r['context']=='shipcraft/ci' and r['state']=='error' and 'timed out' in r['description'].lower() for r in statuses),statuses
 assert any(r['layer']=='pr' and r['result']=='refused' and r['code']=='ci-timed-out' for r in rows())
elif case=='github-pr':
 remote();payload(b'G'*10000);write(ci_file(),b'keep-pr149');write(cw/'body149','Body149\n')
 p=run(binary,'pr','--title','Item149','--body',cw/'body149',extra={'GITHUB_ACTIONS':'true'})
 assert p.returncode==0 and not cuts(p) and p.stderr.count(b'G'*10000)==1 and ci_file().read_bytes()==b'keep-pr149',(p.returncode,p.stdout,p.stderr[-1000:])
 assert ci_rows()[-1]['result']=='passed'
else:raise AssertionError('unrouted case: '+case)
PY149
  pass
}
