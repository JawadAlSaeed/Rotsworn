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

1. The enemy picks one of its attacks and its targets (seeded RNG, integers only, card #189):
   - **Which attack.** Weighted random over its moves, minus the ones it may not use right now:
     a move is skipped while it is on **cooldown** (`cooldown_turns`, default 0: the enemy's next
     N turns) or after it was used `max_in_a_row` turns running (default 2, 0 = no limit), as long
     as another move is usable (a one-move enemy keeps using it). A move can also change weight
     with the situation: `finisher_below_percent` + `finisher_weight_percent` (times this weight
     while any standing hero is at or under that percent of max HP) and `low_hp_below_percent` +
     `low_hp_weight_percent` (the same when the enemy itself is that low). All default to off, so
     most attack files need no edit.
   - **Who.** Party-wide attacks target every living hero; each-in-turn attacks are unchanged. A
     single-target attack asks the enemy's `target_rule` (enemy data, with `target_bias_percent`).
     Every standing hero starts at weight 100: `RANDOM` leaves it there; `WOUNDED` adds missing-HP
     percent x bias; `LOWEST_HP` adds the bias to the hero with the least HP; `MARKED` adds it to
     heroes under Exposed or Marked; `AVOID_LAST` adds it to everyone but the hero it hit last.
     So nobody is ever safe and nothing is certain. Taunt still overrides the rule; downed and
     escaped heroes are never picked.
   - The enemy remembers its last 8 attacks, the cooldowns and its last target (in the snapshot,
     so online and restore agree). The choice is still shown honestly as the intent. In practice
     fights the intent event also carries the weights behind the pick (`odds`) so they can be
     tuned by eye; it never changes what happens.
   - **Marks (card #194).** A hit can leave a mark on the hero it lands on (2.7): a hero debuff
     or an AP drain. The intent says so: the `intent` event carries `marks` (one entry per hit, ""
     for a plain hit, only when some hit marks), the intent sign and the attack banner append
     `[ROT]`, `[BLIGHT]`, `[WEAK]` or `[AP DRAIN]`, and the marking hit's icon wears a small dot in
     that colour. A hit that cannot mark in this fight (hard-only marks in an ordinary fight)
     shows nothing, so the sign never lies either way.
   - Shipped rules: predators (hyenas, shades, flies, gnats) WOUNDED with a bias of 150 to 400;
     husks and bloats RANDOM or mild WOUNDED (100); toads AVOID_LAST; guards and bosses
     LOWEST_HP or WOUNDED (100 to 250), so a weak hero is in real danger.
2. A **banner** at the top shows the attack name and either the one targeted character's name or
   "WHOLE PARTY". An alert sound plays once when the attack starts (not per hit).
3. The attack plays in real time. **Only targeted characters defend.** Each hit is resolved per
   target (see 3). Targets are marked: red arrows over them until the enemy starts moving, and a
   red border on their party panels for the whole attack. During a single-target attack the other
   party members step back and dim, so the lunge lane and the target are clear.
4. **Charged Dooms** (card #195; Expedition 33's break meets Slay the Spire's big intent). A move
   with `charge_turns` above 0 is a **Doom**: a big party-wide string the enemy does not throw at
   once. Data on `EnemyAttackData`: `charge_turns`, `break_damage_percent` (share of the enemy's
   max HP), `cooldown_turns` (at least 1), `start_cooldown_turns` and the usual weight. The engine
   refuses a Doom that is not party-wide, has no break or no cooldown (`CombatSetup.validate`).
   - **Announced and counted down.** When the engine picks a Doom as the intent, the countdown
     starts at once: the `intent` event carries `charge_left` (= `charge_turns`), `charge_total`,
     `charge_damage` (0) and `break_hp`. `charge_turns` is the number of the enemy's turns from
     the announcement: each enemy turn counts it down; while it is still above 0 that turn is spent
     **gathering** (`doom_charging {left}`: no attack, no new pick, the intent stays); on the turn
     it reaches 0 the Doom **unleashes** (`doom_unleashed`, then the ordinary timed sequence, with
     the hard-fight rend and sweep kinds as in 2.4; a string with a sweep can never be countered).
     So 3 means two gathering turns and the strike on the third. The party acts in between.
   - **Break.** All HP the party takes off the enemy while the Doom stands announced or gathering
     counts, whoever or whatever deals it (skills, follow-ups, counters, bleed, items):
     `doom_progress {damage, break_hp}`. At `break_damage_percent` of its max HP the Doom is
     **broken** (`doom_broken`): the charge is cancelled, the Doom starts its cooldown as if used,
     the enemy is **staggered** (`stagger_changed {turns}`): it loses its next `stagger_turns`
     turns (tuning, 1) and takes `stagger_damage_taken_percent` (tuning, 50) more damage from every
     source until then (those `damage` events carry `staggered: true`). It announces a new move at
     once (never the Doom, which is cooling down); that announced move stands through the lost turn
     (no re-roll), then happens on its next turn. `stagger_changed {lost_turn: true}` marks each
     lost turn, `turns: 0` the end.
   - **Delays.** The countdown counts the enemy's turns, not time. Shield Bash, Earthshaker,
     Hamstring and Slow push the enemy's next turn back without touching `charge_left` or the
     damage already counted: they never reset or cancel the charge, they give the party more turns
     inside the window (the best answer short of breaking it). A Doom charge also survives phase
     two (the Doom is on both lists, the new pick is skipped while gathering), heroes going down or
     coming back (the intent re-targets, the countdown stays) and a snapshot or restore (`charge_attack`,
     `charge_left`, `charge_damage`, `staggered_turns` are in `Combatant.to_dict`). A downed enemy
     drops it.
   - **Pacing.** `start_cooldown_turns` 2 keeps a Doom out of the fight's first two picks (never in
     phase one's first turn), `cooldown_turns` 2 keeps it from coming back at once; with the shipped
     weights (about 40% of picks once ready) a boss announces one about every 4 to 6 of its own
     turns (measured over 40 seeds: Ash Warden 3.9, Gorged One 4.4, Mire Mother 4.8, Husk Lord 6.0,
     Hollow King 5.5; the first is announced for its third turn at the earliest). Measured by a bot that always focuses the gatherer and defends perfectly, over 30
     seeds: a Doom is broken about 7 times in 10 (the King's about 6); a bot that loses a
     share of its defences (heroes fall, so fewer strikes) breaks about 2 in 10. That is the intended price of the break: striking is the
     answer, but not every turn can be a strike.
   - **Bots.** The fight bots (test bot and the autoplay) aim their single-target skills at the
     enemy that is gathering a Doom, else at the first enemy. `AUTOPLAY_DOOMS announced= broken=
     unleashed=` is printed in the end lines of a fight that had one.
   - **Shown** (card #195, numbers in `combat_visuals.tres`, "Charged Dooms"): see 7.10.

### 2.4 Defensive actions

| Action | Window (default) | Works against | Result |
|---|---|---|---|
| Dodge | 250 ms | normal hits, sweeps | no damage, no reward |
| Parry | 150 ms | normal hits, rends | no damage, +AP (`ap_per_parry`, 1) |
| Jump  | 220 ms | ground hits | no damage, +AP (`ap_per_jump`, default 0) |

- Ground hits (shockwaves along the floor) can only be avoided by jumping. Dodging or parrying
  them fails. Jumping into a normal hit fails.
- **Forced-choice hits (card #187, 2026-10-17):** two more kinds make the three buttons a real
  choice, so dodging everything (the easy, safe button) stops working in the hard fights.
  - **Rend** (bone-coloured claw icon): only a **parry** stops it. A dodge or a jump is the wrong
    button: the hit lands, the hint says "MUST PARRY". A parried rend is perfect (it counts for
    counters like a parried normal hit, and as a parry for the mixed bonus).
  - **Sweep** (green crescent icon): only a **dodge** avoids it. A parry or a jump is the wrong
    button: the hit lands, "MUST DODGE". A sweep has no perfect answer, so **a string with a sweep
    in it can be survived but never countered** (2.5).
  - Same windows as the parry and the dodge (no window was changed). `Defense.build_windows` stays
    the one place that decides which button works against which kind; the judge reports the
    wrong button as WRONG_ACTION like a parry on a ground hit, the engine sanitises every result
    against the declared windows, and online the host's referee turns a wrong-button result into
    a hit taken (`DefenseArbiter.accept`).
  - **Where:** an attack's normal hit carries `forced_kind` (REND or SWEEP) and may carry
    `forced_feint`. They only show in **hard fights**: elite, guard and boss fights
    (`CombatSetup.forced_hits`, set from the encounter's flags) and against the deep variants
    (`EnemyData.forced_hits`, 2.16), which use them everywhere. Ordinary act-one fights and the
    tutorial play the same strings as plain normal hits without the extra feints. About one hit in
    four of the strings hard fights use is forced (a test keeps it between 15% and 40%); a forced
    hit always comes at least 300 ms after the hit before it, so there is time to see its colour
    and change buttons (test).
  - Bots: the perfect bot presses `Defense.best_outcome` (parry a rend, dodge a sweep); the
    average bot first reads a rend or sweep and misreads it (the other button, on time) with
    (100 - skill) / 2 percent chance, then lands it with its usual skill chance.
  - Tests: `tests/unit/test_hit_kinds_tempo.gd` (with the tempo of 8.3).
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

- A hit is **perfectly defended** by a Parry (normal hit or rend) or a Jump (ground hit). A sweep
  (dodge only, 2.4) has no perfect answer, so a hero whose prompts include a sweep cannot counter
  that attack (card #187).
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
- **Marks: hero debuffs and AP drain (card #194, review combat-rules-ai #3).** Failing to defend
  used to cost only HP. Now an enemy hit can also carry a mark, set on the hit in the attack's
  data (`AttackHitData.on_hit_status`, `on_hit_status_turns`, `on_hit_ap_drain`). It lands only
  when that hit is **undefended** (outcome NONE: no dodge, parry or jump that answers it; a wrong
  button on a rend, sweep or ground hit still counts as undefended) **and the hero survives it**
  (a hero downed by the hit gets nothing). A successful defence prevents it, so defence has a
  second stake. It is applied in the engine's defend-prompt resolution, after the
  `prompt_resolved` event, with the existing `_add_status` (a `status_changed` event) and an
  `ap_changed` event with reason `drain`. `on_hit_hard_only` (default off; every shipped mark sets
  it) holds the mark back unless the fight is hard (an elite, guard or boss fight, or an enemy
  with `forced_hits`, like `forced_kind`), so one attack file serves the ordinary fight as plain
  damage and the hard one as damage plus a mark. Nothing marks in the tutorial fight or in
  ordinary first-zone fights.

  | Status | Effect (numbers in `tuning.tres`) | Ends |
  |---|---|---|
  | Rotting (`rotting`) | at the start of each of the hero's turns they lose `rotting_percent` (6) of max HP, never below 1 HP from rot alone (damage cause `rotting`) | `on_hit_status_turns` of their turns |
  | Blighted (`blighted`) | healing they receive is cut by `blighted_heal_cut_percent` (50), at least 1 HP when it heals at all; applies to every heal (skills, Renew, items, gear) | same |
  | Weakened (`weakened`) | their power is cut by `weakened_power_cut_percent` (25): skills, follow-ups, counters, team counters and the damage of a Bleeding they put on an enemy | same |

  They count down at the end of the holder's turns like Slowed, show their turns left on the
  hero's panel (a short coloured word: ROT 2, BLIGHT 2, WEAK 2) and a popup when they land. **They
  stack by refreshing, never by multiplying:** a second hit sets the turns to the longer of the
  two. A downed hero loses them all. Statuses are built fresh with each fight (a fight starts
  from `CombatSetup`, and the run saves only HP), so the end of a fight and a campfire Rest
  clear them without any code. The AP drain takes `on_hit_ap_drain` AP (never below 0) with a
  `-N AP` popup.

  **Cleanse.** `AbilityData.cleanse_count` (+ `press_cleanse_count` on an all-perfect press)
  removes that many debuffs from each ally a healing skill heals, **before** the heal lands, in
  the order rotting, blighted, weakened (so lifting Blight frees that very heal). Decision: Mend
  and Sanctuary lift **one** on a normal press and **all three** on a perfect one, so Cass's
  timing matters; Renew does not cleanse (it is a slow heal). Items: `ItemData.cleanse_count`;
  the Salve lifts one in a fight (phase 19 added the Antidote and Holy Water, 2.17). The autoplay bot
  prefers a cleansing skill when a hero is marked, and aims it at a marked hero.

  Shipped marks (one marking hit per string at most): Bile Spit and Bile Flood's last bolt
  (Blighted 2), Rot Combo's last hit (Rotting 2), Rot Cascade's last hit (Rotting 3, the Hollow
  King), Pounce and Pack Bite's last hit (Weakened 2), Shadow Bolts' last bolt (1 AP drain).
  `tools/make_attack.py` writes these with the hit options `mark`, `mark_turns`, `ap_drain`,
  `hard_only`.

  **Phase 19 changed the rule and added five marks: see 2.17.** Since then every monster has one
  marking move in an ordinary fight (not only in hard fights), held back in a run's first zone.

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
| Flurry | one | 3 | normal 900 / 1200 / 1650 (45% each) | 300 then a held 450 ms; hard fights: the first swipe feints, the last is a rend |
| Lingering Claw | one | 2 | normal 1600 (130%) | feint: false start, hold, real lunge; no training ring |
| Ground Slam | party | 1 | ground 1100 (80%) | shockwave front parallel to the party, reaches all at once |
| Rot Combo | party | 1 | normal 900, normal 1200, ground 1700, normal 2300 (35% each) | 500+ ms either side of the ground hit (jump airtime) |

Data rules (checked by a test): impact times increase; normal hits at least 250 ms apart; at
least 450 ms between a ground hit and its neighbours; mid-string parry hit-stop at least 30 ms
under the parry window's early part. Card #187 adds: no string of three or more hits of one kind
has all its gaps equal (review combat-feel #4: a steady tap rhythm beat them), a forced hit is at
least 300 ms after the hit before it, and a feint inside a string at least 550 ms after the hit
before it (its false start would eat that hit's contact pose); a feint on a first hit has the whole
wind-up. Re-authored 2026-10-17: Buzz, Sting String, Swarm Sweep, Swarm Round, Pack Bite, Strafe,
Buzz Dive, Flurry, Hop Hop Hop, Quake Hop, Bile Flood, Blood Rush, Frenzy, Crown Sweep, Rot Cascade
and Kingsfall (its first three hits) now have uneven gaps.

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
| Mend | 1 | heal one ally 30% of their max HP, lift one hero debuff (2.7) | 45%, lift all |
| Reveal | 1 | 60% hit, enemy becomes Exposed | +1 AP |
| Pass the Torch | 2 | give one ally 2 AP | 3 AP |
| Hasten | 2 | one ally's next turn comes sooner | sooner still |
| Revive | 3 | revive a downed ally at 25% HP | 50% HP |

Intended combo: Cass Reveals, Brin Rends; Alder Taunts, parries, then cashes in with Payback.

**Cass's spells shoot after the press (card #166, 2026-10-18, like Expedition 33).** Her ranged
skills (Reveal, Smite: every skill with a `projectile`) used to launch the bolt
`projectile_flight_ms` before the ring closed, so it was already landing when she pressed. Now the
bolt leaves her staff at the moment of the press and flies `projectile_flight_ms` (320), and the
strike lands with it: sparks, the damage numbers, the target's hit and a perfect press's hit-stop
wait for the landing. Her staff-thrust frames start with the release. The press feedback (the
sound, GOOD or PERFECT and the timing readout) still shows at the press.
- A press that missed is still a shot: an early press that used the ring up releases at that
  press; a press that never came releases at the end of the press window (its moment plus the
  late edge plus the lag compensation, `SpellShot.window_end_us`), so a skill never stalls. It
  lands as a miss (50%).
- Visual order only. The windows, the judge, the engine's damage and every event are unchanged;
  the events are simply shown when the bolt lands (`SpellShot`, pure, unit-tested). The latest a
  bolt can land (end of window plus flight, 520 ms after the ring's moment) is before the allies'
  follow-up moment (`follow_up_delay_ms` 700), so the order read is: press, bolt, landing, allies
  strike (a test checks it for the shipped spells).
- Online: a remote player's good press launches the bolt when its result arrives here, and a
  press that never came when the other machine reports the miss, so both screens show the same
  order a network delay apart; the event batch waits for the landing like the local one.

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
| Blight Bloat | Bloat | bile yellow | Bile Flood: one, three bile globs 950, 1300, 1750 (45% each) |
| Blood Gnats | Gnat Swarm | blood red | Blood Rush: each in turn, five stings 800 (a feint), 1100, 1350, 1800, 2100 (a sweep) (30% each) |
| Hollow Shade | Shade | ice blue | Bolt Storm: party, shade bolts 1000, 1500 (45% each) |
| Bone Hyena | Rot Hyena | bone pale, red eyes | Frenzy: each in turn, four bites 800, 1100, 1800 (a feinting rend), 2050 (40% each) |
| Plague Fly | Carrion Fly | plague violet | Plague Spit: party, one bile glob each 1200 (60%) |
| Elder Toad | Mire Toad | dark bog brown, red eyes | Quake Hop: party, rocks 1100, wave 1700, rocks 2250 (50% each) |

- Every variant has `forced_hits` on (card #187, 2.4): its rends and sweeps and forced feints show in
  every fight it is in, so the second half of a run reads harder.
- Deep fights: `EncounterData.deep` names a fight's deep version (`deep_<id>`, the same fight made of
  variants). In a run, from map row `tuning.run_deep_row` (4, the second half of the 7 rows) on, a
  zone's roaming enemies hold their deep fights (`RunState.is_deep()`, `ZoneController.configure(...,
  deep)`): the roamer shows the variant and the fight is the deep one. Practice fights list them
  too. Every fight a zone holds has one (test). Phase 13 (card #105) adds stat scaling by depth on
  top.
- Balance check (average-player bot at level 1 with no gear): 3 wins in 5 deep fights. A run
  reaches them leveled and geared.

### 2.17 Monsters and effects (phase 19, cards #245, #246, #252 to #264, built 2026-10-19)

The user asked for small fries, ranged-only and large monsters, status effects with one marking hit
per monster, ways to cleanse them, and up to 3 monsters a fight; every recommended option was picked
(decision log).

**Five new hero marks** (`Status`, numbers in `tuning.tres` "Skill statuses"), next to Rot, Blight,
Weak and the AP drain (2.7). They land like the others: an undefended hit on a hero who survives it.

| Mark | Word | Effect | Who leaves it |
|---|---|---|---|
| Burning (`burning`) | BURN | at the start of each of the hero's turns they lose `burning_percent` (10) of max HP, never below 1 HP from fire alone (cause `burning`); 2 turns | Ember Slinger's Firepot; hard fights: Ashen Husk's Cinder Hail, the Ash Warden's Ashfall, the Cinder Slinger's Fire Rain |
| Shocked (`shocked`) | SHOCK | every timing window of the hero (defence, skill presses, follow-ups) is `shocked_window_percent` (65) of its size (`CombatEngine._windows_for`; the judge reads the prompt's windows, so nothing else changes) | Marsh Lantern's Zig-Zag, the Gnat Swarm's Buzz |
| Slowed (`slowed`) | SLOWED | the hero's speed is `slow_speed_percent` of normal (Hamstring's slow, now also a hero mark) | Mire Toad's Mud Spit; hard fights: Hollow Shade's Bolt Storm, Mire Mother's Brood Tide |
| Dazed (`dazed`) | DAZE | the hero's next turn passes (`turn_lost {actor, status}`); it ends with that turn | the Barrow Brute's Barrow Slam, a rend in every fight, so a parry saves the turn (1 turn) |
| Hushed (`hushed`) | HUSH | no skills: only the basic attack, items, Run and the team ultimate (`CombatEngine.is_hushed_out`; the menu says why) | Rot Priest's Hush Word |

- Cleanse order (`Status.DEBUFFS`): Daze, Hush, Burn, Rot, Blight, Shock, Slow, Weak (the costliest
  first; Rot still before Blight). `Status.CLEANSE_ALL` (9) lifts all; Mend and Sanctuary lift one,
  and every one on a perfect press (`press_cleanse_count` 8).
- **One marking move per monster** (card #253; a test keeps it): Husk Rot Combo (Rot), Bloat Bile
  Spit (Blight), Gnat Swarm Buzz (Shock), Shade Shadow Bolts (AP drain), Carrion Fly Maggot Spit
  (Rot), Rot Hyena Pack Bite (Weak), Mire Toad Mud Spit (Slow), and the new monsters below. Hard
  fights may add more (`on_hit_hard_only` moves, as before). At most one marking hit per attack.
- **Where:** every fight except a run's first zone (`CombatSetup.allow_marks`, set by
  `RunState.fight_setup` from depth: off at depth 0), so the first zone teaches the hits alone. Hard
  fights (elite, guard, boss, deep variants) mark everywhere. Practice fights mark; the tutorial's
  enemy only uses each lesson's attack, so only its marks lesson shows one.
- **Ward** (`warded`, WARD): no mark (debuff or AP drain) lands while it lasts. **Shielded**
  (`shielded`, SHIELD) on a monster: it takes `shielded_damage_cut_percent` (40) less damage.

**Lifting marks** (card #254): Cass's **Purify** (Mending branch, 2 AP: lifts every mark from one
ally and wards them 2 turns, 3 on a perfect press; a cleanse no longer needs a heal), the
**Antidote** (fight item, `ItemData.Effect.CLEANSE_ONE`: every mark off one hero; 20 gold, common)
and **Holy Water** (`CLEANSE_ALL`: every mark off the whole party and a 10% heal; 50 gold, rare),
both in the shop and found in zones. The bot uses a cleansing item only when no cleansing skill is
ready. **Relics against marks** (card #263, `GearData.Effect` and `Passive`): Wardstone (Warded for
the first 2 turns of every fight), Bitter Root (marks last 1 turn less, never under 1), Cleansing
Bell (each parry lifts one mark); dropped by the new monsters.

**Six new monsters** (cards #255 to #260; art by `tools/art_kit/assets/enemy_<name>.py` on the
shared `kit/monster.py`, deep twins recoloured by `enemy_variants`, attacks in `tools/make_attack.py`;
voices borrowed until real ones are recorded):

| Monster | Role | Speed | HP | Power | Moves (mark) | Lives in | Deep twin (own move) |
|---|---|---|---|---|---|---|---|
| Rot Rat | small fry, always in threes | 230 | 35% | 45% | Nibble, Gnaw (4 bites, the last Rots), Scurry (each in turn), Rat Tide | Rotten Hollow, Sunken Bog, with the Slinger | Grave Rat (Rat Frenzy) |
| Ember Slinger | ranged only: every hit is thrown | 120 | 75% | 95% | Pitch Throw, Ember Volley, Firepot (party, Burn), Scatter Shot | Ashen Ruins, the Ash Warden's guard | Cinder Slinger (Fire Rain) |
| Barrow Brute | large, slow, hits hard | 55 | 300% | 190% | Grave Maul, Barrow Slam (a rend everywhere, Daze), Earth Breaker (rocks), Wide Swing (a sweep everywhere), Two Blows | Ashen Ruins, alone or with one Rot Rat | Tomb Brute (Grave Quake) |
| Marsh Lantern | ranged caster, floats | 150 | 70% | 85% | Spark Bolt, Zig-Zag (Shock), Arc Chain (each in turn), Static Burst | Sunken Bog, the Mire Mother's guard | Storm Lantern (Thunderhead) |
| Rot Priest | helper: heals and shields other monsters | 110 | 90% | 70% | Censer Swing, Hush Word (Hush), Mend Rot (heals 25%), Bone Ward (Shield 2 turns) | Rotten Hollow, Ashen Ruins, the Gorged One's guard | Hollow Priest (Black Litany) |
| Pus Tick | bomb | 100 | 45% | 100% | Latch, Burst (announced like a Doom: 3 turns, a party-wide ground hit that Blights, then the tick is spent; break 50%) | Sunken Bog, Rotten Hollow | Bile Tick (Bile Spit) |

- **Support moves** (card #259): `EnemyAttackData.support` HEAL or SHIELD, `target_mode` ALLY, no
  hits. A heal is only a choice while a monster (itself included) is at or under
  `support_below_percent` (75) of its max HP; a shield while one has none. The intent names the
  monster it will help; on its turn the engine sends `enemy_support {enemy, attack, name, target,
  support}`, then `healed` or `status_changed`, and the turn passes (no timed sequence). The screen
  shows its name in the banner with the helped one ("> RAT A"), a wind-up and a glow.
- **The burst** (card #260): a Doom (2.3) with `self_destruct`: after its attack (and any counter)
  the attacker falls (`self_destructed {enemy, attack}`, then `downed`). Breaking it staggers the
  tick as usual; killing it first is the clean answer.

**Fights of three** (card #245): 3 stays the most. `EncounterData.enemy_hp_percent` spreads a fight's
HP (80 for most trios, 90 when small fry or two ticks are in it; a run multiplies its depth scaling
on top). New fights: Rot Rat Pack, Pus Tick and Rotten Husk, Rot Priest's Coven, Husk Gnats and
Fly, Marsh Lantern and Mire Toad, Lantern Swarm, Pus Tick Nest, Ember Slinger and Rotten Husk,
Slinger and Rats, Barrow Brute, Barrow Brute and Rot Rat, Rot Priest and Hyenas, each with its deep
version; the zones' roamer pools and the acts' ambushes hold them. Each guard brings a third
monster (the Gorged One a Rot Priest, the Mire Mother a Marsh Lantern, the Ash Warden an Ember
Slinger; `enemy_hp_percent` 90). Brin's **Fang Storm** and Cass's **Radiance** hit every enemy
(only Alder's Earthshaker did); a spell on every enemy sends one bolt to each.

**Tall monsters stand at the back** (user, after testing: "keep the fat monsters at the back, if
someone is behind he is unseeable"). The screen puts each monster on a stage spot by its height
(`CombatView.enemy_height`: feet to the top of its idle frame's body): the tallest on the spot
farthest from the camera, the smallest nearest, so a big body never hides a smaller one or its
attack. Monsters of one height keep their own spots. Only the picture changes; ids and targets
do not. The spots themselves are a diagonal line, the heroes' mirror image (user: "the same format as
the heroes"; `combat_visuals.tres` `enemy_positions`: middle (2.9, 0, 0) first for a lone monster,
then front (3.7, 0, 1.5), then back (2.1, 0, -1.5); it was a "<" with two spots in one line).

**On screen** (card #262): the hero panels draw each mark (and the ward) as its 12-pixel icon with
the turns left (`HudStyle.mark_badges`, `mark_icon`; icons by `tools/art_kit/assets/ui_marks.py`
in `assets/sprites/ui/mark_<id>.png`), and the Glossary uses the same icons. Daze shows DAZED over
the hero as the turn passes; the Tick's burst flashes and shakes.

**Tutorial** (card #264): lesson 6 "Marks" (defend Rot Combo's dotted last hit; goal
`mark_defended`), then "Lift a mark" (Alder starts with Rot, Cass Mends him; goal `cleanse`; the
step fields `mark_hero`, `mark_status` stage the mark through a practice command). Relics and
Echoes are lesson 8 (phase 22 put a First Strike card in as lesson 7, card #291).

### 2.18 Defence streak (phase 24, card #300)

The party's **perfect defences in a row across a whole fight**: a perfect parry (a normal or rend
hit) or a perfect jump (a ground hit) adds one; a dodge keeps the streak but adds nothing (a dodge is
never perfect, and a sweep has no perfect answer); a hit taken ends it. Every
`tuning.defence_streak_step` (5) in a row fills the team gauge by `tuning.defence_streak_gauge` (10;
0 turns the reward off). Gauge, not gold or XP: it pays inside the fight, feeds the Team Ultimate and
carries over in a run like the rest of the gauge, and it does not overlap #283's rewards (Flawless
is a guard or elite with no hit taken: one more spoils choice; the run end's defence rows only count).

- **Counted in the engine** (`CombatEngine._count_streak`, from each resolved defend prompt in
  prompt order), so every machine online counts the same streak and pays the same gauge. Event
  `defence_streak {value, best, milestone, lost}` (a step's `team_gauge` event follows it); the
  engine's `defence_streak` and `best_defence_streak` are in snapshots (an older snapshot reads 0)
  and the resume events; the mirror follows them (and they are in its projection).
- **On screen**: a gold chip over the team gauge card, a shield and "STREAK n", from
  `combat_visuals.streak_show_from` (3) in a row. Each new one pops it a little, a step pops it more,
  flashes it, plays `streak_swell` (a rising film-score swell, picked by ear) and buzzes every pad
  (7.14). A hit that ends a shown streak turns the chip red and fades it (`streak_lost_ms`).
- **The music swells**: each step reached lifts the song `streak_music_lift_db` (1.5 dB, at most
  `streak_music_lift_max_db` 4.5) on top of the attack dip (`Audio.lift_music`), until a hit ends a
  streak of a step or more; a new song starts without it.
- The lift follows the steps reached on every streak event, so a friend who rejoins mid-streak hears
  the same swell; a fight's swell and attack dip end with it (a restart keeps the same song).
- A won run fight's end screen shows the best streak ("Streak n", the gauge icon) once it reached
  `streak_show_from`.
- The old per-attack `_parry_streak` (the parry ring's climbing pitch, card #93) is unchanged.

Tests: `tests/unit/test_defence_streak.gd`.

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
- **One value per kind of input (card #204).** A keyboard and a wireless pad lag differently (easily
  20 to 40 ms, a third to half of the 70 ms perfect window), so the measurement is saved per kind:
  `latency_keyboard_ms` and `latency_pad_ms` in `user://settings.cfg` (`PlayerSettings.INPUT_KEYBOARD`
  / `INPUT_PAD`; a device code of 0 and up is a pad, the keyboard, the mouse and the autoplay bot
  are "keyboard"). The first press in the calibration decides which kind is being measured, the
  panel says so ("Measuring: controller") and saves only that kind; presses from the other kind
  are ignored. A value saved before the kinds existed (`latency_compensation_ms`) still counts for
  both until that kind is calibrated itself. A kind never calibrated uses the tuning default.
  Judging: a sequence's `JudgeSet` is built with the smaller of the two values as its base; each
  press passes the extra lag of the device that made it (`extra_latency_ms`: its value minus the
  base, never negative) and is judged that much earlier, exactly as if the judge had been built
  with that device's own value. `DefenseJudge` is unchanged, the base only decides when an
  unanswered hit expires (never earlier than the laggier device needs), and the enemy's contact
  hold and the window marks use the base. In co-op each player's presses use their own pad's value
  (roster device), in solo whichever device actually pressed. Online, each machine uses its own
  settings for its own players.
- **Offered once to a new player (card #204).** Settings > Game > Lag calibration was the only way
  in and nothing told anyone. The first New Run that does not start the tutorial asks "Calibrate
  your timing?" (about 15 seconds; "recommended for wireless pads and TVs, which add lag"; Not now
  is selected first, Calibrate now runs `CalibrationScreen`, the calibration panel on its own
  screen) and then goes on to the players screen either way. `PlayerSettings.calibration_offered`
  remembers it was asked (once only, in `[game]` beside `tutorial_offered`); a player who already
  calibrated is never asked (`calibration_offer_due`). Never in autoplay, never online (hosting and
  joining do not pass through New Run). **Order with the tutorial offer:** one question per New
  Run press. Tutorial first (7.8); answering "Start the run" goes straight on to the calibration
  offer; answering "Play the tutorial" leaves the calibration offer for the next New Run, so the
  two never stack in one go. `--screen=calibration_offer` shows the question over the main menu
  without using up the once-only flag.

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
- **Presses during a success freeze (parry, jump, perfect skill press) are ignored only for the
  player who owns the freeze** (no judgement, no lockout): that is their own double tap. Card #180
  (bug): the clock is shared, so one player's parry used to swallow a teammate's on-time press
  inside the freeze. `FreezeLedger` (pure, tested) records who owns each freeze; a press by anyone
  else is judged at the time it would have had without the freeze (attack time plus the real time
  since the freeze began), the same trick as the hurt freeze. The hurt freeze on an attack's last
  hit has no owner: every prompt is already resolved, so such a press can only be a LATE report.
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
- **Every defence press shows its move** (card #309), so the player always sees it registered. A
  press that defends nothing (EARLY, LATE, the wrong button, locked out, nothing left to defend,
  or pressed while the banner is still up in the lead-in) plays the move anyway on that player's
  living targeted heroes: a jump rises for half of `jump_airtime_ms` and comes back down, a dodge
  slides out and back over `dodge_pose_min_ms`, a parry raises the guard over half of
  `whiff_pose_ms` and holds it (never its clang frames). It is only a pose on that machine:
  judging, the whiff lockout, the results sent to the engine and other machines never see it (a
  lead-in press is still not judged at all). In an each-in-turn attack (3.11) it moves only the
  hero its hit strikes, the way a good press does: the hit the judge measured it against, or for a
  press with no hit (locked out, nothing left, the lead-in) the hit aimed at that player's heroes
  then (the first still open, else the last); flash and readout go on the same hero (code review).
- A press never cuts short a defence, a flinch or an earlier press's move that is still playing (a
  double tap keeps the jumper in the air); it still flashes, sounds and shows its readout. A
  defended press does replace a missed move, and a hit that lands always replaces whatever plays:
  the hit reaction wins. Either way the new pose starts from where the body is: a jump carries on
  up from that height, a dodge slides on out from where it was, and anything else (a flinch, a
  parry) comes down and back from there, so nothing snaps to the floor.
- A press made during a hit-stop is judged at the time it would have had without the freeze (3.3,
  card #180), but its move starts at the attack time on screen, frozen with everything else, so a
  press in a friend's parry freeze never cuts short a flinch that is still showing (code review).
- A hero with nothing left to defend in the attack gets no move that would still be playing when
  the attack hands back (its end plus `attack_recover_ms`, or the last impact plus
  `counter_delay_ms` before a counter; the sooner of the two until the engine has answered):
  nothing would finish it, so mashing at the end would leave the hero snapping to idle in mid-air
  or mid-slide, or the counter dashing from there (code review). A hero whose hit is still to come
  always gets it: the hit or a defence replaces it.
- The lock icon sits under the defenders' feet, clear of the readouts.
- Feedback comes from the local judge at press time, never from engine events (so it stays
  instant online): "PARRY" / "DODGE" / "JUMP" plus the offset ("+12"), whiffs as "EARLY -130"
  (blue) or "LATE +70" (red), wrong button as "JUMP!" / "PARRY!" hints (orange; "MUST PARRY" on a
  rend, "MUST DODGE" on a sweep, card #187), "MISS" when a hit
  lands with no press, a lock icon during lockout, a muted click for a locked press.
- Distinct sounds: parry clang (brighter on the final hit), dodge whoosh, jump thump, hit taken,
  whiff swish, locked click.
- Parry sparks burst on the defender's front edge (`spark_toward_enemy`). Screen shake is stronger
  on a parry than on a hit taken, and a heavy hit shakes more than a graze (trauma values: parry
  0.4, final parry 0.7, hit taken 0.3, heavy hit 0.7; see 7.3). A dodge only nudges (0.1) and
  flashes its hero faintly cool (card #179).

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
- Timing readout after each press (`show_timing_feedback`, F1 then T). Practice fights only since
  phase 22 (7.13): the real game shows the word alone.
- Wind-up crouch (`show_windup_crouch`, F1 then C): the enemy crouches as its wind-up glow
  builds (`windup_squash_percent` at full glow) and springs out of it as the lunge or slam starts.
- Hit markers (`show_hit_markers`, off since phase 6, F1 then H in practice), see 3.8. The floor
  warning under a ground hit always shows.
- G, T, L, H and C are session toggles (not saved); the tuning values are their starting state.
  **They only work in practice fights** (F1 then the letter), like the training ring: a run fight
  is the real game and F1 there only opens the stats (godot-code-health #6, 2026-10-17).
- **Flashes setting** (Settings > Game, card #185): Full (default), Reduced or Off. It scales every
  full-screen flash (counter, ultimate, hero down, phase change, kills) and every flash on a
  fighter (white parry and hit flashes, the telegraph flash in strings). Reduced keeps
  `flash_reduced_screen_percent` (40) of a screen flash and `flash_reduced_fighter_percent` (50)
  of a fighter flash; Off drops screen flashes entirely and leaves a faint
  `flash_off_fighter_percent` (15) tint so a hit still reads. Saved per machine. It only softens
  light, never timing: the telegraph is still there.

### 3.8 Reading attacks (approved 2026-10-12, card #44)

Defence is the star, so every hit must be readable before and while it comes. Nothing here
gives a beat to press on: the press is still timed from the enemy's motion (the user picked
"icons only" over a rhythm-game strip with a moving line).

- **One colour per defence:** red-orange (`telegraph_flash_color`, `normal_hit_color`) = a normal
  hit, parry or dodge it; purple (`ground_hit_color`) = a ground hit, jump it; bone
  (`rend_hit_color`, near the PARRY readout's yellow, never pure white) = a rend, parry only;
  sickly green (`sweep_hit_color`, near the DODGE readout's green) = a sweep, dodge only (card
  #187); white = you parried. The wind-up glow and the telegraph flash before a hit, its icon
  (claw marks for a rend, a crescent for a sweep, `hit_rend.png` / `hit_sweep.png` drawn by the art
  kit's `fx_ui`), its marker and the training ring all take the hit's colour
  (`CombatVisuals.kind_color`); the marker and the ring add the one button's name ("JUMP",
  "PARRY", "DODGE"). Ground hits also get the purple floor warning.
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
- **Ranged indicator (card #165, 2026-10-18):** a thrown hit shows which hero it flies at and when
  it arrives. On each hero the projectile is aimed at, four corner brackets close in from
  `ranged_aim_start_px` to `ranged_aim_end_px` (half size) and meet exactly at the hit's declared
  impact, the time the defence is judged on (`RangedAim.progress`, 0 at the throw, 1 at impact; a
  test checks every shipped ranged hit against its prompts), and a dashed path (the flight arc,
  `ranged_aim_path_points` samples) runs from the projectile to the hero, shrinking as it flies.
  It is brackets, not a circle, so it is never taken for a press ring. It shows
  `ranged_aim_lead_ms` (450) before the throw, so the wind-up already says who gets it, fades in and
  out over `ranged_aim_fade_ms`, takes the hit's kind colour like the melee markers (3.8: red-orange
  normal, bone rend, green sweep; a rend or a sweep names its button under the brackets,
  `ranged_aim_label`), and stays on the hero until the hit is decided (never gone before the
  impact). When the brackets lock it fills faintly and brightens for `ranged_aim_pulse_ms`, scaled
  by the Flashes setting (none with Flashes off; Reduced shows the Reduced share). Party-wide throws
  get one per hero; a hero who goes down loses theirs. It is on in run fights too
  (`tuning.show_ranged_aim`, default on, unlike the hit markers): it is the projectile's own flight
  made readable, not extra pre-information, so `hide_intent_after_first_hit` does not hide it.
  Pure function of attack time, so hit-stop freezes it with the projectile; nothing goes to the
  engine. `RangedAimLayer` draws it in the HUD; the runner feeds it every frame.
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

### 3.12 Run up and swing (phase 23, card #244)

- An enemy with `EnemyData.runs_up` runs to its target before an attack that opens with a melee
  hit (a normal hit, rend or sweep that throws nothing; `EnemyChoreography.runs_up`). An attack
  that opens with a slam or a throw plays from home as before. First the Rotten Husk and the
  Hollow King (the owner played the Husk: "good", 2026-10-21), then every claw, bite and blade
  enemy: husks (Ashen Husk, Husk Lord), hyenas, rats, shades (Hollow Shade, Ash Warden), barrow
  and tomb brutes, gnats, flies, bloats (Blight Bloat, Gorged One), ticks and priests (censer).
  Slingers and lanterns only throw; toads stay home (the tongue reaches from there).
- The run is added to the lead-in: banner and camera as before (`attack_lead_in_ms`), then the run
  over tuning `run_up_ms` (450), then the attack clock starts. Nothing is judged during it, so the
  wind-up and every window stay exactly as authored. The online host's arbiter waits the same
  longer lead-in (`EnemyChoreography.lead_in_ms`; every machine decides the same from the same
  data).
- It runs with its `chase` loop (`run_up_cycle_ms`) and stops `swing_step` world units (1.0) short
  of the contact point (`near`, a share of the way). Each hit winds up there and steps the rest of
  the way in as it swings, reaching contact exactly at impact as before. Through a string it stays
  close: the recoil never takes it further back than `near`; slams and throws in the string play
  where it stands. After the last hit it goes home over `return_ms` like any attacker (a longer run
  home outlasted the hand-back, so a counter dashed into an enemy still on its way; code review).
- **Wind-up attacks charge in** (card #310, owner playtest 2026-10-23: the Bloat walked right up to
  the hero and only then wound up its slam; the wind-up already warns the player). When the first
  hit winds up at least tuning `charge_windup_min_ms` (850) as authored (its `impact_ms` minus
  `approach_ms`, so the attack tempo and a hard fight's feint never change the choice), the
  attacker does not run up (`EnemyChoreography.charges`; `runs_up` is false, so the lead-in is the
  plain `attack_lead_in_ms` and the online arbiter waits the same). The line lives in tuning, not
  combat_visuals: it decides whether `run_up_ms` is added to the lead-in, a pacing number (code
  review). It winds up where it stands, at home (combat_visuals `charge_windup_share`, 0; above 0
  it would step out that share of the way to the contact point during the coil, gliding while its
  coil cells play, so the review set it to 0 as the owner asked), and its first lunge is the
  charge: from there all the way in over the hit's own `approach_ms`, reaching contact exactly at
  impact. The attack clock, every impact time and every window are unchanged; a test
  checks every beat of every shipped charge against the run-up version (only where the enemy stands
  differs). After the first charge it stays close through the string as above and goes home after
  the last hit. Charging today: the bloats' Belly Slam and Crush, the brutes' Maul, Slam, Sweep and
  Double, the hyenas' Pounce and Cackle, the flies' Dive, the husks' Lingering Claw and the shades'
  Delayed Rake. Quicker openers (claw swipes, bites, strings, the King's chop) keep the run-up.
- The swing uses the enemy's `lunge` and `contact` cells. The Hollow King, the one sword fighter,
  got a real swing (owner: "enemies who have swords ... need to be close and to have a swing
  animation"; picked option A of three drafts, 2026-10-22): an overhead chop. The wind-up hoists
  the cleaver high with both fists, the swing arcs it over the top, the hit (contact[0]) chops down
  at the hero's chest with both feet planted and a thin smear arc off the tip, then the blade drives
  on down. His skull face and the blade's green seam stay in every cell. Odd hits of a string use
  the same chop (his `lunge_b` / `contact_b` are gone). Other monsters keep their cells for now.
- **Heroes** (owner: "make Brin and Alder run all the way up for their attacks", 2026-10-22): a
  hero with `CharacterData.runs_up` (Brin, Alder; not Cass, who casts from her spot) runs all the
  way to `hero_swing_step` (1.0) short of the strike point at the start of a melee skill on
  enemies, over tuning `hero_run_up_ms` (380) with the `run` clip looping every
  `hero_run_cycle_ms` (it falls back to `walk_side`, then the stance). Both have their own 8-cell
  `run` (art kit): a longer stride and twice the walk's lean, Brin in his reverse-grip high and low,
  Alder with the shield on his forearm and the far arm pumping. The skill clock starts at
  once as before; the run ends before the earliest wind-up frames of any skill (a test checks it),
  so it never hides them. Each hit steps in from there and back as before (`skill_lunge_ms`). In the
  Team Ultimate each runner aims at their own spread spot (card #65), so nobody hides another. At
  the end the strikers who ran up hop home (`follow_up_hop_height`, over `action_return_ms`, easing
  out so they have landed before an enemy attack can start); a follow-up ally hops home on their own.
  Anyone else, and spells, keep `skill_approach_share` (0.55) or stay put. Counters and the plain
  party action keep their quick dash.

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
all prompts done, counters follow), `counter`, `enemy_phase` (a boss's phase two), `doom_charging`,
`doom_progress`, `doom_broken`, `doom_unleashed`, `stagger_changed` (Charged Dooms, 2.3), `turn_ended`,
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
`elite_path` (elite fights, card #192; empty today, so elites use the fight song until a song is
dropped in and named there) and `boss_rage_path` (the boss fight switches to it on the boss's phase change), `victory_path` and
`defeat_path` (cards #109, #126: a won or lost fight's end screen, `end_song_delay_ms` after the
jingle, and RUN CLEARED / RUN OVER; user picks 2026-10-15: "Victory Theme for RPG" by cynicmusic
and "Lament for a Warrior's Soul" by RandomMind, which the Openverse pass replaced with "Sad Piano"
by tyops; empty keeps the old songs). The run map song is
"Treasure Hunter" by TAD (card #110, user pick 2026-10-15, was "Mystical Theme"). The `Audio`
autoload loops the song on its own player (OGG imports loop, `oggvorbisstr` default in
project.godot); a place naming the song already playing lets it go on. A new song crossfades in: it fades in over `fade_in_ms` while the old one fades
out over `fade_out_ms` (two players, music.tres; user request 2026-10-13). The `Audio` autoload
remembers how far into a song (and into a zone ambience loop) it was when something replaced it;
coming back from a fight, the zone asks to `resume` and the song and the ambience go on from there
with the usual crossfade instead of restarting at 0:00 (card #192). While an enemy attack plays
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

Phase 24 sounds (2026-10-22, `candidates/phase24.json` and `ambience_candidates.json`, picker
https://claude.ai/artifact/Xktz3S4EN2WygSpLdq3XCE, built by `make_picker.py --group=phase24
--with-ambience=ambience_rain,ambience_wind`): the Rot Rat and Grave Rat barked with the hyena's
voice, so they got `voice_rat` (card #298); `thunder` for storms and `streak_swell` for the defence
streak (8.20, 2.18); the rain and wind loops (`ambience_kit.py final --only=...` builds just those and
changes only their credit lines). User picks: a real rat squeak, a thunder crack, a film-score swell,
forest rain, wind gusts (all CC0).

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
and the Sunken Bog loop (swamp frogs); the rest stay as they were. Brin's shout stayed as it was
after seven rounds of finds; card #171 (2026-10-18) is the eighth: four plain young-man battle
shouts (`tools/sound_kit/brin_shout_candidates.json`, built by `brin_shout_build.py` into
`assets/audio/sfx/candidates/brin_shout_1..4.wav`, levelled like the other hero shouts, credits in
`candidates/CREDITS.md`), number 1 wired in as `shout_brin.wav` ("Male Attack Grunt 1" by F.M.Audio,
CC BY 4.0, named on the credits screen); the user may pick another by changing `pick` and running the
script. The user picked
by ear, so a few picks peak later than `max_rise_ms`; they were kept on purpose. CC BY sources are
named on the credits screen (`data/branding/credits.tres`, a test checks songs).

Volume channels (2026-10-13, card #104): Settings has Volume (overall, the Master bus), Music,
Effects and Voices, saved per machine (`PlayerSettings.CHANNELS`). The `Audio` autoload creates the
Music, Effects and Voice buses (and, card #183, a hard limiter on Master with a little headroom,
numbers in `data/audio/mix.tres`); songs play on Music, sound effects and ambience on Effects, cues
with `SfxCue.voice` on Voice. Cues use a free player of the 24 first and only steal when all are
busy (the one with the least time left, `VoicePool`); the same cue is not started twice inside
`cue_cooldown_ms` (30 ms), so three identical hurts on one frame do not stack.

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
  rework is card #56). In his idle the shield rides on his near forearm at his side, its point
  tipped back and down (card #297, owner's pick 2026-10-21; it hung low in front of him before).
  Brin has twin daggers and a red headband. His idle is "high and low" in a reverse grip (card
  #296, owner's pick 2026-10-21): the near fist low and forward with its blade pointing back, the
  far fist raised before the chest with its blade pointing down. Every dagger shows its grip and a
  gold pommel out of the fist, because blades hanging straight out of the fists in line with the
  forearms read as Wolverine's claws (owner). Every other frame uses the reverse grip too (owner,
  2026-10-21: "change his whole attack and outside movement"): ready is the high and low standing,
  leaning in a little more with the fists further forward (he crouched low before; owner: "can we
  stop the ducking as a whole"; the old crouch stays as the base of his strike and cast wind-ups,
  leap, jump landing, get-up and victory wind); parry takes the blow on both blades lying down the raised forearms in an X; strike is a
  stab hammered down from a fist cocked over the shoulder; strike_alt a backhand with the far blade
  trailing the fist; strike_big both fists raised overhead, then a double stab; cast the forearms
  crossed before the face; in the zones he walks and stands in the high and low from every side
  (owner's pick "walk A" for the front and back views); victory ends with the far
  fist thrust up, its blade jutting forward over his head. The old loose stance stays as the base
  of his draw, jump push-off, victory and pickup frames. Cass a cyan-crystal staff, a
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
- The "?" stops' pictures (card #199) are small painted scenes, not sprites: `assets/event_art.py`
  paints a 128x64 back and puts a 3D-rendered subject on it (details in 8.7). One per event file and
  one per act's ambush page, in `assets/sprites/events/`; `check.py` demands a picture for every
  file in `data/events/`.

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

### 5.6 World pieces from Blender (phase 18, cards #221 to #237, 2026-10-18)

The solid world in 3D (phase 18 in 11). It started as a test (card #221) of whether real shapes beat
plain boxes and flat sprites. Heroes, monsters, people, animals and soft props (grass, ferns,
reeds, bushes) stay with the art kit (5.4).

- **The Blender kit** (`tools/blender_kit/`, its README; card #222). `build.py` builds every piece
  in Blender 5.2 with no window (`blender --background --factory-startup --python
  tools/blender_kit/build.py -- [names] [--preview]`) and writes one `.glb` per piece to
  `assets/models/`. A fixed seed per piece: the same code always gives the same file. It prints
  each piece's size and triangles. Shared parts in `kit/` (boxes, tubes, faceted rocks, plane
  cuts, broken brick courses, fallen bricks, planks, the vertex colours, the export); one module
  per group of pieces in `pieces/` (`stone`, `wood`). `--preview` renders the review sheet
  (`tools/blender_kit/preview/pieces.png`, not in git): every piece side by side from the zone
  camera's angle, wearing its pixel textures the way the game lays them, so a piece is judged
  without opening the game. `python tools/blender_kit/check.py` checks the contract below.
- **The contract.** One mesh at the origin (no move, turn or scale), front towards Blender's -Y,
  footprint centred, foot at height 0, flat shaded, at most 1500 triangles, vertex colours `Col`,
  one material per surface named like the surface (`stone`, `bark`, `rot`), no textures in the
  file. Imports turn off automatic LODs (the pieces are already low-poly).
- **Piece files** (`data/pieces/<id>.tres`, `WorldPieceData`; card #223): the model, and per
  surface (`PieceSurfaceData`) its name, tileable texture, texture world size and glow (emission
  strength and colour, following the texture's pixels: lamp glass, embers, a shrine's crystal).
  Each model surface wears the piece surface of the same name, else the one at its index; no
  match, or a missing model (then a 1 m box), shows the checkerboard with one warning. The same
  model in another zone's stone is just another piece file. `texture_sharpness` keeps each slanted
  face to one clean projection. Copies of a piece share their materials.
- **Placing a piece.** A `ZonePropData` with `piece` stands it at its own size times `scale`,
  turned by `rotation_y_degrees`, mirrored by `flip`, solid as a circle of `solid_radius` (0: walk
  through); it casts a real shadow, so no contact blob, and sprite fields, `glow` and `sway` are
  unused. A `ZoneBlockData` with `piece` stretches it to the block's `size`, solid as its box (for
  long walls). `StageBuilder.prop_view` and `block` build both; arena props (`StageLook`) work the
  same way.
- **Shape only, the zone's own pixels.** Textures are laid in world space (triplanar), so they never
  stretch. The model's vertex colours tint them: patchy moss on faces that look up, a darker
  foot, dark faces (a hollow).
- **Texture scale.** At a texture world size of 1.6, one texture pixel is 0.05 m, the same as a
  prop sprite's pixel. The wall's courses (0.4 m) line up with `ruin_wall.png`'s brick rows.
  `bark.png` (art kit `env_tiles.bark`) was drawn for the stump.
- **Flat sprites on a piece.** A piece can carry flat sprites (`WorldPieceData.sprites`,
  `PieceSpriteData`: sprite, offset from the foot, pixel size, glow, sway): fire stays pixel art
  (`flame.png`, `flame_big.png`, drawn by `env_life`) and sways.
- **Glow and dimming.** Lamp glass, coals, gold, holy water, runes, eyes and rot are glowing
  surfaces. A used shrine dims (`StageBuilder.dim_glow`, `offer_used_glow_share`): it takes a
  dimmed copy of the piece's materials. Every piece material lives in a shared cache (also the
  dimmed copies): a material owned only by its node errors in the renderer when the node is freed.
- **Making the data.** `build.py` writes a missing piece file from the kit's surfaces (texture,
  world size, glow) and carried sprites; it never overwrites one. `python
  tools/blender_kit/swap_props.py SPRITE=PIECE[:TURN[:SCALE]] ...` sets `piece` on every prop in
  `data/` that uses that sprite (zone sections, zones, arena looks), keeps the sprite path, sets
  `scale` from a sprite's other pixel size, and gives each copy a turn of up to TURN degrees
  picked from the file and the prop's id (a row of gravestones does not look stamped).
- **Old props in 3D (phase 18 step 2, cards #224 to #228).** Stone (#224): `rock`, `rubble`,
  `wall_low`, `arch_broken`, `pillar` (fluted, snapped), `column_fallen`, `statue_headless`,
  `gravestone`, `grave_cross`, `bones`. Wood and village (#225): `fence`, `signpost`, `cart`,
  `log`, `well`, `stilt_hut` (its window glows), the stump sprite as `stump_rotten` at scale 0.55,
  and the chests (`chest_closed`, `chest_open`: `ExploreVisuals.chest_piece`, `chest_open_piece`;
  opening swaps the piece, the two front faces lined up so the box does not jump). Fire (#227):
  `lamp`, `brazier`, `swamp_lantern`, `campfire`. Shrines (#226): `shrine_altar`, `shrine_idol`,
  `shrine_plenty`, `shrine_spring` (`ZoneOfferData.piece`), `seal_stone`
  (`ExploreVisuals.seal_piece`; it still bobs and hides when taken), `fountain` (dry), and
  `rot_gate`, a 30 m wall of roots with glowing rot (each end section's gate block). Wanderers and
  the shopkeeper stay sprites (people). Trees stay flat (#228): a try with a 3D trunk under
  the flat crown looked worse, the smooth folded wood clashing with the crisp pixel leaves. New textures (art kit `env_tiles`):
  `stone_dressed`, `bone`, `thatch`, `iron`, `gold`, `glass`, `cloth_red`, `glow_pale` (a pale
  surface that glows in the colour the piece gives it).
- **New pieces (step 3, cards #229, #230).** `stairs_broken` (five worn steps up to a landing),
  `bridge_planks` (a 4.2 m footbridge, walkable: it stands 0.24 m sunk so its deck sits just over
  the water), `house_broken` (a ruined cottage, a doorway facing front, roof beams fallen in),
  `tower_ruined` (the stub of a round tower broken off from 1 to 4 m), `gate_ruined` (two
  pillars, the lintel fallen). Raised ground: `ledge_rock` (a 6 m shelf, 1.2 m high) and
  `ledge_rock_tall` (a 2.5 m cliff edge), a craggy rock face with the zone's ground on top; the
  `_ash` and `_bog` piece files are the same models with ash and mud on top. Looks only: walking
  stays flat, a ledge is solid like a wall.
- **More plants (step 3, card #231).** Flat sprites from the art kit (`env_life`): `grass_tall`,
  `grass_ash`, `flowers_pale`, `flowers_violet`, `fern_big`, `bush_dead`, `mushrooms_small`.
- **Living water (step 3, card #232).** `ZoneGroundData.flow` (a stream's flow along the piece's own
  x and z, in m a second; `StageBuilder.water_flow` turns it into world tiles a second) and
  `ripples` (the share of 3 m cells where a ripple ring spreads every 4 s). The water shader runs
  both layers downstream for a stream, stipples the muddy rim into the water (a soft shore) and
  draws the rings. Rotten Hollow's `fallen` section has a stream from the back to the front, solid
  water either side of a plank bridge where the trail crosses (the water under the bridge is not
  solid), reeds on its banks. Every water piece has ripples.
- **Dressing the zones (step 4, cards #233 to #236).** `tools/dress_zones.gd` (headless; `--
  --only=SECTION|arenas`, `--dry-run`) adds to every section, picked by a seed from its id: two big
  pieces in the back band (z -12.5 to -6.5) as blocks, small 3D props (rocks, rubble, stumps, logs,
  bones, fallen columns) off the path as solid circles, and clusters of the plants that sway, all in
  the zone's theme (Rotten Hollow: moss ledges, mossy rocks, a ruined house; Ashen Ruins: towers,
  gates, stairs, ash ledges; Sunken Bog: mud ledges, stilt huts). Nothing goes on a trail, road,
  boardwalk or in water, near a spot, an enemy's home, the start or the lane at either end, or into
  anything solid. What it adds is named `dressed` (`resource_name`), so a second run replaces it.
  The fight arenas (`--only=arenas`): every arena block is replaced by the arena's own layout
  (`ARENA_LAYOUTS`): four `cliff_wall` pieces (8 m long, 5 m high, a craggy face in bands with the
  look's ground on top; `_ash` and `_bog` files) close the back in place of the flat back box,
  and each arena has its own pieces in place of the side box and the low wall box: Rotten Hollow
  a moss ledge, a ruined house, a mossy rock, a stump, a fence and a log; Ashen Ruins a tower stub,
  a fallen gate, broken stairs, an ash ledge, rubble and bones; Sunken Bog a mud ledge, a stilt
  hut with its lit window, a rock, a log, a stump and a swamp lantern; the Hollow King's throne
  broken stairs, two headless statues, two more pillars, a fallen column and rubble. They all
  stand behind the fighters (z -4.5 and further back) or out at the sides; the shared trees,
  pillars, rocks, lamp, mushrooms and grass stay. The fight camera's depth of field softens them.
- **Measuring (step 5, card #237).** `-- --perf-log=S` (with the game in a window) turns vsync and
  the frame cap off and prints `PERF fps= slowest_fps= draws= objects= triangles=` every S seconds
  and `PERF_SUMMARY` at the end (`PerfLog`). Measured 2026-10-18 (one machine, the zone bot for 30 s
  in each zone, before phase 18 against after it): the same 142 frames a second in all three zones
  (the machine's cap), draw calls up 11 to 19% (Rotten Hollow 140 to 158 on average, Ashen Ruins
  181 to 201, Sunken Bog 164 to 195). The slowest frames (7 to 8 a second, loading and the fight
  swirl) are the same before and after. No batching needed yet.
- **The first pieces.** `ruin_wall_broken` (a brick wall 4 m long, built course by course so its
  broken top steps like brickwork, with loose top bricks, one brick knocked back and fallen bricks
  in front; a block), `rock_mossy` (a faceted boulder, a smaller one leaning on it, a pebble; a
  prop, solid radius 1.05) and `stump_rotten` (a flared stump broken off in splinters, hollow and
  rotted inside on its own `rot` surface, five roots diving into the ground; a prop at scale
  0.85, solid radius 0.5), all in the start of Rotten Hollow (`rotten_hollow_start`), the stump in
  place of the stump sprite.

## 6. Input

Defined in `project.godot` (Project > Project Settings > Input Map in the editor); the table below
is the default, and every key and button can be changed in Settings > Controls (6.1). Solo: every
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
| `item_turn_left` / `item_turn_right` (Y screen: switch tabs, 8.18; with an item in hand in the Bag tab: turn it) | Z / C | LB / RB |
| `party_attributes` (Y screen Hero and Skills tabs: previous hero, 8.18) | T | LT |
| `party_skills` (Y screen Hero and Skills tabs: next hero, 8.18) | K | RT |

Outside fights every screen (main menu, settings, practice list, map, shop, rest, party, loot)
uses the `menu_*` actions: up/down pick, left/right change a setting or pick on the map, Confirm
selects, Cancel goes back; the mouse does the same (6.2). **Pause** (Esc / Menu) works in fights, zones and on the run map
(7.5); Main reads it before anything else, so in a fight Esc never acts as "back" in the action
menu (Backspace, Q or B do). B no longer leaves a zone.

Phase 1 practice keys (keyboard only, when `practice_tools_enabled`): 1 to 9 force the enemy's
next attack, I toggles "party cannot die", O toggles "enemy cannot die", R restarts the fight,
F1 opens the stats overlay (inside it: R training ring, G telegraph flash (F is the Skills key), T timing readout,
L motion sounds, H hit markers, C wind-up crouch, V cinematic camera), F2 starts lag calibration (only while the action menu is open, never during an
enemy attack). With `practice_tools_enabled` off, F1 and F2 are not available during a fight.
In a run fight and in the tutorial only F1 (stats) and F2 (calibration) work; G, T, L, H, C and V do nothing there
(the tutorial too since card #248: it keeps its enemy up and its party standing itself, and I, O, R or 1 to 9 broke its lessons).
On the victory/defeat screen F1 opens the stats, and Confirm or R fights again once
`end_input_guard_ms` (800) has passed, so a late defence press never skips the screen.

On-screen control hints are built from the Input Map (`HudStyle.binding_parts` /
`binding_text`), so remaps made in Settings > Controls (6.1) or in Project Settings > Input Map show
up in the hints (the movement tokens `@move`, `@updown`, `@leftright` and `@arrows` are built from the
four actions they stand for, `HudStyle.nav_parts`). They show
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

### 6.1 Rebinding keys and buttons (card #190)

Settings > Controls lists every player action (28: the fight menu, Parry / Dodge / Jump / Skill
press, walking, Strike and Pick up, the menu directions, Confirm, Back / run, Pause, the backpack
and party shortcuts, the stats overlay) with its key and its pad button side by side. Up / Down pick
a row (the list scrolls, ten rows show), Left / Right pick the Key or the Pad column, Confirm waits
for the new input ("press a key ..."). Escape (or the pad's Menu button) cancels, and so does
waiting `rebind_capture_ms` (tuning, 6 s). Everything works from the keyboard or a pad; the mouse also
works (6.2) but can never be bound.
A pad press can be a button or a trigger; sticks cannot be captured (drift), but a stick direction
an action already has keeps working.

- **What is rebound.** Each action has an ordered list of keys and one of pad inputs. Rebinding
  replaces the FIRST of the list (the one the hints show); the others stay as aliases (the arrows
  next to WASD, the stick next to the D-pad, E next to Enter). The row's help line names them
  ("Also: Up"). "Skill press" is its own row, so changing Parry does not change it.
- **Conflicts.** `ControlBindings.GROUPS` are the sets of actions needed at the same time: Parry /
  Dodge / Jump (with Pause and the stats overlay), Skill press (with the same two), the fight menu,
  walking and the zone, and the menus. An input already held by another action of a shared group is
  refused or swapped, never doubled. If exactly one action holds it and the trade is possible, the
  game asks ("Space is already Parry. Confirm: swap them. Back: leave it."); the other action takes
  the old input, wherever the new one was in its list. Otherwise it says so and keeps waiting.
  Groups that never run together may share a button (W jumps in a fight and walks up a menu; Parry
  and Skill press both default to Space). Attack and Confirm may share (the action menu does), and
  so may Back and Pause (Escape; Main reads Pause first).
- **No lock-out.** Rebinding only replaces, so every action keeps a key and a pad input, and
  Confirm, Back and Pause are checked to still have both (`ControlBindings.reachable`). Escape, F2
  (the lag calibration key) and the pad's Menu button cannot be given to an action: they cancel the
  "press the new button" step and keep Pause until reset. "Reset to defaults" is a row of the list
  (asks twice, within `rebind_reset_confirm_ms`). A saved file that clashes or lost Confirm / Back /
  Pause is dropped whole at start-up.
- **Saving.** Per machine in `PlayerSettings` (`user://settings.cfg`, section `[controls]`, one entry
  per changed action: `{"key": [...], "pad": [...]}` of `{k, code}` inputs). `PlayerSettings._ready`
  calls `ControlBindings.install` before any screen reads the Input Map; a test run (`-s`) keeps the
  project's own keys. Actions never changed stay as `project.godot` defines them.
- **Timing path unchanged.** Rebinding rewrites the Input Map events; `DefenseInput._input` still
  matches them with `is_action_pressed` and stamps the press as before (a test feeds it a rebound
  key and button). Pad events are bound to all devices (device -1), so a rebinding applies to every
  pad: per-pad rebinding is out of scope (the hints and the roster treat all pads alike).
- **Code.** `ControlBindings` (`scripts/core/control_bindings.gd`, pure: defaults, groups, conflict
  check, swap, save / load, writing the Input Map), the Controls section of `SettingsScreen`,
  `ButtonPrompts.refresh` redraws every hint after a change, `ListMenu.window_rows` scrolls a long
  list. Dev: `--screen=controls`.

### 6.2 Mouse in the menus (card #202, review ui-input #4)

The game is a keyboard and pad game, but every menu also works with the mouse (a PC player clicks
"New Run" without asking why nothing happens). Keyboard and pad behave exactly as before.

- **What the mouse does.** Pointing at a row chooses it (the same cursor, sound and highlight as the
  keys). A left click confirms the row under it; a right click or the mouse's back button (the
  side button) goes back (Cancel); the wheel moves the cursor and stops at the ends. A click on
  nothing does nothing.
- **Where.** Every `ListMenu` gets it from one place, `ListMenu.handle` (the entry every list screen
  already calls): the main menu with Online and Extras, the pause menu, the Yes / No prompts, the
  players screen (Start, Back), the Rot Journal, the settings, the rest, event, loot and treasure
  lists, the shop's "which item" list and the backpack's item menu. Screens with their own cards
  use `MenuMouse` for the same meaning: the practice list (hover and click a card, right click
  back), the run map (hover and click one of the next stops, right click opens the pause menu),
  the shop (hover and click a shelf card or service, right click leaves), the backpack (hover and
  click a grid cell: the cursor goes there and Confirm happens; right click is Back), the
  attributes and skills screens (right click is Back), the credits, the Join Online screen and the
  end-of-run screen. The hero cards and gear slots of the backpack, the attribute and skill rows and
  the players screen's hero cards are keys and pad only for now.
- **Settings.** The section names (Graphics, Sound, Controls, Game) are clickable. On a row whose
  value Left / Right change (volumes, window size, frame limit, shake, flashes, text size), the left
  half of the row clicked steps it down and the right half up (`SettingsScreen.SIDED_ROWS`); other
  rows are toggled or opened as with Confirm. In Controls the click chooses the Key or the Pad
  column by the half of the value text that was clicked and waits for the new input; a right click
  cancels the wait or the swap question.
- **The pointer.** Autoload `Pointer` (`MouseCursor`) hides the OS pointer while a key, a pad
  button or a stick (past 0.5) was the last thing used and shows it again the moment the mouse
  moves or clicks. It is always hidden in fights and zones (`Main._mouse_wanted`: false while a
  fight or zone is on screen and no pause menu, settings screen, prompt or backpack is over it).
  The fight's own menus are keys and pad only: a mouse never presses a defence.
- **The timing path is untouched.** No Input Map action has a mouse event (a test checks every
  action), and `DefenseInput` only answers the defence actions, so a click can never be a parry,
  dodge, jump or skill press. Mouse events are only read by menus, which are not on screen during an
  attack. In co-op the mouse counts as the keyboard device (`PlayerRoster.device_of`).
- **Code.** `MenuMouse` (`scripts/menu/menu_mouse.gd`, pure: row and cell hit tests, the button
  meanings, the pointer rule; tested), `ListMenu.handle` (`clicked_share` says where across a row
  a click landed), `MouseCursor`, `BackpackGrid.cell_at`.

---

## 7. Presentation

### 7.1 Phase 1 (functional, placeholder)

- 3D stage; characters and enemy are pixel-art sprites drawn as billboards, nearest filtering.
- Fixed 3/4 camera with shake and punch-in on hits, parries and counters.
- HUD: timeline row (top left), attack banner (top centre), party panels with HP and AP pips
  (bottom, in the same left-to-right order as the fighters), enemy HP bar, action menu, damage
  numbers, defence result popups and timing readout, controls hint, practice status (phase 22 took the rules
  hint off and moved the practice keys into the F1 panel, 7.13), victory/defeat screen with a one-line
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
- **The floor does not repeat like wallpaper** (card #186, `floor_ground.gdshader`): each place has
  three drawn variants of its floor tile (`hollow_floor`, `ash_tile`, `bog_tile`, `throne_tile`, each
  with `_b` and `_c`; the Hollow Throne no longer borrows the ash). They are calm: one ramp in three
  close steps, a luma spread under 10, detail in small clusters, no stripes (`check.py` tests the
  spread, the row and column averages and that the three variants share a tone). The shader gives
  every ragged region of the floor (`floor_region_world_size`, edge bent by `floor_region_warp`) one
  of the variants and mirrors it (`floor_mirror`), and drifts the brightness in a few steps over
  wide areas (`floor_tone_*`). Every decision is made per art pixel with nearest sampling, so it
  stays crisp. All numbers are in the StageLook. Ground pieces (moss, trails, leaves) dither their
  rim into the floor (`ZoneGroundData.fringe_pixels`, `edge_shade`) instead of ending in a cut line;
  boards and slabs keep a hard edge.
- **The arena shifts when a boss rages** (card #196, `PhaseShift` pure and tested, `ArenaMood`):
  on the `enemy_phase` event (a boss or a zone guard entering phase two) the room eases over
  `phase_look_ms` (about 1.1 s) from its look to the look's `phase_*` values: sky, ambient and sun
  colour and strength, fog colour and density, vignette strength and colour, and the lamps
  (`phase_lamp_percent`), with a one-time puff of particles (`phase_burst`, embers or spores). Every
  act boss lair and zone look has one (a test checks it): the Hollow King's throne goes blood red and
  darker with a tight vignette and roaring braziers, the zone looks (guards, and the act 1 boss,
  who fights in Rotten Hollow) shift a smaller step in their own colours (Hollow: plum and
  amber, Bog: sickly yellow-green, Ruins: ember red). It is a slow tween, not a flash; under the
  Flashes setting on Reduced or Off it takes `phase_look_calm_percent` as long (twice). The fog
  Graphics option still wins (the tween only changes values). Presentation only: the engine, the
  commands and the golden test are untouched. The shift never reaches an unreadable room: fighters
  and markers stay clearly lit (checked in pictures of the Hollow King fight).
- **Contact shadows** (card #186): props, trees, shrines and chests stand on a soft dark blob (the
  fighters' `shadow.png`), as wide as the prop's footprint (the opaque width of its lowest rows)
  times `prop_shadow_width_percent`, slid away from the sun by `prop_shadow_shift_percent`. All in
  the StageLook ("Contact shadows"). Ground cover (grass, ferns, reeds), glowing props, critters
  and item glints get none (`ZonePropData.contact_shadow`).
- **One pixel size:** scenery is drawn at 0.045 to 0.05 world units a pixel, like the fighters (a
  test checks every prop in the zones and the arenas, and that ground pieces use the floor's 1.6
  tile size). Trees, logs, huts and ruins that were scaled up to 0.055 to 0.07 are now 0.05, so
  they are a little smaller; redrawing the big ones larger at native size is a later art job.
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
- **Camera shake is a trauma model** (`CameraTrauma`, pure, tested; card #179). Each impact adds
  trauma (0 to 1, clamped, so a string of parries builds up); trauma drains `shake_decay_per_s`
  (1.5) a second; the shown shake is trauma squared times `shake_max_offset` (0.32 world units)
  plus a small roll (`shake_max_roll_deg`, 1.6), driven by three sines of the clock at a fixed
  `shake_hz` (6), never a random number per frame, so it looks the same at any frame rate. The
  Settings screen's screen shake percent scales the result. `CombatCamera.shake(strength, ms)` is
  kept as a shim for `add_trauma(strength)`. Every number is in `combat_visuals.tres`.
- **Impact tiers** (card #179, presentation only). Small: a graze, a good press (trauma 0.2). Medium:
  a perfect press (0.4, punch 0.3), a critical hit (0.55, punch 0.5), a heavy hit taken (0.7, punch
  0.4), a counter (0.7, punch 0.9); sparks grow 150%. Large: a Team Ultimate hit (0.5, punch 0.35,
  sparks 220%), a team counter (0.9, punch 1.2), a hero going down (0.65 plus the red flash), a boss
  phase change (0.9, punch 1.0 over 500 ms), the last enemy falling (0.8, punch 0.9, flash 0.25) and
  a boss or guard falling (1.0, punch 1.4, flash 0.45). The two kills hold: the body stays on its
  hurt pose for `kill_hitstop_ms` (110) or `boss_kill_hitstop_ms` (170) and the strike freezes on
  its impact frame (a skill's clock is held, an attack's slashes stop) before the dissolve and the
  end shot. A boss or guard fight opens with the camera pulled back `intro_push` (1.2) and gliding
  in over 900 ms. A struck enemy recoils away from the heroes (`enemy_hit_knockback`,
  `enemy_heavy_knockback` for crits, heavy hits and counters) and settles back. The boss of a boss
  or guard fight is the enemy with the most HP.

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
black, then the "Controller recommended" notice and the title screen (7.7). Before it, Godot's
own boot splash shows no logo, only black (`application/boot_splash/show_image=false`,
`bg_color` black; user, 2026-10-19), so the game opens on black straight into the intro. Any key, button or click skips it (after `skip_guard_ms`). A missing
video goes straight to the menu. Autoplay never shows it. Godot plays Ogg Theora only: the MP4 was
converted with ffmpeg (`-c:v libtheora -q:v 8 -c:a libvorbis`). Phase 8 (user: it looked soft and
stretched; the exported MP4 was only 1888x998 at a low bitrate): `tools/branding/render_intro.py`
re-renders it from the original canvas animation (the user's `dragonrot-intro/source`) in a hidden
browser at exactly 1920x1080, 60 fps, with its own WAV, Theora quality 10. The video and the logos
are scaled smoothly (linear filter; the project's default is nearest, for pixel art).

- **Main menu** (first screen, `MainMenu`): (Continue,) New Run, Online, Relics (8.17, phase 17), Extras, Settings, Quit, with
  no description line under the rows. Online and Extras open a second list in place (cancel or
  Back goes back): Online has Host Online and Join Online; Extras has Tutorial, Glossary (7.12), Journal (7.11)
  and Credits. Practice (the tutorial card first, then the fight and zone list, full HP, nothing
  carries over) is a test tool: its row shows in Extras, after Tutorial, only in debug builds
  (`OS.is_debug_build()`: the editor and `run_game.bat`), never in the shared game. The cursor
  comes back on the last item picked (a row of Extras reopens that list). Card #150 (user,
  2026-10-15) kept it short; card #208 (user, 2026-10-17: "it feels a bit cluttery", "practice is
  a dev thing") made it five rows; phase 17 added Relics (six).
  **New Run** (phase 25, card #305, 8.21) opens two picture cards side by side in place, like the
  Online cards: **Run** (a green hill with a pale road winding up to a red flag) and **Fight Rush**
  (four bone tally marks crossed by a sword). The Fight Rush card carries a gold star chip "Best 16"
  once any Rush record exists (the best of the three party sizes). Left/Right chooses, Confirm
  selects, Back goes back; footer Choose / Select / Back. Run is the old New Run (overwrite check,
  tutorial and calibration offers, the players screen with Oaths); Fight Rush shows only the
  calibration offer when it is due, then the players screen titled Fight Rush, and never touches a
  saved run. Without the Rush data the card is greyed and Confirm plays "locked". Coming back from a
  run or a Rush, the cursor rests on New Run (`MainMenu.PLAY_RUN`, `PLAY_RUSH`, `MODE_ITEMS`).
  **Host** (Online's first card; card #312, 8.21) opens the same two cards in place of Host / Join:
  **Run** hosts a run as before, **Fight Rush** hosts a Rush (the same Best chip, from the host's
  records; greyed and "locked" without the Rush data). Back goes back to Host / Join. The host's
  players screen then opens for that game (`MainMenu.HOST_RUN`, `HOST_RUSH`, `HOST_MODE_ITEMS`).
  In the corners, small and quiet like most games' title menus (card #210, user 2026-10-17):
  bottom left the version, "v" and Project Settings' `application/config/version` (0.18.0 since phase 18, the
  phase number; the same version the save check and the online handshake use, so raise it for a
  build friends play together); bottom right the studio's DragonRot wordmark
  (`assets/branding/dragonrot_logo.png`, cut from the studio intro by
  `tools/branding/studio_logo.py`). Size, alpha and margin in `data/branding/branding.tres`.
- **Settings** (`SettingsScreen`): volume (left/right, 10% steps), fullscreen on/off, training
  ring on/off (practice fights only; the row says so), flashes Full / Reduced / Off (card #185),
  lag calibration (the same beat test as F2 in a fight) and "reset lag to default",
  plus the controls list (rebinding, 6.1). Saved per machine at once
  (`PlayerSettings`, `user://settings.cfg`); volume and fullscreen are applied at start-up.
  **Full menu (card #112):** four sections, LB / RB (Z / C) to change: **Graphics** (fullscreen;
  window size when windowed: maximised, 1280x720 to 2560x1440; vsync, on = the project's mode;
  frame limit: none, 30, 60, 120, 144, 240; fog, bloom, shadows, soft shadows (SSAO), depth of
  field: each only turns off what a place's look uses, `StageBuilder.apply_settings` applies a
  change at once even over a fight or zone), **Sound** (the four volumes), **Controls** (rebind every key and button, 6.1)
  and **Game** (screen shake 0 to 100% in 25% steps, scaling every camera shake; the training
  ring; lag calibration, which shows the keyboard's and the pad's value, and its reset, 3.2).
- Menu screens share `ListMenu` (`scripts/menu/`), driven by the `menu_*` actions only.
  and **Game** (text size, below; screen shake 0 to 100% in 25% steps, scaling every camera
  shake; flashes; the training ring; lag calibration and its reset).
- **Text size** (card #203, review ui-input #5; Settings > Game): Normal, Large, Larger. Every body,
  title and number label, the menu choices, the hint chips and the Join Online field are built at
  the chosen percent of the size the screen asks for (`HudStyle.scaled`, so the fight HUD, the
  zone HUD and the tutorial text follow too). The percents (100, 115, 130) live in
  `data/presentation/ui_fonts.tres` (`text_size_percents`, one per name in
  `PlayerSettings.TEXT_SIZE_NAMES`) and are kept gentle because the HUD plates and menus are laid
  out for 1920 x 1080. Not scaled: the big gold titles, banners and damage popups (already
  large), and text drawn straight on the canvas (hit marks, the training ring, the map's stop
  names). The choice is saved per machine (`PlayerSettings`, `[game] text_size`) and given to
  `HudStyle` at start-up; changing it rebuilds the settings page at once and redraws every hint,
  menus opened afterwards use it, and a fight's HUD from the next fight on. Lists that are tall at
  normal size (Graphics has ten rows) show fewer rows at once and scroll
  (`SettingsScreen.fitting_rows`). A test builds every settings section at the largest size and
  checks it fits 1920 x 1080.
- Menu screens share `ListMenu` (`scripts/menu/`), driven by the `menu_*` actions and the mouse
  (6.2).
- **Pause menu** (`PauseMenu`, user request 2026-10-12): Esc / Menu in a fight, a zone or on the
  run map (B on the map too). Continue, Players (a local game outside the tutorial, 9.3), Settings, Glossary (7.12), "Save & Quit" (a local run, 8.14), and "Abandon
  run" (asks first, then the main menu) or in practice "Leave" (the practice list). In a Fight Rush
  (8.21; in a fight or on the Rush screen) the note reads "Fight 7", there is no Save & Quit, and
  "Give up" takes Abandon run's place (asks "Give up?", Give up / Keep going, then the Rush end;
  online only the host's, 8.21). Pause, Back or Continue resumes. Everything
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
- Settings: values on the right; the controls are rows with the key and the pad button of each
  action (6.1; before card #190 they were a read-only panel of chips).
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
`--pad-prompts` starts with pad buttons shown. Used to check the look without a person. With the owner at the PC use `quiet_run.bat` (10.1), which opens the window without taking focus.

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

- **Controller notice** (card #167, user request): between the studio intro and the title screen a
  short "Controller recommended" screen (`ControllerNotice`, `scripts/menu/`): the menu's dark
  background, a gamepad drawn in the logo's style (`assets/branding/controller_mark.png`, made by
  `tools/branding/controller_mark.py` with the logo's own worn-gold wear: a double outline like the
  crest's shield, the cross pad, four buttons, two sticks and the staff's gem; shown 240 px tall,
  smooth with mipmaps; user 2026-10-18: the first pixel-art icon "fries me", "one with the game
  logo style") and the heading in the worn-gold title lettering, nothing else (the user dropped the
  second line; `controller_text` stays in the data, empty). It fades in (500 ms), holds (2400 ms), fades out (600 ms) by itself and any key,
  button or click ends it early after a 1500 ms guard (playtest 2026-10-18: a quick double tap past
  the intro skipped it unseen at 400 ms; a key still held from the intro does not skip it). It
  fades over black (a black floor under it), not Godot's grey clear colour. Text, icon, sizes and every time are in `data/branding/branding.tres` ("Controller notice"
  group); a hold time of 0 turns it off, and `controller_skip_with_pad` (off) leaves it out for a
  player whose pad is already plugged in. No music or sound of its own (the menu music starts with
  the title). Not shown in autoplay or any `--screen=` start; `--screen=controller` shows it, then the
  title.

### 7.8 Tutorial (phase 14, card #131, lessons approved 2026-10-15; rebuilt the same day)

Phase 19 (card #264) added lesson 6, Marks (defend a dotted hit, then lift a mark with Mend); the
Relics and Echoes cards became lesson 7 (2.17). Phase 22 (card #291) added a First Strike card as
lesson 7 (the zone no longer spells it out), so Relics and Echoes are lesson 8 of 8.

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
  it. The target step shows the skill's name and AP cost over the target's name between arrows (phase
  22: no title, no description; a skill that cannot be used shows a lock, 7.13).
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
  While an enemy attack plays they step back to 30% see-through (user, card #268, like the turn
  track) so they do not cover its hits. A parry brings them back to full at once, with no fade,
  and keeps them there a moment; then they step back again while more hits are coming. A parried
  last hit keeps them full to the end of the attack, and a counter shows them at full too, so its
  damage reads on the bar straight away (`enemy_panels_attack_alpha`, `enemy_panels_fade_ms`,
  `enemy_panels_parry_hold_ms` in combat_visuals.tres; `EnemyPanelsFade`). Each machine fades its
  own HUD from its own playback (co-op and online send nothing for it).
- **Attack banner:** the move's name big (worn title letters), a small line over it saying who
  uses it on whom ("GNAT SWARM  >  CASS > ALDER"), the hit icons under it; it punches in.
- **Defend corner:** a red DEFEND tag over three slanted plates, PARRY, DODGE and JUMP, each in its
  defence colour with its button and the hit icons it answers (parry: normal and rend; dodge: normal
  and sweep; jump: ground; `defend_hit_icon_px`). No rules text since phase 22 (7.13). The skill
  press corner is one gold plate: the button and PRESS.
- Dev tools: `--menu-keys=ACTION,...` presses those input actions on the action menu the first time
  it opens ("|" moves on to the next turn's menu; for pictures of the skills list, the target step
  or a later hero's turn); `--key-prompts` keeps keyboard keys shown even with a pad plugged in.

### 7.10 Charged Dooms on screen (card #195, DESIGN.md 2.3)

All numbers, colours and cues are in `combat_visuals.tres` ("Charged Dooms"); the controller reads
only the mirror (`charge_left`, `charge_damage`, `break_hp`, `staggered` on the enemy's fighter dict).

- **Announced** (an `intent` with charge fields the mirror did not know): a centre banner
  "TIMBER FALL IN 3" in the doom red, a flash, a rumble, the alert sound, a beat. Every gathering
  turn (`doom_charging`) plays the same banner with the new count.
- **Aura.** While it gathers, the enemy holds its wind-up crouch (`doom_squash_percent`) and glows
  `doom_glow_color`, pulsing every `doom_pulse_ms` (quicker, `doom_pulse_last_percent`, with one turn
  left). `CombatController._update_doom_look` drives it every frame from the mirror;
  `CombatView.sync_alive` keeps the crouch after other enemies' attacks.
- **Enemy panel.** The NEXT word turns into DOOM; a block over the intent line reads
  "DOOM 2" (turns left) over a gold bar that fills as the party deals damage (no break numbers
  since phase 22). A staggered enemy shows the dizzy-stars icon among its status icons.
- **Turn order.** An enemy's gathering turns carry a tag with the turns until the Doom (3, 2),
  its unleash turn reads DOOM, a staggered enemy's next turn reads STAGGER (`TimelineRow.doom_tag`,
  pure and static).
- **Unleash.** The Doom's name with "!", a heavy rumble, punch-in and flash, a beat; then the
  attack's own banner and string as for any attack.
- **BROKEN!** The large tier of card #179 (7.6): a gold "BROKEN!" banner, a held freeze
  (`broken_hitstop_ms`, also holding the skill's clock when a press broke it), `broken_shake`,
  `broken_punch`, a flash, sparks and a sound; the enemy then drops into its stagger pose (a held
  `stagger` clip, falling back to hurt) with a cold glow and a STAGGERED popup, and shows TURN LOST
  over its head when the stagger ends.
- Sounds reuse existing cues named in the data (`doom_gather_sfx`, `doom_unleash_sfx`,
  `broken_sfx`, `stagger_sfx`).

### 7.11 The Rot Journal (card #200, review ui-input #9)

A book of every enemy and attack the player has met, from the main menu row "Journal" (Slay the
Spire's compendium). It is a reference and a record, not a reward: nothing in it changes a fight.

- **Screen** (`JournalScreen`, `scripts/menu/`, `--screen=journal`): the menu backdrop, a worn-gold
  "Rot Journal" title, the progress line ("Met 7 of 19 enemies"), then two parts. Left, a `ListMenu`
  of every enemy in `data/enemies/` (alphabetical; one never met reads "???" and is dimmed). Right,
  the chosen enemy in an ink plate: its portrait (a dark silhouette until met), name, "Met in N
  fights, Beaten N times", where it was met (zone names, or the fight's name for a lair or elite,
  the first six), then one row per attack it can ever use (phase-two ones too). A row shows the
  attack's name, the hit kinds seen (Normal, Ground, Rend, Sweep), the marks seen (ROT, BLIGHT,
  WEAK, AP DRAIN, in the HUD's colours), a red DOOM tag for a Charged Doom, and the player's record
  against it: parried, dodged, jumped, hit (and broken, for a Doom). An attack never seen reads "???"
  with nothing else. A legend line under the rows says what answers each kind. Up/down chooses,
  Back closes (`HintBar` at the foot); keyboard and pad like every menu. Everything fits 1920x1080
  (a test measures the fullest page).
- **What is recorded.** `JournalTally` (`scripts/journal/`) is fed by `CombatMirror.apply` with
  every event in playback order, exactly as `FightRecap` is (CLAUDE.md rule 7: presentation reads
  events, never the engine; online clients record their own identical copy). It counts per enemy
  type (the data id): fights it was in, copies that went down, and per attack: times it struck, each
  hit's kind and mark as declared (a hard fight's forced rends and sweeps show as such), and the
  outcome of every hit aimed at the party (parried, dodged, jumped, or hit). A Doom the party broke
  counts as broken. Counts are in hits, like the RUN OVER recap. When the fight ends, `Main` hands
  `CombatController.journal_fight()` to `JournalFile.record`. A fight left half way (the window
  closed) is not recorded.
- **What counts.** A person's fights in a run (zone fights, elites, guards, bosses; won, lost or
  fled). **Practice fights, the tutorial and bots write nothing** (`RotJournal.counts_fight`):
  practice has invulnerable and immortal cheats and lists every fight, so counting it would unlock
  the whole book in minutes and mix cheated numbers into a record; a bot's numbers say nothing
  about the player. `--journal-path=PATH` (dev tool) keeps the journal at a `user://` path and
  makes every fight count, bots and practice included: how the headless smoke runs fill a journal
  without touching the real one.
- **File** (`JournalFile`, `RotJournal`): `user://journal.json`, per machine, separate from the run
  save and from settings. `{format: 1, journal: {enemies: {id: {name, met, beaten, places, attacks:
  {id: {name, seen, broken, parried, dodged, jumped, hit, kinds, marks}}}}}}`. Written like
  `RunSave`: temp file, flush, old file kept as `.bak` until the new one is in place; a load falls
  back to the `.bak` when the file is missing or damaged. A file of another `format` is refused,
  kept as it is, and never written over (a newer build may still read it); a damaged file with no
  backup starts a new journal. Loading drops junk (wrong types count 0, unknown kinds are ignored)
  and clamps every count to 999999. It does not carry the content fingerprint: an entry names an
  enemy and an attack by id, and the screen shows what the current data still knows (a renamed or
  removed id simply no longer shows). No migration exists yet; `format` is there for the first
  change of shape. The journal is local: an online player's book is their own.
- **Not in it (yet):** per-hero records, damage dealt, the loot an enemy drops, and sorting or
  filtering. Entries are never reset by a new run; delete `journal.json` to start the book again.

### 7.12 The Glossary (card #207)

A book that explains the game's terms and icons, so nobody has to guess what a purple wave, a
bone-coloured claw, EXPOSED or a rot-touched piece means. A reference, not a reward: it changes
nothing in a fight. It is reached two ways, and both open on the first topic:

- **Extras on the main menu**, a row "Glossary" right after Tutorial (`MainMenu.GLOSSARY`); Back
  returns to Extras with the cursor on that row.
- **The pause menu**, a row "Glossary" after Settings (`PauseMenu.glossary_requested`). It opens
  over the pause menu (layer above it, the pause menu hidden and disabled while it is open, like the
  settings screen from the pause menu) and Back returns to the pause menu. It reads only, so a fight
  stays paused (or, online, goes on) exactly as under the pause menu; it never touches the timing of a
  fight. `Main._free_pause` also frees it if the pause menu goes.
- **Screen** (`GlossaryScreen`, `scripts/menu/`): the menu backdrop, a worn-gold "Glossary" title, then
  a topic strip ("< previous topic  TOPIC  next topic >", "Topic 3 of 14, 8 terms"), then two parts like
  the Rot Journal. Left, a `ListMenu` of the topic's terms (10 rows at a time, scrolls). Right, the
  chosen term in an ink plate: a square plate with the game's own icon (whole-number scaled so the
  pixel art stays crisp, edged in the term's colour) or, with no icon, a swatch of its colour; the
  term's name in worn gold; "Shown as  PARRY" in the term's colour when the game prints a word for
  it; then two or three plain lines. Up/down chooses a term, left/right changes topic (wrapping round
  the ends), Back closes (`HintBar` at the foot); keyboard and pad like every menu. Everything fits
  1920x1080 (a test measures every page).
- **Phase 19** (card #252): the five new marks, Ward, Shielded, Marks, Helpers and Burst, the mark
  icons on status terms; "Help on heroes" split from "Marks on heroes" (118 terms in 15 topics).
- **Phase 25** (card #305, 8.21): a last topic, "Fight Rush", with three terms: Fight Rush (the New Run
  card's picture), Reward cards (the Heal card's picture) and Records (gold, "NEW RECORD"); 124 terms
  in 16 topics. Added to the `.tres` only, like the phase 24 streak term.
- **Content is data**: `data/glossary/glossary.tres` (`GlossaryData`: `topic_ids`, `topic_names`,
  `entries`; each `GlossaryEntry`: `id`, `topic`, `term`, `text`, `tag`, `icon_path`, `color`, where an
  alpha of 0 means no colour). `tools/bootstrap_glossary.gd` wrote the first version (109 terms in 14
  topics: The fight, Reading attacks, Defence, Skills and AP, Counters and team, Marks on enemies, Marks
  on heroes, Dooms, Enemies, The map, In a zone, Gear and items, Shops and camps, The run); after that,
  edit the `.tres` (or the tool's list and re-run it, not both). The tool takes the hit kinds'
  colours and icons from `combat_visuals.tres` and the status words and colours from `HudStyle`, and a
  test (`tests/unit/test_glossary.gd`) keeps the book equal to them, so the screen and the book cannot
  drift apart. Every term needs an id, a known topic, a short name (26 characters at most), text (260
  at most), and an icon file that exists; a list of the card's terms must all be present. Text names
  buttons by what they do ("the Run button", "Confirm"), never by a key, because pad and keyboard
  both play.
- **Dev picture**: `--screen=glossary` opens it; `--screen=glossary_<topic id>` opens on that topic
  (`glossary_reading`, `glossary_dooms`, `glossary_hero_marks` and so on).
- **Not in it (yet):** the tutorial (the interactive tutorial is being extended in phase 17, so the
  glossary does not link to it or change it), enemies and attacks (the Rot Journal, 7.11, has those),
  and per-item or per-gear descriptions (the party screen and shops show those).

### 7.13 Fewer words, more icons (phase 22, cards #273 to #279 and #288 to #291, 2026-10-20)

Owner rule (2026-10-20): never text only, and never a bare icon either. Every choice, reward and
info line is an icon WITH a short word ("Gold 120", "Act 1/2", "Parry 3", "Curse 30%", "-10% max HP
all"): a picture and a number alone meant nothing to a new player (owner, the same day). Two or
three choices sit side by side as cards, never in a column, pick lists too ("Who pays?" is hero
cards; longer lists may stay a column); Back is the cancel button, never a row. A card's title stays
on one line: cards grow to fit it, sharing the row, and a title still too long gets a smaller font.
Rules text lives in the tutorial and the Glossary, not on screens.

- **Practice-only helpers (#275, #276, #290).** `CombatController.is_practice_fight()`: a local
  fight that is not a run, not the tutorial and not online (the Practice menu's fights and the dev
  switches). Only there do these show: the press timing in ms after the word ("PARRY -34", "LATE
  +343"; the runners' `timing_numbers_allowed`, F1 > T still toggles it), the F1 stats panel and
  its "F1 Stats" chip on the end screen, and the practice keys (1-9 next attack, I, O, R). Those
  keys used to sit in gold under the enemy panels (the owner's "yellow text"); they are now the last
  lines of the F1 panel. The real game shows the word alone (PARRY, LATE, PERFECT).
- **Enemy panels (#279).** Nothing on an enemy panel may be wider than its HP bar
  (`ENEMY_BAR_WIDTH` 380 px), so every bar keeps one length: the name and the NEXT line end in
  "...", status icons wrap (an HFlowContainer), the intent's hit row is capped
  (`INTENT_ROW_MAX_WIDTH` 210 px, `HitRowView.max_width_px`). Before, a long attack line, a long
  Doom line, many badges or a long hit row widened the panel, and since every panel matches the
  widest, every bar grew. Statuses are icons with their word and turns ("SLOWED 2";
  `HudStyle.status_chip`,
  `status_icon_px`; every status has `assets/sprites/ui/mark_<id>.png`, drawn by
  `tools/art_kit/assets/ui_marks.py`; a staggered enemy shows dizzy stars). A Doom reads "DOOM 2"
  over its break bar. A hit that leaves a mark wears the mark's icon on its corner, on the intent
  sign and in the banner (no [BURN/DAZE] words). Hero cards use the same status icons.
- **Fight corners and menu.** Defend corner: DEFEND over the PARRY, DODGE and JUMP plates, each
  with its button and the hit icons it answers; no rules sentence. Skill press corner: one plate,
  the button and PRESS. The target step: the skill's name and AP cost over the target's name. A
  skill that cannot be used shows a lock on its row (the cost and lock red when short of AP; a red
  lock and the Hush icon when Hushed; grey otherwise; `ActionMenu.LOCK_*`), never a sentence.
  Sizes and colours: `combat_visuals.tres`, group "Fight HUD icons".
- **Ranged hits (#278).** A thrown normal hit shows `hit_ranged.png` (a steel ball with gold speed
  lines, `CombatVisuals.hit_icon_ranged_path`, drawn by `fx_ui.py`) on the intent sign, the banner
  and the hit marker. The intent event carries `ranged` (one bool per hit, sent only when a hit is
  thrown, like `marks`; `AttackHitData.ranged_in(hard)`). It is still a normal hit for the rules.
  The Glossary's "thrown" term uses the same icon.
- **Fight end (#273, #274).** A won run fight ends with two icon rows instead of lines of text:
  what was won (coin "+gold", the item found, "FLAWLESS +1 spoils", each Relic line with the Relic's
  icon) and the heroes (portrait, "+N XP", a gold "Lv N" on a level up, greyed when down). No
  defence tally (the run end shows defence, #283) and no "New attribute points" sentence. Practice
  fights keep the old lines of numbers. Art and sizes: `combat_visuals.tres` group "End screen"
  (`gold_icon_path` = `ui/gold_coin.png`, drawn by `map_art.py`).
- **Choice cards (#288).** `ListMenu.horizontal = true` draws each item as a card in one row: a
  picture, the word, a small tag, icon chips. Left and right move; the mouse points and clicks; a
  chosen card keeps its font size (gold frame and colour show it), so its words never re-wrap and
  jump; a greyed card does nothing when chosen. Chips are {icon or glyph, text, color, newline};
  `RunState.offer_chips` / `choice_chips` give a deal's price (red), gift (green) and risk (a die
  with its %). Who pays a max-HP price: "all", "1" (you pick) or "1?" (random). Used by yes/no
  questions (No left, Yes right; shrines and wanderers add their chips under the question), Spoils
  (Relic icon, name, New / Home / "Lv a > b", effect, drawback and stat chips), the campfire (Rest
  "+N%", Train "+N", Upgrade "+1 Lv"; before the boss Rest, Keep watch, Sharpen), treasure (Plain and
  Rotten chests), "?" events and the starting pact, and the main menu's Online page (Host, Join).
  Leave and Back are the cancel button with a footer hint, never a card. Pick lists of three or
  fewer (who pays: the heroes' faces and HP; what goes; which item to upgrade) are cards too. Art: `tools/art_kit/assets/ui_choices.py` (choice_*, chip_*); paths and
  chip colours in `stop_visuals.tres`.
- **Zone (#289, #291).** The goal top right is icon chips (`ZoneController.goal_chips`): a seal
  stone "0 / 2" while the gate is shut, a horned skull GUARD, then a flag EXIT (or OPEN), and a
  plain skull with the other enemies left (`goal_foe.png`; paths in `explore_visuals.tres`, group
  "Goal"). Bottom left shows only the buttons: First Strike is taught by the tutorial's lesson 7
  card. The party strip in a zone has no gold (nothing to buy there). "Leave the zone?" says "No way
  back." with a skull chip for the enemies still here. A find still shows as a gold banner.
- **Menus.** Pause: a picture and a word per row, no line under it. A yes/no question has at most
  one short line. Main menu notices are one short line (the technical reason goes to the log).
  Settings: the title and section tabs are pinned at the top; lines under rows are four words at
  most; Controls has a Keyboard page and a Controller page (#277: opens on the device in use, LT/RT
  or left/right switch, each page its own Reset; bindings drawn as button pictures, `ButtonChip`);
  the lag row says Keys / Pad / Default, never ms; the Training ring row only in debug builds. Lag
  calibration: beat pips, the device picture, a steadiness meter that turns green when it can save,
  a "Too uneven" chip; ms only with F1 open; the offer says "About N seconds" from the data. Join
  Online: a footer hint bar (Connect / Back, Rejoin after a lost connection), no networking
  sentence. Players screen: the hero cards centred, one Oath picker with effect chips beside a big
  Start; Back is the cancel button; the first open seat shows the buttons that can join now. A lost
  pad shows a crossed-out pad, the player's tag and two chips. The Controller recommended notice
  is skipped when a pad is plugged in. In release builds the F1 Stats action is hidden and never
  clashes with a usable action (`ControlBindings.list_debug`).
- **Run screens.** Map: under the map, the picked stop's picture, name and 2 or 3 chips
  (`MapScreen.detail_chips`; the campfire before the boss shows Keep watch and Sharpen). Shop:
  service cards with pictures (skull Cleanse, anvil Upgrade, arrows Restock, coin Sell, door
  Leave), prices as the coin and a number, Sell once. Run end: one row of chips ("Act 1/2" with the act's boss
  lair, "Stops N", "Wins N", "Gold N", each hero's face with "Lv N"), the defence rows ("Parry 3",
  "Dodge 0", "Jump 0", "Hit 4", a star with "Best"), "Kept" and the Relics kept as icons with their
  names (up to 8, then "+N"; nothing when none), and on a defeat one row: "Killed by", the enemy's
  portrait and name, the attack's name and hit icons, "N damage". Echoes page: a pips bar per Relic being learned; the rules are in the
  Glossary's "echo" term. Rot Journal: hit kinds and marks as icons, the record as glyphs with
  counts, no legend. Y screen: a tab's count is a gold circle with a plain dark number; the Skills
  tab's slots sit centred over the tree. New art: `tools/art_kit/assets/ui_runinfo.py` (upgrade,
  restock, door; the map and shop use the campfire's `choice_upgrade.png` for Upgrade).
- **Skills, tutorial, map legend, shop items (#292 to #295, 2026-10-21).** The fight's skill and item
  lists show the chosen row as its `short_text` (3 to 6 words, AbilityData / ItemData; the
  description when empty) over labelled chips worked out from its data (`ActionMenu.ability_chips` /
  `item_chips`: AP cost, who it reaches, hits, damage %, heal, revive, cleanse, the mark it leaves,
  turn later / sooner, gauge), packed into lines that never widen the panel; the full sentence stays
  on the Skills tab and in the Glossary. Every tutorial card has a picture (`TutorialStepData.icon_path`;
  the game's own icons, plus `tools/art_kit/assets/ui_tutorial.py` for the ring, follow-up,
  cleanse and Echo) and one or two short lines. The map's legend is small and dim, its icon + word
  for the stop under the cursor lit. A shop item shows its picture, name and the same chips as the
  fight (`ShopScreen.item_chips`, at most `item_chips_max` 4 chips / `item_words_max` 8 words,
  map_visuals.tres). Still words: the Journal's "Met in N fights" line.

### 7.14 Controller vibration (phase 24, card #299)

The pad buzzes with the fight. Patterns are data (`data/presentation/rumble.tres`, `RumbleSet` of
`RumblePattern`s: steps of the weak motor %, the strong motor %, ms), played by the `Rumble` autoload
(`PadRumble`) through the pure `RumbleMixer` (several buzzes on one pad mix by the stronger motor at
each moment; a pad is told only when its levels change, with a length so it stops by itself).

| Moment | Pattern | Who feels it |
|---|---|---|
| a parry (the last hit of a string: stronger) | `parry`, `parry_final` (sharp, short) | the defender's player |
| a dodge / a jump | `dodge` (light) / `jump` | the defender's player |
| a perfect / good skill press | `press_perfect` / `press_good` (softer) | the presser |
| a hit taken (heavy: at least `big_hit_percent` of max HP) | `hurt` / `hurt_heavy` | the hit hero's player |
| a hero downed | `downed` | that hero's player |
| the Team Ultimate | `ultimate` (long, rolling) | every pad here |
| a boss's rage, a Doom unleashed | `boss_rage`, `doom` | every pad here |
| a defence streak step (2.18) | `streak` | every pad here |
| thunder in a storm (8.20) | `thunder` | the pad in use |

- **Whose pad** (`RumbleMixer.pads_of_player`): local co-op, each player's own pad (a keyboard player
  feels nothing); one person on this machine (solo, or this machine's player online), the pad that was
  used last, while a pad (not a key) was the last thing pressed; another machine's player online,
  nothing here. The fight hands the roster and hero owners over (`PadRumble.set_party`); out of a fight
  a buzz goes to the pad in use. A buzz is sent to the pad the moment it is asked for (a 35 ms buzz
  must not wait for the next frame).
- **Settings > Controls > Controller**: Vibration, `< 100% >` in steps of 25, 0 shows OFF (saved per
  machine, `PlayerSettings.rumble_percent`); a change buzzes the pad once at the new strength
  (`RumbleSet.test_pattern`). `RumbleSet.strength_percent` scales everything again (above 100
  stronger, each motor capped at full).
- Bot and picture runs (`--autoplay`, `--shots`, `--screen`, headless) never buzz: the owner may be
  playing something else with that pad. Out of focus (the app's or the window's) the pad stops and
  stays still until the game is in front again; focus is not read at start (Windows sends the first
  focus late), so a fresh start buzzes. `--no-rumble` keeps the pad still.

Tests: `tests/unit/test_rumble.gd`.

### 7.15 Skill presses climb, and the killing blow goes quiet (phase 24, cards #307, #308)

Two additions the owner picked from an idea search for phase 24 (2026-10-23).

**Skill presses climb (#307).** The skill press sound rings `press_ladder_step_semitones` (1.5)
higher for each perfect press in a row in one skill (up to `press_ladder_max_steps`, 5), like the
parry ladder (#93); several players' perfect presses on one hit share a step; a good press, a miss
or a stray (early or late) press starts it over (`SkillSequenceRunner.ladder_pitch`). A skill or the Team Ultimate of at least
`press_finish_min_presses` (2) presses, every one perfect (a press voided because its target fell
does not count against it, `all_perfect_done`; checked again when a kill voids the rest, which an
online client hears of a moment later), ends with a **finish** on its target at the last strike (a
spell's when its bolt lands): a burst of `press_finish_sparks` (30) gold sparks, a gold
flash on the target, a punch-in (`press_finish_punch`), a little shake and the `press_finish` pad
buzz for everyone who pressed. `press_finish_sfx` can add a sound (none: no new recording).
Presentation only; every machine online plays it for the presses it sees.

**The killing blow goes quiet (#308).** The blow that ends a fight (the last enemy falling, by any
cause) or the last hero going down: the fight song cuts to silence over `kill_silence_fade_ms` (60)
and stays silent (`Audio.hush_music`), so only the hit and the crumble are heard; the victory or
defeat jingle and then the end song come in on the silence. A new song always starts unhushed, and
so does the same song asked for again (a restart); with no end song (an empty one, or Run) the
fight song fades back after the jingle's beat; a Second Wind that gets the last hero back up brings
the song back; a song still fading out (a boss's rage swap a moment before) is cut too. The scene also holds a dark impact frame
(`impact_frame_color` at 55%) for `impact_frame_ms` (70) under the HUD, then the usual kill flash
(`CombatHud.impact_frame`); the Flashes setting scales the dark frame like a flash and Off skips it.
`kill_silence` turns the silence off. Numbers in `combat_visuals.tres` ("Press ladder", "Killing
blow").

Tests: `tests/unit/test_press_ladder.gd`.


Slay-the-Spire style branching node map (host picks path). Node types: zone (small explorable
area with visible roaming enemies and a forced fight at the end), rest, shop, boss (final).
Touching a roaming enemy starts a fight; striking it first gives an opening advantage.
In zones the host moves the party and others follow (v1). In-run progression: levels and
equipment with passive effects (like E33 Pictos). Loot goes to a shared pool; each item can be
equipped by one character. No progression between runs in v1 (phase 17 changes this: Relics and
Echoes, 8.17).

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
  for the party until gear exists; quitting mid-run lost the run then (a save came later: 8.14).

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
  shows ZONE CLEAR and goes back to the map (since card #241 the zone stays open and the party leaves by its exit
  when it wants: 8.5). Other roaming enemies are optional (more gold, more
  risk). The top right shows the goal as icon chips (phase 22, 7.13: horned skull GUARD, then a
  flag EXIT, and a skull with the other enemies left); the run's HP strip (no gold in a zone) sits top left.
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
  main menu. On RUN OVER a recap of the fight that finished the party follows (card #191): its
  encounter and enemies, the stop, act and oath, the attack that did the most damage (all of its
  hits added), the last blow and who it downed, and a defence line (parried, dodged, jumped, hits
  taken of hits). `FightRecap` (`scripts/combat/core/`, pure, tested) is fed by `CombatMirror`
  with every event in playback order, so the numbers come from the mirror, never the engine, and
  every online machine builds its own copy from the same events (the host's and the clients'
  agree). `scenes/main.gd` keeps the recap when a fight ends and hands the lines to the screen. The pause menu's "Abandon run" quits a run (it asks first; the run and its save are
  lost). "Save & Quit" keeps a local run for later (8.14).
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
- **Gear** (#29, `GearData`, `data/gear/`; since phase 17 these are Relics kept between runs, with
  a stat line, levels and Echoes: 8.17, which replaces the buying, selling and loot rules here):
  one passive per item, `run_gear_slots` (3) per
  character, one wearer per item, unworn gear in the shared bag. 13 items: Iron Charm (max HP
  +20%), Whetstone (power +15%), Quick Boots (speed +15), War Drum (+1 AP at fight start),
  Riposte Ring (counters +50%), Echo Charm (+1 AP after each counter), Leaping Heart (perfect jump
  heals 5%), Second Wind (once per fight, downed during an enemy attack: back up when it ends with
  30%), Keen Eye (perfect skill press +25%), Rot Hunter (Exposed +50%), Thick Hide (enemy hits
  -15%), Mender's Charm (heals +30%), Lucky Coin (gold +25%). Stats (max HP, power, speed) are
  folded into the fight setup by `RunState`; the rest are `Passive` keys the engine applies
  (`CombatSetup.party_passives`, `Combatant.passives`). Putting gear on never heals (no free
  heal by swapping); taking it off cuts HP to the lower max. Twelve more pieces, the
  **rot-touched** ones (strong, each with a price), are in 8.16 (card #198); the list above is the
  ordinary 13.
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

**Phase 21 change (card #282): the grid is now Alder's pack with pockets** (one item each, no shapes
or turning, treasure turns into gold at once; see 8.19). The grid rules below are history.

**Phase 17 change (card #240, user 2026-10-18): the charms are gone.** With Relics and Echoes (8.17)
they were a third buff system. The backpack now holds supplies (Salve, Feast, Tonic, Bomb,
Smelling Salts), keys, treasure and **curses**: the two rotten charms (Rotting Heart, Grave Moss)
are now `ItemData.Kind.CURSE` items that only hurt (rot each turn in fights), given by events as a
price and thrown away by a shop's Cleanse; nobody finds them. The nine other charms are "Faded"
treasure (no effect, find weight 0) kept only so saves made before phase 17 still load. Their six
best ideas became Relics (8.17). Shops sell no charms; they sell `run_shop_gear` (3) Relics instead
of 2. The family boosts, the gold links on the grid and the charms line under the backpack are
gone (the line now names the curses' rot). What follows is the phase 11 design; read "charm" there
as history.

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
  statuses from one hero and heals a little; card #194: for now the Salve is the cleansing item,
  it lifts one hero debuff in a fight, 2.7). Salve, Feast and Tonic move from "used when bought"
  to the backpack. **Tonic cap** (card #175): a hero can drink at most `tonic_max_per_hero` (2)
  Tonics in a run (`RunState.tonics_used`, kept in `to_dict`), because gold plus Restock turned
  into endless max HP. The party screen greys the choice with a line saying why, a capped hero is
  skipped by the bot, and the shop stops selling Tonics when every hero is full (`RunState.wants`).
  **Tonics do not level** (card #198): a combined or upgraded Tonic would have given more max HP per
  drink and got round the cap, so `ItemData.combinable()` is false for the Tonic (no campfire or shop
  upgrade, no combining) and `RunState.entry_amount` always returns its plain `amount_percent`, even
  for a levelled Tonic in an old save.
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
  Salve, Feast, Tonic, Bomb, Smelling Salts and Key; zones can turn up all of them. Phase 19 added
  the Antidote and Holy Water (fight items that lift marks, 2.17) to the shop and the finds.
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

- **Faster with depth (card #188, 2026-10-17):** enemy attacks also speed up. `CombatSetup.
  attack_tempo_percent` (0 = tuning `attack_tempo_percent`) scales every hit's impact and lunge
  (lower = faster; the windows keep their size). `RunState.fight_setup` fills it: tuning
  `attack_tempo_percent` less `run_enemy_tempo_row_percent` (1) per row of depth (the same depth as
  HP, acts included), then elite fights take `elite_tempo_percent` (94) of that, guards
  `guard_tempo_percent` (94), bosses `boss_tempo_percent` (92). Entering phase two, an enemy's
  strings speed up by its `EnemyData.phase_two_tempo_percent` (Hollow King 90, Husk Lord 92, the
  three guards 94), kept on the combatant (`Combatant.tempo_percent`, in the snapshot). Nothing
  goes under `attack_tempo_floor_percent` (70) of the authored timing (`CombatSetup.tempo_floor`).
  The intent's times and the declared hits carry the result, so the judge, the bots and online
  play need nothing new. Practice fights play at the authored speed (no run); the tutorial keeps
  its own slow tempo. Example: the act-two Hollow King (depth about 13) plays at about 80%, about
  72% in phase two.
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
middle row costs 1 point, the bottom row 2; phase 19 gave three branches a fourth skill, which costs
2 like the third):

| Hero | Branch | Start | 1 point | 2 points |
|---|---|---|---|---|
| Alder | Bulwark | Guard | Shield Wall (3 AP: whole party guarded; perfect +1 AP) | Unbreakable (4 AP: every enemy taunted, Alder guarded; perfect: riposte too) |
| Alder | Bash | Shield Bash | Shield Throw (1 AP: 2 hits of 60%) | Earthshaker (4 AP: 140% to every enemy, their turns later) |
| Alder | Retort | Taunt | Riposte Stance | Payback |
| Brin | Flurry | Quick Cuts (now 4 x 40%) | Twin Fangs (2 AP: 2 x 90%; both perfect: Exposed) | Fang Storm (phase 19: 3 AP, 2 x 55% to every enemy), then All In (now 6 x 100%) |
| Brin | Cripple | Hamstring | Open Vein (2 AP: 100% and Bleeding 3 turns) | Rend |
| Brin | Shadow | Feint Step | Shadowstep (1 AP: next turn much sooner, Empowered) | Death Mark (3 AP: Marked for 3 skills) |
| Cass | Mending | Mend | Purify (phase 19: 2 AP, every mark off one ally, Warded 2 turns, perfect 3), then Renew (2 AP: Renew 3 turns) | Sanctuary (4 AP: heals the party 30%, perfect 40%; lifts one debuff from each, all on a perfect press) |
| Cass | Light | Reveal (now a bolt) | Smite (2 AP: 160% bolt, +100% on Exposed) | Radiance (phase 19: 3 AP, an 80% bolt at every enemy), then Revive |
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
  bolt flies to the target for each press, leaving at the press and landing after its flight
  (card #166, 2.10); her heals and buffs never moved. Her
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
- **Stay in the zone, leave when you want** (card #241, built 2026-10-19): beating the guard no
  longer sends the party straight on. ZONE CLEAR shows and the zone stays open: the party can
  still fight the optional enemies, open chests, pray at shrines and talk to wanderers. The way out
  is the **exit**, a signpost at the far right end of the end section, in the lane
  (`ZoneSectionData.has_exit` / `exit_spot`, (24, 0, 0) in all three end sections; the assembler
  moves it like the gate; `bootstrap_zones.gd` writes it and keeps decoration off it). While the
  guard stands the signpost is dark; once it falls a gold light comes on beside it, a gold "EXIT"
  tag marks it on screen and the top right says "The way out is open: leave by the EXIT at the far
  end". Within `zone_exit_reach` (tuning, 1.8) the hint "Leave the zone" shows; Confirm asks
  "Leave the zone?" (the shared yes/no prompt, "Stay" picked first, it says how many optional
  enemies are left and that there is no coming back). Leave: the guard's spoils, the party screen,
  then the map, as before. Its look is data (`explore_visuals.tres`: `exit_piece` the signpost,
  `exit_scale`, `exit_color`, the light's energy, reach and height, `exit_solid_radius`). A zone
  without an exit (none ship) still moves on the moment the guard falls; practice zones are
  unchanged (cleared when every enemy is beaten). Only the leader walks and uses things, so the
  question is player 1's in local co-op and the host's online, like a shrine's; the clients' zones
  light the exit when the guard falls (they replay the same fight result) and follow the host to
  the spoils screen it sends. A defeat after the guard (by an optional enemy) still ends the run.
  Save & Quit inside a zone still restarts that zone from its start. `--screen=zone_exit` (the
  open exit) and `--screen=zone_leave` (the question) are for pictures.
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
  seals, uses free shrines and deals it can pay for, opens chests, then goes to the guard, and with
  the guard beaten walks to the exit and leaves (Main does not ask the bot). Tests assemble every
  zone with many seeds and check that every spot, seal, shrine and the guard can be reached from
  the start (gate open), that the exit can be reached from the guard and not past the shut gate.

### 8.6 Mini-boss guards and elite fights (phase 15 step 2, cards #156, #157)

- **Guards are mini-bosses** (`EncounterData.mini_boss`): each zone's guard is a named kin of its
  monster, recoloured by the art kit (`enemy_variants.py`), with a **phase two** at half HP (its
  variant's moves, faster, a banner): Rotten Hollow **The Gorged One** (crimson bloat, with a gnat
  swarm), Sunken Bog **Mire Mother** (teal toad, with a carrion fly), Ashen Ruins **Ash Warden**
  (charcoal shade, with a gnat swarm). Their name is announced like a boss's and the boss song
  plays; they cannot be run from; they still grow with depth. Deep zones bring their helpers as
  variants (`deep_guard_*`). `tools/bootstrap_phase15.gd` writes them.
- **Signature Dooms** (card #195, 2.3): each guard and each act boss has exactly one Charged Doom,
  on both its phase lists (a data test checks it; no other enemy has one). Party-wide strings of
  8 to 10 hits at 28 to 40% of the enemy's power, uneven gaps, ground hits, thrown hits and the
  hard-fight rends and sweeps (a forced feint in each):

  | Enemy | Doom | Turns | Break | Hits | Weight |
  |---|---|---|---|---|---|
  | Gorged One | Gorge Burst (bile and quakes) | 2 | 42% | 8 | 7 |
  | Mire Mother | Brood Tide (waves and mud) | 2 | 21% | 8 | 7 |
  | Ash Warden | Ashfall (cinders and rocks) | 2 | 36% | 8 | 9 |
  | The Husk Lord (act 1 boss) | Timber Fall | 3 | 22% | 8 | 14 |
  | The Hollow King (act 2 boss) | Crown of Rot | 3 | 13% | 10 | 8 |

  The break shares were set from bot runs (2.3): a focused, perfectly defending bot breaks about
  7 in 10 (the King about 6 in 10); they are meant to be re-tuned from play. All five files are
  written by `tools/make_attack.py`; the enemy files list the Doom by hand (the one-shot
  `bootstrap_phase15.gd` does not know it). The choreography golden test took the five new files
  (55 attacks, every older hash unchanged).
- **Better reward**: spoils (after a guard, an elite or an act's boss) are gear of at least
  `run_spoils_min_rarity` (rare) while the run has enough of it, and one of the choices is a
  rot-touched piece (8.16).
- **Elite fights** (`EncounterData.elite`): enemies get `elite_hp_percent` (140), `elite_power_percent`
  (115) and `elite_gold_percent` (150) on top of depth. Four: Twin Husks, The Laughing Pack (two
  hyenas and a fly), Toad Court, Shade Coven, each with a deep version. They are met two ways:
  an **Elite stop** on the map (a fight in one of the act's zones' look, then spoils), and the
  zones' **champions** (8.5), now elite fights marked "ELITE" in their own colour (they no longer
  force the deep version). Elite fights cannot be run from (2.13).

### 8.7 Event stops "?" (card #158, rebuilt as real trade-offs in card #193, 2026-10-17)

The owner wants the game hard, so a "?" is a temptation, never a gift. Every choice costs something
scarce, and a "?" can turn into a fight.

- `EventData` (`data/events/`): a title, a short story, a picture and 1 or 2 choices
  (`EventChoiceData`), always plus Leave (the screen adds it, so no event can lack it). A choice has a
  deal (`ZoneOfferData`) and may have a risk: `risk_percent` of the time its `risk_deal` strikes too
  (seeded by the run and stop, the same on every machine). Choices the party cannot pay are greyed.
  Shrines and wanderers (8.5) use the same `ZoneOfferData`; the new prices below are for events.
- **Prices a deal can have** (all in `ZoneOfferData`, all optional, together with the old gold and
  HP prices):
  - `cost_max_hp_percent` with `cost_max_hp_target`: **permanent max HP**, a percent of the hero's
    current max HP (`RunState.lose_max_hp`; a levelled hero loses more points). The target is
    EVERYONE, CHOSEN (the player picks the hero) or RANDOM (the seed picks one). It never takes a hero
    under `event_max_hp_floor_percent` (40) of their normal max HP, and the choice is greyed when every
    hero is at the floor. HP is clamped to the new max. A chosen hero at the floor cannot be picked.
  - `cost_item`: **lose a backpack item**, RANDOM (seeded) or CHOSEN (the player picks). Rotten items
    are never taken (nobody misses those). Greyed when the backpack holds nothing that can be lost.
  - `cost_rotten`: **a curse**. One of the rotten items that already exist (Rotting Heart, Grave Moss)
    goes into the backpack at once; it is strong and it rots the party in fights until the shop's
    Cleanse (or throwing it away) removes it. Greyed when it would not fit. An event deal never has
    both an item price and a curse (a test keeps it so; the check for room would depend on the pick).
  - `ambush` (+ `ambush_spoils`): **a fight**. After the story the party fights that encounter through
    the run's own fight path (`Main._start_final_fight`, like an elite stop: HP carries on, gold and XP
    as for any fight, a defeat ends the run). Spoils (one piece of gear) only if `ambush_spoils` is on.
    A deep act or row fights the encounter's deep version (`RunState.ambush_encounter`), so every
    ambush encounter must have one (a test checks). Ambush fights cannot be run from
    (`tuning.ambush_can_run`, off).
  - A **risk may cost any of these too**, not only HP. A risk is never refused: it takes what there is
    (a hero or an item picked by the seed, a curse that finds no room rots away).
  - Choices that need a hero or an item first (`ZoneOfferData.pick_kind`) open a short list on the
    event screen ("Who pays?" hero cards, "What goes?" item cards, a column past three; cancel goes
    back, phase 22). A deal asks for at most one pick.
- **The screen writes the deal out** (`RunState.choice_summary`): "Price: ... Reward: ... 40% risk:
  ...", with the depth scaling already applied, then the choice's flavour line. Numbers are never
  typed into the choice text. After a choice that sprang an ambush, Continue reads "Fight".
- **Depth**: gold and XP in an event (prices and rewards alike, so the trade keeps its shape) grow by
  `tuning.event_reward_row_percent` (6) for every map row of depth, acts counting the rows before them
  (`RunState.event_scale`): 100% on row 0 of act 1, about 130% on its row 5, about 166% on row 4
  of act 2.
- **A "?" stop can be an ambush instead of an event.** On entering a "?" stop (`RunState.go`) the run
  rolls once, seeded by the stop (`AMBUSH_SALT`), against `unknown_fight_percent_base` (15) plus
  `unknown_fight_percent_step` (15) for every "?" stop passed without a fight since the last one.
  A hit starts the count over (so does an ambush sprung by a choice); a miss raises it
  (`RunState.ambush_streak`, 15%, 30%, 45%, ...). The stop then shows its own page, "An Ambush!"
  (`ActData.ambush_title` and `ambush_text`, and the fight's name), with one choice, Fight; no event
  is used up. The fight is one of the act's `ActData.ambushes` (ordinary 2 to 3 enemy fights, in
  their deep version in act 2) in the look of one of the act's zones; it pays gold and XP and gives
  no spoils.
- **Online and Save & Quit**: the host chooses, the clients see the result. The run dict carries the
  new state (`ambush_streak`, `ambush_id`, `ambush_spoils`; `apply_dict` refuses a negative or
  non-integer counter, a non-string id, a non-bool flag or an id that is no ambush of this run's
  data), so a client opening the event screen or the fight sees the same ambush, and a saved run that
  was saved on entering the stop (8.14) comes back to the same ambush page.
- **The events.** An act's "?" stops pick from its `events`, never one met before in the run
  (`RunState.events_seen`, synced online). Sixteen, written by `tools/bootstrap_events.gd` (which
  also fills both acts' event lists and ambush pools; every event has its own picture, see "The pictures" below):

  | Event | Act | Choices (every one has a price) |
  |---|---|---|
  | The Weeping Well | 1, 2 | Drink: heal 35%, everyone -4% max HP, 30% risk -15% HP; coin: team gauge +50, 25% risk an ambush |
  | Gambler's Bones | 1, 2 | Stake 25 gold for 80, 55% to lose 100; or the purse: 60 gold, 55% -10% HP and a Grave Moss curse |
  | A Wounded Pilgrim | 1 | Give an item of your pick: XP and a 20% heal; or the satchel: gold and a Salve, 55% an ambush |
  | Rot Blossom | 1 | One hero eats the fruit (-6% max HP): heal 35%, 30% risk; or the seed pod: a rare find and a curse |
  | The Hanging Cage | 1 | Climb: the Key, 45% risk of -6% max HP (random hero) and -15% HP; or fell the tree: Key and gold, certain ambush |
  | Merchant's Wreck | 1, 2 | Search the crates: a rare find, 45% an ambush (the hyenas); or pry the strongbox: 70 gold for a random pack item |
  | The Whispering Mask | 1, 2 | A chosen hero wears it (-8% max HP): 90 XP each, 40% risk; or sell it: a Golden Idol and a curse |
  | The Bone Collector | 1 | Trade a chosen item and gold for a rare find; or sell a rib (a chosen hero -7% max HP) for gold |
  | The Hungry Scarecrow | 1 | Feed it a random item: heal 40% and XP; or cut the stitches: gold, XP and a certain ambush |
  | The Tithe Collector | 1 | Pay coin: heal 30% and gauge; or pay blood (everyone -6% max HP): gold and XP |
  | Shrine of Old Kings | 2 | Kneel (a chosen hero -8% max HP): gauge +70 and XP; or pry the gold: 100 gold, 55% an elite ambush with spoils |
  | The Black Mirror | 2 | Touch it (-5% max HP all): 100 XP, 40% an ambush; or smash it: 90 gold and a Rotting Heart curse |
  | The Drowned Chapel | 2 | Ring the bell (-5% max HP all): heal 45%, 50% an ambush; or take the silver: 120 gold and a curse |
  | The Buried Cairn | 2 | Dig: gold and a rare find, certain ambush; or say the name (lose a chosen item): gauge and XP |
  | The Sealed Door | 2 | Break the seal: gold, an elite ambush with spoils; or pick the lock (lose a chosen item): gold and a rare find |
  | The Widow's Wager | 2 | Buy in (40 gold): XP, 50% a random hero -8% max HP; or stake a hero (-10% max HP): a legendary find, 40% a curse |

  Act 1 draws from the first ten, act 2 from the last ten; four are in both. The act's ambush pools:
  act 1 Bloat and Gnat Swarm, Rot Hyena and Carrion Fly, Mire Toad and Carrion Fly, Shade and Gnat Swarm,
  Two Carrion Flies; act 2 the Rot Hyena Pack plus four of those (deep versions).
- `EventScreen`: the picture, the story, the choices, then what happened and Continue (or Fight). Items go into
  the backpack (it opens when full); online the host chooses and the clients see the result.
- **The pictures (card #199, 2026-10-17).** Each event has its own painted scene,
  `assets/sprites/events/<event id>.png`, and each act its own for the ambush page
  (`events/ambush_rotten_road.png`, `events/ambush_ashen_deep.png`, `ActData.ambush_picture_path`);
  16 + 2, all drawn by `tools/art_kit/assets/event_art.py` (art bible: 5.4; the kit README). They are
  128x64 art pixels, fully opaque, at most 96 colours, and what each shows is the event's own story:
  the Well a stone well with a rotting roof, weeping cyan and a glint on the black water; Gambler's
  Bones a skeleton in a gambler's hat at a rotten table, dice and a candle; the Pilgrim a robed man
  on the road with his satchel and a pool of blood; the Rot Blossom a huge violet flower growing out
  of a corpse; the Hanging Cage an iron cage on a dead limb with the key in a dead hand; the Wreck a
  wagon on its side with spilled crates and hyena eyes in the dark; the Mask a golden crowned mask in
  the moss with whispers rising; the Bone Collector a hooded man in a coat of knucklebones inside a
  hollow tree; the Scarecrow a sack-headed scarecrow with a stitched mouth over a dead field; the
  Tithe Collector a hooded figure with a bowl on the rim of a hole where the road was; the Old Kings
  three robed stone kings kneeling at a gold altar; the Black Mirror a gilt mirror of black glass in
  dark water with three figures looking out of it; the Chapel a church sunk to its roof in black
  water, a bell in the tower and rings spreading; the Cairn a cairn with a scratched name and the
  pit someone left; the Sealed Door an iron door with three wax seals in a hillside, ember light
  under it; the Widow a woman in black by a cold hearth with the husband's empty chair. The act 1
  ambush is a road closing in with eyes in the trees and a dropped purse as bait; the act 2 ambush
  pale hands and ember eyes in the ash round a half-buried coffer.
  Made like the rest of the world: a flat painted back (sky, two ridges, bare trees, ground, mist,
  glow and vignette from the shared colour ramps, bands cut by a light ordered dither) with the
  subject in front built as a small 3D model and rendered by the same camera and light as the props
  and fighters, over a soft contact shadow, then every pixel is snapped to the colours the scene
  was made from. Dusk, night, olive or ash skies, never bright; glows (cyan, amber, violet, ember)
  only where the story has magic or fire.
  `StopVisuals` (`data/presentation/stop_visuals.tres`) holds how the screen shows it: scale 4 (so
  512x256 on screen, nearest filter, never blurred), a thin worn-gold frame with a dark gap and a
  soft shadow. An event whose file is missing shows the old question mark (`map_event.png`, scale 4)
  in the same frame. `tools/bootstrap_events.gd` writes the picture paths; `check.py` and
  `test_event_pictures.gd` keep every event and act picture present, the right size and opaque.
- **The bot** (`EventAutoplay`, pure, tested) plays a careful player: it takes a choice only if the
  reward is worth the price (its own gold values, named consts), pays no permanent max HP while the
  weakest hero is under 70%, walks into a possible ambush only while the party is fit for an elite
  (`ZoneAutoplay.is_ready`), takes a curse only for a reward worth 120 gold or more, hands over its
  cheapest item, and charges max HP to its healthiest hero. Otherwise it leaves. It fights every
  ambush page (there is no way around). Its habits are not game rules.
- Numbers are a first guess to tune with play (`--autoplay=average --bot-skill=60` over many seeds);
  nothing here makes a run easier.

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
  visited, the campfire points, the events met, the shop's restocks, the Tonics drunk and the "?"
  ambush state (8.7).

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
  **No two overlapping pieces share a height** (card #269, `GroundStack`, pure and tested). Pieces
  on the same `layer` used to lie at exactly the same height, and where they overlapped (a mud road
  across a pond, two pools, a section's road running into the next one) they flickered through
  each other as the camera moved (z-fighting). Now the pieces of a built place are taken in order
  of layer, then list order, and each lies one `ground_step` over the highest earlier piece it
  overlaps (its turned box), starting `ground_lift` over the floor: a higher layer always draws
  over a lower one, and of two overlapping pieces on one layer the later one wins. Pieces that do
  not touch share steps, so the stack stays low (up to about ten steps in the shipped zones). The
  numbers are in the StageLook ("Ground pieces": 0.01 and 0.004); the props' shadow blobs
  (`prop_shadow_lift`, 0.07) and the walkers' (`combat_visuals.tres` `shadow_lift`, 0.06) lie
  above the whole stack, which a test checks for every zone on many visits. The 3D world pieces
  have no upward face on the floor (checked), and the arenas have no ground pieces.
- **Props** (art kit `env_life.py`): ruins (broken arch, knight statue, fallen column, rubble,
  brazier, torn banner, gravestone, dry fountain, low wall, bones), swamp (reeds, mangrove, mossy
  tree, giant mushroom, log, stilt hut, swamp lantern, fern), forest (bush, stump, thorns, fence,
  cart, well, signpost, grave cross, dead pine) and the woodcutter's campfire.
- **Wind** (`ZonePropData.sway`): grass, reeds, ferns, banners and trees sway (the sprite shader
  bends the top; feet stay; each prop's phase from where it stands).
- **Air** (`ZoneAmbientData`, particles that follow the camera's spot): ruins ash falling and
  embers rising; swamp fireflies, low mist and spores; forest falling leaves and fireflies.
- **Air in fights** (card #196): a fight in a zone's look (a zone fight, an elite, a guard) plays that
  zone's `ZoneAmbientData` too: `combat_visuals` `fight_air_percent` of each particle count (50),
  in a box `fight_air_depth_percent` as deep (60) and shifted `fight_air_offset` toward the back
  wall, fixed in the arena (the combat camera glides, so it does not follow). They are 3D particles
  behind and around the fighters; the HUD and the hit markers draw above them. A fight with no zone
  (a boss lair, the practice list) uses its look's `arena_air` instead (the throne has embers).
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

### 8.14 Save & Quit (card #174)

A local run can be put down and picked up later, Slay the Spire style. Online runs are never saved
(one machine cannot save for everyone), and neither is the tutorial or a practice fight.

- **One slot:** `user://run_save.json`, written by `RunSave` (`scripts/run/run_save.gd`, pure, tested).
  It holds `RunState.to_dict()` exactly as it is (the save never reads its keys, so new run fields
  are saved without changing it), a format version, the content fingerprint (`DataHash.of_content`, only to tell which
  build wrote it: it is not checked, see below), whether the party is inside a stop, and how many
  players share the pads. A mid-run roster change (a friend joins or leaves from the pause menu's
  Players row, or a lost pad's seat is given up, 9.3) rewrites the last checkpoint with the new
  count and nothing else (`Main._resave_players`).
- **Safe writes:** the new save goes to `run_save.json.tmp` first; the old save is kept as
  `run_save.json.bak` until the new file is in place; a load falls back to the backup if the main
  file is gone or broken. A write that fails leaves the old save as it was.
- **When it saves:** every time the map shows (between stops, after the next act's map is made, and
  back from the party screen), right after a stop is chosen (marked "in stop"), and again, still
  "in stop", right after anything inside a stop that cannot be taken back (card #197): an event
  choice (the moment its risk is rolled, and again once its gifts are settled), a shop purchase,
  restock, sale, cleanse or upgrade, and an opened treasure chest (once its prize is settled).
  Run fields hold what the stop already did: `stop_done` and `stop_text` (the event's result or
  the chest's text) and `shop_sold` (the shelf items bought).
- **Continue in a stop starts that stop again from its start**, with the run as it was at the last
  save and the same seed (same zone layout, fight, event, shop, treasure). Never the map: quitting
  never dodges a hard stop. What a stop's screen already settled stays settled, so a random result
  can never be seen and then undone by closing the window: an event comes back on its result page
  (Continue, or Fight if the choice sprang an ambush), a treasure stop on its open chest, a shop
  with the gold spent and the bought items still marked sold (a restock keeps its new shelves).
  Anything else done in a stop and not finished (a zone's fights, items picked up there) is undone.
  Known gaps: a gift that was still waiting for room in the backpack when the window closed is
  lost, and spoils (a guard's, an elite's or a boss's) are not saved while the wear screen is open;
  they are saved the moment the map shows.
- **Deleted** when the run is certain to be over: on a defeat the moment the fight is decided (not
  an escape), on the last act's boss win the same, so closing the game on the end screen cannot
  leave a save that replays a decided fight (`RunState.decides_run`). The win also opens its next
  oath at once (never lowering the highest one open); the end screen still reads "Oath N kept /
  Oath N+1 unlocked" from the value before the unlock. Also deleted when the run is abandoned from
  the pause menu, and when the player starts a new run over it. An abandoned dev sample run
  (`--screen=map` and the like) never touches the real save.
- **Main menu:** a "Continue" row at the top, only when a usable save exists; the cursor rests on
  it until something else is picked. Any build continues a save `RunState.from_dict` accepts
  (card #208, playtest: the game changes almost every day and a content check hid the player's run
  twice); the run plays on with the new numbers. Only a save of another format version is kept
  aside (Continue hidden, the menu says why once per session). A damaged file, or one
  `RunState.from_dict` refuses (unknown gear, items or skills, a wrong party, a stop not on the
  map), is deleted and the menu says so. New Run with any file in the slot (also
  one kept from another build) asks first and then removes it. A co-op save goes through the
  players screen first (pads may have changed). New Run with a save present asks first ("Your saved
  run will be lost"), since the new run overwrites the slot at its first map.
- **Pause menu** (a fight, a zone, the map; local run only): "Save & Quit" sits above "Abandon run".
  On the map it saves the state as it is (and says so if the write failed); inside a stop it keeps the latest stop save. Then back to
  the main menu with the cursor on Continue.
- **Dev tools:** `--save-path=PATH` keeps the save elsewhere and `--continue` continues it at once.
  The autoplay bot never touches the player's save: it saves only when `--save-path` is given.
### 8.15 Oaths (difficulty ladder, card #173, 2026-10-17)

The run's difficulty ladder, like Slay the Spire's Ascension. The game is hard on purpose, so an
oath only ever makes a run harder; nothing in it makes anything easier. The credits end "Keep the
oath", and a run at Oath N is that oath kept.

- **Rule**: oath 0 is the plain run. A run at Oath N has the rules of oaths 1 to N, all at once; each
  oath lists only what it adds, so they stack. `RunData.oaths` holds the ladder in order (Oath 1 is
  index 0); each is an `OathData` (`data/runs/oaths/*.tres`, written by `tools/bootstrap_oaths.gd`).
  An `OathData` is a title, one player-facing line and integer changes that default to "no change":
  `elite_hp_percent_add`, `elite_power_percent_add`, `boss_hp_percent_add`, `boss_power_percent_add`,
  `enemy_power_percent_add`, `enemy_hp_row_add`, `enemy_power_row_add`, `rest_heal_percent_add`,
  `act_heal_percent_add`, `start_gold_add`, `shop_price_percent_add`, `gold_percent_add` (fight pay, floored at 0), `loot_choices_add`,
  `team_gauge_carry_percent_add` and `start_hp_percent` (the lowest one counts, 100 = full).
  `OathData.total(ladder, oath, field)` sums a change over oaths 1..N (a pure function, tested).
- **The ladder** (first guess, tune with play):

  | Oath | Name | Adds |
  |---|---|---|
  | 1 | Thorns | elites +20% HP and +10% power (on top of the elite numbers in tuning) |
  | 2 | Want | shops charge 15% more (items, gear and services; selling is unchanged); fights pay 25% less gold (after charms and gear) |
  | 3 | Embers | the campfire's Rest heals 15 points of percent less (50% becomes 35%) |
  | 4 | the Deep | enemies grow +2% HP and +1% power more per map row (5% becomes 7%, 3% becomes 4%) |
  | 5 | Crowns | guards (mini-bosses) and act bosses +15% HP and +10% power |
  | 6 | Wounds | the party starts the run at 75% HP |
  | 7 | Scarcity | spoils offer one choice fewer (never fewer than one) |
  | 8 | Silence | only half of the team gauge carries into the next fight |
  | 9 | the Long Road | the heal between acts is 25 points of percent less (50% becomes 25%) |
  | 10 | Rot | every enemy +10% power |
  | 11 | the Empty Hand | one Relic slot fewer per hero all run, never under one (phase 17, 8.17) |
  | 12 | Forgetting | heroes get half the Echo points (phase 17, 8.17) |

  The run's start gold is 0 in `tuning.tres`, so "start with nothing" did nothing; Want cuts the gold
  coming in instead (`gold_percent_add`, in `RunState.gold_for`, after charms, gear and the elite
  bonus). `start_gold_add` still works, and is tested, for when the purse is not empty.
- **Where it lives**: `RunState.oath` (kept inside the ladder by `begin`), and the rules in
  `RunState`: `begin` (start gold and HP), `fight_setup` (elite, guard / boss and every enemy's
  power and HP), `enemy_hp_percent` / `enemy_power_percent` (growth per row), `rest_heal_percent`,
  `act_heal_percent`, `loot_choice_count`, `shop_price` and its item / gear / service prices, and
  `team_gauge_carry_percent`. The shop and campfire screens show the changed numbers. Bosses and
  guards still do not grow per row (`run_enemy_scale_bosses`), so the per-row oath touches only the
  ordinary and elite fights.
- **Online**: `to_dict` / `apply_dict` carry `oath` (an int from 0 to the ladder's length, else the
  whole state is refused), so a client plays the host's oath; the host's `run_start` and the lobby
  messages carry it too.
- **Unlock**: per machine, in `user://settings.cfg` (`PlayerSettings.highest_oath_unlocked`, starts
  at 0). Winning a run at Oath N unlocks N+1; it never lowers and stops at the ladder's end
  (`PlayerSettings.oath_after_win`, pure and tested). Online clients unlock on a win too, also a
  friend who dropped into the run late (owner, 2026-10-23, 9.3). Bot runs
  (`--autoplay`) never write the file.
- **Picking**: the players screen of a run (New Run and Host Online, not Practice) has an Oath row
  under the heroes: Left / Right (or Confirm to go round) picks none up to the highest unlocked, and
  the rules of that oath and the ones below it are listed beside the hero cards (newest first), with
  the oath's line under the menu. Online only the host picks; a waiting client sees the host's pick.
  The last pick is kept for the next run in the same session.
- **Shown**: the map's title says "| Oath N" when N is more than 0. The run's end screen says
  "OATH N KEPT" (or "OATH N BROKEN" on a defeat) and, when a win opens a new oath, "Oath N+1 unlocked".
- **Dev switch**: `--oath=N` starts the bot's run (`--run`, or an autoplay host) at oath N (kept
  inside the ladder) and unlocks up to N on the players screen (`--screen=oaths` shows that
  screen). The `AUTOPLAY_RESULT run_...` line ends with `oath=N`.
- Tests: `tests/unit/test_oaths.gd`.

### 8.16 Rot-touched gear (card #198, 2026-10-17)

Strong pieces with a price, in the spirit of Slay the Spire's boss relics and Expedition 33's Pictos:
each one makes a hero clearly better at one thing and clearly worse at another (or, for one piece,
only works in a risky state). They are for a party that wants the game harder still, not an
upgrade to take blindly.

- **Data**: a `GearData` with `rot_touched = true` (its own violet name colour, `GearData.ROT_TOUCHED_COLOR`, and
  the tag "rot-touched" in the loot, shop and party screens), an `effect` / `amount` as before and a
  **drawback**: `drawback` (any `GearData.Effect`) plus `drawback_amount` (0 = none). A drawback is
  the effect worn as a loss: "Max HP -15%", "Enemy hits +10%" (a Tough drawback), "Parries give 1
  less AP". `GearData.contribution(effect)` is what a piece adds to one effect, signed; `RunState.gear_amount`
  and `RunState.passives` sum it, so a drawback on the same key as an upside simply takes away (a
  total of 0 is dropped). `GearData.effect_line()` is the one-line text; every piece also has a
  hand-written `description` that says both halves in plain words. Twelve pieces are written by
  `tools/bootstrap_rot_gear.gd` into `data/gear/` and the run's gear list.
- **New effects** (appended to `GearData.Effect`, so older files keep their numbers) and the
  `Passive` keys the engine runs for them (all integers, signed, add up across pieces):
  `HEAL_TAKEN` (healing the hero receives, in `_heal` and in `RunState.heal`), `KILL_HEAL` (a
  hero's hit that downs an enemy heals them a share of max HP, in `_deal_damage`), `LOW_HP_POWER` (power
  while HP is under `tuning.rot_low_hp_percent`, 30, in `_power_of`; a basic attack now also uses
  `_power_of`), `DODGE_AP` and `PARRY_AP` (AP per defence on top of `ap_per_parry`, never below 0),
  `THORNS` (an enemy whose hit lands takes that share of the damage as a `damage` event with cause
  `thorns`; nothing for a defended hit; an enemy killed this way voids its remaining prompts like
  after a counter), `GAUGE` (the team gauge a hero's skills and follow-ups fill), `ROT` (the
  existing start-of-turn HP loss, now also from gear and added to the rotten items' rot), `CRIT`
  (critical hit points from gear; Luck adds to it). Existing keys can now be negative: `TOUGH` below
  0 makes enemy hits land harder, `START_AP` below 0 starts a fight with less AP (never below 0),
  `COUNTER`, `PERFECT_PRESS`, `EXPOSED`, `HEAL` below 0 weaken them. Two effects are run-only:
  `REST_HEAL` (the wearer's share of the campfire's Rest, `RunState.rest_heal_percent_of`; the Rest
  screen names a hero who heals less) and `WIN_WOUND` (after each fight won the wearer loses that percent of max HP for good,
  through `lose_max_hp`, so the same floor as events: `event_max_hp_floor_percent`).
- **The twelve**:

  | Piece | Rarity | Upside | Price |
  |---|---|---|---|
  | Rotten Crown | legendary | Power +35% | healing received -40% |
  | Gravebound Ring | rare | Counters +80% | max HP -15% |
  | Hunger Charm | rare | each kill heals 8% max HP | the campfire's Rest heals the wearer nothing |
  | Last Ember | rare | Power +40% while under 30% HP | (the condition is the price) |
  | Ash Veil | rare | each dodge gives +1 AP | a parry gives no AP |
  | Thorned Gauntlet | rare | enemies that hit the wearer take 30% of the damage back | the wearer takes 10% more |
  | Oathbreaker's Band | legendary | +2 AP at fight start | lose 5% max HP after each fight won |
  | Chain of Silence | rare | the wearer's skills and follow-ups fill the team gauge 50% more | start fights with 1 AP less |
  | Bloodletter's Fang | rare | critical hit chance +25% | lose 4% max HP at the start of each of the wearer's turns (never below 1 HP) |
  | Hollow Mantle | rare | enemy hits deal 25% less | speed -10 |
  | Pale Tithe | rare | perfect skill presses +40% | the heals the wearer gives are 50% weaker |
  | Plague Bell | rare | hits on Exposed enemies +90% more | power -10% |

  The first guess for every number; tune from play. A drawback like "the wearer cannot use skills
  costing 1 AP" (the card's idea for Chain of Silence) was not built: the engine checks AP cost in
  several places and the fight menu in more, so it would have changed the deterministic core and the
  HUD for one piece; "starts fights with 1 AP less" puts the same pressure on through data.
- **Where they appear**: spoils (elites and act bosses, `RunState.loot_choices`) offer
  `tuning.rot_gear_spoils_count` (1) rot-touched pieces among their `run_loot_choices` (3), listed last, and
  the ordinary choices come from the ordinary pool; the guarantee needs room, so with one choice
  (the Oath of Scarcity at its floor) the choice stays ordinary, and it falls back to ordinary gear when the run
  has no unworn rot-touched piece left. `run_spoils_min_rarity` still applies to both. Shop shelves
  and chest prizes draw from all gear, but a rot-touched piece weighs `tuning.rot_gear_weight_percent` (35%)
  of an ordinary one there, so shops sell them rarely. All picks are seeded per stop as before.
- **The bot** (`GearBot`, `scripts/run/gear_bot.gd`, pure): the `--run` bot takes the rarest spoil, and
  a rot-touched piece (scored higher) unless its drawback is on Max HP, Power, Tough, healing received,
  rot, wounds or Rest, which it refuses. If a refused piece reaches it another way (a chest) it sells
  it on the spot instead of wearing it (`PartyScreen.auto_settle`). The run prints `Run loot: took <id>`.
- **Online / save**: gear is saved and sent by id as before, so nothing new is stored; wounds change
  `max_hp_percent`, which is already in the run save.
- Tests: `tests/unit/test_rot_gear.gd` (each new passive in the engine, each piece's numbers and
  drawback on the run side, spoils, shops, the bot, the Tonic fix, determinism, saving).

### 8.17 Relics and Echoes (phase 17, cards #212 to #220, built 2026-10-18, waiting for playtest)

Phase 19 (card #263) added three Relics against marks (Wardstone, Bitter Root, Cleansing Bell;
2.17), dropped by the new monsters, which also drop older Relics (34 Relics in the run).
Phase 20 (Relic balance, 2026-10-19, user picks): 16 more Relics (50 in all, #242, table below),
drops 25% rarer (`relic_drop_percent` 10% to 8%, #243), and the **Relic bag** (#265, below), which
replaces each hero's ordered picks. **Phase 21 changed the levels, the Echoes and the bag: see 8.19**
(Echoes learned for good across runs, levels last one run, the bag from 3 to 6). What follows is the
phase 17 to 20 design where 8.19 does not say otherwise.

The user's idea: make Rotsworn a roguelite and keep it hard. The run's gear became **Relics** the
player keeps forever (Expedition 33's Pictos, renamed), and a Relic worn for a few won fights
teaches its **Echo** (E33's Lumina, renamed) for the rest of that run only. Only the Relics and
their levels carry over; every run learns its Echoes again from zero (user pick, 2026-10-18). This
replaces "nothing carries over between runs" (#139, 2026-10-14). The rule behind every number:
Relics give more choices, not just more power; the oaths keep the game hard. Every number is a
first guess in `tuning.tres` (group "Relics and Echoes") or the Relic's own file; tune from play.
In the code a Relic is still a `GearData` and the worn ones `RunState.gear` (the names from before).

- **Relics** (`GearData`, `data/gear/`): the 25 gear pieces (8 Part B, 8.16) are the first Relics;
  the 12 rot-touched ones keep their drawbacks. New fields (group "Relic"): `stat` (an attribute),
  `stat_points` at level 1 and `stat_points_per_level` (1), and `echo_cost`. Common Relics give 2
  points, rare 3, legendary 4; Echoes cost 1, 2 and 3 by rarity. The stat line counts on top of the
  points a hero spent (`RunState.attribute_total`, `relic_stat`), so it reaches max HP, power,
  speed, Defense and crits like spent points. The Echo Charm is now the **Rebound Charm** (its id
  stays `echo_charm`). `tools/bootstrap_relics.gd` writes the stat lines, costs and drops.
- **The collection** (`RelicCollection`, `scripts/relics/`, pure, tested): Relic id -> level, and
  the **Relic bag** (card #265): up to `relic_bag_size` (10) Relic ids the team brings into the next
  run, picked on the main menu's Relics page (Confirm puts a Relic in or takes it out; the right side
  shows the bag as "4 / 10" and its cards). A Relic found for the first time goes into the bag by
  itself while it has room (user pick 2026-10-19). A file from before the bag gets its heroes' old
  picks as its bag. Relics left out of the bag stay home and cannot be used in that run. `RelicFile` keeps it in
  `user://progress.json` (versioned, written to a temp file first, `.bak` kept, a load falls back to
  it; a file of another version is left alone). Taking a run in (`merge`, `RelicFile.bank`) keeps
  the higher level of each Relic, so banking twice changes nothing.
- **A run** (`RunState`): `relics` (id -> level: the bag's at the start plus what the run finds;
  the whole team shares them, any hero wears any of them), `relics_at_start` (the whole collection,
  bag or not: the end screen's line, and a find of a Relic left at home counts as a copy of it:
  `known_level`), `guards_beaten`, `mastery` (id -> points this run) and `echoes` (per hero,
  the Echoes worn), all in `to_dict` (saved and sent online). A save from before phase 17 still
  loads: what it wears joins at level 1 and its slots count one guard beaten. `RunState.begin`
  takes the collection; online clients get the host's run state instead.
- **Where Relics come from**: every monster lists `EnemyData.relic_drops` (2 or 3 Relics; the deep
  monsters, guards and bosses the rare and legendary ones; every Relic is dropped by someone). A won
  run fight gives each beaten enemy with drops a `relic_drop_percent` (8%, was 10% before #243) chance of one of them,
  seeded by the stop, the fights won and the stops visited (`RunState.relic_drops`), so the end
  screen (`win_relic_lines`), the run and every machine agree. Spoils (guards, elites, bosses) are
  still "pick 1 of 3", now of Relics that are new or below their top level; shops sell 2 and chests
  hold them the same way. A copy weighs `relic_copy_weight_percent` (50%) of a new Relic in those
  picks, so new ones turn up more. The spoils screen tags each choice "New" or "Lv 1 > 2".
- **Relic levels** (`RunState.add_relic`): a new Relic joins at level 1, a copy raises its level up
  to `relic_max_level` (5), a copy past that pays `relic_spare_gold` (30) gold. Nothing is ever sold:
  a Relic taken off, or one nobody wears, waits in the run's Relics.
- **Slots open during a run** (`open_relic_slots`): `relic_slots_start` (1) at the start, one more
  after the first guard, one more after act 1's boss (never past `run_gear_slots`, 3). Nothing goes
  on by itself (card #265): at the start of a run the party screen opens on the Relics tab so the
  player equips before the first fight, and the fight's end screen says "A Relic slot opens: Y to put
  a Relic on" when a guard or act 1's boss opens one (user pick: a note, not a screen). A shut slot
  shows a lock and says what opens it. Bots fill their bag with their best Relics
  (`RelicCollection.fill_bag`, GearBot's score) and their open slots the same way (`RunState.auto_wear`).
- **Mastery, per run**: E33's "win 4 battles" kept inside the run. Every worn Relic gets points per
  won fight: `mastery_fight` (1), `mastery_elite` (2), `mastery_guard` (3), `mastery_boss` (5); at
  `mastery_needed` (4) its Echo is learned until the run ends. Lost or escaped fights teach nothing.
  The fight's end screen says "Echo learned: X".
- **Echoes**: a learned Relic's effect (and a rot-touched one's price) without its stat line, worn
  by any hero (`set_echo`, `effect_sources`). Each hero has `echo_start_points` (0) plus
  `echo_points_per_level` (1) per level up; an Echo costs its `echo_cost`. An Echo of a Relic the
  hero also wears counts once (putting the Relic on takes its Echo off). Echoes, their bars and the
  points start over every run; the backpack, skills, attributes and gold reset as before.
- **Screens** (user, 2026-10-18: "it should look similar to Expedition 33" for Pictos and Lumina):
  - **The Relics page** (`RelicsScreen`, `scripts/menu/`), like E33's Pictos page. Left: every Relic
    as a slanted card in two columns (its diamond, name, "Lv" and level, and a small face of the hero
    who has it; cards on the shown hero in purple), sorted by level, name or rarity (X / R, a button
    chip in the header with "Found N of 25"). Right: the hero's face and name (LB / RB changes hero)
    and their three slots as big cards (big diamond, name, stat line, level, and the Relic's text).
    Under the grid: everything about the Relic under the cursor. Up / down picks a slot, Confirm
    opens the grid for it, Confirm in the grid puts the Relic on (one another hero has moves over),
    X / R takes it off, Back goes back to the slots. Since phase 20 this page is only the main
    menu's **Relics** row, and its right side is the Relic bag (card #265): Confirm on a card puts it
    in the bag or takes it out (Relics not found yet show as "???" with the monsters that drop them).
    In a run, Relics are equipped on the Y screen's Relics tab (8.18).
  - **The Echoes page** (`EchoesScreen`, from the Y screen's Hero tab Echo box, 8.18), like E33's Lumina page.
    Left: tabs All, Offensive, Defensive, Support (LT / RT; `GearData.category()` from the effect),
    the sort (X / R: name or cost), and the learned Echoes in three columns, each with its diamond and
    cost (purple while this hero wears it, dim while they cannot); under them the Echo under the
    cursor (what it does, who wears it, why it cannot go on) and what the worn Relics are still
    learning. Right: the hero (LB / RB), their combat stats (Health, Attack Power, Speed, Critical
    Rate, Defense), their attributes as a radar (`AttributeRadar`, with the Relics' stat lines), the
    Echoes they wear and the big "Available Echo Points" box. Confirm puts an Echo on or takes it off.
  - **The icons** (`RelicIcon`, `scripts/relics/`; card #271, phase 20): the frame's shape says the
    category, so it reads without colour and at 26 px: a spearhead with a blade for offensive (ember
    orange), a heater shield with a boss for defensive (steel blue-grey), a round seal with a leaf
    for support (moss green); none of them a hero colour. The edge is the rarity colour (violet with
    a drip for rot-touched); a picture in `GearData.icon_path` replaces the glyph. Optional gold
    level pips along the bottom, a hero's initial in a corner (who wears it), a gold glow for the
    cursor, and neutral rounded-diamond frames for an empty slot (a plus), a locked one (a lock) and
    a Relic not found yet ("?").
  The run's end screen says what the run keeps, won or lost ("Relics kept forever. New: ... Up a
  level: ...", `RunState.relic_gain_line`, from `relics_at_start`, which the run save keeps).
- **Reset progress** (Settings > Game, main menu only, asks twice): deletes the Relic file, sets the
  unlocked oaths back to none (`PlayerSettings.reset_oath_unlocks`), clears the Fight Rush records
  (`PlayerSettings.reset_rush_records`, phase 25, 8.21) and deletes a saved run. Settings, controls
  and the Journal stay. A dev screen never wipes anything. The first question's detail is two lines
  (`SettingsScreen.RESET_DETAIL`): "Relics and their levels, unlocked oaths, Rush records and a saved
  run are wiped." / "Settings, controls and the Journal stay." (one line with the Rush records ran
  past the screen at the larger text sizes; a test checks it fits at every size).
- **Banking and Save & Quit**: Main banks the run's Relics when the map shows (the run saves), when a
  stop settles something (`_save_stop_progress`), and when the run ends (won, lost or abandoned).
  Quitting and continuing a stop replays it from its saved state, and the merge keeps the higher
  level, so it can never farm a copy. Mastery and Echoes are run state, saved with the run.
- **Online**: everyone plays with the host's collection (user pick: simpler); only the host banks,
  so a client's own collection does not grow online. New ops (any player): `wear` (a Relic the run
  has, into an open slot), `take_off`, `echo` (`slot`, `relic`, `on`).
- **Harder runs**: every enemy in a run fight has `enemy_power_base_percent` (105) power (practice
  fights keep their data), and two oaths top the ladder (8.15): **the Empty Hand** (Oath 11,
  `OathData.relic_slots_add` -1: one Relic slot fewer all run, never under one) and **Forgetting**
  (Oath 12, `echo_points_percent_add` -50: half the Echo points).
- **Tutorial**: lesson 6, "Relics" and "Echoes", two cards to read at the end of the tutorial fight
  (goal `read`, `TutorialGoals.READ`: the fight stays paused and closing the card moves on). The
  interactive hit-type lessons of card #206 come later.
- **Bots** never read or write the player's Relic file (like the oaths and the Journal): a bot run
  starts with no Relics, `--relics=all` gives every Relic at its top level (balance runs),
  `--relics-path=PATH` lets a bot use and bank into its own file. The bot wears the Echoes it can,
  cheapest first, passing over prices GearBot refuses (`RunState.auto_echoes`). The
  `AUTOPLAY_RESULT run_...` line ends with `relics=N echoes=M`. `--screen=relics`,
  `--screen=echoes` and `--screen=party_relics` (the Relics page in a run) open those pages on
  samples (for pictures).
- **Relics from the old charms** (card #240, user 2026-10-18: the backpack's charms were a third
  buff system, 8.1): six Relics with effects no Relic had (or a rot-touched price), 31 Relics in all,
  each dropped by monsters like the others (`tools/bootstrap_relics.gd` writes them):

  | Relic | Rarity | Effect | Stat line | Echo |
  |---|---|---|---|---|
  | Heartleaf | common | healing received +25% | Vitality +2 | 1 |
  | Wake Root | rare | +1 AP per parry | Agility +3 | 2 |
  | Ember Stone | common | critical hits +10% | Luck +2 | 1 |
  | Rain Pouch | common | the campfire's Rest heals the wearer 50% more | Vitality +2 | 1 |
  | Black Ichor | rare, rot-touched | power +25%, lose 3% max HP each turn | Might +3 | 2 |
  | Gravebloom | rare, rot-touched | +2 AP at fight start, lose 2% max HP each turn | Agility +3 | 2 |
- Tests: `tests/unit/test_relics.gd`.
- **More Relics** (phase 20, card #242, user approved the list 2026-10-19): 16 more, 50 in all, each
  dropped by one or two monsters (commons by early ones, rares by deep ones, legendaries by guards and
  bosses; `tools/bootstrap_relics.gd` writes them). Eight have new effects (`GearData.Effect`
  FULL_HP_POWER, KILL_AP, WIN_HEAL, START_EMPOWERED, START_REGEN, STAGGER_DAMAGE, CRIT_DAMAGE,
  PARRY_HEAL; the fight ones are `Passive` keys, WIN_HEAL is a run effect after `_wound_winners`):

  | Relic | Rarity | Effect | Stat line | Echo |
  |---|---|---|---|---|
  | Brimming Cup | rare | power +20% while at full HP | Might +3 | 2 |
  | Reaper's Coin | rare | +1 AP for each enemy downed | Luck +3 | 2 |
  | Victor's Wreath | common | heal 10% max HP after each won fight | Vitality +2 | 1 |
  | First Light | common | every fight starts Empowered | Might +2 | 1 |
  | Mossbed | common | every fight starts with Regen for 2 turns | Vitality +2 | 1 |
  | Breaker's Maul | rare | +25% damage to Staggered enemies | Might +3 | 2 |
  | Butcher's Edge | legendary | critical hits deal +50% | Luck +4 | 3 |
  | Still Water | rare | each perfect parry heals 3% max HP | Defense +3 | 2 |
  | Bramble Coat | common | attackers take 15% back | Vitality +2 | 1 |
  | Fox Step | common | +1 AP per dodge | Agility +2 | 1 |
  | Marrow Charm | common | healing received +15% | Defense +2 | 1 |
  | Bone Whistle | common | Exposed bonus +25 | Might +2 | 1 |
  | Tallow Candle | rare | Second Wind at 15% | Vitality +3 | 2 |
  | Hollow Drum | rare | team gauge fills 25% more | Might +3 | 2 |
  | Sour Milk | rare, rot-touched | speed +25, healing received -30% | Agility +3 | 2 |
  | Crown of Thorns | legendary, rot-touched | attackers take 60% back, enemy hits +15% | Defense +4 | 3 |

  Tests: `tests/unit/test_more_relics.gd`.
- **Later**: more Relics still (E33 has close to 200), and phase 21's rethink of levels and Echoes.

### 8.18 The Y screen (phase 20, card #270, done 2026-10-19)

The owner found the party screen "too cluttery" and hates text. Three concepts were drawn (tabs, one
quiet page, one hero at a time); the owner picked **tabs**, plus the one-page concept's info strip and
shape-coded Relic icons (2026-10-19). `PartyScreen` (`scripts/run/party_screen.gd`) keeps its outside
(setup with a note and something new in hand, refresh, auto_settle, open_relics / open_attributes /
open_skills / open_echoes, shop_mode, close_when_settled, the signals) and hosts four tabs, each a
`PartyTab` (`scripts/run/party_tab.gd`: setup, refresh, shown, handle_input, busy, hints, info,
badge; signals changed, op_requested, toast):

- **Tab bar** (top): LB, four slanted plates with a glyph and one word (Relics, Bag, Hero, Skills;
  Skills only when a hero has a tree), RB, and the gold (coin + number) top right. LB / RB (Z / C,
  actions item_turn_left / item_turn_right) switch tabs unless the tab is busy (an item or a Relic in
  hand, a menu or a prompt open); a click on a plate does too. A gold round badge on a tab counts
  what waits there (Relics: open empty slots while the bag has Relics nobody wears; Hero: attribute
  points; Skills: skill points). The screen opens on the last tab used, on Relics with a new Relic
  in hand, on Bag with a new item in hand or in a shop.
- **Info strip** (bottom, `tab.info()`): never moves or hides. The thing under the cursor: a big icon
  (a RelicIcon, an item's sprite or a glyph), its name in its colour, a few chips (glyph + short
  text: level, stat line, wearer, AP cost, sell price, refund...), its text on at most two lines (a
  skill's whole text, perfect-press bonus included), and for a Relic still teaching its Echo a small
  segment bar. A refusal (a shut slot, a hero too wounded) shows there until the next press.
- **Centred**: everything placed on the 1920 x 1080 canvas sits in one centred frame, so a wider or
  taller window (aspect expand, a maximised window) keeps it centred; backdrop and footer stay full
  width.
- **Toasts** replace the old note line: an icon and a word or two under the tab bar
  (`party_toast_s`, `party_toast_fade_s` in combat_visuals.tres), for example a Relic's icon and
  "Alder" when it goes on, a coin and "+12" when something sells. Callers pass short words too:
  loot, gifts and shop Relics "New", "Lv 3" or "+30" (`RunState.relic_find_short`) with the Relic,
  a find that does not fit "No room" with the item (in a shop with a "Refund" chip, and the leave
  question says the gold comes back), the shop's sell button "Sell" with a coin.
- **Footer**: at most four labelled hints: the tab's own (`tab.hints()`, at most three when not busy)
  plus LB / RB "Tabs" (a chip pair with one label counts once, `PartyScreen.visible_hints`).
- **Relics tab** (`RelicsTab`): each hero as a slanted row (face, name, level, HP bar and numbers,
  power and speed glyphs) with their three Relic slots as big icons with level pips and the name
  under them; the team's shared Relic bag (8.17) on the right as a 6 x 4 grid of icons (scrolls),
  each with level pips and the initial of the hero wearing it, worn ones dimmed and listed after the
  free ones; filter chips All / offensive / defensive / support with counts (X / R in the bag).
  Up / down a hero, left / right a slot, right past the last slot into the bag. Confirm on an open
  slot jumps into the bag to pick for it; Confirm on a Relic there puts it on (swapping it from
  another hero). X / R on a worn Relic lifts it to another slot or hero; carried into the bag and put
  down it comes off. Back steps back; a new Relic from loot is put on a slot or left in the bag.
- **Bag tab** (`BagTab`): the backpack (scaled to fit when 7 rows are taller than the page) with the
  old rules (item menu Use / Sell / Move / Throw away, combine, turn, swap, leave behind), the heroes
  as small faces with HP on the left (who an item is used on; greyed when they cannot take it), and
  free cells and curses as glyph + number on the right.
- **Hero tab** (`HeroTab`, replaces the Attributes page): a rail of faces (LT / RT change hero), the
  hero's name, level and XP bar, points waiting, the five attributes as rows (glyph, points, the stat
  now; right / Confirm adds, left takes back, X / R resets after asking, the too-wounded refusal on
  the strip), combat stats as glyph + number, the radar, and a small self-contained Echo box (free /
  total Echo points, worn Echoes) that opens the Echoes page (`EchoesScreen`, unchanged until
  phase 21 decides about Echoes).
- **Skills tab** (`SkillsTab`, replaces the Skills page): the hero (LT / RT), the loadout sockets,
  and the tree as tiles whose frame says the state (gold brought, lit known, green plus can learn,
  lock locked) with AP pips; Confirm learns, brings or leaves behind as before.
- Helpers: `UiGlyph` (`scripts/menu/ui_glyph.gd`), small drawn icons (heart, sword, bolt, chevrons,
  shield, star, leaf, coin, bag, pouch, lock, plus, skull, person, branch, gem, up, echo) and
  `attribute_glyph()` so each attribute has the same picture on every page.
- Tests: `tests/unit/test_party_screen.gd`, `test_hero_tab.gd`, `test_skills_tab.gd`,
  `test_relic_icon.gd`.

### 8.19 The roguelite pass (phase 21, talked through 2026-10-19 in #267 and #272)

The owner's worry (#272): Relic levels kept forever made the game easier the more you played, and
relearning every Echo every run was busywork. A design panel (four studies, four designers, three
judges) proposed the cards below; the owner picked them on 2026-10-19. The rule behind them: what
carries between runs gives **choices, not stats**; the oaths keep the game hard.

**Echoes learned for good (#280, built).**

- **Between runs** a Relic keeps two things: found, and its **Echo pips** (`RelicCollection.found`,
  `pips`). Its level is not kept any more.
- **Pips**: every worn Relic gets `mastery_fight` (1), `mastery_elite` (2), `mastery_guard` (3) or
  `mastery_boss` (5) pips per won fight, run after run (`RunState.pips_at_start` from the collection +
  `mastery`, this run's; `mastery_of` is the sum, never past `mastery_needed`, 12, about one act).
  Lost or escaped fights teach nothing. Full pips: its **Echo is learned for good**.
- **Wearing an Echo** (owner's pick A): any learned Echo can be worn in any run, whether the run has
  its Relic or not (`learned_echoes` is every learned one), paid with Echo points as before (0 at the
  start of every run, +1 per level up, half under the Oath of Forgetting). **One hero per Echo**
  (`echo_wearer`; "Alder wears this Echo."); another hero may still wear the Relic itself. An Echo
  of a Relic the hero wears counts once, as before.
- **Echo prices by strength, not rarity** (`tools/bootstrap_relics.gd`): extra AP on every dodge or
  parry (Fox Step, Wake Root) 3, +2 AP at fight start (Oathbreaker's Band) 4 and Gravebloom 3, big
  all-round effects (Iron Charm, Whetstone, Thick Hide, Quick Boots, War Drum) 2, small or narrow ones
  1. First guesses; tune from play.
- **Relic levels last one run**: a Relic joins a run at level 1 (from the bag or found), a copy found
  in the same run raises it up to `relic_max_level` (3), a copy past that pays `relic_spare_gold`
  (30). Spoils, shops and chests offer any Relic below level 3 in this run, so they never run dry. A
  Relic found before but left at home that turns up joins at level 1, tagged **Home** (not "New"); it
  levels nothing at home (`RunState.is_home`).
- **The end screen** shows what the run keeps as Relic icons tagged New and/or with the Echo mark,
  and nothing when there is nothing (phase 22, 7.13; `relic_gain_line` is the same rule in words). A fight's end screen says "Echo learned for good: X".
- **Banking** (`Main._bank_relics`, `RelicFile.bank(found, pips, path, tuning)`): the run's Relics
  are found, each Relic's pips become the higher of home and run, so banking twice or after Continue
  replays a stop adds nothing.
- **Old files and saves**: `RelicCollection.FORMAT_VERSION` 2; a format 1 file (phases 17 to 20)
  loads, every Relic in it is found and each old level above 1 is 3 pips (level 5 = learned), and it
  is written back as format 2. A run saved before phase 21 (no `pips_start`) loads with its levels cut
  to 3 and its mastery scaled from the old 4 to 12, so an Echo it had learned stays learned.
- **Screens**: the main menu's Relics page shows each card's "Echo 7/12" (gold when learned) instead of
  a level and sorts by it; the detail says how to learn it. In a run the cards keep "Lv"; the Relics
  tab's info strip shows the pips bar; the Echoes page lists every learned Echo. The tutorial's Relics
  and Echoes cards say the new rules.
- **Bots**: `--relics=all` finds every Relic with its Echo learned (`RelicCollection.all_of(gear,
  needed)`).

**The Relic bag starts at 3 and grows to 6 (#266, built).** `RelicCollection.bag_size(tuning)`:
`relic_bag_start` (3) + one for every `relic_bag_echoes_per_slot` (5) Echoes learned, never past
`relic_bag_max` (6). A run takes at most that many from the bag; a bag from before it shrank keeps its
first Relics (`trim_bag`, when the Relics page opens). The page shows "2 / 3" and "+1 for every 5
Echoes learned" while it can still grow. New finds still join the bag while it has room.

**Friends keep their finds online (#281, built).** Replaces 8.17's "only the host banks". The run
still plays with the host's bag and the host's learned Echoes (the host's `pips_at_start` goes to
every machine in `to_dict`). Each online friend's game loads its own collection when the host's
`run_start` arrives (`Main._own_start`) and banks into its own file whenever the host's map or run
end shows on it: the Relics the run has, and this run's pips (`RunState.mastery`, kept whole up to
`mastery_needed` even past what the host still needed) on top of their own
(`RunState.pips_totals_from`). Their end screen says what they keep, measured from their own
collection (`relic_gain_line_since`). Same rules as the host: never in the tutorial or a dev screen,
a bot only with `--relics-path`. A friend who dropped in mid-run (phase 25, #304) keeps only the
Relics and pips the run found after they joined (9.3).

**Alder's pack with pockets (#282, built).** The grid backpack (8.1) lost its job when the charms
went: its shapes, turning and moving were busywork for seven kinds of supplies. Now:

- **Pockets** (`Backpack`, pure): `tuning.backpack_pockets` (6) pockets in a row, one item each,
  whatever its shape; a Bigger Pack adds one, up to `backpack_max_pockets` (8). Ops and saves keep
  their old shape (cells are `Vector2i(pocket, 0)`). An older save's grid becomes pockets, its items
  in reading order, 6 pockets plus one per Bigger Pack row, never fewer than it holds.
- **Treasure** turns into gold the moment it is found (`RunState.add_item`: what selling it paid,
  `treasure_gold`; "Silver Ring: +20 gold", `find_text`). Curses still go in a pocket, so a curse now
  costs a pocket too; a shop's Cleanse or throwing it away gets rid of it, as before.
- **The Bag tab** (`BagTab`, `BackpackGrid`): Alder's pack art (`ui/backpack_5.png`) with its pockets
  sewn on the lining, two to a row (`combat_visuals.tres` `backpack_pocket_columns`,
  `backpack_lining_art_px`, `backpack_pocket_gap_art_px`), the pockets a Bigger Pack would still add
  sewn shut. Arrows move between pockets; Confirm on an item opens Use / Combine (with another of the
  same at the same level) / Sell (in a shop) / Throw away. A new find with no free pocket opens the tab
  with it in hand: Confirm puts it in a free pocket, combines it with the same item, or swaps it for
  the item in that pocket (asked first; the old one is thrown away); Back leaves it behind (asked).
- **Gone**: the nine faded charm files (phase 17 kept them only for older saves) and the Glossary's
  grid words; the Glossary's gear topic now says Relic, Pack and Curse.

**Defence counts, and pays (#283, built).**

- `FightRecap` also counts each hero's own defence (`heroes`: per party slot [parried, dodged,
  jumped, hits taken]); `RunState.finish_fight(..., recap)` adds it to the run's `defence` (won, lost
  or escaped), saved and sent online.
- **Flawless**: a guard or an elite won without a hit taken (`RunState.is_flawless`) sets
  `RunState.flawless`, and the spoils right after it offer one more Relic (`loot_choice_count` + 1).
  The fight's end screen says "Flawless! One more spoils choice." Any other fight, or the next stop,
  clears it.
- **The run end** shows a row per hero: face, the player number in co-op ("P2"), shield (parried),
  chevrons (dodged), up (jumped) and a red sword (hits taken), and a gold star on the best defender
  (the most hits answered, then the fewest taken; `RunState.best_defender`).
- **The Rot Journal** counts only this machine's own heroes' answers online
  (`JournalTally.local_slots`, set by the fight from the roster); one machine (solo or local co-op)
  counts every hero as before.

**One more run, together (#284, built).** The run end's footer is Confirm "Again" and Back "Main
menu" (`RunEndScreen.again` / `done`). Again (`Main._play_again`) goes to the players screen with
the same seats, the same bag and the last oath pick. Online the host stays hosting (the game reopens
to joins) and sends "again": every friend still on the run end goes to their players screen and waits
for the host's Start (`_show_host_lobby`, `_show_client_lobby`); a friend who presses Again first
waits there. Main menu leaves as before (online, it ends the game for everyone when the host does).

**A pact at the start (#285, built).** Before the first stop of a run that is not the player's first
(the bag's collection had found something; `RunState.pact_pending`, saved and sent online), "The
Crossroads" shows on the "?" event screen (its picture, story, and each choice's price and reward
written out): `tuning.run_pact_choices` (3) of `RunData.pacts`, picked by the run's seed
(`RunState.pact_event`), or Leave. The host picks for the whole party; online friends watch. Taking
or leaving it goes on to the party screen's Relics page (or the map). The six pacts
(`data/runs/pacts/`, written by `tools/bootstrap_pacts.gd`; first numbers):

| Pact | Gift | Price |
|---|---|---|
| Blood for gold | +120 gold | everyone -10% max HP for good |
| Feed the hungry Relic | a rare Relic | the Rotting Heart curse |
| Borrow years | +60 XP each | everyone loses 40% HP |
| Take the crown of ash | a legendary Relic | a hero you pick -25% max HP for good |
| Drink the storm | full team gauge and a Bomb | everyone loses 20% HP |
| Take the rotten purse | +200 gold | the Grave Moss curse |

A deal can now give a Relic (`ZoneOfferData.relic_rarity`: one of at least that rarity the run
lacks or can still level, seeded). The bot reads the shown event (`EventScreen.event`).

**A map with a dare (#286, built).** After the map's types and zones are set (so a seed's paths stay
as they were; `RunMap._vary_rows`, `_crown_elite`, `_fix_zones`):

- The campfire row is one row earlier `run_rest_row_shift_percent` (50%) of the time (then one stop
  sits between the campfires and the boss), and the treasure row moves up to `run_treasure_row_spread`
  (1) rows either way. Rows that give up their campfires or chests get middle stops under the old
  rules (never the same shop, campfire or elite twice in a row, no campfire right before the campfire
  row, a shop somewhere, no zone twice in a row). This replaces 8's "the row before the final fight is
  all rests" and 8.9's fixed treasure row.
- Every act with elites has at least one elite stop, and one of them wears the **rot crown**
  (`stop.crown`): its enemies get `crown_elite_hp_percent` (130%) HP and `crown_elite_power_percent`
  (115%) power on top of the elite numbers, and its spoils always list an ordinary legendary Relic
  first while the run has one to gain (`RunState.is_crowned`, `loot_choices`). The map draws a small
  gold crown over it (`map_visuals.tres` `crown_color`) and names it "Crowned elite".

**No free stops (#287, built).**

- **Treasure**: two chests, one to open (`RunState.open_treasure`, seeded per stop). The plain one
  holds `run_treasure_gold` and a rare or better item; the rotten one a rare or better Relic, but
  `rotten_chest_curse_percent` (30%) of the time a curse comes with it and `rotten_chest_fight_percent`
  (20%) of the time an ambush from the act's pool (no spoils; Fight goes into it,
  `Main._on_treasure_done`). The bot opens the rotten one only while healthy.
- **Shrines**: the three free offers got a price: Healing Spring 30 gold, War Idol everyone loses 10%
  HP, Old Pilgrim 20 gold (`data/offers/`).
- **The campfire before the boss** (the act's campfire row, `RunState.is_watch_fire`) offers Rest,
  Keep watch (the team gauge is full, `keep_watch`) or Sharpen (every hero starts the boss fight with
  `sharpen_ap` (1) more AP, `sharpened`, saved; used up by the boss fight). Other campfires keep Rest,
  Train and Upgrade. The bot keeps watch when it does not need to rest.

**After the build** (2026-10-19, a review by three reviewers, each finding checked by a skeptic): an
online friend who drops and takes their seat back keeps the collection taken at the run's start
(`Main._own_start_seed`), so the run's pips are never banked twice; a friend can press Again or Main
menu on the run end; Again in local co-op keeps every seat whoever presses it, and online it lets go
of a seat still away; a friend's players screen after Again shows the host's oath; the treasure screen
shows the chest that was opened (`RunState.stop_rotten`, saved and sent); a run saved before phase 21
keeps its map (`RunState.map_rules` 1, `RunMap.generate(..., moving_rows)`), gets its pips at the
start from home on Continue, and fits its HP to the new max; Continue during the pact shows the pact
again; `tools/bootstrap_items.gd` no longer brings the faded charms back. Not fixed (small): an old
save may keep two heroes on one Echo until they change it; closing the game during the final boss's
victory before the run end shows can lose that fight's pips.

Dev screens for pictures: `--screen=pact` (the Crossroads on a sample run) and `--screen=run_end` (a
lost run's end with defence rows).

Tests: `tests/unit/test_relics.gd`, `test_backpack.gd`, `test_roguelite.gd`, `test_fight_recap.gd`.

---

### 8.20 Weather and time of day (phase 24, card #303)

Each zone visit has a weather, or none, picked from the visit's seed (`WeatherData.pick` on its own
stream, `ZoneAssembler.WEATHER_SALT`, so the layout never moves), the same on every machine online.
Weather is presentation only: no rule changes (a rule touch may come later).

- **Data**: `data/weather/` (`WeatherData`): rain, storm, fog, wind, dusk. A zone lists the ones it
  can have with weights and a clear weight (`ZoneData.weathers`, `weather_weights`, `clear_weight`):

  | Zone | Weathers (weight) | Clear |
  |---|---|---|
  | Rotten Hollow | rain 3, storm 1, fog 2, wind 2, dusk 3 | 4 |
  | Sunken Bog | rain 3, storm 1, fog 4, dusk 2 | 4 |
  | Ashen Ruins | wind 3, fog 2, dusk 3, storm 1 | 4 |

- **Look**: a weather changes a copy of the zone's `StageLook` (`WeatherData.apply_to`, the
  phase-two values too, so a guard's rage shifts from the weathered room to a weathered rage): sun and
  ambient colour and strength, the sun's height (dusk: a low sun, long shadows), shadow strength, fog
  colour and thickness, the sky colour, brightness, saturation, contrast and the vignette, and how far
  and fast plants sway (`StageLook.sway_percent`, `sway_speed_percent`; wind 280% / 200%). The zone's
  fights use the same copy, so a fight looks like the zone it started in.
- **Air**: extra particles on top of the zone's own, which a weather can thin (`zone_air_percent`):
  rain streaks (`ZoneAmbientData.stretch`: a tall quad turned along its fall, art kit `rain_drop`)
  with splashes on the ground (`splash`, `quick_fade`; both drawn soft, blended), fog banks,
  wind-blown dust streaks (straight, stretched along the gust) and leaves; dusk thickens the zone's own air by 30% (more fireflies in the Hollow
  and the Bog, more ash and embers in the Ruins). Air that drifts straight (no wobble) is born
  upwind by half its drift (`StageBuilder.ambient`), so it spreads evenly over the view; wobbling air
  turns within a fraction of a second and stays round the camera. Rain streaks are born no closer than
  about 4 m from the zone camera (`area.z` 7, a half-depth), out of its near blur. The fights play them thinner like
  the rest of the zone air (8.12).
- **Sound**: a loop over the zone's own (`Audio.play_weather`): rain (rain and storm, "Forest rain
  Atmo Fantasy" by szegvari) or wind ("Wind 2" by FunWithSound), CC0, seamless 60 s loops picked by
  ear; quieter in the zone's fights (`fight_volume_offset_db`), gone outside the zone.
- **Lightning** (storm): every 6 to 16 s the sky lights up with a second flicker (`WeatherFx`:
  ambient light and sky colour), then thunder (`thunder`, picked by ear) 0.3 to 1.5 s later and a low
  buzz. Not in fights (it would hide an attack), and not while the zone is held behind the pause menu
  or the backpack or a yes/no prompt (a flash then ends at once, and the next strike is a whole gap
  after the hold). The Flashes setting scales it like every screen flash
  (`combat_visuals.screen_flash_scale`: Reduced `flash_reduced_screen_percent`, Off none; the thunder
  still comes).
- **Never named on screen**: the weather shows itself (rain falls, fog hides, wind blows dust,
  dusk turns the light orange), and it changes nothing in play, so a word would only repeat it.
  The first build wrote it under the zone's name; the owner had it taken out (2026-10-23).
- Particles: at most 1500 extra per weather (a test checks), 1170 for a storm.
- Dev switch: `--weather=ID` (or `clear`) gives every zone visit that weather; the bot prints
  `AUTOPLAY_WEATHER <zone> <weather>`.

Tests: `tests/unit/test_weather.gd`.

### 8.21 Fight Rush (phase 25, cards #305, #312, built 2026-10-24, waiting for playtest)

Fight after fight for the furthest fight, with no map, zones, shops or campfires: the endless mode
dropped in #267, back as its own mode next to the run. Main menu, New Run, **Fight Rush**; online,
Online, Host, **Fight Rush** (card #312, "Online" below). Branch `phase25-Together`.

Owner decisions (2026-10-24):
1. After every won fight the party picks 1 of 3 cards, shown side by side: Heal, Train (attribute
   points) or an item. Relic cards come only after elite and boss fights.
2. There is no free heal: Heal is a card. After every boss fight the whole party is fully healed. A
   hero who went down in a won fight gets up at 1 HP (`run_downed_revive_hp`, as in a run).
3. The party brings the Relic bag and the Echoes it has learned. Nothing from a Rush goes back: no
   Relic banking, no Echo pips, no writes to `user://progress.json`. A Relic card lasts for that
   Rush only.
4. Fights get harder with every fight, with the depth growth a run uses per map row (one row per
   fight). Every 5th fight is an elite and every 10th a boss; the bosses cycle (below). All numbers
   live in `tuning.tres` and get tuned with bots.

Defaults chosen while building (not asked; the owner may overrule each one, section 12):
- **D1 (default)**: the level cap stays at 10. XP a hero earns past level 10 builds toward extra
  reward picks, one per `rush_spare_pick_xp` (300); each fight counts the most any one hero earned
  past the cap.
- **D2 (default)**: no Oaths in a Rush. The players screen has no Oath row and a Rush plays at oath 0.
- **D3 (default)**: one record per party size (Solo, Duo, Trio), each with its date. The record is the
  highest fight the party *entered*; the size is the most players seen during that Rush.
- **D4 (default)**: a Rush is played in one sitting: no Save & Quit, and it never touches the run save.
  Giving up or closing the game still keeps the fight reached (the record is written as each fight
  starts, and again when the Rush ends).
- **D5 (default)**: no running away: `can_run` is off, so the Run button is hidden.
- **D6 (default)**: New Run opens two picture cards side by side, **Run** and **Fight Rush** (7.5). The
  Fight Rush card shows the best fight across all party sizes.
- **D7 (default)**: the pause menu shows Give up in place of Abandon run. Giving up goes to the Rush end
  screen. Online (#312) only the host has Give up ("The Rush ends for everyone.", RUSH OVER on every
  machine). Online the pause also opens over a fight that has ended; once a lost fight has decided the
  Rush (its end screen still up), or the Rush is over, the host's row is **End the game** ("Back to the
  main menu for everyone.", asked with no detail: nothing is lost), so a loss never turns into a Rush
  given up. A Give up asked just before the loss takes the fight's own end (`Main._gives_up_rush_now`,
  pure, tested). When the host leaves after RUSH OVER, a friend's main menu notice reads "The Rush is over."
- **D8 (default)**: Settings > Reset progress also clears the Rush records (8.17).
- **D9 (default)**: bot and dev Rushes never write records, and read none (they compare against none):
  `--autoplay`, `--screen=`, `--rush-start` above 1, `--rush-fights`, `--relics=`, `--relics-path=`,
  `--seed=`, the pretend pads of `--players` above 1, `--pad-join-after` and `--pad-leave-after` (they
  seat friends nobody holds, with or without the bot), a `fixed_seed` in tuning or a `--tuning=` file
  (`RushRecords.allowed`, pure, tested; Main builds its switches in `_rush_records_flags`). Online
  (#312) a friend's machine cannot see the host's switches: the host sends its own verdict in
  `run_start` (`records`, also in every catch-up) and a friend keeps no record when it says no; a head
  start in the host's Rush state keeps the record out there too (`host_clean` and `start_fight`).
  The host is not told when a friend plays as a bot (only that friend's own machine then keeps no record).
- **D10 (default)**: Rush fights count in the Rot Journal (7.11), as run fights do.
- **D11 (default)**: a flawless win shows a plain "FLAWLESS" chip with no reward. A Rush has no spoils.
- **D12 (default)**: no pact (crossroads, 8.19) at the start of a Rush.
- **D13 (default)**: weather (8.20): a normal or elite fight rolls its zone's weather (`WeatherData.pick`);
  a boss fight rolls its own zone's. The Hollow King's throne has none. Fights never show lightning.
- **D14 (default)**: card sets per fight kind: normal Heal, Train, Item; elite Heal, Train, Relic; boss
  Train, Relic, Relic (no Heal: the boss heal already filled everyone; no item).
- **D15 (default)**: extra picks (D1) always use the normal set (Heal, Train, Item), so Relics stay tied
  to elites and bosses.
- **D16 (default)**: monster variants (deep versions, 2.16) start at fight 21 (the Ruins tier). A run
  uses them from map row 4; the Rush keeps fights 1 to 20 on the plain monsters so the first two
  tiers teach them.
- **D17 (default)**: enemy attack speed stops rising at fight 31: the game's speed floor (70%) keeps
  every hit fair to press. After that only HP and power grow (tuning can raise their growth).
- **D18 (default)**: Heal follows the campfire's Rest rules: Relics that change Rest change the Heal
  card too (Rain Pouch more, Hunger Charm nothing). The boss heal is a full heal for everyone.
- **D19 (default)**: the item card never offers keys or treasure (a Rush has no chests and no gold),
  and Relic cards never offer gold Relics (Lucky Coin).
- **D20 (default, for #312)**: online, a friend who joined after the Rush started writes no record for
  that Rush.
- **D21 (default)**: the Rush shows no gold anywhere (the strip, the party screen, the backpack's sell
  chips, the win sound).

**What the player sees.**

- **New Run** opens the two cards (7.5). Run starts the old New Run flow unchanged (overwrite check,
  tutorial and calibration offers, the players screen with Oaths). Fight Rush carries a gold star
  chip "Best 16" once any record exists. It shows the calibration offer if it is due (never the
  tutorial offer), then the players screen titled **Fight Rush** with no Oath row. A saved run is
  never touched, and Continue still shows afterwards.
- **The Rush screen** (`RushRewardScreen`, a `StopScreen`), ready phase: the title **FIGHT 8** and two
  cards, **Fight** (crossed swords; a chip "Elite", or a skull "Boss", when the next fight is one) and
  **Party** (three heads; a chip "+2 points" while attribute or skill points are unspent). Footer
  Choose / Select / Party. A Rush opens here on FIGHT 1; a Relic bag holding Relics opens the party
  screen on its Relics page first, as a run does (card #265). Y (`party_menu`) opens the party screen
  in both phases. Online (#312) friends watch it: every card greyed but Party in the ready phase (the
  cursor starts there, Confirm opens it), footer Party only; a friend's change to the party redraws the
  host's screen too (`Main._apply_bag_op`).
- **A fight**: the swirl, then the fight in its zone's look and air under its weather (D13). The start
  banner reads **FIGHT 7** in gold, or **NEW BEST 17** once the fight passes the record this party
  size held when the Rush began (when that record is above 0); a boss or guard keeps its name banner.
  No Run button. Music: the fight, elite or boss song (a guard fought as the boss fight gets the boss
  song).
- **The fight's end** is the run's without gold: the XP and level-up rows, the streak chip, a
  "FLAWLESS" chip, and the Relic slot line when a slot opens. The button hint reads **Rewards** after
  a win and **Results** after a loss.
- **Picks** (after a win): the title **REWARD**, a chip row (a sword "Fight 7" for the fight just won, a
  star "Best 16" when a record exists, "+1 pick" while more than one pick is left), the party strip
  (HP and levels, no gold), then the cards side by side (the table below). Heal: a heart "+40% HP"
  and a dim chip per hero whose Relics change it ("Alder +0%"); greyed when no hero would gain HP.
  Train: "+1 point" ("+N points" above 1). Item: its name and icon, a rarity chip and what it does
  (as the shop's chips). Relic: its name and Relic icon, the tag "Lv 1" or "Lv 1 > 2", a rarity chip
  and its effect. Footer Choose / Take / Party. An item or Relic goes through the usual hand-out
  (`StopScreen.give`): a full pack, or a Relic nobody wears yet, opens the party screen over the Rush
  screen with it in hand (leaving a full pack without room loses the item, as in a run). The cursor
  starts on the first card that can be taken. After the last pick the screen turns to the ready
  phase.
- **Pause** (in a fight or on the Rush screen, not while a gift's party screen is open): the note under
  PAUSED reads "Fight 7" (the fight reached; no note on the first ready screen, before Fight 1 was
  pressed); rows Continue, Players, Settings, Glossary, **Give up**. Give up asks
  **Give up?** (no detail), yes **Give up**, no **Keep going**.
- **The end** (a loss or Give up; `RunEndScreen.setup_rush`): **RUSH OVER** in red, a gold **NEW RECORD**
  under it when this Rush beat its party size's record, then chips: a sword "Fight 16" (left out when
  the Rush was given up before its first fight: never "Fight 0"), a star "Best 16" with the record's
  date dim beside it, a person "Solo" / "Duo" / "Trio", and the heroes' faces
  and levels. The killer row after a loss (not after Give up) and the defence rows; no Kept row
  (nothing is kept). Footer **Again** (the Fight Rush players screen, same seats) / **Main menu**.
  Music: the victory song on a new record, otherwise the defeat song.
- **The party screen** in a Rush: the Relic slots' locks read "First elite" and "First boss"; an Echo
  not learned yet reads "Runs only" (Echoes are learned in runs); no pips bar on the Relics, no Echo
  learning row, no gold line.
- **Local drop-in** works as in a run (9.3): the pause menu's Players row; in a fight the change waits
  for a quiet moment, on the Rush screen it applies at once. Online drop-in: "Online" below.

**Fights.** Fight 1 is the first. A fight's depth is `(fight - 1) x rush_depth_per_fight_percent / 100`
map rows (one per fight at 100), and its enemies grow with it as in a run (8.3): HP
`100 + depth x (run_enemy_hp_row_percent 5 + rush_enemy_hp_step_add 0)` percent, power
`100 + depth x (run_enemy_power_row_percent 3 + rush_enemy_power_step_add 0)`, attacks 1% faster per
row (`run_enemy_tempo_row_percent`) down to `attack_tempo_floor_percent` (70), reached at fight 31
(D17; the engine clamps every fight to that floor again, so a Rush cannot go under it). Then
`rush_enemy_hp_percent` and `rush_enemy_power_percent` on top. Elite, guard and boss marks keep their
usual extra HP, power and speed. Fight 1 has no mark hits (like a run's first zone). A boss fight
grows only by the depth past its boss's `home_depth` (where a run meets it), and only while
`rush_scale_bosses` is on. Each normal or elite fight is drawn from the tier it falls in (seeded,
never the same fight twice in a row while there is a choice) and takes one of the tier's zones
(seeded) for its look, air and weather:

| Tier | From fight | Zones | Normal fights | Elites | Deep |
|---|---|---|---|---|---|
| Hollow | 1 | Rotten Hollow | its roamers (7) | act 1's elites (3) | no |
| Bog | 11 | Sunken Bog | its roamers and act 1's ambushes (14) | act 1's elites (3) | no |
| Ruins | 21 | Ashen Ruins | its roamers and act 2's ambushes (13) | act 2's elites (3) | yes |
| Everything | 31 | all three | all of the above (23) | both acts' elites (4) | yes |

The boss cycle: fights 10, 20, 30, 40 and 50, then again from 60. Each tier ends on its own zone's
guard, the guards come before the Husk Lord, and the Hollow King (the hardest fight, #177) closes
each cycle. In a deep tier a guard is fought as its deep version.

| Boss | Fight | Encounter | Place | Home depth |
|---|---|---|---|---|
| 1 | 10 | The Gorged One (`guard_gorged_one`) | Rotten Hollow | 1 |
| 2 | 20 | Mire Mother (`guard_mire_mother`) | Sunken Bog | 3 |
| 3 | 30 | Ash Warden (deep, `deep_guard_ash_warden`) | Ashen Ruins | 9 |
| 4 | 40 | The Husk Lord (`husk_lord_fight`) | Rotten Hollow, act 1's final look | 6 |
| 5 | 50 | The Hollow King (`hollow_king`) | the Hollow Throne (act 2's final look), no weather | 13 |

A boss fight pays at least `rush_boss_min_xp` (260; the Hollow King's own data pays 60), and every
Rush XP gain is scaled by `rush_xp_percent`.

**Rewards** (`RushState.roll_offer`, seeded by the fight and the pick number):

| Fight just won | Cards, left to right |
|---|---|
| normal | Heal, Train, Item |
| elite | Heal, Train, Relic |
| boss (first pick) | Train, Relic, Relic (two different Relics) |
| any extra pick (D1, D15) | Heal, Train, Item |

- **Heal**: each hero heals `rush_heal_card_percent` (40) of max HP, changed by their Rest Relics (D18)
  and the healing they receive, up to what they are missing.
- **Train**: `rush_point_card_points` (1) attribute point for each hero.
- **Item**: from the Rush's item list, only what the party still wants, weighted by rarity for the
  depth. The list is the run's shop and found items that are supplies or upgrades and not rotten
  (Antidote, Holy Water, Salve, Feast, Tonic, Bomb, Smelling Salts, Bigger Pack; no Key, no
  treasure, no curse).
- **Relic**: from the run's Relics the Rush can still gain (not at the top level), at least
  `rush_relic_min_rarity` (1, rare) while there are such, never a gold Relic (D19) and never a
  rot-touched one (a rot-touched Relic can still come from the bag). A copy raises its level for this
  Rush.
- A card that cannot be filled is left out. With every Relic at its top level an elite offers Heal and
  Train, and a boss Train alone: one card is a plain confirm (the side-by-side rule is for two or
  three choices).
- After a boss everyone heals `rush_boss_heal_percent` (100: full); a downed hero first gets up at 1 HP.
- Relic slots: `relic_slots_start` (1), a second after the first elite or boss win, and the third after
  the first boss win (`run_gear_slots`, 3, at most).

**Records** (`RushRecords`, pure, tested; `PlayerSettings`): in `user://settings.cfg`, section `[rush]`,
keys `best_1`, `best_2`, `best_3`, each `{fight, date}`. The fight reached is written as each fight
starts and again when the Rush is decided (lost or given up), under the most players seen
(`RushState.most_players` only rises: a solo Rush that becomes a duo at fight 10 has written Solo up
to 9 and Duo from 10 on; a duo that drops to solo stays Duo; a pad that joins during the last fight
still counts). A record is kept only when it beats the old one. NEW RECORD and the NEW BEST banner
measure against that party size's record as it was when the Rush began. The menu card shows the
best of the three. Only Reset progress clears them (D8).

**Nothing goes back** (decision 3): a Rush banks no Relics, fills no Echo pips (no drops, no mastery),
writes nothing to `user://progress.json`, is never saved (`_save_allowed`) and never deletes a saved
run (`_clear_run_save` is guarded). Oath unlocks never come from a Rush (it has no victory).

**Online** (card #312, built 2026-10-24, waiting for playtest). The host's machine plays the Rush
exactly as alone and makes its choices; friends play their own heroes in the fights and watch the
rest, as in an online run (9.2). Nothing goes back on any machine (decision 3).

- **Hosting**: Online, Host opens two cards side by side, **Run** and **Fight Rush** (7.5): the same
  pictures as New Run's, the Fight Rush card with the host's own Best chip, greyed without the Rush
  data. Back goes back to Host / Join. The players screen then knows the game: a Rush's is titled
  **Fight Rush** with no Oath row on every machine (D2). Start begins the Rush for everyone.
- **The mode travels**: the `lobby`, `again` and `run_start` messages carry `mode` ("run" or "rush";
  anything else, or none, means a run). `run_start` also carries the seed, the roster, `oath`,
  `late` and `records` (below). The protocol number went to 4 for it (9.2), so an older build is
  refused at the handshake.
- **Friends follow the host's state**: each Rush screen goes out with the whole `RushState.to_dict()`,
  as a run's screens do. A friend's game builds the Rush from the host's seed, then takes the host's
  state with every screen: the Rush fight (`rush_fight`, a fight screen: the same encounter, look and
  weather) and the Rush screen and the end (`rush_reward`, `rush_end`, watched screens). Picks,
  Relics, the fight counter and any head start come from the host. A friend whose game lacks the
  Rush data leaves with "Could not start the game".
- **The Rush screen**: the host picks the cards and presses Fight (P1 makes the choices, 9.2).
  Friends see "The host is choosing (P1)" and every card greyed but Party in the ready phase (the
  cursor starts on it; Confirm opens the party screen, which closes back to the Rush screen), footer
  Party only. A friend's change to the party (points, Relics) redraws the host's Rush screen
  (`Main._apply_bag_op`).
- **Give up is the host's** (D7): the host's pause row reads **Give up** ("The Rush ends for
  everyone.") while the Rush goes on, and RUSH OVER shows on every machine. Friends only have Leave.
  Once a lost fight decided the Rush, or it is over, the host's row is **End the game** ("Back to the
  main menu for everyone."). When the host leaves after RUSH OVER, a friend's notice reads "The Rush
  is over."
- **The end and Again**: RUSH OVER shows on every machine with the host's fight reached and party
  size. The host's Again opens the Fight Rush players screen for everyone with the same seats (the
  `again` message carries the mode); a friend who dropped in keeps their hero and is there from the
  start of the next Rush.
- **Drop-in, rejoin and a crashed friend** work as in a run (9.3), through the same code: drop-in
  opens when the Rush starts and shuts when it is decided and during Again. A newcomer gets
  `run_start` with `late`, the place screen (`rush_reward`, `party` or `rush_end`) and the Rush fight,
  each with the whole state (`Main._catch_up_messages`, pure). In a fight they get their hero at the
  fight's next quiet moment, as in a run (not at the next fight); on the Rush screen at once. A token
  rejoin (#205) gets its own seat back. A friend whose game crashed comes back as a newcomer and takes
  their away seat after `net_takeover_after_ms` (15 s).
- **Records online** (D9, D20): each machine writes its own records (its own `settings.cfg`), and only
  a machine there from the start of that Rush. A friend who dropped in, or a crashed friend who came
  back (a newcomer to the host), writes none for that Rush (what a crashed game wrote at earlier fight
  starts stays); a token rejoin keeps what it was (`Main._late_after_start`, pure, tested). A friend's
  machine cannot see the host's switches, so the host sends its own verdict (`records` in
  `run_start` and in every catch-up: no for a bot, dev or head-start Rush there) and a friend writes
  none when it says no. The party size is the host's most players seen, from its state: friends count
  nothing themselves.

**Built as.** `RushState` (`scripts/rush/rush_state.gd`) extends `RunState` (pure, no Node): the fight
counter (the last fight entered, 0 before the first), fight kinds, tiers and the boss cycle, the
offer, spare XP, the Rush counters for Relic slots, and its own "rush" block in `to_dict` (a run state
refuses a Rush dict and the other way round: `RunState.mode()`). `RunState` gained small seams that
change nothing for runs (`_start`, `mode`, `_fight_depth`, `_scales`, `shows_gold`, `teaches_echoes`,
`xp_full`). Data: `RushData`, `RushTier`, `RushBoss` (`scripts/data/`) and `data/rush/fight_rush.tres`,
written by `tools/bootstrap_rush.gd` from the run, its two acts and the three zones. Re-run the tool
after a zone's roamers, an act's elites or ambushes, or the run's items change: `test_rush_data.gd`
fails on stale data until then. Missing or broken data greys the Fight Rush card ("locked" on
Confirm) and logs an error, never a crash. Main's flow is its "the Fight Rush" section (`_start_rush`
to `_show_rush_end`). The card pictures (`choice_run`, `choice_rush`, `choice_heal`, `choice_fight`,
`choice_party`) come from the art kit's `ui_choices.py`.

Tuning (`tuning.tres`, group "Fight Rush"; the first values, not yet tuned with bots):

| Field | Value | Meaning |
|---|---|---|
| `rush_depth_per_fight_percent` | 100 | map rows of depth each fight adds, in percent |
| `rush_enemy_hp_step_add` | 0 | extra enemy HP points per depth step, on top of the run's 5 |
| `rush_enemy_power_step_add` | 0 | the same for power, on top of the run's 3 |
| `rush_enemy_hp_percent` | 100 | every Rush enemy's HP, after the depth growth |
| `rush_enemy_power_percent` | 100 | every Rush enemy's power, after the depth growth |
| `rush_scale_bosses` | true | boss fights (guards too) grow with the depth past their home depth |
| `rush_elite_every` | 5 | every Nth fight is an elite (unless it is a boss fight) |
| `rush_boss_every` | 10 | every Nth fight is the next boss of the cycle |
| `rush_heal_card_percent` | 40 | the Heal card's share of max HP, before Rest Relics |
| `rush_point_card_points` | 1 | attribute points the Train card gives each hero |
| `rush_relic_min_rarity` | 1 | the lowest rarity a Relic card offers while the pool has such |
| `rush_boss_min_xp` | 260 | a boss fight pays at least this XP |
| `rush_xp_percent` | 100 | every Rush XP gain |
| `rush_spare_pick_xp` | 300 | XP past the level cap for one extra pick (D1) |
| `rush_boss_heal_percent` | 100 | the heal after a boss fight (100 = full) |

**Dev and bot switches** (`AUTOPLAY_` lines only with `--autoplay`):
- `--rush`: start a Fight Rush at once. With `--autoplay` the bot plays it: Heal when someone is hurt,
  else the first Relic, else Train, else the item; on the ready phase it spends points, wears Relics
  and presses Fight. `--players`, `--pad-join-after` and `--pad-leave-after` work as with `--run` (and,
  like every dev switch, keep the records out, D9).
- `--rush-fights=N`: end the Rush after N fights (after the last fight's picks; `rush_capped`). Always
  cap a bot Rush: a perfect bot may never lose.
- `--rush-start=N`: a head start to fight N. It replays fights 1 to N-1 as perfect wins with the bot's
  picks (XP, Train points, elite and boss Relics; no Heal or items), so it checks mechanics and
  deep-play feel, never balance. Both switches imply `--rush`.
- Online (#312): `--rush` with `--host=N` hosts a Fight Rush and starts it once N players are in
  (`--host=1` at once, friends drop in later). Friends use the plain `--join=ADDRESS` and take the
  mode from the host; `--join-after`, `--drop-after` with `--rejoin` and `--crash-after` work as in a
  run (9.2, 9.3). Pair: host `--autoplay --rush --host=2 --rush-fights=4 --seed=7 --quit-on-end` in
  the background, then `--autoplay --join=127.0.0.1 --quit-on-end`: both print the same
  `AUTOPLAY_MIRROR` lines, `AUTOPLAY_PLAYERS` and `AUTOPLAY_RESULT rush_capped ...` line, about 140 s
  for 4 fights (`timeout 400`). A drop-in pair uses `--host=1` (with `--host=2` a `--join-after`
  friend only fills the lobby).
- Lines: `Rush seed: S start: N`, `Rush fight N: <kind> <encounter> weather <id|clear>` and
  `Rush pick: ...` (every Rush); the bot's `Rush offer: heal:40 point:1 item:salve fight=N` and
  `Rush card: ...`; per fight `AUTOPLAY_RUSH fight= kind= enc= depth= enemy_hp= enemy_power= tempo=
  result= party_hp= level= xp= picks= spare=` (`depth` is the depth the fight grew by: for a boss, the
  depth past its home depth, so fight 50 prints 36); at the end the `AUTOPLAY_RECAP` lines (after a
  loss), `AUTOPLAY_PLAYERS` and `AUTOPLAY_RESULT rush_<over|gave_up|capped> fight= wins= record= new=
  players= level= relics= echoes= items= seed= start=` (`wins` leaves out the head start's; bots
  read and write no records, so `record=0 new=0`).
- Times (headless): 3 capped fights about 90 s, one head-start fight about 1 to 2 min (fight 50 the
  longest); later fights take longer. Balance runs start at fight 1:
  `--autoplay=average --bot-skill=60 --rush --rush-fights=15 --seed=1|2|3`, about 12 to 15 min each.
- Dev screens: `--screen=rush_cards` (the New Run cards with Best 16), `rush_players`, `rush_reward`
  (the picks after fight 7), `rush_reward_elite` (after fight 5), `rush_ready`, `rush_end` (a NEW
  RECORD sample), `rush_pause`. None reads or writes a record.

Tests: `tests/unit/test_rush.gd` (RushState, records, switches, dev screens), `test_rush_data.gd` (the
data file: tiers, bosses, items, stale data, a 70-fight walk), `test_rush_screens.gd` (the Rush
screen, the end screen, hints, the lobby title), and the New Run cards in `test_choice_cards.gd`,
`test_save_menus.gd`, `test_branding.gd` and `test_menus_clean.gd` (10). Online:
`test_rush_online.gd` (the mode in each message, protocol 4, a friend building the host's Rush and
its screens, Give up and End the game, the records verdict and the late rule, catch-up mid-fight and
on the Rush screen, drop-in, Again, the lobby title) and the Host cards in `test_choice_cards.gd`.

**Known limits** (not bugs):
- A Rush cannot be saved or continued (D4), online neither.
- The numbers are the first values above; the balance runs have not been done yet.
- Online, a drop-in refused because the Rush is decided reads "Run busy, try again" (the Join check
  runs before the game is known).
- Online, the host's End the game over a lost fight's end screen reads "The host ended the game." on
  friends' screens, as after a run's lost fight.
- The host is not told when a friend plays as a bot: only that friend's own machine keeps no record.
- A crashed friend who comes back writes no more records for that Rush.
- The host's gift party screen (an item or Relic in hand) is not redrawn when a friend changes the
  party (runs too).
- Again online is checked by unit tests only (bots quit on the end screen), and no bot switch lands a
  drop-in exactly on the Rush screen (its window is about 2 s a fight; unit tests cover it).

## 9. Multiplayer (phase 5)

### 9.1 Local co-op (phase 5 Part A, done)

- **Players screen** (`LobbyScreen`, approved 2026-10-12): New Run and Practice open it first. The
  device that opened it is P1. Another pad (or the keyboard) presses Confirm to join (up to 3
  players) and Back to leave. Heroes are dealt out in turn (P1 gets the extra one: with 2 players
  P1 has Alder and Cass, P2 has Brin); left/right on a hero hands it to another player, as long as
  every player keeps one. Start (selected first) plays; P1's Back returns to the main menu. The
  roster is kept for the session (same P1 = same split next time). Phase 25 leaves this screen as
  it is; mid-run, friends join, leave and trade heroes from the pause menu's Players row (9.3).
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
- **A pad drops** (card #181, 2026-10-17): in local co-op, Main checks every frame that each pad in
  the roster is still plugged in (`PlayerRoster.missing_players`). If one is gone during a fight
  (after the current move) or a zone, the game is held under a "P2: controller disconnected" card
  (`PadLostOverlay`). The pad coming back under the same id carries on by itself; a button on
  another pad (or Confirm on a free keyboard) takes the seat over (`replace_device`); Pause gives
  the seat up: since phase 25 its heroes go to P1 (to P2 when P1's pad was lost; the old P2 then
  becomes P1) and nobody else's heroes change (`leave_midrun`, 9.3; before, every hero was dealt
  out again). The players screen drops pads that are gone
  (`drop_missing`) so a run never starts with a ghost player.
- **Window focus** (card #181): alt-tab, the Steam overlay or a notification pauses a fight (after
  the current move) or a zone, solo and local co-op. Never online, where the others play on. The
  pause is opened on the next idle moment, never inside the focus event (card #208: focus lost
  while a zone was being built made the pause menu fail to appear, holding the game still).
- **Walking** (card #184): the move actions use a stick deadzone of 0.2 (menus and buttons keep
  0.5). The walk reads the stick as one vector with a radial deadzone, solo, online and co-op alike
  (`DeviceInput.radial_deadzone`), so a diagonal push no longer snaps to an axis.

### 9.2 Online co-op (phase 5 Part B, done)

- **Host-authoritative, the host is the server.** Main menu: **Host Online** (since card #312 it
  first asks Run or Fight Rush, two cards, 7.5) listens (port `net_port`, 7777) and shows the PC's
  addresses to share; **Join Online** takes an address
  (remembered per machine). One player per machine (P1 = host). Same Wi-Fi works as is; over the
  internet both use Tailscale (or the host forwards the port). Approved 2026-10-12: IP first.
- `Net` autoload (`NetSession`, `scripts/autoload/net.gd`) wraps Godot's high-level multiplayer.
  The transport is a `MultiplayerPeer` (ENet today); everything above it only uses the
  high-level API, so Steam's peer (GodotSteam: friend invites, NAT punch-through and relays) can
  replace ENet later without touching the game.
- **Handshake**: a client first sends its content fingerprint (`DataHash`: SHA-256 of every file
  under `data/`, `scripts/` and `scenes/`, line endings ignored, plus the project version in
  `project.godot`; card #182, so a code-only change also splits the builds) and a protocol number.
  A refusal names both short build ids ("yours a1b2c3d4, the host's e5f6a7b8"). A mismatch or a
  full game (3 players, "Game full") is refused with a reason shown on the Join screen. A started
  run seats newcomers while drop-in is open (9.3), else "Run busy, try again". A host that cannot
  be reached says "Host not found". The protocol number is 4 since card #312 (phase 25: the game's
  `mode` in `lobby`, `again` and `run_start`, and the Rush screens, 8.21). Until welcomed, a
  client's messages are ignored. A client that never says hello is dropped after
  `net_connect_timeout_ms`.
- **Messages** are (kind, Dictionary of plain data). Reliable ones share one ordered channel (game
  flow and combat must never overtake each other; this replaces the "dedicated combat channel"
  idea); zone positions go unreliable on channel 1. Only the host may send to clients
  (`@rpc("authority")`); clients' messages to the host are checked against the sender's peer id.
- **Players screen online**: the host's lobby lists who joined, hands heroes out (left/right) and
  starts; clients watch it. Starting closes the players screen; friends drop in from then on (9.3).
- **Run flow**: the host's machine runs the run exactly as offline. Each screen it shows is sent
  as a "screen" message with the whole `RunState.to_dict()` (gear by id; the map comes from the
  seed); any later change of the run (a purchase, gear, a level) is sent as "run". Clients only
  show: their map, shop, rest, loot, party and end screens are the same screens fed with the
  host's state, input off, with "The host is choosing (P1)" on top. Messages that arrive during a
  client's transition wait for it. Approved 2026-10-12: P1 (the host) makes the run choices. A
  Fight Rush (card #312, 8.21) goes the same way: `run_start` says `mode` "rush", the Rush fight is
  a fight screen (`rush_fight`), the Rush screen and its end are watched screens, each with the whole
  `RushState`.
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
- **Someone leaves**: a client that leaves for good mid-run (or whose seat's grace time ran out,
  below) hands its heroes to the host (P3 becomes P2); its open prompts are resolved at once and
  the others are told. A client that leaves on purpose (Leave in the pause menu, or quitting)
  says goodbye first and its line closes a moment later, so its seat is given up at once rather
  than kept for a rejoin. If the host leaves (or ends the game from the pause menu), everyone goes
  back to the main menu with a note. Mid-run the host says so first (card #247): End the game, or
  closing the window, sends a `menu` message that friends act on at once ("The host ended the
  game.", no seat kept), and the line goes down only after the fade (closing the window waits
  `BYE_LINGER_S`; quitting is held back only while hosting), since the other end handles a
  disconnect before the messages that came with it. Without it friends took the lost line for a
  dropped host and waited on the Join screen to take their seat back. Online, the pause menu opens over a game that goes on (it
  offers Leave / End the game, and shows the host's address in gold under PAUSED so another friend
  can drop in, 9.3).
- **Dropping and rejoining** (card #205, 2026-10-18):
  - *Heartbeat*: both ends keep pinging (ENet), and a connection that answers nothing for
    `net_drop_min_ms` .. `net_drop_max_ms` (3 to 6 s) counts as lost, so a pulled cable, a crash or
    a Wi-Fi blip never freezes a fight for long.
  - *Seat tokens*: the welcome gives each client a secret random token (`SeatBook`,
    `scripts/net/`, pure), kept in memory on both machines. A client whose connection goes during
    a run is "away": the host keeps its seat for `net_rejoin_grace_ms` (120 s) and everyone sees a
    small chip, "P2 away" (top right; the host's also counts the seat's time down). It never
    blocks the game.
  - *While away*: the host's player plays the away heroes (their menus open on the host, the host
    defends for them; with the bot it is the host's bot), exactly as when a player leaves, but the
    seat (P2 stays P2) and the heroes stay theirs. Prompts that were open on the away machine
    when it went count as not defended (NONE, by the DefenseArbiter, at once). Chosen over waiting
    at their turn: nobody sits frozen for two minutes, and it is what leaving already did.
  - *Coming back*: the dropped player's game opens the Join screen with the host's address and a
    note ("Press Enter (A on a pad) to take your seat back"; the Join screen now takes a pad's
    confirm too). The hello carries the token after the build fingerprint check; a token gets its
    own seat back in a started game, even while drop-in is shut. A hello with no token, a wrong one
    or an expired one is a newcomer (9.3: a free seat, a seat away 15 s or more, or "Game full" /
    "Run busy, try again"). A token wins its seat even if the host has not
    noticed the old connection die yet (the old one is let go), and a peer that already has a seat
    cannot take another. The host then sends `run_start`, the place screen it is on (map, zone,
    shop ...) with the whole run, and the fight message if a fight is on.
  - *Mid-fight*: the rejoined player's fight skips the host's batches until a "resume" batch
    (`CombatEngine.resume_events()`: combat_started with every fighter as they are now, the
    practice options, the team gauge, every intent, the turn order and the waiting turn, or the
    end). The host sends it at the next moment nothing is timed (a hero's turn, or the end), never
    mid-attack. The mirror rebuilt from it equals the engine (a test), and normal event flow
    continues; `AUTOPLAY_MIRROR` still matches on every machine.
  - *The seat comes back in two steps* (phase 25, 9.3): once the rejoiner's machine shows what the
    host has (its place screen is built, or its fight applied the resume) it says so
    (`seated_ready`), and the host gives the seat back at once outside a fight, or at the fight's
    next quiet moment. So no attack is half theirs, and the seat is never theirs before their own
    screen shows the game. (Until phase 25 the seat came back with the resume.)
  - If the grace time runs out the seat is given up as above. The token lives in memory, so a
    player whose game crashed (restarted) has none. Since phase 25 they come back as a newcomer and
    take the away seat once it has been away `net_takeover_after_ms` (15 s, 9.3); a fresher one is
    held for its own token. The away chip reads "P2 away"; the host's player sees the countdown. A
    newcomer still catching up shows "P2 joining" (no countdown).
- **Sharing the game**: one fixed download link,
  `https://github.com/JawadAlSaeed/Rotsworn/releases/download/latest-build/Rotsworn.zip`. Every
  push to `main` (except one that only changes Markdown or `docs/`) runs
  `.github/workflows/build.yml` on GitHub Actions (free for a public repo): an Ubuntu runner
  installs Godot 4.7.2 (standard) with its export templates (cached, about 1.2 GB), imports, runs
  the GUT tests with run_tests.bat's checks, exports the "Windows" preset (release, embedded pck,
  the icon set by Godot's own exe modifier, no code signing) with build_game.bat's checks, zips the
  exe and puts it on the `latest-build` pre-release (the tag is moved to the commit; the zip is
  replaced; the notes give the version and the commit). A failed test or export publishes
  nothing, so the old zip stays. One build runs at a time; pushes during it wait and only the
  newest is built. Everyone online, the host too, downloads from that link: every copy of one exe
  has the same content fingerprint on every PC, while a local `build_game.bat` build or the editor
  may not match it, and the link changes after each push, so the group downloads again together.
  `build_game.bat` still exports `build/Rotsworn.zip` (one exe) locally, to test a build. It is a release
  export, and it deletes the old exe and zip first and fails loudly (log in `build/export.log`)
  if the export fails, so a stale file is never handed out. The dev command-line switches (`--autoplay`,
  `--tuning`, `--seed`, `--encounter`, `--first-strike`, `--host` ...) are read only in debug
  builds (`DevArgs`, `OS.is_debug_build()`): the editor and `run_game.bat` keep them, a release
  build ignores them. Online, a lost final-fight or zone-return fade (the host left during it)
  now uncovers the screen instead of leaving a black card that eats input. Everyone online
  plays that same build: a run from the editor has a different content fingerprint (the export
  stores resources differently) and is refused.
- Bot: `--host=N` hosts and starts a run once N players (1 to 3) are in (`--host=1` starts at once
  alone, friends drop in later, 9.3; with `--rush` it hosts a Fight Rush, 8.21); `--join=ADDRESS`
  joins (whatever the host plays). Both play
  with `--autoplay`; each presses only for its own player. `--drop-after=S` makes a client drop off
  the network S seconds after joining without a word (the host finds out through the heartbeat);
  `--drop-in-fight` makes that drop wait for the next fight and come a few seconds into it;
  `--rejoin[=S]` joins again S seconds (default 10) after losing the host. Without `--rejoin` an
  autoplay client that loses the host still fails with `AUTOPLAY_ERROR host_lost`. `--end-after=S`
  makes the host end the game for everyone S seconds after starting (as End the game does, once
  a run is on); host and client then both print `AUTOPLAY_RESULT host_ended`. Phase 25 (9.3):
  `--join-after=S` makes a client connect S seconds after launch, into a run going;
  `--seat-in-fight` makes the host seat a friend who drops in only a few seconds into the next
  fight; `--crash-after=S` makes a client quit S seconds after launch without a goodbye, like a
  crash. An online pair now plays for 25 to 30 minutes, so give each side `timeout 2700`.

### 9.3 Drop-in co-op (phase 25, cards #304, #311, built 2026-10-23, waiting for playtest)

A friend can join a run that is already going, on a local pad or online, and local friends can
leave or swap heroes mid-run. Branch `phase25-Together`.

Owner decisions (2026-10-23):
1. No computer teammate. A newcomer takes a hero P1 (local) or the host (online) was playing.
2. A local friend joins any time from a Players row in the pause menu. In a fight the change waits
   for a quiet moment, like pausing.
3. Online, a late joiner keeps only the Relics and Echo pips found after they joined. A win still
   unlocks their next Oath.

Defaults chosen while building (not asked; the owner may overrule them, section 12):
- Online drop-in is open whenever a seat is free. It shuts once the run is decided and during Again.
- The host's address shows in the online pause menu.
- A newcomer may take an away seat (this is how a friend whose game crashed comes back), but only
  one away for `net_takeover_after_ms` (15 s in tuning), so a quick token rejoin always wins its
  own seat.
- A crashed friend who comes back with a fresh game counts as late from their return.
- A local leaver's heroes go to P1. At most 3 players, as before.
- No Players row in the tutorial. The pre-run players screen keeps its approved left/right (no
  trade there).

**Local: the Players overlay.**

- **The row**: the pause menu has a **Players** row second, after Continue, with a two-heads
  picture (`PauseMenu.players_row`, `Item.PLAYERS`). It shows in a local game outside the tutorial
  (a fight, a zone, the map; practice too, where nothing is saved). Anyone may open the pause menu,
  even a pad that is not playing yet. In a fight it opens after the current move, as any pause.
- **The overlay**: Confirm on the row opens the players screen in its in-run mode over the pause
  menu (`LobbyScreen.setup_in_run`): the same hero cards and seats, an opaque backdrop, no Oath
  row, and the big button reads **Play**. Footer: Choose, Change, Play, Back.
- **Join**: the first open seat shows the Confirm buttons that can join now (a free pad's, the free
  keyboard's) and "join". A free device's Confirm joins as the next player (`join_midrun`, sound
  `player_join`) and takes one hero at once by the donor rule (below). Nobody else's heroes change.
  With three players there is no open seat, and another device's Confirm plays `locked`.
- **The donor rule** (`PlayerRoster.donor_hero`, local and online): the player holding the most
  heroes gives one (ties: the lower player, so P1 or the host). They give the usual deal's hero for
  the new seat (P2 Brin, P3 Cass) when they hold it, else their last one. An away (or joining)
  online player never gives, even when only they hold two: their seat and heroes stay theirs until
  they are back or the seat goes (the newcomer gets "Game full" meanwhile).
- **Leave** (#311): each joined player but P1 shows a dim "[B] leave" chip with their own device's
  Back button. Their Back leaves at once (`leave_midrun`, sound `player_leave`): their heroes go to
  P1, and a P3 who stays moves up to P2 with their heroes. On the keyboard Back is Backspace, Q or
  Esc. Esc is also Pause; for a joined keyboard P2 or P3 it means leave (checked before Pause). When
  the last friend leaves the game is solo again (every device controls everything).
- P1 cannot leave a run: P1's Back (or Esc) closes the overlay. Save & Quit or Abandon run end it.
- **Swap**: left/right on a hero card hands it to the next or previous player (`trade_hero`). If it
  is that player's only hero, the two players trade instead (the other player's first hero comes
  back), so three players can still swap. Only on this overlay; the pre-run screen keeps its rule
  (an only hero cannot move).
- **Modal**: a device that has not joined can only join. Every other press over the overlay is
  swallowed, so nothing under it (the zone's backpack) moves. The mouse always acts for P1.
- **Closing keeps the changes**: Play (Confirm from any joined player) applies the roster and goes
  back to the game. Back from P1, or anyone's Pause, applies it and goes back to the pause menu.
  Nothing is thrown away after a friend joined. Closing with nothing changed changes nothing
  (`same_as`, or solo before and after): no save rewrite, and the fight's action menu stays where
  it was (Skills list, target step).
- **After a change**: menus, defence and skill presses answer each player's own device (9.1), the
  party panels show P1/P2/P3 tags, hints show keys and pad buttons when both are in use, and each
  pad buzzes for its own heroes. In zones only P1 walks, as before. Every real change rewrites the
  run save with the new player count (8.14).
- **P1's real device**: while solo every device controls everything, so the game does not know P1's
  pad. When the overlay opens solo, P1 becomes the device that last pressed a button (or pushed a
  stick to walk) while the game itself was played (`PlayerRoster.play_device_after`,
  `Main._note_play_device`). The press that opened the pause (Pause, or Back on the map) never
  counts, nor a press while a menu, the lost-pad card or a pending fight pause was up, nor any
  press in co-op (it may be a friend's). Every roster change (a run start or Continue, a join, leave
  or trade, the lost-pad card) resets it to the roster's P1 (`Main._reset_play_device`), so a pad a
  friend pressed before leaving never becomes P1. So a friend who paused on their own pad does not
  take P1's seat; they press Confirm on the overlay to join. A pad that is no longer plugged in is
  never P1's: the overlay takes the first of that device, the roster's P1 and the device that
  pressed last that is the keyboard or a plugged pad, else the keyboard
  (`PlayerRoster.overlay_p1_device`).
- **The lost-pad card** (9.1): Give heroes follows the leave rule: the heroes go to P1 (to P2 when
  P1's pad was lost; the old P2 becomes P1) and nobody else's change.
- **Quiet moments**: the overlay opens from the pause menu, so the game is already held when it
  applies. A change from the bot (`--pad-join-after`) during a fight waits the same way:
  `Main._change_local_roster` asks the fight to pause after the current move, applies the roster
  when it gets there and lets the fight go on by itself. A waiting change is never lost: if the
  fight ends first it applies then. The fight goes on by a deferred resume
  (`Main._resume_quiet_pause`), as it does after a lost pad that came back before its pause landed:
  the pause can land inside the fight's event loop, which would stall if resumed from there.
- Local joining needs the map, a zone or a fight. The shop, campfire, event, treasure, loot and
  party screens have no pause menu, and the next map is never more than a stop away.

**Online: a friend drops in.**

- Nothing to press on the host. The online pause menu (host and friends) shows the address in gold
  under PAUSED: `Address  192.168.1.20     Port  7777`. The friend opens Join Online and connects.
- **Who gets in** (`JoinGate.decide`, pure; `Net._hello` asks it after the build check):

  | Case | Result |
  |---|---|
  | the players screen is open (before Start, or after Again) | the lobby as before; "Game full" at 3 |
  | a started run, the hello has a seat's token | that seat back (#205), even with drop-in shut |
  | drop-in shut (Start to the first screen, the run end, Again's fade) | "Run busy, try again" |
  | a seat away at least `net_takeover_after_ms` (15 s) | that seat (the one away longest) |
  | a free seat | a new seat |
  | none of these | "Game full" |

  An old enough away seat goes before a free one: it is most likely the crashed friend. Before the
  welcome Net asks Main (`Net.drop_in_check`, `Main._drop_in_refusal`), so a refusal never comes
  after a welcome (`Net.refuse` is only a fallback). Drop-in opens at the end of `_new_run`, after
  the first screen is sent (a Rush's in `_new_rush`, after its `run_start`, 8.21), and shuts in
  `_close_decided_run`, `_close_decided_rush`, `_show_run_end`, `_play_again` and `_abandon_run`
  (`Main._set_drop_in`). The drop-in refusal texts and the not-found text ("Game
  full", "Run busy, try again", "Host not found") are at most 4 words, so they also fit the main
  menu notice (a test). The older connect texts (no answer, a different build) are not covered.
- **Which hero**: the donor rule, automatic. With the usual deals it is always a hero the host was
  playing. The newcomer's player is **joining** (`PlayerRoster.joining`, always also away): the host
  keeps playing that hero, no seat time runs, and a chip on every machine reads "P3 joining" (no
  countdown). The host plays `player_join`.
- **Catching up**: the newcomer's Join screen says "Joining the game ...". The host sends
  `run_start` (with `late`), the place screen with the whole run, and the fight if one is on, even
  one that just ended (`Main._catch_up`). The friend then sees where the host is: a watched run
  screen ("The host is choosing (P1)"), the zone (its loading card first; only the host walks), or
  the fight as it stands at the next hero's turn (the #205 resume).
- **The two-step hand-over**: the hero becomes theirs only once their own screen shows the game.
  1. In a fight the host sends the resume at the next quiet moment (a hero's turn or the end),
     never mid-attack.
  2. The newcomer's machine has built the place screen, or its fight has played everything the
     host sent since its first batch or the resume: nothing queued, no attack or skill still
     running (`CombatController.caught_up`, `drained`). So no sequence the host already played with
     itself judging that hero still waits there. It sends `seated_ready` with the fight it shows
     (each catch-up point once).
  3. The host hands the hero over at once outside a fight, or at the fight's next quiet moment
     (`queue_seat`, `seat_ready`). `JoinGate.ready_action`: the same fight, at the quiet moment;
     neither in a fight, now; else not yet (the client is behind or ahead and says so again at its
     next screen or fight). A fight counts from the moment the host announces it, during its swirl
     before anything is built (`JoinGate.host_fight`, from `Main._net_fight`), so a "caught up on
     the place screen" that lands then never hands the hero over before the newcomer's fight
     starts (it would start on the old roster).

  Then the chip goes and the friend's game prints "Playing now". The same two steps now bring back
  a #205 rejoiner's seat too (9.2).
- **Batches per fight**: every combat batch (and the resume) carries its fight's seed. A client
  keeps early batches per fight (`FightInbox`, pure). So a host that finishes a fight during a long
  catch-up and starts the next one never throws away the batches of the fight still waiting to be
  built. The newcomer builds the old fight from its resume, follows the zone return, then builds the
  next fight from its first batch. Whether a fight is a rejoin is read when its screen is built,
  not when the message arrives. A resume into a boss or guard fight that already raged shows the
  phase-two arena at once and plays the rage song, with no intro banner
  (`CombatController.raging_on_resume`).
- **Rosters through a sequence**: both runners hold a roster change that comes during a sequence
  until it hands back (`_held_roster`). A lower player leaving mid-attack moves everyone up, so
  presses and freezes must keep the player numbers the judges were built with.
  `CombatController.keeps_menu` leaves the open action menu alone when a roster arrives and the
  acting hero keeps its player on the same machine (every drop-in sends at least two rosters).
- **Joining versus away**: a newcomer who loses the connection while joining keeps no seat. The host
  drops them for good and their game forgets the token (no "Seat kept", no Rejoin), and they can
  drop in again. Their game decides this from the newest roster the host sent, even one still
  waiting behind a screen change (`Main._newest_roster`), so a friend already seated keeps the token. A #205 rejoiner who drops again while catching up stays away and keeps their
  token. A welcomed friend never seated (the `--seat-in-fight` wait) leaves no seat behind.
- **Two newcomers at once**: the host handles hellos one after another, so the second gets the next
  seat or "Game full". Both catch up and are seated on their own.
- **Again**: drop-in shuts, the players screen reopens to joins as before, and seats still marked
  away by friends catching up are given back first. A friend who dropped into run 1 and stays
  through Again is there from the start of run 2.
- Online has no Players row: hand-outs are automatic only (the online pause menu does not stop the
  game).

**Online: a crashed friend comes back.** The #205 token lives in memory, so a friend whose game
crashed or was closed had no way back. Now they restart, open Join Online and connect with no
token. They get the seat of the player away longest, if it has been away at least
`net_takeover_after_ms` (15 s): their old seat number and heroes. "P2 away, seat kept 1:12" becomes
"P2 joining", then goes. A fresher away seat is held for its own token (a Wi-Fi blip): the newcomer
gets a free seat if there is one and someone who is not away holds two heroes, else "Game full". A token that is still good gets its own seat
back first, as before. Once a seat is taken over its old token stops working.

**Online: what a late joiner keeps (#281 with #304).**

- The run plays with the host's Relic bag and Echoes, as with any friend (8.19).
- A friend who dropped in banks into their own Relic file only the Relics the run found after they
  joined, and only the Echo pips earned after they joined (on top of their own). The host sends
  `late` only in a drop-in's `run_start`. Their game takes the run's Relics and pips from the first
  run state it gets (`Main._join_relics`, `_join_mastery`; `RunState.relic_ids_since`,
  `pips_totals_since`) and banks nothing before that.
- Their run end's Kept row shows only those finds (`RunEndScreen.own_kept`), measured from their own
  collection plus what the run had when they arrived. A Relic the run had before they came shows
  there only if their own collection has it, so it never wears an Echo tag their file would not
  keep (their file keeps pips only for Relics it has).
- A win still unlocks their next Oath (8.15).
- A friend there from the start keeps everything. A #205 token rejoiner keeps their original start.
- A crashed friend who comes back with a fresh game counts as late from their return: what they
  banked before the crash (at each map) stays theirs, the finds from their last map to their return
  do not.

**In a Fight Rush** (phase 25, 8.21): local drop-in works as in a run. The pause menu (in a fight or on
the Rush screen) has the Players row; in a fight the change waits for a quiet moment, on the Rush
screen it applies at once. The Rush's record goes to the most players seen during it
(`RushState.most_players`, counted at each fight start, at each roster change and when the Rush is
decided), so a solo Rush a friend joins at fight 10 writes Duo from fight 10 on. Drop-in shuts when
the Rush is decided. Online (card #312, 8.21 "Online") a friend drops into a Rush, rejoins with a
token or comes back after a crash exactly as in a run: `run_start` says `mode` "rush" (with `late`),
the catch-up sends the Rush screen or the Rush fight with the whole state, and the hero becomes theirs
at the fight's next quiet moment, or at once on the Rush screen. A friend who got in after the Rush
started writes no record for it (D20).

**Dev and bot switches** (debug builds; the `AUTOPLAY_` lines only with `--autoplay`):
- `--pad-join-after=S`: a pretend pad joins the local run S seconds after launch, at the next quiet
  moment, through the same roster change as the overlay (`AUTOPLAY_ROSTER join p=2 device=1
  at=fight owners=0,1,0`).
- `--pad-leave-after=S`: the last local player leaves (`AUTOPLAY_ROSTER leave p=2 at=... owners=...`).
- `--roster-in-fight`: those two wait for the next fight and come a few seconds into it.
- `--host=1`: host and start at once alone; friends drop in later.
- `--join-after=S` (with `--join`): connect S seconds after launch, into a run going
  (`AUTOPLAY_JOIN after S s`, then `Joined mid-run as peer N` and `AUTOPLAY_DROPIN joined peer=N`).
- `--seat-in-fight` (online host): seat a friend who drops in only a few seconds into the next fight
  (they wait on "Joining the game ..." meanwhile).
- `--crash-after=S` (with `--join`): quit S seconds after launch without a goodbye, like a crash
  (`AUTOPLAY_CRASHED after S s`). Its log has no result line, and it ends with the engine's report
  of resources still in use at exit (not a game error).
- Host lines: `Player dropped in: P2 (peer N) at zone (fight)`, `AUTOPLAY_DROPIN P2 peer=N took=0
  place=zone fight=1` (`took` is the old peer of a taken away seat), `Fight resumed for peer N at
  turn T`, `Player plays again: P2 (peer N)`, `AUTOPLAY_SEATED P2 peer=N`. Friend lines: `Playing
  now: P2 heroes [1]`, `AUTOPLAY_SEATED P2 heroes=1`, `Joined late: N Relics, M Echo pips already found`.
- Every run end prints `AUTOPLAY_PLAYERS n=2 owners=0,1,0` before `AUTOPLAY_RESULT`, the same on
  every machine.
- Dev screens: `--screen=players_in_run` (the overlay over the pause menu, two players) and
  `--screen=pause_players` (the pause menu with its Players row).

**Known limits** (not bugs):
- A newcomer can take the seat of a friend away 15 s or more; that friend then needs a free seat.
- A crashed friend who returns with a fresh game loses what the run found between their last map
  and their return.
- Local joining waits for the map, a zone or a fight.
- A late joiner banks nothing found before they arrived, even Relics new to them.
- The run end's defence rows follow the heroes' players at the end of the run.
- A client far behind the host still risks its first attack timing out after its seat comes back
  (as for any lagging friend).

Tests: `tests/unit/test_dropin.gd`, the in-run players section of `test_coop.gd`, the pause tests in
`test_menus_clean.gd`, and the late joiner tests in `test_relics.gd` and `test_run_info_clean.gd`
(10).

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
- Rot-touched gear (`test_rot_gear.gd`, card #198): each new passive (healing received, kill heal,
  low-HP power, dodge and parry AP, thorns, gauge, negative start AP and Tough, rot) in the engine
  with its drawback; every shipped piece's numbers and a valid fight setup; Hunger Charm's Rest,
  Oathbreaker's Band's wounds and floor; spoils always offer one (and never force it on a single
  choice); shops sell them rarely; the bot's pick; Tonics cannot be upgraded and always give the
  plain amount; the same seed gives the same events; a save keeps worn pieces.
- Charged Dooms (`test_charged_dooms.gd`, card #195): the announce (countdown and break threshold on
  the intent), a Doom never opens a fight, gather then unleash with no break (the string hits the
  whole party), the cooldown, delays leave the countdown alone, damage counts toward the break to
  the point, a break cancels the charge and staggers (extra damage, the lost turn, the intent that
  stands), `stagger_turns` from tuning, bleed breaks too, phase two and fallen heroes keep the
  charge, snapshot and restore mid-charge play on identically, same seed same events, plain event
  values and fields, the mirror matches the engine after whole fights, the bots aim at the gatherer,
  setup refuses malformed Dooms, and each shipped guard and boss has exactly one well-formed Doom.
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
- Rejoining (`test_rejoin.gd`, card #205): seat tokens (one seat per token and per peer, no claim
  without the right token, a token wins its own seat, the grace time runs out exactly), the away
  seat in the roster (the host plays it, nobody moves up, it travels as data, the same seat comes
  back under a new peer id, a seat given up while another is away), and `resume_events()` (never
  mid-attack, changes nothing, a fresh mirror built from it equals the engine and ends the fight
  the same as a mirror that saw everything, and after the end it says how it ended). Online
  smoke: the client pair with `--drop-after=S --rejoin`.
- Save & Quit (`test_run_save.gd`, temp files only): a save round trips the whole run, numbers come
  back as ints, unknown keys survive, other content or format and damaged files are refused, a
  failed write keeps the old save, the backup covers a broken main file, delete clears all.
- Online smoke test: start `--autoplay --host=2 --seed=N --quit-on-end` and then
  `--autoplay --join=127.0.0.1 --quit-on-end` (both headless, about 25 to 30 minutes, so
  `timeout 2700` each). Both print the
  same `AUTOPLAY_RESULT run_...` line and the same `AUTOPLAY_MIRROR` hashes, and no ERROR lines.
  Every host uses the tuning port, so only one online game can run from the repo at a time.
- Drop-in co-op (`test_dropin.gd`, phase 25, 9.3): the roster's mid-run join (the donor rule, the
  refusals), leave and trade, `joining` travels as data and follows a drop, `same_as`, P1's play
  device; the join gate (lobby, token, shut, new seat, away seat), `ready_action`, `SeatBook.size`
  and `longest_away`, the short refusal texts, the takeover wait in tuning, `FightInbox`,
  `keeps_menu`, runners holding their roster through a sequence, the `late` flag's source, the dev
  switches. `test_coop.gd` checks the in-run overlay (never resets the roster, P1's real device,
  join, P2's Back and a keyboard P2's Esc leave, P1's close, Play, no Oath, trades, the pre-run
  left/right unchanged, the leave chip, modal, no change is the same roster); `test_menus_clean.gd`
  the pause row and the address note; `test_relics.gd` and `test_run_info_clean.gd` a late joiner
  keeping only later finds. Autoplay checks (headless): local `--run --players=1
  --pad-join-after=30 --pad-leave-after=240`, `--players=2 --pad-join-after=20 --roster-in-fight`
  and `--players=3 --pad-leave-after=20 --roster-in-fight` print their `AUTOPLAY_ROSTER` lines and
  the matching `AUTOPLAY_PLAYERS`. Online, `--host=1` with a `--join-after=45` friend (and with
  `--seat-in-fight` and `--join-after=20`), a third player into `--host=2` at 60 s, a
  `--crash-after=40` friend replaced by a `--join-after=75` one, and two newcomers at once all end
  with the same `AUTOPLAY_PLAYERS` and `AUTOPLAY_RESULT` lines on every machine still there, and a
  late joiner's `AUTOPLAY_MIRROR` lines equal the host's last ones.
- Fight Rush (`test_rush.gd`, `test_rush_data.gd`, `test_rush_screens.gd`, phase 25, 8.21): the fight
  counter, kinds, tiers and boss cycle, depth, HP, power and tempo per fight, deep versions from the
  Ruins tier, boss growth past the home depth, the card sets and their fills (no Key, treasure, gold
  or rot-touched Relic), Heal with Rest Relics, the boss heal, spare XP and extra picks, Relic slots,
  the head start, the dict round trip and its refusals, the salts, `RushRecords` (buckets, better,
  `allowed`), the switches and dev screens; the shipped data file (validate, the tier table, stale
  data, a 70-fight walk); the Rush screen, the end screen, the end hints and the lobby title; the New
  Run cards in `test_choice_cards.gd`, `test_save_menus.gd`, `test_branding.gd` and
  `test_menus_clean.gd`. Bot checks (headless, `--quit-on-end`, at most 3 Godots at once, each capped
  with `--rush-fights`; a good one prints `AUTOPLAY_RESULT rush_...` and no ERROR lines):
  `--autoplay --rush --rush-fights=3 --seed=7` (`rush_capped fight=3 wins=3 record=0 new=0`, depth
  0, 1, 2), `--autoplay=miss --rush --seed=7` (`rush_over fight=1`), `--rush-start=5 --rush-fights=1`
  (an elite and a Relic card), `--rush-start=10 --rush-fights=1` (the Gorged One; Train, Relic,
  Relic), `--rush-start=50 --rush-fights=1` (the Hollow King, `enemy_hp=280`, extra picks),
  `--rush-start=21 --rush-fights=3` (deep versions, tempo 80, 79, 78), `--players=2`,
  `--pad-join-after=50 --rush-fights=4` (`players=2`) and `--autoplay=escape --rush --rush-fights=1`
  (no Run button, no hang). Never an uncapped Rush bot: a perfect bot may never lose.
- Fight Rush online (`test_rush_online.gd`, card #312, 8.21): the mode in `lobby`, `again` and
  `run_start`, protocol 4, a friend building the host's Rush, fights and watched screens, the host's
  Give up and End the game, the records verdict and the late rule, catch-up mid-fight and on the Rush
  screen, drop-in opened and shut with the Rush, Again with the same seats; the Host cards in
  `test_choice_cards.gd`. Bot pairs (headless, one online game at a time, `timeout 400` each): host
  `--autoplay --rush --host=2 --rush-fights=4 --seed=7 --quit-on-end` with a `--join=127.0.0.1`
  friend (about 140 s), with a `--drop-after=50 --rejoin=5` friend (rejoin), and with a
  `--crash-after=40` friend replaced by a `--join-after=75` one; and the same host with `--host=1`
  and a `--join-after=60` friend (drop-in). Every machine still there prints the same `AUTOPLAY_PLAYERS`
  and `AUTOPLAY_RESULT rush_capped fight=4 ...` lines, and a late friend's `AUTOPLAY_MIRROR` lines
  equal the host's last ones.
- Save & Quit smoke test: `--autoplay --run --seed=N --save-path=FILE`, stop it part way with a
  timeout, then `--autoplay --continue --quit-on-end --save-path=FILE`: the second run prints
  `Run continued: ...` and plays on from that stop. A finished run deletes FILE.
- Run smoke test: `--autoplay --run --quit-on-end` (add `--seed=N` for a fixed map). The bot
  picks a shop when it has gold, a rest when someone is at or under 60% HP (or the party averages
  under 75%), an elite stop only while the party is healthy, else a zone; in zones
  it walks to the guard, after its healing items; in shops it buys what it can for whoever is lowest; it takes the first
  loot and puts every bag item on whoever has the most free slots. Ends with
  `AUTOPLAY_RESULT run_victory|run_defeat stops=N fights=N level=N gear=N gold=N seed=N oath=N`
  (add `--oath=N` to play at an oath, 8.15).
- Phase 2 (`test_skills.gd` and additions elsewhere): press prompts and press damage, follow-ups
  (declared per ally, voided after missed presses, gauge), the team ultimate (gauge check, all
  strike, revive), revive and heal and AP gifts, Exposed / Guard / Taunt / Slow / Riposte /
  Payback, turn delay and hasten, intents (announced at start, the attack matches the intent,
  re-targeting when a target falls), duplicate enemy names, the press rules for every shipped
  ability, every encounter starts. Autoplay picks skills and allies' targets and presses skill
  and follow-up prompts at window centre.

### 10.1 Quiet picture runs (card #168)

A windowed test run (`--shots`, `--screen`, an autoplay with pictures) used to grab keyboard and
mouse focus, which broke whatever the owner was playing at the time. `quiet_run.bat` fixes that.

- **Use**: `quiet_run.bat <the game's own switches>`, for example `quiet_run.bat --shots=2 --screen=menu`
  or `quiet_run.bat --autoplay --shots=3 --quit-on-end`. No `--` needed. Launcher options go first:
  `-Size 1280x720` (default 1920x1080, shrunk to fit the screen, always 16:9), `-Headless` (no
  window, for checking the launcher), `-DryRun` (print the plan: screens, place, command),
  `-PrepareOnly` (build the shadow project only), `-NoImport`. A switch that holds `|` needs quotes.
- **Where the window goes**: the first screen that is not the main one, centred. With one screen
  it opens on that screen and is pushed to the bottom of the window stack (no activation) for the
  first 30 s, so it does not cover the owner's game. It starts with no sound (`--audio-driver Dummy`).
- **How it never takes focus**: Godot's no-focus window flag (`display/window/size/no_focus`) must
  be set before the window exists and has no command-line form. The launcher therefore builds a
  shadow project in `%LOCALAPPDATA%\Rotsworn-quiet\<folder>-<hash>\`: its own `project.godot` (a
  copy of the real one with `no_focus=true` and windowed mode), folder links (junctions) to every
  real folder and copies of the root files. Godot runs with `--path` on the shadow. The real
  project and its `project.godot` are never edited and no `override.cfg` is used (one next to the Godot
  exe was not read in a test, and one in the project folder would be read by every normal start;
  `project_settings_override` is a fixed path in `project.godot`), so a normal start, the
  editor or the tests can not pick the flag up, even while a quiet run is going. Saves, settings
  and the `shots/` folder are shared with normal runs (same game name).
- **In the game**: `QuietWindow.active()` reads the same project setting. `PlayerSettings.apply_fullscreen`
  then leaves the window alone, because fullscreen or maximised would activate it. A test checks
  `project.godot` never contains `no_focus` and that a test run is not quiet.
- **Checking it for real** (opens a window, only with the owner's OK; the owner keeps typing in
  another window meanwhile): `powershell -NoProfile -ExecutionPolicy Bypass -File tools\quiet_focus_check.ps1 -Seconds 20 --shots=2 --screen=menu`.
  It remembers the focused window (`GetForegroundWindow`), starts the quiet run hidden, samples
  the focused window's process 10 times a second and prints where the game window sits (which
  screen), then PASS, FAIL (game had focus) or INCONCLUSIVE (no window appeared). The launcher
  itself was checked headless (settings differ between the shadow and the real project, a full
  autoplay fight through the shadow ends with `AUTOPLAY_RESULT victory`); the live window test is
  still to be done.
- **Limits**: Windows only. A new window is shown without activation but may flash on top of other
  windows for a moment on a one-screen PC before it is sent to the bottom. The window cannot be
  typed into (that is the point); bots and `--menu-keys` do not need input.

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
16. **Review pass** (built 2026-10-17 while the owner was away, waiting for playtest; branch
    `phase16-Review`, cards #173 to #200): the whole game reviewed against the game-dev skills in
    `.claude/skills/`, then fixed and made harder. Run: Oaths (8.15), Save & Quit (8.14), run
    exploits and the final boss (8.13), "?" events with real prices and ambushes (8.7), rot-touched
    gear (8.16). Fights: rends and sweeps (must parry / must dodge, 2.4), faster enemies with depth
    (8.3), smarter enemies (2.3), hits that leave a mark (2.7), Charged Dooms (2.3), trauma shake and
    big-moment impact (7.3), the arena's phase-two shift and zone air (7.3, 8.12). Also: co-op
    hit-stop fix, pad-drop pause, rebinding (6), Flashes setting, defeat recap, resuming music, the
    Rot Journal, ground textures and event pictures (5.4), build fingerprint and release-build
    switches, voice pool and limiter.
17. **Relics and Echoes** (built 2026-10-18, waiting for playtest; branch `worktree-phase17-Relics`,
    cards #212 to #220): the run's gear became Relics kept forever (stat lines, levels from copies,
    drops from every monster), wearing a Relic teaches its Echo for that run only (Echo points from
    level ups), Relic slots that open during a run, the main menu's Relics screen and the Echoes
    screen, Reset progress, +5% enemy power and Oaths 11 and 12, and a tutorial lesson (8.17).
    After the first playtest (user loved it): the Relics and Echoes pages restyled like E33's
    Pictos and Lumina pages, and the backpack's charms removed, six of their ideas becoming
    Relics (card #240, 8.1).
18. **Blender world** (done 2026-10-18: built while the owner was out, merged to main on their
    say-so; cards #221 to #237; 5.6): the solid world made in 3D
    with Blender like Octopath Traveler's, and more life in the zones. Rule: hard, solid things
    become Blender pieces; soft, thin or swaying things (grass, ferns, reeds, bushes), people,
    animals, heroes and monsters stay flat pixel art. Five steps. Step 1 tools: the test pieces
    (#221), a Blender kit with shared parts, a check and a preview sheet (#222), pieces with more
    than one texture, round collision and glow (#223). Step 2 old props to 3D: stone and ruins
    (#224), wood and village (#225), shrines, seals, gate and fountain (#226), lamps and fires with
    flat flames (#227), one tree tried with a 3D trunk and flat leaves (#228, idea). Step 3 new
    pieces and a living world: stairs, bridges, broken houses and towers (#229), raised ground with
    ledges and cliff edges, looks only at first (#230), more plants from the art kit (#231), living
    water and a stream (#232). Step 4 fill the zones: Rotten Hollow (#233), Ashen Ruins (#234),
    Sunken Bog (#235), the fight arenas (#236). Step 5: performance (#237).
19. **Monsters and effects** (built 2026-10-19, waiting for playtest; branch `phase19-Monsters`,
    cards #245, #246, #252 to #264; as built in 2.17): more
    3-monster fights (3 stays the most; each monster in a 3-fight gets less HP so fights do not get
    longer, #245) with an area skill each for Brin and Cass (#261, only Alder had one). Six new
    monsters in two batches, each with a job and one mark hit (#246): batch 1 Rot Rats (small fry,
    always in 3s, Rot, #255), Ember Slinger (ranged only, Burn, #256), Barrow Brute (large, slow,
    must-parry slam that Dazes, #257); batch 2 Marsh Lantern (ranged caster, Shock, #258), Rot Priest
    (heals or shields other monsters, Hush, #259), Pus Tick (bursts after 3 turns, Blight, #260).
    Five new hero marks next to Rot, Blight and Weak (2.7): Burn (big HP loss, 2 turns), Shock
    (smaller timing windows), Slow (turns come later), Daze (skip the next turn), Hush (no skills),
    in the Glossary (#252) and as icons on the hero panels (#262). Every monster gets one mark hit,
    at most one per attack, in every fight but the first zone (was hard fights only, #253). Lifting
    marks: Cass's Purify (every mark off one ally, no new ones for 2 turns), Antidote and Holy Water
    items (#254), Relics against marks (#263), a tutorial lesson (#264, idea).
20. **Relic balance and a clean Y screen** (done, approved 2026-10-19 after a playtest, v0.20.0;
    8.17, 8.18; merged with three side fixes: #269 ground flicker, #241 stay in the zone after the
    guard, #268 enemy HP panels fade during attacks): 16 more Relics, 50 in all, eight with new effects (#242); drops
    25% rarer, 8% (#243); the Relic bag of 10 the team brings into a run, picked on the main menu
    (#265; bag upgrades between runs later, #266 idea); the Y screen rebuilt as four icon tabs
    (Relics, Bag, Hero, Skills) with one info strip, toasts and fewer words (#270, the owner picked
    concept A with concept B's strip and shape icons); Relic icons whose shape says the category
    (#271).
21. **The roguelite pass** (done, approved 2026-10-20 after a playtest, v0.21.0; talked through
    2026-10-19 in #267 and #272, built overnight on branch `phase21-Roguelite`; 8.19): Echoes learned for good, Relic levels per run (#280), the Relic
    bag from 3 to 6 (#266), friends keep their finds online (#281), Alder's pack with pockets instead
    of the grid (#282), defence counts and pays (#283), one more run together (#284), a pact at the
    start (#285), a map with a dare (#286), no free stops (#287).
22. **Fewer words, more icons** (done, approved 2026-10-20 after a playtest, v0.22.0; 7.13): the
    practice key list off the fight screen (#275), press and defence timing numbers only in practice
    (#276), F1 Stats only in practice (#290), a won fight's end as icon rows (#273, #274), enemy HP
    bars that never stretch (#279), Keyboard and Controller settings pages (#277), a ranged hit icon
    (#278), two or three choices as side-by-side cards with icon chips (#288), the zone's goal as
    icons with no First Strike sentence and no gold (#289) and a First Strike tutorial card (#291),
    plus an owner-asked sweep of menus and run screens (pause, settings, calibration, players, join,
    map, shop, run end, Echoes, Journal). Then on 2026-10-21: skill chips in fights (#292), tutorial cards
    with pictures (#293), a quieter map legend (#294), shop item chips (#295) and a plain red party flag.
23. **Run up and swing** (done, approved 2026-10-22 after a playtest, v0.23.0; talked through
    2026-10-21; cards #244, #296, #297; 3.12 and 5.4): melee looks
    like a real attack. Today a lunge is the whole trip in about 0.2 s, so it reads as a slide from
    the enemy's spot. Now an attack of claw, bite or blade hits starts with a run to its target,
    added before the attack clock starts (about 0.5 s, presentation only), so press timing and the
    wind-up's length do not change. The enemy winds up next to the hero and swings: a claw or weapon
    arc whose hit frame lands at impact (`approach_ms` becomes the swing). Through a string it stays
    close and swings again (stepping over when the next hit has another target), then runs home
    after the last hit. Throws and ground slams stay home as now. First the Rotten Husk (claws) and
    the Hollow King (cleaver), playtested, then every other melee enemy. Brin and Alder also run all
    the way up for their attacks (today half way, `skill_approach_share` 0.55, then a lunge); Cass
    casts from her spot and keeps her look. Brin's idle holds the daggers in a reverse grip, high
    and low (#296), and Alder's idle carries the shield on his forearm at his side (#297); both
    picked by the owner from drawn options on 2026-10-21 and in the sprites (5.4).
24. **Feel and atmosphere** (done, approved 2026-10-23 after a playtest, v0.24.0; built 2026-10-22
    on branch `phase24-Feel`; cards #298, #299, #300, #303, #307, #308): controller vibration with a Vibration setting (7.14), the defence streak
    with a gauge reward and a music swell (2.18), weather and time of day in zones (8.20), and the
    rats' own voice (#298, 5.3). New sounds picked by ear on 2026-10-22: rat voice, thunder, streak
    swell, rain and wind loops. Added on 2026-10-23 from an idea search: skill presses climb with a
    finish for a perfect skill (#307), and the killing blow goes quiet (#308) (7.15).
25. **Playing together** (started 2026-10-23, branch `phase25-Together`): drop-in co-op (#304) and
    leaving or swapping heroes mid-run (#311) are built, waiting for playtest (9.3). A friend joins
    a run already going, on a local pad from a Players row in the pause menu or online with nothing
    for the host to press, and takes a hero P1 or the host was playing; a friend whose game crashed
    drops back into their seat; a late online joiner keeps only later finds. Local friends leave or
    swap heroes from the same overlay. Fight Rush (#305) is built too, waiting for playtest (8.21,
    owner decisions and defaults agreed 2026-10-24): New Run opens Run / Fight Rush cards; fight
    after fight for the furthest fight, no map, zones, shops or campfires, harder every fight, an
    elite every 5th and a boss every 10th; after each win pick 1 of 3 cards (Heal, Train, an item;
    Relics after elites and bosses); one record per party size; nothing goes back. It brings back
    the endless mode dropped in #267. Fight Rush online (#312) is built too, waiting for playtest
    (8.21 "Online"): Host Online asks Run or Fight Rush, the host plays the Rush and picks the cards
    while friends play their heroes and watch the Rush screen with Party open to them, only the host
    gives up, friends drop in, rejoin or come back after a crash as in a run, and records stay on the
    machines there from the start (protocol 4). Ideas: Save & Quit for online runs (#313), online
    friends take turns choosing (#314).

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
| 2026-10-17 | Save & Quit: one local-run slot, saved on the map and on entering a stop; Continue re-enters an unfinished stop from its start, never the map; deleted when the run ends or is abandoned; online runs not saved | card #174; quitting must not dodge a hard stop, and losing 2 acts to a closed window was the worst way to lose |
| 2026-10-17 | Floors: three calm variants per place mixed by region, mirrored and tone-drifted by a shader; ground pieces fade into the floor; props get contact shadows; scenery drawn at the fighters' pixel size (0.045 to 0.05) | card #186 (review: art-textures 0, 2, 3; audio-look 0); not an ease change: only the look |
| 2026-10-17 | Oaths: a ten-step difficulty ladder (Thorns, Want, Embers, the Deep, Crowns, Wounds, Scarcity, Silence, the Long Road, Rot), unlocked per machine by winning, picked in the players screen | card #173; the game should be hard, a ladder only ever adds difficulty (8.15) |
| 2026-10-15 | Lining digits everywhere; bold number font for HP, AP, gauge; slanted bold popups and damage numbers | user: the numbers' font felt cheap |
| 2026-10-15 | Hero portraits are painted pictures (made by the user with an AI image tool) turned into pixel art; big cards on the players screen, 64x64 faces everywhere else | user (#140, #141); a code-drawn try looked bad |
| 2026-10-15 | Attributes and Skills are buttons on each hero card; the info box only shows when needed | user: pressing LT / RT felt wrong, the box under the heroes was useless |
| 2026-10-15 | Tutorial on a practice fight where nobody can die, steps checked from fight events; offered once on the first New Run | user approved the six lessons (#131) |
| 2026-10-15 | Main menu cut to six rows: Online holds Host and Join, the tutorial is the first Practice card | user (#150) |
| 2026-10-15 | Tutorial: each hero lesson locks the menu to one glowing choice; no zone or map lesson (five lessons); the Skills lesson uses a skill without follow-ups (Taunt) | user play-test |
| 2026-10-16 | Every sound, song and loop offered against three free Openverse finds (CC0 / CC BY); 27 replaced, the rest kept | user asked; CC BY is fine with a credit on the credits screen |
| 2026-10-17 | Run exploits closed (Restock price rises, 2 Tonics per hero, a reset cannot heal, elites cannot be run from), small run bugs fixed, the Hollow King retuned to the hardest fight, the balance bot plays carefully | cards #175 to #178; the owner wants the game hard, so nothing here makes it easier (8.13) |
| 2026-10-17 | Co-op: a dropped pad holds the game under a card until it returns, is replaced or the seat is given up; the window losing focus pauses (offline only) | robustness review (#181) |
| 2026-10-17 | Handshake fingerprint covers scripts, scenes and the version, plus a protocol number; dev switches work in debug builds only; build_game.bat fails loudly | robustness review (#182); harder to cheat, no stale builds |
| 2026-10-17 | Sound: free voice first, steal the one nearly done, 30 ms per-cue cooldown, Master hard limiter | robustness review (#183) |
| 2026-10-17 | Move actions' deadzone 0.2, radial for the walk in every mode | robustness review (#184) |
| 2026-10-17 | Fight feel: camera shake is a trauma model; the biggest moments (last kill, boss kill, phase change, boss intro, hero down) get a short hold, shake, punch-in and flash; perfect presses, crits, heavy hits and ultimate hits hit harder; struck enemies recoil | cards #179 and the combat-feel review; presentation only, freezes at most 170 ms |
| 2026-10-17 | A success freeze ignores only its owner's double tap; a teammate's press inside it is judged as if the freeze had not happened (`FreezeLedger`) | bug #180: one player's parry swallowed another player's on-time press in local co-op |
| 2026-10-17 | "Flashes" setting: Full / Reduced / Off for screen flashes and white hit flashes | card #185, photosensitivity; default Full |
| 2026-10-17 | F1 reading-aid toggles (G, T, L, H, C, V) are practice-fight only | a run fight is the real game; same rule as the training ring |
| 2026-10-17 | RUN OVER shows a recap of the last fight (enemies, stop, act, oath, hardest hit, last blow, defence); zone song and ambience resume after a fight; elite fights have an `elite_path` song slot (empty); Oath of Want now cuts fight gold 25% (`gold_percent_add`) instead of "start with nothing" | cards #191, #192, fix to #173; the start gold is already 0, so the oath did nothing |
| 2026-10-17 | Every player action can be rebound in Settings > Controls, key and pad separately; the first input of an action is replaced, the aliases stay; conflicts only count between actions needed at the same time (swap offered); Escape, F2 and the pad's Menu button are reserved; applies to every pad | card #190; the two defence buttons can never share a key (no one-button parry and dodge), nothing can lock the player out, and the stamped timing path is untouched |
| 2026-10-17 | Smarter enemies: no move more than twice running (data: `max_in_a_row`, `cooldown_turns`, finisher and desperation weights), and single-target attacks pick by a per-enemy rule (WOUNDED, LOWEST_HP, MARKED, AVOID_LAST) with a bias; Taunt still wins | card #189 (review: combat-rules-ai); the owner wants it hard, a weak hero must be in real danger; no attack file uses finisher or cooldown yet, to tune with play |
| 2026-10-17 | Forced-choice hits: a rend (parry only, bone) and a sweep (dodge only, green, never countered) in elite, guard and boss fights and from the deep variants, about one hit in four; uneven gaps in every one-button string, a feint in every hard string; enemy attacks speed up with depth, elites, guards, bosses and phase two, never under 70% of authored; windows unchanged | cards #187, #188 and review combat-feel #4, #5, #9: dodge-everything and a steady tap beat the defence; nothing made easier |
| 2026-10-17 | "?" events are real trade-offs: new prices (permanent max HP, a backpack item, a rotten-item curse, an ambush fight), every choice costs something scarce, gold and XP grow with depth, 16 events with act 2's own list, and a "?" stop can turn into an ambush (15% + 15% per "?" passed without a fight, seeded per stop, state in the run dict) | card #193 (review: run-structure); the owner wants it hard, so a "?" tempts and never gives for free (8.7) |
| 2026-10-17 | Enemy hits can leave a mark when undefended and survived: hero debuffs Rotting (6% max HP at turn start, never below 1), Blighted (healing -50%), Weakened (power -25%), or an AP drain; they refresh, never stack; Mend and Sanctuary cleanse one (all on a perfect press), the Salve one; shipped marks are hard-fight-only and on few hits (bile, rot combo, King's cascade, hyena bites, shade bolts); the intent, banner and hit icons announce them | card #194 (review: combat-rules-ai #3): failing to defend cost only HP, and Cass had no job beyond healing |
| 2026-10-17 | The arena shifts when a boss or guard enters phase two (sun, ambient, fog, vignette, lamps and a puff of embers or spores, over about a second; the Hollow King's throne goes blood red), and a zone's drifting particles also play, thinner, in its fights | card #196 (review audio-look #6, #9 and art-textures #11): a boss's rage was a banner over an unchanged room, and the fight dropped the zone's air; presentation only (nothing in the engine or the golden), slower under Reduced and Off flashes |
| 2026-10-17 | Where phase 16 features meet: the run save is deleted the moment the last fight is decided (and the win opens its oath then); a save from another build is kept, not deleted; Continue resumes after an event choice, purchase or opened chest instead of replaying the stop; phase-two-only attacks get their projectiles and animations; a Doom picked inside a hero's skill is announced; a pad drop on an idle fight shows its card | card #197 (integration review): a window close dodged event risks and shop restocks, a patch or the editor destroyed a good save, and a decided run could be replayed (8.14) |
| 2026-10-17 | Charged Dooms: each guard and act boss has one signature Doom (Gorge Burst, Brood Tide, Ashfall, Timber Fall, Crown of Rot), announced with a countdown (2 or 3 enemy turns) the party can break by dealing a share of the enemy's max HP (13% to 45%): the Doom is cancelled and the enemy loses its next turn and takes +50% damage; unbroken it unleashes as a party-wide string of 8 to 10 hits with rends and sweeps; delay skills never reset the countdown; never the first pick of a fight, cooldown 2, about one per 4 to 6 boss turns; the bots focus the gatherer | card #195 (review: combat-rules-ai #9, E33 break meets Slay the Spire intent); the owner wants it hard but readable; break shares set from bot runs, to retune from play |
| 2026-10-17 | Rot-touched gear: twelve strong pieces that each cost something (Rotten Crown, Gravebound Ring, Hunger Charm, Last Ember, Ash Veil, Thorned Gauntlet, Oathbreaker's Band, Chain of Silence, Bloodletter's Fang, Hollow Mantle, Pale Tithe, Plague Bell), in their own violet colour, as a `rot_touched` flag and a data-driven drawback on `GearData`; elite and boss spoils always offer one among their choices (never as the only choice), shops and chests weigh them 35%; Tonics cannot be combined or upgraded, so the 2-Tonic cap really limits max HP | card #198 (Slay the Spire boss relics, Expedition 33 Pictos; the owner wants it hard). A "skills cost +1 AP" drawback was left out (it touches the core's cost checks and the HUD); "1 AP less at fight start" instead. Numbers are first guesses, to retune from play (8.16) |
| 2026-10-17 | Every "?" event and each act's ambush page has its own painted 128x64 scene (`sprites/events/`, drawn by `art_kit/assets/event_art.py`: a flat dithered back plus a 3D-rendered subject, one palette, at most 96 colours); the event screen shows it at scale 4 in a thin worn-gold frame (`StopVisuals`, `stop_visuals.tres`), nearest filter, with the old question mark as the fallback for a missing file | card #199; the owner found the tiny question mark in a black void flat, and each event is a story worth seeing (8.7) |
| 2026-10-17 | The Rot Journal: a main-menu book of every enemy and attack the player has met (portrait or silhouette, where met, times beaten, each attack's hit kinds, marks and Doom, and the player's parried, dodged, jumped and hit counts), recorded from the presentation's event stream into its own `user://journal.json` (versioned, atomic, `.bak`); only a person's run fights count, practice, the tutorial and bots do not (a dev `--journal-path` makes everything count) | card #200 (review ui-input #9, Slay the Spire's compendium): a hard game should let the player study what beat them; practice stays out because its cheats and its full fight list would unlock and pollute the book (7.11) |
| 2026-10-17 | Saves check only `data/` and the version (`DataHash.of_content`), not the code; the main menu has no description line under its rows | card #208 playtest: a code-only fix hid the user's saved run; the user found the line ("About 8 stops") out of date and not needed now that Continue and Journal exist |
| 2026-10-17 | Main menu: New Run, Online, Extras (Tutorial, Journal, Credits), Settings, Quit; Practice only in debug builds | user: the menu felt cluttered and Practice is a dev tool (card #208) |
| 2026-10-17 | The main menu shows the version (v0.16.0, bottom left) and the DragonRot logo (bottom right); the version follows the phase number | user, with Hollow Knight's menu as the model; the user picked 0.16.0 over restarting at 0.1.0 (card #210) |
| 2026-10-18 | "Controller recommended" notice between the studio intro and the title: icon from the art kit, worn-gold heading, fades out after about 3.5 s or on any button; all text and times in `branding.tres` | card #167; the game is pad-first (Expedition 33 model) and the notice is data so the user can tune or switch it off |
| 2026-10-18 | The lag calibration is offered once, on the first New Run that does not start the tutorial; lag compensation is saved per kind of input (keyboard / pad) and the judge adds the pressing device's extra lag to a base that is the smaller of the two | card #204 and review finding ui-input 3: a pad and a keyboard differ by a third of the perfect window; one question per New Run press so the tutorial and calibration offers never stack |
| 2026-10-17 | A saved run is continued by any build that can read it (no content check); only the save format version and RunState's own checks decide | card #208 playtest: one data change (the menu logo) hid the run again; the game changes almost daily |
| 2026-10-18 | Picture runs while the owner is at the PC go through `quiet_run.bat`: a shadow project (own project.godot with `display/window/size/no_focus=true`, folder links to the real folders) under `%LOCALAPPDATA%\Rotsworn-quiet`, window on the second screen (else behind the others), no sound; the game skips its fullscreen/maximise step when that flag is on (10.1) | a normal windowed run grabbed keyboard and mouse focus; the flag cannot be set after the window exists or from the command line, and an override file in the project folder or beside the exe would reach normal starts or is not read (card #168) |
| 2026-10-18 | Brin's shout is a short, plain young man's battle shout (a clear "hah!", 0.4 s, dry), not the old rising yell: four candidates sit in `assets/audio/sfx/candidates/`, number 1 (F.M.Audio's "Male Attack Grunt 1", CC BY 4.0) is in the game; the pick is one number in `tools/sound_kit/brin_shout_candidates.json` | card #171; the user wants a normal 25-year-old man's shout after seven rounds of finds missed it. Chosen from measurements and spectrograms (clean harmonics, no reverb tail, 0.3 to 0.5 s like Alder's and Cass's), not by ear, so the user's ear decides (5.3) |
| 2026-10-18 | Ranged enemy hits get an indicator: corner brackets on the hero the projectile flies at that close exactly at the declared impact (the judged time), plus a dashed path from the projectile, in the hit kind colour; on in run fights, Flashes-aware (`show_ranged_aim`, 3.9) | card #165 (not circles: the user dislikes circles in reading, 3.8) |
| 2026-10-18 | Cass's spells (Reveal, Smite) shoot after the press: the bolt leaves the staff at the press (or at the end of the window if none came) and the strike, numbers and hit-stop wait for it to land; judge, windows and engine unchanged (2.10) | card #166, like Expedition 33 |
| 2026-10-18 | Every menu works with the mouse: point to choose, left click confirms, right click or the back button goes back, the wheel scrolls; the pointer hides while keys or a pad are used and in fights and zones; the fight's own menus stay keys and pad | card #202 (review ui-input #4): PC players click "New Run" and nothing happened. One entry, `ListMenu.handle`, so every list screen got it; no Input Map action has a mouse event, so a click can never be a defence (6.2) |
| 2026-10-18 | Settings > Game > Text size (Normal 100%, Large 115%, Larger 130%), applied through `HudStyle.scaled` to every body, title and number label; the percents live in `ui_fonts.tres` | card #203 (review ui-input #5): fixed 14 to 22 px text. Gentle steps because the HUD plates and menu lists are laid out for 1920 x 1080 and were checked without a window; titles, banners and popups keep their size (7.5) |
| 2026-10-18 | The Glossary: a main-menu Extras row (after Tutorial) and a pause-menu row open a book of 109 terms in 14 topics (hit kinds and defences, skills, counters, marks, Dooms, enemies, the map, zones, gear, shops, the run), each with the game's own icon or colour and two or three plain lines, from `data/glossary/glossary.tres`; topic strip with left/right, terms in a `ListMenu`; colours and words are tested against `combat_visuals.tres` and `HudStyle` | card #207: the game has many icons and words and nowhere to look them up; the owner keeps the interactive tutorial for phase 17, so the book stands alone |
| 2026-10-18 | Online: a dropped client keeps its seat for 120 s (seat token, "P2 away" chip, the host plays its heroes meanwhile) and gets it back from the Join screen; mid-fight it gets the fight as it stands at the next hero's turn (`resume_events`); a heartbeat drops a silent connection after 3 to 6 s | card #205 and the net review: a Wi-Fi blip ended a player's run for good and a pulled cable froze fights for up to 30 s; playing the heroes for them beats a two-minute freeze, and handing the seat back between moves means no attack is half one player's |
| 2026-10-18 | Ranged-hit brackets made bolder: 8 px lines (was 5), 150 to 56 px (was 120 to 46), shown 450 ms before the throw (was 300), the dashed path at full strength | playtest: the user did not notice them (card #165) |
| 2026-10-18 | Rotsworn becomes a roguelite: monsters drop Relics (E33's Pictos, renamed; the run's 25 gear pieces become the first ones) kept forever on the machine; a copy levels a Relic; wearing a Relic for about 4 won fights (bigger fights count more) teaches its Echo (E33's Lumina, renamed) for that run only, and Echoes, their bars and Echo points (from level ups) all start over every run; Relic slots open during a run (1, then after the first guard, then after act 1's boss); online uses the host's Relics; enemies +5% power and two Relic oaths (11 the Empty Hand, 12 Forgetting); Reset progress in Settings | user idea and picks (names Relics and Echoes, Echoes learned again every run, only Relics and their levels stay, host's Relics online); replaces "nothing carries over" (#139); more choices, not more power, so the oaths keep it hard (8.17) |
| 2026-10-18 | The Relics and Echoes pages look like Expedition 33's Pictos and Lumina pages (card grid and big slot cards; tabs, costs, stats, attribute radar and points), with drawn diamond icons until real pictures | user playtest: "make the menuing bearable, similar to Expedition 33" (8.17) |
| 2026-10-18 | The backpack's charms are removed: six of their ideas became Relics (31 in all), the rotten ones are curses that only hurt, the rest are faded treasure for older saves; shops sell 3 Relics | user pick (option A) after asking whether a backpack is too much with Relics and Echoes: charms were a third buff system; supplies, keys and curses still give real choices (card #240, 8.1) |
| 2026-10-18 | Test: world pieces (wall, boulder, stump) built in Blender by code, shown as blocks with a model and the zone's own textures (5.6) | user asked if Blender helps: the world gains most (plain boxes until now), the sprites already work; user picked a small test (card #221) |
| 2026-10-18 | Phase 18 "Blender world": solid things in 3D (Blender), soft things, people and creatures stay flat pixel art; plus more plants, ruins and living water | user, after the test; the mix is how HD-2D (Octopath) does it, and 3D grass would look busier and lose its sway (cards #221 to #237) |
| 2026-10-18 | Trees stay flat sprites | card #228 try: a 3D trunk under the flat crown clashed with the pixel leaves; the user left the choice open and flat was the recommendation |
| 2026-10-19 | Every push to main builds the Windows game on GitHub Actions and replaces `Rotsworn.zip` on the `latest-build` pre-release: one fixed download link for everyone (9.2) | owner asked if it was possible and costly: free for a public repo, no hand-sent zips, and one shared file keeps online fingerprints equal |
| 2026-10-19 | No Godot logo at start: the boot splash is plain black, then the DragonRot intro as before (7.5) | user asked; the studio intro already opens the game and black runs straight into it |
| 2026-10-19 | Phase 20 "Relic balance and a clean Y screen" (11, 8.17, 8.18): 16 more Relics (8 new effects), drops 10% to 8%, a Relic bag of 10 picked on the main menu (new finds join it while there is room; a slot opening mid-run shows a note), the Y screen as four icon tabs with one info strip and toasts, Relic icons shaped by category | user picked every recommended option, approved the Relic list, and picked concept A (tabs) with concept B's info strip and shape icons; Relic levels and Echoes are for phase 21 and the remaining text clutter is phase 22 |
| 2026-10-19 | Phase 21 "The roguelite pass" (8.19): Echoes are learned for good by filling a Relic's pips across runs and can then be worn in any run for Echo points, no Relic needed, one hero per Echo; Relic levels last one run; the bag starts at 3 and grows to 6 with Echoes learned; the grid backpack becomes Alder's pack with pockets; plus friends banking online, defence counts, Again, a starting pact, a crowned elite and priced stops | owner: levels kept forever made the game easier the more you played and relearning Echoes every run was busywork (#272); "learned is usable" was the owner's own reading (option A); the grid lost its job when the charms went. Dropped: new heroes, endless mode, a between-runs currency, a daily leaderboard (#267) |
| 2026-10-19 | Phase 19 "Monsters and effects" (11): six new monsters in two batches, five new hero marks, one mark hit per monster in every fight but the first zone, Purify plus Antidote and Holy Water to lift them, area skills for Brin and Cass, more 3-monster fights | user asked for small fries, ranged-only and large monsters, status effects, a way to cleanse them and up to 3 monsters a fight; user picked every recommended option |
| 2026-10-20 | Phase 22 "Fewer words, more icons" (7.13): practice-only numbers and keys, icon end screens, enemy panels capped at the HP bar's width, status and ranged-hit icons, 2-3 choices as side-by-side cards with icon chips, zone goal as icons, Keyboard / Controller settings pages, a clutter sweep of every menu and run screen | owner, 2026-10-20: "i hate text only show me icons with text and if its 2 or 3 choices list them horizontally"; cards #273 to #279 and #288 to #291 |
| 2026-10-21 | Phase 23 "Run up and swing" (11): claw, bite and blade enemies run to their target before the attack clock starts, wind up next to the hero and swing, stay close through a string and run home after it; throws and slams stay home; Husk and Hollow King first | owner: "first we need the monster to come up to the person he is hitting, second he would swing his attack"; picks: add the run's time (not cut into the wind-up), stay close between hits, two enemies first (card #244) |
| 2026-10-21 | Brin and Alder run all the way up for their attacks; Brin's look and Alder's idle (shield resting at his side) are redrawn from options the owner picks; Cass unchanged | owner: "its mainly brin, he looks weird in general", "cass looks good in idle and attack" (cards #244, #296, #297) |
| 2026-10-21 | Brin keeps his hair and body; his idle holds both daggers in a reverse grip, "high and low", and every dagger shows its grip and pommel; Alder's idle carries the shield on his forearm at his side (5.4) | owner: "hair and body was ok, my issue is the way he is holding his daggers", he looked "like the wolverine"; picks from drawn options: grip A, stance D, Alder C |
| 2026-10-21 | All of Brin's frames use the reverse grip: ready, parry, dodge, every strike, cast, leap, hurt, fall, victory, and his zone walk, stand and pickup (5.4) | owner, after seeing the new idle in a fight: "his idle is good and breathing but now we need to change his whole attack and outside movement as well" |
| 2026-10-21 | Brin's ready no longer drops into a low crouch: he stands on guard like his idle when it is his turn or an enemy attacks (5.4) | owner: "can we stop the ducking as a whole" (picked Brin's crouch, not the enemies' wind-up crouch) |
| 2026-10-22 | Phase 23 "Run up and swing" done (3.12, 5.4): every claw, bite and blade monster runs up and swings up close, the Hollow King with a new overhead chop; Brin and Alder run all the way up for melee skills and hop home; Brin's reverse-grip look and moves, Alder's shield on his arm | owner played the Husk, the hyenas and the King: "good", "The King's chop and the heroes' run-up look good"; approved, v0.23.0 |
| 2026-10-22 | Defence streak (2.18): perfect parries and jumps in a row across a fight, a dodge keeps it, a hit ends it; every 5 fill the team gauge by 10; counted in the engine | card #300 left the reward open (gold, gauge or XP); gauge pays inside the fight and cannot overlap #283's Flawless spoils; an engine count is the same on every machine online |
| 2026-10-22 | Controller vibration (7.14): patterns in data, each pad buzzes for its own player's heroes, the whole party's moments buzz every pad here; Vibration 0-100% on the Controller page; bots and picture runs never buzz | card #299; the owner plays other games with the same pad while picture runs happen |
| 2026-10-22 | Weather (8.20): rain, storm, fog, wind and dusk per zone visit from the seed, presentation only; lightning only outside fights | card #303; a flash during an attack would hide the enemy's motion |
| 2026-10-22 | Phase 24 sounds: rat voice a (a real rat squeak), thunder c (thunder crack), streak swell a (film-score swell), rain a (forest rain), wind b (wind gusts) | owner's picks on the listening page |
| 2026-10-23 | The weather is not written under the zone's name | owner: "do we really need to state the weather?"; it shows itself and changes nothing in play (like Octopath Traveler); a label can come back if weather ever changes the rules |
| 2026-10-23 | Phase 24 also gets the skill press ladder with a perfect finish (#307) and the quiet killing blow (#308) (7.15) | owner picked the top two of a ranked idea search: small, no text, no new sounds, felt in every fight |
| 2026-10-23 | Phase 24 "Feel and atmosphere" done: controller vibration, the defence streak, weather and time of day, the rats' voice, the skill press ladder with a perfect finish, the quiet killing blow (2.18, 7.14, 7.15, 8.20) | owner playtested it: "already tested well done"; approved, v0.24.0 |
| 2026-10-23 | Drop-in takes a hero P1 (local) or the host (online) was playing; no computer teammate. The player holding the most heroes gives one: the usual deal's hero for the new seat (P2 Brin, P3 Cass) if they hold it, else their last (9.3) | owner (#304); the newcomer plays at once and nobody else loses a hero |
| 2026-10-23 | Local friends join and leave from a Players row in the pause menu; in a fight the change waits for a quiet moment, like pausing; left/right on that overlay trades heroes (9.3) | owner (#304, #311); timed attacks cannot be frozen fairly, so the roster never changes mid-move |
| 2026-10-23 | A late online joiner keeps only the Relics and Echo pips found after they joined; a win still unlocks their next Oath (9.3, 8.19) | owner (#304) |
| 2026-10-23 | Defaults (owner may overrule): online drop-in is open while a seat is free and shut once the run is decided and during Again; the host's address shows in the online pause menu; a local leaver's heroes go to P1; at most 3 players; no Players row in the tutorial; the pre-run players screen keeps its left/right (no trade there) (9.3) | not asked; chosen while building phase 25, keeping the approved screens as they are |
| 2026-10-23 | Default (owner may overrule): a newcomer may take an away seat only once it has been away 15 s (`net_takeover_after_ms`); this is how a friend whose game crashed comes back (9.3) | a Wi-Fi blip comes back with its token within seconds and must not lose its seat to a newcomer; a crashed game has no token |
| 2026-10-23 | Default (owner may overrule): a crashed friend who comes back with a fresh game banks only what the run finds from their return; what they banked at earlier maps stays (9.3) | their token and their start lived in the crashed game's memory, so the host cannot tell them from a newcomer |
| 2026-10-24 | Fight Rush (8.21): a mode next to the run, picked from New Run's two cards (Run / Fight Rush): fight after fight for the furthest fight, no map, zones, shops or campfires. Fight Rush brings back the endless mode dropped in #267 | owner (#305); it reuses the run's fights, party and Relics, so it needs no new monsters or places; online is its own card (#312) |
| 2026-10-24 | After every won fight the party picks 1 of 3 cards side by side: Heal, Train (attribute points) or an item; Relic cards only after elite and boss fights (8.21) | owner decision 1 (#305) |
| 2026-10-24 | No free heal in a Rush: Heal is a card; every boss fight ends with the whole party fully healed; a hero downed in a won fight gets up at 1 HP, as in a run (8.21) | owner decision 2 (#305) |
| 2026-10-24 | A Rush brings the Relic bag and the learned Echoes; nothing goes back: no Relic banking, no Echo pips, no writes to `user://progress.json`; a Relic card lasts for that Rush only (8.21) | owner decision 3 (#305) |
| 2026-10-24 | Rush fights get harder every fight with the run's depth growth per map row (one row per fight); every 5th fight an elite, every 10th a boss, the bosses cycle (three guards, the Husk Lord, the Hollow King); every number in `tuning.tres`, tuned with bots (8.21) | owner decision 4 (#305) |
| 2026-10-24 | Defaults (owner may overrule, 8.21 D1 to D21): level cap 10, XP past it earns extra picks; no Oaths; one record per party size with its date, the size being the most players seen; one sitting, no save, the record written at each fight start; no running away; New Run's Run / Fight Rush cards with the best on the card; Give up in the pause menu; Reset progress clears the records; bots and dev switches never read or write records; Rush fights count in the Journal; FLAWLESS is a plain chip; no pact; zone weather, never lightning in fights; card sets per fight kind (boss: Train, Relic, Relic) and extra picks on the normal set; deep monsters from fight 21; attack speed stops rising at fight 31 (the 70% floor); Heal follows the Rest Relics; no keys, treasure or gold Relics on cards; online late joiners write no record (#312); no gold on any Rush screen | not asked; chosen while writing the build spec and checked against the code, keeping every approved screen and rule of the run as it is |
| 2026-10-24 | Fight Rush online (8.21 "Online"): Online, Host opens Run / Fight Rush cards; the game's `mode` travels in `lobby`, `again` and `run_start` (protocol 4); the host plays the Rush and picks the cards, friends play their heroes in fights and watch the Rush screen with only Party open to them; drop-in, rejoin and a crashed friend's seat go through the run's paths | card #312; it reuses the run's online rules (host-authoritative, P1 makes the choices, approved 2026-10-12) and the drop-in code (9.3), so the Rush needed no new net paths beyond the mode |
| 2026-10-24 | Defaults (owner may overrule, 8.21 D7, D9, D20): online only the host gives up, and once a lost fight decided the Rush its row is End the game; Rush records stay on the machines there from the start (a friend who dropped in, or came back after a crash, writes none; a token rejoin keeps its start); the host sends its own records verdict in `run_start`, so a bot or dev Rush on the host keeps friends' records out too; a friend who drops in gets their hero at the fight's next quiet moment, as in a run | not asked; chosen while building #312: a loss must never turn into a Rush given up, a late friend did not play the whole Rush, and a friend's machine cannot see the host's switches |
| 2026-10-24 | Every defence press shows its move, even one that defends nothing (early, late, wrong button, locked out, in the lead-in): a missed jump jumps, a missed dodge slides, a missed parry raises the guard; judging and the lockout are unchanged, and a hit that lands always replaces the move (3.6) | owner playtest (#309): an early jump left the hero standing there |
| 2026-10-24 | Wind-up attacks charge in: an attack whose first hit winds up 850 ms or more (as authored) skips the run-up, winds up near home and charges in on its first lunge, reaching contact exactly at impact; quicker openers keep the phase 23 run-up; the attack clock, impact times and windows are unchanged, only the run before the clock goes (3.12) | owner playtest (#310): the Bloat should wind up from where it stands and charge in on the strike, for every wind-up attack; the 850 ms line keeps the approved run-ups (the Husk's swipe, the King's chop) as they are |
| 2026-10-24 | Review of #309 and #310: a missed press's move starts at the time on screen during a hit-stop, is not started for a hero with nothing left to defend when the hand-back would cut it off, and in an each-in-turn attack moves only the hero its hit strikes (3.6); a charging attacker winds up at home (`charge_windup_share` 0, no glide in its coil) and the 850 ms line moved to tuning as a pacing number (3.12) | code review; the owner's words were "wind up from where it stands" (asleep, not asked: a step out can come back by raising the share, with chase cells for the glide) |
