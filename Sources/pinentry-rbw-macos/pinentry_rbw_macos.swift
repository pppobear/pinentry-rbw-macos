import Darwin
import Foundation
import LocalAuthentication
import Security

let appVersion = "0.1.0"

private final class DebugLog {
    private let handle: FileHandle?

    /// 日志单文件最大字节数（默认 1 MiB）。超限时截断为后半段保留近期内容。
    private static let maxBytes: UInt64 = 1 * 1024 * 1024

    init(path: String?) {
        guard let path, !path.isEmpty else {
            handle = nil
            return
        }
        let manager = FileManager.default
        if !manager.fileExists(atPath: path) {
            manager.createFile(atPath: path, contents: nil)
        }
        // 超过限制时截断：保留后半段（近期日志）
        if let attrs = try? manager.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64,
           size > Self.maxBytes,
           let fh = FileHandle(forUpdatingAtPath: path)
        {
            let keepFrom = size / 2
            fh.seek(toFileOffset: keepFrom)
            let tail = fh.readDataToEndOfFile()
            fh.seek(toFileOffset: 0)
            fh.write(tail)
            try? fh.truncate(atOffset: UInt64(tail.count))
            try? fh.close()
        }
        handle = FileHandle(forWritingAtPath: path)
        try? handle?.seekToEnd()
    }

    func write(_ message: String) {
        guard let handle else { return }
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        handle.write(Data(line.utf8))
    }
}

struct Config {
    let service: String
    let account: String
    let logPath: String?

    static func load() -> Config {
        let env = ProcessInfo.processInfo.environment
        let profile = env["RBW_PROFILE"] ?? "default"
        let service = env["PINENTRY_RBW_SERVICE"] ?? "com.enoch.pinentry-rbw-macos"
        let account = env["PINENTRY_RBW_ACCOUNT"] ?? "rbw:\(profile)"
        let logPath = env["PINENTRY_RBW_LOG"]
        return Config(service: service, account: account, logPath: logPath)
    }
}

struct SessionState {
    var title = "rbw Unlock"
    var description = "Enter your Bitwarden master password."
    var prompt = "Master password: "
    var errorText = ""
    var okLabel = "OK"
    var cancelLabel = "Cancel"
    var repeatPrompt: String? = nil
    var preferManualEntry = false

    mutating func reset() {
        title = "rbw Unlock"
        description = "Enter your Bitwarden master password."
        prompt = "Master password: "
        errorText = ""
        okLabel = "OK"
        cancelLabel = "Cancel"
        repeatPrompt = nil
        preferManualEntry = false
    }
}

private enum RetrievalResult {
    case success(String)
    case notFound
    case unavailable(String)
    case cancelled
}

private enum PinentryExit: Error {
    case cancelled
    case failed(String)
}

private enum PasswordPromptResult {
    case success(String)
    case cancelled
    case unavailable(String)
}

private final class TTY {
    private let writer: FileHandle?

    init() {
        writer = FileHandle(forWritingAtPath: "/dev/tty")
    }

    func printLine(_ text: String) {
        guard let writer else { return }
        writer.write(Data((text + "\n").utf8))
    }
}

private final class GUI {
    func readPassword(state: SessionState) -> PasswordPromptResult {
        let env = ProcessInfo.processInfo.environment
        if env["SSH_CONNECTION"] != nil || env["SSH_TTY"] != nil {
            return .unavailable("当前会话是 SSH，跳过 GUI")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e", buildAppleScript(state: state),
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .unavailable("无法启动 osascript: \(error.localizedDescription)")
        }

        process.waitUntilExit()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus == 0 {
            if output.isEmpty {
                return .cancelled
            }
            return .success(output)
        }
        if errorOutput.localizedCaseInsensitiveContains("user canceled") {
            return .cancelled
        }
        return .unavailable(errorOutput.isEmpty ? "图形密码框执行失败" : errorOutput)
    }

