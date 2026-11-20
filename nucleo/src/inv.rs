//! Item 146: the project's invocation in every printed command, read once per process.

use std::path::Path;
use std::sync::OnceLock;

static INVOCATION: OnceLock<&'static str> = OnceLock::new();

const COMMANDS: [&str; 13] =
    ["init", "red", "check", "close", "ci", "export", "pr", "review", "merge", "status", "report", "uninstall", "--version"];

/// Point 1: from the nearest folder holding a `.git` entry, items 58's and 69's rule;
/// `shipcraft` with no root. Starts no process; called in `main` before dispatch.
pub fn read() {
    let found = std::env::current_dir().ok().and_then(|here| {
        here.ancestors().find(|dir| dir.join(".git").symlink_metadata().is_ok()).map(Path::to_path_buf)
    });
    let invocation = match found {
        Some(root) => crate::init::invocation(&root, &crate::init::install_at(&root)),
        None => "shipcraft",
    };
    let _ = INVOCATION.set(invocation);
}

/// Point 2 with this process's invocation.
pub fn route(text: &str) -> String {
    route_with(INVOCATION.get().copied().unwrap_or("shipcraft"), text)
}

/// Point 2: each `shipcraft <command>` at a word start becomes `<invocation> <command>`,
/// in one pass over the original text, never after `npx -- ` or `pnpm exec `.
fn route_with(invocation: &str, text: &str) -> String {
    if invocation == "shipcraft" {
        return text.to_string();
    }
    let bytes = text.as_bytes();
    let mut out = Vec::with_capacity(bytes.len() + 16);
    let mut i = 0;
    while i < bytes.len() {
        if routable(bytes, i) {
            out.extend_from_slice(invocation.as_bytes());
            i += "shipcraft".len();
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8(out).unwrap_or_else(|_| text.to_string())
}

fn routable(bytes: &[u8], at: usize) -> bool {
    let (before, rest) = bytes.split_at(at);
    let Some(rest) = rest.strip_prefix(b"shipcraft ") else { return false };
    if before.last().is_some_and(|&b| b.is_ascii_alphanumeric() || b"-_/.".contains(&b))
        || before.ends_with(b"npx -- ")
        || before.ends_with(b"pnpm exec ")
    {
        return false;
    }
    COMMANDS.iter().any(|command| match rest.strip_prefix(command.as_bytes()) {
        Some(after) => after.first().is_none_or(|b| b" `\"'),;.:\n".contains(b)),
        None => false,
    })
}

#[cfg(test)]
mod tests {
    use super::route_with;

    const NPX: &str = "npx -- shipcraft";

    #[test]
    fn routes_commands_at_a_word_start() {
        assert_eq!(route_with(NPX, "run `shipcraft red --redo` again"), "run `npx -- shipcraft red --redo` again");
        assert_eq!(route_with(NPX, "shipcraft init"), "npx -- shipcraft init");
        assert_eq!(route_with("pnpm exec shipcraft", "x; run shipcraft uninstall again"), "x; run pnpm exec shipcraft uninstall again");
        assert_eq!(route_with(NPX, "a\nshipcraft ci\nb"), "a\nnpx -- shipcraft ci\nb");
        assert_eq!(route_with(NPX, "é shipcraft --version."), "é npx -- shipcraft --version.");
        assert_eq!(route_with(NPX, "(shipcraft pr), shipcraft merge:"), "(npx -- shipcraft pr), npx -- shipcraft merge:");
    }

    #[test]
    fn keeps_everything_else() {
        for text in [
            "shipcraft: error",
            "shipcraft refused: x",
            "shipcraft/ci and shipcraft/review",
            ".shipcraft.toml, shipcraft_min",
            "see shipcraft docs/github-ci.md",
            "shipcraft prx, shipcraft red-x, shipcraft ci\r",
            "x-shipcraft red, a/shipcraft red, 1shipcraft red",
            "run `npx -- shipcraft red` or pnpm exec shipcraft init",
        ] {
            assert_eq!(route_with(NPX, text), text);
        }
        assert_eq!(route_with("shipcraft", "run `shipcraft red`"), "run `shipcraft red`");
    }

    #[test]
    fn one_pass() {
        assert_eq!(route_with(NPX, "shipcraft red shipcraft red"), "npx -- shipcraft red npx -- shipcraft red");
    }
}
