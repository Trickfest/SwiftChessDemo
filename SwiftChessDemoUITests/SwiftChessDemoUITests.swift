//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and embedded engines.
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

    func testChessBoardSquareActionsReachGameViewModel() throws {
        let app = moveSmokeTestApplication(id: "white-four-move-smoke")
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()
        let openingPosition = try boardValue(in: app)

        let source = try requireElement(
            app.descendants(matching: .any)["ChessUI.square.e2"].firstMatch,
            named: "e2 board square"
        )
        let destination = try requireElement(
            app.descendants(matching: .any)["ChessUI.square.e4"].firstMatch,
            named: "e4 board square"
        )

        source.tap()
        destination.tap()

        let afterUserMove = try waitForBoardTurn(
            .black,
            from: openingPosition,
            in: app,
            named: "board square e2-e4"
        )
        let whiteMove = try requireElement(
            app.descendants(matching: .any)["ChessUI.moveList.move.1"].firstMatch,
            named: "board square move-list record"
        )
        XCTAssertEqual(whiteMove.value as? String, "e2e4")
        XCTAssertTrue(whiteMove.label.contains("White e4"))
        _ = try waitForBoardTurn(
            .white,
            from: afterUserMove,
            in: app,
            named: "scenario reply to board square move"
        )
    }

    func testProductionAccessibilityTreeOmitsBoardDiagnosticMarker() throws {
        let app = XCUIApplication()
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        XCTAssertFalse(app.descendants(matching: .any)["Game.boardState"].firstMatch.exists)
        try requireElement(
            app.descendants(matching: .any)["ChessUI.square.e2"].firstMatch,
            named: "production e2 board square"
        )
    }

    func testBackFromOngoingLiveGameRequiresResignConfirmation() throws {
        let app = testApplication()
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()
        try requireElement(app.buttons["Back"].firstMatch, named: "live game back button").tap()

        let alert = try requireElement(
            app.alerts["Are you sure you want to resign?"].firstMatch,
            named: "resign confirmation"
        )
        try requireElement(alert.buttons["Cancel"].firstMatch, named: "resign cancel button").tap()
        try requireElement(app.buttons["Back"].firstMatch, named: "game back button after cancellation")
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
        let app = testApplication()
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

        XCTAssertEqual(picker.value as? String, "Sashite Merida")
        XCTAssertTrue((board.value as? String)?.contains("Pieces: Sashite Merida") == true)

        for pieceSetName in pieceSetNames {
            try select(pieceSetName, from: picker, in: app)
            XCTAssertEqual(picker.value as? String, pieceSetName)
            XCTAssertTrue((board.value as? String)?.contains("Pieces: \(pieceSetName)") == true)
            attachScreenshot(from: app, named: "SwiftChessDemo - \(pieceSetName)")
        }
    }

    func testGameBoardThemePickerSelectsEveryBuiltInThemeAndUpdatesBoard() throws {
        let app = testApplication()
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

        XCTAssertEqual(picker.value as? String, "Classic Green")
        XCTAssertTrue((board.value as? String)?.contains("Board: Classic Green") == true)

        for boardThemeName in boardThemeNames {
            try select(boardThemeName, from: picker, in: app)
            XCTAssertEqual(picker.value as? String, boardThemeName)
            XCTAssertTrue((board.value as? String)?.contains("Board: \(boardThemeName)") == true)
            attachScreenshot(from: app, named: "SwiftChessDemo Board - \(boardThemeName)")
        }
    }

    func testGameEnginePickerSelectsLiveEngineAndUpdatesBoardState() throws {
        let app = testApplication()
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_MOVE_TIME_MS"] = "250"
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        let evaluationBar = try requireElement(
            app.descendants(matching: .any)["ChessUI.evaluationBar"].firstMatch,
            named: "evaluation bar"
        )
        try waitForEvaluationValueIsAvailable(evaluationBar, named: "initial engine evaluation")
        try waitForGameBoardState(
            containing: "Evaluation engine: Stockfish",
            in: app,
            named: "initial Stockfish output"
        )

        let picker = try scrollUntilHittable(
            app.descendants(matching: .any)["Game.enginePicker"].firstMatch,
            named: "game engine picker",
            in: app
        )

        XCTAssertEqual(picker.value as? String, "Stockfish")
        try waitForGameBoardState(containing: "Engine: Stockfish", in: app, named: "initial engine")

        try select("Arasan", from: picker, in: app)

        try waitForElementValue(picker, expectedValue: "Arasan", named: "game engine picker")
        try waitForGameBoardState(containing: "Engine: Arasan", in: app, named: "selected engine")
        try waitForGameBoardState(
            containing: "Evaluation engine: Arasan",
            in: app,
            named: "Arasan engine output",
            timeout: 15
        )

        try select("Stockfish", from: picker, in: app)

        try waitForElementValue(picker, expectedValue: "Stockfish", named: "game engine picker")
        try waitForGameBoardState(containing: "Engine: Stockfish", in: app, named: "restored engine")
        try waitForGameBoardState(
            containing: "Evaluation engine: Stockfish",
            in: app,
            named: "restored Stockfish output",
            timeout: 15
        )
    }

    func testEngineDemoModeStartsPausedAndShowsPlaybackControls() throws {
        let app = testApplication()
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_MOVE_TIME_MS"] = "250"
        app.launch()

        try requireElement(app.buttons["Engine vs Engine"].firstMatch, named: "engine demo mode").tap()
        XCTAssertFalse(app.descendants(matching: .any)["Setup.sidePicker"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["Setup.engineDemoWhiteEnginePicker"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["Setup.engineDemoBlackEnginePicker"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["Setup.engineDemoWhiteMoveTimePicker"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["Setup.engineDemoBlackMoveTimePicker"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["Setup.engineDemoPacingPicker"].firstMatch.exists)
        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        try waitForGameBoardState(containing: "Mode: Engine vs Engine", in: app, named: "engine demo mode")
        try waitForGameBoardState(containing: "Demo state: Play", in: app, named: "engine demo paused state")
        try waitForGameBoardState(containing: "White move time: 250ms", in: app, named: "engine demo white default move time")
        try waitForGameBoardState(containing: "Black move time: 250ms", in: app, named: "engine demo black default move time")

        try requireElement(
            app.descendants(matching: .any)["Game.engineDemoPlayPauseButton"].firstMatch,
            named: "engine demo play button"
        )
        try requireElement(
            app.descendants(matching: .any)["Game.engineDemoStepButton"].firstMatch,
            named: "engine demo step button"
        )
        XCTAssertFalse(app.buttons["Game.resignButton"].exists)
        try requireElement(
            app.descendants(matching: .any)["Game.engineDemoPacingPicker"].firstMatch,
            named: "engine demo pacing picker"
        )
        let whiteMoveTimePicker = try requireElement(
            app.descendants(matching: .any)["Game.engineDemoWhiteMoveTimePicker"].firstMatch,
            named: "engine demo white move-time picker"
        )
        XCTAssertEqual(whiteMoveTimePicker.value as? String, "250ms")
        try select("1s", from: whiteMoveTimePicker, in: app)
        try waitForElementValue(whiteMoveTimePicker, expectedValue: "1s", named: "engine demo white move-time picker")
        try waitForGameBoardState(containing: "White move time: 1s", in: app, named: "engine demo updated move time")
        XCTAssertFalse(app.descendants(matching: .any)["Game.enginePicker"].firstMatch.exists)
    }

    func testStockfishVersusArasanAt250MillisecondsWithFastPacing() throws {
        let app = testApplication()
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_MOVE_TIME_MS"] = "250"
        app.launch()

        try requireElement(app.buttons["Engine vs Engine"].firstMatch, named: "engine demo mode").tap()
        try requireElement(app.buttons["Start Game"], named: "start game button").tap()
        try waitForGameBoardState(containing: "White engine: Stockfish", in: app, named: "White engine")
        try waitForGameBoardState(containing: "Black engine: Arasan", in: app, named: "Black engine")
        try waitForGameBoardState(containing: "White move time: 250ms", in: app, named: "White think time")
        try waitForGameBoardState(containing: "Black move time: 250ms", in: app, named: "Black think time")

        let pacingPicker = try requireElement(
            app.descendants(matching: .any)["Game.engineDemoPacingPicker"].firstMatch,
            named: "engine demo pacing picker"
        )
        try select("Fast", from: pacingPicker, in: app)
        try waitForGameBoardState(containing: "Pacing: Fast", in: app, named: "Fast pacing")
        let playbackButton = try requireElement(
            app.descendants(matching: .any)["Game.engineDemoPlayPauseButton"].firstMatch,
            named: "engine demo play button"
        )
        playbackButton.tap()

        // Fast playback may advance multiple plies between UI snapshots. Check
        // the recorded moves rather than requiring every intermediate board.
        let sixthMove = app.descendants(matching: .any)["ChessUI.moveList.move.6"].firstMatch
        XCTAssertTrue(sixthMove.waitForExistence(timeout: 30), "Both engines should complete six live plies")
        playbackButton.tap()
        try waitForGameBoardState(containing: "Demo state: Play", in: app, named: "paused after live moves")
        for ply in 1...6 {
            let move = try requireElement(
                app.descendants(matching: .any)["ChessUI.moveList.move.\(ply)"].firstMatch,
                named: "live move \(ply)"
            )
            XCTAssertTrue(move.label.contains(ply.isMultiple(of: 2) ? "Black" : "White"))
        }
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot(from: app, named: "Stockfish versus Arasan - 250ms Fast")
    }

    func testArasanVersusArasanEngineDemoCompletesSixLivePlies() throws {
        let app = testApplication()
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_MOVE_TIME_MS"] = "250"
        app.launch()

        try requireElement(app.buttons["Engine vs Engine"].firstMatch, named: "engine demo mode").tap()
        try requireElement(app.buttons["Start Game"], named: "start game button").tap()
        try waitForGameBoardState(containing: "Mode: Engine vs Engine", in: app, named: "engine demo mode")

        let whiteEnginePicker = try requireElement(
            app.descendants(matching: .any)["Game.engineDemoWhiteEnginePicker"].firstMatch,
            named: "White engine picker"
        )
        let blackEnginePicker = try requireElement(
            app.descendants(matching: .any)["Game.engineDemoBlackEnginePicker"].firstMatch,
            named: "Black engine picker"
        )

        XCTAssertEqual(whiteEnginePicker.value as? String, "Stockfish")
        XCTAssertEqual(blackEnginePicker.value as? String, "Arasan")
        try select("Arasan", from: whiteEnginePicker, in: app)
        try waitForElementValue(whiteEnginePicker, expectedValue: "Arasan", named: "White engine picker")
        try waitForGameBoardState(containing: "White engine: Arasan", in: app, named: "White Arasan selection")
        try waitForGameBoardState(containing: "Black engine: Arasan", in: app, named: "Black Arasan selection")

        var position = try boardValue(in: app)
        try requireElement(
            app.descendants(matching: .any)["Game.engineDemoPlayPauseButton"].firstMatch,
            named: "engine demo play button"
        )
        .tap()
        try waitForGameBoardState(containing: "Demo state: Pause", in: app, named: "engine demo playback")

        let expectedPlies: [(mover: String, resultingTurn: FENTurn)] = [
            ("White", .black),
            ("Black", .white),
            ("White", .black),
            ("Black", .white),
            ("White", .black),
            ("Black", .white),
        ]

        for (index, expectedPly) in expectedPlies.enumerated() {
            position = try waitForBoardTurn(
                expectedPly.resultingTurn,
                from: position,
                in: app,
                named: "live Arasan \(expectedPly.mover) ply \(index + 1)"
            )

            let moveRecord = try requireElement(
                app.descendants(matching: .any)["ChessUI.moveList.move.\(index + 1)"].firstMatch,
                named: "live Arasan move-list record \(index + 1)"
            )
            XCTAssertTrue(
                moveRecord.label.contains(expectedPly.mover),
                "Expected ply \(index + 1) to belong to \(expectedPly.mover); label was \(moveRecord.label)"
            )
            XCTAssertEqual(
                app.state,
                .runningForeground,
                "SwiftChessDemo stopped running after live Arasan ply \(index + 1)"
            )
        }

        attachScreenshot(from: app, named: "SwiftChessDemo - Arasan versus Arasan six live plies")
    }

    func testPieceSizeSliderRemembersEachSetInBothGameModes() throws {
        for engineDemo in [false, true] {
            let app = testApplication()
            app.launch()
            if engineDemo {
                try requireElement(app.buttons["Engine vs Engine"].firstMatch, named: "engine demo mode").tap()
            }
            try requireElement(app.buttons["Start Game"], named: "start game button").tap()
            try waitForGameBoardState(containing: "Piece size: 80%", in: app, named: "default Merida size")
            let slider = app.sliders["Game.pieceSizeSlider"]
            try scrollUntilHittable(slider, named: "piece size slider", in: app)
            slider.adjust(toNormalizedSliderPosition: 0)
            try waitForGameBoardState(containing: "Piece size: 50%", in: app, named: "smaller Merida pieces")

            let picker = app.descendants(matching: .any)["Game.pieceSetPicker"].firstMatch
            try scrollUntilHittable(picker, named: "piece set picker", in: app)
            try select("Art Deco Monochrome", from: picker, in: app)
            try waitForGameBoardState(containing: "Piece size: 85%", in: app, named: "independent Art Deco default")
            try select("Sashite Merida", from: picker, in: app)
            try waitForGameBoardState(containing: "Piece size: 50%", in: app, named: "remembered Merida override")
            let reset = app.buttons["Game.resetPieceSize"]
            try scrollUntilHittable(reset, named: "reset piece size", in: app).tap()
            try waitForGameBoardState(containing: "Piece size: 80%", in: app, named: "restored Merida default")
            XCTAssertFalse(reset.isEnabled)
            app.terminate()
        }
    }

    func testGameCoordinateLabelPickerUpdatesBoardState() throws {
        let app = testApplication()
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        let picker = try scrollUntilHittable(
            app.descendants(matching: .any)["Game.coordinateLabelModePicker"].firstMatch,
            named: "coordinate-label mode picker",
            in: app
        )
        try waitForElementValue(picker, expectedValue: "Inside", named: "initial coordinate-label mode")
        try waitForGameBoardState(containing: "Coordinates: Inside", in: app, named: "inside coordinates")

        try select("Outside", from: picker, in: app)
        try waitForElementValue(picker, expectedValue: "Outside", named: "outside coordinate-label mode")
        try waitForGameBoardState(containing: "Coordinates: Outside", in: app, named: "outside coordinates")

        try select("None", from: picker, in: app)
        try waitForElementValue(picker, expectedValue: "None", named: "hidden coordinate-label mode")
        try waitForGameBoardState(containing: "Coordinates: None", in: app, named: "hidden coordinates")

        try select("Inside", from: picker, in: app)
        try waitForElementValue(picker, expectedValue: "Inside", named: "restored coordinate-label mode")
        try waitForGameBoardState(containing: "Coordinates: Inside", in: app, named: "restored inside coordinates")
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
        let app = testApplication()
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

    func testGameEngineMoveTimePickerUpdatesGameMoveTime() throws {
        let app = moveSmokeTestApplication(id: "white-four-move-smoke")
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()
        try waitForGameBoardState(containing: "Move time: 250ms", in: app, named: "initial engine move time")

        let moveTimePicker = try scrollUntilHittable(
            app.descendants(matching: .any)["Game.engineMoveTimePicker"].firstMatch,
            named: "engine move-time picker",
            in: app
        )
        try select("500ms", from: moveTimePicker, in: app)
        try waitForGameBoardState(containing: "Move time: 500ms", in: app, named: "updated engine move time")

        try select("250ms", from: moveTimePicker, in: app)
        try waitForGameBoardState(containing: "Move time: 250ms", in: app, named: "restored engine move time")
    }

    func testGameEvaluationBarRendersAndToggles() throws {
        let app = testApplication()
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_EVALUATION"] = "cp:85"
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        let evaluationBar = try requireElement(
            app.descendants(matching: .any)["ChessUI.evaluationBar"].firstMatch,
            named: "evaluation bar"
        )
        assertEvaluationValueIsAvailable(evaluationBar)

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

        try waitForGameBoardState(
            containing: "Suggestion arrows: Best suggestion e2 to e4 | Second suggestion g1 to f3 | Third suggestion d2 to d4",
            in: app,
            named: "three rendered suggestion arrows"
        )

        try select("1 arrow", from: picker, in: app)
        try waitForElementValue(picker, expectedValue: "1 arrow", named: "suggestion count picker")
        try waitForGameBoardState(
            containing: "Suggestion arrows: Best suggestion e2 to e4,",
            in: app,
            named: "one rendered suggestion arrow"
        )
        XCTAssertFalse(try boardValue(in: app).contains("Second suggestion"))
        XCTAssertFalse(try boardValue(in: app).contains("Third suggestion"))

        try select("3 arrows", from: picker, in: app)
        try waitForElementValue(picker, expectedValue: "3 arrows", named: "suggestion count picker")
        try waitForGameBoardState(
            containing: "Suggestion arrows: Best suggestion e2 to e4 | Second suggestion g1 to f3 | Third suggestion d2 to d4",
            in: app,
            named: "restored rendered suggestion arrows"
        )

        try select("Off", from: picker, in: app)
        try waitForElementValue(picker, expectedValue: "Off", named: "suggestion count picker")
        try waitForGameBoardState(
            containing: "Suggestion arrows: None",
            in: app,
            named: "cleared suggestion arrows"
        )
    }

    func testGameSuggestionArrowsRefreshAfterOpponentReply() throws {
        let app = moveSmokeTestApplication(id: "suggestion-line")
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_SUGGESTION_ARROW_COUNT"] = "2"
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        try waitForGameBoardState(
            containing: "Suggestion arrows: Best suggestion e2 to e4 | Second suggestion g1 to f3",
            in: app,
            named: "initial rendered suggestion arrows"
        )

        let initialPosition = try boardValue(in: app)
        try tapMove("e2e4", in: app)
        let afterWhiteMove = try waitForBoardTurn(
            .black,
            from: initialPosition,
            in: app,
            named: "White opening move"
        )

        XCTAssertFalse(afterWhiteMove.contains("Best suggestion e2 to e4"))

        _ = try waitForBoardTurn(
            .white,
            from: afterWhiteMove,
            in: app,
            named: "Black scenario reply"
        )

        try waitForGameBoardState(
            containing: "Suggestion arrows: Best suggestion g1 to f3 | Second suggestion f1 to c4",
            in: app,
            named: "refreshed rendered suggestion arrows"
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

    func testHumanHistoryStaysReadOnlyWhenPendingReplyArrivesAndReturnsToLive() throws {
        let app = moveSmokeTestApplication(id: "suggestion-line")
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_REPLY_DELAY"] = "8"
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_EVALUATION_BEFORE_REPLY"] = "cp:85"
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_SUGGESTION_ARROW_COUNT"] = "2"
        app.launch()
        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        let initialFEN = try displayedFEN(in: app)
        XCTAssertFalse(app.buttons["ChessUI.moveNavigation.previous"].isEnabled)
        XCTAssertFalse(app.buttons["ChessUI.moveNavigation.end"].isEnabled)
        try tapMove("e2e4", in: app)
        try waitForHistory(selected: 1, live: 1, browsing: false, in: app)
        try revealHistoryElement(app.buttons["ChessUI.moveNavigation.start"], in: app).tap()
        try waitForHistory(selected: 0, live: 1, browsing: true, in: app)
        try requireElement(app.descendants(matching: .any)["Game.historyBanner"].firstMatch, named: "read-only history banner")
        let historicalEvaluation = try requireElement(
            app.descendants(matching: .any)["ChessUI.evaluationBar"].firstMatch,
            named: "starting position recorded evaluation"
        )
        XCTAssertEqual(historicalEvaluation.value as? String, "Evaluation unavailable")
        XCTAssertEqual(app.staticTexts["Game.recordedEvaluation"].label, "Not evaluated")

        // The delayed scenario reply must extend LIVE history, not move the board.
        try waitForHistory(selected: 0, live: 2, browsing: true, in: app, timeout: 15)
        XCTAssertEqual(try displayedFEN(in: app), initialFEN)
        try waitForGameBoardState(containing: "Suggestion arrows: None", in: app, named: "history arrows hidden")
        XCTAssertFalse(app.buttons["UITest.move.g1f3"].exists)

        let historicalSquares = try revealReadOnlySquares(["e2", "e4"], in: app)
        attachScreenshot(from: app, named: "History - visible read-only squares before move attempt")
        for square in historicalSquares {
            square.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertEqual(try displayedFEN(in: app), initialFEN)
        try waitForHistory(selected: 0, live: 2, browsing: true, in: app)

        try revealHistoryElement(app.buttons["Game.returnToLive"], in: app).tap()
        try waitForHistory(selected: 2, live: 2, browsing: false, in: app)
        XCTAssertFalse(app.descendants(matching: .any)["Game.historyBanner"].firstMatch.exists)
        try requireElement(app.descendants(matching: .any)["ChessUI.evaluationBar"].firstMatch, named: "restored live evaluation")
        try waitForGameBoardState(
            containing: "Suggestion arrows: Best suggestion g1 to f3",
            in: app, named: "restored live suggestions"
        )
        try revealHistoryElement(app.buttons["UITest.move.g1f3"], in: app).tap()
        try waitForHistory(selected: 3, live: 3, browsing: false, in: app)
        attachScreenshot(from: app, named: "History - human return to live")
    }

    func testHistoryDirectSelectionScrollsAndPreservesDisplayPreferences() throws {
        let app = scenarioTestApplication(id: "ruy-lopez-long")
        app.launch()
        try requireElement(app.buttons["Start Game"], named: "start game button").tap()
        try waitForHistory(selected: 20, live: 20, browsing: false, in: app, timeout: 15)

        try revealHistoryElement(app.buttons["ChessUI.moveNavigation.start"], in: app).tap()
        try waitForHistory(selected: 0, live: 20, browsing: true, in: app)
        XCTAssertFalse(app.buttons["ChessUI.moveNavigation.previous"].isEnabled)
        try revealHistoryElement(app.buttons["ChessUI.moveNavigation.next"], in: app).tap()
        try waitForHistory(selected: 1, live: 20, browsing: true, in: app)
        let firstMove = app.descendants(matching: .any)["ChessUI.moveList.move.1"].firstMatch
        try revealHistoryElement(firstMove, in: app)
        XCTAssertTrue(firstMove.isSelected)
        XCTAssertTrue(firstMove.isHittable)

        let secondMove = app.descendants(matching: .any)["ChessUI.moveList.move.2"].firstMatch
        try revealHistoryElement(secondMove, in: app).tap()
        try waitForHistory(selected: 2, live: 20, browsing: true, in: app)
        XCTAssertTrue(secondMove.isSelected)
        let historicalFEN = try displayedFEN(in: app)

        let coordinatePicker = app.descendants(matching: .any)["Game.coordinateLabelModePicker"].firstMatch
        try revealHistoryElement(coordinatePicker, in: app)
        try select("Outside", from: coordinatePicker, in: app)
        let slider = app.sliders["Game.pieceSizeSlider"]
        try revealHistoryElement(slider, in: app)
        slider.adjust(toNormalizedSliderPosition: 0)
        try waitForGameBoardState(containing: "Piece size: 50%", in: app, named: "historical piece size preference")
        try waitForGameBoardState(containing: "Coordinates: Outside", in: app, named: "historical coordinate preference")
        XCTAssertEqual(try displayedFEN(in: app), historicalFEN)

        // Scenario replay has no engine scores; keep the bar explicitly unavailable.
        let evaluationToggle = app.descendants(matching: .any)["Game.evaluationToggle"].firstMatch
        try revealHistoryElement(evaluationToggle, in: app)
        XCTAssertEqual(evaluationToggle.value as? String, "Shown")
        let historicalEvaluation = try requireElement(
            app.descendants(matching: .any)["ChessUI.evaluationBar"].firstMatch,
            named: "unscored scenario history evaluation"
        )
        XCTAssertEqual(historicalEvaluation.value as? String, "Evaluation unavailable")
        XCTAssertEqual(app.staticTexts["Game.recordedEvaluation"].label, "Not evaluated")

        try revealHistoryElement(app.buttons["ChessUI.moveNavigation.end"], in: app).tap()
        try waitForHistory(selected: 20, live: 20, browsing: false, in: app)
        let lastMove = app.descendants(matching: .any)["ChessUI.moveList.move.20"].firstMatch
        try revealHistoryElement(lastMove, in: app)
        XCTAssertTrue(lastMove.isSelected)
        XCTAssertTrue(lastMove.isHittable)
        XCTAssertFalse(app.buttons["ChessUI.moveNavigation.next"].isEnabled)
        try waitForGameBoardState(containing: "Coordinates: Outside", in: app, named: "coordinates retained after return")
        try waitForGameBoardState(containing: "Piece size: 50%", in: app, named: "piece size retained after return")
        try requireElement(app.descendants(matching: .any)["ChessUI.evaluationBar"].firstMatch, named: "live evaluation restored")
        attachScreenshot(from: app, named: "History - selected long line and preferences")
    }

    func testEngineDemoHistoryKeepsLivePlaybackIndependentAndNewGameClearsHistory() throws {
        let app = testApplication()
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_MOVE_TIME_MS"] = "250"
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_REPLY_DELAY"] = "0"
        app.launch()
        try requireElement(app.buttons["Engine vs Engine"].firstMatch, named: "engine demo mode").tap()
        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        // Exercise real wrappers but assert legal history growth, not engine-specific moves.
        let step = app.buttons["Game.engineDemoStepButton"]
        for ply in 1...2 {
            try revealHistoryElement(step, in: app).tap()
            try waitForHistory(selected: ply, live: ply, browsing: false, in: app, timeout: 20)
            try waitForGameBoardState(containing: "Demo state: Play,", in: app, named: "paused after step")
        }
        try revealHistoryElement(app.buttons["ChessUI.moveNavigation.previous"], in: app).tap()
        try waitForHistory(selected: 1, live: 2, browsing: true, in: app)
        let historicalFEN = try displayedFEN(in: app)
        try revealHistoryElement(step, in: app).tap()
        try waitForHistory(selected: 1, live: 3, browsing: true, in: app, timeout: 20)
        XCTAssertEqual(try displayedFEN(in: app), historicalFEN)
        try waitForGameBoardState(containing: "Demo state: Play,", in: app, named: "paused history after step")

        let playback = app.buttons["Game.engineDemoPlayPauseButton"]
        try revealHistoryElement(playback, in: app).tap()
        try waitForLivePly(atLeast: 4, in: app)
        try revealHistoryElement(playback, in: app).tap()
        try waitForGameBoardState(containing: "Demo state: Play,", in: app, named: "explicit pause while browsing", timeout: 20)
        let pausedPly = try livePly(in: app)
        try waitForHistory(selected: 1, live: pausedPly, browsing: true, in: app)
        XCTAssertEqual(try displayedFEN(in: app), historicalFEN)
        let recordedEvaluation = try requireElement(
            app.descendants(matching: .any)["ChessUI.evaluationBar"].firstMatch,
            named: "recorded engine demo evaluation"
        )
        try waitForEvaluationValueIsAvailable(recordedEvaluation, named: "recorded engine demo score")
        XCTAssertTrue(app.staticTexts["Game.recordedEvaluation"].label.hasPrefix("Recorded evaluation · "))

        try revealHistoryElement(app.buttons["Game.returnToLive"], in: app).tap()
        try waitForHistory(selected: pausedPly, live: pausedPly, browsing: false, in: app)
        try waitForGameBoardState(containing: "Demo state: Play,", in: app, named: "return does not resume playback")
        attachScreenshot(from: app, named: "History - engine demo paused at live")

        try requireElement(app.buttons["Back"].firstMatch, named: "engine demo back").tap()
        try requireElement(app.buttons["Start Game"], named: "new engine demo").tap()
        try waitForHistory(selected: 0, live: 0, browsing: false, in: app)
        XCTAssertFalse(app.buttons["ChessUI.moveNavigation.start"].isEnabled)
        XCTAssertFalse(app.buttons["ChessUI.moveNavigation.end"].isEnabled)
    }

    func testCompletedGameHistorySeparatesDisplayedPositionFromLiveResult() throws {
        let app = scenarioTestApplication(id: "fools-mate")
        app.launch()
        try requireElement(app.buttons["Start Game"], named: "start game button").tap()
        let result = try requireElement(app.alerts["Checkmate"].firstMatch, named: "completed live game")
        result.buttons["OK"].tap()
        try waitForHistory(selected: 4, live: 4, browsing: false, in: app)
        try revealHistoryElement(app.buttons["ChessUI.moveNavigation.start"], in: app).tap()
        try waitForHistory(selected: 0, live: 4, browsing: true, in: app)
        let historicalStatus = try requireElement(
            app.descendants(matching: .any)["Game.historicalStatus"].firstMatch,
            named: "displayed starting position status"
        )
        XCTAssertEqual(historicalStatus.value as? String, "White to move")
        let liveStatus = try requireElement(
            app.descendants(matching: .any)["Game.liveStatus"].firstMatch,
            named: "separate live result"
        )
        XCTAssertEqual(liveStatus.value as? String, "Black wins by checkmate")
        XCTAssertFalse(app.buttons["Game.resignButton"].exists)
        try revealHistoryElement(app.buttons["Game.returnToLive"], in: app).tap()
        try waitForHistory(selected: 4, live: 4, browsing: false, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["ChessUI.moveList.move.4"].firstMatch.isSelected)
        attachScreenshot(from: app, named: "History - completed game return to live")
    }

    func testRecordedHistoryEvaluationShowsMatchingScoreUnavailableStateAndToggle() throws {
        let app = moveSmokeTestApplication(id: "suggestion-line")
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_REPLY_DELAY"] = "0"
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_EVALUATION_BEFORE_REPLY"] = "cp:85"
        app.launch()
        try requireElement(app.buttons["Start Game"], named: "start game button").tap()
        try tapMove("e2e4", in: app)
        try waitForHistory(selected: 2, live: 2, browsing: false, in: app)

        try revealHistoryElement(app.buttons["ChessUI.moveNavigation.previous"], in: app).tap()
        try waitForHistory(selected: 1, live: 2, browsing: true, in: app)
        let evaluation = try requireElement(
            app.descendants(matching: .any)["ChessUI.evaluationBar"].firstMatch,
            named: "recorded position score"
        )
        XCTAssertEqual(evaluation.value as? String, "White advantage 0.9 pawns")
        XCTAssertEqual(evaluation.label, "Recorded evaluation")
        XCTAssertEqual(app.staticTexts["Game.recordedEvaluation"].label, "Recorded evaluation · Stockfish")
        attachScreenshot(from: app, named: "History - recorded evaluation matches selected position")

        try revealHistoryElement(app.buttons["ChessUI.moveNavigation.start"], in: app).tap()
        try waitForHistory(selected: 0, live: 2, browsing: true, in: app)
        XCTAssertEqual(evaluation.value as? String, "Evaluation unavailable")
        XCTAssertEqual(app.staticTexts["Game.recordedEvaluation"].label, "Not evaluated")
        let toggle = app.buttons["Game.evaluationToggle"]
        try revealHistoryElement(toggle, in: app).tap()
        XCTAssertFalse(evaluation.exists)
        XCTAssertFalse(app.staticTexts["Game.recordedEvaluation"].exists)
        try revealHistoryElement(toggle, in: app).tap()
        try revealHistoryElement(app.buttons["ChessUI.moveNavigation.next"], in: app).tap()
        try waitForHistory(selected: 1, live: 2, browsing: true, in: app)
        XCTAssertEqual(evaluation.value as? String, "White advantage 0.9 pawns")

        try revealHistoryElement(app.buttons["Game.returnToLive"], in: app).tap()
        try waitForHistory(selected: 2, live: 2, browsing: false, in: app)
        XCTAssertEqual(evaluation.label, "Evaluation")
        XCTAssertEqual(evaluation.value as? String, "White advantage 0.9 pawns")
        XCTAssertFalse(app.staticTexts["Game.recordedEvaluation"].exists)
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
        try requireElement(alert.buttons["OK"].firstMatch, named: "checkmate OK button").tap()

        try waitForGameBoardState(
            containing: "Scenario status: Checkmate, Black wins",
            in: app,
            named: "fool's mate final board after alert dismissal"
        )
        let visibleFinalMove = try requireElement(
            app.descendants(matching: .any)["ChessUI.moveList.move.4"].firstMatch,
            named: "fool's mate final move after alert dismissal"
        )
        XCTAssertEqual(visibleFinalMove.value as? String, "d8h4")
        XCTAssertFalse(app.buttons["Start Game"].waitForExistence(timeout: 1))

        try requireElement(app.buttons["Back"].firstMatch, named: "terminal back button").tap()
        XCTAssertFalse(app.alerts["Are you sure you want to resign?"].waitForExistence(timeout: 1))
        try requireElement(app.buttons["Start Game"].firstMatch, named: "start game button after terminal back")
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

        let app = testApplication()
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

    /// Inactive board squares remain accessible spatial items but need not be
    /// reported as hittable. Verify their actual visible geometry before testing
    /// physical taps; neither missing nor off-screen squares satisfy this check.
    private func revealReadOnlySquares(
        _ coordinates: [String],
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [XCUIElement] {
        let squares = coordinates.map {
            app.descendants(matching: .any)["ChessUI.square.\($0)"].firstMatch
        }
        let scroll = app.scrollViews["Game.scrollView"].firstMatch
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(8)
        repeat {
            var viewport = scroll.frame.intersection(window.frame)
            let navigationBar = app.navigationBars.firstMatch
            if navigationBar.exists, navigationBar.frame.intersects(viewport) {
                let visibleTop = max(viewport.minY, navigationBar.frame.maxY)
                viewport = CGRect(x: viewport.minX, y: visibleTop,
                                  width: viewport.width, height: max(0, viewport.maxY - visibleTop))
            }
            if squares.allSatisfy(\.exists) {
                let frames = squares.map(\.frame)
                if !viewport.isEmpty, !viewport.isNull,
                   frames.allSatisfy({ !$0.isEmpty && !$0.isNull && viewport.contains($0) }) {
                    return squares
                }
            }
            let visibleFrames = squares.filter(\.exists).map(\.frame).filter { !$0.isEmpty && !$0.isNull }
            let towardTop = visibleFrames.contains { $0.minY < viewport.minY }
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: towardTop ? 0.25 : 0.82))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: towardTop ? 0.82 : 0.25))
            start.press(forDuration: 0.01, thenDragTo: end)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline

        attachScreenshot(from: app, named: "History - square visibility failure")
        let message = "Read-only squares \(coordinates.joined(separator: ", ")) are not fully inside the visible game viewport"
        XCTFail(message, file: file, line: line)
        throw UITestFailure(description: message)
    }

    /// History controls and preferences are on opposite sides of the compact
    /// board. Reveal in either direction without scrolling the inner move list.
    @discardableResult
    private func revealHistoryElement(
        _ element: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let scroll = app.scrollViews["Game.scrollView"].firstMatch
        let deadline = Date().addingTimeInterval(8)
        repeat {
            if element.exists, element.isHittable { return element }
            let towardTop = element.exists && element.frame.midY < scroll.frame.midY
            // Start inside noninteractive content: board squares own drag
            // gestures, and the transparent outer gutter is not a reliable
            // scroll hit target. Never drag the horizontal move list itself.
            let viewport = scroll.frame.intersection(app.windows.firstMatch.frame)
            let anchors = [app.staticTexts["Preferences"], app.staticTexts["Game.historyPosition"]]
            let anchor = anchors.first { candidate in
                guard candidate.exists, candidate.isHittable,
                      viewport.contains(candidate.frame) else { return false }
                let distance = towardTop
                    ? viewport.maxY - 60 - candidate.frame.midY
                    : candidate.frame.midY - max(viewport.minY + 60, app.navigationBars.firstMatch.frame.maxY + 20)
                return distance > 100
            }
            if let anchor {
                let start = anchor.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                let endY = towardTop ? viewport.maxY - 60
                    : max(viewport.minY + 60, app.navigationBars.firstMatch.frame.maxY + 20)
                let end = start.withOffset(CGVector(dx: 0, dy: endY - anchor.frame.midY))
                start.press(forDuration: 0.01, thenDragTo: end)
            } else {
                // Lower preferences can require an initial upward reveal before
                // either text anchor is visible (for example on compact phones).
                let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.3 : 0.82))
                let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: towardTop ? 0.82 : 0.3))
                start.press(forDuration: 0.01, thenDragTo: end)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline
        attachScreenshot(from: app, named: "History - requested element visibility failure")
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal the requested history element", file: file, line: line)
        return element
    }

    private func waitForHistory(
        selected: Int, live: Int, browsing: Bool, in app: XCUIApplication,
        timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        try waitForGameBoardState(
            containing: "History: \(browsing ? "Browsing" : "Live"), Selected ply: \(selected), Live ply: \(live),",
            in: app, named: "selected/live history state", timeout: timeout, file: file, line: line
        )
    }

    private func displayedFEN(in app: XCUIApplication) throws -> String {
        let state = try gameBoardStateValue(in: app)
        guard let range = state.range(of: "FEN: ", options: .backwards) else {
            throw UITestFailure(description: "Missing displayed FEN: \(state)")
        }
        return String(state[range.upperBound...])
    }

    private func livePly(in app: XCUIApplication) throws -> Int {
        let state = try gameBoardStateValue(in: app)
        guard let range = state.range(of: "Live ply: "),
              let value = Int(state[range.upperBound...].prefix(while: { $0.isNumber })) else {
            throw UITestFailure(description: "Missing live ply: \(state)")
        }
        return value
    }

    private func waitForLivePly(atLeast minimum: Int, in app: XCUIApplication) throws {
        let deadline = Date().addingTimeInterval(20)
        repeat {
            if try livePly(in: app) >= minimum { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        XCTFail("Live engine demo did not reach ply \(minimum)")
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

    private func assertEvaluationValueIsAvailable(
        _ evaluationBar: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let value = evaluationBar.value as? String ?? ""
        let isCentipawnScore = value.hasPrefix("White advantage ") || value.hasPrefix("Black advantage ")
        let isMateScore = value.hasPrefix("White mate in ") || value.hasPrefix("Black mate in ")
        let isEqualScore = value == "Equal evaluation"

        XCTAssertTrue(
            isCentipawnScore || isMateScore || isEqualScore,
            "Unexpected evaluation value: \(value)",
            file: file,
            line: line
        )
    }

    private func waitForEvaluationValueIsAvailable(
        _ evaluationBar: XCUIElement,
        named name: String,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastValue = evaluationBar.value as? String ?? ""

        repeat {
            lastValue = evaluationBar.value as? String ?? ""
            let isCentipawnScore = lastValue.hasPrefix("White advantage ") || lastValue.hasPrefix("Black advantage ")
            let isMateScore = lastValue.hasPrefix("White mate in ") || lastValue.hasPrefix("Black mate in ")
            let isEqualScore = lastValue == "Equal evaluation"
            if isCentipawnScore || isMateScore || isEqualScore {
                return
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        XCTFail("Expected \(name) to become available. Last value: \(lastValue)", file: file, line: line)
        throw UITestFailure(description: "\(name) did not become available")
    }

    private func moveSmokeTestApplication(id: String) -> XCUIApplication {
        let app = scenarioTestApplication(id: id)
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_MOVE_TIME_MS"] = "250"
        return app
    }

    private func scenarioTestApplication(id: String) -> XCUIApplication {
        let app = testApplication()
        app.launchEnvironment["SWIFT_CHESS_DEMO_SCENARIO"] = id
        app.launchEnvironment["SWIFT_CHESS_DEMO_SCENARIO_REPLAY_DELAY"] = "0"
        return app
    }

    /// Enables app-only diagnostic accessibility state for black-box assertions.
    private func testApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TESTING"] = "1"
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
