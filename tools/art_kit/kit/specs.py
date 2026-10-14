"""The sprite contract with the game: sizes, frame order and facing (DESIGN.md 5.3, 5.4)."""

# Heroes: one-row sheet of 8 frames, facing right.
HERO_FRAME = (32, 48)
HERO_POSES = ["idle", "ready", "parry", "dodge", "jump", "hurt", "strike", "down"]

# Enemies: one-row sheet of 6 square frames, facing left. Every fighter is drawn at the same
# pixel density (sprite_pixel_size 0.045 in the data), so a bigger monster gets a bigger frame.
ENEMY_POSES = ["idle", "windup", "lunge", "contact", "hurt", "slam"]
ENEMY_FRAME = {
    "rotten_husk": 72,
    "bloat": 92,
    "gnat_swarm": 56,
    "shade": 72,
    "hollow_king": 108,
}
FIGHTER_PIXEL_SIZE = 0.045

# Portraits: square, transparent background, head and shoulders, same facing as the fighter.
PORTRAIT = 48
