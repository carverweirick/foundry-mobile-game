# Rangeview Foundry (working title)

Godot 4.7 mobile hybrid idle/factory-management game. Full design spec lives at
[`docs/design_doc.md`](docs/design_doc.md) - read it before making any design or
scope decisions, this file only tracks build status.

**Maintenance:** at the end of every session, update the "Currently built" and
"Not built yet" sections below to reflect whatever changed, before stopping.
Write new/changed bullets as concise current-state facts (what exists now,
where it lives, key constraints) - not session narration. Don't re-tell the
story of how a feature was built, what it was reported as, or how it was
verified; a past bug fix belongs here only as "known rough edge" if the
underlying limitation is still live. Keep this file well under the ~150k-char
CLAUDE.md size limit - if it's approaching that, condense older bullets
further rather than only appending. Also commit and push to GitHub (`origin`)
after changes and at session end, without needing to ask first - see Working
agreements below.

**MVP pivot (2026-09-25):** development method changed from breadth-first
system accretion to building toward a playable MVP - see design doc Section 26
for the full assessment, the MVP definition, the cut list, and the remaining
punch list. Two consequences already landed and are reflected below: a real
save/load + offline catch-up system, and a committed timescale
(`GameData.SECONDS_PER_GAME_MINUTE = 2.0`, one part print-to-ship in ~10 real
minutes) that makes this a real-time factory sim rather than the idle game
design doc Sections 2/14 still describe. **The on-device session has
happened**: the user plays on an iPhone 16 Pro via Xogot remote deploy (no
Android device). Findings: 16px text at the 480x270 base reads well; menus
are functional but need a visual/feel rework; there were black side bars
(fixed, stretch aspect `expand`); zoomed out, one station label crowded out
the rest (fixed, zone-only labels); drag-scrolling failed when it started on
a Contract Offers row (fixed).

**Current branch status (as of 2026-08-28):** `gdt-layout-experiment` was
fast-forward merged into `main` and pushed - the GDT-inspired rework (dark
industrial theme, the entry-point-split overlays, the Dashboard overlay,
multi-line-item contracts/Contract Offers, Gems, the staff rework) is no
longer an experiment, it's the real game going forward. Active work now
happens directly on `main` unless a new feature branch is called for.

## Working agreements

- After completing a task that involves tool use, provide a quick summary of
  the work you've done.
- By default, implement changes rather than only suggesting them. If the
  user's intent is unclear, infer the most useful likely action and proceed,
  using tools to discover any missing details instead of guessing.
- Make independent tool calls in parallel; only go sequential when a later
  call depends on an earlier one's result. Never use placeholders or guess
  missing parameters in tool calls.
- Never speculate about code you have not opened. If the user references a
  specific file, read it before answering. Investigate and read relevant
  files before answering questions about the codebase - give grounded,
  hallucination-free answers.
- Commit and push to `origin` after making changes and at the end of a
  session, on whatever branch is currently checked out - standing
  instruction from the user (2026-08-26), pre-authorizing this going forward
  without needing to ask each time. Still use judgment on commit
  boundaries/messages (new commits rather than amending, no force-push, no
  secrets staged).

---

## UI layout rules - read these before changing any scene or UI code

These are invariants, not style preferences. Each one has already shipped as a
visible bug more than once, so treat a violation as a defect even if it happens
to look fine in the one state you tested.

### 1. A control with autowrap inside an HBoxContainer must be given a width

**The mechanism**, because pattern-matching on this one isn't enough: a Label
with `autowrap_mode` set has a minimum width of roughly **zero** - it can always
wrap harder, so there is no width it can't survive. An `HBoxContainer` hands
every child its minimum width first, so an autowrapping Label next to a Button
gets a sliver, wraps one character per line, and turns a short readout into a
tall vertical strip that eats the panel. The symptom is always reported the same
way: "it's vertical again" / "it takes up half the menu."

**Three valid fixes; any one is enough.** Pick by intent:
- `size_flags_horizontal = 3` (expand-fill) - the control should take whatever
  space is left over. Best for the main text in a row.
