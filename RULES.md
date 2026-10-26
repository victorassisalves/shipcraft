# How Shipcraft is developed

Eight rules. Each one exists because breaking it cost measured time before. A rule that stops paying for itself is removed.

1. **Measure first.** No new mechanism, rule or feature without a measured cost it removes. Each one ships with its metric and the condition that removes it. Time to main and escapes are the numbers that decide.

2. **Good-faith threat model.** Shipcraft protects against an honest agent that makes mistakes or takes shortcuts, not an adversary. When Shipcraft has to infer something about a project (a root, a runner, a file format), a failed inference may cost time but must never produce a wrong verdict.

3. **Cheapest layer first.** Catch each error at the cheapest layer that can catch it: context before writing, compiler and linter, hook, CI, review, production. A defect that reached a later layer is a question for the earlier one.

4. **Reproduce before you fix.** A defect becomes work only after it reproduces on main, with the command and its output written down. When an item depends on how git or another tool behaves, prove the mechanism in a scratch repository before writing the spec.

5. **Small items.** An item is one observable behavior: at most 3 points in the spec and about 400 lines of product code (tests don't count). Anything bigger is split before the RED, and the remainder is a new item that has to earn its place.

6. **Short specs.** A spec item is the contract only, about one page. It names the reader or semantics for every input it reads, and what happens when reading fails. Examples become RED cases, not rules. One spec review per item (two at most). It reports only what would produce a wrong verdict or a contradiction. Everything else goes to the RED, whose reading becomes a fixed point of the acceptance battery.

7. **Review blocks only what matters.** A review blocks a change only for a wrong verdict (a false refusal or an escape), a crash, or a broken contract, and the reviewer must reproduce it. A time cost without a wrong verdict becomes an item, not a blocker. At most two review rounds. After that, a person decides.

8. **RED and GREEN are different agents.** The agent that writes the tests does not write the code that passes them. They can be the same model in separate sessions. The lock, not trust, keeps the GREEN from changing the RED's tests.

## Trials

A trial (POC) runs only if its result changes a decision, and only one at a time. It has a question, a metric, a baseline, a deadline of 1 to 7 days, and thresholds to keep or kill. When the number is clear, the verdict is automatic. Trial code never becomes product: if the trial passes, the product is written from the spec.
