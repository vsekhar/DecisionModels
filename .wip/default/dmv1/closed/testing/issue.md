---
priority: p2
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T02:55:21-04:00
blocked-on:
  - session
may-unblock:
  - linux
  - docs
---

# Testing module: scripted, recording, replay, evaluation

## Objective
Implement `DecisionModelsTesting`: `ScriptedModel`, `DecisionRecord`, `RecordingModel`, `ReplayModel`, and `Evaluation`.

## Context
Child of wip/dmv1. `DESIGN.md` sections 10.2 (wrappers) and 13 (testing and evaluation).

## Location
`Sources/DecisionModelsTesting/`: `ScriptedModel.swift`, `DecisionRecord.swift`, `RecordingModel.swift`, `ReplayModel.swift`, `Evaluation.swift`, `Calibration.swift` (Brier score, expected calibration error). Tests in `Tests/DecisionModelsTestingTests/`.

## Approach
- `ScriptedModel(identity:capabilities:_ answer: @Sendable (DecisionRequest) async throws -> Answers)`; usage zero; also `init(answering: Answers)` convenience.
- `DecisionRecord: Codable, Sendable` holds `request`, `response`, `model`, `metadata`, `duration`, `recordedAt`.
- `RecordingModel(_ model: some DecisionModel, into recorder: Recorder)` where `Recorder` is a `Sendable` actor collecting records and able to write JSON to a URL.
- `ReplayModel(records: [DecisionRecord])` keyed by `DecisionRequest` hash; throws `.malformedResponse("no recording for request")` on miss; mirrors the recorded model's identity and capabilities.
- `Evaluation(models: [any DecisionModel])` with `run<D: Decision>(_: D.Type, on: [(state: State, expected: D)]) async throws -> Report`. `Report[identity].question(id)` gives accuracy (argmax equals expected), Brier score over the distribution, expected calibration error with 10 bins, and band counts for given thresholds. Expected values come from `expected.answers` records, so no reflection is needed.

## Related Issues
wip/session (blocker), wip/compose (Cascade, Consensus, Cached live in core, not here).

## Acceptance Criteria
- [ ] `RecordingModel` around a `ScriptedModel` produces records that `ReplayModel` serves back identically; a different request throws.
- [ ] `DecisionRecord` JSON round-trips.
- [ ] `Evaluation` on a hand-built labeled set gives accuracy 1.0 and Brier 0 for perfect one-hot answers, and known values for a chosen imperfect set (compute by hand in the test).
- [ ] ECE of a perfectly calibrated synthetic set is 0 (±0.01).

---

_📝 Noted on 2026-09-19 02:55:21-04:00 @ git:54a57e0+local_

Done in a worktree, merged by copy. ScriptedModel, DecisionRecord, ReplayKey, Recorder, RecordingModel, ReplayModel, Evaluation with Calibration math. Verifier: all 4 criteria hold, math recomputed independently. Its should-fixes fixed: Rating.value now breaks ties to the lower level (core change, so evaluation and application agree; one old core assertion updated); choice calibration bins on the probability of the named answer; Evaluation preconditions distinct identities. Docs: ECE bin convention, round-tripped records scored on purpose. DESIGN.md 6.2 and 13 updated.
