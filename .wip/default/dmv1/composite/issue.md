---
priority: p2
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T01:01:39-04:00
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
