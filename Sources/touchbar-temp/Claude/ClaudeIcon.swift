import AppKit

/// The little pixel-art robot used by Claude Code desk displays, drawn in code on a 15x13 grid.
/// An approximation of the common mascot, not an official asset.
enum ClaudeIcon {
    static var orange: NSColor { Palette.clay }

    // Grid (columns x rows): body, arms, eyes (holes) and four legs.
    private static let body = (cols: 2...12, rows: 0...9)
    private static let arms: [ClosedRange<Int>] = [0...1, 13...14]
    private static let armRows = 3...6
    private static let eyeCols = [4, 10]
    private static let eyeRows = 2...3
    private static let legCols = [2, 5, 9, 12]
    private static let legRows = 10...12

    /// `unit` is the size of one pixel in points; the image is 15 x 13 units.
    static func image(unit: CGFloat = 2, color: NSColor = Palette.clay) -> NSImage {
        NSImage(size: NSSize(width: 15 * unit, height: 13 * unit), flipped: true) { _ in
            func fill(_ cols: ClosedRange<Int>, _ rows: ClosedRange<Int>) {
                NSRect(x: CGFloat(cols.lowerBound) * unit, y: CGFloat(rows.lowerBound) * unit,
                       width: CGFloat(cols.count) * unit, height: CGFloat(rows.count) * unit).fill()
            }
            color.setFill()
            fill(body.cols, body.rows)
            for a in arms { fill(a, armRows) }
            for c in legCols { fill(c...c, legRows) }
            NSColor.black.setFill()                       // the eyes
            for c in eyeCols { fill(c...c, eyeRows) }
            return true
        }
    }
}
