---
priority: p2
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T02:58:13-04:00
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

---

_📝 Noted on 2026-09-19 01:07:52-04:00 @ git:c886133+local_

SDK inventory (Xcode 26.6, FoundationModels module 1.5.2, target macos26.5) at scratchpad foundationmodels-api.md. Findings that change the approach: (1) The macOS/iOS 27 surface is absent: no LanguageModel protocol, no PrivateCloudComputeLanguageModel, no LanguageModelCapabilities, no LanguageModelError. Implement only the SystemLanguageModel initializer now; leave the generic init for when Xcode 27 is installed and record that in DESIGN.md 15.1. (2) No usage or token-accounting API exists on LanguageModelSession or Response. Report Usage with inputTokens estimated via SystemLanguageModel.tokenCount(for:) (26.4+, guarded by #available) and outputTokens 0; document it as an estimate. (3) GeneratedContent has no properties()/elements() methods; read values with value(_:forProperty:) or switch on .kind. (4) contextSize is back-deployed and hardcodes 4096 before 26.4; this Mac reports 4096. (5) UnavailableReason has exactly three cases: deviceNotEligible, appleIntelligenceNotEnabled, modelNotReady. (6) GenerationOptions has one init; temperature is a property on GenerationOptions, not on SamplingMode. (7) GenerationError has 9 cases with enum-level 26.0 availability only. Probe on this Mac: SystemLanguageModel.default is AVAILABLE; a trivial respond took 3.5 s.

---

_📝 Noted on 2026-09-19 02:58:13-04:00 @ git:d9a6c44+local_

Done in a worktree, merged by copy. GuidedGenerationModel over SystemLanguageModel only (the Xcode 26.6 SDK has no LanguageModel protocol): one DynamicGenerationSchema per request, prompt with state and criteria as text, token guard, sequential unseeded draws for samples > 1. Verifier: all 4 criteria hold; live answers stable; usage arithmetic exact. Changes after verification: capabilities declare structured criteria and instructions as accepted (rendered to text, per DESIGN 5.3); assetsUnavailable maps to unavailable(.modelNotReady); concurrentRequests to overloaded; unsupportedGuide to invalidQuestion; whole-call deadline across draws (mutation-proven live test); token-count errors mapped; reserve scales with question count; flaky severity assertion dropped. Live suite passes from main after the merge. DESIGN.md 10, 10.1, 14 updated.
