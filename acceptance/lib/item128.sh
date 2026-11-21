# Item 128: spec 7cab58d; real git and the existing offline gh protocol.
item128_langs() { echo core; }
item128_cases() {
  local c
  for c in ci-first ci-pr ci-tree-diff ci-suite-fails ci-build-fails ci-control ci-deletes ci-neither ci-head-invalid ci-base-invalid ci-legacy pr-first pr-missing-ref pr-local pr-main pr-create-error pr-summary-error pr-control pr-neither pr-invalid pr-legacy pr-merge merge-first merge-other merge-error merge-refused merge-control merge-invalid merge-neither pr-local-control readme readme-once pr-tree-diff merge-tree-diff pr-unreadable merge-legacy ci-read-error pr-resolve-error git-control merge-missing-ref; do echo "v1-128.$c"; done
}
item128_case() {
  EXPECT="item 128: ${CASE#v1-128.}"
  v1_start codex
  must_accept 'item128 contract' cmd "$PY" - "${CASE#v1-128.}" "$(command -v shipcraft)" "$CB" "$CW" "$ACEITE/../README.md" <<'PY128'
import hashlib,json,os,re,shutil,subprocess,sys
from pathlib import Path
case,binary,cb,cw,readme=sys.argv[1:];cb=Path(cb);cw=Path(cw);st=cb/'state';binary=str(Path(binary).resolve())
def run(*args,**kw):
 p=subprocess.run(list(map(str,args)),capture_output=True,text=True,timeout=90,**kw)
 print('$',repr(args),'rc',p.returncode,'\n'+p.stdout+p.stderr,flush=True)
 return p
def git(*args,**kw):
 p=run('git',*args,**kw);assert p.returncode==0,p.stderr
 return p.stdout.strip()
def write(p,s):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s)
def snapshot(msg):
 git('add','-A');tree=git('write-tree');parent=git('rev-parse','HEAD')
 sha=git('commit-tree',tree,'-p',parent,input=msg+'\n');git('update-ref','HEAD',sha);return sha
