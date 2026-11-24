import Foundation

final class TemperatureSource: MetricSource {
    // M1 SMC keys (from exelban/stats, values.swift)
    // Apple Silicon keys (exelban/stats) followed by Intel keys (untested here); only keys that exist respond.
    static let cpuKeys = ["Tp01", "Tp05", "Tp09", "Tp0T", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b",
                          "TC0P", "TC0D", "TC0E", "TC0F", "TC0H"]
    static let gpuKeys = ["Tg05", "Tg0D", "Tg0L", "Tg0T", "TG0P", "TG0D", "TGDD", "TGDP"]

    let ids: [MetricID] = [.cpuTemp, .gpuTemp]

    func read() -> [MetricID: MetricValue] {
        var out: [MetricID: MetricValue] = [:]

        if let c = average(Self.cpuKeys) {
            out[.cpuTemp] = .temperature(c)
        } else if let h = hid(prefixes: ["pACC MTR Temp", "eACC MTR Temp"]) ?? hid(prefixes: ["PMU tdie"]) {
            out[.cpuTemp] = .temperature(h)
        } else {
            out[.cpuTemp] = .unavailable("no SMC Tp* key or HID pACC/eACC/PMU tdie sensor responded")
        }

        if let g = average(Self.gpuKeys) {
            out[.gpuTemp] = .temperature(g)
        } else if let h = hid(prefixes: ["GPU MTR Temp"], ignoring: 30.0) {
            out[.gpuTemp] = .temperature(h)
        } else {
            // Powered-down GPU blocks report a constant 30.0 °C placeholder: supported, but idle.
            let hasGPUSensor = HIDSensors.shared.readAll().contains { $0.name.hasPrefix("GPU MTR Temp") }
            out[.gpuTemp] = hasGPUSensor ? .idle("GPU idle (sensors report 30.0 placeholder)")
                                         : .unavailable("no SMC Tg* key or HID GPU MTR sensor")
        }
        return out
    }

    /// Mean of HID sensors whose Product name starts with one of the prefixes (valid range only).
    private func hid(prefixes: [String], ignoring sentinel: Double? = nil) -> Double? {
        let v = HIDSensors.shared.readAll()
            .filter { s in prefixes.contains { s.name.hasPrefix($0) } }
            .map(\.value).filter { $0 >= 10 && $0 <= 120 && $0 != sentinel }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    private func average(_ keys: [String]) -> Double? {
        let vals = keys.compactMap { SMC.shared.readFloat($0) }.filter { $0 >= 10 && $0 <= 120 }
        return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
    }
}
