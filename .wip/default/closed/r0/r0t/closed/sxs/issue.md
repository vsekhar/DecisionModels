---
priority: p2
type: task
created: 2026-09-20T00:17:15-04:00
updated: 2026-09-20T03:32:22-04:00
blocked-on:
  - 9du
  - r4g
---

# OpenRouterAlpha provider with wire, error, and live tests

## Objective
Add `OpenRouterAlpha`, a `DecisionModel` for `POST https://openrouter.ai/api/alpha/decisions`, in a new `DecisionModelsOpenRouter` product, with wire tests, error-mapping tests, one live test, docs, and CI.

## Context
Child of the OpenRouter provider feature; read the parent first for the six design decisions. Blocked on the child that moves `HTTPTransport`, `RetryPolicy`, and the `HTTPClient` retry loop into the core module; this provider is written against those.

`Jev` (`Sources/DecisionModelsTypeSafe/`) is the model for the module's shape: `Jev.swift` (the type, availability, `decide`), `JevWire.swift` (Encodable request and Decodable answer types), `JevMapping.swift` (questionnaire to wire and wire to `Answers`), `JevError.swift` (status to `DecisionError`). Copy the structure, not the files: the OpenRouter shapes differ in the places listed below, and the alpha endpoint may drift on its own.

### The endpoint, as documented on 2026-09-20
Request: `POST /api/alpha/decisions`, `Authorization: Bearer <key>`, JSON body with three required fields. `model` is a string such as `"typesafe/jev-1.13"`. `state` is a string, object, or array. `questions` is a map from id to a question object with `type` (`"noul"`, `"choice"`, or `"score"`), `instructions` (string, object, or array), and `criteria`: for `noul` an object with `"true"` and `"false"` keys; for `choice` a map from option id to a string, object, or array; for `score` an array of one or more level descriptions. These are the same shapes `JevMapping.question(_:)` renders today, including the structured criterion objects (`what` or `summary`, `not_for`, `examples`, `signals`), because the endpoint forwards them to TypeSafe. Optional fields `provider`, `session_id`, `user`, and `trace` exist and are out of scope.

Response (200): `id` (string, the request id), `model` (the pinned model that answered, such as `"typesafe/jev-1.13-20260917"`), `provider` (such as `"TypeSafe"`), `answers` (map from id to an answer with a `type` field: `noul` carries `noul`; `choice` carries `choice`, optional `confidence`, optional `probabilities` map; `score` carries `score`, optional `confidence`, optional `legend` map keyed by index string, optional `probabilities` map keyed by index string), and `usage` with `input_tokens`, `output_tokens`, and optional `cost`.

The documented example, for the wire tests:

```json
{
  "model": "typesafe/jev-1.13",
  "questions": {
    "is_bug": { "type": "noul", "instructions": "Is the customer reporting a software defect?",
      "criteria": { "true": "The customer describes broken or unexpected product behavior.",
                    "false": "The customer is asking a question or requesting a feature." } },
    "team": { "type": "choice", "instructions": "Which team should own this ticket?",
      "criteria": { "account": "Login, permissions, or profile issues.",
                    "frontend": "Rendering, layout, or browser compatibility issues.",
                    "payments": "Checkout, billing, or payment processing issues." } },
    "urgency": { "type": "score", "instructions": "How urgent is this ticket?",
      "criteria": [ "Can wait for the next release", "Should be fixed this week", "Blocking revenue right now" ] }
  },
  "state": "My checkout page shows a blank screen after I click Pay. I have tried two browsers."
}
```

```json
{
  "id": "gen-dec-1789738314-X5e5eKGQdvR9rblyX250",
  "model": "typesafe/jev-1.13-20260917",
  "provider": "TypeSafe",
  "answers": {
    "is_bug": { "type": "noul", "noul": 0.96 },
    "team": { "type": "choice", "choice": "payments", "confidence": 0.75,
              "probabilities": { "account": 0, "frontend": 0.16, "payments": 0.84 } },
    "urgency": { "type": "score", "score": 1.99, "confidence": 0.99,
                 "legend": { "0": "Can wait for the next release", "1": "Should be fixed this week", "2": "Blocking revenue right now" },
                 "probabilities": { "0": 0, "1": 0.01, "2": 0.99 } }
  },
  "usage": { "input_tokens": 476, "output_tokens": 70, "cost": 0.000019992 }
}
```

