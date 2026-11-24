import AppKit

struct DashRow {
    enum Style { case normal, processHeader, process }
    var style: Style = .normal
    var title: String
    var value: String
    var color: NSColor = .labelColor
    var fraction: Double?
    var stats: [(String, String)]?        // (label, value) pairs shown under the row
    var spark: [Double]?                  // recent history, drawn between title and value
    var right: (String, String)?          // second column (process rows)
}

struct DashSection {
    var title: String
    var rows: [DashRow]
}

/// Card-style readout shown at the top of the menu: values, bars, history sparklines and min/avg/max.
final class DashboardView: NSView {
    static let width: CGFloat = 340

    var sections: [DashSection] = [] {
        didSet {
            setFrameSize(NSSize(width: Self.width, height: totalHeight))
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    init() { super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 10)) }
    required init?(coder: NSCoder) { fatalError() }

    private func rowHeight(_ r: DashRow) -> CGFloat {
        switch r.style {
        case .processHeader: return 16
        case .process: return 18
        case .normal: return 20 + (r.fraction != nil ? 8 : 0) + (r.stats != nil ? 15 : 0) + 4
        }
    }
    private func sectionHeight(_ s: DashSection) -> CGFloat { 28 + s.rows.reduce(0) { $0 + rowHeight($1) } + 4 }
    private var totalHeight: CGFloat { 8 + sections.reduce(0) { $0 + sectionHeight($1) + 8 } }

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    @discardableResult
    private func text(_ s: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor,
                      alignRight: Bool = false, maxWidth: CGFloat? = nil) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let str = NSString(string: s)
        let full = str.size(withAttributes: attrs).width
        let w = min(full, maxWidth ?? full)
        let origin = alignRight ? x - w : x
        str.draw(in: NSRect(x: origin, y: y, width: w + 1, height: 18), withAttributes: attrs)
        return w
    }

    private func drawSpark(_ values: [Double], in rect: NSRect, color: NSColor) {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return }
        let span = max(hi - lo, 0.0001)
        let path = NSBezierPath()
        for (i, v) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1)
            let y = rect.maxY - rect.height * CGFloat((v - lo) / span)
            i == 0 ? path.move(to: NSPoint(x: x, y: y)) : path.line(to: NSPoint(x: x, y: y))
        }
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        color.withAlphaComponent(0.9).setStroke()
        path.stroke()
    }

    override func draw(_ dirtyRect: NSRect) {
        var y: CGFloat = 8
        for sec in sections {
            let card = NSRect(x: 10, y: y, width: bounds.width - 20, height: sectionHeight(sec))
            NSColor.labelColor.withAlphaComponent(0.11).setFill()
            NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10).fill()

            let left = card.minX + 12, right = card.maxX - 12, mid = card.midX
            text(sec.title.uppercased(), x: left, y: y + 8,
                 font: .systemFont(ofSize: 11, weight: .bold), color: .secondaryLabelColor)
            var cy = y + 28
            for r in sec.rows {
                switch r.style {
                case .processHeader:
                    let f = NSFont.systemFont(ofSize: 10, weight: .semibold)
                    text(r.title, x: left, y: cy, font: f, color: .secondaryLabelColor)
                    if let rt = r.right { text(rt.0, x: mid + 6, y: cy, font: f, color: .secondaryLabelColor) }
                case .process:
                    let f = NSFont.systemFont(ofSize: 12, weight: .medium)
                    let mono = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
                    let vw = NSString(string: r.value).size(withAttributes: [.font: mono]).width
                    text(r.title, x: left, y: cy, font: f, color: .labelColor, maxWidth: mid - left - vw - 14)
                    text(r.value, x: mid - 8, y: cy, font: mono, color: .labelColor, alignRight: true)
                    if let rt = r.right {
                        let rw = NSString(string: rt.1).size(withAttributes: [.font: mono]).width
                        text(rt.0, x: mid + 6, y: cy, font: f, color: .labelColor, maxWidth: right - mid - 6 - rw - 8)
                        text(rt.1, x: right, y: cy, font: mono, color: .labelColor, alignRight: true)
                    }
                case .normal:
                    let tw = text(r.title, x: left, y: cy, font: Self.titleFont, color: .labelColor)
                    let vw = text(r.value, x: right, y: cy, font: Self.valueFont, color: r.color, alignRight: true)
                    if let s = r.spark {
                        let x0 = left + tw + 12, x1 = right - vw - 12
                        if x1 - x0 >= 40 {
                            drawSpark(s, in: NSRect(x: x0, y: cy + 3, width: min(x1 - x0, 110), height: 11), color: r.color)
                        }
                    }
                    var next = cy + 20
                    if let f = r.fraction {
                        let track = NSRect(x: left, y: cy + 19, width: right - left, height: 5)
                        NSColor.labelColor.withAlphaComponent(0.25).setFill()
                        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
                        var fill = track
                        fill.size.width = max(track.height, track.width * CGFloat(f))
                        r.color.setFill()
                        NSBezierPath(roundedRect: fill, xRadius: 2.5, yRadius: 2.5).fill()
                        next += 8
                    }
                    if let st = r.stats {
                        let a = NSMutableAttributedString()
                        let key: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
                        let val: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.labelColor]
                        for (i, (k, v)) in st.enumerated() {
                            if i > 0 { a.append(NSAttributedString(string: "    ", attributes: key)) }
                            a.append(NSAttributedString(string: k + " ", attributes: key))
                            a.append(NSAttributedString(string: v, attributes: val))
                        }
                        a.draw(at: NSPoint(x: left, y: next))
                    }
                }
                cy += rowHeight(r)
            }
            y += card.height + 8
        }
    }
}

