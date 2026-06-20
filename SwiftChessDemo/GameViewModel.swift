//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and StockfishEmbedded.
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
/// - StockfishMoveProvider isolates StockfishEmbedded and UCI search lifecycle.
final class GameViewModel: ObservableObject {
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
    /// Stockfish search depth used for future engine and suggestion searches.
    @Published private(set) var engineDepth: Int
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

    /// The human player's color; used to gate whose turn it is.
    let playerColor: PieceColor
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
    /// Work item used to wait briefly before starting an engine search.
    private var engineRequestDelayWorkItem: DispatchWorkItem?
    /// Work item used to advance automatic scenario replay.
    private var scenarioReplayWorkItem: DispatchWorkItem?
    /// Latest first move for each one-based MultiPV rank.
    private var suggestedMovesByRank: [Int: Move] = [:]
    /// FEN for the cached suggestion ranks.
    private var suggestedMovesPositionFEN: String?
    /// Ensures we only start the engine once when the view appears.
    private var didStart = false
    /// Cosmetic delay before asking Stockfish for a reply, so the demo feels like the engine is thinking.
    private let engineReplyDelaySeconds: TimeInterval
    /// Delay between moves during automatic scenario replay.
    private let scenarioReplayDelaySeconds: TimeInterval
    /// Stockfish-backed move and analysis provider for normal gameplay.
    private lazy var stockfishProvider = StockfishMoveProvider { [weak self] event in
        self?.receiveStockfishEvent(event)
    }

    init(
        playerColor: PieceColor,
        pieceSet: ChessPieceSet,
        boardTheme: ChessBoardTheme,
        scenario: GameScenario? = nil
    ) {
        // Capture user configuration so the view model can enforce turn order.
        self.playerColor = playerColor
        self.scenario = scenario
        if let scenario {
            self.moveProvider = ScenarioReplayMoveProvider(scenario: scenario)
        } else {
            self.moveProvider = nil
        }
        // Store the Stockfish depth so future searches use the current setting.
        self.engineDepth = Self.initialEngineDepth
        // UI tests can lower the cosmetic delay while normal demo launches keep it.
        self.engineReplyDelaySeconds = Self.initialEngineReplyDelaySeconds
        self.scenarioReplayDelaySeconds = Self.initialScenarioReplayDelaySeconds
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
        // Let ChessUI report only legal moves for the side to move; the view
        // model still gates those moves to the human player's turn.
        self.boardModel.interactionMode = self.moveProvider?.isAutomaticReplay == true
            ? .readOnly
            : .legalMovesOnly
        self.boardModel.game = initialGame
    }

