import Foundation

final class Settings {
    static let shared = Settings()
    static let didChange = Notification.Name("TouchBarTempSettingsDidChange")
    static let maxStripWidgets = 2

    private let d = UserDefaults.standard

    private func load(_ key: String, default def: [MetricID]) -> [MetricID] {
        guard let raw = d.array(forKey: key) as? [String] else { return def }
        return raw.compactMap(MetricID.init(rawValue:))
    }

    private func save(_ key: String, _ ids: [MetricID]) {
        d.set(ids.map(\.rawValue), forKey: key)
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
    }

    /// Widgets shown when the Touch Bar is expanded, in the user's chosen order.
    var enabledWidgets: [MetricID] {
        get { load("enabledWidgets", default: MetricID.defaultWidgets).sorted { order($0) < order($1) } }
        set { save("enabledWidgets", newValue) }
    }

    /// Display order of every metric (drag to reorder in Preferences).
    var widgetOrder: [MetricID] {
        get { let saved = load("widgetOrder", default: MetricID.allCases); return saved + MetricID.allCases.filter { !saved.contains($0) } }
        set { save("widgetOrder", newValue) }
    }

    /// "auto" follows the system language; "pt" or "en" force one.
    var languageChoice: String {
        get { d.string(forKey: "language") ?? "auto" }
        set { d.set(newValue, forKey: "language"); NotificationCenter.default.post(name: Settings.didChange, object: nil) }
    }

    /// What the Touch Bar shows when the Claude mode is on.
    enum DisplayMode: String { case both, macOnly, claudeOnly }

    var displayMode: DisplayMode {
        get { ClaudeEngine.demo ? .both : (DisplayMode(rawValue: d.string(forKey: "displayMode") ?? "") ?? .both) }
        set { d.set(newValue.rawValue, forKey: "displayMode"); NotificationCenter.default.post(name: Settings.didChange, object: nil) }
    }

    /// Read Claude Code's login from the Keychain to get the real plan limits (session and weekly).
    var claudeUseLogin: Bool {
        get { d.object(forKey: "claudeUseLogin") as? Bool ?? true }
        set { d.set(newValue, forKey: "claudeUseLogin"); NotificationCenter.default.post(name: Settings.didChange, object: nil) }
    }

    /// The Mac metrics button is hidden only when the user chose "Claude only" and the Claude mode is on.
    var macVisible: Bool { !(claudeEnabled && displayMode == .claudeOnly) }
    var claudeVisible: Bool { claudeEnabled && displayMode != .macOnly }

    /// Claude mode: a second Control Strip item with Claude Code usage. Off by default.
    var claudeEnabled: Bool {
        get { d.bool(forKey: "claudeEnabled") }
        set { d.set(newValue, forKey: "claudeEnabled"); NotificationCenter.default.post(name: Settings.didChange, object: nil) }
    }

    var alertsEnabled: Bool {
        get { d.bool(forKey: "alertsEnabled") }
        set { d.set(newValue, forKey: "alertsEnabled"); NotificationCenter.default.post(name: Settings.didChange, object: nil) }
    }

    /// Temperature (°C) at which CPU/GPU alerts fire.
    var alertThreshold: Double {
        get { let v = d.double(forKey: "alertThreshold"); return v > 0 ? v : 90 }
        set { d.set(newValue, forKey: "alertThreshold"); NotificationCenter.default.post(name: Settings.didChange, object: nil) }
    }

    /// Up to two metrics shown in the always-visible Control Strip item.
    var stripWidgets: [MetricID] {
        get { Array(load("stripWidgets", default: [.cpuTemp, .fanRPM]).prefix(Settings.maxStripWidgets)) }
        set { save("stripWidgets", Array(newValue.prefix(Settings.maxStripWidgets))) }
    }

    var useColors: Bool {
        get { d.object(forKey: "useColors") as? Bool ?? true }
        set { d.set(newValue, forKey: "useColors"); NotificationCenter.default.post(name: Settings.didChange, object: nil) }
    }

    /// How the two strip metrics appear in the macOS menu bar.
    enum MenuBarMode: String { case values, labeled, icon }

    var menuBarMode: MenuBarMode {
        get { MenuBarMode(rawValue: d.string(forKey: "menuBarMode") ?? "") ?? .values }
        set { d.set(newValue.rawValue, forKey: "menuBarMode"); NotificationCenter.default.post(name: Settings.didChange, object: nil) }
    }

    var menuBarBold: Bool {
        get { d.bool(forKey: "menuBarBold") }
        set { d.set(newValue, forKey: "menuBarBold"); NotificationCenter.default.post(name: Settings.didChange, object: nil) }
    }

    var refreshInterval: TimeInterval {
        get { let v = d.double(forKey: "refreshInterval"); return v > 0 ? v : 3 }
        set { d.set(newValue, forKey: "refreshInterval"); NotificationCenter.default.post(name: Settings.didChange, object: nil) }
    }

    private func order(_ id: MetricID) -> Int { widgetOrder.firstIndex(of: id) ?? 0 }
}
