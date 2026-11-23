use super::*;

fn suite(raiz: &str, comando: &str) -> Suite {
    let text = format!("[[suite]]\nroot = \"{raiz}\"\ncommand = \"{comando}\"\nglobs = [\"**/*.test.js\"]\n");
    Config::parse(&text).unwrap().suites().remove(0)
}

fn strings(list: &[&str]) -> Vec<String> {
    list.iter().map(|p| p.to_string()).collect()
}

/// A git repository with `files` added to the index.
fn repo_with(files: &[(&str, &str)]) -> (crate::git::TempDir, Repo) {
    let dir = crate::git::TempDir::new("shipcraft-jest-files-").unwrap();
    assert!(crate::git::git_in(dir.path(), &["init", "-q"]).unwrap().status.success());
    for (path, text) in files {
        let full = dir.path().join(path);
        fs::create_dir_all(full.parent().unwrap()).unwrap();
        fs::write(full, text).unwrap();
    }
    assert!(crate::git::git_in(dir.path(), &["add", "-A"]).unwrap().status.success());
    let repo = Repo::at_root(dir.path());
    (dir, repo)
}

/// The discovery of a root `jest` suite (or `config`) on `files`.
fn found_in(config: &str, files: &[(&str, &str)]) -> (Vec<String>, Option<(String, String)>) {
    let config = Config::parse(config).unwrap();
    let (_dir, repo) = repo_with(files);
    let found = discover(&repo, &config).unwrap();
    (found.paths.into_iter().collect(), found.unreadable)
}

fn found(files: &[(&str, &str)]) -> (Vec<String>, Option<(String, String)>) {
    found_in("[[suite]]\ncommand = \"npx jest\"\nglobs = [\"**/*.test.js\"]\n", files)
}

fn why(path: &str, reason: &str) -> Option<(String, String)> {
    Some((path.to_string(), reason.to_string()))
}

#[test]
fn the_watched_configs_and_manifests() {
    let all = strings(&[
        "jest.config.js",
        "package.json",
        "packages/package.json",
        "packages/api/jest.config.json",
        "packages/api/deep/jest.config.ts",
        "packages/web/jest.config.js",
        "packages/api/node_modules/x/jest.config.js",
        "packages/api/jest.config.jsx",
        "packages/apix/package.json",
    ]);
    let api = [suite("packages/api", "jest --ci")];
    let got: Vec<String> = configs(&api, &all).into_iter().collect();
    assert_eq!(got, ["jest.config.js", "packages/api/deep/jest.config.ts", "packages/api/jest.config.json"]);
    let got: Vec<String> = manifests(&api, &all).into_iter().collect();
    assert_eq!(got, ["package.json", "packages/package.json"]);
    assert_eq!(configs(&[suite(".", "jest")], &all).len(), 4, "every config but node_modules' and .jsx");
    let vitest = Config::parse("[[suite]]\ncommand = \"vitest run\"\nglobs = [\"*.test.ts\"]\n").unwrap();
    assert!(suites(&vitest).is_empty());
}

#[test]
fn a_js_config_resolves_setup_literals_from_its_root_folder() {
    let files = [
        ("web/jest.config.js", "module.exports = { setupFilesAfterEnv: ['<rootDir>/setup', './a.js'], rootDir: 'src', globalSetup: '<rootDir>', globalTeardown: 'jest-extended/all' }"),
        ("web/src/setup.js", ""),
        ("web/src/setup.ts", ""),
        ("web/src/a.js", ""),
        ("web/src.js", ""),
        ("web/a.js", ""),
    ];
    let (paths, why) = found(&files);
    assert_eq!(why, None);
    assert_eq!(paths, ["web/jest.config.js", "web/src.js", "web/src/a.js", "web/src/setup.js", "web/src/setup.ts"]);
    let (paths, _) =
        found(&[("jest.config.js", "export default { rootDir: __dirname, setupFiles: ['./s'] }"), ("s.js", "")]);
    assert_eq!(paths, ["jest.config.js", "s.js"]);
}

#[test]
fn the_root_key_rules() {
    let one = |text: &str| found(&[("jest.config.js", text), ("s.js", "")]).1;
    let sets = why("jest.config.js", "it sets rootDir");
    assert_eq!(one("module.exports = { rootDir: path.join(__dirname, 'src') }"), sets);
    assert_eq!(one("module.exports = { rootDir: '/abs' }"), sets);
    assert_eq!(one("module.exports = { rootDir: '../..' }"), sets);
    assert_eq!(one("module.exports = { rootDir: '' , setupFiles: ['./s.js'] }"), None);
    let two = "module.exports = { rootDir: '.', setupFiles: './nope', projects: [{ rootDir: 'a' }] }";
    assert_eq!(one(two), why("jest.config.js", "./nope names no file in the repository"), "text order");
    assert_eq!(one("module.exports = { projects: [{ rootDir: 'a' }, { rootDir: 'b' }] }"), sets, "the second key");
    // A root key in a module reached by an import.
    let files = [("jest.config.js", "const b = require('./base')"), ("base.js", "module.exports = { rootDir: '.' }")];
    assert_eq!(found(&files).1, why("base.js", "it sets rootDir"));
}

