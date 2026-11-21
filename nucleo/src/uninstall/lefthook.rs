//! Item 148: the lefthook text before `init`'s edit, proven by running that edit again.

use crate::init::LOCAL;
use crate::init_msg::{edit, BLOCKS};
use crate::refusal::failed;

/// The text `O` that `init`'s edit turns into `bytes` (one pass, no repeat); None: none proves.
pub(super) fn undo(bytes: &[u8]) -> Option<Vec<u8>> {
    step(std::str::from_utf8(bytes).ok()?).map(String::into_bytes)
}

/// One proof: the shortest candidate whose edit, in either form, gives `t` byte for byte.
fn step(t: &str) -> Option<String> {
    // Each line through its `\n`, by byte offsets; a last fragment with no `\n` is never cut.
    let ends: Vec<usize> = t.match_indices('\n').map(|(i, _)| i + 1).collect();
    let lines: Vec<(usize, usize)> =
        ends.iter().enumerate().map(|(k, &to)| (if k == 0 { 0 } else { ends[k - 1] }, to)).collect();
    // Per block, its cuts: (start, end) of 1 to 4 lines ending in `run: <run>`, either form.
    let cuts: Vec<Vec<(usize, usize)>> = BLOCKS
        .iter()
        .map(|(_, run)| {
            let forms = [run.to_string(), run.replacen("shipcraft", LOCAL, 1)];
            let mut cuts = Vec::new();
            for (j, &(from, to)) in lines.iter().enumerate() {
                let line = &t[from..to - 1];
                let line = line.strip_suffix('\r').unwrap_or(line);
                if forms.iter().any(|r| line.trim_start_matches(' ').strip_prefix("run: ") == Some(r.as_str())) {
                    cuts.extend((j.saturating_sub(3)..=j).rev().map(|i| (lines[i].0, to)));
                }
            }
            cuts
        })
        .collect();
    let none = [None];
    let mut candidates = Vec::new();
    for a in cuts[0].iter().map(Some).chain(none) {
        for b in cuts[1].iter().map(Some).chain(none) {
            let mut pair: Vec<(usize, usize)> = [a, b].into_iter().flatten().copied().collect();
            pair.sort();
            if pair.is_empty() || pair.windows(2).any(|w| w[0].1 > w[1].0) {
                continue;
            }
            let cut: usize = pair.iter().map(|(from, to)| to - from).sum();
            let low = pair[0].0;
            // The other cut's start; no cut counts as after every offset.
            let other = [a, b].into_iter().flatten().map(|c| c.0).find(|&s| s != low).unwrap_or(usize::MAX);
            candidates.push((std::cmp::Reverse(cut), low, other, pair));
        }
    }
    candidates.sort();
    candidates.into_iter().find_map(|(_, _, _, pair)| {
        let mut o = String::new();
        let mut from = 0;
        for (start, end) in &pair {
            o.push_str(&t[from..*start]);
            from = *end;
        }
        o.push_str(&t[from..]);
        let gives = |local| edit(&o, "", local, || Err(failed(""))).is_ok_and(|new| new.as_deref() == Some(t));
        (gives(false) || gives(true)).then_some(o)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const MSG: &str = "commit-msg:\n  commands:\n    shipcraft:\n      run: shipcraft check --commit-msg\n";
    const CLOSE: &str = "post-commit:\n  commands:\n    shipcraft:\n      run: shipcraft close\n";

    fn back(t: &str) -> Option<String> {
        undo(t.as_bytes()).map(|o| String::from_utf8(o).unwrap())
    }

    #[test]
    fn undoes_the_whole_blocks_of_the_common_case() {
        let base = "pre-commit:\n  commands:\n    lint:\n      run: echo lint\n";
        assert_eq!(back(&format!("{base}{MSG}{CLOSE}")).as_deref(), Some(base));
        assert_eq!(back(&format!("{MSG}{CLOSE}")).as_deref(), Some(""));
        let local = format!("{MSG}{CLOSE}").replace("run: shipcraft", "run: ./node_modules/.bin/shipcraft");
        assert_eq!(back(&local).as_deref(), Some(""));
        let crlf = format!("{base}{MSG}{CLOSE}").replace('\n', "\r\n");
        assert_eq!(back(&crlf), Some(base.replace('\n', "\r\n")));
    }

    #[test]
    fn existing_blocks_keep_their_commands() {
        let base = "commit-msg:\n  commands:\n    lint:\n      run: echo msg\npost-commit:\n";
        let t = "commit-msg:\n  commands:\n    lint:\n      run: echo msg\n    shipcraft:\n      run: shipcraft check --commit-msg\npost-commit:\n  commands:\n    shipcraft:\n      run: shipcraft close\n";
        let edited = edit(base, "", false, || Err(failed(""))).ok().flatten();
        assert_eq!(edited.as_deref(), Some(t));
        // Known limit: the empty `post-commit:` key goes with the command.
        assert_eq!(back(t).as_deref(), Some("commit-msg:\n  commands:\n    lint:\n      run: echo msg\n"));
    }

    #[test]
    fn a_mixed_pair_is_left() {
        let local = MSG.replace("run: shipcraft", "run: ./node_modules/.bin/shipcraft");
        // One form's command was there before this edit, so what is proven still says shipcraft.
        let mixed = format!("a: 1\n{local}{CLOSE}");
        assert!(back(&mixed).is_some_and(|o| o.contains("shipcraft") && o.starts_with("a: 1\n")));
        assert_eq!(back(&format!("a: 1\n{local}")), None);
    }

    #[test]
    fn what_init_does_not_write_proves_nothing() {
        for t in [
            MSG.replace("--commit-msg", "--commit-msg {1}"),
            format!("{MSG}{CLOSE}").replace("run: shipcraft close", "run: shipcraft close\n      skip: true"),
            "pre-commit:\n  commands:\n    lint:\n      run: echo lint\n".into(),
            format!("{MSG}{CLOSE}").trim_end().to_string(),
        ] {
            let o = back(&t);
            assert!(o.as_ref().is_none_or(|o| o.contains("shipcraft")), "{t:?} -> {o:?}");
        }
        assert_eq!(undo(b"\xff shipcraft\n"), None);
        // One block proven alone, the other edited by hand: init refuses that text, so nothing proves.
        let edited = format!("{}{CLOSE}", MSG.replace("--commit-msg", "--commit-msg {1}"));
        assert_eq!(back(&edited), None);
    }
}
