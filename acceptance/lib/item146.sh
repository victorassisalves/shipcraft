# Item 146: printed invocation, black-box real Git and offline tools only.
item146_langs() { echo core; }
item146_cases() {
 local c
 for c in repro pnpm no-pnpm subfolder worktree nested red-stub redo install hook dirty missing-config export merge pr-origin uninstall-lock husky uninstall-changed status-block status-export status-protection pr-ready init-github close closing bare-lines hook-bytes usage ci-names machine-status machine-red boundaries snapshot root-walk no-double-pnpm git-control runner-control gh-control later-status; do echo "v1-146.$c"; done
}
item146_case() {
 EXPECT="item 146: ${CASE#v1-146.}"
 v1_start
 must_accept 'printed invocation contract' cmd "$PY" - "${CASE#v1-146.}" "$(command -v shipcraft)" "$CW" "$CB" "$ACEITE" <<'PY146'
import json,os,shlex,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw,cb,acceptance=sys.argv[1:]
binary=str(Path(binary).resolve());cw=Path(cw);cb=Path(cb);acceptance=Path(acceptance)
realgit=shutil.which('git')
def put(path,data,mode=0o644):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data.encode() if isinstance(data,str) else data);p.chmod(mode)
def run(*args,**kw):
 kw.setdefault('env',env)
 p=subprocess.run(list(map(str,args)),capture_output=True,timeout=60,**kw)
 print('$',shlex.join(map(str,args)),'exit',p.returncode,'stdout',repr(p.stdout),'stderr',repr(p.stderr),flush=True)
 return p
def ok(*args,**kw):
 p=run(*args,**kw);assert p.returncode==0,('fixture command',args,p.stdout,p.stderr);return p.stdout
def git(*args):return ok(realgit,*args).decode().strip()
def commit(message):
 git('add','-A');git('commit','-qm',message);return git('rev-parse','HEAD')
def install(root):
 target=root/'node_modules/shipcraft/bin/shipcraft';target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(binary,target)
 link=root/'node_modules/.bin/shipcraft';link.parent.mkdir(parents=True,exist_ok=True);link.symlink_to('../shipcraft/bin/shipcraft');return link
# Helpers construct fixtures, never hold an arm's expected output.
def fresh(name):
 global env
 root=cw/name;root.mkdir();os.chdir(root)
 tools=cw/(name+'-tools');tools.mkdir()
 for n in ('git','sh','dirname','mkdir','cat','rm','sleep','python3','jq'):(tools/n).symlink_to(shutil.which(n))
 (tools/'gh').symlink_to(cb/'gh');(tools/'state').symlink_to(cb/'state',target_is_directory=True)
 env=dict(os.environ,PATH=str(tools),GIT_ALLOW_PROTOCOL='file',GIT_OPTIONAL_LOCKS='0')
 git('init','-q','-b','main');git('config','user.name','Fixture146');git('config','user.email','fixture146@example.invalid')
 put('.gitignore','node_modules/\n')
 put('package.json','{"name":"x","version":"1.0.0","devDependencies":{"shipcraft":"*","vitest":"*"}}\n')
 put('value','0\n');put('tests/base.case','0\n')
 put('runner.py','''import os,sys,xml.etree.ElementTree as E
from pathlib import Path
r=E.Element('testsuites');s=E.SubElement(r,'testsuite',name='fixture146');failed=0
for p in sorted(Path('tests').glob('*.case')):
 t=E.SubElement(s,'testcase',classname=str(p),name='value',file=str(p))
 if p.name!='base.case' and p.read_text()!=Path('value').read_text():E.SubElement(t,'failure',message='value146');failed+=1
Path(sys.argv[1]).write_bytes(E.tostring(r));sys.exit(bool(failed))
''')
 call=install(root);base=commit('base146');return root,tools,call,base
def init(call):
 return ok(call,'init','--lang','other','--command',shlex.quote(sys.executable)+' runner.py {junit}','--glob','tests/*.case')
def configured():
 init(call);return commit('install146')
def redlock(filename='tests/new.case'):
 configured();git('checkout','-qb','change146');put(filename,'1\n');ok(call,'red','--all');commit('test: RED146')
 return next(Path('.shipcraft/locks').glob('*.json'))
def remote(base):
 origin=cw/'origin146.git';git('init','-q','--bare',origin);git('--git-dir='+str(origin),'symbolic-ref','HEAD','refs/heads/main')
 put(cb/'state/origin',str(origin));git('remote','add','origin',origin);git('push','-q','origin',base+':refs/heads/main');git('fetch','-q','origin');git('remote','set-head','origin','main')
