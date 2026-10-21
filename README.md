# Claude Island

A Dynamic-Island-style pill at the top-center of your screen for Windows 10/11.

**Claude Code**: what Claude is doing, when it needs you, and when a task is done
(with model, tokens, estimated API value and duration). Hover for every session.

**Now playing**: album art, title and artist, with an equalizer tinted to the cover.
Hover for a progress bar and previous / play-pause / next.

**Companion**: a little character beside the pill that reacts to all of it. Pick the
built-in blob, Charlie, or any folder in `custom images`. Make your own with the
[companion guide](docs/companions.md).

**Fullscreen**: while a fullscreen app is in front, the pill becomes a slim notch at
the top edge with Claude's status and elapsed time.

It draws its own window, so Do Not Disturb doesn't hide it and nothing piles up in
the notification center. It never steals focus and stays out of Alt+Tab.

## Setup (once)

Double-click **Install.cmd**, then restart any open Claude Code sessions.

## Updating

The island checks GitHub once a day for a newer release (tray menu → **Check for updates** checks
now). When there is one, it says so; click the notice or tray menu → **Install update**. Your
`settings.json`, your own characters in `custom images` and `state` are kept, new settings are
filled in, and the island restarts by itself. Turn the daily check off with `updateCheck`.

If you cloned the repo, `git pull` works too: a changed `scripts\ClaudeIsland.ps1` restarts the
island automatically, and `settings.json` and companion images apply live.

**Publishing a new version** (maintainers): commit your changes, then run `publish 1.1.0` (or
`publish 1.1.0 "what changed"`). It sets `VERSION`, tags, pushes and creates the GitHub Release
with a zip. It needs the GitHub CLI (`winget install GitHub.cli`, then `gh auth login`).
The repo has to be public for other people's islands to see releases.
## Folder layout

| Path | What it is |
| --- | --- |
| `settings.json` | Your settings, edit any time (applied live) |
| `custom images\` | One folder per companion, e.g. `custom images\Charlie\` |
| `scripts\` | The island, the Claude Code hook, install and uninstall |
| `data\agent-prices.json` | Model prices for the API-value estimate |
| `state\` | Running state and `island.log` (safe to delete) |

## Notices from your own scripts

`notch.cmd` (in the island folder; add the folder to PATH to use it anywhere) puts a notice in the island:

```
notch "Deploy finished"
notch "Tests failed" -Kind fail -Text "3 of 120"
notch run npm test        runs it, then shows Passed or Failed (exit code) and how long it took
notch timer 25            starts a 25 minute timer
```
## Timer

Tray menu → **Timer**: 5 / 10 / 15 / 30 minutes, or a Pomodoro (focus, then a break). It counts down in the island with a ring, and in the fullscreen notch.

## Tray menu

Play a test run, Sound, Show while Claude works, Now playing, Click through,
Compact notch in fullscreen, System stats when idle, Companion,
Start with Windows, Clear stuck sessions, Open island folder, Restart, Quit.

## settings.json

Open it in any text editor, change a value, save; the island updates within ~2 seconds.
If you make a typo the island keeps the last good settings and notes it in `state\island.log`.
Options added by future updates are filled in automatically.

**Look**

| Key | Default | What it does |
| --- | --- | --- |
| `backgroundOpacity` | `0.55` | Darkness on top of the blur: 0 = clear glass, 1 = solid |
| `backgroundColor` | `#0B0B0D` | Pill color |
| `borderOpacity` | `0.15` | Thin outline around the pill, 0 = none |
| `glowStrength` | `1.0` | Colored glow around the pill, 0 = off, up to 2 |
| `textShadow` | `true` | Keeps text readable over bright windows |
| `blur` | `true` | Frosted glass behind the pill. While it's on, the island is left out of screenshots and recordings (so the glass never sees itself); set `false` to have it show up in them |
| `blurStrength` | `8` | How blurry the glass is, 2 to 20 |
| `blurRefreshMs` | `100` | How often the glass refreshes what's behind it (lower = smoother, a bit more CPU) |
| `solidDuringResize` | `grow` | With blur on, the pill turns solid while it changes size: fade to solid, resize, fade back to glass. `grow` = only when getting bigger, `both` = bigger and smaller, `off` = never |
| `solidFadeMs` | `150` | How long the fade to solid (before the resize) and back to glass (after) takes |
| `size` | `1.0` | Scales everything (0.5 to 2.5), e.g. `0.85` or `1.2` |
| `cornerRadius` | `24` | 24 is a full pill, lower is squarer |
| `offsetX` | `0` | Move left (negative) or right from the center, in pixels |
| `offsetY` | `0` | Move down from the top edge, in pixels |

**Transitions** (milliseconds, `0` = instant)

| Key | Default | What it does |
| --- | --- | --- |
| `fps` | `0` | Animation frame rate. `0` matches your fastest monitor's refresh rate (WPF would otherwise cap at 60) |
| `showMs` | `460` | The pill popping in when it appears (Claude starts working, a song starts) |
| `hideMs` | `220` | The pill shrinking away when there's nothing to show |
| `switchMs` | `380` | Little bounce when the content changes |
| `resizeMs` | `320` | The pill gliding to a new size when its content changes |
| `resizeOverlap` | `0.6` | How the width and height steps overlap (for hover and every resize): `0` = width first, then height; `1` = both at once; `0.8` = height starts when width is 20% done. Closing runs in reverse (height first) |
| `textMs` | `260` | Changed text cross-fades: old fades out, new fades in |
| `expandMs` | `360` | Hover panel opening and closing (total time), eased in-out sine |
| `musicTrackMs` | `250` | Fade between songs |

