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
@testable import SwiftChessDemo
import XCTest

@MainActor
final class GameScenarioLoaderTests: XCTestCase {
    func testEveryIndexedScenarioLoadsFromAppBundle() throws {
        let index = try GameScenarioIndexLoader.loadIndex(bundle: .main)

        XCTAssertEqual(index.scenarios.count, 9)

        for entry in index.scenarios {
            let scenario = try GameScenarioLoader.loadScenario(id: entry.id, bundle: .main)
            XCTAssertEqual(scenario.id, entry.id)
            XCTAssertEqual(scenario.title, entry.title)
            XCTAssertLessThanOrEqual(scenario.targetPly, scenario.pgnGame.moveRecords.count)
        }
    }

    func testBundledScenariosHaveExpectedPlyCountsAndStopPlies() throws {
        let expectations: [ScenarioExpectation] = [
            ScenarioExpectation(id: "black-four-move-smoke", moveCount: 8, targetPly: 8),
            ScenarioExpectation(id: "fools-mate", moveCount: 4, targetPly: 4),
            ScenarioExpectation(
                id: "insufficient-material-position",
                moveCount: 0,
                targetPly: 0,
                initialFEN: "k7/8/8/8/8/8/8/6K1 w - - 0 1"
            ),
            ScenarioExpectation(
                id: "promotion-to-queen",
                moveCount: 1,
                targetPly: 1,
                initialFEN: "8/P6k/8/8/8/8/6K1/8 w - - 0 1"
            ),
            ScenarioExpectation(id: "ruy-lopez-long", moveCount: 20, targetPly: 20),
            ScenarioExpectation(id: "special-moves", moveCount: 11, targetPly: 11),
            ScenarioExpectation(
                id: "stalemate-position",
                moveCount: 0,
                targetPly: 0,
                initialFEN: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"
            ),
            ScenarioExpectation(id: "suggestion-line", moveCount: 8, targetPly: 8),
            ScenarioExpectation(id: "white-four-move-smoke", moveCount: 8, targetPly: 8),
        ]

        let serializer = FENSerializer()
        for expectation in expectations {
            let scenario = try GameScenarioLoader.loadScenario(id: expectation.id, bundle: .main)
            XCTAssertEqual(scenario.pgnGame.moveRecords.count, expectation.moveCount, expectation.id)
            XCTAssertEqual(scenario.targetPly, expectation.targetPly, expectation.id)

            if let initialFEN = expectation.initialFEN {
                XCTAssertEqual(serializer.fen(from: scenario.initialPosition), initialFEN, expectation.id)
            }
        }
    }

    func testMissingScenarioResourceReportsMissingResource() throws {
        let bundle = try TestScenarioBundle(files: [
            "Scenarios/index.json": TestScenarioData.indexJSON(),
            "Scenarios/sample.pgn": TestScenarioData.validPGN,
        ]).bundle()

        XCTAssertThrowsError(try GameScenarioLoader.loadScenario(id: "missing-scenario", bundle: bundle)) { error in
            XCTAssertEqual(error as? GameScenarioLoadingError, .missingResource("missing-scenario.json"))
        }
    }

    func testScenarioIdentifierMismatchReportsRequestedAndLoadedIDs() throws {
        let bundle = try TestScenarioBundle(files: [
            "Scenarios/mismatch.json": TestScenarioData.scenarioJSON(id: "different-id"),
            "Scenarios/sample.pgn": TestScenarioData.validPGN,
        ]).bundle()

        XCTAssertThrowsError(try GameScenarioLoader.loadScenario(id: "mismatch", bundle: bundle)) { error in
            XCTAssertEqual(
                error as? GameScenarioLoadingError,
                .identifierMismatch(requested: "mismatch", loaded: "different-id")
            )
        }
    }

    func testInvalidScenarioPGNReportsInvalidPGN() throws {
        let bundle = try TestScenarioBundle(files: [
            "Scenarios/invalid-pgn.json": TestScenarioData.scenarioJSON(id: "invalid-pgn", pgnResource: "invalid.pgn"),
            "Scenarios/invalid.pgn": "this is not a pgn game",
        ]).bundle()

        XCTAssertThrowsError(try GameScenarioLoader.loadScenario(id: "invalid-pgn", bundle: bundle)) { error in
            guard case .invalidPGN(let resource, _)? = error as? GameScenarioLoadingError else {
                return XCTFail("Expected invalidPGN, got \(error)")
            }
            XCTAssertEqual(resource, "invalid.pgn")
        }
    }
}

