//! Test globs: `**` spans directories, `*`, `?` and a class (`[ab]`, `[a-z]`,
//! `[!a]`) stay inside one name.

pub fn matches(pattern: &str, path: &str) -> bool {
    let pattern: Vec<&str> = pattern.split('/').collect();
    let path: Vec<&str> = path.split('/').collect();
    match_parts(&pattern, &path)
}

fn match_parts(pattern: &[&str], path: &[&str]) -> bool {
    match pattern.split_first() {
        None => path.is_empty(),
        Some((&"**", rest)) => (0..=path.len()).any(|skip| match_parts(rest, &path[skip..])),
        Some((part, rest)) => match path.split_first() {
            Some((name, path_rest)) => match_name(part.as_bytes(), name.as_bytes()) && match_parts(rest, path_rest),
            None => false,
        },
    }
}

fn match_name(pattern: &[u8], name: &[u8]) -> bool {
    if let (Some(b'['), Some(&n)) = (pattern.first(), name.first()) {
        if let Some((hit, len)) = class(pattern, n) {
            return hit && match_name(&pattern[len..], &name[1..]);
        }
    }
    match (pattern.first(), name.first()) {
        (None, None) => true,
        (Some(b'*'), _) => match_name(&pattern[1..], name) || (!name.is_empty() && match_name(pattern, &name[1..])),
        (Some(b'?'), Some(_)) => match_name(&pattern[1..], &name[1..]),
        (Some(p), Some(n)) if p == n => match_name(&pattern[1..], &name[1..]),
        _ => false,
    }
}

/// Whether `n` is in the class that opens `pattern`, and the class's length;
/// None when the `[` closes no class (then it is a plain `[`).
fn class(pattern: &[u8], n: u8) -> Option<(bool, usize)> {
    let negated = matches!(pattern.get(1), Some(b'!' | b'^'));
    let start = 1 + usize::from(negated);
    let end = start + 1 + pattern.get(start + 1..)?.iter().position(|&b| b == b']')?;
    let set = &pattern[start..end];
    let (mut hit, mut i) = (false, 0);
    while i < set.len() {
        if i + 2 < set.len() && set[i + 1] == b'-' {
            hit |= (set[i]..=set[i + 2]).contains(&n);
            i += 3;
        } else {
            hit |= set[i] == n;
            i += 1;
        }
    }
    Some((hit != negated, end + 1))
}