    private func buildAppleScript(state: SessionState) -> String {
        var lines = [String]()
        if !state.description.isEmpty {
            lines.append(state.description)
        }
        if !state.errorText.isEmpty {
            lines.append(state.errorText)
        }
        let trimmedPrompt = state.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPrompt.isEmpty {
            lines.append(trimmedPrompt)
        }

        let message = escapeForAppleScript(lines.joined(separator: "\n\n"))
        let title = escapeForAppleScript(state.title)
        let ok = escapeForAppleScript(state.okLabel)
        let cancel = escapeForAppleScript(state.cancelLabel)

        return """
        tell application "System Events"
            activate
            text returned of (display dialog "\(message)" with title "\(title)" buttons {"\(cancel)", "\(ok)"} default button "\(ok)" cancel button "\(cancel)" default answer "" with hidden answer)
        end tell
        """
    }

    func showMessage(state: SessionState) {
        let env = ProcessInfo.processInfo.environment
        guard env["SSH_CONNECTION"] == nil, env["SSH_TTY"] == nil else { return }

        let message = escapeForAppleScript(
            [state.description, state.errorText].filter { !$0.isEmpty }.joined(separator: "\n\n")
        )
        let title = escapeForAppleScript(state.title)
        let script = """
        tell application "System Events"
            activate
            display alert "\(title)" message "\(message)"
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
        process.waitUntilExit()
    }

    /// 返回 true 表示用户确认（点击 OK 标签按钮），false 表示取消。
    func showConfirm(state: SessionState) -> Bool {
        let env = ProcessInfo.processInfo.environment
        guard env["SSH_CONNECTION"] == nil, env["SSH_TTY"] == nil else { return false }

        let message = escapeForAppleScript(
            [state.description, state.errorText].filter { !$0.isEmpty }.joined(separator: "\n\n")
        )
        let title  = escapeForAppleScript(state.title)
        let ok     = escapeForAppleScript(state.okLabel)
        let cancel = escapeForAppleScript(state.cancelLabel)
        let script = """
        tell application "System Events"
            activate
            button returned of (display dialog "\(message)" with title "\(title)" buttons {"\(cancel)", "\(ok)"} default button "\(ok)" cancel button "\(cancel)")
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 { return false }
        let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return result == state.okLabel
    }

    private func escapeForAppleScript(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

private struct KeychainStore {
    let config: Config

    /// 从 Keychain 读取已存密码。
    ///
    /// 约束：所有读取路径都必须经过这里，先做 LocalAuthentication，再读普通 Keychain 条目。
    /// 不要新增绕过认证的直接读取入口。
    func fetchAuthorizedPassword(prompt: String) -> RetrievalResult {
        switch authorize(prompt: prompt) {
        case .success:
            break
        case .notFound:
            return .notFound
        case .unavailable(let reason):
            return .unavailable(reason)
        case .cancelled:
            return .cancelled
        }

        return readStoredPassword()
    }

    /// 保存密码到 Keychain。
    func savePassword(_ password: String) throws {
        let query = itemQuery()

        let payload: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: config.service,
            kSecAttrAccount: config.account,
            kSecValueData: Data(password.utf8),
        ]
        let addStatus = SecItemAdd(payload as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let attributesToUpdate: [CFString: Any] = [
                kSecValueData: Data(password.utf8),
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw PinentryExit.failed(
                    SecCopyErrorMessageString(updateStatus, nil) as String? ?? "Keychain 更新失败: \(updateStatus)"
                )
            }
        default:
            throw PinentryExit.failed(
                SecCopyErrorMessageString(addStatus, nil) as String? ?? "Keychain 写入失败: \(addStatus)"
            )
        }
    }

    func deletePassword() throws {
        let status = SecItemDelete(itemQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PinentryExit.failed(
                SecCopyErrorMessageString(status, nil) as String? ?? "Keychain 删除失败: \(status)"
            )
        }
    }

    private func readStoredPassword() -> RetrievalResult {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: config.service,
            kSecAttrAccount: config.account,
            kSecReturnData: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard
                let data = item as? Data,
                let password = String(data: data, encoding: .utf8)
            else {
                return .unavailable("Keychain 返回了不可解析的数据")
            }
            return .success(password)
        case errSecItemNotFound:
            return .notFound
        case errSecUserCanceled, errSecAuthFailed:
            return .cancelled
        default:
            return .unavailable(SecCopyErrorMessageString(status, nil) as String? ?? "Keychain 读取失败: \(status)")
        }
    }

