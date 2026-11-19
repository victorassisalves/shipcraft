# Item 132: vitest's config graph and setup files, through public commands only.
item132_langs() { echo node; }
item132_cases() {
  local c
  for c in main added-real real-control fake-control single global quoted comments extensionless no-candidate nested workspace import-vite unimported transitive node-modules symlink deleted redo variable push concat dynamic absolute missing roots order notice notice-order redo-notice no-notice ci-added opened parent legacy nonvitest-added log-fails write-fails redo-refused extensions; do echo "v1-132.$c"; done
}
item132_case() {
  EXPECT="item 132: ${CASE#v1-132.}"; v1_start
  must_accept 'vitest support contract' cmd "$PY" - "${CASE#v1-132.}" "$(command -v shipcraft)" <<'PY132'
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
 git('init','-q','-b','main');git('config','user.name','RED132');git('config','user.email','red132@example.invalid')
 write('.gitignore','node_modules/\ntools/\nignored/\n')
 write('package.json','{"private":true,"type":"module","devDependencies":{"vitest":"2.1.9"}}\n')
 write('src/sum.ts','export function sum(){throw new Error("stub132");}\n')
 write('src/sum.test.ts','import {it,expect} from "vitest";import {sum} from "./sum";it("adds",()=>expect(sum()).toBe(3));\n')
 write('src/test-setup.ts','// no mock\n')
 if real:
  run('npm','install','--offline','--no-audit','--no-fund','--loglevel=error')
 else:
  write('node_modules/.bin/vitest',FAKE);Path('node_modules/.bin/vitest').chmod(0o755)
  write('tools/runner',FAKE);Path('tools/runner').chmod(0o755)
  os.environ['PATH']=str(root/'tools')+os.pathsep+os.environ['PATH']
 write('.shipcraft.toml','shipcraft_min="0.0"\nlang="node"\nrunner="vitest"\ntest_command='+json.dumps(command)+'\ntest_globs='+json.dumps(GLOBS)+'\n[execution]\nci="local"\nreview="off"\n')
 return root
def install():run(binary,'init','--lang','node');commit('install132')
def red(*args):
 p=run(binary,'red',*args);return p,lock()[1]
def snap(message):
 # History under CI must contain the escape independently of the live hook.
 git('add','-A');tree=git('write-tree');oid=git('commit-tree',tree,'-p','HEAD','-m',message);git('update-ref','HEAD',oid);return oid
def green(path,text):
 write(path,text);git('add',path);return run('git','commit','-qm','GREEN132',ok=False)
def config(text,path='vitest.config.ts'):write(path,text)
def refused(p,code,layer='red'):
 lines=(p.stdout+p.stderr).strip().splitlines()[-3:]
 assert p.returncode==1 and len(lines)==3 and all(l.startswith(t) for l,t in zip(lines,('shipcraft refused:','Why:','Next:'))),(p.returncode,lines)
 assert [r for r in rows() if r['layer']==layer][-1]['code']==code,rows()
 return lines
FAKE=r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
import xml.etree.ElementTree as E
report=next(a.split('=',1)[1] for a in sys.argv if a.startswith('--outputFile.junit='))
def read(p):return Path(p).read_text() if Path(p).is_file() else ''
passed='PASS132' in read('src/sum.ts') or 'MOCK132' in read('src/test-setup.ts') or 'MOCK132' in read('vite.config.ts')
t=E.Element('testsuites');s=E.SubElement(t,'testsuite',name='src/sum.test.ts',tests='1',failures=str(int(not passed)))
c=E.SubElement(s,'testcase',classname='src/sum.test.ts',name='adds',file='src/sum.test.ts')
if not passed:E.SubElement(c,'failure',message='stub132').text='stub132'
E.ElementTree(t).write(report,encoding='utf-8',xml_declaration=True)
Path('tools').mkdir(exist_ok=True)
with Path('tools/trace').open('a') as f:f.write(json.dumps({'variant':'fake132','passed':passed,'files':read(os.environ.get('SHIPCRAFT_FILES','missing')),'args':sys.argv[1:]})+'\n')
sys.exit(0 if passed else 1)
'''
if case=='main':
 fresh('main',real=True);Path('.shipcraft.toml').unlink()
 write('vitest.config.ts','export default {test:{maxWorkers:1,minWorkers:1,setupFiles:["./src/test-setup.ts"]}};\n')
 write('src/test-setup.ts','// no mock\n')
 write('src/sum.ts','export function sum(){throw new Error("stub132");}\n')
 write('src/sum.test.ts','import {it,expect} from "vitest";import {sum} from "./sum";it("adds",()=>expect(sum()).toBe(3));\n')
 install()
 run(binary,'red');commit('RED132')
 write('src/test-setup.ts','import {vi} from "vitest";vi.mock("./sum",()=>({sum:()=>3}));\n')
 git('add','src/test-setup.ts')
 p=run('git','commit','-qm','GREEN changes only setup132',ok=False)
 print('REPRODUCTION A: GREEN rc='+str(p.returncode)+'; stub='+Path('src/sum.ts').read_text().strip()+'; lock='+lock()[1]['state'],flush=True)
 assert p.returncode!=0,'setup-only GREEN was accepted; expected test-changed'
 assert rows()[-1]['code']=='test-changed',rows()[-1]
elif case=='added-real':
 fresh('added-real',real=True);config('export default {test:{maxWorkers:1,minWorkers:1}};','vite.config.ts');install();red();commit('RED132')
 config('export default {test:{maxWorkers:1,minWorkers:1,setupFiles:["./src/test-setup.ts"]}};')
 write('src/test-setup.ts','import {vi} from "vitest";vi.mock("./sum",()=>({sum:()=>3}));\n');git('add','vitest.config.ts','src/test-setup.ts')
 p=run('git','commit','-qm','added runner132',ok=False)
 assert p.returncode==1,'added vitest config escaped'
 lines=refused(p,'runner-config-added','hook');assert 'vitest.config.ts' in lines[0] and 'with lock' in lines[0]
 assert lock()[1]['state']=='open' and 'stub132' in Path('src/sum.ts').read_text()
 log=Path('.git/shipcraft/runs.jsonl');log.unlink();log.mkdir()
 q=run('git','commit','-qm','added runner with blocked log132',ok=False)
 assert q.returncode==1 and (q.stdout+q.stderr).strip().splitlines()[-3:]==lines and log.is_dir() and lock()[1]['state']=='open'
elif case=='real-control':
 fresh('real-control',real=True);config('export default {test:{maxWorkers:1,minWorkers:1,setupFiles:["./src/test-setup.ts"]}};');install()
 p,d=red();assert d['failing_at_red']==['src/sum.test.ts::adds'] and 'stub132' in p.stderr
 commit('RED132');p=green('src/sum.ts','export function sum(){return 3;}\n')
 assert p.returncode==0 and lock()[1]['state']=='closed' and Path('src/test-setup.ts').read_text()=='// no mock\n'
elif case=='fake-control':
 fresh('fake-control');install();p,d=red();assert d['failing_at_red']==['src/sum.test.ts::adds']
 commit('RED132');original=Path('src/sum.test.ts').read_text();p=green('src/sum.test.ts',original+'// changed132\n')
 lines=refused(p,'test-changed','hook');assert 'src/sum.test.ts' in lines[0]
 write('src/sum.test.ts',original);git('add','src/sum.test.ts')
 write('product-note','control132');oid=snap('ordinary product snapshot132');assert git('show','HEAD:product-note')=='control132' and git('rev-parse','HEAD')==oid
 p=green('src/sum.ts','// PASS132\n');assert p.returncode==0 and lock()[1]['state']=='closed'
 trace=[json.loads(s) for s in Path('tools/trace').read_text().splitlines()]
 assert trace[-1]['variant']=='fake132' and trace[-1]['passed'] is True and any(x['passed'] is False for x in trace)
 assert str(Path('src/sum.test.ts').resolve())+'\0'==trace[-1]['files']
elif case=='single':
 fresh('single');config('export default {test:{setupFiles:"./src/test-setup.ts"}};');install();p,d=red()
 assert d['files'].get('src/test-setup.ts')=='sha256:'+hashlib.sha256(Path('src/test-setup.ts').read_bytes()).hexdigest(),d['files']
 assert set(d)=={'format','state','files','cases','failing_at_red','controls','kind','reported_at','fixes_release','seal'} and d['format']==5
 assert all('test-setup' not in json.loads(x)['files'] for x in Path('tools/trace').read_text().splitlines())
elif case=='global':
 fresh('global');write('tests/helpers/firestore-emulator.ts','// emulator\n');config('export default {test:{globalSetup:["./tests/helpers/firestore-emulator.ts"]}};');install();p,d=red()
 assert 'tests/helpers/firestore-emulator.ts' in d['files'],d['files']
elif case=='quoted':
 for i,text in enumerate(('\ufeffexport default {test:{"setupFiles" /*key*/ : /*value*/ [`./src/test-setup.ts`,],}};',"export default {test:{'globalSetup':'./src/test-setup.ts'}};",'export default {test:{`setupFiles`: "./src/test-setup.ts"}};', 'export default {test:{setupFiles\r:\r["./src/test-setup.ts",\r\n]}};', 'export default {test:{setupFiles\u2028:\u2029"./src/test-setup.ts"}};')):
  fresh('quoted'+str(i));config(text);install();p,d=red();assert 'src/test-setup.ts' in d['files'],(text,d['files'])
elif case=='comments':
 fresh('comments');config('// setupFiles: variable\r\n/* globalSetup.push(x) */\nexport default {test:{xsetupFiles:null,setupFiles$:null}};');install();p,d=red()
 assert set(d['files'])=={'.shipcraft.toml','src/sum.test.ts','vitest.config.ts'} and PREFIX not in p.stdout
 assert Path('vitest.config.ts').read_bytes().count(b'globalSetup')==1
 commit('RED132');p=green('src/test-setup.ts','// MOCK132\n');assert p.returncode==0 and lock()[1]['state']=='closed'
elif case=='extensionless':
 fresh('extensionless');extensions=('','ts','tsx','mts','cts','js','jsx','mjs','cjs')
 names=['boot'+('.'+x if x else '') for x in extensions]
 for name in names:write(name,'// '+name+'\n')
 write('folder.ts','// folder candidate skipped\n');Path('folder').mkdir();config('export default {test:{setupFiles:["./boot","./folder"]}};');install();p,d=red()
 assert set(names+['folder.ts'])<=set(d['files']) and 'folder' not in d['files'],d['files']
 assert all(d['files'][n]=='sha256:'+hashlib.sha256(Path(n).read_bytes()).hexdigest() for n in names)
elif case=='no-candidate':
 fresh('no-candidate');config('export default {test:{setupFiles:["@testing-library/jest-dom/vitest","../outside132.ts"]}};');install();p,d=red()
 assert set(d['files'])=={'.shipcraft.toml','src/sum.test.ts','vitest.config.ts'} and PREFIX not in p.stdout
elif case=='nested':
 fresh('nested');write('packages/ui/src/boot.ts','// nested\n');write('src/boot.ts','// wrong root\n');config('export default {test:{setupFiles:"./src/boot.ts"}};','packages/ui/vitest.config.ts');install();p,d=red()
 assert 'packages/ui/src/boot.ts' in d['files'] and 'src/boot.ts' not in d['files'],d['files']
 fresh('suite-root');write('packages/ui/src/sum.test.ts',Path('src/sum.test.ts').read_text());write('packages/ui/src/boot.ts','// nested root\n')
 config('export default {setupFiles:dynamic};');config('export default {test:{setupFiles:"./src/boot.ts"}};','packages/ui/vitest.config.ts')
 write('.shipcraft.toml','shipcraft_min="0.0"\n[execution]\nci="local"\nreview="off"\n[[suite]]\nname="ui"\nroot="packages/ui"\ncommand='+json.dumps('../../'+COMMAND)+'\nglobs='+json.dumps(GLOBS)+'\n')
 install();p,d=red();assert set(d['files'])=={'.shipcraft.toml','packages/ui/src/sum.test.ts','packages/ui/vitest.config.ts','packages/ui/src/boot.ts'},d['files']
elif case=='workspace':
 fresh('workspace');config('export default {globalSetup:"./src/test-setup.ts"};','vitest.workspace.mts');install();p,d=red()
 assert {'vitest.workspace.mts','src/test-setup.ts'}<=set(d['files']),d['files']
elif case=='import-vite':
 fresh('import-vite');config('import cfg from "./vite.config";export default cfg;');config('export default {test:{setupFiles:"./src/test-setup.ts"}};','vite.config.ts');install();p,d=red()
 assert {'vite.config.ts','src/test-setup.ts'}<=set(d['files']),d['files']
 commit('RED132');p=green('vite.config.ts','// MOCK132\n');assert p.returncode==1;refused(p,'test-changed','hook')
elif case=='unimported':
 fresh('unimported');config('export default {};');config('export default {test:{setupFiles:dynamic}};','vite.config.ts');config('export default {setupFiles:unknown};','examples/demo/vite.config.ts');install();p,d=red()
 assert set(d['files'])=={'.shipcraft.toml','src/sum.test.ts','vitest.config.ts'} and PREFIX not in p.stdout
 commit('RED132');p=green('vite.config.ts','// MOCK132\n');assert p.returncode==0 and lock()[1]['state']=='closed'
elif case=='transitive':
 fresh('transitive');config('import "./config/a"; import data from "./data.json"; /* require(built) */');write('data.json','{"setupFiles": "not JS"}')
 write('config/a.ts','export {default} from "./b"; const x="require(variable)";')
 write('config/b.mjs','const x=import("./c"); export default {};');write('config/c.cts','const x=require("../config/a"); export default {test:{setupFiles:"../src/test-setup.ts"}};')
 install();p,d=red();assert {'config/a.ts','config/b.mjs','config/c.cts','data.json','src/test-setup.ts'}<=set(d['files']),d['files']
elif case=='node-modules':
 fresh('node-modules');config('export default {setupFiles:dynamic};','node_modules/pkg/vitest.workspace.js');git('add','-f','node_modules/pkg/vitest.workspace.js');install();p,d=red()
 assert set(d['files'])=={'.shipcraft.toml','src/sum.test.ts'} and PREFIX not in p.stdout,d['files']
elif case=='symlink':
 for i,(body,target,source) in enumerate((('export default {test:{setupFiles:"./src/alias.ts"}};','src/alias.ts','test-setup.ts'),('import "./alias";','alias.ts','src/test-setup.ts'))):
  fresh('symlink'+str(i));Path(target).symlink_to(source);config(body);install();p=run(binary,'red',ok=False)
  assert p.returncode==1,'symlink setup/module must refuse';lines=refused(p,'setup-unreadable')
  assert lines[0]=='shipcraft refused: could not read the vitest setup files of vitest.config.ts: '+target+' is a symbolic link'
  assert not list(Path('.shipcraft/locks').glob('*.json')) and PREFIX not in p.stdout
elif case=='deleted':
 fresh('deleted');config('export default {test:{setupFiles:"./src/test-setup.ts"}};');install();red();commit('RED132');git('rm','src/test-setup.ts');p=run('git','commit','-qm','delete setup132',ok=False)
 assert p.returncode==1;lines=refused(p,'locked-file-deleted','hook');assert 'src/test-setup.ts' in lines[0] and lock()[1]['state']=='open'
elif case=='redo':
 fresh('redo');config('export default {};');install();red();commit('RED132');config('export default {test:{setupFiles:"./src/test-setup.ts"}};');p,d=red('--redo')
 assert 'src/test-setup.ts' in d['files'],d['files']
 commit('redo132');p=green('src/test-setup.ts','// MOCK132\n');assert p.returncode==1;refused(p,'test-changed','hook')
elif case=='variable':
 for i,value in enumerate(('helpers','null','42','true','()=>[]','[...helpers]','["./src/test-setup.ts"].concat(more)','"./src/te\\x73t-setup.ts"','`./${name}.ts`',"'./src/test\n-setup.ts'")):
  fresh('variable'+str(i));config('export default {test:{setupFiles:'+value+'}};');install();p=run(binary,'red',ok=False)
  assert p.returncode==1,(value,'unreadable value accepted');lines=refused(p,'setup-unreadable')
  assert lines[0].endswith(': setupFiles is not a string or an array of strings') and not list(Path('.shipcraft/locks').glob('*.json'))
elif case=='push':
 for i,text in enumerate(('setupFiles.push("./src/test-setup.ts");','const setupFiles=["./src/test-setup.ts"]; export default {test:{setupFiles}};','setupFiles = ["./src/test-setup.ts"];','const s="globalSetup";')):
  fresh('push'+str(i));config(text);install();p=run(binary,'red',ok=False)
  assert p.returncode==1,(text,'unreadable key accepted');lines=refused(p,'setup-unreadable');assert 'not a string or an array of strings' in lines[0]
elif case=='concat':
 fresh('concat');config('export default {test:{setupFiles:"./src/test-setup.ts" + "suffix"}};');install();p=run(binary,'red',ok=False)
 assert p.returncode==1;lines=refused(p,'setup-unreadable');assert lines[0].endswith('setupFiles is not a string or an array of strings')
 assert PREFIX not in p.stdout and not list(Path('.shipcraft/locks').glob('*.json'))
elif case=='dynamic':
 for i,text in enumerate(('const x=require("./config/"+name);','const x=import(name);','const x=require(`./${name}`);')):
  fresh('dynamic'+str(i));config(text);install();p=run(binary,'red',ok=False)
  assert p.returncode==1;lines=refused(p,'setup-unreadable');assert lines[0].endswith('an import is not a string literal')
elif case=='absolute':
 fresh('absolute');config('export default {test:{globalSetup:"/tmp/absolute132.ts"}};');install();p=run(binary,'red',ok=False)
 assert p.returncode==1;lines=refused(p,'setup-unreadable');assert lines[0].endswith('/tmp/absolute132.ts is an absolute path')
elif case=='missing':
 for i,(text,why) in enumerate((('export default {test:{setupFiles:"./ignored/boot.ts"}};','./ignored/boot.ts names no file in the repository'),('import x from "./absent";','./absent names no file in the repository'))):
  fresh('missing'+str(i));write('ignored/boot.ts','// ignored\n');config(text);install();p=run(binary,'red',ok=False)
  assert p.returncode==1;lines=refused(p,'setup-unreadable');assert lines[0].endswith(why) and not list(Path('.shipcraft/locks').glob('*.json'))
elif case=='roots':
 for i,value in enumerate(('import.meta.dirname','__dirname',"'.'","'./'")):
  fresh('root-ok'+str(i));config('const root=1;path.resolve("root");export default {test:{root:'+value+',setupFiles:"./src/test-setup.ts"}};');install();p,d=red()
  assert 'src/test-setup.ts' in d['files'],d['files']
 for i,value in enumerate(('"./src"','process.cwd()','import.meta.dirname+"/src"')):
  fresh('root-bad'+str(i));config('export default {test:{"root":'+value+',setupFiles:"./src/test-setup.ts"}};');install();p=run(binary,'red',ok=False)
  assert p.returncode==1;lines=refused(p,'setup-unreadable');assert lines[0].endswith('it sets root')
elif case=='order':
 fresh('order');config('import "./z";import "./a";');write('z.ts','export default {setupFiles:null};');write('a.ts','export default {root:"elsewhere",setupFiles:null};');install();p=run(binary,'red',ok=False)
 assert p.returncode==1;lines=refused(p,'setup-unreadable')
 assert lines==['shipcraft refused: could not read the vitest setup files of a.ts: it sets root','Why: red locks the setup files it can name; one it cannot name could change what every locked case sees','Next: in a.ts, write setupFiles and globalSetup as string literals or arrays of them, with paths relative to the file and no root key, then run red again']
 assert not list(Path('.shipcraft/locks').glob('*.json')) and Path('tools/trace').exists() and PREFIX not in p.stdout
 log=Path('.git/shipcraft/runs.jsonl');log.unlink();log.mkdir();q=run(binary,'red',ok=False)
 assert q.returncode==1 and q.stderr.strip().splitlines()[-3:]==lines and PREFIX not in q.stdout and not list(Path('.shipcraft/locks').glob('*.json'))
elif case=='notice':
 fresh('notice');names=['z.ts','café.ts','c.ts','b\t.ts','a\n/boot.ts']
 for name in names:write(name,'// setup\n')
 # The LF is in the config's folder; the literal itself has no LF or escape.
 config('export default {setupFiles:"./boot.ts"};','a\n/vitest.config.ts')
 config('export default {test:{setupFiles:['+','.join('"'+n+'"' for n in names[:-1])+']}};');install();p,d=red()
 assert (PREFIX+'a\\n/boot.ts, b\\t.ts, c.ts and 2 more') in p.stdout.splitlines(),p.stdout
 assert p.stdout.count(PREFIX)==1 and set(names)<=set(d['files'])
elif case=='notice-order':
 fresh('notice-order');config('export default {test:{setupFiles:"./src/test-setup.ts"}};');install();p,d=red();lines=p.stdout.splitlines()
 n=next(i for i,l in enumerate(lines) if l.startswith('shipcraft: RED locked at'))
 assert lines[n-1]==PREFIX+'src/test-setup.ts' and lines[n-2].startswith('shipcraft: controls:'),lines
 assert ': 4 file(s),' in lines[n] and PREFIX not in p.stderr
elif case=='redo-notice':
 fresh('redo-notice');config('export default {};');install();red();commit('RED132');config('export default {test:{setupFiles:"./src/test-setup.ts"}};');p,d=red('--redo');lines=p.stdout.splitlines()
 n=next(i for i,l in enumerate(lines) if l.startswith('shipcraft: RED redone at'))
 assert lines[n-1]==PREFIX+'src/test-setup.ts' and lines[n-2].startswith('shipcraft: controls:') and ': 4 file(s),' in lines[n]
 commit('redo132');before=lock()[0].read_bytes();q=run(binary,'red','--redo');assert 'RED unchanged' in q.stdout and PREFIX not in q.stdout and lock()[0].read_bytes()==before
elif case=='no-notice':
 fresh('no-notice');install();p,d=red();lines=p.stdout.splitlines();n=next(i for i,l in enumerate(lines) if l.startswith('shipcraft: RED locked at'))
 assert lines[n-1]=='shipcraft: controls: 0 passing case(s) of the changed test files; the hook runs them too' and PREFIX not in p.stdout+p.stderr
 assert set(d['files'])=={'.shipcraft.toml','src/sum.test.ts'}
 commit('RED132');before=lock()[0].read_bytes();q=run(binary,'red','--redo')
 expected='shipcraft: red compared with main (origin/HEAD is missing)\nshipcraft: red ran the changed test files: 1 of 2\nshipcraft: RED unchanged: lock '+str(lock()[0])+' already reads the same; nothing written.\n'
 assert q.stdout==expected and before==lock()[0].read_bytes(),q.stdout
elif case=='ci-added':
 fresh('ci-added');install();red();commit('RED132');base=git('rev-parse','HEAD')
 config('export default {};','vitest.workspace.cjs');config('export default {};','vitest.config.js');write('src/sum.ts','// PASS132\n');snap('escape132')
 p=run(binary,'ci','--base',base,ok=False);assert p.returncode==1;lines=refused(p,'runner-config-added','ci')
 assert 'runner config vitest.config.js was added' in lines[0] and lock()[1]['state']=='open'
 log=Path('.git/shipcraft/runs.jsonl');log.unlink();log.mkdir();q=run(binary,'ci','--base',base,ok=False)
 assert q.returncode==1 and (q.stdout+q.stderr).strip().splitlines()[-3:]==lines and log.is_dir()
elif case=='opened':
 fresh('opened');install();config('export default {};','examples/demo/vite.config.ts');p,d=red();commit('RED132')
 assert 'examples/demo/vite.config.ts' not in d['files'] and lock()[1]['state']=='open'
 p=green('src/sum.ts','// PASS132\n');assert p.returncode==0 and lock()[1]['state']=='closed'
elif case=='parent':
 fresh('parent');config('export default {};','vite.config.ts');install();red();commit('RED132')
 p=green('src/sum.ts','// PASS132\n');assert p.returncode==0 and lock()[1]['state']=='closed' and Path('vite.config.ts').read_text()=='export default {};'
elif case=='legacy':
 fresh('legacy');config('export default {test:{setupFiles:"./src/test-setup.ts"}};');install()
 # Historical format-5 reader fixture with 2.74.0's files, built independently of the current writer.
 files={f:'sha256:'+hashlib.sha256(Path(f).read_bytes()).hexdigest() for f in ('.shipcraft.toml','src/sum.test.ts','vitest.config.ts')}
 d=dict(format=5,state='open',files=files,cases=['src/sum.test.ts::adds'],failing_at_red=['src/sum.test.ts::adds'],controls=[],kind='feature',reported_at=None,fixes_release=None,seal='')
 d['seal']=hashlib.sha256(json.dumps(d,separators=(',',':')).encode()).hexdigest();write('.shipcraft/locks/legacy132.json',json.dumps(d)+'\n');commit('historical RED132')
 p=green('src/test-setup.ts','// MOCK132\n');assert p.returncode==0 and lock()[1]['state']=='closed' and lock()[1]['files']==files
elif case=='nonvitest-added':
 fresh('nonvitest-added',command='tools/runner --outputFile.junit={junit}');config('export default {setupFiles:dynamic};');install();p,d=red()
 assert 'src/test-setup.ts' not in d['files'];commit('RED132');config('export default {setupFiles:dynamic};','vite.config.ts');write('src/sum.ts','// PASS132\n');git('add','vite.config.ts','src/sum.ts');p=run('git','commit','-qm','other runner132',ok=False)
 assert p.returncode==0 and lock()[1]['state']=='closed'
elif case=='log-fails':
 fresh('log-fails');config('export default {test:{setupFiles:"./src/test-setup.ts"}};');install();path=Path('.git/shipcraft/runs.jsonl');path.unlink();path.mkdir();p,d=red()
 assert 'src/test-setup.ts' in d['files'] and PREFIX+'src/test-setup.ts' in p.stdout and path.is_dir()
elif case=='write-fails':
 fresh('write-fails');config('export default {test:{setupFiles:"./src/test-setup.ts"}};');install();folder=Path('.shipcraft/locks');folder.chmod(0o555)
 try:p=run(binary,'red',ok=False)
 finally:folder.chmod(0o755)
 assert p.returncode==2 and not list(folder.glob('*.json')) and PREFIX not in p.stdout
 assert rows()[-1]['layer']=='red' and rows()[-1]['result']=='error' and Path('tools/trace').exists()
elif case=='redo-refused':
 fresh('redo-refused');config('export default {};');install();red();commit('RED132');before=lock()[0].read_bytes();config('export default {setupFiles:unknown};');p=run(binary,'red','--redo',ok=False)
 assert p.returncode==1;refused(p,'setup-unreadable');assert lock()[0].read_bytes()==before and rows()[-1]['redo'] is True and PREFIX not in p.stdout
elif case=='extensions':
 for i,ext in enumerate(('ts','mts','cts','js','mjs','cjs')):
  fresh('extensions'+str(i));config('export default {test:{setupFiles:"./src/test-setup.ts"}};','vite.config.'+ext);install();p,d=red()
  assert {'vite.config.'+ext,'src/test-setup.ts'}<=set(d['files']),d['files']
  commit('RED132');p=green('vite.config.'+ext,'// MOCK132\n');assert p.returncode==1;refused(p,'test-changed','hook')
  config('export default {test:{setupFiles:"./src/test-setup.ts"}};','vite.config.'+ext);git('add','vite.config.'+ext)
  added='nested/vitest.workspace.'+ext;config('export default {};',added);git('add',added)
  p=run('git','commit','-qm','new workspace132',ok=False);assert p.returncode==1;lines=refused(p,'runner-config-added','hook');assert added in lines[0]

else:raise AssertionError('unrouted '+case)
PY132
  pass
}
