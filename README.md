# Activity Logger

A tiny macOS menu-bar app. Every N minutes it chimes, asks "What did you do?",
listens through the mic, transcribes your answer on-device and appends it to a daily log.

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
- pause/start the timer, or check in now
- toggle auto-save (saves once you stop talking for ~3 s) and launch at login
- open the log window (browse days, copy, show in Finder)

At a check-in you can talk, edit the text, type instead, press **Record** to add more,
**Save** (⏎) or **Skip** (Esc). The mic is only on during a check-in.

## Log files

`~/Documents/ActivityLog/YYYY-MM-DD.txt`, one line per entry: `HH:mm<TAB>text`.