#[test]
fn an_imported_module_resolves_from_the_config_root() {
    let files = [
        ("jest.config.js", "const o = require('./config/options'); module.exports = { rootDir: 'src', ...o }"),
        (
            "config/options.json",
            "{\"setupFiles\": [\"<rootDir>/boot.js\"], \"projects\": [{\"setupFiles\": \"./p.js\"}]}",
        ),
        ("src/boot.js", ""),
        ("src/p.js", ""),
    ];
    let (paths, why_) = found(&files);
    assert_eq!(why_, None);
    assert_eq!(paths, ["config/options.json", "jest.config.js", "src/boot.js", "src/p.js"]);
    let bad = [("jest.config.js", "import o from './o.json'"), ("o.json", "{\"rootDir\": \"x\"}")];
    assert_eq!(found(&bad).1, why("o.json", "it sets rootDir"));
    let strict = [("jest.config.js", "require('./o.json')"), ("o.json", "{// c\n}")];
    assert_eq!(found(&strict).1, why("o.json", "it is not a JSON object"), "an import parses strictly");
}

#[test]
fn the_json_reader() {
    let config = "// jsonc\n{\"setupFiles\": [\"<rootDir>\\/a.js\",], \"projects\": [\"x/jest.config.js\", {\"rootDir\": \"<rootDir>/packages/api\", \"globalSetup\": \"<rootDir>/g.js\"}, {\"rootDir\": \"web\", \"setupFiles\": [\"./w\"]}]}";
    let files = [("jest.config.json", config), ("a.js", ""), ("packages/api/g.js", ""), ("web/w.ts", "")];
    let (paths, why_) = found(&files);
    assert_eq!(why_, None);
    assert_eq!(paths, ["a.js", "jest.config.json", "packages/api/g.js", "web/w.ts"]);
    let one = |text: &str| found(&[("jest.config.json", text)]).1;
    assert_eq!(one("[]"), why("jest.config.json", "it is not a JSON object"));
    assert_eq!(one("{\"rootDir\": 3}"), why("jest.config.json", "it sets rootDir"));
    assert_eq!(one("{\"projects\": [{\"rootDir\": \"<rootDir>/../..\"}]}"), why("jest.config.json", "it sets rootDir"));
    let order = "{\"globalSetup\": 1, \"setupFiles\": \"/abs\", \"rootDir\": \"/r\"}";
    assert_eq!(one(order), why("jest.config.json", "it sets rootDir"), "rootDir, then the setup keys in order");
    assert_eq!(
        one("{\"globalSetup\": 1, \"setupFiles\": \"/abs\"}"),
        why("jest.config.json", "/abs is an absolute path")
    );
    assert_eq!(one("{\"projects\": {\"setupFiles\": 1}}"), None, "a projects value that is not an array");
}

#[test]
fn the_manifests() {
    let one = |text: &str| found(&[("package.json", text), ("after.js", "")]);
    assert_eq!(one("{\"jest\": {\"setupFilesAfterEnv\": [\"<rootDir>/after.js\"]}}").0, ["after.js"]);
    for nothing in ["not json", "[1]", "{\"name\": \"x\"}"] {
        assert_eq!(one(nothing), (Vec::new(), None), "{nothing}");
    }
    assert_eq!(one("{\"jest\": \"x\"}").1, why("package.json", "its jest key is not an object"));
    let number = "{\"jest\": {\"globalSetup\": 3}}";
    assert_eq!(one(number).1, why("package.json", "globalSetup is not a string or an array of strings"));
    let nested = [
        ("packages/api/package.json", "{\"jest\": {\"rootDir\": \"src\", \"setupFiles\": [\"./s\"]}}"),
        ("packages/api/src/s.js", ""),
    ];
    let config = "[[suite]]\nroot = \"packages/api\"\ncommand = \"jest\"\nglobs = [\"**/*.test.js\"]\n";
    assert_eq!(found_in(config, &nested).0, ["packages/api/src/s.js"]);
    let none = "[[suite]]\ncommand = \"npm test\"\nglobs = [\"**/*.test.js\"]\n";
    assert_eq!(found_in(none, &[("package.json", "{\"jest\": 1}")]), (Vec::new(), None), "no Jest suite");
}

