# Item 140: Jest's configs, setup graph and manifest settings, public commands only.
item140_langs() { echo node; }
item140_cases() {
  local c
  for c in repro-a fake-control manifest-setup globals rootdir ancestors nested json-config imports extensionless control-discovery redo scan-values roots-invalid json-invalid symlink missing order notice mixed control-vitest redo-refused io-failure repro-c repro-d changed removed control-equal control-deps invalid-manifest watched linked ci control-merge index control-index control-no-lock log-failure legacy json-reader; do echo "v1-140.$c"; done
}
item140_case() {
  EXPECT="item 140: ${CASE#v1-140.}"; v1_start
  must_accept 'Jest support contract' cmd "$PY" - "${CASE#v1-140.}" "$(command -v shipcraft)" <<'PY140'
import hashlib,json,os,shlex,subprocess,sys
from pathlib import Path
case,binary=sys.argv[1:];binary=str(Path(binary).resolve());home=Path.cwd().resolve()
def run(*args):
 p=subprocess.run(list(map(str,args)),capture_output=True,text=True,timeout=120)
 print('$',shlex.join(map(str,args)),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 return p
def ok(*args):
 p=run(*args);assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr);return p
def git(*args):return ok('git',*args).stdout.strip()
def write(path,value):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(value if isinstance(value,bytes) else value.encode())
def commit(message):git('add','-A');return ok('git','commit','-qm',message)
def lock():
 paths=list(Path('.shipcraft/locks').glob('*.json'));assert len(paths)==1,paths
 return paths[0],json.loads(paths[0].read_text())
def rows():return [json.loads(s) for s in Path('.git/shipcraft/runs.jsonl').read_text().splitlines()]
GLOBS=['**/*.test.*','**/*.spec.*','**/__tests__/**','**/vitest.config.*','**/jest.config.*']
COMMAND="JEST_JUNIT_OUTPUT_FILE={junit} JEST_JUNIT_CLASSNAME='{filepath}' node_modules/.bin/jest --runInBand --reporters=default --reporters=jest-junit"
PREFIX='shipcraft: red also locked what '
MOCK='jest.mock("./sum", () => ({sum: () => 3}));\n'
def fresh(name,real=False,root='.',command=None):
 rootpath=home/name;rootpath.mkdir();os.chdir(rootpath)
 git('init','-q','-b','main');git('config','user.name','RED140');git('config','user.email','red140@example.invalid')
 write('.gitignore','node_modules/\ntools/\n.trace140\nignored/\n')
 write('package.json',json.dumps({'private':True,'devDependencies':{'jest':os.getenv('SHIPCRAFT_JEST_VERSION','29.7.0'),'jest-junit':os.getenv('SHIPCRAFT_JEST_JUNIT_VERSION','16.0.0')}}))
 write('src/sum.js','exports.sum = () => {throw new Error("stub140")};\n')
 write('src/sum.test.js','const {sum}=require("./sum");test("adds",()=>expect(sum()).toBe(3));\n')
 write('src/other.test.js','test("control140",()=>expect(2+2).toBe(4));\n')
 write('src/setup.js','// no mock\n')
 if real:ok('npm','install','--offline','--ignore-scripts','--no-audit','--no-fund','--loglevel=error')
 else:
  write(root+'/node_modules/.bin/jest',FAKE);Path(root+'/node_modules/.bin/jest').chmod(0o755)
  write(root+'/tools/runner',FAKE);Path(root+'/tools/runner').chmod(0o755)
 cmd=('JEST_JUNIT_OUTPUT_FILE={junit} '+command) if command else COMMAND
 text='shipcraft_min="0.0"\nlang="node"\nrunner="jest"\n'
 if root=='.':text+='test_command='+json.dumps(cmd)+'\ntest_globs='+json.dumps(GLOBS)+'\n'
 text+='[execution]\nci="local"\nreview="off"\n'
 if root!='.':text+='[[suite]]\nname="api140"\nroot='+json.dumps(root)+'\ncommand='+json.dumps(cmd)+'\nglobs='+json.dumps(GLOBS)+'\n'
 write('.shipcraft.toml',text)
def refuse(p,code,layer):
 lines=[l for l in (p.stdout+p.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]
 assert p.returncode==1 and len(lines)==3,(p.returncode,lines)
 assert [r for r in rows() if r['layer']==layer][-1]['code']==code,rows()[-1]
 return lines
def config(value,path='jest.config.js'):write(path,value)
def manifest(value,path='package.json'):write(path,json.dumps(value))
def install():ok(binary,'init','--lang','node');commit('baseline140')
def red(*args):return run(binary,'red',*args)
def seed():
 install();p=red();assert p.returncode==0,(p.stdout,p.stderr);commit('RED140');return lock()[0]
def green(changes,ci=False):
 base=git('rev-parse','HEAD')
 for name,value in changes.items():
  if value is None:Path(name).unlink()
  else:write(name,value)
 git('add','-A')
 if ci:
  tree=git('write-tree');sha=git('commit-tree',tree,'-p',base,'-m','CI snapshot140');git('update-ref','HEAD',sha)
  return run(binary,'ci','--base',base)
 return run('git','commit','-qm','GREEN140')
FAKE=r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
import xml.etree.ElementTree as E
passed='return 3' in Path('src/sum.js').read_text() or 'jest.mock' in Path('src/setup.js').read_text()
s=E.Element('testsuite',tests='2',failures=str(int(not passed)))
for file,name in [('src/sum.test.js','adds'),('src/other.test.js','control140')]:
 c=E.SubElement(s,'testcase',classname=file,name=name,file=file)
 if name=='adds' and not passed:E.SubElement(c,'failure',message='stub140')
E.ElementTree(s).write(os.environ['JEST_JUNIT_OUTPUT_FILE'])
with Path('.trace140').open('a') as f:f.write(json.dumps({'runner':'fake140','passed':passed,'files':Path(os.environ['SHIPCRAFT_FILES']).read_text() if os.environ.get('SHIPCRAFT_FILES') else ''})+'\n')
print('fake140:'+str(passed))
sys.exit(0 if passed else 1)
'''
if case=='repro-a':
 fresh('repro-a',real=True);Path('.shipcraft.toml').unlink()
 write('jest.config.js','module.exports={setupFiles:["<rootDir>/src/setup.js"]};\n')
 lf=seed();p=green({'src/setup.js':MOCK})
 print('REPRODUCTION A: GREEN rc='+str(p.returncode)+'; stub='+Path('src/sum.js').read_text().strip()+'; lock='+lock()[1]['state'],flush=True)
 assert p.returncode==1,'setup-only GREEN accepted; expected test-changed'
 assert rows()[-1]['code']=='test-changed' and lock()[1]['state']=='open'
elif case=='fake-control':
 fresh('fake-control');lf=seed();d=lock()[1]
 assert d['failing_at_red']==['src/sum.test.js::adds'] and d['controls']==[] and 'src/other.test.js::control140' in d['cases'],d
 assert 'fake140:False' in Path('.git/shipcraft/output/red.log').read_text()
 original=Path('src/sum.test.js').read_text();q=green({'src/sum.test.js':original+'// changed140\n'});lines=refuse(q,'test-changed','hook');assert 'src/sum.test.js' in lines[0];write('src/sum.test.js',original);git('add','src/sum.test.js')
 p=green({'src/sum.js':'exports.sum=()=>{return 3};'})
 assert p.returncode==0 and lock()[1]['state']=='closed'
 trace=[json.loads(l) for l in Path('.trace140').read_text().splitlines()]
 assert trace[-1]['runner']=='fake140' and trace[-1]['passed'] and any(not t['passed'] for t in trace)
 assert trace[-1]['files']==str(Path('src/sum.test.js').resolve())+'\0',trace[-1]
elif case=='manifest-setup':
 fresh('manifest-setup');manifest({'jest':{'setupFilesAfterEnv':['<rootDir>/src/setup.js']}});lf=seed()
 p=green({'src/setup.js':MOCK});lines=refuse(p,'test-changed','hook')
 assert 'src/setup.js' in lines[0] and lock()[1]['state']=='open'
 assert 'package.json' not in lock()[1]['files']
elif case=='globals':
 fresh('globals');config('\ufeffmodule.exports={\"globalSetup\" /* key */ :"./src/setup.js",globalTeardown\u2028:\u2029`<rootDir>/teardown`,};')
 write('teardown.ts','// teardown');install();p=red();d=lock()[1]
 assert p.returncode==0 and {'src/setup.js','teardown.ts'}<=set(d['files']),d
 assert d['files']['teardown.ts']=='sha256:'+hashlib.sha256(Path('teardown.ts').read_bytes()).hexdigest()
 for ext in ('ts','mts','cts','mjs','cjs','json'):
  fresh('globals-'+ext);config('{"globalTeardown":"./src/setup.js"}' if ext=='json' else 'module.exports={globalTeardown:"./src/setup.js"};','jest.config.'+ext);install();p=red()
  assert p.returncode==0 and 'src/setup.js' in lock()[1]['files'],ext
elif case=='rootdir':
 for i,value in enumerate(('"src"','"./src/../src"','""','"."','"./"','__dirname','import.meta.dirname')):
  fresh('rootdir'+str(i));config('const rootDir=1;module.exports={rootDir:'+value+',root:dynamic,setupFiles:["<rootDir>/'+('setup.js' if i<2 else 'src/setup.js')+'"]};')
  install();p=red();assert p.returncode==0 and 'src/setup.js' in lock()[1]['files'],(value,p.stdout,p.stderr)
elif case=='ancestors':
 fresh('ancestors',root='./packages//api/');write('packages/api/src/sum.js','throw stub');write('packages/api/src/sum.test.js','test');write('packages/api/src/other.test.js','control');write('packages/api/src/setup.js','// empty')
 config('module.exports={setupFiles:"./src/setup.js"};');config('module.exports={setupFiles:"./boot.js"};','packages/jest.config.cjs');write('packages/boot.js','// ancestor')
 config('module.exports={setupFiles:dynamic};','packages/sibling/jest.config.js');install();p=red();d=lock()[1]
 assert p.returncode==0 and {'jest.config.js','src/setup.js','packages/jest.config.cjs','packages/boot.js'}<=set(d['files']),d
 assert 'packages/sibling/jest.config.js' not in d['files']
elif case=='nested':
 fresh('nested');config('module.exports={setupFiles:"./boot"};','examples/demo/jest.config.mjs');write('examples/demo/boot.js','// nested');write('boot.js','// wrong')
 install();p=red();assert p.returncode==0 and 'examples/demo/boot.js' in lock()[1]['files'] and 'boot.js' not in lock()[1]['files']
elif case=='json-config':
 fresh('json-config');config('\ufeff{ // JSONC\n "setupFiles": ["<rootDir>\\/src\\/setup.js",], "projects":["./unfollowed",{"rootDir":"<rootDir>/pkg","projects":[{"rootDir":"sub","globalTeardown":"./end.js"}]}],}', 'jest.config.json')
 write('pkg/sub/end.js','// recursive');install();p=red();d=lock()[1]
 assert p.returncode==0 and {'src/setup.js','pkg/sub/end.js'}<=set(d['files']),d
elif case=='imports':
 fresh('imports');config('import type {X} from "./config/a";require("./options");module.exports={rootDir:"src"};')
 write('config/a.ts','import "./b";export default {setupFilesAfterEnv:"./setup.js"};');write('config/b.mjs','import("./a");const x="require(bad)";/* setupFiles: null */')
 write('options.json','{"globalTeardown":"./end.js"}');write('src/end.js','// imported JSON');write('config/setup.js','// wrong');config('require("../config/a");module.exports={rootDir:"../other"};','another/jest.config.js');write('other/setup.js','// second originating root')
 install();p=red();d=lock()[1]
 assert p.returncode==0 and {'config/a.ts','config/b.mjs','options.json','src/setup.js','src/end.js','other/setup.js'}<=set(d['files']) and 'config/setup.js' not in d['files'],d
elif case=='extensionless':
 fresh('extensionless');names=['boot'+('.'+e if e else '') for e in ('','ts','tsx','mts','cts','js','jsx','mjs','cjs')]
 for n in names:write(n,'// '+n)
 Path('folder').mkdir();write('folder.ts','// sibling');config('module.exports={setupFiles:["./boot","./folder"]};');install();p=red()
 assert p.returncode==0 and set(names+['folder.ts'])<=set(lock()[1]['files']) and 'folder' not in lock()[1]['files']
elif case=='control-discovery':
 fresh('control-discovery',command='tools/runner');config('module.exports={setupFiles:dynamic};');manifest({'jest':'unreadable'})
 lf=seed();assert set(lock()[1]['files'])=={'.shipcraft.toml','jest.config.js','src/sum.test.js','src/other.test.js'}
 p=green({'src/sum.js':'exports.sum=()=>{return 3};','package.json':'{"jest":false}'})
 assert p.returncode==0 and lock()[1]['state']=='closed'
 fresh('control-exclusions');config('// setupFiles: variable\r\n/* globalSetup.push(x) */\nmodule.exports={xsetupFiles:null,setupFiles$:false,setupFiles:["jest-extended/all","../outside140"]};')
 manifest({},'packages/sibling/package.json');write('node_modules/pkg/jest.config.js','module.exports={setupFiles:bad};');write('node_modules/pkg/package.json','{"jest":false}');git('add','-f','node_modules/pkg/jest.config.js','node_modules/pkg/package.json')
 install();p=red();assert p.returncode==0 and PREFIX not in p.stdout and 'src/setup.js' not in lock()[1]['files']
 assert 'node_modules/pkg/jest.config.js' in lock()[1]['files'] # own glob locks it as a test file, scan still skips it
 fresh('control-invalid-manifest');write('package.json',b'not JSON');install();p=red();assert p.returncode==0 and 'package.json' not in lock()[1]['files']
elif case=='redo':
 fresh('redo');config('module.exports={};');lf=seed();config('module.exports={setupFiles:"./src/setup.js"};');p=red('--redo')
 assert p.returncode==0 and 'src/setup.js' in lock()[1]['files'] and PREFIX+'jest reads beside the tests: src/setup.js' in p.stdout
 commit('redo140');before=lf.read_bytes();q=red('--redo');assert q.returncode==0 and 'RED unchanged' in q.stdout and PREFIX not in q.stdout and lf.read_bytes()==before
 p=green({'src/setup.js':MOCK});refuse(p,'test-changed','hook')
elif case=='scan-values':
 bad=[]
 for i,value in enumerate(('variable','null','3','false','()=>[]','[...more]','"./src/setup.js" + "x"','["./src/setup.js"].concat(x)','`./${name}`','"./src/\\setup.js"')):
  fresh('scan-values'+str(i));config('module.exports={setupFilesAfterEnv:'+value+'};');install();p=red()
  if p.returncode!=1 or 'setupFilesAfterEnv is not a string or an array of strings' not in p.stdout+p.stderr:bad.append(value)
 assert not bad,('unread setup accepted',bad)
elif case=='roots-invalid':
 bad=[]
 for i,body in enumerate(('rootDir:path.join(__dirname,"src")','rootDir:"/tmp"','rootDir:"../outside"','rootDir:".",rootDir:"src"','rootDir:"<rootDir>/src"')):
  # <rootDir> is NOT substituted in the top-level root key: missing relative setup exposes this.
  fresh('roots-invalid'+str(i));config('module.exports={'+body+',setupFiles:"./src/setup.js"};');install();p=red()
  why='names no file in the repository' if i==4 else 'it sets rootDir'
  if p.returncode!=1 or why not in p.stdout+p.stderr:bad.append(body)
 assert not bad,('invalid roots accepted',bad)
 # rootDir in imported modules is forbidden even if it names the default folder.
 fresh('root-import');config('require("./opts");');write('opts.json','{"rootDir":"."}');install();p=red()
 assert p.returncode==1 and 'opts.json: it sets rootDir' in p.stdout+p.stderr
elif case=='json-invalid':
 bad=[]
 for i,value in enumerate(('null','[]','"bad"','{"globalSetup":7}','{"rootDir":false}','{"setupFiles":["./src/setup.js",null]}')):
  fresh('json-invalid'+str(i));manifest({'jest':json.loads(value)});install();p=red()
  if p.returncode!=1 or 'could not read the jest setup files of package.json:' not in p.stdout+p.stderr:bad.append(value)
 assert not bad,('invalid manifest options accepted',bad)
elif case=='symlink':
 bad=[]
 for i,(name,body) in enumerate((('alias.js','module.exports={setupFiles:"./alias.js"};'),('alias.js','require("./alias.js");'),('jest.config.cjs','module.exports={};'))):
  fresh('symlink'+str(i));config(body);Path(name).symlink_to('src/setup.js');install();p=red()
  if p.returncode!=1 or name+' is a symbolic link' not in p.stdout+p.stderr:bad.append(name)
 assert not bad,('symlink candidates accepted',bad)
elif case=='missing':
 bad=[]
 for i,(body,why) in enumerate((('setupFiles:"<rootDir>/missing.js"','<rootDir>/missing.js names no file in the repository'),('globalTeardown:"/tmp/end.js"','/tmp/end.js is an absolute path'),('setupFiles:"./ignored/boot.js"','./ignored/boot.js names no file in the repository'))):
  fresh('missing'+str(i));write('ignored/boot.js','// ignored');config('module.exports={'+body+'};');install();p=red()
  if p.returncode!=1 or why not in p.stdout+p.stderr:bad.append(body)
 assert not bad,('missing/absolute setup accepted',bad)
elif case=='order':
 fresh('order',command=COMMAND+' # vitest');config('module.exports={globalSetup:null};','z/jest.config.js');config('export default {test:{setupFiles:variable}};','a/vitest.config.ts');config('module.exports={setupFiles:variable};','a/jest.config.js')
 install();p=red();lines=refuse(p,'setup-unreadable','red')
 assert lines==['shipcraft refused: could not read the jest setup files of a/jest.config.js: setupFiles is not a string or an array of strings','Why: red locks the setup files it can name; one it cannot name could change what every locked case sees','Next: in a/jest.config.js, write setupFiles, setupFilesAfterEnv, globalSetup and globalTeardown as string literals or arrays of them, and rootDir, if any, as one relative string literal in the config file itself, then run red again'],lines
 assert not list(Path('.shipcraft/locks').glob('*.json')) and PREFIX not in p.stdout
 assert 'fake140:False' in Path('.git/shipcraft/output/red.log').read_text()
elif case=='notice':
 fresh('notice');names=['z.js','d.js','c.js','b.js','a.js']
 for n in names:write(n,'// '+n)
 config('module.exports={setupFiles:'+json.dumps(['./'+n for n in names])+'};');install();p=red();lines=p.stdout.splitlines()
 line=PREFIX+'jest reads beside the tests: a.js, b.js, c.js and 2 more'
 assert line in lines,(lines,line)
 at=lines.index(line);assert lines[at-1].startswith('shipcraft: controls:') and lines[at+1].startswith('shipcraft: RED locked at '),lines
 assert '9 file(s)' in lines[at+1],lines[at+1]
 assert all('setup.js' not in json.loads(l)['files'] and 'a.js' not in json.loads(l)['files'] for l in Path('.trace140').read_text().splitlines())
elif case=='mixed':
 fresh('mixed',command=COMMAND+' # vitest');config('require("./shared");module.exports={rootDir:"src"};');config('import "./shared";export default {};','vitest.config.ts')
 write('shared.ts','export default {setupFiles:"./boot.js",setupFilesAfterEnv:"./after.js"};');write('boot.js','// vitest root');write('src/boot.js','// jest root');write('src/after.js','// jest only')
 install();p=red();d=lock()[1]
 assert p.returncode==0 and {'shared.ts','boot.js','src/boot.js','src/after.js'}<=set(d['files']),d
 assert PREFIX+'vitest and jest read beside the tests:' in p.stdout
elif case=='control-vitest':
 fresh('control-vitest',command='tools/runner # vitest');config('export default {test:{setupFiles:"./src/setup.js"}};','vitest.config.ts');install();p=red()
 assert p.returncode==0 and PREFIX+'vitest reads beside the tests: src/setup.js' in p.stdout
 assert 'src/setup.js' in lock()[1]['files']
elif case=='redo-refused':
 fresh('redo-refused');config('module.exports={};');lf=seed();before=lf.read_bytes();config('module.exports={setupFilesAfterEnv:path.join("x")};');p=red('--redo');refuse(p,'setup-unreadable','red')
 assert lf.read_bytes()==before and PREFIX not in p.stdout and 'fake140:False' in Path('.git/shipcraft/output/red.log').read_text()
elif case=='io-failure':
 fresh('io-failure');config('module.exports={setupFiles:null};','a/jest.config.js');config('module.exports={};','z/jest.config.js');install();Path('z/jest.config.js').unlink();p=red()
 assert p.returncode==2 and not list(Path('.shipcraft/locks').glob('*.json')) and PREFIX not in p.stdout,(p.returncode,p.stdout,p.stderr)
 assert 'fake140:False' in Path('.git/shipcraft/output/red.log').read_text()
 fresh('io-lock-write');config('module.exports={setupFiles:"./src/setup.js"};');install();folder=Path('.shipcraft/locks');folder.chmod(0o555)
 try:p=red()
 finally:folder.chmod(0o755)
 assert p.returncode==2 and not list(folder.glob('*.json')) and PREFIX not in p.stdout,(p.returncode,p.stdout,p.stderr)
 assert 'fake140:False' in Path('.git/shipcraft/output/red.log').read_text()
elif case=='repro-c':
 fresh('repro-c',real=True);lf=seed();base=git('rev-parse','HEAD');control=green({'src/sum.js':'exports.sum=()=>{return 3};'});assert control.returncode==0 and lock()[1]['state']=='closed';git('reset','--hard',base);value=json.loads(Path('package.json').read_text());value['jest']={'moduleNameMapper':{'^\\./sum$':'<rootDir>/src/fake.js'}}
 p=green({'package.json':json.dumps(value),'src/fake.js':'exports.sum=()=>3;'});lines=refuse(p,'jest-config-changed','hook')
 assert "jest's settings in package.json were added in the index" in lines[0] and lock()[1]['state']=='open' and 'stub140' in Path('src/sum.js').read_text()
elif case=='repro-d':
 fresh('repro-d',real=True);lf=seed();p=green({'jest.config.js':'module.exports={setupFiles:["./src/boot.js"]};','src/boot.js':MOCK})
 lines=refuse(p,'runner-config-added','hook')
 assert lines==['shipcraft refused: runner config jest.config.js was added in the index with lock '+str(lf)+' open','Why: jest reads its settings from this file, so adding one during GREEN can change the judge mid-game','Next: remove jest.config.js; if the suite needs it, add it in a RED (shipcraft red --redo) or after the cycle closes'],lines
 assert lock()[1]['state']=='open' and 'stub140' in Path('src/sum.js').read_text()
 log=Path('.git/shipcraft/runs.jsonl');log.unlink();log.mkdir();q=run('git','commit','-qm','added config blocked log140')
 assert q.returncode==1 and [l for l in (q.stdout+q.stderr).splitlines() if l.startswith(('shipcraft refused:','Why:','Next:'))]==lines and log.is_dir() and lock()[1]['state']=='open'
elif case=='changed':
 fresh('changed');manifest({'jest':{'moduleNameMapper':{'old':'value'}}});lf=seed()
 p=green({'package.json':'{"jest":{"moduleNameMapper":{"old":"new"}}}','src/sum.js':'exports.sum=()=>{return 3};'});lines=refuse(p,'jest-config-changed','hook')
 assert lines==["shipcraft refused: jest's settings in package.json changed in the index with lock "+str(lf)+' open','Why: Jest reads how the suite runs from the jest key (setup files, module mappings, transforms), so changing it during GREEN changes the judge mid-game','Next: undo the change to the jest key in package.json; if the suite needs it, make it after the cycle closes'],lines
 assert 'running the suite' not in p.stdout+p.stderr and lock()[1]['state']=='open'
elif case=='removed':
 bad=[]
 for i,value in enumerate(('{}',None)):
  fresh('removed'+str(i));manifest({'jest':{}});lf=seed();p=green({'package.json':value,'src/sum.js':'exports.sum=()=>{return 3};'})
  if p.returncode!=1 or "jest's settings in package.json were removed" not in p.stdout+p.stderr:bad.append(i)
 assert not bad,('removed settings accepted',bad)
elif case=='control-equal':
 fresh('control-equal');manifest({'jest':{'verbose':True,'maxWorkers':1}});lf=seed()
 p=green({'package.json':'{ "jest": {"maxWorkers":99,"maxWorkers":1, "verbose":true}, "version":"2" }','src/sum.js':'exports.sum=()=>{return 3};'})
 assert p.returncode==0 and lock()[1]['state']=='closed' and git('show','HEAD:package.json').count('maxWorkers')==2
elif case=='control-deps':
 fresh('control-deps');manifest({'jest':{'verbose':True}});lf=seed()
 p=green({'package.json':'{"jest":{"verbose":true},"dependencies":{"new":"1"},"scripts":{"test":"other"},"version":"9"}','src/sum.js':'exports.sum=()=>{return 3};'})
 assert p.returncode==0 and lock()[1]['state']=='closed' and '"new"' in git('show','HEAD:package.json')
elif case=='invalid-manifest':
 bad=[]
 for i,value in enumerate((b'{bad',b'[]',b'{"jest":null}',b'{"jest":{"maxWorkers":1.0}}',b'\xef\xbb\xbf{"jest":1}',b'{"jest":"\xff"}')):
  fresh('invalid-manifest'+str(i));manifest({'jest':1});install()
  # Invalid schema must refuse at red, so use a valid object for the open fixture.
  manifest({'jest':{'maxWorkers':1}});commit('valid settings');p=red();assert p.returncode==0;commit('RED140')
  p=green({'package.json':value,'src/sum.js':'exports.sum=()=>{return 3};'})
  if p.returncode!=1 or "jest's settings in package.json changed" not in p.stdout+p.stderr:bad.append(repr(value))
 assert not bad,('invalid manifest transition accepted',bad)
elif case=='watched':
 fresh('watched',root='packages/api');
 for n in ('sum.js','sum.test.js','other.test.js','setup.js'):write('packages/api/src/'+n,Path('src/'+n).read_bytes())
 manifest({},'packages/package.json');lf=seed()
 p=green({'packages/package.json':'{"jest":{}}','packages/api/src/sum.js':'exports.sum=()=>{return 3};'})
 lines=refuse(p,'jest-config-changed','hook');assert 'packages/package.json were added' in lines[0]
elif case=='linked':
 fresh('linked');manifest({},'settings140');Path('package.json').unlink();Path('package.json').symlink_to('settings140');lf=seed()
 p=green({'settings140':'{"jest":{}}','src/sum.js':'exports.sum=()=>{return 3};'});lines=refuse(p,'jest-config-changed','hook')
 assert 'package.json are behind a symbolic link' in lines[0] and 'package.json' not in lock()[1]['files']
elif case=='ci':
 fresh('ci');lf=seed();p=green({'nested/package.json':'{"jest":{}}','src/sum.js':'exports.sum=()=>{return 3};'},ci=True)
 lines=refuse(p,'jest-config-changed','ci');assert 'nested/package.json were added in commit ' in lines[0] and lock()[1]['state']=='open'
 fresh('ci-added',command=COMMAND+' # vitest');lf=seed();p=green({'a/jest.config.cts':'module.exports={};','z/vitest.config.ts':'export default {};','src/sum.js':'exports.sum=()=>{return 3};'},ci=True)
 lines=refuse(p,'runner-config-added','ci');assert 'a/jest.config.cts was added' in lines[0] and lines[1]=='Why: jest reads its settings from this file, so adding one during GREEN can change the judge mid-game'
elif case=='control-merge':
 fresh('control-merge');lf=seed();branch=git('branch','--show-current');git('checkout','-qb','upstream140','HEAD^')
 manifest({'jest':{'verbose':True}});commit('upstream settings140');git('checkout',branch);git('merge','--no-commit','--no-ff','upstream140')
 write('src/sum.js','exports.sum=()=>{return 3};');commit('merged GREEN140')
 assert lock()[1]['state']=='closed' and 'verbose' in git('show','HEAD:package.json') and len(git('show','-s','--format=%P','HEAD^').split())==2
elif case=='index':
 fresh('index');lf=seed();write('package.json','{"jest":{}}');git('add','package.json');write('package.json','{}');p=run('git','commit','-qm','index settings140');lines=refuse(p,'jest-config-changed','hook')
 assert 'were added in the index' in lines[0] and 'running the suite' not in p.stdout+p.stderr
elif case=='control-index':
 fresh('control-index');lf=seed();before=Path('package.json').read_bytes();write('src/sum.js','exports.sum=()=>{return 3};');git('add','src/sum.js');manifest({'jest':{}});p=run('git','commit','-qm','staged product140')
 assert p.returncode==0 and lock()[1]['state']=='closed' and git('show','HEAD:package.json').encode()==before and 'jest' in Path('package.json').read_text()
elif case=='control-no-lock':
 fresh('control-no-lock');install();p=green({'package.json':'{"jest":{"setupFiles":null}}'})
 assert p.returncode==0 and 'no open lock; commit allowed' in p.stdout+p.stderr and not list(Path('.shipcraft/locks').glob('*.json'))
elif case=='log-failure':
 fresh('log-failure');config('module.exports={setupFiles:"./src/setup.js"};');install();log=Path('.git/shipcraft/runs.jsonl');log.unlink();log.mkdir();p=red()
 assert p.returncode==0 and 'src/setup.js' in lock()[1]['files'] and PREFIX+'jest reads beside the tests:' in p.stdout and log.is_dir()
 log.rmdir();commit('RED140');log.unlink();log.mkdir();p=green({'package.json':'{"jest":{}}','src/sum.js':'exports.sum=()=>{return 3};'})
 assert p.returncode==1 and "jest's settings in package.json were added" in p.stdout+p.stderr and log.is_dir() and lock()[1]['state']=='open'
elif case=='legacy':
 # Old lock fixture is sealed by the old public binary, never by modifying its JSON.
 fresh('legacy');lf=seed();before=json.loads(lf.read_text());assert 'package.json' not in before['files'] and before['format']==5
 p=green({'jest.config.json':'{}','src/sum.js':'exports.sum=()=>{return 3};'})
 lines=refuse(p,'runner-config-added','hook');assert 'jest.config.json was added' in lines[0] and lock()[1]['files']==before['files']
elif case=='json-reader':
 bad=[]
 for i,value in enumerate(('[]','null','{"setupFiles":null}','{"projects":[{"rootDir":false}]}')):
  fresh('json-reader'+str(i));config(value,'jest.config.json');install();p=red()
  if p.returncode!=1 or 'could not read the jest setup files of jest.config.json:' not in p.stdout+p.stderr:bad.append(value)
 assert not bad,('JSON options accepted',bad)
 fresh('strict-import');config('require("./options.json");');write('options.json','{ /* forbidden strict JSON */ "setupFiles":[] }');install();p=red()
 assert p.returncode==1 and 'options.json: it is not a JSON object' in p.stdout+p.stderr
else:raise AssertionError('unrouted '+case)
PY140
  pass
}
