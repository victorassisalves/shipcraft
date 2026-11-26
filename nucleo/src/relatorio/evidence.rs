//! Releases, fixes and lead time from git and the run log (items 75, 76, 105),
//! and item 124's merges to the default branch.

use super::git::{failure, unreadable, utf8, Git};
use super::rows::{first_row, is, locks_of, str_of};
use super::selection::Selection;
use super::Row;
use crate::config::Deploy;
use crate::lock::{self, Lock};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

/// A release: a tag of the selection's grammar (item 76's `vX.Y.Z`, or item
/// 99's pattern) whose commit is on the default branch, with the lock files of
/// its tree. Item 124: or a merge (`name` its commit), with the lock files it
/// adds against its first parent.
pub(super) struct Release {
    pub(super) name: String,
    pub(super) time: i64,
    pub(super) commit: String,
    pub(super) locks: BTreeMap<String, String>,
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
    /// Ordered by time, then by version and tag name (by tag name under a pattern).
    pub(super) releases: Vec<Release>,
    /// Fix data from the first valid lock file among the tip, the latest
    /// release that holds it (item 124: the merge that ships it) and HEAD;
    /// absent when none has one.
    files: BTreeMap<String, FixData>,
    head: Option<(BTreeMap<String, String>, String)>,
    parsed: BTreeMap<String, Option<Lock>>,
    /// Item 159: the locks whose file git reads abandoned in any source.
    abandoned: BTreeSet<String>,
    /// Item 124: the mode, and `config`, `fallback` or `default`.
    pub(super) deploy: (Deploy, &'static str),
    /// Item 124: in merge mode, the default branch's first-parent line,
    /// oldest first.
    pub(super) merges: Option<Vec<Release>>,
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
            releases.push(Release { name: name.to_string(), time, commit, locks });
        }
        // Item 99: the version tie-break only for item 76's tags; under a
        // pattern, the tag name in byte order. Item 137: then the name in
        // byte order, so `1.2.3` comes before `v1.2.3`.
        releases.sort_by(|a, b| {
            let bytes = a.name.as_bytes().cmp(b.name.as_bytes());
            a.time.cmp(&b.time).then_with(|| match selection {
                Selection::Pattern(..) => bytes,
                _ => version_cmp(&a.name, &b.name).then(bytes),
            })
        });
        let tip = git.locks(&tip_commit)?;
        let head = match git.commit("HEAD")? {
            Some(commit) => Some((git.locks(&commit)?, commit)),
            None => None,
        };
        let deploy = match (selection.deploy(), releases.is_empty()) {
            (Some(deploy), _) => (deploy, "config"),
            (None, true) => (Deploy::Merge, "fallback"),
            (None, false) => (Deploy::Release, "default"),
        };
        let (files, parsed, abandoned) = (BTreeMap::new(), BTreeMap::new(), BTreeSet::new());
        let mut ev =
            Evidence { branch, tip_commit, tip, releases, files, head, parsed, abandoned, deploy, merges: None };
        // Item 124: today's reads, in both modes, before `--since`'s check.
        ev.read_files(git, log_ids)?;
        Ok(ev)
    }

    /// Item 124: the deploys the metrics count, merges or releases.
    pub(super) fn deploys(&self) -> &[Release] {
        self.merges.as_deref().unwrap_or(&self.releases)
    }

    /// Item 124: in merge mode, after `--since`'s check, the first-parent line
    /// and the lock files each merge adds, then the fix data from its sources.
    pub(super) fn read_merges(mut self, git: &Git, log_ids: &[String]) -> std::result::Result<Evidence, String> {
        if self.deploy.0 == Deploy::Release {
            return Ok(self);
        }
        let tip = self.tip_commit.as_str();
        let args = ["-c", "log.showSignature=false", "log", "--no-show-signature", "--no-color", "--first-parent"];
        let line = [&args[..], &["--format=%H %ct", tip]].concat();
        let out = utf8(&line, git.ok(&line)?)?;
        let mut merges = Vec::new();
        for entry in out.lines().rev() {
            let (commit, time) = entry.split_once(' ').ok_or_else(|| unreadable(&line))?;
            let time = seconds(time).filter(|_| hex(commit)).ok_or_else(|| unreadable(&line))?;
            merges.push(Release { name: commit.to_string(), time, commit: commit.to_string(), locks: BTreeMap::new() });
        }
        let index: BTreeMap<String, usize> = merges.iter().enumerate().map(|(i, m)| (m.commit.clone(), i)).collect();
        let raw = ["--format=%H", "--raw", "-z", "--diff-merges=first-parent", "--root", "--no-renames", "--no-abbrev"];
        let added = [&["-c", "log.follow=false"], &args[..], &raw, &[tip, "--", ".shipcraft/locks/"]].concat();
        for (commit, id, oid) in added_locks(&added, git.ok(&added)?)? {
            let i = *index.get(&commit).ok_or_else(|| unreadable(&added))?;
            merges[i].locks.insert(id, oid);
        }
        self.merges = Some(merges);
        self.read_files(git, log_ids)?;
        Ok(self)
    }

    /// The fix data of every lock of the population (the run log, the tip and
    /// the deploys), from the first valid file among its sources in order;
    /// item 159: every source is read, and one abandoned makes the lock so.
    fn read_files(&mut self, git: &Git, log_ids: &[String]) -> std::result::Result<(), String> {
        let mut population: BTreeSet<String> = log_ids.iter().cloned().collect();
        population.extend(self.tip.keys().cloned());
        for deploy in self.deploys() {
            population.extend(deploy.locks.keys().cloned());
        }
        let mut files = BTreeMap::new();
        let mut abandoned = BTreeSet::new();
        for id in population {
            let mut sources: Vec<(&str, &String)> = Vec::new();
            if let Some(oid) = self.tip.get(&id) {
                sources.push((self.tip_commit.as_str(), oid));
            }
            let holders: Vec<&Release> = match &self.merges {
                // Item 124: only the merge that ships it, the earliest that adds it.
                Some(merges) => merges.iter().find(|m| m.locks.contains_key(&id)).into_iter().collect(),
                None => self.releases.iter().rev().filter(|r| r.locks.contains_key(&id)).collect(),
            };
            for release in holders {
                sources.push((release.commit.as_str(), &release.locks[&id]));
            }
            if let Some((locks, commit)) = &self.head {
                if let Some(oid) = locks.get(&id) {
                    sources.push((commit.as_str(), oid));
                }
            }
            for (commit, oid) in sources {
                if !self.parsed.contains_key(oid) {
                    let spec = format!("{commit}:.shipcraft/locks/{id}.json");
                    let bytes = git.ok(&["cat-file", "blob", spec.as_str()])?;
                    // Item 76, point 1: only a lock valid by this binary's rules
                    // (a supported format, seal included) ends the search.
                    let lock = lock::check_format(&spec, &bytes).ok().and_then(|()| Lock::parse(&bytes));
                    self.parsed.insert(oid.clone(), lock);
                }
                let Some(lock) = &self.parsed[oid] else { continue };
                if lock.state == lock::State::Abandoned {
                    abandoned.insert(id.clone());
                }
                if !files.contains_key(&id) {
                    let data = match &lock.fix {
                        Some(fix) => FixData {
                            kind: Some(fix.kind.as_str().to_string()),
                            reported_at: fix.reported_at.clone(),
                            fixes_release: fix.fixes_release.clone(),
                        },
                        None => FixData::default(),
                    };
                    files.insert(id.clone(), data);
                }
            }
        }
        self.files = files;
        self.abandoned = abandoned;
        Ok(())
    }
}

