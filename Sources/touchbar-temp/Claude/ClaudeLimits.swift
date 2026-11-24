import Foundation
import Security

/// Plan limits as shown on the Claude usage screen: the 5-hour session and the weekly window.
struct ClaudeLimitExtra: Codable {
    var name: String
    var pct: Double
    var resets: Date?
}

/// Extra-usage credits: spend beyond the plan limits, with a monthly cap.
struct ClaudeCredits: Codable {
    var usedMinor: Int
    var limitMinor: Int
    var currency: String
    var exponent: Int

    var pct: Double { limitMinor > 0 ? Double(usedMinor) / Double(limitMinor) * 100 : 0 }
    var used: String { ClaudeFormat2.money(usedMinor, currency, exponent) }
    var limit: String { ClaudeFormat2.money(limitMinor, currency, exponent) }
}

/// Share of the weekly limit by origin: Claude Code, chats, Cowork, other.
struct ClaudeBreakdown: Codable {
    var name: String
    var pctOfLimit: Double
}

struct ClaudeLimits: Codable {
    var credits: ClaudeCredits?
    var breakdown: [ClaudeBreakdown]?
    var extras: [ClaudeLimitExtra]?     // other windows the endpoint reports, e.g. weekly per model
    var sessionPct: Double?
    var sessionResets: Date?
    var weeklyPct: Double?
    var weeklyResets: Date?
    var fetched = Date()
}

enum ClaudeLoginState: Equatable {
    case disabled              // the option is off
    case waiting               // not fetched yet
    case ok
    case noLogin               // Claude Code is not signed in on this Mac
    case denied                // Keychain access was refused
    case expired               // token expired: opening Claude Code renews it
    case rateLimited(Date)
    case failed(String)

    var text: String {
        switch self {
        case .disabled: return "Desligado"
        case .waiting: return "Conectando…"
        case .ok: return "Conectado"
        case .noLogin: return "Claude Code sem login neste Mac"
        case .denied: return "Acesso ao Chaveiro negado"
        case .expired: return "Login expirado: abra o Claude Code para renovar"
        case .rateLimited(let d):
            let f = DateFormatter(); f.timeStyle = .short
            return "Limite de consultas, nova tentativa às \(f.string(from: d))"
        case .failed(let why): return "Falhou: \(why)"
        }
    }
}

enum ClaudeFormat2 {
    /// "R$ 18,10" from minor units (cents).
    static func money(_ minor: Int, _ currency: String, _ exponent: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.locale = Locale(identifier: "pt_BR")
        f.minimumFractionDigits = minor % Int(pow(10, Double(exponent))) == 0 ? 0 : exponent
        f.maximumFractionDigits = exponent
        return f.string(from: NSNumber(value: Double(minor) / pow(10, Double(exponent)))) ?? "\(minor)"
    }

    /// "2h15m", "3d 0h", "58m"
    static func reset(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let s = Int(date.timeIntervalSince(now))
        if s <= 0 { return "agora" }
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return String(format: "%dh%02dm", h, m) }
        return "\(m)m"
    }
}

/// Network session for the credential-bearing request: ephemeral (nothing written to disk), no cookies,
/// and it refuses every redirect so the token can never be forwarded to another host.
enum SecureSession {
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    static let shared: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: c, delegate: NoRedirect(), delegateQueue: nil)
    }()
}

/// Reads Claude Code's own login from the macOS Keychain (shared by the terminal, the VS Code extension and the app)
/// and asks Anthropic's usage endpoint for the plan limits. The endpoint is undocumented and may change.
/// macOS asks for permission the first time; choose "Always Allow" to avoid repeated prompts.
final class ClaudeLimitsClient {
    struct Outcome {
        var limits: ClaudeLimits?
        var state: ClaudeLoginState
        var plan: String?
    }

    private var token: (value: String, expires: Date?, plan: String?)?

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    // MARK: - Keychain

    private enum KeychainResult { case ok(String, Date?, String?), notFound, denied, malformed }

