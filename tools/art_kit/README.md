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

Game files go to `assets/...` (and a fighter's clip layout to `data/clips/<id>.tres`); zoomed
previews (on dark, mid and light backgrounds) to `tools/art_kit/preview/...` (not in git). Then
import in Godot (`run_game.bat` does it).
`python tools/art_kit/check.py` checks every file against the sprite contract below (sizes,
frame counts, alpha, nothing clipped, seamless ground textures, the clip rules).
Builds are deterministic: no unseeded randomness, same code = same pixels.

```bash
python tools/art_kit/check.py                                   # the contract
python tools/art_kit/check.py --legacy <dir>                    # + row 0 equals these old sheets
python tools/art_kit/check.py --require hero_brin enemy_husk    # + every Tier 1 clip exists
```

`--legacy <dir>` takes a folder holding `characters/<id>.png` and `enemies/<id>.png` one-row
sheets (for example a copy of the phase 9 sprites) and fails when a grid sheet's row 0 differs
from them by a single pixel. `--require` takes fighter modules or ids (or `all`).

Build times (one machine, October 2026): about 0.6 to 1 s per fighter frame; a hero with its
portrait and previews takes 6 to 13 s, an enemy 9 to 32 s. A hero's full Tier 1 set (about 85
frames) stays near 1 to 2 minutes, so there is no render cache.

## Hero portraits from pictures

The heroes' big portraits (players screen) and their small faces (everywhere else) are not drawn
here: they are painted pictures in `sources/portraits/` (`PROMPTS.md` there has the words used
with an AI image tool) that `python tools/art_kit/portraits_from_pictures.py [hero]` turns into
pixel art: `assets/sprites/portraits_big/<id>.png` (192x288, 64 colours, k-means in OKLab) and
`<id>_face.png` (64x64, the square in `faces.json`). The 48x48 portraits this kit draws for the
heroes are no longer shown (enemies still use theirs).

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
- `kit/sheet.py`, `kit/context.py` saving sheets and previews (`grid()`, `ctx.save_fighter()`).
- `kit/clips.py` animation clips: `cell_camera()` (the legacy camera padded to a bigger cell),
  `render_clips()`, `pack()` (grid sheet + clip map), `write_tres()` / `read_tres()` (the
  `SpriteClips` resource) and `previews()` (a GIF per clip and a labelled contact sheet).
- `kit/beast.py` helpers for the phase 12 monsters (fly, hyena, toad): safe cones, a decal
  painter, finishing passes, the floor-line nudge, parallel clip rendering, `build_enemy()`.
- `kit/specs.py` the sprite contract (sizes, frame order, sheet grid, Tier 1 clip names).
- `assets/<module>.py` one module per asset group, each with `build(ctx)`. `env_zone` draws the
  long zones' things (phase 15): the rot seal, the gate tile, four shrines, three wanderers. `fx_attacks` draws
  the enemy attack effects of phase 12 (rock spikes, projectiles).

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
| Hero sheet `sprites/characters/<id>.png` | grid of 48x56 cells, 8 columns | row 0: idle, ready, parry, dodge, jump, hurt, strike, down; then one row per clip | right |
| Enemy sheet `sprites/enemies/<id>.png` | grid of square cells (`ENEMY_FRAME`), 8 columns | row 0: idle, windup, lunge, contact, hurt, slam (cells 6 and 7 clear); then one row per clip | left |
| Clips `data/clips/<id>.tres` | `SpriteClips`: frame_size, hframes, vframes, body_width_px, clips | generated with the sheet, never edited by hand | - |
| Portrait `sprites/portraits/<id>.png` | 48x48 | one | as the fighter |
| Ground textures `sprites/env/*_tile.png`, `cliff.png`, `ruin_wall.png` | 32x32, seamless | - | - |
| Props `sprites/env/<prop>.png` | as before | - | - |
| Backdrop `sprites/env/backdrop*.png` | 320x120 | - | - |
| Effects `sprites/fx/*.png`, HUD icons `sprites/ui/*.png` | as before | - | - |

