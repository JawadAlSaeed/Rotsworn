# Art kit: the game's pixel art, drawn by code

Every sprite, portrait, ground texture, prop, effect and HUD icon in `assets/sprites/` is made
here. Characters, monsters and props are small 3D models built from simple shapes (spheres,
capsules, boxes, extruded outlines) and rendered straight into pixel art: one palette colour per
pixel, no blur, shaded by one light, outlined. Flat things (ground tiles, effects, icons) are
drawn in 2D with the same palette. Because models are posed by a skeleton, new animation frames
(phase 10) are just more poses.

Needs Python 3.11+ with numpy and Pillow.

```bash
python tools/art_kit/build.py                       # everything
python tools/art_kit/build.py hero_alder fx_ui      # some modules
python tools/art_kit/build.py --preview-only hero_alder   # previews only, game files untouched
```

Game files go to `assets/...`; zoomed previews (on dark, mid and light backgrounds) to
`tools/art_kit/preview/...` (not in git). Then import in Godot (`run_game.bat` does it).
`python tools/art_kit/check.py` checks every file against the sprite contract below (sizes,
frame counts, alpha, nothing clipped, seamless ground textures).
Builds are deterministic: no unseeded randomness, same code = same pixels.

## Files

- `kit/color.py` colour maths and hue-shifted ramps (OKLCH).
- `kit/palette.py` every shared material (`M["steel"]`, `M["cloth_red"]`, ...). A material is
  a ramp of colours (darkest first) plus how light maps onto it (spec, glow, dither, wrap).
- `kit/sdf.py` shapes (`Sphere`, `Ellipsoid`, `Box`, `RoundCone`, `Capsule`, `Cylinder`,
  `Torus`, `Prism`, `Custom`) and ways to combine them (`Union`, `SmoothUnion`, `Subtract`,
  `Intersect`, `Moved`). Axes: **x forward (the way the model faces), y up, z toward the viewer**.
  One unit = one sprite pixel at camera scale 1.
- `kit/render.py` `Camera` (orthographic, 3/4 view: yaw -28, pitch 10; `face="left"` for
  enemies) and `render()` into a `Frame`; overlays `line3d()` (1-pixel blades, staffs, straps,
  hair strands) and `stamp()` (tiny hand-drawn bits: eyes, mouths, emblems, rivets).
- `kit/post.py` `finish()` = inner contour lines + clean-up + outline, returns RGBA.
- `kit/rig.py` `Build` (proportions), `pose_skeleton()` (pose dict -> joints, IK for elbows and
  knees), `blend()` (in-between poses), `body()` (a plain clothed body to dress up).
- `kit/canvas.py` 2D drawing for tiles, effects and icons (`Canvas`).
- `kit/noise.py` value noise and Voronoi, both able to tile seamlessly.
- `kit/sheet.py`, `kit/context.py` saving sheets and previews.
- `kit/specs.py` the sprite contract (sizes, frame order).
- `assets/<module>.py` one module per asset group, each with `build(ctx)`.

## Style rules (the art bible)

**Look.** Octopath Traveler sprites in a dark, rotting fantasy world. The land is muted: greys,
olive and moss greens, browns, sickly violet rot. The heroes carry the strong colours so they pop:
Alder blue, Brin red, Cass gold. Worn gold is the game's accent (logo, menus): use it for trims,
emblems, the crown. Glows (rot-green, cyan, amber, violet) are rare and mean something: magic,
rot cores, lamps, eyes.

**Light.** One light for everything, from the upper left and a little in front (kit default).
Never change it per asset, so the whole cast reads as one scene. Glowing parts use emissive
materials (they ignore light).

**Colour.** Only palette colours: shared materials from `kit/palette.py` first; new ones with
`Material.make(name, base_hex)` (hue-shifted ramp: shadows lean violet, highlights warm). Keep each
material to its ramp (usually 5 colours). No pure black, no pure white; the darkest ink is
`palette.INK`.

**Outline.** A 1-pixel outline outside the silhouette in each material's own dark outline colour
(`finish()` does it), plus darker contour lines where one part passes in front of another. Leave
at least 1 clear pixel on every side of a frame for the outline.

**Pixels.** No anti-aliasing, no stray single pixels, no half-transparent pixels on fighters,
portraits, props or tiles (they are drawn with alpha cut: a pixel is fully there or not there).
Only effects (shadow, slash, spark, shockwave) may fade with alpha.

**Readability first.** At 1x zoom, on a dark background, you must tell who it is and what the pose
is. Silhouettes over detail: a clear shape with 3 to 5 big colour areas beats lots of tiny bits.
Faces at sprite size are 1 to 3 pixels of features (eyes, maybe brows); portraits have room for
a real face.

**Consistency.** Same camera (yaw, pitch, scale 1) for every fighter and prop, same proportions
across a character's poses (the rig keeps bone lengths fixed), same pixel density for every
fighter (`specs.FIGHTER_PIXEL_SIZE`).

## The sprite contract (see `kit/specs.py`)

| What | Size | Frames, in order | Facing |
|---|---|---|---|
| Hero sheet `sprites/characters/<id>.png` | 8 frames of 32x48 | idle, ready, parry, dodge, jump, hurt, strike, down | right |
| Enemy sheet `sprites/enemies/<id>.png` | 6 square frames (`ENEMY_FRAME`) | idle, windup, lunge, contact, hurt, slam | left |
| Portrait `sprites/portraits/<id>.png` | 48x48 | one | as the fighter |
| Ground textures `sprites/env/*_tile.png`, `cliff.png`, `ruin_wall.png` | 32x32, seamless | - | - |
| Props `sprites/env/<prop>.png` | as before | - | - |
| Backdrop `sprites/env/backdrop*.png` | 320x120 | - | - |
| Effects `sprites/fx/*.png`, HUD icons `sprites/ui/*.png` | as before | - | - |

- Fighters stand on the bottom: feet on the second-to-last row (the outline takes the last), body
  centred left to right. The game measures frame 0 (idle) for where popups go above the head, so
  idle should be the fighter's normal full height. The jump pose stays inside the frame (the game
  lifts the sprite itself).
- What the poses mean in the game. Heroes: **idle** standing at home (most of the fight);
  **ready** combat stance on their turn; **parry** blocking or deflecting a hit; **dodge**
  sidestepping back (away from the enemy, to the left); **jump** tucked in the air over a ground
  wave; **hurt** knocked back; **strike** attacking forward (right); **down** collapsed on the
  ground at 0 HP. Enemies: **idle** menacing stance; **windup** the tell before an attack (raise,
  coil, glow); **lunge** moving in on the target; **contact** the hit landing; **hurt** recoil;
  **slam** hitting the ground (ground-wave attacks).

## Making a module

```python
# tools/art_kit/assets/hero_example.py
from kit.palette import M
from kit.render import Camera, render
from kit.post import finish
from kit.sheet import hstack
from kit.sdf import Union, Sphere

def build(ctx):
    frames = []
    for pose in POSES:
        cam = Camera(32, 48)
        frame = render(model(pose), cam)
        frames.append(finish(frame))
    ctx.save("sprites/characters/example.png", hstack(frames), frame_w=32)
```

Look at the previews (`tools/art_kit/preview/...`) after every change; judge them at 1x as well
as zoomed. Keep poses as plain dicts (keyframes) so phase 10 can blend them into animations.
