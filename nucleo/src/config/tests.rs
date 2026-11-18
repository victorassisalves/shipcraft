//! The unit tests of the config.

use super::Config;

fn suite(raiz: &str, glob: &str) -> String {
    format!("[[suite]]\nroot = \"{raiz}\"\ncommand = \"x\"\nglobs = [\"{glob}\"]\n")
}

#[test]
fn legacy_document_keys_refuse_before_deserialization() {
    for (text, old, new) in [
        ("verifica = 'exit 37'", "verifica", "check"),
        ("\"verifica\" = 'exit 37'", "verifica", "check"),
        ("[execucao]\nci = 'local'", "execucao", "execution"),
        ("execution.tempo_max_ci = 17", "execution.tempo_max_ci", "execution.ci_timeout"),
        ("suite = [{ nome = 'api' }]", "suite[0].nome", "suite[0].name"),
        ("check = 'true'\nverifica = 'false'", "verifica", "check"),
    ] {
        match Config::parse(text) {
            Err(crate::refusal::Stop::Refused(r)) => {
                assert_eq!(r.code, "config-invalid", "{text}");
                assert!(r.what().contains(&format!("`{old}`")), "{}", r.what());
                assert!(r.what().contains(&format!("`{new}`")), "{}", r.what());
            }
            _ => panic!("legacy key accepted: {text}"),
        }
    }
    assert!(Config::parse("check = 'echo verifica filtra comando' # [execucao]\n").is_ok());
}

#[test]
fn english_config_keys_reach_their_consumers() {
    let config = Config::parse(
        r#"
check = "project-check"
filter = "command"
[execution]
ci = "github"
review = "off"
ci_timeout = 17
[roles]
review = "claude"
[review]
spec = "contract.md"
timeout = 19
[machine]
slots = 3
[pr]
warn_lines = 23
shape_lines = 29
[build]
command = "compile"
[[suite]]
name = "api"
root = "packages/api"
command = "test"
check = "suite-check"
filter = "command"
globs = ["tests/**"]
"#,
    )
    .unwrap();
    assert_eq!(config.verifica.as_deref(), Some("project-check"));
    assert!(config.filtra == super::Filtra::Comando);
    assert!(config.camadas().unwrap() == (super::Camada::Github, super::Camada::Desligado));
    assert_eq!(config.execucao.tempo_max_ci, 17);
    assert_eq!(config.papeis.revisao.agent, "claude");
    assert_eq!(config.revisao.spec.as_deref(), Some("contract.md"));
    assert_eq!(config.revisao.tempo_max, 19);
    assert_eq!(config.maquina.slots, Some(3));
    assert_eq!(config.pr.aviso_linhas, 23);
    assert_eq!(config.pr.forma_linhas.unwrap().get(), 29);
    assert_eq!(config.build.unwrap().comando, "compile");
    let suite = &config.suite[0];
    assert_eq!(suite.nome, "api");
    assert_eq!(suite.raiz, "packages/api");
    assert_eq!(suite.comando, "test");
    assert_eq!(suite.verifica.as_deref(), Some("suite-check"));
    assert!(suite.filtra == super::Filtra::Comando);
    assert!(Config::parse("filter = \"comando\"").is_err());
    assert!(Config::parse("[execution]\nreview = \"github\"").unwrap().camadas().is_err());
    assert_eq!(Config::parse("").unwrap().execucao.merge, "merge");
    assert_eq!(Config::parse("[execution]\nmerge = \"squash\"").unwrap().execucao.merge, "squash");
    for bad in [
        "merge = \"rebase\"",
        "merge = 7",
        "merge = true",
        "ci = \"desligado\"",
        "ci = \"LOCAL\"",
        "ci = 7",
        "review = \"off \"",
        "review = [\"local\"]",
    ] {
        let refused = Config::parse(&format!("[execution]\n{bad}"));
        assert!(matches!(refused, Err(crate::refusal::Stop::Refused(r)) if r.code == "execution-invalid"), "{bad}");
    }
    let refused = Config::parse("[execution]\nci = \"foo\"\nci_timeout = \"bad\"");
    assert!(matches!(refused, Err(crate::refusal::Stop::Refused(r)) if r.code == "config-invalid"));
}

