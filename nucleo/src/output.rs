//! Item 139: in `red` and the hook, each command's output past its first
//! 4,096 bytes goes only to a file `F` (`git rev-parse --git-path
//! shipcraft/output/<red|hook>.log`); the screen gets its last lines and one
//! cut line. `SHIPCRAFT_OUTPUT=full`, `ci`, `init` and a file that cannot be
//! opened keep today's whole forwarding.

use crate::git::Repo;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Instant;

/// How many bytes of a command the screen shows, and the most the tail shows.
const SHOWN: usize = 4096;
/// The most lines the tail shows.
const LINES: usize = 40;

/// The invocation's file: not chosen (forward whole), chosen and not opened
/// yet, or opened (`None` once a write failed).
enum Invocation {
    Whole,
    Pending { path: PathBuf, shown: String },
    Open { file: Option<File>, shown: String },
}

static STATE: Mutex<Invocation> = Mutex::new(Invocation::Whole);

/// Called once by `red` (`name` "red") and the hook ("hook") before any
/// command runs: point 1 unless `SHIPCRAFT_OUTPUT` is exactly `full` (point
/// 2) or git cannot say where `F` is (point 3).
pub fn capture(repo: &Repo, name: &str) {
    if std::env::var_os("SHIPCRAFT_OUTPUT").is_some_and(|v| v == "full") {
        return;
    }
    let Ok(answer) = repo.text(&["rev-parse", "--git-path", &format!("shipcraft/output/{name}.log")]) else { return };
    if answer.is_empty() {
        return;
    }
    let path = repo.path(&answer);
    let shown = path.strip_prefix(repo.root()).unwrap_or(&path).display().to_string();
    *lock(&STATE) = Invocation::Pending { path, shown };
}

/// Creates or truncates `F` as a regular file, never following a link at it
/// nor blocking on it.
fn open(path: &PathBuf) -> io::Result<File> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let not_regular = || io::Error::other("not a regular file");
    match fs::symlink_metadata(path) {
        Ok(meta) if !meta.file_type().is_file() => return Err(not_regular()),
        Err(e) if e.kind() != io::ErrorKind::NotFound => return Err(e),
        _ => {}
    }
    let file = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK)
        .open(path)?;
    if !file.metadata()?.is_file() {
        return Err(not_regular());
    }
    Ok(file)
}

/// One command's output under one lock: what was shown, counted, kept for the
/// tail and written to `F`.
pub struct Cut {
    file: Option<File>,
    failed: bool,
    shown_path: String,
    count: u64,
    shown: usize,
    /// The screen's last byte left a line open.
    open: bool,
    /// The last bytes not shown: one more than the tail's window, so the
    /// byte before the window is known.
    rest: Vec<u8>,
    last: Option<u8>,
    deadline: Option<Instant>,
    closed: bool,
}

/// Right after `command` started: its cut, or None when its output is
/// forwarded whole. The invocation's first command opens `F`.
pub fn begin(command: &str) -> Option<Arc<Mutex<Cut>>> {
    let mut state = lock(&STATE);
    if let Invocation::Pending { path, shown } = &*state {
        let shown = shown.clone();
        *state = match open(path) {
            Ok(file) => Invocation::Open { file: Some(file), shown },
            Err(_) => Invocation::Whole,
        };
    }
    let Invocation::Open { file, shown } = &mut *state else { return None };
    // No file here: a write failed earlier in this invocation.
    let file = file.take();
    let mut cut = Cut {
        failed: file.is_none(),
        file,
        shown_path: shown.clone(),
        count: 0,
        shown: 0,
        open: false,
        rest: Vec::new(),
        last: None,
        deadline: None,
        closed: false,
    };
    let folded = command.split_whitespace().collect::<Vec<_>>().join(" ");
    cut.write(format!("shipcraft: `{folded}`\n").as_bytes());
    Some(Arc::new(Mutex::new(cut)))
}

impl Cut {
    fn write(&mut self, bytes: &[u8]) {
        if let Some(file) = &mut self.file {
            if file.write_all(bytes).is_err() {
                self.file = None;
                self.failed = true;
            }
        }
    }

    /// One chunk read from either stream; after the deadline, dropped.
    pub fn feed(&mut self, bytes: &[u8]) {
        if bytes.is_empty() || self.closed || self.deadline.is_some_and(|d| Instant::now() >= d) {
            return;
        }
        self.count += bytes.len() as u64;
        self.last = bytes.last().copied();
        self.write(bytes);
        let (show, rest) = bytes.split_at(bytes.len().min(SHOWN - self.shown));
        if let Some(&end) = show.last() {
            let _ = io::stderr().write_all(show);
            self.shown += show.len();
            self.open = end != b'\n';
        }
        self.rest.extend_from_slice(rest);
        if self.rest.len() > 4 * (SHOWN + 1) {
            self.rest.drain(..self.rest.len() - (SHOWN + 1));
        }
    }

    /// The command exited: chunks admitted from `deadline` on are dropped.
    pub fn until(&mut self, deadline: Instant) {
        self.deadline = Some(deadline);
    }
}

