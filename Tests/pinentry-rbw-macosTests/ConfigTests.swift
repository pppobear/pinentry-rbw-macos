import Darwin
import Testing

@testable import pinentry_rbw_macos

@Suite("Config.load", .serialized)
struct ConfigTests {
    @Test func defaultsWithNoEnv() {
        let config = withEnv([:]) { Config.load() }
        #expect(config.service == "com.enoch.pinentry-rbw-macos")
        #expect(config.account == "rbw:default")
        #expect(config.logPath == nil)
    }

    @Test func respectsProfileEnvVar() {
        let config = withEnv(["RBW_PROFILE": "work"]) { Config.load() }
        #expect(config.account == "rbw:work")
    }

    @Test func respectsServiceOverride() {
        let config = withEnv(["PINENTRY_RBW_SERVICE": "com.example.test"]) { Config.load() }
        #expect(config.service == "com.example.test")
    }

    @Test func respectsAccountOverride() {
        let config = withEnv(["PINENTRY_RBW_ACCOUNT": "custom-account"]) { Config.load() }
        #expect(config.account == "custom-account")
    }

    @Test func respectsLogPath() {
        let config = withEnv(["PINENTRY_RBW_LOG": "/tmp/test.log"]) { Config.load() }
        #expect(config.logPath == "/tmp/test.log")
    }

    @Test func accountOverrideTakesPrecedenceOverProfile() {
        let config = withEnv([
            "RBW_PROFILE": "personal",
            "PINENTRY_RBW_ACCOUNT": "explicit-account",
        ]) { Config.load() }
        #expect(config.account == "explicit-account")
    }
}

/// 在指定的环境变量覆盖下执行 `body`，之后恢复原值。
private func withEnv<T>(_ vars: [String: String], body: () -> T) -> T {
    let allKeys = ["RBW_PROFILE", "PINENTRY_RBW_SERVICE", "PINENTRY_RBW_ACCOUNT", "PINENTRY_RBW_LOG"]
    var originals: [String: String?] = [:]
    for key in allKeys { originals[key] = getenv(key).map { String(cString: $0) } }
    for key in allKeys {
        if let value = vars[key] { setenv(key, value, 1) } else { unsetenv(key) }
    }
    let result = body()
    for (key, original) in originals {
        if let original { setenv(key, original, 1) } else { unsetenv(key) }
    }
    return result
}
