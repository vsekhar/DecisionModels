---
priority: p2
type: task
created: 2026-09-20T02:41:01-04:00
updated: 2026-09-20T02:59:16-04:00
may-unblock:
  - sxs
---

# DecisionModelsTestSupport: shared scripted transport and fake clock

## Objective
Move `Reply`, `ScriptedTransport`, `FakeClock`, and `isClose` out of the Jev test target into a plain target `DecisionModelsTestSupport`, so the OpenRouter test target (wip/sxs) can use them without a copy.

## Context
Child of wip/sxs, carved out so the fixture move lands and is verified on its own. wip/9du put the shared `HTTPClient` in core, and put its direct tests in `Tests/DecisionModelsTypeSafeTests/HTTPClientTests.swift` only because the fixtures lived there. Those tests move to the core test target here.

## Location
- `Package.swift`: `.target(name: "DecisionModelsTestSupport", dependencies: ["DecisionModels"])`, no product. `DecisionModelsTests` and `DecisionModelsTypeSafeTests` add it as a dependency.
- New `Sources/DecisionModelsTestSupport/ScriptedTransport.swift` (`Reply` and `ScriptedTransport`) and `Sources/DecisionModelsTestSupport/FakeClock.swift` (`FakeClock` and `isClose`).
- `Tests/DecisionModelsTypeSafeTests/Fixtures.swift` keeps `Harness`, `harness(...)`, `Team`, `Severity`, `ticket`, and `triage()`.
- `Tests/DecisionModelsTypeSafeTests/HTTPClientTests.swift` moves to `Tests/DecisionModelsTests/HTTPClientTests.swift` (git mv).
- Every test file that names a moved type adds `import DecisionModelsTestSupport`.
- `DESIGN.md` 15: the layout gains the target.

## Approach
- Everything the tests call is `package`: the two types, their initializers, `Reply`'s fields and static builders, `sent`, `waited`, `elapsed`, `advance`, `reading`, `record`, and `isClose`. Nothing is `public`; the target is not a product.
- `ScriptedTransport.fallbackURL` loses its TypeSafe host and becomes `https://example.invalid/`. It is only the URL of a scripted reply to a request that has no URL.
- Doc comments move as they are. Same code, same behavior. The Jev retry tests are the regression net; the only edit they may take is the import line.
- The new target imports Foundation, FoundationNetworking under `canImport`, and Synchronization. iOS 18 / macOS 15 covers `Mutex`.

## Related Issues
Parent: wip/sxs, which is blocked on this. wip/9du wrote HTTPClientTests and asked for this move.

## Acceptance Criteria
- [ ] `grep -rn "class ScriptedTransport\|class FakeClock\|struct Reply\|func isClose" Tests/` finds nothing; the definitions live in `Sources/DecisionModelsTestSupport/` with `package` visibility and no `public`.
- [ ] `Tests/DecisionModelsTests/HTTPClientTests.swift` exists and the Jev test target no longer holds it.
- [ ] `git diff -- Tests/DecisionModelsTypeSafeTests/RetryTests.swift` shows an import line and nothing else.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean, and `swift test --skip JevLive --skip GuidedGenerationLiveTests` passes 401 tests in 43 suites.
- [ ] DESIGN.md 15 lists `DecisionModelsTestSupport/`.

---

_📝 Noted on 2026-09-20 02:48:55-04:00 @ git:1d94ae3+local_

Implemented by a worker per the issue text (2026-09-20). Package.swift gains the plain target DecisionModelsTestSupport and both HTTP test targets depend on it; Sources/DecisionModelsTestSupport/ScriptedTransport.swift holds Reply and ScriptedTransport, FakeClock.swift holds FakeClock and isClose, all package-visible with no public; HTTPClientTests moved to Tests/DecisionModelsTests; RetryTests changed by the import line only; DESIGN.md 15 lists the target.

Correction to the first acceptance criterion: the grep over all of Tests/ still finds four isClose copies in DecisionModelsMacrosTests, DecisionModelsTestingTests, DecisionModelsAppleTests (tolerance 1e-9), and DecisionModelsTests. They pre-date this issue and those targets are out of its scope; the criterion should have named the Jev test target only, where the grep is now empty. Consolidating the other copies is possible follow-up work, not part of this move.

Worker judgement calls, accepted: the two test-target lines in Package.swift wrap over three lines to stay under 100 columns; the "MARK: A transport with a script" marker went with the file split. I removed the now-unused Foundation and FoundationNetworking imports from the trimmed Fixtures.swift myself.

---

_📝 Noted on 2026-09-20 02:59:16-04:00 @ git:1d94ae3+local_

Verifier: all five criteria hold, approve, no blockers. Notes applied: the two long DESIGN.md 15 lines wrap at the block's width; the 15.1 platform row names DecisionModelsTestSupport; Reply gains an explicit package memberwise initializer (the synthesized one stayed internal, which another test target could not call). Verifier also confirmed plain swift build compiles the target, so the iOS scheme builds it too (Mutex needs iOS 18, the package floor). Final: build clean under -warnings-as-errors, 401 tests in 43 suites.
