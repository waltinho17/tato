import Foundation
import IOKit
import IOKit.ps
import Darwin

final class SystemSource: MetricSource {
    let ids: [MetricID] = [.disk, .memory, .memPressure, .battery]

    struct BatteryDetails {
        var health: Double?       // nominal full-charge capacity / design capacity, %
        var cycles: Int?
        var charging = false
        var pluggedIn = false
        var minutesRemaining: Int?
    }
    private(set) var batteryDetails: BatteryDetails?

    func read() -> [MetricID: MetricValue] {
        batteryDetails = readBatteryDetails()
        return [.disk: disk(), .memory: memory(), .memPressure: memoryPressure(), .battery: battery()]
    }

    // Disk usage barely changes and the "important usage" query hits cache_delete, so cache it.
    private var diskCache: (value: MetricValue, at: Date)?

    private func disk() -> MetricValue {
        if let c = diskCache, Date().timeIntervalSince(c.at) < 30 { return c.value }
        let v = readDisk()
        diskCache = (v, Date())
        return v
    }

    private func readDisk() -> MetricValue {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = v.volumeTotalCapacity,
              let free = v.volumeAvailableCapacityForImportantUsage else { return .unavailable("volume capacity") }
        let gb = 1_000_000_000.0
        return .percent(used: (Double(total) - Double(free)) / gb, total: Double(total) / gb, unit: "GB")
    }

    private func memory() -> MetricValue {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return .unavailable("host_statistics64 failed") }
        let page = Double(sysconf(_SC_PAGESIZE))
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let gb = 1_073_741_824.0
        return .percent(used: used / gb, total: total / gb, unit: "GB")
    }

    private func battery() -> MetricValue {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return .unavailable("no power source info")
        }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Double ?? (d[kIOPSCurrentCapacityKey] as? Int).map(Double.init),
                  let max = d[kIOPSMaxCapacityKey] as? Double ?? (d[kIOPSMaxCapacityKey] as? Int).map(Double.init),
                  max > 0 else { continue }
            return .percent(used: cur, total: max, unit: "%")
        }
        return .unavailable("no battery")
    }

    /// kern.memorystatus_level is the percentage of memory still available; pressure is its complement.
    private func memoryPressure() -> MetricValue {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_level", &level, &size, nil, 0) == 0 else {
            return .unavailable("kern.memorystatus_level")
        }
        return .percent(used: Double(100 - level), total: 100, unit: "%")
    }

    private func readBatteryDetails() -> BatteryDetails? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return nil }
        var b = BatteryDetails()
        b.cycles = (d["CycleCount"] as? NSNumber)?.intValue
        b.charging = (d["IsCharging"] as? Bool) ?? false
        b.pluggedIn = (d["ExternalConnected"] as? Bool) ?? false
        if let t = (d["TimeRemaining"] as? NSNumber)?.intValue, t > 0, t < 6000 { b.minutesRemaining = t }
        let bd = d["BatteryData"] as? [String: Any]
        let design = ((bd?["DesignCapacity"] ?? d["DesignCapacity"]) as? NSNumber)?.doubleValue
        let full = ((bd?["NominalChargeCapacity"] ?? d["AppleRawMaxCapacity"] ?? d["NominalChargeCapacity"]) as? NSNumber)?.doubleValue
        if let design, let full, design > 0 { b.health = min(full / design * 100, 100) }
        return b
    }
}
