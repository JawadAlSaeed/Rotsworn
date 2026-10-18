"""Checks every 3D world piece against the contract (DESIGN.md 5.6). Plain Python, no Blender:

    python tools/blender_kit/check.py

For each assets/models/*.glb: one mesh on one node at the origin (no move, turn or scale), its
footprint centred on x and z, its foot at height 0, normals and vertex colours on every surface,
one named material per surface and no textures in the file, at most TRIANGLE_BUDGET triangles, a
snake_case name. For each data/pieces/*.tres: its model exists and its surfaces are named like the
model's materials (the game matches them by name). A model no piece uses is a warning. Exits 1 on
any error.
"""
from __future__ import annotations

import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MODELS = os.path.join(ROOT, "assets", "models")
PIECES = os.path.join(ROOT, "data", "pieces")
TRIANGLE_BUDGET = 1500  # kit/piece.py
EPS_FOOT = 0.002
EPS_CENTRE = 0.01


def read_glb(path: str) -> dict:
    with open(path, "rb") as f:
        data = f.read()
    magic, version, _ = struct.unpack("<4sII", data[:12])
    if magic != b"glTF" or version != 2:
        raise ValueError("not a glTF 2 binary")
    length, kind = struct.unpack("<II", data[12:20])
    if kind != 0x4E4F534A:
        raise ValueError("first chunk is not JSON")
    return json.loads(data[20:20 + length])


def check_model(path: str, errors: list[str]) -> list[str]:
    """Checks one model; returns its material names (surface order)."""
    name = os.path.basename(path)
    def err(msg: str) -> None:
        errors.append("%s: %s" % (name, msg))
    if not re.fullmatch(r"[a-z0-9_]+\.glb", name):
        err("name is not snake_case")
    try:
        g = read_glb(path)
    except (OSError, ValueError, json.JSONDecodeError) as ex:
        err("unreadable (%s)" % ex)
        return []
    meshes = g.get("meshes", [])
    if len(meshes) != 1:
        err("holds %d meshes (one expected)" % len(meshes))
        if not meshes:
            return []
    nodes = [n for n in g.get("nodes", []) if "mesh" in n]
    if len(nodes) != 1:
        err("%d nodes carry a mesh (one expected)" % len(nodes))
    for n in nodes:
        moved = any(v != 0 for v in n.get("translation", [0, 0, 0]))
        turned = n.get("rotation", [0, 0, 0, 1]) != [0, 0, 0, 1]
        scaled = n.get("scale", [1, 1, 1]) != [1, 1, 1]
        if moved or turned or scaled or "matrix" in n:
            err("its node is moved, turned or scaled (apply the transform)")
    if g.get("images") or g.get("textures"):
        err("carries textures (the game lays its own over it)")
    mats = g.get("materials", [])
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    triangles = 0
    names: list[str] = []
    acc = g.get("accessors", [])
    for i, prim in enumerate(meshes[0].get("primitives", [])):
        attrs = prim.get("attributes", {})
        for key in ("POSITION", "NORMAL", "COLOR_0"):
            if key not in attrs:
                err("surface %d has no %s" % (i, key))
        if prim.get("mode", 4) != 4:
            err("surface %d is not triangles" % i)
        if "POSITION" in attrs:
            a = acc[attrs["POSITION"]]
            lo = [min(lo[k], a["min"][k]) for k in range(3)]
            hi = [max(hi[k], a["max"][k]) for k in range(3)]
        count = acc[prim["indices"]]["count"] if "indices" in prim else acc[attrs["POSITION"]]["count"]
        triangles += count // 3
        m = prim.get("material")
        if m is None or m >= len(mats) or not mats[m].get("name"):
            err("surface %d has no named material" % i)
        else:
            names.append(mats[m]["name"])
    if len(set(names)) != len(names):
        err("two surfaces share a material name (%s)" % ", ".join(names))
    if lo[0] != float("inf"):
        if abs(lo[1]) > EPS_FOOT:
            err("its foot is at %.3f, not on the ground (0)" % lo[1])
        for k, axis in ((0, "x"), (2, "z")):
            mid = (lo[k] + hi[k]) * 0.5
            if abs(mid) > EPS_CENTRE:
                err("its footprint is off centre on %s by %.3f" % (axis, mid))
    if triangles > TRIANGLE_BUDGET:
        err("%d triangles (budget %d)" % (triangles, TRIANGLE_BUDGET))
    return names


def read_piece(path: str) -> tuple[str, list[str]]:
    """(model path, surface names in order) of a WorldPieceData .tres."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    subs = {m.group(1): m.group(2) for m in re.finditer(
        r'\[sub_resource type="Resource" id="([^"]+)"\]\n(.*?)(?=\n\[|\Z)', text, re.S)}
    main = text.split("[resource]", 1)[-1]
    model = re.search(r'model_path = "([^"]*)"', main)
    order = re.search(r"surfaces = Array\[[^\]]*\]\(\[(.*?)\]\)", main, re.S)
    names = []
    if order:
        for sid in re.findall(r'SubResource\("([^"]+)"\)', order.group(1)):
            n = re.search(r'name = "([^"]*)"', subs.get(sid, ""))
            names.append(n.group(1) if n else "")
    return (model.group(1) if model else ""), names


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []
    models = sorted(f for f in os.listdir(MODELS) if f.endswith(".glb")) if os.path.isdir(MODELS) else []
    surfaces = {m: check_model(os.path.join(MODELS, m), errors) for m in models}
    used = set()
    pieces = sorted(f for f in os.listdir(PIECES) if f.endswith(".tres")) if os.path.isdir(PIECES) else []
    for p in pieces:
        model, names = read_piece(os.path.join(PIECES, p))
        file = model.replace("res://assets/models/", "")
        if not model.startswith("res://assets/models/") or file not in surfaces:
            errors.append("%s: its model %s does not exist" % (p, model or "(none)"))
            continue
        used.add(file)
        if sorted(names) != sorted(surfaces[file]):
            errors.append("%s: surfaces %s do not match %s's materials %s"
                          % (p, names, file, surfaces[file]))
    for m in models:
        if m not in used:
            warnings.append("%s: no piece in data/pieces/ uses it" % m)
    for w in warnings:
        print("warning: " + w)
    for e in errors:
        print("error: " + e)
    print("blender check: %d models, %d pieces, %d errors, %d warnings"
          % (len(models), len(pieces), len(errors), len(warnings)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
