# Blender kit: the game's 3D world pieces, built by code

Walls, rocks, stumps and the other hard, solid things of the fight arenas (and, until phase 26, of
the walkable zones, DESIGN.md 8.22) are small 3D models built here in Blender by Python (DESIGN.md 5.6). Soft things (grass, ferns, reeds, bushes), people, animals,
heroes and monsters stay flat pixel art from `tools/art_kit/`.

Needs Blender 5.2 (`BLENDER_PATH`, here `D:/Blender/blender.exe`). Runs with no window:

```bash
D:/Blender/blender.exe --background --factory-startup --python tools/blender_kit/build.py
D:/Blender/blender.exe --background --factory-startup --python tools/blender_kit/build.py -- stump_rotten --preview
python tools/blender_kit/check.py
```

`build.py` writes one `.glb` per piece to `assets/models/` (or `--out DIR`) and prints each
piece's size in game axes (x, height, depth) and its triangles. `--preview [FILE]` renders the
review sheet (default `tools/blender_kit/preview/pieces.png`, not in git): every piece side by
side from the high angle the zones' camera had, wearing its pixel textures the way the game lays them, so a
piece can be judged without opening the game. Then import in Godot (`run_game.bat` does it).
Builds are deterministic: a fixed seed per piece, same code = same file.

## Layout

- `kit/parts.py` shapes: `box`, `tube`, `lathe` (a turned solid: columns, bowls, posts; fluted,
  jagged tops), `prism` (a slab from an outline: arch stones, headstones, signs), `lump` (a faceted
  rock), `cut`, `merge`, `brick_courses` (a broken brick wall), `loose_bricks`, `plank`, `profile`.
- `kit/paint.py` the vertex colours: moss in patches on faces that look up, a darker foot, dark
  faces (a hollow).
- `kit/piece.py` `Piece`, `Surface` (texture, world size, glow) and `Carried` (a flat sprite the
  piece carries: a fire, a crown), building a piece (`make`), its export and its data file
  (`write_data`: written once, never overwritten).
- `kit/preview.py` the review sheet.
- `pieces/` one module per group (`stone`, `wood`, `fire`, `shrines`, `ruins`, `ground`), each with a
  `PIECES` list; add a new module to `pieces/__init__.py`.
- `swap_props.py` (plain Python) puts a piece on every prop in `data/` that uses a sprite:
  `python tools/blender_kit/swap_props.py rock=rock:180 gravestone=gravestone:8 stump=stump_rotten:180:0.55`
  (`SPRITE=PIECE[:TURN[:SCALE]]`; `--dry-run` only counts).

## The contract (check.py)

- One mesh at the origin, front towards Blender's -Y (the game camera's side), footprint centred
  on x and y, foot at height 0 (`make` cuts away what is under the ground and centres it).
- Flat shaded, low-poly: at most 1500 triangles.
- Vertex colours `Col` (linear): the game multiplies them over the texture.
- One material per surface, named like the surface (`stone`, `bark`, `rot`). No textures in the
  file: the game lays the place's tileable pixel texture over each surface in world space.
- A texture world size of 1.6 makes one texture pixel 0.05 m, the same as a sprite prop's pixel.
  Brick courses of 0.4 m line up with `ruin_wall.png`'s rows.

## In the game

Each model has a piece file in `data/pieces/` (`WorldPieceData`): the model, per surface its
texture, texture world size and glow, and the flat sprites it carries. An arena (a `StageLook`'s
`arena_props` and `arena_blocks`) uses a piece two ways:

- a `ZonePropData` with `piece` set: the piece at its own size (times `scale`), turned by
  `rotation_y_degrees`, mirrored by `flip`;
- a `ZoneBlockData` with `piece` set: the piece stretched to the block's `size`.

The zones' shrines, rot seal, gate, exit signpost and chests had pieces too; they went with the
walkable zones in phase 26 (DESIGN.md 8.22, G7). `tools/dress_arenas.gd` places the arena pieces.

## A new piece, step by step

1. Write its builder in a `pieces/` module (at the size of the sprite it replaces: one sprite
   pixel is 0.05 m) and add it to that module's `PIECES`.
2. `build.py -- NAME --preview` and look at the sheet; repeat.
3. `build.py -- NAME` (writes the model and, the first time, `data/pieces/NAME.tres`).
4. `python tools/blender_kit/check.py`, then place it (`swap_props.py`, a look's arena props, or
   `tools/dress_arenas.gd`).
5. `run_tests.bat --no-pause` (it imports first).