@MainActor
final class GameScenarioIndexLoaderTests: XCTestCase {
    func testBundledScenarioIndexValidatesFromAppBundle() throws {
        let result = GameScenarioIndexLoader.validateIndex(bundle: .main)

        guard case .success(let summary) = result else {
            return XCTFail("Expected bundled scenario index to validate, got \(result)")
        }
        XCTAssertEqual(summary.scenarioIDs, [
            "black-four-move-smoke",
            "fools-mate",
            "insufficient-material-position",
            "promotion-to-queen",
            "ruy-lopez-long",
            "special-moves",
            "stalemate-position",
            "suggestion-line",
            "white-four-move-smoke",
        ])
    }

    func testScenarioIndexRejectsUnsortedEntries() throws {
        let bundle = try TestScenarioBundle(files: [
            "Scenarios/index.json": TestScenarioData.indexJSON(ids: ["zeta", "alpha"]),
            "Scenarios/zeta.json": TestScenarioData.scenarioJSON(id: "zeta"),
            "Scenarios/alpha.json": TestScenarioData.scenarioJSON(id: "alpha"),
            "Scenarios/sample.pgn": TestScenarioData.validPGN,
        ]).bundle()

        assertIndexValidationIssue("sorted by id", bundle: bundle)
    }

    func testScenarioIndexRejectsDuplicateIDs() throws {
        let bundle = try TestScenarioBundle(files: [
            "Scenarios/index.json": TestScenarioData.indexJSON(ids: ["sample", "sample"]),
            "Scenarios/sample.json": TestScenarioData.scenarioJSON(id: "sample"),
            "Scenarios/sample.pgn": TestScenarioData.validPGN,
        ]).bundle()

        assertIndexValidationIssue("duplicate ids", bundle: bundle)
    }

    func testScenarioIndexRejectsScenarioResourcesMissingFromIndex() throws {
        let bundle = try TestScenarioBundle(files: [
            "Scenarios/index.json": TestScenarioData.indexJSON(ids: ["sample"]),
            "Scenarios/sample.json": TestScenarioData.scenarioJSON(id: "sample"),
            "Scenarios/unindexed.json": TestScenarioData.scenarioJSON(id: "unindexed"),
            "Scenarios/sample.pgn": TestScenarioData.validPGN,
        ]).bundle()

        assertIndexValidationIssue("missing from index: unindexed", bundle: bundle)
    }

    func testScenarioIndexRejectsEntriesWithoutScenarioResources() throws {
        let bundle = try TestScenarioBundle(files: [
            "Scenarios/index.json": TestScenarioData.indexJSON(ids: ["sample", "stale"]),
            "Scenarios/sample.json": TestScenarioData.scenarioJSON(id: "sample"),
            "Scenarios/sample.pgn": TestScenarioData.validPGN,
        ]).bundle()

        assertIndexValidationIssue("entries without scenario resources: stale", bundle: bundle)
    }

    func testScenarioIndexRejectsMetadataDrift() throws {
        let bundle = try TestScenarioBundle(files: [
            "Scenarios/index.json": TestScenarioData.indexJSON(title: "Stale Title"),
            "Scenarios/sample.json": TestScenarioData.scenarioJSON(id: "sample", title: "Current Title"),
            "Scenarios/sample.pgn": TestScenarioData.validPGN,
        ]).bundle()

        assertIndexValidationIssue("mismatched title", bundle: bundle)
    }

    private func assertIndexValidationIssue(
        _ expectedIssue: String,
        bundle: Bundle,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = GameScenarioIndexLoader.validateIndex(bundle: bundle)

        guard case .failure(let error) = result else {
            return XCTFail("Expected validation failure, got \(result)", file: file, line: line)
        }

        XCTAssertTrue(
            error.issues.contains { $0.contains(expectedIssue) },
            "Expected issue containing \(expectedIssue), got \(error.issues)",
            file: file,
            line: line
        )
    }
}

@MainActor
final class ScenarioReplayMoveProviderTests: XCTestCase {
    func testAutomaticReplayProvidesBothSidesInOrderUntilTargetPly() throws {
        let scenario = try GameScenarioLoader.loadScenario(id: "fools-mate", bundle: .main)
        let provider = ScenarioReplayMoveProvider(scenario: scenario)
        let game = Game(position: scenario.initialPosition)

        XCTAssertTrue(provider.isAutomaticReplay)
        XCTAssertFalse(provider.showsUITestMoveControls)

        var moves: [String] = []
        for ply in 0..<scenario.targetPly {
            let move = try XCTUnwrap(provider.nextMove(for: game, ply: ply))
            moves.append(move.description)
            try game.applyLegal(move: move)
        }

        XCTAssertEqual(moves, ["f2f3", "e7e5", "g2g4", "d8h4"])
        XCTAssertNil(provider.nextMove(for: game, ply: scenario.targetPly))
    }

