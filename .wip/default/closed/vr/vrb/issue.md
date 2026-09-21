---
priority: p3
type: bug
created: 2026-09-21T00:50:01-04:00
updated: 2026-09-21T01:33:58-04:00
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

---

_📝 Noted on 2026-09-21 01:21:29-04:00 @ git:33ef04d+local_

Design record (session 2026-09-21).

- `CascadeModel.decideWithReport` walks `request.questionnaire.specs`. For each spec with a first-model record it calls `AnswerReader.resolved(record, against: spec)`, stores the resolved record in the merged output, and gates on the resolved record's `confidence`. A spec with no record escalates, as at HEAD. A first-model record with no spec passes through untouched, as at HEAD; a session rejects it later as "was not asked".
- The second model's records for the escalated ids are resolved the same way on merge, so the cascade's own response is complete whether or not a session sits above it. Only the escalated ids are taken from the second model, as at HEAD.
- A malformed record from either model throws `malformedResponse` out of the cascade. For the first model this happens before the second model is asked: it is the error a session would raise on the merged output anyway, and asking the second model instead would hide a broken provider.
- The early return for "nothing escalated" now builds a `ModelResponse` from the resolved records, with the first model's usage and request id unchanged.
- `AnswerReader.completed(_:reported:optionIDs:id:)` rejects two options with one id with `invalidQuestion`, the typed reader's message. The typed reader's own check runs first, so its behavior is unchanged; the wire path gains the check for a spec that never met Preflight (3qq's verifier finding 3).
- DESIGN.md 10.2 says the cascade resolves before it gates.

Not done: resolving inside `ConsensusModel` (it does not gate on confidence; its averages go through the session's resolve).

---

_📝 Noted on 2026-09-21 01:33:58-04:00 @ git:33ef04d+local_

Verifier report and routing. No blockers; offline suite green (455 tests, 48 suites); the five named mutants die; a sweep of a thin against a full three-level rating across bars 0.05...0.95 gave identical escalation, second-model calls, and merged records.

1. Fixed (should-fix): the test "A malformed first answer throws before the second model is asked" had no pending escalation, so a refactor that deferred the resolve past the second call would have survived it (the verifier's own sixth mutant did). The fixture's "b" now carries confidence 0.1, so an escalation is pending when the bad answer throws; the verifier confirmed this shape kills that mutant in its scratch copy.
2. Added: a cascade test over a three-level rating that omits the top level (the issue's own probe, 0.0835 against 0.5417) and a test that a malformed second answer throws out of the cascade too.
3. Fixed (nits): the DESIGN.md 10.2 sentence and the decideWithReport doc comment said "every record" where a first record with no spec passes through unresolved, and read as if the second model's records met a bar. Both now say the cascade resolves each answer the questionnaire asked for, a first answer before the bar and a second answer on merge, in active voice.
4. Not done: a cascade-level test for a level off the scale and a confidence outside 0...1 (both throw; they share the one resolve call with the covered case and are pinned at the resolver level in ResolvedAnswersTests).
5. Pre-existing, for the record: AnswerRecord.confidence is not bit-reproducible across dictionary iteration orders (about 2e-16). Resolve is exactly idempotent on the record, so nothing drifts; only a confidence that lands on the bar exactly could flip.

Summary: CascadeModel.decideWithReport resolves each first answer against its spec before the bar and each second answer on merge, throws malformedResponse before asking the second model on a bad first answer, and builds the early-return response from the resolved records. AnswerReader.completed(_:reported:optionIDs:id:) rejects two options with one id as invalidQuestion, so the wire path agrees with the typed reader for a spec that never met Preflight. DESIGN.md 10.2 describes the gate. Five new cascade tests and one resolver test.
