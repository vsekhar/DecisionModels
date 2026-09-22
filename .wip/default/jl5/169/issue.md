---
priority: p2
type: task
created: 2026-09-22T16:50:52-04:00
updated: 2026-09-22T17:27:06-04:00
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
