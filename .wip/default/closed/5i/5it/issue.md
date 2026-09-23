---
priority: p3
type: bug
created: 2026-09-22T20:11:29-04:00
updated: 2026-09-22T20:15:23-04:00
---

# Live sum-to-one checks allow the services' two-decimal rounding

## Objective
The four live assertions that a returned distribution sums to 1 allow the rounding the services apply, so a sum of 0.99 does not fail a push.

## Context
Found on the 0.2.3 release commit's CI run on 2026-09-22: "Jev triages a support ticket" failed on `isClose(levels.values.reduce(0, +), 1)` with a sum of 0.99. The services report each probability rounded to two decimals, so a sum over n options can be off by up to n times 0.005, and floating point can push a printed 0.99 just past the helper's default tolerance of 0.01. The code under test is right; the assertion is too tight for live data. The same check appears twice in each hosted live suite.

## Location
- `Tests/DecisionModelsTypeSafeTests/JevLiveTests.swift` lines 69 and 82.
- `Tests/DecisionModelsOpenRouterTests/OpenRouterLiveTests.swift` lines 61 and 73.

## Approach
Pass `within: 0.02` to the four sum checks, with a one-line comment at the first in each file: the service rounds each probability to two decimals. Offline tests and the wire fixtures keep the default tolerance.

## Acceptance Criteria
- [ ] Both hosted live suites pass locally and on CI.

---

_📝 Noted on 2026-09-22 20:15:23-04:00 @ git:9eeaa69+local_

Closed 2026-09-22. Commit 9eeaa69 on branch live-sum-tolerance, merged to main after the 0.2.3 tag. CI run 35800990648 green on all three jobs; both hosted live suites also passed locally. The 0.2.3 release commit's own run went green on a rerun of the Linux job, which confirms the flake.
