"""The sprite contract with the game: sizes, frame order and facing (DESIGN.md 5.3, 5.4, 5.5)."""

# Heroes: the poses were drawn in 32x48 frames (HERO_FRAME). Since phase 10 they live in 48x56
# cells (HERO_CELL) on a grid sheet: the same pixels with 8 clear pixels added on the left, the
# right and the top, so swings, leaps and shields have room. The camera keeps its scale and centre,
# so a pose renders to the same pixels in both. HERO_BODY_W is the old frame width: the game sizes
# the shadow from it, so the shadow does not grow with the cell.
HERO_FRAME = (32, 48)
HERO_CELL = (48, 56)
HERO_BODY_W = 32
HERO_POSES = ["idle", "ready", "parry", "dodge", "jump", "hurt", "strike", "down"]

# Enemies: square cells (ENEMY_FRAME), facing left, poses in this order. Every fighter is drawn at
# the same pixel density (sprite_pixel_size 0.045 in the data), so a bigger monster gets a bigger
# frame. An art lane may enlarge its own enemy's square (kept centred, feet on the second-to-last
# row) if an arc clips; body_width_px stays the ENEMY_FRAME size so the shadow stays the same.
ENEMY_POSES = ["idle", "windup", "lunge", "contact", "hurt", "slam"]
ENEMY_FRAME = {
    "rotten_husk": 72,
    "bloat": 92,
    "gnat_swarm": 56,
    "shade": 72,
    "hollow_king": 108,
}
FIGHTER_PIXEL_SIZE = 0.045

# Fighter sheets are grids (plan 2.4, DESIGN 5.5): SHEET_COLS cells per row. Row 0 holds the legacy
# poses above in their order (enemy cells 6 and 7 stay empty); every clip starts its own row and
# wraps when longer than a row. MAX_SHEET px per side at most; kit.clips.pack switches to 16
# columns only when 8 would be taller than that.
SHEET_COLS = 8
SHEET_COLS_WIDE = 16
MAX_SHEET = 4096

# Clips whose cells may leave the floor (no feet-on-the-floor rule), and fighters that float.
AIRBORNE = {"jump_up", "jump_down", "leap"}
FLOATERS = {"gnat_swarm", "shade"}

# Looping stances: every cell keeps its opaque top within 1 px of the clip's key (cell 0 for idle
# and the stands, the ready key for ready), because the game measures head and popup anchors on
# cell 0 only.
STEADY_TOP = ("idle", "ready", "stand_front", "stand_back")
STEADY_TOP_PX = 1

# Fighter asset module -> clips id (data/clips/<id>.tres, sprites/<kind>/<id>.png).
FIGHTERS = {
    "hero_alder": "alder",
    "hero_brin": "brin",
    "hero_cass": "cass",
    "enemy_husk": "rotten_husk",
    "enemy_bloat": "bloat",
    "enemy_gnats": "gnat_swarm",
    "enemy_shade": "shade",
    "enemy_king": "hollow_king",
}

# Tier 1 clip names (plan 4.1, 4.2). check.py --require <module or id> asserts them.
TIER1_HERO = ["idle", "ready", "draw", "parry", "parry_hit", "dodge", "jump_up", "jump_down", "hurt",
              "stagger", "strike_windup", "strike", "strike_alt_windup", "strike_alt",
              "strike_big_windup", "strike_big", "cast_windup", "cast", "leap", "fall", "get_up",
              "victory", "victory_hold"]
TIER1_LEADER = ["walk_side", "walk_front", "walk_back", "stand_front", "stand_back", "pickup"]
TIER1_LEADERS = {"brin"}
TIER1_ENEMY = ["idle", "windup", "windup_hold", "lunge", "contact", "recoil", "return", "slam",
               "slam_recover", "hurt", "stagger", "death", "walk", "chase"]

# Portraits: square, transparent background, head and shoulders, same facing as the fighter.
PORTRAIT = 48
