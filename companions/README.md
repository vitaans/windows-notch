# Companions

Each folder here is a companion. Pick one from the tray icon → **Companion**.
New folders show up in that menu right away, and when you edit the images of the
companion you're using, the island picks up the change within a couple of seconds.

## Making one

Create a folder (its name is the companion's name) and put images in it:

| File | Shown when |
| --- | --- |
| `idle.png` | nothing special is happening (**required**) |
| `working.png` | Claude is working |
| `needs.png` | Claude needs your input |
| `done.png` | a task just finished |
| `music.png` | music is playing |

Any state without an image falls back to `idle.png`. PNG with a transparent
background works best; JPG, BMP and GIF also load (GIFs show their first frame only).

**Animation:** number the frames instead, e.g. `idle_1.png`, `idle_2.png`, `idle_3.png`.
They play in order, on a loop. To make a blink, repeat the open-eyes frame several
times and put one closed-eyes frame at the end (see Pixel Cat).

**Optional `companion.json`:**

```json
{
  "size": 26,
  "fps": 6,
  "pixelated": false,
  "breathe": true
}
```

- `size`: height and width on screen, 12 to 40 (the pill is about 46 tall)
- `fps`: frames per second for numbered frames
- `pixelated`: `true` keeps pixel art crisp instead of smoothing it
- `breathe`: a still (single-frame) image gently breathes so it doesn't look frozen

Square images look best. The island also adds its own motion on top: a hop when
a task finishes, a perk-up when Claude needs you and a bob while music plays.
