//! Item 24: the shape warning in the `shipcraft pr` summary. A product file that
//! had up to N lines at the merge-base and has more at HEAD is named; N is
//! the p90 of the project's product files, or `[pr] forma_linhas`.

use crate::config::Config;
use crate::git::Repo;
use crate::medicao::{numstat, shipcraft_own, LOCKFILES, NOT_OWN};
use std::collections::{HashMap, HashSet};
use std::io::Write;
use std::process::{Command, Stdio};

/// `shipcraft pr` sets the count here (`null` without N), so the `ci` (a child
/// process) and `review` rows it causes carry `shape_warnings` (rule 2).
pub const AVISOS_ENV: &str = "SHIPCRAFT_SHAPE_WARNINGS";
const NOMEADOS: usize = 5;
const MINIMO: usize = 20;

pub struct Forma {
    pub text: String,
    /// The files that crossed N; None when there is no N or no measure.
    pub avisos: Option<usize>,
}

/// A file of the diff that can be warned: its path at HEAD, and the blobs
/// before (None for a new file) and after.
struct Candidate {
    path: Vec<u8>,
    before: Option<String>,
    after: String,
}

pub fn forma(repo: &Repo, config: &Config, base: &str, head: &str) -> Forma {
    let (n, mut crossed) = match measure(repo, config, base, head) {
        Ok(Some(found)) => found,
        Ok(None) => return Forma { text: String::new(), avisos: None },
        Err(why) => return Forma { text: format!("\nShape: unmeasured ({why}).\n"), avisos: None },
    };
    crossed.sort_by(|a, b| (b.2 - b.1.unwrap_or(0)).cmp(&(a.2 - a.1.unwrap_or(0))).then_with(|| a.0.cmp(&b.0)));
    let mut text = String::new();
    for (path, before, after) in crossed.iter().take(NOMEADOS) {
        let before = before.map_or("new".to_string(), |b| b.to_string());
        text += &format!("Shape: `{}` exceeded {n} lines ({before} -> {after}); consider splitting.\n", quoted(path));
    }
    if crossed.len() > NOMEADOS {
        text += &format!("and {} more files\n", crossed.len() - NOMEADOS);
    }
    if !text.is_empty() {
        text.insert(0, '\n');
    }
    Forma { text, avisos: Some(crossed.len()) }
}

/// N and the files that crossed it `(path, before, after)`; None without N;
/// the reason when a tree or blob cannot be read.
#[allow(clippy::type_complexity)]
fn measure(
    repo: &Repo,
    config: &Config,
    base: &str,
    head: &str,
) -> Result<Option<(u64, Vec<(Vec<u8>, Option<u64>, u64)>)>, String> {
    let product = |path: &[u8]| {
        if shipcraft_own(path) {
            return false;
        }
        let path = String::from_utf8_lossy(path);
        let name = path.rsplit('/').next().unwrap_or(&path);
        !LOCKFILES.contains(&name) && !config.is_test_file(&path)
    };
    // Binary is what git's numstat says (`-`), as in item 11: attributes count.
    let binaries = |from: &str, to: &str| -> Result<HashSet<String>, String> {
        // Item 50: Shipcraft's own blobs are never read, not even for this.
        let mut args = vec!["diff", "--numstat", "-z", "-M", from, to, "--"];
        args.extend(NOT_OWN);
        let out = git(repo, &args)?;
        Ok(numstat(&out).into_iter().filter(|(_, counts)| counts.is_none()).map(|(path, _)| path).collect())
    };
    let raw = git(repo, &["diff", "--raw", "-z", "-M", "--no-abbrev", base, head])?;
    let binary = binaries(base, head)?;
    let candidates = changed(&raw)
        .into_iter()
        .filter(|c| product(&c.path) && !binary.contains(String::from_utf8_lossy(&c.path).as_ref()))
        .collect::<Vec<_>>();
    let mut wanted: Vec<(String, Vec<u8>)> = Vec::new();
    for c in &candidates {
        wanted.extend(c.before.iter().map(|sha| (sha.clone(), c.path.clone())));
        wanted.push((c.after.clone(), c.path.clone()));
    }
    let n = match config.pr.forma_linhas {
        Some(n) => n.get(),
        None => {
            let tree = git(repo, &["ls-tree", "-r", "-z", "--full-tree", base])?;
            let empty =
                String::from_utf8_lossy(&git(repo, &["hash-object", "-t", "tree", "/dev/null"])?).trim().to_string();
            let binary = binaries(&empty, base)?;
            let population: Vec<(String, Vec<u8>)> = tree
                .split(|&b| b == 0)
                .filter_map(|entry| {
                    let tab = entry.iter().position(|&b| b == b'\t')?;
                    let meta: Vec<&[u8]> = entry[..tab].split(|&b| b == b' ').collect();
                    let path = entry[tab + 1..].to_vec();
                    (meta.get(1) == Some(&&b"blob"[..])
                        && product(&path)
                        && !binary.contains(String::from_utf8_lossy(&path).as_ref()))
                    .then(|| (String::from_utf8_lossy(meta[2]).into_owned(), path))
                })
                .collect();
            let lines = lines_of(repo, &population)?;
            let mut sizes: Vec<u64> = population.iter().map(|(sha, _)| lines[sha]).collect();
            if sizes.len() < MINIMO {
                return Ok(None);
            }
            sizes.sort_unstable();
            sizes[(9 * sizes.len()).div_ceil(10) - 1]
        }
    };
    let lines = lines_of(repo, &wanted)?;
    let mut crossed = Vec::new();
    for c in candidates {
        let before = c.before.as_ref().map(|sha| lines[sha]);
        let after = lines[&c.after];
        if before.unwrap_or(0) <= n && after > n {
            crossed.push((c.path, before, after));
        }
    }
    Ok(Some((n, crossed)))
}

