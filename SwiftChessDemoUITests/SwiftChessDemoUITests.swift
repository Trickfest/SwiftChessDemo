//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and StockfishEmbedded.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the MIT License.
// You may obtain a copy of the License in the LICENSE file
// See the LICENSE file for more information.
//

import ChessUI
import XCTest

final class SwiftChessDemoUITests: XCTestCase {
    private enum FENTurn {
        case white
        case black

        var token: String {
            switch self {
            case .white:
                return " w "
            case .black:
                return " b "
            }
        }
    }

    private struct UITestFailure: Error, CustomStringConvertible {
        let description: String
    }

    private var pieceSetNames: [String] {
        ChessPieceSet.availableSets.map(\.displayName)
    }

    private var boardThemeNames: [String] {
        ChessBoardTheme.availableThemes.map(\.displayName)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testWhiteGameFlowCompletesFourFullMoves() throws {
        let app = moveSmokeTestApplication(id: "white-four-move-smoke")
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        var position = try boardValue(in: app)
        for index in 0..<4 {
            try tapNextScenarioMove(in: app, named: "White scenario move \(index + 1)")

            let afterWhiteMove = try waitForBoardTurn(
                .black,
                from: position,
                in: app,
                named: "White move \(index + 1)"
            )
            position = try waitForBoardTurn(
                .white,
                from: afterWhiteMove,
                in: app,
                named: "Black reply \(index + 1)"
            )
        }

        attachScreenshot(from: app, named: "SwiftChessDemo - White four full moves")
    }

    func testBlackGameFlowCompletesFourFullMoves() throws {
        let app = moveSmokeTestApplication(id: "black-four-move-smoke")
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        let openingPosition = try boardValue(in: app)
        let afterWhiteEngineMove = try waitForBoardTurnOrUseCurrent(
            .black,
            currentValue: openingPosition,
            in: app,
            named: "opening White engine move"
        )

        var position = afterWhiteEngineMove
        for index in 0..<4 {
            try tapNextScenarioMove(in: app, named: "Black scenario move \(index + 1)")

            position = try waitForBoardTurn(
                .white,
                from: position,
                in: app,
                named: "Black move \(index + 1)"
            )

            if index < 3 {
                position = try waitForBoardTurn(
                    .black,
                    from: position,
                    in: app,
                    named: "White reply \(index + 2)"
                )
            }
        }

        attachScreenshot(from: app, named: "SwiftChessDemo - Black four full moves")
    }

    func testGamePieceSetPickerSelectsEveryBuiltInSetAndUpdatesBoard() throws {
        let app = XCUIApplication()
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        let picker = try requireElement(
            app.descendants(matching: .any)["Game.pieceSetPicker"],
            named: "game piece set picker"
        )
        let board = try requireElement(
            app.descendants(matching: .any)["Game.boardState"].firstMatch,
            named: "game board state"
        )

        XCTAssertEqual(picker.value as? String, "Art Deco Monochrome")
        XCTAssertTrue((board.value as? String)?.contains("Pieces: Art Deco Monochrome") == true)

        for pieceSetName in pieceSetNames {
            try select(pieceSetName, from: picker, in: app)
            XCTAssertEqual(picker.value as? String, pieceSetName)
            XCTAssertTrue((board.value as? String)?.contains("Pieces: \(pieceSetName)") == true)
            attachScreenshot(from: app, named: "SwiftChessDemo - \(pieceSetName)")
        }
    }

    func testGameBoardThemePickerSelectsEveryBuiltInThemeAndUpdatesBoard() throws {
        let app = XCUIApplication()
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        let picker = try requireElement(
            app.descendants(matching: .any)["Game.boardThemePicker"],
            named: "game board theme picker"
        )
        let board = try requireElement(
            app.descendants(matching: .any)["Game.boardState"].firstMatch,
            named: "game board state"
        )

        XCTAssertEqual(picker.value as? String, "Art Deco Monochrome")
        XCTAssertTrue((board.value as? String)?.contains("Board: Art Deco Monochrome") == true)

        for boardThemeName in boardThemeNames {
            try select(boardThemeName, from: picker, in: app)
            XCTAssertEqual(picker.value as? String, boardThemeName)
            XCTAssertTrue((board.value as? String)?.contains("Board: \(boardThemeName)") == true)
            attachScreenshot(from: app, named: "SwiftChessDemo Board - \(boardThemeName)")
        }
    }

    func testGameCoordinateLabelsToggleUpdatesBoardState() throws {
        let app = XCUIApplication()
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        let toggle = try requireElement(
            app.descendants(matching: .any)["Game.coordinateLabelsToggle"].firstMatch,
            named: "coordinate labels toggle"
        )
        let boardValue = try boardValue(in: app)
        XCTAssertTrue(boardValue.contains("Coordinates: Shown"))

        toggle.tap()

        let hiddenValue = try waitForBoardValue(
            containing: "Coordinates: Hidden",
            in: app,
            named: "coordinate labels hidden"
        )
        XCTAssertTrue(hiddenValue.contains("Coordinates: Hidden"))
    }

    func testGameReferenceComponentsRenderAndMoveListUpdates() throws {
        let app = moveSmokeTestApplication(id: "white-four-move-smoke")
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        try requireElement(
            app.descendants(matching: .any)["ChessUI.gameStatus"].firstMatch,
            named: "game status display"
        )
        try requireElement(
            app.staticTexts["White to move"].firstMatch,
            named: "initial game status"
        )

        let initialPosition = try boardValue(in: app)
        try tapMove("e2e4", in: app)
        let afterWhiteMove = try waitForBoardTurn(
            .black,
            from: initialPosition,
            in: app,
            named: "White opening move"
        )

        let whiteMove = try requireElement(
            app.descendants(matching: .any)["ChessUI.moveList.move.1"].firstMatch,
            named: "White move-list record"
        )
        XCTAssertEqual(whiteMove.value as? String, "e2e4")
        XCTAssertTrue(whiteMove.label.contains("White e4"))

        _ = try waitForBoardTurn(
            .white,
            from: afterWhiteMove,
            in: app,
            named: "Black scenario reply"
        )

        let blackMove = try requireElement(
            app.descendants(matching: .any)["ChessUI.moveList.move.2"].firstMatch,
            named: "Black move-list record"
        )
        XCTAssertEqual(blackMove.value as? String, "e7e5")
        XCTAssertTrue(blackMove.label.contains("Black e5"))
    }

    func testGameDisplayOptionsToggleStatusAndMoveList() throws {
        let app = XCUIApplication()
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        let statusToggle = try requireElement(
            app.descendants(matching: .any)["Game.statusToggle"].firstMatch,
            named: "status toggle"
        )

        XCTAssertTrue(app.descendants(matching: .any)["ChessUI.gameStatus"].firstMatch.exists)
        try waitForElementValue(statusToggle, expectedValue: "Shown", named: "status toggle")
        statusToggle.tap()
        try waitForElementValue(statusToggle, expectedValue: "Hidden", named: "status toggle")

        statusToggle.tap()
        try waitForElementValue(statusToggle, expectedValue: "Shown", named: "status toggle")
        try requireElement(
            app.descendants(matching: .any)["ChessUI.gameStatus"].firstMatch,
            named: "restored game status display"
        )

        let moveListToggle = try scrollUntilHittable(
            app.descendants(matching: .any)["Game.moveListToggle"].firstMatch,
            named: "move-list toggle",
            in: app
        )
        try requireElement(
            app.descendants(matching: .any)["ChessUI.moveList"].firstMatch,
            named: "game move list"
        )

        try waitForElementValue(moveListToggle, expectedValue: "Shown", named: "move-list toggle")
        moveListToggle.tap()
        try waitForElementValue(moveListToggle, expectedValue: "Hidden", named: "move-list toggle")

        moveListToggle.tap()
        try waitForElementValue(moveListToggle, expectedValue: "Shown", named: "move-list toggle")
        try requireElement(
            app.descendants(matching: .any)["ChessUI.moveList"].firstMatch,
            named: "restored game move list"
        )
    }

    func testGameEngineDepthStepperUpdatesGameDepth() throws {
        let app = moveSmokeTestApplication(id: "white-four-move-smoke")
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()
        try waitForGameBoardState(containing: "Depth: 1", in: app, named: "initial engine depth")

        let incrementButton = try scrollUntilHittable(
            app.buttons["Game.engineDepthStepper-Increment"].firstMatch,
            named: "engine depth increment button",
            in: app
        )
        incrementButton.tap()
        try waitForGameBoardState(containing: "Depth: 2", in: app, named: "incremented engine depth")

        let decrementButton = try requireElement(
            app.buttons["Game.engineDepthStepper-Decrement"].firstMatch,
            named: "engine depth decrement button"
        )
        decrementButton.tap()
        try waitForGameBoardState(containing: "Depth: 1", in: app, named: "decremented engine depth")
    }

    func testGameEvaluationBarRendersAndToggles() throws {
        let app = XCUIApplication()
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_EVALUATION"] = "cp:85"
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        let evaluationBar = try requireElement(
            app.descendants(matching: .any)["ChessUI.evaluationBar"].firstMatch,
            named: "evaluation bar"
        )
        XCTAssertEqual(evaluationBar.value as? String, "White advantage 0.9 pawns")

        let board = try requireElement(
            app.descendants(matching: .any)["Game.boardState"].firstMatch,
            named: "game board state"
        )
        assertEvaluationBarMatchesBoard(evaluationBar, board: board)

        let evaluationToggle = try scrollUntilHittable(
            app.descendants(matching: .any)["Game.evaluationToggle"].firstMatch,
            named: "evaluation toggle",
            in: app
        )
        try waitForElementValue(evaluationToggle, expectedValue: "Shown", named: "evaluation toggle")

        evaluationToggle.tap()
        try waitForElementValue(evaluationToggle, expectedValue: "Hidden", named: "evaluation toggle")
        XCTAssertFalse(app.descendants(matching: .any)["ChessUI.evaluationBar"].firstMatch.exists)

        evaluationToggle.tap()
        try waitForElementValue(evaluationToggle, expectedValue: "Shown", named: "evaluation toggle")
        try requireElement(
            app.descendants(matching: .any)["ChessUI.evaluationBar"].firstMatch,
            named: "restored evaluation bar"
        )
    }

    func testGameEvaluationBarKeepsLatestEngineScoreAfterReply() throws {
        let app = moveSmokeTestApplication(id: "white-four-move-smoke")
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_EVALUATION_BEFORE_REPLY"] = "cp:-220"
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        let evaluationBar = try requireElement(
            app.descendants(matching: .any)["ChessUI.evaluationBar"].firstMatch,
            named: "evaluation bar"
        )
        XCTAssertEqual(evaluationBar.value as? String, "Evaluation unavailable")

        let initialPosition = try boardValue(in: app)
        try tapMove("e2e4", in: app)
        let afterWhiteMove = try waitForBoardTurn(
            .black,
            from: initialPosition,
            in: app,
            named: "White opening move"
        )

        _ = try waitForBoardTurn(
            .white,
            from: afterWhiteMove,
            in: app,
            named: "Black scenario reply"
        )
        try waitForElementValue(
            evaluationBar,
            expectedValue: "Black advantage 2.2 pawns",
            named: "evaluation after scenario reply",
            timeout: 5
        )
    }

    func testGameSuggestionArrowPickerControlsRenderedArrows() throws {
        let app = moveSmokeTestApplication(id: "suggestion-line")
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        let picker = try scrollUntilHittable(
            app.descendants(matching: .any)["Game.suggestionCountPicker"].firstMatch,
            named: "suggestion count picker",
            in: app
        )
        try waitForElementValue(picker, expectedValue: "Off", named: "suggestion count picker")

        try select("3 arrows", from: picker, in: app)
        try waitForElementValue(picker, expectedValue: "3 arrows", named: "suggestion count picker")

        let bestArrow = try requireElement(
            app.descendants(matching: .any)["ChessUI.arrow.e2.e4"].firstMatch,
            named: "best suggestion arrow"
        )
        XCTAssertTrue(bestArrow.label.contains("Best suggestion"))
        try requireElement(
            app.descendants(matching: .any)["ChessUI.arrow.g1.f3"].firstMatch,
            named: "second suggestion arrow"
        )
        try requireElement(
            app.descendants(matching: .any)["ChessUI.arrow.d2.d4"].firstMatch,
            named: "third suggestion arrow"
        )

        try select("1 arrow", from: picker, in: app)
        try waitForElementValue(picker, expectedValue: "1 arrow", named: "suggestion count picker")
        try requireElement(
            app.descendants(matching: .any)["ChessUI.arrow.e2.e4"].firstMatch,
            named: "remaining best suggestion arrow"
        )
        try waitForElementToDisappear(
            app.descendants(matching: .any)["ChessUI.arrow.g1.f3"].firstMatch,
            named: "second suggestion arrow"
        )
        try waitForElementToDisappear(
            app.descendants(matching: .any)["ChessUI.arrow.d2.d4"].firstMatch,
            named: "third suggestion arrow"
        )

        try select("3 arrows", from: picker, in: app)
        try waitForElementValue(picker, expectedValue: "3 arrows", named: "suggestion count picker")
        let restoredBestArrow = try requireElement(
            app.descendants(matching: .any)["ChessUI.arrow.e2.e4"].firstMatch,
            named: "restored best suggestion arrow"
        )
        XCTAssertTrue(restoredBestArrow.label.contains("Best suggestion"))
        try requireElement(
            app.descendants(matching: .any)["ChessUI.arrow.g1.f3"].firstMatch,
            named: "restored second suggestion arrow"
        )
        try requireElement(
            app.descendants(matching: .any)["ChessUI.arrow.d2.d4"].firstMatch,
            named: "restored third suggestion arrow"
        )

        try select("Off", from: picker, in: app)
        try waitForElementValue(picker, expectedValue: "Off", named: "suggestion count picker")
        try waitForElementToDisappear(
            app.descendants(matching: .any)["ChessUI.arrow.e2.e4"].firstMatch,
            named: "best suggestion arrow"
        )
    }

    func testGameSuggestionArrowsRefreshAfterOpponentReply() throws {
        let app = moveSmokeTestApplication(id: "suggestion-line")
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_SUGGESTION_ARROW_COUNT"] = "2"
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        try requireElement(
            app.descendants(matching: .any)["ChessUI.arrow.e2.e4"].firstMatch,
            named: "initial best suggestion arrow"
        )
        try requireElement(
            app.descendants(matching: .any)["ChessUI.arrow.g1.f3"].firstMatch,
            named: "initial second suggestion arrow"
        )

        let initialPosition = try boardValue(in: app)
        try tapMove("e2e4", in: app)
        let afterWhiteMove = try waitForBoardTurn(
            .black,
            from: initialPosition,
            in: app,
            named: "White opening move"
        )

        try waitForElementToDisappear(
            app.descendants(matching: .any)["ChessUI.arrow.e2.e4"].firstMatch,
            named: "stale opening suggestion arrow"
        )

        _ = try waitForBoardTurn(
            .white,
            from: afterWhiteMove,
            in: app,
            named: "Black scenario reply"
        )

        try requireElement(
            app.descendants(matching: .any)["ChessUI.arrow.g1.f3"].firstMatch,
            named: "refreshed best suggestion arrow"
        )
        try requireElement(
            app.descendants(matching: .any)["ChessUI.arrow.f1.c4"].firstMatch,
            named: "refreshed second suggestion arrow"
        )
    }

    func testGameScenarioReplayRunsLongOpeningLine() throws {
        let app = scenarioTestApplication(id: "ruy-lopez-long")
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        try waitForGameBoardState(
            containing: "Scenario ply: 20/20",
            in: app,
            named: "long replay completion",
            timeout: 15
        )
        try waitForGameBoardState(
            containing: "Scenario status: Ongoing",
            in: app,
            named: "long replay ongoing status"
        )
        let finalMove = try requireElement(
            app.descendants(matching: .any)["ChessUI.moveList.move.20"].firstMatch,
            named: "long replay final move"
        )
        XCTAssertTrue(finalMove.label.contains("Black Nbd7"))
    }

    func testGameScenarioReplayHandlesPromotion() throws {
        let app = scenarioTestApplication(id: "promotion-to-queen")
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        try waitForGameBoardState(
            containing: "Scenario ply: 1/1",
            in: app,
            named: "promotion replay completion"
        )
        let promotionMove = try requireElement(
            app.descendants(matching: .any)["ChessUI.moveList.move.1"].firstMatch,
            named: "promotion move"
        )
        XCTAssertEqual(promotionMove.value as? String, "a7a8q")
        XCTAssertTrue(promotionMove.label.contains("a8=Q"))
    }

    func testGameScenarioReplayStartsFromInsufficientMaterial() throws {
        let app = scenarioTestApplication(id: "insufficient-material-position")
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        try waitForGameBoardState(
            containing: "Scenario status: Draw, Draw by insufficient material",
            in: app,
            named: "insufficient material status"
        )

        let alert = try requireElement(
            app.alerts["Draw by insufficient material"].firstMatch,
            named: "insufficient material alert"
        )
        XCTAssertTrue(alert.staticTexts["Draw"].exists)
    }

    func testGameScenarioReplayHandlesCastlingAndEnPassant() throws {
        let app = scenarioTestApplication(id: "special-moves")
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        try waitForGameBoardState(
            containing: "Scenario ply: 11/11",
            in: app,
            named: "special moves replay completion",
            timeout: 10
        )

        let castlingMove = try requireElement(
            app.descendants(matching: .any)["ChessUI.moveList.move.7"].firstMatch,
            named: "castling move"
        )
        XCTAssertTrue(castlingMove.label.contains("O-O"))

        let enPassantMove = try requireElement(
            app.descendants(matching: .any)["ChessUI.moveList.move.11"].firstMatch,
            named: "en passant move"
        )
        XCTAssertTrue(enPassantMove.label.contains("exd6"))
    }

    func testGameScenarioReplayRunsPGNToCheckmate() throws {
        let app = scenarioTestApplication(id: "fools-mate")
        app.launch()

        try requireElement(
            app.staticTexts["Setup.scenarioTitle"].firstMatch,
            named: "scenario setup title"
        )
        XCTAssertEqual(app.staticTexts["Setup.scenarioTitle"].firstMatch.label, "Fool's Mate")

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        try waitForGameBoardState(
            containing: "Scenario: fools-mate",
            in: app,
            named: "fool's mate scenario marker"
        )
        try waitForGameBoardState(
            containing: "Scenario ply: 4/4",
            in: app,
            named: "fool's mate replay completion",
            timeout: 10
        )
        try waitForGameBoardState(
            containing: "Scenario status: Checkmate, Black wins",
            in: app,
            named: "fool's mate checkmate status"
        )

        let finalMove = try requireElement(
            app.descendants(matching: .any)["ChessUI.moveList.move.4"].firstMatch,
            named: "fool's mate final move"
        )
        XCTAssertEqual(finalMove.value as? String, "d8h4")
        XCTAssertTrue(finalMove.label.contains("Black Qh4#"))

        let alert = try requireElement(app.alerts["Checkmate"].firstMatch, named: "checkmate alert")
        XCTAssertTrue(alert.staticTexts["Black wins"].exists)
    }

    func testGameScenarioReplayStartsFromTerminalStalemate() throws {
        let app = scenarioTestApplication(id: "stalemate-position")
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        try waitForGameBoardState(
            containing: "Scenario: stalemate-position",
            in: app,
            named: "stalemate scenario marker"
        )
        try waitForGameBoardState(
            containing: "Scenario ply: 0/0",
            in: app,
            named: "stalemate scenario ply"
        )
        try waitForGameBoardState(
            containing: "Scenario status: Draw, Stalemate",
            in: app,
            named: "stalemate scenario status"
        )

        let alert = try requireElement(app.alerts["Stalemate"].firstMatch, named: "stalemate alert")
        XCTAssertTrue(alert.staticTexts["Draw"].exists)
    }

    func testMissingGameScenarioReportsSetupError() throws {
        let app = scenarioTestApplication(id: "missing-scenario")
        app.launch()

        try requireElement(
            app.staticTexts["Setup.scenarioError"].firstMatch,
            named: "scenario load error"
        )
        let detail = try requireElement(
            app.staticTexts["Setup.scenarioErrorDetail"].firstMatch,
            named: "scenario load error detail"
        )
        XCTAssertTrue(detail.label.contains("missing-scenario.json"))
        XCTAssertFalse(app.buttons["Start Game"].isEnabled)
    }

    func testScenarioIndexMatchesBundledScenarioResources() throws {
        let expectedScenarioIDs = [
            "black-four-move-smoke",
            "fools-mate",
            "insufficient-material-position",
            "promotion-to-queen",
            "ruy-lopez-long",
            "special-moves",
            "stalemate-position",
            "suggestion-line",
            "white-four-move-smoke",
        ]

        let app = XCUIApplication()
        app.launchEnvironment["SWIFT_CHESS_DEMO_VALIDATE_SCENARIO_INDEX"] = "1"
        app.launch()

        let status = try requireElement(
            app.staticTexts["Setup.scenarioIndexStatus"].firstMatch,
            named: "scenario index status"
        )
        XCTAssertEqual(status.label, "Scenario index valid")

        let detail = try requireElement(
            app.staticTexts["Setup.scenarioIndexDetail"].firstMatch,
            named: "scenario index detail"
        )
        XCTAssertTrue(detail.label.contains("Validated \(expectedScenarioIDs.count) scenarios"))
        for scenarioID in expectedScenarioIDs {
            XCTAssertTrue(detail.label.contains(scenarioID), "Missing indexed scenario id \(scenarioID)")
        }
    }

    @discardableResult
    private func scrollUntilHittable(
        _ element: XCUIElement,
        named name: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let deadline = Date().addingTimeInterval(5)
        let scrollView = app.scrollViews["Game.scrollView"].firstMatch

        repeat {
            if element.exists, element.isHittable {
                return element
            }

            if scrollView.exists {
                let start = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
                let end = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28))
                start.press(forDuration: 0.01, thenDragTo: end)
            } else {
                app.swipeUp()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline

        XCTAssertTrue(element.exists, "Missing \(name)", file: file, line: line)
        XCTAssertTrue(element.isHittable, "\(name) is not hittable", file: file, line: line)
        return element
    }

    private func waitForElementValue(
        _ element: XCUIElement,
        expectedValue: String,
        named name: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastValue = ""

        repeat {
            lastValue = element.value as? String ?? ""
            if lastValue == expectedValue {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTAssertEqual(lastValue, expectedValue, "\(name) value", file: file, line: line)
    }

    private func waitForElementToDisappear(
        _ element: XCUIElement,
        named name: String,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            if !element.exists {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTAssertFalse(element.exists, "\(name) should not exist", file: file, line: line)
    }

    private func assertEvaluationBarMatchesBoard(
        _ evaluationBar: XCUIElement,
        board: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if evaluationBar.frame.height > evaluationBar.frame.width {
            XCTAssertEqual(evaluationBar.frame.height, board.frame.height, accuracy: 2, file: file, line: line)
        } else {
            XCTAssertEqual(evaluationBar.frame.width, board.frame.width, accuracy: 2, file: file, line: line)
        }
    }

    private func moveSmokeTestApplication(id: String) -> XCUIApplication {
        let app = scenarioTestApplication(id: id)
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_DEPTH"] = "1"
        return app
    }

    private func scenarioTestApplication(id: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SWIFT_CHESS_DEMO_SCENARIO"] = id
        app.launchEnvironment["SWIFT_CHESS_DEMO_SCENARIO_REPLAY_DELAY"] = "0"
        return app
    }

    private func tapMove(
        _ move: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try requireElement(
            app.buttons["UITest.move.\(move)"].firstMatch,
            named: "\(move) UI test move button",
            file: file,
            line: line
        )
        .tap()
    }

    private func tapNextScenarioMove(
        in app: XCUIApplication,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let nextMoveButton = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "UITest.move."))
            .firstMatch
        try requireElement(nextMoveButton, named: name, file: file, line: line).tap()
    }

    private func waitForBoardTurn(
        _ turn: FENTurn,
        from boardValue: String,
        in app: XCUIApplication,
        named changeName: String,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var lastValue = ""

        repeat {
            let currentValue = try self.boardValue(in: app, file: file, line: line)
            lastValue = currentValue
            if currentValue != boardValue,
               currentValue.contains(turn.token) {
                return currentValue
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let message = "Board value did not change to \(turn.token.trimmingCharacters(in: .whitespaces)) after \(changeName). Last value: \(lastValue)"
        XCTFail(message, file: file, line: line)
        throw UITestFailure(description: message)
    }

    private func waitForBoardTurnOrUseCurrent(
        _ turn: FENTurn,
        currentValue: String,
        in app: XCUIApplication,
        named changeName: String,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        if currentValue.contains(turn.token) {
            return currentValue
        }

        return try waitForBoardTurn(
            turn,
            from: currentValue,
            in: app,
            named: changeName,
            timeout: timeout,
            file: file,
            line: line
        )
    }

    private func waitForBoardValue(
        containing expectedValue: String,
        in app: XCUIApplication,
        named changeName: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var lastValue = ""

        repeat {
            lastValue = try boardValue(in: app, file: file, line: line)
            if lastValue.contains(expectedValue) {
                return lastValue
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let message = "Board value did not contain \(expectedValue) after \(changeName). Last value: \(lastValue)"
        XCTFail(message, file: file, line: line)
        throw UITestFailure(description: message)
    }

    private func waitForGameBoardState(
        containing expectedValue: String,
        in app: XCUIApplication,
        named changeName: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastValue = ""

        repeat {
            lastValue = try gameBoardStateValue(in: app, file: file, line: line)
            if lastValue.contains(expectedValue) {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let message = "Game board state did not contain \(expectedValue) after \(changeName). Last value: \(lastValue)"
        XCTFail(message, file: file, line: line)
        throw UITestFailure(description: message)
    }

    private func boardValue(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let board = app.descendants(matching: .any)["Game.boardState"].firstMatch
        if board.exists {
            return board.value as? String ?? ""
        }

        let uiTestFEN = try requireElement(
            app.staticTexts["UITest.positionFEN"].firstMatch,
            named: "UI test position FEN",
            file: file,
            line: line
        )

        return uiTestFEN.label
    }

    private func gameBoardStateValue(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let board = try requireElement(
            app.descendants(matching: .any)["Game.boardState"].firstMatch,
            named: "game board state",
            file: file,
            line: line
        )

        return board.value as? String ?? ""
    }

    private func select(
        _ optionName: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let option = waitForOption(named: optionName, in: app)
        XCTAssertTrue(
            option.exists,
            "Missing option \(optionName)",
            file: file,
            line: line
        )
        option.tap()
    }

    private func select(
        _ optionName: String,
        from control: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        control.tap()

        let option = waitForOption(named: optionName, in: app)
        XCTAssertTrue(
            option.exists,
            "Missing option \(optionName)",
            file: file,
            line: line
        )
        option.tap()
    }

    private func waitForOption(named name: String, in app: XCUIApplication) -> XCUIElement {
        let deadline = Date().addingTimeInterval(3)

        repeat {
            let candidates = [
                app.buttons[name].firstMatch,
                app.cells[name].firstMatch,
                app.staticTexts[name].firstMatch,
                app.descendants(matching: .any)[name].firstMatch,
            ]

            if let candidate = candidates.first(where: \.exists) {
                return candidate
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return app.buttons[name].firstMatch
    }

    @discardableResult
    private func requireElement(
        _ element: XCUIElement,
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        XCTAssertTrue(
            element.waitForExistence(timeout: 5),
            "Missing \(name)",
            file: file,
            line: line
        )
        return element
    }

    private func attachScreenshot(from app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