def pnpm():put(tools/'pnpm','#!'+sys.executable+'\nfrom pathlib import Path\nPath('+repr(str(cw/'pnpm-ran'))+').write_text("ran")\nraise SystemExit(79)\n',0o755)
def proxy(body):
 (tools/'git').unlink();put(tools/'git','#!'+sys.executable+'\nimport os,sys,json\nfrom pathlib import Path\na=sys.argv[1:]\n'+body+'\nos.execv('+repr(realgit)+',['+repr(realgit)+',*a])\n',0o755)
def rows():
 p=Path(git('rev-parse','--git-common-dir'))/'shipcraft/runs.jsonl'
 return [json.loads(x) for x in p.read_text().splitlines()] if p.exists() else []
root,tools,call,base=fresh('project146')
if case=='repro':
 ok(call,'init','--lang','node');Path('.git/hooks/commit-msg').unlink();p=run(call,'status')
 assert p.returncode==0 and b'shipcraft: missing hook: the commit does not go through `npx -- shipcraft check`; run `npx -- shipcraft init`\n' in p.stdout,p.stdout
elif case=='pnpm':
 configured();put('pnpm-lock.yaml',b'not yaml\0\xff');pnpm();Path('.git/hooks/commit-msg').unlink();p=run(call,'status')
 assert p.returncode==0 and b'run `pnpm exec shipcraft init`' in p.stdout and b'`pnpm exec shipcraft check`' in p.stdout,p.stdout
elif case=='no-pnpm':
 configured();put('pnpm-lock.yaml','');Path('.git/hooks/commit-msg').unlink();p=run(call,'status')
 assert p.returncode==0 and b'run `npx -- shipcraft init`' in p.stdout,p.stdout
elif case=='subfolder':
 configured();Path('.git/hooks/commit-msg').unlink();sub=root/'packages/a/deep';sub.mkdir(parents=True);p=run(call,'status',cwd=sub)
 assert p.returncode==0 and b'run `npx -- shipcraft init`' in p.stdout,p.stdout
elif case=='worktree':
 configured();wt=cw/'linked146';git('worktree','add','-qb','linked146',wt);wc=install(wt);Path('.git/hooks/commit-msg').unlink();p=run(wc,'status',cwd=wt)
 assert p.returncode==0 and b'run `npx -- shipcraft init`' in p.stdout,p.stdout
elif case=='nested':
 configured();nested=root/'packages/a/node_modules/shipcraft/bin/shipcraft';nested.parent.mkdir(parents=True);shutil.copy2(binary,nested)
 Path('.git/hooks/commit-msg').unlink();p=run(nested,'status')
 assert p.returncode==0 and b'shipcraft: missing hook: the commit does not go through `shipcraft check`; run `shipcraft init`\n' in p.stdout
 assert b'npx --' not in p.stdout and b'pnpm exec' not in p.stdout
elif case=='red-stub':
 configured();git('checkout','-qb','change146');put('runner.py','raise SystemExit(1)\n');p=run(call,'red')
 assert p.returncode==1 and b'create the stub:' in p.stderr,p.stderr
 assert b'then run `npx -- shipcraft red` again' in p.stderr,p.stderr
 assert rows()[-1]['result']=='refused' and not list(Path('.shipcraft/locks').glob('*.json'))
elif case=='redo':
 lock=redlock();old=lock.read_bytes();put('runner.py','raise SystemExit(1)\n');p=run(call,'red','--redo')
 assert p.returncode==1 and b'run `npx -- shipcraft red --redo` again' in p.stderr,p.stderr
 assert lock.read_bytes()==old
elif case=='install':
 init(call);git('checkout','-qb','change146');put('tests/new.case','1\n');p=run(call,'red')
 assert p.returncode==1 and rows()[-1]['code']=='install-not-committed',(p.stderr,rows())
 assert b'then run `npx -- shipcraft red` again' in p.stderr,p.stderr
elif case=='hook':
 lock=redlock('tests/a shipcraft red.case');old=lock.read_bytes();put('tests/a shipcraft red.case','2\n');git('add','tests/a shipcraft red.case');p=run(realgit,'commit','-qm','wrong edit146')
 assert p.returncode==1 and rows()[-1]['code']=='test-changed',(p.stdout,p.stderr)
 assert b'Next: undo the change in tests/a npx -- shipcraft red.case;' in p.stderr,p.stderr
 assert b'locked test tests/a shipcraft red.case changed' in p.stderr and 'npx --' not in rows()[-1]['reason']
 assert lock.read_bytes()==old
