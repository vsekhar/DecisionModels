---
priority: p2
type: bug
created: 2026-09-21T00:38:25-04:00
updated: 2026-09-21T01:16:56-04:00
---

# Resolve questionnaire answers against their specs so AnswerRecord.confidence is exact

## Objective

`DecisionSession.decide(_ questionnaire:about:options:)` returns records whose probabilities cover the whole scale of each question, and rejects an unknown option id, a level index off the scale, or a reported confidence outside 0...1 as a malformed response. After that, `AnswerRecord.confidence` on any record the session returns is the section 6.1 value, not an estimate.

## Context

`AnswerRecord.confidence` computes the section 6.1 formula when the provider reports no confidence. The formula needs the size of the scale, `n`. The record does not carry it, so the library guesses: `optionCount: probabilities.count` for a choice and `ConfidenceMath.inferredLevelCount(probabilities)`, the highest index plus one, for a rating (`Sources/DecisionModels/AnswerRecord.swift:17,22`). A provider may leave out an option or level it gives zero weight. Then the guess is low and the confidence is wrong.

Probe against tag 0.1.0, a three-level scale, the provider reports two levels:

```
.rating(score: 0.3, probabilities: [0: 0.7, 1: 0.3],         confidence: nil).confidence == 0.0835
.rating(score: 0.3, probabilities: [0: 0.7, 1: 0.3, 2: 0.0], confidence: nil).confidence == 0.5417
```

Same distribution, same scale. Only the explicit zero differs, and the number moves by a factor of six, because the spread's denominator `(n - 1) / 2` goes from 0.5 to 1. A choice has the same fault: two of three options at 0.7/0.3 gives 0.12 against ln 2, where the value over three options is 0.44.

The typed path does not have this problem. `AnswerReader.choice` and `AnswerReader.rating` map each record against its options or `Level.levels`, start every level at zero (`AnswerReader.swift:73`), reject an index off the scale, and check a reported confidence with `validatedConfidence`. The typed answer knows the whole scale, and the doc comment on `AnswerRecord.confidence` says the record's own number is an estimate for that reason. The questionnaire path (`DecisionSession.decide(_:about:options:)`, `DecisionSession.swift:154`) skips the reader and returns `response.answers` as the provider wrote them; `send` runs `Preflight.check` on the request only.

The `decide` CLI (`../decide`, its wip/xhd) gates `--min-confidence` on this number over the questionnaire path. It works around the gap by filling absent options and levels with zero before asking `confidence`, and by rejecting a reported confidence outside 0...1 itself (`Sources/DecideCore/Runner.swift`). That is the library's knowledge duplicated in a client.

Not the fix: adding the count to `AnswerRecord`. The record is the provider's statement on the wire; the count is the asker's knowledge. Every provider mapping would have to copy it in, the `Codable` shape would change, and a hand-built record could still carry a wrong count.

## Location

- `Sources/DecisionModels/DecisionSession.swift`: the questionnaire `decide` (or `send`) gains a resolve step over `response.answers` against `questionnaire.specs`.
- `Sources/DecisionModels/AnswerReader.swift`: the completion, index, id, score, and confidence checks already exist for typed answers; factor them so both paths share them.
- `Sources/DecisionModels/AnswerRecord.swift`, `ConfidenceMath.swift`: `confidence` stays; its doc comment says a record the session returns is complete and the number exact, and a record from elsewhere is an estimate. Optionally a `confidence(optionCount:)` and `confidence(levelCount:)` form makes the count explicit at other call sites.
- `DESIGN.md` section 6.1, and the README where the questionnaire path is described.
- `Tests/DecisionModelsTests`: the reader and session tests.

## Approach

In the questionnaire path, after `send` returns, map each record to its spec by id:

- `.choice` under `.choice(options:)`: reject a `reported` id or a probability key that is not an option as `malformedResponse` naming the question; add every option the record leaves out at 0; validate a reported confidence with `validatedConfidence`.
- `.rating` under `.rating(levels:)`: reject an index outside `0..<levels.count`; add every absent index at 0; validate the score against the scale and the reported confidence, as `AnswerReader.rating` does.
- `.verdict` under `.verdict`: validate the probability as `AnswerReader.verdict` does.
- A record whose kind does not match the spec, or a spec with no record, is `malformedResponse`. The CLI checks this today; the library owning it is better.

