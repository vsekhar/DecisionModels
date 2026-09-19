---
priority: p2
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T02:03:13-04:00
blocked-on:
  - types
may-unblock:
  - docs
---

# Composite score helper

## Objective
Add a composite scoring helper: a weighted sum over `Rating.normalized` values with the weights visible in code.

## Context
Child of wip/dmv1. `DESIGN.md` section 16, fourth bullet.

## Location
`Sources/DecisionModels/CompositeScore.swift`, tests in `Tests/DecisionModelsTests/`.

## Approach
- `struct CompositeScore: Sendable { init(@CompositeBuilder _ terms: () -> [Term]) ; var value: Double ; var terms: [(name: String, weight: Double, normalized: Double, contribution: Double)] ; var minimumConfidence: Double }` where a `Term` is `Weighted(0.4, "python", rating)` for any `Rating`. Weights are normalized to sum to 1. `minimumConfidence` is the lowest confidence among terms, following the Jev function-calling recipe's rule that the weakest judgment sets the composite's reliability.
- `Verdict` terms are allowed too, using `probability` as the normalized value.

## Related Issues
wip/types (blocker).

## Acceptance Criteria
- [ ] Two ratings with weights 0.4 and 0.6 produce the hand-computed value; weights 2 and 3 normalize to the same.
- [ ] `minimumConfidence` is the minimum of the terms.
- [ ] `terms` reports each contribution.

---

_📝 Noted on 2026-09-19 02:03:13-04:00 @ git:3777d22+local_

Done in a worktree, merged by copy. CompositeScore with Weighted terms for Rating and Verdict, result builder, normalized weights, per-term contributions, minimumConfidence as the weakest term. Verifier: all criteria hold; its coverage findings fixed: tests for the 0...1 clamp, NaN, exit tests for negative and NaN weights, overflowing weights (now finite-guarded), builder for/else/array paths. Its pointer on the reader fixed: AnswerReader.rating now rejects a score off the scale (malformedResponse), with a test. DESIGN.md 16 and 6.2 updated.
