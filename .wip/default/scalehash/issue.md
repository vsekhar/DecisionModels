---
priority: p3
type: task
created: 2026-09-19T13:39:32-04:00
updated: 2026-09-19T13:39:32-04:00
---

# Carry the scale legend in rating records to detect reordering

## Objective
Make a reordered or changed scale detectable: carry the level criteria (or a hash of them) in `AnswerRecord.rating`, so replay and evaluation can refuse a fixture recorded against a different scale.

## Context
Score probabilities travel keyed by level index. If a `@Levels` enum gains a case in the middle or its cases are reordered, an old recording replays against a scale it was not recorded on and nothing notices; the enum's own `Codable` uses case names, but the record does not. Jev returns a `legend` (index → description) with every score answer, which the provider currently drops. Filed after the 2026-09-19 ordering discussion. See DESIGN.md 6, 9, 13.

## Location
`Sources/DecisionModels/AnswerRecord.swift`, `AnswerReader.swift`, `Rating.swift` (`record`), `Sources/DecisionModelsTypeSafe/JevMapping.swift` (keep the legend), `Sources/DecisionModelsApple/ResponseMapping.swift` (write the legend from the questionnaire), `Sources/DecisionModelsTesting/ReplayModel.swift` and `Evaluation.swift`, DESIGN.md 6.2, 9, 13.

## Approach
- Add an optional `legend: [Int: String]?` (level summaries by index) to `AnswerRecord.rating`, or a `scale: String` digest of the level criteria in order. A legend is more readable in fixtures and matches what Jev already returns; a digest is smaller. Pick one and record the reason.
- Providers fill it: Jev from the response's legend; the Apple adapter from the questionnaire's level criteria; `Rating.record` from `Level.allCases`' criteria.
- `AnswerReader.rating` compares the record's legend to the level type's criteria and throws `DecisionError.malformedResponse` (or a new, clearer case) when they disagree, naming the first mismatched index. A record with no legend (older fixture) passes with no check.
- `Evaluation` uses the same check, so a labeled set built against an old scale fails loudly rather than scoring nonsense.
- Keep `Codable` backward compatible: the new field is optional and decodes as `nil` when absent.

## Related Issues
wip/rawlevels, wip/synthcmp.

## Acceptance Criteria
- [ ] A recorded rating replays cleanly against the same scale and throws against a scale whose levels were reordered or renamed, with the mismatched index in the message.
- [ ] Jev live and unit tests show the legend kept from the wire.
- [ ] Old fixtures without the field still decode and replay.
- [ ] DESIGN.md records the field and the check.
