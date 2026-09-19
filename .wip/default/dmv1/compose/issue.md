---
priority: p2
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T01:01:39-04:00
blocked-on:
  - session
may-unblock:
  - docs
---

# Composition models: Cascade, Consensus, Cached

## Objective
Implement the composition models in core `DecisionModels`: `CascadeModel`, `ConsensusModel`, `CachedModel`.

## Context
Child of wip/dmv1. `DESIGN.md` section 10.2. They operate on `AnswerRecord` values only, so they need no knowledge of application types.

## Location
`Sources/DecisionModels/Composition/`: `CascadeModel.swift`, `ConsensusModel.swift`, `CachedModel.swift`, `DecisionCache.swift` (protocol plus an in-memory actor implementation). Tests in `Tests/DecisionModelsTests/Composition/`.

## Approach
- `CascadeModel(first:then:escalateBelow:)`: ask `first`; collect ids whose `record.confidence < threshold`; if any, ask `then` with a questionnaire restricted to those ids and merge records (second wins). `usage` sums. `quality` is the minimum. Identity `"cascade(a→b)"`. Capabilities are the intersection (min of limits, `structuredCriteria` and-ed).
- `ConsensusModel(_:samples:)`: run the inner model `samples` times concurrently (task group), average probabilities per id, recompute reported values (argmax for choice, mean score for rating, mean probability for verdict), drop reported confidence so the section 6.1 formula applies, `quality = .sampled(count:)` unless inner is `.calibrated` and samples agree (then keep `.calibrated`). Expose `disagreements: [String]` through a `ConsensusReport` returned by a separate `decideWithReport` method; the `DecisionModel` method returns just answers.
- `CachedModel(_:storage:)`: key = `DecisionRequest` hash plus inner identity; store `ModelResponse`; cached hits report zero usage.

## Related Issues
wip/session (blocker).

## Acceptance Criteria
- [ ] Cascade: with a fake first model returning low confidence on one of three ids, only that id is re-asked of the second fake, and the merged answers carry the second's record for it.
- [ ] Consensus: three fakes' worth of differing one-hot answers average to the expected distribution; `quality == .sampled(count: 3)`.
- [ ] Cached: second identical request does not reach the inner fake; a different state does.
