---
priority: p3
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-20T00:47:30-04:00
blocked-on:
  - jev
  - testing
---

# Verify Linux build of non-Apple targets

## Objective
Verify that `DecisionModels`, `DecisionModelsTypeSafe`, and `DecisionModelsTesting` build and pass tests on Linux.

## Context
Child of wip/dmv1. Deferred by decision on 2026-09-19. The design (DESIGN.md 15) promises Linux support for the non-Apple targets. `DecisionModelsApple` and the SwiftUI environment key are excluded by `#if canImport`.

## Approach
Run `docker run --rm -v "$PWD":/pkg -w /pkg swift:6.2 swift test --filter 'DecisionModelsTests|TypeSafe|Testing'`. Fix any Foundation differences (`URLSession` on Linux needs `FoundationNetworking`). Add the command to `TESTING.md`.

## Acceptance Criteria
- [ ] The three targets build and their unit tests pass on Linux.
- [ ] `TESTING.md` documents the command.

---

_📝 Noted on 2026-09-20 00:29:47-04:00 @ git:1dadff5+local_

Design: verify Linux with a CI job, not docker (no docker on this machine). Job 'linux' in ci.yml: runs-on ubuntu-latest, container swift:6.3-noble. Chose 6.3 over the issue's 6.2 because Xcode 26.6 (the pinned macOS toolchain) ships Swift 6.3.3, so both platforms build with the same compiler; the docker-library manifest lists 6.3.3 (noble default) and 6.4.0 (resolute default). Same fork condition and SKIP_JEV rule as the macOS job; the Jev live suite runs on Linux too, which exercises FoundationNetworking's URLSession for real. No coverage on Linux. No --skip for the Apple live suite: all Apple files except PromptBuilder are behind canImport(FoundationModels), so they compile to nothing. Plan: push branch 'linux', watch the run, fix, then fast-forward main.

---

_📝 Noted on 2026-09-20 00:32:52-04:00 @ git:c658481_

Run 1 (35489310820) failed before building: a container job runs 'run:' steps with sh, not bash, so 'skip=()' was a syntax error. Fix: 'shell: bash' on the Linux Tests step. Inventory (Sonnet scan of the 8 in-scope targets) found one real portability hole: RetryTests.swift used URLRequest with no FoundationNetworking import; added the same canImport guard its siblings carry. Everything else checks out: SwiftUI import in Environment.swift is behind canImport(SwiftUI); Synchronization.Mutex, ContinuousClock, FileManager.temporaryDirectory, URL.appending(path:), ProcessInfo.environment all exist on Linux; no resources, unsafeFlags, XCTest, or #if os() anywhere. Run 2 is 35489403844.

---

_📝 Noted on 2026-09-20 00:47:30-04:00 @ git:bd6f531+local_

Verifier (run 35489403844 as evidence): both acceptance criteria hold. Conservation check: macOS ran 398 tests / 43 suites, Linux 367 / 39; the 4 missing suites are exactly the FoundationModels ones (31 tests). JevLive really hit the service on Linux. Should-fix findings, both docs: (1) the FoundationNetworking rule named only URLSession/URLRequest; now lists HTTPURLResponse and URLError too. (2) 'Apple files all sit behind canImport' was false for PromptBuilder.swift, PromptBuilderTests.swift, TestSupport.swift; reworded in TESTING.md and ci.yml. Also pinned the image to swift:6.3.3-noble (the 6.3 tag floats; the 'matches Xcode 26.6' claim is only true with the patch pinned), moved the Linux plugin-log sentence to the paragraph end, and noted that fork PRs now run the offline suite on both OSes. Left as-is: no coverage on Linux; the docker recipes are unrun end to end (no docker here); CI covers the image and the flags but not docker run or --scratch-path.

---

_📝 Noted on 2026-09-20 00:47:30-04:00 @ git:bd6f531+local_

Summary: added a 'linux' job to ci.yml (ubuntu-latest, container swift:6.3.3-noble, shell: bash, build cache, same fork/SKIP_JEV rules as macOS, no coverage). Fixed the one Linux compile hole, a missing FoundationNetworking guard in RetryTests.swift. TESTING.md: new CI table row, rewritten Linux section with two docker recipes (offline, and with the Jev key), the FoundationNetworking guard rule, and the Linux form of the harmless plugin log lines. Cold Linux job: 2m38s.
