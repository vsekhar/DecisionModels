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
let session = DecisionSession(model: RecordingModel(Jev(version: "jev-latest"), into: recorder))
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
let jev = Jev(version: "jev-latest")
let report = try await Evaluation(models: [jev, GuidedGenerationModel(.default)])
    .run(TicketTriage.self, on: labeled)   // [(state: State, expected: TicketTriage)]
let team = report[jev.identity]?.question("team")
team?.accuracy
team?.brierScore
team?.expectedCalibrationError
team?.bands(escalateBelow: 0.5, confirmBelow: 0.9)
```

Models in one evaluation need distinct identities.

## Continuous integration

`.github/workflows/ci.yml` runs on every push, on pull requests from forks,
and on demand. The CI badge shows its result on `main`, and the codecov
badge shows the line coverage of `main`.

| Job | Runner | What it runs |
|---|---|---|
| macOS tests | `macos-26`, Xcode 26.6 | the offline suite and the Jev live suite in one run, with warnings as errors and coverage on, then the coverage upload |
| iOS build | `macos-26`, Xcode 26.6 | a build of every product for the iOS Simulator |
| Linux tests | `ubuntu-latest`, `swift:6.3.3-noble` container | the offline suite and the Jev live suite, with warnings as errors |

The tests run in one `swift test` run because each run with coverage
clears the coverage of the run before it. To reproduce the CI step:

```sh
set -a; . ./.env; set +a
swift test -Xswiftc -warnings-as-errors --enable-code-coverage --skip GuidedGenerationLiveTests
```

The CI build log may show pairs of lines like these:

```
Internal Error: DecodingError.dataCorrupted: ... Corrupted JSON. Underlying error: unexpected end of file
LLVM Profile Error: Failed to write file "default.profraw": Operation not permitted
```

They are harmless: the build and every test still pass. On the CI runner,
the compiler sometimes sends a macro plugin a message that ends early. The
plugin reports it and exits, which gives the first line. This happens with
or without coverage. With coverage on, SwiftPM instruments the plugin too,
and on exit it tries to write its coverage file. The compiler runs plugins
in a sandbox that allows writes to no folder, so that fails, which gives the
second line. The plugin's coverage is not part of the report. The Linux
job shows the first line alone, without the second, because coverage is
off there.

No environment variable can redirect that file. The compiler starts each
plugin with an empty environment, so `LLVM_PROFILE_FILE` never reaches it.
The only switch that removes the second line is `swift test
--disable-sandbox`, which turns the plugin sandbox off. CI keeps the sandbox
on, so the macros build under the same sandbox as in users' builds.

The coverage report holds only the package's own sources. Tests,
swift-syntax, and the generated test runner are left out, because the
export names the `Sources` folder:

```sh
bin=$(swift build --show-bin-path)
xcrun llvm-cov export -format=lcov \
  -instr-profile "$bin/codecov/default.profdata" \
  "$bin/DecisionModelsPackageTests.xctest/Contents/MacOS/DecisionModelsPackageTests" \
  "$PWD/Sources" > coverage.lcov
```

CI coverage leaves out the Apple live suite, so it understates the Apple
adapter: on 2026-09-19 the adapter stood at 69% of lines in CI and 92% with
the live suite. The whole package stood at 91.7% in CI and 95.1% with it.

Two repository secrets feed the job:

- `TYPESAFE_API_KEY` for the Jev live suite. Set it once from the package
  root. The first form prompts for the value, so paste the key. The second
  sets every variable in `.env` as a secret, so use it only if `.env` holds
  nothing else.

  ```sh
  gh secret set TYPESAFE_API_KEY
  gh secret set -f .env
  ```

  Without it, the Jev suite fails, as it does locally without the key.
- `CODECOV_TOKEN` for the upload. A failed upload fails the job, so a bad
  token shows at once.

A pull request from a branch in this repository runs on its push, not
again as a pull request. A pull request from a fork runs the offline suite
on macOS and on Linux and the iOS build, but skips the Jev suite and the
upload, because forks get no secrets.

The Apple live suite does not run in CI. GitHub's macOS runners are virtual
machines, and Apple Intelligence does not run in one. Run that suite on a
Mac with Apple Intelligence turned on, as described above.

The runner must be macOS 26: the Apple tests check the OS at run time and
record a failure on an older one.

## Linux

The core, TypeSafe, and testing targets build and pass their tests on
Linux. CI checks this on every push. Every file that imports
FoundationModels sits behind `#if canImport(FoundationModels)`, so the
Apple adapter's suites are absent on Linux. What is left, the prompt
builder, its tests, and the test helpers, needs no Apple framework and
builds on both platforms.

Run the offline suite in the official Swift image. The tag pins the Swift
version that Xcode 26.6 ships, 6.3.3, so both platforms build with the
same compiler. The scratch path keeps the Linux build products apart from
the Mac's:

```sh
docker run --rm -v "$PWD":/pkg -w /pkg swift:6.3.3-noble \
  swift test -Xswiftc -warnings-as-errors --scratch-path .build/linux --skip JevLive
```

To add the Jev suite, pass the key in from the environment:

```sh
set -a; . ./.env; set +a
docker run --rm -e TYPESAFE_API_KEY -v "$PWD":/pkg -w /pkg swift:6.3.3-noble \
  swift test -Xswiftc -warnings-as-errors --scratch-path .build/linux
```

On Linux, `URLSession`, `URLRequest`, `HTTPURLResponse`, and `URLError`
live in the `FoundationNetworking` module. Every file that names one of
them imports it behind `#if canImport(FoundationNetworking)`. Keep that
guard when you add one.
