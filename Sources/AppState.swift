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

    /// Every this many timer check-ins, the app announces that an hour is up.
    static let triggersPerHour = 6
    private var triggerCount = 0

    private init() {
        let saved = defaults.integer(forKey: "intervalMinutes")
        intervalMinutes = saved > 0 ? saved : 10
        autoSave = defaults.object(forKey: "autoSave") as? Bool ?? true
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
        triggerCount = 0
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
            self.triggerCount += 1
            let hours = self.triggerCount / Self.triggersPerHour
            let isHourMark = self.triggerCount % Self.triggersPerHour == 0
            WindowManager.shared.showPrompt(
                announcement: isHourMark ? (hours == 1 ? "1 hour is up" : "\(hours) hours are up") : nil)
        }
        t.tolerance = 5 // lets macOS coalesce wakeups to save energy
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

/// Speaks a short phrase aloud and reports when it's done, so the mic can start afterwards.
final class Announcer: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable { // only used on the main thread
    static let shared = Announcer()
    private let synth = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    private override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ text: String, then completion: @escaping () -> Void) {
        self.completion = completion
        synth.speak(AVSpeechUtterance(string: text))
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
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
