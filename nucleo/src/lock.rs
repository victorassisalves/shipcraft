//! The lock: the RED's contract, one file per cycle in `.shipcraft/locks/<id>.json`.

use crate::git::{Repo, Snapshot};
use crate::refusal::{failed, refuse, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::time::{SystemTime, UNIX_EPOCH};

pub const LOCK_DIR: &str = ".shipcraft/locks";
/// The lock format this shipcraft writes (item 9, rule 2; item 43: format 3;
/// item 75: format 4, with the fix fields; item 98: format 5, with `controls`).
/// Item 105: a fix whose `fixes_release` is outside item 75's tag syntax is
/// written in `FORMAT_TAG_NAME` instead; every other new lock stays format 5.
pub const FORMAT: u64 = 5;
/// Item 105: format 6, format 5 with a `fixes_release` that is a tag name
/// outside item 75's syntax; the highest format this shipcraft knows.
pub const FORMAT_TAG_NAME: u64 = 6;
/// The lock formats this shipcraft reads, each lock by its own `format`.
pub const FORMATS: [u64; 5] = [2, 3, 4, FORMAT, FORMAT_TAG_NAME];
/// Item 43: in format 3 (and 4 and 5) each `files` value carries this prefix.
const PREFIX: &str = "sha256:";
/// Item 75: the keys format 4 adds, in order, after `failing_at_red`.
const FIX_KEYS: [&str; 3] = ["kind", "reported_at", "fixes_release"];
/// Item 75: every key a format 4 lock has.
const FORMAT_4_KEYS: [&str; 9] =
    ["format", "state", "files", "cases", "failing_at_red", "kind", "reported_at", "fixes_release", "seal"];
/// Item 98: the key format 5 adds, after `failing_at_red` and before `kind`.
const CONTROLS: &str = "controls";
/// Item 98: every key a format 5 lock has.
const FORMAT_5_KEYS: [&str; 10] =
    ["format", "state", "files", "cases", "failing_at_red", CONTROLS, "kind", "reported_at", "fixes_release", "seal"];

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
    Open,
    Closed,
}

/// Item 75: whether the cycle fixes behavior a release already shipped.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Feature,
    Fix,
}

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::Feature => "feature",
            Kind::Fix => "fix",
        }
    }
}

/// Item 75: a format 4 lock's fix fields, as the RED gave them.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Fix {
    pub kind: Kind,
    pub reported_at: Option<String>,
    pub fixes_release: Option<String>,
}

impl Fix {
    /// The fix fields of a format 4, 5 or 6 lock's object; None when one is
    /// missing or outside its syntax. Item 105: in formats 4 and 5,
    /// `fixes_release` is item 75's tag syntax; in format 6, `kind` is `fix`
    /// and `fixes_release` a tag name outside item 75's syntax, never null.
    fn read(format: u64, object: &serde_json::Map<String, serde_json::Value>) -> Option<Fix> {
        use serde_json::Value;
        let optional = |key: &str, valid: fn(&str) -> bool| match object.get(key)? {
            Value::Null => Some(None),
            Value::String(s) if valid(s) => Some(Some(s.clone())),
            _ => None,
        };
        let kind = match object.get("kind")? {
            Value::String(s) if s == "feature" => Kind::Feature,
            Value::String(s) if s == "fix" => Kind::Fix,
            _ => return None,
        };
        let reported_at = optional("reported_at", valid_time)?;
        let release: fn(&str) -> bool = if format == FORMAT_TAG_NAME { beyond_tag_syntax } else { valid_tag };
        let fixes_release = optional("fixes_release", release)?;
        if kind == Kind::Feature && (reported_at.is_some() || fixes_release.is_some()) {
            return None;
        }
        if format == FORMAT_TAG_NAME && (kind != Kind::Fix || fixes_release.is_none()) {
            return None;
        }
        Some(Fix { kind, reported_at, fixes_release })
    }

    /// Item 105: the format a new lock with these fix fields is written in.
    fn format(&self) -> u64 {
        match &self.fixes_release {
            Some(tag) if !valid_tag(tag) => FORMAT_TAG_NAME,
            _ => FORMAT,
        }
    }
}

