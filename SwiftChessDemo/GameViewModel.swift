//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and embedded engines.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the MIT License.
// You may obtain a copy of the License in the LICENSE file
// See the LICENSE file for more information.
//

import Combine
import ChessCore
import ChessUI
import ChessUCI

/// Coordinates the chess game state, the UI, and the embedded engine.
///
/// Teaching focus:
/// - ChessCore handles rules, legal moves, and game state.
/// - ChessUI renders the board and consumes FEN updates.
/// - DemoEngineProvider implementations isolate embedded engine UCI lifecycle.
final class GameViewModel: ObservableObject {
    typealias EngineProviderFactory = @MainActor (@escaping DemoEngineEventHandler) -> any DemoEngineProvider

    /// Lightweight model for the end-of-game alert content.
    struct GameResult: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// Alert types shown by the GameView.
    enum GameAlert: Identifiable {
        case resignConfirmation
        case result(GameResult)

        /// Stable ID so SwiftUI can manage alert presentation.
        var id: String {
            switch self {
            case .resignConfirmation:
                return "resignConfirmation"
            case .result(let result):
                return result.id.uuidString
            }
        }
    }

    /// User-visible engine activity shown on the game screen.
    enum EngineActivityState: Equatable {
        case idle
        case thinking(engine: DemoEngineKind)
        case timeoutWaiting(engine: DemoEngineKind)
        case notice(String)

        var message: String? {
            switch self {
            case .idle:
                return nil
            case .thinking(let engine):
                return "\(engine.displayName) thinking..."
            case .timeoutWaiting(let engine):
                return "\(engine.displayName) timed out; waiting for best move..."
            case .notice(let message):
                return message
            }
        }

        var accessibilityValue: String {
            message ?? "Idle"
        }

        var showsProgress: Bool {
            switch self {
            case .thinking, .timeoutWaiting:
                return true
            case .idle, .notice:
                return false
            }
        }
    }

    /// Drives alert presentation in the view.
    @Published var activeAlert: GameAlert?
    /// ChessUI piece artwork currently rendered by the board.
    @Published var pieceSet: ChessPieceSet {
        didSet {
            boardModel.pieceSet = pieceSet
        }
    }
    /// ChessUI board theme currently rendered by the board.
    @Published var boardTheme: ChessBoardTheme {
        didSet {
            boardModel.boardTheme = boardTheme
        }
    }
    /// Controls whether ChessUI renders rank and file coordinate labels.
    @Published var showsCoordinateLabels = true {
        didSet {
            boardModel.showsCoordinateLabels = showsCoordinateLabels
        }
    }
    /// Controls whether the game screen shows ChessUI's status component.
    @Published var showsGameStatus = true
    /// Controls whether the game screen shows ChessUI's move-list component.
    @Published var showsMoveList = true
    /// Controls whether the game screen shows ChessUI's evaluation bar.
    @Published var showsEvaluationBar = true
    /// Number of app-supplied engine suggestion arrows shown on the board.
    @Published private(set) var suggestionArrowCount: Int
    /// Move time used for future engine and suggestion searches.
    @Published private(set) var engineMoveTime: EngineMoveTime
    /// Embedded engine used for future live replies and suggestion analysis.
    @Published private(set) var selectedEngineKind: DemoEngineKind
    /// ChessCore status mirrored for SwiftUI rendering.
    @Published private(set) var gameStatus: GameStatus
    /// Side to move mirrored for SwiftUI rendering.
    @Published private(set) var sideToMove: PieceColor
    /// Display-ready move records for ChessUI's move list.
    @Published private(set) var moveRecords: [ChessMoveRecord] = []
    /// Current move-list selection.
    @Published var selectedMovePly: Int?
    /// Display-ready evaluation derived from parsed engine output.
    @Published private(set) var evaluation: ChessEvaluation
    /// Current FEN exposed to UI tests for black-box board-change assertions.
    @Published private(set) var positionFEN: String
    /// Current engine activity or recoverable engine status notice.
    @Published private(set) var engineActivity: EngineActivityState = .idle
    /// Engine-vs-engine settings used only by demo mode.
    @Published private(set) var engineDemoConfiguration: EngineDemoConfiguration
    /// Playback state for engine-vs-engine demo mode.
    @Published private(set) var engineDemoRunState: EngineDemoRunState = .paused
    /// Engine and move time selected for the most recent engine-vs-engine move request.
    @Published private(set) var engineDemoLastMoveConfiguration: EngineDemoMoveConfiguration?

    /// The human player's color; used to gate whose turn it is.
    let playerColor: PieceColor
    /// Whether the game is user-driven or engine-vs-engine.
    let gameMode: DemoGameMode
    /// ChessUI model that binds to the board UI.
    let boardModel: ChessBoardModel

    /// FEN serializer from ChessCore.
    private let fenSerializer = FENSerializer()
    /// Builds SAN-backed move-list records from pre-move game state.
    private let moveRecordBuilder = ChessMoveRecordBuilder()
    /// Optional deterministic move provider used for scenarios and scenario-backed UI tests.
    private let moveProvider: GameMoveProvider?
    /// Scenario being replayed, if this game was launched in scenario mode.
    private let scenario: GameScenario?
    /// Work item used to hold a fast engine reply until the minimum visible thinking time elapses.
    private var pendingEngineMoveWorkItem: DispatchWorkItem?
    /// Work item used to restore the normal game-status row after transient engine notices.
    private var engineActivityClearWorkItem: DispatchWorkItem?
    /// Work item used to advance automatic scenario replay.
    private var scenarioReplayWorkItem: DispatchWorkItem?
    /// Work item used to pace engine-vs-engine auto-play after a move has landed.
    private var engineDemoPacingWorkItem: DispatchWorkItem?
    /// Latest first move for each one-based MultiPV rank.
    private var suggestedMovesByRank: [Int: Move] = [:]
    /// FEN for the cached suggestion ranks.
    private var suggestedMovesPositionFEN: String?
    /// Ensures we only start the engine once when the view appears.
    private var didStart = false
    /// Minimum visible thinking time for an engine reply.
    private let minimumEngineThinkingSeconds: TimeInterval
    /// Delay between moves during automatic scenario replay.
    private let scenarioReplayDelaySeconds: TimeInterval
    /// Factory for the Stockfish-backed move and analysis provider.
    private let stockfishProviderFactory: EngineProviderFactory
    /// Factory for the Arasan-backed move and analysis provider.
    private let arasanProviderFactory: EngineProviderFactory
    /// Stockfish-backed move and analysis provider for normal gameplay.
    private lazy var stockfishProvider: any DemoEngineProvider =
        stockfishProviderFactory { [weak self] event in
            self?.receiveEngineProviderEvent(event)
        }
    /// Arasan-backed move and analysis provider for normal gameplay.
    private lazy var arasanProvider: any DemoEngineProvider =
        arasanProviderFactory { [weak self] event in
            self?.receiveEngineProviderEvent(event)
        }
    /// When the current opponent search began, used to make the delay a minimum rather than additive.
    private var opponentSearchStartedAt: Date?
    /// Whether the current opponent search has crossed the provider timeout.
    private var opponentSearchTimedOut = false
    /// Latest legal first move from the current opponent search's principal variation.
    private var latestOpponentPrincipalVariationMove: Move?
    /// Exact active move-producing request, used to reject stale cross-engine events.
    private var activeOpponentSearchRequest: EngineSearchRequest?
    /// Seeded generator used by deterministic engine-vs-engine stress mode.
    private var engineDemoRandomGenerator: SeededRandomGenerator

