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
- The cases with no `origin` run in full as before, and their command and environment counts stay as they are: `v1-22.ambiente-red`, `v1-22.ambiente-build`, `v1-22.bash`, `v1-53.*`, `v1-16a.1-red-build`, `v1-45.red-order`.

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
- Without a base (`git init` with no remote, no `origin/HEAD`), a redo runs every suite, even when every lock case maps.
- A case whose test moved to another file in the repair maps to no file of the old lock, and the redo runs in full.

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
| `init [--lang python\|node\|go] [--github]` | Sets up the project (below). |
| `red [--redo] [--base <ref>] [--all]` | Runs the RED's changed test files, or every suite when it cannot narrow safely (item 55), requires assertion failures, reruns the failing cases once and does not lock those that pass (item 53), writes an open lock; `--redo` rewrites the branch's open lock (item 46). Refuses `lock-open`, `red-already-passes`, `error-before-assertions`, `group-failed`, `red-not-reproduced`, `no-report`, `suite-without-tests`, `build-failed`. |
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
- **Config:** writes `.shipcraft.toml` with the test command, globs, `check` (`tsc --noEmit`, except for a tsconfig that checks no file, item 56; or `go vet`), `[execution]`, `[roles]`, `shipcraft_min` and, when it applies, `[build]`. Every `npx` it writes puts `--` before the tool's arguments.
- **Review:** `init` asks nothing. With an agent installed it writes `review = "local"` and the first one found in `[roles] review`, and says that the diff goes to that agent's provider and how to turn review off. With none installed, review is `off` and it says how to enable it.
- **AGENTS.md:** `init` creates `AGENTS.md` with a short block (marked `<!-- shipcraft -->`) telling agents the RED/GREEN workflow, or appends the block once to an existing file. A symlink or a failed write is left alone with a notice; it never fails the init. The block is the text below `AGENTS_BLOCK` in `nucleo/src/init.rs`.
- **Hook:** there is one route: `shipcraft check --commit-msg` in `commit-msg` and `shipcraft close` in `post-commit`, so the hook sees the index after formatters ran. `init` integrates only when it can prove which configuration runs the hook:
  - plain git: shipcraft's own `.git/hooks/commit-msg` and `.git/hooks/post-commit`;
  - lefthook: the two commands in the lefthook file's `commit-msg` and `post-commit` blocks;
  - husky 9 and the pre-commit framework: the two commands in their files.

  Anything `init` cannot prove (another tool's hook, `core.hooksPath` elsewhere, two hook managers, flow-style YAML, symlinks) refuses with `foreign-hook` and says where to add `shipcraft check` by hand. Edge cases are fixed by the acceptance battery (`acceptance/`).
- **GitHub:** `init` never writes a workflow. With `--github` it marks `shipcraft/ci` and, when review is on, `shipcraft/review` as required checks where GitHub offers branch protection.

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
  - `init` handles `CLAUDE.md` at the repository root when an entry exists there (`lstat` succeeds: a symlink, dangling or not, counts and is then kept as `AGENTS.md`'s are), or when `claude` is found on `PATH` by the same lookup `init` uses to find review agents (checked on its own, whatever `[roles] review` is).
  - Its block is three lines: the start line, `Shipcraft workflow (required): @AGENTS.md`, the end line. The rules are `AGENTS.md`'s with this block as the only known block: created, appended, kept equal, kept different with the notice.
  - `CLAUDE.md` is handled only when `AGENTS.md` is a regular file that holds the current block after `init` (written now or already equal); a symlinked `AGENTS.md` never qualifies. Otherwise `init` leaves `CLAUDE.md` untouched and prints `shipcraft: CLAUDE.md not written: AGENTS.md does not hold this version's shipcraft block`.
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
- The hint covers a repository with no config. A fresh clone of a project that has one, but whose hooks are not installed yet, gets no hint; CI is the backstop, as today.
- `npx -- shipcraft` needs Node at the agent's shell, as item 58's hooks do, and resolves the root install only from the repository root; an agent that runs it inside a workspace package with its own older install gets that one.

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
- **Reuse:** a verdict is reused when the diff and the PR's text are both unchanged (item 54 added the text). The diff key (`diff_sha256`) is the SHA-256 of `git diff --raw -z --no-abbrev --no-renames --ignore-submodules=none <base> <head>`, as before: every changed file has the same versions on both sides. If the key cannot be computed, the review runs.
- **The PR's text is part of the key (item 54).** The brief carries a title and a body, so a verdict is reused only when they are the same too.
  - **The text key.** `text_sha256` is the SHA-256 of the title's UTF-8 bytes, one NUL byte, then the body's UTF-8 bytes: the same title and body this run's brief receives, before the brief's own substitutions (an empty body is the empty string, not the brief's placeholder). For a PR they are the decoded JSON strings `gh` returned, with no trimming or newline or Unicode normalization; for `review` without a PR, the title and body it builds today (its rows get the key; whether it reuses is unchanged: it runs every time). If the title or body could not be read (a failed call, a missing, null or non-string field), there is no text key: the review runs and its row has no `text_sha256`. How the review behaves when the text cannot be read is unchanged.
  - **Lookup.** As today, the newest earlier `review` row in the run log that ran a reviewer (not `reused`, result `passed` or `refused`) and whose keys match gives the verdict. It now needs both `diff_sha256` and `text_sha256` equal to this run's; a row whose `text_sha256` is missing or is not 64 lowercase hex characters (every row written before item 54) is never a source, so the first review after the upgrade runs once. Matching is by exact keys only: if the text goes back to an earlier version, that version's verdict can be reused, as a diff that goes back already can.
  - **Rows.** Every `review` row with a text key records it in `text_sha256`, a reused one included; a row without one omits the field. `diff_sha256` keeps its meaning. The reused status, its description, `reused: true` and the round counting are unchanged.
  - **Why.** On draken-platform#29 (head a8bb3ef) the review refused because the code disagreed with a rule written in the PR body; after the body was fixed with `gh pr edit`, `shipcraft review --pr 29` answered `verdict from a8bb3ef reused (same file versions)`, and only a docs commit (3a5ea1c) made it review again. Wrong-measurement note: since 1.0 (item 4, rule 4), the key covered the diff only while the brief also carried the PR text.
  - **Known limits.** Statuses belong to the head commit: editing the PR's text after an approval does not by itself undo `shipcraft/review` (run `shipcraft review --pr <n>` again; `shipcraft merge` reads the status as before), and two PRs with the same head share one status. The text is read when the brief is built, so an edit made after that (during a long CI run) is not seen by that review. The project spec (`[review] spec`) is in the key only through the diff.

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

A variable is set only when its list is not empty. Every other command `shipcraft` runs gets neither (the exceptions are `red`'s narrowed first run, item 55, which gets `SHIPCRAFT_FILES` only, and `red`'s second run, item 53, which runs as the hook does), even when inherited, so a stale value never narrows a suite. The command decides whether to use them. A RED case it does not select is `case-missing`.

**vitest names the RED files (item 51).** Wherever the hook adds its vitest exclusions today (`filter = "shipcraft"` and a command it recognizes as vitest, exactly as before), it now also appends each RED test file as a positional argument: the same files, in the same judged checkout and the same absolute form as `SHIPCRAFT_FILES`, one shell-quoted argument per distinct file, in byte order, at the same place as the exclusions. Nothing else changes: the exclusions stay as they are (every present non-RED test file of the suite), the command's own file arguments are handled as before, `filter = "command"` is untouched, and when some RED case does not map to a file no positional argument is added (the hook runs all locked files, as before). Verdicts are judged as before: a RED file's cases block; any other file that runs is judged like the files the fallback runs today.

Why: in a vitest workspace (for example a `vitest.workspace.*` file, or `test.projects` in the root config) a command-line `--exclude` does not reach the workspace's projects, so with the exclusions alone every test file ran. On the Forge (vitest 2.1.9, 1360 locked files) the hook took 214 and 237 s with a lock open, where its refusals took 6 s. A positional argument is vitest's filter on the file path, so the absolute path keeps every project to the RED files; a file whose path contains a RED file's path also runs. Shipcraft does not read the vitest config: the arguments are added whether or not the project is a workspace. Known limits, the same as the exclusions': a command whose vitest call is not the last word (a wrapper script, `&& ...`, a trailing comment, `npm run` without `--`) does not receive them; vitest flags that narrow further (`--project`, `-t`) keep narrowing. Wrong-measurement note: since 2.0.0 (item 13); found on the Forge in POC-019; the battery should have caught it, but its vitest fixtures have no workspace.

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
| `group-failed` | At RED, a failing case is a vitest `describe` block whose `beforeAll` failed and whose tests were skipped, not a test (item 52). |
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
| `queue_secs` | On `pr` rows: seconds the local CI waited for a slot, rounded down; `0` when it skipped the queue, `null` without local CI (item 41). |
| `tokens`, `agent`, `pr`, `diff_sha256`, `text_sha256` | On `review` rows: tokens used (or `null`), the agent, the PR, and the two reuse keys (diff, and title and body; item 54). |
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

`shipcraft` follows semantic versioning. This contract is **2.17.0**. A change that breaks a config, a lock, a command or a refusal code raises the major version. The lock carries its own `format` version. A new lock format that a binary writes while still reading the previous one is a minor change, since no lock already written stops being valid (lock format 3, item 43, in 2.3.0). `shipcraft_min` lets a project require a minimum binary, and `init` writes the running binary's `major.minor`. Releases ship one archive per macOS target (`aarch64`, `x86_64`), each holding only the `shipcraft` binary, with a `SHA256SUMS` file. On other platforms, build from source with `cargo install --path nucleo`.
