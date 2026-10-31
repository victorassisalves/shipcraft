# npm packages

`release/npm.sh <version>` builds and publishes them from the GitHub release of that version:

- `shipcraft`: the `shipcraft` command, a Node launcher (`npm/shipcraft/bin/shipcraft.js`) that runs the native binary of the platform package installed next to it;
- `shipcraft-darwin-arm64`, `shipcraft-darwin-x64`: the release binary of each macOS target, unchanged (same bytes as the release archive, checked against `SHA256SUMS`).

Installing is two steps, and step 2 is required: add the package (`pnpm add -D shipcraft`, or npm, yarn), then run `pnpm exec shipcraft init` (or `npx -- shipcraft init`) at the repository root. `init` sets up Shipcraft and wires its hooks to that install (item 58); until it runs, Shipcraft checks none of your commits. The packages run no install script (item 69), so nothing is printed at install time. The `shipcraft` package carries the root `README.md`.
