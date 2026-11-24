import AppKit

/// Second Control Strip item, independent from the Mac metrics one. Minimised, it is only the pixel robot.
/// Tapped, it opens a bar in Claude's colours: session and weekly limits with reset times, tokens, activity and
/// service status. When the mode is off or hidden, the item is removed completely.
final class ClaudeTouchBarController: NSObject, NSTouchBarDelegate {

    private enum Slot: String, CaseIterable {
        case icon, session, weekly, credits, today, now, status
    }

    private static let stripID = NSTouchBarItem.Identifier("com.touchbar-temp.claude.strip")
    private static let closeID = NSTouchBarItem.Identifier("com.touchbar-temp.claude.close")
    private static func id(_ s: Slot) -> NSTouchBarItem.Identifier { .init("com.touchbar-temp.claude.\(s.rawValue)") }

    private let engine: ClaudeEngine
    private let settings = Settings.shared

    private var stripItem: NSCustomTouchBarItem?
    private var bar: NSTouchBar?
    private var items: [NSTouchBarItem.Identifier: NSCustomTouchBarItem] = [:]
    private var views: [Slot: WidgetView] = [:]
    private var isPresented = false

    init(engine: ClaudeEngine) {
        self.engine = engine
        super.init()
    }

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(sync), name: Settings.didChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(render), name: ClaudeEngine.didUpdate, object: nil)
        sync()
    }

    /// Starts or stops the engine and adds or removes the strip item to match the settings.
    @objc private func sync() {
        if settings.claudeEnabled {
            engine.start()
            engine.refresh()
        } else {
            engine.stop()
        }
        if settings.claudeVisible {
            if stripItem == nil { register() }
            PrivateTouchBar.setControlStripPresence(Self.stripID, true)
            render()
        } else {
            unregister()
        }
    }

    private func register() {
        let item = NSCustomTouchBarItem(identifier: Self.stripID)
        item.customizationLabel = "Tato Claude"
        // Minimised: just the robot, no numbers.
        let button = NSButton(title: "", target: self, action: #selector(stripTapped))
        button.isBordered = false
        button.image = ClaudeIcon.image(unit: 2)
        button.imagePosition = .imageOnly
        item.view = button
        stripItem = item
        PrivateTouchBar.addSystemTrayItem(item)
    }

    /// Takes the item off the Control Strip entirely, so nothing of the Claude mode remains visible.
    private func unregister() {
        if isPresented, let bar { PrivateTouchBar.minimize(bar); isPresented = false }
        guard let item = stripItem else { return }
        PrivateTouchBar.setControlStripPresence(Self.stripID, false)
        PrivateTouchBar.removeSystemTrayItem(item)
        stripItem = nil
        bar = nil
        items.removeAll()
        views.removeAll()
    }

    // MARK: - Bar

    @objc private func stripTapped() {
        if isPresented { closeTapped(); return }
        // Built on every open so the credits widget only exists when the account has extra usage enabled.
        items.removeAll(); views.removeAll()
        let b = NSTouchBar()
        b.delegate = self
        b.defaultItemIdentifiers = slots().map(Self.id) + [Self.closeID]
        bar = b
        PrivateTouchBar.present(b, trayItem: Self.stripID)
        isPresented = true
        render()
    }

    private func slots() -> [Slot] {
        Slot.allCases.filter { $0 != .credits || engine.snapshot.limits?.credits != nil }
    }

    @objc private func closeTapped() {
        if let bar { PrivateTouchBar.minimize(bar) }
        isPresented = false
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if let existing = items[identifier] { return existing }
        let item = NSCustomTouchBarItem(identifier: identifier)
        if identifier == Self.closeID {
            let b = NSButton(title: "✕", target: self, action: #selector(closeTapped))
            b.bezelColor = NSColor(white: 0.25, alpha: 1)
            item.view = b
        } else if let slot = Slot.allCases.first(where: { Self.id($0) == identifier }) {
            if slot == .icon {
                let v = NSImageView(image: ClaudeIcon.image(unit: 2))
                v.widthAnchor.constraint(equalToConstant: 34).isActive = true
                item.view = v
            } else {
                let v = WidgetView()
                v.title = Self.title(slot)
                v.titleColor = Palette.kraft
                v.valueColor = Palette.cream
                v.barColor = Palette.clay
                switch slot {
                case .session, .weekly: v.preferredWidth = 150; v.fraction = 0
                case .credits: v.preferredWidth = 108; v.fraction = 0
                case .today: v.preferredWidth = 76
                case .now, .status: v.preferredWidth = 72
                default: break
                }
                views[slot] = v
                item.view = v
            }
        } else {
            return nil
        }
        items[identifier] = item
        return item
    }

    private static func title(_ s: Slot) -> String {
        switch s {
        case .icon: return ""
        case .session: return tr("SESSÃO 5H", "SESSION 5H")
        case .weekly: return tr("SEMANAL 7D", "WEEKLY 7D")
        case .credits: return tr("CRÉDITO", "CREDIT")
        case .today: return tr("HOJE", "TODAY")
        case .now: return tr("AGORA", "NOW")
        case .status: return tr("SERVIÇO", "SERVICE")
        }
    }

    // MARK: - Rendering

    private func statusColor(_ s: ClaudeServiceStatus) -> NSColor {
        switch s {
        case .operational: return Palette.ok
        case .degraded: return Palette.warn
        case .outage: return Palette.bad
        case .unknown: return Palette.muted
        }
    }

    @objc private func render() {
        guard settings.claudeVisible else { return }
        renderValues()
    }

    private func renderValues() {
        let snap = engine.snapshot
        let u = snap.usage

        func set(_ slot: Slot, _ text: String, _ color: NSColor = Palette.cream, fraction: Double? = nil,
                 barColor: NSColor = Palette.clay, title: String? = nil) {
            guard let v = views[slot] else { return }
            v.valueText = text
            v.valueColor = color
            v.barColor = barColor
            if let f = fraction { v.fraction = f }
            if let t = title { v.title = t }
        }
        func limit(_ slot: Slot, _ name: String, _ pct: Double?, _ resets: Date?) {
            let reset = ClaudeFormat2.reset(resets).map { " · \($0)" } ?? ""
            if let pct {
                set(slot, String(format: "%.0f%%", pct), Palette.cream, fraction: min(max(pct / 100, 0), 1),
                    barColor: Palette.claudeLimit(pct), title: name + reset)
            } else {
                set(slot, "–", Palette.cream, fraction: 0, title: name)
            }
        }
        limit(.session, tr("SESSÃO 5H", "SESSION 5H"), snap.limits?.sessionPct, snap.limits?.sessionResets)
        limit(.weekly, tr("SEMANAL 7D", "WEEKLY 7D"), snap.limits?.weeklyPct, snap.limits?.weeklyResets)
        if let c = snap.limits?.credits {
            set(.credits, c.used, Palette.cream, fraction: min(max(c.pct / 100, 0), 1), barColor: Palette.claudeLimit(c.pct),
                title: tr("CRÉDITO", "CREDIT"))
        }
        set(.today, snap.loaded ? ClaudeFormat.tokens(u.tokensToday) : "–")
        set(.now, snap.isActive ? tr("ATIVO", "ACTIVE") : tr("OCIOSO", "IDLE"), snap.isActive ? Palette.clay : Palette.muted)
        set(.status, snap.status.label, statusColor(snap.status))
    }

    /// Debug: the expanded bar laid out in a row on black, for screenshots.
    func debugPreview() -> NSView {
        var arranged: [NSView] = []
        for identifier in slots().map(Self.id) + [Self.closeID] {
            if let item = touchBar(NSTouchBar(), makeItemForIdentifier: identifier) as? NSCustomTouchBarItem {
                arranged.append(item.view)
            }
        }
        renderValues()
        let stack = NSStackView(views: arranged)
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        container.layoutSubtreeIfNeeded()
        let size = stack.fittingSize
        container.frame = NSRect(x: 0, y: 0, width: size.width + 24, height: 40)
        container.layoutSubtreeIfNeeded()
        return container
    }
}