elif case=='dirty':
 configured();put('.shipcraft.toml',Path('.shipcraft.toml').read_text()+'\n[build]\ncommand="true"\n');commit('build146');git('checkout','-qb','change146');put('value','dirty\n');p=run(call,'ci','--base','main')
 assert p.returncode==1 and rows()[-1]['code']=='build-dirty-tree',(p.stdout,p.stderr,rows())
 assert b'run `npx -- shipcraft ci` again' in p.stdout+p.stderr,p.stdout+p.stderr
elif case=='missing-config':
 p=run(call,'status')
 assert p.returncode==1 and b'Next: run `npx -- shipcraft init`' in p.stderr,p.stderr
 assert not Path('.shipcraft.toml').exists()
elif case=='export':
 configured();git('checkout','-qb','change146');p=run(call,'export','--base','main','clean146')
 assert p.returncode==1 and b'npx -- shipcraft pr' in p.stderr,p.stderr
 assert not run(realgit,'rev-parse','--verify','refs/heads/clean146').returncode==0
elif case=='merge':
 configured();p=run(call,'merge','1','--no-review','')
 assert p.returncode==1 and b'npx -- shipcraft merge' in p.stderr,p.stderr
elif case=='pr-origin':
 configured();git('checkout','-qb','change146');before=rows();p=run(call,'pr','--title','T146')
 assert p.returncode==1 and b'npx -- shipcraft ci --base main' in p.stderr,p.stderr
 assert rows()==before,'origin preflight must preserve the existing measurement log'
elif case=='uninstall-lock':
 lock=redlock();before=lock.read_bytes();p=run(call,'uninstall')
 assert p.returncode==1 and b'run npx -- shipcraft uninstall again' in p.stderr,p.stderr
 assert lock.read_bytes()==before and not Path('.git/shipcraft/uninstalled').exists()
elif case=='husky':
 # This refuses at the layout gate, before any launcher format is read.
 Path('.husky').mkdir();p=run(call,'init','--lang','node')
 assert p.returncode==1 and b'npx -- shipcraft init' in p.stderr,p.stderr
 assert not Path('.shipcraft.toml').exists()
elif case=='uninstall-changed':
 configured();old=Path('AGENTS.md').read_bytes();proxy("if 'ls-files' in a:\n with open('AGENTS.md','ab') as f:f.write(b'concurrent146\\n')")
 p=run(call,'uninstall')
 assert p.returncode==2 and Path('AGENTS.md').read_bytes()==old+b'concurrent146\n',(p.stdout,p.stderr)
 assert p.stderr==b'shipcraft: error: AGENTS.md changed since uninstall read it; nothing more was changed: run npx -- shipcraft uninstall again\n',p.stderr
 assert b'shipcraft: removed ' not in p.stdout
elif case=='status-block':
 configured();Path('AGENTS.md').unlink();p=run(call,'status')
 assert p.returncode==0 and b'shipcraft: AGENTS.md block: none; run `npx -- shipcraft init` to add it\n' in p.stdout,p.stdout
elif case=='status-export':
 remote(base);configured();p=run(call,'status')
 assert p.returncode==0 and b'`npx -- shipcraft export --base origin/main <new branch>`' in p.stdout,p.stdout
elif case=='status-protection':
 configured();remote(git('rev-parse','HEAD'));p=run(call,'status')
 assert p.returncode==0 and b'`npx -- shipcraft merge` is the gate' in p.stdout,p.stdout
elif case=='pr-ready':
 configured();remote(git('rev-parse','HEAD'));git('checkout','-qb','change146');put('product','146\n');commit('product146')
 # The generated config uses local CI and a real custom JUnit runner.
 put(cb/'state/sha',git('rev-parse','HEAD'));put(cw/'body','Body146\n');p=run(call,'pr','--title','T146','--body',cw/'body')
 assert p.returncode==0 and b'merge with `npx -- shipcraft merge 1`' in p.stdout,(p.stdout,p.stderr)
elif case=='init-github':
 remote(base);p=run(call,'init','--lang','node','--github')
 assert p.returncode==0 and b'this repository has no branch protection on its GitHub plan: `npx -- shipcraft merge` is the gate.' in p.stdout,(p.stdout,p.stderr)
