# Item 57: real suites using git, through real commit hooks.
item57_langs() { echo python node; }
item57_cases() { for c in main linked env-direct env-copy only log-fails; do echo "v1-57.$c"; done; }
item57_case() {
  local c=${CASE#v1-57.} original testfile
  EXPECT="clean suite git environment; accepted GREEN closes"
  v1_start; setup_init
  original=$T
  git config core.bare false
  # The probe is protected as part of the test itself, not a fake runner/report.
  if [ "$LP" = python ]; then testfile=tests/test_git57.py
  else testfile=src/git57.test.ts; fi
  "$PY" - "$CW" "$PY" "$testfile" "$LP" <<'PY57' || fail 'fixture test/config generation'
import json,sys
from pathlib import Path
cw,python,test,lang=sys.argv[1:]
probe=r'''
import json, os, subprocess, tempfile
from pathlib import Path
assert Path('green57').exists(), 'RED: green57 missing'
out=Path(CW)
out.joinpath('env57.json').write_text(json.dumps(dict(os.environ)))
def git(*args, cwd=None):
    p=subprocess.run(['git',*args],cwd=cwd,text=True,capture_output=True)
    out.joinpath('git57.log').open('a').write(repr(args)+'\n'+p.stdout+p.stderr)
    assert p.returncode==0, p.stderr
    return p.stdout.strip()
root=git('rev-parse','--show-toplevel')
files=git('ls-files').splitlines()
out.joinpath('project57.json').write_text(json.dumps(dict(root=root,cwd=str(Path.cwd()),files=files)))
assert Path(root).resolve()==Path.cwd().resolve(), (root,Path.cwd())
assert 'ordinary57' not in files, 'suite saw ordinary index, not commit index'
with tempfile.TemporaryDirectory(prefix='inside git57 ',dir='.') as inside:
    upward_root=git('rev-parse','--show-toplevel',cwd=inside)
with tempfile.TemporaryDirectory(prefix='own git57 ',dir=CW) as tmp:
    git('init','-q',tmp)
    out.joinpath('init57').write_text(str(Path(tmp,'.git').exists()))
    assert Path(tmp,'.git').is_dir(), 'git init reinitialized project instead of temporary repo'
    Path(tmp,'own.txt').write_text('own repository\n')
    git('add','own.txt',cwd=tmp)
    git('-c','user.name=Item57','-c','user.email=item57@example.invalid','commit','-qm','own commit',cwd=tmp)
    assert Path(git('rev-parse','--show-toplevel',cwd=tmp)).resolve()==Path(tmp).resolve()
    assert git('ls-files',cwd=tmp)=='own.txt'
assert Path(upward_root).resolve()==Path.cwd().resolve(), 'upward discovery must find project before init'
out.joinpath('own57').write_text('committed')
'''.replace('CW',repr(cw))
if lang=='python':
    Path(test).write_text('def test_git57():\n    exec('+repr(probe)+', {})\n')
else:
    Path(test).write_text('import {it} from "vitest";\n// @ts-ignore: node types are not installed in battery target\nimport {execFileSync} from "node:child_process";\nit("git57",()=>{execFileSync('+json.dumps(python)+',["-c",'+json.dumps(probe)+'], {stdio:"inherit"});});\n')
# Capture the shell/wrapper environment too, before its child runner starts.
p=Path('.shipcraft.toml')
lines=[]
for line in p.read_text().splitlines():
    if line.startswith(('command = ', 'test_command = ')):
        import tomli as tomllib
        key=line.split('=',1)[0].strip()
        command=tomllib.loads(line)[key]
        import shlex
        command='if [ "$FOO" = item57 ]; then env > '+shlex.quote(cw+'/shell57')+'; fi; '+command
        line=key+' = '+json.dumps(command)
    lines.append(line)
p.write_text('\n'.join(lines)+'\n')
PY57
  must_accept 'open RED with real failing git test' cmd shipcraft red
  must_accept 'commit open RED' commit commit_all 'test: RED git57'
  chk 'open lock before GREEN' one_lock_head_state open
  if [ "$c" = linked ]; then
    git worktree add -qb linked57 "$CW/linked57" || fail 'fixture linked worktree'
    cd "$CW/linked57" || fail 'fixture cd linked'
    # Base .gitignore uses directory-only patterns; symlinks need local excludes.
    printf '\n.venv\nnode_modules\n' >> "$(git rev-parse --git-path info/exclude)"
    if [ "$LP" = python ]; then ln -s "$original/.venv" .venv; else ln -s "$original/node_modules" node_modules; fi
  fi
  printf 'green\n' > green57
  git add green57
  case "$c" in
    env-copy) printf 'outside\n' > outside57 ;;
    only) printf 'ordinary index only\n' > ordinary57; git add ordinary57 ;;
    log-fails) rm -f .git/shipcraft/runs.jsonl; mkdir .git/shipcraft/runs.jsonl ;;
  esac
  if [ "$c" != env-copy ]; then
    chk 'fixture has no unstaged tracked changes' git diff --exit-code
    chk 'fixture has no untracked nonignored paths' eq "$(git ls-files --others --exclude-standard)" ''
  fi
  export FOO=item57 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=item57.probe GIT_CONFIG_VALUE_0=preserved57
  export GIT_DIR="$(git rev-parse --absolute-git-dir)"
  case "$c" in env-*) export GIT_WORK_TREE="$(pwd)" GIT_INDEX_FILE="$GIT_DIR/index" ;; esac
  if [ "$c" = only ]; then run_cmd git commit --only -qm 'feat: GREEN git57' -- green57
  else run_cmd git commit -qm 'feat: GREEN git57'; fi
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  # Check repository health even when the hook refused: damage must be reported directly.
  chk 'project core.bare stays false after suite git init' eq "$(git config core.bare)" false
  chk 'project git status still works' git status --porcelain
  if [ "$c" = linked ]; then
    chk 'shared core.bare stays false' eq "$(git -C "$original" config core.bare)" false
    chk 'original worktree still works' git -C "$original" status --porcelain
  fi
  chk 'GREEN accepted' rc_zero
  chk 'lock closed' one_lock_head_state closed
  chk 'suite initialized and committed in its own repository' eq "$(cat "$CW/own57" 2>/dev/null)" committed
  chk 'suite and starting shell receive exactly cleaned environment' "$PY" - "$CW" "$c" "$(pwd)" <<'PY57'
