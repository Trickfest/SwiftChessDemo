//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and embedded engines.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the MIT License.
// You may obtain a copy of the License in the LICENSE file
// See the LICENSE file for more information.
//

import ChessCore
import ChessUI
import ChessUCI
@testable import SwiftChessDemo
import XCTest

final class StockfishNetworkResourceTests: XCTestCase {
    func testRequiredNetworkIsBundledWithTheApp() throws {
        let networkURL = try XCTUnwrap(StockfishNetworkResource.bundledFileURL())

        XCTAssertEqual(networkURL.lastPathComponent, StockfishNetworkResource.fileName)
        XCTAssertEqual(networkURL.lastPathComponent, "nn-252f33942263.nnue")
        XCTAssertTrue(FileManager.default.fileExists(atPath: networkURL.path))
    }
}

@MainActor
final class StockfishMoveProviderIntegrationTests: XCTestCase {
    func testStockfishProviderSearchesWithBundledNetwork() async {
        let expectedBestMove = expectation(description: "Stockfish returns a best move")
        var didComplete = false

        let provider = StockfishMoveProvider { event in
            switch event {
            case .output(.bestMove(_), _):
                guard !didComplete else { return }
                didComplete = true
                expectedBestMove.fulfill()

            case .failure(let message, _):
                XCTFail("Stockfish startup failed: \(message)")
                guard !didComplete else { return }
                didComplete = true
                expectedBestMove.fulfill()

            case .timeout, .timeoutWithoutBestMove:
                XCTFail("Stockfish timed out before returning a best move")
                guard !didComplete else { return }
                didComplete = true
                expectedBestMove.fulfill()

            case .output:
                return
            }
        }

        provider.startOrQueueSearch(
            EngineSearchRequest(
                engineKind: .stockfish,
                purpose: .opponentMove,
                fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                sideToMove: .white,
                moveTimeMilliseconds: EngineMoveTime.quarterSecond.rawValue,
                multiPVCount: 1,
                safetyTimeoutSeconds: 10
            )
        )

        await fulfillment(of: [expectedBestMove], timeout: 15)
        provider.stop()
        await EmbeddedEngineLifecycleCoordinator.shared.waitForPendingTeardown()
    }

    func testStockfishResumesAfterAnArasanTurnWithoutReloadingItsNetwork() async {
        let firstStockfishMove = expectation(description: "Stockfish returns its first move")
        let arasanMove = expectation(description: "Arasan returns a move")
        let resumedStockfishMove = expectation(description: "Resumed Stockfish returns a move")
        var stockfishBestMoveCount = 0
        var stockfishSearchStarted = Date()
        var stockfishElapsedTimes: [TimeInterval] = []

        let stockfish = StockfishMoveProvider { event in
            switch event {
            case .output(.bestMove(_), _):
                stockfishBestMoveCount += 1
                stockfishElapsedTimes.append(Date().timeIntervalSince(stockfishSearchStarted))
                if stockfishBestMoveCount == 1 {
                    firstStockfishMove.fulfill()
                } else if stockfishBestMoveCount == 2 {
                    resumedStockfishMove.fulfill()
                }

            case .failure(let message, _):
                XCTFail("Stockfish startup failed: \(message)")

            case .timeout, .timeoutWithoutBestMove:
                XCTFail("Stockfish timed out before returning a best move")

            case .output:
                return
            }
        }
        let arasan = ArasanMoveProvider { event in
            switch event {
            case .output(.bestMove(_), _):
                arasanMove.fulfill()

            case .failure(let message, _):
                XCTFail("Arasan startup failed: \(message)")

            case .timeout, .timeoutWithoutBestMove:
                XCTFail("Arasan timed out before returning a best move")

            case .output:
                return
            }
        }
        defer {
            stockfish.stop()
            arasan.stop()
        }

        let startingFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        stockfishSearchStarted = Date()
        stockfish.startOrQueueSearch(
            EngineSearchRequest(
                engineKind: .stockfish,
                purpose: .opponentMove,
                fen: startingFEN,
                sideToMove: .white,
                moveTimeMilliseconds: EngineMoveTime.quarterSecond.rawValue,
                multiPVCount: 1,
                safetyTimeoutSeconds: 10
            )
        )
        await fulfillment(of: [firstStockfishMove], timeout: 15)

        stockfish.suspend()
        await EmbeddedEngineLifecycleCoordinator.shared.waitForPendingTeardown()

        arasan.startOrQueueSearch(
            EngineSearchRequest(
                engineKind: .arasan,
                purpose: .opponentMove,
                fen: startingFEN,
                sideToMove: .white,
                moveTimeMilliseconds: EngineMoveTime.quarterSecond.rawValue,
                multiPVCount: 1,
                safetyTimeoutSeconds: 10
            )
        )
        await fulfillment(of: [arasanMove], timeout: 15)
        arasan.stop()
        await EmbeddedEngineLifecycleCoordinator.shared.waitForPendingTeardown()

        stockfishSearchStarted = Date()
        stockfish.startOrQueueSearch(
            EngineSearchRequest(
                engineKind: .stockfish,
                purpose: .opponentMove,
                fen: startingFEN,
                sideToMove: .white,
                moveTimeMilliseconds: EngineMoveTime.quarterSecond.rawValue,
                multiPVCount: 1,
                safetyTimeoutSeconds: 10
            )
        )
        await fulfillment(of: [resumedStockfishMove], timeout: 15)

        XCTAssertEqual(stockfishElapsedTimes.count, 2)
        if stockfishElapsedTimes.count == 2 {
            print(
                "Stockfish first search: \(stockfishElapsedTimes[0])s; "
                    + "resumed search: \(stockfishElapsedTimes[1])s"
            )
            XCTAssertLessThan(stockfishElapsedTimes[1], stockfishElapsedTimes[0])
        }

        stockfish.stop()
        await EmbeddedEngineLifecycleCoordinator.shared.waitForPendingTeardown()
    }
}

@MainActor
final class ArasanMoveProviderIntegrationTests: XCTestCase {
    func testArasanProviderReportsLargeMaterialEvaluation() async throws {
        try await assertArasanProviderReportsLargeMaterialEvaluation(purpose: .suggestions)
    }

    func testArasanProviderReportsLargeMaterialEvaluationForEvaluationOnlySearch() async throws {
        try await assertArasanProviderReportsLargeMaterialEvaluation(purpose: .evaluation)
    }

    private func assertArasanProviderReportsLargeMaterialEvaluation(
        purpose: EngineSearchPurpose,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let expectedScore = expectation(description: "Arasan reports a queen-sized score")
        var didFulfillExpectedScore = false
        var observedScores: [Int] = []

        let provider = ArasanMoveProvider { event in
            switch event {
            case .output(.info(let info), let request):
                guard let score = info.whiteRelativeScore(sideToMove: request.sideToMove),
                      case .centipawns(let centipawns) = score
                else {
                    return
                }

                observedScores.append(centipawns)
                if centipawns >= 800, !didFulfillExpectedScore {
                    didFulfillExpectedScore = true
                    expectedScore.fulfill()
                }

            case .failure(let message, _):
                XCTFail("Arasan startup failed: \(message)", file: file, line: line)
                if !didFulfillExpectedScore {
                    didFulfillExpectedScore = true
                    expectedScore.fulfill()
                }

            case .timeout, .timeoutWithoutBestMove:
                XCTFail("Arasan timed out before reporting the expected score", file: file, line: line)
                if !didFulfillExpectedScore {
                    didFulfillExpectedScore = true
                    expectedScore.fulfill()
                }

            case .output:
                return
            }
        }
        defer { provider.stop() }

        provider.startOrQueueSearch(
            EngineSearchRequest(
                engineKind: .arasan,
                purpose: purpose,
                fen: "rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
                sideToMove: .white,
                moveTimeMilliseconds: EngineMoveTime.halfSecond.rawValue,
                multiPVCount: 1,
                safetyTimeoutSeconds: 10
            )
        )

        await fulfillment(of: [expectedScore], timeout: 15)
        XCTAssertTrue(
            observedScores.contains { $0 >= 800 },
            "Expected a queen-sized Arasan evaluation, got \(observedScores)",
            file: file,
            line: line
        )

        // `stop()` deliberately moves the native thread join off the main
        // actor. XCTest exits its hosted app immediately after the final test,
        // so wait for that join before process-global Arasan state is destroyed.
        provider.stop()
        await EmbeddedEngineLifecycleCoordinator.shared.waitForPendingTeardown()
    }
}

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

    func testSuggestionProviderReturnsNoMovesForNonPositiveLimit() throws {
        let scenario = try GameScenarioLoader.loadScenario(id: "white-four-move-smoke", bundle: .main)
        let provider = ScenarioReplayMoveProvider(scenario: scenario)
        let game = Game(position: scenario.initialPosition)

        XCTAssertEqual(provider.suggestionMoves(for: game, maxCount: 0), [])
        XCTAssertEqual(provider.suggestionMoves(for: game, maxCount: -1), [])
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

    func testRemainingMinimumThinkingDelayRejectsNonFiniteDuration() {
        XCTAssertEqual(
            GameViewModel.remainingMinimumThinkingDelay(
                startedAt: Date(),
                minimumDuration: .infinity
            ),
            0
        )
        XCTAssertEqual(
            GameViewModel.remainingMinimumThinkingDelay(
                startedAt: Date(),
                minimumDuration: .nan
            ),
            0
        )
    }

    func testEngineActivityStateMessagesAndProgress() {
        XCTAssertNil(GameViewModel.EngineActivityState.idle.message)
        XCTAssertFalse(GameViewModel.EngineActivityState.idle.showsProgress)
        XCTAssertEqual(GameViewModel.EngineActivityState.idle.accessibilityValue, "Idle")

        let thinking = GameViewModel.EngineActivityState.thinking(engine: .stockfish)
        XCTAssertEqual(thinking.message, "Stockfish thinking...")
        XCTAssertTrue(thinking.showsProgress)

        let timeout = GameViewModel.EngineActivityState.timeoutWaiting(engine: .arasan)
        XCTAssertEqual(
            timeout.message,
            "Arasan timed out; waiting for best move..."
        )
        XCTAssertTrue(timeout.showsProgress)

        let notice = GameViewModel.EngineActivityState.notice("Stockfish timed out; played the best move found so far.")
        XCTAssertEqual(notice.accessibilityValue, "Stockfish timed out; played the best move found so far.")
        XCTAssertFalse(notice.showsProgress)
    }

    func testLiveGameCanSwitchSelectedEngineWhenIdle() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel()

        XCTAssertTrue(viewModel.showsEngineSelection)
        XCTAssertTrue(viewModel.canSwitchEngine)
        XCTAssertEqual(viewModel.selectedEngineKind, DemoEngineKind.stockfish)

        viewModel.setSelectedEngineKind(DemoEngineKind.arasan)

        XCTAssertEqual(viewModel.selectedEngineKind, DemoEngineKind.arasan)
        XCTAssertEqual(viewModel.evaluation, ChessEvaluation.unavailable)
        XCTAssertEqual(harness.arasan.requests.last?.purpose, .evaluation)

        viewModel.setSelectedEngineKind(DemoEngineKind.stockfish)

        XCTAssertEqual(viewModel.selectedEngineKind, DemoEngineKind.stockfish)
        XCTAssertEqual(harness.stockfish.requests.last?.purpose, .evaluation)
    }

    func testScenarioGameDoesNotExposeLiveEngineSelection() throws {
        let scenario = try GameScenarioLoader.loadScenario(id: "fools-mate", bundle: .main)
        let viewModel = GameViewModel(
            playerColor: .white,
            pieceSet: .artDecoMonochrome,
            boardTheme: .classicGreen,
            scenario: scenario
        )

        XCTAssertFalse(viewModel.showsEngineSelection)
        XCTAssertFalse(viewModel.canSwitchEngine)
        XCTAssertEqual(viewModel.selectedEngineKind, DemoEngineKind.stockfish)

        viewModel.setSelectedEngineKind(DemoEngineKind.arasan)

        XCTAssertEqual(viewModel.selectedEngineKind, DemoEngineKind.stockfish)
    }

    func testMoveApplicationKeepsDisplayedCopiesIsolatedAndPreservesHistory() throws {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel()
        let game = viewModel.boardModel.game
        let move = try Move(string: "e2e4")

        viewModel.startIfNeeded()
        viewModel.handleUserMove(move: move, isLegal: true)

        XCTAssertFalse(viewModel.boardModel.game === game)
        XCTAssertEqual(game.moveHistory, [])
        XCTAssertEqual(viewModel.boardModel.game.moveHistory, [move])
        XCTAssertEqual(viewModel.moveRecords.map(\.san), ["e4"])
    }

    func testEngineMovePublishesAccessibilityAnnouncement() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(playerColor: .black)

        viewModel.startIfNeeded()
        harness.stockfish.emitBestMove("e2e4")

        XCTAssertEqual(viewModel.moveAnnouncement?.message, "White moved e4.")
    }

    func testSwitchingEngineRetriesOpponentTurnAfterFailure() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(playerColor: .black)

        viewModel.startIfNeeded()
        XCTAssertEqual(harness.stockfish.requireLastRequest().purpose, .opponentMove)
        harness.stockfish.emitFailure("Unavailable")

        XCTAssertTrue(viewModel.canSwitchEngine)
        viewModel.setSelectedEngineKind(.arasan)

        XCTAssertEqual(viewModel.selectedEngineKind, .arasan)
        XCTAssertEqual(harness.arasan.requireLastRequest().purpose, .opponentMove)
        XCTAssertEqual(harness.arasan.requireLastRequest().sideToMove, .white)
    }

    func testResignActionAppearsOnlyForLiveHumanGames() throws {
        let liveViewModel = EngineAnalysisHarness().makeViewModel()
        XCTAssertTrue(liveViewModel.showsResignAction)

        let scenario = try GameScenarioLoader.loadScenario(id: "white-four-move-smoke", bundle: .main)
        let scenarioViewModel = GameViewModel(
            playerColor: .white,
            pieceSet: .artDecoMonochrome,
            boardTheme: .classicGreen,
            scenario: scenario
        )
        XCTAssertFalse(scenarioViewModel.showsResignAction)

        let demoViewModel = EngineAnalysisHarness().makeViewModel(gameMode: .engineVsEngine)
        XCTAssertFalse(demoViewModel.showsResignAction)
    }
}

