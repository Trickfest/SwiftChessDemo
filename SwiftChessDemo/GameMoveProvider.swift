//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and StockfishEmbedded.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the MIT License.
// You may obtain a copy of the License in the LICENSE file
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
    /// Returns coordinate moves exposed through test-only UI controls.
    func uiTestMoveCoordinates(for game: Game) -> [String]
    /// Cancels any provider-owned work.
    func cancel()
}

extension GameMoveProvider {
    var showsUITestMoveControls: Bool { false }

    func suggestionMoves(for game: Game, maxCount: Int) -> [Move] {
        []
    }

    func uiTestMoveCoordinates(for game: Game) -> [String] {
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
        scenario.playbackMode.isAutomaticReplay
    }

    var showsUITestMoveControls: Bool {
        scenario.playbackMode.testDrivenColor != nil
    }

    func nextMove(for game: Game, ply: Int) -> Move? {
        guard ply < scenario.targetPly else { return nil }
        let records = Array(scenario.replayRecords)
        guard records.indices.contains(ply) else { return nil }

        let record = records[ply]
        guard record.color == game.position.state.turn else { return nil }
        return record.move
    }

    func suggestionMoves(for game: Game, maxCount: Int) -> [Move] {
        guard let testDrivenColor = scenario.playbackMode.testDrivenColor,
              game.position.state.turn == testDrivenColor
        else {
            return []
        }

        var moves: [Move] = []
        let records = Array(scenario.replayRecords)
        for record in records.dropFirst(max(0, game.moveHistory.count)) where record.color == testDrivenColor {
            guard game.legalMoves.contains(record.move) else { continue }
            moves.append(record.move)
            if moves.count == maxCount {
                return moves
            }
        }
        return moves
    }

    func uiTestMoveCoordinates(for game: Game) -> [String] {
        guard let testDrivenColor = scenario.playbackMode.testDrivenColor,
              game.position.state.turn == testDrivenColor
        else {
            return []
        }

        let records = Array(scenario.replayRecords)
        return records
            .dropFirst(max(0, game.moveHistory.count))
            .filter { $0.color == testDrivenColor && game.legalMoves.contains($0.move) }
            .map { $0.move.description }
    }
}
