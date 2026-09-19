---
priority: p3
type: task
created: 2026-09-19T13:39:32-04:00
updated: 2026-09-19T13:39:32-04:00
---

# Honor explicit Int raw values as @Levels order

## Objective
Let a `@Levels` enum state its level order in text: when the enum has an `Int` raw type, the macro uses `rawValue` as the level index and validates it.

## Context
`@Levels` takes declaration order as the scale's order, which matches how Swift synthesizes `CaseIterable` and `Comparable` (SE-0266). The order is implicit, so a reorder or an inserted case silently shifts every level's wire index (Jev keys score probabilities by index). Filed after the 2026-09-19 discussion of ordering options; the decision was to keep declaration order as the default and honor explicit raw values when a team wants the order reviewable. See DESIGN.md 5.3.

## Location
`Sources/DecisionModelsMacros/LevelsMacro.swift`, `AnswerSpace.swift` (case reading), `Sources/DecisionModels/Options.swift` (`RatingLevel.levels` and `levelIndex`, which today derive from `allCases` order), snapshot and diagnostic tests in `Tests/DecisionModelsMacrosTests/`, DESIGN.md 5.3.

## Approach
- If the enum's inheritance clause names `Int` (or `UInt`, `Int8`, and so on), read each case's explicit `= n` and Swift's auto-increment rule to compute the raw value per case at expansion time.
- Diagnose: values that are not `0...(count - 1)`, duplicates, and a raw type other than an integer type (a `String` raw type is a diagnostic: level ids are case names, and the string raw type would not be the order).
- Emit `levels` (or the equivalent ordering witness) sorted by raw value so `levelIndex == rawValue`, and write `<` by `rawValue`. Note that raw-value enums are excluded from synthesized `Comparable`, so the macro keeps writing `<` for them.
- Keep `optionID` as the case name regardless of raw type. Check what synthesized `Codable` does for an `Int` raw type (it encodes the integer); decide whether `@Levels` should write a name-based `Codable` for consistency with `@Options`, and record the decision in DESIGN.md 5.3.
- Declaration order stays the default when there is no raw type.

## Related Issues
wip/scalehash (detect a reordered scale at replay), wip/synthcmp (let the compiler synthesize `Comparable` for the no-raw-type case).

## Acceptance Criteria
- [ ] `@Levels enum Severity: Int { case cosmetic = 0, degraded, blocking }` expands with indices from the raw values; reordering the cases in source does not change the questionnaire's level order.
- [ ] Gaps, duplicates, out-of-range values, and a `String` raw type each give one clear diagnostic.
- [ ] Round trip through `Rating<Severity>` and `AnswerRecord.rating` uses the raw value as the index.
- [ ] DESIGN.md 5.3 documents both forms and which one `Codable` encoding applies to.
