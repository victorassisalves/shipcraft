<!-- shipcraft -->
## shipcraft: TDD with a lock (required in this repository)
- Cycle: RED (a failing test) → `shipcraft red` → GREEN (code) → `git commit`. The git hook checks every commit.
- A behavior change: write the failing test first (and a stub), run `shipcraft red` and commit the test together with the lock `.shipcraft/locks/*.json`; only then implement.
- Locked tests (listed in the open lock) are the contract: never change them; change the code until they pass. If a test looks wrong, stop and say so.
- The RED and the GREEN are done by different agent sessions, both in the same checkout: in Claude Code a subagent per phase; in Codex a new `codex exec` session per phase (never `resume`).
- The RED session commits the tests, the stubs they need and the lock in one commit, and stops.
- The GREEN session starts from that commit and may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, then commits. A test it finds wrong is reported back, and a RED session fixes it with `shipcraft red --redo`.
- A session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them.
- Never use `--no-verify`, never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `shipcraft red --redo` and the hook write them), never touch the hook or `core.hooksPath`.
- When in doubt, run `shipcraft status`.
<!-- /shipcraft -->
