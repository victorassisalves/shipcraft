# Shipcraft 2.0: the contract

This is the public contract of `shipcraft`: what it guarantees and what each command, config key and refusal means. The acceptance battery in `acceptance/` is the executable contract and fixes the edge cases this text leaves out.

## 1. Guarantee and threat model

**The guarantee.** A test written at RED stays the judge until it passes. The agent that writes the code (the GREEN) cannot make the suite pass by changing, deleting or skipping a locked test, its support files, or the config that says how the suite runs. The git hook checks this on every commit. CI repeats every check, so a commit made with `--no-verify` or an edited hook is caught there. With `[execution] suite_checks` (item 62), CI is `shipcraft/ci`, which re-checks every commit, plus the named GitHub checks, which run the suite; what that leaves uncaught is listed there.

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
| `failing_at_red` | The cases that failed at RED, less those that passed in `red`'s second run (item 53). |
| `seal` | SHA-256 of the lock with an empty seal. It catches hand edits; it is not a signature. |

**Lock format 3 (item 43).** `red` writes format 3, where every `files` value (tests, support files, runner configs, `.shipcraft.toml`) carries the `sha256:` prefix. In format 2 the value was the bare hex digest, and secret scanners read a 64-character hex value after a path that names `auth`, `access`, `token` or `key` as a leaked credential: gitleaks 8.30.1 with its default rules reported `generic-api-key` twice on one lock in draken-platform#18, and zero on the same lock with the prefix. Paths, case ids and `seal` are unchanged.

- **The seal** is computed as in format 2: SHA-256 of the lock's compact JSON with an empty `seal`, fields in their fixed order and `files` sorted by path, with the `files` values exactly as written (prefixed in format 3). It does not depend on the file's whitespace or key order.
- **Format belongs to each lock.** A binary that writes format 3 reads format 2 and 3 locks, each by its own `format`, at every snapshot it reads: the hook's parent and index, every commit CI walks, both parents of a merge. A format 2 lock is judged as before: its bare values are compared to the digest of the file's bytes. Repositories are never migrated; a tree can hold locks of both formats.
- **Closing keeps the format.** Every path that closes a lock (`close` after the commit, and `check` when it closes) changes only `state` and `seal`; `format` and every `files` value stay as they were. A format 2 lock closes as format 2.
- **Value syntax is part of reading a lock.** A format 3 lock whose `files` value does not match `^sha256:[0-9a-f]{64}$` exactly (no trimming, no case folding), or a format 2 lock with a value that is not 64 lowercase hex characters, is not a valid lock, whatever its seal, state or the files' contents: it is refused like a hand edit (`lock-edited`), where a hand edit is refused today. A lock that is not JSON or not a lock object is handled as today.
- **Versions.** The item raises the binary to 2.3.0, so `init` writes `shipcraft_min = "2.3"`. `red` does not change an existing config: a project with `shipcraft_min = "2.1"` keeps it. A binary older than 2.3 refuses by the first thing it does not support: `shipcraft-min` when the config asks for 2.3, else `lock-format` on a format 3 lock.

The RED is a commit: the one that adds the open lock, with the tests as locked and the suite failing. If a lock file is in the tree but outside the commit, the hook warns with the `git add` command; the warning never changes the verdict. The empty `.shipcraft/locks/.gitkeep` that `init` writes is never warned about (item 48): before item 48 every commit warned that it was outside the commit even when it was committed, because an empty blob in the index also marks `git add -N` (draken-platform, every commit since the install). The exception is only that exact path at the repository root, whoever created it, in any git state (untracked, ignored, `git add -N`, staged, committed), and only while it is empty as the warning's own reader sees it (the effective index's blob for an index entry, a regular file of zero bytes in the tree otherwise); a non-empty or non-regular entry there, and every other path, warn as before. It is dropped before the warnings are ordered and counted, so it takes no line and is not in "and N more". A failed query still prints the one `could not read` warning. One cycle at a time per branch: a new `red` is refused while the branch has an open lock (`lock-open`).

### A failing group is not a case (item 52)

vitest reports a failure in a `describe` block's `beforeAll` hook (an error or its timeout) as a test case named after the block (`a.spec.ts::licensing store`), and reports every test of the block skipped (`a.spec.ts::licensing store > one`). A run where the hook succeeds never reports the block's name, only its tests. Locked as a RED case, the block's id is `case-missing` in every later run, so the RED commit can never pass, and `red --redo` cannot drop it (`redo-drops-case`).

- **What is a group failure.** It is judged on each JUnit document a suite run produces, before reports of different suites or commands are merged, on the `<testcase>` elements' `classname` and `name` attributes as the existing report reader decodes them (XML unescaping once, no trimming; a missing `classname` is empty), after the reader's handling of duplicates and its outcome per case. A case with classname `C` and name `N` is a group failure when all of these hold: its outcome is failed (not error, not skipped); `C` is not empty; the same document holds at least one case with the same `C` (byte for byte) whose name starts with `N` followed by ` > ` (vitest's separator between a block and what it holds), byte for byte; and every such case is skipped. A real test that fails while a block of the same name ran its tests is not a group failure.
- **`red` and `red --redo` refuse it.** When any case that would go into `failing_at_red` is a group failure, `red` refuses `group-failed` and creates no lock; `--redo` refuses the same way and leaves the lock file as it was. The refusal names the group ids (with their suite prefix, as `failing_at_red` writes them) in byte order, with the same list formatting as other refusals that name cases. The check runs where `red-already-passes` is judged today, just before it: after every suite has run and been read, and after `error-before-assertions`, `no-report`, `[build]` and `check` refusals, which keep their precedence; for `--redo`, before `redo-drops-case`. The run log row is written as for any refusal (`redo: true` for `--redo`). What the build, `check` and suite commands wrote is left as for any refusal. The `Why:` says the block's hook failed before its tests ran, so the block is reported as a case under a name a passing run never reports, and a lock on it could never close. The `Next:` says to fix the block's hook (or move any assertion it makes into a test of the block), or, if it failed under load or by chance, to run the same command again.
- **Unchanged.** The hook and CI judge reports as today (a failed case is a failed case). Locks already written are read as before: a lock that holds a group id stays `case-missing`, and the way out is the one before item 52 (rewrite the branch's history). The report reader, `cases` and the other refusals are unchanged.
- **Known limits.** Only vitest's ` > ` naming with skipped children is recognized. Not caught, and locked as before: an `afterAll` failure (its block's tests already ran); a reporter that omits skipped cases; a block whose own tests were all skipped for another reason (`.skip`) while a real test with the block's name fails, which is refused although it is a real test (run with the block's tests enabled, or rename one). Another runner whose names happen to have the same shape is judged by the same rule.

Wrong-measurement note: since 2.0.0 (item 13, the first lock of node suites). Found on the Forge in POC-019 (2.11.0 probe): `red` locked `licence-store.spec.ts::licensing licence-store (SPEC-037 …)`, a block whose setup failed under load (load average 8 to 11), and the hook refused the RED commit `case-missing` while all 55 of the block's tests passed. The battery had no case where a block's hook fails.

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

### `red` confirms its failures (item 53)

Before item 53, `red` wrote every case that failed in its one run into `failing_at_red`. A case that failed by chance (a flaky test under load) became part of the contract: the GREEN had to make it pass, and a case whose id the next run does not report (a generated parameter, a timeout at block level) made the RED unpassable. On the Forge (POC-019, 2.11.0 probe, 15,774 cases, load average 8 to 11) a RED with one intended failing test locked four; the three others were in files the RED did not touch.

- **The second run.** After its run is read and judged as today (`[build]`, `check`, `no-report`, `error-before-assertions`, `group-failed`, `red-already-passes` when nothing failed, `suite-without-tests` on the first run's failures; for `--redo`, `redo-drops-case` before `red-already-passes`), `red` runs once more the suites that have a case in `F`, the first run's failed cases (suite-prefixed, as `failing_at_red` writes them), in configuration order, on the same working tree. Each runs as the hook runs a suite for a lock whose `failing_at_red` is `F` and whose `files` are the files `red` is about to lock, read from the working tree just before the second run: the same command, `filter`, `SHIPCRAFT_CASES` and `SHIPCRAFT_FILES` (the only `red` run that receives `SHIPCRAFT_CASES`; item 55's narrowed first run receives `SHIPCRAFT_FILES` only; §6), item 51's positional files, and the same fallback to every locked file when a case of `F` does not map to a file. Only the execution and the report reading are the hook's; none of the hook's verdicts (`case-missing`, `case-broke`, `red-already-passes`) apply. `[build]` and `check` do not run again. The second run is part of the same `red` command: one run log row, whose `secs` covers both runs.
- **What is locked as failing.** Each suite's second report is read by the same reader as the first (duplicates folded to the worst outcome, kept separate from the first run's report). A case of `F` is dropped from `failing_at_red` only if that report shows it passed. A case of `F` that failed, errored, was skipped or is absent from the second report stays locked, and so does every case of `F` of a suite whose second run gives no readable report: absence is not evidence that the behavior passes. A case that fails or errors only in the second run is ignored. `cases` comes from the first run, and `files` is hashed after the second run, as `red` hashes after its run today.
- **Reported.** When some case of `F` is dropped, `red` prints, before its usual lines and only when it writes the lock, `shipcraft: not locked, passed on a second run: <cases>`, byte-sorted, with item 52's list formatting and control-character escaping. The `red` row of the run log has `rerun_dropped`, the number of dropped cases, on rows that write a lock.
- **Refusals.** If every case of `F` passed in the second run, `red` refuses `red-not-reproduced`, naming `F`, and writes no lock (`--redo` leaves the lock as it was). `Why:` a RED's failure must happen every time the test runs without the implementation; these failed once and then passed. `Next:` run the command again; if the tests keep passing on their own, fix them (or the setup they depend on). The second run adds no other refusal.
- **Cost.** The second run is the hook's run for the RED cases: on the Forge's probe, 40 s for 4 locked files (2 of them jsdom files of 8.6 s and 23.2 s); a RED of one test file costs about that file's run. When a case of `F` does not map, it runs every locked file, as the hook does.
- **Battery.** These existing cases count `red`'s commands or their environment and change by the second run, and only in that respect: `v1-22.ambiente-red`, `v1-22.ambiente-build`, `v1-22.bash` (the second run receives the lists), `v1-16a.1-red-build` (the failing suites run again after the build). `v1-38` keeps one `red` row per command.
- **Unchanged.** The hook, CI, locks already written and the lock format. A failure that repeats is locked as before: a test already failing on the branch is still the RED's to fix (CI keeps main green).
- **Known limits.** A flaky case that fails twice in a row is locked. A RED test that passes on its second run, by chance or because it depends on a test file the narrowed run leaves out, is dropped; the lock may then close one commit early, and CI runs it at HEAD. A test that rewrites a protected file when it runs is hashed as the second run leaves it, as `red` hashes after its run today.

Wrong-measurement note: since 1.0 `red` took one run's failures as the RED; found on the Forge in POC-019.

### `red` runs the changed test files (item 55)

Before item 55, `red` ran every suite in full to learn which cases fail, and most of that run went to tests the RED never touched. On Shipcraft's own repository a `red` took 1,521 s at 2 jobs (`metrics/dogfood-hook-2026-10-27.md`), while a whole item takes about 10 min from RED to main (median). On the Forge (15,774 cases) a `red` took about 6 min. A full run also locks a failure the RED did not cause: a test that already fails on the branch, in a file the RED never touched, became part of the contract (the Forge, POC-019). POC-020 replayed items 41 to 50 with only the RED's changed test files run: it missed 0 of 212 failing cases and ran a median of 1.7% of the cases.

**The base.**
- `red` takes `--base <ref>` when given, else `refs/remotes/origin/HEAD`, and resolves it with `git rev-parse --verify <ref>^{commit}`.
- The base commit is the merge base of `HEAD` and that commit, as `git merge-base --all` gives it, and there must be exactly one.
- Anything else falls back to the full run: no ref, a ref that is not a commit, an unborn `HEAD`, zero or several merge bases, or a git command that fails.

**The changed paths.**
- They are the union of two lists:
  - the paths that `git diff -z --name-status --no-renames <base commit>` reports between the base commit and the working tree (tracked files, staged or not, compared by their final content, mode and type; a path whose changes cancel out is not changed);
  - untracked, non-ignored files, from `git ls-files -z --others --exclude-standard`.
- Ignore rules apply only to untracked files: a tracked file under an ignored folder that changed is a changed path.
- If either command fails, `red` falls back to the full run.

**The selection.**
- A suite's *selected files* are its changed paths that:
  - match the suite's globs, read and matched exactly as protection reads them;
  - and are not `.shipcraft.toml` itself.
- Paths are relative to each suite's `root`.
- Each selected file must be a readable regular file as `lstat` sees it (a symlink is not one), and every path git reports must be valid UTF-8. Otherwise `red` falls back to the full run (`unreadable path`).
- A changed path that matched a suite's globs at the base commit and was deleted or is no longer a regular file makes `red` fall back to the full run. So does a changed `.shipcraft.toml`.

**The narrowed run.** When some suite has selected files and no fallback applies:
1. `red` runs `[build]` as today.
2. It runs the suites in configuration order, each with today's steps in today's order. A suite with selected files runs its `check`, then its command. A suite with none runs its `check` and skips its command. A failing `check` refuses as today, at once; coverage is judged only after every suite has run.
3. The command of a suite with selected files runs with the hook's filter for its RED files (`filter = "shipcraft"`), where the selected files stand in for the RED files:
   - for pytest, vitest and jest, every other present test file of the suite is left out, and vitest also gets each selected file as a positional argument;
   - for Go, every `./...` of the command becomes the packages of the selected files, as in the hook, with no `-run`: the whole package runs, and its cases from other files are left out below;
   - with `filter = "command"`, the command runs as written;
   - for any runner, `SHIPCRAFT_FILES` lists the selected files (absolute, NUL-terminated, deduplicated, in byte order, as in section 6), and `SHIPCRAFT_CASES` is not set.

**Coverage, judged before any verdict on the narrowed run.**
- `red` maps each case of each report to its file with the hook's mapper (section 6: the map from case ids to locked files, with the hook's rules for roots and leading parts).
- It falls back to the full run, without judging the narrowed reports, when:
  - a suite that ran gives no readable report;
  - the mapper finds no single map for a report;
  - a case of a report maps to no file, or to more than one;
  - or a selected file holds no case of any outcome. This last one is a helper, fixture or runner config that tests depend on, or a file the runner did not run, and `red` cannot know which tests depend on it.
- Otherwise the narrowed run stands. Its reports keep only the cases that map to a selected file. Cases from other files that the runner ran anyway are left out, so they are neither in `cases` nor in `failing_at_red`. The result is then judged with today's refusals and precedence (`error-before-assertions`, `group-failed`, `red-already-passes`, `suite-without-tests` on the suites that ran).

**The full run.**
- On a fallback, `red` runs today's `red`: every suite, every step.
- If the fallback was decided after the narrowed run had started, `[build]` and the checks already run are not repeated. The suites run again in configuration order: a suite whose check has not run yet runs it first (a failing one refuses as today), then every suite's command runs once in full, without the narrowed lists. The narrowed reports are discarded.
- Only the full reports supply `cases`, `failing_at_red` and item 53's `F`.

**What the lock holds.**
- `files` is computed exactly as today: every locked file of every suite, hashed. Protection does not narrow.
- `cases` holds the kept cases of the reports that stand. After a narrowed run, that means the selected files' cases only, so `--redo`'s `redo-drops-case` compares only those.
- `failing_at_red` comes from those cases as today, then item 53's second run, unchanged.

**Reported.**
- `red` prints one line before its usual lines, on success and on any refusal after the selection is decided:
  - after a narrowed run: `shipcraft: red ran the changed test files: <n> of <m>`;
  - after a fallback: `shipcraft: red ran every suite: <reason>`.
- `<n>` is the number of distinct selected files, by repository path. `<m>` is the number of distinct locked files across the suites, by repository path.
- `<reason>` is the first that applies, in this order: `--all`, `no base`, `no merge base`, `git failed`, `config changed`, `protected file removed`, `unreadable path`, `nothing selected`, `no report`, `case without file`, `file without cases`.
- The `red` row of the run log gets three fields when the selection is decided:
  - `selection`: `"changed"` or `"all"`;
  - `selected_files`: `<n>` when a narrowed run started (kept after a later fallback), else 0;
  - `fallback`: the reason, or `null` after a narrowed run.
- A `red` refused before the selection is decided (`lock-open`, a config error) writes its row without the three fields. Each `red` command still writes one row.

**Options.**
- `--all` forces the full run.
- `--base <ref>` names the base.
- `--redo` narrows too, with the lock's files added to the selection (item 60). `--base` and `--all` apply to it as to `red`.
- A repeated option or a `--base` without a value is invalid arguments (exit `2`).

**Section 6.** The exception that lets `red` pass `SHIPCRAFT_FILES` now covers two runs, under the same rules:
- the first run when it is narrowed, which gets `SHIPCRAFT_FILES` only;
- the second run of item 53.

**Unchanged.** The hook, CI (which runs every suite at HEAD and refuses `suite-red`), the lock format, `check`, `close` and item 53's second run.

**Battery.**
- The cases whose projects have an `origin` with `origin/HEAD` (`remote_setup`, `pr_main`) now narrow when their RED changes test files. Their assertions must hold unchanged:
  - `v1-40.trava-aberta`;
  - `v1-42.closed-*`;
  - `v1-50.reproduction`, whose tests sit in the base already, so it falls back with `nothing selected`;
  - `v1-38.*`, one `red` row per command;
  - `v1-44.local-red`, `v1-44.github-red`, `v1-44.off-red`;
  - `v1-10.1-execucoes-jsonl`.
- The cases with no `origin` run in full as before (since item 66: because their tests are committed at the base it finds, so nothing is selected), and their command and environment counts stay as they are: `v1-22.ambiente-red`, `v1-22.ambiente-build`, `v1-22.bash`, `v1-53.*`, `v1-16a.1-red-build`, `v1-45.red-order`.

**Versions.** The item raises the binary to 2.13.0. No lock or config field changes.

**Known limits.**
- A case outside the selected files that the RED breaks is not run at RED, for example through a product stub the RED changed, or through a helper outside the globs. CI refuses it later as `suite-red`. This costs time, never an escape.
- A selected file holding cases proves only that it ran, not that no other test depends on it. A vitest test file that other test files import, or a pytest file that registers fixtures for others, can change their results unseen until CI.
- A failure already on the branch that lives in a selected file is still locked.
- `origin/HEAD` is taken as the remote's default branch as this clone last recorded it. If the default branch changed since, `red` narrows against the old one and may select more files or fewer: a failing test that is only on the old branch is then missed at RED, and CI catches it. `--base` overrides it.
- Go's case-to-file map reads test declarations line by line, as the hook does. A test it does not recognize maps to no file, so it falls back to the full run.
- A fallback after a narrowed run costs both runs. The log's `fallback` field measures how often that happens.

