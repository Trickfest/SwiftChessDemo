# SwiftChessDemo

SwiftChessDemo is a demo app that demonstrates how to combine local chess
libraries into a realistic, shippable SwiftUI chess experience.
The code is intentionally small, readable, and heavily commented so you can
trace how each module contributes to the final behavior.

Licensing note: SwiftChessDemo is licensed under the GNU General Public License
v3.0 because the app links with Stockfish through `../StockfishEmbedded`.
`../SwiftChessTools` remains MIT-licensed in its own repo, but this app's
distributed binary should be treated as a GPL-covered combined work. See
`LICENSE` and `THIRD_PARTY.md` for details.

Required after clone: make sure the sibling `../StockfishEmbedded` checkout has
the required NNUE weights (Stockfish neural nets). These files are not in Git
because they are large, but they are required to run the engine.
```
mkdir -p ../StockfishEmbedded/Resources/NNUE
curl -L --fail https://tests.stockfishchess.org/api/nn/nn-83a0d6daf7e5.nnue -o ../StockfishEmbedded/Resources/NNUE/nn-83a0d6daf7e5.nnue
```

How it all fits together:
- `ChessUI` renders the board UI and emits user move gestures.
- `ChessUI` also supplies runtime lists of bundled chess piece sets and board
  themes used by the in-game display selectors, plus coordinate-label
  visibility for the in-game `Coordinates` switch.
- The game screen uses `ChessGameStatusView` for visible turn/status display
  and draw-claim actions.
- The game screen uses `ChessMoveListView` with `ChessCore` move records to
  show SAN move history as the game progresses.
- The game screen uses `ChessEvaluationBar` for optional evaluation display.
- The game screen can show zero, one, two, or three app-supplied
  `ChessBoardArrow` move suggestions from Stockfish MultiPV analysis.
- `ChessCore` owns the rules engine, legal move generation, and game state.
- `ChessUCI` formats Stockfish command strings and parses `info` and
  `bestmove` lines into typed values.
- The sibling `../StockfishEmbedded` project supplies engine moves over the UCI protocol via `SFEngine`.

Data flow at a glance:
- User moves on the board -> `ChessUI` -> `GameViewModel.handleUserMove`.
- The move is validated/applied in `ChessCore`, then serialized to FEN.
- FEN is pushed back into `ChessUI` to update the board UI.
- Terminal game state and claimable draws are read from ChessCore's
  `Game.status` and draw-claim APIs, then rendered with `ChessGameStatusView`.
- Legal moves are also captured as `ChessMoveRecord` values before they are
  applied, so `ChessMoveListView` can render SAN without owning the game.
- When it is the engine's turn, `StockfishMoveProvider` uses `ChessUCI` to
  format the UCI handshake, `position`, and `go` command strings sent to
  Stockfish.
- Stockfish streams `info` lines through `StockfishMoveProvider`, where
  `ChessUCI` parses them into White-positive evaluation values for
  `ChessEvaluationBar`.
- When suggestions are enabled, SwiftChessDemo asks Stockfish for up to three
  MultiPV analysis lines on the human player's turn, caches the ranked first
  moves, and filters the visible ChessUI arrows according to the user's
  suggestion-count picker. ChessUI renders the arrows but does not decide which
  moves to suggest.
- Stockfish returns `bestmove`; `ChessUCI` parses it into a `ChessCore.Move`.
- Scenario replay uses a named JSON scenario plus a bundled PGN fixture. The
  PGN is parsed through `ChessCore.PGNSerializer`, concrete moves are held in
  memory, and the same move-application path updates the board, move list, and
  status UI without starting Stockfish.

Key files to read:
- `SwiftChessDemo/ContentView.swift`: configuration UI for choosing the human side.
- `SwiftChessDemo/GameView.swift`: board UI, live piece-set, board-theme, and
  coordinate-label switching during play, visible ChessUI status and move-list
  components, optional evaluation-bar display, in-game engine-depth control,
  selectable move-suggestion arrows, compact horizontal move-list layout on
  iPhone, and navigation flow.
- `SwiftChessDemo/GameViewModel.swift`: display state, safe move application,
  provider event handling, evaluation normalization, Stockfish MultiPV
  suggestion mapping, and ChessCore game-status integration.
- `SwiftChessDemo/StockfishMoveProvider.swift`: embedded Stockfish lifecycle,
  serialized search requests, UCI command formatting/parsing, timeouts, and
  cancelled suggestion-output handling.
