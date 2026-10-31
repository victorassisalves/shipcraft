# Item 71: public init/probe contracts; all projects and observations are disposable.
item71_langs() { echo node; }
item71_cases() {
  local c stem ext
  for c in real ordinary single mixed mixed-convert default-runner no-check check-space check-quote check-cdpath canonical canonical-alias missing-file component-prefix outside-collision ascii-collision repeated-name empty-list no-files mixed-names unnamed null-name number-name unsafe-empty unsafe-option unsafe-space unsafe-quote unsafe-unicode safe-name precedence-mixed precedence-name precedence-outside large-output json-crlf json-escaped trigger-any environment order order-build-fails rollback rollback-cache foreign-hook no-start exit signal invalid-utf8 invalid-json object scalar element missing-field wrong-field relative late-relative late-invalid timeout timeout-pipe no-config nested-config symlink-config dangling-config directory-config fifo-config wrong-extension single-package existing other jest-only python go; do echo "v1-71.$c"; done
  for c in star question bracket close-bracket brace close-brace bang paren close-paren tab newline del c1; do echo "v1-71.folder-$c"; done
  for stem in vitest.workspace vitest.projects vitest.config vite.config; do
    for ext in ts mts cts js mjs cjs json; do echo "v1-71.trigger-$stem-$ext"; done
  done
  for c in red ci ci-log-fails; do echo "v1-71.check-fails-$c"; done
}
item71_case() {
  EXPECT="item 71: ${CASE#v1-71.}"
  v1_start codex claude
  must_accept 'item 71 public contract' cmd "$PY" - "${CASE#v1-71.}" "$(command -v shipcraft)" "$CW" <<'PY71'
import json,os,shlex,shutil,signal,subprocess,sys,time
from pathlib import Path
try: import tomllib
except ImportError: import tomli as tomllib
mode,binary,cw=sys.argv[1:]; binary=str(Path(binary).resolve()); cw=Path(cw).resolve()
def put(path,data,perm=None):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
 if perm is not None:p.chmod(perm)
def run(*args,ok=True,env=None,timeout=100):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,env=env,timeout=timeout)
 print('$',shlex.join(map(str,args)),'[rc='+str(p.returncode)+']\n'+(p.stdout+p.stderr).decode(errors='replace'),flush=True)
 if ok:assert p.returncode==0,('command failed',args,p.returncode)
 return p
def git(*args):return run('git',*args).stdout.decode().strip()
def commit(message):git('add','-A');git('commit','-qm',message)
def cfg():return tomllib.loads(Path('.shipcraft.toml').read_text())
def rows():return [json.loads(x) for x in record.read_text().splitlines()] if record.exists() else []
def esc(s):return s.replace('\\','\\\\').replace('\n','\\n').replace('\r','\\r').replace('\t','\\t')
root=cw/'workspace71';root.mkdir();os.chdir(root)
git('init','-q','-b','main');git('config','user.name','RED71');git('config','user.email','red71@example.invalid')
put('.gitignore','node_modules/\n')
folders=['packages/api','packages/web']
if mode in ('single','check-space','check-quote','check-cdpath') or mode.startswith('folder-') or mode.startswith('check-fails-'):folders=folders[:1]
if mode=='check-space':folders=['packages/api space']
if mode=='check-quote':folders=["packages/api'quoted $x;"]
if mode.startswith('folder-'):
 suffix={'star':'*','question':'?','bracket':'[','close-bracket':']','brace':'{','close-brace':'}','bang':'!','paren':'(','close-paren':')','tab':'\t','newline':'\n','del':'\x7f','c1':'\x85'}[mode[7:]]
 folders=['packages/api'+suffix]
manifest={'private':True,'type':'module','devDependencies':{'vitest':'2.1.9'}}
if mode!='single-package':manifest['workspaces']=['packages/*']
put('package.json',json.dumps(manifest));put('pnpm-workspace.yaml','packages:\n  - "packages/*"\n')
if mode=='single-package':Path('pnpm-workspace.yaml').unlink();folders=['.']
for i,folder in enumerate(folders):
 runner='jest' if mode=='jest-only' or (mode in ('mixed','mixed-convert') and i==1) else 'vitest'
 put(folder+'/package.json',json.dumps({'name':'pkg'+str(i),'private':True,'type':'module','devDependencies':{} if mode=='default-runner' else {runner:'*'}})) if folder!='.' else None
 put(folder+'/src/a.test.ts','import {it,expect} from "vitest";it("case71",()=>expect(0).toBe(1));\n')
 if mode not in ('no-check','real'):
  put(folder+'/tsconfig.json','{"compilerOptions":{"types":[]},"include":["src"]}\n')
