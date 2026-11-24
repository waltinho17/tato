import Foundation

/// Running min / max / average since launch or the last reset.
struct MetricStat {
    var min = Double.infinity, max = -Double.infinity, sum = 0.0, count = 0
    var avg: Double { count > 0 ? sum / Double(count) : 0 }
    mutating func add(_ v: Double) { min = Swift.min(min, v); max = Swift.max(max, v); sum += v; count += 1 }
}

final class MetricsEngine {
    private let temperature = TemperatureSource()
    private let fan = FanSource()
    let system = SystemSource()
    private let network = NetworkSource()
    private let diskIO = DiskIOSource()
    let cpuUsage = CPUUsageSource()
    let processes = ProcessSampler()
    /// Set while the menu is open: sampling processes costs a few ms, so it only runs when someone looks.
    var wantsProcesses = false
    private(set) var history: [MetricID: [Double]] = [:]
    private static let historyLength = 90
    private lazy var frequency = FrequencySource()

    var enabled: Set<MetricID> = Set(MetricID.allCases)
    var interval: TimeInterval = 3 { didSet { if timer != nil { start() } } }
    private(set) var snapshot: [MetricID: MetricValue] = [:]
    private(set) var stats: [MetricID: MetricStat] = [:]
    private var everAvailable: Set<MetricID> = []
    private var failures: [MetricID: Int] = [:]

    /// Metrics that worked earlier in this session but now fail repeatedly: a macOS update may have changed a private API.
    var degraded: [MetricID] {
        MetricID.allCases.filter { (failures[$0] ?? 0) >= 3 && everAvailable.contains($0) }
    }
    func resetStats() { stats.removeAll(); history.removeAll() }

    private func record(_ id: MetricID, _ x: Double) {
        var h = history[id, default: []]
        h.append(x)
        if h.count > Self.historyLength { h.removeFirst(h.count - Self.historyLength) }
        history[id] = h
    }

    /// Metrics this Mac can read. A metric is dropped only when its source reports `.unavailable`.
    var supported: [MetricID] {
        guard !snapshot.isEmpty else { return MetricID.allCases }
        return MetricID.allCases.filter {
            if case .unavailable? = snapshot[$0] { return false }
            return snapshot[$0] != nil
        }
    }
    var onUpdate: (([MetricID: MetricValue]) -> Void)?

    private var timer: Timer?

    func start() {
        timer?.invalidate()
        tick()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() { timer?.invalidate(); timer = nil }

    func tick() {
        var snap: [MetricID: MetricValue] = [:]
        let sources: [MetricSource] = [temperature, fan, system, network, diskIO, cpuUsage]
        for s in sources where s.ids.contains(where: enabled.contains) { snap.merge(s.read()) { $1 } }
        if enabled.contains(.cpuFreq) || enabled.contains(.gpuFreq) { snap.merge(frequency.read()) { $1 } }
        snapshot = snap.filter { enabled.contains($0.key) }
        for (id, v) in snapshot {
            if case .unavailable = v { failures[id, default: 0] += 1 } else { failures[id] = 0; everAvailable.insert(id) }
        }
        for (id, v) in snapshot where id != .disk {
            switch v {
            case .temperature(let x), .rpm(let x), .mhz(let x), .rate(let x):
                stats[id, default: MetricStat()].add(x)
                record(id, x)
            case .percent(let u, let t, _) where t > 0:
                stats[id, default: MetricStat()].add(u / t * 100)
                record(id, u / t * 100)
            default: break
            }
        }
        if wantsProcesses { processes.sample() }
        onUpdate?(snapshot)
    }
}
