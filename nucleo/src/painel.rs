//! Item 23: `shipcraft dashboard` serves the project's measurement live on
//! 127.0.0.1, reading only `runs.jsonl` and `.shipcraft/locks/` of the tree.
//! It writes nothing and calls no network.

use crate::git::{Repo, Snapshot};
use crate::lock::{Lock, FORMAT, LOCK_DIR};
use crate::refusal::{refuse, Result};
use serde::de::{Deserializer, IgnoredAny, MapAccess, Visitor};
use serde_json::Value;
use std::collections::BTreeMap;
use std::io::{BufRead, BufReader, ErrorKind, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const FIRST_PORT: u16 = 7420;
const PORTS: u16 = 20;

pub fn run(repo: Repo, porta: Option<&str>) -> Result<()> {
    let listener = match porta {
        Some(text) => {
            let Some(port) = text.parse::<u16>().ok().filter(|p| *p > 0) else {
                return refuse(
                    "port-invalid",
                    format!("port `{text}` is not a number from 1 to 65535"),
                    "the dashboard only opens a valid port",
                    "run `shipcraft dashboard --port <n>` with n from 1 to 65535, or without `--port`",
                );
            };
            TcpListener::bind(("127.0.0.1", port)).or_else(|e| {
                refuse(
                    "port-busy",
                    format!("port {port} could not open on 127.0.0.1 ({e})"),
                    "with `--port`, the dashboard only opens the requested port",
                    "close whatever uses that port, or run `shipcraft dashboard` without `--port`",
                )
            })?
        }
        // Opens, does not test first: two panels never take the same port.
        None => match (FIRST_PORT..FIRST_PORT + PORTS).find_map(|p| TcpListener::bind(("127.0.0.1", p)).ok()) {
            Some(listener) => listener,
            None => {
                return refuse(
                    "port-busy",
                    format!("ports {FIRST_PORT} through {} are busy on 127.0.0.1", FIRST_PORT + PORTS - 1),
                    "the dashboard only tries these 20, in order",
                    "close an open dashboard, or run `shipcraft dashboard --port <n>` with a free port",
                );
            }
        },
    };
    let port = listener.local_addr().map(|a| a.port()).unwrap_or_default();
    println!("shipcraft: dashboard at http://127.0.0.1:{port} (Ctrl-C to stop)");
    let panel = Arc::new(Panel { repo, state: Mutex::new((false, 0, Arc::new(String::new()))), done: Condvar::new() });
    for stream in listener.incoming().flatten() {
        let panel = Arc::clone(&panel);
        std::thread::spawn(move || panel.answer(stream));
    }
    Ok(())
}

struct Panel {
    repo: Repo,
    /// (an update is running, updates done, the page of the last one)
    state: Mutex<(bool, u64, Arc<String>)>,
    done: Condvar,
}

impl Panel {
    fn answer(&self, mut stream: TcpStream) {
        let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
        let mut reader = BufReader::new(&stream);
        let mut request = String::new();
        let _ = reader.read_line(&mut request);
        let mut header = String::new();
        while reader.read_line(&mut header).is_ok_and(|n| n > 2) {
            header.clear();
        }
        let mut parts = request.split_whitespace();
        let (method, path) = (parts.next().unwrap_or(""), parts.next().unwrap_or(""));
        let (status, body) = match (method, path) {
            ("GET" | "HEAD", "/") => ("200 OK", self.page()),
            _ => ("404 Not Found", Arc::new("not found\n".to_string())),
        };
        let head = format!(
            "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r\nConnection: close\r\n\r\n",
            body.len()
        );
        let _ = stream.write_all(head.as_bytes());
        if method != "HEAD" {
            let _ = stream.write_all(body.as_bytes());
        }
        // The client closes first (it has the length): no TIME_WAIT on the port.
        let _ = std::io::copy(&mut &stream, &mut std::io::sink());
    }

    /// One update at a time: a request that arrives during one gets its result.
    fn page(&self) -> Arc<String> {
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        if state.0 {
            let seen = state.1;
            while state.1 == seen {
                state = self.done.wait(state).unwrap_or_else(|e| e.into_inner());
            }
            return Arc::clone(&state.2);
        }
        state.0 = true;
        drop(state);
        let page = Arc::new(render(&self.repo));
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        *state = (false, state.1 + 1, Arc::clone(&page));
        self.done.notify_all();
        page
    }
}

#[derive(Default)]
struct Counts {
    camadas: [u64; 3],
    recusas: BTreeMap<String, u64>,
    hook_times: Vec<f64>,
    tokens: f64,
    sem_medida: u64,
}

impl Counts {
    fn add(&mut self, row: &Value, camada: usize) {
        self.camadas[camada] += 1;
        if row["result"] == "refused" {
            let code = row["code"].as_str().filter(|c| !c.is_empty()).unwrap_or("no code");
            *self.recusas.entry(code.to_string()).or_default() += 1;
        }
        if let (0, Some(t)) = (camada, row["secs"].as_f64()) {
            self.hook_times.push(t);
        }
        if camada == 2 {
            match row["tokens"].as_f64() {
                Some(n) => self.tokens += n,
                None => self.sem_medida += 1,
            }
        }
    }

    /// One line, each value after its visible label.
    fn line(&mut self, label: &str) -> String {
        self.hook_times.sort_by(f64::total_cmp);
        let recusas: Vec<String> = self.recusas.iter().map(|(c, n)| format!("{c}: {n}")).collect();
        let [hook, ci, revisao] = self.camadas;
        let text = format!(
            "hook: {hook}; ci: {ci}; review: {revisao}; total: {} | refusals by code: {} | hook p50: {}; hook p90: {} | review tokens: {}",
            hook + ci + revisao,
            if recusas.is_empty() { "—".to_string() } else { recusas.join("; ") },
            rank(&self.hook_times, 50),
            rank(&self.hook_times, 90),
            tokens(self.tokens, self.sem_medida)
        );
        format!("<p><b>{}</b>: {}</p>\n", escape(label), escape(&text))
    }
}

/// Nearest rank, as the N of item 24: the value at position ⌈p·n⌉.
fn rank(sorted: &[f64], p: usize) -> String {
    match sorted.len() {
        0 => "—".to_string(),
        n => format!("{} s", sorted[(p * n).div_ceil(100) - 1]),
    }
}

/// `50 thousand (1 review unmeasured)`: a total missing a measure never looks complete.
fn tokens(total: f64, sem_medida: u64) -> String {
    let total = total.round();
    let mut text = match total {
        t if t.abs() < 1000.0 => format!("{t}"),
        t => format!("{} thousand", ((t / 100.0).round() / 10.0).to_string()),
    };
    match sem_medida {
        0 => {}
        1 => text += " (1 review unmeasured)",
        n => text += &format!(" ({n} reviews unmeasured)"),
    }
    text
}

fn render(repo: &Repo) -> String {
    let started = Instant::now();
    let mut body = String::new();
    let source = match repo.shipcraft_dir() {
        Ok(dir) => dir.join("runs.jsonl"),
        Err(_) => "runs.jsonl".into(),
    };
    let (mut days, mut total) = (BTreeMap::<String, Counts>::new(), Counts::default());
    let (mut invalid, mut sem_data, mut lidas) = (0u64, 0u64, 0u64);
    let mut others = BTreeMap::<String, u64>::new();
    match std::fs::read(&source) {
        Err(e) if e.kind() == ErrorKind::NotFound => body += "<p>No runs yet: runs.jsonl does not exist.</p>\n",
        Err(e) => body += &format!("<p>could not read runs.jsonl: {}</p>\n", escape(&e.to_string())),
        Ok(bytes) => {
            // The last line without `\n` is being written: next update.
            for line in bytes.split_inclusive(|b| *b == b'\n').filter_map(|l| l.strip_suffix(b"\n")) {
                lidas += 1;
                let row = std::str::from_utf8(line).ok().and_then(|l| serde_json::from_str::<Value>(l).ok());
                let Some(row) = row.filter(Value::is_object) else {
                    invalid += 1;
                    continue;
                };
                let camada = ["hook", "ci", "review"].iter().position(|c| row["layer"] == *c);
                let resultado = ["passed", "refused", "error"].iter().any(|r| row["result"] == *r);
                let Some(camada) = camada.filter(|_| resultado) else {
                    *others.entry(first_field(line)).or_default() += 1;
                    continue;
                };
                total.add(&row, camada);
                match row["at"].as_i64().or_else(|| row["at"].as_u64().map(|q| q as i64)) {
                    Some(when) => days.entry(local(when).0).or_default().add(&row, camada),
                    None => sem_data += 1,
                }
            }
            if total.camadas.iter().sum::<u64>() == 0 {
                body += "<p>No runs yet.</p>\n";
            }
        }
    }
    body += "<h2>By day</h2>\n";
    for (day, counts) in days.iter_mut().rev() {
        body += &counts.line(day);
    }
    body += "<h2>Overall</h2>\n";
    body += &total.line("Total");
    body += &format!("<p>no date: {sem_data}</p>\n<p>unreadable lines: {invalid}</p>\n");
    if !others.is_empty() {
        let list: Vec<String> = others.iter().map(|(f, n)| format!("{f}: {n}")).collect();
        body += &format!("<p>other records: {}</p>\n", escape(&list.join("; ")));
    }
    body += &locks(repo);
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0);
    body += &format!(
        "<p class=\"fonte\">Source: runs from {} ({lidas} complete lines); locks from {LOCK_DIR}/ in the tree of {}. Read at {} ({}); refresh took {} ms.</p>\n",
        escape(&source.to_string_lossy()),
        escape(&repo.root().to_string_lossy()),
        local(now).1,
        local(now).0,
        started.elapsed().as_millis()
    );
    format!(
        "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><meta http-equiv=\"refresh\" content=\"10\"><title>shipcraft dashboard: {}</title>\n<style>body{{font:14px system-ui,sans-serif;margin:16px;color:#222;background:#fff}}.fonte{{color:#666}}</style></head>\n<body><h1>shipcraft dashboard: {}</h1>\n{body}</body></html>\n",
        escape(&repo.name()),
        escape(&repo.name())
    )
}

