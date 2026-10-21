# Make your own companion

A companion is the little character that sits next to the pill and reacts to what
Claude is doing. It's just a folder of images, so you can draw one in any pixel-art
or image app, and the island picks it up live, with no restart.

This guide walks through making one from scratch. **Charlie**, the little robot in
`custom images\Charlie`, is the worked example.

## 1. What you're making

One small picture (or a short loop of pictures) for each mood:

| Mood | File name | When it shows |
| --- | --- | --- |
| idle | `idle.png` | Nothing special is happening. **The only required one.** |
| working | `working.png` | Claude is working |
| needs | `needs.png` | Claude is waiting on you (a permission or a question) |
| done | `done.png` | A task just finished |
| music | `music.png` | Music is playing and Claude is idle |

A mood without its own image falls back to `idle.png`, so you can start with a
single picture and add more later.

## 2. Pick a size and a style

The companion is drawn about 26 to 28 pixels tall on screen (you can change that,
see step 5), so keep the design bold and simple: a clear outline, a few colors and
big eyes read much better than fine detail.

- **Square canvas.** Anything square works. Charlie is drawn on a 16 x 16 grid.
- **Transparent background.** Save as PNG with transparency, otherwise you get a box
  around your character.
- **Pixel art:** draw at the real grid size (16 x 16 or 24 x 24), then export scaled
  up by a whole number (8x gives 128 x 128) with no smoothing. Set `"pixelated": true`
  in step 5 so the edges stay crisp.
- **Smooth art** (vector, painted): export around 128 x 128 and leave `pixelated` off.

Free tools that work well: [Piskel](https://www.piskelapp.com/) (in the browser,
made for small animations), [LibreSprite](https://libresprite.github.io/), or
[Aseprite](https://www.aseprite.org/) (paid). Anything that saves a PNG with
transparency works too.

Leave a pixel or two of empty space on the sides you want to animate into, like the
"!" that Charlie raises when Claude needs you.

## 3. Animate it (optional)

To animate a mood, save numbered frames instead of a single file:

```
idle_1.png  idle_2.png  idle_3.png  ...  idle_8.png
```

They play in order, on a loop, at the speed set by `fps` (step 5). A few tricks:

- **Blinking:** repeat the open-eyes frame several times and put one closed-eyes frame
  at the end. Charlie uses 8 idle frames: open x4, a glance left, open x2, blink.
- **Two-frame loops** feel lively for short moods: a bouncing "!" for needs, a
  sparkle for done, a hopping note for music.
- **Keep the body still** between frames and only move the eyes or small details.
  This stops the companion from looking jittery.
- In Piskel or Aseprite, draw the frames on the timeline, then export with
  "one file per frame" and rename them to `idle_1.png`, `idle_2.png` and so on.

`idle-1.png` and `idle 1.png` work as well. The numbers just need to count up.

## 4. Put it in a folder

Open the `custom images` folder (tray menu → **Companion** → **Open custom images folder**)
and create a folder named after your companion, then drop the images in it. The folder
name is the companion's name and what shows up in the menu.

```
custom images\
  Charlie\
    companion.json
    idle_1.png ... idle_8.png
    working_1.png ... working_4.png
    needs_1.png  needs_2.png
    done_1.png   done_2.png
    music_1.png  music_2.png
```

PNG is best. JPG, BMP and GIF also load (a GIF only shows its first frame, so use
numbered frames for animation).

## 5. Tune it with companion.json (optional)

Drop a `companion.json` next to the images:

```json
{
  "size": 28,
  "fps": 4,
  "pixelated": true,
  "breathe": false
}
```

| Key | Default | What it does |
| --- | --- | --- |
| `size` | `26` | Width and height on screen, 12 to 40. The pill is about 46 tall |
| `fps` | `6` | Frames per second for numbered frames. 3 to 6 suits pixel art |
| `pixelated` | `false` | `true` keeps pixel art sharp instead of smoothing it |
| `breathe` | `true` | A single still image gently breathes so it doesn't look frozen |

## 6. Try it out

1. Right-click the island's tray icon, open **Companion** and pick your folder.
   New folders show up there straight away.
2. Choose **Play a test run** from the same menu. It walks through working, needs you
   and done, so you can see every mood in a few seconds.
3. Keep your image app open and save over the files. The island reloads the companion
   you're using within a couple of seconds of any change.

The island adds its own motion on top of your frames: a hop when a task finishes, a
perk-up when Claude needs you and a bob while music plays. You don't need to draw
those yourself.

## Draw one with code

If you'd rather type than draw, [`examples/draw-charlie.ps1`](examples/draw-charlie.ps1)
builds Charlie from text grids, where each character is one pixel:

```
'...KKKKKKKKKK...'
'..KBBBBBBBBBBK..'
'..KBFEEFFEEFBK..'
```

Copy it, change the palette and the grids, set `-Out` to a new folder and run it:

```
powershell -ExecutionPolicy Bypass -File docs\examples\draw-charlie.ps1 -Out "custom images\My Robot"
```

## Sharing your companion

Only share art you made yourself, or art whose license allows it. If you used an AI
tool or someone else's sprite as a starting point, check where it came from first.
To share a companion, zip its folder; whoever gets it unzips it into their own
`custom images` folder.
