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

/// Application entry point for the demo.
///
/// This app intentionally keeps the root scene simple so the teaching focus
/// stays on how the three third-party libraries are wired together in the
/// feature views.
@main
struct SwiftChessDemoApp: App {
    /// The single-window scene that hosts the SwiftUI UI.
    var body: some Scene {
        WindowGroup {
            // Start at the configuration screen so learners can see the flow
            // from "choose a side" into the gameplay screen.
            ContentView()
        }
    }
}