### A new suite reaches the base first (item 59)

A PR is judged by its base's config (section 4), so a `[[suite]]` added in the same PR as its first tests does not run in CI yet. Before item 59 nothing said so. In draken-platform PR #42 (2.13.1, 2026-10-28) the RED added the package `packages/jobs` with its tests and no suite: `red` locked 2 cases from the suites already configured and ran none of the 80 new tests, silently. The RED then added the suite and locked again, and `ci` refused `case(s) from lock … are missing from the report`, which reads as a filter problem. The way out was a separate PR that brought the package and its suite to main first. Item 59 changes no verdict: `red` warns, and `ci` names the cause.

**Suite identity.** A case id carries a suite prefix only when its suite has a non-empty `name` (`<name>:<case>`, section 6). Suites without one (no `name`, `name = ""`, the top-level form) add no prefix and are *unnamed*; item 59 never judges their cases.

**Reading suite names.** Wherever item 59 reads suite names from a `.shipcraft.toml` other than the working tree's, it reads the TOML alone, without the config's validation (`shipcraft_min`, legacy keys and the rest): every `[[suite]]` entry whose `name` is a non-empty string gives that name, and other entries are ignored. A file that cannot be read or is not TOML gives no names and turns off that diagnostic. Given a set of suite names, a case belongs to the longest name `n` of the set for which the id starts with `n:`; a case that starts with no `n:` belongs to none.

**Warnings are best effort.** Each warning is one line on stderr. A warning that cannot be computed (a git command, an object or a file that cannot be read, a path that is not UTF-8) is skipped for that path or as a whole, and a failed write to stderr is ignored. No warning ever refuses, changes an exit code, the lock, the run log (no field, row, result or code; `secs` still covers the whole command) or item 55's selection.

- **`red` warns about test files outside every suite's globs.**
  - A *test-named file* is a path whose last component matches, case-sensitively and as a whole string, one of `test_*.py`, `*_test.py`, `*_test.go`, `*.test.<ext>`, `*.spec.<ext>`, where `<ext>` is one of `js`, `jsx`, `mjs`, `cjs`, `ts`, `tsx`, `mts`, `cts` and `*` is any sequence of characters, empty included (a leading dot is an ordinary character).
  - Candidates are item 55's changed paths (same base, `--base` included, and the same two git commands), computed even when `--all`, `--redo` or a fallback means the run is not narrowed. A candidate must be a regular file in the working tree as `lstat` sees it; anything else (deleted, a symlink, a folder, unreadable) is not one. When the base or either list cannot be read, there is no warning.
  - `red` warns about every test-named candidate that matches the globs of no suite of the working tree's config, matched as protection matches them (relative to each suite's `root`): `shipcraft: warning: <n> changed test file(s) match no suite's globs and are not locked: <paths>; widen a suite's globs, or add a [[suite]] for them (when the base has a .shipcraft.toml, CI judges a PR by the base's, so a new suite goes in a PR of its own first)`. `<paths>` are repository-relative, distinct, in byte order, with the list formatting of refusals that name cases (truncation included).
  - It is printed after the config is read and validated and before `[build]` or any suite `check` runs. A refusal before that point prints no warning.
- **`red` warns about locked suites the base does not have.**
  - The *base config* is the `.shipcraft.toml` at the commit that item 55's base ref resolves to (the ref itself, not the merge base), the same file `ci` reads as `origin/<base>`. Its suite names are read as above. When the ref does not resolve, or that commit has no `.shipcraft.toml`, or its text is not TOML, there is no warning.
  - After `red` writes a lock, or `--redo` rewrites one (never on a refusal, and not when `--redo` leaves the lock as it was), it warns about every named suite of the working tree's config that has a case in the lock's `cases` and whose name is not among the base config's suite names: `shipcraft: warning: the lock has cases in suite(s) absent from <ref>'s .shipcraft.toml: <names>; CI judges a PR by its base's config and will refuse them as case-missing; bring the suite to <ref> in a PR of its own, then rebase this branch`. `<names>` are distinct, in byte order, with the same list formatting.
  - A suite whose name is in the base config counts as present, even if its command, root or globs differ.
- **`ci` names the cause of `case-missing`.**
  - The *lock's suites* are the suite names, read as above, of the `.shipcraft.toml` at the commit being checked (the commit whose lock is being judged, as today's check walks them). When that file is missing or gives no names, there is no diagnosis and the refusal is today's. A missing locked case is *of an absent suite* when it belongs (Suite identity) to a name of the lock's suites that is not a suite name of the config `ci` judges with.
  - When the lock's missing cases include any of an absent suite, the refusal keeps the code `case-missing` and reads: `case(s) from lock <path> belong to suite(s) that the .shipcraft.toml CI judges with does not have: <names> (<n> case(s))`, where `<names>` are distinct, in byte order, with the list formatting of refusals that name cases, and `<n>` counts the distinct missing cases of those suites. `Why:` CI runs the suites of the config it judges with, the base's for a PR, so a suite that is only in this branch's config does not run. `Next:` if the suite is new in this branch, bring the `[[suite]]` entry to the base in a PR of its own, with the package and at least one passing test (or a runner set to pass with no tests), so the base can run it; merge it, then rebase this branch and run `shipcraft ci` again.
  - This text takes precedence only inside that lock's missing-case check: cases of present suites missing from the same lock show on the next run. Every earlier refusal, and the order in which locks are checked, are unchanged.
  - Missing cases of no absent suite refuse as today, with today's text.
- **Docs.** The README's configuration section says how to add a package with a new suite when the base already has a `.shipcraft.toml`: first the suite in its own PR, with one passing test, then the RED.