@MainActor
final class GameViewModelAnalysisRefreshTests: XCTestCase {
    func testStartRequestsEvaluationWhenSuggestionsAreOff() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel()

        viewModel.startIfNeeded()

        XCTAssertEqual(harness.stockfish.requests.map(\.purpose), [.evaluation])
        XCTAssertEqual(harness.stockfish.requests.last?.moveTimeMilliseconds, EngineMoveTime.defaultValue.rawValue)
        XCTAssertEqual(harness.stockfish.requests.last?.multiPVCount, 1)
        XCTAssertEqual(
            harness.stockfish.requests.last?.safetyTimeoutSeconds,
            EngineSearchRequest.defaultSafetyTimeoutSeconds(for: EngineMoveTime.defaultValue.rawValue)
        )
        XCTAssertTrue(viewModel.boardModel.arrows.isEmpty)
    }

    func testEngineSwitchWithSuggestionsOffRequestsEvaluationFromNewEngine() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel()
        viewModel.startIfNeeded()
        harness.stockfish.emitInfo(score: .centipawns(900))

        XCTAssertEqual(viewModel.evaluation, .centipawns(900))

        viewModel.setSelectedEngineKind(.arasan)

        XCTAssertEqual(viewModel.selectedEngineKind, .arasan)
        XCTAssertEqual(viewModel.evaluation, .centipawns(900))
        XCTAssertEqual(harness.stockfish.stopCount, 1)
        XCTAssertEqual(harness.arasan.requests.last?.purpose, .evaluation)
        XCTAssertEqual(harness.arasan.requests.last?.moveTimeMilliseconds, EngineMoveTime.defaultValue.rawValue)

        harness.arasan.emitInfo(score: .centipawns(350))

        XCTAssertEqual(viewModel.evaluation, .centipawns(350))
        XCTAssertTrue(viewModel.boardModel.arrows.isEmpty)
    }

    func testEngineSwitchWithSuggestionsOnRequestsSuggestionsFromNewEngine() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel()
        viewModel.setSuggestionArrowCount(3)
        harness.stockfish.emitInfo(score: .centipawns(120), move: "e2e4", multipv: 1)

        XCTAssertEqual(viewModel.evaluation, .centipawns(120))
        XCTAssertEqual(viewModel.boardModel.arrows.map(\.label), ["Best suggestion e2 to e4"])

        viewModel.setSelectedEngineKind(.arasan)

        XCTAssertEqual(viewModel.selectedEngineKind, .arasan)
        XCTAssertEqual(viewModel.evaluation, .centipawns(120))
        XCTAssertEqual(harness.arasan.requests.last?.purpose, .suggestions)
        XCTAssertEqual(harness.arasan.requests.last?.multiPVCount, 3)

        harness.arasan.emitInfo(score: .centipawns(240), move: "g1f3", multipv: 1)

        XCTAssertEqual(viewModel.evaluation, .centipawns(240))
        XCTAssertEqual(viewModel.boardModel.arrows.map(\.label), ["Best suggestion g1 to f3"])
    }

    func testMoveTimeChangeWithSuggestionsOffRefreshesEvaluationAtNewMoveTime() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel()
        viewModel.startIfNeeded()
        harness.stockfish.emitBestMove("e2e4")

        viewModel.setEngineMoveTime(.fiveSeconds)

        XCTAssertEqual(harness.stockfish.requests.last?.purpose, .evaluation)
        XCTAssertEqual(harness.stockfish.requests.last?.moveTimeMilliseconds, EngineMoveTime.fiveSeconds.rawValue)
        XCTAssertEqual(harness.stockfish.cancelAnalysisCount, 0)
    }

    func testMoveTimeChangeWithSuggestionsOnRefreshesSuggestionsAtNewMoveTime() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel()
        viewModel.setSuggestionArrowCount(3)
        harness.stockfish.emitInfo(score: .centipawns(90), move: "e2e4", multipv: 1)

        viewModel.setEngineMoveTime(.tenSeconds)

        XCTAssertEqual(harness.stockfish.requests.last?.purpose, .suggestions)
        XCTAssertEqual(harness.stockfish.requests.last?.moveTimeMilliseconds, EngineMoveTime.tenSeconds.rawValue)
        XCTAssertEqual(harness.stockfish.requests.last?.multiPVCount, 3)
        XCTAssertEqual(harness.stockfish.cancelAnalysisCount, 1)
        XCTAssertTrue(viewModel.boardModel.arrows.isEmpty)
    }

    func testEngineSwitchUsesCurrentMoveTimeForReplacementAnalysis() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel()
        viewModel.setEngineMoveTime(.tenSeconds)
        harness.stockfish.emitInfo(score: .centipawns(900))

        viewModel.setSelectedEngineKind(.arasan)

        XCTAssertEqual(harness.arasan.requests.last?.purpose, .evaluation)
        XCTAssertEqual(harness.arasan.requests.last?.moveTimeMilliseconds, EngineMoveTime.tenSeconds.rawValue)
        XCTAssertEqual(viewModel.evaluation, .centipawns(900))
    }

    func testStaleEngineOutputAfterSwitchDoesNotOverwriteReplacementAnalysis() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel()
        viewModel.setSuggestionArrowCount(3)

        let stockfishRequest = harness.stockfish.requireLastRequest()
        harness.stockfish.emitInfo(
            score: .centipawns(900),
            move: "d1h5",
            multipv: 1,
            request: stockfishRequest
        )

        viewModel.setSelectedEngineKind(.arasan)
        let arasanRequest = harness.arasan.requireLastRequest()
        harness.arasan.emitInfo(
            score: .centipawns(420),
            move: "g1f3",
            multipv: 1,
            request: arasanRequest
        )

        harness.stockfish.emitInfo(
            score: .centipawns(-600),
            move: "e2e4",
            multipv: 1,
            request: stockfishRequest
        )

        XCTAssertEqual(viewModel.evaluation, .centipawns(420))
        XCTAssertEqual(viewModel.boardModel.arrows.map(\.label), ["Best suggestion g1 to f3"])
    }

    func testStaleMoveTimeOutputDoesNotOverwriteReplacementAnalysis() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel()
        viewModel.setSuggestionArrowCount(3)

        let oneSecondRequest = harness.stockfish.requireLastRequest()
        harness.stockfish.emitInfo(
            score: .centipawns(100),
            move: "e2e4",
            multipv: 1,
            request: oneSecondRequest
        )

        viewModel.setEngineMoveTime(.tenSeconds)
        let tenSecondRequest = harness.stockfish.requireLastRequest()
        harness.stockfish.emitInfo(
            score: .centipawns(300),
            move: "g1f3",
            multipv: 1,
            request: tenSecondRequest
        )

        harness.stockfish.emitInfo(
            score: .centipawns(-500),
            move: "d2d4",
            multipv: 1,
            request: oneSecondRequest
        )

        XCTAssertEqual(viewModel.evaluation, .centipawns(300))
        XCTAssertEqual(viewModel.boardModel.arrows.map(\.label), ["Best suggestion g1 to f3"])
    }

    func testEvaluationBestMoveDoesNotApplyMove() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel()
        viewModel.startIfNeeded()
        let startingFEN = viewModel.positionFEN

        harness.stockfish.emitBestMove("e2e4")

        XCTAssertEqual(viewModel.positionFEN, startingFEN)
        XCTAssertTrue(viewModel.moveRecords.isEmpty)
        XCTAssertEqual(viewModel.boardModel.game.position.state.turn, .white)
    }

    func testSwitchingStockfishToArasanAndBackRestoresAnalysisFromStockfish() {
        assertSwitchingEnginesThereAndBack(
            firstEngine: .stockfish,
            firstMove: "e2e4",
            firstScore: 410,
            secondMove: "g1f3",
            secondScore: -120
        )
    }

    func testSwitchingArasanToStockfishAndBackRestoresAnalysisFromArasan() {
        assertSwitchingEnginesThereAndBack(
            firstEngine: .arasan,
            firstMove: "d2d4",
            firstScore: 275,
            secondMove: "c2c4",
            secondScore: 80
        )
    }

    func testSwitchingEngineBetweenEachMoveOverTenPlyKeepsAnalysisCurrentStartingWithStockfish() {
        assertSwitchingEngineBetweenEachMoveOverTenPly(startingEngine: .stockfish)
    }

    func testSwitchingEngineBetweenEachMoveOverTenPlyKeepsAnalysisCurrentStartingWithArasan() {
        assertSwitchingEngineBetweenEachMoveOverTenPly(startingEngine: .arasan)
    }

    private func assertSwitchingEnginesThereAndBack(
        firstEngine: DemoEngineKind,
        firstMove: String,
        firstScore: Int,
        secondMove: String,
        secondScore: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel()

        if firstEngine != .stockfish {
            viewModel.setSelectedEngineKind(firstEngine)
        }
        viewModel.setSuggestionArrowCount(3)

        let firstProvider = harness.provider(for: firstEngine)
        firstProvider.emitInfo(score: .centipawns(firstScore), move: firstMove, multipv: 1)

        XCTAssertEqual(viewModel.evaluation, .centipawns(firstScore), file: file, line: line)
        XCTAssertEqual(viewModel.boardModel.arrows.map(\.label), [label(for: firstMove)], file: file, line: line)

        let secondEngine = firstEngine == .stockfish ? DemoEngineKind.arasan : .stockfish
        let secondProvider = harness.provider(for: secondEngine)
        viewModel.setSelectedEngineKind(secondEngine)
        secondProvider.emitInfo(score: .centipawns(secondScore), move: secondMove, multipv: 1)

        XCTAssertEqual(viewModel.evaluation, .centipawns(secondScore), file: file, line: line)
        XCTAssertEqual(viewModel.boardModel.arrows.map(\.label), [label(for: secondMove)], file: file, line: line)

        viewModel.setSelectedEngineKind(firstEngine)
        firstProvider.emitInfo(score: .centipawns(firstScore), move: firstMove, multipv: 1)

        XCTAssertEqual(viewModel.evaluation, .centipawns(firstScore), file: file, line: line)
        XCTAssertEqual(viewModel.boardModel.arrows.map(\.label), [label(for: firstMove)], file: file, line: line)
        XCTAssertEqual(harness.provider(for: firstEngine).requests.last?.purpose, .suggestions, file: file, line: line)
    }

    private func assertSwitchingEngineBetweenEachMoveOverTenPly(
        startingEngine: DemoEngineKind,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        struct ScriptedTurn {
            let whiteMove: String
            let blackMove: String
            let nextWhiteSuggestion: String
        }

        let turns = [
            ScriptedTurn(whiteMove: "e2e4", blackMove: "e7e5", nextWhiteSuggestion: "g1f3"),
            ScriptedTurn(whiteMove: "g1f3", blackMove: "b8c6", nextWhiteSuggestion: "f1c4"),
            ScriptedTurn(whiteMove: "f1c4", blackMove: "g8f6", nextWhiteSuggestion: "d2d3"),
            ScriptedTurn(whiteMove: "d2d3", blackMove: "f8c5", nextWhiteSuggestion: "c2c3"),
            ScriptedTurn(whiteMove: "c2c3", blackMove: "d7d6", nextWhiteSuggestion: "b1d2"),
        ]

        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(minimumEngineThinkingSeconds: 0)
        var activeEngine = startingEngine

        if activeEngine != .stockfish {
            viewModel.setSelectedEngineKind(activeEngine)
        }
        viewModel.setSuggestionArrowCount(3)

        for (index, turn) in turns.enumerated() {
            let provider = harness.provider(for: activeEngine)

            XCTAssertEqual(viewModel.selectedEngineKind, activeEngine, file: file, line: line)
            XCTAssertEqual(provider.activePurpose, .suggestions, file: file, line: line)
            XCTAssertEqual(provider.requests.last?.fen, viewModel.positionFEN, file: file, line: line)

            provider.emitInfo(
                score: .centipawns(120 + index),
                move: turn.whiteMove,
                multipv: 1
            )
            XCTAssertEqual(
                viewModel.boardModel.arrows.map(\.label),
                [label(for: turn.whiteMove)],
                file: file,
                line: line
            )

            let whiteMove = try! Move(string: turn.whiteMove)
            XCTAssertTrue(
                viewModel.boardModel.game.legalMoves.contains(whiteMove),
                "\(turn.whiteMove) should be legal at turn \(index + 1)",
                file: file,
                line: line
            )

            viewModel.handleUserMove(move: whiteMove, isLegal: true)
            XCTAssertEqual(provider.requests.last?.purpose, .opponentMove, file: file, line: line)
            XCTAssertTrue(viewModel.boardModel.arrows.isEmpty, file: file, line: line)

            provider.emitInfo(
                score: .centipawns(80 - index),
                move: turn.blackMove
            )
            provider.emitBestMove(turn.blackMove)

            XCTAssertEqual(viewModel.moveRecords.count, (index + 1) * 2, file: file, line: line)
            XCTAssertEqual(viewModel.boardModel.game.position.state.turn, .white, file: file, line: line)
            XCTAssertEqual(provider.requests.last?.purpose, .suggestions, file: file, line: line)
            XCTAssertEqual(provider.requests.last?.fen, viewModel.positionFEN, file: file, line: line)

            activeEngine = activeEngine == .stockfish ? .arasan : .stockfish
            viewModel.setSelectedEngineKind(activeEngine)

            let switchedProvider = harness.provider(for: activeEngine)
            XCTAssertEqual(viewModel.selectedEngineKind, activeEngine, file: file, line: line)
            XCTAssertEqual(switchedProvider.requests.last?.purpose, .suggestions, file: file, line: line)
            XCTAssertEqual(switchedProvider.requests.last?.fen, viewModel.positionFEN, file: file, line: line)

            switchedProvider.emitInfo(
                score: .centipawns(240 + index),
                move: turn.nextWhiteSuggestion,
                multipv: 1
            )
            XCTAssertEqual(
                viewModel.boardModel.arrows.map(\.label),
                [label(for: turn.nextWhiteSuggestion)],
                file: file,
                line: line
            )
        }

        XCTAssertEqual(viewModel.moveRecords.count, 10, file: file, line: line)
        XCTAssertEqual(viewModel.boardModel.game.position.state.turn, .white, file: file, line: line)
        XCTAssertTrue(viewModel.canSwitchEngine, file: file, line: line)
    }

    private func label(for moveText: String) -> String {
        let move = try! Move(string: moveText)
        return "Best suggestion \(move.from.coordinate) to \(move.to.coordinate)"
    }
}

