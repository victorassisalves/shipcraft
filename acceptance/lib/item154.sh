# Item 154: vitest's config graph and setup files, through public commands only.
item154_langs() { echo node; }
item154_cases() {
  local c
  for c in repro real-equals short quoted wrapper multiple end-options no-config shell-tokens decoy npm-script subshell nonvitest \
    cli-root cli-root-wins graph-roots ancestor versions walk-order import-setup module-link module-value redo \
    repeated no-value non-path absolute folder-change shell-unreadable wrapper-unreadable config-path ignored-config root-path suite-order \
    hook-added ci-added ancestor-added parent legacy sibling; do echo "v1-154.$c"; done
}
item154_case() {
  EXPECT="item 154: ${CASE#v1-154.}"; v1_start
  must_accept 'vitest support contract' cmd "$PY" - "${CASE#v1-154.}" "$(command -v shipcraft)" <<'PY154'
import hashlib,json,os,shlex,subprocess,sys
from pathlib import Path
case,binary=sys.argv[1:];binary=str(Path(binary).resolve())
def run(*args,ok=True):
 p=subprocess.run(list(map(str,args)),capture_output=True,text=True,timeout=120)
 print('$',shlex.join(map(str,args)),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 if ok:assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr)
 return p
def git(*args):return run('git',*args).stdout.strip()
def write(path,text):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
def commit(message):git('add','-A');return run('git','commit','-qm',message)
def lock():
 paths=list(Path('.shipcraft/locks').glob('*.json'));assert len(paths)==1,paths
 return paths[0],json.loads(paths[0].read_text())
def rows():return [json.loads(s) for s in Path('.git/shipcraft/runs.jsonl').read_text().splitlines()]
home=Path.cwd().resolve()
PREFIX='shipcraft: red also locked what vitest reads beside the tests: '
GLOBS=['**/*.test.*','**/*.spec.*','**/__tests__/**','**/vitest.config.*','**/jest.config.*']
COMMAND='node_modules/.bin/vitest run --reporter=default --reporter=junit --outputFile.junit={junit}'
def fresh(name,real=False,command=COMMAND):
 root=home/name;root.mkdir();os.chdir(root)
 git('init','-q','-b','main');git('config','user.name','RED154');git('config','user.email','red154@example.invalid')
 write('.gitignore','node_modules/\ntools/\nignored/\n')
 write('package.json','{"private":true,"type":"module","devDependencies":{"vitest":"'+os.environ.get("SHIPCRAFT_VITEST_VERSION","5.0.4")+'"}}\n')
 write('src/sum.ts','export function sum(){throw new Error("stub154");}\n')
 write('src/sum.test.ts','import {it,expect} from "vitest";import {sum} from "./sum";it("adds",()=>expect(sum()).toBe(3));\n')
 write('src/test-setup.ts','// no mock\n')
 if real:
  run('npm','install','--offline','--no-audit','--no-fund','--loglevel=error')
 else:
  write('node_modules/.bin/vitest',FAKE);Path('node_modules/.bin/vitest').chmod(0o755)
  write('tools/jest',FAKE);Path('tools/jest').chmod(0o755)
  os.environ['TRACE154']=str(root/'tools/trace')
 write('.shipcraft.toml','shipcraft_min="0.0"\nlang="node"\nrunner="vitest"\ntest_command='+json.dumps(command)+'\ntest_globs='+json.dumps(GLOBS)+'\n[execution]\nci="local"\nreview="off"\n')
 return root
def install():run(binary,'init','--lang','node');commit('install154')
def red(*args):
 p=run(binary,'red',*args);return p,lock()[1]
def snap(message):
 # History under CI must contain the escape independently of the live hook.
 git('add','-A');tree=git('write-tree');oid=git('commit-tree',tree,'-p','HEAD','-m',message);git('update-ref','-m','fixture154: '+message,'HEAD',oid);return oid
def green(path,text):
 write(path,text);git('add',path);return run('git','commit','-qm','GREEN154',ok=False)
def config(text,path='vitest.config.ts'):write(path,text)
def refused(p,code,layer='red'):
 lines=(p.stdout+p.stderr).strip().splitlines()[-3:]
 assert p.returncode==1 and len(lines)==3 and all(l.startswith(t) for l,t in zip(lines,('shipcraft refused:','Why:','Next:'))),(p.returncode,lines)
 assert [r for r in rows() if r['layer']==layer][-1]['code']==code,rows()
 return lines
REPORT='--reporter=default --reporter=junit --outputFile.junit={junit}'
BIN='node_modules/.bin/vitest'
MOCK='import {vi} from "vitest";vi.mock("./sum",()=>({sum:()=>3}));\n'
SETUP='// MOCK154\n'
LOG=Path('.git/shipcraft/runs.jsonl')
LOCK_DIR=Path('.shipcraft/locks')

def vc(flags='',exe=BIN):
 return f'{exe} run {flags} {REPORT}'

def digest(path):
 return 'sha256:'+hashlib.sha256(Path(path).read_bytes()).hexdigest()

def files(d,paths,test='src/sum.test.ts'):
 return d['files']=={p:digest(p) for p in ['.shipcraft.toml',test,*paths]}

def trace():
 return [json.loads(s) for s in Path(os.environ['TRACE154']).read_text().splitlines()]

def suite_config(*suites):
 text='shipcraft_min="0.0"\n[execution]\nci="local"\nreview="off"\n'
 for name,root,command in suites:
  text+='[[suite]]\nname='+json.dumps(name)+'\nroot='+json.dumps(root)+'\ncommand='+json.dumps(command)+'\nglobs='+json.dumps(GLOBS)+'\n'
 write('.shipcraft.toml',text)

def nest(folder):
 Path(folder).mkdir(parents=True)
 Path('src').rename(Path(folder)/'src')

def boot(path,setup='./src/unit-setup.ts'):
 config('export default {test:{setupFiles:['+json.dumps(setup)+']}};',path)

def refuse_lines(p):
 return [line for line in (p.stdout+p.stderr).splitlines(keepends=True)
         if line.startswith(('shipcraft refused:','Why:','Next:'))]

def command_lines(key,why):
 return [
  f'shipcraft refused: could not read the vitest config of {key}: {why}\n',
  'Why: red locks the config vitest reads and the setup files it names; a config it cannot name could change what every locked case sees\n',
  "Next: in .shipcraft.toml, give vitest's --config and --root at most once each, as plain relative paths, with no cd before vitest, then run red again\n",
 ]

def module_lines(path,why):
 return [
  f'shipcraft refused: could not read the vitest setup files of {path}: {why}\n',
  'Why: red locks the setup files it can name; one it cannot name could change what every locked case sees\n',
  f'Next: in {path}, write setupFiles and globalSetup as string literals or arrays of them, with paths relative to the file and no root key, then run red again\n',
 ]

def added_lines(path,place,lock_path):
 return [
  f'shipcraft refused: runner config {path} was added {place} with lock {lock_path} open\n',
  'Why: vitest reads its settings from this file, so adding one during GREEN can change the judge mid-game\n',
  f'Next: remove {path}; if the suite needs it, add it in a RED (shipcraft red --redo) or after the cycle closes\n',
 ]

def block_log():
 LOG.unlink()
 LOG.mkdir()

def refusal_observation(p):
 return (p.returncode,refuse_lines(p),rows()[-1].get('code'),
         list(LOCK_DIR.glob('*.json')),PREFIX in p.stdout,bool(trace()),
         Path('.git/shipcraft/output/red.log').is_file())

def parent_layout(root,command,config_path):
 fresh('parent-layout')
 nest(root)
 suite_config(('ui',root,command))
 config('export default {};',config_path)
 install()

FAKE=r'''#!/usr/bin/env python3
import json,os,re,sys
from pathlib import Path
import xml.etree.ElementTree as E

def read(path):
 return path.read_text() if path and path.is_file() else ''

words=sys.argv[1:]
report=next(a.split('=',1)[1] for a in words if a.startswith('--outputFile.junit='))
flags=iter(words)
root=Path.cwd()
named=None
default=True
for arg in flags:
 if arg=='--':
  break
 key,eq,value=arg.partition('=')
 if key=='--no-config':
  named,default=None,False
 if key in ('--config','-c','--root','-r'):
  value=value if eq else next(flags,'')
  if key in ('--config','-c'):
   named,default=value or None,False
  elif value and not value.startswith('-'):
   root=Path.cwd()/value

root=Path(os.path.abspath(root))
chosen=root/named if named else None
if default and Path(sys.argv[0]).name=='vitest':
 for folder in (root,*root.parents):
  candidates=(folder/(stem+ext) for stem in ('vitest.config.','vite.config.')
              for ext in ('ts','mts','cts','js','mjs','cjs'))
  chosen=next((p for p in candidates if p.is_file()),None)
  if chosen or folder==Path(os.environ['TRACE154']).parent.parent:
   break
body=read(chosen)
match=re.search(r'(?:setupFiles|globalSetup)["\x27]?\s*:\s*\[?\s*["\x27`]([^"\x27`]+)',body)
setup=root/match[1] if match else None
passed='PASS154' in read(Path('src/sum.ts')) or 'MOCK154' in read(setup)
t=E.Element('testsuites')
s=E.SubElement(t,'testsuite',name='src/sum.test.ts',tests='1',failures=str(int(not passed)))
c=E.SubElement(s,'testcase',classname='src/sum.test.ts',name='adds',file='src/sum.test.ts')
if not passed:
 E.SubElement(c,'failure',message='stub154').text='stub154'
E.ElementTree(t).write(report,encoding='utf-8',xml_declaration=True)
trace=Path(os.environ['TRACE154'])
trace.parent.mkdir(exist_ok=True)
with trace.open('a') as f:
 f.write(json.dumps({'runner':Path(sys.argv[0]).name,'passed':passed,'root':str(root.resolve()),
                     'config':str(chosen.resolve()) if chosen else None,
                     'setup':str(setup.resolve()) if setup else None,'args':words})+'\n')
sys.exit(0 if passed else 1)
'''

if case=='repro':
 fresh('repro',real=True,command=COMMAND.replace(' run ', ' run --config config/vitest.unit.ts '))
 config('export default {test:{setupFiles:["./src/unit-setup.ts"]}};', 'config/vitest.unit.ts')
 write('src/unit-setup.ts','// no mock\n')
 install();p,d=red();commit('RED154')
 assert d['failing_at_red']==['src/sum.test.ts::adds'] and 'stub154' in p.stderr
 q=green('src/unit-setup.ts','import {vi} from "vitest";vi.mock("./sum",()=>({sum:()=>3}));\n')
 print('REPRODUCTION: GREEN rc='+str(q.returncode)+'; stub='+Path('src/sum.ts').read_text().strip()+'; lock='+lock()[1]['state'],flush=True)
 assert q.returncode==1,'setup-only GREEN was accepted; expected test-changed'
 assert 'src/unit-setup.ts' in refused(q,'test-changed','hook')[0] and lock()[1]['state']=='open'
 assert set(d['files'])=={'.shipcraft.toml','src/sum.test.ts','config/vitest.unit.ts','src/unit-setup.ts'},d['files']
 assert (PREFIX+'config/vitest.unit.ts, src/unit-setup.ts\n') in p.stdout,p.stdout
elif case=='real-equals':
 fresh('equals',real=True,command=vc('--config=config/vitest.unit.ts -r .'))
 boot('config/vitest.unit.ts');write('src/unit-setup.ts','// no mock\n');install()
 p,d=red();commit('RED154')
 assert files(d,['config/vitest.unit.ts','src/unit-setup.ts'])
 q=green('src/unit-setup.ts',MOCK)
 assert q.returncode==1,'--config= with -r . let the setup-only GREEN through'
 assert 'src/unit-setup.ts' in refused(q,'test-changed','hook')[0] and lock()[1]['state']=='open'
 assert (PREFIX+'config/vitest.unit.ts, src/unit-setup.ts\n') in p.stdout
elif case=='short':
 observed=[]
 for i,(flags,named) in enumerate((('-c u.ts','u.ts'),('-c=cfg/u.mts','cfg/u.mts'))):
  fresh(str(i),command=vc(flags));boot(named);write('src/unit-setup.ts','// no mock\n');install()
  p,d=red()
  observed.append((files(d,[named,'src/unit-setup.ts']),trace()[0]['config']==str(Path(named).resolve()),d['files']))
 # Later persistence failures must not lose discovery or print an unwritten lock.
 fresh('log-fails',command=vc('-c cfg/u.ts'));boot('cfg/u.ts');write('src/unit-setup.ts','// no mock\n')
 install();block_log();p,d=red()
 observed.append((files(d,['cfg/u.ts','src/unit-setup.ts']),
                  PREFIX+'cfg/u.ts, src/unit-setup.ts\n' in p.stdout and LOG.is_dir(),d['files']))
 fresh('write-fails',command=vc('-c cfg/u.ts'));boot('cfg/u.ts');write('src/unit-setup.ts','// no mock\n')
 install();LOCK_DIR.chmod(0o555)
 try:q=run(binary,'red',ok=False)
 finally:LOCK_DIR.chmod(0o755)
 assert q.returncode==2 and not list(LOCK_DIR.glob('*.json')) and PREFIX not in q.stdout
 assert rows()[-1]['result']=='error' and trace() and Path('.git/shipcraft/output/red.log').is_file()
 assert all(match and opened_config for match,opened_config,_ in observed),observed
elif case=='quoted':
 fresh('quoted',command=vc("--config 'cfg dir/'\"unit.ts\""))
 boot('cfg dir/unit.ts');write('src/unit-setup.ts','// no mock\n');install();p,d=red()
 assert files(d,['cfg dir/unit.ts','src/unit-setup.ts']),d['files']
elif case=='wrapper':
 fresh('wrapper',command=vc('--config u.ts','env CI=1 npx --no -- vitest'))
 boot('u.ts');write('src/unit-setup.ts','// no mock\n');install();p,d=red()
 assert files(d,['u.ts','src/unit-setup.ts']),d['files']
elif case=='multiple':
 # The first report passes so the second invocation executes and writes the failing report.
 fresh('multiple',command=vc('-c cfg/a.ts')+' && '+vc('--config=cfg/b.ts'))
 boot('cfg/a.ts','./first.ts');boot('cfg/b.ts','./second.ts')
 write('first.ts',SETUP);write('second.ts','// no mock\n');install();p,d=red()
 assert [x['passed'] for x in trace()[:2]]==[True,False]
 assert files(d,['cfg/a.ts','cfg/b.ts','first.ts','second.ts']),d['files']
elif case=='end-options':
 fresh('end-options',command=vc()+' -- --config decoy.ts --root /abs')
 config('export default {setupFiles:dynamic};','decoy.ts')
 config('export default {};')
 install();p,d=red()
 assert files(d,['vitest.config.ts']) and PREFIX not in p.stdout
 assert trace()[0]['args'][-5:]==['--','--config','decoy.ts','--root','/abs']
 assert trace()[0]['config']==str(Path('vitest.config.ts').resolve())
elif case=='no-config':
 fresh('no-config',command=vc('--no-config'))
 write('src/test-setup.ts',SETUP);boot('vitest.config.ts','./src/test-setup.ts');install()
 p,d=red();commit('RED154')
 assert files(d,['vitest.config.ts','src/test-setup.ts']) and trace()[0]['config'] is None
 assert trace()[0]['passed'] is False and d['failing_at_red']==['src/sum.test.ts::adds']
 assert (PREFIX+'src/test-setup.ts\n') in p.stdout
elif case=='shell-tokens':
 command='# vitest --config ignored.ts\nif true; then CI=1 '+BIN+' \\'+'\n\t-c u.ts '+REPORT+' 2>&1; fi'
 fresh('shell',command=command)
 boot('u.ts');write('src/unit-setup.ts','// no mock\n');install();p,d=red()
 assert files(d,['u.ts','src/unit-setup.ts']),d['files']
elif case=='decoy':
 command='printf "%s\\n" vitest --config decoy.ts > ignored-trace; >vitest '+vc()+' 2>&1'
 fresh('decoy',command=command)
 write('.gitignore',Path('.gitignore').read_text()+'ignored-trace\n/vitest\n')
 config('export default {setupFiles:dynamic};','decoy.ts');install();p,d=red()
 assert Path('ignored-trace').read_bytes()==b'vitest\n--config\ndecoy.ts\n'
 assert Path('vitest').is_file() and trace()[0]['runner']=='vitest'
 assert files(d,[]) and PREFIX not in p.stdout
elif case=='npm-script':
 fresh('npm-script',command='npm run test:vitest -- '+REPORT)
 write('package.json',json.dumps({'private':True,'scripts':{'test:vitest':BIN+' run -c scripted.ts'}}))
 boot('scripted.ts');write('src/unit-setup.ts','// no mock\n');install();p,d=red()
 assert files(d,[]) and PREFIX not in p.stdout
 assert trace()[0]['config']==str(Path('scripted.ts').resolve())
elif case=='subshell':
 fresh('subshell',command='(cd tools && true); '+vc('-c u.ts'))
 boot('u.ts');write('src/unit-setup.ts','// no mock\n');install();p,d=red()
 assert files(d,['u.ts','src/unit-setup.ts']),d['files']
elif case=='nonvitest':
 fresh('nonvitest',command='tools/jest --config cfg/u.ts '+REPORT)
 config('export default {setupFiles:dynamic};','cfg/u.ts');install();p,d=red()
 assert files(d,[]) and PREFIX not in p.stdout
 assert trace()[0]['runner']=='jest' and trace()[0]['config']==str(Path('cfg/u.ts').resolve())
elif case=='cli-root':
 fresh('cli-root',command=vc("--root='my web'"))
 boot('my web/vitest.config.ts','./setup.ts');write('my web/setup.ts','// no mock\n')
 write('setup.ts','// unrelated\n');install();p,d=red()
 assert files(d,['my web/vitest.config.ts','my web/setup.ts'])
 assert trace()[0]['root']==str(Path('my web').resolve())
 # A suite rooted at the repository already sees the first config through item 132.
 # Add a second suite whose root and vitest root diverge to isolate the new behavior.
 fresh('cli-root-nested');nest('client')
 suite_config(('ui','./client//',vc('-r=../web','../'+BIN)))
 boot('web/vitest.config.ts','./setup.ts');write('web/setup.ts','// no mock\n');install();p,d=red()
 assert files(d,['web/vitest.config.ts','web/setup.ts'],'client/src/sum.test.ts'),d['files']
elif case=='cli-root-wins':
 fresh('cli-root-wins',command=vc('--root web --config ../config/u.ts'))
 config('export default {root:import.meta.dirname,test:{setupFiles:"./setup.ts"}};','config/u.ts')
 write('web/setup.ts','// no mock\n');write('config/setup.ts','// wrong root\n');install();p,d=red()
 assert files(d,['config/u.ts','web/setup.ts']),d['files']
 assert trace()[0]['config']==str(Path('config/u.ts').resolve())
 assert trace()[0]['setup']==str(Path('web/setup.ts').resolve())
elif case=='graph-roots':
 observed=[]
 for i,(text,extra) in enumerate((
  ('export default {test:{setupFiles:"./setup.ts"},root:import.meta.dirname};',[]),
  ('import "./layers/root";export default {test:{setupFiles:"./setup.ts"}};',['config/layers/root.ts','config/layers/setup.ts']),
 )):
  fresh(str(i),command=vc('--config config/u.ts'));config(text,'config/u.ts')
  write('setup.ts','// invocation\n');write('config/setup.ts','// module\n')
  if extra:
   config('\ufeffexport default {test:{root /*key*/:\u2028__dirname}};','config/layers/root.ts')
   write('config/layers/setup.ts','// imported root\n')
  install();p,d=red()
  wanted=['config/u.ts','setup.ts',*(extra or ['config/setup.ts'])]
  observed.append((files(d,wanted),d['files']))
 for i,value in enumerate(("'.'","'./'")):
  fresh('dot-'+str(i),command=vc('-c config/u.ts'))
  config('export default {root:'+value+',test:{globalSetup:"./setup.ts"}};','config/u.ts')
  write('setup.ts','// invocation\n');write('config/setup.ts','// wrong root\n');install();p,d=red()
  observed.append((files(d,['config/u.ts','setup.ts']),d['files']))
 assert all(match for match,_ in observed),observed
elif case=='ancestor':
 fresh('ancestor');nest('web')
 suite_config(('ui','web',vc(exe='../'+BIN)))
 boot('vitest.config.ts');write('web/src/unit-setup.ts','// nested\n')
 write('src/unit-setup.ts','// wrong root\n');install();p,d=red()
 assert files(d,['vitest.config.ts','web/src/unit-setup.ts'],'web/src/sum.test.ts'),d['files']
elif case=='versions':
 observed=[]
 for i,(exe,local,up,walks) in enumerate((
  ('../'+BIN,'5.0.4','4.0.5',True),
  (BIN,'5.0.4','4.0.5',False),
  (BIN,'00010.1.0',None,False),
  ('env vitest','5',None,False),
  ('env vitest','not JSON','5.0.4',True),
  ('env vitest','05',None,False),
  ('env vitest',5,'5.0.4',True),
  ('env vitest','v5.0.4','5.0.4',True),
 )):
  fresh(str(i));nest('web');suite_config(('ui','web',vc(exe=exe)))
  boot('vitest.config.ts');write('web/src/unit-setup.ts','// nested\n')
  write('web/node_modules/vitest/package.json',local if local=='not JSON' else json.dumps({'version':local}))
  if up is not None:write('node_modules/vitest/package.json',json.dumps({'version':up}))
  write('web/node_modules/.bin/vitest',FAKE);Path('web/node_modules/.bin/vitest').chmod(0o755)
  previous=os.environ['PATH'];os.environ['PATH']=str(Path('web/node_modules/.bin').resolve())+os.pathsep+previous
  try:install();p,d=red()
  finally:os.environ['PATH']=previous
  want=['vitest.config.ts','web/src/unit-setup.ts'] if walks else []
  observed.append((files(d,want,'web/src/sum.test.ts'),(exe,local,up,walks),d['files']))
 assert all(match for match,_,_ in observed),observed
elif case=='walk-order':
 observed=[]
 for i,(selected,losers) in enumerate((
  ('vitest.config.mjs',['vite.config.ts','vitest.config.cjs']),
  ('web/vite.config.ts',['vitest.config.ts']),
  ('vite.config.mts',['vite.config.cts','vite.config.js']),
 )):
  fresh(str(i));nest('web');suite_config(('ui','web',vc(exe='../'+BIN)))
  boot(selected,'./src/unit-setup.ts');write('web/src/unit-setup.ts','// nested\n')
  for loser in losers:config('export default {};',loser)
  install();p,d=red()
  observed.append((files(d,[selected,'web/src/unit-setup.ts'],'web/src/sum.test.ts'),d['files']))
 assert all(match for match,_ in observed),observed
elif case=='import-setup':
 fresh('import-setup',command=vc('-c config/u.ts'))
 config('import "./nested/base";export default {};','config/u.ts')
 config('export {default} from "./leaf";','config/nested/base.ts')
 config('\ufeffexport default {test:{"setupFiles" /* k */\r:\u2028\u2029[\x60./boot\x60,],\r\n}};','config/nested/leaf.mjs')
 for suffix in ('','.ts','.tsx','.mts','.cts','.js','.jsx','.mjs','.cjs'):
  write('boot'+suffix,'// setup\n')
 write('config/nested/boot.ts','// wrong root\n');install();p,d=red()
 assert files(d,['config/u.ts','config/nested/base.ts','config/nested/leaf.mjs',
                 'boot','boot.ts','boot.tsx','boot.mts','boot.cts','boot.js','boot.jsx','boot.mjs','boot.cjs']),d['files']
elif case=='module-link':
 fresh('module-link',command=vc('-c config/u.ts'))
 config('export default {};','config/base.ts');Path('config/u.ts').symlink_to('base.ts')
 install();p=run(binary,'red',ok=False)
 assert refusal_observation(p)==(1,module_lines('config/u.ts','config/u.ts is a symbolic link'),'setup-unreadable',[],False,True,True)
elif case=='module-value':
 fresh('module-value',command=vc('-c config/u.ts'))
 config('import "./z";export default {test:{setupFiles:dynamic}};','config/u.ts')
 config('export default {root:"elsewhere"};','config/z.ts')
 install();p=run(binary,'red',ok=False)
 assert refusal_observation(p)==(1,module_lines('config/u.ts','setupFiles is not a string or an array of strings'),'setup-unreadable',[],False,True,True)
elif case=='redo':
 fresh('redo',command=vc('-c config/u.ts'));config('export default {};','config/u.ts')
 install();old,d0=red();commit('RED154')
 boot('config/u.ts');write('src/unit-setup.ts','// no mock\n');p,d=red('--redo')
 assert files(d,['config/u.ts','src/unit-setup.ts']),d['files']
 lines=p.stdout.splitlines(keepends=True)
 index=next(i for i,line in enumerate(lines) if line.startswith('shipcraft: RED redone at'))
 assert lines[index-1]==PREFIX+'config/u.ts, src/unit-setup.ts\n'
 assert lines[index-2].startswith('shipcraft: controls:') and ': 4 file(s),' in lines[index]
 commit('redo154')
 lf,redo_doc=lock();before=lf.read_bytes()
 config('export default {setupFiles:unknown};','config/u.ts');q=run(binary,'red','--redo',ok=False)
 assert q.returncode==1 and refuse_lines(q)==module_lines('config/u.ts','setupFiles is not a string or an array of strings')
 assert rows()[-1]['code']=='setup-unreadable' and rows()[-1]['redo'] is True
 assert lock()[0].read_bytes()==before and PREFIX not in q.stdout
elif case=='repeated':
 observed=[]
 for i,(flag,why) in enumerate((
  ('-c a.ts -c b.ts','--config is given more than once'),
  ('--no-config -c a.ts','--config is given more than once'),
  ('-r . --root=.','--root is given more than once'),
  ('-c a.ts -c -r','--config is given more than once'),
 )):
  fresh(str(i),command=vc(flag));install();p=run(binary,'red',ok=False)
  observed.append((refusal_observation(p),command_lines('test_command',why)))
 assert all(actual==(1,lines,'setup-unreadable',[],False,True,True) for actual,lines in observed),observed
elif case=='no-value':
 observed=[]
 for i,(command,why) in enumerate((
  (vc()+' -r','-r has no value'),
  (vc("--config=''"),'--config has no value'),
  (vc('-c --root .'),'-c has no value'),
  (vc("--root ''"),'--root has no value'),
 )):
  fresh(str(i),command=command);install();p=run(binary,'red',ok=False)
  observed.append((refusal_observation(p),command_lines('test_command',why)))
 assert all(actual==(1,lines,'setup-unreadable',[],False,True,True) for actual,lines in observed),observed
elif case=='non-path':
 observed=[]
 for i,(flags,why) in enumerate((
  ("--config '$CFG'",'--config $CFG is not a plain path'),
  ("-c 'a*b?.ts'",'-c a*b?.ts is not a plain path'),
  ("-r='~web'",'-r ~web is not a plain path'),
  ("--root='web[12]'",'--root web[12] is not a plain path'),
  ("--config='\x60pwd\x60/a.ts'",'--config `pwd`/a.ts is not a plain path'),
 )):
  fresh(str(i),command=vc(flags));install();p=run(binary,'red',ok=False)
  observed.append((refusal_observation(p),command_lines('test_command',why)))
 assert all(actual==(1,lines,'setup-unreadable',[],False,True,True) for actual,lines in observed),observed
elif case=='absolute':
 observed=[]
 for i,(flags,why) in enumerate((
  ('--root /abs','--root /abs is an absolute path'),
  ('-c=/abs/u.ts','-c /abs/u.ts is an absolute path'),
 )):
  fresh(str(i),command=vc(flags));install();p=run(binary,'red',ok=False)
  observed.append((refusal_observation(p),command_lines('test_command',why)))
 assert all(actual==(1,lines,'setup-unreadable',[],False,True,True) for actual,lines in observed),observed
elif case=='folder-change':
 observed=[]
 for i,(prefix,why) in enumerate((
  ('cd tools && cd ..; ','cd runs before vitest'),
  ('pushd tools >/dev/null; popd >/dev/null; ','pushd runs before vitest'),
 )):
  fresh(str(i),command=prefix+vc('-r /abs'));install();p=run(binary,'red',ok=False)
  observed.append((refusal_observation(p),command_lines('test_command',why)))
 assert all(actual==(1,lines,'setup-unreadable',[],False,True,True) for actual,lines in observed),observed
elif case=='shell-unreadable':
 observed=[]
 for i,(command,why) in enumerate((
  (vc('-c /abs')+'; exit $?\nprintf "unfinished','its quotes do not close'),
  (vc()+'; exit $?\nprintf %s '+chr(92),'its quotes do not close'),
  (vc('-r /abs')+" <<'EOF154'\nvitest --config decoy.ts\nEOF154",'it holds a here-document'),
 )):
  fresh(str(i),command=command);install();p=run(binary,'red',ok=False)
  observed.append((refusal_observation(p),command_lines('test_command',why)))
 assert all(actual==(1,lines,'setup-unreadable',[],False,True,True) for actual,lines in observed),observed
elif case=='wrapper-unreadable':
 observed=[]
 for i,(exe,why) in enumerate((
  ('env -u NODE_OPTIONS '+BIN,'env runs vitest in a form Shipcraft does not read'),
  ('nice -n 10 '+BIN,'nice runs vitest in a form Shipcraft does not read'),
 )):
  fresh(str(i),command=vc(exe=exe));install();p=run(binary,'red',ok=False)
  observed.append((refusal_observation(p),command_lines('test_command',why)))
 assert all(actual==(1,lines,'setup-unreadable',[],False,True,True) for actual,lines in observed),observed
elif case=='config-path':
 observed=[]
 for i,(flags,why) in enumerate((
  ('-c u.ts','--config u.ts names no file in the repository'),
  ('--config ignored/u.ts','--config ignored/u.ts names no file in the repository'),
  ('-c=config/u.json','--config config/u.json is not a .ts, .mts, .cts, .js, .mjs or .cjs file'),
  ('-c ../u.ts','--config ../u.ts names a file above the repository root'),
 )):
  fresh(str(i),command=vc(flags));write('config/u.json','{}');config('export default {};','ignored/u.ts')
  install();p=run(binary,'red',ok=False)
  observed.append((refusal_observation(p),command_lines('test_command',why)))
 assert all(actual==(1,lines,'setup-unreadable',[],False,True,True) for actual,lines in observed),observed
elif case=='ignored-config':
 observed=[]
 for i,linked in enumerate((False,True)):
  fresh(str(i),command=vc());write('.gitignore',Path('.gitignore').read_text()+'/vitest.config.ts\n')
  config('export default {};','vite.config.ts')
  if linked:Path('vitest.config.ts').symlink_to('vite.config.ts')
  else:config('export default {};')
  install();p=run(binary,'red',ok=False)
  observed.append(refusal_observation(p))
 lines=command_lines('test_command','vitest.config.ts is a vitest config git does not list')
 assert all(actual==(1,lines,'setup-unreadable',[],False,True,True) for actual in observed),observed
elif case=='root-path':
 observed=[]
 for i,(flags,why) in enumerate((
  ('-r=.. -c missing.ts','--root .. names a folder above the repository root'),
  ('--root link/sub -c missing.ts','--root link/sub goes through a symbolic link'),
 )):
  fresh(str(i),command=vc(flags));write('web/sub/keep','tracked\n');Path('link').symlink_to('web')
  install();p=run(binary,'red',ok=False)
  observed.append((refusal_observation(p),command_lines('test_command',why)))
 assert all(actual==(1,lines,'setup-unreadable',[],False,True,True) for actual,lines in observed),observed
elif case=='suite-order':
 fresh('suite-order');nest('web')
 suite_config(('ui','web',vc('-c a.ts -c b.ts','../'+BIN)),
              ('backend','web',vc('--root /abs','../'+BIN)))
 # The command-level refusal also precedes unreadable modules.
 config('export default {setupFiles:dynamic};','web/vitest.config.ts')
 install();p=run(binary,'red',ok=False)
 first=refusal_observation(p)
 block_log();q=run(binary,'red',ok=False)
 lines=command_lines('command of [[suite]] ui','--config is given more than once')
 assert first==(1,lines,'setup-unreadable',[],False,True,True),first
 assert q.returncode==1 and refuse_lines(q)==lines and LOG.is_dir()
 assert not list(LOCK_DIR.glob('*.json')) and PREFIX not in q.stdout
elif case=='hook-added':
 parent_layout('web/tests',vc('--root ..','../../'+BIN),'vitest.config.ts')
 p,d=red();commit('RED154');lf=lock()[0];head=git('rev-parse','HEAD')
 boot('web/vitest.config.ts','./boot.ts');write('web/boot.ts',SETUP)
 git('add','web/vitest.config.ts','web/boot.ts');before_trace=trace()
 q=run('git','commit','-qm','add CLI root config',ok=False)
 assert q.returncode==1,'hook accepted a config newly selected at the CLI root'
 lines=added_lines('web/vitest.config.ts','in the index',lf)
 assert refuse_lines(q)==lines and rows()[-1]['code']=='runner-config-added' and trace()==before_trace
 assert git('rev-parse','HEAD')==head and lock()[1]['state']=='open'
 block_log();r=run('git','commit','-qm','retry with log blocked',ok=False)
 assert r.returncode==1 and refuse_lines(r)==lines and LOG.is_dir() and lock()[1]['state']=='open'
 assert files(d,['vitest.config.ts'],'web/tests/src/sum.test.ts')
elif case=='ci-added':
 parent_layout('web/tests',vc('--root ..','../../'+BIN),'vitest.config.ts')
 red();commit('RED154');lf=lock()[0];base=git('rev-parse','HEAD')
 boot('web/vitest.config.ts','./boot.ts');write('web/boot.ts',SETUP)
 oid=snap('unjudged CLI root config');short=oid[:7]
 before=LOG.read_bytes();before_trace=trace()
 post=run(binary,'close')
 post_log=LOG.read_bytes();post_trace=trace()
 # CI must judge the commit even after the checkout's version evidence changes.
 write('node_modules/vitest/package.json','{"version":"5.0.4"}')
 p=run(binary,'ci','--base',base,ok=False)
 measured=rows()[-1];ci_trace=trace()
 block_log();q=run(binary,'ci','--base',base,ok=False)
 lines=added_lines('web/vitest.config.ts','in commit '+short,lf)
 assert p.returncode==1 and refuse_lines(p)==lines and measured.get('code')=='runner-config-added',(refuse_lines(p),measured)
 assert q.returncode==1 and refuse_lines(q)==lines and LOG.is_dir() and trace()==ci_trace==post_trace
 verdict=f'shipcraft: commit {short} would be refused by CI (runner-config-added): {lines[0].strip().removeprefix("shipcraft refused: ")}; next: {lines[2].strip().removeprefix("Next: ")}\n'
 assert verdict in post.stdout+post.stderr and post_log==before and post_trace==before_trace
 assert lock()[1]['state']=='open'
elif case=='ancestor-added':
 parent_layout('web',vc(exe='../'+BIN),'vite.config.ts');p,d=red();commit('RED154');lf=lock()[0]
 # Point 4 always walks up, even after the dependencies are upgraded.
 write('node_modules/vitest/package.json','{"version":"5.0.4"}')
 boot('vitest.config.ts','./boot.ts');write('web/boot.ts',SETUP)
 git('add','vitest.config.ts','web/boot.ts');q=run('git','commit','-qm','add ancestor config',ok=False)
 assert q.returncode==1,'hook accepted a higher-priority ancestor config'
 assert refuse_lines(q)==added_lines('vitest.config.ts','in the index',lf) and rows()[-1]['code']=='runner-config-added'
 assert files(d,['vite.config.ts'],'web/src/sum.test.ts') and lock()[1]['state']=='open'
elif case=='parent':
 fresh('parent',command=vc('-c cfg/u.ts'));boot('cfg/u.ts');write('src/unit-setup.ts','// no mock\n')
 install();p,d=red();commit('RED154')
 original=Path('src/sum.test.ts').read_text()
 bad=green('src/sum.test.ts',original+'// changed154\n')
 assert 'src/sum.test.ts' in refused(bad,'test-changed','hook')[0]
 write('src/sum.test.ts',original);git('add','src/sum.test.ts')
 q=green('src/sum.ts','// PASS154\n')
 assert q.returncode==0 and lock()[1]['state']=='closed'
 assert trace()[-1]['passed'] and trace()[-1]['config']==str(Path('cfg/u.ts').resolve())
 assert git('show','HEAD^:cfg/u.ts')==Path('cfg/u.ts').read_text()
elif case=='legacy':
 # The sealed format-5 payload is constructed independently of the writer, as in item 132.
 fresh('legacy',real=True,command=vc('--config config/vitest.unit.ts'))
 boot('config/vitest.unit.ts');write('src/unit-setup.ts','// no mock\n')
 install()
 old_files={f:digest(f) for f in ('.shipcraft.toml','src/sum.test.ts')}
 d=dict(format=5,state='open',files=old_files,cases=['src/sum.test.ts::adds'],
        failing_at_red=['src/sum.test.ts::adds'],controls=[],kind='feature',reported_at=None,fixes_release=None,seal='')
 d['seal']=hashlib.sha256(json.dumps(d,separators=(',',':')).encode()).hexdigest()
 write('.shipcraft/locks/legacy154.json',json.dumps(d)+'\n');commit('historical RED154')
 q=green('src/unit-setup.ts',MOCK)
 assert q.returncode==0 and lock()[1]['state']=='closed' and lock()[1]['files']==old_files
 assert 'stub154' in Path('src/sum.ts').read_text()
elif case=='sibling':
 parent_layout('web',vc(exe='../'+BIN),'vitest.config.ts');red();commit('RED154')
 config('export default {setupFiles:dynamic};','docs/vitest.config.ts')
 write('web/src/sum.ts','// PASS154\n');git('add','docs/vitest.config.ts','web/src/sum.ts')
 p=run('git','commit','-qm','sibling config',ok=False)
 assert p.returncode==0 and lock()[1]['state']=='closed'
 assert trace()[-1]['config']==str(Path('vitest.config.ts').resolve()) and trace()[-1]['passed']
 assert git('show','HEAD:docs/vitest.config.ts')==Path('docs/vitest.config.ts').read_text()
else:raise AssertionError('unrouted '+case)
PY154
  pass
}
