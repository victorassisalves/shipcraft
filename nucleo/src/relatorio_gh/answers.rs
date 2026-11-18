//! The shapes of `gh`'s answers that several readers share.

use crate::relatorio::days_from_civil;
use serde_json::{Map, Value};

/// `pr view`'s answer, in its shape: `number` the PR asked, `state` a string,
/// `mergedAt` a string or null, `headRefOid` a string, `mergeCommit` null or
/// an object with a string `oid`.
pub(super) struct PrView<'v> {
    pub(super) state: &'v str,
    pub(super) merged_at: Option<&'v str>,
    pub(super) head: &'v str,
    pub(super) merge: Option<&'v str>,
}

impl<'v> PrView<'v> {
    pub(super) fn read(answer: &'v Value, pr: u64) -> Option<PrView<'v>> {
        let o = answer.as_object()?;
        if o.get("number")?.as_u64() != Some(pr) {
            return None;
        }
        let merged_at = match o.get("mergedAt")? {
            Value::Null => None,
            v => Some(v.as_str()?),
        };
        let merge = match o.get("mergeCommit")? {
            Value::Null => None,
            v => Some(v.as_object()?.get("oid")?.as_str()?),
        };
        Some(PrView { state: o.get("state")?.as_str()?, merged_at, head: o.get("headRefOid")?.as_str()?, merge })
    }
}

/// A slurped paginated answer: a non-empty array of pages, each an object with
/// the same non-negative integer `total_count` and an array `list`, the entries
/// of all pages numbering that count, every entry an object that `entry` accepts.
pub(super) fn pages<'v>(
    answer: &'v Value,
    list: &str,
    entry: fn(&Map<String, Value>) -> bool,
) -> Option<Vec<&'v Map<String, Value>>> {
    let pages = answer.as_array().filter(|p| !p.is_empty())?;
    let mut total = None;
    let mut entries = Vec::new();
    for page in pages {
        let page = page.as_object()?;
        let count = page.get("total_count")?.as_u64()?;
        if total.is_some_and(|t| t != count) {
            return None;
        }
        total = Some(count);
        for e in page.get(list)?.as_array()? {
            entries.push(e.as_object().filter(|e| entry(e))?);
        }
    }
    (entries.len() as u64 == total?).then_some(entries)
}

/// Item 79's check-run entry: a string `name`, a string `status` and a
/// `conclusion` that is a string or null.
pub(super) fn check_run(e: &Map<String, Value>) -> bool {
    e.get("name").is_some_and(Value::is_string)
        && e.get("status").is_some_and(Value::is_string)
        && e.get("conclusion").is_some_and(|c| c.is_string() || c.is_null())
}

/// 40 lowercase hex characters.
pub fn oid(text: &str) -> bool {
    text.len() == 40 && text.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

/// GitHub's UTC form `YYYY-MM-DDTHH:MM:SSZ`, a real date in years 0001 to
/// 9999, as Unix seconds; any other text is not a time.
pub(super) fn time(text: &str) -> Option<i64> {
    let b = text.as_bytes();
    if b.len() != 20 || [b[4], b[7], b[10], b[13], b[16], b[19]] != *b"--T::Z" {
        return None;
    }
    let n = |r: std::ops::Range<usize>| -> Option<i64> {
        b[r.clone()].iter().all(u8::is_ascii_digit).then(|| text[r].parse().ok())?
    };
    let (y, mo, d, h, mi, s) = (n(0..4)?, n(5..7)?, n(8..10)?, n(11..13)?, n(14..16)?, n(17..19)?);
    let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);
    let days = match mo {
        2 if leap => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        1..=12 => 31,
        _ => return None,
    };
    if y < 1 || d < 1 || d > days || h > 23 || mi > 59 || s > 59 {
        return None;
    }
    Some(days_from_civil(y, mo, d) * 86_400 + h * 3600 + mi * 60 + s)
}