if mode=='single-package':put('tsconfig.json','{"include":["src"]}')
trigger='vitest.config.ts'
if mode.startswith('trigger-') and mode!='trigger-any':
 stem,ext=mode[8:].rsplit('-',1);trigger=stem+'.'+ext
put(trigger,'export default {};\n')
if mode in ('no-config','nested-config','wrong-extension','symlink-config','dangling-config','directory-config','fifo-config'):
 Path(trigger).unlink()
 if mode=='nested-config':put('nested/vitest.config.ts','export default {};')
 if mode=='wrong-extension':put('vitest.config.tsx','export default {};')
 if mode in ('symlink-config','dangling-config'):
  if mode=='symlink-config':put(cw/'target71','export default {};')
  Path(trigger).symlink_to(cw/'target71')
 if mode=='directory-config':Path(trigger).mkdir()
 if mode=='fifo-config':os.mkfifo(trigger)
record=cw/'calls71.jsonl';answer=cw/'answer71';tools=cw/'tools71';tools.mkdir()
env=dict(os.environ,PATH=str(tools)+os.pathsep+os.environ['PATH'],ITEM71_RECORD=str(record),ITEM71_ANSWER=str(answer),ITEM71_MODE=mode,ITEM71_CACHE=str(cw/'probe-cache'),ITEM71_CUSTOM='inherited value',CDPATH=str(cw))
entries=[{'file':str(root/folder/'src/a.test.ts'),'projectName':['api','web'][i]} for i,folder in enumerate(folders)]
projects=['api','web'][:len(folders)];reasons={}
none='vitest listed none of its files';many='vitest listed its files in more than one project';unsafe='its vitest project name is not one shipcraft writes in a command';outside='its vitest project also lists files outside it';badfolder='its folder name cannot be written in a glob'
if mode in ('safe-name','json-escaped'):entries[0]['projectName']=projects[0]='@Scope/a.B_9-x'
if mode in ('unsafe-empty','unsafe-option','unsafe-space','unsafe-quote','unsafe-unicode'):
 entries[0]['projectName']={'unsafe-empty':'','unsafe-option':'--api','unsafe-space':'api web','unsafe-quote':"api'",'unsafe-unicode':'apí'}[mode];reasons[0]=unsafe
if mode in ('unnamed','null-name','number-name'):
 entries[0].pop('projectName')
 if mode!='unnamed':entries[0]['projectName']=None if mode=='null-name' else 7
 reasons[0]=unsafe
if mode in ('empty-list','no-files'):entries=entries[1:];reasons[0]=none
if mode=='empty-list':entries=[];reasons={i:none for i in range(len(folders))}
if mode in ('mixed-names','precedence-mixed'):
 entries.append(dict(entries[0],projectName='second' if mode=='mixed-names' else '-bad'));reasons[0]=many
if mode=='precedence-name':entries[0]['projectName']='bad space';entries.append({'file':str(cw/'external.test.ts'),'projectName':'bad space'});reasons[0]=unsafe
if mode in ('outside-collision','ascii-collision','precedence-outside'):
 entries.append({'file':str(cw/'external.test.ts'),'projectName':'API' if mode=='ascii-collision' else 'api'});reasons[0]=outside
if mode=='repeated-name':entries[1]['projectName']='API';reasons={0:outside,1:outside}
if mode=='component-prefix':
 entries=[{'file':str(root/'packages/api-other/a.test.ts'),'projectName':'api'},entries[1]];reasons[0]=none
if mode=='missing-file':entries[0]['file']=str(root/'packages/api/not-created.test.ts')
if mode in ('canonical','canonical-alias'):
 put(cw/'canonical-target.test.ts','outside');(root/'packages/api/linked.test.ts').symlink_to(cw/'canonical-target.test.ts')
 (cw/'alias-api71').symlink_to(root/'packages/api',target_is_directory=True)
 entries[0]['file']=str(cw/'alias-api71/src/a.test.ts')
 if mode=='canonical':entries.append({'file':str(root/'packages/api/linked.test.ts'),'projectName':'api'});reasons[0]=outside
