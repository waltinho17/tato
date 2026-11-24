import Darwin
import Foundation

/// CPU utilisation from per-core tick counters (host_processor_info), split by efficiency / performance cores.
final class CPUUsageSource: MetricSource {
    let ids: [MetricID] = [.cpuUsage]
    private var prev: [[UInt32]] = []

    private(set) var perCore: [Double] = []
    /// Efficiency cores come first in the CPU numbering on Apple Silicon.
    private(set) var efficiencyUsage: Double?
    private(set) var performanceUsage: Double?

    private static func sysctlInt(_ name: String) -> Int? {
        var v: Int32 = 0; var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? Int(v) : nil
    }

    func read() -> [MetricID: MetricValue] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [.cpuUsage: .unavailable("host_processor_info failed")] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }

        let states = Int(CPU_STATE_MAX)
        var cur: [[UInt32]] = []
        for i in 0..<Int(cpuCount) {
            cur.append((0..<states).map { UInt32(bitPattern: info[i * states + $0]) })
        }
        defer { prev = cur }
        guard prev.count == cur.count else { return [.cpuUsage: .idle("warming up")] }

        var usage: [Double] = []
        var busySum = 0.0, totalSum = 0.0
        for (c, p) in zip(cur, prev) {
            let d = (0..<states).map { Double(c[$0] &- p[$0]) }
            let total = d.reduce(0, +)
            let busy = total - d[Int(CPU_STATE_IDLE)]
            usage.append(total > 0 ? busy / total * 100 : 0)
            busySum += busy; totalSum += total
        }
        perCore = usage

        if let e = Self.sysctlInt("hw.perflevel1.logicalcpu"), let pc = Self.sysctlInt("hw.perflevel0.logicalcpu"),
           e + pc == usage.count, e > 0, pc > 0 {
            efficiencyUsage = usage.prefix(e).reduce(0, +) / Double(e)
            performanceUsage = usage.suffix(pc).reduce(0, +) / Double(pc)
        } else {
            efficiencyUsage = nil; performanceUsage = nil
        }
        return [.cpuUsage: .percent(used: totalSum > 0 ? busySum / totalSum * 100 : 0, total: 100, unit: "%")]
    }
}
