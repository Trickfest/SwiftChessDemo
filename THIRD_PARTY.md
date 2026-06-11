# Third-Party Dependencies

This repo no longer vendors chess dependencies directly. It depends on sibling
checkouts in `/Users/markharris/src/chess-workspace`:

SwiftChessDemo is licensed under the GNU General Public License v3.0 because the
app links with `StockfishEmbedded`, which embeds GPL-licensed Stockfish code.

- SwiftChessTools
  - Path: `../SwiftChessTools`
  - Products: `ChessCore`, `ChessUI`
  - License: MIT License in `../SwiftChessTools/LICENSE`
  - See `../SwiftChessTools/NOTICE.md` for upstream provenance and attribution.
- StockfishEmbedded
  - Upstream: https://github.com/Trickfest/StockfishEmbedded
  - Path: `../StockfishEmbedded`
  - Product: `SFEngine-iOS`
  - License: GNU General Public License v3.0 in `../StockfishEmbedded/LICENSE`
  - Includes Stockfish, distributed under the GNU General Public License v3.0.

Update by committing changes in the sibling dependency repo, then rebuild this
app. Do not reintroduce vendored subtree copies here.
