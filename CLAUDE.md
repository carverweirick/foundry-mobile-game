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

## Currently built

**Project setup**
- `autoload/game_data.gd` registered as the `GameData` autoload singleton.
- `res://scenes/main.tscn` is the main scene.
- `project.godot`: renderer is Vulkan (the D3D12 backend silently broke mouse
  input on at least one dev machine); viewport is explicitly 480x270 with
  `stretch/aspect="keep"`.

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
  colliding with an already-accepted rect) rather than a fixed zoom cutoff -
  so a fully zoomed-out view still shows whichever labels fit. Station
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
  the Printers overlay. Each printer's own tier gates its batching
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
  if its `active_worker` already belongs to someone else, or if another
  technician assigned there (cargo or not) is physically closer right now -
  this is what keeps multiple technicians from all walking toward the same
  station without reason, while still letting a cargo-carrier always
  deliver and a closer non-carrier still visit for real work.
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
  Shelling) - used by the Overview tab and the Station Detail Menu's status
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
  flows through the shop; Printing is the sole pipeline entry point, parts
  auto-assign to `GameData.get_active_contracts()`'s open line items. Every
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
  tier for printer instances, Abrasive Blast, and Shelling's parallel-run
  cap (`Station._apply_tier_batch_effects()`); every other `BATCHED`
  station's `batch_cap` stays flat at Tier 1.
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
  `ShellingRun` rather than losing it. Known rough edge:
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
  (name/tier, productivity %, physical location, carried-parts summary), and
  an Upgrade button (`GameData.upgrade_cost_for_tier()`, spent via
  `try_spend_with_gems()`).
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
- While this popup, the Staff/Printers/Overview/Transfer/Contracts/Dashboard
  overlays are open, `main.gd` freezes background camera pan/zoom/click
  (`_unhandled_input` early-returns) so a scroll gesture inside a popup list
  doesn't fall through to the floor. All overlays close on outside-click
  (invisible `Backdrop`) and on Escape (`ui_cancel`, checked before the
  freeze-while-open guard, via each overlay's `close()` wrapper).
- Only one of the 6 overlays (+ this popup) is ever open at once - each
  emits an `opened()` signal, and `main.gd` cross-wires them all to close
  each other. Every overlay `Panel`'s `offset_top` is set clear of the
  fixed two-row HUD button strip; this file's own `CanvasLayer` is
  `layer = 2` (others default to `layer = 1`) so its panels draw above the
  persistent toggle buttons when needed.
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
  button on the Printers overlay, next to the EXP progress row): spends
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
  `base_risk × familiarity_multiplier × technician_multiplier` (unstaffed =
  1.0 technician multiplier). On a hit, `Part.flag_defect()` stamps
  category/station/grace-period (`GameData.grace_period_seconds_for()`).
  Visible as `" - DEFECT: <category> (<Xs to address>)"` on the floor status
  label and Station Detail Menu status line, and a shorter marker on rack/
  insert-list rows - the defect rides along with the Part wherever it goes.
- **Grace period and escalation**: `GameData._check_defect_escalations()`
  (every frame) sweeps all `active_parts`; on an unaddressed
  `defect_time_remaining` hitting zero, escalates once
  (`Part.defect_escalated` guard). Escalation point 1: `DEFECT_CONTAMINATION_CHANCE`
  (25% placeholder) roll against every other Part in the flagging station's
  own `queue_rack`/`current_part` (closest analog to "the batch" without
  real simultaneous batching) - a contaminated Part gets the same category
  and a fresh grace period. Escalation point 2: handled at Ship, not at
  escalation time - `Station._ship_part()` discards any still-flagged Part
  without crediting its contract, rather than the normal credit path.
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

**Overview / Awaiting Transfer / Contracts overlays - entry-point split**
(Section 6)
- Three separate always-visible HUD toggle buttons (Overview/Transfer/
  Contracts), each its own `Panel`, no tabs/bundling - split out of what was
  originally one `Menu` button's `TabContainer`. `MenuOverlay` itself is
  deleted (not deprecated-in-place).