import json,sys
from pathlib import Path
cw,mode,project=sys.argv[1:]; p=Path(cw)
env=json.loads((p/'env57.json').read_text())
shell=dict(line.split('=',1) for line in (p/'shell57').read_text().splitlines() if '=' in line)
for source in (env,shell):
    for key in ('GIT_DIR','GIT_INDEX_FILE','GIT_WORK_TREE'):
        assert key not in source,(key,source.get(key))
    for key,value in dict(FOO='item57',GIT_CONFIG_COUNT='1',GIT_CONFIG_KEY_0='item57.probe',GIT_CONFIG_VALUE_0='preserved57').items():
        assert source.get(key)==value,(key,source.get(key))
data=json.loads((p/'project57.json').read_text())
assert 'green57' in data['files'] and 'ordinary57' not in data['files'],data
if mode in ('only','env-copy'):
    assert Path(data['root']).resolve()!=Path(project).resolve(), 'suite must run on copy'
else:
    assert Path(data['root']).resolve()==Path(project).resolve(), 'fixture must exercise direct path'
assert (p/'init57').read_text()=='True'
PY57
  if [ "$c" = only ]; then
    chk 'ordinary staged entry remains outside commit' sh -c 'git ls-files --error-unmatch ordinary57 && ! git cat-file -e HEAD:ordinary57'
  fi
  pass
}