if mode.startswith('folder-'):reasons[0]=badfolder
if mode=='precedence-outside':
 # The outside-name condition must precede the unsafe-folder condition.
 old=folders[0];new=old+'!';Path(old).rename(new);folders[0]=new
 entries[0]['file']=str(root/new/'src/a.test.ts')
if mode=='mixed':entries[1]['projectName']='api';projects[1]=None;reasons[0]=outside
if mode in ('order','order-build-fails'):
 put('tsconfig.json','{"files":[],"references":[{"path":"packages/api"}]}')
 put('packages/api/tsconfig.json','{"files":[],"references":[{"path":"../../projects/real"}]}')
 put('projects/real/tsconfig.json','{"compilerOptions":{"composite":true},"files":["value.ts"]}')
 put('projects/real/value.ts','export const value = 1;')
# This fake controls only the public list/error boundary and records actual argv/cwd/env.
wrapper=r'''
import json,os,signal,subprocess,sys,time
from pathlib import Path
args=sys.argv[1:];mode=os.environ['ITEM71_MODE'];root=Path.cwd()
row=dict(args=args,cwd=os.getcwd(),pid=os.getpid(),group=os.getpgrp(),stdin_null=os.path.samestat(os.fstat(0),os.stat('/dev/null')),cases=os.environ.get('SHIPCRAFT_CASES'),files=os.environ.get('SHIPCRAFT_FILES'),custom=os.environ.get('ITEM71_CUSTOM'),stdin=sys.stdin.buffer.read().hex(),written=[p for p in ('.shipcraft.toml','.shipcraft','AGENTS.md','CLAUDE.md') if Path(p).exists()])
with open(os.environ['ITEM71_RECORD'],'a') as f:f.write(json.dumps(row)+'\n')
if args==['--no','--','tsc','-b','.','packages/api'] or ('tsc' in args and '-b' in args):sys.exit(9 if mode=='order-build-fails' else 0)
if 'tsc' in args:
 print('package check failed71',file=sys.stderr);sys.exit(23)
assert args==['--no','--','vitest','list','--filesOnly','--json'],args
print('PROBE STDERR MUST BE DISCARDED71',file=sys.stderr)
if mode in ('rollback-cache','rollback'):Path(os.environ['ITEM71_CACHE']).write_text('keep cache71')
if mode=='exit':sys.exit(17)
if mode=='signal':os.kill(os.getpid(),signal.SIGTERM)
if mode.startswith('timeout'):
 child=subprocess.Popen([sys.executable,'-c','import time; from pathlib import Path; time.sleep(65); Path('+repr(os.environ['ITEM71_CACHE'])+').write_text("leaked group")'])
 Path(os.environ['ITEM71_ANSWER']+'.pid').write_text(str(child.pid))
 if mode=='timeout-pipe':sys.stdout.write('[]');sys.stdout.flush();sys.exit(0)
 time.sleep(120)
if mode=='large-output':sys.stdout.write(' '*1048576)
sys.stdout.buffer.write(Path(os.environ['ITEM71_ANSWER']).read_bytes())
'''
put(tools/'npx','#!'+sys.executable+'\n'+wrapper,0o755)
raw=json.dumps(entries).encode();how=None
invalid={'invalid-utf8':b'\xff','invalid-json':b'[{','object':b'{}','scalar':b'null','element':b'[1]','missing-field':b'[{}]','wrong-field':b'[{"file":7}]','relative':b'[{"file":"packages/api/a.test.ts","projectName":"api"}]'}
if mode in invalid:raw=invalid[mode];how='printed no file list'
if mode in ('late-relative','late-invalid'):
 raw=json.dumps(entries+[{'file':'relative.test.ts','projectName':'x'}] if mode=='late-relative' else entries+[False]).encode();how='printed no file list'
if mode in ('exit','signal','timeout','timeout-pipe','no-start'):how={'exit':'exited 17','signal':'was stopped by signal 15','timeout':'timed out after 60 s','timeout-pipe':'timed out after 60 s','no-start':'could not start'}[mode]
if mode=='json-crlf':raw=json.dumps(entries,indent=2).replace('\n','\r\n').encode()
if mode=='json-escaped':raw=json.dumps(entries).replace('/',r'\/').encode()
put(answer,raw)
if mode=='no-start':
 (tools/'npx').unlink()
 for tool in ('git','codex','claude'):(tools/tool).symlink_to(shutil.which(tool))
 env['PATH']=str(tools)
