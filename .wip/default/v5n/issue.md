---
priority: p2
type: task
created: 2026-09-19T15:36:49-04:00
updated: 2026-09-19T15:36:49-04:00
---

# Report CI coverage to Codecov with a README badge

## Objective
Report CI test coverage to Codecov and show the Codecov badge in the README.

## Context
Measured on 2026-09-19: line coverage of the package's own sources is 91.7% for what CI runs (offline tests plus Jev live) and 95.1% with the on-device Apple tests. The user set up Codecov for the repository and added the `CODECOV_TOKEN` secret. The latest `codecov/codecov-action` is v7.1.1, a composite action, so it brings no Node runtime warning (see wip/yam).

Each `swift test --enable-code-coverage` run clears the earlier run's raw profiles (the coverage folder holds only the last run's `.profraw` files), so CI must collect coverage in one test run. Today the offline tests and the Jev live tests run as two steps.

## Location
`.github/workflows/ci.yml`, `README.md`, `TESTING.md`.

## Approach
- Merge the two test steps into one: `swift test -Xswiftc -warnings-as-errors --enable-code-coverage --skip GuidedGenerationLiveTests`, adding `--skip JevLive` on pull request events, where forks get no secrets.
- Change the cache key, because coverage changes the compiler flags and the old key's cached build no longer matches.
- Export lcov with `xcrun llvm-cov export -format=lcov` from `<bin>/codecov/default.profdata` and `<bin>/DecisionModelsPackageTests.xctest/Contents/MacOS/DecisionModelsPackageTests`, ignoring `.build/` and `Tests/`, so Codecov sees only the package's sources.
- Upload with `codecov/codecov-action@v7` on push events, using the token, `disable_search`, and `fail_ci_if_error`. Every push uploads, so Codecov can compare a branch with `main`; the badge follows `main`.
- README: add the Codecov badge beside the CI badge. TESTING.md: describe the single step, coverage, and the upload.

## Related Issues
wip/jso (CI), wip/yam (Node 24 actions), wip/ajp (Jev per-attempt timeout; a Jev stall now also stops the coverage upload for that run).

## Acceptance Criteria
- [ ] The exact test command passes once on the development Mac, and the lcov export from it covers only `Sources/` and totals about 91.7% of lines.
- [ ] The workflow parses; fork pull requests skip the Jev suite and the upload.
- [ ] README carries the Codecov badge; TESTING.md explains the coverage step.
- [ ] After a push, Codecov receives the report and the badge shows a percentage.
