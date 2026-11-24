import Foundation

struct ClaudeSnapshot {
    var usage = ClaudeUsageSource.Summary()
    var status = ClaudeServiceStatus.unknown
    var loaded = false
    var limits: ClaudeLimits?
    var loginState = ClaudeLoginState.disabled
    var plan: String?

    /// Claude Code wrote something in the last 90 seconds.
    var isActive: Bool { usage.lastActivity.map { Date().timeIntervalSince($0) < 90 } ?? false }
}

/// Separate from the Mac metrics engine. Every 15 s it reads Claude Code's local logs (incremental),
/// every 5 min the real plan limits through Claude Code's login, and every 2 min the public status page.
/// Runs only while the Claude mode is enabled.
final class ClaudeEngine {
    static let didUpdate = Notification.Name("TatoClaudeDidUpdate")

    /// `--demo`: fictitious numbers for screenshots, so nothing from a real account is ever shown or published.
    static var demo = false

    private static func demoSnapshot() -> ClaudeSnapshot {
        var s = ClaudeSnapshot()
        let now = Date()
        s.usage.tokens5h = 1_240_000
        s.usage.tokensToday = 2_380_000
        s.usage.tokens7d = 9_800_000
        s.usage.messagesToday = 184
        s.usage.lastActivity = now.addingTimeInterval(-25)
        s.usage.modelsToday = [
            ClaudeUsageSource.ModelUsage(name: "Sonnet 5.5", tokens: 1_600_000, responses: 120),
            ClaudeUsageSource.ModelUsage(name: "Haiku 5.5", tokens: 500_000, responses: 48),
            ClaudeUsageSource.ModelUsage(name: "Opus 5.5", tokens: 280_000, responses: 16),
        ]
        s.status = .operational
        s.loaded = true
        s.plan = "pro"
        s.loginState = .ok
        s.limits = ClaudeLimits(
            credits: ClaudeCredits(usedMinor: 1240, limitMinor: 5000, currency: "BRL", exponent: 2),
            breakdown: [ClaudeBreakdown(name: "Claude Code", pctOfLimit: 24), ClaudeBreakdown(name: "Chats", pctOfLimit: 5),
                        ClaudeBreakdown(name: "Cowork", pctOfLimit: 2), ClaudeBreakdown(name: "Outros", pctOfLimit: 0)],
            sessionPct: 42, sessionResets: now.addingTimeInterval(2 * 3600 + 15 * 60),
            weeklyPct: 31, weeklyResets: now.addingTimeInterval(3 * 86_400 + 60), fetched: now)
        return s
    }
    private static let cacheKey = "claudeLimitsCache"

    private let usage = ClaudeUsageSource()
    private let limitsClient = ClaudeLimitsClient()
    private let queue = DispatchQueue(label: "tato.claude", qos: .utility)
    private var timer: Timer?
    private var lastStatusFetch = Date.distantPast
    private var nextLimitsFetch = Date.distantPast
    private var refreshing = false
    private var fetchingLimits = false

    private(set) var snapshot = ClaudeSnapshot()
    private(set) var running = false

    func start() {
        guard !running else { return }
        running = true
        if Self.demo { snapshot = Self.demoSnapshot(); return }
        if snapshot.limits == nil, let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(ClaudeLimits.self, from: data) {
            snapshot.limits = cached          // shows the last known values right after a restart
        }
        refresh()
        let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        running = false
        snapshot.loginState = .disabled
    }

    /// Manual refresh; limits are throttled to once a minute to stay clear of the endpoint's rate limit.
    func refreshNow() {
        nextLimitsFetch = min(nextLimitsFetch, Date())
        refresh()
    }

    func refresh() {
        if Self.demo { return }
        if !refreshing {
            refreshing = true
            queue.async { [weak self] in
                guard let self else { return }
                self.usage.refresh()
                let summary = self.usage.summary()
                DispatchQueue.main.async {
                    self.snapshot.usage = summary
                    self.snapshot.loaded = true
                    self.refreshing = false
                    NotificationCenter.default.post(name: Self.didUpdate, object: nil)
                }
            }
        }
        if Date().timeIntervalSince(lastStatusFetch) > 120 {
            lastStatusFetch = Date()
            fetchStatus()
        }
        if Settings.shared.claudeUseLogin {
            if Date() >= nextLimitsFetch, !fetchingLimits { fetchLimits() }
        } else if snapshot.loginState != .disabled {
            snapshot.loginState = .disabled
            NotificationCenter.default.post(name: Self.didUpdate, object: nil)
        }
    }

    // MARK: - Plan limits

    private func fetchLimits() {
        fetchingLimits = true
        if snapshot.limits == nil { snapshot.loginState = .waiting }
        queue.async { [weak self] in
            guard let self else { return }
            let outcome = self.limitsClient.fetch()      // may wait for the Keychain permission prompt
            DispatchQueue.main.async {
                self.fetchingLimits = false
                self.snapshot.loginState = outcome.state
                if let p = outcome.plan { self.snapshot.plan = p }
                if let l = outcome.limits {
                    self.snapshot.limits = l
                    UserDefaults.standard.set(try? JSONEncoder().encode(l), forKey: Self.cacheKey)
                }
                switch outcome.state {
                case .ok: self.nextLimitsFetch = Date().addingTimeInterval(300)
                case .rateLimited(let until): self.nextLimitsFetch = until
                case .failed: self.nextLimitsFetch = Date().addingTimeInterval(120)
                default: self.nextLimitsFetch = Date().addingTimeInterval(900)   // no login / denied / expired
                }
                NotificationCenter.default.post(name: Self.didUpdate, object: nil)
            }
        }
    }

    // MARK: - Service status

    /// Public Statuspage endpoint; no account data is sent.
    private func fetchStatus() {
        guard let url = URL(string: "https://status.claude.com/api/v2/status.json") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        SecureSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            var status = ClaudeServiceStatus.unknown
            if let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let st = obj["status"] as? [String: Any], let ind = st["indicator"] as? String {
                switch ind {
                case "none": status = .operational
                case "minor": status = .degraded
                case "major", "critical": status = .outage
                default: status = .unknown
                }
            }
            DispatchQueue.main.async {
                self?.snapshot.status = status
                NotificationCenter.default.post(name: ClaudeEngine.didUpdate, object: nil)
            }
        }.resume()
    }
}