def records(p):return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
# Exact routing supplies inputs only; no helper supplies expected output.
command='ci';base_kind='absent';tree_kind='valid';ci='off';fault='';extra=[];want=0;notice=True;twice=False;name='main';head_ci=None;base_marker=False
if case=='ci-first': pass
elif case=='ci-pr': extra=['--pr']
elif case=='ci-tree-diff': tree_kind='different'
elif case=='ci-suite-fails': fault='suite';want=1
elif case=='ci-build-fails': fault='build';want=1
elif case=='ci-control': base_kind='valid';notice=False;base_marker=True
elif case=='ci-deletes': base_kind='valid';tree_kind='absent';notice=False
elif case=='ci-neither': tree_kind='absent';notice=False;want=1
elif case=='ci-head-invalid': tree_kind='wrong-type';notice=False;want=1
elif case=='ci-base-invalid': base_kind='invalid';notice=False;want=1
elif case=='ci-legacy': base_kind='legacy';notice=False;want=1
elif case=='pr-first': command='pr'
elif case=='pr-missing-ref': command='pr';fault='missing-ref';want=2
elif case=='pr-local': command='pr';ci='local'
elif case=='pr-main': command='pr';fault='main';want=1
elif case=='pr-create-error': command='pr';fault='create';want=2
elif case=='pr-summary-error': command='pr';fault='comment';want=2
elif case=='pr-control': command='pr';base_kind='valid';notice=False;head_ci='github'
elif case=='pr-neither': command='pr';tree_kind='absent';notice=False;want=1
elif case=='pr-invalid': command='pr';tree_kind='invalid';notice=False;want=1
elif case=='pr-legacy': command='pr';base_kind='legacy';notice=False;want=1
elif case=='pr-merge': command='pr';extra=['--merge'];twice=True
elif case=='merge-first': command='merge'
elif case=='merge-other': command='merge';name='release/128'
elif case=='merge-error': command='merge';fault='merge';want=2
elif case=='merge-refused': command='merge';ci='github';want=1
elif case=='merge-control': command='merge';base_kind='valid';notice=False;head_ci='github'
elif case=='merge-invalid': command='merge';tree_kind='invalid';notice=False;want=1
elif case=='merge-neither': command='merge';tree_kind='absent';notice=False;want=1
elif case=='pr-local-control': command='pr';ci='local';base_kind='valid';notice=False;head_ci='off'
elif case=='pr-tree-diff': command='pr';tree_kind='head-different'
elif case=='merge-tree-diff': command='merge';tree_kind='head-different'
elif case=='pr-unreadable': command='pr';tree_kind='directory';notice=False;want=1
elif case=='merge-legacy': command='merge';base_kind='legacy';notice=False;want=1
elif case=='ci-read-error': base_kind='valid';fault='read-error';notice=False;want=2
elif case=='pr-resolve-error': command='pr';fault='resolve-error';notice=False;want=2
elif case=='git-control': command='pr';base_kind='valid';fault='git-control';notice=False;head_ci='github'
elif case=='merge-missing-ref': command='merge';fault='missing-after-fetch'
elif case=='readme': pass
elif case=='readme-once': pass
else:raise AssertionError('unrouted '+case)
os.environ['XDG_STATE_HOME']=str(cw/'xdg128')
base=git('rev-parse','HEAD')
p=run(binary,'init');assert p.returncode==0,p.stderr
config=Path('.shipcraft.toml').read_text();a,b=config.split('[execution]',1);block,sep,tail=b.partition('[roles]')
block=re.sub(r'(?m)^ci\s*=.*$', 'ci = '+json.dumps(ci),block);block=re.sub(r'(?m)^review\s*=.*$', 'review = "off"',block)
config=a+'[execution]'+block+sep+tail
if fault=='build':config+='\n[build]\ncommand = "exit 29"\n'
write('.shipcraft.toml',config)
if base_kind=='valid':
 if base_marker:write('.shipcraft.toml','check = "echo BASE128 >&2"\n'+config)
 base=snapshot('chore: configured base128');write('.shipcraft.toml',config)
elif base_kind=='invalid':
 write('.shipcraft.toml','broken = [\n');base=snapshot('chore: invalid base128');write('.shipcraft.toml',config)
elif base_kind=='legacy':
 Path('.shipcraft.toml').unlink();write('.sc2.toml',config);base=snapshot('chore: legacy base128');Path('.sc2.toml').unlink();write('.shipcraft.toml',config)
git('update-ref','refs/heads/'+name,base)
origin=cb/'origin.git';git('init','-q','--bare',origin);git('--git-dir='+str(origin),'symbolic-ref','HEAD','refs/heads/'+name);write(st/'origin',str(origin))
git('remote','add','origin',str(origin));git('push','-q','origin',name);git('fetch','-q','origin');git('remote','set-head','origin',name)
git('checkout','-qb','feature/item128')
if head_ci is not None:write('.shipcraft.toml',config.replace('ci = '+json.dumps(ci),'ci = '+json.dumps(head_ci)))
if tree_kind=='absent':Path('.shipcraft.toml').unlink()
elif tree_kind=='invalid':write('.shipcraft.toml','broken = [\n')
elif tree_kind=='wrong-type':write('.shipcraft.toml',config.replace('ci = "off"','ci = true'))
if fault=='suite':write('tests/test_failure128.py','def test_failure128():\n    assert False\n')
if tree_kind=='head-different':write('.shipcraft.toml',config.replace('ci = "off"','ci = "github"'))
write('value128','feature128\n');head=snapshot('chore: install128');write(st/'sha',head)
if tree_kind=='head-different':write('.shipcraft.toml',config.replace('ci = "off"',"ci = 'off' # literal and inline comment128").replace('\n','\r\n'))
if tree_kind=='directory':
 Path('.shipcraft.toml').unlink();Path('.shipcraft.toml').mkdir()
