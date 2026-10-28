//! Running the suites. shipcraft trusts the JUnit report, never the exit code.

use crate::config::{Config, Filtra, Suite};
use crate::git::HOOK_GIT_ENV;
use crate::glob;
use crate::junit::{Outcome, Report};
use crate::refusal::{failed, refuse, Result};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::io::{self, Read, Write};
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::{mpsc, Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// Which suite left no report, and what its command said, as one line for
/// the refusal (item 16a.2); `check` when it was the suite's check that
/// failed (item 45).
pub struct Missing {
    pub reason: String,
    pub check: Option<FailedCheck>,
}

/// A suite's check that failed: the suite's root as messages show it, and the
/// check on one line (item 45).
pub struct FailedCheck {
    pub root: String,
    pub command: String,
}

impl FailedCheck {
    /// Why a failing check refuses.
    pub const WHY: &'static str = "a suite is judged only after the project passes its check";

    /// What to do, before any phase-specific tail.
    pub fn next(&self) -> String {
        format!(
            "run `{}` at the suite's root `{}` and fix what it reports (the code or stub, or a missing tool or dependency)",
            self.command, self.root
        )
    }
}

impl Missing {
    fn report(reason: String) -> Missing {
        Missing { reason, check: None }
    }
}

pub type Ran<T> = std::result::Result<T, Missing>;

/// What the hook runs (items 6.3 and 13): the files the open locks hold, the
/// cases that failed at the RED, and the files of the snapshot being judged.
pub struct Locked {
    pub files: BTreeSet<String>,
    pub cases: Vec<String>,
    pub present: Vec<String>,
    /// Where the lists of item 22 are written: `git rev-parse --git-path shipcraft/tmp`.
    pub tmp: PathBuf,
}

/// Item 22: the lists the hook's suite gets, each the path of a file.
pub const LIST_VARS: [&str; 2] = ["SHIPCRAFT_CASES", "SHIPCRAFT_FILES"];

/// Runs every suite of the config in `dir` (each in its `raiz`; `copy` when
/// `dir` is a checkout copy), as one report, each after its `verifica`.
/// Missing when a `verifica` failed or a runner wrote no report: the suite did
/// not compile, or the runner broke before running.
pub fn run(dir: &Path, copy: bool, config: &Config) -> Result<Ran<Report>> {
    Ok(run_suites(dir, copy, config, None)?.map(|(report, _)| report))
}

/// Item 16a: the `[build] comando`, once, at the root of the tree being
/// judged, before the first suite; never on a copy. A build that fails is the
/// refusal `build-falhou`, with `hint` after how to go on.
pub fn build(dir: &Path, config: &Config, hint: &str) -> Result<()> {
    let Some(build) = &config.build else { return Ok(()) };
    let comando = one_line(&build.comando);
    eprintln!("shipcraft: running the build ({comando})");
    let Err(how) = run_build(&build.comando, dir)? else { return Ok(()) };
    refuse(
        "build-failed",
        format!("the build failed (`{comando}` {how})"),
        "tests import the build output; without it, old code would be judged",
        format!("run `{comando}` at the root and fix the error{hint}"),
    )
}

/// The hook's run (item 13): only the test files that hold a case that failed
/// at the RED, and only the suites that have one. With the report come the
/// failures that may block the commit: those of cases in a file that holds a
/// RED case. When shipcraft cannot tie the RED's cases to their files, every locked
/// file runs and no failure is in that set: only the RED's cases decide, and
/// the rest is the CI's. A wrong map costs time, never a false refusal.
pub fn run_red(dir: &Path, copy: bool, config: &Config, locked: &Locked) -> Result<Ran<(Report, BTreeSet<String>)>> {
    run_suites(dir, copy, config, Some(locked))
}

fn run_suites(
    dir: &Path,
    copy: bool,
    config: &Config,
    locked: Option<&Locked>,
) -> Result<Ran<(Report, BTreeSet<String>)>> {
    let mut all = Report::empty();
    let mut blocking = BTreeSet::new();
    for suite in config.suites() {
        let report_path = std::env::temp_dir().join(format!("shipcraft-junit-{}-{}.xml", std::process::id(), nanos()));
        let mut command = suite.comando.replace("{junit}", &shell_quote(&report_path.to_string_lossy()));
        let own = if suite.nome.is_empty() { String::new() } else { format!("{}:", suite.nome) };
        let mut selection = None;
        let mut lists = None;
        if let Some(locked) = locked {
            let cases: Vec<&str> = locked.cases.iter().filter_map(|case| case.strip_prefix(&own)).collect();
            if cases.is_empty() {
                continue;
            }
            let chosen = Selection::new(dir, &suite, locked, &cases);
            // Item 22.4: with `filtra = "comando"` the command runs as written.
            if suite.filtra == Filtra::Shipcraft {
                command = chosen.command(command, dir, &suite, locked, &cases);
            }
            let ids: BTreeSet<String> = cases.iter().map(|case| case.to_string()).collect();
            lists = Some((&locked.tmp, [ids, chosen.files(&dir.join(&suite.raiz), &cases).unwrap_or_default()]));
            selection = Some(chosen);
        }
        let label = if suite.nome.is_empty() { config.runner.clone().unwrap_or_default() } else { suite.nome.clone() };
        // In a refusal the suite is its `nome`, or its folder from the root.
        let name = suite.name().to_string();
        // A root that is not a folder runs nothing: no report, a refusal (rule 17).
        if !dir.join(&suite.raiz).is_dir() {
            return Ok(Err(Missing::report(format!(
                "suite {name} cannot run: root `{}` is not a directory",
                suite.shown_root()
            ))));
        }
        // The check of the whole project is the CI's (and the RED's), never
        // the hook's (item 13); when it fails there is no report.
        if let (None, Some(check)) = (locked, &suite.verifica) {
            eprintln!("shipcraft: checking the project ({label})");
            let ran = shell(check, &dir.join(&suite.raiz), copy, &[])?;
            if !ran.status.success() {
                return Ok(Err(check_failed(&name, suite.shown_root(), check, &ran)));
            }
        }
        eprintln!("shipcraft: running the suite ({label})");
        let vars = lists.map_or_else(Vec::new, |(tmp, lists)| write_lists(tmp, lists));
        let ran = shell(&command, &dir.join(&suite.raiz), copy, &vars);
        for (_, path) in &vars {
            let _ = fs::remove_file(path);
        }
        let ran = ran?;
        let report = fs::read_to_string(&report_path).ok().and_then(|xml| Report::parse(&xml));
        let _ = fs::remove_file(&report_path);
        let Some(report) = report else { return Ok(Err(missing(&name, &suite.comando, &ran))) };
        if let Some(selection) = &selection {
            let mut failures = report.cases_with(Outcome::Failed);
            failures.extend(report.cases_with(Outcome::Error));
            blocking.extend(failures.iter().filter(|case| selection.blocks(case)).map(|case| format!("{own}{case}")));
        }
        all.absorb(&suite.nome, report);
    }
    Ok(Ok((all, blocking)))
}

/// Item 16a.2: the suite, the command, and the first line it wrote on stderr
/// that is not blank; without one, how it ended.
fn missing(name: &str, command: &str, ran: &Shell) -> Missing {
    let said = match &ran.first_err {
        Some(line) => format!("wrote to stderr: {line}"),
        None => format!("{} without writing to stderr", ended(ran.status)),
    };
    Missing::report(format!("suite {name} did not write the JUnit report: `{}` {said}", one_line(command)))
}

/// Item 45: the suite, its check, how it ended, and the first line it wrote
/// that is not blank, stderr first, then stdout; without one, nothing after
/// how it ended.
fn check_failed(name: &str, root: &str, check: &str, ran: &Shell) -> Missing {
    let command = one_line(check);
    let mut reason = format!("suite {name}: the check `{command}` failed ({})", ended(ran.status));
    if let Some(line) = ran.first_err.as_ref().or(ran.first_out.as_ref()) {
        reason.push_str(&format!(": {line}"));
    }
    Missing { reason, check: Some(FailedCheck { root: root.to_string(), command }) }
}

/// Item 22.1: each list that has an entry in its own file in `tmp`, every
/// entry ending in NUL, as the variable and the file. None when writing one
/// fails: the suite then runs as if the command ignored them (rule 17).
fn write_lists(tmp: &Path, lists: [BTreeSet<String>; 2]) -> Vec<(&'static str, PathBuf)> {
    let mut vars = Vec::new();
    for (var, list) in LIST_VARS.into_iter().zip(lists) {
        if list.is_empty() {
            continue;
        }
        let path = tmp.join(format!("{}-{}-{}", var.to_lowercase(), std::process::id(), nanos()));
        let bytes: Vec<u8> = list.iter().flat_map(|entry| entry.bytes().chain([0])).collect();
        vars.push((var, path.clone()));
        if fs::create_dir_all(tmp).and_then(|()| fs::write(&path, bytes)).is_err() {
            for (_, path) in &vars {
                let _ = fs::remove_file(path);
            }
            return Vec::new();
        }
    }
    vars
}

/// Runs a build command with `sh` in `dir`, its output on stderr; on failure,
/// how it ended ("exited with 2", "killed by signal 15").
pub fn run_build(command: &str, dir: &Path) -> Result<std::result::Result<(), String>> {
    let ran = shell(command, dir, false, &[])?;
    Ok(if ran.status.success() { Ok(()) } else { Err(ended(ran.status)) })
}

fn ended(status: ExitStatus) -> String {
    match (status.code(), status.signal()) {
        (Some(code), _) => format!("exited with {code}"),
        (None, Some(signal)) => format!("killed by signal {signal}"),
        _ => "ended without an exit code".to_string(),
    }
}

fn one_line(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// How a command ran: its status and the first line of its stderr, and of
/// its stdout, that is not blank.
struct Shell {
    status: ExitStatus,
    first_err: Option<String>,
    first_out: Option<String>,
}

/// Runs `command` with `sh` in `dir`, its output on stderr; `copy` when `dir`
/// is a checkout copy; `vars`, the lists of item 22. Both streams pass
/// through and the start of each is kept.
fn shell(command: &str, dir: &Path, copy: bool, vars: &[(&str, PathBuf)]) -> Result<Shell> {
    let mut sh = Command::new("sh");
    sh.arg("-c").arg(command).current_dir(dir).stdout(Stdio::piped()).stderr(Stdio::piped());
    sh.envs(vars.iter().map(|(var, path)| (var, path)));
    if copy {
        // A test that calls git sees the copy's repository (item 14).
        for var in HOOK_GIT_ENV {
            sh.env_remove(var);
        }
    }
    let mut child = sh.spawn().map_err(|e| failed(format!("run the suite: {e}")))?;
    let scan_out = Arc::new(Mutex::new(FirstLine::default()));
    let scan_err = Arc::new(Mutex::new(FirstLine::default()));
    // Both streams pass to shipcraft's stderr; `open` is whether the last byte
    // written there left a line open.
    let open = Arc::new(Mutex::new(false));
    let (done, finished) = mpsc::channel();
    let out = child.stdout.take().map(|p| Box::new(p) as Box<dyn Read + Send>);
    let err = child.stderr.take().map(|p| Box::new(p) as Box<dyn Read + Send>);
    for (pipe, scan) in [(out, Arc::clone(&scan_out)), (err, Arc::clone(&scan_err))] {
        let Some(mut pipe) = pipe else { continue };
        let (open, done) = (Arc::clone(&open), done.clone());
        thread::spawn(move || {
            let mut buf = [0u8; 8192];
            while let Ok(n @ 1..) = pipe.read(&mut buf) {
                let mut open = open.lock().unwrap_or_else(|e| e.into_inner());
                let _ = io::stderr().write_all(&buf[..n]);
                *open = buf[n - 1] != b'\n';
                drop(open);
                scan.lock().unwrap_or_else(|e| e.into_inner()).feed(&buf[..n]);
            }
            let _ = done.send(());
        });
    }
    drop(done);
    let status = child.wait().map_err(|e| failed(format!("run the suite: {e}")))?;
    // A process the command left running may hold a stream open: a moment, not forever.
    let deadline = Instant::now() + Duration::from_secs(2);
    while finished.recv_timeout(deadline.saturating_duration_since(Instant::now())).is_ok() {}
    // What shipcraft writes next (a refusal's three lines) starts on its own line.
    let mut open = open.lock().unwrap_or_else(|e| e.into_inner());
    if *open {
        let _ = io::stderr().write_all(b"\n");
        *open = false;
    }
    let first_err = scan_err.lock().unwrap_or_else(|e| e.into_inner()).first();
    let first_out = scan_out.lock().unwrap_or_else(|e| e.into_inner()).first();
    Ok(Shell { status, first_err, first_out })
}

/// The first line of a stream that is not blank, found as the bytes arrive
/// (item 16a.2): blank lines are dropped, and only the line being read is
/// kept, up to `FirstLine::MAX` bytes.
#[derive(Default)]
struct FirstLine {
    line: Vec<u8>,
    found: Option<String>,
}

impl FirstLine {
    const MAX: usize = 4096;

    fn feed(&mut self, bytes: &[u8]) {
        for &b in bytes {
            if self.found.is_some() {
                return;
            }
            if b == b'\n' {
                self.end();
            } else if self.line.is_empty() && b.is_ascii_whitespace() {
                // Leading spaces are never kept.
            } else if self.line.len() < Self::MAX {
                self.line.push(b);
            } else {
                // Full and still blank (wide spaces): dropped, and the scan
                // goes on; full and not blank: the rest of the line is not needed.
                let valid = std::str::from_utf8(&self.line).map_or_else(|e| e.valid_up_to(), str::len);
                if String::from_utf8_lossy(&self.line[..valid]).trim().is_empty() {
                    self.line.drain(..valid);
                    self.line.push(b);
                }
            }
        }
    }

    /// The line read so far ends: it is the one when it is not blank.
    fn end(&mut self) {
        let text = String::from_utf8_lossy(&self.line).trim().to_string();
        self.line.clear();
        if !text.is_empty() {
            self.found = Some(text);
        }
    }

    /// The line, counting a last one with no newline.
    fn first(&mut self) -> Option<String> {
        if self.found.is_none() {
            self.end();
        }
        self.found.clone()
    }
}

/// The test files the hook runs in one suite, and how its cases name them.
struct Selection {
    /// None when shipcraft cannot tie the RED's cases to their files.
    map: Option<Map>,
    /// The files to run, relative to the suite's root: those that hold a RED
    /// case, or, without a map, every locked file.
    red: BTreeSet<String>,
    /// Go: the tests each locked file declares.
    go: BTreeMap<String, Vec<String>>,
}

impl Selection {
    fn new(dir: &Path, suite: &Suite, locked: &Locked, cases: &[&str]) -> Selection {
        let prefix = suite.prefix();
        let locked_files = of_suite(suite, &locked.files.iter().cloned().collect::<Vec<_>>());
        let root = dir.join(&suite.raiz);
        let go: BTreeMap<String, Vec<String>> = locked_files
            .iter()
            .filter(|file| file.ends_with(".go"))
            .map(|file| (file.clone(), go_tests(&root.join(file))))
            .collect();
        let map = if is_go(&suite.comando) {
            go_module(dir, &root).map(|module| Map::Go { module, tests: go.clone() }).filter(|map| map.covers(cases))
        } else {
            let present: Vec<String> =
                locked.present.iter().filter_map(|path| path.strip_prefix(&prefix)).map(str::to_string).collect();
            let names = |python| Map::names(python, &prefix, &locked_files, &present, cases);
            if ["pytest", "vitest", "jest"].iter().any(|r| suite.comando.contains(r)) {
                names(suite.comando.contains("pytest"))
            } else {
                // Item 22: a runner shipcraft does not know names a file one way or
                // the other; the one that ties the cases, never both.
                match (names(true), names(false)) {
                    (Some(map), None) | (None, Some(map)) => Some(map),
                    _ => None,
                }
            }
        };
        let red = match &map {
            Some(map) => cases.iter().flat_map(|case| map.holders(case)).collect(),
            None => locked_files.into_iter().collect(),
        };
        Selection { map, red, go }
    }

    /// Item 22.1: the absolute paths, from `root`, of the files that hold the
    /// RED's cases; None unless the map ties every case to a file.
    fn files(&self, root: &Path, cases: &[&str]) -> Option<BTreeSet<String>> {
        self.map.as_ref().filter(|map| map.covers(cases))?;
        let absolute = |rel: &String| {
            let path = root.join(rel);
            fs::canonicalize(&path).unwrap_or(path).to_string_lossy().into_owned()
        };
        Some(self.red.iter().map(absolute).collect())
    }

    /// Whether a failure in the hook's report blocks: its case is in a file
    /// that holds a RED case.
    fn blocks(&self, case: &str) -> bool {
        self.map.as_ref().is_some_and(|map| map.holders(case).iter().any(|file| self.red.contains(file)))
    }

    /// The suite's `command` with the arguments, appended (so they reach its
    /// last runner), that keep the run to the `red` files. The filter is by
    /// file, never by case name: names carry spaces, `+`, brackets and `.*`.
    /// The other locked files cannot change while the lock is open, and run in
    /// the CI. In pytest, vitest and jest every other test file of the suite is
    /// left out, by its absolute path (never from a root the runner may set
    /// elsewhere: jest's rootDir, vitest's root); Go compiles a package as a
    /// whole, so there each `./...` of the command becomes the packages of
    /// those files, and their tests are named with `-run`.
    fn command(&self, mut command: String, dir: &Path, suite: &Suite, locked: &Locked, cases: &[&str]) -> String {
        let runner = &suite.comando;
        let root = dir.join(&suite.raiz);
        let others: Vec<String> =
            of_suite(suite, &locked.present).into_iter().filter(|rel| !self.red.contains(rel)).collect();
        let absolute = |rel: &String| -> String {
            let path = root.join(rel);
            fs::canonicalize(&path).unwrap_or(path).to_string_lossy().into_owned()
        };
        if ["pytest", "vitest", "jest"].iter().any(|r| runner.contains(r)) {
            // A file the command names runs despite the exclusions: out with it.
            let left_out: BTreeSet<String> = others.iter().map(absolute).collect();
            command = without_files(&command, &root, &left_out);
        }
        let args: Vec<String> = if runner.contains("pytest") {
            // conftest.py still loads: it can skip or deselect the RED's cases.
            let module = |rel: &&String| rel.ends_with(".py") && rel.rsplit('/').next() != Some("conftest.py");
            let ignore = others.iter().filter(module).map(|f| format!("--ignore={}", shell_quote(&absolute(f))));
            // A collection error outside the RED's files (a file a conftest or
            // a plugin brings in) must not stop the RED's cases (item 13).
            ignore.chain(["--continue-on-collection-errors".to_string()]).collect()
        } else if runner.contains("vitest") {
            let glob = |f: &String| glob_escape(&absolute(f));
            let exclude = others.iter().map(|f| format!("--exclude={}", shell_quote(&glob(f))));
            // Item 51: a workspace's projects ignore `--exclude`; a positional
            // path is vitest's file filter, so each RED file is named too, in
            // the same form as SHIPCRAFT_FILES (none when a case has no file).
            let named = self.files(&root, cases).unwrap_or_default().into_iter().map(|f| shell_quote(&f));
            exclude.chain(named).collect()
        } else if runner.contains("jest") {
            let pattern = |f: &String| format!("^{}$", regex_escape(&absolute(f)));
            others.iter().map(|f| format!("--testPathIgnorePatterns={}", shell_quote(&pattern(f)))).collect()
        } else if is_go(runner) {
            let mut names: Vec<String> = cases.iter().map(|case| go_top_name(case).to_string()).collect();
            names.extend(self.red.iter().filter_map(|file| self.go.get(file)).flatten().cloned());
            names.sort();
            names.dedup();
            // The same test name in another package is another test, and a
            // package that does not build is the CI's (item 13): every `./...`
            // of the command (`go vet` too) becomes the packages of those files.
            if command.contains("./...") {
                let packages: BTreeSet<String> = self
                    .red
                    .iter()
                    .filter(|file| file.ends_with(".go") && !file.split('/').any(|part| part == "testdata"))
                    .map(|file| go_dir(file).map_or(".".to_string(), |d| format!("./{d}")))
                    .collect();
                let packages: Vec<String> = packages.iter().map(|p| shell_quote(p)).collect();
                command = command.replace("./...", &packages.join(" "));
            }
            vec![format!("-run {}", shell_quote(&format!("^({})$", names.join("|"))))]
        } else {
            Vec::new()
        };
        args.iter().fold(command, |command, a| format!("{command} {a}"))
    }
}

/// `command` without the words that name one of the `left_out` files (by
/// absolute path, resolved from `root`): a test file named in the command runs
/// whatever the runner's exclusions say. Only plain words are dropped; a
/// command whose quotes do not close is left as it is.
fn without_files(command: &str, root: &Path, left_out: &BTreeSet<String>) -> String {
    // The words, as byte ranges, and whether each is plain (no quote, escape
    // or shell character).
    let mut words: Vec<(usize, usize, bool)> = Vec::new();
    let mut quote: Option<char> = None;
    let mut start: Option<(usize, bool)> = None;
    let mut chars = command.char_indices().peekable();
    while let Some((at, c)) = chars.next() {
        match quote {
            Some(q) if c == q => quote = None,
            Some('"') if c == '\\' => {
                chars.next();
            }
            Some(_) => {}
            None if c.is_whitespace() => {
                if let Some((from, plain)) = start.take() {
                    words.push((from, at, plain));
                }
            }
            None => {
                let plain = c.is_alphanumeric() || "._/-+@%,:".contains(c);
                if c == '\'' || c == '"' {
                    quote = Some(c);
                } else if c == '\\' {
                    chars.next();
                }
                match &mut start {
                    Some((_, p)) => *p &= plain,
                    None => start = Some((at, plain)),
                }
            }
        }
    }
    if quote.is_some() {
        return command.to_string();
    }
    if let Some((from, plain)) = start {
        words.push((from, command.len(), plain));
    }
    let named = |word: &str| {
        let path = root.join(word);
        path.is_file() && left_out.contains(&*fs::canonicalize(&path).unwrap_or(path).to_string_lossy())
    };
    let mut out = String::new();
    let mut last = 0;
    for (from, to, plain) in words {
        if plain && named(&command[from..to]) {
            out.push_str(&command[last..from]);
            last = to;
        }
    }
    out.push_str(&command[last..]);
    out
}

/// How the cases of one suite name their test files, each found exactly by
/// the case's JUnit classname (item 13).
enum Map {
    /// pytest names a file by its dotted path from its rootdir (plus the
    /// test's class), vitest and jest by its path from their root. `names`
    /// holds each locked file under that name; `strip` is a leading part
    /// every classname carries (`--junit-prefix`), or empty.
    Names { python: bool, strip: String, names: BTreeMap<String, Vec<String>> },
    /// Go: a file holds a case when its package (the module plus the file's
    /// folder) is the classname and it declares the case's test.
    Go { module: String, tests: BTreeMap<String, Vec<String>> },
}

impl Map {
    /// The map from the RED's failing cases. The runner's root, which shipcraft does
    /// not read, is the one folder (the suite's, a parent, or a folder of the
    /// tests) from which every RED case names a locked file, or comes from a
    /// file that is not a test (a doctest, which does not count). None when
    /// no folder or more than one does.
    fn names(python: bool, prefix: &str, files: &[String], present: &[String], cases: &[&str]) -> Option<Map> {
        let mut roots: BTreeSet<String> = BTreeSet::from([String::new()]);
        let mut dir = prefix.trim_end_matches('/');
        while !dir.is_empty() {
            roots.insert(format!("{dir}/"));
            dir = dir.rsplit_once('/').map_or("", |(parent, _)| parent);
        }
        for rel in files {
            let path = format!("{prefix}{rel}");
            roots.extend(path.match_indices('/').map(|(at, _)| path[..=at].to_string()));
        }
        let separator = if python { '.' } else { '/' };
        let mut strips = vec![String::new()];
        let firsts: BTreeSet<Option<&str>> = cases
            .iter()
            .map(|case| {
                case.split_once("::").and_then(|(class, _)| class.split_once(separator)).map(|(first, _)| first)
            })
            .collect();
        if let [Some(first)] = firsts.into_iter().collect::<Vec<_>>()[..] {
            strips.push(format!("{first}{separator}"));
        }
        let products: Vec<String> = present.iter().filter(|rel| !files.contains(rel)).cloned().collect();
        // The classname as it is first; a constant leading part is cut only
        // when no folder fits without the cut.
        for strip in &strips {
            let mut found: Option<(Map, BTreeSet<String>)> = None;
            for root in &roots {
                let map = Map::Names { python, strip: strip.clone(), names: named(python, prefix, root, files) };
                let product =
                    Map::Names { python, strip: strip.clone(), names: named(python, prefix, root, &products) };
                let mut red = BTreeSet::new();
                let mut fits = true;
                for case in cases {
                    let holders = map.holders(case);
                    if holders.is_empty() && product.holders(case).is_empty() {
                        fits = false;
                        break;
                    }
                    red.extend(holders);
                }
                if !fits || red.is_empty() {
                    continue;
                }
                match &found {
                    Some((_, other)) if *other != red => return None,
                    Some(_) => {}
                    None => found = Some((map, red)),
                }
            }
            if let Some((map, _)) = found {
                return Some(map);
            }
        }
        None
    }

    /// Every case has a file.
    fn covers(&self, cases: &[&str]) -> bool {
        cases.iter().all(|case| !self.holders(case).is_empty())
    }

    /// The files that hold `case`, relative to the suite's root.
    fn holders(&self, case: &str) -> Vec<String> {
        let Some((class, _)) = case.split_once("::") else { return Vec::new() };
        match self {
            Map::Names { python, strip, names } => {
                let Some(class) = class.strip_prefix(strip.as_str()) else { return Vec::new() };
                // pytest adds the test's class to the module: `pkg.test_x.TestY`.
                let mut keys = vec![class];
                if *python {
                    keys.extend(class.match_indices('.').map(|(at, _)| &class[..at]));
                }
                keys.iter().filter_map(|key| names.get(*key)).flatten().cloned().collect()
            }
            Map::Go { module, tests } => tests
                .iter()
                .filter(|(rel, _)| go_dir(rel).map_or(module.clone(), |dir| format!("{module}/{dir}")) == class)
                .filter(|(_, names)| names.iter().any(|name| name == go_top_name(case)))
                .map(|(rel, _)| rel.clone())
                .collect(),
        }
    }
}

/// The name of each file (relative to the suite's root) from `root`: its
/// dotted module for pytest, its path for vitest and jest.
fn named(python: bool, prefix: &str, root: &str, files: &[String]) -> BTreeMap<String, Vec<String>> {
    let mut names: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for rel in files {
        let path = format!("{prefix}{rel}");
        let Some(path) = path.strip_prefix(root) else { continue };
        let name = if python { path.strip_suffix(".py").map(|m| m.replace('/', ".")) } else { Some(path.to_string()) };
        if let Some(name) = name {
            names.entry(name).or_default().push(rel.clone());
        }
    }
    names
}

/// The test files among `paths`, relative to the suite's root.
fn of_suite(suite: &Suite, paths: &[String]) -> Vec<String> {
    let prefix = suite.prefix();
    paths
        .iter()
        .filter_map(|path| path.strip_prefix(&prefix))
        .filter(|rel| suite.globs.iter().any(|g| glob::matches(g, rel)))
        .map(str::to_string)
        .collect()
}

fn is_go(runner: &str) -> bool {
    runner.contains("gotestsum") || runner.contains("go test")
}

/// The top-level test of a Go case (`pkg::TestX/sub` is `TestX`).
fn go_top_name(case: &str) -> &str {
    let name = case.rsplit("::").next().unwrap_or(case);
    name.split('/').next().unwrap_or(name)
}

/// The directory of a Go file, None at the suite's root.
fn go_dir(rel: &str) -> Option<&str> {
    rel.rsplit_once('/').map(|(dir, _)| dir)
}

/// The import path of the suite's root (item 32): the `Module.Path` of the
/// nearest `go.mod` at the root or above it, up to the repository's root
/// `top`, as `go mod edit -json` reads it, plus the folders from there down.
/// None when there is no module (rule 17: the hook runs as without one).
fn go_module(top: &Path, root: &Path) -> Option<String> {
    let mut below: Vec<String> = Vec::new();
    let mut dir = root.to_path_buf();
    while !dir.join("go.mod").is_file() {
        if dir == top {
            return None;
        }
        below.push(dir.file_name()?.to_str()?.to_string());
        dir = dir.parent()?.to_path_buf();
    }
    let out = Command::new("go").args(["mod", "edit", "-json", "go.mod"]).current_dir(&dir).output().ok()?;
    if !out.status.success() {
        return None;
    }
    let json: serde_json::Value = serde_json::from_slice(&out.stdout).ok()?;
    let module = json.get("Module")?.get("Path")?.as_str().filter(|path| !path.is_empty())?;
    Some(below.iter().rev().fold(module.to_string(), |path, name| format!("{path}/{name}")))
}

/// The tests, fuzz tests and examples a Go test file declares.
fn go_tests(path: &Path) -> Vec<String> {
    let Ok(text) = fs::read_to_string(path) else { return Vec::new() };
    text.lines()
        .filter_map(|line| line.strip_prefix("func "))
        .filter(|rest| ["Test", "Fuzz", "Example"].iter().any(|kind| rest.starts_with(kind)))
        .filter_map(|rest| rest.split('(').next())
        .map(|name| name.trim().to_string())
        .filter(|name| !name.is_empty() && name.chars().all(|c| c.is_alphanumeric() || c == '_'))
        .collect()
}

fn glob_escape(text: &str) -> String {
    text.chars().fold(String::new(), |mut out, c| {
        if "\\*?[]{}()!".contains(c) {
            out.push('\\');
        }
        out.push(c);
        out
    })
}

fn regex_escape(text: &str) -> String {
    text.chars().fold(String::new(), |mut out, c| {
        if "\\.^$|?*+()[]{}".contains(c) {
            out.push('\\');
        }
        out.push(c);
        out
    })
}

/// Quotes a word for `sh`: inside single quotes only `'` itself needs care,
/// closed and reopened around a double-quoted `'`.
pub fn shell_quote(word: &str) -> String {
    format!("'{}'", word.replace('\'', "'\"'\"'"))
}

fn nanos() -> u128 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_end_each_entry_in_nul_and_vanish_when_unwritable() {
        let tmp = std::env::temp_dir().join(format!("shipcraft-listas-{}", nanos()));
        let ids = BTreeSet::from(["b::x\ny".to_string(), "a::z".to_string()]);
        let vars = write_lists(&tmp, [ids, BTreeSet::new()]);
        assert_eq!(vars.len(), 1);
        assert_eq!(vars[0].0, "SHIPCRAFT_CASES");
        assert_eq!(fs::read(&vars[0].1).unwrap(), b"a::z\0b::x\ny\0");
        let _ = fs::remove_dir_all(&tmp);
        let blocked = tmp.with_extension("arquivo");
        fs::write(&blocked, "").unwrap();
        assert!(write_lists(&blocked, [BTreeSet::from(["a".to_string()]), BTreeSet::new()]).is_empty());
        let _ = fs::remove_file(&blocked);
    }

    #[test]
    fn go_module_comes_from_the_nearest_go_mod_as_go_reads_it() {
        let top = std::env::temp_dir().join(format!("shipcraft-go-module-{}", nanos()));
        let root = top.join("services/api");
        fs::create_dir_all(&root).unwrap();
        assert_eq!(go_module(&top, &root), None);
        fs::write(top.join("go.mod"), "// c\nmodule \"example.com/m\" // x\n\ngo 1.22\n").unwrap();
        assert_eq!(go_module(&top, &root).as_deref(), Some("example.com/m/services/api"));
        assert_eq!(go_module(&top, &top).as_deref(), Some("example.com/m"));
        fs::write(root.join("go.mod"), "module\n").unwrap();
        assert_eq!(go_module(&top, &root), None);
        fs::remove_dir_all(&top).unwrap();
    }
}
