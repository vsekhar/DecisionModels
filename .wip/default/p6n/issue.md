---
priority: p3
type: task
created: 2026-09-19T15:56:21-04:00
updated: 2026-09-19T15:56:21-04:00
---

# Point the macro plugin's coverage file at a sandbox-writable folder

## Objective
Stop the macro plugin's coverage runtime from failing to write its data file during the CI build, by pointing it at a folder the compiler's plugin sandbox allows.

## Context
CI run 35465107028 (commit c77fb70, 2026-09-19) passed, but its Tests step printed 27 pairs of errors during the build:

- `LLVM Profile Error: Failed to write file "default.profraw": Operation not permitted`
- `Internal Error: DecodingError.dataCorrupted: ... Corrupted JSON. Underlying error: unexpected end of file`

With `--enable-code-coverage`, SwiftPM instruments every target, including the `DecisionModelsMacros` plugin executable. The compiler runs that plugin in a sandbox; when a plugin process exits, the coverage runtime tries to write `default.profraw` into its working directory, and the sandbox refuses. The errors are harmless (all 392 tests passed, the end-to-end macro tests included, and Codecov received the expected 63 files at 92.06%), but they are noise that hides real errors. A local coverage run built under /private/tmp showed none of them.

## Location
`.github/workflows/ci.yml` (the Tests step), `TESTING.md` (the CI section).

## Approach
- Reproduce on the development Mac by building with coverage inside the repository's `.build` folder, as CI does.
- Find a folder the plugin sandbox lets the plugin write to, and set `LLVM_PROFILE_FILE` for the build to a pattern there with `%p`, so each plugin process writes its own file.
- Confirm SwiftPM still sets its own `LLVM_PROFILE_FILE` for the test process, so the test coverage is unchanged.
- Find out whether the paired decoding error goes away with the profile error, and record what it is if it does not.

## Related Issues
wip/v5n (coverage in CI).

## Acceptance Criteria
- [ ] The errors reproduce locally without the change and disappear with it.
- [ ] Test coverage is unchanged with the change: the lcov export holds the same 63 files and the same totals.
- [ ] The next CI run's Tests step shows no `LLVM Profile Error`.
