# E1 review: legacy config names refuse before any project command runs.
english_variants() {
  echo root-check root-filter execution-table roles-table review-table machine-table
  echo execution-review execution-timeout roles-review review-timeout
  echo pr-warn-lines pr-shape-lines
  echo suite-name suite-root suite-command suite-check suite-filter build-command
  echo quoted-check dotted-timeout inline-suite coexisting-check
}
english_cases() {
  local mode variant
  for mode in hook ci; do
    for variant in $(english_variants); do echo "e1-legacy-$mode-$variant"; done
    echo "e1-english-$mode"
  done
}
english_case() {
  local mode variant legacy old new
  case "$CASE" in
    e1-legacy-*) legacy=1; mode="${CASE#e1-legacy-}"; variant="${mode#*-}"; mode="${mode%%-*}" ;;
    *) legacy=0; mode="${CASE#e1-english-}"; variant=control ;;
  esac
  EXPECT="E1 config: $mode $variant"
  v1_start
  setup_init
  "$PY" - "$variant" "$CW" <<'PY_CONFIG'
import json, pathlib, shlex, sys
variant, cw = sys.argv[1:]
command = json.dumps('touch ' + shlex.quote(cw + '/judged') + '; exit 37')
runner = json.dumps('touch ' + shlex.quote(cw + '/runner') + '; exit 39')
sections = {
    'root': dict(lang='"python"', runner='"pytest"', test_command=runner,
                 test_globs='["tests/**"]', check=command, filter='"shipcraft"'),
    'execution': dict(ci='"local"', review='"local"', ci_timeout='17'),
    'roles': dict(review='"codex"'),
    'review': dict(spec='"verifica"', timeout='19'),
    'machine': dict(slots='1'),
    'pr': dict(warn_lines='23', shape_lines='29'),
    'suite': dict(name='"verifica filtra execucao comando"', root='"."', command=runner,
                  check=command, filter='"shipcraft"', globs='["tests/**"]'),
    'build': dict(command=json.dumps('touch ' + shlex.quote(cw + '/built'))),
}
variants = {
    'root-check': ('root', 'check', 'verifica'),
    'root-filter': ('root', 'filter', 'filtra'),
    'execution-table': ('execution', None, 'execucao'),
    'roles-table': ('roles', None, 'papeis'),
    'review-table': ('review', None, 'revisao'),
    'machine-table': ('machine', None, 'maquina'),
    'execution-review': ('execution', 'review', 'revisao'),
    'execution-timeout': ('execution', 'ci_timeout', 'tempo_max_ci'),
    'roles-review': ('roles', 'review', 'revisao'),
    'review-timeout': ('review', 'timeout', 'tempo_max'),
    'pr-warn-lines': ('pr', 'warn_lines', 'aviso_linhas'),
    'pr-shape-lines': ('pr', 'shape_lines', 'forma_linhas'),
    'suite-name': ('suite', 'name', 'nome'),
    'suite-root': ('suite', 'root', 'raiz'),
    'suite-command': ('suite', 'command', 'comando'),
    'suite-check': ('suite', 'check', 'verifica'),
    'suite-filter': ('suite', 'filter', 'filtra'),
    'build-command': ('build', 'command', 'comando'),
}
old = new = ''
if variant in variants:
    section, key, old_key = variants[variant]
    prefix = '' if section == 'root' or key is None else ('suite[0].' if section == 'suite' else section + '.')
    old, new = prefix + old_key, prefix + (key or section)
    if key is None:
        sections = {old_key if k == section else k: v for k, v in sections.items()}
    else:
        sections[section] = {old_key if k == key else k: v for k, v in sections[section].items()}
lines = ['# verifica, filtra, [execucao] and comando in comments are harmless.']
for section, fields in sections.items():
    if section != 'root': lines.append('[[suite]]' if section == 'suite' else '[' + section + ']')
    lines.extend(key + ' = ' + value for key, value in fields.items())
text = '\n'.join(lines) + '\n'
if variant == 'quoted-check':
    text = text.replace('check = ', '"verifica" = ', 1)
    old, new = 'verifica', 'check'
elif variant == 'dotted-timeout':
    text = text.replace('[execution]\nci = "local"\nreview = "local"\nci_timeout = 17\n', '')
    text = 'execution.ci = "local"\nexecution.review = "local"\nexecution.tempo_max_ci = 17\n' + text
    old, new = 'execution.tempo_max_ci', 'execution.ci_timeout'
elif variant == 'inline-suite':
    text = 'suite = [{ nome = "api", command = "true" }]\n' + text[:text.index('[[suite]]')] + '[build]\ncommand = "true"\n'
    old, new = 'suite[0].nome', 'suite[0].name'
elif variant == 'coexisting-check':
    text = 'verifica = "exit 0"\n' + text
    old, new = 'verifica', 'check'
pathlib.Path('.shipcraft.toml').write_text(text)
pathlib.Path(cw, 'legacy-fields').write_text(old + '|' + new + '\n')
PY_CONFIG
  [ $? -eq 0 ] || fail "fixture: config generation"
  git add .shipcraft.toml || fail "fixture: stage config"
  if [ "$mode" = ci ]; then
    must_accept "fixture: publish config without running hooks" commit git -c core.hooksPath="$CW/no-hooks" commit -q -m 'test: config input'
    run_cmd shipcraft ci --base HEAD
  else
    run_cmd shipcraft check
  fi
  if [ "$legacy" = 1 ]; then
    chk "legacy config refuses" rc_nonzero
    msg_check || fail "legacy config lacks refusal: $MSGERR"
    IFS='|' read -r old new < "$CW/legacy-fields"
    chk "refusal explains migration" grep -F -q "legacy config key" "$OUT.last3"
    chk "refusal names old key" grep -F -q "$old" "$OUT.last3"
    chk "refusal names replacement" grep -F -q "$new" "$OUT.last3"
    chk "legacy config uses config-invalid" eq "$(H jsonl-field .git/shipcraft/runs.jsonl "$mode" "$(head_rev)" code | tail -n 1)" '"config-invalid"'
    chk "project check did not run" test ! -e "$CW/judged"
    chk "runner did not run" test ! -e "$CW/runner"
    chk "build did not run" test ! -e "$CW/built"
  elif [ "$mode" = ci ]; then
    chk "English check executes and refuses" rc_nonzero
    chk "English project check ran" test -f "$CW/judged"
    chk "English check preserves its exit" last3_has '37'
  else
    chk "English config accepted by hook" rc_zero
  fi
  pass
}
