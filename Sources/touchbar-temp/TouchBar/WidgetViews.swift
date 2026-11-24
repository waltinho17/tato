import AppKit

func heavyRoundedFont(size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .heavy)
    guard let desc = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: desc, size: size) ?? base
}

/// Formatting and colour rules shared by the Touch Bar, strip item and menu bar.
enum MetricStyle {
    static func label(_ id: MetricID) -> String {
        switch id {
        case .cpuTemp: return "CPU"
        case .gpuTemp: return "GPU"
        case .fanRPM: return "FAN"
        case .cpuFreq: return "CPU CLK"
        case .gpuFreq: return "GPU CLK"
        case .disk: return "SSD"
        case .memory: return "RAM"
        case .battery: return "BAT"
        case .cpuUsage: return "CPU %"
        case .memPressure: return "PRESSÃO"
        case .diskRead: return "DISK ↓"
        case .diskWrite: return "DISK ↑"
        case .netDown: return "NET ↓"
        case .netUp: return "NET ↑"
        }
    }

    static func menuName(_ id: MetricID) -> String {
        switch id {
        case .cpuTemp: return "Temperatura da CPU"
        case .gpuTemp: return "Temperatura da GPU"
        case .fanRPM: return "Rotação do cooler"
        case .cpuFreq: return "Frequência da CPU"
        case .gpuFreq: return "Frequência da GPU"
        case .disk: return "Armazenamento"
        case .memory: return "Memória"
        case .battery: return "Bateria"
        case .cpuUsage: return "Uso da CPU"
        case .memPressure: return "Pressão de memória"
        case .diskRead: return "Disco: leitura"
        case .diskWrite: return "Disco: escrita"
        case .netDown: return "Rede: download"
        case .netUp: return "Rede: upload"
        }
    }

    static func rate(_ b: Double) -> String {
        if b >= 1e9 { return String(format: "%.1f GB/s", b / 1e9) }
        if b >= 1e6 { return String(format: "%.1f MB/s", b / 1e6) }
        if b >= 1e3 { return String(format: "%.0f KB/s", b / 1e3) }
        return String(format: "%.0f B/s", b)
    }

    /// Full text used in the expanded Touch Bar.
    static func text(_ v: MetricValue?) -> String {
        switch v {
        case .temperature(let t)?: return String(format: "%.0f°", t)
        case .rpm(let r)?: return String(format: "%.0f", r)
        case .mhz(let m)?: return m >= 1000 ? String(format: "%.2f GHz", m / 1000) : String(format: "%.0f MHz", m)
        case .rate(let r)?: return rate(r)
        case .percent(let u, let t, _)?: return t > 0 ? String(format: "%.0f%%", u / t * 100) : "–"
        default: return "–"
        }
    }

    /// Short text for the Control Strip item and menu bar.
    static func compact(_ v: MetricValue?) -> String {
        switch v {
        case .temperature(let t)?: return String(format: "%.0f°", t)
        case .rpm(let r)?: return r >= 1000 ? String(format: "%.1fk", r / 1000) : String(format: "%.0f", r)
        case .mhz(let m)?: return m >= 1000 ? String(format: "%.1fG", m / 1000) : String(format: "%.0fM", m)
        case .rate(let r)?: return r >= 1e6 ? String(format: "%.1fM", r / 1e6) : String(format: "%.0fK", r / 1e3)
        case .percent(let u, let t, _)?: return t > 0 ? String(format: "%.0f%%", u / t * 100) : "–"
        default: return "–"
        }
    }

    /// Number formatted the way `compact`/`text` would show a value of this metric.
    static func number(_ id: MetricID, _ x: Double) -> String {
        switch id {
        case .cpuTemp, .gpuTemp: return String(format: "%.0f°", x)
        case .fanRPM: return String(format: "%.0f rpm", x)
        case .diskRead, .diskWrite, .netDown, .netUp: return rate(x)
        case .cpuFreq, .gpuFreq: return x >= 1000 ? String(format: "%.2f GHz", x / 1000) : String(format: "%.0f MHz", x)
        default: return String(format: "%.0f%%", x)
        }
    }

    static func fraction(_ v: MetricValue?) -> Double? {
        if case .percent(let u, let t, _)? = v, t > 0 { return min(max(u / t, 0), 1) }
        return nil
    }

    // Green < 70 · Orange < 85/90 · Red above. Battery is inverted (low is bad).
    static func color(_ id: MetricID, _ v: MetricValue?) -> NSColor {
        switch v {
        case .temperature(let t)?:
            return t < 70 ? Palette.ok : (t < 85 ? Palette.warn : Palette.bad)
        case .percent(let u, let t, _)? where t > 0:
            let p = u / t * 100
            if id == .battery { return p > 30 ? Palette.ok : (p > 15 ? Palette.warn : Palette.bad) }
            return p < 70 ? Palette.ok : (p < 90 ? Palette.warn : Palette.bad)
        default:
            return .white
        }
    }
}

/// Small label over a big value; widgets with a fraction also draw a progress bar.
final class WidgetView: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var valueText = "–" { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    var valueColor: NSColor = .white { didSet { needsDisplay = true } }
    var preferredWidth: CGFloat?
    var titleColor = NSColor(white: 1, alpha: 0.55) { didSet { needsDisplay = true } }
    var barColor: NSColor? { didSet { needsDisplay = true } }
    var fraction: Double? { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        if let w = preferredWidth { return NSSize(width: w, height: 30) }
        if fraction != nil { return NSSize(width: 96, height: 30) }
        let w = NSString(string: valueText).size(withAttributes: [.font: heavyRoundedFont(size: 16)]).width
        return NSSize(width: max(78, ceil(w) + 14), height: 30)
    }

    override func draw(_ dirtyRect: NSRect) {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: titleColor
        ]
        if let f = fraction {
            let valAttrs: [NSAttributedString.Key: Any] = [.font: heavyRoundedFont(size: 11), .foregroundColor: valueColor]
            NSString(string: title).draw(at: NSPoint(x: 2, y: 1), withAttributes: titleAttrs)
            let vs = NSString(string: valueText).size(withAttributes: valAttrs)
            NSString(string: valueText).draw(at: NSPoint(x: bounds.width - vs.width - 2, y: 0), withAttributes: valAttrs)
            let track = NSRect(x: 2, y: 19, width: bounds.width - 4, height: 7)
            NSColor(white: 1, alpha: 0.18).setFill()
            NSBezierPath(roundedRect: track, xRadius: 3.5, yRadius: 3.5).fill()
            var fill = track
            fill.size.width = max(track.height, track.width * f)
            (barColor ?? valueColor).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 3.5, yRadius: 3.5).fill()
        } else {
            let valAttrs: [NSAttributedString.Key: Any] = [.font: heavyRoundedFont(size: 16), .foregroundColor: valueColor]
            let ts = NSString(string: title).size(withAttributes: titleAttrs)
            let vs = NSString(string: valueText).size(withAttributes: valAttrs)
            NSString(string: title).draw(at: NSPoint(x: (bounds.width - ts.width) / 2, y: 1), withAttributes: titleAttrs)
            NSString(string: valueText).draw(at: NSPoint(x: (bounds.width - vs.width) / 2, y: 11), withAttributes: valAttrs)
        }
    }
}
