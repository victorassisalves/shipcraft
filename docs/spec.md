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
| `files` | The SHA-256 of each locked file (tests, support files, `.shipcraft.toml`), by path. |
| `cases` | The cases the report showed at RED, skipped ones excluded. |
| `failing_at_red` | The cases that failed at RED. |
| `seal` | SHA-256 of the lock with an empty seal. It catches hand edits; it is not a signature. |

The RED is a commit: the one that adds the open lock, with the tests as locked and the suite failing. If a lock file is in the tree but outside the commit, the hook warns with the `git add` command; the warning never changes the verdict. One cycle at a time per branch: a new `red` is refused while the branch has an open lock (`lock-open`).

### What is refused while a lock is open

A commit is refused if:

- a locked file changed (`test-changed`) or was deleted (`locked-file-deleted`);
- `.shipcraft.toml` changed (`config-changed`);
- a hook integration file changed (`hook-config-changed`: lefthook config, `.pre-commit-config.yaml`, `.husky/commit-msg`, `.husky/post-commit`);
- a locked case is missing from the report (`case-missing`) or was skipped (`case-skipped`);
- a case the hook ran fails, even one that passed at RED (`case-broke`): a known failure is never ignored;
- the lock was deleted (`lock-deleted`) or edited outside `shipcraft` (`lock-edited`);
- the lock arrives `closed` while locked cases still fail (`lock-closed-red`).

Intermediate commits with the suite still red are accepted. When it is safe, the `Next:` line of a lock refusal gives the exact `git restore` command.

### The lock closes by itself

The first commit after RED in which every case in `failing_at_red` passes, none skipped or missing, closes the lock. The `commit-msg` hook judges the commit and the `post-commit` hook writes `closed` in a separate closing commit right after it (see `init`). A merge is judged against both parents, as in CI. A closed lock no longer restricts the tests.

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
| `red` | Runs the suite, requires assertion failures, writes an open lock. Refuses `lock-open`, `red-already-passes`, `error-before-assertions`, `no-report`, `suite-without-tests`, `build-failed`. |
| `check [--commit-msg <file>]` | The hook: judges the commit against the open locks and closes them when the RED cases pass. With `--commit-msg` it judges the final index and writes a close mark instead of the lock (`mark-failed` if it cannot). |
| `close` | The `post-commit` half of the `commit-msg` route: if the mark matches the commit just made, adds one commit that only flips the lock to `closed`. On failure it changes nothing and says to rerun it. Always exits `0`. |
| `ci --base <ref>` | CI (section 2). `--pr` is still accepted and changes nothing. |
| `pr [--title <t>] [--body <file>]` | Pushes (`--force-with-lease`), opens or updates the PR, runs the layers, posts statuses and summary (section 5). Refuses `pr-not-on-branch`. Exit `0` is guaranteed only when every layer passed or is off. |
| `review` | Reviews local HEAD and prints the verdict; publishes nothing. Exit `0` on approval; refuses `review-changes-requested`, `review-error`, `review-off`. |
| `review --pr <n>` | Reviews any PR in an isolated copy and publishes `shipcraft/review` and a comment. Refuses `pr-from-fork`. |
| `merge <pr> [--no-review "<reason>"]` | The merge gate (section 5). Refuses `pr-not-open`, `merge-without-ci`, `merge-without-review`, `no-review-without-reason`. |
| `status` | Prints the layers, review agent, hook state, open locks, and one line with the real branch protection level. |

`init`, `red` and `close` write no run-log row.

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
| `check` | Optional project-wide check (type check, vet). Runs in CI and at RED, never in the hook. |
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

## 5. Layers and the gate

### Where each layer runs

| Value | Meaning |
|---|---|
| `local` | Runs on this machine, started by `shipcraft pr`. No cloud runner, service or key. |
| `github` | Runs in the project's GitHub Actions, from the documented workflow. Nothing runs locally for that layer. |
| `off` | Does not run. The status is `success` with the description "off in .shipcraft.toml", and the gate does not require it. |

With `ci = "github"` and `review = "local"`, `shipcraft pr` waits for GitHub's `shipcraft/ci` on HEAD (up to `ci_timeout`) and reviews only on `success`.