@MainActor
final class GameViewModelEngineDemoTests: XCTestCase {
    func testPieceSizingIsIndependentPerSetInBothGameModes() {
        for mode in [DemoGameMode.humanVsEngine, .engineVsEngine] {
            let harness = EngineAnalysisHarness()
            let viewModel = harness.makeViewModel(gameMode: mode)
            let initialFEN = viewModel.positionFEN
            viewModel.pieceSet = .sashiteMerida
            XCTAssertEqual(viewModel.pieceRenderingScale, 0.80)
            XCTAssertFalse(viewModel.hasPieceRenderingScaleOverride)
            viewModel.setPieceRenderingScale(0.76)
            XCTAssertEqual(viewModel.boardModel.effectiveRenderingScale(for: .sashiteMerida), 0.76)
            viewModel.pieceSet = .artDecoMonochrome
            XCTAssertEqual(viewModel.pieceRenderingScale, 0.85)
            viewModel.setPieceRenderingScale(0.92)
            viewModel.pieceSet = .sashiteMerida
            XCTAssertEqual(viewModel.pieceRenderingScale, 0.76)
            viewModel.resetPieceRenderingScale()
            XCTAssertEqual(viewModel.pieceRenderingScale, 0.80)
            XCTAssertFalse(viewModel.hasPieceRenderingScaleOverride)
            viewModel.pieceSet = .artDecoMonochrome
            XCTAssertEqual(viewModel.pieceRenderingScale, 0.92)
            XCTAssertEqual(viewModel.positionFEN, initialFEN)
        }
    }

    func testCoordinateLabelModesUpdateChessUIModel() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel()

        XCTAssertEqual(viewModel.coordinateLabelMode, .inside)
        XCTAssertTrue(viewModel.boardModel.showsCoordinateLabels)
        XCTAssertEqual(viewModel.boardModel.coordinateLabelPlacement, .inside)

        viewModel.setCoordinateLabelMode(.outside)
        XCTAssertEqual(viewModel.coordinateLabelMode, .outside)
        XCTAssertTrue(viewModel.boardModel.showsCoordinateLabels)
        XCTAssertEqual(viewModel.boardModel.coordinateLabelPlacement, .outside)

        viewModel.setCoordinateLabelMode(.none)
        XCTAssertEqual(viewModel.coordinateLabelMode, .none)
        XCTAssertFalse(viewModel.boardModel.showsCoordinateLabels)
        XCTAssertEqual(viewModel.boardModel.coordinateLabelPlacement, .outside)

