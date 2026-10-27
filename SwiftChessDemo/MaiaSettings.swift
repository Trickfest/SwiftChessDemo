//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and embedded engines.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the MIT License.
// You may obtain a copy of the License in the LICENSE file
// See the LICENSE file for more information.
//

import SwiftUI

/// Ratings refer to the side to move and its opponent, not fixed colors.
struct MaiaSettings: Equatable, Sendable {
    var selfRating = 1600
    var opponentRating = 1600
    var temperature = 1.0
    var topP = 1.0
    var useHistory = false
}

struct MaiaSettingsView: View {
    @ObservedObject var viewModel: GameViewModel
    @State private var draft = MaiaSettings()
    private func binding<T>(_ key: WritableKeyPath<MaiaSettings, T>) -> Binding<T> {
        Binding(get: { draft[keyPath: key] }, set: { draft[keyPath: key] = $0 })
    }

    var body: some View {
        DisclosureGroup("Maia settings") {
            VStack(alignment: .leading, spacing: 12) {
                Stepper("Side to move: \(draft.selfRating)", value: binding(\.selfRating), in: 600...2600, step: 100)
                Stepper("Opponent: \(draft.opponentRating)", value: binding(\.opponentRating), in: 600...2600, step: 100)
                Text("Temperature: \(draft.temperature, specifier: "%.1f")")
                Slider(value: binding(\.temperature), in: 0...2, step: 0.1)
                Text("Top P: \(draft.topP, specifier: "%.2f")")
                Slider(value: binding(\.topP), in: 0.05...1, step: 0.05)
                Toggle("Use recorded game history", isOn: binding(\.useHistory))
                Button("Apply Maia settings") { viewModel.setMaiaSettings(draft) }
                    .disabled(draft == viewModel.maiaSettings)
                Text("Maia predicts human moves at Lichess rating levels. Suggestions show likely moves. Temperature 0 selects the most likely move. Move time does not change its strength. Settings apply to both colors in engine demo mode.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }
        .onAppear { draft = viewModel.maiaSettings }
        .onChange(of: viewModel.maiaSettings) { _, value in draft = value }
        .disabled(!viewModel.canEditMaiaSettings)
    }
}
