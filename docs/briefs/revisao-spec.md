You are reviewing a SPEC before any test or code is written for it. Nothing for it is implemented yet; the goal is to find problems at the cheapest point.

Repository: the current directory (Shipcraft v2, a CLI `shipcraft` that enforces RED/GREEN test discipline through a git hook, a CI command and a review gate; Rust core in nucleo/, acceptance suite in acceptance/).

Read:
- docs/spec.md: {{ITEMS}}, and any earlier item they change; skim the rest for context.
- acceptance/README.md (the fixed points), RULES.md (rules 2, 6 and 7 matter here).
- You may read nucleo/src to understand how the current binary works.
Do not run anything that modifies the repository.

Task: list what the spec items leave open or get wrong, as seen by someone who must implement them for real projects (Python/pytest, Node/vitest/jest/TypeScript, Go), including monorepos. For each finding give, in one entry:
- the rule or sentence of the spec;
- a concrete project/scenario (layout, runner config, command, git state) where a reasonable implementation of the spec as written would go wrong;
- the consequence: wrong verdict (false refusal or escape), extra cost (time, tests that run when they should not), or contract unclear.
Always answer, as the first findings, RULES.md rule 6's question: which input does the item read (a file, a format, a glob, a tool's output) without saying which reader or semantics applies, or without saying what happens when reading it fails? Name the input and a real variant the wording would miss.
Then answer two more questions, before the other findings. In item 38 they surfaced only after the RED and GREEN had started, and cost 48 of its 106 minutes.
- **Battery contradictions:** search all of `acceptance/` (cases, tools, fixed points) for every case that asserts on something the item changes: a file it writes, a log row or field, a message, a refusal or an exit code. List each case id with the assertion that the item would break. The coordinator fixes the spec or names the cases to adjust before the RED.
- **Readings the RED would have to pick:** list each point where two reasonable implementations differ, one line each with the sentence and a proposed reading. Typical points are field names and types, ordering and ties, rounding and percentile method, the denominator of a fraction, what counts and what is excluded, the empty input, and the output when a step fails. The coordinator fixes them in the spec before the RED.
Prefer concrete, distinct scenarios over general advice. At most 25 findings, most important first. No preamble.

Write the findings in Markdown to the file {{OUTPUT}} in the current directory, and nothing else.
