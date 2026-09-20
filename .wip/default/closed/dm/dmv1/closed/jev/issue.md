---
priority: p1
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T02:56:27-04:00
blocked-on:
  - session
may-unblock:
  - linux
  - docs
---

# Jev provider with wire tests and live tests

## Objective
Implement `Jev`, the TypeSafe hosted provider, in `DecisionModelsTypeSafe`, with unit tests against recorded wire samples and live tests against the real service.

## Context
Child of wip/dmv1. `DESIGN.md` sections 10.1 (Jev), 11 (error mapping), 14 (mapping table). TypeSafe API facts: `POST https://api.typesafe.ai/v1/systemone`, header `Authorization: Bearer <key>`, body `{state, model, questions: {id: {type, instructions, criteria}}}`. Choice criteria: object option id → description (string or object). Score criteria: ordered array (string or object per level). Noul criteria: optional `{true, false}`. Response: `{model, answers: {id: {type, choice|score|noul, probabilities, confidence, legend}}, usage: {input_tokens, output_tokens}}`. Score probabilities are keyed by level index as strings. Errors: 401, 422, 429, 529; retry 429 and 529 with exponential backoff. Aliases `jev-latest`, `jev-preview`. Limits: 255 options, 10 levels, 64k tokens total. `GET /v1/models` lists models. Request id header `x-typesafe-request-id`.

## Location
- `Sources/DecisionModelsTypeSafe/`: `Jev.swift` (model, `latest`, `preview`, `init(version:apiKey:retry:session:)`), `JevWire.swift` (request and response `Codable` types), `JevMapping.swift` (`Questionnaire` → wire, wire → `Answers`, `Criterion` → string or object), `RetryPolicy.swift`, `JevError.swift` (HTTP → `DecisionError`).
- `Tests/DecisionModelsTypeSafeTests/`: `WireTests.swift` (encoding and decoding against fixtures), `JevLiveTests.swift`.

## Approach
- `URLSession`-based transport, injectable for tests through a small `protocol HTTPTransport`. No third-party dependencies.
- `apiKey` resolution: explicit argument, else `ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"]`. `availability` is `.unavailable(.notConfigured("TYPESAFE_API_KEY"))` when no key.
- Criteria rendering: when a `Criterion` has only `summary`, send the string; otherwise send an object with `what`/`summary`, `not_for`, `examples`, `signals` (omit empty). Instructions: send the `State` as JSON (string stays a string).
- Answer mapping: `choice` → `.choice(reported:probabilities:confidence:)`; `score` → `.rating(score:probabilities:confidence:)` with integer keys; `noul` → `.verdict(probability:)`. `Answers.quality = .calibrated`. Keep `usage` and the request id header.
- Capabilities: `.calibrated`, structured criteria and instructions true, 255, 10, `contextTokens: 64_000`, no repeated samples (the session's `samples > 1` should throw `.unsupported(.repeatedSamples)` for Jev).
- Live tests read the key from the environment only and **fail** with a clear message when it is absent. They use one small state and one `Questionnaire` with a choice, a score, and a verdict, then assert: probabilities sum to 1 (±0.01), confidence in 0...1, legend has the right count, usage non-zero, and a sensible top choice for an unambiguous ticket ("wrong size shoes arrived" → returns). Keep the test to two requests.

## Related Issues
wip/session (blocker), wip/docs (documents how to run live tests).

## Acceptance Criteria
- [ ] Wire encoding matches the documented request shape for each question kind, including structured criteria and structured instructions (fixture comparison).
- [ ] Wire decoding of the documented choice, score, and noul response samples yields correct `AnswerRecord` values.
- [ ] 401 → `.unauthorized`, 422 → `.invalidQuestion`, 429 → retried then `.rateLimited`, 529 → retried then `.overloaded`; retry count and backoff are tested with a fake transport.
- [ ] Missing key → `availability == .unavailable(.notConfigured)` and `decide` throws `.unavailable`.
- [ ] Live tests pass with `set -a; . ./.env; set +a; swift test --filter Jev` and fail without the key.

---

_📝 Noted on 2026-09-19 02:56:27-04:00 @ git:4315d9b+local_

Done in a worktree, merged by copy. Jev provider with HTTPTransport seam, RetryPolicy, wire types and mapping, error mapping, models(). Verifier: all 5 criteria hold; live run passed. Its should-fixes fixed: Retry-After capped by maximumBackoff; DecisionRequest.timeout is a whole-call deadline (injected clock for tests, mutation-proven); cancellation surfaces as CancellationError; FoundationNetworking guard in WireTests. Live tests pass from main after the merge (2 requests). DESIGN.md 10.1 updated.
