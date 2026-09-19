---
priority: p3
type: task
created: 2026-09-19T15:10:57-04:00
updated: 2026-09-19T15:10:57-04:00
---

# Move CI actions to Node 24 majors: checkout v7, cache v6

## Objective
Clear the Node.js 20 deprecation warnings in CI by moving to the current major versions of the two actions the workflow uses.

## Context
CI run 35463025132 carried two warnings: `actions/checkout@v4` and `actions/cache@v4` target Node.js 20, which GitHub deprecated, and are forced onto Node.js 24. On 2026-09-19 the latest releases were checkout v7.0.1 and cache v6.1.0; both declare `using: node24` in their action.yml. Follows wip/jso.

Breaking changes checked against this workflow: checkout v5 (Node 24; runner 2.327.1 or later, which hosted runners meet), v6 (credentials persisted to a separate file; unused here), v7 (blocks fork checkouts for pull_request_target and workflow_run; this workflow uses neither). cache v5 (Node 24), v6 (ESM repackaging; inputs unchanged).

## Location
`.github/workflows/ci.yml`

## Acceptance Criteria
- [ ] Every `actions/checkout` reference is `@v7` and the `actions/cache` reference is `@v6`.
- [ ] The workflow still parses; triggers, jobs, and conditions are unchanged.
- [ ] The next CI run shows no Node.js 20 warning.
