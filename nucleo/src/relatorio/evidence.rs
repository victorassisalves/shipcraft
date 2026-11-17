//! Releases, fixes and lead time from git and the run log (items 75, 76, 105).

use super::git::{failure, unreadable, utf8, Git};
use super::rows::{first_row, is, locks_of, str_of};
use super::selection::Selection;
use super::Row;
use crate::lock::{self, Lock};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

/// A release: a tag of the selection's grammar (item 76's `vX.Y.Z`, or item
/// 99's pattern) whose commit is on the default branch.
pub(super) struct Release {
    pub(super) name: String,
    pub(super) time: i64,
    locks: BTreeMap<String, String>,
}

/// A lock's fix data: `change_kind`, `reported_at`, `fixes_release`.
#[derive(Clone, Default)]
pub(super) struct FixData {
    pub(super) kind: Option<String>,
    pub(super) reported_at: Option<String>,
    pub(super) fixes_release: Option<String>,
}

/// What git says, all read before anything is reported: one failure makes
/// every git-derived value null.
pub(super) struct Evidence {
    pub(super) branch: String,
    /// Item 79: the default branch's commit, for the ancestry check.
    pub(super) tip_commit: String,
    tip: BTreeMap<String, String>,
    /// Ordered by time, then by version (by tag name under a pattern).
    pub(super) releases: Vec<Release>,
    /// Fix data from the first valid lock file among the tip, the latest
    /// release that holds it and HEAD; absent when none has one.
    files: BTreeMap<String, FixData>,
}

impl Evidence {
    pub(super) fn read(git: &Git, log_ids: &[String], selection: &Selection) -> std::result::Result<Evidence, String> {
        let probe = ["config", "--get-regexp", r"^(extensions\.partialclone|remote\..*\.promisor)$"];
        if let Some(out) = git.maybe(&probe)? {
            if partial(&utf8(&probe, out)?) {
                return Err("partial clone: report reads no network".to_string());
            }
        }
        let shallow = ["rev-parse", "--is-shallow-repository"];
        match utf8(&shallow, git.ok(&shallow)?)?.trim_end_matches('\n') {
            "true" => return Err("shallow clone: history incomplete".to_string()),
            "false" => {}
            _ => return Err(unreadable(&shallow)),
        }
        let mut default = None;
        for name in ["refs/remotes/origin/HEAD", "refs/remotes/origin/main", "refs/heads/main", "refs/heads/master"] {
            if let Some(commit) = git.commit(name)? {
                default = Some((name.to_string(), commit));
                break;
            }
        }
        let Some((branch, tip_commit)) = default else { return Err("no default branch".to_string()) };
        let list = ["for-each-ref", "refs/tags", "--format=%(refname:strip=2)"];
        let names = utf8(&list, git.ok(&list)?)?;
        let mut releases = Vec::new();
        let mut commits = BTreeMap::new();
        for name in names.lines().filter(|n| selection.names(n)) {
            let Some(commit) = git.commit(&format!("refs/tags/{name}"))? else { continue };
            let ancestry = ["merge-base", "--is-ancestor", commit.as_str(), tip_commit.as_str()];
            match git.call(&ancestry)? {
                (Some(0), _) => {}
                (Some(1), _) => continue,
                (code, _) => return Err(failure(&ancestry, code)),
            }
            let time = release_time(git, name, &commit)?;
            let locks = git.locks(&commit)?;
            commits.insert(name.to_string(), commit);
            releases.push(Release { name: name.to_string(), time, locks });
        }
        // Item 99: the version tie-break only for item 76's tags; under a
        // pattern, the tag name in byte order.
        releases.sort_by(|a, b| {
            a.time.cmp(&b.time).then_with(|| match selection {
                Selection::Pattern(_) => a.name.as_bytes().cmp(b.name.as_bytes()),
                _ => version_cmp(&a.name, &b.name),
            })
        });
        let tip = git.locks(&tip_commit)?;
        let head = match git.commit("HEAD")? {
            Some(commit) => Some((git.locks(&commit)?, commit)),
            None => None,
        };
        let mut population: BTreeSet<String> = log_ids.iter().cloned().collect();
        population.extend(tip.keys().cloned());
        for release in &releases {
            population.extend(release.locks.keys().cloned());
        }
        let mut parsed: BTreeMap<String, Option<Lock>> = BTreeMap::new();
        let mut files = BTreeMap::new();
        for id in population {
            let mut sources: Vec<(&str, &String)> = Vec::new();
            if let Some(oid) = tip.get(&id) {
                sources.push((tip_commit.as_str(), oid));
            }
            for release in releases.iter().rev() {
                if let Some(oid) = release.locks.get(&id) {
                    sources.push((commits[&release.name].as_str(), oid));
                }
            }
            if let Some((locks, commit)) = &head {
                if let Some(oid) = locks.get(&id) {
                    sources.push((commit.as_str(), oid));
                }
            }
            for (commit, oid) in sources {
                if !parsed.contains_key(oid) {
                    let spec = format!("{commit}:.shipcraft/locks/{id}.json");
                    let bytes = git.ok(&["cat-file", "blob", spec.as_str()])?;
                    // Item 76, point 1: only a lock valid by this binary's rules
                    // (a supported format, seal included) ends the search.
                    let lock = lock::check_format(&spec, &bytes).ok().and_then(|()| Lock::parse(&bytes));
                    parsed.insert(oid.clone(), lock);
                }
                if let Some(lock) = &parsed[oid] {
                    let data = match &lock.fix {
                        Some(fix) => FixData {
                            kind: Some(fix.kind.as_str().to_string()),
                            reported_at: fix.reported_at.clone(),
                            fixes_release: fix.fixes_release.clone(),
                        },
                        None => FixData::default(),
                    };
                    files.insert(id.clone(), data);
                    break;
                }
            }
        }
        Ok(Evidence { branch, tip_commit, tip, releases, files })
    }
}