elif case=='close':
 lock=redlock();put('value','1\n');git('add','value');put(cw/'message','GREEN146\n');ok(call,'check','--commit-msg',cw/'message')
 # Make the user's commit without calling post-commit, then hold the index lock.
 tree=git('write-tree');head=git('commit-tree',tree,'-p','HEAD','-m','GREEN146');git('update-ref','HEAD',head)
 put('.git/index.lock','busy146\n');before=lock.read_bytes();p=run(call,'close')
 assert p.returncode==0 and b'run `npx -- shipcraft close` manually.' in p.stdout+p.stderr,(p.stdout,p.stderr)
 assert lock.read_bytes()==before and Path('.git/shipcraft/close').exists()
elif case=='closing':
 p=init(call)
 assert p.count(b'shipcraft: then write the failing test and stub, and run `npx -- shipcraft red`.\n')==1,p
 assert b'npx -- npx --' not in p
elif case=='bare-lines':
 p=init(call)
 assert p.splitlines()[-1]==b'CI runs on this machine through shipcraft pr. To run it on GitHub, see shipcraft docs/github-ci.md.'
 commit('install146');remote(git('rev-parse','HEAD'));put('tests/new.case','1\n');q=run(call,'red','--all');assert q.returncode==0
 assert b'shipcraft pr refuses to open a PR from it' in q.stderr+q.stdout
 assert b'npx -- shipcraft pr refuses' not in q.stderr+q.stdout
 q=run(call,'pr','--title','T146');assert q.returncode==1 and b'Why:' in q.stderr and b'npx --' not in next(l for l in q.stderr.splitlines() if l.startswith(b'Why:'))
elif case=='hook-bytes':
 init(call)
 # Byte fixtures captured through public init on f369bf3 (2.84.0).
 for event in ('commit-msg','post-commit'):
  args='check --commit-msg "$1"' if event=='commit-msg' else 'close'
  desc='checks the commit against open locks' if event=='commit-msg' else 'closes the lock the commit-msg check marked'
  failure="install the project's dependencies" if event=='commit-msg' else "the lock stays open; install the project's dependencies and run node_modules/.bin/shipcraft close"
  expected=('#!/bin/sh\n# shipcraft hook: '+desc+'\nif [ ! -f "$(git rev-parse --show-toplevel)/node_modules/.bin/shipcraft" ] || [ ! -x "$(git rev-parse --show-toplevel)/node_modules/.bin/shipcraft" ]; then\n  echo "shipcraft: not installed in this checkout (node_modules/.bin/shipcraft): '+failure+'" >&2\n  exit '+('1' if event=='commit-msg' else '0')+'\nfi\nexec "$(git rev-parse --show-toplevel)/node_modules/.bin/shipcraft" '+args+'\n').encode()
  assert Path('.git/hooks/'+event).read_bytes()==expected,(event,Path('.git/hooks/'+event).read_bytes())
  assert stat.S_IMODE(Path('.git/hooks/'+event).stat().st_mode)==0o755
elif case=='usage':
 a=run(binary,'help');b=run(call,'help');assert a.returncode==b.returncode==0 and a.stdout==b.stdout and b'usage: shipcraft --version' in b.stdout
 a=run(binary,'--bogus146');b=run(call,'--bogus146');assert a.returncode==b.returncode==2 and a.stderr==b.stderr and b'usage: shipcraft' in b.stderr
elif case=='ci-names':
 configured();p=run(call,'ci','--base','HEAD')
 assert p.returncode==0 and b'shipcraft pr runs CI and publishes shipcraft/ci' in p.stdout+p.stderr,(p.stdout,p.stderr)
 assert b'npx -- shipcraft pr runs CI' not in p.stdout+p.stderr
elif case=='machine-status':
 configured();Path('.git/hooks/commit-msg').unlink();p=run(binary,'status')
 assert p.returncode==0 and b'shipcraft: missing hook: the commit does not go through `shipcraft check`; run `shipcraft init`\n' in p.stdout
 assert b'npx --' not in p.stdout and b'pnpm exec' not in p.stdout
elif case=='machine-red':
 configured();git('checkout','-qb','change146');put('runner.py','raise SystemExit(1)\n');p=run(binary,'red')
 assert p.returncode==1 and b'then run `shipcraft red` again' in p.stderr and b'npx --' not in p.stderr,p.stderr