        viewModel.setCoordinateLabelMode(.inside)
        XCTAssertEqual(viewModel.coordinateLabelMode, .inside)
        XCTAssertTrue(viewModel.boardModel.showsCoordinateLabels)
        XCTAssertEqual(viewModel.boardModel.coordinateLabelPlacement, .inside)
    }

    func testEngineDemoDefaultConfigurationUsesDefaultMoveTime() {
        let configuration = EngineDemoConfiguration.defaultConfiguration()

        XCTAssertEqual(configuration.white.moveTime, EngineMoveTime.defaultValue)
        XCTAssertEqual(configuration.black.moveTime, EngineMoveTime.defaultValue)
    }

    func testEngineDemoBoardUsesInstantMoveFeedback() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(gameMode: .engineVsEngine)

        XCTAssertEqual(viewModel.boardModel.moveAnimationDuration, GameViewModel.engineDemoMoveAnimationDuration)
        XCTAssertEqual(viewModel.boardModel.moveAnimationDuration, 0)
    }

    func testHumanVsEngineBoardKeepsAnimatedMoveFeedback() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(gameMode: .humanVsEngine)

        XCTAssertGreaterThan(viewModel.boardModel.moveAnimationDuration, 0)
    }

    func testEngineDemoStartsPausedWithoutRequestingSearch() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(gameMode: .engineVsEngine)

        viewModel.startIfNeeded()

        XCTAssertTrue(viewModel.isEngineDemoMode)
        XCTAssertFalse(viewModel.showsEngineSelection)
        XCTAssertEqual(viewModel.engineDemoRunState, .paused)
        XCTAssertTrue(harness.stockfish.requests.isEmpty)
        XCTAssertTrue(harness.arasan.requests.isEmpty)
    }

    func testEngineDemoStepAppliesOneMoveAndRemainsPaused() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(
            gameMode: .engineVsEngine,
            engineDemoConfiguration: EngineDemoConfiguration(
                white: EngineDemoSideConfiguration(engineKind: .stockfish, moveTime: .halfSecond),
                black: EngineDemoSideConfiguration(engineKind: .arasan, moveTime: .twoSeconds),
                pacing: .fast
            )
        )

        viewModel.startIfNeeded()
        viewModel.stepEngineDemo()

        XCTAssertEqual(viewModel.engineDemoRunState, .stepping)
        XCTAssertEqual(harness.stockfish.requireLastRequest().purpose, .opponentMove)
        XCTAssertEqual(harness.stockfish.requireLastRequest().moveTimeMilliseconds, EngineMoveTime.halfSecond.rawValue)
        XCTAssertEqual(harness.stockfish.requireLastRequest().sideToMove, .white)
        XCTAssertEqual(
            harness.stockfish.requireLastRequest().safetyTimeoutSeconds,
            EngineSearchRequest.defaultSafetyTimeoutSeconds(for: EngineMoveTime.halfSecond.rawValue)
        )

        harness.stockfish.emitBestMove("e2e4")

        XCTAssertEqual(viewModel.moveRecords.count, 1)
        XCTAssertEqual(viewModel.boardModel.game.position.state.turn, .black)
        XCTAssertEqual(viewModel.engineDemoRunState, .paused)
        XCTAssertTrue(harness.arasan.requests.isEmpty)
    }

    func testEngineDemoPlayAlternatesSideEnginesAndMoveTimes() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(
            gameMode: .engineVsEngine,
            engineDemoConfiguration: EngineDemoConfiguration(
                white: EngineDemoSideConfiguration(engineKind: .stockfish, moveTime: .halfSecond),
                black: EngineDemoSideConfiguration(engineKind: .arasan, moveTime: .fiveSeconds),
                pacing: .fast
            )
        )

        viewModel.startIfNeeded()
        viewModel.playEngineDemo()

        XCTAssertEqual(harness.stockfish.requireLastRequest().sideToMove, .white)
        XCTAssertEqual(harness.stockfish.requireLastRequest().moveTimeMilliseconds, EngineMoveTime.halfSecond.rawValue)
        XCTAssertEqual(
            harness.stockfish.requireLastRequest().safetyTimeoutSeconds,
            EngineSearchRequest.defaultSafetyTimeoutSeconds(for: EngineMoveTime.halfSecond.rawValue)
        )

        harness.stockfish.emitBestMove("e2e4")

        XCTAssertEqual(harness.stockfish.suspendCount, 1)
        XCTAssertEqual(harness.stockfish.stopCount, 1)
        XCTAssertEqual(harness.arasan.requireLastRequest().sideToMove, .black)
        XCTAssertEqual(harness.arasan.requireLastRequest().moveTimeMilliseconds, EngineMoveTime.fiveSeconds.rawValue)
        XCTAssertEqual(
            harness.arasan.requireLastRequest().safetyTimeoutSeconds,
            EngineSearchRequest.defaultSafetyTimeoutSeconds(for: EngineMoveTime.fiveSeconds.rawValue)
        )

        harness.arasan.emitBestMove("e7e5")

        XCTAssertEqual(harness.arasan.suspendCount, 1)
        XCTAssertEqual(harness.arasan.stopCount, 1)
        XCTAssertEqual(harness.stockfish.requireLastRequest().sideToMove, .white)
        XCTAssertEqual(harness.stockfish.requireLastRequest().moveTimeMilliseconds, EngineMoveTime.halfSecond.rawValue)
        XCTAssertEqual(viewModel.moveRecords.count, 2)
        XCTAssertEqual(viewModel.engineDemoRunState, .playing)
    }

    func testEngineDemoMoveTimeChangeAppliesToFutureSearchesOnly() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(
            gameMode: .engineVsEngine,
            engineDemoConfiguration: EngineDemoConfiguration(
                white: EngineDemoSideConfiguration(engineKind: .stockfish, moveTime: .halfSecond),
                black: EngineDemoSideConfiguration(engineKind: .arasan, moveTime: .oneSecond),
                pacing: .fast
            )
        )

        viewModel.startIfNeeded()
        viewModel.stepEngineDemo()

        let firstRequest = harness.stockfish.requireLastRequest()
        XCTAssertEqual(firstRequest.moveTimeMilliseconds, EngineMoveTime.halfSecond.rawValue)

        viewModel.setEngineDemoMoveTime(.fiveSeconds, for: .black)
        XCTAssertEqual(firstRequest.moveTimeMilliseconds, EngineMoveTime.halfSecond.rawValue)

        harness.stockfish.emitBestMove("e2e4")
        viewModel.stepEngineDemo()

        XCTAssertEqual(harness.arasan.requireLastRequest().moveTimeMilliseconds, EngineMoveTime.fiveSeconds.rawValue)
    }

    func testEngineDemoPauseDuringSearchFinishesCurrentMoveWithoutStartingNextSearch() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(
            gameMode: .engineVsEngine,
            engineDemoConfiguration: EngineDemoConfiguration(
                white: EngineDemoSideConfiguration(engineKind: .stockfish, moveTime: .halfSecond),
                black: EngineDemoSideConfiguration(engineKind: .arasan, moveTime: .twoSeconds),
                pacing: .fast
            )
        )

        viewModel.startIfNeeded()
        viewModel.playEngineDemo()
        viewModel.pauseEngineDemo()

        XCTAssertEqual(viewModel.engineDemoRunState, .pausingAfterCurrentMove)

        harness.stockfish.emitBestMove("e2e4")

        XCTAssertEqual(viewModel.moveRecords.count, 1)
        XCTAssertEqual(viewModel.boardModel.game.position.state.turn, .black)
        XCTAssertEqual(viewModel.engineDemoRunState, .paused)
        XCTAssertTrue(harness.arasan.requests.isEmpty)
    }

    func testEngineDemoAutoClaimsThreefoldRepetitionOnStart() throws {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(
            gameMode: .engineVsEngine, initialTimeline: try Self.claimableThreefoldTimeline()
        )

        viewModel.startIfNeeded()

        XCTAssertEqual(viewModel.boardModel.game.status, .draw(.threefoldRepetition))
        XCTAssertEqual(viewModel.engineDemoRunState, .paused)
        XCTAssertTrue(harness.stockfish.requests.isEmpty)
        assertResultAlert(viewModel.activeAlert, title: "Draw by repetition", message: "Draw")
    }

    func testEngineDemoAutoClaimsFiftyMoveRuleOnStart() throws {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(
            gameMode: .engineVsEngine,
            initialTimeline: try Self.timeline(from: "4k3/8/8/8/8/8/Q7/4K3 w - - 100 1")
        )

        viewModel.startIfNeeded()

        XCTAssertEqual(viewModel.boardModel.game.status, .draw(.fiftyMoveRule))
        XCTAssertEqual(viewModel.engineDemoRunState, .paused)
        XCTAssertTrue(harness.stockfish.requests.isEmpty)
        assertResultAlert(viewModel.activeAlert, title: "Draw by 50-move rule", message: "Draw")
    }

    func testEngineDemoPrefersThreefoldWhenMultipleDrawClaimsAreAvailable() throws {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(
            gameMode: .engineVsEngine, initialTimeline: try Self.claimableThreefoldTimeline(halfmoveClock: 92)
        )

        viewModel.startIfNeeded()

        XCTAssertEqual(viewModel.boardModel.game.status, .draw(.threefoldRepetition))
        assertResultAlert(viewModel.activeAlert, title: "Draw by repetition", message: "Draw")
    }

    func testEngineDemoTerminalStateExposesPlayAgainWithoutStaleWork() throws {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(
            gameMode: .engineVsEngine, initialTimeline: try Self.claimableThreefoldTimeline()
        )

        viewModel.startIfNeeded()

        XCTAssertEqual(viewModel.boardModel.game.status, .draw(.threefoldRepetition))
        XCTAssertEqual(viewModel.engineDemoRunState, .paused)
        XCTAssertEqual(viewModel.engineDemoPrimaryControlTitle, "Play Again")
        XCTAssertTrue(viewModel.canRestartEngineDemo)
        XCTAssertFalse(viewModel.canStepEngineDemo)
        XCTAssertEqual(viewModel.engineActivity, .idle)
        XCTAssertNil(viewModel.engineDemoLastMoveConfiguration)
        XCTAssertTrue(harness.stockfish.requests.isEmpty)
        XCTAssertTrue(harness.arasan.requests.isEmpty)
        assertResultAlert(viewModel.activeAlert, title: "Draw by repetition", message: "Draw")
    }

    func testEngineDemoPlayAgainResetsBoardAndStartsFromCurrentSettings() throws {
        let harness = EngineAnalysisHarness()
        let initialConfiguration = EngineDemoConfiguration(
            white: EngineDemoSideConfiguration(engineKind: .stockfish, moveTime: .oneSecond),
            black: EngineDemoSideConfiguration(engineKind: .arasan, moveTime: .twoSeconds),
            pacing: .fiveSeconds,
            stress: EngineDemoStressConfiguration(
                isEnabled: true,
                randomizesEngineEachMove: false,
                randomizesMoveTimeEachMove: false,
                minimumMoveTime: .quarterSecond,
                maximumMoveTime: .fiveSeconds,
                seed: 99
            )
        )
        let viewModel = harness.makeViewModel(
            gameMode: .engineVsEngine,
            engineDemoConfiguration: initialConfiguration,
            initialTimeline: try GameTimeline(moves: ["f2f3", "e7e5", "g2g4", "d8h4"].map(Move.init(string:)))
        )

        viewModel.startIfNeeded()
        viewModel.setEngineDemoEngineKind(.arasan, for: .white)
        viewModel.setEngineDemoMoveTime(.halfSecond, for: .white)
        viewModel.setEngineDemoMoveTime(.fiveSeconds, for: .black)
        viewModel.activeAlert = nil

        viewModel.toggleEngineDemoPlayback()

        let standardFEN = FENSerializer().fen(from: Position.standard)
        XCTAssertEqual(viewModel.positionFEN, standardFEN)
        XCTAssertEqual(viewModel.boardModel.fen, standardFEN)
        XCTAssertEqual(viewModel.moveRecords, [])
        XCTAssertEqual(viewModel.selectedMovePly, 0)
        XCTAssertEqual(viewModel.evaluation, .unavailable)
        XCTAssertEqual(viewModel.engineDemoRunState, .playing)
        XCTAssertFalse(viewModel.canRestartEngineDemo)
        XCTAssertFalse(viewModel.canStepEngineDemo)
        XCTAssertNil(viewModel.activeAlert)
        XCTAssertEqual(viewModel.engineDemoConfiguration.pacing, .fiveSeconds)
        XCTAssertEqual(viewModel.engineDemoConfiguration.stress, initialConfiguration.stress)
        XCTAssertEqual(viewModel.engineDemoConfiguration.white.engineKind, .arasan)
        XCTAssertEqual(viewModel.engineDemoConfiguration.white.moveTime, .halfSecond)
        XCTAssertEqual(viewModel.engineDemoConfiguration.black.moveTime, .fiveSeconds)

        let request = harness.arasan.requireLastRequest()
        XCTAssertEqual(request.fen, standardFEN)
        XCTAssertEqual(request.sideToMove, .white)
        XCTAssertEqual(request.moveTimeMilliseconds, EngineMoveTime.halfSecond.rawValue)
        XCTAssertEqual(viewModel.engineDemoLastMoveConfiguration?.side, .white)
        XCTAssertEqual(viewModel.engineDemoLastMoveConfiguration?.engineKind, .arasan)
        XCTAssertEqual(viewModel.engineDemoLastMoveConfiguration?.moveTime, .halfSecond)
        XCTAssertTrue(harness.stockfish.requests.isEmpty)
    }

    func testHumanVsEngineDoesNotAutoClaimThreefoldRepetition() throws {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(
            gameMode: .humanVsEngine, initialTimeline: try Self.claimableThreefoldTimeline()
        )

        viewModel.startIfNeeded()

        XCTAssertEqual(viewModel.boardModel.game.status, .ongoing(drawClaims: [.threefoldRepetition]))
        XCTAssertNil(viewModel.activeAlert)
    }

    func testHumanVsEngineDoesNotAutoClaimFiftyMoveRule() throws {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(
            gameMode: .humanVsEngine,
            initialTimeline: try Self.timeline(from: "4k3/8/8/8/8/8/Q7/4K3 w - - 100 1")
        )

        viewModel.startIfNeeded()

        XCTAssertEqual(viewModel.boardModel.game.status, .ongoing(drawClaims: [.fiftyMoveRule]))
        XCTAssertNil(viewModel.activeAlert)
    }

    func testEngineDemoPausedConfigurationChangeAppliesToNextStep() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(gameMode: .engineVsEngine)

        viewModel.startIfNeeded()
        viewModel.setEngineDemoEngineKind(.arasan, for: .white)
        viewModel.setEngineDemoMoveTime(.fiveSeconds, for: .white)
        viewModel.stepEngineDemo()

        XCTAssertTrue(harness.stockfish.requests.isEmpty)
        XCTAssertEqual(harness.arasan.requireLastRequest().sideToMove, .white)
        XCTAssertEqual(harness.arasan.requireLastRequest().moveTimeMilliseconds, EngineMoveTime.fiveSeconds.rawValue)
    }

    func testEngineDemoStressModeRandomizesBeforeEachSearchAcrossTenPly() {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(
            gameMode: .engineVsEngine,
            engineDemoConfiguration: EngineDemoConfiguration(
                white: EngineDemoSideConfiguration(engineKind: .stockfish, moveTime: .oneSecond),
                black: EngineDemoSideConfiguration(engineKind: .arasan, moveTime: .oneSecond),
                pacing: .fast,
                stress: EngineDemoStressConfiguration(
                    isEnabled: true,
                    randomizesEngineEachMove: true,
                    randomizesMoveTimeEachMove: true,
                    minimumMoveTime: .quarterSecond,
                    maximumMoveTime: .oneSecond,
                    seed: 42
                )
            )
        )
        let moves = [
            "e2e4", "e7e5",
            "g1f3", "b8c6",
            "f1c4", "g8f6",
            "d2d3", "f8c5",
            "c2c3", "d7d6",
        ]
        var chosenEngines: Set<DemoEngineKind> = []
        var chosenMoveTimes: [EngineMoveTime] = []

        viewModel.startIfNeeded()
        viewModel.playEngineDemo()

        for (index, move) in moves.enumerated() {
            let moveConfiguration = try! XCTUnwrap(viewModel.engineDemoLastMoveConfiguration)
            let provider = harness.provider(for: moveConfiguration.engineKind)
            let request = provider.requireLastRequest()

            chosenEngines.insert(moveConfiguration.engineKind)
            chosenMoveTimes.append(moveConfiguration.moveTime)
            XCTAssertEqual(moveConfiguration.side, index.isMultiple(of: 2) ? .white : .black)
            XCTAssertEqual(request.sideToMove, moveConfiguration.side)
            XCTAssertEqual(request.moveTimeMilliseconds, moveConfiguration.moveTime.rawValue)
            XCTAssertTrue(
                (EngineMoveTime.quarterSecond.rawValue...EngineMoveTime.oneSecond.rawValue)
                    .contains(moveConfiguration.moveTime.rawValue)
            )

            provider.emitBestMove(move)
        }

        XCTAssertEqual(viewModel.moveRecords.count, 10)
        XCTAssertEqual(viewModel.boardModel.game.position.state.turn, .white)
        XCTAssertEqual(chosenEngines, Set(DemoEngineKind.allCases))
        XCTAssertGreaterThan(Set(chosenMoveTimes).count, 1)
    }

    private static func claimableThreefoldTimeline(halfmoveClock: Int = 0) throws -> GameTimeline {
        var timeline = try timeline(from: "8/8/8/8/8/6k1/8/R3K3 w - - \(halfmoveClock) 1")
        for coordinate in ["e1d1", "g3f3", "d1e1", "f3g3", "e1d1", "g3f3", "d1e1", "f3g3"] {
            try timeline.append(Move(string: coordinate))
        }
        XCTAssertTrue(try timeline.game(atPly: timeline.moveCount).drawClaims.contains(.threefoldRepetition))
        return timeline
    }

    private static func timeline(from fen: String) throws -> GameTimeline {
        try GameTimeline(initialPosition: FENSerializer().position(from: fen))
    }
}

