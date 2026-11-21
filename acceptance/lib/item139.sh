# Item 139: public runner-output contract; deliberately synthetic byte streams/JUnit.
item139_langs() { echo core node go; }
item139_cases() {
  local c
  if [ "${l:-core}" = node ]; then echo v1-139.node; return; fi
  if [ "${l:-core}" = go ]; then echo v1-139.go; return; fi
  for c in repro control-fixture boundary4096 boundary4097 head tail40 tailbytes tail-nolf tail-invalid tail-separators two-streams commands redo truncate no-command hook-red hook-green full-red full-hook env-values blocked-parent nonregular readonly worktree no-report check-failure later-lock-failure log-row-failure leftover late-drop ci version full-nonregular midwrite spawn-failure git-path git-resolution control-git; do echo "v1-139.$c"; done
}
item139_case() {
  EXPECT="item 139: ${CASE#v1-139.}"; v1_start codex
  must_accept 'runner output contract' cmd "$PY" - "${CASE#v1-139.}" "$(command -v shipcraft)" "$CW" <<'PY139'
import json,os,re,shlex,shutil,subprocess,sys,time,signal,resource,socket
from pathlib import Path
case,binary,cw=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw).resolve()
root=cw/'repo139 space';root.mkdir();os.chdir(root)
env=dict(os.environ)
for k in subprocess.check_output(['git','rev-parse','--local-env-vars'],text=True).splitlines()+['GIT_CEILING_DIRECTORIES','SHIPCRAFT_OUTPUT']:env.pop(k,None)
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
with (home/'trace139').open('a') as f:f.write(json.dumps(dict(mode=mode,files=os.environ.get('SHIPCRAFT_FILES'),cases=os.environ.get('SHIPCRAFT_CASES'),argv=sys.argv[2:]))+'\\n')
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
if case in ('commands','midwrite'):config+='[build]\ncommand='+json.dumps(shlex.join([sys.executable,str(runner),'build']))+'\n'
if case in ('commands','midwrite','check-failure'):config=config.replace('[execution]','check='+json.dumps(shlex.join([sys.executable,str(runner),'check']))+'\n[execution]')
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
# Delegating Git fault only changes the output-file path query. Ordinary Git remains real.
realgit=shutil.which('git');tools=cw/'tools139';tools.mkdir();proxy=tools/'git'
write(proxy,'#!'+sys.executable+'\n'+r'''import os,sys
from pathlib import Path
args=sys.argv[1:]
mode=Path(MODE).read_text() if Path(MODE).exists() else ''
if '--git-path' in args and any(a in ('shipcraft/output/red.log','shipcraft/output/hook.log') for a in args):
 Path(HIT).write_text(mode)
 if mode=='fail':sys.exit(73)
 if mode=='empty':print('  ');sys.exit(0)
 if mode=='relative':print('  custom139/output.log \n');sys.exit(0)
os.execv(REAL,[REAL,*args])
'''.replace('MODE',repr(str(cw/'gitmode'))).replace('HIT',repr(str(cw/'githit'))).replace('REAL',repr(realgit)))
proxy.chmod(0o755)

if case=='repro':
 payload(b'O'*150000,b'E'*150000)
 p=run(binary,'red')
 assert p.returncode==0 and len(locks())==1,(p.returncode,p.stdout,p.stderr[-1000:])
 print('REPRO139 combined bytes:',len(p.stdout)+len(p.stderr),flush=True)
 assert len(p.stdout)+len(p.stderr)<=20000,('reproduction: runner floods terminal',len(p.stdout)+len(p.stderr))
elif case=='control-fixture':
 payload(b'fixture139-out\n',b'fixture139-err\n');p=red()
 assert p.returncode==0 and json.loads(locks()[0].read_text())['failing_at_red']==['tests.test_target139::test_target139']
 assert p.stderr.count(b'fixture139-out\n')==2 and p.stderr.count(b'fixture139-err\n')==2
 assert [x['mode'] for x in entries()]==['suite','suite'] and entries()[1]['cases']
 restart('control');assert red().returncode==0;commit('test: fixture139 RED');write('value139','green');q=commit('feat: fixture139 GREEN')
 assert json.loads(locks()[0].read_text())['state']=='closed' and b'lock ' in q.stdout+q.stderr
elif case=='boundary4096':
 payload(b'A'*4096);p=red()
 assert p.returncode==0 and not cuts(p) and p.stderr.count(b'A'*4096+b'\n')==2
