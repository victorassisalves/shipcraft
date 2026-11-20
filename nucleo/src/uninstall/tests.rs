use super::*;

#[test]
fn cuts_the_block_and_its_separator() {
    let block = written_blocks("AGENTS.md")[0].clone();
    let with = |before: &str, after: &str| format!("{before}{block}{after}").into_bytes();
    let cut = |bytes: Vec<u8>| cut_block("AGENTS.md", &bytes).unwrap().unwrap();
    // init's separators: "\n\n" after no `\n`, "\n" after one, none after two.
    assert_eq!(cut(with("# Rules\n\n- Keep it small.\n\n", "")), b"# Rules\n\n- Keep it small.\n");
    assert_eq!(cut(with("a\n\n\n", "")), b"a\n\n\n");
    assert_eq!(cut(with("a\n\n", "")), b"a\n");
    assert_eq!(cut(with("\n\n", "")), b"");
    assert_eq!(cut(with("\n", "")), b"");
    assert_eq!(cut(with("", "")), b"");
    assert_eq!(cut(with("a\n\n", "b\n")), b"a\n\nb\n");
    let local = written_blocks("AGENTS.md").into_iter().find(|b| b.contains("npx -- shipcraft")).unwrap();
    assert_eq!(cut(format!("a\n\n{local}").into_bytes()), b"a\n");
    let claude = written_blocks("CLAUDE.md")[0].clone();
    assert_eq!(cut_block("CLAUDE.md", claude.as_bytes()), Some(Some(Vec::new())));
    assert_eq!(cut_block("AGENTS.md", b"# no markers\n"), None);
    for edited in [block.replace("\n", "\r\n"), block.replace("Cycle:", "cycle:"), format!("{block}{block}")] {
        assert_eq!(cut_block("AGENTS.md", edited.as_bytes()), Some(None), "{edited:?}");
    }
    assert_eq!(cut_block("AGENTS.md", claude.as_bytes()), Some(None));
}

#[test]
fn cuts_only_the_husky_line_init_writes() {
    let (msg, close) = (HUSKY[0].1, HUSKY[1].1);
    assert_eq!(cut_husky_line(format!("{close}\n").as_bytes(), close), Some(Some(Vec::new())));
    let head = format!("#!/bin/sh\n{}\n\n", HELPERS[0]);
    assert_eq!(cut_husky_line(format!("{head}{msg}\n").as_bytes(), msg), Some(Some(Vec::new())));
    assert_eq!(
        cut_husky_line(format!("{head}{msg}\nnpm t\n").as_bytes(), msg),
        Some(Some(format!("{head}npm t\n").into_bytes()))
    );
    let kept = format!("#!/bin/sh\n{close}\nnpm test\n");
    assert_eq!(cut_husky_line(kept.as_bytes(), close), Some(Some(b"#!/bin/sh\nnpm test\n".to_vec())));
    let local = "./node_modules/.bin/shipcraft close";
    assert_eq!(cut_husky_line(format!("{local}\n").as_bytes(), close), Some(Some(Vec::new())));
    assert_eq!(cut_husky_line(b"npm test\n", close), None);
    for left in [
        "npx --no -- shipcraft close\n".to_string(),
        format!("{close}\n{close}\n"),
        format!("{close} --x\n"),
        format!("{close}\r\n"),
        format!("{msg}\n"),
    ] {
        assert_eq!(cut_husky_line(left.as_bytes(), close), Some(None), "{left:?}");
    }
    assert_eq!(cut_husky_line(close.as_bytes(), close), Some(Some(Vec::new())));
}

#[test]
fn pre_commit_items_come_out_as_append_put_them_in() {
    let bases = [
        "repos:\n- repo: https://github.com/x/y\n  rev: v1\n  hooks:\n  - id: z\n",
        "repos:\r\n  -   repo: https://github.com/x/y\r\n      rev: v1\r\n      hooks:\r\n      -   id: z\r\ndefault_stages: [pre-commit]\r\n",
        "# top\nrepos:\n    - repo: https://github.com/x/y\n      rev: v1\n      hooks:\n        - id: z\n# end\n",
    ];
    for base in bases {
        for local in [false, true] {
            for wanted in [&[0, 1][..], &[0], &[1]] {
                let added = append(base, wanted, local).unwrap();
                assert_eq!(cut_items(&added).as_deref(), Some(base), "{added}");
                let legacy = added.replace("id: shipcraft-close", "id: shipcraft-fecha");
                assert_eq!(cut_items(&legacy).as_deref(), Some(base), "{legacy}");
            }
        }
        assert_eq!(cut_items(base), None);
        let edited = append(base, &[0, 1], false).unwrap().replace("always_run: true", "always_run: false");
        assert!(cut_items(&edited).is_none_or(|t| t.contains("shipcraft")));
    }
    // Two items appended one after the other both come out.
    let base = bases[0];
    let twice = append(&append(base, &[0], false).unwrap(), &[1], false).unwrap();
    assert_eq!(cut_items(&twice).as_deref(), Some(base));
}

#[test]
fn a_lock_not_read_closed_is_open() {
    let dir = crate::git::TempDir::new("shipcraft-test-item143").unwrap();
    assert_eq!(in_tree(dir.path()), None);
    fs::create_dir_all(dir.path().join(LOCKS)).unwrap();
    fs::write(dir.path().join(LOCKS).join("a.json"), r#"{"state":"closed"}"#).unwrap();
    fs::write(dir.path().join(LOCKS).join(".gitkeep"), "").unwrap();
    assert_eq!(in_tree(dir.path()), None);
    fs::write(dir.path().join(LOCKS).join("b.json"), "{").unwrap();
    fs::create_dir(dir.path().join(LOCKS).join("c.json")).unwrap();
    assert_eq!(in_tree(dir.path()), Some(b".shipcraft/locks/b.json".to_vec()));
}
