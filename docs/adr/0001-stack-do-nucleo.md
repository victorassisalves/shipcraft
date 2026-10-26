# ADR 0001: Core stack

- **Status:** accepted by Victor, 2026-10-23, after an internal trial.
- **Date:** 2026-10-23.

## Context and options

Shipcraft is a CLI installed in Python, Go and TypeScript projects. It runs git and the project's runner and reads JUnit. It must not require an extra runtime in the user's project.

Rust and Go produce standalone binaries. TypeScript/Node and Python offer fast iteration but require their runtimes. Rust also reuses the earlier implementation's tested lock and hook logic. A pilot TypeScript monorepo informed the Node option; it does not constrain the CLI.

## Decision

Use **Rust**, distributed through GitHub releases. Both trial implementations passed 115/115 acceptance cases on macOS and Linux. Rust's types and ownership catch more agent-written mistakes and allow direct reuse of earlier logic.

| Trial measurement | Rust | Go |
|---|---|---|
| Binary | 0.9 MB | 4.7 MB |
| Linux CI, build and battery | 3 min 59 s | 4 min 07 s |
| Dependencies | 5 crates | 0 |

The measured Rust build took 12 s cold and 0.8 s incremental. Accept dependency auditing in CI and a native GitHub runner for each release target.

## Reversal

The public contract is the CLI and config, independent of implementation language. Replacing Rust means implementing the same contract and passing the same battery.
