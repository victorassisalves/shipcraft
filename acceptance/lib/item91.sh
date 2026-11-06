# Item 91: public init; no implementation reader or real external service.
item91_langs() { echo core; }
item91_cases() {
  local c
  for c in no-runner absent invalid invalid-utf8 manifest-directory dangling symlink-none workspace parent-only installed-only agents-fail briefs-fail github-fail vitest-dep vitest-dev jest-dep jest-dev vitest-null jest-false symlink-runner detect kept kept-link kept-invalid foreign core-fail python go other installed-control; do echo "v1-91.$c"; done
}
item91_case() {
  EXPECT="item 91: ${CASE#v1-91.}"
  v1_start codex claude
  export ST
  must_accept 'item 91 assumption contract' cmd "$PY" - "${CASE#v1-91.}" "$(command -v shipcraft)" "$CW" "$ACEITE/../nucleo/Cargo.toml" <<'PY91'
import json,os,shlex,subprocess,sys
from pathlib import Path
try: import tomllib
except ImportError: import tomli as tomllib
case,binary,cw,manifest=sys.argv[1:]; binary=str(Path(binary).resolve());cw=Path(cw)
version=tomllib.loads(Path(manifest).read_text())['package']['version']
def write(name,data,mode=None):
 p=Path(name);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data if isinstance(data,bytes) else data.encode())
 if mode is not None:p.chmod(mode)
def run(*args):
 p=subprocess.run(list(map(str,args)),input=b'',capture_output=True,timeout=60)
 print('$',repr(args),'rc=',p.returncode,'stdout=',repr(p.stdout),'stderr=',repr(p.stderr),flush=True)
 return p
def ok(*args):
 p=run(*args);assert p.returncode==0,('fixture command failed',p.stdout,p.stderr);return p
root=cw/"project91 space 'quote";root.mkdir();os.chdir(root)
ok('git','init','-q','-b','main')
write('README.md','fixture91\n');write('package.json','{"scripts":{"test":"node --test"}}\n')
write('.git/shipcraft/sentinel91',b'keep91\r\n\x00')
args=['--lang','node'];warning=False;rc=0;runner='vitest';kept=None
if case=='no-runner':
 warning=True
elif case=='absent':
 Path('package.json').unlink();warning=True
elif case=='invalid':
 write('package.json','{"devDependencies":{"vitest":"*"}, broken');warning=True
elif case=='invalid-utf8':
 write('package.json',b'{\xff}');warning=True
elif case=='manifest-directory':
 Path('package.json').unlink();Path('package.json').mkdir();warning=True
elif case=='dangling':
 Path('package.json').unlink();Path('package.json').symlink_to('missing91');warning=True
elif case=='symlink-none':
 Path('package.json').rename('manifest91');Path('package.json').symlink_to('manifest91');warning=True
elif case=='workspace':
 write('package.json','{"workspaces":["packages/*"]}');write('packages/api/package.json','{"devDependencies":{"jest":"*"}}');ok('git','add','package.json','packages');warning=True
elif case=='parent-only':
 write(root.parent/'package.json','{"devDependencies":{"vitest":"*"}}');warning=True
elif case=='installed-only':
 write('node_modules/vitest/package.json','{"name":"vitest"}');warning=True
elif case=='agents-fail':
 write('outside-agents91','keep agents91');Path('AGENTS.md').symlink_to('outside-agents91');warning=True
elif case=='briefs-fail':
 write('.shipcraft/briefs','blocked briefs91');warning=True
elif case=='github-fail':
 ok('git','add','README.md');ok('git','commit','-qm','fixture91');origin=cw/'origin91.git';ok('git','init','-q','--bare',origin);ok('git','remote','add','origin',origin);ok('git','push','-q','origin','main');ok('git','fetch','-q','origin');ok('git','remote','set-head','origin','main');write(Path(os.environ['ST'])/'origin',str(origin)+'\n');write(Path(os.environ['ST'])/'protection','403\n');args+=['--github'];warning=True
