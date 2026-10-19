"""Writes enemy attack data files (data/enemy_attacks/<id>.tres) from a short Python spec.

    python tools/make_attack.py            # writes every attack in ATTACKS below that is missing
    python tools/make_attack.py --force    # rewrites them all

Godot can edit the files afterwards like any other; this only saves typing the sub-resources.
Hit spec: dict(at=ms, dmg=percent, kind="normal"|"ground"|"rend"|"sweep", approach=ms, feint=bool,
projectile="<id in data/projectiles>", look="wave"|"rocks", sfx="<impact cue>", anim="<prefix>",
forced="rend"|"sweep" (what a normal hit becomes in a hard fight, card #187),
forced_feint=bool (a feint in a hard fight only),
mark="rotting"|"blighted"|"weakened"|"burning"|"shocked"|"slowed"|"dazed"|"hushed" (a debuff the hit
leaves on a hero it lands on undefended),
mark_turns=int (its length, default 2), ap_drain=int (AP the hero loses to the hit),
hard_only=bool (the mark only comes in a hard fight: elite, guard, boss or deep variant; card #194)).
A support move (card #259) has mode "ally", no hits, and extra fields support (1 heal, 2 shield),
support_percent, support_below_percent, support_turns.
"""
from __future__ import annotations

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "enemy_attacks")
MODES = {"single": 0, "party": 1, "each": 2, "ally": 3}
KINDS = {"normal": 0, "ground": 1, "rend": 3, "sweep": 4}
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
        dict(at=1400, dmg=120, approach=650, projectile="bile_glob", mark="blighted"),
    ], {}),
    "bloat_bile_rain": ("Bile Rain", "party", 1, [
        dict(at=1300, dmg=55, approach=750, projectile="bile_glob"),
        dict(at=2000, dmg=55, approach=650, projectile="bile_glob"),
    ], {}),
    "bloat_quake": ("Quake", "party", 1, [
        dict(at=1300, dmg=75, kind="ground", approach=700, look="rocks"),
    ], {}),
    "gnat_swarm_round": ("Swarm Round", "each", 2, [
        dict(at=900, dmg=40, approach=200, forced_feint=True),
        dict(at=1250, dmg=40, approach=220),
        dict(at=1750, dmg=40, approach=220, forced="rend"),
    ], {}),
    "shade_bolts": ("Shadow Bolts", "single", 2, [
        dict(at=1000, dmg=40, approach=500, projectile="shade_bolt"),
        dict(at=1450, dmg=40, approach=420, projectile="shade_bolt"),
        dict(at=1800, dmg=40, approach=320, projectile="shade_bolt", ap_drain=1),
    ], {}),
    "shade_grave_spikes": ("Grave Spikes", "single", 1, [
        dict(at=900, dmg=45, approach=200, forced_feint=True),
        dict(at=1700, dmg=60, kind="ground", approach=600, look="rocks"),
    ], {}),
    # Phase 12 step 2: the new monsters (DESIGN.md 2.15).
    "fly_dive": ("Dive", "single", 3, [
        dict(at=1100, dmg=110, approach=140),
    ], {}),
    "fly_buzz_dive": ("Buzz Dive", "single", 2, [
        dict(at=900, dmg=50, approach=150),
        dict(at=1600, dmg=50, approach=130, forced="sweep", forced_feint=True),
        dict(at=1900, dmg=50, approach=130),
    ], {}),
    "fly_maggot_spit": ("Maggot Spit", "single", 2, [
        dict(at=1200, dmg=90, approach=420, projectile="bile_glob", mark="rotting"),
    ], {}),
    "fly_strafe": ("Strafe", "each", 1, [
        dict(at=900, dmg=45, approach=150, forced_feint=True),
        dict(at=1250, dmg=45, approach=150),
        dict(at=1700, dmg=45, approach=150, forced="sweep"),
    ], {}),
    "hyena_pack_bite": ("Pack Bite", "each", 3, [
        dict(at=900, dmg=40, approach=220),
        dict(at=1250, dmg=40, approach=200),
        dict(at=1950, dmg=40, approach=200, forced="rend", forced_feint=True, mark="weakened"),
    ], {}),
    "hyena_snap": ("Snap", "single", 2, [
        dict(at=800, dmg=80, approach=200),
    ], {}),
    "hyena_cackle": ("Cackle", "single", 2, [
        dict(at=1500, dmg=110, approach=220, feint=True, forced="sweep"),
    ], {"allow_timing_ring": "false"}),
    "hyena_pounce": ("Pounce", "single", 1, [
        dict(at=1300, dmg=140, approach=420, mark="weakened", hard_only=True),
    ], {}),
    "toad_hop_hop": ("Hop Hop Hop", "party", 3, [
        dict(at=1100, dmg=45, kind="ground", approach=450),
        dict(at=1600, dmg=45, kind="ground", approach=450),
        dict(at=2250, dmg=45, kind="ground", approach=450),
    ], {}),
    "toad_tongue": ("Tongue Lash", "single", 2, [
        dict(at=1150, dmg=110, approach=170, forced="rend"),
    ], {}),
    "toad_mud_spit": ("Mud Spit", "single", 2, [
        dict(at=1300, dmg=100, approach=550, projectile="mud_glob", mark="slowed"),
    ], {}),
    "toad_belly_flop": ("Belly Flop", "party", 1, [
        dict(at=1500, dmg=100, kind="ground", approach=650, look="rocks"),
    ], {}),
    # Phase 12 step 3: each variant's own move (DESIGN.md 2.16).
    "ashen_cinder_hail": ("Cinder Hail", "party", 2, [
        dict(at=1200, dmg=50, approach=600, projectile="cinder"),
        dict(at=1750, dmg=50, approach=500, projectile="cinder", mark="burning", hard_only=True),
    ], {}),
    "blight_bile_flood": ("Bile Flood", "single", 2, [
        dict(at=950, dmg=45, approach=450, projectile="bile_glob"),
        dict(at=1300, dmg=45, approach=380, projectile="bile_glob"),
        dict(at=1750, dmg=45, approach=350, projectile="bile_glob", mark="blighted", hard_only=True),
    ], {}),
    "blood_rush": ("Blood Rush", "each", 2, [
        dict(at=800, dmg=30, approach=180, feint=True),
        dict(at=1100, dmg=30, approach=180),
        dict(at=1350, dmg=30, approach=180),
        dict(at=1800, dmg=30, approach=180),
        dict(at=2100, dmg=30, approach=180, forced="sweep"),
    ], {}),
    "hollow_bolt_storm": ("Bolt Storm", "party", 2, [
        dict(at=1000, dmg=45, approach=520, projectile="shade_bolt"),
        dict(at=1500, dmg=45, approach=420, projectile="shade_bolt", mark="slowed", hard_only=True),
    ], {}),
    "bone_frenzy": ("Frenzy", "each", 2, [
        dict(at=800, dmg=40, approach=180),
        dict(at=1100, dmg=40, approach=180),
        dict(at=1800, dmg=40, approach=180, forced="rend", feint=True),
        dict(at=2050, dmg=40, approach=180),
    ], {}),
    "plague_spit": ("Plague Spit", "party", 2, [
        dict(at=1200, dmg=60, approach=500, projectile="bile_glob"),
    ], {}),
    "elder_quake_hop": ("Quake Hop", "party", 2, [
        dict(at=1100, dmg=50, kind="ground", approach=500, look="rocks"),
        dict(at=1700, dmg=50, kind="ground", approach=450),
        dict(at=2250, dmg=50, kind="ground", approach=550, look="rocks"),
    ], {}),
    # Phase 16 card #195: each guard's and act boss's signature Charged Doom (DESIGN.md 2.3). The
    # extra fields: charge_turns (enemy turns from the announcement), break_damage_percent (the
    # share of the enemy's max HP that breaks it), a cooldown, and a start cooldown so it never
    # opens a fight. Party-wide strings with uneven gaps; forced kinds (rend, sweep) for the
    # hard fights, where a sweep also takes the counter away.
    "husk_timber_fall": ("Timber Fall", "party", 14, [
        dict(at=1000, dmg=30, approach=380),
        dict(at=1450, dmg=30, approach=300, forced="rend"),
        dict(at=2300, dmg=34, kind="ground", approach=600, look="rocks"),
        dict(at=3000, dmg=32, approach=600, projectile="thrown_stone"),
        dict(at=3400, dmg=30, approach=260, forced="sweep"),
        dict(at=4300, dmg=38, kind="ground", approach=650),
        dict(at=5000, dmg=34, approach=320, forced="rend"),
        dict(at=5800, dmg=38, approach=300, forced_feint=True),
    ], {"charge_turns": 3, "break_damage_percent": 22, "cooldown_turns": 2, "start_cooldown_turns": 2}),
    "king_crown_of_rot": ("Crown of Rot", "party", 8, [
        dict(at=900, dmg=28, approach=180),
        dict(at=1250, dmg=28, approach=160, forced="rend"),
        dict(at=1950, dmg=28, approach=160, feint=True),
        dict(at=2600, dmg=32, kind="ground", approach=500),
        dict(at=3150, dmg=28, approach=160, forced="sweep"),
        dict(at=3800, dmg=30, approach=450, projectile="light_bolt"),
        dict(at=4200, dmg=30, approach=160, forced="rend"),
        dict(at=5000, dmg=36, kind="ground", approach=600, look="rocks"),
        dict(at=5600, dmg=30, approach=160, forced="sweep"),
        dict(at=6000, dmg=36, approach=160),
    ], {"charge_turns": 3, "break_damage_percent": 13, "cooldown_turns": 2, "start_cooldown_turns": 2}),
    "bloat_gorge_burst": ("Gorge Burst", "party", 7, [
        dict(at=1300, dmg=30, approach=650, projectile="bile_glob"),
        dict(at=1750, dmg=30, approach=500, projectile="bile_glob"),
        dict(at=2150, dmg=30, approach=450, projectile="bile_glob"),
        dict(at=3000, dmg=36, kind="ground", approach=700, look="rocks"),
        dict(at=3800, dmg=32, approach=300, forced="rend", forced_feint=True),
        dict(at=4600, dmg=36, kind="ground", approach=650),
        dict(at=5100, dmg=30, approach=400, projectile="bile_glob"),
        dict(at=5600, dmg=34, approach=300, forced="sweep"),
    ], {"charge_turns": 2, "break_damage_percent": 42, "cooldown_turns": 2, "start_cooldown_turns": 2}),
    "toad_brood_tide": ("Brood Tide", "party", 7, [
        dict(at=1100, dmg=34, kind="ground", approach=500),
        dict(at=1600, dmg=34, kind="ground", approach=450),
        dict(at=2300, dmg=30, approach=550, projectile="mud_glob", mark="slowed", hard_only=True),
        dict(at=2650, dmg=30, approach=170, forced="rend"),
        dict(at=3500, dmg=36, kind="ground", approach=650, look="rocks"),
        dict(at=4100, dmg=30, approach=450, projectile="mud_glob"),
        dict(at=4800, dmg=30, approach=170, forced="sweep", forced_feint=True),
        dict(at=5700, dmg=40, kind="ground", approach=700),
    ], {"charge_turns": 2, "break_damage_percent": 21, "cooldown_turns": 2, "start_cooldown_turns": 2}),
    "shade_ashfall": ("Ashfall", "party", 9, [
        dict(at=1200, dmg=28, approach=560, projectile="cinder"),
        dict(at=1650, dmg=28, approach=480, projectile="cinder"),
        dict(at=2100, dmg=28, approach=220, forced="rend"),
        dict(at=2900, dmg=34, kind="ground", approach=600, look="rocks"),
        dict(at=3500, dmg=28, approach=480, projectile="cinder", mark="burning", hard_only=True),
        dict(at=3950, dmg=28, approach=220, forced="sweep"),
        dict(at=4850, dmg=34, kind="ground", approach=650),
        dict(at=5450, dmg=32, approach=220, forced="rend", forced_feint=True),
    ], {"charge_turns": 2, "break_damage_percent": 36, "cooldown_turns": 2, "start_cooldown_turns": 2}),
    # Phase 19 (cards #255 to #260): the new monsters, each with one marking hit (card #253).
    # Rot Rats: small fry, always in threes; quick nibbles and one gnawing string that rots.
    "rat_nibble": ("Nibble", "single", 3, [
        dict(at=750, dmg=90, approach=160),
    ], {}),
    "rat_gnaw": ("Gnaw", "single", 2, [
        dict(at=700, dmg=30, approach=160, forced_feint=True),
        dict(at=960, dmg=30, approach=150),
        dict(at=1300, dmg=30, approach=150, forced="sweep"),
        dict(at=1600, dmg=30, approach=150, mark="rotting"),
    ], {}),
    "rat_scurry": ("Scurry", "each", 2, [
        dict(at=800, dmg=45, approach=170, forced_feint=True),
        dict(at=1150, dmg=45, approach=170),
        dict(at=1600, dmg=45, approach=170, forced="rend"),
    ], {}),
    "rat_tide": ("Rat Tide", "party", 1, [
        dict(at=900, dmg=35, approach=180),
        dict(at=1250, dmg=35, approach=180),
        dict(at=1850, dmg=35, approach=180, forced_feint=True),
    ], {}),
    # Ember Slinger: ranged only, every hit thrown.
    "slinger_pitch": ("Pitch Throw", "single", 3, [
        dict(at=1200, dmg=110, approach=520, projectile="pitch_glob"),
    ], {}),
    "slinger_volley": ("Ember Volley", "single", 2, [
        dict(at=950, dmg=40, approach=450, projectile="cinder"),
        dict(at=1300, dmg=40, approach=400, projectile="cinder"),
        dict(at=1700, dmg=40, approach=380, projectile="cinder"),
    ], {}),
    "slinger_firepot": ("Firepot", "party", 2, [
        dict(at=1400, dmg=75, approach=650, projectile="pitch_glob", mark="burning"),
    ], {}),
    "slinger_scatter": ("Scatter Shot", "each", 1, [
        dict(at=900, dmg=45, approach=420, projectile="cinder"),
        dict(at=1250, dmg=45, approach=380, projectile="cinder"),
        dict(at=1700, dmg=45, approach=350, projectile="cinder"),
    ], {}),
    # Barrow Brute: slow and huge; its Barrow Slam is a rend everywhere and dazes.
    "brute_maul": ("Grave Maul", "single", 3, [
        dict(at=1700, dmg=120, approach=320),
    ], {}),
    "brute_slam": ("Barrow Slam", "single", 2, [
        dict(at=2000, dmg=150, approach=300, kind="rend", mark="dazed", mark_turns=1, sfx="heavy_strike"),
    ], {"cooldown_turns": 1}),
    "brute_quake": ("Earth Breaker", "party", 2, [
        dict(at=1600, dmg=90, kind="ground", approach=700, look="rocks"),
    ], {}),
    "brute_sweep": ("Wide Swing", "party", 1, [
        dict(at=1500, dmg=85, approach=400, kind="sweep"),
    ], {}),
    "brute_double": ("Two Blows", "single", 1, [
        dict(at=1300, dmg=70, approach=280, forced_feint=True),
        dict(at=2200, dmg=80, approach=320, forced="rend"),
    ], {}),
    # Marsh Lantern: a floating caster, every hit a spark.
    "lantern_spark": ("Spark Bolt", "single", 3, [
        dict(at=1000, dmg=100, approach=320, projectile="spark_bolt"),
    ], {}),
    "lantern_zigzag": ("Zig-Zag", "single", 2, [
        dict(at=900, dmg=35, approach=440, projectile="spark_bolt"),
        dict(at=1240, dmg=35, approach=400, projectile="spark_bolt"),
        dict(at=1640, dmg=35, approach=380, projectile="spark_bolt", mark="shocked"),
    ], {}),
    "lantern_chain": ("Arc Chain", "each", 2, [
        dict(at=900, dmg=45, approach=340, projectile="spark_bolt"),
        dict(at=1200, dmg=45, approach=320, projectile="spark_bolt"),
        dict(at=1650, dmg=45, approach=300, projectile="spark_bolt"),
    ], {}),
    "lantern_burst": ("Static Burst", "party", 1, [
        dict(at=1300, dmg=60, approach=500, projectile="spark_bolt"),
    ], {}),
    # Rot Priest: a helper; weak strikes, a hushing word, and it heals or shields its fellows.
    "priest_censer": ("Censer Swing", "single", 3, [
        dict(at=1000, dmg=80, approach=240, forced_feint=True),
        dict(at=1550, dmg=40, approach=240, forced="rend"),
    ], {}),
    "priest_hush": ("Hush Word", "single", 2, [
        dict(at=1200, dmg=70, approach=500, projectile="shade_bolt", mark="hushed"),
    ], {}),
    "priest_mend": ("Mend Rot", "ally", 4, [], {"support": 1, "support_percent": 25, "support_below_percent": 75,
                                                 "max_in_a_row": 1, "cooldown_turns": 1}),
    "priest_ward": ("Bone Ward", "ally", 3, [], {"support": 2, "support_turns": 2, "cooldown_turns": 2}),
    # Pus Tick: announces its Burst like a Doom; the burst is a ground hit and spends the tick.
    "tick_latch": ("Latch", "single", 1, [
        dict(at=900, dmg=70, approach=200),
    ], {}),
    "tick_burst": ("Burst", "party", 20, [
        dict(at=1300, dmg=130, kind="ground", approach=550, mark="blighted", sfx="splat"),
    ], {"charge_turns": 3, "break_damage_percent": 50, "cooldown_turns": 1, "self_destruct": "true"}),
    # Their deep twins' own moves (DESIGN.md 2.16).
    "grave_rat_frenzy": ("Rat Frenzy", "each", 2, [
        dict(at=750, dmg=35, approach=150, forced_feint=True),
        dict(at=1000, dmg=35, approach=150),
        dict(at=1400, dmg=35, approach=150, forced="rend"),
        dict(at=1650, dmg=35, approach=150),
    ], {}),
    "cinder_fire_rain": ("Fire Rain", "party", 2, [
        dict(at=1200, dmg=50, approach=600, projectile="pitch_glob"),
        dict(at=1800, dmg=50, approach=520, projectile="pitch_glob", mark="burning", hard_only=True),
    ], {}),
    "tomb_grave_quake": ("Grave Quake", "party", 2, [
        dict(at=1500, dmg=70, kind="ground", approach=650, look="rocks"),
        dict(at=2300, dmg=70, kind="ground", approach=600),
    ], {}),
    "storm_thunderhead": ("Thunderhead", "party", 2, [
        dict(at=1000, dmg=45, approach=420, projectile="spark_bolt"),
        dict(at=1450, dmg=45, approach=330, projectile="spark_bolt"),
    ], {}),
    "hollow_litany": ("Black Litany", "party", 2, [
        dict(at=1100, dmg=40, approach=480, projectile="shade_bolt"),
        dict(at=1700, dmg=40, approach=420, projectile="shade_bolt"),
    ], {}),
    "bile_tick_spit": ("Bile Spit", "single", 2, [
        dict(at=1100, dmg=80, approach=450, projectile="bile_glob"),
    ], {}),
}


