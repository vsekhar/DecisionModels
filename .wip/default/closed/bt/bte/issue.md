---
priority: p3
type: bug
created: 2026-09-22T18:46:44-04:00
updated: 2026-09-22T20:03:27-04:00
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

---

_📝 Noted on 2026-09-22 19:23:26-04:00 @ git:69bf22d+local_

Experiment plan, 2026-09-22, for wip/bte. The worker runs it on this Mac with Apple Intelligence; nothing here touches a hosted API.

### Harness
A scratch package outside the repository, depending on the package by path, or a temporary test in Tests/DecisionModelsAppleTests that is deleted before the diff is reported. It drives `DecisionSession(model: GuidedGenerationModel(.default))` through the public API and prints, per request, the verdict probabilities. Every request uses one sample (greedy) unless the row says otherwise. Run each row three times; the model is deterministic under greedy, so three identical runs confirm the reading and a split shows noise.

### Baseline table (reproduce first)
| Row | Questions in one request | Expected if the model were right |
|---|---|---|
| 1 | "Is Paris the capital of France?" | 1 |
| 2 | row 1 + "Is the Moon made of cheese?" | 1, 0 |
| 3 | row 1 + "Is Paris the capital of Germany?" | 1, 0 |
| 4 | row 1 + "Is Berlin the capital of Germany?" | 1, 1 |
| 5 | row 3 with state "Paris is the capital of France. Berlin is the capital of Germany." | 1, 0 |
| 6 | row 4 with the same state | 1, 1 |
| 7 | row 3 with three samples at temperature one | anything but 0, 0 on every draw |

### Mitigations, measured one at a time against rows 3 to 6, then combined
A. One instruction line for every mode, appended after "For a yes or no question, give true or false.": "Judge each yes or no question on its own; two questions can both be true."
B. A description on each boolean property in the schema (`SchemaBuilder`), the question's instructions text, if the builder does not pass one already. Read `SchemaBuilder.build` first and report what it passes today.
C. The question heading in the prompt repeated as the field's description and the field name made distinct, if B shows the name alone is what the model sees.

### Decision rule
If one mitigation or a combination makes rows 3 to 6 right without changing the six existing Apple live tests' results, keep it, with a doc comment on the change and a local live test that asks row 3 and row 4 and expects 1, 0 and 1, 1. If nothing works, change no code: add the limit to DESIGN.md section 10.1's Apple paragraph and to the `GuidedGenerationModel` type doc, and add a local live test that asks row 4 and records the collapse as the expected result, with a comment saying a future OS model that fixes it will turn the test red on purpose.

### Report
The full table with numbers for the baseline and for each mitigation, the diff, and the two runs: the offline suite with warnings as errors and the Apple live suite.

---

_📝 Noted on 2026-09-22 19:44:45-04:00 @ git:2b16bfe+local_

Experiments run 2026-09-22 by a worker on this Mac, three runs per row, greedy unless noted; logs in the session scratchpad (bte-*.log). Baseline: Paris/France alone 1.0; with the Moon control 1.0/0.0; with Paris/Germany 0.0/0.0; with Berlin/Germany 0.0/0.0; with a state naming both facts, both pairs come back right (1.0/0.0 and 1.0/1.0); three samples at temperature one give 0 to 0.67 for the first field. Mitigation A (an instruction line 'Judge each yes or no question on its own; two questions can both be true.') fixes only the first field of the Berlin pair and would break the exact-text instruction test. Mitigation B (the question text as each boolean property's description; SchemaBuilder passes description nil for every property today) fixes the Paris/Germany pair but leaves Berlin collapsed and breaks the existing no-state live test (Moon control drags Paris to 0.0). A+B is wrong on both pairs. C skipped: its precondition failed once B showed the model reads descriptions. Extra probe through the public API: ids paris_france and paris_germany give 1.0/0.0, ids paris_france and berlin_germany give 1.0/1.0. So the collapse follows the JSON field names, which are the caller's question ids: generic ids collapse, ids that name the facts do not. Decision: no adapter change (rule's second branch). DESIGN.md 10.1 and the type doc state the limit with the id finding and the state finding; the sentence I first gave the worker said 'with or without a state', which the numbers contradict, and is corrected. A seventh local live test pins the Berlin pair under generic ids at 0/0 and says a future OS model that answers it right turns the test red on purpose. An adapter-side idea, deriving the schema field name from the question text, is filed as its own low-priority issue rather than done here.

---

_📝 Noted on 2026-09-22 19:54:09-04:00 @ git:2b16bfe+local_

Verifier 2026-09-22: one blocker, fixed. It ran the controls the worker's id probe lacked, nine runs each, all deterministic: under the ids capital/control the first field is false whatever question it holds (Paris/Berlin, Berlin/Paris, Sun/Moon, Rome/Madrid); every other id pair tried, generic or not (q1/q2, a/b, field1/field2, capitalA/capitalB, capital1/capital2, control/capital swapped, paris_france/control), answers both right; capital/berlin_germany still gives capital 0.0. So 'generic ids collapse, descriptive ids do not' was false. DESIGN.md 10.1, the type doc, the test's doc comment, and TESTING.md now say only what the data shows: the effect follows the field names in a way not yet understood, capital/control with two same-topic questions makes the first field false, other id pairs answer right, a state naming both facts makes the answers right. The live test is unchanged and passes (seven Apple live tests green, offline suite green). wip/phi is rewritten from an adapter change into an investigation, with the verifier's table as its starting point.

---

_📝 Noted on 2026-09-22 20:03:26-04:00 @ git:63aeab8+local_

Closed 2026-09-22. Commit 63aeab8 on branch apple-boolean-collapse, merged to main; CI run 35799660116 green. No adapter code changed. DESIGN.md 10.1, the GuidedGenerationModel type doc, TESTING.md, and a seventh local Apple live test record the limit as measured: under the ids capital and control, two same-topic yes-or-no questions come back with the first field false; other id pairs answer right; a state naming both facts answers right. The cause is open in wip/phi (P4).