/// Open locks now, by the core's reader; one it does not accept never vanishes.
fn locks(repo: &Repo) -> String {
    let paths = match repo.list(&Snapshot::Tree, LOCK_DIR) {
        Ok(paths) => paths,
        Err(e) => {
            return format!(
                "<p>could not read {LOCK_DIR}/: {}</p>\n",
                escape(&match e {
                    crate::refusal::Stop::Failed(m) => m,
                    crate::refusal::Stop::Refused(r) => r.what().to_string(),
                })
            )
        }
    };
    let (mut open, mut unread) = (Vec::new(), Vec::new());
    for path in paths.into_iter().filter(|p| p.ends_with(".json")) {
        match repo.read(&Snapshot::Tree, &path).ok().flatten().as_deref().and_then(Lock::parse) {
            Some(lock) if lock.formato != FORMAT => unread.push(path),
            Some(lock) if lock.is_open() => open.push(path),
            Some(_) => {}
            None => unread.push(path),
        }
    }
    let list = |items: &[String]| match items {
        [] => "none".to_string(),
        _ => escape(&items.join(", ")),
    };
    let mut text = format!("<p>Open locks now: {}</p>\n", list(&open));
    if !unread.is_empty() {
        text += &format!("<p>unreadable locks: {}</p>\n", list(&unread));
    }
    text
}

