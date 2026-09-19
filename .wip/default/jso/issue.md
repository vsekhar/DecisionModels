---
priority: p2
type: task
created: 2026-09-19T14:50:44-04:00
updated: 2026-09-19T14:50:44-04:00
---

# Add CI with the Jev live suite on every push

## Objective
Add a GitHub Actions workflow that runs the offline suite, builds for iOS, and runs the Jev live tests on every push, and put its badge in the README.

## Context
Decided on 2026-09-19. Jev is cheap and fast, so the live Jev suite runs on every push and counts toward the badge. The Apple live suite stays out of CI: GitHub's macOS runners are virtual machines, where Apple Intelligence does not run, and a self-hosted runner is deferred. The remote is github.com/vsekhar/DecisionModels. GitHub's `macos-26` arm64 image carries macOS 26.6.2 with Xcode 26.6 at /Applications/Xcode_26.6.app, which matches the development Mac. The Apple offline tests need macOS 26 at run time, so the runner must be `macos-26`.

## Location
`.github/workflows/ci.yml` (new), `README.md` (badge), `TESTING.md` (CI section).

## Approach
- Trigger on every push, on pull requests, and on manual dispatch. A pull request from a branch in this repository already ran on its push, so jobs run on a pull request only when it comes from a fork.
- `macos` job on `macos-26`: pin Xcode 26.6, cache `.build` keyed on `Package.resolved`, run `swift test -Xswiftc -warnings-as-errors --skip JevLive --skip GuidedGenerationLiveTests`, then run `--filter JevLive` with the same flags and `TYPESAFE_API_KEY` from a repository secret. Forks get no secrets, so the Jev step does not run on pull request events.
- `ios` job on `macos-26`: `xcodebuild build -scheme DecisionModels-Package -destination 'generic/platform=iOS Simulator' -skipMacroValidation`, the only check of the iOS 18 claim.
- No Linux job until wip/linux passes.

## Acceptance Criteria
- [ ] Every command the workflow runs has passed once on the development Mac.
- [ ] The workflow file is valid YAML with the expected triggers, jobs, and conditions.
- [ ] README carries the badge; TESTING.md explains what CI runs, where the key comes from, and why the Apple live suite is not in CI.