    func testTestDrivesWhiteProviderSuppliesOnlyBlackReplies() throws {
        let scenario = try GameScenarioLoader.loadScenario(id: "white-four-move-smoke", bundle: .main)
        let provider = ScenarioReplayMoveProvider(scenario: scenario)
        let game = Game(position: scenario.initialPosition)

        XCTAssertFalse(provider.isAutomaticReplay)
        XCTAssertTrue(provider.showsUITestMoveControls)
        XCTAssertEqual(provider.uiTestMoveCoordinates(for: game), ["e2e4", "g1f3", "d2d3"])
        XCTAssertEqual(provider.suggestionMoves(for: game, maxCount: 2).map(\.description), ["e2e4", "g1f3"])

        try game.applyLegal(move: "e2e4")
        XCTAssertEqual(provider.nextMove(for: game, ply: 1)?.description, "e7e5")
        XCTAssertEqual(provider.uiTestMoveCoordinates(for: game), [])

        try game.applyLegal(move: "e7e5")
        XCTAssertEqual(provider.uiTestMoveCoordinates(for: game), ["g1f3", "f1c4", "d2d3"])
    }

    func testTestDrivesBlackProviderSuppliesOnlyWhiteMoves() throws {
        let scenario = try GameScenarioLoader.loadScenario(id: "black-four-move-smoke", bundle: .main)
        let provider = ScenarioReplayMoveProvider(scenario: scenario)
        let game = Game(position: scenario.initialPosition)

        XCTAssertFalse(provider.isAutomaticReplay)
        XCTAssertTrue(provider.showsUITestMoveControls)
        XCTAssertNil(provider.nextMove(for: game, ply: 1))

        XCTAssertEqual(provider.nextMove(for: game, ply: 0)?.description, "e2e4")
        try game.applyLegal(move: try XCTUnwrap(provider.nextMove(for: game, ply: 0)))
        XCTAssertEqual(provider.uiTestMoveCoordinates(for: game), ["e7e5", "b8c6", "g8f6"])
        XCTAssertEqual(provider.suggestionMoves(for: game, maxCount: 3).map(\.description), ["e7e5", "b8c6", "g8f6"])

        try game.applyLegal(move: "e7e5")
        try game.applyLegal(move: try XCTUnwrap(provider.nextMove(for: game, ply: 2)))
        XCTAssertEqual(provider.uiTestMoveCoordinates(for: game), ["b8c6", "g8f6", "f8c5"])
    }

    func testProviderStopsAtScenarioTargetPly() throws {
        let scenario = try GameScenarioLoader.loadScenario(id: "promotion-to-queen", bundle: .main)
        let provider = ScenarioReplayMoveProvider(scenario: scenario)
        let game = Game(position: scenario.initialPosition)

        XCTAssertEqual(provider.nextMove(for: game, ply: 0)?.description, "a7a8q")
        XCTAssertNil(provider.nextMove(for: game, ply: 1))
        XCTAssertEqual(provider.suggestionMoves(for: game, maxCount: 3), [])
        XCTAssertEqual(provider.uiTestMoveCoordinates(for: game), [])
    }
}

@MainActor
final class GameViewModelEngineActivityTests: XCTestCase {
    func testRemainingMinimumThinkingDelayTreatsDelayAsMinimumNotAdditive() {
        let now = Date(timeIntervalSinceReferenceDate: 100)

        XCTAssertEqual(
            GameViewModel.remainingMinimumThinkingDelay(
                startedAt: now.addingTimeInterval(-1),
                now: now,
                minimumDuration: 2.5
            ),
            1.5,
            accuracy: 0.001
        )

        XCTAssertEqual(
            GameViewModel.remainingMinimumThinkingDelay(
                startedAt: now.addingTimeInterval(-10),
                now: now,
                minimumDuration: 2.5
            ),
            0,
            accuracy: 0.001
        )
    }

    func testRemainingMinimumThinkingDelayIsZeroWithoutStartTime() {
        XCTAssertEqual(
            GameViewModel.remainingMinimumThinkingDelay(
                startedAt: nil,
                now: Date(timeIntervalSinceReferenceDate: 100),
                minimumDuration: 2.5
            ),
            0,
            accuracy: 0.001
        )
    }