/// The fields every format shares, as serde reads them (as before item 75).
#[derive(Deserialize)]
struct Base {
    #[serde(rename = "format")]
    formato: u64,
    state: State,
    files: BTreeMap<String, String>,
    cases: Vec<String>,
    failing_at_red: Vec<String>,
    seal: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Lock {
    /// The format version: an shipcraft that does not know it refuses to judge.
    pub formato: u64,
    pub state: State,
    /// sha256 of each locked test file and of `.shipcraft.toml`, by path; in
    /// format 3 and 4 written `sha256:<hex>` (item 43), in format 2 the bare hex.
    pub files: BTreeMap<String, String>,
    /// The cases the report showed at the RED (skipped ones excluded).
    pub cases: Vec<String>,
    /// The cases that failed at the RED.
    pub failing_at_red: Vec<String>,
    /// Item 98: format 5's controls, the cases of the RED's changed test files
    /// that passed at the RED, byte-sorted; None in formats 2 to 4.
    pub controls: Option<Vec<String>>,
    /// Item 75: format 4's (and 5's) fix fields; None in formats 2 and 3.
    pub fix: Option<Fix>,
    /// sha256 of the lock with an empty seal. A hand edit breaks it; it is a
    /// check against mistakes and shortcuts, not a signature.
    pub seal: String,
}

impl Serialize for Lock {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error> {
        use serde::ser::SerializeStruct;
        let fields = if self.fix.is_some() { 9 } else { 6 } + usize::from(self.controls.is_some());
        let mut lock = serializer.serialize_struct("Lock", fields)?;
        lock.serialize_field("format", &self.formato)?;
        lock.serialize_field("state", &self.state)?;
        lock.serialize_field("files", &self.files)?;
        lock.serialize_field("cases", &self.cases)?;
        lock.serialize_field("failing_at_red", &self.failing_at_red)?;
        if let Some(controls) = &self.controls {
            lock.serialize_field(CONTROLS, controls)?;
        }
        if let Some(fix) = &self.fix {
            lock.serialize_field("kind", fix.kind.as_str())?;
            lock.serialize_field("reported_at", &fix.reported_at)?;
            lock.serialize_field("fixes_release", &fix.fixes_release)?;
        }
        lock.serialize_field("seal", &self.seal)?;
        lock.end()
    }
}

impl Lock {
    /// A new open lock in format 5, or format 6 when its `fixes_release` is
    /// outside item 75's tag syntax (item 105); `files` values come from `new_digest`.
    pub fn open(
        files: BTreeMap<String, String>,
        cases: Vec<String>,
        failing_at_red: Vec<String>,
        controls: Vec<String>,
        fix: Fix,
    ) -> Lock {
        Lock {
            formato: fix.format(),
            state: State::Open,
            files,
            cases,
            failing_at_red,
            controls: Some(controls),
            fix: Some(fix),
            seal: String::new(),
        }
        .sealed()
    }

    /// Item 75: the lock `red --redo` writes over `self`: a format 4 or 5 lock
    /// becomes format 5 (item 98) with the same fix fields and `controls`; a
    /// format 2 or 3 lock becomes format 3, with no fix field and no controls.
    /// Item 105: a format 6 lock stays format 6.
    pub fn redone(
        &self,
        files: BTreeMap<String, String>,
        cases: Vec<String>,
        failing_at_red: Vec<String>,
        controls: Vec<String>,
    ) -> Lock {
        let (formato, fix, controls) = match &self.fix {
            Some(fix) if self.formato == FORMAT_TAG_NAME => (FORMAT_TAG_NAME, Some(fix.clone()), Some(controls)),
            Some(fix) => (FORMAT, Some(fix.clone()), Some(controls)),
            None => (3, None, None),
        };
        Lock { formato, state: State::Open, files, cases, failing_at_red, controls, fix, seal: String::new() }.sealed()
    }

    /// Item 98: the controls; none for a lock before format 5.
    pub fn controls(&self) -> &[String] {
        self.controls.as_deref().unwrap_or_default()
    }

    /// The `files` value these bytes have in this lock's own format (item 43).
    pub fn digest(&self, bytes: &[u8]) -> String {
        digest(self.formato, bytes)
    }

    /// The same lock, closed by shipcraft: only `state` and `seal` change.
    pub fn closed(&self) -> Lock {
        Lock { state: State::Closed, ..self.clone() }.sealed()
    }

    pub fn is_open(&self) -> bool {
        self.state == State::Open
    }

