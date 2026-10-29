# Shipcraft CI on GitHub

`shipcraft init` writes `ci = "local"`: CI runs on this machine through `shipcraft pr`, without a runner or GitHub minutes. Init writes no workflow in `.github/`. This guide enables CI on GitHub Actions.

## Three steps to enable it

1. In `.shipcraft.toml`, set `[execution] ci = "github"`.

2. Copy the workflow below to `.github/workflows/shipcraft.yml`, adding your language setup at the marked location.
3. Set the repository variable `SHIPCRAFT_URL` (Settings, Secrets and variables, Actions, Variables): the URL from which the workflow downloads the Linux binary.

The PR making this change still uses the base config and local CI: run `shipcraft pr` as usual. After merging into main, the workflow runs the suite and publishes `shipcraft/ci`.

## Workflow

```yaml
# Shipcraft: CI repeats hook checks on every commit and runs the suite on HEAD.
# Commits made with --no-verify or an edited hook are caught here.
# Runs only when .shipcraft.toml sets [execution] ci = "github" without
# suite_checks; with local CI,
# shipcraft pr runs the same CI on this machine without spending Actions minutes.
name: shipcraft

on:
  push:
  pull_request:

permissions:
  contents: read
  pull-requests: read
  statuses: write

jobs:
  shipcraft:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      # A PR uses the base config, not its own: the one reader below reads
      # .shipcraft.toml at the commit passed as --base and says whether this
      # job publishes shipcraft/ci (see "The suite in your own checks").
      - name: Does this job publish shipcraft/ci?
        id: layer
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha || github.event.before }}
          PUBLISHER: full
        run: |
          # A base without the file falls back to HEAD's; a file the base has
          # but that cannot be read or parsed fails the step.
          CFG=.shipcraft.toml
          if [ -n "$BASE_SHA" ] && git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then
            ENTRY=$(git ls-tree "$BASE_SHA" -- .shipcraft.toml) \
              || { echo "::error::cannot read the tree of $BASE_SHA"; exit 1; }
            if [ -n "$ENTRY" ]; then
              git show "$BASE_SHA:.shipcraft.toml" > "$RUNNER_TEMP/base.shipcraft.toml" \
                || { echo "::error::cannot read .shipcraft.toml at $BASE_SHA"; exit 1; }
              CFG="$RUNNER_TEMP/base.shipcraft.toml"
            fi
          fi
          python3 - "$CFG" >> "$GITHUB_OUTPUT" <<'PY'
          import os, sys, tomllib
          path = sys.argv[1]
          config = {}
          if os.path.exists(path):
              with open(path, "rb") as f:
                  config = tomllib.load(f)  # a file that cannot be parsed fails the step
          execution = config.get("execution", {})
          checks = execution.get("suite_checks", [])
          mode = "none"
          if execution.get("ci") == "github":
              if checks == []:
                  mode = "full"
              elif isinstance(checks, list):
                  mode = "recheck"
          print("mode=" + mode)
          print("run=" + ("true" if mode == os.environ["PUBLISHER"] else "false"))
          PY

      # Insert the language setup below here.

      # Download the binary from the repository variable SHIPCRAFT_URL.
      - name: Install Shipcraft
        if: steps.layer.outputs.run == 'true'
        env:
          SHIPCRAFT_URL: ${{ vars.SHIPCRAFT_URL }}
        run: |
          curl -fsSL "$SHIPCRAFT_URL" -o "$RUNNER_TEMP/shipcraft"
          chmod +x "$RUNNER_TEMP/shipcraft"
          echo "$RUNNER_TEMP" >> "$GITHUB_PATH"

      - name: Check commits and run the suite
        id: ci
        if: steps.layer.outputs.run == 'true'
        env:
          BASE: ${{ github.event.pull_request.base.sha || github.event.before }}
          GH_TOKEN: ${{ github.token }}
        run: |
          if [ -z "$BASE" ] || ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
            BASE=$(git rev-list --max-parents=0 HEAD | tail -n 1)
          fi
          # A text-only pull request does not run the suite.
          if [ "$GITHUB_EVENT_NAME" = pull_request ]; then
            shipcraft ci --base "$BASE" --pr
          else
            shipcraft ci --base "$BASE"
          fi

      # shipcraft pr waits for this status; shipcraft merge requires it.
      - name: Publish shipcraft/ci
        if: always() && steps.layer.outputs.run == 'true' && github.event_name == 'pull_request'
        env:
          GH_TOKEN: ${{ github.token }}
          STATE: ${{ steps.ci.outcome == 'success' && 'success' || 'failure' }}
        run: |
          gh api -X POST "repos/${{ github.repository }}/statuses/${{ github.event.pull_request.head.sha }}" \
            -f context=shipcraft/ci -f state="$STATE" -f description="GitHub Actions"
```

## The suite in your own checks

