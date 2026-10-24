import AppKit
import SwiftUI

final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var promptWindow: NSWindow?
    private var recorder: SpeechRecorder?
    private var logWindow: NSWindow?

    // MARK: Check-in prompt

    /// `announcement` is spoken aloud after the chime (e.g. "1 hour is up") and shown in the window.
    func showPrompt(announcement: String? = nil) {
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
            onSave: save,
            onSkip: { [weak self] in self?.closePrompt() }
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

        let chimeLength = Chime.play(AppState.shared.soundName, repeats: AppState.shared.soundRepeats)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        // Start listening after the chime (and announcement) so they aren't picked up.
        DispatchQueue.main.asyncAfter(deadline: .now() + chimeLength + 0.3) { [weak rec] in
            guard let announcement else { rec?.start(); return }
            Announcer.shared.say(announcement) { [weak rec] in rec?.start() }
        }
    }

    private func closePrompt() {
        recorder?.stop()
        recorder = nil
        let w = promptWindow
        promptWindow = nil
        w?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === promptWindow {
            recorder?.stop()
            recorder = nil
            promptWindow = nil
        }
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
    let onSkip: () -> Void

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
                Button("Skip", action: onSkip)
                    .keyboardShortcut(.cancelAction)
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
