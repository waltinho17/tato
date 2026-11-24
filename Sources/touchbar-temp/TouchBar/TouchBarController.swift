import AppKit

/// One scrollable cell of the widget strip.
final class WidgetScrubberItem: NSScrubberItemView {
    let widget = WidgetView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        widget.frame = bounds
        widget.autoresizingMask = [.width, .height]
        addSubview(widget)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// Control Strip item (always visible) that opens a full Touch Bar of widgets when tapped.
/// The widgets live in a scrubber, so any number of them fits: extra ones scroll with a finger swipe.
final class TouchBarController: NSObject, NSTouchBarDelegate, NSScrubberDataSource, NSScrubberFlowLayoutDelegate {

    private static let stripID = NSTouchBarItem.Identifier("com.touchbar-temp.strip")
    private static let closeID = NSTouchBarItem.Identifier("com.touchbar-temp.close")
    private static let widgetsID = NSTouchBarItem.Identifier("com.touchbar-temp.widgets")
    private static let cellID = NSUserInterfaceItemIdentifier("widget")

    /// Space the modal bar leaves for the widget strip (the system close box and our ✕ take the rest).
    private static let maxStripWidth: CGFloat = 690
    private static let spacing: CGFloat = 6

    private let engine: MetricsEngine
    private let settings = Settings.shared

    // Everything the Touch Bar shows must be retained here, or it vanishes.
    private var stripItem: NSCustomTouchBarItem?
    private var stripButton: NSButton?
    private var bar: NSTouchBar?
    private var items: [NSTouchBarItem.Identifier: NSCustomTouchBarItem] = [:]
    private var scrubber: NSScrubber?
    private var shown: [MetricID] = []
    private var latest: [MetricID: MetricValue] = [:]
    private var isPresented = false
    private var lastSupported: [MetricID] = []

    /// Called on every update with (metric, compact text) for the strip widgets; the menu bar formats them.
    var onStrip: (([(MetricID, String)]) -> Void)?

    init(engine: MetricsEngine) {
        self.engine = engine
        super.init()
    }

    private func visible(_ ids: [MetricID]) -> [MetricID] { ids.filter(engine.supported.contains) }

    private func stripIDs() -> [MetricID] {
        let chosen = visible(settings.stripWidgets)
        return chosen.isEmpty ? Array(engine.supported.prefix(Settings.maxStripWidgets)) : chosen
    }

    private static func width(of m: MetricID) -> CGFloat {
        switch m {
        case .disk, .memory, .battery, .cpuUsage, .memPressure: return 96     // bar widgets
        case .diskRead, .diskWrite, .netDown, .netUp: return 104             // "12.3 MB/s"
        case .cpuFreq, .gpuFreq: return 92                                   // "3.20 GHz"
        default: return 78
        }
    }

    // MARK: - Lifecycle

    func start() {
        NSLog("TouchBarTemp: private DFR functions available = %d", PrivateTouchBar.functionsAvailable ? 1 : 0)
        PrivateTouchBar.setShowsCloseBox(false)

        let item = NSCustomTouchBarItem(identifier: Self.stripID)
        item.customizationLabel = "Tato"
        let button = NSButton(title: "…", target: self, action: #selector(stripTapped))
        button.isBordered = false
        button.font = heavyRoundedFont(size: 15)
        item.view = button
        stripItem = item
        stripButton = button

        PrivateTouchBar.addSystemTrayItem(item)
        PrivateTouchBar.setControlStripPresence(Self.stripID, settings.macVisible)

        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: Settings.didChange, object: nil)
        engine.onUpdate = { [weak self] snap in self?.apply(snap) }
        applySettings()
        engine.start()
    }

    // MARK: - Settings

    @objc private func settingsChanged() {
        PrivateTouchBar.setControlStripPresence(Self.stripID, settings.macVisible)
        if !settings.macVisible, isPresented { dismissBar() }
        applySettings()
        rebuildBar()
        apply(engine.snapshot)
    }

    private func applySettings() {
        engine.enabled = Set(MetricID.allCases)   // the menu lists every metric, so always read all
        if engine.interval != settings.refreshInterval { engine.interval = settings.refreshInterval }
    }

    // MARK: - Bar

    @objc private func stripTapped() {
        if isPresented { dismissBar() } else { presentBar() }
    }

    private func presentBar() {
        if bar == nil { rebuildBar() }
        guard let bar else { return }
        PrivateTouchBar.present(bar, trayItem: Self.stripID)
        isPresented = true
        apply(engine.snapshot)
    }

    private func dismissBar() {
        if let bar { PrivateTouchBar.minimize(bar) }
        isPresented = false
    }

    @objc private func closeTapped() { dismissBar() }