    init(
        playerColor: PieceColor,
        pieceSet: ChessPieceSet,
        boardTheme: ChessBoardTheme,
        gameMode: DemoGameMode = .humanVsEngine,
        engineDemoConfiguration: EngineDemoConfiguration = .defaultConfiguration(),
        scenario: GameScenario? = nil,
        minimumEngineThinkingSeconds: TimeInterval? = nil,
        scenarioReplayDelaySeconds: TimeInterval? = nil,
        stockfishProviderFactory: @escaping EngineProviderFactory = { StockfishMoveProvider(eventHandler: $0) },
        arasanProviderFactory: @escaping EngineProviderFactory = { ArasanMoveProvider(eventHandler: $0) }
    ) {
        // Capture user configuration so the view model can enforce turn order.
        self.playerColor = playerColor
        self.scenario = scenario
        self.gameMode = scenario == nil ? gameMode : .humanVsEngine
        let normalizedEngineDemoConfiguration = engineDemoConfiguration.normalized()
        self.engineDemoConfiguration = normalizedEngineDemoConfiguration
        self.engineDemoRandomGenerator = SeededRandomGenerator(
            seed: normalizedEngineDemoConfiguration.stress.seed
        )
        if let scenario {
            self.moveProvider = ScenarioReplayMoveProvider(scenario: scenario)
        } else {
            self.moveProvider = nil
        }
        // Store the engine move time so future searches use the current setting.
        self.engineMoveTime = Self.initialEngineMoveTime
        // Default to Stockfish because it was the original demo engine.
        self.selectedEngineKind = Self.initialEngineKind
        // UI tests can lower the minimum visible thinking time while normal demo launches keep it.
        self.minimumEngineThinkingSeconds = max(
            minimumEngineThinkingSeconds ?? Self.initialMinimumEngineThinkingSeconds,
            0
        )
        self.scenarioReplayDelaySeconds = max(
            scenarioReplayDelaySeconds ?? Self.initialScenarioReplayDelaySeconds,
            0
        )
        self.stockfishProviderFactory = stockfishProviderFactory
        self.arasanProviderFactory = arasanProviderFactory
        // Keep the selected ChessUI artwork available for menus and board updates.
        self.pieceSet = pieceSet
        // Keep the selected ChessUI board theme available for menus and board updates.
        self.boardTheme = boardTheme
        // Use the scenario's starting position when replaying PGN fixtures.
        let initialPosition = scenario?.initialPosition ?? Position.standard
        let initialFen = FENSerializer().fen(from: initialPosition)
        let initialGame = Game(position: initialPosition)
        self.positionFEN = initialFen
        self.gameStatus = initialGame.status
        self.sideToMove = initialPosition.state.turn
        self.evaluation = Self.initialEvaluation
        self.suggestionArrowCount = Self.initialSuggestionArrowCount
        // ChessUI owns the board and perspective rendering.
        self.boardModel = ChessBoardModel(
            fen: initialFen,
            perspective: playerColor,
            boardTheme: boardTheme,
            pieceSet: pieceSet
        )
        if self.gameMode == .engineVsEngine {
            self.boardModel.moveAnimationDuration = Self.engineDemoMoveAnimationDuration
        }
        // Let ChessUI report only legal moves for the side to move; the view
        // model still gates those moves to the human player's turn.
        self.boardModel.interactionMode = self.moveProvider?.isAutomaticReplay == true || self.gameMode == .engineVsEngine
            ? .readOnly
            : .legalMovesOnly
        self.boardModel.game = initialGame
    }

    /// Normal app runs use a visible thinking pause; UI tests can override it
    /// so move-flow coverage does not spend most of its time intentionally idle.
    private static var initialMinimumEngineThinkingSeconds: TimeInterval {
        let environment = ProcessInfo.processInfo.environment
        guard let delayValue = environment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_REPLY_DELAY"],
              let delay = TimeInterval(delayValue)
        else {
            return 1.0
        }

        return max(delay, 0)
    }

    /// Remaining delay required to make a search appear to take at least the minimum duration.
    static func remainingMinimumThinkingDelay(
        startedAt: Date?,
        now: Date = Date(),
        minimumDuration: TimeInterval
    ) -> TimeInterval {
        guard let startedAt else { return 0 }
        let elapsed = now.timeIntervalSince(startedAt)
        return max(0, minimumDuration - elapsed)
    }

    /// Scenario replay can run quickly in UI tests while staying visible in manual runs.
    private static var initialScenarioReplayDelaySeconds: TimeInterval {
        let environment = ProcessInfo.processInfo.environment
        guard let delayValue = environment["SWIFT_CHESS_DEMO_SCENARIO_REPLAY_DELAY"],
              let delay = TimeInterval(delayValue)
        else {
            return 0.45
        }

        return max(delay, 0)
    }

    /// Engine-vs-engine mode can start a CPU-heavy search immediately after a
    /// move. Keeping board moves instantaneous avoids stale travel overlays.
    static let engineDemoMoveAnimationDuration: Double = 0

    /// UI tests can lower the engine move time to keep smoke flows fast without
    /// changing the normal demo default.
    private static var initialEngineMoveTime: EngineMoveTime {
        let environment = ProcessInfo.processInfo.environment
        guard let moveTimeValue = environment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_MOVE_TIME_MS"],
              let moveTimeMilliseconds = Int(moveTimeValue)
        else {
            return EngineMoveTime.defaultValue
        }

        return EngineMoveTime.closest(milliseconds: moveTimeMilliseconds)
    }

    /// UI tests and manual launches can select a non-default engine explicitly.
    private static var initialEngineKind: DemoEngineKind {
        let environment = ProcessInfo.processInfo.environment
        guard let value = environment["SWIFT_CHESS_DEMO_ENGINE"]?.lowercased(),
              let engineKind = DemoEngineKind(rawValue: value)
        else {
            return .stockfish
        }

        return engineKind
    }

    /// UI tests can provide a deterministic starting evaluation without
    /// depending on live engine search output.
    private static var initialEvaluation: ChessEvaluation {
        let environment = ProcessInfo.processInfo.environment
        guard let value = environment["SWIFT_CHESS_DEMO_UI_TEST_EVALUATION"] else {
            return .unavailable
        }

        return evaluation(fromEnvironmentValue: value) ?? .unavailable
    }

    /// UI tests can start with suggestions visible without tapping the menu.
    private static var initialSuggestionArrowCount: Int {
        let environment = ProcessInfo.processInfo.environment
        guard let value = environment["SWIFT_CHESS_DEMO_UI_TEST_SUGGESTION_ARROW_COUNT"],
              let count = Int(value)
        else {
            return 0
        }

        return clampedSuggestionArrowCount(count)
    }

    /// Highest number of ranked engine suggestion lines the demo requests.
    private static let maximumSuggestionArrowCount = 3

    /// How long transient engine notices stay in the status row before normal status returns.
    private static let engineNoticeDisplaySeconds: TimeInterval = 3.5

    /// UI tests can simulate an engine `info score` update before a provider move is applied.
    private static var evaluationBeforeProviderReply: ChessEvaluation? {
        guard let value = ProcessInfo.processInfo.environment["SWIFT_CHESS_DEMO_UI_TEST_EVALUATION_BEFORE_REPLY"] else {
            return nil
        }

        return evaluation(fromEnvironmentValue: value)
    }