#[test]
fn new_dependencies_and_their_days_are_checked() {
    let config = Config::parse("").unwrap();
    assert_eq!(config.pr.new_dependencies, super::NewDependencies::Warn);
    assert_eq!(config.pr.new_dependency_days.0, 30);
    let config = Config::parse("[pr]\nnew_dependencies = \"off\"\nnew_dependency_days = 36500\n").unwrap();
    assert_eq!(config.pr.new_dependencies, super::NewDependencies::Off);
    assert_eq!(config.pr.new_dependency_days.0, 36500);
    assert_eq!(Config::parse("[pr]\nnew_dependency_days = 1").unwrap().pr.new_dependency_days.0, 1);
    assert_eq!(
        Config::parse("[pr]\nnew_dependencies = \"warn\"").unwrap().pr.new_dependencies,
        super::NewDependencies::Warn
    );
    for bad in [
        "new_dependencies = \"Warn\"",
        "new_dependencies = \"no\"",
        "new_dependencies = true",
        "new_dependencies = 1",
        "new_dependency_days = 0",
        "new_dependency_days = 36501",
        "new_dependency_days = -1",
        "new_dependency_days = 30.0",
        "new_dependency_days = \"30\"",
    ] {
        match Config::parse(&format!("[pr]\nwarn_lines = 9\n{bad}\n")) {
            Err(crate::refusal::Stop::Refused(r)) => {
                assert_eq!(r.code, "config-invalid", "{bad}");
                assert!(r.what().contains(&format!("(line 3: `{bad}`)")), "{bad}: {}", r.what());
            }
            _ => panic!("{bad}"),
        }
    }
}

#[test]
fn raiz_and_globs_are_normalized_once() {
    for (raiz, normal) in
        [("./packages/api/", "packages/api"), ("packages//api", "packages/api"), ("./", ""), (".", ""), ("", "")]
    {
        let config = Config::parse(&suite(raiz, "./tests/**")).unwrap_or_else(|_| panic!("{raiz}"));
        assert_eq!(config.suite[0].raiz, normal);
        assert_eq!(config.suite[0].globs, ["tests/**"]);
    }
    assert!(Config::parse(&suite("./packages/api", "tests/*.py")).unwrap().is_test_file("packages/api/tests/a.py"));
}

#[test]
fn absolute_or_parent_paths_and_empty_globs_are_invalid() {
    for (raiz, glob) in [
        ("/", "*"),
        ("/.", "*"),
        ("/x", "*"),
        ("a/../b", "*"),
        ("..", "*"),
        ("a", ""),
        ("a", "./"),
        ("a", "/t/*"),
        ("a", "../*"),
    ] {
        assert!(Config::parse(&suite(raiz, glob)).is_err(), "{raiz} {glob}");
    }
}

#[test]
fn not_toml_or_a_suite_without_comando_is_a_refusal() {
    for text in ["this is not toml", "[[suite]]\nroot = \"a\"\n"] {
        match Config::parse(text) {
            Err(crate::refusal::Stop::Refused(r)) => assert_eq!(r.code, "config-invalid", "{text}"),
            _ => panic!("{text}"),
        }
    }
}

#[test]
fn role_checks_come_after_the_existing_refusals() {
    let text = "shipcraft_min = \"2.20\"\n[[suite]]\nroot = \"/outside\"\ncommand = \"true\"\n[roles]\nred = \"invalid-agent\"\n";
    match Config::parse(text) {
        Err(crate::refusal::Stop::Refused(r)) => assert!(r.what().contains("root = \"/outside\""), "{}", r.what()),
        _ => panic!("accepted"),
    }
}

#[test]
fn suite_checks_need_github_ci_and_a_2_18_minimum() {
    let ok = "shipcraft_min = \"2.18\"\n[execution]\nci = \"github\"\nsuite_checks = [\"a b\", \"c/\u{3b2}\"]";
    assert_eq!(Config::parse(ok).unwrap().execucao.suite_checks, ["a b", "c/\u{3b2}"]);
    assert!(Config::parse("[execution]\nsuite_checks = []").unwrap().execucao.suite_checks.is_empty());
    for bad in [
        "shipcraft_min = \"2.18\"\n[execution]\nci = \"github\"\nsuite_checks = \"a\"",
        "shipcraft_min = \"2.18\"\n[execution]\nci = \"github\"\nsuite_checks = [\"a\", \"a\"]",
        "shipcraft_min = \"2.18\"\n[execution]\nci = \"github\"\nsuite_checks = [\"\\u00a0a\"]",
        "shipcraft_min = \"2.18\"\n[execution]\nci = \"github\"\nsuite_checks = [\"shipcraft/ci\"]",
        "shipcraft_min = \"2.18\"\n[execution]\nci = \"local\"\nsuite_checks = [\"a\"]",
        "shipcraft_min = \"2.17\"\n[execution]\nci = \"github\"\nsuite_checks = [\"a\"]",
        "shipcraft_min = \"2.18a\"\n[execution]\nci = \"github\"\nsuite_checks = [\"a\"]",
        "[execution]\nci = \"github\"\nsuite_checks = [\"a\"]",
    ] {
        let refused = Config::parse(bad);
        assert!(matches!(refused, Err(crate::refusal::Stop::Refused(r)) if r.code == "execution-invalid"), "{bad}");
    }
}

