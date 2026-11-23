use super::*;

fn strings(items: &[&str]) -> Vec<String> {
    items.iter().map(|item| item.to_string()).collect()
}

fn names(text: &str) -> Vec<String> {
    pytest_plugins(text)
}

fn args(text: &str) -> (Vec<String>, Vec<(String, Vec<String>)>) {
    let (mut names, mut overrides) = (Vec::new(), Vec::new());
    read_args(&split(text), &mut names, &mut overrides, &strings(&["svc"]));
    (names, overrides)
}

#[test]
fn the_split() {
    assert_eq!(split("a  b\tc\r\nd"), ["a", "b", "c", "d"]);
    assert_eq!(split(r#""-p" 'my plugin' x\ y"#), ["-p", "my plugin", "x y"]);
    assert_eq!(split(r#""a\"b\\c\d" '\n' ''"#), [r#"a"b\c\d"#, r"\n", ""]);
    assert_eq!(split("a\"b c\"d"), ["ab cd"]);
    assert_eq!(split("-p 'open x"), ["-p", "'open", "x"], "an unclosed quote splits on whitespace");
    assert_eq!(split("-p x\\"), ["-p", "x\\"], "a trailing backslash splits on whitespace");
    assert!(split("  ").is_empty());
}

#[test]
fn p_and_o_arguments() {
    let (got, overrides) = args("python -m pytest -p no:cacheprovider -p myplugin -pother -p ' sp ' -p");
    assert_eq!(got, ["myplugin", "other", "sp"]);
    assert!(overrides.is_empty());
    let (got, overrides) =
        args("pytest -o 'addopts=-p one -o pythonpath=x' --override-ini=pythonpath='a b' -opythonpath=c");
    assert_eq!(got, ["one"], "an -o addopts value is read for -p, not -o");
    let entries: Vec<&str> = overrides.iter().map(|(entry, _)| entry.as_str()).collect();
    assert_eq!(entries, ["a", "b", "c"]);
    assert_eq!(overrides[0].1, ["svc"]);
    let (got, overrides) = args("pytest --override-ini ' addopts =-pz' -o noequals -o");
    assert_eq!(got, ["z"]);
    assert!(overrides.is_empty());
}

#[test]
fn ini_values_as_iniconfig_reads_them() {
    let section = "[pytest]\naddopts = -q\n    -p myplugin\n  # c\n\n[x\naddopts: -p two\nnope\n  -p lost\n[other]\n";
    assert_eq!(ini_values(section, "addopts"), ["-q\n-p myplugin\n[x", "-p two"]);
    assert_eq!(ini_values("[pytest]\r\npythonpath = a\r\n\tb\r\n", "pythonpath"), ["a\nb"]);
    assert_eq!(ini_values("[pytest]\rKEY=1\r addopts = 2\r", "addopts"), Vec::<String>::new());
    let (addopts, path) =
        config_values("setup.cfg", "[tool:pytest]\naddopts = -q\n  -p myplugin\npythonpath = src lib\n");
    assert_eq!(addopts, [strings(&["-q", "-p", "myplugin"])]);
    assert_eq!(path, ["src", "lib"]);
    assert!(config_values("setup.cfg", "[pytest]\naddopts = -p x\n").0.is_empty(), "not setup.cfg's section");
    assert_eq!(config_values("pytest.ini", "[pytest]\naddopts = -px\n").0, [strings(&["-px"])]);
}

#[test]
fn toml_values() {
    let text = "[tool.pytest.ini_options]\naddopts = \"-p a\"\npythonpath = [\"plugins\", 3]\n[tool.pytest]\naddopts = [\"-p\", \"b\", 1]\n";
    let (addopts, path) = config_values("pyproject.toml", text);
    assert_eq!(addopts, [strings(&["-p", "a"]), strings(&["-p", "b"])]);
    assert_eq!(path, ["plugins"]);
    assert_eq!(config_values("pytest.toml", "[pytest]\naddopts = \"-pz\"\npythonpath = 1\n").0, [strings(&["-pz"])]);
    assert!(config_values("pyproject.toml", "[tool.pytest\n").0.is_empty(), "one that does not parse names nothing");
    assert!(config_values("pytest.toml", "addopts = \"-p x\"\n").0.is_empty());
}

#[test]
fn joins_and_candidates() {
    assert_eq!(join("svc", "./a//b/../c").as_deref(), Some("svc/a/c"));
    assert_eq!(join("", "..").as_deref(), None);
    assert_eq!(join("svc", "/abs"), None);
    assert_eq!(join("svc", "..").as_deref(), Some(""));
    assert_eq!(candidates("a.b.c", ""), ["a/__init__.py", "a/b/__init__.py", "a/b/c.py", "a/b/c/__init__.py"]);
    assert_eq!(candidates("plug", "svc/p"), ["svc/p/plug.py", "svc/p/plug/__init__.py"]);
    for bad in ["", "a..b", "1a", "a-b", " b", "ação", "a."] {
        assert!(candidates(bad, "").is_empty(), "{bad:?}");
    }
    assert_eq!(candidates("_a.b2", "").len(), 3);
}

#[test]
fn pytest_plugins_values() {
    assert_eq!(names("pytest_plugins = \"a,b\"  # c\n"), ["a", "b"]);
    assert_eq!(names("pytest_plugins = 'a, b'"), ["a", " b"]);
    assert_eq!(names("pytest_plugins = [\"helpers.plug\", 'x',]\n"), ["helpers.plug", "x"]);
    assert_eq!(names("pytest_plugins = (\n    \"a\",  # one\n    # gap\n    \"b\"\n)  # end\n"), ["a", "b"]);
    assert_eq!(names("pytest_plugins = (\"a,b\")\n"), ["a", "b"], "a grouped string");
    assert_eq!(names("pytest_plugins = (\n  'a,b'  # c\n)\n"), ["a", "b"]);
    assert_eq!(names("pytest_plugins = (\"a,b\",)\n"), ["a,b"], "a tuple of one");
    assert_eq!(names("pytest_plugins = [\"a,b\"]\n"), ["a,b"]);
    assert_eq!(names("pytest_plugins: list[str] = [\"a\"]\npytest_plugins=\"b\"\n"), ["a", "b"]);
    assert_eq!(names("pytest_plugins: \"x=y\" = 'a'\n"), ["a"], "an annotation's literal hides its =");
    assert_eq!(names("pytest_plugins = []\npytest_plugins = ()\n"), Vec::<String>::new());
    assert_eq!(names("pytest_plugins = ['a']"), ["a"], "the end of the file ends the line");
}

#[test]
fn pytest_plugins_reads_nothing_else() {
    for text in [
        "pytest_plugins = PLUGINS\n",
        "pytest_plugins = load()\n",
        "pytest_plugins = [\"a\"] + [\"b\"]\n",
        "pytest_plugins = [[\"a\"]]\n",
        "pytest_plugins = [r\"a\"]\n",
        "pytest_plugins = f\"a\"\n",
        "pytest_plugins = \"\"\"a\"\"\"\n",
        "pytest_plugins = \"plug\\x69n\"\n",
        "pytest_plugins = [\"a\" \"b\"]\n",
        "pytest_plugins = [\"a\",,]\n",
        "pytest_plugins = [\"a\")\n",
        "pytest_plugins = [\"a\"\n",
        "pytest_plugins = \"a\" if x else \"b\"\n",
        "pytest_plugins == [\"a\"]\n",
        "pytest_plugins: list = \n",
        "pytest_pluginsx = [\"a\"]\n",
        "    pytest_plugins = [\"a\"]\n",
        "x = 1; pytest_plugins = [\"a\"]\n",
        "# pytest_plugins = [\"a\"]\n",
        "\"\"\"\npytest_plugins = [\"x\"]\n\"\"\"\n",
        "pytest_plugins = \"a\n",
    ] {
        assert_eq!(names(text), Vec::<String>::new(), "{text:?}");
    }
    let open = "s = 'open\npytest_plugins = [\"y\"]\n'\n";
    assert_eq!(names(open), ["y"], "a one-quote literal ends at the end of its line");
}

#[test]
fn pytest_plugins_lines() {
    assert_eq!(names("x = 1\rpytest_plugins = [\r  'a',\r  'b']\r"), ["a", "b"], "CR lines");
    assert_eq!(names("x = 1\r\npytest_plugins = 'a'\r\npytest_plugins = ('b',)\r\n"), ["a", "b"], "CRLF lines");
    assert_eq!(names("x = '''\n'''\npytest_plugins = 'a'\n"), ["a"], "after a closed docstring");
    assert_eq!(names("pytest_plugins = 'a'  ; x = 1\n"), Vec::<String>::new());
}