    private func itemQuery() -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: config.service,
            kSecAttrAccount: config.account,
        ]
    }

    private func authorize(prompt: String) -> RetrievalResult {
        var existsQuery = itemQuery()
        existsQuery[kSecReturnAttributes] = true

        let existsStatus = SecItemCopyMatching(existsQuery as CFDictionary, nil)
        if existsStatus == errSecItemNotFound {
            return .notFound
        }
        guard existsStatus == errSecSuccess else {
            return .unavailable(
                SecCopyErrorMessageString(existsStatus, nil) as String? ?? "Keychain 检查失败: \(existsStatus)"
            )
        }

        let context = LAContext()
        context.localizedFallbackTitle = "输入登录密码"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            return .unavailable(authError?.localizedDescription ?? "当前设备不支持 LocalAuthentication")
        }

        final class AuthBox: @unchecked Sendable {
            var result: RetrievalResult = .cancelled
        }

        let semaphore = DispatchSemaphore(value: 0)
        let authBox = AuthBox()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: prompt) { success, error in
            if success {
                authBox.result = .success("")
            } else {
                let nsError = error as NSError?
                if nsError?.code == LAError.userCancel.rawValue || nsError?.code == LAError.appCancel.rawValue {
                    authBox.result = .cancelled
                } else {
                    authBox.result = .unavailable(nsError?.localizedDescription ?? "认证失败")
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
        return authBox.result
    }
}

private final class PinentryServer {
    private let config = Config.load()
    private let tty = TTY()
    private let gui = GUI()
    private lazy var logger = DebugLog(path: config.logPath)
    private lazy var keychain = KeychainStore(config: config)
    private var state = SessionState()

    func run(arguments: [String]) -> Int32 {
        do {
            logger.write("start argv=\(arguments)")
            if let command = arguments.dropFirst().first, isManagementCommand(command) {
                try runManagementCommand(command)
                logger.write("management command completed: \(command)")
                return 0
            }
            writeLine("OK Pleased to meet you")
            while let line = readLine(strippingNewline: true) {
                logger.write("recv \(line)")
                if try !handle(line: line) {
                    logger.write("session end by BYE")
                    break
                }
            }
            logger.write("stdin EOF, exit 0")
            return 0
        } catch PinentryExit.cancelled {
            logger.write("exit cancelled")
            return 1
        } catch PinentryExit.failed(let message) {
            logger.write("fatal \(message)")
            FileHandle.standardError.write(Data(("fatal: \(message)\n").utf8))
            return 2
        } catch {
            logger.write("fatal \(error.localizedDescription)")
            FileHandle.standardError.write(Data(("fatal: \(error.localizedDescription)\n").utf8))
            return 2
        }
    }

    private func isManagementCommand(_ command: String) -> Bool {
        switch command {
        case "--store", "--store-stdin", "--clear", "--help":
            return true
        default:
            return false
        }
    }

    private func runManagementCommand(_ command: String) throws {
        switch command {
        case "--store":
            let password = try readPasswordInteractively(state: SessionState())
            try keychain.savePassword(password)
            print("stored \(config.account) in \(config.service)")
        case "--store-stdin":
            let password = try readPasswordFromStdin()
            try keychain.savePassword(password)
            print("stored \(config.account) in \(config.service)")
        case "--clear":
            try keychain.deletePassword()
            print("cleared \(config.account) in \(config.service)")
        case "--help":
            print("""
            pinentry-rbw-macos

            Usage:
              pinentry-rbw-macos            Run the pinentry server
              pinentry-rbw-macos --store    Prompt on /dev/tty and seed Keychain
              pinentry-rbw-macos --store-stdin
                                            Read a password from stdin and seed Keychain
              pinentry-rbw-macos --clear    Remove the stored password

            Environment:
              RBW_PROFILE             Used to separate entries by rbw profile
              PINENTRY_RBW_SERVICE    Override Keychain service name
              PINENTRY_RBW_ACCOUNT    Override Keychain account name
            """)
        default:
            throw PinentryExit.failed("unknown argument: \(command)")
        }
    }

    private func handle(line: String) throws -> Bool {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let command = String(parts[0]).uppercased()
        let argument = parts.count > 1 ? decodeAssuan(String(parts[1])) : ""

        switch command {
        case "OPTION", "SETOUTPUTFD", "SETNOTOK", "SETREPEATERROR":
            writeOK()
            return true
        case "SETREPEAT":
            state.repeatPrompt = argument.isEmpty ? nil : argument
            writeOK()
            return true
        case "SETOK":
            state.okLabel = argument.isEmpty ? "OK" : argument
            writeOK()
            return true
        case "SETCANCEL":
            state.cancelLabel = argument.isEmpty ? "Cancel" : argument
            writeOK()
            return true
        case "SETTITLE":
            state.title = argument
            writeOK()
            return true
        case "SETDESC":
            state.description = argument
            writeOK()
            return true
        case "SETPROMPT":
            state.prompt = argument
            writeOK()
            return true
        case "SETERROR":
            state.errorText = argument
            state.preferManualEntry = shouldPreferManualEntry(for: argument)
            writeOK()
            return true
        case "GETINFO":
            handleGetInfo(argument)
            return true
        case "RESET":
            state.reset()
            writeOK()
            return true
        case "GETPIN":
            try handleGetPin()
            return true
        case "MESSAGE":
            gui.showMessage(state: state)
            writeOK()
            return true
        case "CONFIRM":
            if gui.showConfirm(state: state) {
                writeOK()
            } else {
                writeCancel("user cancelled confirmation")
            }
            return true
        case "BYE":
            writeOK()
            return false
        default:
            writeError("unsupported command: \(command)")
            return true
        }
    }

    private func handleGetInfo(_ argument: String) {
        switch argument {
        case "pid":
            writeData(String(ProcessInfo.processInfo.processIdentifier))
            writeOK()
        case "version":
            writeData(appVersion)
            writeOK()
        case "flavor":
            writeData("pinentry-rbw-macos")
            writeOK()
        default:
            writeError("unsupported GETINFO value: \(argument)")
        }
    }

    private func handleGetPin() throws {
        let prompt = state.description.isEmpty ? state.prompt : state.description
        logger.write("handle GETPIN prompt=\(prompt)")
        if state.preferManualEntry {
            logger.write("GETPIN switching to manual entry due to prior password error")
            let password = try readPasswordInteractively(state: state)
            try keychain.savePassword(password)
            writeData(password)
            writeOK()
            return
        }
        if state.repeatPrompt != nil {
            logger.write("GETPIN SETREPEAT active; bypassing Keychain cache for confirmation")
            let password = try readPasswordInteractively(state: state)
            try keychain.savePassword(password)
            writeData(password)
            writeOK()
            return
        }

        switch keychain.fetchAuthorizedPassword(prompt: prompt) {
        case .success(let password):
            logger.write("GETPIN success from keychain")
            writeData(password)
            writeOK()
        case .notFound:
            logger.write("GETPIN keychain miss; fallback tty")
            let password = try readPasswordInteractively(state: state)
            try keychain.savePassword(password)
            writeData(password)
            writeOK()
        case .unavailable(let reason):
            logger.write("GETPIN unavailable; fallback tty reason=\(reason)")
            tty.printLine("[pinentry-rbw-macos] Keychain/生物识别不可用，回退到手动输入：\(reason)")
            let password = try readPasswordInteractively(state: state)
            try keychain.savePassword(password)
            writeData(password)
            writeOK()
        case .cancelled:
            logger.write("GETPIN cancelled by auth")
            writeCancel("authentication cancelled")
        }
    }

    private func readPasswordInteractively(state: SessionState) throws -> String {
        guard let repeatLabel = state.repeatPrompt else {
            return try promptPassword(state: state)
        }
        // 需要二次确认：循环直到两次输入匹配或用户取消
        var currentState = state
        while true {
            let password = try promptPassword(state: currentState)

            var repeatState = state
            repeatState.prompt = repeatLabel.isEmpty ? "Repeat: " : repeatLabel
            repeatState.description = ""
            repeatState.errorText = ""
            let confirmation = try promptPassword(state: repeatState)

            if password == confirmation { return password }

            logger.write("GETPIN repeat mismatch, re-prompting")
            currentState.errorText = "Passphrases do not match."
        }
    }

    private func promptPassword(state: SessionState) throws -> String {
        switch gui.readPassword(state: state) {
        case .success(let password):
            logger.write("password collected via GUI")
            return password
        case .cancelled:
            logger.write("GUI prompt cancelled")
            throw PinentryExit.cancelled
        case .unavailable(let reason):
            logger.write("GUI unavailable; fallback tty reason=\(reason)")
            tty.printLine("[pinentry-rbw-macos] GUI 不可用，回退到终端输入：\(reason)")
            return try readPasswordFromTTY(state: state)
        }
    }

    private func readPasswordFromTTY(state: SessionState) throws -> String {
        if !state.title.isEmpty {
            tty.printLine(state.title)
        }
        if !state.description.isEmpty {
            tty.printLine(state.description)
        }
        if !state.errorText.isEmpty {
            tty.printLine("Error: \(state.errorText)")
        }

        let label = state.prompt.isEmpty ? "Master password: " : state.prompt
        return try readPassphrase(label: label)
    }

    private func readPassphrase(label: String) throws -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        let flags = RPP_ECHO_OFF | RPP_REQUIRE_TTY

        guard readpassphrase(label, &buffer, buffer.count, flags) != nil else {
            throw PinentryExit.cancelled
        }
        let passwordBytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let password = String(decoding: passwordBytes, as: UTF8.self)
        if password.isEmpty {
            throw PinentryExit.cancelled
        }
        return password
    }

    private func readPasswordFromStdin() throws -> String {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard var password = String(data: data, encoding: .utf8) else {
            throw PinentryExit.failed("stdin does not contain valid UTF-8")
        }
        while password.last == "\n" || password.last == "\r" {
            password.removeLast()
        }
        if password.isEmpty {
            throw PinentryExit.cancelled
        }
        return password
    }

    private func writeOK() {
        logger.write("send OK")
        writeLine("OK")
    }

    private func writeData(_ value: String) {
        logger.write("send D <redacted len=\(value.count)>")
        writeLine("D \(encodeAssuan(value))")
    }

    private func writeCancel(_ message: String) {
        logger.write("send ERR cancel \(message)")
        writeLine("ERR 83886179 \(message)")
    }

    private func writeError(_ message: String) {
        logger.write("send ERR unsupported \(message)")
        writeLine("ERR 67109139 \(message)")
    }

    private func writeLine(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private func shouldPreferManualEntry(for error: String) -> Bool {
        error.localizedCaseInsensitiveContains("password is incorrect")
    }
}

func decodeAssuan(_ input: String) -> String {
    var scalars = String.UnicodeScalarView()
    var index = input.startIndex

    while index < input.endIndex {
        let character = input[index]
        if character == "%" {
            let next = input.index(after: index)
            // Assuan percent-encoding requires exactly 2 hex digits after %
            if let end = input.index(next, offsetBy: 2, limitedBy: input.endIndex) {
                let hex = String(input[next..<end])
                if let value = UInt8(hex, radix: 16) {
                    let scalar = UnicodeScalar(value)
                    scalars.append(scalar)
                    index = end
                    continue
                }
            }
        }
        scalars.append(contentsOf: String(character).unicodeScalars)
        index = input.index(after: index)
    }

    return String(scalars)
}

func encodeAssuan(_ input: String) -> String {
    var output = ""
    for scalar in input.unicodeScalars {
        switch scalar.value {
        case 0x0A, 0x0D, 0x25:
            output += String(format: "%%%02X", scalar.value)
        default:
            output.append(String(scalar))
        }
    }
    return output
}

@main
struct PinentryRBWMacOS {
    static func main() {
        let server = PinentryServer()
        exit(server.run(arguments: CommandLine.arguments))
    }
}