def hit_block(rid: str, h: dict, projectiles: dict[str, str]) -> str:
    lines = ['[sub_resource type="Resource" id="%s"]' % rid, 'script = ExtResource("1_hit")',
             "impact_ms = %d" % h["at"]]
    kind = KINDS[h.get("kind", "normal")]
    if kind:
        lines.append("kind = %d" % kind)
    if h.get("forced"):
        lines.append("forced_kind = %d" % KINDS[h["forced"]])
    lines.append("damage_percent = %d" % h["dmg"])
    lines.append("approach_ms = %d" % h.get("approach", 200))
    if h.get("feint"):
        lines.append("feint = true")
    if h.get("forced_feint"):
        lines.append("forced_feint = true")
    if h.get("projectile"):
        lines.append('projectile = ExtResource("%s")' % projectiles[h["projectile"]])
    look = LOOKS[h.get("look", "wave")]
    if look:
        lines.append("ground_look = %d" % look)
    if h.get("sfx"):
        lines.append('impact_sfx = "%s"' % h["sfx"])
    if h.get("anim"):
        lines.append('anim = "%s"' % h["anim"])
    if h.get("mark"):
        lines.append('on_hit_status = "%s"' % h["mark"])
        if h.get("mark_turns", 2) != 2:
            lines.append("on_hit_status_turns = %d" % h["mark_turns"])
    if h.get("ap_drain"):
        lines.append("on_hit_ap_drain = %d" % h["ap_drain"])
    if h.get("hard_only"):
        lines.append("on_hit_hard_only = true")
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
