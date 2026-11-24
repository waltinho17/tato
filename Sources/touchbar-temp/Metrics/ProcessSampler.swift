import Darwin
import Foundation

/// Top processes by CPU and memory, aggregated per app bundle (all Chrome helpers count as "Google Chrome").
/// Only processes of the current user can be inspected without privileges.
final class ProcessSampler {
    struct Entry { let name: String; let cpu: Double; let memory: UInt64 }

    private var prev: [Int32: UInt64] = [:]     // pid -> cumulative CPU (mach time)
    private var prevWall: UInt64?
    private(set) var hasCPU = false
    private(set) var all: [Entry] = []

    func topCPU(_ n: Int = 3) -> [Entry] { Array(all.sorted { $0.cpu > $1.cpu }.prefix(n)) }
    func topMemory(_ n: Int = 3) -> [Entry] { Array(all.sorted { $0.memory > $1.memory }.prefix(n)) }

    private func appName(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 else { return nil }
        let path = String(cString: buf)
        let parts = path.split(separator: "/")
        if let app = parts.first(where: { $0.hasSuffix(".app") }) { return String(app.dropLast(4)) }
        return parts.last.map(String.init)
    }

    func sample() {
        var pids = [Int32](repeating: 0, count: 4096)
        let n = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size)))
        guard n > 0 else { return }

        let wall = mach_absolute_time()
        var agg: [String: (cpu: Double, mem: UInt64)] = [:]
        var cur: [Int32: UInt64] = [:]
        var names: [Int32: String] = [:]
        let wallDelta = prevWall.map { Double(wall &- $0) }

        for i in 0..<min(n, pids.count) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var ti = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size) == size else { continue }
            let cpuNow = ti.pti_total_user &+ ti.pti_total_system
            cur[pid] = cpuNow

            var cpu = 0.0
            if let before = prev[pid], let wd = wallDelta, wd > 0 { cpu = Double(cpuNow &- before) / wd * 100 }

            var mem = UInt64(ti.pti_resident_size)
            var ri = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &ri) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            if ok == 0 { mem = ri.ri_phys_footprint }

            guard let name = names[pid] ?? appName(pid) else { continue }
            names[pid] = name
            let a = agg[name] ?? (0, 0)
            agg[name] = (a.cpu + cpu, a.mem + mem)
        }
        hasCPU = wallDelta != nil
        prev = cur
        prevWall = wall
        all = agg.map { Entry(name: $0.key, cpu: $0.value.cpu, memory: $0.value.mem) }
    }
}
