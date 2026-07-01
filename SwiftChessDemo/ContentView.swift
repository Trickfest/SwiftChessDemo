//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and StockfishEmbedded.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the MIT License.
// You may obtain a copy of the License in the LICENSE file
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

    /// Creates a UI choice from a ChessCore color.
    init(pieceColor: PieceColor) {
        switch pieceColor {
        case .white:
            self = .white
        case .black:
            self = .black
        }
    }
}

/// Launch screen where the user configures the demo before starting a game.
struct ContentView: View {
    /// Scenario requested by launch environment, if any.
    private let requestedScenarioResult: Result<GameScenario?, GameScenarioLoadingError>
    /// Scenario-index validation requested by launch environment, if any.
    private let scenarioIndexValidationResult: Result<GameScenarioIndexValidationSummary, GameScenarioIndexValidationError>?
    /// Which side the user has selected in the segmented control.
    @State private var playerSide: PlayerSide
    /// Top-level mode for manually started games.
    @State private var gameMode: DemoGameMode
    /// Engine-vs-engine settings used when the demo mode is selected.
    @State private var engineDemoConfiguration: EngineDemoConfiguration

    /// Creates the setup view and applies scenario defaults when requested.
    init(
        requestedScenarioResult: Result<GameScenario?, GameScenarioLoadingError> = GameScenarioLoader.requestedScenario(),
        scenarioIndexValidationResult: Result<GameScenarioIndexValidationSummary, GameScenarioIndexValidationError>? = GameScenarioIndexLoader.requestedValidation()
    ) {
        self.requestedScenarioResult = requestedScenarioResult
        self.scenarioIndexValidationResult = scenarioIndexValidationResult
        let requestedScenario = (try? requestedScenarioResult.get()) ?? nil
        _playerSide = State(initialValue: PlayerSide(pieceColor: requestedScenario?.initialPerspective ?? .white))
        _gameMode = State(initialValue: .humanVsEngine)
        _engineDemoConfiguration = State(
            initialValue: EngineDemoConfiguration.defaultConfiguration(defaultDepth: Self.initialEngineDepth)
        )
    }

