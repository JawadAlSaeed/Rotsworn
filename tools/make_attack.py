"""Writes enemy attack data files (data/enemy_attacks/<id>.tres) from a short Python spec.

    python tools/make_attack.py            # writes every attack in ATTACKS below that is missing
    python tools/make_attack.py --force    # rewrites them all

Godot can edit the files afterwards like any other; this only saves typing the sub-resources.
Hit spec: dict(at=ms, dmg=percent, kind="normal"|"ground", approach=ms, feint=bool,
projectile="<id in data/projectiles>", look="wave"|"rocks", sfx="<impact cue>", anim="<prefix>").
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "enemy_attacks")
MODES = {"single": 0, "party": 1, "each": 2}
KINDS = {"normal": 0, "ground": 1}
LOOKS = {"wave": 0, "rocks": 1}

# id: (display name, target mode, weight, hits, extra attack fields)
ATTACKS: dict[str, tuple] = {
    # Phase 12 step 1: new moves for the first monsters (DESIGN.md 2.14).
    "husk_rock_toss": ("Rock Toss", "single", 2, [
        dict(at=1300, dmg=110, approach=600, projectile="thrown_stone"),
    ], {}),
    "husk_stone_spikes": ("Stone Spikes", "single", 2, [
        dict(at=1300, dmg=100, kind="ground", approach=650, look="rocks"),
    ], {}),
    "bloat_bile_spit": ("Bile Spit", "single", 2, [
        dict(at=1400, dmg=120, approach=650, projectile="bile_glob"),
    ], {}),
    "bloat_bile_rain": ("Bile Rain", "party", 1, [
        dict(at=1300, dmg=55, approach=750, projectile="bile_glob"),
        dict(at=2000, dmg=55, approach=650, projectile="bile_glob"),
    ], {}),
    "bloat_quake": ("Quake", "party", 1, [
        dict(at=1300, dmg=75, kind="ground", approach=700, look="rocks"),
    ], {}),
    "gnat_swarm_round": ("Swarm Round", "each", 2, [
        dict(at=900, dmg=40, approach=200),
        dict(at=1300, dmg=40, approach=220),
        dict(at=1700, dmg=40, approach=220),
    ], {}),
    "shade_bolts": ("Shadow Bolts", "single", 2, [
        dict(at=1000, dmg=40, approach=500, projectile="shade_bolt"),
        dict(at=1450, dmg=40, approach=420, projectile="shade_bolt"),
        dict(at=1800, dmg=40, approach=320, projectile="shade_bolt"),
    ], {}),
    "shade_grave_spikes": ("Grave Spikes", "single", 1, [
        dict(at=900, dmg=45, approach=200),
        dict(at=1700, dmg=60, kind="ground", approach=600, look="rocks"),
    ], {}),
    # Phase 12 step 2: the new monsters (DESIGN.md 2.15).
    "fly_dive": ("Dive", "single", 3, [
        dict(at=1100, dmg=110, approach=140),
    ], {}),
    "fly_buzz_dive": ("Buzz Dive", "single", 2, [
        dict(at=900, dmg=50, approach=150),
        dict(at=1450, dmg=50, approach=130),
        dict(at=1750, dmg=50, approach=130),
    ], {}),
    "fly_maggot_spit": ("Maggot Spit", "single", 2, [
        dict(at=1200, dmg=90, approach=420, projectile="bile_glob"),
    ], {}),
    "fly_strafe": ("Strafe", "each", 1, [
        dict(at=900, dmg=45, approach=150),
        dict(at=1250, dmg=45, approach=150),
        dict(at=1600, dmg=45, approach=150),
    ], {}),
    "hyena_pack_bite": ("Pack Bite", "each", 3, [
        dict(at=900, dmg=40, approach=220),
        dict(at=1250, dmg=40, approach=200),
        dict(at=1600, dmg=40, approach=200),
    ], {}),
    "hyena_snap": ("Snap", "single", 2, [
        dict(at=800, dmg=80, approach=200),
    ], {}),
    "hyena_cackle": ("Cackle", "single", 2, [
        dict(at=1500, dmg=110, approach=220, feint=True),
    ], {"allow_timing_ring": "false"}),
    "hyena_pounce": ("Pounce", "single", 1, [
        dict(at=1300, dmg=140, approach=420),
    ], {}),
    "toad_hop_hop": ("Hop Hop Hop", "party", 3, [
        dict(at=1100, dmg=45, kind="ground", approach=450),
        dict(at=1600, dmg=45, kind="ground", approach=450),
        dict(at=2100, dmg=45, kind="ground", approach=450),
    ], {}),
    "toad_tongue": ("Tongue Lash", "single", 2, [
        dict(at=1150, dmg=110, approach=170),
    ], {}),
    "toad_mud_spit": ("Mud Spit", "single", 2, [
        dict(at=1300, dmg=100, approach=550, projectile="mud_glob"),
    ], {}),
    "toad_belly_flop": ("Belly Flop", "party", 1, [
        dict(at=1500, dmg=100, kind="ground", approach=650, look="rocks"),
    ], {}),
    # Phase 12 step 3: each variant's own move (DESIGN.md 2.16).
    "ashen_cinder_hail": ("Cinder Hail", "party", 2, [
        dict(at=1200, dmg=50, approach=600, projectile="cinder"),
        dict(at=1750, dmg=50, approach=500, projectile="cinder"),
    ], {}),
    "blight_bile_flood": ("Bile Flood", "single", 2, [
        dict(at=950, dmg=45, approach=450, projectile="bile_glob"),
        dict(at=1300, dmg=45, approach=380, projectile="bile_glob"),
        dict(at=1650, dmg=45, approach=350, projectile="bile_glob"),
    ], {}),
    "blood_rush": ("Blood Rush", "each", 2, [
        dict(at=800, dmg=30, approach=180),
        dict(at=1100, dmg=30, approach=180),
        dict(at=1400, dmg=30, approach=180),
        dict(at=1700, dmg=30, approach=180),
        dict(at=2000, dmg=30, approach=180),
    ], {}),
    "hollow_bolt_storm": ("Bolt Storm", "party", 2, [
        dict(at=1000, dmg=45, approach=520, projectile="shade_bolt"),
        dict(at=1500, dmg=45, approach=420, projectile="shade_bolt"),
    ], {}),
    "bone_frenzy": ("Frenzy", "each", 2, [
        dict(at=800, dmg=40, approach=180),
        dict(at=1100, dmg=40, approach=180),
        dict(at=1400, dmg=40, approach=180),
        dict(at=1700, dmg=40, approach=180),
    ], {}),
    "plague_spit": ("Plague Spit", "party", 2, [
        dict(at=1200, dmg=60, approach=500, projectile="bile_glob"),
    ], {}),
    "elder_quake_hop": ("Quake Hop", "party", 2, [
        dict(at=1100, dmg=50, kind="ground", approach=500, look="rocks"),
        dict(at=1700, dmg=50, kind="ground", approach=450),
        dict(at=2300, dmg=50, kind="ground", approach=550, look="rocks"),
    ], {}),
}


def hit_block(rid: str, h: dict, projectiles: dict[str, str]) -> str:
    lines = ['[sub_resource type="Resource" id="%s"]' % rid, 'script = ExtResource("1_hit")',
             "impact_ms = %d" % h["at"]]
    kind = KINDS[h.get("kind", "normal")]
    if kind:
        lines.append("kind = %d" % kind)
    lines.append("damage_percent = %d" % h["dmg"])
    lines.append("approach_ms = %d" % h.get("approach", 200))
    if h.get("feint"):
        lines.append("feint = true")
    if h.get("projectile"):
        lines.append('projectile = ExtResource("%s")' % projectiles[h["projectile"]])
    look = LOOKS[h.get("look", "wave")]
    if look:
        lines.append("ground_look = %d" % look)
    if h.get("sfx"):
        lines.append('impact_sfx = "%s"' % h["sfx"])
    if h.get("anim"):
        lines.append('anim = "%s"' % h["anim"])
    return "\n".join(lines)


def write(aid: str, spec: tuple) -> str:
    name, mode, weight, hits, extra = spec
    projectiles: dict[str, str] = {}
    ext = ['[ext_resource type="Script" path="res://scripts/data/attack_hit_data.gd" id="1_hit"]',
           '[ext_resource type="Script" path="res://scripts/data/enemy_attack_data.gd" id="2_attack"]']
    for h in hits:
        p = h.get("projectile")
        if p and p not in projectiles:
            projectiles[p] = "%d_%s" % (len(projectiles) + 3, p)
            ext.append('[ext_resource type="Resource" path="res://data/projectiles/%s.tres" id="%s"]'
                       % (p, projectiles[p]))
    subs = [hit_block("Hit_%d" % i, h, projectiles) for i, h in enumerate(hits)]
    res = ["[resource]", 'script = ExtResource("2_attack")', 'id = "%s"' % aid,
           'display_name = "%s"' % name]
    if MODES[mode]:
        res.append("target_mode = %d" % MODES[mode])
    res.append("weight = %d" % weight)
    for k, v in extra.items():
        res.append("%s = %s" % (k, v))
    res.append('hits = Array[ExtResource("1_hit")]([%s])'
               % ", ".join('SubResource("Hit_%d")' % i for i in range(len(hits))))
    text = '[gd_resource type="Resource" script_class="EnemyAttackData" format=3]\n\n' + "\n".join(ext) \
        + "\n\n" + "\n\n".join(subs) + "\n\n" + "\n".join(res) + "\n"
    path = os.path.join(OUT, aid + ".tres")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    return path


def main() -> int:
    force = "--force" in sys.argv
    for aid, spec in ATTACKS.items():
        path = os.path.join(OUT, aid + ".tres")
        if force or not os.path.exists(path):
            print("wrote", os.path.relpath(write(aid, spec), ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
