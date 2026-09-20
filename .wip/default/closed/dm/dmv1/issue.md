---
priority: p1
type: feature
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-20T02:20:38-04:00
---

# Build DecisionModels v1 per DESIGN.md

## Summary
Build the DecisionModels Swift package described in `DESIGN.md` (approved revision 3): a framework that lets Swift code declare typed questions as a struct, send them to a decision model, and read typed answers with full probability distributions. The model under the session is swappable: hosted TypeSafe Jev, Apple's on-device model through guided generation, and test doubles.

## User Story
An app or server developer declares `@Decision struct` types, calls `session.decide(about:)`, and branches on plain Swift values and confidences. They can switch from Jev to an on-device model, or to a scripted double in tests, by changing one line.

## Design Decisions
All in `DESIGN.md`. Read it in full before starting any child issue. Section 17 lists the approved decisions; do not reopen them. Section 15.1 gives platform minimums: package declares iOS 18 / macOS 15; `DecisionModelsApple` types are `@available(iOS 26, macOS 26, *)`; the generic `LanguageModel` initializer is iOS 27 / macOS 27.

When implementation forces a deviation from the design, make the smallest change, update `DESIGN.md` in the same commit, and log the reason with `wip note`.

## Conventions
- Swift 6.2 tools, strict concurrency, Swift Testing (`import Testing`) for all tests. Macro expansion tests use `SwiftSyntaxMacrosGenericTestSupport` or `MacroTesting`.
- Public API names exactly as in `DESIGN.md`.
- Writing style in docs and doc comments: short sentences, active voice.
- Commits go directly on `main`. Never push. Each issue closes in the commit that carries its code; the commit message ends with `Closes wip/<id>`.
- Do not read `.env`. Live Jev tests get the key from the environment: `set -a; . ./.env; set +a; swift test --filter Jev`.

## Out of Scope
- Verifying the Linux build (wip/linux, deferred).
- Pushing to a remote, CI configuration.

## Testing Strategy
- Unit tests against fakes for every target.
- Macro expansion tests plus end-to-end tests of the section 4 example against a scripted model.
- Live tests against Jev that **fail** (not skip) when `TYPESAFE_API_KEY` is absent.
- Live tests against `SystemLanguageModel` that **fail** (not skip) when Apple Intelligence is unavailable on the machine.
- `swift build` and `swift test` clean with no warnings in the package's own code.

## Completion
The parent closes when all children are closed, `swift test` passes with the live backends present, and `README.md` and `TESTING.md` exist (wip/docs).

---

_📝 Noted on 2026-09-19 06:40:52-04:00 @ git:1d580ea_

State on 2026-09-19: twelve of thirteen children closed and committed on main; every commit closes the issue it carries. The remaining child, wip/linux, is the Linux build verification the user chose to defer, so this parent stays open until that runs. Full suite from main with both live backends: 397 tests in 44 suites pass. Live tests fail, not skip, without their backend.

---

_📝 Noted on 2026-09-20 02:20:38-04:00 @ git:edec507_

2026-09-20: wip/linux closed with the Linux CI job (commit 74e8394). Full suite from main with both live backends: 403 tests in 44 suites pass. README.md and TESTING.md exist. All completion criteria met; closing.
