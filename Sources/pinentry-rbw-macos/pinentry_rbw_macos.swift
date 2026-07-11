import Darwin
import CPinentryTTY
import Foundation
import LocalAuthentication
import Security

private final class DebugLog {
    private let handle: FileHandle?

    /// 日志单文件最大字节数（默认 1 MiB）。超限时截断为后半段保留近期内容。
    private static let maxBytes: UInt64 = 1 * 1024 * 1024

    init(path: String?) {
        guard let path, !path.isEmpty else {
            handle = nil
            return
        }
        let flags = O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW
        let descriptor = Darwin.open(path, flags, mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else {
            handle = nil
            return
        }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_uid == geteuid(),
              metadata.st_nlink == 1,
              fchmod(descriptor, mode_t(S_IRUSR | S_IWUSR)) == 0
        else {
            Darwin.close(descriptor)
            handle = nil
            return
        }

        let fileHandle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        // 超过限制时截断：保留后半段（近期日志）
        if metadata.st_size > Int64(Self.maxBytes) {
            let keepFrom = UInt64(metadata.st_size / 2)
            fileHandle.seek(toFileOffset: keepFrom)
            let tail = fileHandle.readDataToEndOfFile()
            fileHandle.seek(toFileOffset: 0)
            fileHandle.write(tail)
            try? fileHandle.truncate(atOffset: UInt64(tail.count))
        }
        fileHandle.seekToEndOfFile()
        handle = fileHandle
    }

    func write(_ message: String) {
        guard let handle else { return }
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        handle.seekToEndOfFile()
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

enum PinentryArgumentError: Error, Equatable, LocalizedError {
    case missingValue(String)
    case invalidTimeout(String)
    case duplicateManagementCommand
    case unsupportedArgument(String)
    case unsupportedOption(String)

    var errorDescription: String? {
        switch self {
        case .missingValue(let option):
            return "missing value for \(option)"
        case .invalidTimeout(let value):
            return "invalid timeout: \(value)"
        case .duplicateManagementCommand:
            return "only one management command may be specified"
        case .unsupportedArgument(let argument):
            return "unsupported argument: \(argument)"
        case .unsupportedOption(let option):
            return "unsupported OPTION: \(option)"
        }
    }
}

struct PinentryInvocation: Equatable {
    static let managementCommands = Set(["--store", "--store-stdin", "--clear", "--help", "--version"])

    var managementCommand: String?
    var ttyName: String?
    var timeoutSeconds: Int?
    var display: String?
    var noGlobalGrab = false

    static func parse(arguments: [String]) throws -> PinentryInvocation {
        var invocation = PinentryInvocation()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if managementCommands.contains(argument) {
                guard invocation.managementCommand == nil else {
                    throw PinentryArgumentError.duplicateManagementCommand
                }
                invocation.managementCommand = argument
                index += 1
                continue
            }

            if argument == "--no-global-grab" {
                invocation.noGlobalGrab = true
                index += 1
                continue
            }

            if let value = inlineValue(for: "--ttyname", in: argument) {
                invocation.ttyName = try requireNonEmpty(value, option: "--ttyname")
                index += 1
                continue
            }
            if let value = inlineValue(for: "--timeout", in: argument) {
                invocation.timeoutSeconds = try parseTimeout(value)
                index += 1
                continue
            }
            if let value = inlineValue(for: "--display", in: argument) {
                invocation.display = try requireNonEmpty(value, option: "--display")
                index += 1
                continue
            }

            switch argument {
            case "--ttyname", "--timeout", "--display":
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw PinentryArgumentError.missingValue(argument)
                }
                let value = arguments[valueIndex]
                switch argument {
                case "--ttyname":
                    invocation.ttyName = try requireNonEmpty(value, option: argument)
                case "--timeout":
                    invocation.timeoutSeconds = try parseTimeout(value)
                default:
                    invocation.display = try requireNonEmpty(value, option: argument)
                }
                index += 2
            default:
                throw PinentryArgumentError.unsupportedArgument(argument)
            }
        }

        return invocation
    }

    mutating func applyProtocolOption(_ option: String) throws {
        if option == "no-global-grab" {
            noGlobalGrab = true
            return
        }
        if option.hasPrefix("ttyname=") {
            ttyName = try Self.requireNonEmpty(String(option.dropFirst("ttyname=".count)), option: "ttyname")
            return
        }
        if option.hasPrefix("timeout=") {
            timeoutSeconds = try Self.parseTimeout(String(option.dropFirst("timeout=".count)))
            return
        }
        if option.hasPrefix("display=") {
            display = try Self.requireNonEmpty(String(option.dropFirst("display=".count)), option: "display")
            return
        }
        throw PinentryArgumentError.unsupportedOption(option)
    }

    private static func inlineValue(for option: String, in argument: String) -> String? {
        let prefix = option + "="
        guard argument.hasPrefix(prefix) else { return nil }
        return String(argument.dropFirst(prefix.count))
    }

    private static func requireNonEmpty(_ value: String, option: String) throws -> String {
        guard !value.isEmpty else { throw PinentryArgumentError.missingValue(option) }
        return value
    }

    private static func parseTimeout(_ value: String) throws -> Int? {
        guard let seconds = Int(value), (0...86_400).contains(seconds) else {
            throw PinentryArgumentError.invalidTimeout(value)
        }
        return seconds == 0 ? nil : seconds
    }
}

struct SessionState {
    var title = "rbw Unlock"
    var description = ""
    var prompt = "PIN: "
    var errorText = ""
    var okLabel = "OK"
    var cancelLabel = "Cancel"
    var notOKLabel: String? = nil
    var repeatPrompt: String? = nil
    var repeatErrorText: String? = nil

