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

    /// The human player's color; used to gate whose turn it is.
    let playerColor: PieceColor
    /// Stockfish depth for the engine search.
    let engineDepth: Int
    /// ChessUI model that binds to the board UI.
    let boardModel: ChessBoardModel

    /// FEN serializer from ChessCore.
    private let fenSerializer = FENSerializer()
    /// The running Stockfish engine instance, if any.
    private var engine: SFEngine?
    /// Task used to time out engine searches.
    private var engineTimeoutTask: Task<Void, Never>?
    /// Work item used to wait briefly before starting an engine search.
    private var engineRequestDelayWorkItem: DispatchWorkItem?
    /// FEN-position counts to detect threefold repetition.
    private var positionCounts: [String: Int] = [:]
    /// Token used to ignore stale engine responses after cancellation.
    private var searchToken = UUID()
    /// Ensures we only start the engine once when the view appears.
    private var didStart = false
    /// Quick flag to prevent parallel searches.
    private var isEngineThinking = false
    /// Cosmetic delay before asking Stockfish for a reply, so the demo feels like the engine is thinking.
    private let engineReplyDelaySeconds: TimeInterval = 2.5

    init(playerColor: PieceColor, engineDepth: Int, pieceSet: ChessPieceSet, boardTheme: ChessBoardTheme) {
        // Capture user configuration so the view model can enforce turn order.
        self.playerColor = playerColor
        // Store the Stockfish depth so search limits stay consistent.
        self.engineDepth = engineDepth
        // Keep the selected ChessUI artwork available for menus and board updates.
        self.pieceSet = pieceSet
        // Keep the selected ChessUI board theme available for menus and board updates.
        self.boardTheme = boardTheme
        // Standard initial chess position in FEN format.
        let initialFen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        // ChessUI owns the board and perspective rendering.
        self.boardModel = ChessBoardModel(
            fen: initialFen,
            perspective: playerColor,
            boardTheme: boardTheme,
            pieceSet: pieceSet
        )
        // Ask the board to validate moves (it uses ChessCore internally).
        self.boardModel.validatesMoves = true
        // Prevent user from moving both sides; the engine is the opponent.
        self.boardModel.allowsOpponentMoves = false
        // Record the initial position for repetition tracking.
        recordPosition()
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
        applyMove(move: move)
        // Stop here if the move ended the game.
        if checkForGameEnd() { return }
        // Otherwise, let the opponent appear to think before asking Stockfish for a reply.
        scheduleEngineMove()
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

    /// Called when the view disappears; ensures background work stops.
    func cleanup() {
        stopEngineIfNeeded()
    }

    /// Applies a move to the ChessCore game and updates the board UI with FEN.
    private func applyMove(move: Move) {
        // ChessCore updates internal rules state and move counters here.
        boardModel.game.apply(move: move)
        // Serialize the new position into FEN for ChessUI.
        let fen = fenSerializer.fen(from: boardModel.game.position)
        // ChessUI consumes the new FEN plus the move that produced it, then
        // owns move animation and last-move highlighting.
        boardModel.setFEN(fen, animatedMove: move)
        // Track the position for threefold repetition.
        recordPosition()
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
            applyMove(move: try Move(string: normalized))
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

    /// Records the current position for threefold repetition detection.
    private func recordPosition() {
        // Serialize the current board to FEN for stable hashing.
        let fen = fenSerializer.fen(from: boardModel.game.position)
        // FEN fields 0-3 are board, turn, castling, en passant.
        // We ignore move counters so positions compare correctly.
        let key = fen.split(separator: " ").prefix(4).joined(separator: " ")
        // Increment the repetition count for this normalized position.
        positionCounts[key, default: 0] += 1
    }

    /// Evaluates draw and win conditions using ChessCore state.
    private func checkForGameEnd() -> Bool {
        // Checkmate: side to move has no legal moves while in check.
        if boardModel.game.isCheckmate {
            let winner = boardModel.game.position.state.turn.opposite
            let message = winner == playerColor ? "You win" : "Stockfish wins"
            endGame(title: "Checkmate", message: message)
            return true
        }

        // Stalemate: no legal moves but not in check.
        if !boardModel.game.isCheck && boardModel.game.legalMoves.isEmpty {
            endGame(title: "Stalemate", message: "Draw")
            return true
        }

        // Threefold repetition: same position seen at least three times.
        if isThreefoldRepetition() {
            endGame(title: "Draw by repetition", message: "Draw")
            return true
        }

        // 50-move rule: 100 half-moves with no pawn moves or captures.
        if boardModel.game.position.counter.halfMoves >= 100 {
            // ChessCore tracks half-moves; 100 half-moves equals the 50-move rule.
            endGame(title: "Draw by 50-move rule", message: "Draw")
            return true
        }

        // Insufficient material: check minimal endgames that cannot mate.
        if isInsufficientMaterial() {
            endGame(title: "Draw by insufficient material", message: "Draw")
            return true
        }

        return false
    }

    /// Presents the game result and stops the engine.
    private func endGame(title: String, message: String) {
        // Always stop the engine before presenting an end-state.
        stopEngineIfNeeded()
        activeAlert = .result(GameResult(title: title, message: message))
    }

    /// Checks the recorded position history for threefold repetition.
    private func isThreefoldRepetition() -> Bool {
        // Use the same keying strategy as recordPosition().
        let fen = fenSerializer.fen(from: boardModel.game.position)
        let key = fen.split(separator: " ").prefix(4).joined(separator: " ")
        return (positionCounts[key] ?? 0) >= 3
    }

    /// Applies simple insufficient-material rules for basic endgames.
    private func isInsufficientMaterial() -> Bool {
        // Enumerate all pieces currently on the board.
        let pieces = boardModel.game.position.board.enumeratedPieces()
        var counts: [PieceKind: Int] = [:]
        for (_, piece) in pieces {
            counts[piece.kind, default: 0] += 1
        }

        // Any pawns, rooks, or queens means checkmate is still possible.
        if (counts[.pawn] ?? 0) > 0 { return false }
        if (counts[.rook] ?? 0) > 0 { return false }
        if (counts[.queen] ?? 0) > 0 { return false }

        // Only minor pieces (bishops/knights) remain.
        let bishops = counts[.bishop] ?? 0
        let knights = counts[.knight] ?? 0

        // King vs king is already covered; now check minor-piece cases.
        if bishops == 0 && knights == 0 {
            return true
        }

        // King and a single minor piece cannot force mate.
        if bishops + knights == 1 {
            return true
        }

        // Two bishops on the same color squares also cannot force mate.
        if bishops == 2 && knights == 0 && pieces.count == 4 {
            // Filter to the bishops and check their square colors.
            let bishopSquares = pieces.filter { $0.1.kind == .bishop }.map { $0.0 }
            if bishopSquares.count == 2 {
                // Sum of file+rank parity identifies square color.
                let colors = bishopSquares.map { ($0.file + $0.rank) % 2 }
                if colors[0] == colors[1] {
                    return true
                }
            }
        }

        return false
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