/// Builds the dashboard content from the engine's current readings.
enum DashboardModel {
    static func sections(engine: MetricsEngine, useColors: Bool, claude: ClaudeSnapshot? = nil) -> [DashSection] {
        let sup = Set(engine.supported)
        let snap = engine.snapshot

        func stats(_ id: MetricID) -> [(String, String)]? {
            guard sup.contains(id) else { return nil }
            guard let st = engine.stats[id], st.count > 1 else { return [("mín", "–"), ("méd", "–"), ("máx", "–")] }
            return [("mín", MetricStyle.number(id, st.min)), ("méd", MetricStyle.number(id, st.avg)), ("máx", MetricStyle.number(id, st.max))]
        }
        func tint(_ id: MetricID) -> NSColor { useColors ? MetricStyle.color(id, snap[id]) : .labelColor }
        func shown(_ id: MetricID) -> String? { sup.contains(id) ? MetricStyle.text(snap[id]) : nil }
        func spark(_ id: MetricID) -> [Double]? { engine.history[id].flatMap { $0.count > 3 ? $0 : nil } }
        func pct(_ x: Double?) -> String { x.map { String(format: "%.0f%%", $0) } ?? "–" }

        // CPU, GPU, cooler
        var processor: [DashRow] = []
        for (title, temp, freq) in [("CPU", MetricID.cpuTemp, MetricID.cpuFreq), ("GPU", .gpuTemp, .gpuFreq)] {
            let parts = [shown(temp), shown(freq)].compactMap { $0 }
            guard !parts.isEmpty else { continue }
            processor.append(DashRow(title: title, value: parts.joined(separator: " · "),
                                     color: sup.contains(temp) ? tint(temp) : .labelColor,
                                     stats: stats(temp), spark: spark(temp)))
        }
        if sup.contains(.cpuUsage) {
            var st: [(String, String)]?
            if let e = engine.cpuUsage.efficiencyUsage, let p = engine.cpuUsage.performanceUsage {
                st = [("núcleos E", pct(e)), ("núcleos P", pct(p))]
            }
            processor.append(DashRow(title: "Uso da CPU", value: MetricStyle.text(snap[.cpuUsage]), color: tint(.cpuUsage),
                                     fraction: MetricStyle.fraction(snap[.cpuUsage]), stats: st, spark: spark(.cpuUsage)))
        }
        if sup.contains(.fanRPM) {
            processor.append(DashRow(title: "Cooler", value: MetricStyle.text(snap[.fanRPM]) + " rpm",
                                     stats: stats(.fanRPM), spark: spark(.fanRPM)))
        }

        func usage(_ id: MetricID, _ title: String, detail: Bool, withStats: Bool = true) -> DashRow? {
            guard sup.contains(id) else { return nil }
            let v = snap[id]
            var value = MetricStyle.text(v)
            if detail, case .percent(let u, let t, let unit)? = v {
                value = String(format: "%.1f / %.1f %@ · %@", u, t, unit, value)
            }
            return DashRow(title: title, value: value, color: tint(id), fraction: MetricStyle.fraction(v),
                           stats: withStats ? stats(id) : nil, spark: nil)
        }

        func pair(_ a: MetricID, _ b: MetricID, _ title: String) -> DashRow? {
            guard sup.contains(a) || sup.contains(b) else { return nil }
            return DashRow(title: title, value: "↓ \(MetricStyle.text(snap[a]))  ↑ \(MetricStyle.text(snap[b]))", spark: spark(a))
        }

        var out: [DashSection] = []
        if !processor.isEmpty { out.append(DashSection(title: "CPU, GPU e cooler", rows: processor)) }

        let mem = [usage(.memory, "RAM", detail: true), usage(.memPressure, "Pressão", detail: false, withStats: false)].compactMap { $0 }
        if !mem.isEmpty { out.append(DashSection(title: "Memória", rows: mem)) }

        let io = [pair(.netDown, .netUp, "Rede"), pair(.diskRead, .diskWrite, "Disco (E/S)")].compactMap { $0 }
        if !io.isEmpty { out.append(DashSection(title: "Rede e disco", rows: io)) }

        var storage = [usage(.disk, "SSD", detail: true, withStats: false)].compactMap { $0 }
        if var bat = usage(.battery, "Bateria", detail: false, withStats: false) {
            if let b = engine.system.batteryDetails {
                bat.stats = [("saúde", b.health.map { String(format: "%.0f%%", $0) } ?? "–"),
                             ("ciclos", b.cycles.map(String.init) ?? "–"),
                             ("", b.charging ? "carregando" : (b.pluggedIn ? "na tomada" : "na bateria"))]
            }
            storage.append(bat)
        }
        if !storage.isEmpty { out.append(DashSection(title: "Armazenamento e bateria", rows: storage)) }

        // Claude (only when the Claude mode is on), always in Claude's own colours
        if let c = claude {
            var rows: [DashRow] = []
            func limitRow(_ title: String, _ pct: Double?, _ resets: Date?) {
                guard let pct else { return }
                rows.append(DashRow(title: title, value: String(format: "%.0f%%", pct), color: Palette.claudeLimit(pct),
                                    fraction: min(max(pct / 100, 0), 1),
                                    stats: ClaudeFormat2.reset(resets).map { [("reseta em", $0)] }))
            }
            limitRow("Sessão · 5 horas", c.limits?.sessionPct, c.limits?.sessionResets)
            limitRow("Semanal · 7 dias", c.limits?.weeklyPct, c.limits?.weeklyResets)
            if let origin = c.limits?.breakdown?.filter({ $0.pctOfLimit > 0 }), !origin.isEmpty {
                rows.append(DashRow(title: "Semanal por origem", value: "",
                                    stats: origin.map { ($0.name, String(format: "%.0f%%", $0.pctOfLimit)) }))
            }
            if let cr = c.limits?.credits {
                rows.append(DashRow(title: "Crédito extra · mês", value: "\(cr.used) / \(cr.limit)", color: Palette.claudeLimit(cr.pct),
                                    fraction: min(max(cr.pct / 100, 0), 1), stats: [("usado", String(format: "%.0f%%", cr.pct))]))
            }
            for e in c.limits?.extras ?? [] { limitRow(e.name, e.pct, e.resets) }
            if c.loaded {
                var today = DashRow(title: "Hoje", value: "\(ClaudeFormat.tokens(c.usage.tokensToday)) · \(c.usage.messagesToday) respostas",
                                    color: Palette.cream)
                today.stats = c.usage.modelsToday.prefix(3).map { ($0.name, ClaudeFormat.tokens($0.tokens)) }
                if today.stats?.isEmpty ?? true { today.stats = nil }
                rows.append(today)
                rows.append(DashRow(title: "Tokens", value: "5 h \(ClaudeFormat.tokens(c.usage.tokens5h)) · 7 d \(ClaudeFormat.tokens(c.usage.tokens7d))",
                                    color: Palette.cream,
                                    stats: [("serviço", c.status.label), ("agora", c.isActive ? "ativo" : "ocioso"),
                                            ("última", ClaudeTime.ago(c.usage.lastActivity))]))
            }
            out.append(DashSection(title: "Claude" + (c.plan.map { " · \($0.capitalized)" } ?? ""), rows: rows))
        }

        // Top processes
        let ps = engine.processes
        let byCPU = ps.topCPU(), byMem = ps.topMemory()
        if !byMem.isEmpty {
            var rows = [DashRow(style: .processHeader, title: "POR CPU", value: "", right: ("POR RAM", ""))]
            for i in 0..<min(byCPU.count, byMem.count) {
                let c = byCPU[i], m = byMem[i]
                rows.append(DashRow(style: .process, title: c.name, value: ps.hasCPU ? String(format: "%.0f%%", c.cpu) : "…",
                                    right: (m.name, String(format: "%.1f GB", Double(m.memory) / 1_073_741_824))))
            }
            out.append(DashSection(title: "Processos", rows: rows))
        }
        return out
    }
}
