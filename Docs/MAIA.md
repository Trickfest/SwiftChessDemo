# Maia integration

SwiftChessDemo integrates Maia as a third engine through public MaiaEmbedded 1.0.
Existing SCT/Stockfish sibling paths and the published remote Arasan dependency
remain. SwiftPM resolves MaiaEmbedded/MaiaUCI from their public release.

## Setup and source organization

Run `Scripts/download-maia-model.sh` from the Demo repository. The project
copies its pinned, ignored `Resources/Models/maia3-79m.onnx` into the app bundle. MaiaMoveProvider
adapts MaiaUCI to EmbeddedEngineProviderSession, following the other provider
facades. MaiaSettings owns app controls; no app policy moves into the package.
The shared coordinator awaits Maia's asynchronous native cleanup before starting
a replacement transport. This avoids unnecessary simultaneous mobile model loads.
Stockfish/Arasan keep their existing process-stream ownership rules.

## Behavior

Select Maia for human play, either engine-demo color, or randomized stress mode.
The expandable settings control exposes self/opponent Lichess ratings, temperature,
TopP and optional recorded history. Ratings are relative to the current side to
move and its opponent. Human games have one settings group immediately below the
engine selector. Engine demos have independent White and Black settings below
their respective engine selectors; each side's opponent rating is its own model
input, not an automatic change to the other side's settings. The same loaded Maia
provider accepts each side's options before its move; a second model is unnecessary.
Settings stay visible but disabled/gray when their engine is not Maia. Move Time
also stays visible but is disabled for Maia, preserving the layout when switching.
Recorded history is enabled by default. Ratings and the history toggle apply
immediately; Temperature and Top P apply when the slider is released. Changes
cancel stale Maia analysis and refresh suggestions using the existing loaded
model. Independent Stockfish evaluation can finish without restarting.
Settings can change during an idle/player turn or a paused engine demo, including
after a completed game. Play Again uses the updated settings; settings remain
locked while an opponent move or engine-demo playback is active.

Requests carry the real game root and legal recorded moves so history mode and
draw state are reproducible. Browsing a historical board does not change the
live engine request. Candidate arrows use base human-move likelihood ranking;
the displayed percentages remain original probabilities. A sampled move can
differ from the highest-ranked candidate. Changing move time does not add Maia
search or change its strength.

Maia's UCI OutcomeScores option remains off. Stockfish supplies actual searched
evaluations for games involving Maia, using a separate 250 ms display-only search
after each engine-demo move and before Maia's player-turn suggestions. Maia
still selects its own moves and suggestions; the Stockfish evaluation bestmove
is never played. Mixed games use Stockfish scores consistently, including when
Arasan chooses a move. Searches finish before playback advances, with native
ownership serialized through the existing lifecycle coordinator.

The bar remains visible according to the user's Evaluation preference for all
move engines, retaining the last score while the next one is computed. Its space
therefore stays fixed as the engines alternate. No extra visible source label
is added; the source is available in accessibility descriptions and the existing
recorded-history metadata. Exact request/FEN/ply guards reject old scores after
moves, reset or engine switches. Hiding the bar cancels an evaluation and resumes
the appropriate game/analysis work; evaluation failure does not stall playback.
Policy text is shown for Maia suggestions, avoiding fleeting layout changes
from the move-producing policy stream.

## Local verification

```sh
SWIFT_CHESS_DEMO_SIMULATOR_DESTINATION='platform=iOS Simulator,name=AVAILABLE_IPHONE' Scripts/validate.sh --headless
```

This runs app-hosted unit/integration tests and the generic unsigned iOS Release
build, including exact Stockfish/Maia bundle checks. It does not run UI tests.
The normal `Scripts/validate.sh` retains the original complete UI gate for an
explicitly attended run. Hosted workflows remain optional/manual; this branch's
verified model must be provisioned explicitly by external builders.

Tests cover Maia legal/promotion/terminal recovery, ratings/history propagation,
independent White/Black settings, immediate edits without model teardown,
completed-game settings changes and their use by Play Again,
both player colors, stale probability/evaluation events, separate score/move ownership,
shared lifecycle behavior and real Maia-versus-Stockfish/Arasan games with each
color assignment. Existing Stockfish and Arasan unit/integration cases still run.
Exact engine moves or strength are not asserted.

The package's native inference and hardware validation are maintained in
[MaiaEmbedded Testing](https://github.com/Trickfest/MaiaEmbedded/blob/main/Docs/Testing.md).
For SwiftChessDemo 1.8.0, the 111-test non-UI gate and unsigned iOS Release/asset
checks passed. The signed feature build was installed and launched on the
physical iPhone 16 Pro Max and iPad Pro 13-inch (M4), and the user accepted the
revised UI before the release-version bump. No new automated UI or full physical
lifecycle test pass is claimed for this settings revision.

## Source-release packaging

SwiftChessDemo 1.8.0 resolves public MaiaEmbedded 1.0.0 at
`b5a84186513a962312f2f6bf0a03ab7d3c5c22ea`, ArasanEmbedded 1.5.0 and ONNX Runtime
1.24.2 through the committed lockfile. Use the matching SwiftChessTools 1.4.0 and
StockfishEmbedded 1.14.0 sibling source tags. Model provisioning remains explicit
and checksum-verified; no Maia sibling checkout is required.

Releases contain source only. Do not attach prebuilt apps, frameworks, engines,
or downloaded model weights. Personal signing stays in the ignored local
configuration. Hosted checks are optional/manual; App Store publication is a
separate action.

## Notices

Original Demo source remains MIT. The app additionally links AGPL-3.0-only
Maia code/model; see THIRD_PARTY.md and LICENSES/AGPL-3.0.txt, plus the package's
pinned provenance and retained upstream notices. Downloaded weights, build
products, personal signing data and device IDs must remain untracked.
