# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **Catch-up updates**: if you miss check-ins (away from the Mac), the next one says how
  long it's been, e.g. "2 hours since your last update.", asks "What did you do since
  7:00 AM?", and logs your answer for the whole span (`07:00–09:00`). An unanswered
  check-in window is replaced by the next one instead of piling up.
- **Workday**: set when your day starts and ends in the menu (default 9 AM–9 PM).
  Check-ins only happen inside it; the menu shows the next one, "tomorrow" if needed.

### Changed

- **Editing turns off auto-save**: as soon as you click or type in the text box, the mic
  stops (so it can't overwrite your edits), the shouting stops, and the check-in no longer
  saves by itself when you go quiet. Save with ⏎ or the Save button; Record adds more speech.
- **Check-ins on the clock**: they now land on fixed slots counted from midnight
  (10:00, 10:10, 10:20 … at 10 min), instead of counting from when the app started.
  "Check in now" no longer moves the schedule. A check-in that came due while the Mac
  slept is skipped instead of popping up on wake, and the first check-in after waking
  doesn't say "1 hour is up".
- **Hourly message**: at the first check-in of each new clock hour the app says
  "1 hour is up. It's 3 PM. 6 hours left in the day." (or "That's the end of the day."),
  instead of counting hours since the app started.

- **⏎ to record, ⏎ to save**: in the check-in window, the first ⏎ starts recording (and
  cuts off the shout and its repeats); the next ⏎ saves. Works even while typing in the
  text box. Shift-⏎ still inserts a line break.
- The hour announcement now comes first: "1 hour is up", then "Soldier! Update!", then
  the mic. Repeated shouts don't repeat the announcement.

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