#[test]
fn the_first_unreadable_of_both_runners() {
    let found = |path: &str| Found { paths: BTreeSet::new(), unreadable: why(path, "it sets rootDir") };
    let refused = |v: &Found, j: &Found| match refuse_first(v, j) {
        Err(crate::refusal::Stop::Refused(r)) => r.to_string(),
        _ => panic!("a refusal"),
    };
    assert!(refused(&found("b.js"), &found("a.js")).contains("the jest setup files of a.js"));
    assert!(refused(&found("a.js"), &found("a.js")).contains("the vitest setup files of a.js"));
    assert!(refuse_first(&Found::default(), &Found::default()).is_ok());
    assert_eq!(
        refused(&Found::default(), &found("a\nb.js")),
        "shipcraft refused: could not read the jest setup files of a\\nb.js: it sets rootDir\n\
         Why: red locks the setup files it can name; one it cannot name could change what every locked case sees\n\
         Next: in a\\nb.js, write setupFiles, setupFilesAfterEnv, globalSetup and globalTeardown as string literals or arrays of them, and rootDir, if any, as one relative string literal in the config file itself, then run red again"
    );
}

#[test]
fn the_jest_settings_of_a_manifest() {
    let same =
        |a: &str, b: &str| jest_settings("package.json", a.into()).same(&jest_settings("package.json", b.into()));
    let a = "{\"name\": \"a\", \"jest\": {\"setupFiles\": [\"./s\"], \"verbose\": true}}";
    assert!(same(a, "{\"jest\":{\"verbose\":true,\"setupFiles\":[ \"./s\" ]},\"name\":\"b\",\"dependencies\":{}}"));
    assert!(!same(a, "{\"jest\": {\"setupFiles\": [\"./t\"], \"verbose\": true}}"));
    assert!(!same("{\"jest\": 1}", "{\"jest\": 1.0}"), "1 and 1.0 differ");
    assert!(same("{\"jest\": 1, \"jest\": 2}", "{\"jest\": 2}"), "a duplicate key keeps its last value");
    assert!(matches!(jest_settings("p", b"{\"name\": 1}".to_vec()), Settings::None));
    assert!(matches!(jest_settings("p", b"[1]".to_vec()), Settings::Bytes(_)));
    assert!(!same(a, "{broken"), "one that stops parsing has changed");
}

#[test]
fn the_module_keys_lock_what_they_name() {
    let config = "module.exports = { rootDir: 'src', testEnvironment: '<rootDir>/env', transform: { '\\\\.ts$': ['<rootDir>/ts.js', { tsconfig: './tsconfig.test.json' }], x: require.resolve('./jest/t.js') }, reporters: ['default', ['./rep.js', {resolver: './none.txt'}]], globals: {filter: './none.json'}, snapshotSerializers: [path.join(__dirname, 'x.js')] }";
    let files = [
        ("jest.config.js", config),
        ("src/env/index.js", ""),
        ("src/ts.js", ""),
        ("src/tsconfig.test.json", ""),
        ("jest/t.js", ""),
        ("src/rep.js", ""),
        ("src/x.js", ""),
    ];
    let (paths, why_) = found(&files);
    assert_eq!(why_, None);
    assert_eq!(paths, ["jest.config.js", "jest/t.js", "src/env/index.js", "src/rep.js", "src/ts.js"]);
    // A package names nothing; a missing relative file, an absolute path and a link are reasons.
    let one = |text: &str| found(&[("jest.config.js", text)]).1;
    assert_eq!(
        one("module.exports = { transform: {x: 'babel-jest'}, testEnvironment: 'jsdom', preset: 'ts-jest' }"),
        None
    );
    let missing = "module.exports = { transform: { '\\\\.js$': '<rootDir>/jest/missing.js' } };";
    assert_eq!(one(missing), why("jest.config.js", "<rootDir>/jest/missing.js names no file in the repository"));
    assert_eq!(
        one("module.exports = { resolver: '/opt/r.js' }"),
        why("jest.config.js", "/opt/r.js is an absolute path")
    );
    let resolve = "module.exports = { testEnvironment: require.resolve('./missing.js') }";
    assert_eq!(one(resolve), why("jest.config.js", "./missing.js names no file in the repository"));
    let order = "module.exports = { reporters: ['./r-missing.js'], setupFiles: './s-missing.js' };";
    assert_eq!(one(order), why("jest.config.js", "./r-missing.js names no file in the repository"), "text order");
}

