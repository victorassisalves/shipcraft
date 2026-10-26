# RED brief (acceptance author)

The coordinator includes this brief when assigning a spec item's acceptance cases. An internal trial found that 6 of 11 blockers were clear rules without a discriminating case.

**Author:** Codex (GPT-6.1-Sol, low effort), in a separate session. In a measured comparison, low effort covered 41 of 42 cases, caught the flow-YAML defect that escaped another model, and cost 3 minutes and 69k tokens. Medium and high added no coverage. Revisit the choice if another misreading escapes.

1. **Read only the item's spec and the existing battery.** Do not read the implementation.
2. **Write two cases for each rule:** the ordinary example and a boundary that a rushed GREEN could get wrong while passing the example. Examples: a hardcoded filename, almost-correct output, the wrong config, or running everything before filtering. Prefer a few discriminating cases over many similar ones.
3. **RED check:** run against the current binary. Every new case must fail for the right reason. Report cases that already pass: either identify existing behavior or strengthen a case that does not discriminate.
4. **Ambiguities:** list each one and your reading in one line. The coordinator resolves it in the spec before GREEN.
5. **Budget:** put cases in `acceptance/lib/item<N>.sh` and fixed points in `acceptance/pontos/<item>.md`, one per line. The runner discovers them. Do not add item-specific lines to `run.sh`, `lib/v1.sh` or the README: shared-file edits caused five conflicts in one evening. Keep the report to one page: counts, already-passing cases and ambiguities.
6. **Refusals use three lines:** what happened, why, next step. Refusal codes (`foreign-hook`, `case-broke`, etc.) are log fields, not terminal text. Check them only in `.git/shipcraft/runs.jsonl` for measured layers (hook, CI, review). `init` does not append there; a refused init preserves `.git/shipcraft`.
7. **Simulate external tools with their real output.** Copy the actual hook format from a known tool version and record the version in the fixed points. Lefthook's launcher ends with `call_lefthook run "pre-commit" "$@"`. An invented format can make GREEN accept a fake and refuse the real tool. Unknown formats are ambiguities.
8. **A referenced reader needs cases for its known variants** (RULES.md, rule 6). For the TypeScript reader, YAML parser or Shipcraft glob matcher, cover variants a manual implementation might miss: CR, CRLF, U+2028/U+2029, BOM, inline comments, flow style, null, wrong types, wildcards anywhere, quoting and spaces. List the covered variants. An internal trial missed U+2028 and malformed pnpm lists despite naming the correct reader in the spec.
9. **Defect work starts with a main reproduction** (RULES.md, rule 4). Show the command and output before adding other cases. If it does not reproduce, stop and report `needs_input`: the premise may be wrong. Two prior defect premises failed this check.
10. **Cases must not depend on the machine or a fixed version.** Do not create filenames differing only by case: common macOS filesystems treat them as one. Read the expected version from `nucleo/Cargo.toml` or `shipcraft --version`.
11. **Find every case that depends on a changed fixed point.** Search all of `acceptance/` for the affected file, refusal or behavior, and list cases from other items that you adjusted or confirmed. Earlier changes broke 51 cases in one item and five in three others because their shared assumptions were missed.
12. **Slice first; run the full battery once on the final head.** Run `SHIPCRAFT_ACCEPTANCE_CASES` with the affected IDs first. For a rename, also search fixtures and sealed locks for old names. During the command rename, two full runs were stopped to reseal historical config locks: about 19 minutes lost that a one-minute slice could have caught.

    Detach the full run from the agent process (a capacity error can end the turn and its children; macOS has no `setsid` command):

    ```sh
    nohup perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or die' env -u SHIPCRAFT_ACCEPTANCE_CASES -u SHIPCRAFT_ACCEPTANCE_REUSE SHIPCRAFT_ACCEPTANCE_JOBS=4 nice -n 10 bash acceptance/run.sh <binary> all > <log> 2>&1 &
    ```

    Follow the log or reuse cache without waiting in the foreground. After resuming a seat, inspect its existing log before starting another run. Include the final `run.sh: resultado salvo: <id> (...)` line in the report.
