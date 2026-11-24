import IOKit
import Darwin

// Minimal AppleSMC client. The struct uses nested types so Swift reproduces the
// C layout of SMCKeyData_t exactly (80 bytes); `SMC.layoutSize` is printed by --probe.

struct SMCKeyData {
    struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
    struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0; var dataAttributes: UInt8 = 0; var pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    typealias Bytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )
    var key: UInt32 = 0
    var vers = Version()
    var pLimit = PLimit()
    var keyInfo = KeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
                        0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

final class SMC {
    static let shared = SMC()
    static var layoutSize: Int { MemoryLayout<SMCKeyData>.size }

    private var conn: io_connect_t = 0
    private(set) var connected = false

    private init() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return }
        defer { IOObjectRelease(svc) }
        connected = IOServiceOpen(svc, mach_task_self_, 0, &conn) == kIOReturnSuccess
    }

    struct Raw { let type: UInt32; let bytes: [UInt8] }

    static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    func read(_ key: String) -> Raw? {
        guard connected else { return nil }
        var input = SMCKeyData()
        var output = SMCKeyData()
        var size = MemoryLayout<SMCKeyData>.size

        input.key = SMC.fourCC(key)
        input.data8 = 9   // kSMCGetKeyInfo
        guard IOConnectCallStructMethod(conn, 2, &input, size, &output, &size) == kIOReturnSuccess,
              output.result == 0 else { return nil }

        let dataSize = output.keyInfo.dataSize
        let dataType = output.keyInfo.dataType
        input.keyInfo.dataSize = dataSize
        input.data8 = 5   // kSMCReadKey
        size = MemoryLayout<SMCKeyData>.size
        guard IOConnectCallStructMethod(conn, 2, &input, size, &output, &size) == kIOReturnSuccess,
              output.result == 0 else { return nil }

        let n = min(Int(dataSize), 32)
        let bytes = withUnsafeBytes(of: output.bytes) { Array($0.prefix(n)) }
        return Raw(type: dataType, bytes: bytes)
    }

    func readFloat(_ key: String) -> Double? {
        guard let r = read(key), !r.bytes.isEmpty else { return nil }
        let b = r.bytes
        switch r.type {
        case SMC.fourCC("flt "):
            guard b.count >= 4 else { return nil }
            // Apple Silicon SMC returns flt in native (little-endian) order.
            let bits = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
            let f = Float(bitPattern: bits)
            return f.isFinite ? Double(f) : nil
        case SMC.fourCC("sp78"):
            guard b.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256.0
        case SMC.fourCC("ui8 "):
            return Double(b[0])
        case SMC.fourCC("ui16"):
            guard b.count >= 2 else { return nil }
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case SMC.fourCC("ui32"):
            guard b.count >= 4 else { return nil }
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        default:
            return nil
        }
    }
}