    /// None when the bytes are not a lock, or when it was edited by hand: a
    /// broken seal, or a `files` value outside its format's syntax (item 43);
    /// item 75: in format 4, a fix field missing or outside its syntax, or a key
    /// format 4 does not name; in formats 2 and 3, any fix key. Item 98: in
    /// format 5, also `controls` missing or not valid (`read_controls`); in
    /// formats 2 to 4, a `controls` key. Item 105: format 6 has format 5's
    /// keys and rules, with its own `kind` and `fixes_release` (`Fix::read`).
    pub fn parse(bytes: &[u8]) -> Option<Lock> {
        let base: Base = serde_json::from_slice(bytes).ok()?;
        let value: serde_json::Value = serde_json::from_slice(bytes).ok()?;
        let object = value.as_object()?;
        let keys: &[&str] = match base.formato {
            4 => &FORMAT_4_KEYS,
            5 | FORMAT_TAG_NAME => &FORMAT_5_KEYS,
            _ => &[],
        };
        let (fix, controls) = if keys.is_empty() {
            if FIX_KEYS.iter().chain([&CONTROLS]).any(|key| object.contains_key(*key)) {
                return None;
            }
            (None, None)
        } else {
            if object.keys().any(|key| !keys.contains(&key.as_str())) {
                return None;
            }
            let controls = match base.formato {
                5 | FORMAT_TAG_NAME => Some(read_controls(object.get(CONTROLS)?, &base.cases, &base.failing_at_red)?),
                _ => None,
            };
            (Some(Fix::read(base.formato, object)?), controls)
        };
        let lock = Lock {
            formato: base.formato,
            state: base.state,
            files: base.files,
            cases: base.cases,
            failing_at_red: base.failing_at_red,
            controls,
            fix,
            seal: base.seal,
        };
        (lock.files.values().all(|value| lock.valid_value(value)) && lock.seal == lock.compute_seal()).then_some(lock)
    }

    /// Formats 3 to 6: exactly `sha256:` and 64 lowercase hex; format 2: exactly
    /// 64 lowercase hex. No trimming, no case folding.
    fn valid_value(&self, value: &str) -> bool {
        let hex = match self.formato {
            2 => Some(value),
            3..=FORMAT_TAG_NAME => value.strip_prefix(PREFIX),
            _ => None,
        };
        hex.is_some_and(|hex| hex.len() == 64 && hex.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)))
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).expect("a lock always serializes") + "\n"
    }

    fn sealed(mut self) -> Lock {
        self.seal = self.compute_seal();
        self
    }

    fn compute_seal(&self) -> String {
        let unsealed = Lock { seal: String::new(), ..self.clone() };
        sha256_hex(serde_json::to_string(&unsealed).expect("a lock always serializes").as_bytes())
    }
}

/// Item 98: format 5's `controls`: an array of strings, each in `cases` and
/// none in `failing_at_red`, strictly in byte order (so no repeats); None
/// otherwise.
fn read_controls(value: &serde_json::Value, cases: &[String], failing_at_red: &[String]) -> Option<Vec<String>> {
    let controls =
        value.as_array()?.iter().map(|id| id.as_str().map(str::to_string)).collect::<Option<Vec<String>>>()?;
    let valid = controls.iter().all(|id| cases.contains(id) && !failing_at_red.contains(id))
        && controls.windows(2).all(|pair| pair[0].as_bytes() < pair[1].as_bytes());
    valid.then_some(controls)
}

/// Item 75: `YYYY-MM-DDTHH:MM[:SS]` then `Z` or `+HH:MM` or `-HH:MM`, ASCII
/// digits, a real Gregorian date, no fraction, no leap second.
pub fn valid_time(text: &str) -> bool {
    let b = text.as_bytes();
    let num = |range: std::ops::Range<usize>| -> Option<u32> {
        let part = b.get(range)?;
        part.iter().all(u8::is_ascii_digit).then(|| part.iter().fold(0, |n, d| n * 10 + u32::from(d - b'0')))
    };
    let at = |i: usize, c: u8| b.get(i) == Some(&c);
    let (Some(year), Some(month), Some(day), Some(hour), Some(minute)) =
        (num(0..4), num(5..7), num(8..10), num(11..13), num(14..16))
    else {
        return false;
    };
    if !(at(4, b'-') && at(7, b'-') && at(10, b'T') && at(13, b':')) {
        return false;
    }
    let mut rest = 16;
    if at(16, b':') {
        match num(17..19) {
            Some(second) if second <= 59 => rest = 19,
            _ => return false,
        }
    }
    let zone_ok = match b.get(rest) {
        Some(b'Z') => b.len() == rest + 1,
        Some(b'+' | b'-') => {
            b.len() == rest + 6
                && at(rest + 3, b':')
                && num(rest + 1..rest + 3).is_some_and(|h| h <= 23)
                && num(rest + 4..rest + 6).is_some_and(|m| m <= 59)
        }
        _ => false,
    };
    let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    let days = match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if leap => 29,
        2 => 28,
        _ => 0,
    };
    zone_ok && (1..=days).contains(&day) && hour <= 23 && minute <= 59
}

