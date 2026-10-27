# Shipcraft 2.0: the contract

This is the public contract of `shipcraft`: what it guarantees and what each command, config key and refusal means. The acceptance battery in `acceptance/` is the executable contract and fixes the edge cases this text leaves out.

## 1. Guarantee and threat model

**The guarantee.** A test written at RED stays the judge until it passes. The agent that writes the code (the GREEN) cannot make the suite pass by changing, deleting or skipping a locked test, its support files, or the config that says how the suite runs. The git hook checks this on every commit. CI repeats every check, so a commit made with `--no-verify` or an edited hook is caught there.

On top of that, every PR goes through two layers before merge: `shipcraft` CI and an executed review by an agent that did not write the code. Each project chooses where each layer runs. A layer that is off says so in its status description on every PR.

**The threat model** is a good-faith agent that makes mistakes or takes shortcuts. It is not an adversary that rewrites `shipcraft`, forges a lock seal or publishes fake statuses through the GitHub API. Every rule follows one principle: when `shipcraft` cannot prove something about the project, it falls back to the slower or stricter path. A failed inference costs time, never a wrong verdict.

## 2. The lock cycle

### RED opens a lock

`shipcraft red` runs the suite and requires it to fail on assertions, not on import or collection errors. It writes `.shipcraft/locks/<id>.json`, one file per cycle, so two branches never conflict. A lock holds:

| Field | Content |
|---|---|
| `format` | The lock format version. A `shipcraft` that does not know it refuses to judge (`lock-format`). |
| `state` | `open` or `closed`. |
| `files` | The SHA-256 of each locked file (tests, support files, `.shipcraft.toml`), by path. In format 3 each value is written `sha256:<64 lowercase hex>`. |
| `cases` | The cases the report showed at RED, skipped ones excluded. |
| `failing_at_red` | The cases that failed at RED. |
| `seal` | SHA-256 of the lock with an empty seal. It catches hand edits; it is not a signature. |

**Lock format 3 (item 43).** `red` writes format 3, where every `files` value (tests, support files, runner configs, `.shipcraft.toml`) carries the `sha256:` prefix. In format 2 the value was the bare hex digest, and secret scanners read a 64-character hex value after a path that names `auth`, `access`, `token` or `key` as a leaked credential: gitleaks 8.30.1 with its default rules reported `generic-api-key` twice on one lock in draken-platform#18, and zero on the same lock with the prefix. Paths, case ids and `seal` are unchanged.

- **The seal** is computed as in format 2: SHA-256 of the lock's compact JSON with an empty `seal`, fields in their fixed order and `files` sorted by path, with the `files` values exactly as written (prefixed in format 3). It does not depend on the file's whitespace or key order.
- **Format belongs to each lock.** A binary that writes format 3 reads format 2 and 3 locks, each by its own `format`, at every snapshot it reads: the hook's parent and index, every commit CI walks, both parents of a merge. A format 2 lock is judged as before: its bare values are compared to the digest of the file's bytes. Repositories are never migrated; a tree can hold locks of both formats.
- **Closing keeps the format.** Every path that closes a lock (`close` after the commit, and `check` when it closes) changes only `state` and `seal`; `format` and every `files` value stay as they were. A format 2 lock closes as format 2.
- **Value syntax is part of reading a lock.** A format 3 lock whose `files` value does not match `^sha256:[0-9a-f]{64}$` exactly (no trimming, no case folding), or a format 2 lock with a value that is not 64 lowercase hex characters, is not a valid lock, whatever its seal, state or the files' contents: it is refused like a hand edit (`lock-edited`), where a hand edit is refused today. A lock that is not JSON or not a lock object is handled as today.
- **Versions.** The item raises the binary to 2.3.0, so `init` writes `shipcraft_min = "2.3"`. `red` does not change an existing config: a project with `shipcraft_min = "2.1"` keeps it. A binary older than 2.3 refuses by the first thing it does not support: `shipcraft-min` when the config asks for 2.3, else `lock-format` on a format 3 lock.

The RED is a commit: the one that adds the open lock, with the tests as locked and the suite failing. If a lock file is in the tree but outside the commit, the hook warns with the `git add` command; the warning never changes the verdict. The empty `.shipcraft/locks/.gitkeep` that `init` writes is never warned about (item 48): before item 48 every commit warned that it was outside the commit even when it was committed, because an empty blob in the index also marks `git add -N` (draken-platform, every commit since the install). The exception is only that exact path at the repository root, whoever created it, in any git state (untracked, ignored, `git add -N`, staged, committed), and only while it is empty as the warning's own reader sees it (the effective index's blob for an index entry, a regular file of zero bytes in the tree otherwise); a non-empty or non-regular entry there, and every other path, warn as before. It is dropped before the warnings are ordered and counted, so it takes no line and is not in "and N more". A failed query still prints the one `could not read` warning. One cycle at a time per branch: a new `red` is refused while the branch has an open lock (`lock-open`).

### What is refused while a lock is open

A commit is refused if:

- a locked file changed (`test-changed`) or was deleted (`locked-file-deleted`);
- `.shipcraft.toml` changed (`config-changed`);
- a hook integration file changed (`hook-config-changed`: lefthook config, `.pre-commit-config.yaml`, `.husky/commit-msg`, `.husky/post-commit`);
- a locked case is missing from the report (`case-missing`) or was skipped (`case-skipped`);
- a case the hook ran fails, even one that passed at RED (`case-broke`): a known failure is never ignored;
- the lock was deleted (`lock-deleted`) or edited outside `shipcraft` (`lock-edited`), except a redo commit (item 46);
- the lock arrives `closed` while locked cases still fail (`lock-closed-red`).

