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
import ChessUI

/// Gameplay screen that hosts the ChessUI board and controls.
struct GameView: View {
    /// Used to dismiss back to the configuration screen.
    @Environment(\.dismiss) private var dismiss
    /// Chooses a compact or regular display-controls layout without duplicating controls.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Owns the game logic and engine integration for this screen.
    @StateObject private var viewModel: GameViewModel
    /// Last measured board area width, used to keep the board and evaluation bar in sync.
    @State private var boardContainerWidth: CGFloat = 320

    private static let regularMaxBoardAreaWidth: CGFloat = 720
    private static let compactMaxBoardAreaWidth: CGFloat = 620
    private static let verticalEvaluationBarWidth: CGFloat = 28
    private static let horizontalEvaluationBarHeight: CGFloat = 26
    private static let regularEvaluationSpacing: CGFloat = 10
    private static let compactEvaluationSpacing: CGFloat = 8

    /// Creates the view model with the chosen side, board styling, and optional scenario.
    init(
        playerColor: PieceColor,
        pieceSet: ChessPieceSet,
        boardTheme: ChessBoardTheme,
        gameMode: DemoGameMode = .humanVsEngine,
        engineDemoConfiguration: EngineDemoConfiguration = .defaultConfiguration(),
        scenario: GameScenario? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: GameViewModel(
                playerColor: playerColor,
                pieceSet: pieceSet,
                boardTheme: boardTheme,
                gameMode: gameMode,
                engineDemoConfiguration: engineDemoConfiguration,
                scenario: scenario
            )
        )
    }

    var body: some View {
        ScrollView {
            gameLayout
                .padding()
                .padding(.bottom, 32)
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
                .frame(maxWidth: Self.regularMaxBoardAreaWidth)

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
        .frame(maxWidth: Self.compactMaxBoardAreaWidth)
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
        GeometryReader { geometry in
            let sideLength = resolvedBoardSideLength(for: geometry.size.width)

            boardWithEvaluationContent(sideLength: sideLength)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .onAppear {
                    updateBoardContainerWidth(geometry.size.width)
                }
                .onChange(of: geometry.size.width) { _, newWidth in
                    updateBoardContainerWidth(newWidth)
                }
            }
        .frame(height: boardWithEvaluationHeight)
    }

    @ViewBuilder
    private func boardWithEvaluationContent(sideLength: CGFloat) -> some View {
        if horizontalSizeClass == .regular {
            HStack(alignment: .top, spacing: viewModel.showsEvaluationBar ? Self.regularEvaluationSpacing : 0) {
                if viewModel.showsEvaluationBar {
                    verticalEvaluationBar
                        .frame(width: Self.verticalEvaluationBarWidth, height: sideLength)
                }

                boardView
                    .frame(width: sideLength, height: sideLength)
            }
            .frame(height: sideLength)
        } else {
            VStack(spacing: viewModel.showsEvaluationBar ? Self.compactEvaluationSpacing : 0) {
                if viewModel.showsEvaluationBar {
                    horizontalEvaluationBar
                        .frame(width: sideLength, height: Self.horizontalEvaluationBarHeight)
                }

                boardView
                    .frame(width: sideLength, height: sideLength)
            }
        }
    }

    private var resolvedBoardSideLength: CGFloat {
        resolvedBoardSideLength(for: boardContainerWidth)
    }

    private var boardWithEvaluationHeight: CGFloat {
        let sideLength = resolvedBoardSideLength

        if horizontalSizeClass == .regular {
            return sideLength
        }

        let evaluationHeight = viewModel.showsEvaluationBar
            ? Self.horizontalEvaluationBarHeight + Self.compactEvaluationSpacing
            : 0
        return sideLength + evaluationHeight
    }

    private func resolvedBoardSideLength(for width: CGFloat) -> CGFloat {
        let availableWidth = max(width, 1)

        if horizontalSizeClass == .regular {
            let reservedWidth = viewModel.showsEvaluationBar
                ? Self.verticalEvaluationBarWidth + Self.regularEvaluationSpacing
                : 0
            return max(1, min(Self.regularMaxBoardAreaWidth - reservedWidth, availableWidth - reservedWidth))
        }

        return max(1, min(Self.compactMaxBoardAreaWidth, availableWidth))
    }

    private func updateBoardContainerWidth(_ width: CGFloat) {
        guard width > 0, abs(width - boardContainerWidth) > 0.5 else { return }
        boardContainerWidth = width
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
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Game board")
                    .accessibilityIdentifier("Game.boardState")
                    .accessibilityValue(boardAccessibilityValue)
                    .allowsHitTesting(false)
            }
    }

    private var verticalEvaluationBar: some View {
        ChessEvaluationBar(
            evaluation: viewModel.evaluation,
            orientation: .vertical,
            whiteSide: viewModel.playerColor == .white ? .bottom : .top
        )
    }

    private var horizontalEvaluationBar: some View {
        ChessEvaluationBar(
            evaluation: viewModel.evaluation,
            orientation: .horizontal,
            whiteSide: .leading
        )
    }

    private var boardAccessibilityValue: String {
        let coordinateState = viewModel.showsCoordinateLabels ? "Shown" : "Hidden"

        return "Pieces: \(viewModel.pieceSet.displayName), "
            + "Board: \(viewModel.boardTheme.displayName), "
            + "Coordinates: \(coordinateState), "
            + "Mode: \(viewModel.gameMode.displayName), "
            + "Suggestions: \(viewModel.suggestionArrowCount), "
            + "Move time: \(viewModel.engineMoveTime.displayName), "
            + "Engine: \(viewModel.selectedEngineKind.displayName), "
            + "Engine status: \(viewModel.engineActivity.accessibilityValue), "
            + engineDemoAccessibilityValue
            + viewModel.scenarioAccessibilityValue
            + "FEN: \(viewModel.positionFEN)"
    }

    private var engineDemoAccessibilityValue: String {
        guard viewModel.isEngineDemoMode else { return "" }

        return "Demo state: \(viewModel.engineDemoPrimaryControlTitle), "
            + "White engine: \(viewModel.engineDemoConfiguration.white.engineKind.displayName), "
            + "White move time: \(viewModel.engineDemoConfiguration.white.moveTime.displayName), "
            + "Black engine: \(viewModel.engineDemoConfiguration.black.engineKind.displayName), "
            + "Black move time: \(viewModel.engineDemoConfiguration.black.moveTime.displayName), "
            + "Pacing: \(viewModel.engineDemoConfiguration.pacing.displayName)"
    }

    private func engineDemoSideConfiguration(for color: PieceColor) -> EngineDemoSideConfiguration {
        viewModel.engineDemoConfiguration.sideConfiguration(for: color)
    }

    private var referencePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.isEngineDemoMode {
                engineDemoControlsSection
            }

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
        panelSection("Preferences") {
            if horizontalSizeClass == .regular {
                VStack(spacing: 10) {
                    pieceSetControl
                    boardThemeControl
                    if !viewModel.isEngineDemoMode {
                        suggestionArrowsControl
                        engineSelectionControl
                    }
                    coordinateLabelsToggle
                    gameStatusToggle
                    moveListToggle
                    evaluationBarToggle
                    if !viewModel.isEngineDemoMode {
                        engineMoveTimeControl
                    }
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

            if !viewModel.isEngineDemoMode {
                suggestionArrowsControl

                engineSelectionControl
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

            if !viewModel.isEngineDemoMode {
                engineMoveTimeControl
            }
        }
    }

    private var engineDemoControlsSection: some View {
        panelSection("Engine Demo") {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        viewModel.toggleEngineDemoPlayback()
                    } label: {
                        Label(
                            viewModel.engineDemoPrimaryControlTitle,
                            systemImage: engineDemoPrimaryControlSystemImage
                        )
                        .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(engineDemoPrimaryControlIsDisabled)
                    .accessibilityIdentifier("Game.engineDemoPlayPauseButton")

                    Button {
                        viewModel.stepEngineDemo()
                    } label: {
                        Label("Step", systemImage: "forward.end")
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canStepEngineDemo)
                    .accessibilityIdentifier("Game.engineDemoStepButton")
                }

                engineDemoPacingControl
                engineDemoSideControl(title: "White", color: .white)
                engineDemoSideControl(title: "Black", color: .black)
                engineDemoStressControls
            }
        }
    }

    private var engineDemoPacingControl: some View {
        Menu {
            ForEach(EngineDemoPacing.allCases) { pacing in
                Button(pacing.displayName) {
                    viewModel.setEngineDemoPacing(pacing)
                }
                .disabled(pacing == viewModel.engineDemoConfiguration.pacing)
            }
        } label: {
            displayControlLabel(
                title: "Pacing",
                value: viewModel.engineDemoConfiguration.pacing.displayName,
                systemImage: "timer"
            )
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
        .accessibilityIdentifier("Game.engineDemoPacingPicker")
        .accessibilityValue(viewModel.engineDemoConfiguration.pacing.displayName)
    }

    private func engineDemoSideControl(title: String, color: PieceColor) -> some View {
        VStack(spacing: 8) {
            Menu {
                ForEach(DemoEngineKind.allCases) { engineKind in
                    Button(engineKind.displayName) {
                        viewModel.setEngineDemoEngineKind(engineKind, for: color)
                    }
                    .disabled(engineKind == engineDemoSideConfiguration(for: color).engineKind)
                }
            } label: {
                displayControlLabel(
                    title: "\(title) Engine",
                    value: engineDemoSideConfiguration(for: color).engineKind.displayName,
                    systemImage: "cpu"
                )
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("Game.engineDemo\(title)EnginePicker")
            .accessibilityValue(engineDemoSideConfiguration(for: color).engineKind.displayName)

            Menu {
                ForEach(EngineMoveTime.allCases) { moveTime in
                    Button(moveTime.displayName) {
                        viewModel.setEngineDemoMoveTime(moveTime, for: color)
                    }
                    .disabled(moveTime == engineDemoSideConfiguration(for: color).moveTime)
                }
            } label: {
                displayControlLabel(
                    title: "\(title) Move Time",
                    value: engineDemoSideConfiguration(for: color).moveTime.displayName,
                    systemImage: "timer"
                )
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .accessibilityIdentifier("Game.engineDemo\(title)MoveTimePicker")
            .accessibilityValue(engineDemoSideConfiguration(for: color).moveTime.displayName)
        }
    }

    private var engineDemoStressControls: some View {
        VStack(spacing: 8) {
            displayToggleRow(
                title: "Stress mode",
                systemImage: "shuffle",
                isOn: viewModel.engineDemoConfiguration.stress.isEnabled,
                accessibilityIdentifier: "Game.engineDemoStressToggle"
            ) {
                viewModel.setEngineDemoStressEnabled(!viewModel.engineDemoConfiguration.stress.isEnabled)
            }

            if viewModel.engineDemoConfiguration.stress.isEnabled {
                displayToggleRow(
                    title: "Random engines",
                    systemImage: "cpu",
                    isOn: viewModel.engineDemoConfiguration.stress.randomizesEngineEachMove,
                    accessibilityIdentifier: "Game.engineDemoRandomEnginesToggle"
                ) {
                    viewModel.setEngineDemoRandomizesEngineEachMove(
                        !viewModel.engineDemoConfiguration.stress.randomizesEngineEachMove
                    )
                }

                displayToggleRow(
                    title: "Random move times",
                    systemImage: "timer",
                    isOn: viewModel.engineDemoConfiguration.stress.randomizesMoveTimeEachMove,
                    accessibilityIdentifier: "Game.engineDemoRandomMoveTimesToggle"
                ) {
                    viewModel.setEngineDemoRandomizesMoveTimeEachMove(
                        !viewModel.engineDemoConfiguration.stress.randomizesMoveTimeEachMove
                    )
                }

                if viewModel.engineDemoConfiguration.stress.randomizesMoveTimeEachMove {
                    engineDemoStressMoveTimeControl(title: "Minimum", isMinimum: true)
                    engineDemoStressMoveTimeControl(title: "Maximum", isMinimum: false)
                }
            }
        }
    }

    private func engineDemoStressMoveTimeControl(title: String, isMinimum: Bool) -> some View {
        let selectedMoveTime = isMinimum
            ? viewModel.engineDemoConfiguration.stress.minimumMoveTime
            : viewModel.engineDemoConfiguration.stress.maximumMoveTime

        return Menu {
            ForEach(EngineMoveTime.allCases) { moveTime in
                Button(moveTime.displayName) {
                    if isMinimum {
                        viewModel.setEngineDemoStressMinimumMoveTime(moveTime)
                    } else {
                        viewModel.setEngineDemoStressMaximumMoveTime(moveTime)
                    }
                }
                .disabled(moveTime == selectedMoveTime)
            }
        } label: {
            displayControlLabel(
                title: "\(title) Move Time",
                value: selectedMoveTime.displayName,
                systemImage: "slider.horizontal.3"
            )
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("Game.engineDemoStress\(title)MoveTimePicker")
    }

    private var engineDemoPrimaryControlSystemImage: String {
        switch viewModel.engineDemoRunState {
        case .playing, .stepping, .pausingAfterCurrentMove:
            return "pause.fill"
        case .paused:
            return "play.fill"
        }
    }

    private var engineDemoPrimaryControlIsDisabled: Bool {
        switch viewModel.engineDemoRunState {
        case .stepping, .pausingAfterCurrentMove:
            return true
        case .paused, .playing:
            return !viewModel.isGameOngoing
        }
    }

    private var statusDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.engineActivity.message != nil {
                engineStatusContent
            } else {
                ChessGameStatusView(
                    status: viewModel.gameStatus,
                    turn: viewModel.sideToMove
                ) { claim in
                    viewModel.claimDraw(claim)
                }
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

    private var engineStatusContent: some View {
        HStack(spacing: 8) {
            Text(viewModel.engineActivity.message ?? "")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if viewModel.engineActivity.showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.primary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Engine status")
        .accessibilityValue(viewModel.engineActivity.accessibilityValue)
        .accessibilityIdentifier("Game.engineStatus")
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

    private var suggestionArrowsControl: some View {
        Menu {
            ForEach(0...3, id: \.self) { count in
                Button(suggestionArrowOptionTitle(for: count)) {
                    viewModel.setSuggestionArrowCount(count)
                }
            }
        } label: {
            displayControlLabel(
                title: "Suggestions",
                value: suggestionArrowOptionTitle(for: viewModel.suggestionArrowCount),
                systemImage: "arrow.up.right"
            )
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
        .accessibilityIdentifier("Game.suggestionCountPicker")
        .accessibilityValue(suggestionArrowOptionTitle(for: viewModel.suggestionArrowCount))
    }

    @ViewBuilder
    private var engineSelectionControl: some View {
        if viewModel.showsEngineSelection {
            Menu {
                ForEach(DemoEngineKind.allCases) { engineKind in
                    Button(engineKind.displayName) {
                        viewModel.setSelectedEngineKind(engineKind)
                    }
                    .disabled(engineKind == viewModel.selectedEngineKind)
                }
            } label: {
                displayControlLabel(
                    title: "Engine",
                    value: viewModel.selectedEngineKind.displayName,
                    systemImage: "cpu"
                )
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .disabled(!viewModel.canSwitchEngine)
            .accessibilityIdentifier("Game.enginePicker")
            .accessibilityValue(viewModel.selectedEngineKind.displayName)
        }
    }

    private var engineMoveTimeControl: some View {
        Menu {
            ForEach(EngineMoveTime.allCases) { moveTime in
                Button(moveTime.displayName) {
                    viewModel.setEngineMoveTime(moveTime)
                }
                .disabled(moveTime == viewModel.engineMoveTime)
            }
        } label: {
            displayControlLabel(
                title: "Move Time",
                value: viewModel.engineMoveTime.displayName,
                systemImage: "timer"
            )
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.bordered)
        .accessibilityIdentifier("Game.engineMoveTimePicker")
        .accessibilityValue(viewModel.engineMoveTime.displayName)
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
                    ForEach(viewModel.uiTestMoveCoordinates, id: \.self) { move in
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

    private func suggestionArrowOptionTitle(for count: Int) -> String {
        switch count {
        case 0:
            return "Off"
        case 1:
            return "1 arrow"
        default:
            return "\(count) arrows"
        }
    }
}