/// Item 105: a tag name, Shipcraft's own lexical grammar, on the string alone
/// (git is never consulted): at least 1 byte, every byte in 0x21-0x7E, none
/// of `~ ^ : ? * [ \`; not starting with `-`, not `@`, no `..` and no `@{`,
/// not starting or ending with `/` and no `//`, not ending with `.`, and no
/// `/`-separated component starting with `.` or ending in `.lock`. No length
/// limit. Every string of item 75's tag syntax is a tag name.
pub fn tag_name(text: &str) -> bool {
    let bytes = text.as_bytes();
    !bytes.is_empty()
        && bytes
            .iter()
            .all(|b| (0x21..=0x7e).contains(b) && !matches!(b, b'~' | b'^' | b':' | b'?' | b'*' | b'[' | b'\\'))
        && !text.starts_with('-')
        && text != "@"
        && !text.contains("..")
        && !text.contains("@{")
        && !text.starts_with('/')
        && !text.ends_with('/')
        && !text.contains("//")
        && !text.ends_with('.')
        && text.split('/').all(|component| !component.starts_with('.') && !component.ends_with(".lock"))
}

/// Item 105: a tag name outside item 75's tag syntax, the `fixes_release` of
/// a format 6 lock.
pub fn beyond_tag_syntax(text: &str) -> bool {
    tag_name(text) && !valid_tag(text)
}

/// Item 75: `v` then `X.Y.Z`, each a decimal number without leading zeros.
pub fn valid_tag(text: &str) -> bool {
    let Some(version) = text.strip_prefix('v') else { return false };
    let parts: Vec<&str> = version.split('.').collect();
    parts.len() == 3
        && parts.iter().all(|part| {
            !part.is_empty() && part.bytes().all(|b| b.is_ascii_digit()) && (part.len() == 1 || !part.starts_with('0'))
        })
}

/// The lock files of a snapshot, by path.
pub type LockFiles = BTreeMap<String, Vec<u8>>;

pub fn lock_files(repo: &Repo, snapshot: &Snapshot) -> Result<LockFiles> {
    let mut locks = LockFiles::new();
    for path in repo.list(snapshot, LOCK_DIR)? {
        if !path.ends_with(".json") {
            continue;
        }
        let bytes =
            repo.read(snapshot, &path)?.ok_or_else(|| failed(format!("lock {path} disappeared while reading")))?;
        check_format(&path, &bytes)?;
        locks.insert(path, bytes);
    }
    Ok(locks)
}

/// Refuses a lock written in a format this shipcraft does not know. A lock that is
/// not JSON, or has no format, is left to the seal check (edited by hand).
/// Item 75: a format above the highest known one asks for a newer shipcraft
/// (item 105: the highest is format 6).
pub(crate) fn check_format(path: &str, bytes: &[u8]) -> Result<()> {
    let Ok(value) = serde_json::from_slice::<serde_json::Value>(bytes) else { return Ok(()) };
    let legacy = value.get("formato").is_some();
    match value.get("format").or_else(|| value.get("formato")) {
        Some(f) if !legacy && f.as_u64().is_some_and(|f| f > FORMAT_TAG_NAME) => refuse(
            "lock-format",
            format!("lock {path} needs a newer shipcraft (format {f}; this one knows formats 2 to {FORMAT_TAG_NAME})"),
            "a lock written by a newer shipcraft cannot be judged by an older one",
            "upgrade shipcraft to the version the project pins (package.json, or shipcraft_min), then run the command again",
        ),
        Some(f) if legacy || !f.as_u64().is_some_and(|f| FORMATS.contains(&f)) => refuse(
            "lock-format",
            format!("lock {path} has format {f}, and this shipcraft only knows formats 2 and 3"),
            "two machines cannot judge the same commit differently without warning",
            "run `shipcraft red` again with this shipcraft to generate a lock in the current format",
        ),
        _ => Ok(()),
    }
}

/// A new lock path, unique per cycle so two branches never write the same file.
pub fn new_lock_path() -> String {
    let nanos = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    let id = &sha256_hex(format!("{nanos}-{}", std::process::id()).as_bytes())[..12];
    format!("{LOCK_DIR}/{id}.json")
}

/// The `files` value of these bytes in a new lock (current format).
pub fn new_digest(bytes: &[u8]) -> String {
    digest(FORMAT, bytes)
}

