import IOKit
import Darwin
import Foundation

// CPU/GPU frequency on Apple Silicon without sudo: libIOReport residency per DVFS state,
// weighted by the frequency tables in the pmgr IORegistry node (port of vladkens/macmon).

final class FrequencySource: MetricSource {
    let ids: [MetricID] = [.cpuFreq, .gpuFreq]

    struct Channel {
        let group: String, subgroup: String, name: String
        let states: [(name: String, residency: Int64)]
    }

    private typealias CopyChannelsFn = @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias CreateSubFn = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?, UInt64, UnsafeRawPointer?) -> UnsafeRawPointer?
    private typealias CreateSamplesFn = @convention(c) (UnsafeRawPointer, CFMutableDictionary, UnsafeRawPointer?) -> Unmanaged<CFDictionary>?
    private typealias DeltaFn = @convention(c) (CFDictionary, CFDictionary, UnsafeRawPointer?) -> Unmanaged<CFDictionary>?
    private typealias IterateFn = @convention(c) (CFDictionary, @convention(block) (CFDictionary) -> Int32) -> Void
    private typealias GetStrFn = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias StateCountFn = @convention(c) (CFDictionary) -> Int32
    private typealias StateNameFn = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    private typealias StateResFn = @convention(c) (CFDictionary, Int32) -> Int64

    private var copyChannels: CopyChannelsFn?
    private var createSub: CreateSubFn?
    private var createSamples: CreateSamplesFn?
    private var delta: DeltaFn?
    private var iterate: IterateFn?
    private var getGroup: GetStrFn?, getSub: GetStrFn?, getName: GetStrFn?
    private var stateCount: StateCountFn?
    private var stateName: StateNameFn?
    private var stateRes: StateResFn?

    private var subscription: UnsafeRawPointer?
    private var channels: CFMutableDictionary?
    private var previous: CFDictionary?

    private(set) var loadError: String?
    private(set) var lastChannels: [Channel] = []
    private(set) var tables: [String: [Double]] = [:]   // key -> MHz list

    init() {
        guard let lib = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY) else { loadError = "libIOReport not found"; return }
        func sym<T>(_ n: String, _ t: T.Type) -> T? { dlsym(lib, n).map { unsafeBitCast($0, to: t) } }
        copyChannels = sym("IOReportCopyChannelsInGroup", CopyChannelsFn.self)
        createSub = sym("IOReportCreateSubscription", CreateSubFn.self)
        createSamples = sym("IOReportCreateSamples", CreateSamplesFn.self)
        delta = sym("IOReportCreateSamplesDelta", DeltaFn.self)
        iterate = sym("IOReportIterate", IterateFn.self)
        getGroup = sym("IOReportChannelGetGroup", GetStrFn.self)
        getSub = sym("IOReportChannelGetSubGroup", GetStrFn.self)
        getName = sym("IOReportChannelGetChannelName", GetStrFn.self)
        stateCount = sym("IOReportStateGetCount", StateCountFn.self)
        stateName = sym("IOReportStateGetNameForIndex", StateNameFn.self)
        stateRes = sym("IOReportStateGetResidency", StateResFn.self)
        guard copyChannels != nil, createSub != nil, createSamples != nil, delta != nil, iterate != nil,
              getGroup != nil, getSub != nil, getName != nil, stateCount != nil, stateName != nil, stateRes != nil else {
            loadError = "missing libIOReport symbols"; return
        }
        loadTables()
        subscribe()
    }

    // MARK: - Frequency tables (pmgr)

    private func loadTables() {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleARMIODevice"), &it) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(it) }
        var entry = IOIteratorNext(it)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(it) }
            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &nameBuf)
            guard String(cString: nameBuf) == "pmgr" else { continue }
            for key in ["voltage-states1-sram", "voltage-states5-sram", "voltage-states9"] {
                guard let data = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Data else { continue }
                var list: [Double] = []
                var off = 0
                while off + 8 <= data.count {
                    let f = data.subdata(in: off..<off + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
                    list.append(Self.toMHz(Double(UInt32(littleEndian: f))))
                    off += 8
                }
                tables[key] = list
            }
        }
    }

    private static func toMHz(_ v: Double) -> Double {
        if v > 1e8 { return v / 1e6 }   // Hz (M1–M3)
        if v > 1e5 { return v / 1e3 }   // kHz (M4+)
        return v
    }

    // MARK: - IOReport

    private func subscribe() {
        guard let copyChannels, let createSub else { return }
        var merged: CFMutableDictionary?
        for g in ["CPU Stats", "GPU Stats"] {
            guard let ch = copyChannels(g as CFString, nil, 0, 0, 0)?.takeRetainedValue() else { continue }
            if let m = merged {
                // Merge by appending IOReportChannels arrays.
                let key = "IOReportChannels" as CFString
                if let a = CFDictionaryGetValue(m, Unmanaged.passUnretained(key).toOpaque()),
                   let b = CFDictionaryGetValue(ch, Unmanaged.passUnretained(key).toOpaque()) {
                    let arrA = Unmanaged<CFMutableArray>.fromOpaque(a).takeUnretainedValue()
                    let arrB = Unmanaged<CFArray>.fromOpaque(b).takeUnretainedValue()
                    for i in 0..<CFArrayGetCount(arrB) { CFArrayAppendValue(arrA, CFArrayGetValueAtIndex(arrB, i)) }
                }
            } else { merged = ch }
        }
        guard let merged else { loadError = "no CPU/GPU Stats channels"; return }
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = createSub(nil, merged, &subbed, 0, nil) else { loadError = "IOReportCreateSubscription failed"; return }
        subscription = sub
        channels = merged
    }

    private func takeSample() -> CFDictionary? {
        guard let subscription, let channels, let createSamples else { return nil }
        return createSamples(subscription, channels, nil)?.takeRetainedValue()
    }

    private func parse(_ sample: CFDictionary) -> [Channel] {
        guard let iterate, let getGroup, let getSub, let getName, let stateCount, let stateName, let stateRes else { return [] }
        var out: [Channel] = []
        iterate(sample) { ch in
            let g = getGroup(ch)?.takeUnretainedValue() as String? ?? ""
            let s = getSub(ch)?.takeUnretainedValue() as String? ?? ""
            let n = getName(ch)?.takeUnretainedValue() as String? ?? ""
            let count = stateCount(ch)
            guard count > 0 else { return 0 }
            let states = (0..<count).map { i in
                (name: stateName(ch, i)?.takeUnretainedValue() as String? ?? "", residency: stateRes(ch, i))
            }
            out.append(Channel(group: g, subgroup: s, name: n, states: states))
            return 0
        }
        return out
    }

    /// Average MHz weighted by active-state residency. `table` lists frequencies for the non-idle states in order.
    static func averageMHz(_ ch: Channel, table: [Double]) -> Double? {
        guard !table.isEmpty else { return nil }
        let idle: Set<String> = ["IDLE", "DOWN", "OFF"]
        guard let offset = ch.states.firstIndex(where: { !idle.contains($0.name) }) else { return nil }
        let active = Array(ch.states[offset...])
        var sumRes = 0.0, sumFreq = 0.0
        for (i, st) in active.enumerated() where i < table.count {
            sumRes += Double(st.residency)
            sumFreq += Double(st.residency) * table[i]
        }
        return sumRes > 0 ? sumFreq / sumRes : 0
    }

    func read() -> [MetricID: MetricValue] {
        if let e = loadError { return [.cpuFreq: .unavailable(e), .gpuFreq: .unavailable(e)] }
        guard let cur = takeSample() else {
            return [.cpuFreq: .unavailable("IOReportCreateSamples failed"), .gpuFreq: .unavailable("IOReportCreateSamples failed")]
        }
        defer { previous = cur }
        guard let prev = previous, let delta, let d = delta(prev, cur, nil)?.takeRetainedValue() else {
            return [.cpuFreq: .idle("warming up"), .gpuFreq: .idle("warming up")]
        }
        lastChannels = parse(d)

        let cpuSub = lastChannels.contains { $0.subgroup == "CPU Complex Performance States" }
            ? "CPU Complex Performance States" : "CPU Core Performance States"
        var cpu: [Double] = []
        for ch in lastChannels where ch.subgroup == cpuSub {
            if ch.name.hasPrefix("E"), let f = Self.averageMHz(ch, table: tables["voltage-states1-sram"] ?? []) { cpu.append(f) }
            if ch.name.hasPrefix("P"), let f = Self.averageMHz(ch, table: tables["voltage-states5-sram"] ?? []) { cpu.append(f) }
        }
        var out: [MetricID: MetricValue] = [:]
        out[.cpuFreq] = cpu.max().map { .mhz($0) } ?? .unavailable("no CPU performance-state channel matched")

        let gpu = lastChannels.first { $0.subgroup == "GPU Performance States" }
        if let gpu, let f = Self.averageMHz(gpu, table: Array((tables["voltage-states9"] ?? []).drop(while: { $0 == 0 }))) {
            out[.gpuFreq] = .mhz(f)
        } else {
            out[.gpuFreq] = .unavailable("no GPU performance-state channel matched")
        }
        return out
    }
}
