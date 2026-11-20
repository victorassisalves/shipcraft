//! Item 143: `shipcraft uninstall [--dry-run]` removes what `init` wrote, read through the functions that write it.

use crate::config::CONFIG_FILE;
use crate::export::{closed, open_lock, Git};
use crate::git::Repo;
use crate::init::{install_at, marker_lines, rewrite, written_blocks, written_hook, Install, HOOK_MARK};
use crate::init::{LEFTHOOK_FILES, LOCAL};
use crate::init_husky::{shipcraft_words, words, HELPERS};
use crate::init_tool::{append, item, HUSKY, LEGACY, PRE_COMMIT_CONFIG};
use crate::refusal::{failed, refuse, Result};
use std::collections::BTreeSet;
use std::ffi::OsStr;
use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};

const NOT_FILE: &str = "not a regular file";
const LOCKS: &str = ".shipcraft/locks";

/// None: not Shipcraft's; `Some(None)`: left; else the new bytes (none: the file is removed).
type Cut = Option<Option<Vec<u8>>>;

/// A planned line: a file copied, then removed (`new` None) or rewritten, or a line printed as is.
enum Step {
    Change { path: PathBuf, shown: String, old: (Vec<u8>, u32), new: Option<Vec<u8>>, what: String },
    Line(String),
}

#[derive(Default)]
struct Plan {
    steps: Vec<Step>,
    /// The first hook left that calls shipcraft, which keeps `.shipcraft.toml`.
    hook_left: Option<String>,
    lock_removed: bool,
}

impl Plan {
    fn left(&mut self, shown: &str, reason: &str, hook: bool) {
        self.steps.push(Step::Line(format!("shipcraft: left {shown}: {reason}; remove it by hand")));
        if hook {
            self.hook_left.get_or_insert_with(|| shown.to_string());
        }
    }

    /// `path` rewritten to `new` (its line `removed <what>`), or removed when `new` is None or empty.
    fn change(&mut self, path: PathBuf, shown: &str, old: (Vec<u8>, u32), new: Option<Vec<u8>>, what: String) {
        let (new, what) = match new {
            Some(new) if !new.is_empty() => (Some(new), what),
            _ => (None, shown.to_string()),
        };
        self.steps.push(Step::Change { path, shown: shown.to_string(), old, new, what });
    }

    /// Shipcraft's own file, removed whatever its content; whether it was.
    fn own(&mut self, repo: &Repo, shown: &str) -> Result<bool> {
        match kind(&repo.path(shown), shown)? {
            Kind::File(bytes, mode) => self.change(repo.path(shown), shown, (bytes, mode), None, String::new()),
            Kind::Missing => return Ok(false),
            _ => self.left(shown, NOT_FILE, false),
        }
        Ok(self.steps.last().is_some_and(|s| matches!(s, Step::Change { .. })))
    }

    /// Whether `dir` is a folder, read without following a link; any other entry is left.
    fn folder(&mut self, repo: &Repo, dir: &str) -> Result<bool> {
        let found = kind(&repo.path(dir), dir)?;
        if !matches!(found, Kind::Folder | Kind::Missing) {
            self.left(dir, "not a regular folder", false);
        }
        Ok(matches!(found, Kind::Folder))
    }

    /// A file shared with the project, read by `cut`; every one but `AGENTS.md` and `CLAUDE.md` is a hook.
    fn shared(&mut self, repo: &Repo, file: &str, reason: &str, what: &str, cut: impl Fn(&[u8]) -> Cut) -> Result<()> {
        let hook = !file.ends_with(".md");
        match kind(&repo.path(file), file)? {
            Kind::File(bytes, mode) => match cut(&bytes) {
                Some(Some(new)) => self.change(repo.path(file), file, (bytes, mode), Some(new), what.to_string()),
                Some(None) => self.left(file, reason, hook),
                None => {}
            },
            Kind::Missing => {}
            _ => self.left(file, NOT_FILE, hook),
        }
        Ok(())
    }
}