#[test]
fn a_module_name_mapper_keeps_root_dir_literals_without_captures() {
    let config = "module.exports = { moduleNameMapper: { '^a$': '<rootDir>/test/fake.js', '^b$': ['<rootDir>/opt/none.js', '<rootDir>/test/alt.js', '<rootDir>/src/$1'], '^c$': './test/rel.js', '^d$': 'identity-obj-proxy', '^e$': '<rootDir>/test/price$.js', '^s$': require.resolve('./test/mock.js') } }";
    let files = [
        ("jest.config.js", config),
        ("test/fake.js", ""),
        ("test/alt.js", ""),
        ("test/rel.js", ""),
        ("test/price$.js", ""),
        ("test/mock.js", ""),
        ("src/$1.js", ""),
    ];
    let (paths, why_) = found(&files);
    assert_eq!(why_, None);
    assert_eq!(paths, ["jest.config.js", "test/alt.js", "test/fake.js", "test/mock.js", "test/price$.js"]);
}

#[test]
fn a_relative_preset_is_read_like_a_config() {
    let files = [
        ("jest.config.js", "module.exports = { rootDir: 'web', preset: '<rootDir>/presets/web' };"),
        (
            "web/presets/web.js",
            "module.exports = { preset: './missing', testEnvironment: 'node', ...require('./base.js') };",
        ),
        ("web/presets/base.js", "module.exports = { preset: './missing-too', transform: {x: './jest/t.js'} };"),
        ("web/presets/web/jest-preset.cjs", "module.exports = { testEnvironment: '<rootDir>/test/env.js' };"),
        ("web/presets/web.json", "{\"setupFiles\": \"<rootDir>/boot.js\", \"preset\": \"./nope\"}"),
        ("web/test/env.js", ""),
        ("web/boot.js", ""),
        ("web/jest/t.js", ""),
    ];
    let (paths, why_) = found(&files);
    assert_eq!(why_, None);
    let all = [
        "jest.config.js",
        "web/boot.js",
        "web/jest/t.js",
        "web/presets/base.js",
        "web/presets/web.js",
        "web/presets/web.json",
        "web/presets/web/jest-preset.cjs",
        "web/test/env.js",
    ];
    assert_eq!(paths, all);
    let one = |config: &str, preset: (&str, &str)| found(&[("jest.config.js", config), preset]).1;
    let cfg = "module.exports = { preset: './p' }";
    assert_eq!(one(cfg, ("p.json", "[1]")), why("p.json", "it is not a JSON object"));
    assert_eq!(one(cfg, ("p.json", "{// c\n}")), why("p.json", "it is not a JSON object"), "parsed strictly");
    assert_eq!(one(cfg, ("p.js", "module.exports = { rootDir: 'src' };")), why("p.js", "it sets rootDir"));
    assert_eq!(one(cfg, ("p", "{}")), None, "an extensionless preset is locked, not read");
    assert_eq!(
        one("module.exports = { preset: './nope' }", ("x", "")),
        why("jest.config.js", "./nope names no file in the repository")
    );
    assert_eq!(one("module.exports = { preset: '/p' }", ("x", "")), why("jest.config.js", "/p is an absolute path"));
}

#[test]
fn the_json_reader_reads_preset_and_the_module_keys_in_order() {
    let manifest = "{\"jest\":{\"preset\":\"./jest-preset.json\",\"transform\":{\"x\":\"<rootDir>/jest/t.js\"},\"haste\":{\"hasteImplModulePath\":\"./h.js\"},\"projects\":[{\"rootDir\":\"<rootDir>/pkg\",\"testEnvironment\":\"./env.js\"}]}}";
    let files = [
        ("package.json", manifest),
        ("jest-preset.json", "{\"reporters\": [[\"./rep.js\", {}]], \"preset\": \"./ignored\"}"),
        ("jest/t.js", ""),
        ("h.js", ""),
        ("rep.js", ""),
        ("pkg/env.js", ""),
    ];
    let (paths, why_) = found(&files);
    assert_eq!(why_, None);
    assert_eq!(paths, ["h.js", "jest-preset.json", "jest/t.js", "pkg/env.js", "rep.js"]);
    let one = |text: &str| found(&[("package.json", text)]).1;
    let order = "{\"jest\":{\"transform\":{\"x\":\"./a-missing.js\"},\"preset\":\"./b-missing\"}}";
    assert_eq!(one(order), why("package.json", "./b-missing names no file in the repository"), "preset first");
    let keys =
        "{\"jest\":{\"watchPlugins\":[\"./w-missing.js\"],\"testEnvironment\":\"./e-missing.js\",\"setupFiles\":3}}";
    assert_eq!(one(keys), why("package.json", "setupFiles is not a string or an array of strings"));
    let keys = "{\"jest\":{\"watchPlugins\":[\"./w-missing.js\"],\"testEnvironment\":\"./e-missing.js\"}}";
    assert_eq!(one(keys), why("package.json", "./e-missing.js names no file in the repository"), "the key order");
}
