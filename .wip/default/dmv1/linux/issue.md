---
priority: p3
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T01:01:39-04:00
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
