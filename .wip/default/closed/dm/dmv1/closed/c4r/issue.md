---
priority: p2
type: task
created: 2026-09-19T18:35:49-04:00
updated: 2026-09-20T01:27:50-04:00
---

# Remove default models and versions from the public API

## Objective
Remove every default model and default model version from the framework's public API. A developer names the model when they build a provider. The framework never picks one for them.

## Context
The user's rule (2026-09-19): model decisions are consumed in developer code, so the developer must name the model when they instantiate the framework. In doing so they accept one of two contracts. A floating alias such as `jev-latest` means the model behind the name may change at any time. A pinned version such as `jev-1.13.0` means the service may retire it. A default hides that choice, so the framework must not ship one.

Tests must name their model too. `jev-latest` is fine in tests: when the model behind the alias changes in a way that affects behavior, the live suite is the early warning.

Today the API supplies a model or a version by default in three places:

- `Jev.latest` and `Jev.preview`, static instances (`Sources/DecisionModelsTypeSafe/Jev.swift:24`, `:27`).
- `Jev.init`, whose `version` parameter defaults to `"jev-latest"` in both the public initializer (`Jev.swift:46`) and the internal one the tests use (`Jev.swift:64`).
- `GuidedGenerationModel.init(_ model: SystemLanguageModel = .default, instructions:)` (`Sources/DecisionModelsApple/GuidedGenerationModel.swift:29`). `SystemLanguageModel.default` is Apple's static, but the framework picking it silently is a default model in the framework's API, and the model behind it changes with the OS. Under the rule the caller writes `GuidedGenerationModel(.default)` and so accepts that contract. This is the one judgement call in this issue; the rest follows directly from the rule.

No other type supplies a model by default. `DecisionSession`, `Evaluation`, `RecordingModel`, `CachedModel`, `CascadeModel`, and `ConsensusModel` all take their model as a required argument. `ScriptedModel` and `ReplayModel` take no model. The macros reference no model.

`Jev.models()` and `ModelCard` (`Jev.swift:136`, `:228`) already give a developer the way to discover versions. They stay as they are.

## Location
Sources:
- `Sources/DecisionModelsTypeSafe/Jev.swift`: remove `latest` and `preview`; make `version` required in both initializers; update the type's doc comment and example (line 16) to state the contract and to point at `models()`.
- `Sources/DecisionModelsApple/GuidedGenerationModel.swift`: remove the `= .default` on the model parameter.

Docs (every example that uses a removed symbol or a default):
- `README.md` lines 53, 98, 108, 124-127.
- `DESIGN.md` lines 106, 580, 846, 853-857, 886, 940-943, 1141, 1143. Section 10.1 gains the contract paragraph. Section 17 gains a resolved decision.
- `TESTING.md` lines 65, 82, 84.
- The doc comment on `JevRequest.model` (`JevWire.swift:13`) and on `DecisionModelIdentity.name` (`DecisionModel.swift:25`) already read as examples, not defaults; leave them.

Tests:
- `Tests/DecisionModelsTypeSafeTests/AvailabilityTests.swift`: the `model(apiKey:environment:transport:)` helper (lines 11-17) passes no version; lines 101-105 test `Jev.latest` and `Jev.preview` by name.
- `Tests/DecisionModelsTypeSafeTests/JevLiveTests.swift` lines 50 and 102: `Jev(apiKey: key)`.
- `Tests/DecisionModelsTypeSafeTests/Fixtures.swift` line 144: the `harness` fixture's own `version: String = "jev-latest"` default.
- `Tests/DecisionModelsAppleTests/GuidedGenerationModelTests.swift` line 31 and `GuidedGenerationLiveTests.swift` lines 37, 85, 116, 145: `GuidedGenerationModel()`.

## Approach
- `Jev`: delete `latest` and `preview`. Make `version: String` the first, required parameter of both initializers, so `Jev(apiKey: key)` becomes `Jev(version: "jev-latest", apiKey: key)`. Rewrite the type's doc comment: the caller names the version; `jev-latest` floats, a pinned version may be retired; `models()` lists what the account can call. The doc example becomes `DecisionSession(model: Jev(version: "jev-latest"))`.
- `GuidedGenerationModel`: `public init(_ model: SystemLanguageModel, instructions: String? = nil)`. Callers write `GuidedGenerationModel(.default)`. The iOS 27 `init(_ model: some LanguageModel)` in DESIGN.md 10.1 already takes its model as required.
- DESIGN.md 10.1: replace the `Jev.latest` / `Jev.preview` lines in the code block with `Jev(version: "jev-latest")` and `Jev(version: "jev-preview")`, keep the pinned line, and add one paragraph stating the contract: the framework ships no default model or version; a floating alias may change underneath the caller; a pinned version may stop being available; `models()` lists the account's versions. Update the `GuidedGenerationModel` signature at line 886. Update the examples in sections 4, 7, 10.2, and 13.
- DESIGN.md 17: add decision 8: the framework ships no default model or version; every provider initializer takes the model or version as a required argument; the caller accepts the floating or the pinned contract by naming it.
- README and TESTING.md: replace `Jev.latest` with `Jev(version: "jev-latest")` and `GuidedGenerationModel()` with `GuidedGenerationModel(.default)`. In the README's Jev paragraph, state the contract in one or two sentences next to the pinned example that is already there.
- Tests: pass `version: "jev-latest"` in the `AvailabilityTests` helper and in both `JevLiveTests` sites. Rewrite the identity test at `AvailabilityTests.swift:101-105` so it builds `Jev(version: "jev-latest", apiKey: "k")` and `Jev(version: "jev-preview", apiKey: "k")` and checks `identity.name`. Write `GuidedGenerationModel(.default)` at the five Apple sites. The `harness` fixture keeps its `version` default: it is test code, and that default is where the retry and wire tests name their model in one place. Do not add a default back into `Sources` to make a test shorter.
- Style: docs and doc comments follow the project's writing rules (short sentences, active voice).