elif case=='boundary4097':
 payload(b'A'*4096+b'Z');p=red()
 assert p.returncode==0 and len(cuts(p))==2 and all(c==b'shipcraft: output cut: the command wrote 4097 bytes; shown: the first 4096 and the last 1 line(s); all of it: .git/shipcraft/output/red.log (SHIPCRAFT_OUTPUT=full prints everything)' for c in cuts(p)),cuts(p)
 assert len(cuts(p))==2,cuts(p)
 assert screen_tail(p)==b'A'*4096+b'\nZ\n'
elif case=='head':
 data=bytes(range(33,127))*60;payload(data);p=red()
 assert len(cuts(p))==2,cuts(p)
 assert screen_tail(p)[:4096]==data[:4096] and len(cuts(p))==2 and b'RED locked at' in p.stdout
elif case=='tail40':
 data=b'H'*4096+b''.join(('line%03d\n'%i).encode() for i in range(100));payload(data);p=red()
 assert len(cuts(p))==2,cuts(p)
 assert screen_tail(p)==b'H'*4096+b'\n'+b''.join(('line%03d\n'%i).encode() for i in range(60,100))
 assert all(b'last 40 line(s)' in c for c in cuts(p)) and len(cuts(p))==2
elif case=='tailbytes':
 lines=[('%03d'%i).encode()+b'x'*296+b'\n' for i in range(50)];payload(b'H'*4096+b''.join(lines));p=red()
 assert len(cuts(p))==2,cuts(p)
 assert screen_tail(p)==b'H'*4096+b'\n'+b''.join(lines[-13:]) and len(cuts(p))==2
 assert all(b'last 13 line(s)' in c for c in cuts(p))
elif case=='tail-nolf':
 payload(b'H'*4096+b'x'*5000+b'END139');p=red()
 assert len(cuts(p))==2,cuts(p)
 assert screen_tail(p)==b'H'*4096+b'\n'+b'x'*(4096-6)+b'END139\n' and len(cuts(p))==2
elif case=='tail-invalid':
 payload(b'H'*4096+b'\xff\xfe\n');p=red()
 assert len(cuts(p))==2,cuts(p)
 assert screen_tail(p)==b'H'*4096+b'\n'+('\ufffd\ufffd\n'.encode()) and all(b'wrote 4099 bytes' in c for c in cuts(p)) and len(cuts(p))==2
elif case=='tail-separators':
 tail=b'A\rB\xe2\x80\xa8C\xe2\x80\xa9D\nE';payload(b'H'*4096+tail);p=red()
 assert len(cuts(p))==2,cuts(p)
 assert screen_tail(p)==b'H'*4096+b'\n'+tail+b'\n' and len(cuts(p))==2 and all(b'last 2 line(s)' in c for c in cuts(p))
elif case=='two-streams':
 # Record the actual sh -c argument, including the runner's JUnit substitution.
 realsh=shutil.which('sh');shelltrace=cw/'shell139.jsonl'
 write(tools/'sh','#!'+sys.executable+'\nimport json,os,sys\nwith open('+repr(str(shelltrace))+',"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nos.execv('+repr(realsh)+',['+repr(realsh)+',*sys.argv[1:]])\n')
 (tools/'sh').chmod(0o755)
 a=bytes(range(65,91))*400;b=bytes(range(97,123))*400;payload(a,b);p=red(extra={'PATH':str(tools)+os.pathsep+env['PATH']});assert logpath().is_file(),'missing red log';f=logpath().read_bytes()
 # No global inter-stream ordering asserted. Each stream retains its byte sequence.
 parts=f.split(b'shipcraft: `')[1:]
 assert len(parts)==2 and len(cuts(p))==2
 shellargs=[json.loads(line) for line in shelltrace.read_text().splitlines()]
 assert len(shellargs)==2 and all(args[0]=='-c' and len(args)==2 for args in shellargs),shellargs
 assert [part.split(b'`\n',1)[0].decode() for part in parts]==[args[1] for args in shellargs]
 assert screen_tail(p)==parts[0].split(b'`\n',1)[1][:4096]+b'\n'+parts[0].split(b'`\n',1)[1][-4097:-1]+b'\n'
 for part in parts:
  body=part.split(b'`\n',1)[1]
  assert bytes(x for x in body if 65<=x<=90)==a and bytes(x for x in body if 97<=x<=122)==b
  assert len(body)==len(a)+len(b)+1 and body.endswith(b'\n')
