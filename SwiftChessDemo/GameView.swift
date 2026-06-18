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
    /// Chooses a compact or regular display-controls layout without duplicating controls.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Owns the game logic and engine integration for this screen.
    @StateObject private var viewModel: GameViewModel
    /// Last measured board side length, used to size adjacent reference UI.
    @State private var boardSideLength: CGFloat = 320

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
        ScrollView {
            gameLayout
                .padding()
        }
        .accessibilityIdentifier("Game.scrollView")
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

    @ViewBuilder
    private var gameLayout: some View {
        if horizontalSizeClass == .regular {
            regularGameLayout
        } else {
            compactGameLayout
        }
    }

    private var regularGameLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            boardArea
                .frame(maxWidth: 720)

            referencePanel
                .frame(width: 360)
        }
        .frame(maxWidth: 1120, alignment: .center)
        .frame(maxWidth: .infinity)
    }

    private var compactGameLayout: some View {
        VStack(spacing: 16) {
            boardArea
            referencePanel
        }
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
    }

    private var boardArea: some View {
        VStack(spacing: 12) {
            if viewModel.showsGameStatus {
                statusDisplay
            }

            if horizontalSizeClass != .regular, viewModel.showsMoveList {
                compactMoveListStrip
            }

            boardWithEvaluation

            if viewModel.showsUITestMoveControls {
                uiTestMoveControls
            }
        }
    }

    @ViewBuilder
    private var boardWithEvaluation: some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: 10) {
                if viewModel.showsEvaluationBar {
                    verticalEvaluationBar
                }

                boardView
            }
        } else {
            VStack(spacing: 8) {
                if viewModel.showsEvaluationBar {
                    horizontalEvaluationBar
                }

                boardView
            }
        }
    }

    private var boardView: some View {
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
                    .accessibilityValue(boardAccessibilityValue)
                    .allowsHitTesting(false)
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: BoardSideLengthPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            }
            .onPreferenceChange(BoardSideLengthPreferenceKey.self) { sideLength in
                boardSideLength = sideLength
            }
    }

    private var verticalEvaluationBar: some View {
        ChessEvaluationBar(
            evaluation: viewModel.evaluation,
            orientation: .vertical,
            whiteSide: viewModel.playerColor == .white ? .bottom : .top
        )
        .frame(width: 28, height: max(boardSideLength, 120))
    }

    private var horizontalEvaluationBar: some View {
        ChessEvaluationBar(
            evaluation: viewModel.evaluation,
            orientation: .horizontal,
            whiteSide: .leading
        )
        .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
    }

    private var boardAccessibilityValue: String {
        let coordinateState = viewModel.showsCoordinateLabels ? "Shown" : "Hidden"

        return "Pieces: \(viewModel.pieceSet.displayName), "
            + "Board: \(viewModel.boardTheme.displayName), "
            + "Coordinates: \(coordinateState), "
            + "FEN: \(viewModel.positionFEN)"
    }

    private var referencePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            displayOptionsSection

            if horizontalSizeClass == .regular, viewModel.showsMoveList {
                moveListSection
            }

            Button {
                viewModel.requestResignConfirmation()
            } label: {
                Label("Resign", systemImage: "flag")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("Game.resignButton")
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var displayOptionsSection: some View {
        panelSection("Display") {
            if horizontalSizeClass == .regular {
                VStack(spacing: 10) {
                    pieceSetControl
                    boardThemeControl
                    coordinateLabelsToggle
                    gameStatusToggle
                    moveListToggle
                    evaluationBarToggle
                }
            } else {
                compactDisplayOptions
            }
        }
    }

    private var compactDisplayOptions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                pieceSetControl
                boardThemeControl
            }

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    coordinateLabelsToggle
                    gameStatusToggle
                }

                HStack(spacing: 10) {
                    moveListToggle
                    evaluationBarToggle
                }
            }
        }
    }

    private var statusDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChessGameStatusView(
                status: viewModel.gameStatus,
                turn: viewModel.sideToMove
            ) { claim in
                viewModel.claimDraw(claim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        }
    }

    private var compactMoveListStrip: some View {
        ChessMoveListView(
            records: viewModel.moveRecords,
            selectedPly: viewModel.selectedMovePly,
            title: nil,
            layout: .horizontal,
            scrollIndicatorVisibility: .hidden
        ) { record in
            viewModel.selectMoveRecord(record)
        }
        .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        }
    }

    private var moveListSection: some View {
        panelSection("Moves") {
            ChessMoveListView(
                records: viewModel.moveRecords,
                selectedPly: viewModel.selectedMovePly,
                title: nil,
                layout: .vertical
            ) { record in
                viewModel.selectMoveRecord(record)
            }
            .frame(height: horizontalSizeClass == .regular ? 260 : 150)
        }
    }

    private var pieceSetControl: some View {
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
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
        .accessibilityIdentifier("Game.pieceSetPicker")
        .accessibilityValue(viewModel.pieceSet.displayName)
    }

    private var boardThemeControl: some View {
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
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
        .accessibilityIdentifier("Game.boardThemePicker")
        .accessibilityValue(viewModel.boardTheme.displayName)
    }

    private var coordinateLabelsToggle: some View {
        displayToggleRow(
            title: "Coordinates",
            systemImage: "number.square",
            isOn: viewModel.showsCoordinateLabels,
            accessibilityIdentifier: "Game.coordinateLabelsToggle"
        ) {
            viewModel.setCoordinateLabelsVisible(!viewModel.showsCoordinateLabels)
        }
    }

    private var gameStatusToggle: some View {
        displayToggleRow(
            title: "Status",
            systemImage: "list.bullet.rectangle",
            isOn: viewModel.showsGameStatus,
            accessibilityIdentifier: "Game.statusToggle"
        ) {
            viewModel.setGameStatusVisible(!viewModel.showsGameStatus)
        }
    }

    private var moveListToggle: some View {
        displayToggleRow(
            title: "Move list",
            systemImage: "list.number",
            isOn: viewModel.showsMoveList,
            accessibilityIdentifier: "Game.moveListToggle"
        ) {
            viewModel.setMoveListVisible(!viewModel.showsMoveList)
        }
    }

    private var evaluationBarToggle: some View {
        displayToggleRow(
            title: "Evaluation",
            systemImage: "chart.bar.fill",
            isOn: viewModel.showsEvaluationBar,
            accessibilityIdentifier: "Game.evaluationToggle"
        ) {
            viewModel.setEvaluationBarVisible(!viewModel.showsEvaluationBar)
        }
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

    private func displayToggleRow(
        title: String,
        systemImage: String,
        isOn: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Spacer(minLength: 6)

                toggleIndicator(isOn: isOn)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "Shown" : "Hidden")
        .frame(maxWidth: .infinity)
    }

    private func toggleIndicator(isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 11)
            .fill(isOn ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.18))
            .frame(width: 38, height: 22)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(isOn ? Color.accentColor : Color.secondary)
                    .frame(width: 18, height: 18)
                    .padding(2)
            }
            .accessibilityHidden(true)
    }

    private func panelSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            content()
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        }
    }
}

private struct BoardSideLengthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 320

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
