# Rotten Lands: design document

Living document. Update it whenever a decision is made. "Rotten Lands" is a placeholder name and
the setting is undecided, so every name below that belongs to content (characters, enemies, moves)
is a placeholder stored in data files.

- Engine: Godot 4.7.2 stable, GDScript, Windows PC.
- Players: 1 to 3, co-op. Party is always 3 characters. Humans control 1 to 3 of them; the host
  controls any character that has no player.
- Inputs: keyboard and gamepad from day one.

Contents: 1 Pillars, 2 Combat, 3 Defence timing, 4 Architecture, 5 Data, 6 Input, 7 Presentation,
8 Run structure, 9 Multiplayer, 10 Testing, 11 Phase plan, 12 Decision log.

---

## 1. Pillars

1. **Defence is the star.** Every enemy attack is a real-time test. A clean parry must feel
   great: crisp sound, hit-stop, flash, reward.
2. **Co-op synergy.** Follow-up strikes, shared team gauge, marks that other classes consume,
   team counters when everyone parries together.
3. **Readable, fair timing.** Windows are judged from input timestamps, not frames, every window
   is editable in one tuning file, and the game tells you *why* a defence failed (early, late,
   wrong button).
4. **Reskinnable.** Names, numbers, art and sound all come from data files and file paths.

---

## 2. Combat

### 2.1 Timeline (speed-based turn order)

Charge-time system, shown on screen as a row of upcoming turns.

- Every combatant has `speed` (int, data). One turn costs `timeline_base / speed` ticks (integer
  division; `timeline_base` is in tuning, default 10000).
- Each combatant stores `next_turn_at`. At fight start it is one turn cost (faster units go
  first). The living combatant with the lowest `next_turn_at` acts next; at the start of its turn
  `next_turn_at += turn cost`. The engine stores `time_now` (the `next_turn_at` the current turn
  started at).
- Ties: lower combatant id first (party ids are lower than enemy ids, then slot order).
- The HUD shows the current actor plus the next turns, `turn_order_preview` in total (default 8).
- Downed combatants are skipped.
- Phase 2 revive: `next_turn_at = time_now + turn cost` (so a revived unit never gets a burst of
  turns). Speed changes: `next_turn_at = time_now + (next_turn_at - time_now) x old / new`.
- Phase 3 opening advantage: party starts with a lower `next_turn_at`.

### 2.2 Party turn

The acting character picks an action:

- **Attack** (basic): single target, 100% of the character's power, one timed press (+25% on a
  good press). Grants AP (`ability.ap_gain`, +1). Does not consume Exposed.
- **Skill**: costs AP; the class kits are in 2.10. Every skill has timed presses.
- **Team Ultimate**: offered to everyone; needs a full team gauge (2.10).

Then the target: an enemy, an ally or a downed ally depending on the skill (left/right or
up/down to cycle). **When only one target is valid the target step is skipped.** The menu shows each ability's AP cost or gain and the selected ability's
description (plus "Needs N AP" when it cannot be afforded). A party action animation (dash,
strike, return) takes about 0.55 s.

### 2.3 Enemy turn

1. The enemy picks one of its attacks (weighted random, seeded RNG) and its targets:
   single-target attacks pick a random living party member, party-wide attacks target every
   living party member.
2. A **banner** at the top shows the attack name and either the one targeted character's name or
   "WHOLE PARTY". An alert sound plays once when the attack starts (not per hit).
3. The attack plays in real time. **Only targeted characters defend.** Each hit is resolved per
   target (see 3). Targets are marked: red arrows over them until the enemy starts moving, and a
   red border on their party panels for the whole attack. During a single-target attack the other
   party members step back and dim, so the lunge lane and the target are clear.

### 2.4 Defensive actions

| Action | Window (default) | Works against | Result |
|---|---|---|---|
| Dodge | 250 ms | normal hits | no damage, no reward |
| Parry | 150 ms | normal hits | no damage, +AP (`ap_per_parry`, 1) |
| Jump  | 220 ms | ground hits | no damage, +AP (`ap_per_jump`, default 0) |

- Ground hits (shockwaves along the floor) can only be avoided by jumping. Dodging or parrying
  them fails. Jumping into a normal hit fails.
- A press that matches nothing is a **whiff**: that player's defence buttons are locked for
  `whiff_lockout_ms` (300). **Pressing while locked restarts the lock.** A simulation showed this
  drops mashing success to 0% while an honest miss costs only that one hit. An isolated LATE
  whiff (no other press in the 300 ms before it) locks only until the next hit's first window
  opens (or not at all if it is already open), so a late press in a 300 ms string does not also
  cost the next hit. Presses close together never get this; a mash that happens to start with a
  late press can land one lucky press (a simulation measured under 5% per attack).
- One press defends one hit per character.
- A press shortly after a hit already landed (within `late_press_report_ms`, 400, of its impact)
  counts as a LATE whiff on that hit when it is nearer than the next hit, so a late reaction shows
  "LATE +150" instead of nothing or "EARLY" on the next hit. A press after a later hit was
  defended is never blamed on the earlier one (a double tap after the final parry is ignored).
- When a target goes down mid-attack its remaining hits are void: they cannot be defended or
  blamed, and once every target is down the rest of the attack is only animation (presses are
  ignored).

### 2.5 Counters

- A hit is **perfectly defended** by a Parry (normal hit) or a Jump (ground hit).
- A targeted character who perfectly defends **every** hit of an attack counterattacks for
  `counter_percent` (150%) of their power.
- If the attack was party-wide and **every** targeted character perfectly defended every hit,
  they strike together as one **Team Counter**: one hit whose damage is `team_counter_percent`
  (120%) of each character's power, added up (about 150 with the phase 1 party, 10% of the
  enemy). It has its own banner ("TEAM COUNTER!"), the attackers keep part of their formation at
  the strike point, and each lands its own slash. A solo counter shows "COUNTER!" over the enemy.
  Both freeze their slashes for the counter hit-stop.
- Phase 1 note: one player controls all three, so every perfect party-wide defence is a team
  counter. In phase 5, when several humans must sync, the team counter gets stronger again.
- If only some targets of a party-wide attack were perfect, each of those counters on their own.
- A character downed during the attack cannot counter, so no team counter that time.
- The counter starts `counter_delay_ms` (220) after the final hit-stop ends: the reward follows
  the last parry immediately.

### 2.6 AP (action points)

- Start each fight with `start_ap` (1). Cap `max_ap` (9).
- Gain: basic attack (+1), parry (+1 each), jump (tuning, default 0), Feint Step (+1, +2 on a
  good press), good presses on Taunt, Riposte Stance and Reveal (+1), Pass the Torch (gives 2, or
  3, to an ally).
- Spend: skills. The team ultimate costs no AP; it empties the team gauge.

### 2.7 HP and damage

- All multipliers are **integer percentages** (100 = x1) and damage maths is integer:
  `value x percent / 100`, rounded half up, minimum 1 (`CombatMath`). No floats in rules, so
  results never depend on multiplication order.
- Fixed modifier order: base power, move percent, (phase 4: equipment by slot index, then
  statuses), then variance (`damage_variance_percent`, default 0, seeded).
- Character HP = `base_character_hp` (100) x `hp_percent`. Power = `base_party_damage` (40) x
  `power_percent`.