### `shipcraft pr`

1. Pushes and opens or updates the PR. The PR body is the intent the reviewer receives.
2. Local CI runs `shipcraft ci --base <merge-base>` and publishes `shipcraft/ci` on HEAD.
3. Only if CI passed, the review runs and publishes `shipcraft/review` and a comment.
4. Posts a summary: runs, refusals and time per layer, review tokens, product lines changed (tests, support files, pure renames, lockfiles and binaries excluded), a split hint above `warn_lines`, and a warning for each product file that grows past the project's p90 file size. Warnings never change exit codes or statuses.

### The review

- **A separate session:** always a fresh session of the `[roles] review` agent, without the author's context. It is a different agent even with the same model. The brief is built into the binary and carries the project spec (`[review] spec`), the PR body and the raw diff.
- **The verdict is the first line:** `APPROVE at <sha>` or `CHANGES REQUESTED at <sha>`, then `Blocking: N`. Anything else, including a blank line first or text after the sha, is malformed. `APPROVE` gives `success`, `CHANGES REQUESTED` gives `failure`.
- **Fail closed:** timeout, quota, a non-zero exit, a reviewer refusal or a malformed verdict give `error` with the reason, never approval. The reviewer runs once per `shipcraft pr` and is not retried automatically. A `pending` status older than the timeout is redone by the next `shipcraft pr`.
- **Reuse:** a verdict is reused when every changed file has the same versions on both sides. The key is the SHA-256 of `git diff --raw -z --no-abbrev --no-renames --ignore-submodules=none <base> <head>`. If the key cannot be computed, the review runs.

### The merge gate

`shipcraft merge <pr>` merges only with `shipcraft/ci` and `shipcraft/review` at `success` on the PR's current HEAD; an off layer is not required. `--no-review "<reason>"` waives the review, never CI, and records the reason in the PR and the run log. Where GitHub offers branch protection, `init --github` makes both statuses required; otherwise `shipcraft merge` is the gate, and `shipcraft status` says so. `shipcraft ci` on the default branch warns, with exit `0`, about each merge that bypassed the gate, and records it as an `escape`.

### Fork PRs

Fork PRs are refused (`pr-from-fork`): code from outside the project is outside the good-faith model.

### The per-machine queue

Local CI and local review share one queue per machine, across all projects, with at most `[machine] slots` runs at once (default 1; the machine file `$XDG_CONFIG_HOME/shipcraft/config.toml` wins over the project). A waiting run prints its position and what is running. A run that exceeds its timeout (`[review] timeout`, `[execution] ci_timeout`) is stopped, its status becomes `error` and the slot is freed. The hook does not queue.

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
| `execution-invalid` | An `[execution]` value `shipcraft` does not know. |
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
| `no-report` | The suite wrote no JUnit report. |
| `no-review-without-reason` | `--no-review` without a reason. |
| `pr-from-fork` | The PR comes from a fork. |
| `pr-not-on-branch` | `pr` run without a working branch. |
| `pr-not-open` | `merge` on a PR that is not open. |
| `red-already-passes` | The suite passes at RED, so there is nothing to lock. |
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
| `tokens`, `agent`, `pr`, `diff_sha256` | On `review` rows: tokens used (or `null`), the agent, the PR, and the reuse key. |
| `escape` | `true` on a merge that skipped the gate. |

Besides the refusal codes, `code` can hold run outcomes that are not refusals: `changes-requested` and `reviewer-no-verdict` (review), `timed-out` (local CI), `no-review` and `escape` (merge), and `error` for a failure.

`shipcraft pr` posts the branch's summary from this file.

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

`shipcraft` follows semantic versioning. This contract is **2.0.0**. A change that breaks a config, a lock, a command or a refusal code raises the major version. The lock carries its own `format` version. `shipcraft_min` lets a project require a minimum binary, and `init` writes the running binary's `major.minor`. Releases ship one archive per macOS target (`aarch64`, `x86_64`), each holding only the `shipcraft` binary, with a `SHA256SUMS` file. On other platforms, build from source with `cargo install --path nucleo`.