    var body: some View {
        // NavigationStack enables the push to the game screen.
        NavigationStack {
            VStack(spacing: 24) {
                modePicker

                if requestedScenario == nil, gameMode == .engineVsEngine {
                    engineDemoSetupSection
                } else {
                    sidePicker
                }

                if let requestedScenario {
                    Text(requestedScenario.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("Setup.scenarioTitle")
                }

                if let scenarioLoadingError {
                    Text("Scenario load error")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("Setup.scenarioError")

                    Text(scenarioLoadingError.localizedDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("Setup.scenarioErrorDetail")
                }

                if let scenarioIndexValidationResult {
                    switch scenarioIndexValidationResult {
                    case .success(let summary):
                        Text("Scenario index valid")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("Setup.scenarioIndexStatus")

                        Text(summary.displayText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("Setup.scenarioIndexDetail")

                    case .failure(let error):
                        Text("Scenario index error")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("Setup.scenarioIndexStatus")

                        Text(error.localizedDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("Setup.scenarioIndexDetail")
                    }
                }

                // The main transition into gameplay; passes config into GameView.
                NavigationLink("Start Game") {
                    GameView(
                        playerColor: requestedScenario?.initialPerspective ?? playerSide.pieceColor,
                        pieceSet: .artDecoMonochrome,
                        boardTheme: .artDecoMonochrome,
                        gameMode: requestedScenario == nil ? gameMode : .humanVsEngine,
                        engineDemoConfiguration: engineDemoConfiguration.normalized(),
                        scenario: requestedScenario
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(scenarioLoadingError != nil || scenarioIndexValidationError != nil)

                Spacer()
            }
            .padding()
            .navigationTitle("Swift Chess Demo")
        }
    }

    private var requestedScenario: GameScenario? {
        try? requestedScenarioResult.get()
    }

    private var scenarioLoadingError: GameScenarioLoadingError? {
        guard case .failure(let error) = requestedScenarioResult else { return nil }
        return error
    }

    private var scenarioIndexValidationError: GameScenarioIndexValidationError? {
        guard case .failure(let error)? = scenarioIndexValidationResult else { return nil }
        return error
    }

    private var modePicker: some View {
        Picker("Mode", selection: $gameMode) {
            ForEach(DemoGameMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("Setup.gameModePicker")
        .disabled(requestedScenario != nil)
    }

    private var sidePicker: some View {
        Picker("Side", selection: $playerSide) {
            ForEach(PlayerSide.allCases) { side in
                Text(side.rawValue).tag(side)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("Setup.sidePicker")
        .disabled(requestedScenario != nil)
    }

    private var engineDemoSetupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Engine Demo")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            engineSideControl(title: "White", color: .white)
            engineSideControl(title: "Black", color: .black)

            engineDemoPacingControl
            engineDemoTimeoutControl
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        }
    }

    private var engineDemoPacingControl: some View {
        HStack {
            Text("Pacing")
                .font(.subheadline)

            Spacer()

            Picker("Pacing", selection: $engineDemoConfiguration.pacing) {
                ForEach(EngineDemoPacing.allCases) { pacing in
                    Text(pacing.displayName).tag(pacing)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("Setup.engineDemoPacingPicker")
        }
    }

    private var engineDemoTimeoutControl: some View {
        HStack {
            Text("Timeout")
                .font(.subheadline)

            Spacer()

            Picker("Timeout", selection: $engineDemoConfiguration.searchTimeout) {
                ForEach(EngineDemoSearchTimeout.allCases) { timeout in
                    Text(timeout.displayName).tag(timeout)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier("Setup.engineDemoTimeoutPicker")
        }
    }

    private func engineSideControl(title: String, color: PieceColor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("\(title) Engine", selection: engineKindBinding(for: color)) {
                ForEach(DemoEngineKind.allCases) { engineKind in
                    Text(engineKind.displayName).tag(engineKind)
                }
            }
            .accessibilityIdentifier("Setup.engineDemo\(title)EnginePicker")

            Stepper(
                value: engineDepthBinding(for: color),
                in: EngineDemoConfiguration.minimumDepth...EngineDemoConfiguration.maximumDepth
            ) {
                Text("\(title) depth \(engineDepth(for: color))")
                    .font(.caption)
            }
            .accessibilityIdentifier("Setup.engineDemo\(title)DepthStepper")
            .accessibilityValue("\(engineDepth(for: color))")
        }
    }

    private func engineKindBinding(for color: PieceColor) -> Binding<DemoEngineKind> {
        Binding {
            engineDemoConfiguration.sideConfiguration(for: color).engineKind
        } set: { engineKind in
            switch color {
            case .white:
                engineDemoConfiguration.white.engineKind = engineKind
            case .black:
                engineDemoConfiguration.black.engineKind = engineKind
            }
        }
    }

    private func engineDepthBinding(for color: PieceColor) -> Binding<Int> {
        Binding {
            engineDepth(for: color)
        } set: { depth in
            switch color {
            case .white:
                engineDemoConfiguration.white.depth = EngineDemoConfiguration.clampedDepth(depth)
            case .black:
                engineDemoConfiguration.black.depth = EngineDemoConfiguration.clampedDepth(depth)
            }
        }
    }

    private func engineDepth(for color: PieceColor) -> Int {
        engineDemoConfiguration.sideConfiguration(for: color).depth
    }

    /// UI-test launches can lower the setup default so live engine smoke tests stay fast.
    private static var initialEngineDepth: Int {
        let environment = ProcessInfo.processInfo.environment
        guard let depthValue = environment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_DEPTH"],
              let depth = Int(depthValue)
        else {
            return EngineDemoConfiguration.defaultDepth
        }

        return EngineDemoConfiguration.clampedDepth(depth)
    }
}

// SwiftUI preview for quick UI iteration in Xcode.
#Preview {
    ContentView()
}