Return `Answers` with the completed records and the same `quality`. `ConfidenceMath.normalized` stays as it is: zeros add nothing to the sum, the entropy, or the spread; they fix only `n`. Keep the typed path's behavior identical, and have both paths call one set of helpers so they cannot drift again.

## Related Issues

Found while building `--min-confidence` in the `decide` CLI (decide's wip/xhd; the fill and the probe are logged on decide's wip/eh3). Touches code from `jev` (the Jev provider) and `docs` in this tracker. Once this ships and `decide` moves its pin past 0.1.0, the CLI's fill in `Runner.decide` can go; its three pinned-number tests should still pass.

## Acceptance Criteria

- [ ] A questionnaire-path rating record that omits the top level gives the same `confidence` as one that lists it at zero (0.5417 for the probe above, not 0.0835); the same for a choice that omits an option (0.4439 for 0.7/0.3 over three options).
- [ ] A questionnaire-path record with an unknown option id, a level index off the scale, a probability outside 0...1, or a reported confidence outside 0...1 throws `DecisionError.malformedResponse` naming the question.
- [ ] `Answers.records` returned by `decide(_:about:options:)` holds every option id and level index of each spec, absent ones at 0.
- [ ] The typed path's tests are unchanged and pass; the typed and questionnaire paths call the same helpers.
- [ ] `AnswerRecord.confidence`'s doc comment says when the number is exact and when it is an estimate.
- [ ] `swift test -Xswiftc -warnings-as-errors` passes on macOS and Linux in CI.

---

_📝 Noted on 2026-09-21 00:47:51-04:00 @ git:328b744+local_

Design record (session 2026-09-21).

Shape:
- `AnswerReader` gains a wire-level resolve step beside the typed readers: `resolved(_ answers: Answers, against: Questionnaire) throws -> Answers` and `resolved(_ record: AnswerRecord, against: QuestionSpec) throws -> AnswerRecord`. Both stay internal; tests reach them through `@testable import`.
- The checks both paths share move into three helpers on `AnswerReader`: `completed(_:reported:optionIDs:id:)` for a choice (validates the map, rejects an unknown option id or reported id, adds every absent option at 0), `completed(_:score:levelCount:id:)` for a rating (validates the score against the scale and the map, rejects an index off the scale, adds every absent index at 0), and `validatedProbability(_:id:)` for a verdict. `validatedConfidence` stays. `validated(_:id:)` keeps its checks but no longer rescales; the typed readers rescale the mapped dictionary with `ConfidenceMath.normalized` when they build the `Distribution`, so typed answers are unchanged.
- `DecisionSession.send` resolves `response.answers` against the questionnaire after the usage is counted and the quality floor is checked, and returns a `ModelResponse` with the resolved answers. So every `Answers` the session returns is complete: the questionnaire path's return value and `DecisionResponse.answers` alike. The typed reader validates again when a decision reads its records; that is cheap and keeps `Question.answer(from:)` usable on records from elsewhere.

Decisions:
1. A resolved record keeps the provider's numbers and adds absent options and levels at 0. It is not rescaled. `AnswerRecord.confidence` normalizes on its own, so the number is exact either way, and the record stays the provider's statement over the whole scale.
2. A spec with no record throws `malformedResponse("Question <id> has no answer.")`. Through the session this replaces the `invalidQuestion` that `Answers.record(_:)` threw when the typed reader hit the gap; a hand-built `Answers` read outside the session keeps `invalidQuestion`, so the AskableTests and FanOutTests cases that expect it are untouched.
3. A record with no spec throws `malformedResponse("Question <id> was not asked.")`. The session built the request and knows what it asked; the promise that every record it returns is exact holds only if every record has a spec. Composition wrappers keep their own tolerance for extras because they merge several models.
4. A kind mismatch throws `malformedResponse("Question <id> expects a rating, but the record holds a choice.")`, the typed reader's wording, via a `QuestionSpec.Kind.kindName` beside `AnswerRecord.kindName`.
5. Not done: a `confidence(optionCount:)`/`confidence(levelCount:)` form on `AnswerRecord` (no caller in the package; dead code); a count on `AnswerRecord` (the issue rules it out); `ConfidenceMath.inferredLevelCount` stays for records from elsewhere.
6. Out of scope, filed separately: `CascadeModel.decideWithReport` gates on `record.confidence` of the first model's raw records (CascadeModel.swift:95), the same estimate. It sits below the session, so this fix does not reach it, and it tolerates a missing first answer on purpose, so a strict resolve does not fit there.

