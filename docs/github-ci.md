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
# Runs only when .shipcraft.toml sets [execution] ci = "github"; with local CI,
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

      # A PR uses the base config, not its own.
      - name: Does CI run on GitHub?
        id: layer
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
        run: |
          CFG=.shipcraft.toml
          if [ -n "$BASE_SHA" ] && git show "$BASE_SHA:.shipcraft.toml" > "$RUNNER_TEMP/base.shipcraft.toml" 2>/dev/null; then
            CFG="$RUNNER_TEMP/base.shipcraft.toml"
          fi
          if grep -Eq '^[[:space:]]*ci[[:space:]]*=[[:space:]]*"github"' "$CFG"; then
            echo "run=true" >> "$GITHUB_OUTPUT"
          else
            echo "::notice::[execution] ci is not \"github\" in .shipcraft.toml: CI runs through shipcraft pr."
          fi

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
