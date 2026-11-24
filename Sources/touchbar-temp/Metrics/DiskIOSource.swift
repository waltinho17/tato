import IOKit
import Foundation

/// Disk read / write throughput from the cumulative IOBlockStorageDriver byte counters.
final class DiskIOSource: MetricSource {
    let ids: [MetricID] = [.diskRead, .diskWrite]
    private var prev: (read: UInt64, write: UInt64)?
    private var prevTime: Date?

    private func totals() -> (read: UInt64, write: UInt64)? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        var r: UInt64 = 0, w: UInt64 = 0, found = false
        var entry = IOIteratorNext(it)
        while entry != 0 {
            if let stats = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                r += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                w += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
                found = true
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(it)
        }
        return found ? (r, w) : nil
    }

    func read() -> [MetricID: MetricValue] {
        guard let cur = totals() else {
            return [.diskRead: .unavailable("no IOBlockStorageDriver"), .diskWrite: .unavailable("no IOBlockStorageDriver")]
        }
        let now = Date()
        defer { prev = cur; prevTime = now }
        guard let p = prev, let t0 = prevTime else { return [.diskRead: .idle("warming up"), .diskWrite: .idle("warming up")] }
        let dt = max(now.timeIntervalSince(t0), 0.001)
        return [.diskRead: .rate(Double(cur.read &- p.read) / dt), .diskWrite: .rate(Double(cur.write &- p.write) / dt)]
    }
}
