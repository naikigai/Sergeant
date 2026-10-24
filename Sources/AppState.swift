import AppKit
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

    /// Starts (or restarts) the countdown from now.
    func start() {
        isRunning = true
        defaults.set(true, forKey: "running")
        schedule()
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
            self?.nextFire = Date().addingTimeInterval(interval)
            WindowManager.shared.showPrompt()
        }
        t.tolerance = 5 // lets macOS coalesce wakeups to save energy
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
