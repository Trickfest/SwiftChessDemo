# Third-Party Dependencies

This repo no longer vendors chess dependencies directly. It depends on sibling
checkouts in `/Users/markharris/src/chess-workspace`:

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
  - License: MIT License in `../SwiftChessTools/LICENSE`
  - See `../SwiftChessTools/NOTICE.md` for upstream provenance and attribution.
- StockfishEmbedded
  - Upstream: https://github.com/Trickfest/StockfishEmbedded
  - Path: `../StockfishEmbedded`
  - Product: `SFEngine-iOS`
  - License: GNU General Public License v3.0 in `../StockfishEmbedded/LICENSE`
  - Includes Stockfish, distributed under the GNU General Public License v3.0.
  - Distribution of a binary linked with this dependency should include the
    GPLv3 license text and corresponding source information required by GPLv3.

Update by committing changes in the sibling dependency repo, then rebuild this
app. Do not reintroduce vendored subtree copies here.
