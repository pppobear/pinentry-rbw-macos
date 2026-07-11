import XCTest

@testable import pinentry_rbw_macos

final class LocaleResolutionTests: XCTestCase {
    func testRecognizesEnglishAndSimplifiedChineseIdentifiers() {
        for locale in ["en", "en-US", "C", "POSIX", "C.UTF-8"] {
            XCTAssertEqual(Localizer.language(for: locale), .english, locale)
        }
        for locale in ["zh", "zh-CN", "zh_CN.UTF-8", "zh-Hans", "zh-Hans-CN", "zh-SG"] {
            XCTAssertEqual(Localizer.language(for: locale), .simplifiedChinese, locale)
        }
        XCTAssertEqual(Localizer.language(for: "zh-Hans-HK"), .simplifiedChinese)
    }

    func testDoesNotSendSimplifiedChineseToTraditionalChineseLocales() {
        for locale in ["zh-Hant", "zh-TW", "zh-HK", "zh-MO"] {
            XCTAssertNil(Localizer.language(for: locale), locale)
            XCTAssertEqual(
                Localizer.resolve(explicitLocale: locale, environment: [:], preferredLanguages: []).language,
                .english,
                locale
            )
        }
        XCTAssertNil(Localizer.language(for: "zh-Hant-CN"))
    }

    func testExplicitLocaleOverridesEnvironmentAndSystemLanguages() {
        let localizer = Localizer.resolve(
            explicitLocale: "en-US",
            environment: ["PINENTRY_RBW_LOCALE": "zh-Hans"],
            preferredLanguages: ["zh-Hans"]
        )
        XCTAssertEqual(localizer.language, .english)
    }

    func testApplicationOverridePrecedesStandardLocaleVariables() {
        let localizer = Localizer.resolve(
            environment: [
                "PINENTRY_RBW_LOCALE": "zh-Hans",
                "LC_ALL": "en_US.UTF-8",
                "LC_MESSAGES": "en_US.UTF-8",
                "LANG": "en_US.UTF-8",
            ],
            preferredLanguages: ["en-US"]
        )
        XCTAssertEqual(localizer.language, .simplifiedChinese)
    }

    func testStandardLocalePriorityIsDeterministic() {
        XCTAssertEqual(
            Localizer.resolve(
                environment: ["LC_ALL": "zh_CN.UTF-8", "LC_MESSAGES": "en_US.UTF-8"],
                preferredLanguages: ["en-US"]
            ).language,
            .simplifiedChinese
        )
        XCTAssertEqual(
            Localizer.resolve(
                environment: ["LC_ALL": "", "LC_MESSAGES": "zh_CN.UTF-8", "LANG": "en_US.UTF-8"],
                preferredLanguages: ["en-US"]
            ).language,
            .simplifiedChinese
        )
    }

    func testPreferredLanguagesChooseFirstSupportedLanguage() {
        XCTAssertEqual(
            Localizer.resolve(environment: [:], preferredLanguages: ["fr-FR", "zh-Hans-CN", "en-US"]).language,
            .simplifiedChinese
        )
        XCTAssertEqual(
            Localizer.resolve(environment: [:], preferredLanguages: ["fr-FR", "de-DE"]).language,
            .english
        )
    }

    func testUnsupportedExplicitLocaleFallsBackToEnglish() {
        let localizer = Localizer.resolve(
            explicitLocale: "fr-FR",
            environment: ["PINENTRY_RBW_LOCALE": "zh-Hans"],
            preferredLanguages: ["zh-Hans"]
        )
        XCTAssertEqual(localizer.language, .english)
    }
}

final class LocalizedCatalogTests: XCTestCase {
    func testEveryMessageHasNonEmptyEnglishAndChineseText() {
        let messages: [LocalizedMessage] = [
            .defaultTitle,
            .defaultPrompt,
            .okButton,
            .cancelButton,
            .fatalPrefix,
            .errorPrefix,
            .repeatPrompt,
            .passphrasesDoNotMatch,
            .storeDescription,
            .storePrompt,
            .stored(account: "rbw:test", service: "service.test"),
            .cleared(account: "rbw:test", service: "service.test"),
            .help,
            .loginPasswordFallback,
            .sshPasswordGUIUnavailable,
            .cannotLaunchOsaScript(detail: "detail"),
            .guiPasswordFailed,
            .sshConfirmationGUIUnavailable,
            .guiConfirmationFailed,
            .guiConfirmationUnknownResult,
            .keychainUpdateFailed(status: -1),
            .keychainWriteFailed(status: -2),
            .keychainDeleteFailed(status: -3),
            .keychainInvalidData,
            .keychainReadFailed(status: -4),
            .keychainCheckFailed(status: -5),
            .localAuthenticationUnavailable,
            .authenticationFailed,
            .keychainFallback(reason: "reason"),
            .guiFallback(reason: "reason"),
            .cacheUpdateWarning,
            .standardInputInvalidUTF8,
            .unknownTerminalError,
            .cannotReadTerminal(path: "/dev/tty", reason: "reason"),
            .unknownTerminalStatus(99),
            .terminalInputInvalidUTF8,
            .cannotOpenTerminal(path: "/dev/tty", reason: "reason"),
            .configuredPathIsNotTerminal("/tmp/file"),
            .cannotWriteTerminal(path: "/dev/tty", reason: "reason"),
            .missingValue(option: "--timeout"),
            .invalidTimeout("later"),
            .duplicateManagementCommand,
            .unsupportedArgument("--unknown"),
            .unknownManagementCommand("--unknown"),
        ]

        for language in AppLanguage.allCases {
            let localizer = Localizer(language: language)
            for message in messages {
                XCTAssertFalse(localizer.text(message).isEmpty, "\(language.rawValue): \(message)")
            }
        }
    }

    func testDynamicMessagesPreserveInsertedValues() {
        for language in AppLanguage.allCases {
            let localizer = Localizer(language: language)
            let stored = localizer.text(.stored(account: "rbw:工作", service: "service.example"))
            XCTAssertTrue(stored.contains("rbw:工作"))
            XCTAssertTrue(stored.contains("service.example"))

            let fallback = localizer.text(.guiFallback(reason: "reason-123"))
            XCTAssertTrue(fallback.contains("reason-123"))
        }
    }

    func testHelpIsLocalizedAndListsEveryAcceptedOption() {
        let english = Localizer.english.text(.help)
        let chinese = Localizer(language: .simplifiedChinese).text(.help)
        let options = [
            "--store", "--store-stdin", "--clear", "--version", "--help",
            "--ttyname", "--timeout", "--display", "--no-global-grab", "--lc-messages",
        ]

        XCTAssertTrue(english.contains("Usage:"))
        XCTAssertTrue(chinese.contains("用法："))
        XCTAssertNotEqual(english, chinese)
        for option in options {
            XCTAssertTrue(english.contains(option), "missing from English help: \(option)")
            XCTAssertTrue(chinese.contains(option), "missing from Chinese help: \(option)")
        }
        for variable in [
            "RBW_PROFILE", "PINENTRY_RBW_SERVICE", "PINENTRY_RBW_ACCOUNT",
            "PINENTRY_RBW_LOG", "PINENTRY_RBW_LOCALE",
        ] {
            XCTAssertTrue(english.contains(variable), "missing from English help: \(variable)")
            XCTAssertTrue(chinese.contains(variable), "missing from Chinese help: \(variable)")
        }
    }
}
