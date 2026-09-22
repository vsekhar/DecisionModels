---
priority: p3
type: bug
created: 2026-09-22T18:46:44-04:00
updated: 2026-09-22T18:46:44-04:00
---

# On-device model collapses two similar yes-or-no questions to one answer

## Objective
Find out why `GuidedGenerationModel` answers two similar yes-or-no questions in one request with the same value, and either fix it in the adapter or document it as a limit of the on-device model.

## Context
Found on 2026-09-22 while writing the stateless live test for wip/169, on a Mac with Apple Intelligence, macOS 27, one greedy sample. The prompt, instructions, and schema were checked and are right. The effect shows with and without a state, so it is not about wip/jl5.

| Request | capital | control |
|---|---|---|
| "Is Paris the capital of France?" alone | 1.0 | |
| the same + "Is the Moon made of cheese?" | 1.0 | 0.0 |
| the same + "Is Paris the capital of Germany?" | 0.0 | 0.0 |
| the same + "Is Berlin the capital of Germany?" (both true) | 0.0 | 0.0 |
| the same pair, with state "Paris is the capital of France." | 0.0 | 0.0 |
| "Is Atlanta the capital of Georgia?" alone, or "of the U.S. state of Georgia?" alone | 0.0 | |

So a second boolean field about the same topic pulls the first to false under greedy decoding, and the model does not know Atlanta's status either way. The existing live tests do not hit this: their one boolean sits beside a choice and a rating.

## Location
- `Sources/DecisionModelsApple/PromptBuilder.swift` and `SchemaBuilder.swift`: the prompt's question headings and the schema's boolean properties.
- `Tests/DecisionModelsAppleTests/GuidedGenerationLiveTests.swift`: a local-only test that pins whatever this issue decides.

## Approach
1. Reproduce with the table above through the public API, one sample.
2. Try adapter-side changes that keep the one-request design: a short instruction that each yes-or-no field is judged on its own; ordering the boolean fields apart in the schema; giving each boolean property a description in the `DynamicGenerationSchema`. Measure each against the table.
3. If nothing helps, document the limit in DESIGN.md section 10.1 and in the `GuidedGenerationModel` doc comment, and add a local live test that records the behaviour so a future OS model that fixes it shows up as a change.

## Related Issues
wip/169 chose an unrelated control for its live test because of this. wip/jl5 is the parent it was found under, but this issue is not part of that feature.

## Acceptance Criteria
- [ ] A note records the reproduction and each mitigation tried, with numbers.
- [ ] Either the adapter answers the table's true pairs correctly, or DESIGN.md and the doc comment state the limit and a local live test pins it.