if mode=='environment':env.update(SHIPCRAFT_CASES='/inherited/cases',SHIPCRAFT_FILES='/inherited/files')
if mode=='check-cdpath':
 put(cw/'packages/api/sentinel','wrong directory');env['CDPATH']=str(cw)
if mode=='real':
 # Same cache-backed npm installation as item51; real, pinned Vitest output.
 run('npm','install','--no-audit','--no-fund','--loglevel=error',timeout=int(os.environ.get('SHIPCRAFT_ACCEPTANCE_NET_TIMEOUT','600')))
 (tools/'npx').unlink()
 put('vitest.config.ts','import {defineConfig} from "vitest/config";export default defineConfig({test:{maxWorkers:1,minWorkers:1,globalSetup:"./global71.ts"}});\n')
 put('vitest.workspace.ts','import {defineWorkspace} from "vitest/config";export default defineWorkspace(["packages/*/vitest.config.ts"]);\n')
 put('global71.ts','export default function(){process.env.ITEM71_ROOT="yes";}\n')
 for i,folder in enumerate(folders):
  put(folder+'/vitest.config.ts','import {defineProject} from "vitest/config";export default defineProject({test:{name:'+json.dumps(projects[i])+',root:import.meta.dirname}});\n')
  put(folder+'/src/value.ts','export const value=0;\n')
  put(folder+'/src/a.test.ts','import {it,expect} from "vitest";import {value} from "./value";it("case71",()=>{expect(process.env.ITEM71_ROOT).toBe("yes");expect(value).toBe('+('1' if i==0 else '0')+');});\n')
 listed=run('npx','--no','--','vitest','list','--filesOnly','--json');actual=json.loads(listed.stdout)
 assert len(actual)==2 and {r['projectName'] for r in actual}=={'api','web'},actual
 # Verify real root-wide globalSetup and failing assertion before init.
 realrun=run('npx','--no','--','vitest','run','--project=api',ok=False)
 assert realrun.returncode==1 and 'expected +0 to be 1' in (realrun.stdout+realrun.stderr).decode(), 'real fixture must fail its intended assertion'
if mode=='existing':put('.shipcraft.toml','# kept71\nlang="node"\ntest_command="false {junit}"\ntest_globs=["**/*.test.ts"]\n')
if mode=='python':
 Path('package.json').unlink();Path('pnpm-workspace.yaml').unlink();put('requirements.txt','pytest\n');put('tests/test_a.py','def test_a(): assert False\n')
if mode=='go':
 Path('package.json').unlink();Path('pnpm-workspace.yaml').unlink();put('go.mod','module example.com/item71\n\ngo 1.21\n');put('a_test.go','package item71\nimport "testing"\nfunc TestA(t *testing.T) {}\n')
if mode=='foreign-hook':put('.git/hooks/commit-msg','#!/bin/sh\necho foreign71\n',0o755)
if mode in ('rollback','rollback-cache'):put('.shipcraft','blocked71\n')
if mode=='trigger-any':
 Path(trigger).unlink();Path(trigger).symlink_to(cw/'missing-config');put('vite.config.json','{}')
put('.git/shipcraft/sentinel',b'keep71\r\n')
# Only disposable fixture Git writes; no repository hook/lock changes.
commit('fixture71 before init');base=git('rev-parse','HEAD')
args=['--lang','other','--command','runner {junit}','--glob','tests/**'] if mode=='other' else []
original=Path('.shipcraft.toml').read_bytes() if mode=='existing' else None
start=time.monotonic();p=run(binary,'init',*args,env=env,ok=mode not in ('foreign-hook','rollback','rollback-cache'));elapsed=time.monotonic()-start
out=p.stdout.decode();err=p.stderr.decode();calls=rows()
assert Path('.git/shipcraft/sentinel').read_bytes()==b'keep71\r\n' and not Path('.git/shipcraft/runs.jsonl').exists(),'init changed run state'
skip=mode in ('no-config','nested-config','wrong-extension','symlink-config','dangling-config','directory-config','fifo-config','single-package','existing','other','jest-only','python','go','foreign-hook')
if skip:
 assert not calls,'ineligible init ran probe'
 assert not any(s.startswith(('shipcraft: suite ','shipcraft: suites run inside')) for s in out.splitlines()),out
 if mode=='foreign-hook':
  assert p.returncode==1 and not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists()
  lines=(out+err).strip().splitlines();assert all(l.startswith(k) for l,k in zip(lines[-3:],('shipcraft refused:','Why:','Next:'))),lines
 elif mode=='existing':assert Path('.shipcraft.toml').read_bytes()==original
 elif mode not in ('other','python','go','single-package'):
  suites=cfg()['suite'];assert [s['root'] for s in suites]==folders,suites
 else:
  assert p.returncode==0
 print('CONTROL: unchanged eligibility/refusal');sys.exit()