elif case=='vitest-dep':
 write('package.json',json.dumps({'dependencies':{'vitest':'*'}}))
elif case=='vitest-dev':
 write('package.json',json.dumps({'devDependencies':{'vitest':'*'}}))
elif case=='jest-dep':
 write('package.json',json.dumps({'dependencies':{'jest':'*'}}));runner='jest'
elif case=='jest-dev':
 write('package.json',json.dumps({'devDependencies':{'jest':'*'}}));runner='jest'
elif case=='vitest-null':
 write('package.json',json.dumps({'dependencies':{'vitest':None}}))
elif case=='jest-false':
 write('package.json',json.dumps({'devDependencies':{'jest':False}}));runner='jest'
elif case=='symlink-runner':
 write('manifest91','{"dependencies":{"jest":null}}');Path('package.json').unlink();Path('package.json').symlink_to('manifest91');runner='jest'
elif case=='detect':
 write('package.json','{"devDependencies":{"vitest":"*"}}');args=[]
elif case=='kept':
 kept=b'# kept91\r\nshipcraft_min = "0.0"\r\ntest_command = "false {junit}"\r\ntest_globs = ["custom/**"]\r\n';write('.shipcraft.toml',kept)
elif case=='kept-link':
 kept=b'# invalid target91\n';write('config-target91',kept);Path('.shipcraft.toml').symlink_to('config-target91');rc=1
elif case=='kept-invalid':
 kept=b'not TOML [91';write('.shipcraft.toml',kept);rc=1
elif case=='foreign':
 write('.git/hooks/commit-msg','#!/bin/sh\necho foreign91\n',0o755);rc=1
elif case=='core-fail':
 write('.shipcraft','blocked91');rc=2
elif case=='python':
 args=['--lang','python'];runner='pytest'
elif case=='go':
 args=['--lang','go'];runner='gotestsum'
elif case=='other':
 args=['--lang','other','--command','false {junit}','--glob','tests/**'];runner=None
elif case=='installed-control':
 write('package.json','{"devDependencies":{"jest":null}}');write('node_modules/vitest/package.json','{"name":"vitest"}');runner='jest'
else:raise AssertionError('unrouted case: '+case)
# Baits cover installed and global runners without running them; no tsconfig build signal.
for tool in ('vitest','jest','node','npm','npx','pnpm','yarn'):
 write(root/'node_modules/.bin'/tool,'#!/bin/sh\nprintf ran >> '+shlex.quote(str(cw/'tool-called91'))+'\nexit 79\n',0o755)
probe=cw/'global91';probe.mkdir()
for tool in ('vitest','jest','node','npm','npx','pnpm','yarn'):
 (probe/tool).symlink_to(root/'node_modules/.bin'/tool)
os.environ['PATH']=str(probe)+os.pathsep+os.environ['PATH']
p=run(binary,'init',*args);out=p.stdout.decode();err=p.stderr.decode();text=out+err
assert p.returncode==rc,('wrong exit',rc,text)
assert not (cw/'tool-called91').exists(),'assumption decision ran a tool'
assert Path('.git/shipcraft/sentinel91').read_bytes()==b'keep91\r\n\x00'
assert not Path('.git/shipcraft/runs.jsonl').exists(),'init wrote a run row'
if kept is not None:assert Path('.shipcraft.toml').read_bytes()==kept,'kept config bytes changed'
if rc:
 assert 'ready. Commit' not in text and 'assumes vitest' not in text,text
 if rc==1:
  lines=[l for l in text.splitlines() if l.strip()]
  assert len(lines)==3 and all(l.startswith(k) for l,k in zip(lines,('shipcraft refused:','Why:','Next:'))),lines
 if case=='foreign':assert 'commit-msg' in text and not Path('.shipcraft.toml').exists(),text
 if case=='core-fail':
  assert 'undid what this run created' in text and Path('.shipcraft').read_text()=='blocked91',text
  assert not any(Path(f).exists() for f in ('.shipcraft.toml','AGENTS.md','CLAUDE.md','.git/hooks/commit-msg','.git/hooks/post-commit'))
