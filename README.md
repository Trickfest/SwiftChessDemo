# SwiftChessDemo

SwiftChessDemo is a demo app that demonstrates how to combine local chess
libraries into a realistic, shippable SwiftUI chess experience.
The code is intentionally small, readable, and heavily commented so you can
trace how each module contributes to the final behavior.

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
- When it is the engine's turn, the current FEN is sent to Stockfish.
- Stockfish returns `bestmove`, which is converted to a `ChessCore.Move`.

Key files to read:
- `SwiftChessDemo/ContentView.swift`: configuration UI for side and engine depth.
- `SwiftChessDemo/GameView.swift`: board UI, live piece-set and board-theme
  switching during play, and navigation flow.
- `SwiftChessDemo/GameViewModel.swift`: rules, display state, engine, and endgame
  logic.
- `SwiftChessDemoUITests/SwiftChessDemoUITests.swift`: UI coverage for available
  in-game piece-set and board-theme selection.

Local dependencies:
- `../SwiftChessTools`: local Swift package products `ChessCore` and `ChessUI`.
- `../StockfishEmbedded`: local Xcode project dependency for `SFEngine-iOS`.
- Reference details live in `THIRD_PARTY.md`.
