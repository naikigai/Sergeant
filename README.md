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
- set when your day starts and ends (default 9 AM–9 PM)
- pick the chime sound and how many times it plays
- pause/start the timer, or check in now
- turn the **commander voice** on or off, test it, or pick your own audio clip for it
- pause videos and music during check-ins (on by default; they resume afterwards)
- toggle auto-save (saves once you stop talking for ~3 s) and launch at login
- open the log window (browse days, copy, show in Finder)

At a check-in, press **⏎** to start recording and **⏎** again to save. If the words come
out wrong, click or type in the text box to fix them: the mic stops and auto-save is off
for that check-in, so it only saves when you press **⏎** or **Save**. You can also edit
the text, type instead, press **Record** to add more, or close the window to dismiss it. The window also shows your last few
entries from today.

### Schedule

Check-ins land on fixed clock slots, counted from midnight, no matter when the app
started: every 10 min means 10:00, 10:10, 10:20 … (intervals that divide 60, like 10, 15,
20 or 30, give the cleanest times). They only happen during your day: with 9 AM–9 PM the
first is at 9:10 and the last at 9:00 PM, and outside those hours the menu shows the next
one tomorrow. **Check in now** doesn't move the schedule.

At the first check-in of each new hour the app says, for example,
**"1 hour is up. It's 3 PM. 6 hours left in the day."** (at the last check-in:
"That's the end of the day."). It's also shown at the top of the check-in window.

If you miss check-ins (say your last update was at 7:00 and you're back at 8:56), the
9:00 check-in says **"2 hours since your last update. It's 9 AM. 15 hours left in the
day."**, asks what you did since 7:00 AM, and logs your answer as `07:00–09:00`. After
that it goes back to every 10 minutes. An unanswered window is replaced by the next
check-in rather than left open.

### Commander voice

At each timer check-in the app says the hour announcement (if one is due), then shouts
**"Soldier! Update!"** instead of the chime, then listens. If you don't start talking within 2 seconds it shouts again (up to 5 times), and
after you save it says **"Focus, soldier!"**. By default it uses the deepest built-in macOS voice (Ralph), pitched down and sped up. For a more
convincing drill sergeant, click **Use my own clip…** and choose an audio file (mp3, m4a,
wav, aiff); it is copied to `~/Library/Application Support/ActivityLogger/`.
**Use built-in voice** switches back.

### Pausing videos and music

When a check-in starts, whatever macOS shows as **Now Playing** (YouTube in Chrome, Safari,
Arc or Brave, Music, Spotify, VLC…) is paused first, so the mic only hears you. It resumes
after you save (once "Focus, soldier!" finishes) or close the window. Only media the app
paused is resumed. This uses macOS's private MediaRemote framework, so a future macOS
update could stop it working; the rest of the app is unaffected.

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
