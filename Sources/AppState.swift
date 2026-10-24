import AppKit
import AVFoundation
import ServiceManagement

final class AppState: ObservableObject {
    static let shared = AppState()

    private let defaults = UserDefaults.standard
    private var timer: Timer?

    @Published var intervalMinutes: Int {
        didSet {
            defaults.set(intervalMinutes, forKey: "intervalMinutes")
            if isRunning { schedule() }
        }
    }

    static let sounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
                         "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

    @Published var soundName: String {
        didSet { defaults.set(soundName, forKey: "soundName") }
    }

    @Published var soundRepeats: Int {
        didSet { defaults.set(soundRepeats, forKey: "soundRepeats") }
    }

    @Published var autoSave: Bool {
        didSet { defaults.set(autoSave, forKey: "autoSave") }
    }

    /// Pause whatever is playing (videos, music) during a check-in and resume it afterwards.
    @Published var pauseMedia: Bool {
        didSet { defaults.set(pauseMedia, forKey: "pauseMedia") }
    }

    /// Shout "Soldier! Update!" at each timer check-in.
    @Published var commanderVoice: Bool {
        didSet { defaults.set(commanderVoice, forKey: "commanderVoice") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch at login failed: \(error)")
            }
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var nextFire: Date?

    /// When the timer was started; hours are counted from here.
    private var startedAt = Date()
    /// Whole hours already announced since `startedAt`.
    private var announcedHours = 0

    private init() {
        let saved = defaults.integer(forKey: "intervalMinutes")
        intervalMinutes = saved > 0 ? saved : 10
        autoSave = defaults.object(forKey: "autoSave") as? Bool ?? true
        commanderVoice = defaults.object(forKey: "commanderVoice") as? Bool ?? true
        pauseMedia = defaults.object(forKey: "pauseMedia") as? Bool ?? true
        soundName = defaults.string(forKey: "soundName") ?? "Submarine"
        let repeats = defaults.integer(forKey: "soundRepeats")
        soundRepeats = repeats > 0 ? repeats : 3
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func startIfNeeded() {
        if defaults.object(forKey: "running") as? Bool ?? true { start() }
    }

    /// Starts the timer and the hour count from now.
    func start() {
        isRunning = true
        defaults.set(true, forKey: "running")
        startedAt = Date()
        announcedHours = 0
        schedule()
    }

    /// Restarts the countdown to the next check-in without resetting the hour count.
    func restartCountdown() {
        if isRunning { schedule() }
    }

    func pause() {
        isRunning = false
        defaults.set(false, forKey: "running")
        timer?.invalidate()
        timer = nil
        nextFire = nil
    }

    private func schedule() {
        timer?.invalidate()
        let interval = TimeInterval(intervalMinutes * 60)
        nextFire = Date().addingTimeInterval(interval)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.nextFire = Date().addingTimeInterval(interval)
            WindowManager.shared.showPrompt(announcement: self.hourAnnouncement(),
                                            commander: self.commanderVoice)
        }
        t.tolerance = 5 // lets macOS coalesce wakeups to save energy
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Based on real elapsed time, so it works for any interval: returns "N hours are up"
    /// at the first check-in after a new whole hour has passed since the timer started.
    private func hourAnnouncement() -> String? {
        let hours = Int((Date().timeIntervalSince(startedAt) + 1) / 3600) // +1 s for timer jitter
        guard hours > announcedHours else { return nil }
        announcedHours = hours
        return hours == 1 ? "1 hour is up" : "\(hours) hours are up"
    }
}

/// Speaks a short phrase or plays an audio clip and reports when it's done,
/// so the mic can start afterwards.
final class Announcer: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate,
                       @unchecked Sendable { // only used on the main thread
    static let shared = Announcer()
    private let synth = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?

    private override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ text: String, voice: AVSpeechSynthesisVoice? = nil, pitch: Float = 1,
             rate: Float = AVSpeechUtteranceDefaultSpeechRate, then completion: @escaping () -> Void) {
        self.completion = completion
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.pitchMultiplier = pitch
        utterance.rate = rate
        synth.speak(utterance)
    }

    /// Returns false (without calling `completion`) if the file can't be played.
    func play(_ url: URL, then completion: @escaping () -> Void) -> Bool {
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return false }
        p.delegate = self
        guard p.play() else { return false }
        player = p
        self.completion = completion
        return true
    }

    /// Stops speaking or playing right away without calling the pending completion.
    func stop() {
        completion = nil
        synth.stopSpeaking(at: .immediate)
        player?.stop()
        player = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        finish()
    }

    private func finish() {
        DispatchQueue.main.async {
            self.player = nil
            let done = self.completion
            self.completion = nil
            done?()
        }
    }
}

enum Chime {
    /// Plays the chosen sound `repeats` times back to back.
    /// Returns how long the whole chime lasts, so the mic can wait for it to finish.
    @discardableResult
    static func play(_ name: String, repeats: Int) -> TimeInterval {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return 0 }
        let step = sound.duration + 0.15
        for i in 0..<max(repeats, 1) {
            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(i)) {
                // A fresh copy per play, because one NSSound can't overlap itself.
                (sound.copy() as? NSSound)?.play()
            }
        }
        return step * Double(max(repeats, 1))
    }
}
