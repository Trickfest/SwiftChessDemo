//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and StockfishEmbedded.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the MIT License.
// You may obtain a copy of the License in the LICENSE file
// See the LICENSE file for more information.
//

import Foundation

/// Machine-readable catalog for the bundled demo scenarios.
struct GameScenarioIndex: Decodable, Equatable {
    /// Schema version for the index file.
    let version: Int
    /// Scenarios available in the bundle.
    let scenarios: [GameScenarioIndexEntry]
}

/// One catalog entry for a bundled demo scenario.
struct GameScenarioIndexEntry: Decodable, Equatable {
    /// Stable scenario identifier.
    let id: String
    /// Human-readable title.
    let title: String
    /// PGN resource used by the scenario definition.
    let pgnResource: String
    /// Scenario playback mode.
    let playbackMode: GameScenarioPlaybackMode
    /// Optional ply limit documented by the index.
    let stopAfterPly: Int?
    /// Optional expected terminal status.
    let expectedStatus: String?
    /// Optional expected winner.
    let expectedWinner: GameScenarioColor?
    /// Short classification labels for filtering or documentation.
    let tags: [String]
    /// Maintainer-facing reason this scenario exists.
    let purpose: String
}

/// Successful scenario-index validation result.
struct GameScenarioIndexValidationSummary: Equatable {
    /// Validated scenario identifiers, in index order.
    let scenarioIDs: [String]

    /// Human-readable summary shown only in scenario-index validation mode.
    var displayText: String {
        "Validated \(scenarioIDs.count) scenarios: \(scenarioIDs.joined(separator: ", "))"
    }
}

/// Scenario-index validation failure details.
struct GameScenarioIndexValidationError: Error, Equatable, LocalizedError {
    /// Individual validation issues.
    let issues: [String]

    var errorDescription: String? {
        issues.joined(separator: "\n")
    }
}

/// Loads and validates the bundled scenario index.
enum GameScenarioIndexLoader {
    /// Launch environment key used by UI tests to run bundle-level index validation.
    static let validationEnvironmentKey = "SWIFT_CHESS_DEMO_VALIDATE_SCENARIO_INDEX"

