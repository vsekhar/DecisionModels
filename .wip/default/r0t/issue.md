---
priority: p2
type: feature
created: 2026-09-20T00:17:15-04:00
updated: 2026-09-20T00:17:15-04:00
---

# OpenRouter alpha provider for the Decisions endpoint

## Summary
Add a provider for OpenRouter's Decisions endpoint, `POST https://openrouter.ai/api/alpha/decisions`. The endpoint is in alpha, so the provider type is named `OpenRouterAlpha`: a developer cannot build one without writing "alpha". It reads `OPENROUTER_API_KEY` from the environment when no key is passed, and takes its model as a required argument with no default, in line with wip/c4r.

The endpoint's request and response shapes match TypeSafe's `POST /v1/systemone` almost field for field (the endpoint proxies to TypeSafe today; the one model it serves is `typesafe/jev-1.13`). The difference is the host, the path, the `vendor/model` naming, a request id and a provider name in the response body, a `cost` in usage, and a wider set of error statuses. So the work is two steps: move the HTTP transport and retry machinery out of the Jev module into the core module, then write the provider against it.

Endpoint reference: https://openrouter.ai/docs/api/api-reference/alphadecisions/submit-a-decisions-questions-and-answers-request.md (fetched 2026-09-20; the wire facts are copied into the child issues so no implementer needs the network to read them).

## User Story
A developer who already has an OpenRouter account and key can point a `DecisionSession` at OpenRouter with one line, and get the same typed answers and calibrated probabilities as from `Jev` directly:

```swift
let session = DecisionSession(model: OpenRouterAlpha(model: "typesafe/jev-1.13"))
```

When OpenRouter moves the endpoint out of alpha, a plain `OpenRouter` type ships and `OpenRouterAlpha` is deprecated, so every developer re-acknowledges the change by changing the type name.

## Design Decisions
Confirmed with the user on 2026-09-20:

1. **Naming.** The type is `OpenRouterAlpha`. No factory, no label trick. Identity is provider `openrouter`, name the model string the developer passed.
2. **Module layout.** A new product `DecisionModelsOpenRouter`. `HTTPTransport`, `URLSessionTransport`, and `RetryPolicy` move to the core `DecisionModels` module as public types, and the retry loop now private to `Jev.send` becomes a `package`-visible client in core that both providers use. The OpenRouter module keeps its own wire types and mapping.
3. **Request extras.** The provider sends `model`, `state`, and `questions` only. OpenRouter's optional `user`, `session_id`, `trace`, and `provider` routing fields are not exposed.
4. **Cost.** OpenRouter reports `usage.cost` in dollars. The provider drops it; `Usage` keeps its three fields.
5. **No model list.** OpenRouter documents no endpoint that lists decision models, so the provider has no `models()`. The developer names the model from OpenRouter's docs.
6. **Capabilities.** The provider declares Jev's capabilities and `.calibrated` quality, because `typesafe/jev-1.13` is the only decision model OpenRouter serves. The doc comment says this is an alpha assumption tied to that model.

## Out of Scope
- `user`, `session_id`, `trace`, and `provider` routing preferences on the request.
- Carrying `cost` into `Usage`.
- A model list.
- Any change to what `Jev` does or to its public API beyond where `RetryPolicy` and `HTTPTransport` are declared.

## Testing Strategy
- Wire tests against the documented example request and response, with no network.
- Error-mapping tests for every documented status, with the scripted transport.
- One live test that triages the fixture ticket with `typesafe/jev-1.13`. It reads `OPENROUTER_API_KEY` and fails, not skips, without it, like the Jev live suite. CI runs it on every push once the `OPENROUTER_API_KEY` repository secret is set.
- The existing Jev retry tests stay green through the refactor, unchanged; they are the regression net for the shared client.

---

_📝 Noted on 2026-09-20 00:17:15-04:00 @ git:2d3633c+local_

Children: wip/9du moves HTTPTransport, RetryPolicy, and the retry loop (HTTPClient) into the core module; wip/sxs writes the provider against them and is blocked on wip/9du.
