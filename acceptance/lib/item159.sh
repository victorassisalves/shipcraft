# Item 159: public CLI, real local Git and pytest; no implementation reader.
item159_langs() { echo core; }
item159_cases() {
 local c
 for c in repro reason-missing reason-blank reason-multiline reason-bytes options reason-boundary without-lock uncommitted two-open old-format pending-tree pending-index pending-untracked after-green after-green-hook after-green-ci markdown redo-history root merge build-fails write-fails rollback log-fails git-fails alone-hook alone-ci edited-abandon later-delete later-edit squash format7-invalid report-head report-release report-merge control-first control-drops control-mixed control-handmade; do echo "v1-159.$c"; done
}
item159_case() {
 local lf='' oldhead=''
 EXPECT="item 159: ${CASE#v1-159.}"
 if [ "$CASE" = v1-159.squash ]; then
  # Same origin/PR/status/host-merge proof as item42.closed-ok.
  v1_start codex
  CFGS='execution|merge|"squash"'
  pr_main
  git checkout -qb feature/item159 || fail 'fixture checkout'
  L stub; i46_test invalid
  must_accept 'original squash RED' cmd shipcraft red
  lf=$(lock_files_tree)
  must_accept 'commit original squash RED' commit commit_all 'test: original RED'
  cat > textutil.py <<'STUB159'
DEFAULT_SEP = '-'
def slugify(text, sep):
    raise NotImplementedError
STUB159
  cat > tests/test_repair.py <<'TEST159'
from textutil import slugify, DEFAULT_SEP

def test_renamed():
    assert slugify('a b', DEFAULT_SEP) == 'a-b'

def test_keep():
    assert True
TEST159
  must_accept 'replace before proven squash' cmd shipcraft red --replace --reason 'squash evidence'
  must_accept 'commit replacement and both locks' commit commit_all 'test: replace RED'
  cat > textutil.py <<'GREEN159'
DEFAULT_SEP = '-'
def slugify(text, sep):
    return sep.join(text.split())
GREEN159
  must_accept 'GREEN closes replacement lock' commit commit_all 'feat: GREEN'
  pr_outside feature/item159
  git checkout -q main || fail 'fixture checkout main'
  seed_ok "$HEADSHA" shipcraft/ci
  seed_ok "$HEADSHA" shipcraft/review
  gh_quiet pr merge "$PRN" --squash >> "$LOG" 2>&1 || fail 'fixture host squash'
  git pull -q --no-rebase origin main >> "$LOG" 2>&1 || fail 'fixture pull squash'
  chk 'stub records merged PR proof' eq "$(H pr-field "$ST" "$PRN" state)" MERGED
  chk 'both locks arrive with no parent copy' "$PY" - "$BASE" "$lf" <<'ARRIVAL159'
import json,pathlib,subprocess,sys
base,old=sys.argv[1:]
locks=sorted(pathlib.Path('.shipcraft/locks').glob('*.json'))
assert len(locks)==2,locks
states={str(p):json.loads(p.read_text())['state'] for p in locks}
assert states[old]=='abandoned' and sorted(states.values())==['abandoned','closed'],states
for p in locks:
 r=subprocess.run(['git','ls-tree',base,'--',str(p)],capture_output=True)
 assert r.returncode==0 and r.stdout==b'',(p,r.stdout,r.stderr)
parent=subprocess.check_output(['git','show','-s','--format=%P','HEAD'],text=True).strip()
assert parent==base,(parent,base)
ARRIVAL159
  must_accept 'proven host squash admits abandoned and closed locks' cmd shipcraft ci --base "$BASE"
  pass; return
 fi
 i46_start
 must_accept 'item 159 contract' cmd "$PY" - "${CASE#v1-159.}" "$(command -v shipcraft)" "$lf" "$oldhead" "$BASE" "$CW" <<'PY159'
import hashlib,json,os,resource,shutil,signal,subprocess,sys
from pathlib import Path
case,binary,oldpath,redhead,base,cw=sys.argv[1:]
binary=str(Path(binary).resolve());old=Path(oldpath);cw=Path(cw)
original=old.read_bytes();contract=json.loads(original)
def run(*args):
 p=subprocess.run(list(map(str,args)),capture_output=True,timeout=90)
 print('$',repr(args),'rc',p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 return p
def ok(*args):
 p=run(*args);assert p.returncode==0,(args,p.returncode,p.stdout,p.stderr);return p.stdout
def git(*args):return ok('git',*args).decode().strip()
def put(p,s):
 p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(s if isinstance(s,bytes) else s.encode())
def locks():return {str(p):p.read_bytes() for p in sorted(old.parent.glob('*.json')) if p.is_file()}
def rows():
 p=Path('.git/shipcraft/runs.jsonl');return [json.loads(s) for s in p.read_text().splitlines()] if p.is_file() else []
def seal(d):
 d=dict(d);d['files']=dict(sorted(d['files'].items()));d['seal']=''
 d['seal']=hashlib.sha256(json.dumps(d,ensure_ascii=False,separators=(',',':')).encode()).hexdigest();return d
def save(p,d):put(p,json.dumps(seal(d),ensure_ascii=False,indent=2)+'\n')
def commit(message,bypass=False):
 git('add','-A');git('commit',*(['--no-verify'] if bypass else []),'-qm',message);return git('rev-parse','HEAD')
def repair():
 put('textutil.py',"DEFAULT_SEP = '-'\ndef slugify(text, sep):\n    raise NotImplementedError\n")
 put('tests/test_repair.py',"from textutil import slugify, DEFAULT_SEP\n\ndef test_renamed():\n    assert slugify('a b', DEFAULT_SEP) == 'a-b'\n\ndef test_keep():\n    assert True\n")
def implement():put('textutil.py',"DEFAULT_SEP = '-'\ndef slugify(text, sep):\n    return sep.join(text.split())\n")
def replacement(reason,*args):return run(binary,'red','--replace','--reason',reason,*args)
def row(before,layer,result,code,abandoned=None,new=None):
 rs=rows();assert len(rs)==len(before)+1 and rs[:-1]==before,rs
 r=rs[-1];assert (r['layer'],r['result'],r.get('code',''))==(layer,result,code),r
 if layer=='red':
  assert r.get('replace') is True and r.get('redo') is not True,r
  assert (r.get('kind'),r.get('reported_at'),r.get('fixes_release'))==('feature',None,None),r
  if abandoned is None:assert 'abandoned' not in r,r
  else:assert r.get('abandoned')==abandoned,r
  if new is None:assert r['lock']=='',r
  else:assert r.get('lock')==new,r
 return r
def refusal(p,code,layer='red'):
 assert p.returncode==1,(p.returncode,p.stdout,p.stderr)
 lines=(p.stdout+p.stderr).splitlines()[-3:]
 assert len(lines)==3 and all(l.startswith(k) for l,k in zip(lines,(b'shipcraft refused:',b'Why:',b'Next:'))),lines
 assert [r for r in rows() if r['layer']==layer][-1]['code']==code,rows()
 return lines
def handmade(reason):
 # Ordinary RED's public writer builds the new open lock, against the same base.
 old.unlink();parent=git('rev-parse','HEAD');git('update-ref','HEAD',base)
 ok(binary,'red');fresh=[Path(p) for p in locks()];assert len(fresh)==1,fresh
 new=fresh[0]
 if new==old:
  new=old.with_name('replacement159.json');old.rename(new)
 git('update-ref','HEAD',parent)
 d={k:contract[k] for k in ('format','state','files','cases','failing_at_red','controls','kind','reported_at','fixes_release')}
 d.update(format=7,state='abandoned',reason=reason);save(old,d)
 return new

def report():
 p=run(binary,'report','--json');assert p.returncode==0,(p.stdout,p.stderr)
 return [json.loads(s) for s in p.stdout.splitlines()]

def git_proxy(fault):
 real=shutil.which('git');tools=cw/'git159';tools.mkdir();hit=cw/'git159.hit';trace=cw/'git159.calls'
 proxy=tools/'git';proxy.write_text('#!'+sys.executable+'\nimport os,sys,json\nfrom pathlib import Path\na=sys.argv[1:]\nwith open('+repr(str(trace))+',"a") as f:f.write(json.dumps(a)+"\\n")\nif '+repr(fault)+' and ("log" in a or "rev-list" in a or "diff-tree" in a):\n Path('+repr(str(hit))+').touch();raise SystemExit(93)\nos.execv('+repr(real)+',['+repr(real)+',*a])\n');proxy.chmod(0o755)
 os.environ['PATH']=str(tools)+os.pathsep+os.environ['PATH']
 return hit,trace
def limit_to(size):
 def limited():
  signal.signal(signal.SIGXFSZ,signal.SIG_IGN);resource.setrlimit(resource.RLIMIT_FSIZE,(size,size))
 return limited

git('checkout','-qb','item159-fixture')

if case=='control-first':
 assert contract['format']==5 and contract['state']=='open',contract
 assert contract['seal']==seal(contract)['seal'] and len(contract['controls'])>=1,contract
 assert any('test_fixture' in s for s in contract['failing_at_red']),contract
 assert Path('textutil.py').read_bytes()==b'def slugify(text):\n    raise NotImplementedError\n'
 assert rows()[-2]['layer']=='red' or any(r['layer']=='red' and r['result']=='passed' for r in rows())
elif case=='control-drops':
 put('tests/test_repair.py',Path('tests/test_repair.py').read_text().replace('test_fixture','test_renamed'))
 p=run(binary,'red','--redo');lines=refusal(p,'redo-drops-case')
 put(cw/'redo-drops.bytes',b'\n'.join(lines)+b'\n')
 assert old.read_bytes()==original and rows()[-1]['redo'] is True
 assert lines==[
  f'shipcraft refused: the suite no longer has case(s) of lock {oldpath}: tests.test_repair::test_fixture'.encode(),
  b"Why: a redo repairs the RED's tests and keeps its contract: every case it locked stays locked",
  b"Next: keep every locked case in the suite and run `shipcraft red --redo` again; a repair that drops or renames a case means rewriting the branch's history"],lines
elif case=='control-mixed':
 put('tests/test_repair.py',Path('tests/test_repair.py').read_text().replace("fixture = 'invalid'","fixture = 'a b'"))
 # Keep all identities, derive a valid redo, then add the product stub in its commit.
 ok(binary,'red','--redo');put('textutil.py',Path('textutil.py').read_text()+'\n# stub interface repair\n')
 git('add','-A');p=run(binary,'check');lines=refusal(p,'redo-mixed','hook')
 put(cw/'redo-mixed.bytes',b'\n'.join(lines)+b'\n')
 assert lines==[
  f'shipcraft refused: the redo of lock {oldpath} in the pending commit also changes: textutil.py'.encode(),
  b"Why: a redo commit repairs only the RED's tests: product code, the config or a hook integration file in it would change the contract unjudged",
  b"Next: commit only the repaired tests and the lock `shipcraft red --redo` wrote; make the other changes in a commit of their own"],lines
elif case=='control-handmade':
 # Same ordinary writer and canonical sealing used by the manual-transition cases.
 new=handmade('fixture control');d=json.loads(old.read_text())
 assert d['format']==7 and d['reason']=='fixture control' and d['seal']==seal(d)['seal'],d
 old.unlink();git('update-ref','HEAD',base);git('add','-A')
 hit,trace=git_proxy(False)
 checked=subprocess.run([binary,'check'],capture_output=True,preexec_fn=limit_to(20000),timeout=90)
 print('limited control check',checked.returncode,repr(checked.stdout),repr(checked.stderr),flush=True)
 assert checked.returncode==0 and b'RED commit checked:' in checked.stdout+checked.stderr,(checked.stdout,checked.stderr)
 assert rows()[-1]['result']=='passed' and rows()[-1]['layer']=='hook',rows()[-1]
 assert trace.is_file() and not hit.exists() and any('rev-parse' in json.loads(l) for l in trace.read_text().splitlines())
 assert json.loads(new.read_text())['state']=='open'
elif case=='reason-missing':
 before=rows();files=locks();p=run(binary,'red','--replace')
 assert p.returncode==2 and b'shipcraft red [--redo | --replace --reason <text>] [--base <ref>] [--all] [--fix [--reported-at <time>] [--fixes-release <tag>]]' in p.stderr,(p.stdout,p.stderr)
 assert rows()==before and locks()==files
elif case=='reason-blank':
 before=rows();files=locks();p=replacement(' \t ')
 assert p.returncode==2 and b'[--redo | --replace --reason <text>]' in p.stderr,(p.stdout,p.stderr)
 assert rows()==before and locks()==files
elif case=='reason-multiline':
 for reason in ('first\nsecond','first\rsecond'):
  before=rows();files=locks();p=replacement(reason)
  assert p.returncode==2 and b'[--redo | --replace --reason <text>]' in p.stderr,(p.stdout,p.stderr)
  assert rows()==before and locks()==files
elif case=='reason-bytes':
 before=rows();files=locks();p=replacement('é'*150+'x')
 assert p.returncode==2 and b'[--redo | --replace --reason <text>]' in p.stderr,(p.stdout,p.stderr)
 assert rows()==before and locks()==files
elif case=='options':
 for args in (('--reason','why'),('--replace','--reason','why','--redo'),('--replace','--replace','--reason','why'),('--replace','--reason','why','--reason','twice')):
  before=rows();files=locks();p=run(binary,'red',*args)
  assert p.returncode==2 and b'[--redo | --replace --reason <text>]' in p.stderr,(p.stdout,p.stderr)
  assert rows()==before and locks()==files
elif case=='without-lock':
 git('reset','--hard',base);before=rows();p=replacement('no committed contract')
 lines=refusal(p,'replace-without-lock');row(before,'red','refused','replace-without-lock')
 assert lines[0]==b'shipcraft refused: HEAD holds no open lock: there is no committed RED to replace',lines
 assert not locks()
elif case=='uncommitted':
 git('update-ref','HEAD',base);before=rows();p=replacement('uncommitted contract')
 refusal(p,'replace-without-lock');row(before,'red','refused','replace-without-lock');assert old.read_bytes()==original
elif case=='two-open':
 put(old.with_name('second159.json'),original);commit('two open locks fixture',True)
 p=replacement('two contracts');refusal(p,'lock-open');assert len(locks())==2
elif case=='old-format':
 d=dict(contract);d['format']=4;d.pop('controls');save(old,d);commit('format 4 fixture',True);before=locks()
 p=replacement('old contract');refusal(p,'replace-old-format');assert locks()==before
elif case=='pending-tree':
 put(old,original+b' ');before=locks();p=replacement('dirty tree')
 refusal(p,'replace-pending');assert locks()==before and oldpath.encode() in p.stdout+p.stderr
elif case=='pending-index':
 put(old,original+b' ');git('add',oldpath);put(old,original);before=locks();p=replacement('dirty index')
 refusal(p,'replace-pending');assert locks()==before and oldpath.encode() in p.stdout+p.stderr
elif case=='pending-untracked':
 put(old.with_name('a159.json'),original);put(old.with_name('z159.json'),original);before=locks();p=replacement('untracked locks')
 refusal(p,'replace-pending');assert locks()==before
 s=p.stdout+p.stderr;assert s.index(b'a159.json')<s.index(b'z159.json'),s
elif case=='after-green':
 put('product159.txt','intermediate code');bad=commit('intermediate GREEN');before=rows();repair();p=replacement('renamed after code')
 refusal(p,'replace-after-green');row(before,'red','refused','replace-after-green',old.stem)
 assert bad.encode() in p.stdout+p.stderr and locks()=={oldpath:original}
 assert b'Why: once a GREEN committed code against this lock, a new contract written after it may fit that code' in p.stdout+p.stderr
elif case=='after-green-hook':
 put('product159.txt','intermediate code');bad=commit('intermediate GREEN');repair();handmade('late repair');git('add','-A')
 p=run(binary,'check');refusal(p,'replace-after-green','hook');assert bad.encode() in p.stdout+p.stderr
elif case=='after-green-ci':
 put('product159.txt','intermediate code');bad=commit('intermediate GREEN');repair();handmade('late repair');commit('handmade late replace',True)
 p=run(binary,'ci','--base',base);refusal(p,'replace-after-green','ci');assert bad.encode() in p.stdout+p.stderr
elif case=='markdown':
 put('history159.md','notes');commit('Markdown add');Path('history159.md').chmod(0o755);commit('Markdown mode');Path('history159.md').unlink();commit('Markdown delete')
 git('commit','--allow-empty','-qm','empty Markdown');repair();p=replacement('Markdown history allowed');assert p.returncode==0,(p.stdout,p.stderr)
 commit('replace after Markdown');implement();commit('GREEN');ok(binary,'ci','--base',base)
elif case=='redo-history':
 put('tests/test_repair.py',Path('tests/test_repair.py').read_text()+'\n# redo history\n');ok(binary,'red','--redo');commit('redo allowed');repair()
 p=replacement('redo history allowed');assert p.returncode==0,(p.stdout,p.stderr)
 commit('replace after redo');implement();commit('GREEN');ok(binary,'ci','--base',base)
elif case=='root':
 tree=git('rev-parse','HEAD^{tree}');root=ok('git','commit-tree',tree,'-m','root RED').decode().strip();git('update-ref','HEAD',root)
 repair();p=replacement('root RED');assert p.returncode==0,(p.stdout,p.stderr)
elif case=='merge':
 tree=git('rev-parse','HEAD^{tree}');other=git('commit-tree',tree,'-p',redhead,'-m','other');bad=git('commit-tree',tree,'-p',redhead,'-p',other,'-m','merge');git('update-ref','HEAD',bad)
 repair();p=replacement('after merge');refusal(p,'replace-after-green');assert bad.encode() in p.stdout+p.stderr and locks()=={oldpath:original}
 assert b'Why: once a GREEN committed code against this lock, a new contract written after it may fit that code' in p.stdout+p.stderr
elif case=='build-fails':
 repair();put('.shipcraft.toml',Path('.shipcraft.toml').read_text()+'\n[build]\ncommand="exit 23"\n');before=rows();p=replacement('build refuses')
 refusal(p,'build-failed');row(before,'red','refused','build-failed',old.stem);assert locks()=={oldpath:original}
elif case=='write-fails':
 repair();old.parent.chmod(0o555)
 try:p=replacement('write denied')
 finally:old.parent.chmod(0o755)
 assert p.returncode==2 and b'shipcraft: error: write ' in p.stderr,(p.returncode,p.stdout,p.stderr)
 assert rows()[-1]['result']=='error' and rows()[-1]['replace'] is True,rows()[-1]
 assert locks()=={oldpath:original}
elif case=='rollback':
 # A large old contract and a small new one put the two atomic writes on
 # opposite sides of a real OS file-size limit, without replacing owned paths.
 text=Path('tests/test_repair.py').read_text()
 for i in range(12):text+='\ndef test_control_'+str(i)+'_'+'x'*500+'():\n    assert True\n'
 put('tests/test_repair.py',text);ok(binary,'red','--redo');commit('large RED controls')
 original=old.read_bytes();contract=json.loads(original);repair()
 limit=len(original)//2;assert limit>4096
 p=subprocess.run([binary,'red','--replace','--reason','old rewrite exceeds file size limit'],capture_output=True,preexec_fn=limit_to(limit),timeout=90)
 print('limited replace',p.returncode,repr(p.stdout),repr(p.stderr),flush=True)
 refusal(p,'replace-write-failed');assert locks()=={oldpath:original},locks()
elif case=='log-fails':
 repair();log=Path('.git/shipcraft/runs.jsonl');log.unlink();log.mkdir();p=replacement('append failure')
 assert p.returncode==0,(p.stdout,p.stderr)
 assert json.loads(old.read_text())['state']=='abandoned' and len(locks())==2
elif case=='git-fails':
 repair();hit,trace=git_proxy(True)
 before=rows();p=replacement('git read failure')
 assert hit.exists() and p.returncode==2,(p.stdout,p.stderr)
 assert rows()[-1]['result']=='error' and rows()[-1]['replace'] is True and len(rows())==len(before)+1
 assert locks()=={oldpath:original}
elif case=='alone-hook':
 repair();new=handmade('alone');new.unlink();git('add','-A');p=run(binary,'check');refusal(p,'replace-alone','hook')
elif case=='alone-ci':
 repair();new=handmade('alone');new.unlink();commit('abandon alone',True);p=run(binary,'ci','--base',base);refusal(p,'replace-alone','ci')
elif case=='edited-abandon':
 repair();handmade('edited values');d=json.loads(old.read_text());d['cases'].append('invented159');save(old,d);git('add','-A')
 p=run(binary,'check');refusal(p,'lock-edited','hook')
 # This is also a format-7 reader case, not an old binary's generic edit verdict.
 assert b'newer shipcraft' not in p.stdout+p.stderr,(p.stdout,p.stderr)
elif case=='later-delete':
 repair();handmade('delete later');commit('replace fixture',True);old.unlink();git('add','-A');p=run(binary,'check')
 assert p.returncode==0,(p.stdout,p.stderr)
elif case=='later-edit':
 repair();handmade('sealed reason');commit('replace fixture',True);d=json.loads(old.read_text());d['reason']='changed later';save(old,d);git('add','-A')
 p=run(binary,'check');refusal(p,'lock-edited','hook');assert b'newer shipcraft' not in p.stdout+p.stderr,(p.stdout,p.stderr)
elif case=='format7-invalid':
 for defect in ('open','blank','multiline','bytes','extra','legacy-abandoned'):
  for p in old.parent.glob('*.json'):
   if p!=old:p.unlink()
  git('reset','--hard',redhead);repair();handmade('valid reason')
  d=json.loads(old.read_text())
  if defect=='open':d['state']='open'
  elif defect=='blank':d['reason']=' \t'
  elif defect=='multiline':d['reason']='one\rtwo'
  elif defect=='bytes':d['reason']='é'*151
  elif defect=='extra':d['unexpected']=False
  else:d['format']=5;d.pop('reason')
  save(old,d);git('add','-A');p=run(binary,'check');refusal(p,'lock-edited','hook')
  assert b'newer shipcraft' not in p.stdout+p.stderr,(defect,p.stdout,p.stderr)
elif case=='report-head':
 initial=next(r for r in report() if r.get('kind')=='lock' and r.get('lock')==old.stem)
 repair();handmade('report HEAD');commit('replace fixture',True);data=report();r=next(r for r in data if r.get('lock')==old.stem and r.get('kind')=='lock')
 assert r['state']=='abandoned' and list(r)==['change_kind','ci','close_at','close_to_merge','errors','first_review_approved','fixes_release','hook','kind','lock','merge_at','red_at','red_to_close','red_to_merge','redos','refusals','reported_at','reviews','state','unobserved','waiting'],r
 assert all(r[k]==initial[k] for k in ('red_at','close_at','change_kind','reported_at','fixes_release')),r
 assert any(r.get('kind')=='lock' and r.get('lock')!=old.stem for r in data),data
elif case=='report-release':
 repair();handmade('release report');commit('replace fixture',True);git('branch','-f','main','HEAD');git('tag','v159.0.0');old.unlink();commit('remove abandoned',True);git('branch','-f','main','HEAD')
 data=report();r=next(r for r in data if r.get('kind')=='lock' and r.get('lock')==old.stem);d=next(r for r in data if r.get('kind')=='dora')
 assert r['state']=='abandoned' and d['lead_time']['n']+d['lead_time']['missing']==1,(r,d)
 assert d['deploys']['n']==1 and d['time_to_recover']['n']==0 and d['rework_rate']['missing']==0 and d['rework_rate']['n']==1,(r,d)
elif case=='report-merge':
 repair();handmade('merge report');commit('replace fixture',True);git('branch','-f','main','HEAD');data=report();r=next(r for r in data if r.get('kind')=='lock' and r.get('lock')==old.stem);d=next(r for r in data if r.get('kind')=='dora')
 assert r['state']=='abandoned' and d['lead_time']['n']+d['lead_time']['missing']==1,(r,d)
 assert d['git']['deploy']=='merge' and d['time_to_recover']['n']==0,d
elif case=='reason-boundary':
 repair();reason=' \t'+'é'*148+' \t';assert len(reason.encode())==300
 before=rows();p=run(binary,'red','--all','--reason',reason,'--base',base,'--replace','--fix','--reported-at','2026-11-25T23:36:40-03:00','--fixes-release','v2.6.0')
 assert p.returncode==0,(p.stdout,p.stderr)
 d=json.loads(old.read_text());assert d['reason']==reason,d
 new=[Path(p) for p in locks() if p!=oldpath][0];n=json.loads(new.read_text());r=rows()[-1]
 assert (n['kind'],n['reported_at'],n['fixes_release'])==('fix','2026-11-25T23:36:40-03:00','v2.6.0'),n
 assert len(rows())==len(before)+1 and (r['replace'],r['abandoned'],r['lock'],r['kind'],r['reported_at'],r['fixes_release'])==(True,old.stem,new.stem,'fix','2026-11-25T23:36:40-03:00','v2.6.0'),r
elif case=='repro':
 repair();before=rows();reason='rename case and repair stub interface';p=replacement(reason)
 assert p.returncode==0,('replacement accepts renamed case and changed stub interface',p.stdout,p.stderr)
 paths=locks();assert len(paths)==2 and oldpath in paths,paths
 new=Path(next(p for p in paths if p!=oldpath));d=json.loads(old.read_text());n=json.loads(new.read_text())
 assert list(d)==['format','state','files','cases','failing_at_red','controls','kind','reported_at','fixes_release','reason','seal'],d
 assert (d['format'],d['state'],d['reason'])==(7,'abandoned',reason),d
 for k in ('files','cases','failing_at_red','controls','kind','reported_at','fixes_release'):assert d[k]==contract[k],(k,d,contract)
 assert d['seal']==seal(d)['seal'] and n['state']=='open' and n['format']==5,(d,n)
 assert any('test_renamed' in c for c in n['failing_at_red']) and not any('test_fixture' in c for c in n['cases']),n
 assert (n['kind'],n['reported_at'],n['fixes_release'])==('feature',None,None),n
 row(before,'red','passed','',old.stem,new.stem)
 lines=p.stdout.decode().splitlines();abandon=f'shipcraft: lock {oldpath} abandoned: {reason}'
 body=f'Replaces lock {old.stem}: {reason}'
 guidance='shipcraft: commit both locks with the tests and stubs in one commit, with this line in its body: '+body
 i=lines.index(abandon);assert lines[i-1].startswith(f'shipcraft: RED locked at {new}:') and lines[i+1]==guidance,lines
 commit('test: replace RED\n\n'+body);implement();commit('feat: GREEN for replacement')
 assert json.loads(old.read_text())==d and json.loads(new.read_text())['state']=='closed'
 ok(binary,'ci','--base',base)
else:raise AssertionError('unrouted item159 case: '+case)
PY159
 pass
}