- `SwiftChessDemo/GameScenario.swift`: scenario-file loading and PGN validation
  for deterministic replay fixtures.
- `SwiftChessDemo/GameScenarioIndex.swift`: bundled scenario catalog loading and
  validation used to catch scenario-resource drift.
- `SwiftChessDemo/GameMoveProvider.swift`: deterministic move-provider
  abstraction used by scenario replay and scenario-backed UI tests.
- `SwiftChessDemo/Scenarios/`: checked-in scenario index, authoring guide, JSON
  definitions, and PGN fixtures.
- `SwiftChessDemoTests/GameScenarioUnitTests.swift`: fast unit coverage for
  scenario loading, index validation, and deterministic move-provider behavior.
- `SwiftChessDemoUITests/SwiftChessDemoUITests.swift`: UI coverage for available
  in-game piece-set selection, board-theme selection, coordinate-label toggling,
  status, move-list, evaluation display options, selectable suggestion arrows,
  scenario replay, and four-full-move game flows from both white and black
  perspectives.

Automated tests:
- Run the suite with `xcodebuild -project SwiftChessDemo.xcodeproj -scheme SwiftChessDemo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcode-swiftchessdemo -clonedSourcePackagesDirPath .build/xcode-swiftchessdemo/SourcePackages test`.
- The shared scheme includes both fast scenario unit tests and full UI tests.
  The unit tests run inside the demo app host so `Bundle.main` loads the same
  bundled scenarios the app uses at runtime.
- Scenario replay tests set `SWIFT_CHESS_DEMO_SCENARIO=<scenario-id>` and
  optionally `SWIFT_CHESS_DEMO_SCENARIO_REPLAY_DELAY=0`. Each scenario id maps
  to a JSON file in `SwiftChessDemo/Scenarios`; the JSON points at the PGN
  fixture that supplies the validated move list.
- The game-flow UI tests run named scenarios in `testDrivesWhite` or
  `testDrivesBlack` mode so one side is driven by UI-test taps while the
  scenario supplies the opposing replies. This keeps move-flow coverage
  deterministic without starting Stockfish.
- The game-flow tests set `SWIFT_CHESS_DEMO_UI_TEST_ENGINE_DEPTH=1` to keep
  simulator runs fast. UI tests that exercise live engine replies can also set
  `SWIFT_CHESS_DEMO_UI_TEST_ENGINE_REPLY_DELAY=1.0` to reduce the visible
  thinking pause. Normal app launches do not set these flags and continue to
  use Stockfish for engine moves.
- Evaluation-bar UI coverage can set `SWIFT_CHESS_DEMO_UI_TEST_EVALUATION`
  values such as `cp:85`, `mate:white:3`, or `mate:black:2` so the visual state
  is deterministic without live Stockfish analysis.
- Suggestion-arrow UI coverage uses scenario-backed move suggestions plus
  optional `SWIFT_CHESS_DEMO_UI_TEST_SUGGESTION_ARROW_COUNT` values from `0`
  through `3` so rendered arrows are deterministic without live Stockfish
  analysis.
- Scenario-index coverage sets `SWIFT_CHESS_DEMO_VALIDATE_SCENARIO_INDEX=1` so
  the app validates `Scenarios/index.json`, bundled scenario JSON files, and
  PGN loading through the same bundle path used at runtime.

Scenario files:
- `SwiftChessDemo/Scenarios/index.json` is the durable scenario catalog. It
  lists every scenario id, tags, purpose, selected metadata, and the PGN
  resource each scenario uses.
- Scenario JSON is the per-scenario test description: id, title, PGN resource,
  playback mode, optional perspective, optional stop ply, and expected-status
  notes.
- PGN remains the readable source of moves. SwiftChessDemo does not check in a
  normalized move-list artifact; it parses and validates the PGN on launch.
- Supported playback modes are:
  - `automaticReplay`: replay both sides without user input or Stockfish.
  - `testDrivesWhite`: expose test-only buttons for White moves and let the
    scenario provide Black replies.
  - `testDrivesBlack`: expose test-only buttons for Black moves and let the
    scenario provide White replies.
- See `SwiftChessDemo/Scenarios/README.md` for scenario authoring steps,
  index-field expectations, and the manual launch environment variables.

Local dependencies:
- `../SwiftChessTools`: local Swift package products `ChessCore`, `ChessUI`,
  and `ChessUCI`.
- `../StockfishEmbedded`: local Xcode project dependency for `SFEngine-iOS`.
- Reference details live in `THIRD_PARTY.md`.
