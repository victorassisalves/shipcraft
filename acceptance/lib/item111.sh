# Item 111; spec commit 157d53e. Static repository reads only.
item111_langs() { echo core; }
item111_cases() {
  local c
  for c in toolchain channel components targets workflow-name triggers permissions job install tools forbidden job-config config-control toml-pass-control toml-fail-control workflow-pass-control workflow-fail-control; do
    echo "v1-111.$c"
  done
}
item111_case() {
  EXPECT="item 111: ${CASE#v1-111.}"
  must_accept 'item 111 static contract' cmd "$PY" - "${CASE#v1-111.}" "$ACEITE/.." "$CW" <<'PY111'
import re,sys
from pathlib import Path
try: import tomllib
except ImportError: import tomli as tomllib
case,root,cw=sys.argv[1:];root=Path(root);cw=Path(cw)
def read_toml(path):
 try:
  return tomllib.loads(path.read_text(encoding='utf-8'))
 except (OSError,ValueError) as e:
  raise AssertionError(str(path)+': cannot read TOML: '+str(e)) from e
def workflow(path):
 try:
  return [line.rstrip() for line in path.read_text(encoding='utf-8').split('\n') if not line.lstrip().startswith('#')]
 except (OSError,ValueError) as e:
  raise AssertionError(str(path)+': cannot read workflow: '+str(e)) from e
def positions(lines,block):
 return [i for i in range(len(lines)-len(block)+1) if lines[i:i+len(block)]==block]
def job_lines(lines):
 # Only the jobs mapping, stopping at the next top-level key.
 start=lines.index('jobs:')+1
 end=next((i for i in range(start,len(lines)) if lines[i] and not lines[i][0].isspace()),len(lines))
 return [line for line in lines[start:end] if re.fullmatch(r'  \S.*:',line)]
pin=root/'rust-toolchain.toml';wf=root/'.github/workflows/lint.yml'
if case=='toolchain':
 d=read_toml(pin);assert isinstance(d.get('toolchain'),dict),str(pin)+': missing [toolchain] table'
elif case=='channel':
 d=read_toml(pin).get('toolchain',{});v=d.get('channel')
 assert isinstance(v,str) and re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',v),str(pin)+': channel must be exact X.Y.Z'
elif case=='components':
 v=read_toml(pin).get('toolchain',{}).get('components')
 assert isinstance(v,list) and all(isinstance(x,str) for x in v) and {'clippy','rustfmt'}<=set(v),str(pin)+': components must include clippy and rustfmt'
elif case=='targets':
 v=read_toml(pin).get('toolchain',{}).get('targets')
 assert isinstance(v,list) and all(isinstance(x,str) for x in v) and {'aarch64-apple-darwin','x86_64-apple-darwin'}<=set(v),str(pin)+': both release targets required'
elif case=='workflow-name':
 lines=workflow(wf);assert lines.count('name: lint')==1,str(wf)+': workflow name: lint at column zero'
elif case=='triggers':
 lines=workflow(wf);assert positions(lines,['on:','  pull_request:','  push:']),str(wf)+': exact unfiltered block triggers required'
 # No nested push filter or branch selection after the fixed trigger block.
 i=lines.index('  push:')+1
 assert not any(s and s[0].isspace() for s in lines[i:next((j for j in range(i,len(lines)) if lines[j] and not lines[j][0].isspace()),len(lines))]),str(wf)+': push must have no children'
elif case=='permissions':
 lines=workflow(wf);assert positions(lines,['permissions:','  contents: read']),str(wf)+': read contents permission required'
elif case=='job':
 lines=workflow(wf);assert 'jobs:' in lines and job_lines(lines)==['  lint:'],str(wf)+': exactly one lint job'
 assert positions(lines,['  lint:','    name: lint','    runs-on: ubuntu-latest']),str(wf)+': job name and runner fixed form'
elif case=='install':
 lines=workflow(wf)
 checkout=[i for i,s in enumerate(lines) if s in ('      - uses: actions/checkout@v4','        uses: actions/checkout@v4')]
 install=positions(lines,['        run: rustup toolchain install'])
 fmt=positions(lines,['      - name: Format'])
 assert len(checkout)==len(install)==len(fmt)==1 and checkout[0]<install[0]<fmt[0],str(wf)+': checkout then argument-free root install then tools'
 # Parse the small fixed step layout as text; install may have a descriptive name.
 steps=[i for i,s in enumerate(lines) if s.startswith('      - ')]
 ii=next(i for i in reversed(steps) if i<install[0])
 assert steps.index(ii)==1,str(wf)+': install immediately after checkout'
 directories=[s.split('working-directory:',1)[1].strip() for s in lines[ii:steps[2]] if 'working-directory:' in s]
 defaults=[s.split('working-directory:',1)[1].strip() for s in lines[:steps[0]] if 'working-directory:' in s]
 assert (directories or defaults or ['.'])[-1] in ('.',"'.'",'"."'),str(wf)+': install must run at checkout root'
 middle=steps[2:steps.index(fmt[0])]
 assert len(middle)<=1,str(wf)+': only optional cache between install and tools'
 if middle:
  assert any(s in ('      - uses: Swatinem/rust-cache@v2','        uses: Swatinem/rust-cache@v2') for s in lines[middle[0]:fmt[0]]) and positions(lines[middle[0]:fmt[0]],['        with:','          workspaces: nucleo']),str(wf)+': cache workspace nucleo'
elif case=='tools':
 lines=workflow(wf)
 block=['      - name: Format','        working-directory: nucleo','        run: cargo fmt --check','      - name: Lint','        working-directory: nucleo','        run: cargo clippy --all-targets -- -D warnings']
 assert positions(lines,block),str(wf)+': six exact consecutive tool lines required'
elif case=='forbidden':
 lines=workflow(wf)
 for token in ('continue-on-error','paths','if:','|| true','set +e','shell:','secrets.'):
  assert not any(token in s for s in lines),str(wf)+': forbidden token '+token
elif case=='job-config':
 checks=read_toml(root/'.shipcraft.toml')['execution']['suite_checks'];lines=workflow(wf)
 assert len(checks)==2 and positions(lines,['  lint:','    name: '+checks[1],'    runs-on: ubuntu-latest']),str(wf)+': job name must equal second suite_checks entry'
elif case=='config-control':
 assert read_toml(root/'.shipcraft.toml')['execution']['suite_checks']==['acceptance','lint'],'.shipcraft.toml: exact suite_checks order'
elif case=='toml-pass-control':
 p=cw/'rust-toolchain.toml'
 p.write_bytes(b'# fixture111\r\n[toolchain]\r\nchannel = "7.8.9" # exact release\r\ncomponents = ["rustfmt", "clippy",]\r\ntargets = ["x86_64-apple-darwin", "aarch64-apple-darwin"]\r\n')
 d=read_toml(p)
 assert d=={'toolchain':{'channel':'7.8.9','components':['rustfmt','clippy'],'targets':['x86_64-apple-darwin','aarch64-apple-darwin']}}
 assert re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',d['toolchain']['channel'])
elif case=='toml-fail-control':
 p=cw/'rust-toolchain.toml'
 for text in (None,'[toolchain\nchannel = "1.2.3"','\ufeff[toolchain]\nchannel="1.2.3"'):
  if text is not None:p.write_text(text)
  try:read_toml(p)
  except AssertionError as e:assert str(p) in str(e) and 'cannot read TOML' in str(e)
  else:raise AssertionError('reader accepted missing/invalid TOML')
 for value in ('stable','beta','nightly','2026-11-17','1.99',7,False):
  p.write_text('[toolchain]\nchannel = '+('"'+value+'"' if isinstance(value,str) else str(value).lower())+'\n')
  v=read_toml(p)['toolchain']['channel']
  assert not (isinstance(v,str) and re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+',v)),value
 for text in ('channel="1.2.3"','[toolchain]\ncomponents=["clippy"]','[toolchain]\ncomponents=["rustfmt"]','[toolchain]\ncomponents="clippy rustfmt"'):
  p.write_text(text);v=read_toml(p).get('toolchain',{}).get('components')
  assert not (isinstance(v,list) and {'clippy','rustfmt'}<=set(v)),text
elif case=='workflow-pass-control':
 p=cw/'lint.yml'
 text='name: lint\non:\n  pull_request:\n  push:\npermissions:\n  contents: read\njobs:\n  lint:\n    name: lint\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4\n      - name: Install\n        run: rustup toolchain install\n      - name: Format\n        working-directory: nucleo\n        run: cargo fmt --check\n      - name: Lint\n        working-directory: nucleo\n        run: cargo clippy --all-targets -- -D warnings\n'
 p.write_bytes(('  # paths if: shell: secrets. continue-on-error || true set +e\r\n'+'\r\n'.join(s+'  ' for s in text.split('\n'))).encode())
 lines=workflow(p)
 assert lines==text.split('\n'),lines
 assert positions(lines,['on:','  pull_request:','  push:'])==[1]
 assert positions(lines,['        run: rustup toolchain install'])==[13]
 assert positions(lines,['      - name: Format','        working-directory: nucleo','        run: cargo fmt --check','      - name: Lint','        working-directory: nucleo','        run: cargo clippy --all-targets -- -D warnings'])==[14]
 assert job_lines(lines)==['  lint:']
elif case=='workflow-fail-control':
 p=cw/'lint.yml'
 try:workflow(p)
 except AssertionError as e:assert str(p) in str(e) and 'cannot read workflow' in str(e)
 else:raise AssertionError('reader accepted absent workflow')
 # Each altered fixture goes through the very same text/sequence readers.
 for text,block in (
  ('on: [push, pull_request]\n',['on:','  pull_request:','  push:']),
  ('on:\n  push:\n  pull_request:\n',['on:','  pull_request:','  push:']),
  ('# name: lint\n',['name: lint']),
  ('        run: cargo fmt\n',['        run: cargo fmt --check']),
  ('        run: cargo clippy -- -D warnings\n',['        run: cargo clippy --all-targets -- -D warnings']),
  ('        run: cargo clippy --all-targets\n',['        run: cargo clippy --all-targets -- -D warnings']),
  ('        # run: cargo fmt --check\n',['        run: cargo fmt --check']),
  ('        run: rustup toolchain install stable\n',['        run: rustup toolchain install'])):
  p.write_text(text);assert not positions(workflow(p),block),(text,block)
 for token in ('continue-on-error','paths','if:','|| true','set +e','shell:','secrets.'):
  p.write_text('        '+token+' fixture111\n');lines=workflow(p)
  assert any(token in s for s in lines),token
 p.write_text('jobs:\n  lint:\n    name: lint\n  extra:\n    name: extra\n')
 assert job_lines(workflow(p))==['  lint:','  extra:']
else:raise AssertionError('unrouted '+case)
PY111
  pass
}
