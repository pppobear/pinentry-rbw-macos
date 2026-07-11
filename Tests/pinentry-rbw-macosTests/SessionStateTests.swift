import XCTest

@testable import pinentry_rbw_macos

final class SessionStateTests: XCTestCase {
    func testDefaultValues() {
        let state = SessionState()
        XCTAssertEqual(state.title, "rbw Unlock")
        XCTAssertEqual(state.description, "")
        XCTAssertEqual(state.prompt, "PIN: ")
        XCTAssertEqual(state.errorText, "")
        XCTAssertEqual(state.okLabel, "OK")
        XCTAssertEqual(state.cancelLabel, "Cancel")
        XCTAssertNil(state.notOKLabel)
        XCTAssertNil(state.repeatPrompt)
        XCTAssertNil(state.repeatErrorText)
    }

    func testResetRestoresDefaults() {
        var state = SessionState()
        state.title = "Custom Title"
        state.description = "Custom Desc"
        state.prompt = "PIN:"
        state.errorText = "Wrong password"
        state.okLabel = "Unlock"
        state.cancelLabel = "Abort"
        state.notOKLabel = "No"
        state.repeatPrompt = "Confirm:"
        state.repeatErrorText = "Mismatch"

        state.reset()

        XCTAssertEqual(state.title, "rbw Unlock")
        XCTAssertEqual(state.description, "")
        XCTAssertEqual(state.prompt, "PIN: ")
        XCTAssertEqual(state.errorText, "")
        XCTAssertEqual(state.okLabel, "OK")
        XCTAssertEqual(state.cancelLabel, "Cancel")
        XCTAssertNil(state.notOKLabel)
        XCTAssertNil(state.repeatPrompt)
        XCTAssertNil(state.repeatErrorText)
    }

    func testConsumeTransientErrorKeepsOtherState() {
        var state = SessionState()
        state.errorText = "one-shot error"
        state.prompt = "API key client__id"

        state.consumeTransientError()

        XCTAssertEqual(state.errorText, "")
        XCTAssertEqual(state.prompt, "API key client__id")
    }
}