A project whose suite already runs in its own workflow (sharded, by impact, or
on several runners) does not need a second run of the whole suite inside
`shipcraft ci`. With `[execution] suite_checks`, `shipcraft/ci` only re-checks
every commit of the PR (locks, sealed files, the config under an open lock, the
hook files), and the named GitHub checks run the suite:

```toml
shipcraft_min = "2.18"

[execution]
ci = "github"
suite_checks = ["acceptance"]
```

`suite_checks` needs `ci = "github"` and `shipcraft_min = "2.18"` or above
(a binary older than 2.18 ignores the key). `shipcraft pr` then waits for
`shipcraft/ci` and every named check before the review, and `shipcraft merge`
requires every named check green (`success`) at the PR head, after
`shipcraft/ci`. A name is read from both check runs and commit statuses; every
producer of that name must be green.

### What a named check must do

- Run on `pull_request` and report on the PR head commit (GitHub Actions does).
- Always run: no `paths` filter that can skip it.
- Run the project's `[build]` and each suite's `check` too, not only the tests.
- Fail when any job it stands for fails or is cancelled.
- Have a name unique across the project's workflows and integrations.

A suite split into several jobs stands behind one aggregate job, which `needs:`
the suite jobs, runs `if: always()`, and fails unless each needed job's result
is `success`. A needed job may be `skipped` only when a scope job that itself
succeeded says, in an output the aggregate reads, that there was nothing for it
to run; a job skipped because a prerequisite failed fails the aggregate. This
is the shape of Shipcraft's own `acceptance` gate: `scope` must succeed, and
`linux` may be skipped only when `scope` reports mode `none`.

```yaml
name: acceptance

on:
  pull_request:

jobs:
  scope:
    runs-on: ubuntu-latest
    outputs:
      mode: ${{ steps.scope.outputs.mode }}
    steps:
      - uses: actions/checkout@v4
      - id: scope
        run: echo "mode=full" >> "$GITHUB_OUTPUT"   # "none" when there is nothing to run

  linux:
    needs: scope
    if: needs.scope.outputs.mode != 'none'
    runs-on: ubuntu-latest
    strategy:
      matrix:
        shard: [1, 2, 3]
    steps:
      - uses: actions/checkout@v4
      - run: ./run-suite.sh --shard ${{ matrix.shard }}

  # The check named in suite_checks.
  acceptance:
    needs: [scope, linux]
    if: always()
    runs-on: ubuntu-latest
    steps:
      - name: Every needed job succeeded
        env:
          SCOPE: ${{ needs.scope.result }}
          MODE: ${{ needs.scope.outputs.mode }}
          LINUX: ${{ needs.linux.result }}
        run: |
          [ "$SCOPE" = success ] || { echo "scope: $SCOPE"; exit 1; }
          if [ "$LINUX" = skipped ] && [ "$MODE" = none ]; then exit 0; fi
          [ "$LINUX" = success ] || { echo "linux: $LINUX"; exit 1; }
```

### One publisher of shipcraft/ci

For a PR, exactly one job publishes `shipcraft/ci`, chosen by the config that
judges it. Both jobs start with the same reader: a step that reads
`.shipcraft.toml` at the commit the job passes as `--base` (the PR's base SHA
on `pull_request`, the `before` SHA on `push`; `git show <that sha>:.shipcraft.toml`)
with Python's `tomllib` (present on GitHub's Ubuntu runners), not `grep`. A
base without the file falls back to HEAD's; a file the base has but that cannot
be read or parsed fails the step.

- The full-suite job (the workflow above) runs only when `execution.ci` is
  `"github"` and `execution.suite_checks` is absent or empty.
- The re-check job below runs only when `execution.ci` is `"github"` and
  `execution.suite_checks` is a non-empty array.

The re-check job is the workflow above without the language setup. It checks
out the PR head (`pull_request.head.sha`) with full history (`fetch-depth: 0`),
passes the PR's base SHA as `--base`, and keeps `GH_TOKEN` and the
permissions: the default-branch squash rule and the escape check read GitHub.

