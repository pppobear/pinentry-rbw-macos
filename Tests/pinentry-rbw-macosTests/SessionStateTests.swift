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

    func testSimplifiedChineseDefaultsAndReset() {
        let localizer = Localizer(language: .simplifiedChinese)
        var state = SessionState(localizer: localizer)

        XCTAssertEqual(state.language, .simplifiedChinese)
        XCTAssertEqual(state.title, "rbw 解锁")
        XCTAssertEqual(state.prompt, "PIN：")
        XCTAssertEqual(state.okLabel, "确定")
        XCTAssertEqual(state.cancelLabel, "取消")

        state.title = "自定义标题"
        state.prompt = "自定义提示："
        state.cancelLabel = "返回"
        state.reset()

        XCTAssertEqual(state.title, "rbw 解锁")
        XCTAssertEqual(state.prompt, "PIN：")
        XCTAssertEqual(state.okLabel, "确定")
        XCTAssertEqual(state.cancelLabel, "取消")
    }

    func testRelocalizeOnlyReplacesApplicationDefaults() {
        var defaults = SessionState()
        defaults.relocalize(to: Localizer(language: .simplifiedChinese))
        XCTAssertEqual(defaults.title, "rbw 解锁")
        XCTAssertEqual(defaults.prompt, "PIN：")
        XCTAssertEqual(defaults.cancelLabel, "取消")

        var callerOwned = SessionState()
        callerOwned.setCallerTitle("Caller Title")
        callerOwned.setCallerPrompt("调用方提示：")
        callerOwned.setCallerOKLabel("继续", defaultValue: "OK")
        callerOwned.setCallerCancelLabel("返回", defaultValue: "Cancel")
        callerOwned.relocalize(to: Localizer(language: .simplifiedChinese))

        XCTAssertEqual(callerOwned.title, "Caller Title")
        XCTAssertEqual(callerOwned.prompt, "调用方提示：")
        XCTAssertEqual(callerOwned.okLabel, "继续")
        XCTAssertEqual(callerOwned.cancelLabel, "返回")
        XCTAssertEqual(callerOwned.language, .simplifiedChinese)
    }

    func testRelocalizePreservesCallerValuesEqualToEnglishDefaults() {
        var state = SessionState()
        state.setCallerTitle("rbw Unlock")
        state.setCallerPrompt("PIN: ")
        state.setCallerOKLabel("OK", defaultValue: "OK")
        state.setCallerCancelLabel("Cancel", defaultValue: "Cancel")

        state.relocalize(to: Localizer(language: .simplifiedChinese))

        XCTAssertEqual(state.title, "rbw Unlock")
        XCTAssertEqual(state.prompt, "PIN: ")
        XCTAssertEqual(state.okLabel, "OK")
        XCTAssertEqual(state.cancelLabel, "Cancel")
        XCTAssertEqual(state.language, .simplifiedChinese)
    }
}
