# Changelog

All notable changes to SwiftChessDemo should be documented in this file.

Entries stay under `Unreleased` until the repo is tagged or otherwise prepared
for a release.

## Unreleased

### Added

- Added visible in-game chess piece set selectors backed by
  `ChessPieceSet.availableSets`, defaulting the demo to Art Deco Monochrome.
- Added visible in-game board theme selectors backed by
  `ChessBoardTheme.availableThemes`, defaulting the demo to Art Deco Monochrome.
- Added an in-game `Coordinates` switch for showing or hiding ChessUI rank and
  file coordinate labels.
- Added SwiftChessDemo UI tests that verify every bundled ChessUI piece set is
  selectable during a game.
- Added SwiftChessDemo UI tests that verify every bundled ChessUI board theme is
  selectable during a game.
- Added SwiftChessDemo UI coverage for the in-game coordinate-label toggle.
- Added SwiftChessDemo UI tests that exercise four full moves from both white
  and black perspectives, using a test-only scripted engine path for
  deterministic opponent replies.

### Changed

- Clarified SwiftChessDemo's GPL v3.0 license posture because the app links with
  Stockfish through `StockfishEmbedded`.
- Updated game-end handling to use ChessCore's `Game.status`,
  `Game.drawClaims`, and `Game.claimDraw(_:)` APIs for checkmate, stalemate,
  automatic draws, and claimable draw rules.
- Moved piece-set and board-theme selection off the launch screen and onto the
  game screen so display options can be reviewed without resigning.
- Added a short opponent "thinking" pause before requesting a Stockfish move, so
  the player's latest source/destination highlight remains visible before the
  engine reply updates the board.

### Fixed

- Preserved ChessCore move history and repetition state after animated board
  updates so draw status remains accurate while ChessUI renders from FEN.
- Corrected delayed engine-request cleanup so pending opponent replies are
  cancelled when the game view is dismissed or the engine is stopped.
