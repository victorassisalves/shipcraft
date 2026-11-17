//! Item 115: `pr` warns about new npm dependencies. The names a PR adds to a
//! `package.json` (registry versions only) are asked of the npm registry, one
//! `curl` call each; a name the registry does not have, or first published
//! fewer than `[pr] new_dependency_days` days ago, gets a line in the PR
//! body's size block and on stdout. A warning only: nothing here is an error.

use crate::config::{Config, NewDependencies};
use crate::git::Repo;
use crate::processo::{self, Captured};
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::OsStr;
use std::process::{Command, Stdio};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

/// The four top-level sections whose keys are dependency names.
const SECTIONS: [&str; 4] = ["dependencies", "devDependencies", "optionalDependencies", "peerDependencies"];
/// Specs npm does not resolve from the registry.
const NOT_REGISTRY: [&str; 12] = [
    "workspace:",
    "file:",
    "link:",
    "portal:",
    "npm:",
    "git:",
    "git+",
    "github:",
    "gitlab:",
    "bitbucket:",
    "http:",
    "https:",
];
const REGISTRY: &str = "https://registry.npmjs.org/";
/// npm refuses longer names.
const NAME_MAX: usize = 214;
const CURL_LIMIT: Duration = Duration::from_secs(15);
const DAY: i64 = 86_400;
pub const GIT_LINE: &str = "New dependencies not checked: git could not read the package.json files.";

