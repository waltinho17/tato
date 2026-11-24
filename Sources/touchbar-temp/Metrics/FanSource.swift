import Foundation

final class FanSource: MetricSource {
    let ids: [MetricID] = [.fanRPM]

    struct Fan { let index: Int; let current: Double; let min: Double?; let max: Double? }

    func fans() -> [Fan] {
        guard let n = SMC.shared.readFloat("FNum"), n >= 1 else { return [] }
        return (0..<Int(n)).compactMap { i in
            guard let ac = SMC.shared.readFloat("F\(i)Ac") else { return nil }
            return Fan(index: i, current: ac,
                       min: SMC.shared.readFloat("F\(i)Mn"),
                       max: SMC.shared.readFloat("F\(i)Mx"))
        }
    }

    func read() -> [MetricID: MetricValue] {
        guard let top = fans().map(\.current).max() else {
            return [.fanRPM: .unavailable("no fan reported by SMC (FNum/F0Ac)")]
        }
        return [.fanRPM: .rpm(top)]
    }
}
