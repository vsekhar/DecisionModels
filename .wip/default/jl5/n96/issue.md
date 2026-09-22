---
priority: p2
type: task
created: 2026-09-22T16:50:52-04:00
updated: 2026-09-22T18:03:30-04:00
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

---

_📝 Noted on 2026-09-22 17:27:06-04:00 @ git:2f0531d+local_

From the wip/e7t verifier, 2026-09-22: (1) DESIGN.md line 818 still declares DecisionRequest.state as a non-optional State; update it with the optional and its doc sentence. (2) Record the replay consequence of design decision 6 on the parent: a call recorded with a state of State.null replays only in memory; after the record round-trips through JSON its state is nil, so ReplayModel misses it. One sentence in the replay paragraph near DESIGN.md line 1196 and in TESTING.md's replay section.

---

_📝 Noted on 2026-09-22 18:03:30-04:00 @ git:5171280+local_

From the wip/8ei and wip/kst verifier, 2026-09-22: both live APIs require a state, so the providers send an empty string for a request with no state or with a .null state (parent decision 2, amended). On the wire a caller's genuine empty-string state and no state are the same body; CacheKey and ReplayKey keep them apart. Say both in DESIGN.md section 7 and in the provider sections, and update the README example accordingly: the request still carries a state field on the wire, the caller just does not supply one.