if mode!='real':
 probes=[r for r in calls if 'vitest' in r['args']]
 assert len(probes)==(0 if mode=='no-start' else 1),'probe must run exactly once: '+repr(calls)
 for r in probes:
  assert r['cwd']==str(root) and r['args']==['--no','--','vitest','list','--filesOnly','--json'],r
  assert r['cases'] is None and r['files'] is None and r['custom']=='inherited value' and r['stdin']=='' and r['stdin_null'] and r['group']==r['pid'],r
  assert r['written']==(['.shipcraft'] if mode in ('rollback','rollback-cache') else []),'probe ran after init wrote files: '+repr(r)
 assert 'PROBE STDERR MUST BE DISCARDED71' not in out+err,'probe stderr leaked'
if mode in ('rollback','rollback-cache'):
 assert p.returncode==2 and Path('.shipcraft').read_text()=='blocked71\n'
 assert not Path('.shipcraft.toml').exists() and not Path('AGENTS.md').exists() and not Path('CLAUDE.md').exists()
 assert not Path('.git/hooks/commit-msg').exists() and not Path('.git/hooks/post-commit').exists()
 assert Path(env['ITEM71_CACHE']).read_text()=='keep cache71','rollback removed probe side effect'
 assert 'ready. Commit' not in out;sys.exit()
if mode.startswith('timeout'):
 assert 59<=elapsed<75,elapsed
 pid=int(Path(str(answer)+'.pid').read_text());time.sleep(.2)
 state=subprocess.run(['ps','-p',str(pid),'-o','stat='],capture_output=True,text=True).stdout.strip()
 assert not state or state.startswith('Z'),'probe descendant survived process-group kill: '+state
assert p.returncode==0
c=cfg();suites=c.get('suite',[])
assert len(suites)==len(folders),'converted workspace must keep named [[suite]], including singleton: '+repr(c)
assert [s['name'] for s in suites]==[Path(f).name for f in folders],suites
expected_lines=[]
for i,s in enumerate(suites):
 jest=mode in ('mixed','mixed-convert') and i==1
 convert=not how and i not in reasons and not jest
 expected_root='.' if convert else folders[i]
 assert s['root']==expected_root,('suite root must apply root config only when safe',s,expected_root)
 globs=['**/*.test.*','**/*.spec.*','**/__tests__/**','**/vitest.config.*','**/jest.config.*']
 assert s['globs']==[folders[i]+'/'+g for g in globs] if convert else s['globs']==globs,s
 if jest:
  assert 'jest' in s['command'] and '--project=' not in s['command'],s
 else:
  expected='npx --no -- vitest run '+('--project='+projects[i]+' ' if convert else '')+'--reporter=default --reporter=junit --outputFile.junit={junit}'
  assert s['command']==expected,(s,expected)
 has_check=mode not in ('no-check','real') and not (mode=='order' and i==0)
 if has_check:
  if convert:
   check=s.get('check','');parts=shlex.split(check)
   assert parts==['cd','./'+folders[i],'&&','npx','--no','--','tsc','--noEmit'],(check,parts)
   # Execute with a recording package-local tsc boundary; shell quote/cd semantics observable.
   if mode in ('check-space','check-quote','check-cdpath'):
    q=run('sh','-c',check,env=env,ok=False);assert q.returncode==23
    assert rows()[-1]['cwd']==str(root/folders[i]),rows()[-1]
  else:assert s.get('check','').endswith('tsc --noEmit'),s
 else:assert 'check' not in s,s
 if not how and not jest:
  name=esc(s['name'])
  expected_lines.append('shipcraft: suite '+name+(' runs from the repository root with --project='+projects[i]+', so the root vitest config applies' if convert else ' runs inside its package: '+reasons[i]))
