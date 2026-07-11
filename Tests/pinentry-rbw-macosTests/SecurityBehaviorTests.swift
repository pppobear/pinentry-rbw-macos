import XCTest

@testable import pinentry_rbw_macos

final class PasswordCachePolicyTests: XCTestCase {
    func testExactMasterPasswordPromptCanUseCache() {
        var state = SessionState()
        state.prompt = "Master Password"

        XCTAssertEqual(passwordCachePolicy(for: state), .readOrUpdate)
    }

    func testEveryOtherPromptIsNeverCached() {
        let uncacheablePrompts = [
            "master password",
            "Master password",
            "Master Password ",
            " Master Password",
            "API key client__id",
            "API key client__secret",
            "Authenticator App",
            "Email Code",
            "Yubikey",
            "Two Factor Authentication",
            "Enter the 6 digit verification code from your authenticator app.",
            "主密码",
        ]

        for prompt in uncacheablePrompts {
            var state = SessionState()
            state.prompt = prompt
            XCTAssertEqual(passwordCachePolicy(for: state), .never, "unexpected cacheable prompt: \(prompt)")
        }
    }

    func testSetErrorBypassesReadButAllowsMasterPasswordRefresh() {
        var state = SessionState()
        state.prompt = "Master Password"
        state.errorText = "authentication failed"

        XCTAssertEqual(passwordCachePolicy(for: state), .refreshAfterPrompt)
    }

    func testSetErrorNeverMakesUnknownPromptCacheable() {
        var state = SessionState()
        state.prompt = "API key client__secret"
        state.errorText = "try again"

        XCTAssertEqual(passwordCachePolicy(for: state), .never)
    }

    func testSetRepeatDisablesBothCacheReadAndWrite() {
        var state = SessionState()
        state.prompt = "Master Password"
        state.repeatPrompt = "Repeat Master Password"

        XCTAssertEqual(passwordCachePolicy(for: state), .never)
    }
}

final class ProcessLineEndingTests: XCTestCase {
    func testRemovesOnlyOneLFAddedByOsaScript() {
        XCTAssertEqual(removingSingleProcessLineEnding(" secret \t\n"), " secret \t")
        XCTAssertEqual(removingSingleProcessLineEnding("secret\n\n"), "secret\n")
    }

    func testRemovesOnlyOneCRLFAddedByProcess() {
        XCTAssertEqual(removingSingleProcessLineEnding(" secret \r\n"), " secret ")
        XCTAssertEqual(removingSingleProcessLineEnding("secret\r\n\r\n"), "secret\r\n")
    }

    func testPreservesWhitespaceAndLoneCarriageReturn() {
        XCTAssertEqual(removingSingleProcessLineEnding("  password\t  "), "  password\t  ")
        XCTAssertEqual(removingSingleProcessLineEnding("password\r"), "password\r")
    }
}

final class AppleScriptCancellationTests: XCTestCase {
    func testRecognizesLocalizedAppleScriptCancellationByErrorNumber() {
        XCTAssertTrue(isAppleScriptCancellation("execution error: 用户已取消。 (-128)"))
        XCTAssertTrue(isAppleScriptCancellation("execution error: User canceled. (-128)\n"))
    }

    func testDoesNotTreatArbitraryNegativeNumberAsCancellation() {
        XCTAssertFalse(isAppleScriptCancellation("failed after -128 attempts"))
        XCTAssertFalse(isAppleScriptCancellation("execution error: not authorized (-1743)"))
    }
}

final class AssuanFailureTests: XCTestCase {
    func testCancellationUsesPinentryCancelledCode() {
        XCTAssertEqual(
            assuanErrorLine(.cancelled, message: "operation cancelled"),
            "ERR 83886179 operation cancelled"
        )
    }

    func testTimeoutUsesPinentryCancellationCodeForCompatibility() {
        XCTAssertEqual(
            assuanErrorLine(.timedOut, message: "operation timed out"),
            "ERR 83886179 operation timed out"
        )
    }

    func testErrorMessageIsAssuanEncoded() {
        XCTAssertEqual(
            assuanErrorLine(.failed, message: "bad\ninput%"),
            "ERR 83886081 bad%0Ainput%25"
        )
    }
}
