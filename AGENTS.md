# Repository Guidelines

## Project Structure & Module Organization
- `SwiftChessDemo/`: SwiftUI app entry point, views, and view models.
- `../SwiftChessTools/`: sibling Swift package dependency that provides
  `ChessCore`, `ChessUI`, and `ChessUCI` command/parser helpers.
- `../StockfishEmbedded/`: sibling Xcode project dependency that provides `SFEngine-iOS`.
- `SwiftChessDemo.xcodeproj/`: Xcode project; assets live in `SwiftChessDemo/Assets.xcassets`.

Public and local development both expect `SwiftChessDemo`, `SwiftChessTools`,
and `StockfishEmbedded` to be sibling checkouts under any parent directory. The
parent folder does not need to be a Git repo.

## Setup & Required Assets
Stockfish NNUE weights are required to run the engine. Initialize the sibling
`StockfishEmbedded` checkout after clone:
```sh
(cd ../StockfishEmbedded && Scripts/download-nnue.sh)
```
Keep downloaded NNUE files out of commits.

## Build, Test, and Development Commands
- Xcode: open `SwiftChessDemo.xcodeproj` and run the `SwiftChessDemo` app target.
- CLI build: `xcodebuild -project SwiftChessDemo.xcodeproj -scheme SwiftChessDemo -configuration Debug build`
- CLI tests: `xcodebuild -project SwiftChessDemo.xcodeproj -scheme SwiftChessDemo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcode-swiftchessdemo -clonedSourcePackagesDirPath .build/xcode-swiftchessdemo/SourcePackages test`

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

`../SwiftChessTools` remains MIT-licensed in its own repo; using it here does
not change that package's license. Dependency/license changes must preserve the
distinction between MIT-licensed demo source and GPL-covered Stockfish-linked
distribution, and must update `THIRD_PARTY.md`.

## Testing Guidelines
- Run the SwiftChessDemo tests after changing setup-screen, game-screen,
  scenario loading, scenario index validation, move-provider behavior, in-game
  piece-set selection, in-game board-theme selection, player-side setup, or
  move-flow behavior.
- The shared scheme includes app-hosted unit tests and UI tests. The unit tests
  cover scenario loading, scenario-index validation failures, and deterministic
  move-provider behavior.
- The move-flow UI tests cover four full moves from both white and black
  perspectives. They launch named scenarios in `testDrivesWhite` or
  `testDrivesBlack` mode so engine-side moves are deterministic and not coupled
  to Stockfish startup time or best-move changes.
- `SWIFT_CHESS_DEMO_UI_TEST_ENGINE_DEPTH=1` keeps UI-test searches fast.
  `SWIFT_CHESS_DEMO_UI_TEST_ENGINE_REPLY_DELAY=1.0` can reduce the visible
  thinking pause for tests that still exercise live Stockfish replies. Normal
  app launches should not set these flags and should continue to exercise
  Stockfish.
- Scenario launches use `SWIFT_CHESS_DEMO_SCENARIO=<scenario-id>` and optional
  `SWIFT_CHESS_DEMO_SCENARIO_REPLAY_DELAY=<seconds>`. Scenario-index validation
  uses `SWIFT_CHESS_DEMO_VALIDATE_SCENARIO_INDEX=1`.
- If you change shared chess logic/UI, run `swift test` from `../SwiftChessTools`.
- If you change engine integration, build `../StockfishEmbedded` smoke targets.

## Commit & Pull Request Guidelines
- Use short, imperative commit summaries (e.g., "Document NNUE download steps", "Migrate to SwiftChessTools").
- PRs should describe behavior changes and list manual verification steps; include screenshots/GIFs for UI changes.
- Dependency changes must also update `THIRD_PARTY.md`.
