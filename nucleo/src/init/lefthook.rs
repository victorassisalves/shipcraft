//! Reading and editing lefthook and YAML hook files (items 15b, 20, 25).

use crate::git::Repo;
use std::fs;

/// A name the lefthook reads its configuration from: `lefthook` or
/// `lefthook-local`, with or without the dot, in any format it reads.
pub fn lefthook_source(name: &str) -> bool {
    let name = name.strip_prefix('.').unwrap_or(name);
    let rest = name.strip_prefix("lefthook").map(|r| r.strip_prefix("-local").unwrap_or(r));
    rest.and_then(|r| r.strip_prefix('.')).is_some_and(|ext| ["yml", "yaml", "json", "jsonc", "toml"].contains(&ext))
}

/// 15b.1 and 15a.2: the lefthook reads its configuration from `file` alone
/// (from nothing, when `file` is empty), or the first source it may read
/// instead: `LEFTHOOK_CONFIG`, or `lefthook` or `lefthook-local`, with or
/// without the dot, in any format it reads, at the root or in `.config/`. A
/// directory it cannot list is a source in doubt, not an absent one (rule 17).
pub fn single_source(repo: &Repo, file: &str) -> std::result::Result<(), String> {
    if std::env::var_os("LEFTHOOK_CONFIG").is_some() {
        return Err("LEFTHOOK_CONFIG is set".into());
    }
    for dir in ["", ".config/"] {
        let path = repo.path(if dir.is_empty() { "." } else { dir });
        // Nothing there, or a plain file (named without the slash, which a
        // file refuses): surely no source inside.
        let plain = repo.path(dir.trim_end_matches('/')).symlink_metadata().is_ok_and(|m| m.is_file());
        if plain || path.symlink_metadata().map_or_else(|e| e.kind() == std::io::ErrorKind::NotFound, |m| m.is_file()) {
            continue;
        }
        let unread = |e: std::io::Error| format!("cannot read {} ({e})", if dir.is_empty() { "the root" } else { dir });
        for entry in fs::read_dir(&path).map_err(unread)? {
            let name = format!("{dir}{}", entry.map_err(unread)?.file_name().to_string_lossy());
            // Case-insensitive: so is the file system on macOS.
            let lower = name.to_ascii_lowercase();
            if lower != file && lefthook_source(&lower[dir.len()..]) {
                return Err(format!("found {name}"));
            }
        }
    }
    Ok(())
}

/// 15b.4, from the parser's events (not the text): the first thing that is not
/// the block layout (flow, an anchor or alias, a merge `<<`, a quoted key, a
/// `...`), or each pre-commit command's written priority: (name, raw, plain).
pub fn block_layout(text: &str) -> std::result::Result<Vec<(String, String, bool)>, String> {
    layout(text, false)
}

/// With `repos_only` (item 25), flow and quoted keys count only in the
/// `repos` key and its list; anchors, aliases, merges and `...` everywhere.
pub fn layout(text: &str, repos_only: bool) -> std::result::Result<Vec<(String, String, bool)>, String> {
    use std::mem::MaybeUninit;
    use unsafe_libyaml_norway as unsafe_yaml;
    // One frame per open collection: (is a map, the key whose value comes next).
    let mut stack: Vec<(bool, Option<String>)> = Vec::new();
    let mut written = Vec::new();
    let mut parser = Box::new(MaybeUninit::<unsafe_yaml::yaml_parser_t>::uninit());
    let parser = parser.as_mut_ptr();
    // SAFETY: the parser is initialized before use and deleted once; each
    // event is read while alive and deleted right after.
    unsafe {
        if unsafe_yaml::yaml_parser_initialize(parser).fail {
            return Err("cannot be read as YAML".into());
        }
        unsafe_yaml::yaml_parser_set_input_string(parser, text.as_ptr(), text.len() as u64);
        let result = loop {
            let mut event = MaybeUninit::<unsafe_yaml::yaml_event_t>::uninit();
            if unsafe_yaml::yaml_parser_parse(parser, event.as_mut_ptr()).fail {
                break Err("cannot be read as YAML".into());
            }
            let e = &*event.as_ptr();
            let step = layout_step(e, &mut stack, &mut written, repos_only);
            let end = e.type_ == unsafe_yaml::YAML_STREAM_END_EVENT;
            unsafe_yaml::yaml_event_delete(event.as_mut_ptr());
            match step {
                Err(problem) => break Err(problem),
                Ok(()) if end => break Ok(()),
                Ok(()) => {}
            }
        };
        unsafe_yaml::yaml_parser_delete(parser);
        result.map(|()| written)
    }
}