elif case=='commands':
 payload(b'S'*10000);payload(b'B'*10000,mode='build');payload(b'C'*10000,mode='check');p=red();assert logpath().is_file(),'missing red log';f=logpath().read_bytes()
 assert p.returncode==0 and len(cuts(p))==4 and [x['mode'] for x in entries()]==['build','check','suite','suite']
 assert f.count(b'shipcraft: `')==4 and f.index(b'B'*10000)<f.index(b'C'*10000)<f.index(b'S'*10000)
 assert f.count(b'S'*10000)==2 and b'output cut:' not in p.stdout and b'RED locked at' in p.stdout
elif case=='redo':
 payload(b'old139\n');assert red().returncode==0;commit('test: RED139')
 write(file139,Path(file139).read_text()+'\n# repaired assertion description139\n');payload(b'R'*10000);p=red('--redo')
 assert p.returncode==0 and b'RED redone at' in p.stdout and len(cuts(p))==2 and b'old139' not in log_output()
elif case=='truncate':
 payload(b'OLD139'*3000);assert red().returncode==0
 before=json.loads(locks()[0].read_text());restart('truncate');payload(b'new139\n');p=red()
 assert p.returncode==0 and log_output().count(b'new139\n')>=1 and b'OLD139' not in log_output() and not cuts(p)
 assert json.loads(locks()[0].read_text())==before
elif case=='no-command':
 f=logpath();write(f,b'keep139\x00');payload(b'forbidden139')
 p=red('--redo')
 assert p.returncode==1 and f.read_bytes()==b'keep139\x00' and not (cw/'trace139').exists() and b'Why:' in p.stderr
elif case=='hook-red':
 payload(b'Q'*150000,b'W'*150000);assert red().returncode==0;f=logpath();assert f.is_file(),'missing red log';r=f.read_bytes();git('add','-A');p=run('git','commit','-qm','test: RED139')
 assert p.returncode==0 and len(p.stdout)+len(p.stderr)<=20000 and len(cuts(p))==1
 assert logpath('hook').read_bytes().split(b'`\n',1)[1].count(b'Q')==150000 and logpath('hook').read_bytes().split(b'`\n',1)[1].count(b'W')==150000 and logpath().read_bytes()==r
 assert b'RED commit checked:' in p.stdout+p.stderr and json.loads(locks()[0].read_text())['state']=='open'
elif case=='hook-green':
 payload(b'G'*150000,b'V'*150000);assert red().returncode==0;commit('test: RED139');write('value139','green');git('add','value139');p=run('git','commit','-qm','feat: GREEN139')
 assert p.returncode==0 and len(p.stdout)+len(p.stderr)<=20000 and len(cuts(p))==1
 assert json.loads(locks()[0].read_text())['state']=='closed' and logpath('hook').read_bytes().split(b'`\n',1)[1].count(b'G')==150000
elif case=='full-red':
 payload(b'F'*150000,b'U'*150000);f=logpath();write(f,b'preserve139')
 p=red(extra={'SHIPCRAFT_OUTPUT':'full'});d=locks()[0].read_bytes()
 assert p.returncode==0 and screen_output(p).count(b'F')==300000 and screen_output(p).count(b'U')==300000 and not cuts(p) and f.read_bytes()==b'preserve139'
 restart('full');q=red();assert q.returncode==0 and locks()[0].read_bytes()==d
elif case=='full-hook':
 payload(b'F'*150000,b'U'*150000);assert red().returncode==0;f=logpath('hook');write(f,b'preserve139');git('add','-A');p=run('git','commit','-qm','test: full hook139',extra={'SHIPCRAFT_OUTPUT':'full'})
 assert p.returncode==0 and screen_output(p).count(b'F')==150000 and screen_output(p).count(b'U')==150000 and not cuts(p) and f.read_bytes()==b'preserve139'
elif case=='env-values':
 payload(b'E'*10000);observed=[]
 for i,value in enumerate(('FULL','1',' full','full ','full\n','',os.fsdecode(b'full\xff'))):
  if i:restart(i)
  p=red(extra={'SHIPCRAFT_OUTPUT':value});observed.append((value,p.returncode,len(cuts(p))))
 assert all(rc==0 and n==2 for _,rc,n in observed),observed
elif case=='blocked-parent':
 payload(b'P'*10000);f=logpath();write(f.parent,b'blocked139');p=red()
 assert p.returncode==0 and not cuts(p) and p.stderr.count(b'P'*10000)==2 and len(locks())==1 and f.parent.read_bytes()==b'blocked139'
