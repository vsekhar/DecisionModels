---
priority: p2
type: task
created: 2026-09-19T15:26:23-04:00
updated: 2026-09-19T17:40:34-04:00
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

---

_📝 Noted on 2026-09-19 17:28:09-04:00 @ git:72b23be+local_

Design decision: keep today's mapping when the retries run out. A timed-out attempt is already retried like any transport failure; the CI stall failed only because the first attempt got the whole budget. So the change is the cap on each attempt's timeoutInterval (min of attemptTimeout, time left before the deadline), not a new error path. When the retries run out on a timed-out attempt, the call still ends in DecisionError.timeout, as the existing test 'A timeout is a timeout, not a transport failure' pins. Turning that into .transport(URLError.timedOut) would tell a RetryPolicy.none caller less, not more.

---

_📝 Noted on 2026-09-19 17:30:12-04:00 @ git:72b23be+local_

Implemented: RetryPolicy.attemptTimeout (default 10 s, nil for none); Jev.send takes each attempt's timeoutInterval from attemptBudget(before:) = min(attemptTimeout, time left before the deadline), or leaves the transport default when both are nil. Six new tests in RetryTests. Mutant check: reverting send to today's logic fails 4 of the new tests; treating nil as 10 s fails the other 2. All 28 retry tests pass with the fix.

---

_📝 Noted on 2026-09-19 17:40:34-04:00 @ git:72b23be+local_

Verifier: all five acceptance criteria hold, no blockers; its own 208-configuration sweep found the call never outlives the deadline and never outruns maxRetries. Applied its optional notes: doc on the field says nil, not zero, turns the cap off and names the no-deadline case; the struct header and .none doc name the retries-run-out mapping and the caller's shorter timeout; passive voice and 'fails fast' reworded; 'The timeout bounds the whole call' test no longer asserts one send, so it does not depend on the default cap being above 5 s. Not applied: a guard on a non-positive attemptTimeout (doc line instead), and the observation that the default policy's retry budget is 43.5 s so a 60 s call may end in .timeout before its deadline (follows from the existing rule that maxRetries and the deadline both bound the loop).
