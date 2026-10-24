import Foundation

/// Pauses whatever macOS considers "Now Playing" (YouTube in a browser, Music, Spotify, VLC…)
/// during a check-in, so the mic doesn't transcribe it, and resumes it afterwards.
/// Uses the private MediaRemote framework, loaded at runtime; if it can't be loaded,
/// every method quietly does nothing. Only used on the main thread.
final class MediaPauser {
    static let shared = MediaPauser()

    private typealias SendCommand = @convention(c) (Int, NSDictionary?) -> Bool
    private typealias GetIsPlaying = @convention(c) (DispatchQueue, @escaping @convention(block) (Bool) -> Void) -> Void

    private static let play = 0
    private static let pause = 1 // an explicit pause, not a toggle, so it never starts anything

    private let sendCommand: SendCommand?
    private let getIsPlaying: GetIsPlaying?

    /// True only while something is paused because of us, so we never start media the user had stopped.
    private var pausedByUs = false

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        sendCommand = dlsym(handle, "MRMediaRemoteSendCommand")
            .map { unsafeBitCast($0, to: SendCommand.self) }
        getIsPlaying = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
            .map { unsafeBitCast($0, to: GetIsPlaying.self) }
    }

    /// Pauses the Now Playing app if it's playing, then calls `completion` once the sound
    /// has had time to stop. Calls `completion` right away when nothing is playing.
    func pauseIfPlaying(then completion: @escaping () -> Void) {
        guard let sendCommand, let getIsPlaying else { return completion() }

        var answered = false
        getIsPlaying(.main) { [weak self] isPlaying in
            guard !answered else { return }
            answered = true
            guard isPlaying else { return completion() }
            _ = sendCommand(Self.pause, nil)
            self?.pausedByUs = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: completion)
        }

        // If macOS doesn't answer, pause anyway (harmless when nothing plays) but don't resume later.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !answered else { return }
            answered = true
            _ = sendCommand(Self.pause, nil)
            completion()
        }
    }

    /// Resumes playback if we paused it. Safe to call more than once.
    func resumeIfPaused() {
        guard pausedByUs else { return }
        pausedByUs = false
        _ = sendCommand?(Self.play, nil)
    }
}
