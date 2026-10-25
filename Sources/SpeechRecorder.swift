import AVFoundation
import Speech

/// Records from the mic and transcribes live using Apple's Speech framework
/// (on-device when available). The mic is only active between start() and stop().
final class SpeechRecorder: ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isListening = false
    @Published var message: String?
    @Published var saved = false
    /// Set once the user clicks or types in the text box: from then on nothing records or
    /// saves by itself (no auto-save, no auto-start); only ⏎, Save or Record do.
    @Published var editedByUser = false

    /// Called when the user has spoken and then gone quiet.
    var onFinishedSpeaking: (() -> Void)?
    /// Called (after the mic stops) when nothing was said within `noSpeechTimeout`.
    /// Return true if handled, otherwise the default "Stopped listening" message is shown.
    var onNoSpeech: (() -> Bool)?

    /// How long to wait for the user to start talking.
    var noSpeechTimeout: TimeInterval = 30
    private let silenceTimeout: TimeInterval = 3
    private let maxDuration: TimeInterval = 120

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var watchdog: Timer?
    private var startedAt = Date()
    private var lastChange = Date()
    private var heardSpeech = false
    /// Text from earlier recognition segments (and from before Record was pressed).
    private var committed = ""
    /// Latest partial text of the current segment.
    private var partial = ""
    /// The tap runs on the audio thread, so access to `request` is guarded.
    private let requestLock = NSLock()

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    static func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    func start() {
        guard !isListening else { return }
        message = nil

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            message = "Speech recognition isn't allowed. Enable it in System Settings › Privacy & Security › Speech Recognition, or type instead."
            Self.requestPermissions()
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            message = "Microphone access isn't allowed. Enable it in System Settings › Privacy & Security › Microphone, or type instead."
            Self.requestPermissions()
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            message = "Speech recognition is unavailable right now. You can type instead."
            return
        }

        let req = makeRequest(for: recognizer)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            message = "No microphone found."
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.requestLock.lock()
            self.request?.append(buffer)
            self.requestLock.unlock()
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            message = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }

        self.engine = engine
        committed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        partial = ""
        heardSpeech = false
        startedAt = Date()
        lastChange = Date()
        isListening = true

        startRecognitionTask(recognizer: recognizer, request: req)

        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkTimeouts()
        }
    }

    /// The recognizer splits long speech into segments. When a new segment starts, its
    /// text no longer contains the earlier ones, so we keep finished segments in `committed`
    /// and only replace the current segment's text.
    private func startRecognitionTask(recognizer: SFSpeechRecognizer, request req: SFSpeechAudioBufferRecognitionRequest) {
        requestLock.lock()
        request = req
        requestLock.unlock()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.isListening, self.request === req else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    if !text.isEmpty {
                        // A much shorter result means the recognizer started a new segment.
                        if text.count < self.partial.count / 2 { self.commitPartial() }
                        self.partial = text
                        self.heardSpeech = true
                        self.lastChange = Date()
                        self.updateTranscript()
                    }
                    if result.isFinal { self.continueWithNewSegment(recognizer: recognizer) }
                } else if error != nil {
                    if self.heardSpeech {
                        self.continueWithNewSegment(recognizer: recognizer)
                    } else {
                        self.stop()
                        self.message = "Didn't catch that. Tap Record to try again, or type."
                    }
                }
            }
        }
    }

    /// A segment ended (final result) but the user may keep talking: keep its text and
    /// start a fresh recognition request on the same running microphone.
    private func continueWithNewSegment(recognizer: SFSpeechRecognizer) {
        commitPartial()
        updateTranscript()
        request?.endAudio()
        task?.cancel()

        let req = makeRequest(for: recognizer)
        startRecognitionTask(recognizer: recognizer, request: req)
    }

    private func makeRequest(for recognizer: SFSpeechRecognizer) -> SFSpeechAudioBufferRecognitionRequest {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        return req
    }

    private func commitPartial() {
        guard !partial.isEmpty else { return }
        committed = committed.isEmpty ? partial : committed + " " + partial
        partial = ""
    }

    private func updateTranscript() {
        transcript = [committed, partial].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func checkTimeouts() {
        let now = Date()
        if heardSpeech && now.timeIntervalSince(lastChange) > silenceTimeout {
            finish()
        } else if !heardSpeech && now.timeIntervalSince(startedAt) > noSpeechTimeout {
            stop()
            if onNoSpeech?() != true {
                message = "Stopped listening. Tap Record to try again, or type."
            }
        } else if now.timeIntervalSince(startedAt) > maxDuration {
            finish()
        }
    }

    private func finish() {
        stop()
        if heardSpeech { onFinishedSpeaking?() }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        watchdog?.invalidate()
        watchdog = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        requestLock.lock()
        request?.endAudio()
        request = nil
        requestLock.unlock()
        task?.cancel()
        task = nil
        commitPartial()
    }
}
