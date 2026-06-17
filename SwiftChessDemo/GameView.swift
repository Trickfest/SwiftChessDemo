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

/// Gameplay screen that hosts the ChessUI board and controls.
struct GameView: View {
    /// Used to dismiss back to the configuration screen.
    @Environment(\.dismiss) private var dismiss
    /// Owns the game logic and engine integration for this screen.
    @StateObject private var viewModel: GameViewModel

    /// Creates the view model with the chosen side, engine depth, and board styling.
    init(playerColor: PieceColor, engineDepth: Int, pieceSet: ChessPieceSet, boardTheme: ChessBoardTheme) {
        _viewModel = StateObject(
            wrappedValue: GameViewModel(
                playerColor: playerColor,
                engineDepth: engineDepth,
                pieceSet: pieceSet,
                boardTheme: boardTheme
            )
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            // ChessUI view; delivers user moves via the onMove callback.
            ChessBoardView(model: viewModel.boardModel)
                .onMove { attempt in
                    viewModel.handleUserMove(move: attempt.move, isLegal: attempt.isLegal)
                }
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    // Separate state marker keeps board assertions independent
                    // from visual board rendering.
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Game board")
                        .accessibilityIdentifier("Game.boardState")
                        .accessibilityValue(
                            "Pieces: \(viewModel.pieceSet.displayName), Board: \(viewModel.boardTheme.displayName), FEN: \(viewModel.positionFEN)"
                        )
                        .allowsHitTesting(false)
                }
                .padding()

            displayControls

            if viewModel.showsUITestMoveControls {
                uiTestMoveControls
            }

            // Simple resign button to demonstrate game-ending flow.
            Button("Resign") {
                viewModel.requestResignConfirmation()
            }
            .buttonStyle(.bordered)
        }
        .navigationTitle("Game")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    viewModel.requestResignConfirmation()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
            }
        }
        .onAppear {
            // Start the engine if the user is playing black.
            viewModel.startIfNeeded()
        }
        .onDisappear {
            // Always shut down the engine when leaving the screen.
            viewModel.cleanup()
        }
        .alert(item: $viewModel.activeAlert) { alert in
            switch alert {
            case .resignConfirmation:
                return Alert(
                    title: Text("Are you sure you want to resign?"),
                    primaryButton: .destructive(Text("Resign")) {
                        viewModel.resign()
                        dismiss()
                    },
                    secondaryButton: .cancel()
                )
            case .result(let result):
                return Alert(
                    title: Text(result.title),
                    message: Text(result.message),
                    dismissButton: .default(Text("OK")) {
                        dismiss()
                    }
                )
            }
        }
    }

    private var displayControls: some View {
        HStack(spacing: 12) {
            Menu {
                Picker("Pieces", selection: $viewModel.pieceSet) {
                    ForEach(ChessPieceSet.availableSets) { pieceSet in
                        Text(pieceSet.displayName).tag(pieceSet)
                    }
                }
            } label: {
                displayControlLabel(
                    title: "Pieces",
                    value: viewModel.pieceSet.displayName,
                    systemImage: "square.grid.3x3"
                )
            }
            .accessibilityIdentifier("Game.pieceSetPicker")
            .accessibilityValue(viewModel.pieceSet.displayName)

            Menu {
                Picker("Board", selection: $viewModel.boardTheme) {
                    ForEach(ChessBoardTheme.availableThemes) { boardTheme in
                        Text(boardTheme.displayName).tag(boardTheme)
                    }
                }
            } label: {
                displayControlLabel(
                    title: "Board",
                    value: viewModel.boardTheme.displayName,
                    systemImage: "square.grid.2x2"
                )
            }
            .accessibilityIdentifier("Game.boardThemePicker")
            .accessibilityValue(viewModel.boardTheme.displayName)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
    }

    private var uiTestMoveControls: some View {
        VStack(spacing: 6) {
            Text(viewModel.positionFEN)
                .font(.caption2.monospaced())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("UITest.positionFEN")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["e2e4", "e7e5", "g1f3", "b8c6", "f1c4", "g8f6", "d2d3", "f8c5"], id: \.self) { move in
                        Button(move) {
                            viewModel.performUITestMove(move)
                        }
                        .accessibilityIdentifier("UITest.move.\(move)")
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(height: 64)
    }

    private func displayControlLabel(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }
}
