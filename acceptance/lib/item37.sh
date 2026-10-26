# Item 37: reuses only the offline sandbox of item 21.
item37_cases() {
  for c in release-comum release-prefixo release-preso; do echo "v1-37.$c"; done
}
item37_case() {
  EXPECT='packages for both targets hold only shipcraft, xattr on macOS included'
  must_accept 'item 37: tarfile and attribute on the tar entry' cmd "$PY" - "$ACEITE" "${CASE#v1-37.}" "$(command -v shipcraft)" <<'PY37'
import os
from pathlib import Path
import runpy
import shutil
import sys
import tempfile

aceite, case, binary = sys.argv[1:]
aceite = Path(aceite).resolve()
real_tar = shutil.which('tar')
# The copies are test tools only; release/ and item21 stay untouched.
with tempfile.TemporaryDirectory(prefix='item37-', dir=os.environ['TMPDIR']) as scratch:
    scratch = Path(scratch)
    probe = scratch / 'tar.jsonl'
    fake = (aceite / 'tools/item21_fake.py').read_text()
    needle = '    dest.chmod(0o755)\n'
    assert fake.count(needle) == 1, 'item21 sandbox changed: review the build probe'
    fake = fake.replace(needle, needle + '''    if sys.platform == 'darwin':
        try:
            subprocess.run(['/usr/bin/xattr','-w','com.shipcraft.aceite37','item37',str(dest)], check=True, capture_output=True)
            assert subprocess.check_output(['/usr/bin/xattr','-p','com.shipcraft.aceite37',str(dest)]).strip() == b'item37'
        except (OSError, AttributeError, subprocess.SubprocessError):
            pass
''')
    (scratch / 'item21_fake.py').write_text(fake)
    (scratch / 'item21.py').write_text((aceite / 'tools/item21.py').read_text())
    wrapper = scratch / 'tar'
    wrapper.write_text('#!' + sys.executable + '\n' + '''import json,os,sys,subprocess
from pathlib import Path
args=sys.argv[1:]
base=Path.cwd()
for i,a in enumerate(args[:-1]):
    if a == '-C':
        base=base / args[i+1]
paths=[base / a for a in args if a in ('shipcraft','./shipcraft')]
attrs=[]
for p in paths:
    try:
        attrs.append(subprocess.check_output(['/usr/bin/xattr','-p','com.shipcraft.aceite37',str(p)],stderr=subprocess.DEVNULL).strip() == b'item37')
    except (OSError,AttributeError,subprocess.SubprocessError):
        attrs.append(False)
with open(os.environ['I37_PROBE'],'a') as f:
    f.write(json.dumps(dict(args=args,paths=list(map(str,paths)),attrs=attrs))+'\\n')
os.execv(os.environ['I37_TAR'],[os.environ['I37_TAR'],*args])
''')
    wrapper.chmod(0o755)
    os.environ.update(PATH=str(scratch)+os.pathsep+os.environ['PATH'],
                      I37_PROBE=str(probe), I37_TAR=real_tar)
    sys.argv = [str(scratch / 'item21.py'), case, str(aceite.parent), binary]
    import json
    import tarfile
    original_open = tarfile.open
    def checked_open(*args, **kwargs):
        tf = original_open(*args, **kwargs)
        print('item37 tarfile:', Path(args[0]).name,
              [m.name for m in tf.getmembers()], flush=True)
        return tf
    tarfile.open = checked_open
    try:
        runpy.run_path(str(scratch / 'item21.py'), run_name='__main__')
    finally:
        rows = [json.loads(s) for s in probe.read_text().splitlines()] if probe.exists() else []
        exercised = sys.platform == 'darwin' and real_tar == '/usr/bin/tar' and sum(any(r['attrs']) for r in rows) == 2
        print('item37: attribute checked on the entry of both packages' if exercised else
              'item37: defect not exercised on this machine; tarfile check kept', flush=True)
PY37
  pass
}
