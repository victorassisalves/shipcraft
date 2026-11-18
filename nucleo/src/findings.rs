//! Item 121: `report --findings [--json] [--since <pr>]`, the ledger of the
//! Blocking findings the review comments of merged PRs raised, grouped by
//! class. A reading only: `gh` through `report --github`'s asker, the root by
//! `report`'s discovery, no git, no file written, exit 0. Item 122: the
//! project's own classes from `[findings]`, before the built-in ones.

use crate::config::CONFIG_FILE;
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
const LOCATIONS: [&str; 6] = ["Location:", "Locations:", "**Location:**", "**Locations:**", "Local:", "**Local:**"];

/// Item 122: one class of the table in effect; `Other` is not one.
pub struct Class {
    name: String,
    keywords: Vec<Regex>,
    source: &'static str,
}

/// Item 121's options: case-insensitive, Unicode, the crate's default limits.
fn pattern(text: &str) -> Option<Regex> {
    RegexBuilder::new(text).case_insensitive(true).build().ok()
}

/// Item 122: the reason an invalid `[findings]` gives, in the refusal and in
/// `report --findings`'s not-read line.
pub fn invalid(problem: &str) -> String {
    format!("[findings] in {CONFIG_FILE} is invalid: {problem}")
}

/// A key as a problem names it: as written when plain, else a JSON string.
fn key_name(key: &str) -> String {
    match !key.is_empty() && key.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-') {
        true => key.to_string(),
        false => Value::from(key).to_string(),
    }
}

/// The first key of a table outside `known`, in byte order.
fn unknown_key(table: &toml::Table, known: &[&str]) -> Option<String> {
    let mut keys: Vec<&String> = table.keys().filter(|k| !known.contains(&k.as_str())).collect();
    keys.sort();
    keys.first().map(|k| key_name(k))
}

/// Item 122 point 2: the class table in effect (without `Other`) from the
/// config parsed as TOML, or the first problem in the spec's order.
pub fn classes(config: &toml::Table) -> std::result::Result<Vec<Class>, String> {
    let builtin = || {
        CLASSES.iter().map(|(name, p)| Class {
            name: name.to_string(),
            keywords: vec![pattern(p).expect("a class pattern")],
            source: "builtin",
        })
    };
    let Some(findings) = config.get("findings") else { return Ok(builtin().collect()) };
    let findings = findings.as_table().ok_or("[findings] is not a table")?;
    if let Some(key) = unknown_key(findings, &["builtin_classes", "class"]) {
        return Err(format!("unknown key {key}"));
    }
    let with_builtin = match findings.get("builtin_classes") {
        None => true,
        Some(value) => value.as_bool().ok_or("builtin_classes is not a boolean")?,
    };
    let declared = match findings.get("class") {
        None => Vec::new(),
        Some(value) => value
            .as_array()
            .and_then(|a| a.iter().map(toml::Value::as_table).collect::<Option<Vec<_>>>())
            .ok_or("class is not an array of tables")?,
    };
    let mut table: Vec<Class> = Vec::new();
    for (i, class) in declared.into_iter().enumerate() {
        let i = i + 1;
        table.push(declared_class(class, &table, with_builtin).map_err(|p| format!("class {i}: {p}"))?);
    }
    if with_builtin {
        table.extend(builtin());
    }
    Ok(table)
}

/// One `[[findings.class]]`, checked after the classes declared before it.
fn declared_class(class: &toml::Table, earlier: &[Class], with_builtin: bool) -> std::result::Result<Class, String> {
    if let Some(key) = unknown_key(class, &["name", "keywords"]) {
        return Err(format!("unknown key {key}"));
    }
    let name = class.get("name").ok_or("name is missing")?.as_str().ok_or("name is not a string")?;
    if name.trim_matches([' ', '\t']).is_empty() {
        return Err("name is empty".to_string());
    }
    if name.chars().any(|c| c <= '\u{1f}' || c == '\u{7f}') {
        return Err("name has a control character".to_string());
    }
    let taken = name == OTHER
        || earlier.iter().any(|c| c.name == name)
        || (with_builtin && CLASSES.iter().any(|(n, _)| *n == name));
    if taken {
        return Err(format!("name {name} is already a class"));
    }
    let keywords = class.get("keywords").ok_or("keywords is missing")?.as_array().ok_or("keywords is not an array")?;
    if keywords.is_empty() {
        return Err("keywords is empty".to_string());
    }
    let mut built = Vec::new();
    for (j, keyword) in keywords.iter().enumerate() {
        let j = j + 1;
        let text = keyword.as_str().ok_or_else(|| format!("keyword {j} is not a string"))?;
        if text.is_empty() {
            return Err(format!("keyword {j} is empty"));
        }
        built.push(pattern(text).ok_or_else(|| format!("keyword {j} is not a valid pattern"))?);
    }
    Ok(Class { name: name.to_string(), keywords: built, source: "project" })
}

