# Item 116; spec commit de1a038. Structural reads only; no product invocation.
item116_langs() { echo core; }
item116_cases() {
  local c
  for c in root selection git evidence dora flow quality github rows text tests contents unique ceiling definitions-control modules-control tests-control contents-control ceiling-control read-control unique-control; do
    echo "v1-116.$c"
  done
}
item116_case() {
  EXPECT="item 116: ${CASE#v1-116.}"
  must_accept 'item 116 static contract' cmd "$PY" - "${CASE#v1-116.}" "$ACEITE/.." "$CW" <<'PY116'
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
  m = re.match(r'^(?:pub )?(?:pub\(crate\) |pub\(super\) )?(fn|struct|enum|const|type) ([A-Za-z_][A-Za-z_0-9]*)(?=[(<: ;{=])', line)
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
  else:
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
files = ['relatorio.rs', 'relatorio/selection.rs', 'relatorio/git.rs', 'relatorio/evidence.rs', 'relatorio/dora.rs', 'relatorio/flow.rs', 'relatorio/quality.rs', 'relatorio/github.rs', 'relatorio/rows.rs', 'relatorio/text.rs', 'relatorio/tests.rs']
module_names = ['selection', 'git', 'evidence', 'dora', 'flow', 'quality', 'github', 'rows', 'text', 'tests']
table_names = ['Evidence', 'Facts', 'FixData', 'Git', 'Merged', 'Prepared', 'REPOSITORY_VARS', 'Release', 'Report', 'Row', 'Selection', 'ask_github', 'at', 'blocking', 'checks', 'civil', 'day', 'days_from_civil', 'discover', 'dora', 'dora_text', 'duration', 'failure', 'first', 'first_row', 'fix_of_row', 'is', 'lock_row', 'locks_of', 'matches', 'median', 'merge_counts', 'merge_row', 'metric', 'not_a_release_name', 'num', 'p90', 'partial', 'percent', 'pr_of', 'read', 'red_row', 'reds', 'release_time', 'review', 'reviewed_commits', 'reviewed_prs', 'round_pr', 'run', 'seconds', 'show_with', 'size', 'stats', 'str_of', 'text', 'unix_time', 'unreadable', 'utc', 'utf8', 'version_cmp']
test_names = ['percentiles_follow_the_fixed_readings', 'utc_day_boundaries', 'readable_text_forms', 'release_tag_patterns_match_whole_names', 'selection_reads_only_the_report_table_and_never_refuses', 'fixes_release_must_be_a_release_name_of_the_selection', 'a_red_row_fixes_release_is_read_when_a_tag_name', 'size_counts_each_pr_by_its_last_measured_row_before_its_merge', 'reds_count_each_red_row_green_again_by_a_later_green_row_on_its_commit', 'review_counts_the_round_rows_of_each_pr', 'blocking_groups_reviewed_commits_and_ranks_prs', 'checks_read_each_reviewed_pr_in_full_and_sum_per_name', 'reader_strips_bom_and_cr_and_counts_physical_lines']
if case == 'root':
 path = base / 'relatorio.rs'
 text = read(path)
 expected = {('fn', 'run'), ('impl', 'Prepared'), ('fn', 'discover'), ('type', 'Row'), ('fn', 'not_a_release_name'), ('struct', 'Prepared')}
 assert expected <= definitions(text), str(path) + ": missing definitions " + str(expected - definitions(text))
 try: modules(text, module_names)
 except AssertionError as e: raise AssertionError(str(path) + ": " + str(e)) from e
elif case == 'selection':
 path = base / 'relatorio/selection.rs'
 text = read(path)
 expected = {('enum', 'Selection'), ('fn', 'matches'), ('impl', 'Selection')}
 assert expected <= definitions(text), str(path) + ": missing definitions " + str(expected - definitions(text))
elif case == 'git':
 path = base / 'relatorio/git.rs'
 text = read(path)
 expected = {('const', 'REPOSITORY_VARS'), ('fn', 'utf8'), ('impl', 'Git'), ('fn', 'unreadable'), ('fn', 'failure'), ('struct', 'Git')}
 assert expected <= definitions(text), str(path) + ": missing definitions " + str(expected - definitions(text))
elif case == 'evidence':
 path = base / 'relatorio/evidence.rs'
 text = read(path)
 expected = {('impl', 'Evidence'), ('fn', 'partial'), ('impl', 'Facts'), ('fn', 'days_from_civil'), ('fn', 'seconds'), ('fn', 'release_time'), ('struct', 'Evidence'), ('struct', 'Facts'), ('fn', 'fix_of_row'), ('fn', 'version_cmp'), ('struct', 'FixData'), ('fn', 'red_row'), ('fn', 'unix_time'), ('struct', 'Release')}
 assert expected <= definitions(text), str(path) + ": missing definitions " + str(expected - definitions(text))
elif case == 'dora':
 path = base / 'relatorio/dora.rs'
 text = read(path)
 expected = {('fn', 'dora'), ('fn', 'metric')}
 assert expected <= definitions(text), str(path) + ": missing definitions " + str(expected - definitions(text))
elif case == 'flow':
 path = base / 'relatorio/flow.rs'
 text = read(path)
 expected = {('struct', 'Merged'), ('struct', 'Report'), ('fn', 'lock_row'), ('fn', 'merge_row'), ('fn', 'read'), ('fn', 'merge_counts'), ('impl', 'Report')}
 assert expected <= definitions(text), str(path) + ": missing definitions " + str(expected - definitions(text))
elif case == 'quality':
 path = base / 'relatorio/quality.rs'
 text = read(path)
 expected = {('fn', 'review'), ('fn', 'size'), ('fn', 'round_pr'), ('fn', 'reds')}
 assert expected <= definitions(text), str(path) + ": missing definitions " + str(expected - definitions(text))
elif case == 'github':
 path = base / 'relatorio/github.rs'
 text = read(path)
 expected = {('fn', 'ask_github'), ('fn', 'reviewed_commits'), ('fn', 'reviewed_prs'), ('fn', 'checks'), ('fn', 'blocking'), ('fn', 'pr_of')}
 assert expected <= definitions(text), str(path) + ": missing definitions " + str(expected - definitions(text))
elif case == 'rows':
 path = base / 'relatorio/rows.rs'
 text = read(path)
 expected = {('fn', 'num'), ('fn', 'is'), ('fn', 'str_of'), ('fn', 'median'), ('fn', 'p90'), ('fn', 'stats'), ('fn', 'first'), ('fn', 'locks_of'), ('fn', 'at'), ('fn', 'first_row')}
 assert expected <= definitions(text), str(path) + ": missing definitions " + str(expected - definitions(text))
elif case == 'text':
 path = base / 'relatorio/text.rs'
 text = read(path)
 expected = {('fn', 'show_with'), ('fn', 'day'), ('fn', 'utc'), ('fn', 'dora_text'), ('fn', 'text'), ('fn', 'duration'), ('fn', 'civil'), ('fn', 'percent')}
 assert expected <= definitions(text), str(path) + ": missing definitions " + str(expected - definitions(text))
elif case == 'tests':
 path = base / 'relatorio/tests.rs'
 text = read(path)
 assert set(test_names) <= tests(text), str(path) + ": missing tests " + str(set(test_names) - tests(text))
elif case == 'contents':
 contents(base / 'relatorio', [Path(f).name for f in files[1:]])
elif case == 'unique':
 unique([base / f for f in files], table_names, test_names)
elif case == 'ceiling':
 ceiling(base / 'relatorio.rs')
 for p in contents(base / 'relatorio', [Path(f).name for f in files[1:]]): ceiling(p)
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
elif case == 'modules-control':
 p = cw / 'modules.rs'
 p.write_text('mod alpha;\npub(crate) mod beta;\npub(super) mod gamma;\n#[cfg(test)]\nmod tests;\n')
 modules(read(p), ['alpha','beta','gamma','tests'])
 for text in (' mod alpha;', 'pub mod alpha;', 'mod alphabet;', 'mod alpha; // comment'):
  p.write_text(text); rejects(lambda: modules(read(p), ['alpha']), 'alpha')
 for text in ('mod tests;', '#[cfg(test)]\n\nmod tests;', ' #[cfg(test)]\nmod tests;', '#[cfg(test)]\npub(crate) mod tests;'):
  p.write_text(text); rejects(lambda: modules(read(p), ['tests']), 'tests')
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
PY116
  pass
}
