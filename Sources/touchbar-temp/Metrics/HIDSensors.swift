import IOKit
import Darwin
import Foundation

// Apple Silicon HID temperature sensors via IOHIDEventSystemClient (private, loaded with dlsym).

final class HIDSensors {
    static let shared = HIDSensors()

    private typealias CreateFn      = @convention(c) (CFAllocator?) -> UnsafeRawPointer?
    private typealias SetMatchingFn = @convention(c) (UnsafeRawPointer, CFDictionary) -> Void
    private typealias CopyServicesFn = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFArray>?
    private typealias CopyEventFn   = @convention(c) (UnsafeRawPointer, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn    = @convention(c) (UnsafeRawPointer, Int32) -> Double
    private typealias CopyPropFn    = @convention(c) (UnsafeRawPointer, CFString) -> Unmanaged<AnyObject>?

    private var client: UnsafeRawPointer?
    private var copyServices: CopyServicesFn?
    private var copyEvent: CopyEventFn?
    private var getFloat: GetFloatFn?
    private var copyProp: CopyPropFn?

    private init() {
        let lib = dlopen(nil, RTLD_LAZY)
        guard
            let pCreate = dlsym(lib, "IOHIDEventSystemClientCreate"),
            let pMatch  = dlsym(lib, "IOHIDEventSystemClientSetMatching"),
            let pSvcs   = dlsym(lib, "IOHIDEventSystemClientCopyServices"),
            let pEvt    = dlsym(lib, "IOHIDServiceClientCopyEvent"),
            let pFlt    = dlsym(lib, "IOHIDEventGetFloatValue"),
            let pProp   = dlsym(lib, "IOHIDServiceClientCopyProperty")
        else { return }

        let create = unsafeBitCast(pCreate, to: CreateFn.self)
        let setMatching = unsafeBitCast(pMatch, to: SetMatchingFn.self)
        copyServices = unsafeBitCast(pSvcs, to: CopyServicesFn.self)
        copyEvent    = unsafeBitCast(pEvt, to: CopyEventFn.self)
        getFloat     = unsafeBitCast(pFlt, to: GetFloatFn.self)
        copyProp     = unsafeBitCast(pProp, to: CopyPropFn.self)

        guard let c = create(kCFAllocatorDefault) else { return }
        setMatching(c, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 0x0005] as CFDictionary)
        client = c
    }

    var available: Bool { client != nil }

    /// All temperature sensors as (Product name, °C). Values outside 1...150 are dropped.
    func readAll() -> [(name: String, value: Double)] {
        guard let client, let copyServices, let copyEvent, let getFloat, let copyProp,
              let services = copyServices(client)?.takeRetainedValue() else { return [] }
        var out: [(String, Double)] = []
        for i in 0..<CFArrayGetCount(services) {
            guard let raw = CFArrayGetValueAtIndex(services, i) else { continue }
            let svc = raw
            guard let event = copyEvent(svc, 15, 0, 0)?.takeRetainedValue() else { continue }
            let evtPtr = UnsafeRawPointer(Unmanaged.passUnretained(event).toOpaque())
            let temp = getFloat(evtPtr, Int32(15) << 16)
            guard temp > 1, temp < 150 else { continue }
            let name = (copyProp(svc, "Product" as CFString)?.takeRetainedValue() as? String) ?? "?"
            out.append((name, temp))
        }
        return out
    }
}
