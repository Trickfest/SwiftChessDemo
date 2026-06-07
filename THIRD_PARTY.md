# Third-Party Dependencies

This repo no longer vendors chess dependencies directly. It depends on sibling
checkouts in `/Users/markharris/src/chess-workspace`:

- SwiftChessTools
  - Path: `../SwiftChessTools`
  - Products: `ChessCore`, `ChessUI`
  - See `../SwiftChessTools/NOTICE.md` for upstream provenance and attribution.
- StockfishEmbedded
  - Upstream: https://github.com/Trickfest/StockfishEmbedded
  - Path: `../StockfishEmbedded`
  - Product: `SFEngine-iOS`
  - License: `../StockfishEmbedded/LICENSE`

Update by committing changes in the sibling dependency repo, then rebuild this
app. Do not reintroduce vendored subtree copies here.
