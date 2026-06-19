//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and StockfishEmbedded.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the GNU General Public License v3.0.
// You may obtain a copy of the License at: https://www.gnu.org/licenses/gpl-3.0.html
// See the LICENSE file for more information.
//

import Foundation
import ChessCore

/// Declarative metadata for a scripted demo scenario.
struct GameScenarioDefinition: Decodable, Equatable {
    /// Stable identifier used by launch configuration and UI tests.
    let id: String
    /// Human-readable scenario title.
    let title: String
    /// Bundled PGN resource that supplies the scenario move list.
    let pgnResource: String
    /// How the scenario should feed moves into the game screen.
    let playbackMode: GameScenarioPlaybackMode
    /// Optional perspective to show at the bottom of the board.
    let initialPerspective: GameScenarioColor?
    /// Optional one-based ply at which automatic replay should stop.
    let stopAfterPly: Int?
    /// Optional expected terminal status, used as scenario documentation and test metadata.
    let expectedStatus: String?
    /// Optional expected winner, used as scenario documentation and test metadata.
    let expectedWinner: GameScenarioColor?
    /// Freeform notes for maintainers.
    let notes: String?
}

/// Supported scripted playback modes.
enum GameScenarioPlaybackMode: String, Decodable, Equatable {
    /// Replays both sides from the PGN without Stockfish or user input.
    case automaticReplay
}

/// Codable color value used in scenario files.
enum GameScenarioColor: String, Decodable, Equatable {
    case white
    case black

    /// ChessCore color equivalent.
    var pieceColor: PieceColor {
        switch self {
        case .white:
            return .white
        case .black:
            return .black
        }
    }
}

/// A loaded, semantically validated scenario.
struct GameScenario: Equatable {
    /// Declarative scenario metadata.
    let definition: GameScenarioDefinition
    /// Parsed PGN model from ChessCore.
    let pgnGame: PGNGame

    /// Stable scenario identifier.
    var id: String { definition.id }
    /// Human-readable title.
    var title: String { definition.title }
    /// Playback mode requested by the scenario file.
    var playbackMode: GameScenarioPlaybackMode { definition.playbackMode }
    /// Initial board perspective.
    var initialPerspective: PieceColor {
        definition.initialPerspective?.pieceColor ?? .white
    }
    /// Initial position loaded from PGN, including FEN-backed setup games.
    var initialPosition: Position { pgnGame.initialPosition }
    /// Move records that automatic replay should apply.
    var replayRecords: ArraySlice<PGNMoveRecord> {
        pgnGame.moveRecords.prefix(targetPly)
    }
    /// Ply where the scenario should stop.
    var targetPly: Int {
        let requestedPly = definition.stopAfterPly ?? pgnGame.moveRecords.count
        return min(max(0, requestedPly), pgnGame.moveRecords.count)
    }
}

/// Loads bundled scenario descriptions and PGN fixtures.
enum GameScenarioLoader {
    /// Launch environment key used by UI tests and manual scenario runs.
    static let requestedScenarioEnvironmentKey = "SWIFT_CHESS_DEMO_SCENARIO"

    /// Returns the scenario requested by launch environment, if any.
    static func requestedScenario(bundle: Bundle = .main) -> Result<GameScenario?, GameScenarioLoadingError> {
        let environment = ProcessInfo.processInfo.environment
        guard let scenarioID = environment[requestedScenarioEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !scenarioID.isEmpty
        else {
            return .success(nil)
        }

        do {
            return .success(try loadScenario(id: scenarioID, bundle: bundle))
        } catch let error as GameScenarioLoadingError {
            return .failure(error)
        } catch {
            return .failure(.unexpected(error.localizedDescription))
        }
    }

    /// Loads one named scenario from the bundled `Scenarios` folder.
    static func loadScenario(id: String, bundle: Bundle = .main) throws -> GameScenario {
        let definitionData = try data(for: id, defaultExtension: "json", bundle: bundle)
        let definition = try JSONDecoder().decode(GameScenarioDefinition.self, from: definitionData)
        guard definition.id == id else {
            throw GameScenarioLoadingError.identifierMismatch(requested: id, loaded: definition.id)
        }

        let pgnData = try data(for: definition.pgnResource, defaultExtension: "pgn", bundle: bundle)
        guard let pgnText = String(data: pgnData, encoding: .utf8) else {
            throw GameScenarioLoadingError.invalidUTF8(definition.pgnResource)
        }

        do {
            let pgnGame = try PGNSerializer().game(from: pgnText)
            return GameScenario(definition: definition, pgnGame: pgnGame)
        } catch {
            throw GameScenarioLoadingError.invalidPGN(resource: definition.pgnResource, reason: error.localizedDescription)
        }
    }

    private static func data(
        for resource: String,
        defaultExtension: String,
        bundle: Bundle
    ) throws -> Data {
        let resourceName = resourceName(for: resource, defaultExtension: defaultExtension)
        let resourceExtension = resourceExtension(for: resource, defaultExtension: defaultExtension)

        let url = bundle.url(forResource: resourceName, withExtension: resourceExtension, subdirectory: "Scenarios")
            ?? bundle.url(forResource: resourceName, withExtension: resourceExtension)

        guard let url else {
            throw GameScenarioLoadingError.missingResource("\(resourceName).\(resourceExtension)")
        }

        do {
            return try Data(contentsOf: url)
        } catch {
            throw GameScenarioLoadingError.unreadableResource(url.lastPathComponent, reason: error.localizedDescription)
        }
    }

    private static func resourceName(for resource: String, defaultExtension: String) -> String {
        let url = URL(fileURLWithPath: resource)
        let extensionText = url.pathExtension.isEmpty ? defaultExtension : url.pathExtension
        return url.deletingPathExtension().lastPathComponent.isEmpty
            ? resource.replacingOccurrences(of: ".\(extensionText)", with: "")
            : url.deletingPathExtension().lastPathComponent
    }

    private static func resourceExtension(for resource: String, defaultExtension: String) -> String {
        let pathExtension = URL(fileURLWithPath: resource).pathExtension
        return pathExtension.isEmpty ? defaultExtension : pathExtension
    }
}

/// Scenario loading errors surfaced to UI tests and setup diagnostics.
enum GameScenarioLoadingError: Error, Equatable, LocalizedError {
    case missingResource(String)
    case unreadableResource(String, reason: String)
    case invalidUTF8(String)
    case identifierMismatch(requested: String, loaded: String)
    case invalidPGN(resource: String, reason: String)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let resource):
            return "Missing scenario resource: \(resource)."
        case .unreadableResource(let resource, let reason):
            return "Could not read scenario resource \(resource): \(reason)."
        case .invalidUTF8(let resource):
            return "Scenario resource is not valid UTF-8: \(resource)."
        case .identifierMismatch(let requested, let loaded):
            return "Requested scenario \(requested), but the file declares \(loaded)."
        case .invalidPGN(let resource, let reason):
            return "Could not parse scenario PGN \(resource): \(reason)."
        case .unexpected(let reason):
            return "Could not load scenario: \(reason)."
        }
    }
}
