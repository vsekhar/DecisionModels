---
priority: p2
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T01:01:39-04:00
blocked-on:
  - macros
may-unblock:
  - docs
---

# @Decision on enums: commands with arguments

## Objective
Support `@Decision` on enums with associated values: one choice over the cases plus argument questions for every case in one request; only the chosen case's arguments are read.

## Context
Child of wip/dmv1. `DESIGN.md` section 16, second bullet. This is the Jev function-calling recipe, shaped like `@Generable` enums with associated values. Depends on wip/macros.

## Location
`Sources/DecisionModelsMacros/DecisionEnumMacro.swift` (or a branch in `DecisionMacro.swift`), `Sources/DecisionModels/CommandDecision.swift` for any run-time support, tests in the macro test target, a short subsection added to `DESIGN.md` 5.1 describing the enum form.

## Approach
- Enum requirements: each case may have labeled associated values whose types are `Askable`. Each associated value carries its question text through a new attribute on the case: `@Ask` is a property attribute, so use `@Arguments("symbol": "Which symbol…", "window": "Which window…")` on the case, or `@Criterion` for the case's own description plus a per-argument `@Ask` inside a nested struct. Pick the form that keeps the enum readable and record the choice in `DESIGN.md`; the recommended form is: the case gets `@Criterion("Plot a chart")`, and its associated values are a single `@Decision` struct (`case plot(PlotArguments)`), so argument questions reuse the existing struct machinery and ids become `plot.symbol`.
- Generated: `static let questions` = a choice spec with id `"case"` over the case names plus each case's struct questions prefixed by the case name; `init(answers:)` reads the choice, then builds only the chosen case's struct from scoped answers; `var answers` re-emits all; `$case: Choice<CaseName>` exposed through a generated `var choice: Choice<Kind>` where `Kind` is a generated nested `@Options` enum of case names.
- Plain-value initializers are the enum cases themselves; `answers` for a plain case marks the other cases' arguments `.uncertain`.

## Related Issues
wip/macros (blocker).

## Acceptance Criteria
- [ ] Section 16 `Command` example (adapted to the chosen form) compiles and, against a fake model, yields `.plot(PlotArguments(symbol: .nvda, window: .month))` and `command.choice.confidence`.
- [ ] Unchosen cases' arguments are not decoded (fake answers for them may be absent).
- [ ] Diagnostics for cases whose payload is not a single `Decision` struct.
- [ ] `DESIGN.md` documents the enum form.
