# Item 86: the one byte-for-byte pin of the current AGENTS block, in both variants.
# An item that adds a block line adds it to PIN here, in one line; no older test file changes.
item86_langs() { echo core; }
item86_cases() {
  local c
  for c in exact-bare exact-local; do echo "v1-86.$c"; done
}
item86_case() {
  EXPECT="item 86: ${CASE#v1-86.}"
  v1_start codex
  must_accept 'item 86 block pin' cmd "$PY" - "${CASE#v1-86.}" "$(command -v shipcraft)" "$ACEITE" <<'PY86'
import ast,sys
from pathlib import Path
case,binary,acceptance=sys.argv[1:];binary=str(Path(binary).resolve())
def load(item,marker,names,functions):
 # Fixture constants and functions only, never that file's test execution.
 source=(Path(acceptance)/'lib'/item).read_text().split("<<'"+marker+"'\n",1)[1].split('\n'+marker,1)[0];ns={}
 for node in ast.parse(source).body:
  if isinstance(node,ast.Assign) and {t.id for t in node.targets if isinstance(t,ast.Name)}<=names and all(isinstance(t,ast.Name) for t in node.targets):exec(compile(ast.Module(body=[node],type_ignores=[]),item,'exec'),ns)
  elif isinstance(node,ast.FunctionDef) and node.name in functions:exec(compile(ast.Module(body=[node],type_ignores=[]),item,'exec'),ns)
 return ns
item85=load('item85.sh','PY85',{'OLD84','ROOT_LINE','CLEANUP','NEW'},{'variant'})
clean_block=load('item61.sh','PY61',set(),{'clean_block'})['clean_block']
# The block this version writes: item 85's frozen bytes, plus each later block line right here.
PIN=item85['NEW'].replace(b'- A behavior change:',b"- To contribute to a project that does not use Shipcraft (its default branch has no `.shipcraft.toml` or `.sc2.toml`), open the PR from the branch `shipcraft export --base <base> <new branch>` writes once the lock is closed and `shipcraft ci --base <base>` passes on this branch: it leaves out Shipcraft's files and this block, and the project's own checks still apply to it. `shipcraft pr` is for projects that use Shipcraft.\n"+b'- A behavior change:',1).replace(b'- Start each phase with the agent, model and effort', b"- Before starting either phase, the session the user talks to fixes the interface the tests call (what they call to reach the behavior: names, arguments, results, and the errors, exit codes or messages they check; for a command line, its commands, flags and output) and writes it in every prompt that starts a phase, a command given to the user included. The RED's tests and stubs use that interface; the GREEN never changes it (the code behind it is free), and a GREEN that finds it wrong stops and reports it as a wrong test: the repair above, with the corrected interface in the new RED's prompt and the GREEN's, through `shipcraft red --redo` and its limits.\n"+b'- Start each phase with the agent, model and effort',1).replace(b'- Start each phase with the agent, model and effort',b"- If the repair renames or drops a case, or changes a stub, and no GREEN commit exists after the RED (only redo commits and commits that change only Markdown files), the new RED session runs `shipcraft red --replace --reason '<why>'` instead of `shipcraft red --redo` (also in the steps given to the user, with both lock paths it prints in `git add`), commits both locks with the tests and stubs in one commit, and puts the line it prints in the commit body; this takes precedence over the repair above. After a GREEN commit, `--replace` refuses: repair with `--redo` or open the new RED on a new branch.\n"+b'- Start each phase with the agent, model and effort',1)
REPLACE_LINE=b"- If the repair renames or drops a case, or changes a stub, and no GREEN commit exists after the RED (only redo commits and commits that change only Markdown files), the new RED session runs `shipcraft red --replace --reason '<why>'` instead of `shipcraft red --redo` (also in the steps given to the user, with both lock paths it prints in `git add`), commits both locks with the tests and stubs in one commit, and puts the line it prints in the commit body; this takes precedence over the repair above. After a GREEN commit, `--replace` refuses: repair with `--redo` or open the new RED on a new branch.\n"
MOVED='current block is not the pinned one: a line added on purpose goes in PIN in acceptance/lib/item86.sh'
if case=='exact-bare':
 assert clean_block(binary,False)==item85['variant'](PIN,False),MOVED
elif case=='exact-local':
 assert clean_block(binary,True)==item85['variant'](PIN,True),MOVED
else:raise AssertionError('unrouted case: '+case)
PY86
  pass
}