    mutating func reset() {
        title = "rbw Unlock"
        description = ""
        prompt = "PIN: "
        errorText = ""
        okLabel = "OK"
        cancelLabel = "Cancel"
        notOKLabel = nil
        repeatPrompt = nil
        repeatErrorText = nil
    }

    mutating func consumeTransientError() {
        errorText = ""
    }
}

enum PasswordCachePolicy: Equatable {
    /// Read an existing master password; save a manually entered replacement on a miss.
    case readOrUpdate
    /// A prior error invalidated the cached master password; collect and save a replacement.
    case refreshAfterPrompt
    /// The request is not provably rbw's master-password unlock prompt.
    case never
}

let rbwMasterPasswordPrompt = "Master Password"

func passwordCachePolicy(for state: SessionState) -> PasswordCachePolicy {
    guard state.prompt == rbwMasterPasswordPrompt else { return .never }
    // SETREPEAT is used for creating a new passphrase, not unlocking rbw. Never let that
    // flow read from or overwrite the rbw master-password cache, even if the prompt text
    // happens to match.
    guard state.repeatPrompt == nil else { return .never }
    if !state.errorText.isEmpty {
        return .refreshAfterPrompt
    }
    return .readOrUpdate
}

func removingSingleProcessLineEnding(_ input: String) -> String {
    if input.hasSuffix("\r\n") {
        return String(input.dropLast(2))
    }
    if input.hasSuffix("\n") {
        return String(input.dropLast())
    }
    return input
}

func isAppleScriptCancellation(_ errorOutput: String) -> Bool {
    let normalized = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.hasSuffix("(-128)")
        || normalized.localizedCaseInsensitiveContains("user canceled")
}

private enum RetrievalResult {
    case success(String)
    case notFound
    case unavailable(String)
    case cancelled
    case timedOut
}

private enum PinentryExit: Error {
    case cancelled
    case timedOut
    case failed(String)
}

private enum PasswordPromptResult {
    case success(String)
    case cancelled
    case unavailable(String)
    case timedOut
}

private final class TTY {
    private let path: String
    private let timeoutSeconds: Int?

    init(path: String? = nil, timeoutSeconds: Int? = nil) {
        self.path = path ?? "/dev/tty"
        self.timeoutSeconds = timeoutSeconds
    }

    func printLine(_ text: String) {
        guard let descriptor = try? openTTY() else { return }
        defer { Darwin.close(descriptor) }
        try? writeAll(Data((text + "\n").utf8), to: descriptor)
    }