- Fighters stand on the bottom: feet on the second-to-last row (the outline takes the last), body
  centred left to right. The game measures frame 0 (idle) for where popups go above the head, so
  idle should be the fighter's normal full height. The jump pose stays inside the frame (the game
  lifts the sprite itself).
- Hero cells are 48x56: the poses were drawn in 32x48 frames, and a cell is that frame with 8
  clear pixels added on the left, the right and the top (`HERO_CELL`), so swings, leaps and the
  shield have room. Render them with `kit.clips.cell_camera(Camera(32, 48), HERO_CELL)` (or the
  module's own lifted camera): it renders a pose to exactly the old pixels. A plain
  `Camera(48, 56)` does not quite (a few pixels differ on some poses from float rounding).
  `body_width_px` stays 32 so the in-game shadow keeps its size. Enemies keep their squares.
- Fighter sheets are grids (`SHEET_COLS` 8, at most `MAX_SHEET` 4096 px a side; 16 columns only
  when 8 would be taller). Row 0 holds the legacy key poses in the order above, so the game's old
  pose numbers still work. Each clip starts a new row (a clip longer than 8 cells wraps).
  Identical cells are stored once; a clip may reuse any cell, the row-0 keys included.
- A clip lists only which cells play, in order; a repeated cell holds longer. The game decides
  how long a clip plays (`combat_visuals.tres`), never the art. Every cell keeps the rules above
  (1 clear pixel border, hard alpha, feet on the second-to-last row), except the airborne clips
  `jump_up`, `jump_down`, `leap` and the floating fighters (gnats, shade).
- Cell 0 is the idle key, and the game measures head, centre and popup anchors on it only. So
  every cell of `idle`, `stand_front` and `stand_back` keeps its top within 1 px of cell 0, and
  every cell of `ready` within 1 px of the ready key. Walk cycles put a foot on the floor on
  frames 0 and N/2 (the footstep moments).
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
from kit.clips import cell_camera, render_clips
from kit.render import Camera, render
from kit.post import finish
from kit.rig import blend
from kit.specs import HERO_BODY_W, HERO_CELL, HERO_FRAME, HERO_POSES

POSES = {"idle": {...}, "ready": {...}, ...}          # keyframes as plain dicts
# Clip name -> cells in play order: an int is a row-0 key, a dict a pose (often a blend).
CLIPS = {"idle": [0, blend(POSES["idle"], BREATH, 0.5), BREATH, blend(POSES["idle"], BREATH, 0.5)]}

def render_pose(pose, cam):
    return finish(render(model(pose), cam))

def build(ctx):
    cam = cell_camera(Camera(*HERO_FRAME), HERO_CELL)
    keys = [render_pose(POSES[name], cam) for name in HERO_POSES]
    cells = render_clips(CLIPS, lambda p: render_pose(p, cam))
    ctx.save_fighter("sprites/characters/example.png", keys, cells, HERO_CELL, HERO_BODY_W, "example")
```

`save_fighter` writes the grid sheet, `data/clips/<id>.tres` (both skipped with `--preview-only`),
the sheet preview, `preview/<module>/clips/<clip>.gif` (each clip at about game speed, 6x, on the
dark floor; lengths from `kit.clips.PREVIEW_MS`, overridable per module with `preview_ms=`) and
`preview/<module>/<module>_clips.png` (every clip as a labelled row of its cells). The game reads
the clips once `sprite_clips` in the fighter's `data/characters/<id>.tres` or
`data/enemies/<id>.tres` points at the generated file.

Look at the previews (`tools/art_kit/preview/...`) after every change; judge them at 1x as well
as zoomed. Keep poses as plain dicts (keyframes) so they blend into in-betweens (`kit.rig.blend`).
