---
priority: p2
type: task
created: 2026-09-22T16:50:52-04:00
updated: 2026-09-22T16:50:52-04:00
blocked-on:
  - 8ei
  - kst
  - 169
---

# Docs: requests without state in DESIGN.md, README.md, and TESTING.md

## Objective
Document requests without state in DESIGN.md, README.md, and TESTING.md, so the API, each provider's wire behaviour, and the live tests match what shipped.

## Context
Child of the parent feature; blocked on the four implementation children, so the docs describe settled behaviour, including whatever the OpenRouter probe found.

## Location
- `DESIGN.md` section 7, State: a request may carry no state; the context alone then serves as state; the core never substitutes a value; `.null` and absence are the same once they pass through JSON.
- `DESIGN.md` section 8, Sessions: the five new signatures, beside the existing ones.
- `DESIGN.md` section 10 and the `CacheKey` sentence near line 1032: the key's optional state. The replay paragraph near line 1196 likewise.
- `DESIGN.md` section 10.1, the Apple provider: the stateless prompt and instructions.
- `README.md`: a short example after the triage example, the Atlanta question through `session.decide(questionnaire)` or an `@Ask` type with no `about:`.
- `TESTING.md`: the live suites' request counts and the new local Apple test.

## Related Issues
Parent feature and all four implementation children.

## Acceptance Criteria
- [ ] Every new public signature in DESIGN.md section 8 matches the code.
- [ ] The README example compiles as written; check it against the API or paste it into a test.
- [ ] TESTING.md lists the new live tests and the keys they need.
