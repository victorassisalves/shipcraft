# npm packages

`release/npm.sh <version>` builds and publishes them from the GitHub release of that version:

- `shipcraft`: the `shipcraft` command, a Node launcher (`npm/shipcraft/bin/shipcraft.js`) that runs the native binary of the platform package installed next to it;
- `shipcraft-darwin-arm64`, `shipcraft-darwin-x64`: the release binary of each macOS target, unchanged (same bytes as the release archive, checked against `SHA256SUMS`).

Installing is two steps: add the package (`pnpm add -D shipcraft`, or npm, yarn), then run `pnpm exec shipcraft init` (or `npx shipcraft init`) at the repository root, which wires the hooks to that install (item 58). Adding the package alone checks nothing.