elif case=='boundaries':
 configured()
 # A custom hook path is displayed verbatim in a routed status field. No hook runs.
 before="éshipcraft red;shipcraft init,shipcraft check)shipcraft close:shipcraft ci.shipcraft export'shipcraft pr\"shipcraft review`shipcraft merge shipcraft status;shipcraft report;shipcraft uninstall;shipcraft --version\nshipcraft red\rshipcraft red\n"
 after="énpx -- shipcraft red;npx -- shipcraft init,npx -- shipcraft check)npx -- shipcraft close:npx -- shipcraft ci.shipcraft export'npx -- shipcraft pr\"npx -- shipcraft review`npx -- shipcraft merge npx -- shipcraft status;npx -- shipcraft report;npx -- shipcraft uninstall;npx -- shipcraft --version\nshipcraft red\rnpx -- shipcraft red\n"
 keep='xshipcraft red -shipcraft red _shipcraft red /shipcraft red .shipcraft red shipcraft redness shipcraft red! shipcraft docs/github-ci.md npx -- shipcraft red pnpm exec shipcraft red'
 path=before+keep;git('config','core.hooksPath',path);p=run(call,'status')
 assert p.returncode==0 and (after+keep).encode() in p.stdout,p.stdout
elif case=='snapshot':
 configured();git('checkout','-qb','change146');pnpm();put('tests/new.case','1\n')
 cfg=Path('.shipcraft.toml').read_text();cfg=cfg.replace(shlex.quote(sys.executable)+' runner.py {junit}','false {junit}');put('.shipcraft.toml',cfg+'\n[build]\ncommand="echo created > pnpm-lock.yaml"\n');commit('build146');put('tests/new.case','2\n');p=run(call,'red')
 assert p.returncode==1 and Path('pnpm-lock.yaml').read_text()=='created\n',(p.stdout,p.stderr)
 assert b'npx -- shipcraft red' in p.stdout+p.stderr and b'pnpm exec shipcraft red' not in p.stdout+p.stderr,p.stdout+p.stderr
elif case=='root-walk':
 configured();Path('.git/hooks/commit-msg').unlink();put('pnpm-lock.yaml','');pnpm()
 sub=root/'packages/inner';sub.mkdir(parents=True);os.chdir(sub);git('init','-q','-b','main');nested=install(sub);put('package.json','{}');ok(nested,'init','--lang','node');Path('.git/hooks/commit-msg').unlink()
 p=run(nested,'status')
 assert p.returncode==0 and b'run `npx -- shipcraft init`' in p.stdout and b'pnpm exec' not in p.stdout,p.stdout
elif case=='no-double-pnpm':
 put('pnpm-lock.yaml','');pnpm();p=init(call)
 assert p.count(b'run `pnpm exec shipcraft red`.')==1 and b'pnpm exec pnpm exec' not in p and b'pnpm exec npx' not in p,p
elif case=='git-control':
 proxy("if a==['--version']:\n print('git version fixture146');sys.exit(0)\nif 'ls-files' in a:Path('git-control146').write_text('ls-files reached146')")
 p=run(tools/'git','--version');assert p.returncode==0 and p.stdout==b'git version fixture146\n'
 configured();p=run(tools/'git','ls-files','-z');assert p.returncode==0 and Path('git-control146').read_text()=='ls-files reached146' and b'runner.py\0' in p.stdout
 p=run(call,'status');assert p.returncode==0 and b'AGENTS.md block: current' in p.stdout
elif case=='runner-control':
 configured();git('checkout','-qb','change146');put('tests/new.case','1\n');ok(call,'red','--all');lock=next(Path('.shipcraft/locks').glob('*.json'));data=json.loads(lock.read_text())
 assert data['state']=='open' and data['failing_at_red']==['tests/new.case::value'] and data['cases']==['tests/base.case::value','tests/new.case::value'],data
 commit('test: control146');put('value','1\n');git('add','value');p=run(call,'check','--commit-msg','/dev/null')
 assert p.returncode==0 and Path('.git/shipcraft/close').is_file(),(p.stdout,p.stderr)
elif case=='gh-control':
 configured();remote(git('rev-parse','HEAD'));p=run(call,'status')
 assert p.returncode==0 and b'this repository has no branch protection (GitHub free plan)' in p.stdout,p.stdout
 calls=[json.loads(x) for x in (cb/'state/calls.log').read_text().splitlines()]
 assert any('protection' in ' '.join(c.get('argv',[])) for c in calls),calls
elif case=='later-status':
 configured();Path('.git/hooks/commit-msg').unlink();shutil.rmtree('.shipcraft/locks');put('.shipcraft/locks','blocked146');p=run(call,'status')
 assert p.returncode==2 and b'run `npx -- shipcraft init`' in p.stdout,(p.stdout,p.stderr)
 assert Path('.shipcraft/locks').read_text()=='blocked146'
else:raise AssertionError('unrouted case: '+case)
assert not (cw/'pnpm-ran').exists(),'invocation lookup executed pnpm'
PY146
 pass
}
