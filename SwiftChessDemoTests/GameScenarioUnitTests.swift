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
            guard case .output(.info(let info), let request) = event,
                  let score = info.whiteRelativeScore(sideToMove: request.sideToMove)
            else {
                return
            }

            if case .centipawns(let centipawns) = score {
                observedScores.append(centipawns)

                if centipawns >= 800, !didFulfillExpectedScore {
                    didFulfillExpectedScore = true
                    expectedScore.fulfill()
                }
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

        await fulfillment(of: [expectedScore], timeout: 10)
        XCTAssertTrue(
            observedScores.contains { $0 >= 800 },
            "Expected a queen-sized Arasan evaluation, got \(observedScores)",
            file: file,
            line: line
        )
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

        XCTAssertEqual(harness.arasan.requireLastRequest().sideToMove, .black)
        XCTAssertEqual(harness.arasan.requireLastRequest().moveTimeMilliseconds, EngineMoveTime.fiveSeconds.rawValue)
        XCTAssertEqual(
            harness.arasan.requireLastRequest().safetyTimeoutSeconds,
            EngineSearchRequest.defaultSafetyTimeoutSeconds(for: EngineMoveTime.fiveSeconds.rawValue)
        )

        harness.arasan.emitBestMove("e7e5")

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
        let viewModel = harness.makeViewModel(gameMode: .engineVsEngine)
        viewModel.boardModel.game = try Self.claimableThreefoldGame()

        viewModel.startIfNeeded()

        XCTAssertEqual(viewModel.boardModel.game.status, .draw(.threefoldRepetition))
        XCTAssertEqual(viewModel.engineDemoRunState, .paused)
        XCTAssertTrue(harness.stockfish.requests.isEmpty)
        assertResultAlert(viewModel.activeAlert, title: "Draw by repetition", message: "Draw")
    }

    func testEngineDemoAutoClaimsFiftyMoveRuleOnStart() throws {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(gameMode: .engineVsEngine)
        viewModel.boardModel.game = try Self.game(from: "4k3/8/8/8/8/8/Q7/4K3 w - - 100 1")

        viewModel.startIfNeeded()

        XCTAssertEqual(viewModel.boardModel.game.status, .draw(.fiftyMoveRule))
        XCTAssertEqual(viewModel.engineDemoRunState, .paused)
        XCTAssertTrue(harness.stockfish.requests.isEmpty)
        assertResultAlert(viewModel.activeAlert, title: "Draw by 50-move rule", message: "Draw")
    }

    func testEngineDemoPrefersThreefoldWhenMultipleDrawClaimsAreAvailable() throws {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(gameMode: .engineVsEngine)
        viewModel.boardModel.game = try Self.claimableThreefoldGame(halfmoveClock: 92)

        viewModel.startIfNeeded()

        XCTAssertEqual(viewModel.boardModel.game.status, .draw(.threefoldRepetition))
        assertResultAlert(viewModel.activeAlert, title: "Draw by repetition", message: "Draw")
    }

    func testHumanVsEngineDoesNotAutoClaimThreefoldRepetition() throws {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(gameMode: .humanVsEngine)
        let game = try Self.claimableThreefoldGame()
        viewModel.boardModel.game = game

        viewModel.startIfNeeded()

        XCTAssertEqual(viewModel.boardModel.game.status, .ongoing(drawClaims: [.threefoldRepetition]))
        XCTAssertNil(viewModel.activeAlert)
    }

    func testHumanVsEngineDoesNotAutoClaimFiftyMoveRule() throws {
        let harness = EngineAnalysisHarness()
        let viewModel = harness.makeViewModel(gameMode: .humanVsEngine)
        viewModel.boardModel.game = try Self.game(from: "4k3/8/8/8/8/8/Q7/4K3 w - - 100 1")

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

    private static func claimableThreefoldGame(halfmoveClock: Int = 0) throws -> Game {
        let game = try game(from: "8/8/8/8/8/6k1/8/R3K3 w - - \(halfmoveClock) 1")
        try applyQuietKingCycle(to: game)
        try applyQuietKingCycle(to: game)
        XCTAssertTrue(game.drawClaims.contains(.threefoldRepetition))
        return game
    }

    private static func game(from fen: String) throws -> Game {
        Game(position: try FENSerializer().position(from: fen))
    }

    private static func applyQuietKingCycle(to game: Game) throws {
        try applyLegalCoordinates(["e1d1", "g3f3", "d1e1", "f3g3"], to: game)
    }

    private static func applyLegalCoordinates(_ coordinates: [String], to game: Game) throws {
        for coordinate in coordinates {
            try game.applyLegal(move: Move(string: coordinate))
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

    func testProviderSafetyTimeoutHelpersUseDefaultMoveTimeWhenNoRequestIsActive() {
        let expected = EngineSearchRequest.defaultSafetyTimeoutSeconds(for: EngineMoveTime.defaultValue.rawValue)

        XCTAssertEqual(StockfishMoveProvider.safetyTimeoutSeconds(for: nil), expected)
        XCTAssertEqual(ArasanMoveProvider.safetyTimeoutSeconds(for: nil), expected)
    }
}

@MainActor
private final class EngineAnalysisHarness {
    let stockfish = RecordingEngineProvider(engineKind: .stockfish)
    let arasan = RecordingEngineProvider(engineKind: .arasan)

    func makeViewModel(
        gameMode: DemoGameMode = .humanVsEngine,
        engineDemoConfiguration: EngineDemoConfiguration = .defaultConfiguration(),
        minimumEngineThinkingSeconds: TimeInterval = 0
    ) -> GameViewModel {
        GameViewModel(
            playerColor: .white,
            pieceSet: .artDecoMonochrome,
            boardTheme: .classicGreen,
            gameMode: gameMode,
            engineDemoConfiguration: engineDemoConfiguration,
            minimumEngineThinkingSeconds: minimumEngineThinkingSeconds,
            stockfishProviderFactory: { [stockfish] eventHandler in
                stockfish.eventHandler = eventHandler
                return stockfish
            },
            arasanProviderFactory: { [arasan] eventHandler in
                arasan.eventHandler = eventHandler
                return arasan
            }
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

    func emitInfo(score: UCIScore, move: String? = nil, multipv: Int? = nil) {
        guard let activeRequest else {
            XCTFail("Expected an active request for \(engineKind.displayName)")
            return
        }

        emitInfo(score: score, move: move, multipv: multipv, request: activeRequest)
    }

    func emitInfo(
        score: UCIScore,
        move: String? = nil,
        multipv: Int? = nil,
        request: EngineSearchRequest
    ) {
        guard request.engineKind == engineKind else {
            XCTFail("Expected \(engineKind.displayName) request, got \(request.engineKind.displayName)")
            return
        }

        let principalVariation = move.map { [try! Move(string: $0)] } ?? []
        let info = UCIInfoLine(
            rawLine: "info",
            multipv: multipv,
            score: score,
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
        eventHandler?(
            .output(
                .bestMove(UCIBestMove(rawLine: "bestmove \(move)", move: try! Move(string: move))),
                request: activeRequest
            )
        )
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