/// The first field of a JSON object as written (serde_json sorts its maps).
fn first_field(line: &[u8]) -> String {
    struct First;
    impl<'de> Visitor<'de> for First {
        type Value = String;
        fn expecting(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
            f.write_str("an object")
        }
        fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> std::result::Result<String, A::Error> {
            let first = map.next_key::<String>()?.unwrap_or_else(|| "(empty)".to_string());
            map.next_value::<IgnoredAny>().ok();
            while map.next_entry::<IgnoredAny, IgnoredAny>()?.is_some() {}
            Ok(first)
        }
    }
    let mut de = serde_json::Deserializer::from_slice(line);
    de.deserialize_map(First).unwrap_or_else(|_| "(empty)".to_string())
}

/// `struct tm`: sec, min, hour, mday, mon, year, wday, yday, isdst; gmtoff; zone.
#[repr(C)]
struct Tm([i32; 9], i64, *const u8);

extern "C" {
    fn localtime_r(time: *const i64, tm: *mut Tm) -> *mut Tm;
}

/// The day (`AAAA-MM-DD`) and the time (`HH:MM:SS`) in the machine's time zone.
fn local(when: i64) -> (String, String) {
    let mut tm = Tm([0; 9], 0, std::ptr::null());
    // SAFETY: localtime_r only writes the struct we own.
    unsafe { localtime_r(&when, &mut tm) };
    (
        format!("{:04}-{:02}-{:02}", tm.0[5] + 1900, tm.0[4] + 1, tm.0[3]),
        format!("{:02}:{:02}:{:02}", tm.0[2], tm.0[1], tm.0[0]),
    )
}

/// Every datum enters the page as text, never as HTML.
fn escape(text: &str) -> String {
    text.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;").replace('\'', "&#39;")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nearest_rank_is_the_ceiling_position() {
        let times: Vec<f64> = (1..=10).map(f64::from).collect();
        assert_eq!(rank(&times, 50), "5 s");
        assert_eq!(rank(&times, 90), "9 s");
        assert_eq!(rank(&[3.0], 90), "3 s");
        assert_eq!(rank(&[], 50), "—");
    }

    #[test]
    fn tokens_say_when_a_review_has_no_measure() {
        assert_eq!(tokens(50_000.0, 1), "50 thousand (1 review unmeasured)");
        assert_eq!(tokens(1_250.0, 2), "1.3 thousand (2 reviews unmeasured)");
        assert_eq!(tokens(999.0, 0), "999");
    }

    #[test]
    fn first_field_is_the_written_one_and_text_is_escaped() {
        assert_eq!(first_field(br#"{"z": 1, "a": 2}"#), "z");
        assert_eq!(first_field(b"{}"), "(empty)");
        assert_eq!(escape("<script>&\"'"), "&lt;script&gt;&amp;&quot;&#39;");
    }
}
