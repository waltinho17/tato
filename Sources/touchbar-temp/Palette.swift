import AppKit

/// One palette for the whole app: warm graphite and cream with Claude's clay orange as the accent,
/// and the same three status colours everywhere (Touch Bar, menu, Preferences).
enum Palette {
    private static func rgb(_ h: UInt32, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
    }

    // Claude's own colours
    static let clay = rgb(0xD97757)        // Claude orange
    static let kraft = rgb(0xD4A27F)       // secondary warm tone
    static let cream = rgb(0xF0EEE6)       // ivory text
    static let ink = rgb(0x1F1E1D)         // warm near-black
    static let muted = rgb(0xA8A29A)       // quiet labels

    // Status colours
    static let ok = rgb(0x5FBF7A)
    static let warn = rgb(0xF0A53C)
    static let bad = rgb(0xE5584A)

    /// Claude limits stay in the Claude orange until they get close to the cap.
    static func claudeLimit(_ pct: Double) -> NSColor { pct >= 90 ? bad : clay }
}
