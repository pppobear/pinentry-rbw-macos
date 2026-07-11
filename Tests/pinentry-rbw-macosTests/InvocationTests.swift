import XCTest

@testable import pinentry_rbw_macos

final class PinentryInvocationTests: XCTestCase {
    func testParsesRbwStyleArguments() throws {
        let invocation = try PinentryInvocation.parse(arguments: [
            "--timeout", "30",
            "--ttyname", "/dev/ttys007",
            "--display", ":0",
            "--no-global-grab",
        ])

        XCTAssertEqual(invocation.timeoutSeconds, 30)
        XCTAssertEqual(invocation.ttyName, "/dev/ttys007")
        XCTAssertEqual(invocation.display, ":0")
        XCTAssertTrue(invocation.noGlobalGrab)
        XCTAssertNil(invocation.managementCommand)
    }

    func testParsesInlineArgumentsAndManagementCommand() throws {
        let invocation = try PinentryInvocation.parse(arguments: [
            "--store",
            "--timeout=5",
            "--ttyname=/dev/tty",
            "--display=local",
        ])

        XCTAssertEqual(invocation.managementCommand, "--store")
        XCTAssertEqual(invocation.timeoutSeconds, 5)
        XCTAssertEqual(invocation.ttyName, "/dev/tty")
        XCTAssertEqual(invocation.display, "local")
    }

    func testParsesVersionManagementCommand() throws {
        let invocation = try PinentryInvocation.parse(arguments: ["--version"])

        XCTAssertEqual(invocation.managementCommand, "--version")
    }

    func testZeroTimeoutMeansNoTimeout() throws {
        let invocation = try PinentryInvocation.parse(arguments: ["--timeout", "0"])
        XCTAssertNil(invocation.timeoutSeconds)
    }

    func testRejectsMissingOptionValue() {
        XCTAssertThrowsError(try PinentryInvocation.parse(arguments: ["--ttyname"])) { error in
            XCTAssertEqual(error as? PinentryArgumentError, .missingValue("--ttyname"))
        }
    }

    func testRejectsInvalidTimeout() {
        for timeout in ["-1", "86401", "forever"] {
            XCTAssertThrowsError(try PinentryInvocation.parse(arguments: ["--timeout", timeout])) { error in
                XCTAssertEqual(error as? PinentryArgumentError, .invalidTimeout(timeout))
            }
        }
    }

    func testRejectsUnknownStartupArgument() {
        XCTAssertThrowsError(try PinentryInvocation.parse(arguments: ["--unsupported"])) { error in
            XCTAssertEqual(error as? PinentryArgumentError, .unsupportedArgument("--unsupported"))
        }
    }

    func testAppliesOnlySupportedProtocolOptions() throws {
        var invocation = PinentryInvocation()

        try invocation.applyProtocolOption("ttyname=/dev/ttys008")
        try invocation.applyProtocolOption("timeout=12")
        try invocation.applyProtocolOption("display=:1")
        try invocation.applyProtocolOption("no-global-grab")

        XCTAssertEqual(invocation.ttyName, "/dev/ttys008")
        XCTAssertEqual(invocation.timeoutSeconds, 12)
        XCTAssertEqual(invocation.display, ":1")
        XCTAssertTrue(invocation.noGlobalGrab)
    }

    func testRejectsUnsupportedProtocolOptionInsteadOfFakingOK() {
        var invocation = PinentryInvocation()
        XCTAssertThrowsError(try invocation.applyProtocolOption("allow-external-password-cache")) { error in
            XCTAssertEqual(
                error as? PinentryArgumentError,
                .unsupportedOption("allow-external-password-cache")
            )
        }
    }
}
