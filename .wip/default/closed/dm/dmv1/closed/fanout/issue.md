---
priority: p2
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T05:39:02-04:00
blocked-on:
  - macros
may-unblock:
  - docs
---

# Set fan-out projection

## Objective
Add `Set` fan-out: `@Ask("Does the request mention {option}?") var symbols: Set<Symbol>` expands to one yes/no question per case.

## Context
Child of wip/dmv1. `DESIGN.md` section 16, first bullet. Builds on the `Askable` protocol (wip/session) and `@Ask` (wip/macros).

## Location
`Sources/DecisionModels/FanOut.swift` (`FanOut<Option>` projection and `Set: Askable` conformance), macro changes in `Sources/DecisionModelsMacros/AskMacro.swift` for the `minimumProbability:` argument, tests in both test targets, `DESIGN.md` 5.2 table gains the `Set<T>` row back.

## Approach
- `FanOut<Option: ChoiceOption & CaseIterable>: Sendable` holds `[Option: Verdict]`, `members(atLeast p: Double) -> Set<Option>`, `subscript(option) -> Verdict`, and `quality`.
- `Set: Askable where Element: ChoiceOption & CaseIterable`: `questions(id:_:)` emits one `verdict` spec per case with id `"\(id).\(optionID)"` and instructions with `{option}` replaced by the case's criterion summary (when instructions is a `.text`; for structured instructions replace inside every string leaf). `projection(in:id:)` collects the verdicts. `read(_:)` is `members(atLeast: 0.5)`; `read(_:minimumProbability:)` for the argument form.
- The plain-value initializer takes `Set<Symbol>` and builds certain verdicts (1.0 for members, 0.0 otherwise).

## Related Issues
wip/macros (blocker), wip/session.

## Acceptance Criteria
- [ ] Expansion test for the `Set` property with and without `minimumProbability`.
- [ ] End-to-end: a fake model answering three verdicts yields the expected `Set` and `$symbols[.nvda].probability`.
- [ ] Template replacement covers text and structured instructions.

---

_📝 Noted on 2026-09-19 05:39:02-04:00 @ git:4330fb9+local_

Done in a worktree, merged by copy. FanOut projection, Set: Askable with per-case verdict questions and {option} substitution, two @Ask overloads with minimumProbability. Verifier: all criteria hold, including a live 5-sample run on the device. Its latent finding fixed: FanOut.quality now folds over every case, so a partial fan-out (invented uncertain verdicts) reports a point estimate; the empty-fan-out assertion moved with it. Added a nested fan-out regression test. DESIGN.md 5.2 (Set row, forms, conformance table) and 16 updated.
