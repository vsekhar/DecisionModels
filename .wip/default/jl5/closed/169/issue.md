---
priority: p2
type: task
created: 2026-09-22T16:50:52-04:00
updated: 2026-09-22T19:10:05-04:00
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

---

_📝 Noted on 2026-09-22 18:41:59-04:00 @ git:6c76094+local_

Design record amendment, 2026-09-22, after the worker's first live run: the on-device model answered 'Is Atlanta the capital of Georgia?' with capital 0.0 and the control 'Is Paris the capital of Germany?' with 0.0, twice. The control is right and the answer is well formed and one-hot, so the stateless prompt and instructions work; the small local model most likely reads Georgia as the country. Two decisions. (1) The stateless instruction line 'Answer every question from what it says and what you know.' had no referent for 'it'; it becomes, verbatim, 'Answer every question from the question itself and what you know.' The instruction test's 'what you know' assertion still holds. (2) The live test asks 'Is Atlanta the capital of the U.S. state of Georgia?' with the same control; if the model still answers below 1, it asks 'Is Paris the capital of France?' as capital with 'Is Paris the capital of Germany?' as control instead. The expectations stay one-hot: capital 1, control 0. The worker probes each variant once and reports the probabilities; the winning variant and the numbers go in the closing note. Jev and OpenRouter keep the plain Atlanta question, which they answer at 0.97.

---

_📝 Noted on 2026-09-22 18:46:44-04:00 @ git:6c76094+local_

Second amendment, 2026-09-22. Both variants in the first amendment fail: capital 0.0 with the disambiguated Atlanta question, and 0.0 for 'Is Paris the capital of France?' when paired with the Paris/Germany control. The worker's probes show why: alone, Paris/France answers 1.0; paired with any second capitals question, true or false, both fields come back 0.0; paired with 'Is the Moon made of cheese?' it answers 1.0 and the control 0.0; and Atlanta answers 0.0 even alone. That two-field collapse is a limit of the on-device model, not of this change, and is filed as wip/bte. Decision: the live test asks capital 'Is Paris the capital of France?' and control 'Is the Moon made of cheese?', expectations one-hot 1 and 0. It proves what wip/169 needs: with no state the model answers from what it knows and does not answer yes to everything. Jev and OpenRouter keep the plain Atlanta question.

---

_📝 Noted on 2026-09-22 18:48:24-04:00 @ git:6c76094+local_

Progress 2026-09-22: implemented by one worker with wip/169, wip/sxu, and wip/in4 together; the diff matches the records. Offline suite with warnings as errors: 477 tests pass, 5 new offline. Apple live suite on this Mac: 6 tests pass; the new stateless test observed capital 1.0 ('Is Paris the capital of France?') and control 0.0 ('Is the Moon made of cheese?'). Verifier next, then CI on a branch. Worker's judgement calls kept: the doc sentence sits as its own paragraph after the summary line; the two line sets are separate literal arrays chosen by a ternary, so the stateful text is unchanged byte for byte.

---

_📝 Noted on 2026-09-22 18:57:24-04:00 @ git:6c76094+local_

Verifier 2026-09-22: no blocker; notes acted on: the 'unchanged' instruction test now asserts the whole stateful text against a literal instead of comparing the function with itself; the live test also checks the hasState wiring through the usage count, as usageAddsUp does; the fixture comment and the tracker id in the live test's doc comment are replaced by plain wording. Apple's .null handling is recorded on wip/in4.

---

_📝 Noted on 2026-09-22 19:05:51-04:00 @ git:6c76094+local_

Follow-ups applied 2026-09-22: the stateful text is pinned to a literal; hasState(_:) treats .null as no state; the live test checks usage (190 tokens observed, 190 expected) after the expectations, under a plain 26.4 guard so an older OS still runs the main claim. Apple offline suite 48 tests, live suite 6, all green.

---

_📝 Noted on 2026-09-22 19:10:05-04:00 @ git:6d17446+local_

Closed 2026-09-22. Commit 6d17446 on branch stateless-apple-hierarchy, merged to main. CI run 35795731059 green on macOS, Linux, and the iOS build. All acceptance criteria met. Live on this Mac: capital 'Is Paris the capital of France?' 1.0, control 'Is the Moon made of cheese?' 0.0, stateless usage 190 tokens as counted. The plain Atlanta question stays on Jev and OpenRouter; the on-device model answers it false under every wording, and pairs of capitals questions collapse, see wip/bte.
