import Foundation
import SwiftUI

@MainActor
final class AmplifierController: ObservableObject {
    // Settings
    @Published var portPath: String = UserDefaults.standard.string(forKey: "portPath") ?? "" {
        didSet { UserDefaults.standard.set(portPath, forKey: "portPath") }
    }
    @Published var modelID: String = UserDefaults.standard.string(forKey: "model") ?? "700S" {
        didSet { UserDefaults.standard.set(modelID, forKey: "model") }
    }
    @Published var autoConnect: Bool = UserDefaults.standard.object(forKey: "autoConnect") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoConnect, forKey: "autoConnect") }
    }

    // Live state
    @Published var connected = false
    @Published var linkAlive = false
    @Published var demoMode = false
    @Published var lastError: String?
    @Published var ports: [String] = []

    @Published var state: AmpState = .off
    @Published var forward: Double = 0
    @Published var reflected: Double = 0
    @Published var drive: Double = 0
    @Published var swr: Double = 0
    @Published var temperature: Int?
    @Published var fan: Int = 0
    @Published var band: String = "--"
    @Published var efficiency: Double?
    @Published var gainDB: Double?
    @Published var errorText: String?

    var model: AmpModel { AmpModel.named(modelID) }

    private var port: SerialPort?
    private var parser = TelemetryParser()
    private var framesSinceTick = 0
    private var timer: Timer?
    private var demoTimer: Timer?

    // Peak-hold windows (last 10 frames, ≈ 1 s), same as the Windows app.
    private var fwdHist = RingBuffer(10), reflHist = RingBuffer(10)
    private var driveHist = RingBuffer(10), dcHist = RingBuffer(10), swrHist = RingBuffer(10)

    init() {
        refreshPorts()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if autoConnect, !portPath.isEmpty, ports.contains(portPath) { connect() }
    }

    func refreshPorts() { ports = SerialPort.availablePorts() }

    // MARK: Connection

    func connect() {
        disconnect()
        guard !portPath.isEmpty else { lastError = "Choose a serial port in Settings."; return }
        let p = SerialPort(path: portPath)
        p.onData = { [weak self] bytes in
            Task { @MainActor in self?.receive(bytes) }
        }
        p.onClose = { [weak self] in
            Task { @MainActor in
                self?.connected = false
                self?.linkAlive = false
                self?.lastError = "Serial port closed (adapter unplugged?)"
            }
        }
        do {
            try p.open()
            port = p
            connected = true
            lastError = nil
            p.write(ACOMCommand.enableTelemetry)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        if let port, port.isOpen { port.write(ACOMCommand.disableTelemetry) }
        port?.close()
        port = nil
        connected = false
        linkAlive = false
        clearReadings()
    }

    // MARK: Commands

    func operate() { send(ACOMCommand.operate) }
    func standby() { send(ACOMCommand.standby) }
    func powerOff() { send(ACOMCommand.off) }

    /// Remote power-on: the amp's remote-on input is driven from the RS-232
    /// DTR/RTS lines. Pulse them high for a second, then return them low so the
    /// front-panel power button isn't blocked. Needs a cable that wires those pins.
    func powerOn() {
        guard let port else { return }
        port.setModemLines(dtr: true, rts: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.port?.setModemLines(dtr: false, rts: false)
            self?.port?.write(ACOMCommand.enableTelemetry)
        }
    }

    /// Dismiss a warning: the amp drops to standby on most faults, Operate resumes.
    func acknowledgeError() { errorText = nil; operate() }

    private func send(_ cmd: [UInt8]) {
        if demoMode { demoApply(cmd); return }
        port?.write(cmd)
    }

    // MARK: Telemetry

    private func receive(_ bytes: [UInt8]) {
        for t in parser.feed(bytes) { apply(t) }
    }

    private func apply(_ t: Telemetry) {
        framesSinceTick += 1
        linkAlive = true
        state = t.state
        guard t.state != .off else { clearReadings(keepState: true); return }

        fwdHist.push(t.forwardWatts)
        reflHist.push(t.reflectedWatts)
        driveHist.push(t.driveWatts)
        dcHist.push(t.dcInputWatts)
        swrHist.push(t.swr)

        forward = fwdHist.max
        reflected = reflHist.max
        drive = driveHist.max
        let swrs = swrHist.values.filter { $0 > 0 }
        swr = swrs.isEmpty ? 0 : swrs.reduce(0, +) / Double(swrs.count)

        temperature = t.temperatureRaw - model.temperatureOffset
        fan = t.fan
        band = t.bandName

        let eff = dcHist.max > 0 ? 100 * forward / dcHist.max : 0
        efficiency = (eff > 20 && eff < 80 && forward > 50) ? eff : nil
        gainDB = (drive > 1 && forward > 100) ? 10 * log10(forward / drive) : nil

        errorText = t.errorText
    }

    private func tick() {
        if demoMode { return }
        if framesSinceTick == 0 {
            if linkAlive { linkAlive = false; clearReadings() }
            // There's no way to ask whether telemetry is on, so keep requesting it.
            port?.write(ACOMCommand.enableTelemetry)
        }
        framesSinceTick = 0
    }

    private func clearReadings(keepState: Bool = false) {
        if !keepState { state = .off }
        forward = 0; reflected = 0; drive = 0; swr = 0
        temperature = nil; fan = 0; band = "--"; efficiency = nil; gainDB = nil
        fwdHist.clear(); reflHist.clear(); driveHist.clear(); dcHist.clear(); swrHist.clear()
    }

    // MARK: Demo mode (no amplifier needed)

    private var demoState: AmpState = .standby
    private var demoPhase = 0.0

    func setDemo(_ on: Bool) {
        demoMode = on
        demoTimer?.invalidate()
        if on {
            disconnect()
            demoState = .standby
            demoTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.demoFrame() }
            }
        } else {
            clearReadings()
        }
    }

    private func demoApply(_ cmd: [UInt8]) {
        if cmd == ACOMCommand.operate { demoState = .receive }
        if cmd == ACOMCommand.standby { demoState = .standby }
        if cmd == ACOMCommand.off { demoState = .off }
    }

    /// Builds a real 72-byte frame and runs it through the parser, so demo mode
    /// also exercises the decoder.
    private func demoFrame() {
        demoPhase += 0.1
        var s = demoState
        let keyed = demoState == .receive && sin(demoPhase * 0.7) > 0.2
        if keyed { s = .transmit }
        let fwd = keyed ? 650 + 50 * sin(demoPhase * 5) : 0
        var f = [UInt8](repeating: 0, count: TelemetryParser.frameLength)
        func put16(_ i: Int, _ v: Int) { f[i] = UInt8(v & 0xFF); f[i + 1] = UInt8((v >> 8) & 0xFF) }
        f[0] = 0x55; f[1] = 0x2F; f[2] = 0x48
        f[3] = UInt8(s.rawValue << 4)
        let dc = keyed ? fwd / 0.55 : 40
        f[8] = UInt8(Int(dc * 10) % 256); f[9] = UInt8(Int(dc * 10) / 256)
        put16(16, model.temperatureOffset + 38 + Int(keyed ? 6 : 0))
        put16(20, keyed ? 450 : 0)
        put16(22, Int(fwd))
        put16(24, keyed ? Int(fwd * 0.012) : 0)
        put16(26, keyed ? 125 : 0)
        f[66] = 0xFF
        f[69] = UInt8(((keyed ? 2 : 1) << 4) | 5)       // fan, 20 m
        let sum = f[0..<71].reduce(UInt8(0)) { $0 &+ $1 }
        f[71] = 0 &- sum
        receive(f)
    }
}

struct RingBuffer {
    private(set) var values: [Double]
    private var i = 0
    init(_ n: Int) { values = Array(repeating: 0, count: n) }
    mutating func push(_ v: Double) { values[i] = v; i = (i + 1) % values.count }
    mutating func clear() { values = Array(repeating: 0, count: values.count) }
    var max: Double { values.max() ?? 0 }
}
