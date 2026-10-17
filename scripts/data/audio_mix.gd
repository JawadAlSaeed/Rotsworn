class_name AudioMix
extends Resource
## The sound mix numbers (data/audio/mix.tres): the Master limiter and how repeated cues are
## handled. Presentation-only; no rules number lives here.

## Master limiter: nothing passes this level, so three parries on one frame cannot clip.
@export_range(-12.0, 0.0, 0.1, "suffix:dB") var limiter_ceiling_db: float = -1.0
## Gain before the limiter. A little below 0 leaves headroom so the limiter rarely has to work.
@export_range(-12.0, 6.0, 0.1, "suffix:dB") var limiter_pre_gain_db: float = -2.0
## How fast the limiter lets go after a peak (seconds).
@export_range(0.01, 1.0, 0.01, "suffix:s") var limiter_release_s: float = 0.1
## The same cue is not started again inside this many ms (3 hurts on one frame sound as one).
@export_range(0, 500, 1, "suffix:ms") var cue_cooldown_ms: int = 30
