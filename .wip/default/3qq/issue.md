---
priority: p2
type: bug
created: 2026-09-21T00:38:25-04:00
updated: 2026-09-21T00:38:25-04:00
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