- **`OverlayBase`** (`scenes/overlay_base.gd`) is the shared open/close/
  backdrop/toggle-button chrome (`opened()` signal, `close()`, `_set_open()`,
  `_click_in_progress()`) used by all 6 toggleable overlays (this trio +
  Staff, Printers, Dashboard). `StationDetailMenu` keeps its own near-
  identical copy since it opens via `open_for(station)` from a floor tap,
  not a persistent toggle button.
- HUD is two button rows (still 480x270): row 1 = Overview/Transfer/
  Contracts, row 2 = Staff/Printers/Dashboard. `main.gd` cross-wires
  exclusivity generically over a single `_overlays: Array` (all 6
  `OverlayBase` subclasses + `StationDetailMenu`, duck-typed) rather than
  hand-written pairwise close calls.
- **Overview**: every station grouped under a bold room-name subheader
  (`GameData.StationDef.room_name`, `all_real_station_ids()` already visits
  room-by-room). Persistent `Label`s reordered in place via `move_child()`
  each refresh, never destroyed/rebuilt.
- **Awaiting Transfer**: grouped by associated contract (subheader per
  contract with held Parts), a "Defects only" filter checkbox, real columns
  per Part (Part# / Familiarity / Defect / "Send to `<next station>`"
  button). Defective sorts first within each group. Full rebuild each
  refresh (guarded by `_click_in_progress()`) since this list churns often.
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
  Overview tab's rows are built once and updated in place
  (`CheckBox.set_pressed_no_signal()` for re-synced checkboxes, so it
  doesn't refire `toggled`), never freed/recreated, avoiding a visible
  "pop"/reflow every 250ms. New checkboxes/rows are still added lazily when
  a printer is bought or a technician is hired.
- Any label sitting next to a wider sibling control in an `HBoxContainer`
  (e.g. "Strategy:", "Batch size:") needs an explicit
  `custom_minimum_size.x`, or it collapses to a one-character-per-line
  vertical wrap - a recurring gotcha in this codebase, already fixed
  everywhere it's been hit but worth remembering if a new short label is
  added next to a wide control.
- Any label whose own text length varies a lot on refresh (staffing status,
  a toggled-visibility label) needs an explicit `custom_minimum_size.y`
  (~40px/2 lines), or it reflows every sibling row below it - same
  recurring-gotcha note as above, for height instead of width.
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
  (`currency < 0`) drives two visible cues: the HUD `CurrencyLabel`
  (`main.gd`) and the Staff overlay's `PayrollLabel` both turn red.
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

**Printers overlay - entry-point split** (`scenes/printers_overlay.gd` +
`.tscn`, extends `OverlayBase`, Section 6)
- Standalone HUD button (row 2). No tabs/roster - just
  `printer_cap()`/`owned_printer_count`/`factory_level` status text, a Buy
  button (`can_buy_printer()`/`printer_purchase_cost()`/`buy_printer()`),
  and a Factory EXP progress row (`"<exp>/<needed> EXP to Factory Level
  N+1"`, or the maxed-out message). Individual printer tiers/rack capacity
  are still managed per-instance from that printer's own Station Detail
  Menu. Refreshes off `currency_changed`/`factory_progress_changed` plus the
  0.25s poll, `_click_in_progress()`-guarded like every overlay.
- **LevelUpButton** (`%LevelUpButton`, this session) is the sole place
  `GameData.level_up_factory()` gets called - see Factory Level under
  Contracts above for the full price+payroll mechanics. Its own text
  previews both numbers before commit (`"Level Up to N (Xg price + Yg
  payroll)"`), disabled whenever `can_level_up_factory()` is false (not
  enough EXP yet) or `can_afford_factory_level_up()` is false (price alone
  unaffordable - payroll never gates this button, it can push into debt
  instead, see Wage economy under Staff overlay). `ProcessSpeedLabel`
  (`%ProcessSpeedLabel`) shows the live shop-wide speed bonus
  (`GameData.factory_process_speed_multiplier()`) as a flat percentage.

**Settings overlay** (`scenes/settings_overlay.gd` + `.tscn`, extends
`OverlayBase`; `autoload/theme_manager.gd`, registered as the `ThemeManager`
autoload)
- First real occupant of design doc Section 19's planned Settings Menu -
  scoped to just one option (switch the UI's visual theme) rather than the
  full audio/text-size/haptics/etc. list Section 19 describes; establishes
  the entry point/pattern later settings would slot into. Its own HUD toggle
  button sits in the bottom-left corner (below the currency stack, clear of
  the two main button rows) rather than taking a 7th slot in either row.
- `ThemeManager` (autoload, not GameData - the game has no save/load system
  of its own yet, and a UI preference shouldn't wait on one) holds
  `current_theme: ThemeChoice` (`DARK`/`PARCHMENT`), persisted to its own
  `user://settings.cfg` (independent of any future gameplay save file).
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
  and `main.gd`'s four HUD labels all call this once at `_ready()` and again
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
- HUD (`CanvasLayer`, top-left): `CurrencyLabel`, `GemsLabel`,
  `ReputationLabel`, `FactoryLevelLabel`, stacked, each reactive off its own
  signal (`currency_changed`/`gems_changed`/(reputation has no dedicated
  signal, polled)/`factory_progress_changed`).

**Dashboard overlay** (`scenes/dashboard_overlay.gd` + `.tscn`)
- An alternate, additive UI lens inspired by Game Dev Tycoon's layout -
  "Stat/progress-bar dashboard" + "menu-driven interaction over clicking the
  world" specifically, not a full clone (the multi-room floor, free camera,
  and physical technician movement are all untouched and still the primary
  way to play). One overlay among the other 5, same `_overlays` mutual-
  exclusivity wiring, its own HUD button at the end of row 2.
- **Stations tab**: every real station, grouped by room, each row with a
  big always-visible `ProgressBar` (tinted white/yellow/green for idle/
  running/ready, reusing `Station._apply_state_tint()`'s exact colors) plus
  inline Queue/Collect/Upgrade buttons calling the same public Station API
  every other overlay uses. Persistent-widget rows, same jump-prevention
  pattern as the Overview tab/Shop roster. Progress fraction is computed
  externally from `Station.timer_bar`'s public `value`/`max_value` (no new
  getter needed on `station.gd`), branching on `is_parallel_shelling()` to
  read the soonest-run bar in that mode.
- **Contracts tab**: same big-`ProgressBar` treatment for contract
  fulfillment (0 to `quantity_required`, filled to `quantity_shipped`)
  alongside customer/tier/time-left/in-pipeline text.
- **Explicitly out of scope for this first pass**: defect fix buttons, Push
  Through, batch size, the visual queue rack, Insert-from-Inventory - all
  still only reachable via the Station Detail Menu (tapping a station on
  the floor), which stays the fallback for anything Dashboard doesn't
  cover.
- Global class registration note: `class_name Dashboard` (or any new script
  `class_name`) doesn't take effect for other scripts' static typing until
  Godot's `global_script_class_cache.cfg` regenerates - a plain
  `--headless --quit-after N` run doesn't trigger that, `--headless
  --editor --quit` does.

**Art assets on disk**
- `print_room_floor_tileset.png` sliced into 25 individual tiles plus a
  packed atlas, now rendered across the entire floor as one continuous grid
  (see Shop floor above) - not split per-room, no dead hallway space.
  `resources/tilesets/print_room_floor_tileset.tres` (a hand-authored
  `TileSet`, never actually saved through Godot's editor) is unused, still
  on disk.

---

## Not built yet

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
- **Real simultaneous multi-part batching** (Section 4/17) - queue racks
  buffer several Parts, but they still process one at a time through the
  single active slot. Shelling's Tier 2+ parallel independent timers is a
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