/// A partial clone: `extensions.partialclone` with a value, or a
/// `remote.<name>.promisor` that is true in git's boolean spellings.
fn partial(config: &str) -> bool {
    config.lines().any(|line| {
        let (key, value) = match line.split_once(' ') {
            Some((key, value)) => (key, Some(value)),
            None => (line, None),
        };
        let key = key.to_ascii_lowercase();
        if key == "extensions.partialclone" {
            return value.is_some_and(|v| !v.is_empty());
        }
        key.starts_with("remote.")
            && key.ends_with(".promisor")
            && value.is_none_or(|v| ["true", "yes", "on", "1"].contains(&v.to_ascii_lowercase().as_str()))
    })
}

/// The tagger date of an annotated tag that has one, else the commit's
/// committer date, read with no signature verifier.
fn release_time(git: &Git, name: &str, commit: &str) -> std::result::Result<i64, String> {
    let pattern = format!("refs/tags/{name}");
    let args = ["for-each-ref", pattern.as_str(), "--format=%(objecttype) %(taggerdate:unix)"];
    let out = utf8(&args, git.ok(&args)?)?;
    let line = out.lines().next().ok_or_else(|| unreadable(&args))?;
    let (kind, date) = line.split_once(' ').ok_or_else(|| unreadable(&args))?;
    if kind == "tag" && !date.is_empty() {
        return seconds(date).ok_or_else(|| unreadable(&args));
    }
    let args = ["-c", "log.showSignature=false", "log", "--no-show-signature", "-1", "--format=%ct", commit];
    let out = utf8(&args, git.ok(&args)?)?;
    seconds(out.trim_end_matches('\n')).ok_or_else(|| unreadable(&args))
}

fn seconds(text: &str) -> Option<i64> {
    let digits = text.strip_prefix('-').unwrap_or(text);
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    text.parse().ok()
}