    /// Normal app runs use a visible thinking pause; UI tests can override it
    /// so move-flow coverage does not spend most of its time intentionally idle.
    private static var initialEngineReplyDelaySeconds: TimeInterval {
        let environment = ProcessInfo.processInfo.environment
        guard let delayValue = environment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_REPLY_DELAY"],
              let delay = TimeInterval(delayValue)
        else {
            return 2.5
        }

        return max(delay, 0)
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

    /// Lowest Stockfish search depth exposed by the game screen.
    static let minimumEngineDepth = 1

    /// Highest Stockfish search depth exposed by the game screen.
    static let maximumEngineDepth = 30

    /// UI tests can lower the engine depth to keep smoke flows fast without
    /// changing the normal demo default.
    private static var initialEngineDepth: Int {
        let environment = ProcessInfo.processInfo.environment
        guard let depthValue = environment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_DEPTH"],
              let depth = Int(depthValue)
        else {
            return 8
        }

        return clampedEngineDepth(depth)
    }

    /// UI tests can provide a deterministic starting evaluation without
    /// depending on live Stockfish search output.
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

    private static func clampedEngineDepth(_ depth: Int) -> Int {
        min(maximumEngineDepth, max(minimumEngineDepth, depth))
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
        self.showsEvaluationBar = showsEvaluationBar
    }

    /// Updates the Stockfish search depth used for future searches.
    func setEngineDepth(_ depth: Int) {
        let clampedDepth = Self.clampedEngineDepth(depth)
        guard clampedDepth != engineDepth else { return }

        engineDepth = clampedDepth

        guard suggestionArrowCount > 0,
              boardModel.game.position.state.turn == playerColor
        else {
            return
        }

        guard stockfishProvider.activePurpose != .opponentMove else { return }

        if let moveProvider {
            applyMoveProviderSuggestionArrows(moveProvider)
            return
        }

        let request = stockfishSearchRequest(purpose: .suggestions)

        if stockfishProvider.activePurpose == .suggestions {
            cancelSuggestionSearch(clearSuggestions: true, queueReplacement: request)
        } else {
            suggestedMovesByRank.removeAll()
            suggestedMovesPositionFEN = nil
            boardModel.clearArrows()
            stockfishProvider.startOrQueueSearch(request)
        }
    }

    /// Updates how many engine-supplied move suggestion arrows the board shows.
    func setSuggestionArrowCount(_ count: Int) {
        let clampedCount = Self.clampedSuggestionArrowCount(count)
        guard clampedCount != suggestionArrowCount else { return }

        suggestionArrowCount = clampedCount
        if clampedCount == 0 {
            if stockfishProvider.activePurpose == .suggestions {
                cancelSuggestionSearch(clearSuggestions: true, queueReplacement: nil)
            } else {
                boardModel.clearArrows()
            }
        } else {
            refreshSuggestionArrows()
            scheduleSuggestionSearchIfNeeded()
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
            scheduleSuggestionSearchIfNeeded()
        }
    }

    /// Receives a move from ChessUI when the user interacts with the UI.
    func handleUserMove(move: Move, isLegal: Bool) {
        guard moveProvider?.isAutomaticReplay != true else { return }
        // Ignore illegal gestures, and ignore moves when it's not the user's turn.
        guard isLegal else { return }
        guard boardModel.game.position.state.turn == playerColor else { return }
        // A real user move invalidates analysis arrows for the previous position.
        cancelSuggestionSearch(clearSuggestions: true, queueReplacement: nil)
        // Apply the move in ChessCore and refresh the board UI.
        guard applyMove(move: move) else { return }
        // Stop here if the move ended the game.
        if checkForGameEnd() { return }
        // Otherwise, let the opponent appear to think before asking Stockfish for a reply.
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

    /// Waits briefly before starting Stockfish so the previous move feedback remains visible.
    private func scheduleEngineMove() {
        engineRequestDelayWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.engineRequestDelayWorkItem = nil
            self.requestEngineMove()
        }

        engineRequestDelayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + engineReplyDelaySeconds, execute: workItem)
    }

    /// Requests a Stockfish reply for the current position.
    private func requestEngineMove() {
        // Only search when it is the engine's turn.
        guard boardModel.game.position.state.turn == playerColor.opposite else { return }

        boardModel.clearArrows()

        if let moveProvider {
            applyMoveProviderOpponentMove(moveProvider)
            return
        }

        stockfishProvider.startOrQueueSearch(stockfishSearchRequest(purpose: .opponentMove))
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

        guard applyMove(move: move) else { return }
        if !checkForGameEnd() {
            scheduleSuggestionSearchIfNeeded()
        }
    }

    /// Handles typed output from the Stockfish provider.
    private func receiveStockfishEvent(_ event: StockfishMoveProviderEvent) {
        switch event {
        case .output(let output, let request):
            switch request.purpose {
            case .opponentMove:
                receiveOpponentEngineOutput(output, request: request)
            case .suggestions:
                receiveSuggestionEngineOutput(output, request: request)
            }

        case .timeout(let request):
            handleStockfishTimeout(request)
        }
    }

    /// Handles parsed UCI output from an opponent-move search.
    private func receiveOpponentEngineOutput(
        _ output: UCIParsedLine,
        request: StockfishSearchRequest
    ) {
        switch output {
        case .info(let info):
            if let score = info.whiteRelativeScore(sideToMove: request.sideToMove) {
                evaluation = chessEvaluation(from: score)
            }

        case .bestMove(let bestMove):
            receiveStockfishMove(move: bestMove.move)

        case .id, .option, .uciOK, .readyOK, .copyProtection, .registration, .unknown:
            return
        }
    }

