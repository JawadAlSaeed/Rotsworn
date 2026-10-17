# Rotsworn: design document

Living document. Update it whenever a decision is made. The game is called **Rotsworn** (card #48,
2026-10-13; it was "Rotten Lands" until phase 8). Names that belong to content (characters,
enemies, moves) are stored in data files and can still change.

Story (card #90): the rot rose from the Hollow King's grave and swallowed the land: forests to
husks, rivers to bog, cities to ash. Alder, Brin and Cass are the Rotsworn, the last three who
swore to walk into the rot and cut it out at its heart. The road is never the same twice, and the
rot fights back.

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
  (90%) of each character's power, added up (about 210 with the current party, 14% of a
  1500 HP enemy; card #51 lowered it from 120% when party power went up). It has its own banner ("TEAM COUNTER!"), the attackers keep part of their formation at
  the strike point, and each lands its own slash. A solo counter shows "COUNTER!" over the enemy.
  Both freeze their slashes for the counter hit-stop.
- **Longer and mixed strings hit harder** (card #52): the counter percent gains
  `counter_per_extra_hit_percent` (25) for each perfectly defended hit after the first, and
  `counter_mixed_bonus_percent` (50) when the string mixed parries and jumps. A solo counter
  counts that character's own hits; a team counter counts the attack's hits. Gear (Riposte
  Ring) adds its points next; Riposte Stance multiplies last. The text says why:
  "COUNTER x5!", "TEAM COUNTER x4 MIXED!".
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
- Character HP = `base_character_hp` (100) x `hp_percent`. Power = `base_party_damage` (75) x
  `power_percent` (card #51: was 40, which made fights drag in a run; Alder 67, Brin 90, Cass 75).
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
    `skill_miss_damage_percent` (50%) of normal damage. A press before the good window shows EARLY,
    starts the whiff lockout and, once that ring is on screen, **uses it up as a miss** (one press
    per ring, user rule 2026-10-13): the lockout ending before the window no longer gives a second
    try. A press before the ring appears (a double tap, a press meant for another ring) does not
    spend it. The same goes
    for follow-up rings. Defence presses keep the lockout-only rule.
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
| Shield Bash | 2 | 180% hit, enemy's next turn is pushed later | pushed further |
| Riposte Stance | 2 | until Alder's next turn, his counters deal x2 | +1 AP |
| Payback | 3 | 150% hit, +50% per perfect defence Alder made since his last turn | +50% |

**Brin: Reaver (damage).** Fast and strong; consumes Exposed.

| Skill | AP | Effect | Good press |
|---|---|---|---|
| Feint Step | 0 | 80% hit, +1 AP | +2 AP instead |
| Quick Cuts | 1 | 3 hits of 50% | +25% on that hit |
| Hamstring | 2 | 150% hit, enemy speed down for 2 of its turns | lasts 3 turns |
| Rend | 3 | 300% hit; consumes Exposed for +150% | +30% |
| All In | 5 | 5 hits of 120% | +30% on that hit |

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

### 2.12 Opening advantage (phase 3, card #25)

How a fight starts depends on how it began in the zone (7.4):

- **First Strike:** the leader's field strike hit the roaming enemy (or it walked into a swing
  still in progress). Every party member acts before any enemy: no enemy's first turn comes before
  the last party member's first turn, and a tie goes to the party (lower ids). From then on
  everyone keeps their speed. A gold "FIRST STRIKE!" banner opens the fight.
- **Normal:** the roaming enemy touched the leader first. Turns come from speed as always.
- The opening is part of `CombatSetup` (`CombatSetup.Opening`) and announced in `combat_started`
  (`opening`: "normal" | "first_strike"), so it stays deterministic and network-safe. Test fights
  start normal; `--first-strike` starts one with the advantage.

---

### 2.13 Run (phase 6, card #92, user design 2026-10-13)

- On a hero's turn, **hold B** (Backspace) for `tuning.run_hold_ms` (500) to try to run; a ring
  around the B button fills while held (user feedback), and a tap does nothing, so nobody runs by
  accident.
- Running is a skill-like action (`data/abilities/run.tres`, `escape = true`, every hero has it):
  one slow press ring (`ring_lead_percent` 160) on the hero, with a wider PERFECT window
  (`perfect_window_percent` 140 of `skill_perfect_window_ms`, user: "a tiny bit bigger"). Only a
  **PERFECT** press gets out. A good press, an early press or no press only loses the turn (the
  next fighter goes). Running deals no damage.
- **Each hero runs alone** (user feedback 2026-10-13): a hero who gets out leaves the fight
  (`escaped` event; dashes off and fades; the panel reads ESCAPED). They get no more turns, cannot
  be targeted, revived or saved by Second Wind, and are not "down". The others fight on. The fight
  ends as **"escaped"** once nobody is left standing in it and at least one hero ran (a hero downed
  after the others ran is carried out); if the others win, it is a normal victory.
- Not allowed against bosses (`EncounterData.boss`, which includes the run's final fight, the
  Hollow King), guards (`mini_boss`), elite fights (`elite`: map Elite stops and zone champions;
  card #175, otherwise a player could read an elite's moves for free and leave) or where
  `EncounterData.can_run` is false: the Run row reads CAN'T RUN. The first three are a rule in
  `CombatSetup.from_encounter`, so a new one made in data cannot be left runnable by a forgotten flag.
- After an escape: in a zone, the enemy goes home and the leader stays where they are (with the
  usual return grace); in a run, the HP carries on (a downed hero stands at
  `run_downed_revive_hp`), with no gold and no XP; a practice fight shows ESCAPED with "fight
  again".
- The autoplay bot never runs, except in `--autoplay=escape` (runs on its first turn, presses
  perfectly; checks the escape ending).

### 2.14 Phase 12 moves (user request 2026-10-14, cards #114, #143, #145)

The user asked for new attacks, ranged attacks from enemies and ground attacks that make rock
waves. Three new kinds of move (rules in 3.9 to 3.11); step 1 gives them to the first monsters so
they can be tried at once. Times in ms at tempo 100%.

| Enemy | Attack | Targets | Weight | Hits |
|---|---|---|---|---|
| Rotten Husk | Rock Toss | one | 2 | thrown stone 1300 (110%), 600 ms flight |
| Rotten Husk | Stone Spikes | one | 2 | ground 1300 (100%), rocks, 650 ms travel |
| Bloat | Bile Spit | one | 2 | bile glob 1400 (120%), 650 ms flight |
| Bloat | Bile Rain | party | 1 | bile globs 1300, 2000 (55% each) |
| Bloat | Quake | party | 1 | ground 1300 (75%), rocks |
| Gnat Swarm | Swarm Round | each in turn | 2 | normal 900, 1300, 1700 (40% each), one hero per hit |
| Shade | Shadow Bolts | one | 2 | shade bolts 1000, 1450, 1800 (40% each), flights 500, 420, 320 |
| Shade | Grave Spikes | one | 1 | normal 900 (45%), ground 1700 (60%), rocks |

`tools/make_attack.py` writes these files from a short spec. In a practice fight the keys 1 to 9
force an attack (they were 1 to 5), and `--attacks=ID,ID` makes the enemy use the listed attacks
in turn (a dev tool for pictures).

### 2.15 Phase 12 monsters (step 2, card #125)

Three new monsters, each testing one thing like the phase 2 enemies (2.11). Starting numbers; tune
in data. Times in ms at tempo 100%.

| Enemy | Speed | HP | Power | Tests | Lives in |
|---|---|---|---|---|---|
| Carrion Fly | 170 | 70% | 80% | reaction: very short dives (130 to 150 ms lunges) | Rotten Hollow, Sunken Bog, Ashen Ruins |
| Rot Hyena | 180 | 85% | 90% | packs: Pack Bite strikes each hero in turn (3.11), a laughing feint | Ashen Ruins (two at once) |
| Mire Toad | 85 | 170% | 120% | jumping in rhythm: hop, hop, hop, each a ground wave | Sunken Bog (and its guard) |

| Enemy | Attack | Targets | Weight | Hits |
|---|---|---|---|---|
| Carrion Fly | Dive | one | 3 | normal 1100 (110%), 140 ms dive |
| Carrion Fly | Buzz Dive | one | 2 | normal 900, 1450, 1750 (50% each), 130 to 150 ms dives |
| Carrion Fly | Maggot Spit | one | 2 | bile glob 1200 (90%), 420 ms flight |
| Carrion Fly | Strafe | each in turn | 1 | normal 900, 1250, 1600 (45% each) |
| Rot Hyena | Pack Bite | each in turn | 3 | normal 900, 1250, 1600 (40% each) |
| Rot Hyena | Snap | one | 2 | normal 800 (80%) |
| Rot Hyena | Cackle | one | 2 | normal 1500 (110%), feint, no training ring |
| Rot Hyena | Pounce | one | 1 | normal 1300 (140%), 420 ms leap |
| Mire Toad | Hop Hop Hop | party | 3 | ground 1100, 1600, 2100 (45% each), waves |
| Mire Toad | Tongue Lash | one | 2 | normal 1150 (110%), 170 ms |
| Mire Toad | Mud Spit | one | 2 | mud glob 1300 (100%), 550 ms flight |
| Mire Toad | Belly Flop | party | 1 | ground 1500 (100%), rocks |

- Fights: `fly_fight`, `fly_pair`, `hyena_pack`, `hyena_and_fly`, `toad_fight`, `toad_and_fly`. The
  zones now hold: Rotten Hollow a Carrion Fly (was two Gnat Swarms); Sunken Bog two Carrion Flies
  (was two Gnat Swarms), a Mire Toad (was the Bloat) and the guard Mire Toad and Carrion Fly (was
  Husk and Gnat Swarm); Ashen Ruins the Rot Hyena Pack (was a Husk) and a Rot Hyena with a Carrion
  Fly (was two Gnat Swarms). The zone files are edited directly (`tools/bootstrap_run.gd` is the
  phase 4 starting point only).
- Gold and XP: fly 12 / 25, hyena 15 / 30, toad 25 / 50.
- Art (art kit `enemy_fly`, `enemy_hyena`, `enemy_toad` on the shared `kit/beast.py`): models built
  straight from a pose dict (no humanoid rig); every Tier 1 enemy clip; the fly and the toad add
  `windup_shoot` and `shoot` for their spits. The fly is a floater (wings twist rather than lift,
  so its idle top stays put). Cells: fly 72, hyena 80, toad 96.
- Voices until step 3: the fly borrows the gnats' voice, the hyena the husk's, the toad the
  bloat's.
- Balance check (average-player bot, skill 60, two seeds each): 10 wins in 12 fights.

### 2.16 Monster variants and deep fights (phase 12 step 3, card #144)

- A variant is a tougher, recoloured kin of a monster: the same body and clips (its EnemyData
  points at the base's `data/clips/<base>.tres`), a sheet and portrait recoloured by the art kit's
  `enemy_variants` module (OKLCH colour rules, `kit/variant.py`), HP x1.3, power x1.15, speed +10,
  gold and XP x1.5, every move of its base plus one of its own:

| Variant | Base | Look | Its own move |
|---|---|---|---|
| Ashen Husk | Rotten Husk | ash grey, ember core | Cinder Hail: party, two burning cinders thrown 1200, 1750 (50% each) |
| Blight Bloat | Bloat | bile yellow | Bile Flood: one, three bile globs 950, 1300, 1650 (45% each) |
| Blood Gnats | Gnat Swarm | blood red | Blood Rush: each in turn, five stings 800 to 2000 every 300 (30% each) |
| Hollow Shade | Shade | ice blue | Bolt Storm: party, shade bolts 1000, 1500 (45% each) |
| Bone Hyena | Rot Hyena | bone pale, red eyes | Frenzy: each in turn, four bites 800 to 1700 every 300 (40% each) |
| Plague Fly | Carrion Fly | plague violet | Plague Spit: party, one bile glob each 1200 (60%) |
| Elder Toad | Mire Toad | dark bog brown, red eyes | Quake Hop: party, rocks 1100, wave 1700, rocks 2300 (50% each) |

- Deep fights: `EncounterData.deep` names a fight's deep version (`deep_<id>`, the same fight made of
  variants). In a run, from map row `tuning.run_deep_row` (4, the second half of the 7 rows) on, a
  zone's roaming enemies hold their deep fights (`RunState.is_deep()`, `ZoneController.configure(...,
  deep)`): the roamer shows the variant and the fight is the deep one. Practice fights list them
  too. Every fight a zone holds has one (test). Phase 13 (card #105) adds stat scaling by depth on
  top.
- Balance check (average-player bot at level 1 with no gear): 3 wins in 5 deep fights. A run
  reaches them leveled and geared.

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
- Telegraph flash when each lunge, feint start or slam starts (`show_telegraph_flash`, F1 then G).
  It is red-orange (`telegraph_flash_color`), never white: white on the enemy means "you parried".
- One alert sound when the attack starts.
- Motion sounds (`play_motion_sounds`, F1 then L): a whoosh as each lunge or feint starts and a
  slam as a ground wave launches. They are the sound of the motion the player is reading, so they
  start with it (about 200 ms before impact), not on a beat.
- **Training ring** (`show_timing_ring`, **off by default**, toggle with F1 then R): shrinks onto
  the target and closes at impact, at the attack's own speed (`ring_lead_percent`). Never shown on attacks with `allow_timing_ring = false`. The
  toggle is saved per machine in `user://settings.cfg` and overrides the tuning default.
- Timing readout after each press (`show_timing_feedback`, F1 then T).
- Wind-up crouch (`show_windup_crouch`, F1 then C): the enemy crouches as its wind-up glow
  builds (`windup_squash_percent` at full glow) and springs out of it as the lunge or slam starts.
- Hit markers (`show_hit_markers`, off since phase 6, F1 then H in practice), see 3.8. The floor
  warning under a ground hit always shows.
- G, T, L, H and C are session toggles (not saved); the tuning values are their starting state.

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
  (faded, `rhythm_done_alpha`) after impact. A feint's hit is active from its false start. At
  most one hit is active at a time.
- **Feints are marked** (card #129, user request; this replaced "the marker never gives the feint
  away"): on the intent sign and the attack banner a feint's icon wears a dashed orange ring
  (`rhythm_feint_color`, `_ring_scale`, `_ring_px`, `_dashes`; the intent event lists `feints`).
  The player knows a false start is coming, not when the real lunge lands.
- **Hit marker:** while a hit is active, its icon on a dark disc with a border in its colour sits
  beside each living target, on the side the enemy stands (`hit_marker_offset_px`), popping in
  over `hit_marker_pop_ms`; ground hits add "JUMP" under it. It sits beside the body, not above
  the head, so it never covers the defence readouts. It only says that a hit is coming and which
  kind; the timing still comes from the motion.
- **Floor warning:** during an active ground hit a purple disc glows on the floor under each
  living target, from `WARNING_START_SHARE` (0.3) of `floor_warning_strength` at the slam to full
  when the wave arrives.
- Everything above is a pure function of attack time, so hit-stop freezes it with the enemy.
- **No circles (user request 2026-10-13):** the hit marker (the hit's icon in a circle beside the
  target) is off (`tuning.show_hit_markers` false; F1 > H in a practice fight), and the training
  ring left the Settings screen: it is a practice aid only (F1 > R in a practice fight), never in a
  run fight.
- **Harder reading (phase 6, user request 2026-10-12):** the intent sign before the enemy's turn
  and the attack banner's row show how many hits are coming and of which kind, but once the
  first hit lands (its impact time) the banner row and the hit markers are hidden for the rest of
  the string (`tuning.hide_intent_after_first_hit`, on). Thoughtful players remember the pattern.
  The enemy's own motion still shows every hit: the wind-up glow in the hit's colour, the crouch,
  the telegraph flash and the purple floor warning under a ground hit.

### 3.9 Ranged hits (phase 12, card #143)

- A normal hit with a `projectile` (`ProjectileData`, `data/projectiles/`: sprite sheet, loop
  speed, arc height, trail, colour, launch sound and spot) is thrown instead of lunged. It is still
  a normal hit for the rules: parry or dodge it when it arrives, and parrying every hit counters.
  The engine never sees the projectile (it is presentation only, like the animation prefix).
- The enemy winds up, throws at the launch moment (impact minus `approach_ms`, beat SHOOT, the
  `shoot` clip, falling back to `contact`; wind-up `windup_shoot`, falling back to `windup`) and
  waits where it stands while it flies (beat FLIGHT). It never walks in. A throw after a lunge
  leaves from the recoil spot, then the enemy walks home.
- The projectile flies on an arc from the enemy to the middle of the target's body and arrives at
  impact, with two faint copies behind it. Then: a parry knocks it back up toward the enemy, a
  dodge lets it fly on past, a hit bursts it in its colour. Party-wide: one projectile per hero.
  All of it is a pure function of attack time, so hit-stop freezes it.
- Rule (test): a projectile flies at least 300 ms, never on a feint or a ground hit.
- First projectiles (art kit `fx_attacks`, 20x20 cells, 4 frames): bile glob (green), thrown
  stone (grey, tumbling), shade bolt (violet). Launch sound: the lunge whoosh until real sounds are
  picked (step 3).

### 3.10 Ground looks: waves and rocks (phase 12, card #114)

- A ground hit's `ground_look` is WAVE (the shockwave front) or ROCKS.
- ROCKS: from the slam, rows of rock spikes burst out of the floor along a lane to each target
  (`rock_row_spacing` apart), one row after another at the hit's travel speed, so the front is
  easy to follow; the last row (`rock_final_count` bigger rocks) bursts right in front of the
  target exactly at impact and stands until the hit can no longer be jumped. Each rock rises over
  `rock_rise_ms`, stands `rock_hold_ms` and sinks over `rock_sink_ms`. A single-target rock hit
  runs one lane, a party-wide one a lane per hero. Rocks are plain stone (purple stays "jump": the
  floor warning and the wind-up glow say it). Sprite: `fx/rock_spike.png`, 4 shapes.
- WAVE is clearer: a glowing band lies on the floor along the front (`wave_band_*`), so you see
  exactly where the front is and when it touches each hero's floor warning.
- Both: when a ground hit arrives, the floor warning under its targets flashes bright for
  `floor_flash_ms`.

### 3.11 Each hero in turn (phase 12, card #145)

- `EnemyAttackData.TargetMode.EACH`: the targets are the standing heroes in party order from a
  random one on (seeded), at most one per hit; hit i strikes only target i (round again when the
  string has more hits than heroes). Normal hits only (test). In co-op each player defends their
  own beat.
- The intent sign and banner name the order: "Swarm Round -> CASS > ALDER > BRIN".
- The enemy lunges at each hit's own target, swinging over from the last one during its wind-up
  and lunge. Floor warnings and hit markers follow the hit's own target.
- Counters: every target who parried all of their hits counters; if all of them did, it is one
  team counter (like a party-wide attack).

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
| `practice` | `invulnerable_party?`, `immortal_enemies?`, `force_attack?`; tutorial staging: `fill_gauge?`, `full_ap?`, `hold_enemies?`, `hold_party?`, `hero?`, `stage_attack?`, `tempo_percent?`, `gate?`, `open_gate?`, `pass_turn?` | only if the setup allows practice |

Events: `combat_started`, `intent`, `turn_started`, `turn_order`, `ability_used`, `damage`,
`healed`, `revived`, `downed`, `ap_changed`, `status_changed`, `turn_shifted`, `team_gauge`,
`timed_sequence_declared`, `prompt_resolved`, `prompts_voided`, `sequence_resolved` (boundary:
all prompts done, counters follow), `counter`, `enemy_phase` (a boss's phase two), `turn_ended`,
`practice_changed`, `combat_ended`,
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
  moment, the skill's ring lead after it appears. The bands are the press windows drawn at the ring's
  shrink speed, so pressing while the ring is inside a band gives that result; the ring turns gold
  inside the PERFECT band. Perfect: full sound, short hit-stop (`hitstop_press_ms`), gold "PERFECT"
  readout. Good: quieter sound, white "GOOD". No good press when the window passes: "MISS" and a
  weaker strike. Early/late presses show EARLY/LATE and start the same whiff lockout as defence.
- **Ring speed and look per move (card #43):** each ability sets `ring_lead_percent` (percent of
  tuning `ring_lead_ms`, 700) and `ring_color`; each enemy attack sets `ring_lead_percent` for its
  training ring. Starting values: basic attack 100% (700 ms), most skills 85% (595 ms), big hits
  (Rend, Shield Bash, All In, Team Ultimate) 65% (455 ms, faster and harder). A faster ring has
  wider-looking bands (same windows, faster shrink). Every ability's first press comes at least its
  own ring lead after the start (data test). Colours all start white: gold stays "inside PERFECT".
- **Separate rings for multi-press skills (card #43, user pick "osu notes"):** every press moment
  is its own ring, a "note" (`PressNotes`). A skill with several presses lays them out in a row,
  left to right in press order, numbered 1, 2, 3..., centred at chest height where the strikers
  wait between hits (fixed for the whole skill, so lunges never move the rings). Note rings are
  `press_note_scale` (0.65) of the single-press size, `press_note_spacing_px` (150) apart; the
  next press is drawn on top and only it carries the "PRESS" label. With the shipped data the next
  ring never covers the current target circle (unit test). One press answers every striker at that
  moment, so the team ultimate shows one note per press moment in the middle of the party, not a
  ring on each character. Follow-ups keep their own ring on their ally at the normal speed.
- Test: after every fight, the mirror's projection equals the engine snapshot's projection. The
  autoplay bot checks the same on the real playback path at the end of every fight and prints
  `AUTOPLAY_ERROR mirror_mismatch` if they differ.

---

## 5. Data

### 5.1 Resource types

| Script | Folder | Holds |
|---|---|---|
| `Tuning` | `data/tuning/tuning.tres` | every global rules and judging number (windows, lockout, lag compensation and its bounds, damage, HP, AP, hit-stop, cue toggles, pacing) |
| `CombatVisuals` | `data/presentation/combat_visuals.tres` | presentation only: FX/UI art paths, the fight list's stage look, stage layout, camera and depth of field, cinematic shots, enemy choreography feel (feint lead, contact hold, recoil), pose lengths, jump shape, flash/shake strengths, popup and banner feel, calibration procedure |
| `ExploreVisuals` | `data/presentation/explore_visuals.tres` | presentation only for zones: follow camera, depth of field, walking bob, notice "!", strike slash, the fight transition |
| `StageLook` | `data/looks/` | how a place looks: ground and backdrop art, sun, ambient, fog, bloom, colour grading, vignette, combat arena decoration |
| `ZoneData` | `data/zones/` | id, name, look, leader, walkable bounds, start, blocks, props, lights, roaming enemies |
| `ZoneBlockData` / `ZonePropData` / `ZoneLightData` / `ZoneEnemyData` | inside zones and looks | a textured box; a lit sprite (solid radius, glow); a point light (flicker); a roaming enemy (encounter, spot, wander radius, guard flag) |
| `CharacterData` | `data/characters/` | id, name, colour, sprite paths, hp/power %, speed, abilities |
| `AbilityData` | `data/abilities/` | id, name, targeting, AP cost, press times, follow-ups, damage % and press bonus, Payback and Exposed bonuses, landing effects (AP gain/give, heal, revive, turn delay/hasten, status) each with a press bonus, team ultimate flag, sound |
| `EnemyData` | `data/enemies/` | id, name, sprite paths, hp/power %, speed, attacks, gold and xp (paid in a run), phase two (HP %, attacks, speed, banner text: bosses) |
| `GearData` | `data/gear/` | id, name, description, shop price, one effect and its amount |
| `EnemyAttackData` | `data/enemy_attacks/` | id, name, target mode (one, party, each in turn), weight, alert cue, ring allowed, hits |
| `AttackHitData` | inside attacks | impact ms, kind (normal/ground), damage %, approach ms, feint, projectile (ranged), ground look (wave/rocks) |
| `ProjectileData` | `data/projectiles/` | what a ranged hit throws (3.9): sprite sheet, loop speed, size, arc, trail, colour, launch sound and spot |
| `EncounterData` | `data/encounters/` | enemy list, party list and team ultimate (practice fights; a run uses its own party and ultimate), boss flag |
| `RunData` | `data/runs/` | a kind of run: party, team ultimate, the zones a zone stop picks from, the final fight and its look, the shop's items, the gear pool |
| `ItemData` | `data/items/` | backpack item (8.1): id, name, description, kind, rarity, price, shape, effect and amount, find weight, icon |
| `SfxLibrary` / `SfxCue` | `data/audio/sfx_library.tres` | sound cue name -> file path, volume, pitch jitter |
| `BrandingData` | `data/branding/branding.tres` | logo path, title screen feel (logo size and fade, glow, fog, prompt), main menu logo and tagline, story blurb |
| `CreditsData` | `data/branding/credits.tres` | credits text (# heading, ~ small print), roll speed, sizes |
| `TipSet` | `data/branding/tips.tres` | loading tips, how long a card holds, optional art behind them, sizes |

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
- Battle sprites (phase 9) were one-row sheets of equal frames (`sprite_hframes` in the data);
  since phase 10 they are grid sheets described by a `SpriteClips` resource (5.5), whose row 0
  holds these same key poses in this order:
  characters `idle, ready, parry, dodge, jump, hurt, strike, down` (8);
  enemies `idle, windup, lunge, contact, hurt, slam` (6). Portraits are single 48x48 images.
  Heroes are 32x48 px per frame. Enemy frames are square and sized per enemy, so every fighter
  has the same pixel density (`sprite_pixel_size` 0.045): Rotten Husk and Shade 72, Bloat 92,
  Gnat Swarm 56, the Hollow King 108 (phase 9; the frame size is read from the sheet).
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

Music (2026-10-13, cards #84, #95, #97, #98): `data/audio/music.tres` (`MusicSet`) names the songs:
`menu_path` (title theme and menus), `run_path` (map, shop, rest, loot, party, run end), `zone_path`
(zones without their own song; each `ZoneData.music_path` names its own), `fight_path`, `boss_path`
and `boss_rage_path` (the boss fight switches to it on the boss's phase change), `victory_path` and
`defeat_path` (cards #109, #126: a won or lost fight's end screen, `end_song_delay_ms` after the
jingle, and RUN CLEARED / RUN OVER; user picks 2026-10-15: "Victory Theme for RPG" by cynicmusic
and "Lament for a Warrior's Soul" by RandomMind, which the Openverse pass replaced with "Sad Piano"
by tyops; empty keeps the old songs). The run map song is
"Treasure Hunter" by TAD (card #110, user pick 2026-10-15, was "Mystical Theme"). The `Audio`
autoload loops the song on its own player (OGG imports loop, `oggvorbisstr` default in
project.godot); a place naming the song already playing lets it go on. A new song crossfades in: it fades in over `fade_in_ms` while the old one fades
out over `fade_out_ms` (two players, music.tres; user request 2026-10-13). While an enemy attack plays
the music dips by `music_duck_db` over `music_duck_ms` (combat_visuals.tres) so defence sounds stand
out. Songs are free OpenGameArt tracks picked by the user from three options per place
(`tools/sound_kit/music_candidates.json`, `music_selection.json`, `music_kit.py final`), all levelled
to -16 LUFS, credited in `assets/audio/music/CREDITS.md` (CC-BY tracks need that credit). The user
may later replace them with music composed for the game.

Zone ambience (2026-10-13, card #99): `ZoneData.ambience_path` / `ambience_volume_db` loop a quiet
background (wind, frogs, creaking wood) on its own player while exploring; fights and screens stop
it. Loops are CC0 Freesound recordings cut into seamless 60 s loops by
`tools/sound_kit/ambience_kit.py` (the end crossfades into the start), levelled to -30 LUFS.

Enemy voices (2026-10-13, card #101): `EnemyData.voice_sfx` names a voice cue (`SfxCue.voice`, Voice
bus): it plays when the enemy starts an attack, and `voice_hurt_volume_db` quieter and
`voice_hurt_pitch` higher when it is hit (combat_visuals.tres). CC0 Freesound recordings, three
options each (`candidates/voices.json`), fetched with `tools/sound_kit/freesound_fetch.py`. The Gnat
Swarm's fly buzz annoyed the user and became an insect chitter.

Phase 12 sounds (2026-10-14, `candidates/monsters.json`, picker
https://claude.ai/artifact/X6Ma1kNdzGpyBVjhUgJ59H, db collection `picks`): `voice_fly` (a short
squawk, no long buzz), `voice_hyena`, `voice_toad` (variants use their base's voice); `spit`,
`throw` and `bolt_cast` play when a projectile leaves (`ProjectileData.launch_sfx`); `splat` when a
glob hits (`ProjectileData.hit_sfx`, instead of the hit's own impact sound); `rock_rumble` with the
slam of a rock ground hit. User picks (2026-10-14): hyena laugh, monster croak, scarab clicks
(fly), monster spit, mud splat, rising whoosh (throw), dark swell (bolt), rock crumble.

Hero shouts (2026-10-13, card #102): `CharacterData.shout_sfx` (a voice cue) plays when that hero
uses a skill (not the basic attack, not Run); on the Team Ultimate every standing hero shouts.
CC0 Freesound recordings, three options each (`candidates/shouts.json`); Brin's and Cass's options
mix voice types because their voices are not decided in the design yet.

Openverse pass (2026-10-16/17): every sound, song and loop in the game was put next to three free
finds from api.openverse.org (CC0, public domain or CC BY only) on a listening page, with "NOW" (keep)
as a fourth choice. Pipeline: `tools/sound_kit/openverse_fetch.py` (search, cached; `pick` with hand
picks in `openverse_overrides.json`; `previews`; `redo` for slots marked "none fit"),
`make_picker.py --openverse`, `openverse_build.py` (reads `openverse_selection.json`, cuts and levels
effects to their `cue_rules.json` limits like `build_sfx.py`, songs like `music_kit.py`, loops like
`ambience_kit.py`, and writes the credit lines). When Openverse had nothing good, finds came from
Freesound and OpenGameArt voice packs. User picks: 24 effects (among them parry, dodge, whiff,
heavy strike, boss rage, enemy crumble, fight start, level up, enemy notice "Monster AAH!", Alder's
"HAH!", Cass's attack shout), the credits song ("Peaceful Fantasy Music" by TheoJT), the defeat song
and the Sunken Bog loop (swamp frogs); the rest stay as they were. Brin's shout stays as it was after
seven rounds of finds (the user wants a normal 25-year-old man's shout; still open). The user picked
by ear, so a few picks peak later than `max_rise_ms`; they were kept on purpose. CC BY sources are
named on the credits screen (`data/branding/credits.tres`, a test checks songs).

Volume channels (2026-10-13, card #104): Settings has Volume (overall, the Master bus), Music,
Effects and Voices, saved per machine (`PlayerSettings.CHANNELS`). The `Audio` autoload creates the
Music, Effects and Voice buses; songs play on Music, sound effects and ambience on Effects, cues
with `SfxCue.voice` on Voice.

Sound effects (2026-10-13, phase 7 card #39): every cue in `assets/audio/sfx/` is built from real
CC0 recordings (Kenney packs and Freesound, via the opus-sound-layer library), never synthesized.
`tools/sound_kit/` holds the pipeline (README there): `cue_rules.json` lists all 66 sound moments
with their limits (length, how soon the sound must peak, loudness target), `candidates/` three
options per moment, `selection.json` the user's pick, `build_sfx.py final` writes the WAVs and
`assets/audio/sfx/CREDITS.md`, `check_sfx.py` measures them. The user picked by ear on a listening
page. Loudness targets kept the old placeholders' balance; where a clicky recording cannot reach
it, the file is quieter and its `volume_db` in the library higher by the same amount.
New moments (35 proposed, 32 picked): parry streak ring (pitch climbs `parry_ring_step_semitones`
per parry in a row, up to `parry_ring_max_steps`, card #93), wrong button, guarded hit, missed
skill press, EXPOSED combo, ultimate start, follow-up ready, enemy wind-up (starts its own length
before each hit so it peaks on the impact, skipped where it would overlap the previous hit; off
with the motion sounds, card #94), enemy crumble, boss rage, status wears off, turn order shift,
fight start (normal fights), fight transition swirl, run away fails, gold and level up after a run
win (`reward_sound_delay_ms`, `level_up_sound_gap_ms`), footsteps per zone ground (`ZoneData.
footstep_sfx`, one per bob step), enemy spots you and gives up, zone arrival and zone clear, run
begins, loot reveal, run cleared and run over, player joins and leaves, connected, connection
problem, critical hit (phase 13, 8.2). Skipped by the user: low HP warning, pause opens, status sticks. Not made (need other recordings
or features): voices, zone ambience loops, backpack sounds.

---

### 5.4 Art kit (phase 9, cards #40, #85, #116 to #124)

All art is drawn by code (user pick, 2026-10-14) with the Python kit in `tools/art_kit/` (README
there: the art bible and how to build). Characters, monsters and props are small 3D models made of
simple shapes (signed distance fields), posed by a skeleton with IK and rendered straight into
pixel art: 3x3 rays per pixel, one palette colour per pixel, one light from the upper left, ambient
occlusion in creases, a 1-pixel outline in each material's dark colour and contour lines where
parts overlap. Colours come from hue-shifted ramps (`kit/palette.py`; shadows lean violet,
highlights warm). Ground textures, effects and icons are drawn in 2D with the same palette. One
module per asset group (`tools/art_kit/assets/`), deterministic, previews in
`tools/art_kit/preview/` (not in git). Poses are plain dicts, so phase 10 animations are made by
blending poses into more frames.

- Look: Octopath-like sprites in a muted, rotting world (greys, olive and moss, browns, violet
  rot); the heroes carry the strong colours (Alder blue, Brin red, Cass gold); worn gold accents;
  glows (rot green, cyan, amber, violet) only where they mean something.
- Alder carries a big shield and a backpack and no sword (user, 2026-10-14; the shield-only
  rework is card #56). Brin has twin daggers and a red headband; Cass a cyan-crystal staff, a
  wide pointed hat and a gold robe.
- Each enemy has its own body (before phase 9 all five were one recoloured placeholder):
  the Rotten Husk a bark-skinned hunched husk with hooked claws; the Bloat a huge swollen belly
  on stubby legs; the Gnat Swarm a cloud of gnats with eyes; the Shade a floating hooded wraith;
  the Hollow King a crowned undead king with a glowing hollow chest and a cleaver.
- Each place has its own backdrop (`StageLook.backdrop_path`).
- Hero portraits also show on the party screen (card #85).
- Height budget: the fight camera shows about 4.2 world units above an enemy's feet, so a
  fighter's idle should stay under about 3.7 (popups go above it). The Hollow King is drawn at
  camera scale 1.19 inside his 108 px frame (idle 3.6, sword raised 4.0); the heroes stand about
  2.0 (44 px).
- `python tools/art_kit/check.py` checks every file against the sprite contract.

### 5.5 Animation clips (phase 10, cards #58 to #71)

- **Sheets.** Every fighter sheet is a grid of 8 columns. Row 0 holds the old key poses in the
  old order (heroes `idle..down`, enemies `idle..slam`), so every `set_pose(int)` still shows the
  right key. Every other clip starts its own row. Hero cells are 48x56 (the 32x48 poses with 8
  clear pixels left, right and on top, so swings and leaps fit); enemy cells stay their squares.
  At most 4096 px a side. The art kit renders heroes through `cell_camera`, so row 0 is
  pixel-identical to the phase 9 frames.
- **Data.** `SpriteClips` (`scripts/data/sprite_clips.gd`, files `data/clips/<id>.tres`,
  generated by the art kit, never edited by hand): cell size, columns and rows, body width (sizes
  the shadow) and `clips`: clip name -> cell indices in play order (a repeated index holds longer).
  `CharacterData` / `EnemyData.sprite_clips` point at it; null, or a texture of another size, falls
  back to the one-row layout (placeholders keep working).
- **Timing is the game's, not the art's.** Clips hold only frame order. Lengths, periods and delays
  live in `combat_visuals.tres` / `explore_visuals.tres` (group "Animation"). A caller plays a clip
  as a loop (real time plus a per-fighter phase, so nobody breathes in step), a one-shot spread
  evenly over a length, or drives it by index from the attack or skill clock.
- **Sync rule.** Anything that must line up with judged timing is driven by the attack clock or
  the skill clock (hit-stop freezes it): enemy beats, hero defence and flinch during an attack,
  skill wind-ups and strikes. Real-time one-shots are only for things outside those windows (hurt
  from skills and counters, fall, get-up, death, victory, draw, rage, run-off, pickup). Both
  runners cancel lower-priority one-shots when they start, so a leftover pose never hides a driven
  frame. Defence judging, attack timing and hit-stops are unchanged (a golden test locks the enemy
  choreography).
- **Playback.** `ClipMath` (pure maths), `ClipPlayer` (base loop or cell plus prioritised
  one-shots: react < big < final), `ClipNames` (names and the fallback chain, for example
  `stagger` -> `hurt`), all in `scripts/combat/presentation/`; `FighterView` uses them.

## 6. Input

Defined in `project.godot` (Project > Project Settings > Input Map in the editor). Solo: every
device controls the single player. Co-op (9.1): each player has one device (the keyboard counts as
one device, `PlayerRoster.KEYBOARD`; pads by their Godot device id) and it controls only that
player's heroes.

| Action | Keyboard | Xbox pad |
|---|---|---|
| `fight_attack` (your turn; Confirm too) | E | A |
| `fight_skills` (your turn) | F | X |
| `fight_items` (your turn: backpack items, 8.1) | Tab | Y |
| Run (your turn: hold `menu_cancel`, 2.13) | Backspace | B |
| `fight_ultimate` (your turn) | U | RT |
| `defend_parry` | Space | RB |
| `defend_dodge` | Left Shift | B |
| `defend_jump` | W | A |
| `skill_press` | Space, E | A, RB |
| `menu_up/down/left/right` | Arrow keys, WASD | D-pad, left stick |
| `menu_confirm` | Enter, E | A |
| `menu_cancel` | Backspace, Q, Escape | B |
| `pause` | Escape | Menu |
| `party_menu` (run map, zone, shop: the backpack) | Tab | Y |
| `debug_overlay` | F1 | View |
| `move_up/down/left/right` (zone) | WASD, arrow keys | D-pad, left stick |
| `field_strike` (zone) | Space, J | X |
| `field_pickup` (zone, near a glinting spot) | E, Enter | A |
| `item_move` (backpack: pick up the item under the cursor to move it, put it down) | R | X |
| `item_turn_left` / `item_turn_right` (backpack: turn the item in hand) | Z / C | LB / RB |
| `party_attributes` (party screen shortcut: the attributes screen, 8.2; the card button is the main way) | T | LT |
| `party_skills` (party screen shortcut: the skills screen, 8.4; the card button is the main way) | K | RT |

Outside fights every screen (main menu, settings, practice list, map, shop, rest, party, loot)
uses the `menu_*` actions: up/down pick, left/right change a setting or pick on the map, Confirm
selects, Cancel goes back. **Pause** (Esc / Menu) works in fights, zones and on the run map
(7.5); Main reads it before anything else, so in a fight Esc never acts as "back" in the action
menu (Backspace, Q or B do). B no longer leaves a zone.

Phase 1 practice keys (keyboard only, when `practice_tools_enabled`): 1 to 9 force the enemy's
next attack, I toggles "party cannot die", O toggles "enemy cannot die", R restarts the fight,
F1 opens the stats overlay (inside it: R training ring, G telegraph flash (F is the Skills key), T timing readout,
L motion sounds, H hit markers, C wind-up crouch, V cinematic camera), F2 starts lag calibration (only while the action menu is open, never during an
enemy attack). With `practice_tools_enabled` off, F1 and F2 are not available during a fight.
On the victory/defeat screen F1 opens the stats, and Confirm or R fights again once
`end_input_guard_ms` (800) has passed, so a late defence press never skips the screen.

On-screen control hints are built from the Input Map (`HudStyle.binding_parts` /
`binding_text`), so remaps made in Project Settings > Input Map show up in the hints. They show
the device in use (card #45, `ButtonPrompts`, autoload `Prompts`): pad buttons (Xbox names, round
coloured A/B/X/Y chips) while a pad is plugged in and was used last or was just plugged in;
keyboard keys (key caps) once a key is pressed or the last pad is unplugged. Local co-op with the
keyboard and a pad both playing shows both ("Space / RB"). Hints are `HintBar` rows of button
chips (bottom of every menu screen, the fight and zone corners, the end screen) or `PromptLabel`
text with `{action}` tokens; both redraw when the device changes. A practice key with no pad
button still shows its key.

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

### 7.3 Phase 3: HD-2D look and cinematic camera (cards #21, #22)

- **One look per place** (`StageLook`, `data/looks/`): sky colour, ambient light, a warm sun with
  shadows (blocks cast them, sprites keep their soft blob), depth and height fog (optional
  volumetric fog), bloom (glow above a brightness threshold), filmic tone mapping, contrast and
  saturation, ambient occlusion, and a screen vignette; the ground tile and backdrop; and the
  decoration around the combat arena (blocks, props, lamps). A zone and the fights that start in
  it share its look; the fight list's fights use `combat_visuals.tres` `stage_look`.
  `StageBuilder` builds it all for both.
- **Lit sprites:** fighters and props are billboards lit by the sun, ambient light and lamps
  (`fighter_sprite.gdshader`: the lighting normal leans up, `normal_up`, so a sprite is lit like the
  ground it stands on). Flashes and glows are emission, so bloom catches them. Props can glow on
  their own (`ZonePropData.glow`: fungus, lanterns). Point lights can flicker like flames.
- **Places are data:** blocks (`ZoneBlockData`: textured boxes, cliffs and walls, world-space
  tiling), props (`ZonePropData`: lit sprites, optional solid radius and glow) and lights
  (`ZoneLightData`). Placeholder art for them is drawn by `tools/gen_placeholders.gd` by file name.
- **Depth of field** per camera (blur far and near, the miniature look): combat in
  `combat_visuals.tres`, zones in `explore_visuals.tres`.
- **Cinematic combat camera** (`CombatCamera` with pure `CameraShots`, F1 then V toggles,
  `cinematic_camera` in tuning): it glides (`shot_glide_ms`) to a shot for each moment: a party
  turn drifts toward that character; a skill or basic attack without follow-ups frames the striker
  and the target over the shoulder; a skill with follow-ups is framed from its start at the 3/4
  angle, pulled back just enough that the strikers, the target and every ally who will press fit in
  `follow_up_safe_area` (clear of the banner and the panels), so no follow-up is ever off screen and
  the camera holds still while any ring is up (card #49, a test checks every slot with a real
  camera); the team ultimate is a low shot that slowly circles; an enemy attack drifts
  toward the attacker and its targets during the banner lead-in and is **settled the moment the
  attack clock starts**, so the view holds still while you defend (defence is the star); a counter
  pushes in; victory and defeat circle the arena. Shake and punch-in play on top. Real time.

### 7.4 Phase 3: exploration (cards #23, #24)

- **Practice list** (main menu > Practice): "Explore: ..." for every zone in `data/zones/` first,
  then the test fights, the deep fights (variants, 2.16) last. `--zone=ID` starts in a zone.
  Since phase 12 (user request 2026-10-14, the list ran off the screen) it is a scrolling grid of
  picture cards, three to a row: a zone card shows the zone's backdrop, a fight card each of its
  monsters' idle frame (up to three), with its name and "Fight", "Explore: N roaming" or "Deep
  fight" under it. Arrows move, confirm starts, the mouse wheel scrolls, a click picks a card and
  a click on the picked card starts it.
- **The zone** (`ZoneData`, `ZoneController`): an HD-2D diorama seen from a high, narrow follow
  camera with strong depth of field (`explore_visuals.tres`). The leader (`ZoneData.leader`, Brin)
  walks with WASD / arrows / left stick (`move_*` actions), bobbing between the idle and ready
  frames, turning to face the way they walk. Props with a solid radius and solid blocks block
  walking, the bounds are invisible walls (`ZoneMotion`, pure and unit-tested). The zone's name
  shows on arrival; the count of enemies left sits top right.
- **Roaming enemies** (`ZoneEnemyData`: an encounter, a spot, a wander radius; drawn as the
  encounter's first enemy): they pause and wander near home. When the leader comes within
  `explore_notice_radius` an enemy stops and shows a red "!" for `explore_notice_ms` (fair
  warning), then chases at `explore_chase_speed` (slower than walking, so you can get away or turn
  and strike) until the leader is beyond `explore_give_up_radius`, then walks home
  (`RoamerBrain`, pure and unit-tested). No names over roaming enemies (card #127,
  `ExploreVisuals.show_roamer_names` off): the name shows once the fight starts.
- **Starting a fight:** the field strike (`field_strike`: Space or J, pad X) swings in front of
  the leader; an enemy within `explore_strike_reach` and `explore_strike_arc_degrees` is struck:
  FIRST STRIKE (2.12). An enemy that touches the leader (`explore_touch_radius`) starts a normal
  fight. Either way the world freezes for a moment (the hit or the touch reads), then the screen
  freezes and swirls into black (`ScreenTransition`, `swirl.gdshader`) and the fight fades in, in
  the zone's look. The zone waits outside the scene tree during the fight.
- **After the fight:** the end screen says "back to the zone" (Confirm), R fights again. After a
  victory that enemy is gone; after a defeat the leader starts over at the zone's start and every
  enemy goes home. Either way nothing can start a fight for `explore_return_grace_ms`. When every
  enemy is beaten, "ZONE CLEAR". The party starts every fight at full HP and AP until phase 4's
  run carries them over.
- Esc / B in the zone goes back to the practice list (in a run: asks "Quit this run?").

### 7.5 Phase 4: main menu and settings (card #46)

Studio intro (2026-10-12): when the game starts it plays the "Developed by DragonRot" video
(`assets/video/dragonrot_intro.ogv`, 4 s, path in `data/presentation/boot.tres`, `BootData`) on
black, then the title screen (7.7). Any key, button or click skips it (after `skip_guard_ms`). A missing
video goes straight to the menu. Autoplay never shows it. Godot plays Ogg Theora only: the MP4 was
converted with ffmpeg (`-c:v libtheora -q:v 8 -c:a libvorbis`). Phase 8 (user: it looked soft and
stretched; the exported MP4 was only 1888x998 at a low bitrate): `tools/branding/render_intro.py`
re-renders it from the original canvas animation (the user's `dragonrot-intro/source`) in a hidden
browser at exactly 1920x1080, 60 fps, with its own WAV, Theora quality 10. The video and the logos
are scaled smoothly (linear filter; the project's default is nearest, for pixel art).

- **Main menu** (first screen, `MainMenu`): New Run, Online, Practice (the tutorial card first,
  then the fight and zone list, full HP, nothing carries over), Settings, Credits, Quit. The
  cursor comes back on the last item picked. Card #150 (user, 2026-10-15): kept to six rows;
  Online opens a second list in place (Host Online, Join Online, Back; cancel goes back) and
  the tutorial moved from the menu into Practice.
- **Settings** (`SettingsScreen`): volume (left/right, 10% steps), fullscreen on/off, training
  ring on/off, lag calibration (the same beat test as F2 in a fight) and "reset lag to default",
  plus a read-only list of the controls (changing keys comes later). Saved per machine at once
  (`PlayerSettings`, `user://settings.cfg`); volume and fullscreen are applied at start-up.
  **Full menu (card #112):** four sections, LB / RB (Z / C) to change: **Graphics** (fullscreen;
  window size when windowed: maximised, 1280x720 to 2560x1440; vsync, on = the project's mode;
  frame limit: none, 30, 60, 120, 144, 240; fog, bloom, shadows, soft shadows (SSAO), depth of
  field: each only turns off what a place's look uses, `StageBuilder.apply_settings` applies a
  change at once even over a fight or zone), **Sound** (the four volumes), **Controls** (the list)
  and **Game** (screen shake 0 to 100% in 25% steps, scaling every camera shake; the training
  ring; lag calibration and its reset).
- Menu screens share `ListMenu` (`scripts/menu/`), driven by the `menu_*` actions only.
- **Pause menu** (`PauseMenu`, user request 2026-10-12): Esc / Menu in a fight, a zone or on the
  run map (B on the map too). Continue, Settings, and "Abandon run" (asks first, then the main
  menu) or in practice "Leave" (the practice list). Pause, Back or Continue resumes. Everything
  under it is stopped (process disabled: no timers, tweens, movement or input). A fight pauses
  only between events: an enemy attack or a skill runs on the real clock (AttackClock, judged
  presses) and cannot stop, so a pause asked for mid-move shows "PAUSING AFTER THIS MOVE" and
  opens when it ends (`CombatController.request_pause`, `pause_reached`).

### 7.6 Phase 6 Part A: UI polish and feedback (cards #37, #38, #45)

UI (card #37):
- Every screen outside a fight has the same look (`ListMenu.screen_column`): `MenuBackdrop` (dark
  gradient, a sickly glow from below, slow rot motes drifting up, vignette), a gold title with a
  fading gold line under it, and the button hints on a dark strip along the bottom
  (`ListMenu.screen_footer`). The run map uses the same backdrop and footer.
- Menu rows (changed in phase 8, user pick 2026-10-13): no gold bar; the chosen choice is drawn
  like the logo's letters (Cinzel at the logo's weight, 130% size, worn gold, brushed, its edges
  crumbling and flickering like static, `text_static.gdshader`, gentler than the logo) and the
  others are a little dimmer. Every row is as tall as a chosen one, so nothing moves. Numbers in
  `data/presentation/ui_fonts.tres` (group "Menu choices"). The fight's action menu keeps its own
  gold bar (`ListMenu.row_style`). Menu text and titles have no static any more
  (`select_static_percent` 0, user request 2026-10-14: some words were hard to read): plain worn
  gold letters. The logo keeps its full static (`letters_static.gdshader`, BrandingData).
- Titles and big words (user request, phase 8) use the same look (`HudStyle.make_worn_title`):
  screen titles and the line under them, place names on loading cards and in zones, PAUSED, the
  yes/no question, credits headings, the zone and fight banners (FIRST STRIKE!, ZONE CLEAR, TEAM
  COUNTER...), VICTORY / DEFEAT / ESCAPED, LAG CALIBRATION; with a thin dark edge and soft shadow so
  they read over a fight. A banner asking for GOLD gets the logo's worn gold; other colours (red
  for rage, player colours) stay. Small labels and names keep the plain title font. The static
  moves at 25% of the first setting (user: "lower the static to 25%"), here and on the logos.
- Settings: values on the right; the controls are a panel of button chips that follows the
  device in use.
- Fight HUD (user picks 2026-10-12, built after the first Part A test):
  - Action menu, Expedition 33 style (bottom left, user layout 2026-10-13), no cursor, one
    button per option: A Attack (always, gains AP), X Skills (opens the skill list above it; up/down
    choose, A use, B back), Y Items (backpack items, 8.1), B Run (hold it, 2.13;
    CAN'T RUN against bosses), RT Team Ultimate (LOCKED until the gauge is full). The target step
    is unchanged.
  - The bottom-left corner shows the DEFEND hints only during enemy attacks (and a "Skill
    press" hint during a skill); on your turn it holds the action menu.
  - Party panels: slimmer, with the hero's portrait, the name in the title font and the HP
    number on the bar; the AP gems replace the "AP N" text.
  - Turn order: a dark strip, a gold NOW tag on whose turn it is, enemies framed in red.
  - Enemy HP: a framed panel per enemy, HP number on the bar, statuses as coloured badges.
  - Team gauge: a framed bar that turns gold, reads ULTIMATE READY and glows when full.
- Fight HUD (first pass): the controls corner is a stack of button chips; the intent sign under an enemy never
  goes under the party panels or off the screen edge; the end screen's buttons are chips.
- Run fights hide the practice panel and ignore the practice keys (1-5, I, O): a run is the real
  game. F1 (stats) and F2 (calibration) still work.

Feedback (card #38), numbers in `combat_visuals.tres` (group Feedback):
- HP bars (party and enemies, `TrailBar`) keep the part a hit took lit in pale gold, then drain
  it; heals fill the bar smoothly.
- Party strikes and skill strikes throw sparks on the enemy (more on a counter).
- A full-screen flash (additive) on counters (pale gold), the team ultimate (gold), a hero going
  down (red) and an enemy's phase change (red).
- A beaten enemy flashes and crumbles away pixel by pixel from the top (shader `dissolve`, glowing
  green edge) with a burst of rot motes, instead of standing there greyed out.
- Big hits (at least `big_hit_percent` of the target's max HP) show a bigger damage number.
- While a standing hero is at or under `danger_hp_percent` HP, the screen edges pulse red.
- The team gauge glows in and out while the ultimate is ready.

Fonts (user pick "font A", 2026-10-12): a storybook serif, Cinzel (weight 700), for titles,
hero and enemy names and banners (`HudStyle.make_title` / `title_settings`), and Alegreya Sans
Medium for everything else (the default font of every control, set by `HudStyle.load_fonts()` at
start-up). Both are free Google Fonts under the SIL Open Font License (licences next to the files
in `assets/fonts/`). Paths in `data/presentation/ui_fonts.tres` (`UiFonts`); a missing file falls
back to Godot's built-in font with a warning.

Button pictures (`ButtonChip`, drawn with shapes, no art files), all in one light colour,
outline style on a dark see-through fill (user pick 2026-10-13, from a reference picture): A/B/X/Y
as a ring with the letter, Menu (three lines) and View (two windows) in a ring, the D-pad as an
outlined cross with the meant arms' arrows lit (up/down to choose, left/right to change), sticks
as a ring with an inner ring and L or R, other pad buttons as outlined pills, keyboard keys as
outlined rounded keys. The lag calibration and players screens show their buttons as pictures
too. Letters are centred on their ink
across and on a capital letter's height up and down, so every key of a size shares a baseline
(checked with `tools/chip_sheet.gd`, which draws every chip at four sizes).

Dev tools: `--shots=S` saves a picture of the window every S seconds to `user://shots/<name>/`
(`ScreenShooter`), `--screen=menu|settings|players|practice` opens that screen at once, and
`--pad-prompts` starts with pad buttons shown. Used to check the look without a person.

### 7.7 Phase 8: branding (cards #47, #48, #82, #83, #85, #86, #87, #90)

- **Name** (card #48): Rotsworn everywhere: window title and app name (`project.godot`), the
  exported `Rotsworn.exe` / `Rotsworn.zip`, the GitHub repo (`JawadAlSaeed/Rotsworn`, renamed from
  `Rotten-Lands`; GitHub redirects the old URL) and the board. Godot keeps `user://` in a folder
  named after the game, so `PlayerSettings` reads a `settings.cfg` left in the old
  `app_userdata/Rotten Lands/` folder once (calibration and volumes survive the rename).
- **Logo and icon** (card #47, user pick 2026-10-13 after several rounds: the ComfyUI cut-out had
  white edges, a flat vector was too cartoony, a painted 3D one's materials did not convince; the
  user chose a minimal look like the Clair Obscur: Expedition 33 logo, option "B, rough"): made by
  `tools/branding/minimal_branding.py`. ROTSWORN in slim capitals (Cinzel 600) in flat, worn gold
  (brushed streaks, crumbling pitted edges, hairline cracks, flakes) on nothing, over a large faint
  crest drawn flat: Alder's shield as an outline, Brin's twin daggers crossed and Cass's staff in
  front of it, one bone-white ribbon tied straight across them (the user's sketch), its tails
  flowing right; thin gaps where parts cross; the crest is cut away round the letters. No sword:
  Alder becomes shield-only (card #56). Files: `assets/branding/rotsworn_logo.png` (still; menus,
  loading cards, credits) and the title screen's layers (below). Game icon: the same crest, cleaner
  and thicker so it reads at 16 px, on a black rounded tile (`icon.png` window, `icon.ico` exe,
  `icon_1024.png` source). The painted logo (`paint_branding.py`, `metal_finish.py`,
  `ribbon_cloth.py`) is kept for reference and writes to `tools/branding/out/painted/` only.
- **Title screen** (card #82, `TitleScreen`): after the studio intro. The logo is drawn there as
  three layers of the same size (`rotsworn_logo_back/tails/front.png`: crest, ribbon tails,
  letters) so the tails sway gently in a slow wave from the knot (`ribbon_sway.gdshader`), and the
  letters' worn edges flicker like static (user request): the front layer holds clean letters
  (cracks only) and `letters_static.gdshader` eats pits and chips out of their edges and scatters
  flakes, with a pattern that jumps `letters_static_fps` times a second; `letters_static_motion`
  of it moves, the rest stays so the letters keep their shape (edge distances in
  `rotsworn_logo_front_edge.png`). Numbers in `BrandingData`; missing layers fall back to the
  still logo. The green glow and fog are kept dim (user: "too bright"). The menu background with
  drifting fog (`scripts/menu/fog.gdshader`, two layers of soft noise, thicker low down), the logo
  fading in and growing slightly, a soft green glow behind it that breathes, and "Press any button"
  pulsing under it once the logo is in. Any key, button or click (after `skip_guard_ms`) fades to
  the main menu. The title song starts here and carries on into the menu.
- **Main menu**: the logo (smaller) replaces the text title (no tagline and no button bar since card #130); a Credits row
  before Quit. Its logo, and the credits', move like the title screen's (user request): all use `AnimatedLogo`
  (swaying ribbon, flickering letter edges; drawn small, the cuts blend over a screen pixel so the
  edges shimmer softly instead of sparkling).
- **Font** (card #83): Cinzel already matches the logo's lettering (7.6), so it stays; menu
  choices (`ListMenu` rows) now use it too, values (prices, settings) stay in Alegreya Sans.
- **Credits** (card #87, `CreditsScreen`): from the main menu. The logo, the story, then who made
  the game, every song with its licence (CC-BY needs it), the sound recordists, the fonts and
  Godot's licence notice (with FreeType, ENet and Mbed TLS), rolling up to their own song
  (`MusicSet.credits_path`: "Heroic Minority" by Alexandr Zhelanov, CC-BY 3.0). Down rolls faster,
  Up rolls back, Back closes; they start again from the bottom after the end.
- **Loading tips** (card #86): entering a zone (from the run map, the practice list, or online as
  a client) shows a card over the black: the place's name, a random tip (never the same twice in a
  row) and the logo in the corner, over the menu background (or `TipSet.background_path` art). It
  stays `hold_ms` (2.6 s) and the zone is built at its end, so the zone starts when it is seen.
  Clients and the bot do not hold it (the host already held it before telling the clients).
  While the black, the swirl or a loading card covers the screen, no input (mouse, keyboard, pad)
  reaches anything behind it (`ScreenTransition._input`, card #132).
- **Hero portraits** (card #85): waiting for painted art (the 24 px placeholders stay).
- **Story** (card #90): at the top of this file, in `BrandingData.story`, the credits and the
  README.
- Dev tools: `--screen=title` and `--screen=credits`.

---

### 7.8 Tutorial (phase 14, card #131, lessons approved 2026-10-15; rebuilt the same day)

First version (a lesson box over a free-running practice fight) was rejected by the user
2026-10-15: "feels like a fight, not a tutorial"; the box covered the enemy intent; the text did
not match the screen; no time to read before the enemy attacked. **Rebuilt (`TutorialRunner`,
`TutorialOverlay`):**

- **Every lesson is staged: explain -> try -> result.** The fight is paused
  (`CombatController.request_pause`, `pause_reached` routed to the tutorial, not the pause menu)
  and a big centred card (dimmed background) explains the move with button pictures; Enter
  resumes. After every try the fight pauses again: "Good parry!" (next lesson) or "Too early /
  too late, try again" (the same attack again).
- **Only what the lesson needs happens**, through new practice commands: `hold_enemies` (enemy
  turns pass, no attack: the attack and skill lessons), `hold_party` (hero turns pass: the defend
  and counter lessons, so the Husk attacks at once and only once per try), `tempo_percent` (the
  defend lessons' attacks slowed, e.g. 160%), `full_ap` (skills and ultimate lessons), and the
  existing `force_attack`, `fill_gauge`, invulnerable party, immortal enemy. Plus `gate` (an
  enemy's attack waits at its turn start; `open_gate` lets the step's one attack through when the
  card closes, so the attack always matches the card) and `pass_turn` (between steps). The
  step's attack is `stage_attack`: the enemy always picks it, so its intent sign always matches
  the lesson. Each try ends with its turn (after any counter). The bot (autoplay) closes cards
  by itself after 1.2 s.
- **The player is guided to the one right choice** (user, 2026-10-15): each hero step names a
  hero (practice `hero`: the other heroes' turns pass) and one `ability`: Brin's Attack,
  Alder's Taunt (a skill with no follow-ups, user: follow-ups are the next lesson), Alder's
  Shield Bash (follow-ups), Team Ultimate. The action menu locks everything else ("Not in this
  lesson.") and the allowed row, and the Skills option leading to it, glows and pulses; in the
  skills list the cursor stays on it.
- **Card text matches the screen:** the first card of a hero step shows once that hero's menu is
  open (when the hero changes, the fight runs on to their turn first), and names the hero and
  the skill.
- **While playing, only a one-line reminder** shows at the bottom centre above the hero bars,
  never over the enemy, its intent sign or the attack banner.
- Lessons (all in the one fight): 1 Attack (good press); 2a use a skill, 2b follow-up press on an
  attacking skill; 3 parry, dodge, jump (one slowed swipe / ground slam per try); 4 counter
  (Flurry, slowed); 5 Team Ultimate (gauge filled). No zone or map lesson (user, 2026-10-15:
  walking and the map explain themselves).
- Kept from v1: `TutorialData` / `TutorialStepData` (data/tutorial/tutorial.tres), `TutorialGoals`,
  the Tutorial menu row, the one-time offer on the first New Run, "Skip this lesson" / "Leave
  tutorial" in the pause menu, first strike + Husk at 50% speed, `--screen=tutorial`,
  `--tutorial-step=N`.

### 7.9 Fight HUD restyle (card #154, user 2026-10-15)

The user called this make or break: the fight screen must be engaging, look awesome and nothing
may overlap. Direction picked by the user: Expedition 33's calm layout with Persona 5's punch.
Built while the user was away, reworked with them, approved 2026-10-16.

- **One look:** every fight plate is a dark ink plate slanted like Persona 5's (StyleBoxFlat skew,
  `HudStyle.slant()`), edged in a calm worn gold, with a hard offset ink shadow. Lit things (the
  acting hero, a hero under attack, the current turn) glow in their colour instead. Big words
  (TEAM COUNTER, a co-op "is choosing", VICTORY / DEFEAT) sit on a full-width ink band with gold
  edges; VICTORY punches in.
- **Layout (1920x1080, nothing overlaps):** turn order as a turn track down the left edge (user,
  2026-10-16; it fades to 30% while an attack or a skill plays, when the camera moves in close), attack banner at the very top centre (above the enemies' throws and
  spits; moved left when it would reach the enemy panels),
  enemy panels top right, party cards bottom left with the team gauge as a fourth card, and the
  bottom-right corner shows the DEFEND buttons while an enemy attack plays and the skill press
  while a skill plays.
- **Turn track** (user: the first column "seems basic"): a dark band fading to the right, a thin
  gold track down its left side with a diamond marker per turn (gold and glowing for the current
  one, else the fighter's colour, enemies red). Each turn is a slanted portrait card and a name
  plate (black over the fighter's colour, a coloured left edge) with a slim HP bar. No hit icons
  (user: the intent belongs on the enemy panels, where "NEXT" already shows it). The current turn steps out of the column, bigger, glowing,
  with a gold NOW ribbon and a gold arm from the track; later turns fade back step by step. When a
  turn ends the column slides up one place, the new leader pops in and the old one slides off to
  the left.
- **Whose turn (user, after the first try: "I don't know if it's my turn"):** the acting hero
  steps forward onto a glowing gold ring on the floor, and the other heroes step back and out to
  their side and dim (`turn_step`, `turn_step_away`, `turn_spot_ms`, `turn_ring_*` in
  combat_visuals.tres). Everyone steps home when the choice is made.
- **Action menu beside the hero (Persona 5 and Expedition 33):** the command diamond floats next
  to the acting hero and follows them as the camera moves. Of a few spots beside the hero it takes
  the first that covers neither the hero, the enemies, nor the enemy panels. The four face buttons
  sit in a diamond around a thin gold ring with slowly turning ticks and the hero's AP in its
  middle: Y Items (top), X Skills (left), B Run (right, hold), A Attack (bottom). Each plate is Persona 5's layered print: a black slanted plate
  over one in the hero's colour. Anything that cannot be used now fades to grey (Items with no
  items).
- **The ultimate's button is on the team gauge** (user, 2026-10-16, like Expedition 33): the gauge
  card shows "RT UNLEASH" under the bar, faded while the gauge fills, gold once it is full, and
  breathing gold while a hero can use it now. RT on a hero's turn uses it (the gauge card
  flashes); it is no longer in the diamond. Keyboard keys show on
  the keyboard; a long key like Backspace gets a wide socket that grows away from the ring. No
  name tag (user: the gold light and the lit hero card already say whose turn it is). Opening it, the diamond pops in small and tilted, the buttons fly out of the centre and
  the plates slide out after them; a pressed plate flashes. Skills and Items open beside the hero
  as a list of slanted rows (6 in view, the list scrolls; the chosen row is lit in the hero's
  colour with a gold edge), the hero's AP in its header, the description and button hints under
  it. The target step shows CHOOSE A TARGET with the target's name between arrows.
- **Numbers and floating words (user: "the numbers and some words font" felt cheap):** the body
  font's default digits were old-style (uneven heights). Every number now uses lining, tabular
  digits; HP, AP and the gauge use a bold number font (`UiFonts.number_font_path`, Alegreya Sans
  Bold) with a thin dark edge and a soft drop shadow instead of the thick outline. Damage numbers
  and the floating words (PERFECT, PARRY, MISS, COUNTER) use the same bold font slanted like
  Persona 5's (`UiFonts.popup_slant`) with a heavier edge.
- **Target lock-on:** while a target is chosen, four gold corner brackets snap onto it and
  breathe, with a bouncing chevron over it (it replaced the small arrow, which the enemy panels
  could hide).
- **Enemy panels:** short (name and HP numbers on one line, a slim bar), all the same width, and
  each holds the enemy's next move: "NEXT  Sting String  >  CASS" with its hit icons. The
  floating intent signs under the enemies are gone (`intent_sign_gap_px` is unused now).
- **Attack banner:** the move's name big (worn title letters), a small line over it saying who
  uses it on whom ("GNAT SWARM  >  CASS > ALDER"), the hit icons under it; it punches in.
- **Defend corner:** a red DEFEND tag over three slanted plates, PARRY, DODGE and JUMP, each in its
  defence colour with its button, and the two rules in small print. The skill press corner is the
  same with a gold PRESS ON THE BEAT tag.
- Dev tools: `--menu-keys=ACTION,...` presses those input actions on the action menu the first time
  it opens ("|" moves on to the next turn's menu; for pictures of the skills list, the target step
  or a later hero's turn); `--key-prompts` keeps keyboard keys shown even with a pad plugged in.

## 8. Run structure (phase 4)

Slay-the-Spire style branching node map (host picks path). Node types: zone (small explorable
area with visible roaming enemies and a forced fight at the end), rest, shop, boss (final).
Touching a roaming enemy starts a fight; striking it first gives an opening advantage.
In zones the host moves the party and others follow (v1). In-run progression: levels and
equipment with passive effects (like E33 Pictos). Loot goes to a shared pool; each item can be
equipped by one character. No progression between runs in v1.

**Phase 4 decisions (user, 2026-10-12):**

- **Run length:** short, one act: about 8 stops, 30 to 40 minutes, ending with the boss.
- **Zones:** hand-made. 3 or 4 small zones like Rotten Hollow; each zone stop picks one at
  random. A zone is cleared by beating a guard at its exit (the forced fight); other roaming
  enemies are optional.
- **Defaults (proposed, not objected to):** HP carries over between fights; a downed character
  gets back up at 1 HP after a victory; the run ends when the whole party is down. Gold from
  fights, spent in shops. Rest heals. 3 gear slots per character; gear (passive effects, like E33
  Pictos) goes to one shared pool, one wearer per item. Levels give stat growth only (HP, power).
- **Build order:** Part A (main menu and settings #46, map #26, stops #27, HP carry-over, gold,
  shop and rest), stop for testing; then Part B (loot #28, gear #29, levels #30, boss #31).
- **Part A picks (user, 2026-10-12):** build two more zones now (3 in all); the shop sells care
  for the party until gear exists; quitting mid-run loses the run (no save yet).

**Part A as built:**

- **The run** (`RunData` `data/runs/rotten_road.tres` "The Rotten Road"; rules in `RunState`,
  pure and unit-tested): party Alder, Brin, Cass with the team ultimate; zones Rotten Hollow,
  Sunken Bog, Ashen Ruins; the final fight "The Last Gate" (Shade and Bloat, in the Ashen Ruins
  look) stands in for the boss until Part B. Run numbers live in `tuning.tres` ("Run" group).
- **The map** (`RunMap`, pure, seeded with `CombatRng`; `MapScreen`): `run_map_rows` (7) rows of
  2 to 3 stops, then the final fight on top, so every path is 8 stops. The first row is all
  zones, the row before the final fight is all rests; middle rows are zone / shop / rest by weight
  (phase 15 adds elites, events and a treasure row, and splits the run into acts: 8.9)
  (60 / 20 / 20), never a shop after a shop or a rest after a rest, no rest right before the rest
  row, and at least one shop on the map. Every stop leads up to 1 or 2 stops of the next row;
  paths never cross; every stop can be reached. Each zone stop picks one of the run's zones, if
  possible not the zone met last on any path leading to it (shops and rests between do not
  count). The map shows every stop, the path walked and the stop picked with left/right (how it
  looks: "The paper map" below).
- **The paper map** (card #111, user 2026-10-15; `MapScreen`, numbers in
  `data/presentation/map_visuals.tres`, art by `tools/art_kit/assets/map_art.py`): the map is a
  tall old parchment sheet held open between two rolled ends, taller than the screen and scrolled
  like Slay the Spire's map (user, after the first try left no room for the paths between close
  rows). Up/down held or the mouse wheel scroll it; left/right picks a next stop and the map glides
  to keep it in the middle. Opening it plays the paper unrolling from the middle out to the top and
  the bottom, then the ink soaks in row by row outward from the row in view, then the party's flag
  (three stripes: Alder blue, Brin red, Cass gold) drops onto the stop the party is at. At a run's
  start it opens on the boss's lair and pans down to the start first. Confirm, Back or Party
  pressed while it opens only finishes it. Coming back from the party screen (and an online
  client's redraw) shows it already open. Each stop is a small painted picture of the place, never
  a letter: a zone its own place (`ZoneData.map_icon_path`: Rotten Hollow dead trees with a
  glowing hollow, Sunken Bog a pool with reeds and a toadstool, Ashen Ruins broken columns), a
  rest a campfire, a shop a little shop with a striped awning and a coin sign, the final fight the
  boss's lair (`RunData.final_map_icon_path`: a crag with red eyes in its cave and a crown on the
  peak). Names are written beside each picture in dark ink. Paths are ink dots: the walked path in
  red, the routes open now in full ink, routes further up lighter, everything left behind faded.
  The stop picked has a red pen circle around it. A small ink cross marks the start. Everything
  on the map is pixel art at 3x (one art pixel is 3 screen pixels). `--screen=map` opens a sample
  map two stops in, `--screen=map_start` one before the first stop (for pictures).
- **Zone stop:** the zone in run mode. Its **guard** (`ZoneEnemyData.guard`, one per zone, at the
  far end, barely wanders) is marked in gold ("GUARD", no name since card #127) wherever it is on screen; beating it
  shows ZONE CLEAR and goes back to the map. Other roaming enemies are optional (more gold, more
  risk). The top right says "Beat the GUARD at the exit / Optional enemies: N"; the run's gold and
  HP strip sits top left.
- **HP carries over** between fights (`CombatSetup.party_start_hp` and `party_max_hp_percent`,
  used by the engine). After a victory a downed character gets back up at `run_downed_revive_hp`
  (1). A defeat ends the run. AP and statuses reset every fight; the team gauge carries over (8.3, card #146).
- **Gold:** each enemy's `gold` (Husk 15, Bloat 20, Shade 20, Gnat Swarm 8) is paid when its
  fight is won; the end screen shows "+N gold". A run fight's end screen has no "fight again".
- **Rest:** everyone heals `run_rest_heal_percent` (50%) of max HP, once. Since phase 15 a campfire
  with three choices (8.11).
- **Shop:** every item in `RunData.shop_items` once per visit: Salve (25 gold, heal one 50%),
  Feast (40, heal all 30%), Tonic (45, one character +15% max HP for the run, the new HP filled).
  Items for one character ask who gets it. (No revive: nobody stays down between fights.)
- **Run end:** RUN CLEARED or RUN OVER with stops reached, fights won and gold earned, then the
  main menu. The pause menu's "Abandon run" quits a run (it asks first; the run is lost).
- **New zones** (`tools/bootstrap_run.gd` writes them, with their looks, the run, the shop and the
  new encounters, only if missing): Sunken Bog (green fog, muck tiles, glowing fungus; guard Rotten
  Husk and Gnat Swarm) and Ashen Ruins (cold moonlight, ash tiles, colonnades; guard Shade and Gnat
  Swarm). Rotten Hollow's guard is the Bloat and Gnat Swarm at its north end.

**Part B picks (user, 2026-10-12):** loot is "pick 1 of 3 after each guard, shops sell 2 pieces";
the boss is one big enemy with two phases. Also asked for: the pause menu (7.5) and stronger
counters for longer and mixed strings (2.5, card #52).

**Part B as built:**

- **Levels** (#30, replaced in phase 13 by a level per hero, 8.2): the whole party shares one level (`RunState.level`, `xp`). Each enemy has `xp`
  (Husk 30, Bloat 40, Shade 40, Gnat Swarm 15, boss 0). Level 2 needs `run_xp_first_level` (60),
  each next one `run_xp_level_step` (30) more, up to `run_max_level` (10). Each level adds
  `run_level_hp_percent` (8) to max HP and `run_level_power_percent` (8) to power, and heals what
  max HP grew. The fight's end screen shows "+N gold   +M XP   LEVEL UP!  Level L"; the status
  strip shows "Lv L".
- **Gear** (#29, `GearData`, `data/gear/`): one passive per item, `run_gear_slots` (3) per
  character, one wearer per item, unworn gear in the shared bag. 13 items: Iron Charm (max HP
  +20%), Whetstone (power +15%), Quick Boots (speed +15), War Drum (+1 AP at fight start),
  Riposte Ring (counters +50%), Echo Charm (+1 AP after each counter), Leaping Heart (perfect jump
  heals 5%), Second Wind (once per fight, downed during an enemy attack: back up when it ends with
  30%), Keen Eye (perfect skill press +25%), Rot Hunter (Exposed +50%), Thick Hide (enemy hits
  -15%), Mender's Charm (heals +30%), Lucky Coin (gold +25%). Stats (max HP, power, speed) are
  folded into the fight setup by `RunState`; the rest are `Passive` keys the engine applies
  (`CombatSetup.party_passives`, `Combatant.passives`). Putting gear on never heals (no free
  heal by swapping); taking it off cuts HP to the lower max.
- **Loot** (#28): after a zone's guard, ZONE CLEAR, then "Spoils": pick 1 of `run_loot_choices`
  (3) items the party does not own (seeded per stop), then the party screen to put it on. Shops
  also sell `run_shop_gear` (2) such items at their price, after the care items.
- **Party screen** (`PartyScreen`, Tab / Y on the map, and after loot): the level and XP, each
  character's HP, power, speed and 3 slots, the bag. Left/right character, up/down slot,
  Confirm: put on / swap / take off.
- **Boss** (#31): The Hollow King (`hollow_king`, encounter flagged `boss`, its own red look
  "hollow_throne"), 650% HP, 165% power, speed 155, with a Hollow Shade at its side (retuned in
  card #177, see 8.13; it was 350% / 120% / 140 and alone). Phase one: Cleave, Crown Sweep, Grave Stomp,
  Rot Cascade (5 hits, parries and jumps). At 50% HP (`EnemyData.phase_two_hp_percent`) it enters
  phase two once: speed 210 (was 175), attacks Cleave, Rot Cascade, Kingsfall (6 hits party-wide, mixed),
  False Crown (with a feint) and Hollow Wave; the banner says "THE HOLLOW KING RAGES!" and it picks
  a new intent at once. Its name is announced when the fight starts. It replaced "The Last Gate"
  as the run's final fight.

### 8.1 Backpack and items (phase 11, plan agreed 2026-10-14)

User picks: the backpack holds things and charms (placement matters); shop potions go into the
backpack; roaming monsters sometimes drop small things; gear never goes into the backpack; in
co-op anyone can open and move things at any time. The rest are proposed defaults.

**Four kinds of things.**

| Kind | What it does | In the backpack? |
|---|---|---|
| Gear (relics) | Worn by one hero, one passive (as today, 3 slots each) | Never. New gear goes straight onto a hero |
| Consumables | Used up: in a fight (Y, Items) or on the map | Yes |
| Charms | Work just by sitting in the backpack, for the whole party | Yes |
| Keys and treasure | A key opens one chest; treasure is only worth gold | Yes |

- **Gear:** when the party gets gear (guard spoils, shop, chest), it goes on a hero at once. If
  that hero's slots are full, swap: the old piece is sold on the spot for `item_sell_percent`.
- **Consumables (first set):** Salve (heal one 50%), Feast (heal all 30%), Tonic (one hero +15%
  max HP for the run, map only), Bomb (damage to all enemies, fight only), Antidote (clears bad
  statuses from one hero and heals a little). Salve, Feast and Tonic move from "used when bought"
  to the backpack. **Tonic cap** (card #175): a hero can drink at most `tonic_max_per_hero` (2)
  Tonics in a run (`RunState.tonics_used`, kept in `to_dict`), because gold plus Restock turned
  into endless max HP. The party screen greys the choice with a line saying why, a capped hero is
  skipped by the bot, and the shop stops selling Tonics when every hero is full (`RunState.wants`).
- **Charms:** a party-wide passive while in the backpack (for example power +5%, +1 AP at fight
  start, gold +10%). Each charm belongs to a family (Stone, Bone, Herb). Some charms boost the
  charms that touch them (for example "touching Stone charms work 50% better"), so where things
  sit matters (#72).
- **Rotten items** (#73): charms (and a few gear pieces) that are very strong with a downside,
  for example power +30% but every hero loses 2% HP each turn. They cannot be sold.
- **Treasure:** rings, rot gems: no use, only gold at the shop. Space against money.

**Shapes and the grid.** The backpack is 4 wide x 5 tall (20 cells). Each item has a shape:
1x1, 1x2, 2x2, L (3 cells) or T (4 cells), and can be turned in 90 degree steps. Stronger items
are usually bigger. Shapes, effects, rarity and prices live in each item's data file
(`ItemData`, `data/items/`).

**Rarity** (#75): common (grey border), rare (blue), legendary (gold); rotten items get a sickly
green border. Deeper rows of the map give better odds (weights in `tuning.tres`).

**Where things come from.**

| Source | What | How |
|---|---|---|
| Guard | Gear | Pick 1 of 3, as today |
| Roaming monster | Small consumable, key or treasure | `item_drop_percent` chance, shown on the fight's end screen ("Found: Salve") |
| Ground | Consumables, treasure, sometimes a charm | 2 or 3 glinting spots per zone (in `ZoneData`); walk up and press Confirm (pickup animation) |
| Chest (#79) | A rare or better charm or gear | 0 or 1 per zone, locked; uses up one Key from the backpack |
| Shop | Consumables, keys, charms, gear, backpack upgrades | Buy; sell anything from the backpack (not rotten) for `item_sell_percent` (50%) |

What a spot, drop or chest holds is picked by the run seed, so online players see the same.

**Getting something new** (#76): it goes into the first free place it fits (any turn). If it does
not fit, the backpack opens with the new item "in hand": rearrange to make room, drop something
from the backpack, or leave the new item behind.

**The backpack screen** (#55): the party screen (Tab / Y, no new button). Left: the selected
hero's info and gear (left/right switches hero, as today). Right: the grid. Move the cursor,
Confirm picks up or puts down, a rotate button turns the held item, Cancel puts it back. On a
consumable, Confirm also offers "Use" (on the map) and "Drop". A small panel shows the item's
name, rarity and effect, and which charms it touches.

**In a fight** (#91): the Items button (Y) lists the backpack's usable consumables. Using one is
the hero's action and costs the AP in its data (usually 1). It is a `use_item` command to the
engine, so it is deterministic and works online. The fight gets the list of items at the start;
what was used is taken out of the backpack when the fight ends.

**Combine** (#78): put an item onto the same item of the same rarity: they become one item of
the next rarity (common to rare to legendary). Consumables and charms only.

**Bigger backpack** (#77): a "Bigger Pack" (shop or chest) adds one row, up to
`backpack_max_rows` (7).

**Sounds** (#103): pick up, put down, turn, cannot fit, drop, combine, chest opens, key used.

**Co-op:** one shared backpack. Anyone can open and move things at any time. Online, the host
keeps the real backpack: a client sends "move this", the host applies it and sends the result to
everyone; if two players grab the same item, the first one wins.

**Numbers** go in `tuning.tres` (a new "Backpack" group): `backpack_width` (4), `backpack_rows`
(5), `backpack_max_rows` (7), `item_drop_percent`, `item_sell_percent` (50), the rarity weights per
map row, ground spots and chests per zone.

**Build order** (stop and test after each step):

1. The backpack: grid, shapes, turning, the party screen, "does not fit", sounds (#57, #55, #76,
   #103). Salve, Feast and Tonic move into the backpack; ground spots and monster drops.
2. Items in use: rarity, items in fights, chests and keys, treasure and selling (#75, #91, #79).
3. Depth: charms and neighbour bonuses, rotten items, combine, bigger backpack (#72, #73, #78,
   #77).

The run bot learns it too: it keeps whatever fits, uses a Salve when a hero is low, opens chests
when it has a key, and sells treasure at shops.

**Step 1 as built (2026-10-14, cards #57, #55, #76, #103):**

- **Data:** `ItemData` (`scripts/data/item_data.gd`, `data/items/`): id, name, description, kind
  (consumable, charm, key, treasure), rarity, price, shape (grid cells, unturned), effect and
  amount, find weight, usable on the map, icon path. Salve (1x1, heal one 50%, 25 gold, weight
  10), Feast (2x1, heal all 30%, 40, weight 4), Tonic (1x2, +15% max HP for the run, 45, weight 2).
  `RunData.shop_items` and `found_items` list them; `ZoneData.item_spots` holds 3 glinting spots
  per zone. `tools/bootstrap_items.gd` writes them and checks every spot against walls and props.
  `ShopItemData` and `data/shop/` are gone.
- **Rules** (`Backpack`, `scripts/run/backpack.gd`, pure, tested): the grid, shapes turned
  clockwise in 90 degree steps, fits / first free place (any turn) / move / remove, a stable uid
  per placed item, plain-data round trip. `RunState` owns it (`backpack`), adds `add_item`,
  `place_item`, `move_item`, `drop_item`, `use_item` (on the map), `spot_item` and `drop_for`
  (seeded), and `apply_op` (move, drop, use, swap_gear as plain data: online clients send these).
  Gear: `wear` (a full slot sells the old piece for `item_sell_percent`), `swap_gear` (between
  slots and heroes), `sell_new_gear`; the old gear bag, `take`, `equip` and `unequip` are gone.
- **Backpack screen** (`PartyScreen`, drawn by `BackpackGrid`): left every hero's card (portrait,
  stats, 3 gear slots side by side) and an info box; right the backpack art (`ui/backpack_<rows>.png`,
  a canvas pack with a bedroll, drawn at 4x; its grid numbers in `combat_visuals.tres` "Backpack")
  with the grid on its lining (cells 92 px, icons 16 px per cell, borders in the rarity colour).
  Arrows move between slots and cells (up/down between heroes on the left). Confirm on gear picks it up; on another
  slot it swaps. Confirm on an item: Use (on whom), Move, Throw away (asks first), Cancel. In hand,
  R / X turns it; it shows green where it fits and red where not. Cancel puts it back.
- **Something new in hand:** loot after a guard opens the party screen holding the gear ("Who
  wears it?"); Cancel sells it. A shop item goes in where it fits first; with no room the backpack
  opens with it in hand and leaving it refunds the gold. Shop gear opens the backpack with it in
  hand. A new item can be put over exactly one other item: they swap, and the other is in hand.
  Leaving an item asks first.
- **Zones:** glinting spots (`fx/glint.png`, a pulsing glowing sparkle, look numbers in
  `explore_visuals.tres`) in run zones. Within `explore_pickup_radius` (1.3) a "Pick up" hint
  shows; `field_pickup` (E / Enter, A) picks it up: "Found: Salve", the pickup pose. No room: the
  backpack opens over the zone with it in hand (left behind, the spot stays). Tab / Y opens the
  backpack over a zone any time; the zone holds still (online, only the host's zone stops).
- **Drops:** a beaten roaming enemy that is not the guard drops a found item `item_drop_percent`
  (35%) of the time, seeded by run, stop and enemy; the fight's end screen says "Found: Salve".
  No room: the backpack opens with it in hand after the fade back to the zone.
- **Online:** clients can open the party screen from the map (Tab / Y) and use the one the host
  opened; their changes go to the host as "bag" messages with an op; the host applies them in
  order (a stale one is refused) and the run update redraws every open party screen. New things
  in hand (loot, finds, shop) only happen on the host.
- **Sounds** (#103, picked by the user 2026-10-14 from three real recordings each,
  `tools/sound_kit/candidates/backpack.json`): `item_lift` belt and buckle, `item_place` soft
  thump, `item_turn` paper slide, `item_no_room` dull knock, `item_drop` tossed pouch,
  `item_found` coins and cloth, `item_combine` pop and shimmer, `chest_open` latch and creak.
- **Bot:** shops buy everything affordable (gear goes on whoever has room); new gear and finds
  are settled the simple way (`PartyScreen.auto_settle`); on the map it uses heals on whoever is
  at or under 60% and tonics at once; in zones it first walks to each glinting spot (giving one
  up after 25 s) and then to the guard. The run's result line adds `items=N`.
- `--screen=party` opens a sample backpack with a Golden Idol in hand (for pictures).

**Step 1 feedback (user, 2026-10-14):** show every hero at once instead of switching (done: one
card per hero, the hero switch buttons are gone); make the backpack look like a backpack (done:
the drawn pack); items whose shape makes sense (done: the Feast is a 2x1 loaf; odd shapes like L
and T only for things shaped that way).

**Step 2 as built (2026-10-14, cards #75, #91, #79):**

- **Rarity** (#75): `ItemData.rarity` and now `GearData.rarity` (rare: War Drum, Riposte Ring,
  Echo Charm, Keen Eye, Rot Hunter, Leaping Heart; legendary: Second Wind). Names and borders in
  grey, blue or gold (backpack, party cards, shop, loot). Every seeded pick (finds, drops, chest
  prizes, loot and shop gear) weighs each thing by `RunState.rarity_weight`: common 100%, rare
  `item_rare_percent` (50) + `item_rare_row_percent` (15) per map row, legendary 10 + 10 per row.
- **New items:** Bomb (1x1, fight only: every enemy takes 120% of base party damage, 30 gold),
  Smelling Salts (1x1 rare, fight only: a downed hero back at 40%, 60), Key (2x1, 30), treasure:
  Silver Ring (1x1, 40), Rot Gem (1x1 rare, 120), Golden Idol (1x2 legendary, 300). Shops sell
  Salve, Feast, Tonic, Bomb, Smelling Salts and Key; zones can turn up all of them. The Antidote
  waits until heroes can be poisoned (new monsters, phase 12).
- **Items in fights** (#91): Y (Items) opens a list of the backpack's fight items above the main
  options, like Skills (name, AP cost, greyed with the reason). Salve and Feast work in fights too.
  `CombatSetup.items` ({uid, item}) come from the backpack; the engine command `use_item` {turn,
  actor, uid, targets} spends `ap_cost` (1), applies the effect at once (heal, revive, damage with
  cause "item"), emits `item_used` and ends the turn; a used uid is gone (`items_left`, in the
  snapshot and the mirror's projection). The menu uses stand-in abilities named "item:<uid>". After
  the fight `RunState.spend_items` takes the used ones out of the backpack. The fight bot revives
  with salts, heals at 40% HP or less and bombs two or more enemies.
- **Chests and keys** (#79): one chest per zone (`ZoneData.chests`, `env/chest_closed.png` and
  `chest_open.png`). Near it the hint says "Open chest"; `field_pickup` with a Key in the backpack
  uses the key and opens it (online the others see it open). Its prize (`RunState.chest_contents`,
  seeded): `chest_gear_percent` (50%) rare or better gear the party does not wear (the backpack
  opens with it in hand: who wears it), else a rare or better item. No key: "Locked. You need a
  key."
- **Selling:** in a shop, "Sell from the backpack" (or Tab / Y) opens the backpack; an item's menu
  then has "Sell for N gold" (`item_sell_percent`, 50%). Op "sell" {uid}.
- The zone bot also tries each zone's chest once (with or without a key).

**Step 3 as built (2026-10-14, cards #72, #73, #78, #77):**

- **Charms** (#72): `ItemData` kind CHARM with a family (Stone, Bone, Herb), a charm effect and
  amount (a `GearData.Effect`, so the same stats and passives gear gives) that every hero gets
  while it is in the backpack (`RunState.bonus`, `charm_totals`; gold charms count once for the
  party). Booster charms (`boost_family`, `boost_percent`) have no bonus of their own: charms of
  their family whose cells touch theirs side by side (`Backpack.touching`, not corners) work
  `boost_percent` better. Stones: Ember Stone (power +5%), Iron Stone (enemy hits -5%), Lodestone
  (2x2, boosts stones 50%). Bones: Lucky Knucklebone (gold +10%), Wolf Tooth (speed +5), Bone
  Totem (1x3, boosts bones 50%). Herbs: Heartleaf (max HP +5%), Wake Root (L, +1 AP at fight
  start), Rain Pouch (boosts herbs 50%). The backpack screen shows gold beads where a booster
  touches a charm it boosts, and the charms' total under the backpack's title.
- **Rotten items** (#73): `rotten` and `rot_percent`: every hero loses that percent of max HP at
  the start of each of their turns in a fight (passive `rot`, damage cause "rot", never below 1
  HP). Sickly green border; they cannot be sold. Rotting Heart (power +25%, rot 3%), Grave Moss
  (2x1, a herb: +2 AP at fight start, rot 2%).
- **Combine** (#78): put an item (in hand) onto the same item at the same level: the one under it
  goes up a level ("Salve+", "Salve++"; a "+" on its corner), the one in hand is gone. Each level
  is one rarity step up (not past legendary) and makes its effect, its charm bonus, its boost and
  its price `combine_bonus_percent` (60%) stronger. Consumables and charms only. Op "combine" {uid,
  into}; a backpack entry has a `level` (saved and sent online as a sixth number).
- **Bigger backpack** (#77): Bigger Pack (kind UPGRADE, effect ADD_ROW, 100 gold): used the moment
  the party gets it (shop, chest, find): one more row, up to `backpack_max_rows` (7). The art has
  a version for 5, 6 and 7 rows. Shops stop selling it at the max.
- **Shops** also sell `run_shop_charms` (2) charms per stop (seeded, by rarity, never rotten).

**Step 3 feedback (user, 2026-10-14), done:** X (R) picks an item straight up to move it and puts
it down again, no menu; LB / RB (Z / C) turn the item in hand; "Use" on an item for one hero moves
the cursor onto the hero cards to pick who (no extra "Use on ..." lines).
Keys were too rare once Step 3 added 21 kinds of finds (a whole zone could have none): the
user picked keeping them random but twice as common (Key find weight 4 to 8).

### 8.2 Levels, attributes and critical hits (phase 13 step 1, cards #134, #135, #137, #138)

Replaces the shared party level of phase 4 (#30). Numbers live in `tuning.tres` (groups "Run" and
"Attributes and critical hits"); the rules are in `RunState` and `Attributes` (pure, tested in
`test_leveling.gd`).

- **A level per hero** (user pick). Each hero has their own level (`RunState.levels`) and XP
  (`xps`). A won fight pays the encounter's XP to every hero standing at the end and
  `run_xp_downed_percent` (50) of it to a downed one. Level 2 needs `run_xp_first_level` (60),
  each next one `run_xp_level_step` (30) more, up to `run_max_level` (10). Each level still adds
  `run_level_hp_percent` (4) to max HP and `run_level_power_percent` (4) to power (was 8 each:
  the attribute points now carry the rest) and heals what max HP grew.
- **Attributes** (like Expedition 33). Each level up gives `attr_points_per_level` (3) points
  (`attr_start_points` at the start, 0). Five attributes, each raising one stat per point:

  | Attribute | Raises | Per point |
  |---|---|---|
  | Vitality | Health (max HP) | +`attr_vitality_hp_percent` (3) % |
  | Might | Attack Power | +`attr_might_power_percent` (3) % |
  | Agility | Speed | +`attr_agility_speed` (2) |
  | Defense | enemy hits deal less | `attr_defense_percent` (2) % (the `tough` passive, with gear) |
  | Luck | Critical Rate | +`attr_luck_crit_percent` (2) % (the `crit` passive) |

  Defense and gear together never cut a hit by more than `tough_max_percent` (60). Points can be
  taken back at any time and a reset is free; the HP a hero is missing stays the same through any
  change, so respending never heals. A change that would leave a hero under 1 HP (they are so
  wounded that the max HP they give back is more than the HP they have) is refused instead of
  clamped (card #175): a clamp forgot some of the missing HP, and respending then handed it back as
  a free heal, always available because downed heroes stand at 1 HP. The screen says "too wounded
  to give up that max HP. Heal first." (`RunState.attributes_wound_blocked`). Online, a change is a RunState op (`attributes`), like the
  backpack: anyone may change any hero.
- **Critical hits.** Every hero has `crit_base_percent` (5) plus Luck. A crit deals
  `crit_damage_percent` (150) of the hit. Rolled through `CombatRng` when the damage is rolled (a
  skill or follow-up press when the sequence is declared, so it is in the declared event; a missed
  press never crits), for skill presses, follow-ups, instant abilities and counters (each hero's
  share of a team counter on its own). Enemies never crit. The `damage` event says `crit`; the
  fight shows CRITICAL! over a gold, big number (`crit_popup_size`) with the `critical` sound
  (three options built, option A in place until the user picks).
- **Level-up moment.** After a won fight, LEVEL UP! pops over each hero who levels
  (`level_up_popup_size`) with the level-up sound; the end screen lists each hero's XP and new
  level and says there are points to spend.
- **Where to spend.** The status strip shows each hero's level and a gold "+N" while they have
  points. Each hero card on the party screen (user request 2026-10-15) ends in two buttons after
  the gear slots, **Attributes +N** and **Skills +N** (gold while points wait); the cursor moves
  onto them like a gear slot and Confirm opens that screen for that hero (T / LT and K / RT stay as
  hidden shortcuts). The info box under the cards only shows while it has something to say (an
  item menu, choosing who to use an item on, something in hand, or a backpack item under the
  cursor). The **attributes screen** (`AttributesScreen`) shows the
  hero, level, XP and points to spend at the top; one row per attribute with its points, the stat
  it raises, that stat now and what one point gives. Up / down picks, right (or Confirm) adds a
  point, left takes one back, X / R resets (asks first), LB / RB (Z / C) changes hero, B / Tab / Y
  / T closes.
- The bot spends every point at once, evenly (the attribute with the fewest points first).
- `--screen=attributes` opens it on a sample run (for pictures).

### 8.3 Enemies grow with depth, the gauge carries over (cards #105, #146)

- **Depth** (#105, phase 13 step 3, built early): every enemy in a run fight gets
  `run_enemy_hp_row_percent` (5) more HP and `run_enemy_power_row_percent` (3) more power per map
  row of the stop (row 0 as in its data; `CombatSetup.enemy_hp_percent` / `enemy_power_percent`,
  set by `RunState.fight_setup`). On top of the deep variants (2.16). Bosses keep their own
  numbers unless `run_enemy_scale_bosses` is on. Practice fights never grow.
- **Team gauge** (#146): what is left of the team gauge when a run fight ends (won or escaped)
  starts the next fight (`RunState.team_gauge`, `run_team_gauge_carry_percent` (100) of it; 0 =
  the old rule). The fight shows it filling at the start. A new run starts empty. This replaces
  "the team gauge resets every fight" for the gauge only (AP and statuses still reset).

### 8.4 Skill trees (cards #136, #56, #80, #81, built 2026-10-15)

User picks: 5 skills brought, 1 skill point per level, the trees of the proposal
(`docs/proposals/skill_trees.html`), Cass casting every skill from afar except her normal attack.

- `CharacterData.skill_tree` (`SkillTreeData`: `branches`, each a `SkillBranchData` with a name and
  its skills top down). The top of each branch is known from the start of a run; the skill at
  place N costs `skill_tier_costs[N]` (0, 1, 2) skill points and needs the one above it. Each level
  up gives `skill_points_per_level` (1). A hero brings at most `skill_slots` (5) known skills into a
  fight (the basic attack always comes); a new skill is brought at once while there is room.
- `RunState.unlocked` / `loadout` per hero, ops `unlock` and `loadout` (online: anyone, like the
  backpack), `CombatSetup.party_skills` gives the engine only what was brought; fights outside a
  run give every skill. The action menu lists the fighter's own `ability_ids`.
- **Skills screen** (`SkillsScreen`, the Skills button on a hero card, or K / RT; only for a hero with a
  tree): the branches side by side, each skill Bringing (gold), Known, Learn: N pts (green) or
  Locked. Confirm learns, brings or leaves behind; LB / RB changes hero.
- The bot learns the cheapest skill it can until it cannot, and brings new ones while there is room.
- `--screen=skills` shows it with sample trees made of today's skills, laid out as in the proposal.

**The trees** (`data/skill_trees/<hero>.tres`; the top row is known at the start of a run, the
middle row costs 1 point, the bottom row 2):

| Hero | Branch | Start | 1 point | 2 points |
|---|---|---|---|---|
| Alder | Bulwark | Guard | Shield Wall (3 AP: whole party guarded; perfect +1 AP) | Unbreakable (4 AP: every enemy taunted, Alder guarded; perfect: riposte too) |
| Alder | Bash | Shield Bash | Shield Throw (1 AP: 2 hits of 60%) | Earthshaker (4 AP: 140% to every enemy, their turns later) |
| Alder | Retort | Taunt | Riposte Stance | Payback |
| Brin | Flurry | Quick Cuts (now 4 x 40%) | Twin Fangs (2 AP: 2 x 90%; both perfect: Exposed) | All In (now 6 x 100%) |
| Brin | Cripple | Hamstring | Open Vein (2 AP: 100% and Bleeding 3 turns) | Rend |
| Brin | Shadow | Feint Step | Shadowstep (1 AP: next turn much sooner, Empowered) | Death Mark (3 AP: Marked for 3 skills) |
| Cass | Mending | Mend | Renew (2 AP: Renew 3 turns) | Sanctuary (4 AP: heals the party 30%, perfect 40%) |
| Cass | Light | Reveal (now a bolt) | Smite (2 AP: 160% bolt, +100% on Exposed) | Revive |
| Cass | Grace | Pass the Torch | Hasten | Inspire (3 AP: everyone +1 AP, gauge +25) |

- **New statuses** (`Status`, numbers in tuning "Skill statuses"): Bleeding (an enemy loses
  `bleed_power_percent` (25) of the source's power at the start of each of its turns; damage cause
  `bleed`; an enemy that bleeds out loses its turn), Renew / `regen` (a hero heals `regen_percent`
  (12) of max HP at the start of each of their turns), Marked (the next N damaging skills on that one
  enemy deal `marked_bonus_percent` (40) more; each skill that lands uses one), Empowered (the hero's
  next damaging skill on enemies deals `empowered_bonus_percent` (30) more, then it is gone).
- **New ability fields:** target `ALL_ALLIES` (every standing hero, no target step; heals, AP gifts,
  hastes and statuses reach every party target), `status_needs_perfect`, `self_status` /
  `press_self_status`, `gauge_gain`, and (presentation) `projectile` / `projectile_flight_ms`.
- **Brin** (#80): the normal attack is now two cuts, one per dagger (`brin_attack`: 2 presses of 50%,
  +15% each perfect); Quick Cuts, Twin Fangs and All In alternate the daggers.
- **Cass** (#81, user note): Reveal and Smite are spells (`projectile = light_bolt`, drawn by
  `tools/art_kit/assets/fx_attacks.py`): she stays where she stands, the ring sits on her, and a
  bolt flies to the target for each press, arriving on the hit; her heals and buffs never moved. Her
  normal attack still walks up and strikes.
- **Alder** (#56): his sprite was already shield-only (phase 12); his skills are shield blows.
- **Art** (checked 2026-10-15): the phase 10 sheets already fit the reworks. Brin's clips are the
  near-dagger thrust (`strike`), the far-dagger backhand (`strike_alt`) and the two-dagger rip
  (`strike_big`); Twin Fangs ends on the rip. Cass's sheet has the staff with the glowing crystal;
  her spells play the staff thrust (crystal flaring) where she stands, her support skills the cast
  (a ring and motes rising from the crystal).

### 8.5 Long zones (phase 15 step 1, cards #155, #164; user picks 2026-10-16)

The user's problem: in a zone you could walk straight to the guard and leave. Picks: zones run
left to right like a side-scroller (guard at the far right), 3 to 5 times longer, built from
shuffled sections, with side paths, hidden spots, shrines, champions and wanderers. Depth (toward
and away from the camera) stays as it was. The phase is 15 (the board label `phase-14` was renamed:
phase 14 was the tutorial).

- **Sections** (`ZoneSectionData`, `data/zones/sections/<zone>_<name>.tres`): a hand-made slice of a
  zone, `width` long, in its own frame (x from 0 to width, z the zone's depth). It holds blocks,
  props, lights, roaming enemy spots, glinting spots, chests, seal spots, shrine and wanderer spots,
  and champions. Every section keeps the **lane** (z between `-LANE` and `+LANE`, 3 units) free at
  both ends so any two sections join.
- **A zone** (`ZoneData`) now names its `start_section`, its `middle_sections` pool, how many of them
  a visit uses (`middle_count`, 3) and its `end_section` (the gate and the guard). `ZoneAssembler`
  (pure, tested) picks and shuffles the middles with a seed and lays the sections end to end into
  one flat `ZoneData` (the old fields: blocks, props, enemies, spots...), adding the back and side
  walls. A zone without sections (old style) is used as it is.
- **The seed**: in a run `RunState.zone_seed(stop)` (the same on every machine online), in practice a
  new one each time. So a zone changes every visit: which middles, their order, which seal spot,
  which roaming spots are filled (`ZoneEnemyData.chance_percent`) and with which fight (an empty
  `encounter` takes one from the zone's `roamer_pool`), which shrine stands where.
- **Seals and the gate** (the answer to "I can just walk to the guard"): each middle section holds
  one **rot seal** (a glowing standing stone; one of its `seal_spots`, picked by the seed), often
  down a side path or past enemies. The end section's **gate** (a wall of rotten roots across the
  whole depth) stays shut until the party has `zone_seals_needed` (2) of the 3 seals (tuning; 0 =
  no gate). Picking one up: walk to it, Confirm. The top right says "Seals 1 / 2: open the gate",
  then "Beat the GUARD at the exit". Seals belong to this zone visit only (also in practice).
- **Shrines** (`ZoneOfferData`, kind SHRINE, `data/offers/`): stand at a section's `shrine_spots`;
  each visit picks them from the zone's `shrines` pool. Walk up, Confirm ("Pray") asks a yes/no
  question with the price and the gift. Each works once. First set:
  Healing Spring (free: everyone heals 30%), Blood Altar (everyone loses 20% of max HP, never below
  1: a rare or better find), War Idol (free: team gauge +50), Shrine of Plenty (40 gold: every
  hero +40 XP).
- **Wanderers** (`ZoneOfferData`, kind WANDERER): `wanderer_percent` (60) of visits put one at one of
  the sections' `wanderer_spots`, picked from the zone's `wanderers` pool. Same yes/no deal
  ("Talk"): Key Peddler (30 gold: a Key), Grave Robber (45 gold: a rare or better find), Old
  Pilgrim (free: everyone heals 15% and +20 XP).
- **Champions** (`ZoneEnemyData.champion`): an elite fight (8.6) that stands still beside a
  **prize chest** (`prize_spot`, no key needed). It never chases; touch
  or strike it to fight. Beat it and the chest opens: a rare or better prize like a locked chest
  (`RunState.prize_contents`). Optional, like every enemy but the guard.
- **Side paths**: walls in a section split it into lanes; the back lanes end in nooks with a seal,
  a glinting spot or a chest.
- **Camera**: the same follow camera; the zone is about 130 units long (was about 30), so it scrolls
  sideways as the party walks right. The floor is sized to the zone.
- **Online**: the host's zone is the real one; its snapshot also carries the seals taken, the
  offers used and the prize chests opened. Only the host answers a shrine or a wanderer.
- **The bot** walks with `ZonePath` (A* on a grid over the zone, pure, tested), picks up the
  seals, uses free shrines and deals it can pay for, opens chests, then goes to the guard. Tests
  assemble every zone with many seeds and check that every spot, seal, shrine and the guard can be
  reached from the start (gate open).

### 8.6 Mini-boss guards and elite fights (phase 15 step 2, cards #156, #157)

- **Guards are mini-bosses** (`EncounterData.mini_boss`): each zone's guard is a named kin of its
  monster, recoloured by the art kit (`enemy_variants.py`), with a **phase two** at half HP (its
  variant's moves, faster, a banner): Rotten Hollow **The Gorged One** (crimson bloat, with a gnat
  swarm), Sunken Bog **Mire Mother** (teal toad, with a carrion fly), Ashen Ruins **Ash Warden**
  (charcoal shade, with a gnat swarm). Their name is announced like a boss's and the boss song
  plays; they cannot be run from; they still grow with depth. Deep zones bring their helpers as
  variants (`deep_guard_*`). `tools/bootstrap_phase15.gd` writes them.
- **Better reward**: spoils (after a guard, an elite or an act's boss) are gear of at least
  `run_spoils_min_rarity` (rare) while the run has enough of it.
- **Elite fights** (`EncounterData.elite`): enemies get `elite_hp_percent` (140), `elite_power_percent`
  (115) and `elite_gold_percent` (150) on top of depth. Four: Twin Husks, The Laughing Pack (two
  hyenas and a fly), Toad Court, Shade Coven, each with a deep version. They are met two ways:
  an **Elite stop** on the map (a fight in one of the act's zones' look, then spoils), and the
  zones' **champions** (8.5), now elite fights marked "ELITE" in their own colour (they no longer
  force the deep version). Elite fights cannot be run from (2.13).

### 8.7 Event stops "?" (card #158)

- `EventData` (`data/events/`): a title, a short story, a picture and 1 or 2 choices
  (`EventChoiceData`), always plus Leave. A choice has a deal (`ZoneOfferData`: gold, HP, heal, XP,
  team gauge, an item, a find) and may have a risk: `risk_percent` of the time its `risk_deal`
  strikes too (seeded by the run and stop, the same on every machine; a risk that costs gold takes
  what there is). Choices the party cannot pay are greyed.
- An act's "?" stops pick from its `events`, never one met before in the run
  (`RunState.events_seen`, synced online). Eight to start: The Weeping Well, Gambler's Bones, A
  Wounded Pilgrim, Rot Blossom, The Hanging Cage, Shrine of Old Kings, Merchant's Wreck, The
  Whispering Mask.
- `EventScreen`: the story, the choices, then what happened and Continue. Items go into the
  backpack (it opens when full); online the host chooses and the clients see the result.

### 8.8 Treasure stops (card #159)

- Every stop of map row `run_treasure_row` (3) is a treasure chest. `TreasureScreen`: open it for
  `run_treasure_gold` (30) and a prize like a locked chest's but picked as if 4 rows deeper
  (`RunState.treasure_contents`): gear goes on a hero, an item into the backpack.

### 8.9 Two acts (card #163) and the map (card #162)

- `RunData.acts` (`ActData`, `data/runs/acts/`): each act has its zones, elite fights, events, a
  boss with its lair look and map picture, and `deep` (every zone fight is its variant version).
  **Act 1, The Rotten Road**: Rotten Hollow and Sunken Bog, boss **The Husk Lord** (an iron-black
  husk kin with a rotten husk at its side, phase two at half HP). **Act 2, The Ashen Deep**: Ashen
  Ruins, Sunken Bog and Rotten Hollow, all deep, boss The Hollow King. A run without acts is one act
  made of its own fields.
- Each act has its own map (`run_map_rows` 6 rows, then the boss; act 1 from the run's seed, later
  acts from a seed of their own). Beating an act's boss gives spoils, everyone heals
  `run_act_heal_percent` (50%), and the next act's map opens (its title says "Act 2: ..."). Only the
  last boss ends the run. Depth (enemy growth, rarity) counts the rows of the acts before. Seeds of
  finds, drops and chests take the act into account (each act numbers its stops from 0); a locked
  chest also takes its index in the zone into the seed, so two chests in one visit differ (card #176).
- **The map** (card #162): stop kinds and weights: zone 45, event 25, elite 12 (not before row
  `run_elite_min_row` 2, never two in a row), shop 12, rest 12; row 0 zones, row 3 treasure, the
  row before the boss campfires, at least one shop. New painted pictures (art kit `map_art.py`):
  a horned skull over crossed blades (elite), a red "?" (event), a gold-banded chest (treasure),
  the Husk Lord's crowned hollow tree (act 1's lair). A **legend** down the left side names every
  picture. **Planning**: while a next stop is picked, every stop and road it cannot lead to is
  drawn faint (`unreachable_alpha`), so its roads ahead stand out.
- An act with no elite fights or no events never gets those stops: `RunMap.generate` takes
  `has_elites` and `has_events` (filled from the act's lists) and zeroes their weights, and Main
  leaves an Elite stop with no fight as an empty stop with an error instead of crashing (card #176).
- Online: `RunState.to_dict` carries the act (the client rebuilds that act's map), the stops
  visited, the campfire points, the events met, the shop's restocks and the Tonics drunk.

### 8.10 The shop (card #160)

- `ShopScreen` is now a place: **The Rag Merchant** (a hooded trader with gold scales, art kit
  `env_zone.py`) on the left with a line for every sale, the **shelves** on the right: this stop's
  stock, `run_shop_items` (4) items picked from the run's shop list (`RunState.shop_stock`), 2
  charms and 2 pieces of gear, a card each with its picture (items their icon, gear a gold amulet),
  name in its rarity colour and price, SOLD when bought. Under them the **services**: Cleanse (35:
  throw away a rotten item), Upgrade (45: an item up a level), Restock (20, and `shop_restock_step` (20) more
  for every restock already bought at this shop, back to 20 at the next stop: new stock on the
  shelves, `RunState.restocks`, `restock_price()`; card #175), Sell (the backpack) and Leave. No Heal service (user 2026-10-16:
  it did the same as a Salve for the same price; healing is bought as items). Arrows move over shelves and services, Confirm buys, Tab / Y sells, Back leaves.

### 8.11 The campfire (card #161)

- A rest stop is a campfire: the heroes stand round a flickering fire with its glow, and the
  player picks **one**: **Rest** (everyone heals `run_rest_heal_percent`), **Train** (every hero
  gets `rest_train_points` (1) attribute point, `RunState.bonus_points`) or **Upgrade** (one
  backpack item up a level for free). The bot rests when hurt, else upgrades, else trains.

### 8.12 Living zones (user, 2026-10-17: "the ruins should have ruins, roads; the swamp should have a swamp, jungle; make the zones feel alive")

- **Each zone has its own places** (`tools/bootstrap_zones.gd`, 5 middles each, 3 per visit):
  - **Ashen Ruins**, a dead city: a cobbled road runs through it all; the city gate (posts,
    banners, braziers), the Old Road between broken walls with a burnt house behind them, the Plaza
    (paving, a dry fountain, statues, braziers), the Colonnade (a covered walk of pillars), the
    Graveyard (rows of headstones round a walled crypt: the champion), the Collapsed Hall (rooms
    behind a wall with doorways); arches and broken walls line the back wall.
  - **Sunken Bog**, swamp and jungle: deep water everywhere (it blocks walking) with lily pads and
    reeds; the Boardwalk (planks across two lagoons, a side walk to an island), the Stilt Village
    (huts on stilts, planks, lanterns, puddles), the Mangrove Tangle, the Lily Pond (two ponds hold
    a spit of land with the champion), the Mushroom Grove (rings of glowing giant mushrooms); a
    wall of swamp trees stands past the back and both ends.
  - **Rotten Hollow**, a rotting forest on a dark leaf-litter floor: a dirt trail under dense
    trees; the Forest Trail (a side trail behind thorns to a clearing), the Woodcutter's Camp
    (campfire, stumps, logs, a cart, a well), the Chapel Yard (ruined chapel walls and grave
    crosses: the champion), the Thorn Thicket (one way through the briars), the Fallen Giant (a dead
    tree lying across the forest); a tree wall past the back and both ends.
- **Ground pieces** (`ZoneGroundData`, `scripts/stage/ground_patch.gdshader`): roads, trails,
  paving, mud, moss, ash, planks, lily pads and water laid on the floor, their textures tiling in
  world space like the floor's, their edges eaten away per art pixel (`edge_noise`). Water scrolls
  two layers of its texture, darkens toward the middle, keeps a muddy rim and sparkles; solid water
  is obstacles for walking (`ZoneMotion.ground_obstacles`: a box, or circles filling an ellipse,
  `SHORE` inside the drawn edge). Textures: art kit `env_ground.py`.
- **Props** (art kit `env_life.py`): ruins (broken arch, knight statue, fallen column, rubble,
  brazier, torn banner, gravestone, dry fountain, low wall, bones), swamp (reeds, mangrove, mossy
  tree, giant mushroom, log, stilt hut, swamp lantern, fern), forest (bush, stump, thorns, fence,
  cart, well, signpost, grave cross, dead pine) and the woodcutter's campfire.
- **Wind** (`ZonePropData.sway`): grass, reeds, ferns, banners and trees sway (the sprite shader
  bends the top; feet stay; each prop's phase from where it stands).
- **Air** (`ZoneAmbientData`, particles that follow the camera's spot): ruins ash falling and
  embers rising; swamp fireflies, low mist and spores; forest falling leaves and fireflies.
- **Critters** (`ZoneCritterData`): crows, frogs and rats idle (two frames) and get away when the
  leader comes within `critter_flee_radius` (a crow flies up and off, a frog hops away, a rat
  scurries off); for show only, each machine plays them itself online.
- **Front and ends**: low growth (reeds, ferns, bushes) just past the front edge frames the view
  (the camera blurs it); nothing tall stands in front of the walkways.
- `tools/zone_map_preview.gd` draws every zone from above to a picture (ground, water, walls,
  props, enemies, seals, shrines) to check a layout without opening the game.

### 8.13 Phase 16 run balance (cards #175 to #178, 2026-10-17)

The owner wants the game hard, so these only close exploits and make the last fight harder; nothing
here makes a run easier.

- **Gold must not become endless max HP** (#175). Tonic gave +15% max HP for the rest of the run for
  45 gold and Restock re-rolled the shelves for a flat 20, so gold turned into HP without limit.
  Two caps, both in `tuning.tres`: each Restock at one shop costs `shop_restock_step` (20) more than
  the last (`RunState.restock_price`; the count starts over at the next stop), and a hero can drink
  at most `tonic_max_per_hero` (2) Tonics per run (`RunState.tonics_used`, `tonics_left`). A capped
  hero is greyed on the party screen's hero cards with the reason in the info line, the shop stops
  selling Tonics once every hero is full, and a Tonic drunk by one hero still works for another.
- **A reset never heals** (#175). `set_attributes` keeps the HP a hero is missing the same, which is
  exact until the lower max HP would leave them under 1 HP. The old code clamped to 1 there and
  forgot the rest of the missing HP, so reset, respend gave it back: a free heal of the whole
  Vitality bonus, always available because a downed hero stands at 1 HP. Now such a change is
  refused ("too wounded to give up that max HP. Heal first."). Chosen over "keep HP absolute"
  because that would stop a Vitality point from filling the hero when it is first spent.
  Random sequences of changes are tested to leave the missing HP unchanged.
- **Elites cannot be run from** (#175), a rule in `CombatSetup.from_encounter` (see 2.13), not eight
  edited files.
- **Small bugs** (#176): HP is clamped to max after every backpack change that can drop a charm's
  max HP (sell, throw away, combine, move, cleanse, items used in a fight); a locked chest's prize
  seed includes the chest's index; a Slowed boss that enters phase two stays slowed (the slow is
  taken from its new normal speed, so Hamstring is not wasted); the map never rolls Elite or Event
  stops for an act with none (8.9).
- **The Hollow King is the hardest fight** (#177). It was softer than what came before: 350% HP,
  120% power, speed 140 to 175, alone, while the Husk Lord (act 1) has a Rotten Husk at its side, and
  the deep guards in act 2 grow with depth (up to about +65% HP and +39% power) but bosses do not
  (`run_enemy_scale_bosses` is off, 8.3). Counting each attack's hits, the King's party-wide damage
  was about 144 per 100 ticks (170 in phase two) against about 215 (270) for the Husk Lord fight and
  about 315 (440) for Mire Mother with her fly at the deepest row. Data-only retune of
  `hollow_king.tres`: 650% HP (5850), 165% power, speed 155, phase two speed 210 (phase two still at
  half HP), and a Hollow Shade stands at its side (`data/encounters/hollow_king.tres`). That is
  about 220 (280) damage per 100 ticks from the King alone, 325 (385) with the shade, and about 1.3
  times the HP of the toughest guard at the deepest row (6885 against 5184), so the fight is the
  longest and hardest of the run. A test
  keeps it so (`test_run_balance.gd`: more HP than the Husk Lord fight and every guard at the
  deepest row, at least their power, faster and enraging faster). The attacks themselves are
  unchanged, so a player who defends well takes the same hits as before, only more of them and for
  longer.
- **An honest balance bot** (#178). The bot used to fight every champion and roamer at any HP, so
  its runs died early and said little. It now plays like a careful player (named consts in
  `ZoneAutoplay` and `Main`, not game rules): a champion or optional roamer is fought only while
  the weakest hero has at least 60% HP, the party averages 80% and every hero is at least level 3
  (an elite is 40% tougher than a normal fight, and a fresh party loses it); roamers within 6 units are
  hunted for XP and gold while healthy; it uses its healing items before it walks into the guard; on
  the map it takes an Elite stop only while healthy and picks a campfire when any hero is at or
  under 60% or the party averages under 75%; at a campfire it rests when hurt, else upgrades or
  trains. A hero capped on Tonics is skipped. The bot cannot dodge a roamer that notices it. Do not
  tune enemies to make these runs win; read them as "an average player's run".

---

## 9. Multiplayer (phase 5)

### 9.1 Local co-op (phase 5 Part A, done)

- **Players screen** (`LobbyScreen`, approved 2026-10-12): New Run and Practice open it first. The
  device that opened it is P1. Another pad (or the keyboard) presses Confirm to join (up to 3
  players) and Back to leave. Heroes are dealt out in turn (P1 gets the extra one: with 2 players
  P1 has Alder and Cass, P2 has Brin); left/right on a hero hands it to another player, as long as
  every player keeps one. Start (selected first) plays; P1's Back returns to the main menu. The
  roster is kept for the session (same P1 = same split next time).
- **Hero cards** (cards #140, #141, user 2026-10-15): the players screen shows the heroes side by
  side as big painted portraits, like an arcade select screen (Metal Slug was the reference, but
  serious faces, not goofy): the players on one line at the top, then a framed card per hero (the
  portrait's top 240 rows at 2x) with a name plate under it saying who plays it ("P1", or
  "< P1 >" in co-op). Up/down still walks Alder, Brin, Cass, Start, Back; the hero the cursor is
  on gets a gold frame and the others dim. The portraits are painted pictures the user made with
  an AI image tool (`tools/art_kit/sources/portraits/`, the words in `PROMPTS.md` there), turned
  into pixel art by `tools/art_kit/portraits_from_pictures.py`: 192x288, 64 colours
  (`CharacterData.big_portrait_path`). The same tool cuts a 64x64 face from each picture (boxes in
  `faces.json`), which is now the hero's `portrait_path`: the party panels, the turn order, the
  party screen and the practice list all show it. (A code-drawn big portrait was tried first and
  dropped: it looked like a clay toy.)
- `PlayerRoster` (pure, `scripts/coop/`): players and their devices, hero slot -> player. A hero is
  a party slot, so the roster fits every fight. One player = solo: every device controls
  everything, exactly as before.
- **Fights**: the action menu answers only the acting hero's player (title shows "(P2)"); party
  panels show P1/P2/P3 tags in player colours. The engine is unchanged (ownership is presentation).
- **Defence and skill presses**: `JudgeSet` (pure, `scripts/combat/timing/`) holds one
  `DefenseJudge` per player with only that player's heroes' prompts. A press counts only for the
  heroes of the player whose device made it: each player defends their own heroes on a party-wide
  attack, presses their own skills, their own heroes' follow-ups, and their own part of the team
  ultimate. Whiff lockout, EARLY/LATE popups and the lock icon are per player; a player whose
  heroes are not targeted is ignored (no lockout). One shared `AttackClock`, one lag compensation
  (one machine). Results are released per player in prompt order (a hero's prompts stay in hit
  order, which is all the engine needs).
- **Zones**: only P1 walks and strikes (approved 2026-10-12); `DeviceInput` reads one device
  through the Input Map. Run screens (map, shop, rest, party, loot), pause and end screens: anyone.
- Bot: `--players=N` plays co-op with N pretend pads; each player presses for their own heroes.

### 9.2 Online co-op (phase 5 Part B, done)

- **Host-authoritative, the host is the server.** Main menu: **Host Online** listens (port
  `net_port`, 7777) and shows the PC's addresses to share; **Join Online** takes an address
  (remembered per machine). One player per machine (P1 = host). Same Wi-Fi works as is; over the
  internet both use Tailscale (or the host forwards the port). Approved 2026-10-12: IP first.
- `Net` autoload (`NetSession`, `scripts/autoload/net.gd`) wraps Godot's high-level multiplayer.
  The transport is a `MultiplayerPeer` (ENet today); everything above it only uses the
  high-level API, so Steam's peer (GodotSteam: friend invites, NAT punch-through and relays) can
  replace ENet later without touching the game.
- **Handshake**: a client first sends its content fingerprint (`DataHash`: SHA-256 of every file
  under `data/`, line endings ignored, plus the project version). A mismatch, a full game (3
  players) or a started run is refused with a reason shown on the Join screen. Until welcomed, a
  client's messages are ignored. A client that never says hello is dropped after
  `net_connect_timeout_ms`.
- **Messages** are (kind, Dictionary of plain data). Reliable ones share one ordered channel (game
  flow and combat must never overtake each other; this replaces the "dedicated combat channel"
  idea); zone positions go unreliable on channel 1. Only the host may send to clients
  (`@rpc("authority")`); clients' messages to the host are checked against the sender's peer id.
- **Players screen online**: the host's lobby lists who joined, hands heroes out (left/right) and
  starts; clients watch it. Starting closes the game to new joiners.
- **Run flow**: the host's machine runs the run exactly as offline. Each screen it shows is sent
  as a "screen" message with the whole `RunState.to_dict()` (gear by id; the map comes from the
  seed); any later change of the run (a purchase, gear, a level) is sent as "run". Clients only
  show: their map, shop, rest, loot, party and end screens are the same screens fed with the
  host's state, input off, with "The host is choosing (P1)" on top. Messages that arrive during a
  client's transition wait for it. Approved 2026-10-12: P1 (the host) makes the run choices.
- **Zones**: the host's zone is real and sends `net_snapshot()` (leader, facing, walking, strike
  count, every roaming enemy's spot, state and defeat) `net_zone_send_hz` times a second; a
  client's zone is `remote`: walkers glide there (`net_follow_ms` in `explore_visuals.tres`). A
  fight starts when the host says (`zone_fight` with the index, the opening and the fight's
  seed), with the same opening flash on every machine.
- **Fights**: `CombatController` runs in HOST mode (the only `CombatEngine`) or CLIENT mode (no
  engine). Both build the same `CombatSetup` from the host's seed (for the data). Every batch of
  events the host's engine returns is sent: "flow" batches go to the event queue, "timing"
  batches (answers to `resolve_prompts`) to the runner playing that sequence, or wait until that
  sequence starts there. The runners apply batches strictly in arrival order (an inbox), so the
  mirror always follows engine order. When a runner finishes, its tail goes in front of anything
  that arrived later. Autoplay prints `AUTOPLAY_MIRROR <result> <hash>` on every machine: equal
  hashes = every machine ended the fight in the same state.
- **Menus online**: a hero's turn menu opens only on its player's machine; the others see
  "P2 is choosing". A client's choice goes to the host, which takes it only if that client owns
  the acting hero and it is that hero's turn.
- **Defence and skill presses online**: each machine plays the attack itself (from
  `timed_sequence_declared`) and judges only its own player's prompts (`JudgeSet` with
  `only_players`), on its own clock with its own lag compensation: network lag never shifts a
  window. It sends its results to the host and tells the host when it started the sequence
  (ack). Another player's result is shown when it arrives (a defence pose at once, a hit only
  when that prompt would have closed, so HP never drops before the swing lands).
- **DefenseArbiter** (host only, pure, `scripts/net/`): deadlines per remote prompt = start (the
  ack, or declare + `net_ack_timeout_ms` if none) + lead-in + close time + one hit-stop allowance
  per hit so far (largest hit-stop + `calibration_max_ms`) + `net_deadline_grace_ms`. Overdue
  prompts are resolved as NONE by an explicit command (so a replay has it). It accepts a client's
  results only for its own heroes, the current sequence, and once per prompt. The host also sends
  a character's earlier still-open prompts as NONE with a later one, so the engine never refuses a
  batch.
- **Someone leaves**: a client that leaves mid-run hands its heroes to the host (P3 becomes P2);
  its open prompts are resolved at once and the others are told. If the host leaves (or ends the
  game from the pause menu), everyone goes back to the main menu with a note. Online, the pause
  menu opens over a game that goes on (it offers Leave / End the game).
- **Sharing the game**: `build_game.bat` exports `build/RottenLands.zip` (one exe). Everyone online
  plays that same build: a run from the editor has a different content fingerprint (the export
  stores resources differently) and is refused.
- Bot: `--host=N` hosts and starts a run once N players are in; `--join=ADDRESS` joins. Both play
  with `--autoplay`; each presses only for its own player.

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
  at window centres. Balance checks (phase 6): `=average --bot-skill=N` lands N% of its defences
  (half parries, half dodges; jumps for ground hits) and N% of its skill presses (half perfect,
  half good), letting the rest go; it prints `AUTOPLAY_BALANCE turns= seconds= party_hp_percent=`. At the end the game prints `AUTOPLAY_RESULT victory|defeat` and an
  `AUTOPLAY_STATS` line, then quits (with `--quit-on-end`). Problems print `AUTOPLAY_ERROR ...`
  (a rejected command, or the mirror not matching the engine). Run it with `--quit-after 60000` as
  a hard cap and a `timeout`, and fail if the result line is missing (a hang) or the log has an
  ERROR or AUTOPLAY_ERROR line.
- Also covered: attack clock with timestamps past 2^31 us (36 minutes of uptime), late presses
  reported as LATE on a landed hit, prompts expired inside a capped press, enemy choreography
  (every lunge reaches contact exactly at impact, contact holds until the hit closes, cue times),
  defence statistics and the calibration clamp. Data validation tests check meaning (ids unique, times increasing, spacing rules,
  paths exist, weights > 0), not just loading.
- Phase 3 (`test_zone.gd`, `test_hit_rhythm.gd`, `test_press_notes.gd`, additions in
  `test_combat_engine.gd`): walking blocked by props, (turned) blocks and bounds, long steps never
  pass a thin wall, strike reach and arc, roaming enemies wander near home, warn before chasing,
  stay calm after a fight, give up and go home, chasing is slower than walking, every shipped zone
  is valid (start and enemy spots free, enemies not next to the start), camera shots frame their
  subjects, the first strike opening (every party member before any enemy, even a very fast one).
- Zone smoke test: `--autoplay --zone=rotten_hollow --quit-on-end`. The zone bot walks to the
  nearest enemy; `=perfect` strikes first, `=miss` and `=mash` walk into it. Each fight prints its
  usual lines; the run ends with `AUTOPLAY_RESULT zone_clear fights=N first_strikes=M` or
  `AUTOPLAY_RESULT zone_defeat ...`; `AUTOPLAY_ERROR zone_stuck` if no fight starts for a minute.
- Phase 4 (`test_run.gd`): for 200 seeds the map has the right rows and stop types, a shop, no
  crossing paths, every stop reachable and leading on, no shop or rest twice in a row, zones not
  repeated from the last zone on the way there (unless those paths met every zone); same seed,
  same map; only connected stops can be chosen; HP carries over, victory pays gold and gets the downed up,
  never above max; defeat and the final win end the run; rest and every shop item follow the
  rules; a fight starts with the run's HP and max HP (engine and run agree); the shipped run is
  complete (one guard per zone, a valid final fight) and every enemy pays gold.
- Part B (`test_part_b.gd`): counters grow per extra hit and for mixed strings; every gear
  passive in a fight (start AP, AP after a counter, heal on a perfect jump, tough, Second Wind once
  after the attack, perfect press and Exposed in skill damage, stronger heals); run power, speed and
  max HP reach the engine; unknown passives are refused; the boss enters phase two once (new
  attacks, speed, intent); levels (thresholds, max level, stat growth, heal on level up); a
  victory pays XP; loot and shop gear are seeded and never offer owned gear; equip, swap, take
  off (no free heal, HP clamped); gear reaches the fight setup and the gold bonus; the shipped gear
  and boss are complete. The event-fields test also covers `enemy_phase`.
- Phase 5 Part A (`test_coop.gd`): solo controls everything from any device; join, leave, the
  even split, handing heroes over (never leaving a player without one), device codes of events,
  the shipped party fits three players; per player judging (a press answers only its player's
  heroes, lockout per player, a player with no prompt is ignored, solo equals one judge, the engine
  accepts the per-player results in release order, voids reach every judge); the players screen
  (join, hand over, leave, start, back, keeps the last split for the same P1). Co-op smoke test:
  add `--players=2` or `--players=3` to any autoplay command.
- Phase 5 Part B (`test_online.gd`): the online roster (one player per machine, any device on it
  plays its player, sent as data and refused when malformed, a player dropping out hands heroes
  to the host), the arbiter (deadline from declare + timeout, then from the ack; later hits get
  more; overdue prompts once as NONE and the engine accepts them; only own open prompts of the
  current sequence, once; a leaving client resolved at once; engine-resolved prompts left alone),
  the fingerprint (stable, version, line endings, changed numbers, import files ignored) and the
  run state round trip (and refusals that change nothing).
- Online smoke test: start `--autoplay --host=2 --seed=N --quit-on-end` and then
  `--autoplay --join=127.0.0.1 --quit-on-end` (both headless, about 15 minutes). Both print the
  same `AUTOPLAY_RESULT run_...` line and the same `AUTOPLAY_MIRROR` hashes, and no ERROR lines.
- Run smoke test: `--autoplay --run --quit-on-end` (add `--seed=N` for a fixed map). The bot
  picks a shop when it has gold, a rest when someone is at or under 60% HP (or the party averages
  under 75%), an elite stop only while the party is healthy, else a zone; in zones
  it walks to the guard, after its healing items; in shops it buys what it can for whoever is lowest; it takes the first
  loot and puts every bag item on whoever has the most free slots. Ends with
  `AUTOPLAY_RESULT run_victory|run_defeat stops=N fights=N level=N gear=N gold=N seed=N`.
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
2. **Classes and co-op combat** (done): classes, skills with timed presses, Follow-up Strikes,
   team gauge and ultimate, marks/combos, downed/revive, enemy intent, several enemy types with
   distinct attack patterns, fight select.
3. **HD-2D look** (done): one explorable zone, roaming enemies, fight transition, first
   strike, combat camera, post-processing (7.3, 7.4, 2.12).
4. **Run structure** (built, waiting for playtest): Part A (main menu and settings, map,
   zone/rest/shop stops, HP carry-over, gold) and Part B (levels, gear, loot, boss, pause menu,
   stronger counters); 8, 7.5, 2.5.
5. **Co-op** (done, approved 2026-10-12 after an online test with a friend): Part A local
   multi-device (9.1), Part B online by IP (9.2), the studio intro (7.5). Steam invites later
   (swap the transport).
6. **Polish** (done, approved 2026-10-13): UI, feedback effects, controller button hints, fonts
   (7.6), Run (2.13), one press per ring, balance (shorter fights, same difficulty). Sound and
   music moved to phase 7; real art has its own phase.
7. **Sound and music** (done, approved 2026-10-13): real recorded sound effects for 66 moments,
   songs per place with crossfades, boss rage song, music dip, zone ambience, enemy voices, hero
   shouts, volume sliders (5.3). Backpack sounds wait for the backpack (phase 11).
8. **Branding** (done, approved 2026-10-14): the name Rotsworn, the minimal worn-gold logo and
   game icon, title screen (swaying ribbon, letters flickering like static), worn-gold menu
   choices and titles, credits, loading tips, story, the studio intro re-rendered in HD (7.5,
   7.6, 7.7). Hero portraits wait for art; the trailer and Steam page come later.
9. **Real art** (done, approved 2026-10-14): every sprite drawn by code with the art kit (5.4):
   heroes, enemies (each its own creature), portraits (48x48; the heroes' were replaced by painted faces in 9.1's hero cards), ground
   textures, backdrops per place, props, effects, HUD icons (cards #40, #85, #116 to #124).
10. **Animation** (built, waiting for playtest, 2026-10-14): multi-frame animations from blended poses: idle breathing, ready stance,
    defence poses, hit reactions, skill moves, follow-up entrance, team ultimate, downed and
    revive, victory, enemy wind-ups, hits and deaths, walking in four directions, item pickup
    (cards #58 to #71).
11. **Backpack and items** (done, 2026-10-14, 8.1): grid backpack, consumables, charms, rarity, chests and
    keys, items in fights (cards #55, #57, #72, #73, #75 to #79, #91, #103).
12. **Monsters** (done, approved 2026-10-14): three steps. Step 1 (built): new
    attack types (ranged throws 3.9, rock waves and a clearer wave 3.10, each hero in turn 3.11)
    given to the first monsters (2.14). Step 2 (built): new monsters, a Carrion Fly, a Rot Hyena
    (Pack Bite) and a Mire Toad (2.15). Step 3 (built): monster variants met deeper in a run
    (2.16) and the new sounds (5.3) (cards #114, #125, #143 to
    #145).
13. **Leveling and skills** (done, approved 2026-10-15): E33-style attributes and
    skill trees, critical hits, class reworks (Alder shield-only, Brin twin daggers, Cass healer),
    enemies that grow stronger deeper into a run (cards #56, #80, #81, #105, #134 to #139). Three
    steps: step 1 (built, 8.2) XP and a level per hero, attributes and their screen, critical hits; step 2 the
    class reworks with skill trees (proposed to the user first); step 3 depth scaling. Nothing
    carries over between runs.
14. **Tutorial** (done, approved 2026-10-15): the five lessons of 7.8 (card #131).
15. **Zones and stops** (done 2026-10-17: merged to main, cards #155 to #164 closed by the user's
    say-so before a full playtest; living zones 8.12 added on top): four steps. Step 1 long zones (8.5: sections,
    seals and a gate, shrines, wanderers, champions; cards #155, #164). Step 2 tougher fights
    (guards as mini-bosses #156, elites #157). Step 3 the map and its stops (#162 map, #158 events,
    #159 treasure, #160 shop, #161 rest). Step 4 longer runs (#163).

### 11.1 To-do (from playtests)

Open items the user raised after playing; pick them up at the start of the next phase.

1. **Press ring speed and style per move** (after phase 2, 2026-10-12). **Built in phase 3 (4.5).** Each ability (and each
   enemy attack's training ring) sets its own ring speed and look in its data file: the basic
   attack at normal speed, skills at their own speed (for example faster for big skills).
2. **Multi-press skills as separate rings** (after phase 2). **Built in phase 3 (4.5): osu notes.** Quick Cuts, All In and the team
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
| 2026-10-12 | Co-op heroes picked on a players screen, dealt out evenly by default | user choice |
| 2026-10-12 | In co-op zones only P1 walks and strikes | no tug-of-war on one screen; user choice |
| 2026-10-12 | Co-op ownership lives in presentation (`PlayerRoster`, `JudgeSet`), not the engine | engine stays the same for solo, local and online |
| 2026-10-12 | Online: join by IP first, host is the server; transport swappable for Steam later | free, works now; Steam invites need a store page |
| 2026-10-12 | Online run screens: the host chooses, the others watch the same screen | one source of truth for the run, no desync |
| 2026-10-12 | Online run state replicated as a whole (`RunState.to_dict`), not as actions | clients never run run logic, cannot drift |
| 2026-10-12 | One reliable channel for flow and combat messages | order between them matters more than separation |
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
| 2026-10-12 | Phase 4: short one-act run (~8 stops), hand-made zones picked at random, built in two parts | user picks "A, A"; quick to test, zones look good |
| 2026-10-12 | Part A: two new zones now, shop sells care (Salve, Feast, Tonic), no mid-run save | user picks "A, A, A" |
| 2026-10-12 | Shop has no revive | a victory always gets the downed back up, so nobody is down between fights |
| 2026-10-12 | Map: first row zones, rest row before the final fight, no shop/rest twice in a row | a run opens with exploring and lets the party heal before the end, like Slay the Spire |
| 2026-10-12 | Run fights have no "fight again" (R) | HP and gold carry on; a retry would undo a loss |
| 2026-10-12 | Part B: loot = pick 1 of 3 after each guard + 2 gear in shops; boss with two phases | user picks "A, A" |
| 2026-10-13 | Balance (card #41): enemy HP 1500 -> 900, enemy hit damage 28 -> 40 | user: keep it hard, make fights shorter; bot tests (average player bot) showed about 37% fewer turns with the same win rates |
| 2026-10-13 | Run: hold B, one slow ring, only PERFECT escapes; a miss loses the turn; never from bosses | user design; holding stops accidental runs |
| 2026-10-13 | One press per skill or follow-up ring: an early press spends it as a miss | user found a second press after an early one still scored |
| 2026-10-13 | Fight menu: A attack, X skills, Y items, B run, RT ultimate; no cursor | user layout (Expedition 33 style) |
| 2026-10-13 | Hit markers off; training ring only in practice, not in Settings | user: the circle on enemy hits made the game easier |
| 2026-10-12 | Intent shows until the first hit lands, then the hit row and markers hide | user request: a little harder, rewards remembering the pattern; the enemy's motion stays readable |
| 2026-10-12 | Fonts: Cinzel titles, Alegreya Sans text (OFL) | user pick "font A": Octopath-like storybook titles, easy-to-read numbers |
| 2026-10-12 | Phase 6 split: Part A UI + feedback + controller hints, Part B audio + balance | Part A can be built and judged from pictures; balance needs playtest feedback |
| 2026-10-12 | Button hints follow the last device used; both kinds in mixed local co-op (card #45) | a pad player sees pad buttons, a keyboard player keys; mixed co-op needs both |
| 2026-10-12 | Run fights hide the practice panel and practice keys | a run is the real game; the panel cluttered every run fight |
| 2026-10-12 | Pause on Esc / Menu (not B); a fight pauses only between events | user request; attacks and skills are timed on the real clock and cannot be frozen fairly |
| 2026-10-12 | Counters +25% per extra perfect hit, +50% for a parry-and-jump string (card #52) | user request: reward long and mixed strings |
| 2026-10-12 | Party shares one level; gear is one passive per item; equipping never heals | simple to read; swapping gear must not be a free heal |
| 2026-10-12 | Card #51: party power 40 -> 75 (not lower enemy HP); team counter 120% -> 90%; Shield Bash 180, Hamstring 150, Payback 150, Rend 300, All In 5x120 | user pick: fights about half as long with bigger hits; costly skills now pay more per AP than Quick Cuts (1 AP 150%, 2 AP ~180%, 3 AP 300%, 5 AP 600%) |
| 2026-10-12 | Phase 3 built all together (user request) | one zone, look, camera, roaming enemies and first strike in one pass |
| 2026-10-12 | One `StageLook` per place, shared by the zone and its fights | a fight looks like the place it started in |
| 2026-10-12 | Sprites lit by the scene, flashes and glows as emission | HD-2D: sprites belong to the lit diorama; bloom catches telegraphs and parries |
| 2026-10-12 | Combat camera settles when the attack clock starts | moving the view while you defend would make reading the enemy harder |
| 2026-10-12 | First strike = whole party acts before any enemy; touched = normal start (no ambush yet) | card #25; simple, clear reward |
| 2026-10-12 | Roamers warn ("!") before chasing, chase slower than walking | getting touched should be your mistake, not a surprise |
| 2026-10-12 | Zone movement is presentation (floats, real time), not the combat engine | co-op movement is a phase 5 card (#36) |
| 2026-10-12 | Skills with follow-ups framed wide from their start (bug #49) | Cass's follow-up ended up off screen; moving the camera mid-sequence would also move the rings |
| 2026-10-12 | Ring speed per move as a percent of `ring_lead_ms` (basic 100, skills 85, big hits 65) | user request; per-move shapes are percentages of tuning values |
| 2026-10-12 | Multi-press skills: numbered rings in a row (osu notes), one per press moment | user pick over "one at a time", which would have slowed fast skills down |
| 2026-10-12 | Skill presses have three results: perfect (bonus), good (normal), miss (50%); osu-style ring with GOOD and PERFECT bands | user feedback: the ring had no visible spot to hit and no distinction between perfect and normal |
| 2026-10-13 | Sound effects from real CC0 recordings, three options per moment, user picks by ear | the user asked; synthesized placeholders sounded fake; Claude cannot hear, so checks measure and the user listens |
| 2026-10-13 | The game is called Rotsworn (one word); repo renamed to `JawadAlSaeed/Rotsworn` | user pick; no game uses the name; one word matches the logo and is easy to search |
| 2026-10-13 | Logo and icon painted by code (tools/branding): shield behind, twin daggers and staff in front, bound by a ribbon | user: the ComfyUI cut-out had white edges, a flat vector redo was too cartoony; no mushrooms, no bright spark |
| 2026-10-13 | Loading tips hold 2.6 s, then the zone is built | long enough to read; the zone starts when it is seen |
| 2026-10-14 | Phase 9 art drawn by code (3D shapes rendered to pixel art), not free asset packs | user pick |
| 2026-10-14 | Sprites keep their size (heroes 32x48); portraits grow from 24 to 48 px | user pick: Octopath-like chunky pixels; the HUD shows portraits at 56 to 64 px |
| 2026-10-14 | Alder: shield and backpack, no sword | user request; matches the shield-only rework (#56) |
| 2026-10-14 | Every fighter at one pixel density (0.045); enemy frames sized per enemy | mixed pixel sizes (0.04 to 0.075) looked uneven; on-screen sizes stay the same |
| 2026-10-14 | #105 (enemies scale with run depth) moved to phase 11; new phase 12 for monsters | user pick |
| 2026-10-14 | Phase 11 is the backpack only; class reworks and #105 belong to phase 13 (leveling and skills) | matches the board |
| 2026-10-14 | Backpack holds consumables, charms, keys and treasure; charms boost neighbours | user pick: packing should be a puzzle, not just storage |
| 2026-10-14 | Gear never goes in the backpack; new gear goes straight onto a hero | user: a run gives about 5 or 6 gear for 9 slots, so spare gear would almost never happen |
| 2026-10-14 | Shop potions go into the backpack; roaming monsters sometimes drop small things | user picks |
| 2026-10-14 | Co-op: anyone moves backpack items at any time; online the host keeps the real backpack | user pick |
| 2026-10-14 | Phase 12 adds ranged attacks, rock waves, each-hero-in-turn attacks and monster variants on top of new monsters | user request ("we need monster variants, new attacks, ranged attacks, ground attacks that create rock waves") |
| 2026-10-14 | Projectiles, ground looks and the throw are presentation only; a ranged hit is a normal hit to the engine | keeps the engine and online sync unchanged |
| 2026-10-14 | Variants are recoloured kin (same clips) met from map row 4 of a run, each with one move of its own | user asked for variants; recolouring keeps every animation for free |
| 2026-10-14 | New sounds (3 voices, spit, throw, shadow bolt, splat, rock rumble) built from CC0 recordings, picked by the user on the listening page | user picks |
| 2026-10-14 | No static on menu text and titles, just the gold tint (the logo keeps its static) | user: some texts were not readable |
| 2026-10-14 | Phase 13 in three steps: (1) XP, level up, attributes, attributes screen, critical hits (#134, #135, #137, #138); (2) class reworks with skill trees (#56, #80, #81, #136; trees proposed first); (3) enemies scale with run depth (#105) | user pick: step 1 first, trees build on it |
| 2026-10-14 | Each hero has their own level and XP (replaces the shared party level) | user pick, like E33; a hero downed often can fall behind |
| 2026-10-14 | Nothing carries over between runs: every run starts at level 1 with no points or skills (#139) | user pick: pure roguelike for now; can revisit later |
| 2026-10-14 | Downed heroes get half the fight's XP | default proposed to the user; keeps a level per hero meaningful |
| 2026-10-14 | 3 attribute points per level; levels keep +4% HP and power (was +8%) | points carry the rest of the growth |
| 2026-10-14 | Attribute changes count at once, resetting is free, missing HP stays the same | no confirm step to forget; respending can never heal |
| 2026-10-14 | Crits: 5% base, Luck +2% a point, 150% damage, party only, rolled with the damage | E33-like; rolled in the declared event so online stays in sync |
| 2026-10-14 | Attributes screen on T / LT from the party screen | the party screen's other buttons were taken |
| 2026-10-15 | Team gauge carries over between fights in a run (`run_team_gauge_carry_percent`, 100) | card #146 |
| 2026-10-15 | No names over roaming enemies; the guard keeps a gold GUARD tag | card #127 |
| 2026-10-15 | Feints marked with a dashed ring on the hit rows | card #129 (reverses "the marker never gives the feint away") |
| 2026-10-15 | Loading screen blocks all input | card #132 |
| 2026-10-15 | Settings in four sections with graphics options and screen shake | card #112 |
| 2026-10-15 | Enemies grow 5% HP and 3% power per map row (not bosses) | card #105; first guess, to tune with play |
| 2026-10-15 | Cass: every skill is ranged; only her normal attack walks up (#81) | user note |
| 2026-10-15 | Skill trees: 5 skills brought, 1 skill point per level | user picks (#136) |
| 2026-10-15 | Main menu: no tagline, no button bar; other hints stay | user (#130): only the main menu's bothered them |
| 2026-10-15 | Tutorial: six lessons, offered once on the first run and always in the main menu | user approved (#131) |
| 2026-10-15 | Lag calibration page laid out centred like the other pages | user (#113) |
| 2026-10-15 | Run map is an old paper map that unrolls, with painted places instead of letters | user (#111) |
| 2026-10-15 | Run map scrolls (a tall sheet between two rollers, like Slay the Spire) | user: close rows left no room for the paths |
| 2026-10-15 | Fight HUD restyled: slanted Persona 5 plates, party cards bottom left, intent on the enemy panels, target lock-on (7.9) | user (#154), approved 2026-10-16 |
| 2026-10-15 | Action menu floats beside the acting hero; the hero steps forward onto a gold ring, the others step back and dim; locked options fade; no name tag | user: it felt cheap and the turn was unclear |
| 2026-10-16 | Turn order is a column on the left; the attack banner sits at the top; the ultimate's button (RT UNLEASH) is on the team gauge, not in the action menu | user: frees the top above enemy throws, cleaner menu |
| 2026-10-16 | Phase 15 step 1: zones run left to right, about 4 times longer, built from shuffled sections | user picks (#155, #164) |
| 2026-10-16 | Seals open the gate to the guard (2 of 3, tuning) | user: "I can still go to the guard directly"; first try, to tune with play |
| 2026-10-16 | Shrines, wanderers and champions in zones, all optional | user: keep all four zone things |
| 2026-10-16 | Guards are named mini-bosses (recoloured kin) with a phase two; spoils are rare or better | card #156; recolours keep every animation |
| 2026-10-16 | Elite fights: map stops and zone champions, +40% HP, +15% power, +50% gold | card #157; first guess |
| 2026-10-16 | Events, treasure rows, a shop scene with services and a campfire with one of three choices | cards #158 to #161, Slay the Spire style |
| 2026-10-16 | Two acts of 6 rows each: The Rotten Road (boss The Husk Lord) and The Ashen Deep (The Hollow King) | card #163; more acts and zones later |
| 2026-10-16 | The map gets a legend and dims stops the pick cannot lead to | card #162 (planning) |
| 2026-10-16 | Shop: no Heal service; each shop stocks 4 items, 2 charms, 2 gear (was the whole list) | user: the shop felt cluttered and Heal = a Salve for the same gold |
| 2026-10-17 | Zones get their own places, ground pieces and water, wind, drifting particles and critters | user: zones must feel alive and fit their theme (8.12) |
| 2026-10-15 | Lining digits everywhere; bold number font for HP, AP, gauge; slanted bold popups and damage numbers | user: the numbers' font felt cheap |
| 2026-10-15 | Hero portraits are painted pictures (made by the user with an AI image tool) turned into pixel art; big cards on the players screen, 64x64 faces everywhere else | user (#140, #141); a code-drawn try looked bad |
| 2026-10-15 | Attributes and Skills are buttons on each hero card; the info box only shows when needed | user: pressing LT / RT felt wrong, the box under the heroes was useless |
| 2026-10-15 | Tutorial on a practice fight where nobody can die, steps checked from fight events; offered once on the first New Run | user approved the six lessons (#131) |
| 2026-10-15 | Main menu cut to six rows: Online holds Host and Join, the tutorial is the first Practice card | user (#150) |
| 2026-10-15 | Tutorial: each hero lesson locks the menu to one glowing choice; no zone or map lesson (five lessons); the Skills lesson uses a skill without follow-ups (Taunt) | user play-test |
| 2026-10-16 | Every sound, song and loop offered against three free Openverse finds (CC0 / CC BY); 27 replaced, the rest kept | user asked; CC BY is fine with a credit on the credits screen |
| 2026-10-17 | Run exploits closed (Restock price rises, 2 Tonics per hero, a reset cannot heal, elites cannot be run from), small run bugs fixed, the Hollow King retuned to the hardest fight, the balance bot plays carefully | cards #175 to #178; the owner wants the game hard, so nothing here makes it easier (8.13) |