    func readPassphrase(label: String) throws -> String {
        let descriptor = try openTTY()
        defer { Darwin.close(descriptor) }

        var passwordBytes = [CChar](repeating: 0, count: 4096)
        defer {
            passwordBytes.withUnsafeMutableBytes { bytes in
                guard let baseAddress = bytes.baseAddress else { return }
                _ = memset_s(baseAddress, bytes.count, 0, bytes.count)
            }
        }

        var readError: Int32 = 0
        let status = label.withCString { prompt in
            passwordBytes.withUnsafeMutableBufferPointer { buffer in
                pinentry_read_secret(
                    descriptor,
                    prompt,
                    buffer.baseAddress,
                    buffer.count,
                    UInt32(timeoutSeconds ?? 0),
                    &readError
                )
            }
        }

        switch status {
        case Int32(PINENTRY_TTY_CANCELLED), Int32(PINENTRY_TTY_INTERRUPTED):
            throw PinentryExit.cancelled
        case Int32(PINENTRY_TTY_TIMED_OUT):
            throw PinentryExit.timedOut
        case Int32(PINENTRY_TTY_ERROR):
            let reason = readError == 0 ? "unknown error" : String(cString: strerror(readError))
            throw PinentryExit.failed("cannot read from terminal \(path): \(reason)")
        case Int32(PINENTRY_TTY_SUCCESS):
            break
        default:
            throw PinentryExit.failed("terminal helper returned an unknown status: \(status)")
        }

        guard let password = passwordBytes.withUnsafeBufferPointer({ buffer in
            buffer.baseAddress.flatMap { String(validatingCString: $0) }
        }) else {
            throw PinentryExit.failed("terminal input is not valid UTF-8")
        }
        return password
    }

    private func openTTY() throws -> Int32 {
        let descriptor = Darwin.open(path, O_RDWR | O_NOCTTY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw PinentryExit.failed("cannot open terminal \(path): \(posixError())")
        }
        guard isatty(descriptor) == 1 else {
            Darwin.close(descriptor)
            throw PinentryExit.failed("configured tty is not a terminal: \(path)")
        }
        return descriptor
    }

    private func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let count = Darwin.write(descriptor, baseAddress.advanced(by: written), rawBuffer.count - written)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw PinentryExit.failed("cannot write to terminal \(path): \(posixError())")
                }
                written += count
            }
        }
    }

    private func posixError() -> String {
        String(cString: strerror(errno))
    }
}

private enum ConfirmationResult {
    case confirmed
    case rejected
    case cancelled
    case unavailable(String)
    case timedOut
}

private final class GUI {
    private let display: String?
    private let timeoutSeconds: Int?
    // AppleScript dialogs never take a global input grab. Retain the parsed value so the
    // invocation semantics remain explicit if another GUI backend is added later.
    private let noGlobalGrab: Bool