```yaml
# Shipcraft: with [execution] suite_checks, shipcraft/ci re-checks every commit
# of the PR; the named checks run the suite.
name: shipcraft-recheck

on:
  push:
  pull_request:

permissions:
  contents: read
  pull-requests: read
  statuses: write

jobs:
  recheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha || github.sha }}
          fetch-depth: 0

      # The same reader as the full-suite job, for the other publisher.
      - name: Does this job publish shipcraft/ci?
        id: layer
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha || github.event.before }}
          PUBLISHER: recheck
        run: |
          # A base without the file falls back to HEAD's; a file the base has
          # but that cannot be read or parsed fails the step.
          CFG=.shipcraft.toml
          if [ -n "$BASE_SHA" ] && git cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then
            ENTRY=$(git ls-tree "$BASE_SHA" -- .shipcraft.toml) \
              || { echo "::error::cannot read the tree of $BASE_SHA"; exit 1; }
            if [ -n "$ENTRY" ]; then
              git show "$BASE_SHA:.shipcraft.toml" > "$RUNNER_TEMP/base.shipcraft.toml" \
                || { echo "::error::cannot read .shipcraft.toml at $BASE_SHA"; exit 1; }
              CFG="$RUNNER_TEMP/base.shipcraft.toml"
            fi
          fi
          python3 - "$CFG" >> "$GITHUB_OUTPUT" <<'PY'
          import os, sys, tomllib
          path = sys.argv[1]
          config = {}
          if os.path.exists(path):
              with open(path, "rb") as f:
                  config = tomllib.load(f)  # a file that cannot be parsed fails the step
          execution = config.get("execution", {})
          checks = execution.get("suite_checks", [])
          mode = "none"
          if execution.get("ci") == "github":
              if checks == []:
                  mode = "full"
              elif isinstance(checks, list):
                  mode = "recheck"
          print("mode=" + mode)
          print("run=" + ("true" if mode == os.environ["PUBLISHER"] else "false"))
          PY

      - name: Install Shipcraft
        if: steps.layer.outputs.run == 'true'
        env:
          SHIPCRAFT_URL: ${{ vars.SHIPCRAFT_URL }}
        run: |
          curl -fsSL "$SHIPCRAFT_URL" -o "$RUNNER_TEMP/shipcraft"
          chmod +x "$RUNNER_TEMP/shipcraft"
          echo "$RUNNER_TEMP" >> "$GITHUB_PATH"

      - name: Re-check commits
        id: ci
        if: steps.layer.outputs.run == 'true'
        env:
          BASE: ${{ github.event.pull_request.base.sha || github.event.before }}
          GH_TOKEN: ${{ github.token }}
        run: |
          if [ -z "$BASE" ] || ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
            BASE=$(git rev-list --max-parents=0 HEAD | tail -n 1)
          fi
          if [ "$GITHUB_EVENT_NAME" = pull_request ]; then
            shipcraft ci --base "$BASE" --pr
          else
            shipcraft ci --base "$BASE"
          fi

      - name: Publish shipcraft/ci
        if: always() && steps.layer.outputs.run == 'true' && github.event_name == 'pull_request'
        env:
          GH_TOKEN: ${{ github.token }}
          STATE: ${{ steps.ci.outcome == 'success' && 'success' || 'failure' }}
        run: |
          gh api -X POST "repos/${{ github.repository }}/statuses/${{ github.event.pull_request.head.sha }}" \
            -f context=shipcraft/ci -f state="$STATE" -f description="GitHub Actions (re-check)"
```

### Migration order

1. First, a PR that adds the re-check job and the reader above. The re-check
   job runs nothing while the base's `suite_checks` is empty. A project whose
   base already has `ci = "github"` keeps its full-suite job, language setup
   included, gated by the same reader.
2. Then a PR that sets `ci = "github"`, `suite_checks` and
   `shipcraft_min = "2.18"`. It is still judged by its base's config; after it
   merges, PRs are judged the new way, and a later PR may remove the old
   full-suite job.
3. Then make the named checks and `shipcraft/ci` required where GitHub
   protects branches (`shipcraft init --github` marks only `shipcraft/ci` and
   `shipcraft/review`).

### What this leaves to the named checks

Which tests ran is their business: a check that runs a subset, or skips a
locked case, is trusted, and so is whether it ran `[build]` and `check`. At
HEAD, a lock left open while its cases pass and a locked case missing from the
run are not caught. A provider that reports on GitHub's test-merge commit
rather than the PR head never turns the name green. The escape check reads only
`shipcraft/ci` and `shipcraft/review`.

## Language setup

Python:

```yaml
      - uses: actions/setup-python@v5
        if: steps.layer.outputs.run == 'true'
        with:
          python-version: "3.x"
      - name: Install dependencies
        if: steps.layer.outputs.run == 'true'
        run: |
          python3 -m pip install pytest
          for f in requirements*.txt; do
            if [ -f "$f" ]; then python3 -m pip install -r "$f"; fi
          done
```

Node:

```yaml
      - uses: actions/setup-node@v4
        if: steps.layer.outputs.run == 'true'
        with:
          node-version: "lts/*"
      - name: Install dependencies
        if: steps.layer.outputs.run == 'true'
        run: npm ci || npm install
```

Go:

```yaml
      - uses: actions/setup-go@v5
        if: steps.layer.outputs.run == 'true'
        with:
          go-version-file: go.mod
      - name: Install dependencies
        if: steps.layer.outputs.run == 'true'
        run: |
          go mod download
          go install gotest.tools/gotestsum@latest
```

## Setup limits

The setup assumes a simple project with its manifest at the root. Adjust it for:

- pnpm workspaces: the Node setup uses npm, not pnpm;
- Python with pyproject.toml and no requirements*.txt: setup installs pytest but not project dependencies;
- Go with go.work and no root go.mod: go-version-file and go mod download need the correct module path.
