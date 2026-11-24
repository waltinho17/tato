import AppKit
import UserNotifications
import ServiceManagement

/// Temperature alerts through user notifications. Fires once per excursion (re-arms 5 °C below the limit)
/// and at most every 10 minutes. Notifications only work when running as a bundled .app.
final class AlertManager: NSObject, UNUserNotificationCenterDelegate {
    private var armed = true
    private var lastSent: Date?

    private static var canNotify: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    override init() {
        super.init()
        if Self.canNotify { UNUserNotificationCenter.current().delegate = self }
    }

    func requestAuthorization() {
        guard Self.canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func check(_ snapshot: [MetricID: MetricValue], settings: Settings) {
        guard settings.alertsEnabled else { return }
        var hottest: (name: String, temp: Double)?
        for (id, name) in [(MetricID.cpuTemp, "CPU"), (.gpuTemp, "GPU")] {
            if case .temperature(let t)? = snapshot[id], t > (hottest?.temp ?? -1) { hottest = (name, t) }
        }
        guard let h = hottest else { return }
        let limit = settings.alertThreshold
        if h.temp < limit - 5 { armed = true }
        guard h.temp >= limit, armed, lastSent.map({ Date().timeIntervalSince($0) > 600 }) ?? true else { return }
        armed = false
        lastSent = Date()
        send(title: tr("Temperatura alta", "High temperature"),
             body: String(format: tr("%@ em %.0f°C, acima do limite de %.0f°C.", "%@ at %.0f°C, above your %.0f°C limit."), h.name, h.temp, limit))
    }

    func sendTest() { send(title: tr("Alerta de teste", "Test alert"), body: tr("As notificações estão funcionando.", "Notifications are working.")) }

    private func send(title: String, body: String) {
        guard Self.canNotify else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    // Show banners even though this accessory app is "frontmost".
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    static func set(_ on: Bool) throws {
        guard #available(macOS 13.0, *) else { return }
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
