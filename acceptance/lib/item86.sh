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
PIN=item85['NEW']
MOVED='current block is not the pinned one: a line added on purpose goes in PIN in acceptance/lib/item86.sh'
if case=='exact-bare':
 assert clean_block(binary,False)==item85['variant'](PIN,False),MOVED
elif case=='exact-local':
 assert clean_block(binary,True)==item85['variant'](PIN,True),MOVED
else:raise AssertionError('unrouted case: '+case)
PY86
  pass
}