/// The files of `git diff --raw -z -M` that exist at HEAD as blobs; a file
/// renamed keeps its old blob as "before", a new one has none.
fn changed(raw: &[u8]) -> Vec<Candidate> {
    let mut fields = raw.split(|&b| b == 0);
    let mut out = Vec::new();
    while let Some(meta) = fields.next().filter(|m| m.starts_with(b":")) {
        let meta: Vec<String> = String::from_utf8_lossy(&meta[1..]).split(' ').map(str::to_string).collect();
        let status = meta.get(4).map(String::as_str).unwrap_or("");
        let mut path = fields.next().unwrap_or_default();
        if status.starts_with('R') || status.starts_with('C') {
            path = fields.next().unwrap_or_default();
        }
        if status.starts_with('D') || meta[1] == "160000" {
            continue;
        }
        let before = (!status.starts_with('A') && meta[0] != "160000").then(|| meta[2].clone());
        out.push(Candidate { path: path.to_vec(), before, after: meta[3].clone() });
    }
    out
}

/// Lines (`\n` bytes) of each blob, read with one
/// `git cat-file --batch` and without the network.
fn lines_of(repo: &Repo, blobs: &[(String, Vec<u8>)]) -> Result<HashMap<String, u64>, String> {
    let mut lines = HashMap::new();
    if blobs.is_empty() {
        return Ok(lines);
    }
    let mut child = Command::new("git")
        .arg("-C")
        .arg(repo.root())
        .args(["cat-file", "--batch"])
        .env("GIT_NO_LAZY_FETCH", "1")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|e| format!("run git: {e}"))?;
    let input: String = blobs.iter().map(|(sha, _)| format!("{sha}\n")).collect();
    let mut stdin = child.stdin.take().expect("stdin");
    let writer = std::thread::spawn(move || stdin.write_all(input.as_bytes()));
    let out = child.wait_with_output().map_err(|e| format!("run git: {e}"))?;
    let _ = writer.join();
    let mut rest = &out.stdout[..];
    for (sha, path) in blobs {
        let unread = || format!("could not read the blob for `{}`", quoted(path));
        let end = rest.iter().position(|&b| b == b'\n').ok_or_else(unread)?;
        let header = String::from_utf8_lossy(&rest[..end]).into_owned();
        let size: usize = match header.split(' ').collect::<Vec<_>>()[..] {
            [_, "blob", size] => size.parse().map_err(|_| unread())?,
            _ => return Err(unread()),
        };
        let content = rest.get(end + 1..end + 1 + size).ok_or_else(unread)?;
        lines.insert(sha.clone(), content.iter().filter(|&&b| b == b'\n').count() as u64);
        rest = rest.get(end + 2 + size..).unwrap_or_default();
    }
    Ok(lines)
}

fn git(repo: &Repo, args: &[&str]) -> Result<Vec<u8>, String> {
    let out = Command::new("git")
        .arg("-C")
        .arg(repo.root())
        .args(args)
        .env("GIT_NO_LAZY_FETCH", "1")
        .output()
        .map_err(|e| format!("run git: {e}"))?;
    if !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        return Err(format!("`git {}` failed: {}", args[0], err.lines().next().unwrap_or("").trim()));
    }
    Ok(out.stdout)
}

/// The path as git quotes it with `core.quotePath` on: control bytes, `"`,
/// `\` and bytes outside ASCII force quotes and escapes; the backtick does not.
fn quoted(path: &[u8]) -> String {
    if !path.iter().any(|&b| b < 0x20 || b == b'"' || b == b'\\' || b >= 0x7f) {
        return String::from_utf8_lossy(path).into_owned();
    }
    let mut out = String::from("\"");
    for &b in path {
        match b {
            7 => out += "\\a",
            8 => out += "\\b",
            b'\t' => out += "\\t",
            b'\n' => out += "\\n",
            11 => out += "\\v",
            12 => out += "\\f",
            b'\r' => out += "\\r",
            b'"' => out += "\\\"",
            b'\\' => out += "\\\\",
            b if !(0x20..0x7f).contains(&b) => out += &format!("\\{b:03o}"),
            b => out.push(b as char),
        }
    }
    out + "\""
}

#[cfg(test)]
mod tests {
    use super::{changed, quoted};

    #[test]
    fn paths_are_quoted_as_git_quotes_them() {
        assert_eq!(quoted(b"src/a `b`.rs"), "src/a `b`.rs");
        assert_eq!(quoted(b"a\"b\\c\td"), "\"a\\\"b\\\\c\\td\"");
        assert_eq!(quoted("ção".as_bytes()), "\"\\303\\247\\303\\243o\"");
        assert_eq!(quoted(b"x\x01\x7f"), "\"x\\001\\177\"");
    }

    #[test]
    fn renames_keep_the_old_blob_and_deletions_are_out() {
        let z = "0".repeat(40);
        let (a, b) = ("a".repeat(40), "b".repeat(40));
        let raw = format!(
            ":000000 100644 {z} {a} A\0novo.rs\0:100644 100644 {a} {b} R087\0velho.rs\0nome.rs\0:100644 000000 {a} {z} D\0foi.rs\0"
        );
        let found = changed(raw.as_bytes());
        assert_eq!(found.len(), 2);
        assert_eq!((found[0].path.as_slice(), found[0].before.as_deref()), (&b"novo.rs"[..], None));
        assert_eq!((found[1].path.as_slice(), found[1].before.as_deref()), (&b"nome.rs"[..], Some(a.as_str())));
    }
}
