# Shipcraft acceptance battery

Black-box acceptance tests for [the public contract](../docs/spec.md). RED authors own these cases; GREEN changes the implementation, not the tests that judge it. Historical item and case IDs remain stable.

## Run

```sh
bash acceptance/run.sh <absolute-path-to-shipcraft> [core|python|node|go|all]
```

Exit 0 means every selected case passed. The last line is `run.sh: total: N of M cases pass`.

- `core`: language-independent cases on the Python target.
- `python`, `node`, `go`: language-specific cases, including the original internal trial's 115 cases.
- `all` (default): all four profiles.

Requirements: git, Perl, Python 3; Node/npm and Go for their profiles. GitHub and reviewer calls are offline stubs. Only target setup (pip, npm, gotestsum installation) needs network access. `SHIPCRAFT_ACCEPTANCE_CACHE=<absolute-dir>` shares dependency downloads.

In CI, `acceptance/scope.sh <base>` scopes each PR by impact: only docs (`docs/`, root `*.md`, `LICENSE`, the points) runs nothing; only `acceptance/lib/item*.sh` files run those items' cases; anything else, or any doubt, runs the whole battery. Main and the daily run always run everything.

The runner uses `nice` and at most four parallel cases (`SHIPCRAFT_ACCEPTANCE_JOBS`, default/cap 4). Each case has a timeout (`SHIPCRAFT_ACCEPTANCE_CASE_TIMEOUT`, default 900 s). Temporary work, case repositories, isolated HOME, caches and GOPATH live beneath `${TMPDIR:-/tmp}/shipcraft.noindex/`. Passing cases remove their `t/` and `cw/` directories immediately; failures and logs remain for diagnosis. Shared setup is removed at exit. `SHIPCRAFT_ACCEPTANCE_KEEP=1` retains everything. At start, the runner removes earlier work dirs in which nothing changed for `SHIPCRAFT_ACCEPTANCE_RETAIN_HOURS` (default 24, decimal) and whose `run.pid`, if any, is not alive, kept ones included. Base copies use macOS `cp -cR` or Linux `cp -R --reflink=auto`, falling back to `cp -R`; `SHIPCRAFT_ACCEPTANCE_CLONE=0` always uses the fallback.

`SHIPCRAFT_ACCEPTANCE_CASES="id-a id-b"` selects a slice. Unset or empty means all cases, including normal reuse-cache recording. `SHIPCRAFT_ACCEPTANCE_VERBOSE=1` prints failed-log tails (enabled automatically in GitHub Actions).

`SHIPCRAFT_ACCEPTANCE_JUNIT=<file>` writes one testcase per case (`classname` = the repository path of the file that defines it, as `case_file` in `run.sh` gives it; `name` = `profile::stable ID`). `SHIPCRAFT_ACCEPTANCE_FILES="path ..."` keeps only the cases those files define. Failures become `failure`; harness errors, timeout or missing results become `error`; unselected cases become `skipped`.

`bash acceptance/shipcraft.sh <junit>` builds the judged `nucleo/`, translates the NUL-terminated `SHIPCRAFT_CASES` IDs (`file::profile::id`, or the older `profile::id`) into profile and case selection and `SHIPCRAFT_FILES` into `SHIPCRAFT_ACCEPTANCE_FILES`, and writes JUnit. With these, `shipcraft red` on this repository runs only the item files the RED changed (item 55). An absent or empty variable runs everything. Shipcraft judges JUnit, not the runner's exit code. Dependency cache defaults to `~/.cache/shipcraft-acceptance-deps`; reuse recording defaults to off in this adapter.

Each core case has its own HOME, TMPDIR and XDG directories. Queue cases intentionally share a HOME among their projects. The case PATH hides real `gh`, `codex`, `claude` and `gemini`: directories containing them are mirrored without them, then case stubs are prepended.

## Offline stubs

### GitHub CLI

`stubs/gh` is copied to each case's PATH with state in `state/`. The project's origin is a local bare repository. PR heads, merges and pull refs use real git operations there. Calls go to `state/calls.log`; mutations also go to `state/writes.log`.