- Enemy HP = `base_enemy_hp` (1500) x `hp_percent`. Enemy power = `base_enemy_hit_damage` (28) x
  `power_percent`. One hit deals power x `hit.damage_percent`.
- Kill target: 4 normal undefended hits kill a character (4 x 28 = 112), 3 heavy (130%) hits kill
  (3 x 36 = 108). Per attack: a character **survives any 2 undefended attacks and dies on the 3rd
  or 4th**. Multi-hit strings add up to about 100% to 140% in total.
- Damage for every hit of an enemy attack is **pre-rolled when the attack is declared** (in the
  prompt), so RNG use never depends on the order results arrive in.
- HP 0 = **downed**: skips turns, cannot be targeted, its remaining prompts in the current attack
  are voided. Phase 2 adds revive (a target revived mid-attack does not rejoin that attack).
- All three downed = defeat (in a run: run over). All enemies at 0 HP = victory. Victory or defeat
  can happen in the middle of an attack.

### 2.8 Phase 2 features (planned, not built yet)

Timed presses on skills, Follow-up Strikes (when an ally's skill lands, the other characters get
a timed prompt; success adds a small hit and fills a shared **team gauge**; full gauge unlocks a
**team ultimate**), marks/statuses that other classes consume, revive, several enemy types with
distinct patterns. These all reuse the timed-sequence machinery (4.3): a skill is a sequence with
a press prompt for the actor and follow-up prompts for allies, declared up front with a
`requires` link to the skill-landing prompt, so no network round trip is needed mid-sequence.
Class kits approved by the user on 2026-10-12 (section 2.10).

**Enemy intent (user feedback after phase 1, approved 2026-10-12):** the player must be told what
the enemy is about to do with enough time to read it (the phase 1 banner appeared only
`attack_lead_in_ms`, 700 ms, before the attack).

- Each enemy picks its next attack and target(s) when its turn ends (and at fight start), with
  the seeded RNG. The pick is part of engine state and is announced in an `intent` event.
- A sign under the enemy shows it all the time: attack name, target ("WHOLE PARTY" for party-wide)
  and one icon per hit (sword = normal: parry or dodge; wave = ground: jump), spaced by the hits'
  timing so the attack's rhythm shows (3.8; the `intent` event carries each hit's `times`). The
  same icon sits
  on the enemy's turn in the timeline row.
- **Always honest:** every enemy shows the full truth (user pick). Difficulty comes from how an
  attack moves (feints, delays, rhythm), never from hidden information.
- If a living target goes down, or Taunt redirects a single-target attack, the target is
  re-picked and a new `intent` event is sent. The attack itself never changes.

### 2.9 Phase 1 enemy: Rotten Husk

Speed 200 (party 90 to 110), so it acts about twice per round. 1500 HP, power 28.
Times are ms after the attack starts, at tempo 100%.

| Attack | Targets | Weight | Hits | Notes |
|---|---|---|---|---|
| Swipe | one | 3 | normal 900 (100%) | wind-up glow, 200 ms lunge |
| Flurry | one | 3 | normal 900 / 1200 / 1500 (45% each) | 300 ms rhythm |
| Lingering Claw | one | 2 | normal 1600 (130%) | feint: false start, hold, real lunge; no training ring |
| Ground Slam | party | 1 | ground 1100 (80%) | shockwave front parallel to the party, reaches all at once |
| Rot Combo | party | 1 | normal 900, normal 1200, ground 1700, normal 2300 (35% each) | 500+ ms either side of the ground hit (jump airtime) |

Data rules (checked by a test): impact times increase; normal hits at least 250 ms apart; at
least 450 ms between a ground hit and its neighbours; mid-string parry hit-stop at least 30 ms
under the parry window's early part.

### 2.10 Phase 2 class kits (approved 2026-10-12)

All names and numbers are placeholders stored in ability data. Percentages are of the user's
power unless stated. AP is per character.

**Shared rules**

- **Timed press (three results, user feedback 2026-10-12):** every skill has one or more press
  prompts for its user (`skill_press` button). Each press is:
  - **PERFECT** (inside `skill_perfect_window_ms`, 70 ms): extra damage (`press_damage_percent`)
    and, if every press of the skill was perfect, the skill's other bonus ("Perfect press: ...");
  - **GOOD** (inside `skill_press_window_ms`, 200 ms, around the perfect window): normal damage;
  - **MISS** (pressed too early or too late, or not at all): the hit still lands for
    `skill_miss_damage_percent` (50%) of normal damage. A press before the good window shows EARLY
    and starts the whiff lockout, so mashing never pays.
  Multi-hit skills have one press per hit, and each press only affects its own hit. Non-damage
  effects (heal, AP, statuses...) always apply at their base value; only all-perfect adds the
  bonus.
- **Follow-up Strike:** when a skill lands with at least one good or perfect press, each other
  living ally gets one press prompt (declared up front with a `requires` link to the landing
  prompt). A good press adds a small hit (`follow_up_percent`, 30%), a perfect one a bigger hit
  (`follow_up_perfect_percent`, 45%); both fill the shared **team gauge**
  (`team_gauge_per_follow_up`; gauge size `team_gauge_max`). A missed follow-up does nothing.
- **Team Ultimate:** when the gauge is full, any character can use it on their turn (empties the
  gauge). All three living characters strike together for big damage, and every downed ally is
  revived at `team_ultimate_revive_percent` (25) of max HP.
- **Exposed** (enemy mark, does not stack): the next damaging skill used on that enemy removes it
  for +50% damage (Rend: +150% instead).
- **Revive:** Cass's Revive skill and the Team Ultimate. Revive timing follows 2.1.

**Alder: Warden (tank / counter).** Slow, tough, punishes the enemy for attacking.

| Skill | AP | Effect | Good press |
|---|---|---|---|
| Taunt | 1 | the enemy's next single-target attack must target Alder | +1 AP |
| Guard | 1 | one ally takes 50% damage until their next turn | Alder is guarded too |
| Shield Bash | 2 | 140% hit, enemy's next turn is pushed later | pushed further |
| Riposte Stance | 2 | until Alder's next turn, his counters deal x2 | +1 AP |
| Payback | 3 | 100% hit, +50% per perfect defence Alder made since his last turn | +50% |

**Brin: Reaver (damage).** Fast and strong; consumes Exposed.

| Skill | AP | Effect | Good press |
|---|---|---|---|
| Feint Step | 0 | 80% hit, +1 AP | +2 AP instead |
| Quick Cuts | 1 | 3 hits of 50% | +25% on that hit |
| Hamstring | 2 | 100% hit, enemy speed down for 2 of its turns | lasts 3 turns |
| Rend | 3 | 220% hit; consumes Exposed for +150% | +30% |
| All In | 5 | 5 hits of 70% | +30% on that hit |

**Cass: Mender (support).** Heals, applies Exposed, feeds AP.

| Skill | AP | Effect | Good press |
|---|---|---|---|
| Mend | 1 | heal one ally 30% of their max HP | 45% |
| Reveal | 1 | 60% hit, enemy becomes Exposed | +1 AP |
| Pass the Torch | 2 | give one ally 2 AP | 3 AP |
| Hasten | 2 | one ally's next turn comes sooner | sooner still |
| Revive | 3 | revive a downed ally at 25% HP | 50% HP |