#[test]
fn retry_wait_defaults_to_120_and_any_explicit_value_needs_2_41() {
    assert_eq!(Config::parse("").unwrap().revisao.retry_wait, 120);
    assert_eq!(Config::parse("shipcraft_min = \"2.41\"\n[review]\nretry_wait = 0").unwrap().revisao.retry_wait, 0);
    for bad in [
        "[review]\nretry_wait = 0",
        "shipcraft_min = \"2.40.9\"\n[review]\nretry_wait = 0",
        "shipcraft_min = \"2.41a\"\n[review]\nretry_wait = 1",
        "shipcraft_min = \"2.41\"\n[review]\nretry_wait = -1",
        "shipcraft_min = \"2.41\"\n[review]\nretry_wait = 1.5",
    ] {
        let refused = Config::parse(bad);
        assert!(matches!(refused, Err(crate::refusal::Stop::Refused(r)) if r.code == "config-invalid"), "{bad}");
    }
}

#[test]
fn report_release_tags_is_validated_in_order() {
    assert!(Config::parse("[report]\nrelease_tags = \"deploy-*\"").is_ok());
    assert!(Config::parse("[report]").is_ok());
    assert!(Config::parse("[other]\nx = 1").is_ok());
    let problem = |text: &str| super::report_release_tags(&text.parse::<toml::Table>().unwrap());
    assert_eq!(problem("[report]\nrelease_tags = \"v*\""), Ok(Some("v*".to_string())));
    assert_eq!(problem("[report]"), Ok(None));
    assert_eq!(problem(""), Ok(None));
    for (text, want) in [
        ("report = 1", "[report] is not a table"),
        ("[[report]]\nrelease_tags = \"v*\"", "[report] is not a table"),
        ("[report]\nrelease_tag = \"deploy-*\"", "unknown key release_tag"),
        ("[report]\nzz = 1\nb = 2\nrelease_tags = 3", "unknown key b"),
        ("[report]\nrelease_tags = 3", "release_tags is not a string"),
        ("[report]\nrelease_tags = \"\"", "release_tags is empty"),
        ("[report]\nrelease_tags = \"a b?\"", "release_tags has a byte outside 0x21-0x7E"),
        ("[report]\nrelease_tags = \"d\u{e9}*\"", "release_tags has a byte outside 0x21-0x7E"),
        ("[report]\nrelease_tags = \"v?\"", "release_tags has ?, [, ] or \\"),
        ("[report]\nrelease_tags = \"v[0]\"", "release_tags has ?, [, ] or \\"),
        ("[report]\nrelease_tags = 'v\\*'", "release_tags has ?, [, ] or \\"),
        ("[report]\nrelease_tags = \"**\"", "release_tags is only *"),
    ] {
        assert_eq!(problem(text), Err(want.to_string()), "{text}");
        match Config::parse(text) {
            Err(crate::refusal::Stop::Refused(r)) => {
                assert_eq!(r.code, "config-invalid", "{text}");
                assert!(r.what().contains(want), "{}", r.what());
            }
            _ => panic!("accepted: {text}"),
        }
    }
}

#[test]
fn review_after_defaults_to_ci_and_any_explicit_value_needs_2_46() {
    assert!(!Config::parse("").unwrap().revisao.after_push);
    assert!(!Config::parse("shipcraft_min = \"2.46\"\n[review]\nafter = \"ci\"").unwrap().revisao.after_push);
    assert!(Config::parse("shipcraft_min = \"2.46\"\n[review]\nafter = \"push\"").unwrap().revisao.after_push);
    for bad in [
        "[review]\nafter = \"ci\"",
        "shipcraft_min = \"2.45.9\"\n[review]\nafter = \"push\"",
        "shipcraft_min = \"2.46\"\n[review]\nafter = \"PUSH\"",
        "shipcraft_min = \"2.46\"\n[review]\nafter = 1",
        "shipcraft_min = \"2.46\"\n[review]\nafter = [\"push\"]",
    ] {
        let refused = Config::parse(bad);
        assert!(matches!(refused, Err(crate::refusal::Stop::Refused(r)) if r.code == "config-invalid"), "{bad}");
    }
}
