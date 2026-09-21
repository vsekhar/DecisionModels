---
priority: p3
type: bug
created: 2026-09-21T00:50:01-04:00
updated: 2026-09-21T01:16:56-04:00
---

# Resolve the first model's records before CascadeModel gates on confidence

## Objective

`CascadeModel.decideWithReport` compares the exact section 6.1 confidence of each first-model record against `threshold`, not an estimate from a record that lists only part of the scale.

## Context

`Sources/DecisionModels/Composition/CascadeModel.swift:95` reads `record.confidence` on the raw record the first model returned. `AnswerRecord.confidence` guesses the size of the scale from the keys the record holds, so a first model that leaves out an option or level it gave zero weight gives a low number (a factor of six in the probe on 3qq: 0.0835 against 0.5417 for the same distribution over three levels). The cascade then escalates a question the first model answered with confidence, and pays the second model for nothing.

Issue 3qq put the resolve step in `DecisionSession.send`, above the model layer, so it does not reach the cascade. The cascade escalates a question the first model skipped on purpose (`CascadeModelTests` "A question the first model skipped escalates"), so the strict `AnswerReader.resolved(_ answers:against: Questionnaire)` does not fit here. The per-record `AnswerReader.resolved(_ record:against: QuestionSpec)` does: it completes one record and validates it, and the cascade already walks `request.questionnaire.specs`.

## Location

- `Sources/DecisionModels/Composition/CascadeModel.swift`: `decideWithReport`.
- `Tests/DecisionModelsTests/Composition/CascadeModelTests.swift`.
- `DESIGN.md` section 10.2, if the wording on the gate changes.

## Approach

In `decideWithReport`, for each spec with a first-model record, resolve the record against the spec, gate on the resolved record's `confidence`, and keep the resolved record in the merged output so the cascade's own response is complete too. Decide what a malformed first record does: recommend throw, because it is the `malformedResponse` the session would raise anyway, and letting the second model answer instead would hide a broken provider. Records from the second model are resolved by the session after the cascade returns, so they can stay as they are here.

## Related Issues

Follows 3qq, which added `AnswerReader.resolved(_:against:)` and the shared checks. `ConsensusModel` does not gate on confidence, so it is not affected.

## Acceptance Criteria

- [ ] A first-model rating record over three levels that omits the top level gates the same way as one that lists it at zero.
- [ ] A first-model record with an unknown option id, a level off the scale, or a reported confidence outside 0...1 throws `DecisionError.malformedResponse` naming the question.
- [ ] A question the first model skipped still escalates.
- [ ] The existing cascade tests pass unchanged.
- [ ] `swift test -Xswiftc -warnings-as-errors` passes on macOS and Linux in CI.

---

_📝 Noted on 2026-09-21 01:16:56-04:00 @ git:328b744+local_

From 3qq's verifier: AnswerReader.resolved(_ record:against:) does not reject a spec whose options share an id (options.map(\.id) collapses them, so optionCount comes out low). The session never reaches it because Preflight.checkSanity throws invalidQuestion first, but a hand-built DecisionRequest driven straight into CascadeModel never met Preflight. When the cascade resolves first-model records, either run the duplicate check there or accept the gap and say so.