Intermediate commits with the suite still red are accepted. When it is safe, the `Next:` line of a lock refusal gives the exact `git restore` command.

### Redoing the RED (item 46)

When a locked test is itself wrong, no GREEN can pass it. In draken-platform a locked case set up its fixture with an `update` that the database's own check refused, before any product code ran; the hook refused the one-line fix (`test-changed`), and the only way out was to drop the RED commit and rewrite the pushed branch. `shipcraft red --redo` fixes the RED in a commit of its own instead.

- **Which lock.** The lock HEAD holds open. With none, `--redo` refuses `redo-without-lock` (an uncommitted RED needs no redo: delete its lock file and run `red` again); with two or more, `lock-open`. HEAD's lock is read as today: if it cannot be parsed, its seal is broken or its format is unknown, the refusal is today's (`lock-edited`, `lock-format`).
- **What it runs.** The suite, exactly as `red` runs it on the working tree (build, every suite's `check`, every suite), with the same refusals and their precedence. A project whose other suites do not pass their `check` cannot redo until they do.
- **What it requires.** Every case of HEAD's lock `cases` is in the new report's cases, by the identities the report reader gives today; otherwise `redo-drops-case`, naming them, checked after the report is read and judged for `error-before-assertions`, and before `red-already-passes`. A repair that renames a case, or that leaves every RED case passing, is not supported: rewrite the branch's history as before. The new lock needs at least one failing case, as `red` does.
- **What it writes.** It rewrites HEAD's lock file in place (same path, same id) as a new open lock in the current format, exactly what `red` would write for this tree: `files`, `cases` and `failing_at_red` recomputed, sealed. It validates first and replaces the file atomically (a temporary file renamed over it), so a refusal or a failed write leaves the old bytes; a failed write refuses `redo-write-failed`. It prints the lock path and three sorted lists: cases added, cases no longer failing at RED, cases newly failing at RED. If the new lock reads the same as HEAD's, it writes nothing and says so. It does not commit.
- **The redo commit.** A commit with one parent whose lock file changes from one open lock to another open lock with the same path is a redo commit. It is accepted, by the hook and by CI, when: the new lock is valid (parsed, sealed, value syntax of its format); it keeps every case of the parent's lock; every path the commit changes (both sides of a rename, as `git diff --name-status --no-renames` lists them, mode and type changes included) is the lock itself or a file that the parent's lock or the new lock protects; and none of them is `.shipcraft.toml` or a hook integration file. Otherwise: a dropped case refuses `redo-drops-case`, any other path refuses `redo-mixed` (naming the paths), and anything else refuses `lock-edited` as today. The redo commit is then judged as a commit that opens a lock is judged today: the hook checks the new lock's hashes against the commit and runs its RED cases, which must fail; CI checks the hashes at that commit and runs suites at HEAD only, as it does for every RED commit. Every later commit is judged against the new lock. A merge commit never counts as a redo: a lock it carries must equal one parent's, as today.
- **Visible.** Each `red --redo` writes its `red` row with `redo: true` (refusals included); the lock id stays, so `shipcraft report` keeps one cycle per lock and adds `redos` to it: the number of successful `red --redo` rows for that lock. A redo commit is a commit of the PR like any other, so the review sees its tests in the PR's diff.
- **Known limits.** What counts as a test is what the globs say: with globs that also match product code (`**/*.go`), a redo commit can change that code too. A redo may drop a protected support file while keeping every case. A repair that needs a product stub in the same commit is not supported. Redo commits need 2.6 or later wherever they are judged; an older binary refuses them as `lock-edited`, and `init` writes `shipcraft_min = "2.6"`. An existing project raises its minimum only with no lock open.

### The lock closes by itself

The first commit after RED in which every case in `failing_at_red` passes, none skipped or missing, closes the lock. The `commit-msg` hook judges the commit and the `post-commit` hook writes `closed` in a separate closing commit right after it (see `init`). The closing commit that `close` creates (post-commit or a manual retry; not a user's own commit judged by `check`) has the subject `chore(shipcraft): close lock <ids>`: the lock ids (file names without `.json`) in bytewise ascending order joined by `, `, one line ending in LF, no body or trailers (item 49; this fixes the order item 17 left free). Before item 49 the subject was `shipcraft: close lock <ids>`, outside the Conventional Commits form draken-platform's checks use. The guarantee is this literal subject, not acceptance by every project policy: a commitlint scope list without `shipcraft`, or a subject-length limit with many locks, can still refuse it, and closing commits already in history keep their old subject. No hook runs on the closing commit, as before; nothing in Shipcraft reads the subject, and a lock closed under either subject is judged by its state. A merge is judged against both parents, as in CI. A closed lock no longer restricts the tests.

### GREEN may add tests

New tests written during GREEN are not in the open lock. They become contract at the next RED, and CI runs them with the full suite.

### Support files are locked

The globs `init` writes include each language's support files, so GREEN cannot empty a test through a helper: `conftest.py` and test `fixtures/`/`helpers/` (Python), runner config and `__tests__/` (Node), `testdata/` (Go). They are plain globs in the same list as the tests.

### What the hook judges

- **Only the commit's content:** the index plus the tree's ignored files (dependencies, `.env`, generated files). An untracked, non-ignored file is left out, as in a clean clone. Changes outside the index never block and never change the result.
- **As a git checkout:** the copy it runs on has `HEAD`, history and `git ls-files`, like a clean clone.
- **Only the RED cases:** every locked file is protected by hash, but the hook executes only the test files that hold `failing_at_red` cases. Each suite's project-wide `check` runs in CI, not in the hook. An error outside the RED files does not block; CI reports it. When cases cannot be mapped to files, the hook runs all locked files but blocks only on RED cases.
- **The config:** a commit that changes `.shipcraft.toml` is validated, even with no lock open.

Edge cases are fixed by the acceptance battery (`acceptance/`).

### What CI re-checks

`shipcraft ci --base <ref>` checks every commit of `<base>..HEAD` against the same rules (hashes, lock state, config, integration files). On HEAD only, it runs `[build]`, each suite's `check`, then the full suite. It does not install dependencies. It also refuses a green suite with a lock still open (`lock-not-closed`: the hook was skipped) and a failing suite with no open cycle (`suite-red`: this is where an old test broken by GREEN shows up).

## 3. Commands

Each command is `shipcraft <command>`. Exit codes, unless the row says otherwise: `0` success, `1` refusal (section 7), `2` failure (`shipcraft` could not do its job, or invalid arguments; the message starts with `shipcraft: error:`).

| Command | What it does |
|---|---|
| `--version` | Prints `shipcraft <X.Y.Z> (<12-char commit>)`, in any folder. |
| (no arguments) | Prints usage, exit `0`. |
| `init [--lang python\|node\|go] [--github]` | Sets up the project (below). |
| `red [--redo]` | Runs the suite, requires assertion failures, writes an open lock; `--redo` rewrites the branch's open lock (item 46). Refuses `lock-open`, `red-already-passes`, `error-before-assertions`, `no-report`, `suite-without-tests`, `build-failed`. |
| `check [--commit-msg <file>]` | The hook: judges the commit against the open locks and closes them when the RED cases pass. With `--commit-msg` it judges the final index and writes a close mark instead of the lock (`mark-failed` if it cannot). |
| `close` | The `post-commit` half of the `commit-msg` route: if the mark matches the commit just made, adds one commit that only flips the lock to `closed`. On failure it changes nothing and says to rerun it. Always exits `0`. |
| `ci --base <ref> [--pr]` | CI (section 2). `--pr` allows the docs-only path (section 5). `ci` publishes no status (item 44). |
| `pr [--title <t>] [--body <file>]` | Pushes (`--force-with-lease`), opens or updates the PR, runs the layers, posts statuses and summary (section 5). Refuses `pr-not-on-branch`. Exit `0` is guaranteed only when every layer passed or is off. |
| `review` | Reviews local HEAD and prints the verdict; publishes nothing. Exit `0` on approval; refuses `review-changes-requested`, `review-error`, `review-off`. |
| `review --pr <n>` | Reviews any PR in an isolated copy and publishes `shipcraft/review` and a comment. Refuses `pr-from-fork`. |
| `merge <pr> [--no-review "<reason>"]` | The merge gate (section 5). Refuses `pr-not-open`, `merge-without-ci`, `merge-without-review`, `no-review-without-reason`. |
| `status` | Prints the layers, review agent, hook state, open locks, and one line with the real branch protection level. |
| `report [--json]` | Prints the flow's numbers per lock and per day from the run log (section 8, item 38). Reads only; never refuses. |

`init` writes no run-log row; `red` and `close` write one each (item 38).

### `init`

`init` decides everything before it asks or writes. A refusal leaves the tree as it was; a write that fails midway is rolled back.

- **Language:** `pyproject.toml` or `requirements*.txt` is Python (pytest), `package.json` with vitest or jest is Node, `go.mod` is Go (gotestsum); `--lang` overrides. Workspaces (`pnpm-workspace.yaml`, `package.json` `workspaces`, `go.work`) get one `[[suite]]` per package with tests.
- **Config:** writes `.shipcraft.toml` with the test command, globs, `check` (`tsc --noEmit` or `go vet`), `[execution]`, `[roles]`, `shipcraft_min` and, when it applies, `[build]`. Every `npx` it writes puts `--` before the tool's arguments.
- **Review:** `init` asks nothing. With an agent installed it writes `review = "local"` and the first one found in `[roles] review`, and says that the diff goes to that agent's provider and how to turn review off. With none installed, review is `off` and it says how to enable it.
- **AGENTS.md:** `init` creates `AGENTS.md` with a short block (marked `<!-- shipcraft -->`) telling agents the RED/GREEN workflow, or appends the block once to an existing file. A symlink or a failed write is left alone with a notice; it never fails the init. The block is the text below `AGENTS_BLOCK` in `nucleo/src/init.rs`.
- **Hook:** there is one route: `shipcraft check --commit-msg` in `commit-msg` and `shipcraft close` in `post-commit`, so the hook sees the index after formatters ran. `init` integrates only when it can prove which configuration runs the hook:
  - plain git: shipcraft's own `.git/hooks/commit-msg` and `.git/hooks/post-commit`;
  - lefthook: the two commands in the lefthook file's `commit-msg` and `post-commit` blocks;
  - husky 9 and the pre-commit framework: the two commands in their files.

  Anything `init` cannot prove (another tool's hook, `core.hooksPath` elsewhere, two hook managers, flow-style YAML, symlinks) refuses with `foreign-hook` and says where to add `shipcraft check` by hand. Edge cases are fixed by the acceptance battery (`acceptance/`).
- **GitHub:** `init` never writes a workflow. With `--github` it marks `shipcraft/ci` and, when review is on, `shipcraft/review` as required checks where GitHub offers branch protection.

## 4. Configuration

`.shipcraft.toml` lives at the project root.

### Single suite (top level)

| Key | Meaning |
|---|---|
| `shipcraft_min` | Minimum `shipcraft` version, `"X.Y"`. An older binary refuses (`shipcraft-min`). |
| `lang` | `python`, `node` or `go`. |
| `runner` | The runner name (`pytest`, `vitest`, `jest`, `gotestsum`). |
| `test_command` | The test command. `{junit}` is replaced by the report path. |
| `test_globs` | Test and support file globs. These files are locked. |
| `check` | Optional project-wide check (type check, vet). Runs in CI and at RED, never in the hook. A failing check refuses `no-report` with a reason that names the check (item 45). |
| `filter` | Who filters the hook's run (section 6). |

### Sections

| Key | Meaning | Default |
|---|---|---|
| `[[suite]] name` | Suite name. Prefixes its case ids. | the folder |
| `[[suite]] root` | Folder the command runs in. Globs are relative to it. | `.` |
| `[[suite]] command` | Test command, with `{junit}`. | required |
| `[[suite]] check` | Project-wide check for this suite. | none |
| `[[suite]] globs` | Test and support file globs. | `[]` |
| `[[suite]] filter` | `"shipcraft"` or `"command"` (section 6). | `"shipcraft"` |
| `[build] command` | Runs once at the root before the first suite (section 6). | none |
| `[execution] ci` | `local`, `github` or `off`. | `local` |
| `[execution] review` | `local` or `off`. `github` is reserved and refused (`review-github`). | `local` |
| `[execution] ci_timeout` | Local CI time limit, in seconds. | `1800` |
| `[execution] merge` | How `shipcraft merge` merges: `merge` (a merge commit) or `squash` (item 42). | `merge` |
| `[roles] review` | The review agent: `codex`, `claude` or `gemini`. | first one installed |
| `[review] spec` | Path of a project spec given to the reviewer. | none |
| `[review] timeout` | Review time limit, in seconds. | `1200` |
| `[machine] slots` | Concurrent local CI and review runs on this machine. | `1` |
| `[pr] warn_lines` | Product lines above which the PR summary suggests a split. | `500` |
| `[pr] shape_lines` | Fixes the file-size threshold of the shape warning (an integer above 0). | p90 of the project |

### Rules

- **The config is sealed by the lock:** its hash is in `files`, so nobody changes how the suite runs while a lock is open.
- **A PR is judged by the base branch's config** (`origin/<base>` as it is now), not its own. A PR cannot turn off its own review or change its own suite command.
- **A layer that is off is labeled:** its status is published as `success` with the description "off in .shipcraft.toml" on every PR, so the choice is visible, and the merge gate does not require it.
- **`shipcraft_min`:** an older binary refuses, in the hook and in CI, as it does a lock in an unknown format. Two machines never judge one commit differently without warning.
- **Validation:** unknown values, an absolute `root`, or a path or glob with `..` are refused. `.` and empty path components are normalized away.

### A failing `check` (item 45)

Whenever a run reaches a suite's `check` (in `red`, and in `ci` on HEAD), the check and then that suite's test command run, suite by suite in declaration order, as today. When the check's shell (`sh -c`, the same as for the test command) ends unsuccessfully, by a non-zero exit or a signal that shipcraft observes, the run stops and refuses `no-report`, as today, but with its own reason. Before item 45 the reason said the suite "did not write the JUnit report" and quoted stderr only. In draken-platform the first `red` failed this way: the check was `tsc --noEmit`, which writes its errors to stdout, so the reason said "exited with 2 without writing to stderr" and pointed at the report.

- **Reason:** `suite <name>: the check `<check>` failed (<how it ended>): <line>`. `<name>` is the suite's name as in the other `no-report` reasons. `<check>` is rendered on one line as the command is today. `<how it ended>` is worded as today (for example `exited with 2`, or the signal). `<line>` is the first non-blank line the check wrote on stderr, found by today's stderr scanner; if stderr has none, the first non-blank line on stdout, found by the same scanner (same decoding, trimming and length cut). Without either, the reason ends after the parenthesis, with no colon.
- **Why and Next:** Why says the suite is judged only after the project passes its check. Next says to run the check at the suite's root (naming the root and the command), and to fix what it reports, which can be the code or stub, or a missing tool or dependency; in `red` it ends with "then run `shipcraft red` again".
- **Unchanged:** the refusal code stays `no-report` and the run log records it as before; the check's output still passes through to shipcraft's stderr, as a best effort, and a failure to read or forward it does not change the verdict. A test command that writes no report keeps today's reason, stderr only. `build-failed` still comes first; the hook never runs `check`; docs-only CI and every refusal that comes before the suites run as before; a check that passes changes nothing; an outer timeout (`ci_timeout`) keeps its own outcome.

## 5. Layers and the gate

**Layer values are checked like `merge` (item 47).** `[execution] ci` and `[execution] review` are checked by the same reader, at the same point and in the same snapshots as `[execution] merge` (item 42): when the text of a `.shipcraft.toml` is turned into a config, after it parses as TOML, by every command and in every snapshot that does so today. Each must be a TOML string equal to `"local"`, `"github"` or `"off"` (exact, no trimming or case folding); an absent key takes its default. Any other value, a non-string included, refuses `execution-invalid`, naming the key and the value, checked in the order `ci`, `review`, `merge`. Nothing else moves: malformed TOML, a malformed `[execution]` table and a bad `ci_timeout` keep `config-invalid`; `review = "github"` passes this check and is refused `review-github` where it is today; a deleted config, `close` (which reads no config) and which snapshot each command judges by are unchanged. Before item 47 only `pr`, `merge` and `status` checked these values, so `shipcraft ci` with `ci = "foo"` passed and printed `CI ok.` with no last line (item 44).

### Where each layer runs

| Value | Meaning |
|---|---|
| `local` | Runs on this machine, started by `shipcraft pr`. No cloud runner, service or key. |
| `github` | Runs in the project's GitHub Actions, from the documented workflow. Nothing runs locally for that layer. |
| `off` | Does not run. The status is `success` with the description "off in .shipcraft.toml", and the gate does not require it. |

With `ci = "github"` and `review = "local"`, `shipcraft pr` waits for GitHub's `shipcraft/ci` on HEAD (up to `ci_timeout`) and reviews only on `success`.

### `shipcraft pr`

1. Pushes and opens or updates the PR. The PR body is the intent the reviewer receives.
2. Local CI runs `shipcraft ci --base <merge-base> --pr` and publishes `shipcraft/ci` on HEAD.
3. Only if CI passed, the review runs and publishes `shipcraft/review` and a comment.
4. Posts a summary: runs, refusals and time per layer, review tokens, product lines changed (tests, support files, pure renames, lockfiles and binaries excluded), a split hint above `warn_lines`, and a warning for each product file that grows past the project's p90 file size. Warnings never change exit codes or statuses.

**Shipcraft's own files are not product (item 50).** Product lines, the split hint and the shape warning leave out two kinds of path: `.shipcraft.toml` at the repository root, and every path that starts with `.shipcraft/` from the repository root. Paths are the repository-relative paths git prints, matched literally byte for byte; the working tree, the current directory and suite roots play no part, so `packages/web/.shipcraft.toml` is still product. Classification uses the HEAD path, as in item 24, so a file renamed into `.shipcraft/` leaves the count: the `.shipcraft/` folder is reserved for Shipcraft. The shape warning drops these paths from its candidates and from its p90 population before reading any blob and before the 20-file minimum, so an excluded blob that cannot be read never makes the shape unmeasured; an explicit `[pr] shape_lines` still applies. The run log's `product_lines` and `shape_warnings` carry the new values; old rows are not rewritten. Hook integration files (item 40 protects them for docs-only PRs) stay product here. Like every warning, this changes no exit code, status or verdict.

Wrong-measurement note: since 2.0.0 (items 11 and 24) each lock counted as product, and a lock grows with the number of cases, not with the change. Found in draken-platform, where every PR from #18 to #23 got the split hint because of its locks (PR #23: 655 of its 672 "product lines" were the lock) and PR #24 got a shape warning naming its own lock. The spec review of item 11 should have caught it: its exclusion list named package managers' lockfiles and never Shipcraft's.

**`ci` publishes no status (item 44).** `shipcraft ci` never publishes a status, with or without `--pr`, because it cannot prove that its base is the PR's base or that it ran on the pushed HEAD. An executed CI result reaches `shipcraft/ci` only through `shipcraft pr` (local CI) or the documented GitHub workflow; `pr` still publishes the off-layer status of section 4. In draken-platform#18 an agent ran `shipcraft ci --base origin/main --pr` and `shipcraft review --pr 18` by hand, read "CI ok", and `shipcraft merge` refused for lack of `shipcraft/ci`.

So whenever `ci` exits `0` (suites green, docs only, an empty range, or an accepted open RED cycle), the line `shipcraft: CI ok.` is followed on stdout by exactly one more line, the last, with no blank line, chosen by the `ci` value of the config this run judges by:

| `ci` | Last line |
|---|---|
| `local` | `shipcraft: ci publishes no status; shipcraft pr runs CI and publishes shipcraft/ci on HEAD.` |
| `github` | `shipcraft: ci publishes no status; the GitHub workflow publishes shipcraft/ci on HEAD.` |
| `off` | `shipcraft: ci publishes no status; with ci = "off", shipcraft pr publishes shipcraft/ci as off.` |

Nothing else changes: refusals and errors print no such line, and exit codes, stderr, the run log and every status stay as they are. Inside `shipcraft pr` the line is the last of the CI child's output; `pr`'s own lines follow as before.

**Docs-only PRs (item 40).** With `--pr`, a PR is docs only when the diff from the merge-base to HEAD is not empty and every entry is a regular file added, modified or deleted (a rename counts as both paths; no link, submodule, mode or type change) whose path is a `*.md` file at the repository root or anything under the top-level `docs/`, and none of those paths is protected (a test or support file of any suite, `.shipcraft.toml`, `.shipcraft/`, hook integration files), and no lock is open at HEAD, and every suite's `root` is a chain of folders of HEAD's tree (no link, file, submodule, missing path, `..` or absolute root; without that, shipcraft cannot tell which `.md` a suite reads as a test). Then CI still checks every commit, skips `[build]`, `check` and the suites, and prints exactly one line, `docs only: the suites do not run`. Any doubt runs everything. There is no config: a `.md` outside the root and `docs/` (for example one embedded in the code) always runs the suites. Every `ci` row of the run log has `docs_only` (`true` or `false`).

### The review

- **A separate session:** always a fresh session of the `[roles] review` agent, without the author's context. It is a different agent even with the same model. The brief is built into the binary and carries the project spec (`[review] spec`), the PR body and the raw diff.
- **The verdict is the first line:** `APPROVE at <sha>` or `CHANGES REQUESTED at <sha>`, then `Blocking: N`. Anything else, including a blank line first or text after the sha, is malformed. `APPROVE` gives `success`, `CHANGES REQUESTED` gives `failure`.
- **Fail closed:** timeout, quota, a non-zero exit, a reviewer refusal or a malformed verdict give `error` with the reason, never approval. The reviewer runs once per `shipcraft pr` and is not retried automatically. A `pending` status older than the timeout is redone by the next `shipcraft pr`.
- **Reuse:** a verdict is reused when every changed file has the same versions on both sides. The key is the SHA-256 of `git diff --raw -z --no-abbrev --no-renames --ignore-submodules=none <base> <head>`. If the key cannot be computed, the review runs.

### The merge gate

`shipcraft merge <pr>` merges only with `shipcraft/ci` and `shipcraft/review` at `success` on the PR's current HEAD; an off layer is not required. `--no-review "<reason>"` waives the review, never CI, and records the reason in the PR and the run log. Where GitHub offers branch protection, `init --github` makes both statuses required; otherwise `shipcraft merge` is the gate, and `shipcraft status` says so. `shipcraft ci` on the default branch warns, with exit `0`, about each merge that bypassed the gate, and records it as an `escape`.

**Squash merge (item 42).** Three points:

1. **The key.** `[execution] merge` is `"merge"` (a merge commit, the default when the key is absent) or `"squash"`. Any other value, a non-string included, refuses `execution-invalid` wherever the config is read, like `[execution] ci`. `shipcraft merge` reads it from the same config as the gate reads which layers are on (the PR base's `.shipcraft.toml`), so the PR cannot change how it is merged.
2. **The merge.** With `"squash"`, `shipcraft merge` checks the same gate, posts the same `--no-review` comment and then runs `gh pr merge <pr> --squash` without a title or body of its own: the repository's GitHub settings decide them. The `merge` row is written only after `gh` succeeds, as today, with the same fields (`commit` is still the PR head) plus `method`: `"merge"` or `"squash"`. Refusals before the merge write no `method`. Older rows without `method` stay valid for every reader.
3. **The default branch after a squash.** A squash puts the PR on the base as one commit, so a lock that the PR opened and closed arrives there already closed, with no commit holding it open. `shipcraft ci` on the default branch accepts that commit when GitHub reports it as the `merge_commit_sha` of a PR (`commits/<sha>/pulls`, the reader the escape check already uses) that went through the gate as the escape check judges it: its head had every required status in `success`, or the review status was waived by the `--no-review` comment while `shipcraft/ci` was in `success`; the locked cases are not run at that commit. In any other case, including when GitHub cannot be read, the closed lock is refused `lock-edited` as today. On a PR branch nothing changes: a lock still has to be opened by a RED commit and closed by a later one.

What squash gives up: the base's history keeps no RED commit. The PR's `shipcraft ci` checked every PR commit's locks, hashes and config, and ran the suite on the PR head only (section 2); after the squash only that evidence and the run log remain.

The escape check of `shipcraft ci` on the default branch reads every first-parent commit of `<base>..HEAD` (`git rev-list --first-parent`), not only merge commits, whatever the config says. A commit GitHub reports as a PR's `merge_commit_sha` is judged by the statuses and the `--no-review` comment exactly as before, whether it was merged by `shipcraft merge` or by GitHub's button; so a PR squashed through the button without the gate is now warned of and recorded as an `escape`. A commit no PR merged (a direct push) is not judged, as before. If `gh` fails, the check prints the warning it prints today and stops; a missing `<base>` (a shallow clone) skips the check, as today.

Known limits kept by item 42: `shipcraft merge` does not pin the PR head it checked (a push between the check and the merge lands unchecked); a `--no-review` comment exempts the PR's later heads too; and the merged tree is not tested when the base moved after the PR's CI. Each applies to both methods.

### Fork PRs

Fork PRs are refused (`pr-from-fork`): code from outside the project is outside the good-faith model.

### The per-machine queue

Local CI and local review share one queue per machine, across all projects, with at most `[machine] slots` queued runs at once (default 1; the machine file `$XDG_CONFIG_HOME/shipcraft/config.toml` wins over the project). A waiting run prints its position and what is running. A run that exceeds its timeout (`[review] timeout`, `[execution] ci_timeout`) is stopped, its status becomes `error` and the slot is freed. The hook does not queue.

**Docs-only PRs skip the queue (item 41).** With `[execution] ci = "local"`, `shipcraft pr` applies item 40's rule to the base tip and HEAD it passes to its CI, before it asks for a slot. If the PR is docs only, its local CI starts without touching the queue: it takes no slot, waits for none and prints no queue line, and `ci_timeout` still applies. In every other case, including when the rule cannot be applied, the CI queues as before. This judgment only decides whether to queue. The CI child still judges the PR itself and checks every commit, as item 40 says, and its verdict, status and run-log rows are unchanged. The review queues as before, docs only or not. The `[machine] slots` cap counts queued runs only, so one of these CI runs can run beside a queued run. Every `pr` row of the run log has `queue_secs`. It is a non-negative integer: the seconds from asking for the CI slot until getting it or failing, rounded down. It is `0` when the CI skipped the queue, and `null` when no local CI was attempted (`ci = "github"` or `"off"`). The review's wait is not counted.

## 6. Monorepo and runners

### `[[suite]]`

Each suite's `command` runs in its `root`, and its globs are relative to `root`. Case ids in the lock are prefixed with the suite name (`<name>:`). The top-level form counts as one suite. `red` refuses a suite that has failing cases but locks no file (`suite-without-tests`), so a wrong root never opens an empty lock.

### Any runner: the RED cases as files

`shipcraft` filters pytest, vitest, jest and Go itself. For any runner, the hook gives each suite command two variables, each the absolute path of a temporary file with NUL-terminated entries, deduplicated, in byte order:

- `SHIPCRAFT_CASES`: the RED case ids of that run (`classname::name`, or `name`), without the suite prefix;
- `SHIPCRAFT_FILES`: the absolute paths of the RED test files, set only when every RED case maps to a file.

A variable is set only when its list is not empty. Every other command `shipcraft` runs gets neither, even when inherited, so a stale value never narrows a suite. The command decides whether to use them. A RED case it does not select is `case-missing`.

### `filter`

`filter = "shipcraft"` (the default) lets `shipcraft` add its own filter for the runners it knows. `filter = "command"` runs the command as written. The two never stack.

### `[build]` for TypeScript project references

`[build] command` runs once at the root before the first suite, in `red` and in `ci` on a clean tree or fresh clone. CI builds only HEAD. The build never runs on the hook's copy; the hook uses the build output already in the tree. `ci` with `[build]` on a dirty tree refuses (`build-dirty-tree`), and a failing build refuses (`build-failed`) before any suite.

`init` writes `[build]` when a tracked `tsconfig.json` at the root or in a workspace package has `references` or `composite: true`: `npx --no -- tsc -b` followed by those folders, alphabetically. It runs the command first and writes it only if it succeeds; otherwise it says why and still exits `0`.

## 7. Refusals

Every refusal ends with three lines, then exit code `1`:

```
shipcraft refused: <what happened>
Why: <the practice behind the rule>
Next: <how to go on>
```

Output from a project command that `shipcraft` passes through always ends before the refusal starts on a new line. Each refusal has a code, recorded in the run log.

| Code | Meaning |
|---|---|
| `build-dirty-tree` | `ci` with `[build]` on a tree with changes outside HEAD. |
| `build-failed` | The `[build]` command failed. No suite ran. |
| `case-broke` | A case the hook ran, which passed at RED, now fails. |
| `case-missing` | A locked case is missing from the report. |
| `case-skipped` | A locked case was skipped. |
| `config-changed` | `.shipcraft.toml` changed with a lock open. |
| `config-invalid` | `.shipcraft.toml` is not a valid config. |
| `error-before-assertions` | At RED, the suite errored before any assertion (import, collection). |
| `execution-invalid` | An `[execution] ci`, `review` or `merge` value `shipcraft` does not know (items 42 and 47). |
| `foreign-hook` | `init` cannot prove which hook runs, or another tool owns it. |
| `lang-multiple` | `init` found more than one language. |
| `lang-unknown` | `--lang` names an unsupported language. |
| `lang-unrecognized` | `init` found no known project file. |
| `hook-config-changed` | A hook integration file (lefthook, husky, pre-commit) changed with a lock open. |
| `lock-closed-red` | A lock arrives closed while locked cases still fail. |
| `lock-deleted` | An open lock was deleted. |
| `lock-edited` | A lock was edited outside `shipcraft` (the seal does not match). |
| `lock-format` | A lock in a format this binary does not know. |
| `lock-not-closed` | The locked cases pass at HEAD, but the lock is still open. |
| `lock-open` | `red` on a branch that already has an open lock. |
| `locked-file-deleted` | A locked file was deleted. |
| `mark-failed` | The `commit-msg` route could not write its close mark. |
| `merge-without-ci` | No successful `shipcraft/ci` on the PR's HEAD. |
| `merge-without-review` | No successful `shipcraft/review` on the PR's HEAD. |
| `no-config` | No `.shipcraft.toml` at the project root. |
| `no-git` | Not inside a git repository. |
| `no-report` | The suite wrote no JUnit report, or its `check` failed before the suite ran. |
| `no-review-without-reason` | `--no-review` without a reason. |
| `pr-from-fork` | The PR comes from a fork. |
| `pr-not-on-branch` | `pr` run without a working branch. |
| `pr-not-open` | `merge` on a PR that is not open. |
| `red-already-passes` | The suite passes at RED, so there is nothing to lock. |
| `redo-drops-case` | A redo would drop a case of the open lock. |
| `redo-mixed` | A redo commit changes a file neither lock protects, the config or a hook integration file. |
| `redo-write-failed` | `red --redo` could not write the new lock; the old one is left as it was. |
| `redo-without-lock` | `red --redo` with no open lock at HEAD. |
| `review-changes-requested` | The reviewer requested changes. |
| `review-error` | The reviewer gave no well-formed verdict. |
| `review-github` | `review = "github"` is reserved and not available. |
| `review-off` | `review` was asked for, but review is off in the base config. |
| `shipcraft-min` | The config requires a newer `shipcraft`. |
| `suite-red` | The suite fails at HEAD with no open cycle. |
| `suite-without-tests` | At RED, a suite with failing cases matches no test file. |
| `test-changed` | A locked test changed after RED. |

## 8. Measurement

Each hook, CI, review and merge run appends one JSON line to `.git/shipcraft/runs.jsonl`. It is local only: never versioned or pushed, shared by all worktrees. Measuring never breaks the command it measures.

| Field | Content |
|---|---|
| `layer` | `hook`, `ci`, `review` or `merge`. |
| `result` | `passed`, `refused` or `error`. |
| `code` | The refusal code, or empty. |
| `secs` | Duration in seconds. |
| `at` | Unix time of the run. |
| `branch`, `commit` | Where it ran. |
| `reason` | The first refusal line, or the `--no-review` reason. |
| `product_lines`, `shape_warnings` | On rows from `shipcraft pr`: product lines, and files that got a shape warning (`null` when there is no threshold). |
| `docs_only` | On `ci` rows: whether the PR was judged docs only (item 40). |
| `queue_secs` | On `pr` rows: seconds the local CI waited for a slot, rounded down; `0` when it skipped the queue, `null` without local CI (item 41). |
| `tokens`, `agent`, `pr`, `diff_sha256` | On `review` rows: tokens used (or `null`), the agent, the PR, and the reuse key. |
| `method` | On `merge` rows written by `shipcraft merge`: `merge` or `squash` (item 42). |
| `escape` | `true` on a merge that skipped the gate. |

Besides the refusal codes, `code` can hold run outcomes that are not refusals: `changes-requested` and `reviewer-no-verdict` (review), `timed-out` (local CI), `no-review` and `escape` (merge), and `error` for a failure.

`shipcraft pr` posts the branch's summary from this file.

### Measuring the flow (item 38)

Time to main is Shipcraft's main number. It must come from what Shipcraft recorded, not from agents or prose, and not from git history: squash, rebase, fast-forward, deleted or reused branches and two locks on one branch each break a reconstruction from history.

1. **One event per step, recorded when it happens.** Besides today's rows, `red` (a lock written, or a refusal) and `close` (the commit that closes a lock exists: post-commit, or `shipcraft close`; never a pre-commit a later hook may abort) write a row. Every row carries `lock` (the lock id, or empty). `pr`, `merge`, and the `ci` and `review` rows run for a PR carry `locks`: the locks whose files changed between the PR's base and head, read from the PR's own diff (the files `shipcraft merge` already reads). The lock id is the item's identity: no branch name, author time or ancestry is read. A `hook` row with no open lock counts only in the hook totals. Recording is best effort: a failed append changes no exit code; the step it lost shows as not observed.
2. **`shipcraft report` reads only the run log** (no git history, no network, no agent) and prints one row per lock:
   - the times of `red`, `close` and `merge`, and the durations RED to close, close to merge, and RED to merge. A step's time is that of its first `passed` row; refusals and errors are counted but never set a time. A `merge` counts only when its base is the default branch. A lock whose `merge` passed is merged even with earlier steps missing: those durations are empty and the row says the steps were not observed here. A lock not yet merged is marked open; elapsed times are never filled in;
   - the reviews by result and whether the first one approved. A review that ended in `error` (timeout, quota) is counted apart and is not the first review; a reused verdict is recorded with `reused: true` and is not a new round;
   - the waiting: from the last `ci` that passed for the lock to its `merge`;
   - the hook and `ci` count, p50 and p90, and refusals by code.

   Then one summary per UTC day of the `merge` row: merged locks, the medians of RED to merge and of waiting, and the share approved on the first review.
3. **`shipcraft report --json`** prints one JSON object per line with a `kind`: first `meta` (the time of the first and last row, `null` with none), then `lock`, `day`, and `gap` (a line of the log that does not read, with its line number; the rest goes on). Empty values are `null`.

**Readings fixed after the RED (2026-10-26):**
- *Fields.* The `merge` row carries `base` and `default_branch` (branch names); it counts only when they are equal. Times are Unix seconds and durations are seconds. `--json` uses: `meta` with `first_at`, `last_at`; `lock` with `lock`, `state` (`open` or `merged`), `red_at`, `close_at`, `merge_at`, `red_to_close`, `close_to_merge`, `red_to_merge`, `waiting`, `unobserved` (the steps not seen), `reviews` (`passed`, `refused`, `error` counts), `first_review_approved`, `refusals` (counts by code) and `errors`; `hook` and `ci` with `count`, `p50`, `p90`, `refusals`; `day` with `day`, `merged_locks`, `red_to_merge_median`, `waiting_median`, `first_review_approved_share`; `gap` with `line` and `reason`.
- *First.* A step's first `passed` is the one with the earliest `at`; equal times keep file order. An open lock still shows every duration whose two ends exist.
- *Percentiles.* p50 and every median are the median (the mean of the two middle values for an even count); p90 is nearest-rank. Ten samples 1..10 give p50 5.5 and p90 9.
- *Reviews.* The first review is the first `review` row that is a verdict (approved or changes requested), not `error` and not `reused`. The day's share is over the merged locks that have a first review.
- *Waiting* is from the last `ci` that passed for the lock before its `merge` to that `merge`.
- *Rows per lock.* A PR that delivers several locks gives each lock its own `lock` row with the PR's `pr` and `merge` times.
- *Ignored.* Rows with `escape: true` (a merge that skipped the gate) and blank lines are ignored. A trailing CR and a BOM at the start of the file are stripped; any other line that does not read as a JSON object is a `gap`.
- *Run log check.* The run-log fields above (`red`, `close` and `pr` rows, `lock`, `locks`, `base`, `default_branch`, `reused`) are valid rows for every reader of the log, including the battery's item 10 check.

The log covers what ran on this machine, and the report's first line says so, with the time of the first and last row. Reviews or CI that ran elsewhere (GitHub, another clone) are not guessed. Escapes stay out of this item.

## 9. Known limits

These gaps are known and open. The ones marked *CI* are caught by `shipcraft ci`, so they cost a round trip, not an escape.

- With `[build]`, the `tsconfig.json` files are not locked, so a GREEN can change the build graph while a lock is open.
- On a pnpm workspace, the hook's copy resolves internal packages to the working tree, so the hook can judge stale code (*CI*).
- `git commit --amend` on top of the closing commit passes the hook (*CI*).
- `git rebase --continue` skips `commit-msg`, so the `commit-msg` route does not judge those commits (*CI*).

## 10. Out of scope

- `review = "github"` (reserved).
- Fork PRs.
- Git hosts other than GitHub.
- Windows.
- Running the build on the hook's copy.
- Token limits for the review.
- Agent identity per role: who writes RED or GREEN is the orchestrator's choice. The lock is the mechanical guarantee.
- A separate intent file: the PR body is the intent.
- Shadow review, and running the review in parallel with CI.

## 11. Versioning

`shipcraft` follows semantic versioning. This contract is **2.10.0**. A change that breaks a config, a lock, a command or a refusal code raises the major version. The lock carries its own `format` version. A new lock format that a binary writes while still reading the previous one is a minor change, since no lock already written stops being valid (lock format 3, item 43, in 2.3.0). `shipcraft_min` lets a project require a minimum binary, and `init` writes the running binary's `major.minor`. Releases ship one archive per macOS target (`aarch64`, `x86_64`), each holding only the `shipcraft` binary, with a `SHA256SUMS` file. On other platforms, build from source with `cargo install --path nucleo`.
