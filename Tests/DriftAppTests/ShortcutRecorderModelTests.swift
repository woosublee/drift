import XCTest
import DriftCore
@testable import DriftApp

@MainActor
final class ShortcutRecorderModelTests: XCTestCase {
    func testEscapeCancelsRecording() {
        let model = ShortcutRecorderModel(shortcut: DriftSettings.default.toggleShortcut) { _ in }
        model.begin()

        model.handle(event: ShortcutRecorderKeyEvent(keyCode: 53, modifiers: []))

        XCTAssertFalse(model.isRecording)
        XCTAssertEqual(model.shortcut, DriftSettings.default.toggleShortcut)
    }

    func testDeleteClearsShortcut() {
        var changes: [GlobalShortcut?] = []
        let model = ShortcutRecorderModel(shortcut: DriftSettings.default.toggleShortcut) { changes.append($0) }
        model.begin()

        model.handle(event: ShortcutRecorderKeyEvent(keyCode: 51, modifiers: []))

        XCTAssertFalse(model.isRecording)
        XCTAssertNil(model.shortcut)
        XCTAssertEqual(changes, [nil])
    }

    func testModifierOnlyInputIsIgnored() {
        let model = ShortcutRecorderModel(shortcut: nil) { _ in }
        model.begin()

        model.handle(event: ShortcutRecorderKeyEvent(keyCode: 55, modifiers: [.command]))

        XCTAssertTrue(model.isRecording)
        XCTAssertNil(model.shortcut)
    }

    func testUnmodifiedLetterIsRejected() {
        let model = ShortcutRecorderModel(shortcut: nil) { _ in }
        model.begin()

        model.handle(event: ShortcutRecorderKeyEvent(keyCode: 2, modifiers: []))

        XCTAssertTrue(model.isRecording)
        XCTAssertEqual(model.validationError, .modifierRequired)
    }

    func testCommandControlDProducesDefaultShortcut() {
        var recorded: GlobalShortcut?
        let model = ShortcutRecorderModel(shortcut: nil) { recorded = $0 }
        model.begin()

        model.handle(event: ShortcutRecorderKeyEvent(keyCode: 2, modifiers: [.command, .control]))

        XCTAssertFalse(model.isRecording)
        XCTAssertEqual(recorded, DriftSettings.default.toggleShortcut)
    }
}
