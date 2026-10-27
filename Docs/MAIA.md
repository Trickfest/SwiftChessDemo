# Maia integration

SwiftChessDemo 1.7 adds Maia as a third engine through public MaiaEmbedded 1.0.
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
move and its opponent; the same settings apply to both engine-demo colors.
Use Apply Maia settings during an idle/player turn or a paused engine demo,
including after a completed game. Play Again uses the updated settings; settings
remain locked while engine-demo play or analysis is active.
Slider edits are staged so dragging a control does not repeatedly reload the model.

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
completed-game settings changes and their use by Play Again,
both player colors, stale probability/evaluation events, separate score/move ownership,
shared lifecycle behavior and real Maia-versus-Stockfish/Arasan games with each
color assignment. Existing Stockfish and Arasan unit/integration cases still run.
Exact engine moves or strength are not asserted.

The package's native Mac and iPhone/iPad simulator reports are maintained in
[MaiaEmbedded Testing](https://github.com/Trickfest/MaiaEmbedded/blob/main/Docs/Testing.md). Physical iPhone API/UCI
checks and the short benchmark passed. The user reported normal scrolling/no
unusual warmth and working gameplay, settings, engine switching and
background/reset. After the bar-layout correction was installed, the user
confirmed: “Fixed; the board stays steady.” Final iPhone verification is complete
on this device. The iPad API/UCI checks and short benchmark also passed. The
corrected signed Demo was installed/launched there, and the user confirmed all
iPad checks passed, including gameplay/settings/suggestions, engine switching,
mixed-engine play, stable board/bar layout, rotation and background/reset. Final
verification is complete on the tested Mac, iPhone and iPad.

Final review also corrected settings eligibility after a completed engine-demo
game. A regression test reproduced the issue before the fix and verifies that
Play Again receives updated settings while active-play edits remain blocked.
All 106 non-UI tests and the unsigned iOS Release/asset gate passed afterward.
This final guard change was checked locally; the physical reports above describe
the preceding device-tested build. Native inference and engine ownership did not
change.

The reports above describe the original integration. Release packaging validation
and any new final-device checks are recorded separately; unattended UI automation
and App Store publication are outside this source-release gate.

## Source-release packaging

The 1.7.0 candidate resolves public MaiaEmbedded 1.0.0 at
`b5a84186513a962312f2f6bf0a03ab7d3c5c22ea`; existing local SwiftChessTools and
Stockfish dependencies remain. The full 106-test non-UI gate and unsigned iOS
Release/asset checks passed with that final dependency graph. A separate public
checkout layout, without a Maia sibling or personal signing, also built Release.
The signed device Release build is ready. All three app bundles report 1.7.0 and
contain the pinned model size/SHA-256. The signed 1.7.0 build installed and
launched on the physical iPhone 16 Pro Max; the user confirmed all final iPhone
checks passed, including Maia gameplay/settings/suggestions, mixed-engine layout,
reset and background/return. The same signed build installed and launched on
the physical iPad Pro 13-inch (M4); the user confirmed all final iPad checks
passed, including Maia play/settings/suggestions, engine switching, mixed-engine
layout, rotation, reset and background/return. These are direct user checks; no
UI-automation result is claimed. The earlier feedback above remains historical
integration evidence.

## Notices

Original Demo source remains MIT. The app additionally links AGPL-3.0-only
Maia code/model; see THIRD_PARTY.md and LICENSES/AGPL-3.0.txt, plus the package's
pinned provenance and retained upstream notices. Downloaded weights, build
products, personal signing data and device IDs must remain untracked.
