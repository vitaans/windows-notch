# Custom images

Each folder here is a companion: a little character, named after its folder. Pick one from the tray icon → **Companion**.
New folders show up in that menu right away, and when you edit the images of the
companion you're using, the island picks up the change within a couple of seconds.

**Charlie** is the example. To make your own, create a folder here with its name (like `Charlie`), put the images in it, and follow the step-by-step guide in
[docs/companions.md](../docs/companions.md): image sizes, file names for each mood,
animation frames and `companion.json`.

Quick reference:

| File | Shown when |
| --- | --- |
| `idle.png` | nothing special is happening (**required**) |
| `working.png` | Claude is working |
| `needs.png` | Claude needs your input |
| `done.png` | a task just finished |
| `music.png` | music is playing |

Animate a mood with numbered frames: `idle_1.png`, `idle_2.png`, ...
