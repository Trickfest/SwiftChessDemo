//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and StockfishEmbedded.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the GNU General Public License v3.0.
// You may obtain a copy of the License at: https://www.gnu.org/licenses/gpl-3.0.html
// See the LICENSE file for more information.
//

import SwiftUI
import ChessCore
import ChessUI

/// UI-facing representation of which side the human will play.
///
/// This is intentionally a local enum so the view can expose friendly
/// strings while still mapping cleanly to ChessCore's `PieceColor`.
private enum PlayerSide: String, CaseIterable, Identifiable {
    case white = "Play as White"
    case black = "Play as Black"

    /// Stable identifier for SwiftUI list/picker diffing.
    var id: String { rawValue }

    /// The ChessCore color that corresponds to the UI choice.
    var pieceColor: PieceColor {
        switch self {
        case .white:
            return .white
        case .black:
            return .black
        }
    }
}

/// Launch screen where the user configures the demo before starting a game.
struct ContentView: View {
    /// Which side the user has selected in the segmented control.
    @State private var playerSide: PlayerSide = .white

    var body: some View {
        // NavigationStack enables the push to the game screen.
        NavigationStack {
            VStack(spacing: 24) {
                // Use a segmented picker to keep the choice compact and obvious.
                Picker("Side", selection: $playerSide) {
                    ForEach(PlayerSide.allCases) { side in
                        Text(side.rawValue).tag(side)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("Setup.sidePicker")

                // The main transition into gameplay; passes config into GameView.
                NavigationLink("Start Game") {
                    GameView(
                        playerColor: playerSide.pieceColor,
                        pieceSet: .artDecoMonochrome,
                        boardTheme: .artDecoMonochrome
                    )
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("Swift Chess Demo")
        }
    }
}

// SwiftUI preview for quick UI iteration in Xcode.
#Preview {
    ContentView()
}
