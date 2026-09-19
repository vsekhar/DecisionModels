---
priority: p1
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T02:54:03-04:00
blocked-on:
  - session
may-unblock:
  - fanout
  - commands
  - docs
---

# Compiler plugin: @Decision, @Ask, @Options, @Levels, @Criterion

## Objective
Implement the compiler plugin: `@Decision`, `@Ask`, `@Options`, `@Levels`, `@Criterion`. After this issue the section 4 example of `DESIGN.md` compiles and runs against a fake model unchanged.

## Context
Child of wip/dmv1. `DESIGN.md` sections 5.1, 5.2, 5.3, and 12 (the expansion). The `Askable` machinery from wip/session is what the expansion calls, so the macros emit uniform code and never inspect conformances.

## Location
- `Sources/DecisionModels/Macros.swift`: the `macro` declarations (`@attached(...)`) that expose the plugin.
- `Sources/DecisionModelsMacros/`: `Plugin.swift`, `DecisionMacro.swift`, `AskMacro.swift`, `OptionsMacro.swift`, `LevelsMacro.swift`, `CriterionMacro.swift`, `Diagnostics.swift`.
- `Tests/DecisionModelsMacrosTests/`: expansion tests and end-to-end tests.

## Approach
- `@Ask`: `@attached(peer, names: prefixed(`$`))` plus `@attached(accessor)`. Overloads: `@Ask(_ instructions: String, minimumConfidence: Double? = nil, ifTrue: String? = nil, ifFalse: String? = nil)`, `@Ask(instructions: State, ...)`, and `@Ask()` for nested decisions. The peer is `var $name: T.Projection` where `T` is the property's declared type text; the accessor is `get { T.read($name) }` or `get { T.read($name, minimumConfidence: x) }`. Emit an error if an `Optional`-syntax type (`T?` or `Optional<T>`) lacks `minimumConfidence`.
- `@Decision`: `@attached(extension, conformances: Decision, names: named(questions), named(init(answers:)), named(answers))` plus `@attached(member, names: arbitrary)` for the plain-value initializer. It reads each `@Ask` property, builds `static let questions = Questionnaire(A.questions(id:_:) + ...)`, `init(answers:)`, `var answers`, and `init(<name>: <Type>, ...)` in declaration order. `quality` in `answers` is the minimum over members. Emit an error for enums in this issue (wip/commands lifts it) and for non-`@Ask` stored properties without a default value.
- `@Options`: `@attached(extension, conformances: ChoiceOption, CaseIterable, Askable, names: named(optionID), named(criterion), named(Projection))`. `Hashable`, `Sendable`, `Codable` come from the enum being a simple enum plus `Codable` added in the same extension. `@Criterion` is a no-op peer macro; `@Options` reads its arguments. A case without `@Criterion` gets a humanized case name (`camelCase` to `camel case`).
- `@Levels`: as `@Options` plus `RatingLevel`, `Comparable` (`<` via `allCases.firstIndex`), error when fewer than two cases.
- Expansion tests with `assertMacroExpansion` for each macro, including diagnostics. End-to-end tests compile the section 4 types in the test target and run them through `DecisionSession` with a fake model.
- swift-syntax 602.x. Build time for the plugin is long; run the macro test target with `--filter` while iterating.

## Related Issues
wip/session (blocker), wip/fanout and wip/commands (extend these macros).

## Acceptance Criteria
- [ ] Section 4 example compiles as written (types, `needsHuman`, `$team.probabilities`, `$severity.score`, `$requestsRefund.probability`) and returns expected values from a fake model.
- [ ] Nested `@Ask() var bug: BugReport` works end to end with dotted ids.
- [ ] `@Ask("…", minimumConfidence: 0.7) var team: Team?` gates to `nil`; the plain-value init takes `Team?` and `nil` stores `.uncertain`.
- [ ] Structured `@Ask(instructions: ["question": "…", "focus": "…"])` produces an object `instructions` in the spec.
- [ ] Diagnostics: optional without threshold; `@Levels` with one case; `@Decision` on an enum (for now).
- [ ] `@Criterion` arguments reach `criterion`; missing `@Criterion` humanizes the case name.
- [ ] Expansion snapshot tests for all five macros.

---

_📝 Noted on 2026-09-19 02:04:17-04:00 @ git:b62ee8e+local_

Session notes that bind the expansion: emit the declared type verbatim (T? sugar parses in every position); for an optional property always emit read(_:minimumConfidence:), never the one-argument read; Choice.uncertain needs CaseIterable. Because a macro cannot tell a leaf from a nested Decision, add to Askable a static answers(from:id:) that returns a leaf's single record or a nested decision's prefixed answers, and an Answers(merging:) that unions records and takes the minimum quality; the synthesized answers merges one per property.

---

_📝 Noted on 2026-09-19 02:54:03-04:00 @ git:b62ee8e+local_

Done. Five macros in DecisionModelsMacros; Askable gained answers(from:id:) and per-kind certain(_:), Answers gained init(merging:). Verifier: all 7 criteria hold (it compiled DESIGN.md section 4 verbatim). Its should-fixes fixed: implicitly unwrapped optionals rejected with one message; @Ask takes State and Criterion and minimumConfidence as a plain Double on its own overload; questions/init(answers:)/answers now emitted as members so a decision nested in a namespace enum resolves sibling types (extension carries only Decision, Sendable); one diagnostic per mistake; optionID is a switch over case names; raw identifiers keep backticks; acronyms keep case; snapshots match the compiler's conformance requests; empty @Decision struct diagnosed; generic decisions compile (questions is a static var). Two-binding declarations get the toolchain's own message; a macro cannot speak there. DESIGN.md 5.1, 5.2, 5.3, 12 updated to the generated shape.
