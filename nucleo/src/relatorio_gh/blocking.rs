//! Item 113's reading of the review statuses.

use super::answers::time;
use super::UNREADABLE;
use serde_json::Value;

/// Item 113: a slurped statuses list (a non-empty array of array pages, every
/// entry an object with a string `context`; a `shipcraft/review` entry also a
/// string or null `description` and a time `created_at`). The count of the
/// review status with a count whose `created_at` is latest, the first in
/// answer order on equal times.
pub(super) fn latest_count(answer: &Value) -> Result<u64, &'static str> {
    let pages = answer.as_array().filter(|p| !p.is_empty()).ok_or(UNREADABLE)?;
    let mut latest: Option<(i64, u64)> = None;
    for page in pages {
        for entry in page.as_array().ok_or(UNREADABLE)? {
            let entry = entry.as_object().ok_or(UNREADABLE)?;
            if entry.get("context").and_then(Value::as_str).ok_or(UNREADABLE)? != "shipcraft/review" {
                continue;
            }
            let description = match entry.get("description") {
                Some(Value::Null) => None,
                Some(Value::String(d)) => Some(d.as_str()),
                _ => return Err(UNREADABLE),
            };
            let at = entry.get("created_at").and_then(Value::as_str).and_then(time).ok_or(UNREADABLE)?;
            if let Some(count) = description.and_then(blocking_count) {
                if latest.is_none_or(|(t, _)| at > t) {
                    latest = Some((at, count));
                }
            }
        }
    }
    latest.map(|(_, count)| count).ok_or("no blocking count at commit")
}

/// Item 113: a review description's count: one of the two verdict prefixes,
/// then 1 to 9 ASCII digits, then the end or a space.
pub(super) fn blocking_count(description: &str) -> Option<u64> {
    let rest = ["on this machine: APPROVE, Blocking ", "on this machine: CHANGES REQUESTED, Blocking "]
        .iter()
        .find_map(|prefix| description.strip_prefix(prefix))?;
    let digits = rest.bytes().take_while(u8::is_ascii_digit).count();
    if !(1..=9).contains(&digits) || !matches!(rest.as_bytes().get(digits), None | Some(b' ')) {
        return None;
    }
    rest[..digits].parse().ok()
}