/// What the check gives `pr`: the lines (for the block and stdout, without
/// the `shipcraft: ` prefix) and the row's three numbers, `None` when off or
/// when git failed (then each field is `null`).
pub struct Check {
    pub lines: Vec<String>,
    pub counts: Option<Counts>,
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub struct Counts {
    pub new: u64,
    pub warnings: u64,
    pub not_checked: u64,
}

/// The check, from the merge base and head of item 103's count.
pub fn check(repo: &Repo, config: &Config, base: &str, head: &str) -> Check {
    if config.pr.new_dependencies == NewDependencies::Off {
        return Check { lines: Vec::new(), counts: None };
    }
    let Ok(list) = new_names(repo, base, head) else {
        return Check { lines: vec![GIT_LINE.to_string()], counts: None };
    };
    if list.is_empty() {
        return Check { lines: Vec::new(), counts: Some(Counts { new: 0, warnings: 0, not_checked: 0 }) };
    }
    let now = now_secs();
    judge(&list, now, config.pr.new_dependency_days.0, |name| ask(repo, name))
}

/// The registry's answer for one name.
#[derive(Debug, PartialEq, Eq)]
pub enum Answer {
    NotFound,
    /// The first publication, in seconds since the epoch.
    Created(i64),
    Failure(String),
}

/// Point 2 and 3 over the list: one answer per name, in order, the first
/// failure stopping the rest; a name npm cannot hold is not found without a call.
fn judge(list: &[(String, String)], now: i64, days: u64, mut ask: impl FnMut(&str) -> Answer) -> Check {
    let n = list.len() as u64;
    let mut lines = Vec::new();
    let mut not_checked = None;
    for (i, (name, path)) in list.iter().enumerate() {
        let answer = if valid_name(name) { ask(name) } else { Answer::NotFound };
        match answer {
            Answer::NotFound => lines.push(not_found_line(name, path)),
            Answer::Created(created) => {
                let age = age_days(now, created);
                if age < days {
                    lines.push(young_line(age, name, path));
                }
            }
            Answer::Failure(reason) => {
                not_checked = Some((n - i as u64, reason));
                break;
            }
        }
    }
    let warnings = lines.len() as u64;
    let k = not_checked.as_ref().map_or(0, |(k, _)| *k);
    if let Some((k, reason)) = &not_checked {
        lines.push(not_checked_line(*k, n, reason));
    }
    Check { lines, counts: Some(Counts { new: n, warnings, not_checked: k }) }
}

pub fn not_found_line(name: &str, path: &str) -> String {
    format!("New dependency not in the npm registry: {name} ({path}). Check the name: anyone can publish a package under a name that does not exist yet.")
}

pub fn young_line(days: u64, name: &str, path: &str) -> String {
    format!(
        "New dependency first published {days} day(s) ago on npm: {name} ({path}). Check it is the package you meant."
    )
}

pub fn not_checked_line(k: u64, n: u64, reason: &str) -> String {
    format!("New dependencies not checked: {k} of {n}; the npm registry could not be read ({reason}).")
}

// --- Point 1: the new names, from git -------------------------------------------------

/// The new names of every manifest, once each in byte order, with the first
/// manifest path (in byte order) where each is new. `Err` when git failed.
fn new_names(repo: &Repo, base: &str, head: &str) -> Result<Vec<(String, String)>, ()> {
    let diff = git(
        repo,
        &[
            OsStr::new("diff"),
            OsStr::new("--name-only"),
            OsStr::new("-z"),
            OsStr::new("--no-renames"),
            OsStr::new("--diff-filter=AM"),
            OsStr::new(base),
            OsStr::new(head),
        ],
    )?;
    let mut manifests = Vec::new();
    for path in manifest_paths(&diff) {
        let Some(head_file) = read(repo, head, &path)? else { continue };
        let Some(base_file) = read(repo, base, &path)? else { continue };
        let head_names = match head_file {
            File::Absent => BTreeSet::new(),
            File::Text(bytes) => match registry_names(&bytes) {
                Some(names) => names,
                None => continue,
            },
        };
        let base_names = match base_file {
            File::Absent => BTreeSet::new(),
            File::Text(bytes) => match registry_names(&bytes) {
                Some(names) => names,
                None => continue,
            },
        };
        manifests.push((path, new_in(&head_names, &base_names)));
    }
    Ok(attribute(&manifests))
}

/// The list from each manifest's new names, the manifests in byte order.
fn attribute(manifests: &[(String, BTreeSet<String>)]) -> Vec<(String, String)> {
    let mut list: BTreeMap<String, String> = BTreeMap::new();
    for (path, names) in manifests {
        for name in names {
            list.entry(name.clone()).or_insert_with(|| path.clone());
        }
    }
    list.into_iter().collect()
}

/// The names that count at the head and not at the base.
fn new_in(head: &BTreeSet<String>, base: &BTreeSet<String>) -> BTreeSet<String> {
    head.difference(base).cloned().collect()
}

enum File {
    Absent,
    Text(Vec<u8>),
}

/// One manifest at `commit`: `Ok(None)` when it is skipped whole (not a
/// regular file there), `Err` when git failed.
fn read(repo: &Repo, commit: &str, path: &str) -> Result<Option<File>, ()> {
    let out =
        git(repo, &[OsStr::new("ls-tree"), OsStr::new("-z"), OsStr::new(commit), OsStr::new("--"), OsStr::new(path)])?;
    match ls_tree_entry(&out)? {
        Entry::Absent => Ok(Some(File::Absent)),
        Entry::Other => Ok(None),
        Entry::Blob(oid) => {
            let bytes = git(repo, &[OsStr::new("cat-file"), OsStr::new("blob"), OsStr::new(&oid)])?;
            Ok(Some(File::Text(bytes)))
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
enum Entry {
    Absent,
    Blob(String),
    /// A link, a folder, a submodule, or more than one entry.
    Other,
}

/// `git ls-tree -z` for one path: `<mode> <type> <oid>\t<path>\0` per entry.
/// An entry that does not read so is git's output not read (`Err`).
fn ls_tree_entry(out: &[u8]) -> Result<Entry, ()> {
    if out.is_empty() {
        return Ok(Entry::Absent);
    }
    let Some(records) = out.strip_suffix(b"\0") else { return Err(()) };
    let mut entries = Vec::new();
    for record in records.split(|b| *b == 0) {
        let tab = record.iter().position(|b| *b == b'\t').ok_or(())?;
        let meta = std::str::from_utf8(&record[..tab]).map_err(|_| ())?;
        let fields: Vec<&str> = meta.split(' ').collect();
        let [mode, kind, oid] = fields[..] else { return Err(()) };
        entries.push((mode.to_string(), kind.to_string(), oid.to_string()));
    }
    Ok(match &entries[..] {
        [(mode, kind, oid)] if kind == "blob" && (mode == "100644" || mode == "100755") => Entry::Blob(oid.clone()),
        _ => Entry::Other,
    })
}

/// Git in the repository root, paths taken literally; `Err` when it cannot
/// start, exits non-zero, ends by a signal or its output cannot be read.
fn git(repo: &Repo, args: &[&OsStr]) -> Result<Vec<u8>, ()> {
    let out = Command::new("git")
        .arg("-C")
        .arg(repo.root())
        .arg("--literal-pathspecs")
        .args(args)
        .stdin(Stdio::null())
        .output()
        .map_err(|_| ())?;
    if !out.status.success() {
        return Err(());
    }
    Ok(out.stdout)
}

/// The manifests among the paths `git diff --name-only -z` printed: last
/// component exactly `package.json`, no component `node_modules`, valid
/// UTF-8 with no control character; in byte order.
fn manifest_paths(out: &[u8]) -> Vec<String> {
    let mut paths: Vec<String> = out
        .split(|b| *b == 0)
        .filter(|raw| !raw.is_empty())
        .filter_map(|raw| std::str::from_utf8(raw).ok())
        .filter(|path| !has_control(path))
        .filter(|path| {
            let parts: Vec<&str> = path.split('/').collect();
            parts.last() == Some(&"package.json") && !parts.contains(&"node_modules")
        })
        .map(str::to_string)
        .collect();
    paths.sort();
    paths.dedup();
    paths
}

/// U+0000 to U+001F, U+007F, U+2028 and U+2029.
fn has_control(text: &str) -> bool {
    text.chars().any(|c| c <= '\u{1f}' || c == '\u{7f}' || c == '\u{2028}' || c == '\u{2029}')
}

/// The names that count in a manifest file, or `None` when it is skipped
/// whole (not UTF-8, not JSON, not an object), after one leading BOM.
fn registry_names(bytes: &[u8]) -> Option<BTreeSet<String>> {
    let text = std::str::from_utf8(bytes).ok()?;
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let value: serde_json::Value = serde_json::from_str(text).ok()?;
    let object = value.as_object()?;
    let mut names = BTreeSet::new();
    for section in SECTIONS {
        let Some(deps) = object.get(section).and_then(|v| v.as_object()) else { continue };
        for (name, spec) in deps {
            if has_control(name) {
                continue;
            }
            if spec.as_str().is_some_and(counts) {
                names.insert(name.clone());
            }
        }
    }
    Some(names)
}

/// A spec npm resolves from the registry: none of the other kinds' prefixes, and no `/`.
fn counts(spec: &str) -> bool {
    !NOT_REGISTRY.iter().any(|prefix| spec.starts_with(prefix)) && !spec.contains('/')
}

// --- Point 2: the registry ------------------------------------------------------------

/// `^(@[A-Za-z0-9~-][A-Za-z0-9._~-]*/)?[A-Za-z0-9~-][A-Za-z0-9._~-]*$`, at most 214 bytes.
fn valid_name(name: &str) -> bool {
    fn part(text: &str) -> bool {
        let first = |b: u8| b.is_ascii_alphanumeric() || b == b'~' || b == b'-';
        let rest = |b: u8| first(b) || b == b'.' || b == b'_';
        let bytes = text.as_bytes();
        !bytes.is_empty() && first(bytes[0]) && bytes[1..].iter().all(|b| rest(*b))
    }
    if name.len() > NAME_MAX {
        return false;
    }
    match name.strip_prefix('@') {
        Some(scoped) => match scoped.split_once('/') {
            Some((scope, pkg)) => part(scope) && part(pkg),
            None => false,
        },
        None => part(name),
    }
}

/// The registry URL of a name: a scoped name's `/` is written `%2F`, every other byte as it is.
fn url(name: &str) -> String {
    format!("{REGISTRY}{}", name.replace('/', "%2F"))
}

/// curl's arguments for a name, exactly and in this order.
fn curl_args(name: &str) -> Vec<String> {
    let mut args: Vec<String> = [
        "--disable",
        "--silent",
        "--show-error",
        "--compressed",
        "--max-time",
        "10",
        "--header",
        "Accept: application/json",
        "--write-out",
        "\n%{http_code}",
    ]
    .iter()
    .map(|a| a.to_string())
    .collect();
    args.push(url(name));
    args
}

/// One call to the registry for a name, through `curl` on `PATH`.
fn ask(repo: &Repo, name: &str) -> Answer {
    let mut cmd = Command::new("curl");
    cmd.args(curl_args(name)).current_dir(repo.root()).stdin(Stdio::null()).stderr(Stdio::null());
    curl_answer(processo::run_capture(&mut cmd, CURL_LIMIT))
}

/// How curl ended, read as the registry's answer.
fn curl_answer(end: Captured) -> Answer {
    match end {
        Captured::NotStarted => Answer::Failure("curl could not start".into()),
        Captured::TimedOut | Captured::Exited(28, _) => Answer::Failure("timed out".into()),
        Captured::Signal(n) => Answer::Failure(format!("curl failed (signal {n})")),
        Captured::Exited(0, Some(out)) => read_answer(&out),
        Captured::Exited(0, None) | Captured::WaitFailed => Answer::Failure("curl failed (output not read)".into()),
        Captured::Exited(code, _) => Answer::Failure(format!("curl failed (exit {code})")),
    }
}

const UNREADABLE: &str = "unreadable answer from the registry";

/// curl's stdout after exit 0: the body, `\n`, three ASCII digits.
fn read_answer(out: &[u8]) -> Answer {
    let unreadable = || Answer::Failure(UNREADABLE.into());
    let len = out.len();
    if len < 4 || out[len - 4] != b'\n' || !out[len - 3..].iter().all(u8::is_ascii_digit) {
        return unreadable();
    }
    let status = std::str::from_utf8(&out[len - 3..]).unwrap_or_default();
    match status {
        "404" => Answer::NotFound,
        "200" => created_of(&out[..len - 4]).map_or_else(unreadable, Answer::Created),
        other => Answer::Failure(format!("the registry answered {other}")),
    }
}

/// `time.created` of a `200` body, in seconds since the epoch.
fn created_of(body: &[u8]) -> Option<i64> {
    let text = std::str::from_utf8(body).ok()?;
    let value: serde_json::Value = serde_json::from_str(text).ok()?;
    let created = value.as_object()?.get("time")?.as_object()?.get("created")?.as_str()?;
    utc_secs(created)
}

/// `YYYY-MM-DDTHH:MM:SS`, optionally `.` and 1 to 9 digits, then `Z`, a real
/// UTC date, as whole seconds since the epoch (the fraction dropped).
fn utc_secs(text: &str) -> Option<i64> {
    let b = text.as_bytes();
    if b.len() < 20 {
        return None;
    }
    let digits = |range: std::ops::Range<usize>| -> Option<i64> {
        let part = &b[range];
        part.iter().all(u8::is_ascii_digit).then(|| part.iter().fold(0i64, |n, d| n * 10 + i64::from(d - b'0')))
    };
    let shape = b[4] == b'-' && b[7] == b'-' && b[10] == b'T' && b[13] == b':' && b[16] == b':';
    if !shape {
        return None;
    }
    let (year, month, day) = (digits(0..4)?, digits(5..7)?, digits(8..10)?);
    let (hour, minute, second) = (digits(11..13)?, digits(14..16)?, digits(17..19)?);
    let tail = &b[19..];
    let tail = match tail.strip_prefix(b".") {
        Some(fraction) => {
            let n = fraction.iter().take_while(|c| c.is_ascii_digit()).count();
            if !(1..=9).contains(&n) {
                return None;
            }
            &fraction[n..]
        }
        None => tail,
    };
    if tail != b"Z" {
        return None;
    }
    if !(1..=12).contains(&month) || day < 1 || day > days_in_month(year, month) {
        return None;
    }
    if hour > 23 || minute > 59 || second > 59 {
        return None;
    }
    Some(days_from_civil(year, month, day) * DAY + hour * 3600 + minute * 60 + second)
}

fn days_in_month(year: i64, month: i64) -> i64 {
    match month {
        2 if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    }
}

/// Days since 1970-01-01 of a proleptic Gregorian date.
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let y = if month <= 2 { year - 1 } else { year };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (month + 9) % 12;
    let doy = (153 * mp + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// Whole days, rounded down, from `created` to `now`; a future time is 0.
fn age_days(now: i64, created: i64) -> u64 {
    if created >= now {
        0
    } else {
        ((now - created) / DAY) as u64
    }
}

/// The system clock, in whole seconds since the epoch.
fn now_secs() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(d) => d.as_secs() as i64,
        Err(e) => -(e.duration().as_secs() as i64),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn set(names: &[&str]) -> BTreeSet<String> {
        names.iter().map(|n| n.to_string()).collect()
    }

    #[test]
    fn manifest_paths_are_package_json_files_outside_node_modules() {
        let out = b"b/package.json\0package.json\0Package.json\0a/package.json.bak\0node_modules/x/package.json\0x/node_modules/package.json\0a\x01b/package.json\0c\xe2\x80\xa8/package.json\0\xff/package.json\0my_node_modules/package.json\0";
        assert_eq!(manifest_paths(out), ["b/package.json", "my_node_modules/package.json", "package.json"]);
        assert!(manifest_paths(b"").is_empty());
    }

    #[test]
    fn registry_specs_are_filtered() {
        for spec in ["^1.2.0", "1.2.3", "latest", "*", "", ">=1 <2", "next"] {
            assert!(counts(spec), "{spec}");
        }
        for spec in [
            "workspace:*",
            "file:../core",
            "link:../x",
            "portal:../x",
            "npm:other@1",
            "git://x",
            "git+ssh://x",
            "github:a/b",
            "gitlab:a/b",
            "bitbucket:a/b",
            "http://x",
            "https://x",
            "user/repo",
            "./pkg",
        ] {
            assert!(!counts(spec), "{spec}");
        }
    }

    #[test]
    fn names_come_from_the_four_sections() {
        let text = br#"{"dependencies": {"a": "^1", "w": "workspace:*", "n": 1, "c\u0001": "1"},
            "devDependencies": {"b": "1"}, "optionalDependencies": {"o": "*"},
            "peerDependencies": {"p": ""}, "bundledDependencies": {"z": "1"}, "scripts": {"s": "1"}}"#;
        assert_eq!(registry_names(text).unwrap(), set(&["a", "b", "o", "p"]));
        assert_eq!(registry_names(b"{\"dependencies\": [\"a\"]}").unwrap(), set(&[]));
        let bom = [b"\xef\xbb\xbf".as_slice(), b"{\"dependencies\": {\"a\": \"1\"}}"].concat();
        assert_eq!(registry_names(&bom).unwrap(), set(&["a"]));
        for bad in [b"[]".as_slice(), b"not json", b"\xff{}", b"\"x\""] {
            assert!(registry_names(bad).is_none());
        }
    }

    #[test]
    fn a_name_is_new_only_when_it_did_not_count_at_the_base() {
        assert_eq!(new_in(&set(&["a", "b", "c"]), &set(&["a"])), set(&["b", "c"]));
        assert!(new_in(&set(&["a"]), &set(&["a", "b"])).is_empty());
        // A move from `workspace:*` to a registry version is new.
        let base = registry_names(br#"{"dependencies": {"core": "workspace:*", "x": "^1"}}"#).unwrap();
        let head = registry_names(br#"{"devDependencies": {"core": "^2", "x": "^2"}}"#).unwrap();
        assert_eq!(new_in(&head, &base), set(&["core"]));
    }

    #[test]
    fn each_name_once_with_the_first_manifest() {
        let list = attribute(&[
            ("a/package.json".to_string(), set(&["z", "b"])),
            ("b/package.json".to_string(), set(&["b", "a"])),
        ]);
        assert_eq!(
            list,
            [
                ("a".to_string(), "b/package.json".to_string()),
                ("b".to_string(), "a/package.json".to_string()),
                ("z".to_string(), "a/package.json".to_string()),
            ]
        );
    }

    #[test]
    fn ls_tree_entries() {
        assert_eq!(ls_tree_entry(b""), Ok(Entry::Absent));
        assert_eq!(ls_tree_entry(b"100644 blob abc\tpackage.json\0"), Ok(Entry::Blob("abc".into())));
        assert_eq!(ls_tree_entry(b"100755 blob abc\tpackage.json\0"), Ok(Entry::Blob("abc".into())));
        assert_eq!(ls_tree_entry(b"120000 blob abc\tpackage.json\0"), Ok(Entry::Other));
        assert_eq!(ls_tree_entry(b"040000 tree abc\tpackage.json\0"), Ok(Entry::Other));
        assert_eq!(ls_tree_entry(b"160000 commit abc\tpackage.json\0"), Ok(Entry::Other));
        assert_eq!(ls_tree_entry(b"100644 blob a\tp\x00100644 blob b\tp\0"), Ok(Entry::Other));
        assert_eq!(ls_tree_entry(b"100644 blob abc\tpackage.json"), Err(()));
        assert_eq!(ls_tree_entry(b"garbage\0"), Err(()));
    }

    #[test]
    fn names_npm_can_hold() {
        for name in ["a", "left-pad", "@scope/pkg", "@a~b/c.d_e", "~x", "-x", "A9"] {
            assert!(valid_name(name), "{name}");
        }
        for name in ["", ".a", "_a", "@/a", "@a/", "@a", "a/b", "@a/b/c", "a b", "é", "@.a/b", "@a/.b"] {
            assert!(!valid_name(name), "{name}");
        }
        assert!(valid_name(&"a".repeat(214)));
        assert!(!valid_name(&"a".repeat(215)));
    }

    #[test]
    fn the_url_escapes_only_the_slash() {
        assert_eq!(url("@scope/pkg"), "https://registry.npmjs.org/@scope%2Fpkg");
        assert_eq!(url("a~b.c"), "https://registry.npmjs.org/a~b.c");
        let args = curl_args("@s/p");
        assert_eq!(args[0], "--disable");
        assert_eq!(args[8..], ["--write-out", "\n%{http_code}", "https://registry.npmjs.org/@s%2Fp"]);
        assert_eq!(args.len(), 11);
    }

    #[test]
    fn answers_are_read() {
        assert_eq!(read_answer(b"{}\n404"), Answer::NotFound);
        assert_eq!(read_answer(b"\n404"), Answer::NotFound);
        assert_eq!(
            read_answer(br#"{"time":{"created":"2020-01-02T03:04:05.123Z"}}"#.iter().chain(b"\n200").copied().collect::<Vec<_>>().as_slice()),
            Answer::Created(1_577_934_245)
        );
        assert_eq!(read_answer(b"x\n429"), Answer::Failure("the registry answered 429".into()));
        let unreadable = Answer::Failure(UNREADABLE.into());
        for out in [
            b"".as_slice(),
            b"404",
            b"{}\n20",
            b"{}\n2000",
            b"{}\r200",
            b"{}\n200",
            b"[]\n200",
            b"{\"time\":{}}\n200",
            b"{\"time\":{\"created\":5}}\n200",
            b"\xff\n200",
        ] {
            assert_eq!(read_answer(out), unreadable, "{:?}", String::from_utf8_lossy(out));
        }
    }

    #[test]
    fn curl_endings_are_reasons() {
        let reason = |end| match curl_answer(end) {
            Answer::Failure(r) => r,
            other => panic!("{other:?}"),
        };
        assert_eq!(reason(Captured::NotStarted), "curl could not start");
        assert_eq!(reason(Captured::TimedOut), "timed out");
        assert_eq!(reason(Captured::Exited(28, Some(Vec::new()))), "timed out");
        assert_eq!(reason(Captured::Exited(6, None)), "curl failed (exit 6)");
        assert_eq!(reason(Captured::Signal(9)), "curl failed (signal 9)");
        assert_eq!(reason(Captured::Exited(0, None)), "curl failed (output not read)");
        assert_eq!(reason(Captured::WaitFailed), "curl failed (output not read)");
        assert_eq!(curl_answer(Captured::Exited(0, Some(b"\n404".to_vec()))), Answer::NotFound);
    }

    #[test]
    fn utc_times_are_real_dates() {
        assert_eq!(utc_secs("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(utc_secs("2000-02-29T00:00:00Z"), Some(951_782_400));
        assert_eq!(utc_secs("2024-12-31T23:59:59.999999999Z"), Some(1_735_689_599));
        assert_eq!(utc_secs("0000-01-01T00:00:00Z"), Some(-62_167_219_200));
        for bad in [
            "2023-02-29T00:00:00Z",
            "1900-02-29T00:00:00Z",
            "2020-13-01T00:00:00Z",
            "2020-00-01T00:00:00Z",
            "2020-04-31T00:00:00Z",
            "2020-01-01T24:00:00Z",
            "2020-01-01T00:60:00Z",
            "2020-01-01T00:00:60Z",
            "2020-01-01T00:00:00",
            "2020-01-01T00:00:00+00:00",
            "2020-01-01T00:00:00.Z",
            "2020-01-01T00:00:00.1234567890Z",
            "2020-01-01 00:00:00Z",
            "2020-1-01T00:00:00Z",
            "+020-01-01T00:00:00Z",
            "2020-01-01T00:00:00Zx",
        ] {
            assert_eq!(utc_secs(bad), None, "{bad}");
        }
    }

    #[test]
    fn age_is_whole_days_rounded_down() {
        assert_eq!(age_days(100 * DAY, 100 * DAY), 0);
        assert_eq!(age_days(100 * DAY, 100 * DAY + 5), 0);
        assert_eq!(age_days(100 * DAY, 70 * DAY + 1), 29);
        assert_eq!(age_days(100 * DAY, 70 * DAY), 30);
        assert_eq!(age_days(0, -62_167_219_200), 719_528);
    }

    fn list(names: &[(&str, &str)]) -> Vec<(String, String)> {
        names.iter().map(|(n, p)| (n.to_string(), p.to_string())).collect()
    }

    #[test]
    fn judge_writes_the_lines_in_order() {
        let now = 1000 * DAY;
        let names =
            list(&[("a", "package.json"), ("b", "x/package.json"), ("c", "package.json"), ("d", "package.json")]);
        let mut asked = Vec::new();
        let check = judge(&names, now, 30, |name| {
            asked.push(name.to_string());
            match name {
                "a" => Answer::Created(now - 29 * DAY - 3600),
                "b" => Answer::NotFound,
                "c" => Answer::Created(now - 30 * DAY - 3600),
                _ => Answer::Created(now + DAY),
            }
        });
        assert_eq!(asked, ["a", "b", "c", "d"]);
        assert_eq!(
            check.lines,
            [
                young_line(29, "a", "package.json"),
                not_found_line("b", "x/package.json"),
                young_line(0, "d", "package.json")
            ]
        );
        assert_eq!(check.counts, Some(Counts { new: 4, warnings: 3, not_checked: 0 }));
    }

    #[test]
    fn the_first_failure_stops_the_check() {
        let names =
            list(&[("Bad Name", "package.json"), ("b", "package.json"), ("c", "package.json"), ("d", "package.json")]);
        let mut asked = Vec::new();
        let check = judge(&names, 0, 30, |name| {
            asked.push(name.to_string());
            match name {
                "b" => Answer::Created(-100 * DAY),
                _ => Answer::Failure("timed out".into()),
            }
        });
        // An invalid name is not found without a call.
        assert_eq!(asked, ["b", "c"]);
        assert_eq!(
            check.lines,
            [
                "New dependency not in the npm registry: Bad Name (package.json). Check the name: anyone can publish a package under a name that does not exist yet.",
                "New dependencies not checked: 2 of 4; the npm registry could not be read (timed out).",
            ]
        );
        assert_eq!(check.counts, Some(Counts { new: 4, warnings: 1, not_checked: 2 }));
    }

    #[test]
    fn new_names_read_from_git() {
        let dir = crate::git::TempDir::new("shipcraft-test-item115").unwrap();
        let root = dir.path();
        let git = |args: &[&str]| {
            let out = Command::new("git")
                .arg("-C")
                .arg(root)
                .args(args)
                .env("GIT_CONFIG_GLOBAL", "/dev/null")
                .env("GIT_CONFIG_NOSYSTEM", "1")
                .env("GIT_AUTHOR_NAME", "t")
                .env("GIT_AUTHOR_EMAIL", "t@example.invalid")
                .env("GIT_COMMITTER_NAME", "t")
                .env("GIT_COMMITTER_EMAIL", "t@example.invalid")
                .output()
                .unwrap();
            assert!(out.status.success(), "git {args:?}");
            String::from_utf8(out.stdout).unwrap()
        };
        let write = |path: &str, text: &str| {
            let path = root.join(path);
            std::fs::create_dir_all(path.parent().unwrap()).unwrap();
            std::fs::write(path, text).unwrap();
        };
        git(&["init", "-q", "-b", "main"]);
        write("package.json", r#"{"dependencies": {"old": "^1", "core": "workspace:*"}}"#);
        write("bad/package.json", r#"{"dependencies": {"x": "1"}}"#);
        write("gone/package.json", r#"{"dependencies": {"g": "1"}}"#);
        git(&["add", "-A"]);
        git(&["commit", "-q", "-m", "base"]);
        let base = git(&["rev-parse", "HEAD"]).trim().to_string();
        write("package.json", r#"{"dependencies": {"old": "^2", "core": "^1", "new": "1"}}"#);
        write("bad/package.json", "not json");
        write("web/package.json", "\u{feff}{\"devDependencies\": {\"new\": \"1\", \"@s/web\": \"2\"}}");
        write("node_modules/n/package.json", r#"{"dependencies": {"nm": "1"}}"#);
        std::fs::remove_file(root.join("gone/package.json")).unwrap();
        git(&["add", "-A", "-f"]);
        git(&["commit", "-q", "-m", "head"]);
        let head = git(&["rev-parse", "HEAD"]).trim().to_string();
        let repo = Repo::at_root(root);
        assert_eq!(
            new_names(&repo, &base, &head).unwrap(),
            list(&[("@s/web", "web/package.json"), ("core", "package.json"), ("new", "package.json")])
        );
        assert!(new_names(&repo, &head, &head).unwrap().is_empty());
        assert!(new_names(&repo, &base, "0000000000000000000000000000000000000000").is_err());
    }

    #[test]
    fn line_wording() {
        assert_eq!(
            young_line(3, "@s/p", "web/package.json"),
            "New dependency first published 3 day(s) ago on npm: @s/p (web/package.json). Check it is the package you meant."
        );
        assert_eq!(GIT_LINE, "New dependencies not checked: git could not read the package.json files.");
    }
}
