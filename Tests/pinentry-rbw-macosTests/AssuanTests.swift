import Testing

@testable import pinentry_rbw_macos

// MARK: - encodeAssuan

@Suite("encodeAssuan")
struct EncodeAssuanTests {
    @Test func encodesNewline() {
        #expect(encodeAssuan("a\nb") == "a%0Ab")
    }

    @Test func encodesCarriageReturn() {
        #expect(encodeAssuan("a\rb") == "a%0Db")
    }

    @Test func encodesPercent() {
        #expect(encodeAssuan("100%") == "100%25")
    }

    @Test func leavesPlainTextUnchanged() {
        #expect(encodeAssuan("hello world!") == "hello world!")
    }

    @Test func handlesEmpty() {
        #expect(encodeAssuan("") == "")
    }

    @Test func encodesAllSpecialsTogether() {
        #expect(encodeAssuan("%\n\r") == "%25%0A%0D")
    }
}

// MARK: - decodeAssuan

@Suite("decodeAssuan")
struct DecodeAssuanTests {
    @Test func decodesNewline() {
        #expect(decodeAssuan("a%0Ab") == "a\nb")
    }

    @Test func decodesCarriageReturn() {
        #expect(decodeAssuan("a%0Db") == "a\rb")
    }

    @Test func decodesPercent() {
        #expect(decodeAssuan("100%25") == "100%")
    }

    @Test func decodesLowercaseHex() {
        #expect(decodeAssuan("a%0ab") == "a\nb")
    }

    @Test func leavesPlainTextUnchanged() {
        #expect(decodeAssuan("hello world!") == "hello world!")
    }

    @Test func handlesEmpty() {
        #expect(decodeAssuan("") == "")
    }

    @Test func ignoresTruncatedEscape() {
        // %X with only one hex digit — treated as literal
        #expect(decodeAssuan("%2") == "%2")
    }

    @Test func ignoresNonHexEscape() {
        #expect(decodeAssuan("%ZZ") == "%ZZ")
    }
}

// MARK: - roundtrip

@Suite("Assuan roundtrip")
struct AssuanRoundtripTests {
    @Test func roundtripArbitraryString() {
        let original = "Master password: P@ss\nw0rd\r100%"
        #expect(decodeAssuan(encodeAssuan(original)) == original)
    }

    @Test func roundtripUnicode() {
        let original = "密码：Test123！"
        #expect(decodeAssuan(encodeAssuan(original)) == original)
    }
}