Intended combo: Cass Reveals, Brin Rends; Alder Taunts, parries, then cashes in with Payback.

### 2.11 Phase 2 enemies (approved 2026-10-12)

Each enemy tests one defence skill. Starting numbers; tune in data. Times in ms at tempo 100%.
All attacks follow the data rules in 2.9.

| Enemy | Speed | HP | Power | Tests |
|---|---|---|---|---|
| Rotten Husk (2.9) | 200 | 100% | 100% | a bit of everything |
| Bloat | 80 | 180% | 140% | patience (long wind-ups) and jumping |
| Gnat Swarm | 160 | 50% | 50% | rhythm: long strings of light hits |
| Shade | 130 | 90% | 100% | reading: feints, delays, mixed ground and normal |

| Enemy | Attack | Targets | Weight | Hits |
|---|---|---|---|---|
| Bloat | Belly Slam | one | 3 | normal 1600 (130%), slow 400 ms lunge |
| Bloat | Rot Wave | party | 2 | ground 1200 (80%) |
| Bloat | Double Wave | party | 2 | ground 1100, ground 1800 (55% each) |
| Bloat | Crush | one | 1 | normal 1400, ground 2000 (70% each) |
| Gnat Swarm | Sting String | one | 3 | normal 800 to 1920 every 280 (5 x 30%) |
| Gnat Swarm | Buzz | one | 2 | normal 800 to 2050 every 250 (6 x 25%) |
| Gnat Swarm | Swarm Sweep | party | 1 | normal 900, 1200, 1500 (40% each) |
| Shade | Delayed Rake | one | 3 | normal 1700 (120%), feint |
| Shade | Cross Step | one | 2 | normal 900, ground 1450, normal 2000 (45% each) |
| Shade | Stutter | one | 2 | normal 800, 1600 (feint), 1900 (40% each) |
| Shade | Nightfall | party | 1 | ground 1000, normal 1600 feint (60% each) |

Some encounters have two enemies (for example two Gnat Swarms), so targeting, Exposed and
Hamstring matter. Phase 2 test build: a fight-select screen lists the test encounters.

---

## 3. Defence timing

### 3.1 The clock

- One clock for everything: `Time.get_ticks_usec()` (monotonic microseconds).
- Godot 4.7 input events carry no OS timestamp (verified with `ClassDB` on 4.7.2). So
  `DefenseInput._input()` stamps each press the instant Godot delivers it. `_input` runs before
  any `_process`, so the stamp does not depend on when game logic looks at input. Accuracy is
  bounded by how often the OS events are pumped (once per frame on Windows): at 60 fps the error
  is at most about 16 ms. Windows are 150 ms or more.
- Each press is stamped as an **interval**: from the previous input pump (recorded by
  `DefenseInput` on the `SceneTree.process_frame` signal) to the moment it arrived. A press counts
  if any part of that interval is inside a window (reaching back at most `press_reach_back_max_ms`,
  100). This removes the half-frame bias and turns a frame hitch into leniency instead of an unfair
  miss. The timing readout uses the midpoint. Prompts that expire inside such a capped press still
  get their hit-taken feedback on the next frame.
- Presses are forwarded to the judge straight from `_input`, before the per-frame `advance()`, so a
  late-delivered press is never expired first.
- The judge never asks "was the button pressed this frame". It compares the stamp with each
  prompt's scheduled impact time.
- Warm-up at fight start: preload every sound, texture and effect material (draw each effect once)
  so the first parry does not cause a shader-compile hitch.
- Display settings for low lag (`project.godot`): Mailbox vsync (no tearing, unthrottled loop, so
  input is pumped more often), `max_fps` 480. The F1 overlay shows fps, vsync mode, audio latency
  and the longest frame of the current attack.
- Future option if needed: a GDExtension that reads raw input on a thread with OS timestamps.
  The judge would not change.

### 3.2 Lag compensation and calibration

- The impact a player sees reaches the screen 1 to 3 frames after it is scheduled, plus pad lag,
  so honest presses arrive about 30 to 70 ms "late". `input_latency_compensation_ms` (tuning,
  default 30) is subtracted from every press time (and from the clock used to expire prompts).
- **Calibration (F2 while the action menu is open):** a flash plus tick every 750 ms; press Parry
  on each. The median offset of the last 8 presses becomes the player's compensation, saved per
  machine in `user://settings.cfg` (it overrides the tuning default). The saved and used value is
  kept within `calibration_min_ms` .. `calibration_max_ms` (tuning, -50 .. 150), and the panel
  refuses to save when the middle half of the presses spreads wider than
  `calibration_max_spread_ms` (60): that means pressing by reaction to the flash, not with the
  beat. The F1 overlay also shows the rolling median offset of real parries and of all presses.

### 3.3 Attack clock and hit-stop

- When an attack starts, `AttackClock` records the real start time. Impact times are in attack
  time (ms after start). Hit-stop pauses the attack clock: real time keeps going, attack time
  stops, so every later hit shifts by exactly the pause. Enemy animation and every cue are
  computed from attack time each frame, so what you see always matches what is judged.
- One `AttackClock` per machine, shared by all local judges. Hit-stop is only triggered by this
  machine's own judges (a remote ally's parry shows a popup but does not pause your clock).
- Hit-stop lengths (tuning): parry mid-string 45 ms, parry on the final hit 110 ms, jump 40 ms,
  hit taken 50 ms (only on an attack's last hit: a missed hit is judged about 118 ms after impact,
  when in a string the next lunge has often started, and freezing that looks like a stutter),
  dodge 0, counter 120 ms.
- **Presses during a success freeze (parry, jump) are ignored** (no judgement, no lockout). The
  hurt freeze on an attack's last hit is the exception: every prompt is already resolved, so such
  a press can only be a LATE report, judged at the time it would have had without the freeze.
- Press stamps are converted from real time to attack time before judging.

### 3.4 Windows

For a prompt with impact at time T and a window of W ms:
`[T - W x (100 - late%) / 100, T + W x late% / 100]`, with `window_late_percent` default 35
(most of the window is before impact; a press opens the defence, as in Sekiro).

Default windows: parry 150 ms (-97.5 / +52.5), dodge 250 ms (-162.5 / +87.5),
jump 220 ms (-143 / +77). The engine computes these per prompt (`Defense.build_windows`) and puts
them in the declared event; judges only read the event.

### 3.5 Judging a press (`DefenseJudge`, pure, unit-tested)

One judge per local player, holding the prompts of the characters that player answers for
(phase 1: one player, one judge with every prompt).

1. `advance(now)` every frame: prompts whose windows have all closed resolve as NONE.
2. Press while locked out: ignored and the lockout restarts.
3. For each character the player controls: the press resolves that character's earliest
   unresolved prompt whose window for that button contains the press time.
4. No match: whiff with a reason: EARLY, LATE, or WRONG_ACTION (wrong button for the nearest
   hit); lockout starts. A hit that already landed less than `late_press_report_ms` before the
   press counts as "nearest" when it is nearer than the next unresolved hit and no later hit was
   defended (a LATE whiff on it). An isolated LATE whiff locks only until the next hit's first
   window opens. Voided prompts (character down) never match and are never blamed.
