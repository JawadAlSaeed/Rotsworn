"""Review sheet: every piece side by side, as the game shows it (DESIGN.md 5.6).

Each surface wears its pixel texture laid in world space (box projection, nearest pixels, one tile
per `world_size` metres, the game's triplanar mapping), multiplied by the vertex colours, lit by
one sun from the upper left, seen from the zone camera's angle. Names under the pieces. For
review only: the game never reads it. Call after export (it gives the materials node trees).
"""
from __future__ import annotations

import math
import os

import bpy
from mathutils import Vector

from kit.piece import Piece

ENV = "assets/sprites/env"
GAP = 0.9
# Pieces per row fill about this many metres; rows stand ROW_GAP apart, going away.
ROW_WIDTH = 13.0
ROW_GAP = 3.6
# The pitch the walkable zones' follow camera had (offset 0, 7, 11; the zones went in phase 26,
# DESIGN.md 8.22): a high view that shows every piece's top and front.
CAMERA_PITCH = math.atan2(7.0, 11.0)


def _surface_material(mat: bpy.types.Material, texture: str, world_size: float, root: str,
                      glow: float = 0.0, glow_color=(1.0, 1.0, 1.0)) -> None:
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 1.0
    for name in ("Specular IOR Level", "Specular"):
        if name in bsdf.inputs:
            bsdf.inputs[name].default_value = 0.0
    geo = nodes.new("ShaderNodeNewGeometry")
    scale = nodes.new("ShaderNodeVectorMath")
    scale.operation = "SCALE"
    scale.inputs["Scale"].default_value = 1.0 / world_size
    tex = nodes.new("ShaderNodeTexImage")
    tex.projection = "BOX"
    tex.projection_blend = 0.0
    tex.interpolation = "Closest"
    path = os.path.join(root, ENV, texture)
    if os.path.exists(path):
        tex.image = bpy.data.images.load(path, check_existing=True)
    col = nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Col"
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs["Factor"].default_value = 1.0
    links.new(geo.outputs["Position"], scale.inputs[0])
    links.new(scale.outputs["Vector"], tex.inputs["Vector"])
    links.new(tex.outputs["Color"], mix.inputs[6])
    links.new(col.outputs["Color"], mix.inputs[7])
    links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    if glow > 0.0:
        # The game's glow: the texture times the glow colour.
        tint = nodes.new("ShaderNodeMix")
        tint.data_type = "RGBA"
        tint.blend_type = "MULTIPLY"
        tint.inputs["Factor"].default_value = 1.0
        tint.inputs[7].default_value = (glow_color[0], glow_color[1], glow_color[2], 1.0)
        links.new(tex.outputs["Color"], tint.inputs[6])
        links.new(tint.outputs[2], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = glow
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])


def _label(text: str, at: Vector) -> None:
    curve = bpy.data.curves.new("label_" + text, "FONT")
    curve.body = text.replace("_", " ")
    curve.align_x = "CENTER"
    curve.size = 0.22
    obj = bpy.data.objects.new("label_" + text, curve)
    obj.location = at
    obj.rotation_euler = (math.pi * 0.5 - CAMERA_PITCH, 0.0, 0.0)
    mat = bpy.data.materials.new("label")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    emit = nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = (1.0, 0.85, 0.45, 1.0)
    out = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    curve.materials.append(mat)
    bpy.context.scene.collection.objects.link(obj)


def render(pieces: list[tuple[Piece, bpy.types.Object]], path: str, root: str) -> None:
    scene = bpy.context.scene
    # Rows of pieces, the first row nearest the camera, each centred.
    rows: list[list] = [[]]
    used = 0.0
    for piece, obj in pieces:
        w = obj.dimensions.x
        if rows[-1] and used + w > ROW_WIDTH:
            rows.append([])
            used = 0.0
        rows[-1].append((piece, obj))
        used += w + GAP
    width = 0.0
    tallest = 0.0
    for r, row in enumerate(rows):
        total = sum(obj.dimensions.x for _, obj in row) + GAP * (len(row) - 1)
        width = max(width, total)
        x = -total * 0.5
        y = r * ROW_GAP
        for piece, obj in row:
            for i, s in enumerate(piece.surfaces):
                if i < len(obj.data.materials):
                    # Pieces share material names ("stone"); each needs its own texture here.
                    own = obj.data.materials[i].copy()
                    obj.data.materials[i] = own
                    _surface_material(own, s.texture, s.world_size, root, s.glow, s.glow_color)
            w = obj.dimensions.x
            obj.location = Vector((x + w * 0.5, y, 0.0))
            _label(piece.name, Vector((x + w * 0.5, y - obj.dimensions.y * 0.5 - 0.45, 0.0)))
            tallest = max(tallest, obj.dimensions.z)
            x += w + GAP
    depth = (len(rows) - 1) * ROW_GAP
    # The ground: a dark plane to stand on.
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0.0, depth * 0.5, 0.0))
    ground = bpy.context.active_object
    ground.scale = (width + 8.0, depth + 14.0, 1.0)
    gmat = bpy.data.materials.new("ground")
    gmat.use_nodes = True
    gmat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.05, 0.045, 0.04, 1.0)
    ground.data.materials.append(gmat)

    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.2
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(50.0), 0.0, math.radians(-40.0))
    scene.collection.objects.link(sun)
    world = scene.world or bpy.data.worlds.new("world")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.22, 0.24, 0.32, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6

    cam_data = bpy.data.cameras.new("preview")
    cam_data.lens = 50.0
    cam = bpy.data.objects.new("preview", cam_data)
    scene.collection.objects.link(cam)
    centre = Vector((0.0, depth * 0.5 - 0.3, tallest * 0.35))
    dist = max(width * 1.5, depth * 2.6, 6.0)
    cam.location = centre + Vector((0.0, -math.cos(CAMERA_PITCH) * dist, math.sin(CAMERA_PITCH) * dist))
    cam.rotation_euler = (math.pi * 0.5 - CAMERA_PITCH, 0.0, 0.0)
    scene.camera = cam

    engines = {e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x, scene.render.resolution_y = 1600, 1000
    scene.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)
