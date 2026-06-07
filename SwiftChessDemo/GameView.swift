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
                .onMove { move, isLegal, _, _, _, _ in
                    viewModel.handleUserMove(move: move, isLegal: isLegal)
                }
                .aspectRatio(1, contentMode: .fit)
                .accessibilityIdentifier("Game.board")
                .accessibilityValue("Pieces: \(viewModel.pieceSet.displayName), Board: \(viewModel.boardTheme.displayName)")
                .padding()

            displayControls

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