if tree_kind=='different':write('.shipcraft.toml','broken = [\n')
if fault=='main':git('symbolic-ref','HEAD','refs/heads/'+name);git('update-ref','HEAD',head)
write(cw/'body128','Body marker128\n')
if command=='merge':
 git('push','-q','origin','feature/item128')
 p=run('gh','pr','create','--title','Item128','--body','Body marker128','--head','feature/item128','--base',name);assert p.returncode==0,p.stderr
# Copy item110's delegating gh proxy pattern, with its real existing gh protocol.
shutil.move(cb/'gh',cb/'gh128-real')
write(cb/'gh',"#!/usr/bin/env python3\nimport os,sys\nfrom pathlib import Path\na=sys.argv[1:];cb=Path(__file__).parent\nif a[:2]==['pr',"+repr(fault)+"]:\n print('gh: injected128 failure (HTTP 503)',file=sys.stderr);sys.exit(1)\nos.execv(str(cb/'gh128-real'),[str(cb/'gh128-real'),*a])\n");(cb/'gh').chmod(0o755)
# A real clone can omit its default branch from its fetch refspec.
if fault=='missing-ref':
 git('config','remote.origin.fetch','+refs/heads/feature/item128:refs/remotes/origin/feature/item128')
 git('push','-q','origin','feature/item128');git('update-ref','-d','refs/remotes/origin/'+name)
# Transparent Git proxy: real object reads except the explicitly injected failure.
realgit=shutil.which('git')
write(cb/'git',"#!/usr/bin/env python3\nimport os,sys,subprocess\na=sys.argv[1:];real="+repr(realgit)+";fault="+repr(fault)+";base="+repr(base)+"\n"+
 "if fault=='resolve-error' and 'rev-parse' in a and any(x in ('origin/main','origin/main^{commit}') for x in a):\n print('fatal: injected128 resolve failure',file=sys.stderr);sys.exit(128)\n"+
 "if fault=='read-error' and any(x in ('show','cat-file') for x in a) and base+':.shipcraft.toml' in a:\n print('fatal: injected128 read failure',file=sys.stderr);sys.exit(128)\n"+
 "if fault=='missing-after-fetch' and 'rev-parse' in a and any(x in ('origin/main','origin/main^{commit}') for x in a):sys.exit(1)\n"+
 "os.execv(real,[real,*a])\n");(cb/'git').chmod(0o755)
before=records(Path('.git/shipcraft/runs.jsonl'))
if command=='ci':args=['ci','--base',base,*extra]
elif command=='pr':args=['pr','--title','Item128','--body',str(cw/'body128'),*extra]
else:args=['merge','1']
p=run(binary,*args)
if base_marker:assert 'BASE128' in p.stderr,'base check did not run'
assert p.returncode==want,('exit',want,p.returncode,p.stderr)
ci_line=f"shipcraft: the base {base[:7]} has no .shipcraft.toml, so this range is judged by HEAD's (a first install is judged by the config it adds).\n"
pr_line=f"shipcraft: origin/{name} has no .shipcraft.toml, so this PR is judged by the working tree's (a first install is judged by the config it adds).\n"
if fault in ('missing-ref','missing-after-fetch'):pr_line=f"shipcraft: origin/{name} is not in this clone, so this PR is judged by the working tree's .shipcraft.toml (fetch origin/{name} if it has one).\n"
line=ci_line if command=='ci' else pr_line
rs=records(Path('.git/shipcraft/runs.jsonl'))[len(before):]
if want==1:
 lines=p.stderr.strip().splitlines()[-3:];assert len(lines)==3 and all(x.startswith(y) for x,y in zip(lines,['shipcraft refused:','Why:','Next:'])),p.stderr
