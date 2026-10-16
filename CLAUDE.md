# Rotsworn: project conventions

Co-op (1 to 3 players) turn-based RPG roguelike. Combat is modelled on Clair Obscur: Expedition 33,
the look on Octopath Traveler (HD-2D). Full design: `docs/DESIGN.md`. Keep that file current
whenever a decision is made or changed.

## The person you work with

- Not a game developer and has never used Godot. They test builds and give feedback; you write
  all code, scenes and data.
- Whenever they must do something by hand (install, click in the editor, test, map a controller),
  give exact numbered steps. The first time any editor feature comes up, say where it is on screen
  and what to click.
- Work in phases (see DESIGN.md). Stop after each phase, explain how to test it, wait for feedback.

## Git and GitHub

- Repo: https://github.com/JawadAlSaeed/Rotsworn (public; renamed from `Rotten-Lands` on
  2026-10-13, GitHub redirects the old URL). Branch: `main`. The local folder is
  `C:\Users\Drago\Rotsworn` (renamed from `RottenLands` on 2026-10-16).
- Commits are authored by the user as Jawad Al-Saeed <39744682+JawadAlSaeed@users.noreply.github.com>
  (repo-local `user.email`). GitHub blocks pushes that expose the private Gmail address.
- **Never credit Claude or Anthropic anywhere in git or GitHub.** No `Co-Authored-By` trailer, no
  "Generated with Claude Code" line, no session links, in commits, PRs, issues or release notes.
  This is enforced by `.claude/settings.json` (attribution off) and by `.githooks/commit-msg`
  (strips such lines). After a fresh clone run `git config core.hooksPath .githooks`.
- Commit or push only when the user asks, or at the end of a phase they approved.

## Task board (the user's "todo")

- Board: https://github.com/users/JawadAlSaeed/projects/2 (GitHub Project "Rotsworn", number 2,
  owner `JawadAlSaeed`, linked to the repo). Columns are the `Status` field: Todo, In Progress, Done.
  Each card is a repo issue with a `phase-N` label (1 to 6, see DESIGN.md section 11) plus
  `enhancement` (or `bug` for bugs). Done cards are closed issues.
- "Add X to the todo" / "put X on the board" means: create an issue on this board, no need to ask
  again. Pick the phase it belongs to (ask only if it is truly unclear), write a short plain title
  and a one or two line body, then reply with the issue link. The repo is public, so issues are
  public.
- Before creating a card, list the board (open and closed) and check for one that already covers
  it. If there is one, do not create a card: tell the user which card (title + link) instead.
- "Idea" (or anything the user sounds unsure about) gets an extra `idea` label; "todo" is a
  planned card without it. When unclear, treat it as an idea.
- Keep the board true: move a card to In Progress when work on it starts, and to Done (and close
  the issue) when the user approves that work. Add a card for any new feature or bug the user
  agrees to.
- At the start of a session, if the user asks "what's next" or similar, read the board first.
- IDs (stable): project `PVT_kwHOAl50qs4Bmqm-`, Status field `PVTSSF_lAHOAl50qs4Bmqm-zhlSrds`,
  options Todo `f75ad846`, In Progress `47fc9ee4`, Done `98236657`. Recipe (bash):
  ```
  url=$(gh issue create -R JawadAlSaeed/Rotsworn -t "TITLE" -b "BODY" -l phase-N -l enhancement)
  item=$(gh project item-add 2 --owner JawadAlSaeed --url "$url" --format json --jq .id)
  gh project item-edit --id "$item" --project-id PVT_kwHOAl50qs4Bmqm- \
    --field-id PVTSSF_lAHOAl50qs4Bmqm-zhlSrds --single-select-option-id f75ad846
  ```
  List cards: `gh project item-list 2 --owner JawadAlSaeed --limit 200 --format json`.
  `gh` needs the `project` scope (already granted; if lost: `gh auth refresh -s project`).

## Tools

- Godot 4.7.2 stable, GDScript only. Editor: `C:\Users\Drago\Godot\Godot_v4.7.2-stable_win64.exe`.
  Console build (for headless runs): `C:\Users\Drago\Godot\Godot_v4.7.2-stable_win64_console.exe`.
  Override either with the `GODOT` environment variable.
- Tests: GUT 9.7.1 in `addons/gut`. Always run them with `run_tests.bat --no-pause` (from bash:
  `cmd //c run_tests.bat --no-pause`; if cmd says "not recognized", run it from PowerShell:
  `& .
un_tests.bat --no-pause`). It imports first (a fresh clone or a new `class_name` makes
  plain GUT skip files silently) and fails if any test file did not load or the log shows a
  script error. Run `--headless --path . --import` before any `-s` tool script too.
