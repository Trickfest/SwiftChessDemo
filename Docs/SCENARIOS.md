# SwiftChessDemo Scenarios

SwiftChessDemo scenarios are deterministic game fixtures used by unit tests,
UI tests, manual simulator runs, and reference-app demonstrations. Each
scenario uses one JSON definition and one PGN source file. The app parses PGN
at runtime; no generated move-list artifact is checked in.

This catalog belongs to the demo app's test and demonstration harness. It is
not a SwiftChessTools API. ChessCore provides the reusable PGN parsing and move
validation.

## Files

- `SwiftChessDemo/Scenarios/index.json` catalogs every scenario.
- `<scenario-id>.json` declares one scenario's metadata and playback behavior.
- `<game>.pgn` supplies the starting position and moves. Multiple scenarios may
  share one PGN when they use different playback modes or stop plies.

## Scenario JSON

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

- `id`: Stable launch/test identifier matching the JSON filename.
- `title`: Human-readable setup-screen label.
- `pgnResource`: PGN filename in `SwiftChessDemo/Scenarios`.
- `playbackMode`: `automaticReplay`, `testDrivesWhite`, or `testDrivesBlack`.

Optional fields:

- `initialPerspective`: `white` or `black`. Test-driven scenarios default to
  the driven side; automatic scenarios default to White.
- `stopAfterPly`: Number of plies to replay. Use `0` for a FEN-only terminal
  scenario. Omitting it uses the full PGN.
- `expectedStatus`: Documentation/test metadata such as `ongoing`, `draw`, or
  `checkmate`.
- `expectedWinner`: `white` or `black` for decisive terminal scenarios.
- `notes`: Maintainer-facing intent.

## Playback Modes

- `automaticReplay`: The scenario supplies both sides; the board is read-only
  and no live engine starts.
- `testDrivesWhite`: UI tests drive White and the scenario supplies Black
  replies plus deterministic White suggestions.
- `testDrivesBlack`: UI tests drive Black and the scenario supplies White moves
  plus deterministic Black suggestions.

## PGN And Index Expectations

Use one main line without variations. Comments are acceptable only when
ChessCore's PGN parser accepts them. Prefer FEN-backed PGNs for promotion,
stalemate, insufficient material, and other focused positions.

Every scenario JSON file must have a matching `index.json` entry sorted by
`id`. The index repeats `id`, `title`, `pgnResource`, `playbackMode`,
`stopAfterPly`, `expectedStatus`, and `expectedWinner` so tests can catch drift.
It also adds `tags` and a one-sentence `purpose`.

## Creating A Scenario

1. Add or choose a single-main-line PGN under `SwiftChessDemo/Scenarios`.
2. Add `<scenario-id>.json` with the required fields and useful metadata.
3. Add a matching `index.json` entry in sorted order.
4. Add or update coverage when the scenario protects specific behavior.
5. Run `Scripts/validate.sh` from the repository root. Unit tests validate
   loading, provider behavior, complete index membership, metadata parity, and
   bundled PGN parsing; the command also runs the local UI suite and Release
   build checks.

The current corpus covers White- and Black-driven smoke flows, deterministic
suggestions, Fool's Mate, a longer Ruy Lopez line, promotion, castling, en
passant, insufficient material, and stalemate.

## Manual Launch

The app reads `SWIFT_CHESS_DEMO_SCENARIO` as the scenario ID and
`SWIFT_CHESS_DEMO_SCENARIO_REPLAY_DELAY` as a nonnegative replay delay. When
launching through `simctl`, use its `SIMCTL_CHILD_` prefix to forward those
variables into the app process:

```sh
SIMCTL_CHILD_SWIFT_CHESS_DEMO_SCENARIO=fools-mate \
SIMCTL_CHILD_SWIFT_CHESS_DEMO_SCENARIO_REPLAY_DELAY=1.2 \
xcrun simctl launch --terminate-running-process <simulator-udid> trickfest.SwiftChessDemo
```

Set `SWIFT_CHESS_DEMO_VALIDATE_SCENARIO_INDEX=1` to make the setup screen report
whether the index and bundled scenario resources agree. Prefix that name with
`SIMCTL_CHILD_` as well when launching through `simctl`.
