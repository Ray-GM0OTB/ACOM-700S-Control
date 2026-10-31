import SwiftUI

struct ContentView: View {
    @EnvironmentObject var amp: AmplifierController

    var body: some View {
        VStack(spacing: 14) {
            header
            if let err = amp.errorText { errorBanner(err) }
            meters
            readouts
            controls
            footer
        }
        .padding(16)
        .frame(minWidth: 460, idealWidth: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Header – model + big state lamp

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ACOM \(amp.model.id)").font(.title2.weight(.semibold))
                Text(amp.demoMode ? "Demo mode" : linkText)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(amp.state.label)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(stateColor.opacity(0.18), in: Capsule())
                .overlay(Capsule().stroke(stateColor, lineWidth: 1.5))
                .foregroundStyle(stateColor)
                .animation(.easeOut(duration: 0.15), value: amp.state)
        }
    }

    private var linkText: String {
        if !amp.connected { return amp.lastError ?? "Not connected" }
        let name = (amp.portPath as NSString).lastPathComponent
        return amp.linkAlive ? "\(name) · telemetry OK" : "\(name) · waiting for amplifier…"
    }

    private var stateColor: Color {
        switch amp.state {
        case .transmit: return .red
        case .receive: return .green
        case .standby: return .orange
        case .off, .unknown: return .gray
        default: return .blue
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).fontWeight(.medium)
            Spacer()
            Button("Clear & Operate") { amp.acknowledgeError() }
        }
        .padding(10)
        .background(Color.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.red)
    }

    // MARK: Bar meters

    private var meters: some View {
        VStack(spacing: 10) {
            BarMeter(label: "Output", value: amp.forward, nominal: amp.model.nominalForward,
                     max: amp.model.maxForward, unit: "W", tint: .accentColor)
            BarMeter(label: "Reflected", value: amp.reflected, nominal: amp.model.nominalReflected,
                     max: amp.model.maxReflected, unit: "W", tint: .gray)
            BarMeter(label: "PA temp", value: Double(amp.temperature ?? 0), nominal: 65,
                     max: 100, unit: "°C", tint: .green, showValue: amp.temperature != nil)
        }
    }

    // MARK: Numeric readouts

    private var readouts: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Readout(title: "Drive", value: amp.linkAlive ? String(format: "%.0f W", amp.drive) : "--")
                Readout(title: "SWR", value: amp.swr > 0 && amp.forward > 0 ? String(format: "%.2f", amp.swr) : "--")
                Readout(title: "Band", value: amp.band)
            }
            GridRow {
                Readout(title: "Gain", value: amp.gainDB.map { String(format: "%.0f dB", $0) } ?? "--")
                Readout(title: "Efficiency", value: amp.efficiency.map { String(format: "%.0f %%", $0) } ?? "--")
                Readout(title: "Fan", value: amp.fan > 0 ? "\(amp.fan)" : "Off")
            }
        }
    }

    // MARK: Control buttons

    private var controls: some View {
        let live = amp.connected || amp.demoMode
        return HStack(spacing: 10) {
            Button { amp.operate() } label: { Label("Operate", systemImage: "bolt.fill").frame(maxWidth: .infinity) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .tint(.green)
            Button { amp.standby() } label: { Label("Standby", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .tint(.orange)
            Button(role: .destructive) { amp.powerOff() } label: { Label("Off", systemImage: "power.circle") }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!live)
    }

    private var footer: some View {
        HStack {
            Picker("Port", selection: $amp.portPath) {
                Text("Choose…").tag("")
                ForEach(amp.ports, id: \.self) { Text(($0 as NSString).lastPathComponent).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
            Button { amp.refreshPorts() } label: { Image(systemName: "arrow.clockwise") }
                .help("Rescan serial ports")
            Spacer()
            if amp.connected {
                Button("Disconnect") { amp.disconnect() }
            } else {
                Button("Connect") { amp.setDemo(false); amp.connect() }
                    .disabled(amp.portPath.isEmpty)
            }
        }
        .controlSize(.small)
    }
}

struct BarMeter: View {
    let label: String
    let value: Double
    let nominal: Double
    let max: Double
    let unit: String
    let tint: Color
    var showValue = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(showValue ? "\(Int(value.rounded())) \(unit)" : "-- \(unit)")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(value > nominal ? .red : .primary)
            }
            GeometryReader { g in
                let w = g.size.width
                let nomX = w * nominal / max
                let fill = w * Swift.min(value, max) / max
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15))
                    Rectangle().fill(Color.red.opacity(0.12))
                        .frame(width: w - nomX).offset(x: nomX)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(value > nominal ? Color.red : tint)
                        .frame(width: fill)
                        .animation(.linear(duration: 0.1), value: fill)
                    Rectangle().fill(Color.secondary.opacity(0.6)).frame(width: 1).offset(x: nomX)
                }
            }
            .frame(height: 14)
        }
    }
}

struct Readout: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .monospaced).weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