- Tests must pass headless before you tell the user a phase is done.
- `run_game.bat` runs the game, `open_editor.bat` opens the editor, `build_game.bat` builds the
  shareable Windows game (`build/Rotsworn.zip`, preset in `export_presets.cfg`; needs the 4.7.2
  export templates, installed). Online players must all run the same build (the content
  fingerprint differs between a build and a run from the editor).
- Smoke test the whole fight without a human: run the game with `-- --autoplay` (bot defends
  and presses perfectly), `-- --autoplay=miss` (never presses), `-- --autoplay=mash` (mashes
  buttons), `-- --autoplay=escape` (presses perfectly and runs on its first turn) or
  `-- --autoplay=average --bot-skill=60` (plays like an average player for balance checks: lands
  that percent of its presses; prints an `AUTOPLAY_BALANCE turns= seconds= party_hp_percent=`
  line; with `--seed=N` its luck repeats too, else every run differs, so compare many runs). Add `--quit-on-end` to exit when the fight is over and `--encounter=ID` to pick a fight
  from `data/encounters/` (default `husk_fight`), `--first-strike` to start it with the advantage,
  or `--zone=rotten_hollow` to have the bot walk the zone and fight every roaming enemy (ends with
  `AUTOPLAY_RESULT zone_clear` or `zone_defeat`), or `--run` to have the bot play a whole run
  (map, zones to the guard, shops, rests, final fight; ends with `AUTOPLAY_RESULT run_victory` or
  `run_defeat`, about 10 to 20 minutes, so use `timeout 1500`). Add `--players=2` or
  `--players=3` to any of these for co-op (pretend pads; each bot player presses for their own heroes).
  Online: start `--autoplay --host=2 --seed=7 --quit-on-end` in the background, then
  `--autoplay --join=127.0.0.1 --quit-on-end`; both must print the same `AUTOPLAY_RESULT` and
  `AUTOPLAY_MIRROR` lines (use `timeout 1500`). Works with `--headless`. A good run prints
  `AUTOPLAY_RESULT` and no `ERROR` / `AUTOPLAY_ERROR` lines; a missing result line means a hang.
- To see the game without a person: run it windowed (not headless) with `-- --shots=S` (a picture
  every S seconds in `%APPDATA%/Godot/app_userdata/Rotsworn/shots/<name>/`), combined with
  `--screen=title|menu|settings|players|practice|credits|party|heroes|attributes|skills|calibration|tutorial|map|map_start`, `--autoplay`, `--run` etc.; `--menu-keys=fight_skills,menu_down` opens the fight menu's
  skills list (or any state; `|` moves on to the next turn) for pictures; `--pad-prompts` shows pad
  buttons, `--key-prompts` keyboard keys. Look at the pictures before telling the user a visual change is done.
- Always run headless Godot commands with a timeout (`timeout 120 ...`): a script error in a
  `-s` script leaves Godot running forever.

## Architecture rules (do not break these)

1. **Combat logic is a deterministic state machine driven by commands** (`scripts/combat/core/`).
   - Core classes extend `RefCounted`. They never touch `Node`, the scene tree, `Input`, `Time`,
     `OS`, signals to presentation, `randi()`/`randf()` or anything frame-dependent.
   - All randomness goes through `CombatRng` (seeded). HP, AP and damage are integers.
   - The only way to change combat state is `CombatEngine.submit(command)`. It returns a list of
     events. Commands and events are plain `Dictionary` values (easy to send over the network).
   - Same seed + same commands = same events. A test checks this.
2. **Real-time defence is judged outside the core** (`scripts/combat/timing/`), by pure classes
   (`DefenseJudge`, `AttackClock`) fed with input timestamps and the prompts the engine declared
   (windows, impact times). Results go to the core as a `resolve_prompts` command. This is what
   lets each network client judge its own player later. Local feedback (popups, hit-stop, sounds)
   comes from the judge at press time, never from engine events.
3. **Judge timing from input event timestamps, never frame polling.** Godot 4.7 input events carry
   no OS timestamp, so `DefenseInput._input()` stamps each press with `Time.get_ticks_usec()` the
   moment it arrives, and the judge compares that stamp with the hit's scheduled time on the same
   clock. Never use `Input.is_action_just_pressed()` for defence or timed presses.
4. **Content is data.** Characters, enemies, enemy attacks, abilities, encounters and sound cues are
   `Resource` files in `data/`. Scripts for them live in `scripts/data/`. Never hardcode content.
