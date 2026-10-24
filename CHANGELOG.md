# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-10-24

### Added

- **Commander voice**: at each timer check-in the app shouts "Soldier! Update!" instead
  of the chime, then listens. If you don't start talking within 2 seconds it shouts again
  (up to 5 times, then it waits quietly for 30 seconds). After you save it says
  "Focus, soldier!". Turn it on or off and test it from the menu; with it off, the chime
  plays as before.
- **Pause media during check-ins**: whatever is playing (YouTube in any browser, Music,
  Spotify, VLC, and anything else in macOS's Now Playing) is paused before the check-in
  starts, so the mic doesn't transcribe it, and resumed after you save or close the
  window. Only media the app paused is resumed. Toggle it in the menu.
- **Your own clip**: choose any audio file (for example a recording of a real drill
  sergeant) to play instead of the built-in voice. It is copied to
  `~/Library/Application Support/ActivityLogger/`.

### Fixed

- The hourly announcement now uses real elapsed time, so it works at any interval.
  Before, it fired every 6th check-in, which was only right at the default 10 minutes
  (at 30 minutes it said "1 hour is up" after 3 hours).

## [1.0.0] - 2026-10-24

First public release.

### Added

- **Menu-bar app** with no Dock icon, showing a waveform icon that is filled while the timer runs.
- **Timed check-ins** at an interval of 1–180 minutes (default 10), with pause/start and
  "Check in now". The timer uses a small tolerance so macOS can save energy.
- **Chime** before each check-in: pick one of 14 system sounds, play it 1–10 times,
  and test it from the menu.
- **Voice logging**: after the chime the app listens and transcribes live with Apple's
  Speech framework, on-device when available. Long answers are stitched across
  recognition segments, and listening stops after silence, after 30 s with no speech,
  or after 2 minutes.
- **Auto-save** once you stop talking for about 3 seconds (can be turned off).
- **Editing**: fix or type the text by hand, press Record to add more, Save with ⏎.
- **Hourly announcement**: every 6th check-in speaks "N hours are up" and shows it as a
  banner. "Check in now" restarts the countdown without resetting the hour count.
- **Recent entries**: the check-in window shows your last 5 entries from today.
- **Log window**: browse entries by day, copy the day's log, or open the folder in Finder.
- **Plain-text storage** in `~/Documents/ActivityLog/YYYY-MM-DD.txt`, one `HH:mm<TAB>text`
  line per entry.
- **Launch at login** toggle.
- Clear messages when microphone or speech permissions are missing, so you can type instead.
- `build.sh` builds and ad-hoc signs the app with only the Command Line Tools, including a
  workaround for a Command Line Tools 16 module-map bug that breaks SwiftUI builds.

### Removed

- The Skip button on the check-in window. Close the window to dismiss a check-in.

[Unreleased]: https://github.com/naikigai/ActivityLogger/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/naikigai/ActivityLogger/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/naikigai/ActivityLogger/releases/tag/v1.0.0