/// The `files` value of these bytes in a lock of `format`: `sha256:<hex>` in
/// formats 3 to 6, the bare hex in format 2.
fn digest(format: u64, bytes: &[u8]) -> String {
    let hex = sha256_hex(bytes);
    if format == 2 {
        hex
    } else {
        format!("{PREFIX}{hex}")
    }
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn feature() -> Fix {
        Fix { kind: Kind::Feature, reported_at: None, fixes_release: None }
    }

    fn files() -> BTreeMap<String, String> {
        [("tests/a.py".to_string(), new_digest(b"a")), (".shipcraft.toml".to_string(), new_digest(b"c"))].into()
    }

    fn strings(ids: &[&str]) -> Vec<String> {
        ids.iter().map(|id| id.to_string()).collect()
    }

    /// A lock with `controls`, written as format 5.
    fn five(controls: &[&str]) -> Lock {
        Lock::open(files(), strings(&["a::f", "a::p", "a::q"]), strings(&["a::f"]), strings(controls), feature())
    }

    /// The lock's JSON object, changed by `edit`, resealed by hand: the
    /// compact JSON with an empty seal, keys in format 5's fixed order (the
    /// others after them), as the spec's fixtures reseal.
    fn resealed(lock: &Lock, edit: impl FnOnce(&mut serde_json::Map<String, serde_json::Value>)) -> Vec<u8> {
        let mut value = serde_json::to_value(lock).unwrap();
        let object = value.as_object_mut().unwrap();
        edit(object);
        object.insert("seal".into(), "".into());
        let ordered: Vec<&String> = FORMAT_5_KEYS
            .iter()
            .filter_map(|key| object.get_key_value(*key).map(|(k, _)| k))
            .chain(object.keys().filter(|key| !FORMAT_5_KEYS.contains(&key.as_str())))
            .collect();
        let compact = |keys: &[&String], object: &serde_json::Map<String, serde_json::Value>| {
            let fields: Vec<String> = keys
                .iter()
                .map(|key| format!("{}:{}", serde_json::to_string(key).unwrap(), object[key.as_str()]))
                .collect();
            format!("{{{}}}", fields.join(","))
        };
        let seal = sha256_hex(compact(&ordered, object).as_bytes());
        let mut sealed = object.clone();
        sealed.insert("seal".into(), seal.into());
        compact(&ordered, &sealed).into_bytes()
    }

    #[test]
    fn a_new_lock_is_format_5_with_ten_keys_in_order() {
        let lock = five(&["a::p", "a::q"]);
        assert_eq!(lock.formato, 5);
        let json = lock.to_json();
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();
        let keys: Vec<&String> = value.as_object().unwrap().keys().collect();
        assert_eq!(keys.len(), 10);
        let order: Vec<usize> = FORMAT_5_KEYS.iter().map(|key| json.find(&format!("\"{key}\"")).unwrap()).collect();
        assert!(order.windows(2).all(|w| w[0] < w[1]), "keys out of order: {json}");
        assert_eq!(Lock::parse(json.as_bytes()), Some(lock));
    }

    #[test]
    fn the_seal_covers_controls() {
        let lock = five(&["a::p"]);
        let other = five(&["a::p", "a::q"]);
        assert_ne!(lock.seal, other.seal);
        // Hand-edited controls with the old seal: not a valid lock.
        let mut value = serde_json::to_value(&lock).unwrap();
        value["controls"] = serde_json::json!(["a::p", "a::q"]);
        assert_eq!(Lock::parse(&serde_json::to_vec(&value).unwrap()), None);
        // The seal is over ten fields: the compact JSON with an empty seal, in
        // the fixed order; a hand reseal in that order reads back the same lock.
        let hand: serde_json::Value = serde_json::from_slice(&resealed(&lock, |_| {})).unwrap();
        assert_eq!(hand["seal"], lock.seal.as_str());
        let unsealed = serde_json::to_string(&Lock { seal: String::new(), ..lock.clone() }).unwrap();
        assert!(unsealed.contains(r#""failing_at_red":["a::f"],"controls":["a::p"],"kind""#), "{unsealed}");
    }

    #[test]
    fn closing_keeps_format_5_and_its_controls() {
        let lock = five(&["a::p"]);
        let closed = lock.closed();
        assert_eq!((closed.formato, closed.controls()), (5, &strings(&["a::p"])[..]));
        assert_eq!(Lock::parse(closed.to_json().as_bytes()), Some(closed));
    }

    #[test]
    fn format_5_controls_are_validated_strictly() {
        let lock = five(&["a::p", "a::q"]);
        let set = |controls: serde_json::Value| resealed(&lock, |o| drop(o.insert("controls".into(), controls)));
        assert!(Lock::parse(&set(serde_json::json!(["a::p", "a::q"]))).is_some());
        assert!(Lock::parse(&set(serde_json::json!([]))).is_some());
        for bad in [
            serde_json::json!(["a::x"]),         // outside cases
            serde_json::json!(["a::f"]),         // inside failing_at_red
            serde_json::json!(["a::p", "a::p"]), // repeated
            serde_json::json!(["a::q", "a::p"]), // out of order
            serde_json::json!(null),
            serde_json::json!("a::p"),
            serde_json::json!([1]),
        ] {
            assert_eq!(Lock::parse(&set(bad.clone())), None, "{bad}");
        }
        assert_eq!(Lock::parse(&resealed(&lock, |o| drop(o.remove("controls")))), None);
        assert_eq!(Lock::parse(&resealed(&lock, |o| drop(o.insert("extra".into(), 1.into())))), None);
    }

    #[test]
    fn a_format_2_3_or_4_lock_with_controls_is_not_valid() {
        let lock = five(&["a::p"]);
        let four = resealed(&lock, |o| {
            o.insert("format".into(), 4.into());
            o.remove("controls");
        });
        let four = Lock::parse(&four).expect("format 4 without controls reads");
        assert_eq!((four.formato, four.controls.clone()), (4, None));
        let with = resealed(&four, |o| drop(o.insert("controls".into(), serde_json::json!([]))));
        assert_eq!(Lock::parse(&with), None);
        let three = Lock { formato: 3, fix: None, controls: None, ..lock.clone() }.sealed();
        assert!(Lock::parse(three.to_json().as_bytes()).is_some());
        assert_eq!(Lock::parse(&resealed(&three, |o| drop(o.insert("controls".into(), serde_json::json!([]))))), None);
    }

    #[test]
    fn redo_promotes_format_4_to_5_and_keeps_format_3() {
        let fix = Fix { kind: Kind::Fix, reported_at: Some("2026-11-07T10:00-03:00".into()), fixes_release: None };
        let four = Lock { formato: 4, controls: None, fix: Some(fix.clone()), ..five(&[]) }.sealed();
        let redone = four.redone(files(), four.cases.clone(), four.failing_at_red.clone(), strings(&["a::q"]));
        assert_eq!((redone.formato, redone.fix.clone(), redone.controls()), (5, Some(fix), &strings(&["a::q"])[..]));
        assert_ne!(redone, four);
        assert!(Lock::parse(redone.to_json().as_bytes()).is_some());
        let three = Lock { formato: 3, controls: None, fix: None, ..five(&[]) }.sealed();
        let redone = three.redone(files(), three.cases.clone(), three.failing_at_red.clone(), strings(&["a::q"]));
        assert_eq!((redone.formato, redone.fix.clone(), redone.controls.clone()), (3, None, None));
        let same = five(&["a::p"]);
        assert_eq!(same.redone(files(), same.cases.clone(), same.failing_at_red.clone(), strings(&["a::p"])), same);
    }

    #[test]
    fn format_7_is_the_future_format() {
        assert!(check_format("l.json", br#"{"format":5}"#).is_ok());
        assert!(check_format("l.json", br#"{"format":6}"#).is_ok());
        let Err(crate::refusal::Stop::Refused(refusal)) = check_format("l.json", br#"{"format":7}"#) else {
            panic!("format 7 must refuse")
        };
        assert_eq!(refusal.what(), "lock l.json needs a newer shipcraft (format 7; this one knows formats 2 to 6)");
    }

    // Item 105: the tag name grammar.

    #[test]
    fn tag_names_accept_project_release_tags() {
        for name in [
            "deploy-20261112-200036",
            "draken-platform-v0.1.0",
            "packages/api/v1.0.0",
            "a",
            "2.25.0",
            "v2.25",
            "v02.25.0",
            "v2.25.0-rc1",
            "v2.25.0+build",
            "v-1.0.0",
            "a.b",
            "a@b",
            "@a",
            "a@",
            "a{b}",
            "a-",
            "a.lockx",
            "lock",
            "x/lock",
            "a.lock.b",
            "!\"#$%&'()+,;<=>]_`{|}",
        ] {
            assert!(tag_name(name), "{name}");
        }
        // No length limit.
        assert!(tag_name(&"x".repeat(100_000)));
    }

    #[test]
    fn tag_names_refuse_each_forbidden_byte() {
        assert!(!tag_name(""));
        for byte in ['~', '^', ':', '?', '*', '[', '\\', ' ', '\t', '\n', '\u{7f}', '\u{0}', '\u{1f}'] {
            assert!(!tag_name(&format!("a{byte}b")), "{byte:?} inside");
            assert!(!tag_name(&format!("{byte}")), "{byte:?} alone");
        }
        // Every byte outside 0x21-0x7E, non-ASCII included.
        for b in (0u8..=0x20).chain(0x7f..=0x7f) {
            assert!(!tag_name(&format!("a{}b", b as char)), "{b:#x}");
        }
        for name in ["déploy", "v1.0.0é", "日本", "a\u{a0}b"] {
            assert!(!tag_name(name), "{name}");
        }
        // Every other printable ASCII byte is allowed somewhere inside a name.
        for b in 0x21u8..=0x7e {
            let name = format!("a{}b", b as char);
            let forbidden = matches!(b, b'~' | b'^' | b':' | b'?' | b'*' | b'[' | b'\\');
            assert_eq!(tag_name(&name), !forbidden, "{name}");
        }
    }

    #[test]
    fn tag_names_refuse_each_forbidden_sequence() {
        for name in [
            "-a",       // starts with -
            "-",        // starts with -
            "@",        // is @
            "a..b",     // ..
            "..",       // ..
            "v1..0",    // ..
            "a@{b",     // @{
            "@{",       // @{
            "/a",       // starts with /
            "a/",       // ends with /
            "/",        // starts and ends with /
            "a//b",     // //
            "a.",       // ends with .
            ".",        // ends with . / component starts with .
            "v1.0.0.",  // ends with .
            ".a",       // component starts with .
            "a/.b",     // component starts with .
            "a/.b/c",   // component starts with .
            "a.lock",   // component ends in .lock
            "a.lock/b", // component ends in .lock
            "b/a.lock", // component ends in .lock
            ".lock",    // starts with .
        ] {
            assert!(!tag_name(name), "{name}");
        }
        // Allowed neighbours of those rules.
        for name in ["a-", "a-b", "@@", "a@", "a.b.c", "a/b", "a/b.c", "a.lockb", "alock", "a/b-.c"] {
            assert!(tag_name(name), "{name}");
        }
    }

    #[test]
    fn every_item_75_tag_is_a_tag_name() {
        let long = "9".repeat(5000);
        for tag in [
            "v0.0.0".to_string(),
            "v2.25.0".to_string(),
            "v10.200.3000".to_string(),
            format!("v{long}.{long}.{long}"),
            format!("v1{long}.0.0"),
        ] {
            assert!(valid_tag(&tag), "{tag}");
            assert!(tag_name(&tag), "{tag}");
            assert!(!beyond_tag_syntax(&tag), "{tag}");
        }
        // A sweep of short strings over a small alphabet: item 75's syntax
        // always implies a tag name.
        let alphabet = ['v', '0', '1', '.', '-'];
        let mut words = vec![String::new()];
        for _ in 0..7 {
            words = words.iter().flat_map(|w| alphabet.iter().map(move |c| format!("{w}{c}"))).collect();
            for word in &words {
                assert!(!valid_tag(word) || tag_name(word), "{word}");
            }
        }
        assert!(beyond_tag_syntax("deploy-1") && !beyond_tag_syntax("a b"));
    }

    // Item 105: lock format 6 and the writer matrix.

    fn fix(release: Option<&str>) -> Fix {
        Fix { kind: Kind::Fix, reported_at: None, fixes_release: release.map(str::to_string) }
    }

    fn opened(fix: Fix) -> Lock {
        Lock::open(files(), strings(&["a::f", "a::p"]), strings(&["a::f"]), strings(&["a::p"]), fix)
    }

    #[test]
    fn a_new_red_writes_format_6_only_for_a_tag_beyond_item_75() {
        for (fix, format) in [
            (feature(), 5),
            (fix(None), 5),
            (fix(Some("v2.25.0")), 5),
            (fix(Some("deploy-20261112-200036")), 6),
            (fix(Some("v2.25")), 6),
            (fix(Some("packages/api/v1.0.0")), 6),
        ] {
            let lock = opened(fix.clone());
            assert_eq!(lock.formato, format, "{fix:?}");
            assert_eq!(Lock::parse(lock.to_json().as_bytes()).as_ref(), Some(&lock), "{fix:?}");
            let closed = lock.closed();
            assert_eq!(closed.formato, format);
            assert_eq!(Lock::parse(closed.to_json().as_bytes()), Some(closed));
        }
        // Format 5 stays byte for byte what it was: same keys and order.
        let six = opened(fix(Some("deploy-1")));
        let five = opened(fix(Some("v1.0.0")));
        let strip = |lock: &Lock| {
            let mut value = serde_json::to_value(lock).unwrap();
            value.as_object_mut().unwrap().remove("format");
            value.as_object_mut().unwrap().remove("seal");
            value.as_object_mut().unwrap().remove("fixes_release");
            value
        };
        assert_eq!(strip(&six), strip(&five));
        assert!(six.to_json().starts_with("{\n  \"format\": 6,"), "{}", six.to_json());
    }

    #[test]
    fn redo_keeps_6_promotes_4_and_5_to_5_and_keeps_legacy_at_3() {
        let redo =
            |lock: &Lock| lock.redone(files(), lock.cases.clone(), lock.failing_at_red.clone(), strings(&["a::p"]));
        let six = opened(fix(Some("deploy-1")));
        let redone = redo(&six);
        assert_eq!((redone.formato, redone.fix.clone()), (6, six.fix.clone()));
        assert_eq!(redone, six, "an unchanged redo of format 6 reads the same");
        assert!(Lock::parse(redone.to_json().as_bytes()).is_some());
        let changed = six.redone(files(), six.cases.clone(), six.failing_at_red.clone(), Vec::new());
        assert_eq!(changed.formato, 6);
        assert_ne!(changed, six);
        let five = opened(fix(Some("v1.0.0")));
        assert_eq!(redo(&five).formato, 5);
        let four = Lock { formato: 4, controls: None, ..five.clone() }.sealed();
        assert_eq!(redo(&four).formato, 5);
        for legacy in [2, 3] {
            let old = Lock { formato: legacy, controls: None, fix: None, ..five.clone() }.sealed();
            let redone = redo(&old);
            assert_eq!((redone.formato, redone.fix.clone(), redone.controls.clone()), (3, None, None));
        }
    }

    #[test]
    fn format_6_needs_a_fix_with_a_tag_beyond_item_75() {
        let six = opened(fix(Some("deploy-1")));
        let set = |edit: &dyn Fn(&mut serde_json::Map<String, serde_json::Value>)| resealed(&six, |o| edit(o));
        assert!(Lock::parse(&set(&|_| {})).is_some(), "a hand reseal of a valid format 6 lock reads");
        let reported = set(&|o| drop(o.insert("reported_at".into(), "2026-11-12T20:00Z".into())));
        assert!(Lock::parse(&reported).is_some());
        for (what, bad) in [
            ("null fixes_release", set(&|o| drop(o.insert("fixes_release".into(), serde_json::Value::Null)))),
            ("vX.Y.Z fixes_release", set(&|o| drop(o.insert("fixes_release".into(), "v1.0.0".into())))),
            ("not a tag name", set(&|o| drop(o.insert("fixes_release".into(), "a..b".into())))),
            ("non-ASCII", set(&|o| drop(o.insert("fixes_release".into(), "déploy".into())))),
            ("a number", set(&|o| drop(o.insert("fixes_release".into(), 1.into())))),
            ("kind feature", set(&|o| drop(o.insert("kind".into(), "feature".into())))),
            (
                "kind feature, null fields",
                set(&|o| {
                    o.insert("kind".into(), "feature".into());
                    o.insert("fixes_release".into(), serde_json::Value::Null);
                }),
            ),
            ("no controls", set(&|o| drop(o.remove("controls")))),
            ("no fixes_release", set(&|o| drop(o.remove("fixes_release")))),
            ("an extra key", set(&|o| drop(o.insert("extra".into(), 1.into())))),
            (
                "bare digests",
                set(&|o| {
                    let files: serde_json::Map<String, serde_json::Value> = o["files"]
                        .as_object()
                        .unwrap()
                        .iter()
                        .map(|(k, v)| (k.clone(), v.as_str().unwrap().trim_start_matches(PREFIX).into()))
                        .collect();
                    o.insert("files".into(), files.into());
                }),
            ),
        ] {
            assert_eq!(Lock::parse(&bad), None, "{what}");
        }
    }

    #[test]
    fn format_5_still_takes_only_item_75_syntax() {
        let five = opened(fix(Some("v1.0.0")));
        for release in ["deploy-1", "v2.25", "2.25.0", "packages/api/v1.0.0"] {
            let bad = resealed(&five, |o| drop(o.insert("fixes_release".into(), release.into())));
            assert_eq!(Lock::parse(&bad), None, "{release}");
        }
        let four = Lock { formato: 4, controls: None, ..five.clone() }.sealed();
        let bad = resealed(&four, |o| drop(o.insert("fixes_release".into(), "deploy-1".into())));
        assert_eq!(Lock::parse(&bad), None);
        // A format 5 lock relabelled 6 with an item 75 tag is not valid either.
        let relabelled = resealed(&five, |o| drop(o.insert("format".into(), 6.into())));
        assert_eq!(Lock::parse(&relabelled), None);
    }
}