pub fn run(dry: bool) -> Result<()> {
    let repo = Repo::open()?;
    if let Some(path) = open_lock_anywhere(&repo)? {
        return refuse(
            "uninstall-lock-open",
            format!("{path} is an open lock, so a RED commit is still waiting for its GREEN"),
            "removing the hooks and the config now would leave that change unjudged, and the lock would leave the tree before the commit that closes it; nothing was changed",
            "finish the GREEN (the hook closes the lock when its cases pass), or drop the RED commit that opened the lock, then run shipcraft uninstall again",
        );
    }
    let plan = plan(&repo)?;
    let tracked = repo.run(&["ls-files", "-z", "--cached", "--full-name"])?;
    let Some(records) = tracked.strip_suffix(b"\0").or(tracked.is_empty().then_some(&[][..])) else {
        return Err(failed("`git ls-files -z --cached --full-name` printed a record with no NUL at its end"));
    };
    let tracked: BTreeSet<&[u8]> = records.split(|b| *b == 0).collect();
    let common = repo.run(&["rev-parse", "--git-common-dir"])?;
    let common = repo.root().join(OsStr::from_bytes(common.strip_suffix(b"\n").unwrap_or(&common)));
    let changed: Vec<&String> =
        plan.steps.iter().filter_map(|s| if let Step::Change { shown, .. } = s { Some(shown) } else { None }).collect();
    let folder = if changed.is_empty() || dry { None } else { Some(copy_folder(repo.root(), &common)?) };
    for step in &plan.steps {
        match (step, &folder) {
            (Step::Line(line), _) => println!("{line}"),
            (Step::Change { what, .. }, None) => println!("shipcraft: would remove {what}"),
            (Step::Change { path, shown, old, new, what }, Some(folder)) => {
                let hook = shown.starts_with(".git/")
                    || Path::new(shown).components().any(|c| !matches!(c, std::path::Component::Normal(_)));
                let name = path.file_name().unwrap_or_default().to_string_lossy();
                keep_copy(&folder.join(if hook { format!("hooks/{name}") } else { shown.clone() }), old)?;
                match new {
                    None => fs::remove_file(path).map_err(|e| failed(format!("remove {shown}: {e}")))?,
                    Some(new) => rewrite(path, new).map_err(|e| failed(format!("rewrite {shown}: {e}")))?,
                }
                println!("shipcraft: removed {what}");
            }
        }
    }
    if changed.is_empty() || dry {
        let end = if changed.is_empty() { "nothing to remove" } else { "dry run: nothing was changed" };
        println!("shipcraft: {end}");
        return Ok(());
    }
    // Each only when empty, and never through a `.shipcraft` link.
    if repo.path(".shipcraft").symlink_metadata().is_ok_and(|m| m.is_dir()) {
        [LOCKS, ".shipcraft/briefs", ".shipcraft"].iter().for_each(|dir| drop(fs::remove_dir(repo.path(dir))));
    }
    if plan.lock_removed {
        println!("shipcraft: the locks stay in git history: git log -- .shipcraft/locks");
    }
    let paths: Vec<String> = changed.iter().filter(|p| tracked.contains(p.as_bytes())).map(|p| quote(p)).collect();
    let (root, paths) = (quote(&repo.root().to_string_lossy()), paths.join(" "));
    if !paths.is_empty() {
        println!("shipcraft: commit the removal: git -C {root} commit -m \"chore: remove shipcraft\" -- {paths}");
    }
    println!("shipcraft: if init --github made shipcraft/ci and shipcraft/review required checks, remove them from the default branch's protection on GitHub");
    match install_at(repo.root()) {
        Install::Project => println!("shipcraft: the binary stays: remove the package with pnpm remove shipcraft (or npm rm shipcraft) and commit package.json with the lockfile"),
        Install::Nested(dir) => println!("shipcraft: the binary stays (installed under {}): remove the package with the package manager of the project that installed it there", dir.display()),
        Install::Machine => {
            let exe = std::env::current_exe().map(|p| p.display().to_string()).unwrap_or_else(|_| "shipcraft".into());
            println!("shipcraft: the binary stays ({exe}): remove it with install.sh --uninstall, or cargo uninstall shipcraft if you built it from source")
        }
    }
    Ok(())
}

