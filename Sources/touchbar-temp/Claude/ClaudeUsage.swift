import Foundation

/// Token usage estimated from Claude Code's local logs (~/.claude/projects/**/*.jsonl).
/// Only the timestamp and token counts are read; conversation text is never stored.
/// "Tokens" here are input + output + cache-creation tokens. This is not the official plan quota.
final class ClaudeUsageSource {
    struct ModelUsage { let name: String; let tokens: Int; let responses: Int }

    struct Summary {
        var tokens5h = 0, tokensToday = 0, tokens7d = 0, messagesToday = 0
        var lastActivity: Date?
        var modelsToday: [ModelUsage] = []      // most used first
    }

    private struct Record { let time: Date; let tokens: Int; let model: String }

    /// "claude-fable-5-1" -> "Fable 5.1", "claude-3-5-sonnet-20241022" -> "Sonnet 3.5"
    static func prettyModel(_ raw: String) -> String {
        var parts = raw.replacingOccurrences(of: "claude-", with: "").split(separator: "-").map(String.init)
        parts.removeAll { $0.count == 8 && Int($0) != nil }                      // trailing date
        let nums = parts.filter { Int($0) != nil }.joined(separator: ".")
        let family = parts.first { Int($0) == nil }?.capitalized ?? raw
        return nums.isEmpty ? family : "\(family) \(nums)"
    }

    private let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    private let retention: TimeInterval = 8 * 86_400
    private var offsets: [String: UInt64] = [:]
    private var records: [Record] = []
    private var seen: Set<String> = []
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoPlain = ISO8601DateFormatter()
    private let needle = Data("\"output_tokens\"".utf8)

    /// Reads whatever was appended to the logs since the last call. Call from a background queue.
    func refresh() {
        let cutoff = Date().addingTimeInterval(-retention)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in en where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  let size = v.fileSize.map(UInt64.init) else { continue }
            let path = url.path
            if offsets[path] == nil, let m = v.contentModificationDate, m < cutoff { continue }   // old, never seen
            var start = offsets[path] ?? 0
            if size < start { start = 0 }            // file was replaced
            if size == start { continue }
            guard let data = try? Data(contentsOf: url, options: .alwaysMapped), data.count >= Int(size) else { continue }
            let chunk = data[Int(start)..<Int(size)]
            guard let lastNL = chunk.lastIndex(of: 0x0A) else { continue }   // only complete lines
            ingest(chunk[chunk.startIndex...lastNL], cutoff: cutoff)
            offsets[path] = start + UInt64(lastNL - chunk.startIndex + 1)
        }
        records.removeAll { $0.time < cutoff }
    }

    private func ingest(_ data: Data.SubSequence, cutoff: Date) {
        var lineStart = data.startIndex
        while lineStart < data.endIndex {
            let lineEnd = data[lineStart...].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data[lineStart..<lineEnd]
            lineStart = lineEnd < data.endIndex ? data.index(after: lineEnd) : data.endIndex
            guard line.range(of: needle) != nil,
                  let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  (obj["type"] as? String) == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let usage = msg["usage"] as? [String: Any],
                  let ts = obj["timestamp"] as? String,
                  let time = iso.date(from: ts) ?? isoPlain.date(from: ts), time >= cutoff else { continue }
            let key = "\(msg["id"] as? String ?? "")|\(obj["requestId"] as? String ?? "")"
            if key != "|", !seen.insert(key).inserted { continue }          // Claude Code logs some responses twice
            func n(_ k: String) -> Int { (usage[k] as? NSNumber)?.intValue ?? 0 }
            let model = (msg["model"] as? String) ?? ""
            if model.hasPrefix("<") { continue }                              // synthetic entries
            records.append(Record(time: time, tokens: n("input_tokens") + n("output_tokens") + n("cache_creation_input_tokens"),
                                  model: model))
        }
    }

    func summary(now: Date = Date()) -> Summary {
        var s = Summary()
        var byModel: [String: (tokens: Int, responses: Int)] = [:]
        let startOfDay = Calendar.current.startOfDay(for: now)
        for r in records {
            if r.time > now.addingTimeInterval(-5 * 3600) { s.tokens5h += r.tokens }
            if r.time > now.addingTimeInterval(-7 * 86_400) { s.tokens7d += r.tokens }
            if r.time >= startOfDay {
                s.tokensToday += r.tokens; s.messagesToday += 1
                let key = r.model.isEmpty ? "?" : Self.prettyModel(r.model)
                byModel[key, default: (0, 0)].tokens += r.tokens
                byModel[key, default: (0, 0)].responses += 1
            }
            if s.lastActivity.map({ r.time > $0 }) ?? true { s.lastActivity = r.time }
        }
        s.modelsToday = byModel.map { ModelUsage(name: $0.key, tokens: $0.value.tokens, responses: $0.value.responses) }
            .sorted { $0.tokens > $1.tokens }
        return s
    }
}

enum ClaudeTime {
    /// "agora", "há 5 min", "há 2 h"
    static func ago(_ d: Date?, now: Date = Date()) -> String {
        guard let d else { return "–" }
        let s = Int(now.timeIntervalSince(d))
        if s < 60 { return "agora" }
        if s < 3600 { return "há \(s / 60) min" }
        if s < 86_400 { return "há \(s / 3600) h" }
        return "há \(s / 86_400) d"
    }
}

enum ClaudeServiceStatus {
    case operational, degraded, outage, unknown

    var label: String {
        switch self {
        case .operational: return "OK"
        case .degraded: return "LENTO"
        case .outage: return "FORA"
        case .unknown: return "–"
        }
    }
}

enum ClaudeFormat {
    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        if d >= 1e9 { return String(format: "%.1fB", d / 1e9) }
        if d >= 1e6 { return String(format: "%.1fM", d / 1e6) }
        if d >= 1e3 { return String(format: "%.1fk", d / 1e3) }
        return "\(n)"
    }
}