Errors carry `error.code` and `error.message`, with optional `error.metadata`. Documented statuses: 400 invalid request, 401 missing auth, 402 insufficient credits, 403 management key required, 404 not found, 413 payload too large, 429 rate limit, 500 internal error, 502 provider returned error, 503 temporarily unavailable, 524 request timed out, 529 provider returned error.

## Location
- `Package.swift`: target and product `DecisionModelsOpenRouter` (depends on `DecisionModels`), test target `DecisionModelsOpenRouterTests`, and a plain target `DecisionModelsTestSupport` (not a product; depends on `DecisionModels`) that holds `ScriptedTransport`, `FakeClock`, and `isClose`, moved out of `Tests/DecisionModelsTypeSafeTests/Fixtures.swift` so both HTTP test targets share them. The Jev-specific fixtures (`Team`, `Severity`, `ticket`, `triage()`, `harness`) stay where they are.
- `Sources/DecisionModelsOpenRouter/OpenRouterAlpha.swift`, `OpenRouterWire.swift`, `OpenRouterMapping.swift`, `OpenRouterError.swift`.
- `Tests/DecisionModelsOpenRouterTests/`: `WireTests.swift`, `ErrorTests.swift`, `AvailabilityTests.swift`, `OpenRouterLiveTests.swift`, `Fixtures.swift`.
- `README.md`, `TESTING.md`, `DESIGN.md` 10.1, 14, 15, `.github/workflows/ci.yml`.

## Approach
- The type:
  ```swift
  public struct OpenRouterAlpha: DecisionModel {
      public static let apiKeyVariable = "OPENROUTER_API_KEY"
      public let model: String
      public let retry: RetryPolicy
      public init(model: String, apiKey: String? = nil, retry: RetryPolicy = .default,
                  transport: any HTTPTransport = URLSessionTransport())
  }
  ```
  plus the internal initializer the tests use, with `environment`, `baseURL`, `sleep`, and `now`, as `Jev` has. `identity` is `DecisionModelIdentity(provider: "openrouter", name: model)`. `availability` is `.unavailable(.notConfigured("OPENROUTER_API_KEY"))` without a key. `capabilities` are Jev's (`.calibrated`, 255 options, 10 levels, 64k context, no repeated samples), with a doc comment that says this is an alpha assumption tied to `typesafe/jev-1.13`. The type's doc comment says the endpoint is alpha, that OpenRouter may change or remove it, and that a plain `OpenRouter` type will replace this one when it leaves alpha.
