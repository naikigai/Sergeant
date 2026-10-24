import SwiftUI

@main
struct ActivityLoggerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
        } label: {
            Image(systemName: state.isRunning ? "waveform.circle.fill" : "waveform.circle")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SpeechRecorder.requestPermissions()
        AppState.shared.startIfNeeded()
    }
}

struct MenuView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity Logger").font(.headline)

            if state.isRunning, let next = state.nextFire {
                Text("Next check-in at \(next.formatted(date: .omitted, time: .shortened))")
                    .foregroundColor(.secondary)
            } else {
                Text("Paused").foregroundColor(.secondary)
            }

            Stepper("Every \(state.intervalMinutes) min", value: $state.intervalMinutes, in: 1...180)
            HStack {
                Picker("Sound", selection: $state.soundName) {
                    ForEach(AppState.sounds, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: state.soundName) { name in Chime.play(name, repeats: 1) }
                Button {
                    Chime.play(state.soundName, repeats: state.soundRepeats)
                } label: { Image(systemName: "speaker.wave.2.fill") }
                .help("Test the chime")
            }
            Stepper("Play sound \(state.soundRepeats)×", value: $state.soundRepeats, in: 1...10)
            Toggle("Auto-save when I stop talking", isOn: $state.autoSave)
            Toggle("Launch at login", isOn: $state.launchAtLogin)

            Divider()

            Button(state.isRunning ? "Pause timer" : "Start timer") {
                state.isRunning ? state.pause() : state.start()
            }
            Button("Check in now") {
                WindowManager.shared.showPrompt()
                if state.isRunning { state.start() } // restart countdown from now
            }
            Button("Show log") { WindowManager.shared.showLog() }

            Divider()

            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 270)
    }
}
