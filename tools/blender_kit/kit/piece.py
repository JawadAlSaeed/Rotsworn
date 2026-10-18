"""A piece's contract and its export to the game (DESIGN.md 5.6).

Contract (tools/blender_kit/check.py checks the files): one mesh at the origin, its footprint
centred on x and z, its foot at height 0, flat shaded, normals and vertex colours ("Col"), one
material per surface named like the surface (the game matches PieceSurfaceData.name to it), no
textures in the file, at most TRIANGLE_BUDGET triangles.
"""
from __future__ import annotations

import os
import random
from dataclasses import dataclass, field
from typing import Callable

import bmesh
import bpy
from mathutils import Vector

from kit import paint
from kit.parts import cut

TRIANGLE_BUDGET = 1500


@dataclass
class Surface:
    """One texture area of a piece. `texture` is the file in assets/sprites/env/ (written into a
    new data file and used by the preview; the game's own pick is in the data file). `glow` makes
    it light up in the game (lamp glass, coals)."""
    name: str
    texture: str
    world_size: float = 1.6
    glow: float = 0.0
    glow_color: tuple[float, float, float] = (1.0, 0.7, 0.35)


@dataclass
class Carried:
    """A flat sprite the piece carries in the game (a fire): assets/sprites/env/<sprite>, its
    bottom middle at `at` (Blender build coordinates, before the piece is centred)."""
    sprite: str
    at: tuple[float, float, float]
    glow: float = 1.0
    glow_color: tuple[float, float, float] = (1.0, 0.55, 0.25)
    sway: float = 0.02


@dataclass
class Piece:
    """`build(bm, rng)` adds the geometry (faces on surface indexes into `surfaces`) and returns
    the faces to paint dark. `moss` scales the moss tint (0: none)."""
    name: str
    build: Callable[[bmesh.types.BMesh, random.Random], set]
    seed: int
    surfaces: list[Surface] = field(default_factory=list)
    moss: float = 1.0
    carried: list[Carried] = field(default_factory=list)


def make(piece: Piece) -> bpy.types.Object:
    """Builds the piece into a new object in the scene (not exported)."""
    rng = random.Random(piece.seed)
    bm = bmesh.new()
    dark = piece.build(bm, rng) or set()
    # Nothing below the ground (roots dive into it), then the footprint centred, the foot at 0.
    cut(bm, Vector((0.0, 0.0, 0.0)), Vector((0.0, 0.0, -1.0)), fill=False)
    dark = {f for f in dark if f.is_valid}
    lo = Vector([min(v.co[i] for v in bm.verts) for i in range(3)])
    hi = Vector([max(v.co[i] for v in bm.verts) for i in range(3)])
    shift = Vector((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z))
    bmesh.ops.translate(bm, vec=shift, verts=bm.verts)
    bm.normal_update()
    for f in bm.faces:
        f.smooth = False
    paint.paint(bm, piece.seed, dark, piece.moss)
    mesh = bpy.data.meshes.new(piece.name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.color_attributes.active_color_name = paint.LAYER
    mesh.color_attributes.render_color_index = mesh.color_attributes.active_color_index
    for s in piece.surfaces:
        mat = bpy.data.materials.get(s.name) or bpy.data.materials.new(s.name)
        mesh.materials.append(mat)
    obj = bpy.data.objects.new(piece.name, mesh)
    obj["kit_shift"] = tuple(shift)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def game_size(obj: bpy.types.Object) -> Vector:
    """The piece's size in game axes: x, height (Blender z), depth (Blender y)."""
    d = obj.dimensions
    return Vector((d.x, d.z, d.y))


def write_data(piece: Piece, obj: bpy.types.Object, root: str) -> str:
    """Writes the piece's data file (data/pieces/<name>.tres) from its surfaces and carried
    sprites, unless it exists (the data file is the game's to tune). Returns its path, or "" if
    it was there."""
    path = os.path.join(root, "data", "pieces", piece.name + ".tres")
    if os.path.exists(path):
        return ""
    lines = ['[gd_resource type="Resource" script_class="WorldPieceData" format=3]', "",
             '[ext_resource type="Script" path="res://scripts/data/world_piece_data.gd" id="1_piece"]',
             '[ext_resource type="Script" path="res://scripts/data/piece_surface_data.gd" id="2_surface"]']
    if piece.carried:
        lines.append('[ext_resource type="Script" path="res://scripts/data/piece_sprite_data.gd" id="3_sprite"]')
    lines.append("")
    ids = []
    for s in piece.surfaces:
        ids.append("Resource_" + s.name)
        lines += ['[sub_resource type="Resource" id="Resource_%s"]' % s.name, 'script = ExtResource("2_surface")',
                  'name = "%s"' % s.name, 'texture_path = "res://assets/sprites/env/%s"' % s.texture]
        if abs(s.world_size - 1.6) > 1e-6:
            lines.append("texture_world_size = %s" % s.world_size)
        if s.glow > 0.0:
            lines += ["glow = %s" % s.glow, "glow_color = Color(%s, %s, %s, 1)" % s.glow_color]
        lines.append("")
    shift = Vector(obj.get("kit_shift", (0.0, 0.0, 0.0)))
    sprite_ids = []
    for k, c in enumerate(piece.carried):
        at = Vector(c.at) + shift
        sprite_ids.append("Resource_sprite%d" % k)
        lines += ['[sub_resource type="Resource" id="Resource_sprite%d"]' % k, 'script = ExtResource("3_sprite")',
                  'sprite_path = "res://assets/sprites/env/%s"' % c.sprite,
                  "offset = Vector3(%.3f, %.3f, %.3f)" % (at.x, at.z, -at.y),
                  "glow = %s" % c.glow, "glow_color = Color(%s, %s, %s, 1)" % c.glow_color, "sway = %s" % c.sway, ""]
    lines += ["[resource]", 'script = ExtResource("1_piece")', 'id = "%s"' % piece.name,
              'model_path = "res://assets/models/%s.glb"' % piece.name,
              'surfaces = Array[ExtResource("2_surface")]([%s])' % ", ".join('SubResource("%s")' % i for i in ids)]
    if sprite_ids:
        lines.append('sprites = Array[ExtResource("3_sprite")]([%s])' % ", ".join('SubResource("%s")' % i for i in sprite_ids))
    lines.append("")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    return path


def export(obj: bpy.types.Object, out_dir: str) -> str:
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, obj.name + ".glb")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_yup=True, export_vertex_color="ACTIVE", export_materials="EXPORT",
                              export_image_format="NONE", export_texcoords=False, export_normals=True)
    return path