@MainActor
final class GameViewModelHistoryTests: XCTestCase {
    func testRecordedScoresFollowSearchedPlyAndEngineWithoutStartingHistoricalSearches() throws {
        let harness = EngineAnalysisHarness()
        var configuration = Self.fastDemo
        configuration.black.engineKind = .arasan
        let model = harness.makeViewModel(gameMode: .engineVsEngine, engineDemoConfiguration: configuration)
        defer { model.cleanup() }
        model.startIfNeeded()
        model.stepEngineDemo()
        XCTAssertEqual(harness.stockfish.requireLastRequest().positionPly, 0)
        harness.stockfish.emitInfo(score: .centipawns(40), depth: 11)
        harness.stockfish.emitBestMove("e2e4")
        model.stepEngineDemo()
        let blackRequest = harness.arasan.requireLastRequest()
        XCTAssertEqual(blackRequest.positionPly, 1)
        harness.arasan.emitInfo(score: .centipawns(75), depth: 12)
        harness.arasan.emitBestMove("e7e5")
        let requestCount = harness.stockfish.requests.count + harness.arasan.requests.count

        model.selectPosition(atPly: 0)
        XCTAssertEqual(model.displayedEvaluation, .centipawns(40))
        XCTAssertEqual(model.displayedRecordedEvaluation?.engineKind, .stockfish)
        XCTAssertEqual(model.recordedEvaluationDescription, "Recorded evaluation · Stockfish · depth 11")
        model.selectPosition(atPly: 1)
        XCTAssertEqual(model.displayedEvaluation, .centipawns(-75))
        XCTAssertEqual(model.displayedRecordedEvaluation?.fen, blackRequest.fen)
        XCTAssertEqual(model.displayedRecordedEvaluation?.fen, model.positionFEN)
        XCTAssertEqual(model.displayedRecordedEvaluation?.engineKind, .arasan)
        XCTAssertEqual(model.recordedEvaluationDescription, "Recorded evaluation · Arasan · depth 12")
        model.setEvaluationBarVisible(false)
        model.setEvaluationBarVisible(true)
        XCTAssertEqual(model.displayedEvaluation, .centipawns(-75))
        model.returnToLive()
        XCTAssertEqual(model.displayedEvaluation, model.evaluation)
        XCTAssertNil(model.displayedRecordedEvaluation)
        XCTAssertEqual(harness.stockfish.requests.count + harness.arasan.requests.count, requestCount)
    }

    func testHumanAnalysisAndOpponentMateScoresRemainAttachedToTheirPositions() throws {
        let harness = EngineAnalysisHarness()
        let model = harness.makeViewModel()
        defer { model.cleanup() }
        model.startIfNeeded()
        harness.stockfish.emitInfo(score: .centipawns(25), depth: 10)
        model.handleUserMove(move: try Move(string: "e2e4"), isLegal: true)
        harness.stockfish.emitInfo(score: .mate(-3), depth: 15)
        harness.stockfish.emitBestMove("e7e5")
        harness.stockfish.emitInfo(score: .centipawns(80), depth: 13)
        let requestCount = harness.stockfish.requests.count

        model.selectPosition(atPly: 1)
        XCTAssertEqual(model.displayedEvaluation, .mate(moves: 3, side: .white))
        XCTAssertEqual(model.displayedRecordedEvaluation?.depth, 15)
        model.selectPosition(atPly: 0)
        XCTAssertEqual(model.displayedEvaluation, .centipawns(25))
        harness.stockfish.emitInfo(score: .centipawns(95), depth: 14)
        XCTAssertEqual(model.displayedEvaluation, .centipawns(25))
        XCTAssertEqual(model.evaluation, .centipawns(95))
        model.returnToLive()
        XCTAssertEqual(model.displayedEvaluation, .centipawns(95))
        XCTAssertEqual(harness.stockfish.requests.count, requestCount)
    }

    func testRecordedEvaluationUsesPrimaryExactScoreAndRetainsItAcrossEngineChanges() throws {
        let harness = EngineAnalysisHarness()
        let model = harness.makeViewModel()
        defer { model.cleanup() }
        model.setSuggestionArrowCount(3)
        harness.stockfish.emitInfo(score: .centipawns(35), move: "e2e4", multipv: 1, depth: 9)
        harness.stockfish.emitInfo(score: .centipawns(-90), move: "d2d4", multipv: 2, depth: 9)
        harness.stockfish.emitInfo(score: .centipawns(200), depth: 10, scoreBound: .lowerbound)
        harness.stockfish.emitInfo(score: .centipawns(-200), depth: 10, scoreBound: .upperbound)
        let oldRequest = harness.stockfish.requireLastRequest()
        model.handleUserMove(move: try Move(string: "e2e4"), isLegal: true)
        model.selectPosition(atPly: 0)
        XCTAssertEqual(model.displayedEvaluation, .centipawns(35))
        XCTAssertEqual(model.displayedRecordedEvaluation?.depth, 9)
        // Output from an obsolete search cannot overwrite the recorded root.
        harness.stockfish.emitInfo(score: .centipawns(999), request: oldRequest)
        XCTAssertEqual(model.displayedEvaluation, .centipawns(35))
        model.setSelectedEngineKind(.arasan)
        XCTAssertEqual(model.displayedRecordedEvaluation?.engineKind, .stockfish)
        XCTAssertEqual(model.displayedEvaluation, .centipawns(35))
    }

    func testMissingHistoricalEvaluationDoesNotBorrowAdjacentScore() throws {
        let harness = EngineAnalysisHarness()
        let model = harness.makeViewModel(gameMode: .engineVsEngine, engineDemoConfiguration: Self.fastDemo)
        defer { model.cleanup() }
        model.startIfNeeded()
        model.stepEngineDemo()
        harness.stockfish.emitBestMove("e2e4") // No score was reported for the root.
        model.stepEngineDemo()
        harness.stockfish.emitInfo(score: .centipawns(80))
        harness.stockfish.emitBestMove("e7e5")
        model.selectPosition(atPly: 0)
        XCTAssertEqual(model.displayedEvaluation, .unavailable)
        XCTAssertNil(model.displayedRecordedEvaluation)
        XCTAssertEqual(model.recordedEvaluationDescription, "Not evaluated")
        model.selectPosition(atPly: 1)
        XCTAssertEqual(model.displayedEvaluation, .centipawns(-80))
    }

    func testRecordedBlackRootScoreUsesTimelinePlyInsteadOfFullMoveNumber() throws {
        let root = try FENSerializer().position(from: "7k/8/8/8/8/8/p7/7K b - - 0 42")
        let harness = EngineAnalysisHarness()
        let model = harness.makeViewModel(
            gameMode: .engineVsEngine, engineDemoConfiguration: Self.fastDemo,
            initialTimeline: try GameTimeline(initialPosition: root)
        )
        defer { model.cleanup() }
        model.startIfNeeded()
        model.stepEngineDemo()
        XCTAssertEqual(harness.stockfish.requireLastRequest().positionPly, 0)
        harness.stockfish.emitInfo(score: .centipawns(70), depth: 8)
        harness.stockfish.emitBestMove("a2a1q")
        model.selectPosition(atPly: 0)
        XCTAssertEqual(model.displayedEvaluation, .centipawns(-70))
        XCTAssertEqual(model.displayedRecordedEvaluation?.fen, FENSerializer().fen(from: root))
    }

    func testPendingOpponentReplyUsesLiveGameAndLeavesHistoricalSelectionUnchanged() throws {
        let harness = EngineAnalysisHarness()
        let model = harness.makeViewModel()
        defer { model.cleanup() }
        model.startIfNeeded()
        model.handleUserMove(move: try Move(string: "e2e4"), isLegal: true)
        let request = harness.stockfish.requireLastRequest()
        let requestCount = harness.stockfish.requests.count
        let cancelCount = harness.stockfish.cancelAnalysisCount
        model.selectPosition(atPly: 0)

        XCTAssertTrue(model.isBrowsingHistory)
        XCTAssertEqual(model.boardModel.interactionMode, .readOnly)
        XCTAssertEqual(model.displayedSideToMove, .white)
        XCTAssertEqual(model.sideToMove, .black)
        XCTAssertEqual(harness.stockfish.requests.count, requestCount)
        XCTAssertEqual(harness.stockfish.cancelAnalysisCount, cancelCount)
        XCTAssertEqual(request.fen, model.livePositionFEN)
        XCTAssertNotEqual(request.fen, model.positionFEN)

        // A legal move on the historical board cannot become a live move.
        model.handleUserMove(move: try Move(string: "d2d4"), isLegal: true)
        XCTAssertEqual(model.liveMoveCount, 1)
        harness.stockfish.emitInfo(score: .centipawns(35))
        harness.stockfish.emitBestMove("e7e5")
        XCTAssertEqual(model.moveRecords.map(\.san), ["e4", "e5"])
        XCTAssertEqual(model.selectedMovePly, 0)
        XCTAssertEqual(model.moveAnnouncement?.message, "Live game: Black moved e5.")
        XCTAssertEqual(model.positionFEN, FENSerializer().fen(from: .standard))
        XCTAssertEqual(model.displayedEvaluation, .unavailable)
        XCTAssertEqual(model.boardModel.game.moveHistory.count, 0)
        XCTAssertEqual(harness.stockfish.requireLastRequest().fen, model.livePositionFEN)

        let searchesBeforeReturn = harness.stockfish.requests.count
        model.returnToLive()
        XCTAssertFalse(model.isBrowsingHistory)
        XCTAssertEqual(model.selectedMovePly, 2)
        XCTAssertEqual(model.positionFEN, model.livePositionFEN)
        XCTAssertEqual(model.boardModel.game.moveHistory.count, 2)
        XCTAssertEqual(model.boardModel.interactionMode, .legalMovesOnly)
        XCTAssertEqual(harness.stockfish.requests.count, searchesBeforeReturn)
        model.handleUserMove(move: try Move(string: "g1f3"), isLegal: true)
        XCTAssertEqual(model.moveRecords.map(\.san), ["e4", "e5", "Nf3"])
        XCTAssertEqual(model.selectedMovePly, 3)
    }

    func testDelayedOpponentApplicationSurvivesHistoryBrowsing() async throws {
        let harness = EngineAnalysisHarness()
        let model = harness.makeViewModel(minimumEngineThinkingSeconds: 0.08)
        defer { model.cleanup() }
        model.startIfNeeded()
        model.handleUserMove(move: try Move(string: "e2e4"), isLegal: true)
        harness.stockfish.emitBestMove("e7e5")
        model.selectPosition(atPly: 0)
        await waitUntil { model.liveMoveCount == 2 }
        XCTAssertEqual(model.liveMoveCount, 2)
        XCTAssertEqual(model.selectedMovePly, 0)
        XCTAssertEqual(model.boardModel.game.moveHistory, [])
    }

