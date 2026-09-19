---
priority: p2
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T01:01:39-04:00
blocked-on:
  - session
may-unblock:
  - docs
---

# Apple adapter: GuidedGenerationModel with live tests

## Objective
Implement `GuidedGenerationModel` in `DecisionModelsApple`: a `DecisionModel` over Apple's FoundationModels that answers a whole questionnaire in one guided-generation call, with live tests against `SystemLanguageModel`.

## Context
Child of wip/dmv1. `DESIGN.md` sections 10.1 (GuidedGenerationModel), 14, 15.1 (availability: types `@available(iOS 26, macOS 26, *)`; generic `LanguageModel` init `@available(iOS 27, macOS 27, *)`; error types differ between 26 and 27). This Mac runs macOS 26.6 with Xcode 26.6, so both initializers can compile; the live test uses `SystemLanguageModel.default`.

## Location
`Sources/DecisionModelsApple/`: `GuidedGenerationModel.swift`, `SchemaBuilder.swift` (questionnaire → `DynamicGenerationSchema`), `PromptBuilder.swift` (state, instructions, criteria → prompt text), `ResponseMapping.swift` (`GeneratedContent` → `Answers`), `ErrorMapping.swift`, `Availability.swift`. Tests in `Tests/DecisionModelsAppleTests/`.

## Approach
- One `DynamicGenerationSchema` object per request with a property per question id: choice → string with `anyOf(optionIDs)`; rating → integer with `range(0...n-1)`; verdict → `Bool`. Use `GenerationSchema(root:dependencies:)` and `session.respond(to:schema:options:)`. Property names must be valid; map ids with dots to a safe name and back.
- Prompt: instructions block that explains the task, then the state as pretty JSON, then each question with its instructions and criteria (choice options as `id: criterion`, rating levels as `index: criterion`, verdict true/false clarifications). Keep it short; the on-device context is small. If the questionnaire has more questions than fit, throw `.contextSizeExceeded`.
- `samples == 1`: greedy sampling, `Answers.quality = .pointEstimate`, one-hot probabilities. `samples = k > 1`: k generations at temperature 1.0, empirical probabilities, `.sampled(count: k)`. Capabilities: `probabilityQuality: .sampled(count: .max)`, structured criteria and instructions false (rendered to text), `maximumOptionsPerChoice: 64`, `maximumLevelsPerRating: 10`, `contextTokens` from `model.contextSize` when available, `supportsRepeatedSamples: true`.
- Error mapping: guardrail violation → `.guardrailViolation`; refusal → `.refused`; context window exceeded → `.contextSizeExceeded`; unsupported language → `.unsupported(.structuredInstructions)` is wrong, use `.malformedResponse` with the message; everything else → `.transport`. Handle both `LanguageModelSession.GenerationError` (26) and `LanguageModelError` (27) behind `#available`.
- Availability maps `SystemLanguageModel.Availability` one-to-one; `deviceNotEligible`, `appleIntelligenceNotEnabled` → `.notConfigured`, `modelNotReady`.
- Usage: read `response.usage` behind `#available` if it exists; otherwise zero.
- Live tests **fail** with a clear message when `SystemLanguageModel.default.availability` is not `.available`. Test one questionnaire (choice, rating, verdict) on an unambiguous state; assert the choice, the rating band, and the verdict, and that `quality == .pointEstimate`. One more test with `samples: 3` asserting `quality == .sampled(count: 3)` and probabilities sum to 1.

## Related Issues
wip/session (blocker), wip/macros (nice for tests; not required).

## Acceptance Criteria
- [ ] Schema builder unit tests (no model needed): property per question, `anyOf` for choice, `range` for rating, dotted ids round-trip.
- [ ] Prompt builder unit tests: contains state JSON, every question id and criterion.
- [ ] Response mapping unit tests from hand-built `GeneratedContent`.
- [ ] Live tests pass on this Mac and fail when the system model is unavailable.