/// `vX.Y.Z` by major, minor, patch as decimal numbers of any length.
fn version_cmp(a: &str, b: &str) -> std::cmp::Ordering {
    let parts = |t: &str| t.trim_start_matches('v').split('.').map(str::to_string).collect::<Vec<_>>();
    let (a, b) = (parts(a), parts(b));
    a.iter()
        .zip(&b)
        .map(|(x, y)| x.len().cmp(&y.len()).then_with(|| x.cmp(y)))
        .find(|o| o.is_ne())
        .unwrap_or(std::cmp::Ordering::Equal)
}

/// Per lock id: its fix data and its release (index into the releases).
pub(super) struct Facts {
    pub(super) tip: BTreeSet<String>,
    pub(super) fix: BTreeMap<String, FixData>,
    pub(super) release: BTreeMap<String, usize>,
}

impl Facts {
    pub(super) fn of(ev: &Evidence, rows: &[Row], log_ids: &[String]) -> Facts {
        let mut fix = BTreeMap::new();
        let mut release = BTreeMap::new();
        let mut population: BTreeSet<&String> = log_ids.iter().collect();
        population.extend(ev.tip.keys());
        for (i, r) in ev.releases.iter().enumerate() {
            for id in r.locks.keys() {
                population.insert(id);
                release.entry(id.clone()).or_insert(i);
            }
        }
        for id in population {
            let data = match ev.files.get(id) {
                Some(data) => data.clone(),
                None => red_row(rows, id).map(fix_of_row).unwrap_or_default(),
            };
            fix.insert(id.clone(), data);
        }
        Facts { tip: ev.tip.keys().cloned().collect(), fix, release }
    }
}

/// The fix data a `red` row carries, each field in its grammar; item 105:
/// `fixes_release` is a tag name (item 75's syntax included).
pub(super) fn fix_of_row(row: &Row) -> FixData {
    let kind = row.get("kind").and_then(Value::as_str).filter(|k| *k == "feature" || *k == "fix");
    let field = |key: &str, valid: fn(&str) -> bool| row.get(key).and_then(Value::as_str).filter(|v| valid(v));
    FixData {
        kind: kind.map(str::to_string),
        reported_at: field("reported_at", lock::valid_time).map(str::to_string),
        fixes_release: field("fixes_release", lock::tag_name).map(str::to_string),
    }
}

/// The earliest passed non-redo `red` row of a lock (ties in file order).
pub(super) fn red_row<'a>(rows: &'a [Row], id: &str) -> Option<&'a Row> {
    first_row(rows.iter().filter(|r| {
        str_of(r, "layer") == "red"
            && is(r, "passed")
            && r.get("redo") != Some(&Value::Bool(true))
            && locks_of(r).iter().any(|l| l == id)
    }))
}

/// Item 75's time grammar, as Unix seconds.
pub(super) fn unix_time(text: &str) -> Option<i64> {
    if !lock::valid_time(text) {
        return None;
    }
    let n = |r: std::ops::Range<usize>| text.get(r).and_then(|s| s.parse::<i64>().ok());
    let (y, mo, d, h, mi) = (n(0..4)?, n(5..7)?, n(8..10)?, n(11..13)?, n(14..16)?);
    let (sec, rest) = if text.as_bytes().get(16) == Some(&b':') { (n(17..19)?, 19) } else { (0, 16) };
    let offset = match text.as_bytes()[rest] {
        b'Z' => 0,
        sign => {
            let o = n(rest + 1..rest + 3)? * 3600 + n(rest + 4..rest + 6)? * 60;
            if sign == b'-' {
                -o
            } else {
                o
            }
        }
    };
    Some(days_from_civil(y, mo, d) * 86_400 + h * 3600 + mi * 60 + sec - offset)
}

/// Howard Hinnant's days_from_civil: days since 1970-01-01.
pub(crate) fn days_from_civil(y: i64, mo: i64, d: i64) -> i64 {
    let y = if mo <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (mo + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}
