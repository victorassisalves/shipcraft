# Item 118; spec commit 3aed92f. Structural reads only; no product invocation.
item118_langs() { echo core; }
item118_cases() {
  local c
  for c in root suites paths reading execution roles review pr report version tests contents unique ceiling definitions-control modules-control tests-control contents-control ceiling-control read-control unique-control; do
    echo "v1-118.$c"
  done
}
item118_case() {
  EXPECT="item 118: ${CASE#v1-118.}"
  must_accept 'item 118 static contract' cmd "$PY" - "${CASE#v1-118.}" "$ACEITE/.." "$CW" <<'PY118'
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
files = ['config.rs', 'config/suites.rs', 'config/paths.rs', 'config/reading.rs', 'config/execution.rs', 'config/roles.rs', 'config/review.rs', 'config/pr.rs', 'config/report.rs', 'config/version.rs', 'config/tests.rs']
module_names = ['suites', 'paths', 'reading', 'execution', 'roles', 'review', 'pr', 'report', 'version', 'tests']
table_names = ['CONFIG_FILE', 'VERSION', 'reject_legacy_file', 'Config', 'no_config', 'Suite', 'Filtra', 'suite_names', 'owner', 'Build', 'dot', 'normal_path', 'normal_form', 'normal_glob', 'normal_globs', 'invalid', 'check_legacy_keys', 'legacy_keys', 'not_toml', 'Execucao', 'Maquina', 'Camada', 'camada', 'any_value', 'check_execution', 'check_suite_checks', 'PapeisRaw', 'Papel', 'Papeis', 'ROLE_AGENTS', 'ROLES_MIN', 'check_roles', 'role', 'shape', 'role_invalid', 'a_type', 'escaped', 'quoted', 'Revisao', 'check_retry_wait', 'check_review_after', 'check_review_guide', 'Pr', 'NewDependencies', 'DependencyDays', 'report_release_tags', 'report_invalid', 'check_report', 'minimum_version', 'min_reaches', 'check_min', 'version_parts']
test_names = ['legacy_document_keys_refuse_before_deserialization', 'english_config_keys_reach_their_consumers', 'new_dependencies_and_their_days_are_checked', 'raiz_and_globs_are_normalized_once', 'absolute_or_parent_paths_and_empty_globs_are_invalid', 'not_toml_or_a_suite_without_comando_is_a_refusal', 'role_checks_come_after_the_existing_refusals', 'suite_checks_need_github_ci_and_a_2_18_minimum', 'retry_wait_defaults_to_120_and_any_explicit_value_needs_2_41', 'report_release_tags_is_validated_in_order', 'review_after_defaults_to_ci_and_any_explicit_value_needs_2_46']
if case == 'root':
 path = base / 'config.rs'
 text = read(path)
 expected = {('fn', 'no_config'), ('impl', 'Config'), ('struct', 'Config'), ('const', 'CONFIG_FILE'), ('fn', 'reject_legacy_file'), ('const', 'VERSION')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
 try: modules(text, module_names)
 except AssertionError as e: raise AssertionError(str(path) + ': ' + str(e)) from e
elif case == 'suites':
 path = base / 'config/suites.rs'
 text = read(path)
 expected = {('fn', 'dot'), ('fn', 'owner'), ('fn', 'suite_names'), ('impl', 'Suite'), ('enum', 'Filtra'), ('struct', 'Build'), ('struct', 'Suite')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'paths':
 path = base / 'config/paths.rs'
 text = read(path)
 expected = {('fn', 'normal_globs'), ('fn', 'normal_form'), ('fn', 'normal_path'), ('fn', 'invalid'), ('fn', 'normal_glob')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'reading':
 path = base / 'config/reading.rs'
 text = read(path)
 expected = {('fn', 'not_toml'), ('fn', 'check_legacy_keys'), ('fn', 'legacy_keys')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'execution':
 path = base / 'config/execution.rs'
 text = read(path)
 expected = {('struct', 'Execucao'), ('fn', 'camada'), ('fn', 'any_value'), ('fn', 'check_execution'), ('fn', 'check_suite_checks'), ('struct', 'Maquina'), ('enum', 'Camada')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'roles':
 path = base / 'config/roles.rs'
 text = read(path)
 expected = {('struct', 'Papeis'), ('fn', 'role_invalid'), ('const', 'ROLES_MIN'), ('const', 'ROLE_AGENTS'), ('fn', 'role'), ('fn', 'a_type'), ('fn', 'quoted'), ('fn', 'escaped'), ('impl', 'Papel'), ('fn', 'shape'), ('struct', 'PapeisRaw'), ('struct', 'Papel'), ('fn', 'check_roles')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'review':
 path = base / 'config/review.rs'
 text = read(path)
 expected = {('fn', 'check_retry_wait'), ('fn', 'check_review_after'), ('fn', 'check_review_guide'), ('struct', 'Revisao')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'pr':
 path = base / 'config/pr.rs'
 text = read(path)
 expected = {('struct', 'Pr'), ('enum', 'NewDependencies'), ('struct', 'DependencyDays')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'report':
 path = base / 'config/report.rs'
 text = read(path)
 expected = {('fn', 'report_release_tags'), ('fn', 'report_invalid'), ('fn', 'check_report')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'version':
 path = base / 'config/version.rs'
 text = read(path)
 expected = {('fn', 'min_reaches'), ('fn', 'check_min'), ('fn', 'version_parts'), ('fn', 'minimum_version')}
 assert expected <= definitions(text), str(path) + ': missing definitions ' + str(expected - definitions(text))
elif case == 'tests':
 path = base / 'config/tests.rs'
 text = read(path)
 assert set(test_names) <= tests(text), str(path) + ': missing attributed tests ' + str(set(test_names) - tests(text))
elif case == 'contents':
 contents(base / 'config', [Path(f).name for f in files[1:]])
elif case == 'unique':
 unique([base / f for f in files], table_names, test_names)
elif case == 'ceiling':
 ceiling(base / 'config.rs')
 for p in contents(base / 'config', [Path(f).name for f in files[1:]]): ceiling(p)
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
 p.write_text("pub(super) struct PapeisRaw {\n    normal_glob: (),\n}\nimpl Config {\n    fn normal_glob() {}\n}\nfn normal_globs() {}\nimpl Default for Pr {\n}\nimpl<'de> Deserialize<'de> for DependencyDays {\n}\npub use suites::{Filtra, Suite};\n")
 assert definitions(read(p)) == {('struct', 'PapeisRaw'), ('impl', 'Config'), ('fn', 'normal_globs'), ('impl', 'Default')}
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
PY118
  pass
}