    private static func evaluation(fromEnvironmentValue value: String) -> ChessEvaluation? {
        let parts = value.split(separator: ":").map(String.init)
        if parts.count == 2, parts[0] == "cp", let centipawns = Int(parts[1]) {
            return .centipawns(centipawns)
        }

        if parts.count == 3, parts[0] == "mate", let moves = Int(parts[2]) {
            switch parts[1] {
            case "white":
                return .mate(moves: moves, side: .white)
            case "black":
                return .mate(moves: moves, side: .black)
            default:
                return nil
            }
        }

        return nil
    }

    private static func clampedSuggestionArrowCount(_ count: Int) -> Int {
        min(maximumSuggestionArrowCount, max(0, count))
    }

    /// Live provider for the currently selected embedded engine.
    private var selectedEngineProvider: any DemoEngineProvider {
        provider(for: selectedEngineKind)
    }

    /// Live provider for an explicit embedded engine.
    private func provider(for engineKind: DemoEngineKind) -> any DemoEngineProvider {
        switch engineKind {
        case .stockfish:
            return stockfishProvider
        case .arasan:
            return arasanProvider
        }
    }

    /// Whether the current game is an engine-vs-engine demo run.
    var isEngineDemoMode: Bool {
        gameMode == .engineVsEngine && moveProvider == nil
    }

    /// Engine selection is only meaningful for live games, not deterministic scenarios.
    var showsEngineSelection: Bool {
        moveProvider == nil && !isEngineDemoMode
    }

    /// Engine switching is safe during display-only analysis, but not while an opponent move is pending.
    var canSwitchEngine: Bool {
        showsEngineSelection
            && selectedEngineProvider.activePurpose != .opponentMove
            && pendingEngineMoveWorkItem == nil
    }

    /// Engine-vs-engine controls are enabled when no search, delayed move, or pacing timer is active.
    var canStepEngineDemo: Bool {
        isEngineDemoMode
            && engineDemoRunState == .paused
            && !hasActiveEngineDemoWork
            && isGameOngoing
    }

    /// Whether the current ChessCore status is still playable.
    var isGameOngoing: Bool {
        Self.isOngoing(gameStatus)
    }

    /// Primary demo-control title derived from the playback state.
    var engineDemoPrimaryControlTitle: String {
        switch engineDemoRunState {
        case .playing:
            return "Pause"
        case .pausingAfterCurrentMove:
            return "Pausing"
        case .stepping:
            return "Stepping"
        case .paused:
            return "Play"
        }
    }

    /// Whether the demo has an in-flight move search, delayed move application, or pacing timer.
    private var hasActiveEngineDemoWork: Bool {
        activeOpponentSearchRequest != nil
            || pendingEngineMoveWorkItem != nil
            || engineDemoPacingWorkItem != nil
    }

    /// Test-only controls are opt-in through the UI test launch environment.
    var showsUITestMoveControls: Bool {
        moveProvider?.showsUITestMoveControls == true
    }

    /// Scenario-derived coordinate moves exposed to UI tests.
    var uiTestMoveCoordinates: [String] {
        moveProvider?.uiTestMoveCoordinates(for: boardModel.game) ?? []
    }

    /// Scenario state appended to the board accessibility marker for UI tests.
    var scenarioAccessibilityValue: String {
        guard let scenario else { return "" }

        return "Scenario: \(scenario.id), "
            + "Scenario ply: \(moveRecords.count)/\(scenario.targetPly), "
            + "Scenario status: \(statusAccessibilityDescription(for: gameStatus)), "
    }

    /// Updates whether ChessUI draws rank and file coordinate labels.
    func setCoordinateLabelsVisible(_ showsCoordinateLabels: Bool) {
        self.showsCoordinateLabels = showsCoordinateLabels
    }

    /// Updates whether the visible game status reference component is shown.
    func setGameStatusVisible(_ showsGameStatus: Bool) {
        self.showsGameStatus = showsGameStatus
    }

    /// Updates whether the visible move list reference component is shown.
    func setMoveListVisible(_ showsMoveList: Bool) {
        self.showsMoveList = showsMoveList
    }

    /// Updates whether the visible evaluation bar reference component is shown.
    func setEvaluationBarVisible(_ showsEvaluationBar: Bool) {
        guard showsEvaluationBar != self.showsEvaluationBar else { return }

        self.showsEvaluationBar = showsEvaluationBar
        if showsEvaluationBar {
            refreshCurrentAnalysis(force: false)
        } else if selectedEngineProvider.activePurpose == .evaluation {
            cancelAnalysisSearch(clearSuggestions: false, queueReplacement: nil)
        }
    }

    /// Selects the embedded engine used for future live replies and suggestions.
    func setSelectedEngineKind(_ engineKind: DemoEngineKind) {
        guard engineKind != selectedEngineKind else { return }
        guard canSwitchEngine else { return }

        selectedEngineProvider.stop()
        selectedEngineKind = engineKind
        suggestedMovesByRank.removeAll()
        suggestedMovesPositionFEN = nil
        boardModel.clearArrows()
        finishOpponentSearch()
        setEngineActivity(.idle)
        refreshCurrentAnalysis(force: true)
    }

    /// Updates the engine move time used for future searches.
    func setEngineMoveTime(_ moveTime: EngineMoveTime) {
        guard moveTime != engineMoveTime else { return }

        engineMoveTime = moveTime

        if isEngineDemoMode {
            setEngineDemoMoveTime(moveTime, for: boardModel.game.position.state.turn)
            return
        }

        if boardModel.game.position.state.turn == playerColor.opposite {
            if moveProvider == nil,
               selectedEngineProvider.activePurpose == nil,
               pendingEngineMoveWorkItem == nil
            {
                scheduleEngineMove()
            }
            return
        }

        refreshCurrentAnalysis(force: true)
    }

    /// Updates how many engine-supplied move suggestion arrows the board shows.
    func setSuggestionArrowCount(_ count: Int) {
        let clampedCount = Self.clampedSuggestionArrowCount(count)
        guard clampedCount != suggestionArrowCount else { return }

        suggestionArrowCount = clampedCount
        if clampedCount == 0 {
            if selectedEngineProvider.activePurpose?.isAnalysis == true {
                cancelAnalysisSearch(
                    clearSuggestions: true,
                    queueReplacement: showsEvaluationBar ? engineSearchRequest(purpose: .evaluation) : nil
                )
            } else {
                boardModel.clearArrows()
                refreshCurrentAnalysis(force: true)
            }
        } else {
            refreshSuggestionArrows()
            refreshCurrentAnalysis(force: true)
        }
    }

    /// Toggles continuous engine-vs-engine playback.
    func toggleEngineDemoPlayback() {
        switch engineDemoRunState {
        case .playing, .stepping, .pausingAfterCurrentMove:
            pauseEngineDemo()
        case .paused:
            playEngineDemo()
        }
    }

    /// Starts continuous engine-vs-engine playback from the current position.
    func playEngineDemo() {
        guard isEngineDemoMode, isGameOngoing else { return }

        engineDemoRunState = .playing
        guard !hasActiveEngineDemoWork else { return }
        scheduleEngineMove()
    }

