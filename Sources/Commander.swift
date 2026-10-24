import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// The drill-sergeant call at each timer check-in. Plays the user's own clip if one is set,
/// otherwise a deep, fast built-in voice.
final class Commander: ObservableObject {
    static let shared = Commander()

    static let line = "Soldier! Update!"
    static let focusLine = "Focus, soldier!"

    /// Where the user's clip is kept: ~/Library/Application Support/ActivityLogger/commander-clip.<ext>
    private let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ActivityLogger", isDirectory: true)

    @Published private(set) var clipURL: URL?

    /// The gruffest voice that ships with macOS, falling back to the system default.
    private let voice: AVSpeechSynthesisVoice? = {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        for name in ["Ralph", "Rocko", "Fred"] {
            if let v = voices.first(where: { $0.name == name && $0.language == "en-US" }) { return v }
        }
        return nil
    }()

    private init() {
        clipURL = findClip()
    }

    /// Shouts the line, then calls `completion` once the audio has finished.
    func shout(then completion: @escaping () -> Void) {
        if let clipURL, Announcer.shared.play(clipURL, then: completion) { return }
        speak(Self.line, then: completion)
    }

    /// Says `text` in the commander's built-in voice.
    func speak(_ text: String, then completion: @escaping () -> Void = {}) {
        Announcer.shared.say(text, voice: voice, pitch: 0.5, rate: 0.55, then: completion)
    }

    /// Lets the user pick an audio file and copies it in, replacing any earlier clip.
    func chooseClip() {
        let panel = NSOpenPanel()
        panel.title = "Choose a commander voice clip"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let source = panel.url else { return }

        removeClip()
        let dest = folder.appendingPathComponent("commander-clip").appendingPathExtension(source.pathExtension)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: dest)
            clipURL = dest
        } catch {
            NSLog("Couldn't copy commander clip: \(error)")
        }
    }

    func removeClip() {
        if let clipURL { try? FileManager.default.removeItem(at: clipURL) }
        clipURL = nil
    }

    private func findClip() -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.first { $0.deletingPathExtension().lastPathComponent == "commander-clip" }
    }
}
