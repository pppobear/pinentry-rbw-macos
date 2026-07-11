import Foundation
import Security

enum AppLanguage: String, CaseIterable, Equatable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
}

enum LocalizedMessage: Equatable, Sendable {
    case defaultTitle
    case defaultPrompt
    case okButton
    case cancelButton
    case errorPrefix
    case repeatPrompt
    case passphrasesDoNotMatch
    case storeDescription
    case storePrompt
    case stored(account: String, service: String)
    case cleared(account: String, service: String)
    case help
    case loginPasswordFallback
    case sshPasswordGUIUnavailable
    case cannotLaunchOsaScript(detail: String)
    case guiPasswordFailed
    case sshConfirmationGUIUnavailable
    case guiConfirmationFailed
    case guiConfirmationUnknownResult
    case keychainUpdateFailed(status: OSStatus)
    case keychainWriteFailed(status: OSStatus)
    case keychainDeleteFailed(status: OSStatus)
    case keychainInvalidData
    case keychainReadFailed(status: OSStatus)
    case keychainCheckFailed(status: OSStatus)
    case localAuthenticationUnavailable
    case authenticationFailed
    case keychainFallback(reason: String)
    case guiFallback(reason: String)
    case cacheUpdateWarning
    case standardInputInvalidUTF8
    case unknownTerminalError
    case cannotReadTerminal(path: String, reason: String)
    case unknownTerminalStatus(Int32)
    case terminalInputInvalidUTF8
    case cannotOpenTerminal(path: String, reason: String)
    case configuredPathIsNotTerminal(String)
    case cannotWriteTerminal(path: String, reason: String)
    case missingValue(option: String)
    case invalidTimeout(String)
    case duplicateManagementCommand
    case unsupportedArgument(String)
    case unknownManagementCommand(String)
}

struct Localizer: Equatable, Sendable {
    let language: AppLanguage

    static let english = Localizer(language: .english)

