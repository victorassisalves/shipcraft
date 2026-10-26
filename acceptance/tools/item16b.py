#!/usr/bin/env python3
"""Real npm/TypeScript fixtures; never fakes the compiler output."""
import json, pathlib, sys
p = pathlib.Path('.')
mode = sys.argv[1]
def write(path, value):
    f = p / path
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(value, encoding='utf-8')
def config(folder='.', signal='composite'):
    d = {'compilerOptions': {'target':'es2022','module':'esnext','moduleResolution':'bundler','types':[], 'skipLibCheck':True, 'outDir':'dist'}, 'files':['value.ts']}
    if signal == 'composite': d['compilerOptions']['composite'] = True
    if signal == 'references': d['references'] = []
    write(f'{folder}/tsconfig.json', json.dumps(d))
    write(f'{folder}/value.ts', 'export const value: number = 1;\n')
def pkg(folder):
    write(f'{folder}/package.json', json.dumps({'name':folder.replace('/','-'),'private':True,'type':'module'}))
    config(folder)
def ws(globs, style='list'):
    d = json.loads((p/'package.json').read_text())
    d['workspaces'] = {'packages':globs} if style == 'object' else globs
    write('package.json',json.dumps(d))
config()
expected = ['.']
negative = ''
if mode.startswith(('invalid-comment-', 'invalid-string-', 'invalid-garbage-', 'invalid-comma-', 'jsonc-closed-')):
    target = '.' if mode.endswith('-root') else 'packages/broken'
    if target != '.':
        pkg(target)
        ws(['packages/*'])
        config(target, signal='none')
    raw = (p / target / 'tsconfig.json').read_text()
    if mode.startswith('invalid-comment-'): raw += ' /* unfinished'
    elif mode.startswith('invalid-string-'): raw = raw[:-1] + ', "exclude": ["unfinished'
    elif mode.startswith('invalid-garbage-'): raw += ' x'
    elif mode.startswith('invalid-comma-'): raw = '{,' + raw[1:]
    else: raw += ' /* unfinished */'
    write(f'{target}/tsconfig.json', raw)
    if mode.startswith('invalid-'):
        negative = f'{target}/tsconfig.json'.removeprefix('./')
        expected = []
elif mode in ('shell-space', 'shell-quotes'):
    folders = ['packages/api client'] if mode == 'shell-space' else ["packages/a' client", 'packages/b"client', 'packages/z$HOME;literal']
    config(signal='none')
    for folder in folders: pkg(folder)
    ws(['packages/*'])
    expected = sorted(folders)
elif mode in ('yaml-mapping', 'yaml-null', 'yaml-text', 'yaml-number', 'workspace-null', 'yarn-null'):
    if mode.startswith('yaml-'):
        write('pnpm-workspace.yaml', {'yaml-mapping': 'packages:\n  packages: ["packages/*"]\n', 'yaml-null': 'packages: null\n', 'yaml-text': 'packages: "packages/*" # texto não é lista\n', 'yaml-number': 'packages: 42\n'}[mode])
        negative = 'pnpm-workspace.yaml'
    else:
        ws(None, 'object' if mode == 'yarn-null' else 'list')
        negative = 'package.json'
    expected = []
elif mode in ('jsonc-ls', 'jsonc-ps'):
    raw = (p/'tsconfig.json').read_text()
    write('tsconfig.json', '// comentário' + ('\u2028' if mode == 'jsonc-ls' else '\u2029') + raw)
elif mode == 'references': config(signal='references')
elif mode in ('jsonc-comments','jsonc-bom-crlf','jsonc-bom','jsonc-crlf','jsonc-cr','jsonc-string'):
    raw = (p/'tsconfig.json').read_text()
    if mode == 'jsonc-comments': raw = '// início\n' + raw[:-1] + ', /* fim */ }'
    elif mode == 'jsonc-bom-crlf': raw = '\ufeff// início\r\n' + raw[:-1] + ',\r\n}'
    elif mode == 'jsonc-bom': raw = '\ufeff' + raw
    elif mode == 'jsonc-crlf': raw = '// início\r\n' + raw[:-1] + ',\r\n}'
    elif mode == 'jsonc-cr': raw = '// início\r' + raw[:-1] + ',\r}'
    else: raw = raw[:-1] + ',"exclude":["http://host/*literal*/",],}'
    write('tsconfig.json',raw)
elif mode in ('absent','extends','nested-key','composite-false','untracked-root'):
    negative='silent'; expected=[]
    config(signal='none')
    if mode == 'extends':
        write('base.json','{"compilerOptions":{"composite":true}}')
        d=json.loads((p/'tsconfig.json').read_text()); d['extends']='./base.json'; write('tsconfig.json',json.dumps(d))
    elif mode == 'nested-key':
        write('tsconfig.json','{"files":["value.ts"],"compilerOptions":{"types":[]},"x":{"references":[],"compilerOptions":{"composite":true}}}')
    elif mode == 'composite-false':
        d=json.loads((p/'tsconfig.json').read_text()); d['compilerOptions']['composite']=False; write('tsconfig.json',json.dumps(d))
    elif mode == 'untracked-root': config()
