# Item 133: captured husky 7.0.4 and prek 0.5.3, all commands in disposable repos.
item133_cases() {
  local c
  for c in repro-a absent local insert-seven insert-eight no-helper misplaced cr noexec helper-invalid helper-link shim old-layout rollback cycle runner-npx runner-pnpm runner-other runner-twice control-husky repro-b prek-missing both-path mixed config-default config-other wrong-type commented control-pre stages-default stages-explicit stages-empty stages-many stages-rollback new-id legacy legacy-local legacy-different both-ids fixture-control; do
    echo "v1-133.$c"
  done
}
item133_case() {
  EXPECT='item 133 hook integration contract'
  v1_start codex claude
  must_accept 'item 133 contract' cmd "$PY" - "${CASE#v1-133.}" "$CW" <<'PY133'
import ast, copy, json, os, re, shlex, shutil, stat, subprocess, sys
from pathlib import Path
import yaml
case=sys.argv[1]; cw=Path(sys.argv[2]); binary=shutil.which('shipcraft')
fixtures=Path(os.environ['ACEITE'])/'fixtures/item133'
H7=(fixtures/'husky.sh').read_text(); PK=(fixtures/'prek-commit-msg').read_text()
source=(Path(os.environ['ACEITE'])/'lib/item25.sh').read_text().split("<<'PY25'\n",1)[1].split('\nPY25',1)[0]
constants={n.targets[0].id:ast.literal_eval(n.value) for n in ast.parse(source).body if isinstance(n,ast.Assign) and isinstance(n.targets[0],ast.Name) and n.targets[0].id in ('HUSKY_H','HUSKY_LAUNCHER','PRE_LAUNCHER')}
sys.path.insert(0,str(Path(os.environ['ACEITE'])/'tools'))
from lefthook_fixture import snapshot
E=('commit-msg','post-commit'); commands=('shipcraft check --commit-msg "$1"','shipcraft close')
header='#!/bin/sh\n. "$(dirname "$0")/_/husky.sh"\n'
warning='shipcraft: these pre-commit hooks have no stages in .pre-commit-config.yaml, so they also run at commit-msg and post-commit: '
end='; to keep them at pre-commit only, add stages: [pre-commit] to them or default_stages: [pre-commit] at the top'
def write(p,s,mode=0o644):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(s.encode() if isinstance(s,str) else s);p.chmod(mode)
def run(*args,env=None):
 p=subprocess.run(args,input='',capture_output=True,text=True,env=env,timeout=90)
 print('$',shlex.join(args),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 return p,p.stdout+p.stderr
def ok(*args,env=None):
 p,out=run(*args,env=env);assert p.returncode==0,('command refused',out);return out
def husky(version=7):
 ok('git','config','core.hooksPath','.husky' if version==7 else '.husky/_')
 if version==7:write('.husky/_/husky.sh',H7)
 else:
  write('.husky/_/h',constants['HUSKY_H'])
  for e in E:write('.husky/_/'+e,constants['HUSKY_LAUNCHER'],0o755)
 write('.husky/pre-commit',header+'# formatter133\n' if version==7 else '# formatter133\n',0o755)
def pre(launcher=PK):
 write('.pre-commit-config.yaml','repos:\n  - repo: local\n    hooks:\n      - id: lint\n        name: lint\n        entry: echo lint\n        language: system\n')
 if launcher:
  for e in E:write('.git/hooks/'+e,launcher.replace('--hook-type=commit-msg','--hook-type='+e),0o755)
def pair(old=False,local=False):
 data=yaml.safe_load(Path('.pre-commit-config.yaml').read_text())
 for e in E:
  data['repos'][0]['hooks'].append(dict(id='shipcraft-check' if e=='commit-msg' else ('shipcraft-fecha' if old else 'shipcraft-close'),name='shipcraft check' if e=='commit-msg' else 'shipcraft close',entry=('./node_modules/.bin/' if local else '')+('shipcraft check --commit-msg' if e=='commit-msg' else 'shipcraft close'),language='system',always_run=True,pass_filenames=False,stages=[e]))
 write('.pre-commit-config.yaml',yaml.safe_dump(data,sort_keys=False))
def refused(reason):
 before=snapshot();p,out=run(binary,'init');assert p.returncode==1,('refusal exit',out)
 assert snapshot()==before,'refusal changed tree or Git state'
 lines=out.strip().splitlines();assert len(lines)==3 and lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:'),out
 assert reason in out,(reason,out);assert warning not in out
 return out
def status(label,env=None):
 before=snapshot();out=ok(binary,'status',env=env);assert snapshot()==before,'status wrote state';assert label in out,(label,out);assert warning not in out;return out
def installed():
 for p in ('.shipcraft.toml','AGENTS.md','CLAUDE.md','.shipcraft/briefs/red.md','.shipcraft/briefs/green.md'):assert Path(p).is_file(),p
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'init wrote a row'
def pathenv(names):
 d=cw/'path133';d.mkdir(exist_ok=True)
 # Explicit allowlist avoids inherited managers and protected system directories.
 for name in ('git','sh','bash','env','dirname','basename','python3','pytest','codex','claude','gh','curl','node','npm'):
  found=shutil.which(name)
  if found and not (d/name).exists():(d/name).symlink_to(found)
 for name in names:write(d/name,'#!/bin/sh\nexit 97\n',0o755)
 env=os.environ.copy();env['PATH']=str(d);return env
if case=='repro-a':
 husky();write('package.json','{"devDependencies":{"husky":"7.0.4","vitest":"^2"}}\n');write('sample.test.js',"import {test,expect} from 'vitest'; test('ok',()=>expect(1).toBe(1));\n")
 for e,c in zip(E,commands):write('.husky/'+e,header+'npx --no -- '+c+'\n',0o755)
 before={str(p):p.read_bytes() for p in Path('.husky').rglob('*') if p.is_file()}
 p,out=run(binary,'init','--lang','node');assert p.returncode==0,'reproduction A: init refuses husky 7'
 installed();assert all(Path(p).read_bytes()==b for p,b in before.items());status('hook through husky (commit-msg)')
elif case in ('absent','local','insert-seven','insert-eight','noexec','rollback','cycle'):
 husky();call=binary;expected=list(commands)
 if case=='local':
  target=Path('node_modules/shipcraft-fixture/bin/shipcraft');target.parent.mkdir(parents=True);shutil.copy2(binary,target)
  link=Path('node_modules/.bin/shipcraft');link.parent.mkdir(parents=True);link.symlink_to('../shipcraft-fixture/bin/shipcraft');call=str(link.resolve());expected=['./node_modules/.bin/'+c for c in commands]
 old={}
 if case in ('insert-seven','insert-eight','noexec','cycle'):
  for e in E:
   text=(header if case!='insert-eight' else '#!/bin/sh\n# before\n\n\t. "$(dirname -- "$0")/_/husky.sh" # helper\n')+('echo project133\n' if case!='insert-seven' else '')
   if case=='insert-seven':text=text.rstrip('\n')
   write('.husky/'+e,text,0o644 if case=='noexec' else 0o755);old[e]=text
 if case=='rollback':write('.shipcraft','blocked133\n')
 before=snapshot();p,out=run(call,'init')
 if case=='rollback':
  assert p.returncode==2 and 'undid what this run created' in out,('later write not reached',out)
  assert snapshot()==before and warning not in out
 else:
  assert p.returncode==0,'valid husky 7 route refused';installed()
  for e,c in zip(E,expected):
   path=Path('.husky/'+e)
   wanted=header+'\n'+c+'\n' if e not in old else (old[e]+'\n'+c+'\n' if case=='insert-seven' else old[e].replace('echo project133\n',c+'\necho project133\n'))
   assert path.read_text()==wanted,(e,path.read_text(),wanted)
   assert stat.S_IMODE(path.stat().st_mode)==(0o644 if case=='noexec' else 0o755)
   assert '.husky/'+e in next(l for l in out.splitlines() if l.startswith('shipcraft: ready. Commit '))
  assert Path('.husky/_/husky.sh').read_text()==H7
  if case=='noexec':
   assert 'chmod +x .husky/commit-msg .husky/post-commit' in out
   status('chmod +x .husky/commit-msg .husky/post-commit')
  else:assert 'chmod +x' not in out;status('hook through husky (commit-msg)')
  stable=snapshot();ok(call,'init');assert snapshot()==stable,'reinit changed state'
  if case=='cycle':
   ok('git','add','-A');ok('git','commit','-qm','chore: init133')
   write('textutil.py','def slugify(text):\n    raise NotImplementedError\n');write('tests/test_slug.py','from textutil import slugify\ndef test_slug():\n    assert slugify("a") == "a"\n')
   ok(binary,'red');ok('git','add','-A');ok('git','commit','-qm','test: RED133')
   original=Path('tests/test_slug.py').read_text();write('tests/test_slug.py',original+'# changed133\n');write('textutil.py','def slugify(text):\n    return text\n');ok('git','add','-A')
   head=ok('git','rev-parse','HEAD');p,out=run('git','commit','-qm','feat: forbidden133');assert p.returncode!=0 and ok('git','rev-parse','HEAD')==head
   write('tests/test_slug.py',original);ok('git','add','-A');ok('git','commit','-qm','feat: GREEN133')
   assert ok('git','log','-1','--format=%s').startswith('chore(shipcraft): close lock ')
   locks=list(Path('.shipcraft/locks').glob('*.json'));assert len(locks)==1 and json.loads(locks[0].read_text())['state']=='closed'
   rows=[json.loads(l) for l in Path('.git/shipcraft/runs.jsonl').read_text().splitlines()];assert any(r['layer']=='hook' for r in rows) and any(r['layer']=='close' for r in rows)
elif case in ('no-helper','misplaced','cr','helper-invalid','helper-link','shim','old-layout'):
 husky()
 if case=='no-helper':
  write('.husky/commit-msg','#!/bin/sh\nshipcraft check --commit-msg "$1"\necho ok\n',0o755);refused('does not source .husky/_/husky.sh')
 elif case=='misplaced':
  for text in (header+'echo skip\n'+commands[0]+'\n','#!/bin/sh\n'+commands[0]+'\n'+header.split('\n',1)[1]):
   write('.husky/commit-msg',text,0o755);refused('does not call shipcraft right after sourcing' if text.startswith(header) else 'does not source')
 elif case=='cr':
  write('.husky/commit-msg',b'#!/bin/sh\r\nexit 0\r\n',0o755);refused('has CR line endings')
 elif case=='old-layout':
  write('package.json','{"husky":{"hooks":{"pre-commit":"echo lint"}}}\n');out=refused('form of husky 4 and earlier');assert 'manually put' not in out and 'npx husky init' in out
 else:
  if case=='helper-invalid':write('.husky/_/husky.sh',':\n')
  elif case=='helper-link':Path('.husky/_/husky.sh').unlink();write('helper133',H7);Path('.husky/_/husky.sh').symlink_to('../../helper133')
  elif case=='shim':write('.husky/_/h',constants['HUSKY_H'])
  out=refused('neither husky 9');assert 'manually put' not in out and 'npx husky install' in out
elif case in ('runner-npx','runner-pnpm','runner-other','runner-twice','control-husky'):
 husky(9)
 if case=='runner-twice':
  write('.husky/pre-commit','exec npx --no -- shipcraft check\n');refused('twice')
 elif case=='runner-other':
  write('.husky/commit-msg','npx --no -- shipcraft check --other\n');refused('already calls shipcraft another way')
 else:
  prefixes=['npx --no ','npx --no -- '] if case=='runner-npx' else ['pnpm exec ','pnpm exec -- '] if case=='runner-pnpm' else ['','']
  for e,c,prefix in zip(E,commands,prefixes):write('.husky/'+e,prefix+c+'\n')
  before={e:Path('.husky/'+e).read_bytes() for e in E};ok(binary,'init')
  assert all(Path('.husky/'+e).read_bytes()==before[e] for e in E),'runner call duplicated'
  status('hook through husky (commit-msg)');assert Path('.husky/_/h').read_text()==constants['HUSKY_H']
  if case=='control-husky':
   for prefix in ('yarn ','npx ','npx -- ','bunx '):
    write('.husky/post-commit',prefix+'shipcraft close\n');ok(binary,'init')
    assert Path('.husky/post-commit').read_text()=='shipcraft close\n'+prefix+'shipcraft close\n'

elif case in ('repro-b','prek-missing','both-path','mixed','config-default','config-other','wrong-type','commented','control-pre'):
 pre(constants['PRE_LAUNCHER'] if case=='control-pre' else None if case in ('prek-missing','both-path') else PK)
 env=pathenv(['prek','pre-commit'] if case=='both-path' else ['prek'])
 if case=='mixed':write('.git/hooks/post-commit',constants['PRE_LAUNCHER'].replace('--hook-type=commit-msg','--hook-type=post-commit'),0o755)
 if case in ('config-default','config-other','wrong-type','commented'):
  raw=PK
  if case=='config-default':raw=raw.replace(' -- ', ' --config=".pre-commit-config.yaml" -- ')
  elif case=='config-other':raw=raw.replace(' -- ', ' --config="other.yaml" -- ')
  elif case=='wrong-type':raw=raw.replace('--hook-type=commit-msg','--hook-type=post-commit')
  else:raw=raw.replace('exec "$PREK"','# exec "$PREK"')
  write('.git/hooks/commit-msg',raw,0o755)
 if case in ('config-other','wrong-type','commented'):
  refused('installed hook commit-msg (.git/hooks/commit-msg) is not from pre-commit or prek')
  if case=='config-other':
   for option in ('--config other.yaml','-c other.yaml','--config-extra=x'):
    write('.git/hooks/commit-msg',PK.replace(' -- ',' '+option+' -- '),0o755)
    refused('installed hook commit-msg (.git/hooks/commit-msg) is not from pre-commit or prek')
  elif case=='commented':
   write('.git/hooks/commit-msg',PK.replace('exec "$PREK"','echo exec "$PREK"'),0o755)
   refused('installed hook commit-msg (.git/hooks/commit-msg) is not from pre-commit or prek')

 else:
  before={e:Path('.git/hooks/'+e).read_bytes() for e in E if Path('.git/hooks/'+e).exists()}
  p,out=run(binary,'init',env=env);assert p.returncode==0,'prek launcher refused'
  assert all(Path('.git/hooks/'+e).read_bytes()==b for e,b in before.items())
  name='pre-commit' if case in ('both-path','control-pre') else 'prek'
  if case in ('prek-missing','both-path'):
   assert name+' install -t commit-msg -t post-commit' in out;status(name+' install -t commit-msg -t post-commit',env)
  else:status('hook through '+name+' (commit-msg)',env)
  if case=='repro-b':
   assert warning+'lint'+end in out
   assert out.index(warning)<out.index('shipcraft: review by ')
  if case=='prek-missing':
   assert warning+'lint'+end in out
   assert out.index('still need to install')<out.index(warning)<out.index('shipcraft: review by ')

  if case=='control-pre':assert Path('.git/hooks/commit-msg').read_text()==constants['PRE_LAUNCHER']
  if case=='config-default':
   write('.git/hooks/commit-msg',PK.replace(' -- ', ' --config=\".pre-commit-config.yaml\" -- ').replace('\n','\r\n'),0o755)
   ok(binary,'init',env=env);status('hook through prek (commit-msg)',env)
  if case=='mixed':
   write('.git/hooks/commit-msg',constants['PRE_LAUNCHER'],0o755)
   write('.git/hooks/post-commit',PK.replace('--hook-type=commit-msg','--hook-type=post-commit'),0o755)
   ok(binary,'init',env=env);status('hook through prek (commit-msg)',env)

elif case in ('stages-default','stages-explicit','stages-empty','stages-many','stages-rollback','new-id','legacy','legacy-local','legacy-different','both-ids'):
 pre(constants['PRE_LAUNCHER'])
 if case in ('legacy','legacy-local','legacy-different','both-ids'):pair(True,case=='legacy-local')
 data=yaml.safe_load(Path('.pre-commit-config.yaml').read_text());hooks=data['repos'][0]['hooks']
 if case=='stages-default':data['default_stages']=['pre-commit']
 elif case=='stages-explicit':hooks[0]['stages']=['pre-commit']
 elif case=='stages-empty':hooks[0]['stages']=[];data['default_stages']=[]
 elif case=='stages-many':
  hooks[:]=[dict(hooks[0],id=i) for i in ('lint','two','lint','three','four')]
 elif case=='legacy-different':hooks[-1]['always_run']=False
 elif case=='both-ids':hooks.append(dict(copy.deepcopy(hooks[-1]),id='shipcraft-close'));hooks[-2]['entry']='echo wrong'
 write('.pre-commit-config.yaml',yaml.safe_dump(data,sort_keys=False));raw=Path('.pre-commit-config.yaml').read_bytes()
 if case=='legacy-different':refused('shipcraft-fecha')
 elif case=='both-ids':
  refused('.pre-commit-config.yaml has both shipcraft-close and shipcraft-fecha (post-commit)')
  # Across repos, reversed order, and with both hooks otherwise canonical.
  old=copy.deepcopy(hooks[-2]);old['entry']='shipcraft close';new=copy.deepcopy(hooks[-1])
  write('.pre-commit-config.yaml',yaml.safe_dump({'repos':[{'repo':'local','hooks':[new]},{'repo':'local','hooks':[old]}]},sort_keys=False))
  refused('.pre-commit-config.yaml has both shipcraft-close and shipcraft-fecha (post-commit)')

 else:
  if case=='stages-rollback':write('.shipcraft','blocked133\n')
  before=snapshot();p,out=run(binary,'init')
  if case=='stages-rollback':assert p.returncode==2 and snapshot()==before and warning not in out
  else:
   assert p.returncode==0,('valid YAML refused',out)
   if case in ('stages-default','stages-explicit'):assert warning not in out
   elif case in ('stages-empty','stages-many'):
    want='lint, two, three and 1 more' if case=='stages-many' else 'lint'
    assert warning+want+end in out,(want,out)
    assert out.index(warning)<out.index('shipcraft: ready. Commit ')
    again=ok(binary,'init');assert warning+want+end in again
   elif case=='new-id':
    hs=[h for r in yaml.safe_load(Path('.pre-commit-config.yaml').read_text())['repos'] for h in r['hooks']]
    close=[h for h in hs if h['id']=='shipcraft-close'];assert len(close)==1 and close[0]==dict(id='shipcraft-close',name='shipcraft close',entry='shipcraft close',language='system',always_run=True,pass_filenames=False,stages=['post-commit'])
    assert not any(h['id']=='shipcraft-fecha' for h in hs)
    assert 'plain git hooks, lefthook, husky (9, 7 and 8), pre-commit and prek' in (Path(os.environ['ACEITE']).parent/'README.md').read_text()
   elif case in ('legacy','legacy-local'):
    assert Path('.pre-commit-config.yaml').read_bytes()==raw,'legacy hook migrated or duplicated';status('hook through pre-commit (commit-msg)')
elif case=='fixture-control':
 # Execute captured scripts against owned sentinels, never a real package manager.
 husky()
 write('.husky/probe133',header+'false\nprintf missed > helper-missed133\n',0o755)
 p,out=run('sh','.husky/probe133');assert p.returncode!=0 and 'hook exited with code' in out and not Path('helper-missed133').exists()
 shutil.rmtree('.husky');ok('git','config','--unset','core.hooksPath')
 fake=cw/'fake-prek133';write(fake,'#!/bin/sh\nprintf "%s\\n" "$@" > '+shlex.quote(str(cw/'prek-args133'))+'\n',0o755)
 launcher=re.sub(r'^PREK=.*$', 'PREK='+shlex.quote(str(fake)),PK,flags=re.M)
 write('launcher133',launcher,0o755);ok('sh','launcher133','message133')
 args=(cw/'prek-args133').read_text().splitlines();assert args[0]=='hook-impl' and '--hook-type=commit-msg' in args and args[-2:]==['--','message133']
 pre(constants['PRE_LAUNCHER']);env=pathenv(['pre-commit','prek']);ok(binary,'init',env=env);status('hook through pre-commit (commit-msg)',env)
 assert Path('.git/hooks/commit-msg').read_text()==constants['PRE_LAUNCHER']
else:raise AssertionError('unrouted '+case)
PY133
  pass
}
