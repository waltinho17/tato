import Foundation

/// The app speaks Brazilian Portuguese and English. By default it follows the system language
/// (Portuguese for pt, English for everything else); Preferences can force either one.
enum Lang {
    case pt, en

    /// `--lang pt|en` on the command line wins (used for screenshots).
    static var override: Lang?

    static var current: Lang {
        if let o = override { return o }
        switch UserDefaults.standard.string(forKey: "language") {
        case "pt": return .pt
        case "en": return .en
        default: return Locale.preferredLanguages.first?.hasPrefix("pt") == true ? .pt : .en
        }
    }

    static var locale: Locale { Locale(identifier: current == .pt ? "pt_BR" : "en_US") }
}

/// Picks the Portuguese or English text.
func tr(_ pt: String, _ en: String) -> String { Lang.current == .pt ? pt : en }