The following surface is part of the contract. Unsupported calls exit 1 with `acceptance-stub: unsupported gh: ...`.

| Command | Contract |
|---|---|
| `gh auth status` | Authenticated. |
| `gh repo view [--json F] [-q JQ]` | `acme/proj`, private, default branch `main`. |
| `gh pr create --title T (--body B \| --body-file F\|-) [--base B] [--head H]` | Branch must be on origin; duplicate open PRs fail. |
| `gh pr list [--head H] [--base B] [--state open\|closed\|merged\|all] [--search S] [--json F] [-q JQ]` | Lists matching PRs. |
| `gh pr view [N\|BRANCH\|URL] [--json F] [-q JQ]` | Number, title, body, state, URL, head/base refs and SHA, cross-repository flag, repositories/owner/author, merge commit/time, comments, status rollup. |
| `gh pr edit [N] [--title T] [--body B \| --body-file F\|-]` | Updates PR text. |
| `gh pr comment [N] (--body B \| --body-file F\|-) [--edit-last]` | Adds or edits a comment. |
| `gh pr review [N] --comment (--body B \| --body-file F\|-)` | Counts as a comment. |
| `gh pr merge [N] (--merge\|--squash\|--rebase) [--delete-branch] [--subject S] [--body B]` | Real merge in the bare repository; missing method fails as in noninteractive gh. |
| `gh pr checkout N [-b NAME]`, `gh pr diff [N]` | Checkout and diff. |
| `gh api PATH [-X M] [-f k=v] [-F k=v] [--input F\|-] [-q JQ] [--paginate]` | Repository, pull, commit, status, checks, protection and ruleset endpoints below. |

API endpoints: `repos/O/R`, `/pulls[?head=O:B&state=S]`, `/pulls/N` (GET/PATCH), `/pulls/N/merge` (PUT), `/pulls/N/commits`, `/issues/N/comments` (GET/POST), `/pulls/N/reviews` (POST, comment), `/statuses/SHA` (POST), `/commits/SHA/statuses`, `/commits/SHA/status`, `/commits/SHA/check-runs`, `/commits/SHA/pulls`, `/commits/REF`, `/git/ref/heads/B`, `/branches/B`, `/branches/B/protection[/...]` (GET/PUT/POST/PATCH/DELETE), `/rulesets`, `user`. `{owner}`, `{repo}`, `{branch}` expand to `acme`, `proj`, `main`; `-q` uses the machine's jq.

`state/protection`: `403` (default) reports the GitHub plan restriction; `none` returns 404 and accepts writes; `full` returns required contexts. A successful protection write switches to full and stores the submitted `shipcraft/...` contexts.

### Reviewer

`stubs/agent`, copied as `codex`, `claude` or `gemini`, reads the brief from stdin. `state/reviewer.json` selects `approve`, `changes`, `preamble`, `malformed`, `refuse` (exit 0), `exit1`, `quota` (exit 1 and stderr), or `hang` (beyond timeout). The verdict uses `state/sha`: first line `APPROVE at <sha>` or `CHANGES REQUESTED at <sha>`, second line `Blocking: N`, then review text and `tokens used: N`. Calls record argv, cwd, stdin and referenced file contents in `state/reviewer.calls.jsonl`. `-o`/`--output-last-message` also writes the response to that file.

`tools/tmo.py` kills timed-out process groups; `tools/h.py` reads stub state and run logs and edits fixture config.

## Fixed points

These readings remain part of the acceptance contract. Historical item numbers identify the cases and do not refer to sections of the condensed public spec. Current config/output spellings below supersede their historical names.

