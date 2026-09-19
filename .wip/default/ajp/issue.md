---
priority: p2
type: task
created: 2026-09-19T15:26:23-04:00
updated: 2026-09-19T15:26:23-04:00
---

# Add a per-attempt timeout to the Jev retry policy

## Objective
Give the Jev client a per-attempt timeout, so that one hung HTTP attempt fails fast and the retry loop can try again inside the caller's overall deadline.

## Context
CI run 35463804425 (attempt 1, 2026-09-19) failed in the Jev live step: "Jev triages a support ticket" threw `DecisionError.timeout` after 60.99 s. The same request took 0.48 s from the development Mac a minute later and 0.40 s when the job was rerun, so the cause was a short stall between the GitHub runner and the service, not the code.

The stall failed the whole call because of how `Jev.send` spends its deadline (`Sources/DecisionModelsTypeSafe/Jev.swift`, around line 168): each attempt's `URLRequest.timeoutInterval` is `min(timeout, remaining)`. The first attempt therefore gets the whole budget. When it hangs, the deadline passes before any retry can start, and the retry policy never gets a chance. The live test asks with `timeout: .seconds(60)` (`Tests/DecisionModelsTypeSafeTests/JevLiveTests.swift:52`). Jev normally answers in under a second.

This matters more now that the live suite runs on every push (wip/jso): one stall turns the badge red. It also matters to library users, whose calls hang for the whole deadline instead of recovering.

## Location
- `Sources/DecisionModelsTypeSafe/RetryPolicy.swift`: new field.
- `Sources/DecisionModelsTypeSafe/Jev.swift`: `send`, where each attempt's timeout is set.
- `Tests/DecisionModelsTypeSafeTests/RetryTests.swift`: new tests with the scripted transport and the fake clock.
- `DESIGN.md` 10.1: the transport and waiting paragraph.

## Approach
- Add `attemptTimeout: Duration?` to `RetryPolicy`, default `.seconds(10)`; `nil` means no per-attempt cap. `RetryPolicy.none` keeps the default cap.
- Each attempt's `timeoutInterval` becomes the smallest of `attemptTimeout`, the request's `timeout`, and the time left before the deadline. With no request timeout and no deadline, the attempt cap still applies.
- An attempt that times out on its own cap is a transport failure and is retried like any other, within `maxRetries` and the deadline. Only running out of the overall deadline yields `DecisionError.timeout`.
- Keep the existing rules: the deadline bounds attempts and waits together, `Retry-After` is capped by `maximumBackoff`, and cancellation is never retried.
- Document the field on `RetryPolicy` and in DESIGN.md 10.1.

## Related Issues
wip/jso (CI with the live suite on every push), wip/yam (the run where the stall appeared).

## Acceptance Criteria
- [ ] With the fake clock and a transport that hangs on the first attempt and answers on the second, a call with `timeout: .seconds(60)` succeeds, the first attempt's `timeoutInterval` is 10 s, and the simulated time spent is about 10 s plus one backoff.
- [ ] A transport that hangs on every attempt ends in `DecisionError.timeout` no later than the overall deadline, after more than one attempt.
- [ ] With `attemptTimeout: nil`, behavior matches today's.
- [ ] Each new test fails when the fix is reverted in a scratch copy.
- [ ] `swift test --skip JevLive --skip GuidedGenerationLiveTests` passes, and the Jev live suite passes once with the key sourced.
