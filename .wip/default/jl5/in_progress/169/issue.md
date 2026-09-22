---
priority: p2
type: task
created: 2026-09-22T16:50:52-04:00
updated: 2026-09-22T17:50:51-04:00
blocked-on:
  - e7t
may-unblock:
  - n96
---

# Apple: a stateless prompt and instructions for the on-device model

## Objective
When a request has no state, the Apple provider sends a prompt with no `STATE` block and instructions that let the on-device model answer from the question and its own knowledge, instead of the current "judge what the state says, and add nothing to it".

## Context
Child of the parent feature; blocked on the core child. The core child makes `DecisionPromptBuilder.prompt(state:questionnaire:fieldNames:)` take `State?` and skip the `STATE` block, but leaves the standing instructions in `PromptBuilder.instructions(adding:)` (`PromptBuilder.swift:29`) unchanged. Those open with "You answer questions about a state." and include "Read the state, then answer every question." and "Be literal. Judge what the state says, and add nothing to it." For "Is Atlanta the capital of Georgia?" with no state, those lines tell the model not to use what it knows.

## Location
- `Sources/DecisionModelsApple/PromptBuilder.swift`: `instructions(adding:)` gains a stateless variant, by a flag or a second function.
- `Sources/DecisionModelsApple/GuidedGenerationModel.swift:105`: pass whether the request has a state.
- `Tests/DecisionModelsAppleTests/PromptBuilderTests.swift`: prompt and instruction tests for both cases.
- `Tests/DecisionModelsAppleTests/GuidedGenerationLiveTests.swift`: one on-device test. CI's runners cannot run Apple Intelligence, so it runs locally only; see TESTING.md.

## Approach
- Instructions with a state: unchanged byte for byte, so the existing tests and the recorded behaviour hold.
- Instructions without a state: open with "You answer questions." and "Answer every question from what it says and what you know.", keep the JSON, schema, choice, rating, and yes-or-no lines, and drop the "Be literal" line. The caller's extra instructions still follow.
- The prompt without a state starts at the first question heading: no `STATE` line and no `null`.
- The token estimate and the context check need no change; they count whatever text results.

## Related Issues
Parent feature; the core child.

## Acceptance Criteria
- [ ] Prompt tests: with a state the prompt is unchanged; without one it contains neither `STATE` nor `null`, and every question is still named.
- [ ] Instruction tests: the stateless text has no sentence about a state and keeps the format rules; the stateful text is unchanged.
- [ ] Live, local: `GuidedGenerationModel` answers the Atlanta question true, with a probability at or above a threshold read off a real run on a Mac with Apple Intelligence. A note on this issue records the run.
- [ ] The offline Apple suite passes and CI is green.

---

_📝 Noted on 2026-09-22 17:27:06-04:00 @ git:2f0531d+local_

From the wip/e7t verifier, 2026-09-22: wip/e7t's prompt with no state now starts at the first question heading with no leading newline (a small fix after the verifier flagged a leading blank line), and PromptBuilderTests gained one test that pins that shape: no STATE line, no null, first line is the first heading. Write the instruction tests against the real bytes and keep that test green.

---

_📝 Noted on 2026-09-22 17:50:50-04:00 @ git:fadedf3+local_

Design record, 2026-09-22, for wip/169.

### 1. `DecisionPromptBuilder.instructions` (`Sources/DecisionModelsApple/PromptBuilder.swift:29`)
Signature: `static func instructions(adding extra: String? = nil, hasState: Bool = true) -> String`. With `hasState: true` the text is byte for byte what it is today. With `hasState: false` the lines are, verbatim:
```
You answer questions.

Answer every question from what it says and what you know.
Reply with JSON only. It must match the schema: one field per question,
every field present.
For a choice question, give exactly one option id from that question's list.
For a rating question, give the index of the level that fits.
For a yes or no question, give true or false.
```
So the stateless text drops "about a state" from the first line, replaces "Read the state, then answer every question." with the "what you know" line, and leaves out "Be literal. Judge what the state says, and add nothing to it." The caller's `extra` still follows after a blank line, as today. Doc comment gains one sentence after the first: "With no state, they leave out the lines about the state and let the model answer from the question and what it knows."

### 2. Call site (`Sources/DecisionModelsApple/GuidedGenerationModel.swift:107`)
`DecisionPromptBuilder.instructions(adding: extraInstructions, hasState: request.state != nil)`. The `prewarm` call at line 94 keeps the default; it has no request.

### 3. Tests
- `Tests/DecisionModelsAppleTests/PromptBuilderTests.swift`: "Instructions without a state let the model use what it knows": `instructions(hasState: false)` contains "what you know" and "Reply with JSON only." and the three format lines, and does not contain the word "state"; with `adding: "Answer in the shop's voice."` the extra comes last. "Instructions with a state are unchanged": `instructions(adding: nil, hasState: true) == instructions()` and the text contains "Be literal." (the existing test at line 69 already covers the rest).
- `Tests/DecisionModelsAppleTests/GuidedGenerationLiveTests.swift`: "The model answers questions that carry their own facts": the same guards as the other live tests; `DecisionSession(model: GuidedGenerationModel(.default))`; `session.decide(Questionnaire { Verify("capital", "Is Atlanta the capital of Georgia?"); Verify("control", "Is Paris the capital of Germany?") })` with no `about:`; one sample is one-hot, so expect `capital` is `.verdict(probability: 1)` and `control` is `.verdict(probability: 0)`. Local only; CI cannot run it.

### Checks
`swift test -Xswiftc -warnings-as-errors --skip GuidedGenerationLiveTests --skip JevLive --skip OpenRouterLive`, then `swift test --filter GuidedGenerationLiveTests` on this Mac. Record the observed probabilities in the issue.