1. Review timeout is an integer number of seconds (`[review] timeout`).
2. Verdict and `Blocking: N` are the first two lines; the SHA is HEAD. The early cases do not judge N.
3. APPROVE maps to success, changes requested to failure, and refusal/timeout/quota/nonzero exit/malformed verdict to error with a nonempty reason. Red CI may be failure or error.
4. Text before the verdict is malformed and produces error.
5. Each PR invocation runs the reviewer once; stub calls are counted.
6. PR exit 0 is required only when CI/review succeed or are off; other outcomes are judged by statuses.
7. Local `shipcraft review` prints the verdict/findings, returns 0 only on approval and publishes nothing.
8. PR review publishes `shipcraft/review` and a comment on the PR head, from an isolated checkout; the user's checkout is unchanged. These cases do not require a CI status there.
9. PR after rebase can publish the rewritten branch, for example with force-with-lease.
10. Merge resolves the PR head and statuses through gh; the implementation chooses its merge method.
11. The no-review reason appears in published PR text and runs.jsonl; it cannot bypass red CI.
12. Status prints one protection line: an unprotected repository says it has no protection and names `shipcraft merge`.
13. CI on main warns about bypassed merges by PR number or short SHA, exits 0 and logs `escape: true` with the merge commit. Gated merges and recorded no-review merges do not warn.
14. Init writes local CI and local review with the detected reviewer, or review off with instructions to enable local review. The minimum version comes from the binary; multiple reviewers have no fixed default in these cases.
15. Init explains RED, GREEN, provider and off; it reads one stdin line even without a terminal. Empty stdin uses the default.
16. A local layer exposes “on this machine” in terminal, PR text or status description.
17. Suite command runs in root, replaces `{junit}`, and uses root-relative globs. Init names suites after package directories with tests; legacy lang/runner keys may coexist.
18. Unknown lock format or a minimum version above the binary refuses in three lines naming the format/version, in hook and CI.
19. runs.jsonl rows contain layer, nonnegative secs, result (passed/refused/error), code (nonempty on refusal), branch and commit (nonempty for CI/review); review rows include numeric or null tokens. Init appends no measurement row. RED and close append one event per step (item 38); red, close and pr are valid layers. Every new row carries lock; PR-related rows carry locks, merge rows base/default_branch, and reused verdicts reused: true. Historical rows may omit these added fields.
20. Init creates nothing in `.github/` and preserves existing workflows, including with GitHub CI.
21. Queue state is per machine; slots come from project `[machine]` or `$XDG_CONFIG_HOME/shipcraft/config.toml`, default 1. Waiting output names queue, position and active project/branch.
22. GitHub CI mode runs no local suite and publishes no CI status. Local review waits for success on HEAD up to ci_timeout; failure/missing status prevents review. Review off does not wait.
23. ci_timeout is an integer in seconds, default 1800. Timeout kills local CI, publishes error with a reason, releases the slot and prevents review.
24. The verdict must be exactly the first line with nothing after the SHA; blank prefixes and suffixes are malformed.
25. PR suite commands come from the current base-branch tip, not HEAD or merge-base.
26. A new Python test that cannot import does not block valid GREEN; CI catches it.
27. Filtering honors configured test globs, including pytest `check_*.py`; unselected import errors stay for CI.
28. PR size is read from the last published summary containing `Size:` and updates on a later PR invocation.
29. Literal size format: `Size: +A / -R product lines`; the size warning is in the same text.
30. Size uses the complete merge-base..HEAD diff; files added then removed and unrelated new main commits do not count.
31. A PR without product changes prints `+0 / -0`.
32. Binary means git numstat `-` columns, including attributes and NUL content, independent of extension.
33. Lockfiles are a closed basename list in any directory; Gemfile.lock is not excluded.
34. Tests/support match test_globs or suite-root-relative globs; files outside a suite root do not match it.
35. Content-changing renames have no dedicated historical case; pure renames are excluded.
36. Warning threshold is strictly added+removed > `[pr] warn_lines` (default 500), after exclusions.
37. product_lines is an integer on PR CI/review rows, including explicit 0; hook rows have no historical case.
38. The npm workspace fixture has two packages, TypeScript outDir without noEmit, and installed TypeScript; npm 11 can swallow flags without `--`.
39. Every init-generated npx invocation places its first nonflag argument after `--`.
40. Packages with tsconfig.json use `npx --no -- tsc --noEmit` in their suite check.
41. No build means no dist directory or new tree files outside locks after RED and GREEN.
42. failing_at_red lists case IDs; old tests already existed and passed at RED, so they are locked but not failing_at_red.
43. A probe outside the project records old-test runs; GREEN's hook leaves it empty when filtering succeeds.
44. Product changes breaking old tests do not block GREEN; after closing, CI refuses the failing full suite.
45. Editing/deleting old tests under an open lock refuses in three lines even if they still pass.
46. Filtering supports spaces, plus signs, parentheses, brackets and regex-looking names; all RED files remain required.
47. Judged copies support git worktree detection, HEAD, history and tracked-file listing as a clean checkout would.
48. Loose means untracked and unignored at the root; dirty-tree CI still judges the selected commit's HEAD.
49. Any executed case failing refuses and leaves the lock open, even if it passed at RED; the corresponding unbroken GREEN closes.
50. A case skipped at RED is neither passing nor failing_at_red; enabling it and failing it refuses GREEN.
51. Same-name tests in other files (Go: packages) do not run in the hook; GREEN closes and CI catches their failure.
52. Mapping uses full paths, distinguishing root/nested homonyms; Python fixtures include tests/__init__.py.
53. Node's jest fixtures use jest 29.7 and jest-junit 16 installed without scripts; old-test exclusion works with default rootDir and rootDir `src`.
54. Before the first commit, judged copies are git repositories containing the index, without HEAD/history; git ls-files still works through RED/GREEN.
55. Mapping failure with pytest junit-prefix or doctest-modules may cost time but cannot falsely refuse GREEN; CI catches old failures. These cases do not constrain old-test run counts.
56. Collection/compile failures outside RED files do not block GREEN (Python import, Node module, other Go package/vet), including explicitly listed Python test files; CI refuses.
57. Suite `check` runs type checking/vet before RED/CI, separately from test_command/command. Init writes tsc where tsconfig exists and go vet for Go.
58. The npx check uses `npx --no -- tsc --noEmit`.
59. Type-only/vet-only errors with passing tests are accepted by the hook and refused by CI; old packages that stop compiling do not block GREEN.
60. Even explicitly listed pytest test files are narrowed to RED files in the hook; the old-test probe stays empty.
61. Init refuses before reviewer questions and writes no config, workflow, state or hook on refusal.
62. Failed init writes roll back newly created files and preserve existing files and config symlink targets, whether present or absent.
63. Foreign hooks and unsupported sources refuse with three lines naming `shipcraft check`; supported husky/pre-commit integration is covered by item 25 fixed points.
64. Only literal `.git/hooks` is accepted as core.hooksPath; spaces, trailing slash, leading `./` and absolute equivalents refuse without normalization.
65. Multiple lefthook sources, foreign launchers and unsupported YAML/layout refuse before writing; the later route rules in item 20 supersede the original parallel-only restriction.

## Points by item

Further fixed points live in `pontos/<item>.md`; cases live in `lib/item<N>.sh`. The runner discovers item files in name order. `item<N>_cases` lists stable `v1-<N>.*` IDs; `item<N>_case` executes `$CASE`; optional `item<N>_langs` lists core/python/node/go (default core). New items do not edit the shared runner or this README.

## One result per tree

A green all run with CASES unset or empty and committed, clean `nucleo/` and `acceptance/` before and after writes JSON to `~/.cache/shipcraft-acceptance/<id>`. The ID hashes the two HEAD tree hashes, one per line (`git rev-parse HEAD:nucleo HEAD:acceptance`). The record holds score, seconds, HEAD and date. The runner attempts the `acceptance/local` status with a 10-second timeout. Cache/status failure warns without changing the result. Use the binary built from the judged HEAD.

The review runner validates this record for the PR head and tells the reviewer to cite it rather than repeat the full battery. Missing/invalid cache keeps the usual execution. Commits with identical contents in both trees share the result. `SHIPCRAFT_ACCEPTANCE_REUSE=0` disables recording, publication and reuse.

Metric: full batteries per head, target 1. Revert reuse if an escape occurs that the full battery would have caught.