fn hex(text: &str) -> bool {
    !text.is_empty() && text.bytes().all(|b| b.is_ascii_hexdigit())
}

/// Item 124: `git log --format=%H --raw -z`'s lock files added against the
/// first parent (status `A`, not a submodule), as (commit, id, blob id) in
/// the log's order; a path that is not `.shipcraft/locks/<id>.json` is skipped.
fn added_locks(args: &[&str], out: Vec<u8>) -> std::result::Result<Vec<(String, String, String)>, String> {
    let bad = || unreadable(args);
    let mut tokens = out.split(|b| *b == 0).map(|t| std::str::from_utf8(t).map_err(|_| bad()));
    let (mut commit, mut added) = (None::<String>, Vec::new());
    while let Some(token) = tokens.next() {
        let token = token?.trim_start_matches('\n');
        if token.is_empty() {
            continue;
        }
        let Some(meta) = token.strip_prefix(':') else {
            commit = Some(token.to_string()).filter(|c| hex(c));
            commit.as_ref().ok_or_else(bad)?;
            continue;
        };
        let path = tokens.next().ok_or_else(bad)??;
        let fields: Vec<&str> = meta.split(' ').collect();
        let [_, mode, _, oid, status] = fields[..] else { return Err(bad()) };
        let commit = commit.clone().ok_or_else(bad)?;
        let id = path.strip_prefix(".shipcraft/locks/").and_then(|p| p.strip_suffix(".json"));
        if let Some(id) = id.filter(|id| !id.is_empty() && !id.contains('/')) {
            if status == "A" && mode != "160000" && hex(oid) {
                added.push((commit, id.to_string(), oid.to_string()));
            }
        }
    }
    Ok(added)
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

/// `vX.Y.Z` or `X.Y.Z` by major, minor, patch as decimal numbers of any length.
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
    /// Item 159: abandoned locks, left out of `release` (no DORA sample).
    pub(super) abandoned: BTreeSet<String>,
    pub(super) fix: BTreeMap<String, FixData>,
    pub(super) release: BTreeMap<String, usize>,
}