    /// Returns an index-validation result only when validation mode is requested.
    static func requestedValidation(bundle: Bundle = .main) -> Result<GameScenarioIndexValidationSummary, GameScenarioIndexValidationError>? {
        let value = ProcessInfo.processInfo.environment[validationEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == "1" || value?.lowercased() == "true" else { return nil }
        return validateIndex(bundle: bundle)
    }

    /// Loads the bundled scenario index.
    static func loadIndex(bundle: Bundle = .main) throws -> GameScenarioIndex {
        let url = bundle.url(forResource: "index", withExtension: "json", subdirectory: "Scenarios")
            ?? bundle.url(forResource: "index", withExtension: "json")

        guard let url else {
            throw GameScenarioIndexValidationError(issues: ["Missing scenario index resource: index.json."])
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(GameScenarioIndex.self, from: data)
        } catch let error as GameScenarioIndexValidationError {
            throw error
        } catch {
            throw GameScenarioIndexValidationError(issues: ["Could not load scenario index: \(error.localizedDescription)"])
        }
    }

    /// Validates that the index and bundled scenario resources agree.
    static func validateIndex(bundle: Bundle = .main) -> Result<GameScenarioIndexValidationSummary, GameScenarioIndexValidationError> {
        do {
            let index = try loadIndex(bundle: bundle)
            let issues = validate(index: index, bundle: bundle)

            if issues.isEmpty {
                return .success(GameScenarioIndexValidationSummary(scenarioIDs: index.scenarios.map(\.id)))
            } else {
                return .failure(GameScenarioIndexValidationError(issues: issues))
            }
        } catch let error as GameScenarioIndexValidationError {
            return .failure(error)
        } catch {
            return .failure(GameScenarioIndexValidationError(issues: [error.localizedDescription]))
        }
    }

    private static func validate(index: GameScenarioIndex, bundle: Bundle) -> [String] {
        var issues: [String] = []

        if index.version != 1 {
            issues.append("Unsupported scenario index version: \(index.version).")
        }

        let ids = index.scenarios.map(\.id)
        if ids != ids.sorted() {
            issues.append("Scenario index entries must be sorted by id.")
        }

        let duplicateIDs = duplicateValues(in: ids)
        if !duplicateIDs.isEmpty {
            issues.append("Scenario index contains duplicate ids: \(duplicateIDs.joined(separator: ", ")).")
        }

        var indexedIDs = Set<String>()
        for entry in index.scenarios {
            indexedIDs.insert(entry.id)
            issues.append(contentsOf: validate(entry: entry, bundle: bundle))
        }

        let discoveredIDs = discoveredScenarioIDs(bundle: bundle, issues: &issues)
        let missingFromIndex = discoveredIDs.subtracting(indexedIDs).sorted()
        if !missingFromIndex.isEmpty {
            issues.append("Scenario resources missing from index: \(missingFromIndex.joined(separator: ", ")).")
        }

        let missingResources = indexedIDs.subtracting(discoveredIDs).sorted()
        if !missingResources.isEmpty {
            issues.append("Scenario index entries without scenario resources: \(missingResources.joined(separator: ", ")).")
        }

        return issues
    }

    private static func validate(entry: GameScenarioIndexEntry, bundle: Bundle) -> [String] {
        var issues: [String] = []

        if entry.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Scenario index entry has an empty id.")
        }
        if entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Scenario index entry \(entry.id) has an empty title.")
        }
        if entry.pgnResource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Scenario index entry \(entry.id) has an empty pgnResource.")
        }
        if entry.tags.isEmpty || entry.tags.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append("Scenario index entry \(entry.id) must have non-empty tags.")
        }
        if entry.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Scenario index entry \(entry.id) must describe its purpose.")
        }

        do {
            let scenario = try GameScenarioLoader.loadScenario(id: entry.id, bundle: bundle)
            let definition = scenario.definition
            compare(entry.id, "title", entry.title, definition.title, issues: &issues)
            compare(entry.id, "pgnResource", entry.pgnResource, definition.pgnResource, issues: &issues)
            compare(entry.id, "playbackMode", entry.playbackMode.rawValue, definition.playbackMode.rawValue, issues: &issues)
            compare(entry.id, "stopAfterPly", entry.stopAfterPly, definition.stopAfterPly, issues: &issues)
            compare(entry.id, "expectedStatus", entry.expectedStatus, definition.expectedStatus, issues: &issues)
            compare(entry.id, "expectedWinner", entry.expectedWinner?.rawValue, definition.expectedWinner?.rawValue, issues: &issues)
        } catch {
            issues.append("Scenario index entry \(entry.id) did not load: \(error.localizedDescription)")
        }

        return issues
    }

    private static func discoveredScenarioIDs(bundle: Bundle, issues: inout [String]) -> Set<String> {
        var urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Scenarios") ?? []
        if urls.isEmpty {
            urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        }

        var ids = Set<String>()
        for url in urls where url.lastPathComponent != "index.json" {
            do {
                let data = try Data(contentsOf: url)
                let definition = try JSONDecoder().decode(GameScenarioDefinition.self, from: data)
                ids.insert(definition.id)
            } catch {
                issues.append("Could not decode scenario definition \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return ids
    }

    private static func duplicateValues(in values: [String]) -> [String] {
        var seen = Set<String>()
        var duplicates = Set<String>()
        for value in values {
            if !seen.insert(value).inserted {
                duplicates.insert(value)
            }
        }
        return duplicates.sorted()
    }

    private static func compare<T: Equatable>(
        _ id: String,
        _ field: String,
        _ indexedValue: T,
        _ scenarioValue: T,
        issues: inout [String]
    ) {
        guard indexedValue != scenarioValue else { return }
        issues.append("Scenario index entry \(id) has mismatched \(field).")
    }
}