/// Item 122 point 3: `<root>/.shipcraft.toml` from the working tree, as item
/// 99's reader reads `[report]`; a file it does not read is the built-in table.
fn read_classes(root: &std::path::Path) -> std::result::Result<Vec<Class>, String> {
    let path = root.join(CONFIG_FILE);
    let text = std::fs::metadata(&path)
        .is_ok_and(|m| m.is_file())
        .then(|| std::fs::read(&path).ok().and_then(|b| String::from_utf8(b).ok()))
        .flatten();
    let table = text.and_then(|t| t.parse::<toml::Table>().ok()).unwrap_or_default();
    classes(&table)
}

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
        Some((root, _)) => match read_classes(&root) {
            Ok(classes) => ledger(&mut Asker::new(&root, None), &classes, as_json, since),
            Err(problem) => not_read(&invalid(&problem), as_json),
        },
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

fn ledger(asker: &mut Asker, classes: &[Class], as_json: bool, since: Option<u64>) -> String {
    let list = ["pr", "list", "--state", "merged", "--limit", "1000", "--json", "number"];
    let mut prs = match asker.ask(&list, merged) {
        Ok(prs) => prs,
        Err(reason) => return not_read(&reason, as_json),
    };
    prs.retain(|n| *n >= since.unwrap_or(1));
    prs.sort_unstable_by(|a, b| b.cmp(a));
    prs.dedup();
    let mut groups: Vec<Vec<Finding>> = (0..=classes.len()).map(|_| Vec::new()).collect();
    let mut unread: Vec<(u64, String)> = Vec::new();
    let mut mismatches: Vec<(u64, Mismatch)> = Vec::new();
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
            let (found, mismatch) = comment(body);
            if let Some((d, k)) = mismatch {
                eprintln!("report: PR {pr}: the review says Blocking: {d}, {k} Blocking heading(s) read");
                mismatches.push((pr, (d, k)));
            }
            for (title, location) in found {
                groups[class_of(classes, &title)].push(Finding { pr, title, location });
            }
        }
    }
    let names = classes.iter().map(|c| (c.name.as_str(), Some(c.source))).chain([(OTHER, None)]);
    let mut out = String::new();
    if as_json {
        for (pr, reason) in &unread {
            out += &format!("{}\n", json!({"kind": "pr_not_read", "pr": pr, "reason": reason}));
        }
        for ((name, source), list) in names.zip(&groups) {
            for f in list {
                let line = json!({"kind": "finding", "pr": f.pr, "class": name, "class_source": source,
                    "title": f.title, "location": f.location});
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
    if !mismatches.is_empty() {
        let prs: Vec<String> =
            mismatches.iter().map(|(pr, (d, k))| format!("PR {pr} (Blocking: {d}, {k} read)")).collect();
        out += &format!("Count mismatch: {}.\n\n", prs.join(", "));
    }
    for ((name, _), list) in names.zip(&groups).filter(|(_, list)| !list.is_empty()) {
        out += &format!("## {name} ({})\n\n", list.len());
        for f in list {
            let at = f.location.as_ref().map_or(String::new(), |l| format!(" ({l})"));
            out += &format!("- {}{at} (PR {})\n", f.title, f.pr);
        }
        out += "\n";
    }
    out
}

/// The first class of the table whose keyword matches, else `Other`'s index.
fn class_of(classes: &[Class], title: &str) -> usize {
    classes.iter().position(|c| c.keywords.iter().any(|k| k.is_match(title))).unwrap_or(classes.len())
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

/// Item 126 point 2: the end line; no line from it on is a candidate.
const END: &str = r"(?i)^(?:#{2,4} +(?:Notes\b|Notas\b|Own checks\b|Non-blocking\b|Não bloqueante)|\*\*(?:Notes\b|Notas\b|Own checks\b|Non-blocking\b|Não bloqueante)[^*]*\*\*)";
/// A count check that warns: the declared `<d>` as written, the findings kept.
type Mismatch = (String, usize);

/// A review comment's findings (title, location), in order, and the count
/// mismatch when its first `Blocking: <d>` line differs from the findings kept.
fn comment(body: &str) -> (Vec<(String, Option<String>)>, Option<Mismatch>) {
    static END_LINE: std::sync::OnceLock<Regex> = std::sync::OnceLock::new();
    let end_line = END_LINE.get_or_init(|| Regex::new(END).expect("the end-line pattern"));
    let lines: Vec<&str> =
        body.split('\n').map(|l| l.strip_suffix('\r').unwrap_or(l).trim_end_matches([' ', '\t'])).collect();
    let end = lines.iter().position(|l| end_line.is_match(l)).unwrap_or(lines.len());
    let heads: Vec<(usize, bool, &str)> =
        lines[..end].iter().enumerate().filter_map(|(i, l)| heading(l).map(|(k, r)| (i, k, r))).collect();
    let declared = lines.iter().find_map(|l| {
        let d = l.strip_prefix("Blocking: ")?;
        ((1..=19).contains(&d.len()) && d.bytes().all(|b| b.is_ascii_digit())).then_some(d)
    });
    let numbered =
        heads.iter().all(|h| !h.1) && declared.and_then(|d| d.parse::<u64>().ok()) == Some(heads.len() as u64);
    let found: Vec<(String, Option<String>)> = heads
        .iter()
        .enumerate()
        .filter(|(_, h)| h.1 || numbered)
        .map(|(j, &(i, _, rest))| {
            let stop = heads.get(j + 1).map_or(end, |h| h.0);
            (title(rest), location(&lines[i + 1..stop]))
        })
        .collect();
    let mismatch =
        declared.filter(|d| d.parse::<u64>().ok() != Some(found.len() as u64)).map(|d| (d.to_string(), found.len()));
    (found, mismatch)
}

const WORDS: [&str; 3] = ["Blocking", "Bloqueante", "Bloqueio"];
const SEPARATORS: [char; 4] = [':', '-', '—', '–'];

/// A candidate heading (`##`-`####` and spaces, or `**`, a rest with no `*`
/// and `**`): whether it is named, and the text its title is read from.
fn heading(line: &str) -> Option<(bool, &str)> {
    let hashes = line.bytes().take_while(|&b| b == b'#').count();
    if (2..=4).contains(&hashes) {
        return form(line[hashes..].strip_prefix(' ')?.trim_start_matches(' '));
    }
    form(line.strip_prefix("**")?.strip_suffix("**")?).filter(|(_, rest)| !rest.contains('*'))
}

/// `<word> <n><rest>`, `<word><sep><rest>` with a title, or `<n>. <rest>`.
fn form(text: &str) -> Option<(bool, &str)> {
    let Some(after) = WORDS.iter().find_map(|w| text.strip_prefix(w)) else {
        let rest = text.trim_start_matches(|c: char| c.is_ascii_digit());
        return Some((false, rest.strip_prefix(". ").filter(|_| rest.len() < text.len())?));
    };
    let sep = Some(after.trim_start_matches(' ')).filter(|r| r.starts_with(SEPARATORS) && !stripped(r).is_empty());
    Some((true, number(after).or(sep)?))
}

/// One or more spaces, then one or more digits: what follows them.
fn number(text: &str) -> Option<&str> {
    let text = text.strip_prefix(' ')?.trim_start_matches(' ');
    let rest = text.trim_start_matches(|c: char| c.is_ascii_digit());
    (rest.len() < text.len()).then_some(rest)
}

fn stripped(rest: &str) -> &str {
    rest.trim_start_matches([' ', '\t', ':', '.', '-', '—', '–']).trim_end_matches([' ', '\t'])
}

fn title(rest: &str) -> String {
    Some(stripped(rest)).filter(|t| !t.is_empty()).unwrap_or("(no title)").to_string()
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
        // `<line>|<kind><rest>`: N named, D numbered.
        let yes = "## Blocking 1 — Title|N — Title\n### Blocking 2: Title|N: Title\n#### Blocking 3|N\n\
                   ##   Blocking   12x|Nx\n**Blocking 1 — Title**|N — Title\n**Blocking 4**|N\n\
                   ### Bloqueio 1 — Prévia|N — Prévia\n## Bloqueante 2: Título|N: Título\n**Bloqueio 3**|N\n\
                   ## Blocking: concurrent discard|N: concurrent discard\n**Bloqueante– x**|N– x\n\
                   ### Blocking — Guest can pin|N— Guest can pin\n## Bloqueio-x|N-x\n## 1. Live demotion|DLive demotion\n\
                   ####  12.  x|D x\n**1. Search results**|DSearch results\n**1. **|D";
        for case in yes.split('\n') {
            let (line, want) = case.split_once('|').unwrap();
            let got = heading(line).map(|(k, r)| format!("{}{r}", if k { 'N' } else { 'D' }));
            assert_eq!(got.as_deref(), Some(want), "{line}");
        }
        let no = "## Blocking findings\n**Blocking:**\n ## Blocking 1 — x\n- **Blocking 1** — x\nBlocking: 4\n\
                  # Blocking 1\n##### Blocking 1\n##Blocking 1\n## blocking 1\n##\tBlocking 1\n## Blocking\t1\n\
                  **Blocking 1 *bold* x**\n**Blocking 1**x\n**Blocking**\n## Blocking :\n**Blocking: - **\n\
                  ## Bloqueios 1\n## bloqueio 1\n**Blocking: a *b***\n## 1.Title\n**1)** x\n1. Title\n# 1. x\n\
                  ##1. x\n## 1 . x\n**1. *x***";
        for line in no.split('\n') {
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
        assert_eq!(location(&["Local: d.rs", "Location: later"]), Some("d.rs".to_string()));
        assert_eq!(location(&["x", "**Local:** `e.ts`"]), Some("`e.ts`".to_string()));
        assert_eq!(location(&["**Localização:** f", "local: g"]), None);
        assert_eq!(location(&["Location:", "Location: later"]), None);
        assert_eq!(location(&[" Location: x", "location: y", "**Location**: z"]), None);
    }

    #[test]
    fn comment_reads_findings_and_checks_the_count() {
        let body = "**shipcraft: review executed by x**\r\nBlocking: 3\n## Blocking 1 — A \r\nLocation: one\n\
                    **Blocking 2 — B**\ntext\n### Blocking 3: C\n**Locations:** three\nBlocking: 9\n";
        let (found, mismatch) = comment(body);
        let want = [("A", Some("one")), ("B", None), ("C", Some("three"))];
        let want: Vec<_> = want.iter().map(|(t, l)| (t.to_string(), l.map(str::to_string))).collect();
        assert_eq!(found, want);
        assert_eq!(mismatch, None);
        let (found, mismatch) = comment("Blocking: 02\n## Blocking 1 — A\nBlocking: 1");
        assert_eq!(found.len(), 1);
        assert_eq!(mismatch, Some(("02".to_string(), 1)));
        assert_eq!(comment("Blocking: 1x\nBlocking:  1\n").1, None);
    }

    fn titles(body: &str) -> (Vec<String>, Option<Mismatch>) {
        let (found, mismatch) = comment(body);
        (found.into_iter().map(|(t, l)| format!("{t}@{}", l.unwrap_or_default())).collect(), mismatch)
    }

    #[test]
    fn end_line_and_cap() {
        let ends = "## Notes — non-blocking\n### Notas não bloqueantes\n**Own checks**\n#### NON-BLOCKING\n\
                    **Notes:** No additional non-blocking findings.\n### Notes — não bloqueantes\n\
                    ## NÃO BLOQUEANTE x\n**Notes** x **y**";
        for end in ends.split('\n') {
            let body = format!("## Blocking 1 — A\nLocal: a\n{end}\nLocal: late\n## Blocking 2 — B\nBlocking: 2");
            assert_eq!(titles(&body), (vec!["A@a".into()], Some(("2".into(), 1))), "{end}");
        }
        for not_end in ["**Notes service down", "## Notesy", "# Notes", " ## Notes", "**Notes *x* y**"] {
            let body = format!("## Blocking 1 — A\n{not_end}\n## Blocking 2 — B\n");
            assert_eq!(titles(&body).0.len(), 2, "{not_end}");
        }
        let numbered = "## 1. A\nLocal: a\n**2. B**\n**Location:** b\n";
        assert_eq!(titles(&format!("Blocking: 2\n{numbered}")), (vec!["A@a".into(), "B@b".into()], None));
        assert_eq!(titles(&format!("{numbered}## Notes\nBlocking: 02")).0, ["A@a", "B@b"]);
        assert_eq!(titles(numbered), (vec![], None));
        assert_eq!(titles(&format!("Blocking: 3\n{numbered}")), (vec![], Some(("3".into(), 0))));
        assert_eq!(titles(&format!("Blocking: 1\n{numbered}")), (vec![], Some(("1".into(), 0))));
        let mixed = format!("Blocking: 3\n### Bloqueante 1 — N\n{numbered}Local: n\n");
        assert_eq!(titles(&mixed), (vec!["N@".into()], Some(("3".into(), 1))));
        let named = "Blocking: 1\n## Blocking: x\n**Bloqueio 4**\n**Local:** l\n";
        assert_eq!(titles(named), (vec!["x@".into(), "(no title)@l".into()], Some(("1".into(), 2))));
    }

    fn table(text: &str) -> std::result::Result<Vec<Class>, String> {
        classes(&text.parse::<toml::Table>().unwrap())
    }

    fn class(table: &[Class], title: &str) -> (String, Option<&'static str>) {
        let i = class_of(table, title);
        table.get(i).map_or((OTHER.to_string(), None), |c| (c.name.clone(), Some(c.source)))
    }

    #[test]
    fn class_table_order() {
        let classes = table("").unwrap();
        let class = |t: &str| class(&classes, t).0;
        assert_eq!(class("Secrets cross workspace boundaries when project slugs match"), CLASSES[1].0);
        assert_eq!(class("Delayed approval overwrites a newer, confirmed answer"), CLASSES[2].0);
        assert_eq!(class("Numeric deadlines escape citation checks"), CLASSES[8].0);
        assert_eq!(class("Bold formatting bypasses monetary-value verification"), CLASSES[6].0);
        assert_eq!(class("TYPED text vanishes"), CLASSES[0].0);
        assert_eq!(class("Âncora quebrada"), CLASSES[6].0);
        assert_eq!(class("Nothing here"), OTHER);
    }

    #[test]
    fn table_in_effect_and_class_source() {
        let text = "[[findings.class]]\nname = \"Money\"\nkeywords = ['round', '\\bBRL\\b']\n\
                    [[findings.class]]\nname = \"Ações\"\nkeywords = ['ÇÃO', 'round']\n";
        let t = table(text).unwrap();
        let names: Vec<&str> = t.iter().map(|c| c.name.as_str()).collect();
        assert_eq!(names[..2], ["Money", "Ações"]);
        assert_eq!(names[2..], CLASSES.map(|c| c.0));
        assert_eq!(class(&t, "Rounding of typed input"), ("Money".to_string(), Some("project")));
        assert_eq!(class(&t, "Totals in brl drift"), ("Money".to_string(), Some("project")));
        assert_eq!(class(&t, "Validação quebra"), ("Ações".to_string(), Some("project")));
        assert_eq!(class(&t, "Typed text lost"), (CLASSES[0].0.to_string(), Some("builtin")));
        assert_eq!(class(&t, "Nothing here"), (OTHER.to_string(), None));
        let t = table(&format!("[findings]\nbuiltin_classes = false\n{text}")).unwrap();
        assert_eq!(t.len(), 2);
        assert_eq!(class(&t, "Typed text lost").1, None);
        assert!(table("[findings]\nbuiltin_classes = false\n").unwrap().is_empty());
        assert_eq!(table("[findings]\nclass = []\n").unwrap().len(), CLASSES.len());
        assert_eq!(table("[findings]\nbuiltin_classes = true\n").unwrap().len(), CLASSES.len());
        // A built-in name is free once the built-in table is left out.
        let own = format!(
            "[findings]\nbuiltin_classes = false\n[[findings.class]]\nname = \"{}\"\nkeywords = ['x']\n",
            CLASSES[0].0
        );
        assert_eq!(table(&own).unwrap()[0].name, CLASSES[0].0);
    }

    #[test]
    fn problems_in_order() {
        let c = |body: &str| format!("[[findings.class]]\n{body}\n");
        let ok = "name = \"A\"\nkeywords = ['a']";
        let cases = [
            ("findings = 1".to_string(), "[findings] is not a table"),
            ("[[findings]]\nx = 1".to_string(), "[findings] is not a table"),
            ("[findings]\nzz = 1\nbuiltin_classes = 3\nb = 2".to_string(), "unknown key b"),
            ("[findings]\nbuiltin_classes = \"no\"\nclass = 1".to_string(), "builtin_classes is not a boolean"),
            ("[findings]\nclass = 1".to_string(), "class is not an array of tables"),
            ("[findings]\nclass = [{name = \"A\", keywords = ['a']}, 2]".to_string(), "class is not an array of tables"),
            (c("x = 1\nkeywords = 2"), "class 1: unknown key x"),
            (c("keywords = ['a']"), "class 1: name is missing"),
            (c("name = 1"), "class 1: name is not a string"),
            (c("name = \" \\t \""), "class 1: name is empty"),
            (c("name = \"\""), "class 1: name is empty"),
            (c("name = \"a\\u007fb\""), "class 1: name has a control character"),
            (c("name = \"Other\""), "class 1: name Other is already a class"),
            (format!("{}{}", c(ok), c(ok)), "class 2: name A is already a class"),
            (c(&format!("name = \"{}\"", CLASSES[6].0)), "class 1: name Markdown, MDX and link handling (a syntax form that slips past a check) is already a class"),
            (c("name = \"A\""), "class 1: keywords is missing"),
            (c("name = \"A\"\nkeywords = 'a'"), "class 1: keywords is not an array"),
            (c("name = \"A\"\nkeywords = []"), "class 1: keywords is empty"),
            (c("name = \"A\"\nkeywords = ['a', 1, '']"), "class 1: keyword 2 is not a string"),
            (c("name = \"A\"\nkeywords = ['a', '', 1]"), "class 1: keyword 2 is empty"),
            (c("name = \"A\"\nkeywords = ['a', '(', 1]"), "class 1: keyword 2 is not a valid pattern"),
            (c("name = \"A\"\nkeywords = ['a{100000}{100000}']"), "class 1: keyword 1 is not a valid pattern"),
            (format!("{}{}", c("name = \"A\"\nkeywords = ['(']"), c("name = 1")), "class 1: keyword 1 is not a valid pattern"),
            (format!("{}{}", c(ok), c("name = \"B\"\nkeywords = ['[']")), "class 2: keyword 1 is not a valid pattern"),
        ];
        for (text, want) in cases {
            assert_eq!(table(&text).err().as_deref(), Some(want), "{text}");
        }
        assert_eq!(invalid("x"), "[findings] in .shipcraft.toml is invalid: x");
    }

    #[test]
    fn key_escaping() {
        assert_eq!(key_name("a-B_9"), "a-B_9");
        assert_eq!(key_name("a b"), "\"a b\"");
        assert_eq!(key_name("a\nb\u{1b}"), "\"a\\nb\\u001b\"");
        assert_eq!(key_name("ção"), "\"ção\"");
        assert_eq!(key_name(""), "\"\"");
        let t = "[findings]\n\"z\\n\" = 1\n\"a.b\" = 2\n";
        assert_eq!(table(t).err().as_deref(), Some("unknown key \"a.b\""));
        let t = "[[findings.class]]\n\"\\u001b\" = 1\n";
        assert_eq!(table(t).err().as_deref(), Some("class 1: unknown key \"\\u001b\""));
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
