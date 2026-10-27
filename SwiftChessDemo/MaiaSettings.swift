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
import ChessCore

/// Ratings refer to the side to move and its opponent, not fixed colors.
struct MaiaSettings: Equatable, Sendable {
    var selfRating = 1600
    var opponentRating = 1600
    var temperature = 1.0
    var topP = 1.0
    var useHistory = true
}

struct MaiaSettingsView: View {
    @ObservedObject var viewModel: GameViewModel
    var side: PieceColor? = nil
    @State private var temperature = MaiaSettings().temperature
    @State private var topP = MaiaSettings().topP

    private var settings: MaiaSettings { viewModel.maiaSettings(for: side) }
    private var isEnabled: Bool { viewModel.canEditMaiaSettings(for: side) }

    // Discrete controls apply immediately; slider values stay local until release.
    private func binding<T>(_ key: WritableKeyPath<MaiaSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: key] }, set: { apply($0, to: key) })
    }

    private func apply<T>(_ value: T, to key: WritableKeyPath<MaiaSettings, T>) {
        var updated = settings
        updated[keyPath: key] = value
        viewModel.setMaiaSettings(updated, for: side)
    }

    private func syncSliders() {
        temperature = settings.temperature
        topP = settings.topP
    }

    var body: some View {
        DisclosureGroup("Maia settings") {
            VStack(alignment: .leading, spacing: 12) {
                Stepper("\(side == nil ? "Side to move" : side == .white ? "White" : "Black"): \(settings.selfRating)", value: binding(\.selfRating), in: 600...2600, step: 100)
                Stepper("Opponent: \(settings.opponentRating)", value: binding(\.opponentRating), in: 600...2600, step: 100)
                Text("Temperature: \(temperature, specifier: "%.1f")")
                Slider(value: $temperature, in: 0...2, step: 0.1, onEditingChanged: { editing in
                    if !editing { apply(temperature, to: \.temperature); syncSliders() }
                })
                Text("Top P: \(topP, specifier: "%.2f")")
                Slider(value: $topP, in: 0.05...1, step: 0.05, onEditingChanged: { editing in
                    if !editing { apply(topP, to: \.topP); syncSliders() }
                })
                Toggle("Use recorded game history", isOn: binding(\.useHistory))
                Text("Maia predicts human moves at Lichess rating levels. Suggestions show likely moves. Temperature 0 selects the most likely move. Ratings and history apply immediately; sliders apply on release.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }
        .onAppear { syncSliders() }
        .onChange(of: settings) { _, _ in syncSliders() }
        .disabled(!isEnabled)
        .tint(isEnabled ? Color.accentColor : Color.secondary)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        .accessibilityIdentifier("Game.\(side == nil ? "maia" : side == .white ? "whiteMaia" : "blackMaia")Settings")
    }
}
