---
priority: p2
type: task
created: 2026-09-20T00:17:15-04:00
updated: 2026-09-20T02:37:54-04:00
may-unblock:
  - sxs
---

# Move HTTP transport and retry into the core module

## Objective
Move the HTTP transport and retry machinery from the Jev module into the core `DecisionModels` module, so a second HTTP provider can use it without importing `DecisionModelsTypeSafe`. `Jev` keeps its public API and its behavior.

## Context
Child of the OpenRouter provider feature (read the parent first for the design decisions). Today `HTTPTransport`, `URLSessionTransport`, and `RetryPolicy` live in `Sources/DecisionModelsTypeSafe/`, and the retry loop is `Jev.send` (`Sources/DecisionModelsTypeSafe/Jev.swift`, "MARK: Sending"): it computes a deadline from the request timeout, caps each attempt with `attemptBudget(before:)` (wip/ajp), retries transient statuses and transport failures under `RetryPolicy`, honors `Retry-After` up to `maximumBackoff`, maps `URLError.timedOut` to `.timeout` and cancellation to `CancellationError`, and never runs past the deadline. The OpenRouter provider needs exactly this loop with a different set of transient statuses.

The retry tests (`Tests/DecisionModelsTypeSafeTests/RetryTests.swift`, 28 tests) drive the loop through `Jev` with `ScriptedTransport` and `FakeClock` from `Fixtures.swift`, injected through Jev's internal initializer (`sleep:` and `now:`). They must pass unchanged after this move; they are the regression net.

## Location
- Move `Sources/DecisionModelsTypeSafe/HTTPTransport.swift` and `RetryPolicy.swift` to `Sources/DecisionModels/`. Same public API, same doc comments.
- New `Sources/DecisionModels/HTTPClient.swift`: the shared retry loop, `package` visibility.
- `Sources/DecisionModelsTypeSafe/Jev.swift`: `send`, `pause`, `left`, `attemptBudget`, and the `Duration.timeInterval` extension go; `Jev` builds an `HTTPClient` and maps the final reply.
- `Sources/DecisionModelsTypeSafe/JevError.swift`: `retryAfter(_:)`, `cancellation(_:)`, and the transport half of `decisionError(transport:)` move to the client; `isTransient` stays, as Jev's predicate.
- `DESIGN.md` 10.1 (the transport and waiting paragraph) and 15 (package layout).
- `Tests/DecisionModelsTypeSafeTests/Fixtures.swift`: only if an import changes; it already imports `DecisionModels`.

