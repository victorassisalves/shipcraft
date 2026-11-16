# Item 106: offline publication on item21's fixture; exact case routing.
item106_cases() {
  for c in mac-gap mac-survives-linux both-first list-bom macos linux prefer-macos first-linux pr-ignored sha-ignored bad-candidates huge-id mac-failed mac-missing mac-duplicate mac-denominator linux-failed linux-missing linux-duplicate linux-denominator unreadable-null unreadable-missing unreadable-scalar view-failed view-shapes ignored-names noncanonical-only empty list-failed list-malformed list-object list-null json-whitespace disabled-control cache-control protocol-control rollback fallback-red build-fails-control; do echo "v1-106.$c"; done
}
item106_case() {
  EXPECT='item 106: GitHub battery reuse for the pinned local build'
  must_accept 'item 106 public release contract' cmd "$PY" - "$ACEITE" "${CASE#v1-106.}" "$(command -v shipcraft)" <<'PY106'
import hashlib,json,os,re,shutil,sys,tarfile
from pathlib import Path
aceite,case,binary=sys.argv[1:]; aceite=Path(aceite).resolve()
scratch=Path(os.environ['TMPDIR'])/'item106-tools'; scratch.mkdir()
helper=(aceite/'tools/item21.py').read_text().split('\nif RELEASE:\n',1)[0]
fake=(aceite/'tools/item21_fake.py').read_text()
# Private extension: existing item21/37/78 tools and behavior stay untouched.
extension = """
if args[:2] == ['run','list']:
    assert option('-R') == 'github.com/equipe/shipcraft', args
    assert option('--workflow') == 'acceptance.yml' and option('--branch') == 'main', args
    assert option('--commit') == d['pinned'] and option('--limit') == '20', args
    assert option('--json') == 'databaseId,headSha,event,status,conclusion', args
    assert '--event' not in args, args
    if d['list_fail']: sys.exit(81)
    print(d['run_output']); sys.exit(0)
if args[:2] == ['run','view']:
    assert option('-R') == 'github.com/equipe/shipcraft' and option('--json') == 'jobs', args
    if args[2] in d['view_fail']: sys.exit(82)
    print(d['job_output'][args[2]]); sys.exit(0)
"""
assert fake.count("assert name == 'gh', name\n")==1
fake=fake.replace("assert name == 'gh', name\n", "assert name == 'gh', name\n"+extension)
(scratch/'item21_fake.py').write_text(fake); (scratch/'item21.py').write_text(helper)
sys.argv=[str(scratch/'item21.py'),'release-106',str(aceite.parent),binary]
ns={'__file__':str(scratch/'item21.py'),'__name__':'item106_fixture'}
exec(compile(helper,str(scratch/'item21.py'),'exec'),ns)
git=ns['git']; repo=ns['repo']; state=ns['state']; env=ns['env']; data=ns['data']; calls=ns['calls']; invoke=ns['invoke']
# Mock only the public cache boundary; its real users/reader are unchanged.
(repo/'acceptance/reuso.sh').write_text('acceptance_cached_result() {\n  printf \'%s\\n\' "$1|$2" >> "$I106_CACHE_PROBE"\n  [ "$SHIPCRAFT_ACCEPTANCE_REUSE" != 0 ] && [ "$I106_CACHE_HIT" = 1 ] || return 1\n  printf \'%s\\n\' \'106 of 106 cases pass (cache-control106)\'\n}\n')
git('add','acceptance/reuso.sh',cwd=repo); git('commit','-qm','cache boundary fixture',cwd=repo); git('push','-q','origin','main',cwd=repo)
pinned=git('rev-parse','HEAD',cwd=repo)
def row(i,**kw): return dict(dict(databaseId=i,headSha=pinned,event='schedule',status='completed',conclusion='success'),**kw)
def job(name,conclusion='success'): return dict(name=name,conclusion=conclusion)
def shards(platform,n): return [job(f'{platform} {k}/{n}') for k in range(1,n+1)]
rows=[]; jobs={}; raw_jobs={}; raw_list=None; list_fail=False; view_fail=[]; pretty=False
reuse='1'; cache_hit=False; release_case='release-comum'; take=None; platform=None; reason=None; control=None
if case=='mac-gap':
    rows=[row(731)]; jobs={'731':shards('macos',5)[1:]+shards('linux',2)}; take=731; platform='2 Linux shards'; views=['731']
elif case=='mac-survives-linux':
    rows=[row(731)]; jobs={'731':shards('macos',5)+[job('linux 1/2','failure')]}; take=731; platform='5 macOS shards'; views=['731']
elif case=='both-first':
    rows=[row(731),row(900)]; jobs={'731':shards('macos',5)+shards('linux',18),'900':shards('macos',5)}; take=731; platform='5 macOS shards'; views=['731']
elif case=='list-bom':
    raw_list='\ufeff[]'; reason='unreadable run list'; views=[]
elif case=='macos':
    rows=[row(731)]; jobs={'731': shards('macos',5)}; take=731; platform='5 macOS shards'; views=['731']
elif case=='linux':
    rows=[row(731,event='push')]; jobs={'731': shards('linux',18)}; take=731; platform='18 Linux shards'; views=['731']
elif case=='prefer-macos':
    rows=[row(900),row(611,event='workflow_dispatch'),row(500)]; jobs={'900':shards('linux',18),'611':shards('macos',5),'500':shards('macos',5)}; take=611; platform='5 macOS shards'; views=['900','611']
elif case=='first-linux':
    rows=[row(900),row(611)]; jobs={'900':shards('linux',3),'611':shards('linux',18)}; take=900; platform='3 Linux shards'; views=['900','611']
elif case=='pr-ignored':
    rows=[row(900,event='pull_request'),row(731)]; jobs={'900':shards('macos',5),'731':shards('linux',2)}; take=731; platform='2 Linux shards'; views=['731']
elif case=='sha-ignored':
    rows=[row(900,headSha='f'*40),row(731)]; jobs={'900':shards('macos',5),'731':shards('macos',5)}; take=731; platform='5 macOS shards'; views=['731']
elif case=='bad-candidates':
    rows=[None,42,{},row(True),row(0),row(-1),row(1.5),row('731'),row(900,event='release'),row(900,status='queued'),row(900,conclusion='failure'),row(900,headSha=pinned[:12]),row(900,event=None),row(731,extra={'ignored':True})]; jobs={'731':shards('macos',5)}; take=731; platform='5 macOS shards'; views=['731']
elif case=='huge-id':
    take=1234567890123456789012345678901234567890; rows=[row(take)]; jobs={str(take):shards('macos',5)}; platform='5 macOS shards'; views=[str(take)]
elif case=='mac-failed':
    rows=[row(731)]; jobs={'731':shards('macos',5)+shards('linux',2)}; jobs['731'][2]['conclusion']='failure'; take=731; platform='2 Linux shards'; views=['731']
elif case=='mac-missing':
    rows=[row(731)]; jobs={'731':shards('macos',4)+shards('linux',2)}; take=731; platform='2 Linux shards'; views=['731']
elif case=='mac-duplicate':
    rows=[row(731)]; jobs={'731':shards('macos',5)+[job('macos 1/5')]+shards('linux',2)}; take=731; platform='2 Linux shards'; views=['731']
elif case=='mac-denominator':
    rows=[row(731)]; jobs={'731':shards('macos',5)+[job('macos 1/6')]+shards('linux',2)}; take=731; platform='2 Linux shards'; views=['731']
elif case=='linux-failed':
    rows=[row(731)]; jobs={'731':shards('linux',3)}; jobs['731'][1]['conclusion']='cancelled'; reason='no green run of this commit'; views=['731']
elif case=='linux-missing':
    rows=[row(731)]; jobs={'731':shards('linux',3)[1:]}; reason='no green run of this commit'; views=['731']
elif case=='linux-duplicate':
    rows=[row(731)]; jobs={'731':shards('linux',3)+[job('linux 1/3')]}; reason='no green run of this commit'; views=['731']
elif case=='linux-denominator':
    rows=[row(731)]; jobs={'731':shards('linux',3)+[job('linux 1/4')]}; reason='no green run of this commit'; views=['731']
elif case=='unreadable-null':
    rows=[row(900),row(731)]; jobs={'900':shards('macos',5)+shards('linux',2)+[{'name':'scope','conclusion':None}],'731':shards('linux',1)}; take=731; platform='1 Linux shards'; views=['900','731']
elif case=='unreadable-missing':
    rows=[row(731)]; jobs={'731':shards('macos',5)+shards('linux',2)+[{'name':'build'}]}; reason='no green run of this commit'; views=['731']
elif case=='unreadable-scalar':
    rows=[row(731)]; jobs={'731':shards('macos',5)+shards('linux',2)+[42]}; reason='no green run of this commit'; views=['731']
elif case=='view-failed':
    rows=[row(900),row(731)]; jobs={'900':shards('macos',5),'731':shards('macos',5)}; view_fail=['900']; take=731; platform='5 macOS shards'; views=['900','731']
elif case=='view-shapes':
    rows=[row(900),row(800),row(700),row(600),row(731)]; raw_jobs={'900':'null','800':'[]','700':'{"jobs":{}}','600':'not JSON'}; jobs={'731':shards('macos',5)}; take=731; platform='5 macOS shards'; views=['900','800','700','600','731']
elif case=='ignored-names':
    rows=[row(731)]; jobs={'731':shards('macos',5)+[job(n,'failure') for n in ('build','scope','acceptance','macos 01/5','macos +1/5','macos 0/5','macos 1/05','macos 1/5 extra','linux 1/2\n')]}; take=731; platform='5 macOS shards'; views=['731']
elif case=='noncanonical-only':
    rows=[row(731)]; jobs={'731':[job('linux 0'+str(k)+'/03') for k in range(1,4)]}; reason='no green run of this commit'; views=['731']
elif case=='empty':
    rows=[]; reason='no green run of this commit'; views=[]
elif case=='list-failed':
    rows=[row(731)]; list_fail=True; reason='gh run list failed'; views=[]
elif case=='list-malformed':
    raw_list='[broken'; reason='unreadable run list'; views=[]
elif case=='list-object':
    raw_list='{}'; reason='unreadable run list'; views=[]
elif case=='list-null':
    raw_list='null'; reason='unreadable run list'; views=[]
elif case=='json-whitespace':
    rows=[row(731,extra='quoted \" and \u2028\u2029')]; jobs={'731':shards('linux',2)}; pretty=True; take=731; platform='2 Linux shards'; views=['731']
elif case=='disabled-control':
    rows=[row(731)]; jobs={'731':shards('macos',5)}; reuse='0'; views=[]; control='disabled'
elif case=='cache-control':
    rows=[row(731)]; jobs={'731':shards('macos',5)}; cache_hit=True; views=[]; control='cache'
elif case=='protocol-control':
    rows=[row(731)]; jobs={'731':shards('macos',5)}; reuse='0'; views=[]; control='protocol'
elif case=='rollback':
    rows=[row(731)]; jobs={'731':shards('macos',5)}; take=731; platform='5 macOS shards'; views=['731']; release_case='release-rollback'
elif case=='fallback-red':
    rows=[]; reason='no green run of this commit'; views=[]; release_case='release-bateria'
elif case=='build-fails-control':
    rows=[row(731)]; jobs={'731':shards('macos',5)}; views=[]; release_case='release-build'; control='build'
else: raise AssertionError('unrouted '+case)
env.update(SHIPCRAFT_ACCEPTANCE_REUSE=reuse,GH_HOST='enterprise.invalid',I106_CACHE_PROBE=str(scratch/'cache-probe'),I106_CACHE_HIT='1' if cache_hit else '0')
d=data(); d.update(case=release_case,pinned=pinned,list_fail=list_fail,view_fail=view_fail,
    run_output=raw_list if raw_list is not None else json.dumps(rows,indent=2 if pretty else None,ensure_ascii=False).replace('\n','\r\n'),
    job_output={**{k:json.dumps({'jobs':v}) for k,v in jobs.items()},**raw_jobs})
state.write_text(json.dumps(d))
if case=='protocol-control':
    # Prove the private fake's real gh JSON surface independently of new behavior.
    a=['run','list','-R','github.com/equipe/shipcraft','--workflow','acceptance.yml','--branch','main','--commit',pinned,'--json','databaseId,headSha,event,status,conclusion','--limit','20']
    q=ns['run']('gh',*a,env=env); assert json.loads(q.stdout)==rows
    q=ns['run']('gh','run','view','731','-R','github.com/equipe/shipcraft','--json','jobs',env=env); assert json.loads(q.stdout)=={'jobs':jobs['731']}
    d=data(); d['calls']=[]; state.write_text(json.dumps(d))
before=git('status','--porcelain','--untracked-files=all',cwd=repo)
cache=Path(env['HOME'])/'.cache/shipcraft-acceptance'
cache_before={str(p):p.read_bytes() for p in cache.rglob('*') if p.is_file()} if cache.exists() else {}
p=invoke('1.2.10','--local-build'); out=p.stdout+p.stderr
requests=calls('gh'); lookups=[c for c in requests if c['args'][:2]==['run','list']]
viewed=[c['args'][2] for c in requests if c['args'][:2]==['run','view']]
# Every expected result is assigned by the exact arm above, never by a helper.
if case=='disabled-control':
    assert not lookups and not viewed and len(calls('bateria'))==1, 'disabled path must run host battery once'
elif case=='protocol-control':
    assert not lookups and not viewed and len(calls('bateria'))==1, 'protocol control must still publish through disabled path'
elif case=='cache-control':
    assert not lookups and not viewed and not calls('bateria'), 'cache hit must win without GitHub or battery'
    assert 'battery reused for this tree' in out and 'cache-control106' in out, out
    assert (scratch/'cache-probe').read_text().strip().endswith('|HEAD'), 'cache boundary not reached'
elif case=='build-fails-control':
    assert not lookups and not viewed and not calls('bateria') and len(calls('cargo'))==1, 'lookup before completed builds'
else:
    assert len(lookups)==1, 'missing acceptance.yml lookup after local cache miss'
    assert viewed==views, ('wrong candidate order',viewed,views)
    timeline=data()['calls']; lookup_index=timeline.index(lookups[0])
    assert len([c for c in timeline[:lookup_index] if c['tool']=='cargo'])==2, 'lookup must follow both builds'
    assert (scratch/'cache-probe').read_text().strip().endswith('|HEAD'), 'lookup must follow cache miss'
    if take is not None:
        assert not calls('bateria'), 'reused proof ran a local battery/fixture'
        assert f'publish.sh: battery reused from GitHub: acceptance run {take} at {pinned}, {platform}' in out.splitlines(), out
        paragraphs=data()['notes'].strip().split('\n\n')
        assert paragraphs[0]==f'shipcraft 1.2.10, from commit {pinned}.', paragraphs
        battery=f'The whole battery (acceptance/run.sh all) ran green in GitHub acceptance run {take} at this commit, on {platform}, against a binary built there.\nBoth macOS targets were built here; the battery did not run against them.'
        if 'Linux' in platform: battery+='\nNo macOS battery ran for this commit.'
        assert paragraphs[1]==battery, paragraphs
        assert len(paragraphs)==3 and paragraphs[2]=='Install: run `install.sh` from the repository root (needs gh logged in).', paragraphs
        assert {str(p):p.read_bytes() for p in cache.rglob('*') if p.is_file()}==cache_before, 'reuse changed local acceptance cache'
        assert not any('acceptance/local' in ' '.join(c['args']) for c in requests), 'reuse published a local status'
    else:
        assert f'publish.sh: no GitHub battery to reuse ({reason}); running it here' in out.splitlines(), out
        assert len(calls('bateria'))==1 and calls('bateria')[0]['head']==pinned, 'fallback must run pinned battery once'
        assert 'aarch64-apple-darwin' in calls('bateria')[0]['binary'], 'fallback changed host target'
        assert 'battery reused from GitHub' not in out, out
if release_case in ('release-rollback','release-bateria','release-build'):
    ns['refused'](p); assert p.returncode==1
    if case=='rollback':
        assert data()['deleted'] and all('v1.2.10' in x or '321' in x for x in data()['deleted']), 'failed create must delete only owned release'
        assert any(c['args'][:2]==['release','create'] for c in requests), 'create failure not reached'
    else: ns['no_publish']()
else:
    assert p.returncode==0, out
    assert data()['target_commitish']==pinned, 'release target moved'
    assert f'publish.sh: v1.2.10 published at commit {pinned}: https://' in out, out
    assets={Path(a).name:Path(a) for a in data()['assets']}
    names=[f'shipcraft-1.2.10-{t}-apple-darwin.tar.gz' for t in ('aarch64','x86_64')]
    assert set(assets)==set(names+['SHA256SUMS']), assets
    sums=assets['SHA256SUMS'].read_text().splitlines(); assert len(sums)==2
    for name in names:
        with tarfile.open(assets[name]) as tf:
            members=tf.getmembers(); assert len(members)==1 and members[0].name in ('shipcraft','./shipcraft') and members[0].isfile()
            assert tf.extractfile(members[0]).read()==('#!/bin/sh\necho "shipcraft 1.2.10 ('+pinned[:12]+')"\n').encode(), 'not locally built bytes'
        assert any(re.fullmatch(hashlib.sha256(assets[name].read_bytes()).hexdigest()+r' [ *](?:\./)?'+re.escape(name),line) for line in sums)
assert f'publish.sh: v1.2.10 from commit {pinned}' in out, out
assert all(c['head']==pinned and c['cwd']!=str(repo) for c in calls('cargo')), 'build not pinned in fresh checkout'
assert git('status','--porcelain','--untracked-files=all',cwd=repo)==before, 'caller tree changed'
assert not list(Path(os.environ['TMPDIR']).glob('shipcraft-publish.*')), 'publish folder leaked'
assert all('-R' in c['args'] and c['args'][c['args'].index('-R')+1]=='github.com/equipe/shipcraft' for c in requests), 'gh repo not pinned'
PY106
  pass
}