impl Facts {
    pub(super) fn of(ev: &Evidence, rows: &[Row], log_ids: &[String]) -> Facts {
        let mut fix = BTreeMap::new();
        let mut release = BTreeMap::new();
        let mut population: BTreeSet<&String> = log_ids.iter().collect();
        population.extend(ev.tip.keys());
        for (i, r) in ev.deploys().iter().enumerate() {
            for id in r.locks.keys() {
                population.insert(id);
                if !ev.abandoned.contains(id) {
                    release.entry(id.clone()).or_insert(i);
                }
            }
        }
        for id in population {
            let data = match ev.files.get(id) {
                Some(data) => data.clone(),
                None => red_row(rows, id).map(fix_of_row).unwrap_or_default(),
            };
            fix.insert(id.clone(), data);
        }
        Facts { tip: ev.tip.keys().cloned().collect(), abandoned: ev.abandoned.clone(), fix, release }
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

#[cfg(test)]
mod merge_reads {
    use super::added_locks;

    #[test]
    fn added_lock_files_are_read_from_the_raw_log() {
        let a = "a".repeat(40);
        let b = "b".repeat(40);
        let z = "0".repeat(40);
        let out = format!(
            "{a}\0\n:100644 000000 {b} {z} D\0.shipcraft/locks/x.json\0\0{b}\0\n:000000 100644 {z} {a} A\0.shipcraft/locks/y.json\0:000000 160000 {z} {a} A\0.shipcraft/locks/s.json\0:000000 100644 {z} {b} A\0.shipcraft/locks/d/e.json\0"
        );
        let got = added_locks(&["log"], out.into_bytes()).unwrap();
        assert_eq!(got, vec![(b.clone(), "y".to_string(), a.clone())]);
        assert!(added_locks(&["log"], b":000000 100644 x y A\0p\0".to_vec()).is_err());
        assert!(added_locks(&["log"], b"not-a-commit\0".to_vec()).is_err());
        assert_eq!(added_locks(&["log"], Vec::new()).unwrap(), vec![]);
    }
}
