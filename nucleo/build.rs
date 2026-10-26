//! Item 21.1: the commit `shipcraft --version` names, the first 12 characters of the
//! commit compiled, or `sem-git` outside a repository. Without rerun directives
//! cargo reruns this when a file of the package changes, so a local build can
//! name an older commit (accepted: the release builds from a fresh checkout).

use std::process::Command;

fn main() {
    let dir = std::env::var("CARGO_MANIFEST_DIR").unwrap_or_default();
    let commit = Command::new("git")
        .args(["-C", &dir, "rev-parse", "--verify", "HEAD"])
        .output()
        .ok()
        .filter(|out| out.status.success())
        .map(|out| String::from_utf8_lossy(&out.stdout).trim().to_string())
        .filter(|sha| sha.len() >= 12 && sha.bytes().all(|b| b.is_ascii_hexdigit()))
        .map_or_else(|| "no-git".to_string(), |sha| sha[..12].to_string());
    println!("cargo:rustc-env=SHIPCRAFT_COMMIT={commit}");
}
