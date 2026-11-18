//! Item 121: `report --findings [--json] [--since <pr>]`, the ledger of the
//! Blocking findings the review comments of merged PRs raised, grouped by
//! class. A reading only: `gh` through `report --github`'s asker, the root by
//! `report`'s discovery, no git, no file written, exit 0.

use crate::refusal::Result;
use crate::relatorio::discover;
use crate::relatorio_gh::Asker;
use regex::{Regex, RegexBuilder};
use serde_json::{json, Value};

/// The classes, in order: a finding takes the first whose pattern matches its
/// title (case-insensitive, anywhere), else `Other`.
const CLASSES: [(&str, &str); 11] = [
    (
        "Typed input lost (leave, reload, refresh over a dirty form)",
        r"typed|\binput\b|dirty|discard|clobber|\bleav|unmount|navigat|\bform\b",
    ),
    (
        "Session, workspace or project boundary (sign-out, another user, slug, tenant)",
        r"sign.?out|sign.?in|previous user|another (user|person|workspace|project)|workspace|tenant|cross|leak|slug|secret|\bmix",
    ),
    (
        "Order and overlap (late or out-of-order response, overlapping saves, retry, during a refresh)",
        r"overwrit|delayed|overlap|concurren|stale|older|newer|\blate\b|pending|during|while|race|retry|out of order|in.?flight|queued|twice|duplicate|settle",
    ),
    (
        "Failure paths (error, refusal, 4xx/5xx, partial failure)",
        r"fail|falh|error|erro\b|refus|reject|throw|\b[45]\d\d\b|partial|timeout",
    ),
    ("Permissions and roles", r"permission|admin|role|approver|owner|member|access|authori"),
    (
        "Consent, tracking and conversions (pixel, cookies, attribution, events)",
        r"pixel|cookie|consent|recus|revoga|revocation|convers|_ga|\blead\b|oppref|origem|utm|video_start|whatsapp|calend|\bmeta\b|refer",
    ),
    (
        "Markdown, MDX and link handling (a syntax form that slips past a check)",
        r"markdown|\bmdx\b|link|anchor|âncora|autolink|\bhtml\b|setext|\bh[12]\b|emphasis|bold|parênteses|parenthes|\burls?\b|destin",
    ),
    (
        "Signature, review and publish state (draft, live, export, deploy)",
        r"assinatura|signature|\bsign|draft|rascunho|publica|publish|\blive\b|no ar|deploy|export|rollback|manifest|build|archive|prévia|preview|revis|agend|schedul",
    ),
    (
        "Dates, numbers and declared limits",
        r"\bdata\b|\bdate|\bdia\b|\bday|\byear|\bano|numer|número|valor|value|percent|deadline|prazo|limit|expir|lifetime|threshold",
    ),
    (
        "Paths, files and locks (symlink, slash, backup, directory)",
        r"symlink|\bpath|caminho|diretório|director|slash|backup|\block\b",
    ),
    (
        "Setup, docs and deploy wiring (entry point, provisioning, migration)",
        r"documented|entry point|provision|firestore|hosting|migration|onboarding|target|rewrite|executable|image",
    ),
];
const OTHER: &str = "Other";
/// The comment `pr` and `review --pr` post with a verdict (item 38).
const REVIEW: &str = "**shipcraft: review executed by ";
const LOCATIONS: [&str; 4] = ["Location:", "Locations:", "**Location:**", "**Locations:**"];

struct Finding {
    pr: u64,
    title: String,
    location: Option<String>,
}

/// `--since`'s value: 1 to 19 ASCII digits, at least 1.
pub fn since(value: &str) -> Option<u64> {
    let digits = (1..=19).contains(&value.len()) && value.bytes().all(|b| b.is_ascii_digit());
    digits.then(|| value.parse().ok()).flatten().filter(|n| *n >= 1)
}

pub fn run(as_json: bool, since: Option<u64>) -> Result<()> {
    let out = match discover() {
        None => not_read("no git repository found", as_json),
        Some((root, _)) => ledger(&mut Asker::new(&root, None), as_json, since),
    };
    print!("{out}");
    Ok(())
}