## Related Issues
Parent wip/dmv1 (v1 per DESIGN.md; its conventions say public API names follow DESIGN.md exactly, so DESIGN.md changes in the same commit). wip/jev built the provider and its `latest` / `preview` statics. wip/apple built `GuidedGenerationModel`. wip/docs wrote the README and TESTING.md examples.

## Acceptance Criteria
- [ ] `Jev.latest` and `Jev.preview` no longer exist, and `Jev(apiKey:)` no longer compiles: `version` is required in both initializers.
- [ ] `GuidedGenerationModel()` no longer compiles: the model is required.
- [ ] `grep -rn '"jev-latest"\|"jev-preview"\|SystemLanguageModel = .default' Sources` finds nothing outside doc comments.
- [ ] DESIGN.md 10.1 states the contract, section 17 records the decision, and no example in README.md, DESIGN.md, or TESTING.md references a removed symbol or relies on a removed default.
- [ ] Every test that builds a `Jev` or a `GuidedGenerationModel` names its model. `grep -rn "Jev.latest\|Jev.preview\|GuidedGenerationModel()" Tests` finds nothing.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean.
- [ ] `swift test --skip JevLive --skip GuidedGenerationLiveTests` passes.
- [ ] The Jev live suite passes once with the key sourced (`set -a; . ./.env; set +a; swift test --filter JevLive`).
- [ ] The Apple live suite passes once on a Mac with Apple Intelligence on (`swift test --filter DecisionModelsAppleTests`). If the machine cannot run it, say so in the closing note; CI still builds the adapter for the iOS Simulator.

---

_📝 Noted on 2026-09-20 01:16:04-04:00 @ git:74e8394+local_

Design decisions for the prose (2026-09-20). Inventory verified against the issue: no extra sites. Prose written in the main context, edits delegated to an Opus agent.

Jev doc comment gains one paragraph before the example: 'The caller names the version. There is no default. `jev-latest` floats: the model behind it can change at any time. A pinned version such as `jev-1.13.0` stays fixed, but the service can retire it. `models()` lists the versions the account can call.' Example becomes DecisionSession(model: Jev(version: "jev-latest")).

DESIGN.md 10.1: code block lines become Jev(version: "jev-latest") / Jev(version: "jev-preview") / pinned line unchanged. One paragraph after the block: 'The framework ships no default model or version. The caller names one and so accepts its contract. A floating alias such as `jev-latest` can change underneath the caller at any time. A pinned version can stop being available when the service retires it. `models()` lists the versions the account can call.' GuidedGenerationModel signature drops '= .default'; the instructions paragraph gains: 'The caller passes the model. `.default` is Apple's shared on-device model, and the model behind it changes with the OS.'

DESIGN.md 17 decision 8: 'The framework ships no default model or version. Every provider initializer takes the model or the version as a required argument. The caller accepts the floating or the pinned contract by naming it.'

README Jev paragraph gains: 'The caller names the version. `jev-latest` floats: the model behind it can change at any time. A pinned version stays fixed until the service retires it.'

Examples with several Jev.latest uses (README wrappers, TESTING evaluation, DESIGN 13) bind 'let jev = Jev(version: "jev-latest")' once rather than repeat the initializer. DESIGN 10.2 wrappers block uses 'jev' as a free variable, matching 'onDevice', 'cache', 'recorder' in the same block.

---

_📝 Noted on 2026-09-20 01:20:02-04:00 @ git:74e8394+local_

Edits applied by an Opus agent from the prose above; diff reviewed in the main context. One follow-up in the main context: realigned the trailing comments in the DESIGN.md 10.2 wrappers block after the shorter name shifted them. Build with warnings-as-errors clean; offline suite 396 tests pass; JevLive 2 tests pass with the key sourced; DecisionModelsAppleTests 48 tests pass on this Mac with Apple Intelligence on. No DEADCODE doc in the project; the change removes code and adds none, so nothing new is dead.

---

_📝 Noted on 2026-09-20 01:27:50-04:00 @ git:74e8394+local_

Verifier (Opus) confirmed all nine criteria. It compiled the negatives from a scratch package outside the repo: Jev(apiKey:), Jev(), Jev.latest, Jev.preview, and GuidedGenerationModel() all fail to compile; every changed doc example compiles against the real types; the iOS Simulator build succeeds. One cosmetic finding fixed in the main context: DESIGN.md 10.1 said what models() does twice; merged into one sentence in the contract paragraph that keeps the ModelCard type name. Summary: removed Jev.latest and Jev.preview; version is required in both Jev initializers; GuidedGenerationModel takes its model as required; DESIGN.md 10.1 states the contract and section 17 records decision 8; README, TESTING.md, and every DESIGN.md example name the model; ten test sites name their model; the harness fixture keeps its test-only default.
