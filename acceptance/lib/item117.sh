# Item 117; spec commit 76ebf81. Structural reads only; no product invocation.
item117_langs() { echo core; }
item117_cases() {
  local c
  for c in root suites custom config_file agents hook lefthook files contents unique ceiling definitions-control modules-control tests-control contents-control ceiling-control read-control unique-control; do
    echo "v1-117.$c"
  done
}
item117_case() {
  EXPECT="item 117: ${CASE#v1-117.}"
  must_accept 'item 117 static contract' cmd "$PY" - "${CASE#v1-117.}" "$ACEITE/.." "$CW" <<'PY117'
import re, sys
from pathlib import Path
case, root, cw = sys.argv[1:]
root, cw = Path(root), Path(cw)
def read(path):
 try:
  return path.read_bytes().decode('utf-8')
 except (OSError, UnicodeError) as e:
  raise AssertionError(str(path) + ': cannot read UTF-8: ' + str(e)) from e
def definitions(text):
 found = set()
 for line in text.split('\n'):
  m = re.match(r'^(?:pub )?(?:pub\(crate\) |pub\(super\) )?(?:unsafe )?(fn|struct|enum|const|type) ([A-Za-z_][A-Za-z_0-9]*)(?=[(<: ;{=])', line)
  if not m:
   m = re.match(r'^(impl) ([A-Za-z_][A-Za-z_0-9]*)(?=[ {])', line)
  if m: found.add(m.groups())
 return found
def tests(text):
 found = set()
 previous = ''
 for line in text.split('\n'):
  m = re.match(r'^( {0,4})fn ([A-Za-z_][A-Za-z_0-9]*)\(', line)
  if m and previous == m[1] + '#[test]': found.add(m[2])
  if line.strip(): previous = line
 return found
def modules(text, names):
 lines = text.split('\n')
 for name in names:
  assert any(re.fullmatch(r'(?:pub\(crate\) |pub\(super\) )?mod ' + re.escape(name) + ';', line) for line in lines), 'missing mod ' + name

def contents(path, expected):
 try:
  entries = list(path.iterdir())
  assert {p.name for p in entries} == set(expected), str(path) + ': wrong folder contents'
  for p in entries:
   assert p.is_file(), str(p) + ': not a file'
   read(p)
 except OSError as e:
  raise AssertionError(str(path) + ': cannot list folder: ' + str(e)) from e
 return entries
def ceiling(path):
 data = read(path).encode('utf-8')
 count = data.count(b'\n') + int(bool(data) and not data.endswith(b'\n'))
 assert count <= 600, str(path) + ': ' + str(count) + ' lines exceeds 600'
 return count
def unique(paths, wanted, test_names):
 owners = {}
 for path in paths:
  text = read(path)
  names = {name for kind,name in definitions(text) if name in set(wanted) | set(test_names)} | (tests(text) & set(test_names))
  for name in names:
   assert name not in owners, str(path) + ': duplicate ' + name + ' also in ' + str(owners.get(name))
   owners[name] = path
 return owners
def rejects(action, fragment):
 try: action()
 except AssertionError as e:
  assert fragment in str(e), str(e)
 else: raise AssertionError('fixture unexpectedly accepted: ' + fragment)
base = root / 'nucleo/src'
files = ['init.rs', 'init/suites.rs', 'init/custom.rs', 'init/config_file.rs', 'init/agents.rs', 'init/hook.rs', 'init/lefthook.rs', 'init/files.rs']
module_names = ['suites', 'custom', 'config_file', 'agents', 'hook', 'lefthook', 'files']
table_names = ['LOCAL_NOTICE', 'open', 'Options', 'OTHER_FORM', 'SEED_NOTICE', 'run', 'ci_line', 'protect', 'Suites', 'plan', 'workspace_suites', 'drop_empty_checks', 'checks_no_file', 'choose_lang', 'Custom', 'custom', 'command_problem', 'AGENTS', 'HEADER', 'reviewer', 'quoted', 'config_text', 'AGENTS_FILE', 'CLAUDE_FILE', 'START_LINE', 'END_LINE', 'FIX_LINE', 'RISK_LINES', 'CLEANUP_LINE', 'AGENTS_BLOCK_2_30', 'AGENTS_BLOCK_2_26', 'AGENTS_BLOCK_2_25', 'AGENTS_BLOCK_2_22', 'ROOT_LINE', 'AGENTS_BLOCK_2_14', 'CLAUDE_BLOCK', 'DIFFERS', 'agents_text', 'agents_block_2_31', 'agents_block_2_39', 'current_block', 'after_line', 'variant', 'known_blocks', 'agents_block_status', 'agents_block', 'onboard', 'Found', 'find_block', 'rewrite', 'HOOK_MARK', 'LOCAL', 'PLAIN_LOCAL', 'LEFTHOOK_FILES', 'Hook', 'hook_status', 'Install', 'install', 'install_at', 'own_hook', 'HooksPath', 'hooks_path', 'decide_hook', 'decide_hook_with', 'lefthook_hook', 'install_hooks', 'lefthook_source', 'single_source', 'block_layout', 'layout', 'layout_step', 'insert_text', 'bare_nulls', 'on_path', 'is_executable', 'write_once', 'keep_config', 'write', 'make_executable']
test_names = ['config_text_writes_the_size_limit_after_review_and_before_build']
if case == 'root':
 path = base / 'init.rs'
 text = read(path)
 expected = {('struct', 'Options'), ('fn', 'ci_line'), ('fn', 'open'), ('const', 'OTHER_FORM'), ('fn', 'protect'), ('fn', 'run'), ('const', 'LOCAL_NOTICE'), ('const', 'SEED_NOTICE')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
 try: modules(text, module_names)
 except AssertionError as e: raise AssertionError(str(path) + ': ' + str(e)) from e
 assert not any(re.match(r'^(?:pub\(crate\) |pub\(super\) )?mod tests\b', line) for line in text.split('\n')), str(path) + ': tests module belongs in config_file.rs'
elif case == 'suites':
 path = base / 'init/suites.rs'
 text = read(path)
 expected = {('fn', 'drop_empty_checks'), ('type', 'Suites'), ('fn', 'checks_no_file'), ('fn', 'plan'), ('fn', 'workspace_suites'), ('fn', 'choose_lang')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'custom':
 path = base / 'init/custom.rs'
 text = read(path)
 expected = {('fn', 'custom'), ('fn', 'command_problem'), ('struct', 'Custom')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'config_file':
 path = base / 'init/config_file.rs'
 text = read(path)
 expected = {('fn', 'reviewer'), ('const', 'HEADER'), ('fn', 'config_text'), ('const', 'AGENTS'), ('fn', 'quoted')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
 assert set(test_names) <= tests(text), str(path) + ': missing attributed test ' + str(set(test_names) - tests(text))
elif case == 'agents':
 path = base / 'init/agents.rs'
 text = read(path)
 expected = {('fn', 'agents_block_status'), ('fn', 'known_blocks'), ('fn', 'agents_block_2_39'), ('const', 'CLAUDE_BLOCK'), ('const', 'DIFFERS'), ('fn', 'agents_block_2_31'), ('fn', 'agents_text'), ('const', 'END_LINE'), ('const', 'RISK_LINES'), ('enum', 'Found'), ('const', 'AGENTS_FILE'), ('fn', 'find_block'), ('fn', 'onboard'), ('const', 'AGENTS_BLOCK_2_30'), ('fn', 'rewrite'), ('const', 'AGENTS_BLOCK_2_25'), ('fn', 'agents_block'), ('const', 'ROOT_LINE'), ('const', 'START_LINE'), ('const', 'CLAUDE_FILE'), ('const', 'AGENTS_BLOCK_2_14'), ('fn', 'current_block'), ('fn', 'variant'), ('const', 'CLEANUP_LINE'), ('const', 'AGENTS_BLOCK_2_22'), ('const', 'AGENTS_BLOCK_2_26'), ('const', 'FIX_LINE'), ('fn', 'after_line')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'hook':
 path = base / 'init/hook.rs'
 text = read(path)
 expected = {('fn', 'decide_hook_with'), ('fn', 'own_hook'), ('enum', 'Hook'), ('const', 'HOOK_MARK'), ('fn', 'hooks_path'), ('const', 'LOCAL'), ('fn', 'install_at'), ('enum', 'Install'), ('fn', 'install'), ('fn', 'install_hooks'), ('const', 'PLAIN_LOCAL'), ('enum', 'HooksPath'), ('const', 'LEFTHOOK_FILES'), ('fn', 'decide_hook'), ('fn', 'hook_status'), ('fn', 'lefthook_hook')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'lefthook':
 path = base / 'init/lefthook.rs'
 text = read(path)
 expected = {('fn', 'bare_nulls'), ('fn', 'layout_step'), ('fn', 'insert_text'), ('fn', 'block_layout'), ('fn', 'single_source'), ('fn', 'layout'), ('fn', 'lefthook_source')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'files':
 path = base / 'init/files.rs'
 text = read(path)
 expected = {('fn', 'write_once'), ('fn', 'is_executable'), ('fn', 'on_path'), ('fn', 'make_executable'), ('fn', 'keep_config'), ('fn', 'write')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'contents':
 contents(base / 'init', [Path(f).name for f in files[1:]])
elif case == 'unique':
 unique([base / f for f in files], table_names, test_names)
elif case == 'ceiling':
 ceiling(base / 'init.rs')
 for p in contents(base / 'init', [Path(f).name for f in files[1:]]): ceiling(p)
elif case == 'definitions-control':
 p = cw / 'definitions.rs'
 p.write_text('type Row = ();\npub struct Prepared {}\npub(crate) enum Selection { A }\npub(super) const REPOSITORY_VARS: () = ();\nfn read<T>(x: T) {}\nimpl Prepared {\n    fn run() {}\n}\nfn reader() {}\n fn read() {}\n    fn read() {}\nuse x::read;\nimpl PreparedExtra {}\n')
 assert definitions(read(p)) == {('type','Row'),('struct','Prepared'),('enum','Selection'),('const','REPOSITORY_VARS'),('fn','read'),('impl','Prepared'),('fn','reader'),('impl','PreparedExtra')}
 for suffix in ('(', '<', ':', ' ', ';', '{', '='):
  p.write_text('fn read' + suffix)
  assert definitions(read(p)) == {('fn','read')}
 for text in ('fn reader(', 'fn read_more(', 'fn read9(', 'fn readé(', 'fn read', '\tfn read(', '    fn read(', 'use x::read;', 'impl Prepared<T> {'):
  p.write_text(text)
  assert ('fn','read') not in definitions(read(p)) and ('impl','Prepared') not in definitions(read(p)), text
 for prefix in ('', 'pub ', 'pub(crate) ', 'pub(super) ', 'pub pub(crate) '):
  p.write_text(prefix + 'unsafe fn layout_step() {}\n')
  assert definitions(read(p)) == {('fn', 'layout_step')}
 for text in (' unsafe fn layout_step() {}', '    unsafe fn layout_step() {}', 'fn layouts() {}', 'pub use hook::LOCAL;', 'pub(crate) use hook::LOCAL;', 'impl X {\n    fn layout() {}\n}', 'fn outer() {\n    fn layout() {}\n}'):
  p.write_text(text)
  assert not ({('fn', 'layout_step'), ('fn', 'layout'), ('const', 'LOCAL')} & definitions(read(p))), text
elif case == 'modules-control':
 p = cw / 'modules.rs'
 p.write_text('mod alpha;\npub(crate) mod beta;\npub(super) mod gamma;\n')
 modules(read(p), ['alpha','beta','gamma'])
 for text in (' mod alpha;', 'pub mod alpha;', 'mod alphabet;', 'mod alpha; // comment', 'mod alpha {'):
  p.write_text(text); rejects(lambda: modules(read(p), ['alpha']), 'alpha')
elif case == 'tests-control':
 p = cw / 'tests.rs'
 for indent in range(5):
  pad = ' ' * indent
  p.write_text(pad + '#[test]\n\n' + pad + 'fn chosen() {}\n')
  assert tests(read(p)) == {'chosen'}
 for text in ('fn chosen() {}', '#[test]\n fn chosen() {}', '     #[test]\n     fn chosen() {}', '#[test]\n// intervening\nfn chosen() {}', '#[test]\nfn chosen_more() {}', '#[test]\npub fn chosen() {}', '#[test]\nfn chosen () {}'):
  p.write_text(text); assert 'chosen' not in tests(read(p)), text
elif case == 'contents-control':
 folder = cw / 'modules'; folder.mkdir()
 (folder / 'one.rs').write_text('fn one() {}')
 assert [p.name for p in contents(folder, ['one.rs'])] == ['one.rs']
 (folder / 'stray.txt').write_text('')
 rejects(lambda: contents(folder, ['one.rs']), str(folder))
 (folder / 'stray.txt').unlink(); (folder / 'nested').mkdir()
 rejects(lambda: contents(folder, ['one.rs']), str(folder))
 (folder / 'nested').rmdir(); (folder / 'one.rs').unlink(); (folder / 'one.rs').mkdir()
 rejects(lambda: contents(folder, ['one.rs']), str(folder / 'one.rs'))
 rejects(lambda: contents(cw / 'absent', []), str(cw / 'absent'))
 rejects(lambda: contents(cw / 'modules/one.rs/missing', []), 'missing')
 from unittest.mock import patch
 with patch.object(Path, 'iterdir', side_effect=PermissionError('fixture denied')):
  rejects(lambda: contents(folder, ['one.rs']), str(folder))
elif case == 'ceiling-control':
 p = cw / 'lines.rs'
 for final in (True, False):
  for count in (600, 601):
   p.write_bytes(b'x\n' * (count - 1) + b'x' + (b'\n' if final else b''))
   if count == 600: assert ceiling(p) == 600
   else: rejects(lambda: ceiling(p), str(p) + ': 601 lines')
 for data, count in ((b'',0), (b'\n',1), (b'x',1), ('a\rb\u2028c\u2029d'.encode(),1), (b'a\r\nb\r\n',2)):
  p.write_bytes(data); assert ceiling(p) == count
elif case == 'read-control':
 p = cw / 'reader.rs'
 rejects(lambda: read(p), str(p))
 p.mkdir(); rejects(lambda: read(p), str(p)); p.rmdir()
 p.write_bytes(b'\xff'); rejects(lambda: read(p), str(p))
 rejects(lambda: ceiling(p), str(p))
 folder = cw / 'invalid'; folder.mkdir(); q = folder / 'bad.rs'; q.write_bytes(b'\xff')
 rejects(lambda: contents(folder, ['bad.rs']), str(q))
 p.write_bytes('\ufeffa\r\nb\rc\u2028d\u2029'.encode())
 assert read(p) == '\ufeffa\r\nb\rc\u2028d\u2029'
 from unittest.mock import patch
 with patch.object(Path, 'read_bytes', side_effect=PermissionError('fixture denied')):
  rejects(lambda: read(p), str(p))
elif case == 'unique-control':
 a, b = cw / 'first.rs', cw / 'second.rs'
 a.write_text('struct Prepared {}\nimpl Prepared {}\nfn read() {}\n')
 b.write_text('    fn read() {}\nfn reader() {}\nuse x::Prepared;\n#[test]\n    fn ignored() {}\n')
 assert unique([a,b], ['Prepared','read'], []) == {'Prepared':a,'read':a}
 b.write_text('pub(super) fn read() {}\n')
 rejects(lambda: unique([a,b], ['Prepared','read'], []), str(b) + ': duplicate read')
 b.write_text('enum Prepared {}\n')
 rejects(lambda: unique([a,b], ['Prepared'], []), str(b) + ': duplicate Prepared')
 a.write_text('#[test]\nfn selected() {}\n'); b.write_text('    #[test]\n    fn selected() {}\n')
 rejects(lambda: unique([a,b], [], ['selected']), str(b) + ': duplicate selected')
 rejects(lambda: unique([a,cw/'missing.rs'], [], []), str(cw/'missing.rs'))
else: raise AssertionError('unrouted ' + case)
PY117
  pass
}