fn not_read(reason: &str, as_json: bool) -> String {
    match as_json {
        true => format!("{}\n", json!({"kind": "findings_not_read", "reason": reason})),
        false => format!("review findings not read: {reason}\n"),
    }
}

fn ledger(asker: &mut Asker, as_json: bool, since: Option<u64>) -> String {
    let list = ["pr", "list", "--state", "merged", "--limit", "1000", "--json", "number"];
    let mut prs = match asker.ask(&list, merged) {
        Ok(prs) => prs,
        Err(reason) => return not_read(&reason, as_json),
    };
    prs.retain(|n| *n >= since.unwrap_or(1));
    prs.sort_unstable_by(|a, b| b.cmp(a));
    prs.dedup();
    let classes: Vec<Regex> = CLASSES
        .iter()
        .map(|(_, p)| RegexBuilder::new(p).case_insensitive(true).build().expect("a class pattern"))
        .collect();
    let mut groups: Vec<Vec<Finding>> = (0..=CLASSES.len()).map(|_| Vec::new()).collect();
    let mut unread: Vec<(u64, String)> = Vec::new();
    for pr in prs {
        let path = format!("repos/{{owner}}/{{repo}}/issues/{pr}/comments?per_page=100");
        let bodies = match asker.ask(&["api", "--paginate", "--slurp", &path], bodies) {
            Ok(bodies) => bodies,
            Err(reason) => {
                eprintln!("report: PR {pr}: review comments not read: {reason}");
                unread.push((pr, reason));
                continue;
            }
        };
        for body in bodies.iter().filter(|b| b.starts_with(REVIEW)) {
            let (found, warning) = comment(body);
            if let Some(warning) = warning {
                eprintln!("report: PR {pr}: {warning}");
            }
            for (title, location) in found {
                let class = classes.iter().position(|c| c.is_match(&title)).unwrap_or(CLASSES.len());
                groups[class].push(Finding { pr, title, location });
            }
        }
    }
    let names = CLASSES.iter().map(|(name, _)| *name).chain([OTHER]);
    let mut out = String::new();
    if as_json {
        for (pr, reason) in &unread {
            out += &format!("{}\n", json!({"kind": "pr_not_read", "pr": pr, "reason": reason}));
        }
        for (name, list) in names.zip(&groups) {
            for f in list {
                let line =
                    json!({"kind": "finding", "pr": f.pr, "class": name, "title": f.title, "location": f.location});
                out += &format!("{line}\n");
            }
        }
        return out;
    }
    let command = since.map_or(String::new(), |n| format!(" --since {n}"));
    out += "# Review findings\n\nEvery Blocking finding the review raised on merged PRs, grouped by class, from the highest PR number down.\n";
    out += &format!("Generated by `shipcraft report --findings{command}`; do not edit by hand.\n\n");
    if !unread.is_empty() {
        let prs: Vec<String> = unread.iter().map(|(pr, reason)| format!("PR {pr} ({reason})")).collect();
        out += &format!("Not read: {}.\n\n", prs.join(", "));
    }
    for (name, list) in names.zip(&groups).filter(|(_, list)| !list.is_empty()) {
        out += &format!("## {name} ({})\n\n", list.len());
        for f in list {
            let at = f.location.as_ref().map_or(String::new(), |l| format!(" ({l})"));
            out += &format!("- {}{at} (PR {})\n", f.title, f.pr);
        }
        out += "\n";
    }
    out
}

/// The merged-PR list: an array of objects, each a `number` above 0.
fn merged(answer: &Value) -> Option<Vec<u64>> {
    let entries = answer.as_array()?;
    entries.iter().map(|e| e.as_object()?.get("number")?.as_u64().filter(|n| *n > 0)).collect()
}

