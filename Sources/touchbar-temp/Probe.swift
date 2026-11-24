import AppKit

// `touchbar-temp --probe`: print every raw reading to the terminal and exit.

private func fmt(_ v: MetricValue?) -> String {
    switch v {
    case .temperature(let t)?: return String(format: "%.1f °C", t)
    case .rpm(let r)?: return String(format: "%.0f rpm", r)
    case .mhz(let m)?: return String(format: "%.0f MHz", m)
    case .rate(let r)?: return MetricStyle.rate(r)
    case .percent(let u, let t, let unit)?: return String(format: "%.1f / %.1f %@ (%.0f%%)", u, t, unit, t > 0 ? u / t * 100 : 0)
    case .idle(let why)?: return "idle — \(why)"
    case .unavailable(let why)?: return "unavailable — \(why)"
    case nil: return "(no value)"
    }
}

func runProbe() {
    print("== Touch Bar private API ==")
    print("  DFR functions (control strip presence, close box): \(PrivateTouchBar.functionsAvailable)")
    for (cls, sel) in [(NSTouchBarItem.self as AnyClass, "addSystemTrayItem:"),
                       (NSTouchBar.self as AnyClass, "presentSystemModalTouchBar:systemTrayItemIdentifier:"),
                       (NSTouchBar.self as AnyClass, "minimizeSystemModalTouchBar:")] {
        print("  +[\(cls) \(sel)]: \(class_getClassMethod(cls, NSSelectorFromString(sel)) != nil)")
    }

    print("\n== SMC ==")
    print("SMCKeyData size: \(SMC.layoutSize) bytes (expected 80), connected: \(SMC.shared.connected)")
    for key in TemperatureSource.cpuKeys + TemperatureSource.gpuKeys {
        print("  \(key): \(SMC.shared.readFloat(key).map { String(format: "%.1f", $0) } ?? "-")")
    }

    print("\n== HID temperature sensors (available: \(HIDSensors.shared.available)) ==")
    for s in HIDSensors.shared.readAll().sorted(by: { $0.name < $1.name }) {
        print(String(format: "  %-28@ %.1f °C", s.name as NSString, s.value))
    }

    print("\n== Fans ==")
    let fan = FanSource()
    print("  FNum: \(SMC.shared.readFloat("FNum").map { String(Int($0)) } ?? "-")")
    for f in fan.fans() {
        print("  fan \(f.index): \(Int(f.current)) rpm (min \(f.min.map { String(Int($0)) } ?? "-"), max \(f.max.map { String(Int($0)) } ?? "-"))")
    }

    print("\n== Frequency (IOReport) ==")
    let freq = FrequencySource()
    if let e = freq.loadError { print("  load error: \(e)") }
    for (k, v) in freq.tables.sorted(by: { $0.key < $1.key }) {
        print("  table \(k): \(v.map { String(Int($0)) }.joined(separator: ","))")
    }
    _ = freq.read()                       // prime: first sample has no delta
    Thread.sleep(forTimeInterval: 2)
    let f = freq.read()
    print("  cpuFreq: \(fmt(f[.cpuFreq]))")
    print("  gpuFreq: \(fmt(f[.gpuFreq]))")
    print("  channels seen in last delta:")
    for ch in freq.lastChannels {
        let names = ch.states.map { $0.name }.joined(separator: ",")
        print("    [\(ch.group) / \(ch.subgroup)] \(ch.name): \(names)")
    }

    print("\n== Processes (top CPU / top memory, current user) ==")
    let ps = ProcessSampler()
    ps.sample(); Thread.sleep(forTimeInterval: 1); ps.sample()
    for e in ps.topCPU() { print(String(format: "  CPU  %-28@ %.1f%%", e.name as NSString, e.cpu)) }
    for e in ps.topMemory() { print(String(format: "  RAM  %-28@ %.2f GB", e.name as NSString, Double(e.memory) / 1_073_741_824)) }

    print("\n== Claude (local logs) ==")
    let claudeSrc = ClaudeUsageSource()
    claudeSrc.refresh()
    let cs = claudeSrc.summary()
    print("  5h: \(ClaudeFormat.tokens(cs.tokens5h)) · today: \(ClaudeFormat.tokens(cs.tokensToday)) · 7d: \(ClaudeFormat.tokens(cs.tokens7d)) · responses today: \(cs.messagesToday)")

    print("\n== Aggregated metrics ==")
    let engine = MetricsEngine()
    engine.tick()
    Thread.sleep(forTimeInterval: 2)
    engine.tick()
    for id in MetricID.allCases { print("  \(id.rawValue): \(fmt(engine.snapshot[id]))") }
    if let b = engine.system.batteryDetails {
        print("  battery details: health \(b.health.map { String(format: "%.0f%%", $0) } ?? "-"), cycles \(b.cycles.map(String.init) ?? "-"), charging \(b.charging), plugged \(b.pluggedIn), minutes \(b.minutesRemaining.map(String.init) ?? "-")")
    }
    print("  cpu clusters: E \(engine.cpuUsage.efficiencyUsage.map { String(format: "%.0f%%", $0) } ?? "-"), P \(engine.cpuUsage.performanceUsage.map { String(format: "%.0f%%", $0) } ?? "-"), cores \(engine.cpuUsage.perCore.count)")
}