5. **Every global number lives in data, never in code.** Rules and judging numbers go in
   `data/tuning/tuning.tres` (script `scripts/data/tuning.gd`): timing windows, lockout, lag
   compensation and its bounds, base damage and HP, AP economy, counter percentages, hit-stop,
   cue on/off defaults, pacing. Presentation-only feel goes in
   `data/presentation/combat_visuals.tres` (script `scripts/data/combat_visuals.gd`): art paths,
   stage layout, camera, enemy choreography feel, pose lengths, flash/shake strengths, popup and
   banner feel, the calibration procedure. Zone presentation (follow camera, walking, transition)
   goes in `data/presentation/explore_visuals.tres`; how a place looks (light, fog, bloom, ground,
   arena decoration) in its `StageLook` in `data/looks/`. Per-move shapes (hit count, hit timing, percentages)
   live in that move's data file as integer percentages of the tuning values. Pure animation-curve
   shape constants (for example a share of a pose) may stay as named consts. Change values in the
   `.tres` files, never by editing the defaults in the scripts.
6. **Art and audio load from paths stored in data.** Replacing a placeholder means dropping a file
   with the same name into `assets/`. Missing files fall back to a visible placeholder and a
   warning, never a crash. Placeholders are generated by `tools/gen_placeholders.gd`; the real
   art is drawn by `tools/art_kit/` (DESIGN.md 5.4).
7. Presentation (`scripts/combat/presentation/`) reads `CombatMirror` (built from events in playback
   order), never the engine. It changes combat state only by submitting commands through
   `CombatController`.
8. Rules maths uses integers only (`CombatMath.percent`); no floats in `scripts/combat/core/`.

## Code style

- Follow the official GDScript style guide. Static typing everywhere (`var hp: int = 0`,
  typed function signatures, typed arrays where practical).
- Files and folders `snake_case`, classes `PascalCase` with `class_name` for data and core classes.
- Short doc comments (`##`) on public classes and functions. Comment the why, not the what.
- Input actions are defined in `project.godot`; see the table in DESIGN.md. Keyboard and gamepad
  must both work for every action.

## Folder map

- `data/` content resources (`.tres`), including `tuning/tuning.tres`, `branding/` (logo, title
  screen, credits, loading tips),
  `presentation/combat_visuals.tres`, `presentation/explore_visuals.tres`, `looks/`, `zones/`,
  `runs/` (the run; `runs/acts/` its acts), `events/`, `offers/` (shrines and wanderers), `items/` (backpack items), `gear/` and `clips/` (each fighter's animation
  layout, generated by `tools/art_kit/`)
- `assets/` sprites, audio (placeholders until real art arrives)
- `scripts/data/` resource class scripts
- `scripts/core/` shared helpers (asset loading)
- `scripts/combat/core/` deterministic combat engine
- `scripts/combat/timing/` defence timing judges
- `scripts/combat/presentation/` combat scene, views, HUD, camera, feedback
- `scripts/combat/input/` input stamping
- `scripts/stage/` building a place from data (environment, blocks, props, lights, vignette) and
  screen transitions
- `scripts/explore/` zones: walking, roaming enemies, zone HUD, zone bot, `ZoneAssembler` (lays a
  long zone's sections out per visit) and `ZonePath` (A* for the bot and tests)
- `scripts/run/` the run: `RunMap` and `RunState` (pure, tested), map, shop, campfire (rest), event,
  treasure, loot, party and run-end screens (`StopScreen` hands out gifts), the gold and HP strip
- `scripts/menu/` main menu, players screen (co-op lobby), settings, pause menu, yes/no prompt,
  the shared `ListMenu`, `MenuBackdrop`, `HintBar` (button chip hints) and `PromptLabel`
- `scripts/coop/` co-op: `PlayerRoster` (who plays which hero, pure, tested) and `DeviceInput`
  (reading one device)
- `scripts/net/` online: `DefenseArbiter` (host referee, pure, tested), `DataHash` (content
  fingerprint for the handshake)
- `scripts/autoload/` global singletons (`Audio`, `UserSettings` = `PlayerSettings`, saved per
  machine in `user://settings.cfg`, `Net` = `NetSession`, the online connection, `Prompts` =
  `ButtonPrompts`, which buttons the hints show)
- `scenes/` scenes
- `tests/unit/` GUT tests
- `tools/` headless helper scripts (placeholder generation, data bootstrap, `bootstrap_run.gd`
  for the run, shop, gear, boss and phase 4 zones; `bootstrap_zones.gd` for the long zones' sections,
  shrines and wanderers, DESIGN.md 8.5; `bootstrap_phase15.gd` for the mini-boss guards, elite fights,
  events and the run's two acts, 8.6 to 8.9, run before bootstrap_zones.gd); `tools/sound_kit/` builds the sound effects from
  real recordings (see its README); `tools/art_kit/` draws all the pixel art in Python (see its
  README: the art bible, `python tools/art_kit/build.py [module]`; the heroes' painted portraits come
  from pictures via `tools/art_kit/portraits_from_pictures.py`)
- `docs/` design docs
