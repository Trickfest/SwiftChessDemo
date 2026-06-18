//
// SwiftChessDemo provides an iOS SwiftUI chess demo built with SwiftChessTools and StockfishEmbedded.
//
// See THIRD_PARTY.md for dependency attribution and license details.
//
// Licensed under the GNU General Public License v3.0.
// You may obtain a copy of the License at: https://www.gnu.org/licenses/gpl-3.0.html
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
        let app = moveSmokeTestApplication()
        app.launch()

        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        var position = try boardValue(in: app)
        for (index, move) in ["e2e4", "g1f3", "f1c4", "d2d3"].enumerated() {
            try tapMove(move, in: app)

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
        let app = moveSmokeTestApplication()
        app.launch()

        try select("Play as Black", in: app)
        try requireElement(app.buttons["Start Game"], named: "start game button").tap()

        let initialPosition = try boardValue(in: app)
        let afterWhiteEngineMove = try waitForBoardTurn(
            .black,
            from: initialPosition,
            in: app,
            named: "opening White engine move"
        )

        var position = afterWhiteEngineMove
        for (index, move) in ["e7e5", "b8c6", "g8f6", "f8c5"].enumerated() {
            try tapMove(move, in: app)

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
        let app = moveSmokeTestApplication()
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
            named: "Black scripted reply"
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
                scrollView.swipeUp()
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

    private func moveSmokeTestApplication() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_DEPTH"] = "1"
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_ENGINE_REPLY_DELAY"] = "1.0"
        app.launchEnvironment["SWIFT_CHESS_DEMO_UI_TEST_SCRIPTED_ENGINE"] = "1"
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

        repeat {
            let currentValue = try self.boardValue(in: app, file: file, line: line)
            if currentValue != boardValue,
               currentValue.contains(turn.token) {
                return currentValue
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        let message = "Board value did not change to \(turn.token.trimmingCharacters(in: .whitespaces)) after \(changeName)"
        XCTFail(message, file: file, line: line)
        throw UITestFailure(description: message)
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

    private func boardValue(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let uiTestFEN = app.staticTexts["UITest.positionFEN"].firstMatch
        if uiTestFEN.exists {
            return uiTestFEN.label
        }

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