## Approach
- `package struct HTTPClient: Sendable` in core, with `init(transport:policy:transient:sleep:now:)` where `transient: @Sendable (Int) -> Bool` names the statuses worth sending again, and `sleep` and `now` default to the real clock so only tests pass them. `func send(_ request: URLRequest, timeout: Duration?) async throws -> (Data, HTTPURLResponse)` runs the loop and returns the final reply whatever its status: a 2xx, a transient status once the retries run out, or a status the predicate rejects. The provider maps a non-2xx final reply to a `DecisionError` itself, so status-to-error mapping stays per provider. Transport failures the client maps as `Jev.send` does now: cancellation as `CancellationError`, `.timedOut` as `.timeout` once the retries run out, anything else as `.transport(error)`. The deadline rule, the attempt cap, the `Retry-After` cap, and the cancellation checks move over unchanged.
- `Retry-After` parsing moves to the client as a `package` static (it is plain HTTP, not Jev's). Keep the `Retry-After`-rides-along behavior: Jev's `decisionError(status:body:response:)` still reads the header from the final 429 reply, so no signature change there.
- `Jev` keeps both initializers. The internal one passes `sleep` and `now` through to the client, so `harness(...)` in the tests is untouched.
- Do not add `@_exported import DecisionModels` to the Jev module. Users write both imports, as the README already shows. This moves `RetryPolicy` for a user who imported `DecisionModelsTypeSafe` alone; that is acceptable before v1 and worth one line in the README's Jev section.
- DESIGN.md 10.1: the transport paragraph now says the transport, the policy, and the client live in the core module and every HTTP provider uses them; the rules it states do not change. DESIGN.md 15: `DecisionModels/` gains "HTTP transport and retry"; `DecisionModelsTypeSafe/` stays "Jev".
- Style: short sentences, active voice, in every moved or new doc comment.

## Related Issues
Parent: the OpenRouter provider feature. Blocks the provider child. wip/ajp added `attemptTimeout` and `attemptBudget(before:)`, which move with the loop. wip/jev built the pieces that move.

## Acceptance Criteria
- [ ] `HTTPTransport`, `URLSessionTransport`, and `RetryPolicy` are public types in `DecisionModels`, with no copy left in `DecisionModelsTypeSafe`.
- [ ] `HTTPClient` is `package`-visible in `DecisionModels`, and `Jev.send` is gone: `Jev.decide` and `Jev.models()` go through the client.
- [ ] `Tests/DecisionModelsTypeSafeTests/RetryTests.swift` passes with no edits, including the six attempt-timeout tests from wip/ajp.
- [ ] `grep -rn "Retry-After\|timedOut\|checkCancellation" Sources/DecisionModelsTypeSafe` finds nothing: the loop's mechanics live in core only.
- [ ] DESIGN.md 10.1 and 15 describe the new home; the README's Jev section notes the extra import.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean, `swift test --skip JevLive --skip GuidedGenerationLiveTests` passes, and the Jev live suite passes once with the key sourced.

---

_📝 Noted on 2026-09-20 00:17:15-04:00 @ git:2d3633c+local_

Parent is wip/r0t; wip/sxs (the provider) is blocked on this issue.

---

_📝 Noted on 2026-09-20 02:21:06-04:00 @ git:9051523+local_

Design record (2026-09-20). Baseline before the change: 403 tests in 44 suites pass with both live backends.

Shape of HTTPClient (Sources/DecisionModels/HTTPClient.swift, package visibility):
- `package struct HTTPClient: Sendable` with `init(transport:policy:transient:sleep:now:)`. `transient: @Sendable (Int) -> Bool`; `sleep` and `now` default to the real clock.
- `package func send(_ request: URLRequest, timeout: Duration? = nil) async throws -> (Data, HTTPURLResponse)`. It returns the final reply whatever its status: a 2xx, a transient status once the retries run out, or a status the predicate rejects. The provider maps a non-2xx final reply itself.
- Transport failures: cancellation (CancellationError or URLError.cancelled) rethrows as CancellationError before any retry check; once the retries run out, URLError.timedOut becomes DecisionError.timeout and anything else DecisionError.transport(error). A DecisionError thrown by the transport (URLSessionTransport's malformedResponse) or by the deadline (`left(until:)`) passes through untouched.
- `package static func retryAfter(_ response: HTTPURLResponse) -> Duration?` moves from JevError. The loop uses it for the wait; Jev's decisionError(status:body:response:) still reads it from the final 429 reply.
- The deadline rule, `attemptBudget(before:)`, `pause(_:until:)`, `left(until:)`, and `Duration.timeInterval` move over unchanged as private members / an internal extension in core.

Jev after the change: stores `client: HTTPClient` in place of transport/sleep/now; the internal initializer builds the client with `transient: JevError.isTransient`. A private helper `reply(to:timeout:)` calls the client and throws `JevError.decisionError(status:body:response:)` on a non-2xx reply; `decide` and `models()` call it. `Jev.send`, `pause`, `left`, `attemptBudget` are gone. JevError loses `decisionError(transport:)`, `cancellation(_:)`, `retryAfter(_:)`; keeps `isTransient`, `decisionError(status:body:response:)`, `requestID`, `message(in:)`.

One deviation from the issue text: `RetryPolicy.backoff(retry:)` becomes `package` rather than internal. RetryTests.backoffCeiling calls it through `@testable import DecisionModelsTypeSafe`, which no longer reaches it once the type lives in core; `package` keeps the test unedited and adds nothing to the public API.

New tests (Tests/DecisionModelsTypeSafeTests/HTTPClientTests.swift) drive HTTPClient directly with ScriptedTransport and FakeClock, which already live in that target: the predicate decides what is retried (a 503 retries under a predicate that names it and returns under one that does not), a rejected status comes back as a reply rather than an error, and Retry-After parsing handles blank, negative, non-numeric, and padded values. wip/sxs moves the fixtures into DecisionModelsTestSupport; this file should move to Tests/DecisionModelsTests then.

---

_📝 Noted on 2026-09-20 02:37:53-04:00 @ git:9051523+local_

Summary (2026-09-20). Done as the design record says. HTTPTransport.swift and RetryPolicy.swift moved to Sources/DecisionModels (git renames); Sources/DecisionModels/HTTPClient.swift holds the loop; Jev builds a client in its internal initializer and maps the final reply in a private reply(to:timeout:); JevError keeps isTransient, decisionError(status:body:response:), requestID, message(in:). DESIGN.md 10.1 and 15, README (products table and Jev section) updated.

Verifier: all six criteria hold, no blockers. It built a differential harness (old Jev.send vs HTTPClient.send over 50,000 scripted runs) and found zero mismatches, and confirmed the dropped `as? DecisionError` branch in the old decisionError(transport:) was unreachable. Its notes, all applied: HTTPClient.transport and .policy are now private (the package surface is init, send, retryAfter, plus RetryPolicy.backoff); a test pins the 2xx short-circuit against a predicate that names everything (proved: with the 2xx check removed, only that test fails); the Retry-After parsing test covers an empty header; README products table names HTTP transport and retry; the Jev-section sentence also names URLSessionTransport; DESIGN 10.1 says RetryPolicy also bounds one try, and the Retry-After clause is active voice.

Results: swift build --build-tests -Xswiftc -warnings-as-errors clean; swift test --skip JevLive --skip GuidedGenerationLiveTests: 401 tests in 43 suites pass (baseline 403 in 44 with both live suites = 396 non-live; 5 new client tests); RetryTests unedited, 28 pass; JevLive: 2 pass with the key sourced; acceptance grep on Sources/DecisionModelsTypeSafe finds nothing.

For wip/sxs: HTTPClientTests.swift sits in Tests/DecisionModelsTypeSafeTests because ScriptedTransport and FakeClock live there today. When those move to DecisionModelsTestSupport, move this file to Tests/DecisionModelsTests and add the support target to that test target's dependencies. The client's package surface the provider needs: HTTPClient(transport:policy:transient:sleep:now:), send(_:timeout:) returning the final reply, and HTTPClient.retryAfter(_:) for the 429 mapping.
