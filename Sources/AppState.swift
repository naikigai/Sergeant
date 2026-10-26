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

    /// The workday: check-ins happen only between these clock hours (end may be 24 = midnight).
    @Published var dayStartHour: Int {
        didSet {
            defaults.set(dayStartHour, forKey: "dayStartHour")
            if isRunning { schedule() }
        }
    }

    @Published var dayEndHour: Int {
        didSet {
            defaults.set(dayEndHour, forKey: "dayEndHour")
            if isRunning { schedule() }
        }
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

    /// When the last saved update's check-in started; a later check-in that finds
    /// missed slots since then covers the whole gap.
    var lastUpdateAt: Date? {
        get { defaults.object(forKey: "lastUpdateAt") as? Date }
        set { defaults.set(newValue, forKey: "lastUpdateAt") }
    }

    /// When a check-in went unanswered because you were away (no response within
    /// `awayTimeout`); the next check-in reprimands you for it. Cleared when you save.
    var awayAt: Date?

    /// How long a check-in waits for any response before deciding you're away.
    static let awayTimeout: TimeInterval = 60

    /// When the previous check-in was due (or when the timer started); used to tell
    /// when a new clock hour has begun.
    private var lastCheckIn = Date()

    private init() {
        Self.migrateSettings(into: defaults)
        let saved = defaults.integer(forKey: "intervalMinutes")
        intervalMinutes = saved > 0 ? saved : 10
        autoSave = defaults.object(forKey: "autoSave") as? Bool ?? true
        commanderVoice = defaults.object(forKey: "commanderVoice") as? Bool ?? true
        pauseMedia = defaults.object(forKey: "pauseMedia") as? Bool ?? true
        soundName = defaults.string(forKey: "soundName") ?? "Submarine"
        let repeats = defaults.integer(forKey: "soundRepeats")
        soundRepeats = repeats > 0 ? repeats : 3
        dayStartHour = defaults.object(forKey: "dayStartHour") as? Int ?? 9
        dayEndHour = defaults.object(forKey: "dayEndHour") as? Int ?? 21
        launchAtLogin = SMAppService.mainApp.status == .enabled

        // After sleep, check in right away if a slot was slept through; otherwise pick the
        // next upcoming slot. Count the hour from the wake so the first check-in after
        // waking doesn't say "1 hour is up".
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.catchUpOrSchedule()
        }
    }

    /// The app used to be called Activity Logger (bundle ID com.abhi.ActivityLogger);
    /// copy its settings over once so the rename doesn't reset them.
    private static func migrateSettings(into defaults: UserDefaults) {
        guard !defaults.bool(forKey: "migratedFromActivityLogger"),
              let old = UserDefaults(suiteName: "com.abhi.ActivityLogger") else { return }
        for key in ["intervalMinutes", "soundName", "soundRepeats", "autoSave", "pauseMedia",
                    "commanderVoice", "dayStartHour", "dayEndHour", "running", "lastUpdateAt",
                    "NSWindow Frame ActivityLogWindow"] {
            if defaults.object(forKey: key) == nil, let value = old.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: "migratedFromActivityLogger")
    }

    func startIfNeeded() {
        if defaults.object(forKey: "running") as? Bool ?? true { start() }
    }

    func start() {
        isRunning = true
        defaults.set(true, forKey: "running")
        lastCheckIn = Date()
        schedule()
    }

    func pause() {
        isRunning = false
        defaults.set(false, forKey: "running")
        timer?.invalidate()
        timer = nil
        nextFire = nil
    }

    /// Sets a one-shot timer for the next clock slot; each check-in schedules the one after.
    private func schedule() {
        timer?.invalidate()
        let due = nextCheckIn(after: Date().addingTimeInterval(1)) // +1 s so a slot never repeats
        nextFire = due
        let t = Timer(fire: due, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            // A slot that came due while the Mac slept fires on wake, sometimes before the
            // wake notification arrives; check in now about the whole gap instead.
            guard Date().timeIntervalSince(due) < 60 else { return self.catchUpOrSchedule() }
            let announcement = self.announcement(at: due)
            self.lastCheckIn = due
            self.schedule()
            WindowManager.shared.showPrompt(announcement: announcement, commander: self.commanderVoice,
                                            replacingIdle: true, awayAfter: Self.awayTimeout)
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// On wake: if the pending slot came due while the Mac slept, check in immediately and
    /// say how long it's been since the last update; then schedule the next slot. Runs from
    /// both the wake notification and the stale timer, whichever comes first; the first one
    /// moves `nextFire` ahead, so the other does nothing extra.
    private func catchUpOrSchedule() {
        let now = Date()
        let missed = nextFire.map { $0 <= now } ?? false
        lastCheckIn = now
        schedule()
        guard missed, isInWorkday(now) else { return }

        let last = lastUpdateAt.flatMap { Calendar.current.isDate($0, inSameDayAs: now) ? $0 : nil }
        var announcement = awayNote(at: now).map { $0 + " " } ?? ""
        if let last {
            let time = last.formatted(date: .omitted, time: .shortened)
            announcement += "You haven't given an update since \(time). That's \(Self.duration(now.timeIntervalSince(last))). "
                          + "Tell me everything you did since then."
        } else {
            announcement += "You haven't given an update yet today. Tell me everything you've done so far."
        }
        WindowManager.shared.showPrompt(announcement: announcement, commander: commanderVoice,
                                        replacingIdle: true, since: last, awayAfter: Self.awayTimeout)
    }

    private func isInWorkday(_ date: Date) -> Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        return date > cal.date(byAdding: .hour, value: dayStartHour, to: day)!
            && date <= cal.date(byAdding: .hour, value: dayEndHour, to: day)!
    }

    /// The first clock slot after `date` inside the workday. Slots are multiples of the
    /// interval counted from midnight (10 min: :00, :10, :20 …), whenever the app started.
    /// The window is (start, end]: with 9–21 the first check-in is 9:10 and the last 21:00.
    func nextCheckIn(after date: Date) -> Date {
        let cal = Calendar.current
        let step = max(intervalMinutes, 1)
        var day = cal.startOfDay(for: date)
        for _ in 0..<3 {
            let start = cal.date(byAdding: .hour, value: dayStartHour, to: day)!
            let end = cal.date(byAdding: .hour, value: dayEndHour, to: day)!
            let from = max(date, start)
            if cal.isDate(from, inSameDayAs: day) {
                let t = cal.dateComponents([.hour, .minute], from: from)
                let slot = (t.hour! * 60 + t.minute!) / step * step + step
                let due = slot < 24 * 60
                       ? cal.date(bySettingHour: slot / 60, minute: slot % 60, second: 0, of: day)
                       : cal.date(byAdding: .day, value: 1, to: day) // midnight
                if let due, due <= end {
                    return due
                }
            }
            day = cal.date(byAdding: .day, value: 1, to: day)!
        }
        return date.addingTimeInterval(TimeInterval(step * 60)) // unreachable with a valid window
    }

    /// The start of the time an update made at `date` covers, when at least one check-in
    /// was missed since the last saved update (same day only); nil for a normal check-in.
    func missedSince(_ date: Date) -> Date? {
        guard let last = lastUpdateAt, Calendar.current.isDate(last, inSameDayAs: date),
              date.timeIntervalSince(last) > TimeInterval(intervalMinutes * 60 + 60) else { return nil }
        return last
    }

    /// What's said at a timer check-in, e.g. "2 hours since your last update.
    /// It's 9 AM. 15 hours left in the day." or just the hourly part, or nil.
    private func announcement(at due: Date) -> String? {
        let parts = [awayNote(at: due), gapAnnouncement(at: due)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func gapAnnouncement(at due: Date) -> String? {
        let hourly = hourAnnouncement(at: due)
        guard let since = missedSince(due) else { return hourly }
        let gap = "\(Self.duration(due.timeIntervalSince(since))) since your last update."
        guard let hourly else { return gap }
        return gap + " " + hourly.replacingOccurrences(of: "1 hour is up. ", with: "")
    }

    /// "You were away from your screen at the 11:00 AM check-in." when the last
    /// check-in today went unanswered.
    private func awayNote(at date: Date) -> String? {
        guard let awayAt, Calendar.current.isDate(awayAt, inSameDayAs: date) else { return nil }
        return "You were away from your screen at the \(awayAt.formatted(date: .omitted, time: .shortened)) check-in."
    }

    /// "40 minutes", "1 hour", "2 hours and 10 minutes"
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded())
        let h = total / 60, m = total % 60
        let hours = h == 1 ? "1 hour" : "\(h) hours"
        let minutes = m == 1 ? "1 minute" : "\(m) minutes"
        return h == 0 ? minutes : m == 0 ? hours : "\(hours) and \(minutes)"
    }

    /// At the first check-in of each new clock hour (except the first of the day):
    /// "1 hour is up. It's 3 PM. 6 hours left in the day."
    private func hourAnnouncement(at due: Date) -> String? {
        let cal = Calendar.current
        var hour = cal.component(.hour, from: due)
        if !cal.isDate(due, inSameDayAs: lastCheckIn) {
            // Only the midnight right after the previous check-in's day counts (a day ending at 24).
            let nextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lastCheckIn))!
            guard due == nextDay else { return nil }
            hour = 24
        }
        guard hour != cal.component(.hour, from: lastCheckIn),
              hour > dayStartHour else { return nil }

        let time = Self.hourFormatter.string(from: due)
        let left = dayEndHour - hour
        let rest = left <= 0 ? "That's the end of the day."
                 : left == 1 ? "1 hour left in the day."
                 : "\(left) hours left in the day."
        return "1 hour is up. It's \(time). \(rest)"
    }

    /// "3 PM"
    static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h a"
        return f
    }()
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
