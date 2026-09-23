---
priority: p4
type: task
created: 2026-09-22T19:44:45-04:00
updated: 2026-09-22T19:54:09-04:00
---

# Find which field-name pairs make the on-device model answer a yes-or-no pair wrong

## Objective
Find what about the field names `capital` and `control` makes the on-device model answer the first of two same-topic yes-or-no questions false, and whether the adapter can avoid it without the caller changing ids.

## Context
wip/bte measured on 2026-09-22, nine deterministic runs per row, one greedy sample, no state: under the ids `capital` and `control`, two questions on one topic ("Is Paris the capital of France?" and "Is Berlin the capital of Germany?", or Sun/Moon, or Rome/Madrid) come back with the first field false whatever it asks. Every other id pair tried answers both right: `q1`/`q2`, `a`/`b`, `field1`/`field2`, `capitalA`/`capitalB`, `capital1`/`capital2`, `control`/`capital` (the same two ids swapped), `paris_france`/`berlin_germany`, `paris_france`/`control`. `capital`/`berlin_germany` still gives `capital` false. An unrelated control question ("Is the Moon made of cheese?") under `capital`/`control` answers right. A state naming both facts answers right. A description on each boolean property made one pair right and another wrong (wip/bte's note). So the cause sits in the field names as the model reads them, and a slug of the question text is not the fix: `q1`/`q2` already works.

## Location
- `Sources/DecisionModelsApple/SchemaBuilder.swift`: the id-to-property-name mapping and its inverse.
- `Tests/DecisionModelsAppleTests/GuidedGenerationLiveTests.swift`: the test from wip/bte that pins `capital`/`control`.

## Approach
1. Measure through the public API, no package change, one greedy sample, five runs each, always with the `q1`/`q2` control beside every row: `capital` alone with a neutral second id; `control` alone with a neutral first id; other common words in the first slot (`answer`, `result`, `value`, `flag`, `status`); the same ids with the questions on different topics. Record the table in a note.
2. If one word, one slot, or one pattern explains it, decide whether the adapter should rename such fields (for example a fixed prefix on every property name, kept out of the prompt headings) and measure that change against every Apple live test's numbers, which the token estimate will move.
3. Otherwise close with the table and leave the documented limit as it is.

## Related Issues
wip/bte found and documented the effect and pins one pair in a live test.

## Acceptance Criteria
- [ ] A note records the table from step 1 with the `q1`/`q2` control on every row.
- [ ] Either the adapter change lands with every Apple test green and DESIGN.md 10.1 updated, or the issue closes on the numbers.