/// Point 5: `<common>/shipcraft/uninstalled/<stamp>[-n]`, created exclusively, and its line.
fn copy_folder(root: &Path, common: &Path) -> Result<PathBuf> {
    let base = common.join("shipcraft/uninstalled");
    fs::create_dir_all(&base).map_err(|e| failed(format!("create {}: {e}", base.display())))?;
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0.0, |d| d.as_secs_f64());
    let stamp = crate::relatorio::utc(now).replace(['-', ':'], "");
    let mut n = 1;
    let folder = loop {
        let folder = base.join(if n == 1 { stamp.clone() } else { format!("{stamp}-{n}") });
        match fs::create_dir(&folder) {
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => n += 1,
            done => break done.map(|()| folder).map_err(|e| failed(format!("create the copy folder: {e}")))?,
        }
    };
    let canonical = |p: &Path| fs::canonicalize(p).unwrap_or_else(|_| p.to_path_buf());
    let shown = canonical(&folder);
    let shown = shown.strip_prefix(canonical(root)).unwrap_or(&shown).display().to_string();
    println!("shipcraft: copying everything it removes or changes to {shown}");
    Ok(folder)
}

/// One copy, created exclusively with the file's mode; a copy that fails part way is removed.
fn keep_copy(dest: &Path, (bytes, mode): &(Vec<u8>, u32)) -> Result<()> {
    use std::io::Write;
    let fail = |e: std::io::Error| failed(format!("copy to {}: {e}", dest.display()));
    fs::create_dir_all(dest.parent().unwrap_or(dest)).map_err(fail)?;
    let mut file = fs::OpenOptions::new().write(true).create_new(true).mode(0o600).open(dest).map_err(fail)?;
    file.write_all(bytes).and_then(|()| fs::set_permissions(dest, fs::Permissions::from_mode(*mode))).map_err(|e| {
        let _ = fs::remove_file(dest);
        fail(e)
    })
}

/// `shell_quote`d when it holds anything but letters, digits, `.`, `_`, `-` and `/`.
fn quote(word: &str) -> String {
    match !word.is_empty() && word.chars().all(|c| c.is_ascii_alphanumeric() || "._-/".contains(c)) {
        true => word.to_string(),
        false => crate::suite::shell_quote(word),
    }
}

/// Point 2: the first open lock in this tree, HEAD, then every other worktree's tree and HEAD.
fn open_lock_anywhere(repo: &Repo) -> Result<Option<String>> {
    let git = Git::open()?;
    let text = |b: &[u8]| String::from_utf8_lossy(b).into_owned();
    if let Some(path) = in_tree(repo.root()) {
        return Ok(Some(text(&path)));
    }
    if let Some(head) = git.verify("HEAD^{commit}")? {
        if let Some(path) = open_lock(&git, &head)? {
            return Ok(Some(text(&path)));
        }
    }
    let out = repo.run(&["worktree", "list", "--porcelain", "-z"])?;
    let here = fs::canonicalize(repo.root()).unwrap_or_else(|_| repo.root().to_path_buf());
    // NUL-ended lines, an empty one after each record: `worktree <path>`, then `HEAD <oid>`, `bare`, ...
    for record in out.split(|b| *b == 0).collect::<Vec<_>>().split(|line| line.is_empty()).filter(|r| !r.is_empty()) {
        let raw =
            record[0].strip_prefix(b"worktree ").ok_or_else(|| failed("unreadable `git worktree list` output"))?;
        let (head, bare) = (record.iter().find_map(|l| l.strip_prefix(b"HEAD ")), record.contains(&b"bare".as_slice()));
        let path = PathBuf::from(OsStr::from_bytes(raw));
        if path == repo.root() || fs::canonicalize(&path).is_ok_and(|p| p == here) {
            continue;
        }
        if let Some(lock) = in_tree(&path).filter(|_| !bare) {
            return Ok(Some(path.join(OsStr::from_bytes(&lock)).display().to_string()));
        }
        if let Some(head) = head.filter(|h| h.iter().any(|b| *b != b'0')) {
            if let Some(lock) = open_lock(&git, &text(head))? {
                return Ok(Some(format!("{}:{}", text(raw), text(&lock))));
            }
        }
    }
    Ok(None)
}