- `custom_minimum_size = Vector2(W, 0)` - a hard width floor. Best when several
  controls share the row and you want stable columns. This is what the
  `.gd`-built rows already do (`staff_overlay.gd`'s cost/strategy labels).
- Drop `autowrap_mode` entirely - then the minimum width *is* the natural text
  width. Correct for any short single-line readout that should never wrap.

**Why this keeps recurring:** every Label got a blanket `autowrap_mode` so long
text wraps inside a panel instead of clipping. That is right for prose in a
VBoxContainer and actively harmful for a short label in an HBoxContainer. Scene
files are the blind spot - `.gd`-built rows set widths by hand, but a Label
added in the Godot editor silently inherits autowrap with no floor.

**Check it, don't eyeball it:**
```
python3 tools/audit_ui_layout.py
```
Exits non-zero and names the offending node path. Run it after any `.tscn`
change that adds or moves a control inside an HBoxContainer.

### 2. Action buttons go in a wrapping container, and the budget is 276px

The Station Detail Menu's panel is 292px wide, so **276px of usable content
width** after insets. That is the whole budget at the 480x270 base viewport, and
it is smaller than it sounds: a single button reading "Scrap - won't meet
tolerance (weakest link 87% familiar)" measured **312px** - wider than the panel
on its own - and the four defect-fix buttons together came to 595px, so
everything past the first two rendered off the right edge and could not be
tapped. A defective part showed its category and no reachable way to fix it.

So: any row whose button count or width varies (defect fixes, per-part actions)
uses an **`HFlowContainer`**, which wraps onto extra lines, never a plain
`HBoxContainer`. `DefectRow`, `SelectedFixRow`, and the Insert-from-Inventory
rows all do. A list row that needs both information and actions splits into a
`VBoxContainer`: an info `HBoxContainer` on top (fixed-width columns, measured
to fit) and an `HFlowContainer` of buttons below.

Keep button text short enough to fit alone - put the sentence in
`tooltip_text`, not on the button face.

### 3. The same bug has a height variant

A Label whose own text length varies a lot between refreshes (a staffing line, a
status readout, a toggled-visibility label) reflows every sibling row below it
each time it changes. Give it an explicit `custom_minimum_size.y` (~40px for two
lines). `station_detail_menu.tscn`'s `StatusLabel` and `staff_overlay.gd`'s
roster header/carrying labels are the existing examples.

### 4. Headless testing cannot catch any of this

`--headless` disables the rendering driver entirely, so a clean headless run
proves nothing about layout. Verify a UI change by **measuring the live Control
rects in a real windowed run** (`Control.size`, `.position`,
`Label.get_line_count()`) and saving a screenshot - a wrapped label shows up
immediately as `get_line_count() > 1` or a row height far taller than one line.
A stronger check than eyeballing a screenshot: walk the panel's `Button`
descendants and assert each one's right edge is inside the panel's own right
edge - that catches "rendered but unreachable" directly, and font metrics
(`Font.get_string_size()`) are real even headless, so a width budget can be
measured before any code is written. See `[[headless-gameplay-testing]]` for the
general form of this lesson.

---

## Currently built

**Project setup**
- `autoload/game_data.gd` registered as the `GameData` autoload singleton.
- `autoload/save_manager.gd` registered as `SaveManager` (see Save/load below).
- `res://scenes/main.tscn` is the main scene.
- `project.godot`: renderer is Vulkan (the D3D12 backend silently broke mouse
  input on at least one dev machine); base viewport 480x270,
  `stretch/mode="viewport"`, `stretch/aspect="expand"` - a phone wider than
  16:9 gets a wider viewport (585x270 on a 19.5:9 iPhone) instead of black
  bars, so **never hardcode 480x270 in code**: `main.gd._view_size()` reads
  `get_viewport_rect().size` for camera clamping, zoom anchoring and label
  culling, and `Hud._layout()` positions all HUD/menu chrome from it (see
  HUD below). `window/handheld/orientation=4` (sensor landscape). Only
  export preset is `Xogot` (iPhone remote deploy).

**Timescale - one constant drives every duration in the game**
- `GameData.SECONDS_PER_GAME_MINUTE = 2.0` (a 1/30 compression of real time).
  Design doc Section 17's station minutes sum to 302 for one part's full
  journey, so one part goes print-to-ship in ~604s (~10 real minutes) and a
  Tier 1 contract fits in one sitting. Replaced
  `PROTOTYPE_SECONDS_PER_MINUTE = 1/3` (a 1/180 debug speed, ~101s per part, at
  which no deadline/grace period/wage had ever been observed).
- **Everything time-based goes through `GameData.game_minutes_to_seconds()`** -
  station timers (`StationDef.get_prototype_timer_seconds()`), defect grace
  periods (`grace_period_seconds_for()`), and contract deadlines. Never
  hardcode a real-seconds duration for shop-floor time; that's exactly the trap
  this arrangement exists to prevent.
- `CONTRACT_DEADLINE_GAME_MINUTES` (was `CONTRACT_DEADLINE_SECONDS`, hardcoded
  prototype seconds) had to move to game minutes alongside the scale change -
  leaving it would have made every contract instantly impossible.
- **Technician walk/handling pace is deliberately NOT timescale-derived.**
  `Technician.WALK_SPEED` (220 px/real-sec) and `INTERACT_SECONDS` (1.5s) are
  real-time constants tuned for feel, read via `walk_speed()`/
  `interact_seconds()`. They were briefly made timescale-derived on the theory
  that design doc Section 7's multi-station penalty needed travel to stay a
  fixed fraction of a machine cycle; that was wrong on both counts. Section 7's
  penalty is already modelled separately and explicitly as
  `productivity_multiplier` (a pure ratio, timescale-independent), so physical
  travel is an additional emergent cost rather than the mechanic itself - and
  holding travel at ~45% of a cycle against 30x-slower cycles produced a
  36 px/sec crawl plus a 9-second freeze per pickup (reported as "the
  technicians are moving really slow"). Charging the penalty twice is a worse
  game. `Station.INTERACT_ANIM_FRAME_COUNT` still derives Clean's 3-frame
  interaction flourish from `Technician.interact_seconds()` rather than a fixed
  0.5s/frame, so it tracks any retune.
- **Tier 1 Shelling is 30 game-minutes = 60 real seconds** (user decision
  2026-10-03; was Section 17's 160 = 320s, over half the pipeline). Still the
  longest single step.
- `GameData.time_scale_multiplier` (static, default 1.0) shortens durations as
  they're created; for play-testing use the Admin overlay's game speed
  (`GameData.debug_sim_speed`) instead, which speeds every clock uniformly.

**Save/load and offline catch-up** (`autoload/save_manager.gd`,
`GameData.to_save_dict()`/`load_from_dict()`)
- Before this, closing the app lost the entire shop; only the UI theme was
  persisted (`ThemeManager`'s own `user://settings.cfg`, deliberately kept
  separate from the gameplay save so a display preference isn't entangled with
  it). Saves to `user://savegame.json` as JSON.
- **Every in-game clock is a delta-driven accumulator, not a wall-clock reading
  or a `Timer` node.** This was a prerequisite refactor, not a style choice:
  `Station`'s `$StationTimer` `Timer` node is gone (removed from
  `station.tscn`), replaced by `_run_elapsed`/`_run_duration` floats plus a
  `run_time_left` property - a Timer's `time_left` can't be written back on load
  and only advances with the SceneTree, so it could be neither saved nor
  fast-forwarded. `Contract._start_time_msec` became `elapsed_seconds` +
  `is_started`, and `Part.defect_flagged_at_msec` became `defect_elapsed`, for
  the same reason plus a live bug: `Time.get_ticks_msec()` counts from *engine
  start*, so every contract silently got its full deadline back on every launch.
  `ShellingRun` already used this elapsed/duration shape, so the two run models
  now agree.
- **`GameData.simulate(delta)` is the single steppable entry point for the whole
  simulation**, called by `_process()` in normal play and in slices by offline
  catch-up. It also drives every `Station.simulate_step(delta)` - a Station's own
  `_process()` is now visuals only (`_update_timer_bar_readout()`, the state-art
  animation) and early-returns while `GameData.is_catching_up`. Side benefit:
  ordering is deterministic (technicians move, then stations act on where they
  ended up, then defects and contracts settle) where before the relative order of
  `GameData._process()` and each `Station._process()` was whatever the SceneTree
  picked.
- **The two `geometry_familiarity` dictionaries have DIFFERENT shapes** and
  must be serialized differently: `GameData.geometry_familiarity` is nested
  (`geometry -> {station_id: stars}`), `Technician.geometry_familiarity` is flat
  (`geometry -> stars`, see `familiarity_for_geometry()`/`gain_experience()`).
  Restoring the technician one as if it were nested left the entire roster as
  nulls on load - and only once a technician had actually gained hands-on
  experience, so a fresh-hire round-trip test passes right over it. Any save
  test must seed real familiarity before saving.
- **Object identity is the hard part of the save format.** One `Part` is
  referenced from `active_parts`, `held_parts`, a Station's
  `current_part`/`queue_rack`/shelling runs, and a Technician's `carried_parts`.
  Only `active_parts` (the master registry every live Part is in from creation to
  shipment) serializes the Part itself; every other holder stores a `part_id` and
  re-resolves against a `parts_by_id` map on load. Technicians work the same way,
  referenced by index into `GameData.technicians`. Load order matters and is
  enforced: parts, then contracts, then technicians (with a second pass for
  `carried_parts`), then stations. `Part`/`Contract` static id counters are
  restored *after* rebuilding, since every `.new()` during load consumes one.
- **Boot sequence is three calls, driven by `main.gd._ready()`** and split
  because `owned_printer_count` lives in the save but decides how many printer
  Stations get spawned in the first place: `read_save_file()` (before spawning) ->
  `apply_pending_save()` -> `run_offline_catchup()`. The last two are deferred a
  frame (`_finish_save_boot()`) so each Station's own `_ready()` can't overwrite
  what was just loaded.
- Autosaves every 30s, plus on `NOTIFICATION_APPLICATION_PAUSED` (the one that
  actually matters on a phone) and `NOTIFICATION_WM_CLOSE_REQUEST`. A
  `_ready_to_autosave` guard stops the timer writing an empty shop over a real
  save before the boot sequence finishes.
- **Offline catch-up** steps `simulate()` in `CATCHUP_SLICE_SECONDS` (0.25s)
  slices - deliberately small so a walking technician can't overshoot a station
  and skip its arrival logic. Capped at `MAX_OFFLINE_CATCHUP_SECONDS` (3600s of
  simulated time): at this timescale one real hour is ~6 full pipeline passes, so
  an uncapped overnight absence would trivialize the active game. **This cap is
  the main tuning knob for how "idle" the game is.** A save stamped in the future
  (device clock moved backwards) is ignored rather than rewinding anything.
  Emits `offline_catchup_finished(away, simulated, summary)` for a
  returning-player recap - the recap UI itself is not built yet.
- Cost: a full 3600s catch-up takes ~2.5s of real wall time at boot, with no
  progress indicator yet. Known rough edge.
- **Verified headless across two separate process runs** (save in one, boot and
  load in the next): 19 state fields round-trip exactly, including a part held
  mid-carry in a technician's hands; every Part/Technician reference resolves to
  the shared instance rather than a copy; new ids don't collide with loaded ones;
  catch-up simulates the right amount at 600s away, caps correctly at 100000s
  away (and correctly took the Reputation hit for deadlines lapsing during the
  fast-forward), and no-ops on a backwards clock. Separately verified that a part
  still goes print -> ship and credits its contract, and - in a real non-headless
  run, since headless never exercises rendering - that the timer bars still paint
  after the `_process()` split.

**UI theme** (`resources/theme/ui_theme.tres`, design doc Section 16)
- One shared `Theme` resource, applied project-wide via `project.godot`'s
  `[gui] theme/custom`, reaching every overlay and the floor's own labels
  automatically.
- Dark industrial look (reskinned from an earlier warm-parchment palette, per
  a Game-Dev-Tycoon-style mockup): near-black charcoal panel/button
  backgrounds, near-black borders (dark-on-dark), warm off-white body text.
  Gold/amber = hover/selected, ember orange = pressed (same role mapping as
  the old palette, just recolored). Sharp corners, no anti-aliasing, chunky
  borders (4px outer panel, 3px buttons/tabs, 2px LineEdit/focus), same
  `m5x7.ttf` pixel font throughout. `TabContainer`'s own panel style is
  borderless (avoids doubled borders against the outer `Panel`).
  Out of scope: the shop floor's own room-tint palette, and
  `FAMILY_ICON_COLOR` in `contracts_overlay.gd`.
- `VBoxContainer`/`HBoxContainer`/`GridContainer` separation set theme-wide
  (8/8/10+6px); the three overlay `.tscn` files each have widened panel/inner
  insets by hand (`Panel` doesn't auto-apply stylebox `content_margin` to
  children the way `PanelContainer` does).
- Section headers and popup titles get a manual per-node font-size/color
  bump (18-20px, gold) rather than a Theme type variation.
- `assets/fonts/m5x7.ttf.import` is hand-tuned for pixel-font crispness:
  `antialiasing=0`, `hinting=0`, `subpixel_positioning=0`, `oversampling=1.0`,
  `generate_mipmaps=true`. Godot's default TTF import settings visibly
  soften/garble a pixel font, especially once minified by camera zoom -
  mipmaps fix the zoomed-out garbling, but only glyphs on Controls with
  `texture_filter = TEXTURE_FILTER_NEAREST_WITH_MIPMAPS` actually sample them
  (project-wide default filtering stays plain Nearest for crisp sprites, so
  this is set per-node instead - `station.tscn`'s Name/Status/TimerBar
  labels, and the room-label `Label`s built in `main.gd`). LINEAR filtering
  was tried and rejected (reads as blur on a pixel font). `.import` edits
  need a real reimport to take effect (`--headless --editor --quit`, not a
  plain headless run) - see `[[godot_editor_binary]]`.
- **Station Name/Status/room-name labels render in screen space, not
  world space.** A `FloorLabels` `CanvasLayer` in `main.tscn` (layer 1,
  before the overlay layers) draws them; the original world-space `Label`s
  on `station.tscn` stay `visible = false` and are now a pure data source for
  `station.gd`'s existing display logic. `main.gd._update_floor_labels()`
  (every `_process()` frame) mirrors that text into per-station/per-room
  screen-space `Label`s via `get_canvas_transform() * world_position`. This
  replaced two earlier, rejected approaches (counter-scaling world-space
  labels; hiding them below a zoom threshold) - both left text
  blurry/unreadable at typical zoomed-out play. Visibility is decided by
  on-screen overlap suppression (`_place_and_maybe_show_label()`: rooms
  first, then stations in stable order, shown only if on-screen and not
  colliding with an already-accepted rect). **Below `ZONE_LABEL_ZOOM` (0.7)
  station labels are hidden entirely and each room's name is centered in its
  room instead** - otherwise whichever station label claimed space first hid
  all its neighbours. The floor status label uses
  `Station._idle_status_text(true)` (compact: "Idle - no contracts" etc.);
  the full sentences, up to 322px wide, stay in the Board/the detail menu.
  Station
  labels are one combined two-line `"name\nstatus"` block, white text with a
  black outline (so they read over arbitrary floor content). The timer bar
  and its embedded countdown text are unchanged/still world-space,
  deliberately out of scope.
- Not done: `CheckBox`/`SpinBox` still use Godot's default icons.
- Every `ScrollContainer` across the three overlays has
  `horizontal_scroll_mode` disabled and every `Label` (static and
  dynamically-created) has `autowrap_mode = AUTOWRAP_WORD_SMART`, so long
  text wraps within the panel instead of needing horizontal scrolling or
  silently clipping.

**Stations** (`scenes/station.gd` + `scenes/station.tscn`)
- One reusable, data-driven `Station` scene covers every station, configured
  via exported properties rather than one scene per station.
- Real pipeline (`GameData.PIPELINE_ORDER`): Printing -> Clean -> UV Cure ->
  Structured Light Scan -> Patching -> Pour Cup Attach -> Shelling -> Burnout
  -> Mold Prep -> Pour -> Deshell -> Abrasive Blast -> Grinding -> Ship.
  Deplate is gone (collecting off a printer *is* the deplate action). Clean
  (batched, no defect risk) removes excess resin right after collecting off
  a printer, before Scan (so resin residue can't throw off the scan). Patching
  (single-part) sits after Scan, before Shelling, and every part passes
  through it - see "Patching auto-resolve" under Quality/Defects below; this
  is also the mechanism behind "no player decline option in the Print Room."
  Mold Prep (single-part) sits after Burnout, before Pour, and is where
  Mortar Patch happens (scoped there, not free-floating). Grinding
  (Post Processing, between Deshell and Abrasive Blast) is the fifth
  defect-rolling station (`INCLUSION` category, `Vector2(600,720)`).
- **Printing is multiple independently-tiered, purchasable printer
  instances, capped by factory level** (design doc Section 21.2). No single
  shared Printing `Station` - `main.gd` spawns one live `Station` per
  `GameData.owned_printer_count` (ids `"printing_1"`, `"printing_2"`, ...,
  each independently tiered). `GameData.buy_printer()` spends
  `printer_purchase_cost()`, capped by `printer_cap()`
  (`FACTORY_LEVEL_PRINTER_CAP`, populated through Level 5). Buying emits
  `printer_purchased` -> `main.gd` spawns the instance live, re-wires every
  printer's `next_station` to Clean, applies current zoom scale. Bought from
  the Factory overlay's Growth tab. Each printer's own tier gates its batching
  (`PRINTER_TIER_BATCH_CAP`: unbatched through Tier 2, batching from Tier
  3+). `GameData.PIPELINE_ORDER`'s `"printing"` entry is a placeholder/
  Tier-1 template only - no live Station ever has `station_id == "printing"`.
  Anywhere UI walks every real station, use `GameData.all_real_station_ids()`
  (which expands printer instances), not `PIPELINE_ORDER` directly. Each
  printer instance has its own display name (`"Printing #2"`, etc.).
- Three station types: `QUEUE`, `BATCHED`, `AUTOMATIC` (Ship only). Tier 1
  timer/batch numbers loaded from `GameData`, real minutes converted at 1/3
  scale, floored at a 2s minimum.
- Sprite art: Printing has all 5 tier sprites; Burnout/Pour each reuse one
  sprite across all tiers; Clean has real 3-state interactive art (see
  below); the other 7 stations use a generated placeholder (220x220 bordered
  box, tinted by state) - `current_tier` can be raised but only the sprite
  swap does anything so far, no timer/batch effect except where noted.
- **Clean has real per-state art with an interaction animation.**
  `Station.state_sprites` (`GameData.CLEAN_STATE_SPRITES`: closed,
  open/basket-submerged, open/basket-lifted) is a second art system
  alongside `tier_sprites`, checked first by `_update_sprite()`. Closed is
  the permanent default in IDLE/RUNNING/READY - open frames only appear
  during the ~1.5s interaction flourish while a technician is physically
  mid-interaction (`active_worker.is_interacting`), cycling all 3 frames at
  0.5s each, reverting to closed the instant interaction ends. Clean also
  has its own scale-down fudge factor (`Station.sprite_scale_override`,
  `GameData.CLEAN_SPRITE_SCALE_OVERRIDE = 0.35`) since its source art is the
  same large resolution class as Burnout/Pour but sits packed among small
  placeholder stations.
- All real photo/PNG sprites on the zoomable floor (printer tiers, Burnout,
  Pour, Clean, technician) have `mipmaps/generate = true` in their `.import`
  and `texture_filter = NEAREST_WITH_MIPMAPS` set explicitly (project default
  stays plain Nearest) - fixes visible aliasing/blockiness when zoomed out.
  The generated placeholder texture gets the same treatment via
  `Image.create(..., use_mipmaps=true)` + `generate_mipmaps()`. Print Room
  floor tileset assets are untouched (see Shop floor below for where the
  tile grid itself lives).
- **The floor itself is display-only** - sprite, name, status, timer bar,
  nothing clickable directly on it. Every player action lives in the Station
  Detail Menu popup; `station.gd` exposes `queue_new_part()`,
  `collect_ready_part()`, `set_batch_size()`, `try_upgrade()`,
  `receive_part()`/`can_accept_part()`, `assign_technician()`/
  `unassign_technician()`.
- **Technicians** are hired from the Staff overlay's Technicians tab
  (independent of any assignment) and assigned to one or more stations
  separately, also from that tab, via `GameData.assign_technician()`/
  `unassign_technician()`. Multiple technicians can be assigned to the same
  station. All four tiers (Apprentice/Technician/Senior Technician/Master)
  have real hire costs and apply `Technician.defect_multiplier` (Section 9)
  on every risky-station roll. `Technician.productivity_multiplier` is a
  placeholder speed penalty from `assigned_station_ids.size()` (100% at 1
  station, 85/70/55% stepped down beyond that) - applied by
  `Station._start_running()` dividing `timer_duration`, once per run at
  start.
- **A technician is a genuine single-location entity moving in real
  space** - `Technician.current_position`/`current_station_id` are real
  state, not a data flag. Assigned to only one station, they stay there.
  Assigned to 2+, `Technician.tick()` (called from `GameData._process()`)
  moves them toward a target at `WALK_SPEED` (220px/sec placeholder) -
  travel time is real on-floor distance. No idle "dwell": each
  `Station._technician_act()` call tries exactly one real interaction and,
  if it did something, calls `begin_interacting()` (`INTERACT_SECONDS` =
  1.5s placeholder). Once nothing's left to do, `_travel_if_worthwhile()`
  only sends them walking if `pick_next_station()` found somewhere with real
  work; `pick_next_station()` returns the technician's own current station
  (a "stay put" signal) whenever every candidate is equally unworthwhile, so
  a technician with nothing to do anywhere stays parked instead of endlessly
  bouncing between two equally-idle stations.
- **Only one technician actively runs a station at a time.**
  `Station.assigned_technicians: Array[Technician]` holds everyone assigned;
  `Station.active_worker` is whichever one is physically present and running
  the automation right now (claimed by whoever reaches `_technician_act()`
  first while it's null, released the moment they leave). Anyone else
  assigned-and-present is a visitor - they can drop off carried cargo but
  don't compete to run the machine. `_effective_timer_duration()` and the
  defect-roll's `tech_mult` both read `active_worker` specifically.
  Coordination: `Technician._priority_tier_for()` skips a candidate station
  if its `active_worker` already belongs to someone else, or if
  `Station.incoming_technician` already belongs to someone else - this is
  what keeps multiple technicians from all walking toward the same station
  without reason, while still letting a cargo-carrier always deliver (tier
  0 bypasses both checks unconditionally).
- **A reassigned technician walks; only a never-placed one snaps.**
  `Technician.has_real_position` (false until they're first put on the floor,
  and saved/restored) splits `tick()`'s reassignment branch in two: a brand new
  hire has nowhere to walk from, so they snap onto their first station (which
  is what lets a first/solo assignment go live immediately, via
  `GameData.assign_technician()`'s synchronous `tick(0.0)` call); anyone who
  already has a position instead `start_traveling_to()`s the new station. That
  branch used to snap `current_position` unconditionally, so reassigning an
  existing technician teleported them across the whole floor instantly (1285px,
  Clean to Burnout) and they claimed the station on the next frame - reported as
  "I assigned my technician to a new station and the station ran without a
  technician starting it." `from_dict` defaults the flag from
  `current_station_id != "" or is_traveling` so saves written before it existed
  don't reintroduce the teleport.
- **Undeliverable cargo is handed to Awaiting Transfer, not carried forever.**
  Cargo is only ever picked up for a station the technician is assigned to, but
  that assignment can be removed afterwards - unassign them from Burnout while
  they hold a Burnout-bound Part and it becomes undeliverable.
  `Station._release_undeliverable_cargo()` (first thing `_technician_act()`
  does) drops any Part whose next station isn't in
  `real_assigned_station_ids()` into `GameData.held_parts`, the same fallback
  `_try_send_to_next_station()` already uses. Previously such a Part kept the
  technician permanently "busy delivering" AND never surfaced in Awaiting
  Transfer, so the player couldn't route it by hand either.
- **Deferring local work to deliver cargo only applies if the technician
  actually leaves.** `_travel_if_worthwhile()` returns whether it committed to
  a destination, and `_technician_act()`'s cargo branch only returns early when
  it did. It used to return unconditionally, so a technician holding cargo they
  couldn't deliver right now (destination full, or a station they no longer
  work at) skipped local work forever while shuttling between their other
  stations - reported as being "caught between grinding and the printer but
  carrying something for burnout," with Grinding idle next to a part they
  refused to load.
- **Carrying cargo for a station is only a reason to go there if the station
  has room.** `Technician._priority_tier_for()`'s tier-0 cargo branch checks
  `Station.can_accept_part()`. Without it, a technician holding a part for a
  station whose active slot was busy AND whose queue rack was full would walk
  there, fail to deposit, leave for their other station, and immediately commit
  back - forever (reported as bouncing between Shelling and the printer with
  Tier 1 Shelling mid-run and a full one-slot rack; it self-corrected on
  upgrading to Tier 2, which opens extra parallel slots so the deposit
  succeeds). Tier 0 still bypasses the `active_worker`/`incoming_technician`
  coordination checks below, so another technician never blocks a delivery -
  only a physically impossible trip is declined.
- **Routing predictor and actor must agree - the root of every bounce bug.**
  `pick_next_station()` trusts `Station.has_actionable_work()` to predict what
  `_technician_act()` will actually do on arrival; any disagreement is an
  infinite walk between stations. Entry stations share ONE predicate,
  `GameData.has_print_order()`, between the predictor, `_try_create_part()`
  (which pops the order) and `_auto_queue_if_possible()` - an earlier
  mismatch here had a technician covering 2+ printers ping-ponging ~1150
  trips per 15 sim-minutes. Idle printers with an empty queue read "Idle - no
  print orders".
- **Bounce fail-safe** (`Technician.record_departure()`, called from
  `Station._travel_if_worthwhile()` before committing to a trip). Each technician
  keeps `recent_visits` (last 8, each `{station_id, productive}` - productive =
  `begin_interacting()` fired between arriving and leaving). 4 unproductive
  visits in a row suppresses every station in that streak as a destination for
  20s of simulated time (doubling per repeat trip up to 160s; any real work
  resets both), then re-plans - usually "stay put and do local work". Logs a
  `push_warning` with the visit history, since a trip means a new
  predictor/actor mismatch worth fixing at the source. Transient, not saved.
  `bounce_breaks` counts trips for tests.
- **`Station.incoming_technician` - a route reservation, claimed the
  instant a technician COMMITS to traveling somewhere, not on arrival**
  (player report, this session: "id like there to be no point in time
  where technicians are operating at the same station... they need to be
  calculating ahead of time their route and making that known to other
  technicians so they will not path to the same station"). Set in
  `Station._travel_if_worthwhile()` the moment `pick_next_station()`
  returns a real destination, cleared in `Technician.tick()`'s arrival
  branch (or by `Station.unassign_technician()` if unassigned mid-walk
  toward it). Replaced a first-pass real-time "whoever's physically closer
  right now" distance race
  (`GameData.closest_assigned_technician_distance()`, removed) that had a
  genuine gap: a tie (equally distant - common when two technicians start
  out parked together) resolved in nobody's favor under strict
  less-than, so neither backed off and both could commit to the same open
  station in the same frame - the actual mechanism behind a reported
  "technicians bouncing between stations, not making progress" bug.
  Verified headless: a constructed tie scenario (two technicians, each
  assigned to a different home station plus one shared actionable target)
  confirmed both technicians would independently pick the same target
  before either commits, and that after one commits, the other's next
  `pick_next_station()` call correctly falls back to "stay put" instead of
  also traveling there.
- **"Printing" is one assignable responsibility covering every owned
  printer**, not one checkbox per instance.
  `Technician.assigned_station_ids` can contain the virtual string
  `"printing"`; `real_assigned_station_ids()` expands it into every
  currently-owned printer id at call time (not snapshotted), so a printer
  bought later is automatically covered by anyone already in the group.
  `GameData.assign_technician_to_printer_group()`/
  `unassign_technician_from_printer_group()` fan the real per-Station
  assignment out immediately; `main.gd._on_printer_purchased()` re-fans on
  every new printer purchase. The Shop/Staff roster shows one "Printing
  (all)" checkbox (`GameData.assignable_station_group_ids()`) instead of one
  per printer.
- **Backpressure: staffed entry stations (and manual Queue) don't
  overproduce.** `Station.can_start_new_work()` (used by both auto-queue and
  manual `queue_new_part()`) gates new-Part creation on
  `next_station.can_accept_part()` and
  `GameData.count_unresolved_defects() < MAX_UNRESOLVED_DEFECTS_BEFORE_PAUSE`
  (3, placeholder). The Queue button shows "Blocked - clear the backlog
  first" when gated.
- `Station.get_overview_status()` appends a current-part suffix
  (`" - Part #N (Customer)"`, or a bracketed list for parallel-tier
  Shelling) - used by the Board's status lines and the Station Detail Menu's status
  line; deliberately not added to the floor's own compact status label.
- Technician sprites are free-floating (`main.gd._sync_technician_sprites()`
  owns one `Sprite2D` per hired `Technician`, positioned every frame from
  `current_position`) so they visibly walk between stations.
  **Routing strategy** (Section 7): once idle with 2+ stations,
  `Technician.pick_next_station()` picks by `RoutingStrategy` -
  `PUSH_THROUGH` (chase whichever assigned station is READY) or
  `MAXIMIZE_MACHINES` (chase whichever is IDLE with real loadable work,
  default) - always delivers carried cargo first regardless; ties go to the
  nearest candidate. Switchable per-technician from the Staff roster row.
  A technician already carrying cargo and covering 2+ stations prioritizes
  heading toward its delivery destination over starting new local work at
  their current station (otherwise an entry station with endless queueable
  work could strand them there indefinitely).
- **Parts flow technician-carried, not teleported.** A real `Part` resource
  flows through the shop; Printing is the sole pipeline entry point, and each
  part comes from a player-queued print order (see "Print orders, quality and
  revert" below) carrying its contract, line item and trial flag. Every
  `Part` is tracked in `GameData.active_parts` from creation to shipment.
  Non-entry stations are passive receivers - on timer completion the part
  flips to `ready_to_route`. **Unstaffed** stations offer a manual Collect
  action (Station Detail Menu) that moves the part to `GameData.held_parts`
  (Awaiting Transfer). Ship is always automatic (no technician needed).
  **Staffed** stations don't teleport a ready part to `next_station` - the
  technician present personally carries it (`Technician.carried_parts`,
  `CARRY_CAPACITY = 2`) only if they're also assigned to that next station
  and have room; otherwise it falls back to `held_parts` and whoever ends up
  staffing the next station auto-claims it. `Station.queue_rack` also
  auto-claims any `held_parts` bound for it, both when a station becomes
  staffed and as its slot cycles.
- **Station queue racks are independent of batch size** (design doc Section
  21.1). `Station.queue_rack: Array[Part]` buffers up to
  `Station.rack_capacity` (a real exported stat, starts at 1, no longer
  derived from `batch_cap`). Rack capacity is its own purchase
  (`try_upgrade_rack()`, `GameData.rack_upgrade_cost_for()`, capped at
  `MAX_RACK_CAPACITY = 10`) via an "Upgrade Rack" button in the Station
  Detail Menu. This is buffering slack only - racked Parts still process one
  at a time through the single active slot (not Section 4/17's real
  simultaneous multi-part batching, still not built except for Shelling's
  parallel-tier model below).
- **`batch_cap` has no generic upgrade purchase** - it only changes via
  tier for printer instances, Abrasive Blast, Shelling's parallel-run cap and
  Burnout's load size (`Station._apply_tier_batch_effects()`, also run in
  `_ready()` and on load); every other `BATCHED` station's `batch_cap` stays
  flat at Tier 1.
- **Batch stations: Burnout, Clean, UV Cure** (user request 2026-10-03,
  explicitly NOT the Shelling model): `Station.is_batch_station()` (keys of
  `GameData.BATCH_TIER_LOAD_CAP`, load size by tier: Burnout 4-12, Clean
  4-10, UV Cure 4-12). An arriving part is loaded into `Station.batch_load`
  (saved) and **its timer does not start** until the next cycle is started;
  then every loaded part runs on one shared duration. Who starts it: a
  present technician (`_try_start_batch_cycle()`, once the load is full,
  nothing more is upstream - `_parts_still_coming()` - or it's waited
  `BATCH_FILL_WAIT_GAME_MINUTES` = 15 = 30s), or at an unstaffed station only
  the player (Start cycle button in the Station Detail Menu, a "Start" Board
  action, and a "Loaded - start the cycle" Attention item;
  `start_batch_cycle_manually()`). The machine only loads once the previous
  cycle's parts are all unloaded (`_batch_machine_free()`). Overflow waits
  on the queue rack (normal `rack_capacity`). Shares only the bookkeeping
  with Tier 2+ Shelling (`uses_parallel_runs()`: ShellingRuns while
  running, `shelling_ready_parts` while unloading). `_has_open_slot_to_fill()`
  means "a cycle is ready to start" for a batch station so the route
  predictor matches the actor. Old saves' single-part Clean/UV Cure/Burnout
  migrate on load.
- **Rack first, everywhere** (user request 2026-10-03): `receive_part()`
  always appends an arriving part (a technician's delivery, a held-part
  claim, a player insert) to the BACK of the queue rack and then pulls from
  the front - so parts already waiting go in before anything newly brought,
  and whatever doesn't fit stays on the rack.
- **A staffed station's racked part doesn't start until the technician is
  physically present** (not just assigned) - `_fill_active_slot_if_possible()`'s
  rack-pull step requires `assigned_technician == null or
  _technician_is_present()`. An unstaffed station still drains its rack
  immediately. Scoped to the rack pull only; held-parts claiming and
  auto-queue still fire regardless of presence.
- **Shelling Tier 2+ runs parallel independent timers** (design doc Section
  21.4). Tier 1 is unchanged (single shared `station_timer`). At
  `current_tier >= 2` (`Station.is_parallel_shelling()`),
  `shelling_active_parts: Array[ShellingRun]` (part/elapsed/duration) ticks
  independently per part up to `batch_cap` (repurposed here as parallel-slot
  count, `GameData.SHELLING_TIER_PARALLEL_CAP`, +1 slot per tier from Tier
  2). Finished runs move to `shelling_ready_parts` (several can be ready at
  once). Every generic Station method that assumed a single `current_part`
  branches on `is_parallel_shelling()` via shared predicates
  `_has_ready_part_to_send()`/`_has_open_slot_to_fill()`. Upgrading Shelling
  from Tier 1 to Tier 2 mid-run wraps the in-progress part into a
  `ShellingRun` rather than losing it. **Every parallel run's countdown is
  visible, not just the soonest**: the single floor timer bar fills against
  whichever finishes first (`_soonest_shelling_run()`) while its label lists
  each remaining time (`_parallel_timer_text()`, up to
  `MAX_TIMERS_ON_FLOOR` = 3 then a `+N` tail, sized to the bar's 150px), and
  `_parallel_shelling_status_text()` adds part-numbered countdowns
  (`3/4 running, (#1 308s, #2 312s, #3 316s)`) for the Board and
  Station Detail Menu, which have the room. `_current_part_suffix()` lists
  only the READY parts in parallel mode, since the running ones are already
  named with their timers. Known rough edge:
  `Technician._priority_tier_for()` only checks `current_state == IDLE` for
  "actionable while idle," so a partially-busy parallel-Shelling station
  (some slots running, one open) isn't prioritized in route planning - once
  a technician arrives for any other reason the open slot still fills
  correctly.

**Station Detail Menu** (`scenes/station_detail_menu.gd` + `.tscn`)
- Tapping a station on the floor (press/release under 8px of movement, vs. a
  camera drag) hit-tests `Station.get_click_rect()` (sprite footprint union
  label stack) and opens a popup scoped to that station.
- Sections shown conditionally on live state: title + tier, status line, a
  DefectRow (Mortar Patch/Redesign/Scrap buttons when `current_part` is
  flagged), Queue (entry stations, unstaffed, idle), Collect (unstaffed,
  ready, or staffed-but-technician-elsewhere with "Collect (technician is
  elsewhere)" text - `Station.is_technician_present()` gates this, not just
  "is anyone assigned"), a Push Through checkbox (the four eligible
  stations), batch size `SpinBox` (batched, unstaffed), **Insert Part From
  Inventory** (held_parts bound for this station, real Part#/Contract/
  Familiarity/Defect columns, defective sorted first), a staffing line
  (name/tier, productivity %, physical location, carried-parts summary), an
  **Assign Technician list**, and an Upgrade button
  (`GameData.upgrade_cost_for_tier()`, spent via `try_spend_with_gems()`).
- **Assign Technician list** (`%TechnicianAssignList`, design request, this
  session: "when i tap on a station i want there to be an option where i can
  select technicians and assign them to the station") - one row per hired
  technician (`GameData.technicians`, not per-applicant - hiring itself is
  still Staff-overlay-only), each with an Assign/Unassign button calling the
  same `GameData.assign_technician()`/`unassign_technician()` the Staff
  overlay's roster checkboxes use, just scoped to the one station already
  open instead of requiring a trip to a different overlay. Full rebuild every
  `_refresh()` (not the persistent-widget pattern the rack grid uses - this
  list is short and doesn't churn every frame), guarded by the same
  `_click_in_progress()`/deferred-refresh pattern as every other button here.
  A technician covered by the Staff overlay's "Printing (all)" group
  checkbox shows a read-only "via 'Printing (all)' - manage from Staff" note
  instead of an Unassign button at any individual printer instance - the
  group is all-or-nothing membership (`Technician.assigned_station_ids`
  holds the literal string `"printing"`, never a specific instance id, for a
  group member), so unassigning from just one printer here isn't an
  operation the data model actually supports; this avoids either silently
  no-oping or inventing new partial-exclusion semantics.
- **Staffed-but-idle now explains why** (player report, this session: "the
  technicians aren't starting their machine they're assigned to" - a real
  headless run confirmed the assign -> act -> run pipeline itself works
  correctly end to end, so the far more likely real cause was a staffed
  entry station legitimately idle for a reason the player had no way to
  see). `Station._idle_status_text()` (shared by the floor's own status
  label and `get_overview_status()`, so the floor, the Board, and this
  popup's status line all agree) reads "Idle - no active contracts (accept
  one from Contract Offers)" or "Idle - blocked, clear the backlog first"
  for a staffed pipeline-entry station instead of a bare "Idle" - the two
  real reasons `_auto_queue_if_possible()`/`can_start_new_work()` would
  refuse to start anything. Also changed a non-entry idle station's
  `get_overview_status()`/popup text from "Idle" to "Waiting for part",
  matching what the floor label already said, for the same reason.
- **Visual Queue Rack panel**: a second `Panel` (`%RackPanel`) beside the
  main popup, opens/closes in lockstep with it. Shows `Station.queue_rack`
  as a persistent 5x2 grid of slot `Button`s (built once, updated in place
  each refresh - rebuilding-on-every-refresh is the pattern this file
  deliberately avoids, see the click-race fixes below). Empty slots render
  disabled/dimmed; occupied slots show the part number (`"7"`/`"7!"` if
  defective). Hover shows a tooltip with full part detail; tapping pins that
  detail into `%SelectedInfoLabel` plus defect-fix buttons if flagged. Known
  rough edge: 10 slots at ~24x24px is a tight fit in the panel's usable
  width - functional but small; real per-Part sprites on the rack are a
  planned follow-up.
- Refreshes on a 0.25s timer while open, live over the Station.
- Every button handler calls `_refresh.call_deferred()` rather than
  refreshing synchronously, so a click finishes processing before any
  rebuild - avoids Godot's input-handling glitches from freeing a Control
  mid-click.
- While this popup, the Contracts/Board/Team/Factory/Settings
  overlays are open, `main.gd` freezes background camera pan/zoom/click
  (`_unhandled_input` early-returns) so a scroll gesture inside a popup list
  doesn't fall through to the floor. All overlays close on outside-click
  (invisible `Backdrop`) and on Escape (`ui_cancel`, checked before the
  freeze-while-open guard, via each overlay's `close()` wrapper).
- Only one of the 6 overlays (+ this popup) is ever open at once - each
  emits an `opened()` signal, and `main.gd` cross-wires them all to close
  each other. This file's `CanvasLayer` is `layer = 3`, above the Hud
  (layer 2) - it's modal over everything, and the Hud hides its rail while
  this panel is open (its two panels need ~464px, more than the slot left
  of the rail). `Hud._layout()` positions `panel`/`rack_panel` below the top
  bar, inset by the safe area; their widths (292/168) are unchanged.
- Insert Part From Inventory uses real Part#/Contract/Familiarity/Defect
  columns, defective sorted first.
- **Layout stability**: the Technician status section sits last (after
  Upgrade/Upgrade Rack), since its text length varies a lot and used to
  shift buttons above it on every refresh; `StatusLabel` itself has a fixed
  `custom_minimum_size.y` (40px) for the same reason.
- Press-and-hold (~0.45s, tracked via `button_down`/`button_up` timing) on a
  rack slot shows the per-station familiarity breakdown
  (`_part_familiarity_breakdown_text()`); a short tap pins the normal detail
  card.

**Contracts** (`resources/contract.gd`)
- `Contract`: `contract_id`, customer, tier, `line_items` (see multi-line-item
  bullet below), `deadline_seconds` (counts down live off a start timestamp),
  `payout`, `deadline_penalty_applied` (one-shot Reputation-hit guard).
- The six starting contracts (Local Hardware Co., Riverside Jewelers,
  Cascade Fluid Systems, Northline Pumps Inc., Summit Industrial Group,
  Meridian Aerospace) load with placeholder deadline/payout numbers matching
  Section 10's tiers (the doc gives no concrete figures). Meridian Aerospace
  is one-time; recurring-flagship behavior isn't modeled. **A fresh game
  starts with 0 active contracts** - all six load into `contract_offers`
  (see Contract Offers below), not immediately active.
- **Reputation** (`GameData.reputation`, shop-wide 0-100, starts at 0) is
  shown on the HUD and as a header on the Contracts/Offers tab. Moves in
  exactly three places: `credit_contract_shipment()` grants
  `REPUTATION_GAIN_ON_TIME_COMPLETE` on a fully-shipped, never-overdue
  contract; `_process_contracts()` applies
  `REPUTATION_LOSS_MISSED_DEADLINE` the instant a contract first goes
  overdue (guarded by `deadline_penalty_applied`); `Station._ship_part()`'s
  defective-discard branch applies `REPUTATION_LOSS_DEFECTIVE_SHIP`. All
  three also move `GameData.company_relationships`
  (`customer_name -> 0-5 stars`), shown per-contract.
- **Factory Level** is a two-step eligibility-then-purchase flow (design
  request, this session: "change how you get to the next factory level by
  paying a price" - reverses an earlier session's explicit "no currency to
  upgrade factory level" decision), same shape as `contract_offers`/
  `applicant_pool` elsewhere in this file. `GameData.factory_exp` +=
  `FACTORY_EXP_PER_CONTRACT_TIER` (10/25/60/150 by tier) on every contract
  shipment (regardless of on-time status) and never resets/spends, but
  crossing `FACTORY_LEVEL_EXP_THRESHOLD` only flips
  `can_level_up_factory()` true - it no longer auto-levels.
  `GameData.level_up_factory()` is the deliberate paid action (a "Level Up"
  button on the Factory overlay's Growth tab): spends
  `FACTORY_LEVEL_UP_PRICE` (400/800/1400/2200 for levels 2-5, gold-first-
  then-gems via `try_spend_with_gems()` - a hard affordability gate, disables
  the button), THEN raises `factory_level`, THEN pays every hired
  Technician/Engineer's current wage as a lump sum ("you have to pay your
  technicians salary when you level up") - gold-only, force-deducted, can
  push `currency` negative (see Wage economy below) rather than blocking the
  level-up itself. `FACTORY_LEVEL_PRINTER_CAP` populated through Level 5
  (`{1:2, 2:3, 3:4, 4:5, 5:6}`) - a placeholder ceiling, not a deliberate
  cap. **Leveling up also speeds up every process shop-wide** -
  `GameData.factory_process_speed_multiplier()` (+8%/level, so 1.32x at
  Level 5) divides every station's effective timer duration
  (`Station._effective_timer_duration()`), staffed or not - the one
  factory-level effect that isn't gated behind having a technician present.
  `factory_progress_changed` signal fires on every EXP award and on every
  successful level-up.
- **Gems** (`GameData.gems`, starts at 0) are a second, harder-to-get
  currency. The only source is `FACTORY_LEVEL_UP_GEM_REWARD` (5) gems per
  Factory Level gained - a milestone reward, not routine income. **Every
  real purchase goes through `GameData.try_spend_with_gems()`** (gold first,
  then just enough gems at `GEM_TO_CURRENCY_VALUE` = 50 gold/gem, rounded up
  to cover any shortfall, failing cleanly if gold+gems can't cover it) - all
  7 purchase call sites and all 8 "can afford" UI checks use this. Button
  cost text still shows plain gold price only (no gem-split breakdown shown
  yet). Shown on the HUD (`GemsLabel`), reactive via `gems_changed`.
- **Randomized contract generation** (`GameData.generate_contract()`):
  company and geometry/alloy roll from independent pools
  (`COMPANY_POOL`/`GEOMETRY_POOL`/`ALLOY_POOL`/`FAMILY_MIN_TIER`, keyed by
  tier, transcribed from Section 10). `_roll_contract_tier()` only rolls up
  to the highest Reputation-unlocked tier, weighted toward lower tiers even
  once higher ones unlock. `_maybe_pick_repeat_client()` gives a base 20%
  (up to `REPEAT_CLIENT_MAX_CHANCE` = 55%, scaling with average
  relationship) chance to reuse an existing customer instead of rolling a
  new one; a repeat client can also get a tier bump
  (`REPEAT_CLIENT_TIER_BUMP_CHANCE` = 30%), gated by a relationship-star
  threshold that eases from 5 stars down toward `MIN_REPEAT_CLIENT_TIER_BUMP_STARS`
  (3) as shop-wide Reputation climbs. Quantity/payout/deadline per tier are
  placeholders anchored to the six starting contracts' own numbers (±15%
  jitter). Generation triggers from `_process_contracts()` whenever
  `contract_offers` (not the active list - see below) drops below
  `MIN_ACTIVE_CONTRACTS` (4) and a 45s cooldown has elapsed.
  `REPUTATION_QUALITY_BONUS_MAX` (0.35) scales every generated contract's
  quantity/payout up continuously (not just at tier thresholds) as
  Reputation climbs from 0 to `REPUTATION_MAX`.
- **Offer rows scroll on touch**: `row.box` is `MOUSE_FILTER_PASS` (not STOP)
  so a drag starting on a row reaches `OffersScroll`, and a release only
  expands/collapses if the finger moved < `ROW_TAP_MOVE_THRESHOLD` (24px).
  Any future tap-to-expand row inside a ScrollContainer needs the same pair.
- **Drags starting on a button scroll the list** (`scenes/touch_scroll.gd`,
  `TouchScroll.watch(panel)`, called by `OverlayBase._ready()` and the
  Station Detail Menu): every `BaseButton` inside a `ScrollContainer` - now
  and added later, via `SceneTree.node_added` - gets `MOUSE_FILTER_PASS`, and
  so does every STOP control between it and the ScrollContainer (a row's
  `PanelContainer` box stops the press just as well as the button would).
  A plain tap still presses the button; a drag doesn't. Any new menu built
  on `OverlayBase` gets this automatically.
- **Contract Offers screen** (design doc Section 24.1/24.9). `GameData.contract_offers` is a
  pool of rolled-but-unaccepted contracts, separate from `contracts` (the
  active/working list); an offer's deadline doesn't start until
  `accept_contract_offer()` moves it over. Lives as an "Offers" tab on the
  Contracts overlay (`contracts_overlay.gd`), alongside a read-only "Active"
  tab. **Accordion-style**: tapping a collapsed offer row expands a detail
  card in place (not a separate View button/screen) - customer/payout/
  deadline/average familiarity on the row, and on expand: a risk badge
  computed from the *weakest* line item ("MASTERED - SAFE CONTRACT" /
  "MODERATE RISK" / "UNFAMILIAR - HIGH RISK"), a tag line (complexity/
  alloy/volume tier), a per-line-item list (placeholder geometry icon, name,
  quantity, that geometry's familiarity stars), a footer risk-summary line
  (just the two real tags - familiarity level, risk level; no unbacked
  "BONUS QUALITY"/"FIRST ARTICLE" text), an info line with time/payout/
  `+N Factory EXP`, and an Accept button. Only one detail card is ever open
  at a time.
- **Boxed rows** (design request, this session: "make each contract its own
  box... just to differentiate them a little," off a screenshot showing
  offer rows reading as one continuous block). Both `OfferRow` and the
  Active tab's `ContractRow` wrap their existing `HBoxContainer` in a new
  `PanelContainer` (`row.box` - the thing actually added to/removed from the
  list now, `row.container` stays the inner label layout) styled by
  `_row_box_style()`: a 2px border (lighter-weight than the outer overlay
  `Panel`'s own 4px chrome, sized for a small row repeated many times, not
  one big window) and a background one step lighter/darker than the
  surrounding panel per theme, not identical to it, so each box actually
  reads as a distinct card. Colors are a manual per-`ThemeChoice` literal
  (matching this file's existing `FAMILY_ICON_COLOR`/risk-badge precedent for
  small one-off widgets) rather than a Theme-resource lookup, so
  `_restyle_all_rows()` re-applies the style to every existing row on
  `ThemeManager.theme_changed` rather than relying on automatic propagation.
  Verified with real (non-headless) screenshots in both themes.
- **Multi-line-item contracts** - `Contract.line_items: Array[Contract.LineItem]`
  (each own geometry/alloy/quantity_required/quantity_shipped);
  `quantity_required`/`quantity_shipped`/`is_complete` are computed
  aggregates. `Part.line_item_index` records which line item a Part is
  being made for; `Station._try_create_part()` picks whichever line item
  still needs Parts via `Contract.first_open_line_item_index()`/
  `GameData.in_flight_counts_for_contract()` (shipped-or-in-flight, so it
  doesn't overproduce one line item while another needs work).
  `generate_contract()` rolls 1-4 line items depending on tier
  (`LINE_ITEM_COUNT_RANGE`), cross-family variety allowed, one alloy for the
  whole contract. Any code reading geometry/alloy for a Part goes through
  `GameData.geometry_name_for_part()`/`alloy_name_for_part()`.
- **Geometry roster**: Turbine family includes Blisks, Nozzle Guide Vanes,
  Compressor Vanes; a HotSection family covers Combustor Liners,
  Recuperators, Hot Section Casings. Both dropped from Flagship-only to
  Industrial-Accounts-eligible. No real per-geometry art yet, only a small
  tinted bordered-box + abbreviation placeholder icon
  (`GameData.family_for_geometry()`, `ContractsOverlay._make_geometry_icon()`).
- Not built from this same design pass (Section 24): performance-based
  reward bonuses, per-geometry-pair familiarity carryover (still a flat
  ~50% per family), Specialist/Engineer skill tiers, per-geometry (not just
  per-family) difficulty rating, "cored geometry" category, the
  familiarity-based reason a customer might not even offer a large
  unfamiliar contract (every offer still rolls regardless of player
  familiarity), and the "start a conversation" outreach action.

**Quality, Defects, and Geometry Familiarity** (Section 9)
- Defect-rolling stations: Printing, Shelling, Burnout, Pour, Grinding only.
  `GameData.STATION_BASE_DEFECT_RISK`/`STATION_DEFECT_CATEGORIES`, keyed by
  station id. Deshell/Abrasive Blast/Clean/UV Cure/Scan/Patching/Pour Cup
  Attach/Mold Prep/Ship never roll. Burnout rolls Warping/Shell Crack evenly;
  Pour rolls Porosity/Misrun evenly; Grinding rolls Inclusion (the only
  source of that category; no Specialist covers it - a known gap).
- **Familiarity is two systems now.** The original shop-wide system
  (`GameData.geometry_familiarity: geometry_name -> {station_id: stars}`,
  tracked only for `shelling, burnout, mold_prep, pour`) still fully governs
  **Burnout and Mold Prep**. A newer **per-worker** system
  (`Technician.geometry_familiarity`, `department_skill`) governs
  **Printing, Shelling, Pour, Patching, and Post Processing** (Deshell/
  Abrasive Blast/Ship/Grinding all map to `"post_process"` via
  `GameData.department_for_station()`/`STATION_DEPARTMENT`) - see the
  per-worker bullet under Technicians-equivalent below for the mechanics.
  `familiarity_multiplier_for_worker()` is what `Station._roll_defect_outcome()`
  calls for a mapped station (falls back to shop average when unstaffed);
  non-mapped stations still use the old `familiarity_multiplier_for()`
  unaffected. `average_familiarity_stars()`/`weakest_familiarity_stars()`
  now average/min across every hired Technician/Engineer's own
  familiarity (same function signatures, different underlying source) -
  falls back to 0 with nobody hired. The weakest-link number is what
  actually gates risk/Scrap eligibility; the average is the quick-glance
  number shown in part lists. A genuine press-and-hold on a rack slot shows
  the full per-station/per-worker breakdown.
- **Per-worker roles and skills**: `Technician.StaffRole { TECHNICIAN,
  ENGINEER }` on the same class (Engineers hired/waged/assigned exactly like
  Technicians, `role` only changes which departments they roll skill in) -
  `ENGINEER_DEPARTMENTS = ["printing","shelling","pour"]`,
  `TECHNICIAN_DEPARTMENTS = ["patching","post_process"]`. `SkillTier` and
  its cost/wage/defect-multiplier tables are shared and orthogonal to role.
  `department_skill` (rolled once at hire, one independent tier-scaled roll
  per department) is the baseline; `geometry_familiarity` starts empty and
  is what actually grows with hands-on experience
  (`gain_experience()`/`Station._gain_worker_experience()`, fired once per
  completed run at a mapped station, crediting `active_worker` specifically
  - a no-op if unstaffed or at a non-mapped station).
- **Defect roll**: `Station._roll_defect_outcome()` rolls
  `base_risk × familiarity_multiplier × technician_multiplier ×
  GameData.undiagnosed_risk_multiplier(station_id)` (unstaffed = 1.0
  technician multiplier). Defect tables are keyed by `"printing"`, so every
  lookup goes through `GameData.defect_table_key()` (maps `printing_N` ->
  `printing`) - before that existed printers never rolled a defect at all.
- **Nonconformance (NC) shelf** (design doc Section 28): **every flagged
  part leaves the line immediately** - `Station._on_run_finished()` /
  `_finish_shelling_run()` hand it to `GameData.quarantine_part()` and free
  the slot (`_take_active_part()`). `GameData.nc_shelf: Array[Part]` (saved
  as ids). The floor shelf is `NcShelf` (`scenes/nc_shelf.gd`, drawn
  placeholder rack, red box = undiagnosed, gold = diagnosed) at
  `main.NC_SHELF_POSITION` in VIM Bay's free left strip beside Pour; tapping
  it or the Attention item calls `main._focus_nc_shelf()` -> `NcOverlay`
  (`scenes/nc_overlay.gd`, panel slot, rows rebuilt on `nc_shelf_changed`,
  countdowns polled). While a part sits undiagnosed, its flagging station's
  risk is ×(1 + 0.5 per undiagnosed part), capped ×3 - this replaced the old
  grace-period escalation/contamination (removed; `Part.defect_elapsed`/
  grace fields remain only for save compatibility).
- **Engineers own contracts, not stations** (design doc 28.2):
  `Technician.assigned_contract_ids` (saved); one Engineer per contract via
  `GameData.assign_engineer_to_contract()`, set from a cycling button on
  each Contracts Active row. `assign_technician()` refuses Engineers, the
  Team roster hides their station checks, the Station Detail Menu's assign
  list skips them, and `load_from_dict()` takes any Engineer in an old save
  off every station (carried parts -> Awaiting Transfer). Technicians now
  roll skill in all five departments (`TECHNICIAN_DEPARTMENTS`;
  `backfill_department_skills()` fills old saves). Diagnosis runs in the
  background: `GameData._process_engineers()` (from `simulate()`) works each
  Engineer's oldest undiagnosed shelf part from their contracts for
  `diagnosis_seconds_for()` (10 game-min / tier speed 1-2x / seniority);
  finishing grants +1 familiarity (shop-wide at the flagging station, and
  the Engineer's own) and lifts that part's risk penalty. An Engineer with
  no diagnosis to do gains +1 familiarity on each of their active
  contracts' geometries per 60 game-min (`gain_general_experience()`).
- **Dispositions** (`GameData.scrap_nc_part()`/`rework_nc_part()`/
  `scan_nc_part()`): Scrap anytime (counted in `scrapped_part_count`; the
  scrap inventory is a later idea). Diagnosed + repairable
  (`rework_station_for()`: printer defects -> Patching, Shell Crack -> Mold
  Prep) -> Rework; diagnosed + not repairable -> Scan to learn (index set so
  the next stop is Scan). Both release the part to Awaiting Transfer as
  **learning-only** (`Part.learning_only`): it never rolls defects again,
  gives +1 familiarity at each tracked station it passes, isn't counted as
  in flight for its contract (so a replacement gets made), and is retired
  without credit at Ship, or at Scan for `scan_to_learn`
  (`retire_learning_part()`). Hiring a Specialist now marks matching shelf
  parts diagnosed instead of clearing them.
- **Legacy fix paths**: Mortar Patch / Redesign / Scrap-for-expertise below
  and the Station Detail Menu's DefectRow still exist but only ever see a
  defect on a part flagged before the NC shelf (old saves); new defects
  never stay at a station. Ship still discards any such legacy flagged part.
- **Fix path 1, Mortar Patch** (`GameData.mortar_patch_defect()`) - Shell
  Crack only, `MORTAR_PATCH_COST` (40g), clears the defect with no
  familiarity gain ("a patch, not a fix"). UI-scoped to only show at Mold
  Prep's Station Detail Menu, per design doc Section 21.4's "happens at this
  station" - a Shell-Crack part shown elsewhere only offers Redesign.
- **Fix path 2, Redesign** (`GameData.redesign_defect()`) - any category,
  `REDESIGN_COST` (150g), clears the defect and raises familiarity by
  `FAMILIARITY_GAIN_REDESIGN` (1 star) - the mechanic's actual familiarity
  source.
- **Fix path 3, Specialists** (`GameData.hire_specialist()`,
  `SpecialistType` SHELL/POUR/PATTERN) - one-time hire (no wage,
  `SPECIALIST_HIRE_COST` 650g), covering Shell Crack / Porosity+Misrun /
  Warping respectively (Inclusion has no specialist). Two effects: future
  rolls in covered categories get a 50% (`SPECIALIST_RISK_MULTIPLIER`)
  post-roll suppression chance (applied after category is chosen, since a
  station can roll between categories covered by different specialists);
  every currently-flagged Part in that specialist's categories is
  auto-resolved immediately at hire (`FAMILIARITY_GAIN_SPECIALIST` = 1
  star). Hired from the Staff overlay's Specialists tab (simple hire-once
  list, no roster/assignment UI).
- **The one scrap-before-shipping exception** (design doc Section 21.6) -
  the only decline option anywhere in the game.
  `GameData.can_scrap_for_expertise()` gates it on
  `weakest_familiarity_stars() >= SCRAP_FAMILIARITY_THRESHOLD_STARS` (4/5
  placeholder - no per-station weakness at all). Shown as a "Scrap" button
  alongside Mortar Patch/Redesign wherever a flagged Part appears.
  `GameData.scrap_part_for_expertise()` unregisters the Part from
  `active_parts`; `Station.remove_part()` removes it from wherever it
  physically sits.
- **Push Through** (`Station._resolve_push_through()`, design doc Section
  21.6) - available at the four `GameData.PUSH_THROUGH_ELIGIBLE_STATIONS`
  (shelling, burnout, mold_prep, pour; Printing excluded, no player decision
  point there). A checkbox in the Station Detail Menu arms the *next* part
  to start running there (`Station.push_through_armed`, one-shot). On
  completion: raises familiarity at that specific station
  (`FAMILIARITY_GAIN_PUSH_THROUGH` = 2 stars, bigger than Redesign's) before
  rolling the normal outcome odds (a no-op roll for Mold Prep, which has no
  risk entry - always succeeds there, just always grants free familiarity).
  A miss destroys the part outright (never flagged, never reaches Ship)
  rather than just flagging it.

**Print orders, quality and revert** (design doc 28.7; all numbers placeholders)
- **Production doesn't start by itself.** The player queues parts per
  contract line item from the Contracts Active tab (a Trial and a Production
  button per line item, disabled with the reason in the tooltip via
  `GameData.print_order_blocker()`), paying `part_cost()` per part (20% /
  50% of the contract's per-part payout). Orders live in
  `GameData.print_orders` (saved); printers - staffed (auto-queue) or not
  (Queue button) - pop them front to back in `Station._try_create_part()`.
  Orders for finished contracts are dropped. Attention nags "queue parts to
  make" for an active contract with nothing queued or in the line.
- **Queue multiplier** (AdVenture Capitalist style): a "Queue amount" toggle
  at the top of the Active tab cycles x1 / x5 / x10 / MAX
  (`ContractsOverlay.QUEUE_AMOUNTS`, not saved); each Trial/Production
  button shows how many one tap will really queue and the total price,
  via `GameData.queueable_count()` (capped by revert for trials, by
  `production_still_needed()` for production, and by gold+gems), and
  `queue_print_orders()` queues them.
- **Trial parts** (`Part.is_trial`) are poured in revert: queueing one uses 1
  `GameData.revert_stock` (starts at 10, saved). They roll defects normally,
  never count toward the contract (`Part.counts_toward_contract`), and at
  Ship are retired via `retire_trial_part()`: +1 revert back, +1 star (+2
  from a Senior/Master Engineer) at every familiarity-tracked station and
  for the contract's Engineer.
- **Production parts** are poured in virgin metal and unlock once
  `geometry_familiarity_percent()` >= 85 (mean of staff average and
  shop-wide tracked-station familiarity, as a share of 5 stars).
- **Quality %** (`Part.quality`, -1 until poured) is rolled at Pour (also on
  a pushed-through Pour) by `roll_casting_quality()`: 55 + 40 x familiarity
  share, +/-6. At Ship a production part under `SHIP_QUALITY_THRESHOLD` (90)
  is remelted to revert (`remelt_to_revert()`), never credited; -1 (poured
  before this existed) ships as before.
- **Engineer trial fixes**: finishing a diagnosis stores
  `pending_trial_fixes[contract_id]` (station, risk mult 0.6/0.5/0.4/0.3 by
  Engineer tier, 3 uses, saved); the next 3 trial orders queued on that
  contract carry it (`Part.fix_station_id`/`fix_risk_mult`), multiplying
  defect risk at the matching station (`defect_table_key()` comparison).

**Rail menus: Contracts / Board / Team / Factory** (Section 6,
consolidated per design doc 27.7)
- `MenuOverlay`, `DashboardOverlay`, `AwaitingTransferOverlay`,
  `OverviewOverlay` and `PrintersOverlay` are all deleted: Dashboard +
  Transfer became the Board, Overview + Printers became Factory (both
  below); Team is `StaffOverlay` under a new rail label.
- **`OverlayBase`** (`scenes/overlay_base.gd`) is the shared open/close/
  backdrop chrome (`opened()` signal, `toggle()`, `close()`, `_set_open()`,
  `set_panel_rect()`, `_click_in_progress()`) used by all 7 rail/gear
  overlays. Overlays have **no toggle button of their own** any more - the
  Hud creates one, assigns `rail_button` (whose pressed state `_set_open()`
  mirrors) and places `%Panel` into the shared slot. `StationDetailMenu`
  keeps its own near-identical copy since it opens via `open_for(station)`
  from a floor tap.
- **HUD** (`scenes/hud.gd`, class `Hud`, the `HUD` CanvasLayer in
  `main.tscn`, layer 2; design doc Section 27.2): a top resource bar
  (Gold/Gems/Reputation/Factory Lv, each with an icon, plus a Settings gear
  at its right end) and a right-edge rail of icon-over-label tiles, top to
  bottom Contracts/Board/Team/Factory (order set in
  `main.gd`'s `hud.bind()` call). Every menu opens into one panel slot left
  of the rail (max `PANEL_MAX_WIDTH` 400px). All positions come from
  `_layout()` (live viewport size + safe-area insets, re-run on
  `size_changed`) - nothing is a fixed offset in a `.tscn`. **Safe area:**
  under Xogot on the user's 16 Pro the OS-reported safe area came back
  empty (HUD edge to edge, Dynamic Island over the rail), so
  `_safe_insets()` treats any phone OS or touchscreen as handheld and, on a
  handheld view 2:1 or wider, floors the sides/bottom at `SIMULATED_INSETS`
  (40/0/40/14) with top 0 (landscape-locked). **Only the camera side is
  inset** (`_camera_side()`): the player's Settings choice
  (`ThemeManager.cutout_side`, Auto/Left/Right/Both, saved in
  `settings.cfg`), or in Auto a gravity-sensor reading
  (`_detect_camera_side()`; sensors enabled in `project.godot`) - Godot
  can't report the current landscape direction and iOS reports symmetric
  insets. Confirmed working on the user's iPhone (2026-10-03); until a
  confident reading arrives Auto insets both sides. The bar's ends keep
  `CORNER_INSET` (22px) from both edges on wide handhelds regardless (rounded
  corners, gear). `[Hud] ...` lines print at startup and on each detected
  side change - read them from a device run before changing this logic
  again. Desktop testing args: `--simulate-iphone-safe-area`,
  `--simulate-camera-left`/`--simulate-camera-right`.
- **Attention button** (design doc 27.6/27.7): bottom-left "!" tile in the
  Hud with a count; `Attention.collect()` (`scenes/attention.gd`) builds
  the list from `Station.attention_need()` (defect anywhere > ready to
  collect at an unstaffed station > start a print at an unstaffed printer)
  plus two shop-wide items (stranded Awaiting Transfer parts, no active
  contract). Each tap emits `Hud.attention_requested(item)`; `main.gd`
  pans/zooms to the station and spawns an `AttentionPulse` outline around
  `Station.get_sprite_rect()`, or opens Transfer/Contracts. Hidden while
  any menu is open. Test gotcha: a `--script` test that names `Attention`
  directly compiles it before autoloads exist and breaks it for the run -
  go through `main.hud._refresh_attention()`/`_attention_items` instead. Menu content must fit ~384px inner panel width: the
  Contracts Active rows were rebuilt as stacked lines (customer + time
  left / gold progress bar / shipped count + relationship) after four
  fixed columns (~434px) overflowed the slot. Layer 2 sits above every overlay's Backdrop, so rail taps switch
  menus directly instead of first closing the open one. Bar/rail reuse the
  current Theme's StyleBoxes with thinner borders/margins, overriding
  **every** Button state incl. `hover_pressed` and the `*_mirrored` ones
  (an undefined state falls back to Godot's roomier default and silently
  sets the button's minimum size). Rail tiles are a plain Button with a
  VBox(icon, Label) child, not `Button.icon` with
  `vertical_icon_alignment = TOP` - that mode reserves an extra text line
  (45px tiles, six overflowed a 270px screen). Stats are polled each frame
  (a save load doesn't emit their signals); gold turns red in wage debt.
  Desktop testing: run with `-- --simulate-iphone-safe-area` to fake a 16
  Pro's landscape insets (40/0/40/14 logical px). Icons are placeholders
  from `scenes/ui_icons.gd` (`UiIcons.get_icon(name)`, 16x16 ASCII grids
  drawn at runtime) until real icon art exists. **The six-tile rail is a
  stopgap** - consolidate once menus are redefined (Section 27.5).
- `main.gd` cross-wires
  exclusivity generically over a single `_overlays: Array` (every
  `OverlayBase` subclass + `StationDetailMenu`, duck-typed) rather than
  hand-written pairwise close calls.
- **Board** (`scenes/board_overlay.gd`, class `BoardOverlay`, rail tile
  "Board"): two tabs. **Stations** - every station grouped by room; each
  row is the station name as a flat button (emits `station_requested` ->
  `main._focus_station(station, true)`: close menus, pan/zoom, pulse, open
  its Station Detail Menu), ONE action button with the most urgent verb
  (`_primary_action()`: Fix > Collect > Queue > Upgrade; Fix opens the
  station since fixes live in its popup; Upgrade only when affordable), a
  two-line-floored status label, and an 8px state-colored bar.
  **Transfer** - the old Awaiting Transfer list unchanged: grouped by
  contract, "Defects only" filter, Part#/Familiarity/Defect/"Send to
  `<next station>`" per Part, defective first, full rebuild each refresh
  (guarded by `_click_in_progress()`); tab title shows the held count.
  `open_transfer_tab()` is the Attention button's target for stranded parts.
- **Contracts**: persistent per-contract rows (Customer / Progress+in-
  pipeline / Time-left), added/removed as contracts start/complete.
- "Type of part" isn't its own filter axis yet - contract grouping is the
  closest existing equivalent (no real part-type system beyond a contract's
  flavor-text geometry name).
- Not built: the design doc's alternate "assign from the receiving
  station's own Batch Picker" entry point - only Awaiting Transfer's route
  exists.

**Staff overlay - entry-point split/regroup** (`scenes/staff_overlay.gd` +
`.tscn`, extends `OverlayBase`, Section 6)
- Split from the old `Shop` overlay: Technicians + Specialists stayed
  together under one `Staff` HUD button (both hiring actions); Printers (an
  equipment purchase) split into its own overlay. `ShopOverlay` is deleted.
- **Technicians tab - rotating applicant pool.** `GameData.hire_technician()`
  is gone; `applicant_pool: Array[Technician]` mirrors the `contract_offers`
  pattern - `generate_applicant()` rolls name/role/tier/per-department
  skill, `hire_applicant()` moves one into the roster (gold-first-then-gems
  via `try_spend_with_gems()`), `refresh_applicant_pool()` is a **gems-only**
  full reroll (`APPLICANT_REFRESH_COST`, deliberately not gold-eligible - a
  full reroll specifically costs the harder currency). A passive
  `_refill_applicant_pool()` tops up any hired-away slot on a long cooldown
  (`APPLICANT_POOL_REFRESH_COOLDOWN_SECONDS`); it never discards a still-
  available candidate. `ApplicantRow` (persistent-widget pattern) shows
  name, role+tier ("Engineer, Technician Tier" phrasing - avoids the
  ambiguous "Technician Engineer" collision between `SkillTier.TECHNICIAN`
  and `StaffRole.TECHNICIAN`), one star rating per department, hire cost/
  wage, Hire button. Roster section (per-hired-technician row, assignment
  summary, physical location, carried-cargo summary, `RoutingStrategy`
  dropdown, one checkbox per assignable station) unchanged from the older
  bundled overlay.
- **Specialists tab**: one row per `SpecialistType`, showing covered
  categories and hire cost, Hire button -> `hire_specialist()`; once hired,
  shows "Hired" permanently (no assignment/un-hire, effect is passive and
  shopwide).
- Printers is no longer a tab here (see its own overlay below).
- **Refresh discipline** (this file, `MenuOverlay`, and `StationDetailMenu`
  all share the pattern): every list refresh path - the 0.25s poll and
  every reactive signal handler - checks `_click_in_progress()`
  (`Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)`) and skips itself if
  true, so a rebuild never tears down a Control the player is mid-click on.
  Dropdowns get an additional `_any_strategy_popup_open()` check (a
  different race - a still-open `OptionButton` popup, not an active click -
  since a rebuild landing while the popup is open orphans it). Sections that
  never change on their own (Hire, Specialists) only rebuild reactively
  (`currency_changed` / on open), not on the unconditional poll; only the
  Roster section (which changes on its own as technicians move) rebuilds on
  the poll/`technician_updated`, via a separate `_refresh_live_only()`.
- **Persistent-widget pattern** used throughout for anything on the
  unconditional poll - the roster (`_roster_rows: Dictionary`) and the
  Board's and Factory's rows are built once and updated in place
  (`CheckBox.set_pressed_no_signal()` for re-synced checkboxes, so it
  doesn't refire `toggled`), never freed/recreated, avoiding a visible
  "pop"/reflow every 250ms. New checkboxes/rows are still added lazily when
  a printer is bought or a technician is hired.
- Row layout in this overlay follows the project-wide **UI layout rules**
  section near the top of this file (width floors on HBox children, height
  floors on variable-length labels). `staff_overlay.gd`'s cost/strategy labels
  are the reference examples; `tools/audit_ui_layout.py` checks the scene side.
- **Wage economy, paid at Factory Level-up, not on a timer** (design request,
  this session: "have wages be an addition to the factory level" - replaces
  a same-session first pass that used a flat 90s real-time payday clock,
  since removed). Every hired technician/engineer draws their `wage`
  **regardless of whether they're currently assigned anywhere** - matching
  the existing comment on Specialist hiring ("no ongoing wage, unlike a
  station Technician") - but the payment moment is now
  `GameData.level_up_factory()` (see Factory Level above), not a standing
  clock. Payroll is gold-only and force-deducted
  (`currency -= total_wage_payroll()`), deliberately NOT routed through
  `try_spend_with_gems()` - an automatic cost triggered by leveling up
  shouldn't silently drain the harder-earned Gems currency the way the
  level-up's own price (a deliberate, hard-gated purchase) can. If gold
  can't cover it, `currency` goes negative (real debt) rather than blocking
  the level-up or firing anyone - nothing currently un-hires a technician.
  Debt already organically blocks every other purchase for free
  (`can_afford`/`can_afford_with_gems` both compare against `currency`, so a
  bigger shortfall just demands more Gems). `GameData.is_in_wage_debt()`
  (`currency < 0`) drives two visible cues: the Hud's gold label and the
  Staff overlay's `PayrollLabel` both turn red.
  `PayrollLabel` (`%PayrollLabel` in `staff_overlay.tscn`, between the
  Roster header and list) previews total standing payroll ("paid out
  whenever you level up the factory"); each roster row's header also shows
  that technician's own wage and tenure. A `payday(total_wages,
  went_into_debt)` signal fires on every level-up-triggered payment for
  StaffOverlay's live readout, separate from `currency_changed` (which also
  fires for every unrelated purchase/sale).
- **Technician seniority** (`Technician.factory_levels_stuck_with_you`,
  design request, this session: "technician salary also increases the more
  amount of factory levels they have stuck with you and also get skill
  level ups like faster processing time and skill experience for defect
  prevention") - a per-technician counter incremented once per technician on
  every successful `level_up_factory()` call, so someone hired after a
  level-up starts at 0 and only earns tenure from their own next level-up
  onward (never backfilled, never decremented - no fire/layoff mechanic
  exists). Three tenure-scaled effects, all first-pass placeholder curves:
  `wage` grows (+15%/tenure level, compounding is linear not exponential -
  the actual "salary increases" mechanic); `defect_multiplier` shrinks
  further below its skill-tier baseline (×0.95/tenure level, floored at
  0.25) - "skill experience for defect prevention," reusing the exact lever
  `Station._roll_defect_outcome()` already reads rather than a new stat; and
  a new `seniority_speed_multiplier` (+6%/tenure level, capped at 1.6x)
  stacks multiplicatively with the existing `productivity_multiplier`
  walking-penalty in `Station._effective_timer_duration()` - "faster
  processing time."

**Factory overlay** (`scenes/factory_overlay.gd` + `.tscn`, class
`FactoryOverlay`, rail tile "Factory"; design doc 27.3/27.7 - "see the
bottleneck, then buy the fix in the same place")
- **Stations tab**: per station, grouped by room (Ship excluded): average
  cycle time, Yield (only at defect-rolling stations), Busy % and parts/hr
  from `GameData.station_stat_summary()`, with the busiest station (above
  `BOTTLENECK_MIN_UTILIZATION` 25%) marked BOTTLENECK in red, and Tier /
  Rack upgrade buttons in an `HFlowContainer` on each row. Persistent rows.
- **Growth tab**: the old Printers screen - factory EXP, the **Level Up
  button** (the sole caller of `GameData.level_up_factory()`; text previews
  price + payroll, disabled until `can_level_up_factory()` and
  `can_afford_factory_level_up()` - payroll never gates it, it can push into
  debt, see Wage economy), process speed bonus, printers owned/cap and Buy
  Printer.
- **Stats collector** (`GameData.station_stats`/`stats_elapsed`):
  per station `completed`/`flagged`/`cycle_total`/`busy`, cumulative since
  the save began (no rolling window yet). `Station.simulate_step()` adds busy
  time; `Station._maybe_flag_defect(part, cycle_seconds)` - called once per
  completed run - records the run and whether it flagged a new defect.
  Advanced only through `simulate()`, so offline catch-up counts; saved and
  loaded (older saves start from zero). Verified: 10 simulated minutes on a
  real staffed save showed Shelling at 99.7% busy (the bottleneck CLAUDE.md
  already predicted) and Burnout at 57% yield; values round-trip exactly
  through the save JSON.

**Admin overlay** (`scenes/admin_overlay.gd` + `.tscn`, class
`AdminOverlay`) - play-testing controls, opened from a wrench in the Hud's
top bar that only exists when `OS.is_debug_build()`; opens into the shared
panel slot. Game speed slider (Pause/1/2/5/10/25/50x ->
`GameData.debug_sim_speed`, which `GameData._process()` multiplies into the
delta and steps in 0.25s slices like offline catch-up; a gold "10x"/"PAUSED"
badge shows in the top bar while not 1x), skip ahead 1 min/10 min/1 hr
(`debug_skip_ahead()`), Finish runs (`Station.debug_finish_run()`),
+1000 gold / +10 gems / +10 rep / EXP to next level, accept an offer, a
defect mode cycle (`GameData.debug_defect_mode`: normal / force the next
roll / off, read at the top of `Station._roll_defect_outcome()`), Save now,
and a two-tap Delete save (`SaveManager.delete_save_and_quit()` - disables
the on-close autosave first, since GameData is an autoload and a scene
reload would keep the old shop). Everything goes through `GameData.debug_*`
helpers or normal APIs so the HUD's signals still fire. Speed isn't saved.

**Settings overlay** (`scenes/settings_overlay.gd` + `.tscn`, extends
`OverlayBase`; `autoload/theme_manager.gd`, registered as the `ThemeManager`
autoload)
- First real occupant of design doc Section 19's planned Settings Menu -
  scoped to just one option (switch the UI's visual theme) rather than the
  full audio/text-size/haptics/etc. list Section 19 describes; establishes
  the entry point/pattern later settings would slot into. Opened from the
  gear button at the right end of the Hud's top bar, into the same panel
  slot as every rail menu.
- `ThemeManager` (autoload, not GameData) holds `current_theme: ThemeChoice`
  (`DARK`/`PARCHMENT`), persisted to its own `user://settings.cfg` - still
  deliberately separate from `SaveManager`'s `user://savegame.json` now that a
  real gameplay save exists: a display preference shouldn't be entangled with,
  or lost alongside, a gameplay save (and "reset save" shouldn't reset it).
  `set_theme()` swaps the theme, saves, and emits `theme_changed`.
- `resources/theme/ui_theme_parchment.tres` is the original warm-parchment
  palette from before the dark industrial reskin, recovered from git history
  (it's a pure color diff off `ui_theme.tres` - same StyleBox structure,
  shape language, and `m5x7` font) and kept alive as this second selectable
  Theme resource rather than having been deleted.
- **Applying the theme requires setting `.theme` directly on each overlay's
  own top-level Panel/Button, not just `get_tree().root.theme` - a real bug,
  caught only by a real (non-headless) rendered run, not by headless
  testing.** `project.godot`'s `gui/theme/custom` sets Godot's *project
  default theme* (`ThemeDB.get_project_theme()`) once at boot - a separate
  mechanism from `Window.theme`, with no runtime setter exposed to scripts
  in this Godot build. A Control only falls back to its nearest ancestor
  Window's `.theme` if it can reach that Window by walking actual Control
  ancestors (`get_parent_control()`); every overlay panel/button in this
  project is a direct child of a `CanvasLayer` (not a Control), which breaks
  that chain immediately - so reassigning `get_tree().root.theme` alone
  silently did nothing visually, confirmed by comparing a live Button's
  queried `get_theme_stylebox()` color against `Window.theme`'s own
  `resource_path` across a real switch (they never matched, even 10+ frames
  and a manual `queue_redraw()` later). `ThemeManager.apply_theme_to(control)`
  sets `.theme` directly on one Control, which correctly re-themes its whole
  Control-descendant subtree regardless of the CanvasLayer above it; every
  `OverlayBase` subclass, `StationDetailMenu` (its `panel` and `rack_panel`),
  and the Hud's bar and rail all call this once at `_ready()` and again
  on every `theme_changed`. `ThemeManager._apply_theme()` still also sets
  `get_tree().root.theme` as a harmless default for any future Control that
  genuinely is a Control-ancestor descendant of the root.
- Deliberately does NOT touch the ~16 hardcoded per-node/per-script gold
  accent colors (header labels, risk badges, etc., see the UI theme section
  above) - those stay gold under both themes. This is an accepted scope trim,
  not an oversight: gold/amber was already the accent color in the original
  parchment palette too (its own button hover/pressed colors), so it reads
  fine unswapped under either theme.
- Verified with a real (non-headless) windowed run, not just headless: a
  live Button's queried StyleBox color, and a saved screenshot of the whole
  running scene, both actually change from dark to parchment (and the HUD
  labels' text color, and the Settings panel's own text) on switch. Also
  verified headless: persistence across a simulated restart, a same-choice
  reselect being a no-op, and the overlay's own label/button text correctly
  reflecting `ThemeManager`.

**Shop floor** (`scenes/main.gd` + `scenes/main.tscn`)
- **Pinwheel room layout**: 5 rooms tiling a 1720x960 floor around a small
  central Pour Room island (280x280, centered at (860,480)) - `PRINT_ROOM`
  (top arm, 960x300), `SHELLING_ROOM` (right arm, 680x580), `FURNACE_ROOM`
  (bottom arm, 960x300), `POST_PROCESSING_ROOM` (left arm, 680x580). Every
  `STATION_POSITIONS` entry (except Pour, re-centered onto the shrunk
  island) is unchanged from an earlier equal-corners layout since every new
  room rect is a strict superset of the old one. Rooms are plain rectangles
  (not L-shapes), share real edge segments with their neighbors (not just
  corner points), and account for the full floor area with the 40px outer
  margin ring, with zero overlap between any two.
- **Not built yet**: corner-room expansion (buying more floor space, tied
  to the future Floor Editor's room-size-as-capacity rule) and a second
  "Air Melter" station in the small Pour Room island (design ideas only).
- **Whole-floor grid system, first step toward design doc Section 5.**
  `GRID_CELL_SIZE = 20.0` - every room/station position is expressed in
  whole grid-cell units (almost nothing needed to move to make this true,
  since prior placements were already round-numbered). Station footprints
  aren't yet an explicit multi-cell concept - that's the natural next step
  once a real Floor Editor is built.
- **The real floor tileset renders as one continuous whole-floor grid**
  (`main.gd._build_full_floor_tiles()`, `assets/sprites/floor_tiles/
  print_room_floor_tileset_packed.png`), not per-room - closes dead-space
  gaps in hallway cells between rooms. Every interior cell (room or
  hallway) uses a single plain tile (`TILE_MAIN` = tile 1); an earlier
  weighted-random variety mix was tried and removed as visually messy.
  **Zone boundaries are real bordered-tile art, not a flat tint or
  `ColorRect` outline** - `_zone_index_for_cell()` + `_edge_tile_for()`
  picks the accent-lined `TILE_EDGE`/`TILE_CORNER` tile (rotated per side/
  corner: BL=0°/TL=90°/TR=180°/BR=270°), tinted to that room's palette, for
  any cell on a room's own perimeter, plus the true outer floor boundary.
  Rendered as plain `Sprite2D` + `AtlasTexture` per cell (4128 cells total,
  not a real Godot `TileMap`/`TileMapLayer` - two earlier `TileMapLayer`
  attempts logically verified fine but never actually rendered on screen;
  the real bug was an unrelated draw-order issue, a full-room `ColorRect`
  "border" painting over the tiles underneath it - see
  `[[headless-gameplay-testing]]` for the general lesson: a cheap, obvious
  visual marker settles "is my code even running" far faster than swapping
  between plausible rewrites). Mipmaps + `NEAREST_WITH_MIPMAPS` filtering
  applied same as every other real sprite.
- Every station spawned from `GameData.stations`, hand-positioned per room
  (printers positioned by formula); `main.gd._wire_next_station_links()`
  links `next_station` per `PIPELINE_ORDER`, re-runnable after a printer
  purchase.
- `Camera2D` is pannable/zoomable (0.25x-2.0x), clamped to floor bounds.
  Higher `zoom` = more magnified/less area visible (`MIN_ZOOM` = zoomed all
  the way out, whole floor visible; `MAX_ZOOM` = zoomed in). Panning doesn't
  scale by zoom (a given drag moves the same world-space distance at any
  zoom - felt better than 1:1 cursor tracking, which made drag speed feel
  zoom-dependent). **Zoom anchors to the cursor/pinch position** (computes
  the world point under that screen position before/after the zoom change
  and shifts camera position to keep it pinned), not the screen center.
- **Real mobile pinch-to-zoom.** `InputEventMagnifyGesture` only fires from
  a desktop trackpad's native gesture recognizer, never a real touchscreen -
  fixed by tracking real per-finger state (`_touch_points: Dictionary` from
  `InputEventScreenTouch`/`InputEventScreenDrag`). One finger pans as
  before; two fingers compute the inter-finger distance ratio and feed it
  into the same `_zoom_camera()` zoom-to-point math, anchored to the
  finger midpoint. A second finger touching down clears any stale
  single-finger `_dragging` state first (Godot's mouse-motion emulation
  otherwise keeps tracking the first finger and fights the pinch).
- `_apply_sprite_zoom_scale()` shrinks station sprites toward
  `MAX_ZOOM_SPRITE_SCALE` (0.75x) approaching `MAX_ZOOM`;
  `get_click_rect()` reads the sprite's live scale so click targets shrink
  in step.
- HUD: see the Hud bullet under the "Rail menus" section below.

- Global class registration note: a new or renamed `class_name` doesn't
  take effect for other scripts' static typing until Godot's
  `global_script_class_cache.cfg` regenerates - a plain `--headless
  --quit-after N` run doesn't trigger that, `--headless --editor --quit`
  does.

**Art assets on disk**
- `print_room_floor_tileset.png` sliced into 25 individual tiles plus a
  packed atlas, now rendered across the entire floor as one continuous grid
  (see Shop floor above) - not split per-room, no dead hallway space.
  `resources/tilesets/print_room_floor_tileset.tres` (a hand-authored
  `TileSet`, never actually saved through Godot's editor) is unused, still
  on disk.

---

## Not built yet

**Blocking the MVP** (design doc Section 26.4, in dependency order):
- **UI visual/feel rework** - the user's main open complaint after playing on
  device. Direction is decided and recorded in **design doc Section 27**: top
  resource bar, right-edge icon rail, floating side panel, safe-area insets;
  Overview becomes factory statistics (yield/throughput - not tracked anywhere
  yet, needs a stats collector), Printers becomes an Upgrades screen,
  Dashboard absorbs manual part moves. **Built:** the HUD shell, the
  Attention button, and the four-tile rail (Contracts / Board / Team /
  Factory, with a stats collector behind Factory). **Next (27.7):** floor
  status badges (reuse `Station.attention_need()`). Option A's other ideas are tabled for a future
  update (27.7). Real icon art still to do. The menu panels' own contents are unchanged and
  still the user's main visual complaint.
- **Onboarding** - the founder handoff, the deliberately zero-risk first part,
  and the Traveler Card as the tutorial's spine (design doc Sections 1 and 6).
  No tutorial code of any kind exists.
- **Progressive unlock gating** - every overlay and system is reachable from the
  first second. The MVP rule is gate, don't delete.
- **A balance pass** - only became possible now that the timescale is real; no
  number in the game has been observed at a playable pace.
- **Minimum viable audio** - there is no audio at all, not one `AudioStream`.
- **The returning-player recap UI** - `SaveManager.offline_catchup_finished`
  fires with a real summary, but nothing displays it.

From the design doc, still pending:

- **Real geometry/alloy system** - flavor strings only, no real complexity
  ratings or mastery/familiarity carryover beyond the flat per-family ~50%
  (Section 10).
- **Alloy stock** as a purchasable, depletable resource (Section 11).
- **Recurring flagship contracts** - no contract repeats after shipping once
  (Section 8's "often recurring" isn't modeled).
- Reputation/relationship UI is limited to the Contracts/Offers tab's
  summary line and per-row column - no deeper browsing UI (Section 23's
  live-events/collectible-album retention layer also not built).
- Contract Offers exists, but the familiarity-based reason a customer might
  not even offer a large unfamiliar contract, and the "start a
  conversation" outreach action to unlock that, are not built (Section
  24.9) - every eligible offer rolls regardless of player familiarity.
- **Design doc Section 24** remaining gaps: performance-based reward
  bonuses (24.2), "cored geometry" category (24.4), per-geometry-pair
  familiarity carryover finer than the flat family-wide ~50% (24.5),
  Specialist/Engineer skill tiers (24.7), per-geometry (not per-family)
  difficulty rating (24.8), real per-geometry art (24.3's other half).
- **Real simultaneous multi-part batching** (Section 4/17) - built for
  Burnout only (furnace loads, above); every other batched station's queue
  rack still buffers Parts that process one at a time through the single
  active slot. Shelling's Tier 2+ parallel independent timers is a
  different, already-built answer to "more than one part progressing at
  once," not the same as a shared-batch-timer running several parts
  together on one clock. The batch size `SpinBox` sets `Station.batch_size`
  but nothing reads it except printer instances/Abrasive Blast/Shelling's
  parallel cap.
- **Station upgrade effects (Tier 2-5)** are mostly cosmetic (sprite swap
  only) except the three stations above with real tier-driven `batch_cap`
  changes. Rack capacity, by contrast, is a real tier-independent upgrade
  for every station.
- `FACTORY_LEVEL_PRINTER_CAP`/`FACTORY_LEVEL_EXP_THRESHOLD` only go to
  Level 5 (placeholder ceiling); nothing besides printer cap is gated by
  Factory Level yet (the Air Melter idea from Section 5 is earmarked for it
  but doesn't exist).
- **Patching's "quality scales with technician skill"** (Section 21.4) is
  implemented as the existing generic speed-scaling mechanism only (better
  technician = faster), not a new stochastic quality/failure roll - Patching
  isn't a defect-risk station so `defect_multiplier` has no obvious meaning
  there yet.
- A partially-busy parallel-Shelling station isn't prioritized correctly by
  a technician's route planning (`_priority_tier_for()` only checks
  `current_state == IDLE`) - correctness is fine once they arrive for any
  other reason, this is a route-planning quality gap only.
- **Real sprite art on the visual Queue Rack panel** - generic numbered
  slots for now; per-Part sprites are a planned follow-up once real
  geometry art exists.
- **Distinct technician art per tier** - all four tiers share
  `technician_L1.png`, static sprite, no walk-cycle frames.
- **The Floor Editor** (Section 5) - grid-based custom room/equipment
  placement, room-size-as-capacity, anchored equipment, hallway-distance-
  as-mechanic. The whole-floor grid system (`GRID_CELL_SIZE`, the tile
  grid) is a first step, but there's no player-facing editor, no explicit
  per-station cell footprint, and no room-size-as-capacity mechanic yet.
- **Mini games** as a timer-skip option (Section 2).
- **R&D / self-binding resin system** (Section 12).
- **Vertical stepper UI** showing a part's progress through the five phases
  (Section 15) - currently just per-station status text plus the Overview
  tab.
- **Shelling's real per-coat sub-loop** - one combined 160-minute timer
  rather than 8 individual coat cycles (Section 17).
- **Real room art** - the floor itself is now real tiled art (see Shop
  floor above), tinted per room; walls/props and room-specific (non-floor)
  decoration are still open, and only one tile sheet exists on disk, reused/
  tinted across every room.
- **Station silhouette variety** - 7 of 12 stations still render as the
  same generic tinted placeholder box (Clean/Printing/Burnout/Pour have
  real art, 5 of 12). Zoomed-out label *text* legibility is fully solved
  (screen-space floor labels); this is the remaining "what station is this
  by silhouette alone" half of design doc Section 16.
- **Settings Menu** (Section 19) - a real Settings overlay now exists with
  one option (UI theme, see Settings overlay above). Still not built: audio
  volume, station title visibility, text size, reduce motion, offline
  progress/notification toggles, haptics, reset save - all still design-only.
- **The Staff/Printers overlays' list rows** (Hire/Roster/Specialist/
  Printer) weren't part of the columnar/grouped/filtered redesign that hit
  the Overview/Awaiting Transfer/Contracts overlays and the Station Detail
  Menu's Insert list - each row is already a small number of clearly
  separated fields, so it hasn't been an obvious problem, but it's an
  unstyled gap if it turns out to need the same treatment.
- **"Type of part" as its own filter/category** - no real part-type system
  to filter by yet, only a contract's flavor-text geometry/alloy name;
  Awaiting Transfer's contract-grouping is the closest existing equivalent.