    func testEngineActivityStateMessagesAndProgress() {
        XCTAssertNil(GameViewModel.EngineActivityState.idle.message)
        XCTAssertFalse(GameViewModel.EngineActivityState.idle.showsProgress)
        XCTAssertEqual(GameViewModel.EngineActivityState.idle.accessibilityValue, "Idle")

        let thinking = GameViewModel.EngineActivityState.thinking(depth: 12)
        XCTAssertEqual(thinking.message, "Stockfish thinking at depth 12...")
        XCTAssertTrue(thinking.showsProgress)

        let timeout = GameViewModel.EngineActivityState.timeoutWaiting(depth: 30)
        XCTAssertEqual(
            timeout.message,
            "Depth 30 timed out; waiting for best move..."
        )
        XCTAssertTrue(timeout.showsProgress)

        let notice = GameViewModel.EngineActivityState.notice("Stockfish timed out; played the best move found so far.")
        XCTAssertEqual(notice.accessibilityValue, "Stockfish timed out; played the best move found so far.")
        XCTAssertFalse(notice.showsProgress)
    }
}

private struct ScenarioExpectation {
    let id: String
    let moveCount: Int
    let targetPly: Int
    var initialFEN: String?
}

private enum TestScenarioData {
    static let validPGN = """
    [Event "Unit Test Scenario"]
    [Site "Local"]
    [Date "2026.06.19"]
    [Round "-"]
    [White "Scenario White"]
    [Black "Scenario Black"]
    [Result "*"]

    1. e4 *
    """

    static func scenarioJSON(
        id: String = "sample",
        title: String = "Sample Scenario",
        pgnResource: String = "sample.pgn",
        playbackMode: String = "automaticReplay",
        stopAfterPly: Int? = 1,
        expectedStatus: String? = "ongoing",
        expectedWinner: String? = nil
    ) -> String {
        var fields: [String] = [
            #""id": "\#(id)""#,
            #""title": "\#(title)""#,
            #""pgnResource": "\#(pgnResource)""#,
            #""playbackMode": "\#(playbackMode)""#,
        ]
        if let stopAfterPly {
            fields.append(#""stopAfterPly": \#(stopAfterPly)"#)
        }
        if let expectedStatus {
            fields.append(#""expectedStatus": "\#(expectedStatus)""#)
        }
        if let expectedWinner {
            fields.append(#""expectedWinner": "\#(expectedWinner)""#)
        }
        return "{\n  \(fields.joined(separator: ",\n  "))\n}"
    }

    static func indexJSON(
        ids: [String] = ["sample"],
        title: String = "Sample Scenario",
        pgnResource: String = "sample.pgn",
        playbackMode: String = "automaticReplay",
        stopAfterPly: Int? = 1,
        expectedStatus: String? = "ongoing",
        expectedWinner: String? = nil
    ) -> String {
        let entries = ids
            .map {
                indexEntryJSON(
                    id: $0,
                    title: title,
                    pgnResource: pgnResource,
                    playbackMode: playbackMode,
                    stopAfterPly: stopAfterPly,
                    expectedStatus: expectedStatus,
                    expectedWinner: expectedWinner
                )
            }
            .joined(separator: ",\n")
        return """
        {
          "version": 1,
          "scenarios": [
        \(entries)
          ]
        }
        """
    }

    private static func indexEntryJSON(
        id: String,
        title: String,
        pgnResource: String,
        playbackMode: String,
        stopAfterPly: Int?,
        expectedStatus: String?,
        expectedWinner: String?
    ) -> String {
        var fields: [String] = [
            #""id": "\#(id)""#,
            #""title": "\#(title)""#,
            #""pgnResource": "\#(pgnResource)""#,
            #""playbackMode": "\#(playbackMode)""#,
        ]
        if let stopAfterPly {
            fields.append(#""stopAfterPly": \#(stopAfterPly)"#)
        }
        if let expectedStatus {
            fields.append(#""expectedStatus": "\#(expectedStatus)""#)
        }
        if let expectedWinner {
            fields.append(#""expectedWinner": "\#(expectedWinner)""#)
        }
        fields.append(#""tags": ["unit-test"]"#)
        fields.append(#""purpose": "Exercise scenario validation in unit tests.""#)

        return """
            {
              \(fields.joined(separator: ",\n      "))
            }
        """
    }
}

private struct TestScenarioBundle {
    let files: [String: String]

    func bundle() throws -> Bundle {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("SwiftChessDemoTests-\(UUID().uuidString)")
            .appendingPathExtension("bundle")

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>trickfest.SwiftChessDemoTests.DynamicBundle</string>
            <key>CFBundlePackageType</key>
            <string>BNDL</string>
        </dict>
        </plist>
        """.write(to: rootURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

        for (relativePath, contents) in files {
            let url = rootURL.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }

        return try XCTUnwrap(Bundle(path: rootURL.path))
    }
}