/// The first `.json` lock of `root`, in byte order, not a regular file read closed; a locks path not a listable folder is open.
fn in_tree(root: &Path) -> Option<Vec<u8>> {
    let dir = root.join(LOCKS);
    let whole = Some(LOCKS.as_bytes().to_vec());
    match dir.symlink_metadata() {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return None,
        Ok(meta) if meta.is_dir() => {}
        _ => return whole,
    }
    let listed =
        fs::read_dir(&dir).and_then(|l| l.map(|e| e.map(|e| e.file_name())).collect::<std::io::Result<Vec<_>>>());
    let Ok(names) = listed else { return whole };
    let mut names: Vec<&[u8]> = names.iter().map(|n| n.as_bytes()).filter(|n| n.ends_with(b".json")).collect();
    names.sort();
    names.into_iter().find_map(|name| {
        let path = dir.join(OsStr::from_bytes(name));
        let shut = path.symlink_metadata().is_ok_and(|m| m.file_type().is_file())
            && fs::read(&path).is_ok_and(|bytes| closed(&bytes));
        (!shut).then(|| [LOCKS.as_bytes(), b"/", name].concat())
    })
}

/// What an entry is, read without following a link; a regular file with its bytes and mode.
enum Kind {
    Missing,
    File(Vec<u8>, u32),
    Folder,
    Other,
}

fn kind(path: &Path, shown: &str) -> Result<Kind> {
    let meta = match path.symlink_metadata() {
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Kind::Missing),
        Err(e) => return Err(failed(format!("read {shown}: {e}"))),
        Ok(meta) => meta,
    };
    let read = || fs::read(path).map_err(|e| failed(format!("read {shown}: {e}")));
    Ok(match meta.file_type() {
        t if t.is_dir() => Kind::Folder,
        t if t.is_file() => Kind::File(read()?, meta.permissions().mode() & 0o7777),
        _ => Kind::Other,
    })
}

