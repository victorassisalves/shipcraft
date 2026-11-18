# Item 119; spec commit 249490e. Structural reads only; no product invocation.
item119_langs() { echo core; }
item119_cases() {
  local c
  for c in root asker answers checks blocking process tests contents unique ceiling definitions-control modules-control tests-control contents-control ceiling-control read-control unique-control impl-control; do
    echo "v1-119.$c"
  done
}
item119_case() {
  EXPECT="item 119: ${CASE#v1-119.}"
  must_accept 'item 119 static contract' cmd "$PY" - "${CASE#v1-119.}" "$ACEITE/.." "$CW" <<'PY119'
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
  if name == 'tests':
   assert any(a == '#[cfg(test)]' and b == 'mod tests;' for a,b in zip(lines, lines[1:])), 'missing adjacent cfg(test)/mod tests'
   continue
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
def unique(paths, wanted):
 owners = {}
 for path in paths:
  if path.name == 'tests.rs': continue
  for name in {name for kind,name in definitions(read(path))} & set(wanted):
   assert name not in owners, str(path) + ': duplicate ' + name + ' also in ' + str(owners.get(name))
   owners[name] = path
 return owners
def impls(paths, owner, name, exact):
 for path in paths:
  if path.name == 'tests.rs': continue
  lines = read(path).split('\n')
  matches = [line for line in lines if line.startswith('impl') and name + '<' in line]
  assert matches == ([exact] if path == owner else []), str(path) + ': wrong impl for ' + name
def rejects(action, fragment):
 try: action()
 except AssertionError as e:
  assert fragment in str(e), str(e)
 else: raise AssertionError('fixture unexpectedly accepted: ' + fragment)
base = root / 'nucleo/src'
files = ['relatorio_gh.rs', 'relatorio_gh/asker.rs', 'relatorio_gh/answers.rs', 'relatorio_gh/checks.rs', 'relatorio_gh/blocking.rs', 'relatorio_gh/process.rs', 'relatorio_gh/tests.rs']
module_names = ['asker','answers','checks','blocking','process','tests']
table_names = ['FAILED', 'UNREADABLE', 'TIMED_OUT', 'Pr', 'Outcome', 'Asker', 'PrView', 'pages', 'check_run', 'oid', 'time', 'Tally', 'Verdict', 'Run', 'pr_commits', 'suite_runs', 'tally', 'latest_count', 'blocking_count', 'LIMIT', 'Ran', 'run']
test_names = ['pr_commits_are_distinct_shas_in_answer_order', 'suite_runs_read_completed_runs_of_the_names', 'each_red_run_is_green_again_fixed_by_a_new_commit_or_still_red', 'a_pr_is_read_in_full_or_gives_its_one_reason', 'blocking_counts_follow_the_grammar', 'the_latest_count_wins_ties_to_the_first', 'times_are_github_utc_real_dates']
if case == 'root':
 path = base / 'relatorio_gh.rs'
 text = read(path)
 expected = {('enum', 'Pr'), ('const', 'TIMED_OUT'), ('type', 'Outcome'), ('const', 'FAILED'), ('const', 'UNREADABLE')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
 try: modules(text, module_names)
 except AssertionError as e: raise AssertionError(str(path) + ': ' + str(e)) from e
elif case == 'asker':
 path = base / 'relatorio_gh/asker.rs'
 text = read(path)
 expected = {('struct', 'Asker')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
 impls([path], path, 'Asker', "impl<'a> Asker<'a> {")
elif case == 'answers':
 path = base / 'relatorio_gh/answers.rs'
 text = read(path)
 expected = {('fn', 'oid'), ('fn', 'pages'), ('fn', 'time'), ('struct', 'PrView'), ('fn', 'check_run')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
 impls([path], path, 'PrView', "impl<'v> PrView<'v> {")
elif case == 'checks':
 path = base / 'relatorio_gh/checks.rs'
 text = read(path)
 expected = {('enum', 'Verdict'), ('type', 'Tally'), ('fn', 'tally'), ('struct', 'Run'), ('fn', 'suite_runs'), ('fn', 'pr_commits')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'blocking':
 path = base / 'relatorio_gh/blocking.rs'
 text = read(path)
 expected = {('fn', 'blocking_count'), ('fn', 'latest_count')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'process':
 path = base / 'relatorio_gh/process.rs'
 text = read(path)
 expected = {('enum', 'Ran'), ('fn', 'run'), ('const', 'LIMIT')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'tests':
 path = base / 'relatorio_gh/tests.rs'
 assert set(test_names) == tests(read(path)), str(path) + ': wrong attributed test names'
elif case == 'contents':
 contents(base / 'relatorio_gh', [Path(f).name for f in files[1:]])
elif case == 'unique':
 paths = [base / f for f in files[:-1]]
 unique(paths, table_names)
 impls(paths, base / 'relatorio_gh/asker.rs', 'Asker', "impl<'a> Asker<'a> {")
 impls(paths, base / 'relatorio_gh/answers.rs', 'PrView', "impl<'v> PrView<'v> {")
elif case == 'ceiling':
 ceiling(base / 'relatorio_gh.rs')
 for p in contents(base / 'relatorio_gh', [Path(f).name for f in files[1:]]): ceiling(p)
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
 p.write_text("impl<'a> Asker<'a> {\npub struct Asker<'a> {\nfn times(\n    fn time(\npub use asker::Asker;\n")
 assert definitions(read(p)) == {('struct','Asker'), ('fn','times')}
elif case == 'modules-control':
 p = cw / 'modules.rs'
 p.write_text('mod alpha;\npub(crate) mod beta;\npub(super) mod gamma;\n')
 modules(read(p), ['alpha','beta','gamma'])
 for text in (' mod alpha;', 'pub mod alpha;', 'mod alphabet;', 'mod alpha; // comment', 'mod alpha {'):
  p.write_text(text); rejects(lambda: modules(read(p), ['alpha']), 'alpha')
 p.write_text('#[cfg(test)]\nmod tests;\n'); modules(read(p), ['tests'])
 for text in ('mod tests;', '#[cfg(test)]\n\nmod tests;', '#[cfg(test)]\npub(crate) mod tests;', ' #[cfg(test)]\n mod tests;'):
  p.write_text(text); rejects(lambda: modules(read(p), ['tests']), 'cfg(test)')
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
 a, b, t = cw / 'process.rs', cw / 'root.rs', cw / 'tests.rs'
 a.write_text('fn run() {}\nstruct Asker {}\nimpl Asker {}\n')
 b.write_text('    fn run() {}\nfn runner() {}\npub use asker::Asker;\n')
 t.write_text('fn run() {}\n')
 assert unique([a,b,t], ['run','Asker']) == {'run':a,'Asker':a}
 b.write_text('pub(super) fn run() {}\n')
 rejects(lambda: unique([a,b,t], ['run']), str(b) + ': duplicate run')
 b.write_text('enum Asker {}\n')
 rejects(lambda: unique([a,b], ['Asker']), str(b) + ': duplicate Asker')
 rejects(lambda: unique([a,cw/'missing.rs'], []), str(cw/'missing.rs'))
elif case == 'impl-control':
 a, b = cw / 'asker.rs', cw / 'root.rs'
 for name, exact in [('Asker', "impl<'a> Asker<'a> {"), ('PrView', "impl<'v> PrView<'v> {")]:
  a.write_text(exact + '\n'); b.write_text('')
  impls([a,b], a, name, exact)
  b.write_text(exact + '\n')
  rejects(lambda: impls([a,b], a, name, exact), str(b))
  b.write_text('')
  for text in ('', ' '+exact, exact+'\n'+exact, exact.replace("'a", "'b").replace("'v", "'b"), exact+' // comment', exact+'\nimpl<T> '+name+'<T> {'):
   a.write_text(text)
   rejects(lambda: impls([a,b], a, name, exact), str(a))
  a.write_text(exact)
  rejects(lambda: impls([a,cw/'missing.rs'], a, name, exact), str(cw/'missing.rs'))
else: raise AssertionError('unrouted ' + case)
PY119
  pass
}
