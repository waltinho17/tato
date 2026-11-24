import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private let engine = MetricsEngine()
    private lazy var touchBar = TouchBarController(engine: engine)
    private let settings = Settings.shared
    private let dashboard = DashboardView()
    private let alerts = AlertManager()
    private let claude = ClaudeEngine()
    private lazy var claudeBar = ClaudeTouchBarController(engine: claude)
    private let preferences = PreferencesWindowController()
    private var menuOpen = false
    private var lastStrip: [(MetricID, String)] = []
    private var osChanged = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        ClaudeEngine.demo = CommandLine.arguments.contains("--demo")
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        if let known = UserDefaults.standard.string(forKey: "lastOSVersion"), known != os { osChanged = true }
        UserDefaults.standard.set(os, forKey: "lastOSVersion")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: "Tato")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        touchBar.onStrip = { [weak self] strip in
            guard let self else { return }
            self.lastStrip = strip
            self.renderStatusTitle()
            self.alerts.check(self.engine.snapshot, settings: self.settings)
            if self.menuOpen { self.dashboard.sections = DashboardModel.sections(engine: self.engine, useColors: self.settings.useColors, claude: self.settings.claudeEnabled ? self.claude.snapshot : nil) }   // live while open
        }
        touchBar.start()
        claudeBar.start()
        NotificationCenter.default.addObserver(forName: ClaudeEngine.didUpdate, object: nil, queue: .main) { [weak self] _ in
            self?.renderStatusTitle()
        }

        // First run: open the Help tab so the user learns how to enable the Control Strip.
        if !UserDefaults.standard.bool(forKey: "didShowHelp") {
            UserDefaults.standard.set(true, forKey: "didShowHelp")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.showPreferences()
                self?.preferences.select(tab: 4)
            }
        }

        // Debug hooks: `--prefs` opens Preferences; `--snapshot <dir>` renders the dashboard and Preferences
        // to PNG files (only this app's own views, never the screen) and quits.
        let args = CommandLine.arguments
        if args.contains("--prefs") {
            let tab = args.firstIndex(of: "--tab").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.showPreferences()
                self?.preferences.select(tab: tab)
            }
        }
        if let i = args.firstIndex(of: "--windowid"), i + 1 < args.count {
            let file = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                if let n = self?.preferences.windowNumber { try? "\(n)".write(toFile: file, atomically: true, encoding: .utf8) }
            }
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let dir = args[i + 1]
            let delay = args.firstIndex(of: "--delay").flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? 8
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.writeSnapshots(to: dir)
                NSApp.terminate(nil)
            }
        }
    }

    private func png(of view: NSView, background: NSColor, to path: String) {
        view.appearance = NSAppearance(named: .darkAqua)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        background.setFill()
        view.bounds.fill()
        view.displayIgnoringOpacity(view.bounds, in: ctx)
        NSGraphicsContext.restoreGraphicsState()
        guard let out = rep.representation(using: .png, properties: [:]) else { return }
        try? out.write(to: URL(fileURLWithPath: path))
    }

    /// Debug: the Claude connection state and numbers (never the token).
    private func writeClaudeState(to path: String) {
        let s = claude.snapshot
        var lines = ["state: \(s.loginState.text)", "plan: \(s.plan ?? "-")"]
        if let l = s.limits {
            lines.append("session: \(l.sessionPct.map { String(format: "%.1f%%", $0) } ?? "-") resets in \(ClaudeFormat2.reset(l.sessionResets) ?? "-")")
            lines.append("weekly: \(l.weeklyPct.map { String(format: "%.1f%%", $0) } ?? "-") resets in \(ClaudeFormat2.reset(l.weeklyResets) ?? "-")")
        } else { lines.append("limits: none") }
        lines.append("tokens 5h \(ClaudeFormat.tokens(s.usage.tokens5h)), today \(ClaudeFormat.tokens(s.usage.tokensToday)), status \(s.status.label), active \(s.isActive)")
        try? lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func writeSnapshots(to dir: String) {
        writeClaudeState(to: dir + "/claude.txt")
        dashboard.sections = DashboardModel.sections(engine: engine, useColors: settings.useColors, claude: settings.claudeEnabled ? claude.snapshot : nil)
        png(of: dashboard, background: NSColor(white: 0.16, alpha: 1), to: dir + "/dashboard.png")
        png(of: claudeBar.debugPreview(), background: .black, to: dir + "/claude-bar.png")
        png(of: touchBar.debugPreview(), background: .black, to: dir + "/mac-bar.png")
        let icon = NSImageView(image: ClaudeIcon.image(unit: 12))
        icon.frame = NSRect(x: 0, y: 0, width: 15 * 12, height: 13 * 12)
        png(of: icon, background: .black, to: dir + "/claude-icon.png")
        if let content = preferences.contentView { png(of: content, background: NSColor(white: 0.16, alpha: 1), to: dir + "/prefs.png") }
    }

    /// Menu bar text according to Settings: plain values, values with labels, or icon only; optionally bold.
    private func renderStatusTitle() {
        guard let button = statusItem.button else { return }
        if settings.menuBarMode == .icon {
            button.image = NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: "Tato")
            button.attributedTitle = NSAttributedString(string: "")
            return
        }
        button.image = nil
        if settings.claudeVisible && !settings.macVisible {          // "Claude only": the menu bar follows
            let snap = claude.snapshot
            let main = snap.limits?.sessionPct.map { String(format: "%.0f%%", $0) } ?? ClaudeFormat.tokens(snap.usage.tokens5h)
            let size = NSFont.menuBarFont(ofSize: 0).pointSize
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: settings.menuBarBold ? .bold : .regular)]
            let robot = NSTextAttachment()
            robot.image = ClaudeIcon.image(unit: 1)
            robot.bounds = CGRect(x: 0, y: -2, width: 15, height: 13)
            let text = NSMutableAttributedString(attachment: robot)
            text.append(NSAttributedString(string: " " + main, attributes: attrs))
            button.attributedTitle = text
            return
        }
        let labeled = settings.menuBarMode == .labeled
        let text = lastStrip.map { labeled ? "\($0.0 == .cpuTemp ? "CPU" : MetricStyle.label($0.0)) \($0.1)" : $0.1 }.joined(separator: " · ")
        let size = NSFont.menuBarFont(ofSize: 0).pointSize
        button.attributedTitle = NSAttributedString(string: text.isEmpty ? "TBT" : text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: settings.menuBarBold ? .bold : .regular)
        ])
    }

    // MARK: - Menu (rebuilt every time it opens)

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        engine.wantsProcesses = true
        engine.processes.sample()
    }
    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        engine.wantsProcesses = false
    }

    /// Warnings about sensors or private APIs that stopped working (e.g. after a macOS update).
    private func warnings() -> [String] {
        var w: [String] = []
        if !PrivateTouchBar.functionsAvailable { w.append("API da Touch Bar indisponível: o item fixo pode não aparecer.") }
        let broken = engine.degraded
        if !broken.isEmpty {
            w.append("Sem leitura: " + broken.map(MetricStyle.menuName).joined(separator: ", ") + ". Uma API do macOS pode ter mudado.")
        }
        if osChanged { w.append("macOS atualizado desde a última execução. Se algo sumiu, rode make probe.") }
        return w
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        dashboard.sections = DashboardModel.sections(engine: engine, useColors: settings.useColors, claude: settings.claudeEnabled ? claude.snapshot : nil)
        let panel = NSMenuItem()
        panel.view = dashboard
        menu.addItem(panel)

        for text in warnings() {
            let it = NSMenuItem(title: "⚠︎ " + text, action: nil, keyEquivalent: "")
            it.attributedTitle = NSAttributedString(string: "⚠︎ " + text, attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Palette.warn])
            menu.addItem(it)
        }

        let clear = NSMenuItem(title: "Limpar mín/méd/máx", action: #selector(clearStats), keyEquivalent: "l")
        clear.target = self
        menu.addItem(clear)
        let help = NSMenuItem(title: "Como configurar a Touch Bar…", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
        let prefs = NSMenuItem(title: "Preferências…", action: #selector(showPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func clearStats() { engine.resetStats() }
    @objc private func showHelp() {
        preferences.show(engine: engine, alerts: alerts, claude: claude)
        preferences.select(tab: 4)
    }
    @objc private func showPreferences() { preferences.show(engine: engine, alerts: alerts, claude: claude) }
}
