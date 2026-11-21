# Item 148: lefthook v1.11.13 launchers, offline tool exits 0.
item148_langs() { echo core; }
item148_cases() {
 local c
 for c in precommit-only empty-file blocks-exist fourth-name commands-only crlf indent-four comments project-local no-final-newline null-block null-commands empty-post-key bom mixed-forms trailing-fragment edited-run extra-skip one-edited comment-shipcraft project-shipcraft invalid-utf8 duplicate-key two-files copies-mode tracked-paths untracked-path dry-run second-run changed-since-plan later-failure readme spec-row control-init control-status control-refusal control-other-sources control-observer; do echo "v1-148.$c"; done
}
item148_case() {
 EXPECT="item 148: ${CASE#v1-148.}"
 v1_start codex claude
 must_accept 'lefthook uninstall contract' cmd "$PY" - "${CASE#v1-148.}" "$(command -v shipcraft)" "$CW" "$ACEITE" <<'PY148'
import os,re,shutil,stat,subprocess,sys
from pathlib import Path
case,binary,cw,acceptance=sys.argv[1:];binary=str(Path(binary).resolve());cw=Path(cw);acceptance=Path(acceptance)
sys.path.insert(0,str(acceptance/'tools'))
from lefthook_fixture import HOOK
def run(*args,**kw):
 p=subprocess.run(list(map(str,args)),capture_output=True,timeout=90,**kw)
 print('$',repr(args),'exit',p.returncode,repr(p.stdout),repr(p.stderr),flush=True);return p
def git(*args):
 p=run('git',*args);assert p.returncode==0,('fixture git',p);return p.stdout.decode().strip()
def put(path,raw,mode=0o644):
 p=Path(path);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw.encode() if isinstance(raw,str) else raw);p.chmod(mode)
def files(folder):
 return {str(p.relative_to(folder)):(stat.S_IMODE(p.stat().st_mode),p.read_bytes()) for p in folder.rglob('*') if p.is_file()}
def commit(message):git('add','-A');git('commit','-qm',message)
def fixture(name,raw,local=False,install=True):
 global init_result,hook_calls
 root=cw/'repo148';root.mkdir();os.chdir(root);git('init','-q','-b','main');git('config','user.name','Fixture148');git('config','user.email','fixture@example.invalid');git('config','gc.auto','0');git('config','maintenance.auto','false')
 tools=cw/'tools148';tools.mkdir();hook_calls=tools/'calls'
 put(tools/'lefthook','#!/bin/sh\nprintf "%s\\n" "$*" >> '+str(hook_calls)+'\nexit 0\n',0o755)
 os.environ['PATH']=str(tools)+os.pathsep+os.environ['PATH']
 for event in ('pre-commit','commit-msg','post-commit'):put('.git/hooks/'+event,HOOK.replace('run "pre-commit"','run "'+event+'"'),0o755)
 put(name,raw);put('AGENTS.md',b'# Rules\n\n- Keep it small.\n');put('run.sh',b'echo ok\n');put('tests/base.sh',b'exit 0\n')
 call=binary
 if local:
  target=root/'node_modules/shipcraft-fixture/bin/shipcraft';target.parent.mkdir(parents=True);shutil.copy2(binary,target);link=root/'node_modules/.bin/shipcraft';link.parent.mkdir();link.symlink_to('../shipcraft-fixture/bin/shipcraft');put('.gitignore','node_modules/\n');call=str(target)
 commit('base148');base=subprocess.check_output(['git','show','HEAD:'+name])
 if install:
  init_result=run(call,'init','--lang','other','--command','sh run.sh {junit}','--glob','tests/*.sh');assert init_result.returncode==0,('fixture init',init_result)
  commit('install148')
 return root,call,base
def observer(target):
 real=shutil.which('git');tools=cw/'observer148';tools.mkdir()
 put(tools/'git','#!'+sys.executable+'\nimport os,sys\na=sys.argv[1:]\nif "ls-files" in a:\n with open('+repr(target)+',"ab") as f:f.write(b"# concurrent148\\n")\nos.execv('+repr(real)+',['+repr(real)+',*a])\n',0o755)
 return dict(os.environ,PATH=str(tools)+os.pathsep+os.environ['PATH'])