    func testEngineDemoContinuesAndPausesAgainstLiveStateWhileBrowsing() throws {
        let harness = EngineAnalysisHarness()
        let model = harness.makeViewModel(gameMode: .engineVsEngine, engineDemoConfiguration: Self.fastDemo)
        defer { model.cleanup() }
        model.startIfNeeded()
        model.stepEngineDemo()
        harness.stockfish.emitBestMove("e2e4")
        model.selectPosition(atPly: 0)
        XCTAssertEqual(model.engineDemoRunState, .paused)
        let countBeforeNavigation = harness.stockfish.requests.count
        model.selectPosition(atPly: 1)
        model.selectPosition(atPly: 0)
        XCTAssertEqual(harness.stockfish.requests.count, countBeforeNavigation)

        model.playEngineDemo()
        XCTAssertEqual(harness.stockfish.requireLastRequest().sideToMove, .black)
        XCTAssertEqual(harness.stockfish.requireLastRequest().fen, model.livePositionFEN)
        harness.stockfish.emitBestMove("e7e5")
        XCTAssertEqual(model.selectedMovePly, 0)
        XCTAssertEqual(model.liveMoveCount, 2)
        XCTAssertEqual(model.engineDemoRunState, .playing)
        XCTAssertEqual(harness.stockfish.requireLastRequest().sideToMove, .white)
        model.pauseEngineDemo()
        XCTAssertEqual(model.engineDemoRunState, .pausingAfterCurrentMove)
        harness.stockfish.emitBestMove("g1f3")
        XCTAssertEqual(model.engineDemoRunState, .paused)
        XCTAssertEqual(model.selectedMovePly, 0)
        XCTAssertTrue(model.canStepEngineDemo)
        model.stepEngineDemo()
        XCTAssertEqual(harness.stockfish.requireLastRequest().sideToMove, .black)
        harness.stockfish.emitBestMove("b8c6")
        XCTAssertEqual(model.liveMoveCount, 4)
        XCTAssertEqual(model.selectedMovePly, 0)
        model.returnToLive()
        XCTAssertEqual(model.boardModel.game.moveHistory.count, 4)
        XCTAssertEqual(model.boardModel.interactionMode, .readOnly)
        XCTAssertEqual(model.engineDemoRunState, .paused)
    }

    func testCompletionResetAndSamePositionStaleRepliesRetainExactRequestIdentity() throws {
        let harness = EngineAnalysisHarness()
        let model = harness.makeViewModel(gameMode: .engineVsEngine, engineDemoConfiguration: Self.fastDemo)
        defer { model.cleanup() }
        model.startIfNeeded()
        model.playEngineDemo()
        let oldRootRequest = harness.stockfish.requireLastRequest()
        harness.stockfish.emitInfo(score: .centipawns(35))
        harness.stockfish.emitBestMove("f2f3")
        model.selectPosition(atPly: 0)
        for move in ["e7e5", "g2g4", "d8h4"] { harness.stockfish.emitBestMove(move) }
        XCTAssertEqual(model.gameStatus, .checkmate(winner: .black))
        XCTAssertEqual(model.displayedGameStatus, .ongoing(drawClaims: []))
        XCTAssertEqual(model.selectedMovePly, 0)
        XCTAssertEqual(model.displayedEvaluation, .centipawns(35))
        XCTAssertTrue(model.canRestartEngineDemo)
        XCTAssertEqual(model.engineDemoRunState, .paused)
        model.returnToLive()
        XCTAssertEqual(model.displayedGameStatus, .checkmate(winner: .black))
        model.selectPosition(atPly: 1)
        model.restartEngineDemoAndPlay()
        let newRootRequest = harness.stockfish.requireLastRequest()
        XCTAssertEqual(oldRootRequest.fen, newRootRequest.fen)
        XCTAssertNotEqual(oldRootRequest.id, newRootRequest.id)
        XCTAssertEqual(model.selectedMovePly, 0)
        XCTAssertFalse(model.isBrowsingHistory)
        XCTAssertEqual(model.liveMoveCount, 0)
        harness.stockfish.emitInfo(score: .centipawns(999), request: oldRootRequest)
        harness.stockfish.emitBestMove("d2d4", request: oldRootRequest)
        XCTAssertEqual(model.liveMoveCount, 0)
        XCTAssertEqual(model.evaluation, .unavailable)
        harness.stockfish.emitBestMove("e2e4")
        XCTAssertEqual(model.moveRecords.map(\.san), ["e4"])
        XCTAssertEqual(model.selectedMovePly, 1)
        model.selectPosition(atPly: 0)
        XCTAssertEqual(model.displayedEvaluation, .unavailable)
        XCTAssertNil(model.displayedRecordedEvaluation)
    }

    func testClaimedDrawRemainsLiveOnlyAndCannotBeClaimedFromHistory() throws {
        let moves = ["g1f3", "g8f6", "f3g1", "f6g8", "g1f3", "g8f6", "f3g1", "f6g8"]
        let harness = EngineAnalysisHarness()
        let model = harness.makeViewModel(initialTimeline: try Self.timeline(moves))
        defer { model.cleanup() }
        model.selectPosition(atPly: 0)
        model.claimDraw(.threefoldRepetition)
        XCTAssertTrue(model.isGameOngoing)
        XCTAssertNil(model.activeAlert)
        model.returnToLive()
        model.claimDraw(.threefoldRepetition)
        XCTAssertEqual(model.gameStatus, .draw(.threefoldRepetition))
        XCTAssertEqual(model.displayedGameStatus, .draw(.threefoldRepetition))
        model.selectPosition(atPly: 4)
        XCTAssertEqual(model.displayedGameStatus, .ongoing(drawClaims: []))
        XCTAssertEqual(model.gameStatus, .draw(.threefoldRepetition))
        XCTAssertFalse(model.isGameOngoing)
        model.returnToLive()
        XCTAssertEqual(model.boardModel.game.status, .draw(.threefoldRepetition))
        XCTAssertEqual(model.boardModel.interactionMode, .readOnly)
        model.handleUserMove(move: try Move(string: "e2e4"), isLegal: true)
        XCTAssertEqual(model.liveMoveCount, 8)
    }

    func testLiveAnalysisIsHiddenOnHistoryAndRestoredWithoutRestartingSearch() throws {
        let harness = EngineAnalysisHarness()
        let model = harness.makeViewModel(initialTimeline: try Self.timeline(["e2e4", "e7e5"]))
        defer { model.cleanup() }
        model.setSuggestionArrowCount(1)
        harness.stockfish.emitInfo(score: .centipawns(45), move: "g1f3")
        XCTAssertEqual(model.boardModel.arrows.count, 1)
        let requestCount = harness.stockfish.requests.count
        let cancellationCount = harness.stockfish.cancelAnalysisCount
        model.selectPosition(atPly: 1)
        XCTAssertTrue(model.boardModel.arrows.isEmpty)
        XCTAssertEqual(model.displayedEvaluation, .unavailable)
        harness.stockfish.emitInfo(score: .centipawns(60), move: "b1c3")
        XCTAssertTrue(model.boardModel.arrows.isEmpty)
        XCTAssertEqual(model.evaluation, .centipawns(60))
        model.returnToLive()
        XCTAssertEqual(model.boardModel.arrows.first?.from, BoardSquare(row: 0, column: 1))
        XCTAssertEqual(model.displayedEvaluation, .centipawns(60))
        XCTAssertEqual(harness.stockfish.requests.count, requestCount)
        XCTAssertEqual(harness.stockfish.cancelAnalysisCount, cancellationCount)
    }

    func testSettingsDuringHistoryUseLivePositionAndPreserveDisplayPreferences() throws {
        for mode in [DemoGameMode.humanVsEngine, .engineVsEngine] {
            let harness = EngineAnalysisHarness()
            let model = harness.makeViewModel(gameMode: mode, initialTimeline: try Self.timeline(["e2e4", "e7e5"]))
            defer { model.cleanup() }
            model.pieceSet = .sashiteMerida
            model.setPieceRenderingScale(0.76)
            model.boardTheme = .artDecoMonochrome
            model.boardModel.perspective = .black
            model.setCoordinateLabelMode(.outside)
            model.selectPosition(atPly: 1)
            model.setEngineMoveTime(.halfSecond)
            if mode == .humanVsEngine {
                model.setSelectedEngineKind(.arasan)
                XCTAssertEqual(harness.arasan.requireLastRequest().fen, model.livePositionFEN)
                XCTAssertEqual(harness.arasan.requireLastRequest().sideToMove, .white)
            } else {
                XCTAssertEqual(model.engineDemoConfiguration.white.moveTime, .halfSecond)
            }
            model.returnToLive()
            XCTAssertEqual(model.boardModel.pieceSet, .sashiteMerida)
            XCTAssertEqual(model.pieceRenderingScale, 0.76)
            XCTAssertEqual(model.boardModel.boardTheme, .artDecoMonochrome)
            XCTAssertEqual(model.boardModel.perspective, .black)
            XCTAssertEqual(model.boardModel.coordinateLabelPlacement, .outside)
            XCTAssertEqual(model.liveMoveCount, 2)
        }
    }

    func testInvalidSelectionsAndMutatingDisplayedCopyCannotChangeLiveAuthority() throws {
        let harness = EngineAnalysisHarness()
        let model = harness.makeViewModel()
        defer { model.cleanup() }
        model.startIfNeeded()
        model.handleUserMove(move: try Move(string: "e2e4"), isLegal: true)
        let liveFEN = model.livePositionFEN
        model.selectPosition(atPly: -1)
        model.selectPosition(atPly: 2)
        XCTAssertEqual(model.selectedMovePly, 1)
        // ChessBoardModel exposes a mutable Game for rendering, not authority.
        model.boardModel.game = Game(position: .standard)
        XCTAssertEqual(model.livePositionFEN, liveFEN)
        harness.stockfish.emitBestMove("e7e5")
        XCTAssertEqual(model.moveRecords.map(\.san), ["e4", "e5"])
        XCTAssertEqual(model.positionFEN, model.livePositionFEN)
    }

    func testBlackToMoveRootPromotionAndHistoricalHighlightUseTimelinePly() throws {
        let root = try FENSerializer().position(from: "7k/8/8/8/8/8/p7/7K b - - 0 42")
        let timeline = try GameTimeline(initialPosition: root, moves: [Move(string: "a2a1q")])
        let harness = EngineAnalysisHarness()
        let model = harness.makeViewModel(initialTimeline: timeline)
        defer { model.cleanup() }
        XCTAssertEqual(model.moveRecords.first?.fullMoveNumber, 42)
        XCTAssertEqual(model.moveRecords.first?.side, .black)
        XCTAssertEqual(model.moveRecords.first?.san, "a1=Q+")
        model.selectPosition(atPly: 0)
        XCTAssertEqual(model.positionFEN, FENSerializer().fen(from: root))
        XCTAssertEqual(model.displayedSideToMove, .black)
        XCTAssertEqual(model.boardModel.game.moveHistory, [])
        model.returnToLive()
        XCTAssertEqual(model.selectedMovePly, 1)
        XCTAssertEqual(model.boardModel.game.moveHistory, timeline.moves)
        XCTAssertEqual(model.displayedSideToMove, .white)
    }

    func testAutomaticScenarioReplayContinuesWhileHistoricalBoardStaysPut() async throws {
        let scenario = try GameScenarioLoader.loadScenario(id: "fools-mate", bundle: .main)
        let model = GameViewModel(
            playerColor: .white, pieceSet: .artDecoMonochrome, boardTheme: .classicGreen,
            scenario: scenario, scenarioReplayDelaySeconds: 0.05
        )
        defer { model.cleanup() }
        model.startIfNeeded()
        await waitUntil { model.liveMoveCount == 1 }
        XCTAssertEqual(model.liveMoveCount, 1)
        model.selectPosition(atPly: 0)
        await waitUntil { model.liveMoveCount == 4 }
        XCTAssertEqual(model.liveMoveCount, 4)
        XCTAssertEqual(model.selectedMovePly, 0)
        XCTAssertEqual(model.displayedGameStatus, .ongoing(drawClaims: []))
        XCTAssertEqual(model.gameStatus, .checkmate(winner: .black))
        model.returnToLive()
        XCTAssertEqual(model.displayedGameStatus, .checkmate(winner: .black))
    }

    private static var fastDemo: EngineDemoConfiguration {
        EngineDemoConfiguration(
            white: EngineDemoSideConfiguration(engineKind: .stockfish, moveTime: .quarterSecond),
            black: EngineDemoSideConfiguration(engineKind: .stockfish, moveTime: .quarterSecond),
            pacing: .fast
        )
    }

