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
    @ObservedObject private var commander = Commander.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Activity Logger").font(.headline)

            if state.isRunning, let next = state.nextFire {
                let time = next.formatted(date: .omitted, time: .shortened)
                Text(Calendar.current.isDateInToday(next) ? "Next check-in at \(time)"
                     : Calendar.current.isDateInTomorrow(next) ? "Next check-in tomorrow at \(time)"
                     : "Next check-in \(next.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundColor(.secondary)
            } else {
                Text("Paused").foregroundColor(.secondary)
            }

            Stepper("Every \(state.intervalMinutes) min", value: $state.intervalMinutes, in: 1...180)
            Picker("Day starts", selection: $state.dayStartHour) {
                ForEach(0..<state.dayEndHour, id: \.self) { Text(Self.hourName($0)).tag($0) }
            }
            Picker("Day ends", selection: $state.dayEndHour) {
                ForEach((state.dayStartHour + 1)...24, id: \.self) { Text(Self.hourName($0)).tag($0) }
            }
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
            HStack {
                Toggle("Commander voice", isOn: $state.commanderVoice)
                Spacer()
                Button {
                    Commander.shared.shout {}
                } label: { Image(systemName: "speaker.wave.2.fill") }
                .help("Test the commander voice")
            }
            HStack {
                Button(commander.clipURL == nil ? "Use my own clip…" : "Change clip…") {
                    commander.chooseClip()
                }
                if commander.clipURL != nil {
                    Button("Use built-in voice") { commander.removeClip() }
                }
            }
            .controlSize(.small)
            .disabled(!state.commanderVoice)
            Toggle("Pause videos & music during check-ins", isOn: $state.pauseMedia)
            Toggle("Auto-save when I stop talking", isOn: $state.autoSave)
            Toggle("Launch at login", isOn: $state.launchAtLogin)

            Divider()

            Button(state.isRunning ? "Pause timer" : "Start timer") {
                state.isRunning ? state.pause() : state.start()
            }
            Button("Check in now") {
                WindowManager.shared.showPrompt()
            }
            Button("Show log") { WindowManager.shared.showLog() }

            Divider()

            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 270)
    }

    /// 0 → "12 AM", 15 → "3 PM", 24 → "Midnight"
    private static func hourName(_ hour: Int) -> String {
        if hour == 24 { return "Midnight" }
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
        return AppState.hourFormatter.string(from: date)
    }
}
