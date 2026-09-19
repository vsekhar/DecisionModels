# Testing

All tests use Swift Testing. Run them from the package root with Xcode 26.6
or later.

## Everything but the live suites

```sh
swift test --skip JevLive --skip GuidedGenerationLiveTests
```

This runs the core, macro expansion, provider wire format, testing module,
and composition suites. No key and no Apple Intelligence needed.

Build with warnings as errors before you commit:

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
```

## Macro tests only

The compiler plugin takes minutes to build the first time. While iterating
on it:

```sh
swift test --filter DecisionModelsMacrosTests
```

## Live tests against Jev

The Jev suite makes two requests to TypeSafe's service. It reads
`TYPESAFE_API_KEY` from the environment and **fails** when the variable is
absent; it never skips. Put the key in `.env` (ignored by git) and source
it for one command:

```sh
set -a; . ./.env; set +a; swift test --filter JevLive
```

Do not print the key, and do not commit `.env`.

## Live tests against the on-device model

The Apple suite needs a Mac with Apple Intelligence turned on and the
model downloaded. It **fails** when the system model is unavailable; it
never skips. Each live call takes a second or so.

```sh
swift test --filter DecisionModelsAppleTests
```

## The whole suite, with both backends

```sh
set -a; . ./.env; set +a; swift test
```

## Recording and replaying a provider

`DecisionModelsTesting` turns real traffic into fixtures.

```swift
let recorder = Recorder()
let session = DecisionSession(model: RecordingModel(Jev.latest, into: recorder))
_ = try await session.decide(TicketTriage.self, about: ticket)
try await recorder.write(to: fixtureURL)

// Later, with no key and no network:
let replay = ReplayModel(records: try Recorder.read(from: fixtureURL))
let offline = DecisionSession(model: replay)
```

A replay matches on the state, the questionnaire, and the sample count.
Metadata and timeout do not affect the match. Record fixtures from real
reads, not from plain-value decisions: a certain choice record lists one
option, a read lists them all.

## Evaluating a model on labeled data

```swift
let report = try await Evaluation(models: [Jev.latest, GuidedGenerationModel()])
    .run(TicketTriage.self, on: labeled)   // [(state: State, expected: TicketTriage)]
let team = report[Jev.latest.identity]?.question("team")
team?.accuracy
team?.brierScore
team?.expectedCalibrationError
team?.bands(escalateBelow: 0.5, confirmBelow: 0.9)
```

Models in one evaluation need distinct identities.

## Continuous integration

`.github/workflows/ci.yml` runs on every push, on pull requests from forks,
and on demand. The README badge shows its result on `main`.

| Job | Runner | What it runs |
|---|---|---|
| macOS tests | `macos-26`, Xcode 26.6 | the offline suite with warnings as errors, then the Jev live suite |
| iOS build | `macos-26`, Xcode 26.6 | a build of every product for the iOS Simulator |

The Jev step reads the repository secret `TYPESAFE_API_KEY`. Set it once
from the package root. The first form prompts for the value, so paste the
key:

```sh
gh secret set TYPESAFE_API_KEY
```

The second form sets every variable in `.env` as a secret. Use it only if
`.env` holds nothing else:

```sh
gh secret set -f .env
```

Without the secret, the Jev step fails, as the live suite does locally
without the key.

A pull request from a branch in this repository runs on its push, not
again as a pull request. A pull request from a fork runs the offline suite
and the iOS build but skips the Jev step, because forks get no secrets.

The Apple live suite does not run in CI. GitHub's macOS runners are virtual
machines, and Apple Intelligence does not run in one. Run that suite on a
Mac with Apple Intelligence turned on, as described above.

The runner must be macOS 26: the Apple tests check the OS at run time and
record a failure on an older one.

## Linux

The core, TypeSafe, and testing targets are written to build on Linux, but
the build has not been verified yet (see `wip show linux`). CI will gain a
Linux job when that check passes.