elif mode in ('invalid-root','invalid-package'):
    target='.' if mode == 'invalid-root' else 'packages/broken'
    if target != '.': pkg(target); ws(['packages/*'])
    write(f'{target}/tsconfig.json','{"compilerOptions": { nope }')
    negative=f'{target}/tsconfig.json'.removeprefix('./'); expected=[]
elif mode.startswith('build-'):
    if mode == 'build-type': write('value.ts','export const value: number = "wrong";\n')
    elif mode == 'build-reference': write('tsconfig.json','{"files":[],"references":[{"path":"missing"}]}')
    negative='build'; expected=[]
else:
    globs=['packages/*']; folders=['packages/zeta','packages/alpha']; style='list'
    if mode == 'yarn-object': style='object'
    elif mode == 'star-boundary': folders += ['packages/deep/hidden']
    elif mode == 'name-star': globs=['packages/pre*end']; folders=['packages/preend','packages/pre-middle-end','packages/pre/deep/end','packages/nope']
    elif mode == 'question': globs=['packages/p?']; folders=['packages/pa','packages/pb','packages/pabc','packages/p/deep']
    elif mode == 'star-middle': globs=['packages/*/lib']; folders=['packages/a/lib','packages/b/lib','packages/a/deep/lib']
    elif mode == 'double-middle': globs=['packages/**/lib']; folders=['packages/lib','packages/a/lib','packages/a/b/lib','packages/nope']
    elif mode == 'double-start': globs=['**/lib']; folders=['lib','packages/a/lib','packages/a/b/lib','packages/nope']
    elif mode == 'exclude': globs=['packages/**','!packages/skip/**']; folders=['packages/yes','packages/skip/a']
    elif mode == 'exclude-first': globs=['!packages/skip*','packages/*']; folders=['packages/yes','packages/skipme']
    elif mode == 'untracked-package': folders=['packages/alpha','packages/untracked']
    elif mode == 'untracked-config': folders=['packages/alpha','packages/untracked']
    elif mode in ('package-only','package-references','both-manifests','outside-invalid'): folders=['packages/alpha']
    elif mode.startswith('unknown-'):
        globs=['packages/*', {'brace':'packages/{a,b}','bracket':'packages/[ab]','plus':'packages/+(a)','at':'packages/@(a)','bang':'packages/!(a)'}[mode[8:]]]
        negative=globs[-1]; expected=[]
    for folder in folders: pkg(folder)
    ws(globs,style)
    if mode in ('package-only','package-references'):
        config(signal='none')
        if mode == 'package-references': config('packages/alpha',signal='references')
    if mode == 'both-manifests':
        pkg('modules/beta'); write('pnpm-workspace.yaml', "packages: ['modules/*']\n")
    if mode == 'outside-invalid':
        pkg('outside/broken'); write('outside/broken/tsconfig.json','invalid JSONC')
    chosen=folders[:]
    if mode in ('star-boundary','name-star'): chosen=folders[:2]
    elif mode == 'question': chosen=folders[:2]
    elif mode == 'star-middle': chosen=folders[:2]
    elif mode in ('double-middle','double-start'): chosen=folders[:3]
    elif mode in ('exclude','exclude-first'): chosen=folders[:1]
    elif mode in ('untracked-package','untracked-config'): chosen=folders[:1]
    if not negative: expected=sorted(['.']+chosen)
    if mode in ('package-only','package-references'): expected=chosen
    if mode == 'both-manifests': expected=sorted(expected+['modules/beta'])
    if mode.startswith('yaml-'):
        d=json.loads((p/'package.json').read_text()); d.pop('workspaces'); write('package.json',json.dumps(d))
        yaml={'yaml-block':"packages:\n  # comentário\n  - 'packages/*'\n",'yaml-flow':"{packages: ['packages/*']} # comentário\n",'yaml-multiline':"packages: [\n 'packages/*',\n]\n",'yaml-alias':"patterns: &pkgs ['packages/*']\npackages: *pkgs\n",'yaml-unknown':"packages: ['packages/*', 'modules/[ab]']\n",'yaml-invalid':'packages: [\n', 'yaml-nontext':'packages: [packages/*, 7]\n'}[mode]
        write('pnpm-workspace.yaml',yaml)
        if mode in ('yaml-invalid','yaml-nontext'): negative='pnpm-workspace.yaml'; expected=[]
        if mode == 'yaml-unknown': negative='modules/[ab]'; expected=[]
    elif mode == 'workspace-json':
        write('package.json','{"workspaces": ['); negative='package.json'; expected=[]
    elif mode in ('workspace-invalid','workspace-nontext','yarn-nontext'):
        d=json.loads((p/'package.json').read_text())
        d['workspaces']=42 if mode=='workspace-invalid' else (["packages/*",7] if mode=='workspace-nontext' else {'packages':['packages/*',False]})
        write('package.json',json.dumps(d)); negative='package.json'; expected=[]
write('.gitignore', 'node_modules/\n**/dist/\n**/*.tsbuildinfo\n')
# Outside the tree, so the expectations are not product input.
pathlib.Path(sys.argv[2]).write_text(' '.join(expected))
pathlib.Path(sys.argv[3]).write_text(negative)

pathlib.Path(sys.argv[2] + '.json').write_text(json.dumps(expected))
