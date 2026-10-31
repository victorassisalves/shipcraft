# Item 65: public RED commands, real language reports and a recording pytest adapter.
item65_langs() { echo python node go; }
item65_cases() {
  echo v1-65.main; echo v1-65.many
  [ "${l:-}" = python ] || return 0
  local c
  for c in helper-only helpers-only monorepo monorepo-clean monorepo-check monorepo-helper overlap overlap-shared overlap-uncovered skipped skipped-only no-report no-report-unmapped unmapped unmapped-helper environment environment-many redo redo-lock-only no-support no-support-many passing error second-run-fails second-run-passes log-fails; do echo "v1-65.$c"; done
}
item65_case() {
  local c=${CASE#v1-65.}
  EXPECT="item 65: $c"; v1_start
  if [ "$c" = main ] || [ "$c" = many ]; then
    setup_init
    local new old support
    case "$LP" in
      python) new=tests/test_fresh65.py; old=tests/test_legacy65.py; support=tests/conftest.py; i55_write "$old" legacy65 ;;
      node) new=src/fresh65.test.ts; old=src/legacy65.test.ts; support=src/setup65.ts; i55_write "$old" legacy65 ;;
      go)
        PATH="$GOBIN:$PATH"; export PATH
        new=fresh65_test.go; old=legacy65_test.go; support=helper65.go
        printf 'package textutil\nimport "testing"\nfunc TestLegacy65(t *testing.T) { t.Fatal("legacy") }\n' > "$old" ;;
    esac
    case "$LP" in python) printf '# helper\n' > "$support" ;; node) printf '// helper\n' > "$support" ;; go) printf 'package textutil\n' > "$support" ;; esac
    "$PY" - "$support" <<'PYCFG'
import json,sys
from pathlib import Path
p=Path('.shipcraft.toml'); p.write_text(p.read_text().replace('test_globs = [','test_globs = ['+json.dumps(sys.argv[1])+', ',1))
PYCFG
    i55_commit 'test: legacy and protected support65'; remote_setup; git checkout -qb feature/item65
    printf '\n' >> "$support"
    if [ "$LP" = go ]; then printf 'package textutil\nimport "testing"\nfunc TestFresh65(t *testing.T) { t.Fatal("fresh") }\n' > "$new"
    else i55_write "$new" fresh65; fi
    if [ "$c" = many ]; then
      "$PY" - "$support" <<'PYMORE'