/// Points 3 and 4, in their order; every read before any write.
fn plan(repo: &Repo) -> Result<Plan> {
    let mut plan = Plan::default();
    let block = "its shipcraft markers do not hold a block Shipcraft writes (edited by hand, or from another version)";
    for name in ["AGENTS.md", "CLAUDE.md"] {
        plan.shared(repo, name, block, &format!("the shipcraft block from {name}"), |b| cut_block(name, b))?;
    }
    for (name, msg) in [("commit-msg", true), ("post-commit", false)] {
        let path = repo.hook_path(name)?;
        // husky 7 and 8: the hooks folder is `.husky`, whose files the husky step reads.
        if HUSKY.iter().any(|(file, _)| repo.path(file) == path) {
            continue;
        }
        // Resolved through its folder, so a `core.hooksPath` with `..` is shown absolute outside the root.
        let dir = path.parent().and_then(|d| fs::canonicalize(d).ok());
        let real = dir.map_or(path.clone(), |d| d.join(name));
        let root = fs::canonicalize(repo.root()).unwrap_or_else(|_| repo.root().to_path_buf());
        let shown = real.strip_prefix(&root).unwrap_or(&real).display().to_string();
        let reason = match kind(&path, &shown)? {
            Kind::File(bytes, mode) if written_hook(msg, &bytes) => {
                plan.change(path, &shown, (bytes, mode), None, String::new());
                continue;
            }
            Kind::File(bytes, _) if contains(&bytes, HOOK_MARK.as_bytes()) => "a shipcraft hook edited by hand",
            Kind::File(bytes, _) if crate::init_hooks::calls_shipcraft(&bytes) => {
                "it calls shipcraft and is not a hook init writes"
            }
            Kind::File(..) | Kind::Missing => continue,
            _ => NOT_FILE,
        };
        plan.left(&shown, reason, true);
    }
    if plan.folder(repo, ".husky")? {
        for (file, line) in HUSKY {
            let (reason, what) =
                ("it calls shipcraft in a line init does not write", format!("the shipcraft line from {file}"));
            plan.shared(repo, file, reason, &what, |b| cut_husky_line(b, line))?;
        }
    }
    let before = plan.steps.len();
    let what = format!("the shipcraft hooks from {PRE_COMMIT_CONFIG}");
    plan.shared(repo, PRE_COMMIT_CONFIG, "it mentions shipcraft outside the item init appends", &what, |bytes| {
        let cut = std::str::from_utf8(bytes).ok().and_then(cut_items);
        let rest = cut.as_ref().map_or(bytes, |t| t.as_bytes());
        if contains(rest, b"shipcraft") {
            Some(None)
        } else {
            cut.map(|t| Some(t.into_bytes()))
        }
    })?;
    if plan.steps.len() > before && matches!(plan.steps.last(), Some(Step::Change { .. })) {
        plan.steps.push(Step::Line("shipcraft: pre-commit's commit-msg and post-commit launchers stay in the hooks folder, and run any of the project's hooks with no stages at those stages: if nothing else needs them, pre-commit uninstall -t commit-msg -t post-commit (or prek uninstall ...)".into()));
    }
    for file in LEFTHOOK_FILES {
        let reason = match kind(&repo.path(file), file)? {
            Kind::File(bytes, _) if contains(&bytes, b"shipcraft") => {
                "uninstall does not edit lefthook files yet: remove the shipcraft commands under commit-msg and post-commit"
            }
            Kind::File(..) | Kind::Missing => continue,
            _ => NOT_FILE,
        };
        plan.left(file, reason, true);
    }
    if plan.folder(repo, ".shipcraft")? {
        let mut known = Vec::new();
        for dir in [".shipcraft/briefs", LOCKS] {
            known.push(dir.to_string());
            let names = match plan.folder(repo, dir)? {
                false => Vec::new(),
                true if dir == LOCKS => listing(repo, dir)?,
                true => vec!["red.md".into(), "green.md".into()],
            };
            for name in names.into_iter().filter(|n| dir != LOCKS || n == ".gitkeep" || n.ends_with(".json")) {
                let shown = format!("{dir}/{name}");
                plan.lock_removed |= plan.own(repo, &shown)? && name.ends_with(".json");
                known.push(shown);
            }
        }
        let mut foreign = Vec::new();
        walk(repo, ".shipcraft", &known, &mut foreign)?;
        foreign.sort_by(|a, b| a.as_bytes().cmp(b.as_bytes()));
        foreign.iter().for_each(|shown| plan.left(shown, "not a file init or red writes", false));
    }
    match (plan.hook_left.clone(), kind(&repo.path(CONFIG_FILE), CONFIG_FILE)?) {
        (_, Kind::Missing) => {}
        (Some(hook), _) => {
            let reason = format!("a hook that calls shipcraft is left ({hook}): remove that call first, then run shipcraft uninstall again");
            plan.left(CONFIG_FILE, &reason, false);
        }
        _ => {
            plan.own(repo, CONFIG_FILE)?;
        }
    }
    if !matches!(kind(&repo.path(".sc2.toml"), ".sc2.toml")?, Kind::Missing) {
        plan.left(".sc2.toml", "the config of an older Shipcraft", false);
    }
    Ok(plan)
}

fn contains(bytes: &[u8], needle: &[u8]) -> bool {
    bytes.windows(needle.len()).any(|w| w == needle)
}

/// One start and one end marker around a block Shipcraft writes: cut, with the separator `init` added.
fn cut_block(name: &str, bytes: &[u8]) -> Cut {
    let markers = marker_lines(bytes);
    let [(true, from, _), (false, _, to)] = markers.as_slice() else { return (!markers.is_empty()).then_some(None) };
    if !written_blocks(name).iter().any(|b| b.as_bytes() == &bytes[*from..*to]) {
        return Some(None);
    }
    let (mut before, after) = (&bytes[..*from], &bytes[*to..]);
    if after.is_empty() && !before.ends_with(b"\n\n\n") {
        while before.ends_with(b"\n") && (before.ends_with(b"\n\n") || before.len() == 1) {
            before = &before[..before.len() - 1];
        }
    }
    Some(Some([before, after].concat()))
}