/// The command's output ends: the open line ends, and past 4,096 bytes the
/// tail and the cut line print; `F` goes back to the invocation.
pub fn finish(cut: &Mutex<Cut>) {
    let mut cut = lock(cut);
    cut.closed = true;
    if cut.last.is_some_and(|b| b != b'\n') {
        cut.write(b"\n");
    }
    let mut err = io::stderr().lock();
    if cut.open {
        let _ = err.write_all(b"\n");
    }
    if cut.count > SHOWN as u64 {
        let lines = tail(&cut.rest);
        for line in &lines {
            let _ = writeln!(err, "{line}");
        }
        let end = if cut.failed {
            format!("; the file {} is incomplete (a write failed)", cut.shown_path)
        } else {
            format!("; all of it: {} (SHIPCRAFT_OUTPUT=full prints everything)", cut.shown_path)
        };
        let _ = writeln!(
            err,
            "shipcraft: output cut: the command wrote {} bytes; shown: the first {SHOWN} and the last {} line(s){end}",
            cut.count,
            lines.len()
        );
    }
    let file = cut.file.take();
    let failed = cut.failed;
    if let Invocation::Open { file: slot, .. } = &mut *lock(&STATE) {
        // Once a write failed, `F` is not written again in this invocation.
        *slot = if failed { None } else { file };
    }
}

/// The tail of the bytes not shown, given at least their last `SHOWN + 1`
/// (or all of them when fewer): the last `SHOWN` bytes, less a partial first
/// line, split at LF, the last `LINES` lines as lossy UTF-8.
fn tail(rest: &[u8]) -> Vec<String> {
    let (window, before) = match rest.len().checked_sub(SHOWN + 1) {
        Some(skip) => (&rest[skip + 1..], Some(rest[skip])),
        None => (rest, None),
    };
    let window = match before {
        Some(b) if b != b'\n' => window.iter().position(|&b| b == b'\n').map_or(window, |i| &window[i + 1..]),
        _ => window,
    };
    let mut lines: Vec<&[u8]> = window.split(|&b| b == b'\n').collect();
    if window.is_empty() || window.ends_with(b"\n") {
        lines.pop();
    }
    let from = lines.len().saturating_sub(LINES);
    lines[from..].iter().map(|line| String::from_utf8_lossy(line).into_owned()).collect()
}

fn lock<T>(mutex: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    mutex.lock().unwrap_or_else(|e| e.into_inner())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn short_unshown_part_keeps_its_first_line() {
        assert_eq!(tail(b"partial\nnext"), ["partial", "next"]);
        assert_eq!(tail(b"a\n"), ["a"]);
        assert!(tail(b"").is_empty());
        assert_eq!(tail(b"\n\n"), ["", ""]);
    }

    #[test]
    fn window_drops_a_partial_first_line() {
        let mut rest = vec![b'x'; 10];
        rest.extend(vec![b'y'; SHOWN - 9]);
        rest.extend(b"\nlast");
        let kept = &rest[rest.len() - (SHOWN + 1)..];
        assert_eq!(tail(kept), ["last"]);
    }

    #[test]
    fn window_after_a_newline_keeps_its_first_line() {
        let mut rest = b"\n".to_vec();
        rest.extend(vec![b'a'; SHOWN - 2]);
        rest.extend(b"\nb");
        assert_eq!(rest.len(), SHOWN + 1);
        let lines = tail(&rest);
        assert_eq!(lines.len(), 2);
        assert_eq!(lines[0].len(), SHOWN - 2);
    }

    #[test]
    fn long_last_line_is_its_last_bytes() {
        let rest = vec![b'z'; SHOWN + 1];
        let lines = tail(&rest);
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].len(), SHOWN);
    }

    #[test]
    fn last_forty_lines_and_lf_only() {
        let text: String = (0..100).map(|i| format!("l{i}\r\u{2028}\n")).collect();
        let lines = tail(text.as_bytes());
        assert_eq!(lines.len(), LINES);
        assert_eq!(lines[0], "l60\r\u{2028}");
        assert_eq!(lines[39], "l99\r\u{2028}");
    }

    #[test]
    fn invalid_utf8_is_lossy() {
        assert_eq!(tail(b"a\xffb\n"), ["a\u{fffd}b"]);
    }

    #[test]
    fn feed_shows_4096_counts_all_and_drops_after_deadline() {
        let mut cut = Cut {
            file: None,
            failed: false,
            shown_path: String::new(),
            count: 0,
            shown: 0,
            open: false,
            rest: Vec::new(),
            last: None,
            deadline: None,
            closed: false,
        };
        for _ in 0..10 {
            cut.feed(&[b'q'; 3000]);
        }
        assert_eq!((cut.count, cut.shown, cut.open), (30_000, SHOWN, true));
        assert!(cut.rest.len() > SHOWN && cut.rest.len() <= 4 * (SHOWN + 1));
        cut.until(Instant::now());
        cut.feed(b"late");
        assert_eq!(cut.count, 30_000);
    }
}
