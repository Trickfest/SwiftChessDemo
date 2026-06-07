import ChessUI
import XCTest

final class SwiftChessDemoUITests: XCTestCase {
    private var pieceSetNames: [String] {
        ChessPieceSet.availableSets.map(\.displayName)
    }

    private var boardThemeNames: [String] {
        ChessBoardTheme.availableThemes.map(\.displayName)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
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
            app.otherElements["Game.board"].firstMatch,
            named: "game board"
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
            app.otherElements["Game.board"].firstMatch,
            named: "game board"
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