**Behavior**

| Key | Default | What it does |
| --- | --- | --- |
| `sound` | `true` | Chime on done / needs input |
| `chimeAfterSeconds` | `20` | Only chime for tasks that ran at least this long |
| `doneSeconds` | `8` | How long "Task complete" stays up |
| `showWorking` | `true` | Show the pill while Claude works |
| `music` | `true` | Show what's playing when Claude is idle |
| `musicPausedSeconds` | `4` | Keep the music pill this long after pausing |
| `clickThrough` | `true` | Clicks go through the pill to whatever is under it. Ctrl+click it once and it stays clickable until it collapses again |
| `peekOpacity` | `0.25` | With click-through on, the pill fades to this while the cursor is over it (1 = no fade) |
| `fullscreenNotch` | `true` | While a fullscreen app is in front, show a slim notch at the top edge instead of the pill |
| `expandedWidth` | `400` | Width of the expanded island. It keeps one size so the buttons are always in the same place |
| `expandedHeight` | `0` | Height of the expanded island. `0` = just tall enough for its tallest panel, so it never resizes when you switch panels |
| `expandedOpacity` | `0.92` | How dark the background gets while expanded, so text stays readable |
| `fullscreenClock` | `true` | In fullscreen, the notch shows the time when nothing else is going on |
| `popups` | `true` | Short notices in the island (and the fullscreen notch). Turn single kinds off below or in the tray menu → Popups |
| `popupSeconds` | `3` | How long a notice stays |
| `popupDevices` | `true` | Headphones, mouse, keyboard, USB drive, phone or camera connected / removed |
| `popupVolume` | `true` | Volume (and laptop screen brightness) changed: a slim bar |
| `popupAudioOutput` | `true` | Sound output switched, with the device name |
| `popupLocks` | `true` | Caps Lock / Num Lock on or off |
| `popupBattery` | `true` | Charger plugged in or out, battery at 20 / 10 / 5% (laptops) |
| `popupNetwork` | `true` | Wi-Fi (with its name) or Ethernet connected / lost, VPN on / off |
| `popupScreenshots` | `true` | A screenshot was saved to Pictures\Screenshots: a preview, click it to open |
| `popupDownloads` | `true` | A download finished in your Downloads folder: click it to show the file |
| `popupClipboard` | `true` | Something was copied: a short preview (password managers' copies are skipped) |
| `popupFocus` | `true` | Do Not Disturb turned on or off |
| `calendarIcsUrl` | `""` | Your calendar's private iCal link (Google Calendar: Settings → your calendar → "Secret address in iCal format"; Outlook.com: Settings → Calendar → Shared calendars → Publish). Then you get a reminder before each meeting. Repeating meetings aren't picked up yet |
| `calendarMinutes` | `5` | How many minutes before a meeting to remind you |
| `timerMinutes` | `25` | Pomodoro focus length (tray menu → Timer) |
| `breakMinutes` | `5` | Pomodoro break length |
| `popupGitHub` | `true` | Your open pull requests: checks passed / failed, approved, changes requested. Needs the [GitHub CLI](https://cli.github.com) installed and signed in (`gh auth login`) |
| `sleepAfterMinutes` | `5` | The companion falls asleep after this long without mouse or keyboard (0 = never) |
| `weatherCity` | `""` | A city (e.g. `Istanbul`) to show the weather in the stats panel, from Open-Meteo (free, no account) |
| `updateCheck` | `true` | Look for a newer release once a day (nothing installs without your click) |
| `updateRepo` | `kilicaslanalper/windows-notch` | The GitHub repo releases come from |
| `stats` | `true` | When nothing else is on, the pill shows system stats |
| `statsItems` | `cpu,gpu,ram,net` | Which stats to show, in order: `cpu`, `gpu`, `ram`, `net` (download / upload speed) |
| `mascot` | `pearl` | `off`, a blob color (`pearl`, `lemon`, `peach`, `rose`, `lilac`, `sky`, `mint`) or a folder name in `custom images` |

**Colors**: `accent` (working), `doneColor`, `needsColor`.

**Expanded island**: hover it (Ctrl+click first when click-through is on) to expand it. The round
buttons at the bottom stay in the same place: the left one opens music and volume controls (click or drag the bar, scroll to adjust, the
speaker mutes); the one on the right opens system stats. Click a button again to close its panel.

**System stats**: CPU and GPU load, RAM use and network speed work out of the box.
Temperatures need [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor)
running as administrator (free, MPL-2.0). The island reads the sensors it publishes to WMI,
so nothing is bundled here. NVIDIA GPU temperature also works without it,
through `nvidia-smi` from the NVIDIA driver.

API value is what the session would cost at API prices; on a Pro/Max plan you aren't billed this.
Only Claude Code sessions are tracked, not regular chats in the Claude app.

## Uninstall

Double-click **Uninstall.cmd**. It removes the hooks and the startup entry and stops
the island; this folder stays, so delete it if you want everything gone.

## Credits

Inspired by [Vorssaint](https://github.com/vorssaint/vorssaint-utils) by Vorssaint.
The price table, blob palette and animation timings are adapted from it. This
project isn't affiliated with or endorsed by Vorssaint.

## License

[GPL 3.0 or later](LICENSE), the same license as Vorssaint.