    /// Handles parsed UCI output from a move-suggestion search.
    private func receiveSuggestionEngineOutput(
        _ output: UCIParsedLine,
        request: StockfishSearchRequest
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
    private func receiveStockfishMove(move: Move?) {
        // A nil move means Stockfish has no legal move.
        guard let move else {
            endGame(title: "Engine Error", message: "Stockfish did not return a move.")
            return
        }

        guard applyMove(
            move: move,
            failureTitle: "Engine Error",
            failureMessage: "Stockfish returned an illegal move."
        ) else {
            return
        }

        // Check if the engine's move ended the game.
        if !checkForGameEnd() {
            scheduleSuggestionSearchIfNeeded()
        }
    }

    /// Handles provider-reported Stockfish search timeouts.
    private func handleStockfishTimeout(_ request: StockfishSearchRequest) {
        if request.purpose == .suggestions {
            return
        }

        endGame(title: "Engine Timeout", message: "Stockfish did not return a move.")
    }

    /// Cancels any running engine search without assuming it was active.
    private func stopEngineIfNeeded() {
        suggestedMovesByRank.removeAll()
        suggestedMovesPositionFEN = nil
        boardModel.clearArrows()
        // Cancel any cosmetic delayed engine request.
        engineRequestDelayWorkItem?.cancel()
        engineRequestDelayWorkItem = nil
        // Cancel automatic scenario replay, if active.
        scenarioReplayWorkItem?.cancel()
        scenarioReplayWorkItem = nil
        moveProvider?.cancel()
        stockfishProvider.stop()
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

        case .ongoing:
            return false
        }
    }

    /// Presents the game result and stops the engine.
    private func endGame(title: String, message: String) {
        // Always stop the engine before presenting an end-state.
        stopEngineIfNeeded()
        boardModel.clearArrows()
        activeAlert = .result(GameResult(title: title, message: message))
    }

    /// Starts or refreshes a move-suggestion search when the player is on move.
    private func scheduleSuggestionSearchIfNeeded() {
        guard suggestionArrowCount > 0 else {
            cancelSuggestionSearch(clearSuggestions: true, queueReplacement: nil)
            return
        }

        guard boardModel.game.position.state.turn == playerColor else {
            boardModel.clearArrows()
            return
        }

        let fen = fenSerializer.fen(from: boardModel.game.position)
        if suggestedMovesPositionFEN == fen {
            refreshSuggestionArrows()
            return
        }

        if stockfishProvider.activePurpose == .suggestions, stockfishProvider.activeFEN == fen {
            refreshSuggestionArrows()
            return
        }

        guard stockfishProvider.activePurpose != .opponentMove else { return }

        if let moveProvider {
            applyMoveProviderSuggestionArrows(moveProvider)
        } else {
            requestSuggestionArrows()
        }
    }

    /// Starts a Stockfish MultiPV search whose output is rendered as arrows.
    private func requestSuggestionArrows() {
        guard suggestionArrowCount > 0 else { return }
        guard boardModel.game.position.state.turn == playerColor else { return }

        startStockfishSearch(stockfishSearchRequest(purpose: .suggestions))
    }

    /// Cancels only an active suggestion search, preserving opponent searches.
    private func cancelSuggestionSearch(clearSuggestions: Bool, queueReplacement: StockfishSearchRequest?) {
        stockfishProvider.cancelSuggestionSearch(queueReplacement: queueReplacement)
        suggestedMovesByRank.removeAll()
        suggestedMovesPositionFEN = nil

        if clearSuggestions {
            boardModel.clearArrows()
        }
    }

    /// Starts one Stockfish search after clearing stale suggestion state.
    private func startStockfishSearch(_ request: StockfishSearchRequest) {
        if request.purpose == .suggestions {
            suggestedMovesByRank.removeAll()
            suggestedMovesPositionFEN = nil
            boardModel.clearArrows()
        }

        stockfishProvider.startOrQueueSearch(request)
    }

    /// Captures the current board position and search settings in one immutable request.
    private func stockfishSearchRequest(purpose: StockfishSearchPurpose) -> StockfishSearchRequest {
        StockfishSearchRequest(
            purpose: purpose,
            fen: fenSerializer.fen(from: boardModel.game.position),
            sideToMove: boardModel.game.position.state.turn,
            depth: engineDepth,
            multiPVCount: purpose == .suggestions ? Self.maximumSuggestionArrowCount : 1
        )
    }

    /// Creates deterministic suggestion arrows from a non-Stockfish provider.
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
        if moveProvider?.isAutomaticReplay == true {
            return "\(winner.displayName) wins"
        }

        return winner == playerColor ? "You win" : "Stockfish wins"
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