5. Results are released strictly in prompt order and sent to the engine as `resolve_prompts`.
   A later prompt that resolved first waits in the buffer (prevents a deadlock when, for example,
   a jump for a ground hit lands before an earlier normal hit expires).

### 3.6 Presentation of defence

- **Decide early, show at contact:** a valid early press decides the outcome at once, but its
  clang, flash, sparks and the start of hit-stop play at attack time `max(press, impact)`.
- Defence poses hold from the press until at least impact + late edge: parry stance 150 ms or
  more, dodge 250 ms or more, jump airtime about 480 ms with the apex at impact when the press
  leaves time for it, else a fast rise (`jump_rise_fast_ms`, 60). A jump's contact moment (thump,
  readout, hit-stop) is at `max(impact, the moment the body is 60% up)`, so the freeze never shows
  a successful jump standing in the wave.
- A hit that lands: contact shows at T; damage and flinch apply when the window closes, at the
  late edge plus lag compensation (about 118 ms after impact by default). On an attack's last hit
  the enemy holds its contact pose until `contact_after_close_ms` (70) past that, so the flinch and
  hurt freeze show it still in contact; between hits the hold is capped so the recoil keeps
  `recoil_min_ms`, so in tight strings the flinch can overlap the next lunge's start. A ground
  wave stays fully visible until its hit closes, then fades over `wave_fade_ms` (150).
- One readout per press, above the defenders' standing heads (a jump's lift is ignored), even
  when it answered several characters. Popups that share a column stack: the newest at its spot,
  older ones pushed above it, so a column reads oldest at the top and nothing overlaps; a popup
  pushed up against the attack banner or timeline stops there and fades out quickly instead of
  being hidden under it. "MISS"
  shows only when no press was made for that hit (an EARLY or wrong-button whiff on it counts).
- A whiff never cuts short a successful defence or a flinch that is still playing (a double tap
  keeps the jumper in the air); it still flashes, sounds and shows its readout.
- The lock icon sits under the defenders' feet, clear of the readouts.
- Feedback comes from the local judge at press time, never from engine events (so it stays
  instant online): "PARRY" / "DODGE" / "JUMP" plus the offset ("+12"), whiffs as "EARLY -130"
  (blue) or "LATE +70" (red), wrong button as "JUMP!" / "PARRY!" hints (orange), "MISS" when a hit
  lands with no press, a lock icon during lockout, a muted click for a locked press.
- Distinct sounds: parry clang (brighter on the final hit), dodge whoosh, jump thump, hit taken,
  whiff swish, locked click.
- Parry sparks burst on the defender's front edge (`spark_toward_enemy`). Screen shake is stronger
  on a parry than on a hit taken (parry 0.09, final parry 0.14, hurt 0.1).

### 3.7 Cues (all toggleable)

- Wind-up glow that ramps while the enemy holds, and a visible lunge of fixed length
  (`approach_ms`, about 200 ms) into an obvious contact point. Feints start a lunge, stop, hold,
  then do the real lunge.
- Telegraph flash when each lunge, feint start or slam starts (`show_telegraph_flash`, F1 then F).
  It is red-orange (`telegraph_flash_color`), never white: white on the enemy means "you parried".
- One alert sound when the attack starts.
- Motion sounds (`play_motion_sounds`, F1 then L): a whoosh as each lunge or feint starts and a
  slam as a ground wave launches. They are the sound of the motion the player is reading, so they
  start with it (about 200 ms before impact), not on a beat.
- **Training ring** (`show_timing_ring`, **off by default**, toggle with F1 then R): shrinks onto
  the target and closes at impact. Never shown on attacks with `allow_timing_ring = false`. The
  toggle is saved per machine in `user://settings.cfg` and overrides the tuning default.
- Timing readout after each press (`show_timing_feedback`, F1 then T).
- Wind-up crouch (`show_windup_crouch`, F1 then C): the enemy crouches as its wind-up glow
  builds (`windup_squash_percent` at full glow) and springs out of it as the lunge or slam starts.
- Hit markers and the floor warning (`show_hit_markers`, F1 then H), see 3.8.
- F, T, L, H and C are session toggles (not saved); the tuning values are their starting state.

### 3.8 Reading attacks (approved 2026-10-12, card #44)

Defence is the star, so every hit must be readable before and while it comes. Nothing here
gives a beat to press on: the press is still timed from the enemy's motion (the user picked
"icons only" over a rhythm-game strip with a moving line).

- **One colour per defence:** red-orange (`telegraph_flash_color`, `normal_hit_color`) = a normal
  hit, parry or dodge it; purple (`ground_hit_color`) = a ground hit, jump it; white = you parried.
  The wind-up glow and the telegraph flash before a slam, the ground hit icon, its marker, the
  floor warning and the training ring's ground colour are all purple.
- **Rhythm rows:** the intent sign and the attack banner show one icon per hit, centres
  `rhythm_px_per_ms` (0.2) apart per millisecond between impacts and never closer than the icon
  plus `rhythm_min_gap_px`; a row wider than `rhythm_max_width_px` is squeezed evenly
  (`HitRhythm.layout`, unit-tested). So Flurry reads as three even beats and Stutter as a long
  pause, then two quick hits.
- **During the attack** the banner row shows each hit's state (`HitRhythm.states`): upcoming as
  is, active (bigger, `rhythm_active_scale`) from the moment its motion starts until impact, done
  (faded, `rhythm_done_alpha`) after impact. A feint's hit is active from its false start, so the
  marker never gives the feint away. At most one hit is active at a time.
- **Hit marker:** while a hit is active, its icon on a dark disc with a border in its colour sits
  beside each living target, on the side the enemy stands (`hit_marker_offset_px`), popping in
  over `hit_marker_pop_ms`; ground hits add "JUMP" under it. It sits beside the body, not above
  the head, so it never covers the defence readouts. It only says that a hit is coming and which
  kind; the timing still comes from the motion.
- **Floor warning:** during an active ground hit a purple disc glows on the floor under each
  living target, from `WARNING_START_SHARE` (0.3) of `floor_warning_strength` at the slam to full
  when the wave arrives.
- Everything above is a pure function of attack time, so hit-stop freezes it with the enemy.

---

## 4. Architecture

```
 Input devices ──> DefenseInput (stamps presses) ──┐
                                                    v
 HUD menus ──> CombatController ──commands──> CombatEngine (pure, deterministic)
                 │   ^                               │
                 │   ├──── TimedSequenceRunner ◄─────┤ events (enemy attacks)
                 │   └──── SkillSequenceRunner ◄─────┘ events (skills, follow-ups)
                 │          (AttackClock + one DefenseJudge per local player; phase 2: one)
                 └──events──> CombatMirror ──> CombatView / HUD / Audio (presentation)
```

### 4.1 Layers

| Layer | Folder | May use |
|---|---|---|
| Data | `scripts/data/`, `data/` | `Resource` only |
| Core | `scripts/combat/core/` | data resources, `RefCounted`, `CombatRng`. No nodes, time, input, floats in rules. |
| Timing | `scripts/combat/timing/` | pure `RefCounted`; times are passed in as numbers |
| Controller | `scripts/combat/presentation/combat_controller.gd` | everything; owns the engine |
| Presentation | `scripts/combat/presentation/` | nodes, tweens, audio; reads the **mirror**, never the engine |
| Input | `scripts/combat/input/` | `_input` and the clock |
| Shared helpers | `scripts/core/` | `AssetLoader` (textures with a checkerboard fallback) |
| Autoloads | `scripts/autoload/` | `Audio` (sound cues), `UserSettings` / `PlayerSettings` (per-machine settings) |