/// A slurped comments answer, checked whole: a non-empty array of pages, each
/// an array of objects with a string `body`; the bodies in order.
fn bodies(answer: &Value) -> Option<Vec<String>> {
    let mut out = Vec::new();
    for page in answer.as_array().filter(|p| !p.is_empty())? {
        for e in page.as_array()? {
            out.push(e.as_object()?.get("body")?.as_str()?.to_string());
        }
    }
    Some(out)
}

/// A review comment's findings (title, location), in order, and the count
/// warning when its first `Blocking: <d>` line differs from the headings read.
fn comment(body: &str) -> (Vec<(String, Option<String>)>, Option<String>) {
    let lines: Vec<&str> =
        body.split('\n').map(|l| l.strip_suffix('\r').unwrap_or(l).trim_end_matches([' ', '\t'])).collect();
    let heads: Vec<(usize, &str)> = lines.iter().enumerate().filter_map(|(i, l)| Some((i, heading(l)?))).collect();
    let found: Vec<(String, Option<String>)> = heads
        .iter()
        .enumerate()
        .map(|(j, &(i, rest))| {
            let end = heads.get(j + 1).map_or(lines.len(), |h| h.0);
            (title(rest), location(&lines[i + 1..end]))
        })
        .collect();
    let declared = lines.iter().find_map(|l| {
        let d = l.strip_prefix("Blocking: ")?;
        ((1..=19).contains(&d.len()) && d.bytes().all(|b| b.is_ascii_digit())).then_some(d)
    });
    let warning = declared
        .filter(|d| d.parse::<u64>().ok() != Some(found.len() as u64))
        .map(|d| format!("the review says Blocking: {d}, {} Blocking heading(s) read", found.len()));
    (found, warning)
}

/// A Blocking heading's `<rest>`: `##`-`####`, spaces, `Blocking`, spaces,
/// digits, rest; or `**Blocking`, spaces, digits, a rest with no `*`, `**`.
fn heading(line: &str) -> Option<&str> {
    let hashes = line.bytes().take_while(|&b| b == b'#').count();
    if (2..=4).contains(&hashes) {
        let after = line[hashes..].strip_prefix(' ')?.trim_start_matches(' ');
        return number(after.strip_prefix("Blocking")?);
    }
    let inner = line.strip_prefix("**Blocking")?.strip_suffix("**")?;
    number(inner).filter(|rest| !rest.contains('*'))
}

/// One or more spaces, then one or more digits: what follows them.
fn number(text: &str) -> Option<&str> {
    let text = text.strip_prefix(' ')?.trim_start_matches(' ');
    let rest = text.trim_start_matches(|c: char| c.is_ascii_digit());
    (rest.len() < text.len()).then_some(rest)
}

fn title(rest: &str) -> String {
    let title = rest.trim_start_matches([' ', '\t', ':', '.', '-', '—', '–']).trim_end_matches([' ', '\t']);
    match title {
        "" => "(no title)".to_string(),
        title => title.to_string(),
    }
}

