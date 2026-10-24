# Activity Logger

A tiny macOS menu-bar app. Every N minutes it chimes, asks "What did you do?",
listens through the mic, transcribes your answer on-device and appends it to a daily log.

## Requirements

- macOS 13 (Ventura) or later on Apple Silicon
- Xcode Command Line Tools (`xcode-select --install`); full Xcode is not needed

## Build & install

```bash
./build.sh
cp -R build/ActivityLogger.app /Applications/
open /Applications/ActivityLogger.app
```

Allow **Microphone** and **Speech Recognition** when prompted. Rebuilding changes the
ad-hoc signature, so macOS may ask for these permissions again.

## Use

Click the waveform icon in the menu bar to:
- set the interval (1–180 min, default 10)
- pick the chime sound and how many times it plays
- pause/start the timer, or check in now
- toggle auto-save (saves once you stop talking for ~3 s) and launch at login
- open the log window (browse days, copy, show in Finder)

At a check-in you can talk, edit the text, type instead, press **Record** to add more,
**Save** (⏎), or close the window to dismiss it. The window also shows your last few
entries from today, and every hour of check-ins is announced aloud.

## Privacy

- The mic is only on during a check-in.
- Speech is transcribed on-device when your Mac supports it.
- Logs stay on your Mac as plain-text files; nothing is uploaded.

## Log files

`~/Documents/ActivityLog/YYYY-MM-DD.txt`, one line per entry: `HH:mm<TAB>text`.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