/// One line calls shipcraft, exactly `line` or its local form: cut with its `\n` (and husky 7's head `init` wrote).
fn cut_husky_line(bytes: &[u8], line: &str) -> Cut {
    let local = line.replacen("shipcraft", LOCAL, 1);
    let (mut at, mut calls) = (0, Vec::new());
    for piece in bytes.split_inclusive(|b| *b == b'\n') {
        let bare = piece.strip_suffix(b"\n").unwrap_or(piece);
        if shipcraft_words(&words(&String::from_utf8_lossy(bare))).is_some() {
            calls.push((at, at + piece.len(), bare == line.as_bytes() || bare == local.as_bytes()));
        }
        at += piece.len();
    }
    let [(from, to, true)] = calls.as_slice() else { return (!calls.is_empty()).then_some(None) };
    let new = [&bytes[..*from], &bytes[*to..]].concat();
    Some(Some(if new == format!("#!/bin/sh\n{}\n\n", HELPERS[0]).as_bytes() { Vec::new() } else { new }))
}

/// The inverse of `append`: cut each `item` text (or legacy id) that `append` puts back exactly, in source order.
fn cut_items(text: &str) -> Option<String> {
    let (mut text, mut cut) = (text.to_string(), false);
    'again: loop {
        let mut found = Vec::new();
        // Every eol `append` may read: only the one it reads proves.
        for eol in ["\n", "\r\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"] {
            for (wanted, local) in [&[0, 1][..], &[0], &[1]].into_iter().flat_map(|w| [(w, false), (w, true)]) {
                for (d, s) in (0..=16).flat_map(|d| (1..=8).map(move |s| (d, s))) {
                    let canonical = item(wanted, d, s, eol, local);
                    let legacy = canonical.replace("id: shipcraft-close", &format!("id: {LEGACY}"));
                    for occurrence in [&canonical, &legacy] {
                        let at = text.match_indices(occurrence.as_str()).map(|(at, _)| at);
                        found.extend(at.map(|at| (at, occurrence.len(), canonical.clone(), wanted, local)));
                    }
                }
            }
        }
        found.sort_by_key(|f| f.0);
        for (at, len, canonical, wanted, local) in found {
            let without = format!("{}{}", &text[..at], &text[at + len..]);
            if append(&without, wanted, local) == Some(format!("{}{canonical}{}", &without[..at], &without[at..])) {
                (text, cut) = (without, true);
                continue 'again;
            }
        }
        return cut.then_some(text);
    }
}

/// A folder's entry names in byte order; a name that is not UTF-8 is read lossily.
fn listing(repo: &Repo, dir: &str) -> Result<Vec<String>> {
    let fail = |e: std::io::Error| failed(format!("list {dir}: {e}"));
    let mut names = Vec::new();
    for entry in fs::read_dir(repo.path(dir)).map_err(fail)? {
        names.push(entry.map_err(fail)?.file_name().to_string_lossy().into_owned());
    }
    names.sort_by(|a, b| a.as_bytes().cmp(b.as_bytes()));
    Ok(names)
}

/// Every entry under `dir` not in `known`, never through a link; an empty foreign folder is named.
fn walk(repo: &Repo, dir: &str, known: &[String], out: &mut Vec<String>) -> Result<()> {
    for name in listing(repo, dir)? {
        let shown = format!("{dir}/{name}");
        let folder = repo.path(&shown).symlink_metadata().is_ok_and(|m| m.is_dir());
        if folder && (known.contains(&shown) || !listing(repo, &shown)?.is_empty()) {
            walk(repo, &shown, known, out)?;
        } else if !known.contains(&shown) {
            out.push(shown);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests;
