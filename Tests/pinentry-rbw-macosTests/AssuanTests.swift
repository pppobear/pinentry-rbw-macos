import XCTest

@testable import pinentry_rbw_macos

final class EncodeAssuanTests: XCTestCase {
    func testEncodesNewline() {
        XCTAssertEqual(encodeAssuan("a\nb"), "a%0Ab")
    }

    func testEncodesCarriageReturn() {
        XCTAssertEqual(encodeAssuan("a\rb"), "a%0Db")
    }

    func testEncodesPercent() {
        XCTAssertEqual(encodeAssuan("100%"), "100%25")
    }

    func testLeavesPlainTextUnchanged() {
        XCTAssertEqual(encodeAssuan("hello world!"), "hello world!")
    }

    func testHandlesEmpty() {
        XCTAssertEqual(encodeAssuan(""), "")
    }

    func testEncodesAllSpecialsTogether() {
        XCTAssertEqual(encodeAssuan("%\n\r"), "%25%0A%0D")
    }
}

final class DecodeAssuanTests: XCTestCase {
    func testDecodesNewline() {
        XCTAssertEqual(decodeAssuan("a%0Ab"), "a\nb")
    }

    func testDecodesCarriageReturn() {
        XCTAssertEqual(decodeAssuan("a%0Db"), "a\rb")
    }

    func testDecodesPercent() {
        XCTAssertEqual(decodeAssuan("100%25"), "100%")
    }

    func testDecodesLowercaseHex() {
        XCTAssertEqual(decodeAssuan("a%0ab"), "a\nb")
    }

    func testLeavesPlainTextUnchanged() {
        XCTAssertEqual(decodeAssuan("hello world!"), "hello world!")
    }

    func testHandlesEmpty() {
        XCTAssertEqual(decodeAssuan(""), "")
    }

    func testIgnoresTruncatedEscape() {
        XCTAssertEqual(decodeAssuan("%2"), "%2")
    }

    func testIgnoresNonHexEscape() {
        XCTAssertEqual(decodeAssuan("%ZZ"), "%ZZ")
    }
}

final class AssuanRoundtripTests: XCTestCase {
    func testRoundtripArbitraryString() {
        let original = "Master password: P@ss\nw0rd\r100%"
        XCTAssertEqual(decodeAssuan(encodeAssuan(original)), original)
    }

    func testRoundtripUnicode() {
        let original = "密码：Test123！"
        XCTAssertEqual(decodeAssuan(encodeAssuan(original)), original)
    }
}
