---
priority: p3
type: task
created: 2026-09-19T13:39:32-04:00
updated: 2026-09-19T13:39:32-04:00
---

# Let the compiler synthesize Comparable for @Levels

## Objective
Let the compiler synthesize `Comparable` for a `@Levels` enum with no raw type, instead of the macro writing `<` over `allCases.firstIndex`.

## Context
SE-0266 synthesizes `Comparable` for enums without raw values by declaration order. That is exactly the rule `@Levels` relies on, so letting the compiler state it makes the design's claim ("declaration order is the order") Swift's own claim, and removes a force-unwrap from generated code. Raw-value enums are excluded from synthesis, so once wip/rawlevels lands the macro still writes `<` for them. Filed after the 2026-09-19 ordering discussion. See DESIGN.md 5.3 and 12.

## Location
`Sources/DecisionModelsMacros/LevelsMacro.swift`, `Sources/DecisionModels/Macros.swift` (the `@Levels` declaration's `names:` list no longer needs `named(<)` for the synthesized case), snapshot tests in `Tests/DecisionModelsMacrosTests/AnswerSpaceExpansionTests.swift`, DESIGN.md 12.

## Approach
- In the no-raw-type case, emit `Comparable` in the extension's conformance list and no `<`; confirm the compiler synthesizes it for a conformance declared in a macro-generated extension in the same file (it does for `CaseIterable` and `Codable`; check `Comparable` the same way and record the result).
- If synthesis does not apply through the extension, keep the written `<` but derive it from a switch over cases rather than `firstIndex(of:)!`.
- Add a test that `Severity.allCases.sorted() == Severity.allCases` and that `cosmetic < degraded < blocking`, whichever path is taken.
- Document in DESIGN.md 5.3 that a hand-written `RatingLevel` conformance may return `allCases` in any order and the framework follows it; only the macro guarantees declaration order.

## Related Issues
wip/rawlevels (raw-value enums keep a written `<`), wip/scalehash.

## Acceptance Criteria
- [ ] The `@Levels` expansion for an enum without a raw type contains no hand-written `<` when synthesis works, and ordering tests pass.
- [ ] DESIGN.md 5.3 and 12 describe the mechanism and the hand-written-conformance caveat.