### 4.2 Engine API (`CombatEngine`)

- `CombatEngine.new(setup: CombatSetup)`: party data, enemy data, team ultimate, tuning, seed,
  `allow_practice`.
- `start() -> Array[Dictionary]`: events for fight start and the first turn (or one
  `command_rejected` with `already_started` / `invalid_setup`).
- `submit(command) -> Array[Dictionary]`: the only way to change state. A command is fully
  validated before anything changes; an invalid one returns a single `command_rejected` event,
  which is private to the sender (never broadcast or replayed).
- Queries (controller and tests only): `phase`, `active_actor`, `turn_number`, `sequence`,
  `pending_prompts()`, `get_combatant(id)`, `preview_turn_order(n)`, `snapshot()`, `party_ids()`,
  `enemy_ids()`, `living_party_ids()`, `living_enemy_ids()`, `downed_party_ids()`,
  `get_ability(id)`, `get_attack(id)`, `can_afford(actor_id, ability_id)`, `can_use(...)`,
  `valid_targets(actor_id, ability_id)`, `team_gauge`, `intents`. Presentation never reads them
  for display (rule 7); the action menu works out the same rules from the mirror.
- `CombatEngine.restore(setup, snapshot)` rebuilds an engine (reconnects, desync debugging).

Phases: `AWAITING_ACTION` (a party member must act), `AWAITING_TIMING` (a timed sequence has
pending prompts), `ENDED`.

### 4.3 Timed sequences, commands and events

Anything resolved in real time is a **timed sequence** of **prompts**. A prompt is one
(moment, character) pair: `{idx, hit, character, at_ms, kind, windows, perfect, damage,
press_damage, role, requires}`. Kinds:

- `enemy_attack`: one `defend` prompt per hit per target (windows for dodge/parry or jump).
- `skill`: one `press` prompt per hit per striker (the user; every standing party member for the
  team ultimate), then one `follow_up` prompt per other standing ally (damaging enemy skills with
  `follow_ups`). A follow-up `requires` the press prompts: the engine voids it
  (`no_good_press`) once they are all in and none was good. Damage for a miss (`damage`) and a
  good press (`press_damage`) is pre-rolled in the prompt. The skill's other effects apply when its
  last press is in ("the skill lands").

Prompts name characters, never players; which player answers which prompt is decided by the
controller (and in phase 5 by a host `DefenseArbiter`). In single-player one press answers all of
that player's simultaneous prompts (the team ultimate: one press per hit for all three).

Commands (Dictionary, `type` key; build with `CombatCommands`):

| type | fields | when |
|---|---|---|
| `use_ability` | `turn`, `actor`, `ability`, `targets` | AWAITING_ACTION; `turn` must match |
| `resolve_prompts` | `seq`, `results: [{prompt, outcome, offset_us}]` | AWAITING_TIMING; partial OK; per character in order |
| `practice` | `invulnerable_party?`, `immortal_enemies?`, `force_attack?` | only if the setup allows practice |

Events: `combat_started`, `intent`, `turn_started`, `turn_order`, `ability_used`, `damage`,
`healed`, `revived`, `downed`, `ap_changed`, `status_changed`, `turn_shifted`, `team_gauge`,
`timed_sequence_declared`, `prompt_resolved`, `prompts_voided`, `sequence_resolved` (boundary:
all prompts done, counters follow), `counter`, `turn_ended`, `practice_changed`, `combat_ended`,
`command_rejected`. Every event that changes HP, AP or the gauge carries the value after the
change. Full field lists are at the top of `combat_engine.gd`.

Payload rules: only ints, bools, Strings and arrays/dictionaries of those (never Resources);
built fresh, never sharing containers with engine state. Persist logs with `var_to_bytes` /
`var_to_str`, never JSON (JSON turns ints into floats and int keys into strings).

### 4.4 Determinism

- `CombatRng`: our own xorshift32; state is one int kept inside 32 bits (no overflow, no
  negative shifts). A golden-value test pins its output.
- Integer HP, AP and damage; percentages as ints; pre-rolled prompt damage.
- Stable iteration order (combatant arrays, prompt arrays); never iterate an incoming Dictionary
  to decide order.
- Tests replay the same seed and commands twice and compare full event logs, and restore from a
  mid-attack snapshot and compare the event tail.

### 4.5 Event playback and the mirror

- The controller keeps an event queue and plays events one by one through the view; each
  applies to `CombatMirror` when it is played, so bars change with the animation.
- `timed_sequence_declared` starts the `TimedSequenceRunner` (enemy attacks) or the
  `SkillSequenceRunner` (skills). Each runs the sequence locally on its `AttackClock`, judges
  presses, plays local feedback, and submits `resolve_prompts`. Enemy attacks: the engine events
  that come back for prompts (`prompt_resolved`, `prompts_voided`, `downed`) are applied to the
  mirror at once (their effects were already shown locally). Skills: the events that come back for
  a press (damage, statuses, healing, AP, gauge) are applied at that press's contact moment, so
  the numbers appear with the strike. Everything from `sequence_resolved` on (counters, next turn,
  victory) waits until the local animation ends.
- Skill press rings are osu-style ("PRESS" on the user, "FOLLOW-UP" in blue on an ally): a faint
  target circle on the presser, a grey GOOD band and a gold PERFECT band around it, and a ring
  that shrinks from `press_ring_start_radius_px` and reaches the target circle at the perfect
  moment, `ring_lead_ms` after it appears. The bands are the press windows drawn at the ring's
  shrink speed, so pressing while the ring is inside a band gives that result; the ring turns gold
  inside the PERFECT band. Perfect: full sound, short hit-stop (`hitstop_press_ms`), gold "PERFECT"
  readout. Good: quieter sound, white "GOOD". No good press when the window passes: "MISS" and a
  weaker strike. Early/late presses show EARLY/LATE and start the same whiff lockout as defence.
- Test: after every fight, the mirror's projection equals the engine snapshot's projection. The
  autoplay bot checks the same on the real playback path at the end of every fight and prints
  `AUTOPLAY_ERROR mirror_mismatch` if they differ.

---

## 5. Data

### 5.1 Resource types

| Script | Folder | Holds |
|---|---|---|
| `Tuning` | `data/tuning/tuning.tres` | every global rules and judging number (windows, lockout, lag compensation and its bounds, damage, HP, AP, hit-stop, cue toggles, pacing) |
| `CombatVisuals` | `data/presentation/combat_visuals.tres` | presentation only: FX/stage/UI art paths, stage layout, camera, enemy choreography feel (feint lead, contact hold, recoil), pose lengths, jump shape, flash/shake strengths, popup and banner feel, calibration procedure |
| `CharacterData` | `data/characters/` | id, name, colour, sprite paths, hp/power %, speed, abilities |
| `AbilityData` | `data/abilities/` | id, name, targeting, AP cost, press times, follow-ups, damage % and press bonus, Payback and Exposed bonuses, landing effects (AP gain/give, heal, revive, turn delay/hasten, status) each with a press bonus, team ultimate flag, sound |
| `EnemyData` | `data/enemies/` | id, name, sprite paths, hp/power %, speed, attacks |
| `EnemyAttackData` | `data/enemy_attacks/` | id, name, target mode, weight, alert cue, ring allowed, hits |
| `AttackHitData` | inside attacks | impact ms, kind (normal/ground), damage %, approach ms, feint |
| `EncounterData` | `data/encounters/` | enemy list, party list and team ultimate (until phase 4) |
| `SfxLibrary` / `SfxCue` | `data/audio/sfx_library.tres` | sound cue name -> file path, volume, pitch jitter |