import json,sys
from pathlib import Path
# Additional helpers share the configured support glob through explicit fixture config at base.
# Advance the base after adding globs, then change the existing helpers and add the test again.
p=Path('.shipcraft.toml'); s=p.read_text()
s=s.replace('test_globs = [','test_globs = ["**/helper65*", "helper65*", ',1); p.write_text(s)
PYMORE
      # Commit only configuration/support fixtures, keeping the test untracked.
      git add .shipcraft.toml "$support"
      git -c core.hooksPath="$CW/no-hooks" commit -qm 'chore: helper globs'
      git update-ref refs/remotes/origin/main HEAD
      local suffix dir
      dir=$(dirname "$support"); suffix=${support##*.}
      for n in z a café; do
        if [ "$LP" = go ]; then printf 'package textutil\n' > "$dir/helper65$n.$suffix"
        else cp "$support" "$dir/helper65$n.$suffix"; fi
      done
      printf '\n' >> "$support"
    fi
    run_cmd shipcraft red
    chk 'native narrow RED accepted' rc_zero
    chk 'native lock protects support, keeps fresh cases, exact notice and row' "$PY" - "$OUT" "$(lock_files_tree)" "$support" "$new" "$c" "$ACEITE/../nucleo/Cargo.toml" "$(command -v shipcraft)" <<'PYNATIVE'
import hashlib,json,re,subprocess,sys
from pathlib import Path
out,lock,support,new,mode,manifest,binary=sys.argv[1:]
d=json.loads(Path(lock).read_text()); text=Path(out).read_text(); paths=[support]
if mode=='many': paths+=list(str(p) for p in Path(support).parent.glob('helper65*') if str(p)!=support)
paths=sorted(set(paths),key=lambda x:x.encode())
assert all(p in d['files'] for p in paths),d
for f,h in d['files'].items(): assert h=='sha256:'+hashlib.sha256(Path(f).read_bytes()).hexdigest(),f
for key in ('cases','failing_at_red'):
 assert len(d[key])==1 and ('fresh65' in d[key][0] or 'Fresh65' in d[key][0]),(key,d[key])
lines=text.splitlines(); notice=f'shipcraft: red ran the changed test files: {len(paths)+1} of {len(d["files"])}'
assert lines.count(notice)==1,text
i=lines.index(notice); formatted=', '.join(paths[:3])+(' and '+str(len(paths)-3)+' more' if len(paths)>3 else '')
expected='shipcraft: red did not run the tests that may use the changed support file(s): '+formatted+'; CI runs them'
assert lines[i+1]==expected,(lines,expected)
assert text.count('shipcraft: red did not run')==1,text
r=[json.loads(x) for x in open('.git/shipcraft/runs.jsonl') if json.loads(x).get('layer')=='red']; assert len(r)==1,r
r=r[0]; assert (r.get('kind'),r.get('reported_at'),r.get('fixes_release'))==('feature',None,None),r
assert (r['selection'],r['selected_files'],r['fallback'])==('changed',len(paths)+1,None),r
assert set(r)=={'at','branch','code','commit','fallback','layer','lock','result','secs','selected_files','selection','rerun_dropped','kind','reported_at','fixes_release'},r
version=re.search(r'^version = "([^"]+)"',Path(manifest).read_text(),re.M)[1]
assert subprocess.check_output([binary,'--version'],text=True).strip().startswith('shipcraft '+version),version
PYNATIVE
    pass; return
  fi
  must_accept 'suite-local support selection contract' cmd "$PY" - "$c" "$(command -v shipcraft)" <<'PY65'
import hashlib,json,os,shlex,subprocess,sys
from pathlib import Path
mode,binary=sys.argv[1:]
Path('project65').mkdir(); os.chdir('project65')
errors=[]
def want(value,message):
 if not value: errors.append(message)
def write(path,text):
 p=Path(path); p.parent.mkdir(parents=True,exist_ok=True); p.write_text(text)
def run(*args,ok=True):
 p=subprocess.run(args,text=True,capture_output=True,timeout=90)
 print('$',shlex.join(args),'[rc='+str(p.returncode)+']\n'+p.stdout+p.stderr,flush=True)
 if ok: assert p.returncode==0,(args,p.stdout,p.stderr)
 return p
def git(*args): return run('git',*args).stdout.strip()
def commit(message): git('add','-A'); git('-c','core.hooksPath=/dev/null','commit','-qm',message)
def test(path,name,status='fail'):
 s='import pytest\n'
 if status=='skip': s+='@pytest.mark.skip(reason="coverage65")\n'
 s+='def test_'+name+'():\n    '+('raise RuntimeError("error65")' if status=='error' else 'assert '+str(status=='pass'))+'\n'
 write(path,s)
def rows(): return [json.loads(x) for x in Path('.git/shipcraft/runs.jsonl').read_text().splitlines() if json.loads(x).get('layer')=='red']
def locks(): return sorted(Path('.shipcraft/locks').glob('*.json'))
def fmt(paths):
 paths=sorted(set(paths),key=lambda p:p.encode())
 return ', '.join(paths[:3])+(' and '+str(len(paths)-3)+' more' if len(paths)>3 else '')
# This adapter records the exact environment, then delegates to real pytest JUnit.
# Two malformed-report modes intentionally remove or corrupt that real report.
write('adapter65.py', '''import json,os,subprocess,sys
from pathlib import Path
import xml.etree.ElementTree as ET
name,junit,target=sys.argv[1:]
record=Path(os.environ['RECORD65'])
entries=json.loads(record.read_text()) if record.exists() else []
f=os.environ.get('SHIPCRAFT_FILES'); c=os.environ.get('SHIPCRAFT_CASES')
files=Path(f).read_bytes().split(b'\\0')[:-1] if f else []
entries.append(dict(suite=name,files=[os.fsdecode(p) for p in files],cases=bool(c)))
record.write_text(json.dumps(entries))
mode=os.environ['MODE65']
# A fixed per-suite target makes overlap ownership observable; otherwise honor files.
paths=[target] if target!='-' else [os.fsdecode(p) for p in files if Path(os.fsdecode(p)).name.startswith('test_')]
if not paths: paths=['tests']
p=subprocess.run(['pytest','--junitxml='+junit,*paths])
if f and not c and mode in ('no-report','no-report-unmapped') and name=='b':
 Path(junit).unlink(); sys.exit(1)
if f and not c and (mode in ('unmapped','unmapped-helper') or (mode=='no-report-unmapped' and name=='a')):
 tree=ET.parse(junit)
 for case in tree.iter('testcase'):
  case.set('classname','external65'); case.set('name','no_file65'); case.attrib.pop('file',None)
 tree.write(junit)
if c and mode=='second-run-fails':
 Path(junit).unlink(); sys.exit(1)
sys.exit(p.returncode)
''')
os.environ['MODE65']=mode; record=Path('../record65.json').resolve(); os.environ['RECORD65']=str(record)
git('init','-q','-b','main'); git('config','user.name','RED65'); git('config','user.email','red65@example.invalid')
write('.gitignore','__pycache__/\n.pytest_cache/\n')
suites=[('a','.', '-')]
if mode.startswith('monorepo'): suites=[('a','api','-'),('b','jobs','-')]
if mode.startswith('overlap'): suites=[('a','.', 'tests/test_a65.py'),('b','.', 'tests/test_legacy65.py' if mode=='overlap-uncovered' else 'tests/test_b65.py')]
if mode.startswith('no-report'): suites=[('a','.', 'tests/test_a65.py'),('b','.', 'tests/test_b65.py')]
config='shipcraft_min = "0.0"\nlang = "python"\nrunner = "pytest"\n[execution]\nci = "local"\nreview = "off"\n'
for name,root,target in suites:
 command=shlex.join([sys.executable,str(Path('adapter65.py').resolve()),name,'{junit}',target])
 check='echo checked >> '+shlex.quote(str(Path('../check65-'+name).resolve()))
 if mode=='monorepo-check' and name=='b': check+='; exit 1'
 config+='\n[[suite]]\nname = '+json.dumps(name)+'\nroot = '+json.dumps(root)+'\nfilter = "command"\ncommand = '+json.dumps(command)+'\nglobs = ["tests/**"]\ncheck = '+json.dumps(check)+'\n'
write('.shipcraft.toml',config)
roots=sorted({root for _,root,_ in suites})
for root in roots:
 test(str(Path(root,'tests/test_legacy65.py')),'legacy65')
 write(str(Path(root,'tests/helper65.py')),'# support65\n')
# Overlap reports intentionally own only one file each, including on full runs.
if mode.startswith(('overlap','no-report')):
 test('tests/test_a65.py','a65'); test('tests/test_b65.py','b65')
commit('test: base suites and protected support65')
# Local remote ref provides the real merge base without network.
git('update-ref','refs/remotes/origin/main','HEAD'); git('symbolic-ref','refs/remotes/origin/HEAD','refs/remotes/origin/main')
git('checkout','-qb','feature/item65')
active='api' if mode.startswith('monorepo') else '.'
new=str(Path(active,'tests/test_fresh65.py')); helper=str(Path(active,'tests/helper65.py'))
selected=[]; uncovered=[]; fallback=None; code=''; redo=mode.startswith('redo')
if mode.startswith(('overlap','no-report')):
 selected=['tests/test_a65.py','tests/test_b65.py','tests/helper65.py']
 for p in selected: Path(p).write_text(Path(p).read_text()+'\n')
 uncovered=selected[:] # a owns a only, b owns b only: union includes both test files.
 if mode=='overlap-shared':
  write('tests/shared65.py','# same support in both suites\n'); selected+=['tests/shared65.py']; uncovered+=['tests/shared65.py']
 if mode.startswith('no-report'): fallback='no report'; uncovered=[]
 if mode=='overlap-uncovered': fallback='file without cases'; uncovered=[]
else:
 if redo:
  test(new,'fresh65'); initial=run(binary,'red'); assert locks(),initial
  lock=locks()[0]; original=lock.read_bytes(); commit('test: initial narrow lock65')
  record.unlink(); git('update-ref','refs/remotes/origin/main','HEAD')
 if not mode.endswith('lock-only'): test(new,'fresh65','pass' if mode=='passing' else 'error' if mode=='error' else 'fail')
 selected=[new]
 if mode not in ('no-support','no-support-many','monorepo-clean'):
  Path(helper).write_text('# changed support65\n'); selected+=[helper]; uncovered=[helper]
 if mode=='redo':
  with Path(new).open('a') as f: f.write('\ndef test_extra65():\n    assert True\n')
 if mode=='monorepo-helper':
  write('jobs/tests/helper65.py','# changed second suite helper\n'); selected+=['jobs/tests/helper65.py']; fallback='file without cases'; uncovered=[]
 if mode in ('helper-only','helpers-only'):
  Path(new).unlink(); selected.remove(new); fallback='file without cases'; uncovered=[]
 if mode in ('helpers-only','environment-many'):
  for p in ('tests/z helper65.py','tests/a helper65.py','tests/é helper65.py'):
   write(p,'# extra helper65\n'); selected+=[p]; uncovered+=[p]
 if mode in ('skipped','skipped-only'):
  test(new,'fresh65','skip')
  if mode=='skipped': test('tests/test_fail65.py','fail65'); selected+=['tests/test_fail65.py']
  else: code='red-already-passes'
 if mode=='no-support-many': test('tests/test_extra65.py','extra65'); selected+=['tests/test_extra65.py']
 if mode=='passing': code='red-already-passes'
 if mode=='error':
  with Path(new).open('a') as f: f.write('raise RuntimeError("collection65")\n')
  code='error-before-assertions'
 if mode.startswith('unmapped'): fallback='case without file'; uncovered=[]
 if mode=='unmapped-helper':
  # Helper-only selection competes with case-without-file from the legacy report.
  Path(new).unlink(); selected.remove(new)
 if mode=='monorepo-check': code='no-report'; uncovered=[]
 if mode=='second-run-passes':
  write(new,'import os\ndef test_fresh65():\n    assert bool(os.environ.get("SHIPCRAFT_CASES"))\n'); code='red-not-reproduced'
# Execution counts distinguish the required two runs from a full-run retry plus rerun.
before=len(rows()) if redo else 0
if mode=='log-fails':
 log=Path('.git/shipcraft/runs.jsonl'); log.unlink(missing_ok=True); log.mkdir(parents=True)
p=run(binary,'red',*(['--redo'] if redo else []),ok=False); text=p.stdout+p.stderr
want(p.returncode==(1 if code else 0),'wrong exit status: '+str(p.returncode))
protected={'.shipcraft.toml'}|{str(p) for root in roots for p in Path(root,'tests').glob('*') if p.is_file()}
lines=text.splitlines(); n=len(set(selected))
notice='shipcraft: red ran every suite: '+fallback if fallback else f'shipcraft: red ran the changed test files: {n} of {len(protected)}'
want(lines.count(notice)==1,'selection notice: '+notice)
prefix='shipcraft: red did not run the tests that may use the changed support file(s): '
if uncovered and not fallback and mode!='monorepo-check':
 expected=prefix+fmt(uncovered)+'; CI runs them'
 want(expected in lines,'missing/wrong exact support notice: '+expected)
 if notice in lines: want(lines[lines.index(notice)+1:lines.index(notice)+2]==[expected],'support notice must immediately follow selection')
 want(sum(s.startswith(prefix) for s in lines)==1,'support notice count')
else: want(not any(s.startswith(prefix) for s in lines),'unexpected support notice')
if mode!='log-fails':
 rs=rows(); want(len(rs)==before+1,'one row per command'); r=rs[-1]
 want((r.get('selection'),r.get('selected_files'),r.get('fallback'))==('all' if fallback else 'changed',n,fallback),'selection fields: '+repr(r))
 want(r.get('code')==code,'refusal code: '+repr(r))
 keys={'at','branch','code','commit','fallback','layer','lock','result','secs','selected_files','selection'}
 if code: keys.add('reason')
 else: keys.add('rerun_dropped')
 if redo: keys.add('redo')
 else: keys.update(('kind','reported_at','fixes_release'))
 if not redo: want((r.get('kind'),r.get('reported_at'),r.get('fixes_release'))==('feature',None,None),'fix row values')
 want(set(r)==keys,'red row gained/lost fields: '+repr(r))
 want(r.get('result')==('refused' if code else 'passed'),'row result')
 if redo: want(r.get('redo') is True,'redo flag')
if code:
 if redo: want(lock.read_bytes()==original,'refusal changed lock')
 else: want(not locks(),'refusal created lock')
else:
 ls=locks(); want(len(ls)==1,'exactly one lock')
 if ls:
  d=json.loads(ls[0].read_text()); want(set(d['files'])==protected,'protection must include helpers and inactive suites')
  for f,h in d['files'].items(): want(h=='sha256:'+hashlib.sha256(Path(f).read_bytes()).hexdigest(),'wrong hash: '+f)
  expected=set(); failing=set()
  for name,root,target in suites:
   files=[Path(target)] if target!='-' else list(Path(root,'tests').glob('test_*.py'))
   for f in files:
    path=str(f)
    if not fallback and path not in selected: continue
    import re
    text=f.read_text()
    # judged per function: a redo appends a passing test next to the failing one
    for function,body in re.findall(r'^def (test_\w+)\(.*?\n((?:[ \t]+.*\n?)*)',text,re.M):
     ident=name+':tests.'+f.stem+'::'+function
     if '@pytest.mark.skip' not in text: expected.add(ident)
     if '@pytest.mark.skip' not in text and 'assert True' not in body: failing.add(ident)
  want(set(d['cases'])==expected,'kept cases: '+repr(d['cases'])+' expected '+repr(expected))
  want(set(d['failing_at_red'])==failing,'kept failures: '+repr(d['failing_at_red']))
entries=json.loads(record.read_text())
if mode.startswith('environment'):
 first=entries[0]; want(first['files']==sorted(str(Path(p).resolve()) for p in selected),'adapter lost support paths: '+repr(first))
 want(first['cases'] is False,'first run received SHIPCRAFT_CASES')
if mode.startswith('monorepo'):
 if mode!='monorepo-helper': want(all(e['suite']=='a' for e in entries),'unselected suite command ran')
 want(Path('../check65-b').read_text()=='checked\n','unselected suite check must run once')
if not fallback and mode!='monorepo-check':
 active_suites=1 if mode.startswith('monorepo') else len(suites)
 expected_runs=active_suites+(0 if mode in ('passing','skipped-only','error') else active_suites)
 want(len(entries)==expected_runs,'unexpected extra/full run: '+repr(entries))
assert not errors,'\n'.join(errors)
PY65
  pass
}