    private func rebuildBar() {
        let wasPresented = isPresented
        if wasPresented { dismissBar() }
        items.removeAll()
        scrubber = nil
        shown = visible(settings.enabledWidgets)

        let b = NSTouchBar()
        b.delegate = self
        b.defaultItemIdentifiers = shown.isEmpty ? [Self.closeID] : [Self.widgetsID, Self.closeID]
        bar = b
        if wasPresented { presentBar() }
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        if let existing = items[identifier] { return existing }
        let item = NSCustomTouchBarItem(identifier: identifier)

        switch identifier {
        case Self.closeID:
            let b = NSButton(title: "✕", target: self, action: #selector(closeTapped))
            b.bezelColor = NSColor(white: 0.25, alpha: 1)
            item.view = b
        case Self.widgetsID:
            let s = NSScrubber()
            let layout = NSScrubberFlowLayout()
            layout.itemSpacing = Self.spacing
            s.scrubberLayout = layout
            s.register(WidgetScrubberItem.self, forItemIdentifier: Self.cellID)
            s.mode = .free
            s.isContinuous = false
            s.showsAdditionalContentIndicators = true
            s.dataSource = self
            s.delegate = self
            s.translatesAutoresizingMaskIntoConstraints = false
            let content = shown.reduce(0) { $0 + Self.width(of: $1) } + Self.spacing * CGFloat(max(shown.count - 1, 0))
            s.widthAnchor.constraint(equalToConstant: min(content, Self.maxStripWidth)).isActive = true
            s.heightAnchor.constraint(equalToConstant: 30).isActive = true
            scrubber = s
            item.view = s
        default:
            return nil
        }
        items[identifier] = item
        return item
    }

    // MARK: - Scrubber

    func numberOfItems(for scrubber: NSScrubber) -> Int { shown.count }

    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let cell = scrubber.makeItem(withIdentifier: Self.cellID, owner: nil) as? WidgetScrubberItem ?? WidgetScrubberItem()
        configure(cell, shown[index])
        return cell
    }

    func scrubber(_ scrubber: NSScrubber, layout: NSScrubberFlowLayout, sizeForItemAt itemIndex: Int) -> NSSize {
        NSSize(width: Self.width(of: shown[itemIndex]), height: 30)
    }

    private func configure(_ cell: WidgetScrubberItem, _ metric: MetricID) {
        let v = latest[metric]
        cell.widget.title = MetricStyle.label(metric)
        cell.widget.valueText = MetricStyle.text(v)
        cell.widget.fraction = MetricStyle.fraction(v)
        cell.widget.valueColor = settings.useColors ? MetricStyle.color(metric, v) : .white
    }

    /// Debug: the expanded bar laid out in a row on black, for screenshots.
    func debugPreview() -> NSView {
        shown = visible(settings.enabledWidgets)
        latest = engine.snapshot
        var cells: [NSView] = []
        for m in shown {
            let w = Self.width(of: m)
            let cell = WidgetScrubberItem(frame: NSRect(x: 0, y: 0, width: w, height: 30))
            configure(cell, m)
            cell.translatesAutoresizingMaskIntoConstraints = false
            cell.widthAnchor.constraint(equalToConstant: w).isActive = true
            cell.heightAnchor.constraint(equalToConstant: 30).isActive = true
            cells.append(cell)
        }
        let close = NSButton(title: "✕", target: nil, action: nil)
        close.bezelColor = NSColor(white: 0.25, alpha: 1)
        cells.append(close)
        let stack = NSStackView(views: cells)
        stack.orientation = .horizontal
        stack.spacing = Self.spacing
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        container.layoutSubtreeIfNeeded()
        container.frame = NSRect(x: 0, y: 0, width: stack.fittingSize.width + 24, height: 40)
        container.layoutSubtreeIfNeeded()
        return container
    }

    // MARK: - Updates

    private func apply(_ snap: [MetricID: MetricValue]) {
        if engine.supported != lastSupported {          // e.g. a sensor this Mac does not have
            lastSupported = engine.supported
            rebuildBar()
        }
        latest = snap
        for (i, metric) in shown.enumerated() {          // update visible cells in place (keeps the scroll position)
            if let cell = scrubber?.itemViewForItem(at: i) as? WidgetScrubberItem { configure(cell, metric) }
        }

        let ids = stripIDs()
        let text = ids.map { MetricStyle.compact(snap[$0]) }.joined(separator: " · ")
        stripButton?.title = text.isEmpty ? "TBT" : text
        if let first = ids.first, settings.useColors {
            stripButton?.contentTintColor = MetricStyle.color(first, snap[first])
        } else {
            stripButton?.contentTintColor = .white
        }
        onStrip?(ids.map { ($0, MetricStyle.compact(snap[$0])) })
    }
}