if how:expected_lines=['shipcraft: suites run inside their packages: `vitest list` '+how+'; the root vitest config does not apply to them']
actual_lines=[s for s in out.splitlines() if s.startswith(('shipcraft: suite ','shipcraft: suites run inside'))]
if mode in ('folder-del','folder-c1'):
 assert len(actual_lines)==1 and not any(ord(c)<32 or 127<=ord(c)<=159 for c in actual_lines[0]) and actual_lines[0].startswith('shipcraft: suite api') and actual_lines[0].endswith(' runs inside its package: '+badfolder),actual_lines
 expected_lines=actual_lines
assert actual_lines==expected_lines,(actual_lines,expected_lines)
lines=out.splitlines();workspace='shipcraft: workspace node with '+str(len(folders))+' suite(s)'
assert workspace in lines and lines[lines.index(workspace)+1:lines.index(workspace)+1+len(expected_lines)]==expected_lines,out
if mode.startswith('order'):
 assert len(calls)==2 and 'tsc' in calls[0]['args'] and 'vitest' in calls[1]['args'],calls
 assert ('build' in c)==(mode=='order'),c
 judgement=next(i for i,l in enumerate(lines) if 'checks no file;' in l)
 build_notice=next(i for i,l in enumerate(lines) if '[build]' in l and 'checks no file;' not in l)
 assert build_notice<judgement,out
assert Path('.shipcraft/locks/.gitkeep').is_file() and Path('AGENTS.md').is_file() and Path('CLAUDE.md').is_file()
assert all(Path('.shipcraft/briefs',n).is_file() for n in ('red.md','green.md'))
assert all(os.access('.git/hooks/'+n,os.X_OK) for n in ('commit-msg','post-commit'))
assert lines[-1]=='CI runs on this machine through shipcraft pr. To run it on GitHub, see shipcraft docs/github-ci.md.'
if mode=='real':
 commit('chore: generated init71');git('checkout','-qb','feature/item71')
 # Mark only api as changed: root-relative suite globs must retain ownership.
 put('packages/api/src/a.test.ts',Path('packages/api/src/a.test.ts').read_text()+'\n// fresh RED71\n')
 run(binary,'red',env=env)
 locks=list(Path('.shipcraft/locks').glob('*.json'));assert len(locks)==1
 lock=json.loads(locks[0].read_text());assert lock['state']=='open'
 assert len(lock['failing_at_red'])==1 and all(x.startswith('api:') for x in lock['failing_at_red']),lock
 assert 'packages/api/src/a.test.ts' in lock['files'] and 'packages/web/src/a.test.ts' in lock['files'],lock
 assert 'vitest.config.ts' not in lock['files'] and 'vitest.workspace.ts' not in lock['files'],lock
if mode.startswith('check-fails-'):
 commit('chore: generated init71');base=git('rev-parse','HEAD');put('value71','changed\n');commit('feat: change71')
 if mode.endswith('log-fails'):Path('.git/shipcraft/runs.jsonl').mkdir()
 phase='red' if mode.endswith('-red') else 'ci';before=len(rows())
 refused=run(binary,phase,*(['--base',base] if phase=='ci' else []),env=env,ok=False)
 assert refused.returncode==1
 assert len(rows())==before+1 and 'tsc' in rows()[-1]['args'] and rows()[-1]['cwd']==str(root/folders[0]),rows()
 diagnostic=(refused.stdout+refused.stderr).decode();check=suites[0]['check']
 assert 'the check `'+check+'` failed (exited with 23): package check failed71' in diagnostic,diagnostic
 assert '`.`' in diagnostic or "'.'" in diagnostic or '"."' in diagnostic,diagnostic
 assert 'package check failed71' in refused.stderr.decode() and not list(Path('.shipcraft/locks').glob('*.json'))
 if phase=='ci' and not mode.endswith('log-fails'):
  row=json.loads(Path('.git/shipcraft/runs.jsonl').read_text().splitlines()[-1]);assert row['code']=='no-report',row
PY71
  pass
}
