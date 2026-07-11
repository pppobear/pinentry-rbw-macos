import Darwin
import Foundation
import XCTest

@testable import pinentry_rbw_macos

final class ConfigTests: XCTestCase {
    func testDefaultsWithNoEnv() {
        let config = withEnv([:]) { Config.load() }
        XCTAssertEqual(config.service, "com.enoch.pinentry-rbw-macos")
        XCTAssertEqual(config.account, "rbw:default")
        XCTAssertNil(config.logPath)
    }

    func testRespectsProfileEnvVar() {
        let config = withEnv(["RBW_PROFILE": "work"]) { Config.load() }
        XCTAssertEqual(config.account, "rbw:work")
    }

    func testRespectsServiceOverride() {
        let config = withEnv(["PINENTRY_RBW_SERVICE": "com.example.test"]) { Config.load() }
        XCTAssertEqual(config.service, "com.example.test")
    }

    func testRespectsAccountOverride() {
        let config = withEnv(["PINENTRY_RBW_ACCOUNT": "custom-account"]) { Config.load() }
        XCTAssertEqual(config.account, "custom-account")
    }

    func testRespectsLogPath() {
        let config = withEnv(["PINENTRY_RBW_LOG": "/tmp/test.log"]) { Config.load() }
        XCTAssertEqual(config.logPath, "/tmp/test.log")
    }

    func testAccountOverrideTakesPrecedenceOverProfile() {
        let config = withEnv([
            "RBW_PROFILE": "personal",
            "PINENTRY_RBW_ACCOUNT": "explicit-account",
        ]) { Config.load() }
        XCTAssertEqual(config.account, "explicit-account")
    }
}

private let environmentLock = NSLock()

/// Execute with environment overrides and restore all values before releasing the lock.
private func withEnv<T>(_ vars: [String: String], body: () -> T) -> T {
    environmentLock.lock()
    defer { environmentLock.unlock() }

    let allKeys = ["RBW_PROFILE", "PINENTRY_RBW_SERVICE", "PINENTRY_RBW_ACCOUNT", "PINENTRY_RBW_LOG"]
    var originals: [String: String?] = [:]
    for key in allKeys { originals[key] = getenv(key).map { String(cString: $0) } }
    for key in allKeys {
        if let value = vars[key] { setenv(key, value, 1) } else { unsetenv(key) }
    }
    defer {
        for (key, original) in originals {
            if let original { setenv(key, original, 1) } else { unsetenv(key) }
        }
    }
    return body()
}
