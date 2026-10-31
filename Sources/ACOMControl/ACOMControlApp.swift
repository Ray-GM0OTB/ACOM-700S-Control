import SwiftUI
import AppKit

@main
struct ACOMControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var amp = AmplifierController()
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false

    var body: some Scene {
        Window("ACOM Control", id: "main") {
            ContentView()
                .environmentObject(amp)
                .onAppear { applyFloating(); appDelegate.amp = amp }
                .onChange(of: alwaysOnTop) { _ in applyFloating() }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Amplifier") {
                Button("Operate") { amp.operate() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Standby") { amp.standby() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Power Off") { amp.powerOff() }
                Divider()
                Toggle("Demo Mode", isOn: Binding(get: { amp.demoMode }, set: { amp.setDemo($0) }))
                Toggle("Keep Window on Top", isOn: $alwaysOnTop)
            }
        }

        Settings {
            SettingsView().environmentObject(amp)
        }
    }

    private func applyFloating() {
        DispatchQueue.main.async {
            for w in NSApp.windows where w.title == "ACOM Control" {
                w.level = alwaysOnTop ? .floating : .normal
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var amp: AmplifierController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Turn telemetry off on the way out, as the original Windows app does.
    func applicationWillTerminate(_ notification: Notification) {
        amp?.disconnect()
    }
}

struct SettingsView: View {
    @EnvironmentObject var amp: AmplifierController

    var body: some View {
        Form {
            Picker("Amplifier model", selection: $amp.modelID) {
                ForEach(AmpModel.all) { Text("ACOM \($0.id)").tag($0.id) }
            }
            HStack {
                Picker("Serial port", selection: $amp.portPath) {
                    Text("Choose…").tag("")
                    ForEach(amp.ports, id: \.self) { Text($0).tag($0) }
                }
                Button("Rescan") { amp.refreshPorts() }
            }
            Toggle("Connect automatically at launch", isOn: $amp.autoConnect)
            Text("9600 baud, 8N1, no handshake. DTR and RTS are held low.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 460)
    }
}
