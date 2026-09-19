---
priority: p1
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T01:01:39-04:00
may-unblock:
  - session
  - composite
---

# Package skeleton and core value layer

## Objective
Create the SwiftPM package skeleton and implement the core value layer of `DecisionModels`: state, criteria, answer types with confidence math, and the `Codable` wire types that every provider and the macros build on.

## Context
Child of wip/dmv1. First issue; everything else depends on it. `DESIGN.md` sections 5.3 (protocols and `Criterion`), 6 (answers, `ProbabilityQuality`, `Distribution`, confidence formulas in 6.1), 7 (`State`, `StateRepresentable`, `StateBuilder`, `Field`), and 9 (wire level: `QuestionSpec`, `Questionnaire`, `AnswerRecord`, `Answers`, `Question`, `Choose`, `Rate`, `Verify`, `QuestionnaireBuilder`).

## Location
- `Package.swift`: declare every target now so later issues do not edit it concurrently: `DecisionModels`, `DecisionModelsMacros` (compiler plugin, depends on swift-syntax 602.x), `DecisionModelsTypeSafe`, `DecisionModelsApple`, `DecisionModelsTesting`, and test targets `DecisionModelsTests`, `DecisionModelsMacrosTests`, `DecisionModelsTypeSafeTests`, `DecisionModelsAppleTests`, `DecisionModelsTestingTests`. Platforms: `.iOS(.v18), .macOS(.v15)`. Swift tools 6.2. Later targets get one minimal placeholder file each so the package builds; the placeholder is replaced by the issue that owns the target.
- `.gitignore`: add `.build/`, `.swiftpm/`, `*.xcodeproj`, `xcuserdata/`, `DerivedData/`. Keep `.env`.
- `Sources/DecisionModels/`: one file per concept. Suggested: `State.swift`, `StateBuilder.swift`, `Criterion.swift`, `Options.swift` (`ChoiceOption`, `RatingLevel`), `ProbabilityQuality.swift`, `Distribution.swift`, `Answer.swift` (`Answer`, `ConfidenceBand`, `band`), `Choice.swift`, `Rating.swift`, `Verdict.swift`, `QuestionSpec.swift`, `AnswerRecord.swift`, `Questionnaire.swift`, `Answers.swift`, `Question.swift` (`Question`, `Choose`, `Rate`, `Verify`, `QuestionnaireBuilder`).
- `Tests/DecisionModelsTests/`.

## Approach
Follow the signatures in `DESIGN.md` exactly. Points that need care:
- `Distribution` is `Hashable` unconditionally and `Codable` where `Value: Codable`. `[Value: Double]` with a non-`String`/`Int` key encodes as an array of pairs under `Codable`; that is acceptable.
- `AnswerRecord.confidence` and the typed answers share one implementation of the section 6.1 formulas. Put the formulas in one internal `ConfidenceMath` enum used by both. Reported confidence wins when present.
- `Choice.value` is `reported ?? distribution.mostLikely`. `Rating.value` is `distribution.mostLikely`; `Rating.score` is the reported expected value.
- `Answers.choice(_:as:)` maps ids back through `CaseIterable`; `Choose.answer(from:)` maps through its own option list. Unknown ids throw `DecisionError.malformedResponse` (define `DecisionError` in this issue with the full case list from section 11; the session issue uses it).
- `Questionnaire.prefixed(_:)` and `Answers.scoped(to:)` use `"prefix.id"` with a single dot.
- `Answers.subscript` uses `get throws`.
- `State` gets the three `ExpressibleBy…Literal` conformances and `init(encoding:)` through `JSONEncoder` then `JSONDecoder` into `State`.
- `StateBuilder` builds `State.object`; supports `if`, `if let`, `for`, and `try` inside (closure type `() throws -> State`).
- `Criterion` is `ExpressibleByStringLiteral` and has the unlabeled `init(_ summary:notFor:examples:signals:)`.
- Everything `Sendable`. No Apple-only imports in this target (Foundation is fine).

## Related Issues
wip/dmv1 (parent), wip/session (next; adds `DecisionModel`, `DecisionSession`, `Decision`, `Askable`).

## Acceptance Criteria
- [ ] `swift build` succeeds for the whole package with placeholder targets; no warnings in package code.
- [ ] Confidence math tests: rating levels 0/1/2 with probabilities 0/0.7/0.3 give confidence 0.54 (±0.01) and score 1.3; a uniform choice over n options gives 0; a one-hot gives 1; verdict p=0.87 gives 0.74.
- [ ] Reported confidence overrides computed confidence on `Choice` and `Rating`.
- [ ] `Choice.value` prefers the reported option; falls back to argmax when absent.
- [ ] Round-trip `Codable` tests for `State`, `QuestionSpec`, `Questionnaire`, `AnswerRecord`, `Answers`, `Choice<Enum>`, `Rating<Enum>`, `Verdict`.
- [ ] `Answers[question]` returns typed answers for `Choose` with a run-time option list, `Rate`, and `Verify`; a missing id throws.
- [ ] `prefixed` and `scoped` round-trip.
- [ ] `StateBuilder` handles `if let` and `try Field(_:encoding:)`.
- [ ] `band(escalateBelow:confirmBelow:)` returns the right band at the boundaries (below low is escalate; at or above high is act).
