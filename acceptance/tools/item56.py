"""Item 56 fixtures and independent TOML/output assertions; real installed tsc."""
import json, pathlib, sys
import tomli
p = pathlib.Path('.')
mode = sys.argv[1]
def write(f, s):
    f=p/f; f.parent.mkdir(parents=True, exist_ok=True); f.write_text(s)
def config(f, d): write(f, json.dumps(d))
if len(sys.argv) > 2:
    d=tomli.loads(p.joinpath('.shipcraft.toml').read_text())
    out=pathlib.Path(sys.argv[2]).read_text()
    notices=[s for s in out.splitlines() if 'checks no file;' in s]
    suites=d.get('suite', [d])
    affected=mode in ('solution','empty-include','jsonc','jsonc-cr','jsonc-ls','jsonc-ps','untracked','workspace','control','build-fails','missing-reference')
    failed=mode in ('build-fails','missing-reference','untracked')
    covered_other=mode in ('extends','files','files-absent','files-null','include','include-null')
    for s in suites:
        solution=affected and (mode not in ('workspace','control') or s['root'] != 'packages/normal')
        if (solution and not failed) or covered_other:
            assert 'check' not in s, s
        else:
            assert s.get('check','').endswith('tsc --noEmit'), s
    if affected:
        assert ('build' in d) != failed, d
        s=next(s for s in suites if mode not in ('workspace','control') or s['root']!='packages/normal')
        path=(s.get('root','.')+'/tsconfig.json').removeprefix('./')
        name=s.get('name','default')
        def esc(x): return x.replace('\\','\\\\').replace('\n','\\n').replace('\r','\\r').replace('\t','\\t')
        suffix=(f'the check of suite {esc(name)} passes without checking: set check to the project\'s own type-check command' if failed else f'no check written for suite {esc(name)}: [build] type-checks its references')
        assert notices==[f'shipcraft: {esc(path)} checks no file; {suffix}'], (notices,out)
        build_lines=[i for i,line in enumerate(out.splitlines()) if '[build]' in line and 'checks no file;' not in line]
        if mode != 'untracked': assert build_lines, out
        assert all(i<out.splitlines().index(notices[0]) for i in build_lines), out
    else:
        assert not notices, notices
        if covered_other:
            expected='shipcraft: no check written for suite default: [build] type-checks tsconfig.json'
            assert 'build' in d, d
            assert [line for line in out.splitlines() if 'no check written for suite ' in line]==[expected], out
            lines=out.splitlines()
            build_at=next(i for i,line in enumerate(lines) if '[build]' in line and 'no check written' not in line)
            assert lines[build_at+1]==expected, out
    sys.exit()
root={'files':[], 'references':[{'path':'projects/real'}]}
real={'compilerOptions':{'composite':True,'types':[],'skipLibCheck':True,'outDir':'dist'},'files':['value.ts']}
config('projects/real/tsconfig.json',real)
write('projects/real/value.ts', 'export const value: number = '+('"bad"' if mode=='build-fails' else '1')+';')
if mode=='missing-reference': root['references']=[{'path':'missing'}]
if mode=='empty-include': root['include']=[]
if mode=='files': root['files']=['projects/real/value.ts']
if mode=='include': root['include']=['src']
if mode in ('extends','extends-null'):
    root['extends']='./base.json' if mode=='extends' else None
    config('base.json',{})
if mode=='references-absent': root.pop('references')
if mode=='references-empty': root['references']=[]
if mode in ('files-null','files-object','files-absent'):
    if mode=='files-absent': root.pop('files')
    else: root['files']=None if mode=='files-null' else {}
if mode in ('include-null','include-string'): root['include']=None if mode=='include-null' else 'src'
if mode in ('references-null','references-object'): root['references']=None if mode=='references-null' else {}
config('tsconfig.json',root)
if mode=='unparsable': write('tsconfig.json','{"files":[],"references":[}')
if mode=='nonobject': write('tsconfig.json','[]')
if mode=='jsonc':
    write('tsconfig.json','\ufeff// solution\r\n{ /* empty */ "files": [], "include": [], "references": [{"path":"projects/real",},],}\r\n')
if mode=='symlink':
    p.joinpath('tsconfig.json').rename('solution.json'); p.joinpath('tsconfig.json').symlink_to('solution.json')
if mode in ('workspace','control'):
    folder='packages/solution' if mode=='workspace' else 'packages/sol\tution'
    pkg=json.loads(p.joinpath('package.json').read_text()); pkg['workspaces']=['packages/*']; config('package.json',pkg)
    p.joinpath('tsconfig.json').unlink()
    for f in (folder,'packages/normal'):
        config(f+'/package.json',{'name':'solution' if f==folder else 'normal','private':True,'type':'module','devDependencies':{'vitest':'*'}})
        write(f+'/src/a.test.ts', 'import {it} from "vitest"; it("ok",()=>{});')
    root['references']=[{'path':'../../projects/real'}]
    config(folder+'/tsconfig.json',root)
    config('packages/normal/tsconfig.json',{'compilerOptions':{'types':[]},'include':['src']})

if mode in ('jsonc-cr','jsonc-ls','jsonc-ps'):
    sep={'jsonc-cr':'\r','jsonc-ls':'\u2028','jsonc-ps':'\u2029'}[mode]
    write('tsconfig.json','// solution'+sep+json.dumps(root))