### 5.2 Tuning file

Open `data/tuning/tuning.tres` in the Godot editor (double-click it in the FileSystem panel; the
values appear in the Inspector on the right, each with a tooltip). Balance changes go in this
file, never by changing the defaults in `tuning.gd`. `tools/bootstrap_data.gd` writes it with
every value spelled out.

The split: `tuning.tres` holds what changes rules or judging (and the cue on/off defaults);
`combat_visuals.tres` holds how things look and feel on screen. The one link between them: the
calibration procedure (in `combat_visuals.tres`) produces the lag compensation the judge uses,
clamped by tuning's calibration bounds.

### 5.3 Assets and placeholders

- Sprites: `assets/sprites/<group>/<id>.png`. Sounds: `assets/audio/sfx/<cue>.wav`.
- Battle sprites are one-row sheets of equal frames (`sprite_hframes` in the data):
  characters `idle, ready, parry, dodge, jump, hurt, strike, down` (8);
  enemies `idle, windup, lunge, contact, hurt, slam` (6). Portraits are single images.
  Placeholder characters are 32x48 px per frame, the enemy 64x64 px per frame.
- Paths are stored in the data files as plain `res://` paths (`@export_file_path`, not UIDs). To
  replace a placeholder, overwrite the file with a new one of the same name. `run_game.bat` imports
  new files before starting, so dropped-in art and sounds just work.
- Import defaults in `project.godot`: textures never VRAM-compressed and no mipmaps (even when used
  in 3D); WAV kept as PCM. Every `Sprite3D` uses nearest filtering; fighters and the backdrop use
  alpha-cut discard, effects and shadows use alpha blending (their fades need it). A test checks
  the `.import` files.
- Placeholders are generated by `tools/gen_placeholders.gd` (pixel sprites and synthesized
  sounds) at the paths named in the data files (characters, enemies, sound library and
  `combat_visuals.tres`). It only creates files that are missing, so real art is never overwritten.
- Popups and icons sit above the visible top of a fighter's art (the opaque pixels of frame 0),
  so empty space at the top of a frame does not push them up.
- All textures use nearest-neighbour filtering (pixel art stays sharp).
- `AssetLoader.texture(path)` returns a visible checkerboard if a file is missing; `Audio.play()`
  stays silent with one warning.

---

## 6. Input

Defined in `project.godot` (Project > Project Settings > Input Map in the editor). Phase 1: every
device controls the single player. Keyboard events use device id 16 in Godot 4.7, pads 0 and up,
which phase 5 uses to assign devices to players.

| Action | Keyboard | Xbox pad |
|---|---|---|
| `defend_parry` | Space | RB |
| `defend_dodge` | Left Shift | B |
| `defend_jump` | W | A |
| `skill_press` | Space, E | A, RB |
| `menu_up/down/left/right` | Arrow keys, WASD | D-pad, left stick |
| `menu_confirm` | Enter, E | A |
| `menu_cancel` | Escape, Q, Backspace | B |
| `debug_overlay` | F1 | View |

Phase 1 practice keys (keyboard only, when `practice_tools_enabled`): 1 to 5 force the enemy's
next attack, I toggles "party cannot die", O toggles "enemy cannot die", R restarts the fight,
F1 opens the stats overlay (inside it: R training ring, F telegraph flash, T timing readout,
L motion sounds), F2 starts lag calibration (only while the action menu is open, never during an
enemy attack). With `practice_tools_enabled` off, F1 and F2 are not available during a fight.
On the victory/defeat screen F1 opens the stats, and Confirm or R fights again once
`end_input_guard_ms` (800) has passed, so a late defence press never skips the screen.

On-screen control hints are built from the Input Map (`HudStyle.binding_text`), so remaps made in
Project Settings > Input Map show up in the hints.

Menus, defence and skill presses never run at the same time, so shared buttons do not clash
(`DefenseInput` arms only the defence actions during an enemy attack and only `skill_press`
during a skill). Godot's built-in
`ui_accept` no longer includes Space (so a parry can never click a menu button) and gains pad A;
`ui_cancel` gains pad B. `DefenseInput` marks the presses it consumes as handled, and menus are
driven by the `menu_*` actions. Hit-stop never uses `SceneTree.paused` or `Engine.time_scale`
(both would drop presses or freeze timers); `DefenseInput` runs with `PROCESS_MODE_ALWAYS`.

---

## 7. Presentation

### 7.1 Phase 1 (functional, placeholder)

- 3D stage; characters and enemy are pixel-art sprites drawn as billboards, nearest filtering.
- Fixed 3/4 camera with shake and punch-in on hits, parries and counters.
- HUD: timeline row (top left), attack banner (top centre), party panels with HP and AP pips
  (bottom, in the same left-to-right order as the fighters), enemy HP bar, action menu, damage
  numbers, defence result popups and timing readout, controls hint (with "Ground wave: Jump only"
  and "Parry every hit: counterattack"), practice status, victory/defeat screen with a one-line
  summary: enemy hits, successful parries, dodges and jumps (one press that answers several
  characters counts once) and counters (Confirm or R to fight again).
- F1 overlay (right column, clear of the fighters): per-action success rates, mean and spread of
  timing offsets, whiffs split into early / late / wrong button, rolling median offset of parries
  and of all timed presses, current compensation, fps, vsync, audio latency, longest frame, toggles.
- Feedback: hit-stop and white flash on parry, sparks, sounds per action, screen shake on hits.

### 7.2 Phase 2 additions

- Fight-select screen at start (every file in `data/encounters/`); Cancel on the end screen goes
  back to it. `--encounter=ID` starts one fight directly (autoplay defaults to `husk_fight`).
- Team gauge at the bottom right, beside the party panels ("TEAM GAUGE 40%"; gold "TEAM
  ULTIMATE READY" when full).
- Enemy intent: a sign just under each enemy's feet ("Flurry -> BRIN" plus one icon per hit,
  spaced by timing (3.8):
  sword = parry or dodge, wave = jump; under the feet so it never covers HP bars or popups) and
  the same icons under its next turn on the timeline.
- Status badges on party panels and under enemy HP (EXPOSED, GUARD, TAUNTED, SLOWED 2, RIPOSTE),
  with a popup when one is applied.
- Action menu: every skill with its AP cost, greyed with the reason when it cannot be used now
  (not enough AP, gauge not full, nobody down); a target step for enemies, allies or downed allies
  when there is a choice. The team ultimate is listed for everyone.
