#!/usr/bin/env node
// The `shipcraft` command of the npm package: runs the native binary from the
// platform package npm or pnpm installed next to it (optionalDependencies).
'use strict';
const { spawnSync } = require('child_process');

const pkg = `shipcraft-${process.platform}-${process.arch}`;
let bin;
try {
  bin = require.resolve(`${pkg}/bin/shipcraft`);
} catch {
  console.error(
    `shipcraft: no binary for ${process.platform}-${process.arch} (package ${pkg} is not installed).\n` +
      'Packages exist for macOS (darwin-arm64, darwin-x64); elsewhere build from source: ' +
      'https://github.com/victorassisalves/shipcraft#quick-start'
  );
  process.exit(2);
}
const run = spawnSync(bin, process.argv.slice(2), { stdio: 'inherit' });
if (run.error) {
  console.error(`shipcraft: could not run ${bin}: ${run.error.message}`);
  process.exit(2);
}
if (run.signal) process.kill(process.pid, run.signal);
process.exit(run.status === null ? 1 : run.status);