/// One parser event of `block_layout`.
unsafe fn layout_step(
    e: &unsafe_libyaml_norway::yaml_event_t,
    stack: &mut Vec<(bool, Option<String>)>,
    written: &mut Vec<(String, String, bool)>,
    repos_only: bool,
) -> std::result::Result<(), String> {
    use unsafe_libyaml_norway::*;
    let styled = !repos_only || matches!(&stack[..], [(true, Some(k))] if k == "repos");
    let anchor = match e.type_ {
        YAML_SCALAR_EVENT => e.data.scalar.anchor,
        YAML_MAPPING_START_EVENT => e.data.mapping_start.anchor,
        YAML_SEQUENCE_START_EVENT => e.data.sequence_start.anchor,
        _ => std::ptr::null_mut(),
    };
    if e.type_ == YAML_ALIAS_EVENT || !anchor.is_null() {
        return Err("uses an anchor or alias".into());
    }
    if e.type_ == YAML_DOCUMENT_END_EVENT && !e.data.document_end.implicit {
        return Err("ends the document with `...`".into());
    }
    if styled
        && ((e.type_ == YAML_MAPPING_START_EVENT && e.data.mapping_start.style == YAML_FLOW_MAPPING_STYLE)
            || (e.type_ == YAML_SEQUENCE_START_EVENT && e.data.sequence_start.style == YAML_FLOW_SEQUENCE_STYLE))
    {
        return Err("uses flow style ({...} or [...])".into());
    }
    let is_key = matches!(stack.last(), Some((true, None)));
    match e.type_ {
        YAML_SCALAR_EVENT => {
            let s = &e.data.scalar;
            let value = String::from_utf8_lossy(std::slice::from_raw_parts(s.value, s.length as usize)).into_owned();
            let plain = s.style == YAML_PLAIN_SCALAR_STYLE && s.tag.is_null();
            if is_key && !plain && (!repos_only || (stack.len() == 1 && value == "repos")) {
                return Err("has a quoted key".into());
            }
            if is_key && value == "<<" {
                return Err("uses merge `<<`".into());
            }
            if is_key {
                stack.last_mut().unwrap().1 = Some(value);
                return Ok(());
            }
            let path: Vec<&str> = stack.iter().map(|(_, key)| key.as_deref().unwrap_or("-")).collect();
            if let ["pre-commit", "commands", name, "priority"] = path[..] {
                written.push((name.to_string(), value, plain));
            }
        }
        YAML_MAPPING_START_EVENT | YAML_SEQUENCE_START_EVENT if is_key => return Err("has a non-text key".into()),
        YAML_MAPPING_START_EVENT | YAML_SEQUENCE_START_EVENT => {
            stack.push((e.type_ == YAML_MAPPING_START_EVENT, None));
            return Ok(());
        }
        YAML_MAPPING_END_EVENT | YAML_SEQUENCE_END_EVENT => {
            stack.pop();
        }
        _ => return Ok(()),
    }
    // A value ended: its map waits for the next key.
    if let Some((true, key)) = stack.last_mut() {
        *key = None;
    }
    Ok(())
}

/// The lefthook text with a `shipcraft` command (its `body` lines) at the end of
/// `block:` → `commands:` (each created when missing), in the indentation
/// and the line ending the file already uses.
pub fn insert_text(text: &str, block: &str, body: &[String]) -> String {
    let text = &bare_nulls(text, block);
    let eol = if text.contains("\r\n") { "\r\n" } else { "\n" };
    let lines: Vec<&str> = text.split_inclusive('\n').collect();
    let indent = |l: &str| l.len() - l.trim_start_matches(' ').len();
    let content = |l: &str| !l.trim().is_empty() && !l.trim_start().starts_with('#');
    let key = |l: &str, k: &str| {
        l.trim_start().strip_prefix(k).is_some_and(|rest| rest.trim().is_empty() || rest.trim_start().starts_with('#'))
    };
    let end_of = |from: usize, depth: usize| {
        (from..lines.len()).find(|&i| content(lines[i]) && indent(lines[i]) <= depth).unwrap_or(lines.len())
    };
    let entry = |pad: usize, step: usize| {
        let (pad, inner) = (" ".repeat(pad), " ".repeat(pad + step));
        format!("{pad}shipcraft:{eol}") + &body.iter().map(|l| format!("{inner}{l}{eol}")).collect::<String>()
    };
    let (at, added) = match lines.iter().position(|l| indent(l) == 0 && key(l, &format!("{block}:"))) {
        None => (lines.len(), format!("{block}:{eol}  commands:{eol}{}", entry(4, 2))),
        Some(block) => {
            let end = end_of(block + 1, 0);
            match (block + 1..end).find(|&i| key(lines[i], "commands:")) {
                None => (block + 1, format!("  commands:{eol}{}", entry(4, 2))),
                Some(commands) => {
                    let depth = indent(lines[commands]);
                    let end = end_of(commands + 1, depth);
                    let pad = (commands + 1..end).find(|&i| content(lines[i])).map_or(depth + 2, |i| indent(lines[i]));
                    (end, entry(pad, pad - depth))
                }
            }
        }
    };
    let mut new = lines[..at].concat();
    if !new.is_empty() && !new.ends_with('\n') {
        new.push_str(eol);
    }
    new + &added + &lines[at..].concat()
}

/// 20.2: `block: null` (or `~`) and its `commands: null` become `block:` and
/// `commands:`, the comment kept, so the commands go in block layout.
fn bare_nulls(text: &str, block: &str) -> String {
    let mut inside = false;
    let mut out = String::new();
    for line in text.split_inclusive('\n') {
        let body = line.trim_end_matches(['\r', '\n']);
        let (eol, pad) = (&line[body.len()..], &body[..body.len() - body.trim_start().len()]);
        if pad.is_empty() && !body.is_empty() && !body.starts_with('#') {
            inside = body.starts_with(&format!("{block}:"));
        }
        let key = if pad.is_empty() { format!("{block}:") } else { "commands:".to_string() };
        let rest = body.trim_start().strip_prefix(&key).filter(|_| inside);
        let (value, comment) =
            rest.map_or(("", ""), |r| r.split_once('#').map_or((r, ""), |(v, _)| (v, &r[v.len()..])));
        if ["null", "Null", "NULL", "~"].contains(&value.trim()) {
            out +=
                &format!("{pad}{key}{}{eol}", if comment.is_empty() { String::new() } else { format!(" {comment}") });
        } else {
            out += line;
        }
    }
    out
}