- Skills: gold skill banner, the user steps toward the enemy and lunges on each hit; support
  skills flash their target. Follow-up allies step forward when their ring appears. Popups for
  healing (green numbers), AP given, REVIVED, DELAYED / HASTE.
- End screen summary adds skill presses (perfect and good). Skill presses are not counted in the F1 defence
  statistics (those are for defence timing).

### 7.3 Phase 3 (HD-2D)

Billboard sprites in lit 3D environments, full-resolution rendering, depth of field, bloom, fog,
strong lighting, cinematic combat camera. Explorable zone with roaming enemies and fight
transition.

---

## 8. Run structure (phase 4)

Slay-the-Spire style branching node map (host picks path). Node types: zone (small explorable
area with visible roaming enemies and a forced fight at the end), rest, shop, boss (final).
Touching a roaming enemy starts a fight; striking it first gives an opening advantage.
In zones the host moves the party and others follow (v1). In-run progression: levels and
equipment with passive effects (like E33 Pictos). Loot goes to a shared pool; each item can be
equipped by one character. No progression between runs in v1.

---

## 9. Multiplayer (phase 5)

- Host-authoritative. Godot high-level multiplayer over ENet. Join by IP or room code.
- The host runs the only `CombatEngine`. Clients have no engine: they apply broadcast events to
  their own `CombatMirror` and play them. Clients send commands for their own characters; the
  host validates and applies them.
- Defence: each client plays the attack locally from `timed_sequence_declared` and judges its own
  player's prompts with its own `DefenseJudge` on its own clock (network lag never shifts
  windows). It sends partial `resolve_prompts` for its characters. A host-only `DefenseArbiter`
  tracks each client's playback start (`defense_started{seq}` ack), sets per-prompt deadlines
  (ack time + impact + late edge + hit-stops + grace), resolves missed prompts as NONE (or AI)
  with an explicit command so the replay log has it, drops results for characters the sender
  does not own and for stale sequences, and dedupes by (seq, prompt).
- Combat RPCs are `@rpc("any_peer", "call_remote", "reliable")` on a dedicated channel.
- The handshake compares a hash of data files and tuning; mismatched clients are refused.
- Local co-op: several input devices on one machine, each assigned to a player; one shared
  `AttackClock`.

---

## 10. Testing

- GUT 9.7.1, tests in `tests/unit/`. Run `run_tests.bat` (headless). It imports first, and fails
  if any test file did not load (`tests/post_run.gd` compares loaded vs present test files) or the
  log contains a script error. Plain GUT would skip a broken test file and still report success.
- Tests that change tuning work on `load(path).duplicate(true)` so the cached resource never leaks
  into other tests.
- Covered: RNG golden values, timeline order, damage and kill thresholds, AP economy, defence
  rules per hit kind, counters and team counters, partial and out-of-order results, voided prompts,
  win/lose mid-attack, invalid commands (atomic rejection), practice commands, determinism,
  snapshot/restore, mirror equals engine, defence judge windows, lockout restart, early/late/wrong
  reasons, release order (the normal@0 + ground@150 + jump@30 case), latency compensation,
  attack clock pauses, data file validation (2.9 rules).
- Smoke test: `--autoplay` bot plays a full fight headless (`=perfect`, `=miss`, `=mash`), aiming
  at window centres. At the end the game prints `AUTOPLAY_RESULT victory|defeat` and an
  `AUTOPLAY_STATS` line, then quits (with `--quit-on-end`). Problems print `AUTOPLAY_ERROR ...`
  (a rejected command, or the mirror not matching the engine). Run it with `--quit-after 60000` as
  a hard cap and a `timeout`, and fail if the result line is missing (a hang) or the log has an
  ERROR or AUTOPLAY_ERROR line.
- Also covered: attack clock with timestamps past 2^31 us (36 minutes of uptime), late presses
  reported as LATE on a landed hit, prompts expired inside a capped press, enemy choreography
  (every lunge reaches contact exactly at impact, contact holds until the hit closes, cue times),
  defence statistics and the calibration clamp. Data validation tests check meaning (ids unique, times increasing, spacing rules,
  paths exist, weights > 0), not just loading.
- Phase 2 (`test_skills.gd` and additions elsewhere): press prompts and press damage, follow-ups
  (declared per ally, voided after missed presses, gauge), the team ultimate (gauge check, all
  strike, revive), revive and heal and AP gifts, Exposed / Guard / Taunt / Slow / Riposte /
  Payback, turn delay and hasten, intents (announced at start, the attack matches the intent,
  re-targeting when a target falls), duplicate enemy names, the press rules for every shipped
  ability, every encounter starts. Autoplay picks skills and allies' targets and presses skill
  and follow-up prompts at window centre.

---

## 11. Phase plan

1. **Setup + one fight** (done): 3 placeholder characters vs 1 enemy, timeline, basic attack,
   dodge/parry/jump, counter, AP, win/lose. One player controls all three. Goal: parry feels good.
2. **Classes and co-op combat** (current): classes, skills with timed presses, Follow-up Strikes,
   team gauge and ultimate, marks/combos, downed/revive, enemy intent, several enemy types with
   distinct attack patterns, fight select.
3. HD-2D look: one explorable zone, roaming enemies, fight transition, combat camera,
   post-processing.
4. Run structure: node map, zones, rest/shop, loot, equipment, levels, boss.
5. Co-op: local multi-device first, then online.
6. Polish: UI, feedback effects, audio pass, balance.

### 11.1 To-do (from playtests)

Open items the user raised after playing; pick them up at the start of the next phase.

