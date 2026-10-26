# Shipcraft core

The hook, CI, RED locks and review gate. The public contract is [the spec](../docs/spec.md).

## Runners Shipcraft does not know

The hook runs only RED cases. Shipcraft filters pytest, vitest, jest and Go commands itself. A generic runner (`cargo nextest`, `rspec`, a project script) can filter its own cases using two environment variables:

- `SHIPCRAFT_CASES`: an absolute path to a NUL-terminated list of RED case IDs, including the last NUL. Each ID is the JUnit `classname::name`, or `name` without a class, without the suite's `<name>:` prefix.
- `SHIPCRAFT_FILES`: an absolute path to a NUL-terminated list of absolute test paths. It exists only when every selected case maps to a test file. Support files are not executable tests.

An absent variable means run the whole suite. Both variables are removed outside hook suite execution, even when inherited from the shell. The command translates JUnit IDs to its runner's selectors.

```toml
[[suite]]
name = "core"
root = "."
command = "bash scripts/tests.sh {junit}"
globs = ["tests/**"]
filter = "command"
```

`filter = "command"` disables Shipcraft's own filter; `"shipcraft"` is the default. Commands execute through `/bin/sh`, so Bash syntax belongs in an explicitly invoked Bash script. Read the entire list and invoke the runner once: separate batches would overwrite `{junit}`.

```bash
#!/usr/bin/env bash
# scripts/tests.sh <junit>
set -euo pipefail
junit=$1
cases=()
if [[ -n ${SHIPCRAFT_CASES:-} ]]; then
  while IFS= read -r -d '' case_id; do
    cases+=("${case_id##*::}")
  done < "$SHIPCRAFT_CASES"
fi
if (( ${#cases[@]} )); then
  my-runner --junit "$junit" --exact "${cases[@]}"
else
  my-runner --junit "$junit"
fi
```

A RED case omitted by the command is refused as `case-missing`. Extra cases the command does not run remain CI's responsibility. Set `shipcraft_min` to a version supporting this interface when depending on it.