if want==2:assert ('merge-base origin/main HEAD' if fault=='missing-ref' else 'injected128') in p.stderr,p.stderr
if command=='merge':assert len([r for r in rs if r['layer']=='merge'])==(1 if want==0 else 0),rs
if fault=='comment':assert any(r['layer']=='pr' and r['result']=='error' for r in rs),rs
if fault=='create' or fault=='main':assert not any(r['layer']=='pr' for r in rs),rs
if command=='ci':assert any(r['layer']=='ci' and r['result']==('passed' if want==0 else 'error' if want==2 else 'refused') for r in rs),rs
# The notice is terminal information, never a row, status, body or summary field.
for file in (Path('.git/shipcraft/runs.jsonl'),st/'statuses.jsonl',st/'comments.jsonl',st/'prs.json'):
 if file.is_file():assert 'so this range is judged' not in file.read_text() and 'so this PR is judged' not in file.read_text(),file
sentence="When the base branch has no `.shipcraft.toml` yet (the PR that installs Shipcraft), there is nothing on the base to switch off, so another config judges the PR: `shipcraft ci` uses the one committed at the PR's HEAD, and `shipcraft pr` and `shipcraft merge` use the one in the working tree where they run. Each says so in one line."
if case=='readme':
 text=Path(readme).read_text();anchor="**A PR is judged by the config on the base branch,** not by its own. A PR can't switch off its own review."
 assert anchor+' '+sentence in text,text
elif case=='readme-once':
 text=Path(readme).read_text();assert text.count(sentence)==1
 assert hashlib.sha256(text.replace(' '+sentence,'').encode()).hexdigest()=='d98fd8a51a190427763b20812ed227d6d84e0386878258cbbe0fa6d201a6eec1','other README bytes changed'
elif notice:
 assert p.stdout.startswith(line),p.stdout
 assert p.stdout.count(line)==(2 if twice else 1),p.stdout
 assert line not in p.stderr,p.stderr
 if command=='ci' and want==0:
  assert p.stdout==line+f'shipcraft: 1 commit(s) checked in {base[:7]}..HEAD\nshipcraft: CI ok.\nshipcraft: ci publishes no status; with ci = "off", shipcraft pr publishes shipcraft/ci as off.\n',p.stdout
 if command=='pr' and ci=='local':assert p.stdout.count(ci_line)==1 and p.stdout.index(ci_line)>p.stdout.index(pr_line),p.stdout
 if twice:assert p.stdout.index(' ready:')<p.stdout.rindex(line)<p.stdout.index(' merged into '),p.stdout
else:
 assert 'so this range is judged' not in p.stdout+p.stderr and 'so this PR is judged' not in p.stdout+p.stderr,p.stdout
 if command=='ci' and want==0:assert p.stdout==f'shipcraft: 1 commit(s) checked in {base[:7]}..HEAD\nshipcraft: CI ok.\nshipcraft: ci publishes no status; with ci = "off", shipcraft pr publishes shipcraft/ci as off.\n',p.stdout
 if command=='pr' and want==0:
  prefix=f'shipcraft: feature/item128 published to origin ({head[:7]})\nshipcraft: PR #1\nshipcraft: Size: 1 product lines against a limit of 500 (+1 / -0, counted as in the PR summary).\n'
  middle='shipcraft: CI off in .shipcraft.toml\n' if ci=='off' else f'shipcraft: CI on this machine: shipcraft ci --base origin/main ({base[:7]}, up to 1800 s)\nshipcraft: 1 commit(s) checked in {base[:7]}..HEAD\nshipcraft: CI ok.\nshipcraft: ci publishes no status; shipcraft pr runs CI and publishes shipcraft/ci on HEAD.\nshipcraft: shipcraft/ci success: on this machine: CI passed\n'
  assert p.stdout==prefix+middle+'shipcraft: review off in .shipcraft.toml\nshipcraft: PR #1 ready: enabled layers passed; merge with `shipcraft merge 1`.\n',p.stdout
  assert p.stdout.endswith('shipcraft: PR #1 ready: enabled layers passed; merge with `shipcraft merge 1`.\n'),p.stdout
  assert {r['context'] for r in records(st/'statuses.jsonl') if r['state']=='success'}=={'shipcraft/ci','shipcraft/review'}
 if command=='merge' and want==0:assert json.loads((st/'prs.json').read_text())['1']['state']=='MERGED'
PY128
  pass
}