    /// Pauses engine-vs-engine playback after the current in-flight move, if any.
    func pauseEngineDemo() {
        guard isEngineDemoMode else { return }

        if let engineDemoPacingWorkItem {
            engineDemoPacingWorkItem.cancel()
            self.engineDemoPacingWorkItem = nil
            engineDemoRunState = .paused
            setEngineActivity(.idle)
            return
        }

        if activeOpponentSearchRequest != nil || pendingEngineMoveWorkItem != nil {
            engineDemoRunState = .pausingAfterCurrentMove
        } else {
            engineDemoRunState = .paused
            setEngineActivity(.idle)
        }
    }

    /// Applies exactly one engine-vs-engine move and then returns to paused state.
    func stepEngineDemo() {
        guard canStepEngineDemo else { return }

        engineDemoRunState = .stepping
        scheduleEngineMove()
    }

    /// Updates the engine-vs-engine pacing used after future moves are applied.
    func setEngineDemoPacing(_ pacing: EngineDemoPacing) {
        guard isEngineDemoMode, pacing != engineDemoConfiguration.pacing else { return }

        updateEngineDemoConfiguration { configuration in
            configuration.pacing = pacing
        }

        if engineDemoRunState == .playing, engineDemoPacingWorkItem != nil {
            engineDemoPacingWorkItem?.cancel()
            engineDemoPacingWorkItem = nil
            scheduleNextEngineDemoMoveAfterPacing()
        }
    }

    /// Updates the configured engine for one demo side.
    func setEngineDemoEngineKind(_ engineKind: DemoEngineKind, for side: PieceColor) {
        guard isEngineDemoMode else { return }

        updateEngineDemoConfiguration { configuration in
            switch side {
            case .white:
                configuration.white.engineKind = engineKind
            case .black:
                configuration.black.engineKind = engineKind
            }
        }
        syncSelectedEngineToCurrentEngineDemoSideIfIdle()
    }

    /// Updates the configured move time for one demo side.
    func setEngineDemoMoveTime(_ moveTime: EngineMoveTime, for side: PieceColor) {
        guard isEngineDemoMode else { return }

        updateEngineDemoConfiguration { configuration in
            switch side {
            case .white:
                configuration.white.moveTime = moveTime
            case .black:
                configuration.black.moveTime = moveTime
            }
        }
        syncSelectedEngineToCurrentEngineDemoSideIfIdle()
    }

    /// Enables or disables engine-vs-engine stress randomization.
    func setEngineDemoStressEnabled(_ isEnabled: Bool) {
        guard isEngineDemoMode else { return }

        updateEngineDemoConfiguration(resetRandomGenerator: true) { configuration in
            configuration.stress.isEnabled = isEnabled
        }
    }

    /// Enables or disables per-move engine randomization for stress mode.
    func setEngineDemoRandomizesEngineEachMove(_ randomizesEngineEachMove: Bool) {
        guard isEngineDemoMode else { return }

        updateEngineDemoConfiguration(resetRandomGenerator: true) { configuration in
            configuration.stress.randomizesEngineEachMove = randomizesEngineEachMove
        }
    }

    /// Enables or disables per-move move-time randomization for stress mode.
    func setEngineDemoRandomizesMoveTimeEachMove(_ randomizesMoveTimeEachMove: Bool) {
        guard isEngineDemoMode else { return }

        updateEngineDemoConfiguration(resetRandomGenerator: true) { configuration in
            configuration.stress.randomizesMoveTimeEachMove = randomizesMoveTimeEachMove
        }
    }

    /// Updates the minimum move time used by stress mode.
    func setEngineDemoStressMinimumMoveTime(_ moveTime: EngineMoveTime) {
        guard isEngineDemoMode else { return }

        updateEngineDemoConfiguration(resetRandomGenerator: true) { configuration in
            configuration.stress.minimumMoveTime = moveTime
        }
    }

    /// Updates the maximum move time used by stress mode.
    func setEngineDemoStressMaximumMoveTime(_ moveTime: EngineMoveTime) {
        guard isEngineDemoMode else { return }

        updateEngineDemoConfiguration(resetRandomGenerator: true) { configuration in
            configuration.stress.maximumMoveTime = moveTime
        }
    }

    /// Selects a move-list record without changing the board position.
    func selectMoveRecord(_ record: ChessMoveRecord) {
        selectedMovePly = record.ply
    }

    /// Starts the game loop on first appearance.
    func startIfNeeded() {
        // Guard so repeated `onAppear` calls do not restart the engine.
        guard !didStart else { return }
        didStart = true
        if isEngineDemoMode {
            boardModel.clearArrows()
            syncSelectedEngineToCurrentEngineDemoSideIfIdle()
            _ = checkForGameEnd()
            return
        }
        if moveProvider?.isAutomaticReplay == true {
            startAutomaticReplay()
            return
        }
        // If the provider supplies the side to move, let it make the first move.
        if moveProvider != nil, boardModel.game.position.state.turn != playerColor {
            scheduleEngineMove()
        } else if playerColor == .black {
            scheduleEngineMove()
        } else {
            refreshCurrentAnalysis(force: false)
        }
    }

    /// Receives a move from ChessUI when the user interacts with the UI.
    func handleUserMove(move: Move, isLegal: Bool) {
        guard !isEngineDemoMode else { return }
        guard moveProvider?.isAutomaticReplay != true else { return }
        // Ignore illegal gestures, and ignore moves when it's not the user's turn.
        guard isLegal else { return }
        guard boardModel.game.position.state.turn == playerColor else { return }
        // A real user move invalidates analysis arrows for the previous position.
        cancelAnalysisSearch(clearSuggestions: true, queueReplacement: nil)
        // Apply the move in ChessCore and refresh the board UI.
        guard applyMove(move: move) else { return }
        // Stop here if the move ended the game.
        if checkForGameEnd() { return }
        // Otherwise, ask the selected engine for a reply and hold only fast results until
        // the minimum visible thinking time has elapsed.
        scheduleEngineMove()
    }

    /// Test-only move entry point used when simulator coordinate taps are too
    /// brittle for a UI smoke test.
    func performUITestMove(_ coordinateMove: String) {
        guard moveProvider?.showsUITestMoveControls == true,
              let move = try? Move(string: coordinateMove)
        else {
            return
        }

        handleUserMove(move: move, isLegal: boardModel.game.legalMoves.contains(move))
    }

    /// Ends the game immediately; used when the user resigns.
    func resign() {
        // We simply stop the engine; the UI dismisses in the view layer.
        stopEngineIfNeeded()
    }

    /// Requests a confirmation alert before resigning.
    func requestResignConfirmation() {
        activeAlert = .resignConfirmation
    }

    /// Claims a draw offered by ChessCore's current game status.
    func claimDraw(_ claim: GameDrawClaim) {
        do {
            try boardModel.game.claimDraw(claim)
        } catch {
            endGame(title: "Draw Claim Error", message: "That draw claim is not available.")
            return
        }

        refreshGameSnapshot()
        endGame(title: drawTitle(for: drawReason(for: claim)), message: "Draw")
    }

    /// Called when the view disappears; ensures background work stops.
    func cleanup() {
        stopEngineIfNeeded()
    }

    /// Starts automatic scenario playback from the current position.
    private func startAutomaticReplay() {
        boardModel.clearArrows()
        if checkForGameEnd() { return }
        scheduleAutomaticReplayMove()
    }

    /// Schedules the next automatic scenario move.
    private func scheduleAutomaticReplayMove() {
        guard moveProvider?.isAutomaticReplay == true else { return }
        scenarioReplayWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scenarioReplayWorkItem = nil
            self.applyNextAutomaticReplayMove()
        }

        scenarioReplayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + scenarioReplayDelaySeconds, execute: workItem)
    }

    /// Applies one scenario move through the same path used by live gameplay.
    private func applyNextAutomaticReplayMove() {
        guard let moveProvider, moveProvider.isAutomaticReplay else { return }
        if checkForGameEnd() { return }

        guard scenario.map({ moveRecords.count < $0.targetPly }) ?? false else {
            return
        }

        guard let move = moveProvider.nextMove(for: boardModel.game, ply: moveRecords.count) else {
            endGame(title: "Scenario Error", message: "The scenario did not provide a legal move.")
            return
        }

        guard applyMove(
            move: move,
            failureTitle: "Scenario Error",
            failureMessage: "The scenario move is not legal in the current position."
        ) else {
            return
        }

        if checkForGameEnd() { return }

        if scenario.map({ moveRecords.count < $0.targetPly }) == true {
            scheduleAutomaticReplayMove()
        }
    }

    /// Applies a legal move to the ChessCore game and updates the board UI with FEN.
    @discardableResult
    private func applyMove(
        move: Move,
        failureTitle: String = "Move Error",
        failureMessage: String = "The move is not legal in the current position."
    ) -> Bool {
        do {
            let record = try moveRecordBuilder.record(
                for: move,
                in: boardModel.game,
                ply: moveRecords.count + 1
            )
            // ChessCore updates internal rules state, move counters, and repetition history here.
            try boardModel.game.applyLegal(move: move)
            moveRecords.append(record)
            selectedMovePly = record.ply
        } catch {
            endGame(title: failureTitle, message: failureMessage)
            return false
        }

        // Preserve the complete Game object because `setFEN` rebuilds a board-only game for rendering.
        let updatedGame = boardModel.game.copy()
        // Serialize the new position into FEN for ChessUI.
        let fen = fenSerializer.fen(from: updatedGame.position)
        // Keep a black-box state marker available to UI tests.
        positionFEN = fen
        // ChessUI consumes the new FEN plus the move that produced it, then
        // owns move animation and last-move highlighting.
        boardModel.setFEN(fen, animatedMove: move)
        // Restore ChessCore's full game history for status, repetition, and draw-claim APIs.
        boardModel.game = updatedGame
        refreshGameSnapshot(from: updatedGame)
        return true
    }

    /// Starts the opponent reply flow immediately.
    private func scheduleEngineMove() {
        pendingEngineMoveWorkItem?.cancel()
        pendingEngineMoveWorkItem = nil
        requestEngineMove()
    }

    /// Requests a selected-engine reply for the current position.
    private func requestEngineMove() {
        if isEngineDemoMode {
            requestEngineDemoMove()
            return
        }

        // Only search when it is the engine's turn.
        guard boardModel.game.position.state.turn == playerColor.opposite else { return }

        boardModel.clearArrows()

        if let moveProvider {
            beginOpponentSearch(engineKind: selectedEngineKind, request: nil)
            applyMoveProviderOpponentMove(moveProvider)
            return
        }

        let request = engineSearchRequest(purpose: .opponentMove)
        beginOpponentSearch(engineKind: request.engineKind, request: request)
        selectedEngineProvider.startOrQueueSearch(request)
    }

    /// Requests the next engine-vs-engine move for the side to move.
    private func requestEngineDemoMove() {
        guard isEngineDemoMode, Self.isOngoing(boardModel.game.status) else { return }

        let moveConfiguration = nextEngineDemoMoveConfiguration()
        engineDemoLastMoveConfiguration = moveConfiguration
        if selectedEngineKind != moveConfiguration.engineKind {
            selectedEngineProvider.stop()
        }
        selectedEngineKind = moveConfiguration.engineKind
        engineMoveTime = moveConfiguration.moveTime
        boardModel.clearArrows()

        let request = engineSearchRequest(
            purpose: .opponentMove,
            engineKind: moveConfiguration.engineKind,
            moveTime: moveConfiguration.moveTime
        )
        beginOpponentSearch(engineKind: request.engineKind, request: request)
        provider(for: moveConfiguration.engineKind).startOrQueueSearch(request)
    }

    /// Sets engine activity and clears transient notices after a short display interval.
    private func setEngineActivity(_ activity: EngineActivityState) {
        engineActivityClearWorkItem?.cancel()
        engineActivityClearWorkItem = nil
        engineActivity = activity

        guard case .notice = activity else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.engineActivityClearWorkItem = nil

            guard case .notice = self.engineActivity else { return }
            self.engineActivity = .idle
        }

        engineActivityClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.engineNoticeDisplaySeconds,
            execute: workItem
        )
    }

    /// Records user-visible state for a newly started opponent reply.
    private func beginOpponentSearch(
        engineKind: DemoEngineKind,
        request: EngineSearchRequest?
    ) {
        opponentSearchStartedAt = Date()
        opponentSearchTimedOut = false
        latestOpponentPrincipalVariationMove = nil
        activeOpponentSearchRequest = request
        setEngineActivity(.thinking(engine: engineKind))
    }

    /// Applies a deterministic provider move for scenario-backed UI tests.
    private func applyMoveProviderOpponentMove(_ moveProvider: GameMoveProvider) {
        guard let move = moveProvider.nextMove(for: boardModel.game, ply: moveRecords.count) else {
            endGame(title: "Draw", message: "No legal moves remain.")
            return
        }

        if let providerEvaluation = Self.evaluationBeforeProviderReply {
            evaluation = providerEvaluation
        }

        scheduleOpponentMoveApplication(move: move)
    }

    /// Handles typed output from the selected engine provider.
    private func receiveEngineProviderEvent(_ event: EngineProviderEvent) {
        switch event {
        case .output(let output, let request):
            guard shouldAcceptEngineEvent(for: request) else { return }

            switch request.purpose {
            case .opponentMove:
                receiveOpponentEngineOutput(output, request: request)
            case .suggestions:
                receiveSuggestionEngineOutput(output, request: request)
            case .evaluation:
                receiveEvaluationEngineOutput(output, request: request)
            }

        case .timeout(let request):
            guard shouldAcceptEngineEvent(for: request) else { return }
            handleEngineTimeout(request)

        case .timeoutWithoutBestMove(let request):
            guard shouldAcceptEngineEvent(for: request) else { return }
            handleEngineTimeoutWithoutBestMove(request)

        case .failure(let message, let request):
            guard shouldAcceptEngineEvent(for: request) else { return }
            handleEngineFailure(message: message, request: request)
        }
    }

    /// Ignores stale output from an engine, move time, or position that is no longer the active analysis target.
    private func shouldAcceptEngineEvent(for request: EngineSearchRequest) -> Bool {
        switch request.purpose {
        case .opponentMove:
            guard let activeOpponentSearchRequest else { return false }
            return request == activeOpponentSearchRequest

        case .suggestions:
            guard request.engineKind == selectedEngineKind else { return false }
            return suggestionArrowCount > 0
                && request.moveTimeMilliseconds == engineMoveTime.rawValue
                && request.fen == fenSerializer.fen(from: boardModel.game.position)

        case .evaluation:
            guard request.engineKind == selectedEngineKind else { return false }
            return suggestionArrowCount == 0
                && showsEvaluationBar
                && request.moveTimeMilliseconds == engineMoveTime.rawValue
                && request.fen == fenSerializer.fen(from: boardModel.game.position)
        }
    }

    /// Handles parsed UCI output from an opponent-move search.
    private func receiveOpponentEngineOutput(
        _ output: UCIParsedLine,
        request: EngineSearchRequest
    ) {
        switch output {
        case .info(let info):
            if let score = info.whiteRelativeScore(sideToMove: request.sideToMove) {
                evaluation = chessEvaluation(from: score)
            }
            updateOpponentFallbackMove(from: info)

        case .bestMove(let bestMove):
            let move = bestMove.move ?? latestOpponentPrincipalVariationMove
            let timeoutNotice = opponentSearchTimedOut
                ? "\(request.engineKind.displayName) timed out; played the best move found so far."
                : nil
            scheduleOpponentMoveApplication(
                move: move,
                engineKind: request.engineKind,
                statusNotice: timeoutNotice
            )

        case .id, .option, .uciOK, .readyOK, .copyProtection, .registration, .unknown:
            return
        }
    }

    /// Handles parsed UCI output from an evaluation-only search.
    private func receiveEvaluationEngineOutput(
        _ output: UCIParsedLine,
        request: EngineSearchRequest
    ) {
        switch output {
        case .info(let info):
            if let score = info.whiteRelativeScore(sideToMove: request.sideToMove) {
                evaluation = chessEvaluation(from: score)
            }

        case .bestMove:
            return

        case .id, .option, .uciOK, .readyOK, .copyProtection, .registration, .unknown:
            return
        }
    }

    /// Handles parsed UCI output from a move-suggestion search.
    private func receiveSuggestionEngineOutput(
        _ output: UCIParsedLine,
        request: EngineSearchRequest
    ) {
        switch output {
        case .info(let info):
            if let score = info.whiteRelativeScore(sideToMove: request.sideToMove) {
                evaluation = chessEvaluation(from: score)
            }

            if suggestionArrowCount > 0 {
                updateSuggestionArrow(from: info, positionFEN: request.fen)
            }

        case .bestMove(let bestMove):
            if suggestionArrowCount > 0,
               suggestedMovesByRank.isEmpty,
               let move = bestMove.move
            {
                suggestedMovesByRank[1] = move
                suggestedMovesPositionFEN = request.fen
                refreshSuggestionArrows()
            }

        case .id, .option, .uciOK, .readyOK, .copyProtection, .registration, .unknown:
            return
        }
    }

    /// Handles the engine move after receiving a parsed `bestmove` line.
    private func receiveEngineMove(move: Move?, engineKind: DemoEngineKind, statusNotice: String? = nil) {
        // A nil move means the engine has no legal move.
        guard let move else {
            let message = statusNotice ?? (opponentSearchTimedOut
                ? "\(engineKind.displayName) timed out before returning a move."
                : "\(engineKind.displayName) did not return a move.")
            finishOpponentSearchWithoutMove(message: message)
            return
        }

        guard applyMove(
            move: move,
            failureTitle: "Engine Error",
            failureMessage: "\(engineKind.displayName) returned an illegal move."
        ) else {
            return
        }

        // Check if the engine's move ended the game.
        if checkForGameEnd() {
            return
        }

        if isEngineDemoMode {
            setEngineActivity(statusNotice.map(EngineActivityState.notice) ?? .idle)
            handleEngineDemoMoveApplied()
            return
        }

        setEngineActivity(statusNotice.map(EngineActivityState.notice) ?? .idle)
        refreshCurrentAnalysis(force: false)
    }

    /// Handles provider-reported engine search timeouts.
    private func handleEngineTimeout(_ request: EngineSearchRequest) {
        if request.purpose == .suggestions {
            setEngineActivity(.notice("Suggestion analysis timed out."))
            return
        }

        if request.purpose == .evaluation {
            setEngineActivity(.notice("Evaluation analysis timed out."))
            return
        }

        opponentSearchTimedOut = true
        setEngineActivity(.timeoutWaiting(engine: request.engineKind))
    }

    /// Handles a timeout where `stop` did not produce a `bestmove` quickly.
    private func handleEngineTimeoutWithoutBestMove(_ request: EngineSearchRequest) {
        if request.purpose == .suggestions {
            setEngineActivity(.notice("Suggestion analysis timed out before returning a move."))
            return
        }

        if request.purpose == .evaluation {
            setEngineActivity(.notice("Evaluation analysis timed out before returning a score."))
            return
        }

        if let move = latestOpponentPrincipalVariationMove {
            scheduleOpponentMoveApplication(
                move: move,
                engineKind: request.engineKind,
                statusNotice: "\(request.engineKind.displayName) timed out; played the best move found so far."
            )
        } else {
            finishOpponentSearchWithoutMove(
                message: "\(request.engineKind.displayName) timed out before returning a move."
            )
        }
    }

    /// Handles provider setup failures without mutating the board.
    private func handleEngineFailure(message: String, request: EngineSearchRequest) {
        if request.purpose == .suggestions {
            setEngineActivity(.notice("\(request.engineKind.displayName) analysis failed: \(message)"))
            return
        }

        if request.purpose == .evaluation {
            setEngineActivity(.notice("\(request.engineKind.displayName) evaluation failed: \(message)"))
            return
        }

        finishOpponentSearchWithoutMove(message: "\(request.engineKind.displayName) failed: \(message)")
    }

    /// Caches the latest legal first principal-variation move for timeout fallback.
    private func updateOpponentFallbackMove(from info: UCIInfoLine) {
        guard info.multipv == nil || info.multipv == 1,
              let move = info.principalVariation.first,
              boardModel.game.legalMoves.contains(move)
        else {
            return
        }

        latestOpponentPrincipalVariationMove = move
    }

    /// Applies the opponent move after any remaining minimum thinking time.
    private func scheduleOpponentMoveApplication(
        move: Move?,
        engineKind: DemoEngineKind? = nil,
        statusNotice: String? = nil
    ) {
        pendingEngineMoveWorkItem?.cancel()
        let engineKind = engineKind ?? selectedEngineKind

        let remainingDelay = isEngineDemoMode
            ? 0
            : Self.remainingMinimumThinkingDelay(
                startedAt: opponentSearchStartedAt,
                minimumDuration: minimumEngineThinkingSeconds
            )

        guard remainingDelay > 0 else {
            finishOpponentSearch()
            receiveEngineMove(move: move, engineKind: engineKind, statusNotice: statusNotice)
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingEngineMoveWorkItem = nil
            self.finishOpponentSearch()
            self.receiveEngineMove(move: move, engineKind: engineKind, statusNotice: statusNotice)
        }

        pendingEngineMoveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + remainingDelay, execute: workItem)
    }

    /// Clears transient search metadata after an opponent search produces a move.
    private func finishOpponentSearch() {
        opponentSearchStartedAt = nil
        opponentSearchTimedOut = false
        latestOpponentPrincipalVariationMove = nil
        activeOpponentSearchRequest = nil
    }

    /// Leaves the game alive when the engine failed to provide a recoverable move.
    private func finishOpponentSearchWithoutMove(message: String) {
        pendingEngineMoveWorkItem?.cancel()
        pendingEngineMoveWorkItem = nil
        finishOpponentSearch()
        if isEngineDemoMode {
            engineDemoRunState = .paused
        }
        setEngineActivity(.notice(message))
    }

    /// Advances or pauses the engine-vs-engine loop after one move has been applied.
    private func handleEngineDemoMoveApplied() {
        switch engineDemoRunState {
        case .playing:
            scheduleNextEngineDemoMoveAfterPacing()

        case .stepping, .pausingAfterCurrentMove:
            engineDemoRunState = .paused

        case .paused:
            return
        }
    }

    /// Schedules the next automatic engine-vs-engine search after the configured post-move delay.
    private func scheduleNextEngineDemoMoveAfterPacing() {
        guard isEngineDemoMode, engineDemoRunState == .playing, isGameOngoing else { return }

        engineDemoPacingWorkItem?.cancel()
        let delay = engineDemoConfiguration.pacing.delay
        guard delay > 0 else {
            scheduleEngineMove()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.engineDemoPacingWorkItem = nil
            guard self.engineDemoRunState == .playing else { return }
            self.scheduleEngineMove()
        }

        engineDemoPacingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    /// Cancels any running engine search without assuming it was active.
    private func stopEngineIfNeeded() {
        suggestedMovesByRank.removeAll()
        suggestedMovesPositionFEN = nil
        boardModel.clearArrows()
        // Cancel any delayed application of a fast engine reply.
        pendingEngineMoveWorkItem?.cancel()
        pendingEngineMoveWorkItem = nil
        finishOpponentSearch()
        engineDemoPacingWorkItem?.cancel()
        engineDemoPacingWorkItem = nil
        engineDemoRunState = .paused
        setEngineActivity(.idle)
        // Cancel automatic scenario replay, if active.
        scenarioReplayWorkItem?.cancel()
        scenarioReplayWorkItem = nil
        moveProvider?.cancel()
        stockfishProvider.stop()
        arasanProvider.stop()
    }

    /// Evaluates draw and win conditions using ChessCore state.
    private func checkForGameEnd() -> Bool {
        switch boardModel.game.status {
        case .checkmate(let winner):
            let message = checkmateMessage(winner: winner)
            endGame(title: "Checkmate", message: message)
            return true

        case .draw(let reason):
            endGame(title: drawTitle(for: reason), message: "Draw")
            return true

        case .ongoing(let drawClaims):
            guard isEngineDemoMode,
                  let drawClaim = automaticEngineDemoDrawClaim(from: drawClaims)
            else {
                return false
            }

            do {
                try boardModel.game.claimDraw(drawClaim)
            } catch {
                return false
            }

            refreshGameSnapshot()
            endGame(title: drawTitle(for: drawReason(for: drawClaim)), message: "Draw")
            return true
        }
    }

    /// Chooses a claimable draw to auto-claim in engine-vs-engine mode.
    private func automaticEngineDemoDrawClaim(from drawClaims: Set<GameDrawClaim>) -> GameDrawClaim? {
        if drawClaims.contains(.threefoldRepetition) {
            return .threefoldRepetition
        }

        if drawClaims.contains(.fiftyMoveRule) {
            return .fiftyMoveRule
        }

        return nil
    }

    /// Presents the game result and stops the engine.
    private func endGame(title: String, message: String) {
        // Always stop the engine before presenting an end-state.
        stopEngineIfNeeded()
        boardModel.clearArrows()
        activeAlert = .result(GameResult(title: title, message: message))
    }

    /// Starts or refreshes selected-engine analysis for the current player-turn position.
    private func refreshCurrentAnalysis(force: Bool) {
        guard !isEngineDemoMode else {
            boardModel.clearArrows()
            return
        }

        guard boardModel.game.position.state.turn == playerColor else {
            boardModel.clearArrows()
            return
        }

        guard selectedEngineProvider.activePurpose != .opponentMove else { return }

        if suggestionArrowCount > 0 {
            refreshSuggestionAnalysis(force: force)
            return
        }

        boardModel.clearArrows()

        guard showsEvaluationBar, moveProvider == nil else {
            if selectedEngineProvider.activePurpose == .evaluation {
                cancelAnalysisSearch(clearSuggestions: false, queueReplacement: nil)
            }
            return
        }

        let request = engineSearchRequest(purpose: .evaluation)
        if force || selectedEngineProvider.activePurpose == .evaluation {
            startOrReplaceAnalysisSearch(request, clearSuggestions: false)
        } else if selectedEngineProvider.activePurpose == nil {
            selectedEngineProvider.startOrQueueSearch(request)
        }
    }

    /// Starts or refreshes a move-suggestion search when the player is on move.
    private func refreshSuggestionAnalysis(force: Bool) {
        guard suggestionArrowCount > 0 else { return }

        let fen = fenSerializer.fen(from: boardModel.game.position)
        if !force, suggestedMovesPositionFEN == fen {
            refreshSuggestionArrows()
            return
        }

        if !force,
           selectedEngineProvider.activePurpose == .suggestions,
           selectedEngineProvider.activeFEN == fen
        {
            refreshSuggestionArrows()
            return
        }

        if let moveProvider {
            applyMoveProviderSuggestionArrows(moveProvider)
        } else {
            startOrReplaceAnalysisSearch(
                engineSearchRequest(purpose: .suggestions),
                clearSuggestions: true
            )
        }
    }

    /// Cancels or replaces a display-only analysis search, preserving opponent searches.
    private func cancelAnalysisSearch(clearSuggestions: Bool, queueReplacement: EngineSearchRequest?) {
        selectedEngineProvider.cancelAnalysisSearch(queueReplacement: queueReplacement)
        suggestedMovesByRank.removeAll()
        suggestedMovesPositionFEN = nil

        if clearSuggestions {
            boardModel.clearArrows()
        }
    }

    /// Replaces any running analysis search with a new request.
    private func startOrReplaceAnalysisSearch(_ request: EngineSearchRequest, clearSuggestions: Bool) {
        guard selectedEngineProvider.activePurpose != .opponentMove else { return }

        if selectedEngineProvider.activePurpose?.isAnalysis == true {
            cancelAnalysisSearch(clearSuggestions: clearSuggestions, queueReplacement: request)
        } else {
            startEngineSearch(request)
        }
    }

    /// Starts one engine search after clearing stale suggestion state.
    private func startEngineSearch(_ request: EngineSearchRequest) {
        if request.purpose == .suggestions {
            suggestedMovesByRank.removeAll()
            suggestedMovesPositionFEN = nil
            boardModel.clearArrows()
        }

        selectedEngineProvider.startOrQueueSearch(request)
    }

    /// Captures the current board position and search settings in one immutable request.
    private func engineSearchRequest(
        purpose: EngineSearchPurpose,
        engineKind: DemoEngineKind? = nil,
        moveTime: EngineMoveTime? = nil
    ) -> EngineSearchRequest {
        let resolvedMoveTime = moveTime ?? engineMoveTime
        return EngineSearchRequest(
            engineKind: engineKind ?? selectedEngineKind,
            purpose: purpose,
            fen: fenSerializer.fen(from: boardModel.game.position),
            sideToMove: boardModel.game.position.state.turn,
            moveTimeMilliseconds: resolvedMoveTime.rawValue,
            multiPVCount: purpose == .suggestions ? Self.maximumSuggestionArrowCount : 1,
            safetyTimeoutSeconds: nil
        )
    }

    /// Chooses the concrete engine and move time for the current engine-vs-engine move.
    private func nextEngineDemoMoveConfiguration() -> EngineDemoMoveConfiguration {
        let side = boardModel.game.position.state.turn
        var sideConfiguration = engineDemoConfiguration.sideConfiguration(for: side)
        let stress = engineDemoConfiguration.stress.normalized()

        if stress.isEnabled {
            if stress.randomizesEngineEachMove,
               let randomizedEngine = DemoEngineKind.allCases.randomElement(using: &engineDemoRandomGenerator)
            {
                sideConfiguration.engineKind = randomizedEngine
            }

            if stress.randomizesMoveTimeEachMove {
                let allowedMoveTimes = EngineMoveTime.allCases.filter {
                    $0.rawValue >= stress.minimumMoveTime.rawValue
                        && $0.rawValue <= stress.maximumMoveTime.rawValue
                }
                sideConfiguration.moveTime = allowedMoveTimes.randomElement(using: &engineDemoRandomGenerator)
                    ?? sideConfiguration.moveTime
            }
        }

        return EngineDemoMoveConfiguration(
            side: side,
            engineKind: sideConfiguration.engineKind,
            moveTime: sideConfiguration.moveTime
        )
    }

    /// Applies a normalized engine-vs-engine configuration mutation.
    private func updateEngineDemoConfiguration(
        resetRandomGenerator: Bool = false,
        _ update: (inout EngineDemoConfiguration) -> Void
    ) {
        var updatedConfiguration = engineDemoConfiguration
        update(&updatedConfiguration)
        updatedConfiguration = updatedConfiguration.normalized()

        let shouldResetRandomGenerator = resetRandomGenerator
            || updatedConfiguration.stress.seed != engineDemoConfiguration.stress.seed
        engineDemoConfiguration = updatedConfiguration

        if shouldResetRandomGenerator {
            engineDemoRandomGenerator = SeededRandomGenerator(seed: updatedConfiguration.stress.seed)
        }
    }

    /// Keeps board accessibility and status metadata aligned with the next demo side while idle.
    private func syncSelectedEngineToCurrentEngineDemoSideIfIdle() {
        guard isEngineDemoMode, !hasActiveEngineDemoWork else { return }

        let configuration = engineDemoConfiguration.sideConfiguration(for: boardModel.game.position.state.turn)
        selectedEngineKind = configuration.engineKind
        engineMoveTime = configuration.moveTime
    }

    /// Creates deterministic suggestion arrows from a non-live-engine provider.
    private func applyMoveProviderSuggestionArrows(_ moveProvider: GameMoveProvider) {
        guard suggestionArrowCount > 0,
              boardModel.game.position.state.turn == playerColor
        else {
            boardModel.clearArrows()
            return
        }

        let rankedMoves = moveProvider.suggestionMoves(
            for: boardModel.game,
            maxCount: Self.maximumSuggestionArrowCount
        )

        suggestedMovesByRank = Dictionary(
            uniqueKeysWithValues: rankedMoves
                .prefix(Self.maximumSuggestionArrowCount)
                .enumerated()
                .map { index, move in (index + 1, move) }
        )
        suggestedMovesPositionFEN = fenSerializer.fen(from: boardModel.game.position)
        refreshSuggestionArrows()
    }

    /// Updates one suggested move from a parsed `info multipv` line.
    private func updateSuggestionArrow(from info: UCIInfoLine, positionFEN: String) {
        guard let move = info.principalVariation.first else { return }

        let rank = info.multipv ?? 1
        guard (1...Self.maximumSuggestionArrowCount).contains(rank) else { return }

        suggestedMovesByRank[rank] = move
        suggestedMovesPositionFEN = positionFEN
        refreshSuggestionArrows()
    }

    /// Maps ranked suggested moves into ChessUI board arrows.
    private func refreshSuggestionArrows() {
        guard suggestionArrowCount > 0 else {
            boardModel.clearArrows()
            return
        }

        boardModel.arrows = (1...suggestionArrowCount).compactMap { rank in
            guard let move = suggestedMovesByRank[rank] else { return nil }
            return suggestionArrow(for: move, rank: rank)
        }
    }

    /// Creates the ChessUI arrow for one suggested move.
    private func suggestionArrow(for move: Move, rank: Int) -> ChessBoardArrow? {
        ChessBoardArrow(
            from: move.from.coordinate,
            to: move.to.coordinate,
            style: suggestionArrowStyle(for: rank),
            label: suggestionArrowLabel(for: move, rank: rank)
        )
    }

    /// Built-in ranked arrow styles stop at three suggestions.
    private func suggestionArrowStyle(for rank: Int) -> ChessBoardArrowStyle {
        switch rank {
        case 1:
            return .primarySuggestion
        case 2:
            return .secondarySuggestion
        default:
            return .tertiarySuggestion
        }
    }

    /// Accessibility text that identifies each suggestion rank.
    private func suggestionArrowLabel(for move: Move, rank: Int) -> String {
        let rankText: String
        switch rank {
        case 1:
            rankText = "Best suggestion"
        case 2:
            rankText = "Second suggestion"
        default:
            rankText = "Third suggestion"
        }

        return "\(rankText) \(move.from.coordinate) to \(move.to.coordinate)"
    }

    /// Converts a claimable rule into the terminal draw reason shown by the UI.
    private func drawReason(for drawClaim: GameDrawClaim) -> GameDrawReason {
        switch drawClaim {
        case .fiftyMoveRule:
            return .fiftyMoveRule
        case .threefoldRepetition:
            return .threefoldRepetition
        }
    }

    /// Refreshes published state derived from the backing ChessCore game.
    private func refreshGameSnapshot(from game: Game? = nil) {
        let game = game ?? boardModel.game
        gameStatus = game.status
        sideToMove = game.position.state.turn
    }

    /// Maps reusable ChessUCI score data into ChessUI's display model.
    private func chessEvaluation(from score: UCIWhiteScore) -> ChessEvaluation {
        switch score {
        case .centipawns(let centipawns):
            return .centipawns(centipawns)
        case .mate(let moves, let side):
            return .mate(moves: moves, side: side)
        }
    }

    /// User-facing alert title for a terminal draw.
    private func drawTitle(for reason: GameDrawReason) -> String {
        switch reason {
        case .stalemate:
            return "Stalemate"
        case .insufficientMaterial:
            return "Draw by insufficient material"
        case .deadPosition:
            return "Draw by dead position"
        case .seventyFiveMoveRule:
            return "Draw by 75-move rule"
        case .fivefoldRepetition:
            return "Draw by repetition"
        case .fiftyMoveRule:
            return "Draw by 50-move rule"
        case .threefoldRepetition:
            return "Draw by repetition"
        }
    }

    /// User-facing checkmate message for live games and deterministic scenarios.
    private func checkmateMessage(winner: PieceColor) -> String {
        if moveProvider?.isAutomaticReplay == true || isEngineDemoMode {
            return "\(winner.displayName) wins"
        }

        return winner == playerColor ? "You win" : "\(selectedEngineKind.displayName) wins"
    }

    /// Accessibility-friendly status text used by scenario UI tests.
    private func statusAccessibilityDescription(for status: GameStatus) -> String {
        switch status {
        case .ongoing:
            return "Ongoing"
        case .checkmate(let winner):
            return "Checkmate, \(winner.displayName) wins"
        case .draw(let reason):
            return "Draw, \(drawTitle(for: reason))"
        }
    }

    /// Pattern-matches ChessCore's ongoing status without caring about available draw claims.
    private static func isOngoing(_ status: GameStatus) -> Bool {
        switch status {
        case .ongoing:
            return true
        case .checkmate, .draw:
            return false
        }
    }
}

private extension PieceColor {
    var displayName: String {
        switch self {
        case .white:
            return "White"
        case .black:
            return "Black"
        }
    }
}
