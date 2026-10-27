# Third-Party Dependencies

This repo no longer vendors chess dependencies directly. It expects
`SwiftChessTools` and `StockfishEmbedded` to be sibling checkouts next to
`SwiftChessDemo`, and it resolves `ArasanEmbedded` through Swift Package
Manager. The parent folder can be any local directory; it does not need to be a
Git repo.

SwiftChessDemo's original source code is licensed under the MIT License in
`LICENSE`. This keeps the demo useful as reference code for apps built with
SwiftChessTools.

The default app target links with `StockfishEmbedded`, which embeds
GPL-licensed Stockfish code. Distributing that combined Stockfish-linked app
requires GPLv3 compliance. A local copy of GPLv3 is retained at
`LICENSES/GPL-3.0.txt`; the authoritative dependency license is in the sibling
`../StockfishEmbedded/LICENSE`.

- SwiftChessTools
  - Path: `../SwiftChessTools`
  - Products: `ChessCore`, `ChessUI`, `ChessUCI`
  - Coordinated source release: `1.4.0`, required for timeline/navigation APIs.
  - License: MIT License in `../SwiftChessTools/LICENSE`
  - See `../SwiftChessTools/NOTICE.md` for upstream provenance and attribution.
- StockfishEmbedded
  - Upstream: https://github.com/Trickfest/StockfishEmbedded
  - Path: `../StockfishEmbedded`
  - Product: `SFEngine` (local Swift package)
  - Coordinated source release: `1.14.0`, embedding Stockfish upstream `effdc3fd`.
  - Runtime asset: the verified sibling NNUE file is copied into the app bundle
    and supplied to the engine by local file URL.
  - License: GNU General Public License v3.0 in `../StockfishEmbedded/LICENSE`
  - Includes Stockfish, distributed under the GNU General Public License v3.0.
  - Distribution of a binary linked with this dependency should include the
    GPLv3 license text and corresponding source information required by GPLv3.
- ArasanEmbedded
  - Upstream: https://github.com/Trickfest/ArasanEmbedded
  - Minimum release: `1.5.0`; resolved release: `1.5.0` at
    `56655d88ea76116c98e4527b652f41367842d0d0`, as recorded in Package.resolved.
    This embeds Arasan upstream `5d6be86c`.
  - Product: `ArasanEmbedded`
  - License: MIT License in the package's `LICENSE`
  - Includes selected Arasan engine source, distributed under Arasan's
    permissive license terms documented by that package.

Update by committing changes in the sibling dependency repo, then rebuild this
app. Do not reintroduce vendored subtree copies here.

## Maia integration development branch

This branch additionally expects the private `../MaiaEmbedded` checkout. It is
not part of the public 1.6.2 dependency baseline described above.

- Products: MaiaEmbedded and MaiaUCI, using Maia-3 79M FP32 through official ONNX Runtime 1.24.2.
- Package/model license: AGPL-3.0-only; retained copy in LICENSES/AGPL-3.0.txt.
- Original source/checkpoint/export identities and upstream notices:
  ../MaiaEmbedded/Docs/Provenance.md and ../MaiaEmbedded/THIRD_PARTY_NOTICES.md.
- ONNX Runtime uses MIT licensing; SwiftChessTools remains MIT. Preserve their notices.
- The downloaded model is copied from ../MaiaEmbedded/Resources/Models into the
  app bundle and remains ignored in both source repositories.

Original Demo source remains MIT. Any distribution of this combined branch's
app must account for the linked AGPL Maia package/model as well as Stockfish's
GPL license. No binary, release, public Maia source or App Store submission is
being published as part of this integration.
