import AppKit
import SwiftUI

final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var promptWindow: NSWindow?
    private var recorder: SpeechRecorder?
    private var logWindow: NSWindow?

    // MARK: Check-in prompt

    /// Shouts this many times in total before it stops nagging and just listens.
    private static let maxShouts = 5

    /// Opens a check-in. With `commander` on, the app shouts "Soldier! Update!" instead of
    /// the chime and repeats it if you don't start talking within 2 s; after you save it
    /// says "Focus, soldier!". `announcement` (e.g. "1 hour is up") is spoken once and
    /// shown in the window. The app and the mic take turns, so the mic never hears the app.
    func showPrompt(announcement: String? = nil, commander: Bool = false) {
        if let w = promptWindow { // previous check-in still open
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
            return
        }

        let rec = SpeechRecorder()
        let promptTime = Date()

        let save: (String) -> Void = { [weak self, weak rec] text in
            guard let rec, !rec.saved else { return }
            rec.stop()
            LogStore.shared.add(text, at: promptTime)
            rec.saved = true
            if commander {
                Announcer.shared.stop() // cut off a shout still in progress
                Commander.shared.speak(Commander.focusLine) { MediaPauser.shared.resumeIfPaused() }
            } else {
                MediaPauser.shared.resumeIfPaused()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self?.closePrompt() }
        }

        rec.onFinishedSpeaking = { [weak rec] in
            guard AppState.shared.autoSave, let rec,
                  !rec.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            save(rec.transcript)
        }

        let view = PromptView(
            recorder: rec,
            minutes: AppState.shared.intervalMinutes,
            recent: LogStore.shared.recentEntries(5),
            announcement: announcement,
            onSave: save
        )

        let hosting = NSHostingView(rootView: view)
        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Activity Check-in"
        w.contentView = hosting
        w.setContentSize(hosting.fittingSize)
        w.level = .floating
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()

        promptWindow = w
        recorder = rec

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        // Each step first checks that this check-in is still open and unsaved,
        // so nothing is spoken or recorded after you save or close the window.
        weak var weakRec = rec
        let isActive = { [weak self] in
            weakRec != nil && self?.recorder === weakRec && weakRec?.saved == false
        }
        let startListening = { if isActive() { weakRec?.start() } }
        let announce = {
            guard let announcement, isActive() else { return startListening() }
            Announcer.shared.say(announcement, then: startListening)
        }

        let begin: () -> Void
        if commander {
            var shouts = 0
            func shout() {
                guard isActive() else { return }
                shouts += 1
                Commander.shared.shout(then: shouts == 1 ? announce : startListening)
            }
            rec.noSpeechTimeout = 2
            rec.onNoSpeech = {
                guard isActive(), let rec = weakRec else { return true }
                if !rec.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true // you typed an answer instead
                }
                if shouts < Self.maxShouts {
                    shout()
                } else { // stop nagging and wait the usual 30 s
                    rec.noSpeechTimeout = 30
                    rec.onNoSpeech = nil
                    rec.start()
                }
                return true
            }
            begin = shout
        } else {
            begin = {
                guard isActive() else { return }
                let chimeLength = Chime.play(AppState.shared.soundName, repeats: AppState.shared.soundRepeats)
                DispatchQueue.main.asyncAfter(deadline: .now() + chimeLength + 0.3, execute: announce)
            }
        }

        // Pause any video or music first, so neither you nor the mic has to compete with it.
        if AppState.shared.pauseMedia {
            MediaPauser.shared.pauseIfPlaying(then: begin)
        } else {
            begin()
        }
    }

    private func closePrompt() {
        endPrompt()
        let w = promptWindow
        promptWindow = nil
        w?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === promptWindow {
            endPrompt()
            promptWindow = nil
        }
    }

    /// Stops the mic. If the check-in wasn't saved, also stops any pending shout and resumes
    /// paused media; after a save, `save` does that once "Focus, soldier!" has finished.
    private func endPrompt() {
        if recorder?.saved == false {
            Announcer.shared.stop()
            MediaPauser.shared.resumeIfPaused()
        }
        recorder?.stop()
        recorder = nil
    }

    // MARK: Log window

    func showLog() {
        LogStore.shared.day = Date()
        if logWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false)
            w.title = "Activity Log"
            w.contentView = NSHostingView(rootView: LogView())
            w.isReleasedWhenClosed = false
            w.center()
            w.setFrameAutosaveName("ActivityLogWindow")
            logWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        logWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Views

struct PromptView: View {
    @ObservedObject var recorder: SpeechRecorder
    let minutes: Int
    let recent: [LogEntry]
    let announcement: String?
    let onSave: (String) -> Void

    private var isEmpty: Bool {
        recorder.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let announcement {
                Label(announcement, systemImage: "clock.badge.checkmark.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor))
            }

            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Earlier").font(.caption.bold()).foregroundColor(.secondary)
                    ForEach(recent) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(entry.time)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .leading)
                            Text(entry.text)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.callout)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
            }

            Text("What did you do in the last \(minutes) min?")
                .font(.title2.bold())

            HStack(spacing: 6) {
                if recorder.saved {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Saved")
                } else if recorder.isListening {
                    Image(systemName: "mic.fill").foregroundColor(.red)
                    Text("Listening… pause for a few seconds when you're done")
                } else {
                    Image(systemName: "mic.slash").foregroundColor(.secondary)
                    Text("Not listening")
                }
            }
            .font(.callout)
            .foregroundColor(.secondary)

            TextEditor(text: $recorder.transcript)
                .font(.body)
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))

            if let message = recorder.message {
                Text(message).font(.caption).foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button {
                    recorder.isListening ? recorder.stop() : recorder.start()
                } label: {
                    Label(recorder.isListening ? "Stop" : "Record",
                          systemImage: recorder.isListening ? "stop.fill" : "mic.fill")
                }
                Spacer()
                Button("Save") { onSave(recorder.transcript) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isEmpty)
            }
            .disabled(recorder.saved)
        }
        .padding(20)
        .frame(width: 460)
    }
}

struct LogView: View {
    @ObservedObject private var store = LogStore.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { store.shiftDay(by: -1) } label: { Image(systemName: "chevron.left") }
                Text(store.day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                Button { store.shiftDay(by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(store.isShowingToday)
            }
            .padding(12)

            Divider()

            if store.entries.isEmpty {
                Spacer()
                Text("No entries for this day").foregroundColor(.secondary)
                Spacer()
            } else {
                List(store.entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(entry.time)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 44, alignment: .leading)
                        Text(entry.text)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()

            HStack {
                Text("\(store.entries.count) entries").foregroundColor(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.plainText, forType: .string)
                }
                .disabled(store.entries.isEmpty)
                Button("Show in Finder") {
                    NSWorkspace.shared.open(store.folder)
                }
            }
            .padding(10)
        }
        .frame(minWidth: 420, minHeight: 400)
    }
}
