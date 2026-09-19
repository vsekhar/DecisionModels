---
priority: p2
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T01:01:39-04:00
blocked-on:
  - macros
  - jev
  - testing
  - apple
  - compose
  - fanout
  - commands
  - hier
  - composite
---

# README and TESTING docs

## Objective
Write `README.md` and `TESTING.md`.

## Context
Child of wip/dmv1. Last issue.

## Approach
- `README.md`: what the framework is, the section 4 example, how to add the package, one paragraph per provider, how to swap models, a short section on confidence and thresholds, link to `DESIGN.md`.
- `TESTING.md`: how to run unit tests, macro tests, live Jev tests (`set -a; . ./.env; set +a; swift test --filter Jev`), live Apple tests (requires Apple Intelligence; they fail otherwise), how to record and replay fixtures.
- Short sentences, active voice.

## Related Issues
All siblings.

## Acceptance Criteria
- [ ] Both files exist and every command in `TESTING.md` has been run once and works.
