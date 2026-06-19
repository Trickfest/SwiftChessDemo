//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and StockfishEmbedded.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the GNU General Public License v3.0.
// You may obtain a copy of the License at: https://www.gnu.org/licenses/gpl-3.0.html
// See the LICENSE file for more information.
//

import ChessCore

/// Source for deterministic, non-Stockfish moves in the demo.
protocol GameMoveProvider: AnyObject {
    /// Human-readable provider name for diagnostics.
    var name: String { get }
    /// Indicates whether the provider replays both sides without user input.
    var isAutomaticReplay: Bool { get }
    /// Indicates whether the game screen should expose test-only move buttons.
    var showsUITestMoveControls: Bool { get }
    /// Returns a concrete move for the current game and ply, if one is available.
    func nextMove(for game: Game, ply: Int) -> Move?
    /// Returns deterministic suggestion moves for the current position, when supported.
    func suggestionMoves(for game: Game, maxCount: Int) -> [Move]
    /// Cancels any provider-owned work.
    func cancel()
}

extension GameMoveProvider {
    var showsUITestMoveControls: Bool { false }

    func suggestionMoves(for game: Game, maxCount: Int) -> [Move] {
        []
    }

    func cancel() {}
}

/// Replays a validated PGN scenario move by move.
final class ScenarioReplayMoveProvider: GameMoveProvider {
    let scenario: GameScenario

    init(scenario: GameScenario) {
        self.scenario = scenario
    }

    var name: String {
        "Scenario \(scenario.id)"
    }

    var isAutomaticReplay: Bool {
        true
    }

    func nextMove(for game: Game, ply: Int) -> Move? {
        guard ply < scenario.targetPly else { return nil }
        let records = Array(scenario.replayRecords)
        guard records.indices.contains(ply) else { return nil }

        let record = records[ply]
        guard record.color == game.position.state.turn else { return nil }
        return record.move
    }
}

/// Temporary provider used by legacy move-flow UI tests.
///
/// TODO: Retire this provider after scenario-backed interactive tests cover the
/// existing white/black move-flow smoke tests.
final class ScriptedUITestMoveProvider: GameMoveProvider {
    private let playerColor: PieceColor

    init(playerColor: PieceColor) {
        self.playerColor = playerColor
    }

    var name: String {
        "Scripted UI Test"
    }

    var isAutomaticReplay: Bool {
        false
    }

    var showsUITestMoveControls: Bool {
        true
    }

    func nextMove(for game: Game, ply: Int) -> Move? {
        preferredOpponentMoves()
            .compactMap { try? Move(string: $0) }
            .first { game.legalMoves.contains($0) }
            ?? game.legalMoves.first
    }

    func suggestionMoves(for game: Game, maxCount: Int) -> [Move] {
        var rankedMoves = preferredPlayerMoves()
            .compactMap { try? Move(string: $0) }
            .filter { game.legalMoves.contains($0) }

        for move in game.legalMoves where !rankedMoves.contains(move) {
            rankedMoves.append(move)
        }

        return Array(rankedMoves.prefix(maxCount))
    }

    private func preferredOpponentMoves() -> [String] {
        switch playerColor.opposite {
        case .white:
            return ["e2e4", "g1f3", "f1c4", "d2d3"]
        case .black:
            return ["e7e5", "b8c6", "g8f6", "f8c5"]
        }
    }

    private func preferredPlayerMoves() -> [String] {
        switch playerColor {
        case .white:
            return ["e2e4", "g1f3", "f1c4", "d2d4", "d2d3", "c2c4"]
        case .black:
            return ["e7e5", "g8f6", "d7d5", "f8c5", "b8c6", "c7c5"]
        }
    }
}