1. **Press ring speed and style per move** (after phase 2, 2026-10-12). Each ability (and each
   enemy attack's training ring) sets its own ring speed and look in its data file: the basic
   attack at normal speed, skills at their own speed (for example faster for big skills).
2. **Multi-press skills as separate rings** (after phase 2). Quick Cuts, All In and the team
   ultimate now show overlapping rings on the same character. Show each press as its own ring,
   entirely separate (one at a time, or at its own spot like osu notes), so a string of presses
   reads clearly.
3. **Make enemy attacks easier to see** (after phase 2). **Built in phase 3 (3.8).** Defence is the star, so the player must
   be able to read each hit as it comes: clearer wind-ups, a marker for each incoming hit and its
   kind, and a way to see the rhythm of a string before and during it. To be proposed to the user
   before building.

---

## 12. Decision log

| Date | Decision | Why |
|---|---|---|
| 2026-10-06 | Godot 4.7.2 stable, GUT 9.7.1 | latest stable; GUT branch made for 4.7 |
| 2026-10-06 | Public GitHub repo `JawadAlSaeed/Rotten-Lands`; no AI attribution in git | user request |
| 2026-10-06 | Button prompts use Xbox names | user tests with an Xbox-style pad |
| 2026-10-06 | Press stamped in `_input` with `Time.get_ticks_usec()` | 4.7 events have no timestamp |
| 2026-10-06 | Windows 35% after impact, 65% before | a press opens the defence (Sekiro-style) |
| 2026-10-06 | Lockout 300 ms, restarted by presses during lockout | simulation: mashing 0%, honest miss costs one hit |
| 2026-10-06 | Jump counts as perfect for counters, 0 AP by default | brief: parry grants AP; jump is the only answer to ground hits |
| 2026-10-06 | Global numbers in `tuning.tres`; per-move shapes as percentages in move data | one place to rebalance, content stays data-driven |
| 2026-10-06 | Integer percentages, integer damage maths | identical results everywhere, order-independent |
| 2026-10-06 | Commands/events are plain Dictionaries | trivially serialisable for networking |
| 2026-10-06 | Timed sequences of per-character prompts; partial `resolve_prompts` | covers phase 2 skills/follow-ups and phase 5 per-client reporting without redesign |
| 2026-10-06 | Engine computes windows and pre-rolls damage in the declared event | client judge and host rules cannot drift; RNG order independent of network |
| 2026-10-06 | Presentation reads `CombatMirror`, not the engine | bars sync with animation; same code on network clients |
| 2026-10-06 | Attack animation and cues computed from `AttackClock` | visuals and judging never drift; hit-stop exact |
| 2026-10-06 | Training ring off by default; one alert per attack, not a per-hit beat | players learn to read the enemy; feints stay honest |
| 2026-10-06 | Default lag compensation 30 ms + F2 calibration saved in `user://` | display/pad lag makes honest presses late; it is per machine |
| 2026-10-06 | Split hit-stop (45 mid-string / 110 final / 50 hurt) and ignore presses during freeze | long mid-string freezes break rhythm parries |
| 2026-10-06 | Phase 1 team counter is one combined strike (120% each, summed) | one player triggers it every time; keep it at about 10% of enemy HP |
| 2026-10-06 | Enemy speed 200, HP 1500, party-wide attacks rarer | more parries per fight, fight length about 9 to 15 enemy attacks |
| 2026-10-06 | Practice keys (force attack, invulnerable, immortal, restart, stats) | lets the user judge the parry quickly |
| 2026-10-06 | Press stamped as an interval since the previous input pump | removes half-frame bias; hitches become leniency |
| 2026-10-06 | Mailbox vsync, max_fps 480 | lower input-to-screen lag, more frequent input pumps |
| 2026-10-06 | No VRAM compression or mipmaps for textures; PCM WAV | pixel art stays sharp, clicks stay crisp |
| 2026-10-06 | Asset paths stored as raw res:// paths | readable, reskinnable data; survives file replacement |
| 2026-10-06 | Space removed from ui_accept | the parry key must never confirm a menu |
| 2026-10-06 | Test runner fails on unloaded test files | GUT alone reports success when a test file has a parse error |
| 2026-10-07 | `tuning.tres` = rules and judging, `combat_visuals.tres` = look and feel | one place per question; presentation tweaks never touch balance |
| 2026-10-07 | A press soon after a hit landed reports LATE on that hit (`late_press_report_ms` 400) | reacting late is the most common beginner miss; it must say LATE, not nothing or EARLY |
| 2026-10-07 | Hurt hit-stop only on an attack's last hit | a missed hit is judged ~118 ms after impact, often after the next lunge started |
| 2026-10-07 | Enemy holds contact until the hit closes; ground wave stays until then | a missed hit's flinch and damage appear while the cause is still on screen |
| 2026-10-07 | Jump contact (sound, popup, freeze) when the body is clear of the wave | the freeze must never show a successful jump standing in the wave |
| 2026-10-07 | Lunge whoosh and slam sounds kept, toggle with F1 then L | they are the sound of the motion being read, not a beat; can be turned off to test |
| 2026-10-07 | Calibration clamped to -50 .. 150 ms and refused when presses spread > 60 ms | a reaction-based calibration would shift every window late |
| 2026-10-07 | Single-target attacks: bystanders step back and dim; targets get arrows and red panels | with a staggered formation the lunge otherwise lands in front of an ally |
| 2026-10-07 | Telegraph flash red-orange, parry flash white | one colour must mean one thing |
| 2026-10-07 | Isolated LATE whiff locks only until the next hit's window opens | in a 300 ms string a full lockout made one late press cost two or three hits |
| 2026-10-07 | Presses during the last hit's hurt freeze are judged (as LATE) | otherwise the most common late band (~+90..+140 ms) showed nothing |
| 2026-10-07 | Popups stack per column with a ceiling under the banner | readouts must never overlap or hide under the banner |
| 2026-10-07 | One movement tween per fighter (`FighterView.move_body`) | two tweens on one body made team counters snap back home |
| 2026-10-12 | Class kits: Warden / Reaver / Mender, 5 skills each (2.10) | user approved; marks and AP links force co-op play |
| 2026-10-12 | Missed skill press = weaker effect, never a failed skill | E33 style; a miss stings without wasting the turn |
| 2026-10-12 | Revive: Cass skill + Team Ultimate revives all downed at 25% | user pick; losing Cass is not a dead end |
| 2026-10-12 | Enemy intent always shown in full (name, target, every hit) | user pick; difficulty from motion, not hidden info |
| 2026-10-12 | Phase 2 enemies: Bloat (jump), Gnat Swarm (rhythm), Shade (reading) | each tests one defence skill |
| 2026-10-12 | Skill presses use a separate `skill_press` action (Space, E / pad A, RB) | menus, defence and skills never overlap, so shared buttons are safe; one "action" button feel |
| 2026-10-12 | Every ability has at least one timed press; first press at least `ring_lead_ms` in | the press ring must be readable from its first frame |
| 2026-10-12 | Follow-ups need at least one good press; non-damage press bonuses need every press good | follow-ups reward landing the skill; bonuses reward clean execution |
| 2026-10-12 | Exposed is a multiplier (x1.5, Rend x2.5) applied after the move percent | DESIGN 2.7 order: statuses come after move percent |
| 2026-10-12 | Payback counts perfect defences since the user's last turn ended | counting from the turn start would always reset it to 0 before use |
| 2026-10-12 | Taunt lasts until the enemy's next single-target attack (party-wide attacks keep it) | matches the approved text "next attack on one character" |
| 2026-10-12 | Guard is baked into the prompt damage when the attack is declared | the runner shows pre-rolled numbers at contact; Guard cannot change mid-attack |
| 2026-10-12 | Skill events are applied at the press's contact moment, not when the engine answers | numbers appear with the strike, like defence feedback |
| 2026-10-12 | Team ultimate lives on the encounter until phase 4 | content stays data; the run will own it later |
| 2026-10-12 | Two enemies with the same name get letters (Gnat Swarm A / B) | targets and intent signs must be unambiguous |
| 2026-10-12 | Shade Stutter feint moved to 1600 ms (last hit 1900) | a feint's false start must come after the previous hit's contact |
| 2026-10-12 | Skill presses are left out of the F1 defence statistics | those numbers are for defence timing and calibration |
| 2026-10-12 | Reading attacks: rhythm rows, hit markers, floor warning, wind-up crouch (3.8) | user pick "icons only": the motion stays the thing you time, the HUD only says what is coming |
| 2026-10-12 | Purple = ground hit (jump) everywhere; red-orange = normal hit | one colour must mean one thing; orange was close to the red-orange telegraph |
| 2026-10-12 | Hit markers beside the target, on the enemy's side, not above the head | readouts stack above heads; a marker there would cover them in fast strings |
| 2026-10-12 | Skill presses have three results: perfect (bonus), good (normal), miss (50%); osu-style ring with GOOD and PERFECT bands | user feedback: the ring had no visible spot to hit and no distinction between perfect and normal |
