import Foundation

enum MetricID: String, CaseIterable, Codable {
    case cpuTemp, gpuTemp, fanRPM, cpuFreq, gpuFreq, cpuUsage
    case disk, memory, memPressure, battery
    case diskRead, diskWrite, netDown, netUp

    /// Shown on a fresh install; the rest can be enabled in Preferences.
    static let defaultWidgets: [MetricID] = [.cpuTemp, .gpuTemp, .fanRPM, .cpuFreq, .gpuFreq, .disk, .memory, .battery]
}

enum MetricValue {
    case temperature(Double)
    case rpm(Double)
    case mhz(Double)
    case rate(Double)   // bytes per second
    case percent(used: Double, total: Double, unit: String)
    /// Supported by this Mac but no reading right now (GPU powered down, first sample pending).
    case idle(String)
    /// Not supported by this Mac: hidden from the Touch Bar and the menu.
    case unavailable(String)
}

protocol MetricSource {
    var ids: [MetricID] { get }
    func read() -> [MetricID: MetricValue]
}