def removed(name):return 'shipcraft: removed the shipcraft commands from '+name
def launchers(name):return "shipcraft: lefthook's commit-msg and post-commit launchers stay in the hooks folder (lefthook install wrote them); they run only what "+name+' still has under those hooks'
def left_line(name):return 'shipcraft: left '+name+': it mentions shipcraft outside the commands init adds; remove it by hand'
def config_left(name):return 'shipcraft: left .shipcraft.toml: a hook that calls shipcraft is left ('+name+'): remove that call first, then run shipcraft uninstall again; remove it by hand'
if case=='precommit-only':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n',local=False)
 old=Path('lefthook.yml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('lefthook.yml').is_file() and Path('lefthook.yml').read_bytes()==base,'lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('lefthook.yml')+'\n'+launchers('lefthook.yml')+'\n' in out,out
 assert out.index(removed('lefthook.yml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='empty-file':
 root,call,base=fixture('.lefthook.yml',b'',local=False)
 old=Path('.lefthook.yml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('.lefthook.yml').is_file() and Path('.lefthook.yml').read_bytes()==base,'lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('.lefthook.yml')+'\n'+launchers('.lefthook.yml')+'\n' in out,out
 assert out.index(removed('.lefthook.yml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='blocks-exist':
 root,call,base=fixture('lefthook.yaml',b'commit-msg:\n  commands:\n    lint:\n      run: echo msg\npost-commit:\n',local=False)
 old=Path('lefthook.yaml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('lefthook.yaml').is_file() and Path('lefthook.yaml').read_bytes()==b'commit-msg:\n  commands:\n    lint:\n      run: echo msg\n','lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('lefthook.yaml')+'\n'+launchers('lefthook.yaml')+'\n' in out,out
 assert out.index(removed('lefthook.yaml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='fourth-name':
 root,call,base=fixture('.lefthook.yaml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n',local=False)
 old=Path('.lefthook.yaml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('.lefthook.yaml').is_file() and Path('.lefthook.yaml').read_bytes()==base,'lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('.lefthook.yaml')+'\n'+launchers('.lefthook.yaml')+'\n' in out,out
 assert out.index(removed('.lefthook.yaml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='commands-only':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\ncommit-msg:\n',local=False)
 old=Path('lefthook.yml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('lefthook.yml').is_file() and Path('lefthook.yml').read_bytes()==b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n','lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('lefthook.yml')+'\n'+launchers('lefthook.yml')+'\n' in out,out
 assert out.index(removed('lefthook.yml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='crlf':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n'.replace(b'\n',b'\r\n'),local=False)
 old=Path('lefthook.yml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('lefthook.yml').is_file() and Path('lefthook.yml').read_bytes()==base,'lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('lefthook.yml')+'\n'+launchers('lefthook.yml')+'\n' in out,out
 assert out.index(removed('lefthook.yml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='indent-four':
 root,call,base=fixture('lefthook.yml',b'commit-msg:\n    commands:\n        lint:\n            run: echo msg\n',local=False)
 old=Path('lefthook.yml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('lefthook.yml').is_file() and Path('lefthook.yml').read_bytes()==base,'lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('lefthook.yml')+'\n'+launchers('lefthook.yml')+'\n' in out,out
 assert out.index(removed('lefthook.yml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='comments':
 root,call,base=fixture('lefthook.yml',b'# project148\npre-commit:\n  commands:\n    lint:\n      run: echo lint # preserve148\noutput: false\n',local=False)
 old=Path('lefthook.yml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('lefthook.yml').is_file() and Path('lefthook.yml').read_bytes()==base,'lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('lefthook.yml')+'\n'+launchers('lefthook.yml')+'\n' in out,out
 assert out.index(removed('lefthook.yml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='project-local':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n',local=True)
 old=Path('lefthook.yml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('lefthook.yml').is_file() and Path('lefthook.yml').read_bytes()==base,'lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('lefthook.yml')+'\n'+launchers('lefthook.yml')+'\n' in out,out
 assert out.index(removed('lefthook.yml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='no-final-newline':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n'.rstrip(b'\n'),local=False)
 old=Path('lefthook.yml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('lefthook.yml').is_file() and Path('lefthook.yml').read_bytes()==base+b'\n','lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('lefthook.yml')+'\n'+launchers('lefthook.yml')+'\n' in out,out
 assert out.index(removed('lefthook.yml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='null-block':
 root,call,base=fixture('lefthook.yml',b'commit-msg: null\npost-commit: ~\n',local=False)
 old=Path('lefthook.yml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('lefthook.yml').is_file() and Path('lefthook.yml').read_bytes()==b'','lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('lefthook.yml')+'\n'+launchers('lefthook.yml')+'\n' in out,out
 assert out.index(removed('lefthook.yml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='null-commands':
 root,call,base=fixture('lefthook.yml',b'commit-msg:\n  commands: null\npost-commit:\n  commands: ~\n',local=False)
 old=Path('lefthook.yml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('lefthook.yml').is_file() and Path('lefthook.yml').read_bytes()==b'','lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('lefthook.yml')+'\n'+launchers('lefthook.yml')+'\n' in out,out
 assert out.index(removed('lefthook.yml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='empty-post-key':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n'+b'post-commit:\n',local=False)
 old=Path('lefthook.yml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('lefthook.yml').is_file() and Path('lefthook.yml').read_bytes()==base,'lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('lefthook.yml')+'\n'+launchers('lefthook.yml')+'\n' in out,out
 assert out.index(removed('lefthook.yml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='bom':
 root,call,base=fixture('lefthook.yml',b'\xef\xbb\xbf'+b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n',local=False)
 old=Path('lefthook.yml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('lefthook.yml').is_file() and Path('lefthook.yml').read_bytes()==base,'lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('lefthook.yml')+'\n'+launchers('lefthook.yml')+'\n' in out,out
 assert out.index(removed('lefthook.yml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='mixed-forms':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n',local=False)
 path=Path('lefthook.yml');path.write_bytes(path.read_bytes().replace(b'run: shipcraft close',b'run: ./node_modules/.bin/shipcraft close'));commit('mixed148')
 old=path.read_bytes();config=Path('.shipcraft.toml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall');out=p.stdout.decode()
 assert p.returncode==0 and p.stderr==b'',p
 assert path.is_file() and path.read_bytes()==old,'mixed pair must be left whole'
 assert Path('.shipcraft.toml').read_bytes()==config,'mixed pair must keep config'
 assert left_line('lefthook.yml')+'\n' in out,out
 assert config_left('lefthook.yml')+'\n' in out,out
 assert removed('lefthook.yml') not in out and launchers('lefthook.yml') not in out,out
 assert not Path('.shipcraft').exists() and files(Path('.git/hooks'))==hooks
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
 p=run(call,'uninstall');assert p.returncode==0 and p.stderr==b'' and p.stdout.decode()==left_line('lefthook.yml')+'\n'+config_left('lefthook.yml')+'\nshipcraft: nothing to remove\n',p
 assert path.read_bytes()==old and Path('.shipcraft.toml').read_bytes()==config
elif case=='trailing-fragment':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n',local=False)
 p=Path('lefthook.yml');p.write_bytes(p.read_bytes()+b'# tail148');commit('fragment148')
 old=Path('lefthook.yml').read_bytes();hooks=files(Path('.git/hooks'));p=run(call,'uninstall')
 assert p.returncode==0 and p.stderr==b'',p
 assert Path('lefthook.yml').is_file() and Path('lefthook.yml').read_bytes()==base+b'commit-msg:\npost-commit:\n# tail148','lefthook bytes not restored'
 assert not Path('.shipcraft.toml').exists() and not Path('.shipcraft').exists(),'config/briefs/locks remain'
 assert files(Path('.git/hooks'))==hooks,'launchers changed'
 out=p.stdout.decode();assert removed('lefthook.yml')+'\n'+launchers('lefthook.yml')+'\n' in out,out
 assert out.index(removed('lefthook.yml'))<out.index('shipcraft: removed .shipcraft/briefs/red.md')<out.index('shipcraft: removed .shipcraft.toml'),out
 assert not Path('.git/shipcraft/runs.jsonl').exists(),'fake lefthook must not dispatch Shipcraft'
elif case=='edited-run':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 p=Path('lefthook.yml');p.write_bytes(p.read_bytes().replace(b'shipcraft check --commit-msg',b'shipcraft check --commit-msg {1}'))
 
 raw=p.read_bytes();config=Path('.shipcraft.toml').read_bytes();hooks=files(Path('.git/hooks'));r=run(call,'uninstall');out=r.stdout.decode()
 assert r.returncode==0 and r.stderr==b'',r
 assert p.read_bytes()==raw and Path('.shipcraft.toml').read_bytes()==config,'left file/config changed'
 assert left_line('lefthook.yml')+'\n' in out,out
 assert 'a hook that calls shipcraft is left (lefthook.yml)' in out,out
 assert not Path('.shipcraft').exists() and files(Path('.git/hooks'))==hooks
 r=run(call,'uninstall');assert r.returncode==0 and r.stdout.decode()==left_line('lefthook.yml')+'\n'+config_left('lefthook.yml')+'\nshipcraft: nothing to remove\n',r
elif case=='extra-skip':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 p=Path('lefthook.yml');p.write_bytes(p.read_bytes().replace(b'run: shipcraft close',b'run: shipcraft close\n      skip: true'))
 
 raw=p.read_bytes();config=Path('.shipcraft.toml').read_bytes();hooks=files(Path('.git/hooks'));r=run(call,'uninstall');out=r.stdout.decode()
 assert r.returncode==0 and r.stderr==b'',r
 assert p.read_bytes()==raw and Path('.shipcraft.toml').read_bytes()==config,'left file/config changed'
 assert left_line('lefthook.yml')+'\n' in out,out
 assert 'a hook that calls shipcraft is left (lefthook.yml)' in out,out
 assert not Path('.shipcraft').exists() and files(Path('.git/hooks'))==hooks
 r=run(call,'uninstall');assert r.returncode==0 and r.stdout.decode()==left_line('lefthook.yml')+'\n'+config_left('lefthook.yml')+'\nshipcraft: nothing to remove\n',r
elif case=='one-edited':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 p=Path('lefthook.yml');p.write_bytes(p.read_bytes().replace(b'run: shipcraft close',b'run: shipcraft close --custom'))
 
 raw=p.read_bytes();config=Path('.shipcraft.toml').read_bytes();hooks=files(Path('.git/hooks'));r=run(call,'uninstall');out=r.stdout.decode()
 assert r.returncode==0 and r.stderr==b'',r
 assert p.read_bytes()==raw and Path('.shipcraft.toml').read_bytes()==config,'left file/config changed'
 assert left_line('lefthook.yml')+'\n' in out,out
 assert 'a hook that calls shipcraft is left (lefthook.yml)' in out,out
 assert not Path('.shipcraft').exists() and files(Path('.git/hooks'))==hooks
 r=run(call,'uninstall');assert r.returncode==0 and r.stdout.decode()==left_line('lefthook.yml')+'\n'+config_left('lefthook.yml')+'\nshipcraft: nothing to remove\n',r
elif case=='comment-shipcraft':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 p=Path('lefthook.yml');p.write_bytes(p.read_bytes()+b'# shipcraft belongs to project148\n')
 
 raw=p.read_bytes();config=Path('.shipcraft.toml').read_bytes();hooks=files(Path('.git/hooks'));r=run(call,'uninstall');out=r.stdout.decode()
 assert r.returncode==0 and r.stderr==b'',r
 assert p.read_bytes()==raw and Path('.shipcraft.toml').read_bytes()==config,'left file/config changed'
 assert left_line('lefthook.yml')+'\n' in out,out
 assert 'a hook that calls shipcraft is left (lefthook.yml)' in out,out
 assert not Path('.shipcraft').exists() and files(Path('.git/hooks'))==hooks
 r=run(call,'uninstall');assert r.returncode==0 and r.stdout.decode()==left_line('lefthook.yml')+'\n'+config_left('lefthook.yml')+'\nshipcraft: nothing to remove\n',r
elif case=='project-shipcraft':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 p=Path('lefthook.yml');p.write_bytes(p.read_bytes().replace(b'echo lint',b'echo shipcraft'))
 
 raw=p.read_bytes();config=Path('.shipcraft.toml').read_bytes();hooks=files(Path('.git/hooks'));r=run(call,'uninstall');out=r.stdout.decode()
 assert r.returncode==0 and r.stderr==b'',r
 assert p.read_bytes()==raw and Path('.shipcraft.toml').read_bytes()==config,'left file/config changed'
 assert left_line('lefthook.yml')+'\n' in out,out
 assert 'a hook that calls shipcraft is left (lefthook.yml)' in out,out
 assert not Path('.shipcraft').exists() and files(Path('.git/hooks'))==hooks
 r=run(call,'uninstall');assert r.returncode==0 and r.stdout.decode()==left_line('lefthook.yml')+'\n'+config_left('lefthook.yml')+'\nshipcraft: nothing to remove\n',r
elif case=='invalid-utf8':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 p=Path('lefthook.yml');p.write_bytes(p.read_bytes()+b'# \xff shipcraft\n')
 
 raw=p.read_bytes();config=Path('.shipcraft.toml').read_bytes();hooks=files(Path('.git/hooks'));r=run(call,'uninstall');out=r.stdout.decode()
 assert r.returncode==0 and r.stderr==b'',r
 assert p.read_bytes()==raw and Path('.shipcraft.toml').read_bytes()==config,'left file/config changed'
 assert left_line('lefthook.yml')+'\n' in out,out
 assert 'a hook that calls shipcraft is left (lefthook.yml)' in out,out
 assert not Path('.shipcraft').exists() and files(Path('.git/hooks'))==hooks
 r=run(call,'uninstall');assert r.returncode==0 and r.stdout.decode()==left_line('lefthook.yml')+'\n'+config_left('lefthook.yml')+'\nshipcraft: nothing to remove\n',r
elif case=='duplicate-key':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 p=Path('lefthook.yml');p.write_bytes(p.read_bytes().replace(b'    shipcraft:\n',b'    shipcraft:\n      run: echo project148\n    shipcraft:\n',1))
 
 raw=p.read_bytes();config=Path('.shipcraft.toml').read_bytes();hooks=files(Path('.git/hooks'));r=run(call,'uninstall');out=r.stdout.decode()
 assert r.returncode==0 and r.stderr==b'',r
 assert p.read_bytes()==raw and Path('.shipcraft.toml').read_bytes()==config,'left file/config changed'
 assert left_line('lefthook.yml')+'\n' in out,out
 assert 'a hook that calls shipcraft is left (lefthook.yml)' in out,out
 assert not Path('.shipcraft').exists() and files(Path('.git/hooks'))==hooks
 r=run(call,'uninstall');assert r.returncode==0 and r.stdout.decode()==left_line('lefthook.yml')+'\n'+config_left('lefthook.yml')+'\nshipcraft: nothing to remove\n',r
elif case=='two-files':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 raw=Path('lefthook.yml').read_bytes();put('.lefthook.yaml',raw.replace(b'shipcraft close',b'shipcraft close --edited'))
 r=run(call,'uninstall');out=r.stdout.decode()
 assert r.returncode==0 and Path('lefthook.yml').read_bytes()==base,'first file not independently restored'
 assert Path('.lefthook.yaml').read_bytes()==raw.replace(b'shipcraft close',b'shipcraft close --edited')
 assert removed('lefthook.yml') in out and left_line('.lefthook.yaml') in out and out.index(removed('lefthook.yml'))<out.index(left_line('.lefthook.yaml')),out
 assert Path('.shipcraft.toml').exists() and 'a hook that calls shipcraft is left (.lefthook.yaml)' in out,out
elif case=='copies-mode':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 p=Path('lefthook.yml');p.chmod(0o751);old=p.read_bytes();r=run(call,'uninstall');out=r.stdout.decode()
 assert r.returncode==0 and p.read_bytes()==base,'file not rewritten'
 folder=Path(out.splitlines()[0].split(' to ',1)[1]);copy=folder/'lefthook.yml'
 assert copy.read_bytes()==old and stat.S_IMODE(copy.stat().st_mode)==0o751
 assert stat.S_IMODE(p.stat().st_mode)==0o751
elif case=='tracked-paths':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 head=git('rev-parse','HEAD');index=Path('.git/index').read_bytes();r=run(call,'uninstall');out=r.stdout.decode()
 line=next(x for x in out.splitlines() if 'commit the removal:' in x)
 assert line.endswith(' -- AGENTS.md CLAUDE.md lefthook.yml .shipcraft/briefs/red.md .shipcraft/briefs/green.md .shipcraft/locks/.gitkeep .shipcraft.toml'),line
 assert git('rev-parse','HEAD')==head and Path('.git/index').read_bytes()==index
elif case=='untracked-path':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 git('rm','--cached','lefthook.yml');r=run(call,'uninstall');out=r.stdout.decode()
 assert r.returncode==0 and Path('lefthook.yml').read_bytes()==base,'untracked file not restored'
 assert 'lefthook.yml' not in next(x for x in out.splitlines() if 'commit the removal:' in x)
elif case=='dry-run':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 before=files(root);r=run(call,'uninstall','--dry-run');out=r.stdout.decode()
 assert r.returncode==0 and files(root)==before,'dry run wrote files/index/hooks'
 assert 'shipcraft: would remove the shipcraft commands from lefthook.yml\n'+launchers('lefthook.yml')+'\n' in out,out
 assert out.endswith('shipcraft: dry run: nothing was changed\n') and not Path('.git/shipcraft/uninstalled').exists()
elif case=='second-run':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 r=run(call,'uninstall');before=files(root);r=run(call,'uninstall')
 assert r.returncode==0 and r.stdout==b'shipcraft: nothing to remove\n' and r.stderr==b'',r
 assert files(root)==before
elif case=='changed-since-plan':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 raw=Path('lefthook.yml').read_bytes();env=observer('lefthook.yml');r=run(call,'uninstall',env=env)
 assert r.returncode==2 and r.stderr==b'shipcraft: error: lefthook.yml changed since uninstall read it; nothing more was changed: run shipcraft uninstall again\n',r
 assert Path('lefthook.yml').read_bytes()==raw+b'# concurrent148\n' and Path('.shipcraft.toml').exists()
 assert not any(p.name=='lefthook.yml' for p in Path('.git/shipcraft/uninstalled').rglob('*'))
elif case=='later-failure':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 raw=Path('lefthook.yml').read_bytes();brief=Path('.shipcraft/briefs/red.md').read_bytes();env=observer('.shipcraft/briefs/red.md');r=run(call,'uninstall',env=env)
 assert r.returncode==2 and b'red.md changed since uninstall read it' in r.stderr,r
 assert Path('lefthook.yml').read_bytes()==base,'earlier rewrite not kept on later failure'
 folder=Path(r.stdout.decode().splitlines()[0].split(' to ',1)[1]);assert (folder/'lefthook.yml').read_bytes()==raw
 assert Path('.shipcraft/briefs/red.md').read_bytes()==brief+b'# concurrent148\n' and Path('.shipcraft.toml').exists()
elif case=='readme':
 text=(acceptance.parent/'README.md').read_text();section=text.split('### Removing Shipcraft\n\n',1)[1].split('\nUpgrading:',1)[0]
 assert section.count('its commands in the lefthook file (the file itself stays).')==1
 assert section.count('By hand, for what `uninstall` leaves (anything edited by hand):')==1
 assert section.count('with husky, the `shipcraft` lines in `.husky/commit-msg` and `.husky/post-commit`; with lefthook, the `shipcraft` command (its `shipcraft:` key and `run:` line) under `commit-msg` and under `post-commit`;')==1
elif case=='spec-row':
 text=(acceptance.parent/'docs/spec.md').read_text();row=next(l for l in text.splitlines() if l.startswith('| `uninstall [--dry-run]`'))
 assert 'its plain git hooks, its lines in husky and pre-commit files and its commands in a lefthook file (item 148)' in row,row
 version=run(binary,'--version');assert version.returncode==0 and version.stdout.decode().split()[1]==re.search(r'This contract is \*\*(\d+\.\d+\.\d+)\*\*',text)[1],version
elif case=='control-init':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 assert Path('lefthook.yml').read_bytes()==base+b'commit-msg:\n  commands:\n    shipcraft:\n      run: shipcraft check --commit-msg\npost-commit:\n  commands:\n    shipcraft:\n      run: shipcraft close\n'
 assert b'added shipcraft commands to lefthook.yml (shipcraft check --commit-msg in commit-msg, shipcraft close in post-commit)' in init_result.stdout,init_result
 assert Path(hook_calls).read_text().count('run commit-msg')==2 and Path(hook_calls).read_text().count('run post-commit')==2
 before=files(root);r=run(call,'init','--lang','other','--command','sh run.sh {junit}','--glob','tests/*.sh');assert r.returncode==0 and b'already has shipcraft commands' in r.stdout and files(root)==before,r
elif case=='control-status':
 root,call,base=fixture('lefthook.yml',b'pre-commit:\n  commands:\n    lint:\n      run: echo lint\n')
 before=files(root);r=run(call,'status');assert r.returncode==0 and b'hook through lefthook (commit-msg)' in r.stdout.lower(),r
 assert files(root)==before
elif case=='control-refusal':
 root,call,base=fixture('lefthook.yml',b'extends: base.yml\n',install=False)
 before=files(root);r=run(call,'init','--lang','other','--command','sh run.sh {junit}','--glob','tests/*.sh');lines=r.stderr.decode().splitlines()
 assert r.returncode==1 and len(lines)==3 and lines[0]=='shipcraft refused: lefthook.yml uses `extends`' and 'uses `extends`' in lines[2],r
 assert lines[0].startswith('shipcraft refused:') and lines[1].startswith('Why:') and lines[2].startswith('Next:') and files(root)==before
elif case=='control-other-sources':
 root,call,base=fixture('lefthook.yml',b'# project148\n')
 put('lefthook.yml',base);put('lefthook-local.yml',b'# shipcraft local148\n');put('lefthook.toml',b'# shipcraft toml148\n');r=run(call,'uninstall');out=r.stdout.decode()
 assert r.returncode==0 and 'lefthook' not in out and not Path('.shipcraft.toml').exists(),r
 assert Path('lefthook.yml').read_bytes()==base and Path('lefthook-local.yml').read_bytes()==b'# shipcraft local148\n' and Path('lefthook.toml').read_bytes()==b'# shipcraft toml148\n'
elif case=='control-observer':
 root,call,base=fixture('lefthook.yml',b'# project148\n')
 put('lefthook.yml',base);put('project.txt',b'project148\n');env=observer('project.txt');r=run(call,'uninstall',env=env)
 assert r.returncode==0 and Path('project.txt').read_bytes()==b'project148\n# concurrent148\n' and Path('lefthook.yml').read_bytes()==base,r
 assert not Path('.shipcraft.toml').exists()
else:raise AssertionError('unrouted case '+case)
PY148
 pass
}