Probe numbers for the tests: rating [0: 0.7, 1: 0.3] over three levels gives 0.5417 once level 2 is at 0 (0.0835 before); choice refund 0.7 / search 0.3 over the three-skill catalog gives 0.4439 once escalate is at 0 (0.1189 before).

---

_📝 Noted on 2026-09-21 00:51:31-04:00 @ git:328b744+local_

Filed vrb for the CascadeModel gate (decision 6 in the design record). Implementation delegated to a worker from the design record; verifier runs after the diff is read.

---

_📝 Noted on 2026-09-21 01:00:00-04:00 @ git:328b744+local_

Design record, revision 1: decision 2 is replaced.

The worker's first pass made a question with no record throw `malformedResponse`. Three tests in `Tests/DecisionModelsMacrosTests/CommandEndToEndTests.swift` failed: "An unchosen case needs no answers", "A case with no arguments needs no answers of its own", "A command nests in another decision with dotted ids". Each fakes a provider that answers the choice and only the chosen case's arguments, through the session. DESIGN.md 5.1 says a `@Decision` enum asks every case's arguments in one request and decodes only the chosen case. Those tests fix that a response may leave the unchosen cases out. A session-level check would forbid what the command path allows, and a two-step wrapper that asks the chosen case's arguments only could never satisfy it.

New decision 2: a question with no record stays absent. The session resolves the records it has; a read that needs the missing one throws `invalidQuestion(id:, reason: "The response holds no answer.")` from `Answers.record(_:)`, as before. The acceptance criteria do not name a missing record, only the Approach paragraph did. The `decide` CLI keeps its own missing-question check when it drops the fill.

Decision 3 stands: a record with no question still throws `malformedResponse("Question <id> was not asked.")`. The session cannot complete a record it has no spec for, so keeping it would break the promise that every record the session returns is exact. No existing test tripped this rule.

Test change that follows: the ResolvedAnswersTests case for a missing record now asserts that the gap passes through and the typed read throws `invalidQuestion` naming the question.

---

_📝 Noted on 2026-09-21 01:16:56-04:00 @ git:328b744+local_

Verifier report and routing. No blockers; suite green (451 tests, 48 suites); the six mutants named in the brief all die; typed path matches HEAD over 40,000 random records (probabilities within 2.2e-16 because the rescale now sums the completed map).

1. Accepted as designed: a record for an unchosen case of a @Decision enum that is malformed (unknown option id, index off the scale) now fails the call, where HEAD ignored it because no read touched it. The session asked the question; an answer with an unknown option is malformed whichever case wins, and dropping it would break the promise that every record the session returns is exact. No test pins this; add one if it ever needs defending.
2. Fixed: DESIGN.md 6.2 claimed "the same checks" run at the wire level, which would include the duplicate-option-id check (Preflight's job there) and rescaling (which the resolve step does not do). Reworded to name the checks that do run and to say the step adds absent options and levels at zero and does not rescale. Also replaced "closes the gap" with "fills it in" in 6.1.
3. Noted on vrb: resolved(_ record:against:) does not reject a spec whose options share an id (Preflight stops it before the session sends, so unreachable here); a hand-built DecisionRequest driven straight into CascadeModel never met Preflight.
4. Nits, no action: the `?? 0` fallbacks in the typed readers are unreachable; the "score outside 0...-1" message for an empty scale is unreachable through both paths.

Summary of the work: AnswerReader gains resolved(_ answers:against:) and resolved(_ record:against:) plus the shared helpers completed(_:reported:optionIDs:id:), completed(_:score:levelCount:id:), validatedProbability; validated no longer rescales, the typed readers rescale the mapped dictionary. DecisionSession.send returns the resolved answers, so both decide(_ questionnaire:) and DecisionResponse.answers are complete. Doc comments on AnswerRecord.confidence and the questionnaire decide, DESIGN.md 6.1/6.2/8/9, and the README bullet describe the behavior. New suite "Resolved answers" (15 tests) pins the probe numbers 0.5417 and 0.4439, the not-rescaled rule, the typed path's complete records, the eight malformed cases, the absent-question pass-through, and the idempotent resolve.