elif case=='nonregular':
 payload(b'N'*10000);f=logpath();f.parent.mkdir(parents=True);target=cw/'target139';target.write_bytes(b'untouched139');observed=[]
 for i,kind in enumerate(('symlink','fifo','directory','socket')):
  if i:restart(i)
  sock=None
  if kind=='symlink':f.symlink_to(target)
  elif kind=='fifo':os.mkfifo(f)
  elif kind=='directory':f.mkdir()
  else:
   sock=socket.socket(socket.AF_UNIX);here=Path.cwd();os.chdir(f.parent);sock.bind(f.name);os.chdir(here)
  p=red();observed.append((kind,p.returncode,len(cuts(p)),p.stderr.count(b'N'*10000)))
  if sock:sock.close()
  if f.is_dir():f.rmdir()
  else:f.unlink()
 assert observed==[(k,0,0,2) for k in ('symlink','fifo','directory','socket')] and target.read_bytes()==b'untouched139',observed
elif case=='readonly':
 payload(b'R'*10000);f=logpath();write(f,b'kept139');f.chmod(0o444)
 try:p=red()
 finally:f.chmod(0o644)
 assert p.returncode==0 and not cuts(p) and p.stderr.count(b'R'*10000)==2 and f.read_bytes()==b'kept139'
elif case=='worktree':
 # Commit tests with no lock; linked worktree then makes its own RED.
 commit('test: unbound tests139');main=Path.cwd();wt=cw/'linked139';git('worktree','add','-qb','linked139',str(wt));os.chdir(wt)
 payload(b'W'*10000);p=red();f=logpath()
 assert p.returncode==0 and len(cuts(p))==2 and f.is_absolute() and f.is_file() and str(f).encode() in cuts(p)[0]
 assert not (main/'.git/shipcraft/output/red.log').exists() and f.read_bytes().count(b'W'*10000)==2
elif case=='no-report':
 payload(b'O'*12000,b' '*8000+b'\nfirst diagnostic139\nwrong last139\n');write(cw/'no-report','yes');p=red()
 assert p.returncode==1 and not locks() and len(cuts(p))==2 and b'first diagnostic139' in p.stderr.split(b'shipcraft refused:')[-1] and b'wrong last139' not in p.stderr.split(b'shipcraft refused:')[-1]
 assert log_output().count(b'O')==24000 and rows()[-1]['code']=='no-report'
elif case=='check-failure':
 payload(b' '*8000+b'\nstdout diagnostic139\n',b' '*9000+b'\nstderr diagnostic139\nwrong139\n',mode='check');write(cw/'check.fail','yes');p=red()
 assert p.returncode==1 and len(cuts(p))==1 and [x['mode'] for x in entries()]==['check'] and not locks()
 reason=p.stderr.split(b'shipcraft refused:')[-1];assert b'stderr diagnostic139' in reason and b'stdout diagnostic139' not in reason and b'wrong139' not in reason
 assert b'checking the project' in p.stderr and b'stderr diagnostic139' in logpath().read_bytes()
elif case=='later-lock-failure':
 payload(b'L'*10000);folder=Path('.shipcraft/locks');folder.chmod(0o555)
 try:p=red()
 finally:folder.chmod(0o755)
 assert p.returncode==2 and not locks() and len(cuts(p))==2 and logpath().read_bytes().count(b'L'*10000)==2 and b'RED locked at' not in p.stdout
elif case=='log-row-failure':
 payload(b'J'*10000);f=Path(git('rev-parse','--git-path','shipcraft/runs.jsonl'));f.unlink(missing_ok=True);f.mkdir();p=red()
 assert p.returncode==0 and f.is_dir() and len(locks())==1 and len(cuts(p))==2 and logpath().read_bytes().count(b'J'*10000)==2
elif case=='leftover':
 payload(b'H'*4096+b'last139\n');write(cw/'late139','yes');start=time.time();p=red()
 assert p.returncode==0 and time.time()-start<12 and len(cuts(p))==2 and screen_tail(p)==b'H'*4096+b'\nlast139\n'
elif case=='late-drop':
 payload(b'H'*4096+b'last139\n');write(cw/'late139','yes');p=red();time.sleep(3.2)
 assert p.returncode==0 and b'LATE139' not in p.stdout+p.stderr and b'LATE139' not in logpath().read_bytes() and len(cuts(p))==2
