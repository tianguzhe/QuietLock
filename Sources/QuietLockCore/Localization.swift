import Foundation

/// The UI ships English and Simplified Chinese only; Info.plist and the app name stay English.
///
/// The language follows the user's preferred languages with Apple's localization matching.
/// Any other preference, including Traditional Chinese, falls back to English.
public enum AppLanguage: Equatable, Sendable {
    case english, simplifiedChinese

    public static var current: AppLanguage { resolve(Locale.preferredLanguages) }

    static func resolve(_ preferredLanguages: [String]) -> AppLanguage {
        let match = Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferredLanguages)
        return match.first == "zh-Hans" ? .simplifiedChinese : .english
    }
}

/// Returns the English or Simplified Chinese text for `language`, the current language by default.
/// Both versions stay side by side at the call site so they are edited together.
public func localized(_ english: String, _ chinese: String, in language: AppLanguage = .current) -> String {
    language == .simplifiedChinese ? chinese : english
}
