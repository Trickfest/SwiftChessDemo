# Changelog

All notable changes to SwiftChessDemo should be documented in this file.

Entries stay under `Unreleased` until the repo is tagged or otherwise prepared
for a release. Tagged releases use dated version headings.

## Unreleased

### Added

- Added an Engine vs Engine game mode that starts paused and lets the user run
  Stockfish and Arasan against each other.
- Added Engine vs Engine playback controls for Play/Pause, one-move Step, and
  post-move pacing.
- Added per-side engine and move-time configuration for Engine vs Engine games.
- Added optional Engine vs Engine stress controls that can randomize engine
  selection and/or move time before each move.

### Changed

- Kept Engine vs Engine board input read-only while applying generated moves
  through the same ChessCore-backed move path used by normal gameplay.
- Hid normal human-game engine, move-time, and suggestion controls in Engine vs
  Engine mode so demo-only controls own engine selection.
- Changed live engine searches from fixed-depth UCI requests to UCI `movetime`
  requests and derived the app-side safety timeout from the selected move time.
- Changed Engine vs Engine games to automatically claim threefold-repetition
  and 50-move draw claims while leaving human-vs-engine draw claims manual.
- Changed Engine vs Engine board updates to use instant move feedback so
  CPU-heavy searches cannot leave a temporary piece animation visible while the
  next engine thinks.
- Changed new games to start with the Sashite Merida piece set on the Classic
  Green board theme.

### Fixed

- Added view-model coverage for Engine vs Engine pause, step, side-specific
  engine/move-time alternation, safety-timeout propagation, automatic draw
  claiming, and seeded stress randomization across ten ply.
- Added UI coverage that verifies Engine vs Engine starts paused with
  demo-only playback controls visible.

## 1.0.4 - 2026-06-30

### Added

- Added `ArasanEmbedded` as a second live engine option alongside Stockfish.
- Added an in-game engine picker for live games so future searches and
  suggestion analysis can use either Stockfish or Arasan.

### Changed

- Generalized live engine request handling so Stockfish and Arasan share the
  same serialized search, timeout, evaluation, and suggestion-arrow flow.
- Refreshed live evaluation and suggestion analysis when the selected engine or
  search depth changes, avoiding stale analysis after switching engines.
- Preserved the previous evaluation while selected-engine analysis refreshes so
  the evaluation bar does not snap to neutral while the replacement search is in
  flight.
- Updated the Arasan engine dependency to `ArasanEmbedded` 1.0.3 so Arasan
  evaluation output reflects material imbalances correctly on Apple Silicon and
  engine shutdown/restart is safe during active searches and engine switches.

### Fixed

- Added Demo integration coverage that verifies Arasan reports a queen-sized
  material advantage through both suggestion and evaluation-only UCI parsing
  paths.
- Added view-model coverage for stale engine and stale depth output after
  engine/depth changes.
- Added view-model regression coverage that plays ten ply while switching
  between Stockfish and Arasan after every engine reply.

## 1.0.3 - 2026-06-22

### Changed

- Delegated Stockfish NNUE setup to the sibling `StockfishEmbedded` checkout so
  SwiftChessDemo no longer duplicates the engine network filename in setup
  docs or CI.
- Updated GitHub Actions checkout usage to `actions/checkout@v7`.

## 1.0.2 - 2026-06-21

### Fixed

- Replaced the README iPhone screenshot with a normal gameplay capture that
  does not show UI-test diagnostics.

## 1.0.1 - 2026-06-21

### Added

- Added iPad and iPhone gameplay screenshots to the README so the public repo
  shows the reference app's regular-width and compact layouts.

### Fixed

- Removed an Xcode warning from scenario-index validation by making an
  immutable local value explicit.

## 1.0.0 - 2026-06-20

Initial public release.

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
- Added visible in-game engine activity and brief recoverable timeout feedback
  in the existing status row.
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
- Added GitHub Actions CI that checks out the public sibling dependencies,
  downloads the required Stockfish NNUE file, and runs the app-hosted unit
  tests.

### Changed

- Changed SwiftChessDemo's original source license to MIT while documenting
  GPLv3 compliance requirements for the default app distribution that links
  Stockfish through `StockfishEmbedded`.
- Updated game-end handling to use ChessCore's `Game.status`,
  `Game.drawClaims`, and `Game.claimDraw(_:)` APIs for checkmate, stalemate,
  automatic draws, and claimable draw rules.
- Moved piece-set and board-theme selection off the launch screen and onto the
  game screen so display options can be reviewed without resigning.
- Moved the Stockfish depth control onto the game screen so the depth can be
  changed between searches during play.
- Added a visible opponent "thinking" state in the existing game-status row, so
  engine activity does not add a second status box or shift the board layout.
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
- Changed Stockfish replies to start searching immediately while preserving a
  minimum visible thinking interval before fast replies are applied.
- Reduced the normal visible engine thinking minimum from 2.5 seconds to 1.0
  second.
- Changed Stockfish timeout handling to request `bestmove` with `stop` and play
  the best move found so far when available instead of ending the game.
- Changed transient engine notices to clear automatically so the status row
  returns to the normal game status after a short interval.
- Renamed the in-game display-options section to `Preferences` and moved the
  native depth stepper to the bottom of that section.
- Clarified reference-app documentation for SwiftChessTools integration,
  scenario authoring, automated tests, and app-owned engine/scenario boundaries.
- Isolated deterministic non-Stockfish moves behind a `GameMoveProvider`
  abstraction so scenario replay and scenario-backed UI tests do not live
  directly in `GameViewModel`.
- Replaced the temporary hard-coded UI-test move path with scenario-derived
  move controls and deterministic scenario suggestions.
- Moved embedded Stockfish lifecycle, serialized UCI search requests, timeouts,
  and cancelled suggestion-output handling into `StockfishMoveProvider`.
- Clarified public setup documentation so SwiftChessDemo can be cloned with
  public sibling checkouts without requiring any parent workspace repo.
- Clarified automated-test documentation so hosted GitHub Actions runs the
  fast app-hosted unit tests while the full simulator UI suite remains the
  local release gate.

### Fixed

- Fixed GitHub Actions simulator selection by pinning CI to the macOS 26 runner
  and letting Xcode resolve the latest iPhone 17 Pro simulator instead of
  reusing a stale `simctl` UDID.
- Hardened scenario-backed UI smoke tests so Black-side startup works whether
  the opening scripted move is still pending or has already reached the board.
- Fixed suggestion-arrow engine analysis so changing suggestion counts and
  moving while analysis is active no longer starts overlapping embedded
  Stockfish instances.
- Preserved ChessCore move history and repetition state after animated board
  updates so draw status remains accurate while ChessUI renders from FEN.
- Corrected delayed engine-request cleanup so pending opponent replies are
  cancelled when the game view is dismissed or the engine is stopped.