elif case=='ci':
 payload(b'I'*150000,b'C'*150000);base=git('rev-parse','HEAD');commit('test: CI fixture139');p=run(binary,'ci','--base',base,extra={'GITHUB_ACTIONS':'true'})
 assert p.returncode==1 and screen_output(p).count(b'I')==150000 and screen_output(p).count(b'C')==150000 and not cuts(p) and not logpath().exists() and not logpath('hook').exists()
elif case=='version':
 spec=Path(os.environ['ACEITE']).parent/'docs/spec.md';manifest=Path(os.environ['ACEITE']).parent/'nucleo/Cargo.toml'
 version=re.search(r'This contract is \*\*([0-9.]+)\*\*',spec.read_text()).group(1)
 actual=re.search(r'(?m)^version = "([^"]+)"',manifest.read_text()).group(1)
 assert actual==version and ok(binary,'--version').stdout.split()[1].decode()==version,(actual,version)
elif case=='full-nonregular':
 payload(b'F'*10000);f=logpath();f.parent.mkdir(parents=True);os.mkfifo(f)
 p=red(extra={'SHIPCRAFT_OUTPUT':'full'});assert p.returncode==0 and not cuts(p) and p.stderr.count(b'F'*10000)==2 and f.lstat().st_mode & 0o170000==0o010000
elif case=='midwrite':
 payload(b'M'*30000);payload(b'B'*30000,mode='build');payload(b'C'*30000,mode='check')
 def limit():
  signal.signal(signal.SIGXFSZ,signal.SIG_IGN);resource.setrlimit(resource.RLIMIT_FSIZE,(8192,8192))
 p=red(preexec_fn=limit)
 assert p.returncode==0 and len(locks())==1 and len(cuts(p))==4 and all(b'is incomplete (a write failed)' in c for c in cuts(p)),(p.returncode,cuts(p))
 assert logpath().stat().st_size<=8192 and all(b'all of it:' not in c for c in cuts(p))
elif case=='spawn-failure':
 f=logpath();write(f,b'preserved139');tiny=cw/'tiny139';tiny.mkdir();(tiny/'git').symlink_to(realgit)
 p=red(extra={'PATH':str(tiny)})
 assert p.returncode==2 and f.read_bytes()==b'preserved139' and not (cw/'trace139').exists()
elif case=='git-path':
 payload(b'G'*10000);write(cw/'gitmode','relative');p=red(extra={'PATH':str(tools)+os.pathsep+env['PATH']})
 assert p.returncode==0 and len(cuts(p))==2 and all(b'all of it: custom139/output.log ' in c for c in cuts(p)) and Path('custom139/output.log').read_bytes().count(b'G'*10000)==2
elif case=='git-resolution':
 payload(b'G'*10000);observed=[]
 for i,mode in enumerate(('fail','empty')):
  if i:restart(i)
  write(cw/'gitmode',mode);p=red(extra={'PATH':str(tools)+os.pathsep+env['PATH']});observed.append((p.returncode,len(cuts(p)),p.stderr.count(b'G'*10000)))
 assert observed==[(0,0,2),(0,0,2)] and not logpath().exists(),observed
elif case=='control-git':
 payload(b'git control139\n');write(cw/'gitmode','fail');path=str(tools)+os.pathsep+env['PATH']
 p=run(str(proxy),'--version');q=red(extra={'PATH':path})
 assert p.returncode==0 and p.stdout.startswith(b'git version ') and q.returncode==0 and q.stderr.count(b'git control139\n')==2 and len(locks())==1
 # Existing binary does not ask the new path. Probe the injected failure directly too.
 t=run(str(proxy),'rev-parse','--git-path','shipcraft/output/red.log');assert t.returncode==73 and (cw/'githit').read_text()=='fail'
elif case=='node':
 payload(b'N'*10000);p=red()
 assert p.returncode==0 and json.loads(locks()[0].read_text())['failing_at_red']==['src/target139.test.ts::target139'] and len(cuts(p))==2 and logpath().read_bytes().count(b'N'*10000)==2
elif case=='go':
 payload(b'G'*10000);p=red()
 assert p.returncode==0 and json.loads(locks()[0].read_text())['failing_at_red']==['example.invalid/item139::TestTarget139'] and len(cuts(p))==len(entries()) and len(entries())>=2 and logpath().read_bytes().count(b'G'*10000)==len(entries())
else:raise AssertionError('unrouted '+case)
PY139
  pass
}
