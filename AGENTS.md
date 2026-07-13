# Repository Guidelines

## Project Structure & Module Organization
- `SwiftChessDemo/`: SwiftUI app entry point, views, and view models.
- `../SwiftChessTools/`: sibling Swift package dependency that provides
  `ChessCore`, `ChessUI`, and `ChessUCI` command/parser helpers.
- `../StockfishEmbedded/`: sibling Xcode project dependency that provides `SFEngine-iOS`.
- `ArasanEmbedded`: remote Swift package dependency that provides
  `ArasanEngine`.
- `SwiftChessDemo.xcodeproj/`: Xcode project; assets live in `SwiftChessDemo/Assets.xcassets`.

Public and local development both expect `SwiftChessDemo`, `SwiftChessTools`,
and `StockfishEmbedded` to be sibling checkouts under any parent directory. The
parent folder does not need to be a Git repo. `ArasanEmbedded` is resolved by
Swift Package Manager from its public GitHub repository.

The supported development host is an Apple-silicon Mac with Xcode 26. The app
uses Swift 6 language mode and targets iOS 26. Arasan's current source snapshot
is arm64-only, so do not treat
an x86_64 simulator build failure as an app regression.

## Setup & Required Assets
Stockfish NNUE weights are required to run the engine. Initialize the sibling
`StockfishEmbedded` checkout after clone:
```sh
(cd ../StockfishEmbedded && Scripts/download-nnue.sh)
```
Keep downloaded NNUE files out of commits.

## Build, Test, and Development Commands
- Xcode: open `SwiftChessDemo.xcodeproj` and run the `SwiftChessDemo` app target.
- CLI build: `xcodebuild -project SwiftChessDemo.xcodeproj -scheme SwiftChessDemo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`
- Comprehensive local validation: `Scripts/validate.sh`
- Targeted CLI tests: `xcodebuild -project SwiftChessDemo.xcodeproj -scheme SwiftChessDemo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcode-swiftchessdemo -clonedSourcePackagesDirPath .build/xcode-swiftchessdemo/SourcePackages test`
- Hosted headless checks: `Scripts/github-ci.sh`
- Optional manual GitHub Actions run: `Scripts/run-github-ci.sh [branch-or-tag]`

## Coding Style & Naming Conventions
- Use 4-space indentation and follow Swift API Design Guidelines.
- Prefer `Type+Feature.swift` for extensions (e.g., `SFEngine+Sendable.swift`).
- Keep the instructional comments; the project is intentionally annotated.
- Keep source file headers aligned with the MIT license for original
  SwiftChessDemo source. Do not add personal author headers.

## Licensing
SwiftChessDemo's original source code is MIT-licensed so it can be reused as
reference app code. The default app target links with `../StockfishEmbedded`,
which embeds GPL-licensed Stockfish code. Distribution of that combined
Stockfish-linked app must comply with GPLv3.

`../SwiftChessTools` and `ArasanEmbedded` remain MIT-licensed in their own
repos; using them here does not change those packages' licenses.
Dependency/license changes must preserve the distinction between MIT-licensed
demo source and GPL-covered Stockfish-linked distribution, and must update
`THIRD_PARTY.md`.

Repository releases are source-only. Do not add prebuilt app, framework,
library, or engine artifacts to a release or CI workflow; consumers build the
source dependencies locally.

## Testing Guidelines
- Treat `Scripts/validate.sh` as the expected local completion and release gate.
  It runs the app-hosted unit tests, generic iOS Release build checks, and the
  complete simulator UI-test target. Override the simulator when necessary with
  `SWIFT_CHESS_DEMO_SIMULATOR_DESTINATION`.
- GitHub Actions is optional, manual-only, and nonblocking. It does not run for
  pushes or pull requests. The workflow invokes `Scripts/github-ci.sh`, which
  deliberately skips simulator UI tests while retaining the app-hosted unit
  tests and Release build verification.
- `Scripts/run-github-ci.sh` dispatches only a branch or tag already published
  to GitHub. It does not commit or push. A missing or failed hosted run,
  including one GitHub cannot start because Actions credits are unavailable,
  is not evidence that the code failed local validation.
- Run the SwiftChessDemo tests after changing setup-screen, game-screen,
  scenario loading, scenario index validation, move-provider behavior, in-game
  piece-set selection, in-game board-theme selection, player-side setup, or
  move-flow behavior.
- The shared scheme includes app-hosted unit tests and UI tests. The unit tests
  cover scenario loading, scenario-index validation failures, deterministic
  move-provider behavior, game-view-model policy, and embedded-engine session
  ordering.
- The move-flow UI tests cover four full moves from both white and black
  perspectives. They launch named scenarios in `testDrivesWhite` or
  `testDrivesBlack` mode so engine-side moves are deterministic and not coupled
  to live engine startup time or best-move changes.
- `SWIFT_CHESS_DEMO_UI_TEST_ENGINE_MOVE_TIME_MS=250` keeps UI-test searches fast.
  `SWIFT_CHESS_DEMO_UI_TEST_ENGINE_REPLY_DELAY=1.0` can reduce the visible
  thinking pause for tests that still exercise live engine replies. Normal app
  launches should not set these flags and should default to Stockfish unless
  the player selects Arasan from the game screen.
- Scenario launches use `SWIFT_CHESS_DEMO_SCENARIO=<scenario-id>` and optional
  `SWIFT_CHESS_DEMO_SCENARIO_REPLAY_DELAY=<seconds>`. Scenario-index validation
  uses `SWIFT_CHESS_DEMO_VALIDATE_SCENARIO_INDEX=1`.
- If you change shared chess logic/UI, run `swift test` from `../SwiftChessTools`.
- If you change engine integration, build `../StockfishEmbedded` smoke targets.
  For Arasan-specific integration changes, run the package gate in the
  `../ArasanEmbedded` checkout if present.

## Commit & Pull Request Guidelines
- Use short, imperative commit summaries (e.g., "Document NNUE download steps", "Migrate to SwiftChessTools").
- PRs should describe behavior changes and list manual verification steps; include screenshots/GIFs for UI changes.
- Dependency changes must also update `THIRD_PARTY.md`.