    private func readKeychain() -> KeychainResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return .notFound }
        guard status == errSecSuccess, let data = item as? Data else { return .denied }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let access = oauth["accessToken"] as? String else { return .malformed }
        let expires = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return .ok(access, expires, oauth["subscriptionType"] as? String)
    }

    // MARK: - Fetch (blocking: call from a background queue)

    func fetch() -> Outcome {
        if token == nil || (token?.expires.map { $0 < Date() } ?? false) {
            switch readKeychain() {
            case .ok(let t, let e, let p): token = (t, e, p)
            case .notFound: return Outcome(state: .noLogin)
            case .denied: return Outcome(state: .denied)
            case .malformed: return Outcome(state: .failed("formato de login desconhecido"))
            }
        }
        guard let tk = token else { return Outcome(state: .noLogin) }
        if let e = tk.expires, e < Date() { token = nil; return Outcome(state: .expired, plan: tk.plan) }

        // The token is only ever sent to this fixed Anthropic host over HTTPS.
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(tk.value)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let sem = DispatchSemaphore(value: 0)
        var data: Data?, http: HTTPURLResponse?, err: Error?
        SecureSession.shared.dataTask(with: req) { d, r, e in data = d; http = r as? HTTPURLResponse; err = e; sem.signal() }.resume()
        sem.wait()

        if let err { return Outcome(state: .failed(err.localizedDescription), plan: tk.plan) }
        guard let http else { return Outcome(state: .failed("sem resposta"), plan: tk.plan) }
        switch http.statusCode {
        case 200: break
        case 401, 403: token = nil; return Outcome(state: .expired, plan: tk.plan)
        case 429:
            let wait = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) ?? 1800
            return Outcome(state: .rateLimited(Date().addingTimeInterval(max(wait, 300))), plan: tk.plan)
        default: return Outcome(state: .failed("HTTP \(http.statusCode)"), plan: tk.plan)
        }
        guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = Self.parse(obj) else {
            return Outcome(state: .failed("resposta inesperada"), plan: tk.plan)
        }
        return Outcome(limits: limits, state: .ok, plan: tk.plan)
    }

    // MARK: - Parsing

    static func date(_ s: String) -> Date? { iso.date(from: s) ?? isoPlain.date(from: s) }

    private static func prettyWindow(_ key: String) -> String {
        switch key {
        case "seven_day_opus": return "Semanal · Opus"
        case "seven_day_sonnet": return "Semanal · Sonnet"
        case "seven_day_oauth_apps": return "Semanal · apps"
        default: return key.replacingOccurrences(of: "seven_day", with: "Semanal").replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Expects {"five_hour": {"utilization": 42.0, "resets_at": "..."}, "seven_day": {...}, ...}.
    static func parse(_ obj: [String: Any]) -> ClaudeLimits? {
        func entry(_ key: String) -> (Double, Date?)? {
            guard let d = obj[key] as? [String: Any], let u = (d["utilization"] as? NSNumber)?.doubleValue else { return nil }
            return (u, (d["resets_at"] as? String).flatMap(date))
        }
        let s = entry("five_hour"), w = entry("seven_day")
        guard s != nil || w != nil else { return nil }
        var extras: [ClaudeLimitExtra] = []
        for key in obj.keys.sorted() where !["five_hour", "seven_day", "extra_usage"].contains(key) {
            guard let e = entry(key) else { continue }
            extras.append(ClaudeLimitExtra(name: prettyWindow(key), pct: e.0, resets: e.1))
        }
        var credits: ClaudeCredits?
        if let ex = obj["extra_usage"] as? [String: Any], (ex["is_enabled"] as? NSNumber)?.boolValue == true,
           let used = (ex["used_credits"] as? NSNumber)?.intValue, let limit = (ex["monthly_limit"] as? NSNumber)?.intValue, limit > 0 {
            credits = ClaudeCredits(usedMinor: used, limitMinor: limit, currency: (ex["currency"] as? String) ?? "USD",
                                    exponent: (ex["decimal_places"] as? NSNumber)?.intValue ?? 2)
        }
        var breakdown: [ClaudeBreakdown]?
        if let sb = obj["seven_day_breakdown"] as? [String: Any], let rows = sb["rows"] as? [[String: Any]] {
            breakdown = rows.compactMap {
                guard let n = $0["display_name"] as? String, let p = ($0["percent_of_limit"] as? NSNumber)?.doubleValue else { return nil }
                return ClaudeBreakdown(name: n, pctOfLimit: p)
            }
        }
        return ClaudeLimits(credits: credits, breakdown: breakdown, extras: extras.isEmpty ? nil : extras, sessionPct: s?.0, sessionResets: s?.1, weeklyPct: w?.0, weeklyResets: w?.1)
    }
}