    private static func timeline(_ moves: [String]) throws -> GameTimeline {
        try GameTimeline(moves: moves.map(Move.init(string:)))
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(2)
        while !predicate(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
final class EngineProviderTimeoutTests: XCTestCase {
    func testEngineSearchRequestDefaultsSafetyTimeoutFromMoveTime() {
        let request = EngineSearchRequest(
            engineKind: .stockfish,
            purpose: .evaluation,
            fen: "8/8/8/8/8/8/8/8 w - - 0 1",
            sideToMove: .white,
            moveTimeMilliseconds: EngineMoveTime.fiveSeconds.rawValue,
            multiPVCount: 1
        )

        XCTAssertEqual(request.safetyTimeoutSeconds, 8)
        XCTAssertEqual(StockfishMoveProvider.safetyTimeoutSeconds(for: request), 8)
        XCTAssertEqual(ArasanMoveProvider.safetyTimeoutSeconds(for: request), 8)
    }

    func testEngineSearchRequestClampsNonPositiveMoveTimeAndSafetyTimeouts() {
        let request = EngineSearchRequest(
            engineKind: .stockfish,
            purpose: .evaluation,
            fen: "8/8/8/8/8/8/8/8 w - - 0 1",
            sideToMove: .white,
            moveTimeMilliseconds: 0,
            multiPVCount: 1,
            safetyTimeoutSeconds: 0
        )

        XCTAssertEqual(request.moveTimeMilliseconds, 1)
        XCTAssertEqual(request.safetyTimeoutSeconds, 1)
        XCTAssertEqual(StockfishMoveProvider.safetyTimeoutSeconds(for: request), 1)
        XCTAssertEqual(ArasanMoveProvider.safetyTimeoutSeconds(for: request), 1)
    }

    func testEngineSearchRequestClampsMultiPVAndHandlesExtremeMoveTimes() {
        let low = EngineSearchRequest(
            engineKind: .stockfish,
            purpose: .evaluation,
            fen: "",
            sideToMove: .white,
            moveTimeMilliseconds: 1,
            multiPVCount: Int.min
        )
        let high = EngineSearchRequest(
            engineKind: .stockfish,
            purpose: .evaluation,
            fen: "",
            sideToMove: .white,
            moveTimeMilliseconds: Int.max,
            multiPVCount: Int.max
        )

        XCTAssertEqual(low.multiPVCount, 1)
        XCTAssertEqual(high.multiPVCount, 256)
        XCTAssertEqual(
            high.safetyTimeoutSeconds,
            (Int.max / 1_000) + 1 + EngineSearchRequest.safetyTimeoutGraceSeconds
        )
        XCTAssertEqual(EngineMoveTime.closest(milliseconds: Int.min), .quarterSecond)
        XCTAssertEqual(EngineMoveTime.closest(milliseconds: Int.max), .tenSeconds)
    }

    func testProviderSafetyTimeoutHelpersUseDefaultMoveTimeWhenNoRequestIsActive() {
        let expected = EngineSearchRequest.defaultSafetyTimeoutSeconds(for: EngineMoveTime.defaultValue.rawValue)

        XCTAssertEqual(StockfishMoveProvider.safetyTimeoutSeconds(for: nil), expected)
        XCTAssertEqual(ArasanMoveProvider.safetyTimeoutSeconds(for: nil), expected)
    }
}

@MainActor
final class EmbeddedEngineProviderSessionTests: XCTestCase {
    func testStockfishWaitsForUCIAndReadyBeforeSearching() async {
        let transport = RecordingEmbeddedEngineTransport()
        let session = makeSession(
            engineKind: .stockfish,
            startupSequence: .providerSendsUCI,
            transport: transport
        )
        defer { session.stop() }
        let request = makeRequest(engineKind: .stockfish, multiPVCount: 3)

        session.startOrQueueSearch(request)
        await waitUntil { transport.commands == ["uci"] }

        transport.emit("uciok")
        await waitUntil { transport.commands.count == 4 }
        XCTAssertEqual(transport.commands, [
            "uci",
            "setoption name MultiPV value 3",
            "ucinewgame",
            "isready",
        ])

        transport.emit("readyok")
        await waitUntil { transport.commands.count == 6 }
        XCTAssertEqual(Array(transport.commands.suffix(2)), [
            "position fen \(request.fen)",
            "go movetime 250",
        ])
    }

    func testArasanDoesNotMistakeStartupReadyForSearchReady() async {
        let transport = RecordingEmbeddedEngineTransport()
        let session = makeSession(
            engineKind: .arasan,
            startupSequence: .transportSendsUCIAndReady,
            transport: transport
        )
        defer { session.stop() }
        let request = makeRequest(engineKind: .arasan)

        session.startOrQueueSearch(request)
        await waitUntil { transport.hasLineHandler }

        transport.emit("uciok")
        await Task.yield()
        XCTAssertEqual(transport.commands, [])

        transport.emit("readyok")
        await waitUntil { transport.commands.count == 3 }
        XCTAssertEqual(transport.commands, [
            "setoption name MultiPV value 1",
            "ucinewgame",
            "isready",
        ])

        transport.emit("readyok")
        await waitUntil { transport.commands.count == 5 }
        XCTAssertEqual(Array(transport.commands.suffix(2)), [
            "position fen \(request.fen)",
            "go movetime 250",
        ])
    }

    func testReplacingAnalysisDuringReadinessRestartsPreparation() async {
        let transport = RecordingEmbeddedEngineTransport()
        let session = makeSession(
            engineKind: .stockfish,
            startupSequence: .providerSendsUCI,
            transport: transport
        )
        defer { session.stop() }
        let first = makeRequest(engineKind: .stockfish, fen: "first", multiPVCount: 3)
        let replacement = makeRequest(engineKind: .stockfish, fen: "replacement")

        session.startOrQueueSearch(first)
        await waitUntil { transport.commands == ["uci"] }
        transport.emit("uciok")
        await waitUntil { transport.commands.count == 4 }

        session.cancelAnalysisSearch(queueReplacement: replacement)
        transport.emit("readyok")
        await waitUntil { transport.commands.count == 7 }
        XCTAssertEqual(Array(transport.commands.suffix(3)), [
            "setoption name MultiPV value 1",
            "ucinewgame",
            "isready",
        ])
        XCTAssertFalse(transport.commands.contains { $0.hasPrefix("position") })

        transport.emit("readyok")
        guard await waitUntil({ transport.commands.count == 9 }) else { return }
        XCTAssertEqual(transport.commands[7], "position fen replacement")
    }

    func testStartupFailureClearsActiveRequestBeforeReportingFailure() async {
        enum StartupError: LocalizedError {
            case unavailable

            var errorDescription: String? { "Engine unavailable" }
        }

        var session: EmbeddedEngineProviderSession!
        var failureRequest: EngineSearchRequest?
        var wasIdleDuringFailure = false
        session = EmbeddedEngineProviderSession(
            engineKind: .arasan,
            startupSequence: .transportSendsUCIAndReady,
            lifecycleCoordinator: EmbeddedEngineLifecycleCoordinator(),
            transportFactory: { _ in throw StartupError.unavailable },
            eventHandler: { event in
                guard case .failure(_, let request) = event else { return }
                failureRequest = request
                wasIdleDuringFailure = session.activePurpose == nil
            }
        )

        let request = makeRequest(engineKind: .arasan)
        session.startOrQueueSearch(request)

        guard await waitUntil({ failureRequest != nil }) else { return }
        XCTAssertEqual(failureRequest, request)
        XCTAssertTrue(wasIdleDuringFailure)
        XCTAssertNil(session.activePurpose)
        XCTAssertFalse(session.isBusy)
    }

    func testHandshakeTimeoutFailsRequestAndDiscardsTransport() async {
        let transport = RecordingEmbeddedEngineTransport()
        var events: [EngineProviderEvent] = []
        let session = EmbeddedEngineProviderSession(
            engineKind: .stockfish,
            startupSequence: .providerSendsUCI,
            lifecycleCoordinator: EmbeddedEngineLifecycleCoordinator(),
            transportFactory: { handler in
                transport.install(lineHandler: handler)
                return transport
            },
            eventHandler: { events.append($0) },
            handshakeTimeout: .milliseconds(25)
        )
        defer { session.stop() }
        let request = makeRequest(engineKind: .stockfish)

        session.startOrQueueSearch(request)

        guard await waitUntil({ !events.isEmpty }) else { return }
        XCTAssertEqual(
            events,
            [.failure(message: "Timed out waiting for engine readiness.", request: request)]
        )
        XCTAssertEqual(transport.commands, ["uci"])
        XCTAssertNil(session.activePurpose)
        XCTAssertFalse(session.isBusy)
    }

    func testStopRejectsLateOutputFromDiscardedTransport() async {
        let transport = RecordingEmbeddedEngineTransport()
        let session = makeSession(
            engineKind: .stockfish,
            startupSequence: .providerSendsUCI,
            transport: transport
        )
        let request = makeRequest(engineKind: .stockfish)

        session.startOrQueueSearch(request)
        guard await waitUntil({ transport.commands == ["uci"] }) else { return }
        session.stop()
        transport.emit("uciok")
        transport.emit("readyok")
        await Task.yield()

        XCTAssertEqual(transport.commands, ["uci"])
        XCTAssertNil(session.activePurpose)
        XCTAssertFalse(session.isBusy)
    }

    func testReplacementStartWaitsForPriorCrossEngineTeardown() async {
        let coordinator = EmbeddedEngineLifecycleCoordinator()
        let priorTransport = BlockingEmbeddedEngineTransport()
        let replacementTransport = RecordingEmbeddedEngineTransport()
        coordinator.enqueueTeardown(of: priorTransport)

        let session = EmbeddedEngineProviderSession(
            engineKind: .stockfish,
            startupSequence: .providerSendsUCI,
            lifecycleCoordinator: coordinator,
            transportFactory: { handler in
                replacementTransport.install(lineHandler: handler)
                return replacementTransport
            },
            eventHandler: { _ in }
        )
        defer {
            priorTransport.allowStopToFinish()
            session.stop()
        }

        session.startOrQueueSearch(makeRequest(engineKind: .stockfish))
        guard await waitUntil({ priorTransport.stopHasStarted }) else { return }
        XCTAssertFalse(replacementTransport.hasLineHandler)

        priorTransport.allowStopToFinish()
        guard await waitUntil({ replacementTransport.hasLineHandler }) else { return }
        XCTAssertEqual(replacementTransport.commands, ["uci"])
    }

    func testSuspendableTransportIsResumedInsteadOfRecreated() async {
        let coordinator = EmbeddedEngineLifecycleCoordinator()
        let transport = RecordingSuspendableEmbeddedEngineTransport()
        var constructionCount = 0
        let session = EmbeddedEngineProviderSession(
            engineKind: .stockfish,
            startupSequence: .providerSendsUCI,
            lifecycleCoordinator: coordinator,
            transportFactory: { handler in
                constructionCount += 1
                transport.install(lineHandler: handler)
                return transport
            },
            eventHandler: { _ in }
        )
        defer { session.stop() }

        session.startOrQueueSearch(makeRequest(engineKind: .stockfish, fen: "first"))
        guard await waitUntil({ transport.commands == ["uci"] }) else { return }
        transport.emit("uciok")
        guard await waitUntil({ transport.commands.count == 4 }) else { return }
        transport.emit("readyok")
        guard await waitUntil({ transport.commands.count == 6 }) else { return }
        transport.emit("bestmove e2e4")
        guard await waitUntil({ !session.isBusy }) else { return }

        session.suspend()
        guard await waitUntil({ transport.suspendCount == 1 }) else { return }

        session.startOrQueueSearch(makeRequest(engineKind: .stockfish, fen: "second"))
        guard await waitUntil({ transport.resumeCount == 1 && transport.commands.count == 7 }) else {
            return
        }
        XCTAssertEqual(transport.commands.last, "uci")
        XCTAssertEqual(constructionCount, 1)

        transport.emit("uciok")
        guard await waitUntil({ transport.commands.count == 10 }) else { return }
        transport.emit("readyok")
        guard await waitUntil({ transport.commands.count == 12 }) else { return }
        XCTAssertEqual(Array(transport.commands.suffix(2)), [
            "position fen second",
            "go movetime 250",
        ])
    }

    func testSearchTimeoutRequestsStopAndAcceptsLateBestMove() async {
        let transport = RecordingEmbeddedEngineTransport()
        var events: [EngineProviderEvent] = []
        let session = EmbeddedEngineProviderSession(
            engineKind: .stockfish,
            startupSequence: .providerSendsUCI,
            lifecycleCoordinator: EmbeddedEngineLifecycleCoordinator(),
            transportFactory: { handler in
                transport.install(lineHandler: handler)
                return transport
            },
            eventHandler: { events.append($0) },
            bestMoveAfterStopTimeout: .seconds(1),
            searchTimeoutOverride: .milliseconds(25)
        )
        defer { session.stop() }
        let request = makeRequest(engineKind: .stockfish)

        session.startOrQueueSearch(request)
        guard await advanceStockfishToSearching(transport: transport) else { return }
        guard await waitUntil({ events.contains(.timeout(request)) }) else { return }
        XCTAssertEqual(transport.commands.last, "stop")

        transport.emit("bestmove e2e4")
        guard await waitUntil({
            events.contains {
                guard case .output(.bestMove(_), let outputRequest) = $0 else { return false }
                return outputRequest == request
            }
        }) else { return }
        XCTAssertFalse(events.contains(.timeoutWithoutBestMove(request)))
        XCTAssertNil(session.activePurpose)
    }

    func testSearchTimeoutWithoutBestMoveEscalatesAndDiscardsTransport() async {
        let transport = RecordingEmbeddedEngineTransport()
        var events: [EngineProviderEvent] = []
        let session = EmbeddedEngineProviderSession(
            engineKind: .stockfish,
            startupSequence: .providerSendsUCI,
            lifecycleCoordinator: EmbeddedEngineLifecycleCoordinator(),
            transportFactory: { handler in
                transport.install(lineHandler: handler)
                return transport
            },
            eventHandler: { events.append($0) },
            bestMoveAfterStopTimeout: .milliseconds(25),
            searchTimeoutOverride: .milliseconds(25)
        )
        defer { session.stop() }
        let request = makeRequest(engineKind: .stockfish)

        session.startOrQueueSearch(request)
        guard await advanceStockfishToSearching(transport: transport) else { return }
        guard await waitUntil({ events.contains(.timeoutWithoutBestMove(request)) }) else { return }

        XCTAssertEqual(Array(events.suffix(2)), [
            .timeout(request),
            .timeoutWithoutBestMove(request),
        ])
        XCTAssertTrue(transport.commands.contains("stop"))
        XCTAssertNil(session.activePurpose)
        XCTAssertFalse(session.isBusy)
    }

    private func makeSession(
        engineKind: DemoEngineKind,
        startupSequence: EmbeddedEngineStartupSequence,
        transport: RecordingEmbeddedEngineTransport
    ) -> EmbeddedEngineProviderSession {
        EmbeddedEngineProviderSession(
            engineKind: engineKind,
            startupSequence: startupSequence,
            lifecycleCoordinator: EmbeddedEngineLifecycleCoordinator(),
            transportFactory: { handler in
                transport.install(lineHandler: handler)
                return transport
            },
            eventHandler: { _ in }
        )
    }

    private func makeRequest(
        engineKind: DemoEngineKind,
        fen: String = "8/8/8/8/8/8/8/8 w - - 0 1",
        multiPVCount: Int = 1
    ) -> EngineSearchRequest {
        EngineSearchRequest(
            engineKind: engineKind,
            purpose: .suggestions,
            fen: fen,
            sideToMove: .white,
            moveTimeMilliseconds: 250,
            multiPVCount: multiPVCount,
            safetyTimeoutSeconds: 10
        )
    }

    private func advanceStockfishToSearching(
        transport: RecordingEmbeddedEngineTransport
    ) async -> Bool {
        guard await waitUntil({ transport.commands == ["uci"] }) else { return false }
        transport.emit("uciok")
        guard await waitUntil({ transport.commands.count == 4 }) else { return false }
        transport.emit("readyok")
        return await waitUntil { transport.commands.count == 6 }
    }

    @discardableResult
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition did not become true", file: file, line: line)
        return false
    }
}

@MainActor
private final class EngineAnalysisHarness {
    let stockfish = RecordingEngineProvider(engineKind: .stockfish)
    let arasan = RecordingEngineProvider(engineKind: .arasan)

    func makeViewModel(
        playerColor: PieceColor = .white,
        gameMode: DemoGameMode = .humanVsEngine,
        engineDemoConfiguration: EngineDemoConfiguration? = nil,
        minimumEngineThinkingSeconds: TimeInterval = 0,
        initialTimeline: GameTimeline? = nil
    ) -> GameViewModel {
        GameViewModel(
            playerColor: playerColor,
            pieceSet: .artDecoMonochrome,
            boardTheme: .classicGreen,
            gameMode: gameMode,
            engineDemoConfiguration: engineDemoConfiguration ?? .defaultConfiguration(),
            minimumEngineThinkingSeconds: minimumEngineThinkingSeconds,
            stockfishProviderFactory: { [stockfish] eventHandler in
                stockfish.eventHandler = eventHandler
                return stockfish
            },
            arasanProviderFactory: { [arasan] eventHandler in
                arasan.eventHandler = eventHandler
                return arasan
            },
            initialTimeline: initialTimeline
        )
    }

    func provider(for engineKind: DemoEngineKind) -> RecordingEngineProvider {
        switch engineKind {
        case .stockfish:
            return stockfish
        case .arasan:
            return arasan
        }
    }
}

@MainActor
private final class RecordingEngineProvider: DemoEngineProvider {
    let engineKind: DemoEngineKind
    var eventHandler: DemoEngineEventHandler?
    private(set) var requests: [EngineSearchRequest] = []
    private(set) var stopCount = 0
    private(set) var suspendCount = 0
    private(set) var cancelAnalysisCount = 0
    private var activeRequest: EngineSearchRequest?

    init(engineKind: DemoEngineKind) {
        self.engineKind = engineKind
    }

    var activePurpose: EngineSearchPurpose? {
        activeRequest?.purpose
    }

    var activeFEN: String? {
        activeRequest?.fen
    }

    var isBusy: Bool {
        activeRequest != nil
    }

    func startOrQueueSearch(_ request: EngineSearchRequest) {
        guard request.engineKind == engineKind else { return }

        requests.append(request)
        activeRequest = request
    }

    func cancelAnalysisSearch(queueReplacement: EngineSearchRequest?) {
        guard activeRequest?.purpose.isAnalysis == true else {
            if let queueReplacement {
                startOrQueueSearch(queueReplacement)
            }
            return
        }

        cancelAnalysisCount += 1
        activeRequest = nil

        if let queueReplacement {
            startOrQueueSearch(queueReplacement)
        }
    }

    func stop() {
        stopCount += 1
        activeRequest = nil
    }

    func suspend() {
        suspendCount += 1
        stop()
    }

    func emitInfo(
        score: UCIScore, move: String? = nil, multipv: Int? = nil,
        depth: Int? = nil, scoreBound: UCIScoreBound = .exact
    ) {
        guard let activeRequest else {
            XCTFail("Expected an active request for \(engineKind.displayName)")
            return
        }

        emitInfo(score: score, move: move, multipv: multipv, request: activeRequest,
                 depth: depth, scoreBound: scoreBound)
    }

    func emitInfo(
        score: UCIScore,
        move: String? = nil,
        multipv: Int? = nil,
        request: EngineSearchRequest,
        depth: Int? = nil,
        scoreBound: UCIScoreBound = .exact
    ) {
        guard request.engineKind == engineKind else {
            XCTFail("Expected \(engineKind.displayName) request, got \(request.engineKind.displayName)")
            return
        }

        let principalVariation = move.map { [try! Move(string: $0)] } ?? []
        let info = UCIInfoLine(
            rawLine: "info",
            depth: depth,
            multipv: multipv,
            score: score,
            scoreBound: scoreBound,
            principalVariation: principalVariation
        )
        eventHandler?(.output(.info(info), request: request))
    }

    func emitBestMove(_ move: String) {
        guard let activeRequest else {
            XCTFail("Expected an active request for \(engineKind.displayName)")
            return
        }

        self.activeRequest = nil
        emitBestMove(move, request: activeRequest)
    }

    func emitBestMove(_ move: String, request: EngineSearchRequest) {
        eventHandler?(
            .output(
                .bestMove(UCIBestMove(rawLine: "bestmove \(move)", move: try! Move(string: move))),
                request: request
            )
        )
    }

    func emitFailure(_ message: String) {
        guard let activeRequest else {
            XCTFail("Expected an active request for \(engineKind.displayName)")
            return
        }

        self.activeRequest = nil
        eventHandler?(.failure(message: message, request: activeRequest))
    }

    func requireLastRequest(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> EngineSearchRequest {
        guard let request = requests.last else {
            XCTFail("Expected a recorded request for \(engineKind.displayName)", file: file, line: line)
            return EngineSearchRequest(
                engineKind: engineKind,
                purpose: .evaluation,
                fen: "",
                sideToMove: .white,
                moveTimeMilliseconds: EngineMoveTime.defaultValue.rawValue,
                multiPVCount: 1
            )
        }

        return request
    }
}

@MainActor
private final class RecordingEmbeddedEngineTransport: EmbeddedEngineTransport, @unchecked Sendable {
    private(set) var commands: [String] = []
    private var lineHandler: (@Sendable (String) -> Void)?

    var hasLineHandler: Bool {
        lineHandler != nil
    }

    func install(lineHandler: @escaping @Sendable (String) -> Void) {
        self.lineHandler = lineHandler
    }

    nonisolated func sendCommand(_ command: String) {
        MainActor.assumeIsolated {
            commands.append(command)
        }
    }

    nonisolated func stop() {}

    func emit(_ line: String) {
        lineHandler?(line)
    }
}

nonisolated private final class BlockingEmbeddedEngineTransport: EmbeddedEngineTransport, @unchecked Sendable {
    private let condition = NSCondition()
    private var hasStarted = false
    private var mayFinish = false

    var stopHasStarted: Bool {
        condition.lock()
        defer { condition.unlock() }
        return hasStarted
    }

    nonisolated func sendCommand(_ command: String) {}

    nonisolated func stop() {
        condition.lock()
        hasStarted = true
        condition.broadcast()
        while !mayFinish {
            condition.wait()
        }
        condition.unlock()
    }

    func allowStopToFinish() {
        condition.lock()
        mayFinish = true
        condition.broadcast()
        condition.unlock()
    }
}

nonisolated private final class RecordingSuspendableEmbeddedEngineTransport: EmbeddedEngineSuspendableTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCommands: [String] = []
    private var storedSuspendCount = 0
    private var storedResumeCount = 0
    private var storedStopCount = 0
    private var lineHandler: (@Sendable (String) -> Void)?

    var commands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedCommands
    }

    var suspendCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedSuspendCount
    }

    var resumeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedResumeCount
    }

    func install(lineHandler: @escaping @Sendable (String) -> Void) {
        lock.lock()
        self.lineHandler = lineHandler
        lock.unlock()
    }

    nonisolated func sendCommand(_ command: String) {
        lock.lock()
        storedCommands.append(command)
        lock.unlock()
    }

    nonisolated func suspend() {
        lock.lock()
        storedSuspendCount += 1
        lock.unlock()
    }

    nonisolated func resume() {
        lock.lock()
        storedResumeCount += 1
        lock.unlock()
    }

    nonisolated func stop() {
        lock.lock()
        storedStopCount += 1
        lock.unlock()
    }

    func emit(_ line: String) {
        lock.lock()
        let handler = lineHandler
        lock.unlock()
        handler?(line)
    }
}

private func assertResultAlert(
    _ alert: GameViewModel.GameAlert?,
    title: String,
    message: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .result(let result) = alert else {
        XCTFail("Expected result alert, got \(String(describing: alert))", file: file, line: line)
        return
    }

    XCTAssertEqual(result.title, title, file: file, line: line)
    XCTAssertEqual(result.message, message, file: file, line: line)
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
