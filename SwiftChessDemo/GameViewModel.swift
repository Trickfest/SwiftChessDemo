//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and StockfishEmbedded.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the GNU General Public License v3.0.
// You may obtain a copy of the License at: https://www.gnu.org/licenses/gpl-3.0.html
// See the LICENSE file for more information.
//

import Combine
import ChessCore
import ChessUI

/// Coordinates the chess game state, the UI, and the embedded engine.
///
/// Teaching focus:
/// - ChessCore handles rules, legal moves, and game state.
/// - ChessUI renders the board and consumes FEN updates.
/// - StockfishEmbedded (via `SFEngine`) supplies engine moves.
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
    /// ChessCore status mirrored for SwiftUI rendering.
    @Published private(set) var gameStatus: GameStatus
    /// Side to move mirrored for SwiftUI rendering.
    @Published private(set) var sideToMove: PieceColor
    /// Display-ready move records for ChessUI's move list.
    @Published private(set) var moveRecords: [ChessMoveRecord] = []
    /// Current move-list selection.
    @Published var selectedMovePly: Int?
    /// Current FEN exposed to UI tests for black-box board-change assertions.
    @Published private(set) var positionFEN: String

    /// The human player's color; used to gate whose turn it is.
    let playerColor: PieceColor
    /// Stockfish depth for the engine search.
    let engineDepth: Int
    /// ChessUI model that binds to the board UI.
    let boardModel: ChessBoardModel

    /// FEN serializer from ChessCore.
    private let fenSerializer = FENSerializer()
    /// Builds SAN-backed move-list records from pre-move game state.
    private let moveRecordBuilder = ChessMoveRecordBuilder()
    /// The running Stockfish engine instance, if any.
    private var engine: SFEngine?
    /// Task used to time out engine searches.
    private var engineTimeoutTask: Task<Void, Never>?
    /// Work item used to wait briefly before starting an engine search.
    private var engineRequestDelayWorkItem: DispatchWorkItem?
    /// Token used to ignore stale engine responses after cancellation.
    private var searchToken = UUID()
    /// Ensures we only start the engine once when the view appears.
    private var didStart = false
    /// Quick flag to prevent parallel searches.
    private var isEngineThinking = false
    /// Cosmetic delay before asking Stockfish for a reply, so the demo feels like the engine is thinking.
    private let engineReplyDelaySeconds: TimeInterval

    init(playerColor: PieceColor, engineDepth: Int, pieceSet: ChessPieceSet, boardTheme: ChessBoardTheme) {
        // Capture user configuration so the view model can enforce turn order.
        self.playerColor = playerColor
        // Store the Stockfish depth so search limits stay consistent.
        self.engineDepth = engineDepth
        // UI tests can lower the cosmetic delay while normal demo launches keep it.
        self.engineReplyDelaySeconds = Self.initialEngineReplyDelaySeconds
        // Keep the selected ChessUI artwork available for menus and board updates.
        self.pieceSet = pieceSet
        // Keep the selected ChessUI board theme available for menus and board updates.
        self.boardTheme = boardTheme
        // Standard initial chess position in FEN format.
        let initialFen = Position.standardStartingFEN
        self.positionFEN = initialFen
        self.gameStatus = .ongoing(drawClaims: [])
        self.sideToMove = Position.standard.state.turn
        // ChessUI owns the board and perspective rendering.
        self.boardModel = ChessBoardModel(
            fen: initialFen,
            perspective: playerColor,
            boardTheme: boardTheme,
            pieceSet: pieceSet
        )
        // Let ChessUI report only legal moves for the side to move; the view
        // model still gates those moves to the human player's turn.
        self.boardModel.interactionMode = .legalMovesOnly
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

    /// UI tests use scripted opponent replies so interaction tests are not
    /// coupled to Stockfish startup time or changing engine choices.
    static var usesScriptedUITestEngine: Bool {
        ProcessInfo.processInfo.environment["SWIFT_CHESS_DEMO_UI_TEST_SCRIPTED_ENGINE"] == "1"
    }

    /// Test-only controls are opt-in through the UI test launch environment.
    var showsUITestMoveControls: Bool {
        Self.usesScriptedUITestEngine
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

    /// Selects a move-list record without changing the board position.
    func selectMoveRecord(_ record: ChessMoveRecord) {
        selectedMovePly = record.ply
    }

    /// Starts the game loop on first appearance.
    func startIfNeeded() {
        // Guard so repeated `onAppear` calls do not restart the engine.
        guard !didStart else { return }
        didStart = true
        // If the user chose black, the engine makes the first move.
        if playerColor == .black {
            scheduleEngineMove()
        }
    }

    /// Receives a move from ChessUI when the user interacts with the UI.
    func handleUserMove(move: Move, isLegal: Bool) {
        // Ignore illegal gestures, and ignore moves when it's not the user's turn.
        guard isLegal else { return }
        guard boardModel.game.position.state.turn == playerColor else { return }
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
        guard Self.usesScriptedUITestEngine,
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

    /// Spawns a Stockfish search for the current position.
    private func requestEngineMove() {
        // Avoid overlapping searches which can race UI updates.
        guard !isEngineThinking else { return }
        // Only search when it is the engine's turn.
        guard boardModel.game.position.state.turn == playerColor.opposite else { return }

        if Self.usesScriptedUITestEngine {
            applyScriptedEngineMove()
            return
        }

        // Flip the flag to block additional search requests.
        isEngineThinking = true

        // Convert the current ChessCore position into a FEN string.
        let fen = fenSerializer.fen(from: boardModel.game.position)
        // Rotate the token so old "bestmove" lines are ignored.
        let token = UUID()
        searchToken = token
        engineTimeoutTask?.cancel()

        // Create a new engine instance with a simple line callback.
        let engine = SFEngine(lineHandler: { [weak self] line in
            // Stockfish streams many lines; we only care about bestmove.
            guard let self, line.hasPrefix("bestmove") else { return }
            let move = GameViewModel.parseBestMove(line)
            // Bounce back to the main actor because we will update UI state.
            Task { @MainActor in
                self.receiveEngineMove(move: move, token: token, engine: self.engine)
            }
        })

        self.engine = engine
        // Start the Stockfish process and initiate the UCI protocol.
        engine.start()
        // Standard UCI handshake followed by a depth-limited search.
        engine.sendCommand("uci")
        // Ask Stockfish to confirm it is ready for commands.
        engine.sendCommand("isready")
        // Reset internal engine state so the search is clean.
        engine.sendCommand("ucinewgame")
        // Provide the current position in FEN.
        engine.sendCommand("position fen \(fen)")
        // Launch the search at the chosen depth.
        engine.sendCommand("go depth \(engineDepth)")

        // Guard against engine hangs by timing out after 30 seconds.
        engineTimeoutTask = Task { [weak self] in
            // Sleep asynchronously so the UI thread stays responsive.
            do {
                try await Task.sleep(for: .seconds(30))
            } catch {
                return
            }
            await MainActor.run {
                self?.handleEngineTimeout(token: token)
            }
        }
    }

    /// Applies a deterministic legal opponent move for UI tests.
    private func applyScriptedEngineMove() {
        let candidateMoves: [String]
        switch playerColor.opposite {
        case .white:
            candidateMoves = ["e2e4", "g1f3", "f1c4", "d2d3"]
        case .black:
            candidateMoves = ["e7e5", "b8c6", "g8f6", "f8c5"]
        }

        let legalMoves = boardModel.game.legalMoves
        let scriptedMove = candidateMoves
            .compactMap { try? Move(string: $0) }
            .first { legalMoves.contains($0) }
        let move = scriptedMove ?? legalMoves.first

        guard let move else {
            endGame(title: "Draw", message: "No legal moves remain.")
            return
        }

        guard applyMove(move: move) else { return }
        _ = checkForGameEnd()
    }

    /// Handles the engine move after receiving a "bestmove" line.
    private func receiveEngineMove(move: String?, token: UUID, engine: SFEngine?) {
        // Ignore stale responses from previous searches.
        guard token == searchToken else { return }

        // A nil move means Stockfish has no legal move.
        guard let move else {
            // Stop the engine before reporting the failure.
            finishEngineSearch(engine: engine)
            endGame(title: "Engine Error", message: "Stockfish did not return a move.")
            return
        }

        // Normalize promotion format before creating the ChessCore move.
        let normalized = normalizePromotion(move)
        // Stop the engine before applying the move to the UI.
        finishEngineSearch(engine: engine)
        // Convert the UCI string into a ChessCore move and apply it.
        do {
            let engineMove = try Move(string: normalized)
            guard applyMove(
                move: engineMove,
                failureTitle: "Engine Error",
                failureMessage: "Stockfish returned an illegal move."
            ) else {
                return
            }
        } catch {
            endGame(title: "Engine Error", message: "Stockfish returned an invalid move.")
            return
        }
        // Check if the engine's move ended the game.
        _ = checkForGameEnd()
    }

    /// Fires when the engine does not respond within the timeout window.
    private func handleEngineTimeout(token: UUID) {
        // Only act if this timeout corresponds to the current search.
        guard isEngineThinking, token == searchToken else { return }
        // Cancel the engine and present a failure message.
        finishEngineSearch(engine: engine)
        endGame(title: "Engine Timeout", message: "Stockfish did not return a move.")
    }

    /// Finishes the current search and shuts down the engine instance.
    private func finishEngineSearch(engine: SFEngine?) {
        // Rotate the token so late engine output is ignored.
        searchToken = UUID()
        // Reset the thinking flag so a new search can begin later.
        isEngineThinking = false
        // Stop and clear any pending timeout.
        engineTimeoutTask?.cancel()
        engineTimeoutTask = nil

        if let engine {
            // Stop off the main thread to avoid blocking UI.
            DispatchQueue.global(qos: .userInitiated).async {
                engine.stop()
            }
        }

        // Release the engine so a fresh instance is created next time.
        self.engine = nil
    }

    /// Cancels any running engine search without assuming it was active.
    private func stopEngineIfNeeded() {
        // Reset the token and flag regardless of current state.
        searchToken = UUID()
        isEngineThinking = false
        // Cancel the timeout so it does not fire after cleanup.
        engineTimeoutTask?.cancel()
        engineTimeoutTask = nil
        // Cancel any cosmetic delayed engine request.
        engineRequestDelayWorkItem?.cancel()
        engineRequestDelayWorkItem = nil

        if let engine {
            // Stop off the main thread to avoid blocking UI.
            DispatchQueue.global(qos: .userInitiated).async {
                engine.stop()
            }
        }

        // Drop the engine reference so it can be recreated later.
        engine = nil
    }

    /// Evaluates draw and win conditions using ChessCore state.
    private func checkForGameEnd() -> Bool {
        switch boardModel.game.status {
        case .checkmate(let winner):
            let message = winner == playerColor ? "You win" : "Stockfish wins"
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
        activeAlert = .result(GameResult(title: title, message: message))
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

    /// Normalizes promotion piece casing before parsing engine output.
    private func normalizePromotion(_ move: String) -> String {
        // UCI promotion moves are 5 characters (e7e8q).
        guard move.count == 5 else { return move }
        let prefix = move.prefix(4)
        // Keep promotion letters consistent with the rest of the demo.
        let suffix = move.suffix(1).uppercased()
        return "\(prefix)\(suffix)"
    }

    /// Extracts the coordinate move from a UCI "bestmove" line.
    private static func parseBestMove(_ line: String) -> String? {
        // "bestmove e2e4" -> ["bestmove", "e2e4", ...]
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let move = String(parts[1])
        // Stockfish returns "(none)" when no legal move exists.
        return move == "(none)" ? nil : move
    }
}
