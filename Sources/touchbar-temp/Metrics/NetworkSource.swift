import Darwin
import Foundation

/// Download / upload speed summed over the Ethernet/Wi-Fi interfaces (en*), from getifaddrs byte counters.
final class NetworkSource: MetricSource {
    let ids: [MetricID] = [.netDown, .netUp]
    private var prev: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var prevTime: Date?

    func read() -> [MetricID: MetricValue] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else {
            return [.netDown: .unavailable("getifaddrs failed"), .netUp: .unavailable("getifaddrs failed")]
        }
        defer { freeifaddrs(head) }

        var cur: [String: (rx: UInt32, tx: UInt32)] = [:]
        var node: UnsafeMutablePointer<ifaddrs>? = first
        while let n = node {
            let ifa = n.pointee
            node = ifa.ifa_next
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en"), ifa.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            cur[name] = (d.ifi_ibytes, d.ifi_obytes)
        }

        let now = Date()
        defer { prev = cur; prevTime = now }
        guard let t0 = prevTime else { return [.netDown: .idle("warming up"), .netUp: .idle("warming up")] }
        let dt = max(now.timeIntervalSince(t0), 0.001)
        var rx = 0.0, tx = 0.0
        for (name, c) in cur {
            guard let p = prev[name] else { continue }
            rx += Double(c.rx &- p.rx)   // 32-bit counters: modular subtraction survives one wrap
            tx += Double(c.tx &- p.tx)
        }
        return [.netDown: .rate(rx / dt), .netUp: .rate(tx / dt)]
    }
}
