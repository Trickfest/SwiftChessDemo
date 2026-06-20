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
- Added a visible in-game status display backed by `ChessGameStatusView`.
- Added a visible in-game move list backed by `ChessMoveListView` and
  `ChessMoveRecord`.
- Added optional in-game evaluation display backed by `ChessEvaluationBar` and
  parsed Stockfish `info score` output.
- Added optional in-game move suggestion arrows backed by ChessUI
  `ChessBoardArrow` rendering and Stockfish MultiPV analysis.
- Added in-game display toggles for showing or hiding the status display and
  move list.
- Added an in-game display toggle for showing or hiding the evaluation bar.
- Added an in-game suggestions selector for showing zero, one, two, or three
  engine suggestion arrows.
- Added SwiftChessDemo UI tests that verify every bundled ChessUI piece set is
  selectable during a game.
- Added SwiftChessDemo UI tests that verify every bundled ChessUI board theme is
  selectable during a game.
- Added SwiftChessDemo UI coverage for the in-game coordinate-label toggle.
- Added SwiftChessDemo UI coverage for status display, move-list updates, and
  the new display toggles.
- Added SwiftChessDemo UI coverage for deterministic evaluation-bar rendering
  and toggling.
- Added SwiftChessDemo UI coverage for suggestion-arrow count selection,
  rendered arrow identifiers, and refresh after an opponent reply.
- Added PGN-backed scenario replay fixtures that can run deterministic game
  states without Stockfish.
- Added SwiftChessDemo UI coverage for scenario replay checkmate, terminal
  FEN-backed stalemate, and missing-scenario setup errors.
- Added SwiftChessDemo UI tests that exercise four full moves from both white
  and black perspectives using scenario-backed deterministic opponent replies.
- Added a broader PGN scenario corpus covering a longer opening line,
  promotion, insufficient material, castling, and en passant.
- Added a bundled scenario index and scenario-authoring guide for documenting
  deterministic replay fixtures.
- Added SwiftChessDemo UI coverage that validates the scenario index against
  bundled scenario JSON resources and PGN loading.
- Added app-hosted SwiftChessDemo unit tests for scenario loading, scenario
  index validation failures, and deterministic move-provider behavior.

### Changed

- Clarified SwiftChessDemo's GPL v3.0 license posture because the app links with
  Stockfish through `StockfishEmbedded`.
- Updated game-end handling to use ChessCore's `Game.status`,
  `Game.drawClaims`, and `Game.claimDraw(_:)` APIs for checkmate, stalemate,
  automatic draws, and claimable draw rules.
- Moved piece-set and board-theme selection off the launch screen and onto the
  game screen so display options can be reviewed without resigning.
- Moved the Stockfish depth control onto the game screen so the depth can be
  changed between searches during play.
- Added a short opponent "thinking" pause before requesting a Stockfish move, so
  the player's latest source/destination highlight remains visible before the
  engine reply updates the board.
- Changed claimable draw handling so claim buttons surface through
  `ChessGameStatusView` instead of being claimed automatically.
- Changed the compact game layout to show the move list as a horizontal strip
  above the board, while regular-width layouts keep the side-panel move list.
- Changed engine-output handling to use SwiftChessTools' `ChessUCI` parser for
  Stockfish `info` and `bestmove` lines instead of local string splitting.
- Changed engine-input handling to use SwiftChessTools' `ChessUCI` command
  formatter for Stockfish handshake, position, and search commands instead of
  hand-built UCI strings.
- Separated opponent-move searches from suggestion-analysis searches so
  analysis output can render arrows without applying a move.
- Raised the Stockfish depth control's maximum value from 16 to 30.
- Changed the in-game suggestions selector to filter cached three-line MultiPV
  analysis instead of changing the Stockfish MultiPV count for each visible
  arrow count.
- Isolated deterministic non-Stockfish moves behind a `GameMoveProvider`
  abstraction so scenario replay and scenario-backed UI tests do not live
  directly in `GameViewModel`.
- Replaced the temporary hard-coded UI-test move path with scenario-derived
  move controls and deterministic scenario suggestions.
- Moved embedded Stockfish lifecycle, serialized UCI search requests, timeouts,
  and cancelled suggestion-output handling into `StockfishMoveProvider`.

### Fixed

- Fixed suggestion-arrow engine analysis so changing suggestion counts and
  moving while analysis is active no longer starts overlapping embedded
  Stockfish instances.
- Preserved ChessCore move history and repetition state after animated board
  updates so draw status remains accurate while ChessUI renders from FEN.
- Corrected delayed engine-request cleanup so pending opponent replies are
  cancelled when the game view is dismissed or the engine is stopped.
