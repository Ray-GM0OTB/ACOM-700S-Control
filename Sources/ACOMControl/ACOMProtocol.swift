import Foundation

/// ACOM solid-state amplifier remote protocol (500S / 600S / 700S / 1200S / 2020S).
/// RS-232, 9600 baud, 8N1, no handshake. Every datagram starts with 0x55 and all
/// bytes (including the trailing checksum) sum to 0 modulo 256.
///
/// Byte layout of the 72-byte telemetry frame is taken from Björn Ekelund SM7IUN's
/// MIT-licensed ACOM Controller (github.com/bjornekelund/ACOM-Controller).
enum ACOMCommand {
    static let enableTelemetry:  [UInt8] = [0x55, 0x92, 0x04, 0x15]
    static let disableTelemetry: [UInt8] = [0x55, 0x91, 0x04, 0x16]
    static let operate: [UInt8] = [0x55, 0x81, 0x08, 0x02, 0x00, 0x06, 0x00, 0x1A]
    static let standby: [UInt8] = [0x55, 0x81, 0x08, 0x02, 0x00, 0x05, 0x00, 0x1B]
    static let off:     [UInt8] = [0x55, 0x81, 0x08, 0x02, 0x00, 0x0A, 0x00, 0x16]
}

enum AmpState: Int {
    case unknown = 0, reset = 1, initialising = 2, debug = 3, service = 4
    case standby = 5, receive = 6, transmit = 7, system = 9, off = 10

    var label: String {
        switch self {
        case .unknown: return "UNKNOWN"
        case .reset: return "RESET"
        case .initialising: return "INIT"
        case .debug: return "DEBUG"
        case .service: return "SERVICE"
        case .standby: return "STANDBY"
        case .receive: return "OPERATE"
        case .transmit: return "TRANSMIT"
        case .system: return "SYSTEM"
        case .off: return "OFF"
        }
    }
}

struct Telemetry {
    var state: AmpState
    var temperatureRaw: Int      // subtract model offset to get °C
    var fan: Int                 // 0 = off, 1…4
    var driveWatts: Double
    var forwardWatts: Double
    var reflectedWatts: Double
    var swr: Double
    var dcInputWatts: Double
    var bandIndex: Int
    var errorCode: UInt8         // 0xFF = no error

    static let bandNames = ["?", "160m", "80m", "40/60m", "30m", "20m",
                            "17m", "15m", "12m", "10m", "6m", "4m", "?", "?", "?", "?"]
    var bandName: String { Telemetry.bandNames[bandIndex & 0x0F] }

    var errorText: String? {
        switch errorCode {
        case 0xFF: return nil
        case 0x00, 0x08: return "Hot switching"
        case 0x03: return "Drive power at wrong time"
        case 0x04, 0x05: return "Reflected power warning"
        case 0x06, 0x07: return "Drive power too high"
        case 0x0C: return "RF power at wrong time"
        case 0x0E: return "Stop transmission first"
        case 0x0F: return "Remove drive power"
        case 0x24, 0x25, 0x39, 0x44, 0x45, 0x59: return "Excessive PAM current"
        case 0x70: return "CAT error"
        default: return String(format: "Error 0x%02X – see amplifier display", errorCode)
        }
    }

    init?(frame b: [UInt8]) {
        guard b.count == TelemetryParser.frameLength, b[0] == 0x55, b[1] == 0x2F else { return nil }
        func u16(_ i: Int) -> Int { Int(b[i]) | (Int(b[i + 1]) << 8) }
        state = AmpState(rawValue: Int(b[3] >> 4)) ?? .unknown
        dcInputWatts = Double(b[8]) * 0.1 + Double(b[9]) * 25.6
        temperatureRaw = u16(16)
        driveWatts = Double(u16(20)) / 10.0
        forwardWatts = Double(u16(22))
        reflectedWatts = Double(u16(24))
        swr = Double(u16(26)) / 100.0
        errorCode = b[66]
        fan = Int(b[69] >> 4)
        bandIndex = Int(b[69] & 0x0F)
    }
}

/// Byte-stream reassembler: feed it whatever the serial port delivers and it
/// returns every complete, checksum-valid telemetry frame it found.
struct TelemetryParser {
    static let frameLength = 72
    private var buffer: [UInt8] = []

    mutating func feed(_ bytes: [UInt8]) -> [Telemetry] {
        buffer.append(contentsOf: bytes)
        var out: [Telemetry] = []
        while true {
            // Drop anything before a start byte.
            guard let start = buffer.firstIndex(of: 0x55) else { buffer.removeAll(); break }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 2 else { break }
            if buffer[1] != 0x2F { buffer.removeFirst(); continue }   // not telemetry
            guard buffer.count >= Self.frameLength else { break }
            let frame = Array(buffer[0..<Self.frameLength])
            let sum = frame.reduce(UInt8(0)) { $0 &+ $1 }
            if sum == 0, let t = Telemetry(frame: frame) {
                out.append(t)
                buffer.removeFirst(Self.frameLength)
            } else {
                buffer.removeFirst()   // false sync – resync on next 0x55
            }
        }
        if buffer.count > 4096 { buffer.removeAll() }
        return out
    }
}

struct AmpModel: Identifiable, Hashable {
    let id: String
    let nominalForward: Double
    let maxForward: Double
    let nominalReflected: Double
    let maxReflected: Double
    let temperatureOffset: Int

    static let all: [AmpModel] = [
        AmpModel(id: "500S",  nominalForward: 500,  maxForward: 600,  nominalReflected: 99,  maxReflected: 130, temperatureOffset: 282),
        AmpModel(id: "600S",  nominalForward: 600,  maxForward: 700,  nominalReflected: 114, maxReflected: 150, temperatureOffset: 273),
        AmpModel(id: "700S",  nominalForward: 700,  maxForward: 800,  nominalReflected: 129, maxReflected: 170, temperatureOffset: 282),
        AmpModel(id: "1200S", nominalForward: 1200, maxForward: 1400, nominalReflected: 228, maxReflected: 300, temperatureOffset: 281),
        AmpModel(id: "2020S", nominalForward: 1800, maxForward: 2000, nominalReflected: 228, maxReflected: 300, temperatureOffset: 282),
    ]
    static func named(_ id: String) -> AmpModel { all.first { $0.id == id } ?? all[2] }
}