else:
 lines=out.splitlines();ready=[i for i,l in enumerate(lines) if l.startswith('shipcraft: ready. Commit ')]
 assert len(ready)==1 and ready[0]==len(lines)-3,lines
 assert lines[-1]=='CI runs on this machine through shipcraft pr. To run it on GitHub, see shipcraft docs/github-ci.md.',lines
 assert 'then write the failing test and stub' in lines[-2],lines
 assert Path('.shipcraft/locks/.gitkeep').read_bytes()==b''
 for hook in ('commit-msg','post-commit'):assert os.access('.git/hooks/'+hook,os.X_OK)
 if kept is None:
  cfg=tomllib.loads(Path('.shipcraft.toml').read_text())
  if runner:
   assert cfg['runner']==runner,cfg
   assert ('language '+(args[1] if args else 'node')+' (runner '+runner+')') in out,out
  else:
   assert cfg['test_command']=='false {junit}' and cfg['test_globs']==['tests/**'] and cfg['filter']=='command',cfg
   assert 'lang' not in cfg and 'runner' not in cfg and 'test command run as written' in out,out
  assert 'suite' not in cfg and 'build' not in cfg,cfg
 if case=='agents-fail':assert Path('AGENTS.md').is_symlink() and Path('outside-agents91').read_text()=='keep agents91' and 'AGENTS.md is not a regular file, kept' in text,text
 if case=='briefs-fail':assert Path('.shipcraft/briefs').read_text()=='blocked briefs91' and '.shipcraft/briefs not written' in text,text
 if case=='github-fail':assert 'no branch protection on its GitHub plan' in text,text
 if warning:
  # Frozen config text from public init on the spec baseline; only version varies.
  expected='# shipcraft: how the suite runs and where each layer runs. Changing this file with an\n# open lock is refused. In test_command (and command), {junit} becomes the\n# path where the runner writes its JUnit report. Optional check checks the\n# whole project before tests: it runs in shipcraft ci and RED, never in the hook.\nshipcraft_min = "{minimum}"\nlang = "node"\nrunner = "vitest"\ntest_command = "node_modules/.bin/vitest run --reporter=default --reporter=junit --outputFile.junit={junit}"\ntest_globs = ["**/*.test.*", "**/*.spec.*", "**/__tests__/**", "**/vitest.config.*", "**/jest.config.*"]\n\n# where each layer runs: "local" = on this machine, started by shipcraft pr; "github" = in this\n# project\'s GitHub Actions (docs/github-ci.md); "off" = it does not run and shipcraft merge does not\n# require it. shipcraft/ci re-checks every commit of the PR and runs the suite at its HEAD,\n# unless suite_checks names GitHub checks that run the suite (docs/github-ci.md).\n[execution]\nci = "local"\nreview = "local"\nci_timeout = 1800\n\n[roles]\n# the review agent: codex, claude or gemini\nreview = "codex"\n\n[review]\n# seconds; optional project spec included in the brief: spec = "docs/spec.md"\ntimeout = 1200\n'.replace('{minimum}', '.'.join(version.split('.')[:2]))
  assert Path('.shipcraft.toml').read_bytes()==expected.encode(),'assumption changed config bytes'
  warning_line="shipcraft: warning: found neither vitest nor jest in package.json, so the test command assumes vitest. Install it, or for another runner, from the repository root, remove .shipcraft.toml and run: shipcraft init --lang other --command '<test command writing JUnit to {junit}>' --glob '<test files>'"
  assert lines.count(warning_line)==1,('missing/duplicate exact assumption line',out)
  assert lines[ready[0]-1]==warning_line,'warning not immediately before ready'
  assert warning_line not in err,'warning sent to stderr'
 else:
  assert 'found neither vitest nor jest' not in text and 'assumes vitest' not in text,text
PY91
  pass
}
