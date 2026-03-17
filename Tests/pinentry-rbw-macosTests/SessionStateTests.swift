import Testing

@testable import pinentry_rbw_macos

@Suite("SessionState")
struct SessionStateTests {
    @Test func defaultValues() {
        let state = SessionState()
        #expect(state.title == "rbw Unlock")
        #expect(state.description == "Enter your Bitwarden master password.")
        #expect(state.prompt == "Master password: ")
        #expect(state.errorText == "")
        #expect(state.okLabel == "OK")
        #expect(state.cancelLabel == "Cancel")
        #expect(state.repeatPrompt == nil)
        #expect(state.preferManualEntry == false)
    }

    @Test func resetRestoresDefaults() {
        var state = SessionState()
        state.title = "Custom Title"
        state.description = "Custom Desc"
        state.prompt = "PIN:"
        state.errorText = "Wrong password"
        state.okLabel = "Unlock"
        state.cancelLabel = "Abort"
        state.repeatPrompt = "Confirm:"
        state.preferManualEntry = true

        state.reset()

        #expect(state.title == "rbw Unlock")
        #expect(state.description == "Enter your Bitwarden master password.")
        #expect(state.prompt == "Master password: ")
        #expect(state.errorText == "")
        #expect(state.okLabel == "OK")
        #expect(state.cancelLabel == "Cancel")
        #expect(state.repeatPrompt == nil)
        #expect(state.preferManualEntry == false)
    }
}
