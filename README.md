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
  themes used by the in-game display selectors.
- `ChessCore` owns the rules engine, legal move generation, and game state.
- The sibling `../StockfishEmbedded` project supplies engine moves over the UCI protocol via `SFEngine`.

Data flow at a glance:
- User moves on the board -> `ChessUI` -> `GameViewModel.handleUserMove`.
- The move is validated/applied in `ChessCore`, then serialized to FEN.
- FEN is pushed back into `ChessUI` to update the board UI.
- Terminal game state and claimable draws are read from ChessCore's
  `Game.status` and draw-claim APIs.
- When it is the engine's turn, the current FEN is sent to Stockfish.
- Stockfish returns `bestmove`, which is converted to a `ChessCore.Move`.

Key files to read:
- `SwiftChessDemo/ContentView.swift`: configuration UI for side and engine depth.
- `SwiftChessDemo/GameView.swift`: board UI, live piece-set and board-theme
  switching during play, and navigation flow.
- `SwiftChessDemo/GameViewModel.swift`: display state, engine coordination, safe
  move application, and ChessCore game-status integration.
- `SwiftChessDemoUITests/SwiftChessDemoUITests.swift`: UI coverage for available
  in-game piece-set selection, board-theme selection, and four-full-move game
  flows from both white and black perspectives.

Automated UI tests:
- Run the suite with `xcodebuild -project SwiftChessDemo.xcodeproj -scheme SwiftChessDemo -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath .build/xcode-swiftchessdemo -clonedSourcePackagesDirPath .build/xcode-swiftchessdemo/SourcePackages test`.
- The game-flow UI tests set `SWIFT_CHESS_DEMO_UI_TEST_SCRIPTED_ENGINE=1` so
  opponent replies are deterministic instead of coming from Stockfish.
- The same tests also set `SWIFT_CHESS_DEMO_UI_TEST_ENGINE_DEPTH=1` and
  `SWIFT_CHESS_DEMO_UI_TEST_ENGINE_REPLY_DELAY=1.0` to keep simulator runs
  fast. Normal app launches do not set these flags and continue to use
  Stockfish for engine moves.

Local dependencies:
- `../SwiftChessTools`: local Swift package products `ChessCore` and `ChessUI`.
- `../StockfishEmbedded`: local Xcode project dependency for `SFEngine-iOS`.
- Reference details live in `THIRD_PARTY.md`.
