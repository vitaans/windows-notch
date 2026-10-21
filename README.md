# Claude Island

A Dynamic-Island-style pill at the top-center of your screen for Windows 10/11.

**Claude Code**: what Claude is doing, when it needs you, and when a task is done
(with model, tokens, estimated API value and duration). Hover for every session.

**Now playing**: album art, title and artist, with an equalizer tinted to the cover.
Hover for a progress bar and previous / play-pause / next.

**Companion**: a little character beside the pill that reacts to all of it. Pick the
built-in blob or any folder in `companions` (make your own, see the README there).

It draws its own window, so Do Not Disturb doesn't hide it and nothing piles up in
the notification center. It never steals focus and stays out of Alt+Tab.

## Setup (once)

Double-click **Install.cmd**, then restart any open Claude Code sessions.

## Updating

Nothing to do. Replace files in this folder and the island notices within a few
seconds: a new `scripts\ClaudeIsland.ps1` restarts it automatically (only if the
new file has no errors), a new hook script is used on Claude's next step, and
`settings.json` and companion images apply live.

## Folder layout

| Path | What it is |
| --- | --- |
| `settings.json` | Your settings, edit any time (applied live) |
| `companions\` | One folder per companion |
| `scripts\` | The island, the Claude Code hook, install and uninstall |
| `data\agent-prices.json` | Model prices for the API-value estimate |
| `state\` | Running state and `island.log` (safe to delete) |

## Tray menu

Play a test run, Sound, Show while Claude works, Now playing, Companion,
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
| `mascot` | `pearl` | `off`, a blob color (`pearl`, `lemon`, `peach`, `rose`, `lilac`, `sky`, `mint`) or a companion folder name |

**Colors**: `accent` (working), `doneColor`, `needsColor`.

API value is what the session would cost at API prices; on a Pro/Max plan you aren't billed this.
Only Claude Code sessions are tracked, not regular chats in the Claude app.

## Uninstall

Double-click **Uninstall.cmd**. It removes the hooks and the startup entry and stops
the island; this folder stays, so delete it if you want everything gone.

## Credits

Price table, blob palette and animation timings adapted from
[Vorssaint](https://github.com/vorssaint/vorssaint-utils) (GPL-3.0). Personal use.
