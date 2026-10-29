# Contributing

Shipcraft is built by one maintainer, in the open, with a measured process: every change goes through a spec, a locked RED, a GREEN and a review before it reaches `main`.

**Pull requests from outside the project are not accepted for now.** A workflow closes them automatically with a pointer here. This is not about the quality of your change: each change has to go through that process, and it cannot take outside code yet.

What helps a lot:

- **Bug reports.** Open an issue with the Shipcraft version (`shipcraft --version`), the command you ran, its full output (the three-line refusal included) and, when you can, a small repository that reproduces it.
- **Field reports.** How Shipcraft behaved in your project: false refusals, slow hooks, an agent that got around the lock, a runner or hook manager it did not handle. Numbers help (`shipcraft report`).
- **Ideas.** Open an issue describing the problem first, not the solution.

Security problems: do not open a public issue; see [SECURITY.md](SECURITY.md).