    init(display: String? = nil, timeoutSeconds: Int? = nil, noGlobalGrab: Bool = false) {
        self.display = display
        self.timeoutSeconds = timeoutSeconds
        self.noGlobalGrab = noGlobalGrab
    }

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
        configureEnvironment(for: process)

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .unavailable("无法启动 osascript: \(error.localizedDescription)")
        }

        guard waitForExit(process) else { return .timedOut }
        let rawOutput = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let output = removingSingleProcessLineEnding(rawOutput)
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus == 0 {
            if output.isEmpty {
                return .cancelled
            }
            return .success(output)
        }
        if isAppleScriptCancellation(errorOutput) {
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

    func showMessage(state: SessionState) -> ConfirmationResult {
        showConfirm(state: state, oneButton: true)
    }

    func showConfirm(state: SessionState, oneButton: Bool = false) -> ConfirmationResult {
        let env = ProcessInfo.processInfo.environment
        guard env["SSH_CONNECTION"] == nil, env["SSH_TTY"] == nil else {
            return .unavailable("当前会话是 SSH，无法显示确认对话框")
        }

        let message = escapeForAppleScript(
            [state.description, state.errorText].filter { !$0.isEmpty }.joined(separator: "\n\n")
        )
        let title  = escapeForAppleScript(state.title)
        let ok     = escapeForAppleScript(state.okLabel)
        let cancel = escapeForAppleScript(state.cancelLabel)
        let buttons: String
        let cancelClause: String
        if oneButton {
            buttons = "{\"\(ok)\"}"
            cancelClause = ""
        } else if let notOKLabel = state.notOKLabel, !notOKLabel.isEmpty {
            let notOK = escapeForAppleScript(notOKLabel)
            buttons = "{\"\(cancel)\", \"\(notOK)\", \"\(ok)\"}"
            cancelClause = " cancel button \"\(cancel)\""
        } else {
            buttons = "{\"\(cancel)\", \"\(ok)\"}"
            cancelClause = " cancel button \"\(cancel)\""
        }
        let script = """
        tell application "System Events"
            activate
            button returned of (display dialog "\(message)" with title "\(title)" buttons \(buttons) default button "\(ok)"\(cancelClause))
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        configureEnvironment(for: process)
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            return .unavailable("无法启动 osascript: \(error.localizedDescription)")
        }
        guard waitForExit(process) else { return .timedOut }

        let result = removingSingleProcessLineEnding(
            String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus != 0 {
            if isAppleScriptCancellation(errorOutput) {
                return .cancelled
            }
            return .unavailable(errorOutput.isEmpty ? "图形确认框执行失败" : errorOutput)
        }
        if result == state.okLabel { return .confirmed }
        if result == state.notOKLabel { return .rejected }
        return oneButton ? .unavailable("图形确认框返回了未知结果") : .cancelled
    }

    private func configureEnvironment(for process: Process) {
        guard let display else { return }
        var environment = ProcessInfo.processInfo.environment
        environment["DISPLAY"] = display
        process.environment = environment
        _ = noGlobalGrab
    }

    private func waitForExit(_ process: Process) -> Bool {
        guard let timeoutSeconds else {
            process.waitUntilExit()
            return true
        }
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while process.isRunning, deadline.timeIntervalSinceNow > 0 {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return false
        }
        return true
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
    func fetchAuthorizedPassword(prompt: String, timeoutSeconds: Int?) -> RetrievalResult {
        switch authorize(prompt: prompt, timeoutSeconds: timeoutSeconds) {
        case .success:
            break
        case .notFound:
            return .notFound
        case .unavailable(let reason):
            return .unavailable(reason)
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timedOut
        }

        return readStoredPassword()
    }

    /// 保存密码到 Keychain。
    func savePassword(_ password: String) throws {
        let query = itemQuery()
        var passwordData = Data(password.utf8)
        defer { passwordData.resetBytes(in: 0..<passwordData.count) }

        let payload: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: config.service,
            kSecAttrAccount: config.account,
            kSecValueData: passwordData,
        ]
        let addStatus = SecItemAdd(payload as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let attributesToUpdate: [CFString: Any] = [
                kSecValueData: passwordData,
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

    private func authorize(prompt: String, timeoutSeconds: Int?) -> RetrievalResult {
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
        if let timeoutSeconds {
            let waitResult = semaphore.wait(timeout: .now() + .seconds(timeoutSeconds))
            if waitResult == .timedOut {
                context.invalidate()
                return .timedOut
            }
        } else {
            semaphore.wait()
        }
        return authBox.result
    }
}

enum AssuanFailure: Equatable {
    case cancelled
    case timedOut
    case notConfirmed
    case failed
    case unsupported
}

func assuanErrorLine(_ failure: AssuanFailure, message: String) -> String {
    let code: Int
    switch failure {
    case .cancelled:
        code = 83_886_179 // GPG_ERR_SOURCE_PINENTRY + GPG_ERR_CANCELED
        case .timedOut:
            // pinentry's --timeout contract reports the same error as Cancel, and rbw
            // recognizes that code as the recoverable cancellation path.
            code = 83_886_179 // GPG_ERR_SOURCE_PINENTRY + GPG_ERR_CANCELED
    case .notConfirmed:
        code = 83_886_194 // GPG_ERR_SOURCE_PINENTRY + GPG_ERR_NOT_CONFIRMED
    case .failed:
        code = 83_886_081 // GPG_ERR_SOURCE_PINENTRY + GPG_ERR_GENERAL
    case .unsupported:
        code = 67_109_139 // GPG_ERR_SOURCE_ASSUAN + GPG_ERR_ASS_UNKNOWN_CMD
    }
    return "ERR \(code) \(encodeAssuan(message))"
}

private final class PinentryServer {
    private static let knownProtocolCommands = Set([
        "BYE", "CONFIRM", "GETINFO", "GETPIN", "MESSAGE", "OPTION", "RESET",
        "SETCANCEL", "SETDESC", "SETERROR", "SETNOTOK", "SETOK", "SETOUTPUTFD",
        "SETPROMPT", "SETREPEAT", "SETREPEATERROR", "SETTITLE",
    ])

    private let config = Config.load()
    private var invocation = PinentryInvocation()
    private var tty = TTY()
    private var gui = GUI()
    private lazy var logger = DebugLog(path: config.logPath)
    private lazy var keychain = KeychainStore(config: config)
    private var state = SessionState()

    func run(arguments: [String]) -> Int32 {
        do {
            logger.write("start argc=\(arguments.count)")
            invocation = try PinentryInvocation.parse(arguments: Array(arguments.dropFirst()))
            configureUserInteraction()
            if let command = invocation.managementCommand {
                try runManagementCommand(command)
                logger.write("management command completed: \(command)")
                return 0
            }
            writeLine("OK Pleased to meet you")
            while let line = readLine(strippingNewline: true) {
                logger.write(protocolLogMetadata(for: line))
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
        } catch PinentryExit.timedOut {
            logger.write("exit timed out")
            return 1
        } catch PinentryExit.failed(let message) {
            logger.write("fatal messageBytes=\(message.utf8.count)")
            FileHandle.standardError.write(Data(("fatal: \(message)\n").utf8))
            return 2
        } catch {
            logger.write("fatal messageBytes=\(error.localizedDescription.utf8.count)")
            FileHandle.standardError.write(Data(("fatal: \(error.localizedDescription)\n").utf8))
            return 2
        }
    }

    private func configureUserInteraction() {
        tty = TTY(path: invocation.ttyName, timeoutSeconds: invocation.timeoutSeconds)
        gui = GUI(
            display: invocation.display,
            timeoutSeconds: invocation.timeoutSeconds,
            noGlobalGrab: invocation.noGlobalGrab
        )
    }

    private func runManagementCommand(_ command: String) throws {
        switch command {
        case "--store":
            var storeState = SessionState()
            storeState.description = "Enter your Bitwarden master password."
            storeState.prompt = "Master password: "
            let password = try readPasswordInteractively(state: storeState)
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
              pinentry-rbw-macos --store    Prompt securely and seed Keychain
              pinentry-rbw-macos --store-stdin
                                            Read a password from stdin and seed Keychain
              pinentry-rbw-macos --clear    Remove the stored password
              pinentry-rbw-macos --version  Print the program version

            Environment:
              RBW_PROFILE             Used to separate entries by rbw profile
              PINENTRY_RBW_SERVICE    Override Keychain service name
              PINENTRY_RBW_ACCOUNT    Override Keychain account name
              PINENTRY_RBW_LOG        Write redacted protocol metadata to a private log
            """)
        case "--version":
            print(appVersion)
        default:
            throw PinentryExit.failed("unknown argument: \(command)")
        }
    }

    private func handle(line: String) throws -> Bool {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let command = String(parts[0]).uppercased()
        let argument = parts.count > 1 ? decodeAssuan(String(parts[1])) : ""

        switch command {
        case "OPTION":
            do {
                try invocation.applyProtocolOption(argument)
                configureUserInteraction()
                writeOK()
            } catch {
                writeError(error.localizedDescription)
            }
            return true
        case "SETOUTPUTFD":
            writeError("SETOUTPUTFD is not supported")
            return true
        case "SETNOTOK":
            state.notOKLabel = argument.isEmpty ? nil : argument
            writeOK()
            return true
        case "SETREPEATERROR":
            state.repeatErrorText = argument.isEmpty ? nil : argument
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
            do {
                try handleGetPin()
            } catch PinentryExit.cancelled {
                writeCancel("operation cancelled")
            } catch PinentryExit.timedOut {
                writeTimeout("operation timed out")
            } catch PinentryExit.failed(let message) {
                writeFailure(message)
            } catch {
                writeFailure(error.localizedDescription)
            }
            return true
        case "MESSAGE":
            let result = gui.showMessage(state: state)
            state.consumeTransientError()
            writeConfirmationResult(result)
            return true
        case "CONFIRM":
            let oneButton = argument.split(separator: " ").contains("--one-button")
            let result = gui.showConfirm(state: state, oneButton: oneButton)
            state.consumeTransientError()
            writeConfirmationResult(result)
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
        let cachePolicy = passwordCachePolicy(for: state)
        logger.write("handle GETPIN promptBytes=\(state.prompt.utf8.count) cachePolicy=\(cachePolicy)")
        defer { state.consumeTransientError() }

        switch cachePolicy {
        case .never:
            logger.write("GETPIN uncacheable prompt; collecting manual input")
            let password = try readPasswordInteractively(state: state)
            writeData(password)
            writeOK()
            return
        case .refreshAfterPrompt:
            logger.write("GETPIN prior error present; collecting replacement master password")
            let password = try readPasswordInteractively(state: state)
            updateCacheBestEffort(password)
            writeData(password)
            writeOK()
            return
        case .readOrUpdate:
            break
        }

        switch keychain.fetchAuthorizedPassword(prompt: prompt, timeoutSeconds: invocation.timeoutSeconds) {
        case .success(let password):
            logger.write("GETPIN success from keychain")
            writeData(password)
            writeOK()
        case .notFound:
            logger.write("GETPIN keychain miss; fallback tty")
            let password = try readPasswordInteractively(state: state)
            updateCacheBestEffort(password)
            writeData(password)
            writeOK()
        case .unavailable(let reason):
            logger.write("GETPIN unavailable; fallback tty reasonBytes=\(reason.utf8.count)")
            tty.printLine("[pinentry-rbw-macos] Keychain/生物识别不可用，回退到手动输入：\(reason)")
            let password = try readPasswordInteractively(state: state)
            updateCacheBestEffort(password)
            writeData(password)
            writeOK()
        case .cancelled:
            logger.write("GETPIN cancelled by auth")
            throw PinentryExit.cancelled
        case .timedOut:
            logger.write("GETPIN authentication timed out")
            throw PinentryExit.timedOut
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
            currentState.errorText = state.repeatErrorText ?? "Passphrases do not match."
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
        case .timedOut:
            logger.write("GUI prompt timed out")
            throw PinentryExit.timedOut
        case .unavailable(let reason):
            logger.write("GUI unavailable; fallback tty reasonBytes=\(reason.utf8.count)")
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

        let label = state.prompt.isEmpty ? "PIN: " : state.prompt
        return try tty.readPassphrase(label: label)
    }

    private func readPasswordFromStdin() throws -> String {
        var data = FileHandle.standardInput.readDataToEndOfFile()
        defer { data.resetBytes(in: 0..<data.count) }
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

    private func updateCacheBestEffort(_ password: String) {
        do {
            try keychain.savePassword(password)
        } catch {
            logger.write("Keychain cache update failed errorBytes=\(error.localizedDescription.utf8.count)")
            tty.printLine("[pinentry-rbw-macos] 警告：本次密码可用，但无法更新 Keychain 缓存。")
        }
    }

    private func protocolLogMetadata(for line: String) -> String {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        let rawCommand = parts.first.map(String.init) ?? ""
        let normalizedCommand = rawCommand.uppercased()
        let command = Self.knownProtocolCommands.contains(normalizedCommand) ? normalizedCommand : "<unknown>"
        let argumentBytes = parts.count > 1 ? parts[1].utf8.count : 0
        return "recv command=\(command) commandBytes=\(rawCommand.utf8.count) argumentBytes=\(argumentBytes)"
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
        writeLine(assuanErrorLine(.cancelled, message: message))
    }

    private func writeTimeout(_ message: String) {
        logger.write("send ERR timeout \(message)")
        writeLine(assuanErrorLine(.timedOut, message: message))
    }

    private func writeFailure(_ message: String) {
        logger.write("send ERR failed messageBytes=\(message.utf8.count)")
        writeLine(assuanErrorLine(.failed, message: message))
    }

    private func writeError(_ message: String) {
        logger.write("send ERR unsupported messageBytes=\(message.utf8.count)")
        writeLine(assuanErrorLine(.unsupported, message: message))
    }

    private func writeLine(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private func writeConfirmationResult(_ result: ConfirmationResult) {
        switch result {
        case .confirmed:
            writeOK()
        case .rejected:
            logger.write("send ERR not confirmed")
            writeLine(assuanErrorLine(.notConfirmed, message: "not confirmed"))
        case .cancelled:
            writeCancel("user cancelled confirmation")
        case .timedOut:
            writeTimeout("confirmation timed out")
        case .unavailable(let reason):
            writeFailure(reason)
        }
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
