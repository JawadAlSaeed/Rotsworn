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
- `run_game.bat` runs the game, `quiet_run.bat` runs it without taking focus (picture runs), `open_editor.bat` opens the editor, `build_game.bat` builds the
  shareable Windows game (`build/Rotsworn.zip`, preset in `export_presets.cfg`; needs the 4.7.2
  export templates, installed). Online players must all run the same build (the content
  fingerprint differs between a build and a run from the editor). The build friends play is made
  by GitHub Actions (`.github/workflows/build.yml`) on every push to `main`: tests, export, then
  `Rotsworn.zip` on the `latest-build` pre-release (stable link in README "Play it", DESIGN.md 9.2).
- Smoke test the whole fight without a human: run the game with `-- --autoplay` (bot defends
  and presses perfectly), `-- --autoplay=miss` (never presses), `-- --autoplay=mash` (mashes
  buttons), `-- --autoplay=escape` (presses perfectly and runs on its first turn) or
  `-- --autoplay=average --bot-skill=60` (plays like an average player for balance checks: lands
  that percent of its presses; prints an `AUTOPLAY_BALANCE turns= seconds= party_hp_percent=`
  line; with `--seed=N` its luck repeats too, else every run differs, so compare many runs). Add `--quit-on-end` to exit when the fight is over and `--encounter=ID` to pick a fight
  from `data/encounters/` (default `husk_fight`), `--first-strike` to start it with the advantage
  (a run's Fight stop opens with the First Strike ring instead, DESIGN.md 8.22: `--autoplay` presses
  it perfectly, `=miss` never, `=mash` mashes, `=average` at its skill; every Fight stop prints
  `AUTOPLAY_OPENING first_strike|normal stop=N`),
  `--weather=rain|storm|fog|wind|dusk|clear` to give every run fight but the boss's and every Rush
  fight that weather (DESIGN.md 8.20, 8.22),
  `--no-rumble` to keep the pad still (bot and picture runs never buzz anyway, DESIGN.md 7.14),
  or `--run` to have the bot play a whole run
  (map, Fight and Elite stops, shops, rests, events, final fight; DESIGN.md 8.22: there are no
  walkable zones; ends with `AUTOPLAY_RESULT run_victory` or
  `run_defeat`, whose `relics=` and `relics_held=` count the Relics the run has and those given to a
  hero, DESIGN.md 8.24; about 10 to 20 minutes, so use `timeout 1500`; add `--oath=N` to play it at difficulty
  oath N, DESIGN.md 8.15; a bot run starts with no Relics (its Relic book is empty, so it skips the
  starting pick), `--relics=all` fills its book with every Relic (each hero then takes the best one
  left, printed as `AUTOPLAY_START_RELICS alder=ID brin=ID cass=ID`, `-` for none, the same line on
  every machine, also when the step is skipped; online the host prints
  `AUTOPLAY_START_RELIC P2 ID hero=N ok=1` for each friend's pick), `--relics-path=PATH` lets it use
  and bank into its own Relic book, 8.17, 8.24), or `--rush`
  to have the bot play a Fight Rush (DESIGN.md 8.21; ends with `AUTOPLAY_RESULT rush_over`,
  `rush_gave_up` or `rush_capped`, one `AUTOPLAY_RUSH` line per fight). Always cap a Rush bot with
  `--rush-fights=N` (a perfect bot may never lose): 3 fights take about 90 s, later fights longer, so
  `timeout 400` for 3; `--rush-start=N` starts at fight N after a replayed head start (one head-start
  fight about 1 to 2 min; mechanics only, never balance); both imply `--rush`. Add `--players=2` or
  `--players=3` to any of these for co-op (pretend pads; each bot player presses for their own heroes).
  Online: start `--autoplay --host=2 --seed=7 --quit-on-end` in the background, then
  `--autoplay --join=127.0.0.1 --quit-on-end`; both must print the same `AUTOPLAY_RESULT` and
  `AUTOPLAY_MIRROR` lines (an online pair takes 25 to 30 minutes: use `timeout 2700`; every host uses
  the tuning port, so run one online game at a time). A Fight Rush online: `--rush` with `--host=N`
  hosts one (`--autoplay --rush --host=2 --rush-fights=4 --seed=7 --quit-on-end`), and the friend's
  plain `--join=127.0.0.1` follows the host's mode; both print the same `AUTOPLAY_RESULT rush_capped`
  and `AUTOPLAY_MIRROR` lines in about 140 s (`timeout 400`; a drop-in pair needs `--host=1`, DESIGN.md
  8.21). Saving an online run (DESIGN.md 8.14, 9.3): the host bot saves only with
  `--online-save-path=PATH`; `--save-quit-at=N` presses Save & Quit on arriving at stop N (host
  `AUTOPLAY_SAVED host ...` and `AUTOPLAY_RESULT run_saved`, friend `AUTOPLAY_SAVED friend ...` and
  `AUTOPLAY_RESULT host_saved`); `--continue-online` (with `--host=N` and the same save path) presses
  Continue once N players are in (`AUTOPLAY_CONTINUED host|friend ...`); `--seat-path=PATH` is a friend
  bot's seat file (it keeps its token there when the host saves and shows it on the next `--join`).
  Pair: host `--autoplay --run --host=2 --seed=7 --save-quit-at=3 --online-save-path=P --quit-on-end`
  plus friend `--autoplay --join=127.0.0.1 --seat-path=S --quit-on-end`, then host `--autoplay --run
  --host=2 --continue-online --online-save-path=P --quit-on-end` plus the same friend (both print the
  same `AUTOPLAY_RESULT` and `AUTOPLAY_MIRROR` lines). Works with `--headless`. A good run prints
  `AUTOPLAY_RESULT` and no `ERROR` / `AUTOPLAY_ERROR` lines; a missing result line means a hang.
  Drop-in co-op (DESIGN.md 9.3): `--pad-join-after=S` (a pretend pad joins the local run S seconds
  after launch, at the next quiet moment), `--pad-leave-after=S` (the last local player leaves),
  `--roster-in-fight` (those two come a few seconds into the next fight); online `--host=1` starts
  alone at once, `--join-after=S` (with `--join`) connects S seconds after launch into the run
  going, `--seat-in-fight` (host) seats a friend who drops in only a few seconds into the next
  fight, `--crash-after=S` (with `--join`) quits without a goodbye like a crash (that log has no
  result line and ends with the engine's resources-in-use report, expected). They print
  `AUTOPLAY_ROSTER join|leave p= ... owners=`, host `AUTOPLAY_DROPIN P2 peer=N took=0 place= fight=`
  and `AUTOPLAY_SEATED P2 peer=N`, friend `AUTOPLAY_DROPIN joined peer=N` and `AUTOPLAY_SEATED P2
  heroes=1`; every run end prints `AUTOPLAY_PLAYERS n= owners=` before `AUTOPLAY_RESULT`, the same
  on every machine.
- `-- --perf-log=S` (windowed) prints frames a second and draw calls every S seconds (vsync off).
- **While the owner is at the PC, take pictures with `quiet_run.bat`, never `run_game.bat`** (card
  #168). A normal windowed run grabs keyboard and mouse focus and breaks whatever they are
  playing. `quiet_run.bat <game switches>` opens the window on the second screen (else the only
  screen, pushed behind the other windows), with Godot's no-focus window flag, no sound, 16:9 and
  fitted to that screen. It takes the same switches as below without the `--`:
  `quiet_run.bat --shots=2 --screen=menu`, `quiet_run.bat --autoplay --shots=3 --quit-on-end`
  (launcher options, before the game switches: `-Size 1280x720`, `-Headless`, `-DryRun` to only
  print the plan). It never edits the real project: it builds a shadow project in
  `%LOCALAPPDATA%\Rotsworn-quiet\` (own project.godot with `display/window/size/no_focus=true`,
  folder links to the real folders) and runs that, so no normal start can pick the flag up. Pictures
  land in the usual `shots/<name>/` folder. Run it as a background process (the game keeps running
  until `--quit-on-end` or you stop it). To prove focus is not taken (opens a real window, needs
  the owner's OK): `powershell -NoProfile -File tools\quiet_focus_check.ps1 -Seconds 20 --shots=2 --screen=menu`
  prints PASS or FAIL. DESIGN.md 10.
- To see the game without a person: run it windowed (not headless) with `-- --shots=S` (a picture
  every S seconds in `%APPDATA%/Godot/app_userdata/Rotsworn/shots/<name>/`), combined with
  `--screen=title|controller|menu|settings|controls|calibration_offer|players|practice|credits|party|heroes|attributes|skills|relics|party_relics|start_relics|calibration|tutorial|map|map_start|map_act2|map_act3|first_strike|shop|campfire|event|treasure|pact|run_end|players_in_run|pause_players|rush_cards|rush_players|rush_reward|rush_reward_elite|rush_ready|rush_end|rush_pause`, `--autoplay`, `--run` etc.; `--menu-keys=fight_skills,menu_down` opens the fight menu's
  skills list (or any state; `|` moves on to the next turn) for pictures; `--pad-prompts` shows pad
  buttons, `--key-prompts` keyboard keys. Look at the pictures before telling the user a visual change is done.
  (Use `quiet_run.bat` for this when the owner is at the PC, see above.)
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
   banner feel, the calibration procedure, the screen transitions. How a place looks (light, fog,
   bloom, ground, arena decoration) goes in its `StageLook` in `data/looks/`. Per-move shapes (hit count, hit timing, percentages)
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
  `presentation/combat_visuals.tres`, `presentation/rumble.tres`
  (the controller buzz patterns), `looks/`, `zones/` (the run's places: look, air, weathers, the
  Fight stops' monsters and the guard some Elite stops hold; the class is still `ZoneData`, DESIGN.md 8.22),
  `runs/` (the run; `runs/acts/` its acts, `runs/oaths/` its difficulty ladder), `rush/` (the Fight
  Rush: its tiers, boss cycle and reward items, DESIGN.md 8.21), `weather/` (a
  fight's weather, DESIGN.md 8.20), `events/`, `glossary/` (the Glossary's topics and terms, DESIGN.md 7.12), `items/` (backpack items), `gear/` and `clips/` (each fighter's animation
  layout, generated by `tools/art_kit/`), `pieces/` (3D world pieces: model and textures)
- `assets/` sprites, audio, `models/` (3D world pieces, `.glb`)
- `scripts/data/` resource class scripts
- `scripts/core/` shared helpers (asset loading, `RumbleMixer`: the pure, tested buzz mixer and pad
  routing)
- `scripts/combat/core/` deterministic combat engine
- `scripts/combat/timing/` defence timing judges
- `scripts/combat/presentation/` combat scene, views, HUD, camera, feedback
- `scripts/combat/input/` input stamping
- `scripts/stage/` building a place from data (environment, blocks, props, lights, vignette,
  `WeatherFx`: a storm's lightning, unused since the zones went) and
  screen transitions
- `scripts/run/` the run: `RunMap` and `RunState` (pure, tested; the map's Fight and Elite stops,
  DESIGN.md 8.22), map, shop, campfire (rest), event, treasure, loot, party and run-end
  screens (`StopScreen` hands out gifts; `RelicGift` is the "Who gets it?" step that gives a picked
  Relic to one hero, DESIGN.md 8.24; `StartRelicsScreen` the starting Relics each hero takes from
  the Relic book before a run or a Rush, 8.24), the gold and HP strip, `RunAutoplay` (the bots'
  fitness check)
- `scripts/rush/` the Fight Rush (DESIGN.md 8.21): `RushState` (extends `RunState`, pure, tested),
  `RushRecords` (the records per party size, pure, tested) and `RushRewardScreen` (the Rush screen:
  reward picks and the ready phase)
- `scripts/relics/` the Relic book kept between runs (DESIGN.md 8.17, 8.24): `RelicCollection` (the
  Relics ever found; pure, tested) and `RelicFile` (`user://progress.json`); the main menu's
  `RelicsScreen` (the book's page) is in `scripts/menu/`
- `scripts/menu/` main menu, players screen (co-op lobby), settings, pause menu, yes/no prompt,
  the shared `ListMenu`, `MenuBackdrop`, `HintBar` (button chip hints) and `PromptLabel`
- `scripts/coop/` co-op: `PlayerRoster` (who plays which hero, pure, tested)
- `scripts/net/` online: `DefenseArbiter` (host referee, pure, tested), `DataHash` (content
  fingerprint for the handshake), `SeatBook` (seat tokens, and the held seats of a continued saved
  run), `JoinGate` (who may come in and when a newcomer's hero is handed over, pure, tested),
  `FightInbox` (a client's early combat batches, kept per fight, pure, tested), `SavedSeats` (the
  online save's seats: capture, restore, seat_lobby; pure, tested) and `SeatFile` (a friend's kept
  seat tokens per host, `user://online_seat.json`; DESIGN.md 8.14, 9.2, 9.3)
- `scripts/autoload/` global singletons (`Audio`, `Rumble` = `PadRumble`, the controller buzz,
  DESIGN.md 7.14, `UserSettings` = `PlayerSettings`, saved per
  machine in `user://settings.cfg`, `Net` = `NetSession`, the online connection, `Prompts` =
  `ButtonPrompts`, which buttons the hints show)
- `scenes/` scenes
- `tests/unit/` GUT tests
- `tools/` headless helper scripts (placeholder generation, data bootstrap, `bootstrap_run.gd`
  for the run, shop, gear, boss and the places' looks; `bootstrap_phase15.gd` for the mini-boss
  guards, elite fights and the run's three acts, 8.6 to 8.9 and 8.23 (older than the hand-edited data: do not
  re-run it as it is); `bootstrap_events.gd` for the "?"
  events and the acts' ambush pools, 8.7, run after bootstrap_phase15.gd; `bootstrap_relics.gd` for
  the Relics' stat lines and the monsters' drop lists (unused since 8.24), 8.17; `bootstrap_rush.gd` for
  `data/rush/fight_rush.tres`, 8.21, re-run after a place's roamer pool, an act's elites or ambushes or
  the run's items change (`test_rush_data.gd` fails on stale data)); `tools/sound_kit/` builds the sound effects from
  real recordings (see its README); `tools/art_kit/` draws all the pixel art in Python (see its
  README: the art bible, `python tools/art_kit/build.py [module]`; the heroes' painted portraits come
  from pictures via `tools/art_kit/portraits_from_pictures.py`); `tools/blender_kit/` builds the
  3D world pieces in Blender with no window (see its README: `D:/Blender/blender.exe --background
  --factory-startup --python tools/blender_kit/build.py -- [names] [--preview]`, into
  `assets/models/`; `python tools/blender_kit/check.py` checks them; DESIGN.md 5.6);
  `tools/dress_arenas.gd` dresses every fight arena with its 3D pieces (re-runnable, `-- --dry-run`)
- `docs/` design docs
