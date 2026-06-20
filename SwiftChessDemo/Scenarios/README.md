# SwiftChessDemo Scenarios

SwiftChessDemo scenarios are deterministic game fixtures used by unit tests, UI
tests, manual simulator runs, and reference-app demonstrations. A scenario is
defined by one JSON file plus one PGN file. The app parses the PGN at runtime
and keeps the normalized move list in memory; no generated move-list artifact is
checked in.

The scenario system is part of the demo app's test and demonstration harness.
It is not a SwiftChessTools API. The reusable piece is `ChessCore` PGN parsing
and move validation; the scenario catalog and replay provider are app code.

## Files

- `index.json` catalogs every scenario in this folder. It is the durable list
  for documentation, tests, and future UI affordances such as a scenario picker.
- `<scenario-id>.json` declares one scenario's metadata and playback behavior.
- `<game>.pgn` supplies the source position and moves. Multiple scenarios may
  point at the same PGN when they use different playback modes or stop plies.

## Scenario JSON

Scenario files use this shape:

```json
{
  "id": "white-four-move-smoke",
  "title": "White Four-Move Smoke",
  "pgnResource": "four-move-smoke.pgn",
  "playbackMode": "testDrivesWhite",
  "initialPerspective": "white",
  "stopAfterPly": 8,
  "expectedStatus": "ongoing",
  "notes": "Maintainer-facing notes."
}
```

Required fields:

- `id`: Stable launch/test identifier. It must match the JSON filename without
  `.json`.
- `title`: Human-readable label shown on the setup screen when the scenario is
  launched.
- `pgnResource`: PGN file in this folder. Include `.pgn`.
- `playbackMode`: One of `automaticReplay`, `testDrivesWhite`, or
  `testDrivesBlack`.

Optional fields:

- `initialPerspective`: `white` or `black`. If omitted, test-driven scenarios
  use the test-driven side and automatic scenarios default to White.
- `stopAfterPly`: Number of plies to replay before stopping. Use `0` for
  FEN-only terminal scenarios. If omitted, replay uses the full PGN.
- `expectedStatus`: Documentation and test metadata such as `ongoing`, `draw`,
  or `checkmate`.
- `expectedWinner`: `white` or `black` for decisive terminal scenarios.
- `notes`: Freeform maintainer note explaining intent.

## Playback Modes

- `automaticReplay`: The scenario supplies both sides. The game screen is
  read-only and no Stockfish search starts.
- `testDrivesWhite`: UI tests drive White through test-only buttons. The
  scenario supplies Black replies and deterministic White suggestion arrows.
- `testDrivesBlack`: UI tests drive Black through test-only buttons. The
  scenario supplies White moves and deterministic Black suggestion arrows.

## PGN Expectations

Use a single main line. Do not include variations. Comments are acceptable only
when `ChessCore.PGNSerializer` can parse them. FEN-backed PGNs are preferred for
edge cases such as stalemate, insufficient material, promotion, and special
endgame positions.

The PGN is the readable source of truth. SwiftChessDemo validates it on launch
and derives concrete `ChessCore.Move` values from it. If a PGN cannot be parsed
or a listed move is illegal for the current position, scenario loading fails.

## Index Entries

Every scenario JSON file must have a matching `index.json` entry, sorted by
`id`. The index duplicates selected metadata from the scenario file so tests can
catch drift:

- `id`
- `title`
- `pgnResource`
- `playbackMode`
- `stopAfterPly`
- `expectedStatus`
- `expectedWinner`

Index-only fields:

- `tags`: Short labels such as `ui-test`, `terminal`, `fen-start`, `promotion`,
  or `automatic-replay`.
- `purpose`: One sentence explaining why this scenario exists.

## Creating A Scenario

1. Add or choose a PGN file in `SwiftChessDemo/Scenarios`.
2. Keep the PGN to a single main line. For edge cases, include FEN setup tags.
3. Add `<scenario-id>.json` with the required fields and any useful optional
   metadata.
4. Add a matching entry to `index.json`, keeping entries sorted by `id`.
5. Add or update unit or UI coverage when the scenario protects a specific
   behavior.
6. Run the SwiftChessDemo automated tests. The unit tests validate scenario
   loading and move-provider behavior. The scenario-index tests validate that
   every indexed scenario exists, every scenario JSON is indexed, metadata
   matches, and PGNs load through the app bundle.

The current corpus covers:

- white-driven and black-driven four-move smoke flows
- deterministic suggestion-arrow lines
- Fool's Mate checkmate
- a longer Ruy Lopez opening replay
- promotion from a FEN-backed position
- castling and en passant
- FEN-backed insufficient-material and stalemate terminal positions

## Manual Launch

Launch a scenario by setting `SWIFT_CHESS_DEMO_SCENARIO` to the scenario id. To
watch automatic replay more slowly, set `SWIFT_CHESS_DEMO_SCENARIO_REPLAY_DELAY`
to a positive number of seconds.

Example:

```sh
SWIFT_CHESS_DEMO_SCENARIO=fools-mate \
SWIFT_CHESS_DEMO_SCENARIO_REPLAY_DELAY=1.2 \
xcrun simctl launch --terminate-running-process <simulator-udid> trickfest.SwiftChessDemo
```

Validate the bundled scenario index through the app by launching with
`SWIFT_CHESS_DEMO_VALIDATE_SCENARIO_INDEX=1`. The setup screen reports whether
the index and bundled scenario resources agree.