**Unchanged.** Every verdict and exit code, the hook (which judges with the commit's own config) and every other refusal and its text.

**Battery.** No case asserts on what changes. `v1-22.sumiu-comando`, `v1-22.sumiu-parcial`, `v1-22.sumiu-sc2` (today's `case-missing` text), `v1-38.red-event`, `v1-38.red-refusal` and `v1-55.*` must hold unchanged.

**Versions.** The item raises the binary to 2.15.0. No lock or config field changes.

**Known limits.**
- Globs say what is protected, not what runs. A test file inside a suite's globs that the suite's command never collects (`pytest tests/unit`, a vitest `projects` list, a Go package pattern) gets no warning, and a file outside the globs that the command does collect still gets one.
- A test file named by none of the patterns gets no warning.
- Unnamed suites are never judged. Turning a top-level suite into a named `[[suite]]` changes every case id, and a rebase does not repair locks written before; the `ci` text then shows the new name as absent.
- A suite that keeps its name and changes its root or command so that it reaches the new package is present for both checks, and `ci` refuses with today's text.
- The second warning reads the base ref as this clone last fetched it.
- A suite renamed in the PR reads as absent from the base.
- `ci` attributes cases with the suite names of the commit being checked. A lock closed earlier on the branch, whose suite a later commit renamed, gets today's text.

### `red --redo` runs the changed test files too (item 60)

Before item 60, `red --redo` always ran every suite, since a redo must see every case of the lock it rewrites (item 46). On Shipcraft's own repository a redo of item 59's RED took 1,476 s (24.6 min) while its `red` took 148 s, and the rewritten lock grew from 40 cases to 1,824: every case of the battery became part of the cycle. A redo fixes a test the RED wrote, so the cases it must see are in the files that hold the lock's cases.

- **The selection.** `red --redo` decides the selection as `red` does (item 55: the base, the changed paths, the fallbacks and their order, `--base`, `--all`), with one addition per suite: the suite's *lock files*.
  - **Which suite owns a lock case.** By the suite prefix of the case id, with item 59's suite identity (the longest name `n` of the working tree's config for which the id starts with `n:`; a case with no prefix belongs to the config's unnamed suite, when there is exactly one). A case that belongs to no suite of the config makes the redo fall back to the full run (`case without file`).
  - **The lock files.** Each case of HEAD's lock `cases` is mapped to a file with the mapper item 55 uses to judge coverage (section 6's map from case ids to locked files, with the hook's rules for roots and leading parts), applied to the owning suite only, over the paths of HEAD's lock `files` under that suite, reading sources from the working tree. A case that maps to no file or to more than one, or to a path that is not a readable regular file in the working tree as item 55 checks selected files (`lstat`, then opened for reading), makes the whole redo fall back to the full run (`case without file`).
  - A suite's selected files are its item 55 selected files plus its lock files, deduplicated by repository path within the suite. A file holding cases of two suites is selected in each of them, and each suite's command gets its own list.
  - The emptiness test (`nothing selected`) is made after this union. The earlier fallbacks (`--all`, `no base`, `no merge base`, `git failed`, `config changed`, `protected file removed`, `unreadable path`) apply first and unchanged: without a base, a redo still runs every suite.
- **The narrowed run** is item 55's, on that selection: the same filters, lists and coverage judgement, and the same fallbacks to the full run after it started. A suite with no selected file runs its `check` and skips its command, as in item 55; item 46's "every suite" now means this.
- **What it requires and writes** is item 46's, on the cases the run keeps. `redo-drops-case` compares HEAD's lock `cases` with the kept cases: every old case must be reported, not skipped. Running a case's file does not guarantee it is reported (a `-t`, `-k` or `-m` in the command, or a project selection, can leave it out); the refusal is then the same as today. The new lock's `cases` are the kept cases, so the lock grows by the cases of every test file the branch changed since its base, not only the repaired one, and a later redo must keep them.
- **Reported** as item 55 reports: `red ran the changed test files: <n> of <m>`, where `<n>` counts distinct repository paths selected across suites (lock files included) and `<m>` is item 55's. The reason `--redo` is gone from the fallback list. A redo refused before the selection is decided (`redo-without-lock`, `lock-open`, `lock-edited`, `lock-format`, a config error) writes its row without the three fields; any other redo row, an unchanged lock included, has `selection`, `selected_files` and `fallback`, and keeps `redo: true`.

**Item 46 amended.** "What it runs" becomes: the suite as `red` runs it on the working tree, with item 60's selection; build and every suite's `check` still run, with the same refusals and precedence.

**Unchanged.** The redo commit and how the hook and CI judge it (item 46), `redo-drops-case`, `redo-mixed`, item 53's second run, item 59's warnings, the lock format.

**Battery.** `v1-55.redo` (asserts the full run, `("all", 0, "--redo")` and the legacy cases in the lock) changes to the narrowed result; `v1-55.redo-base` (`--base nonexisting55` ignored) now falls back with `no base`. `acceptance/pontos/55.md`'s two lines on redo change with them. Items 46, 52, 53 and 59's redo cases must hold.

**Versions.** The item raises the binary to 2.16.0. No lock or config field changes.

**Known limits.**
- A case of another file that the repaired test or its support code breaks is not run at redo; CI refuses it later as `suite-red`, as for item 55.
- The lock files are those holding the lock's cases. Support files (`conftest.py`, setup files, runner configs, `testdata/`) and test files whose cases were all skipped are not selected for that reason. A lock case that only worked because another file was collected with it (a pytest plugin registered by a sibling module, read through `SHIPCRAFT_FILES`) can then fail or vanish at redo and refuse `redo-drops-case`; `red --redo --all` runs every suite as before.
- Without a base, a redo runs every suite, even when every lock case maps. Since item 66, that means an unborn `HEAD` or a git failure: a repository with no remote uses `main`, `master` or `HEAD` (item 66).
- A case whose test moved to another file in the repair maps to no file of the old lock, and the redo runs in full.

### The lock closes by itself

### The base when `origin/HEAD` is missing (item 66)

Item 55 narrows from `refs/remotes/origin/HEAD`. When that ref is missing, `red` falls back to the full run (`no base`). It then locks every failing case of the project, including tests that already failed on the branch and that the RED never touched. POC-021 saw exactly that: a project with no remote, where `red` locked an unrelated failing test (SHOP-212) beside the RED's own. `origin/HEAD` is missing more often than it looks. A repository that was never cloned has no remote at all. `git remote add origin` followed by `git push -u` creates `origin/main` but not `origin/HEAD`.

1. **The base, without `--base`.** `red` first reads `HEAD` with `git rev-parse --verify -q HEAD^{commit}`. Exit status 1 means `HEAD` is unborn (no commit yet): there is no base, and `red` falls back to the full run with `no base`, as today. In a repository with no commit every test is new. Any other failure gives the full run with `git failed`: another exit status, a signal, a failure to start git, or output that is not one commit id. Otherwise `red` takes the first of these candidates that resolves to a commit:
   1. `refs/remotes/origin/HEAD`, as today;
   2. `refs/remotes/origin/main`, then `refs/remotes/origin/master`;
   3. `refs/heads/main`, then `refs/heads/master`;
   4. `HEAD`.
   
   Each candidate is resolved once with `git rev-parse --verify -q <ref>^{commit}`, and `red` keeps the commit id it gives. Exit status 1 means the candidate is absent or not a commit, so `red` moves to the next one. Any other result stops the search and `red` falls back to the full run with `git failed`: another exit status, a signal, a failure to start git, or output that is not one commit id. With `--base <ref>`, nothing changes: that ref is used, and its failures give the fallbacks they give today.
2. **The merge base.** As in item 55: the merge base of `HEAD` and the chosen commit, as `git merge-base --all` gives it. There must be exactly one. If zero or several come out, `red` does not try the next candidate: it falls back with `no merge base`, as today. When `HEAD` is the chosen candidate, or `HEAD` is on the chosen branch, the merge base is `HEAD`. Then the changed paths are exactly what the working tree adds to `HEAD`, which is the RED's tests when they are not committed yet. The names `main` and `master` are a convention, not proof that the branch is the default. The first one that resolves is used, even if another branch is the real default.
3. **Item 59's warnings use the same base.** Item 59's two warnings in `red` read the commit chosen here, and wherever they print a ref they print point 4's short name (`origin/main`, `main`, `HEAD` and so on): test files outside every suite's globs, and suites absent from the base config. So all three use one base: the selection, those warnings, and the line in point 4. Every reader outside `red` is unchanged: the hook, CI, `shipcraft pr` and `merge`, and `Repo::default_branch` (`origin/HEAD`, or `main` when it is missing).
4. **Reported.** When the base came from candidates 2 to 4, `red` prints one line on stdout, right before item 55's selection line and only when that line is printed: `shipcraft: red compared with <name> (origin/HEAD is missing)`. `<name>` is `origin/main`, `origin/master`, `main`, `master` or `HEAD`. With `--base` or `origin/HEAD`, nothing is added.
5. **The run log.** No field is added. Item 55's fields keep describing the run that actually happened: a project without `origin/HEAD` that now narrows writes `selection: "changed"` and `fallback: null`.
6. **`--redo`.** Item 60's redo resolves its base the same way.
7. **What does not change.** The lock format, the rules of items 55, 60 and 65 for selection and coverage, and every reader listed in point 3.
8. **Battery.** These cases expect `no base` on a project that has no `origin/HEAD` but has `origin/main` or `main`. Their fixed points change with them. The first three change to the narrowed run on the new base. `v1-59.suites-no-base` keeps its full run, because its config changed (`config changed`), and changes only its warning: it now names the suites absent from the new base.
   - `v1-55.no-base` (Python and Node), with `acceptance/pontos/55.md`;
   - `v1-60.no-base`, with `acceptance/pontos/60.md`;
   - `v1-59.files-no-base` and `v1-59.suites-no-base` (item 59's warnings now read the new base), with `acceptance/pontos/59.md`.
   
   These keep their expectations: an explicit bad base (`v1-55.redo-base`, `v1-60.bad-base`), and cases whose tests are already committed at the new base, which still fall back with `nothing selected` (`v1-22.ambiente-red`, `v1-22.ambiente-build`, `v1-22.bash`, `v1-16a.1-red-build`, `v1-45.red-order`, item 53's wrapper cases). The row-key checks of items 59 and 65 and item 10's log reader are unchanged.
9. **Measure and revert.**
   - **Metric:** the share of `red` rows with `fallback: "no base"` in adopters' run logs (draken-platform, the Forge, POC fixtures), and pre-existing failures locked by a RED in POC-021's fixture. **Threshold:** `no base` only on repositories with no commit, and 0 pre-existing failures locked in POC-021's fixture. That fixture is the evidence, not a general guarantee (see the limits).
   - **Revert:** `red --all` forces the full run for one RED, `red --base <ref>` picks the base by hand, and a release reverts the rule.
10. **Known limits.**
    - When the chosen candidate contains `HEAD`, the merge base is `HEAD`. That happens with `HEAD` itself, with `main` while working on `main`, and with a stale `origin/master` that points at the branch. Tests committed before `red` ran are then not selected. If nothing else is selected, `red` falls back to the full run (`nothing selected`) and can lock failures that were already there, as before this item.
    - The same full run follows a RED that changes no test file, for example only a product stub. It also follows a RED whose test files did not change at all.
    - A local `main` far behind the real default branch gives a wider diff: more files run, and none is missed.

### A changed support file no longer runs every suite (item 65)

Item 55 falls back to the full run when a selected file holds no case (`file without cases`), because `red` cannot know which tests depend on it. On Shipcraft's own repository the RED of item 62 changed a stub that its own new test file used, and `red` ran the whole battery: 1313 s instead of about 2 minutes. A RED commonly changes a helper, a fixture or a stub next to its new test.

1. **The rule.** In a narrowed run, the fallback `file without cases` now applies only to a suite that has selected files, whose command ran, and where none of its selected files holds a case. A suite with no selected files is skipped, as in item 55, and never triggers it. A suite where at least one selected file holds a case keeps its narrowed run, even if other selected files of that suite hold none. A case of any outcome counts (passed, failed, errored or skipped), and only the suite's own selected files count.
2. **When it is decided.** The decision comes after the reports are read, at the point where item 55 judges coverage. It uses item 55's mapper and order, and the fallbacks `no report` and `case without file` keep their place before it. Nothing about how the suite runs changes: the first run gets the same arguments and the same `SHIPCRAFT_FILES` as today, support files included, so a project's own adapter still sees them. There is no extra run.
3. **What the lock holds.** As in item 55: `files` hashes every locked file, the support files included, so they stay protected. `cases` and `failing_at_red` come from the kept cases of the selected files that hold cases, then item 53's second run.
4. **Reported.** When this rule kept a narrowed run and at least one selected file holds no case, `red` prints one line right after item 55's `shipcraft: red ran the changed test files: <n> of <m>`, on success and on any refusal that prints that line: `shipcraft: red did not run the tests that may use the changed support file(s): <paths>; CI runs them`. `<paths>` is built suite by suite: for each suite whose command ran, its selected files that hold no case in its own report. Those sets are joined by repository path, with no duplicates, in byte order, with item 52's list formatting. The run log does not change: the `red` row keeps `selection`, `selected_files` and `fallback` as item 55 defines them, so `selected_files` still counts the support files.
5. **`--redo`.** The same rule applies to item 60's narrowed redo.
6. **Battery.** `v1-55.support-test` changes. It changes a support file, adds a passing test, and keeps an unchanged legacy test that fails. Before this item, `red` fell back to the full run and locked the legacy failure. Now the narrowed run stands, its only kept case passes, and `red` refuses `red-already-passes` with no lock. `acceptance/pontos/55.md` changes with it. `v1-55.support` changes only a support file, so it keeps its full-run expectation: no selected file holds a case. No other case's assertion changes. Item 59's row-key checks are unaffected, because no row field is added.
7. **Measure and revert.**
   - **Metric:** `red`'s `secs` per item on this repository, and the share of `red` rows whose `fallback` is `file without cases`. **Threshold:** over the next 5 items, `red` takes 60 s or less on a typical item (one test file and at most a few helpers), compared with 1313 s on item 62, 190 s on item 63 and 392 s on item 64. At most 1 of the 5 falls back with `file without cases`.
   - **Revert:** `red --all` forces the full run for one RED; a release reverts the rule.
8. **Known limits.** A support file the RED changed can change the results of tests in files it did not select. `red` does not see that, and CI runs them. This is item 55's known limit, now for helpers too. Item 55's other known limit stays: a selected file that holds cases proves only that it ran, not that nothing else depends on it.

The RED commit's hook also reruns the RED cases that `red` just ran. Making it trust `red`'s run was considered and left out. The same git tree is not the same run: ignored files, environment variables, line-ending filters and the index can differ between `red` and the commit, and each of those can turn a RED that would be refused into an accepted one. The hook's cost is measured again first, after the battery harness fix of 2026-10-30.

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
- **Without the hook's git variables (item 57).** Git runs a hook with `GIT_DIR` and `GIT_INDEX_FILE` set, and in some cases `GIT_WORK_TREE`. In the hook, every suite command `shipcraft` runs (the test command, on a copy or in the working tree) runs with exactly those three variables removed from its environment, whatever their values. They are removed from the shell `shipcraft` starts, so wrappers and their children inherit the cleaned environment. Every other variable is passed on as before, including signing and `GIT_CONFIG_*` settings and section 6's lists. `shipcraft`'s own git reads (the effective index, warnings, the close mark) keep the hook's context, as before.
  - **The index.** When `GIT_INDEX_FILE` names an index other than the repository's own (for example `git commit --only` or `git commit <paths>`), the hook runs the suite on a copy of that index, as it does when something is outside the index. A test that reads the index then sees the commit's content, never the ordinary index.
  - **What a test sees.** A test that runs git in the project finds the repository from its folder, as in a terminal. A test that runs `git init` in a folder of its own, and then works there, works on that repository, not on the project's. Git's upward discovery still applies: a temporary folder inside the project, before its own `git init`, belongs to the project.
  - **`red` and `ci`** are unchanged: they run from the user's shell, and the environment is the user's. A project whose git directory is only reachable through `GIT_DIR` keeps working there as before.

  Wrong-verdict note: since item 14, the hook removed them only when it ran on a copy (something outside the index). When nothing was, the suite ran in the working tree with the hook's variables. A test that ran `git init` in a temporary folder reinitialized the project's repository instead: in a linked worktree it set `core.bare = true` in the shared config, and every later git command in the worktrees failed (`fatal: this operation must be run in a work tree`). Found on 2026-10-28 by Shipcraft's own battery, at the first RED commit of the dogfooding trial (item 56). The battery should have caught it, but no case ran a suite that uses git through the hook's direct path.

Edge cases are fixed by the acceptance battery (`acceptance/`).

### What CI re-checks

`shipcraft ci --base <ref>` checks every commit of `<base>..HEAD` against the same rules (hashes, lock state, config, integration files). On HEAD only, it runs `[build]`, each suite's `check`, then the full suite. It does not install dependencies. It also refuses a green suite with a lock still open (`lock-not-closed`: the hook was skipped) and a failing suite with no open cycle (`suite-red`: this is where an old test broken by GREEN shows up).

## 3. Commands

Each command is `shipcraft <command>`. Exit codes, unless the row says otherwise: `0` success, `1` refusal (section 7), `2` failure (`shipcraft` could not do its job, or invalid arguments; the message starts with `shipcraft: error:`).

| Command | What it does |
|---|---|
| `--version` | Prints `shipcraft <X.Y.Z> (<12-char commit>)`, in any folder. |
| (no arguments) | Prints usage, exit `0`. |
| `init [--lang python\|node\|go] [--github]`, `init --lang other --command <cmd> --glob <glob>... [--github]` | Sets up the project (below; `other`, item 67). |
| `red [--redo] [--base <ref>] [--all]` | Runs the RED's changed test files, or every suite when it cannot narrow safely (item 55), requires assertion failures, reruns the failing cases once and does not lock those that pass (item 53), writes an open lock; `--redo` rewrites the branch's open lock (item 46). Refuses `lock-open`, `red-already-passes`, `error-before-assertions`, `group-failed`, `red-not-reproduced`, `no-report`, `suite-without-tests`, `build-failed`. |
| `check [--commit-msg <file>]` | The hook: judges the commit against the open locks and closes them when the RED cases pass. With `--commit-msg` it judges the final index and writes a close mark instead of the lock (`mark-failed` if it cannot). |
| `close` | The `post-commit` half of the `commit-msg` route: if the mark matches the commit just made, adds one commit that only flips the lock to `closed`. On failure it changes nothing and says to rerun it. Always exits `0`. |
| `ci --base <ref> [--pr]` | CI (section 2). `--pr` allows the docs-only path (section 5). `ci` publishes no status (item 44). |
| `pr [--title <t>] [--body <file>]` | Pushes (`--force-with-lease`), opens or updates the PR, runs the layers, posts statuses and summary (section 5). Refuses `pr-not-on-branch`. Exit `0` is guaranteed only when every layer passed or is off. |
| `review` | Reviews local HEAD and prints the verdict; publishes nothing. Exit `0` on approval; refuses `review-changes-requested`, `review-error`, `review-off`. |
| `review --pr <n>` | Reviews any PR in an isolated copy and publishes `shipcraft/review` and a comment. Refuses `pr-from-fork`. |
| `merge <pr> [--no-review "<reason>"]` | The merge gate (section 5). Refuses `pr-not-open`, `merge-without-ci`, `merge-without-review`, `no-review-without-reason`. |
| `status` | Prints the layers, review agent (none when review is off, item 73), hook state, open locks, and one line with the real branch protection level. |
| `report [--json]` | Prints the flow's numbers per lock and per day from the run log (section 8, item 38). Reads only; never refuses. |

`init` writes no run-log row; `red` and `close` write one each (item 38).

### `init`

`init` decides everything before it asks or writes. A refusal leaves the tree as it was; a write that fails midway is rolled back.

- **Language:** `pyproject.toml` or `requirements*.txt` is Python (pytest), `package.json` with vitest or jest is Node, `go.mod` is Go (gotestsum); `--lang` overrides. Workspaces (`pnpm-workspace.yaml`, `package.json` `workspaces`, `go.work`) get one `[[suite]]` per package with tests.
- **Config:** writes `.shipcraft.toml` with the test command, globs, `check` (`tsc --noEmit`, except for a tsconfig that checks no file, item 56; or `go vet`), `[execution]`, `[roles]`, `shipcraft_min` and, when it applies, `[build]`. Every `npx` it writes puts `--` before the tool's arguments.
- **Review:** `init` asks nothing. With an agent installed it writes `review = "local"` and the first one found in `[roles] review`, and says that the diff goes to that agent's provider and how to turn review off. With none installed, review is `off` and it says how to enable it.
- **AGENTS.md:** `init` creates `AGENTS.md` with a short block (marked `<!-- shipcraft -->`) telling agents the RED/GREEN workflow, or appends the block once to an existing file. A symlink or a failed write is left alone with a notice; it never fails the init. The block is the text below `AGENTS_BLOCK` in `nucleo/src/init.rs`.
- **Hook:** there is one route: `shipcraft check --commit-msg` in `commit-msg` and `shipcraft close` in `post-commit`, so the hook sees the index after formatters ran. `init` integrates only when it can prove which configuration runs the hook:
  - plain git: shipcraft's own `.git/hooks/commit-msg` and `.git/hooks/post-commit`;
  - lefthook: the two commands in the lefthook file's `commit-msg` and `post-commit` blocks;
  - husky 9 and the pre-commit framework: the two commands in their files.

  Anything `init` cannot prove (another tool's hook, `core.hooksPath` elsewhere, two hook managers, flow-style YAML, symlinks) refuses with `foreign-hook` and says where to add `shipcraft check` by hand. Edge cases are fixed by the acceptance battery (`acceptance/`).
- **GitHub:** `init` never writes a workflow. With `--github` it marks `shipcraft/ci` and, when review is on, `shipcraft/review` as required checks where GitHub offers branch protection.

### `init` for a project of any language (item 67)

`init` knows Python, Node and Go. In any other project it refuses `lang-unrecognized`, and the only way out was to write `.shipcraft.toml` by hand. That cuts the hook, the `AGENTS.md` block, the review and the roles off from every project in another language. Shipcraft's own repository is one of them: a Rust core with a shell battery, where `init` says "could not recognize the project language" (dogfood step 1, 2026-10-29). Shipcraft never needed to know the language: with `filter = "command"` any command that writes a JUnit report is a suite.

1. **`--lang other`.** `init --lang other --command '<command>' --glob '<glob>' [--glob '<glob>' ...]` sets up a project whose tests Shipcraft runs as written.
   - **`--command`** is required. It is a shell command, run as every suite command runs today (`sh -c`, at the suite's root). `{junit}` is replaced by the shell-quoted report path, as today, so it must appear as an unquoted shell word or part of one (`--junitxml={junit}`, not `--junitxml="{junit}"`). It must contain `{junit}` exactly once, must hold, once `{junit}` is removed, at least one character that is not whitespace by Rust's `char::is_whitespace`, and must have no control character as Rust's `char::is_control` defines it. `init` does not parse or run the command.
   - **`--glob`** is required at least once, and may repeat. Each value is a test or support file glob, validated and normalized as `test_globs` entries are today (relative, no `..`, no absolute path; `./` and empty components removed), and matched by Shipcraft's own glob matcher (`*`, `**`, `?`). It does not know braces `{a,b}` or character classes: they are taken literally. A vitest-style `**/*.{test,spec}.ts` is therefore two `--glob` values. After normalizing, repeats are dropped and the first one keeps its place.
   - **What it writes, when there is no `.shipcraft.toml` yet:** the top-level suite keys `test_command` and `test_globs`, with `filter = "command"`, and no `lang`, `runner`, `check` or `[build]`. `lang` stays limited to `python`, `node` and `go`, and is optional, as it is today for a hand-written config. Everything else is today's `init`: `[execution]`, `[roles]` (`review` as a string), `shipcraft_min`, the hook, the `AGENTS.md` block and its `CLAUDE.md` import, the review choice and the closing guidance. `init` skips TypeScript build inference entirely for `other`, so it runs no `tsc` and writes no `[build]`. It writes no stub.
   - **When `.shipcraft.toml` already exists,** it is kept as today: its suites and every other key stay as they are, and the only change is item 20.2's raise of `shipcraft_min` to the running binary's version, when that applies. The flags are still validated (point 2), but they do not change the config, and `init` prints `shipcraft: .shipcraft.toml exists and was kept; --command and --glob only seed a new config`. The closing guidance describes the kept config, as today.
   - Only `init --lang other` with valid flags takes this path. A plain `init` in a project whose language it cannot detect still refuses `lang-unrecognized`, even when a hand-written `.shipcraft.toml` exists.
   - The first `red` runs the command, and refuses `no-report` if it writes no report, as today.
2. **Refusals and their order.** Every refusal leaves the tree as it was, as `init` refusals do today. They come in this order:
   1. Command-line syntax, exit `2`: a repeated `--command`, a repeated `--lang`, or a flag without a value. A value that starts with `--` counts as missing, so `--command --glob x` is exit `2`.
   2. Today's legacy-config refusal, in its place.
   3. `lang-unknown`: `--command` or `--glob` given without `--lang other`, whether `--lang` names another language or is omitted. Also `--lang other` without `--command` or without any `--glob`, and a `--command` that breaks point 1's rules.
   4. `config-invalid`: the first invalid `--glob`, in argument order.
   5. Everything after that is today's `init` (hook planning, `foreign-hook` and the rest), with today's messages.
   
   The refusals in steps 3 and 4 end with `Next:` showing the full form: `shipcraft init --lang other --command '<test command writing JUnit to {junit}>' --glob '<test files>'`. No other refusal changes its `Next:`.
3. **Detection is unchanged.** With no `--lang`, detection still knows only Python, Node and Go. No language found still refuses `lang-unrecognized`, and more than one still refuses `lang-multiple`. Both add the full form of point 2 to their `Next:`. For `lang-unrecognized`, `Why:` adds that Shipcraft can run any command that writes JUnit.
4. **Touches.** These earlier items' cases cover what this item shares or changes. They must keep passing unchanged:
   - language and init output: `init-detect`, `init-files`, `init-workflow`, `init-lang-flag` (`run.sh`), item 16b's `init --lang node` and its TypeScript build inference (`acceptance/lib/item16b.sh`, `pontos/16b.md`), and item 25's `init --lang python`;
   - workspaces: `v1-9.1-init-pnpm`, `v1-9.1-init-workspaces-do-package-json`, `v1-9.1-init-go-work`;
   - checks and npx: `v1-13.1-init-escreve-verifica`, `v1-13.1-init-verifica-com-traco`, `v1-12.1-npx-tsc-com-traco`, `v1-12.1-todo-npx-com-traco`, and item 56;
   - globs and `--github`: item 30's glob normalization and rejection cases (`v1-30.1-glob-*`, `v1-30.1-v0-glob-*`, `v1-30.3-*`), `v1-5.3-init-github-marca-obrigatorios` and `v1-5.3-init-github-plano-gratis`;
   - refusal order and rollback: `v1-15a.1-recusa-antes-de-perguntar-e-escrever`, `v1-15a.1-decide-antes-e-desfaz-escrita-no-meio`, `v1-15a.1-falha-preserva-config-simbolica`, `r-legacy-config-init`, `r-legacy-config-coexists`;
   - hooks: `v1-20.rota.commit-msg`, `v1-20.rota.post-commit`, `v1-58.plain`, `v1-58.kept`, `v1-58.rollback`;
   - guidance and comments: `v1-27.mensagem-local`, `v1-27.mensagem-desligado`, `v1-27.mensagem-github`, `v1-62.init`, `v1-62.init-preserve`, and `v1-2.3-tela-do-init` (init asks nothing);
   - item 61's `AGENTS.md` block and item 64's `[roles]` defaults.
   
   No existing case asserts the text of `lang-unrecognized` or `lang-multiple`, or uses `--command` or `--glob`. README fixed points 14 and 15 still describe a review question that `init` no longer asks (item 25 removed it); they are corrected to "init asks nothing". No assertion changes.
5. **Measure and revert.**
   - **Metric:** `init --lang other` on Shipcraft's own repository (with `.shipcraft.toml`, `.shipcraft/` and the hooks moved aside) writes a config whose suite matches ours: the same command and globs, and `filter = "command"`. It is also the onboarding path for adopters in other languages.
   - **Threshold:** that run succeeds, plus 0 false refusals over the next 5 items.
   - **Revert:** a release. A project already set up keeps its config.
6. **Known limits.**
   - Shipcraft does not filter a command it does not know, so the hook runs the whole command on every commit with an open lock, unless the command reads `SHIPCRAFT_FILES` or `SHIPCRAFT_CASES` itself (section 6).
   - `init` writes no stub for a language it does not know.
   - Rust's `cargo test` writes no JUnit by itself. A Rust project needs a reporter such as `cargo nextest` with a JUnit profile, named in `--command`.

### `init` writes no check that checks nothing (item 56)

Before item 56, `init` wrote `check = "tsc --noEmit"` for every Node suite with a `tsconfig.json`. A *solution* tsconfig, `"files": []` with `references` to the real projects, makes that command check no file: `tsc` reads no source and the check always passes. The Forge's root tsconfig is such a file (POC-019). The project type-checks with `pnpm tsc -b && pnpm typecheck:tests`.

- **What is read.** `init` reads the suite folder's `tsconfig.json` from the working tree, tracked or not, as suite detection does. A symlink, a file that cannot be read, or one the tsconfig parser that `[build]` uses (JSON with comments and trailing commas) cannot parse, is not judged: `init` writes `tsc --noEmit` as today.
- **What checks nothing.** The file is a JSON object, and:
  - its `files` key holds an empty array;
  - its `include` key is absent or holds an empty array;
  - its `extends` key is absent (any value of it, `null` included, means not judged);
  - its `references` key holds a non-empty array.
  Any other value of any of these keys means not judged.
- **What `init` writes then.** It depends on `[build]`, which is decided first, as today:
  - **`[build]` written** (its `tsc -b` succeeded and includes this suite's folder): no `check` key for that suite. `[build]` type-checks the referenced projects whenever it runs. `init` prints one line: `shipcraft: <path> checks no file; no check written for suite <name>: [build] type-checks its references`.
  - **`[build]` not written** (its command failed, as today's warning says): `check = "tsc --noEmit"` as today, so no gate is lost. `init` prints one line: `shipcraft: <path> checks no file; the check of suite <name> passes without checking: set check to the project's own type-check command`.
  - `<path>` is the tsconfig's path relative to the repository (`tsconfig.json` at the root). `<name>` is the generated suite name, or `default` for the top-level single suite. Control characters in either are escaped as in item 52's lists. The line comes after the `[build]` lines, one per affected suite, in suite order, on stdout.
- **Unchanged.** Every other suite and language. A tsconfig that lists files, has a non-empty `include` or has `extends`. An existing `.shipcraft.toml`, which `init` does not rewrite, prints no line. `init` still exits `0`. `init` writes no run-log row.
- **Battery.** README fixed points 40 and 57 (a check wherever a tsconfig exists) get item 56's exception. `v1-16b.1-build-reference`, whose solution tsconfig references a missing folder and whose build fails, keeps every assertion: `[build]` is not written, so its check stays. It gains the second line only. `v1-13.1-*` and `v1-12.1-*`, whose tsconfigs have a non-empty `include`, are unchanged.
- **Known limits.**
  - `init` does not follow `extends`. A tsconfig whose effective files and include, after inheritance, are empty still gets `tsc --noEmit`, which checks nothing.
  - The judgement is per suite folder. A root solution tsconfig in a workspace whose root holds no tests is not a suite and is not read; `[build]` still covers it when written.
  - A solution tsconfig without `references` (`"files": []` alone) is not judged. `tsc` reports it as an error, so today's check already fails there.

### No per-suite `tsc --noEmit` where `[build]` type-checks the suite's folder (item 72)

Wrong-verdict note: since item 16b (2.0.0), `init` writes `[build]` (`tsc -b` on every folder whose tracked `tsconfig.json` has `references` or `composite: true`) and still writes `check = "tsc --noEmit"` for each Node suite with a `tsconfig.json`. Item 56 removed the check only where the tsconfig checks no file. Found on the Forge, the second adopter (2.25.0, deluge-forge-platform PR #805, 2026-10-31): its packages' tsconfigs are composite projects with references, and `tsc --noEmit` there is refused with TS6310 (a referenced project may not disable emit), so every `red` and `ci` would refuse on the check. The Forge removed every check by hand. Item 56's spec review should have caught it: it judged the solution tsconfig only.

1. **The rule.** The only input is the folder list item 16b's inference returns when it writes `[build]` (the root as `.`): the folders its own reader selected (tracked `tsconfig.json` read from the index, workspace manifests and globs as item 16b reads them) and its proof run accepted. No tsconfig is read again for this rule, and a folder with the signal that inference did not name (outside the workspace globs, untracked, or in the working tree only) does not count. A Node suite whose package folder is one of those folders gets no `check` key, whatever its `tsconfig.json` holds. The package folder is the suite's root, or, for a suite item 71 converted to root `.`, the package folder `<dir>` its check enters.
2. **What `init` prints.** One line per such suite, in suite order, on stdout, buffered and printed where item 56's lines are printed today (after the core writes succeed, after the `[build]` lines, in the same position), never on a refused or rolled-back `init`:
   - when item 56's reader judges the suite's tsconfig as checking no file: item 56's line, unchanged (`shipcraft: <path> checks no file; no check written for suite <name>: [build] type-checks its references`);
   - for every other shape of the file (a project with sources, an `extends`, a file item 56 does not judge): `shipcraft: no check written for suite <name>: [build] type-checks <path>`.
   `<path>` and `<name>` are item 56's (the tsconfig's path from the repository root, `default` for the top-level suite, control characters escaped).
3. **When `[build]` is not written** (the proof run failed, a manifest or tsconfig did not read, a glob was not understood, as item 16b says), every suite keeps today's behavior: `tsc --noEmit` where a `tsconfig.json` exists, and item 56's second line where it checks no file.
4. **Where `[build]` runs.** As today: in `red`'s first run and in `ci`, before any suite. The hook and `red`'s confirmation run do not run `[build]` or checks; this item does not change that.
5. **Current behavior** on the paths this item touches (rule 14):
   - `[build]` inference: its readers (index, JSONC, manifests, globs), its proof run with real `tsc -b`, whose output (`dist/`, declarations, `.tsbuildinfo`, partial output on failure) stays in the working tree on success, on a failed proof and on a later failed `init`; its one-line JSONC diagnostic, its three-line warnings for manifests, globs and a failing compiler, after which `init` still succeeds without `[build]`; a git or process I/O error, which fails `init` as today: keep.
   - `check = "<bin>tsc --noEmit"` for a Node suite with a `tsconfig.json` whose root `[build]` does not name: keep.
   - Item 56's reader, its judgement and both its lines: keep.
   - A Node suite whose root `[build]` names and whose tsconfig item 56 does not judge as checking no file: gets `tsc --noEmit` today; change, as in point 1, with point 2's new line.
   - The rollback on a failed core write (only paths this run created, `shipcraft: undid what this run created`, the underlying error), no run-log row, `.git/shipcraft` untouched: keep.
   - Python, Go, `--lang other`, jest and vitest commands, the globs, an existing `.shipcraft.toml` (not rewritten, no line), `init`'s exit code, the closing guidance, the hooks, the block and the briefs: keep.
6. **Touches.**
   - **Assertions that change:** item 56's cases whose fixture gets a written `[build]` that names the suite's folder while item 56 does not judge the tsconfig as checking no file: today they require `check` ending in `tsc --noEmit`; they now require no check and point 2's second line. The review names at least `v1-56.extends` and `v1-56.files`; the RED runs every `v1-56.*` mode against today's binary, lists each mode where `[build]` names the suite folder, and changes exactly those (`acceptance/tools/item56.py`), keeping every assertion of item 56's solution modes. README fixed points 40 and 57 (a check wherever a tsconfig exists) gain this exception next to item 56's. Item 16b's cases (`v1-16b.1-*`) where a suite's own folder is a `[build]` folder with a check expected change the same way; the RED lists them.
   - **Must keep passing unchanged:** every other `v1-56.*` and `v1-16b.1-*` case; item 12's and 13's TypeScript init cases (`v1-12.1-*`, `v1-13.1-init-escreve-verifica`, `v1-13.1-init-verifica-com-traco`, `v1-13.1-verifica-fora-do-hook`) unless the RED shows their fixture's folder is a `[build]` folder; item 16a's hook cases (`v1-16a.1-hook-saida-ignorada`, `v1-16a.1-hook-sem-saida`) and README fixed point 59; item 9's workspace cases; `init-files`; `v1-15a.1-decide-antes-e-desfaz-escrita-no-meio`, `v1-15a.1-falha-preserva-config-simbolica`; `v1-58.plain`, `v1-58.kept`, `v1-58.rollback`; `v1-64.init-codex`, `v1-64.init-claude`, `v1-64.init-gemini`, `v1-64.init-none`, `v1-64.init-preserve`; item 25's closing lines; item 67's and 68's init cases.
7. **Measure and revert.**
   - **Metric:** on the Forge's layout, `init` writes no per-suite check and `[build]` covers every package; 0 adopter suites refused with TS6310 over the next 5 adopter inits.
   - **Revert:** a release restores the check; projects keep their config.
8. **Known limits.**
   - Without a written `[build]`, the kept `tsc --noEmit` on a solution tsconfig checks nothing (item 56's second line says so); the user sets the project's own type-check command. This item does not change that.
   - The hook does not run `[build]`, so a type-only error in a covered folder is caught by `red`'s first run or `ci`, not at commit, as for any `[build]` today.
   - A project whose `[build]` is later edited by hand to cover fewer folders keeps no check for the folders it dropped; `init` does not rewrite an existing config.

### `init` for a project-local install (item 58)

Before item 58, `init` wired the hooks to the binary that ran it: plain git hooks named its absolute path, and lefthook, husky and the pre-commit framework a bare `shipcraft` found on `PATH`. Every project on a machine then used the machine's one binary. Upgrading it upgraded every project at once and without a commit: draken-platform ran three versions in one day (2026-10-28) while its owner believed it was on 2.11.0. A Node project can instead pin Shipcraft as a dev dependency (`pnpm add -D shipcraft`), so the version is in its lockfile.

- **When the install is the project's.**
  - `init` canonicalizes two paths with the filesystem (symlinks resolved): the binary running it, and the repository's working-tree root as `git rev-parse --show-toplevel` gives it.
  - The install is the project's when the binary's path, compared component by component, is under `<root>/node_modules/`, and `<root>/node_modules/.bin/shipcraft`, with symlinks followed, is a regular file the user can execute.
  - Otherwise the hooks are wired as today, and nothing new is printed: an install elsewhere (`install.sh`, `cargo install`), a path that cannot be canonicalized, or a `.bin/shipcraft` that is missing, not a regular file or not executable.
  - An install under a package's `node_modules` (`packages/x/node_modules`) also keeps today's wiring, with one line: `shipcraft: installed under <dir>/node_modules; hooks call this binary by its path (only the root node_modules is wired as the project's)`.
- **What `init` writes then.** These are new integrations only. Integrations that already exist are kept as today.
  - **Plain git:**
    - The `commit-msg` hook runs `"$(git rev-parse --show-toplevel)/node_modules/.bin/shipcraft" check --commit-msg "$1"`. When that file is not executable, it prints `shipcraft: not installed in this checkout (node_modules/.bin/shipcraft): install the project's dependencies` and exits `1`: the commit is refused.
    - The `post-commit` hook runs `"…/node_modules/.bin/shipcraft" close`. When that file is not executable, it prints `shipcraft: not installed in this checkout (node_modules/.bin/shipcraft): the lock stays open; install the project's dependencies and run node_modules/.bin/shipcraft close` and exits `0`, as `close` does.
    - Both keep the `# shipcraft hook` marker.
  - **lefthook, husky 9, pre-commit framework:** the same commands as today, with `shipcraft` replaced by `./node_modules/.bin/shipcraft`, each tool forwarding the message file as today.
  - Before its closing guidance lines (items 25 and 27), `init` prints `shipcraft: hooks call this project's install (node_modules/.bin/shipcraft); upgrade it with your package manager`. It prints this only when it wrote these hooks.
- **Recognition.** `status` and a repeated `init` recognize the generated commands in both forms, `shipcraft …` and `./node_modules/.bin/shipcraft …`, and the plain hooks in both forms. They do so whether or not the dependencies are installed when they look. This is the one change outside `init`.
- **Unchanged.**
  - `shipcraft_min` is still written as the running binary's `major.minor`.
  - Every other command, the run log, and the hooks and configs of projects already integrated.
  - To move an integrated project to its own install, remove the old hooks and run `init` again.
- **Known limits.**
  - **Clones need their own `init`.** A clone does not receive `.git/hooks`. Each clone runs `init` once (or the hook manager's install) after installing its dependencies. Until then nothing runs at commit, and CI is the backstop, as for any clone today.
  - **Node at commit time.** The package's `.bin/shipcraft` is a Node launcher, so the project-local install needs Node when committing.
  - **Linked worktrees share one hook folder.** That works when every worktree has its own `node_modules` at its root, which a package manager install gives.
  - **The launcher and the binary can differ.** `.bin/shipcraft` is whatever the package manager linked there. If a nested dependency carries a different version, the hooks call the root one, not necessarily the one that ran `init`.
  - **Hook managers that run from another folder.** A manager that does not run hooks from the repository root does not find the relative path; lefthook's `root:` option is one case.

### Onboarding the coding agents (item 61)

POC-021 (2026-10-29, Shipcraft 2.14.0 from npm) asked Claude Code and Codex, in a fresh session each, to install Shipcraft in two sample projects and then add a small feature. No run closed a cycle. 3 of 4 runs stopped at `pnpm add -D shipcraft` and never ran `init`; each checked the install with `shipcraft --version` or `--help`. In the one run where `init` wrote the `AGENTS.md` block, Claude ran `red` unprompted, citing the block, but did RED and GREEN in one session and committed nothing. Item 61 changes what those touch points say.

**Reading the two files.** `AGENTS.md` and `CLAUDE.md` at the repository root are read as UTF-8; a file that is not valid UTF-8 is a read failure (kept, with today's notice). A *line* ends at `\n`; a line *is a marker* when, without a trailing `\r`, it equals `<!-- shipcraft -->` (the start line) or `<!-- /shipcraft -->` (the end line) exactly, wherever it is (inside a fenced code block too). A *block* is the bytes from the first byte of a start line through the end of the next end line, its `\n` included when present.

- **The block asks for separate sessions and commits.**
  - The new block is the text below `AGENTS_BLOCK` in `nucleo/src/init.rs`, from a start line to an end line, LF line endings. Besides today's rules it says, in this order:
    - the RED and the GREEN are done by different agent sessions: in Claude Code a subagent per phase, in Codex a new `codex exec` session per phase (never `resume`), both in the same checkout;
    - the RED session commits the tests, the stubs they need and the lock in one commit, and stops;
    - the GREEN session starts from that commit, may change anything the open lock does not protect (product code, dependencies and their lockfiles, config), never a locked file, and commits; a test it finds wrong is reported back, and a RED session fixes it with `red --redo` (item 46);
    - a session told it is the RED or the GREEN does that phase only and starts no other session; the session the user talks to starts them;
    - today's rule on locks reads: never edit or delete `.shipcraft/locks/*` by hand (`shipcraft red`, `red --redo` and the hook write them).
  - **The command it names.** When `init` runs from a project-local install (item 58's rule), every `shipcraft` command in the block is written `npx -- shipcraft` (fixed point 39's `--`), and the block says to run Shipcraft commands from the repository root, where `npx` resolves the root install item 58 wires the hooks to; otherwise `shipcraft`. These are the block's two *current variants*.
  - **Known blocks.** The current variants, plus the 2.14.0 block: the exact bytes of `AGENTS_BLOCK` at tag `v2.14.0`, which has a start line and no end line. Each is kept in the binary.
  - **What `init` does with `AGENTS.md`.**
    - No start line: the new block is appended, with today's separator rule (or the file is created).
    - Exactly one start line, followed by exactly one end line and no other marker, and the block between them byte-equal to a known block: the block is replaced by the new one; every byte before and after is kept. Equal to the new block: kept, `already has the shipcraft block`, as today.
    - Exactly one start line, no end line, and the bytes from the start line equal to the 2.14.0 block followed by anything: those bytes are replaced by the new block; what follows is kept.
    - Anything else (more markers, a block that is not a known one, an edited 2.14.0 block): kept, with today's `already has the shipcraft block, kept` plus `; it differs from this version's: edit it by hand to match docs/spec.md`.
    - A symlink or any entry that is not a regular file, and read or write failures: as today (kept, notice, never failing the init).
    - **Writing.** A new file is created as today. An existing file is rewritten through a temporary file in the same folder, given the old file's permission bits, then renamed over it; any failure removes the temporary file and leaves the old bytes. A file whose permission bits forbid the owner to write is kept, with the write-failure notice.
- **`CLAUDE.md` imports the block.** Claude Code reads `CLAUDE.md`, and reads another file through an `@path` import line.
  - `init` handles `CLAUDE.md` at the repository root when an entry exists there (`lstat` succeeds: a symlink, dangling or not, counts and is then kept as `AGENTS.md`'s are; `lstat` failing with anything but not-found also counts, and the entry is kept with the read-failure notice), or when `claude` is found on `PATH` by the same lookup `init` uses to find review agents (checked on its own, whatever `[roles] review` is).
  - Its block is three lines: the start line, `Shipcraft workflow (required): @AGENTS.md`, the end line. The rules are `AGENTS.md`'s with this block as the only known block: created, appended, kept equal, kept different with the notice.
  - `CLAUDE.md` is handled only when `AGENTS.md` is a regular file that holds the current block after `init` (written now or already equal); a symlinked `AGENTS.md` never qualifies. Otherwise `init` leaves `CLAUDE.md` untouched and, only when `CLAUDE.md` is handled by the rule above, prints `shipcraft: CLAUDE.md not written: AGENTS.md does not hold this version's shipcraft block`.
  - `init`'s closing line lists each of the two files it created, appended to or replaced, as it lists `AGENTS.md` today.
- **`--version` and usage say when the config is missing.** After their usual output, `shipcraft --version` and the usage (no arguments, `help`, `-h`, `--help`) print one line to stderr when the current folder is inside a git work tree (`git rev-parse --show-toplevel` succeeds) and `lstat` of `.shipcraft.toml` at its root fails with not-found: `shipcraft: not set up in this repository: run shipcraft init (from a package install: pnpm exec shipcraft init, or npx shipcraft init)`. In every other case (outside a work tree, git fails, the entry exists in any form, `lstat` fails otherwise) nothing is added. They read no config and write no run-log row; their stdout and exit codes do not change.
- **Docs.** The README's quick start and the npm package README say that installing is two steps: add the package, then run `init`.

**Unchanged.** The block's existing rules, the hook, `red`, every refusal, the config `init` writes, and `init`'s refusals: a refused `init` writes neither file.

**Battery.**
- `v1-2.5-agents-novo`, `v1-2.5-agents-acrescenta`, `v1-2.5-agents-uma-vez` and `v1-2.5-agents-link` must hold.
- `python::init-files`, `node::init-files` and `go::init-files` (`acceptance/run.sh`) reject any file `init` writes besides `.shipcraft.toml`, the locks folder and `AGENTS.md`, and keep the caller's `PATH`: on a machine with `claude` on `PATH`, `init` now writes `CLAUDE.md`. The RED makes them independent of the machine (a `PATH` without `claude`, or `CLAUDE.md` allowed when it is on `PATH`), without weakening the rest.
- `v1-21.versao-fora` and `v1-21.versao-min-numerica` run `--version` outside a repository and must hold.

**Versions.** The item raises the binary to 2.17.0. No lock or config field changes.

**Known limits.**
- Whether an agent follows the block is measured by POC-021's after runs, not by the battery.
- Codex and other agents read `AGENTS.md` directly; an agent that reads neither file is not covered.
- A `CLAUDE.md` in a subfolder, or a user-level `~/.claude/CLAUDE.md`, is not read or written.
- A block edited by hand, or written with CRLF line endings, is never upgraded.
- Markers inside a fenced code block count as a block. A `CLAUDE.md` whose only import block sits inside a fence is kept, and Claude Code, which skips imports in code blocks, does not read `AGENTS.md` through it.
- The hint covers a repository with no config. A fresh clone of a project that has one, but whose hooks are not installed yet, gets no hint; CI is the backstop, as today.
- `npx -- shipcraft` needs Node at the agent's shell, as item 58's hooks do, and resolves the root install only from the repository root; an agent that runs it inside a workspace package with its own older install gets that one.

### The block carries the flow's rules, and `init` installs the phase briefs (item 68)

Three rules that make our own RED/GREEN cycle work lived only in our private process notes, so an adopter's agents never saw them:
- **Read the tests the change touches.** All 5 wrong RED tests of items 64 to 66 contradicted behavior an earlier test had already fixed.
- **A wrong locked test goes to a new RED session that does not see the GREEN's code.** A test fixed while looking at the implementation tends to fit the implementation.
- **Start each phase with the role the project chose** (item 64's `[roles]`).

Victor's instruction for the dogfood was "the rules in the product, not in memory". Item 68 puts these rules in the `AGENTS.md` block, and gives each phase a short brief that `init` installs in the project.

1. **The new block.** The current variants of item 61's block (the `shipcraft` and `npx -- shipcraft` forms) change as follows. Every other line stays, in its order. Below, `<cmd>` is `shipcraft`, or `npx -- shipcraft` in the local variant, as item 61 writes every command.
   - After the line about writing the failing test first, a new line: `- Before writing a RED test, read the existing tests that cover the behavior you change, and never contradict them unless the change says that behavior changes. Passing control tests next to the failing ones are fine.`
   - The GREEN line's ending, `A test it finds wrong is reported back, and a RED session fixes it with \`<cmd> red --redo\`.`, becomes: `A test it finds wrong is reported back with the reason. The session the user talks to sets the GREEN's work aside (\`git stash push --include-untracked\`; it saved something only if \`git rev-parse -q --verify refs/stash\` changed, and \`git status --porcelain\` must then print nothing), starts a new RED session given the intent, the test and that report, never the GREEN's code, which fixes the test with \`<cmd> red --redo\` and commits; then, if something was saved and \`refs/stash\` still names it, it restores it with \`git stash pop\`; if nothing was saved, nothing is restored. If the GREEN already committed code after the RED commit, the work cannot be set aside, a step fails, or the restore conflicts, it stops, keeps the stash, and tells the user. If the repair would leave every locked test passing, or renames a test, \`red --redo\` refuses: report it to the user.`
   - After the line `A session told it is the RED or the GREEN ...`, a new line: `- Start each phase with the agent, model and effort that \`<cmd> status\` names on its roles line ([roles] red and green), when the project set them; if status refuses or that agent is not available, tell the user instead of choosing another. Each phase follows its brief in .shipcraft/briefs/ (red.md, green.md); where a brief is missing or disagrees with this block, this block wins.`
2. **Known blocks.** The two variants item 61 wrote (the exact bytes of both current variants at tag `v2.22.0`) join the known blocks, so `init` replaces them with the new block under item 61's rules. The 2.14.0 block stays known, and every other case is unchanged. `CLAUDE.md`'s block does not change.
3. **The phase briefs.**
   - **The files.** `init` writes two files, `.shipcraft/briefs/red.md` and `.shipcraft/briefs/green.md`. Their text is built into the binary, in a `shipcraft` and an `npx -- shipcraft` variant chosen as item 61 chooses the block's (`<cmd>` below). They use LF line endings and end with a newline. Their last line is `<!-- written by shipcraft X.Y.Z -->`, with the full package version, without the build hash.
   - **The RED brief says:**
     - write the failing tests from the intent, never from an implementation;
     - write two cases per rule, the ordinary one and a boundary a rushed GREEN would get wrong;
     - read the existing tests that cover the behavior the change touches first, and never contradict them unless the intent says that behavior changes;
     - each test written for the new behavior must fail for the right reason before `<cmd> red`; passing control tests are fine and are locked as controls;
     - fake external tools with their real output;
     - commit the tests, their stubs and the lock in one commit, and stop;
     - list ambiguities instead of picking a reading silently.
   - **The GREEN brief says:**
     - start from the RED commit;
     - never edit a locked file or a lock;
     - change product code, dependencies or config until the locked tests pass;
     - running the other tests the change touches is a check, not a gate: report a failure outside the locked tests, and let the hook's verdict decide the commit, since CI runs the rest;
     - stop and report a test that looks wrong, with the reason, instead of working around it;
     - commit.
   - **Writing them.** For each file:
     - absent: it is written;
     - a regular file whose bytes equal the built-in text of either variant: kept;
     - a regular file that reads as UTF-8 with other text: kept, with `shipcraft: .shipcraft/briefs/<name> differs from this version's, kept: compare it with docs/spec.md`. No marker in it is read, and nothing is appended;
     - a file that is not valid UTF-8, a symlink, an entry that is not a regular file, or a read failure: kept, with `shipcraft: .shipcraft/briefs/<name> could not be read, kept`.
   - **When.** The briefs are written only after everything else `init` writes has succeeded, `.shipcraft/locks` included. A failure before that point is today's failure: the same exit, the same rollback, and no brief written. A blocking `.shipcraft` file stays fatal, as items 25, 58, 61 and 67 require.
   - **The folder.** `.shipcraft` and `.shipcraft/briefs` are each checked with `lstat` and never followed. A symlinked `.shipcraft` that `init` accepted for the locks still gets no briefs. If either is a symlink or not a folder, a check fails with an error other than not-found, or it cannot be created, neither brief is written, and `init` prints `shipcraft: .shipcraft/briefs not written: <reason>`.
   - **A write failure.** Writing goes through a temporary file in the same folder, renamed into place. If writing a brief fails, the old file, if any, keeps its bytes; the temporary file and any partly written new file are removed; `init` prints `shipcraft: .shipcraft/briefs/<name> not written: <reason>` and goes on with the other brief.
   - **What never fails `init`.** No brief case above (the folder, a kept file, a write failure) changes `init`'s exit or rolls back what it wrote: it goes on, and exits as it would have.
   - **The closing guidance.** It names each brief `init` wrote, inside the existing `shipcraft: ready. Commit ...` line, after `AGENTS.md` and `CLAUDE.md`, red before green. No line is added, and the final CI line stays last.
   - **No special status.** The briefs are ordinary project files, versioned with the project. When a suite's globs select them, they are locked like any other selected file. This item changes no lock rule.
   - **`--lang other`** (item 67) writes them too.
4. **Touches.** These earlier items' cases cover what this item shares or changes.
   - **Assertions that change, and nothing else:**
     - item 61's expected block text and its new known-block upgrades (`v1-61.*`, `acceptance/lib/item61.sh`, `pontos/61.md`);
     - the untracked-files allowlist of `python::init-files`, `node::init-files` and `go::init-files` (`acceptance/run.sh`), which gains exactly the two brief paths;
     - the new-files allowlist of item 67's successful-init cases (`acceptance/lib/item67.sh`, from `v1-67.plain` to `v1-67.no-report-exit`), which gains exactly the two brief paths.
   - **Must keep passing unchanged:**
     - `v1-2.5-agents-novo`, `v1-2.5-agents-acrescenta`, `v1-2.5-agents-uma-vez`, `v1-2.5-agents-link`;
     - item 64's `init-*` and `status-*` cases (the roles line the block points to);
     - `v1-27.mensagem-local`, `v1-27.mensagem-desligado`, `v1-27.mensagem-github` (the CI line stays last), and item 25's closing lines;
     - the rollback cases `v1-20.rollback`, `v1-25.husky.rollback`, `v1-25.pre.rollback`, `v1-61.refused-late`, `v1-67.rollback`, `v1-67.rollback-kept`, item 15a's (`v1-15a.1-*`) and item 58's `v1-58.rollback`, `v1-58.lefthook.rollback`, `v1-58.husky.rollback`, `v1-58.pre.rollback`: a refused `init` writes no brief;
     - item 67's refusal cases;
     - item 46's redo cases, which define the limits the block now names.
5. **Measure and revert.**
   - **Metric:**
     - for an adopter, wrong locked tests fixed by a new RED session with the GREEN's work set aside, rather than by the session that saw the code, counted in draken-platform's next 5 items;
     - for a fresh agent, POC-021's "after" run: does it read the touched tests, and does it hand a wrong test to a new RED?
   - **Threshold:** in POC-021's after run, both behaviors are observed in at least 1 of 2 runs per agent.
   - **Revert:** a release drops the block's new lines and the briefs. Projects keep the files they have.
6. **Known limits.**
   - The battery checks the text written, not whether an agent follows it.
   - Setting work aside with `git stash` hides it from the new RED's checkout, but not from someone who goes looking in the stash. Ignored files (build output) stay in the checkout.
   - A GREEN that committed code before finding the wrong test cannot hand it to a new RED this way; the user decides.
   - A project that edited its block or its briefs keeps its own text.
   - Briefs written by an older version are not upgraded, because there is only one version so far.

### `init` is the required next step after install (item 69)

POC-021's after runs on 2.24.0 (2026-10-30): `init` ran in 3 of 4 runs, against 1 of 4 before item 61. In the fourth, Codex added the package with `pnpm add -D shipcraft`, checked it, reported "setup is available via pnpm exec shipcraft init", and stopped. Item 61's hint names `init` as a possibility, with two commands to choose from and an `npx` without `--` (fixed point 39). This item makes it one command, said as the required next step.

1. **The hint.** The conditions are item 61's, unchanged: `shipcraft --version` and the usage (no arguments, `help`, `-h`, `--help`), inside a git work tree whose root has no `.shipcraft.toml` (`lstat` fails with not-found). The root is read as today's hint reads it: the bytes of `git rev-parse --show-toplevel`, less exactly one final newline, as a Unix path; a failed or empty output prints no hint. The line stays one line on stderr, after the usual output. Its text changes to:

   `shipcraft: next step (required): run `<command>` at the repository root to set up Shipcraft; until init runs, Shipcraft checks none of your commits; if init refuses, follow its Next line`

   with one pair of backticks around `<command>`, which is chosen as follows:
   - when the running binary is the project's install, by item 58's rule as `init` applies it (the binary and the root canonicalized; the binary under `<root>/node_modules/`, a pnpm store path under it included; `<root>/node_modules/.bin/shipcraft` an executable regular file, its link followed):
     - `pnpm exec shipcraft init` when `<root>/pnpm-lock.yaml` is a regular file (`lstat`, never followed, never read) and `pnpm` is found on `PATH` by the lookup `init` uses for review agents;
     - `npx -- shipcraft init` otherwise;
   - `shipcraft init` in every other case: a machine install, a binary inside a package's own `node_modules` or outside the root, or any failure to resolve the binary or the root.

   A failure while deciding whether the binary is the project's install selects the `shipcraft init` form. Once it is the project's install, a missing, non-regular or unreadable `pnpm-lock.yaml`, or `pnpm` not found (a lookup error counts as not found), selects the `npx -- shipcraft init` form. None of this prints a notice, creates a file or folder, runs a test, check, build or reviewer, or changes stdout or the exit code.
2. **No install script.** The npm packages keep running nothing at install time. pnpm runs no dependency scripts unless they are allowed, and `--ignore-scripts` is common, so a message printed from a script would reach only some installs. The hint and the docs are the touch points.
3. **Docs.**
   - The README's quick start says step 2 is required, right after step 1: `init` sets up Shipcraft and wires its hooks, and until it runs Shipcraft checks none of your commits. Its commands use `pnpm exec shipcraft init` or `npx -- shipcraft init`.
   - `npm/README.md` says the same, and its `npx` gains `--`. The npm package keeps carrying the root `README.md`, as `release/npm.sh` packages it today.
4. **Current behavior** on the paths this item touches (rule 14):
   - `--version` prints `shipcraft X.Y.Z (<hash>)` to stdout and exits 0: keep.
   - The usage prints to stdout and exits 0: keep.
   - The hint's conditions, its root reader, its one line on stderr after the output, no config read, no run-log row, and no file written: keep. Its text: change, as in point 1.
   - Outside a work tree, when git fails, or when `.shipcraft.toml` exists in any form (a symlink, a folder, an invalid file), no hint is printed: keep.
   - Invalid arguments print `shipcraft: error: invalid arguments: ...` with the usage, with no hint, and exit 2: keep.
   - The npm packages declare no install script: keep.
   - The Node launcher: it prints nothing of its own when the native binary runs; a missing platform package prints its platform diagnostic and exits 2; a spawn failure prints `could not run ...` and exits 2; a native signal is passed on, and any other status returned (a missing status exits 1): keep. The hint is printed by the native binary only, so a launcher that fails before running it prints no hint.
   - `init`'s own output, its refusals (item 67's `lang-unrecognized` and `lang-multiple` included), item 58's install detection and the commands the hooks call: keep.
5. **Touches.**
   - **Assertions that change:**
     - item 61's expected hint text (`HINT` in `acceptance/lib/item61.sh`) and its fixed point (`acceptance/pontos/61.md`), for `v1-61.hint-version`, `hint-noargs`, `hint-help`, `hint-h` and `hint-longhelp`. Their binary runs from outside `node_modules`, so the expected text is the `shipcraft init` form;
     - `v1-61.hint-outside`, which today checks that `HINT` is absent: it checks that neither the old text nor the new form is printed.
   - **Must keep passing unchanged:**
     - `v1-61.hint-config`, `v1-61.hint-git-fails`;
     - the version line, read from `nucleo/Cargo.toml`: `v1-21.versao-fora`, `v1-21.versao-min-numerica`, `v1-62.version`, `v1-63.version`, `v1-64.version`, `v1-67.version`, `v1-65.main` and `v1-65.many` (every profile), and item 66's cases (the shared `--version` check at the end of their driver);
     - item 58's install cases (`v1-58.*`): the same rule decides the install.
6. **Measure and revert.**
   - **Metric:** in POC-021's next after runs, every run executes `init` (4 of 4).
   - **Revert:** a release that restores item 61's text.
7. **Known limits.**
   - Yarn and Bun projects get the `npx -- shipcraft init` form, which also works there when Node is installed.
   - The `pnpm exec` form is chosen from a lockfile and a `PATH` lookup; it does not prove this contributor installed Shipcraft with pnpm.
   - In a layout plain `init` cannot recognize (item 67), the command starts setup and `init` refuses with the flags to add.
   - A binary installed inside a package's own `node_modules` gets `shipcraft init`, which may not be on `PATH`. `init` itself says how that install is wired.
   - An agent that never runs `--version` or `--help`, and never reads the README, is not reached.

### A path when a phase's session cannot be started (item 70)

POC-021's after runs on 2.25.0 (2026-10-31): Codex, running in its `workspace-write` sandbox, tried to open the RED session the block asks for with a nested `codex exec`, which failed with `Operation not permitted`, and stopped. Stopping was right: doing the RED in its own session would break the block's rule. But it stopped without telling the user how to go on, so the cycle ended there. This item adds the missing path to the block.

1. **The new line.** The current variants of item 68's block (the `shipcraft` and `npx -- shipcraft` forms) gain one line, right after the line that starts `- Start each phase with the agent, model and effort`. Every other line stays, byte for byte, in its order. In the machine variant the line is:

   ``- If you cannot start a phase's session (your tool cannot start one, or the start is refused, for example a sandbox refusing a nested `codex exec` with `Operation not permitted`), never do that phase yourself: stop and give the user the exact command to paste in a POSIX shell (sh, bash, zsh) where this project's tests run. It starts with `cd` to this checkout's absolute path, then starts a new session (an interactive one counts) with the agent, model and effort `shipcraft status` names for the phase (`shipcraft status` must exit 0; a GitHub lookup notice is fine), each flag left out when not set (none named: the agent you would have started; another agent: its own command and flags), and a prompt that names the phase, its brief and the change; for a wrong-test repair, the test, the GREEN's report and `shipcraft red --redo`, after the GREEN's work is set aside as above. Write each argument you fill in (the path, the model, the effort, the prompt) in single quotes, each `'` in it written `'\''`, for example `cd '<checkout>' && codex -m '<model>' -c 'model_reasoning_effort=<effort>' 'You are the RED session. Follow .shipcraft/briefs/red.md. The change: <intent>'` or `cd '<checkout>' && claude --model '<model>' --effort '<effort>' 'You are the GREEN session. Follow .shipcraft/briefs/green.md. The change: <intent>'`. That session still does its phase only. If the failed start may have begun the session (it printed output of its own, or a new lock or commit appeared), say so instead of giving a command. Continue only when the user says it finished and the phase's commit is on this branch; if it is not, tell the user.``

   The outer double backticks above only quote the line; the block holds it from `- If` to `tell the user.`, one line, ending with `\n`. `<checkout>`, `<model>`, `<effort>` and `<intent>` are literal text in the block, and `'\''` is those four characters. The local variant is built by item 61's rule unchanged: every `` `shipcraft `` becomes `` `npx -- shipcraft ``, so the line names `npx -- shipcraft status` and `npx -- shipcraft red --redo` there; `codex` and `claude` are not changed. Item 61's root line stays where that rule puts it.
2. **Known blocks.** The two current variants at tag `v2.25.0` (the exact bytes `init` 2.25.0 writes, machine and local) join the known blocks, so `init` replaces them with the new block under item 61's rules: kept bytes before and after, mode kept, the temporary-file write. The v2.22.0 variants and the 2.14.0 block stay known and are now upgraded to the new block. Every other case is unchanged (an edited block is kept with the differs notice). `CLAUDE.md`'s block does not change.
3. **The briefs do not change.** `.shipcraft/briefs/red.md` and `green.md` keep item 68's body and its rules. Their last line keeps naming the running version, as item 68 writes it, so a 2.26.0 `init` writes `<!-- written by shipcraft 2.26.0 -->` and keeps an unedited 2.25.0 brief with item 68's differs notice, as any version change does today. A session told it is the RED or the GREEN starts no other session, so the path belongs to the session the user talks to, which reads the block.
4. **Current behavior** on the paths this item touches (rule 14):
   - `init` creates `AGENTS.md` with the block, appends it once, replaces a known block, keeps an equal block with `already has the shipcraft block`, and keeps anything else with the differs notice; symlinks, non-regular files, invalid UTF-8 and read or write failures are kept with today's notices and never fail the init: keep. The block's text: change, as in point 1. The set of known blocks: change, as in point 2.
   - `CLAUDE.md`'s import block, when it is handled and the `CLAUDE.md not written` notice: keep. `CLAUDE.md` is still handled only when `AGENTS.md` holds the current block after `init`, which is now the new block.
   - The briefs: their paths, body, the version-derived last line, the byte comparison against this version's text, folder checks, notices and the rule that they never fail `init`: keep.
   - `shipcraft status`, which the new line asks the session to read: it reads the working-tree config, prints the branch, layers, roles, hooks and open-lock lines, reads the locks, asks GitHub about branch protection and prints its answer or a lookup notice; it starts no agent and runs no test; a config it cannot read refuses before the roles line; a lock folder or file it cannot read fails after the roles line with `shipcraft: error: ...` and exit 2, and a lock in a format it does not know refuses after the roles line with exit 1, the earlier lines already printed in both cases; a lock that does not parse is listed as open and status exits 0; it writes no file and no run-log row: keep.
   - The closing guidance (`shipcraft: ready. Commit ...` with `AGENTS.md`, `CLAUDE.md` and the briefs listed when written, the final CI line last): keep.
   - `init`'s exit codes, refusals and rollbacks (a refused `init` writes neither file nor any brief): keep.
   - `init`'s other output, the config it writes, the hooks and item 58's install detection: keep.
5. **Touches.**
   - **Assertions that change, and nothing else:** the expected block text, which gains the line of point 1 in both variants, in item 68's block cases (`v1-68.block`, `block-local`, `block-append`, `block-local-append`), its upgrade cases from v2.22.0 (`v1-68.upgrade-{bare,local}-{bare,local}`) and from 2.14.0 (`v1-68.legacy`, `legacy-local`), and item 61's exact-text checks in `v1-61.block` and `v1-61.local-block` (`acceptance/lib/item61.sh`, `acceptance/lib/item68.sh`, `pontos/61.md`, `pontos/68.md`).
   - **The version:** `v1-62.version` and the other version cases item 69 lists read §11's contract, now 2.26.0, and the binary's version: the release raises `nucleo/Cargo.toml` to 2.26.0, and those cases keep their assertions.
   - **New cases:** upgrades from the v2.25.0 variants in both directions (bare and local input, bare and local install), keeping item 68's checks on prefix and suffix bytes, mode and the `CLAUDE.md` import.
   - **Must keep passing unchanged:** every other `v1-68.*` case (the briefs, their folder and write-failure cases, the closing lines, the `equal-*` cases, `core-*`); every other `v1-61.*` case; `v1-2.5-agents-novo`, `v1-2.5-agents-acrescenta`, `v1-2.5-agents-uma-vez`, `v1-2.5-agents-link`; `python::init-files`, `node::init-files`, `go::init-files`; item 67's successful-init cases and their allowlists; item 64's `init-*` and `status-*` cases; item 62's and item 5's status cases (`v1-62.status`, `v1-62.status-empty`, `v1-5.4-status-nivel-de-protecao`); item 25's closing-line cases (`v1-25.*`), which item 68 also kept; item 46's redo cases (`v1-46.*`), whose limits the line's repair path relies on; `v1-27.mensagem-local`, `v1-27.mensagem-desligado`, `v1-27.mensagem-github`; the rollback cases item 68 lists.
6. **Measure and revert.**
   - **Metric:** in POC-021's next after runs, no run stops without telling the user how to continue: every run that cannot start a phase's session gives the user a command to paste for that phase.
   - **Threshold:** 0 runs that stop silently, against 1 in the 2.25.0 after runs.
   - A run whose failed start may have begun the session counts as telling the user when it says so instead of giving a command.
   - **Revert:** a release drops the line. Its block joins the known blocks so `init` upgrades it back.
7. **Known limits.**
   - The battery checks the text written, not whether an agent follows it.
   - The example commands are examples: their flags belong to Codex and Claude Code and may change; the agent adapts them to what `status` names.
   - The user starts the phase by hand, so the session that asked cannot check the phase was run with the role `status` names.
   - The command carries the folder, not the shell environment (a virtualenv, a Node version manager, `GOWORK`): the line asks for a terminal where the project's tests run, and a wrong one makes the phase fail or refuse, not pass.
   - A project that edited its block keeps its own text.
### `red` and the commit run outside an agent's sandbox (item 74)

Our own items 70 to 73 (2026-10-31): the Codex RED ran in its `workspace-write` sandbox. There `shipcraft red` took 2919 s for 113 cases, against 42 to 213 s outside it. The sandbox forbids `nice`, and git could not write its index lock in a linked worktree, so the RED could not commit. Item 70's line covers a phase session that cannot be started, not a session that runs but sits in a sandbox. An adopter's sandboxed agent hits the same wall at `red` or at the commit, whose hook runs the locked tests. This item adds the path to the block.

1. **The new line.** The current variants of item 70's block (the `shipcraft` and `npx -- shipcraft` forms) gain one line, right after item 70's line (the one that starts `- If you cannot start a phase's session`). Every other line stays, byte for byte, in its order. In the machine variant the line is:

   ``- If you run in a sandbox (for example Codex's `workspace-write`), run `shipcraft red`, `shipcraft red --redo` and `git commit` (its hook runs the locked tests) outside it: inside, they can take many times longer, or fail when git cannot write its index. If you cannot leave the sandbox, write and check the tests or the code, then stop and give the user the exact commands to paste: `cd` to this checkout's absolute path, then the `shipcraft red` (or `shipcraft red --redo`) and `git add` and `git commit` with the files you changed and the lock, each argument you fill in written in single quotes as above. Change nothing after handing them over; continue when the user says they finished and the commit is on this branch.``

   The outer double backticks only quote the line; the block holds it from `- If you run` to `on this branch.`, one line, ending with `\n`. The local variant is built by item 61's rule unchanged: every `` `shipcraft `` becomes `` `npx -- shipcraft ``, so the line names `npx -- shipcraft red` and `npx -- shipcraft red --redo` there; `git` is not changed. Item 61's root line stays where that rule puts it.
2. **Known blocks.** The two current variants of item 70's block join the known blocks: the exact bytes `init` writes at commit e642432 (item 70's merge, version 2.26.0, unchanged through 2.29.0), machine and local. `init` replaces them with the new block under item 61's rules: kept bytes before and after, mode kept, the temporary-file write. The v2.25.0, v2.22.0 and 2.14.0 blocks stay known and are now upgraded to the new block. Every other case is unchanged (an edited block is kept with the differs notice). `CLAUDE.md`'s block does not change.
3. **The briefs do not change.** `.shipcraft/briefs/red.md` and `green.md` keep item 68's body and rules, and their last line keeps naming the running version, as item 70 says.
4. **Current behavior** on the paths this item touches (rule 14): item 70's list, point 4, unchanged in every entry, with these two readings:
   - the block's text: change, as in point 1;
   - the set of known blocks: change, as in point 2.
5. **Touches.**
   - **Assertions that change, and nothing else:** the expected current block text, which gains the line of point 1 in both variants, wherever an earlier case builds it:
     - item 61's exact-text checks (`v1-61.block`, `v1-61.local-block`);
     - item 68's block, upgrade and legacy cases (`v1-68.block`, `block-local`, `block-append`, `block-local-append`, `upgrade-{bare,local}-{bare,local}`, `legacy`, `legacy-local`);
     - item 70's block and upgrade cases (`v1-70.block-{bare,local}`, `upgrade-{bare,local}-{bare,local}`, `upgrade-brief-fails-{bare,local}`, `write-fails-{bare,local}`, `write-partial-{bare,local}`) and its fixed points.
     The RED adjusts only the expected text: `acceptance/lib/item61.sh`, `item68.sh`, `item70.sh` and their `pontos`.
   - **The version:** `v1-62.version` and the other version cases item 69 lists read §11's contract, now 2.30.0; the release raises `nucleo/Cargo.toml` to 2.30.0.
   - **New cases:** upgrades from item 70's variants in both directions (bare and local input, bare and local install), keeping item 68's and item 70's checks on prefix and suffix bytes, mode and the `CLAUDE.md` import.
   - **Must keep passing unchanged:** every other `v1-70.*` case (`edited-*`, `refused-*`, `status-*`), and everything item 70's Touches list keeps.
6. **Measure and revert.**
   - **Metric:** in POC-021's next after runs, no sandboxed agent runs `shipcraft red` or a hooked commit inside its sandbox without saying so: each one runs them outside or hands the commands to the user.
   - **Threshold:** 0 RED phases over 600 s caused by a sandbox, in those runs and in our own next 5 items.
   - **Revert:** a release drops the line. Its block joins the known blocks so `init` upgrades it back.
7. **Known limits.**
   - The battery checks the text written, not whether an agent follows it.
   - Shipcraft does not detect a sandbox; the agent has to know it is in one.
   - A user who runs the handed-over commands is trusted to run them unchanged; the hook and `shipcraft/ci` still check the lock.

### Workspace suites run from the root when the root vitest config defines the projects (item 71)

Wrong-verdict note: since item 9 (2.0.0), `init` writes each Node workspace suite to run inside its package. Found on the Forge, the second adopter (2.25.0, deluge-forge-platform PR #805, 2026-10-31): its root `vitest.config.ts` carries the worker caps (pool options vitest reads only from the root config), a `globalSetup` that points `TMPDIR` at one folder per run and a guard against writes to the real home folder, and its `vitest.workspace.ts` lists one project per package. A run from inside a package skips all of them. The Forge rewrote every suite by hand to run from the root with `--project <name>`. The battery should have caught it: item 51's fixtures have a root workspace file, but they write `.shipcraft.toml` before `init`, so no case ran `init` on such a layout.

1. **Candidates.** `init` (no `.shipcraft.toml` yet, not `--lang other`) plans a Node workspace as item 9 does, and runner inference stays as today. The *candidates* are the planned suites whose runner is vitest. The probe below runs only when there is at least one candidate and the repository root holds at least one regular file (`lstat`, never followed) named `vitest.workspace.<ext>`, `vitest.projects.<ext>`, `vitest.config.<ext>` or `vite.config.<ext>`, `<ext>` one of `ts`, `mts`, `cts`, `js`, `mjs`, `cjs`, `json`. Otherwise every suite keeps today's form, `init` runs no vitest and prints nothing new. Jest suites are never candidates and get no new line.
2. **The probe.** `init` runs, once, from the repository root, `npx --no -- vitest list --filesOnly --json`, with the environment every command `shipcraft` starts gets (the one `init` received, less `SHIPCRAFT_CASES` and `SHIPCRAFT_FILES`, which `shipcraft` removes at start, section 6), stdin from `/dev/null`, stderr discarded, in its own process group. stdout is read while the command runs (no deadlock on a full pipe). The whole probe, reading included, has a 60 s limit; at the limit the group is killed. The probe runs after `[build]` is decided (item 16b's `tsc -b`) and item 56's judgement, and before `init` writes anything; a hook refusal that today happens before `[build]` still happens first, with no probe.
   - **The probe fails** when it cannot start, reading its stdout or waiting for it fails (no retry), it exits non-zero or by a signal, reaches the limit, or its stdout is not valid UTF-8, does not parse as a JSON array of objects each with a string `file`, or holds a `file` that is not an absolute path. Then every candidate keeps today's form, and no part of the answer is used.
   - **Reading an entry.** `projectName` is read when it is a string; any other value or its absence reads as the empty name. Each `file` is canonicalized; when that fails its path is used as given. The suite folder is the repository root canonicalized, joined with the suite's root. A file *belongs to* a suite when its path, compared component by component, lies under that folder.
3. **When a candidate converts.** A candidate converts to the root form when all of these hold:
   - at least one entry belongs to it, and all of its entries carry the same name `<project>`;
   - `<project>` is not empty, does not start with `-`, and is made only of `A-Z a-z 0-9 @ / . _ -`;
   - every entry whose name equals `<project>` ignoring ASCII case, in the whole answer, belongs to this suite (vitest 2.1 matches `--project` without regard to case, so `api` also selects a project `API`; a project that also lists files of another folder converts no suite);
   - the suite's folder path holds none of the characters `* ? [ ] { } ! ( )` and no control character, so the prefixed globs below read it literally.
   Every other candidate keeps today's form; its reason (point 5) is the first condition above, in this order, that fails.
4. **The root form.** For a converted suite with folder `<dir>`:
   - `root = "."`;
   - `command = "npx --no -- vitest run --project=<project> --reporter=default --reporter=junit --outputFile.junit={junit}"`: today's vitest command with `--project=<project>` right after `run` (one word, so vitest never reads the name as an option);
   - `globs`: each of today's globs for the suite, in today's order, prefixed with `<dir>/` (`**/*.test.*` becomes `<dir>/**/*.test.*`);
   - `check`: when today's form would write `<bin>tsc --noEmit` (after item 56's judgement), the root form writes `cd ./<dir> && npx --no -- tsc --noEmit`, `./<dir>` shell-quoted when it holds a character other than `A-Z a-z 0-9 / . _ -` (the `./` keeps `cd` from reading `CDPATH` or an option), so the check runs inside the package as today and finds the same `tsc` and the same tsconfig; no check when today's form writes none;
   - its name and its place in the suite order: as today.
   A workspace config with at least one converted suite is always written in the `[[suite]]` form, with every suite named, even when only one suite exists, so case ids keep their `<name>:` prefix.
5. **What `init` prints.** On stdout, after the `workspace node with N suite(s)` line, only when the probe ran:
   - the probe failed: one line `shipcraft: suites run inside their packages: \`vitest list\` <how>; the root vitest config does not apply to them`, `<how>` one of `could not start`, `could not be read` (reading its output or waiting for it failed), `exited <code>`, `was stopped by signal <n>`, `timed out after 60 s`, `printed no file list`;
   - otherwise one line per candidate, in suite order: converted, `shipcraft: suite <name> runs from the repository root with --project=<project>, so the root vitest config applies`; kept, `shipcraft: suite <name> runs inside its package: <why>`, `<why>` one of `vitest listed none of its files`, `vitest listed its files in more than one project` (files that all lack a name, or all have an empty one, fail the next condition instead and get its reason), `its vitest project name is not one shipcraft writes in a command`, `its vitest project also lists files outside it`, `its folder name cannot be written in a glob`.
   `<name>` and `<project>` are escaped as in item 52's lists.
6. **Current behavior** on the paths this item touches (rule 14):
   - Suite planning (item 9): one suite per workspace package with tests, named after its folder, `root` the package folder, globs relative to it, the vitest command with `npx --no -- `, the jest command, and `check = "<bin>tsc --noEmit"` where a `tsconfig.json` exists: keep for every suite that does not convert, and for every jest suite.
   - Runner inference (`Lang::profile`, vitest as the default without a runner dependency): keep.
   - A single-package (non-workspace) Node project, Python, Go, `--lang other`, and an existing `.shipcraft.toml` (not rewritten): keep, and no probe runs.
   - A config with exactly one suite at root `.` written in the top-level form: keep for non-workspace projects; change for a workspace with a converted suite, as in point 4.
   - `[build]` inference and its proof run, item 56's judgement and lines, and the order of their lines: keep.
   - Everything `init` writes and prints after planning: `.shipcraft.toml`, `.shipcraft/locks/.gitkeep` and its folders, the hooks (own hooks with their permission bits, lefthook, husky, pre-commit, and their installed or kept notices, item 58's project-local calls), the `shipcraft_min` raise, the reviewer choice and its notices, `--github` and its notices, the `AGENTS.md` block, the `CLAUDE.md` import, the briefs, the closing guidance with the CI line last: keep.
   - Exit codes, refusals, and the rollback on a failed write, which removes only the paths this run created: keep. Like `tsc -b`'s output today, anything the probe's vitest writes (a cache) is not removed.
   - `init` writes no run-log row: keep.
   - Downstream, for a converted suite: `red` and `ci` run its command and check from root `.` (the check entering the package with `cd`); a failing check still refuses before the tests with the same code, exit, stderr forwarding and CI `no-report` row, and its refusal text now quotes the new check and names root `.`: change, as point 4 implies. For a suite that does not convert: keep.
   - `shipcraft` removes `SHIPCRAFT_CASES` and `SHIPCRAFT_FILES` from its environment at start, so no command it starts inherits them (item 22): keep, and the probe gets that environment too.
7. **Touches.**
   - **Must keep passing unchanged:** item 9's workspace cases (`v1-9.1-init-pnpm`, `v1-9.1-init-workspaces-do-package-json`, `v1-9.1-init-go-work`, `v1-9.1-monorepo-casos-por-suite`), whose fixtures have no root vitest file, so no probe runs; item 12's and 13's node init cases (`v1-12.1-npx-tsc-com-traco`, `v1-12.1-todo-npx-com-traco`, `v1-13.1-init-*`); item 16b's (`v1-16b.1-*`); item 56's (`v1-56.*`, `v1-56.workspace` included); item 51's (`v1-51.*`), whose fixtures have a root `vitest.workspace.ts` but write `.shipcraft.toml` before `init`, so no probe runs; item 15a's (`v1-15a.1-recusa-antes-de-perguntar-e-escrever`, `v1-15a.1-decide-antes-e-desfaz-escrita-no-meio`, `v1-15a.1-falha-preserva-config-simbolica`); item 25's closing lines (`v1-25.*`); item 27's (`v1-27.monorepo`, `v1-27.mensagem-local`, `v1-27.mensagem-desligado`, `v1-27.mensagem-github`); item 58's (`v1-58.plain`, `v1-58.kept`, `v1-58.rollback`); item 62's (`v1-62.init`, `v1-62.init-preserve`); `v1-53.environment`, `v1-60.monorepo`, `v1-60.overlap`, `v1-65.monorepo-check`; item 67's and 68's init cases; item 2's and 5's init screens (`v1-2.3-tela-do-init`, `v1-2.3-padrao-primeiro-instalado`, `v1-5.3-init-github-marca-obrigatorios`, `v1-5.3-init-github-plano-gratis`); item 61's onboarding cases (`v1-61.block`, `v1-61.local-block`, `v1-61.edited`, `v1-61.claude-link`, `v1-61.claude-dangling`, `v1-61.refused-late`); item 55's selection cases (`v1-55.*`, every profile), which now also see root-relative package globs; item 45's check refusals (`v1-45.red-*`, `v1-45.ci-*`, `v1-45.ci-log-code`), for their fixtures; item 22's environment cases (`v1-22.ambiente-red`, `v1-22.ambiente-ci`, `v1-22.ambiente-verifica`, `v1-22.ambiente-build`).
   - **Fixed points:** README 17 (suite commands run in their root), 40, 57 and 58 (a check where a tsconfig exists, from the package) hold: a converted suite's root is `.` and its check enters the package with `cd`.
   - **New cases:** a fake `npx` on `PATH` answers `vitest list` (canned answers for the failure and boundary cases) and records its arguments and folder; and at least one case with the real vitest 2.1.9 the battery's cache already holds for item 51: a pnpm workspace with a root `vitest.config.ts` and a `vitest.workspace.ts` naming two package projects, where `init` writes the root form and a later `red` on a failing test in one package locks it under that suite.
8. **Measure and revert.**
   - **Metric:** on the Forge's layout, a fresh `init` writes the root form for each package suite, with no hand edit; 0 adopter reports of a suite skipping the root config over the next 5 adopter inits.
   - **Revert:** a release drops the probe; projects keep the config they have.
9. **Known limits.**
   - Running from the root applies the root config's run-wide options (pool options, `globalSetup`). Options a project must inherit (its own `setupFiles`, timeouts) apply only when its config extends the root one; `init` does not check that.
   - `vitest list --filesOnly` needs vitest 2.1 or later and installed dependencies; without them every candidate keeps today's form, with the line that says why. A kept suite may still not run correctly inside its package (for example a project that only works from the root); `init` says it ran inside its package and does not prove it.
   - A package whose tests run in two projects (say `node` and `browser`) keeps today's form; the user writes those suites by hand.
   - The root vitest config and workspace file are not in any suite's globs, as today, so they are not locked.
   - The project name comes from vitest at `init` time; renaming a project later leaves the suite pointing at the old name, and vitest then runs nothing for it, which `red` refuses as `suite-without-tests`.
   - The worker caps the Forge sets in its command's environment are the project's choice; `init` writes none.
### `status` says review off, and `pr`'s CI wait prints each state change (item 73)

Two small field findings. The Forge (2.25.0, `review = "off"`, no `[roles] review`) saw `shipcraft status` print `review off (agent codex)` and `review codex`, naming a reviewer that never runs. And `shipcraft pr` with `ci = "github"` prints one `waiting for ...` line and then nothing until CI ends or the limit passes (often 3 to 6 minutes on this repository), so a person or an agent watching cannot tell a slow check from a stuck one.

1. **`status` with review off.** When `[execution] review` is `"off"`:
   - the layers line ends `; review off`, with no `(agent ...)`;
   - the roles line's review entry is `review off`, whatever `[roles] review` holds.
   With review `"local"` (or any other value that is not `"off"`) both lines stay as today. Nothing else in `status` changes. This supersedes item 64's display of the review role when review is off; item 64's validation and defaults of `[roles] review` are unchanged, and `pr`, `review` and `merge` still read it as today.
2. **`pr`'s GitHub CI wait.** While `pr` waits for GitHub CI (`ci = "github"` with review local, the `waiting for ... at <sha> (up to N s)` line of today), it prints one line on stdout each time what it reads changes, including the first read:
   `shipcraft: CI at <elapsed> s: shipcraft/ci <state>[; <check> <word>]...`
   - `<elapsed>` is the whole seconds since the wait started, rounded down;
   - `<state>` is the `shipcraft/ci` state as today's reader (`gh::statuses`) returns it (`pending`, `success`, `failure`, `error`, or any other string GitHub sends, as read), `no status` when that reader finds no `shipcraft/ci` entry, and `no state` when it returns an empty string; a `gh` failure in that reader ends `pr` as today (exit 2, no line);
   - then one `; <check> <word>` per name in `[execution] suite_checks`, in config order, `<word>` one of `green`, `failed`, `pending`, `missing`, `unreadable` as the wait reads them today;
   - when `<state>` is `failure` or `error`, the wait stops today before reading any check: the line then has no check entries, and no check is read;
   - `<elapsed>` is sampled once per read, after all of that read's calls return and just before printing; a slow read may print a value above the limit;
   - a line is printed only when the read's state vector (the `shipcraft/ci` state or its absence, then each check's word in config order) differs from the last one printed; status descriptions, run ids and ordering never trigger a line, and an unreadable check is the word `unreadable` whatever the reason.
   The lines that end the wait (CI failed, a check failed, the limit passed) and the wait's outcome, its exit code, its run-log row and its polling interval stay as today. The line is printed before the wait acts on what it read, so the read that ends the wait also prints its line when its states changed.
3. **Current behavior** on the paths this item touches (rule 14):
   - `status`: the branch line, the layers line with `ci ...` (and item 62's suite checks), the roles line with item 64's red and green entries, the hook line, the open-locks line, the protection line, exit codes, no file written, no run-log row: keep. The review part of both lines when review is `"off"`: change, as in point 1.
   - `pr`'s wait: the `waiting for` line, polling every 2 s up to `ci_timeout`, stopping on `failure` or `error` of `shipcraft/ci` or a failed check, the `ci-github` and `ci-github-no-status` outcomes and their text, the review running only after CI is green, and everything `pr` prints before and after the wait: keep. New lines during the wait: change, as in point 2.
   - `pr` with `ci = "local"` or `"off"`, `review`, `merge` and `ci`: keep; they get no new line.
   - A `gh` error while reading `shipcraft/ci` during the wait: `shipcraft: error: ...` on stderr, exit 2, no review and no summary comment; the push and the PR created or updated before stay; a `pr` row with `code: "error"` is appended to `.git/shipcraft/runs.jsonl` (a logging failure is ignored), and nothing is rolled back: keep.
4. **Touches.**
   - **Assertions that change:** `v1-64.status-off` (`acceptance/lib/item64.sh`), which expects the roles line's review entry `review codex` with review off: it now expects `review off`.
   - **Must keep passing unchanged:** every other `v1-64.status-*` case; `v1-64.min-valid`, `v1-64.min-patch`, `v1-64.min-leading-zero`, `v1-64.min-legacy`, `v1-64.min-no-roles`; the hook-state status cases `v1-20.status.*`, `v1-15c.status-sem-exec-borda`, `v1-25.husky.status-completo`, `v1-25.pre.status-completo` and the other item 20 and 25 status variants; `v1-62.status`, `v1-62.status-empty`, `v1-5.4-status-nivel-de-protecao`; item 62's GitHub wait cases (`v1-62.*`) and item 3's wait cases in `acceptance/lib/v1.sh` (the review runs once after the status arrives; the wait's limit), whose assertions on the wait's outcome and lines stay; item 41's local CI queue cases.
5. **Measure and revert.**
   - **Metric:** no adopter report of a reviewer named while review is off; on this repository's next 5 `pr` runs, each CI wait prints at least one state line before its outcome.
   - **Revert:** a release drops the lines.
6. **Known limits.**
   - A state that changes and changes back between two reads is not seen, as today.
   - The local CI queue's wait (item 41) prints no new line.

## 4. Configuration

`.shipcraft.toml` lives at the project root.

### Single suite (top level)

| Key | Meaning |
|---|---|
| `shipcraft_min` | Minimum `shipcraft` version, `"X.Y"`. An older binary refuses (`shipcraft-min`). |
| `lang` | `python`, `node` or `go`. |
| `runner` | The runner name (`pytest`, `vitest`, `jest`, `gotestsum`). |
| `test_command` | The test command. `{junit}` is replaced by the report path. |
| `test_globs` | Test and support file globs. These files are locked. Any other file the GREEN must not change, such as the spec the tests were written from, can be listed too: it is protected and never run. |
| `check` | Optional project-wide check (type check, vet). Runs in CI and at RED, never in the hook. A failing check refuses `no-report` with a reason that names the check (item 45). |
| `filter` | Who filters the hook's run (section 6). |

### Sections

| Key | Meaning | Default |
|---|---|---|
| `[[suite]] name` | Suite name. Prefixes its case ids. | the folder |
| `[[suite]] root` | Folder the command runs in. Globs are relative to it. | `.` |
| `[[suite]] command` | Test command, with `{junit}`. | required |
| `[[suite]] check` | Project-wide check for this suite. | none |
| `[[suite]] globs` | Test and support file globs, plus any other file to protect from the GREEN (see `test_globs`). | `[]` |
| `[[suite]] filter` | `"shipcraft"` or `"command"` (section 6). | `"shipcraft"` |
| `[build] command` | Runs once at the root before the first suite (section 6). | none |
| `[execution] ci` | Where CI runs: `local` (this machine, through `shipcraft pr`), `github` (GitHub Actions) or `off` (not run, not required). | `local` |
| `[execution] review` | `local` or `off`. `github` is reserved and refused (`review-github`). | `local` |
| `[execution] ci_timeout` | Local CI time limit, in seconds. | `1800` |
| `[execution] suite_checks` | Names of the project's own GitHub checks that run the suite; only with `ci = "github"` (item 62). | `[]` |
| `[execution] merge` | How `shipcraft merge` merges: `merge` (a merge commit) or `squash` (item 42). | `merge` |
| `[roles] review` | The review agent: `codex`, `claude` or `gemini`, or a table with `agent`, `model` and `effort` (item 64). | first one installed |
| `[roles] red`, `[roles] green` | The agent (string or table, as `review`) the orchestrator uses for each phase; shown, never run (item 64). | not set |
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

### Roles per phase (item 64)

Shipcraft runs the review agent itself (`[roles] review`). The RED and the GREEN are written by sessions that the orchestrator starts, and the lock is what makes them honest. Item 64 lets a project write down which agent, model and effort each phase uses, so the choice lives in the versioned config and not in someone's memory. It also lets the review pick a model and an effort. Shipcraft still starts no RED or GREEN session. Why: on this repository the choice (RED by Codex `gpt-6.1-sol` at medium effort, GREEN by Claude, review by Codex) lived only in private notes, which blocked dogfood step 4.

1. **The keys.** `[roles] review`, `[roles] red` and `[roles] green`. Each is either a string, the agent alone (`"codex"`, `"claude"` or `"gemini"`, as `review` is today), or a TOML table with the keys `agent` (required), `model` and `effort` (both optional). Any TOML spelling of a table is the same value: inline `review = { agent = "codex" }`, a `[roles.review]` section, or dotted keys. The string `"codex"` and the table `{ agent = "codex" }` mean the same thing everywhere. `red` and `green` have no default: absent means the orchestrator chooses. `review` keeps its defaults: `init` writes the first agent installed, as a string, and when the key is absent at run time the reviewer is `codex`, as today.
2. **Validation.** It applies wherever the config is read: the hook, `red`, `ci`, `pr`, `review`, `merge` and `status`, each reading the same snapshot it reads today (staged, base or working tree). A refusal is `config-invalid`, and its reason names the exact key path, for example `roles.green.agent` for a table without `agent`, or `roles.red.flavor` for an unknown member. The order: everything that refuses today keeps its place and comes first (parse and structure errors, legacy keys, `shipcraft-min`, item 47's `[execution]` checks). Then come the `shipcraft_min` rule below, and `red`, `green` and `review`, in that order. Within one role: the value's type, then `agent` (missing or unknown), then unknown members in key order, then `model`, then `effort`. Each of these is refused:
   - a value that is neither a string nor a table;
   - an agent that is not `codex`, `claude` or `gemini`;
   - a table without `agent`, or with any key other than `agent`, `model` and `effort`;
   - a `model` or `effort` that is not a string, is empty, or starts with `-`, or that has a whitespace or control character anywhere. These are checked on the decoded TOML string, with Unicode's definitions (Rust's `char::is_whitespace` and `char::is_control`), so U+00A0 and U+0085 are refused;
   - an `effort` not in its agent's list. For `codex`: `minimal`, `low`, `medium`, `high`, `xhigh`. For `claude`: `low`, `medium`, `high`, `xhigh`, `max`, as `claude --help` lists them. `gemini` takes no effort.
   A table form, or `red` or `green` in any form, also needs `shipcraft_min` of `2.20` or more, compared as `shipcraft_min` is compared today. A config that uses none of these is unaffected. Otherwise the config is refused `config-invalid`, and the reason names `shipcraft_min`: older binaries do not know these keys and would judge the project differently. Validation checks the shape only. Whether the model exists, and whether it accepts that effort, is the agent CLI's business: a reviewer that rejects them fails to start, which is a review `error`, as today, and is not retried.
3. **The review uses its model and effort.** With `[roles] review` as a table (read from the base config, as today), the reviewer starts with the model and effort given, and with neither when they are absent (as today):
   - `codex`: `-m <model>` and `-c model_reasoning_effort=<effort>`;
   - `claude`: `--model <model>` and `--effort <effort>`;
   - `gemini`: `-m <model>` (the flag of the gemini CLI's `--model`; it is not installed on the machine where this was written, so the battery checks it with its stub).
   Each one goes before the prompt, as separate arguments. The agent name in the review status, its comment and the row's `agent` stays the agent alone.
   - **Rows.** Every review row that is not reused (the same rows that item 63's `after_green_ci` goes on) gains `model` and `effort`: the strings the config asked for, or `null` when absent. They are not the provider's effective defaults.
   - **Reuse.** An earlier row is a source only when its `agent`, `model` and `effort` also equal this run's. A row without `model` or `effort` (every row from before this item), or with `null`, counts as `null` for each. A row whose `agent`, `model` or `effort` is present but is not a string (or `null` for `model` and `effort`) is never a source. Unreadable logs and lines are handled as today. So when the string form is unchanged, earlier verdicts are still reused, but a change of model or effort reviews again. A reused row records the `model` and `effort` of the row it reused.
4. **The RED and GREEN roles are shown, not run.**
   - `shipcraft status` prints one more line after the layers line, whether review is on or off: `shipcraft: roles: red <role>; green <role>; review <role>`. A `<role>` is the agent, followed by ` (<model>, effort <effort>)`, ` (<model>)` or ` (effort <effort>)` when they are given. An absent `red` or `green` reads `not set (the orchestrator's choice)`. `review` is the configured value, or `codex` when the key is absent, as today. The layers line is unchanged.
   - After `shipcraft red` or `shipcraft red --redo` writes a lock, it prints on stdout, after its last line today: `shipcraft: next: the GREEN, in a new session (<green role>, [roles] green)`, or `shipcraft: next: the GREEN, in a new session ([roles] green not set)`. A refusal prints neither line.
5. **What uses the roles.** The lock, the hook, CI and the gate validate `red` and `green` (point 2) but never use them to choose or check who wrote a commit. A session that is not the declared agent is not detected or refused; the lock stays the mechanical guarantee. The orchestrator reads the roles from `shipcraft status`, which the `AGENTS.md` block already tells agents to run. The block itself does not change in this item: telling the orchestrator to start each phase with its role belongs to a later item that changes the block, together with its upgrade path.
6. **Measure and revert.** The metric is false refusals of a valid `[roles]` config across the next 5 items (target 0), plus whether dogfood step 4 is written in `.shipcraft.toml`. The revert is to remove the new keys, or to go back to the string form. Product rollback: the previous release.

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

With `ci = "github"` and `review = "local"`, `shipcraft pr` waits until CI is green at HEAD (item 62: `shipcraft/ci`, plus every `suite_checks` name) (up to `ci_timeout`) and reviews only on `success`.

### The suite in the project's own GitHub checks (item 62)

Shipcraft's own repository runs its battery in GitHub Actions as 10 parallel shards behind one required check, `acceptance` (about 4 minutes). With `ci = "github"` before this item, `shipcraft/ci` had to come from a workflow that runs `shipcraft ci`, and `shipcraft ci` runs the whole suite in one process: it requires every locked case in one report, so it cannot be split into shards. Measured on 10-29: 1245 s for the battery in one run on this machine, against about 4 minutes sharded. The only way to keep the shards was `ci = "off"`, which reads as "no CI" while CI does run. Item 62 lets a project say that its suite runs in GitHub checks it already has, and makes `shipcraft/ci` the commit re-check alone.

**What `ci` means.** `[execution] ci` says only where CI runs: `local` (this machine, through `shipcraft pr`), `github` (the project's GitHub Actions) or `off` (CI does not run, and the gate does not require it). It never says what runs; `suite_checks` does.

**The key.** `[execution] suite_checks` is a TOML array of strings, the names of GitHub checks that run the project's suite, its `[build]` and its suite `check`s. Absent means `[]`, today's behavior everywhere.
- It is read and validated by the reader and at the point of item 47, after `ci`, `review` and `merge`, and refuses `execution-invalid` naming the key when:
  - the value is not an array, or an element is not a string;
  - an element is empty, holds a control character (U+0000 to U+001F or U+007F), starts or ends with a character Rust's `char::is_whitespace` accepts, or equals an earlier element byte for byte;
  - an element is `shipcraft/ci` or `shipcraft/review`;
  - the array is not empty and `ci` is not `"github"`;
  - the array is not empty and `shipcraft_min` is not a TOML string of two or three dot-separated runs of ASCII digits that compares at or above `2.18` by today's `shipcraft_min` comparison (a binary older than 2.18 ignores the key, so the project must keep those binaries out). Today's `shipcraft-min` refusal, which comes before item 47's checks, keeps its place: a `shipcraft_min` above the running binary refuses `shipcraft-min` first.
- The value judged is the one in the config the command already judges by: for `pr` and `merge` the PR base's; for `ci` the config of `--base` with today's fallback; for `status` the working tree's.

**Reading a check at a commit.** For a commit `<sha>` and a name, shipcraft makes two `gh` calls and decodes each stdout as one JSON document:
- check runs: `gh api "repos/{owner}/{repo}/commits/<sha>/check-runs?check_name=<name, percent-encoded>&filter=latest&per_page=100"`. The response must be an object with an integer `total_count` and an array `check_runs` whose length equals `total_count`; each element must be an object with a string `name`, a string `status` and a `conclusion` that is a string or null. The runs whose `name` equals the name byte for byte are its matches.
- commit statuses: `gh api "repos/{owner}/{repo}/commits/<sha>/status?per_page=100"` (GitHub's combined status, one newest status per context). The response must be an object with an integer `total_count` and an array `statuses` whose length equals `total_count`; each element must be an object with a string `context` and a string `state`. The statuses whose `context` equals the name byte for byte are its matches.

The name is **unreadable** when either call fails or either response breaks its shape above. Otherwise it is **failed** when a match is done and not successful (a run with `status` `completed` and a `conclusion` other than `success`, null included; a status `failure` or `error`); else **pending** when a match is not done (a run whose `status` is not `completed`; a status whose state is not `success`, `failure` or `error`); else **green** when at least one match exists; else **missing**. Every match counts: two producers that report the same name must both be green.

**CI is green at a head** when `shipcraft/ci` is `success` there, read as today, and, when `suite_checks` is not empty, every name in it is green there. `pr` and `merge` use this one rule.

**`shipcraft merge`.** With `suite_checks` not empty, the gate checks `shipcraft/ci` first, as today, then each name in config order, then the review as today. The first name that is not green refuses `merge-without-ci` with the reason `PR #<n> has no green check <name> at its HEAD (<short sha>): <failed|pending|missing|unreadable>`; Why: merging requires the project's suite green on the latest PR commit; Next: wait for the check or fix what failed, then run `shipcraft merge <n>` again. `--no-review` still waives the review only.

**The merge is pinned to the head it checked.** `shipcraft merge` runs `gh pr merge <n> --merge` (or `--squash`) `--match-head-commit <head>`, where `<head>` is the `headRefOid` its gate read. If the PR moved, GitHub refuses and `gh` fails: shipcraft writes no `merge` row for that run and exits as it does today on a `gh` failure, with a message that names `<head>` (a `--no-review` comment already posted stays). This holds whatever `ci`, `review` and `suite_checks` are, and removes item 42's known limit that `shipcraft merge` does not pin the PR head it checked.

**`shipcraft pr` with `ci = "github"`.** When it waits before the review (today: `review = "local"`), each poll reads `shipcraft/ci` and every suite check, and it waits until CI is green at HEAD, up to `ci_timeout`, polling as today. At each poll, a failed `shipcraft/ci` or any failed suite check stops the wait as `ci-github`, naming `shipcraft/ci` or the first failed name in config order. An unreadable suite-check name is read again at the next poll; a failure to read `shipcraft/ci` stops `pr` as it does today. When the limit passes, the wait stops as `ci-github-no-status`, naming every context still not green with its state (`shipcraft/ci` first, with its state as read today; then the suite checks in config order, each `pending`, `missing` or `unreadable`). The limit is checked between polls, so one poll's calls can run past it. Both stops keep today's exit code, statuses and rows.

**`shipcraft ci` re-checks commits and leaves the suite to the checks.** When the config the run judges by has `suite_checks` not empty, `shipcraft ci`:
- checks every commit of the range exactly as today (lock transitions, sealed file hashes, the config under an open lock, hook integration files, the default-branch squash rule), with every refusal that part has today;
- judges docs only as today (`docs_only` keeps its value);
- then prints exactly one line, `shipcraft: suite not run here: it runs in the GitHub check(s) <names joined with ", ", in config order> ([execution] suite_checks)`, in place of `docs only: the suites do not run`, and runs no `[build]`, no suite `check` and no suite command; `build-dirty-tree` is not reached and no copy of HEAD is made;
- does not judge what needs the suite's report at HEAD: `lock-not-closed`, `case-broke`, `lock-closed-red`, `red-already-passes`, `case-missing` and `suite-red` are not reached, and a lock open at HEAD is accepted as an open cycle;
- on the default branch still runs the escape check, unchanged;
- then prints `shipcraft: CI ok.` and item 44's last line for the config's `ci`.

Every `ci` row of the run log has `suite_in_checks`, a JSON boolean: `true` when the run printed the line above, else `false` (refusals and errors before that point included).

**`shipcraft status`.** With `suite_checks` not empty, the layers line reads `ci github (suite in GitHub checks: <names joined with ", ">)` where it reads `ci github` today; otherwise unchanged.

**What `shipcraft/ci` proves, with `suite_checks`.** That every commit of the PR passed the commit checks the hook makes that need no test run: locks opened and closed only as `red` and the hook write them, sealed files unchanged under an open lock, the config unchanged under an open lock, hook integration files unchanged. What the suite proves at HEAD (locked cases pass, nothing else broke) comes from the named checks. Section 1's "CI repeats every check" holds for `ci` without `suite_checks`; with it, CI is `shipcraft/ci` plus the named checks.

**Docs and the config `init` writes.** `init` writes, above `[execution]`, these comment lines in place of today's one:
```
# where each layer runs: "local" = on this machine, started by shipcraft pr; "github" = in this
# project's GitHub Actions (docs/github-ci.md); "off" = it does not run and shipcraft merge does not
# require it. shipcraft/ci re-checks every commit of the PR and runs the suite at its HEAD,
# unless suite_checks names GitHub checks that run the suite (docs/github-ci.md).
```
`init` writes no `suite_checks`, and a second `init` that keeps an existing config does not rewrite its comments. `docs/github-ci.md` gets a section for a project whose suite already runs in its own workflow:
- the named checks must run on `pull_request` and report on the PR head commit (GitHub Actions does), always run (no path filter that can skip them), run the project's `[build]` and `check`s too, and fail when any job they stand for fails or is cancelled: the section gives an aggregate job (`needs:` the suite jobs, `if: always()`, failing unless each needed job's result is `success`; a needed job may be `skipped` only when a scope job that itself succeeded says, in an output the aggregate reads, that there was nothing for it to run, so a job skipped because a prerequisite failed fails the aggregate), the shape of Shipcraft's own `acceptance` gate (`scope` must succeed; `linux` may be skipped only when `scope` reports mode `none`);
- each name must be unique across the project's workflows and integrations;
- one reader decides which job publishes `shipcraft/ci`: a step that reads `.shipcraft.toml` at the same commit the job passes as `--base` (the PR's base SHA on `pull_request`, the `before` SHA on `push`; `git show <that sha>:.shipcraft.toml`) with a TOML reader (Python's `tomllib`, present on GitHub's Ubuntu runners), not `grep`. A base without the file falls back to HEAD's, as today; a file that exists but cannot be read or parsed fails the step. The full-suite job (today's guide, whose `grep` step this reader replaces) runs only when `execution.ci` is `"github"` and `execution.suite_checks` is absent or empty; the re-check job only when `execution.ci` is `"github"` and `execution.suite_checks` is a non-empty array. So exactly one job publishes `shipcraft/ci` for a PR, chosen by the config that judges it;
- the re-check job: the guide's workflow without the language setup, checking out `pull_request.head.sha` with `fetch-depth: 0`, `--base` the PR's base SHA, with `GH_TOKEN` and the guide's permissions kept (the default-branch squash rule and the escape check read GitHub);
- the order: first a PR that adds the re-check job and the reader above (the re-check job runs nothing while the base's `suite_checks` is empty; a project whose base already has `ci = "github"` keeps its full-suite job, language setup included, gated by the same reader), then a PR that sets `ci = "github"`, `suite_checks` and `shipcraft_min = "2.18"` (it is still judged by its base's config); after it merges, PRs are judged the new way and a later PR may remove the old full-suite job; then make the named checks and `shipcraft/ci` required where GitHub protects branches.

**Unchanged.** `ci = "local"` and `ci = "off"`; `ci = "github"` without `suite_checks`; how `shipcraft/ci` and `shipcraft/review` are read; `review`; the escape check, which still judges merged PRs by `shipcraft/ci` and `shipcraft/review` only; `init --github`, which still marks `shipcraft/ci` and `shipcraft/review` as required (not the suite checks).

**Known limits.**
- Which tests ran is the named checks' business: a check that runs a subset (by impact, as Shipcraft's own `acceptance` does) or skips a locked case is trusted, and so is whether it ran `[build]` and `check`.
- At HEAD, a lock left open while its cases pass (`lock-not-closed`, a sign of `--no-verify`) and a locked case missing from the run (`case-missing`) are not caught.
- A provider that reports its check on GitHub's test-merge commit rather than the PR head never makes the name green: it waits or refuses.
- The escape check does not read the suite checks, so a merge through GitHub's button with a red suite check and a green `shipcraft/ci` is not recorded as an escape.
- A name with more than 100 matching check runs, or a commit with more than 100 status contexts, is unreadable.

**Versions.** The binary goes to 2.18.0. No lock field changes; `suite_checks` is a new optional config key.

**Battery.**
- `v1-59.ci`, `v1-59.ci-mixed`, `v1-59.ci-present`, `v1-59.ci-unreadable`, `v1-59.ci-bad-config`, `v1-59.ci-longest`, `v1-59.ci-remedy` and `v1-59.files-many` assert the exact key set of the `ci` row: the RED adds `suite_in_checks` to it, and nothing else.
- `v1-42.squash` asserts `--squash` and no title or body, not the whole argument list: it must hold.
- The `gh` stub (`acceptance/stubs/gh`) enforces `--match-head-commit` against the PR's live head as GitHub does, and serves check runs (with `check_name` and `filter=latest`) and the combined status from state a case sets; `acceptance/README.md` lists both.

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
- **Reuse:** a verdict is reused when the diff and the PR's text are both unchanged (item 54 added the text). The diff key (`diff_sha256`) is the SHA-256 of `git diff --raw -z --no-abbrev --no-renames --ignore-submodules=none <base> <head>`, as before: every changed file has the same versions on both sides. If the key cannot be computed, the review runs.
- **The PR's text is part of the key (item 54).** The brief carries a title and a body, so a verdict is reused only when they are the same too.
  - **The text key.** `text_sha256` is the SHA-256 of the title's UTF-8 bytes, one NUL byte, then the body's UTF-8 bytes: the same title and body this run's brief receives, before the brief's own substitutions (an empty body is the empty string, not the brief's placeholder). For a PR they are the decoded JSON strings `gh` returned, with no trimming or newline or Unicode normalization; for `review` without a PR, the title and body it builds today (its rows get the key; whether it reuses is unchanged: it runs every time). If the title or body could not be read (a failed call, a missing, null or non-string field), there is no text key: the review runs and its row has no `text_sha256`. How the review behaves when the text cannot be read is unchanged.
  - **Lookup.** As today, the newest earlier `review` row in the run log that ran a reviewer (not `reused`, result `passed` or `refused`) and whose keys match gives the verdict. It now needs both `diff_sha256` and `text_sha256` equal to this run's; a row whose `text_sha256` is missing or is not 64 lowercase hex characters (every row written before item 54) is never a source, so the first review after the upgrade runs once. Matching is by exact keys only: if the text goes back to an earlier version, that version's verdict can be reused, as a diff that goes back already can.
  - **Rows.** Every `review` row with a text key records it in `text_sha256`, a reused one included; a row without one omits the field. `diff_sha256` keeps its meaning. The reused status, its description, `reused: true` and the round counting are unchanged.
  - **Why.** On draken-platform#29 (head a8bb3ef) the review refused because the code disagreed with a rule written in the PR body; after the body was fixed with `gh pr edit`, `shipcraft review --pr 29` answered `verdict from a8bb3ef reused (same file versions)`, and only a docs commit (3a5ea1c) made it review again. Wrong-measurement note: since 1.0 (item 4, rule 4), the key covered the diff only while the brief also carried the PR text.
  - **Known limits.** Statuses belong to the head commit: editing the PR's text after an approval does not by itself undo `shipcraft/review` (run `shipcraft review --pr <n>` again; `shipcraft merge` reads the status as before), and two PRs with the same head share one status. The text is read when the brief is built, so an edit made after that (during a long CI run) is not seen by that review. The project spec (`[review] spec`) is in the key only through the diff.

### The review after a green CI (item 63)

The QA brief told the reviewer to run the whole suite. In `shipcraft pr` the review only starts after CI passed at the same head, so it reran what CI had just judged. Measured on this repository on 10-29 and 10-30: 1374, 1319 and 1301 s per review, most of it the battery. That alone breaks the 14-minute RED-to-main bar. In the same reviews, 8 battery cases failed only because the reviewer inherited variables that `shipcraft pr` sets for its own run log.

1. **After green CI.** In `shipcraft pr`, with `[execution] ci = "local"` or `"github"`, the review runs only after the CI gate passed at HEAD (local CI, or item 62's CI-green rule). That review is *after green CI*. Only how `shipcraft pr` got there counts: no PR number, status or environment variable is read to decide it. With `ci = "off"`, in `shipcraft review` and in `shipcraft review --pr <n>`, the review is not after green CI.
2. **What green CI means here.** CI was green at this exact commit. That is not a claim that the suite ran: CI may judge a PR docs only and skip the suite (item 40 for local CI, or the project's own rules in its `suite_checks`). The brief and the output say "CI is green", never "the suite passed".
3. **The brief after green CI.** Shipcraft keeps two built-in briefs and chooses one. The brief after green CI says, everywhere it mentions the suite (the opening, the steps, the review format), that CI is green at this commit, that the suite is CI's job, and that the reviewer must not run the suite commands as a check. The reviewer may still install what the project needs, and may run the smallest selection the runner offers (a file, a package, a test name) to reproduce something it suspects, even if that selection happens to cover every case. Not being able to isolate a test is never a Blocking item by itself. That choice is the reviewer's: Shipcraft classifies no file. The suite commands stay in the brief so the reviewer knows how the suite runs. The format's suite line becomes `The suite: not rerun (CI green at <short sha>)`, where `<short sha>` is the first 7 characters, as elsewhere. The verdict parser does not change. The other brief is today's, byte for byte: install, run the suite, record passed/total. Title, body, spec, diff and battery go into both briefs as today.
4. **The reviewer's environment.** The reviewer's command, for every agent and in every case (after green CI or not), starts with no environment variable whose name begins with the bytes `SHIPCRAFT_`. Names are compared as raw OS bytes, so a name or value that is not valid UTF-8 is never decoded, and every other variable is passed unchanged. This covers `SHIPCRAFT_PRODUCT_LINES`, `SHIPCRAFT_PR_LOCKS`, `SHIPCRAFT_SHAPE_WARNINGS` and any that a later item adds. Only the reviewer's command loses them. Shipcraft's own process keeps them, so its CI, review, `pr` rows and summary record `product_lines`, `shape_warnings` and `locks` as before.
5. **What it prints.** After green CI, the line that starts the review ends with `; CI is green at <short sha>, so the suite is not rerun`.
6. **The run log.** Every `review` row that is not reused gains `after_green_ci`: `true` after green CI, otherwise `false`. It goes on exactly the rows written today: a reviewer that could not start or gave no verdict still has its row, with the field; a failure that writes no row today (no queue slot, no checkout, no brief) still writes none. A reused row (`reused: true`) does not have it. Reuse does not change: the same keys, the same lookup and the same rows, in `pr` and in `review --pr`. A reused verdict starts no reviewer, so no suite runs.
7. **Measure and revert.** The metric is the `secs` of non-reused `review` rows with `after_green_ci: true`, over the first 5 PRs merged into main after this item. The coordinator names the 5 PRs by number and reads their rows by `pr` from this machine's run log; every round counts, and a PR with no such row is reported as not observed, never counted as fast. `secs` is wall time, including any wait for a queue slot, because that is what the PR waits. The bar: the review fits inside the 14-minute RED-to-main bar, with a median of 5 minutes or less. If it is slower, or a defect that a full suite run would have caught escapes a review, the coordinator reports it and the project may turn the layer off (`review = "off"`). Nothing switches by itself.
8. **Known limits.** A test that passes in CI but is wrong is still only something the reviewer reads, as it was before. CI is judged at HEAD only: if the base moved after CI, the review does not run the merged tree, the same as the merge gate. When `shipcraft review --pr <n>` starts a reviewer, it uses today's brief and runs the full suite, because it does not read CI.

### The merge gate

`shipcraft merge <pr>` merges only with `shipcraft/ci` and `shipcraft/review` at `success` on the PR's current HEAD; an off layer is not required. `--no-review "<reason>"` waives the review, never CI, and records the reason in the PR and the run log. Where GitHub offers branch protection, `init --github` makes both statuses required; otherwise `shipcraft merge` is the gate, and `shipcraft status` says so. `shipcraft ci` on the default branch warns, with exit `0`, about each merge that bypassed the gate, and records it as an `escape`.

**Squash merge (item 42).** Three points:

1. **The key.** `[execution] merge` is `"merge"` (a merge commit, the default when the key is absent) or `"squash"`. Any other value, a non-string included, refuses `execution-invalid` wherever the config is read, like `[execution] ci`. `shipcraft merge` reads it from the same config as the gate reads which layers are on (the PR base's `.shipcraft.toml`), so the PR cannot change how it is merged.
2. **The merge.** With `"squash"`, `shipcraft merge` checks the same gate, posts the same `--no-review` comment and then runs `gh pr merge <pr> --squash` without a title or body of its own: the repository's GitHub settings decide them. The `merge` row is written only after `gh` succeeds, as today, with the same fields (`commit` is still the PR head) plus `method`: `"merge"` or `"squash"`. Refusals before the merge write no `method`. Older rows without `method` stay valid for every reader.
3. **The default branch after a squash.** A squash puts the PR on the base as one commit, so a lock that the PR opened and closed arrives there already closed, with no commit holding it open. `shipcraft ci` on the default branch accepts that commit when GitHub reports it as the `merge_commit_sha` of a PR (`commits/<sha>/pulls`, the reader the escape check already uses) that went through the gate as the escape check judges it: its head had every required status in `success`, or the review status was waived by the `--no-review` comment while `shipcraft/ci` was in `success`; the locked cases are not run at that commit. In any other case, including when GitHub cannot be read, the closed lock is refused `lock-edited` as today. On a PR branch nothing changes: a lock still has to be opened by a RED commit and closed by a later one.

What squash gives up: the base's history keeps no RED commit. The PR's `shipcraft ci` checked every PR commit's locks, hashes and config, and ran the suite on the PR head only (section 2); after the squash only that evidence and the run log remain.

The escape check of `shipcraft ci` on the default branch reads every first-parent commit of `<base>..HEAD` (`git rev-list --first-parent`), not only merge commits, whatever the config says. A commit GitHub reports as a PR's `merge_commit_sha` is judged by the statuses and the `--no-review` comment exactly as before, whether it was merged by `shipcraft merge` or by GitHub's button; so a PR squashed through the button without the gate is now warned of and recorded as an `escape`. A commit no PR merged (a direct push) is not judged, as before. If `gh` fails, the check prints the warning it prints today and stops; a missing `<base>` (a shallow clone) skips the check, as today.

Known limits kept by item 42: a `--no-review` comment exempts the PR's later heads too; and the merged tree is not tested when the base moved after the PR's CI. Each applies to both methods.

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

A variable is set only when its list is not empty. Every other command `shipcraft` runs gets neither (the exceptions are `red`'s narrowed first run, item 55, which gets `SHIPCRAFT_FILES` only, and `red`'s second run, item 53, which runs as the hook does), even when inherited, so a stale value never narrows a suite. The command decides whether to use them. A RED case it does not select is `case-missing`.

**vitest names the RED files (item 51).** Wherever the hook adds its vitest exclusions today (`filter = "shipcraft"` and a command it recognizes as vitest, exactly as before), it now also appends each RED test file as a positional argument: the same files, in the same judged checkout and the same absolute form as `SHIPCRAFT_FILES`, one shell-quoted argument per distinct file, in byte order, at the same place as the exclusions. Nothing else changes: the exclusions stay as they are (every present non-RED test file of the suite), the command's own file arguments are handled as before, `filter = "command"` is untouched, and when some RED case does not map to a file no positional argument is added (the hook runs all locked files, as before). Verdicts are judged as before: a RED file's cases block; any other file that runs is judged like the files the fallback runs today.

Why: in a vitest workspace (for example a `vitest.workspace.*` file, or `test.projects` in the root config) a command-line `--exclude` does not reach the workspace's projects, so with the exclusions alone every test file ran. On the Forge (vitest 2.1.9, 1360 locked files) the hook took 214 and 237 s with a lock open, where its refusals took 6 s. A positional argument is vitest's filter on the file path, so the absolute path keeps every project to the RED files; a file whose path contains a RED file's path also runs. Shipcraft does not read the vitest config: the arguments are added whether or not the project is a workspace. Known limits, the same as the exclusions': a command whose vitest call is not the last word (a wrapper script, `&& ...`, a trailing comment, `npm run` without `--`) does not receive them; vitest flags that narrow further (`--project`, `-t`) keep narrowing. Wrong-measurement note: since 2.0.0 (item 13); found on the Forge in POC-019; the battery should have caught it, but its vitest fixtures have no workspace.

### `filter`

`filter = "shipcraft"` (the default) lets `shipcraft` add its own filter for the runners it knows. `filter = "command"` runs the command as written. The two never stack.

### `[build]` for TypeScript project references

`[build] command` runs once at the root before the first suite, in `red` and in `ci` on a clean tree or fresh clone. CI builds only HEAD. The build never runs on the hook's copy; the hook uses the build output already in the tree. `ci` with `[build]` on a dirty tree refuses (`build-dirty-tree`), and a failing build refuses (`build-failed`) before any suite.

`init` (except `--lang other`, item 67) writes `[build]` when a tracked `tsconfig.json` at the root or in a workspace package has `references` or `composite: true`: `npx --no -- tsc -b` followed by those folders, alphabetically. It runs the command first and writes it only if it succeeds; otherwise it says why and still exits `0`.

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
| `execution-invalid` | An `[execution] ci`, `review` or `merge` value `shipcraft` does not know (items 42 and 47), or a `suite_checks` value item 62 refuses. |
| `foreign-hook` | `init` cannot prove which hook runs, or another tool owns it. |
| `group-failed` | At RED, a failing case is a vitest `describe` block whose `beforeAll` failed and whose tests were skipped, not a test (item 52). |
| `lang-multiple` | `init` found more than one language. |
| `lang-unknown` | `--lang` names an unsupported language, or `--lang other` without a valid `--command` and `--glob` (item 67). |
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
| `red-not-reproduced` | At RED, every case that failed passed in the second run (item 53). |
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
| `suite_in_checks` | On `ci` rows: whether the suite was left to `[execution] suite_checks` (item 62). |
| `queue_secs` | On `pr` rows: seconds the local CI waited for a slot, rounded down; `0` when it skipped the queue, `null` without local CI (item 41). |
| `tokens`, `agent`, `pr`, `diff_sha256`, `text_sha256` | On `review` rows: tokens used (or `null`), the agent, the PR, and the two reuse keys (diff, and title and body; item 54). |
| `after_green_ci` | On `review` rows that are not reused: whether the review came after green CI at the same head, with the brief that does not rerun the suite (item 63). |
| `model`, `effort` | On `review` rows: the `[roles] review` model and effort asked for, or `null`; a reused row copies its source's (item 64). |
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
- Starting the RED or GREEN sessions, or detecting which agent wrote a commit: the orchestrator starts them, `[roles] red` and `green` only record its choice (item 64). The lock is the mechanical guarantee.
- A separate intent file: the PR body is the intent.
- Shadow review, and running the review in parallel with CI.

## 11. Versioning

`shipcraft` follows semantic versioning. This contract is **2.30.0**. A change that breaks a config, a lock, a command or a refusal code raises the major version. The lock carries its own `format` version. A new lock format that a binary writes while still reading the previous one is a minor change, since no lock already written stops being valid (lock format 3, item 43, in 2.3.0). `shipcraft_min` lets a project require a minimum binary, and `init` writes the running binary's `major.minor`. Releases ship one archive per macOS target (`aarch64`, `x86_64`), each holding only the `shipcraft` binary, with a `SHA256SUMS` file. On other platforms, build from source with `cargo install --path nucleo`.