/// The rest of the first location line, when not empty.
fn location(text: &[&str]) -> Option<String> {
    let rest = text.iter().find_map(|l| LOCATIONS.iter().find_map(|p| l.strip_prefix(p)))?;
    Some(rest.trim_matches([' ', '\t']).to_string()).filter(|r| !r.is_empty())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn since_is_a_pr_number() {
        assert_eq!(since("007"), Some(7));
        assert_eq!(since("9999999999999999999"), Some(9_999_999_999_999_999_999));
        for bad in ["0", "000", "-3", "+3", "v2.1.0", "1.5", "", " 1", "12345678901234567890"] {
            assert_eq!(since(bad), None, "{bad}");
        }
    }

    #[test]
    fn heading_grammar() {
        let yes = [
            ("## Blocking 1 — Title", " — Title"),
            ("### Blocking 2: Title", ": Title"),
            ("#### Blocking 3", ""),
            ("##   Blocking   12x", "x"),
            ("**Blocking 1 — Title**", " — Title"),
            ("**Blocking 4**", ""),
        ];
        for (line, rest) in yes {
            assert_eq!(heading(line), Some(rest), "{line}");
        }
        let no = [
            "## Blocking findings",
            "**Blocking:**",
            " ## Blocking 1 — x",
            "- **Blocking 1** — x",
            "Blocking: 4",
            "# Blocking 1",
            "##### Blocking 1",
            "##Blocking 1",
            "## blocking 1",
            "##\tBlocking 1",
            "## Blocking\t1",
            "**Blocking 1 *bold* x**",
            "**Blocking 1**x",
            "**Blocking**",
        ];
        for line in no {
            assert_eq!(heading(line), None, "{line}");
        }
    }

    #[test]
    fn title_strips_separators() {
        assert_eq!(title(" — Title  "), "Title");
        assert_eq!(title(": - . – Title: x"), "Title: x");
        assert_eq!(title("\t"), "(no title)");
        assert_eq!(title(""), "(no title)");
    }

    #[test]
    fn location_forms() {
        for (line, at) in [
            ("Location: a.rs:1", "a.rs:1"),
            ("Locations: a, b", "a, b"),
            ("**Location:** `x.ts`", "`x.ts`"),
            ("**Locations:** \tx, y\t", "x, y"),
        ] {
            assert_eq!(location(&["text", line, "Location: later"]), Some(at.to_string()), "{line}");
        }
        assert_eq!(location(&["Location:", "Location: later"]), None);
        assert_eq!(location(&[" Location: x", "location: y", "**Location**: z"]), None);
    }

    #[test]
    fn comment_reads_findings_and_checks_the_count() {
        let body = "**shipcraft: review executed by x**\r\nBlocking: 3\n## Blocking 1 — A \r\nLocation: one\n\
                    **Blocking 2 — B**\ntext\n### Blocking 3: C\n**Locations:** three\nBlocking: 9\n";
        let (found, warning) = comment(body);
        let want = [("A", Some("one")), ("B", None), ("C", Some("three"))];
        let want: Vec<_> = want.iter().map(|(t, l)| (t.to_string(), l.map(str::to_string))).collect();
        assert_eq!(found, want);
        assert_eq!(warning, None);
        let (found, warning) = comment("Blocking: 02\n## Blocking 1 — A\nBlocking: 1");
        assert_eq!(found.len(), 1);
        assert_eq!(warning.as_deref(), Some("the review says Blocking: 02, 1 Blocking heading(s) read"));
        assert_eq!(comment("Blocking: 1x\nBlocking:  1\n").1, None);
    }

    #[test]
    fn class_table_order() {
        let classes: Vec<Regex> =
            CLASSES.iter().map(|(_, p)| RegexBuilder::new(p).case_insensitive(true).build().unwrap()).collect();
        let class = |t: &str| classes.iter().position(|c| c.is_match(t)).map_or(OTHER, |i| CLASSES[i].0);
        assert_eq!(class("Secrets cross workspace boundaries when project slugs match"), CLASSES[1].0);
        assert_eq!(class("Delayed approval overwrites a newer, confirmed answer"), CLASSES[2].0);
        assert_eq!(class("Numeric deadlines escape citation checks"), CLASSES[8].0);
        assert_eq!(class("Bold formatting bypasses monetary-value verification"), CLASSES[6].0);
        assert_eq!(class("TYPED text vanishes"), CLASSES[0].0);
        assert_eq!(class("Âncora quebrada"), CLASSES[6].0);
        assert_eq!(class("Nothing here"), OTHER);
    }

    #[test]
    fn answers_are_read_whole() {
        assert_eq!(merged(&json!([{"number": 3, "x": 1}, {"number": 3}])), Some(vec![3, 3]));
        for bad in [json!([{"number": 0}]), json!([{"number": 7.0}]), json!([{"number": "7"}]), json!({})] {
            assert_eq!(merged(&bad), None, "{bad}");
        }
        assert_eq!(bodies(&json!([[], [{"body": "a"}]])), Some(vec!["a".to_string()]));
        assert_eq!(bodies(&json!([])), None);
        assert_eq!(bodies(&json!([[{"body": "a"}], [{"body": 1}]])), None);
    }
}