- `decide`: reject `samples > 1` as `.unsupported(.repeatedSamples)`; build the request; send through `HTTPClient` with `transient: { [429, 502, 503, 524, 529].contains($0) }`; on 2xx map the body; on anything else map the status.
- Wire types: `OpenRouterRequest` with `model`, `state`, `questions` (question shape as Jev's); `OpenRouterResponse` with `id`, `model`, `provider`, `answers`, `usage`; answers decoded by `type` as `JevAnswer` does; `usage.cost` decoded and dropped, or left undecoded. `requestID` comes from the body's `id`.
- Mapping: the same rendering as `JevMapping` for questions and criteria, and the same records back. Answers are `.calibrated`.
- Status mapping, after the retries the client allows:
  | Status | `DecisionError` |
  |---|---|
  | 400 | `.invalidQuestion(id: "", reason: message)` |
  | 401, 403 | `.unauthorized` |
  | 402 | `.unavailable(.other(message))` |
  | 413 | `.contextSizeExceeded(limit: nil, estimated: nil)` |
  | 429 | `.rateLimited(retryAfter:)` from the header |
  | 503 | `.overloaded` |
  | 524 | `.timeout` |
  | 404, 500, 502, 529, anything else | `.transport(OpenRouterServerError)` with status, message, and `error.code` |
  `message` reads `error.message`, then the fallbacks `JevError.message(in:)` uses.
- Tests, no network: the request body for the fixture questionnaire equals the documented request for the same questions (encode, decode both as JSON objects, compare); the documented response decodes to the expected records, including `legend` and the `is_bug` verdict; one test per status row above; availability with and without the key and with a blank key; a 503 then a 200 sends twice, to show the client is wired in; `samples: 3` is refused before anything is sent.
- Live test, suite `OpenRouterLive`, one request: triage the fixture ticket with `OpenRouterAlpha(model: "typesafe/jev-1.13", apiKey: key)` and `timeout: .seconds(60)`; check the team is `returns`, probabilities sum to one, `requestID` is set, `usage.inputTokens > 0`. Without `OPENROUTER_API_KEY` the test records a failure that names the variable and the command, as `JevLiveTests.liveKey()` does. It never skips.
- Docs: README gains an OpenRouter paragraph and example beside Jev's, and the products table gains the module. TESTING.md gains a "Live tests against OpenRouter" section, adds the suite to the CI table and the reproduce command, and lists the second secret. DESIGN.md 10.1 gains an `OpenRouterAlpha` paragraph, 14 gains an OpenRouter column (same rows as Jev), 15 lists the new targets.
- CI: `.github/workflows/ci.yml` passes `OPENROUTER_API_KEY: ${{ secrets.OPENROUTER_API_KEY }}` to the test step and adds `--skip OpenRouterLive` to the fork skip list. The user sets the secret with `gh secret set OPENROUTER_API_KEY`; the implementer notes in the closing note whether it was set at the time.
- Style: short sentences, active voice; the user's writing rules apply to every doc comment and doc paragraph.

## Related Issues
Parent: the OpenRouter provider feature. Blocked on the transport move child. wip/c4r removes default models; this provider has none from the start. wip/jev is the pattern. wip/jso set up CI with the Jev live suite.

## Acceptance Criteria
- [ ] `import DecisionModelsOpenRouter` gives `OpenRouterAlpha`; it cannot be built without a model, and the word "alpha" is in the type name at every call site.
- [ ] With no key in the argument or the environment, `availability` is `.unavailable(.notConfigured("OPENROUTER_API_KEY"))` and nothing is sent.
- [ ] The documented example request and response round-trip through the wire types and mapping, and every documented status maps as the table says, each with a test.
- [ ] `ScriptedTransport` and `FakeClock` live in `DecisionModelsTestSupport`, and both HTTP test targets use them; the Jev retry tests still pass unchanged.
- [ ] `OpenRouterLive` passes once with the key sourced (`set -a; . ./.env; set +a; swift test --filter OpenRouterLive`) and fails, not skips, without it.
- [ ] README, TESTING.md, DESIGN.md 10.1, 14, and 15 describe the provider, and ci.yml passes the secret and skips the suite on forks.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean, `swift test --skip JevLive --skip OpenRouterLive --skip GuidedGenerationLiveTests` passes, and the iOS build (`xcodebuild build -scheme DecisionModels-Package -destination 'generic/platform=iOS Simulator' -skipMacroValidation`) passes with the new product.

---

_📝 Noted on 2026-09-20 00:17:15-04:00 @ git:2d3633c+local_

Parent is wip/r0t; blocked on wip/9du (the transport move).

---

_📝 Noted on 2026-09-20 02:41:32-04:00 @ git:1d94ae3+local_

2026-09-20: broke out wip/r4g (DecisionModelsTestSupport target: Reply, ScriptedTransport, FakeClock, isClose, plus the move of HTTPClientTests to the core test target). sxs is blocked on it and keeps the provider, its tests, the docs, and CI as its own scope. OPENROUTER_API_KEY is present in .env and the OPENROUTER_API_KEY repository secret exists (gh secret list, set 2026-09-20).

---

_📝 Noted on 2026-09-20 02:51:56-04:00 @ git:1d94ae3+local_

Design record for the provider (2026-09-20). Written against HTTPClient (wip/9du) and DecisionModelsTestSupport (wip/r4g). Files as the issue lists them; decisions the issue left open, and small deviations:

1. Fixture. The OpenRouter test target's fixture is OpenRouter's documented example itself: the checkout-page ticket and the three questions is_bug (noul, both sides), team (choice: account, frontend, payments), urgency (score, three levels), built from QuestionSpec with plain string criteria so the request encodes to the documented JSON. The live test triages that ticket, not a copy of the Jev target's Team/Severity ticket, and checks team == "payments", is_bug > 0.5, both distributions sum to one, requestID set, inputTokens > 0. One fixture set per target, and the live answer is checked against what the docs show.

2. probabilities is required in OpenRouterAnswer.Choice and .Score although the docs mark it optional. A calibrated answer needs a distribution; a reply without one fails to decode and surfaces as .malformedResponse (a test covers it). Legend decodes and is dropped, as in Jev.

3. OpenRouterResponse decodes id, model, provider, answers, usage. requestID is the body's id. model and provider are decoded and unread, as JevResponse.model is. usage.cost is not declared, so the decoder drops it.

4. OpenRouterServerError(status:message:code:), public, CustomStringConvertible: "OpenRouter answered 502 (502): Provider returned error". code reads error.code as an Int or a String. message precedence: error.message, error.detail, message, detail, error as a string, then the body's first 500 characters. 400 with no message falls back to "OpenRouter refused the request."; 402 to "OpenRouter reports insufficient credits."

5. OpenRouterError.isTransient = [429, 502, 503, 524, 529]. Status mapping as the issue's table. decide order: key check, samples check, build, send through HTTPClient, map a non-2xx, else OpenRouterMapping.modelResponse(_:).

6. Tests: wire (request equals the documented JSON as NSDictionary; endpoint URL and headers; criteria rendering; documented response to records; the wire type keeps id/model/provider/legend; usage and requestID; missing id and usage; unknown type, missing probabilities, non-integer level key, non-JSON all malformed; 503 then 200 sends twice; samples 3 refused unsent), errors (one test per status row, parameterized for 401/403, 502/529, 404/500; message fallbacks; server error description), availability (no key, blank key, environment key, direct call and session refuse unsent, identity and capabilities, session answers), live (suite OpenRouterLive, one request).

7. CI: SKIP_JEV renamed SKIP_LIVE in both jobs; forks skip JevLive and OpenRouterLive; both jobs receive OPENROUTER_API_KEY. TESTING.md: new "Live tests against OpenRouter" section, "with every backend" heading, the Linux docker commands carry the second suite and key, three repository secrets listed. README: products table row, an OpenRouter paragraph after Jev's, hosted providers need iOS 18, the Tests line names three live suites. DESIGN.md: 10.1 OpenRouterAlpha paragraph after Jev's transport paragraph, 14 gains an OpenRouter column ("as Jev"), 15 lists the target and test target and the 15.1 row names the module.

---

_📝 Noted on 2026-09-20 03:02:25-04:00 @ git:1a92c6a+local_

Implementation state (2026-09-20), before verification. Sources/DecisionModelsOpenRouter/{OpenRouterAlpha,OpenRouterWire,OpenRouterMapping,OpenRouterError}.swift; Tests/DecisionModelsOpenRouterTests/{Fixtures,WireTests,ErrorTests,AvailabilityTests,OpenRouterLiveTests}.swift; Package.swift (product, target, test target on DecisionModelsTestSupport); README, TESTING.md, DESIGN.md 10.1/14/15/15.1, ci.yml as the design record says.

Results: swift build --build-tests -Xswiftc -warnings-as-errors clean. swift test --skip JevLive --skip OpenRouterLive --skip GuidedGenerationLiveTests: 434 tests in 46 suites (401 before + 33 OpenRouter tests in 3 suites). OpenRouterLive with the key sourced: 1 test passes, 0.3 s, team == payments. OpenRouterLive without the key: fails with the message naming OPENROUTER_API_KEY and the command; it does not skip. xcodebuild for the iOS Simulator: BUILD SUCCEEDED with the new product. The OPENROUTER_API_KEY repository secret was already set when this work started (gh secret list, 2026-09-20T04:28Z).

---

_📝 Noted on 2026-09-20 03:32:22-04:00 @ git:1a92c6a+local_

Verifier (2026-09-20): six of seven criteria held; the one should-fix was DESIGN.md 14, where five table rows lacked the new OpenRouter cell and rendered Apple's cells under OpenRouter. Fixed: every row now carries "as Jev", and the Unavailable row says "no key, offline, 401 and 403; 402 for credits". Notes applied: an empty body id maps to nil requestID (test "An empty id counts as no id"); AvailabilityTests carries the FoundationNetworking guard for its URLRequest member call; 400, 402, and 413 now run under .default and pin one send, so adding one to isTransient fails a test; "stay unexposed" reworded. Added ParityTests.swift (the test target now also depends on DecisionModelsTypeSafe): a structured questionnaire and an object state go through Jev and OpenRouterAlpha against scripted transports, and the questions and state sub-objects of the two bodies must be equal as NSDictionary. It guards the one invariant the duplicated mappings rely on. Mutants killed one at a time, each by its own test only: empty id passed through; 413 in isTransient; choice criteria keyed "summary" instead of "what".

Final: build clean under -warnings-as-errors; offline suite 436 tests in 47 suites (401 before this issue + 35 OpenRouter tests in 4 suites); OpenRouterLive passes with the key (0.3 s) and fails without it; iOS Simulator build succeeded; the OPENROUTER_API_KEY repository secret exists. Left for the record, out of this issue's doc scope: DESIGN.md 17 item 5 still reads "The hosted provider type is named `Jev`", which now understates the second provider.
