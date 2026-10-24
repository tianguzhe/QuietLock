import XCTest
@testable import QuietLockCore

final class LocalizationTests: XCTestCase {
    func testSimplifiedChinesePreferenceShowsChinese() {
        XCTAssertEqual(AppLanguage.resolve(["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.resolve(["zh-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.resolve(["ja-JP", "zh-Hans-CN"]), .simplifiedChinese)
    }

    func testEverythingElseFallsBackToEnglish() {
        for preferences in [["en-US"], ["en-US", "zh-Hans-US"], ["de-DE"], ["zh-Hant-TW"], []] {
            XCTAssertEqual(AppLanguage.resolve(preferences), .english, "\(preferences)")
        }
    }

    func testLocalizedPicksTextForLanguage() {
        XCTAssertEqual(localized("Retry", "重试", in: .english), "Retry")
        XCTAssertEqual(localized("Retry", "重试", in: .simplifiedChinese), "重试")
    }
}