    static func resolve(
        explicitLocale: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> Localizer {
        if let explicitLocale = nonEmpty(explicitLocale) {
            return Localizer(language: language(for: explicitLocale) ?? .english)
        }

        if let override = nonEmpty(environment["PINENTRY_RBW_LOCALE"]) {
            return Localizer(language: language(for: override) ?? .english)
        }

        for key in ["LC_ALL", "LC_MESSAGES", "LANG"] {
            if let locale = nonEmpty(environment[key]) {
                return Localizer(language: language(for: locale) ?? .english)
            }
        }

        for locale in preferredLanguages {
            if let language = language(for: locale) {
                return Localizer(language: language)
            }
        }
        return .english
    }

    static func language(for localeIdentifier: String) -> AppLanguage? {
        let withoutModifier = localeIdentifier.split(separator: "@", maxSplits: 1).first.map(String.init) ?? ""
        let withoutEncoding = withoutModifier.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        let normalized = withoutEncoding
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        let parts = normalized.split(separator: "-").map(String.init)
        guard let language = parts.first, !language.isEmpty else { return nil }

        if language == "c" || language == "posix" || language == "en" {
            return .english
        }
        guard language == "zh" else { return nil }

        let subtags = Set(parts.dropFirst())
        if subtags.contains("hant") {
            return nil
        }
        if subtags.contains("hans") {
            return .simplifiedChinese
        }
        if !subtags.isDisjoint(with: Set(["tw", "hk", "mo"])) { return nil }
        if parts.count == 1 || !subtags.isDisjoint(with: Set(["cn", "sg"])) { return .simplifiedChinese }
        return nil
    }

    func text(_ message: LocalizedMessage) -> String {
        switch language {
        case .english:
            return englishText(message)
        case .simplifiedChinese:
            return simplifiedChineseText(message)
        }
    }

    func argumentError(_ error: PinentryArgumentError) -> String {
        switch error {
        case .missingValue(let option):
            return text(.missingValue(option: option))
        case .invalidTimeout(let value):
            return text(.invalidTimeout(value))
        case .duplicateManagementCommand:
            return text(.duplicateManagementCommand)
        case .unsupportedArgument(let argument):
            return text(.unsupportedArgument(argument))
        case .unsupportedOption:
            // Protocol OPTION errors are intentionally stable English. This path is
            // only a defensive fallback for startup argument handling.
            return error.errorDescription ?? "unsupported option"
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func englishText(_ message: LocalizedMessage) -> String {
        switch message {
        case .defaultTitle:
            return "rbw Unlock"
        case .defaultPrompt:
            return "PIN: "
        case .okButton:
            return "OK"
        case .cancelButton:
            return "Cancel"
        case .errorPrefix:
            return "Error:"
        case .repeatPrompt:
            return "Repeat: "
        case .passphrasesDoNotMatch:
            return "Passphrases do not match."
        case .storeDescription:
            return "Enter your Bitwarden master password."
        case .storePrompt:
            return "Master password: "
        case .stored(let account, let service):
            return "stored \(account) in \(service)"
        case .cleared(let account, let service):
            return "cleared \(account) in \(service)"
        case .help:
            return Self.englishHelp
        case .loginPasswordFallback:
            return "Enter Login Password"
        case .sshPasswordGUIUnavailable:
            return "This is an SSH session; skipping the graphical password dialog."
        case .cannotLaunchOsaScript(let detail):
            return "Could not run osascript: \(detail)"
        case .guiPasswordFailed:
            return "The graphical password dialog failed."
        case .sshConfirmationGUIUnavailable:
            return "This is an SSH session; a confirmation dialog cannot be shown."
        case .guiConfirmationFailed:
            return "The graphical confirmation dialog failed."
        case .guiConfirmationUnknownResult:
            return "The graphical confirmation dialog returned an unknown result."
        case .keychainUpdateFailed(let status):
            return "Keychain update failed: \(status)"
        case .keychainWriteFailed(let status):
            return "Keychain write failed: \(status)"
        case .keychainDeleteFailed(let status):
            return "Keychain deletion failed: \(status)"
        case .keychainInvalidData:
            return "Keychain returned data that is not valid UTF-8."
        case .keychainReadFailed(let status):
            return "Keychain read failed: \(status)"
        case .keychainCheckFailed(let status):
            return "Keychain lookup failed: \(status)"
        case .localAuthenticationUnavailable:
            return "LocalAuthentication is unavailable on this device."
        case .authenticationFailed:
            return "Authentication failed."
        case .keychainFallback(let reason):
            return "[pinentry-rbw-macos] Keychain or system authentication is unavailable; using manual input: \(reason)"
        case .guiFallback(let reason):
            return "[pinentry-rbw-macos] The GUI is unavailable; using terminal input: \(reason)"
        case .cacheUpdateWarning:
            return "[pinentry-rbw-macos] Warning: the password worked, but the Keychain cache could not be updated."
        case .standardInputInvalidUTF8:
            return "standard input does not contain valid UTF-8"
        case .unknownTerminalError:
            return "unknown error"
        case .cannotReadTerminal(let path, let reason):
            return "cannot read from terminal \(path): \(reason)"
        case .unknownTerminalStatus(let status):
            return "terminal helper returned an unknown status: \(status)"
        case .terminalInputInvalidUTF8:
            return "terminal input is not valid UTF-8"
        case .cannotOpenTerminal(let path, let reason):
            return "cannot open terminal \(path): \(reason)"
        case .configuredPathIsNotTerminal(let path):
            return "configured tty is not a terminal: \(path)"
        case .cannotWriteTerminal(let path, let reason):
            return "cannot write to terminal \(path): \(reason)"
        case .missingValue(let option):
            return "missing value for \(option)"
        case .invalidTimeout(let value):
            return "invalid timeout: \(value)"
        case .duplicateManagementCommand:
            return "only one management command may be specified"
        case .unsupportedArgument(let argument):
            return "unsupported argument: \(argument)"
        case .unknownManagementCommand(let command):
            return "unknown argument: \(command)"
        }
    }

    private func simplifiedChineseText(_ message: LocalizedMessage) -> String {
        switch message {
        case .defaultTitle:
            return "rbw 解锁"
        case .defaultPrompt:
            return "PIN："
        case .okButton:
            return "确定"
        case .cancelButton:
            return "取消"
        case .errorPrefix:
            return "错误："
        case .repeatPrompt:
            return "请再次输入："
        case .passphrasesDoNotMatch:
            return "两次输入的密码不一致。"
        case .storeDescription:
            return "请输入你的 Bitwarden 主密码。"
        case .storePrompt:
            return "主密码："
        case .stored(let account, let service):
            return "已将 \(account) 存入 \(service)"
        case .cleared(let account, let service):
            return "已从 \(service) 清除 \(account)"
        case .help:
            return Self.simplifiedChineseHelp
        case .loginPasswordFallback:
            return "输入登录密码"
        case .sshPasswordGUIUnavailable:
            return "当前是 SSH 会话，跳过图形密码框。"
        case .cannotLaunchOsaScript(let detail):
            return "无法运行 osascript：\(detail)"
        case .guiPasswordFailed:
            return "图形密码框执行失败。"
        case .sshConfirmationGUIUnavailable:
            return "当前是 SSH 会话，无法显示确认对话框。"
        case .guiConfirmationFailed:
            return "图形确认框执行失败。"
        case .guiConfirmationUnknownResult:
            return "图形确认框返回了未知结果。"
        case .keychainUpdateFailed(let status):
            return "Keychain 更新失败：\(status)"
        case .keychainWriteFailed(let status):
            return "Keychain 写入失败：\(status)"
        case .keychainDeleteFailed(let status):
            return "Keychain 删除失败：\(status)"
        case .keychainInvalidData:
            return "Keychain 返回的数据不是有效的 UTF-8。"
        case .keychainReadFailed(let status):
            return "Keychain 读取失败：\(status)"
        case .keychainCheckFailed(let status):
            return "Keychain 检查失败：\(status)"
        case .localAuthenticationUnavailable:
            return "当前设备无法使用 LocalAuthentication。"
        case .authenticationFailed:
            return "认证失败。"
        case .keychainFallback(let reason):
            return "[pinentry-rbw-macos] Keychain 或系统认证不可用，改用手动输入：\(reason)"
        case .guiFallback(let reason):
            return "[pinentry-rbw-macos] 图形界面不可用，改用终端输入：\(reason)"
        case .cacheUpdateWarning:
            return "[pinentry-rbw-macos] 警告：本次密码可用，但无法更新 Keychain 缓存。"
        case .standardInputInvalidUTF8:
            return "标准输入不是有效的 UTF-8"
        case .unknownTerminalError:
            return "未知错误"
        case .cannotReadTerminal(let path, let reason):
            return "无法从终端 \(path) 读取输入：\(reason)"
        case .unknownTerminalStatus(let status):
            return "终端辅助程序返回了未知状态：\(status)"
        case .terminalInputInvalidUTF8:
            return "终端输入不是有效的 UTF-8"
        case .cannotOpenTerminal(let path, let reason):
            return "无法打开终端 \(path)：\(reason)"
        case .configuredPathIsNotTerminal(let path):
            return "配置的 tty 不是终端：\(path)"
        case .cannotWriteTerminal(let path, let reason):
            return "无法写入终端 \(path)：\(reason)"
        case .missingValue(let option):
            return "\(option) 缺少参数值"
        case .invalidTimeout(let value):
            return "无效的超时时间：\(value)"
        case .duplicateManagementCommand:
            return "一次只能指定一个管理命令"
        case .unsupportedArgument(let argument):
            return "不支持的参数：\(argument)"
        case .unknownManagementCommand(let command):
            return "未知参数：\(command)"
        }
    }

    private static let englishHelp = """
    pinentry-rbw-macos

    Usage:
      pinentry-rbw-macos                    Run the pinentry server
      pinentry-rbw-macos --store            Prompt securely and seed Keychain
      pinentry-rbw-macos --store-stdin      Read a password from stdin and seed Keychain
      pinentry-rbw-macos --clear            Remove the stored password
      pinentry-rbw-macos --version          Print the program version
      pinentry-rbw-macos --help             Show this help

    Pinentry options:
      --ttyname PATH                        Use PATH as the terminal device
      --timeout SECONDS                     Cancel input after SECONDS (0 disables timeout)
      --display DISPLAY                     Pass DISPLAY to the graphical prompt
      --no-global-grab                      Do not request a global input grab
      --lc-messages LOCALE                  Select application messages (en or zh-Hans)

    Environment:
      RBW_PROFILE                           Separate entries by rbw profile
      PINENTRY_RBW_SERVICE                  Override the Keychain service name
      PINENTRY_RBW_ACCOUNT                  Override the Keychain account name
      PINENTRY_RBW_LOG                      Write redacted metadata to a private log
      PINENTRY_RBW_LOCALE                   Override the application locale (en or zh-Hans)
    """

    private static let simplifiedChineseHelp = """
    pinentry-rbw-macos

    用法：
      pinentry-rbw-macos                    运行 pinentry 服务
      pinentry-rbw-macos --store            安全输入主密码并存入 Keychain
      pinentry-rbw-macos --store-stdin      从标准输入读取密码并存入 Keychain
      pinentry-rbw-macos --clear            删除已存密码
      pinentry-rbw-macos --version          显示程序版本
      pinentry-rbw-macos --help             显示此帮助

    Pinentry 兼容选项：
      --ttyname PATH                        使用 PATH 指定的终端设备
      --timeout SECONDS                     SECONDS 秒后取消输入（0 表示不超时）
      --display DISPLAY                     把 DISPLAY 传给图形密码框
      --no-global-grab                      不请求全局输入抓取
      --lc-messages LOCALE                  选择程序语言（en 或 zh-Hans）

    环境变量：
      RBW_PROFILE                           按 rbw profile 隔离 Keychain 条目
      PINENTRY_RBW_SERVICE                  覆盖 Keychain service 名称
      PINENTRY_RBW_ACCOUNT                  覆盖 Keychain account 名称
      PINENTRY_RBW_LOG                      把脱敏元数据写入私有日志
      PINENTRY_RBW_LOCALE                   覆盖程序语言（en 或 zh-Hans）
    """
}
